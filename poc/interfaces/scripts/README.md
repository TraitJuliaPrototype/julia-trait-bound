Scripts of the two demonstrations (writeup/poc3-plan.md §1), all run in a fresh process with `--project=poc/interfaces/env`:

| script | what |
|---|---|
| `demo_session.jl` | demo 1 as a linear script: steps 1–3 (load, a DataFrame analysed and plotted, a new type in one line), printing each step's time and compile time |
| `demo1.jl` | runs `demo_session.jl` in a fresh process with `--trace-compile` and lists what compiled at run time, per step, separating the trait stack's instances |
| `m0_plain.jl` | M0, the plain twin: DataFrames and CairoMakie without traits, first result, first plot, a new type the idiomatic way |
| `x4_churn.jl storm|makie [plain]` | X4 ported: invalidation trees from `using ChurnStorm` or `using CairoMakie` that touch the trait stack, and the next calls' compile time |
| `x5_redefine.jl` | demo 1 step 5: a worker redefined in the session; what it invalidates, per package |
| `x8_types.jl recipe|trait|plainpre` | X8 ported: the marginal cost per additional user type, a warm-up type first |
| `x6_pirate.jl refuse|refuse-first|tolerate|warn` | demo 1 step 6: a pirate of a sealed package (Pirate, or BasePirate loaded before the stack), refused by deletion, tolerated, or reported |
| `x7_trees.jl` | the audit of what is sealed: a full scan after each load (trait stack, DataFrames wrapper, Makie calls, the StaticArraysCore and ColorTypes wrappers), tolerations ignored, and for the two core wrappers what they would report without the implementations they name |
| `x9_ttfp_blame.jl [plain]` | time to first plot: recompilation blamed on the package whose method insertion invalidated it |
| `x10_load_validation.jl adhoc|app` | load-time validation of package images, instrumented: time and surviving cached code per image |
| `x11_filter.jl` | the patched Julia's insertion filter, A/B (`JULIA_TW_FILTER=0`) |
| `x12_viewcache.jl record|lean|before|after` | view caches: a representation Reports never saw, its first calls with and without the cache, CSV and Makie loaded before or after (stock or patched Julia) |
| `x13_makie_protected.jl [csvfirst]` | the ad-hoc time to first plot on the patched Julia with Makie's tree treated as trait-world code (`JULIA_TW_PROTECT`, measurement only) |
| `x14_makie_wrap.jl` | how close Makie is to a trait wrapper: the sealing audit with Makie wrapped, and `verify_main` over the Makie calls MakiePlots makes |
| `x15_makie_dispatch.jl` | the methods one plot reaches through dynamic dispatch (Julia's dispatch tracing), first plot and a second one |
| `verify_app.jl main|pipeline` | demo 2 step 1: `verify_main` on `App.main` or `Pipeline.pipeline`, targets by kind and normal-path holes by package |

The juliac builds are in `../build/build.sh` (`full` or `trim`). Run one heavy job at a time: the machine is shared, and the untrimmed build with Makie needs more memory than is usually free (session note 20).
