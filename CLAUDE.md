# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is the ARC-AGI-1 dataset (`data/`) plus a static browser UI for solving tasks by hand (`apps/`). There is no build, package manager, linter, or test suite. The task JSON format and the UI controls are covered in `README.md`.

## Data

- `data/training/` and `data/evaluation/` each hold 400 tasks named `<8-hex-id>.json`.
- **Evaluation is held out.** When building or tuning a solver, develop against `training/` only. Open evaluation tasks only for a final scoring run the user asks for. Reading them while iterating leaks the test set (see README).
- **Exception: object labeling.** The labeling app decomposes evaluation Grids on purpose, to produce ground truth for scoring object-perception models (see `docs/adr/0001-evaluation-decompositions-as-ground-truth.md`). Opening evaluation tasks inside that app is expected. Never train on `objects/evaluation/`.
- Scoring is exact match: output dimensions plus every cell, up to 3 attempts per test input. A task counts as solved only when all of its test inputs are solved.

## Testing interface (`apps/`)

Plain jQuery 1.12 + jQuery UI, loaded from CDNs, with global state and no modules. To run it, open `apps/testing_interface.html` in a browser.

- `js/common.js` has the shared pieces: the `Grid` data class, flood fill, and the DOM↔data sync helpers (`fillJqGridWithData`, `copyJqGridToDataGrid`, `setCellSymbol`).
- `js/testing_interface.js` holds the page logic and globals (`CURRENT_INPUT_GRID`, `CURRENT_OUTPUT_GRID`, `TEST_PAIRS`, `CURRENT_TEST_PAIR_INDEX`).
- The output grid has two representations, a DOM grid (`.cell` elements carrying a `symbol` attribute) and a `Grid` object. Call `syncFromEditionGridToDataGrid()` / `syncFromDataGridToEditionGrid()` whenever you cross between them.
- Symbol colors 0–9 come from the `.symbol_N` classes in `css/common.css`.
- Gotchas:
  - "Random task" (`randomTask`) fetches from the GitHub API for `fchollet/ARC`, not from local `data/`, so local edits never show up there. Load files through the file picker instead.
  - `submitSolution` checks the row count and each reference row's cells, but not the submitted row width. An output that is too wide can still pass.
