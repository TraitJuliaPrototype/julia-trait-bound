# A lean trait core that keeps the old APIs: SciML and Makie

Status: **proposal** (2026-10-27, mine; W-60). Not normative. Nothing here ran: it reads the references, W-58's measurements and upstream's source.

Serves: [W-60](../record/todo.md). The user (2026-10-27): "Have we figured out a way to keep old APIs l, both super facing and for library authors (e.g. recipes) while keeping the core genuinely lean and clean trait code with open sets as traits? Is that worth sending an architect agent out for?" And: "I think SciML Problem and Algorithm are more tolerable to require a change by library authors. On everything else I basically agree." Also serves [W-58](2026-10-27-ttfx-sciml-makie.md) (its goal, §1) and W-61 (§5), open issues 72–75.

Builds on, and replaces where they disagree:
- [the port note](2026-10-27-port-architecture-ttfx.md) §4–§5 (revision 2);
- [the Makie rewrite](../explorations/makie-rewrite.md), read with "representation" as key and "projection" as forwarding;
- [the SciML exploration](../explorations/sciml-as-traits.md) §4, and [porting B6](../intro/porting.md#b6-case-study-scimls-architecture-as-traits);
- [loading on demand](../explorations/load-on-demand.md) (open issue 75, option (ii));
- [the cache note](2026-10-27-session-cache.md) (revision 2);
- the reviews [of the cache and port notes](../reviews/2026-10-27-cache-and-port-notes.md) and [of W-58's direction](../reviews/2026-10-27-w58-direction.md).

Numbers are quoted from `experiments/ttfx/README.md` with their experiment IDs; their home is the evidence.

## 0. Summary

- **Yes, with one mechanism the port notes lack: Makie's own code loads by use, not at `using`.** E-179 shows that a lean dependency tree is not enough. A Makie without its statistics, units, triangulation and video dependencies still loads 173 packages in 2.32 s, against 2.7 s: Makie's own code is the load. So the API's names stay at `using`, and most of the code behind them loads at its first use.
- **Four layers, for both libraries:**
  1. a **trait core**: a trait module with the open sets as traits, the core's own concrete types, and the bounded functions that do the work;
  2. **implementation packages**: recipes, blocks, backends, algorithms. Each implements the core's traits for its own types. They load with `using` when the user names them (a backend, a solver), else at first use;
  3. a **compatibility layer**: ordinary code that runs the old author API (`@recipe`, `plot!`, `Attributes`, `lift`, `map!`, `convert_arguments`, `SpecApi`) above the core, loaded at the first old-style plot;
  4. the **user API**: a thin ordinary layer with upstream's names and calls. It parses keywords into typed records, normalizes shapes at the entry, and holds stubs that load implementations at first use.
- **Makie's old recipe authors keep their API unchanged.** Their recipes run as plain code in the compatibility layer. Their leaves are the core's primitives. A new-style recipe is a type that implements the core's `Plot` trait, compiled per key in its author's image. Both kinds sit in one axis.
- **SciML's problem and algorithm authors migrate, by a declared migration.**
  - Algorithms implement `ODEAlgorithm`. For OrdinaryDiffEq's solvers this can be one family declaration over the existing methods.
  - Problems implement `ODEProblemTrait`, or are built as the canonical `ODEProblem`, whose call is unchanged.
  - Callbacks, the integrator interface and every user call keep their API.
- **Loading on demand needs no new language feature.** A key's own package is loaded whenever a value of it exists, so its implementations are package extensions, as today. A function whose implementation needs a package the user did not load (`hist`) gets a typed stub in the ordinary layer. This refines open issue 75's option (ii); no reference changes.
- **The cache across sessions** keeps one part per dependency set, loaded with its packages, including those loaded at first use. It keeps the core's facts code at library keys, valid in any load order.
- **The cost, estimated from floors:**
  - load 1.4–2.7 s;
  - a session 1.8–3.8 s with a cache, against the target of about 3 s and Python's 1.45 s.
  - The plan's load budget of 1.2 s fails at every point of the range. Open issue 73's loader levers stay needed.
- **What is trait-specific** and what is packaging is stated apart (§2.5). The direction review's caution stands: on this workload, plain code has been as fast in every pair measured.
- **Seven experiments,** each minutes to an hour of machine time (§4). Two of them are the user's examples: a `PlotCore` slice with an unchanged upstream recipe on top, and an ODE algorithm package written against a trait core.
- **Pushback for the user** (§3.4): open issue 75's form; the parameters' type as a key against the cache; workloads as the only way ahead for the solver's driver; the load prediction; the SciML migration's transition.

## 1. The architecture

### 1.1 The shape both libraries share

| Layer | What it is | Mode | Loads |
|---|---|---|---|
| user API (the umbrella packages `Makie`, `CairoMakie`, `OrdinaryDiffEq*`, `SciMLBase`'s front end) | upstream's names, keyword parsing into typed records, normalization at the entry, stubs | plain (its bounded workers: facts) | at `using` |
| compatibility layer | the old author API, run above the core | plain | at its first use |
| implementation packages | recipe and block groups, backends, algorithm packages; each a trait module implementing the core's traits for its own types | facts | at `using` when the user names them, else at first use |
| trait core (`PlotCore`; `SciMLBase`'s trait module with `OrdinaryDiffEqCore`'s integrator family) | the traits of the open sets, the core's concrete types, the bounded functions | facts | at `using` |
| TraitWorld, BaseTraits, the patched Julia | | | at `using` |
| the cache across sessions | one generated package per dependency set ([the cache note](2026-10-27-session-cache.md) §3) | both owners | with its dependency set |

**The waist.** Five rules keep the core narrow. Each rests on a reference; none is new.
1. **The core reaches what it does not own only through declared operations.** These are operations on kept values (`Kept{Plot}`, `Dynamic{Transform}`, [traits §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)), calls of `Callable`s ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)), and bounded functions compiled per key ([§6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)). The core never names a provider's or the compatibility layer's types. An operation on a kept value whose implementation the core's image does not know goes through the table of the call's targets ([facts §9](../reference/facts.md#9-the-dynamic-split); [compiler §4.3](../reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)). Such a call holds no edge to the provider.
2. **Implementations reach the core by `@implement` for their own types,** the type owner's right ([traits §10.1](../reference/traits.md#101-who-may-implement)), and by calling bounded functions. A provider adds no method to the core's or the umbrella's functions, except for its own types (porting A4).
3. **The compatibility layer is ordinary code that uses the trait world** ([traits §2](../reference/traits.md#2-trait-modules): a package is an ordinary module around its trait module). Its plot objects conform to the core's `Plot` as one family.
4. **The user API is thin** (porting 0.3, 0.5, A3, A7). It turns keywords into typed records, converts arguments at their bounds, and calls bounded functions. Front ends stay plain, behind a function barrier, as TraitDifferentialEquations' `solve` does.
5. **The entry normalizes call shapes** (class (f) of [the plan](2026-10-27-ttfx-sciml-makie.md) §5): saving times to `Vector{T}`, tolerances to `T`, plot data to the core's position families, attribute values to typed records. So the core's keys are few, and a cache recurs (E-173, E-178).

### 1.2 Makie

**The core, `PlotCore`.** The traits are [the rewrite's](../explorations/makie-rewrite.md) §2, in today's spelling. Each open set and its members:

| Trait | The open set | Implemented by | Loads with |
|---|---|---|---|
| `Positions{N, T}`, `Coords{T}` | point and coordinate data | the core for Base's arrays and `Point`s; users by forwarding (`@implement Positions{2, Float64} Trajectory by data`) | the core; the user's package |
| `GridData`, `ImageData`, `MeshData` | grid, image and mesh data | the core; users | the core |
| `ColorSpec` (`resolve(c, ctx)::ResolvedColors`) | attribute values with several shapes | the core for `Symbol`, colorants and vectors; users | the core |
| `Plot` (`children`, `datalimits`, `emit!`) | recipes | the core's primitives; recipe groups; new-style recipes; the compatibility layer's `Plot{F, T}` family | the core; at first use |
| `Backend` (`draw!` per primitive kind) | backends | `CairoMakie`; GL and WGL backends | `using CairoMakie` |
| `Transform` | axis scales | the core for `typeof(log10)`, `sqrt`, `identity`, `pseudolog10`; users | the core |
| `Ticks` | tick locators and formats | the core (`LogTicks`, Wilkinson); a user's function as `Callable{Tuple{Float64, Float64}, Vector{Float64}}` | the core |
| `Layoutable` | blocks | the core's `Axis` and `Label`; block groups (`Colorbar`, `Legend`, `Slider`, …); users | the core; at first use |
| `AxisValues` | dates, units, categories | extensions (Unitful, Dates), the core for categories | with the user's package |
| `Interaction` | mouse and keyboard handlers | the interaction group | with an interactive backend |

- **Concrete types:** `Point{N, T}`, `RGBAf`, `Rect2f`, `Mat4f`, `ResolvedColors`, `ColorContext`; the primitives (`LinesPrim`, `ScatterPrim`, `PolyPrim`, `TextPrim`, `ImagePrim`, `MeshPrim`); `Scene`, `Figure`, the grid, the core's `Axis`; a typed `Theme` record.
- **Bounded functions:** conversion of data into the position families; colour mapping; the `Float32` conversion; data limits; tick placement; text layout over FreeTypeAbstraction; the render walk, which emits each plot's primitives and hands them to the backend.
- **Derived values:** first as TraitMakie does, by rebuilding children before each render (`refresh!`). A typed graph (`Node{T}`, `Derived{T}`, the rewrite's §3) comes where a measurement asks for it.
- **The layout:** GridLayoutBase's solver, called as it is first (compiled by facts on the core's path, [facts §6.2](../reference/facts.md#62-the-mode-rule)); ported behind `Layoutable` where its untyped content costs.

**The user API, unchanged.** The workload's plot (`experiments/ttfx/plotting.jl`), call by call:
- `using CairoMakie` loads the umbrella `Makie` (names, the old API's types, stubs), `PlotCore`, the Cairo backend and the cache's plotting parts (§1.4).
- `Figure(size = (800, 600))` and `fig[1, 1]` are the umbrella's constructors of the core's `Figure` and grid positions.
- `Axis(fig[2, 1]; xscale = log10)`: the umbrella parses the keywords (about 140 attributes in upstream's `@Block Axis`) into the core's typed axis record. `log10` becomes a `Kept{Transform}` by `convert(Transform, log10)` ([traits §7.3](../reference/traits.md#73-assigning-from-plain-code)). The axis is placed through `Layoutable`.
- `lines!(ax, a.t, y)`:
  - the umbrella converts `x, y` into the position family (`Vector{Point2d}`, by `Coords` per argument and a combination in the worker);
  - it converts the keywords into a typed attribute record;
  - it calls the core's `add_lines!(ax, pos::Dynamic{Positions{2}}, attrs)`. That is compiled once per position family, as TraitMakie's recipes are (porting A12).
  - **An argument the core does not convert** (`lines!(ax, 0..1, sin)`, a user type with only a `convert_arguments` method) goes to the compatibility layer's conversion cascade, which produces the same core primitive. Upstream's semantics for the long tail are upstream's code.
- `save(path, fig; px_per_unit = 1)`: `save` stays FileIO's binding, re-exported, so a script that also uses FileIO keeps working. Makie's method for PNG, SVG and PDF draws through the active `Backend`. Other formats load FileIO's format machinery at first use.
- **Plot objects keep their property API:** `p.color = :red`, `p.color[]`, `p[1]`, `on(p.color)`. The ordinary layer provides it as sugar over the core's typed fields, as TraitMakie's `p.color = x` converts at the field's bound ([traits §7.3](../reference/traits.md#73-assigning-from-plain-code)). The observable-style forms (`on`, `lift` of a plot's attribute) load the compatibility layer.
- **A user's `Observable`** passed as data is subscribed by the umbrella (plain `on`). The new value is converted at its bound into the core's input, which the core reads at each render. Users' `lift` chains stay Observables'.

**Recipe authors: the old API kept, a new one beside it.**

*Old style, unchanged.* `@recipe`, `Makie.plot!(p::MyPlot)`, `map!(p, inputs, output)`, `lift`, `Observable`, `Attributes`, `shared_attributes`, `Makie.convert_arguments`, `Makie.plottype`, `Makie.used_attributes`, `Makie.expand_dimensions` and `SpecApi` keep their meaning. SciMLBase's Makie extension uses most of them (`SciMLBase/ext/SciMLBaseMakieExt.jl`).
- **The names and types** live in the umbrella: `Plot{F, T}`, `Attributes`, `Observable`, the `@recipe` macro, empty generic functions. They load at `using`; ComputePipeline loads in 2 ms and Observables in 6 ms (E-169's imports). A recipe package that loads defines methods for its own `Plot{typeof(myrecipe), T}`, a stakeholder's methods.
- **The machinery** is upstream's creation pipeline, conversion cascade (140 `convert_arguments` methods), `convert_attribute` (95), the plot's ComputePipeline graph and theming. It lives in the compatibility layer, loaded at the first old-style plot. It runs upstream's code unchanged.
- **The leaves are core primitives.** `lines!(p, attrs, data)` inside an old `plot!` creates the core's `LinesPrim` as a child. Its inputs are fed by a bridge: an edge `Callable{Tuple{}, Vector{Point2f}}` that resolves the compatibility graph's node and converts its value. The core calls it as a `Dynamic` callable ([traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)), so it holds no edge into the compatibility layer.
- **The family:** `@implement Plot Plot{F, T} where {F, T}`, declared by the compatibility layer, which owns `Plot{F, T}`. Its operations call the compatibility layer's own functions (`data_limits`, the children list), which old recipes extend for their own types. No old recipe overrides a core operation, so the refusal of late overrides ([traits §4.9](../reference/traits.md#49-checks-at-the-declaration); open issue 63) never meets one.

*New style.* A type of the author's own that implements `Plot` in a trait module (the rewrite's §3 `Stairs`; TraitMakie's `Lollipop` in its tests):

```julia
# in a recipe package's trait module (a sketch, not run)
mutable struct Lollipop
    pos::Vector{Point2d}
    color::ColorSpec                    # Kept{ColorSpec}: the shape may change
    stems::LinesPrim
    heads::ScatterPrim
end
@implement Plot Lollipop begin
    children(r) = Kept{Plot}[r.stems, r.heads]
    datalimits(r) = datalimits(r.heads)
end
```
- Its bounded functions at its key are compiled into its author's image when the package is precompiled ([traits §13](../reference/traits.md#13-compiling-ahead)). It is protected by the facts rule and kept by the cache.
- **A typed `@recipe` form** is optional: an attribute block whose entries carry types (`step::Symbol = :pre`) and typed arguments (`@recipe` already takes argument types: `types_for_plot_arguments`) could generate such a struct and its `@implement`. A Makie-side macro; no reference change.

*Coexistence.* One axis keeps `Vector{Plot}`, that is `Vector{Kept{Plot}}`: core primitives, new-style recipes and old-style `Plot{F, T}` side by side. An old recipe may have new-style children (through the API's functions), and the reverse. Both read the same theme: the compatibility layer's `theme(scene, :key)` reads the core's `Theme` record.

*Makie's own 64 recipes and 16 blocks* (makie-rewrite §1) are not ported at once:
- the core holds the primitives, `lines`, `scatter`, `text`, `poly`, `image`, `heatmap`, `mesh`, and the `Axis` and `Label` blocks;
- the other recipes run first as old-style recipes, from upstream's source unchanged, in groups loaded at first use;
- each moves to the new style when its owner chooses. This is "a library adopts traits one function at a time" ([traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits)) for a plotting ecosystem.
- Upstream's ReferenceTests are the check that both paths draw what upstream draws.

**What loads when (Makie):**

| When | What |
|---|---|
| `using CairoMakie` | TraitWorld; `PlotCore` and its dependencies (colours, geometry, the layout solver, FreeType, Cairo, the PNG writer); the umbrella's names, types and stubs; the Cairo backend; the cache's plotting parts |
| the first call of a recipe or block outside the core | its group, with its cache part: the basic recipes (`barplot`, `band`, `stairs`, `errorbars`, …); the statistics recipes (`hist`, `density`, `boxplot`, …, with StatsBase, KernelDensity, Distributions); contours and triangulations; 3D; the other blocks |
| the first old-style plot, or the first argument the core does not convert | the compatibility machinery |
| the user loads a package | extensions, as today: units on axes, `plot(::Distribution)`, tables, SciMLBase's recipes |
| the first file in another format, a video, an interactive backend's events | FileIO's formats, FFMPEG, the interaction group |

### 1.3 SciML

**The core:** SciMLBase's trait module, which owns the problem and solution types and `solve`'s front end ([move 3](../explorations/sciml-as-traits.md#4-the-shortest-route)), with OrdinaryDiffEqCore's integrator family and controllers. The traits are [B6's](../intro/porting.md#b6-case-study-scimls-architecture-as-traits):

| Trait | The open set | Implemented by |
|---|---|---|
| `ODEProblemTrait{U, T, P}` (`rhs!`), with `ODEJacobian`, `ODEMassMatrix` as subtraits | problems and models | the canonical `ODEProblem`; packages that build their own (NetworkDynamics' `Network`, E-152) |
| `ODEAlgorithm` (`alg_order`, `isadaptive`, …, defaults where a fallback is right) | algorithms | each solver package |
| `Integrator{U, T, P} <: IntegratorView{U, T, P}` (`step!`, `add_tstop!`, `terminate!`, `u_modified!`, `interp!`; fields `u`, `t`, `p`, `dt`) | integrators | OrdinaryDiffEqCore's `ODEIntegrator` family; Sundials and others their own |
| `Callback{U, T, P}`, `EventCallback{U, T, P}` | callbacks | `DiscreteCallback`, `ContinuousCallback` records (entered at `init`); DiffEqCallbacks; users |
| `Trajectory{U, T}` (`times`, `state`, `at`) | solutions as plotting sees them | `ODESolution` |
| `LinearSolver{T}` | linear solvers for implicit methods | a dense LU in the core; LinearSolve's solvers by its extension |

- **Concrete types:** the canonical `ODEProblem{U, T, P, F, …}`, whose right-hand side is kept at a struct parameter bounded by `Callable{RHSSig{P, T}, Nothing}` ([traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait); TDE's form B, E-157). `ODEFunction` is a plain record. `SolverOptions{T}` is the normalized options record. `ODESolution{U, T}` keeps no function axis (move 5).
- **Bounded functions:** the driver `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P})` (the link between the two traits: [traits §3.4](../reference/traits.md#34-parameters-and-associated-types); the user's choice, closed item 51); saving; event location; the PI controller.
- **What stays inside each solver package, as types:** caches, tableaus, `perform_step!`, controllers. A closed set per package, fully typed over the key, so the facts mode costs them nothing (B6).

**The user API, unchanged.** The workload's calls (`experiments/ttfx/workload.jl`):
- `ODEProblem(lorenz!, u0, tspan, p)`: SciMLBase's plain constructor detects the in-place form by reflection, as today, and builds the canonical problem. `F` is `Dynamic{Callable{RHSSig{P, T}, Nothing}}` by `Callable`'s default: the problem's type does not name `lorenz!`. `ODEProblem(compiled_for(f), …)` and `FullSpecialize` give the per-function form.
- `solve(prob, Tsit5(); saveat, reltol, abstol)`:
  - the plain front end (`@nospecializeinfer`, a function barrier) builds `SolverOptions{Float64}`: `saveat` as a `Vector{Float64}` whatever was passed, tolerances as `Float64`;
  - `init` is a typed method naming the solver's own algorithm type (B6), here OrdinaryDiffEqCore's for its algorithm types; it builds the integrator;
  - the core's driver runs it; the result is an `ODESolution`.
- `Rodas5P()`: the Jacobian by ForwardDiff duals under the library's tag, the chunk chosen from the state's length at `init` (TDE's `DualJacobian{P, N, FD}`, E-157); a dense LU for small dense systems.
- `sol.t`, `sol.u`, `sol(t)`, `sol[i]`: fields, and the interpolant kept in the solution as a kept value.
- `init`, `step!`, `reinit!`, `remake`, `integrator.u`: plain front ends and fields, as today.

**Problem and algorithm authors: a declared migration.** Allowed by the user (2026-10-27, quoted above).
- **Algorithm packages:**
  - declare `ODEAlgorithm`. Its operations are the existing functions (`alg_order`, `isadaptive`, `isfsal`, …) with qualified names, so existing methods serve them ("an informal interface becomes a trait over its existing functions", porting 0.2);
  - for OrdinaryDiffEq's solvers, one family declaration in OrdinaryDiffEqCore can cover every subtype of its abstract algorithm types: `@implement ODEAlgorithm A where {A <: OrdinaryDiffEqAlgorithm}`, each member checked at its first use ([traits §4.7](../reference/traits.md#47-families)). A sketch, not run;
  - read the options from `SolverOptions{T}` instead of `DEOptions`' 23 type parameters, and the Jacobian through `jacobian!` instead of `f.jac === nothing`;
  - remove the front-end methods that are pirates by the letter (57 of 63 held by joint owners today; [the inside-out plan §2](2026-10-21-ndport-inside-out.md#2-the-pirates-classified)): move 3 puts the body in SciMLBase;
  - a solver without stepping keeps a typed `solve` method on its own algorithm type, as `__solve` today.
- **Problem packages:** build the canonical `ODEProblem` (unchanged call), or implement `ODEProblemTrait` for their own type. An `AbstractODEProblem` subtype that does neither is converted at the entry: its `f`, `u0`, `tspan` and `p` become the canonical record ([traits §4.10](../reference/traits.md#410-types-that-only-convert), a type that only converts). The `sys` field stays out of the problem's type parameters.
- **Coexistence:** the front end asks `conforms(typeof(alg), ODEAlgorithm)`. A migrated algorithm takes the core's path. An unmigrated one raises an error that names the migration, or, if a transition period is wanted, takes a legacy front end loaded at first use: upstream's DiffEqBase and old integrator, plain, at today's costs (§3.4, pushback 5).

**Everything else keeps its API.**
- Callback authors (DiffEqCallbacks), `affect!(integrator)` with `integrator.u`, `integrator.p`, `terminate!`, `add_tstop!`: the integrator conforms to `IntegratorView` and `Integrator`, whose operations are SciMLBase's existing interface functions. A callback receives a `Dynamic{IntegratorView{U, T, P}}` and reads its declared fields (TDE, E-158).
- Symbolic access (`sol[x]`, `integrator.ps`): move 4, with the `getproperty` sugar kept plain.
- SciMLBase's 20 extensions: methods and implementations for their triggers' types (porting A4).

**What loads when (SciML):**

| When | What |
|---|---|
| `using OrdinaryDiffEqTsit5` | TraitWorld; SciMLBase's trait core and front end; OrdinaryDiffEqCore's integrator family; Tsit5's tableau, cache and step; the cache's solver part |
| `using OrdinaryDiffEqRosenbrock` | Rosenbrock's tableaus, caches and steps; ForwardDiff; a dense LU (LinearAlgebra, in the system image) |
| the first call that needs it | the default algorithm's candidates (`solve(prob)` without an algorithm); LinearSolve's default polyalgorithm for a large or sparse Jacobian without a `linsolve`; NonlinearSolve for a DAE's initialization; the legacy front end, if adopted |
| the user loads a package | AD rules, StaticArrays, ModelingToolkit's symbolic access, LinearSolve's solvers passed as `linsolve` |

### 1.4 Loading on demand

**Two cases.**
- **A key:** a value whose type has no implementation loaded (a `Vector{Quantity}`, a `Date`, a `Normal`). The type's own package is loaded whenever such a value exists. So its implementation is its owner's, or the trait owner's extension with that package as trigger ([traits §10.1](../reference/traits.md#101-who-may-implement): an extension's implementation names each trigger). Nothing waits for a first use.
- **A function:** `hist(x)` on a `Vector{Float64}`, `contour`, `voronoiplot`, `solve(prob)` with the default algorithm. The user loaded nothing that would trigger the code. This case needs loading at first use.

**A typed stub,** in the ordinary layer:

```julia
# in the umbrella Makie, plain code (a sketch, not run)
function hist(args...; kw...)
    m = Base.require(MAKIE_STATS)                   # a dependency of Makie; loads it and its cache part, once
    return Base.invokelatest(m.hist_plot, args...; kw...)   # the provider's own function: the stub never calls itself
end
```
- The provider's `Hist` implements the core's `Plot`. Its `emit!` and `datalimits` at its key are compiled into its own image ([traits §13](../reference/traits.md#13-compiling-ahead)).
- The axis keeps the result as `Kept{Plot}`. The core renders it through the table of the call's targets, since the core's image was compiled before `Hist` existed ([traits §6.8](../reference/traits.md#68-costs-and-choosing), "which four").
- **Cost:** the provider's load at the first call (tens to hundreds of milliseconds for StatsBase's tree); then one dynamic call per plot call, not per element.
- **Rules:**
  - a stub forwards to the provider's own function;
  - a provider adds no method to the umbrella's functions, so loading it discards nothing there;
  - stubs stay in plain code: `Base.require` compiled by facts would put the loader on an interop path.

**What the trait design adds** to plain lazy loading (LazyModules gives the same API and the same delay):
1. The core holds no edge to the provider. Loading it discards no core code ([traits §4](../reference/traits.md#4-implementations): an implementation "discards no trait code"; §7.1).
2. The provider's code at the core's keys is in its own image, valid in any load order ([facts §11](../reference/facts.md#11-package-images)).
3. The provider's contract is checked at its `@implement` ([traits §4.9](../reference/traits.md#49-checks-at-the-declaration)).

In plain Makie the same move adds methods to `plot!` and `convert_arguments` at abstract signatures, which discards plain code compiled there.

**What it changes:** nothing in the references. Open issue 75's option (ii) proposed a new kind of implementation, registered by key and loaded at its first use ([the exploration](../explorations/load-on-demand.md) §3). The key case is covered by extensions. That form stays Optional, for a case extensions do not cover (pushback 1).

### 1.5 Where the cache across sessions fits

- **Its parts follow the packages:** one per dependency set, loaded by TraitWorld's package callback as soon as its set is loaded ([the cache note](2026-10-27-session-cache.md) §3). That covers the core, each algorithm package, and each group loaded at first use.
- **What it keeps:**
  - the core's and implementation packages' facts code at library keys. It stays valid in any load order ([facts §11](../reference/facts.md#11-package-images); E-177);
  - the front ends' and the compatibility layer's plain code. It is validated at load, and lost where a later load invalidates it;
  - the first-call checks (E-175).
- **What it cannot keep:** code that names a type defined in the session. That is the user's own functions, parameter structs, recipes and plot data types. With `Dynamic` positions where these enter (the right-hand side, plot data at public entries), the core compiles nothing for them; only entries and the user's own code compile.
- **What makes it recur:** the entry's normalization (§1.1, rule 5). The parameters' type stays a key: the right-hand side reads it (E-178; pushback 2).
- **What images already cover:** the core's own keys (its workloads), and each implementation's keys (compiled ahead from its `@implement`, and its workload). The cache adds the keys and shapes users met.

## 2. Costs and risks

### 2.1 Load and first use

An estimate from floors, for the workload's packages, with strict mode off and images valid:

| Term | Range (s) | Source |
|---|---|---|
| Julia's startup | 0.10–0.12 | E-168 |
| the solver's dependencies (Tsit5, ForwardDiff, a lean SciMLBase) | 0.30–0.47 | E-176: Tsit5, ForwardDiff and DiffEqBase 0.47 s, 98 packages; the lean core drops part of that tree |
| Rosenbrock with a dense LU, without LinearSolve's tree | 0.10–0.30 | E-176: +0.73 s and 55 packages with the linear-solver tree |
| the plotting core's dependencies | 0.51–0.72 | E-176's floor, 66–83 packages; MathTeXEngine is the difference |
| `PlotCore`'s own image | 0.20–0.50 | E-171: 0.30 s for ScaleL's 86.5 MB of native code; Makie's image 0.71 s for all of Makie (E-169) |
| the Cairo backend | 0.10–0.20 | CairoMakie 0.18 s (E-169's imports) |
| TraitWorld and the trait packages' load hooks | 0.10–0.30 | TraitWorld 0.09 s (E-169's imports, D); D against Dp +0.27–0.29 s after TraitWorld's hook fix (04095fe; the README's E-172 section) |
| the cache's parts | 0.10–0.15 | E-173, E-175 |
| shared packages of the two trees | −0.10 | [the direction review](../reviews/2026-10-27-w58-direction.md), finding 5 |
| **load** | **1.4–2.7** | Python 0.45 s; stock 3.5 s; the plan's budget 1.2 s |
| work after the load, with a cache, the recorded shapes | 0.4–1.1 | D 0.4–0.55 s (E-173, E-175); stock 1.1–1.2 s (E-175) |
| **session** | **1.8–3.8** | target about 3 s; Python 1.45 s; stock 9.2 s |

- **The load is the term that matters.** The budget of 1.2 s fails at every point of the range. Open issue 73's loader levers are orthogonal to this architecture and compound with it: validation and activation remembered for an unchanged environment (up to about 2.2 s of stock's 3.3 s), and facts images without edge validation under strict mode (it scales with the facts share, nearly all of a trait world).
- **First use without a cache** (a first session, or new shapes):
  - the core's own keys come from images;
  - a new key compiles once per environment, then the cache keeps it;
  - a new user function, model or recipe compiles nothing in the core where its position is `Dynamic`: D's second model 0.056 s against Dp's 0.33 s (E-168).
- **Facts copies of Base.** In the product setting, a Base method that facts code reaches is compiled by facts in the session unless an image holds that copy ([fast-loads](../explorations/fast-loads.md) §2). The core's workloads must reach them; a facts system image for the product setting is the alternative (fast-loads §3 item 1).
- **The solver's driver is not compiled ahead from declarations.** It has two trait positions, and `ODEIntegrator` is a family; both are compiled at first call or by a workload ([traits §13](../reference/traits.md#13-compiling-ahead); [lowering L-15](../reference/lowering.md#18-deviations)). Algorithm packages keep workloads, as upstream's do (pushback 3).
- **Loads at first use** move their cost into the session, as matplotlib's lazy imports do (E-168: its backend loads inside the first plot). The workload's script triggers none.

### 2.2 What the compatibility layer costs

- **At `using`:** the old API's names and types only. ComputePipeline 2 ms, Observables 6 ms (E-169's imports); the umbrella's types and empty functions add few methods.
- **At its first use:** its machinery's image, a part of Makie's 0.71 s image (E-169). The share is not measured (X1). An old recipe package loads only the names at its own load. Its workload, run at precompile time, loads the machinery then; the machinery is then a recorded dependency of that package's image, as any.
- **Per old-style plot:** today's cost. Conversions and the creation pipeline are compiled per recipe and argument types, plainly. Code at a type defined in the session is not cacheable.
- **Per frame:** one operation on a `Kept{Plot}` per plot, through the table (9–18 ns, [other-languages §11](../design/other-languages.md#11-heterogeneous-collections)); one indirect call per bridged edge recomputed.
- **None of it reaches the core:** the core calls the compatibility layer only through `Dynamic` callables and kept values.

### 2.3 Invalidation and the facts rule across the layers

| Layer | Mode | What can discard its compiled code | In the cache |
|---|---|---|---|
| trait core; implementation packages written as trait modules | facts | a stakeholder's change (edits, upgrades, their extensions); a winning pirate unless strict mode refuses it ([facts §2.2](../reference/facts.md#22-g2-stable-caches)) | facts code at library keys, valid in any load order |
| plain dependencies the core reaches (GeometryBasics, FreeType, Cairo.jl, GridLayoutBase, ForwardDiff) | facts on the core's path ([facts §6.2](../reference/facts.md#62-the-mode-rule)), plain elsewhere | as the core, for the facts copies | the facts copies |
| the user API's front ends | plain; their bounded workers facts | any owner's method at an abstract call; a fully typed front end only by stakeholders and pirates ([design §2.1](../design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)) | plain code, validated at load |
| the compatibility layer and old recipes | plain | as today: E-177's 6.1 s after a late DataFrames load is Makie's plain path | plain code, validated at load |
| the user's script | plain | — | not kept |

- **The core is protected across every load in a session,** including groups loaded at first use, old recipe packages and the compatibility machinery. It depends on the method table only through facts, and it reaches the other layers only at run-time sites or through the table. At scale this is E-177's result: Makie's plot path compiled by facts recompiled 0.02 s after a late DataFrames load, plain 6.1 s.
- **The plain layers keep today's exposure.** Their size on the workload's path is what decides it: the front ends are thin, and the compatibility layer is absent unless an old-style plot is made.
- **Strict mode** refuses a pirate that would win at a fact of the core ([facts §10.2](../reference/facts.md#102-strict-mode)). Its prototype's check at load costs 6.6 s at this scale (E-168, C/s). So it is off here until its intended design at image validation ([facts §10.3](../reference/facts.md#103-strict-modes-intended-design); open issues §1, deferred item 1).
- **G1 in every layer:** each computes what plain Julia computes, or raises. The ports check digests and pixels against upstream.

### 2.4 What stays plain, and why that is fine

- **Front ends:** keyword parsing, normalization, `remake`, reflection on the user's function. They run once per call, in microseconds, behind a function barrier. Bounded keywords are limited today (T-48, T-39), so plain is also the only form (porting 0.5).
- **The compatibility layer and old recipes:** they keep today's costs, are loaded only when used, and run above a core they cannot discard.
- **Observables, notification and `lift` chains:** ordinary code above the trait world (porting 0.5; TraitMakie's `onchange`).
- **Sugar:** `getproperty` switches (`sol.t`, `integrator.ps`, `p.color[]`), printing, the `@recipe` and `@Block` macros.
- **The legacy SciML front end,** if adopted: loaded only for unmigrated algorithms.
- **Plain dependencies on the core's path** are compiled by facts there anyway; their plain copies serve plain callers only.

### 2.5 What is trait-specific, and what is packaging

**Packaging; plain code could do it too:**
- lean trees, recipe groups and algorithm packages;
- lazy stubs (LazyModules);
- normalizing at the entry;
- erasing the user's function by hand: SciML's `AutoSpecialize` already makes stock's solver cacheable (E-175).

**Trait-specific, to be shown at scale:**
1. **A checked waist.** Groups, old recipe packages and the compatibility machinery load at any time and discard none of the core (E-177). A plain core is exposed to each of them.
2. **One cache per environment, with no load-order key.** Facts code stays valid in any order ([facts §11](../reference/facts.md#11-package-images)); plain caches were keyed by order ([alternatives](../design/alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed)).
3. **`Dynamic` positions by default where user types enter.** A new function, model or recipe compiles nothing in the core, and its signature is checked at every call (E-168: D's second model). Plain code erases by hand, with listed exceptions (SciML's six levels).
4. **Old code above a protected core.** The compatibility layer's and old recipes' invalidations stop at the waist.
5. **Contracts checked at `@implement`** for every provider, whenever it loads.

[The direction review](../reviews/2026-10-27-w58-direction.md) (finding 1) stands: with a cache, the plain twins were as fast as the trait demonstrators in every pair on this workload. §4's experiments test items 1–4 where a plain form would lose.

### 2.6 Risks

1. **Makie's own code on the workload's path may be large.** `Axis` (about 140 attributes, ticks, labels, spines, interactions registered at construction), text layout and the grid. Not measured (X1).
2. **Two creation pipelines.** The compatibility layer must reproduce upstream's behaviour for every old recipe. Packages that reach Makie's internals (AlgebraOfGraphics, GeoMakie, GraphMakie) keep working only as far as the compatibility layer carries those internals.
3. **The bridge:** pull-based updates between ComputePipeline's graph and the core's inputs, and attribute values that change type (a `Kept{X}` input where they may).
4. **The parameters' type is a key** (pushback 2). A parameter struct defined in the user's script compiles the solver in every session (TDE's first solve with `Tuple` parameters +1.35 s, E-168).
5. **Two owners:** a Base method reached from plain and from facts code is compiled twice. That costs image size and precompile time.
6. **Precompile time grows** with compile ahead per `@implement` and with workloads per group.
7. **`save` and FileIO:** the binding must stay FileIO's; FileIO binds Pkg (0.13 s at load, E-169's imports). Makie binds REPL (0.06 s).
8. **The text engine:** MathTeXEngine is 0.21 s of the floor (E-176). The workload's log axis needs rich-text tick labels (superscripts), not LaTeX; whether the core can leave MathTeXEngine to LaTeX strings, loaded at first use, is X1's question.
9. **Strict mode's load cost** (§2.3).
10. **The load target** (§2.1).

## 3. Options considered

### 3.1 Makie

| Option | For | Against | Verdict |
|---|---|---|---|
| M1. Upstream wrapped by facts, a typed front, no core (the port note §4, steps 1–2) | every API kept as it is; protection measured (E-177) | the load stays Makie's (2.3–2.7 s); no open sets as traits; the typed front buys nothing on this workload ([the review](../reviews/2026-10-27-cache-and-port-notes.md) M6) | a baseline, not the end |
| M2. A lean fork, plain (open issue 75, option (i); E-179) | simple | drops features, against the API; saves 0.4 s | rejected |
| M3. A trait core with the compatibility layer above, all loaded at `using` ([the rewrite](../explorations/makie-rewrite.md) §6) | API kept; core protected | loads Makie's own code as today: no load gain | rejected as it stands; M5 is M3 with loading by use |
| M4. Compatibility below the core: old recipes translated into trait recipes by the macro | one pipeline | `plot!` bodies are arbitrary code (`lift`, `map!`, untyped values); no general translation; result types unknown until run | rejected as the general path; kept as the optional typed `@recipe` form |
| **M5. A trait core; groups, blocks and the compatibility machinery loaded at first use; the API in a thin umbrella** | API kept by names and stubs; only the path in use loads; old recipes run unchanged; new recipes in the trait world | two pipelines; the bridge; an estimate, not a measurement | **recommended** |
| M6. Two stacks side by side (upstream for old recipes, the core for new) | no bridge | two scene models cannot share an axis; both load when mixed | rejected |

### 3.2 SciML

| Option | For | Against | Verdict |
|---|---|---|---|
| S1. Upstream wrapped by facts, with normalization at the entry (setting C plus move 1b) | cheap; recurrence where shapes normalize (X5) | not lean (Rosenbrock's tree, DiffEqBase's front end); 57 pirates held by joint owners; open sets informal | the first stage, not the end |
| **S2. A trait core with the open sets as traits; algorithm and problem authors migrate; the user API unchanged** (B6's moves 1–5) | lean; checked contracts; no pirates in the core; the user's function out of every type | a migration for solver packages | **recommended** |
| S3. S2 plus a legacy front end for unmigrated algorithms, loaded at first use | old algorithms keep working during a transition | carries DiffEqBase's front end and its joint owners | optional (pushback 5) |
| S4. TraitDifferentialEquations scaled up, with its own API | already built | changes the user API | rejected |

### 3.3 Loading on demand and the compatibility layer's place

- **O1. Package extensions only:** `hist(x)` would need `using StatsBase` first. Against the user's constraint. Rejected for functions; right for keys.
- **O2. A new kind of implementation, registered by key** ([the exploration](../explorations/load-on-demand.md)): more than needed, since keys are covered by extensions. Optional.
- **O3. Typed stubs for functions, extensions for keys:** **recommended** (§1.4).
- **O4. Everything at `using`:** the status quo; the load follows Makie's own code.
- **The compatibility layer as trait code** instead of plain: its `Dict{Symbol, Any}` and `Any` values would put it on the facts mode's interop tails ([design §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap)), for no guarantee the core needs. Rejected.

### 3.4 What it would change in the references, and pushback

**The recommended architecture changes no reference.** It uses the language as it stands: trait modules inside ordinary packages (traits §2), implementations by the type's owner (§4, §10.1), kept values and `Callable`s at the waist (§5.8, §7), compile ahead (§13), extensions that implement for their triggers (§10.1).

**Changes that come with parts it relies on:**
- **The cache** (open issue 72), when adopted: [the cache note](2026-10-27-session-cache.md) §3's list. That is lowering §15 (a third source of code compiled ahead) and §16 (the session's recording, the cache's load), facts §11 (cache images), compiler §2.9 (an image of code compiled for another owner from a list).
- **A registry by key** (Optional, only if a case appears that extensions miss): traits §4 (a new form of implementation), §5.5 (what a bound does with a registered key not yet loaded), §13; lowering §8.2 (the entry's slow path) and §16 (the registry at load).
- **The porting guideline** (`intro/porting.md`, not a reference), after X3 and X4: a part on a large library, with a lean core, groups loaded at first use, a compatibility layer and typed stubs.

**Pushback for the user** (none decided here):
1. **Open issue 75.** This memo answers it with extensions for keys and typed stubs for functions, and no reference change, instead of option (ii)'s new kind of implementation. Recommended: adopt this form; keep (ii) Optional.
2. **The parameters' type against the cache.** `P` stays a key of the solver (move 1b; E-178). A cache then never covers a parameter type defined in the user's script. Erasing `P` at the solver's entry, while the right-hand side keeps its checked call, needs the checked downcast of a kept value ([open issues §2](../open-issues.md#2-design), item 16; PB-E). Decide after X6 whether it goes on the port's path.
3. **Compile ahead does not reach the solver's driver** (two trait positions; a family). Workloads are its only way into images ([traits §13](../reference/traits.md#13-compiling-ahead), L-15). No change proposed; X4 measures what it costs.
4. **The plan's load prediction fails** under this architecture: 1.4–2.7 s against at most 1.2 s ([the plan](2026-10-27-ttfx-sciml-makie.md) §3). The target of about 3 s holds only in the lower half of the session's range, with a cache. Open issue 73's loader levers then become a prerequisite, not a second lever.
5. **The SciML migration's transition** (mine): the port requires the migration and raises an error naming it for an unmigrated algorithm. A legacy front end loaded at first use (S3) is recorded as the option, if the ecosystem needs a transition period.
6. **Makie's own recipes run first through the compatibility layer, from upstream's source** (mine). They move to trait recipes one at a time.

## 4. The smallest experiments

Each gets a registry row before it runs (question, and the result that would change the architecture). Each runs alone, niced, under the shared lock: minutes to an hour of machine time, a warm-up and two sessions where a time is measured.

**X1. What Makie's own code on the workload's path is** (no new code; minutes).
- **Build:** run the recorder (`experiments/ttfx/cache/record_cis.jl`) over the workload's plot in S. Group the CodeInstances it creates and uses by Makie's source file. In one session, count Makie's methods and external methods by source file.
- **Gives:** the files a `PlotCore` slice must hold; the compatibility machinery's share of Makie's image (`compute-plots.jl`, `conversions.jl`, `recipes.jl`, `attributes.jl`, theming); whether the log axis's tick labels reach MathTeXEngine.
- **Would change:** if the path needs most of Makie's methods, splitting cannot make the core lean, and open issue 73's loader levers come first.

**X2. The solver's lean load** (no new code; minutes).
- **Build:** from the existing `@time_imports` logs, OrdinaryDiffEqRosenbrock's own increment, and what LinearSolve's tree adds; then one session that loads Tsit5 and Rosenbrock with LinearSolve kept out of the path, if a stub of the dense-LU path exists.
- **Gives:** the solver's terms of §2.1 measured instead of estimated.

**X3. A `PlotCore` slice with an unchanged upstream recipe on top** (the user's first example; under an hour of machine time).
- **Build:**
  - TraitMakie extended with a two-row grid, an `Axis` with `xscale = log10` (a `Transform`, `LogTicks`), FreeType tick labels, `lines!` and `save(…; px_per_unit)`;
  - an umbrella module named `CairoMakie` in its own environment, so that `experiments/ttfx/plotting.jl` runs unchanged;
  - a minimal compatibility layer with upstream's `@recipe`, `Plot{F, T}`, a ComputePipeline graph per plot, `map!`, `shared_attributes` and the bridge, loaded at the first old-style plot;
  - upstream's `basic_recipes/stairs.jl` copied unchanged as the old recipe.
- **Measures:**
  - `using` time;
  - the first plot;
  - the old recipe's first plot, with the machinery's load;
  - after a late DataFrames load: CodeInstances lost and seconds recompiled, core against compatibility layer;
  - the PNGs against upstream's.
- **Predicts:** load within E-176's plotting floor plus 0.3 s; first plot under 0.2 s from images; nothing of the core recompiled after the late load.
- **Would change:** a slice that already loads in over 1 s with a fraction of Makie's features says the per-feature load is too high for M5 without the loader levers. A bridge that makes the core name the compatibility layer's types says the waist is not narrow.

**X4. An ODE algorithm package written against a trait core** (the user's second example; minutes of machine time).
- **Build:**
  - TDE's `ODECore` as the core, with `ODEAlgorithm` declared over existing functions;
  - Tsit5 moved into a package of its own, with a typed `init` and its integrator as a family member;
  - the front end with SciML's keyword names, normalized into `SolverOptions`; Rodas5P in a second package after it.
- **Measures:**
  - `using` per package;
  - the first solve from images, with and without the algorithm package's workload (pushback 3);
  - a second algorithm package loaded after the first solve: core CodeInstances lost (predicted 0);
  - the workload's `solve` lines unchanged, digests equal to TDE's.
- **Would change:** a driver that cannot be kept in the algorithm package's image without a workload over every key makes the cache, not images, the solver's main store.

**X5. Normalization at the entry, at upstream scale, plain** (the claim of move 1b; minutes).
- **Build:** a wrapper that turns a range of saving times into a `Vector{Float64}`, tolerances into `Float64` and fixes the keywords' order, before upstream's `solve`. A CodeInstance-level cache recorded from a session with ranges, used by one with vectors; the parameters' type the same in both (E-178 changed it too).
- **Predicts:** the first solve near the cached 0.3–0.5 s, not 3.7 s.
- **Would change:** a solver that still compiles has keys the entry cannot normalize (through `ODEFunction`'s or `DEOptions`' type parameters). Then move 1 is needed for recurrence, not only for its other pay-offs.

**X6. The parameters' type as a key** (minutes).
- **Build:** D, and S, with a cache recorded for `Vector{Float64}` parameters; sessions with a `NamedTuple`, a `Tuple`, and a struct defined in `Main`.
- **Measures:** the first solve's compilation per new parameter type.
- **Decides:** pushback 2.

**X7. A typed stub, at small scale** ([the direction review](../reviews/2026-10-27-w58-direction.md) 1(b); minutes).
- **Build:** TraitMakie's `hist` and its binning moved into a provider package loaded at the first `hist` by a stub in the ordinary layer; PlainPlots the same, as the control.
- **Measures:**
  - `using` without the provider;
  - the first `hist` (the provider's load and first call);
  - CodeInstances of the core lost when the provider loads, against the plain twin's;
  - the stub's cost per call.
- **Would change:** a provider whose load discards core code says the waist leaks. A plain twin that loses nothing either drops the trait-specific claim for loading on demand at this scale, as E-177 framed its own.

**Order:** X1, X2, X5 and X6 first (no new build: they bound the architecture's terms). Then X7 (the smallest new build). Then X3 and X4. W-58's lean Rosenbrock fork ([the direction review](../reviews/2026-10-27-w58-direction.md), ranked 3) is X2's larger form, if X2 leaves the question open.

## 5. Without the large ports: what can be shown, and what only the ports can show

**Can be shown now, on the demonstrators, slices and emulations:**
- each mechanism of the architecture, at small scale:
  - late loads discard none of the core (E-177, done);
  - a cache split by dependency set (E-177, done);
  - an unchanged upstream recipe over a trait core (X3);
  - an algorithm package against a trait core (X4);
  - typed stubs (X7);
- upstream's terms that bound the architecture: Makie's code on the path (X1), the solver's lean load (X2), normalization's effect on recurrence (X5), the parameters' key (X6);
- the checks: contracts at `@implement`, errors that name the bound, readable types (the demonstrators' rows);
- coexistence in one figure of an old recipe, a new recipe and core primitives (X3).

**Only the ports can show:**
- the load of a full-featured core: whether Makie's own code, as trait code split by use, loads within budget at Makie's size, edges into its dependencies included;
- the whole API surface normalized into typed records without a change in behaviour: `Axis`'s attributes, the 64 recipes, the conversions, `solve`'s keywords; upstream's ReferenceTests and SciML's suites as the check;
- the ecosystem's old recipes unchanged at scale (GraphMakie, AlgebraOfGraphics, GeoMakie, SciMLBase's recipes), and their costs;
- the cache's size and load at full scale, and its recurrence under varied use, not self-replay ([the direction review](../reviews/2026-10-27-w58-direction.md), finding 3);
- strict mode at this scale, with its intended design;
- the session against Python's: the only number the user's goal names.

**So W-61's wrap-up can close** the design questions this memo raises: open issue 75's form, pushback 2–5, the cache's references when adopted. It can also run X1, X2 and X5–X7, before any port. X3 and X4 are the ports' first steps, and their smallest form.

## 6. Questions for review

- Is the waist really narrow? Does any path make the core hold an edge to a provider's or the compatibility layer's method: the bridge, the theme, `Observable` inputs, the compatibility family's operations?
- Do typed stubs plus extensions cover every API function whose implementation is heavy? Is a case missed that needs a registry by key?
- Is the estimate of §2.1 fair? Which terms are optimistic (PlotCore's image, the solver's dependencies)?
- Is the migration for algorithm authors as small as claimed: a family over OrdinaryDiffEqCore's abstract types, plus `SolverOptions` in place of `DEOptions`?
- Are the trait-specific claims of §2.5 testable by §4's experiments, and do those experiments have plain controls where a claim needs one?
