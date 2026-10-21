# The NetworkDynamics port, P4 step 2: the graph trait

Status: **adopted; P4 step 2 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md)** (revised 2026-10-21 after the review [`../reviews/2026-10-21-ndport-graph-plan.md`](../reviews/2026-10-21-ndport-graph-plan.md); the coordinator accepted every finding). Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) above all).

Inputs:
- the meta plan's ground rules, its choices 1–16 (choice 16: the port continues around open issue 48, now closed);
- the P2/P4 plan [`2026-10-21-ndport-traits.md`](2026-10-21-ndport-traits.md) ("the traits plan"): §1.3's starting declaration, §4's order, §6's revisit triggers;
- the Fable exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) ("expl."), §2, §5.3, §7;
- E-151, E-152 and E-153 ([evidence §1](../design/evidence.md#1-the-guarantee), [§3](../design/evidence.md#3-first-calls-and-sessions); [`../record/experiments.md`](../record/experiments.md) §11; `ndport/README.md`; the census `ndport/logs/p3/census-P0.log`);
- the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (P3-1, P4-1, P4-2);
- the porting guideline [`../intro/porting.md`](../intro/porting.md): 0.1a, 0.2 ("an informal interface becomes a trait over its existing functions"), B5;
- the clones at `upstream`: `ndport/pkgs/Graphs.jl` (1.15.0), `NetworkLayout.jl` (0.4.11), `GraphMakie.jl` (0.6.6), `NetworkDynamics.jl` (1.3.0); the P4 worktree `pkgs/NetworkDynamics-p4` at c9339fd (step 1's code); TraitWorld 3bebf13.

File and line references are to the clones at `upstream`, and to TraitWorld as cited. No Julia was run for this plan.

## Summary

- **The name is `GraphInterface`, not `Graph`.** Graphs exports `Graph` as an alias of `SimpleGraph` (`src/Graphs.jl:75`, `:496`). Inside Graphs, `@trait Graph` fails outright. Declared in another package, `g::Graph` in a module that has done `using Graphs` is a typed method on `SimpleGraph`, silently. "The graph trait" below means `GraphInterface`.
- **Where it lives:** in Graphs, the owner of `AbstractGraph` and of every function the trait names. Graphs stays plain code: `@trait` and `@implement` work in any module (traits §2). Graphs gains TraitWorld as a dependency. Nothing in Graphs is compiled by facts because of it.
- **Not wrapped:** neither Graphs nor GraphMakie becomes a trait module. GraphMakie's helpers are deferred (§2.6).
- **The declaration:**
  - `Graphs.nv`, `ne`, `is_directed`, `has_edge`, `degree` as operations on Graphs' existing functions;
  - two new operations with concrete results, `edge_list` and `all_neighbor_list`, in place of the open iterators `edges` and `all_neighbors`. Graphs' own test type `Graphs.Test.GenericGraph` returns generators from those (`src/Test/Test.jl:66`–`:91`), so `::AbstractVector{V}` results would refuse it;
  - `V = eltype(Self)`; no default attribute: the first-seen rule makes the graph `Compiled` at every caller here.
- **Conformance:** one family line over `AbstractGraph`, by the existing methods, each member checked at its first use. Graphs' throwing fallbacks infer `Union{}`, and TraitWorld refuses such a method (`TraitWorld/src/implement.jl:270`).
- **The bounds, a function at a time,** in NetworkDynamics: the index manager's reads of the graph (G2), the feed-forward check (G3), optionally the degrees of the inverse aggregation map (G4).
- **`Layout`: not taken.**
- **What it buys, honestly:** correctness, little time.
  - A graph whose edges are not `SimpleEdge`s (`GenericGraph`) builds a network, with the results of the same graph as a `SimpleGraph`. Upstream fails in the index manager's field conversion (`network_structure.jl:37`–`:38`) and in the feed-forward check's `e.src` (`construction.jl:89`–`:95`), by reading; G0 confirms.
  - A graph type whose methods exist but return the wrong type is refused at the first bounded call, naming the operation and both types. Graphs' own `NotImplementedError` already reports a missing method; the trait adds this case.
  - A new graph type still recompiles the stack: the `Network`'s type carries the graph's type (§3.2).
- **Timing: now, trimmed** (§4.4): G0, G1, G2, G3, G7, E-154's runs; G4 optional; G5–G6 only if G0 (d) shows GraphMakie failing on a `GenericGraph` upstream.
- **Measured** by E-154 (§5): results exact against U; the contract on seven graph types and one that returns the wrong type; a `graphtype` pass on `GenericGraph`; the cost against step 1's code (P4G-0).

---

## 1. Where the trait lives

### 1.1 The options

The rules: an implementation is a method, written by the trait's owner or the type's owner ([traits §10.1](../reference/traits.md#101-who-may-implement)). A family over an abstract type is one line, by the members' existing methods ([§4.7](../reference/traits.md#47-families)). Bounded functions exist only in trait modules ([§2](../reference/traits.md#2-trait-modules)).

| Where | Ownership | What it costs | Decision |
|---|---|---|---|
| **Graphs, as plain code** (a new file) | owns the trait, `AbstractGraph` and every function named; implements for foreign subtypes as the trait's owner | TraitWorld becomes a dependency of Graphs. In the port's environments TraitWorld is loaded anyway, so nothing measurable; plain users of Graphs outside the port would load it. Graphs' dependents precompile again in `depot-p4` | **taken** |
| Graphs as a trait module, whole | as above | Graphs' code (1,923 methods, no pirates by the census) is compiled by facts. Graphs has no precompile workload, so every Graphs call from plain code (`watts_strogatz`) is compiled by facts in the session. It protects nothing the workload loses: in E-153's order B no Graphs code is among the losses | not taken |
| An extension of Graphs, triggered by TraitWorld | the extension counts as Graphs | refused: each trigger must own the trait or a type the declaration names (§10.1), and TraitWorld owns neither. Consumers would also reach the trait only through `Base.get_extension` | not possible (pushback P4-4) |
| A small package of its own, holding the trait, the family and the two new functions | owns the trait and the new functions; implements for `AbstractGraph` subtypes by their existing methods; its `AbstractGraph` methods of its own functions are not pirates | the conformant form for an owner that does not want TraitWorld as a dependency (P4-4). For the port, a second home for Graphs' concept with no gain | not taken for the port |
| NetworkDynamics | owns the trait | GraphMakie would depend on NetworkDynamics for it | not taken |

### 1.2 Wrapping Graphs or GraphMakie: what it would cost

- **Graphs, whole:** see the table.
- **GraphMakie, whole:**
  - two pirates by the letter, `Makie.symbol_to_plot(::Val{:GraphPlot})` and `(::Val{:EdgePlot})`, made by Makie's `@recipe` (census). A trait module refuses pirates at their definition ([§10.2](../reference/traits.md#102-pirates)); a macro's methods are not always checked (T-56). They would move to a plain module first;
  - the recipe's `plot!` and its compute-graph closures become trait code, and what they reach is Makie's pipeline, compiled by facts in the session (GraphMakie has no precompile workload). The closest measurement: E-153's W, the first plot 48.5 against 16.0 s ([evidence §3](../design/evidence.md#3-first-calls-and-sessions));
  - nothing is measured to protect: in order B the plotting packages load after the simulation.
  - Not taken.
- **GraphMakie, partly** (a trait submodule for the helpers): see §2.6.

### 1.3 Where the code lives

- **Graphs:** a worktree `ndport/pkgs/Graphs-p4` on a branch `trait-port-p4` from `upstream`. The main clone is on `trait-port` and is shared by `env_port`, `env_p3` and `env_p4` through their `[sources]`; it stays at `upstream` (the meta plan's choice 8). `env_p4`'s and `env_ndtest_p4`'s `[sources]` point Graphs at the worktree, resolved offline.
- **GraphMakie:** a worktree `ndport/pkgs/GraphMakie-p4` only if G5–G6 run.
- **NetworkDynamics:** the P4 worktree, on `trait-port`, from c9339fd (step 1's code).
- **TraitWorld:** a `[deps]` entry in Graphs' `Project.toml`; the path comes from the environment's `[sources]`, as for NetworkDynamics. **Pinned at 3bebf13 for E-154.** A TraitWorld move recompiles NetworkDynamics (E-152's S5 note: 51 s) and changes the baseline; if it moves, the commit is recorded and P4G-0 is run again.
- **The depot:** `ndport/depot-p4`. After G1, Graphs' dependents precompile again: NetworkDynamics, GraphMakie and NetworkLayout's Graphs extension (`env_p4/Manifest.toml`), through the lock. Each of G2–G4 rebuilds NetworkDynamics.
- **The cache cap:** Julia keeps ten cache files per package in a depot and evicts the oldest. NetworkDynamics has been built into `depot-p4` at S0–S6 and is rebuilt at G1–G4, so the image of c9339fd may be evicted. A rerun of P4G-0 after G1 then rebuilds it first; the harness marks a run that precompiled INVALID.

---

## 2. The declaration

### 2.1 What the consumers read from a user's graph

| Consumer | Where (at `upstream`) | Reads | When |
|---|---|---|---|
| ND: `Network(g, …)` | `construction.jl:58`–`:64` | `vertices(g)` and `edges(g)` to count, `nv`, `ne` | construction; stays plain |
| ND: the feed-forward check | `construction.jl:66`–`:96` | `all_neighbors(g, i)`, `collect(edges(g))[eidx]`, `e.src`, `SimpleEdge(src, dst) ∈ simpleedges`, `degree(g, v)` | construction, only with feed-forward vertices (`rhs_check.jl`'s `ff` network) |
| ND: the index manager | `network_structure.jl:32`–`:55` | `nv`, `ne`, `collect(edges(g))` into `edgevec::Vector{SimpleEdge{Int64}}` (`:3`, `:37`) | construction |
| ND: the inverse aggregation map | `aggregators.jl:204`–`:207` | `degree(g)`, as capacities | construction, Threaded and Polyester aggregators |
| ND: other reads of the stored graph | `gbufs.jl:14`, `:46`–`:47`; `post_utils.jl:248`; `show.jl:5`–`:22`; `network_structure.jl:139`–`:140` | `nv`, `ne` | construction, printing, `nv(nw)`; stay plain |
| GraphMakie: the helpers | `recipes.jl:566`, `:599`–`:722`, `:887`–`:982` | `edges` with `src`/`dst`, `ne`, `is_directed`, `has_edge`, `all_neighbors` | each resolve; plain (§2.6) |
| GraphMakie: the recipe's closures, `getedgekeys` | `recipes.jl:221`–`:231`, `:317`–`:318`, `:366`–`:543`; `utils.jl:22`–`:43`, `:80`, `:97` | `nv`, `layout(graph)`, `is_directed`, `ne`; SimpleTraits' `IsDirected` | plain |
| NetworkLayout | `ext/NetworkLayoutGraphsExt.jl` | `adjacency_matrix(g)` | per layout; plain |

### 2.2 The declaration

A new file `src/interface_trait.jl` in Graphs, included after `using .SimpleGraphs` and the aliases (`src/Graphs.jl:490`–`:503`), so that `degree`, `all_neighbors` (`core.jl`) and `SimpleEdge` exist.

```julia
using TraitWorld: @trait, @implement

"The edges of `g` as `SimpleEdge`s, in the order of `edges(g)`."
edge_list(g::AbstractGraph{T}) where {T} = SimpleEdge{T}[SimpleEdge{T}(src(e), dst(e)) for e in edges(g)]
"The in- and out-neighbours of `v`, as `all_neighbors(g, v)` gives them, collected."
all_neighbor_list(g::AbstractGraph{T}, v::Integer) where {T} = collect(T, all_neighbors(g, v))

"What generic code reads from a graph: vertices 1:nv, edges as source and destination."
@trait GraphInterface{V <: Integer} begin
    V = eltype(Self)                                            # eltype(::Type{<:AbstractGraph{T}}) = T, interface.jl:125
    Graphs.nv(g::GraphInterface{V})::V                          # SimpleGraphs.jl:125 returns T
    Graphs.ne(g::GraphInterface)::Int
    Graphs.is_directed(g::GraphInterface)::Bool                 # interface.jl:228, by the type's method
    Graphs.has_edge(g::GraphInterface{V}, s::V, d::V)::Bool
    Graphs.degree(g::GraphInterface{V}, v::V)::Int              # core.jl:158, generic over AbstractGraph
    Graphs.edge_list(g::GraphInterface{V})::Vector{SimpleEdge{V}}
    Graphs.all_neighbor_list(g::GraphInterface{V}, v::V)::Vector{V}
end

@implement GraphInterface G where {G <: AbstractGraph}      # every subtype, by its existing methods
```

- **The operations are written qualified** (`Graphs.nv`): they are Graphs' existing functions ([§3.1](../reference/traits.md#31-operations)). `edge_list` and `all_neighbor_list` are defined as functions of Graphs before the trait, with one method each for `AbstractGraph`.
- **The names** follow Graphs' style (`all_neighbors`, `has_edge`). `all_neighbor_list` says "in and out", unlike Graphs' `neighbors`, which means the out-neighbours.
- **No default attribute** (§2.4).
- `GraphInterface` and the two functions are exported or declared `public`: decided at G1, recorded.

### 2.3 Why this shape

- **`V` is the vertex type** (expl. §2.2). `nv` returns it (`SimpleGraphs.jl:125`), so a declared `Int` would refuse `SimpleGraph{Int32}` at its first use.
- **The open iterators.** `edges`, `vertices`, `outneighbors`, `inneighbors` and `all_neighbors` return whatever the graph type returns: a `SimpleEdgeIter`, a `FrozenVector` (`SimpleGraphs.jl:157`–`:158`), a `Vector` (`simpledigraph.jl:620`), or a generator (`Test/Test.jl`). An operation must declare its result ([§3.1](../reference/traits.md#31-operations)), and the member's method must infer to it ([§4.9](../reference/traits.md#49-checks-at-the-declaration)).
  - `::AbstractVector{V}` refuses `GenericGraph`, Graphs' own type for testing "any `AbstractGraph`".
  - `::Iterable{V}` (BaseTraits) does not help: a generator is not a member of `Iterable` (BaseTraits implements it for arrays and dictionaries, `TraitWorld/src/BaseTraits.jl:84`–`:91`), and its `eltype` is `Any`.
  - An associated iterator type would need a type-level function of the graph type, an `edgeitertype(G)`, for an equation of `Self` ([§3.4](../reference/traits.md#34-parameters-and-associated-types)). Graphs has none.
  - So the trait names what the consumers need, with concrete results: the edge list and the neighbour list, each a copy. The typed comprehension fixes the result type whatever `edges(g)` yields. Cost: one copy per call, at construction. Pushback P4-3.
- **Left out:** `vertices`, `outneighbors`, `inneighbors`, `has_vertex`, `edgetype`, `zero`. No consumer in this step needs them through the trait. ND takes the vertices to be `1:nv(g)` (`construction.jl:170`; `network_structure.jl:35`).
- **`is_directed` and `degree`** have concrete results at every member: `is_directed(::G) = is_directed(G)` reaches the type's method; `degree(g, v)` is a `length` of neighbours (`core.jl:118`, `:158`–`:163`).
- **The edges are `SimpleEdge{V}`,** the type ND's index manager stores. ND converts to `SimpleEdge{Int}` itself (G2).
- **Throwing fallbacks.** With the family "by existing methods", Graphs' `_NI` fallbacks (`interface.jl:18`, `:140`, `:157`, `:229`, `:275`) are methods. The member check infers each operation at the member's concrete argument types and refuses a method that infers `Union{}` (`implement.jl:243`–`:271`). This needs concrete declared arguments: with an abstract one (`v::Integer`) the check asks only that a method exists (`implement.jl:254`–`:263`), and the fallbacks pass that. So `v::V` stays, and callers convert (G3).

### 2.4 No default attribute

- **The traits plan's draft** had `@default_with_dynamic_self`, so that the helpers compile once whatever the graph type. That holds only once the graph's type leaves the `Network`'s type (§3.2).
- **Today:** the graph's type is in the `Network`'s type, so NetworkDynamics compiles everything downstream per graph type anyway. A `Dynamic` graph would add a run-time split per operation, and the `Dynamic` path's machinery compiled per new type ([open issues §4](../open-issues.md#4-runtime-and-measurements), item 35).
- **Without a default,** the first-seen rule decides ([§6.2](../reference/traits.md#62-how-plain-values-enter-the-trait-world)). Every caller in this step knows the graph's type (NetworkDynamics' constructor, compiled by facts and specialised on `g`), so the graph is `Compiled`, and the bounded functions are compiled per graph type, as today, and fully typed.
- **G0 (c) checks traits §5.2 on the way:** a bounded probe called with `with_dynamic(g)` reads `nv` and `edge_list` typed at the caller's `V`. By reading, the erased view carries `V` in its key (`entry.jl:213`–`:262`, `attributes.jl:35`–`:54`, `core.jl:726`). If it shows `Any`, that contradicts §5.2 ("the same results"), and a T- deviation row is proposed to the reference's owner. It decides nothing in this step.

### 2.5 How types conform

One line: `@implement GraphInterface G where {G <: AbstractGraph}` ([§4.7](../reference/traits.md#47-families), the variable form, as BaseTraits' `@implement Iterable A where {A <: AbstractArray}`; T-38 avoided). Each member is checked at its first use, by inference of the seven operations.

Expected, checked by `scripts/graph_check.jl` (§3):

| Type | Expected | The reference for its network (check C) |
|---|---|---|
| `SimpleGraph{Int64}` `g` (the workload's) | conforms | itself |
| `SimpleDiGraph{Int64}` `d` | conforms; `all_neighbors` by its own method | itself |
| `SimpleGraph{Int32}(g)` | conforms, `V = Int32` | `g`, if it builds; ND may still fail later on `Int32` ranges: reported, not claimed |
| `Graphs.Test.GenericGraph(g)` | conforms | `g` |
| `Graphs.Test.GenericDiGraph(d)` | conforms | `d` |
| `Graphs.ReverseView(d)` | conforms | `reverse(d)` |
| `Graphs.UndirectedView(d)` | conforms | `SimpleGraph(d)`, after checking that the edge orders agree |
| `WrongNv(g32)`: an `AbstractGraph{Int32}` subtype wrapping a `SimpleGraph{Int32}`, every function forwarded (`is_directed` on its type, `vertices`, `edges`, `outneighbors`, `inneighbors`, `has_edge`, `ne`), but `nv` returning `Int64` | refused at its first use: `ImplementError` naming `nv`, `WrongNv`, `Int64` and the declared `Int32`, and no other operation | — |

- `WrongNv` is a type the trait catches and Graphs does not: its methods exist, so Graphs' fallbacks never throw, and NetworkDynamics' plain reads (`length(_vertexm) == nv(g)`) accept an `Int64`.

### 2.6 Where the bounds go, and what stays plain

- **NetworkDynamics** (a trait module, whole): up to three new bounded functions in `src/network_structure.jl`, `src/construction.jl` and `src/aggregators.jl`, called from the existing plain-typed code.
  - `Network(g::AbstractGraph, …)` keeps its signature. A bound there would make `g` a trait object, which code may not store bare ([§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object)); the index manager stores the user's graph for `get_graph`.
- **GraphMakie: deferred.**
  - By reading, GraphMakie upstream already handles `GenericGraph`'s generators: its helpers iterate `edges(g)` with `src`/`dst`, size vectors by `ne(g)` and call `all_neighbors`. G0 (d) confirms it.
  - Bounding them would fix nothing and would make their reach trait code: Makie's compute-graph `getindex` through `getattr` (`utils.jl:52`), the marker geometry, the scene's projection (`recipes.jl:910`–`:982`). That is E-153's mechanism; the time is spent for a design test only.
  - **G5–G6 run only if G0 (d) shows GraphMakie failing on a `GenericGraph` upstream.** Then the helpers that fail take the bound, in a trait submodule `GraphKernels`, with a stop rule on the first plot (§4.2).
  - **If the design test "a trait submodule in a plain package" is wanted anyway** (the user's call), the form is a small kernel that reads only the graph: the edge list with each edge's reciprocal flag, `[is_directed(g) && has_edge(g, dst(e), src(e)) for e in edge_list(g)]`, with the geometry and the attribute reads left in the closures. Its reach is Graphs' code only.
  - Plain GraphMakie code may call `edge_list` and `all_neighbor_list` without any bound: they are plain Graphs functions.
- **Plain, unchanged:** the recipe and its helpers; `layout(graph)` and NetworkLayout; ND's direct `nv`/`ne` on the stored graph (§2.1); ND's implicit graph construction (`construction.jl:312`–`:323`), which builds its own `SimpleDiGraph`.

### 2.7 Each construct against TraitWorld today

| Construct | Where | Status | Deviations met |
|---|---|---|---|
| `@trait` and `@implement` in a plain package | [§2](../reference/traits.md#2-trait-modules) | Implemented | none known; Graphs is the port's first plain package to declare a trait |
| a parameter bound and an equation `V = eltype(Self)` | [§3.4](../reference/traits.md#34-parameters-and-associated-types) | Implemented | none; BaseTraits' `Iterable` has the same shape |
| operations on the package's existing functions, qualified | [§3.1](../reference/traits.md#31-operations) | Implemented | none |
| a family over an abstract type, variable form, by existing methods | [§4.7](../reference/traits.md#47-families) | Implemented | T-38 avoided; T-5 not met (no block). `_keys_implement` (`implement.jl:988`–`:1028`) expands it as BaseTraits' families |
| a bound with a `where` variable (`GraphInterface{V} where {V}`) | [§5.1](../reference/traits.md#51-bounds) | Implemented | none |
| the first-seen rule at a typed caller | [§6.2](../reference/traits.md#62-how-plain-values-enter-the-trait-world) | Implemented | none |

### 2.8 `Layout`: not taken

- **No consumer can take it as a bound** without porting GraphMakie's recipe. The `layout` attribute is a layout, a function or a vector (`recipes.jl:222`–`:230`), read in a compute-graph closure; a bounded closure is Planned ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)).
- **It needs a change in NetworkLayout:** `dim` and `ptype` are defined on instances (`NetworkLayout.jl:36`–`:37`); an equation `Dim = dim(Self)` needs them on the type.
- **No benefit for the workload:** one `Spring` layout, computed once per plot.
- **Revisit** when a user's own layout type enters the workload, or when GraphMakie's recipe is ported.

---

## 3. The changes, a function at a time

Each row is one commit. The checks:
- (P) the changed packages and their dependents precompile in `env_p4`, which runs the trait module's definition check;
- (C) `scripts/graph_check.jl` (new), in `env_p4`:
  - the member table of §2.5, through a bounded probe in a scratch trait module (the gate for the contract);
  - `Network` built on each conforming type, with tier S's models, and its `nv`, `ne`, `edgevec` and the hash of `du` (as `rhs_check.jl` computes it) compared with the network on the type's reference (§2.5);
  - `Network` on `WrongNv`: the error, its type and the frame it is raised in;
- (R) `rhs_check.jl`: every hash equal to U's (its `ff` network reaches the feed-forward check; its Threaded and Polyester styles reach the inverse aggregation map);
- (W) the full workload in setting P4, one run, `compare_digests.py --exact` against E-151's U log;
- (T) ND's test subset (`nd_tests.sh p4 …`) in `env_ndtest_p4`, with Graphs' `[sources]` at the worktree.

Graphs' own test suite is not run: it needs its test environment (`test/Project.toml`: StableRNGs, Unitful, JET, IGraphs, NautyGraphs, …), and the change adds one file with two functions and a trait. P and C cover it.

| # | File:line (at `upstream`) | Function | Change | Check |
|---|---|---|---|---|
| G0 | `ndport/scripts/graph_probe.jl`, `graph_check.jl` (new); E-154 registered | — | A few minutes, two sessions. **(a)** In `env_upstream` (U): `Network` on `GenericGraph(g)`, `GenericDiGraph(d)` and `SimpleGraph{Int32}(g)` with tier S's models: the error and its frame. **(d)** In the same session, with CairoMakie: `graphplot(generic_graph(g); layout = Spring(seed = 1))`, the figure built and not saved; and `is_connected`, `edges` as `digest_b` reads them. Mandatory: the `graphtype` pass needs these, and the answer decides G5–G6. **(b)** In `env_p4` with `depot-p4` (step 1's code, Graphs still at `upstream`): the trait of §2.2 declared in a scratch module (it owns the trait, so the family over `AbstractGraph` is allowed), and the member table of §2.5 through a bounded probe. **(c)** In the same session: §2.4's check of traits §5.2 | `ndport/logs/p4g/g0-*.log` |
| G1 | Graphs: `src/interface_trait.jl` (new), its include in `src/Graphs.jl`; `Project.toml` | `GraphInterface`, `edge_list`, `all_neighbor_list`, the family | §2.2; the worktree and the `[sources]` of §1.3 | P, C (the member table) |
| G2 | ND: `src/network_structure.jl:32`–`:38` | `graph_index(g::GraphInterface{V}) where {V}` (new); `IndexManager`'s inner constructor | `graph_index` returns `(; nv = Int(nv(g)), ne = ne(g), edges = SimpleEdge{Int}.(edge_list(g)))`. The constructor calls it first and reads these instead of `nv(g)`, `ne(g)`, `collect(edges(g))` | P, C, R, W |
| G3 | ND: `src/construction.jl:66`–`:96` | `check_feedforward_leaves(g::GraphInterface{V}, vertexm, edgem) where {V}` (new) | the block moved into the function: `all_neighbor_list(g, V(i))` for `all_neighbors(g, i)`; `edge_list(g)[eidx]` for `collect(edges(g))[eidx]`; `src(e)` for `e.src`; `degree(g, src(e))`; the same errors and messages | P, C, R (the `ff` network), T |
| G4 (optional) | ND: `src/aggregators.jl:205` | `degrees(g::GraphInterface{V}) where {V}` (new); `_inv_aggregation_map` | `[degree(g, v) for v in one(V):nv(g)]` for `Graphs.degree(im.g)`. It fixes nothing upstream gets wrong (`degree` is generic over `AbstractGraph`); it adds a third consumer | P, R (Threaded, Polyester), W, T |
| G5–G6 (conditional) | GraphMakie | the helpers G0 (d) shows failing | §2.6; a worktree `pkgs/GraphMakie-p4`; a trait submodule `GraphKernels` | P, W (the stop rule), GraphMakie's `test/runtests.jl` without reference images |
| G7 | `ndport/scripts/workload_steps.jl`, `workload.jl` | `step_b`, `run_sim`, `run_pass`; the driver | **additive, off by default:** a keyword `graph = :simple` through `run_pass` → `run_sim` → `step_b`; `:generic` builds the network on `Graphs.Test.generic_graph(watts_strogatz(20, 4, 0.2; seed = 42))`. The driver runs a pass `graphtype` (steps b–g, `swing!`) only when `NDW_PASSES` names it. A step that throws prints `D graphtype <step> error=<type>` and ends the pass. `run_workload.sh` is not changed. Without `graphtype` in `NDW_PASSES` the output is byte-identical; checked by one U run `--exact` against E-151's. One commit; the coordinator tells P6's agent before it lands | the pass in U (the before) and in P4 |
| G8 | `ndport/` | — | E-154's runs (§4.2); the README's dated table; the guideline's B5 lessons (§7); the pushback entries (§6); commits | §4 |

- **Exact equality is expected at every row.** `edge_list` and `all_neighbor_list` give the same elements in the same order as `edges` and `all_neighbors`; the arithmetic is unchanged.
- **The digest comparison:** `compare_digests.py` is checked to tolerate the extra pass and the `error=` lines; if it does not, a small script compares the `graphtype` pass with the same session's `first`.

### 3.1 What does not change

- **The graph's type stays in the `Network`'s type:** `IndexManager{G}` (`network_structure.jl:1`), `Network{…, G, …}` (`:88`, `:109`), `NetworkLayer` (`construction.jl:214`), `NaiveAggregator` (`aggregators.jl:24`).
- **`get_graph(nw)`** returns the user's graph (`network_structure.jl:148`); the workload reads it (`workload_steps.jl:56`, `:64`, `:87`; `workload_plot.jl:11`, `:37`).
- **Public signatures** of NetworkDynamics, Graphs and GraphMakie. `Network` accepts every `AbstractGraph` it accepts today, except one whose methods violate the interface's types (`WrongNv`), which it refuses.

### 3.2 Not this step: erasing the graph's type

- With the graph kept as `Kept{GraphInterface}` in the index manager, the `Network`'s type would not change with the graph's type, and a new graph type would compile only the bounded functions. Then a `Dynamic` default pays (§2.4).
- But `get_graph` must then return the user's object, read back from a kept value: [open issues §2](../open-issues.md#2-design), item 16; the traits plan's PB-5 meets the same.
- A plain `g::Any` field would erase the type without traits, so the trait is not what this would test.
- Revisit trigger: a new graph type in tier M, or open issue 16 decided (§9).

---

## 4. What it buys, measured cheaply

### 4.1 The expectation, honestly

- **Time: almost nothing for tier S.** One `SimpleGraph{Int64}`, read at construction.
- **The crossings are rare.** Every `AbstractGraph` type is a family member. With TraitWorld 3bebf13 a family member is served by the entry's table (open issue 48, closed); a crossing from trait code costs what one from plain code does, and from a kept value about 390 ns and one allocation (E-152's row). Here NetworkDynamics makes two or three crossings per `Network`, not per right-hand side. Calls between bounded functions are static ([lowering §8.1](../reference/lowering.md#8-bounded-functions-workers-and-entries)). Criterion 3's "again" expects nothing.
- **The member check** (inference of seven operations) runs at the first use in each session. The builder registry is Graphs' (`implement.jl:789`–`:798`); Graphs has no workload, and NetworkDynamics' `@workload` does not save Graphs' registry. If step b misses its first-call bound, the first thing to try is a workload in Graphs that makes `SimpleGraph{Int}` and `SimpleDiGraph{Int}` members once: builders found by the declaring package's workload are saved with its image (`implement.jl:783`–`:785`).
- **A new graph type** works where upstream fails (G0 (a) confirms). It recompiles the stack about as much as new equations do upstream (15.6–16.0 s, E-151), because the `Network`'s type carries it (§3.1). The `graphtype` pass makes that visible.
- **What the contract adds over a plain fix:** a refusal at the first bounded call of a type whose methods return the wrong types, naming the operation, the type and the inferred result. A missing method Graphs reports already.
- **The value for the design** is larger than for the workload:
  - the first family over an abstract type that foreign packages subtype, with a real consumer;
  - a trait declared in a plain package that stays plain;
  - the open-iterator problem (P4-3).

### 4.2 Settings and criteria

**Settings:**
- **U:** upstream, `env_upstream`: the reference for results (E-151's U log); one run with `NDW_PASSES=first,again,params,changed,graphtype` for the before of the `graphtype` pass (and the byte-identity check of G7 from its common passes).
- **P4G-0:** setting P4 of `run_workload.sh` (`env_p4`, `depot-p4`) at NetworkDynamics c9339fd, TraitWorld 3bebf13, Graphs at `upstream`: the before of this step's own effect. E-152's runs after the change to 3bebf13 serve if they are at exactly these commits with today's harness; otherwise two runs before G1.
- **P4G-1:** setting P4 after G8, Graphs at the worktree; two runs with the default passes, one run with `graphtype` added, one attribution run (`NDW_DIAG=1`) with `graphtype`.

Each run records the julia-1.13 commit, TraitWorld 3bebf13, strict mode off, the load order fixed (the P1 plan §2.3), and the machine's load before and after (the harness's `load-before`/`load-after`; a run above 4 is repeated). With n = 2 the numbers are indicative. **What they measure:** NetworkDynamics' bounded functions reading plain graph types through their existing methods: interop, not idiomatic trait code.

| # | Criterion | Before | Pass when |
|---|---|---|---|
| 0 | Results | P4G-0 equal to U exactly | the passes common to U and P4G-1 (`first`, `again`, `params`, `changed`) `--exact` against U in every P4G-1 log; every `rhs_check.jl` hash equal to U's. A gate |
| 1 | The contract | G0 (b) | in `graph_check.jl`: the seven types of §2.5 conform at a bounded probe; `WrongNv` is refused with `ImplementError` naming `nv`, `WrongNv`, `Int64` and `Int32`, and no other operation (the gate). Through `Network`, `WrongNv` is refused by the same error, raised from `graph_index` (reported) |
| 2 | A graph type upstream refuses | U's `graphtype` pass: b fails (G0 (a) names the error) | P4G-1's `graphtype` pass runs b–g; each digest equals the same step's in that session's `first` |
| 3 | No cost | P4G-0, per step, over the common passes | "again": each step, the minimum of two runs, at most 1.10 × P4G-0's + 5 ms. "first": step b at most P4G-0's + 0.5 s. The session's common passes at most P4G-0's + 3 s. The `graphtype` pass reported apart. A failure is confirmed by one more run |
| 4 | What a new graph type compiles | — (U fails) | reported, not a gate: the `graphtype` pass's compile time per step and its new CodeInstances by module; the share of `graph_index` and the member check |
| 5 | Tests | T at c9339fd | the same passes |
| 6 | §5.2 | — | G0 (c): `with_dynamic(g)` at the probe gives results typed at `V`; otherwise a T- row is proposed (not a gate) |

### 4.3 What a failure changes

- **Criterion 0:** a port bug, fixed first.
- **Criterion 1:**
  - a type of §2.5 refused that should conform: the declaration is wrong for it; the result type is fixed in the declaration, and the case recorded;
  - `WrongNv` accepted, or refused naming other operations: a disagreement between TraitWorld and traits §4.9, reported to whoever owns the reference (a T- row; CLAUDE.md, "Precedence").
- **Criterion 2:** a step after b failing on `GenericGraph` (GraphMakie's `getedgekeys`, NetworkLayout's `adjacency_matrix`, `digest_b`'s reads) is known from G0 (d) before G1. If it is GraphMakie's, G5–G6 run; if it is elsewhere, the pass ends there and the plan names the reader.
- **Criterion 3, step b over its bound:** first the workload in Graphs (§4.1); then the member check's cost goes to [open issues §4](../open-issues.md#4-runtime-and-measurements).
- **Criterion 3, "again":** not expected; read with the attribution run.
- **Criterion 6:** a T- row proposed; nothing in this step changes.

### 4.4 The timing, and the order

- **What lets the step start:** the meta plan's choice 16 (the port continues around open issue 48, now closed). E-152 met its criterion 2 and failed its criterion 4; the steady-state gap is the step's crossings per right-hand side, a question for the port's next steps, which this step does not touch.
- **Now, trimmed:** G0 (all four parts), G1, G2, G3, G7, E-154's runs; G4 optional; G5–G6 conditional on G0 (d).
  - P6 shares no tree, environment or depot with this step: P6 reads the main clones, which stay at `upstream`, and never touches `pkgs/Graphs-p4`, `env_p4` or `depot-p4`. The one shared change is G7's, in the harness scripts.
  - Every job runs under the lock, between P6's jobs. G0 takes a few minutes; each of G1–G3 rebuilds Graphs' dependents or NetworkDynamics in `depot-p4`; E-154 adds four or five workload sessions.
  - **Priority:** below TraitWorld work the user approves. This step must not delay it.
- **Why second, before `ODERHS` and `IndexProvider`:** after step 1, each remaining step buys mostly correctness. This one is the cheapest (four or five commits, two packages, no Planned part, no pirates, no SciML question), and its pushback (P4-3) is about associated types, which `ODERHS{T, P}` and `ValueProvider{U, P}` meet next.

---

## 5. The registry row

To be added to `writeup/record/experiments.md` §11 with status running before G0's first run.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-154 | W-32 P4, step 2: Graphs' informal `AbstractGraph` interface as a trait, `GraphInterface{V}`, declared in Graphs (plain) with a family over `AbstractGraph`; NetworkDynamics' construction-time reads of the graph bounded by it ([the graph plan](../plans/2026-10-21-ndport-graph.md)). Tier S plus a `graphtype` pass on `Graphs.Test.GenericGraph`; product setting, strict mode off, fixed load order; julia-1.13 at the build E-152 used, TraitWorld 3bebf13; P4G-1 (two runs) against U (results) and P4G-0 (NetworkDynamics c9339fd, the step's own effect). (0) Are the common passes' digests and the right-hand-side checks exactly equal to U? (1) Do `SimpleGraph{Int64}`, `SimpleDiGraph`, `SimpleGraph{Int32}`, `GenericGraph`, `GenericDiGraph`, `ReverseView` and `UndirectedView` conform at their first use, and is `WrongNv` (an `AbstractGraph{Int32}` whose `nv` returns `Int64`) refused at a bounded probe with `ImplementError` naming `nv` and both types? (2) Does a network on `GenericGraph` build and give the results of the same graph as a `SimpleGraph`, where upstream fails? (3) What does the step cost against P4G-0: the steady state (10 % + 5 ms), the first network (+0.5 s), the session's common passes (+3 s)? (4) What does a new graph type compile, by module? (5) Does a `Dynamic` trait object of `GraphInterface` give results typed at the caller's `V` (expected yes, traits §5.2)? Measures library trait code reading plain graph types (interop). **Would change the plan:** an exact difference (a port bug); a type of the table refused (the declaration), or `WrongNv` accepted (a TraitWorld disagreement with traits §4.9); a step after b failing on `GenericGraph` (G0 (d) names the reader; GraphMakie's helpers then take the bound); step b over its bound (a workload in Graphs, then open issues §4); (5) negative (a T- deviation row, nothing else). | registered (2026-10-21) | `ndport/` (its own repository): `scripts/graph_probe.jl`, `graph_check.jl`, `rhs_check.jl`, `nd_tests.sh`, `run_workload.sh` (setting P4, `NDW_PASSES` with `graphtype`); `logs/p4g/`; the worktrees `pkgs/Graphs-p4` (branch `trait-port-p4`), `pkgs/NetworkDynamics-p4` | — | `ndport/README.md`; [the graph plan](../plans/2026-10-21-ndport-graph.md) |

When E-154 is done, its outcome and an evidence row in `writeup/design/evidence.md` are written in one commit (CLAUDE.md, rule 1).

---

## 6. Expected pushback entries

In the log's shape ([`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md)), numbered on from P4-2. Each is written there once E-154 confirms it.

**P4-3. An informal interface whose functions return open iterators.**
- **The code:** Graphs' `edges`, `vertices`, `outneighbors`, `inneighbors`, `all_neighbors` return what the graph type returns; Graphs' own `GenericGraph` returns generators (`src/Test/Test.jl:66`–`:91`).
- **The idiomatic form:** an associated iterator type with a declared item type (Rust's `type Edges: Iterator<Item = Self::Edge>`; Swift's `associatedtype` with a `where` clause on its `Element`).
- **The reference:** every operation declares its result ([§3.1](../reference/traits.md#31-operations)), checked by inference at each member ([§4.9](../reference/traits.md#49-checks-at-the-declaration)). An associated type is defined by an equation of `Self` ([§3.4](../reference/traits.md#34-parameters-and-associated-types)), which needs a type-level function of the graph type; Graphs has none. A generator is not an `Iterable` member, and its `eltype` is `Any`.
- **What it costs:** two new functions in Graphs (`edge_list`, `all_neighbor_list`), a copy per call, at construction.
- **Blocks:** no.

**P4-4. The owner of an informal interface cannot put the trait in an extension.**
- **The code:** Graphs gains TraitWorld as a hard dependency for one trait and one family line.
- **The idiomatic form:** an optional dependency (a Cargo feature; a Julia package extension triggered by TraitWorld).
- **The reference:** an implementation in an extension must mention each trigger, and each trigger must own the trait or a type the declaration names ([§10.1](../reference/traits.md#101-who-may-implement)). TraitWorld, the trigger, owns neither. The rule's reason (a call's view should not depend on whether a package happens to be loaded) does not bite here, since the trait and its implementation would appear together. But an extension's names reach consumers only through `Base.get_extension`, so NetworkDynamics could not name the trait plainly.
- **The conformant form:** a small package holding the trait, the family and the new functions. It owns the trait and the new functions, implements for foreign subtypes by their existing methods, and adds no pirates.
- **What it costs:** for the port, nothing measurable (TraitWorld is loaded everywhere); for plain users of Graphs, TraitWorld's load.
- **Blocks:** no. An open issue only when a package outside the port is to declare a trait without a second package.

**P4-5, only if G5–G6 run. A bound on one helper needs a trait module, and the module's reach is compiled by facts.**
- **The code:** GraphMakie's helpers, moved into `GraphKernels` only to take a bound.
- **The idiomatic form:** a generic function in a plain package (Rust and Swift allow a bound on any function).
- **The reference:** bounded functions exist only in trait modules, and what trait code reaches is compiled by facts ([§2](../reference/traits.md#2-trait-modules); [facts §6.2](../reference/facts.md#the-mode-rule)).
- **What it costs:** the first plot's time against the stop rule.
- **Blocks:** only if the stop rule fires; then GraphMakie stays plain.

Not pushback, for the guideline: a trait whose natural name is an exported type or alias (`Graphs.Graph`) cannot be declared in that package, and elsewhere a bound spelled with it is a typed method, silently (§7).

---

## 7. Lessons for the porting guideline (B5), expected from this step

To be written there, in the present tense, once G8 confirms them:
- **Check the trait's name against the package's exports.** `Graphs.Graph` is `SimpleGraph`. A bound spelled with a type's name is a typed method.
- **Declare an informal interface's trait in its owner, as plain code.** Graphs stays plain; only the consumers' bounded functions are trait code.
- **Test the declaration against the package's own generic test types** (`Graphs.Test.GenericGraph`): they show which results are open.
- **An open iterator becomes an operation with a concrete result,** a copy with a declared element type.
- **Declare concrete argument types** (`v::V`), so that the member check infers the operation and refuses a throwing fallback; callers convert.
- **Bound the readers, not the front end,** where the front end stores the user's object: `Network(g::AbstractGraph, …)` keeps its type and calls bounded readers.
- **No default attribute while the value's type stays in the library's own types:** a `Dynamic` default pays only once the type is erased.

---

## 8. Choices for the user to review (for the meta plan's list)

Numbered on from the meta plan's 16:

17. **The trait's name:** `GraphInterface`. `Graph` is Graphs' alias of `SimpleGraph`: impossible inside Graphs, a silent typed method elsewhere. Alternatives: `GraphLike`, `IsGraph` (SimpleTraits' style, as `IsDirected`).
18. **Graphs declares the trait as plain code,** with TraitWorld as a hard dependency; the small separate package is the conformant alternative (P4-4). Graphs and GraphMakie are not wrapped.
19. **Two new operations** with concrete results, `edge_list` and `all_neighbor_list`, instead of the open iterators; `vertices`, `outneighbors`, `inneighbors` left out until a consumer needs them (P4-3).
20. **No default attribute:** the graph is `Compiled` at every caller in this step (§2.4).
21. **`Layout` not taken** this round (§2.8).
22. **GraphMakie's helpers deferred,** unless G0 (d) shows GraphMakie failing on a `GenericGraph` upstream; a graph-only kernel if the design test of a trait submodule is wanted (§2.6).
23. **The graph's type stays in the `Network`'s type;** erasing it waits for open issue 16 (§3.2).
24. **Timing:** now, trimmed (G0, G1, G2, G3, G7; G4 optional), below TraitWorld work the user approves (§4.4).

---

## 9. When to revisit

The traits plan's §6 applies. In addition:
- **G0 (d)'s answer,** at once: G5–G6 run or stay deferred.
- **A new graph type in the workload** (tier M), or open issue 16 decided: erasing the graph's type, and with it a `Dynamic` default (§3.2, §2.4).
- **A user's layout type,** or GraphMakie's recipe ported: `Layout` (§2.8).
- **A consumer of the left-out operations** (`outneighbors`, `vertices`): their declaration, by P4-3's pattern.
- **A package outside the port that is to declare a trait without a second package:** P4-4 becomes an open issue.
