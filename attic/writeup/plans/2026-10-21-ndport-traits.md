# The NetworkDynamics port, P2 and P4's first step: the traits, and the component dynamics behind a trait

Status: **adopted; parts P2 and P4 (first step) of the [W-32 meta plan](2026-10-21-networkdynamics-port.md)** (revised 2026-10-21 after the review [`../reviews/2026-10-21-ndport-traits-plan.md`](../reviews/2026-10-21-ndport-traits-plan.md) and P3's first results). Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) above all).

Inputs:
- the Fable exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) (cited "expl. §n");
- the P1 plan [`2026-10-21-ndport-workload.md`](2026-10-21-ndport-workload.md), its workload `ndport/scripts/workload_steps.jl`, and E-151's baselines ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), `ndport/logs/p1/`, `ndport/logs/p1-diag/`);
- the porting guideline [`../intro/porting.md`](../intro/porting.md);
- the P3 plan [`2026-10-21-ndport-facts-first.md`](2026-10-21-ndport-facts-first.md) and its first results (E-153, running: `ndport/logs/p3/`, `ndport/logs/p3-dev/`);
- the clone `ndport/pkgs/NetworkDynamics.jl` (1.3.0, branch `trait-port`, tag `upstream`) and TraitWorld at e9f4bfe.

File and line references to NetworkDynamics are to `ndport/pkgs/NetworkDynamics.jl/` at `upstream`. No Julia was run for this plan.

The ground rules of the meta plan apply:
- the design is not changed;
- pushback goes to the pushback log (its first entries: Appendix A);
- a Planned reference part the port really needs pauses the port and becomes a work item;
- a function at a time, with results equal to upstream at every step.

## Summary

