# Plan: Tables, DataFrames and CSV in the trait world (demonstrator 4)

Written 2026-10-17 (session 27, Fable 5.1), on the user's request: "We should do the DataFrames Traits version. Take the full Tables.jl, DataFrames.jl and CSV.jl packages. Design traits that express the behaviors DataFrames needs from its Series, Columns, Tables, etc. Incorporate traits where it is natural to do so. Show that bringing traits into the system enables interactive work at Python speeds for the full stack on the patched binary."

Context: the fresh-eye review (`writeup/reviews/2026-10-17-demonstrators-fresh-eye.md`, B1, B2, S3) found that the demonstrators compare small trait libraries against small plain baselines, and that no row measures an interactive session. This plan answers both at once: the baseline becomes the real upstream packages, unmodified, and the measured object is a REPL session.

Terms as in `writeup/notes/4-details.md`: trait, conformance, key, worker, entry, `Dynamic{X}`, fact, run-time site. "Upstream" means the registry versions in the depot: Tables 1.14.0 (`~/.julia/packages/Tables/qGyu7`), DataFrames 1.8.2 (`DataFrames/0Y1g5`), CSV 1.1.0 (`CSV/E5gMM`), the versions `TraitReport/env/Manifest.toml` resolves to. "Forks" means our copies with traits. "Patched" means `julia-1.13/julia`; "image" means the TraitWorld system image of `experiments/sysimage`.

## 0. The claim, made falsifiable

