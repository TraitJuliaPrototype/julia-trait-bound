# Trait Regions for Julia — Sharpened: Language Extension and Package Prototype

*Companion to `trait_regions_design_space.md`. Goals: small nominal types, bounded invalidation, efficient caching, opt-in concreteness. This revision separates two artifacts that earlier drafts conflated: a **genuine language extension** (§4), for which JuliaLang/julia#54903 supplies the enrollment mechanism, and a **package-based prototype** (§5), which can measure the payoffs but not deliver the guarantees. It also adopts the closure rule: trait-bound regions may only call trait-bound code (§3).*

## 0. Two artifacts, one design — a three-rung ladder

- **Rung 1 — macro prototype** (today, no compiler changes): `@trait`/`@seal`/`@region` macros, FunctionWrapper witness tables, a hand-maintained cache registry. Demonstrates sharing, TTFX, small signatures, and invalidation behavior *empirically*. Cannot make anything sound.
- **Rung 2 — sealed-interpreter prototype** (today, deep internal APIs): compile worker IR under a custom `AbstractInterpreter` resolving against a frozen `Base.Experimental.@MethodTable`, wrap as a world-pinned `Core.OpaqueClosure`. Demonstrates *constructive* piracy-immunity and frozen-world workers for individual functions. Precedent: GPUCompiler/StaticCompiler.
- **Rung 3 — language extension**: a versioned strict subset in the sense of #54903, plus runtime support (sealed resolution, compiler-managed witness tables, native cache keys). Only here do the guarantees become properties of the language rather than of a package's discipline.

The design core (§2) is shared by all rungs; §3–§4 are what only the extension can honor fully; §5 states, per guarantee, which rung delivers what.

## 1. Goals, operationalized

**Small nominal types** — no worker signature mentions the user type `T`; instance counts scale with representations. **Efficient caching** — one worker per key; keys enumerable; persisted code validated by fingerprint; never-seen types reuse existing native code. **Bounded invalidation** — the definitions that can invalidate a worker are finite and frozen; at Rung 3, *zero* under the closure rule. **Concreteness (opt-in)** — abstract representations become boundary errors, not silent cliffs.

## 2. The shared design core

**Seal = commitment point.** `@seal Trait T` fixes: `project(t::T)::R` (all `T`-specific data logic, at the boundary); **interior witnesses** `w` (signatures in `R` only, called by workers); **boundary witnesses** `b` (`T`-specific — `build` for producing ops, optional `writeback` for mutating ops); a **fingerprint** over trait signatures and interior-witness lowered code. Fail-early checks run at the seal (existence, arity, object safety, best-effort return types); duplicate seals error (local coherence); retroactive seals allowed.

**Worker model, discipline by construction.** `@region` rewrites `f(t)` into a tiny per-`T` entry — `s = seal(Trait, typeof(t)); r = s.project(t); y = f_worker(s.w, r); s.build(t, y)` — and a worker `f_worker(w, r)` in which every trait call is `w.g(r, …)`. The worker cannot express access to `t`; a macro-time lexical check rejects `t` escaping into non-trait position (including closure capture). Module granularity: one region, one worker graph, projection once at the edge.

**Witness dispatch: indirection by default.** Workers are keyed **(region, fn, Trait, R, universe)** and call interior witnesses through fixed-signature pointers: one body per representation, unconditionally — bespoke witnesses included, since they arrive as runtime pointers, not compile-time types. Keying on witness-tuple types is rejected (a `T`-proxy exactly where witnesses matter; closures can embed `T` outright). Indirection cost scales with witness-call *count*, so trait signatures should be **chunky**; pure-data seals (empty `w`) make no indirect calls.

**`@full_compile` opt-out.** Same rewritten worker body, but witnesses passed *unwrapped* (a NamedTuple of function singletons): Julia monomorphizes per witness set ≈ per `T`, with full inlining. Discipline is retained by construction; all four guarantees are forfeited for that function, loudly, and its per-`T` instances stay registry-tracked. (This subsumes the earlier "specialized mode": it *is* the fast lowering, not a third semantics.)

**Producing and mutating operations.** Producers: the worker returns `r′::R`; the entry applies `b.build(t, r′)` once at the boundary — `T` never enters a worker. Mutators: sound only if `project` **aliases**; seals declare `aliasing = true`, mutating ops require it or a `writeback(t, r)` boundary witness.

