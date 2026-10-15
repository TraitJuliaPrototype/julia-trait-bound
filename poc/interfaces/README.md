# poc/interfaces — interface packages around DataFrames.jl and Makie.jl

The proof of concept planned in `writeup/poc3-plan.md` (read its §9 and §10,
the review corrections, first), on top of `TraitWorld/` and the packages in
`poc/world/` (Columns, Rows, Stats, UserTypes, Pirate, developed by path).
Julia 1.12.2; the registry packages are CSV 1.1.0, CairoMakie 0.15.16,
DataFrames 1.8.2, Makie 0.24.16, SnoopCompile 3.2.9, Tables 1.14.0.

    julia +1.12.2 --project=poc/interfaces/env -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'   # MakieInterface takes 80–120 s
    julia +1.12.2 --startup-file=no poc/interfaces/scripts/demo1.jl                                     # demo 1, steps 1–3, with --trace-compile
    julia +1.12.2 --startup-file=no --project=TraitWorld -e 'using Pkg; Pkg.test()'                     # 186 tests

State (2026-10-15, session 20): M0–M8 done and measured; M9 (the write-up
into the design documents and a Fable review) is next. The numbers below are
from fresh processes on one machine, single runs unless a range is given; the
session 20 reruns ran niced while another simulation shared the machine.

## Packages

| Folder | Kind | Content |
|---|---|---|
| `env/` | environment | the registry packages above and every path package |
| `Reports/` | trait package | `summarize(t; cols = 1:ncols(t))`, `zscores(t, i; baseline::ColTable = t)`, `histcounts(t, i; bins = 24)`, `colstd`; composes Columns and Stats (`ColSummary.wsum` is `Stats.weighted`, the piracy target) |
| `../world/Columns/ext/ColumnsDataFramesExt.jl` | extension of Columns | the DataFrame conformance (rule 5: the delegate, loaded with DataFrames): `@implement ColTable DataFrame project(df) = columns(df)`, the DataFrame's own column vectors as `Vector{Vector{Float64}}`, any other column type refused by name |
| `DataFramesInterface/` | interface package | `@interface_package DataFrames`; trait module `Frames`: `@handle Frame`, `frame(names, cols)` and `frame(names, t::ColTable)` (a declared constructor returning a handle), `nrows_of`, `ncols_of` |
| `MakieInterface/` | interface package | `@interface_package Makie` with CairoMakie as the backend; trait module `Plots`: handles `Figure`, `Axis`, `Plot`, trait `PointSeries`, declared calls `figure`, `axis!`, `scatter!`, `lines!`, `hist!` (Makie bins), `histbars!` (Reports bins, the bars cross), `vlines!`, `savefig`, `render`; `@recompile_invalidations` around the Makie imports; a workload at the declared signatures |
| `App/` | ordinary | `main`: CSV to DataFrame, `summarize`, a plot through MakieInterface, saved as PNG; `sinks()`; `data/sample.csv` (200 rows, three Float64 columns) |
| `Pipeline/` | ordinary | the trim variant: the same analysis fed by a small concrete CSV reader, text out, no DataFrames, no Makie |
| `BasePirate/` | adversary | `Base.sum(::Vector{Int8})`, no dependencies: the pirate that can load before the trait stack |
| `ChurnStorm/` | adversary | ported from `attic/ecosystem`: 100 types with Base methods, 20 redefinitions, at load |
| `scripts/` | | `demo_session.jl`, `demo1.jl`, `m0_plain.jl`, `x4_churn.jl`, `x5_redefine.jl`, `x6_pirate.jl`, `x7_trees.jl`, `x8_types.jl`, `verify_app.jl` (see `scripts/README.md`) |
| `build/` | | `build.sh`, `app_full.jl`, `app_trim.jl`: the juliac builds of demo 2; `app_trim` is the trimmed binary (not committed) |

BaseInterface is part of TraitWorld (`doors.jl`, `sealing.jl`), not a folder
here. The capability traits stay in `poc/world/BaseTraits` for now.

## Demo 1, the interactive session (`scripts/demo1.jl`)

Fresh process, `--trace-compile` on, all images fresh.

**Step 1.** `using TraitWorld, Columns, Stats, Reports, DataFramesInterface, MakieInterface`:
4.1 s before sealing, 9.1–10.3 s with the sealing scans at each top-level load
(see "Costs" below). Both interfaces register from their images with
their declared calls (MakieInterface 10, DataFramesInterface 3). Reports
imports Stats, Columns, TraitWorld and Base, nothing else.

**Step 2.** A `DataFrame` read from CSV, analysed and plotted; no trait module
imports DataFrames or Makie.

