# Porting the workload's path: SciML and Makie, for load and first use

Status: **proposal, revision 2** (2026-10-27, mine; W-58 phase 5): after [the fresh-eye review](../reviews/2026-10-27-cache-and-port-notes.md) (§7) and E-175, E-176 (§2b). Not normative.

Serves: W-58 ([the plan](2026-10-27-ttfx-sciml-makie.md) §5, phases 5–6); [the cache note](2026-10-27-session-cache.md); open issue 72.

Builds on: [the SciML exploration](../explorations/sciml-as-traits.md) (moves 0–5, §4), [the porting guideline](../intro/porting.md) (B6, the solvers an open set), [the W-34 plan](2026-10-21-w34-sciml-prerequisites.md) and its prototypes (E-156 to E-161), [the Makie rewrite](../explorations/makie-rewrite.md) (written before keys replaced representations: read "representation" as the key, "projection" as forwarding).

## 1. The goal and the constraint

The user (2026-10-27): the demonstrators are not enough; "We need the former here": a port with upstream's features and API, called the same way. The workload's script (`experiments/ttfx/workload.jl`) runs unchanged on the port: `ODEProblem(f, u0, tspan, p)`, `solve(prob, Tsit5(); saveat, reltol, abstol)`, `Rodas5P()`, `sol.t`, `sol.u`, `sol(t)`; `Figure`, `Axis(…; xscale = log10)`, `lines!`, `save(path, fig; px_per_unit)`.

## 2. What the measurements require of a port

From E-168 to E-174 (`experiments/ttfx/README.md`):
1. **No type of the user's script in the library's keys.** Stock SciML keys its solver on `typeof(f)` through `ODEFunction{iip, specialize, F, …}` and `ODEProblem{…, F, …}`; no cache can keep that code (E-172). With the function out of the types (`NoSpecialize`, a stand-in) and a cache across sessions, the first solve takes 0.30 s instead of 8.2 s and a second model 0.08 s (E-174).
2. **Few call shapes at the entry.** Stock SciML's solver is keyed on the shapes of the call: the keywords' `NamedTuple`, the type of `saveat`, the parameters' type. A cache from one shape leaves another compiling 6.3 s (E-173). The entry normalizes what it can; what it cannot (the parameters' type, which the right-hand side reads) is a key the cache pays once.
3. **Code keyed on library types, compiled by facts,** so that a cache across sessions keeps it and it stays valid in any load order ([the cache note](2026-10-27-session-cache.md)).
4. **No added load.** The load is what remains (3.7 s of a 4.7 s session in E-174). The port must not add to it:
   - TraitWorld's own hooks compiled at each session's first load cost 0.36 s until fixed (TraitWorld 04095fe);
   - compiling SciML by facts added 1.0 s to the load (C against U, E-168), and strict mode's check 6.6 s more.
   How the load itself shrinks is the cache note's and phase 3's question (E-170), not the port's.

## 2b. Revision 2: the load first

E-175 and E-176 change the order:
- **With a cache across sessions, the work after the load is about Python's** in every setting (stock SciML and CairoMakie: 1.1 s after the load, Python 1.0 s): SciML's `AutoSpecialize` already keeps the user's function out of the solver's code below the entry, so move 1 is not needed for first use on this path.
- **The load is the tree** (E-176): stock's load follows the methods its 381 packages add (80,263; 27,681 extend other packages' functions). The plotting tree is most of it: `using CairoMakie` 2.7 s and 261 packages; the solver's 1.09 s and 156 packages, of which Tsit5 alone 0.34 s and 83. Python imports SciPy and matplotlib in 0.45 s.
- **So the port's first aim is a smaller tree for the workload's path,** with a budget: a plotting core that loads in about 0.5 s and a solver in about 0.4 s, the rest of each library loaded only by the features that need it (extensions, separate packages). A trait core is what makes the split possible: a narrow, declared interface between the core and its recipes, backends and algorithms, instead of methods of the core's functions spread over the tree.
- Strict mode's check at load (6.6 s in C) is the other load item; its intended design is facts §10.3's.

**A first estimate** (E-176, `probe_floor.jl`): the dependencies the workload's plot plausibly needs (colours, geometry, observables, the compute pipeline, the layout solver, fonts, tick placement, number formatting, Cairo, the PNG writer) load in 0.51 s (66 packages), 0.72 s with Makie's default text engine (83), against CairoMakie's 2.7 s (261). A core with its own code on that tree might load in about 1 s.

The solver's floor (E-176): Tsit5, ForwardDiff and DiffEqBase 0.47 s (98 packages); Rosenbrock's tree adds 0.73 s (55: the linear-solver tree). A Rosenbrock method on small dense systems needs a dense LU, not LinearSolve's choice of solvers; that choice can be an extension.

Next: which of Makie's 261 packages the workload's plot needs (`Figure`, `Axis` with a log scale, `lines!`, a PNG through Cairo), and which come with features it does not use (statistics recipes: Distributions, StatsBase; units: Unitful; interval arithmetic; sparse arrays; REPL; Pkg through FileIO). The same for the solver: what Rosenbrock's 73 extra packages bring that a dense LU on small systems does not need.

## 3. SciML: the moves in the order that pays for first use

**Move 0, done:** SciML's core wrapped by facts, inside out (P6's trees; setting C). It gives the guarantees, not the shape.

