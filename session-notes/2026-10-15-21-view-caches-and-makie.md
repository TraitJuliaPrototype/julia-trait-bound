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

## The untrimmed App build (the user: "Go")

On the free machine, under a watchdog that would kill it below 2.5 GB
available: 398 s, a 1.17 GB executable. The lowest available memory was
5.4 GB, starting from 22 GB, so the build needs about 16.5 GB. It runs: summaries, a correct
histogram PNG, **0.93–0.98 s from process start to the PNG**, peak RSS
1.1 GB (ad-hoc session 16 s, `App`'s package image 6.4 s). The trimmed
Pipeline binary takes 0.02 s, with no DataFrames and no Makie. Run-time
compilation of the full binary was not measured.

## The binary's time, and a Python baseline

The user asked what the pipeline timing is (the trimmed `Pipeline` binary,
0.02 s: a concrete CSV reader, Reports' summary and histogram counts as text,
no DataFrames, no Makie, no plot), whether the binary uses the cached code,
for a Python baseline, and where the time goes.

- **Cached code.** juliac's non-incremental `--output-o` build loads the
  package images, inferred and native code both (probed in that mode). It
  then regenerates all machine code with LLVM: `JULIA_IMAGE_TIMINGS=1` gives
  134 s wall and 949 CPU-seconds over 8 shards, out of about 400 s.
- **Python** (`poc/interfaces/python/app.py`; a uv environment in `$TMPDIR`,
  not committed): 0.57–0.67 s.
  - imports 0.45 s, work 0.10 s;
  - first run ever 3.9 s (the font cache);
  - without `MPLCONFIGDIR` in a writable place, 2.2–3.5 s every time.
- **Run-time compilation in the binary** (`build/app_prof.jl`, `./build.sh
  prof`): 0.27–0.32 s compiling inside `main`, 60 methods.
  - 26 of the 32 resolvable ones already had inferred code cached after
    `using App`, but no machine code: 18 from Julia's system image, the rest
    from upstream package images.
  - The mechanism: App's workload generates that machine code, but App's
    image saves only the entries it created, and juliac does not run `main`.
  - Replaying the 60 traced statements at build time (`APP_PROF_REPLAY=1`,
    `build/runtime_compiles.jl`, 58 resolved) leaves 0.012 s of compiling:
    the work is 0.10 s and the process 0.69–0.70 s, against Python's
    0.57–0.67 s.
- **Startup:** 0.54 s to `main`. Plain Julia starts in 0.11 s; the rest is
  the packages' share of the 1.17 GB image (strace: 0.5 s without file access)
  and `__init__` work (151 shared libraries, a system font scan).

The user also asked whether trait-bound Julia could be as fast as Python.
My answer: no fundamental reason.
- Compiling per type is the one real difference, and the design turns it into
  a cached, one-time cost per representation.
- Load time and eager images are engineering problems in Julia's loader, which
  sealed views make easier: no re-validation needed, and pre-merged images.

## How close Makie is to a wrapper (the user: "Check how close Makie is to letting us wrap it")

Before this, the user asked whether the full app still carries LLVM and compiles.
- Yes: the untrimmed binary loads `libjulia-codegen` (81 MB) and LLVM (111 MB)
  and compiled 60 methods. None of them is trait-bound code: 59 are Makie's
  tree and 1 is CSV. The trimmed binary also loads both libraries (Julia
  1.12's runtime does) but cannot compile.
- Then: how would this work in Rust or Mojo? Rule 3 is Rust's orphan rule,
  rule 4 is where Rust puts monomorphized code, and calls upward are `dyn`.
  Mojo's `fn` versus Python objects is the layering. Neither has an open,
  dynamic outside.
- Then: `Dict{Symbol,Any}` in Rust: `dyn Any` only downcasts; Rust code
  closes the set with a trait (`dyn AttrValue`) or an enum, which here is a
  small `Union` or a trait object.

x14 and x15 (README, "How close is Makie to a trait wrapper?"):
- **Sealing with Makie wrapped:** 72 pirates instead of 26. The new 46 are
  core/implementation pairs (StatsAPI←StatsBase 23, AbstractFFTs←FFTA 8,
  ComputePipeline/Observables←Makie 8, AxisAlgorithms←Interpolations 5), two
  extensions misattributed by the PoC, and one real pirate
  (`collect_with_eltype`).
- **`verify_main`:** stops after 4–246 instances per call (75 holes; Observables
  26, Base show/logging 24, figureplotting 11).
- **Traced dispatch:** 1,940 distinct targets on the first plot (ComputePipeline
  656, Base 649, Makie 378), and 1 new Makie target on a second plot with
  other data.
- **Verdict:** sealing a few wrappers away; no run-time compilation by
  construction far; in practice close.

## Between nested types and `Any` (the user: "this analysis should be a rather central point")

The user asked whether traits let a system like Makie escape the choice
between deeply nested parametric types and `Any`. The answer went into the
live note as a new first subsection of "How the concepts achieve the goals",
"Between nested types and `Any`" (rev 1112), with the long form in
design-findings §16. A Fable review (11 findings, two experiments) corrected
it at rev 1116:
- `verify_main` does not see dynamic operations (an `Erased` `ccall` through
  a per-session `@cfunction`), and they are not compiled ahead: `Reversed`
  first call 107 ms in a fresh session against 1.4 ms for a projection. The
  note now says what is design and what the prototype does.
- x16 (`scripts/x16_makie_variety.jl`, new): other values of the same types
  add 1 dispatch target, each new argument type or attribute shape 35–84.
  "`Any` hides little variety" became "a stable core and a per-type fringe".
- Makie's positions are `Point{N, Float64}`/`Point{N, Float32}` by element
  type, `Float32` only at the backend; `to_color` has five shapes, so
  attributes need the "inside position" (a union of Makie's own
  representations, dynamic, closed by ownership).
- Growth ends at conformances, not bounds; within a function code still
  multiplies over its bounds; six things continue the product by choice.
- Added: what is new over plain-Julia discipline (x8: hand conversion 36 ms
  per type, trait route 35–47 ms, Makie's recipe route 297 ms): enforcement,
  closed listed targets, placement by owner. "Sane types": the prototype's
  stack frames print `TObj{…View{…}}`; the design should print bound and
  representation.
- Trade-off 1 and the wrapper section now say "Makie as written"; "static,
  inlined" in the conformance table became "static, direct".

Open (findings §16.6): a storable dynamic trait object; dynamic operations
compiled into images; printing; the synthetic-stack and restricted
ComputePipeline experiments.

## Next

1. Step 4, if the user wants it: caching for types of the session (a cache
   that depends on a script?).
2. Concurrent flushes of the same view: a lock instead of last-writer-wins.
3. Julia: keep machine code that a downstream workload generates for an
   upstream code entry, in the downstream image (rule 4's placement). This
   would remove the binary's and `App`'s run-time compilation without
   replaying traces.
4. Startup: the 0.43 s of the packages' image share and `__init__`, split
   further.
4. From session 20: refuse mode's order dependence, ComboCache's session lock,
   remaining review items.
