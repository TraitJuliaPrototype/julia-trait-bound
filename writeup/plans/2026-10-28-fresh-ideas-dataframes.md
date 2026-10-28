# Fresh ideas: DataFrames, CSV and Tables in the trait world, and the weak points they expose

Status: **proposal** (2026-10-28, a fresh-eye agent's ideas, Opus; not adopted). Not normative.

Serves: W-79 and [open issue 82](../open-issues.md#1-decisions-waiting-for-the-user). The user (2026-10-28): "Remember that one purpose of the ports is to identify weak points in the design." "Feel free to send out fresh eyes opus subagents to come up with fresh ideas for the design and/or the architecture of the ports." And, passed on during this work: "The guiding principle should be principled solutions. If a tweak in the trait design can enable a principled solution in the port architecture, that's the most valuable finding we can have."

How this was written: the references, the forks, TraitTables, TraitCSV and upstream's source first; a view formed; then [the current memo](2026-10-28-dataframes-lean-core.md), [its review](../reviews/2026-10-28-dataframes-lean-core.md) and open issue 82. No Julia ran. Line numbers are those of the files at design repository a7e102c.

## 0. Summary

- **One idea carries the architecture: compile per associated type, not per column type.**
  - A column kernel needs the cell type `T` and the data's physical layout. It does not need the column's container type.
  - The layouts are a closed set: dense, pooled, chunked. Closed sets are types. So the core owns concrete span types (`DenseSpan{T}`, `PoolSpan{T}`), and the kernels are plain typed code over them, compiled per `T`.
  - Column types are the open set. Each column type supplies only small operations: hand out a span if it has one, or copy cells into a buffer in bulk.
  - The trait design already compiles a `Dynamic` value's worker once per the trait's parameter values ([lowering §5](../reference/lowering.md#5-keys-and-views), `lowering.md:262`). That is exactly "per `T`". The references do not say so, and the annotation rule forbids asking for it. Weak point 1.
- **Columns meet only in index space.** Sort, groupby, join and unique on several columns each run a per-column kernel that yields integers (ranks, group codes, row pairs). One integer kernel, compiled once, combines them. No code is compiled per tuple of column types, and none per schema.
- **Capabilities split in two.**
  - A capability of the physical layout (a pool, dense storage, chunks) belongs to a closed set. It is an operation on `Column` that returns an optional view: `pooled(c)::Union{Nothing, PoolSpan{T}}`. The trait exposes data, never an algorithm, so a new kernel needs no new operation.
  - A capability from outside (a device column, a lazy database column, a third party's sorted vector) belongs to an open set. It needs a trait of its own, selected where the value is used. That is open issue 82. I support its option (a), with a precise form of (b) beside it (weak point 2).
- **User functions can enter the trait world** if a `Callable`'s argument types may follow another bound's associated type. Then `ByRow(f)` over a column of cell type `T` is compiled once per `T`, not once per closure. Weak point 3.
- **CSV's open set is cell types, not vectors.** A type is a value in Julia. If `Type{S}` may conform to a trait, `Int`, `Date` and `String15` conform directly, and the empty-vector stand-ins go. Weak point 4.
- **Weak points found,** in order of value: (1) `Dynamic` per associated type; (2) capabilities of stored values; (3) `Callable` signatures that follow a bound; (4) types as values. Smaller: (5) operations valid only when another says so; (6) predicate-based informal interfaces; (7) the member check per view type.

## 1. The architecture I propose

### 1.1 Three rules

1. **The key is the associated type.** The hot code of a column kernel must know `T`. It must not know whether the cells sit in a `Vector{T}`, a `SubArray` of one, or a `StringVector`. Porting 0.4 says it: "the key holds what the hot code must know, and no more" (`intro/porting.md:70`).
2. **Layouts are closed, columns are open.** Physical layouts are a small set the core owns, as types. Column types are an open set, as a trait. An operation maps a column to a layout, or copies its cells.
3. **Columns meet in index space.** A kernel over several columns works column by column into integers, and combines integers.

Rule 1 is Arrow's design: compute kernels are chosen "depending on the concrete input types" ([Arrow C++ compute](https://arrow.apache.org/docs/cpp/compute.html)), that is per data type, never per container. Rule 3 is arrow-rs's row format: each column is encoded into bytes that compare as a lexicographic sort would, for "multi-column sorting, grouping, aggregation" ([`arrow_row`](https://docs.rs/arrow-row/latest/arrow_row/)). Rule 2 is pandas' answer for an open set: an extension array hands the fast kernels a NumPy array through `_values_for_factorize` and `_values_for_argsort` ([`ExtensionArray`](https://pandas.pydata.org/docs/reference/api/pandas.api.extensions.ExtensionArray.html)).

### 1.2 The traits

In the Tables fork's trait module (a sketch, not run):

```julia
struct DenseSpan{T};  data::Vector{T}; first::Int; n::Int;  end           # the core's closed layouts
struct PoolSpan{T};   refs::Vector{UInt32}; pool::Vector{T}; base::Int;  end   # refs index pool from `base`
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T                                          # the slow path; plain helpers
    cells!(dst::Vector{T}, c::Column{T}, from::Int)::Int                    # bulk: fills dst from row `from`, returns the count
    dense(c::Column{T})::Union{Nothing, DenseSpan{T}} = nothing           # layout views: every member can serve the default
    pooled(c::Column{T})::Union{Nothing, PoolSpan{T}} = _pool_from_dataapi(c)
    vector(c::Column)::AbstractVector                                      # the API's way back; kernels never call it
end
```

- **Every operation is one every member can do.** No operation is valid only when another one says so (weak point 5). So E-163's refusal (a method that always throws, `traits.md:467`) cannot recur.
- **The views return the library's own concrete types.** Kernels over them are plain typed code. `Vector{T}` returns a `DenseSpan` of itself, a contiguous view of a `Vector` one of its parent, `PooledVector` and `CategoricalArray` a `PoolSpan` of their stored arrays without a copy.
- **`cells!` is the bulk path** for everything else: `StringVector`, ranges, lazy columns. One dispatch per buffer of cells, not per cell.
- **`TableSource`** as the memo has it (`tablenames`, `tablecolumn(t, i)::Dynamic{Column}`, `tablerows`). The schema is data (names, and each column's `T` read from it), never a type. `Tables.Schema{names, types}` (`Tables.jl:454` at the forks' `upstream` tag) stays in the compatibility layer.
- **Open capabilities are traits of their own,** owned by whoever invents them: a GPU package's `DeviceColumn`, a database package's `PushdownColumn`. A kernel's function gets a bounded method for them, from the kernel's owner or from the capability's owner ([traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits), `traits.md:633`). Reaching them from stored columns is weak point 2.

### 1.3 The kernels

In DataFrames' trait module, each kernel takes a stored column as it is, `Dynamic`, and so runs a worker per `T`:

| Operation | Per column, compiled per `T` | Combined in index space, compiled once |
|---|---|---|
| sort, `sortperm` | ranks: Base's typed `sortperm` on the dense span or the gathered `Vector{T}`, with the algorithm Base picks for `T`; a pooled column ranks its pool | a lexicographic sort of rank vectors (`Vector{UInt32}`) |
| groupby | group codes: from the pool, or a `Dict{T, UInt32}` over cells | codes combined by mixed radix, or hashed when the product overflows |
| joins on k keys | joint codes of the left and right key columns (per pair of cell types `(Tl, Tr)`, usually one `T`) | an integer join on the code tuples |
| `unique`, `nonunique` | group codes | as groupby |
| `describe`, fast aggregates | Statistics over the span or the gathered cells | — |
| `show` | `cellstrings` into a `Matrix{String}` | PrettyTables, once per IO type |
| `CSV.write` | each column rendered to bytes per buffer of rows | rows interleaved in byte space |

- Upstream compiles sort per tuple of column types (`DFPerm`, `sort.jl:106`) and groupby per tuple (`row_group_slots!`, `groupeddataframe/utils.jl:192`), both at the `upstream` tag. The forks compiled per column type. This compiles per cell type.
- A new column type compiles `cells!` and its views, a few lines. It compiles no kernel.
- A new cell type (a user's `Celsius`) compiles each kernel once, at that `T`. Weak point 1 states this cost.
- The memo's `refine!` (one comparison sort per column, through `cell`) becomes one typed `sortperm` per column plus one integer sort. Integer keys get Base's fast paths.

### 1.4 User functions

- `transform(df, :a => ByRow(f) => :b)`, `subset(df, :x => ByRow(>(0)))`, `order(:a; by = g)`: the function is seen as `Callable{Tuple{T}, S}`, with `T` the column's cell type and `S` open.
- `Dynamic` by `Callable`'s default: the loop is compiled once per `T`, and a new closure compiles only its own body at `Tuple{T}`. `ByRow(compiled_for(f))` gives upstream's per-closure speed.
- Results widen by value, as Base's `map` and DataFrames do. So `S` is an upper bound inferred at the entry; the loop collects as `map` does when a value falls outside its first result's type. G1 holds: the same column, or an error ([facts §2.1](../reference/facts.md#21-g1-identical-or-error)).
- Several columns, `[:a, :b] => ByRow(f)`: compiled per `(Ta, Tb)`. The user asked for that pair.
- Column-wise functions (`:a => mean`, `:c => levels`) receive the stored vector, as upstream passes it, and stay plain (the review's B3).
- This needs weak point 3.

### 1.5 CSV

- **The open set is cell types:** CSV's own, InlineStrings' widths, a user's type from `types =`. The parse targets are CSV's own storage, a closed set (`TypedColumn{T}`, `UnionColumn{T}`, the string vectors).
- **A cell type conforms to `CellParser{T}`** (a sketch, needs weak point 4):

  ```julia
  @trait CellParser{T} begin
      T = instancetype(Self)                         # Self is Type{Int}; T is Int
      tryparsecell(p::CellParser{T}, buf::Vector{UInt8}, pos::Int, len::Int, opts::ValueOpts)::Union{Nothing, T}
  end
  @implement CellParser Type{Int64} begin … end      # in CSV, the trait's owner
  @implement CellParser Type{String15} begin … end   # in CSV's InlineStrings extension: a member of its own
  ```
- The parse loop `parsecells!(dst::Vector{T}, p::CellParser{T}, …)` is `Compiled` per parser: parsing is the hot path, and the parsers are few.
- Type detection walks a candidate list, a `Vector{CellParser}` passed as a value (CSV's own by default). A package that wants its type detected adds it to the list the user passes. No global registry.
- The forks' `CSVColumn{T}`, `TextColumn{T}` and `S[]` stand-ins go. Porting A11 ("a type passed as a value becomes a value that stands for it", `intro/porting.md:238`) becomes: a type passed as a value conforms itself.

### 1.6 Storage, the compatibility layer, the user API

As the memo has them (§3.2–§3.4 there): `DataFrame.columns::Vector{Dynamic{Column}}` behind an adapter; Tables.jl's duck interface plain, converted once at the entry; the user API unchanged. Mutation and growth plain through `vector(c)`.

One addition: **batches.** Streaming sources (`CSV.Chunks`, Arrow's record batches, `Tables.partitions`) are column batches. A row iterator is converted once into builders per column. Rows stay a view `(table, i)` for user code. Polars' and Arrow's row-wise ingestion is their slow path too.

## 2. Weak points of the design

Each: the case, the rule that blocks it, the change I propose to the references, and what it costs elsewhere. The first four enable a principled form of the port. They get the most room.

### WP1. `Dynamic` is compiled per associated type, but the references say "once" and forbid asking for it

**The case.**
- Per-`T` kernels (§1.3) need a column position whose code is compiled per cell type `T`, never per column type.
- The lowering gives exactly that for a `Dynamic` value at a bare bound: "the worker at the erased key is compiled once per tuple of parameter values" (`lowering.md:262`).
- But a library cannot ask for it at its public positions:
  - a plain caller that knows a `SubArray`'s type passes a `Compiled` value (the first-seen rule, `traits.md:763`), so every kernel compiles per view type;
  - `@default_with_dynamic_self` on `Column` would not apply to Base's vectors, which are "of the trait world" (`traits.md:791`);
  - the annotation `c::Dynamic{Column}` is refused, because `cell` returns `T` (`traits.md:578`).
- The frame's own storage, `Vector{Dynamic{Column}}`, holds columns of different `T`. The references do not say what a kept form with an open parameter is. §7.1 says only that a form "fixes the parameters its operations' result types use" (`traits.md:952`).

**The rules.**
- `traits.md:725`: "`Dynamic`: code compiled once runs for it."
- `traits.md:894`: "`Dynamic` values of one trait share one compiled copy per position, with the parameter values the position fixes."
- `traits.md:578`: a `Dynamic` annotation must fix every parameter its operations' results use.
- `traits.md:952`: silent on a kept form with an open parameter in storage.

**The proposal.** State the level the lowering already builds, and let a library ask for it.
1. §6.1 and §6.7: a `Dynamic` value's code is compiled once per the values of the trait's parameters it carries, its associated types. A trait without parameters keeps "once".
2. §5.1: a `Dynamic` annotation may leave a parameter to a `where` variable: `c::Dynamic{Column{T}} where {T}`. Code after an operation stays typed at each `T`, which is the rule's purpose.
3. §7.1: a kept form may leave parameters open in storage, `Dynamic{Column}` in `Vector{Dynamic{Column}}`, as an existential. From plain code, an operation's result is asserted at the parameter's bound (`Any` for a bare `T`). At a bound, the value's own parameters are read when it enters (as `lowering.md:262` does).

**What it buys.** A third level between "per type" and "once": per associated type. It is what Arrow and Polars do by data type, and what W-63 did by hand for SciML (the solver keyed on the state's type, not the parameters', E-181). It makes "the key holds what the hot code must know" (porting 0.4) something a library declares, not something it engineers by storage.

**What it costs.**
- The promise "a new user type compiles nothing in the library" becomes "nothing beyond its associated types". A user's new cell type compiles each kernel once.
- Swift does the same when it opens an existential at a generic parameter ([SE-0352](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md)), but it opens the whole type. This opens only the associated types.
- No lowering change, if the deviation the forks found is gone: `f(c::Column{T}) where {T}` raised `MethodError` for a `Dynamic{Column}` (`forks/README.md`, "TraitWorld issues found", session 29). Experiment X-B probes it.

### WP2. A stored value's capabilities: who decides which traits a value is seen through

**The case.** Open issue 82 states it with a pool. Under §1.2 the pool is a layout view, so this port does not need issue 82 for the pool. It needs it for capabilities from outside:
- a GPU package whose column type brings its own groupby;
- a database package whose lazy column can push a filter down;
- a package whose sorted vector type lets `sort` and joins skip work.

Their owners can declare the trait and the bounded method. The kernel cannot reach them from a stored `Dynamic{Column}`.

**The rules.**
- `traits.md:856`: "A value is seen through the traits it entered with."
- `traits.md:917`: trait casts are "not part of the language" (Optional, §6.9).
- `traits.md:603`: passing a trait object where a different trait is expected is refused.
- `design/alternatives.md:303`: the reasons for the rule.

**The fault line.** The rule lets the code that stores a value decide what it can be seen as. In a frame, the storer is the frame. It knows only `Column`. The code that wants a capability is written later, often by another package. In an open world the user of a value must decide, not its storer. A tuple of traits at entry (`traits.md:329`) cannot help: a tuple is an intersection, and a frame's columns conform to different sets.

**The proposal.** Issue 82's option (a), with (b) as its spelled form, made precise.
1. **(a) at a bound:** a kept value, and a trait object at the erased key (both hold the user's whole object, `lowering.md:261`), is seen through every trait its object conforms to. Dispatch among bounds then selects the most capable method, as for a plain value (`traits.md:628`).
2. **(b) in code:** `c isa PushdownColumn` on such a value tests its held object (§14's planned membership, `traits.md:1381`). Inside the true branch, `c` is seen through `(Column, PushdownColumn)`. Definition checking follows the branch, as Julia's inference narrows on `isa`. Use it where the fast paths have an order the kernel's author chooses.
3. A `Compiled` trait object that holds only a forwarded part stays as it entered. The alternatives' reason (`design/alternatives.md:303`) holds for it, and only for it.

**Other languages.**
- Go's standard library selects optional capabilities so: `io.Copy` calls `src.WriteTo(dst)` if the source implements `WriterTo` ([`io.Copy`](https://pkg.go.dev/io#Copy)).
- Swift checks a protocol at run time: "the `as?` version of the downcast operator returns an optional value of the protocol's type" ([Protocols](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Protocols.md), "Checking for Protocol Conformance").
- Rust coerces a trait object only to a supertrait ([Rust 1.86](https://blog.rust-lang.org/2025/04/03/Rust-1.86.0/)). A cast to an unrelated trait needs an `as_x(&self) -> Option<&dyn X>` method on the base trait, which closes the set: issue 82's option (c).
- Swift's TabularData stores type-erased `AnyColumn`s and recovers a typed `Column<T>` by `assumingType(_:)` ([`AnyColumn`](https://developer.apple.com/documentation/tabulardata/anycolumn)): use-site recovery again.

**What it costs.**
- At the entry: a conformance check of the held object's type against the bounded methods' traits. It is cacheable per (function, type), like the split's table (E-145).
- G2 is untouched: membership is read when the code runs (`traits.md:1381`), so a later implementation discards nothing.
- Definition checking must narrow on `isa` for (b).
- The decision of 2026-10-21 is reversed for kept values (`decisions.md:121`); W-31 changes; T-53's behaviour becomes the design, with `TraitBoundError` where the object does not conform.
- **The joint-method rule's price grows** (`traits.md:629`). With k unrelated capability traits bounding one function at one position, every pair needs a joint method. The package that adds a capability writes its joints with the existing ones, at its own module's end. Where that list grows, (b)'s explicit order is the answer, not more joints. I would keep the rule.

### WP3. A `Callable` whose argument types follow another bound's associated type

**The case.** `ByRow(f)` over a column of cell type `T`; `subset`'s predicates; `order(…; by = g)`; BaseTraits' `retain!` over any item type. The principled form is `f::Callable{Tuple{T}, S}` beside `c::Column{T}`.

**The rules.**
- `traits.md:707`: "The argument types `A` are a constant type. A bound whose `A` names a method's `where` variables … is refused."
- `traits.md:1154`: `f::Callable{Tuple{T}, Bool}` for any item type "cannot be written".
- `lowering.md:341`: "A `Callable` bound naming one is refused (`_uses_callable`)."
- Open results `S` are Planned (T-18, `traits.md:1514`).

**The proposal.** A `Callable`'s `A` may name `where` variables that other bounded arguments of the same method determine through their associated types.
- The entry enters the other arguments first, reads their parameters (`_trait_param`, `lowering.md:341`), then enters the function at the resulting signature.
- The worker is compiled per `(key…, A)`: per `T` for a `Dynamic` column, which WP1 gives anyway.
- The design already allows the same for a struct parameter's bound, which "may name the struct's other parameters" (`traits.md:707`, §7.4).
- With T-18's open `S`, inferred in plain code at the entry: when `S` is not concrete, the kernel collects by value as Base's `map` does, so the result equals upstream's (G1).

**What it costs.**
- At each call: the erased function made at the signature per `(function type, T)`; cached for functions that capture nothing (`lowering.md` §12), one wrapper allocated for a closure.
- Several functions at signatures that follow one bound: one wrapper each.
- The check of the arguments against `A` moves from the method's definition to its first call per `T` (as §9's first-call row does for open parameters, `traits.md:1175`).

**What it buys.** Upstream compiles `map` per closure. Each new anonymous function at the prompt compiles the loop again; upstream's session spent 0.27 s on one user-function step (`forks/README.md`, M0 table). With this change, a new closure compiles only its own body. That is W-63's lesson (keep user types and functions at the surface) for tables.

### WP4. Types as values: a trait implemented by `Type{S}`

**The case.** CSV's open set is cell types. Julia passes them as types: `types = Dict(:d => Date)`, `stringtype = String15`, `allocatecolumn(T, n)`.
- The references give no way to see a type through a trait: "the first argument is the value seen through the trait" (`traits.md:194`), and every example is an instance.
- So the forks made an empty `Vector{S}` stand for `S` (porting B1 item 5, A11), guarded a run-time `conforms(Vector{S}, TextColumn)` with a static test so that `CSV.Rows` would not ask per cell, and TraitCSV keeps candidates as `Dynamic{CSVColumn}(Int[])` (`TraitCSV/src/CSVCore.jl`, `defaulttypes`).
- The review of the memo found the same gap from the other side (its M4: `parsecell!` "has no receiver").

**The rule.** None refuses it outright; none admits it. `Type{Int}` is a concrete singleton type in Julia, owned by Julia. Whether `@implement CellParser Type{Int64}` is accepted, and what `Self`, the key and printing are then, is not written anywhere. No code in the repository tries it.

**The proposal.** State in §4 that a type value conforms like any value. `Self` is `Type{S}`; an associated type recovers `S` by an equation (`T = instancetype(Self)`); the key is `Type{S}`; a family reads `@implement X Type{S} where {S <: InlineString}`.

**Other languages.** Rust's `FromStr::from_str(s: &str) -> Result<Self, Self::Err>` has no receiver ([`FromStr`](https://doc.rust-lang.org/std/str/trait.FromStr.html)). Swift's protocols declare `static` requirements and initializers ([Protocols](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Protocols.md)). Julia's `Type{S}` gives both without a new construct.

**What it costs.** Probably nothing in the lowering (X-C probes it). Ownership is the usual rule: `Type{Int}`'s owner is Julia, so the trait's owner implements it. It removes a workaround-shaped rule from porting part A.

### WP5. Operations valid only when another one says so

**The case.** The forks' `Column` had `levelcode(c, i)` and `level(c, k)`, valid only when `nlevels(c) > 0`. For other members they always throw. The member check refused them (E-163), and the forked CSV stopped precompiling. The memo answers with `groupcodes(c)`, an algorithm on the trait. A join on pooled keys then needs another operation (the memo's own question 7.1).

**The rule.** `traits.md:220` (a default never throws "not implemented") and `traits.md:467` (always throws: a fallback). They are right.

**The proposal.** No reference change; a rule for porting part A: *a capability of a closed set of layouts is an operation that returns an optional view of a concrete type the trait's owner defines (`pooled(c)::Union{Nothing, PoolSpan{T}}`), never an algorithm, and never an operation that is valid only when another says so.* pandas' `_values_for_factorize` and DataAPI's `refpool` (which returns `nothing`) have this shape.

### WP6. Predicate-based interfaces cannot become implementations

**The case.** Tables.jl's sources announce themselves by a predicate, `Tables.istable(::Type{T}) = true`. A generic implementation "every `T` with `istable(T)`" would make every Tables.jl source a `TableSource` in one line.

**The rule.** `traits.md:505`: "Constraints are patterns, never computed conditions."

**The proposal.** Keep the rule: it keeps overlap decidable. Convert at the entry (`traits.md` §4.10), as the memo's compatibility layer does. Sources are cold; nothing per key is lost. Record it in porting B1, so the next port with a Holy-trait interface does not try.

### WP7. The member check per view type

**The case.** The family over `AbstractVector` checks each member at its first use (`traits.md` §4.7). DataFrames makes many view types (a `SubArray` per parent and index type, `subdataframe.jl:175` at the `upstream` tag). Each first use infers every operation for that type.

**The rule.** `traits.md:466–470`, as designed.

**The proposal.** None to the rule. Two mitigations: per-`T` kernels (WP1) keep the per-type work to the small operations; the facts-keyed cache (W-66) keeps the checks. D2 should count the member types the suites make, and the time their checks take.

## 3. Where I differ from the memo

| Topic | The memo (revision 2) | This proposal | Why |
|---|---|---|---|
| What a kernel is compiled for | the column type: `compiled_for(c)` at the kernel's entry | the cell type `T`: the stored `Dynamic` column as it is, with spans and bulk `cells!` | the hot code needs `T` and the layout, not the container; a new column type compiles no kernel (WP1) |
| The pool | `groupcodes(c)`, an algorithm on `Column`, default through DataAPI | `pooled(c)`, a view of a concrete core type, default through DataAPI | joins and sorts reuse it; no new operation per kernel (WP5) |
| Issue 82 | wanted, the port goes on without it | not needed for the pool; needed for capabilities from outside; (a) with (b) as narrowing | the storer cannot know what later code needs (WP2) |
| Several columns | sort by `refine!` from the last column; groupby by codes | ranks and codes per column, one integer kernel; joins too | integer keys get Base's fast sorts; joins on k keys stop being a special case |
| User functions | plain, per closure | `Callable` at `Tuple{T}`, `Dynamic` by default, widening by value | a new closure compiles its body only (WP3) |
| CSV's trait | `CSVColumn{T} <: Column` on vectors standing for cell types | `CellParser{T}` on cell types themselves | the open set is cell types (WP4) |
| Type detection | a plain branch over CSV's types | a candidate list passed as a value | a user's type joins detection without a registry |
| The writer | plain, `@generated` per tuple of column types | per column into bytes, rows interleaved in byte space | rule 3 |
| Streaming sources | not covered | batches of columns; rows as a view | Arrow and Polars ingest so |

I agree with the memo's open sets, the four layers, the plain compatibility layer, the unchanged user API, plain mutation and growth, and D2 first.

## 4. The smallest experiments

Each gets a registry row first. Each is minutes of machine time, one Julia job at a time, niced. None is a benchmark campaign: each decides one question.

- **X-A. The kernel's key** (decides §1.3 against the memo's `compiled_for`). `sortperm` and group codes over 10⁶ rows of six column types: `Vector{Int}`, `Vector{Union{Missing, Int}}`, a view of a `Vector{Int}`, `PooledVector{String}`, `StringVector{DataString}`, `CategoricalVector{String}`. Two forms: the stored `Dynamic` column at a per-`T` kernel over spans and `cells!`; and `compiled_for` at the entry over `cell`. Count the workers compiled; time a first call and a second call in one session. **Would change the design:** per-`T` slower than `compiled_for` by more than 20% at the second call on any type, with no fix in the span path.
- **X-B. Open parameters in storage and at a bound** (WP1). A `Vector{Dynamic{Column}}` of three cell types, passed to `f(c::Column{T}) where {T}`; and an annotation `c::Dynamic{Column{T}} where {T}`. **Would change:** a `MethodError` makes the session-29 finding a deviation row (T-) and WP1's third point a prerequisite.
- **X-C. A type as a value** (WP4). `@implement CellParser Type{Int64}` and a family `Type{S} where {S <: InlineString}`: accepted or not, `conforms`, the key printed, a bounded call `Compiled` and `Dynamic`. **Would change:** a refusal makes WP4 a lowering item, not a sentence.
- **X-D. Capability selection, emulated** (WP2). T-53's present behaviour accepts a kept value at a bound of another trait (`traits.md:1549`). Measure, without building anything: a call of `g(c::Column)` beside `g(c::(Column, Sorted))` with stored columns, the method each reaches, and the entry's cost per call. This informs issue 82; it does not rest a design on a deviation. **Would change:** an entry cost above about 100 ns per call makes (b), the explicit test inside the kernel, the recommended form.
- **X-E. User functions' first calls, upstream** (WP3's value). Five distinct closures in `transform(df, :a => ByRow(f) => :b)` at the prompt, upstream plain: the time per new closure; then the same loop with the function erased by hand at `Tuple{Int}` (a `FunctionWrapper`). **Would change:** under about 20 ms per new closure, WP3 is not worth the lowering change for DataFrames.

Order: X-B and X-C first (probes, seconds each), then D2 from the memo, then X-A, X-E, X-D.

## 5. Sources

- pandas: [`ExtensionArray`](https://pandas.pydata.org/docs/reference/api/pandas.api.extensions.ExtensionArray.html): required methods, and "when performance is a concern, we highly recommend overriding" `factorize`/`_values_for_factorize` and `argsort`/`_values_for_argsort`.
- Arrow: [C++ compute](https://arrow.apache.org/docs/cpp/compute.html): a function "is implemented by one or several kernels, depending on the concrete input types"; [`arrow_row`](https://docs.rs/arrow-row/latest/arrow_row/): a row format for multi-column sorting and grouping.
- Polars: [`Series`](https://docs.rs/polars-core/latest/polars_core/series/struct.Series.html): `is_sorted_flag`, `i64()` ("Unpack to ChunkedArray of dtype DataType::Int64").
- Swift: [SE-0352](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md); [Protocols](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Protocols.md) (`is`, `as?`, `static` requirements, initializer requirements); TabularData's [`AnyColumn`](https://developer.apple.com/documentation/tabulardata/anycolumn) and `assumingType(_:)`.
- Rust: [`FromStr`](https://doc.rust-lang.org/std/str/trait.FromStr.html); [trait upcasting, Rust 1.86](https://blog.rust-lang.org/2025/04/03/Rust-1.86.0/).
- Go: [`io.Copy`](https://pkg.go.dev/io#Copy).
