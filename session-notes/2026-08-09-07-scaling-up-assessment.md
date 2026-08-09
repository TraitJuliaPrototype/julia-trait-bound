# 2026-08-09 — Session 07: scaling-up assessment (user question)

## Translating large packages to trait style

- **DiffEq**: best candidate — RHS is witness-shaped, solvers are region
  ops; compile cost collapses (solver × uType × f) → (solver × R), R set
  ≈ 3–6. Gated on TraitRegions gaps: multi-object ops (solve(prob,alg)),
  associated types, mutation/writeback, kwargs. Vertical slice (explicit RK
  core, 2 R's) = 2–4 wk after hardening; full DiffEq = person-years + SciML
  buy-in.
- **Makie**: do NOT translate internals; trait-bound the ingestion boundary
  (PlotData trait over ~12 canonical input shapes). Weeks; captures the
  measured 155→18 ms/type win. Finding: adoption is per-boundary, not
  per-package.
- **Stdlib**: becomes TraitCore (curated fingerprinted kernel), not regions.
  v0 days; credible = ongoing.
- **Prerequisite for all**: TraitRegions hardening (~1 month): kwargs/
  defaults/where, multi-trait & multi-object regions, associated result
  types, aliasing/writeback.

## Full Rung-3 prototype on a Julia clone

- **Stage A (no fork, 2–4 wk)**: full Rung 2 — restricted-method-table
  AbstractInterpreter + OpaqueClosure workers; 1.12's Compiler stdlib
  lowers the barrier. Do this first; it's the #54903 entry ticket.
- **Stage B (fork, 1–3 mo)**: keep macro surface (no parser work);
  enrollment metadata in Pkg/loading, universe id at load, sealed
  resolution as supported interpreter mode.
- **Stage C (3–6+ mo)**: world-consistent witness tables (gf.c), native
  cache keys + OC serialization in pkgimages (staticdata.c — hardest),
  optional witness-splitting pass. Fixes X9's native-code gap properly.
- Strategy: Stage A + writeup → recruit core devs before B/C.
