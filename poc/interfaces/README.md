# poc/interfaces — trait wrappers and calls upward around DataFrames.jl and Makie.jl

The proof of concept planned in `writeup/poc3-plan.md` (read its §9 and §10,
the review corrections, first), on top of `TraitWorld/` and the packages in
`poc/world/` (Columns, Rows, Stats, UserTypes, Pirate, developed by path).
Julia 1.12.2; the registry packages are CSV 1.1.0, CairoMakie 0.15.16,
DataFrames 1.8.2, Makie 0.24.16, SnoopCompile 3.2.9, Tables 1.14.0.

    julia +1.12.2 --project=poc/interfaces/env -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'   # MakiePlots takes 80–120 s
    julia +1.12.2 --startup-file=no poc/interfaces/scripts/demo1.jl                                     # demo 1, steps 1–3, with --trace-compile
    julia +1.12.2 --startup-file=no --project=TraitWorld -e 'using Pkg; Pkg.test()'                     # 199 tests, one @test_broken

State (2026-10-15, session 20): M0–M9 done and measured, and reworked for the
note at rev 1110: interface packages are gone, replaced by trait wrappers for
code that comes into the trait world (`DataFramesWrapper`, and the two core
wrappers) and by declared calls in an ordinary trait package for code that
stays outside (`MakiePlots`); sealing covers what workers compile against;
rule numbers are the note's four. The numbers below are
from fresh processes on one machine, single runs unless a range is given; the
session 20 reruns ran niced while another simulation shared the machine.

## Packages

| Folder | Kind | Content |
|---|---|---|
| `env/` | environment | the registry packages above and every path package |
| `Reports/` | trait package | `summarize(t; cols = 1:ncols(t))`, `zscores(t, i; baseline::ColTable = t)`, `histcounts(t, i; bins = 24)`, `colstd`; composes Columns and Stats (`ColSummary.wsum` is `Stats.weighted`, the piracy target) |
| `../world/Columns/ext/ColumnsDataFramesExt.jl` | extension of Columns | the DataFrame conformance (rule 3: the delegate, loaded with DataFrames): `@implement ColTable DataFrame project(df) = columns(df)`, the DataFrame's own column vectors as `Vector{Vector{Float64}}`, any other column type refused by name |
| `DataFramesWrapper/` | trait wrapper | `@trait_wrapper DataFrames`: brings DataFrames in (the projection reads its code), seals its tree, tolerates Tables; trait module `Frames`: `@handle Frame`, `frame(names, cols)` and `frame(names, t::ColTable)` (a declared constructor returning a handle), `nrows_of`, `ncols_of` |
| `MakiePlots/` | trait package with declared calls | Makie stays outside, never wrapped or sealed; CairoMakie as the backend; trait module `Plots`: handles `Figure`, `Axis`, `Plot`, trait `PointSeries`, declared calls `figure`, `axis!`, `scatter!`, `lines!`, `hist!` (Makie bins), `histbars!` (Reports bins, the bars cross), `vlines!`, `savefig`, `render`; `@recompile_invalidations` around the Makie imports; a workload at the declared signatures |
| `StaticArraysCoreWrapper/` | trait wrapper | `@trait_wrapper StaticArraysCore StaticArrays`: StaticArrays named as the implementation it delegates to, and a dependency |
| `ColorTypesWrapper/` | trait wrapper | `@trait_wrapper ColorTypes Colors ColorVectorSpace ImageCore`; tolerates ImageCore's `showarg` on FixedPointNumbers' types and OffsetArrays (which ImageCore brings) |
| `App/` | ordinary | `main`: CSV to DataFrame, `summarize`, a plot through MakiePlots, saved as PNG; `sinks()`; `data/sample.csv` (200 rows, three Float64 columns) |
| `Pipeline/` | ordinary | the trim variant: the same analysis fed by a small concrete CSV reader, text out, no DataFrames, no Makie |
| `BasePirate/` | adversary | `Base.sum(::Vector{Int8})`, no dependencies: the pirate that can load before the trait stack |
| `ChurnStorm/` | adversary | ported from `attic/ecosystem`: 100 types with Base methods, 20 redefinitions, at load |
| `scripts/` | | `demo_session.jl`, `demo1.jl`, `m0_plain.jl`, `x4_churn.jl`, `x5_redefine.jl`, `x6_pirate.jl`, `x7_trees.jl`, `x8_types.jl`, `verify_app.jl` (see `scripts/README.md`) |
| `build/` | | `build.sh`, `app_full.jl`, `app_trim.jl`: the juliac builds of demo 2; `app_trim` is the trimmed binary (not committed) |

