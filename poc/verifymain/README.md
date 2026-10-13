# poc/verifymain — a main that only ever runs compiled code

`TraitRegions.verify_main(f, argtypes)` (`TraitRegions/src/verify.jl`) walks
the optimized code reachable from `f(argtypes...)` and classifies every call:

| class | meaning |
|---|---|
| static | `invoke` of a known CodeInstance, compiled with its caller |
| bounded | dynamic call with finitely many targets known now: concrete or small-Union argument types, methods on concrete types, or `@nospecialize` positions whose declared type mentions no type variable |
| trait | dynamic call made by the trait machinery (seal lookup, projection, entry→worker, witness call); the seals enumerate its targets |
| root | a closure handed to the runtime (task, `atexit` hook, finalizer), followed as an entry of its own |
| guard | the piracy guard's slow path; a verified closed-world build audits at build time instead |
| hole | anything else: a target depends on a runtime type nobody enumerated |

A hole is on an error path when every path from it ends in a throw that
nothing catches, neither a `try` in its function nor one in any caller on the
way to it. A call inferred `Union{}` counts as a throw unless it is `exit`,
or its callee can neither throw nor return (it exits or loops). Exits and
endless loops are normal paths.

The report also lists normal-path method instances without native code and a
build-time piracy audit of every enumerated worker. `compile = true` compiles
the entry and all enumerated targets (call it in the app's
`@compile_workload`). `entrypoints = true` registers them for `juliac --trim`.
In a trimmed build it also marks the build a closed world and switches the
guard off. The verdict holds for the world and the seals at the time of the
check: a later method definition, package load or seal can change it.

## Packages and scripts

| path | role |
|---|---|
| `program.jl` | minimal program over `poc/errorsplit` (Stats, MyTable) plus an app-owned `AppTab`: `main` (trait ops on an `Any` vector), `main_plain` (idiomatic generic code) |
| `VMApp`, `VMAppW` | the same program; workload `main(["1"])` (MyTab only) plus `verify_main(...; compile = true)` (VMApp) or not (VMAppW) |
| `eco_program.jl`, `EcoApp`, `EcoAppW` | the same on the ecosystem: EagerTable, LazyTable, MatTable; `report`, `report_dyn`, `summarize`, `colmean` |
| `observe.jl [minimal\|eco]` | per case, two fresh processes: the verifier's prediction after `using App`, and the run of `App.f(["4"])` observed through `--trace-compile` and the cumulative compile timer |
| `makie_holes.jl` | verifier reports for mains over the CairoMakie stack |
| `trim/` | `juliac --trim` builds: `build.sh` builds and runs the verified program, the same without entry points, and plain Julia |

    julia --project=poc/verifymain/env -e 'using Pkg; Pkg.instantiate()'
    julia --project=poc/verifymain/ecoenv -e 'using Pkg; Pkg.instantiate()'
    julia poc/verifymain/observe.jl            # minimal
    julia poc/verifymain/observe.jl eco        # ecosystem
    julia --project=poc/verifymain/ecoenv poc/verifymain/makie_holes.jl
    poc/verifymain/trim/build.sh

## Results (stock 1.12.2, October 2026)

Prediction vs observation, runtime input `["4"]` (both table types; the
workload saw only one):

| case | predicted | native compiles at runtime | compiler time |
|---|---|---|---|
| VMApp.main, guard off or warn | closed | 0 | 0.0 ms |
| VMAppW.main, guard off or warn | closed | 0 | 0.2 ms |
| VMApp(W).main_plain | 1 hole: `plainsum(::Any)` | 1: `plainsum(::AppTab)` | 12 ms |
| EcoApp.main, guard off or warn | closed | 0 | 0.0 ms |
| EcoAppW.main, guard off or warn | 2 uncompiled: `report`, `report_dyn` workers at `Matrix{Float64}` | the same 2 | 44 ms |
| before the `@seal` fix: EcoApp / EcoAppW | 5 / 7 uncompiled (seal closures) | the same 5 / 7 | |

Every prediction matched the observed native compiles one for one. The
compiler timer adds what the trace cannot see: 0.2 ms in the workload-only
minimal build, with no native compile.

