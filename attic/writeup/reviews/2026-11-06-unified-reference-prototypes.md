# Review: the draft reference against the prototypes

Status: current. Not edited after writing, except by a dated addendum. Dispositions of the findings: none yet (to be recorded by the main session where each is taken up).

Date: 2026-11-06. A reading review: no Julia was run, nothing was built or measured. "Verified" means read in the code or the draft at the lines cited. "Inferred" means reasoning from the draft's rules; it is marked.

## What was read

- The draft, in full: `writeup/reference-unified/README.md`, `traits.md`, `facts.md`, `compiler.md`, `lowering.md` (design repository at 96d3915).
- The decisions behind it: `writeup/record/decisions.md` §9; `writeup/plans/2026-11-06-traits-are-abstract-types.md`; W-83's row of `writeup/record/todo.md`; open issues 82, 96, 97, 102, 104, 105, 111, 112, 114, 117, 118, 119, 124, 135, 137, 138, 140, 141, 142.
- The earlier reference (`writeup/reference/`) for the IDs the prototypes carry; not reviewed.
- The prototypes, with `git log --oneline -1`:
  - `TraitWorld/` 33dd55e: `src/BaseTraits.jl` in full; the rest by grep (its mechanism is what the draft retires).
  - `TraitDifferentialEquations/` e9e07ed: `lib/ODECore/src/core.jl`, `frontend.jl`; `lib/TraitIndexing/src/TraitIndexing.jl`; `lib/TraitArrayTools/src/TraitArrayTools.jl`; `lib/TraitRodas/src/rodas5.jl`; `lib/TraitNonlinearSolve/src/problems.jl`, `solvers.jl` (head); `lib/TraitImplicit`, `lib/TraitLinSolvers`, `lib/TraitNLSolvers`; `src/TraitDifferentialEquations.jl`; `examples/LorenzModels/src/LorenzModels.jl`.
  - `TraitMakie/` ba46982: `src/PlotCore.jl`, `src/TraitMakie.jl`; `compat/MakieCompat/src/MakieCompat.jl` lines 528–620 and by grep.
  - `TraitTables/` 438ac2b, `TraitCSV/` 9c6477b, `TraitReport/` 882c533: the cores and the extension in full.
  - `forks/` 77b9aab: `Tables/src/ColumnCore.jl`, `CSV/src/ColumnParsers.jl`, `DataFrames/src/other/kernels.jl` (lines 1–232, 770–802), `DataFrames/src/dataframe/dataframe.jl` by grep, the extensions.
  - `ndport/` 65ac255: `pkgs/NetworkDynamics-ports/src/component_dynamics.jl`, `symbolicindexing.jl` (the trait part), `network_structure.jl`, `coreloop.jl` by grep; `pkgs/Graphs-p4/src/interface_trait.jl`; `README.md`.
  - `experiments/` e7023da: listing only.
- Not read: TraitWorld's tests; the ndport clones' non-trait code; `TraitDifferentialEquations-w96/`, `TraitWorld-port/`.

## Summary

Two High findings. Both are rules of the draft that real code breaks on its own terms.

- **H1. `Callable` by derived memberships (P-7) is unsound as stated and unbuildable at acceptable cost.** The draft says a derived membership ends only by a definition of the member's own methods (facts §10, traits §9). The inferred result of a closure depends on every callee's methods and on inference's heuristics. So a load of an unrelated package can change which method a trait call selects, against G1 and G2. And `jl_subtype`, `jl_type_intersection` and the type cache must run inference (compiler §7.4). Evidence: TDE's problem types and callbacks, the forks' `byrow`, BaseTraits' `retain!`. Proposal: derive `A` from the method table (a `hasmethod` fact), `S` from a declared result; result types a kernel needs are values decided by inference (`promote_op`), not memberships.
- **H2. `bounded` on by default (P-2, traits §13) refuses the ports' library layer and the draft's own idioms.** Storing a trait argument in a struct whose parameter is the value's type (`CoreProblem(ProblemRHS(prob), …)`, `CellVector(c)`, the draft's own `Problem{typeof(k)}(k, u0)` and `asvector`), wrapping it in `Dynamic{X}(x)`, or capturing it in a closure are "any other use" under §7.3, so open, so refused with `TraitUseError` in every port module. Proposal: `bounded` opt-in per method or module; §7.3 names the two idioms as open methods compiled per type.

