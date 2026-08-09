# TraitRegions.jl — Prototype Implementation Plan (Rung 1, plus a Rung-2 spike)

*A pure-Julia package that implements the shared design core far enough to **measure** its payoffs, centered on a manually implemented and maintained compiled-function cache. Per the gap table in `trait_regions_design_sharpened.md` §5, this prototype demonstrates and prices; it does not deliver guarantees — those belong to the language extension. The optional M4 spike (Rung 2) shows constructive piracy-immunity for a single worker on internal APIs.*

## 1. Claims to demonstrate (each falsifiable)

- **C1 — Sharing / small nominal types.** N sealed types over one representation ⇒ O(1) worker compilations and method instances (per-`T` entries reported separately); no worker signature mentions `T`.
- **C2 — Cross-session caching, unconditional.** Workers precompiled into the pkgimage; a fresh session defining a never-seen type *with a bespoke interior witness* runs a region op with near-zero compilation, vs. full compilation for the `@full_compile` baseline. Wrapper tables rebuild in `__init__` (pointers do not serialize) — that cost is measured, not hidden.
- **C3 — Bounded invalidation, empirically.** Heavy unrelated churn (new methods, new seals, a churn-prone dependency) ⇒ zero worker invalidations; editing a witness ⇒ wrapper refresh only, zero recompiles; pirating an allowlisted `TraitCore` function at `R`'s types ⇒ workers invalidate *and* the blame diagnostic names method and module. **(M4)** the sealed-interpreter worker survives the same pirate.
- **C4 — Opt-in concreteness.** Deep-concreteness check runs once per cache key; a `Vector{Any}`-backed conformer errors/warns at key creation while the direct baseline silently runs 10–100× slow; per-call cost is zero by construction.
- **C5 — Fail-early.** Sealing a nonconforming type errors at the seal (trait/type/method named) vs. a deep `MethodError` at use.

## 2. Non-goals

No soundness. No sealed resolution at Rung 1 (M4 excepted, single-function). No AOT/trim. Single trait per region. The closure rule appears only as convention plus lint. Julia 1.10/1.11, version-hedged reflection shims.

## 3. Architecture (~700–1000 LOC core, plus demo)

Modules: `Traits`, `Seals` (checks, wrapper tables, fingerprints), `Regions` (rewrite, `@full_compile` lowering, lexical `t`-escape check), `Cache` (registry, erased store, blame, precompile enumeration), `TraitCore` (the allowlisted kernel), `Checks`, `Metrics`.

### 3.1 Surface and generated code

```julia
@trait ColTable R begin
    ncols(r)::Int
    col(r, i::Int)::coltype(R)      # associated result type: function of R,
    @boundary build(t, r′)          #   resolved per key at object-safety check
    @project  project(t)::R  aliasing=true
end
```

Generates the generic functions with kernel-level defaults, the `seal` fallback ("not sealed" error), and the `SealInfo` layout `(project, w::WTable, build, writeback?, aliasing::Bool, concrete::Bool, fingerprint)`.

`@seal` runs at definition time: duplicate-seal check; existence/arity; object safety (interior signatures concrete in `R`, results per the associated-type functions); best-effort `Base.return_types`; fingerprint. Mutating ops require `aliasing=true` or a `writeback` witness — checked here.

```julia
@region ColTable module ColStats
    colmean(t, i)  = ...
    standardize(t) = ...            # producer → boundary build
    @full_compile kernel!(t) = ...  # same worker body, witnesses unwrapped:
end                                 #   per-witness-set ≈ per-T, fully inlined
```

The rewrite emits entry + worker as in the design core; the lexical check rejects any use of `t` outside trait position, including closure capture (macro-time error). `@full_compile` reuses the identical worker body with the raw witness NamedTuple — discipline by construction survives the opt-out; only the guarantees don't.

### 3.2 The manual compiled-function cache

**Registry.** `Dict{CacheKey, Meta}`, `CacheKey = (region, fn, trait, R)`. Deep-concreteness verdict, seal fingerprints, external-edge snapshot, first-compile time, and hit counts live in `Meta`; the gate therefore costs nothing per call. `@full_compile` instances tracked in a parallel per-`T` table.

**Erased store (default).** Per seal, a `WTable` of `FunctionWrapper`s; one worker per `R`, forced on miss with timed `precompile`. Wrapper rebuild on fingerprint change; a dirty flag driven by an invalidation callback narrows — but does not close — the stale-pointer window; every reinit is logged so it can't masquerade as (or mask) an invalidation.

**Prescriptive allowlist.** The audit is no longer descriptive: worker `code_typed` may resolve only to {region code, wrapper machinery, `TraitCore`}. Any other edge is an audit **error** — the prototype's approximation of the closure rule. The surviving `TraitCore` edges are snapshotted per key for the blame check (load-time and on-demand diff ⇒ "worker K invalidated by method M of module Mod").

