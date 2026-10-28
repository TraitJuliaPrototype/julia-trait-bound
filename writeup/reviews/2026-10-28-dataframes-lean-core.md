# Fresh-eye review of the design memo "DataFrames, CSV and Tables in the trait world" (W-79, 2026-10-28)

**Reviewer:** fresh eyes (Opus). **Date:** 2026-10-28.

**Reviewed:** `writeup/plans/2026-10-28-dataframes-lean-core.md`, revision 1, at design repository eb75003.

**Read:**
- the references: `reference/traits.md` §1, §3–§8 (all), §9, §10.1, §16–§17 (T-2, T-7, T-18, T-28, T-53, T-77); `reference/lowering.md` §5 (the erased key);
- `intro/porting.md` part 0 (0.1–0.6) and B1;
- `design/evidence.md` §1, §2, §3, §5 and the summary;
- `plans/2026-10-17-dataframes-traits-plan.md` §2, §6, §8; `plans/2026-10-27-lean-core-old-apis.md` (structure, §1.1, §10);
- `forks/README.md`; E-163's row in `record/experiments.md` and its README (`experiments/overnight-2026-10-21/README.md:90`); W-14, W-79 in `record/todo.md`; open issue 68; the decision on small unions (`record/decisions.md:119`);
- the code: `forks/Tables/src/ColumnCore.jl` (all), `forks/CSV/src/ColumnParsers.jl` (all), `forks/CSV/src/core.jl` (column types, 2506–2535, 4405–4470), `forks/CSV/src/api.jl` (1335–1365), `forks/CSV/Project.toml`, `forks/Tables/Project.toml`, `forks/DataFrames/src/other/kernels.jl` (1–120 and the call sites), `dataframe/dataframe.jl` (storage), `dataframe/insertion.jl:760–800`, `join/composer.jl:5–12, 340–380`, `subdataframe/subdataframe.jl:70–76, 175–176`; `TraitWorld/src/implement.jl:250–280` and its git history (fac437a);
- the primary sources the memo cites: pandas' "Extending pandas" page and `pandas/core/arrays/base.py`'s docstring; docs.rs for `arrow_array::Array` and `polars_core::series::Series`.

**Run:** nothing. No Julia (the machine is busy).

**Counts.** Blocking 3, Major 7, minor 10.

---

## Summary

The memo's frame is right. Columns, tables and cell types are the open sets. Pooling is a capability, not part of what every column does. A plain compatibility layer and an unchanged user API are the right shape. The control (upstream compiled by facts) belongs in front.

Three things in the sketch do not work under the references:
- the capability subtraits cannot be reached from the storage the memo chooses (B1);
- `Column` itself repeats E-163's mistake: two of its operations are ones not every member can do, including the memo's own views (B2);
- the user-function bounds are refused by §5.8 (B3).

The memo also narrows the column family to `Vector` and views of `Vector`. That leaves out the column type CSV 1.1.0 produces for strings by default (M1). It does not say where a column is opened, so "compiled per key" is not what its storage gives (M2). Several citations are wrong, the most important being the cause of E-163 (M5). The experiment order puts a cross-build comparison first (M6).

None of this changes the frame. Revision 2 should fix B1–B3 and M1–M2 before W-14 resumes.

---

## Blocking

### B1. The capability subtraits cannot be reached from `Dynamic{Column}` storage

- **Location:** memo §3.1 (lines 70–76, 85, 91: `groupcodes(c::Column)` "with a `PooledColumn` method"), §3.3 (line 105, `DataFrame.columns::Vector{Dynamic{Column}}`), §6 (line 142: trait casts "would help and are not needed").
- **What is wrong:**
  - A stored column is a `Dynamic{Column}`. It entered through `Column` only.
  - "A value is seen through the traits it entered with." A kept value of `X` at a bound of another trait `Y` is refused (`traits.md:856`). `PooledColumn` and `MutableColumn` are other traits.
  - A kept value from plain code "reaches the bounded method for its trait" (`traits.md:635`). So `groupcodes(c)` on a stored column takes the `Column` method. The `PooledColumn` method is never selected. `setcell!` is never reachable either.
  - Asking a kept value for a capability is a trait cast, Optional (`traits.md:914–923`; `intro/porting.md:137` says so in so many words).
  - TraitWorld today accepts such a call only through a deviation, T-53 (`traits.md:1549`: "the entry assembles `Y`'s view from the held object, a trait cast"). A design must not rest on a deviation.
