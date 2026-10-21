# The NetworkDynamics port: where the design pushes back

Status: **current; the pushback log of W-32** ([the meta plan](../plans/2026-10-21-networkdynamics-port.md)). Begun 2026-10-21.

The port does not change the design. Where idiomatic code meets a rule of the references and the rule costs the port something, the case is written here. Each entry gives:
- **the code:** where the port met it;
- **the idiomatic form:** what the code would naturally be;
- **the reference:** the rule it meets;
- **what it costs, and whether it blocks;**
- **what the port did.**

An entry that needs the user's decision is also an open issue. A Planned reference part the port needs is a work item, and the port pauses for it.

## P3-1. Type computations that rely on Base's folding (facts §8)

- **The code:** NetworkDynamics' core loop computes ranges with Static.jl's `StaticInt` strides (`src/utils.jl:20–28`, `_range`): `bs.first + (i - 1) * _fullstride(bs)`, an `Int` times a `StaticInt`.
- **The idiomatic form:** mixed arithmetic of static and ordinary integers, resolved by promotion. Static.jl's promotion rule for a static number with a signed integer (`Static.jl/src/Static.jl:602–607`, 1.4.6) gives `promote_rule(Int, Int)`, which is `Union{}` both ways. So `promote_type` falls back to `typejoin`. Plain Julia folds `typejoin` at compile time, because Base asserts it `:foldable`.
- **The reference:** [facts §8](../reference/facts.md#8-asserted-effects). In a frame compiled by facts that has a run-time site, no asserted effect applies. `typejoin` computes on types as values, so its frame has run-time sites, and under the facts owner nothing folds.
- **What it costs:** the results are the same, bit for bit. In NetworkDynamics wrapped as a trait module, every `x * static(n)` dispatches at run time. One right-hand-side call takes 3 ms and allocates 140 kB, and a Tsit5 solve takes 30.2 s against 19.8 ms upstream (E-153, `ndport/logs/p3/N-1-static-upstream.log`, `ndport/logs/p3-dev/hot-N.log`). Nothing warns: the code is correct and slow. `fully_typed` and the dispatch profiler find it at once (`ndport/scripts/p3_sites.jl`, `p3_hot.jl`).
- **Blocks:** no.
- **What the port did:** fixed it where the rule is, in Static.jl. One method, `Base.promote_rule(::Type{<:StaticInt}, T2::Type{<:Signed}) = promote_type(T2, Int)` (`ndport/pkgs/Static.jl`, branch `trait-port`). Static's own tests state this intent (`test/core_tests.jl:80–82`) and pass. With it, the wrapped package is fully typed on that path and its steady state is faster than upstream's. Under `all` the same code runs at plain speed even without the fix, which §8 does not allow: [facts F-16](../reference/facts.md#deviations).
- **What it teaches:** a package that is correct in plain Julia can lean on Base folding its type computations. Under the facts mode it then dispatches at run time. Run the dispatch profiler on the steady state after wrapping a package ([the porting guideline, B5](../intro/porting.md)).

## P4-1. A per-batch crossing into a family member costs more from trait code than a function barrier (lowering §9.3; the traits plan's PB-4)

- **The code:** NetworkDynamics' core loop keeps each batch's model as `Kept{ComponentDynamics}` and calls `run_vertex_batch!(compiled_for(batch.model), batches, k, args)` once per batch per pass (`ndport/pkgs/NetworkDynamics-p4`, `src/coreloop.jl`, `_process_kept!`, commit c9339fd).
- **The idiomatic form:** a library's own family opened at a loop over its data (the guideline's A12). Upstream does the same with a plain function barrier over a `Vector` of batches: one dynamic call, no allocation.
- **The reference:** a family member takes the entry's generic path ([lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)): the trait object assembled behind one dynamic call, the worker selected by a second. When trait code calls it, that machinery is compiled by facts and has run-time sites (`_pmiss`, `_assemble(TraitList, Any)`, `PEntry`; found by `fully_typed`).
- **What it costs:** a crossing from trait code ~13 allocations and 0.8 µs; the same call from plain code 2 and 0.28 µs. A right-hand side 32 allocations and 3.1 µs against upstream's 0 and 0.5 µs; the workload's steady-state solve 46.8 against 15.3 ms (E-152, `ndport/logs/p4/NOTES.md`, `barrier-s6.log`, `barrier-facts-s6.log`). The gain it buys: changing the equations compiles 0.45 s instead of 15 s.
- **Blocks:** the steady-state criterion of the port's first step; not the results.
- **What the port did:** kept the principled shape and stopped before step 2. The user chose the TraitWorld work (open issue 48, closed): family members are served by the table, and the held-value conversions are at fact signatures. Since then a crossing costs ~390 ns and 1 allocation, about a plain function barrier's; a right-hand side 5 allocations; the steady-state solve 33–41 ms against 15.3 ms. The rest is the step's three crossings per right-hand side, where upstream's typed tuple of batches has none.

## P4-2. A package's loop macro receives the trait object bare (the traits plan's PB-7)

- **The code:** NetworkDynamics' `PolyesterExecution` runs batches with `Polyester.@batch`. Its expansion hands the loop's variables to Polyester's own functions (`wrap_type`, `batch`), not inside a closure.
- **The idiomatic form:** the same erased batches as the sequential and threaded styles.
- **The reference:** a trait object passed to a function outside trait modules is refused by the definition check ([traits §2](../reference/traits.md#2-trait-modules), §9); a five-line trait module confirms `TraitUseError`.
- **What it costs:** Polyester keeps its typed batches, so a change of equations still changes the network's type there.
- **Blocks:** no; the sequential and threaded styles carry the benefit.
- **What the port did:** left `PolyesterExecution` typed. Joining it to the erased path would need a rule for trait objects passed through another package's loop machinery: a question only if wanted.

## P6-1. Plain callers lose constant propagation into a wrapped package's `getproperty` overloads (facts §6.3)

- **The code:** SciMLBase's `Base.getproperty` on its abstract types, each a `sym === :x ? … : getfield` switch: `DEIntegrator` (`integrator_interface.jl:833`), `AbstractSolution` (`solution_interface.jl:72`), `AbstractSciMLProblem` (`problem_interface.jl:1`), `AbstractSciMLFunction` (`scimlfunctions.jl:6190`). Their plain callers: DiffEqBase (`callbacks.jl:150–171`, `integrator.sol.stats.ncondition += 1`), OrdinaryDiffEqCore, Tsit5, Rosenbrock, LinearSolve.
- **The idiomatic form:** an interface package overloads `getproperty` on its abstract types; callers write `x.field` and get the field's type by constant propagation of the `Symbol`.
- **The reference:** [facts §6.3](../reference/facts.md#calls-between-the-modes): "No constant propagation crosses the modes." A facts method reached from plain code is still compiled by facts (§6.2).
- **What it costs:** results bit for bit the same. With SciMLBase a trait module, each such field read in plain code infers to the union of the struct's field types, and the code after it dispatches at run time: the steady-state solve 29.2 against 15.0 ms; the first simulation's solve 30.9 against 11.1 s (E-155, S2; `ndport/logs/p6/NOTES.md`; `ndport/scripts/p6_constprop_probe.jl`). Nothing warns.
- **Blocks:** the inside-out track's steady-state check at S2, while SciMLBase's hot callers are still plain.
- **What the port did:** continued within the design; the cost vanished once DiffEqBase was wrapped (S5: the solver's code is then reached from trait code; 98,419 plain dynamic calls down to 5, the solve 16.0 ms). The user decided [open issue 50](../open-issues.md) (closed): constant propagation crosses from plain code into code compiled by facts (facts §6.3, F-17, W-33), for plain users of a wrapped package.

## P6-2. Strict mode refuses a plotting package's `reshape` pirate to protect Base's own code (facts §10.2)

- **The code:** OffsetArrays' `Base.reshape(A::AbstractArray, inds::Tuple{Vararg{Union{Colon,Integer,AbstractUnitRange}}})`, loaded with Makie; Base's compiled `reshape(::Vector{Dict{Symbol,Any}}, ::Val)` holds the fact it would change.
- **The idiomatic form:** a package that extends Base's array API for all arrays, a pirate by the letter, long accepted.
- **The reference:** [facts §10.2](../reference/facts.md#strict-mode) and its note: strict mode also protects plain code of Base and the standard libraries ([traits §10.3](../reference/traits.md#103-strict-mode)).
- **What it costs:** the method stays inactive in strict sessions that load Makie; the workload's results are unchanged; each strict run logs the refusal.
- **Blocks:** no. Present before any SciML package is wrapped.
- **What the port did:** nothing; recorded.

## P6-3. A plain package's extension rewrites a wrapped core's facts at every load (traits §10.3; facts §2.2)

- **The code:** `PreallocationToolsForwardDiffExt`'s `forwarddiff_compat_chunk_size(::Int)` wins at a fact of SciMLBase's keyword body; `SciMLBaseForwardDiffExt`'s `anyeltypedual` methods win at facts of `promote_u0`.
- **The idiomatic form:** extensions that refine a function for a trigger's types, loaded whenever the trigger is.
- **The reference:** an extension's winning method is its parent's change, a stakeholder's: followed, with a warning ([traits §10.3](../reference/traits.md#103-strict-mode)); G2's exception ([facts §2.2](../reference/facts.md#g2)).
- **What it costs:** warnings at every load; SciMLBase's facts code at those sites compiles again; the solvers' load rose from 0.33 to 4.3 s at S2 (with strict mode off too; not yet attributed).
- **Blocks:** no.
- **What the port did:** nothing; the attribution is due with the track's check J.

## P4-3. An informal interface whose functions return open iterators (traits §3, operations' results)

- **The code:** Graphs' `edges` and `all_neighbors` return a generator for `Graphs.Test.GenericGraph` and a different iterator per graph type; NetworkDynamics' index manager reads them (`construction.jl`, `network_structure.jl`).
- **The idiomatic form:** an operation `edges(g::GraphInterface)` whose result is "something iterable of edges".
- **The reference:** an operation declares its result type; an open iterator type per implementation is not one result type, and BaseTraits' `Iterable` does not cover generators.
- **What it costs:** two new functions in Graphs with concrete results, `edge_list(g)::Vector{SimpleEdge{V}}` and `all_neighbor_list(g, v)::Vector{V}`, a copy each at the network's construction. That result type also meets traits T-58 on a `Dynamic` trait object.
- **Blocks:** no.
- **What the port did:** the two functions in Graphs (public, not exported: `edge_list` is a variable name in NetworkDynamics' tests); NetworkDynamics' index manager reads `edge_list` (E-154, G1–G2).

## P4-4. The owner of an informal interface cannot put the trait in a package extension (traits §10.1)

- **The code:** Graphs declaring `GraphInterface` for its `AbstractGraph` interface.
- **The idiomatic form:** an extension of Graphs triggered by TraitWorld, so that Graphs does not depend on TraitWorld.
- **The reference:** an implementation in a package extension mentions each of the extension's triggers ([traits §10.1](../reference/traits.md#101-who-may-implement)); TraitWorld owns neither the trait nor `AbstractGraph`, so the extension is refused, although the rule's reason does not apply where the extension declares the trait itself.
- **What it costs:** TraitWorld a hard dependency of Graphs; Graphs and its dependents precompile again (29 s in `depot-p4`).
- **Blocks:** no. A small separate interface package holding the trait answers it within the design.
- **What the port did:** declared the trait in Graphs as plain code.

## P6-4. Packages' own inference tests fail under the facts mode by design (facts §4.2, §7.2)

- **The code:** SciMLBase's `test/interpolation_tests.jl:157–158` (`Base.return_types(…) <: AbstractDiffEqArray`) and `test/solution_interface.jl:355–396` (`@inferred`).
- **The idiomatic form:** a package pins inference precision with `@inferred` and `return_types`.
- **The reference:** reflection shows facts inference for a facts method ([facts §7.2](../reference/facts.md#72-reflection)); a run-time site's result is `Any`, with no result type taken from the one matching method (§4.2).
- **What it costs:** 5 assertions of 1,555 in SciMLBase's subset; no result differs.
- **Blocks:** no.
- **What the port did:** recorded (E-155, S2).

## P6-5. Run-time `return_type` answers are a large share of the session's new code (facts §7.1)

- **The code:** facts code on NonlinearSolve's path and on the solution's access calling `return_type` (`collect`, `map`, broadcasting) where facts §7.1's rules 1 and 2 do not fold.
- **The idiomatic form:** `map`, `collect` and broadcasting over values whose element type comes from inference.
- **The reference:** [facts §7.1](../reference/facts.md#71-return_type) rule 3: computed at run time by plain inference, under an owner of its own.
- **What it costs:** 2,094 and 2,903 CodeInstances of `:facts_plain_return_type` in the first simulation's steps c and e; part of their first-call time, not measured apart. The plotting load discards 235 of them (order B).
- **Blocks:** no.
- **What the port did:** recorded (E-155, S4 and S7).

## W34-1. A solver's algorithm trait cannot name its integrator per problem (the exploration's PB-A)

- **The code:** DiffEq.jl's solvers are an open set (the user, 2026-10-21): each solver package adds algorithms, and `init(prob, alg)` builds an integrator whose cache depends on the algorithm and the problem's state together.
- **The idiomatic form:** Rust's `trait Algorithm<P: Problem> { type Integrator: Integrator<P>; fn init(&self, p: P) -> Self::Integrator; }`.
- **The reference:** a trait has no input parameters beside `Self` and no associated types that depend on another trait's implementer ([traits §3](../reference/traits.md), §4.6).
- **What it costs:** the algorithm and the integrator are each checked at their `@implement`; the link between them only at the first call, where `solve!` refuses an integrator that does not conform (a `MethodError` with the bound's hint, [traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits)). Forms within the design that check more (a driver bounded by both traits at shared parameters; `init` as an operation of the problem trait) are in [the review of the W-34 plan](../reviews/2026-10-21-w34-sciml-prerequisites.md). Every new solver package meets it.
- **Blocks:** no; the closest form is in [the porting guideline, B6](../intro/porting.md) ("The solvers are an open set").
- **What the port did:** nothing yet; recorded for W-34.