- **One trait now:** `ComponentDynamics`, NetworkDynamics' component dynamics at the core loop's own calling convention, with the library's implementation `FunctionDynamics` built from a component's `f`, `g` and feed-forward kind.
- **The batches keep the model as a kept value** (`Kept{ComponentDynamics}`) instead of the function types and dimensions as type parameters. The core loop opens each batch's model with `compiled_for` and calls a bounded function that loops over the batch's components. The `Network`'s type then does not depend on the component functions or their dimensions.
- **What it should buy:** after a change of equations, only the new model's batch functions are compiled. SciML's integrator, the solution's symbolic access and the fixed point's NonlinearSolve code keep their types and are not compiled again. Upstream compiles about 16 s there ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), E-151); NetworkDynamics wrapped without traits still compiles about 15 s (E-153's N, `ndport/logs/p3/N-1.log`).
- **Later, each with its own plan, in this order:** `Graph` (Graphs), the user-facing `VertexDynamics`/`EdgeDynamics`, `ODERHS` with the integrator's `f`, `IndexProvider`/`ValueProvider`, `Trajectory`, `IntegratorView`/`Callback`. Not this round: `Positions`, `Source`, the Makie plot and attribute traits (§4).
- **Where the trait code lives:** the whole package is the trait module, starting from P3's wrap (`p3-wrap`) and P3's fix to Static.jl, in a worktree and an environment of its own (§2.2).
- **Nothing Planned is needed for the first step.** `ODERHS` with Rosenbrock's dual signatures needs W-29 (tuples of `Callable`s); the port routes around it (§1.7).
- **Measured cheaply** by E-152: the network's type equal for both equations (a gate); SciML's and SymbolicIndexingInterface's new CodeInstances in the "changed" pass (the headline); its compile time; the steady state within 10 % + 5 ms of the wrapped package; the digests exactly equal to upstream; the right-hand side's allocations (§3).

---

## 1. The traits adopted for this round

### 1.1 How the exploration was read

A recommendation is taken **now** if it serves the workload's first benefit (the run after changing the equations compiles as little as possible, expl. §0) with the smallest change, and needs nothing Planned.
- It is taken **later** if it is principled but buys little time for the workload, or needs another package to become partly a trait module first.
- It is **not** taken this round if it buys nothing for the workload and needs a rewrite or a Planned part.

The exploration's rank (expl. §9) is kept, with two changes:
- **Rank 1 is narrowed:** one trait at the core loop's calling convention, not two traits at the user's (§1.2).
- **The user-facing component traits** become a later step of their own (§4).

| Exploration | Decision | When | Reason |
|---|---|---|---|
| `ComponentDynamics` with `VertexDynamics`/`EdgeDynamics` (expl. §3.2) | `ComponentDynamics` alone, at the core loop's convention; `VertexDynamics`/`EdgeDynamics` later | now / later (step 3) | The core loop treats vertex and edge batches by one code path (`apply_compf`, `apply_compg`, `coreloop.jl:213–233`); one trait reaches the target with one implementation. The user-facing signatures matter only when users implement the trait themselves. |
| `FunctionDynamics` and the batch barrier (expl. §3.2, §3.3) | taken, with the feed-forward kind, `pdim` and `extdim` in the type (§1.2, PB-1) | now | The batch function needs them as constants to stay fully typed. |
| `FeedForwardType` as a value of an operation (expl. §3.1) | taken | now | |
| `StateMask`, the output wrappers, `ExecutionStyle`, `Aggregator`, `GBufProvider` as types (expl. §3.1) | taken: they stay plain | now | |
| Dimensions as values (expl. §3.3) | taken for the batches of the sequential and threaded styles; `KAExecution` keeps static dimensions | now | GPU kernels need isbits batches (PB-6). |
| `ComponentCondition`/`ComponentAffect` keeping `f::Callable{…}` (expl. §3.5) | later, with `IntegratorView`/`Callback` | later (step 7) | Their types do not change with the equations in the workload. The affect's result needs a decision (PB-9). |
| `Network` conforming to `ODERHS` and `IndexProvider` (expl. §4.2, §4.5) | later | steps 4, 5 | |
| `Graph{V}` (expl. §2.2) | taken | later (step 2) | Cheap, principled, the first family over an abstract type with real consumers; no time for the workload. |
| `Layout{Dim, Ptype}` (expl. §2.3) | decided by the `Graph` plan | later or not | Small benefit. It needs `dim`/`ptype` on types in NetworkLayout, or values stated per member (T-37). |
| `ODERHS{T, P}`, `ODEMassMatrix`; the integrator's `f` kept (expl. §4.2) | taken; `ODEJacobian` not | later (step 4) | `Network` has no Jacobian function. Tsit5 through the trait; Rodas5P stays on SciML's path until W-29 (§1.7). |
| `IndexProvider`, `ValueProvider` (expl. §4.5) | taken | later (step 5) | Pays with several providers in a session (tier M). |
| `Trajectory{U, T}` (expl. §4.4) | taken | later (step 6) | Small; types the Observables seam. |
| `IntegratorView{U, T, P}`, `Callback` (expl. §4.3) | taken | later (step 7) | Only if callbacks still compile per network after step 1. Writable fields to decide. |
| `Positions{N, T}` (expl. §5.2) | not this round | — | No time for the workload (expl. §1.3). Many conversion methods. A family per `(N, T)` meets T-38. |
| `Plot`, attribute traits, a typed compute graph (expl. §5.1) | not this round | — | A rewrite, not a port (expl. §5.1). |
| `Source{T}` (expl. §6) | not this round | — | Expressiveness only. `(Positions, Source{…})` bounds need W-29. |
| Initialization, sparsity, metadata, `show`, the doctor, the `solve` front end (expl. §8) | plain | — | Construction-time code, or outside the port's packages. |

### 1.2 NetworkDynamics, now: `ComponentDynamics` and `FunctionDynamics`

A new file `src/component_dynamics.jl` of the wrapped package, included after `component_functions.jl` (`NetworkDynamics.jl:60`). The operations name NetworkDynamics' existing functions qualified.

```julia
"What NetworkDynamics' core loop needs from a component's dynamics, at the loop's own calling convention."
@trait ComponentDynamics begin
    @default_with_dynamic_self
    hasf(m::ComponentDynamics)::Bool                                       # false for a static component
    NetworkDynamics.fftype(m::ComponentDynamics)::FeedForwardType
    NetworkDynamics.pdim(m::ComponentDynamics)::Int
    NetworkDynamics.extdim(m::ComponentDynamics)::Int
    compf!(m::ComponentDynamics, du, u, ins, p, t)::Nothing
    compg!(m::ComponentDynamics, outs::Tuple, u, ins, p, t)::Nothing
end

"A component's `f`, `g` and feed-forward kind, typed: NetworkDynamics' own implementation of `ComponentDynamics`."
struct FunctionDynamics{F, G, FF <: FeedForwardType, PDIM, EXTDIM}
    f::F
    g::G
end
FunctionDynamics(f, g, ff::FeedForwardType, pdim::Int, extdim::Int) =
    FunctionDynamics{typeof(f), typeof(g), typeof(ff), pdim, extdim}(f, g)

hasf(d::FunctionDynamics) = d.f !== nothing
NetworkDynamics.fftype(::FunctionDynamics{F, G, FF}) where {F, G, FF} = FF()
NetworkDynamics.pdim(::FunctionDynamics{F, G, FF, PDIM}) where {F, G, FF, PDIM} = PDIM
NetworkDynamics.extdim(::FunctionDynamics{F, G, FF, PDIM, EXTDIM}) where {F, G, FF, PDIM, EXTDIM} = EXTDIM
compf!(d::FunctionDynamics, du, u, ins, p, t) = (d.f(du, u, ins..., p, t); nothing)        # apply_compf, coreloop.jl:213
compg!(d::FunctionDynamics{F, G, PureFeedForward}, outs, u, ins, p, t) where {F, G} = (d.g(outs..., ins..., p, t); nothing)
compg!(d::FunctionDynamics{F, G, FeedForward}, outs, u, ins, p, t) where {F, G} = (d.g(outs..., u, ins..., p, t); nothing)
compg!(d::FunctionDynamics{F, G, NoFeedForward}, outs, u, ins, p, t) where {F, G} = (d.g(outs..., u, p, t); nothing)
compg!(d::FunctionDynamics{F, G, PureStateMap}, outs, u, ins, p, t) where {F, G} = (d.g(outs..., u); nothing)
@implement ComponentDynamics D where {D <: FunctionDynamics}
```

**Why this shape.**
- **The operations are what `apply_comp!` reads from a batch** (`coreloop.jl:176–248`): whether `f` exists (`evalf`, `:243`), the feed-forward kind (`_needs_u`, `_needs_in`), `pdim` (`_needs_p`, `:240`), the external inputs (`has_external_input`, `external_inputs.jl:84`), and the two calls.
- **The buffer arguments are untyped on purpose.** The loop passes views or `nothing` (`_needs_*`). It runs at `Float64`, at ForwardDiff's duals (the fixed point, the linear analysis, Rodas5P), at sparsity tracers, and with `t === nothing` from symbolic indexing (expl. §3.2, §10.1). On a `Compiled` trait object each call is a direct call at the loop's concrete types (traits §6.8).
- **`pdim` and `extdim` are constants of the key.** They decide whether `p` is `nothing` and whether the external inputs join `ins`. As run-time values they would give `Union` arguments at the user's function. The type parameters `PDIM` and `EXTDIM` make inference see a constant per key, as the batch's `StaticInt` strides do upstream. This is an associated constant written as a type parameter: PB-1.
- **`@default_with_dynamic_self`** is for later public entries (a user's model passed in plain code). Inside the batch the library's cast decides (traits §6.4).
- **The record `VertexModel` does not change.** It keeps `f::Any`, `g::Any` for metadata, printing, the doctor, sparsity and initialization (expl. §3.2).

**Each construct against TraitWorld today** (e9f4bfe):

| Construct | Where | Status | Deviations met |
|---|---|---|---|
| `@trait_module begin … end` around a package's body | [traits §2](../reference/traits.md#2-trait-modules) | Implemented | none. E-153: NetworkDynamics precompiles wrapped in 18 s, nothing refused, digests equal to upstream (`ndport/logs/p3-dev/wrap-precompile.log`, `ndport/logs/p3/N-1.log`) |
| `@default_with_dynamic_self` | [§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations); `TraitWorld/src/trait.jl:225` | Implemented | not inherited by subtraits (per trait, `attributes.jl:207`); irrelevant with one trait |
| operations on existing functions (`NetworkDynamics.fftype`), untyped arguments, an abstract result | [§3.1](../reference/traits.md#31-operations) | Implemented | none. The functions exist before the module (`component_functions.jl:55`, `:425`, `:518`) |
| one-line family by the type's own methods, variable form `D where {D <: FunctionDynamics}` | [§4.7](../reference/traits.md#47-families) | Implemented | T-5 and T-38 avoided by the variable form; T-32 avoided (no block); members are checked at first use |
| `Kept{X}(x)`; a struct field holding a `Kept{X}` (here through the type parameter `M`) | [§7.1](../reference/traits.md#71-the-three-forms), [§7.2](../reference/traits.md#72-a-traits-name-as-a-storage-type) | Implemented | L-25: a family member becomes a split candidate only when a `Dynamic` of it is made |
| `compiled_for(k)` on a kept value in code that is not bounded on it, at a bound | [§6.4](../reference/traits.md#64-casts), [§6.8](../reference/traits.md#68-costs-and-choosing) | Implemented | a family member is not served by the table and takes the generic path ([lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)): PB-4 |
| a bounded function with one trait position and ordinary arguments; an internal function taking the trait object | [§5](../reference/traits.md#5-bounded-functions), [§5.4](../reference/traits.md#54-internal-functions) | Implemented | L-3 not met: new functions of the module |
| a closure over a trait object given to `Threads.@threads` | [§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object) ("a closure passed to Base") | Implemented | Polyester's `@batch` is not Base: PB-7 |
| `Callable` | — | not used | T-51 (six arguments) avoided: no component function is kept as a `Callable` (expl. §10.2) |

### 1.3 Graphs and NetworkLayout: later (step 2)

The declaration the `Graph` plan starts from. It lives in Graphs, the owner of `AbstractGraph` and of the functions. `@trait` and `@implement` work in any module (traits §2), so Graphs need not become a trait module.

```julia
@trait Graph{V <: Integer} begin
    @default_with_dynamic_self
    V = eltype(Self)                                   # Graphs' eltype on graph types (expl. §2.2)
    Graphs.nv(g::Graph{V})::V
    Graphs.ne(g::Graph)::Int
    Graphs.is_directed(g::Graph)::Bool
    Graphs.has_edge(g::Graph{V}, s::V, d::V)::Bool
    Graphs.outneighbors(g::Graph{V}, v::V)::AbstractVector{V}
    Graphs.inneighbors(g::Graph{V}, v::V)::AbstractVector{V}
    edgelist(g::Graph{V})::Vector{SimpleEdge{V}}
end
edgelist(g::AbstractGraph) = collect(edges(g))
@implement Graph G where {G <: AbstractGraph}         # every subtype, by its existing methods, checked at first use
```

- **Constructs:**
  - a parameter bound and an equation: [§3.4](../reference/traits.md#34-parameters-and-associated-types);
  - a family over an abstract type, by existing methods: [§4.7](../reference/traits.md#47-families), [§10.1](../reference/traits.md#101-who-may-implement) (the trait's owner implements for foreign subtypes).
- **Deviations:** T-38 refuses `S{P} where {P}` for a trait whose parameters are defined by equations. The variable form above works.
- **The consumers it bounds:**
  - NetworkDynamics' `IndexManager` (`network_structure.jl:32–55`);
  - GraphMakie's helpers (`recipes.jl:313`, `:599`, `:887`). GraphMakie then becomes partly a trait module, since bounded functions exist only there.
- **The plan settles** the operation list against those consumers (`degree`, `all_neighbors`, `vertices`), and `Layout`.

### 1.4 SciML: later (steps 4–7)

Starting declarations, each confirmed by its plan.

```julia
# SciMLBase (owner of the concept)
@trait ODERHS{T, P} begin
    @default_with_dynamic_self
    rhs!(f::ODERHS{T, P}, du::Vector{T}, u::Vector{T}, p::P, t::Float64)::Nothing
end
# NetworkDynamics
SciMLBase.rhs!(nw::Network, du, u, p, t) = (nw(du, u, p, t); nothing)   # the function's name as the step's plan decides
@implement ODERHS{Float64, Vector{Float64}} N where {N <: Network}    # a family with stated values

# SymbolicIndexingInterface
@trait IndexProvider begin
    @default_with_dynamic_self
    SII.is_variable(ip::IndexProvider, sym)::Bool
    SII.variable_index(ip::IndexProvider, sym)::Union{Nothing, Int}
    SII.is_parameter(ip::IndexProvider, sym)::Bool
    SII.parameter_index(ip::IndexProvider, sym)::Union{Nothing, Int}
    SII.is_observed(ip::IndexProvider, sym)::Bool
    SII.observed(ip::IndexProvider, syms)::Function
    SII.is_time_dependent(ip::IndexProvider)::Bool
end
@trait ValueProvider{U, P} begin
    SII.state_values(v::ValueProvider{U})::U
    SII.parameter_values(v::ValueProvider{U, P})::P
end

# SciMLBase
@trait Trajectory{U, T} begin
    times(s::Trajectory{U, T})::Vector{T}
    state(s::Trajectory{U, T}, i::Int)::U
    at(s::Trajectory{U, T}, t::T)::U
end
```

- **`ODERHS`:**
  - `ODEMassMatrix` as a subtrait waits for its plan: a supertrait with parameters is not shown in [§3.6](../reference/traits.md#36-supertraits-and-bundles).
  - The integrator's `f` kept as a `Callable` is a struct parameter bounded by `Callable`. That needs `ODEIntegrator` in a trait module, without an inner constructor ([§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)). The plan checks `ODEIntegrator`'s constructors.
  - A family with stated parameter values (`ODERHS{Float64, Vector{Float64}} N where {N <: Network}`) is to be checked in TraitWorld.
- **`ValueProvider`** leaves `current_time` out: its result is not one type across providers (expl. §4.5 declared `::Any`, which checks nothing).
- **`IntegratorView`/`Callback`:** expl. §4.3 is the starting point. Which fields are writable is the plan's first decision (`set_u!` writes `u`).
- **Where trait code lands in SciML:** DiffEqBase's cross-package methods are pirates by the letter (expl. §10.6). P3 owns that question; steps 4 and 7 wait for its answer where they put bounded code into DiffEqBase.

### 1.5 Makie, GraphMakie, Observables: not this round, except `Graph`'s bounds in GraphMakie

- GraphMakie's helpers bounded by `Graph`: step 2 (§1.3).
- `Positions`, `Source`, the plot and attribute traits: not this round (table in §1.1). Revisit triggers in §6.

### 1.6 What stays plain

As expl. §8:
- closed library families;
- construction-time and metadata code;
- code that is dynamic by design (Observables, ComputePipeline, Makie's attributes);
- code outside the port's packages (NonlinearSolve, SparseConnectivityTracer, KernelAbstractions, RuntimeGeneratedFunctions).

Unchanged in the first step, though compiled by facts as part of the wrapped package:
- `apply_comp!` and the KA kernels (`coreloop.jl:141–233`), for the typed batches of `KAExecution`;
- `get_buffers`, the aggregators and the gather buffers.

### 1.7 Planned parts and blocking deviations: pause or route around

| What | Needed by | Planned part or deviation | Decision |
|---|---|---|---|
| The solver's dual signatures for the right-hand side (Rodas5P's Jacobian) | step 4 (`ODERHS`) | a function kept at two signatures: tuples of `Callable`s as a struct parameter's bound, Planned ([§3.7](../reference/traits.md#37-tuples-of-traits), [W-29](../record/todo.md)) | **Route around:** Tsit5 through `ODERHS`; Rodas5P keeps SciML's own wrapper (`promote_f`, `DiffEqBase/src/solve.jl:1011`). No pause: W-29 is queued; Rodas5P follows when it lands. PB-8. |
| A component condition called at duals as well as at `Float64` | step 7 | the same (W-29) | Route around: the dual call stays on the plain path. |
| An edge function kept as a `Dynamic` `Callable` (seven or eight arguments) | — | T-51 | Not met: component functions are reached through `ComponentDynamics`' operations, never kept as `Callable`s. |
| `Positions` as a family per `(N, T)`, forwarding for a family | — | T-38, T-7 (Planned) | Not met this round. |
| `Layout`'s parameters by equations on the type | step 2, if taken | NetworkLayout defines `dim`/`ptype` on instances only; a stated value replaces an equation in a family unchecked (T-37, L-26) | The `Graph` plan decides; not blocking. |
| Pirates in DiffEqBase | steps 4, 7 | traits §10.2; open issues §1.20 | P3's question; those steps wait for its answer. |

**The first step needs nothing Planned and meets no blocking deviation.**

---


## 2. The first port step: the component dynamics behind `ComponentDynamics`

### 2.1 What changes, and what does not

- **Before** (`network_structure.jl:88`, `:181`):
  - `ComponentBatch{T,F,G,FFT,DIM,PDIM,INDIMS,OUTDIMS,EXTDIM,IV}` carries the user's function types and every dimension, the dimensions as `StaticInt` strides (`utils.jl:1–10`);
  - `Network{…,VTup,…}` carries the vertex batches' tuple, and `NetworkLayer{GT,ETup,AF}` the edge batches'.
  - So `swing2!` (a new `F`, and `PDIM` 3 → 4) is a new `Network` type. SciML carries that type into the problem, the integrator, the solution and the fixed point's nonlinear problem ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), E-151's attribution).
- **After,** for `SequentialExecution` and `ThreadedExecution`:
  - each batch is `ComponentBatch{T, Any, Any, FeedForwardType, Int, Int, I, O, Int, Vector{Int}, Kept{ComponentDynamics}}`, with `I` and `O` `Int` for vertices and `@NamedTuple{src::Int, dst::Int}` for edges: one concrete type per kind;
  - both containers are a `Vector` of that type;
  - the model is the batch's `model` field, a `Kept{ComponentDynamics}` holding a `FunctionDynamics`;
  - per pass, the core loop builds one `Ref` of the pass's arguments and calls, per batch, `run_vertex_batch!(compiled_for(batches[k].model), batches, k, args)` or `run_edge_batch!`: bounded functions that loop over the batch's components, compiled for the model's key.
- **The scope of the claim:** a change of component functions and of their dimensions. A change of the network's structure still changes the `Network`'s type: the mass matrices (ODE to DAE components), loopback edges, external inputs, the execution style, the aggregator (`NaiveAggregator` turns the edge batches into a tuple again, `aggregators.jl:18–25`). Every path from a component to SciML, with where it stands after the step: the review's table ([finding 2](../reviews/2026-10-21-ndport-traits-plan.md#2-should-fix-the-claim-needs-its-scope-and-its-list-of-paths)). The attribution run (§3) is read against it.
- **What compiles for a new key after the change:**
  - the two batch functions and `_vertex!`/`_edge!` per argument signature: the pass (`Val{:g}`, `Val{:f}`, `Val{:fg}`), the buffers (`(nothing, nothing)`, `(aggbuf, nothing)`, `(gbuf, extbuf)`), the element types (`Float64`, the duals of the fixed point, the linearization and Rodas5P), and `du === nothing` with `t === nothing` from `get_buffers` (`coreloop.jl:103–109`);
  - `swing2!` at each of these;
  - in step b: `FunctionDynamics`' constructor, `Kept{ComponentDynamics}(x)` and the family member's check at first use;
  - at the first crossing: the entry's table entries for the new type.
- **Unchanged:**
  - the record types and the public API;
  - the order of every operation, so the digests stay exactly equal;
  - `KAExecution`'s typed batches and kernels (GPU kernels need isbits batches: PB-6);
  - `PolyesterExecution` until S7 decides (PB-7).

### 2.2 Where the code lives

- **NetworkDynamics is the trait module, whole** (`@trait_module begin … end` around the package's body: P3's wrap). This is the guideline's layout for a package written without traits ([0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)). The bounded functions stand in `coreloop.jl`, and they may pass the trait object to the package's own internal functions ([traits §5.4](../reference/traits.md#54-internal-functions)).
- **The working tree** (the review's finding 1):
  - the worktree `ndport/pkgs/NetworkDynamics-p4` on branch `trait-port`, started from `p3-wrap` (e5425fd, "The package is a trait module");
  - the main clone `ndport/pkgs/NetworkDynamics.jl` stays at `upstream` (detached) for P0; P3's worktree `NetworkDynamics-p3wrap` stays on `p3-wrap` for N;
  - `git -C pkgs/NetworkDynamics-p4 diff upstream` is the port.
- **The environment:** `ndport/env_p4`, as `env_p3` (NetworkDynamics' path at the P4 worktree) with the Static.jl clone (`ndport/pkgs/Static.jl`, branch `trait-port`, c34adbb). Its depot: `JULIA_DEPOT_PATH=ndport/depot-p4:$HOME/.julia:`.
- **Static.jl's fix is part of the port's base.** `Base.promote_rule(::Type{<:StaticInt}, T2::Type{<:Signed}) = promote_type(T2, Int)`: without it, `x * StaticInt(N)` in code compiled by facts is a run-time site, and the wrapped core loop is about 1500 times slower (`ndport/logs/p3-dev/static-fix.log`; facts §8, the dropped `:foldable` assertion of `typejoin`). With it, the wrapped package's steady state is faster than upstream's (a Tsit5 solve 15.3 against 19.7 ms, `ndport/logs/p3/N-1.log`). The typed batches of `KAExecution` and the first step's S1–S4 still use `StaticInt` strides.
- **Pirates:** none. E-153's wrap refused nothing. The new code defines methods of its own functions (`hasf`, `compf!`, `compg!`, the batch functions) and of the package's `fftype`, `pdim`, `extdim` for its own type.
- **Extensions:**
  - `NetworkDynamicsCUDAExt` rebuilds batches with the positional constructor (`ext/NetworkDynamicsCUDAExt.jl:132`) and so keeps typed batches without a model (S3); GPU batches stay isbits.
  - `NetworkDynamicsDataFramesExt` reads `batch.indices` only; `NetworkDynamicsMTKExt` calls `compfg` on records.
  - None declares an implementation or names the trait on an argument, so none is wrapped (the P3 plan §1.4, items 4 and 7).
- **The precompile workload** (`NetworkDynamics.jl:205–208`) becomes `TraitWorld.@workload` at S4, with the first bounded functions: inside a trait module a workload must fix the entries first ([lowering §15.2](../reference/lowering.md#152-workloads); the P3 plan §1.4, item 6). It builds a sequential network and calls it, so ND's image holds the core loop for a `Network` type the workload's network shares, and the batch functions for the workload's own closures' keys.
- **No `@implement` compiles ahead here:** a family's members are not known when ND is precompiled ([§13](../reference/traits.md#13-compiling-ahead)).
- **Fallback, only if the wrapped package must be given up:** one trait submodule `@trait_module module BatchLoop … end` in a file included after `gbufs.jl` (`NetworkDynamics.jl:71`), holding the trait, `FunctionDynamics`, the `@implement` and the batch functions. `ComponentBatch` names the model only by its type parameter `M`, and `VertexBatch`/`EdgeBatch` build the model, so no code moves (the review's finding 5). The package's own workload then stays plain.

### 2.3 The batch functions

In `coreloop.jl`, after `apply_comp!` (`:211`):

```julia
# what a pass evaluates (coreloop.jl:243–248), with f's presence read from the model
_evalf(::Val{:f}, hf::Bool) = hf
_evalf(::Val{:g}, hf::Bool) = false
_evalf(::Val{:fg}, hf::Bool) = hf
_evalg(::Val{:f}) = false
_evalg(::Val{:g}) = true
_evalg(::Val{:fg}) = true

function run_vertex_batch!(m::ComponentDynamics, batches::Vector, k::Int, args::Base.RefValue)
    (ex, fg, inbufs, du, u, o, p, t) = args[]
    batch = batches[k]
    if ex isa ThreadedExecution
        Threads.@threads for i in 1:length(batch)
            _vertex!(m, fg, batch, i, du, u, o, inbufs, p, t)
        end
    else
        for i in 1:length(batch)
            _vertex!(m, fg, batch, i, du, u, o, inbufs, p, t)
        end
    end
    nothing
end

# apply_comp!(::Type{<:VertexModel}, …), coreloop.jl:176–192, with the batch's static facts read from the model
function _vertex!(m, fg, batch, i, du, u, o, inbufs, p, t)
    ef = _evalf(fg, hasf(m)); eg = _evalg(fg); ff = NetworkDynamics.fftype(m)
    nu = ef || ff != PureFeedForward()                                        # _needs_u
    ni = ef || ff isa Union{PureFeedForward, FeedForward}                     # _needs_in
    np = !iszero(NetworkDynamics.pdim(m)) && (ef || ff != PureStateMap())     # _needs_p
    @inbounds begin
        aggbuf, extbuf = inbufs
        _o   = eg ? view(o, out_range(batch, i))            : nothing
        _du  = ef ? view(du, state_range(batch, i))         : nothing
        _u   = nu ? view(u, state_range(batch, i))          : nothing
        _ins = ni ? (view(aggbuf, in_range(batch, i)),)     : nothing
        _p   = np ? view(p, parameter_range(batch, i))      : nothing
        if !iszero(NetworkDynamics.extdim(m)) && ni
            _ins = (_ins..., view(extbuf, extbuf_range(batch, i)))
        end
        ef && compf!(m, _du, _u, _ins, _p, t)
        eg && compg!(m, (_o,), _u, _ins, _p, t)
    end
    nothing
end
# run_edge_batch! and _edge! alike: get_src_dst(gbuf, batch, i), (_osrc, _odst) (coreloop.jl:194–211)
```

- **The flags are computed inside the per-component function** from the operations' results, which inference sees as constants per key. No flag crosses a call as a `Bool` value, so the code stays fully typed without relying on inlining.
- **Why `_needs_*` is restated:** the erased batch no longer carries the static facts (`fftype(batch)` is an abstract field, `pdim(batch)` an `Int`). The batch-based helpers would give `Union` arguments at the user's function. `apply_comp!` keeps using them for typed batches.
- **The arguments travel in one `Ref` per pass,** upstream's own pattern for its vector of batches (`utils.jl:56–70`). The batch crosses as the vector and an index. So the dynamic call at the barrier boxes nothing: the vector and the `Ref` are heap objects, and Julia keeps boxes of small `Int`s preallocated. What remains per crossing is the trait object, built behind a dynamic call on the generic path for family members (lowering §9.3): PB-4.

The core loop gains one method beside upstream's (`coreloop.jl:111–139`), for the erased containers:

```julia
const KeptBatch = ComponentBatch{<:Any, Any, Any, FeedForwardType, Int, Int, <:Any, <:Any, Int, <:Any, <:Kept}

function process_batches!(ex::Union{SequentialExecution, ThreadedExecution}, fg, filt::F,
                          batches::Vector{B}, inbufs, duopt) where {F, B <: KeptBatch}
    (du, u, o, p, t) = duopt
    args = Ref((ex, fg, inbufs, du, u, o, p, t))
    for k in eachindex(batches)
        filt(batches[k]) || continue
        m = compiled_for(batches[k].model)
        dispatchT(B) === VertexModel ? run_vertex_batch!(m, batches, k, args) :
                                       run_edge_batch!(m, batches, k, args)
    end
    nothing
end
```

Upstream's methods (tuples, typed batches, KA, Polyester) are untouched and serve every other container.

### 2.4 The changes, a function at a time

Each row is one commit on `trait-port` in the P4 worktree. Each is followed by its check (§2.5): (P) ND precompiles in `env_p4`, which runs the trait code's definition checks; (R) `rhs_check.jl`: bits equal to upstream's; (W) the full workload in setting P, one run, `compare_digests.py --exact` against E-151's U log; (T) ND's test subset.

| # | File:line (at `upstream`) | Function | Change | Check |
|---|---|---|---|---|
| S0 | the P4 worktree; `ndport/env_p4`, `ndport/depot-p4`; `scripts/run_workload.sh` | — | the worktree on `trait-port` from `p3-wrap`; `env_p4` with Static's fix, resolved offline; the harness's setting P (`env_p4`, `depot-p4`). E-152 registered, status running, before the first run | P; R in U and in P at S0 (the references); T at `upstream` (the reference list) |
| S1 | new `src/component_dynamics.jl`; its include after `src/NetworkDynamics.jl:60` | `ComponentDynamics`, `FunctionDynamics`, its methods, `@implement` | §1.2 | P, R; and `compf!`/`compg!` on a `Kept{ComponentDynamics}` of each check network's components give the same bits as `apply_compf`/`apply_compg` |
| S2 | `src/utils.jl:1–10`, `:21` | `BatchStride`, `_range` | `_dynamic(bs)`: the same stride with `Int` strides; `_range(bs::BatchStride{<:Union{StaticInt, Int}}, i)` | P, R |
| S3 | `src/network_structure.jl:181–206` | `ComponentBatch` (struct, inner constructor), `ConstructionBase.constructorof` | a last type parameter `M` and field `model::M`; keywords `kept = false`, `erased = false`. `kept` stores `Kept{ComponentDynamics}(FunctionDynamics(f, g, ff, pdim, extdim))`, else `nothing`; `erased` (with `kept`) gives `F = G = Any`, `FFT = FeedForwardType` and `_dynamic` strides. `constructorof` passes both from the type, so `@set batch.compf = …` (`sparsity.jl:108–170`) rebuilds the model. The positional call (CUDA ext) gives upstream's batch with `M = Nothing` | P, R |
| S4 | `src/coreloop.jl`, after `:211`; `src/NetworkDynamics.jl:205–208` | `run_vertex_batch!`, `run_edge_batch!`, `_vertex!`, `_edge!`, `_evalf`, `_evalg`; the package's workload | §2.3, not called yet; `@compile_workload` becomes `TraitWorld.@workload` | P, R |
| S5 | `src/construction.jl:381–396`, `:399–414`, and the containers at `:184–207` | `VertexBatch`, `EdgeBatch`; the batch containers in `Network(g, …)` | `kept = erased = true` for `SequentialExecution` and `ThreadedExecution`; their batches a `Vector` (never a tuple: `MAX_UNROLLED_BATCHES`, `:5`, applies to typed batches only). Upstream's `process_batches!` runs them through `apply_comp!`, a call per component dispatched at run time: slow, and exact | P, R with **`sametype=true`** from here on |
| S6 | `src/coreloop.jl:111–139` (a new method beside them) | `process_batches!` for erased containers, `KeptBatch` | §2.3: the batch functions run the core loop | P, R (the threaded style with `-t 2`), **W**, **T** |
| S7 | `src/coreloop.jl:131–139` | `process_batches!(::PolyesterExecution, …)` | first, `Polyester.@batch`'s expansion is read once against the definition check (`TraitWorld/src/checks.jl:101–111`, `:150–158`, `:191–195`), and the answer recorded in PB-7. If a closure over the trait object is accepted, Polyester joins the erased path (its loop inside `run_*_batch!`); if not, it keeps typed batches | P, R |
| S8 | `ndport/` | — | E-152's runs (§3), T, the README's dated table, the guideline's B5 lessons (§5), commits | §3 |

- **Not changed:** `Network`'s struct and inner constructor (its parameters are computed from the containers' types, which no longer vary); `apply_comp!`, the KA path, the aggregators, `get_buffers`, symbolic indexing, callbacks, sparsity, the extensions.
- **Exact equality is expected at every row:** the same user functions run on the same views in the same order. A differing exact field is a port bug, unless the site uses `@muladd` or `@fastmath` (guideline 0.6).

### 2.5 The checks

- **`ndport/scripts/rhs_check.jl`** (new; about a minute with KernelAbstractions' CPU kernels):
  - **the networks:** tier S's, with `swing!` and with `swing2!`; and small networks without ModelingToolkit that reach what the batch functions restate (the review's finding 7): a vertex of each feed-forward kind (`PureFeedForward`, `FeedForward`, `NoFeedForward`, `PureStateMap`), with a loopback edge where ND requires one, and a model with external inputs (`extin`);
  - **for each network and each execution style:** the hash of the bits of `du` at a fixed `u` and `p`, and of `get_buffers`' `o`, `aggbuf` and `extbuf`; `get_jac_prototype(nw)` (SparseConnectivityTracer, ND's own dependency, through `@set batch.compf`);
  - `sametype=` (whether tier S's two `Network` types are equal);
  - `allocs=` (`@allocated` of a warmed call) and `ns=` (the minimum of three timings of 10⁴ calls), for tier S.
  - It runs in U before S0 (the reference), and in P after each row; the threaded style in a session with `-t 2`.
- **The full workload (W):** `run_workload.sh <tag> P 1` after S6; two runs at S8 (§3).
- **Before each P run:** ND and its extensions precompiled in `env_p4` through the lock (`JULIA_NUM_PRECOMPILE_TASKS=4`, niced). Nothing else in `env_p4` depends on ND.
- **ND's own tests (T),** after S6 and at S8:
  - the files that load without ModelingToolkit, Chairmarks, Symbolics or a GPU: `massmatrix_test.jl`, `doctor_test.jl`, `diffusion_test.jl`, `inhomogeneous_test.jl`. They cover every execution style (`testutils.jl:9`), the zero-allocation right-hand side (`diffusion_test.jl:111`), and more than 25 batches (`inhomogeneous_test.jl:89–93`);
  - two small environments: `ndport/env_ndtest_u` (`env_port`'s project, the clones at `upstream`) and `ndport/env_ndtest_p4` (`env_p4`'s), each with OrdinaryDiffEqNonlinearSolve from the depot, resolved offline;
  - **the driver** `ndport/scripts/nd_tests.jl` includes the files. It defines `test_execution_styles` from `testutils.jl` without its CUDA block (skipped anyway without a GPU, `testutils.jl:70`), so CUDA is not loaded. The copy is committed beside the driver;
  - the port must pass what upstream passes here, except the allocation assertions PB-4 explains, each listed.

### 2.6 Risks

- **The barrier's remaining cost:** one trait object per crossing, built behind a dynamic call, and an entry-table lookup that misses for family members (lowering §9.3; PB-4). About three crossings per right-hand side in tier S. By reading, a few hundred ns per crossing, a few ms over step d: within criterion 3's slack, while ND's allocation assertions fail (`diffusion_test.jl:111`; `inhomogeneous_test.jl:93`, whose count then grows with the number of batches).
- **`@propagate_inbounds` component functions** lose the loop's `@inbounds`: upstream's `apply_compf`/`apply_compg` propagate it (`coreloop.jl:213–233`), the operation does not. Results stay equal; a slower step is read with this in mind. `swing!` does not use it; ND's precompile workload does (`precompile_workload.jl:4–11`).
- **`ThreadedExecution` in a bounded function:** `Threads.@threads` builds a closure over the trait object. [§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object) allows a closure passed to Base. Threads are untested in the facts mode ([evidence §5](../design/evidence.md#5-not-shown)); S6 runs the threaded check with two threads. If the definition check refuses the closure, Threaded keeps typed batches, and the disagreement is reported as a deviation.
- **What the member check checks:** with untyped declared arguments, a member's check asks only that the methods exist (`TraitWorld/src/implement.jl:256–264`); inference does not run. A member with `f === nothing` (a static edge) passes the same way. A wrong arity of a user's `f` is caught by ND's construction checks (`component_functions.jl:569–570`), not by the trait.
- **The wrapped package's first fixed point is slower** than upstream's (21.9 against 6.5 s in N, `ndport/logs/p3/N-1.log`): NonlinearSolve's code, reached from the trait module, is compiled by facts in the session. That is P3's finding; criterion 4 compares with N for that reason.

---

## 3. What success means, measured cheaply

**The settings** (the P1 plan §3.2; the P3 plan §4):
- **U:** upstream, the reference for results.
- **P0:** the clones at `upstream`, TraitWorld loaded, product setting (E-151).
- **N:** NetworkDynamics wrapped, without traits, with Static's fix (E-153). The "before" of the trait's own effect.
- **P:** the P4 worktree at S8, `env_p4`, `depot-p4`; two runs.
- **One attribution run in P** (`NDW_DIAG=1`, `ndport/scripts/diag.jl`): the new CodeInstances per step, by module.

Strict mode is off and the load order is fixed (the P1 plan §2.3). With n = 2 the numbers are indicative; P5 owns measurement rounds.

**What the numbers measure:** NetworkDynamics' own trait code (the batch functions) calling the user's plain component functions. That is interop, not idiomatic trait code: no user type implements a trait in this step.

| # | Criterion | Before | Pass when |
|---|---|---|---|
| 0 | **The claim itself** | U, P0, N: tier S's two networks have different types | `sametype=true` in `rhs_check.jl` from S5 on. A gate |
| 1 | Results | P0 and N equal U exactly (E-151; `ndport/logs/p3/N-1.log`) | `compare_digests.py --exact` of each P log against U passes; "again" equals "first" in each run; every `rhs_check.jl` hash equals U's |
| 2 | **"changed" b–e: CodeInstances of SciML and SII** (the headline) | U's attribution run: about 2,300 of "changed" c–e's 6,536 new CodeInstances belong to SciML's and SymbolicIndexingInterface's modules (c 857, d 1,259, e 219; `ndport/logs/p1-diag/U-1.log`) | at most **50** new CodeInstances in steps b–e of "changed" whose method's root module is SciMLBase, DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock, OrdinaryDiffEqDifferentiation, a NonlinearSolve package, SteadyStateDiffEq or SymbolicIndexingInterface. A count above it names the leak |
| 3 | "changed" b–e: compile time | P0: 15.8–15.9 s for the pass ([evidence §3](../design/evidence.md#3-first-calls-and-sessions)); N: 77 + 3,626 + 8,702 + 2,565 ms for b–e (`N-1.log`, one run) | the sum over b–e at most **2,000 ms** in both P runs; a–g reported |
| 4 | Steady state ("again") | N per step (`N-1.log`; E-153's second run when it exists) | each step, minimum of two runs, at most **1.10 × N's + 5 ms**; also reported against P0. A failure is confirmed by one more P run before it counts |
| 5 | First session | N: the first pass, the loads | reported against N and P0; not a gate |
| 6 | The right-hand side | U: `allocs` 0 | `allocs` per call at most the passes with batches (one `Ref` each) plus the crossings (PB-4); the numbers and `ns` reported against U and N |
| 7 | ND's tests | the subset at `upstream` | the same passes, except PB-4's allocation assertions, each listed |

**What a failure changes:**
- **Criteria 0 and 1** are port bugs, fixed before anything else.
- **Criterion 2 above 50:** the attribution run names the module and the type that still varies, read against the review's table of paths. If SciML's types still vary, `ODERHS` (step 4) moves to step 2. If NonlinearSolve's tags carry the network's closures, the fixed point's problem gets its own step.
- **Criterion 3 above 2 s with criterion 2 met:** the time is in NetworkDynamics' own code or the batch functions' signatures (§2.1's list); recorded, and the next plan says whether to reduce it.
- **Criterion 4 failing, confirmed:** the barrier costs more than estimated (§2.6). The port stops before step 2; the numbers go to [open issues §4](../open-issues.md#4-runtime-and-measurements), item 35, and PB-4; the user decides.
- **Criterion 6 above its bound:** an allocation the step was to remove (the `Ref` pattern) is still there: a port bug.

**The registry row,** to be added to `writeup/record/experiments.md` §11 with status running before the first `rhs_check.jl` run (S0). E-152 is the ID the P3 plan reserves for this step.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-152 | W-32 P4, step 1: NetworkDynamics' component dynamics behind `ComponentDynamics`, the sequential and threaded batches erased, in the package wrapped as a trait module ([the traits plan](../plans/2026-10-21-ndport-traits.md) §2). Tier S, product setting, strict mode off, fixed load order, two runs per setting; P against U (results), N (E-153, the trait's own effect) and P0 (E-151). (0) Is the network's type the same for both equations? (1) Are the digests and the right-hand-side checks exactly equal to U? (2) How many new CodeInstances of SciML's packages and SymbolicIndexingInterface does the "changed" pass create in steps b–e (upstream about 2,300 in c–e)? (3) How long does it compile there (N: about 15 s)? (4) Is each steady-state step within 10 % + 5 ms of N? (5) What does the right-hand side cost and allocate per call? (6) Does ND's test subset pass as at `upstream`? Measures library trait code calling plain user functions (interop). **Would change the plan:** different network types, or an exact difference (port bugs); more than 50 such CodeInstances (the attribution names the leak; `ODERHS` may move up); a confirmed steady-state step outside the margin (the port pauses; open issues §4 item 35); allocations beyond one per pass plus one per crossing (a port bug). | running (from S0) | `ndport/` (its own repository): `scripts/rhs_check.jl`, `nd_tests.jl`, `diag.jl`, `run_workload.sh` (setting P); `env_p4`, `env_ndtest_*`; `logs/p4-1/`; the worktree `pkgs/NetworkDynamics-p4`, branch `trait-port` | — | `ndport/README.md`; [the traits plan](../plans/2026-10-21-ndport-traits.md) |

When E-152 is done, its outcome and an evidence row in `writeup/design/evidence.md` are written in one commit (CLAUDE.md, rule 1).

---

## 4. The order after the first step

Each is a later plan, written and reviewed before its work starts. Each keeps the workload's digests equal to upstream's and says what it buys.

1. **Step 2: `Graph` in Graphs** (§1.3), with `Layout` if its plan takes it.
   - **Why second:** cheap; no Planned part; the port's first family over an abstract type, with two real consumers (ND's `IndexManager`, GraphMakie's helpers).
   - It makes GraphMakie partly a trait module, the first port step outside NetworkDynamics.
   - No time for tier S. A new graph type is tier M.
2. **Step 3: `VertexDynamics`/`EdgeDynamics`:** user types conform directly; ND serves `ComponentDynamics` for them by a generic implementation.
   - **Why third:** it completes step 1's trait in the idiomatic form (expl. §3.2, "a user's own type"). It is the port's first idiomatic trait code, to be judged apart from interop.
   - Generic implementations are Implemented for traits without parameters; T-52 (a member that does not conform is accepted with a warning) applies. PB-1 limits what the trait can require of `pdim`.
   - The workload gains a variant: a user's model type (tier M, the P1 plan's h2).
3. **Step 4: `ODERHS` and the integrator's `f` kept** (§1.4).
   - **Why fourth:** after step 1 it buys mostly correctness (expl. §4.2): a checked `rhs!`, calls in the caller's world, the cases `AutoSpecialize` leaves unwrapped.
   - It is the first port into SciML, and needs P3's answer on DiffEqBase's pirates.
   - Tsit5 only; Rodas5P after W-29 (§1.7).
   - **It moves to step 2** if E-152's criterion 2 shows SciML's types still varying.
4. **Step 5: `IndexProvider`/`ValueProvider`** in SymbolicIndexingInterface.
   - **Why fifth:** after step 1 the provider's type is stable within the workload. The benefit (getters compiled per index shape, not per provider) shows with several providers, tier M.
   - A contract for the roughly fifty methods NetworkDynamics implements.
5. **Step 6: `Trajectory`** in SciMLBase: small; types the plotting helper and the Observables seam.
6. **Step 7: `IntegratorView`/`Callback`, and the component callbacks' `Callable`s.**
   - **Why last of the taken:** large (a 26-parameter family with field mappings; writable fields to decide; PB-9).
   - After step 1, the workload's callback types do not change with the equations.
   - Taken only if E-152's attribution, or tier M, shows callbacks compiling per network or per callback.
7. **`Positions`, then `Source`: not this round.** Each comes back only on a trigger of §6: a user data type in plots (tier M), or W-29 for `(Positions, Source{…})`.

---

## 5. Lessons for the porting guideline (B5), expected from this step

To be written there, in the present tense, once S8 confirms them:
- A trait at a library's internal calling convention can come first. The user-facing trait follows as a generic implementation of it.
- A library's own implementation as a family over its own parametric type (`FunctionDynamics`) keeps the user's functions typed inside the key and out of every other type.
- Values that decide types in hot code (dimensions that are zero or not) belong in the key, as type parameters of the implementing type.
- At a barrier from code that does not know the value's type, the other arguments travel as heap objects: one `Ref` of a pass's arguments, a container and an index.
- In a wrapped package, the package's `@compile_workload` becomes `TraitWorld.@workload` with the first bounded function.
- A plain control exists in the package itself: NetworkDynamics' vector path beyond 25 batches (`construction.jl:1–5`, `utils.jl:56–70`) is the plain function barrier. E-152 can be read against it.

---

## 6. When to revisit the traits

The user: "periodically revisit these choices". This plan's choices are revisited at each of these, and the result goes to a dated addendum of this plan or to the next step's plan:

1. **E-152's outcome:** the ranking of §4 against the attribution of what "changed" still compiles.
2. **After each later step's measurement:** whether the next step still buys what §4 says.
3. **When a Planned part lands:**
   - W-29 (tuples of traits): Rodas5P through `ODERHS`, component conditions at two signatures, `(Positions, Source{…})`;
   - forwarding for a whole family (T-7): `Positions` for live data;
   - trait casts, if they leave Optional.
4. **When a deviation or a lowering choice that a decision routes around changes:** T-5, T-38, T-37 (families' forms), T-51, L-25, the generic path for family members (lowering §9.3; PB-4).
5. **When the workload grows** (tier M or L):
   - a second vertex type, or five or more model types (the split's four, expl. §11 item 3);
   - MTK's generated components;
   - threads;
   - a new graph type;
   - a user's data type in plots.
6. **When the user decides a pushback entry or an open issue it raised** (Appendix A; open issues §1.20 on pirates).
7. **When E-153 is complete:** a benefit the traits were to bring that the facts mode already gives moves the traits' justification elsewhere.
8. **When the references change** in §3–§7 of traits, or the decision log records a change there.
9. **At the latest after three port steps,** whichever of the above has fired: a short re-read of the exploration against the pushback log, by the coordinator. A Fable re-read only if the coordinator finds a trait structurally wrong (the meta plan's rule for Fable).

---

## Appendix A. The pushback log's first entries

In the log's shape (the meta plan, "The pushback log"). The IDs are the ones the review cites; they become permanent when the log is created. Entries that need the user's decision also become open issues.

**PB-1. A value constant per implementation (an associated constant).**
- **The code:**
  - NetworkDynamics' batch passes `nothing` for `p` when `pdim` is zero, and adds the external inputs to `ins` when there are any (`coreloop.jl:182–187`, `:240`).
  - Upstream keeps both static as `StaticInt` strides in the batch's type (`utils.jl:10`, `network_structure.jl:181`).
  - The port keeps them as type parameters of `FunctionDynamics` (`PDIM`, `EXTDIM`) and declares `pdim(m)::Int`, `extdim(m)::Int`, whose results inference sees as constants per key.
- **The idiomatic form:** an associated constant: Rust's `const PDIM: usize` in a trait, Swift's `static let`. A trait would declare `pdim` as a value fixed per implementing type, which the key carries.
- **The reference:** a trait's parameters are types ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types)); the key is the receiver type and the declared fields' types ([§6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)). Nothing declares a value constant per type.
- **Blocks:** no. For a user's own type (step 3), the trait cannot require that `pdim` be constant per type; a type returning it from a field gives a `Union` at the user's function.

**PB-4. A barrier per batch: the trait object on the generic path.**
- **The code:** `compiled_for(batches[k].model)` at `run_vertex_batch!`, about three times per right-hand side in tier S (§2.3).
  - The entry is the tabled form. For a family member, the table marks the type untabled for one world (`TraitWorld/src/untyped.jl:78–89`, `:233–237`); each call pays the lookup and falls through to `enter`.
  - `enter` assembles the trait object behind a dynamic call (`entry.jl:215–223`; the family's builder by an `IdDict` lookup, `implement.jl:803–806`). The trait object is not isbits (`View`'s `o::Any`, `core.jl:68–74`), so it is boxed: one allocation per crossing.
  - The worker is then called dynamically. The port passes only heap objects there (a `Ref` per pass, the container and an index), so nothing else is boxed.
  - A family member's table entry is valid for one world; each world change adds an entry and the lookup scans them (`untyped.jl:88–96`). In a session that defines many methods (Revise), the lookup grows.
  - ND asserts zero allocations for the right-hand side (`diffusion_test.jl:111`, `construction_test.jl:540–546`) and a flat count across network sizes (`inhomogeneous_test.jl:93`). Both fail by construction.
- **The idiomatic form:** a library's own family of implementations opened by `compiled_for` at a loop over its data (guideline A12) costs what a plain function barrier with upstream's `Ref` costs: one dynamic call per crossing, no allocation per batch.
- **The reference:** at a bound, a `Compiled` value whose type the code does not know selects its code once per call ([§6.8](../reference/traits.md#68-costs-and-choosing)); a family member takes the generic path ([lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)). Nothing is said of allocations. [Open issues §4](../open-issues.md#4-runtime-and-measurements), item 35 (P2, P3).
- **Blocks:** no, unless E-152's criterion 4 fails. **For the user:** whether serving family members in the entry's table (building the views inside the callee, as for declared implementations) becomes a work item. E-152 adds the numbers.

**PB-5. The raw functions are kept beside the kept model.**
- **The code:** code that does not go through the trait reads a batch's raw `f`, `g` and feed-forward kind: sparsity detection rewrites them (`sparsity.jl:108–170`); the CUDA extension adapts them (`ext/NetworkDynamicsCUDAExt.jl:124–133`); `is_loopback` compares them (`post_utils.jl:219`). The erased batch therefore keeps `compf::Any`, `compg::Any`, `ff::FeedForwardType` beside `model`.
- **The idiomatic form:** read them back from the kept value at their own type.
- **The reference:** opening a kept value at the conforming value's own type is Open ([§7.1](../reference/traits.md#71-the-three-forms); [open issues §2](../open-issues.md#2-design), item 16). Expl. §10.3.
- **Blocks:** no.

**PB-6. GPU kernels need isbits batches.**
- **The code:** `KAExecution` passes the batch into kernels (`coreloop.jl:141–173`); the CUDA extension adapts it.
- **The idiomatic form:** the model kept in the batch for every execution style.
- **The reference:** a kept value holds a boxed object ([§7.1](../reference/traits.md#71-the-three-forms)); a copying isbits layout is an open design item ([open issues §2](../open-issues.md#2-design), item 3). Expl. §10.7.
- **Blocks:** no. `KAExecution` keeps typed batches without a model (S3, S5).

**PB-7. A closure over a trait object given to a plain package.**
- **The code:** `PolyesterExecution` loops with `Polyester.@batch for i in …` (`coreloop.jl:134`), which hands the loop's variables to `Polyester.batch`.
- **The idiomatic form:** the same loop inside the batch function, over the trait object.
- **The reference:** [§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object) allows a closure over a trait object passed to Base and forbids passing the trait object bare to an ordinary function. A closure passed to another package is not named. The definition check refuses a trait object passed bare or inside a tuple (`TraitWorld/src/checks.jl:150–158`, `:191–195`) and accepts a closure that captures one (`:101–111`).
- **Blocks:** the Polyester style in step 1 only. S7 reads `Polyester.@batch`'s expansion once and records which case it is. A question for the user if the reference's answer stays unclear.

**PB-8. Open element types against `Callable`'s constant signature.** (Expl. §10.1.)
- **The code:** component functions run at `Float64`, at several dual tags and chunk sizes, at sparsity tracers, and with `t === nothing`; SciML's `promote_f` installs dual signatures per algorithm (`DiffEqBase/src/solve.jl:1038–1060`).
- **The idiomatic form:** a function kept at an open family of signatures.
- **The reference:** `Callable`'s argument types are a constant ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)); several signatures are a tuple, Planned ([§3.7](../reference/traits.md#37-tuples-of-traits), W-29); a signature chosen by the callee is open issue 10; AD tags in a key are open issue 9.
- **Blocks:** nothing in step 1, where the operations take untyped buffers. In step 4, Rodas5P stays on SciML's path until W-29: a route around, not a pause.

**PB-9. A callback's affect whose result upstream ignores.**
- **The code:** `ComponentAffect([], [:K]) do u, p, ctx; …; p[:K] = 0; end` returns `0` (`workload_steps.jl`, step d). ND ignores the result.
- **The idiomatic form:** `Callable{Tuple{…}, Nothing}`, as TraitDifferentialEquations declares `affect!`.
- **The reference:** every call to a `Callable` checks its result ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)). A declared `Nothing` refuses code that upstream accepts; `Any` checks nothing.
- **Blocks:** no; step 7 decides. A question for the user: whether a port may declare `Nothing` and so refuse such affects.

**PB-10. Membership decided per value.** (Expl. §10.5.)
- **The code:** a static component has `f === nothing` (`coreloop.jl:243`), served in step 1 by `hasf`, whose result is constant per key; SciML's `has_jac(f) = … && f.jac !== nothing` (`scimlfunctions.jl:5770`).
- **The idiomatic form:** `ODEJacobian <: ODERHS` decided by dispatch.
- **The reference:** membership is per type ([§14](../reference/traits.md#14-membership)).
- **Blocks:** no. It limits refinement traits for records with optional fields (step 4).

---

## Appendix B. Choices for the user to review (for the meta plan's list)

The meta plan's list already holds the layout (the package wrapped whole) and the separate working trees. To add, numbered on from there:

- **One trait now** (P4): `ComponentDynamics` at NetworkDynamics' internal calling convention; the user-facing `VertexDynamics`/`EdgeDynamics` later, as a generic implementation of it.
- **Model-static values as type parameters** of the library's implementation (`FunctionDynamics{…, PDIM, EXTDIM}`), standing in for associated constants (PB-1).
- **`KAExecution` keeps typed batches** (GPU kernels need isbits data); Polyester is decided at S7 (PB-7).
- **The barrier:** upstream's own pattern (one `Ref` per pass, the batches as a vector and an index). The remaining allocation per crossing (the trait object, on the generic path for family members) is left to the user as PB-4; ND's allocation assertions are reported as expected failures.
- **The test subset** runs in environments of its own, with `testutils.jl`'s `test_execution_styles` copied without its CUDA block.
- **The criteria:** the network's type equal for both equations (a gate); at most 50 new CodeInstances of SciML and SymbolicIndexingInterface in "changed" b–e (the headline); b–e compiling at most 2 s; the steady state within 10 % + 5 ms of the wrapped package, a failure confirmed by one rerun.
