# Groom Tech Spec into Linear Sub-Issues

You are grooming a tech spec into implementation sub-issues for Linear.

## Input

Tech spec file path: $ARGUMENTS (e.g., `tech-specs/DRO-25-weekly-availability.md`)

## Your Task

1. **Read the tech spec** at the provided path
2. **Identify the parent Linear issue** from the tech spec header
3. **Split the work into logical development phases** following these principles:
   - Each phase should be **independently deployable** (no broken state)
   - Each phase should be **manually testable** at completion
   - Database migrations come first (foundation)
   - Data models before UI (dependencies flow downward)
   - Keep phases small: 1-3 hours of dev work max
   - Group tightly coupled changes together

4. **For each phase, create a Linear sub-issue** with:
   - Clear title: `[Parent-ID] Phase X: <descriptive name>`
   - Description containing:
     - **Goal:** 1-2 sentence summary
     - **Tasks:** Checkbox list of specific items from tech spec
     - **Files to modify:** List of files
     - **Testing:** How to verify this phase works
     - **Blocked by:** Previous phase (if any)

## Phase Splitting Guidelines

### Typical Phase Order:
1. **Database/Schema** - Migrations, new tables/columns
2. **Data Models** - Swift structs, Codable conformance
3. **Services/API** - Backend communication, business logic
4. **UI Components** - Reusable views, building blocks
5. **Feature Integration** - Wire everything together
6. **Polish & Edge Cases** - Error handling, loading states

### Each Phase Must:
- **Compile cleanly** - No broken builds between phases
- **Not break existing features** - Additive changes preferred
- **Be verifiable somehow** - Options include:
  - SQL migration runs successfully (check Supabase dashboard)
  - Code compiles with new models
  - SwiftUI Preview renders the component
  - Unit test passes
  - Full manual e2e test (ideal but not always possible)

Note: It's fine if a phase is just "scaffolding" that only becomes testable once the next phase connects it.

## Output Format

For each phase, output:

```
## Phase X: <Name>

**Goal:** <1-2 sentences>

**Tasks:**
- [ ] Task 1 (from tech spec)
- [ ] Task 2

**Files:**
- `path/to/file1.swift`
- `path/to/file2.swift`

**Verification:**
- How to confirm this phase is complete (e.g., "migration applied", "compiles", "preview works", "full flow testable")

**Blocked by:** Phase X-1 (or "None" for first phase)
```

## After Planning

Once you've defined all phases:

1. **Confirm with user** before creating Linear issues
2. **Use Linear MCP tools** to create sub-issues:
   - Use `mcp__linear__create_issue` for each phase
   - Set `parentId` to the main issue ID
   - Include phase number in title for ordering
   - Set appropriate labels (e.g., "backend", "frontend", "database")
3. **Report back** with links to created issues

## Example

For a tech spec with 6 steps, you might create:

- **Phase 1: Database Migration** (Step 1) - Testable: verify columns in Supabase dashboard
- **Phase 2: Data Models** (Step 2) - Testable: app compiles, unit tests pass
- **Phase 3: UI Component** (Step 3) - Testable: preview the component in isolation
- **Phase 4: Flow Integration** (Steps 4-5) - Testable: full user flow works
- **Phase 5: QA & Edge Cases** (Step 6) - Testable: all manual test cases pass

## Important Notes

- Don't over-split: 3-5 phases is ideal for most features
- Each phase should have a clear "definition of done"
- Include rollback considerations for database phases
- Flag any risks or dependencies in the phase description
