# 2026-10-13 — Session 13: the representation as a trait parameter

## Decision

The user asked whether R should be a trait parameter. Answer adopted: yes,
declared (`@trait ColTable{R}`), with operations implemented per
representation by default (`@implement`) and the seal's own operations kept
as an option; both coexist at one R. The user added: `@implement` should
infer R from the user type and the provided functions where possible.
Terminology: "closure" (taken in programming) is replaced by "trait world" /
"closed trait world" in the design note.

## Built (TraitRegions)

- `@trait Name{R}`: R names the representation; declarations are stored as
  functions of R (`args = R -> (…)`, `ret = R -> T`), so they may depend on
  it (`firstel(r::R)::eltype(R)`). `SelfR` removed.
- `@implement Trait{R}`, `@implement Trait` (R from the annotation of the
  first argument), `@implement Trait T` (T is its own representation; sealed
  onto itself), `@implement Trait T begin project(t) = …; … end` (R inferred
  from the projection at load time, methods evaluated then). Methods of
  `impl_op(::Type{Trait}, ::Val{:op}, r::R, …)`, `impl_info` marks the pair;
  checks: every operation present, result types, deep concreteness, the orphan
  rule (owner of trait or R).
- `@seal Trait{R} T …` declares R; a seal with only `project` uses the
  implementation (`Seal.w = Impl{Trait}()`), otherwise the erased table.
- Regions rewrite trait calls to `_wcall(Trait, Val(:op), w, r, …)`: folds to
  the seal's table (indirect), the implementation (static, inlined) or the op
  registry. `_wret` asserts results to the declared type at R.
- Sealing machinery: registry lookups through `invokelatest` (they were
  invalidated by every package declaring a trait; 134 ms at the first seal of
  a session); `deep_concrete` without `fieldtypes` closures (about 70 ms);
  TraitRegions' workload now seals types (projection only, own operations, the
  macro's path) and expands the macros.
- Tests 93/93 (16 new). Error-split scenarios, both observe suites and the
  concrete PoC unchanged.

## Results (`poc/reprparam`)

- Steady state, one `value` call per element over 4 columns: implementation
  1.02–1.03× plain at 4096 elements per column (0.9 ns per element),
  2.3–2.5× at 16 (the entry); the seal's own operations 24–35× (19–23 ns per
  element, an indirect call each). The note's earlier "5× at 16 elements"
  was X3's coarse trait, not a per-element operation.
- Fresh session, new type sealed and first calls: projection 113 + 3 ms; own
  operations 120 + 11 ms; own representation 240 + 103 ms. The seal alone
  85 ms (314–350 ms before the two fixes).
- A first benchmark run compared against a plain loop whose unused result the
  compiler dropped (0.23 ns per element); the benchmark now consumes results.

## Next

- Implementations for Base-typed representations by package extensions
  (glue), to avoid centralization in the trait's package.
- Seal cost: 85 ms is mostly Julia compiling its reflection (`return_types`)
  and the macro expansion of the user's file; the target is a few ms.