- **So:** the pooled fast path of groupby and joins is dead code under the references. The memo's §6 claim that trait casts are not needed is false for this design.
- **Fix, one of:**
  - (a) **Capabilities as operations with defaults on `Column`**, as porting 0.2 states the pattern ("the library's fallback … as the trait's default operation", `intro/porting.md:135`). For example `groupcodes(c::Column)::Tuple{Vector{Int}, Int}` with a default that hashes cells, overridden by `PooledVector`'s and `CategoricalArray`'s implementations from DataAPI's reference pool. A default serves kept values (`traits.md:221`). This is also pandas' shape (m6). Caveat: a default that names `T` needs T-2 (`traits.md:1498`); the default can call an internal bounded function instead.
  - (b) **Plain storage, bounded kernels.** Keep upstream's `Vector{AbstractVector}`. The plain layer passes the stored vector to each kernel; it enters as a plain value at the bound, and dispatch selects `PooledColumn` over `Column` by the value's conformance (`traits.md:628`). `df.a === v` holds trivially, and no adapter is needed. This is the plan's own fallback R1 (`plans/2026-10-17-dataframes-traits-plan.md:239`).
  - (c) Kept tuples of traits per column (`Dynamic{(Column, PooledColumn)}`): Planned (`traits.md:338, 964`), and per-column trait sets vary. Not recommended.
  - Revision 2 should pick one and say why. (a) keeps the memo's storage. (b) is the smaller change to upstream.

### B2. `Column` asks what not every member can do: `take` and `emptylike` returning `Self`

- **Location:** memo §3.1, lines 66–67 and 83.
- **What is wrong:**
  - `take(c, rows)::Self` and `emptylike(c, n)::Self` require the result to be of the receiver's exact type.
  - For the memo's own view family (`SubArray{<:Any, 1, <:Vector}`, line 83), `c[rows]` is a `Vector`, and no `SubArray` of the same type can be made for new rows. The member check refuses the view at its first use, as it refused `Vector{Int64}` in E-163 (a method whose result does not infer to the declared type, `traits.md:516–520`, `:466`).
  - The same holds for any read-only or lazy column (a range with `copycols = false`, Arrow's memory-mapped columns): none can return a new value of its own type for arbitrary rows.
  - This is the memo's own lesson 5 ("a trait states only what every member does", line 10), broken in the core trait.
- **Fix:** declare the result by the trait, `take(c::Column, rows::Vector{Int})::Column` and `emptylike(c::Column, n::Int)::Column`. A trait-typed result is `Dynamic` and accepts any concrete conforming type (`traits.md:770`): a pooled column returns a `PooledVector`, a view a `Vector`. If a kernel needs the column's own kind, that is a capability (B1's route), not `Column`. D2 must include the view family, or it will find this the slow way.

### B3. The user-function bounds are refused by the references

- **Location:** memo §3.1, line 92: `apply(f::Callable{Tuple{Vector{T}}, S}, c::Column{T})`, `byrow(f::Callable{Tuple{T1, T2}, S}, a::Column{T1}, b::Column{T2})`.
- **What is wrong:**
  - "The argument types `A` are a constant type. A bound whose `A` names a method's `where` variables … is refused when the method is defined. Write one method per signature." (`traits.md:707`). §8.4 repeats it: `f::Callable{Tuple{T}, Bool}` "for the item type `T` of any collection cannot be written" (`traits.md:1154`). Both sketches name `T`, `T1`, `T2` in `A`.
  - The open result `S` is Planned (T-18, `traits.md:713, 1514`).
  - Passing `Vector{T}` (gathered cells) where upstream passes the column changes user-visible behaviour: `transform(df, :c => levels)` on a `CategoricalVector`, or any function that reads a pooled column's pool, sees a different value. The memo promises "names and behaviour as upstream's" (line 104).
  - The 2026-10-17 plan had the same sketch (`plan:137`); the forks never built it ("Not done: user functions as `Callable`s", `forks/README.md`).