`juliac --trim=unsafe-warn` of `VMApp.main` (`trim/`): trim's verifier reports
19 unresolved calls (seal lookup 5, projection 4, entry→worker 4, witness 2,
guard 4), every one a trait dispatch or guard site that `verify_main`
classifies and, except for the switched-off guard, enumerates. With its entry
points registered, the 1.9 MB binary runs and prints the same results as a
session (80.0 for 4 tables, 236.0 for 7). Without them it dies with a
`MethodError` (the seal lookup's target was trimmed away); `main_plain`
trimmed dies with `MethodError` on `plainsum(::MyTab)`; `--trim=safe`
refuses the build.

Real programs on the CairoMakie stack (`makie_holes.jl`), normal-path holes:

| main | holes | where |
|---|---|---|
| `compute_main` (trait ops incl. `ColPlots.histcounts`) | 28 | all in `histcounts`: its comprehension captures `lo` and `w`, which the loop reassigns, so they are boxed and every use is dynamic |
| `plot_main` (`histplot(t::Any, 1)` + render) | 16 | `histplot(::Any, …)` itself, then Makie's display path; the walk stops at holes, so this is a frontier |
| `plot_concrete` (one `EagerTable`, render) | 79 (59 distinct) | ColPlots 30, Observables 20, Makie 18, GridLayoutBase 5, Julia 4, script 2 |

Uncaught-error-path holes: 28 to 51, mostly `show` on values of unknown type
while building error messages. A run takes 0.5 to 2.9 s.

## Review (Fable 5.1) and fixes

The review reproduced every number above and found ways to get a false
CLOSED. Each is now a regression test in `TraitRegions/test/runtests.jl`
("verify_main"), and the reviewer's scripts now report OPEN:

| finding | fix |
|---|---|
| `f(@nospecialize(x::T)) where T` still specializes per runtime type: counted as bounded, crashed a trimmed binary | `@nospecialize` counts only where the declared type has no type variable |
| "cannot reach a value `return`" was taken for "on the way to a throw": a server loop, a main ending in `exit`, and a `try`-recovered exception all hid a hole | error path = every path ends in an uncaught throw; `try` regions of the function and of every caller on the path count as normal |
| closures run by the runtime (`@async`, `Task`, `Threads.@spawn`, `@threads`, `atexit`) were invisible | `jl_new_task`, `Task`, `atexit` and `finalizer` arguments become roots |
| the `@seal` compile hint did nothing for witnesses with abstract declared argument types | `@seal` compiles witnesses at the signatures the registered ops' workers call |
| `entrypoints = true` switched the guard off in any build | only when the build is trimmed |
| witnesses enumerated by table type merged traits with equal witness names | restricted to the enclosing worker's trait |
| traits without ops were missing from the registry | traits are collected from seals too |
| `--trace-compile` cannot see instances served by shared code or inference-only work | `observe.jl` also reports the cumulative compiler time |

## Lessons

1. Trait dispatch is dynamic dispatch with an enumerable target set: the
   prediction is exact and the verified builds compile nothing at runtime,
   on the ecosystem too. The verified build also closes the ownership gap
   (workers at `Matrix{Float64}`), because the app compiles them into its
   own image.
2. Plain Julia is bounded too when the methods are on concrete types (the
   current method table enumerates them); generic code on runtime-typed
   values is not. Seals are what make the set of types finite for generic
   code, and erasure keeps it small (one worker per representation). Both
   verdicts are per world: a later definition, load or seal can change them.
3. A downstream image cannot supply native code for a CodeInstance that
   lives, inferred only, in an upstream image. `@seal` now compiles the
   seal's code into the conformer's image, for the ops it can see.
4. In a trimmed binary a hole is a crash, not a compile. The verifier's
   enumeration is what makes trait dispatch survive trimming.
5. Nothing builds on a main, but a main builds on everything: its closure
   includes Base's printing, error formatting and task machinery. A `try`
   around trait-bound code pulls the error-message code onto the normal
   path (30 holes in the review's example).
6. Type instability inside a region worker is a hole like any other; the
   verifier doubles as a whole-closure type-stability check.
7. Makie's display path is dynamic at its core (attributes, Observables,
   screens). No trait discipline in user code closes it; that needs traits
   or concrete typing in Makie, or a policy that accepts it.

## Limits

The verifier models compiled code by re-running inference (`code_typed`),
not by reading the image; inlining is re-decided. Holes are a frontier: code
behind a hole is not walked or counted. A dynamic call inferred `Union{}`
counts as a throw unless it is `exit`, so one that loops forever is
misread. Seal lookups and projections are over-approximated over all seals
of the traits involved. `invoke`, `@atomic` modify, `@cfunction` and opaque
closures are reported as holes without analysis. A runtime type with no seal
reaches the `seal_info` fallback at a new signature: a compile in a session,
a `MethodError` in a trimmed binary (instead of the "not sealed" error).
`Any`-typed entry arguments make every use a hole. Not thread-safe.
