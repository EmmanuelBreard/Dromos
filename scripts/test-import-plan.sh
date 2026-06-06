#!/bin/bash
# Smoke tests for the import-plan Edge Function.
#
# Usage:
#   SUPABASE_URL=https://cumbrfnguykvxhvdelru.supabase.co \
#   ALLOWED_JWT=<ebreard4@gmail.com JWT> \
#   SERVICE_ROLE_JWT=<JWT for a non-allowlisted user> \
#   ./scripts/test-import-plan.sh
#
# ALLOWED_JWT       — a valid JWT for ebreard4@gmail.com (from Supabase Auth)
# SERVICE_ROLE_JWT  — a JWT for a different (non-allowlisted) user; used to
#                     test the 403 path. If not set, Test 5b is skipped.
#
# REPLACE_EXISTING  — set to "true" to run the happy-path replace test (Test 2).
#                     WARNING: this overwrites the real ebreard4 plan.
#                     Restore from plan_snapshots after running.
#
# Dependencies: curl, jq (replaces python3 for JSON construction)

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
# Use jq to add replace:true — no python3 dependency
HAPPY_PAYLOAD=$(echo "$MINIMAL_PAYLOAD" | jq '. + {replace: true}')
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

# ── Test 5a: No auth header → 401 ────────────────────────────────────────────
# This and 5b are deliberately split: missing header = 401 (not authenticated),
# wrong user = 403 (authenticated but not allowlisted).
echo ""
echo "── Test 5a: No auth header → expect 401 ──"
RESP=$(curl -s -o /tmp/import_plan_t5a.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Content-Type: application/json" \
  -d '{}')
check "no-auth-header" "401" "$RESP" "$(cat /tmp/import_plan_t5a.json)"
echo "   Body: $(cat /tmp/import_plan_t5a.json)"

# ── Test 5b: Auth as non-allowlisted user → 403 ───────────────────────────────
echo ""
echo "── Test 5b: Non-allowlisted user → expect 403 ──"
if [ -n "$SERVICE_ROLE_JWT" ]; then
  RESP=$(curl -s -o /tmp/import_plan_t5b.json -w "%{http_code}" \
    -X POST "$FN_URL" \
    -H "Authorization: Bearer $SERVICE_ROLE_JWT" \
    -H "Content-Type: application/json" \
    -d "$MINIMAL_PAYLOAD")
  check "non-allowlisted-user" "403" "$RESP" "$(cat /tmp/import_plan_t5b.json)"
  echo "   Body: $(cat /tmp/import_plan_t5b.json)"
else
  echo "   SKIPPED — SERVICE_ROLE_JWT is not set."
  echo "   To test the 403 path, export SERVICE_ROLE_JWT with a JWT for a non-ebreard4 account."
fi

# ── Test 6: Invalid sport value → 400 ────────────────────────────────────────
echo ""
echo "── Test 6: Invalid sport value → expect 400 ──"
BAD_SPORT_PAYLOAD=$(cat <<EOF
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
          "sport": "yoga",
          "type": "Easy",
          "template_id": "SWIM_Tempo_01",
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
RESP=$(curl -s -o /tmp/import_plan_t6.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -d "$BAD_SPORT_PAYLOAD")
check "invalid-sport" "400" "$RESP" "$(cat /tmp/import_plan_t6.json)"
echo "   Body: $(cat /tmp/import_plan_t6.json)"

# ── Test 7: Oversized Content-Length → 413 ────────────────────────────────────
echo ""
echo "── Test 7: Oversized Content-Length header → expect 413 ──"
# Send a 1-byte body but lie about Content-Length (600 KB) to exercise the
# header-based guard without actually uploading a large payload.
RESP=$(curl -s -o /tmp/import_plan_t7.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -H "Content-Length: 614400" \
  -d '{}')
check "oversized-payload" "413" "$RESP" "$(cat /tmp/import_plan_t7.json)"
echo "   Body: $(cat /tmp/import_plan_t7.json)"

# ── Test 8: Bad profile_updates → 400 ────────────────────────────────────────
echo ""
echo "── Test 8: Invalid profile_updates.max_hr → expect 400 ──"
BAD_PROFILE_PAYLOAD=$(echo "$MINIMAL_PAYLOAD" | jq '. + {replace: true, profile_updates: {max_hr: 50}}')
RESP=$(curl -s -o /tmp/import_plan_t8.json -w "%{http_code}" \
  -X POST "$FN_URL" \
  -H "Authorization: Bearer $ALLOWED_JWT" \
  -H "Content-Type: application/json" \
  -d "$BAD_PROFILE_PAYLOAD")
check "invalid-profile-updates-max-hr" "400" "$RESP" "$(cat /tmp/import_plan_t8.json)"
echo "   Body: $(cat /tmp/import_plan_t8.json)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "All tests passed."
