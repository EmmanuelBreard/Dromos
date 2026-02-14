# Release Documentation Task

You are managing release versioning. Routine CHANGELOG updates happen during code review (at merge time). This command is for tagging releases.

## Versioning Workflow

**Unreleased** = Committed to `main` but not tagged/deployed

When deploying:
1. Move `[Unreleased]` content to new version section: `[X.Y.Z] - YYYY-MM-DD`
2. Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Create new empty `[Unreleased]` section

## Documentation Style Rules

- Concise — sacrifice grammar for brevity
- Practical — examples over theory
- Accurate — code verified, not assumed
- Current — matches actual implementation

No enterprise fluff. No outdated information. No assumptions without verification.

## Ask if Uncertain

If you're unsure about intent behind a change or user-facing impact, **ask the user** — don't guess.
