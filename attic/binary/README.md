# binary/ — the patched-Julia (Rung-3 P1) prototype

`julia/` is a shallow clone of JuliaLang/julia **v1.12.2** with the
trait-universe patch applied to `src/gf.c` (not committed to this repo's
git — the clone has its own; see the diff via `cd julia && git diff`).

## The patch (P1a: sealed resolution below the matcher, native)

- `jl_set_universe_filter(mods)` — C-exported; a rooted `Vector{Any}` of
  Modules, or NULL to disable.
- `ml_matches_visitor` skips any method whose defining-module chain is
  outside the universe — **before** specificity/shadowing are computed, so a
  filtered pirate's shadowed victims are found normally (the A5 defect of
  the package-side post-filter, fixed at the correct layer).
- The `ml_matches` leaf/full-cache fast paths are bypassed while the filter
  is active (caches may hold non-universe methods).
- Scope and KNOWN UNSOUNDNESS (review #2, reviews/2026-08-09-critical-review-binary.md):
  the filter is GLOBAL — any method compiled while it is active stores an
  unnarrowed CI in the ordinary global cache, which plain dispatch then
  serves after the filter is cleared (silent sealed answers in unsealed
  code; probe-verified). `invoke` paths bypass the filter, so the sealed
  guarantee covers dynamically dispatched edges only. The invalidation
  guard covers the dispatch-backedge channel only. Whether not-narrowing
  validity is sound is exactly open question Q5 — the architect memo
  (reviews/2026-08-09-architect-memo.md, Design C: additive overlay
  tables) eliminates the poisoning class by construction and is the
  intended replacement for this subtractive filter.

## Build / test

    cd julia && make -j14          # ~40-60 min cold, ~2 min incremental
    ./julia/julia --startup-file=no ../test_universe.jl   # expect PASS

`test_universe.jl` checks: pirate excluded from matches, shadowed Base
method recovered, and an OpaqueClosure compiled under the filter keeps
pre-pirate semantics while the live world takes the pirate.

## Next (in order)

- P1b: task-local current-universe consulted by runtime dispatch
  (`jl_apply_generic`) so dynamic calls from sealed code are filtered too.
- Wire TraitRegions to use the native filter when available
  (`isdefined`-probe for the ccall) instead of the Stage-A interpreter.
- P1c: enrollment bit on `jl_method_t` set from Project.toml metadata at
  load, replacing the hand-rooted module array.
