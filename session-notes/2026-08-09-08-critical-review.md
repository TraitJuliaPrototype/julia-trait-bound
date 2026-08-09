# 2026-08-09 — Session 08: independent critical review (subagent, verbatim summary)

Verdict: **the sharing/TTFX core (C1/C2) survives scrutiny; the
invalidation-immunity and sealed-resolution claims as currently demonstrated
do not.** Do not post the draft without addressing A1, A2, B1, B2.

## Blockers (each independently sinks the headline)

- **A1 — X11 territory sealing does not cover dynamic dispatch.** The sealed
  interpreter restricts inference-time lookup only; runtime dispatch (the
  exact shape of our Function-typed witness tables) resolves in the global
  table — verified: a pirate reached through a Ref{Any} call runs INSIDE the
  sealed OC. "Closure rule enforced" holds only for static calls.
- **A2 — X10 immunity evaporates on the next registration.** Every
  register! bumps UNIVERSE_WORLD to current world, adopting all pirates
  defined since. Verified: seal one unrelated type → sealed result changes.
  Immunity of a frozen instant, not a mechanism.
- **B1 — X4 "zero invalidation under churn" doesn't discriminate**: the
  plain twin ALSO scored zero (notes admit it; writeup omits the control).
  Only X10's deliberate pirate discriminates.
- **B2 — X8's 8.5× Makie number has three confounds**: (a) an ordinary
  "bin-then-plot" function achieves the same flat cost with zero trait
  machinery — the experiment measures idiom vs idiom, not the mechanism;
  (b) region registration cost sits outside @timed; (c) one lexical closure
  site shares witness types across all "types", hiding per-type witness
  compile (~5-10 ms) — the M0 notes flagged this artifact, X8 fell into it.

## High-severity correctness

- A3: OP_WORKERS has no duplicate check — cross-package silent op hijack
  (piracy-shaped hazard reintroduced by our own registry).
- A4: un-inferable `project` ⇒ R=Any ⇒ ALL seal checks silently skipped
  (C5 degrades to silence exactly for ill-behaved conformers).
- A5: SealedMT recovery incomplete: only fires when keep is empty (mixed
  shadowing case wrong); ambig/valid_worlds copied stale; morespecific on
  full sigs ≠ call-site specificity; no recovery for closures (no
  ft.instance); findsup unfiltered ⇒ invoke sees pirates.
- A6: fingerprint hashes (sig,file,line) — blind to in-place body edits
  (re-include workflow); universe_id blind to region-op body rewrites,
  unstable across sessions (objectid hashing) — cannot validate persisted
  caches as the design assigns.
- A7: no thread safety anywhere (registries, UNIVERSE_WORLD).
- A8: Pkg.test broken (no test target for Test); testset pirates Base.sum
  in-process, order-fragile.

## Writeup overclaims

- X10 time-pinning conflated with §4.2's territory-based sealed resolution.
- "growing-with-stack-size" asserted but never measured (grid is a TODO).
- Headline "dramatic" leans on M0 numbers + confounded X8; ecosystem-scale
  is 25→14 ms.
- X10's 60-73 ms recompile contrast is session-wide, not stack-specific.

## Design holes to acknowledge

