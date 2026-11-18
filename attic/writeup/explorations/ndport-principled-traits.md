# The principled traits of the NetworkDynamics port

Status: exploration, input to the W-32 traits plan (P2); 2026-10-21. Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) above all). Where this page says the design should be otherwise, that is pushback for the log ([the meta plan](../plans/2026-10-21-networkdynamics-port.md), "The pushback log"), not a change.

**Addendum (2026-10-21):** the user: "In the case of DiffEq.jl solvers should probably be considered an open set...". Where this page treats algorithms as a closed family (a type tree, plain methods), the porting guideline's case study (`../intro/porting.md`, B6, "The solvers are an open set") holds the corrected form; the gap is pushback W34-1.

Every claim about the packages is read from the clones in `ndport/pkgs/` (versions: `ndport/pkgs/VERSIONS.tsv`). File and line references are to those clones. No Julia was run for this page; what needs a measurement is listed in §11.

## Summary

- **The one change that pays for the workload is in NetworkDynamics, not in SciML.** The user's component functions reach the `Network`'s type through the batches (`ComponentBatch{T,F,G,FFT,…}`, `network_structure.jl:181`; `Network{EX,G,NL,VTup,…}`, `:88`). The `Network` is the ODE right-hand side and also the problem's `sys`, so its type reaches `ODEFunction`, `ODEProblem`, `ODEIntegrator`, `ODESolution` and every symbolic getter. Changing the equations therefore recompiles the core loop, the solver's driver and the solution's indexing. Keep the component model as a kept value of a trait (`Kept{VertexDynamics}`) and open it once per batch with `compiled_for`: the per-component loop stays compiled per model type, as today, and nothing above it depends on the model's type.
- **The principled traits, per ecosystem:**
  - Graphs: `Graph{V}` (the `AbstractGraph` interface as a checked contract); NetworkLayout: `Layout{Dim, Ptype}`.
  - NetworkDynamics: `ComponentDynamics` with `VertexDynamics` and `EdgeDynamics` (the component's `f` and `g` as operations, `Dynamic` by default); `NetworkRHS` is not a trait of its own: the `Network` conforms to SciML's right-hand-side trait.
  - SciML: `ODERHS{T, P}` (the right-hand side, with the Jacobian and mass matrix as refinements), `IntegratorView{U, T, P}` (what callbacks see), `Callback`, `IndexProvider` and `ValueProvider` (SymbolicIndexingInterface), `Trajectory{U, T}` (a solution as plotting sees it).
  - Makie and GraphMakie: the data traits behind `convert_arguments` (`Positions{N, T}` first) and `Graph` at the recipe's argument. Recipes, attributes and the compute graph stay plain.
  - Observables: `Source{T}`, last, and only where a Makie bound needs it. Observables itself stays plain.
- **The first three to introduce:** (1) `VertexDynamics`/`EdgeDynamics` in NetworkDynamics, with the batch barrier; (2) `Graph` in Graphs, with `Layout` as its small sibling, used by NetworkDynamics' index manager and GraphMakie's recipe; (3) `ODERHS` at the seam from NetworkDynamics to OrdinaryDiffEq, with `Network` conforming and the integrator's `f` a kept function.
- **The main pushback:** the open set of element types (Float64, several `Dual` tags, sparsity tracers) against `Callable`'s constant argument types (traits §5.8); the six-argument limit of a `Dynamic` function (T-51), which edge output functions exceed; kept values hide the user's object where plain code reads it back (`get_graph`, `integrator.f.sys`; open issue 16); SciML's cross-package methods on SciMLBase's abstract types are pirates by the letter (traits §10.2), so compiling DiffEqBase as a trait module needs `delegate!` first; membership decided per value (`f.jac === nothing`) where a trait decides per type.

## 0. How to read this

**What the workload does** (the user's words, [W-32](../record/todo.md)): define equations, build a network, simulate, plot with GraphMakie, watch trajectories through Observables while simulating, change the equations, run everything again. "Benefit" below means, in this order:
1. the run after changing the equations compiles as little as possible;
2. a new data type in a plot, or a new graph type, compiles only its own conversion;
3. mistakes are caught at a declaration with a readable message;
4. the first run in a fresh session is not slower.

**The rules of the reference this page leans on.**
- A bound ranks below every type (traits §5.5): a library adopts traits one function at a time, and typed methods keep winning.
- A plain value entering a bound is `Compiled` where the code knows its concrete type, `Dynamic` where it does not (§6.2); a trait with `@default_with_dynamic_self` makes values from outside the trait world `Dynamic` (§6.3), which is the default for "a solver's model".
- `compiled_for(x)` on a `Dynamic` value is a function barrier written where it is wanted (§6.4, §6.8). A library's cast overrides the caller's (§6.4).
- `Compiled` code is compiled per key, what the trait sees of the value (§6.7). A `Dynamic` value's operations split over the first four implementations, then a table (§6.8; facts §9).
- A `Callable`'s argument types are a constant (§5.8); a function kept at several signatures is a tuple (§7.5, Planned, W-29).
- A struct parameter bounded by a trait or a `Callable` keeps the value as its bound gives it (§7.4): the user's object under `Compiled`, `Dynamic{X}` under `Dynamic`.
- Families over an abstract type are declared in one line and checked per member at first use (§4.7).
- The facts mode protects compiled trait code from unrelated loads (facts §2.2) and promises nothing about the speed of code that is not fully typed (facts §13).

**What a "principled" trait is here:** it names what the generic code needs (operations with declared results), not what a type stores; a type joins it after the fact; several types that differ only in what the trait cannot see share compiled code.

## 1. The compile-cost map of the workload today

This section grounds the ranking (§9). It is read from the code; the times are for P1 to measure (§11).

### 1.1 NetworkDynamics: where the user's functions reach the types

- `VertexModel` and `EdgeModel` store the user's functions untyped: `f::Any`, `g::Any`, `obsf::Any` (`component_functions.jl:254`, `:258`, `:266`; `:309`, `:313`). The record itself is one concrete type.
- The `Network` constructor groups components by a hash of `(typeof(c), compf(c), compg(c), fftype(c), dim, outdim, pdim, extdim)` (`construction.jl:259`) and builds one `ComponentBatch` per group, whose type carries the function types and the dimensions: `ComponentBatch{T,F,G,FFT,DIM,PDIM,INDIMS,OUTDIMS,EXTDIM,IV}` (`network_structure.jl:181`; `VertexBatch`, `construction.jl:381`).
- The batches go into a tuple when there are at most 25 (`MAX_UNROLLED_BATCHES`, `construction.jl:5`), so that `unrolled_foreach` (`utils.jl:51`) runs each batch at a known type; beyond 25 a `Vector` and a dynamic call per batch.
- The tuple's type is a parameter of `Network{EX,G,NL,VTup,MM,CT,GBT,LM,EM}` (`network_structure.jl:88`), together with the graph type `G`, the mass matrix type `MM` and the aggregator (inside `NL`). The core loop is a method of that type: `(nw::Network{A,B,C,D,E})(du, u, p, t; …)` (`coreloop.jl:1`).
- So **a new component function, a new dimension or a new graph type is a new `Network` type**, and the core loop, `get_buffers`, the observed-function closures (`symbolicindexing_base.jl:593`) and the callback batches (`callbacks.jl:477`) are compiled again for it. The core loop never reads the graph; `G` is in the type only because `IndexManager{G}` stores it (`network_structure.jl:1`).
- The inner call is static today: `apply_compf(f::F, du, u, ins, p, t) where {F}` (`coreloop.jl:213`) and `apply_compg` by feed-forward kind (`:218`–`:233`). That is the part to keep.

### 1.2 SciML: what the problem's type carries

- `ODEProblem(nw, …)` builds `ODEFunction(nw)` (`post_utils.jl:83`). The `Network` declares `__has_sys` and answers `nw.sys === nw` (`network_structure.jl:336`–`:346`), so the function record stores the network as its `sys` (`scimlfunctions.jl:380`), a type parameter of `ODEFunction{…, SYS, …}` (`:539`–`:565`).
- `ODEProblem{uType,tType,iip,P,F,K,PT}` (`problems/ode_problems.jl:114`) carries the function's type `F` and the keywords' type `K`; the keywords include the callbacks (`post_utils.jl:83`).
- `promote_f` wraps an in-place right-hand side into a `FunctionWrappersWrapper` at the `(du, u, p, t)` signature and its dual variants under `AutoSpecialize` (`DiffEqBase/src/solve.jl:1011`, the wrap path `:1038`–`:1060`; for explicit algorithms only when `f.jac === nothing`, `:1201`). That makes the *call* independent of the function's type. It does not touch `sys`, so the record's type still varies with the network.
- `ODEIntegrator` has 26 type parameters, among them `F` (the function record) and `SolType` (`integrators/type.jl:155`); `__init` builds it with `FType = typeof(f)` (`OrdinaryDiffEqCore/src/solve.jl:837`). `solve!` (`:1062`), `loopfooter!`, `handle_callbacks!` (`integrator_utils.jl:1099`) and `savevalues!` are compiled per integrator type. The step itself is per cache type: `perform_step!(integrator, cache::Tsit5Cache, …)` (`tsit_perform_step.jl:204`) calls `f(k2, tmp, p, t + c1 * dt)` (`:214`).
- `ODESolution` carries the problem and the algorithm (`solutions/ode_solutions.jl:119`–`:145`), so `sol[VIndex(1, :x)]` and the SymbolicIndexingInterface getters (`state_indexing.jl:34`, `:63`) are compiled per solution type.
- Callbacks: a `DiscreteCallback{F1,…}` holds its functions as parameters (`SciMLBase/src/callbacks.jl:418`); `_despecialize_callbacks!` wraps them under `AutoSpecialize` only when the `CallbackSet` already holds vectors (`OrdinaryDiffEqCore/src/solve.jl:84`–`:94`).

**Consequence.** After the equations change, the whole chain from the core loop to the plotting getters is compiled again, although every function in it is reached through a type-erased wrapper or an `Any` field somewhere. SciML has built the `Dynamic{Callable}` idea by hand (`FunctionWrappersWrappers`, `Void`, `unwrapped_f`, `SciMLBase.jl:1778`–`:1781`); the leak is the `sys` field and the network's own type.

### 1.3 Makie, GraphMakie, Observables: already dynamic at the seams

- A plot is `Plot{PlotFunc, T}` with `T` the type of the *converted* arguments (`coretypes.jl:66`; `compute-plots.jl:801`–`:804`), not the user's. The user's value is converted once, in a compute-graph edge that calls `convert_arguments(P, args...)` (`compute-plots.jl:497`–`:535`, the edge at `:530`). So a new data type compiles its conversion and the first edge; the pipeline after it is per converted type.
- The compute graph keeps values untyped (`Computed.value::RefValue`, `ComputePipeline.jl:36`; arguments as `RefValue{Any}`, `compute-plots.jl:396`) and each edge's callback as `::Function` (`:86`), typed on first resolve (`:663`–`:680`). Each resolve is a dynamic call per edge.
- GraphMakie's `graph` is a recipe argument without conversion (`@recipe(GraphPlot, graph)`, `recipes.jl:152`); the recipe's edges call `layout(graph)`, `nv`, `edges` on it directly (`:221`–`:231`, `:313`–`:315`, `find_edge_paths`, `:599`). So a new graph type recompiles those edges.
- Observables: listeners are `Vector{Pair{Int, Any}}` (`Observables.jl:69`), `notify` calls each through `invokelatest` (`:203`–`:213`), the module is `@optlevel 0` (`:9`). It is a dynamic notification graph by design. A Makie input made from an `Observable` registers a listener that sets the compute-graph input (`ComputePipeline.jl:806`–`:816`).

**Consequence.** On the plotting side the user's new type costs its own conversion and little else. Traits buy a declared, checked entry and a forwarding form, not compile time. Facts mode changes nothing in what is dynamic here; whether its run-time sites are slower than plain Julia's heuristics is P3's measurement (facts §13).

## 2. Graphs and NetworkLayout

### 2.1 What the consumers need

- NetworkDynamics reads `nv`, `ne`, `vertices`, `edges` (collected into `Vector{SimpleEdge{Int64}}`, `network_structure.jl:3`, `:37`), `has_edge`, `degree`, `all_neighbors`, `outneighbors`, and tests `g isa SimpleDiGraph` once (`construction.jl:319`). All at construction.
- GraphMakie reads `nv`, `ne`, `edges` with `src`/`dst`, `is_directed`, `has_edge`, `all_neighbors`, `vertices` (counted over `GraphMakie.jl/src/*.jl`). All in compute-graph edges.
- NetworkLayout reads only `adjacency_matrix(g)`, through its extension (`ext/NetworkLayoutGraphsExt.jl`).

### 2.2 `AbstractGraph` is a trait; `SimpleGraph` is a type

Graphs' interface is an informal method set with throwing fallbacks: `nv(g::AbstractGraph) = _NI("nv")` (`interface.jl:140`), `edges(g) = _NI("edges")` (`:206`), `is_directed(::Type{T}) = _NI(…)` (`:229`), and so on (`:18` for `_NI`). It is joined after the fact by graph types in other packages. That is a trait by the glossary's definition, and the throwing fallbacks are exactly why an implementation is declared, never inferred (glossary, "Implementation"). The abstract type stays, as the reference says abstract types do (§14); the trait is declared beside it.

```julia
# in Graphs (the owner of the functions and of SimpleGraph)
@trait Graph{V <: Integer} begin
    @default_with_dynamic_self                 # a graph from outside enters Dynamic: layout and index building are not hot
    V = eltype(Self)                           # Graphs.eltype(::Type{<:AbstractGraph{T}}) = T, interface.jl:125
    Graphs.nv(g::Graph{V})::V                  # nv(::AbstractSimpleGraph{T}) returns T, SimpleGraphs.jl:125
    Graphs.ne(g::Graph)::Int
    Graphs.is_directed(g::Graph)::Bool
    Graphs.has_edge(g::Graph{V}, s::V, d::V)::Bool
    Graphs.outneighbors(g::Graph{V}, v::V)::AbstractVector{V}
    Graphs.inneighbors(g::Graph{V}, v::V)::AbstractVector{V}
    edgelist(g::Graph{V})::Vector{SimpleEdge{V}}          # new name: edges(g) returns an iterator of an open type
end
edgelist(g::AbstractGraph) = collect(edges(g))            # Graphs' own method for its own abstract type
@implement Graph G where {G <: AbstractGraph}             # every subtype, by its existing methods, checked at first use
```

- **Why `edgelist`.** `edges(g)` returns `SimpleEdgeIter{G}` or whatever the graph type returns; an operation must declare its result (§3.1). The index manager and GraphMakie both want the list. A foreign graph whose edges are not `SimpleEdge`s (a weighted graph's `SimpleWeightedEdge`) is refused at first use with an `ImplementError` naming `edgelist` and both types, where today it fails inside `IndexManager`'s field conversion.
- **Why `nv` returns `V`.** `nv` returns the vertex type, not `Int` (`SimpleGraphs.jl:125`); a declared `Int` would refuse `SimpleGraph{Int32}` at its first use. This is the kind of thing the result check catches at the declaration.
- **Adjacency** stays a plain function of Graphs (`linalg/spectral.jl:16`), since NetworkLayout takes a matrix and never a graph.
- **Membership.** `IsDirected` (`interface.jl:41`, a SimpleTraits trait) is a property, not a trait of its own here; `is_directed` is an operation. Directed and undirected graphs are one trait: the consumers branch on the answer.
- **What it buys.** A checked contract for every graph type; NetworkDynamics' index manager and GraphMakie's edge helpers compiled once per key, `Dynamic` for a graph type from outside; a readable refusal for a graph type that does not fit.
- **What it does not buy.** Time in this workload: one `SimpleGraph{Int64}`.

### 2.3 NetworkLayout: `AbstractLayout` is a trait of one operation

`AbstractLayout{Dim, Ptype}` requires `layout(::Layout, adj_matrix)::Vector{Point{Dim, Ptype}}` (`NetworkLayout.jl:34`, the docstring; the call form `:39`). `IterativeLayout` adds the iterator interface (`:60`, `:75`–`:87`). That is a trait with one operation and two associated types.

```julia
@trait Layout{Dim, Ptype} begin
    Dim = dim(Self); Ptype = ptype(Self)       # needs dim/ptype on the type; today they are on instances (NetworkLayout.jl:36–37)
    layout(l::Layout{Dim, Ptype}, adj::AbstractMatrix)::Vector{Point{Dim, Ptype}}
end
@implement Layout L where {L <: AbstractLayout}
```

- `Spring`'s result type infers to `Vector{Point{Dim, Ptype}}` from its iterator (`spring.jl:65`–`:81`), but through a comprehension's element type, one of the values decided by inference (facts §2.1, the exception). The member check accepts it; the port should test it.
- GraphMakie's `layout` attribute is a layout, a function or a vector (`recipes.jl:158`, `:222`–`:230`). The recipe keeps it as a `Kept{Layout}` and otherwise calls it as plain code. A `Callable` bound for "a function of the graph" cannot be written, since the graph's type is not constant (§5.8); a `Callable{Tuple{Dynamic{Graph}}, …}` would work once `Graph` exists.
- Benefit: small; cost: small. It belongs with `Graph`.

## 3. NetworkDynamics

### 3.1 What is a trait, what is a type

| Piece | Today | Principled form | Why |
|---|---|---|---|
| `VertexModel`, `EdgeModel` (`component_functions.jl:251`, `:306`) | concrete records: symbols, metadata dicts, `f::Any`, `g::Any` | **types** (records). The *dynamics* they carry conform to `VertexDynamics`/`EdgeDynamics` through a small typed object built at `Network` construction (§3.2) | the record is data; the behaviour is in `f` and `g` |
| the component functions `f`, `g` | plain functions, arity checked by `hasmethod` (`:569`–`:570`) | the operations of `VertexDynamics`/`EdgeDynamics`; a user's own type may implement them directly | what the core loop needs is "evaluate f and g at this signature", nothing else |
| `FeedForwardType` and its four singletons (`:6`–`:49`) | a field `ff::FeedForwardType`, a type parameter of the batch | a **value** returned by an operation `fftype(m)`; it orders the core loop (`coreloop.jl:39`–`:97`) and selects `g`'s argument list | it is a property of a function, not a kind of value |
| `StateMask`, `AntiSymmetric`, `Symmetric`, `Directed`, `Fiducial` (`:81`–`:197`) | callable wrappers that *are* `g` | **types**, NetworkDynamics' own `g` implementations; they stay plain callables inside the implementation | closed, the library's own |
| `ExecutionStyle` (`executionstyles.jl:13`), `Aggregator` (`aggregators.jl:16`), `GBufProvider` (`gbufs.jl:1`) | abstract types with a closed set of library strategies | **types**: an abstract tree is right (§14, "Abstract types stay") | nobody outside joins them; dispatch on them is a switch |
| `Network` (`network_structure.jl:88`) | one struct, its type a product of everything inside | a **type** whose type no longer carries the models; it *conforms* to SciML's right-hand-side trait (§4.2) and to `IndexProvider` (§4.5) | the network is the seam to SciML |
| `VIndex`, `EIndex` (`symbolicindexing_base.jl:127`, `:175`), `NWState`, `NWParameter` (`symbolicindexing.jl:105`, `:27`) | records | **types**; `NWState` and `NWParameter` conform to `ValueProvider` (§4.5) | they are indices and views |
| `ComponentCondition`, `ComponentAffect` (`callbacks.jl:49`, `:98`) | records with a function and a `hasmethod` check at construction (`:54`, `:103`) | records whose function is kept at a declared signature: `f::Callable{Tuple{SymbolicView, SymbolicView, Float64}, Float64}` | the `hasmethod` check is a hand-made `Callable` check |
| initialization (`initialization.jl`), init formulas (RuntimeGeneratedFunctions), sparsity (`sparsity.jl:90` tracers), metadata, `show`, doctor | plain | **plain**, this round (§8) | construction-time, or outside the port's packages |

### 3.2 The traits

```julia
@trait_module module NDCore …                   # NetworkDynamics' core, a trait module inside the package

@trait ComponentDynamics begin
    @default_with_dynamic_self                  # a user's model enters Dynamic; the library's own too, since it holds the user's function
    NetworkDynamics.dim(m::ComponentDynamics)::Int
    NetworkDynamics.pdim(m::ComponentDynamics)::Int
    NetworkDynamics.fftype(m::ComponentDynamics)::FeedForwardType
    hasf(m::ComponentDynamics)::Bool            # false for a static vertex (compf(c) === nothing today)
end

@trait VertexDynamics <: ComponentDynamics begin
    @default_with_dynamic_self                  # declared on each trait: §6.3 does not say whether a subtrait inherits it
    NetworkDynamics.outdim(m::VertexDynamics)::Int
    vf!(m::VertexDynamics, du::AbstractVector, u::AbstractVector, ins::Tuple, p::AbstractVector, t)::Nothing
    vg!(m::VertexDynamics, out::AbstractVector, u::AbstractVector, ins::Tuple, p::AbstractVector, t)::Nothing
end

@trait EdgeDynamics <: ComponentDynamics begin
    @default_with_dynamic_self
    outdim_src(m::EdgeDynamics)::Int
    outdim_dst(m::EdgeDynamics)::Int
    ef!(m::EdgeDynamics, du::AbstractVector, u::AbstractVector, ins::Tuple, p::AbstractVector, t)::Nothing
    eg!(m::EdgeDynamics, osrc::AbstractVector, odst::AbstractVector, u::AbstractVector, ins::Tuple, p::AbstractVector, t)::Nothing
end
```

- **Abstract argument types on purpose.** The core loop runs at `Float64`, at ForwardDiff duals of several tags and chunk sizes (`ad_chunksize`, `network_structure.jl:85`; `cachetype`, `coreloop.jl:13`), at sparsity tracers (`sparsity.jl:90`–`:91`) and with `t === nothing` from symbolic indexing (`coreloop.jl:16`). An operation's arguments may be abstract; the call on a `Compiled` trait object is then a direct call at the concrete types the loop has, and on a `Dynamic` one a split or a table probe at the call's signature (facts §9). This is how the open set of element types is served without a `Callable` per signature. See the pushback in §10.1.
- **One `g` operation per kind,** with `ins` and `u` always passed. The feed-forward kind decides which of them the function reads; the implementation drops the unused ones, as `_gargs` does today (`component_functions.jl:1167`–`:1170`). The core loop keeps its ordering by `fftype`.
- **`Self`'s key.** Operations only, no declared fields: the key is the receiver type. Two models of one type with different captured values share code.

**The library's own implementation**, built from a record at `Network` construction, as `ComponentBatch` is built today (`construction.jl:381`–`:396`):

```julia
struct FunctionDynamics{F, G, FF <: FeedForwardType}     # NetworkDynamics' type: a record's f, g and ff, typed
    f::F; g::G; ff::FF; dim::Int; pdim::Int; outdim::Int
end
vf!(d::FunctionDynamics, du, u, ins, p, t) = (d.f(du, u, ins..., p, t); nothing)
vg!(d::FunctionDynamics{F, G, PureStateMap}, out, u, ins, p, t) where {F, G} = (d.g(out, u); nothing)
… one method per feed-forward kind, as apply_compg today …
@implement VertexDynamics D where {D <: FunctionDynamics}   # one line, own methods; the bare-variable family form (T-5)
```

- `FunctionDynamics{typeof(user_f), …}` holds a type from outside the trait world, so the trait's `Dynamic` default applies (§6.3): it enters `Dynamic` wherever a plain value enters. The `VertexModel` record keeps `f::Any` as today, for metadata, printing and the callers that need the raw function (sparsity, initialization). Nothing in the record changes.
- **A user's own type** (`struct Kuramoto; ω::Float64; end` with `vf!(k::Kuramoto, …)`) conforms by `@implement VertexDynamics Kuramoto` and needs no `VertexModel`. That is the idiomatic form; it is a later step, not the port's first.
- The splat `d.f(du, u, ins..., p, t)` is over a tuple of known length, so inference sees an ordinary call at concrete types, a dispatch tuple (facts §3), not the widened vararg the porting guideline warns about (B4).

### 3.3 The batch barrier: where `compiled_for` goes

```julia
struct VertexBatch                                # one concrete type for every batch
    model::VertexDynamics                         # Kept{VertexDynamics}: the model with its attribute
    indices::Vector{Int}
    statestride::BatchStride; pstride::BatchStride; inbufstride::BatchStride; outbufstride::BatchStride; extbufstride::BatchStride   # plain Ints inside
end

function run_vertex_batch!(m::VertexDynamics, b::VertexBatch, fg, du, u, o, inbufs, p, t)   # bounded: compiled per key of m
    for i in 1:length(b.indices)
        … views as apply_comp! builds them today (coreloop.jl:176–192) …
        evalf(fg, b) && vf!(m, _du, _u, _ins, _p, t)
        evalg(fg, b) && vg!(m, _o, _u, _ins, _p, t)
    end
    nothing
end

# in the core loop, for each batch:
run_vertex_batch!(compiled_for(b.model), b, fg, du, u, o, inbufs, p, t)
```

- **The barrier is the library's choice**, so a caller's attribute does not matter here: a library's cast wins (§6.4). The model is kept `Dynamic` in the batch so that the `Network`'s type is one type; it is opened once per batch per right-hand-side evaluation, and the loop over the batch's components runs compiled for the model's key, with direct calls to `vf!` and `vg!` at the buffers' concrete element types. That is today's inner loop (`apply_compf`, `coreloop.jl:213`) under a barrier.
- **What the barrier costs:** one selection of the worker by the model's type per batch per call, the untyped-caller path (lowering §9.3; about 30 ns in evidence §2, "an untyped trait call"). A network's right-hand side is microseconds and up.
- **What it removes:** the batch tuple, `unrolled_foreach` and the 25-batch cliff (`construction.jl:1`–`:5`): batches are a `Vector{VertexBatch}` of one concrete type, and the loop over them is typed.
- **Dimensions as values.** `BatchStride{DIM}` makes the dimension a type parameter (`utils.jl:1`); a 2-state and a 3-state model then give different batch and `Network` types. Plain `Int`s inside the batch make the `Network` type independent of the dimensions too. Whether the static dimension buys anything in the sequential loop is for P1 to measure; the KernelAbstractions path may need it (§10.7).
- **After this,** `Network{EX, G, MM, …}` varies with the execution style, the graph type and the mass matrix type only. For the workload that is one type across equation changes, and §1.2's chain above it is compiled once.

### 3.4 Where values enter, and with which attribute

| Value | Enters where | Attribute | Effect |
|---|---|---|---|
| the component functions | `FunctionDynamics` built at `Network(…)`; stored as `Kept{VertexDynamics}` in the batch | `Dynamic` (the trait's default; a user's `compiled_for(vm)` changes the kept attribute, not the barrier) | the `Network` type carries no function type |
| the model at the batch barrier | `compiled_for(b.model)` | `Compiled` for the loop | the loop compiled per model type, as today |
| the graph | `IndexManager(g::Graph, …)` at construction | `Dynamic` (the trait's default) | index building compiled once; see §10.3 for `get_graph` |
| the `Network` into SciML | `ODEProblem(nw, …)`, the right-hand side bound (§4.2) | `Dynamic` by `ODERHS`'s default | the solver compiled once per `(U, P, T)` |
| callback functions | `ComponentCondition(f, …)`: `f::Callable{…}` kept with its attribute | `Dynamic` (`Callable`'s default) | the batched condition closures (`callbacks.jl:477`) are one type |

### 3.5 Symbolic indexing, callbacks, initialization

- **`Network` implements SymbolicIndexingInterface's index-provider interface** (`symbolicindexing_base.jl:369`–`:374`, `:396`, `:593`). That interface is a trait (§4.5); `Network` conforms by its existing methods in one line. `SII.observed(nw, syms)` returns closures over the network (`:677`–`:735`); their type is stable once the `Network`'s is. No change inside them for this round.
- **`NWState`, `NWParameter`** conform to `ValueProvider` by their existing methods (`symbolicindexing.jl:334`–`:341`). Both define `getproperty` (`:712`), so they may conform by operations, never by declared fields (§3.3, the `getproperty` rule).
- **Component callbacks.** `ComponentCondition{C, DIM, PDIM}` stores the user's function as a type parameter and checks its arity with `hasmethod` (`callbacks.jl:49`–`:59`). Keeping it as `f::Callable{Tuple{SymbolicView, SymbolicView, Float64}, Float64}` gives one record type, the arity check at the declaration and the result check at every call. The wrapper types (`ContinuousCallbackWrapper{T, C, ST}`, `:414`) and the batched closures then have one type per network, and so does the `CallbackSet` that `ODEProblem(nw, …)` puts into the problem's keywords. A condition is called at duals too, through SII's observed function (`:482`, `:493`); that signature is a second member of the tuple (W-29) or stays on the plain path (§10.1).
- **Initialization** (`find_fixpoint`, `initialize_componentwise`, `initialization_problem`, `initialization.jl:52`, `:172`, `:1206`) builds NonlinearSolve problems from closures over the component functions and init formulas generated at run time (`init_formulas.jl`, RuntimeGeneratedFunctions). NonlinearSolve is outside the port's packages and differentiates with its own dual tags. Plain code this round; the workload's simplest version gives initial values directly.

## 4. SciML

### 4.1 What is a trait, what is a type

| Piece | Principled form | Note |
|---|---|---|
| `AbstractODEFunction` and `ODEFunction{iip, specialize, F, TMM, …, SYS, ID, NLP}` (`scimlfunctions.jl:539`) | the record **conforms** to `ODERHS`; optional capabilities (`jac`, `tgrad`, mass matrix, sparsity) are **refinements** served by the record's own methods with a run-time branch on the field | membership per value, see §10.5 |
| `AbstractODEProblem`, `ODEProblem` (`ode_problems.jl:114`) | a **type** (a record of `f`, `u0`, `tspan`, `p`, keywords) | TDE's `ODEProblemTrait` folds the record and the function into one trait; SciML keeps them apart, and the port follows SciML |
| `AbstractODEAlgorithm`, `Tsit5`, the caches (`basic_caches.jl`, `tsit_caches.jl:1`) | **types**: a closed library family, selected by dispatch | an abstract tree is right |
| `DEIntegrator{Alg, IIP, U, T}` and its interface (`integrator_interface.jl`: `u_modified!` `:341`, `add_tstop!` `:366`, `terminate!` `:202`, `set_proposed_dt!` `:288`, `get_du` `:222`, `savevalues!` `:312`, …) | **`IntegratorView{U, T, P}`**: the interface is an informal method set with throwing fallbacks, joined by every integrator type | the trait callbacks see, as in TDE (`ODECore.jl:57`) |
| `DECallback`, `DiscreteCallback{F1,…}`, `ContinuousCallback{…}`, `VectorContinuousCallback`, `CallbackSet` (`callbacks.jl:418`, `:156`, `:290`, `:488`) | **`Callback`** with `condition` and `affect!`; the records keep their functions as `Kept{Callable{…}}` | TDE's `FunctionCallback` (`ODECore.jl:141`–`:147`) |
| `AbstractODESolution`, `ODESolution` (`ode_solutions.jl:119`) | a **type** that conforms to `Trajectory{U, T}` and to `ValueProvider` | the seam to plotting |
| SymbolicIndexingInterface: `symbolic_container`, `is_variable`, `variable_index`, `parameter_index`, `observed`, … (`index_provider_interface.jl:14`–`:296`); `state_values`, `parameter_values`, `current_time` (`value_provider_interface.jl:17`, `:102`, `:140`) | **`IndexProvider`** and **`ValueProvider`** | informal method sets joined after the fact by many types |
| `symbolic_type`, `is_timeseries` (`trait.jl`) | **values** (Holy-style switches) | they stay as they are |
| `DEOptions` (`type.jl`, 23 parameters), `promote_f`, `get_concrete_problem`, the `solve` front end (`DiffEqBase/src/solve.jl:681`, `:746`, `:1320`) | **plain** | type-level plumbing and keywords |
| `RecursiveArrayTools.DiffEqArray` (`vector_of_array.jl:93`) | a **type**; conforms to `Trajectory` if plotting goes through it | not on the workload's path |
| DiffEqCallbacks' `SavingCallback` (`saving.jl:59`, `:70`) | a `Callback` implementation whose `save_func` is a kept `Callable` | useful for the plot-while-simulating step |

### 4.2 `ODERHS`: the right-hand side, the seam from NetworkDynamics

```julia
@trait ODERHS{T, P} begin
    @default_with_dynamic_self                  # a user's model, a Network: Dynamic; the solver compiled once per (U, P, T)
    rhs!(f::ODERHS{T, P}, du::Vector{T}, u::Vector{T}, p::P, t::Float64)::Nothing
end
@trait ODEJacobian{T, P} <: ODERHS{T, P} begin
    jac!(f::ODEJacobian{T, P}, J::AbstractMatrix{T}, u::Vector{T}, p::P, t::Float64)::Nothing
end
@trait ODEMassMatrix <: ODERHS begin
    mass_matrix(f::ODEMassMatrix)::Union{UniformScaling{Bool}, Diagonal{Float64, Vector{Float64}}, Matrix{Float64}}
    jac_prototype(f::ODEMassMatrix)::Union{Nothing, SparseMatrixCSC{Bool, Int}}
end
```

- **Parameters.** `T` and `P` are stated by the implementation or tied to the conforming type's parameters: `@implement ODERHS{Float64, Vector{Float64}} Network` for the workload; a joint family for `ODEFunction` is not written out (§10.4).
- **`Network` conforms** with `rhs!(nw, du, u, p, t) = (nw(du, u, p, t); nothing)`, `mass_matrix(nw) = nw.mass_matrix`, `jac_prototype(nw) = nw.jac_prototype`. The `Network` is also the index provider: `ODEFunction`'s `sys` stays the network object, typed, now with a stable type.
- **In the integrator**, `f` becomes a field of a kept form, one type per signature. `perform_step!` calls it as before (`f(k2, tmp, p, t + c1 * dt)`, `tsit_perform_step.jl:214`): a kept function is callable, so the step code does not change. This replaces `promote_f`'s wrapping (`DiffEqBase/src/solve.jl:1011`) for the in-place path, with the signature checked and the result asserted `Nothing`, and the call made in the caller's world (compiler §3).
- **The dual signatures** that `promote_f` installs for implicit algorithms (`:1049`–`:1052`, `hasdualpromote`) are a tuple of `Callable`s at the chunk size the algorithm picks: Planned (W-29; open issue 10). Until then the port covers Tsit5, which needs the plain signature only; Rodas waits.
- **The element type `T` is fixed per implementation.** A dual state (sensitivities through `solve`) is another member of a family, as in TDE (porting guideline B2, "The state's element type is the problem's"). `promote_u0`/`promote_tspan` stay plain.
- **What it buys after §3:** little compile time (the chain is already stable once the `Network`'s type is), but the checked contract (`du .= …` returning `du` is refused where `rhs!` is declared `::Nothing`, B2), the removal of the hand-made wrappers, and the cases `AutoSpecialize` cannot wrap (`u0` a `SubArray`, `eltype(u0) === Any`, `jac` given for an explicit algorithm, `:1038`–`:1060`, `:1201`).

### 4.3 `IntegratorView` and `Callback`

```julia
@trait IntegratorView{U, T, P} begin          # fields only: no receiver type, the key is (U, T, P)
    @const u::U
    @const uprev::U
    t::T
    dt::T
    p::P
    u_modified::Bool
    …
    SciMLBase.add_tstop!(i::IntegratorView{U, T}, t::T)::Nothing
    SciMLBase.terminate!(i::IntegratorView)::Nothing
    SciMLBase.set_proposed_dt!(i::IntegratorView{U, T}, dt::T)::Nothing
    index_provider(i::IntegratorView)::Dynamic{IndexProvider}     # for extract_nw(integrator) (symbolicindexing.jl:1034)
end
@trait Callback begin
    condition(cb::Callback, u::Vector{Float64}, t::Float64, i::Dynamic{IntegratorView})::Bool
    affect!(cb::Callback, i::Dynamic{IntegratorView})::Nothing
end
```

- `ODEIntegrator` conforms as a family over its 26 parameters by the bare-variable form, `@implement IntegratorView I where {I <: ODEIntegrator}`, with field mappings where names differ. `ODEIntegrator`'s fields `u`, `uprev` are `const` in TDE's trait and writable here (`set_u!`); which it is must be decided per field.
- `DiscreteCallback` conforms with `condition`/`affect!` as kept `Callable`s at `CondSig`/`AffectSig` (TDE's spelling, `ODECore.jl:74`–`:76`); the record's type is then one type for every pair of plain functions, and `_despecialize_callbacks!` (`OrdinaryDiffEqCore/src/solve.jl:84`) has nothing left to do.
- `handle_callbacks!` (`integrator_utils.jl:1099`) and `apply_discrete_callback!` (`DiffEqBase/src/callbacks.jl:759`–`:773`) become bounded over `Vector{Callback}` items: compiled once, a split per callback per step.
- Benefit for the workload: none unless callbacks are used; principled, and it removes a whole axis of the integrator's type.

### 4.4 `Trajectory`: a solution as plotting sees it

```julia
@trait Trajectory{U, T} begin
    times(s::Trajectory{U, T})::Vector{T}
    state(s::Trajectory{U, T}, i::Int)::U
    at(s::Trajectory{U, T}, t::T)::U            # interpolation, sol(t)
end
```

- `ODESolution` conforms by `sol.t`, `sol.u[i]`, `sol(t)` (`ode_solutions.jl:240`–`:340`). `DiffEqArray` too.
- Plotting helpers in the workload (`trajectory_points(s::Trajectory, i::Int)::Vector{Point2f}`) are compiled once per key; a solution from the prompt is `Dynamic`.
- Symbolic indexing of a solution (`sol[VIndex(1, :x)]`) goes through `ValueProvider` + `IndexProvider` (§4.5), not through this trait.

### 4.5 `IndexProvider` and `ValueProvider`

```julia
@trait IndexProvider begin
    @default_with_dynamic_self
    SII.is_variable(ip::IndexProvider, sym)::Bool
    SII.variable_index(ip::IndexProvider, sym)::Union{Nothing, Int}
    SII.is_parameter(ip::IndexProvider, sym)::Bool
    SII.parameter_index(ip::IndexProvider, sym)::Union{Nothing, Int}
    SII.is_observed(ip::IndexProvider, sym)::Bool
    SII.observed(ip::IndexProvider, syms)::Function          # a closure; its signature is open (§10.1)
    SII.is_time_dependent(ip::IndexProvider)::Bool
    SII.variable_symbols(ip::IndexProvider)::Vector
    SII.parameter_symbols(ip::IndexProvider)::Vector
end
@trait ValueProvider{U, P} begin
    SII.state_values(v::ValueProvider{U})::U
    SII.parameter_values(v::ValueProvider{U, P})::P
    SII.current_time(v::ValueProvider)::Any
end
```

- `Network` conforms to `IndexProvider` by its methods (`symbolicindexing_base.jl:369`–`:374`, `:396`, `:593`); `NWState`, `ODESolution`, `ODEIntegrator`, `ODEProblem` to `ValueProvider`.
- `sym` is untyped on purpose: SII's indices are `VIndex{C, S}` with many parameter shapes; `symbolic_type(sym)` (a value) decides. The result types are the honest ones: `Union{Nothing, Int}` is a small union, which counts as concrete (§11).
- The getter closures (`getsym`, `state_indexing.jl:330`–`:400`) are compiled per index shape and per provider type. With `Dynamic{IndexProvider}` they are compiled per index shape only. Benefit: moderate once several providers are in a session; for the workload, after §3, the provider's type is stable anyway.
- Owner: SymbolicIndexingInterface owns the trait and declares the families for its own types; NetworkDynamics and SciMLBase declare their types' implementations.

## 5. Makie and GraphMakie

### 5.1 What is a trait, what is a type

| Piece | Principled form | Note |
|---|---|---|
| `conversion_trait` and `convert_arguments` (`conversion.jl:21`–`:101`: `PointBased`, `VertexGrid`, `CellGrid`, `ImageLike`, `VolumeLike`; `conversions.jl:14`) | the **data traits**: `Positions{N, T}` (PointBased), `GridData{T}`, `ImageData`, `VolumeData`, one per conversion trait; `convert_arguments(::PointBased, x::MyType)` is the implementation of `Positions` for `MyType` | TraitMakie's `Positions` (`PlotCore.jl:27`); the multi-argument conversions are open issue 12 |
| `Plot{Func, T}` and `@recipe` (`coretypes.jl:66`; `recipes.jl:180`) | **types**, plain this round. A `Plot` trait (TraitMakie `PlotCore.jl:177`) is the principled form, but Makie's recipe is "register edges and children in a compute graph", which is the makie-rewrite's architecture, not a port | §1.3 |
| attributes (`Dict{Symbol, Any}`, `AttributeConvert{key, plot}`, `compute-plots.jl:604`) | **`ColorSpec`, `MarkerShape`, …** as in TraitMakie, later | not on the workload's path |
| `ComputeGraph`, `Computed`, `ComputeEdge` (`ComputePipeline.jl:218`, `:36`, `:84`) | **plain**: it is a dynamic graph by construction | the typed graph of makie-rewrite §3 is a rewrite |
| `GraphPlot`'s `graph` argument (`recipes.jl:152`) and the helpers `find_edge_paths` (`:599`), `find_start_end_shift` (`:887`, `:910`), `elabels_distance_offset` (`:566`) | bounded by **`Graph`** (§2.2) | the real "new data type" seam on the plotting side |
| `layout` (`:158`, `:221`–`:231`) | a `Kept{Layout}` or a plain callable (§2.3) | |

### 5.2 `Positions` and the conversion seam

```julia
@trait Positions{N, T} begin
    @default_with_dynamic_self
    points(x::Positions{N, T})::Vector{Point{N, T}}
end
@implement Positions{2, Float32} Vector{Point2f} begin points(x) = x end      # Makie's own
@implement Positions{N, T} V where {V <: AbstractVector{<:Point{N, T}}} …   # the family, stated per (N, T) today (T-38)
```

- Makie's `convert_arguments(::PointBased, …)` methods become the implementations for Base's types, declared by Makie (the trait's owner, §10.1). A user's type conforms by `points`, or **by forwarding** (`@implement Positions{2, Float32} Trajectory by pts`), which `convert_arguments` cannot express: it must return Makie's vector, a copy.
- The seam in the compute graph is the edge that calls `convert_arguments` (`compute-plots.jl:530`). In the trait form that edge calls a bounded `to_points(x::Positions)` and the user's value enters there, `Dynamic` by the default: the edge is compiled once.
- What it buys for the workload: a checked entry and no copy for a forwarding type; no measurable time. What it costs: one trait, Makie's `PointBased` conversions re-declared as implementations (many methods, `conversions.jl:68`–`:322`). Rank low; do `Vector{Point2f}` and the workload's own type only.

### 5.3 GraphMakie

- With `Graph` from §2.2, the recipe's helpers take `g::Graph` and the compute-graph closures call them: `map!(gp.attributes, [...], :edge_paths) do pos, …, g; find_edge_paths(g, gp.attributes, pos) end` (`recipes.jl:313`). The closure is plain Makie code; `find_edge_paths` is the entry; `g` enters `Dynamic` by the trait's default, so the helper is compiled once, whatever the graph type.
- A bounded closure (`(g::Graph) -> …`) is Planned (§5.8); the named-function form above avoids it.
- `nv(graph)` inside the closures (`:223`) is a call on the plain graph, compiled per graph type as today, unless the closure is given a kept value. Minor.

## 6. Observables

- `Observable{T}` (`Observables.jl:68`) is a **type**. The behaviour Makie needs from it, "the value now, and call me when it changes", is a trait with two operations:

```julia
@trait Source{T} begin
    T = eltype(Self)                                  # needs Base.eltype on the type; today it is on instances (Observables.jl:102)
    value(s::Source{T})::T
    subscribe!(s::Source{T}, f::Callable{Tuple{T}, Nothing})::Nothing
end
@implement Source O where {O <: AbstractObservable}
```

- `ObserverFunction` (`:42`), `on` (`:361`), `notify` (`:203`), `map`/`map!` (`:518`, `:568`) stay plain. `notify`'s `invokelatest` makes every listener a call dispatched at run time, so a bounded listener receives `Dynamic` values (§6.2), which is consistent.
- `Observable{Any}` is Makie's usual form for attributes (`interfaces.jl:227`), and `Source{Any}` gives `value(s)::Any`: nothing is gained there, and nothing is lost.
- Benefit: the "live bound" of open issue 13 becomes expressible as `x::(Positions, Source{…})` once tuples of traits reach bounds with item parameters (W-29). For the workload, the `Observable` holds a `Vector{Point2f}` that plain code updates; no trait is needed. Rank last.

## 7. The seams

1. **Graphs → NetworkDynamics.** `Network(g, …)` reads the graph once through `Graph`'s operations into `IndexManager` (`network_structure.jl:32`–`:55`). The stored graph keeps its type `G` in `IndexManager{G}` and in the `Network` for this round: erasing it would hide the user's graph from `get_graph(nw)` (§10.3). The cost is one `Network` type per graph type, which is one in the workload.
2. **NetworkDynamics → SciML.** `ODEProblem(nw, u0, tspan, p)` (`post_utils.jl:45`–`:83`): the `Network` enters the solver as `Dynamic{ODERHS{Float64, Vector{Float64}}}` through `ODEFunction(nw)`. The solver's integrator and driver are compiled once per `(U, P, T)`; each `rhs!` is one split or table probe (seven per Tsit5 step), against a right-hand side of microseconds. The network stays the problem's index provider (`sys`), typed, with a stable type after §3.
3. **SciML → Observables → Makie.** The workload's own code: `on(sol_obs) do sol; pts[] = trajectory_points(sol, i); end` with `trajectory_points` bounded by `Trajectory` (§4.4), and `lines!(ax, pts)` with `pts::Observable{Vector{Point2f}}`, which Makie takes through `add_input!` (`ComputePipeline.jl:806`). No trait is needed in Makie for this; `Trajectory` is optional.
4. **GraphMakie → Graphs.** The recipe's edges call bounded helpers with the graph (§5.3). The layout is a kept `Layout` or a plain callable (§2.3).
5. **Callbacks → the integrator.** NetworkDynamics' batched condition and affect closures (`callbacks.jl:477`, `:518`) receive the integrator; through `IntegratorView` they read `u`, `p`, `t` and reach the network with `index_provider(i)` (§4.3), where today they read `integrator.f.sys` (`symbolicindexing.jl:1033`–`:1034`).

## 8. What stays plain code, and why that is fine

- **Closed library families:** `ExecutionStyle`, `Aggregator`, `GBufProvider`, the algorithms and caches, the controllers. Abstract types with a fixed method set are what the reference keeps as types (§14). Nobody outside joins them; the facts mode compiles their dispatch as facts at concrete signatures.
- **Construction-time and metadata code:** `VertexModel`'s metadata dicts, `show`, the doctor, `Network`'s checks, `get_concrete_problem`, `promote_f`'s type plumbing, the `solve` front end with its keywords, SII's symbol resolution. Run once per construction or per solve; their run-time sites cost microseconds. The porting guideline's rule for front ends applies (B2: `@nospecialize` and a function barrier behind it).
- **Code that is dynamic by design:** Observables, ComputePipeline, Makie's attribute handling. Traits add nothing to a graph of `Any`; the facts mode protects what is compiled and changes no result (facts §2.1).
- **Code outside the port's packages:** NonlinearSolve (initialization), SparseConnectivityTracer (sparsity), KernelAbstractions (GPU), RuntimeGeneratedFunctions. Reached by calls from trait code, as any Julia code is (§2, "A trait module may use and call any Julia code").
- **Why fine:** none of it is on a per-component or per-step path once the batch barrier (§3.3) and the right-hand-side seam (§4.2) exist. What the facts mode costs at the remaining run-time sites is P3's question, not a reason to port them.

## 9. The ranking

Benefit for the workload per unit of change. "Change" counts the files touched and whether a Planned part of the reference is needed.

| Rank | Trait(s) | Where | Change | Benefit for the workload | Needs |
|---|---|---|---|---|---|
| 1 | `ComponentDynamics`, `VertexDynamics`, `EdgeDynamics`; `FunctionDynamics`; the batch barrier | NetworkDynamics: `component_functions.jl`, `network_structure.jl` (`ComponentBatch`, `Network`'s parameters and inner constructor), `construction.jl` (batches), `coreloop.jl` (`process_batches!`, `apply_comp!`) | medium: four files, the batch and network types reshaped, the record untouched | the run after changing the equations compiles the new model's batch worker and nothing above it: no core loop, no `ODEFunction`/`ODEProblem`/`ODEIntegrator`/`ODESolution`, no SII getters; the 25-batch cliff is gone | nothing Planned. Inner constructors become outer ones (§7.4). The sequential, threaded and Polyester styles; KA stays plain (§10.7) |
| 2 | `Graph`, `Layout` | Graphs (`interface.jl`), NetworkLayout (`NetworkLayout.jl`); users: `IndexManager` (ND), GraphMakie's helpers | small: two traits, two family lines, bounds on about eight functions | a checked contract where today a `NotImplementedError` or a conversion error deep inside; GraphMakie and the index manager compiled once per graph type; the first use of families over an abstract type in the port | `dim`/`ptype`/`eltype` methods on types; the comprehension's element type in `Spring` to test |
| 3 | `ODERHS` (+ `ODEMassMatrix`), `Network` conforming; the integrator's `f` as a kept function | SciMLBase (`scimlfunctions.jl`), DiffEqBase (`promote_f`), OrdinaryDiffEqCore (`__init`, `ODEIntegrator.f`), NetworkDynamics (`post_utils.jl`) | medium: the function record's `f` path; `perform_step!` unchanged | after rank 1, mostly correctness: a checked `rhs!`, calls in the caller's world, the cases `AutoSpecialize` leaves unwrapped; the per-session first solve is not changed | Tsit5 only until W-29 (dual signatures as a tuple) |
| 4 | `IndexProvider`, `ValueProvider` | SymbolicIndexingInterface; NetworkDynamics, SciMLBase declare implementations | small to medium: two traits, one-line families | getters compiled per index shape, not per provider; a contract for the interface NetworkDynamics implements in 50 methods | `observed`'s open result (§10.1) |
| 5 | `Trajectory` | SciMLBase, RecursiveArrayTools; the workload's plotting helper | small | the plotting helper compiled once; the Observables seam typed | — |
| 6 | `IntegratorView`, `Callback` | OrdinaryDiffEqCore, DiffEqBase (`callbacks.jl`), SciMLBase, NetworkDynamics (`callbacks.jl`) | medium | only with callbacks in the workload; removes the callback axis of the integrator's type | field mappings; which fields are writable |
| 7 | `Positions` | Makie (`conversions.jl`), GraphMakie | medium (many conversion methods) | a forwarding form for user data; no time | open issue 12 for multi-argument conversions |
| 8 | `Source` | Observables, Makie | small | expressiveness only (open issue 13) | W-29 for `(Positions, Source{…})` bounds |

**The first three to introduce:** rank 1, then rank 2 (cheap, and it exercises families over an abstract type with real consumers), then rank 3. Revisit the ranking after P1's baseline numbers (§11).

## 10. Pushback

Each entry: the code, what the idiomatic form would be, the reference section it meets, whether it blocks. None asks for a design change; three ask for Planned parts or deviations to be done first.

### 10.1 Open element types against `Callable`'s constant signature

- **The code.** Component functions run at `Float64`, at `ForwardDiff.Dual` of the ODE solver's tag and chunk (`ad_chunksize`, `network_structure.jl:85`), at NonlinearSolve's duals (initialization), at sparsity tracers (`sparsity.jl:90`–`:91`), and with `t === nothing` (`coreloop.jl:16`). SII's `observed` closures are called at the same set (`callbacks.jl:482`). SciML's `promote_f` hard-codes a list of dual signatures per algorithm (`DiffEqBase/src/solve.jl:1038`–`:1060`).
- **The idiomatic form** would keep the function at an open family of signatures, `Callable{Tuple{Vector{T}, …}, Nothing} where T`.
- **The reference:** `Callable`'s argument types are a constant (§5.8); a function kept at several signatures is a tuple (§7.5, Planned, W-29); a signature chosen by the callee is open issue 10; AD tags as part of a key is open issue 9.
- **Within the design:** put the operations on the model trait with abstract argument types (§3.2), so the call dispatches on the model and the element types are the call's; keep the raw function beside it for callers outside the trait world. For the solver's own dual signatures, a tuple of two `Callable`s (W-29). **Blocks:** nothing for Tsit5; Rodas until W-29. To record in the log.

### 10.2 The six-argument limit of a `Dynamic` function (T-51)

- **The code.** Edge output functions with feed-forward take seven arguments, `g(osrc, odst, u, insrc, indst, p, t)` (`apply_compg(::FeedForward, …)`, `coreloop.jl:222`), eight with an external input (`:203`–`:206`).
- **The reference:** a `Callable` takes any number of arguments; the implementation stops at six (T-51).
- **Within the design:** the model trait (§3.2) sidesteps it, since a `Dynamic` trait object's operation is a split, not a pointer call. A `Kept{Callable}` for edge functions would hit it. **Blocks:** the `Callable` spelling for edge functions, until T-51 is fixed in TraitWorld.

### 10.3 Kept values hide the user's object

- **The code.** `get_graph(nw)` returns the stored graph (`network_structure.jl:148`); `extract_nw(int.f)` reads `f.sys` (`symbolicindexing.jl:1033`–`:1034`); callbacks open `integrator.p` at the user's type (porting guideline B2); `unwrapped_f` recovers the raw function from SciML's wrappers (`SciMLBase.jl:1778`).
- **The reference:** a kept value holds the user's object and offers the trait's operations and fields (§7.1); opening it at its concrete type is Open (open issue 16).
- **Within the design:** keep the object typed where plain code reads it back and its type does not vary (the graph in `IndexManager{G}`), or keep the raw object beside the kept one (the record's `f::Any` beside `FunctionDynamics`). **Blocks:** nothing; it decides what is erased (§3.3, §7.1).

### 10.4 Heavy type parameters

- **The code.** `ODEFunction` (21 parameters, `scimlfunctions.jl:539`), `ODEIntegrator` (26, `type.jl:155`), `ODESolution` (18), `DEOptions` (23), `Network` (9), `ComponentBatch` (10).
- **The reference:** a joint family names every variable of the trait's parameters in the type (§4.7); a family with a block whose target is a parametric expression is not lowered (T-5).
- **Within the design:** conform by the bare-variable form, `@implement X I where {I <: ODEIntegrator}`, by the type's own methods, and state the trait's parameters where they are not read from fields. Never spell the parameter list. **Blocks:** nothing.

### 10.5 Membership decided per value

- **The code.** `has_jac(f) = __has_jac(f) && f.jac !== nothing` (`scimlfunctions.jl:5770`); a static vertex has no `f`, and the core loop tests `!isnothing(compf(batch))` (`coreloop.jl:243`); `obsf::Any` may be `nothing`; `_despecialize_callbacks!` branches on the callback's hooks (`OrdinaryDiffEqCore/src/solve.jl:97`–`:107`).
- **The idiomatic form** would make `ODEJacobian <: ODERHS` decide by dispatch ("a subtrait beats its supertrait", §5.5).
- **The reference:** membership is per type (§14).
- **Within the design:** a run-time branch on the field inside the implementation's method, as today, or distinct record types (`ODEFunction` with `TJ <: Function` as a second family, which runs into T-5 and the overlap rules T-9). The `hasf` operation in §3.2 is such a branch. **Blocks:** nothing; it limits what refinement traits can express for records.

### 10.6 Cross-package methods on SciMLBase's abstract types are pirates by the letter

- **The code.** DiffEqBase defines `__solve` and `__init` for `AbstractDEProblem` (`DiffEqBase/src/solve.jl:1320`, `:1336`) and `solve` for `AbstractNoiseProblem` and `AbstractJumpProblem` (`:716`, `:720`); the functions are CommonSolve's and SciMLBase's (`SciMLBase.jl:49`–`:50`, `:105`, `:127`), the types SciMLBase's. OrdinaryDiffEqCore's `__init` names its own algorithm type and is a stakeholder.
- **The reference:** a trait module may not define a pirate (§10.2, `OwnershipError`); strict mode refuses a pirate that wins at a fact of trait code (§10.3); `delegate!(Core => Impl)` lets an implementation package count as the owner of the core package (§10.3). Whether the refusal in trait modules stays is open issue §1.20.
- **Within the design:** `TraitWorld.delegate!(SciMLBase => DiffEqBase)` before DiffEqBase is compiled as a trait module; to confirm that delegation lifts §10.2's refusal, not only strict mode's. **Blocks P3** ("the facts mode first", compiling the unchanged packages as trait modules) for DiffEqBase until decided.

### 10.7 GPU and KernelAbstractions

- **The code.** `compkernel_f!` and friends pass the batch into a kernel (`coreloop.jl:141`–`:173`); `KAExecution` requires isbits batches.
- **The reference:** kept values hold a boxed object; a copying isbits layout is open issue §2 item 3.
- **Within the design:** `KAExecution` stays plain, with today's typed batches, behind the same `ExecutionStyle` switch. **Blocks:** the GPU path, which the workload does not use.

### 10.8 `getproperty` overloads

- **The code.** `Network` (`network_structure.jl:338`–`:346`), `NWState`/`NWParameter` (`symbolicindexing.jl:712`), `Observable` (`Observables.jl:92`), `Plot` (`compute-plots.jl:69`).
- **The reference:** a declared field is read from the stored field; a type with its own `getproperty` must map every declared field (§3.3).
- **Within the design:** operations, not fields, for these types. **Blocks:** nothing.

### 10.9 Inner constructors that compute parameters

- **The code.** `Network`'s inner constructor (`network_structure.jl:107`–`:115`), `ComponentBatch`'s (`:199`–`:202`), `IndexManager`'s (`:32`).
- **The reference:** a struct with a bounded parameter has no inner constructor; write an outer one (§7.4).
- **Within the design:** outer constructors. `ConstructionBase.constructorof` (`:117`) and Accessors' `@set` keep working on the plain fields. **Blocks:** nothing; mechanical.

### 10.10 Keyword-heavy front ends

- **The code.** `solve(prob, alg; kwargs...)`, `VertexModel(; kwargs...)` (`component_functions.jl:303`), Makie's attributes as `Dict{Symbol, Any}`.
- **The reference:** bounded keywords exist (§5.7); a function whose only bounded arguments are keywords is T-48; a container at a bounded keyword is T-39; `Callable` with keywords is Planned.
- **Within the design:** front ends stay plain and call a bounded function behind a barrier. **Blocks:** nothing.

### 10.11 Generated functions and RuntimeGeneratedFunctions

- **The code.** `@generated hash_fields`, `equal_fields` (`utils.jl:144`, `:161`), `Base.copy(c::ComponentModel)` (`component_functions.jl:1134`); RuntimeGeneratedFunctions for init formulas and MTK-generated component functions (`NetworkDynamics.jl:27`, `:48`; `sparsity.jl:267`–`:271`).
- **The reference:** a method's kind follows from its module (facts §6.1); a run-time generated function is a type defined in NetworkDynamics' module with a body made at run time.
- **Within the design:** an RGF as a component function is a value from outside the trait world (its type is RuntimeGeneratedFunctions'), so it enters `Dynamic` like any closure. The generated hash and copy helpers run at construction. To confirm under `all` (P3): that an RGF's call is a fact at concrete types. **Blocks:** nothing known.

### 10.12 The joint-method rule for two component traits

- **The code.** `apply_comp!` dispatches on `Type{<:VertexModel}` and `Type{<:EdgeModel}` (`coreloop.jl:176`, `:194`).
- **The reference:** unrelated bounds at one position need a joint method (§5.5).
- **Within the design:** two function names, `run_vertex_batch!` and `run_edge_batch!` (§3.3). **Blocks:** nothing.

### 10.13 What the check at `@implement` cannot see

- For `FunctionDynamics{F, G, FF}` the operation's method calls `d.f(…)` at abstract argument types, a run-time site in the check (facts §4.2), so a wrong arity of a plain function is still caught by NetworkDynamics' `hasmethod` checks at construction (`component_functions.jl:569`–`:570`), not by the declaration. The declaration catches it for a user's own type that implements `vf!` itself, and the declared `::Nothing` is enforced by the implementation's `nothing`. The port should say so in the guideline rather than promise more.

## 11. To measure first (for P1 and P5)

Registered as experiments before they run ([`../record/experiments.md`](../record/experiments.md)):

1. **The cost of changing the equations today,** split in two: build a second `Network` with new closures and compare `typeof(nw1) == typeof(nw2)`; time the second `solve` and the second `sol[VIndex(1, :x)]`. Then the same with the batches' function types erased by hand (a `Ref{Any}` around `compf`), to see how much of the recompilation is NetworkDynamics' and how much SciML's `sys` leak. This decides whether rank 3 moves up.
2. **The batch barrier's cost:** one `Network` with 1, 4 and 25 batches of a 1-state model, the right-hand side timed with today's tuple unrolling against a vector of batches with one dispatch per batch. A quick test, minutes.
3. **The split beyond four models:** five component model types in one network, to see the table's cost per batch (evidence §2, E-145) against the per-component work.
4. **`Spring`'s result type under the member check** (§2.3) and **`Graph`'s family over `AbstractGraph`** with one foreign graph type (a `SimpleWeightedGraph`): that the refusal is the one described in §2.2.
5. **DiffEqBase as a trait module** with and without `delegate!(SciMLBase => DiffEqBase)` (§10.6): which definitions are refused.
6. **Makie under facts** (P3): the compute graph's resolve path and `convert_arguments` dispatch, plain against `all`, to put a number on facts §13's "the speed of code that is not fully typed".