**Closure-rule lint.** Enrolled packages set a Project.toml marker (`[traitregions] traitbound = "1"`); at load, a lint walks region edges and warns when they land in unenrolled packages. Convention, not enforcement — labeled as such.

**Persistence.** `@compile_workload` over registry keys; fingerprints + edge snapshots in a Scratch TOML; on load: fingerprint drift ⇒ wrapper rebuild only; edge drift ⇒ blame report + re-precompile of the named keys.

### 3.3 `TraitCore`

A small curated kernel (arithmetic, concrete `Vector` ops, `similar`/allocation) with pinned fingerprints — enough for the demo, honest about being the closure rule's real cost at scale. Curation effort is itself a reported result.

## 4. Demo package: `ColStats`

Representation: NamedTuple of `Vector{Float64}` columns (second `R`: `Float32`). Conformers: 12 same-`R` wrappers; 1 bespoke-witness "lazy" conformer (drives C2); 1 `Vector{Any}`-backed (drives C4); 1 view-based conformer (prices return-normalization under erasure). Ops: `colmean`, `zscore!` (requires aliasing), `standardize` (boundary build), `@full_compile kernel!`. Baselines: the same ops as ordinary generic Julia.

## 5. Experiments

| # | Claim | Method | Pass | Falsifier |
|---|---|---|---|---|
| E1 | C1 | 12 types × ops; worker MIs (MethodAnalysis), compile ns (`cumulative_compile_time_ns`, `--trace-compile`) vs. baseline | 1 worker MI/op; compile ~flat in N | worker MIs grow with N |
| E2 | C2 | pkgimage + fresh process + 13th bespoke-witness type; first-call compile ms incl. `__init__` table rebuild | ≥5–10× below baseline | parity |
| E3 | C3 | `@snoop_invalidations` under churn; witness edit; pirate a `TraitCore` fn at `R`'s types; (M4) repeat vs. sealed worker | 0 / 0 (wrappers only) / >0 with offender named / M4 survives | unrelated-churn invalidations; unattributed piracy |
| E4 | C1 | 30-field parametric conformer: signature length, MI count, stacktrace lines | order-of-magnitude smaller | comparable |
| E5 | C4 | `Vector{Any}` conformer: baseline slowdown vs. key-creation error/warn; verify zero per-call gate cost | silent ≥10× vs. loud error; 0 ns/call | measurable per-call cost |
| E6 | — | boundary cost; erased vs. `@full_compile` on chunky vs. per-element signatures; view-conformer normalization cost; break-even body size | reported | boundary or pointers swamp realistic bodies |

Each experiment is a standalone `julia --project` script so compile-time measurement stays clean. E6 locates break-evens deliberately — possibly the negative part of the answer.

## 6. Milestones

**M0 — spike, no macros (~1 day).** One trait, one chunky op, three same-`R` types (one bespoke witness), erased + `@full_compile` paths; crude E1/E3/E6. *Gates:* wrapper overhead amortizes below noise on a chunky body; pkgimage smoke test shows the bespoke-witness type hitting a precompiled worker; verify empirically whether `FunctionWrapper` executes stale pointers after witness redefinition (sizes the dirty-flag work). Unrelated-churn invalidations here ⇒ the core thesis is wrong; stop.

**M1 — macros (2–3 d).** `@trait`/`@seal`/`@region`, all checks including object safety, associated types, aliasing/writeback, lexical escape check, `@full_compile` lowering.

**M2 — cache and checks (2–3 d).** Registry, erased store, fingerprints, prescriptive allowlist audit, blame, persistence, closure lint, `TraitCore` v0.

**M3 — demo + E1–E6 (2–3 d).** `ColStats`, baselines, scripted experiments, results write-up.

**M4 — Rung-2 spike (2–3 d, optional, kill-tolerant).** Compile one worker's typed IR under a custom `AbstractInterpreter` whose method table is a frozen `Base.Experimental.@MethodTable` seeded from `TraitCore` + the region; wrap as a world-pinned `Core.OpaqueClosure`; rerun E3's pirate — expect survival. Deep internals (AbstractInterpreter, IRCode→OpaqueClosure), version-pinned; failure prices Rung 2 without invalidating Rung 1.

## 7. Risks and honest failure modes

The stale-pointer window is real and only narrowed here — a redefined witness may execute stale until the dirty flag lands; M0 measures the exposure, the extension closes it. `TraitCore` curation may dominate effort and is the closure rule's cost made visible. `OpaqueClosure`-from-IR and `AbstractInterpreter` are unstable internals; M4 may die on version churn — acceptable by design. Per-element trait surfaces put pointers in inner loops where `@full_compile` wins; if chunky signatures aren't natural for the target domain, the payoff narrows to coarse-grained ops and the honest conclusion is that moving the boundary needs Rung 3 (sound witness-splitting). `Base.return_types` and lowered-IR hashing are non-stable — shimmed, degrading to arity/existence. The closure lint is convention: nothing at Rung 1 stops an enrolled package from lying, which is precisely why enrollment belongs in #54903's mechanism, not a package's.
