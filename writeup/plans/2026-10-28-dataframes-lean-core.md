# DataFrames, CSV and Tables in the trait world: a design memo (W-79)

Status: **adopted, revision 2** (2026-10-28, mine; W-79; the forks follow it: D2 done (E-211), D0 done (E-212), D1 done (E-213)), after [its fresh-eye review](../reviews/2026-10-28-dataframes-lean-core.md) (§8); a stored value's capabilities were open issue 82, after the user's note that the ports are to find the design's weak points; decided 2026-10-28 (option (a), [traits §6.5](../reference/traits.md#65-values-carry)): the port takes `PooledColumn` as a trait of its own, selected by dispatch, once W-81 is built. Not normative. The forks (W-14) follow it, starting with D2 (§5). The user (2026-10-28): "DataFrames was paused when foundational pieces of the software stack were missing. Unpause it please, and schedule work on a design memo using the previous learnings."

It applies [W-60's memo](2026-10-27-lean-core-old-apis.md) (four layers, the waist, loading on demand, the cache's place) to the third ecosystem, with what [the forks](../../forks/README.md) (sessions 27–29), TraitReport with TraitTables and TraitCSV, and the experiments since have taught.

## 0. Summary

- **The open sets are columns, tables, and the vectors CSV parses into.** User functions, sources and sinks are open sets too, but they stay in plain code (§1). Every other set in the three packages is closed and stays types.
- **Two traits in the core, one in CSV:** `Column{T}` (what every column provides, with its capabilities as operations with defaults), `TableSource` (a table as a consumer reads it), and CSV's `CSVColumn{T} <: Column{T}` (a vector the reader parses cells into).
- **A trait states only what every member does.** The forks' `Column{T}` declared `levelcode` and `level`, which always throw for a column without a pool; the member check refuses such a member ("always throws: a fallback, not an implementation", `TraitWorld/src/implement.jl:270–271`; E-163, `experiments/overnight-2026-10-21/README.md:90`), and the forked CSV no longer precompiles. In revision 2 a capability is an operation with a default that every member can serve: the pooled path is `groupcodes(c)`, whose default asks DataAPI's reference pool, as the forks did.
- **Four layers,** as for SciML and Makie:
  1. a **trait core**: `Tables.ColumnCore` with the traits and their family over `AbstractVector`; DataFrames' and CSV's kernels as bounded functions;
  2. **implementation packages**: column types join the family by being `AbstractVector`s; a source package implements `TableSource`;
  3. a **compatibility layer**: Tables.jl's duck-typed interface, plain, converted once at the entry;
  4. the **user API**: DataFrames' and CSV's names and calls, unchanged, the mini-language and user functions plain as today.
- **Kernels open a column once,** with `compiled_for` at their entry, where they loop over cells: one dispatch per column, code per column type, as Arrow and Polars downcast once per column (§1).
- **The control comes with the first numbers.** The facts mode alone takes upstream CSV and DataFrames from 561 to 2 lost CodeInstances under nine loads (evidence §1, `all`). The forks' session of 2026-10-20 (1.35 s against upstream's 10.7 s, a loaded machine) compared with upstream in plain mode only. D0 measures upstream plain, upstream wrapped in the product setting, upstream under `all` and the forks, on one build.

## 1. What the libraries are for, and their open sets

| Package | What it is for | Open sets (other packages add members) | Closed sets (stay types) |
|---|---|---|---|
| Tables | the interface between table sources and sinks | table sources and sinks; column types | `Schema`, `Columns`, `Row` wrappers |
| DataFrames | an in-memory table with a mini-language for transformations | column types; user functions in `=>` pairs; table sources a frame is built from | `DataFrame`, `SubDataFrame`, `GroupedDataFrame`, `DataFrameRow`, the index, the mini-language's pair forms |
| CSV | read and write delimited text | the vectors cells are parsed into (built-in types, InlineStrings' widths, a user's type with `Parsers`); sources (paths, `IO`, bytes); sinks (any Tables.jl sink) | the structural index, type detection over CSV's own types, `Rows`, `Chunks`, the writer's row emitter |

