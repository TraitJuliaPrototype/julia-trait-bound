# Concrete questions for Julia core developers

Context: `universe_filter_v3.patch` (~170 lines on v1.12.2) implements
sealed resolution below the matcher, task(thread)-scoped sealed dynamic
dispatch, and a sealed dispatch cache. All measured working (tests in this
directory). These questions are where our PoC choices need core-dev judgment
before this could become a PR series.

## Q1 — Where should the universe live on a CodeInstance?
Sealed-compiled code currently exists only as OpaqueClosures (package side)
or implicitly via the global filter. For universe-keyed compilation we see
three options: (a) reuse `cache_owner` with a universe token — works today
but excludes such CIs from pkgimage native code entirely (as we measured:
foreign-owner CIs get `native=false`); (b) a new `universe::UInt64` field on
CodeInstance, part of cache identity; (c) keying by a separate overlay-style
method table per universe. Which direction would upstream entertain? Is (b)
serialization-feasible in staticdata without a format break?

## Q2 — Native-code retention policy for universe-keyed CIs.
We measured (X9, repo notes): workload-compiled foreign CIs survive in
pkgimages with `cache=true, max_world=∞` but `native=false`, costing ~240 ms
of pure LLVM re-codegen per session for a Makie-scale stack. Where exactly
is the drop decision made in the current pipeline (jl_precompile /
staticdata native-code selection), and would a "retain native for CIs
carrying a universe key" rule be acceptable? Within a sealed universe the
usual cross-image method-identity hazards should be excluded by
construction — is that reasoning sound, or does relocation/root layout make
foreign native code fundamentally harder than we think?

## Q3 — Task-scoped vs thread-scoped sealed mode.
PoC puts `sealed_mode` on `jl_tls_states_t` (thread) because adding a field
to `jl_task_t` touches the Julia-visible Task layout. Correct semantics
want task scoping (migration safety). Options: a real `jl_task_t` field, or
piggybacking ScopedValues (but reading the scope chain in the dispatch hot
path seems costly). What is the acceptable mechanism for a per-task flag
consulted in `jl_apply_generic` at ~zero cost?

## Q4 — Filtering below the matcher vs separate method tables.
Our filter skips non-universe methods inside `ml_matches_visitor`, which
correctly recovers universe methods shadowed by more-specific outside
pirates (impossible with post-filtering — we verified both). Alternative:
one `jl_methtable_t` per universe with methods inserted at enrollment.
1.12's typemap/methtable machinery: which approach composes better with the
leaf/full caches and world-splitting, in your view? Is there prior art we
should copy (overlay tables in GPUCompiler are additive, ours is
subtractive)?

## Q5 — Validity semantics for sealed results.
Our filter deliberately does NOT narrow `min/max_valid` for skipped outside
methods, so sealed CIs and cache entries stay valid across pirate
definitions ("immortal workers" — the desired semantics). Is piggybacking
world-validity this way sound with respect to the invalidation machinery,
or do we need an explicit "universe epoch" dimension so that enrollment
changes (the only legitimate invalidator) can be distinguished from
world advancement?

## Q6 — Enrollment metadata (ties to issue #54903).
We want a per-package Project.toml marker to set an enrollment bit on
methods at definition time (jl_method_t flag from the defining module).
Is loading.jl the right place to stamp modules, and would a
`dispatch_status`-adjacent method flag be acceptable, or should enrollment
stay entirely at module granularity (as our PoC has it, via parent-chain
walk at match time — measured cost is small but nonzero per match)?

## Q2 addendum — exact policy sites, from experiment (branch p2-experiments)
The native-code selection for pkgimages is: `precompile_utils.c`
`precompile_enq_all_specializations__` walks ONLY worklist-module methods;
`precompile_enq_specialization_` skips `codeinst->owner != jl_nothing`
outright ("TODO(vchuravy) native code caching for foreign interpreters")
and requires `jl_ir_inlining_cost(inferred) == UINT16_MAX` for standalone
native. Measured consequences: a workload-created foreign specialization of
a LARGE (non-inlineable) method DOES get native code today; the X9 gap is
specifically (a) inlineable foreign CIs reached by runtime dispatch (kept
as IR per staticdata.c:931, re-codegen'd every session) and (b) custom-owner
CIs. Sharpened question: would a rule "emit standalone native for
new-in-this-image foreign CIs regardless of inlining cost when <condition>"
be acceptable, and what should <condition> be — universe membership, a
dispatch-observed bit, or an explicit precompile directive? Our env-gated
experiment (JULIA_PRECOMPILE_FOREIGN=1, patch v4) enqueues foreign
new-in-image specializations; scale measurement (many mid-size functions,
the Makie shape) is the pending next step.

## Q2 — REVISED after the scale experiment (see session-notes 09)
Measured: the ~460-490 ms/100-fn per-session re-codegen constant for
dispatch-reached foreign inlineable CIs is identical on 1.11.7 and 1.12.2;
PrecompileTools' newly-inferred tagging (CI `precompile` flag) fully
eliminates it (0.0 ms); raw policy patches (enqueue foreign + drop inlining
gate) emit native that is NOT honored at load for execution-created CIs.
Revised questions: (a) is the CI-tagging path the intended long-term
mechanism for foreign native retention, and what exactly disqualifies an
untagged execution-created CI at image load (edges? MI identity)?
(b) why do Makie-shaped loads still pay ~240 ms on first plot despite
@compile_workload tagging — window coverage or load-order invalidation of
tagged CIs — and what instrumentation would you accept to find out?
(c) should universe/sealed compilation imply tag-everything-reached?
