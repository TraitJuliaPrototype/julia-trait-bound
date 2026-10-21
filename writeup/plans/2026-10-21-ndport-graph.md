# The NetworkDynamics port, P4 step 2: the graph trait

Status: **proposal; P4 step 2 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md)**. Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) above all). To be reviewed by another Opus agent before work starts.

Inputs:
- the meta plan's ground rules and its list of choices for the user;
- the P2/P4 plan [`2026-10-21-ndport-traits.md`](2026-10-21-ndport-traits.md) ("the traits plan"): §1.3's starting declaration, §4's order, §6's revisit triggers; its review [`../reviews/2026-10-21-ndport-traits-plan.md`](../reviews/2026-10-21-ndport-traits-plan.md);
- the Fable exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) ("expl."), §2, §5.3, §7;
- E-151 and E-153 ([evidence §1](../design/evidence.md#1-the-guarantee), [§3](../design/evidence.md#3-first-calls-and-sessions); `ndport/README.md`; the census `ndport/logs/p3/census-P0.log`);
- the porting guideline [`../intro/porting.md`](../intro/porting.md): 0.1a, 0.2 ("an informal interface becomes a trait over its existing functions"), B5;
- the clones at `upstream`: `ndport/pkgs/Graphs.jl` (1.15.0), `NetworkLayout.jl` (0.4.11), `GraphMakie.jl` (0.6.6), `NetworkDynamics.jl` (1.3.0); TraitWorld at e9f4bfe.

File and line references are to those clones at `upstream`, and to TraitWorld at e9f4bfe. The P4 worktree `ndport/pkgs/NetworkDynamics-p4` was read only: another agent is changing it (step 1, E-152, at S1 when this was written). No Julia was run for this plan.

## Summary

- **The name is not `Graph`.** Graphs exports `Graph` already, as an alias of `SimpleGraph` (`src/Graphs.jl:75`, `:496`). A bound `g::Graph` in a module that has done `using Graphs` would be a typed method on `SimpleGraph`, silently. This plan calls the trait **`GraphInterface`** (a choice for the user, §8). "The graph trait" below means it.
- **Where it lives:** in Graphs, the owner of `AbstractGraph` and of every function the trait names. Graphs stays plain code: `@trait` and `@implement` work in any module (traits §2). Graphs gains TraitWorld as a dependency. Nothing in Graphs is compiled by facts because of it.
- **Not wrapped:** neither Graphs nor GraphMakie becomes a trait module whole. Wrapping buys the workload nothing measured, and GraphMakie's reach is Makie's plot pipeline, which E-153 shows costs the first plot 48.5 against 16.0 s when compiled by facts in the session.
- **The declaration** is narrower than the traits plan's §1.3:
  - `nv`, `ne`, `is_directed`, `has_edge`, `degree` as operations on Graphs' existing functions;
  - two new operations with concrete results, `edgelist` and `neighborlist`, in place of the open iterators `edges`, `outneighbors`, `inneighbors`, `all_neighbors`. Graphs' own reference type `Graphs.Test.GenericGraph` returns generators from those (`src/Test/Test.jl:66`, `:78`–`:82`, `:90`), so `::AbstractVector{V}` results would refuse it;
  - `V = eltype(Self)`, as in the traits plan.
- **Conformance:** one family line over `AbstractGraph`, by the existing methods, each member checked at its first use. Graphs' throwing fallbacks (`_NI`, `src/interface.jl:18`) infer `Union{}`, and TraitWorld refuses such a method as "a fallback, not an implementation" (`TraitWorld/src/implement.jl:270`).
- **The bounds, a function at a time:** three functions in NetworkDynamics (the index manager's reads of the graph, the feed-forward check, the degrees of the inverse aggregation map), then three in GraphMakie (the edge paths, the self-edge paths, the arrow and label offsets) in a trait submodule `GraphKernels`. GraphMakie's part has a stop rule on the first plot's time.
- **`Layout`: not taken.** No consumer can take it as a bound without porting GraphMakie's recipe; the workload computes one layout per plot.
- **What it buys, honestly:** correctness, little time.
  - A graph type whose edges are not `SimpleEdge`s (`GenericGraph`) builds a network, with results equal to the `SimpleGraph` network's. Upstream fails inside the index manager's field conversion, by reading (G0 confirms).
  - A graph type that does not conform is refused at the first bounded call, naming the operation and both types.
  - A new graph type still recompiles the whole stack: the `Network`'s type carries the graph's type (`network_structure.jl:88`, `:109`). Removing it needs `get_graph` to return the user's object from a kept value, open issue 16 (§3.2).
- **The order:** it stays second if E-152 meets its criterion 2 (SciML's types no longer vary with the equations). Otherwise `ODERHS` comes second, as the traits plan §4 says, and this step waits (§4.4).
- **Measured** by E-154 (§5): results exact against U; the contract on seven graph types and one broken one; a new pass on `GenericGraph`; the cost against step 1's end (P4-1).

---

## 1. Where the trait lives

### 1.1 The options

The rules: an implementation is a method, written by the trait's owner or the type's owner ([traits §10.1](../reference/traits.md#101-who-may-implement)). A family over an abstract type is declared in one line, by the members' existing methods ([§4.7](../reference/traits.md#47-families)). Bounded functions exist only in trait modules ([§2](../reference/traits.md#2-trait-modules)).

| Where | Ownership | What it costs | Decision |
|---|---|---|---|
| **Graphs, as plain code** (a new file) | owns the trait, `AbstractGraph` and every function named; implements for foreign subtypes as the trait's owner | TraitWorld becomes a dependency of Graphs. Plain users of Graphs load TraitWorld (in E-151, the port's environment loads in 6.2–6.3 s against 5.4–5.6 s upstream; TraitWorld is part of that difference). Graphs, ND, GraphMakie and NetworkLayout's extension precompile again in `depot-p4`, once | **taken** |
| Graphs as a trait module, whole | as above | Graphs' code (1,923 methods, no pirates by the census) is compiled by facts. Graphs has no precompile workload, so `watts_strogatz` and every Graphs call from plain code is compiled by facts in the session. It protects nothing the workload loses: in E-153's order B, no Graphs code is among the losses | not taken |
| An extension of Graphs, triggered by TraitWorld | the extension counts as Graphs | refused: an implementation in an extension must mention each trigger, and TraitWorld owns neither the trait nor a type it names (§10.1). Consumers would also reach the trait only through `Base.get_extension` | not possible (PB-13) |
| A small package of its own, holding the trait and the family | owns the trait; implements for `AbstractGraph` subtypes by their existing methods | a second home for Graphs' concept; graph authors look in Graphs. It is not an interface package of the rejected kind (no declared calls, no sealing; [alternatives](../design/alternatives.md)), only a split owner | not taken |
| NetworkDynamics | owns the trait | GraphMakie would depend on NetworkDynamics for it | not taken |
| GraphMakie | owns the trait | the same, the other way round | not taken |

### 1.2 Wrapping Graphs or GraphMakie: what it would cost

- **Graphs, whole:** see the table. Nothing to gain for the workload; an unmeasured first-call cost on every Graphs function a plain caller reaches. Not taken.
- **GraphMakie, whole:**
  - two pirates by the letter: `Makie.symbol_to_plot(::Val{:GraphPlot})` and `(::Val{:EdgePlot})`, made by Makie's `@recipe` (census). A trait module refuses pirates at their definition ([§10.2](../reference/traits.md#102-pirates)). A macro's methods are not always checked (T-56), so whether they are refused depends on the order. Either way they would move to a plain module first;
  - the recipe's `plot!` and its compute-graph closures become trait code. What they reach is Makie's pipeline. GraphMakie has no precompile workload, so all of it is compiled by facts in the session. The closest measurement: E-153's W, where the workload's own module is a trait module and the first plot takes 48.5 against 16.0 s ([evidence §3](../design/evidence.md#3-first-calls-and-sessions));
  - what it would protect: GraphMakie's code against later loads. In order B the plotting packages load after the simulation, so their code is not compiled yet when the loads happen; nothing is measured to protect.
  - Not taken.
- **GraphMakie, partly:** one trait submodule holding only the helpers that take the graph (§2.6). Its reach is narrower: GraphMakie's path construction (`beziercurves.jl`) and reads of the plot's attributes. Measured by E-154's criterion 3, with a stop rule.

### 1.3 Where the code lives

- **Graphs:** a worktree `ndport/pkgs/Graphs-p4` on a branch `trait-port-p4` from `upstream`. Today the main clone is on `trait-port` and is shared by `env_port`, `env_p3` and `env_p4` (their `[sources]`). The worktree keeps P0 and N on upstream's code (the meta plan's choice 8). `env_p4`'s and `env_ndtest_p4`'s `[sources]` point Graphs at the worktree.
- **GraphMakie:** the same, `ndport/pkgs/GraphMakie-p4`, branch `trait-port-p4`.
- **NetworkDynamics:** the P4 worktree, on `trait-port`, continuing from E-152's last commit (S8). Step 2 starts only after step 1's agent has finished there.
- **TraitWorld:** a `[deps]` entry in Graphs' and GraphMakie's `Project.toml`; the path comes from the environment's `[sources]`, as for NetworkDynamics in the P4 worktree.
- **The depot:** `ndport/depot-p4`. After G1, Graphs' dependents in `env_p4` precompile again: NetworkDynamics, GraphMakie and NetworkLayout's Graphs extension (from `env_p4/Manifest.toml`), through the lock.

---

## 2. The declaration

### 2.1 What the consumers read from a user's graph

| Consumer | Where (at `upstream`) | Reads | When |
|---|---|---|---|
| ND: `Network(g, …)` | `construction.jl:58`–`:64` | `vertices(g)` and `edges(g)` to count, `nv`, `ne` | construction |
| ND: the feed-forward check | `construction.jl:66`–`:96` | `all_neighbors(g, i)`, `collect(edges(g))[eidx]`, `degree(g, v)` | construction, only with feed-forward vertices (`rhs_check.jl`'s `ff` network) |
| ND: the index manager | `network_structure.jl:32`–`:55` | `nv`, `ne`, `collect(edges(g))` into the field `edgevec::Vector{SimpleEdge{Int64}}` (`:3`, `:37`) | construction |
| ND: the inverse aggregation map | `aggregators.jl:204`–`:207` | `degree(g)`, as capacities | construction, Threaded and Polyester aggregators |
| ND: other reads of the stored graph | `gbufs.jl:14`, `:46`–`:47`; `post_utils.jl:248`; `show.jl:5`–`:22`; `network_structure.jl:139`–`:140` | `nv`, `ne` | construction, printing, `nv(nw)` |
| GraphMakie: `find_edge_paths` | `recipes.jl:599`–`:655` | `edges` with `src`/`dst`, `ne`, `is_directed`, `has_edge` | each resolve of the edge paths |
| GraphMakie: `selfedge_path` | `recipes.jl:664`, `:715` | `all_neighbors(g, v)` | per self-edge |
| GraphMakie: `find_start_end_shift` | `recipes.jl:887`, `:910` | `ne`, `edges` with `src`/`dst` | each resolve |
| GraphMakie: `elabels_distance_offset` | `recipes.jl:566` | `ne` | with edge labels |
| GraphMakie: the recipe's closures | `recipes.jl:221`–`:231`, `:317`–`:318`, `:366`–`:543`; `utils.jl:22`–`:43`, `:80`, `:97` | `nv`, `layout(graph)`, `is_directed`, `ne`; `getedgekeys` by SimpleTraits' `IsDirected` | plain Makie code; not changed (§2.6) |
| NetworkLayout | `ext/NetworkLayoutGraphsExt.jl` | `adjacency_matrix(g)` | per layout; not changed |

### 2.2 The declaration

A new file `src/interface_trait.jl` in Graphs, included after `using .SimpleGraphs` and the aliases (`src/Graphs.jl:490`–`:503`), so that `degree`, `all_neighbors` (`core.jl`) and `SimpleEdge` exist.

```julia
using TraitWorld: @trait, @implement, @default_with_dynamic_self

"What generic code reads from a graph: vertices 1:nv, edges as source and destination."
@trait GraphInterface{V <: Integer} begin
    @default_with_dynamic_self                     # kept only if G0 (c) shows it stays typed (§2.4)
    V = eltype(Self)                               # eltype(::Type{<:AbstractGraph{T}}) = T, interface.jl:125
    nv(g::GraphInterface{V})::V                    # SimpleGraphs.jl:125 returns T
    ne(g::GraphInterface)::Int
    is_directed(g::GraphInterface)::Bool           # interface.jl:228, by the type's method
    has_edge(g::GraphInterface{V}, s::V, d::V)::Bool
    degree(g::GraphInterface{V}, v::V)::Int        # core.jl:158, generic over AbstractGraph
    edgelist(g::GraphInterface{V})::Vector{SimpleEdge{V}}        # new: the edges in `edges(g)`'s order
    neighborlist(g::GraphInterface{V}, v::V)::Vector{V}          # new: `all_neighbors(g, v)`, collected
end
edgelist(g::AbstractGraph{T}) where {T} = SimpleEdge{T}[SimpleEdge{T}(src(e), dst(e)) for e in edges(g)]
neighborlist(g::AbstractGraph{T}, v::Integer) where {T} = collect(T, all_neighbors(g, v))
@implement GraphInterface G where {G <: AbstractGraph}      # every subtype, by its existing methods
```

- `nv`, `ne`, `is_directed`, `has_edge`, `degree` are written unqualified because the file is inside Graphs: they are Graphs' functions, not new ones ([§3.1](../reference/traits.md#31-operations)).
- `edgelist` and `neighborlist` are new functions of Graphs, with one method each for `AbstractGraph`. Graphs owns both the functions and the type.
- `GraphInterface` and the two functions are exported or declared `public`: a choice at G1, recorded.

### 2.3 Why this shape

- **`V` is the vertex type** (expl. §2.2). `nv` returns it (`SimpleGraphs.jl:125`), so a declared `Int` would refuse `SimpleGraph{Int32}` at its first use.
- **The open iterators.** `edges`, `vertices`, `outneighbors`, `inneighbors` and `all_neighbors` return whatever the graph type returns: a `SimpleEdgeIter`, a `FrozenVector` (`SimpleGraphs.jl:157`–`:158`), a `Vector` (`simpledigraph.jl:620`), or a generator (`Test/Test.jl`). An operation must declare its result ([§3.1](../reference/traits.md#31-operations)), and the member's method must infer to it ([§4.9](../reference/traits.md#49-checks-at-the-declaration)).
  - `::AbstractVector{V}` refuses `GenericGraph`, Graphs' own type for testing "any `AbstractGraph`".
  - `::Iterable{V}` (BaseTraits) does not help: a generator is not a member of `Iterable` (BaseTraits implements it for arrays and dictionaries, `TraitWorld/src/BaseTraits.jl:84`–`:91`), and its `eltype` is `Any`.
  - An associated iterator type needs a type function to define it, or a value stated per implementation, which a family over an abstract type cannot state (T-37; equations between type functions are not offered, [§3.4](../reference/traits.md#34-parameters-and-associated-types)).
  - So the trait names what the consumers need with concrete results: the edge list and the neighbour list, each a copy. The typed comprehension fixes the result type whatever `edges(g)` yields. Cost: one copy per call, at construction or per resolve of a plot; 40 edges in tier S. Pushback PB-11.
- **Left out:** `vertices`, `outneighbors`, `inneighbors`, `has_vertex`, `edgetype`, `zero`. No consumer in ND or GraphMakie needs them through the trait. ND already takes the vertices to be `1:nv(g)` (`construction.jl:170`; `network_structure.jl:35`), so its two counting loops (`construction.jl:58`–`:59`) can use `nv` and `ne`; they stay plain calls in this step.
- **`is_directed` and `degree`** have concrete results at every member: `is_directed(::G) = is_directed(G)` reaches the type's method; `degree(g, v)` is `length` of the neighbours (`core.jl:118`, `:158`–`:163`).
- **The edges are `SimpleEdge{V}`,** the type ND's index manager stores. ND converts to `SimpleEdge{Int}` itself (§3, G2).
- **Throwing fallbacks.** Graphs' interface throws `NotImplementedError` for a function a graph type does not implement (`interface.jl:140`, `:157`, `:229`, `:275`). With the family "by existing methods" those fallbacks are methods. The member check infers each operation at the member's concrete argument types, and refuses a method that infers `Union{}` (`implement.jl:270`–`:271`). Every operation here has concrete declared arguments at a member (`V` is concrete), so the check reaches inference rather than the method-exists test it uses for abstract arguments (`implement.jl:254`–`:263`).

### 2.4 `Dynamic` or `Compiled`: the open parameter

- **The traits plan's choice** is `@default_with_dynamic_self`: a graph from outside enters `Dynamic`, and the helpers compile once, whatever the graph type.
- **The gap:** at a bound that leaves `V` open (`g::GraphInterface`), a `Dynamic` value's operations whose results name `V` return `Any` (`_erased_ft`, `TraitWorld/src/attributes.jl:116`; the erased key marks the parameter open, `core.jl:928`–`:934`). The code after them is not fully typed. The reference requires a `Dynamic` **annotation** to fix such parameters ([§5.1](../reference/traits.md#51-bounds); `_check_dynamic_params`, `attributes.jl:272`, applied only to annotations, `trait_module.jl:482`, `:507`). It says nothing of a trait's default at an open bound.
- **What G0 (c) decides,** on a probe trait in a scratch module (§3):
  1. If `g::GraphInterface{V} where {V}` gives a `Dynamic` trait object typed at the caller's `V` (`fully_typed` reports no site after `nv` or `edgelist`), the bounds use that form and the trait keeps the default. A new graph type with the same `V` then compiles none of the bounded functions.
  2. If not, the trait declares no default. The first-seen rule makes the graph `Compiled` where the caller knows its type, which is everywhere here (ND's constructor, GraphMakie's closures). The bounded functions are then compiled per graph type, as today, and fully typed.
- Either way the result is recorded as PB-12. The design is not changed.

### 2.5 How types conform

One line: `@implement GraphInterface G where {G <: AbstractGraph}` ([§4.7](../reference/traits.md#47-families), the variable form; T-38 avoided). Each member is checked at its first use, by inference of the eight operations.

Expected, checked by `scripts/graph_check.jl` (§3):

| Type | Expected | Why |
|---|---|---|
| `SimpleGraph{Int64}` (the workload's) | conforms | |
| `SimpleDiGraph{Int64}` | conforms | `all_neighbors` by its own method |
| `SimpleGraph{Int32}` | conforms, `V = Int32` | ND may still fail later on `Int32` ranges; reported, not claimed |
| `Graphs.Test.GenericGraph{Int64}`, `GenericDiGraph{Int64}` | conform | generators collected by `edgelist` and `neighborlist` |
| `Graphs.ReverseView`, `Graphs.UndirectedView` of a `SimpleDiGraph` | conform | forwarding methods (`wrappedGraphs/graphviews.jl`) |
| a test type `NoEdges <: AbstractGraph{Int}` without `ne` | refused at first use: `ImplementError` naming `ne` "always throws (inferred `Union{}`)" | Graphs' fallback |

### 2.6 Where the bounds go, and what stays plain

- **NetworkDynamics** (already a trait module, whole): three new bounded functions in `src/network_structure.jl` and `src/construction.jl`, called from the existing plain-typed code. `Network(g::AbstractGraph, …)` keeps its signature. A bound there would make `g` a trait object, which code may not store bare ([§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object)); the index manager stores the user's graph for `get_graph`.
- **GraphMakie:** a trait submodule `@trait_module module GraphKernels … end` in a new file `src/kernels.jl`, included last (after `utils.jl`, `src/GraphMakie.jl:14`–`:17`), since the helpers use `getattr` and the path types. It holds `find_edge_paths`, both `selfedge_path` methods, both `find_start_end_shift` methods and `elabels_distance_offset`, moved there with `g::GraphInterface{V}` and their bodies reading the graph through the operations. `selfedge_path` takes the trait object from `find_edge_paths`, so it must be in the same trait module ([§5.4](../reference/traits.md#54-internal-functions)). The recipe's closures (`recipes.jl:314`, `:328`, `:527`) call `GraphKernels.<name>`.
- **Plain, unchanged:** the recipe's closures and `plot!`; `prep_vertex_attributes`, `prep_edge_attributes`, `getedgekeys` (typed on `AbstractGraph`, the last by SimpleTraits); `layout(graph)` and NetworkLayout; ND's direct `nv`/`ne` on the stored graph (§2.1, last ND row); ND's implicit graph construction (`construction.jl:312`–`:323`), which builds its own `SimpleDiGraph`.

### 2.7 Each construct against TraitWorld today

| Construct | Where | Status | Deviations met |
|---|---|---|---|
| `@trait` and `@implement` in a plain package | [§2](../reference/traits.md#2-trait-modules) | Implemented | none known; Graphs is the port's first plain package to declare a trait |
| a parameter bound and an equation `V = eltype(Self)` | [§3.4](../reference/traits.md#34-parameters-and-associated-types) | Implemented | none; BaseTraits' `Iterable` has the same shape |
| operations on the package's existing functions | [§3.1](../reference/traits.md#31-operations) | Implemented | none |
| a family over an abstract type, variable form, by existing methods | [§4.7](../reference/traits.md#47-families) | Implemented | T-38 avoided; T-5 not met (no block) |
| the dynamic default at an open bound | [§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations) | Implemented | the results named by an open parameter are `Any` (§2.4; PB-12) |
| a bound with a `where` variable and ordinary `where` variables | [§5.1](../reference/traits.md#51-bounds) | Implemented | the attribute of a `Dynamic` value at `GraphInterface{V} where {V}`: G0 (c) |
| a trait submodule inside a plain package | [§2](../reference/traits.md#2-trait-modules) | Implemented | L-3 not met: new functions of the submodule |
| internal functions taking the trait object | [§5.4](../reference/traits.md#54-internal-functions) | Implemented | none |

### 2.8 `Layout`: not taken

- **No consumer can take it as a bound** without porting GraphMakie's recipe. The `layout` attribute is a layout, a function or a vector (`recipes.jl:222`–`:230`), read in a compute-graph closure. A bounded closure is Planned (§5.8).
- **It needs a change in NetworkLayout:** `dim` and `ptype` are defined on instances (`NetworkLayout.jl:36`–`:37`); an equation `Dim = dim(Self)` needs them on the type. One line each, but a change with no consumer.
- **No benefit for the workload:** one `Spring` layout, computed once per plot.
- **Revisit** when a user's own layout type enters the workload, or when GraphMakie's recipe is ported.

---

## 3. The changes, a function at a time

Each row is one commit. The checks:
- (P) the changed packages and their dependents precompile in `env_p4`, which runs the trait modules' definition checks;
- (C) `scripts/graph_check.jl` (new): the member table of §2.5; `Network` built on each conforming type in tier S's shape, its `nv`, `ne`, `edgevec` and the `rhs_check.jl` hash of `du` against the `SimpleGraph` network's; the broken type's error and the frame it is raised in;
- (R) `rhs_check.jl`: every hash equal to U's (its `ff` network reaches the feed-forward check; its Threaded and Polyester styles reach the inverse aggregation map);
- (W) the full workload in P, one run, `compare_digests.py --exact` against E-151's U log;
- (T) ND's test subset (`nd_tests.sh`); (GT) Graphs' tests `simplegraphs/runtests`, `interface`, `core`, `wrappedGraphs/graphviews` through a driver as `test/runtests.jl:69`–`:76` includes them; (GM) GraphMakie's `test/runtests.jl` without its reference images.

| # | File:line (at `upstream`) | Function | Change | Check |
|---|---|---|---|---|
| G0 | `ndport/scripts/graph_probe.jl`, `graph_check.jl` (new); E-154 registered | — | In `env_port` (the clones at `upstream`, TraitWorld loaded), a few minutes: **(a)** today's behaviour: `Network` on `GenericGraph(g)` and `SimpleGraph{Int32}(g)` with tier S's models, the error and its frame; **(b)** the trait of §2.2 declared in a scratch module (it owns the trait, so the family over `AbstractGraph` is allowed), the member table of §2.5 by calling a bounded probe; **(c)** `fully_typed` of a bounded probe that reads `nv`, `edgelist` and `has_edge`, at the three bounds `GraphInterface`, `GraphInterface{V} where {V}`, `GraphInterface{Int}`, called from a function that knows the graph's type, with and without the default: decides §2.4; **(d)** optional, with CairoMakie: `graphplot` on `GenericGraph`, the figure built and not saved | the logs, `ndport/logs/p4-2/g0-*.log` |
| G1 | Graphs: `src/interface_trait.jl` (new), its include in `src/Graphs.jl`; `Project.toml` | `GraphInterface`, `edgelist`, `neighborlist`, the family | §2.2, with G0 (c)'s answer; the worktree and `env_p4`'s `[sources]` (§1.3) | P, GT, C (members only) |
| G2 | ND: `src/network_structure.jl:32`–`:38` | `graph_index(g::GraphInterface{V})` (new); `IndexManager`'s inner constructor | `graph_index` returns `(; nv = Int(nv(g)), ne = ne(g), edges = SimpleEdge{Int}.(edgelist(g)))`; the constructor reads these instead of `nv(g)`, `ne(g)`, `collect(edges(g))` | P, C, R, W |
| G3 | ND: `src/construction.jl:66`–`:96` | `check_feedforward_leaves(g::GraphInterface{V}, vertexm, edgem)` (new) | the block moved into the function: `neighborlist` for `all_neighbors`, `edgelist(g)[eidx]` for `collect(edges(g))[eidx]`, `degree` as is; the same errors and messages | P, C, R (the `ff` network), T |
| G4 | ND: `src/aggregators.jl:205` | `degrees(g::GraphInterface{V})` (new); `_inv_aggregation_map` | `[degree(g, v) for v in one(V):nv(g)]` for `Graphs.degree(im.g)` | P, R (Threaded, Polyester), W, T |
| G5 | GraphMakie: `src/kernels.jl` (new), `src/GraphMakie.jl`, `Project.toml`; `recipes.jl:599`–`:722`, `:314` | `GraphKernels.find_edge_paths`, `selfedge_path` (both) | moved (§2.6): `enumerate(edgelist(g))`, `map(edgelist(g))`, `neighborlist(g, v)`; the rest unchanged | P, W (the first plot against the stop rule, §4.2), GM |
| G6 | GraphMakie: `recipes.jl:566`, `:887`–`:982`, `:328`, `:527` | `GraphKernels.find_start_end_shift` (both), `elabels_distance_offset` | moved likewise | P, W, GM |
| G7 | `ndport/scripts/workload.jl`, `workload_steps.jl`, `run_workload.sh` | — | `NDW_GRAPHTYPE=1` adds a pass `graphtype` after `changed`: steps b–f on `Graphs.Test.generic_graph(g)` of the same Watts–Strogatz graph, with `swing!`. `step_b` takes the graph as a keyword. A step that throws prints `D graphtype <step> error=<type>` and ends the pass | the pass in U (the before) and in P |
| G8 | `ndport/` | — | E-154's runs (§4.2); the README's dated table; the guideline's B5 lessons (§7); the pushback entries (§6); commits | §4 |

- **Exact equality is expected at every row.** `edgelist` and `neighborlist` give the same elements in the same order as `edges` and `all_neighbors`; the arithmetic is unchanged.
- **G5–G6 are reverted** if the stop rule fires (§4.3). G1–G4 stand alone.

### 3.1 What does not change

- **The graph's type stays in the `Network`'s type:** `IndexManager{G}` (`network_structure.jl:1`), `Network{…, G, …}` (`:88`, `:109`), `NetworkLayer` (`construction.jl:214`), `NaiveAggregator` (`aggregators.jl:24`).
- **`get_graph(nw)`** returns the user's graph, as today (`network_structure.jl:148`); the workload reads it (`workload_steps.jl:56`, `:64`, `:87`; `workload_plot.jl:11`, `:37`).
- **Public signatures** of ND and GraphMakie. `graphplot` still accepts what it accepts today, and `Network` every `AbstractGraph` it accepts today.

### 3.2 Not this step: erasing the graph's type

- With the graph kept as `Kept{GraphInterface}` in the index manager, the `Network`'s type would not change with the graph's type, and a new graph type would compile only the bounded functions.
- But `get_graph` must then return the user's object, read back from a kept value. That is open: [open issues §2](../open-issues.md#2-design), item 16; the traits plan's PB-5 meets the same.
- A plain `g::Any` field would erase the type without traits, so the trait is not what this would test.
- Revisit trigger: a new graph type in tier M, or open issue 16 decided (§9).

---

## 4. What it buys, measured cheaply

### 4.1 The expectation, honestly

- **Time: almost nothing for tier S.** One `SimpleGraph{Int64}`, read at construction. The bounded functions replace a few hundred microseconds of construction-time reads.
- **A new graph type:** works where upstream fails (by reading: `GenericEdge` cannot be converted to `SimpleEdge{Int64}` in the index manager's `new`, `network_structure.jl:37`–`:38`). But it recompiles the stack about as much as new equations do upstream (15.6–16.0 s, E-151), because the `Network`'s type carries it (§3.1). The pass makes that visible.
- **What the contract adds over a plain fix:** a refusal at the first bounded call, naming the operation, the type and the inferred result, before ND's construction runs into a conversion error. Graphs' own `NotImplementedError` is readable already where a function is missing; the trait adds the case where a method exists and returns the wrong thing.
- **The value for the design** is larger than for the workload:
  - the first family over an abstract type that foreign packages subtype, with real consumers;
  - a trait declared in a plain package that stays plain;
  - the first trait submodule in a plain package (GraphMakie);
  - the open-iterator problem and the dynamic default with an associated type (PB-11, PB-12).

### 4.2 Settings and criteria

**Settings:**
- **U:** upstream, the reference for results (E-151's U log), and one run with `NDW_GRAPHTYPE=1` for the before.
- **P4-1:** the P4 worktree at E-152's end (S8), `env_p4`: the before of this step's own effect. E-152's two runs.
- **P4-2:** after G8, `env_p4`, `depot-p4`; two runs with `NDW_GRAPHTYPE=1`; one attribution run (`NDW_DIAG=1`).

Strict mode off, the load order fixed (the P1 plan §2.3), julia-1.13 at the build E-152 used, TraitWorld e9f4bfe or the commit E-152 used. With n = 2 the numbers are indicative. **What they measure:** library trait code (ND's and GraphMakie's bounded functions) reading plain graph types through their existing methods: interop, not idiomatic trait code.

| # | Criterion | Before | Pass when |
|---|---|---|---|
| 0 | Results | P4-1 equal to U exactly | each P4-2 log `--exact` against U for the four passes; every `rhs_check.jl` hash equal to U's. A gate |
| 1 | The contract | G0 (a): the errors upstream gives | `graph_check.jl`: the six conforming types of §2.5 conform; the broken type is refused with `ImplementError` naming `ne`, raised from the first bounded call, not from `IndexManager`'s `new` |
| 2 | A graph type upstream refuses | U's `graphtype` pass: b fails (G0 (a) names the error) | P4-2's `graphtype` pass runs b–f; each digest equals the same step's in `first` |
| 3 | No cost | P4-1, per step | "again": each step, the minimum of two runs, at most 1.10 × P4-1's + 5 ms. "first": step b at most P4-1's + 0.5 s; **step f at most P4-1's + 2 s (the stop rule for G5–G6)**; the session's four passes at most P4-1's + 3 s. A failure is confirmed by one more run |
| 4 | What a new graph type compiles | — (U fails) | reported, not a gate: the `graphtype` pass's compile time per step and its new CodeInstances by module; the share of `GraphKernels` and `graph_index` |
| 5 | Tests | T at S8; GT and GM at `upstream` | the same passes |

### 4.3 What a failure changes

- **Criterion 0:** a port bug, fixed first.
- **Criterion 1:**
  - a type of §2.5 refused that should conform: the declaration is wrong for it; the result type is fixed in the declaration, and the case recorded;
  - the broken type accepted: a disagreement between TraitWorld and §4.9, reported to whoever owns the reference (a T- row; CLAUDE.md, "Precedence").
- **Criterion 3, step f over the stop rule, confirmed:** G5–G6 are reverted; GraphMakie stays plain; PB-14 records the numbers. A `TraitWorld.@workload` in `GraphKernels` that resolves the helpers on a small graph is the next thing to try, only if the user asks.
- **Criterion 3, step b over its bound:** the member check's cost at first use in a session (inference of eight operations) is the suspect; recorded for [open issues §4](../open-issues.md#4-runtime-and-measurements), not fixed here.
- **Criterion 3, "again":** not expected (no bounded function runs after construction except on plot resolves); a failure is read with the attribution run.

### 4.4 Second, or `ODERHS` and `IndexProvider` first?

- **The traits plan's trigger** (§4 item 3, §6 item 1): `ODERHS` moves to second if E-152's criterion 2 shows SciML's types still varying with the equations. That stands. This step starts only when E-152's outcome is in.
- **If E-152 meets criterion 2:** each remaining step buys mostly correctness after step 1:
  - `ODERHS`: a checked `rhs!`, calls in the caller's world (the traits plan §4 item 3); it needs P3's answer on DiffEqBase's pirates and routes Rodas5P around W-29;
  - `IndexProvider`/`ValueProvider`: pays only with several providers in a session (tier M);
  - the graph trait: correctness, and the design tests of §4.1.
- **Then the graph trait stays second.** It is the cheapest (six commits, three packages, no Planned part, no pirates, no SciML question), it does not touch the files step 1 changed at the same lines, and its pushback (PB-11, PB-12) is about associated types, which `ODERHS{T, P}` and `ValueProvider{U, P}` meet next.
- **If E-152 misses criterion 2:** `ODERHS` comes second; this plan waits and is re-read against E-152's attribution before it starts.

---

## 5. The registry row

To be added to `writeup/record/experiments.md` §11 with status running before G0's first run.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-154 | W-32 P4, step 2: Graphs' informal `AbstractGraph` interface as a trait, `GraphInterface{V}`, declared in Graphs (plain) with a family over `AbstractGraph`; NetworkDynamics' construction-time reads of the graph and GraphMakie's edge-path helpers bounded by it ([the graph plan](../plans/2026-10-21-ndport-graph.md)). Tier S plus a `graphtype` pass on `Graphs.Test.GenericGraph`; product setting, strict mode off, fixed load order; P4-2 two runs against U (results) and P4-1 (E-152's end, the step's own effect). (0) Are the digests and the right-hand-side checks exactly equal to U? (1) Do `SimpleGraph{Int64}`, `SimpleDiGraph`, `SimpleGraph{Int32}`, `GenericGraph`, `GenericDiGraph`, `ReverseView` and `UndirectedView` conform at first use, and is a graph type without `ne` refused at the first bounded call, naming `ne`? (2) Does a network on `GenericGraph` build and give the `SimpleGraph` network's results, where upstream fails? (3) What does the step cost: the steady state against P4-1 (10 % + 5 ms), the first network (+0.5 s), the first plot (+2 s, the stop rule for GraphMakie's trait submodule)? (4) What does a new graph type compile, by module? (5) Does a `Dynamic` value at `GraphInterface{V} where {V}` stay typed (G0 (c))? Measures library trait code reading plain graph types (interop). **Would change the plan:** an exact difference (a port bug); a type of the table refused, or the broken type accepted (the declaration, or a TraitWorld disagreement with traits §4.9); the first plot over its bound, confirmed (GraphMakie's part reverted; PB-14); (5) negative (the trait declares no default; PB-12). | registered (2026-10-21) | `ndport/` (its own repository): `scripts/graph_probe.jl`, `graph_check.jl`, `graphs_tests.jl`, `rhs_check.jl`, `nd_tests.sh`, `run_workload.sh` (`NDW_GRAPHTYPE`); `logs/p4-2/`; worktrees `pkgs/Graphs-p4`, `pkgs/GraphMakie-p4` (branch `trait-port-p4`), `pkgs/NetworkDynamics-p4` | — | `ndport/README.md`; [the graph plan](../plans/2026-10-21-ndport-graph.md) |

When E-154 is done, its outcome and an evidence row in `writeup/design/evidence.md` are written in one commit (CLAUDE.md, rule 1).

---

## 6. Expected pushback entries

In the log's shape ([`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md)). Numbered on from the traits plan's Appendix A (PB-1 to PB-10); the IDs become permanent when written to the log. Each is written there once E-154 confirms it.

**PB-11. An informal interface whose functions return open iterators.**
- **The code:** Graphs' `edges`, `vertices`, `outneighbors`, `inneighbors`, `all_neighbors` return what the graph type returns; Graphs' own `GenericGraph` returns generators (`src/Test/Test.jl:66`–`:91`).
- **The idiomatic form:** an associated iterator type with a declared item type (Rust's `type Edges: Iterator<Item = Self::Edge>`; Swift's `associatedtype` with a `where` clause on its `Element`).
- **The reference:** every operation declares its result ([§3.1](../reference/traits.md#31-operations)), checked by inference at each member ([§4.9](../reference/traits.md#49-checks-at-the-declaration)). An associated type needs an equation of `Self` through a type function, or a stated value, which a family over an abstract type cannot state per member (T-37). A generator is not an `Iterable` member, and its `eltype` is `Any`.
- **What it costs:** two new functions in Graphs (`edgelist`, `neighborlist`), a copy per call. Construction-time and per plot resolve: small here, linear in the edges.
- **Blocks:** no.

**PB-12. A trait's dynamic default with an associated type, at an open bound.**
- **The code:** `@default_with_dynamic_self` on `GraphInterface{V}`, and the bound `g::GraphInterface` in ND and GraphMakie.
- **The idiomatic form:** Rust requires the associated type to be named in a trait object, `dyn Graph<V = u32>`, or the function to be generic over it.
- **The reference:** a `Dynamic` annotation must fix every parameter its operations' results use ([§5.1](../reference/traits.md#51-bounds)). Nothing is said of a trait's default at an open bound ([§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations)). TraitWorld accepts it and types those results `Any` (§2.4).
- **What it costs:** depends on G0 (c). Either the bounds name `V` as a `where` variable and stay typed, or the trait gives up its default and compiles per graph type.
- **Blocks:** no. **For the user** (an open issue if the reference's silence is confirmed): whether a trait's default at an open bound fixes the parameters per call, is refused as the annotation is, or is accepted with untyped results.

**PB-13. The owner of an informal interface declares the trait in its plain package.**
- **The code:** Graphs gains TraitWorld as a hard dependency for one trait and one family line.
- **The idiomatic form:** an optional dependency (a Cargo feature; a Julia package extension).
- **The reference:** an implementation in an extension must mention each trigger, and each trigger must own the trait or a type it names ([§10.1](../reference/traits.md#101-who-may-implement)). TraitWorld, the natural trigger, owns neither. The trait's name would also live only in the extension's module.
- **What it costs:** plain users of Graphs load TraitWorld.
- **Blocks:** no. **For the user:** whether a package may declare its trait and family in an extension triggered by TraitWorld.

**PB-14. A bound on one helper needs a trait module, and the module's reach is compiled by facts.**
- **The code:** GraphMakie's edge-path helpers, moved into `GraphKernels` only so that they can take a bound.
- **The idiomatic form:** a generic function in a plain package (Rust and Swift allow a bound on any function).
- **The reference:** bounded functions exist only in trait modules, and what trait code reaches is compiled by facts ([§2](../reference/traits.md#2-trait-modules); [facts §6.2](../reference/facts.md#the-mode-rule)).
- **What it costs:** E-154's criterion 3 (step f).
- **Blocks:** only if the stop rule fires; then GraphMakie stays plain.

Not pushback, for the guideline: a trait whose natural name is already an exported type or alias in scope (`Graphs.Graph`) is a typed method where it is meant as a bound, and nothing warns (§7).

---

## 7. Lessons for the porting guideline (B5), expected from this step

To be written there, in the present tense, once G8 confirms them:
- **Check the trait's name against the package's exports.** `Graphs.Graph` is `SimpleGraph`. A bound spelled with a type's name is a typed method.
- **Declare an informal interface's trait in its owner, as plain code.** Graphs stays plain; only the consumers' bounded functions are trait code.
- **Test the declaration against the package's own generic test types** (`Graphs.Test.GenericGraph`): they show which results are open.
- **An open iterator becomes an operation with a concrete result,** a copy with a declared element type.
- **Bound the readers, not the front end,** where the front end stores the user's object: `Network(g::AbstractGraph, …)` keeps its type and calls bounded readers.
- **A trait submodule in a plain package** gives one helper a bound; measure the first call of what it reaches.

---

## 8. Choices for the user to review (for the meta plan's list)

Numbered on from the meta plan's 14:

15. **The trait's name:** `GraphInterface`. `Graph` is Graphs' alias of `SimpleGraph`. Alternatives: `GraphLike`, `IsGraph` (SimpleTraits' style, as `IsDirected`).
16. **Graphs declares the trait as plain code,** with TraitWorld as a hard dependency (PB-13). Graphs and GraphMakie are not wrapped whole.
17. **Two new operations** with concrete results, `edgelist` and `neighborlist`, instead of the open iterators; `vertices`, `outneighbors`, `inneighbors` left out until a consumer needs them (PB-11).
18. **`Layout` not taken** this round (§2.8).
19. **GraphMakie's helpers in a trait submodule,** with a stop rule: the first plot at most 2 s slower than P4-1 (PB-14).
20. **The graph's type stays in the `Network`'s type;** erasing it waits for open issue 16 (§3.2).
21. **The dynamic default kept or dropped by G0 (c)** (§2.4, PB-12).
22. **The order:** second if E-152 meets its criterion 2, else after `ODERHS` (§4.4).

---

## 9. When to revisit

The traits plan's §6 applies. In addition:
- **G0 (c)'s answer,** at once: §2.4's form, and PB-12's text.
- **A new graph type in the workload** (tier M), or open issue 16 decided: erasing the graph's type (§3.2).
- **A user's layout type,** or GraphMakie's recipe ported: `Layout` (§2.8).
- **A consumer of the left-out operations** (`outneighbors`, `vertices`): their declaration, by PB-11's pattern.
- **The user's answer on PB-12 or PB-13.**
