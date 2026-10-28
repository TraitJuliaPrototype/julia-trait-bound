# DataFrames, CSV and Tables in the trait world: a design memo (W-79)

Status: **proposal, revision 1** (2026-10-28, mine; W-79), for a fresh-eye review before the forks resume (W-14). Not normative. The user (2026-10-28): "DataFrames was paused when foundational pieces of the software stack were missing. Unpause it please, and schedule work on a design memo using the previous learnings."

It applies [W-60's memo](2026-10-27-lean-core-old-apis.md) (four layers, the waist, loading on demand, the cache's place) to the third ecosystem, with what [the forks](../../forks/README.md) (sessions 27–29), TraitReport with TraitTables and TraitCSV, and the experiments since have taught. It does not change the references.

## 0. Summary

- **The open sets are columns, tables and cell types.** Every other set in the three packages is closed (one package holds every member) and stays types. Traits name them: `Column{T}` (what every column provides), its capability subtraits `MutableColumn{T}` and `PooledColumn{T, R}`, `TableSource` (a table as a consumer reads it), and CSV's `CellParser{T}` (how a cell type, a string width included, is read from bytes).
- **The forks' lesson that shapes the rest:** a trait states only what *every* member does. The forks' `Column{T}` carried the reference-pool operations (`nlevels`, `levelcode`, `level`), which only pooled columns have; the member check of 2026-10-27 (T-77) correctly refuses `Vector{Int64}` there (E-163), and the forked CSV no longer precompiles. Capabilities go to subtraits with the library's fallback in plain code (porting 0.2, "capabilities per type"), as closed issue 68 settled for colour names.
- **Four layers,** as for SciML and Makie:
  1. a **trait core** (`Tables.ColumnCore` with the traits; DataFrames' and CSV's kernels as bounded functions over them);
  2. **implementation packages**: column types (PooledArrays, CategoricalArrays, InlineStrings, Arrow, user types) and sources (CSV.File, Arrow tables, a database result) implementing the core's traits, each for its own types or in an extension of the trait's owner;
  3. a **compatibility layer**: Tables.jl's duck-typed interface (`istable`, `columns`, `getcolumn`, `schema`), which every other table package uses today, kept as plain code and converted once at the entry;
  4. the **user API**: DataFrames' and CSV's names and calls, unchanged: the `=>` mini-language, `select`, `transform`, `combine`, `groupby`, `CSV.read`, `df.a`, indexing, `show`.
- **Users and package authors keep their API.** A package that implements Tables.jl's interface keeps working through the compatibility layer; one that wants its columns compiled per key implements `Column` (one line for an `AbstractVector` subtype with the usual methods).
- **The control comes first.** The facts mode alone already takes upstream CSV and DataFrames from 561 to 2 lost CodeInstances under nine loads and their first work from 3.3 to 0.5 s (evidence §1, `all`). Every claim for traits is measured against upstream compiled by facts, which the forks' session of 2026-10-20 did not do (evidence §3: 1.35 s against upstream's 10.7 s in the default mode). That is the first experiment (D0).

## 1. What the libraries are for, and their open sets

| Package | What it is for | Open sets (other packages add members) | Closed sets (stay types) |
|---|---|---|---|
| Tables | the interface between table sources and sinks | table sources and sinks; column types | `Schema`, `Columns`, `Row` wrappers |
| DataFrames | an in-memory table with a mini-language for transformations | column types (element types and column kinds); user functions in `=>` pairs; table sources a frame is built from | `DataFrame`, `SubDataFrame`, `GroupedDataFrame`, `DataFrameRow`, the index, the mini-language's pair forms |
| CSV | read and write delimited text | cell types (built-in, InlineStrings' widths, a user's type with `Parsers`); sources (paths, `IO`, bytes); sinks (any Tables.jl sink) | the structural index, type detection, `Rows`, `Chunks`, the writer's row emitter |

