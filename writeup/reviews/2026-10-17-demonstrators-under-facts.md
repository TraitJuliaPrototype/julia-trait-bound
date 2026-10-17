# Review: the demonstrators' rows under wrapping by facts

Session 26, 2026-10-17. The rows of TraitDifferentialEquations and TraitMakie were written in session 22, before wrapping by facts. That design removed wrappers, sealing, declared calls, layering and the invalidation filter (TraitWorld b60b126). This review checks every row against the current design (`notes/1-overview.md`, `notes/3-wrapping.md`, `explorations/wrapping-by-facts.md`, `explorations/aot-under-facts.md`). It adds TraitReport, the third demonstrator, and sets the order of work.

**Verdicts:**
- **valid:** the row measures a claim the current design makes, as written;
- **restate:** the claim stands, but its wording or metric belongs to the earlier design;
- **remeasure:** the row is valid, but its numbers predate wrapping by facts or piece 10;
- **done:** measured under the current design.

## What changed for the rows

1. **The metric for loads.** Before, "invalidations in trait-world code, with the filter" was counted with `jl_debug_method_invalidation` and protected by the filter. Now nothing is skipped. The claim is that policy-compiled CodeInstances are lost only to stakeholders of their facts or to winning pirates. The metric is g2all's: policy CodeInstances lost per load, 0 expected. The "TraitWorld machinery: 285 stock, 14 patched" counts no longer measure anything, since the machinery is compiled by the policy where it can be.
2. **Stock and patched now differ by design.** On stock Julia, package images keep no native code for the policy's CodeInstances, so every session compiles them again: the first solve takes 0.44 s on stock against about 55 ms on the patched build (`julia-support.md`, piece 5). Rows that predict milliseconds are predictions for the patched build. Stock numbers are reported beside them as the price of missing piece 5.
3. **Calls into ordinary code are direct.** Cairo, ForwardDiff, CSV and Makie are called as ordinary code, and their code is compiled under the policy (cases A–D of `3-wrapping.md`). "Wrapped or reached through declared calls" is no longer a question.
4. **Pirates are followed.** A pirate that wins at a fact recompiles the code, as "identical or error" requires. Refusing it is strict mode, an option deferred in session 25. Rows about pirates being "reported" or "sealed" are restated as: followed by default, refused under strict mode.
5. **A trait-world package must not invalidate the plain world.** Session 26 found that TraitWorld's own `Base.show(io::IO, T::Type{<:CObj})` and `…Type{<:TObj}` invalidate CSV's read path and Base's exit hooks: 1.0 s in TraitReport. These methods are no pirates, but they widen a function that plain code calls at abstract signatures. This applies to every row measured with other packages loaded.
6. **Leftover machinery:** the view cache is still on by default, and its flush at exit costs 0.14 s even when nothing is new (TraitReport row 6).

## TraitDifferentialEquations