| call | time | compiling |
|---|---|---|
| `summarize(df)`, first result | 2.3 ms | 0.0 ms |
| `zscores(df, 1)` | 0.9 ms | 0.0 ms |
| `summarize(df; cols = [2, 3])`, a new keyword set | 0.2 ms | 0.0 ms |
| `histbars!(ax, df, 1)`, the trait world bins, Makie draws | 1.1 s | 1.4 s (Makie's first barplot) |
| `scatter!(ax, df, 1, 2)` | 260 ms | 400 ms (Makie's first scatter) |
| `render(f)` | 1.2 s | 1.8 s (Makie's first render) |

`--trace-compile` lists no worker, entry or builder of the trait stack
compiled at run time in step 2; the trait-stack lines it does list are the
script's own `@timed` tuples and the `sprint` of the refusal below. The
Makie costs are Makie's own first-plot costs, paid behind the declared calls
as ordinary code; the plain twin pays 12.5 s for its first plot without a
precompile workload (`m0_plain.jl`), MakieInterface's workload precompiles
the declared signatures.

The DataFrame's round trip: `frame(names(df), df)` returns a handle, and
`nrows_of(h)`, `ncols_of(h)` are declared calls back into DataFrames. A
DataFrame with an `Int` column is refused at the entry:
`TraitBoundError: column `n` of the DataFrame is a Vector{Int64}: a ColTable needs Vector{Float64} columns`.

**Step 3.** A new type at the REPL: `struct Measurements; data::Vector{Vector{Float64}}; end; @implement ColTable Measurements`.

| | trait world | plain twin (`m0_plain.jl`, two methods, generic code) |
|---|---|---|
| declaring the type's conformance | 540–680 ms (the one-line form's checks, see "Costs") | 0.6 ms |
| first `summarize(m)` | 10–14 ms (10–14 ms compiling: the projection per type) | 39 ms (39 ms compiling) |
| first plot | 25–28 ms (0.0–3.5 ms compiling) | 58 ms (40 ms compiling) |

The summary through `Measurements` equals the one through the DataFrame.
`x8_types.jl`, the marginal cost per additional type after a warm-up type,
six types, K = 6:

| mode | per type |
|---|---|
| Makie recipe (`convert_arguments` per type, Makie's pipeline compiles per type) | 297 ms |
| trait (`@implement ColTable T`, `histbars!`) | 36–41 ms |
| hand erasure (a generic bin-then-plot function, compiled per type) | 36 ms |

The trait route's 36–41 ms are the conformance declaration (inference of the
projection, the checks), not compiled workers; August's X8 measured 18 ms
on TraitRegions. The note's target of "a few milliseconds" is a target for
the machinery, not reached.

**Step 4, churn** (`x4_churn.jl`). The stack hot, then a churn source loads
under `@snoop_invalidations`:

| churn | invalidated instances, total | in the trait stack | the next calls compile |
|---|---|---|---|
| `using ChurnStorm` | 21 | 0 | 0.00 ms |
| `using CairoMakie` | 8687–8707 | 64, all TraitWorld's check and macro code | 0.00 ms |
| `using CairoMakie`, no trait stack loaded | 304 trees | – | – |

No worker, entry or builder is invalidated; the 64 are the checks' own code
(`worker_problems`, concrete mode, `@implement`'s macro code), which runs
again only at the next check or definition.

**Step 5, a worker redefined** (`x5_redefine.jl`): `Reports.colstd` redefined
in the session (through the trait module's own transform,
`Core.eval(Reports, :(TraitWorld.@stmt colstd(t::ColTable, i::Int) = …))`).
Two invalidation trees; 18 instances of Reports and 12 of TraitWorld, none
of DataFrames or Makie. The next `summarize(df)` takes 0.7–1.2 s (1.4–2.2 s
compiling): the worker and its dependents recompile, and the per-signature
check runs again because `checked_kwcall`'s generated code, which holds the
flag, is regenerated; most of the time is TraitWorld's check code being
recompiled after Makie's load invalidated it. The next plot compiles nothing.

**Step 6, a pirate** (`x6_pirate.jl`, four processes). `Pirate` defines
`Stats.weight(::Float64)`; `BasePirate` defines `Base.sum(::Vector{Int8})`.

| order and mode | what happens |
|---|---|
| stack, then `using Pirate`, refuse | `Error: PiracyError: Pirate defines 1 method on sealed functions and types it does not own: weight(x::Float64) … [needs Julia or Stats]. The methods were deleted (refuse mode) …`; `which(Stats.weight, (Float64,)).module === Stats`; `summarize(v)[1].wsum` stays 6.0; the load took 0.3–1.0 s with the scan |
| `using BasePirate` first, then the stack, refuse | found at the first seal's load, deleted (this needed the scan state reset in `__init__`: precompilation had serialized the scan cursor; session note 20) |
| stack, then `using Pirate`, tolerated | kept; the audit warns at the first call that reaches it, and `wsum` is plain Julia's 12.0 |
| stack, then `using Pirate`, warn mode | reported and kept; the audit's warning at the first call; `wsum` 12.0 |

Refusal is after the load, by deletion, because Base swallows exceptions
thrown by package callbacks (plan §9.3); a deleted method comes back only
with a restart, so refuse-then-tolerate is two processes.

**The audit of the trees** (`x7_trees.jl`): a full scan after each load, in
warn mode, with everything sealed that the loads seal and the tolerations
ignored, so that it shows what the lists must name.

| after | sealed names | piratical methods | packages | scan |
|---|---|---|---|---|
| Columns, Stats, Reports | 7 | 0 | – | 0.2 s |
| + DataFramesInterface (DataFrames' tree) | 30 | 4 | Tables (`nrow`, `ncol` of DataAPI for Base's types) | 0.5–0.7 s |
| + MakieInterface (Makie's tree, CairoMakie loaded) | 210 | 49 | OffsetArrays 12 (`getindex` on Base's ranges), Makie 8 (`deepcopy(::Observable)`, ComputePipeline's functions), FFTA 8 (AbstractFFTs' plans for Base's arrays), ImageCore 5, Interpolations 5, StatsBase 4 (`describe(x)` of DataAPI), Tables 4, IntervalSets 1 (a Makie recipe in its extension), PlotUtils 1, CompositionsBase 1 | 2.0–2.9 s |

These are the two interface packages' `[traits] tolerate` lists in their
Project.toml: `["Tables"]` for DataFramesInterface, the other nine for
MakieInterface. The session also loads CSV as ordinary code; its dependency
Durations defines `Dates.format` and `Dates.tryparsenext` for its own
`DatePart{'n'}`, piracy of Julia, which is sealed from the start, so
`env/Project.toml` tolerates it. With the lists in place demo 1 loads without
a piracy report. By the strict rule an extension owns only as its parent
does: CompositionsBase's InverseFunctions extension defining
`InverseFunctions.inverse` counts as a pirate, though its trigger owns the
function; whether triggers count as owners is open (session note 20).

**Step 7, the doors** (TraitWorld's tests, "poc3 M5"): a worker calling
`eval`, `task_local_storage()` or reading a module's non-constant global is
refused at its build with its line; `@warn` and `println` without an IO are
accepted as outward doors and recorded per worker signature (concrete mode
reports them); the same `task_local_storage` through a declared call of an
interface package is accepted.

## Demo 2, ahead of time (`scripts/verify_app.jl`, `build/build.sh`)

**Step 1, `verify_main` on the full application**, `App.main` (CSV,
DataFrames, CairoMakie): the trait part is closed: 11 trait dispatch sites, 8
targets (5 declared calls: `Figure`, `axis`, `vlines!`, `FileIO.save`,
`barplot!`; one entry; two workers); the build-time checks and the piracy
audit clean. The ordinary code around it has 140 normal-path holes of its
own: CSV 112, Base 17, DataFrames 11. 4.7–5.4 s.

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
| the 39 warnings | 36 in TraitWorld's entry steps and per-signature checks (`enter`'s slow and error paths, `kwfallback`, `checked_kwcall`, `_check_once`, `_guard`, behind barriers on paths that the closed world and the filled entry caches skip); 3 in TraitWorld's `__init__` reading the project's tolerations; none in the pipeline's own code |

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
  CairoMakie, and the first `summarize(df)` after `using MakieInterface`
  infers nothing.
- **The checks' own code is not immune**: `@implement`'s macro code and the
  rule-3 and concrete checks are reflection over Base's compiler, which
  Makie's tree invalidates (64 instances). Hence the 540–620 ms of the
  one-line conformance at the REPL after Makie is loaded (123 ms in
  `poc/world` without Makie) and most of step 5's recompile time.
- **Sealing's scan**: a walk over the functions and types bound in the
  loaded modules, filtered by `primary_world`: 0.2 s bare, 2.0–2.9 s with
  Makie loaded, once per top-level `using` (`_methods_by_ftype` took 10 s).
  The demo's load went from 4.1 s to 9.1–10.3 s with the scans. The owner of
  each method's module is looked up per method, so that lookup must be
  cached: an uncached walk over the loaded modules for every non-extension
  package (session 19's last change) made the full scan 15 s and the demo's
  load 29 s (plan §10.10, fixed in session 20).
- Precompile: MakieInterface 80–120 s (the `@recompile_invalidations` and
  the Makie workload), App 30–80 s, the rest seconds.

## What this shows and what it does not

Shown: a DataFrame enters a trait module through a projection owned by the
trait's package (its extension), and is plotted through declared calls,
without any trait module importing DataFrames or Makie; the workers come
from images; a new type conforms in one line and pays the projection only;
churn and Makie's load invalidate no trait-world code; a pirate of a sealed
package is refused at its load in either order, or tolerated into plain
Julia; the trait part of a program verifies closed.

Not shown or not reached: time to first plot is Makie's; the one-line
conformance costs half a second after Makie is loaded because the
machinery's check code is not immune; sealing refuses by deletion after the
load, not before the image's methods enter the table; the untrimmed build of
the full application did not fit in the memory this machine had free;
parametric user types, `Callable`'s keyword parameter and the capability
traits' move into BaseInterface are not done.
