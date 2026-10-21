# Review: the NetworkDynamics port, P4 step 2: the graph trait (plan)

Date: 2026-10-21. Reviewer: an Opus 5.5 agent, fresh eyes. Not edited after writing, except by a dated addendum.

**Reviewed:** [`../plans/2026-10-21-ndport-graph.md`](../plans/2026-10-21-ndport-graph.md) (status: proposal).

**Read against:**
- the meta plan [`../plans/2026-10-21-networkdynamics-port.md`](../plans/2026-10-21-networkdynamics-port.md) (ground rules, choices 1–16, state);
- the traits plan [`../plans/2026-10-21-ndport-traits.md`](../plans/2026-10-21-ndport-traits.md) §1.3, §4, Appendix A; the P6 plan [`../plans/2026-10-21-ndport-inside-out.md`](../plans/2026-10-21-ndport-inside-out.md) §3.2–§3.4;
- E-152 and E-153 ([`../record/experiments.md`](../record/experiments.md) §11), `ndport/logs/p4/NOTES.md`, the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (P3-1, P4-1, P4-2), [open issues](../open-issues.md) §1 item 48, §2 item 16, §4 item 35;
- [`../reference/traits.md`](../reference/traits.md) §2, §3.1, §3.4, §4.7, §4.9, §5.1–§5.4, §6.2–§6.3, §10.1; [`../reference/lowering.md`](../reference/lowering.md) §8.1–§9.3, L-3;
- Graphs 1.15.0 (`ndport/pkgs/Graphs.jl`, `trait-port` = `upstream`): `src/Graphs.jl`, `interface.jl`, `core.jl`, `SimpleGraphs/SimpleGraphs.jl`, `simpleedge.jl`, `Test/Test.jl`, `wrappedGraphs/graphviews.jl`, `test/runtests.jl`, `test/Project.toml`;
- GraphMakie 0.6.6 (`ndport/pkgs/GraphMakie.jl`, `trait-port` = `upstream`): `src/recipes.jl`, `src/utils.jl`;
- NetworkDynamics at `upstream` (`ndport/pkgs/NetworkDynamics.jl`) and the P4 worktree at c9339fd (read only: `git diff upstream`);
- TraitWorld a373e30 (`src/trait.jl`, `implement.jl`, `entry.jl`, `attributes.jl`, `core.jl`, `BaseTraits.jl`);
- the workload scripts `ndport/scripts/workload_steps.jl`, `workload_plot.jl`; `ndport/env_p4/Project.toml`.

No Julia was run. Every statement about behaviour below is from reading the code.

## Verdict

- **The declaration is correct against Graphs 1.15 for the seven conforming types,** by reading:
  - `nv` returns the vertex type (`SimpleGraphs.jl:125`; `GenericGraph`, `ReverseView`, `UndirectedView` forward it); `ne` is an `Int` field (`SimpleGraphs.jl:183`, `UndirectedView.ne::Int`); `is_directed` reaches each type's `Type` method; `has_edge` and `degree` return `Bool` and `Int`; the two new functions have typed results whatever `edges(g)` yields;
  - `V = eltype(Self)` reads `eltype(::Type{<:AbstractGraph{T}})` (`interface.jl:125`; `eltype` is imported from Base);
  - Graphs' throwing fallbacks (`_NI`, `interface.jl:18`, `:140`, `:157`, `:229`, `:275`) are refused at a member's first use: with concrete declared arguments the member check infers each operation and reports `Union{}` (`implement.jl:243`–`271`).
