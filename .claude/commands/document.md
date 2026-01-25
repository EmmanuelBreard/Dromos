# Update Documentation Task

You are updating documentation after code changes.

## 1. Identify Changes
- Check git diff or recent commits for modified files
- Ignore claude setup and Tech Spec update (like new commands, skills, etc), focus on the code only
- Identify which features/modules were changed
- Note any new files, deleted files, or renamed files

## 2. Verify Current Implementation
**CRITICAL**: DO NOT trust existing documentation. Read the actual code.

For each changed file:
- Read the current implementation
- Understand actual behavior (not documented behavior)
- Note any discrepancies with existing docs

## 3. Update Relevant Documentation

- **CHANGELOG.md**: Add entry under `[Unreleased]` section
  - Use categories: Added, Changed, Fixed, Security, Removed, Database Migrations
  - Be concise, user-facing language
  - **IMPORTANT**: Everything goes in `[Unreleased]` until we tag a release
  - DO NOT create version sections (e.g., `[0.2.0]`) - these only exist after `git tag`
  - When a release is tagged, move `[Unreleased]` content to new version section

## 4. Versioning Workflow

**Unreleased** = Committed to `main` but not tagged/deployed

When deploying:
1. Move `[Unreleased]` content to new version section: `[X.Y.Z] - YYYY-MM-DD`
2. Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Create new empty `[Unreleased]` section

## 5. Documentation Style Rules

✅ **Concise** - Sacrifice grammar for brevity
✅ **Practical** - Examples over theory
✅ **Accurate** - Code verified, not assumed
✅ **Current** - Matches actual implementation

❌ No enterprise fluff
❌ No outdated information
❌ No assumptions without verification

## 6. Ask if Uncertain

If you're unsure about intent behind a change or user-facing impact, **ask the user** - don't guess.