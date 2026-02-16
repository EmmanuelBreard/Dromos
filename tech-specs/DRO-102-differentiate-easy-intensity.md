# DRO-102: Differentiate Easy Intensity by Session Context

**Overall Progress:** `100%`

## TLDR
All `RUN_Easy_*` templates use a flat `mas_pct: 70` and all `BIKE_Easy_*` templates use a flat `ftp_pct: 75`, regardless of duration. A 30min brick run and a 120min long run shouldn't be at the same intensity. Lower the intensity on longer and brick sessions to match coaching best practices.

## Critical Decisions
- **No new templates needed** — current 6 run + 6 bike easy templates already differentiate by duration. We just adjust their `mas_pct` / `ftp_pct` values.
- **No prompt changes needed** — Step 1 says "Easy" generically, Step 3 picks templates by duration fit. Intensity lives entirely in the template data.
- **No fixer changes needed** — `fixBrickRunDuration` already forces `RUN_Easy_01` for brick runs, which will naturally inherit the lower 60% MAS.
- **No Swift code changes** — `WorkoutLibraryService` reads `mas_pct`/`ftp_pct` from JSON dynamically. Values flow through `stepSummaries()` and `flattenedSegments()` automatically.

## Target Values

### Run (`mas_pct`)
| Template | Duration | Context | Current | Target |
|----------|----------|---------|---------|--------|
| `RUN_Easy_01` | 30min | Brick run (always) | 70 | **60** |
| `RUN_Easy_02` | 45min | Short easy | 70 | **65** |
| `RUN_Easy_03` | 60min | Standard easy | 70 | **65** |
| `RUN_Easy_04` | 80min | Long run | 70 | **63** |
| `RUN_Easy_05` | 90min | Long run | 70 | **62** |
| `RUN_Easy_06` | 120min | Long run | 70 | **62** |

### Bike (`ftp_pct`)
| Template | Duration | Context | Current | Target |
|----------|----------|---------|---------|--------|
| `BIKE_Easy_01` | 30min | Short easy | 75 | **70** |
| `BIKE_Easy_02` | 55min | Easy + cadence drills | 75 | **70** |
| `BIKE_Easy_03` | 60min | Standard easy | 75 | **70** |
| `BIKE_Easy_04` | 80min | Medium-long | 75 | **68** |
| `BIKE_Easy_05` | 90min | Long ride | 75 | **65** |
| `BIKE_Easy_06` | 120min | Long ride | 75 | **65** |

> Note: `BIKE_Easy_02` has a cadence drill section (4×20s at 115rpm) — the `ftp_pct` on those segments stays at the same value as the main work segment (both get updated to 70).

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `ai/context/workout-library.json` | MODIFY | Update `mas_pct` on 6 RUN_Easy templates, `ftp_pct` on 6 BIKE_Easy templates (all segments) |

## Context Doc Updates
- `ai-pipeline.md` — Add a note that Easy intensity varies by template duration (not flat across all Easy templates)

## Tasks

- [x] 🟩 **Step 1: Update RUN_Easy templates**
  - [x] 🟩 Set `RUN_Easy_01` → `mas_pct: 60`
  - [x] 🟩 Set `RUN_Easy_02` → `mas_pct: 65`
  - [x] 🟩 Set `RUN_Easy_03` → `mas_pct: 65`
  - [x] 🟩 Set `RUN_Easy_04` → `mas_pct: 63`
  - [x] 🟩 Set `RUN_Easy_05` → `mas_pct: 62`
  - [x] 🟩 Set `RUN_Easy_06` → `mas_pct: 62`

- [x] 🟩 **Step 2: Update BIKE_Easy templates**
  - [x] 🟩 Set `BIKE_Easy_01` → `ftp_pct: 70`
  - [x] 🟩 Set `BIKE_Easy_02` → `ftp_pct: 70` (all 3 segments: work + drill work + drill recovery)
  - [x] 🟩 Set `BIKE_Easy_03` → `ftp_pct: 70`
  - [x] 🟩 Set `BIKE_Easy_04` → `ftp_pct: 68`
  - [x] 🟩 Set `BIKE_Easy_05` → `ftp_pct: 65`
  - [x] 🟩 Set `BIKE_Easy_06` → `ftp_pct: 65`

- [x] 🟩 **Step 3: Deploy**
  - [x] 🟩 Run `scripts/upload-static-assets.sh` to push updated JSON to Supabase Storage (edge function source)
  - [x] 🟩 iOS picks up changes automatically via symlink at next build

- [x] 🟩 **Step 4: Update context docs**
  - [x] 🟩 Add note to `ai-pipeline.md` that Easy intensity varies by template duration
