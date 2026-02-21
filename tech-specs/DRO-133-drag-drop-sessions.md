# DRO-133: Drag & Drop to Reschedule/Reorder Sessions on Home

**Overall Progress:** `0%`

## TLDR
Add drag-and-drop to HomeView so users can reorder sessions within a day and move sessions to a different day. Persisted to Supabase. No constraints — trust the user.

## Critical Decisions
- **SwiftUI API:** Use `draggable` / `dropDestination` (iOS 16+, we target iOS 18) — cleaner than legacy `onDrag`/`onDrop`, no `NSItemProvider` boilerplate.
- **Transfer type:** Transfer session UUID as `String` via `Transferable`. Lightweight, avoids serializing full model.
- **Drop granularity:** Each day section is a `dropDestination`. Within-day reordering uses per-card drop targets to determine insertion index. Cross-day moves append to end of target day (user can then reorder).
- **Write path:** Client-side UPDATE on `plan_sessions` (first client write to this table). New RLS policy scoped to own sessions via join chain.
- **Optimistic UI:** Mutate local `trainingPlan` immediately, persist async. Rollback on failure with toast error.
- **Batch update:** Single RPC call to update all affected `order_in_day` values in one transaction (avoids N+1 updates).

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/011_plan_sessions_user_update.sql` | CREATE | RLS UPDATE policy + `reorder_sessions` RPC function |
| `Dromos/Core/Models/TrainingPlan.swift` | MODIFY | Make `day`, `orderInDay`, `weekId` mutable; add `Transferable` conformance to `PlanSession` |
| `Dromos/Core/Services/PlanService.swift` | MODIFY | Add `moveSession()` and `reorderSessions()` methods |
| `Dromos/Features/Home/HomeView.swift` | MODIFY | Add drag-and-drop modifiers to session cards and day sections |

## Context Doc Updates
- `schema.md` — new RLS UPDATE policy on `plan_sessions`, new `reorder_sessions` RPC function
- `architecture.md` — note drag-and-drop pattern in Home, first client write to `plan_sessions`

## Tasks

- [ ] 🟥 **Phase 1: Database — RLS policy + RPC function**
  - [ ] 🟥 Add UPDATE RLS policy on `plan_sessions` — allow authenticated users to update `day`, `order_in_day`, `week_id` on their own sessions (join via `plan_weeks` → `training_plans` where `user_id = auth.uid()`)
  - [ ] 🟥 Create `reorder_sessions` RPC function — accepts `session_updates JSONB[]` (array of `{id, day, week_id, order_in_day}`), updates all in a single transaction. Validates ownership via same join chain.
  - [ ] 🟥 Apply migration via Supabase MCP

- [ ] 🟥 **Phase 2: Model — Mutable fields + Transferable**
  - [ ] 🟥 In `TrainingPlan.swift`: change `PlanSession.day`, `PlanSession.orderInDay`, `PlanSession.weekId` from `let` to `var`
  - [ ] 🟥 Add `Transferable` conformance to `PlanSession` — transfer `id.uuidString` as `UTType.plainText`
  - [ ] 🟥 Add `TransferRepresentation` with `CodableRepresentation` or `ProxyRepresentation` using the UUID string

- [ ] 🟥 **Phase 3: Service — PlanService move/reorder methods**
  - [ ] 🟥 Add `moveSession(sessionId:toDay:toWeekId:newOrder:)` — optimistic local mutation of `trainingPlan`, then call `reorder_sessions` RPC with all affected sessions' new `order_in_day` values
  - [ ] 🟥 Handle rollback: snapshot state before mutation, restore on RPC failure, set `errorMessage`
  - [ ] 🟥 Recalculate `order_in_day` for source day (fill gaps) and target day (insert at position)

- [ ] 🟥 **Phase 4: UI — Drag and drop in HomeView**
  - [ ] 🟥 Add `.draggable(session.id.uuidString)` to each `SessionCardView` in `daySectionView`
  - [ ] 🟥 Wrap each day's session list in a `dropDestination(for: String.self)` — on drop, resolve session ID, call `planService.moveSession()` to move/reorder
  - [ ] 🟥 Add per-card drop targets for within-day insertion index (drop between cards = insert at that position)
  - [ ] 🟥 Visual feedback: highlight target day section when `isTargeted` is true (subtle background color change)
  - [ ] 🟥 Add drag preview: use session card as the drag preview via `.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12))`
