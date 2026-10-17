# Session 26: the demonstrators, TraitReport, the review under wrapping by facts (running notes)

The user (start of session 26): "I want to continue work on the Demonstrators, and the Julia work required for them. Where do the Demonstrators stand?" Then: "How close are we to being competitive with python for load DataFrames and TraitMakie and make a first plot in a fresh session." After the first numbers: "Okay, so we are within striking distance. Add this scenario as a third demonstrator. Then review all the demonstrator rows, especially if they are still valid or need to be updated due to the new wrap-at-facts design. Then chose an order in which to work on this. Prioritise features and patches in Julia that help over workarounds." And: "Before further digging into details of demonstrator 3 update the docs with the third demonstrator and do the review of the Demonstrators given the new design."

**State at the start:** TraitWorld main 893f0bb, julia-1.13 `trait-world-1.13` f72f7368f0, experiments ff47ef9, design repo a0dcee6. TraitDifferentialEquations 702402d, TraitMakie be65ca9.

## Log

- **State of the demonstrators:** both pass their tests, and both are small (ODECore 537 lines, PlotCore 256). Their READMEs lagged sessions 24 and 25.
- **The Python comparison, measured** (scratch work in `$TMPDIR/ttfp`, now `TraitReport/scripts/`):
  - Python, pandas and matplotlib (`experiments/interfaces/python/app.py`): 0.60–0.61 s from process start; imports 0.41 s, plot and PNG 0.10 s.
  - Julia, the ordinary script with CSV, DataFrames, Statistics and TraitMakie: 4.87–5.11 s on stock 1.13.2 and 5.92–6.02 s patched.
  - Phases, stock: startup 0.10, imports 0.75–0.79, read 3.48–3.66, summarize 0.064–0.068, plot and PNG 0.11, exit 0.36–0.38 s.
  - juliaup is not the cause: the binary called directly starts in 0.10–0.11 s.
- **Where the time goes:**
  1. **`CSVInlineStringsExt` invalidates CSV's read path.** `CSV.File` takes 0.19 s with CSV alone, and 2.46–2.53 s with DataFrames loaded in either order. DataFrames loads InlineStrings. That activates CSV's extension, whose methods of `_settledstringtype`, `_lazyeltype` and `_materializecolumn` invalidate CSV's image code; `thisind(::InlineString, ::Int)` is among the invalidating methods too. This is plain Julia's invalidation of ordinary code, case D of `3-wrapping.md`.
  2. **TraitWorld's own `show(::IO, ::Type{<:CObj})` and `show(::IO, ::Type{<:TObj})`** invalidate `CSV.parsecolchunk!` (0.62 s), Base's exit hooks (0.13 s) and TraitWorld's own `_on_package_load`. Removing both methods (a copy in `$TMPDIR/TW_noshow`) brings the read back to 2.64 s from 3.6 s, exit to 0.18 s, and the whole run to 3.84 s.
  3. **The view-cache flush at exit:** 0.14 s with TraitMakie alone.
  4. **Patched images load slowly:** `using TraitMakie` takes 0.69 s patched against 0.23 s stock.
- **TraitReport created** (a new repository, `TraitReport/`, not committed): the task, three forms (ordinary script; trait-world report under the policy; trimmed binary), eleven rows, an order of work. Form (a) is measured.
- **Review of the rows:** `writeup/reviews/2026-10-17-demonstrators-under-facts.md`.
  - The metric for loads is now policy CodeInstances lost, not invalidations under the filter.
  - Stock and patched differ by design, since piece 5 is missing on stock.
  - Pirates are followed by default, and refused only under strict mode, which is deferred.
  - Several rows predate the policy and need remeasuring.
  - One inconsistency: the overview says a new loss compiles the step again, against the adopted tag decision (open-issues §5.4).
  - Applied to both READMEs.
- **Order of work** (the review's last section; Julia pieces and TraitWorld fixes over workarounds):
  1. TraitWorld stops invalidating plain code, then a remeasure pass;
  2. TraitReport form (b);
  3. the patched images' load time (Julia, piece 5);
  4. Julia pieces 12 and 11;
  5. TraitDifferentialEquations row 5 (tags);
  6. the baselines without traits;
  7. TraitMakie's remaining pieces;
  8. binaries and trim's verifier;
  9. strict mode.
- **Documents updated:**
  - the root README (six repositories, plan item 5);
  - `writeup/README.md`;
  - `open-issues.md` §4.6–4.9 and §5.4;
  - `.gitignore` (`/TraitReport/`).

## Next

The order of work above, starting with step 1: drop TraitWorld's two `show(::IO, ::Type{…})` methods, make the view-cache flush free when nothing is new, then remeasure the rows marked *remeasure* in both READMEs.
