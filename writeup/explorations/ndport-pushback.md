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

