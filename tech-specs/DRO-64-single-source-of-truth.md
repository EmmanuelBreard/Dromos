# DRO-64: Single Source of Truth for workout-library.json + Prompt Files

**Overall Progress:** `0%`

## TLDR

Eliminate duplicate copies of `workout-library.json` (3 copies) and step prompt files (3 copies each) by establishing one canonical location per asset. Includes a hotfix for Step 3 prompt drift (production is behind eval) and scripts to keep everything in sync.

## Critical Decisions

- **Symlink for iOS bundle**: Use a git symlink `Dromos/Dromos/Resources/workout-library.json` → `../../../ai/context/workout-library.json` instead of an Xcode build phase script. Simpler, no pbxproj changes needed since file system sync handles it.
- **Generated .ts from .txt**: Deno Deploy has no filesystem access at runtime, so edge function prompts must stay as `.ts` exports. A sync script generates the `.ts` wrappers from canonical `.txt` files. Run before deploy.
- **Phase 1 is the hotfix**: Step 3 prompt drift is affecting plan quality. Sync it first, independently deployable.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` | MODIFY | Sync content from `ai/prompts/step3-workout-block.txt` |
| `Dromos/Dromos/Resources/workout-library.json` | REPLACE | Delete file, replace with symlink → `../../../ai/context/workout-library.json` |
| `supabase/functions/generate-plan/context/workout-library.json` | DELETE | Dead code — edge function fetches from Storage |
| `supabase/functions/generate-plan/prompts/step1-macro-plan.txt` | DELETE | Dead copy |
| `supabase/functions/generate-plan/prompts/step2-md-to-json.txt` | DELETE | Dead copy |
| `supabase/functions/generate-plan/prompts/step3-workout-block.txt` | DELETE | Dead copy |
| `scripts/sync-prompts.sh` | CREATE | Generates `.ts` wrappers from canonical `ai/prompts/*.txt` |
| `scripts/upload-static-assets.sh` | CREATE | Uploads `workout-library.json` to Supabase Storage bucket |
| `.claude/context/ai-pipeline.md` | MODIFY | Update file locations, remove "dev/eval version" distinction |
| `.claude/context/architecture.md` | MODIFY | Remove `workout-library.json` from Resources listing |

## Context Doc Updates

- `architecture.md` — Remove `workout-library.json` from `Resources/` folder listing, note symlink
- `ai-pipeline.md` — Update File Locations section: remove "dev/eval version" labels, document sync script, remove dead file references

## Tasks

- [ ] 🟥 **Phase 1: Hotfix Step 3 prompt to production**
  - [ ] 🟥 Copy content of `ai/prompts/step3-workout-block.txt` into `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` (wrapped in `` export default `...` ``)
  - [ ] 🟥 Verify the 3 additions are present: ±20% duration flexibility rule, Easy session exemption, worked violation examples
  - [ ] 🟥 Deploy edge function: `supabase functions deploy generate-plan`

- [ ] 🟥 **Phase 2: Consolidate workout-library.json**
  - [ ] 🟥 Delete `supabase/functions/generate-plan/context/workout-library.json`
  - [ ] 🟥 Delete `Dromos/Dromos/Resources/workout-library.json` and create symlink: `ln -s ../../../ai/context/workout-library.json Dromos/Dromos/Resources/workout-library.json`
  - [ ] 🟥 Build iOS app in Xcode — verify `WorkoutLibraryService` still loads the library correctly (symlink resolution)
  - [ ] 🟥 If symlink fails with file system sync: fallback to Xcode Shell Script Build Phase that copies `${SRCROOT}/../ai/context/workout-library.json` → `${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/workout-library.json`

- [ ] 🟥 **Phase 3: Consolidate prompt files**
  - [ ] 🟥 Delete dead `.txt` copies from `supabase/functions/generate-plan/prompts/` (3 files: `step1-macro-plan.txt`, `step2-md-to-json.txt`, `step3-workout-block.txt`)
  - [ ] 🟥 Create `scripts/sync-prompts.sh` that for each step: reads `ai/prompts/step{N}-*.txt` → writes `supabase/.../prompts/step{N}-*-prompt.ts` wrapped in `export default \`...\``
  - [ ] 🟥 Run `scripts/sync-prompts.sh` and verify all 3 generated `.ts` files match current production (steps 1 & 2 should be identical, step 3 already synced in Phase 1)
  - [ ] 🟥 Add a comment header to each generated `.ts`: `// AUTO-GENERATED from ai/prompts/<name>.txt — do not edit directly. Run scripts/sync-prompts.sh`

- [ ] 🟥 **Phase 4: Create Supabase Storage upload script**
  - [ ] 🟥 Create `scripts/upload-static-assets.sh` that uploads `ai/context/workout-library.json` to the `static-assets` bucket using Supabase CLI (`supabase storage cp ai/context/workout-library.json ss:///static-assets/workout-library.json`)
  - [ ] 🟥 Test the script against the live project

- [ ] 🟥 **Phase 5: Update context docs**
  - [ ] 🟥 Update `ai-pipeline.md` File Locations section: remove "dev/eval version" labels, document `scripts/sync-prompts.sh` workflow, remove dead file references
  - [ ] 🟥 Update `architecture.md` Resources section: note symlink to canonical `ai/context/workout-library.json`