**How other systems hold an open set of column types** (primary sources):
- **pandas:** `ExtensionDtype` and `ExtensionArray` ([Extending pandas](https://pandas.pydata.org/docs/development/extending.html)): a column type is any class implementing the array interface; pandas' kernels call its methods per column, and fall back to object arrays where it does not implement a capability.
- **Apache Arrow (Rust):** a column is `ArrayRef = Arc<dyn Array>` ([`arrow_array::Array`](https://docs.rs/arrow-array/latest/arrow_array/trait.Array.html)); compute kernels downcast once per column to a typed array (`as_primitive::<T>()`) and run a loop monomorphized for `T`.
- **Polars:** `Series` wraps `Arc<dyn SeriesTrait>`, and each typed column is a `ChunkedArray<T>` ([`polars_core::series::Series`](https://docs.rs/polars-core/latest/polars_core/series/struct.Series.html)); kernels dispatch on the data type once per column and run typed code over the chunks.

**The common shape:** one dynamic dispatch per column, typed code per element type inside, capabilities as optional methods with a slow general fallback. In the trait world: a `Dynamic{Column}` per stored column, a worker compiled per key, capability subtraits with plain fallbacks.

## 2. What the earlier work taught

From the forks ([`forks/README.md`](../../forks/README.md); porting B1):
1. **Kernels read through the operations,** never through `vector(c)` (the implementation review of 2026-10-18, P7: unwrapping validates a function barrier, not keys). Session 29 rebuilt them so; the suites passed (forks 8c6366a), the session's digests equal upstream's at 26 steps.
2. **Heavy library code runs over gathered cells:** `describe` gathers `cell`s into a `Vector{T}` and runs Statistics there, compiled per `T`, shared by every column kind.
3. **What a type does by itself is an operation:** `take(c, rows)` keeps a pooled column pooled.
4. **A type passed as a value becomes a value that stands for it:** `stringtype = String15` makes `S[]`, and the extension declares implementations only. CSV's InlineStrings extension, which added methods to seven internal functions, cost the reader 0.19 → 2.46–2.53 s whenever DataFrames loaded InlineStrings (TraitReport row 3); TraitCSV's extension, implementations only, discards none of the reader's code (evidence, "Shown").
5. **Capabilities belong in subtraits** (E-163 and the member check, T-77; closed issue 68): the forks' `Column{T}` with `nlevels`, `levelcode`, `level` does not hold for a `Vector{Int64}`.
6. **A type held as a `DataType`** (`allocatecolumn(T, …)`) is a run-time site; carry a value that stands for it (porting B1 item 10).
7. **Where code lives:** a key from one package and a function from another live in no image unless a glue extension compiles them (L-15); the forks' `CSVDataFramesExt` and `CSVDataFramesInlineStringsExt` were plain remedies. The facts-keyed cache (W-66) is the principled answer.
8. **Standard libraries are Julia's own owner:** SparseArrays' `vcat` wins inside CSV's `_parse` (`[0; v]`), so StatsBase's load recompiled the reader (0.34–0.42 s, porting B1 item 11). Avoid concatenation syntax on Base's types in hot paths.

From W-60's memo and its experiments (E-176, E-179–E-184):
9. **Four layers and the waist** (§1.1 there): the core reaches what it does not own only through declared operations; implementations by `@implement` for their own types; the compatibility layer ordinary code; a thin user API that normalizes at the entry.
10. **Normalize at the entry** (rule 5; E-184 at SciML's scale: 1.50 → 0.51 s; E-181 in TDE): here, column inputs to stored column kinds, keyword sets to typed option records, user functions to `Callable`s at the columns' cell types.
11. **Loading on demand** by stubs and `invokelatest` at user-facing entries (E-182): for heavy optional paths (Arrow, PrettyTables' HTML and LaTeX back ends, the statistics behind `describe`'s quantiles if lighter is wanted).
12. **The load follows the tree** (E-176, E-179): DataFrames' tree (PrettyTables, Crayons, SentinelArrays, InlineStrings, PooledArrays, InvertedIndices, Reexport, Compat, DataAPI, Missings, SortingAlgorithms) is a smaller lever than Makie's; measure first (D1).

From the facts work: the facts mode alone protects upstream code from unrelated loads (evidence §1); traits add what the facts rule cannot: protection from a package's own extensions on its internal functions (item 4), compiled code per key shared across schemas (sort, groupby, join per column type, not per tuple of column types), and code that does not depend on the user's schema.

## 3. The architecture

### 3.1 The trait core

In the Tables fork, the owner of the interface (`Tables.ColumnCore`, a trait module):

```julia
# a sketch, not run
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    take(c::Column, rows::Vector{Int})::Self          # a pooled column stays pooled
    emptylike(c::Column, n::Int)::Self                 # a fresh column of the same kind
    vector(c::Column)::AbstractVector                 # the API's way back: df.a === v; kernels never call it
end
@trait MutableColumn{T} <: Column begin
    setcell!(c::MutableColumn{T}, i::Int, x::T)::Nothing
end
@trait PooledColumn{T, R} <: Column begin             # the reference pool (DataAPI's refpool/refarray)
    refs(c::PooledColumn)::AbstractVector{R}
    pool(c::PooledColumn)::AbstractVector{T}
end
@trait TableSource begin
    tablenames(t::TableSource)::Vector{Symbol}
    tablecolumn(t::TableSource, i::Int)::Dynamic{Column}
    tablerows(t::TableSource)::Int
end
@implement (Column, MutableColumn) A where {A <: Vector}       # every Vector, by its own methods
@implement Column A where {A <: SubArray{<:Any, 1, <:Vector}}  # views, for SubDataFrame and group slices
```
- **`Column` holds what every column does.** Pooling and mutability are capabilities: subtraits, each with its fallback in the kernel's plain code (a hash of cells where there is no pool).
- **Whose extension:** `PooledColumn` for `PooledVector` is the trait owner's extension with PooledArrays as trigger (`TablesPooledArraysExt`), as the forks had; the same for CategoricalArrays. A package that owns its column type implements the traits itself.
- **Text:** needs no trait of its own in the core: a string column is a `Column{S}`, and CSV's string widths are `CellParser`s (§3.1, CSV).
- **Concreteness:** none declared. `Vector{Union{Missing, Int}}` is a concrete key (decision 18: a small union counts as concrete); `Vector{Any}` is a legitimate column with one worker of run-time sites.

In the DataFrames fork, `DataFrames.Kernels` (a trait module): bounded functions over `Column`, compiled per key, kept in the image for the workload's keys:
- `colstats(c::Column, stats)` (describe); `refine!(perm, c::Column, rev)` (sort, one column at a time); `groupcodes(c::Column)` with a `PooledColumn` method (groupby); `aggregate(c::Column, agg, gd)` (the fast aggregates); `innerrows(l::Column, r::Column, …)` (joins); `cellstrings(c::Column, rows)` (show); `fromsource(t::TableSource, copycols)` (the frame from a source);
- **user functions:** `apply(f::Callable{Tuple{Vector{T}}, S}, c::Column{T})` for column-wise functions and `byrow(f::Callable{Tuple{T1, T2}, S}, a::Column{T1}, b::Column{T2})` for `ByRow`, the `Callable` `Dynamic` by its default: one worker per cell-type signature, none per closure. A closure whose result type varies is widened by upstream's collector in plain code after the worker (the plan's R5).

In the CSV fork, `CSV.ColumnParsers` (a trait module): `CellParser{T}` with `parsecell!(c::Vector{T}, i, buf, pos, len, opts)::Bool`, implemented for the built-in cell types and, in extensions, for InlineStrings' widths; the parse loop `parsecells!(c::CellParser, …)` one bounded function. Type detection stays plain and returns a value that stands for the column type (`emptylike` of a registered prototype), not a `DataType`.

### 3.2 The compatibility layer: Tables.jl's duck interface

- **Kept, plain:** `istable`, `columns`, `rows`, `getcolumn`, `columnnames`, `schema`, `Tables.Schema{names, types}`, `columntable`, `rowtable`, dict and matrix tables, `Tables.Scan`. Every package that implements Tables.jl today keeps working.
- **One conversion at the entry:** a source that does not conform to `TableSource` is converted once, `Tables.columns(x)` and `getcolumn` per name, into a `Vector{Dynamic{Column}}` ([traits §4.10](../reference/traits.md#410-types-that-only-convert)); a column that does not conform to `Column` (an `AbstractVector` subtype without the methods `Column`'s family needs) is copied into a `Vector{T}`, as upstream's `copycols` does.
- **The per-schema types** (`Schema{names, types}`, `@generated columntable`) are reached only on this layer's paths, never from the core.

### 3.3 The user API, unchanged

- `DataFrame(...)`, `df.a`, `df[!, :a]`, `df[rows, cols]`, `select`, `transform`, `combine`, `groupby`, `subset`, `sort`, the joins, `describe`, `show`, `CSV.read`, `CSV.File`, `CSV.write`: names and behaviour as upstream's; the upstream test suites decide (the plan §1.3).
- **Storage:** `DataFrame.columns::Vector{Dynamic{Column}}` with `_columns(df)` an adapter that reads and writes through the kept values (porting B1 item 12); `df.a` returns `vector(c)`, the stored vector itself.
- **The mini-language stays plain** (`selection.jl`'s `@nospecialize` paths): it normalizes a request into column indices, a `Callable` at the columns' cell types and an output name, then calls the kernels.
- **`show`:** `cellstrings` per key fills a `Matrix{String}`; PrettyTables renders it once per IO type (porting B1 item 11).

### 3.4 What loads when

| When | What |
|---|---|
| `using DataFrames` | TraitWorld; Tables with `ColumnCore`; DataFrames with its kernels; PooledArrays and InlineStrings (dependencies today) with their implementations; PrettyTables (text back end) |
| `using CSV` | CSV with `ColumnParsers` and its built-in parsers; the InlineStrings parsers if InlineStrings is loaded |
| the first HTML or LaTeX `show` | PrettyTables' back end, through a loading stub (only if D1 shows it is worth it) |
| the user loads a package | its implementations: CategoricalArrays' `PooledColumn` (the Tables extension), Arrow's `TableSource` and columns, a user's column type |

### 3.5 Where the facts-keyed cache fits

The kernels' code for a key the images do not hold (a user's element type, a `Vector{Celsius}` column) is facts code at a library key: the store (W-66) keeps it across sessions and environments. Upstream's glue extensions with workloads (lesson 7) then become unnecessary; until the store exists, they stay as plain remedies, labelled.

## 4. Costs and risks

1. **Multi-column groupby and sort** compare cells across columns through `Dynamic` operations, one dispatch per column per comparison (the plan's R3). Upstream specializes per tuple of column types. Mitigation as in the forks: per-column integer codes combined in plain integer code (groupby), one column at a time from the last (sort); measure on 10⁶ rows (D3).
2. **Gathering cells** for `describe` and the aggregates copies each column once per call; upstream calls Statistics on the vector. Bounded by one pass; measure (D3).
3. **Threads:** DataFrames spawns tasks in `groupby` and `combine`. E-63 showed calls through split sites and `compiled_for` consistent while the main thread defines; workers compiled concurrently from several tasks are not tested at this scale. The suites at `-t 4` (`multithreading.jl`) decide.
4. **The member check at abstract declared arguments** (T-77) must hold for every `Vector{T}` the reader produces; the traits of §3.1 are written so that `Column` asks only what `Vector` has.
5. **The compatibility layer's conversion** copies a column that does not conform; a package whose columns are lazy (Arrow's memory-mapped columns) wants to conform instead: Arrow's extension of the Tables fork, or Arrow's own implementation.
6. **Names:** `nrows`, `cell`, `take`, `vector` clash with exported names in the ecosystem (`DataAPI.nrow`, `Base.take!`); operations are functions of `ColumnCore`, not exported (porting B1 item 7).

## 5. The smallest experiments, before the port

Each with a plain control: upstream compiled by facts (`all`) or upstream as it is.
- **D0, the control the forks lacked:** the forks' session (`forks/scripts/session.jl`) for upstream under `all` against upstream plain, on the current build. If upstream under `all` is within 1.5× of the forks' 2026-10-20 session, the traits' share is small and the port's claim narrows to schema independence and extensions (lesson 4). Minutes.
- **D1, the load:** `@time_imports` of `using CSV, DataFrames` (stock and patched), the tree's share, as E-179 for Makie. Minutes.
- **D2, the traits in isolation:** `ColumnCore` of §3.1 in the Tables fork, its implementations for `Vector`, `SubArray`, `PooledVector`; the member check passes for every `Vector{T}` the reader produces and refuses nothing upstream's tests use; Tables' suite green. Then the forked CSV precompiles again. An hour.
- **D3, the kernels' costs:** `refine!`, `groupcodes`, `colstats` and `aggregate` through `cell` on a `Dynamic{Column}`, against upstream on 10⁶ rows, single and two-column. **Would change the design:** a steady-state slowdown above 20% that per-pair workers cannot recover.
- **D4, schema independence:** a second and a third schema with the same column types: compiled code per key reused (no new worker), against upstream's per-tuple specializations; with loads before and after.

## 6. What it would change in the references

Nothing. It uses traits, subtraits, families, `Dynamic` storage, `Callable` at declared signatures, extensions by the trait's owner, and loading stubs, all as the references state them. Two Planned features would help and are not needed: forwarding for a whole family (T-7), and trait casts (§6.9) for asking a kept column for a capability.

## 7. Questions for the review

1. Is the split of `Column` into `Column`, `MutableColumn` and `PooledColumn` the principled one, or does any kernel need a capability as a bound where a plain fallback would serve?
2. Should `TableSource` keep `tablecolumn(t, i)::Dynamic{Column}`, or return a `Kept{Column}` whose attribute the caller decides?
3. Is the compatibility layer's one conversion at the entry enough for lazy sources (Arrow), or do they need `TableSource` from the start?
4. Is D0 the right first experiment, and is its criterion (1.5×) the right one?
