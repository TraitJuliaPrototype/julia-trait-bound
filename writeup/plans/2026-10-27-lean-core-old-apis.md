# A lean trait core that keeps the old APIs: SciML and Makie

Status: **proposal, revision 2; its answers to open issues 75 and 77 adopted** (2026-10-27, by the clean-up W-65: extensions for keys and loading stubs for functions; entries through `invokelatest`; [decisions](../record/decisions.md) §8) (2026-10-27, mine; W-60): after [its review](../reviews/2026-10-27-lean-core-memo.md) (§7), the user's direction on SciML ([decision log](../record/decisions.md) §8) and W-63 (E-181). Not normative. Revision 1 (d734721) read the references, W-58's measurements and upstream's source; revision 2 adds E-179's attribution, E-180 and E-181.

Serves: [W-60](../record/todo.md). The user (2026-10-27): "Have we figured out a way to keep old APIs l, both super facing and for library authors (e.g. recipes) while keeping the core genuinely lean and clean trait code with open sets as traits? Is that worth sending an architect agent out for?"; "I think SciML Problem and Algorithm are more tolerable to require a change by library authors. On everything else I basically agree."; "Regarding SciML, I would like to keep the user API but not necessarily the solver and algorithm developer API. Though a compatibility shim would be great. I also think we can figure out something elegant for the parameters. The outermost layer has to depend on parameter type, but inside the solver we only need to see the right hand side that is partially evaluated on the parameters." Also serves [W-58](2026-10-27-ttfx-sciml-makie.md) (its goal, §1) and W-61 (§5), open issues 72–77.

