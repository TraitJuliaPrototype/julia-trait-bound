# Review: the demonstrators with a fresh eye (claims, baselines, methods)

Session 27, 2026-10-17. Scope: the three READMEs (TraitDifferentialEquations, TraitMakie, TraitReport), the session note `session-notes/2026-10-17-27-traittables-traitcsv.md`, the measurement scripts, the baselines, and `writeup/notes/1-overview.md`. Verified items were checked in the sources or by a small experiment (`/tmp/claude-1000/review/plain_inv.jl`, two short runs on the patched build, `nice -n 19`, shared machine). Everything else is reasoning and is marked so.

Terms. A *CodeInstance* is one compiled specialization of a method. *Invalidation* discards CodeInstances whose inference assumptions a new method breaks; the links that make this possible are *edges*. The *facts policy* is TraitWorld's compiler mode: it records edges only at concrete call signatures. A *key* is the set of types a trait bound can see; a *worker* is library code compiled for one key. A *view cache* is a package TraitWorld writes under `~/.julia/traitworld/views` for workers no package image holds. The *patched build* is Julia 1.13.2 plus 944 inserted lines in 16 files (`git -C julia-1.13 diff --stat v1.13.2`); the *system image* is a 248 MB `sys.so` with TraitWorld compiled in (`experiments/sysimage`). A *workload* is the code a package runs at precompilation so that its image holds the compiled result.

## Summary verdict

- **Robustly shown, on the patched build:** compiled code behind trait-module entries survives unrelated loads in every order (TraitReport form (t) 66–80 ms against 102–147 ms; TDE row 1 after loads 6.5 against 54 ms; TraitMakie 19 against 100 ms), and SciML's per-closure recompiles disappear (a second callback 13–29 ms against 0.96 s; a second loss 17–21 ms against 2.48 s). The SciML numbers are real second closures (`experiments/solvers/ttfs_repeat.jl:17,21`).
- **Not shown:** interactivity at the REPL, where the first new key is known to cost 5.9 s without the system image (`writeup/open-issues.md:12`); any number on stock Julia that is not 10–500× worse than the plain baseline; ahead-of-time compilation under the current design; Revise-style edits; threads; composition beyond three libraries of about 600 lines in total.
- **Not separated:** what the *traits* add from what *an inference barrier at the entry* adds. I verified that both plain baselines lose only abstract-signature CodeInstances rooted at `@nospecialize`/`Any` entries. A hardened plain baseline has not been run.
- **Fresh-session headlines** (6.4–8.0 ms, 18–22 ms, 0.52–0.56 s) are first calls of precompiled keys whose workloads were extended until they covered the measured calls. The plain baselines with the same workloads match them, and the READMEs say so; the comparisons against SciML, Makie, CSV.jl and pandas in the "What it demonstrates" sections do not.
- **Documents disagree** with each other and with the source tree (stale overview numbers; README scopes naming modules and packages that do not exist; "about 2,500 lines" for 691).

## Findings, ranked

### Blocking

**B1. The REPL case is not measured, and it is the interactive case.**
- Every row runs a script with `--startup-file=no` (`experiments/demos/rows.sh:15`, `TraitReport/scripts/measure.sh:56`, `loads.sh:12`). No row starts an interactive session or loads REPL before TraitWorld.
- Known cost: with REPL loaded first, the policy's compiler code in TraitWorld's image fails validation and the first new key costs 5.9 s instead of 0.13 s (`writeup/open-issues.md:12,117`); `@implement` after loads 1.2–1.7 s (`:118`). TraitReport's "REPL: 80 ms" (`TraitReport/README.md:70`) is a precompiled key and does not touch this.
- Consequence: the thesis "excellent interactivity" is supported for precompiled keys only. A user at the REPL who defines a type, uses a `Float32` state or reads a `String15` column pays seconds, unless the custom system image is installed.
- Fix: a REPL row in all three demonstrators (`julia -i`, or `using REPL` first), patched without and with the system image, and stock. State it in each README's status line.

