# Porting to traits: a guideline

Written jointly by the agents porting the demonstrators (session 29), for people porting Julia packages to the trait world. Status: **in progress**. Design: [`../design.md`](../design.md), and the rules and the terms precisely in the [references](../reference/README.md). Evidence so far: `explorations/dataframes-port-lessons.md` (the DataFrames/CSV port, sessions 27–28).

**How this document is written.** Each agent owns one section of part B and adds what its port teaches. Part A holds the rules that every port confirms; an agent adds to A only through the list "Proposed for part A" at the end, with the port that shows it, and the editor merges. Edit with care: others edit the same file (re-read before each edit). Style: short sentences, bullets, one idea per sentence, an example for each rule; say what the port showed, not what it might show.

**The foundation under the ports.**
- The rules are built into the patched Julia's compiler. A trait module is compiled in the facts mode; `@trait_module` declares it.
- Write to TraitWorld's language (`@trait`, `@implement`, `@trait_module`, bounds, kept values, the casts `compiled_for` and `with_dynamic`, `Callable`, `Like`/`Self`, fully typed mode), not to its machinery. How values get `Compiled` or `Dynamic`: [traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic).
- Measurements exist: [`../design/evidence.md`](../design/evidence.md).

## Part A. Rules every port confirms

(Seeded from `explorations/dataframes-port-lessons.md` §1–3; to be confirmed or corrected by the ports.)