**Which open sets get traits.** Columns, tables and CSV's parse targets: the kernels loop over them, so code per key pays. User functions, sources and sinks stay plain: a user function is compiled per closure today and stays so (§3.3); a source is normalized to bytes at the reader's plain entry (rule 5 of W-60's memo); a sink is any Tables.jl sink, reached by the compatibility layer.

**Other systems** (primary sources):
- **pandas** holds an open set of column types: any class implementing `ExtensionArray` with an `ExtensionDtype` ([Extending pandas](https://pandas.pydata.org/docs/development/extending.html)). Its required methods include `take` (with `allow_fill` and `fill_value`, for joins); others are "to override for performance" (`unique`, `factorize`, `argsort`), with defaults on the base class, some through `astype(object)` (the class docstring, `pandas/core/arrays/base.py`). Capabilities are defaults on one interface, overridden per type: the shape of §3.1.
- **Apache Arrow (Rust)** and **Polars** hold a closed set of physical types behind a dynamic interface: a column is `ArrayRef = Arc<dyn Array>` ([`arrow_array::array::Array`](https://docs.rs/arrow-array/latest/arrow_array/array/trait.Array.html)), whose data type is an enum third-party types cannot extend; Polars' `Series` wraps `Arc<dyn SeriesTrait>` and dispatches on its `DataType` enum ([`polars_core::series::Series`](https://docs.rs/polars-core/latest/polars_core/series/struct.Series.html)). Their kernels downcast once per column and run typed code, which is `compiled_for` at a kernel's entry here. The set they downcast over is closed; ours is open, which is what the trait is for.

## 2. What the earlier work taught

From the forks ([`forks/README.md`](../../forks/README.md); porting B1):
1. **Kernels read through the operations,** never through `vector(c)` (the implementation review of 2026-10-18, P7). Session 29 rebuilt them so; the suites passed (forks 8c6366a), the session's digests equal upstream's at 26 steps.
2. **Heavy library code runs over gathered cells:** `describe` gathers `cell`s into a `Vector{T}` and runs Statistics there, compiled per `T`, shared by every column kind.
3. **What a type does by itself is an operation:** `take(c, rows)` keeps a pooled column pooled.
4. **A type passed as a value becomes a value that stands for it:** `stringtype = String15` makes `S[]`, and an extension declares implementations only. CSV.jl's first read took 0.19 s alone and 2.46–2.53 s with DataFrames loaded, in either order (`TraitReport/README.md:66`); the InlineStrings extension's methods on CSV's internal functions are the likely cause, not isolated from DataFrames' other loads, and measured on the package prototype only (evidence, "Shown"). TraitCSV's extension declares implementations only and discards none of the reader's code.
5. **A trait states only what every member does** (§0; E-163).
6. **A type held as a `DataType`** (`allocatecolumn(T, …)`) is a run-time site; carry a value that stands for it (porting B1 item 10).
7. **Where code lives:** a key from one package and a function from another live in no image unless a glue extension compiles them (L-15); the forks' `CSVDataFramesExt` and `CSVDataFramesInlineStringsExt` were plain remedies. The facts-keyed cache (W-66) is the principled answer.
8. **Standard libraries are Julia's own owner:** SparseArrays' `vcat` wins inside CSV's `_parse` (`[0; v]`), so a load that brings SparseArrays recompiles the reader (porting B1 item 11): TraitReport's work after StatsBase or Distributions 344–417 ms against 41 ms (evidence §3). Avoid concatenation syntax on Base's types in hot paths.

From W-60's memo and its experiments (E-176, E-179–E-184):
9. **Four layers and the waist** (§1.1 there).
10. **Normalize at the entry** (rule 5; E-184 at SciML's scale: 1.50 → 0.51 s; E-181 in TDE): column inputs to stored columns, keyword sets to typed option records, sources to bytes.
11. **Loading on demand** by stubs and `invokelatest` at user-facing entries (E-182), for heavy optional paths only.
12. **The load follows the tree** (E-176, E-179); measured here by D1.

From the facts work: the facts mode alone protects upstream code from unrelated loads (evidence §1). What traits add, to be measured against that control: protection from a package's own extensions on its internal functions (lesson 4), code per column type shared across schemas (sort, groupby, join per column, not per tuple of column types), and kernels that do not depend on the user's schema.

## 3. The architecture

### 3.1 The trait core

In the Tables fork, the owner of the interface (`Tables.ColumnCore`, a trait module):

```julia
# a sketch, not run
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    take(c::Column, rows::Vector{Int})::Column        # Dynamic: a view's rows are a Vector, a pooled column's a PooledVector
    emptylike(c::Column, n::Int)::Column               # a fresh column of a kind the member chooses
    vector(c::Column)::AbstractVector                 # the API's way back: df.a === v; kernels never call it
    # capabilities: every member can serve the defaults
    groupcodes(c::Column)::GroupCodes = _groupcodes(DataAPI.refarray(c), DataAPI.refpool(c), c)   # the pool if there is one, else hashed cells
end
@implement Column A where {A <: AbstractVector} begin   # the trait's owner, for every vector
    nrows(c) = length(c)
    cell(c, i) = c[i]
    take(c, rows) = c[rows]
    emptylike(c, n) = similar(c, n)
    vector(c) = c
end
@trait TableSource begin
    tablenames(t::TableSource)::Vector{Symbol}
    tablecolumn(t::TableSource, i::Int)::Dynamic{Column}
    tablerows(t::TableSource)::Int
end
```
- **Every column the stack produces is a member:** `Vector{T}` with and without `Missing` (a small union counts as concrete, [traits §11](../reference/traits.md#11-concreteness-and-fully-typed-mode); closed open issue 18), CSV's `StringVector{DataString}` (its default string column, `forks/CSV/src/core.jl:2535`), `PooledVector`, `CategoricalVector`, views of each (`subdataframe.jl:175`), ranges. Each member is checked at its first use ([traits §4.7](../reference/traits.md#47-families)). A member that fails the check is refused with its reason; the compatibility layer then copies it into a `Vector{T}`, which changes aliasing, and says so.
- **A weak point of the design, found here: a stored value's capabilities** ([open issue 82](../open-issues.md#1-decisions-waiting-for-the-user)). The principled form is a trait per capability, without a subtrait relationship: `@trait PooledColumn{T, R}` (`refs`, `pool`, concretely typed), implemented by PooledArrays and CategoricalArrays (or the Tables fork's extensions), and a kernel with two methods, `groupcodes(c::Column)` and `groupcodes(c::(Column, PooledColumn))`, chosen by dispatch. For plain values that works today. For the frame's stored `Dynamic{Column}` values it does not: a value is seen through the traits it entered with, and the columns of one frame conform to different sets. Until the issue is decided, the port takes the route below, which works today and closes the set of capabilities to `Column`'s owner.
- **The pool as an operation with a default (the route today).** `groupcodes` reads `DataAPI.refarray` and `DataAPI.refpool`, which PooledArrays and CategoricalArrays implement already (CategoricalArrays' pool indexed from 0, with `missing` at 0, by DataAPI's contract); for any other column `refpool` is `nothing` and the default hashes cells. Inside a kernel compiled per column type the branch folds. No member overrides an operation, so no override rule is met.
- **Mutation and growth stay plain:** `df[i, :a] = x`, `push!`, `insert!`, `append!`, the widening that replaces a column with a wider one (`dataframe/insertion.jl:774–791`), and the outer join's `similar(v, Union{T, Missing}, n)` (`join/composer.jl:8–9, 345–346`) run upstream's code on `vector(c)`. They are not hot per key.
- **`GroupCodes`** is a concrete record (codes `Vector{Int}`, the number of groups), so the pooled and hashed paths return one type.

**Where a column is opened.** The frame stores `Dynamic{Column}`. A kernel with a per-cell loop opens it at its entry: `refine!(perm, compiled_for(c), rev)`, `groupcodes(compiled_for(c))`, `innerrows(compiled_for(l), compiled_for(r), …)`. One dispatch per column per kernel, then code per column type ([traits §6.8](../reference/traits.md#68-costs-and-choosing); porting 0.4). Per-column work that is cheap or calls heavy code over gathered cells (`describe`'s gather, `show`'s `cellstrings`) stays `Dynamic` and shares code per cell type. The forks passed `Dynamic` columns into every kernel (`forks/DataFrames/src/abstractdataframe/sort.jl:634`); D3 measures both.

In the DataFrames fork, `DataFrames.Kernels` (a trait module): `colstats(c::Column, stats)` (describe), `refine!(perm, c::Column, rev)` (sort, one column at a time), `groupcodes` and the combination of per-column codes in plain integer code (groupby), `aggregate(c::Column, agg, gd)` (the fast aggregates over gathered cells), `innerrows`/`semirows(l::Column, r::Column, …)` (joins on one key column), `cellstrings(c::Column, rows)` (show), `fromsource(t::TableSource, copycols)` (the frame from a source).

In the CSV fork, `CSV.ColumnParsers` (a trait module), as the forks had it:

```julia
# a sketch, not run
@trait CSVColumn{T} <: Column{T} begin
    T = eltype(Self)
    parsecell!(c::CSVColumn, i::Int, buf::Vector{UInt8}, pos::Int, len::Int, opts::Parsers.Options)::Bool   # false: does not fit
end
@implement CSVColumn Vector{Int64} begin … end                  # members spelled out (porting B1 item 5)
@implement CSVColumn Vector{Union{Missing, Int64}} begin … end
# likewise Float64, Bool, Date, DateTime, Time, String; CSV's InlineStrings extension: Vector{String15}, … as members of their own
```
- The parse loop is one bounded function, `parsecells!(c::CSVColumn, …)`, called with `compiled_for` the column.
- **Type detection** chooses among CSV's own types, a closed set: a plain branch that makes the vector (`Int64[]`), no registry. A user's type enters as a value, `S[]` from `types =` or `stringtype =`, and must conform.
- **The forks' `TextColumn`** (string conversion for `CSV.Rows` and the widths) is not needed: the widths are `CSVColumn` members, and `CSV.Rows` keeps upstream's plain text path. **`CSVSource`** is not needed: the reader's entry is plain and normalizes a source to bytes.
- **The writer** (`@generated _preparewritecolumns` per tuple of column types, `forks/CSV/src/write.jl:911–927`) stays plain in the first port; a writer per column type is a later step, measured first.

### 3.2 The compatibility layer: Tables.jl's duck interface

- **Kept, plain:** `istable`, `columns`, `rows`, `getcolumn`, `columnnames`, `schema`, `Tables.Schema{names, types}`, `columntable`, `rowtable`, dict and matrix tables, `Tables.Scan`. Every package that implements Tables.jl today keeps working.
- **One conversion at the entry:** a source that does not conform to `TableSource` is converted once, `Tables.columns(x)` and `getcolumn` per name, into a `Vector{Dynamic{Column}}` ([traits §4.10](../reference/traits.md#410-types-that-only-convert)). Its columns are `AbstractVector`s, so they are members as they are; no copy unless a member is refused.
- **Lazy sources** (Arrow's memory-mapped tables) keep their columns: an `Arrow.Primitive` is an `AbstractVector`, so it is a member; `TableSource` for Arrow's table is Arrow's, or the Tables fork's extension, when a measurement asks for it.

### 3.3 The user API, unchanged

- `DataFrame(...)`, `df.a`, `df[!, :a]`, `df[rows, cols]`, `select`, `transform`, `combine`, `groupby`, `subset`, `sort`, the joins, `describe`, `show`, `CSV.read`, `CSV.File`, `CSV.write`: names and behaviour as upstream's; the upstream test suites decide.
- **Storage:** `DataFrame.columns::Vector{Dynamic{Column}}` with `_columns(df)` an adapter that reads and writes through the kept values (porting B1 item 12); `df.a` returns `vector(c)`, the stored vector itself.
- **The mini-language and user functions stay plain,** compiled per closure as today; a column-wise function receives the column itself, as upstream passes it. A `Callable` at the columns' cell types would compile per signature instead of per closure, but its argument types would follow a bound's parameter, which the references refuse ([traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)), and its open result is Planned (T-18). Not in this port.
- **`show`:** `cellstrings` per column fills a `Matrix{String}`; PrettyTables renders it once per IO type (porting B1 item 11).

### 3.4 What loads when

| When | What |
|---|---|
| `using DataFrames` | TraitWorld; Tables with `ColumnCore`; DataFrames with its kernels; PooledArrays, InlineStrings, DataAPI (dependencies today); PrettyTables (the text back end) |
| `using CSV` | CSV with `ColumnParsers` and its built-in members; the InlineStrings members when InlineStrings is loaded (an extension of CSV, the trait's owner) |
| the first HTML or LaTeX `show` | PrettyTables' back end, through a loading stub, if D1 finds it worth it |
| the user loads a package | its column types, which are members already; its `TableSource` implementation if it has one |

### 3.5 Where the facts-keyed cache fits

The kernels' code for a column type the images do not hold (a user's element type, a `Vector{Celsius}`) is facts code at a library key: the store (W-66) keeps it across sessions and environments. Upstream's glue extensions with workloads (lesson 7) then become unnecessary; until the store exists, they stay as plain remedies, labelled.

## 4. Costs and risks

1. **Sort and groupby on several columns:** per-column work combined in plain integer code (group codes) or one column at a time from the last (sort); no worker per pair of column types, which would bring back upstream's per-tuple compilation. Where a column type sorts by itself faster (`sortperm` on a `Vector{Int}`, radix), that is an operation with a comparison default, if D3 asks for it.
2. **Gathering cells** for `describe` and the aggregates copies each column once per call; bounded by one pass; D3.
3. **More than four column types** in a session leave the `Dynamic` split's fast path ([traits §6.8](../reference/traits.md#68-costs-and-choosing); 2.5–18.5 ns per call beyond four, E-145): another reason to open columns at the kernels' entry.
4. **Threads:** DataFrames spawns tasks in `groupby` and `combine`, CSV parses in parallel. E-63 showed calls through split sites and `compiled_for` consistent while the main thread defines; workers compiled from several tasks at this scale are tested by the suites at `-t 4`.
5. **`combine` with a function of a `SubDataFrame`** makes a `SubDataFrame` per group, whose columns are kept values per group: one `Dynamic` per column per group. Measured in D3.
6. **Who may implement `Column` for a user's type:** the family covers every `AbstractVector`, so a user's vector type needs no implementation; a user's column that is not an `AbstractVector` is the type owner's implementation ([traits §10.1](../reference/traits.md#101-who-may-implement)).
7. **Names:** `nrows`, `cell`, `take`, `vector` clash with exported names (`DataAPI.nrow`, `Base.take!`); operations are `ColumnCore`'s functions, not exported (porting B1 item 7).

## 5. The smallest experiments, in order

- **D2, the traits in isolation (first: nothing else can be measured on the current build).** `ColumnCore` of §3.1 in the Tables fork; every column type the suites produce (printed from Tables', CSV's and DataFrames' suites) passes the member check, views and `StringVector` included; Tables' suite green; then the forked CSV precompiles. **Would change the design:** a column type the suites produce that cannot be a member.
- **D0, the control, on one build:** the forks' session (`forks/scripts/session.jl`) for upstream in plain mode, upstream wrapped as trait modules in the product setting (porting 0.1), upstream under `all`, and the forks in the product setting; a warm-up and two runs each, on a quiet machine. **Decides the claim's scope:** if the forks are within 1.5× of the better upstream setting (the 2026-10-17 plan's falsification clause, its §6), the traits' contribution is narrowed to schema independence and extensions (lesson 4).
- **D3, the kernels' costs,** with columns opened (`compiled_for`) and `Dynamic`: `refine!`, `groupcodes`, `colstats`, `aggregate`, `innerrows` against upstream on 10⁶ rows, one and two columns, and `combine` over `SubDataFrame`s. **Would change the design:** a steady-state slowdown above 20% against upstream with columns opened.
- **D4, schema independence:** a second and a third schema with the same column types, with loads before and after. **Would change the design:** any new worker for a schema whose column types were seen: keys would be leaking the schema.
- **D1, the load:** `@time_imports` of `using CSV, DataFrames` (stock and patched). **Would change the plan:** PrettyTables and the tree beyond Tables, DataFrames and CSV over 0.3 s of the import: a loading stub for PrettyTables' back ends (§3.4).

## 6. What the design uses from the references

- **Implemented:** traits with an equation for a parameter, families over an abstract type with a block, operations with defaults, `Dynamic` results, kept values in storage, `compiled_for`, implementations in the trait owner's extension, types that only convert, loading stubs (W-60's §1.4).
- **The member check's rule for a method that always throws** (a fallback, not an implementation; `TraitWorld/src/implement.jl:270–271`) is stated in [traits §4.7](../reference/traits.md#47-families) (2026-10-28, mine, for W-71).
- **Wanted, and open:** selecting a capability of a stored value (open issue 82: a kept value seen through every trait its object conforms to, or a checked trait cast, §6.9).
- **Not used:** a `Callable` over a bound's parameters (refused, §5.8) and open results (T-18, Planned), member overrides (T-28), forwarding for a whole family (T-7, Planned).

## 7. Questions left open

1. Is `groupcodes`' default through DataAPI enough for joins on pooled keys, or do joins want their own capability (`refpool` of both sides)? D3 measures.
2. Should a refused member be copied by the compatibility layer, or refused at `DataFrame(...)` with the member check's message? The memo copies, as upstream's `copycols` does; the user may prefer the error.

## 8. The review of revision 1, and what is done with each finding

| Finding | Done |
|---|---|
| B1 capabilities unreachable from `Dynamic` storage | §3.1: capabilities as operations with defaults (`groupcodes` through DataAPI); mutation and growth plain |
| B2 `take`, `emptylike` returning `Self` | §3.1: `::Column` |
| B3 user-function bounds refused | §3.3: user functions plain |
| M1 the family too narrow | §3.1: a family over `AbstractVector`; the stack's column types listed |
| M2 where a column is opened | §3.1: `compiled_for` at a per-cell kernel's entry; D3 measures both |
| M3 §6 | §6 rewritten; the always-throws rule stated in traits §4.7 |
| M4 `CellParser` | §3.1: `CSVColumn{T}` with a receiver, members spelled out; `TextColumn` and `CSVSource` not needed, with reasons |
| M5 citations | §0, §2: E-163's cause from its README; no Tables extension claimed |
| M6 the experiments | §5: D2 first, D0 on one build with the product setting, criteria for D1 and D4, no per-pair workers |
| M7 joins, growth, the pool | §3.1: plain through `vector(c)`; the pool by DataAPI inside code per column type |
| m1 subtrait parameters | no subtraits in the core; `CSVColumn{T} <: Column{T}` with its equation |
| m2 "by its own methods" | §3.1: a block |
| m3 "decision 18" | §3.1: traits §11, closed open issue 18 |
| m4, m5 numbers | §2, lessons 4 and 8 |
| m6, m7 other systems, the URL | §1 |
| m8 `PooledColumn` name clash | no such trait |
| m9 open sets, the writer | §1, §3.1 |
| m10 risks | §4, items 3–6 |