The Base wrapper is implicit, part of TraitWorld (`doors.jl`, `sealing.jl`),
not a folder here; the machinery is `TraitWorld/src/wrapper.jl` and
`calls.jl`. The capability traits stay in `poc/world/BaseTraits` for now.

## Demo 1, the interactive session (`scripts/demo1.jl`)

Fresh process, `--trace-compile` on, all images fresh.

**Step 1.** `using TraitWorld, Columns, Stats, Reports, DataFramesWrapper, MakiePlots`:
4.1 s before sealing, 6.0–6.1 s with the sealing scans at each top-level load
(9.1–10.3 s with the earlier names walk; see "Costs" below). The DataFrames
wrapper registers from its image; MakiePlots and DataFramesWrapper hold their
declared calls (10 and 3). Reports
imports Stats, Columns, TraitWorld and Base, nothing else.

**Step 2.** A `DataFrame` read from CSV, analysed and plotted; no trait module
imports DataFrames or Makie.

| call | time | compiling (of which recompiling) |
|---|---|---|
| `summarize(df)`, first result | 2.1–2.8 ms | 0.0 ms |
| `zscores(df, 1)` | 0.8–1.1 ms | 0.0 ms |
| `summarize(df; cols = [2, 3])`, a keyword type in Reports' workload | 0.2 ms | 0.0 ms |
| `summarize(df; cols = (2, 3))`, a keyword type the image lacks | 884 ms | 868 ms (734 ms) |
| `histbars!(ax, df, 1)`, the trait world bins, Makie draws | 1.07 s | 1.07 s (0.33 s), Makie's first barplot |
| `scatter!(ax, df, 1, 2)` | 252 ms | 250 ms (137 ms), Makie's first scatter |
| `render(f)` | 1.19 s | 1.17 s (0.60 s), Makie's first render |

(Earlier runs printed compile plus recompile time, which double-counts:
Base's `recompile_time` is part of `compile_time`. Fixed in session 20.)

`--trace-compile` lists no worker, entry or builder of the trait stack
compiled at run time for the calls at signatures the images hold; the
trait-stack lines it does list are the script's own `@timed` tuples and the
`sprint` of the refusal below. A keyword type the image lacks is another
matter: plain Julia compiles the sorter and body for it in 46 ms
(`m0_plain.jl`), the trait world in 0.9 s, most of it recompiling the
per-signature check (rule 3, the door walk), whose code Makie's load
invalidated (step 4). That is the cost of a new signature at an entry after
a big load, the same cause as the one-line conformance's half second.

The Makie costs are Makie's own first-plot costs, paid behind the declared
calls as ordinary code, and they remain although MakiePlots's workload
covers these signatures: a third of each is recompilation, which suggests
that the loads after MakiePlots (CSV, DataFrames) invalidate part of
what the workload compiled (not traced further). The plain twin's first plot
(`m0_plain.jl`: bins, `barplot!`, `colorbuffer` in one number, no workload,
CSV and DataFrames loaded first) takes 13.4 s; the two are not comparable
measurements, only an indication of what a workload saves.

The DataFrame's round trip: `frame(names(df), df)` returns a handle, and
`nrows_of(h)`, `ncols_of(h)` are declared calls back into DataFrames. A
DataFrame with an `Int` column is refused at the entry:
`TraitBoundError: column `n` of the DataFrame is a Vector{Int64}: a ColTable needs Vector{Float64} columns`.

**Step 3.** A new type at the REPL: `struct Measurements; data::Vector{Vector{Float64}}; end; @implement ColTable Measurements`.

| | trait world | plain twin (`m0_plain.jl`, two methods, generic code) |
|---|---|---|
| declaring the type's conformance | 540–680 ms (the one-line form's checks, see "Costs") | 0.6–0.7 ms |
| first `summarize(m)` | 10–14 ms (10–14 ms compiling: the projection per type) | 39–45 ms (all compiling) |
| first plot | 25–31 ms (0.0–3.5 ms compiling) | 58–65 ms (40–46 ms compiling) |

The summary through `Measurements` equals the one through the DataFrame.
`x8_types.jl`, the marginal cost per additional type after a warm-up type,
six types, K = 6:

