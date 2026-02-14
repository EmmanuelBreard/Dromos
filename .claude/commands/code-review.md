# Code Review Task

Perform comprehensive code review on the PRs opened linked to the Linear Task shared. Be thorough but concise.

## Step 1: Identify PR Changes

1. Get the PR diff using `gh pr diff <number>`.
2. Group changed files by type (Swift, TypeScript, SQL, config).
3. Read relevant `.claude/context/` docs (schema.md, architecture.md, ai-pipeline.md) to understand expected patterns and current state.

## Step 2: Parallel Review (use sub-agents)

Dispatch the following 3 sub-agents using the Task tool (model: opus). Each reviews ALL changed files but focuses on specific concerns. Run them **in parallel**.

**Important:** Each agent must read the FULL changed files (not just the diff) to understand surrounding context. Include the diff for reference, but instruct agents to read the actual files.

### Agent 1: "Correctness & Error Handling"
Prompt: "Review these changed files for: error handling (try-catch for async, centralized handlers, helpful messages), production readiness (no debug statements, no TODOs, no hardcoded secrets), and logical correctness (does the code do what it claims?).
Changed files: [LIST FROM STEP 1]
Full diff: [DIFF FROM STEP 1]
For each issue found, report: file path, line number, severity (CRITICAL/HIGH/MEDIUM/LOW), description, and suggested fix."

### Agent 2: "Type Safety & Code Quality"
Prompt: "Review these changed files for: TypeScript type safety (no `any` types, proper interfaces, no @ts-ignore), Swift type safety (proper optionals, Codable conformance), logging hygiene (no console.log, uses proper logger), and code clarity.
Changed files: [LIST FROM STEP 1]
Full diff: [DIFF FROM STEP 1]
For each issue found, report: file path, line number, severity (CRITICAL/HIGH/MEDIUM/LOW), description, and suggested fix."

### Agent 3: "Architecture & Security"
Prompt: "Review these changed files for: security (auth checked, inputs validated, RLS policies in place), architecture (follows existing patterns per architecture.md, code in correct directory), SwiftUI patterns (proper @State/@StateObject/@ObservedObject usage, no side effects in view body, correct .task/.onAppear lifecycle), and performance (no unnecessary re-renders, expensive calcs memoized, no N+1 queries).
Changed files: [LIST FROM STEP 1]
Full diff: [DIFF FROM STEP 1]
Read these context docs for expected patterns: `.claude/context/architecture.md` and `.claude/context/ai-pipeline.md`
For each issue found, report: file path, line number, severity (CRITICAL/HIGH/MEDIUM/LOW), description, and suggested fix."

## Step 3: Synthesize & Final Review

After all agents return:
1. **Deduplicate** findings — multiple agents may flag the same line. Keep the one with the better description.
2. **Resolve severity conflicts** — if two agents flag the same issue at different severities, take the higher one.
3. **Cross-cutting scan** — do a brief final pass of the diff for issues that span multiple files or concerns that individual agents may have missed.
4. **Check context doc updates** — grep for new table/function/file names from the diff in `.claude/context/` docs. If the PR adds new tables/columns (check schema.md), new files/services (check architecture.md), or new pipeline steps/fixers (check ai-pipeline.md) and the docs weren't updated, flag as MEDIUM severity.

## Review Concerns Reference
For reference, the complete checklist distributed across sub-agents:
- **Logging** - No console.log statements, uses proper logger with context
- **Error Handling** - Try-catch for async, centralized handlers, helpful messages
- **TypeScript** - No `any` types, proper interfaces, no @ts-ignore
- **Production Readiness** - No debug statements, no TODOs, no hardcoded secrets
- **SwiftUI Patterns** - Proper @State/@StateObject/@ObservedObject usage, no side effects in view body, correct .task/.onAppear lifecycle
- **Performance** - No unnecessary re-renders, expensive calcs memoized
- **Security** - Auth checked, inputs validated, RLS policies in place
- **Architecture** - Follows existing patterns, code in correct directory

## Output Format

### ✅ Looks Good
- [Item 1]
- [Item 2]

### ⚠️ Issues Found
- **[Severity]** [File:line] - [Issue description]
  - Fix: [Suggested fix]

### 📊 Summary
- Files reviewed: X
- Critical issues: X
- Warnings: X

## Severity Levels
- **CRITICAL** - Security, data loss, crashes
- **HIGH** - Bugs, performance issues, bad UX
- **MEDIUM** - Code quality, maintainability
- **LOW** - Style, minor improvements

## Issue Policy
**ALL issues are blockers.** Any issue found (regardless of severity) blocks the PR from merging.

## Fix Loop (max 3 iterations)

When issues are found:
1. List all issues clearly with suggested fixes.
2. Dispatch a sonnet sub-agent to fix the issues. Provide the exact issue list with file paths, line numbers, severity, and suggested fixes. **Include in the prompt:** "After fixing, verify that `.claude/context/` docs (schema.md, architecture.md, ai-pipeline.md) still match the final implementation. Update any that are now stale due to the rework."
3. Re-run the full review process (Step 1 → Step 2 → Step 3) on the updated PR.
4. Repeat up to **3 times**.
5. After 3 failed iterations: **HALT and escalate.** Present all unresolved issues to the user and ask how to proceed.

## End of Review

Once there are **zero issues** (no CRITICAL, no HIGH, no MEDIUM, no LOW):
1. Confirm that the main branch is up to date and no PR is pending/not merged (otherwise stop here and inform me).
2. **Verify context docs match final code.** If the PR went through fix iterations, check that `.claude/context/` docs (schema.md, architecture.md, ai-pipeline.md) reflect the *post-fix* state — not the original implementation. Update any that are stale.
3. Merge the PR.
4. Run `git remote prune origin` to clean up stale remote refs.
5. Update `CHANGELOG.md` under the `[Unreleased]` section:
   - Use categories: Added, Changed, Fixed, Security, Removed, Database Migrations
   - Concise, user-facing language (describe impact, not implementation)
   - For backend-only changes: describe the user-visible improvement (e.g., "Improved plan generation accuracy" not "Added fixDurationCaps post-processor")
   - Everything stays in `[Unreleased]` until a git tag
6. Change the linear task status to `Done`.