Medium: M1 `Dynamic{X}`'s membership pattern misses `Dynamic{Column}`, `Dynamic{Callable}` and `Dynamic{All{…}}` (28 uses in the table ports). M2 casts at a plain argument are silent no-ops, so TDE's documented `ODEProblem(compiled_for(f), …)` does nothing. M3 no key, candidates or attribute rule for an `All{X, Y}` argument (7 uses). M4 `HasProperty` "by the member's own `getproperty`" has no form on a value typed by its trait. M5 a `Dynamic{Callable}` at a second signature needs an explicit re-wrap (TDE's duals). M6 BaseTraits' operations put methods at open sets on `Base.getindex`, `iterate`, `length`. M7 the member hook runs contract checks inside dispatch. M8 C-21 silently breaks the NetworkDynamics port's nine-parameter memberships.

Low: ten items (§4).

What the draft makes simpler is substantial (§2): the item views of BaseTraits (256 lines), TDE's front-end workarounds for kept values (E-239, T-90), the forks' storage change (D2), TraitMakie's four `Live` declarations (T-7), the untyped-fallback ordering (L-3), constructors at bounds (L-50, open issue 135), the subtrait encoding (open issue 124), Revise (T-81).

---

## 1. What each prototype would write under the draft

Each table: the construct as the prototype has it, what it would write, and whether that is better, equal or worse (speed, compile cost, clarity, guarantees). A finding's ID is given where the change is not mechanical.

### 1.1 TraitDifferentialEquations

| Prototype | Under the draft | Verdict |
|---|---|---|
| `CoreSolution.interp::Union{Nothing,Kept{Interpolant{…}}}` and `kept_interpolant` (core.jl:198, 230–232) | a field typed `Interpolant{Vector{T},Float64}`; `keep(d)` where the integrator makes its solution (§7.8) | equal; shorter |
| `ODESolution.prob::Kept{ODEProblemTrait{T,P}}` (core.jl:816), `NonlinearSolution.prob` (problems.jl:279) | a field typed by the trait; `.p` read by §7.9 | equal |
| `Dynamic{IntegratorView{U,T,P}}` as an operation's further argument (core.jl:119–121, 134–137, 161–171) and the user's `LorenzView` (LorenzModels.jl:67, 77–78, 95–96) | `integ::IntegratorView{U,T,P}`: the user's `affect!` is a method at a trait, compiled per key, which is per `ParamIntegrator` type; `getstate(integ, :x)` works on the raw value by dispatch | better: no box; every trait of the integrator reachable (open issue 97's path without §6.5) |
| `Dynamic{StepView{…}}(i)` in the cores (core.jl:1345, rodas5.jl:291) | the same: the one way to keep the core compiled once per state type | equal |
| `Kept{Callback{U,T,P}}[]` with the E-158 note (core.jl:610–611, 758–759) | `Callback{U,T,P}[]`; items plain; the loop's calls split over the first four members, else the table (§7.9) | equal (inferred: the split does the one dispatch the `Compiled` path did) |
| `cb::(EventCallback{U,T,P}, Callback{U,T,P})` (core.jl:629, 770) | `All{…}` | equal; M3 |
| `Kept{Callable}` before the signature is known (core.jl:556–562; TraitIndexing.jl:36, 117, 130–138, 152) | a field typed `Callable`, or `Dynamic{Callable}` | equal in form; H1, M1 |
| `F <: Callable{CoreRHSSig{T},Nothing}` struct parameters (core.jl:436, 509; problems.jl:124, 219; rodas5.jl:56) | §8.2 as written | equal in form; H1 for the membership test the constructor runs |
| `rewrap`, `_partial`, `_user_function` (frontend.jl:88, 111, 120–121; problems.jl:110–111; open issue 105) | `k = keep(f); k isa Dynamic ? Dynamic{Callable{CoreRHSSig{T},Nothing}}(PartialFn(unwrap(k), p)) : PartialFn(k, p)`, inside a method whose `f` is typed `Callable{…}` | equal; M2 says where it stops working |
| `compiled_for(core_no_jacobian)` (frontend.jl:78; problems.jl:208) | the raw function; the parameter records its type (§8.2), the `J === CoreNoJacobian` fold stays | equal |
| the right-hand side seen at the duals through its kept form (core.jl:424, 455, 464, 519; problems.jl:136, 229) | `Dynamic{Callable{CoreDualSig{N},Nothing}}(unwrap(prob.f))`; `UserFunction`/`fplain` (core.jl:404–408, 443, 457–458) become `unwrap` | slightly worse; M5 |
| `_iskept`, `_by_bound`, `conforms` and the E-239 note (core.jl:283–343; problems.jl:59–60) | `x isa HasMassMatrix ? mass_matrix(x) : I` | better |
| `_member_checked`, `F <: Dynamic ‖ …` (core.jl:532–538; problems.jl:239–243; T-90) | goes | better |
| `is_nonlinear_algorithm(alg::NonlinearAlgorithm) = true; (alg) = false`, "by dispatch, not by `conforms`" (solvers.jl; E-242); `getsystem` (TraitIndexing.jl:56–57); `_mass_matrix_of` (core.jl:313–319) | plain Julia dispatch with a guard cell per (type, trait) (compiler §5.6) | equal; L-3 goes |
| `@default_with_dynamic_self` (TraitIndexing.jl:33) | `@default_dynamic` | equal |
| `getstate(v::(ValueProvider{U,P}, IndexProvider{Symbol}), …)` (TraitIndexing.jl:82, 88, 160; core.jl:901) | `All{…}` | equal; M3 |
| `@trait_module begin … end` (ODECore.jl:11 and five more), `@trait_module module Models` (LorenzModels.jl:18) | `@trait_module` after `using TraitWorld` | better (T-81) |
| `rhs_function(prob)::Any = nothing`, a default read by plain callers (core.jl:62, 458) | reached by any caller (P-1) | equal |
| `ODEProblem(compiled_for(f), …)` as documented (frontend.jl:47; core.jl:419) | no effect: `f` is `@nospecialize`d, not typed by a trait (§7.6, last bullet) | worse; M2 |
| `solve(prob, Tsit5())` from the prompt (TraitDifferentialEquations.jl:59–63 → `solve_ode(@nospecialize(prob), …)` → `core_problem(prob::ODEProblemTrait)`, core.jl:540) | `prob` is `Dynamic` by `first_seen`; `rhs!` dispatches per call through the split, unless `ODEProblemTrait` declares `@default_compiled` | equal to today's first-seen; the trait author opts in (L9) |
| `IntegratorView <: HasProperty{:ps, ParameterView{P}}`, `property(i, ::Val{:ps})` (core.jl:95, 668–670) | `Base.getproperty(i::ParamIntegrator, s)` (§4.3, §10.1) | M4 |
| `Rodas5{L <: LinearSolver}`, `Newton{L}`, `ImplicitEuler{N}`, `DualJacobian{N,FD}`, `PartialFn{F,P}`, `ProblemRHS{M}` (rodas5.jl:10, 56; core.jl:385–399, 978; TraitImplicit.jl:20) | §8.2 struct parameters; the methods that build them are open | H2 |
| `@implement ODEProblemTrait{T, LorenzParams{T}} LorenzProblem{T} where {T}` (LorenzModels.jl:64) | the same (P-16) | equal |
| `struct LorenzProblem{T}` + `@implement` | `struct LorenzProblem{T} <: ODEProblemTrait{T, LorenzParams{T}}` and `@implement` after the methods (P-9) | equal; a nicety |

### 1.2 TraitMakie

