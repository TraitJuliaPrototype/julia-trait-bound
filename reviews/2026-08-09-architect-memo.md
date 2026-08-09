# Design memo (Fable architect agent): alternatives to sealed resolution

(Verbatim agent output; commissioned 2026-08-09 alongside a parallel critical
review. Summary of designs A-E and the unbundling recommendation.)

## Organizing observation
The measured 456 ms chain (retention solved by PT tagging → killer is
load-order invalidation → scoping eliminates it) never uses sealed
resolution. The dominant win is an invalidation/caching property; the
semantic fork is a separate feature bundled with it. Three responses to an
out-of-universe definition intersecting universe edges:
(i) doesn't apply inside (sealed resolution — fork, not #54903-conformant);
(ii) applies at an epoch boundary (deferred/verified invalidation — no fork);
(iii) never applies and that's an error (edge contracts — exactly #54903's
error-or-identical shape; the design doc's §4.2 dismissal of this is argued
to be WRONG: the error is attributable to the enrolled package's own
declaration, like a Pkg resolution conflict).

## Designs
- **A — Verified deferred invalidation** (no fork, no enrollment): queue
  kills during load, verify at a barrier (re-match; keep native if resolved
  target unchanged). Helps ALL Julia code. Objection: "fix invalidation
  precision" swamp; genuine intersections still recompile. KEY EXPERIMENT:
  measure what fraction of real-world kills (ChurnStorm/CairoMakie over our
  stack) are spurious — ≥90% ⇒ most of the cost class needs no semantic
  machinery; ≤50% ⇒ sealing is load-bearing.
- **B — Epoch capsules**: X10 promoted to user-visible primitive
  (capsule()/run(cap, f) — explicit world snapshots, MVCC framing).
  Staleness diagnostics instead of silent divergence. Needs staticdata
  cooperation cross-session. Objection: freezing freezes wanted definitions
  too; re-freeze re-exposes invalidation cost.
- **C — Universe as ADDITIVE overlay @MethodTable** (least-fork Rung 3):
  enrollment INSERTS methods into a universe table; region code compiles
  under it with no global fallback; sealed dispatch = apply_generic against
  the table. X11's shadowing defect structurally moot. cache_owner = the
  table (answers Q1); witness table IS the method table (answers Q4).
  Politics: "different method table, like GPU code" — accepted Julia.
  Objection: TraitCore cost arrives day one; still needs staticdata fix.
  EXPERIMENT: rebuild X11 on stock 1.12 with @MethodTable + no-fallback
  interpreter; compare vs fork numbers.
- **D — Frozen-edge contracts** (#54903-native): enrolled package declares
  edges frozen; violating definitions are load-time diagnostics
  (warn/error) with blame; remedy = re-precompile epoch bump. Semantics
  never diverge. Needs A or C underneath to actually keep native code.
  EXPERIMENT: flip v5's skip into detect-and-report; count false alarms.
- **E — Compartments** (module-first kernel): @compartment module compiles
  against its Manifest closure snapshot; universe id = hash(resolved
  sub-manifest + source fingerprints) — the right epoch scheme for EVERY
  design. Objection: retroactive conformance contradicts freezing; without
  erasure discipline the compile-cost pathology returns (the trait trio's
  O(representations) result has no home here).

## Recommendation: UNBUNDLE
Sell three separable goods separately (invalidation immunity, native
retention, AOT closure) instead of pricing them all at sealed resolution.
1. Run A's spuriousness measurement FIRST (highest info per effort).
2. Rebuild Rung 2/3 on additive overlay tables (C), not subtractive filter.
3. Minimal upstreamable PR series, none mentioning traits:
   PR-1 staticdata: retain native for tagged CIs with edges inside a
   Manifest-hashed module set (O(1) hash validation);
   PR-2 loading: deferred invalidation barrier + verification;
   PR-3 Base.Experimental: task-scoped method table for apply_generic.
4. Take D (not sealed resolution) to #54903; sealed EXECUTION survives as
   B's explicit capsule API, not ambient semantics.
5. Keep trait/seal/region as a PACKAGE over the kernel (closed tables +
   Manifest-hashed epochs + the three PRs).

One sentence: the measurements prove EDGE-CONFINED, EPOCH-KEYED
COMPILATION; sealed resolution is one policy on top — propose the
substrate, let the policy be an opt-in execution mode.

## Design-A spuriousness measurement: FIRST RESULT (xA_spurious.jl)
`using CairoMakie` over the warmed ecosystem stack, top-match criterion
(is the invalidating method now the most specific match for the killed
signature): **85 mt_backedge-killed signatures → 31 genuine, 54 spurious
(63.5%)**; 176 method-backedge roots unclassified by this first cut.
Caveats: signature-level not call-site-level (rigorous version needs the
killed CIs' inferred argtypes); one churn source; single run.
Interpretation: between the memo's decision thresholds — deferred
verification (Design A / PR-2) would recover roughly two-thirds of this
channel with no semantic machinery, and universe scoping remains
load-bearing for the remaining third. Both halves of the unbundled
proposal are justified by the same measurement.

## 1.12 rerun (scripts12, stock 1.12.2): spuriousness PERSISTS
667 mt_backedge-killed signatures during `using CairoMakie`: 283 genuine,
**384 spurious (57.6%)** by the top-match criterion (1.11: 63.5%). 1.12's
added precision machinery (interferences, missing-edge morespecific check)
has not eliminated the class. Decision: build the env-gated
verify-before-kill (JULIA_PRECISE_INVALIDATION) at the typename-backedge
kill site and evaluate against the Julia test suite. Baseline established:
patched binary passes worlds 148/148 and core/reflection/misc/invalidation
8,636,166/0 with the filter off.

## Precision patch built and partially evaluated (patch v6)
Env-gated (JULIA_PRECISE_INVALIDATION=1) verify-before-kill at the
typename-backedge kill site: before invalidating, re-match the backedge
signature in the new world (lim=1, no ambiguity); kill only if the new
method wins; any doubt → kill as before (conservative). Evidence so far:
- worlds 148/148 PASSES with gate ON (invalidation semantics preserved);
- genuine-kill control still invalidates (correct), with measured
  verification overhead ~+1.3 ms/check at insertion time — the concrete
  argument for Design A's BATCHED verification at a load barrier rather
  than eager per-kill checks;
- pending (running): broader gated suite + CairoMakie-load kill-count A/B
  on the patched binary.
