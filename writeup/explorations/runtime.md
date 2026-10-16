# The runtime the design needs, and whether to move to Julia 1.13

Exploration, 2026-10-16. The question (the user's): "We need to actually demonstrate the design in practice and I now think that this will not be possible without actually doing a major rewrite like Makie in our design. Should we switch to patching Julia 1.13? Are there any benefits to changing to that?" More broadly: what runtime the design needs, and how to build a demonstrator.

## Summary

- **Move to Julia 1.13.2 now, as a patched build and as stock.** Julia 1.13.0 was released in September 2026, 1.13.2 on 14 October 2026, and 1.12 is unmaintained since 1.13.0. Our insertion-time patch (`gf.c`) applies to 1.13.2 unchanged apart from line offsets. The load-time patch must be rewritten, because image validation moved from `base/staticdata.jl` into the compiler (`Compiler/src/reinfer.jl`). A minimal port is done and tested (`runtime_load_filter_1.13.2.patch`, beside this file). The move costs a few days.
- **What 1.13 offers us is mostly indirect.** Precompilation is about 30% faster and startup about 20% faster, and image objects are no longer traversed by the GC. Image validation and the choice of what a package image compiles are now Julia code instead of C. `invoke(f, ::CodeInstance, …)` is compiled to a direct call. JuliaC.jl replaces the `juliac` script. Nothing in 1.13 or master addresses the design's needs directly: no sealing, no selective invalidation, no module-level method visibility, and no native code for external interpreters' code in package images.
- **The load-time half of the filter needs no rebuild, on 1.12 or 1.13.** Included at run time into the module that validates images, it works on stock 1.12.2 and stock 1.13.2. That takes two Julia-level settings: the loader's require world, and on 1.13 the compiler's world. On the x12 measurement it gives the patched build's numbers: `report` 4.9 ms instead of 29 ms, `summarize` 3.5 ms instead of 32 ms, with CSV and Makie loaded first. Only the insertion-time half needs C. It is 109 lines.
- **An external AbstractInterpreter with its own CodeInstance owner is not a route to the demonstrator.** It gives separate instances, a view-filtered method table, and inferred code cached in package images. But Julia does not save machine code for such instances in package images (a TODO since 1.11, still open on master), and trimmed builds do not include them. So it gives up two of the four pay-offs. GPUCompiler 2 is in the same position: only inferred code persists.
- **Don't track master.** 1.14-DEV changes the IR shapes that TraitWorld's checks walk: global accesses can appear as `Core.BindingPartition`. Two of the three hunks of the `gf.c` patch fail there, and master offers nothing the design needs.
- **The demonstrator is bounded by the rewrite, not by the runtime.** Every runtime piece the demonstrator needs either exists as a package-level prototype, is a small patch, or can be deferred behind a workaround. The deep runtime work, which would make the design a language feature, is not on the demonstrator's critical path. The order of work is in the last section.

## 1. The runtime pieces, collected and refined

| Piece | What it is for | Where it stands | Tier |
|---|---|---|---|
| Invalidation filter at image load | cached trait-world code survives a load of outside packages before it | patched `staticdata.jl` (1.12); now also by run-time injection on stock 1.12.2 and 1.13.2 (§4.1) | package level |
| Invalidation filter at method insertion | the same when they load after | `gf.c` patch, 109 lines; applies to 1.13.2 | small patch |
| Refusing a pirate before an image's methods enter the method table | sealing that does not depend on load order | stock: deletion after the load, order-dependent | small patch (a callback before `jl_activate_methods`) |
| Dispatch check at dynamic sites | a leak becomes an error, not a wrong result | static door and rule-3 checks only; the entries check their own dispatch | deep (in `jl_apply_generic`), or via an interpreter's IR pass |
| Separate compiled instances for trait-world code | Base code used by both worlds without interference | not needed so far: the load filter keeps a Base callee for its trait-world caller (findings §15) | deferred |
| Method attribution to packages | ownership of methods evaluated into other modules | `m.module`; an image already knows which package brings each external method | small, part of the load hook |
| Machine code for upstream CodeInstances in downstream images | a binary or session does not compile what a workload already compiled | dropped (findings §15); a build-time replay works around it | small to medium patch, deferrable |
| Typed field references for lenses | 1 ns lens reads and cheap writes | reads at the field offset are 1.15 ns on stock; writes need a write barrier | package level (a compiled setter per user type); an intrinsic is a small patch |
| `Dynamic` values | dispatch on a boxed trait object | design done, prototype next | package level |
| Definition checking at archetypes | errors at the library's build | prototype, 10 tests | package level |
| `juliac --trim` for verified programs | trimmed binaries | `verify_main` on 1.12; JuliaC.jl on 1.13 | package level |

Two refinements to the list given:
- **"Base compiled twice" has a cheaper answer for code in package images.** Session 21 kept a Base callee valid for its trait-world caller while it stays invalid for ordinary code. That decision is made at image validation, at the caller's edge. Separate instances are needed only for code compiled in a session after an outside method arrived, and even there the insertion-time filter handles the trait-world caller. Base code keeps one instance until a measurement says otherwise.
- **The load-time pieces are two different hooks.** The filter acts at validation, after the methods are in the table. The refusal must act before they enter it. On 1.13 the first is Julia code; the second is still inside one C call (`jl_restore_package_image_from_file` deserializes, then `jl_activate_methods` inserts), so it needs a C callback.

## 2. Julia 1.13 as of October 2026

**Release status.** All of this is from `git ls-remote` on JuliaLang/julia and the tags fetched into a scratch clone:
- `v1.13.0` was tagged on 9 September 2026 after betas from January and four release candidates. `v1.13.1` followed in September, and `v1.13.2` on 14 October 2026.
- `release-1.13` stands at 1.13.3-DEV (16 October).
- `master` is 1.14.0-DEV. There is no `release-1.14` branch yet.
- The 1.13.0 announcement declares 1.12 unmaintained ([Discourse](https://discourse.julialang.org/t/julia-v1-13-0-has-been-released/139326)). The last 1.12 tag is `v1.12.7`; our clone is at `v1.12.2`.

**What changed since 1.12 that matters here:**

| Area | Change | Source |
|---|---|---|
| Image validation | `base/staticdata.jl` is gone. Validation (`insert_backedges`, `verify_method`, `verify_call`) lives in `Compiler/src/reinfer.jl` (`Compiler.ReinferUtils`) and runs in the compiler's world through `jl_call_in_typeinf_world`. `verify_method` was rewritten as an explicit-stack Tarjan walk; `verify_call` is unchanged except for messages. | source diff v1.12.2→v1.13.2 |
| What a package image compiles | `src/precompile_utils.c` (399 lines of C) was replaced by `Compiler/src/precompile.jl` (481 lines of Julia), registered through `jl_set_compile_and_emit_func`. | source diff |
| External interpreters | `invoke(f, ::CodeInstance, args...)` (#56660, in 1.12) is now inlined as `Expr(:invoke)`, about 4.7 ns instead of 25 ns with two allocations (#60442, backported for 1.13.0-beta2). JIT support for external interpreters' instances (`codegen_cache`, #57272) dates from 1.12. | [#60442](https://github.com/JuliaLang/julia/pull/60442), [#57272](https://github.com/JuliaLang/julia/pull/57272) |
| Native code for external interpreters' instances in package images | unchanged: skipped. 1.12.2 has `// TODO(vchuravy) native code caching for foreign interpreters`; 1.13.2 and master have "This code instance is from a foreign interpreter, so we skip it". Their inferred code is serialized (`ext_foreign_cis`) and validated at load like native code. | `Compiler/src/precompile.jl`, `src/staticdata.c` |
| Precompilation and startup | about 30% less precompile time than 1.12, about 20% faster startup | [1.13 highlights](https://julialang.org/blog/2026/09/julia-1.13-highlights/) |
| GC | system and package image objects are permanently marked, so the mark phase skips them. A full GC after `using GLMakie` went from 187 ms to 68 ms. Writes into image objects are tracked separately (#61474). | [1.13 highlights](https://julialang.org/blog/2026/09/julia-1.13-highlights/) |
| AOT | `juliac` became the package JuliaC.jl. Finalizers, `@cfunction` and `mapreduce` now trim. 1.13.2 keeps only test copies of the old build scripts. | highlights; source tree |
| Field access | `fieldoffset(T, :name)` accepts a symbol (#58100) | [NEWS 1.13](https://github.com/JuliaLang/julia/blob/release-1.13/NEWS.md) |

**What did not change:**
- **Method tables.** `jl_methtable_t` is identical in 1.12.2, 1.13.2 and master: one global table, typename-keyed backedges.
- **No new form of global freezing.** `Base.Experimental.disable_new_worlds()` (since 1.12) remains the only one, and it is process-wide, all or nothing.
- **No sealing, no frozen or per-module method tables, no module-level method visibility, no typed field references,** in 1.13.2 or on master: grep of `gf.c`, `julia.h`, `method.c`, `base/experimental.jl`; master's only new experimental macros are `@make_all_arithmetic_checked`, `@reexport` and `@set_syntax_version`.
- **Binding partitions and world age** are 1.12's.

On master (1.14-DEV, [NEWS](https://github.com/JuliaLang/julia/blob/master/NEWS.md)) three changes touch us:
- **#62452:** resolved global accesses carry their binding partition into lowered code, so optimized IR can contain `Core.BindingPartition` and `Core.getglobal_partition` where it had `GlobalRef`. TraitWorld's checks walk IR in nine files (47 matches for `GlobalRef`, `:invoke`, `getglobal` and `code_typed`).
- **#63618:** builds install a static `libjulia-internal.a` without the JIT, for JuliaC.
- **Custom interpreters** must return an `InferenceCache` from `get_inference_cache` ([compiler changes](https://docs.julialang.org/en/v1.14-dev/devdocs/compiler_changes/)).

## 3. What porting our two patches costs

**`trait_world_filter_v1.patch` (`src/gf.c`, 109 lines).** `patch --dry-run` against v1.13.2's `gf.c` applies all three hunks with offsets of 148–166 lines. The functions it hooks, `invalidate_code_instance` and `jl_method_table_activate`, and every field it reads (`m->parent`, `jl_get_ci_mi`, `dt->name->module`) are unchanged. Against master, two of three hunks fail on context (new `JL_CANSAFEPOINT` annotations); the logic would still fit. `gf.c` itself changed by +806/−415 lines from 1.12.2 to 1.13.2 and by +1939/−1189 from 1.13.2 to master.

**`trait_world_load_filter_v1.patch` (`base/staticdata.jl`, 253 lines).** The file no longer exists in 1.13. The port goes into `Compiler/src/reinfer.jl`:
- **Helpers:** copied unchanged except for three qualifications (`Base.IdSet`, `binding_was_invalidated`, `Base.Compiler`).
- **`verify_call`:** the same three edits. 1.13's version also refuses an edge whose match count differs from the expected count, so the port subtracts the outside, owned newcomers from that count.
- **`verify_method`:** the flag for "the code being verified is trait-world code" is set before the edge loop. The keep-the-Base-callee rule moved into the `:return_to_parent` stage of the new explicit-stack walk, where a child's result reaches its parent.

The port took about an hour and is 222 lines of unified diff (`writeup/explorations/runtime_load_filter_1.13.2.patch`). Its first two parts are tested (§4.1). The callee rule compiles and loads but has no test yet that exercises it on 1.13.

**The rest of the move:**
- A cold build of the patched 1.13 (40–60 min, niced, alone).
- Re-precompiling the stack: CSV, DataFrames and Makie's tree; precompilation is about 30% faster on 1.13.
- Pointing TraitWorld's four `Base.StaticData._tw_*` references at `Base.Compiler.ReinferUtils`.
- Moving `experiments/interfaces/build` from `contrib/juliac` to JuliaC.jl.
- Running the 210 tests and the x12/x13 measurements again as the new baseline.

TraitWorld's other contact surface with internals is small: `Base._methods_by_ftype`, `Base._which`, `Compiler.return_type`, `jl_module_usings`, `jl_gf_invoke_lookup_worlds`, `jl_compile_hint`, plus IR walking over `code_typed`, whose shapes 1.13 does not change. Two to four days in all.

## 4. What works without C patches

### 4.1 The load-time filter, injected at run time

Image validation is Julia code in both versions: `Base.StaticData` in 1.12 and `Base.Compiler.ReinferUtils` in 1.13. Including the patched file into that module at run time redefines its methods. Two settings then make the loader use them:
1. **The require world.** Since 1.12 the loader runs in a world fixed at startup (`Base._require_world_age`), so it does not see redefinitions until that world is advanced.
2. **The compiler's world (1.13 only).** 1.13 also runs validation in the compiler's world, which `Base.Compiler.activate_codegen!()` moves to the present.

Each step must be a top-level statement of its own, so that it runs in the world after the redefinitions:

```julia
const R = VERSION >= v"1.13-" ? Base.Compiler.ReinferUtils : Base.StaticData
Base.include(R, patched_file)                         # 1.12: the clone's base/staticdata.jl; 1.13: the ported reinfer.jl
VERSION >= v"1.13-" && Base.Compiler.activate_codegen!()   # 1.13 validates images in the typeinf world
Base._require_world_age[] = Base.get_world_counter()  # the loader runs in the require world
```

**A minimal test, on stock 1.12.2 and stock 1.13.2.** The packages:
- `TW`, a trait module (`const __trait_module__ = true`), has `g(v::Vector{Any}) = numerator(v[1])` compiled into its image. That is an abstract call whose edge lists `numerator`'s three methods.
- `Out` owns `T` and defines `Base.numerator(::T)`.
- `Pir` defines `Base.numerator(::Float32)`: a pirate.

`Out`, or `Pir`, loads before `TW`.

| | stock | injected |
|---|---|---|
| 1.12.2, `Out` first: `TW.g`'s image code valid after the load | no | **yes** (1 edge kept) |
| 1.13.2, `Out` first | no | **yes** (1 edge kept) |
| 1.13.2, `Pir` first | – | no: the pirate fails the edge as before |
| 1.13.2, `TW` alone | yes | – |

**The x12 measurement** (`experiments/interfaces/scripts/x12_viewcache.jl`; stock 1.12.2; a view cache recorded in a fresh directory; CSV, DataFrames, DataFramesWrapper and MakiePlots loaded before or after Reports and UserTypes; first call in a new session, two runs each):

| first call | stock | stock, injected | patched build (session 21) |
|---|---|---|---|
| `summarize(ramp)`, CSV and Makie before | 31.8, 31.9 ms (28.6 recompiling) | **3.5, 3.6 ms** | 3.7 ms |
| `report(ramp)`, before | 29.3, 28.3 ms | **4.9, 4.9 ms** | 5.6 ms |
| image edges kept at load, before | – | 178 | 41–154 |
| `summarize(ramp)`, CSV and Makie after | 33.5 ms | 3.4 ms | 3.6 ms |
| `report(ramp)`, after | 28.0 ms | 28.4 ms (23.7 recompiling) | 6.2 ms |
| load time, before | 5.4–5.8 s | 5.6–5.8 s | – |

- **Injection itself** takes 0.10–0.13 s, mostly compiling the injected methods, which no image can hold.
- **The insertion-time half is still missing:** `report` in the "after" order is invalidated at insertion, and only the C half keeps it.
- **The "after" `summarize` is kept** because the view cache's image is loaded after CSV, so it is validated under the injected filter.
- **The stock baseline differs from session 21's** (31 ms instead of 3.3 ms for `summarize`). This run started by re-precompiling CSV, DataFrames, TraitWorld and Makie's tree, which were stale for stock 1.12.2 in `~/.julia/compiled/v1.12`, so the loaded method set may differ. The comparison with and without injection is within one state.

**Limits:**
- **Advancing the require world is a hack.** That world isolates the loader from methods defined in the session; advancing it exposes the loader to every method defined so far, including pirates of Base. The injection must therefore come first in a session (a startup file, or TraitWorld's `__init__` when it loads first). Images loaded before it are not filtered.
- **Not in precompile processes.** Overwriting Base methods is refused while a package image is generated, so precompile processes validate their dependencies without the filter. That costs recompilation in those processes, not correctness.

This is good enough for a demonstrator on stock Julia and for measurements. It is not a mechanism to ship.

### 4.2 The insertion-time half without C (untested)

Invalidation at insertion happens inside `jl_method_table_activate`, in C, with no hook. One package-level route remains: *revival*.
- **Log the load.** Enable the invalidation log during a load (`jl_debug_method_invalidation`, as SnoopCompile does).
- **Revive afterwards.** For each trait-world CodeInstance whose trigger was an outside, owned method, re-validate it with the load filter's dry check and restore `max_world`, its backedges and its cache entry. 1.13 does exactly these steps from Julia in `reinfer.jl`.

Risks:
- a window in which another task compiles against the invalidated state;
- the log's cost on every load;
- dispatch caches that the invalidation already cleared.

The C patch is simpler and is what a demonstrator should use. Revival is worth a day's experiment only if a demonstrator must run on unpatched Julia in both load orders.

### 4.3 TraitWorld as an external AbstractInterpreter with its own owner

Answers from the 1.12.2, 1.13.2 and master sources:

- **Separate instances: yes.** A `CodeInstance` with a non-`nothing` owner lives in the MethodInstance's cache beside the native one (#52233, 1.11). That is exactly "trait-mode CodeInstances". The interpreter can also present a method table filtered to the view (`method_table(interp)`). That gives the filter's answers by construction at inference, the stage-3 goal.
- **Invalidated by unrelated insertions: yes, unless the interpreter records its edges differently.**
  - `store_backedges` (`Compiler/src/typeinfer.jl`) installs an owner-tagged instance's edges in the same global reverse tables, and `invalidate_code_instance` does not look at owners.
  - An abstract call site's edge is a signature in the method table's backedges, which any intersecting newcomer triggers.
  - The interpreter controls `result_edges`, so it could record per-method `invoke` edges for the view's matches instead. In-view additions would then need their own signal: a per-view constant that TraitWorld redefines, read through a binding edge, would invalidate exactly the dependents. Untested.
- **Stored in package images: inferred code, yes.** It goes through `ext_foreign_cis`, and is validated at load like native code (`scan_new_code!` no longer filters by owner).
- **Native code: JIT only.** Since 1.12 an interpreter can supply a codegen cache, and its instances are added to the JIT and called with `invoke(f, ci, args...)` (#57272). That call is a direct `Expr(:invoke)` on 1.13 (#60442). Package images skip foreign instances when choosing what to compile, in 1.12.2, 1.13.2 and master. Trimmed builds compile only native inference from the entry points.
- **How others do it.** GPUCompiler 2 (CUDA.jl 6.3, built on CompilerCaching.jl) keeps its results in owner-tagged CodeInstances, so inferred code persists in package images through workloads. Machine code does not: a first kernel call after a workload is 0.13 s instead of 1.29 s, of which 72% is still compilation, and making LLVM IR and machine code relocatable is "work in progress" ([CUDA.jl 6.3](https://juliagpu.org/post/2026-08-19-cuda_6.3/)). The compiler-plugin path that Enzyme- and Diffractor-style tools build on is `CompilerPlugins.typeinf`/`typeinf_edge` plus `invoke` on a CodeInstance (#56660). Its caching is the same as GPUCompiler's. I did not read Enzyme's or Diffractor's sources for this note.

**Verdict.** The owner route loses the per-session machine-code cache (first calls back at tens of milliseconds) and trimmed binaries: pay-offs 1 and 2. Closing it means upstream work on native caching of foreign instances, which Julia's developers have left as a TODO for two releases. It is the right long-term shape for "trait-mode instances" and the stage-3 "inference sees only the view". It is the wrong vehicle for a demonstrator in 2026.

### 4.4 Other pieces at package level

- **Lens writes.** A compiled setter per (user type, field), held by the lens as a function pointer, is tiny code compiled once per user type. It costs an indirect call (a few ns) instead of `setfield!`'s 13.6 ns.
  - Reads at the field offset are already 1.15 ns on stock.
  - A hand-written write barrier is not an option: 1.13 changed how writes into image objects are tracked (#61474), which a hand-rolled barrier would silently break.
  - A runtime intrinsic, a typed load or store at an offset with the barrier, is a small patch for later.
- **Dispatch check at dynamic sites.** TraitWorld's static checks (rule 3, doors, concrete mode) report dynamic sites at build time. `Dynamic` values dispatch through TraitWorld's own registry, which can check owners at no extra cost. A check of every generic dynamic call in trait-world code needs either a C change in `jl_apply_generic` or an interpreter's IR pass (§4.3). A demonstrator can do without it, since the static checks find the sites.
- **Method attribution.**
  - `Core.eval(Main, …)` from a package is already refused during precompilation.
  - Requires-style evals land in the package's own module.
  - An image's external methods are listed per image and activated with the package's name (`jl_activate_methods(…, pkgname)`), so the load hook in §5 can attribute by image.

## 5. The minimal runtime for a demonstrator at scale

The demonstrator is a trait-world plotting system in the shape of Makie, used by real people:
- an interactive session in any load order;
- package images that hold its code per representation;
- a trimmed binary that reads data and writes a plot;
- pirates refused at load.

What it needs from the runtime, by tier. Estimates are for this project's pace (one person with Claude sessions); risks are what could make the estimate wrong.

**Package level, stock 1.13.2:**

| Work | Estimate | Risk |
|---|---|---|
| Move TraitWorld and the PoCs to 1.13.2; JuliaC.jl builds | 2–4 days | JuliaC.jl's options differ from `contrib/juliac`; re-baselining all measurements |
| Load filter by injection as an optional TraitWorld mode (`JULIA_TW_INJECT`) | 1–2 days | require-world hack (§4.1); must run before the first image loads |
| `Dynamic{X}` prototype, lenses with compiled setters | 1–2 weeks | interaction of lenses with several views (open in the note) |
| Definition checking extended to keywords, varargs, `Callable` workers | 1 week | already deferred by the prototype |
| The rewrite itself: a vertical slice of a Makie-like system (Figure/Axis, 6–8 plot types, attributes as typed fields and `Dynamic`, conversions as projections, a compute graph with typed edges, layout; Cairo or CairoMakie behind calls upward) | 2–4 months | scope creep toward all of Makie; text, fonts and layout dominate effort in plotting systems; backends' first-use costs are outside the trait world's caching |

**Small patches (patched 1.13.2):**

| Work | Estimate | Risk |
|---|---|---|
| Insertion-time filter (`gf.c`), as is | hours | none known; the hunks apply |
| Load filter compiled into the system image (the ported `reinfer.jl`) instead of injection | 1 day plus one sysimage build | the callee rule is untested on 1.13 |
| Transactional image load: a Julia callback with the image's external methods before `jl_activate_methods`, which may throw and abandon the load | 1–2 weeks | state left behind by an abandoned load (types and modules created, method roots, extension triggers); 1.13's GC treats image objects as permanently marked |
| Upstream CodeInstances' machine code in the downstream image (findings §15) | 1–2 weeks, or keep the build-time replay | duplicate instances for one MethodInstance across images; the replay workaround already gives 0.012 s |

**Deep runtime work (not on the demonstrator's path):**

| Work | Estimate | Risk |
|---|---|---|
| Dispatch check at dynamic sites in `jl_apply_generic`, with a per-task trait-world flag and owners per method | 1–2 months | cost on the hottest path in the runtime; attribution of every method |
| Trait-mode instances with machine code in package images and in trimmed builds (owner-tagged or a native flag) | months; upstream-sized | the same TODO Julia has carried since 1.11; changes to `staticdata.c` and `aotcompile.cpp` |
| Inference over the view's method table (stage 3) | months | two worlds answering the same query; return-type queries |
| Typed field reference intrinsic | 2–3 weeks | codegen and GC barrier interplay |

**What the demonstrator should show, and which tier each part needs:**
1. **Interactivity.** First plot after CSV and DataFrames in either load order, with no trait-world recompilation. The x13 experiment already shows the size of the effect for unmodified Makie: 8.5 s instead of 16 s. Needs both halves of the filter: the small patch, or injection for the "before" order only.
2. **AOT.** A trimmed binary of the plotting pipeline through `verify_main`. Stock 1.13 with JuliaC.jl.
3. **Checking and errors.** Definition checking and concrete mode on the rewrite's own code. Package level.
4. **Identical or error.** A pirate refused in both load orders. Deletion-after-load shows it on stock in one order; the transactional load hook shows it properly.

## 6. Recommendation and order of work

**Stay with the patched-build strategy, but on 1.13.2 rather than 1.12.2. Don't track master.** Reasons, in order of weight:
1. **1.12 is unmaintained.** The ecosystem a Makie-scale demonstrator depends on now tests against 1.13.
2. **The C surface shrinks to one small patch** that applies as is. The load-time half is Julia code, and is injectable at run time for stock users.
3. **1.13 makes the demonstrator's sessions cheaper:** precompilation about 30% faster, startup about 20% faster, GC no longer scanning images (relevant to Makie-sized sessions).
4. **The choice of what an image compiles is now Julia code** (`Compiler/src/precompile.jl`). That is where the "machine code for upstream instances" fix and any future native caching of trait-mode instances would go.
5. **Master's IR change would break TraitWorld's checks** for no gain. The choice should be revisited when `release-1.14` branches.

**Order of work:**
1. Move to 1.13.2: patched build (the `gf.c` patch plus the ported `reinfer.jl`), JuliaC.jl, the 210 tests, and x12/x13/binary measurements as the new baseline. Add injection as TraitWorld's stock-Julia mode, so a user without the patched build gets the load-time half.
2. Prototype `Dynamic{X}` and lenses with compiled setters. These are what a Makie-like scene graph and attribute system are built from, and they are the design's least-tested part.
3. Start the rewrite as a vertical slice, with the four demonstrations above as its acceptance tests from the first week.
4. Add the transactional load hook when the slice first meets a real pirate in its tree. Session 21's audit says it will: OffsetArrays, PlotUtils.
5. Leave the dynamic-site check, trait-mode instances and the owner-tagged interpreter to after the demonstrator, as the subject of an upstream proposal that the demonstrator's numbers support.

## Experiments and sources

**Experiments (this session):**
- `git ls-remote` and depth-1 fetches of `v1.12.2`, `v1.13.0`, `v1.13.2`, `release-1.13` and `master` into a scratch clone; diffs and `patch --dry-run` there. The attic clone was not touched.
- Stock 1.12.2 (juliaup) and stock 1.13.2 (the official binary tarball, unpacked in the session's scratch directory; nothing built).
- x12 via a wrapper that injects the clone's `base/staticdata.jl`, run niced, one job at a time.
- The minimal TW/Out/Pir packages, in a scratch depot.

Side effect: CSV, DataFrames, TraitWorld and Makie's tree were re-precompiled for stock 1.12.2 in `~/.julia/compiled/v1.12`.

**Sources:**
- [Julia v1.13.0 has been released (Discourse)](https://discourse.julialang.org/t/julia-v1-13-0-has-been-released/139326)
- [Julia 1.13 highlights](https://julialang.org/blog/2026/09/julia-1.13-highlights/)
- NEWS.md at `v1.13.2` and `master`, read from the fetched trees ([release-1.13](https://github.com/JuliaLang/julia/blob/release-1.13/NEWS.md), [master](https://github.com/JuliaLang/julia/blob/master/NEWS.md))
- [#57272: CodeInstances of external interpreters in the JIT](https://github.com/JuliaLang/julia/pull/57272)
- [#60442: optimizer support for `invoke(f, ::CodeInstance, …)`](https://github.com/JuliaLang/julia/pull/60442)
- #56660 (`invoke` with a CodeInstance, `CompilerPlugins`) and #52233 (CodeInstance owners), via 1.12's NEWS and `base/optimized_generics.jl`
- [CUDA.jl 6.3: compiler caching](https://juliagpu.org/post/2026-08-19-cuda_6.3/)
- [History of changes to the compiler (1.14-dev docs)](https://docs.julialang.org/en/v1.14-dev/devdocs/compiler_changes/)
- [AlternativeTo summary of the 1.13 release](https://alternativeto.net/news/2026/9/julia-1-13-released-with-major-speed-gains-in-precompilation-startup-and-garbage-collection/)
- Source files read: `src/gf.c`, `src/julia.h`, `src/staticdata.c`, `src/staticdata_utils.c`, `src/precompile_utils.c` (1.12.2), `Compiler/src/{reinfer,precompile,typeinfer,types,bootstrap}.jl`, `base/{loading,experimental,optimized_generics}.jl`, at v1.12.2, v1.13.2 and master.
