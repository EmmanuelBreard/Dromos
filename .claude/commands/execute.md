Now implement precisely as planned, in full.

Implementation Requirements:
- If asked to execute a task named DRO-# or DRO#, query linear to get the requirements
- Write elegant, minimal, modular code.
- Adhere strictly to existing code patterns, conventions, and best practices.
- Include thorough, clear comments/documentation within the code.
- As you implement each step:
  - Update the markdown tracking document with emoji status and overall progress percentage dynamically.
- After implementation, update any affected `.claude/context/` docs:
  - `schema.md` if tables or columns changed
  - `architecture.md` if new files, folders, or patterns were added
  - `ai-pipeline.md` if prompts, eval scripts, or pipeline logic changed
- Create a PR with the changes to git with descriptive git message and link the commit to the linear task you worked on
- When you completed the task change the status of the linear task from in-progress to `In Review`
