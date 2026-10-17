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

- **The user** (after the review): "I consider 1s to be fine relative to python. As for CSV invalidations, consider if a TraitCSV could fix them in a principled manner. In general, principled fixes that could reflect a future state of the ecosystem. Record this preference, then go for your planned order of things." Recorded in memory. TraitCSV is form (b′) in TraitReport's README: package extensions become conformances.
- **Step 1, TraitWorld stops invalidating plain code:**
  - **Julia piece 17** (julia db82407fa6): `Base.Experimental.register_type_printer` and `show_type_plain`. `_show_type` consults a registry by type name, so no method of `show(::IO, ::Type)` is needed. The patched system image was rebuilt (`tw-build.sh` takes a target now).
  - **TraitWorld 6239b1e:**
    - type printers in place of the two `show` methods, with a guard test;
    - under the policy, view caches only with piece 5;
    - the exit hook only when something is noted.
  - **Result:** form (a) 5.0 → 3.8 s stock, exit 0.37 → 0.09 s.
- **Form (b) built** (TraitReport d39ecd6):
  - `ReportCore`, with `Table` and `Job` traits.
  - A `DataFrame` cannot conform, since it is not deeply concrete, so the report converts it into its own `Columns`.
  - Work: 0.27 s stock, **57–65 ms patched**, CSV's read included with DataFrames and InlineStrings loaded. The policy contains CSV's invalidation, as predicted.
- **Patched images load slowly: the cause was TraitWorld's hooks** (TraitWorld 29f0a8e).
  - The image-methods hook was native code, compiled at the first load and invalidated by each later load: 0.82 s.
  - The hooks and the package callback now run under the policy, with a dynamic native fallback, precompiled in TraitWorld's image.
  - `using TraitReport` 1.5 → 0.79 s patched. **Form (b): 1.01–1.05 s patched**, 1.17–1.20 s stock. Python: 0.60 s.
- **Remeasure pass:** `scripts/rows.jl` in both demonstrators (one fresh process per cell; loads none, before, after; stock and patched). Patched:
  - TDE row 1: 32–37 ms;
  - a second model function: 7–12 ms;
  - callbacks: 13–14 ms;
  - TraitMakie's first PNG: 62–65 ms;
  - recolor: 9–48 ms;
  - all in every order.
  - Stock under the policy is slow on first calls of code the images don't hold (TraitMakie's first PNG 4.6–11 s): piece 5 is missing there.
- **New trait code after big loads, two causes** (open-issues §1.3, §1.4, §4.5):
  1. **Compiler code for `FactsInterp`** has abstract edges on the interpreter, since `InferenceState.interp::AbstractInterpreter`. REPL's `REPLInterpreter` (loaded first in any interactive session) breaks them at load. `import REPL` before TraitMakie: a new colour key's first PNG 5.9 s instead of 126 ms. Found with `Base.Compiler.ReinferUtils._jl_debug_method_invalidation` (`insert_backedges_callee` records).
  2. **The machinery's internal functions run natively:** `@implement` 0.64 s, 1.2–1.5 s after loads. Moving `@implement`'s expansion and checks under the policy (TraitWorld a5e4778) helped little, because its run-time sites reach native internal functions (`_analyze_keeps`, `_implement_oneline`, …).
- **Also fixed:** the view-cache flush built stale caches from another directory (a latent bug exposed by a test).
- **Tests at the end:** 344 patched, 300 stock; acceptance 16/16; the hunt as before (C24b); both demonstrators on both builds.

- **The user decided** §1.3 (policy in the platform, a system-image prototype) and §1.4 (facts at non-public functions; run-time dispatch under the policy recorded as an alternative, with an experiment later).
- **Facts at non-public functions** (TraitWorld 83c35dd, then scoped in 6bcca9f):
  - `implement.jl` is `@nospecialize` as a whole, so its calls compile to `:invoke` of policy code;
  - `@implement` 0.64 → 0.20 s for a model type and 0.55 → 0.09 s for a data type without loads; 1.0–1.5 → 0.52 s after loads.
  - Applied to Base's internals, the rule made a report after OffsetArrays, StatsBase and Unitful *slower* (5.4 s against 1.7 s). Scoped to calls within the caller's own package; to confirm with the user.
- **The user's objection** ("the small trait package precompiled exactly what we need … wouldn't that be cheating?") **holds:**
  - The plain package `PlainReport` (form a′), with the same workload, takes 0.94–1.02 s patched, as fast as form (b).
  - Its speed is piece 5: without it, its work takes 0.96–0.99 s.
  - Form (b)'s 55 ms came largely from CSV's own image (CSV's internals are run-time sites under the policy).
  - With other packages loaded first, both forms slow down and the trait form more (5.3–5.7 s against 2.7–2.8 s): CSV's native code is invalidated, and the policy's compiler code in TraitWorld's image fails validation and is recompiled (3.5 s). §1.3, broader than REPL.
- **The user, next:** "We really should have a DataFrames that is built around Traits and then CSV that implements the traits and that would prevent invalidations whether the work is in the precompile workload or not, right? But that's a large intrusive change to DataFrames I guess." Answered in the reply; TraitReport's README records TraitTables and TraitCSV as the form that would show the design.

## Next

1. **The policy in the platform** (§1.3, decided): a patched system image with TraitWorld in it; measure REPL first, the g2all stack first, and TraitReport's load rows.
2. **TraitTables and TraitCSV** (the user's proposal, pending their go): a DataFrame-shaped table of `Dynamic{Column}` and a reader whose cell types are a trait; then TraitReport as a plain script with no workload of its own, against PlainReport, under loads.
3. The rest as before: TraitDifferentialEquations step 4, piece 11, baselines.