- **So:** "one worker per cell-type signature, none per closure" is not expressible under the references, and §6's "nothing changes in the references" is false here too.
- **Fix:** state the gap as an open issue (a `Callable` whose argument types follow a bound's parameters), or keep the mini-language's user functions plain, compiled per closure as today (the plan's R5 fallback and D-c, `plan:243, 265`). Pass the column itself to column-wise functions, as upstream does. `ByRow` with a `Callable` can be measured later as its own experiment.

---

## Major

### M1. The column family leaves out columns the stack produces by default

- **Location:** memo §0 (line 16: "one line for an `AbstractVector` subtype with the usual methods"), §3.1 (lines 82–83), §4 risk 4 (line 127), D2 (line 136).
- **What is wrong:**
  - **CSV 1.1.0's default string column is not a `Vector`.** With `stringtype = DataString`, the default (`forks/CSV/src/api.jl:1185`), `_finishstrings` returns the parsed columns as they are (`api.jl:1339`); string columns stay `DataStrings.StringVector{DataString}` (`core.jl:2535`, `const DataStringVector = StringVector`). So `CSV.read(path, DataFrame)` stores them.
  - **Views of other parents.** A `SubDataFrame` column is `view(parentcol, rows)` for any parent column (`subdataframe/subdataframe.jl:175–176`): pooled, string vectors, categorical. Only views of `Vector` conform.
  - **`PooledVector` needs `Column` too,** by its own implementation, to implement the subtrait (`traits.md:303`). The sketch declares only `PooledColumn` for it (line 86).
  - Every such column falls to the compatibility layer, which copies it into a `Vector{T}` (line 99). That breaks `df.a === v`, changes `copycols = false`, costs a copy per read, and turns a pooled or string-vector column into a plain one.
  - **Who may implement for `StringVector`:** Tables (the trait's owner), in an extension with DataStrings as trigger, or DataStrings itself (`traits.md:1200–1202`). CSV owns neither and may not.
  - **"One line with the usual methods" is false.** `Column`'s operations are new functions of `ColumnCore` (`nrows`, `cell`, …). A user's `AbstractVector` subtype has no methods of them. The one-line form needs the type's own methods of the operations, defined first (`traits.md:386–388`). One line works only if the operations are Base's functions (`Base.length`, `Base.getindex`), declared as qualified operations; then §10.1's rule for existing functions applies (`traits.md:1203`).
- **Fix:** list the column types the stack produces (D2 can print them from the suites): `Vector{T}` with and without `Missing`, `StringVector{DataString}`, `PooledVector`, `CategoricalArray`, views of each, ranges. Declare an implementation for each, or a family over `AbstractVector` whose operations every member can serve (the forks' `ColumnCore.jl:48`, without the pool operations). Say which copy, and that copying changes aliasing.

### M2. Where a column is opened is not said, and "compiled per key" is not what `Dynamic` gives

- **Location:** memo §1 (line 32), §3.1 (line 90: "bounded functions over `Column`, compiled per key"), D3 (line 137).
- **What is wrong:**
  - A `Dynamic{Column}` at a bare `Column` bound runs the erased key's worker, compiled once per tuple of parameter values (`lowering.md:262`). So `refine!` is compiled per cell type `T`, not per column type, and every `cell` call is a dispatch.
  - That dispatch costs about 1–3 ns within the split's four implementations and 2.5–18.5 ns beyond them (`evidence.md:86`, E-145). The stack has more than four column implementations (M1). A sort of 10⁶ rows makes about 4·10⁷ cell reads.
  - The shape the memo cites from Arrow and Polars (line 32: "one dynamic dispatch per column, typed code per element type inside") is `compiled_for(c)` at the kernel's entry, a function barrier (`traits.md:843`). Porting 0.4 says the same: "Loops over the data run `compiled_for` the data" (`intro/porting.md:180`). The memo never names `compiled_for`.
  - The forks call kernels with the `Dynamic{Column}` directly (`forks/DataFrames/src/abstractdataframe/sort.jl:634`, `refine!(perm, _dcolumn(df, cs[k]), revs[k])`). So their measured first calls (sort 0.007 s) may reflect a worker per cell type, not per column type.
- **Fix:** state the attribute per kernel. Per-cell loops (sort, groupby codes, joins, the parse loop) open the column with `compiled_for` at the entry. Cheap per-column work (show's `cellstrings`, `describe`'s gather) may stay `Dynamic` and share code per cell type. D3 measures both paths, and D4 counts workers for both.

### M3. §6 "nothing changes in the references" is not true

- **Location:** memo §6, line 142.
- **What the design needs that the references do not give:**
  - a capability reached from a kept value: trait casts, Optional (B1);
  - a `Callable` bound over a `where` variable, and open results (B3; T-18 Planned);
  - defaults that name the trait's parameter, if B1 (a) is taken (T-2, Planned);
  - an override of a family member from an extension, if `CellParser` is a family over `Vector` and InlineStrings' widths are overrides (M4; refused by `traits.md:470`, T-28).
- **A rule in code only:** E-163's refusal is "`op` at sig always throws (inferred `Union{}`): a fallback, not an implementation" (`TraitWorld/src/implement.jl:270–271`). No reference states it (no "always throws" in `reference/`). The memo's lesson 5 rests on it. It belongs in §4.9 as a rule, or in an open issue.
- **Fix:** replace §6 by a list: what the memo uses that is Implemented, what is Planned, and what needs a decision.

### M4. The `CellParser` sketch is not in the references' syntax, and its family would refuse InlineStrings' extension

- **Location:** memo §0 (line 9), §3.1 (line 94).
- **What is wrong:**
  - `parsecell!(c::Vector{T}, i, buf, pos, len, opts)::Bool` has no receiver. "The first argument is the value seen through the trait. Type it with the trait's name … or `Self`" (`traits.md:194`). A cell type is not a value. Lesson 4's own answer is that a vector stands for it; then the trait is the forks' `CSVColumn{T}` under a new name.
  - If `CellParser` is a family over every `Vector` (as `CSVColumn` was, `ColumnParsers.jl:63`), then `Vector{String15}` is already a member. A declaration in CSV's InlineStrings extension is an override of one member, which only the parameter type's owner may declare, in that package, not in an extension (`traits.md:470`). So the extension is refused.
  - "A registered prototype" (line 94) is not specified. A registry filled at load is state that depends on what is loaded.
  - The forks' `TextColumn` and `CSVSource` are dropped without a word (`forks/README.md`, "The traits").
- **Fix:** write `@trait CellParser{T} begin T = eltype(Self); parsecell!(c::CellParser, i::Int, …)::Bool end`. Implement it for spelled-out members (B1 item 5: "Spell out the members"), so the extension's `Vector{String15}` is a member of its own, not an override. Type detection's candidates are CSV's own, a closed set: a plain branch, no registry. A user's type enters as a value, `S[]` from `types =` or `stringtype =`. Say what becomes of `TextColumn` and `CSVSource`, and why.

### M5. The cited cause of E-163, and two claims about the forks, are wrong

- **Location:** memo lines 10, 41, 86, 127.
- **E-163's cause is not T-77.**
  - T-77 is a retired row (`traits.md:1572`). Its subject is the stakeholder rule at abstract declared arguments (`traits.md:468`), built in TraitWorld 399b512.
  - 399b512 is not an ancestor of TraitWorld bbfc130, the build E-163 ran (`git merge-base --is-ancestor` says no). So it cannot have caused the failure.
  - The cause E-163 records: "`levelcode` and `level` always throw there, so they are fallbacks, not implementations" (`experiments/overnight-2026-10-21/README.md:90`), the result check of `implement.jl:270–271`, now applied to family members. E-163's registry row says only that the forked CSV does not precompile (`record/experiments.md:248`).
  - The forks' `Column` was a family over every `AbstractVector`, with `nlevels(c) = 0` for a column without a pool (`ColumnCore.jl:48–67`). Only `levelcode` and `level` throw. The lesson stands; the citation does not.
- **"`TablesPooledArraysExt`, as the forks had" (line 86) is false.** The Tables fork has no extensions and no weak dependencies (`forks/Tables/Project.toml`; no `forks/Tables/ext`). The forks read reference pools through DataAPI inside the `AbstractVector` family. The extension was the 2026-10-17 plan's (`plan:82`), never built.
- **Fix:** cite `implement.jl:270–271` and E-163's README line 90; drop T-77; say the extension is new.

### M6. The experiment order and criteria

- **Location:** memo §5, lines 133–138.
- **D0 compares across builds.** It sets upstream under `all` on the current build against the forks' 1.35 s from julia-1.13 3b8085c222 and TraitWorld bed3782, on a machine at load 3.4–5.2 ("indicative", `evidence.md:155–160`). CLAUDE.md rule 5 asks a number to say its build. A ratio across builds says little.
- **D0 omits the product setting.** `all` is the test bed, "not a user setting" (`intro/porting.md:86`). Porting 0.1 asks for three runs: upstream, upstream wrapped as a trait module in the product setting, and upstream under `all` (`intro/porting.md:92`). The wrapped run is the user's control.
- **D2 must come first.** The forked CSV does not precompile (W-14). Until D2 passes, no fork number can be taken on the current build. After D2, D0 runs all three upstream settings and the forks on one build, in one session of runs.
- **D1 and D4 state no result that would change the design.** CLAUDE.md requires one for each experiment row. D1 could say: "if the tree beyond Tables, DataFrames and CSV costs more than X of `using`, a loading stub for PrettyTables' back ends (§3.4) is worth it". D4: "if a second schema with the same column types compiles any new worker, keys are leaking the schema".
- **D3's fallback re-introduces what it removes.** Per-pair workers are per tuple of two column types, a step back to upstream's per-tuple compilation. Name the alternative too: sorting is something a type does by itself (lesson 3). A `Vector{Int}` can sort by Base's own `sortperm` (radix) on the stored vector, as an operation with a comparison default.
- **D0's criterion decides only a claim's scope.** That is fine, but say so. The 1.5× matches the 2026-10-17 plan's falsification clause (`plan:252`); cite it.

### M7. What the kernels need beyond `Column`: joins, growth, the pool's types

- **Location:** memo §3.1 (lines 62–76), §3.3.
- **Outer joins need a column of the same kind at another element type.** Upstream builds the non-matching side with `similar(dv, Union{T, Missing}, dims)` filled with `missing` (`join/composer.jl:8–9, 345–346`). `emptylike(c, n)::Self` gives the same element type only. pandas' required `take` has `allow_fill` and `fill_value` for exactly this (m6).
- **Growth with widening.** `push!`, `pushfirst!`, `insert!` and `append!` grow the column, or replace it with a wider one when the value does not fit (`dataframe/insertion.jl:774–791`); `resize!` at `:327, :361`. `MutableColumn` has only `setcell!`.
- **Missing values** are handled by the small-union rule (`traits.md:1290`); nothing is missing there.
- **The pool's declared results are abstract.** `refs(c)::AbstractVector{R}` and `pool(c)::AbstractVector{T}` (lines 74–75) give each read in the hot pooled path a dispatch. The 2026-10-17 plan declared `Vector{R}` and `Vector{T}` (`plan:82`). Also, CategoricalArrays' reference pool is indexed from 0, with `missing` at 0; `pool(c)::AbstractVector{T}` should say its indexing.
- **Fix:** say which of these stay plain, through `vector(c)` and Base's methods (most can: they are not hot per key), and which are kernels. Declare `refs` and `pool` concretely, or give them a key the kernels can open.

---

## minor

- **m1. Subtrait parameters** (lines 70, 73). `MutableColumn{T} <: Column` names no `T` for `Column` and has no equation for its own `T`. §3.6's example repeats `T = eltype(Self)` in the subtrait (`traits.md:295–296`); a parameter not defined by the supertrait's fields is stated at the implementation (`traits.md:309`). `@implement (Column, MutableColumn) A where {A <: Vector}` states no `T`. Write `@trait MutableColumn{T} <: Column{T}` with the equation. `PooledColumn{T, R}` likewise; its `R` is stated per implementation, as a joint family (`traits.md:472–475`).
- **m2. "Every `Vector`, by its own methods"** (line 82). `Vector` has no methods of `ColumnCore`'s functions. Use a block (`traits.md:456–459`) or define them first (`traits.md:387`).
- **m3. `decision 18`** (line 88) is no identifier in the record. Cite `traits.md:1290` (§11) and `record/decisions.md:119`.
- **m4. Lesson 4's numbers** (line 40). 2.46–2.53 s is "CSV.jl's first read … with DataFrames in either order" (`TraitReport/README.md:66`). The attribution to the InlineStrings extension was not isolated from DataFrames' other loads, and it was "measured on the package prototype; not rerun on the compiler" (`evidence.md:268`). Say so.
- **m5. Lesson 8's numbers** (line 44). B1 item 11 gives no 0.34–0.42 s. The number is TraitReport's work under loads with StatsBase or Distributions, 344–417 ms (`evidence.md:143, 277`).
- **m6. Other systems** (lines 27–32).
  - pandas: accurate in substance. The interface lists required methods, `take` among them, and methods "to override for performance" (`unique`, `factorize`, `argsort`, `searchsorted`, `isin`, `value_counts`, `map`). "Some methods convert the ExtensionArray to an ndarray of Python objects, with `self.astype(object)`" (`pandas/core/arrays/base.py`, the class docstring). So pandas' capabilities are defaults on the base class, overridden per type: B1's fix (a), not subtraits with fallbacks in the kernels.
  - Arrow and Polars hold a **closed** set of physical types behind the dynamic trait. arrow-rs: "third-party types cannot extend the `DataType` enum" (docs.rs, `Array::data_type`, Safety). Polars dispatches on its `DataType` enum, with `Object` for foreign values. Their kernels can downcast and monomorphize because the set is closed. The open-set analogue is pandas alone. The memo's heading "how other systems hold an open set of column types" should say this.
- **m7. The Arrow URL** (line 29) returns 404. The page is `https://docs.rs/arrow-array/latest/arrow_array/array/trait.Array.html`.
- **m8. Name clash.** CSV 1.1.0 has an internal `struct PooledColumn{ELT} <: AbstractVector{ELT}` (`forks/CSV/src/core.jl:4413`). The trait `PooledColumn` collides with it in CSV's namespace. Rename one (`RefColumn`, as the 2026-10-17 plan had).
- **m9. Open sets, §0 against §1.** §0 names columns, tables and cell types; §1's table adds user functions, sources (paths, `IO`, bytes) and sinks. The writer (`@generated _preparewritecolumns` per tuple of column types, `plan:141`) is not addressed. Say whether it stays plain.
- **m10. Risks not listed:**
  - more than four column implementations, so `Dynamic` operations leave the split's fast path (`traits.md:905`; `evidence.md:86`);
  - CSV's parallel parse compiles workers from several tasks too, not only DataFrames' `groupby` and `combine` (risk 3);
  - a `SubDataFrame` per group (`combine` with a function of a `SubDataFrame`) makes a kept value per column per group, if storage stays `Dynamic`;
  - who may implement `Column` for `Vector{MyType}` when a user owns `MyType` only: §10.1 names "the trait's owner or the type's owner" (`traits.md:1200`), silent on a parameter's owner.

---

## Answers to the memo's questions (§7)

1. **The split into `Column`, `MutableColumn` and `PooledColumn`** is the right analysis, the wrong mechanism for kept columns. No kernel needs a capability as a bound. Each needs the capability's fast path when the column has it. With kept columns, a capability reaches a kernel only as an operation with a default on `Column` (B1 (a)), or as a bound when the column enters as a plain value (B1 (b)). `MutableColumn` can stay plain entirely: writes go through `vector(c)` in the plain layer (M7).
2. **`tablecolumn(t, i)::Dynamic{Column}`: keep it.** A trait-typed result is `Dynamic` anyway (`traits.md:770`). `Kept{Column}` would let the source decide the attribute. The choice belongs to the kernel's position (`intro/porting.md:177`), made by `compiled_for` at its entry (M2). `Kept` also costs 0.2–0.3 ns per operation more (`evidence.md:87`, E-149).
3. **Lazy sources need `Column` for their columns, not `TableSource`.** The compatibility layer converts the table once (names, columns by `getcolumn`). It copies only a column that does not conform. So Arrow's column types conforming to `Column` (Arrow's own implementation, or Tables' extension) keeps them memory-mapped. `TableSource` for Arrow tables is an optimization of the names and the column lookup, not needed at first.
4. **D0 is not the right first experiment.** D2 is: until the forked CSV precompiles, no fork number can be taken on the current build. Then D0 with four columns on one build: upstream; upstream wrapped as trait modules in the product setting; upstream under `all`; the forks. The 1.5× is the 2026-10-17 plan's clause and fine as a scope criterion. It decides the claim, not the design (M6).

## Answers to the review's questions

1. **Principled?** The open and closed sets are right (m9 aside). `Column{T}` does not yet ask only what every member can do: `take` and `emptylike` returning `Self` (B2). Capabilities per type need defaults, or plain entry, to be reachable (B1). Missing for the kernels: same kind at a wider element type (outer joins), growth with widening (`push!`), views of non-`Vector` parents, the default string column (M1, M7). Missing values are covered by the small-union rule.
2. **Syntax and rules.** Refused or not in the references: `Callable` over `where` variables (B3); `parsecell!` without a receiver (M4); a capability from a kept value (B1). Planned: open `Callable` results (T-18), defaults naming `T` (T-2), member overrides (T-28). Incomplete: subtrait parameters (m1); "by its own methods" (m2); `PooledVector`'s `Column` implementation (M1). Ownership: `Vector` and `SubArray` by Tables, the trait's owner, is allowed; `PooledVector` in Tables' extension with PooledArrays as trigger is allowed (`traits.md:1201–1202`); `StringVector` likewise, never by CSV (M1).
3. **Claims and numbers.** The control's numbers (561 → 2 lost, 3.3 → 0.5 s; `evidence.md:39–40`) and the forks' 1.35 against 10.7 s (`evidence.md:160`) are cited correctly. E-184's 1.50 → 0.51 s is correct (`plans/2026-10-27-lean-core-old-apis.md:449`). Wrong: E-163's cause (M5), the forks' extension (M5), `decision 18` (m3), the B1 item 11 number (m5). Overstated: lesson 4's attribution (m4).
4. **pandas, Arrow, Polars.** pandas accurate; Arrow and Polars accurate as described, but their sets are closed (m6); the Arrow URL is broken (m7).
5. **Experiment order.** D2 first, then D0 on one build with the product setting, then D3 and D4 with both attributes. D1 and D4 need criteria (M6).
6. **Missing risks:** M1's copies changing aliasing; M2's dispatch per cell beyond four implementations; m10's list; and the plan's R9 (late overrides refused) for any operation a package defines after a family covers its type.

## Recommendation

Revise to revision 2 before W-14 resumes. In order:
1. Choose B1's route, and with it the storage. Write `Column` so every member can do every operation (B2).
2. Take the user functions out of the trait core for now (B3), or open an issue for `Callable` over a bound's parameters.
3. List the column types the stack produces and how each conforms (M1). State where kernels open columns (M2).
4. Fix the citations (M5, m3–m7) and replace §6 with what is Implemented, Planned and to decide (M3).
5. Reorder the experiments: D2, then D0 on one build with the product setting, then D3 and D4 (M6).

The frame (four layers, open sets as traits, a plain compatibility layer, the user's API unchanged) needs no change.
