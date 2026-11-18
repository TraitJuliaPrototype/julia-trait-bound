Review (2026-10-28, an Opus agent): annotations and escape hatches in the ports

# Annotations and escape hatches in the ports

## The request

The user (2026-10-28):

> "A number of times when watching your work, it came up that you solved a performance problem by an explicit annotation. Often in Julia code the more principled solution is to fix the inference rather than hard code an annotation. Likewise, marking something nospecialize should be an escape hatch in my opinion. Please send out an opus agent to check where the ports are using workarounds that might warrant a more careful redesign, and save the list of occurences like that in a new markdown."

The coordinator added one question for each finding: would TraitWorld's fully typed mode ([traits §11.3](../reference/traits.md#113-fully-typed-mode)) have caught the root cause early?

## What was read, and the builds

- **Forks** (`forks/`, main, 5c23482): only the forks' changes against upstream e926dbb (`git diff e926dbb HEAD -- DataFrames/src CSV/src CSV/ext Tables/src Tables/ext`).
- **SciML port** (`TraitDifferentialEquations/`, branch w34, 972b330): `src/` and `lib/*`.
- **Makie port** (`TraitMakie/`, main, e52472c): `src/` and `compat/MakieCompat/src`. Not `src/upstream/` (upstream's files, unchanged) and not `baselines/` (plain controls).
- **TraitWorld** (main, a515e3a): the commits made for the ports.
- **Checks run** (julia-1.13 at a4e9ad5da9, TraitWorld a515e3a, product setting, one process each, under the review lock):
  - inference (`Core.Compiler.return_type`) and `fully_typed` reports at the annotated sites;
  - scratch copies of `joinkeys` (without its assertions; with a `Vector{Dynamic{Column}}`) and of `_group_rows!`'s counter (captured variable against `Ref`);
  - the member check of a `Column` copy without its two assertions;
  - plain and facts callers of a bounded function opened with `compiled_for`, with and without a declared result (TraitMakie);
  - specializations of the `Kept{Callable}` constructors per closure (TDE).
  - Scripts and logs: `$TMPDIR/audit/` of the session (not committed; this review quotes the results). The forks' `env_forks` and TraitMakie's manifest are stale against TraitWorld (LinearAlgebra, a dependency since 202ac74), so the checks ran in scratch copies of the environments, resolved offline.

## Classes and columns

- **(A)** inference fixable in the port's own code.
- **(B)** a weak point of the design or of TraitWorld: the device makes up for something the design should provide.
- **(C)** a real dynamic boundary, where the device is the right tool.
- **(D)** a limitation of Julia or Base outside our control.

The column **fully typed** answers: would `@enforce_fully_typed` or `@warn_not_fully_typed` (code in a trait module), or `fully_typed(f, argtypes)` (plain code), have reported the root cause?
- "checked" marks an answer from a run. The other answers are read from the code and from [traits §11.3](../reference/traits.md#113-fully-typed-mode).
- Two rules decide most answers: an operation on a `Dynamic` value counts as declared, not as a fault; compile time is not looked at.

## Summary

43 occurrences: 15 (A), 12 (B), 15 (C), 1 (D).

| | A | B | C | D |
|---|---|---|---|---|
| Forks | 10 | 4 | 3 | 1 |
| SciML (TDE) | 2 | 6 | 8 | 0 |
| Makie | 3 | 0 | 1 | 0 |
| TraitWorld | 0 | 2 | 3 | 0 |

Six assertions and comments are stale today: TraitWorld 38a3abf declares a bounded function's plain result on its entry, so plain inference sees it (F2, F10, F11, F12, F13, S13).

The findings that most warrant a redesign:
1. **Who decides where a column is opened** (F9; also M1). Kernels need code per column type, but a stored `Dynamic` value keeps its attribute ([traits §6.5](../reference/traits.md#65-values-carry)). So every caller of a kernel writes `compiled_for`; the callee cannot say it. E-214: the sorts 742 → 314 ms with the casts.
2. **Facts mode types every run-time site `Any`** ([facts §1](../reference/facts.md)). Plain code reached from a worker loses plain inference's answers. The CSV fork removed upstream's `@nospecializeinfer` from the reader, wrapped a type in `Val` and asserted seven stage results (F16). The reader is a worker only because `CSV.File` enters `ColumnParsers.readfile`, which the lean-core memo §3.1 calls not needed.
3. **Declared results do not reach the caller** in three forms: an undeclared bounded result (M1: 17 call-site assertions in PlotCore, checked); a kept-form result such as `tocolumn`'s `Dynamic{Column}`, `Any` even at `Vector{Int}` (F3, checked); an operation called on a plain value of unknown type (M2, checked). [Traits §7.6](../reference/traits.md#76-equality-and-inference) tells users to assert where declaring the result now suffices.
4. **The member check asks inference to prove a contract the call already asserts** (F5, F17). The family over every `AbstractVector` needs `length(c)::Int` and `c[i]::eltype(c)`: without them DataFrames' `RepeatedVector` is refused (checked).
5. **Keeping a function** (S5–S8, F7): the kept-value constructors compile per closure (checked: 16 → 20 specializations for three closures), so TDE wraps them in `@nospecializeinfer`. A `Compiled` function at a struct parameter loses its attribute when read. Changing a function while keeping its attribute takes TraitWorld's internals. A function kept before its signature is known has no form, so `ByRow{F}` and TDE's `DiscreteCallback` carry `Any` or the closure's type.

## The forks (forks 5c23482)

| ID | Where | Device | Why it is there | Root cause | Class | Fully typed | Proposal |
|---|---|---|---|---|---|---|---|
| F1 | `DataFrames/src/join/core.jl:213–214` (5c23482) | `nl = length(left_cols[1])::Int`, same for `nr` | Hot: the fold's loops over rows. Without it every row's arithmetic dispatched: 443 → 25 ms (E-224, `logs/m8/split.log`). | `left_cols` is `collect(eachcol(...))`, a `Vector{AbstractVector}` (`eltype(DataFrameColumns) = AbstractVector`). `length(::AbstractVector)` infers `Any` (checked). Without the assertions the whole result is `Tuple{Any, Any, Bool}` (checked). | A | Yes, checked: `length(AbstractVector)` at core.jl:213 and :214. | Pass the lengths: `preprocess_columns` already computes `left_len`, `right_len`. Or take the frame's `Vector{Dynamic{Column}}` (`_dcolumns`) and `nrows`: that version infers `Tuple{Vector{Int}, Vector{Int}, Bool}` with no assertion (checked). |
| F2 | `join/core.jl:223` | `jointcodes!(…)::Tuple{Int, Bool}` | Same fold (E-224). | Redundant in plain code: `jointcodes!(::Vector{Int}, ::Vector{Int}, ::Any, ::Any, ::Bool)` infers `Tuple{Int, Bool}` (checked; the entry carries the declared result since TraitWorld 38a3abf). Needed only where the code is compiled by facts, where the call is a run-time site. | A | Yes, checked: `jointcodes!(…, Any, Any, Bool)` and `tocolumn(Any)` at core.jl:223. | Remove with F1's fix. |
| F3 | `Tables/src/ColumnCore.jl:73`; the sites that assert its result: `DataFrames/src/other/kernels.jl:804`, `DataFrames/src/dataframe/dataframe.jl:450`, `CSV/src/ColumnParsers.jl:177` | `tocolumn(c) = Dynamic{Column}(c)::Dynamic{Column}`, and `tocolumn(x)::Dynamic{Column}` at callers | Each column of a `SubDataFrame` or a `CSV.File` as a `Dynamic{Column}` (`TableSource`'s `tablecolumn`, whose declared result the member check needs). | `tocolumn` has no declared result, only a body assertion. And [lowering §8.1](../reference/lowering.md#81-the-rewrite) puts a declared result on the entry only for a plain type without a trait. `tocolumn` infers `Any` at `Any`, `AbstractVector` and even `Vector{Int}` (checked). | B | Yes: `tocolumn(Any)` reported (checked, in F2's run). | Declare `tocolumn(...)::Dynamic{Column}`, and put a kept-form result (`Dynamic{X}`, `Compiled{X}`, `Kept{X}`, concrete types) on the entry too. Open-issue candidate 3. |
| F4 | `join/core.jl:223, 256, 260, 267, 271`; `kernels.jl:276, 320, 600` | `tocolumn(...)` (a `Dynamic`) into `jointcodes!`, `innerrows`, `semirows`; docstrings say "a worker per pair of column types" | M8 (E-224). | The kernels run at the erased key, compiled per pair of cell types: `Column{Int64} at Dynamic`, `Column{String} at Dynamic` (checked). Cells are read through the `Dynamic` split. The docstrings, the README and E-224's "about 300 ms per new pair of column types" describe per-column-type workers. The memo §3.1 says to open the join columns with `compiled_for`. | A | No: `Dynamic` counts as declared. With a `Vector{Dynamic{Column}}` the entry's dispatch on the cell type is reported as 8 run-time sites (checked), noise (W4). | Decide which: open them (`compiled_for`, as the memo), or keep `Dynamic` and correct the docstrings, the README and E-224's row. Steady joins are within 1.2× of upstream either way (E-224). |
| F5 | `Tables/src/ColumnCore.jl:48–49` (30f77b3; first 90b653a) | `nrows(c) = length(c)::Int`, `cell(c, i) = (@inbounds c[...])::eltype(c)` | The family `@implement Column A where {A <: AbstractVector}`: a vector that keeps its data at an abstract type infers neither. | The member check ([traits §4.9](../reference/traits.md#49-checks-at-the-declaration), §4.7) wants each method's inferred result to meet the declared type. Without the assertions `DataFrames.RepeatedVector{Int64}` (`parent::AbstractVector{T}`) is refused: "`xnrows` … returns `Any`, declared `Int64`" (checked). The call on a trait object asserts the declared result anyway ([traits §3.1](../reference/traits.md#31-operations)). | B | No: the member check reports it, at the member's first use. | Open-issue candidate 4. |
| F7 | `Tables/src/utils.jl:237–238` (576eeaa) | `_byrow(@nospecialize(fun), a)` | M6 (E-216): `ByRow(f)` into the `Column` kernel, the function a `Callable` at the cells' types, so no plain code here compiles per closure. | The device works locally, but the gain is spent before it: `ByRow{F}` carries the closure's type, so the plain `ByRow` method and DataFrames' mini-language compile per closure (E-216: the kernel 6.1–6.8 ms against `map`'s 18 ms; a whole `transform` 24–25 ms against upstream's 25 ms). | C (root B) | No: compile time. | The device is right at this boundary. The root is open-issue candidate 5 (a function kept before its signature is known). |
| F8 | `DataFrames/src/groupeddataframe/utils.jl:571` (ff89a63) | `ng = Ref(0)` for a counter a closure updates | Hot: groupby 28 → 3.6 ms (E-214). | Julia boxes a captured variable that the closure assigns (`Core.Box`, JuliaLang#15276), and with it the function's locals. | D | Yes, checked: the boxed copy reports `+(Any, Int64)` and `convert(Type{Int64}, Any)`; the `Ref` copy is fully typed. On the current `_group_rows!` `fully_typed` failed with an `AssertionError` (W4). | Simpler without a closure: `g = get(d, key, 0); g == 0 && (g = d[key] = (n += 1))`, as `firstcodes!` does. |
| F9 | `abstractdataframe.jl:745`, `sort.jl:634`, `splitapplycombine.jl:241`, `groupeddataframe/utils.jl:521, 565`, `CSV/src/write.jl:721`, `ColumnParsers.jl:168` (ff89a63, 78327b5) | `compiled_for(...)` at each kernel's call site, comment "opened (E-214)" | Kernels with a loop per cell want code per column type. E-214: the sorts 742 → 314 ms, `groupby` and `describe` likewise. | The frame stores `Dynamic{Column}`. A kept value keeps its attribute at every bound ([traits §6.5](../reference/traits.md#65-values-carry)); a position attribute `c::Compiled{Column}` applies only to plain values. So the callee, which knows its cost model, cannot open a column; every caller must. | B | No: a `Dynamic` operation counts as declared. | Open-issue candidate 1. |
| F10 | `groupeddataframe/utils.jl:521, 565` | Typed comprehensions `Union{Nothing, Tuple{…}}[refcodes(compiled_for(c), …) …]`, `Int[firstcodes!(…) …]` | Keep the codes typed after a call that opens a `Dynamic`. | `refcodes` and `firstcodes!` declare plain results, which their entries carry (38a3abf). The same mechanism checked in TraitMakie: a declared result through `compiled_for` infers in plain and facts callers. | A | No. | Harmless; may go. |
| F11 | `kernels.jl:788` (in the worker `fromsource`) | `vector(tablecolumn(t, i)::Dynamic{Column})::AbstractVector` | M5 (8c6366a). | An operation on a trait object or a kept value asserts its declared result already: `vector(::Dynamic{Column})` infers `AbstractVector` (checked). | A | No. | Remove. |
| F12 | `DataFrames/src/other/tables.jl:59` (8c6366a) | `fromsource(...)::DataFrame`, comment "an entry at a type that may not conform: its result is not inferred" | `DataFrame(::TableSource)`. | Stale since 38a3abf: `fromsource(::Any, ::Bool)` infers `DataFrame` (checked). | A | No. | Remove the assertion and the comment. |
| F13 | `dataframe.jl:464–465` | `vector(c.cols[i])::AbstractVector` in `ColumnVectors` | The adapter that gives upstream's code `_columns(df)[i]`. | Redundant: `vector(::Dynamic{Column})` infers `AbstractVector` (checked). | A | No. | Remove. |
| F14 | `kernels.jl:45` | `celltype(c) = eltype(emptycells(c, 0))` | Names `T` of `Column{T}` in a worker. | `c::Column{T} where {T}` names it ([lowering §8.1](../reference/lowering.md#81-the-rewrite), `_trait_param`), a constant per key. | A | No. | `where {T}` on the kernels that need `T`. |
| F15 | `DataFrames/src/abstractdataframe/show.jl:381–412` (06e8b97) | Render into an `IOBuffer` wrapped in an `IOContext`, then copy | PrettyTables compiled once, not per kind of `io` (first `show`). | PrettyTables specializes on the `IO` type. | C | No: compile time. | Keep. The principled place is PrettyTables. |
| F16 | `CSV/src/api.jl:1110, 1113, 1246, 1285, 1295–1303` (results asserted); `api.jl:1195, 1249` and `ColumnParsers.jl:45` (`Val(stringtype)`); upstream's `@nospecializeinfer` removed from `_probedelim`, `_prepare`, `_file`, `_filefromprepared` (`api.jl`), `makevalueopts`, `settlecolumns`, `_parse` (`core.jl`) (06e8b97, "read path concrete under the policy") | Assertions, `Val`, removed escape hatches | M5: `CSV.File(path)` enters the worker `ColumnParsers.readfile` (`CSVSource`), so the whole reader is compiled by facts. | In facts code a call at non-fact argument types is a run-time site typed `Any` ([facts §1, §4](../reference/facts.md)), where plain inference would give the methods' union. A type passed as a value (`stringtype::DataType`) is such a site. Upstream's `@nospecializeinfer` makes arguments abstract, so in facts code its calls become run-time sites. The memo ([lean core §3.1](../plans/2026-10-28-dataframes-lean-core.md)) says `CSVSource` is not needed: the reader's entry stays plain. | B (and A) | Yes: it reports these sites. The assertions keep `Any` from spreading; the sites stay. | (A) Drop `CSVSource`/`readfile`, restore upstream's reader with its `@nospecializeinfer`, enter trait code at `parsecells!` only. (B) Open-issue candidate 2. First-call path: without the escape hatches the reader compiles per argument-type combination. |
| F17 | `CSV/ext/CSVInlineStringsExt.jl:76` | `_rowcell(...)::Union{InlineString, String}` | The extension failed to precompile: `rowtext` inferred `Any` against its declared `AbstractString` (README, "Test status"). | The auto width picks a type from a value (`_fitwidth(n)`): instability by design, as upstream. | C | Partly: the member check reports it, fully typed mode would report `_inl(::DataType, …)`. | Keep. The demand comes from F5's rule. |
| F18 | `CSV/src/ColumnParsers.jl:20–26` | `foreach(_ -> gensym(), 1:4096)`, "WORKAROUND" | Two family registries got one gensym name across precompile processes. | TraitWorld now keys `_family_registry` by the module too (`implement.jl:877`). | A | No (not inference). | Remove after a precompile check. |
| F19 | `CSV/src/write.jl:721` | `compiled_for(Tables.ColumnCore.tocolumn(col))` | M7 (E-217). | A `Dynamic` made only to be opened; `col` is a plain `AbstractVector`. | A | No. | `compiled_for(col)`. |

## The SciML port (TraitDifferentialEquations w34, 972b330)

| ID | Where | Device | Why it is there | Root cause | Class | Fully typed | Proposal |
|---|---|---|---|---|---|---|---|
| S1 | `src/TraitDifferentialEquations.jl:30–31` | `Base.@nospecializeinfer _cbs(@nospecialize(cb))`, `Any[...]` | The user's callbacks as given, before the problem's types are known. | A heterogeneous list of user values. | C | Yes (by design; cold). | Keep. |
| S2 | `src/TraitDifferentialEquations.jl:49–53` | `Base.@nospecializeinfer solve(@nospecialize(prob), @nospecialize(alg); …)`, the barrier `_solve` | A caller's code does not infer the solver again; one barrier per problem type (SciML's front end). | The plain API boundary. | C | Yes, by design. | Keep. |
| S3 | `lib/ODECore/src/core.jl:830` | `Base.@nospecializeinfer solve_ode(@nospecialize(prob), …)` in a trait module | The outer layer (W-63), compiled once. | In facts code each use of `prob` (`core_problem(prob)`, `prob.u0`, `prob.p`) is a run-time site; one per solve. | C | Yes: several sites, intended. | Keep, cold. A bound `prob::Dynamic{ODEProblemTrait}` would say the same in the design's terms. |
| S4 | `lib/ODECore/src/core.jl:209–213` | `UserFunction(@nospecialize(f))`, field `f::Any` | No constructor compiled per function. | Hides a function's type on purpose. | C | Partly: reading `fplain.f` is a site. | Keep; see S5. |
| S5 | `lib/ODECore/src/core.jl:337–346` | `DiscreteCallback`/`ContinuousCallback`: fields `::Any`, `Base.@nospecializeinfer` constructors | The functions arrive before the problem's types, so before their signature is known. | No kept form for a function whose signature is fixed later. The same need as F7's `ByRow{F}`. | B | No: compile time. | Open-issue candidate 5. |
| S6 | `lib/ODECore/src/core.jl:367` | `Base.@nospecializeinfer _keep_fn(::Type{K}, @nospecialize(f)) = K(f)::K` | A new callback compiles none of the library's code. | TraitWorld's `Kept{X}(x)` is `@inline` and specialized per value type (`TraitWorld/src/core.jl:668`). Three closures add 4 specializations to the `Kept{Callable}` constructors, 16 → 20 (checked). | B | No: compile time. | Open-issue candidate 6. |
| S7 | `lib/ODECore/src/core.jl:316–321` | `_kept(f::Dynamic) = f; _kept(f) = compiled_for(f)`, and `F <: Dynamic` tests | Pass a problem's kept functions on to `CoreProblem` with their attribute. | A `Compiled` function at a struct parameter is stored as the function itself; read back, it is a plain value ([traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)), so the next bound applies `Callable`'s default, `Dynamic`. [Traits §6.5](../reference/traits.md#65-values-carry) says storage keeps the attribute. | B | No. | Open-issue candidate 7. |
| S8 | `lib/ODECore/src/frontend.jl:66–75`; `core.jl:399–400` | `_partial`, `_uncast`: `f isa TraitWorld.CompiledFor`, `getfield(f, :x)`, `TraitWorld._callable_fn` | Partially evaluate a user's function on the parameters, keeping its cast or attribute. | No public operation changes a function while keeping its attribute; the port reads TraitWorld's internal types. | B | No. | Open-issue candidate 8. |
| S9 | `core.jl:250, 254, 266, 298, 302`; `lib/TraitRodas/src/rodas5.jl:69` | `(prob.f(du, u, t)::Nothing; nothing)` | Hot: once per step. Keeps the solver typed after the call. | Under `Compiled` the field is the function itself, so the call is a plain call, not `Callable`'s checked call ([traits §7.5](../reference/traits.md#75-functions-kept)). Under `Dynamic` the call already asserts `Nothing`. | C | No. | Keep; it costs nothing. A note in traits §7.4 that the field is a plain call would help. |
| S10 | `lib/TraitRodas/src/rodas5.jl:212` | `rodas5_run(...)::ODESolution{Float64}`, "a barrier per N" | The dual chunk `N` is a value from the problem's size. | A run-time value becomes a type parameter: a function barrier. | C | Yes: one site, intended. | Keep. |
| S11 | `rodas5.jl:81` | `Base.@nospecializeinfer dual_jacobian(@nospecialize(f), n, ::Val{N})` | No code per function when the function is entered at the duals. | The struct's bound decides the form. | C | No. | Keep. |
| S12 | `core.jl:598` and the `callbacks::Vector{Any}` it forces (`core.jl:476–495`, `rodas5.jl:206`, `TraitImplicit.jl:25`) | `Vector{Any}` of adapted callbacks, sorted again by `conforms` per callback | `ODEAlgorithm`'s operation `solve_core`. | An operation's declared types name only the trait's parameters and `Self` ([traits §3.1](../reference/traits.md#31-operations)); `CoreProblem{T}`'s `T` cannot type the callbacks. | B | Partly: the `conforms` calls are sites. Cold. | Open-issue candidate 9. |
| S13 | `core.jl:557–559` (comment) | A helper over `Dynamic{IndexProvider}` avoided: "whose entry plain inference sees returning `Any`" | Move 4 (E-160). | Stale since 38a3abf: a bounded helper with a declared `Union{Nothing, Int}` infers it from a plain caller (checked; undeclared: `Any`). | A | No. | Correct the comment; the helper is fine now. |
| S14 | `core.jl:430, 432` | `i.sv::Dynamic{StepView{U,T}}` | Drop `Nothing` from the field's `Union`. | Ordinary Julia. | A | No. | Keep, or initialise `sv` before the first callback. |
| S15 | `core.jl:379` | `Kept{Callback{U,T,P}}[]`, comment "`Callback{U,T,P}[]` is not taken as `Kept{…}` here (E-158 finding)" | Typed vectors of kept callbacks. | The body rewrite (`_dyn_body`, [lowering §13.1](../reference/lowering.md#131-a-users-container-crossing-by-its-bound), L-6) does not rewrite a trait applied to `where` variables. | B | No. | Open-issue candidate 10 (or a lowering deviation row). |
| S16 | `lib/TraitIndexing/src/TraitIndexing.jl:35` | `@noinline _noname(...) = throw(...)` | The error path outlined. | Standard Julia. | C | No. | Keep. |

## The Makie port (TraitMakie e52472c)

| ID | Where | Device | Why it is there | Root cause | Class | Fully typed | Proposal |
|---|---|---|---|---|---|---|---|
| M1 | `src/PlotCore.jl:316–339, 440–456` (17 sites) | `limits(compiled_for(p.pos))::NTuple{4,Float64}`, `pixels(...)::Tuple{Vector{Float64},Vector{Float64}}`, `draw…(...)::Nothing`, `steppoints(...)::Matrix{Float64}`, `binned`, `bandoutline`; comment "opening a dynamic value at a bound selects the worker by dispatch: the result is asserted here" | Every render; the `Plot` implementations' member check needs the declared result inferred. | The bounded kernels (`limits`, `pixels`, …, `PlotCore.jl:205–425`) declare no result. With a declared result, a call through `compiled_for` infers it, plain and facts, at `Kept{Positions}` and `Dynamic{Positions}` (checked); without, `Any`. [Traits §7.6](../reference/traits.md#76-equality-and-inference) says "Assert it". | A | Partly: the result is `Any`, but the report is dominated by noise from the table's miss path (W4, checked: 26 sites). | Declare the kernels' results; drop the 17 assertions. Rewrite traits §7.6 (open-issue candidate 3). Also F9's question: every plot opens every field. |
| M2 | `compat/MakieCompat/src/MakieCompat.jl:280` | `PC.datalimits(q)::NTuple{4,Float64}` | E-223: the member check refused the hand-over's `datalimits` once children held `Vector{Any}` primitives. | `Child.prims::Vector{Any}` (`MakieCompat.jl:98`). `datalimits` is an operation, with 11 methods: at `Any` it infers `Any`, at `Kept{Plot}` `NTuple{4, Float64}` (checked). | A | Yes: `datalimits(::Any)` is a run-time site. | `prims::Vector{Kept{PC.Plot}}` (or `Dynamic`). The general point (an operation's result at a value of unknown type) is in candidate 3. |
| M3 | `MakieCompat.jl:279, 287` | `(c::Child)` on items of `getfield(p, :children)` | The loops over children. | The umbrella's `Plot{F, T}` keeps its children untyped. | A | Yes. | Type the children `Vector{Child}` in the layer. |
| M4 | `MakieCompat.jl:83–99, 128` | `Node.f::Any`, `last::Vector{Any}`, `attrs::Dict{Symbol, Any}`, `Any[resolve(…)]` | The old API's compute graph (`map!`). | Makie's compute graph is dynamic by nature; the layer mirrors it. First old-style PNG 67–80 ms (E-222). | C | Yes, intended. | Keep. |

## TraitWorld (main, a515e3a)

| ID | Where | Device | Why it is there | Root cause | Class | Fully typed | Proposal |
|---|---|---|---|---|---|---|---|
| W1 | `src/hooks.jl:115, 130` (a515e3a) | `@nospecialize(b::Builder)` on `_builder_records`, `_index_builder!` | The forks' import 1.74 → 1.40 s (E-225): compiled once, not per family member. | The functions reflect on the builder's type only; specializing bought nothing. The cost exists because 27 members fixed in the images are checked again at each load (E-213, W-84). | C | No: compile time. | Keep. The redesign is W-84 (do not redo at load what the image did). |
| W2 | `src/core.jl:218` (2215188) | `@inline function _family(@nospecialize(X))` | Folds where `X` is known, also in facts code. | In facts code a kind passed to a function that is not a closure is a run-time site ([facts §3](../reference/facts.md)). Inlining moves the type computation into the caller. | C | Yes, if it stops inlining. | Keep; it is fragile: a larger body stops folding silently. A test that the fold happens would guard it. |
| W3 | `src/core.jl:586–590` (e1d401b) | `invoke(Dynamic{S}, Tuple{Val{:checked}, Any}, …)::Dynamic{S}` in `_as_super` | A held value seen through its supertrait stays typed in facts code. | The held object is `Any`; a call with it is a run-time site. An `invoke` at the method's own signature is a fact. | C | No. | Keep: the principled form of "call exactly this method". |
| W4 | `src/untyped.jl:242–256`, `src/certificate.jl` | (tooling) `fully_typed` | — | Three findings of this review: (1) on `joinkeys` without assertions and on `_group_rows!`, `fully_typed` fails with `AssertionError` (`argextype called on Expr with head :call`); (2) a typed caller passing `Dynamic{Column}` to a `Dynamic{Column{T}} where T` kernel gets 8 sites in the entry (the dispatch on `T`); (3) a call through `compiled_for` on a kept value reports 26–30 sites, mostly the untyped table's miss path (`_pmiss`), locks and `Task` code (all checked). | B | — | Open-issue candidate 11. |
| W5 | `src/core.jl:668` | `@inline function Kept{X}(x)` (and `Dynamic{X}(x)`, `Compiled{X}(x)`) specialized per value type | Fold where the type is known. | Also compiled per closure where the value is a user's function from plain code: the root of S6. | B | No. | Open-issue candidate 6. |

38a3abf (a bounded function's plain declared result on its entry, found by E-160) is the principled fix of the pattern behind F2, F10, F11, F12, F13 and S13. Those assertions can go.

## Candidates for open issues

Each is written as the case, the rule or code that blocks it, and a proposal.

1. **Opening a stored `Dynamic` at the callee** (F9, M1).
   - *Case:* DataFrames' kernels (`refine!`, `colstats`, `refcodes`, `firstcodes!`, `aggregate`) and TraitMakie's drawing loops need code per key. The values arrive as stored `Dynamic` columns or kept fields. Every caller writes `compiled_for`; 9 sites in the forks, 17 in PlotCore. A caller that forgets pays 2× (E-214: sorts 742 against 314 ms).
   - *Blocked by:* [traits §6.5](../reference/traits.md#65-values-carry): a value keeps its attribute at every bound; a position attribute is a default for plain values only.
   - *Proposal:* let a bound say "open here": an attribute such as `c::Opened{Column}`, which opens a `Dynamic` or `Kept` value at the entry (one dispatch per call, then code per key). The callee knows its cost model (a per-cell loop); the caller does not. Values still carry their attribute everywhere else.
2. **Run-time sites in plain code reached from a worker** (F16).
   - *Case:* the CSV fork's reader is compiled by facts because `CSV.File` enters a worker. Every call at abstract types is typed `Any`; plain Julia would give the union of the methods' results. The port removed upstream's `@nospecializeinfer` (seven functions), wrapped a type in `Val`, asserted seven results.
   - *Blocked by:* [facts §1, §4](../reference/facts.md) (a run-time site is typed `Any`; a kind passed to a function is not a fact signature); [facts §6.2, the mode rule](../reference/facts.md#the-mode-rule) (neutral code reached from facts code is compiled by facts).
   - *Proposal:* (a) the porting rule: enter trait code at the kernels, keep plain front ends plain (the memo already says so for CSV). (b) In the compiler: at a run-time site whose matching methods all declare or infer one result type, split on the result (`r isa T ? typed path : generic path`), as union splitting does. Semantics stay; only an edge-free fold is avoided.
3. **Declared results that do not reach the caller** (F3, M1, M2).
   - *Case:* `tocolumn(::Vector{Int})` infers `Any`; four sites assert `::Dynamic{Column}`. PlotCore asserts 17 kernel results. MakieCompat asserts an operation's result on an untyped item.
   - *Blocked by:* [lowering §8.1](../reference/lowering.md#81-the-rewrite): only a plain declared result "no `where` variable, no trait" goes on the entry; an operation has no entry at `Any`; [traits §7.6](../reference/traits.md#76-equality-and-inference) tells users to assert.
   - *Proposal:* put a kept-form result (`Dynamic{X}` and the others: concrete types) on the entry as well. Rewrite traits §7.6: "declare the bounded function's result; a call through `compiled_for` then infers it" (checked true today for plain results). For operations on plain values of unknown type, the guidance: hold them as `Kept{X}`.
4. **The member check against the call's assertion** (F5, F17, M1's `datalimits`/`draw!`).
   - *Case:* `Column`'s family over every `AbstractVector` asserts `length(c)::Int` and `c[i]::eltype(c)`; without them `RepeatedVector` is refused (checked). The assertion repeats Base's contract and what each call on a trait object asserts already.
   - *Blocked by:* [traits §4.9](../reference/traits.md#49-checks-at-the-declaration), §4.7: each method's result must infer to the declared type.
   - *Proposal:* accept an inferred result that is wider than the declared one but not disjoint, and say so in a note at the member's first use; the call's assertion keeps the guarantee. Keep refusing a disjoint result. `@enforce_concrete_only`-style strictness stays available for traits that want proof.
5. **A function kept before its signature is known** (S5, F7).
   - *Case:* TDE's `DiscreteCallback(condition, affect!)` and Tables' `ByRow(f)` receive a function whose argument types are fixed later (the problem's types, the column's cells). They keep it as `Any` with `@nospecializeinfer` constructors, or as `ByRow{F}`, which compiles the plain pipeline per closure (E-216).
   - *Blocked by:* [traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature), §7.5: a kept function has a signature.
   - *Proposal:* a kept function without a signature (`Dynamic{Callable}`), entered at a signature at its first bound, compiled per signature there.
6. **Kept-value constructors compiled per value type** (S6, W5).
   - *Case:* `Kept{Callable{A, S}}(f)` compiles per closure from plain code (checked: 4 specializations for 3 closures). TDE wraps every keep in `@nospecializeinfer _keep_fn`.
   - *Blocked by:* `TraitWorld/src/core.jl:668` (`@inline function Kept{X}(x)`); traits §7 does not say what making a kept value compiles.
   - *Proposal:* making a `Dynamic` value, or a value of a type not of the trait world, compiles nothing per value type: the constructors' entry from plain code unspecialized, as an entry's trait positions are ([lowering §8.2](../reference/lowering.md#82-the-entry)). State it in traits §7.
7. **A struct parameter's `Compiled` value read back** (S7).
   - *Case:* `core_problem` re-casts each function with `compiled_for` unless `F <: Dynamic`.
   - *Blocked by:* [traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait) ("the struct's own methods read the field as a plain value") against [§6.5](../reference/traits.md#65-values-carry) ("storage keeps it").
   - *Proposal:* a value read from a field typed by a bounded parameter, passed on to a bound, keeps the attribute that the parameter records (not `Dynamic`: `Compiled`).
8. **Changing a function, keeping its attribute** (S8).
   - *Case:* `_partial` and `_uncast` read `TraitWorld.CompiledFor`, `WithDynamic`, `getfield(f, :x)`, `TraitWorld._callable_fn`.
   - *Blocked by:* traits §6.4 and §7 offer casts and constructors, no transform.
   - *Proposal:* a public `rewrap(g, f)`: `g` with `f`'s cast or kept form and attribute (or `Like` for functions).
9. **Operation types naming a type variable of another argument** (S12).
   - *Case:* `solve_core(a::ODEAlgorithm, m::CoreProblem, callbacks::Vector{Any}, …)` cannot say `Vector{Kept{StepCallback{Vector{T}, Float64}}}` for `m::CoreProblem{T}`.
   - *Blocked by:* [traits §3.1](../reference/traits.md#31-operations) (declared types name the trait's parameters and `Self`).
   - *Proposal:* allow `where` variables on an operation's declaration, fixed by its arguments, checked at the implementation like a parameter. Low priority: once per solve.
10. **`X{U, T, P}[]` in a trait module's body** (S15).
    - *Case:* `Callback{U, T, P}[]` is not rewritten to `Kept{…}[]`.
    - *Blocked by:* `_dyn_body` (`trait_module.jl`), within L-6.
    - *Proposal:* rewrite a trait applied to `where` variables as `Column[]` is; or a deviation row under L-6.
11. **`fully_typed` on trait-world code** (W4).
    - *Case:* see W4: a crash on two functions; the dispatch on a `Dynamic{X{T}}`'s `T` and the untyped table's miss path, locks and `Task` code reported as faults.
    - *Blocked by:* `TraitWorld/src/certificate.jl` counts only operations on `Dynamic` values as declared.
    - *Proposal:* count the entry's per-parameter dispatch and the table (`_pmiss` and what it calls) as declared sites; fix the `argextype` assertion; a test per case. Without this the guideline below cannot ask port authors to keep reports clean.

## For the porting guideline

**What the fully typed checks catch early.**
- A value read from an untyped container or field used in a hot loop (F1: `length(::AbstractVector)`; M2, M3).
- A captured variable boxed by a closure (F8: `+(Any, Int64)` reported; the `Ref` version clean).
- Plain code reached from a worker that loses inference at run-time sites (F16).
- An undeclared bounded result used after the call (M1, F3), where the report is not drowned in noise (W4).

**What they cannot catch.**
- Logic bugs, and documentation that says another thing than the code does (F4).
- Compile-time costs: code per closure, per `IO` type, per member at load (F7, F15, S6, W1).
- The cost of `Dynamic`: an operation on a `Dynamic` value counts as declared, so a kernel left unopened (F9) is clean.
- A member check's demand (F5, F17): that is the member check's report, not fully typed mode's.

**Recommendation for port authors.**
- Put `@warn_not_fully_typed` before each port's trait module while porting (`ColumnKernels`, `ColumnParsers`, `PlotCore`, `ODECore`); switch to `@enforce_fully_typed` for kernel modules once clean.
- Run `fully_typed(f, argtypes)` in the port's tests on each plain hot loop beside the kernels, at the types the port calls it with: DataFrames' `joinkeys` and `_group_rows!`, the `ColumnVectors` adapter, CSV's reader stages. Run it before adding an assertion: the report names the root cause; an assertion only hides it.
- Before writing `::T` after a call, declare the callee's result instead (a bounded function's declared plain result reaches every caller).
- Before writing `@nospecialize`, ask whether the value is a function or a type that crosses into trait code: then the bound's attribute or `Callable` decides, and the escape hatch is not needed.

**The gap.** The trait-module macros check only bounded functions in trait modules. A port's plain code (`joinkeys`, `_group_rows!`, the CSV reader, `ColumnVectors`, MakieCompat) is outside them. There `fully_typed` is the only check, and it runs only where someone calls it. Until W4's noise and crash are fixed, its reports on code that passes kept values need reading by hand.