| # | Row | Verdict | Change |
|---|---|---|---|
| 1 | first Tsit5 solve, precompiled user package | remeasure | 73–76 ms was session 23. Under facts: 55–60 ms patched in every load order, 0.44 s stock. State both. The < 20 ms prediction is for patched. |
| 2 | first solve, a new model at the prompt | remeasure | 14 ms predates the policy. New trait code after big loads costs 0.8 s for its first call (open-issues §4.5); measure without and with CSV, DataFrames, CairoMakie loaded. |
| 3 | first Rodas5 solve | done | 72–77 ms with ForwardDiff's `Dual`, in every load order. Drop the `LDual` history from the cell. |
| 4 | a new callback | remeasure | 12–14 ms predates the policy; 35–51 ms after loads was the filter era. |
| 5 | gradient: first loss, second loss closure | valid, not built | The adopted decision (tags labelled by a `Callable`'s primal signature, `Tag{Sig{A,S},V}`) is what makes "< 10 ms for the second loss" possible. **Inconsistency:** `notes/1-overview.md` says a new loss "compiles the step again, as today". That is true without the labelled tag, not with it. Fix the overview when row 5 is built. |
| 6 | `Vector{Float32}` state | valid | "Then cached" means: in a view cache on stock, in the conformer's or view cache's image on patched (piece 5). |
| 7 | rows 1–5 after loads, all orders | restate; mostly done | Metric: policy CodeInstances lost, 0 (g2all: 0 over twelve loads). Done for rows 1 and 3. The text "2–4 ODECore methods invalidated (pirates of Base)" is from the filter era and no longer holds. Remaining: rows 2, 4, 5. |
| 8 | the `nextfloat(::Dual)` pirate | restate | Default: followed; the solver's code recompiles where the pirate wins at one of its facts; report how much. Strict mode: refused at definition. Strict mode is deferred, so only the default half is measurable now. |
| 9 | the three error cases | valid | Unaffected: definition checking and the boundary rule are unchanged. |
| 10 | `typeof(integrator)` | done | |
| 11 | run time per step, by model mode | valid | Add the policy's cost: run-time sites where plain Julia would infer (tens of ns, `3-wrapping.md`). The pinned model mode is plan item 1.8, to build when this row needs it. |
| 12 | trimmed binary | valid, deferred | One of the three binaries of `aot-under-facts.md` §4; a trim build compiles the plain call in the closed world. |
| 13 | precompile time and image sizes | valid; extend | Add image load time on the patched build. TraitReport found TraitMakie's image loading in 0.69 s patched against 0.23 s stock, so piece 5's cost must be measured here too. |

**Other text in the README:**
- "the AD tag is erased at the projection": restate as "labelled by the loss's primal signature". Projection is the earlier design's term.
- "No load invalidates the solvers' compiled code": restate as "only stakeholders of its facts, or pirates that win at them, can".
- Prerequisites: all done except the pinned dynamic model mode.

## TraitMakie

| # | Row | Verdict | Change |
|---|---|---|---|
| 1 | time to first PNG, fresh process | remeasure | Load 0.30–0.41 s was session 23. Session 26: `using TraitMakie` takes 0.23 s stock and 0.69 s patched. The patched load time is a new problem (TraitReport row 5). |
| 2 | load-order independence | done on patched | 87–97 ms in every order, with twelve packages before or after. "With the filter" is gone. Stock under facts is still to measure. |
| 3 | invalidations over each load | restate; done | Metric: policy CodeInstances lost, 0. The machinery counts are dropped. |
| 4 | a new data type, colour, recipe | remeasure | 61–132 ms predates the policy. Also measure after big loads (open-issues §4.5). |
| 5 | dispatch targets, phases A–G of x15/x16 | restate | Under facts, count (a) the targets `verify_main` lists (it enumerates dynamic values' targets since session 25), and (b) the run-time sites the policy leaves in PlotCore's compiled code. Phases A–G were Makie's experiment. Keep them as the comparison. |
| 6 | colour shape change | remeasure | Works. The times predate the policy. |
| 7 | `verify_main`, trimmed binary | done | 4.07 MB, 0.05 s, PNG byte-identical (`aot-under-facts.md` §7). Open: `--trim=safe` reports 26 errors, from the machinery's slow paths. |
| 8 | errors | valid | |
| 9 | run-time cost of dynamic positions | valid | Needs PlainPlots. |
| 10 | precompile cost, image sizes | valid; extend | Add image load time, stock against patched. |

**Other text in the README:**
- Scope: "Whether Cairo.jl is wrapped or reached through declared calls is decided by the check" is obsolete. Cairo is called directly (case B).
- Prerequisites: "printing frames by bound and representation" now reads "by bound and key" (done).
- Success: "rows 1–3 and 6–7 hold where PlainPlots fails them" stays. PlainPlots is not built.

## TraitReport (new)

Its rows are written for the current design (its README). It measures case D, which no row covered: CSV and DataFrames compiled under the policy, with InlineStrings' extension methods loading after.

## The order of work

**Principle (the user, session 26):** prefer features and patches in Julia, and fixes in TraitWorld, over workarounds. Workarounds are, for example, ComboCache, workloads added to other people's packages, or caches that stand in for a missing Julia piece. Prefer principled fixes that reflect a future state of the ecosystem: for CSV's invalidations, a TraitCSV (TraitReport form (b′)) rather than a workload in CSV's extension. About 1 s from process start to PNG is the bar against Python's 0.6 s.

1. **TraitWorld stops invalidating plain code.** Drop the two `show(::IO, ::Type{…})` methods, and make the view-cache flush free when nothing is new. Then refresh the TraitDifferentialEquations and TraitMakie READMEs and remeasure the rows marked "remeasure" in one pass (`demos.sh`). This is small, and every later number depends on it.
2. **TraitReport form (b) on the patched build,** then form (b′), TraitCSV. Form (b) is the first measurement of case D and needs no new Julia piece. TraitCSV shows the ecosystem's shape: package extensions become conformances, which cannot discard other keys' code.
3. **Julia: the patched images' load time.** TraitMakie loads in 0.69 s patched against 0.23 s stock. Profile it: native code for foreign CodeInstances (piece 5), owner-aware edge verification (piece 9), or the facts' validation at load. This is the largest remaining gap to Python, and piece 5 is the deep upstream piece, so its cost has to be known.
4. **Julia piece 12, a frozen world for the policy's compiler,** then **piece 11** through 1.13's declared `CompilerPlugins.typeinf`.
   - Piece 12 removes about 0.5 s per session for new keys after big loads (TDE row 2, TraitMakie row 4, a report on a new file type).
   - Piece 11 removes the generator, its re-entry guard, and assumption A4 (threads).
   - Both are upstream material, from the first proposal.
5. **TraitDifferentialEquations step 4: tags labelled by the loss's signature (row 5).** It is the order-of-magnitude claim not yet measured. Fix the overview's sentence with it.
6. **The baselines without traits:** TraitDifferentialEquations' baseline (b), and PlainPlots. Rows 4, 5 and 9 need them to separate what the traits add from what discipline adds.
7. **TraitMakie's remaining pieces:** `barplot` and `hist` (also for TraitReport), `UserPlots`, rows 5, 8 and 10.
8. **Binaries,** when taken up again (deferred, session 25):
   - first trim's verifier: hide the machinery's closed-world slow paths from `--trim=safe`, and let `verify_main` walk packages' `__init__`;
   - then the TraitDifferentialEquations binary and TraitReport form (c).
9. **Strict mode** (deferred): TraitDifferentialEquations row 8's second half, with Julia pieces 1′, 14 and 15.

**Why this order:**
- Step 1 is a bug fix that every number depends on.
- Step 2 is cheap and tells how much of the gap to Python is left for Julia work.
- Steps 3 and 4 are the Julia work the numbers point to, in order of their measured size.
- The order-of-magnitude rows (step 5) and the baselines (step 6) come next, since an upstream proposal needs them.
