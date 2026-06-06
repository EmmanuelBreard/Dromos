#!/bin/bash
# Smoke tests for the import-plan Edge Function.
#
# Usage:
#   SUPABASE_URL=https://cumbrfnguykvxhvdelru.supabase.co \
#   ALLOWED_JWT=<ebreard4@gmail.com JWT> \
#   SERVICE_ROLE_JWT=<service-role JWT for non-allowlisted test> \
#   ./scripts/test-import-plan.sh
#
# ALLOWED_JWT   — a valid JWT for ebreard4@gmail.com (from Supabase Auth)
# SERVICE_ROLE_JWT — a JWT for a different user (or the service-role anonymous bearer
#                    for a non-allowlisted account), used to test the 403 path.
#
# Note: The happy-path test (Test 1) does NOT run against the real ebreard4 plan.
#       It uses the test user flow: it will 409 if ebreard4 already has a plan and
#       `replace` is not set — which is the expected behavior (Test 4 covers this).
#       To run the full happy-path (with replace), export REPLACE_EXISTING=true.

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:?SUPABASE_URL is required}"
ALLOWED_JWT="${ALLOWED_JWT:?ALLOWED_JWT is required (JWT for ebreard4@gmail.com)}"
SERVICE_ROLE_JWT="${SERVICE_ROLE_JWT:-}"
REPLACE_EXISTING="${REPLACE_EXISTING:-false}"
FN_URL="${SUPABASE_URL}/functions/v1/import-plan"

PASS=0
FAIL=0

check() {
  local test_name="$1"
  local expected_status="$2"
  local actual_status="$3"
  local body="$4"

  if [ "$actual_status" = "$expected_status" ]; then
    echo "✓  PASS [$test_name] → HTTP $actual_status"
    PASS=$((PASS + 1))
  else
    echo "✗  FAIL [$test_name] → expected HTTP $expected_status, got HTTP $actual_status"
    echo "   Body: $body"
    FAIL=$((FAIL + 1))
  fi
}

# ── Minimal 1-week payload (swim + bike + run; real template IDs) ─────────────
WEEK_START="2026-07-07"
PLAN_RACE_DATE="2026-09-13"

MINIMAL_PAYLOAD=$(cat <<EOF
{
  "plan": {
    "race_objective": "Olympic",
    "race_date": "$PLAN_RACE_DATE",
    "start_date": "$WEEK_START",
    "total_weeks": 1
  },
  "weeks": [
    {
      "week_number": 1,
      "phase": "Base",
      "is_recovery": false,
      "rest_days": ["Thursday"],
      "start_date": "$WEEK_START",
      "sessions": [
        {
          "day": "Monday",
          "sport": "swim",
          "type": "Tempo",
          "template_id": "SWIM_Tempo_01",
          "duration_minutes": 33,
          "is_brick": false,
          "order_in_day": 0
        },
        {
          "day": "Wednesday",
          "sport": "bike",
          "type": "Easy",
          "template_id": "BIKE_Tempo_01",
          "duration_minutes": 60,
          "is_brick": false,
          "order_in_day": 0
        },
        {
          "day": "Saturday",
          "sport": "run",
          "type": "Easy",
          "template_id": "RUN_Tempo_01",
          "duration_minutes": 45,
          "is_brick": false,
          "order_in_day": 0
        }
      ]
    }
  ]
}
EOF
)

# ── Test 1: No replace flag when plan exists → 409 ───────────────────────────
echo ""
echo "── Test 1: Replace flag missing when plan exists → expect 409 ──"
RESP=$(curl -s -o /tmp/import_plan_t1.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -d "$MINIMAL_PAYLOAD")
check "replace-flag-missing-when-plan-exists" "409" "$RESP" "$(cat /tmp/import_plan_t1.json)"
echo "   Note: 409 expected because ebreard4 already has an active plan and replace=true is not set."
echo "         If user has NO plan, expect 200 (first import)."