- **It runs in today's TraitWorld spelling,** with one slip in the import (finding 14). The family line expands as BaseTraits' `@implement Iterable A where {A <: AbstractArray}` does: `_keys_implement` (`implement.jl:988`–`1028`) turns it into `GraphInterface{_, G} where {G <: AbstractGraph}`, which `_implement_family` takes. T-38 is avoided. Graphs owns the trait, so the family over foreign subtypes is allowed (traits §10.1).
- **The upstream failures the step fixes are real,** by reading: the index manager converts `collect(edges(g))` into `Vector{SimpleEdge{Int64}}` in `new` (`network_structure.jl:37`–`38`), and neither `GenericEdge` nor `SimpleEdge{Int32}` has a `convert` to `SimpleEdge{Int64}` (only a constructor, `simpleedge.jl:28`). The feed-forward check uses `e.src` and `SimpleEdge(src, dst) ∈ simpleedges` (`construction.jl:89`–`95`), both wrong for `GenericEdge`.
- **Where it lives is sound for Graphs:** plain code declaring a trait, no facts compilation added. E-153 supports not wrapping Graphs.
- **GraphMakie's trait submodule is not sound as planned:** it buys no time and, likely, no correctness. Its reach includes Makie's compute graph, marker geometry and scene projection (finding 4).
- **The per-call cost of P4-1 does not bite here:** the step's crossings are a few per construction and per plot resolve, not per right-hand side (finding 6).
- **The dynamic-default question (PB-12) rests on a misreading** of where `Any` comes from, and is not a question for the user (findings 2, 3). **The extension question (PB-13) is real but need not go to the user now** (finding 13).
- **One blocker:** criterion 1's broken type is refused by Graphs' own `NotImplementedError` in NetworkDynamics' plain reads, before any bounded call (finding 1).
- No conflict with P6's trees, environments or depots. One conflict in the shared harness scripts (finding 11).

## Recommendation on timing

- **Go now, trimmed.** Do not wait for P6 or for open issue 48.
  - Open issue 48 is about per-call crossings in hot code. This step's bounded calls run at construction and at plot resolves (finding 6). Whatever 48 decides changes microseconds here.
  - P6 shares no tree, environment or depot with this step (P6 plan §3.3). P6's merge waits for P4's step 2 or 3, so finishing this step helps it.
- **The trimmed step:**
  1. G0 (a), (b) and (d), with the broken type fixed (finding 1) and (d) mandatory (finding 9). G0 (c) only as a check of traits §5.2, not as a decision (finding 2).
  2. G1 without the dynamic default (finding 3).
  3. G2 and G3 (finding 7 for G3).
  4. G4 optional: it fixes nothing upstream gets wrong (finding 15).
  5. G7, additive and off by default (finding 11).
  6. E-154's runs.
  7. **G5–G6 deferred,** unless G0 (d) shows GraphMakie failing on a `GenericGraph` upstream (finding 4).
- **The machine:** G0 takes a few minutes. Each of G1–G3 rebuilds Graphs' dependents in `depot-p4`: NetworkDynamics, GraphMakie, NetworkLayout's extension. E-154 adds three or four workload sessions. All of it runs under the lock, between P6's jobs.
- **Priority:** below open issue 48's TraitWorld work, once the user approves that. This step must not delay it. The step's value is mostly for the design: the first family over an abstract type with foreign subtypes, checked at first use, and the first trait declared in a plain package. That value is worth its small cost.

## Findings

### 1. (blocker, for the registry row) Criterion 1's broken type is refused by Graphs, not by the trait

- `Network(g, …)` reads `ne(g)` in plain code before any bounded call:
  - `@argcheck length(_edgem) == ne(g)` (`construction.jl:64`);
  - `unique_mappings(…, 1:ne(g))` in `IndexManager`'s constructor (`network_structure.jl:35`), before G2's `graph_index(g)`.
- For a type without `ne`, Graphs' fallback `ne(g::AbstractGraph) = _NI("ne")` throws `NotImplementedError` at the first of these.
- So criterion 1 ("refused with `ImplementError` naming `ne`, raised from the first bounded call") cannot pass. Its "would change the plan" clause ("the broken type accepted: a TraitWorld disagreement with §4.9") would fire wrongly.
- A missing method is also the case the plan's own §4.1 says Graphs already reports. The trait adds the case where a method exists and returns the wrong type.
- **Fix:**
  - Test the refusal on a bounded probe in `graph_check.jl`, not through `Network`.
  - Choose a broken type that the trait catches and Graphs does not. Examples: an `AbstractGraph{Int32}` subtype whose `nv` returns `Int`, or whose `has_edge` returns `nothing`. Then: `ImplementError` naming that operation and both types.
  - If the refusal should also show through `Network`, call `graph_index(g)` first in `Network(g, …)` and pass its result down. That is a change in `construction.jl`, beside G2.
  - The broken type defines every other function the operations need: `is_directed` on its type, `edges`, `outneighbors`, `inneighbors`, `has_edge`, `nv`. Otherwise the refusal names more than one operation.
  - E-154's question (1) and its "would change" clause follow.

