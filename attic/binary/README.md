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

## The trait-world invalidation filter (2026-10-15, session 20)

`trait_world_filter_v1.patch` (clone commit `72a6ee9`, on top of the patches
above): `jl_set_trait_world_filter(mods, julia_names)` registers the trait
modules and TraitWorld (rooted by TraitWorld, `wrapper.jl`) and the standard
libraries' names. While `jl_method_table_activate` inserts a method, that
method is the trigger, and `invalidate_code_instance`, which every
invalidation path reaches, skips code of a registered module when the
trigger comes from neither the trait world nor Julia and its definer owns a
type or the function of its signature (Union arguments and extensions prove
no ownership, so in doubt it invalidates). Pirates invalidate as before;
wrapped packages are not protected (their code is also ordinary code).
`jl_tw_skipped` counts the skips. TraitWorld turns it on when the symbol
exists; `JULIA_TW_FILTER=0` turns it off. Results in
`poc/interfaces/README.md` ("Invalidation filter").

The load-time half (session 21, clone commit 0bf9125,
`trait_world_load_filter_v1.patch`, `base/staticdata.jl`): when a package
image is validated, an edge of trait-world code is not failed by newcomer
methods that are outside and owned (same predicate, in Julia), and a Base
callee that fails only through such methods is kept for its trait-world
caller (it stays invalid for ordinary code). Trait modules are recognized by
`__trait_module__`, TraitWorld by `__trait_world_machinery__`, so images that
load before TraitWorld are covered; on unless `JULIA_TW_FILTER=0`.
`JULIA_TW_PROTECT=<names>` treats packages as trait-world code, for
measurements only (x13). `Base.StaticData._tw_skipped` counts kept edges.

Build notes: the clone was built at the old path `binary/julia`, so the
standard library symlinks under `usr/share/julia/stdlib/v1.12` dangled after
the attic move; they were re-pointed to `attic/binary/julia/stdlib`. A
top-level `make` then tries to reinstall them and stops at the system image.
The C library alone: `make -C src -j4`. The system image (after a change in
`base/`): `make -j4 julia-sysimg-release` (about 5 min); it needed
`base/JuliaSyntax` re-pointed to `attic/binary/julia/deps/scratch/JuliaSyntax-…`
and the compiler stage rebuilt once (`touch Compiler/src/Compiler.jl`), whose
old image still named the old source path. Use an own depot for its package
images: `JULIA_DEPOT_PATH=<dir>:~/.julia attic/binary/julia/julia …`.
