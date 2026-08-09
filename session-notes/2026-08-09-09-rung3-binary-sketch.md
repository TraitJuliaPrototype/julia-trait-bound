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

## P1b IMPLEMENTED AND PASSING

`binary/universe_filter_v2.patch` (117 lines total): per-thread
`sealed_mode` flag (jl_tls_states_t, appended pre-#ifdef),
`jl_set_sealed_mode` (save/restore semantics), and a sealed branch in
`jl_apply_generic`: while a universe is set AND sealed_mode is on, every
dynamic call resolves through the FILTERED matcher, bypassing all dispatch
caches (uncached per call — universe-keyed caches are P2).

Test (`test_sealed_dispatch.jl`): pirate `Base.sort(::Vector{Float64})`
defined BEFORE any sealed compilation, reached through a `Ref{Any}` witness
slot — live call takes the pirate (4.0); `sealed_call` returns 3.0.
**X11's residual hole (pre-compile pirate + dynamic call) closed natively.**
P1a test still passes on the same binary.

PoC caveats recorded: sealed dispatch is uncached (slow; P2 fixes);
compilation inside sealed frames unsupported (warm outside first);
thread-scoped, so no task migration mid-sealed-frame; static call sites
inlined pre-sealing are covered by P1a-compiled workers, not this flag —
full coverage = P1a compilation + P1b dispatch together.

Gotcha for future rebuilds: `(make; echo EXIT $?)` backgrounding masks make
failures — check the log, not the task exit code.

Next: TraitRegions native backend (`sealed` uses jl_set_sealed_mode when
available); P1c enrollment bit from Project.toml; P2 universe-keyed caches.

## P2 opener + core-dev questions (tag rung3-p1 set first)

Sealed dispatch cache (direct-mapped 1024, keyed on interned dispatch
tuple, world-bounded, flushed on universe change; rooted via
jl_as_global_root): **91 ns/call sealed vs 37 ns plain (54 ns overhead)**,
down from µs-scale uncached. Both P1 tests still pass. Immortality carries
into the cache (filtered matches don't narrow validity). Patch now
universe_filter_v3.patch (~170 lines).

`binary/QUESTIONS.md`: six concrete core-dev questions (CI universe keying
vs cache_owner; staticdata native-retention rule; task- vs thread-scoped
flag; filtered matcher vs per-universe tables; validity/epoch semantics;
enrollment stamping in loading.jl). These mark the exact edge of what we
could build without upstream judgment — P2 proper (CI keying + staticdata)
should not proceed without answers to Q1/Q2.
