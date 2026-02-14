---
name: ship
description: Automate the full post-tech-spec pipeline — groom, execute, code review, fix, merge. Only invoke manually after a tech spec is ready.
argument-hint: <tech-spec-path>
disable-model-invocation: true
---

# Ship — Automated Post-Tech-Spec Pipeline

Automate the full pipeline from tech spec to merged code: groom → execute → code review → fix → merge.

## Input

Tech spec file path: $ARGUMENTS (e.g., `tech-specs/DRO-64-single-source-of-truth.md`)

## Critical Rules

- **NEVER assume.** If requirements are unclear, HALT and ask the user via AskUserQuestion.
- **NEVER skip QA.** When a QA halt is triggered, wait for explicit user confirmation.
- **NEVER carry tech debt.** ALL code review issues — even LOW severity — must be fixed before merging.
- **NEVER proceed past a halt point** without explicit user confirmation.

---

## Step 0: Setup

1. Read the tech spec at the provided path. **HALT if the file does not exist.**
2. Identify the parent Linear issue ID from the tech spec header (look for `DRO-` pattern). **HALT if not found — ask the user for the Linear issue ID.**
3. Create a feature branch from `main`:
   - Branch name: `feature/<parent-issue-id>-<short-description>` (e.g., `feature/DRO-64-single-source-of-truth`)
   - **HALT if branch already exists** — ask user whether to reuse or create a new one.
4. Report setup completion and proceed to grooming.

---

## Step 1: Groom