Builds on, and replaces where they disagree (their status lines say so when this memo is adopted):
- [the port note](2026-10-27-port-architecture-ttfx.md) §4–§5 (revision 2);
- [the Makie rewrite](../explorations/makie-rewrite.md), read with "representation" as key and "projection" as forwarding;
- [the SciML exploration](../explorations/sciml-as-traits.md) §4, and [porting B6](../intro/porting.md#b6-case-study-scimls-architecture-as-traits);
- [loading on demand](../explorations/load-on-demand.md) (open issue 75, option (ii));
- [the cache note](2026-10-27-session-cache.md) (revision 2, as built);
- [the parameters at the surface](2026-10-27-parameters-outer-layer.md) (W-63, done).

Numbers are quoted with their experiment IDs; their home is [the evidence](../design/evidence.md) §3, which names builds and settings.

## 0. Summary

- **Yes, with two levers the port notes lack.** The lean `using CairoMakie` (E-179) takes 2.3 s: Makie's own images 0.89 s, and 165 other packages 1.19 s, some of which come back through others (SparseArrays through Interpolations, REPL through MathTeXEngine, Pkg through FileIO). So:
  - **most of Makie's own code loads by use, not at `using`;** the API's names stay at `using`;
  - **the tree the core keeps is pruned by what each package brings,** not only by Makie's direct dependencies.
- **Four layers, for both libraries:**
  1. a **trait core**: a trait module with the open sets as traits, the core's own concrete types, and the bounded functions that do the work;
  2. **implementation packages**: recipes, blocks, backends, algorithms. Each implements the core's traits for its own types;
  3. a **compatibility layer**: ordinary code that runs the old author APIs above the core. For Makie, the old recipe API (`@recipe`, `plot!`, `Attributes`, `lift`, `map!`, `convert_arguments`, `SpecApi`). For SciML, a shim for the old algorithm API (the user: "a compatibility shim would be great");
  4. the **user API**: a thin ordinary layer with upstream's names and calls. It parses keywords into typed records, normalizes call shapes, partially evaluates the user's functions on the user's types (W-63), and holds loading stubs.
- **Who keeps what:**
  - **users** keep upstream's calls, in both libraries;
  - **Makie's recipe authors** keep their API: old recipes run as upstream's code in the compatibility layer, above the core;
  - **SciML's callback authors** keep theirs: the integrator view declares what DiffEqCallbacks reads (§1.3);
  - **SciML's problem and algorithm authors** migrate, by a declared migration (§1.3), with a shim for unmigrated algorithms.
- **The parameters stay at the surface** (W-63, E-181). The solver's core is keyed on the state's type; the right-hand side is kept partially evaluated on the parameters. A new parameter type compiles the user's function and a few small records, not the solver (TDE: 1.3–1.5 s → 0.2–0.26 s).
- **Loading on demand: extensions for keys, loading stubs for functions, no reference change.** It meets Julia's world age (§1.4): code loaded inside a function is invisible to the rest of that function. The user-facing entries that can reach such code (render, `save`, `display`) call into the core through `invokelatest`; SciML loads no algorithm code on demand. Whether an on-demand load below top level may instead raise an error is the user's ([open issue 77](../open-issues.md#1-decisions-waiting-for-the-user)).
- **The cache across sessions** keeps one part per dependency set (E-180). At setting C's size its parts cost 0.45 s at load; coarser parts are its next lever ([open issue 76](../open-issues.md#1-decisions-waiting-for-the-user)).
- **The cost, recomputed** (§2.1): load about 1.8–3.3 s, a session about 2.3–4.8 s with a cache, against the target of about 3 s and Python's 1.45 s. The plan's load budget of 1.2 s fails at every point; open issue 73's loader levers are a prerequisite.
- **What is trait-specific** and what is packaging is stated apart (§2.5). The direction review's caution stands. Where §2.5 claims a trait-specific gain, the experiment has a plain control (§4).
- **Experiments** (§4): two zero-run analyses, X7 extended to test the three mechanisms the review found broken as written, X1 by coverage, X5; then the user's two examples (X3, X4) narrowed, each with a plain control.

## 1. The architecture

### 1.1 The shape both libraries share

| Layer | What it is | Mode | Loads |
|---|---|---|---|
| user API (the umbrella packages `Makie`, `CairoMakie`, `OrdinaryDiffEq*`, `SciMLBase`'s front end) | upstream's names, keyword parsing into typed records, normalization and partial evaluation at the entry, loading stubs | plain (its bounded workers: facts) | at `using` |
| compatibility layer | the old author APIs, run above the core | plain on its own paths; facts where the core's calls reach it, kept to a few lines by a hand-over (§1.2) | Makie's: at the first old-style plot, or at `using` of a package whose image needs it; SciML's shim: with an unmigrated algorithm package |
| implementation packages | recipe and block groups, backends, algorithm packages; each a trait module implementing the core's traits for its own types | facts | at `using` when the user names them; Makie's groups at first use |
| trait core (`PlotCore`; `SciMLBase`'s trait module with `OrdinaryDiffEqCore`'s integrator family) | the traits of the open sets, the core's concrete types, the bounded functions | facts | at `using` |
| TraitWorld, BaseTraits, the patched Julia | | | at `using` |
| the cache across sessions | one generated package per dependency set (E-180) | both owners | with its dependency set |

**The waist.** Five conventions over the references keep the core narrow.
1. **The core reaches what it does not own only through declared operations:** operations on kept values (`Kept{Drawable}`, `Dynamic{Transform}`, [traits §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)), calls of `Callable`s ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)), and bounded functions compiled per key ([§6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)). The core never names a provider's or the compatibility layer's types (a convention). An operation on a kept value whose implementation the core's image does not know goes through the table of the call's targets ([facts §9](../reference/facts.md#9-the-dynamic-split); [compiler §4.3](../reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)), whose targets are made at the type's first use in each session (C-14) and compiled by facts.
2. **Implementations reach the core by `@implement` for their own types,** the type owner's right ([traits §10.1](../reference/traits.md#101-who-may-implement)), and by calling bounded functions. A provider adds no method to the core's or the umbrella's functions, except for its own types (porting A4), or as a declared joint owner (§1.2).
3. **The compatibility layer is ordinary code that uses the trait world** ([traits §2](../reference/traits.md#2-trait-modules)). What the core's calls reach of it is compiled by facts ([facts §6.2](../reference/facts.md#62-the-mode-rule)); so the core's operations on old-style plots hand over at once to `Dynamic{Callable}`s the layer registers, which run its own code plainly ([lowering §12](../reference/lowering.md)).
4. **The user API is thin** (porting 0.3, 0.5, A3, A7). Front ends stay plain, behind a function barrier, as TraitDifferentialEquations' `solve` does.
5. **The entry normalizes call shapes and partially evaluates the user's functions on the user's types** (class (f) of [the plan](2026-10-27-ttfx-sciml-makie.md) §5; [porting](../intro/porting.md) §0.4): saving times to `Vector{T}`, tolerances to `T`, plot data to the core's position families, attribute values to typed records, the right-hand side to `PartialFn(f, p)`. So the core's keys are few and the library's own, and a cache recurs (E-173, E-178, E-181).

### 1.2 Makie

**The core, `PlotCore`.** The traits are [the rewrite's](../explorations/makie-rewrite.md) §2, in today's spelling. The core's traits take names upstream does not use, so that `using` brings no name with two meanings: `Plot`, `Lines`, `Hist` stay upstream's types (SciMLBase's extension writes `Makie.plottype(sol) = Makie.Lines`).

| Trait | The open set | Implemented by | Loads with |
|---|---|---|---|
| `Positions{N, T}`, `Coords{T}` | point and coordinate data | the core for Base's arrays and `Point`s; users by forwarding (`@implement Positions{2, Float64} Trajectory by data`); SciMLBase's Makie extension for `Trajectory` (M10) | the core; the user's package |
| `GridData`, `ImageData`, `MeshData` | grid, image and mesh data | the core; users | the core |
| `ColorSpec` (`resolve(c, ctx)::ResolvedColors`) | attribute values with several shapes | the core for `Symbol`, colorants and vectors; users | the core |
| `Drawable` (`children`, `datalimits`, `emit!`) | plots | the core's primitives; recipe groups; new-style recipes; the old `Plot{F, T}` family | the core; at first use |
| `Backend` (`draw!` per primitive kind) | backends | `CairoMakie`; GL and WGL backends | `using CairoMakie` |
| `Transform` | axis scales | the core for `typeof(log10)`, `sqrt`, `identity`, `pseudolog10`; users | the core |
| `Ticks` | tick locators and formats | the core (`LogTicks`, Wilkinson); a user's function as `Callable{Tuple{Float64, Float64}, Vector{Float64}}` | the core |
| `Layoutable` | blocks | the core's `Axis` and `Label`; block groups (`Colorbar`, `Legend`, `Slider`, …); users | the core; at first use |
| `AxisValues` | dates, units, categories | extensions (Unitful, Dates), the core for categories | with the user's package |
| `Interaction` | mouse and keyboard handlers | the interaction group | with an interactive backend |

- **Concrete types:** `Point{N, T}`, `RGBAf`, `Rect2f`, `Mat4f`, `ResolvedColors`, `ColorContext`; the primitives (`LinesPrim`, `ScatterPrim`, `PolyPrim`, `TextPrim`, `ImagePrim`, `MeshPrim`); `Scene`, `Figure`, the grid, the core's `Axis`; a typed `Theme` record.
- **Bounded functions:** conversion of data into the position families; colour mapping; the `Float32` conversion; data limits; tick placement; text layout over FreeTypeAbstraction; the render walk, which emits each plot's primitives and hands them to the backend.
- **Derived values:** first as TraitMakie does, by rebuilding children before each render (`refresh!`). A typed graph (`Node{T}`, `Derived{T}`) comes where a measurement asks for it.
- **The layout:** GridLayoutBase's solver, called as it is first (compiled by facts on the core's path); ported behind `Layoutable` where its untyped content costs.
- **The tree:** pruned by what each kept package brings. E-179's attribution: Interpolations' tree brings SparseArrays (0.23 s), MathTeXEngine and UnicodeFun bring REPL (0.06 s), FileIO and Makie bring Pkg (0.13 s). Each is a candidate for a loading stub or a lighter replacement (X1).

**The user API, unchanged.** The workload's plot (`experiments/ttfx/plotting.jl`), call by call:
- `using CairoMakie` loads the umbrella `Makie` (names, the old API's types, stubs), `PlotCore`, the Cairo backend and the cache's plotting parts.
- `Figure(size = (800, 600))` and `fig[1, 1]` are the umbrella's constructors of the core's `Figure` and grid positions.
- `Axis(fig[2, 1]; xscale = log10)`: the umbrella parses the keywords (about 140 attributes in upstream's `@Block Axis`) into the core's typed axis record. `log10` conforms to `Transform` (the core implements it for `typeof(log10)`) and enters the record's `Transform` field as it is ([traits §7.3](../reference/traits.md#73-assigning-from-plain-code)). The axis is placed through `Layoutable`.
- `lines!(ax, a.t, y)`:
  - the umbrella converts `x, y` into the position family (`Vector{Point2d}`) and the keywords into a typed attribute record;
  - it calls the core's `add_lines!(ax, pos::Dynamic{Positions{2, Float64}}, attrs)`. That is compiled once; its loops run `compiled_for` the data (porting A12);
  - **an argument the core does not convert** (`lines!(ax, 0..1, sin)`, a user type with only a `convert_arguments` method) goes to the compatibility layer's conversion cascade, which produces the same core primitive.
- `save(path, fig; px_per_unit = 1)`: `save` stays FileIO's binding, re-exported. Makie's method for PNG, SVG and PDF draws through the active `Backend`, called through `invokelatest` (§1.4).
- **Plot objects keep their property API:** `p.color = :red`, `p.color[]`, `p[1]`, `on(p.color)`, as sugar over the core's typed fields. The observable-style forms (`on`, `lift` of a plot's attribute) load the compatibility layer.
- **A user's `Observable`** passed as data is subscribed by the umbrella (plain `on`). The new value is converted at its bound into the core's input, which the core reads at each render.

**Recipe authors: the old API kept, a new one beside it.**

*Old style, unchanged.* `@recipe`, `Makie.plot!(p::MyPlot)`, `map!`, `lift`, `Observable`, `Attributes`, `shared_attributes`, `Makie.convert_arguments`, `Makie.plottype`, `Makie.used_attributes`, `Makie.expand_dimensions` and `SpecApi` keep their meaning.
- **The names and types** live in the umbrella, which owns them: `Plot{F, T}`, `Lines`, `Attributes`, `Observable`, the `@recipe` macro, empty generic functions. They load at `using`. A recipe package that loads defines methods for its own `Plot{typeof(myrecipe), T}`, a stakeholder's methods.
- **The machinery** is upstream's creation pipeline, conversion cascade (140 `convert_arguments` methods), `convert_attribute` (95), the plot's ComputePipeline graph and theming, in a compatibility package. Its methods on the umbrella's functions for the umbrella's types would be pirates by the letter, so **the umbrella declares the compatibility package a joint owner** ([traits §10.1](../reference/traits.md#101-who-may-implement), "for split packages"): its methods are stakeholders' changes.
- **When it loads:** at the first old-style plot, or at `using` of a package whose image needs it: an old recipe package with a workload records the machinery as an image dependency (GraphMakie, AlgebraOfGraphics), so a session that loads one loads the machinery at `using`.
- **The family:** the umbrella declares `@implement Drawable Plot{F, T} where {F, T}`. Its operations hand over at once to `Dynamic{Callable}`s the compatibility package registers at its load (`data_limits`, the children list, the leaves). The handed-over code runs plainly; the facts part is the few lines of the hand-over. Each new argument shape of each old recipe is a family member checked at its first use ([traits §4.7](../reference/traits.md#47-families)), unless an image or the cache holds it (E-171: about 0.08 s for a new type).
- **The leaves are core primitives.** `lines!(p, attrs, data)` inside an old `plot!` creates the core's `LinesPrim` as a child. Its inputs are fed by a bridge: a `Dynamic{Callable{Tuple{}, Vector{Point2f}}}` that resolves the compatibility graph's node and converts its value. It holds no edge into the compatibility layer.
- **Names:** `Lines` stays the old type, for dispatch and `documented_attributes(Lines)`; its attribute schema is kept in step with the core's typed record. `lines!` returns the old `Lines` plot object where an old recipe called it, and the core primitive otherwise (porting B1 item 7 records the clash of names at `using`).

*New style.* A type of the author's own that implements `Drawable` in a trait module:

```julia
# in a recipe package's trait module (a sketch, not run)
mutable struct Lollipop
    pos::Vector{Point2d}
    color::ColorSpec                    # Kept{ColorSpec}: the shape may change
    stems::LinesPrim
    heads::ScatterPrim
end
@implement Drawable Lollipop begin
    children(r) = Kept{Drawable}[r.stems, r.heads]
    datalimits(r) = datalimits(r.heads)
    emit!(r, out) = (emit!(r.stems, out); emit!(r.heads, out))
end
```
- The render walk reaches it through the table of the call's targets (rule 1); the targets are made at the type's first use in each session, and kept by the cache at library keys. Its `emit!` is in its author's image only if the package's workload renders through the core.
- **A typed `@recipe` form** is optional: an attribute block whose entries carry types could generate such a struct and its `@implement`. A Makie-side macro; no reference change.

*Coexistence.* One axis keeps `Vector{Drawable}`, that is `Vector{Kept{Drawable}}`: core primitives, new-style recipes and old-style `Plot{F, T}` side by side. Both read the same theme.

*Makie's own 64 recipes and 16 blocks* are not ported at once: the core holds the primitives, `lines`, `scatter`, `text`, `poly`, `image`, `heatmap`, `mesh`, `Axis` and `Label`; the other recipes run first as old-style recipes, from upstream's source unchanged, in groups loaded at first use; each moves to the new style when its owner chooses. Upstream's ReferenceTests check both paths.

**What loads when (Makie):**

| When | What |
|---|---|
| `using CairoMakie` | TraitWorld; `PlotCore` and its pruned dependencies (colours, geometry, the layout solver, FreeType, Cairo, the PNG writer); the umbrella's names, types and stubs; the Cairo backend; FileIO (the `save` binding); the cache's plotting parts |
| the first call of a recipe or block outside the core | its group, with its cache part: the basic recipes; the statistics recipes (with StatsBase, KernelDensity, Distributions); contours and triangulations; 3D; the other blocks |
| the first old-style plot, or the first argument the core does not convert | the compatibility machinery (or at `using`, see above) |
| the first LaTeX string in a label | MathTeXEngine, through a loading stub the core reaches as a `Dynamic{Callable}` (M7; open issue 75) |
| the user loads a package | extensions, as today: units on axes, `plot(::Distribution)`, tables, SciMLBase's recipes |

### 1.3 SciML

**The core:** SciMLBase's trait module, which owns the problem and solution types and `solve`'s front end ([move 3](../explorations/sciml-as-traits.md#4-the-shortest-route)), with OrdinaryDiffEqCore's integrator family and controllers. It is keyed on the state's type, never the parameters' (W-63):

| Trait | The open set | Implemented by |
|---|---|---|
| `ODEProblemTrait{U, T, P}` (`rhs!`), with `ODEJacobian`, `ODEMassMatrix` as subtraits | problems and models (the problem authors' trait) | the canonical `ODEProblem`; packages that build their own (NetworkDynamics' `Network`, E-152) |
| `ODEAlgorithm` (`alg_order`, `isadaptive`, `core_init`; SciMLBase's functions) | algorithms | each solver package |
| `ODEDiffEqAlgorithm <: ODEAlgorithm` (`isfsal`, …: OrdinaryDiffEqCore's functions) | OrdinaryDiffEq's algorithms | OrdinaryDiffEq's solver packages |
| `StepView{U, T}` (`step!`, `step_tstop!`, `step_interp!`; fields `u`, `t`, `dt`, flags) | integrators as the core's driver and callbacks see them, without the parameters | OrdinaryDiffEqCore's `ODEIntegrator` family; Sundials and others their own |
| `IntegratorView{U, T, P}` (fields `u`, `uprev`, `t`, `tprev`, `dt`, `p`, `iter`, `sol`, `opts`, `alg`, `f`; `add_tstop!`, `terminate!`, `u_modified!`, `interp!`) | the integrator as callbacks see it | the outer layer's adapter (`ParamIntegrator`, W-63) |
| `Callback{U, T, P}`, `EventCallback{U, T, P}` | callbacks | `DiscreteCallback`, `ContinuousCallback` records; DiffEqCallbacks; users |
| `Trajectory{U, T}` (`times`, `state`, `at`) | solutions as plotting sees them | `ODESolution` |
| `LinearSolver{T}` | linear solvers for implicit methods | a dense LU in the core; LinearSolve's solvers by its extension |

- **Concrete types:** the canonical `ODEProblem{U, T, P, F, …}`, whose right-hand side is kept partially evaluated on the parameters (`PartialFn(f, p)`) at a struct parameter bounded by `Callable{CoreRHSSig{T}, Nothing}` ([traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait); TDE, E-181). The core's `CoreProblem{T, …}` has no parameter for `P`. `ODEFunction` is a plain record. `SolverOptions{T}` is the normalized options record. `ODESolution{U, T}` keeps no function axis (move 5).
- **Bounded functions:** the driver over `StepView{U, T}`; saving; event location; the PI controller.
- **What stays inside each solver package, as types:** caches, tableaus, `perform_step!`, controllers. A closed set per package, fully typed over the key (B6).

**The user API, unchanged.** The workload's calls (`experiments/ttfx/workload.jl`):
- `ODEProblem(lorenz!, u0, tspan, p)`: SciMLBase's plain constructor detects the in-place form by reflection, as today, and keeps `PartialFn(lorenz!, p)` at the core's signatures, `Dynamic` by `Callable`'s default. `ODEProblem(compiled_for(f), …)` and `FullSpecialize` give the per-function form.
- `solve(prob, Tsit5(); saveat, reltol, abstol)`:
  - the plain front end (`@nospecializeinfer`, a function barrier) builds `SolverOptions{Float64}`: `saveat` as a `Vector{Float64}` whatever was passed, tolerances as `Float64`;
  - the outer layer makes the core's problem and adapts the callbacks (W-63);
  - `core_init(alg::Tsit5, m::CoreProblem{T}, callbacks, opts)` builds the integrator: a method of SciMLBase's `ODEAlgorithm` operation, typed on the algorithm package's own type and the core's concrete problem type;
  - the core's driver runs it; the result is an `ODESolution`.
- `Rodas5P()`: the Jacobian by ForwardDiff duals under the library's tag, the chunk chosen at `init` (TDE's `DualJacobian{N, FD}`); a dense LU for small dense systems.
- `sol.t`, `sol.u`, `sol(t)`, `sol[i]`: fields, and the interpolant kept in the solution as a kept value. The algorithm package that made it is loaded by `using`, never on demand (§1.4).
- `init`, `step!`, `reinit!`, `remake`, `integrator.u`: plain front ends and fields, as today.

**Problem and algorithm authors: a declared migration** (the user's permission), as a list:
1. **The traits' owners:** SciMLBase owns `ODEAlgorithm` with its own functions (`alg_order`, `isadaptive`, `core_init`); OrdinaryDiffEqCore owns a subtrait with its own (`isfsal`, …): SciMLBase cannot name OrdinaryDiffEqCore's functions.
2. **The declarations:** one family declaration per abstract algorithm type in OrdinaryDiffEqCore, `@implement ODEDiffEqAlgorithm A where {A <: OrdinaryDiffEqAlgorithm}`, each member checked at its first use ([traits §4.7](../reference/traits.md#47-families)).
3. **The fallbacks removed:** OrdinaryDiffEqCore's `alg_order` that raises "Order is not defined", and `isadaptive(alg) = false` at `Any` (a pirate by the letter once the joint owners go). A trait default takes their place where a default is right; else each algorithm implements the operation.
4. **`init`'s form:** `core_init(alg::MyAlg, m::CoreProblem{T}, callbacks, opts)`, a method typed on the package's own algorithm type and the core's concrete problem type. The partial evaluation (W-63) reduces every problem, canonical or the author's own type, to `CoreProblem`, so no algorithm package needs a bounded problem argument, and L-3's refusal ([lowering](../reference/lowering.md#18-deviations); porting B6, PB-F) is not met. It compiles per algorithm and state type.
5. **`SolverOptions{T}` keeps `DEOptions`' field names** (1,979 source lines in OrdinaryDiffEq's sublibraries read `opts.`), with its function fields (`internalnorm`, `isoutofdomain`) as `Callable` fields. The Jacobian is read through `jacobian!`, not `f.jac === nothing` (73 lines in Rosenbrock and Differentiation).
6. **The front-end methods that are pirates by the letter** (57 of 63 held by joint owners today; [the inside-out plan §2](2026-10-21-ndport-inside-out.md#2-the-pirates-classified)) are removed: move 3 puts the body in SciMLBase.
7. **SciMLBase's Makie extension** implements the core's position traits for `Trajectory`, so `plot(sol)` stays in the trait world (M10).
- **Problem packages:** build the canonical `ODEProblem` (unchanged call), or implement `ODEProblemTrait{U, T, P}` for their own type; the outer layer partially evaluates its `rhs!` and `jacobian!` on the problem. An `AbstractODEProblem` subtype that does neither is converted at the entry ([traits §4.10](../reference/traits.md#410-types-that-only-convert)).
- **The compatibility shim** (the user: "a compatibility shim would be great"): an unmigrated algorithm package keeps depending on DiffEqBase, so it loads upstream's front end and integrator with it, plain, at today's costs. The front end asks `conforms(typeof(alg), ODEAlgorithm)`: a migrated algorithm takes the core's path, an unmigrated one the shim's. Mine: the shim loads with the package that needs it, never on demand (§1.4).

**Everything else keeps its API.**
- **Callback authors** (DiffEqCallbacks): `affect!(integrator)` reads `integrator.u`, `p`, `t`, `dt`, and also `sol` (20 times), `opts` (20), `tprev` (8), `f` (5), `alg` (4), `uprev` (2), `iter` (1). `IntegratorView{U, T, P}` declares them all: scalars copied by the adapter before each callback and back after (W-63's form: a declared field is a stored field), `sol` as a `Kept{Trajectory{U, T}}`, `opts` as the `SolverOptions{T}` (field names kept), `alg` as a `Kept{ODEAlgorithm}`, `f` as the user's function at its own signature. Mine. A callback is compiled once per problem type, as today in TDE (E-158).
- Symbolic access (`sol[x]`, `integrator.ps`): move 4, with the `getproperty` sugar kept plain.
- SciMLBase's 20 extensions: methods and implementations for their triggers' types (porting A4).

**What loads when (SciML):**

| When | What |
|---|---|
| `using OrdinaryDiffEqTsit5` | TraitWorld; SciMLBase's trait core and front end; OrdinaryDiffEqCore's integrator family; Tsit5's tableau, cache and step; the cache's solver part |
| `using OrdinaryDiffEqRosenbrock` | Rosenbrock's tableaus, caches and steps; ForwardDiff; a dense LU |
| `using OrdinaryDiffEq` | the umbrella, with the default algorithm's candidates for `solve(prob)` |
| inside `solve`, at its first need | LinearSolve's default polyalgorithm for a large or sparse Jacobian without a `linsolve`; NonlinearSolve for a DAE's initialization: used only within `solve`'s own call, through `invokelatest`, never returned |
| `using` of an unmigrated algorithm package | the shim |
| the user loads a package | AD rules, StaticArrays, ModelingToolkit's symbolic access, LinearSolve's solvers passed as `linsolve` |

### 1.4 Loading on demand

**Two cases.**
- **A key:** a value whose type has no implementation loaded (a `Vector{Quantity}`, a `Date`, a `Normal`). The type's own package is loaded whenever such a value exists, so its implementation is its owner's, or an extension with that package as trigger ([traits §10.1](../reference/traits.md#101-who-may-implement)). Nothing waits for a first use. **Not covered:** a key whose package is light and loaded while its implementation needs a heavy one: a `LaTeXString` label needs MathTeXEngine, and Makie re-exports `L"…"`. A loading stub reached through a `Dynamic{Callable}` covers it ([open issue 75](../open-issues.md#1-decisions-waiting-for-the-user)).
- **A function:** `hist(x)`, `contour`, `voronoiplot`. The user loaded nothing that would trigger the code. This case needs loading at first use.

**A loading stub,** in the ordinary layer:

```julia
# in the umbrella Makie, plain code (a sketch, not run)
function hist(args...; kw...)
    m = Base.require(MAKIE_STATS)                   # a dependency of Makie; loads it and its cache part, once
    return Base.invokelatest(m.hist_plot, args...; kw...)   # the provider's own function, in the latest world
end
```
- The provider's `Hist` implements `Drawable`. The axis keeps it as `Kept{Drawable}`; the render walk reaches it through the table.
- **World age.** A call runs in the world it started in ([facts §2.1](../reference/facts.md#21-g1-identical-or-error)). In `function f(x); hist(x); save("h.png", current_figure()); end`, `save` runs in the world before the provider loaded, and the render walk would not find `Hist`'s `emit!`. So **every user-facing entry that can reach code loaded on demand calls into the core through `invokelatest`:** render, `save`, `display`, `show` of a figure. One dynamic call per entry, per plot or save, not per element. SciML loads no code on demand that a returned value needs (§1.3), so `sol(t)` in a loop needs none. Python has no world age; the alternative, an error that names the `using` for a load below top level, changes the API ([open issue 77](../open-issues.md#1-decisions-waiting-for-the-user)).
- **Cost:** the provider's load at the first call (tens to hundreds of milliseconds); the targets of the table at the provider's type at their first use in the session (kept by the cache); then one dynamic call per entry.
- **Rules:**
  - a stub forwards to the provider's own function;
  - a provider adds no method to the umbrella's functions;
  - stubs stay in plain code that plain code calls; where trait code needs one (the text layout's LaTeX), it is reached through a `Dynamic{Callable}`, which runs plainly.

**What the trait design adds** to plain lazy loading (LazyModules gives the same API and the same delay), as hypotheses for X7:
1. The core holds no edge to the provider. Loading it discards no core code **except by stakeholders' changes** ([facts §2.2](../reference/facts.md#22-g2-stable-caches)): standard libraries' methods on Base's types, and stakeholders' extensions the provider activates. The statistics group is the known case: StatsBase and Distributions bring SparseArrays, whose `vcat` made trait code redo 0.34–0.42 s of work in TraitReport ([evidence §3](../design/evidence.md#3-first-calls-and-sessions); porting B1 item 11).
2. The provider's contract is checked at its `@implement` ([traits §4.9](../reference/traits.md#49-checks-at-the-declaration)).

**What it changes:** nothing in the references. Open issue 75's option (ii) (a registry by key) stays Optional.

### 1.5 Where the cache across sessions fits

*(2026-10-27: the environment-keyed cache this section assumed is retired; the direction is the cache keyed on facts and their origins, W-66, [the exploration](../explorations/facts-keyed-cache.md). Its parts follow the stakeholders' identities, not the environment; what follows about what is kept and what makes it recur holds for its facts code.)*

- **Its parts follow the packages:** one per dependency set, loaded by TraitWorld's package callback as soon as its set is loaded (E-180). The architecture multiplies dependency sets (core, umbrella, compatibility layer, groups, algorithm packages), so coarser parts matter (open issue 76; the cache's review: about 8 ms a part whatever its size).
- **What it keeps:** the core's and implementation packages' facts code at library keys; the front ends' and the compatibility layer's plain code, validated at load; the first-call checks; the table's targets at library keys.
- **What it cannot keep:** code that names a type defined in the session: the user's own functions, parameter structs, recipes and plot data types. With the parameters at the surface (W-63) and `Dynamic` positions where user types enter, the core compiles nothing for them.
- **What makes it recur:** the entry's normalization and partial evaluation (rule 5). E-180 shows order independence on D (order B with a cache recorded in order A, 1.05–1.11 s).

## 2. Costs and risks

### 2.1 Load and first use

An estimate from floors and measurements, for the workload's packages, strict mode off, images valid. The builds and settings of each term are in the evidence.

| Term | Range (s) | Source |
|---|---|---|
| Julia's startup | 0.10–0.12 | E-168 |
| the solver's dependencies (Tsit5, ForwardDiff, a lean SciMLBase) | 0.30–0.47 | E-176: Tsit5, ForwardDiff and DiffEqBase 0.47 s, 98 packages |
| Rosenbrock with a dense LU, without LinearSolve's tree | 0.10–0.30 | E-176: +0.73 s and 55 packages with the linear-solver tree; Rosenbrock's own increment 58 ms (`logs/p2/S-imports.log`) |
| the plotting core's dependencies, pruned | 0.51–0.72 | E-176's floor, 66–83 packages; E-179's attribution |
| `PlotCore`'s own image | 0.20–0.50 | E-171; Makie's image 0.60–0.71 s for all of Makie (E-169, E-179) |
| the Cairo backend | 0.10–0.29 | CairoMakie 0.18–0.29 s (E-169, E-179) |
| FileIO and Pkg (the `save` binding) | 0.14 | `logs/p2/S-imports.log` |
| the umbrella's types, stubs and front ends; extensions the workload's loads trigger | 0.05–0.20 | not measured |
| TraitWorld and the trait packages' load hooks | 0.25–0.33 | D against Dp, C against S |
| the cache's parts | 0.15–0.45 | E-180 (D 5 parts, C 45); about 0.1–0.15 with coarser parts (the cache's review, an estimate) |
| shared packages of the two trees | −0.10 | [the direction review](../reviews/2026-10-27-w58-direction.md), finding 5 |
| **load** | **about 1.8–3.3** | Python 0.45 s; stock 3.5 s; the plan's budget 1.2 s |
| work after the load, with a cache | 0.4–1.5 | D 0.4–0.55 s; C with the mechanism about 1.5 s (E-180) |
| **session** | **about 2.3–4.8** | target about 3 s; Python 1.45 s; stock 9.2 s |

- **The load is the term that matters.** The budget of 1.2 s fails at every point. Open issue 73's loader levers compound with this architecture: validation and activation remembered for an unchanged environment (up to about 2.2 s of stock's 3.3 s); facts images without edge validation under strict mode, which waits for strict mode's intended design (deferred by the user).
- **First use without a cache:** the core's own keys come from images; a new key compiles once per environment, then the cache keeps it; a new user function, model, parameter type or recipe compiles nothing in the core where its position is `Dynamic` or partially evaluated (E-168: D's second model 0.056 s; E-181: a new parameter type 0.05–0.1 s beyond the workload's).
- **Facts copies of Base:** the core's workloads must reach them, or a facts system image for the product setting.
- **The solver's driver is not compiled ahead from declarations** ([traits §13](../reference/traits.md#13-compiling-ahead); L-15). Algorithm packages keep workloads (pushback 3).
- **Loads at first use** move their cost into the session, as matplotlib's lazy imports do (E-168). The workload's script triggers none.

### 2.2 What the compatibility layer costs

- **At `using`:** the old API's names and types (ComputePipeline 2 ms, Observables 6 ms); the machinery too, if an old recipe package with a workload is loaded.
- **At its first use:** its machinery's image, a part of Makie's 0.60 s (E-179). The share is X1's.
- **Per old-style plot:** today's plain cost on the creation path; a family member check per new argument shape; the hand-over's few lines compiled by facts.
- **Per frame:** one operation on a `Kept{Drawable}` per plot, through the table (9–18 ns, E-145); one indirect call per hand-over and per bridged edge recomputed.
- **What reaches the core:** the hand-over's `Dynamic{Callable}`s and kept values only (rule 3).

### 2.3 Invalidation and the facts rule across the layers

| Layer | Mode | What can discard its compiled code | In the cache |
|---|---|---|---|
| trait core; implementation packages written as trait modules | facts | a stakeholder's change (edits, upgrades, their extensions, standard libraries' methods on Base's types); a winning pirate unless strict mode refuses it ([facts §2.2](../reference/facts.md#22-g2-stable-caches)) | facts code at library keys, valid in any load order |
| plain dependencies the core reaches | facts on the core's path, plain elsewhere | as the core, for the facts copies | the facts copies |
| the user API's front ends | plain; their bounded workers facts | any owner's method at an abstract call | plain code, validated at load |
| the compatibility layer and old recipes | plain on their own paths; facts for the hand-over | as today on the plain paths | both, validated at load |
| the user's script | plain | — | not kept |

- **The core is protected across loads in a session, except by stakeholders' changes,** which include the standard libraries' methods a group's tree brings (§1.4). The measured case at scale: under `all`, Makie's plot path compiled by facts recompiled 0.02 s after a late DataFrames load, plain Makie 6.1 s (E-177). That setting compiles all of Makie by facts; this architecture keeps the umbrella and the creation path plain, and their exposure is not measured.
- **Strict mode** refuses a pirate that would win at a fact of the core. Its prototype's check at load costs 6.6 s at this scale (C/s), so it is off here until its intended design.
- **G1 in every layer:** each computes what plain Julia computes, or raises. The ports check digests and pixels against upstream.

### 2.4 What stays plain, and why that is fine

- **Front ends:** keyword parsing, normalization, partial evaluation, `remake`, reflection on the user's function. Once per call, behind a function barrier.
- **The compatibility layer and old recipes:** today's costs, loaded only when used.
- **Observables, notification and `lift` chains:** ordinary code above the trait world.
- **Sugar:** `getproperty` switches, printing, the `@recipe` and `@Block` macros.
- **The SciML shim:** loaded only with unmigrated algorithm packages.

### 2.5 What is trait-specific, and what is packaging

**Packaging; plain code could do it too:**
- lean trees, recipe groups and algorithm packages;
- loading stubs (LazyModules);
- normalizing at the entry;
- erasing the user's function, and partial evaluation on the parameters (FunctionWrappers; SciML's `AutoSpecialize`; E-181 measured it with `Callable`).

**Trait-specific, to be shown at scale, each with a plain control:**
1. **A checked waist.** Groups, old recipe packages and the compatibility machinery load at any time and discard none of the core but by stakeholders' changes (X7 (ii), X3).
2. **One cache per environment, with no load-order key** (E-180 on D; at scale, the ports).
3. **`Dynamic` positions by default where user types enter,** with the signature checked at every call (E-168: D's second model).
4. **Old code above a protected core** (X3).
5. **Contracts checked at `@implement`** for every provider, whenever it loads.

[The direction review](../reviews/2026-10-27-w58-direction.md) (finding 1) stands: with a cache, the plain twins were as fast as the trait demonstrators in every pair on this workload. Off the workloads' keys the trait demonstrators now beat their plain twins (1.11 against 1.82 s, E-181), by a technique plain code could also use.

### 2.6 Risks

1. **Makie's own code on the workload's path may be large:** `Axis`, text layout and the grid (X1).
2. **Two creation pipelines.** Packages that reach Makie's internals keep working only as far as the compatibility layer carries them.
3. **The bridge and the hand-over:** pull-based updates between ComputePipeline's graph and the core's inputs.
4. **World age** at on-demand loads (§1.4; open issue 77).
5. **Two owners:** a Base method reached from plain and from facts code is compiled twice.
6. **Precompile time grows** with compile ahead per `@implement` and with workloads per group.
7. **The tree comes back through others** (E-179's attribution): each kept package's own dependencies.
8. **The text engine:** MathTeXEngine (0.21 s of the floor) and REPL through it; the log axis needs rich-text tick labels, not LaTeX (X1).
9. **Strict mode's load cost** and **the load target** (§2.1).

## 3. Options considered

### 3.1 Makie

| Option | For | Against | Verdict |
|---|---|---|---|
| M1. Upstream wrapped by facts, a typed front, no core | every API kept as it is; protection measured (E-177) | the load stays Makie's (2.3–2.7 s); no open sets as traits | a baseline, not the end |
| M2. A lean fork, plain (E-179) | simple | drops features, against the API; saves 0.4 s | rejected |
| M3. A trait core with the compatibility layer above, all loaded at `using` | API kept; core protected | loads Makie's own code as today | rejected as it stands; M5 is M3 with loading by use |
| M4. Old recipes translated into trait recipes by the macro | one pipeline | `plot!` bodies are arbitrary code | rejected as the general path; kept as the optional typed `@recipe` form |
| **M5. A trait core; groups, blocks and the compatibility machinery loaded at first use; the API in a thin umbrella; the tree pruned** | API kept by names and stubs; only the path in use loads; old recipes run unchanged | two pipelines; the bridge and hand-over; world age at on-demand loads; an estimate | **recommended** |
| M6. Two stacks side by side | no bridge | two scene models cannot share an axis | rejected |

### 3.2 SciML

| Option | For | Against | Verdict |
|---|---|---|---|
| S1. Upstream wrapped by facts, with normalization at the entry | cheap | not lean; 57 pirates held by joint owners; open sets informal | the first stage, not the end |
| **S2. A trait core keyed on the state's type; the parameters at the surface; algorithm and problem authors migrate; the user and callback APIs unchanged** | lean; checked contracts; no pirates in the core; the user's function and parameters out of every core type | a migration for solver packages (§1.3's list) | **recommended** |
| **S3. S2 plus the compatibility shim for unmigrated algorithms** | old algorithms keep working | carries DiffEqBase's front end, loaded with them | **recommended with S2** (the user: "a compatibility shim would be great") |
| S4. TraitDifferentialEquations scaled up, with its own API | already built | changes the user API | rejected |

### 3.3 Loading on demand and the compatibility layer's place

- **O1. Package extensions only:** `hist(x)` would need `using StatsBase` first. Rejected for functions; right for keys.
- **O2. A registry by key:** more than needed. Optional.
- **O3. Loading stubs for functions, extensions for keys, entries through `invokelatest`:** **recommended** (§1.4).
- **O4. Everything at `using`:** the status quo.
- **The compatibility layer as trait code:** its `Dict{Symbol, Any}` and `Any` values would put all of it on the facts mode's interop tails. Rejected; the hand-over keeps the facts part to a few lines.

### 3.4 What it would change in the references, and pushback

**The recommended architecture changes no reference.** It uses the language as it stands: trait modules inside ordinary packages, implementations by the type's owner, joint owners for the compatibility package, kept values and `Callable`s at the waist, compile ahead, extensions.

**Changes that come with parts it relies on:**
- **The cache**, when adopted (open issues 72, 76): lowering §15–§16, facts §11, compiler §2.9.
- **A registry by key** (Optional): traits §4, §5.5, §13; lowering §8.2, §16.
- **The porting guideline,** after X3 and X4: a part on a large library. The parameters' example is in already ([porting](../intro/porting.md) §0.4, B2).

**Pushback for the user:**
1. **Open issue 75:** extensions for keys, loading stubs for functions, no reference change; (ii) Optional. Recommended.
2. **World age** ([open issue 77](../open-issues.md#1-decisions-waiting-for-the-user)): entries through `invokelatest` keep upstream's calls (recommended), or an on-demand load below top level raises an error naming the `using`.
3. **Compile ahead does not reach the solver's driver:** workloads are its way into images.
4. **The plan's load prediction fails:** about 1.8–3.3 s against at most 1.2 s. The target of about 3 s holds only at the low end of the session's range. Open issue 73's loader levers are a prerequisite.
5. **The shim's form** (mine): it loads with the unmigrated package that needs it, never on demand.
6. **Makie's own recipes run first through the compatibility layer** (mine); they move to trait recipes one at a time.
7. **Callbacks' view** (mine): `IntegratorView` declares what DiffEqCallbacks reads, copied by the adapter.

The parameters' type against the cache (revision 1's pushback 2) is resolved by W-63.

## 4. The smallest experiments

Each gets a registry row before it runs. Each runs alone, niced, under the shared lock; a warm-up and two sessions where a time is measured.

**Zero-run analyses** (no Julia, minutes):
- X2's first half from `logs/p2/S-imports.log`: Rosenbrock's own increment 58 ms, LinearSolve 41, PureKLU 61, LHLFactorization 22, IntelOpenMP_jll 46 (the review's reading).
- E-179's attribution: done (0.89 s Makie's own images, 1.19 s the kept tree).

**X7. Loading stubs and the waist, at small scale** (minutes). TraitMakie and PlainPlots as its control; a provider package with `hist` and its binning, loaded by a stub in the ordinary layer. Four cases:
- (i) the first `hist` and a `save` in one function: does the render find `Hist` (B1), with and without the entry through `invokelatest`;
- (ii) a provider that brings SparseArrays: the core's facts CodeInstances lost, against the plain twin's (B3);
- (iii) a plain-module family kept in the axis: CodeInstances of owner `:facts` in that module at the first render, with and without the hand-over (B2);
- (iv) the stub's and the entry's cost per call.
- **Would change:** a render that misses `Hist` with the entry through `invokelatest` says the world-age rule is incomplete; a provider whose load discards core code beyond the named exceptions says the waist leaks; a plain twin that loses as little says the waist is not a trait-specific claim at this scale.

**X1. What Makie's own code on the workload's path is** (one untimed session). Path-limited coverage of Makie's source (`--code-coverage=@<Makie's src>`) over the workload's plot in S, with MathTeXEngine; `@time_imports` for the load. Gives the files a `PlotCore` slice must hold, the compatibility machinery's share, and what the log axis's tick labels reach. **Would change:** a path through most of Makie's methods says splitting cannot make the core lean.

**X5. Normalization at the entry, at upstream scale, plain** (minutes). A wrapper normalizing saving times, tolerances and keyword order before upstream's `solve`; a CodeInstance-level cache from a session with ranges, used by one with vectors. The recording session runs the same wrapper, so its prediction is close to true by construction: **the informative result is the residual keys** the wrapper cannot reach (`ODEFunction`'s or `DEOptions`' type parameters), which say move 1 is needed for recurrence.

**X6.** Done for TDE as E-181 (W-63). The port adopts the form; at upstream scale it is part of X4.

**X4. An ODE algorithm package written against a trait core** (the user's second example; a build of days, minutes of machine time). On paper first: `core_init`'s form (§1.3 item 4), the integrator view's fields, `SolverOptions`' field names. Then TDE's `ODECore` as the core with `ODEAlgorithm`, Tsit5 in a package of its own, the front end with SciML's keyword names; PlainODE built the same way as the control. **Measures:** `using` per package; the first solve from images, with and without the package's workload; a second algorithm package loaded after the first solve, core CodeInstances lost against the plain control's; digests against upstream's, within the plan's tolerance.

**X3. The waist test over TraitMakie, with an unchanged upstream recipe** (the user's first example, narrowed; a build of days). A minimal compatibility layer with upstream's `@recipe`, `Plot{F, T}`, a ComputePipeline graph per plot, the hand-over and the bridge; upstream's `stairs.jl` unchanged on top; PlainPlots with the same layer as the control. **Measures:** the old recipe's first plot with the machinery's load; after a late DataFrames load, CodeInstances lost and seconds recompiled, core against compatibility layer against the plain control; PNGs against upstream's. The `Axis`, log ticks and grid slice belongs to the port.

**Order:** X7, then X1, then X5; X4 on paper; then X4 and X3. The lean Rosenbrock fork is X2's second half, if the zero-run reading leaves the question open.

## 5. Without the large ports: what can be shown, and what only the ports can show

**Can be shown now, on the demonstrators, slices and emulations:**
- each mechanism at small scale: late loads (E-177), the cache split by dependency set (E-177, E-180), the parameters at the surface (E-181), loading stubs and the waist (X7), an unchanged upstream recipe over a trait core (X3), an algorithm package against a trait core (X4);
- upstream's terms that bound the architecture: Makie's code on the path (X1), the solver's lean load (X2), normalization's residual keys (X5);
- the checks: contracts at `@implement`, errors that name the bound, readable types.

**Only the ports can show:**
- the load of a full-featured core, edges into its dependencies included;
- the whole API surface normalized into typed records without a change in behaviour; upstream's ReferenceTests and SciML's suites as the check;
- the ecosystem's old recipes unchanged at scale, and their costs;
- the cache's size and load at full scale, and its recurrence under varied use;
- strict mode at this scale, with its intended design;
- the session against Python's.

## 6. Questions for review

- Is the hand-over enough to keep the compatibility layer's code plain, and does any path make the core hold an edge to it?
- Does `invokelatest` at the user-facing entries cover every way a user reaches code loaded on demand?
- Is `core_init` on the core's concrete problem type enough for every solver package, including those with their own problem types (Sundials, DAE solvers)?

## 7. The review, and what is done with it

[The review](../reviews/2026-10-27-lean-core-memo.md) (fresh eyes, Opus, of revision 1):
- **B1** (world age): accepted. §1.4 states it; entries through `invokelatest` (mine); SciML loads no code on demand that a returned value needs; the alternative is the user's ([open issue 77](../open-issues.md#1-decisions-waiting-for-the-user)); X7 (i).
- **B2** (the compatibility layer compiled by facts where the core reaches it): accepted. §1.1 and §2.2–§2.3 say so; the hand-over to `Dynamic{Callable}`s (option (a), mine); X7 (iii).
- **B3** (a group's load can discard core code): accepted. §1.4 and §2.3 name the exceptions; a hypothesis for X7 (ii).
- **M1** (`init` refused for trait-implementing problems): resolved by W-63: every problem becomes the core's concrete `CoreProblem`, and `core_init` is typed on the algorithm's own type and it (§1.3 item 4).
- **M2** (the migration larger): §1.3's list (owners, fallbacks, `init`, field names, pirates, the Makie extension).
- **M3** (callbacks' fields): the view declares DiffEqCallbacks' reads (§1.3, mine).
- **M4** (ownership, piracy, names, member checks, image dependencies): the umbrella owns the types and declares the family; the compatibility package is a joint owner; the core's trait is `Drawable`, the old names keep their meaning; the costs stated (§1.2).
- **M5** (the load understated): §2.1 recomputed with E-180 and the omitted terms; §0 and pushback 4 with it.
- **M6** (E-179 not "Makie's own code"): attributed by `@time_imports` (0.89 s against 1.19 s; `experiments/ttfx/README.md`, E-179); §0 and §1.2 add the tree's pruning; the evidence, the README and the registry fixed.
- **M7** (a key extensions miss): `LaTeXString`, a stub through a `Dynamic{Callable}` (§1.4); recorded in open issue 75.
- **M8** (provider code in its image overstated): the table's path named; workloads that render through the core; the cache keeps the targets (§1.2).
- **M9** (experiments): X7 extended to B1–B3; X1 by coverage; X2's first half read; X5 framed; X3 and X4 narrowed, with plain controls, as builds of days.
- **M10** (`plot(sol)` through the old API): SciMLBase's Makie extension in the migration (§1.3 item 7).
- **Minor:** m1 "loading stub"; m2 "conventions over the references"; m3 `Dynamic{Positions{2, Float64}}`; m4 `log10` conforms; m5 `emit!` in the sketch; m6 E-177's setting stated; m7 builds in the evidence, E-145 cited; m8 E-180 cited; m9 digests against upstream's; m10 the status lines when adopted; m11 open issue 75's link fixed (f3f9ee2).

## 8. X7's result (E-182)

[E-182](../../experiments/x7/README.md), at TraitMakie's scale against PlainPlots:
- **B1 (world age):** confirmed, and not specific to traits: both kinds fail when a `save` follows a load in the same function; both work with the entry through `invokelatest`, at no measurable cost. The rule of §1.4 stands; open issue 77 keeps the choice for the user.
- **B3 (the waist):** the provider's load invalidates none of the trait core's 689 CodeInstances, with SparseArrays too; the plain twin loses 3–8 and recompiles 63–155 ms. §2.5 item 1 holds at this scale. The named exception did not occur: TraitMakie's core does not reach SparseArrays' `vcat`; the full `PlotCore` may.
- **B2 (the hand-over):** without it, the old machinery's code reached from the core runs compiled by facts; with it, that code runs plain. Inference by facts still passes through the callable without making code, about 65 ms at the first render here (open issue 78). Whether the hand-over pays at scale depends on the facts mode's cost on the old machinery's untyped code, which X3 measures.

## 9. X1's result (E-183)

The workload's plot runs 6.1% of Makie's code lines (2,710 of about 44,400, in 52 of 150 files): `makielayout/` 841, `compute-plots.jl` 316, `basic_recipes/` 264. No line that calls MathTeXEngine runs. So a `PlotCore` slice for the workload is small, with the `Axis` as its largest piece (risk 1 of §2.6 bounded), and MathTeXEngine goes behind a loading stub (risk 8; §1.2's table).

## 10. X5's result (E-184)

At upstream scale (stock SciML, caches recorded with ranges, used with vectors): normalizing at the entry takes the first solve from 1.50 to 0.51 s; the residual is keyed on the user's function through the problem's type, and with the function out of it (`NoSpecialize`, standing in for move 1) the first solve takes 0.12 s. So rule 5 (normalization and partial evaluation at the entry) and move 1 (the function kept at a bound, never in a type) together make the cache recur; the canonical `ODEProblem` of §1.3 already keeps the function out of its type. With them, the session is the load (3.7 s here) plus about 0.8 s.