| mode | per type |
|---|---|
| Makie recipe (`convert_arguments` per type, Makie's pipeline compiles per type) | 297 ms |
| trait (`@implement ColTable T`, `histbars!`) | 35–47 ms |
| hand erasure (a generic bin-then-plot function, compiled per type) | 36 ms |

The trait route's 35–47 ms (43–47 ms after the rework, at a load average of 4.4 against 3 before: load or the wrapper lookup in `is_trait_world`, not separated) are the conformance declaration (inference of the
projection, the checks), not compiled workers; August's X8 measured 18 ms
on TraitRegions. The note's target of "a few milliseconds" is a target for
the machinery, not reached.

**Step 4, churn** (`x4_churn.jl`). The stack hot, then a churn source loads
under `@snoop_invalidations`:

| churn | invalidated instances, total | in the trait stack | the next calls compile |
|---|---|---|---|
| `using ChurnStorm` | 21 | 0 | 0.00 ms |
| `using CairoMakie` | 8687–8707 | 64, all TraitWorld's check and macro code | 0.00 ms |

Without the trait stack loaded, `using CairoMakie` gives 304 invalidation
trees (the script counts trees in that mode, not instances). No worker, entry or builder is invalidated; the 64 are the checks' own code
(`worker_problems`, concrete mode, `@implement`'s macro code), which runs
again only at the next check or definition.

**Step 5, a worker redefined** (`x5_redefine.jl`): `Reports.colstd` redefined
in the session (through the trait module's own transform,
`Core.eval(Reports, :(TraitWorld.@stmt colstd(t::ColTable, i::Int) = …))`).
Two invalidation trees; 18 instances of Reports and 12 of TraitWorld, none
of DataFrames or Makie. The next `summarize(df)` takes 0.86–1.07 s (0.84–1.05 s compiling, 0.80–1.0 s of it
recompiling; earlier runs, double-counted, 0.7–1.2 s): the worker and its dependents recompile, and the per-signature
check runs again because `checked_kwcall`'s generated code, which holds the
flag, is regenerated; most of the time is TraitWorld's check code being
recompiled after Makie's load invalidated it. The next plot compiles nothing.

**Step 6, a pirate** (`x6_pirate.jl`, four processes). `Pirate` defines
`Stats.weight(::Float64)`; `BasePirate` defines `Base.sum(::Vector{Int8})`.

| order and mode | what happens |
|---|---|
| stack, then `using Pirate`, refuse | `Error: PiracyError: Pirate defines 1 method on sealed functions and types it does not own: weight(x::Float64) … [needs Julia or Stats]. The methods were deleted (refuse mode) …`; `which(Stats.weight, (Float64,)).module === Stats`; `summarize(v)[1].wsum` stays 6.0; the load took 0.08 s with the scan (0.3–1.0 s with the earlier names walk) |
| `using BasePirate` first, then the stack, refuse | found at the first seal's load, deleted (this needed the scan state reset in `__init__`: precompilation had serialized the scan cursor; session note 20) |
| stack, then `using Pirate`, tolerated | kept; the audit warns at the first call that reaches it, and `wsum` is plain Julia's 12.0 |
| stack, then `using Pirate`, warn mode | reported and kept; the audit's warning at the first call; `wsum` 12.0 |

Refusal is after the load, by deletion, because Base swallows exceptions
thrown by package callbacks (plan §9.3); a deleted method comes back only
with a restart, so refuse-then-tolerate is two processes. This makes refuse
mode order-dependent in a way the note's semantics are not: a wrapper's
tolerations are registered when the wrapper loads, so a package of its tree
that loaded before the first trait package (say OffsetArrays, with 12
methods on Base, before ColorTypesWrapper) is scanned at the first seal, its
methods deleted, and ImageCore then runs without them although the wrapper
would have tolerated them. Under the note the seal's load fails instead and
nothing is broken. Reading every wrapper's tolerations from the active
manifest when TraitWorld loads would remove the order dependence; not done.
Warn mode, the default, reports each definer once per session.

**The audit of what is sealed** (`x7_trees.jl`): a full scan after each
load, in warn mode, tolerations ignored, so that it shows what the lists must
name. Sealing covers what workers compile against: the trait packages, what
the wrappers bring in with their implementations and dependencies, and Julia;
Makie, reached only by calls upward, is not sealed.

| after | sealed names | piratical methods | packages | scan |
|---|---|---|---|---|
| Columns, Stats, Reports | 7 | 0 | – | 0.02 s |
| + DataFramesWrapper (seals DataFrames' tree) | 30 | 4 | Tables 4 (DataAPI's `nrow`, `ncol` for Base's types) | 0.14 s |
| + MakiePlots (calls into Makie, CairoMakie loaded) | 31 | 20 | OffsetArrays 12 (`getindex` on Base's ranges: piracy of Julia), StatsBase 4 (DataAPI's `describe`, and a deprecated `quantile` on Base's arrays), Tables 4 | 0.67 s |
| + StaticArraysCoreWrapper | 34 | 20 | none new; without StaticArrays named: StaticArrays 511 | 0.61 s |
| + ColorTypesWrapper | 47 | 26 | ImageCore 5 (`showarg` on FixedPointNumbers' and MappedArrays' types), PlotUtils 1 (`convert(::Type{RGB}, ::Unsigned)`); without its implementations named: ColorVectorSpace 153, Colors 42, ImageCore 17 | 0.65 s |

So with Makie behind declared calls, what is sealed is small and what pirates
it is real: Base's ranges redefined by OffsetArrays (a working Base method's
result changes), and DataAPI's functions at Base's types once DataFrames is
wrapped. The core wrappers absorb the split packages: 511 StaticArrays methods
and 212 of Colors, ColorVectorSpace and ImageCore are their cores' delegates'.
Two findings remain with ColorTypes wrapped: ImageCore's `showarg` methods are
at other packages' types, so naming ImageCore does not cover them, and
PlotUtils, which loads with Makie as ordinary code, pirates ColorTypes once
ColorTypes is sealed: wrapping a core makes the pirates of it visible in
every tree that is loaded beside the wrapper.

The lists: DataFramesWrapper tolerates Tables; ColorTypesWrapper tolerates
ImageCore and OffsetArrays (which ImageCore brings); the project
(`env/Project.toml`) tolerates what it loads as ordinary code and what
pirates Julia or a wrapped core from outside a wrapper's tree: Durations
(CSV's, `Dates.format` for its own `DatePart{'n'}`), OffsetArrays, PlotUtils
and StatsBase. With the lists in place demo 1 loads without a piracy report.
An extension owns only as its parent does (rule 3: triggers confer nothing).

Before session 20's rework, `@interface_package Makie` sealed Makie's whole
dependency tree and the counts were 49 methods after TraitWorld's built-in
implementer declarations and 1091 without them (StaticArrays 794 among
them); both the closure-wide sealing and the built-in list are gone.

**Step 7, the doors** (TraitWorld's tests, "poc3 M5"): a worker calling
`eval`, `task_local_storage()` or reading a module's non-constant global is
refused at its build with its line; `@warn` and `println` without an IO are
accepted as outward doors and recorded per worker signature (concrete mode
reports them); the same `task_local_storage` through a declared call of an
trait module is accepted. The walk into Base has a budget (3000
method instances); where it stops, a warning says the rest is unchecked,
whatever the concrete level (the seven demo workers stay well inside it). On
stock Julia the check is static: an inward door behind a dynamic call
(`Base.inferencebarrier(eval)(…)`) is not seen, which the design closes by
checking a dynamic call's target when it compiles (a `@test_broken` in the
tests). The standard libraries count as Julia, so `Pkg`, `REPL`,
`InteractiveUtils` and `Test` are in the trait world here, though the note
counts them as ordinary code.

## Time to first plot, end to end (`scripts/x9_ttfp_blame.jl`)

A fresh process, reading `sample.csv`, summarizing it and saving a histogram
as PNG, measured with `time()` laps (session 20, niced, shared machine):

| | ad-hoc session: `using` the trait stack, DataFramesWrapper, MakiePlots, CSV, DataFrames | plain Julia, the same calls | `using App`, then `App.main` |
|---|---|---|---|
| load | 6.6–7.2 s | 5.2 s | 6.0–6.3 s |
| read, summarize, plot, PNG | 14.4–15.1 s | 22.2 s | **0.35 s** |
| to the first PNG | 21.2–21.7 s | 27.4 s | **6.4–6.6 s** |
| compiling during the work (of which recompiling) | 14.5–15.1 s (7.2–7.7 s) | 22.3 s (7.7 s) | 0.45 s (0) |

`x9_ttfp_blame.jl` joins `@snoop_invalidations` of the loads with
`@snoop_inference` of the work: in the ad-hoc session 14 of the 15 s of
inference (profiled, so inflated) re-infer code that a load invalidated, and
1.3 s is fresh. The cause is not piracy and not the trait stack: one method,
`Base.thisind(::InlineStrings.InlineString, ::Int)`, a legitimate method for
InlineStrings' own type (a dependency of CSV), invalidates Makie's text code
that calls `thisind` on abstract strings: 8.4 s; SentinelArrays (CSV's) adds
about 3.8 s, Makie's tree invalidating itself (`broadcasted` for
`Makie.EndPoints`, GeometryBasics, FreeTypeAbstraction, FilePathsBase) the
rest. Load order changes nothing: a package image is checked against the
method table when it loads.

`App` depends on all of them and its workload runs this path, so its image
holds Makie's code compiled with InlineStrings present: after the load, the
read and the plot take 0.35 s and compile nothing again. That is rule 4: code
for a combination of packages lives in a package that depends on all of them,
and an ad-hoc session, where nothing does, compiles the combination itself.
Plain Julia gets the same from an application package with a workload; the
design's contribution is the rule that says where such code lives, and the
guarantee that loads cannot invalidate it inside the trait world. What remains
is the load: CairoMakie's image alone takes about 4.2 s, the trait stack and
its scans about 1 s.

**Combination caches (`ComboCache/`), rule 4 for ad-hoc sessions.** Session 1
runs with `--trace-compile=<file>`; `ComboCache.generate` writes a package that
depends on the project packages the session loaded, importing them **in the
session's load order**, with the recorded compilations as its workload;
`ComboCache.build` precompiles it in a background process (niced, 33 s here);
in later sessions `ComboCache.load()`, after the `using`s, loads it, which adds
no package, only compiled code:

| ad-hoc session, `using` the stack, MakiePlots, CSV, DataFrames | first PNG | read, summarize, plot, PNG after loading | compiling (recompiling) |
|---|---|---|---|
| without a cache | 21.2–22.2 s | 14.4–15.1 s | 14.5–15.0 s (7.2–7.7 s) |
| a package extension of MakiePlots for CSV (removed) | 10.3–11.7 s | 4.2–4.7 s | 4.5–5.1 s (2.7–3.2 s) |
| a combination cache with imports in alphabetical order | 11.1–11.5 s | 4.3–4.5 s | 4.8–5.0 s (3.1–3.2 s) |
| a combination cache with imports in the session's load order | **7.5 s** | **0.34 s** | 0.8 s (0.12 s) |

The load order is the finding: whether cached code is still valid depends on
which packages loaded before which, so code compiled in a process that loads
the same packages in another order can be valid there and invalid in the
session. With alphabetical imports the build process kept Makie's code for
`initialize_block!(::Axis)` and the `Figure` and `Scene` constructors valid,
replayed them as no-ops and stored nothing, while the session had invalidated
them (1.4 s for `initialize_block!` alone). A build that loads in the
session's order invalidates what the session invalidates, recompiles it during
the replay and stores it, which is also why `App`'s image works (its imports
are the session's order). The extension, which inherits the order of an
extension precompile, kept 286 of its Makie CodeInstances invalid in the
session (`x10_load_validation.jl`).

**Automatic: `ComboCache.auto()` in `startup.jl`.** A combination is keyed by
its packages, their versions and their load order (stored under
`[combocache]` in the generated `Project.toml`); a `.built` marker next to the
package says its image is complete. `auto()` registers a package callback
that, after each top-level `using`, loads the largest built combination whose
packages are all loaded in the session, in the same order and at the same
versions. If the session was started with `--trace-compile=<file>`, it also
records the session at exit: a `pending-<pid>.toml` names the trace, the
packages and their order, and a detached, niced process waits for the session
to end (the trace is complete only then), loads the packages in that order,
generates the combination and builds it. The builder claims the record by
renaming it (atomic), so two builders never work on the same session.

    # ~/.julia/config/startup.jl
    using ComboCache; ComboCache.auto()

    julia --trace-compile=trace.jl …   # session 1: work as usual; built after exit
    julia …                            # session 2: the combination loads after the `using`s

End to end (session 1 recorded, its combination built, session 2 with the
same `using`s): the combination loaded by itself, and the read, summary, plot
and PNG took 0.21–0.24 s after loading, 0.18–0.19 s of it recompiling.

Limits: recording needs the command-line flag (1.12 has no way to trace
compilations to a file from inside a session without redirecting the process's
stderr). The builder knows the session ended when its process id is gone,
or, on Linux, when `/proc/<pid>/cmdline` no longer names the trace file
(process ids are reused); inside the Claude Code sandbox `/proc` does not show
the sandbox's processes, so only the id is checked there, and detached
processes are killed when the command that started them ends, so the e2e run
above ran the builder step by hand. A lock held by the session for its
lifetime would work everywhere; not built.

**The load.** `@time_imports using App`: 285 packages, 3.9 s of package
loading with 0.02 s of compilation in it (Makie 1.06 s, MakiePlots 0.33 s,
then a long tail); the rest of the 6 s, about 2 s, is outside the
per-package timer and not broken down here. The native code is linked in
already; the time is deserializing, uniquing and validating the Julia-level
data of each image (types, methods, method tables, the edges of cached code
against the current method table) and running `__init__`, which a sysimage
avoids by being one pre-merged, pre-validated world.

## Invalidation filter on a patched Julia (`scripts/x11_filter.jl`)

The attic's Julia 1.12.2 with `attic/binary/trait_world_filter_v1.patch`: a
method insertion does not invalidate code of a trait module or of TraitWorld
when the new method comes from outside the trait world and Julia and its
definer owns a type or the function in its signature; pirates invalidate as
before. A/B on the same build, after the stack, DataFramesWrapper, MakiePlots,
CSV and DataFrames load:

| | filter on | filter off |
|---|---|---|
| invalidations skipped | 92 | 0 |
| first `summarize(m)` for a new type | **54 ms** (0 recompiling) | 227 ms (211 ms recompiling) |
| first one-line `@implement` | 651–738 ms (166–189 ms recompiling) | 846–987 ms (257–295 ms) |
| first call at a keyword type the images lack | 1010 ms (883 ms recompiling) | 1264 ms (1137 ms) |
| a second new type | 24 ms | 29 ms |

TraitWorld's tests pass on the patched build with the filter on (199). The
trait modules' own code no longer recompiles; what still does is Base's and
the Compiler's code that TraitWorld's checks call (`code_typed`, method
lookup), which Makie's tree invalidates and which ordinary code shares, so
the filter must not protect it. The design's answer is the other half of
trade-off 8, trait-world instances of Base code compiled separately, which
this patch does not attempt.

## Demo 2, ahead of time (`scripts/verify_app.jl`, `build/build.sh`)

**Step 1, `verify_main` on the full application**, `App.main` (CSV,
DataFrames, CairoMakie): the trait part is closed, meaning: no normal-path
hole whose caller is in the trait stack (0), and every trait dispatch site
has enumerated targets (11 sites, 8 targets: 5 declared calls, `Figure`,
`axis`, `vlines!`, `FileIO.save`, `barplot!`; one entry; two workers); the
build-time checks and the piracy audit clean. The program as a whole is
open: the ordinary code has 140 normal-path holes (CSV 112, Base 17,
DataFrames 11), and the code behind the five declared calls, all of Makie's,
is not walked at all. Declared targets with keywords are listed without
their keywords (`Tuple{Type{Figure}}` for `Figure(; size)`). The plan's
"outward doors bound to the application's declared sinks" is not
implemented (`App.sinks()` is a placeholder). 3.7–5.4 s.

**Step 2, the untrimmed juliac build of `App`**: not built. On this machine
(30 GB, shared with another simulation) the build reaches LLVM's code
generation for the whole image (`jl_dump_native`) and then needs about 14 GB
more than was free: killed by a memory guard at 4 GB available, after 5.5 min
with the default image threads and after 19 min with `JULIA_IMAGE_THREADS=1`.
An earlier attempt, run in parallel with other jobs, took the machine down
(session note 20). It needs a machine with the memory to itself.

**Step 3, the trimmed pipeline**, `Pipeline.pipeline` (Columns, Stats and
Reports, a small concrete CSV reader, text out):

| | |
|---|---|
| `verify_main` | 6 trait dispatch sites, 3 targets (one entry, two workers), checks and audit clean; 1 normal-path hole, the builtin `invoke_modify` in Base's scheduler `wait()`, which IO reaches |
| binary | 3.53 MB, 39 trim verifier warnings |
| run | 0.02 s, 49 MB RSS, the same summary and histogram as in the session |
| the 39 warnings | 10 are the entry's two dynamic steps on the normal path of every call, the builder (`b(t)` with `b` from the entry's cache) and the worker (`checked_kwcall(…, enter(…)::Any)`): their targets are registered as entry points by `verify_main` and found by dispatch at run time, the "finitely many targets" of the note's AOT section; 26 are error, slow and check paths that the closed world skips (`_rule3_error`, `_closed_miss`, `_enter_slow`, `kwfallback`, `_check_once`, `_guard_slow`); 3 are TraitWorld's `__init__` reading the project's tolerations; none is in the pipeline's own code |

For comparison, `poc/world`'s M7 binary: 2.09 MB, 47 warnings. Two
earlier binaries built and died at their first dynamic call, one with
DelimitedFiles' `readdlm`, one at `readlines`' `ondone` closure; in both cases
`verify_main` had listed the call as a normal-path hole of the ordinary code,
as it had `rpad` and the `show` of a vector, which the pipeline now avoids by
printing one value per `print`. So the ordinary code's holes are exactly what
decides whether a trimmed binary runs, and `verify_main` names them before
the build.

## Costs of the machinery, and what was fixed

- **Entries lost their cached code at unrelated loads** (session note 19,
  findings 1 and 3): the error paths and the slow path of the machinery had
  inference edges into Base's generic code at abstract types. After the
  sweep (barriers around message formatting and reflection, typed loops
  instead of `any`/`findfirst` on untyped vectors) every entry of Columns,
  Stats and Reports keeps its code through the loads of DataFrames, CSV and
  CairoMakie, and the first `summarize(df)` after `using MakiePlots`
  infers nothing.
- **The checks' own code is not immune**: `@implement`'s macro code and the
  rule-3, door and concrete checks are reflection over Base's compiler,
  which Makie's tree invalidates (64 instances). Hence the 540–680 ms of the
  one-line conformance at the REPL after Makie is loaded (123 ms in
  `poc/world` without Makie), the 0.9 s of an entry's first call at a
  keyword type the image lacks, and most of step 5's recompile time.
- **Sealing's scan**: Julia 1.12 keeps every method in one global table
  (`Core.methodtable`), and a visit of it, filtered by `primary_world`,
  costs 0.02 s bare and 0.03 s with Makie loaded; with the ownership checks
  a full scan takes 0.02–0.81 s, once per top-level `using` (0.02–0.67 s with sealing scoped to the views). The demo's load
  went from 4.1 s to 6.1 s with the scans. The first version walked the
  functions and types bound in the loaded modules (Aqua's way): 2.3 s with
  Makie loaded, blind to call methods of callable types (`(::Base.Fix1{…})(x)`,
  found by the review), and an uncached ownership lookup per method made it
  15 s for a while (plan §10.10, §10.11); `_methods_by_ftype` took 10 s.
- Precompile: MakiePlots 80–120 s (the `@recompile_invalidations` and
  the Makie workload), App 30–80 s, the rest seconds.

## What this shows and what it does not

Shown: a DataFrame enters a trait module through a projection owned by the
trait's package (its extension), and is plotted through declared calls,
without any trait module importing DataFrames or Makie; the workers come
from images; a new type conforms in one line, and its compiled code is the
projection only; churn and Makie's load invalidate no worker, entry or
builder (only the checks' own code); a pirate of a sealed package is
refused at its load in either order, or tolerated into plain Julia; the
trait part of a program verifies closed (no hole in the trait stack, every
trait site enumerated; declared targets not walked), and the trait-world
pipeline trims to a 3.5 MB binary that runs.

Not shown or not reached: time to first plot is Makie's; the one-line
conformance and an entry's first call at a new signature cost half a second
to a second after Makie is loaded, because the machinery's check code is not
immune; the piracy counts rely on implementer declarations the PoC makes on
the packages' behalf (1091 methods without them); sealing refuses by
deletion after the load, which makes refuse mode depend on the load order;
the door check is static, so a door behind a dynamic call is not seen; the
standard libraries all count as Julia; outward doors are not bound to
declared sinks; the untrimmed build of the full application did not fit in
the memory this machine had free; parametric user types, `Callable`'s
keyword parameter and the capability traits' move into the Base wrapper are not
done.