**Associated result types.** Interior returns are declared as functions of `R` (`coltype(R)`), evaluated per key at the object-safety check; erasure forces conformers to *normalize* returns to the declared type (a view-based conformer must materialize — a priced, measurable cost).

**Concreteness, corrected.** `isconcretetype(typeof(r))` is vacuously true; the real check is **deep concreteness of `R`** (fields and type parameters, recursively) — a pure function of `R`, so it runs **once, at cache-key creation**. Checks are per-key; calls are check-free.

**Invalidation within the core.** Workers have no inference edge to any witness (pointers), so witness edits refresh one seal's table and recompile nothing. Residual worker edges are Base/stdlib calls at concrete signatures — the surface the closure rule (§3) then eliminates.

## 3. The closure rule: trait-bound code only calls trait-bound code

Adopted as a design decision: inside a region, every call must resolve to (a) region code, (b) an interior witness, or (c) a region/kernel function of a package that is itself **trait-bound**. Consequences:

- **The piracy surface goes to zero by construction.** No edge from a worker leaves the trait-bound universe, so nothing defined outside it can intersect a worker's call graph. Bounded invalidation stops being statistical ("piracy is rare") and becomes constructive.
- **The universe is a versioned world.** Enrollment metadata plus the resolved set of trait-bound dependencies (versions, seal fingerprints, subset version) hash to a **universe id**. Within one universe, compiled workers are immortal; caches carry the id; a manifest change is the only event that bumps it. This is also precisely a trim/juliac-compatible closed world: the strict corner's AOT story falls out.
- **The cost is a kernel.** Base is not trait-bound, so the universe needs a curated, fingerprinted kernel of primitive operations (`TraitCore`: arithmetic, concrete array ops, allocation) — Rust's `core`/`no_std` bootstrapping problem, stated plainly. Without a credible kernel the closure rule is aspirational.
- **Bifurcation is directional and mitigable.** Dynamic code calls trait-bound code freely; the constraint binds only region-internal *calls*. Enrollment is per-package, but regions are per-module, so a package can expose a trait-bound core inside an otherwise dynamic package and adopt incrementally. And *data* still crosses via seals even where *code* cannot: a dynamic type conforms by projection without its package enrolling.

## 4. The language extension, and issue #54903

Issue #54903 ("strict subsets") proposes opt-in, per-package restrictions declared in Project.toml, organized as versioned collections, with the rule that opting in may turn valid programs into errors but must never change the behavior of programs that still run; motivations include organizational requirements and low-friction language evolution, and commenters insist on Rust-editions-style ecosystem interop. Three implications, in decreasing comfort:

**4.1 It is the enrollment vehicle the closure rule needs.** Per-package Project.toml declaration is exactly the Pkg-visible metadata that makes "only trait-bound dependencies" checkable by the resolver or at load; a versioned collection (`traitbound@1`) is exactly the universe-versioning §3 requires; graduated enforcement (lint → warn → error) matches the contract-strength axis of the original design-space document. Editions-interop maps to the region/fallback boundary.

**4.2 Its non-semantic constraint forces a two-layer decomposition.** The *restriction layer* fits #54903 cleanly — each rule is error-or-identical:

1. In region scope, non-concrete values are accessible only via trait projection (structural; checkable at lowering because the rewrite makes it syntactic).
2. Conformance in-region must be sealed; structural fallback is an error.
3. Interior witnesses satisfy object safety: `R`-expressible signatures, result types declared as functions of `R`.
4. Region calls resolve only within the trait-bound universe (closure rule; checkable against enrollment metadata).
5. Flagged representations pass deep concreteness at key creation.

The *compilation layer* — per-`R` workers, witness tables, universe-keyed caches — is not a restriction but what the restrictions **license** the compiler to do, observationally invisible except for performance. The one genuine fork is rule 6: **sealed resolution** — region code resolves against a method table snapshot of the universe, so a pirate method defined by non-enrolled code *does not apply inside regions*. That is a real semantic divergence between region and non-region evaluation of the same call. It has precedent (overlay method tables already give GPU code different resolution) and it is the only way "zero invalidation" can be a definition rather than a hope; the alternative — erroring at pirate-definition time — cannot work under #54903's model, since strict flags govern the enrolled package's own code, not a stranger's. The fork should be stated, not hidden.

