# Tech Spec Creation Stage

Based on our full exchange, you will produce a detailed tech spec. This happens in two phases:

## Phase 1: Context Gathering

Before writing anything, gather precise implementation details:

1. **Read context docs** — Read the relevant `.claude/context/` files (schema.md, architecture.md, ai-pipeline.md) to understand current state. No agent needed for this.

2. **Feature-specific exploration (if needed)** — If the feature touches areas not fully covered by the context docs, dispatch 1-2 Explore sub-agents using the Task tool (model: sonnet) to find feature-specific code. Example prompts:
   - "Find all SwiftUI views and services related to [feature area] in `Dromos/Dromos/Features/` and `Dromos/Dromos/Core/Services/`. Report file paths, key function signatures, and patterns."
   - "Find all edge function code and prompts related to [feature area] in `supabase/functions/`. Report file structure and data flow."

3. **Decide whether to dispatch agents** using this checklist:
   - Can you identify which files need changes? → If NO, dispatch agents.
   - Do you know the architectural pattern to follow? → If NO, dispatch agents.
   - Do you need exact function signatures or current implementation state? → If YES, dispatch agents.
   - Are there strategic/architectural decisions not yet resolved (e.g., where responsibility lives, validation strategy, UX behavior)? → If YES, **stop and ask the user** before writing the spec. Agents can't resolve these.
   - For trivial changes (1-2 files) or when context docs + discovery cover everything, skip agents entirely.

## Phase 2: Write the Tech Spec

Using the conversation context AND any research findings:
- Produce a markdown plan document.
- Store it in the linear task associated and locally in `/tech-specs` folder.
- Update the content of linear task if the initial description does not match the final feature description.
- Change the status of the linear task to `In Progress`.

### Requirements for the plan:

- Include clear, minimal, concise steps.
- Track the status of each step using these emojis:
  - 🟩 Done
  - 🟨 In Progress
  - 🟥 To Do
- Include dynamic tracking of overall progress percentage (at top).
- Do NOT add extra scope or unnecessary complexity beyond explicitly clarified details.
- Steps should be modular, elegant, minimal, and integrate seamlessly within the existing codebase.
- Every file path and function name in the spec must come from actual codebase findings. Do not invent paths.
- If research findings contradict what was discussed in discovery, flag it as a Critical Decision.

### Markdown Template:

# Feature Implementation Plan

**Overall Progress:** `0%`

## TLDR
Short summary of what we're building and why.

## Critical Decisions
Key architectural/implementation choices made during exploration:
- Decision 1: [choice] - [brief rationale]
- Decision 2: [choice] - [brief rationale]

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `path/to/file` | CREATE/MODIFY/DELETE | What changes |

## Context Doc Updates
Which `.claude/context/` files need updating after implementation (only list those that apply):
- `schema.md` — if new tables, columns, RLS policies, or indexes added
- `architecture.md` — if new files/folders created, new services, or new patterns introduced
- `ai-pipeline.md` — if prompts, pipeline steps, fixers, or eval scripts changed

## Open Questions (if any)
Strategic or product decisions that need clarification before implementation:
- [ ] Question 1
- [ ] Question 2

(Remove this section if there are no open questions.)

## Tasks:

- [ ] 🟥 **Step 1: [Name]**
  - [ ] 🟥 Subtask 1
  - [ ] 🟥 Subtask 2

- [ ] 🟥 **Step 2: [Name]**
  - [ ] 🟥 Subtask 1
  - [ ] 🟥 Subtask 2

...

Again, it's still not time to build yet. Just write the clear plan document. No extra complexity or extra scope beyond what we discussed.
