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
- Deliberate PoC scope: filters `jl_matching_methods`/reflection/inference;
  runtime dispatch caches are NOT filtered (that is the task-universe work,
  P1b). Skipped methods do not narrow result world-validity — which is the
  sealed semantics: universe results stay valid across outside definitions
  ("immortal workers" falling out of the matcher patch).

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