- Piracy INSIDE the universe (enrolled module pirating Base at R's types)
  is fully allowed — bounded invalidation is statistical again with ≥2
  members.
- Flat (trait, opname) namespace = cross-package clobbering by design.
- Witnesses that are existing generic functions (ncols = Base.length) make
  fingerprints drift on ANY unrelated length method → false invalidation.
- sealed()/dyncall single-trait by key structure; OC lifecycle unmanaged.

## What is solid (reviewer-verified)

- t-escape check structurally robust (worker never receives t; @locals
  probe empty; broadcast/interpolation/kwargs all conservatively rejected).
- C1 sharing (1 concrete worker MI per representation) and pkgimage worker
  ownership (X2/precompile_seal) real and reproducible.
- X10's mechanism internally correct for its snapshot — and STRONGER than
  X11 on dynamic calls (invoke_in_world pins the task world, covering
  witness dispatch; the interpreter does not).
- Honest negatives (X3 5×@16, X7 no-win, X9 native=false diagnosis) and
  candid session notes; overselling concentrates in the Discourse draft.
- The jl_matching_methods shadowing observation stands, though the
  workaround built on it is incomplete (A5).

## Repair plan (priority order, next session)

1. Reframe writeup: drop/qualify "enforced not linted" (A1), present X10 as
   snapshot semantics (A2), show X4's control (B1), re-run X8 with
   per-type closure sites + registration inside @timed + a "bin-then-plot"
   third column (B2). 2. Fix A3 (duplicate-op error), A4 (opt-in strict
   mode: error when R=Any), A8 (test target + sort-based test). 3. Note A5/
   A6/A7 + inside-universe piracy as stated limitations. 4. Interesting
   synthesis: combine X10+X11 (world-pin AND table restriction) to cover
   both static and dynamic calls — likely the honest Stage-A endpoint.

## Repair status (same day)

- FIXED A3: register_op! errors on cross-package op hijack.
- FIXED A4: un-inferable `project` is now a seal-time ERROR, not a warning.
- FIXED A8: Test target added (Pkg.test works); Base.sum piracy removed
  from testset. All 23 tests pass post-fix (1.11.7).
- RESOLVED A1 (better than expected): X11 rewritten with measured scope —
  territory seals static calls incl. pre-compile pirates; the OC's own
  creation world seals dynamic calls against post-compile pirates
  (discovered during repair: OCs pin dynamic dispatch to their creation
  world); residual hole = pre-compile pirate reached dynamically, closed by
  compiling sealed workers at registration time.
- REFRAMED in writeup: X10 as snapshot semantics (A2), X4 with the control
  stated (B1), X8 with honest attribution + registration-cost caveat (B2),
  limitations section now includes inside-universe piracy, fingerprint
  blindness, thread safety.
- DEFERRED: A5 (SealedMT mixed-shadowing recovery), A6 (content-based
  fingerprints), A7 (locks), fair X8 rerun with per-type closure sites and
  a bin-then-plot column, sealed-OC registry wiring. All listed in writeup
  as future work or acknowledged limits.

## Fair X8 rerun (repair, B2 closed)

Per-type registration inside @timed, per-type @eval'd witness closures,
plus a `plainpre` (hand bin-then-plot) control. 6 types, marginal compile:
recipe 999.6/6 ≈ 167 ms/type; region 589.3/6 ≈ 98 ms/type; plainpre
303.9/6 ≈ 51 ms/type. Old 18-vs-155 numbers withdrawn from the writeup.
Honest claim: 1.7× over recipes from boundary erasure; hand-erasure is
cheaper per type still; the trait layer's value over hand-erasure is
guarantees (precompiled reduction, seal checks, invalidation immunity),
not marginal compile. Deferred still: A5, A6, A7, sealed-OC wiring,
op-count scaling grid.

## P0 refactor: seals-as-methods (DONE, same day)

Seal storage is now `seal_info(::Type{Trait}, ::Type{T}) = <Seal>` methods,
defined via `@seal` INTO THE CALLING MODULE (external method extension →
serializes in the conformer's pkgimage, merges at load). Consequences:
- EagerTables/LazyTables/MatrixTables seal at TOP LEVEL, `__init__` deleted
  — the seal-side registration boilerplate is gone, validating the Rung-3
  "seals-as-methods" bet (P0 exit criterion met).
- Enumeration from the method table (`each_seal`), `unseal!` via
  delete_method; universe_id/precompile_seal ported; @trait no longer
  generates registries. All 23 tests pass on 1.11.7 AND 1.12.2; ecosystem
  re-verified (report ops, x1, x6).
- Julia itself enforced the design: eval into a closed module during
  precompile is an ERROR — the method MUST belong to the sealing package.
- Honest trade-off: runtime `register!`/interactive sealing now costs
  ~18 ms (method definition) vs ~7 ms dict — X1 static total 27.5 ms vs
  plain 26.2. The package-path seal (the common case) moves this cost to
  precompile (0 ms at load). Interactive-seal fast path = future work;
  op registry (reinit) not yet converted.
- 1.12 note: a seal defined INSIDE @compile_workload is invisible to calls
  in the same block on 1.12 (strict world age) — seal at top level, call in
  the workload. Fixed in TraitRegions' own workload; the ecosystem
  workloads (1.11-pinned) still use in-block @seal and will need the same
  one-line move when migrating to 1.12.
