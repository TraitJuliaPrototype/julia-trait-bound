# 2026-10-13 — Session 12: design reset (closure rule), concrete mode

## Design reset (Claude Doc, rev 48–62)

The user moved the baseline from the edge-level rule to the closure rule:
trait-bound modules depend only on trait-bound modules, and trait-bound code
handles only their values (type closure added in discussion). Decisions:
Base, Core and the standard libraries are trait-bound by designation (one
owner); mechanism B, each specialization compiled against the methods of its
closure, with a fail-safe dispatch check; the edge-level rule is set aside;
calling ordinary code is deferred (the user wants a dynamic import that
states its assumptions, not a "trusts" level). The thesis now promises
interactivity, simple AOT compilation and no performance cliffs. The note was
rewritten in place (51.8k to 30.4k characters), diagrams updated.

## Concrete mode (opt-in), built

The user's main practical cliff: an abstract type deep in a package hierarchy
reaching a hot loop, hard to debug through many layers. Decision: opt-in
concrete mode, `@warn_on_abstract` / `@error_on_abstract` on a region or op.

- `TraitRegions/src/concrete.jl`: `concrete_findings(worker, argtypes)`,
  `check_concrete(trait)`, `AbstractTypeError`, the macros. Walks the
  region package's own code on normal paths (reusing verify.jl's error-path
  analysis), flags abstract uses (dynamic calls, field reads on unknown
  values, abstract returns and widened result types), marks loops (back
  edges), and traces each use to a root: abstract field, boxed variable
  (named from the lowered code or the closure field), type-changing
  variable, container with abstract element type, non-constant global,
  abstract declared result. Traces cross packages (invokes descend into the
  callee's abstract return), try every abstract input, and stop at cycles.
  Lines are the innermost frame in a user file.
- Guard: `GuardState` gains `concrete` and `concrete_ok`; the check runs in
  the slow path once per (op, R), independent of the piracy mode; error mode
  throws every call; warn mode warns once; results of checks during the
  region package's own build persist in its image. `precompile_seal` runs it
  for conformers.
- `@region`: accepts `concrete = :warn|:error` (inserted by the outer macro),
  per-op annotations in any order with `@full_compile`; asserts every witness
  result to the trait's declared type (`_wret`, folds to a typeassert); the
  worker's source location is the op's own.
- Tests: 77/77 (13 new). Error-split scenarios, both observe suites and the
  trim builds unchanged.

## Results

- `poc/concrete`: four packages, `Config.scale::Real` three calls below a hot
  loop. The warning appears while CTop is built and names
  `field scale of CBottom.Config is declared Real (CBottom.jl:6)` with the
  chain through CMid2 and CMid1. Later sessions: no warning. Cost of the
  cliff: 66.2 vs 0.89 ms over 10^6 elements, 74×.
- Ecosystem, nothing annotated, `check_concrete(ColTable)` 1.3 s:
  `histcounts` 1 root (boxed `lo`, ColPlots.jl:35; 16 uses, 10 in loops);
  `histplot_naive` traced into `GridLayoutBase.top_parent`; all else clean.
  One check 5–27 ms warm.
- Correction: earlier notes said `histcounts` boxes `lo` and `w`; only `lo`
  is boxed (it is captured and reassigned); `w` is merely abstract because it
  is computed from `lo`.

## Next

- Concrete mode by default for workers (warn)? Measure false positives on
  more packages.
- Keep conformer-side check results (a conformer cannot persist into the
  region package's image).
- Flag witness calls inside loops (the design's own indirect-call cliff).