| Prototype | Under the draft | Verdict |
|---|---|---|
| `Opened{X}` on the kernels, 13 sites (PlotCore.jl:327, 336, 346, 390, 406, 410, 419, 423, 430, 508, 532, 552) | `@specialize pos::Positions` on the kernel (§7.5 step 3): a plain value read from a field takes it | equal |
| fields typed by a trait holding kept values (PlotCore.jl:131–132, 230–231, 351–387, 485–504, 608–613) | the same text; the field holds the member | equal |
| `setcolor!(p::Plot, c::Kept{ColorSpec})` (PlotCore.jl:322, 467–472, 593–595) | `c::ColorSpec` | equal |
| `add_lines!(ax, pos::Dynamic{Positions}, …)` and eight more, `recolor!(…, c::Dynamic{ColorSpec})`, `add_plot!(ax, p::Dynamic{Plot})` (PlotCore.jl:640–706) | `pos::Positions`: a plain caller's value is `Dynamic` by `first_seen` | equal |
| `push!(ax.plots, Dynamic{Plot}(p))`, `l.pos = Dynamic{Positions}(steppoints(…))` (PlotCore.jl:567, 576, 583, 660–705) | push the raw value; items are plain; calls split | equal |
| `Vector{Dynamic{PC.Plot}}` in MakieCompat (MakieCompat.jl:535–588) | `Vector{PC.Plot}` | equal |
| `@implement Positions Live{Matrix{Float64}} by val` and three more, "forwarding for a whole family: not yet" (TraitMakie.jl:229–233) | `@implement Positions Live{T} by val where {T <: Positions}`; `@implement Sample Live{T} by val where {T <: Sample}` (§5.8) | better (T-7) |
| `Base.convert(::Type{ColorSpec}, x) = _color(x)` and three more (TraitMakie.jl:88–91) | Julia's own conversion at assignment (§8.1); the untyped catch-all needs checking | L2 |
| `@implement PC.Plot P where {P <: Plot}` (MakieCompat.jl:608), `const AbstractPlot = Plot` (:68; W-83's case) | the same; or `mutable struct Plot{F,T} <: PC.Plot` (§5.2) with `abstract type AbstractPlot <: PC.Plot` | better |
| `@joint_owners MakieCompat MakieCompatStats` (TraitMakie.jl:21) | the same (§12.1) | equal |
| `@implement Scale typeof(log10)` (PlotCore.jl:203; W-83's case) | the same | equal |

### 1.3 TraitTables, TraitCSV, TraitReport

| Prototype | Under the draft | Verdict |
|---|---|---|
| `cols::Vector{Column}` "a `Vector{Kept{Column}}`" (TableCore.jl:33) | the same text; holds any vector | equal |
| `compiled_for(c)` at the call, five sites (TableCore.jl:55, 63, 152; TraitTables.jl:51) | the same form (§7.6) | equal |
| `take(c) = Dynamic{Column}([…])`, `fillcolumn` → `Dynamic{Column}(with_dynamic(c))` (TableCore.jl:50; CSVCore.jl:107) | return the vector and store it raw; `Dynamic{Column}` only where "compiled once" must survive a caller that knows the type | equal; M1 |
| `defaulttypes() = CSVColumn[Dynamic{CSVColumn}(Int[]), …]` (CSVCore.jl:49–51) | `CSVColumn[Int[], Float64[], …]` | equal |
| `emptylike(c::CSVColumn)::Self` on a kept value (CSVCore.jl:20; T-35) | the trait's forwarding method; `Self` is the field's type | better (T-35 retires) |
| `@trait CSVColumn{T} <: Column` (CSVCore.jl:17; ColumnParsers.jl:51, 129) | `<: Column{T}` (§4.5, §5.8) | equal |
| `@implement Column A where {A <: Vector}` (TableCore.jl:23) | `@implement Column{T} A where {T, A <: Vector{T}}` (P-16) | equal |
| `Job` of fields only, `@implement Job ReportJob` (ReportCore.jl:39–47) | the same | equal |
| `@implement CSVColumn Vector{String15}` in the extension (TraitCSVInlineStringsExt.jl:10) | the same; names its triggers (§12.1) | equal |

### 1.4 forks (Tables, DataFrames, CSV)

| Prototype | Under the draft | Verdict |
|---|---|---|
| `DataFrame.columns::Vector{Dynamic{Column}}`, `tocolumn`, `_dcolumn(s)`, `vector(c)` (dataframe.jl:181, 239, 445–460; ColumnCore.jl:43, 71–73) | `Vector{AbstractVector}` as upstream: every `AbstractVector` is a `Column`, raw items reach kernels by dispatch; `vector` goes | better: D2's storage change dissolves (inferred) |
| `Opened{Column}` kernels and `Opened{(Column, PooledColumn)}` (kernels.jl:51, 116, 127, 139, 167, 171; ColumnParsers.jl:150) | `@specialize c::Column`; `@specialize c::All{Column, PooledColumn}`: the pooled method is selected by dispatch on the raw vector | better: the reliance on old §6.5 (kernels.jl:170) goes |
| `CellVector{T, C <: Column{T}}` (kernels.jl:37–42; open issue 96) | the draft's own §8.2 example | equal; H2 for the methods that build it |
| `byrow(f::Callable{Tuple{T},S}, c::Column{T}) where {T,S}` (ColumnCore.jl:101–116; E-216) | the same text; `S` by a derived membership | H1 |
| `tablecolumn(t, i)::Dynamic{Column}` (ColumnCore.jl:82, 88; kernels.jl:793–801; ColumnParsers.jl:168–172) | `::Column` | equal |
| `ByRow{F}` compiled per closure (open issue 111; plain code reading the function, 114) | `struct ByRow{F <: Callable}`; a user's closure as `Dynamic{Callable}` where the fork wants one copy; `b.f` readable by plain code, `unwrap(d)` for a wrapped one | better |
| `refine!`'s closure capturing `c` (kernels.jl:128) | open under §7.3 | H2 |
| `@implement CSVSource A where {A <: IO}` and the others (ColumnParsers.jl:27–35) | the same | equal |

### 1.5 ndport (NetworkDynamics, Graphs)

| Prototype | Under the draft | Verdict |
|---|---|---|
| `conforms(typeof(x), X)` (component_dynamics.jl:133) | `x isa X` | equal |
| `Kept{VertexDynamics}(x)` per batch, `KeptBatch`, `compiled_for(batch.model)` (network_structure.jl:226–227; coreloop.jl:133–147) | a field typed `VertexDynamics`; the cast at the call stays | equal |
| the adaptors `_user_vertexf!(m::VertexDynamics, …)` because "defaults and forwarding serve trait code only" (component_dynamics.jl, the user's-type section) | call the operations directly (P-1) | better |
| `observed(nw, idx) = … Kept{Callable}(SII.observed(nw, idx))` (symbolicindexing.jl:1151) | return the function | equal |
| `@implement IndexProvider{NWIndex} Network{EX,G,NL,VTup,MM,CT,GBT,LM,EM} where {…}`, nine variables; `HasSystem`, `HasMassMatrix`, `HasJacobianPrototype` the same (symbolicindexing.jl:1148; network_structure.jl:362–368) | the same; but compiler C-21: "a pattern with more than eight type variables is accepted and never matches" | worse until C-21 is fixed; M8 |
| `@trait GraphInterface{V <: Integer}` with `V = eltype(Self)`, `@implement GraphInterface G where {G <: AbstractGraph}` (interface_trait.jl:28–39) | `@implement GraphInterface{V} G where {V, G <: AbstractGraph{V}}` (P-16) | equal |
| `edge_list` on a `Dynamic` graph: `TypeError`, `SimpleEdge{OpenParam}` (ndport README, E-154) | `Dynamic{GraphInterface{Int64}}` fixes `V` (§7.7) | better |
| `thing isa Union{Dynamic,Compiled,Kept}` (symbolicindexing.jl:32) | `thing isa Dynamic` | equal |
| `@default_with_dynamic_self` three times (component_dynamics.jl:8, 20, 30) | `@default_dynamic` | equal |
| the `@trait_module begin … end` block that cannot hold `public` (NetworkDynamics.jl:4, 225) | `@trait_module` as a statement | better |
| a closure in a bounded function capturing a variable of a type not inferred (E-154's second failure) | the closure makes the method open | H2 |

### 1.6 TraitWorld: BaseTraits

| Prototype | Under the draft | Verdict |
|---|---|---|
| `DynamicItems`, `CompiledItems`, `DynamicValues`, `CompiledValues`, `crossed`, `_may_hold` (BaseTraits.jl:95–350, 256 lines; T-55) | go: `Iterable{<:Shape}` is variance (§10.2); a `Vector{Any}` is converted first | better |
| `retain!(f, xs::(MutableIndexable, Resizable))` (BaseTraits.jl:505) | `All{…}` and `f::Callable{Tuple{T}, Bool}` (§10.3) | equal; H1, M3 |
| `IndexableVector{T, C <: Indexable{T}}`, `asvector` (BaseTraits.jl:386–400; lowering §10) | §8.2; `asvector`'s `typeof(keep(x))` is an open method | H2 |
| `HasProperty{N,R}` with `property(x, Val(N))` and `_propget` (BaseTraits.jl:367–373) | "by the member's own `getproperty`" (§10.1) | M4 |
| families stated without the trait's parameters (`@implement Iterable A where {A <: AbstractArray}`, BaseTraits.jl:86–93; `Solvable S where {S <: Factorization}`, :415) | `@implement Iterable{T} A where {T, A <: AbstractArray{T}}`, `Keyed{K,V} D where {K, V, D <: AbstractDict{K,V}}`, `Solvable{T} S where {T, S <: Factorization{T}}` (P-16) | equal |
| `@implement BoundedText I where {I <: Base.BitInteger}`, a variable over a `Union` (BaseTraits.jl:434) | no pattern form in compiler §4.2 | L6 |
| operations on Base's functions (`Base.iterate`, `getindex`, `setindex!`, `length`, `haskey`, `resize!`; BaseTraits.jl:38–82) | the trait's method per operation is a method of `Base.getindex` at an open set, in the typemap's linear list (lowering §2; compiler §5.1) | M6 |

---

## 2. What the draft simplifies or removes

Each item names the workaround and its ID where one exists.

- **Item views and the crossing** (T-55; BaseTraits.jl:95–350; the old traits §8.2–§8.3): variance (§10.2). 256 lines go; the user converts a `Vector{Any}`.
- **TDE's reads of a kept value's other traits** (E-239, "a candidate open issue"; core.jl:283–343): `isa` on the raw value. The `_iskept`/`_by_bound`/`conforms` layer goes.
- **The family member check through a kept function** (T-90; core.jl:532–538, problems.jl:239–243): goes with H1's caveat.
- **Untyped fallbacks defined after bounded methods** (L-3; solvers.jl `is_nonlinear_algorithm`, TraitIndexing.jl:56–57, core.jl:313–338): Julia's dispatch, trait before `Any`, with the guard of compiler §5.6.
- **Constructors taken out of the method table** (L-50, open issue 135): a constructor at a bound is a method (§6.7).
- **The subtrait encoding** (open issue 124, W-93's `Subtrait{U}`; E-238's 237 invalidated CodeInstances): `B <: A` is subtyping. Nothing is added to a supertrait's functions when a subtrait is declared.
- **Forwarding per family instance** (T-7; TraitMakie.jl:229–233): one family declaration.
- **A constructor operation on a kept value** (T-35; CSVCore.jl:20): the forwarding method returns the object; `Self` is the field's type.
- **`@trait_module module … end` and Revise** (T-81; every port; ND's `public` note, NetworkDynamics.jl:225): a statement in an ordinary module.
- **The forks' storage change** (D2, E-211; dataframe.jl:181–239, ColumnCore.jl:71–73, `vector(c)`): `Vector{AbstractVector}` is a vector of `Column`s; `tocolumn`, `_dcolumns`, `vector` go (inferred).
- **`ByRow` and plain code reading a kept function** (open issues 111, 114): raw values and `unwrap`.
- **`eltype` of a bounded argument; returning the argument** (open issues 137, 138; E-258's 7 of 74 functions): admitted by §7.3.
- **A family whose parameter an equation defines** (open issue 140; `GraphInterface`, `Column`): P-16.
- **Symbolic access through the integrator's other traits** (open issue 97's path, core.jl:672–673): a raw `ParamIntegrator` in callbacks is a member of all its traits; no "seen through every trait" rule is needed. The `.ps` sugar is M4.
- **A `Dynamic` graph's open parameter** (E-154's `SimpleEdge{OpenParam}`): §7.7 fixes the parameters.
- **W-83's collected cases**: `AbstractPlot` as a real abstract type under `PC.Plot`; `Block`/`Axis` as `abstract type Block <: Layoutable`; `Trajectory` as a supertype of an `AbstractDiffEqArray{T,N}`; `GraphInterface` as a supertype of `AbstractGraph{T}` if Graphs adopted it; DataFrames' untyped API calling operations untyped is plain dispatch. The `Plot{F,T}` tree walked in plain code (open issue 112) is unchanged: the draft has no form for it, and needs none.

Not simplified, contrary to what one might expect:
- **Open issue 82** (a kept value's constructor compiled per value type; TDE's 29 `@nospecializeinfer` wrappers): lowering §7's `Dynamic{X}(x)` is an ordinary constructor, specialized per `typeof(x)`. The wrappers stay unless its definition is `Dynamic{X}(@nospecialize(x))`. (L7)
- **The two-layer `ParamIntegrator`/`StepView` adapters** (W-63; core.jl:632–779): still needed, since `P` is a parameter of `Callback{U,T,P}` and part of the key.

---

## 3. Weak points, with proposals

### H1. `Callable{A, S}` by derived memberships (traits §9; compiler §7.4; facts §10; P-7)

**The cases (verified).**
- TDE: `struct ODEProblem{T,P,F<:Callable{CoreRHSSig{T},Nothing},…}` (core.jl:436) and `CoreProblem` (:509); a user's `f(du, u, p, t)` from the prompt; `DiscreteCallback((u, t, i) -> t > 0.05, …)` (TraitDifferentialEquations.jl:140); `_problem` (frontend.jl:71) must dispatch on `f`'s membership once the front end types it (M2).
- forks: `byrow(f::Callable{Tuple{T},S}, c::Column{T}) where {T,S}` from DataFrames' plain `select` pipeline, a new closure per call (ColumnCore.jl:101–116; E-216).
- BaseTraits: `retain!(f::Callable{Tuple{T},Bool}, …)` (§10.3).

**What fails.**
- (a) **A membership by inference is not a fact only stakeholders change.** Facts §10: a derived membership "ends only when a definition changes a method of its member's type at its signature: a stakeholder's change or a pirate's, by Lemma O". Traits §9 says the same. Plain inference's result at `A` depends on every callee's methods and on inference's heuristics (`max_methods`, recursion limits, union splitting). A closure over a non-`const` global, or one that calls a function at an abstract type with more than `max_methods` methods, infers `Any`: it is a member of `Callable{A, Any}` and of nothing narrower. A package that adds one method to such a callee can flip `S` between a type and `Any`. Then `F <: Callable{A, Float64}` ends, dispatch at `byrow(f, c)` changes, and a `MethodError` appears where plain Julia still runs `f`. G1 ("computes what plain code computes") and the G2 statement for derived memberships do not hold, and Lemma O does not cover the case: the definition was by no stakeholder of `F`. (Verified: the wording of facts §10, §2.1; inferred: the inference behaviour, which is Julia's documented one.)
- (b) **Inference inside the type system.** Compiler §7.4: "Subtyping and dispatch derive on demand, in the world asked about." So `jl_subtype(typeof(f), Callable{A,S})`, `jl_type_intersection` and the type cache (compiler §4.7) run `PlainRTInterp`. Subtyping is called from inference's lattice operations, from method insertion and from dispatch. Running inference there reenters inference (a closure whose body calls `byrow` with a closure), allocates, can throw, and gives world-dependent answers that the type cache cannot keep. The prototype kept `Callable` as a mechanism of its own outside dispatch (T-87) and checked the result at the call; nothing in the prototypes shows the derived form working. (Inferred.)
- (c) **The user-facing change.** SciML users' right-hand sides often return their last assignment or `du`. Today TDE reports that at the first call with a hint (T-90's message, traits §5.8 of the old reference). Under the draft `f` is not a member of `Callable{Sig, Nothing}`, so `_problem(f, …)` raises `MethodError` (lowering §9's hint). A closure over a non-`const` global is not a member of `Callable{CondSig, Bool}` at all. Stricter than SciML, and decided by inference rather than by the program.
- (d) **A gap.** Lowering §7 and §9 do not define how a `Dynamic{Callable{A,S}}` is called. If its call is a varargs method whose result is asserted to `S`, the derived rule makes `Dynamic{Callable{A,S}} <: Callable{B,S}` for every `B`, and the call raises `MethodError` at run time: the derived membership would be false.

**Proposal** (keeps the user's "dispatch picks by signature"):
- Derive `A` from the method table alone: `F <: Callable{A, S}` when a call of an `F` at `A` selects one method (a `hasmethod` fact; facts §3 already lists `hasmethod` at a declared signature as a fact signature) and that method's declared result (compiler §6.8) is a subtype of `S`. A method without a declared result is a member of `Callable{A, Any}` and `Callable{A, <:Any}` only. Both halves are syntactic, world-indexed by `F`'s methods alone, and Lemma O holds. Dispatch between `Callable{Tuple{Int}, …}` and `Callable{Tuple{String}, …}` still picks by signature.
- The result type a kernel needs for its output (`byrow`'s `Vector{S}`) is a value decided by inference, under facts §7's rule: `S = Base.promote_op(f, T)` in the method, as `map` does. Not a membership.
- A library that wants a checked result from an unannotated function writes `Callable{A, <:Any}` and asserts at the call (traits §9's assertion stays).
- `Dynamic{Callable{A,S}}`'s call is a method at `A` only, so the wrapper derives memberships at `A` alone.

### H2. `bounded` on by default refuses the ports' library layer and the draft's own idioms (traits §7.3, §13; compiler §6.7; P-2)

**The rule.** §7.3 admits six uses; "any other use makes the method open": `typeof(t)`, "a call of another function with it". §13: `@trait_module` turns on `bounded`; an open method is refused with `TraitUseError`.

**The cases (verified).** Methods at traits that build a value with the argument:
- TDE: `core_problem(prob::ODEProblemTrait) = CoreProblem(ProblemRHS(prob), …)` (core.jl:540); `_steady(prob::ODEProblemTrait{T,P}, …)` (problems.jl:203–204); `nl_core(prob::NonlinearProblemTrait)` (:244); `_names_of(s::IndexProvider{K})` → `Dynamic{IndexProvider{Symbol}}(s)` (core.jl:342).
- forks: `colstats(c, …)` → `CellVector(c)` (kernels.jl:51–53); `aggregate` (:116); `refine!`'s closure capturing `c` (:128): the closure's field takes the type of `c`.
- BaseTraits: `asvector(x::Indexable{T}) = IndexableVector{T, typeof(keep(x))}(keep(x))` (lowering §10).
- The draft itself: `Problem(f::Callable{…}, u0) = (k = keep(f); Problem{typeof(k)}(k, u0))` (traits §7.8; §8.2).
- Not affected: ndport's adaptors `VertexF(x)`, `EdgeG(x, ff)` are built in `_dynamics_record(::Type{T}, @nospecialize(x))`, a plain method (component_dynamics.jl).

Each stores the argument at a struct parameter that becomes the value's type, wraps it in `Dynamic{X}(x)` (a struct of the library, not in §7.3's list), or captures it in a closure. Under §7.3 each is open; under §13 every port module is a `@trait_module`; so each is refused. The draft's own examples would be refused in its own scopes.

**The classification is right; the refusal is wrong as a default.** Such a method cannot be compiled per key for a forwarding member: the key holds the field's type, not the member's. Open, compiled per type or once, is the right compilation. Refusing it refuses the library layer of every port.

**Proposal.**
- `bounded` is opt-in: per method (`@bounded`) or per module (`@trait_module bounded`), off in `@trait_module` by default. The kernels (PlotCore's loops, ColumnKernels, TableCore) opt in; constructors, adapters and front ends stay open.
- §7.3 names the two idioms: "storing the argument in a struct whose parameter is bounded by the trait" and "capturing it in a closure" make the method open at that argument; `keep(x)` is how the stored value carries `Dynamic`. `Dynamic{X}(x)` is listed as admitted (it stores into a field typed `X`).
- §7.8's and §8.2's examples carry a note that they are open methods.

### M1. `Dynamic{X}`'s membership pattern misses the forms the ports use (lowering §2, §7; traits §3.6, §7.7)

- Lowering §2 declares "the family `Dynamic{X{P…}} where {P…}` in `X{P…}`". That pattern does not match `Dynamic{Column}` (the parameter is the UnionAll `Column{T} where T`): TableCore.jl:50, CSVCore.jl:107, ColumnCore.jl:71–73, dataframe.jl:181; 28 uses of `Dynamic{Column}` and `Dynamic{CSVColumn}` across the table ports. Nor `Dynamic{Callable}` bare (TDE's kept functions). Nor `Dynamic{All{Shape, Placed}}` (traits §3.6's own example). As lowered, none is a member of its trait. (Verified: the pattern's text and the uses.)
- Which parameters has `Dynamic{Column}` as a member? §3.2 gives one value per parameter; `T = eltype(Self)` has none for the erased form. §7.7 says "a parametric trait's form fixes the parameters", which reads as "write them".

**Proposal.** Declare the family `Dynamic{Z} where {Z <: X}`; then `Dynamic{All{X,Y}} <: X` and `<: Y`, and `Dynamic{Sub} <: X`. State what `Dynamic{Column}` with the UnionAll is: a member of `Column` at no instance, each parameter-typed result `Any` and asserted, as the table ports use it today; or refuse it and require `Dynamic{Column{T}}`. Say which.

### M2. Casts at a plain argument are silent no-ops; the attribute is visible only through `keep` at a trait argument (traits §7.6, §7.8; compiler §6.9)

- TDE's front end is plain by design: `ODEProblem(@nospecialize(f), …)` (frontend.jl:58), `solve(@nospecialize(prob), @nospecialize(alg); callback)` (TraitDifferentialEquations.jl:59). Its documented `ODEProblem(compiled_for(f), …)` (frontend.jl:47) and the solver's "unless the caller casts it with `compiled_for`" (core.jl:9–12) do nothing under §7.6's last bullet, with no message. `rewrap` (open issue 105) has no equivalent at a plain argument.
- So every function that decides an attribute or passes a cast through must be a method at the trait: `ODEProblem(f::Callable, …)`, `_problem(f::Callable{RHSSig{P,T},Nothing}, …)`, dispatching on `f`'s membership (H1), where SciML's front end is untyped on purpose (`@nospecializeinfer`, so that a caller does not infer the solver).

**Proposal.** A cast at an argument whose declared type is not a trait is refused when lowered, as a cast anywhere else is, so the no-op is visible. And a plain function may pass a cast through: either the runtime carries the bits through a dynamic call into a plain method and out again to the next call that has a trait argument (compiler §6.3 already passes bits through `jl_apply_generic_attr`), or §7.6 states that a front end that accepts casts must type the argument by the trait, `Callable` bare for functions.

### M3. No key, no candidates, no attribute rule for an `All{X, Y}` argument (compiler §6.1, §6.2, §7.2; traits §7.2, §7.5)

- Uses: `getstate(v::All{ValueProvider{U,P}, IndexProvider{Symbol}})` (TraitIndexing.jl:82, 88), `_read` (:160), `getseries` (core.jl:901), `_enter_callback!` (core.jl:629, 770), `refcodes(c::All{Column, PooledColumn})` (kernels.jl:171), `retain!` (BaseTraits.jl:505).
- `TraitKey{X, R, F}` names one set. At an `All{X,Y}` argument: a pair of keys, or `TraitKey{All{X,Y}, R, F∪F′}`? Which candidates does the split take (each set has its own index)? Which default attribute applies when the components' defaults disagree (§7.5 step 4: "where their defaults agree", nothing for the other case)?

**Proposal.** The key of an intersection is the tuple of the components' keys (equal when each is equal); the candidates are the first four members of the intersection in the order of the first component's index; the attribute is `Compiled` where the defaults disagree.

### M4. `HasProperty{N, R}` "by the member's own `getproperty`" has no form on a value typed by its trait (traits §10.1, §4.3)

- `x.ps` lowers to `getproperty(x, :ps)` with a `Symbol` value, not a type. No method at a trait can select on it, and `getproperty(x::HasProperty{N,R}, ::Symbol)` would take every property of every member. Today the operation is `property(x, Val(N))` with TraitWorld's `_propget` hook (BaseTraits.jl:367–373); TDE's callbacks read `integ.ps[:σ]` through it (core.jl:95, 668–670; open issue 97).
- Under the draft, `integ.ps` on a `Dynamic{IntegratorView{…}}` or in erased code is `getproperty` on an abstract value: a run-time site with result `Any`, unless the library's `getproperty(d::Dynamic{X}, s)` (lowering §7) knows `X`'s `HasProperty` supertraits and asserts `R`. Not stated.

**Proposal.** Keep `property(x, Val(N))::R` as the operation. State that `x.N` on a value typed by a trait whose contract includes `HasProperty{N,R}` is lowered to that operation (the declared-field read of §7.9, generalized). A member's own `getproperty` conforms by giving `property(x, Val(N))` at `N`.

### M5. A `Dynamic{Callable}` at a second signature (traits §7.7)

- TDE keeps the right-hand side `Dynamic{Callable{CoreRHSSig{T},Nothing}}` and calls it at the duals (`_ad_jacobian!(prob.f, …)`, core.jl:455, 464; `m.f`, :519; problems.jl:136, 229), relying on the old "seen through every trait its object conforms to" (core.jl:424). Under §7.7 that call is a `MethodError`. `UserFunction`/`fplain` (core.jl:404–408, 443, 457–458) and Rodas5's `chunk_size` path (rodas5.jl:262–267) exist for the one case where the second signature is known only at `init`.
- Under the draft: `Dynamic{Callable{CoreDualSig{N},Nothing}}(unwrap(prob.f))` at each Jacobian (one small allocation per Jacobian), or a second field kept where the chunk is fixed (`DUAL_CHUNK`), with `unwrap` for Rodas5. Slightly worse than today; `unwrap` replaces the `UserFunction` box.

**Proposal.** No rule change. §7.7 states that re-targeting is `Dynamic{Callable{B,S}}(unwrap(d))`, and that `Dynamic{All{Callable{A,S}, Callable{B,S}}}` is the form where both signatures are known when the value is stored.

### M6. BaseTraits' operations become methods at open sets on Base's hottest functions (lowering §2; compiler §5.1)

- `Base.iterate`, `getindex`, `setindex!`, `length`, `haskey`, `resize!` each get the trait's method at `Iterable`, `Indexable`, … (BaseTraits.jl:38–82; lowering §2 "the trait's method for each operation"). Compiler §5.1 puts a method at an open set in the typemap's linear list, "a query at a member reaches it, since the member's supertype chain need not name the set".
- So every cache-missing dispatch of `getindex` or `iterate` in a session intersects with an open set: an entry walk per typename on the argument's chain (compiler §4.5). The ambiguity report at a membership (§5.4) runs over these functions too. The prototype put its methods on Base's functions at its concrete kept types (`HeldValue{X}`, the subtrait encoding of open issue 124), which the typename index serves; never at an open set. The cost is unmeasured. (Inferred.)

**Proposal.** Measure in W-99 on the forks' session. If it shows, BaseTraits declares no trait method on a Base function where every member serves by its own methods and no default exists (the trait's method is unreachable there except for `Dynamic{X}`); `Dynamic{X}`'s forwarding is then a method at the concrete `Dynamic{Iterable{T}}`, which the typename index serves.

### M7. The member hook runs contract checks inside dispatch (compiler §10.4; lowering §4)

- The checks are plain inference of each serving method (lowering §3 step 3). The hook runs "at dispatch, at a split's table miss, or at `keep`". W-84 measured 27 family members checked at load in 390–394 ms (forks README); ND's graph types conform at first use (E-154). Under the draft that cost lands inside the first dynamic dispatch at the member, inside `jl_apply_generic`, possibly reentrantly (the check's inference dispatches). The prototype ran the checks in its own entries, not in the runtime's dispatch. (Inferred.)

**Proposal.** §10.4 states that the hook runs before the instance lookup, outside every runtime lock, with a per-(member, set) "in progress" state that raises on a cycle; and that a package image's kept answers (lowering §4) are the normal path, so a session pays the check only for members no image checked.

### M8. C-21 silently breaks the NetworkDynamics port (compiler Deviations)

- `Network{EX,G,NL,VTup,MM,CT,GBT,LM,EM}` has nine parameters; its memberships in `IndexProvider{NWIndex}`, `HasSystem`, `HasMassMatrix`, `HasJacobianPrototype` are families over all nine (symbolicindexing.jl:1148; network_structure.jl:362–368). Compiler C-21: "A pattern with more than eight type variables is accepted and never matches." On branch `unified` the port's memberships would hold nowhere, with no error. (Verified: both texts.)

**Proposal.** Lift the limit, or refuse such a pattern at `jl_declare_membership`, before W-102.

---

## 4. Low findings

- **L1. `struct S <: X` before its `@implement`.** §5.2 raises `ImplementError` at a use before the declaration; §5.10 and lowering §4 keep a failure "and every use of it through the trait raises the same `ImplementError`". The `@implement` must replace the kept failure; lowering §3 should say so.
- **L2. TraitMakie's `Base.convert(::Type{ColorSpec}, x) = _color(x)`** (TraitMakie.jl:88): with `ColorSpec` an abstract type, Base's `convert(::Type{T}, x::T) where T` and this untyped catch-all both apply to a member; whether Julia ranks them needs checking (the prototype never met Base's method, since the field was `Kept`). The port types its sources, as §8.1's example does.
- **L3. "The first four members declared"** (§7.9, P-15): a library has no say. PlotCore's first four are `Lines`, `Scatter`, `Bars`, `VLines` (PlotCore.jl:473–476); `Stairs`, `Hist`, `Band` and every user recipe take the table. The prototype's `register_dynamic_candidate!` let the library choose; compiler §7.2 keeps it only for keys that are not sets. Offer the trait author a choice (`@candidates`), or state that the table's one indirect call is the design.
- **L4. Compiling ahead of split targets** (traits §16; compiler §7.3) needs the call's other argument types. For `condition(cb::Bounce, u, t, integ::IntegratorView{…})` they are known only at a solve (`ParamIntegrator{…}`). State what is compiled ahead for an operation with abstract further arguments.
- **L5. `@trait_module` "as a module's first statement"** (§13) contradicts its own example (`using TraitWorld` first) and LorenzModels.jl:9–10. Say "before the module's first method", and whether `Base.Experimental.@compiler_options` is honoured there.
- **L6. A family bound that is a `Union`** (`@implement BoundedText I where {I <: Base.BitInteger}`, BaseTraits.jl:434) has no pattern form in compiler §4.2 (`S`, `S{T} where T`, an abstract type, a set instance, `Type{S}`). Add a `Union` pattern, or ten declarations.
- **L7. Open issue 82 stays.** Lowering §7's `Dynamic{X}(x)` is specialized per `typeof(x)`. Define it with `@nospecialize(x)` so that a wrap compiles nothing per value type; TDE's `@nospecializeinfer` wrappers (29) then go.
- **L8. Array literals.** `typejoin` reads declared supertypes only, so `[Circle(1.0), Square(2.0)]` is a `Vector{Any}` when the types joined by `@implement` and a `Vector{Shape}` when by `struct Circle <: Shape`. §10.2's example assumes the first; say it, since it decides whether `total(v)` dispatches.
- **L9. `first_seen` and the solver user.** `solve(prob, Tsit5())` from the prompt with a user's problem type (LorenzModels) makes the problem `Dynamic` (core.jl:540, reached through `solve_ode`'s `@nospecialize(prob)`): the right-hand side dispatches per call through the split. For scale, E-152 measured one network right-hand side at 0.50 µs (ndport README), so a dispatch per call is a visible fraction. The draft gives `@default_compiled` (§4.6, step 4). §7.10 should name which of the ports' traits want it (`ODEProblemTrait`, `VertexDynamics`) and which want `Dynamic` (`Plot`, `Column`). Also: the `Compiled` attribute does not survive storage, only `Dynamic{X}` does (§7.7, §8.1); say so, and that the split makes it unnecessary (TDE's core.jl:9–12 promise needs no form).
- **L10. Up to two compilation signatures per trait argument** (compiler §6.2): `pixels(pos, t, sx, sy)` (PlotCore.jl:336) and `drawbars` (4 trait arguments, :410) can have 2ⁿ variants beside the key products. Note the bound.

---

## 5. Claims that look wrong on their own terms

- Facts §10 and traits §9: a derived `Callable` membership ends only by a definition of the member's methods. False: `S` depends on the whole method table through the member's body (H1a).
- Compiler §7.4: subtyping and intersection "derive on demand". That is inference inside the type system (H1b).
- Traits §7.8, §8.2 and lowering §10: the `keep`/`typeof` constructor idiom, and `asvector`, are open methods under §7.3 and refused under §13's default (H2).
- Lowering §2: the family `Dynamic{X{P…}} where {P…}` does not make `Dynamic{Column}`, `Dynamic{Callable}` or `Dynamic{All{X,Y}}` (traits §3.6's example) members (M1).
- Traits §10.1: `HasProperty` by the member's own `getproperty` cannot be an operation a method at a trait serves (M4).
- Traits §7.5 step 4 for an intersection: "where their defaults agree" leaves the other case undefined (M3).
- Traits §5.2 against §5.10 and lowering §4: a kept failure for a missing `@implement` (L1).
- Compiler §4.2's pattern forms do not cover a `Union` bound (L6).

---

## 6. Across the prototypes

- **The ports' mechanical changes are small**: `Kept{X}` → `X`; `Opened{X}` → `@specialize x::X`; `(X, Y)` → `All{X, Y}`; `Dynamic{X}` on an argument → `X`; `@default_with_dynamic_self` → `@default_dynamic`; families state their instance; `@trait_module` becomes a statement; `conforms` → `isa`. The casts at calls keep their form.
- **The ports' architecture stands**: the two-layer integrator (W-63), the core's `Dynamic{StepView}` box, the recipe children, the column kernels, the batches. The draft removes the encodings around them, not the architecture.
- **Where the ports get worse** is where the draft adds a mechanism the prototype did not need: derived memberships (H1), the `bounded` default (H2), casts that cannot cross a plain front end (M2), the second signature of a wrapped function (M5), the nine-parameter limit (M8).
- **The most valuable tweak**: H1's proposal. It keeps dispatch by signature, keeps result types where they belong (declared, or decided by inference as values), and keeps inference out of subtyping. With it, TDE's front end can stay untyped and the forks' `byrow` stays one copy per cell type.
- **The second**: H2's. With `bounded` opt-in, every port module is a `@trait_module` as written; with it on, none is.

---

## Addendum (2026-11-06, the main session): what was done with each finding

The draft's choices named here are listed in its README (P-n) and in the decision log §9 as mine; open issue 144 asks the user to confirm them.

| Finding | Done |
|---|---|
| H1 | Open issue 143, for the user. The draft marks how `Callable` finds a function's result type Open (traits §9, compiler §7.4, facts §10, lowering §9); the form by inference is in `design/alternatives.md`. |
| H2 | P-20 (mine): `bounded` stays on in `@trait_module` (the user's Q2 (a)); a method open on purpose is marked `@open`; the two idioms are named as open; `Dynamic{X}(t)` and `keep(t)` keep a method fully bounded (traits §7.3, §7.8, §8.2, §13; compiler §6.7; lowering §5, §10). The proposal (`bounded` opt-in) is in `alternatives.md`. |
| M1 | P-5: the pattern `Dynamic{Z} where {P…, Z <: X{P…}}` (lowering §2); `X` must carry its parameters, `Dynamic{Column}` refused when made (traits §7.7, lowering §7). |
| M2 | P-23: a cast at a plain argument has no effect, listed by `detect_unused_casts`; a plain front end keeps the caller's choice by the value it stores (traits §7.6, compiler §6.9). |
| M3 | P-22: keys, candidates, the attribute and specificity at an intersection (traits §3.6, §7.2, §7.5, §7.9; compiler §4.9, §5.2, §6.1, §7.2). |
| M4 | P-27: `getproperty` at a constant name, typed `R` on a value known by its trait (traits §10.1, compiler §7.1, lowering §10). |
| M5 | Traits §7.7 states the second signature: wrap again, or `Dynamic{All{Callable{A, S}, Callable{B, S}}}`. |
| M6 | No rule change; a measurement for W-99 (the work queue's row). |
| M7 | P-18: the member hook checks only, outside every runtime lock, with a cycle raising; images' answers the normal path (compiler §10.4, lowering §4). |
| M8 | W-98: the uncommitted subtyping rule has no fixed bound on a pattern's variables (C-21); the nine-parameter memberships become a gate case (the work queue's row). |
| L1 | Traits §5.2, lowering §3: the `@implement` replaces the kept failure. |
| L2 | No rule change: for the Makie port (type the sources, traits §8.1). |
| L3 | Traits §7.9: declaration order is the design; a trait's package declares its common members first. |
| L4 | Compiler §7.3: targets compiled ahead where the other arguments are concrete. |
| L5 | `@trait_module` before the module's first method (traits §2, §13; lowering §1, §6; the README). |
| L6 | A `Union` bound declares one membership per type (compiler §4.2, lowering §3). |
| L7 | Lowering §7: the constructor takes `@nospecialize(x)`. |
| L8 | Traits §10.2: array literals join declared supertypes only. |
| L9 | Traits §7.10: `@default_compiled` for a hot inner call; only `Dynamic{X}` keeps an attribute through storage. |
| L10 | Compiler §6.2: up to 2ⁿ compilation signatures, each compiled only where asked. |
