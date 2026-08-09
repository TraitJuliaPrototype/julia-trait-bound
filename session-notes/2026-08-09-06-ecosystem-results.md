# 2026-08-09 — Session 06: ecosystem PoC built and measured (X1–X7)

All of `ecosystem/` is up: ColTables (trait), ColStats + ColReports +
ColPlots (regions, incl. CairoMakie), EagerTables + LazyTables +
MatrixTables (conformers; Matrix introduces a second representation),
ChurnStorm (adversary), PlainStack (ordinary-Julia twin). TraitRegions
gained: dynamic op registry (`dyncall`), statically-wired `@region Trait
[Mod.op, …]` imports (faked-native), `@full_compile`, `precompile_seal`
enumeration, `reinit`, fingerprints + `universe_id`. Test suite: 20 pass.
All numbers: Julia 1.11.7, `--startup-file=no`, fresh process per mode.

## X1 — ecosystem TTFX (never-seen type, composed `report` across 2 pkgs)

| mode | register | first-report | total |
|---|---|---|---|
| static (faked-native) | 7.5 | 6.4 | **14 ms** |
| dyn (honest Rung 1) | 7.5 | 6.5 | **14 ms** |
| plain twin | 0 | 25.0 | 25 ms |
| fc (@full_compile) | 8.5 | 34.5 | 43 ms |

Region TTFX cost is flat in stack size; plain grows with it. fc pays per-type
monomorphization by design.

## X3 — steady-state composition (ns/call, report over 6 columns)

| len | plain | static | dyn | fc | hoisted-static |
|---|---|---|---|---|---|
| 16 | 1533 | 2015 (1.31×) | 7712 (5.03×) | 1625 (1.06×) | 1990 |
| 256 | 34325 | 34560 (1.01×) | 40832 (1.19×) | 34249 (1.00×) | 34601 |
| 4096 | 599712 | 591212 (0.99×) | 606152 (1.01×) | 593936 (0.99×) | 599376 |

**Static wiring ≈ plain Julia (the faked-native column erases the abstraction
cost)**; dynamic op-table costs 5× only on tiny bodies; fc ≈ plain; hoisting
the seal lookup adds nothing (entry overhead negligible on composed ops).

## X4 — invalidation immunity at scale

- ChurnStorm (100 types + Base methods + 20 redefinitions): 38 invalidation
  trees, **0 touching our stack**; post-churn compile 0.0 ms (both stacks).
- `using CairoMakie` as field churn: 93 trees, **0 ours**, 0.0 ms after.
- universe_id stable under churn (drifts only on seal changes — X6).

## X5 + X2 — instances scale with representations, not types

13 user types over 2 representations → `colmean#worker`: 3 concrete
instances (2× canonical from erased+raw lowerings, 1× Matrix), NOT 13.
`report#worker`: 2. X2: all worker specializations `cached=true` **before
any call** — served from ColStats'/MatrixTables' pkgimages; the novel
Matrix representation's workers are owned by MatrixTables' image via
`precompile_seal` in its workload (worker-ownership model works).

## X6 — witness edit

Re-seal with edited witness: 23.9 ms (the new witness body's own broadcast —
genuinely new code), nothing else recompiles; fingerprint and universe_id
drift as designed.

## X7 — Makie TTFP (never-seen type, first histogram)

| mode | first-plot total |
|---|---|
| B (boundary: worker reduces, Makie outside) | 270 ms |
| A (Makie inside worker, "wrong") | 245 ms |
| plain Makie on raw Vector | 249 ms |

**Honest finding**: Makie's own irreducible first-plot cost (~230 ms, its
internals compile per-session despite pkgimages) dominates; differences are
process noise. The region machinery adds ~nothing to plotting (B ≈ plain).
Design A did *not* measurably hurt at Rung 1 — it even precompiled. The case
for B is structural (invalidation exposure, closed-world/AOT eligibility),
not measured TTFP — the writeup must say so plainly.

## Where this leaves the claims

Sharing, flat TTFX, churn immunity, representation-scaling, worker
ownership, fingerprint drift: **demonstrated on a 9-package ecosystem**.
The faked-native lowering shows the Rung-3 payoff concretely: erased-level
compile cost AND plain-Julia steady-state speed simultaneously. What Rung 1
cannot show: soundness of any of it (static wiring is convention), and any
plotting TTFP win (that fight is inside Makie).

## Next

Community writeup draft; maybe an op-count scaling grid (X1 at 5/15/45 ops)
for the headline chart; 1.12 smoke test.

## X8 — where Makie DOES show a good speedup (added after X7)

X7 measured only the *first* type; Makie's real per-type cost lives in its
idiomatic integration path: `convert_arguments` recipes drag the user type
through Makie's pipeline, which respecializes per type. The region route
erases the type before Makie sees it. With a warm-up type absorbing the
shared session cost in both modes, marginal cost per additional never-seen
type (6 types, 2 runs, reproducible):

| mode | typical marginal / type | one-time event | 6-type total marginal |
|---|---|---|---|
| recipe (convert_arguments) | **~155 ms, every type, forever** | ~470 ms (type 2) | ~1300 ms |
| region (erased reduction) | **~18 ms** | ~120–350 ms once | ~440 ms |

Also: the warm-up type itself is cheaper (region 209 ms vs recipe 530 ms —
the recipe pipeline compiles through the user type even the first time).
Whole 7-type session: ~0.65 s vs ~1.85 s ≈ **2.9× cumulative; ~8.5× per-type
asymptotically** — and the region curve is flat while the recipe curve keeps
paying ~155 ms per type indefinitely.

Spike forensics: the reproducible mid-run spike in region mode is NOT
invalidation (`@snoop_invalidations`: 0 trees; recompile_time 0) — it is
Julia's `max_methods` union-split heuristic recompiling the script's generic
harness function once its dynamic call site has seen 4 distinct types. One
time per session, position moves with instrumentation, then flat.

## X9 — can the Makie first-plot (warm-up) cost be precompiled away? (Partially — and we know exactly why not)

Chased the ~240 ms region-mode warm-up (X8) to ground:

- Fully package-contained route (`histplot` + `render`, workload-covered):
  still 236 ms compile; second call 0 ms.
- `@snoop_inference`: only ~16 ms is inference; ~254 ms is the ROOT frame =
  **LLVM codegen**. `recompile_time` = 0 ⇒ not invalidation-driven.
- `@snoop_invalidations (using ColPlots)`: 95 trees, **3539 CodeInstances
  killed at load** by Makie's dep chain (FilePathsBase, StaticArrays,
  SparseArrays, JSON, FillArrays…) — real, but NOT the cause of our 236 ms.
- `@recompile_invalidations` around ColPlots' `using` block: +10 s precompile,
  **no change** (247 ms) — confirming the cause is elsewhere. Kept anyway
  (hardens against load-order invalidation; documented as no-op for this metric).
- Direct CI inspection of traced signatures (e.g. `Makie.get_ticks`):
  `cache=true, max_world=∞, native=false` — **the pkgimage kept the inference
  result but dropped the native code** for foreign runtime-dispatch-reached
  methods. The 190 re-JITted signatures are inference-free codegen replays.

**Conclusion**: the remaining ~240 ms/session is a Julia 1.11 pkgimage
native-code retention policy limit, not a Makie-integration or design
problem, and not fixable from package code. A sysimage (PackageCompiler)
or an AOT rung (juliac/trim) removes it; it is once per session and
type-independent — the per-type X8 numbers (18 vs 155 ms) are unaffected.