**4.3 The thread supplies the strongest argument for regions.** One commenter warns that strictness must attach to surface/AST/lowered form, never to levels that can be invalidated (inference); another asks for cohesive promises such as forbidding dynamic dispatch. A bare "no dynamic dispatch" flag violates the first constraint — it is an inference-level property. Regions *convert* it into a lowering-level property: after the rewrite, every worker call is structurally a witness call, an intra-region call, or a universe call, and concreteness is a per-key check. Trait regions are a concrete rule set under which the promise commenters want becomes implementable within the constraints commenters impose.

**Extension-only mechanisms.** With the runtime involved: witness tables become compiler-managed and world-consistent, closing the stale-pointer window a package cannot close (a redefined witness is swapped atomically with the world, never executed stale); cache keys `(region, fn, Trait, R, universe)` become native `CodeInstance` keys, serialized in pkgimages and consumed by juliac; and because the universe is closed and enumerable, the compiler may **devirtualize soundly** — witness-splitting over the known conformer set, union-split-style — recovering monomorphized speed at hot sites without per-`T` keys, something no package can do soundly.

## 5. The package prototype, and the gap

The prototype (see `trait_regions_prototype_plan.md`) is Rung 1 plus an optional Rung 2 spike. Its role is **measurement**: locate break-evens, count instances and invalidations, price indirection and boundaries. Per guarantee:

| Guarantee | Extension mechanism | Prototype mechanism | Verdict |
|---|---|---|---|
| Discipline (trait-only access) | lowering rule under strict flag | macro rewrite + lexical escape check | approximated (macro-evadable) |
| Small nominal types | native worker signatures | same, via rewrite | delivered, measured |
| Per-`R` sharing, in-session | native cache keys | registry + wrapper tables | delivered, measured |
| Cross-session caching | universe-keyed pkgimage/juliac | PrecompileTools workload; wrapper tables rebuilt in `__init__` (pointers don't serialize) | approximated |
| Zero invalidation | sealed resolution + closure rule | concrete edges + `TraitCore` allowlist + blame diagnostics | approximated, statistical; Rung 2 spike: constructive for one worker |
| Witness consistency | world-consistent tables | FunctionWrappers + dirty flag | documented hole (stale-pointer window) |
| Fail-early | seal checks as strict errors | macro-time checks, best-effort `return_types` | approximated |
| Concreteness | compiler deep-check at key creation | recursive check at key creation | delivered |
| Closure rule | resolver-checked enrollment | Project.toml marker + load-time lint | approximated (convention) |
| Piracy immunity | pirates invisible in sealed tables | attribution only | hole; Rung 2 demo |
| AOT/trim | juliac over the closed universe | — | not attempted |

## 6. Alternatives that do not achieve the goals

Structural conformance (open set: no enumeration, no fingerprints, use-site errors — remains the fallback outside regions). Documentation-only protocols (the CLOS status quo). Checking-only layers (C++-concepts: fail-early without sharing — kept as a component). Per-`T` monomorphization as the mechanism (Julia's default; survives only as `@full_compile`). Specialized witness keys as the default (`Wt` is a `T`-proxy; rejected previously). Loose concreteness as default; function-only granularity (spikes only).

## 7. Open problems — where a good answer may not exist

Sealed resolution is a semantic fork some will reject, and it is load-bearing: without it, zero-invalidation is unobtainable in principle. The `TraitCore` kernel is the closure rule's real price, and curating it is ecosystem work no design can shortcut. #54903 is an open discussion, not a landed feature — the extension track builds on a moving target, and its stability rule (options may only relax over time) constrains how the `traitbound` collection can evolve. The stale-pointer window is unclosable at Rung 1. Per-element trait surfaces put pointers in inner loops, where `@full_compile` wins and the payoff narrows to coarse-grained operations. Sound seal-time return-type checking below Rung 3 may not exist.

## 8. Lineage, compressed

Swift witness tables and separate compilation; Rust's erased/monomorphized split, object safety, `core`/`no_std`, and editions; C++ concepts' interface checking; Typed Racket's boundary blame and gradual islands; Go's shape collapse; Mojo's static-core-plus-dynamic-fallback; Julia's own overlay method tables as the sealed-resolution precedent. Full survey: `trait_regions_design_space.md`.
