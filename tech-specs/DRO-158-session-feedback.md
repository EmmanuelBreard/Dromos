# DRO-158: Session Feedback — AI Coaching Commentary on Completed Sessions

**Overall Progress:** `0%`

## TLDR

After Strava sync matches an activity to a plan session, iOS triggers a new `session-feedback` Edge Function that generates a short coaching paragraph comparing planned vs actual, with phase-aware context and recovery nutrition advice. Feedback is written to a new `feedback` column on `plan_sessions` and displayed as an expandable section on completed session cards in the Home tab.

## Critical Decisions

- **iOS triggers, not server** — Matching is client-side (`SessionMatcher.match()`). iOS detects new matches and calls the Edge Function with `(plan_session_id, strava_activity_id)`. Avoids duplicating matching logic server-side.
- **gpt-4o-mini** — Cheaper model, sufficient for structured short-paragraph generation. Consistent with existing OpenAI key in Supabase secrets.
- **Idempotent** — If `feedback` is already populated, iOS skips the call. Edge Function also checks as a safety net.
- **Sequential calls** — When multiple sessions match in one sync, iOS fires calls sequentially to avoid rate limits.
- **Weekly load in prompt** — All sessions for the week (with completion status) are sent to the LLM so it can make smart fueling/recovery observations.
- **RLS bypass for write** — Edge Function writes via `service_role` (same pattern as `chat-adjust`). iOS reads `feedback` via the existing `plan_sessions(*)` nested select — no RLS change needed (already SELECT-only for authenticated).

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/014_session_feedback.sql` | CREATE | Add `feedback` + `matched_activity_id` columns to `plan_sessions` |
| `ai/prompts/session-feedback-v0.txt` | CREATE | Coaching feedback prompt template |
| `supabase/functions/session-feedback/index.ts` | CREATE | Edge Function: auth → fetch context → OpenAI → write feedback |
| `Dromos/Dromos/Core/Models/TrainingPlan.swift` | MODIFY | Add `feedback: String?` and `matchedActivityId: UUID?` to `PlanSession` |
| `Dromos/Dromos/Core/Services/StravaService.swift` | MODIFY | Add `generateFeedback(sessionId:activityId:)` method |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Call feedback generation after `loadCompletionStatuses` |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Add "Coach feedback" disclosure section on completed cards |
| `scripts/sync-prompts.sh` | MODIFY | Add session-feedback prompt → edge function mapping |

## Context Doc Updates

- `schema.md` — Add `feedback` + `matched_activity_id` columns to `plan_sessions` table definition
- `architecture.md` — Add `session-feedback` to Edge Functions table

## Tasks

### Phase 1: Database Migration + Prompt

- [ ] **Step 1.1: Migration**
  - [ ] Create `supabase/migrations/014_session_feedback.sql`:
    ```sql
    -- UP: Add feedback columns to plan_sessions
    ALTER TABLE public.plan_sessions
      ADD COLUMN feedback TEXT,
      ADD COLUMN matched_activity_id UUID REFERENCES public.strava_activities(id);

    -- No RLS changes needed:
    -- iOS already has SELECT on plan_sessions (via join to training_plans).
    -- Edge Function writes via service_role (bypasses RLS).

    -- DOWN:
    -- ALTER TABLE public.plan_sessions
    --   DROP COLUMN feedback,
    --   DROP COLUMN matched_activity_id;
    ```
  - [ ] Apply migration to Supabase project

- [ ] **Step 1.2: Prompt file**
  - [ ] Create `ai/prompts/session-feedback-v0.txt`:
    ```
    You are a triathlon coach providing brief feedback on a completed training session.

    ## Athlete Profile
    - Race: {{race_objective}} on {{race_date}}
    - Experience: {{experience_years}} years
    - VMA: {{vma}} km/h | FTP: {{ftp}}W | CSS: {{css}}s/100m

    ## Session Context
    - Phase: {{phase}} (Week {{week_number}})
    - Recovery week: {{is_recovery}}

    ## This Week's Load
    {{week_sessions}}
    (completed / upcoming / missed)

    ## Planned Session (the one being reviewed)
    - Sport: {{sport}}
    - Type: {{type}}
    - Duration: {{planned_duration}} min

    ## Actual Execution (Strava)
    - Duration: {{moving_time_min}} min
    - Distance: {{distance_km}} km
    - Avg HR: {{avg_hr}} bpm
    - Avg Speed/Pace: {{formatted_pace}}
    - Avg Power: {{avg_watts}}W

    ## Instructions
    Write 2-3 sentences of coaching feedback comparing planned vs actual.
    Be encouraging but honest. Reference the training phase to contextualize
    whether deviations matter. When relevant, include brief recovery nutrition
    advice (carbs, protein if muscle repair is needed) based on session intensity,
    duration, and the week's overall load. If data is sparse, focus on duration
    and general encouragement. Do not use bullet points. Vary your opening tone.
    Return ONLY the feedback paragraph — no JSON, no headers, no markdown.
    ```
  - [ ] Run `scripts/sync-prompts.sh` to generate the TS import for the Edge Function

### Phase 2: Edge Function

- [ ] **Step 2.1: Create `supabase/functions/session-feedback/index.ts`**

  **Request:** `POST` with JWT auth + JSON body:
  ```json
  {
    "plan_session_id": "uuid",
    "strava_activity_id": "uuid"
  }
  ```

  **Flow:**
  1. CORS preflight + method guard (same pattern as `chat-adjust`)
  2. Validate JWT via `auth.getUser()` → extract `userId`
  3. Validate request body: both UUIDs required
  4. **Idempotency check**: `SELECT feedback FROM plan_sessions WHERE id = plan_session_id`. If not null → return `{ skipped: true }` (200)
  5. Fetch context in parallel (all via `service_role` client):
     - **Plan session**: `SELECT ps.*, pw.phase, pw.is_recovery, pw.week_number, pw.id as week_id FROM plan_sessions ps JOIN plan_weeks pw ON ps.week_id = pw.id WHERE ps.id = $1`
     - **Strava activity**: `SELECT * FROM strava_activities WHERE id = $1 AND user_id = $2`
     - **User profile**: `SELECT race_objective, race_date, experience_years, vma, css_seconds_per100m, ftp FROM users WHERE id = $1`
     - **Week sessions**: `SELECT ps.day, ps.sport, ps.type, ps.duration_minutes, ps.feedback FROM plan_sessions ps WHERE ps.week_id = $week_id ORDER BY ps.order_in_day` (to build weekly load context)
  6. Validate ownership: session belongs to user (via `training_plans.user_id` join) and activity belongs to user
  7. Build prompt — replace template placeholders:
     - Athlete profile fields
     - Phase/week context
     - Weekly load: format each session as `"Mon: Easy Swim 45 min [completed]"` / `"[upcoming]"` / `"[missed]"`. Determine status: if `feedback IS NOT NULL` → completed, if session date < today and no feedback → missed, else → upcoming
     - Planned session fields
     - Actual execution: format from `strava_activities` row. Convert `moving_time` to minutes, `distance` to km, `average_speed` to pace (min/km for run, km/h for bike, min/100m for swim). Use "N/A" for null fields.
  8. Call OpenAI:
     ```typescript
     const openai = new OpenAI({ apiKey: openaiApiKey });
     const completion = await openai.chat.completions.create({
       model: "gpt-4o-mini",
       temperature: 0.7,  // slight creativity for varied tone
       max_tokens: 256,   // short paragraph cap
       messages: [
         { role: "system", content: renderedPrompt },
       ],
     });
     ```
  9. Extract feedback text (trim whitespace)
  10. Write to DB:
      ```typescript
      await db.from("plan_sessions")
        .update({ feedback: feedbackText, matched_activity_id: stravaActivityId })
        .eq("id", planSessionId);
      ```
  11. Return `{ feedback: feedbackText }`

  **Error handling:**
  - Missing session/activity → 404
  - Ownership mismatch → 403
  - OpenAI failure → 502, feedback stays NULL (retry on next sync)
  - DB write failure → 500

  **Helper functions to create:**
  - `formatPace(sport: string, avgSpeed: number): string` — converts m/s to sport-appropriate pace
  - `formatWeekSessions(sessions: PlanSession[], today: Date): string` — builds weekly load text
  - `formatAthleteProfile(profile: UserProfile): string` — reuse pattern from `chat-adjust`

### Phase 3: iOS — Service + Trigger

- [ ] **Step 3.1: Update `PlanSession` model**
  - [ ] Add two optional properties to `PlanSession` in `TrainingPlan.swift`:
    ```swift
    struct PlanSession: Codable, Identifiable {
        // ... existing properties ...
        let feedback: String?
        let matchedActivityId: UUID?
    }
    ```
  - [ ] These are automatically decoded from the existing `plan_sessions(*)` nested select since the Supabase decoder handles snake_case → camelCase.

- [ ] **Step 3.2: Add feedback service method**
  - [ ] Add to `StravaService.swift` (since it's already responsible for Strava-related operations and available in `HomeView`):
    ```swift
    /// Calls the session-feedback Edge Function to generate AI coaching feedback.
    /// Returns the feedback text on success, nil on failure (silently — retry on next sync).
    func generateSessionFeedback(sessionId: UUID, activityId: UUID) async -> String? {
        do {
            let response = try await client.functions.invoke(
                "session-feedback",
                options: .init(body: [
                    "plan_session_id": sessionId.uuidString,
                    "strava_activity_id": activityId.uuidString,
                ])
            )
            let decoded = try JSONDecoder().decode(FeedbackResponse.self, from: response.data)
            return decoded.feedback
        } catch {
            print("Session feedback error: \(error)")
            return nil
        }
    }
    ```
  - [ ] Add response DTO in same file or in `StravaModels.swift`:
    ```swift
    struct FeedbackResponse: Codable {
        let feedback: String?
        let skipped: Bool?
    }
    ```

- [ ] **Step 3.3: Trigger feedback after matching**
  - [ ] In `HomeView.swift`, add a new method called after `loadCompletionStatuses`:
    ```swift
    /// For each newly completed session that lacks feedback, trigger AI feedback generation.
    /// Fires sequentially to avoid rate limits. Silently skips failures.
    private func generatePendingFeedback(plan: TrainingPlan) async {
        for (sessionId, status) in completionStatuses {
            guard case .completed(let activity) = status else { continue }

            // Find the PlanSession to check if feedback already exists
            let session = plan.planWeeks
                .flatMap(\.planSessions)
                .first { $0.id == sessionId }
            guard let session, session.feedback == nil else { continue }

            // Fire Edge Function — result is written to DB
            let feedback = await stravaService.generateSessionFeedback(
                sessionId: sessionId,
                activityId: activity.id  // need strava_activities.id (UUID), not stravaActivityId (Int64)
            )

            // If feedback was generated, update local model to avoid re-triggering
            if feedback != nil {
                await planService.fetchFullPlan(userId: plan.userId)
            }
        }
    }
    ```
  - [ ] **Important: `StravaActivity` needs its `id` (UUID PK) exposed.** Check if `StravaActivity` model currently includes the `id` field (the UUID primary key from `strava_activities` table, NOT `stravaActivityId` which is the Strava Int64 ID). If not, add it:
    ```swift
    struct StravaActivity: Codable, Identifiable {
        let id: UUID  // strava_activities.id (PK)
        // ... existing fields ...
    }
    ```
  - [ ] Hook into the Strava sync completion handler in `HomeView.swift`. In the `.onChange(of: stravaService.isSyncing)` block, after `loadCompletionStatuses`, call `generatePendingFeedback`:
    ```swift
    .onChange(of: stravaService.isSyncing) { oldValue, newValue in
        if oldValue && !newValue {
            Task {
                await loadCompletionStatuses(plan: plan)
                await generatePendingFeedback(plan: plan)
            }
        }
    }
    ```
  - [ ] Also trigger on first load (`.task`) so feedback is generated for sessions matched in previous syncs that didn't get feedback yet:
    ```swift
    .task {
        // ... existing code ...
        await loadCompletionStatuses(plan: plan)
        await generatePendingFeedback(plan: plan)
    }
    ```

### Phase 4: iOS — Session Card UI

- [ ] **Step 4.1: Add feedback disclosure to `SessionCardView`**
  - [ ] Add a new `@State` property for the disclosure:
    ```swift
    @State private var showFeedback = true  // default expanded
    ```
  - [ ] In the `.completed` branch of the body (after `StravaRouteMapView`, before the "Planned workout" disclosure), add:
    ```swift
    // Coach feedback disclosure — only when feedback exists
    if let feedback = session.feedback {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showFeedback.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                Text("Coach feedback")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .rotationEffect(.degrees(showFeedback ? 90 : 0))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)

        if showFeedback {
            Text(feedback)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSizeVerticalLayout()
        }
    }
    ```
  - [ ] **Placement**: Insert this block at line ~114 of `SessionCardView.swift`, after the `StravaRouteMapView` if-let block and before the "Planned workout" disclosure button.

### Phase 5: Deploy + Test

- [ ] **Step 5.1: Deploy Edge Function**
  - [ ] Run `scripts/deploy-functions.sh session-feedback` (or deploy individually with `supabase functions deploy session-feedback --no-verify-jwt`)
  - [ ] Verify secrets: `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` are already set from `chat-adjust`

- [ ] **Step 5.2: Manual test**
  - [ ] Trigger Strava sync in the app
  - [ ] Verify feedback appears on completed session cards
  - [ ] Verify feedback quality — check tone, length, phase-awareness, nutrition advice
  - [ ] Verify idempotency — second sync should not regenerate feedback
  - [ ] Verify failed sessions (no match) don't trigger feedback calls
  - [ ] Check Edge Function logs for errors

- [ ] **Step 5.3: Prompt tuning**
  - [ ] Review gpt-4o-mini output quality across different session types (easy/tempo/intervals, swim/bike/run)
  - [ ] Adjust prompt if needed (temperature, instructions, examples)

- [ ] **Step 5.4: Update context docs**
  - [ ] Update `schema.md` with new columns
  - [ ] Update `architecture.md` with new Edge Function entry

## Rollback Plan

- Drop columns: `ALTER TABLE plan_sessions DROP COLUMN feedback, DROP COLUMN matched_activity_id;`
- Delete Edge Function: `supabase functions delete session-feedback`
- Revert Swift changes (model + HomeView + SessionCardView)
- No data loss risk — `feedback` and `matched_activity_id` are additive columns with no existing data
