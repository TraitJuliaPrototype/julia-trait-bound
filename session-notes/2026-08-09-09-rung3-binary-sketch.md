# 2026-08-09 — Session 09: sketch — PoC Julia binary with full Rung-3 support

Feature list: enrollment → universe id → sealed resolution (static+dynamic)
→ compiler-managed seals → universe-keyed native caching → devirtualization
→ AOT over closed universe.

**Load-bearing bet: seals-as-methods** — seal = method of hidden generic
`seal_info(::Type{Trait}, ::Type{T})`. Gets serialization, world-consistent
updates, and deletes the __init__/reinit dance via existing method-table
merging. Testable as P0 TraitRegions refactor, NO FORK (~2 wk).

Fork subsystems:
1. Pkg.jl + base/loading.jl: [strict] traitbound parsing; module enrollment
   bit; universe id at load; jl_method_t enrollment flag (src/julia.h).
2. src/gf.c: universe parameter in ml_matches/jl_matching_methods, filter
   BELOW the matcher (A5/X11 finding: post-filter provably wrong). Dynamic
   dispatch from sealed frames: task-state current-universe consulted by
   jl_apply_generic (closes the residual pre-compile-pirate hole).
3. Compiler stdlib: thread universe through inference (cache_owner-style);
   CI universe key. Stage-A interpreter is the seed.
4. Entries → direct universe-keyed invokes, not dispatchable methods
   (kills max_methods artifacts; native cache keys (region,op,Trait,R,u)).
5. staticdata.c: retain NATIVE code for universe-keyed CIs (fixes X9's
   cache=true,native=false; safe because universe id governs validity).
   Hardest file; biggest payoff (~240 ms/session constant dies).
6. Optimizer: witness-splitting devirt pass (recovers fc-ceiling speed
   soundly); juliac/--trim over the universe = closed world.

Staging: P0 seals-as-methods (2 wk, no fork) → P1 matcher+enrollment
(2-3 mo; exit: native X10/X11, all call shapes) → P2 caching (2-3 mo;
exit: ~0 ms incl. session constant) → P3 devirt+juliac binary (2+ mo).
Total ≈ 1 engineer-year. Risks: gf.c/staticdata.c expertise scarcity
(recruit via Discourse post first), world-splitting × filtered-matcher
bugs, upstream tracking (shape stages as PR series, not divergent fork).