**Claim.** On the patched build with the TraitWorld system image, a fresh interactive session over the forks (REPL loaded first; the forks' package images precompiled; view caches off for the primary number) does the workload of §4 with every step after `using` at a first-call time of at most 100 ms for column types the images hold, and the whole session, imports excluded, in at most 1 s. Loading other packages before or after changes no step by more than the noise floor and discards no policy-compiled code of the forks. A column type that enters through a newly loaded package (InlineStrings' `String15`, PooledArrays' `PooledVector`) costs at most 1 s at its first use in the first session and at most 100 ms in later sessions.

**Python for comparison** (pandas 3.0.6, this machine): imports 0.39–0.41 s (`TraitReport/README.md`, fresh-session table); each step of §4 in 1–30 ms; the session, imports excluded, about 0.2–0.4 s (to be measured in M0).

**What counts as failure.**
- Any step with image-held column types above 1 s at first call, or the session above 3 s imports excluded.
- Any policy-compiled CodeInstance of the forks lost to a load from the matrix of §4.3.
- Upstream on the same patched build within 1.5× of the forks on the session total: then the gain is the Julia patch (piece 5 and others), not the traits. This is the control the review asked for (B2, S1); `TraitReport/README.md` already shows piece 5 alone speeds up a plain package 2×.
- A port that fails the upstream test suites (§1.3) is not a port; its numbers do not count.

**What is not claimed.** Imports at pandas' 0.4 s (Julia's startup is 0.10 s, DataFrames' image alone loads in 0.36 s today; the plausible target is 1.0 s). Zero cost for a column type no image has ever seen (the first worker set for a new key compiles: 0.1–1 s, then cached). Stock Julia: without piece 5 every session compiles the policy's code again (`writeup/notes/3-wrapping.md`, "What Julia must provide"); the stock column is reported as the price of the missing piece, not as a result. Threads, AOT binaries and strict mode are out of scope (§6).

## 1. Scope

### 1.1 Forks, not rewrites

Three repositories under `forks/`, each a `git clone` of the upstream repository checked out at the exact depot version (Tables v1.14.0, DataFrames v1.8.2, CSV v1.1.0), so that `git diff v1.8.2` is the port. Package names and UUIDs stay upstream's: the upstream test suites, and every package that says `using DataFrames`, then work unchanged, and the forks are drop-in replacements in an environment that points at them with `[sources]`. Baseline environments resolve the registry versions; fork environments the paths. The two never share an environment.

| Fork | Owns | Trait modules added | Stays plain |
|---|---|---|---|
| `forks/Tables` | the traits `Column{T}` and `TableSource`; conformances for Base's and Tables' own types; `TablesPooledArraysExt`, `TablesCategoricalArraysExt` | `Tables.ColumnCore` | the duck-typed interface (`istable`, `columns`, `rows`, `getcolumn`, `columnnames`, `schema`), `Tables.Scan`, dict and matrix tables |
| `forks/DataFrames` | `DataFrame` with `columns::Vector{Dynamic{Column}}`; conformances for `SubDataFrame` and `DataFrameRow` to `TableSource`; per-key workers for the hot functions | `DataFrames.ColumnKernels` (describe, show cells, sort, take, hash, aggregates, join keys, subset) | the index, metadata, the `=>` mini-language normalization, reshape, broadcasting, PrettyTables rendering, insertion bookkeeping |
| `forks/CSV` | `CSVColumn{T} <: Column`; conformances for the built-in cell types; `CSVInlineStringsExt` rewritten as conformances | `CSV.ColumnParsers` | the SIMD structural index, delimiter and type detection, `Rows`, `Chunks`, `lazy`, the writer kernel, problems |

TraitTables and TraitCSV (session 27) are absorbed: `TableCore` moves into the Tables fork, `CSVCore` into the CSV fork. The two small repositories stay as history; TraitReport form (t) is re-pointed at the forks in M11 (or kept as the small-library row, labelled).

### 1.2 Adoption, one function at a time

The design allows this (`3-wrapping.md`, "Adopting traits, one function at a time"): a trait bound ranks below every type and above `Any`, so adding a bounded method changes only calls that reached the fallback. The storage change is the root, and it is one line (`forks/DataFrames/src/dataframe/dataframe.jl:179`). Every function that reads `_columns(df)[i]` (`dataframe.jl:441`) then receives a `Dynamic{Column}`; functions that need the vector itself call the `parent` operation (§2.1); functions on the interactive path are rewritten as bounded workers (§2.5); the rest keep upstream's code over the vector. The port is therefore incremental, and at every milestone the test suites decide.

### 1.3 Correctness bar: the upstream test suites

- **DataFrames:** `test/runtests.jl`, all 29 files (about 41 k lines with CSV's), on the patched build, with `-t 1` (and `-t 4` for `multithreading.jl`, see R2). Test dependencies absent from the depot: CategoricalArrays, Combinatorics, DataValues, ShiftedArrays. M1 checks whether the registry (`~/.julia/registries/General.toml` is present) can fetch them; if not, the files that need them are run with those sections skipped and the skip is recorded in the README with line counts. Tests that reach into `DataFrames._columns(df)` and expect a `Vector{AbstractVector}` are adapted; each adapted line is listed.
- **CSV:** `test/runtests.jl` (cpu, tasks, kernel, api, decimals, write, fuzz, scan). DataDecimals is absent from the depot: `decimals.jl` is skipped if it cannot be fetched. `kernel.jl` is exhaustive over chunk geometries and may run long; it runs alone, niced.
- **Tables:** `test/runtests.jl` and `test/scan.jl`. DataValues and QueryOperators are absent; the DataValues sections are skipped if not fetchable.
- **Aqua** piracy checks in CSV's `quality.jl`: the forks' conformances for Base's families are declared by the trait's owner (the Tables fork), so they are no piracy under rule 3. Keep Aqua green.

### 1.4 Deferred, with reasons

- `Tables.Scan` pushdown (Tables 1.14 `src/scan.jl`, CSV `src/scan.jl`): new, orthogonal, no interactive cost measured yet.
- `CSV.Rows`, `CSV.Chunks`, `CSV.lazy`: row-wise and lazy paths; the session uses `CSV.read`/`CSV.File`. They stay plain and must keep passing.
- DataFrames metadata, reshape (`stack`/`unstack`), `flatten`, `allcombinations`: plain; not on the interactive path of §4.
- A trimmed binary (`aot-under-facts.md`), strict mode, Revise edits: later demonstrator rows.
- A `TableSink` trait: sinks are types in the Tables.jl API (`CSV.read(src, DataFrame)`), and traits bound values. The sink stays `DataFrame(t::TableSource)`, a bounded constructor (§2.3).

## 2. The traits

Rules observed: concreteness is opt-in per trait (decision 1); overrides after a conformance are refused, so every conformance declares its operations in its `@implement` block or before it (decision 4); no hidden type parameters (`DataFrame` stays non-parametric, as upstream); fixes in TraitWorld or Julia over workarounds.

### 2.1 `Column{T}` (Tables fork, `src/ColumnCore.jl`)

What DataFrames reads from a column, found by reading the hot paths (§3): length, a cell, a cell write, a fresh column of the same kind, a selection of rows, the vector itself for the API. `T = eltype(Self)`; a column with missing values has `T = Union{Missing, X}`, a concrete key (`Vector{Union{Missing, Float64}}`).

```julia
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    setcell!(c::Column{T}, i::Int, x::T)::Nothing
    emptylike(c::Column, n::Int)::Self          # a fresh column of the same kind, n rows (upstream: similar)
    take(c::Column, idx::Vector{Int})::Self     # rows idx, a new column (upstream: col[idx])
    parent(c::Column)::AbstractVector           # the stored vector, for the API (df.a === the vector)
end
@implement Column A where {A <: Vector} begin … end                      # keys per element type
@implement Column A where {A <: SubArray{T, 1, Vector{T}} where T} begin … end   # views, for SubDataFrame and group slices
```

- **No `@concrete_only`.** `Vector{Any}` columns are legitimate table data (the review of decisions 1 and 4, (c)); such a column gets one worker with run-time sites.
- **`parent` is the API's way back** to the user's vector. `df[!, i]` (`dataframe.jl:550`) becomes `parent(_columns(df)[i])`: one dispatch on the `Dynamic`, returning the stored vector, so `df.a[3] = 1.0` aliases as today. The implementation for `Vector` is `parent(c) = c`; what an operation returns is an ordinary value, so this respects rule 2. **Decision for the user (D-a):** this operation, or a TraitWorld primitive that returns the object a `Dynamic` keeps (open-issues §2.16, "a checked downcast"). The plan proceeds with the operation; M3 is where it is tested.
- **`RefColumn{T, R} <: Column{T}`** for pooled and categorical columns: `refs(c)::Vector{R}`, `pool(c)::Vector{T}`, so that groupby and join take the fast path upstream takes through `DataAPI.refpool`/`refarray` (`groupeddataframe/utils.jl:136`, `:283`; `join/core.jl:123–160`). `PooledVector` conforms in `TablesPooledArraysExt`; `CategoricalVector` in `TablesCategoricalArraysExt` (the trait owner's extensions, rule 3).

### 2.2 `TableSource` (Tables fork)

What a consumer needs from a table: names, a column as a `Dynamic{Column}`, the row count. It replaces the duck-typed `istable/columns/getcolumn/columnnames/schema` for the forks' own types; the duck interface stays for everything else, reached through a conversion.

```julia
@trait TableSource begin
    columnnames(t::TableSource)::Vector{Symbol}
    column(t::TableSource, i::Int)::Column       # a Dynamic{Column}: one dispatch, then workers per key
    nrows(t::TableSource)::Int
end
@implement TableSource CSV.File …                      # in the CSV fork (the type's owner)
@implement TableSource DataFrame …                     # in the DataFrames fork
@implement TableSource NT where {NT <: NamedTuple{names, <:Tuple{Vararg{AbstractVector}}} where names} …   # Tables' ColumnTable
```

Any other Tables.jl table is converted once by plain code, `Tables.columns(x)` and `getcolumn` per name (upstream's own path, `other/tables.jl:37–40`), into a `Vector{Dynamic{Column}}`: the "types that only convert" pattern (`4-details.md`). No `Tables.Schema{names, types}` type is instantiated on this path.

### 2.3 Sinks

`DataFrame(t::TableSource; copycols)` is a bounded constructor: it reads `column(t, i)` for each `i` and keeps the `Dynamic{Column}` (copying through `copy` on the parent when `copycols`). `CSV.read(src, DataFrame)` calls `DataFrame(CSV.File(src))` with `copycols = false`, as `Tables.CopiedColumns` does today (`CSV.jl` `read` doc; `other/tables.jl:44–45`). No `Vector{AbstractVector}` of abstract columns is built between the reader and the frame.

### 2.4 `CSVColumn{T} <: Column` (CSV fork, `src/ColumnParsers.jl`)

The column types a reader produces, as in TraitCSV (decision, session 27), on CSV 1.1.0's byte-level parsing: a cell is `(buf, pos, len, opts)`, parsed by `Parsers`.

```julia
@trait CSVColumn{T} <: Column begin
    @concrete_only                                   # the parse loop is the hot path
    T = eltype(Self)
    parsecell!(c::CSVColumn, i::Int, buf::Vector{UInt8}, pos::Int, len::Int, opts::ValueOpts)::Bool   # false: does not fit
    setmissing!(c::CSVColumn, i::Int)::Nothing
    emptycolumn(c::CSVColumn, n::Int)::Self
end
@implement CSVColumn Vector{Int64} begin parsecell!(c, i, buf, pos, len, o) = … Parsers.parseint … end
# likewise Vector{Float64}, Vector{Bool}, Vector{Date}, Vector{DateTime}, Vector{Time}, Vector{String} (DataString payloads), each with its Union{Missing, _} form
```

- **Type detection stays plain** (`core.jl:2440` `detecttype`, `:2410` `_promotemapped`): it works on bytes and returns a `Type`. The detected type selects a conformance through a registry `emptycolumn(::Type{T}, n)` filled by each `@implement` (as `defaulttypes()` in TraitCSV), so `parsecolchunk!` (`core.jl:2778`) becomes a worker per key instead of native code compiled per `T` at run time (`core.jl:3344` `allocatecolumn(::Type{T}, …) = TypedColumn{T}(n)`, a type as a value).
- **Package extensions become conformances.** `CSVInlineStringsExt` today adds methods to CSV's internal functions `_stringsink`, `_settledstringtype`, `_materializecolumn`, `_rowstringtype`, `_lazyeltype`, `_rowstring`, `_levelvector` (`ext/CSVInlineStringsExt.jl:27–28, 73–75, 77–100, 110–111, 118–127`); loading InlineStrings, which DataFrames does (`src/DataFrames.jl:29`), invalidates CSV's read path for files without a string column (`TraitReport/README.md` row 3: 0.19 s alone, 2.46–2.53 s with DataFrames). In the fork the extension declares `@implement CSVColumn Vector{String15}` (and the other widths), a method of the conformance registry, which invalidates nothing. `stringtype = InlineString` picks the width from the longest value as today (`ext:71–75`) and then runs the worker for that key.
- **Pooled columns:** `PooledColumn` (`core.jl:4456`) stays plain inside the reader; the result conforms to `RefColumn` through `TablesPooledArraysExt`.
- The `Rows`, `Chunks` and `lazy` paths keep their plain code.

### 2.5 Which upstream functions become bounded workers

Compiled per key (the column's type), kept in the fork's image for the keys its `@workload` covers, in a conformer's image or a view cache otherwise:

| Upstream | Today | In the fork |
|---|---|---|
| `describe`: `get_stats(@nospecialize(col), stats)` (`abstractdataframe.jl:786`) | run-time dispatch into Base's `quantile!`, `mean`, `std` compiled natively per column type | `colstats(c::Column, stats)::Dict{Symbol,Any}`, a worker per key |
| `show`: `ourstrwidth`/`ourshow` per cell (`show.jl:10, :35`), then `pretty_table(io, df; …)` (`show.jl:257–275`) | PrettyTables reads `df` through `Tables.getcolumn` at abstract types; formatters at `Any` | `cellstrings(c::Column, rows)::Vector{String}` per key; `pretty_table` receives a `Matrix{String}` and the header. PrettyTables' own code then compiles once, not per frame |
| `sortperm`: `DFPerm{O, T <: Tuple{Vararg{AbstractVector}}}` (`sort.jl:106–110`) | compiled per tuple of column types | one column: `sortperm_col(c::Column, ord)`; several: lexicographic refinement, a worker per key per level |
| `groupby`: `row_group_slots!(ntuple(i -> sdf[!, i], …), Val(false), …)` (`groupeddataframe.jl:244–247`, `utils.jl:192–260`) | compiled per tuple of column types; `hashrows_col!` per column (`utils.jl:3–57`) | `hashcol!(h, c::Column)` per key; `isequal_row` as a dynamic cell comparison per column; `RefColumn` fast path per key |
| `combine` fast aggregates: `check_aggregate` → `Reduce`/`Aggregate` → `groupreduce!` (`fastaggregates.jl:1–80, :178`) | per column type and op, natively | `groupreduce(c::Column, groups, op)` per key, op a type the module dispatches on (Base's functions are compiled calls) |
| `combine`/`select` with user functions: `_transformation_helper` → `fun(cols...)` (`selection.jl:588–606`), `do_call` on views (`callprocessing.jl:86–148`) | the function called at run time; `ByRow` broadcasts compile per closure | a `Callable` in `DynamicCall` mode: `apply(f::Callable{Tuple{Vector{T}}, S}, c::Column)`, `S` open, inferred at the boundary (`4-details.md`, "Function arguments"); `ByRow`: `Callable{Tuple{T1, …}, S}` called per cell through one pointer (4 ns), one worker per signature, none per closure |
| `innerjoin`: `_innerjoin_unsorted(left, right::AbstractArray{T})` (`join/core.jl:278`), `preprocess_columns` (`:123`) | per on-column type | `joinindices(l::Column, r::Column)` per key pair; `RefColumn` path |
| `subset`/`filter`: `subset.jl` | per column type | `mask(c::Column, f::Callable{Tuple{T}, Bool})` per key |
| `df[rows, :]`, `view`, `push!`, `insertcols!` | `col[idx]` per column type | `take(c, idx)` and `setcell!` per key; `insertcols!` stores a `Dynamic{Column}` |
| `CSV.write`: `@generated _preparewritecolumns(cols::Tuple, …)` (`write.jl:911–927`) | generated straight-line code per tuple of column types | `rendercells(c::Column, lo, hi, opts)::Vector{String}`-style workers per key feed the plain row emitter; the `Vector{AbstractVector}` fallback (`write.jl:929`) is the model |

**Functions from above.** User closures never become keys. The `=>` mini-language stays plain (it is already `@nospecialize`d: `selection.jl:225–262, :340–504`, `Ref{Any}` barriers at `:785`). At the point where upstream calls `fun(...)`, the fork calls a bounded worker with `dynamic_fn(Sig, S, fun)` (as TraitDifferentialEquations does, `src/TraitDifferentialEquations.jl:39, :59`). The result's element type follows upstream's widening rules in plain code after the worker returns.

**Where `Dynamic{Column}` lives:** `DataFrame.columns`, `GroupedDataFrame.parent` (unchanged type), the `Vector{Dynamic{Column}}` built by a conversion, `TableSource.column` results. A `SubDataFrame` conforms to `TableSource` by its own methods (its columns are `SubArray` views, keys of the `SubArray` family).

### 2.6 What this leaves as run-time sites

Operations on a `Dynamic{Column}` at the ordinary layer: one dispatch each (20–80 ns), into policy-compiled workers kept in images (the point of the storage decision: dispatch into protected code, not no dispatch). Index bookkeeping, keyword sorters and printing at `Any` stay run-time sites as today.

## 3. Hot spots of interactivity in upstream, with evidence

Each is a place where upstream compiles per schema or per column type at run time, or loses compiled code to loads. Which the fork removes is stated.

1. **Package extensions on internal functions** (CSV): `ext/CSVInlineStringsExt.jl` adds methods to `_stringsink`, `_settledstringtype`, `_materializecolumn`, `_lazyeltype`, `_rowstring`, `_levelvector` (lines above); `_finishstrings` calls `_materializecolumn(S, c, …)` with `S` a type value (`api.jl:1327–1353`). Measured: `CSV.File` 0.19 s alone, 2.46–2.53 s with DataFrames loaded in either order (`TraitReport/README.md` row 3); a `String15` column 3.9–5.0 s in every session (row 11, upper bound: includes `describe`). **Removed:** conformances replace the extension's methods; the reader's facts at `Vector{Float64}` have no stakeholder in InlineStrings.
2. **Columns typed as values, dispatched at run time into native code** (CSV): `allocatecolumn(::Type{T}, n, …) = TypedColumn{T}(n)` (`core.jl:3344`), `parsecolchunk!` per `T` (`core.jl:2778, :2830`), `_parse` and `_file` under `Base.@nospecializeinfer` (`core.jl:3749`, `api.jl:1197`). CSV's own workload (`src/CSV.jl:160–226`) covers the built-in types, so a first read is fast until a load invalidates that native code (item 1), or a type outside the workload appears. **Removed for the parse loop** (workers per key, protected); the index and detection stay plain and are workload-covered upstream code.
3. **`Vector{AbstractVector}` storage** (DataFrames): `dataframe.jl:178–181`; every column read is `_columns(df)[i]::AbstractVector` (`:441, :550`) followed by a function barrier into native code compiled per column type at run time. This is the shape PlainTables measured: 17 of 49 methods lost to nine loads, 16 recompiled (`TraitReport/README.md`, "Form (t)"). **Removed** by `Vector{Dynamic{Column}}` for every function ported in §2.5; the rest keeps the barrier shape over `parent(c)`.
4. **Per-tuple-of-column-types specializations** (DataFrames): `row_group_slots!(cols::Tuple{Vararg{AbstractVector}}, …)` (`groupeddataframe/utils.jl:192, :211, :283`), `DFPerm{O, T <: Tuple}` (`sort.jl:106`), `do_call(f, …, incols::NTuple{N, AbstractVector}, i)` (`callprocessing.jl:86–148`), `_innerjoin_unsorted(left, right::AbstractArray{T})` (`join/core.jl:278`). Every new combination of grouping, sorting or joining columns compiles. **Replaced** by per-column workers and dynamic cross-column comparison; cost: one dispatch per cell comparison across columns in multi-column groupby, to be measured (R3).
5. **Per-schema types** (Tables): `Schema{names, types}` is a type per schema (`Tables.jl:466–493`); `columntable` is `@generated` per schema (`namedtuples.jl:161–178`); `eachcolumn`/`eachcolumns` unroll per schema (`utils.jl:60–140`); `buildcolumns`/`allocatecolumns` per schema (`fallbacks.jl:121–150`). DataFrames reaches them in `Tables.rowtable`, `namedtupleiterator` (`other/tables.jl:6–8`), in `select_transform!` for table-valued results (`selection.jl:829` `Tables.columntable(res)`), and `Tables.schema(df)` builds the type (`other/tables.jl:24`). CSV's writer is `@generated` per tuple of column types (`write.jl:911–927`). **Removed** on the `TableSource` path and in the ported writer; kept where plain Tables.jl interoperability is used.
6. **`@nospecialize` barriers as the cure** (DataFrames): 31 in `selection.jl`, 12 in `splitapplycombine.jl`, 7 in `insertion.jl` (`grep -c`); `get_stats(@nospecialize(col))` (`abstractdataframe.jl:786`). They bound compile time but every call behind them is a run-time site into native code, which loads invalidate (item 3). **Kept** where they guard the mini-language; **replaced** by bounded entries where they guard column code.
7. **`show` through PrettyTables** (`show.jl:257–275`, PrettyTables 3.5.0): the frame is printed through `Tables.getcolumn` at abstract types with formatters and highlighters at `Any`; DataFrames' workload covers `show(IOBuffer(), df)` for its six column types (`other/precompile.jl`). A new column type recompiles part of it. **Reduced** by handing PrettyTables a `Matrix{String}` (§2.5); PrettyTables' own first-call cost remains and is measured in M0.
8. **The policy's compiler code after REPL loads** (TraitWorld, not upstream): with REPL loaded first, a new key's first call costs 5.9 s without the system image, 0.1–0.2 s with it (`writeup/open-issues.md` §1.3; `experiments/sysimage/README.md`). The claim of §0 therefore names the image. The REPL rows are run with and without it.

## 4. The interactive workload

### 4.1 Data

Generated by `scripts/gendata.jl` (deterministic seed), written once:
- `people.csv`: 10 000 rows; `id::Int`, `name::String` (3–12 chars), `city::String` (12 distinct values), `age::Int` with 5% missing, `income::Float64` with 2% missing, `joined::Date`, `active::Bool`.
- `orders.csv`: 50 000 rows; `order_id::Int`, `id::Int` (foreign key), `amount::Float64`, `item::String` (40 distinct), `ts::DateTime`.
- `sensors.csv`: a second schema with the same column types, 10 000 rows; `t::Float64`, `s1..s6::Float64` with missing, `tag::String`.
- `big.csv`: 10⁶ rows × 4 columns (`Int`, `Float64`, `String`, `Float64` with missing) for the throughput row only.

### 4.2 The session script

One file `scripts/session.jl`, read line by line by a real REPL (`julia -i --banner=no < scripts/session.jl`), each step followed by a timestamp line (`println("T step_name ", time_ns())`), so no timing code is compiled inside the measured step. The same steps in `scripts/session.py` for pandas (`time.perf_counter()` marks). Steps:

| # | Step | Julia (forks and upstream alike) | pandas |
|---|---|---|---|
| 0 | imports | `using CSV, DataFrames, Statistics` | `import pandas as pd, numpy as np` |
| 1 | read | `df = CSV.read("people.csv", DataFrame)` | `pd.read_csv` |
| 2 | show | `show(stdout, df)` (the REPL's `display`) | `print(df)` |
| 3 | describe | `describe(df)` | `df.describe(include="all")` |
| 4 | select, filter | `sub = subset(select(df, :id, :city, :income), :income => ByRow(x -> !ismissing(x) && x > 5e4))` | boolean indexing |
| 5 | sort | `sort(df, [:city, :income], rev = [false, true])` | `sort_values` |
| 6 | groupby, combine | `combine(groupby(df, :city), :income => mean ∘ skipmissing => :mean_income, nrow)` | `groupby().agg()` |
| 7 | user function | `transform(df, [:age, :income] => ByRow((a, i) -> coalesce(i, 0.0) / max(coalesce(a, 1), 1)) => :ratio)` | `apply(axis=1)` or vectorized |
| 8 | join | `innerjoin(df, CSV.read("orders.csv", DataFrame), on = :id)` | `merge` |
| 9 | add a column | `df.income_k = df.income ./ 1000` | assignment |
| 10 | write | `CSV.write(tmp, df)` | `to_csv` |
| 11 | second schema | steps 1–3, 5 and 6 on `sensors.csv` | same |
| 12 | new package, new column type | `using InlineStrings` (or `PooledArrays`); `CSV.read("people.csv", DataFrame; stringtype = String15)` (`pool = true`); steps 2, 3, 6 again | `astype("category")`; repeat |

Step 12 is the new-conformance case: `String15` columns enter through `CSVInlineStringsExt`'s conformance; the DataFrames workers for the key `Vector{String15}` exist in no image (InlineStrings is a dependency of DataFrames, so the DataFrames fork's `@workload` can cover `String15`; the plan measures both with and without that line to show the first-session cost honestly, as the review's S2/S3 ask).

### 4.3 Configurations and metrics

Configurations, each a fresh process:
1. stock Julia, upstream (today's user);
2. patched, upstream (the patch alone: the control);
3. patched, forks;
4. patched with the TraitWorld system image, forks (the claim of §0);
5. stock, forks (reported as the price of missing piece 5);
6. pandas.

Each in two drivers: the REPL driver above (primary), and `--startup-file=no` script mode (for comparison with the earlier rows). Each with loads: none; `using REPL` only (implied by the REPL driver); the TraitReport sets (`OffsetArrays StatsBase Unitful`; `IntervalArithmetic Distributions Interpolations StaticArrays`; all nine with CairoMakie) loaded before `using CSV, DataFrames` and, in a second run, after step 10 and before step 11.

Metrics:
- wall time per step from the marks; imports and process start to exit separately;
- ≥ 5 runs per cell, reporting min and median; the harness logs the 1-minute load average and discards a run when it exceeds a stated threshold (the review's S7: noise about 30%);
- compiled code lost per load, per fork and per owner (native or policy), by `scripts/invalidated.jl` as in `TraitReport/scripts/invalidated.jl`;
- image sizes and precompile time of the forks against upstream, `using` time, memory at exit;
- the throughput row: `big.csv` read, groupby, write, second call, against pandas (within 2× is the expectation; CSV 1.1.0's kernel stays plain, so no regression is expected on the read).

Harness: `scripts/measure_session.sh`, modelled on `TraitReport/scripts/measure.sh` (one Julia job under `flock`, `nice -n 19`, raw timestamps subtracted outside the process; Python under the same `flock`/`nice`, without the warm-up asymmetry the review noted, M1).

## 5. Milestones

Each is one sitting for one agent, with a verification run; measurement milestones go first so the target is known. Every milestone ends with the test suites that its changes touch passing on the patched build, and a line in the demonstrator's README.

- **M0. Baseline and harness.** `gendata.jl`, `session.jl`, `session.py`, `measure_session.sh`, `invalidated.jl`; environments `env_upstream` (registry versions) and `env_py`. Measure configurations 1, 2 and 6 for all steps, five runs, with and without the TraitReport load sets. *Exit:* the baseline table in `forks/README.md` (the demonstrator's README); the per-step numbers of §0 confirmed or corrected for pandas.
- **M1. Forks.** Clone the three upstreams at the depot versions into `forks/`; `env_forks` with `[sources]`; run the three upstream test suites unchanged on the patched build (and once on stock), one at a time, niced; resolve or record the missing test dependencies (§1.3); check network access for `Pkg`. *Exit:* three green (or documented) test logs; a list of test lines that touch internals (`_columns`, `Vector{AbstractVector}`) to be adapted in M3.
- **M2. Tables fork: the traits.** `ColumnCore` with `Column{T}` (operations of §2.1), `RefColumn`, `TableSource`; conformances for `Vector`, `SubArray`, `NamedTuple` column tables; `TablesPooledArraysExt`; definition checking passes; micro-benchmark `cell`/`nrows` in a loop against plain (expect 1.00–1.03×, `4-details.md` "Performance"). Tables' tests unchanged. *Exit:* tests; benchmark numbers; the `parent` decision (D-a) tested in isolation.
- **M3. DataFrames storage.** `columns::Vector{Dynamic{Column}}`; `_columns`, `getindex(df, !, i)`, `setindex!(df, v, !, i)` (`dataframe.jl:441, :550, :558, :676`), the inner constructor (`:193–237`) and `insertcols!` adapted; `DataFrame(t::TableSource)`; `TableSource` conformances for `DataFrame`, `SubDataFrame`. Everything else still reads `parent(c)`. Full DataFrames suite. *Exit:* suite green; `using DataFrames` time and image size against upstream; the session steps measured (expected: no gain yet, the control that storage alone is not the win).
- **M4. Workers, batch 1.** `describe`, `show` cells, `sortperm`, `take` for `df[rows, cols]`, `push!`. *Exit:* suite green; steps 2, 3, 5 at the target on configuration 4 for image-held types; code lost under loads = 0 for these workers.
- **M5. CSV fork.** `ColumnParsers` with `CSVColumn` conformances for the built-in cell types on `Parsers`; `parsecolchunk!` as a worker; `CSVInlineStringsExt` as conformances; `CSV.File` conforms to `TableSource`; `DataFrame(::CSV.File)` without the abstract-vector detour. CSV suite (kernel.jl alone, niced). *Exit:* suite green; step 1 at the target with DataFrames and InlineStrings loaded (the row 3 analogue: `CSV.File` time equal with and without DataFrames); row 11 analogue for `String15` with the cost split between the first session and later ones.
- **M6. Workers, batch 2.** `groupby` (hash and `RefColumn` paths), `combine` fast aggregates, user functions as `Callable`s (column-wise and `ByRow`), `innerjoin`/`leftjoin` key matching, `subset`. *Exit:* suite green (`grouping.jl`, `join.jl`, `select.jl`, `subset.jl`); steps 4, 6, 7, 8 at the target; multi-column groupby cost against upstream on `big.csv` (R3).
- **M7. Writer and the remaining paths.** `CSV.write` cell rendering per key over the `Vector{AbstractVector}` emitter model; `df.x = v` and broadcasting paths checked; `SubDataFrame`/`DataFrameRow` printing. *Exit:* CSV `write.jl` tests green; steps 9, 10 at the target.
- **M8. Workloads and images.** `@workload` blocks in the three forks covering the session's keys (`Int64`, `Float64`, `Bool`, `String`, `Date`, `DateTime`, each with and without `Missing`; `String15` in the DataFrames workload, since InlineStrings is its dependency; `PooledVector` in the Tables extension's). Precompile time, image sizes, `using` time, patched and stock. *Exit:* a table; every session step for image-held types needs no new worker (checked with `invalidated.jl`'s "compiled by the work" count).
- **M9. The measurement.** The full matrix of §4.3 (configurations 1–6, REPL and script drivers, load sets, five runs), the lost-code counts, step 12 with and without the `String15` workload line. *Exit:* the README tables; the verdict against §0, step by step.
- **M10. New types beyond the images.** `TablesCategoricalArraysExt` if CategoricalArrays is fetchable; a user-defined element type declared at the prompt (`struct Celsius; v::Float64; end`, a `Vector{Celsius}` column); a `@implement Column` for a user's column type at the prompt. First-session and later-session costs; the view cache's build time and size reported (review S2). *Exit:* a table; open issues filed for what is slow.
- **M11. Documents.** `forks/README.md` as the demonstrator's README (scope by the tree, baselines first, then upstream and pandas; every number labelled stock/patched/image and script/REPL); `writeup/decisions.md` (the forks as the realization of the session-26 decision; D-a), `writeup/open-issues.md`, `writeup/README.md`, the root `README.md` table; TraitReport form (t) re-pointed or labelled history. *Exit:* the documents agree with the tree and with each other (the review's S6).
- **M12 (optional).** The throughput row on `big.csv` beyond the session; a Revise row (edit `colstats`, time the next call); the trimmed binary waits for the deferred AOT work.

Order rationale: M0–M1 fix the target and the bar before any trait is written; M2–M3 are the de-risking steps (the API round trip through `Dynamic`, the test suites on changed storage); M4 shows the first per-key gains on the cheapest functions; M5 removes the largest single upstream cost (item 1 of §3); M6–M7 complete the session; M8–M9 produce the numbers the claim is judged by.

## 6. Risks, and what would falsify the claim

- **R1. The API round trip through `Dynamic{Column}`** (D-a). `df.a` must return the stored vector itself; `parent` as an operation does that for `Vector` conformances. For conformers with a trait object held immutably (not the case for `Vector`, which is mutable and read through, `TraitWorld/src/core.jl:82–96`) the semantics would differ. If M3 finds a hole, the fallback is dual storage (`columns::Vector{AbstractVector}` kept, plus the `Dynamic` built at the entry per call), which keeps the API and loses nothing of the per-key workers; it costs one entry translation per call instead of one dispatch.
- **R2. Threads.** DataFrames spawns tasks in `groupby`/`combine` (`@spawn_for_chunks`, `utils.jl:8, :36`), in the constructor at ≥ 100 000 rows (`dataframe.jl:223–225`) and with `threads = true` in `combine`. Assumption A4 (no method definition on another thread while trait code compiles, `4-details.md` "Identical or error") is untested under worker tasks that compile workers concurrently. Mitigation: the trait modules compile their workers at the first call from the calling task; M6 runs `grouping.jl` and `multithreading.jl` at `-t 4` and watches for hangs or errors; if any, the ported paths run their inner loop under `threads = false` until Julia piece 11.
- **R3. Multi-column groupby and join.** Upstream specializes per tuple of column types; the fork compares cells across columns through dynamic operations (20–80 ns each). On `big.csv` with two grouping columns this may be 2–5× slower than upstream in steady state. Mitigation: a worker per pair of keys for two columns (compiled per pair of keys, still not per schema); the `RefColumn` path for pooled strings. Measured in M6; reported either way.
- **R4. Views as keys.** `SubArray{T, 1, Vector{T}, Tuple{Vector{Int}}, false}` and the `UnitRange` form are keys per `T`; the workloads cover them. A proliferation beyond a few index types would show as compile time in M9.
- **R5. User functions and result types.** Upstream widens result element types by `promote_type` on the fly; a `Callable` with an open result `S` is inferred once at the boundary and asserted per call ("identical or error", A3). `select.jl`'s tests exercise closures that return `missing` on some rows or mixed types. Mitigation: the worker returns the per-cell results into a widening collector written in plain code (upstream's own), so only the iteration is per key. If the collector cannot be separated for `ByRow`, `ByRow` stays plain (compiled per closure, as plain Julia and as today); the session's one `ByRow` step then costs upstream's compile time, which pandas' `apply` also pays in its own way. This would narrow the claim for step 7, not falsify it.
- **R6. Definition checking and the policy's compile cost on large modules.** The trait modules are kept small (the kernels of §2.5, a few hundred lines each); the rest is plain. Known: trait libraries build 10–15% longer (session 27); uncached policy compilation of a CSV/DataFrames workload costs 0.60 s against 0.45 s natively (`3-wrapping.md`, "What this costs"). If a fork's precompile time exceeds 2× upstream's, the workload is trimmed and the number reported.
- **R7. Image sizes.** Patched images carry 30–60% more native code (session 27, rows 13/10). DataFrames' image is large already; M8 reports sizes and `using` time; the plausible import target is 1.0 s, not pandas' 0.4 s.
- **R8. Prototype gaps** (`open-issues.md` §3): results through an opened `Dynamic` are not inferred, so library code asserts them (item 7); `Vector{<:Column}` arguments as a whole (§2.11) are not used, the plan passes `Dynamic` vectors; keyword and `Callable` workers are checked per signature, not at archetypes; forwarding for whole families is not prototyped, so conformances are by own methods (`Vector`, `SubArray`) or in extensions. Any TraitWorld fix made for the forks is recorded in the session note as a principled fix.
- **R9. Late overrides refused** (decision 4). A package that defines a `Column` operation for its own type after the Tables fork's family conformance covers it (a `Vector` subtype is not a `Vector`, so this is unlikely for `Vector`; it can happen for `SubArray` wrappers) would be refused at load. The forks define every operation inside `@implement` blocks; M10's user-type case tests the prompt path.
- **R10. Test dependencies and offline mode.** CategoricalArrays, Combinatorics, DataValues, ShiftedArrays, DataDecimals, QueryOperators are not in the depot. If the proxy denies the package server, their sections are skipped and listed; CategoricalArrays' conformance (M10) is then replaced by PooledArrays' only.
- **R11. The REPL case without the image.** 5.9 s for the first new key (§3, item 8) is the configuration a user has today with TraitWorld as a package. The claim names the image; configuration 3 shows the gap and is reported, and the cleaner form ("the policy in Julia's Compiler") stays a Julia work item.
- **R12. Noise.** About 30% between sessions on this machine; the harness logs load and discards by rule; differences under 20% are not claimed.

**Falsification, restated.** The claim fails if, on configuration 4 with image-held column types, any step's first call exceeds 1 s or the session exceeds 3 s (imports excluded); if any policy-compiled CodeInstance of the forks is lost to the load matrix; or if configuration 2 (patched, upstream) is within 1.5× of configuration 4 on the session total. It is narrowed, not falsified, if step 7 (`ByRow` with a closure) or step 12's first session exceeds the target while the rest holds; the README then says so.

## 7. Resource limits

- One Julia job at a time, under `flock` on the shared lock, `nice -n 19`; `JULIA_NUM_PRECOMPILE_TASKS=4`; `JULIA_PKG_OFFLINE=true` unless M1 establishes network access for the missing test dependencies.
- The upstream test suites run one at a time and alone (DataFrames' suite and CSV's `kernel.jl` are long); never in parallel with a precompilation.
- The system image is rebuilt only when TraitWorld changes (`experiments/sysimage/build.sh`, about 2 minutes, alone, under the memory watchdog); environments are precompiled once per build and image before measuring.
- No juliac builds in this plan.

## 8. Decisions for the user, collected

- **D-a.** The way back from a `Dynamic{Column}` to the stored vector: a `parent` operation of `Column` (the plan's default), or a TraitWorld primitive returning the kept object (open-issues §2.16).
- **D-b.** Fork names and UUIDs kept as upstream's (the plan's default), so the upstream test suites and dependents run unchanged; or `Trait`-prefixed names with a module alias in the test harness.
- **D-c.** `ByRow` with user closures: a `Callable` per signature (the plan's default, R5), or plain per-closure compilation as today.
- **D-d.** Whether the DataFrames fork's workload may cover `String15` (InlineStrings is its dependency, so this is a workload in its own package, not in another's), with the first-session cost reported beside it.
