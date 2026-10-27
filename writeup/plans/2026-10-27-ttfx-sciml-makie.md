# Load and first-use time of a large trait world: SciML and Makie

Status: **adopted** (2026-10-27, mine, under the user's direction below); revision 2 after [its fresh-eye review](../reviews/2026-10-27-ttfx-plan.md) (§7). Not normative.

**Where it stands (2026-10-27):** measured E-168 to E-179. Python's session 1.45 s; stock SciML and CairoMakie 9.2 s; the trait demonstrators 0.96 s. A cache across sessions (emulated) brings the work after the load to about a second, per call shape. The load is Makie's own code (a lean fork without its heavy dependencies saves 0.4 s). Compiled by facts, Makie keeps its code across a later load (6.1 → 0.02 s). Next: the architect's memo on a lean core that keeps the old APIs (W-60), and the wrap-up before the ports (W-61).

Serves: [W-58](../record/todo.md); E-168 to E-177; open issues 72 to 75.

## 1. The goal

The user (2026-10-27): "I would like to get back to looking at load and TTFX times as a whole in a large port setting say (SciML+Makie). With a large solid trait core that is amenable to cross session caching, there should be no reason that loading+running first simulation+plot should be slow. We could take SciPy + matplotlib as a baseline for this, too. […] We need the porting strategy architecture for Makie. But I would now focus on things that directly contribute to this as a next step. Leave ND.jl out for now as it doesn't have a Python analogue."

The user also (2026-10-27): "Remember to design experiments that give feedback quickly. Nothing that runs for hours."

The user then (2026-10-27), on setting D: "Is TraitMakie/TraiteDE a full port of either with all features? Called like the upstream packages are? Or ist it rather a trait version of PlainODE? We need the former here." And: "I also care about why traits don't buy anything for small libraries? Is that because everything is on the precompile workload? This isn't really realistic for large scale packages (as the workload example shows), and traits gradually built up cache that lasts from session to session is exactly what should help here. The fact that all slowness can be fixed by the right precompilation doesn't really matter."

So:
- **D and Dp are references for small libraries, not ports.** TraitDifferentialEquations and TraitMakie are trait versions at PlainODE's and PlainPlots' scale, with their own APIs (Tsit5 and Rodas5 only, their own solution type; no `Figure`, `Axis`, layout or log axis). The goal needs a port with upstream's features and API on the workload's whole path, called by the same script as stock (phase 6).
- **Precompile workloads are not the premise.** A large package cannot cover its users' call shapes in a workload (stock SciML's first solve: E-169). The lever to test is a **cache that builds up across sessions**: code compiled by facts in a session, keyed on trait keys and not on the user's own types, kept for the next session. Facts make it valid in any load order; trait keys make it reusable. Phase 3a measures it first (E-172). It was raised before: W-47's exploration ([`fast-loads.md`](../explorations/fast-loads.md) §3 item 5, merged here), and built for plain code as combination caches and view caches ([alternatives](../design/alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed)); the design question is [open issue 72](../open-issues.md#2-design).

The user then (2026-10-27), on keeping old APIs over a lean trait core: "I think SciML Problem and Algorithm are more tolerable to require a change by library authors. On everything else I basically agree." And: "Can we reasonably demonstrate and continue work on traits and everything without having the large scale ports? If so it might be worth wrapping up what we can before moving into that." An architect's memo on the lean core with old APIs is W-60; the wrap-up before the ports is W-61.

So the measure is one fresh session, start to exit: load the solver and the plotting library, solve, plot to a file, then change the model and do it again. The baseline is the same session in Python.

## 2. The workload

One script per language, the same steps, the same numbers out:

1. **Load:** the solver and the plotting library.
2. **First simulation:** a non-stiff problem (Lorenz, an explicit Runge–Kutta method: `Tsit5`; SciPy `RK45`) and a stiff one (Robertson, a Rosenbrock method: `Rodas5P`; SciPy `Radau`), at the same tolerances, saving at fixed times.
3. **First plot:** the two solutions as lines on two axes, saved to a PNG (CairoMakie; matplotlib's Agg backend).
4. **A second model:** a new right-hand side (Van der Pol, stiff), solved and plotted again.
5. **Again:** steps 2–3 repeated, the steady state.
6. **Exit.**

- **The same argument shapes everywhere:** `Vector{Float64}` parameters and saving times, as Python passes them.
- **Variants,** one session each: **perturbed** (`/p`: `Tuple` parameters and a range of saving times; what the user's ordinary choices cost, against cached keys); **order B** (`/b`: the plotting library loaded after the first simulation, the common order where Julia's load order matters and Python's does not).
- **Outputs:** 800×600 and 800×400 pixels (CairoMakie with `px_per_unit = 1`); each PNG's size is logged. D and Dp write two PNGs on linear axes for the first plot (TraitMakie and PlainPlots have no layout of two axes, no log axis), and use Rodas5 for Rodas5P.
- **Digests** (the values at chosen times) are printed after the last timed step, with the versions of everything loaded. They agree across settings per component within a relative 1e-3, with an absolute floor of 1e-6 (100 times `abstol`: Robertson's second component is barely resolved).

## 3. The target

- **The baseline:** the Python session, warm: 1.45–1.46 s from before the process starts to the end of the last step (load 0.45, first simulation 0.07, first plot 0.51, a second model 0.24, again 0.17; E-168, a warm-up and two sessions).
- **The target for a trait world of SciML and Makie:** the whole session within twice Python's, about 3 s. A first milestone, not the end: the claim is that nothing in the trait design forces it above Python's.
- **The design's predictions, per step,** which the phases confirm or refute: load at most 1.2 s (the load budget: Python's share of its session); load plus first simulation plus first plot at most 2.2 s; a second model at most 0.3 s; the perturbed variant within 0.2 s of the matched one (the core normalizes at its entry, as TDE's `solve` does); the order-B penalty about 0 under facts.
- **Against Python, only totals compare:** the whole session, and load plus first simulation plus first plot. Python defers work to first use (matplotlib's backend loads inside the first plot); Julia does it at `using`. Steps compare between Julia settings.

## 4. The settings

- **Python:** SciPy and matplotlib (`experiments/ttfx/pyenv`, versions in each log).
- **S:** stock Julia 1.13.2, upstream OrdinaryDiffEq (`OrdinaryDiffEqTsit5`, `OrdinaryDiffEqRosenbrock`) and CairoMakie, with their own precompile workloads.
- **U:** the same packages on the patched build, product setting.
- **A:** the same under `all` (needs the facts system image rebuilt, alone; added when it is).
- **C:** upstream SciML's code compiled by facts as trait modules (P6's trees, wrapped inside out; no trait code), with Makie from the port's clones, on TraitWorld main (bbfc130, its first run with these trees). Its question is narrow: does compiling upstream SciML by facts change load and first use? Its Rodas5P solves carry open issue 66 until W-57 is built.
- **D:** the two demonstrators, TraitDifferentialEquations and TraitMakie: a small trait core written as idiomatic trait code.
- **Dp:** the demonstrators' plain twins, PlainODE and PlainPlots: the same features without traits.
- **Strict mode** is off in every setting; C and the phase-6 prototype also run with it on (`/s`).
- **Three comparisons:** features and size (S against Dp), the trait design (D against Dp), the facts mode (U against A; C against U).
- **Harness:** one depot per setting; Julia with `--compiled-modules=existing --pkgimages=existing`, so a missing image is never compiled inside a measured session, and a log that shows precompiling or a rejected image is invalid; a timeout of 300 s; one discarded warm-up session per setting, then two measured (three where a decision hangs on a difference); two cores; one Julia job at a time. The build is frozen for phases 1–3 (julia-1.13 252edca933); a rebuild happens between phases, followed by precompiling everything again, alone.
- **Setup, counted apart:** precompiling a setting takes 3–6 minutes; the facts system image for A is a full build, alone.

## 5. The plan

Every experiment runs in minutes: one fresh session per setting first, three only where a decision hangs on a difference. Nothing runs for hours. Each phase ends with a decision written into this note.

**Phase 1, where the time goes (E-168).** The workload in every setting, matched, then `/p` and `/b`, per step: wall, compile and GC time.
- *Decides:* the three comparisons of §4; whether load, compilation in the session or run time dominates, per step; which of §3's predictions already fail.

- *Outcome (2026-10-27, E-168; `experiments/ttfx/README.md`):* sessions D 1.29–1.30 s against Python's 1.45 s, Dp 1.13 s; S and U 9.1–9.2 s, C 10.9 s. Predictions: S, U and C fail the load budget (3.5–4.5 s) and the first three steps (8.8–10.6 s); D meets them (load 0.81, first three steps 1.1 s, second model 0.056 s) but fails the perturbed one (+1.35 s: its solver is keyed on the parameters' type); order B costs about 0 under facts (C: again 0.04 s, against U's 0.44 s). Strict mode adds 6.6 s to C's load.
- *Decision:* phase 2 attributes, in this order: S's first solve (3.75 s compiling) and first plot (1.4–1.6 s), which upstream's own workloads do not cover; the load of S and C (3.5 and 4.5 s); D's 0.41 s compiling at load. Phase 4 takes two inputs already: the core's key on the parameters' type (class (f)), and strict mode's load cost (its intended design at image validation, facts §10.3, is needed for the target).

**Phase 2, what is spent in the session, and why (E-169).** One attribution run per setting, not timed:
- a sampling profile of each step, C frames included, the load split into reading files, deserialization, method insertion, validation of edges and facts, TraitWorld's hooks and callbacks, `__init__`;
- `@time_imports`; `JULIA_DEBUG=loading` (images rejected); the CodeInstances lost to each load (invalidation);
- the CodeInstances created per step, by owner and module (`ndport/scripts/diag.jl`); `--trace-compile` with timing for the roots.
- Each piece of compilation in the session is one of: (a) in no image; (b) in an image that was rejected; (c) in an image invalidated by a later load; (d) cached under the other owner; (e) keyed on a type of the user's script (`Main`); (f) keyed on the shape of the call (keyword types, containers, the parameters' type, attribute values). (a)–(d) are caching failures; (e) is the floor the design must address; (f) is a question for the core's entry: normalize at the boundary, or key on it.
- *Decides:* the classes' shares per setting; where load time goes; why CairoMakie loads 4.9 s under `all` against 1.9 s plain (evidence §3, not diagnosed), since the intended core loads as facts images.

*The phases below are in the order they were run: 3a, 3c, then the earlier 3 and 3b.*

**Phase 3a, a cache across sessions, emulated (E-172).** Before any design work: a perturbed session (off the workloads' keys) traced; the statements it compiled that do not name `Main` put into a precompiled package loaded with the stack; the perturbed session again, in D, Dp and S.
- *Decides:* how much of an off-workload session a cache across sessions can remove, per setting. The traits' contribution is the difference between D's recovery and Dp's and S's: what stays keyed on the user's own types (`Main`) cannot be kept.

- *Corrected by E-175* ([the review](../reviews/2026-10-27-cache-and-port-notes.md) B1): the emulation kept compile roots only. Recorded at the level of CodeInstances, a cache takes stock's perturbed session to 4.9 s, the trait demonstrators' to 1.16 s, the plain twins' to 0.64 s: with a cache, every setting's work after the load is about a second or less. **The load is the question now** (3.7 s for stock); the next phase measures and designs for it.
- *Outcome (2026-10-27, E-172; superseded by E-175, the roots-only emulation's artefact):* perturbed sessions with the cache: D 2.63 → 1.52 s, Dp 1.83 → 0.70 s, S 12.9 → 11.7 s. What can be kept is decided by the key: S's solver code is keyed on the user's function type and none of it can be kept; Dp's solver sees the function behind a `FunctionWrapper` and all of it is kept.
- *Decision (superseded by E-175: stock's code is as cacheable):* a cache across sessions pays exactly where the core erases the user's own types at its boundary. That is the traits' structural claim (every bound erases or keys on library types, checked), against plain code where erasure is by hand and partial (SciML's `AutoSpecialize` erases inside, but its outer layers keep `typeof(f)` in the problem's type). At the small scale both get it; the difference must show at scale (phase 6), and phase 4 designs the cache with that key discipline. D's remaining 0.18 s in the first solve and its load (0.9 s) go to phase 2.

- *Outcome (2026-10-27, E-174; read with E-175):* at upstream scale, with the user's function behind `NoSpecialize` (a stand-in for move 1 of the SciML route) and the emulated cache, stock SciML's perturbed session falls from 12.9 to 4.7 s: first solve 0.30 s, second model 0.08 s; after the load 1.03 s against Python's 1.00 s.
- *Decision (revised by E-175, which shows the same without `NoSpecialize`):* the premise holds for SciML's path: erase the user's types at the boundary, keep the rest across sessions. **The load becomes the main question** (3.7 s of 4.7 s): phase 2's load profile of S and C comes next, before more design.

**Phase 3c, the load (open issue 73).** After E-175 the load is the question. Measured: where it goes (E-169's profiles of S and C), the facts share of loaded code (11% in C), and that a system image of the stack cannot be built here (E-170). The options are open issue 73's. Done since: E-171 (a trait world's load grows slowly with its size) and E-176 (the load follows the tree).

- *Outcome (2026-10-27, E-176):* the load follows the methods the stack adds, that is its tree: `using CairoMakie` 2.7 s and 261 packages, the solver 1.09 s and 156. The floors: a plotting core's dependencies 0.51–0.72 s (66–83 packages), the solver's 0.47 s (98). An estimate for a port on lean trees with a cache: about 2.6–2.7 s as a lower bound; with Makie's and Rosenbrock's own code, TraitWorld and the facts mode at load and the cache's own load, about 3–4 s, strict mode off, and the load (at least 1.6 s) above §3's budget of 1.2 s ([the direction review](../reviews/2026-10-27-w58-direction.md) 5).
- *Review ([the direction review](../reviews/2026-10-27-w58-direction.md) 1):* every pair measured so far favours plain code (with a cache Dp 0.64 against D 0.97 s; load Dp 0.16 against D 0.45 s, S 3.52 against C 3.85 s), so lean trees are no trait hypothesis by themselves. The trait-specific claim on this path is that cached facts code stays valid when parts of a lean tree load late: E-177 tests it first.
- *Outcome (2026-10-27, E-177):* the trait-specific claim holds on this path: after a late load the plain twins recompile 0.04 s of cached code, the trait code nothing (at the large scale, without a cache: 0.44 s against 0.04 s, E-168). Small at this scale; it grows with the code later loads would invalidate.
- *Outcome at scale (E-177):* a later DataFrames load makes the plot recompile 6.1 s where Makie is plain (S, C), 0.02 s where it is compiled by facts (A). The facts mode's protection is large on this path; its price is the facts images' load (A 8.2 s against 3.6 s).
- *Done (W-59):* facts images loaded slower because they kept specializations without a hash (the documentation system's `push!` of signature types), each inserted by a linear scan; images no longer keep them (julia-1.13 6800be7839): the load under `all` 8.2 → 3.8 s, the protection kept.
- *Decision:* the port's first aim is lean trees for the workload's path ([the port note](2026-10-27-port-architecture-ttfx.md) §2b), with the cache across sessions ([the cache note](2026-10-27-session-cache.md), revision 2) for the work after the load. The loader changes of open issue 73 are a second lever, not a prerequisite.

**Phase 3, the ceilings of caching today (E-170).** Two points:
- the compiled statements of phase 2 that do not name `Main` put into a precompile workload of a small package loaded with the stack;
- one system image of the whole stack (built alone, under the memory guard).
- *Decides:* what package images can remove, what remains keyed on `Main` (the floor), and what loading machinery costs (the difference between the two ceilings). If loading dominates what remains, the next work is load time (image size, validation, hooks), not compilation.

**Phase 3b, the scale probe (E-171),** run beside phase 2: a generated trait module with N implementations and M bounded functions, at 10 and 100 times TDE's, with a workload. Image size; `using` with strict mode off and on; a first call at a cached key and at a new key.
- *Decides:* whether load grows faster than the image's size, or strict mode's load cost grows with the world (E-165: 2.9 against 7.9–8.1 s). Either fails the premise before any porting.

**Phase 4, the design note: a trait core amenable to caching across sessions.** From phases 1–3b, first the cache that builds up across sessions (what is written, where, when, keyed how, validated at load how; its interaction with package images and the facts edges); then: which code the core's images keep and at which keys (the model `Dynamic`, as in TDE; the solver compiled per state and parameter type); how the entry normalizes call shapes (class (f)); what a user's model and data compile anew (class (e)); what each session costs whatever is cached (TraitWorld's per-session work: the session stamp, the untyped tables, `Callable` pointers made at the first call: lowering §9.3, §12, §16); what loading costs (facts §11's validation, the image hook, the load callback; strict mode's checks, and whether its intended design at image validation, facts §10.3, is needed for the target). A fresh-eye review.

**Phase 5, the porting architecture for Makie.** Scoped by phase 2's attribution of the plot steps in S: which of Makie's layers (the conversion pipeline, `ComputePipeline`, recipes, attributes, layout, text and ticks, the Cairo backend) become trait code, at which keys, what stays plain; TraitMakie's lessons. A fresh-eye review.

**Phase 6, the port of the workload's path, at upstream's features and API.** The workload's whole path through SciML (`ODEProblem`, `ODEFunction`, `solve` with its keywords, Tsit5 and Rodas5P with their caches, interpolation, `ODESolution`) and Makie (`Figure`, `Axis` with a log scale, `lines!`, layout, ticks and text, attributes, CairoMakie's `save`) as trait code, called by the same `workload.jl` as stock, with the cache across sessions of phase 4. It needs the porting architectures for SciML and for Makie first (phases 4–5). Earlier wording, for reference: The workload's path through the SciML core with the model `Dynamic` (W-34's forms), and the slice of Makie the plots use, including the components phase 2 finds expensive (or the note says why the trait design does not reach them); as trait code, measured in the same workload, strict mode off and on.

**Pushback** found on the way (the design or the user's direction meeting the code) goes to `open-issues.md` with the evidence, and is listed in this note.

## 6. What is left out

- NetworkDynamics (no Python analogue).
- The detailed performance issues found so far (open issues 66, 71, W-57's sweep): pursued only where (1) shows them on this path.
- Upstream proposals (the user, 2026-10-27: "We are not proposing anything upstream yet.").

## 7. The review's findings and what was done

[The review](../reviews/2026-10-27-ttfx-plan.md) (fresh eyes, Opus, 2026-10-27), before any Julia session was measured (the first launch was stopped):
- **B1** (hidden precompiling; S's depot): one depot per setting, `--compiled-modules=existing --pkgimages=existing`, invalid runs flagged, timeout 300 s, versions printed in the session, the build frozen for phases 1–3 (§4; `experiments/ttfx/run.sh`, `summarize.py`).
- **B2** (shapes favouring D): matched shapes everywhere, the perturbed variant (§2).
- **M1:** setting Dp, the three comparisons (§4). **M2:** the load budget and predictions (§3), the load profile in phase 2. **M3:** strict mode stated per setting, `/s` (§4); its load cost in phases 3b and 4. **M4:** phase 2's tools and the six classes. **M5:** class (f), phase 4. **M6:** order B (§2). **M7:** phase 3b; phase 6's slice. **M8:** C's question narrowed (§4), its own depot, E-168's row corrected. **M9:** a warm-up, then two runs (§4). **M10:** two ceilings in phase 3, the floor (e).
- **Minor:** digests and versions after the last mark (m1); pixels matched and logged, D's differences stated (m2); totals only against Python (§3, m3); the digest tolerance (§2, m4); E-168 corrected and E-169 to E-171 registered (m5); one environment for D and Dp (m6); predictions and setup costs (§3, §4, m7).