Read `.claude/skills/groom/SKILL.md` (or `.claude/commands/groom.md` if skill doesn't exist) and follow its instructions to split the tech spec into phases.

**Additional requirements for /ship context:**
- Every phase MUST have a "Blocked by" field. Use "None" for phases with no dependencies.
- Phases that can run in parallel must be explicitly identified (i.e., they share no blockers between each other).
- After defining phases, create Linear sub-issues under the parent issue immediately — **do not halt for confirmation**.
- Track which phases produce **user-visible frontend changes or e2e-testable flows** vs. backend-only/scaffolding. Tag frontend phases as `[QA-REQUIRED]`.

Proceed directly to execution.

---

## Step 2: Execute + Review Loop

### Build Dependency Graph

From the "Blocked by" fields, determine which phases can run in parallel:
- **Batch 1:** All phases with "Blocked by: None"
- **Batch 2:** All phases whose blockers are satisfied after Batch 1 completes
- Continue until all phases are scheduled

### For Each Batch

#### 2a. Execute (parallel sonnet sub-agents)

For each phase in the current batch, dispatch a **separate Task tool sub-agent (model: sonnet)** simultaneously:

Each agent prompt must include:
1. The Linear task ID for this phase
2. The full phase requirements (Goal, Tasks, Files, Verification)
3. Instruction: "Read `.claude/commands/execute.md` and follow its implementation requirements."
4. Instruction: "Create a PR against the feature branch `<branch-name>`, NOT against `main`."
5. Instruction: "Update Linear task status to 'In Review' when done."

Wait for all agents in the batch to complete before proceeding.

#### 2b. Code Review + Fix + Merge

For each PR created by the execute step:
1. Run the **full process** defined in `.claude/commands/code-review.md` — this includes review (3 parallel agents), fix loop (max 3 iterations), and post-merge checklist (context docs, prune, changelog, Linear status).
2. If `code-review.md` escalates after 3 failed fix iterations: **HALT and present issues to user.**

#### 2c. Next Batch

Once all phases in the current batch are merged, unlock the next batch and repeat from Step 2a.

For DB migration phases: after merging, verify the migration was applied correctly using Supabase MCP tools (`mcp__supabase__list_tables`, `mcp__supabase__execute_sql`). **HALT only if verification reveals unexpected schema state.**

---

## Step 3: Manual QA Checkpoint

**When to trigger QA halt:**
- After the **last phase** of the entire feature completes and is merged.
- Additionally, after any mid-pipeline phase tagged `[QA-REQUIRED]` (produces user-visible frontend changes or e2e-testable flows).

**Do NOT halt for QA** on backend-only, scaffolding, or non-user-visible phases.

**When halting for QA, present this exact format:**

```
## Manual QA — <Feature Name>

### What to test:
1. <Specific user action> → Expected: <specific observable result>
2. <Specific user action> → Expected: <specific observable result>

### Steps:
1. Build and run the app (Cmd+R in Xcode)
2. <Navigate to specific screen — name the tab/button/path>
3. <Perform specific action — tap X, enter Y, scroll to Z>
4. <Verify specific outcome — "you should see...", "the screen should show...">

### What to look for:
- <Specific visual/behavioral expectation>
- <Edge case to verify>
- <Regression to check — existing feature that should still work>

Reply: "QA pass" to continue, or describe what's wrong.
```

**Important:** QA instructions must be specific and actionable. NEVER write vague instructions like "verify it works" or "check the UI." Every instruction must say exactly what to tap, what to look for, and what the expected result is.

**If user reports QA issues:**

> **MANDATORY SEQUENCE — Do NOT skip any step:**
> Fix → Code Review → Merge → THEN re-halt for QA.
> Never present QA re-test to the user without completing code review first.

#### 3a. Fix

1. Dispatch a sonnet sub-agent to fix the reported issues on the feature branch. Include the user's exact feedback verbatim.
2. The agent must create a fix sub-PR against the feature branch.

#### 3b. Code Review + Fix + Merge (mandatory before re-test)

1. Run the **full process** defined in `.claude/commands/code-review.md` on the fix sub-PR — this includes review (3 parallel agents), fix loop (max 3 iterations), and post-merge checklist (context docs, prune, changelog).
2. If `code-review.md` escalates after 3 failed fix iterations: **HALT and present issues to user.**

#### 3c. QA Re-verification

1. **HALT again** for QA re-verification — present updated QA instructions using the same format above.
2. Repeat from Step 3a until user says "QA pass."

---

## Step 4: Final Summary

Once all phases are merged and QA passes:

1. **Verify context docs are up to date.** Check whether the feature introduced:
   - New/changed tables or columns → `schema.md` must reflect them
   - New files, folders, services, or patterns → `architecture.md` must reflect them
   - New/changed prompts, eval scripts, or pipeline logic → `ai-pipeline.md` must reflect them
   If any context doc is stale, update it now before proceeding.

2. Report completion:
```
## Ship Complete — <Feature Name>

### Phases completed:
- Phase 1: <Name> — PR #X
- Phase 2: <Name> — PR #Y
- ...

### Linear tasks closed:
- DRO-XX-1
- DRO-XX-2
- ...

### Context docs updated:
- schema.md: <yes/no — what changed>
- architecture.md: <yes/no — what changed>
- ai-pipeline.md: <yes/no — what changed>

### Open items:
- <Any follow-up tasks, if none say "None">
```

3. Update the tech spec markdown: set all task statuses to 🟩 and progress to 100%.
4. Update the parent Linear issue status to "Done".

---

## Halt Points Summary

| Halt Point | Trigger | What User Does |
|---|---|---|
| Manual QA | After `[QA-REQUIRED]` phases or final phase | "QA pass" or describe issues |
| Fix loop exhausted | 3 failed code review cycles on same phase | Decide how to proceed |
| Ambiguity | Requirements unclear at any point | Clarify via question |
| DB verification fail | Supabase MCP shows unexpected schema | Review and decide |
| Setup issues | Branch exists, no parent issue, invalid path | Provide guidance |

---

## Error Handling

- **Sub-agent fails or times out:** Retry once. If it fails again, HALT and report the failure to the user.
- **PR merge conflict:** HALT and ask the user how to resolve.
- **Linear API error:** Log the error, continue with execution, update Linear manually at end.
- **Build failure after merge:** HALT immediately — do not proceed to next batch.
