# 2026-08-09 — Session 05: sketch for the multi-package ecosystem PoC

Status: **proposal** (user-requested sketch; not yet started). Prerequisites
before package work: the two TraitRegions mechanisms in §"Prerequisites".

## Shape: a miniature table ecosystem, built twice

`ecosystem/` monorepo folder, packages arranged like the real Julia data
stack; each region package gets a "plain twin" written in ordinary generic
Julia so every measurement is an A/B comparison.

| package | role |
|---|---|
| `ColTables.jl` | interface pkg: `ColTable` trait + canonical representations (`Vector{Vector{Float64}}`, Float32 variant). Tiny, stable. |
| `ColStats.jl` | region pkg: ~10 stats ops; precompiles workers for canonical R's |
| `ColReports.jl` | 2nd-tier region pkg whose ops call ColStats ops — cross-package worker-level composition (closure rule as code) |
| `ColPlots.jl` | plotting region pkg wrapping **CairoMakie** (headless) — see §ColPlots |
| `EagerTables.jl` | conformer: struct-of-vectors, accessor witnesses |
| `LazyTables.jl` | conformer: lazy/generated columns, bespoke witnesses, introduces a novel representation |
| `ChurnStorm.jl` | adversarial: hundreds of types, methods on Base fns, load-time redefinitions |

## What it demonstrates beyond the current demo

1. **Ecosystem TTFX**: fresh session + new user type + multi-package region
   stack ⇒ compile cost ≈ the user's witness lines, flat in stack size;
   plain twin pays ops × bodies across every package.
2. **Cross-region composition**: currently impossible (the rewrite makes
   every `g(t, …)` a witness call) — the PoC forces the op→worker mechanism.
3. **Worker ownership**: new representation from `LazyTables` ⇒ its pkgimage
   owns the workers, via the precompile-enumeration API.
4. **Invalidation at scale**: ChurnStorm (controlled dose) + Makie load
   (field test) over the full stack vs plain twin.
5. **Universe id v0**: hash (trait pkg versions, seal fingerprints) at load;
   witness edit ⇒ id drift, shows what would be invalidated.
6. **Multiple representations**: worker MIs = ops × R's, flat in #conformers.

## ColPlots.jl — wrapping Makie (user-requested addition)

Makie is the perfect stress case: huge, inference-heavy, canonical TTFX pain.
Build BOTH designs and compare:

- **Design A (naive, deliberately "wrong")**: workers call `CairoMakie.hist!`
  etc. directly ⇒ inference edges from workers into a giant non-trait-bound
  package. Rung 1 permits it; measure the damage (precompilability,
  invalidation exposure, first-call compile).
- **Design B (the design's answer — boundary pattern)**: workers do the
  shared data reduction (binning, quantiles, downsampling → plain
  `Vector`/`Matrix{Float64}`); the *entry* hands plain arrays to Makie on the
  dynamic side. Makie never enters a region; data crosses, code doesn't
  (design doc §3: "bifurcation is directional and mitigable").
- B forces boundary materialization for lazy/view conformers — this prices
  return-normalization (old E6 concern) on a real consumer.
- Practical: CairoMakie headless in the scripts env (no GPU/display; one-time
  multi-minute install+precompile). ColPlots is a leaf — only plotting
  experiments pay Makie's load time.
- ColPlots Design B ops = "reduction + plot spec" ⇒ also exercises
  cross-region composition (wants ColStats workers), so prerequisites first.

## Experiment matrix

| # | question | measurement |
|---|---|---|
| X1 | ecosystem TTFX | fresh session + new type: compile ms, region stack vs twin |
| X2 | worker ownership | which pkgimage holds which workers (--trace-compile, cache flags) |
| X3 | composition cost | ColReports→ColStats worker-level vs boundary-hop, ns/call |
| X4 | churn immunity | ChurnStorm + `using CairoMakie` last: invalidations, both stacks |
| X5 | representation scaling | worker MIs = ops × R's, flat in #conformers |
| X6 | fingerprint/blame | witness edit + pirate: what recompiles, what gets named |
| X7 | Makie A/B | TTFP for never-seen type: Design A vs B vs plain Makie usage |

## Prerequisites (build in TraitRegions first, ~1–2 days)

1. **Op-to-op calls**: `@region` registers each op's worker in a runtime
   `op → worker` table; calls to non-witness `g(t, …)` lower to a
   worker-to-worker call through it (one indirection, no re-projection).
   Risk to watch: world-age / precompile-ordering surprises when region
   packages load in different orders — if it breaks, that's a finding.
2. **Precompile enumeration**: ops register arg types;
   `TraitRegions.precompile_seal(Trait, T)` in a conformer's workload walks
   loaded regions × ops and precompiles workers for the new R.

## Effort

Mechanisms 1–2 days; six packages + twins ~1 day; ColPlots A/B ~1 day;
experiment scripts + results chapter 1–2 days. Roughly M2+M3 sized.

## Amendment (same day): faking native trait support — the three-column convention

User direction: highlight which costs a hypothetical native ("Rung 3") Julia
would eliminate — especially trait-package→trait-package calls — and fake
them in the prototype now.

**Convention: every ecosystem experiment reports three columns —
plain Julia / prototype (Rung 1) / faked-native (Rung 3 ceiling).**
"What the compiler buys" is always the visible prototype↔faked-native gap.

Cost inventory: the prototype already hits the *compile-time* goals; what
native support eliminates is steady-state indirection and optimization lost
at boundaries: seal lookup (~15ns), entry→worker dynamic dispatch, per-call
dynamic witness calls, opaque cross-region calls (no inlining/IPO), and
use-site return asserts (native: from the trait declaration).

Fakes to build:
1. **Declared cross-region imports (the big one, and barely fake)**:
   `@region ColTable imports (ColStats: colmean, covmat) begin ... end`
   rewrites callee ops inside workers to DIRECT static calls
   `ColStats.var"colmean#worker"(w, r, …)` — same trait ⇒ same w/r; no
   re-projection, no op-table, no dynamic dispatch; Julia infers AND inlines
   across the package boundary. This is the call native would emit; missing
   only the guarantees (add load-time check that imports are region ops of
   the same trait). Caveat for writeup: bypasses the runtime table ⇒
   compile-time-binding flavor (why native needs universe/world machinery);
   convention-based, unsound.
   X3 columns: dynamic op-table / static wiring / plain twin.
2. **fc-stack lowering**: whole composed call chain in @full_compile mode =
   optimization ceiling; native's claim = fc speed at erased compile cost
   via sound witness-splitting. Report "% off fc ceiling".
3. **Hoisted-seal microbenchmarks**: time workers with (w, r) in hand ⇒
   isolates entry overhead that native folds into dispatch.

Implementation order impact: prerequisite mechanism #1 (op→worker table)
stays — it is the honest Rung-1 column; the `imports` static wiring is a
sibling lowering in @region, shares the same parsing. Build together.