**B2. The baselines' losses under loads have one identifiable cause, and the control that isolates the traits' contribution has not been run.**
- Verified (my experiment, patched build, CSV + DataFrames + CairoMakie loaded after a first call):
  - PlainODE loses 19 of 74 valid CodeInstances. All are abstract-signature specializations descending from `solve(@nospecialize(prob::ODEProblem), …)` (`baselines/PlainODE/src/PlainODE.jl:242`): `_solve(::Any, ::Vector, …)`, `solve_ode(::FunctionWrapper{…} where {T,P}, …)`, `ODEProblem(::typeof(lorenz!), ::AbstractVector, …, ::Any)`, `_state(::AbstractVector{<:Dual})`. The concrete `solve_ode` for `Float64` stays. The next call recompiles 11 of them, 57 ms (README: 54 ms).
  - PlainPlots loses 15 of 102: `limits(::Any)`, `pixels(::Any, ::Transform2D)`, `_xy(::AbstractVector, ::AbstractVector)`, `draw!`, `render_png`, `save`, all reached from `Dict{Symbol,Any}` attributes and `Vector{Any}` plots (`baselines/PlainPlots/src/PlainPlots.jl:104–110,161–177`). The next call recompiles 19, 137 ms (README: 100 ms).
- Mechanism (reasoning, standard Julia behaviour): at an abstract call site with one or few matching methods, inference descends into the callee, compiles it at the abstract types and records edges; a later load that adds a method to `size`, `getindex`, `convert` or a `Vector` constructor for a new array type invalidates the chain up to the entry. The trait form's ordinary layer uses the same `@nospecialize` entry (`src/TraitDifferentialEquations.jl:54`) but its chain ends two calls later at the trait module's entry, which plain inference cannot enter.
- What is missing: hardened baselines. PlainODE without `@nospecialize` on `solve` (then `_solve` is concrete per function and nothing abstract exists); PlainPlots and PlainTables with `Base.invokelatest` at their function barriers (`draw!`'s `pixels(pos, t)`, `describe`'s `summarize(t.cols[k], …)`, `parsecsv`'s `fillcolumn(T, …)`), which removes the edges at the cost of one dynamic call each. Until these run, "what the trait form adds: no load order changes its numbers" (`TraitDifferentialEquations/README.md:75`, `TraitMakie/README.md:53`, `TraitReport/README.md:5`) cannot be attributed to traits rather than to where the barrier sits. My expectation, not verified: the hardened PlainODE matches the trait form on row 1 after loads; the hardened PlainPlots and PlainTables come close. The honest claim would then be that traits place the barrier systematically and check it, where plain Julia needs the programmer to know each site.
- Fix: add the hardened variants as baseline (c) in each demonstrator; report the lost methods by name for every baseline (TraitReport's `scripts/invalidated.jl` already does this for (pt)); rewrite the three "what the trait form adds" sentences by the result.

### Significant

**S1. All headline numbers need the patched build; the stock magnitude is not in the headlines.**
- Stock: TraitMakie's first PNG 4.6–11.0 s (`TraitMakie/README.md:52`), TDE row 1 505 ms with loads before (`TraitDifferentialEquations/README.md:48`), TraitReport form (b) work 0.31 s (`TraitReport/README.md:33`). The plain baselines need no patch and keep their numbers on stock. So on today's Julia the trait form loses by one to two orders of magnitude.
- The overview says the policy's code is recompiled per session on stock (`1-overview.md:187`); the session note's "Headline numbers" (`:52–55`) and the README status lines say "patched" without the stock number beside it.
- The patch's own soundness (piece 5: machine code for foreign CodeInstances in package images; owner-aware edges; the inliner change) has no review outside this project. The demonstrators therefore demonstrate design + patch, and the READMEs should say which part each number needs. TraitReport already shows that piece 5 alone speeds up the plain package (`TraitReport/README.md:36`); this control should be run for PlainODE and PlainPlots as well.
- Fix: every headline carries "patched" and the stock number; a one-line table per demonstrator "stock / patched / system image".

**S2. Several numbers depend on a view cache, which is a per-user cache directory, not "code stored with the package that owns it".**
- Rows that need it: TDE row 6 (0.105 s in later sessions, `README.md:53`), TraitReport row 11 (44 ms, `README.md:92`, the status line `:5` does not say so); session 26's TraitMakie first PNG 62–65 ms relied on one and was 137 ms without (session note `:32`).
- The cache lives under `~/.julia/traitworld/views` as packages `TWView_<hash>` built by a detached niced precompile process (`TraitWorld/src/viewcache.jl:1–24`). Its build time, CPU cost and size are not reported anywhere. The sandbox killed the detached builds, so the reported numbers were taken after a manual foreground `viewcache_flush()` (session note `:22`), which a user would not do.
- The overview promises "compiled once per key, stored with the package that owns it" (`1-overview.md:87`). For the combination TraitTables' summary × InlineStrings' `String15` no package owns the code; the view cache is the ComboCache mechanism under another name, which the project itself classed as a workaround (`reviews/2026-10-17-demonstrators-under-facts.md:69`).
- Fix: report the view cache's build time and size per row; mark every view-cache number in the status lines; measure the first session (the one that pays) as the primary number.

**S3. Fresh-session headlines measure precompiled keys with workloads extended to the measured calls.**
- TDE's workload writes exactly the integrator fields the measured callbacks write (`src/TraitDifferentialEquations.jl:134–137`, added after "a second callback 25 → 5.4 ms", session note `:45`); TraitMakie's workload gained `:red` scatter per recipe after the 137 ms finding (`src/TraitMakie.jl:76`); TraitTables' workload gained `colnames` after `invalidated.jl` found it missing (`TraitTables/src/TraitTables.jl:70`, `TraitReport/README.md:79`).
- The plain baselines carry the same workloads and match: PlainODE 9.9 ms (row 1), PlainPlots 21–23 ms, (pt) 0.50–0.52 s. The READMEs state this in their baseline tables (`TraitDifferentialEquations/README.md:74`, `TraitReport/README.md:97`).
- But each README opens with the comparison against SciML (0.16 s), Makie (15.7–16.2 s) and pandas (0.58–0.69 s): a 300–700-line library with an exact workload against general libraries. The pandas comparison is additionally one of scope: TraitCSV parses `Int`, `Float64`, `String` with no missing values (`TraitCSV/src/CSVCore.jl:22–33`); pandas' reader is a full C parser (row 10's 1.5× says as much).
- Fix: open each README with the baseline-controlled number ("a precompiled key's first call; the plain baseline matches"), and move SciML/Makie/pandas to a "motivation" paragraph.

**S4. Row 11's CSV.jl comparison is not like for like.**
- `scripts/row11.jl:22` times `describe(CSV.read(path, DataFrame))`; the trait side times `summary_text` (`:18`). DataFrames' `describe` computes median, quantiles, `nmissing` and `eltype` per column and is itself heavy to compile. Row 3 gives `CSV.File` alone with DataFrames loaded as 2.46–2.53 s (`TraitReport/README.md:129`); so up to half of the "3.9–5.0 s" is `describe` and the DataFrame conversion, not the strings column.
- Fix: time `CSV.File` plus a hand-written mean/std/min/max/sum, and report CSV.jl's second session separately.

**S5. Claims of the overview with no demonstrator evidence.**
- *Simple AOT* (`1-overview.md:90–94`): the one binary is from session 25, before keys and wrapping by facts (4.07 MB in `TraitMakie/README.md:58`; the overview says 2.09 MB at `:94`); `--trim=safe` reports 26 errors; `verify_main` cannot see the workers in a session (`TraitMakie/README.md:56`); TDE row 12 and TraitReport form (c) are not built. Pay-off 2 has no current evidence.
- *No performance cliffs: an abstract type in a hot loop is reported at build* (`:97`): no row shows such a report. TraitMakie row 8 case 3 is an undeclared operation, a different check.
- *Threads*: no demonstrator uses them; assumption A4 (`:205`) is untested.
- *Revise-style edits*: not mentioned in any README or row. "Defining a small module after big loads takes 2.7 s" (`:204`) suggests redefinition at the prompt is slow.
- *Composable reuse at scale*: the largest composition is TraitCSV → TraitTables → TraitMakie, about 600 lines, one supertrait relation (`CSVColumn <: Column`). Nothing with many trait packages, deep hierarchies, or two independent libraries composed by a third party except the `String15` case, which lands in a view cache (S2).
- Fix: either add rows or state in the overview which pay-offs are untested.

**S6. The documents disagree with each other and with the source.**
- `1-overview.md:197–201`: acceptance "16 of 16" (session note `:51`: 15 of 16), first solve "55–60 ms" (README: 6.4–8.0), first PNG "87–97 ms" (README: 18–22). `:178`: a new loss "compiles the step again, as today" contradicts row 5 (flagged in the previous review, `reviews/2026-10-17-demonstrators-under-facts.md:28`, still unfixed). `:19`: "22 s … about 13 s recompiling Makie"; the cited experiment gives 21.2–21.7 s with 7.2–7.7 s recompiling (session 20) or 15.7–16.2 s with 5.1–5.4 s (session 21) (`experiments/interfaces/README.md:222–227,432–435`).
- `TraitDifferentialEquations/README.md:25–36`: "about 2,500 lines", modules `ODETsit5`, `ODERodas`, `LorenzModels`, callbacks `Bounce`, `RaiseSigma`. The source is `src/ODECore.jl` (545 lines) and `src/TraitDifferentialEquations.jl` (146); none of the named modules exists. `:3`: "a real, large library".
- `TraitMakie/README.md:27–41`: packages `CairoBackend`, `Plotting`, `UserPlots`; traits `Coords`, `Source`, `Backend`, `Transform`, `Layoutable`. The source has `PlotCore` and `TraitMakie` (395 lines) with the traits `Positions`, `ColorSpec`, `Plot` (`src/PlotCore.jl:20,37,127`). `:3`: "about a twentieth of Makie's size".
- `TraitReport/README.md:16`: "TraitMakie has no `barplot` yet" (it has).
- Fix: rewrite the Scope sections to the tree; refresh the overview's Status from the session note; fix `:178`.

**S7. Sample sizes and the noise floor.**
- TDE and TraitMakie rows are "single runs" (`TraitDifferentialEquations/README.md:44`, `TraitMakie/README.md:50`); the ranges are across load orders, not repeats. `measure.sh` defaults to 3 runs (`:17`); row 10 is best of 5; row 11 is a single run. No medians or spreads are given.
- The machine's between-session noise is large: the same ad-hoc Makie session measured 21.2–21.7 s (session 20) and 15.7–16.2 s (session 21), about 30%.
- Claims below this floor: "spread under 10%" (TraitMakie row 2 prediction), "equal within 5%" (row 9), (t) 0.52–0.56 against (pt) 0.50–0.52, TraitMakie 18.7–19.3 against PlainPlots 21–23 ms without loads. The READMEs mostly do not claim significance for these, but they are printed as if they were differences.
- Fix: at least 5 fresh processes per cell; report min and median; log the load average in the harness and discard loaded runs by rule, not by hand (`TraitReport/README.md:123` discards "such runs" without a criterion).

### Minor

- **M1. Harness asymmetry.** Python runs without `flock`/`nice` and with a warm-up run (`measure.sh:29,32`); Julia runs under both and without warm-up (`:56`). Effects are milliseconds; equalize anyway.
- **M2. TraitMakie row 9 measures Cairo.** 97–99 ms per drawing of 10⁵ points is Cairo's stroke; a 10% dispatch overhead in the data loop is invisible. Measure `limits`/`pixels` without drawing.
- **M3. Mixed Julia versions in the SciML column.** The stock numbers are from Julia 1.12.2 (`writeup/explorations/solvers.md:41`); some cells add 1.13.2 in brackets, others not (`TraitDifferentialEquations/README.md:46–52`).
- **M4. Frame counts in TDE row 9 are partly cosmetic.** TraitWorld hides its own frames through `update_stackframes_callback`; the SciML counts hide nothing. The row states the unhidden counts (21/42/34), which is correct; the comparison sentence should use them.
- **M5. Two metrics for "lost".** `experiments/facts/g2all.jl:37` counts only `FactsOwner` CodeInstances; `TraitReport/scripts/invalidated.jl:38` counts native and policy code of the libraries' own methods. The ordinary layers do lose native abstract specializations (by construction, as in PlainPlots); only `invalidated.jl` would show it. Use one metric.
- **M6. "On the system image" rows need a 248 MB custom `sys.so`** with a 25 ms startup cost (`experiments/sysimage/README.md`). Label them as such in the status lines; today they are presented beside the patched numbers as if equivalent.
- **M7. Rounding up.** "takes twice as long" (`TraitReport/README.md:5`) is 1.5–1.9× (`:69–73`).
- **M8. Task drift.** Python sets an x-label and 0.8× bar width (`experiments/interfaces/python/app.py:42,45`); `report_tables.jl` does neither. Negligible, but the task description says "the same task".

## What is solid

- **The mechanism of load-order independence is real and I could reproduce its negative in the baselines.** The plain libraries lose exactly their abstract-signature specializations; the trait libraries' workers are not reached by plain inference. TraitReport form (t): 0 of TraitCSV's, TraitTables' and TraitMakie's CodeInstances lost with nine packages before or after (`README.md:77–81`), and the work time agrees (66–80 ms in every order).
- **The order-of-magnitude rows hold against a documented SciML baseline.** A second callback closure 0.96 s and a second loss closure 2.48 s are measured as second closures (`ttfs_repeat.jl:17,21`); the trait form gives 13–29 ms and 17–21 ms on the patched build in every load order.
- **The baseline tables are candid.** They show where the trait form loses: `using` +0.17 s, a first callback +12 ms, a new type +0.1–0.2 s for the conformance's checks, the (t)/(pt) tie in a fresh session, 15% slower than OrdinaryDiffEq's fused loops at n = 1,000.
- **Readable types** (row 10: `Tsit5Integrator{Float64, Vector{Float64}}` against 3,553–24,426 characters) and **shorter traces** (row 9: 12 frames and 289 characters against 29 and 3,789) are measured, not predicted.
- **The harness is careful** where it counts: fresh processes, raw timestamps subtracted outside the process, one Julia job under a lock, environments precompiled before measuring, the view cache switched off for the headline fresh-session numbers (`TraitReport/README.md:63`).
- **The fact rule for type-valued arguments looks sound** (`TraitWorld/src/facts.jl:48–69`): `DataType`/`UnionAll`/`Union` are admitted as fact parameters only for closures, which have one method. Read, not tested.

## Next experiments, ranked

1. **Hardened plain baselines (decides B2).** PlainODE without `@nospecialize` on `solve`; PlainPlots and PlainTables with `Base.invokelatest` at their function barriers. Rerun `scripts/baseline.jl` and `scripts/loads.sh`; list lost methods by name for every library. If the hardened baselines match the trait form, the claim narrows to "systematic, checked barriers"; if not, the attribution to traits stands.
2. **REPL rows (decides B1).** The same rows started as `julia -i` or with `using REPL` first: precompiled key, new type, `Float32` state, `String15` column; patched without and with the system image; stock. This is the user's actual session.
3. **First-session and view-cache costs (S2).** For rows 6 and 11 and a new colour type: wall time to first use including the background build, CPU seconds of the build, size on disk, and whether the second session finds the cache ready. Report the first session as the primary number.
4. **Composition at scale (S5).** Twenty small trait packages with conformances across them, loaded in random orders: `using`, `@implement`, first call, policy and native code lost, and the machinery's own loss (about 190 of 2,064 CodeInstances, `TraitReport/README.md:81`) felt at the first new key without the system image.
5. **Pay-off 2 and edits (S5).** Rebuild the three binaries under the current design with `--trim=safe` (TDE row 12, TraitMakie row 7, TraitReport form (c)); and one Revise row: edit `summarize` in TraitTables, time and check the next call.
