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

## P1a IMPLEMENTED AND PASSING (same session, `binary/`)

Julia v1.12.2 clone + 66-line patch to src/gf.c
(`binary/universe_filter_v1.patch`): `jl_set_universe_filter(mods)` +
filtering in `ml_matches_visitor` BEFORE specificity/shadowing + cache
fast-path bypass. Full from-source build + test on the patched binary:

- pirate `Base.sort(::Vector{Float64})` in Main: excluded from matches;
  **shadowed Base.Sort method recovered correctly** — the A5 defect that is
  unfixable from package land, solved natively at the right layer;
- OpaqueClosure compiled under the filter: pre-pirate semantics (3.0) while
  the live world takes the pirate (4.0) — `NATIVE UNIVERSE FILTER: PASS`;
- emergent: filtered methods don't narrow world-validity ⇒ universe results
  stay valid across outside definitions (immortal workers, for free);
- instructive failure: the GLOBAL filter kills any cache-miss dispatch into
  Main while active (even the test's own helpers) — hands-on proof that the
  universe must be TASK-SCOPED (P1b), exactly as the sketch specified.
  Workaround in test: warm Main paths + enroll Base.Compiler (inference
  dispatches into it).

Next: P1b task-local universe in jl_apply_generic; TraitRegions native-filter
backend; P1c enrollment bit from Project.toml.
