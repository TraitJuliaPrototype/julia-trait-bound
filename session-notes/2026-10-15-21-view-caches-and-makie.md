# 2026-10-15 — Session 21: view caches, the load-time filter, Makie

Continues session 20 (same conversation). The user asked where the PoC stands
against the ideal: install, and trait-bound code is precompiled; a new
representation is compiled once, cached, and taken from the cache by every
later session. My answer listed four missing steps: (1) record from
TraitWorld itself, (2) key the cache by the view, not the session, (3) make
loading safe from invalidation, (4) types defined at the REPL. The user: "1,2,3 no 4
then look at Makie and whether a rearchitected Makie could be cached fully."
Mid-session the user freed the machine ("You have the full machine now"); the
last runs are not niced.

## Steps 1 and 2: view caches (`TraitWorld/src/viewcache.jl`)

- **Recording:** `_check_once` notes a worker signature when it checks it
  (`_VC_NEW`), and `_enter_slow` notes builders.
- **Flushing** (`viewcache_flush`, at exit): signatures are grouped by
  `_vc_packages` (root modules of everything the signature names, without
  Core/Base/Compiler; `nothing` for `Main` or extensions), one
  `TWView_<hash>` package per view. Each package gets a Project.toml with the
  owners as deps, `sigs.jls` (Serialization, so TraitWorld now depends on
  Serialization) and a module that imports the owners. Its precompilation
  runs `_vc_compile`: the check (`worker_problems`, `_check_concrete`), then
  `precompile` of `checked_call`/`checked_kwcall` at the signature.
  `__init__` registers the checked signatures (`_VC_CHECKED`), and
  `_check_once` skips them. Builders join a view only if it names everything
  they name.
- **Loading:** `_vc_load!` from `_on_package_load` at top level. It pushes the
  directory onto LOAD_PATH and lifts `Base.LOADING_CACHE` around the require,
  because the outer `using`'s cache predates the directory ("Cannot locate
  source" otherwise). It loads only if `Base.isprecompiled`; otherwise the
  cache is marked stale and rebuilt at exit.
- **Building:** one process for all caches, niced, with
  `JULIA_TW_VIEWCACHE=0`.
- **Measured** (x12, `UserTypes.Ramp` through Reports): first calls 3.1–3.3 ms
  in lean, CSV-after and CSV-before sessions, against 106–1188 ms without.
- **A fix found on the way:** `_witness`'s ambiguity message used `first.(found)`
  over a `Vector{Any}`. That is an edge to `first(::Any)`, which DataStructures
  extends, so loading CSV before TraitWorld failed `_builder` at image
  validation (172 ms). It now sits behind an inference barrier
  (`_ambiguous_generic`). Found by walking the `@snoop_invalidations` log
  (`logedges`: `verify_methods` and `insert_backedges_callee` triples) to the
  root signature.

## Step 3: the load-time filter (patched Julia)

`Reports.report` (new, deliberately abstract: `string` of a heterogeneous
list, `push!(::Vector{String}, ::Any)`) loses its cached code on stock Julia
in both orders: 30 ms. The `attic/binary` clone's `base/staticdata.jl` now has
the load-time half of the filter (clone commit 0bf9125,
`attic/binary/trait_world_load_filter_v1.patch`):
- `verify_call` fails no edge of trait-world code through outside, owned
  newcomers (full match list, `_tw_outside_owned`).
- In `verify_method`, a non-trait callee that failed is kept for a trait-world
  caller if `_tw_valid_under_filter` (a dry recursive check) passes. The
  callee stays invalid for ordinary code.
- Trait modules are recognized by `__trait_module__`, and TraitWorld by a new
  `const __trait_world_machinery__`. Without that, TraitWorld's own image,
  validated before its `__init__`, lost `_guard_slow` (125 ms).
- The filter is on unless `JULIA_TW_FILTER=0`. Standard libraries are detected
  by path as well.

Result: `report` 5.6–6.2 ms in both orders (lean 5.5 ms). 210 tests pass on
stock and patched Julia.

Building the system image needed `make -j4 julia-sysimg-release` after two
repairs left over from the attic move: re-pointing `base/JuliaSyntax`, and
`touch Compiler/src/Compiler.jl` so that the compiler stage, which still
named the old path, was rebuilt. Notes in `attic/binary/README.md`.

## Makie

- **Source reading** (subagent, Makie 0.24.16, ComputePipeline 0.1.8,
  CairoMakie 0.15.16, Observables 0.5.5):
  - **Per-user-type specialization:** `_create_plot!(F, Dict, args...)` at
    recipes.jl:545 and figureplotting.jl:488, `Plot{Func}(::Tuple, ::Dict)` at
    compute-plots.jl:766, the `convert_arguments` chain, dim converts, and
    `preferred_axis_type` at figureplotting.jl:48.
  - **The compute graph:** user arguments enter it as `RefValue{Any}`
    (compute-plots.jl:396). Edges become
    `TypedEdge{InputTuple,OutputTuple,F}` through `invokelatest`
    (ComputePipeline.jl:120), per closure and value types; about 190 edge
    sites.
  - **Untyped storage:** `Observable{Any}` ×38, `Dict{Symbol,Any}` ×52.
    Observables calls listeners through `invokelatest`.
  - **Base at abstract types:** text and categorical code (text_layouting.jl:109,
    categorical-integration.jl:28–158), and `@max_methods 1`.
  - **One pirate:** `GeometryBasics.collect_with_eltype` at ShaderAbstractions'
    `Buffer` (conversions.jl:2435).
  - **Workload gaps:** the workloads leave out barplot, hist, strings, Dates,
    Categorical and Missing.
- **Experiment x13** (patched Julia, `JULIA_TW_PROTECT` = Makie's tree, 141
  packages, read by both halves of the filter):

  | | first PNG | compiling after loading | recompiling |
  |---|---|---|---|
  | filter off, or protecting only the trait stack | 15.7–16.2 s | 10.2–10.7 s | 5.1–5.4 s |
  | Makie's tree protected, either load order | 8.5–8.9 s | 2.9–3.3 s | 0.6 s |

  What remains: CSV×DataFrames (2.4 s) and `barplot` outside the workload
  (0.24 s); Makie recompiles nothing. A first attempt protected only through
  TraitWorld's registration and changed nothing, because Makie's image is
  validated before TraitWorld sees Makie (DataFramesWrapper loads DataFrames
  first). The name list in `staticdata.jl` fixed that.
- **Answer to the user:** yes, modulo coverage. The list of what Makie must
  change, and what caching cannot remove, is in the README.

## Next

1. Step 4, if the user wants it: caching for types of the session (a cache
   that depends on a script?).
2. Concurrent flushes of the same view: a lock instead of last-writer-wins.
3. The untrimmed `App` build now that the machine is free (needs ~14 GB more
   than was free in session 20).
4. From session 20: refuse mode's order dependence, ComboCache's session lock,
   remaining review items.
