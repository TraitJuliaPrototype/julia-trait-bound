# 2026-08-09 — Session 04: M1 — TraitRegions.jl macro package, working

## What exists now

`TraitRegions/` — the real package (~330 LOC, dep: PrecompileTools only):

- `@trait Name begin method(r, args...)::Ret ... end` — generates trait tag
  type, seal registry (`IdDict{Type,Seal}`), declared-method table. `Ret` may
  be `R` (the representation itself). **Top-level only** (defines structs).
- `@seal Trait T begin project(t)=...; witness(r,...)=... end` — collects the
  definitions as anonymous functions and calls `register!(Trait, T, nt)`,
  which runs all fail-early checks **at seal time**: duplicate seal, witness
  set exactly matches declaration, `hasmethod` per witness at `(R, argtypes...)`,
  best-effort `return_types` vs. declared, and **deep concreteness of `R`**
  (recurses type parameters too — `Vector{Any}` is rejected).
- `@region Trait begin f(t, args...) = ... end` — rewrites each op into a
  `@nospecialize` entry (seal lookup → project → worker call) plus a
  `@noinline` worker; every call `g(t, …)` becomes `getfield(w, :g)(r, …)`;
  any other use of `t` is a **macro-time error** (escape check, incl. closure
  capture — it's just "symbol appears outside first-arg-of-call position").
  Helpers are distinguished from ops syntactically: the trait object is
  erased hence untyped, so **bare-symbol first arg = op, annotated = helper**.

Key architecture decision: the region rewrite is **purely syntactic** — it
never needs the trait declaration at macro-expansion time, so trait, seals,
and regions can live in three different packages with no expansion-order
coupling (trait knowledge is enforced at seal *runtime* instead).

Witness tables are the M0 "dyn" design: `NamedTuple{names, NTuple{N,Function}}`
— same table type for every seal of a trait, so workers key on
`(trait, op, R)` exactly as the design core demands. Registration compiles
nothing; there is no stale-pointer window; no inference edges from workers to
witnesses.

## Test suite (`TraitRegions/test/runtests.jl`) — 14 tests, all pass

correctness (2 layouts, 1 shared R) · 6 fail-early checks (duplicate seal,
missing/unknown witness, wrong return type, `Vector{Any}` rep rejected,
unsealed use) · escape check (2 macro-time rejections incl. closure capture) ·
sharing (exactly 1 concrete worker MI for 2 types; +1 constant abstract MI
from inferring the `@nospecialize` entry) · `R`-returning trait methods.

## Macro-surface TTFX (`spike/RegionDemo` + `spike/scripts/e6_macro_ttfx.jl`)

Fresh session, never-seen type, 4 ops (Julia 1.11.7, `--startup-file=no`):

| mode | register | first-4-ops | total |
|---|---|---|---|
| region (@seal + trait ops) | 4.8 ms | 9.1 ms | **14 ms** |
| direct (ordinary Julia) | 0 | 32.8 ms | **33 ms** |

Matches M0's dyn-path numbers. Direct is nearer than in M0 because
RegionDemo's heavy helpers (`_mean`, `_std`, `_summary_of`) are outlined
shared functions that the workload precompiled for `Vector{Float64}` — the
baseline reuses them too. The remaining per-type direct cost is the op bodies
themselves; it grows with op count and inlining, the region cost does not.

## Known limitations (deliberate M1 scope)

- Ops: positional args only; no kwargs/defaults/`where`.
- Return-type asserts on trait calls are written at the use site
  (`col(t,i)::Vector{Float64}`); without them code is correct but downstream
  is dynamically typed. (A `@generated`-worker variant could inject asserts
  from the trait declaration — M2 candidate.)
- No `@full_compile` on the macro surface yet (M0 has the mechanism).
- No registry enumeration/persistence helpers yet (M2), no blame diagnostics
  (M2), no TraitCore/closure-rule lint (M2/writeup).
- `@trait`/`@region` are top-level-only (structs/consts) — like `@enum`.

## Next

1. M2-lite: `@full_compile` marker; worker/cache-key enumeration API
   (`TraitRegions.keys()`/`precompile_hint` helper so downstream packages get
   the workload for free); invalidation-blame demo on the macro surface.
2. M3: port full E1–E5 to the macro surface; scaling experiment (op count ×
   type count grid) for the headline chart.
3. Writeup for the community discussion (design + numbers + honest gaps).