### 2. (should fix) §2.4 and PB-12 misread where results become `Any`

- **How a plain value enters `Dynamic` at a bound,** under the trait's default:
  - `_enter_erased` → `_enter_keyed` → `_assemble`: the value's trait object at its own key (`entry.jl:213`–`262`);
  - then `_erase` (`attributes.jl:54`). Its erased view type takes the compiled view's trait parameters (`_erased_view_type`, `attributes.jl:35`–`44`). So the erased key is `ErasedKey{Tuple{Int64}, Nothing}`: it carries `V`.
  - `_trait_param` reads `V` from that key as a constant (`core.jl:726`). `_erased_op` asserts each result at the erased key's parameters (`attributes.jl:90`–`96`).
- **What the plan cites** applies elsewhere. `_erased_key_of` and `_erased_ft` (`core.jl:928`–`934`, `attributes.jl:116`) type the declared-field reads of a kept `Dynamic{X}` whose `X` leaves a parameter open. They do not type operations on a trait object at a bound.
- **So, by reading,** G0 (c) should find all three bounds typed at the caller's `V`: `g::GraphInterface`, `g::GraphInterface{V} where {V}` and `g::GraphInterface{Int}`.
  - If G0 (c) shows `Any`, that contradicts traits §5.2 ("Both offer the same operations and fields, with the same results"). The fix is a T- deviation row against TraitWorld, not a question for the user.
- **What does remain:** under the default, the erased worker is compiled once per value of `V`, not once. That is already recorded as open issues §4 item 35, P8. Nothing new for the user.
- **Fix:**
  - Restate §2.4's expectation from the code.
  - Drop PB-12's "For the user" sentence.
  - Keep G0 (c) as a cheap check of §5.2.
  - Decide the default by its benefit (finding 3).

### 3. (should fix) The dynamic default buys nothing in this step; let the first-seen rule decide

- The graph's type stays in the `Network`'s type (§3.1). So NetworkDynamics compiles everything downstream per graph type anyway.
- What a `Dynamic` graph adds:
  - a run-time split per operation, which is per edge in `find_edge_paths` (`has_edge` for directed graphs);
  - the `Dynamic` path's machinery compiled per new type (item 35, P10).
- **Without a default,** every caller in this step knows the graph's type, so the graph is `Compiled`:
  - NetworkDynamics' constructor (facts code, specialised on `g`);
  - GraphMakie's `map!` closures, which are specialised on their arguments when Makie's compute graph calls them.
