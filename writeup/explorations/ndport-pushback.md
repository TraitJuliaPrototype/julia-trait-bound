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