**Move 1, first:** the right-hand side as a trait, the function kept at a `Callable` bound ([the exploration](../explorations/sciml-as-traits.md) §4, move 1; TDE's `ODEProblem`).
- `ODEFunction`'s `F` becomes a bounded struct parameter, `F <: Callable{RHSSig{U, P, T}, Nothing}` for the in-place form; the constructor applies the bound, so `F` is `Dynamic{Callable{…}}` by default and the same type for every function. `FullSpecialize` becomes `compiled_for(f)` at the constructor; `AutoSpecialize`'s wrapper and `promote_f` go.
- Rosenbrock methods call the function at the duals of a Jacobian: a second bounded parameter per signature, as TDE keeps `fd` (W-34's form B), or the tuple of `Callable`s when W-29 is built.
- The user's call is unchanged: `ODEProblem(f, u0, tspan, p)` and `ODEFunction(f; jac)` construct as before.
- Expected: E-174's numbers without `NoSpecialize`'s run-time cost, and with the signature checked.

**Move 1b: the options normalized at the entry.** `solve(prob, alg; kw...)`'s keywords become one typed options record before the integrator is built:
- `saveat` as a `Vector{T}` of the time type, whatever the user passed (a range, a tuple, a number);
- tolerances at the state's element type;
- the integrator's type independent of the keywords' `NamedTuple` (today `DEOptions` has 23 type parameters, several from keywords).
- The entry itself is compiled per keyword shape, as today, but it is small: a function barrier, as TDE's `solve` (`@nospecializeinfer`).
- The parameters' type stays a key: the right-hand side reads it.

**Move 5: the solution independent of the function.** `ODESolution` keeps the problem with its kept function, so the solution's type has no `f` axis, and `sol(t)`, `sol.t`, `sol.u` and plotting code are compiled per key. Needed for the plot step's share of the cache.

**Moves 2–4** (callbacks and the integrator view, the front end's ownership, symbolic access) are not on the workload's path; they stay in the route's order after it.

## 4. Makie: what first use needs, and the porting order

**What the measurements say:**
- Makie's code on the plot path is keyed on library types (`Vector{Float64}`, `Point2f`, `typeof(log10)`, Makie's own types): the emulated cache cut the first plot from 1.56 to 0.48 s for plain code (E-172, E-174). What stays is the user script's own code (`plot_two`, compiled per session, a floor) and the PNG writer's keyword path.
- Makie's load is 0.71 s of S's 3.2 s summed imports, and its dependency tree is most of the 381 packages (E-169).
- A cache of plain Makie code depends on the load order (the combination caches, session 20). Compiled by facts, it does not.

**The order:**
1. **Makie and its tree wrapped by facts** (move 0, as P6 did for SciML), with the cache across sessions: what was measured for plain code, made order-independent. The wrapped tree's own costs to measure: the facts mode's compile in the session and its load (CairoMakie under `all`: 4.9 against 1.9 s, evidence §3, not diagnosed; E-169 asks why).
2. **The typed front** ([the Makie rewrite](../explorations/makie-rewrite.md) §7, step 2): the user's data and attribute values cross into Makie by bound (`Coords`/`Positions`, `ColorSpec`, `Transform` for `xscale`), so Makie's internals are keyed on library types by construction, not by Makie's habit. `lines!(ax, x, y)` keeps its call.
3. **`PlotCore`** (the rewrite's §7, step 3): the plot object, the conversion pipeline and the typed compute graph as trait code, with `Axis` and the layout ported from Makie's algorithms; CairoMakie as the backend. This is where the dependency tree can shrink (a narrow waist: recipes and backends never meet in compiled code), and so where the load can.
- Steps 1–2 serve first use now; step 3 serves the load and the design's other pay-offs, and is the large one.

## 5. Phase 6, re-scoped

1. **SciML move 1 and 1b in P6's trees** (the C setting's packages, already wrapped): `ODEFunction` and `ODEProblem` with the bounded function, the options record, Rosenbrock's dual signature. Results bit-equal to upstream (the port's digests). Measured in the workload: C with the cache against C, U and Python.
2. **Makie wrapped by facts** in the same environment, with the cache.
3. **The cache across sessions** as a prototype ([the cache note](2026-10-27-session-cache.md) §3), split by dependency set, so order B is testable (E-173).
4. Then the typed front for Makie (§4, step 2).

## 6. Questions for review

- Is move 1b's options record compatible with SciML's interface (`init`, `step!`, `reinit!`, `remake` keep the keywords), or does it need a deviation?
- Does keeping `F` bounded in `ODEFunction` break the code that reads `f.f` (SciMLBase's `unwrapped_f`, `get_concrete_problem`, extensions)?
- Is wrapping Makie's tree by facts feasible as P6 was for SciML (pirates by the letter in Makie's tree; extensions such as `IntervalArithmeticMakieExt`)?

## 7. The review, and what is done with it

[The review](../reviews/2026-10-27-cache-and-port-notes.md) (fresh eyes, Opus, 2026-10-27):
- **B1** (the evidence for move 1 coming first rests on an emulation that kept compile roots only): accepted and confirmed by E-175: stock's `AutoSpecialize` already makes the solver cacheable (the perturbed session with a cache 4.9 s). Move 1 is not needed for first use on this path; it stays in the route for its other pay-offs (the signature checked, no hand-written wrapper).
- **M6** (the order does not follow the goal: the load is 3.7 of 4.7 s): accepted, §2b: the load comes first, and for the port that means the tree.
- **M7** (user types still reach the keys after the moves): the parameters' type stays a key by design (the right-hand side reads it); callbacks and `DEOptions`' function fields are move 2's, off the workload's path; the Rosenbrock chunk is chosen per state length (TDE), not per user type; Makie's compute graph is keyed on attribute values' types, the user's own where the user passes them. Listed for the next revision.
- **m4** (move 5 against the SciML exploration's "not needed for the workload after move 1"): accepted: move 5 is needed only if the solution's type still names the function after move 1.
- **m5** (E-174's baseline): the perturbed auto-specialized session's first solve is 5.3 s (S/p), not `NoSpecialize`'s 8.2 s; the 0.30 s compares with 5.3 s.