- **Fix:**
  - Declare no default in G1.
  - G0 (c) leaves the critical path.
  - Revisit with §3.2 (erasing the graph's type), where `Dynamic` and `Kept{GraphInterface}` are what matter.
  - The traits plan's §1.3 draft had the default. Its reason (helpers compiled once whatever the graph type) holds only after §3.2.

### 4. (should fix) GraphKernels (G5–G6) buys neither time nor correctness, and its reach is wider than §1.2 says

- **Correctness:** by reading, GraphMakie upstream already handles `GenericGraph`'s generators:
  - its helpers iterate `edges(g)` with `src`/`dst`, size vectors by `ne(g)`, and call `all_neighbors`;
  - `edgelist` and `neighborlist` are plain Graphs functions with `AbstractGraph` methods, so plain GraphMakie code may call them without any bound.
  - If G0 (d) plots a `GenericGraph` upstream (finding 9), G5–G6 fix nothing.
- **Reach,** the code that becomes trait code and is compiled by facts in the session (GraphMakie has no precompile workload):
  - `find_edge_paths` reads attributes with `getattr(attr.X, i)`. For a `Makie.Computed`, that is `getattr(o[], …)` (`utils.jl:52`), which reaches Makie's compute-graph `getindex`;
  - `find_start_end_shift` reaches `distance_between_markers` (marker geometry), `point_near_offset` with `to_px`, a closure over `project(sc, point)` (the scene's projection), and `inverse_interpolate` (`recipes.jl:910`–`982`);
  - this is E-153's mechanism: Makie's code compiled by facts in the session. The stop rule (+2 s on step f) may well fire, and the time is spent for a design test only.
- **Fix:**
  - Make G5–G6 conditional on G0 (d). If GraphMakie upstream plots a `GenericGraph`, defer them, and say so in choice 19 and PB-14.
  - If the design test "a trait submodule in a plain package" is wanted, bound a small kernel that reads only the graph. Example: the edge list with each edge's reciprocal flag, `(edgelist(g), [is_directed(g) && has_edge(g, dst(e), src(e)) for e in edgelist(g)])`. Leave the geometry and the attribute reads plain, in the closures. The trait code's reach is then Graphs' code only.

### 5. (should fix) The step's gate and baselines are stale

- E-152 is done. It met criterion 2 but failed criterion 4, and the traits plan's rule then paused the port.
  - §4.4 gates this step on criterion 2 alone.
  - What lets this step start is the meta plan's choice 16: the port continues around open issue 48. §4.4 should cite it.
- "E-152's last commit (S8)" (§1.3, §4.2): the code is c9339fd, S6's commit. S8 is the runs.
- "TraitWorld e9f4bfe or the commit E-152 used" (§4.2): E-152 used a373e30. Name a373e30, so that the comparison with E-152's end is like with like.

### 6. (minor; the answer on P4-1) The family's crossings are cheap here; say why

- Every `AbstractGraph` type is a family member. Every call into a bounded function goes through `_conf_family` (`implement.jl:803`), also from a typed caller:
  - an `IdDict` lookup of the member's builder;
  - a dynamic call of the builder;
  - a dynamic call of the worker on the resulting trait object.
  - From facts code, this machinery has run-time sites (P4-1, lowering §9.3).
- **Here:**
  - NetworkDynamics makes three crossings per `Network`;
  - GraphMakie makes one per helper per resolve;
  - worker-to-worker calls (`find_edge_paths` → `selfedge_path`) are static (lowering §8.1).
  - So the cost is microseconds per construction or resolve, not per right-hand side. Criterion 3's "again" rightly expects nothing.
- **The member check** (inference of eight operations) runs at the first use in each session:
  - the builder registry is a constant of Graphs (`implement.jl:789`–`798`);
  - Graphs has no workload, and NetworkDynamics' `@workload` cannot save Graphs' registry in NetworkDynamics' image.
  - If step b misses its first-call bound, try a `TraitWorld.@workload` in Graphs that enters `SimpleGraph{Int}` and `SimpleDiGraph{Int}` once, before blaming the member check. Builders found by the declaring package's workload are saved with its image (`implement.jl:783`–`785`).
- **Fix:** add this reasoning to §4.1 and to E-154's reading.

### 7. (should fix) G3 passes an `Int` index where the operation declares `v::V`

- `ffvertices = findall(hasff, _vertexm)` is a `Vector{Int}`.
- `neighborlist(g, i)` declares `v::V`. For `V ≠ Int64`, the argument check refuses the call, where upstream's `Graphs.all_neighbors(g, i::Integer)` accepted it.
- **Fix:** convert, `neighborlist(g, V(i))`.
- **Keep `v::V` in the declaration.** An abstract `::Integer` would reduce the member check to "a method exists" (`implement.jl:254`–`263`), and Graphs' throwing fallbacks pass that test.

### 8. (should fix) Check (C) needs a reference per type

- "the `rhs_check.jl` hash of `du` against the `SimpleGraph` network's" holds only for `GenericGraph(g)` and `SimpleGraph{Int32}(g)`.
- `SimpleDiGraph`, `GenericDiGraph`, `ReverseView` and `UndirectedView` of a `SimpleDiGraph` have other edges, or another edge order.
- **Fix,** a reference per type:
  - `GenericGraph(g)` against `g`;
  - `GenericDiGraph(d)` against `d`;
  - `ReverseView(d)` against `reverse(d)`;
  - `UndirectedView(d)` against `SimpleGraph(d)`, after checking that the edge order agrees;
  - `SimpleGraph{Int32}` against `Int64`, if it builds.

### 9. (should fix) G0 (d) is not optional

- The `graphtype` pass runs step f (`graphplot(get_graph(nw); layout = Spring(…))`), and criterion 2 needs steps b–f to pass.
- Several reads of the `GenericGraph` in that pass are outside the step's bounds:
  - GraphMakie's `getedgekeys` (SimpleTraits);
  - NetworkLayout's extension (`adjacency_matrix(g)`);
  - `digest_b`'s `is_connected` and `edges`.
- Know before G1 whether they work upstream. The answer also decides finding 4.

### 10. (should fix) Criteria 0 and 3 compare four passes with three

- U has no `graphtype` pass that runs: it fails at step b. E-152's runs have three passes.
- **Fix:**
  - criterion 0: the three common passes `--exact` against U; the `graphtype` pass against the same session's `first` (criterion 2);
  - criterion 3, "the session": over the three common passes; the `graphtype` pass reported apart;
  - check that `compare_digests.py` tolerates the extra pass and the `D graphtype … error=` lines.

### 11. (should fix) G7 changes the shared harness while P6 is using it

- `run_workload.sh`, `workload.jl` and `workload_steps.jl` serve every setting, P6's `I` included.
- **Fix:**
  - The change is additive and off by default: without `NDW_GRAPHTYPE`, the output is byte-identical in format and content.
  - It is one commit, and P6's agent is told before it lands.
  - Alternatively, put the pass in its own script that includes `workload_steps.jl` and leaves the shared files alone. `step_b`'s new keyword then stays the only shared change.

### 12. (should fix) Names that collide

- **Settings `P4-1` and `P4-2`** (§4.2, E-154's row) collide twice:
  - with pushback P4-1 and P4-2;
  - with E-152's run logs `logs/p4-1/P4-{1,2}.log`.
  - "The steady state against P4-1" in E-154's row is ambiguous. Rename them, for example `P4s1` (E-152's end) and `P4s2` (this step).
- **PB-11 to PB-14:** the log numbers its entries by part (P3-1, P4-1, P4-2; the traits plan's PB-4 and PB-7 became P4-1 and P4-2). Write them as P4-3 and on. Log IDs are permanent.
- **Choices 15–22:** the meta plan already has 15 (E-152's departures) and 16 (the port continues around open issue 48). Number on from 16.

### 13. (minor; the answer on PB-13) The extension question is real, but not for the user now

- **The rule refuses it.** An implementation in an extension must mention each trigger, and each trigger must own the trait or a type the declaration names (traits §10.1). TraitWorld, the trigger, owns neither.
- **The rule's reason does not bite in this case.** The reason is that a call's view should not depend on whether a package happens to be loaded. An extension that declares the trait itself exists only when TraitWorld is loaded, so the trait and its implementation appear together.
- **But the form is poor regardless.** An extension's names reach consumers only through `Base.get_extension`, so NetworkDynamics and GraphMakie could not name `GraphInterface` plainly.
- **The design already has a conformant answer:** a small package holding the trait and the family (§1.1, row 4). It is the trait's owner, implements for foreign subtypes by their existing methods, and adds new functions with `AbstractGraph` methods (not pirates). The plan rejects it only as "a second home".
- **For the port,** TraitWorld is loaded everywhere, so Graphs' hard dependency costs nothing measurable.
- **Fix:**
  - Record PB-13 as pushback, with the split package as the conformant form.
  - Raise an open issue only when a package outside the port is to declare a trait, and the user wants it without a second package.

### 14. (minor) Spelling and accuracy

- **The import.** `using TraitWorld: @trait, @implement, @default_with_dynamic_self`: no such macro exists. `@trait` reads that line syntactically (`trait.jl:216`–`233`). Importing it warns at Graphs' precompile. Import `@trait` and `@implement` only (moot if finding 3 is taken).
- **Unqualified operation names.** They reuse Graphs' functions because `@trait` emits `function nv end` in the declaring module, which is a no-op for an existing function. Traits §3.1 says a plain name "creates a new function". Qualifying (`Graphs.nv`) states the intent without relying on that.
- **The name `Graph`.** Inside Graphs, `@trait Graph` would fail outright: `const Graph = SimpleGraph` (`Graphs.jl:496`). The silent typed method is the hazard of a trait of that name declared in another package. Both belong in §8's choice 15.
- **§2.3 on iterator types.** T-37 is not why a family cannot state an iterator type. The reason is that Graphs has no type-level function for it (no `edgeitertype(G)`).
- **`neighborlist`.** It collects `all_neighbors`, but in Graphs `neighbors` means the out-neighbours. A name such as `all_neighborlist`, or at least a docstring saying "in and out", avoids the mix-up. For choice 17.

### 15. (minor) Environments, depots, settings

- **GT.** Graphs' test files need its test environment (`test/Project.toml`: StableRNGs, Unitful, DelimitedFiles, JET, IGraphs, NautyGraphs, …) and the helpers at the top of `runtests.jl` (`testgraphs`, `KMf` through Unitful).
  - Name the environment and check that these are in the depot offline.
  - Or drop GT: the change adds a file and methods, and P and C cover it.
- **The cache cap.**
  - NetworkDynamics has been built into `depot-p4` at S0–S6 and will be rebuilt at G1–G3 (and G4). Julia keeps ten cache files per package and evicts the oldest.
  - E-152's image of c9339fd may be evicted, so a rerun of E-152's setting rebuilds. State it.
- **Pin TraitWorld.** E-152's S5 note shows a TraitWorld move mid-step recompiling NetworkDynamics (51 s). P6 and open issue 48's work may move TraitWorld. Pin E-154 to a373e30, or record the commit and rerun the baseline.
- **G0 in `env_port`.** It loads the live TraitWorld into the default depot that P0 uses. If TraitWorld moved since `env_port`'s last build, G0 rebuilds it there. Harmless, but say it, or run (b)–(c) in `env_p4` with `depot-p4`.
- **CLAUDE.md rule 5.** The settings name the build, strict mode, the load order and the runs. Add the machine's load.
- **G4.** Upstream's `Graphs.degree(im.g)` is generic over `AbstractGraph` and works for every type in §2.5. G4 adds a third consumer, not a fix: optional.

### 16. (minor) E-154's row

- It follows E-152's form, "would change the plan". Apply:
  - finding 1 to question (1);
  - finding 12's names to question (3);
  - finding 2 to question (5): the expected answer, and that a negative answer is a deviation row, not PB-12.
- Name the builds: the julia-1.13 commit and TraitWorld a373e30.

## The questions asked, in short

1. **Correctness against Graphs 1.15, GraphMakie 0.6.6 and the port's NetworkDynamics:**
   - the declaration, the family's first-use checks and the throwing fallbacks are correct (verdict);
   - the `Graph` alias clash is real, and inside Graphs the name is impossible (finding 14);
   - it runs in today's spelling, except the import (finding 14) and G3's index type (finding 7).
2. **Where it lives:**
   - Graphs as plain code: sound;
   - `GraphKernels`: not sound as planned (finding 4);
   - P4-1's per-call costs apply to every member, but the crossings here are rare (finding 6).
3. **Timing:** go now, trimmed; neither P6 nor open issue 48 is a reason to wait (recommendation above).
4. **PB-12 and PB-13:**
   - PB-12 is not real as framed; at most a deviation if G0 (c) shows `Any` (findings 2, 3);
   - PB-13 is real; the split package answers it within the design; not for the user now (finding 13).
5. **Checks, the row, CLAUDE.md and the other tracks:** findings 1, 5, 8–12, 15, 16.
   - No conflict with P6's trees, environments or depots: P6 never touches `pkgs/Graphs-p4`, `pkgs/GraphMakie-p4`, `env_p4` or `depot-p4`, and reads the main clones, which this plan leaves at `upstream`.
   - Step 1's diff (`upstream..c9339fd`) does not touch the lines of G2–G4.
