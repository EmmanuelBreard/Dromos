# Initial Exploration Stage

Your task is NOT to implement this yet, but to fully understand and prepare.

Your responsibilities:

- Analyze and understand the existing codebase thoroughly.
- Determine exactly how this feature integrates, including dependencies, structure, edge cases (within reason, don't go overboard), and constraints.
- Clearly identify anything unclear or ambiguous in my description or the current implementation.
- List clearly all questions or ambiguities you need clarified.
- Search linear based on user message (DR0-#) to get the task description

Remember, your job is not to implement (yet). Just exploring, planning, and then asking me questions to ensure all ambiguities are covered. We will go back and forth until you have no further questions. Do NOT assume any requirements or scope beyond explicitly described details.

Please confirm that you fully understand and I will describe the problem I want to solve and the feature in a detailed manner.

## After All Questions Are Resolved

Once you have no more questions and understand the feature fully, **update the Linear issue description with a comprehensive product-level description**. This is your proof that you understood the feature correctly. The user validates the *what* before the tech spec covers the *how*.

**The Linear issue description must include:**

1. **What we're building** — Plain-language description from the user's perspective
2. **Current state** — What exists today and what's wrong/missing
3. **Expected outcome** — Detailed description of what the user will see/experience. Be exhaustive:
   - Visual layout and component hierarchy
   - Specific data displayed and how it's computed (formulas, mappings, fallbacks)
   - Interaction behavior (tap, scroll, expand, etc.)
   - Color/styling details with exact rules
   - Sport-specific or context-specific variations
   - Edge cases and fallback behaviors
4. **Reference material** — Mention screenshots/prototypes the user provided (attach if possible)

**Then tell the user it's ready for review.** Share:
- The Linear issue link
- The full description inline in the conversation (so they can review without leaving the thread)

The user will review and either confirm or flag misunderstandings. If they flag issues, update the description and re-share. Only after the user is confident will they launch `/create-tech-spec`.