# ── Test 2: Happy path — replace: true ───────────────────────────────────────
echo ""
echo "── Test 2: Happy path (replace: true, 1 week 3 sessions) → expect 200 ──"
HAPPY_PAYLOAD=$(echo "$MINIMAL_PAYLOAD" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['replace'] = True
print(json.dumps(d))
")
if [ "$REPLACE_EXISTING" = "true" ]; then
  RESP=$(curl -s -o /tmp/import_plan_t2.json -w "%{http_code}" \
    -X POST "$FN_URL" \
    -H "Authorization: Bearer $ALLOWED_JWT" \
    -H "Content-Type: application/json" \
    -d "$HAPPY_PAYLOAD")
  check "happy-path-replace" "200" "$RESP" "$(cat /tmp/import_plan_t2.json)"
  echo "   Response: $(cat /tmp/import_plan_t2.json)"
  echo ""
  echo "   IMPORTANT: Real ebreard4 plan was replaced. Restore the Nimes plan from plan_snapshots!"
  echo "   Run: SELECT id, created_at FROM plan_snapshots ORDER BY created_at DESC LIMIT 3;"
else
  echo "   SKIPPED — set REPLACE_EXISTING=true to run (will overwrite real plan)."
  echo "   WARNING: restore the Nimes snapshot manually after running."
fi

# ── Test 3: Bad template_id → 400 with list of unknown IDs ───────────────────
echo ""
echo "── Test 3: Bad template_id → expect 400 ──"
BAD_TEMPLATE_PAYLOAD=$(cat <<EOF
{
  "plan": {
    "race_objective": "Olympic",
    "race_date": "$PLAN_RACE_DATE",
    "start_date": "$WEEK_START",
    "total_weeks": 1
  },
  "replace": true,
  "weeks": [
    {
      "week_number": 1,
      "phase": "Base",
      "is_recovery": false,
      "rest_days": [],
      "start_date": "$WEEK_START",
      "sessions": [
        {
          "day": "Monday",
          "sport": "bike",
          "type": "Tempo",
          "template_id": "BIKE_DOES_NOT_EXIST",
          "duration_minutes": 60,
          "is_brick": false,
          "order_in_day": 0
        }
      ]
    }
  ]
}
EOF
)
RESP=$(curl -s -o /tmp/import_plan_t3.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -d "$BAD_TEMPLATE_PAYLOAD")
check "bad-template-id" "400" "$RESP" "$(cat /tmp/import_plan_t3.json)"
echo "   Body: $(cat /tmp/import_plan_t3.json)"

# ── Test 4: Mismatched total_weeks vs weeks.length → 400 ─────────────────────
echo ""
echo "── Test 4: Mismatched weeks.length vs total_weeks → expect 400 ──"
MISMATCH_PAYLOAD=$(cat <<EOF
{
  "plan": {
    "race_objective": "Olympic",
    "race_date": "$PLAN_RACE_DATE",
    "start_date": "$WEEK_START",
    "total_weeks": 2
  },
  "replace": true,
  "weeks": [
    {
      "week_number": 1,
      "phase": "Base",
      "is_recovery": false,
      "rest_days": [],
      "start_date": "$WEEK_START",
      "sessions": []
    }
  ]
}
EOF
)
RESP=$(curl -s -o /tmp/import_plan_t4.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -d "$MISMATCH_PAYLOAD")
check "mismatch-total-weeks" "400" "$RESP" "$(cat /tmp/import_plan_t4.json)"
echo "   Body: $(cat /tmp/import_plan_t4.json)"

# ── Test 5: Non-allowlisted user → 403 ───────────────────────────────────────
echo ""
echo "── Test 5: Non-allowlisted user → expect 403 ──"
if [ -n "$SERVICE_ROLE_JWT" ]; then
  RESP=$(curl -s -o /tmp/import_plan_t5.json -w "%{http_code}" \
    -X POST "$FN_URL" \
    -H "Authorization: Bearer $SERVICE_ROLE_JWT" \
    -H "Content-Type: application/json" \
    -d '{"plan":{"race_objective":"Olympic","race_date":"2026-09-13","start_date":"2026-07-07","total_weeks":1},"weeks":[]}')
  check "non-allowlisted-user" "403" "$RESP" "$(cat /tmp/import_plan_t5.json)"
  echo "   Body: $(cat /tmp/import_plan_t5.json)"
else
  # No-auth request should return 401 (missing JWT)
  RESP=$(curl -s -o /tmp/import_plan_t5.json -w "%{http_code}" \
    -X POST "$FN_URL" \
    -H "Content-Type: application/json" \
    -d '{}')
  check "no-auth-header" "401" "$RESP" "$(cat /tmp/import_plan_t5.json)"
  echo "   Note: SERVICE_ROLE_JWT not set — tested 401 (no auth) instead of 403 (wrong user)."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "All tests passed."