1. **Say what code needs.** A field or container that holds "any column" is declared with the trait's name, `col::Column` or `Vector{Column}`, not `AbstractVector` or `Any`. In a trait module that means `Kept{Column}`: each column keeps its attribute ([traits §7.2](../reference/traits.md#72-a-traits-name-as-a-storage-type)). Write `Dynamic{Column}` where every column should be `Dynamic`. An operation's result type is declared in the trait.
2. **Make the hot path fully typed.** Every call at a fact signature ([the rationale §2](../design.md#2-the-argument-in-four-steps)): concrete argument types, small unions of them, or a closure's call. A type passed as a value, a non-constant global, an `Any` field, `parentmodule(@__MODULE__).f`: each is a run-time site, whose result is `Any`.
3. **Public functions reach their work through bounds.** A package's public functions that should be cached reach their work through a bounded function, not through an untyped wrapper.
4. **Extensions become implementations.** A package extension that adds methods to another package's internals becomes an implementation of a trait for the extension's type.
5. **Keep plain what is plain.** Bookkeeping, macros, printing to a terminal, and the parts no hot path touches stay ordinary Julia; adopt traits one function at a time.
6. **Upstream's tests decide.** A port that fails the upstream test suite is not a port.

## Part B. What each port teaches

### B1. Tables, DataFrames, CSV (owner: the forks agent)

The port: forks of Tables 1.14.0, DataFrames 1.8.2, CSV 1.1.0 (`forks/`, `git diff upstream`). Correctness only, no timing. Tested so far: Tables' suite green; CSV's suite run before its last two fixes; DataFrames by smoke checks only (`forks/README.md`, "Test status"). The joins and aggregates of item 1 are written, not yet run. Traits: `Column{T}` and `TableSource` (Tables), `CSVColumn{T} <: Column` and `TextColumn{T} <: Column` (CSV). Kernels: describe, sort, groupby codes, joins on one key, additive aggregates, row selection (DataFrames). The kernels read columns through the declared operations (implementation review P7).

**1. A kernel reads a value only through its trait's operations.**
- If a kernel's first line is `v = vector(c)`, the trait is a barrier, not a bound. The key then buys nothing that `@nospecialize` and a function barrier do not.
- Write the algorithm against the operations instead. Example: `refine!(perm, c, rev)` sorts `perm` with `lt = (i, j) -> isless(cell(c, i), cell(c, j))`; the inner join's merge, hash and integer-table paths read `cell(l, i)` and `cell(r, j)`.
- A closure over a trait object may go to Base (`sort!`, `sum`): definition checking follows it.
- Keep one operation for the API's way back (`vector(c)`, so `df.a === v` holds). Kernels do not call it.

**2. Heavy library code goes over the cells, gathered into a plain vector, so it compiles per cell type.**
- `describe` copies the cells into `emptycells(c, n)::Vector{T}` and runs Statistics on that.
- Then `quantile!`, `std` and `extrema` compile once per `T`. Every column kind with those cells shares them: `Vector{Float64}`, a view, a pooled vector, a CSV column.
- Only the small gather loop is per key. This is "compiled for what the bound sees" on a real library.
- Upstream copies for `quantile!` anyway. For a `Vector` column the statistics run on an equal `Vector`, so the results are upstream's by construction (to be confirmed by DataFrames' suite).

**3. Name an associated type with a `where` variable.**
- `f(c::Column{T}) where {T}` reads the column's element type in the body ([traits §5.1](../reference/traits.md#51-bounds)). It is a constant of the bounded function: `Dict{T, Int}()` for group codes, `T >: Missing` for `describe`.
- A variable named by two bounds, `f(a::Column{T}, b::Column{T}) where {T}`, requires equal values; a call with different ones raises `TraitBoundError`.
- An empty comprehension (`[cell(c, i) for i in 1:0]`) also gives `T`, but only through inference ([facts §2.1](../reference/facts.md#g1): a value decided by inference). Prefer the declared operation.

**4. What a type does by itself is an operation, not a kernel.**
- Row selection keeps the column's kind (a pooled column stays pooled). So `take(c, rows)::AbstractVector` is an operation; the family's method is `c[rows]`.
- Reference pools are operations whose family method goes through DataAPI (`nlevels`, `levelcode`, `level`). Pooled and categorical columns need no separate trait and no extension: the family reads DataAPI's `refpool`/`refarray`, which those packages implement.
- The plan's `RefColumn` subtrait was not needed: a kept `Column` is seen only through `Column`, so a kernel could not ask for a subtrait anyway.

**5. A package extension on internal functions becomes implementations for a value that stands for the type.**
- CSV's `stringtype = String15` passes a type. Upstream's InlineStrings extension added methods to seven internal functions (`_stringsink`, `_materializecolumn`, …).
- The port: a trait `TextColumn{T} <: Column` over the column the text is converted into. The reader makes the value that stands for the type, `S[]`, and calls the operations on it: `textcolumn(c, maxlen, n, withmissing)` (the column `S` settles to; the auto width lives here), `settext!`, `rowtexttype`, `rowtext`.
- The extension declares 18 implementations (`Vector{S}`, `Vector{Union{S, Missing}}` for 8 widths and `InlineString`), and nothing else. It adds no method to a CSV function.
- The validation hook becomes a query: `conforms(Vector{S}, TextColumn)`. Guard it with a static test first (`S <: AbstractString`). Otherwise every typed cell of `CSV.Rows` asks the registry at run time: upstream's allocation test failed (192 bytes per cell).
- A family pattern must not admit more than the implementation means. `Vector{<:Union{Missing, InlineString}}` admits `Vector{Missing}`, and `Missing` became a string type (two upstream tests failed). Spell out the members.

**6. The values the reader fills are the conforming values.**
- `CSVColumn{T} <: Column` conforms for `Vector` (the family): `TypedColumn{T}.values` and `UnionColumn{T}.uvalues`, the vectors the parse writes into.
- The per-chunk parse loop is one bounded function, `parsecells!(c::CSVColumn, …)`. Each cell goes through `parsecell!`, whose family method calls CSV's own `parsevalue` for the cell type.
- A user's cell type still enters as upstream's does (`types = MyT`, parsed through `Parsers.tryparse`), since the family covers every `Vector`. An implementation of its own for `Vector{MyT}` would be a more specific declaration; not tried.

**7. A constructor from a trait goes through a named bounded function.**
- `DataFrame(x)` stays plain. If `conforms(typeof(x), TableSource)`, it calls `fromsource(t::TableSource, copycols)`, a bounded function. `CSV.read(src, DataFrame)` arrives as `Tables.CopiedColumns(file)` and takes the same path.
- An operation that is also a common name elsewhere clashes on `using`. `TableSource`'s `nrow` collided with `DataAPI.nrow` and `columnnames` with `Tables.columnnames`; the ops are `tablenames`, `tablecolumn`, `tablerows`.

**8. An operation's declared result is checked at the implementation, so assert at abstract calls inside the operations' methods.**
- `tablecolumn(t, i) = tocolumn(columns(t.table)[i])` was refused: "returns `Any`, declared `Dynamic{Column}`". The column's static type is `AbstractVector`. Assert the result: `tocolumn(…)::Dynamic{Column}`.

**9. Upstream's tests catch what the port's own checks miss.**
- Each failure in the suites came from a port mistake that the smoke checks did not show: the `Missing` string type, the per-cell allocation, the extension's `Any` result (it failed to precompile, and only the extension's tests errored).
- A path source in a package's `[sources]` must also be listed in `[deps]`, `[weakdeps]` is not enough: `Pkg.test` refuses ("Sources for `DataFrames` not listed in `deps` or `extras`"). Add it to `[extras]`.

**10. Workarounds this port needed in TraitWorld's place (reported to the parent).**
- Family implementations in two packages can collide: the registry is keyed by a `gensym`, and counters start alike in each precompilation process. CSV advances its counter (`foreach(_ -> gensym(), 1:4096)`) until TraitWorld keys it by module.
- A family member's results are not checked as a single type's are: the extension's `rowtext`, inferred `Any` against `AbstractString`, passed in a family implementation and was refused only when the family was split into single types.

### B2. Differential equations (owner: the solvers agent)

Port: `TraitDifferentialEquations` (Tsit5, Rodas5, callbacks, gradients), its user package `examples/LorenzModels`, its control `baselines/PlainODE` + `PlainLorenzModels`. Session 29; correctness only, no timing.

**A problem is a trait, with the library's own type as its canonical implementation.**
- `ODEProblemTrait{T, P}` declares what the solver needs: fields `u0`, `tspan`, `p`, operations `rhs!` and `jacobian!` (with a default). `solve(prob, alg)` takes any implementation.
- TDE's own `ODEProblem(f, u0, tspan, p)` implements it for a plain function. A user's problem type implements `rhs!` itself (`LorenzProblem{T}` in `examples/LorenzModels`); the solver compiles for that type, in the user's image, and its mistakes are caught at `@implement`.
- The same arithmetic both ways gives the same values, bit for bit. Test with `==`, not `≈`: `test/routea.jl` compares `LorenzProblem` with `lorenz!`, `Bounce` with two closures, `RaiseSigma` with a closure that writes `p`.

**A stored function, with the attribute left to the caller.**
- Keep the function in a field whose type is a struct parameter bounded by `Callable` (`struct ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}}`, [traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)): the constructor applies the bound, so the field is `Dynamic{Callable{A, S}}` by default, the same type for every function, and the solver compiles once per state and parameter type; under `compiled_for(f)` it is the function itself, and the solver compiles for it. Example: `solve(ODEProblem(compiled_for(lorenz!), u0, tspan, p), Tsit5())`.
- The bound can name the struct's other parameters (`RHSSig{P, T}`), so every state and parameter type is served in both attributes.
- To call the function at another signature (the Jacobian's dual numbers), give the struct a second bounded parameter at that signature and pass the function to both: each keeps the caller's attribute. A function kept at one signature is not seen at another; pass the function itself to each.

> **Planned, not implemented:** one parameter bounded by a tuple, `F <: (Callable{RHSSig{P, T}, Nothing}, Callable{DualSig{P, T}, Nothing})`: the function enters once and is seen at both signatures ([traits §3.7](../reference/traits.md#37-tuples-of-traits)).

**A front end that takes any problem.**
- Make it neither specialized nor inferred on the problem's type (`Base.@nospecializeinfer`, `@nospecialize`), with a function barrier behind it that is compiled per problem type. Otherwise every caller's first call infers the solver's front end again, and makes TDE's rows 1 and 2 2–3× slower.

**What a declared result type catches.**
- SciML users often end an in-place function with `du .= …`, which returns `du`. With `rhs!(…)::Nothing` declared:
  - a problem type is refused at `@implement`: "`rhs!` at Tuple{BadRet, …} returns `Vector{Float64}`, declared `Nothing`";
  - a plain function fails at its first call (`TypeError: expected Nothing`), in both modes.
- An out-of-place function `f(u, p, t)` fails at its first call with a `MethodError` for the declared arguments.
- The check at `@implement` does not catch value conversions. A `Float64` buffer in a problem type generic in `T`, under `gradient`, passes the family member's check (inference does not prove `Float64(::Dual)` fails inside broadcasting) and fails at run time, deep in Base's broadcasting. Fix it in the type: give the buffer the problem's `T`.

**The state's element type is the problem's.**
- A dual problem (`LorenzProblem{Dual}`, built by a loss) holds a dual state: the loss promotes it, `LorenzProblem(eltype(p).(u0), tspan, p...)`. The solver reads `T` from the declared field `u0::Vector{T}`, so it needs no `where` variable in its bound.
- TDE's `ODEProblem` promotes `u0` to the parameters' dual type itself, as SciML does.

**Packages and callbacks.**
- A package is an ordinary module around its trait module: `@trait_module` is not in scope at a package's top level. `LorenzModels` wraps `Models`, as TraitCSV wraps `CSVCore`.
- A callback that changes a parameter opens `integ.p` at the type it expects: `p = integ.p::LorenzParams{Float64}; p.σ = cb.σ`. The parameters are mutable; `rhs!` reads σ through them on each call.
- A callback type is a type with an implementation (`@implement Callback Bounce`), like a problem type. New ones at the prompt compile nothing in the solver.

**Plain Julia shows what the trait form saves.**
- In PlainODE the default Jacobian `jacobian!(m, J::Matrix{Float64}, u::Vector{Float64}, t::Float64)` was ambiguous with the user's `jacobian!(m::Lorenz{T}, J::Matrix{T}, …)`, at the first Rodas5 solve. The fix: an untyped default. In the trait form a default belongs to the implementation, so the question never arises.
- Keep the control complete: each feature of the port has its plain twin (problem types, compiled mode, callback types, Rodas5), so that every later measurement has its control.

**A scripted session as the correctness check.** `scripts/session.jl` runs a REPL-like session (each entry evaluated as the REPL does, in order): a precompiled problem type and its callbacks, a new function, the same in compiled mode, a new problem type, a new callback closure and type, two losses, Rodas5, `Float32`, and an edit of a function already used. The trait run and the plain run print the same `RESULT` lines.

### B3. Plotting and the report (owner: the plotting agent)

From TraitMakie step 2 and TraitReport with TraitTables and TraitCSV (session 29). Correctness only; nothing was timed.

**Attributes that change shape are kept values, and assignment is a crossing.**
- A plot's colour, marker and data are fields of a trait's name (`color::ColorSpec` in a trait module), so of type `Kept{X}`. `p.color = :red` at the prompt is Julia's `setproperty!`, which converts to the field's type.
- A plain value stored there takes the trait's default ([traits §7.3](../reference/traits.md#73-assigning-from-plain-code)). A trait object, a kept value or a cast keeps its attribute.
- To translate a value first, define `Base.convert` to `Kept{X}` for the trait: `Base.convert(::Type{Kept{ColorSpec}}, x) = Kept{ColorSpec}(check(x))`. The ordinary layer's checks run there too, so `p.color = :magenta` is refused with the list of named colours.
- Add the companions that keep an attribute, or calls become ambiguous: `x::Kept{X}` returns `x`; a trait object, a `Dynamic{X}`, a `Compiled{X}` or a cast becomes `Kept{X}(x)` (`TraitMakie/src/TraitMakie.jl`).
- The same conversion makes the default constructor take plain values: a user writes `Lines(matrix, :red, 2.0)` and the fields become kept values.
- Fields without a bound (`step::Symbol`) are not checked when set; check them where they are used, with the same message.

**A recipe with children rebuilds its children from its own fields before each use.**
- `Hist` keeps the sample, `bins` and `color`; `refresh!(h)` recomputes its `Bars` child's points, width and colour, then the child draws itself.
- A child then follows every change of the parent, and a live source, with no notification graph. A cache between renders is an optimization for later.
- A user's recipe made of the library's recipes is plain code: fields of the library's concrete recipe types, the trait's operations delegated to them, `@implement Plot Ribbon`.

**Live data is a value that conforms by forwarding.**
- A `Live{T}` with a field `val` conforms to `Positions` by `by val`. A trait object reads the user's object at its offsets, so a render after `live[] = new` sees the new value. A user's mutable type mutated in place works the same way.
- The notification (`onchange`) is ordinary code.
- Forwarding is declared per parameter value (`Live{Matrix{Float64}}`, `Live{Vector{NTuple{2,Float64}}}`); forwarding for a family is not in TraitWorld yet.

**Keep the control equivalent feature by feature, and compare outputs, not just tests.**
- PlainPlots draws the same reference figures through the same Cairo calls; the test compares the two libraries' PNGs pixel by pixel, and both with committed references. A difference is a bug in one of them.
- PlainTables prints the same summaries as TraitTables, missing cells included (`TraitReport/scripts/check.sh` diffs them for three datasets).
- Where the trait form cannot name something, make the control compute it the same way. A bounded function cannot name the trait's associated type (`Column{T}`'s `T`), so TraitTables names a column's cell type from its cells, and PlainTables does the same instead of using `eltype`.

**Validate names in the ordinary layer, with messages that list the choices.**
- Symbols are values of one conforming type, so a bound cannot refuse `:magenta`. The ordinary layer checks colour, marker, step, alignment and bin count where they are given and lists the alternatives.
- "A missing cell" errors name the fix (`skipmissing = true`).

**A scripted REPL session is the correctness check for interactivity.**
- Feed a session line by line to a real REPL on a pseudo-terminal (`script -qec "julia -i" /dev/null < session.jl`) and print `CHECK <what> ok` lines. Strip terminal escapes before matching (`sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'`).
- Each session defines a new data type, a new plot type and changes an attribute at the prompt (`TraitMakie/scripts/session.jl`, `TraitReport/scripts/session.jl`).
- The REPL displays every result, which tests do not. TraitReport's session found that printing a table with a `String15` column raised a `TypeError`: `string` of an InlineStrings value keeps its type, and the printer asserted `String`. List the `ERROR` lines of the transcript and allow only the deliberate mistakes.
- A result type asserted in trait code (`cellstring(c, i)::String`) holds for the implementations you tested, not for the ones an extension adds later. Convert where the type matters (`String(string(x))`).

### B4. Small examples and acceptance cases (owner: the examples agent)

From `experiments/facts/framing/` and `experiments/examples/` (READMEs there). "Shown" means run once in session 29, with TraitWorld's own policy; "expected" means written but not yet run.

- **Fully typed code is safe from everyone but stakeholders and pirates. Check it, do not assume it.** S1–S10 ran in plain Julia and in the facts mode, as the design says. A stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7, S10) invalidate code at concrete signatures. Nothing else does in facts mode. Shown: `facts/framing/inval_cases.jl`, 20/20 in both modes.
- **A hook on your own type hurts callers only at narrow abstract signatures.** `Base.show(io, ::MyIrr)` invalidates a caller at `show(::IOBuffer, ::AbstractIrrational)` (S1b). On 1.13 it leaves a caller at `show(::IOBuffer, ::Any)` alone, since a call with many matches records no edge (S1c). So the fragile code is the half-abstract kind: `Vector{AbstractShape}` with two or three methods. Shown: S1b, S1c.
- **Do not splat a collection into a call in trait code.** `vcat(xs...)` with many arguments compiles at a widened `Vararg` signature. That signature is not a fact signature. Under facts every call inside it is a run-time site, over the whole argument tuple each time. Write `copy(xs)` or `reduce(vcat, parts)` instead. Shown: `facts/framing/vararg_splat.jl` (10 run-time sites in facts mode, none plain; Julia's core.jl #10981 does not finish). A tuple of concrete types ending in a concrete `Vararg` tail is a fact signature ([facts §3](../reference/facts.md#facts-and-fact-signatures)); a widened `Vararg{Any}` tail is not. To recheck against this case.
- **Customize trait code by implementations, never by a method of someone else's function for someone else's type.** A harmless-looking pirate (`+` on the solver's duals, same values) is refused under strict mode at its definition, and the pirate never runs, for plain code either. In the default tier it is followed and recompiles the solver's dual code. Shown: `examples/strict/dual_pirate.jl`. At the prompt the definer is `Main`: write `@eval Owner f(…) = …` when you are the owner (TraitWorld `test/strict.jl`).
- **Until piece 15, strict mode guards only against pirates that load after the code they break.** A pirate defined or loaded before a trait package's image is followed silently, in both tiers. Shown: `pirate_tiers.jl before|prompt-before`, `dual_pirate.jl before` (2,192 pirate calls under strict mode).
- **An extension method at a fact invalidates; an extension's implementation does not.** S9: an owner's extension that adds `score(::Float64)` invalidates the trait code that calls it, in both tiers. This is the named exception, and the extension rule is open. Shown: `s9_extension.jl`. A glue extension that only declares implementations (`examples/extension/glue.jl`) is expected to invalidate nothing.
- **Do not configure trait code through a `const` that someone else redefines.** A const redefined from another module invalidates the trait code that read it. No tier sees it: there is no rule and no hook for bindings. Pass configuration as an argument or a field. Shown: `pirate_tiers.jl binding` (strict tier).
- **A `Dynamic` answers in the caller's world.** After redefinitions, a call pinned to an older world sees the old methods. An implementation declared later is seen only in the latest world. Shown: `g1_16_dynamic_world.jl`, 6/6 with witness tables off.
- **Split-core packages need their delegate before they load.** Expected, from reading the code: the curated pairs are registered after a package loads, but its image is checked during activation (`examples/strict/split_core.jl`; see that README). `delegate!(Core => Impl)` takes both modules, so it cannot be declared ahead.
- **Fully typed mode names root causes, not yet fixes.** Expected, from reading `concrete.jl`: a warning names the line and the root cause (an abstract field, a non-constant global, a boxed variable). The fix is not named. A type passed as a value warns about nothing, though it is a run-time site under facts. Both are the fully-typed certificate's job (`examples/warnings/teach.jl`).

## Proposed for part A

(Each item: the rule, the port that shows it, the example.)

- **A field that users assign to needs a conversion at `X`.** Assignment from ordinary code (`p.color = :red`) is a crossing, and Julia's `setproperty!` converts to the field's type. TraitWorld converts a plain value for every trait, to the trait's default; a library that needs to translate a value first (a symbol to a colour) defines `Base.convert` to `Kept{X}` for its trait. Shown by TraitMakie step 2 (`src/TraitMakie.jl`); B3.
- **Keep the plain control equivalent feature by feature, and compare its outputs with the trait form's.** Shown by TraitMakie (five figures pixel-identical with PlainPlots) and TraitReport (`scripts/check.sh`: the same summaries and PNGs with PlainTables on three datasets); B3. Example: a test that renders the same figure with both libraries and compares pixels. Also TraitDifferentialEquations: `scripts/session.jl trait|plain` prints identical `RESULT` lines with PlainODE (B2).
- **Leave a function's attribute to the caller, and serve both with one struct.** Keep it at a struct parameter bounded by `Callable` (`ODEProblem{T, P, F, D}`); `Callable`'s default is `Dynamic`, the user asks `compiled_for(f)`. The attribute changes speed, never values. Shown by TraitDifferentialEquations (`ODEProblem`; `test/compiledcall.jl`: identical solutions either way); B2.
- **A package is an ordinary module around its trait module.** `@trait_module` is not in scope at a package's top level. Shown by TraitDifferentialEquations (`ODECore`), TraitCSV (`CSVCore`) and `examples/LorenzModels` (`Models`); B2.
- **Declare result types that catch the common mistake.** `rhs!(…)::Nothing` refuses, at `@implement`, the in-place function whose last line `du .= …` returns `du`. Shown by TraitDifferentialEquations (`test/routea.jl`, case (c)); B2.
- **Do not splat a collection into a call in trait code.** A call at a widened `Vararg` signature is no fact signature: under facts every call inside it is a run-time site over the whole tuple, quadratic in its length. Write `copy(xs)` or `reduce(vcat, parts)`, not `vcat(xs...)`. Shown by `experiments/facts/framing/vararg_splat.jl` (Julia's core.jl #10981 does not finish in facts mode); B4. A concrete `Vararg` tail is a fact signature ([facts §3](../reference/facts.md#facts-and-fact-signatures)); a widened one is not.
- **Configure trait code by arguments or fields, not by a `const` another module redefines.** No tier of the guarantee sees bindings. Shown by `experiments/facts/framing/pirate_tiers.jl binding`; B4.
- **A kernel reads a value only through its trait's operations; heavy library code runs over the gathered cells.** A first line `v = vector(c)` makes the trait a function barrier. Write sorts, joins and group codes against `cell`/`nrows`; for Base or Statistics over many cells, gather them into the trait's `Vector{T}` (`emptycells`) so that code compiles per cell type and is shared by every column kind. Shown by the forks (`DataFrames/src/other/kernels.jl`: `refine!`, `innerrows`, `firstcodes!`, `colstats`); B1. See implementation review P7.
- **Name an associated type through an operation that returns it in a container.** `f(c::Column{T}) where {T}` is not supported; declare `emptycells(c::Column{T}, n)::Vector{T}` and write `T = eltype(emptycells(c, 0))`. Shown by the forks (`Tables/src/ColumnCore.jl`); B1. Also met by TraitReport (B3), which names `T` from the cells; a TraitWorld feature would serve both.
- **A hook on a type passed as a value becomes implementations for a value that stands for the type.** For `stringtype = String15` the reader calls the trait's operations on `String15[]`; the extension declares `@implement TextColumn Vector{String15}` and adds no method to the package's functions. Guard the run-time `conforms` query with a static test (`S <: AbstractString`). Shown by the forks (`CSV/ext/CSVInlineStringsExt.jl`, `CSV/src/api.jl`); B1. Refines rule A4.
