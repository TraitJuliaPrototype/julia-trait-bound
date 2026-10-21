# The NetworkDynamics port, P6: inside out, under strict mode

Status: **proposal; part P6 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md).** Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) §10 and [`../reference/facts.md`](../reference/facts.md) above all). To be reviewed by another Opus agent before work starts.

**The user's words** (2026-10-21), on outside-in against inside-out:
- "I wonder whether inside-out under strict mode is a sensible strategy for trait porting core packages, even if they are not going to run under strict mode eventually. It forces the design to be piracy free at any step and can be done iteratively..."
- "Joint ownership is approved, build it to enable inside out. Note whether a different package structure could avoid it (or heavy use of implement over piracy), but if building joint ownership is simpler than restructuring SciML that is the pragmatic choice. Dual track is also go. For things like split packages I think you can decide yourself to add features that are highly orthogonal. Don't make changes to existing designs and features though..."

**The question:** can the SciML core under NetworkDynamics become trait modules from the bottom up, one step at a time, each step free of pirates under strict mode, with upstream's results? And what does each step buy: load protection for the solver's own code, and a cheaper first simulation once package images hold the code compiled by facts?

**What P6 does not do.**
- It writes no trait and no bounded function. Traits are P4's (the outside-in track).
- It changes neither a reference nor TraitWorld. It uses what is built: `@trait_module`, `@joint_owners`, strict mode, `owned_method`. A TraitWorld bug it finds becomes a deviation row or an open issue.
- It runs quick checks, not benchmarks. Measurement rounds belong to P5.

**Inputs.**
- The meta plan: its ground rules, its choices 1–14; the graph plan's choices 15–22 ([`2026-10-21-ndport-graph.md`](2026-10-21-ndport-graph.md) §8).
- E-151 and E-153: [evidence §1, §3](../design/evidence.md); `ndport/README.md`; [the P3 plan](2026-10-21-ndport-facts-first.md).
- The pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (P3-1: Static's promotion, facts §8).
- The census `ndport/logs/p3/census-P0.log` (TraitWorld e9f4bfe, before joint owners).
- Joint owners as built: [traits §10.1](../reference/traits.md#101-who-may-implement), [§10.2](../reference/traits.md#102-pirates), [§10.3](../reference/traits.md#103-strict-mode); [facts §1](../reference/facts.md#1-terms), [§10.2](../reference/facts.md#strict-mode); `TraitWorld/src/ownership.jl` (`@joint_owners`, `owns`), `TraitWorld/test/joint.jl` (TraitWorld a373e30).
- The alternatives entry "Split packages" ([`../design/alternatives.md`](../design/alternatives.md)).
- The wrap: [porting guideline 0.1a and B5](../intro/porting.md); `git -C ndport/pkgs/NetworkDynamics-p3wrap diff upstream`.
- Images and keep-compiled: [lowering §2](../reference/lowering.md#2-modes-owners-and-images), [facts §11](../reference/facts.md#package-images).
- The dependency graph: `ndport/env_upstream/Manifest.toml`, `ndport/env_p3/Manifest.toml`, the clones' and the depot's `Project.toml` files.

No Julia was run for this plan: the lock is in use by the port's agent. Counts of rebuilt packages come from `env_p3/Manifest.toml` by a script over the manifest. Paths are relative to the repository root; line references are to the clones in `ndport/pkgs/` at `upstream`, and to the depot's copies (`~/.julia/packages/<Name>/<slug>`) for packages not cloned.

---

## 0. Summary

- **The order:** the SciML core, bottom-up, in seven steps. NetworkDynamics stays wrapped on top, as in setting N (P3's `p3-wrap`, read only).
  1. SymbolicIndexingInterface and RecursiveArrayTools;
  2. SciMLBase, with `@joint_owners` and eight one-line moves;
  3. NonlinearSolveBase and BracketingNonlinearSolve;
  4. the NonlinearSolve family (the fixed point's path);
  5. DiffEqBase;
  6. OrdinaryDiffEqCore, OrdinaryDiffEqTsit5 and DiffEqCallbacks (the integrator's driver);
  7. OrdinaryDiffEqDifferentiation and OrdinaryDiffEqRosenbrock.
- **Left plain:** ForwardDiff, LinearSolve, Static, the small interface packages (CommonSolve, SciMLOperators, ADTypes, ArrayInterface and others), the plotting side (Makie, GraphMakie, CairoMakie, Observables, NetworkLayout) and Graphs (P4's). The reasons are in §1.2.
- **The census's 63 pirates, classified** (§2):
  - (a) a joint owner's method: **49**. SciML's 45 need one line in SciMLBase, `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve`, with LinearSolve expected from the extended census. Makie's 4 would need ComputePipeline to name Makie; deferred.
  - (b) avoidable by a different structure: **13**. Eight are one-line moves into SciMLBase or a narrowing to an owned type, made in step 2. Five are Makie's and GraphMakie's, deferred.
  - (c) avoidable by an implementation of a trait: **0**. A pirate names no type its definer owns, and an implementation follows ordinary ownership ([traits §10.1](../reference/traits.md#101-who-may-implement)).
  - (d) a true pirate: **1**, Makie's `Base.deepcopy(::Observable)`; deferred.
- **Could a different structure avoid joint ownership?** In principle, yes: move SciML's front ends into SciMLBase. That is restructuring SciML: DiffEqBase's front end alone is about 1,400 lines with its own dependencies. Joint owners are the pragmatic choice; one-line moves are made where they exist.
- **Each step shows, cheaply** (§3):
  - the workload's digests equal to U's, bit for bit;
  - with strict mode on, no refusal, and no pirate left in a wrapped package;
  - the first simulation's cost against N's 37.8 s and U's 21.5 s;
  - at two milestones, order B: what the plotting load takes from the core's code;
  - the precompile cost of the step.
- **The tracks meet** after P6's step 6 and before P4's step 4 (`ODERHS`), in a fresh environment (§4). P4's step 4 needs bounded code in the solver's packages, and bounded functions exist only in trait modules.
- **About 9 builds and 22 sessions** through the lock, roughly 1.5–2 hours of lock time, spread between P4's runs (§3.4).

---

## 1. The order

### 1.1 The dependency graph, the part that matters

Each package with the stack's packages it depends on (`env_upstream/Manifest.toml`), bottom first:

| Package | Depends on (of the stack) |
|---|---|
| SymbolicIndexingInterface | — (leaves only: Accessors, ArrayInterface, RuntimeGeneratedFunctions, StaticArraysCore) |
| RecursiveArrayTools | SymbolicIndexingInterface |
| SciMLBase | RecursiveArrayTools, SymbolicIndexingInterface; plain: CommonSolve, SciMLOperators, SciMLStructures, ADTypes, ArrayInterface, PreallocationTools, FunctionWrappersWrappers |
| NonlinearSolveBase | SciMLBase, RecursiveArrayTools, SymbolicIndexingInterface |
| BracketingNonlinearSolve | NonlinearSolveBase, SciMLBase |
| LinearSolve (plain) | SciMLBase, RecursiveArrayTools |
| SciMLJacobianOperators | SciMLBase |
| NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve | NonlinearSolveBase, SciMLBase; LinearSolve (the first two), SciMLJacobianOperators (FirstOrder), BracketingNonlinearSolve (Simple) |
| NonlinearSolve | the four above, BracketingNonlinearSolve, NonlinearSolveBase, LinearSolve, SciMLBase |
| DiffEqBase | BracketingNonlinearSolve, SciMLBase, RecursiveArrayTools, SymbolicIndexingInterface |
| OrdinaryDiffEqCore | DiffEqBase, SciMLBase, RecursiveArrayTools |
| OrdinaryDiffEqTsit5 | OrdinaryDiffEqCore, DiffEqBase |
| OrdinaryDiffEqDifferentiation | OrdinaryDiffEqCore, DiffEqBase, LinearSolve; plain: ForwardDiff |
| OrdinaryDiffEqRosenbrock | OrdinaryDiffEqDifferentiation, OrdinaryDiffEqCore, DiffEqBase, LinearSolve |
| DiffEqCallbacks | DiffEqBase, SciMLBase, RecursiveArrayTools |
| NetworkDynamics | NonlinearSolve, DiffEqBase, DiffEqCallbacks, SciMLBase, RecursiveArrayTools, SymbolicIndexingInterface, LinearSolve, SteadyStateDiffEq; plain: Graphs, Static, ForwardDiff |

- NetworkDynamics depends on DiffEqBase, not on OrdinaryDiffEqCore. The workload loads Tsit5 and Rosenbrock itself.
- DiffEqBase depends on BracketingNonlinearSolve, and so on NonlinearSolveBase. The nonlinear base comes before DiffEqBase.
- NonlinearSolve does not depend on DiffEqBase. So the fixed point's path (step 4) can come before the solver (step 5).

### 1.2 What is wrapped, what stays plain

| Package | P6 | Why |
|---|---|---|
| SymbolicIndexingInterface, RecursiveArrayTools | wrapped (step 1) | The bottom of SciML's interfaces. The solution access of step e. No pirates. |
| SciMLBase | wrapped (step 2) | The interface: problems, solutions, callbacks, `__solve`. Owner of every split pair. |
| NonlinearSolveBase, BracketingNonlinearSolve | wrapped (step 3) | Below DiffEqBase and NonlinearSolve. E-153's order B lost 209 of NonlinearSolveBase's CodeInstances in P0. |
| NonlinearSolve, NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve, SciMLJacobianOperators | wrapped (step 4) | The fixed point's path. E-153: most of N's extra 16 s is this code, compiled by facts in the session. |
| DiffEqBase | wrapped (step 5) | `solve`'s front end, `promote_f`, the callbacks' root finding. |
| OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, DiffEqCallbacks | wrapped (step 6) | The integrator's driver. In N it is plain, because `solve` is called from plain code. |
| OrdinaryDiffEqDifferentiation, OrdinaryDiffEqRosenbrock | wrapped (step 7) | Rodas5P's Jacobian and steps. |
| NetworkDynamics | wrapped from the start (P3's `p3-wrap`, read only) | The outer shell. N is known good, and E-153's numbers are against it. |
| ForwardDiff | plain | A leaf. Wrapped callers reach its code by facts already. Wrapping it protects only its plain callers. It also keeps E-153's pirate case (a method on ForwardDiff's duals) a foreign package's. |
| LinearSolve | plain | Large: Krylov, MKL and many extensions. Reached only through wrapped callers. Its front end is of the split kind (`SciMLBase.init(prob::LinearProblem, args...)`, `src/common.jl`), so it is expected to join SciMLBase's joint owners anyway (§2.4). |
| Static | plain, with P3's fix | A leaf below NetworkDynamics. Wrapped callers reach it by facts. |
| CommonSolve, SciMLOperators, SciMLStructures, ADTypes, ArrayInterface, PreallocationTools, FunctionWrappersWrappers, LineSearch, SciMLLogging, OrdinaryDiffEqRosenbrockTableaus | plain | Small interfaces and utilities, reached by facts from wrapped callers. No code of their own on the hot path that a plain caller reaches. |
| SteadyStateDiffEq | plain | Not on tier S's path (`find_fixpoint` calls NonlinearSolve). |
| Makie, GraphMakie, CairoMakie, Observables, NetworkLayout | plain | The plotting side is outside. Makie compiled by facts in the session costs the first plot 48.5 against 16.0 s (E-153, W). It has 10 pirates by the letter, some needing Makie's macro changed (§2). |
| Graphs | plain | P4's graph step declares `GraphInterface` in it as plain code (choice 16). |
| The wrapped packages' extensions | plain | An extension is a module of its own ([porting 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)). It counts as its parent for ownership, so a joint owner's extension is a joint owner too. |

### 1.3 The steps

Each step is one commit per changed tree, tagged `p6-s<k>`. "Rebuilt" counts the step's packages and their dependents in `env_p3`'s manifest, packages and extensions apart.

| Step | Wrapped | Declarations | Pirates resolved | Rebuilt | Precompile (estimate) |
|---|---|---|---|---|---|
| S0 | none: the P6 trees at `upstream`, NetworkDynamics as in N | — | — (the extended census) | every path-sourced package and its dependents | 3–5 min |
| S1 | SymbolicIndexingInterface, RecursiveArrayTools | — | none needed (0 by the census) | 21 + 38 | 2–3 min |
| S2 | SciMLBase | `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve`, plus the names S0's census adds | DiffEqBase's 23 and NonlinearSolve's and NonlinearSolveBase's 22 by joint ownership; 8 by the moves (DiffEqBase 5, OrdinaryDiffEqCore 3) | 19 + 29 | 2 min |
| S3 | NonlinearSolveBase, BracketingNonlinearSolve | — | NonlinearSolveBase's 12, already held by S2's line | 15 + 18 | 1.5 min |
| S4 | NonlinearSolve, NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve, SciMLJacobianOperators | — | NonlinearSolve's 10, already held by S2's line | 17 + 18 | 1.5 min |
| S5 | DiffEqBase | — | none left | 8 + 7 | 1 min |
| S6 | OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, DiffEqCallbacks | — | none left (S2 moved OrdinaryDiffEqCore's 3) | 7 + 3 | 1 min |
| S7 | OrdinaryDiffEqDifferentiation, OrdinaryDiffEqRosenbrock | — | none expected (Rosenbrock 0; Differentiation: S0's census) | 2 + 1 | 0.5 min |

- **The estimates** scale E-151's 175 s for 72 packages in `env_port`. A wrapped package's workload is compiled by facts. That cost NetworkDynamics nothing (18.2 against 22.0 s plain), but SciMLBase is larger. Each step records its measured time and the number rebuilt.
- **Zero-pirate neighbours are grouped** to save builds: SymbolicIndexingInterface with RecursiveArrayTools, the NonlinearSolve family, the integrator's driver with Tsit5 and DiffEqCallbacks.
- **The fixed point before the solver.** Step 4 precedes step 5 because the workload runs step c before step d, and E-153 puts most of N's extra cost in step c.
- **A step's packages are wrapped only when no pirate of theirs is left,** by the census with joint owners counted. Otherwise the step stops, and the pirate is classified (§2) before the step is retried.

### 1.4 The wrap, per package

The same three lines as P3's, and TraitWorld in `[deps]`:

```julia
module SciMLBase
using TraitWorld: TraitWorld, @trait_module, @joint_owners      # 1
@trait_module begin                                              # 2
@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve      # SciMLBase only (S2)
# … the package as it is: its `@max_methods 1` block, its includes, its workload …
end # @trait_module                                              # 3
end
```

- **Only SciMLBase declares joint owners.** `@joint_owners` must stand at the top level of the owner's own module (`ownership.jl`: `owner(__module__) === __module__`). Inside the `@trait_module` block it still does.
- **No other package needs a declaration** for the census's pirates:
  - NonlinearSolve's methods of NonlinearSolveBase's `initialization_alg` name SciMLBase's problem types. NonlinearSolve owns them through SciMLBase's line (`owned_method` asks whether the definer owns the function *or a type*).
  - OrdinaryDiffEqCore's three are moved (§2.2).
- **The declaration's names** come from S0's extended census, not only from the P0 census (§2.4).
- **The moves of step 2** change three trees in one step: SciMLBase gains the methods, DiffEqBase and OrdinaryDiffEqCore lose them. A method defined twice fails precompilation, so the three changes go together.
- **TraitWorld becomes a dependency** of every wrapped package. From step 1 on, every session that loads SymbolicIndexingInterface loads TraitWorld. The load times are recorded per step.
- **`delegate!` is not used.** `KNOWN_DELEGATES` names `SciMLBase => OrdinaryDiffEq` (`TraitWorld/src/strict.jl:26`). That package is never loaded in the workload, so every acceptance in P6 comes from joint owners. The census prints which methods rest on them.

---

## 2. The pirates of the census, classified

The census by the letter (`TraitWorld.owned_method`, TraitWorld e9f4bfe, P0, `ndport/logs/p3/census-P0.log`): DiffEqBase 28, NonlinearSolveBase 12, NonlinearSolve 10, Makie 8, OrdinaryDiffEqCore 3, GraphMakie 2; the others 0. Each keyword method (`Core.kwcall`) is counted apart from its positional method, as the census counts them.

### 2.1 The classes

| Class | Meaning | Count | P6's choice |
|---|---|---|---|
| (a) | a joint owner's method, held by the owner's declaration | 49 (SciML 45, Makie 4) | SciML: declared in step 2. Makie: deferred. |
| (b) | avoidable by a different structure: the method moves to the package that owns the function or a type, or is narrowed to an owned type | 13 (SciML 8, Makie 3, GraphMakie 2) | SciML: the 8 moves in step 2. Makie's and GraphMakie's: deferred. |
| (c) | avoidable by an implementation of a trait instead of a method | 0 | — |
| (d) | a true pirate, to remove or move | 1 (Makie) | deferred |

**Why class (c) is empty.**
- An implementation is a method. Only the trait's owner or the type's owner may write it ([traits §10.1](../reference/traits.md#101-who-may-implement)).
- A pirate, by definition, names no type its definer owns. And the functions here are SciMLBase's, CommonSolve's or Base's.
- So the definer could implement only a trait it declares itself. The owner's code could not call that trait, since the owner does not depend on its implementers.
- An implementation helps only after a restructure: if a hook took a value of the provider's own type (a wrapper backend, a default algorithm), the provider would implement for that type. That is class (b) first.

### 2.2 Per group

| # | Group | Package | n | Examples (file:line) | Class | A different structure? An implementation? | Now |
|---|---|---|---|---|---|---|---|
| G1 | `solve` and `init` on SciMLBase's problem types: the front end | DiffEqBase | 14 | `solve(prob::AbstractDEProblem, args...)` `lib/DiffEqBase/src/solve.jl:653`; `init(::AbstractDEProblem, …)` `:150`; jump problems `:164`, `:720`; noise `:716`; `PDEProblem` `:732`, `:739` | a | Structure: move the front end into SciMLBase (about 1,400 lines of `solve.jl`, with DiffEqBase's dependencies and extensions), or the problem types out of SciMLBase (every SciML package names them). Implementation: no; `solve` is CommonSolve's, the types SciMLBase's. | joint owner |
| G2 | SciMLBase's internal entries `__solve`, `__init` | DiffEqBase | 4 | `__solve(::AbstractDEProblem, …)` `solve.jl:1320`; `__init` `:1336` | a | As G1. | joint owner |
| G3 | hooks SciMLBase declares and DiffEqBase fills, with no owned type in the signature | DiffEqBase | 5 | `wrapfun_iip(ff, inputs)` `norecompile.jl:31`, with `::Val` `:38`; `wrapfun_oop` `:48`; `promote_tspan` with five untyped arguments `solve.jl:858`; `report_integrator_failure(::DEIntegrator, ::Val)` `check_error.jl:33` | a | Structure: `promote_tspan`'s eight lines could move into SciMLBase. `wrapfun_*` need DiffEqBase's `Void` and its ForwardDiff extension's methods; `report_integrator_failure` needs its verbosity settings. Implementation: only if the hook took a backend value of the provider's type (SciMLBase's docs call DiffEqBase a "wrapper-provider package", `SciMLBase.jl:2066`–`2126`). | joint owner |
| G4 | Base's `isempty` on SciMLBase's callback types | DiffEqBase | 3 | `Base.isempty(cb::CallbackSet)` `callbacks.jl:81`; `isempty(::AbstractContinuousCallback) = false` `:84`; `isempty(::AbstractDiscreteCallback) = false` `:85` | b | One line each, into SciMLBase, which owns the types and defines the callbacks. | **moved (S2)** |
| G5 | SciMLBase's wrapper predicates on FunctionWrappers' type | DiffEqBase | 2 | `SciMLBase.isfunctionwrapper(x::FunctionWrapper) = true` `DiffEqBase.jl:116`; `unwrap_fw(fw::FunctionWrapper) = fw.obj[]` `norecompile.jl:26` | b | One line each, into SciMLBase's `function_wrappers.jl`. SciMLBase already depends on FunctionWrappersWrappers, which depends on FunctionWrappers; FunctionWrappers joins SciMLBase's `[deps]`. | **moved (S2)** |
| G6 | the nonlinear front end and entries | NonlinearSolveBase | 12 | `solve(prob::AbstractNonlinearProblem, args...)` `src/solve.jl:76`; `init` `:231`; `__solve` `:634`; `__init` `:647`; `CommonSolve.solve(::HomotopyProblem, ::Nothing, …)` `src/homotopy_sweep.jl:898`; `solve(::HomotopyProblem)` `:904` (NonlinearSolveBase 2.55.0) | a | As G1, for NonlinearSolveBase. | joint owner |
| G7 | the default algorithm, chosen when `alg` is `nothing` | NonlinearSolve | 8 | `SciMLBase.__init(prob::NonlinearProblem, ::Nothing, args...)` `src/default.jl:25`; `__solve` `:40`; on `AbstractSteadyStateProblem`, an alias of `AbstractNonlinearProblem` (`SciMLBase.jl:351`), `:59`, `:65` (NonlinearSolve 4.32.0) | a | Structure: SciMLBase would choose the default, but it knows no solver; or a registry keyed by problem type. Implementation: no owned type; the algorithm is `nothing`. | joint owner |
| G8 | NonlinearSolveBase's initialization hook | NonlinearSolve | 2 | `NonlinearSolveBase.initialization_alg(prob::AbstractNonlinearProblem, autodiff)` `default.jl:71`; on `HomotopyProblem` `:88` | a | Structure: no; the result is NonlinearSolve's own polyalgorithm type, which NonlinearSolveBase cannot name. Held by SciMLBase's line, since the signature names SciMLBase's types. | joint owner |
| G9 | OrdinaryDiffEqCore's methods of SciMLBase's functions | OrdinaryDiffEqCore | 3 | `isadaptive(alg) = false` `alg_utils.jl:312`; `SciMLBase.interp_summary(::Type{cacheType}, dense::Bool) where {cacheType}` `interp_func.jl:73`; `EnzymeRules.inactive_noinl(::typeof(check_error!), args...)` `enzyme_rules.jl:25` | b | `isadaptive`: the fallback of SciMLBase's own function, one line into SciMLBase. `interp_summary`: narrowed to `cacheType <: OrdinaryDiffEqCache`, the type its callers pass (`interp_func.jl:71`, and the `CompositeCache` method below it). `inactive_noinl`: one line into `SciMLBaseEnzymeExt`, which holds SciMLBase's Enzyme rules; the rule is read only when Enzyme is loaded, which is that extension's trigger. | **moved (S2)** |
| G10 | Makie's methods of ComputePipeline's functions | Makie | 4 | `ComputePipeline.add_input!(::ComputeGraph, ::Symbol, ::ShaderAbstractions.UpdatableArray)` `Makie/src/compute-plots.jl:5`, `:16` (the code's own TODO asks whether it belongs in ComputePipeline); `map_latest!(f, ::Observable, …)` `interaction/observables.jl:89` | a | ComputePipeline is a package of Makie's repository; it would name Makie. Structure: `add_input!` into a ComputePipeline extension on ShaderAbstractions. | deferred (Makie plain) |
| G11 | one-line moves on the plotting side | Makie | 3 | `Observables.to_value(::Computed)` `compute-plots.jl:900`, `Base.notify(::Computed)` `:901`: into ComputePipeline, which owns `Computed` and depends on Observables; `GeometryBasics.collect_with_eltype(::Type{T}, ::ShaderAbstractions.Buffer{T})` `conversions.jl:2435`: into ShaderAbstractions, which depends on GeometryBasics | b | One line each. | deferred |
| G12 | Base's `deepcopy` changed for Observables' type | Makie | 1 | `Base.deepcopy(obs::Observable) = Observable{Any}(to_value(obs))` `attributes.jl:51` | d | Moving it would change `deepcopy` for every user of Observables. The principled form is a function of Makie's own at its call sites. | deferred |
| G13 | Makie's `@recipe` registers a plot type by `Val{symbol}` | GraphMakie | 2 | `Makie.symbol_to_plot(::Val{:GraphPlot})`, `(::Val{:EdgePlot})`; the method's line is in Makie's macro (`recipes.jl:192`, `:542`) | b | A different structure in Makie's macro: register by the plot type, which the recipe package owns (the macro already writes `plotsym(::Type{<:PlotType})`). No joint owner fits: Makie cannot name every recipe package. | deferred |

**The answer the user asked for, per group.**
- **G1, G2, G6:** a different structure avoids them only by moving SciML's front ends into SciMLBase, or SciMLBase's problem types out of it. That is restructuring SciML. Joint owners are simpler.
- **G3, G7, G8:** hooks and defaults declared in the interface and filled by "the" provider, with no type of the provider's in the signature. A structure without them needs a backend value of the provider's type in every call. That is a change to SciMLBase's interface. Joint owners are simpler.
- **G4, G5, G9:** one-line moves, principled in the sense of Static's fix: the method goes where the function or the type is owned. Made in step 2. With them, OrdinaryDiffEqCore needs no joint ownership at all.
- **G10–G13:** the plotting side stays plain in P6. Recorded for when it is wrapped.
- **Implementations of traits avoid none of the 63** (class (c), above).

### 2.3 What the P0 census does not cover

- **Packages outside its list.** It covered 17 packages. The wrapped set and its neighbours include more: BracketingNonlinearSolve, the NonlinearSolve family, SciMLJacobianOperators, LinearSolve, OrdinaryDiffEqDifferentiation, SteadyStateDiffEq, SciMLOperators, CommonSolve and others.
  - LinearSolve is expected to show the front-end pattern: `SciMLBase.init(prob::LinearProblem, args...)`, `SciMLBase.solve(prob::LinearProblem, args...)` and `solve(::LinearProblem, ::Nothing, …)` in its `src/common.jl`.
  - S0's **extended census** covers every loaded package (§3.1).
- **Methods the wrap's own check misses.** A trait module refuses a pirate at its definition only for definitions it recognizes ([T-56](../reference/traits.md#17-deviations)). DiffEqBase's `solve` and `init` are defined under `Base.@constprop :aggressive` (`solve.jl:150`, `:653`), so the wrap alone would not refuse them. **The census after loading is the check,** at every step.
- **Pirates loaded before the code they would change.** Strict mode does not refuse these yet ([facts F-6](../reference/facts.md#deviations), Planned). In a bottom-up order, the wrapped core loads before its implementers, so their methods arrive after the core's code. A plain leaf below the core cannot name the core's types. The census covers what remains.

### 2.4 The joint-owner declarations that result

- **SciMLBase:** `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve`, holding G1–G3 and G6–G8 (45 methods).
- **Additions from S0's census** follow one rule. A package is named if its pirates are of the split kind: a front end, `__solve`/`__init`, a default algorithm or a hook of SciMLBase's interface. LinearSolve is expected. A pirate of another kind is classified (b) or (d), and moved or removed before the step that needs it.
- **A package is named even if it stays plain** (LinearSolve). Strict mode refuses a winning pirate whatever its definer's mode, and naming it keeps the result independent of which facts SciMLBase's image happens to hold.
- **What each name costs** ([traits §10.1](../reference/traits.md#101-who-may-implement), "What it costs"): the joint owner's methods are a stakeholder's change. They may discard SciMLBase's code compiled by facts (facts §2.2's exception), and strict mode does not refuse them. S2 measures how much of SciMLBase's image their loads discard (§3.1, check J).
- **Later, for the plotting side:** ComputePipeline would name Makie (G10).

---

## 3. What each step must show, cheaply

### 3.1 The checks

| Check | How | Pass |
|---|---|---|
| **P** precompile | `env_p6` through the lock, `JULIA_NUM_PRECOMPILE_TASKS=4`, niced, `JULIA_TW_STRICT=1`; a script like `p4_precompile.sh` (`p6_precompile.sh`) | builds; no `OwnershipError`; no `PirateError` when images load; the wall time and the number rebuilt recorded |
| **R** results | the workload, P1's order, `NDW_STRICT=1`; `compare_digests.py --exact` against E-151's U log | all digests equal, bit for bit |
| **S** strict mode | the same session's log | no `PirateError`, at load or later. A warning for a package extension's winning method is allowed; each is listed with the method and the code it affects. |
| **C** census | `scripts/p6_census.jl` (new), strict mode on; every loaded package, not only P3's 17. Per pirate: the definer, the owners of the function and of each type. Per package: `wrapped` (its root module has the facts option), `pirates` (with joint owners counted), `joint` (the methods that are pirates without joint owners and owned with them) | pirates in wrapped packages: 0. Pirates elsewhere that name a wrapped package's function or type: listed, each classified before the step that would wrap its definer. |
| **F** first simulation | the R session's first pass: steps a–e, and c and d apart | recorded against I0 (N's 37.8 s) and U's 21.5 s. No pass rule: the expectation is a fall, step c at S4 and step d at S6. At the milestones, the attribution (`NDW_DIAG=1`): new CodeInstances per step by module and owner. |
| **T** steady state | the R session's "again" pass, step d | within 10 % + 5 ms of I0's. Otherwise the dispatch profiler (`p3_hot.jl`) on the steady state, and a fix in the owning package before the next step, as P3-1's ([porting B5](../intro/porting.md)). |
| **L** loads | the R session's load lines | recorded; TraitWorld is loaded from step 1 on |
| **J** joint owners' loads | S2 and S7 only: `scripts/p6_loadinv.jl` (new), strict mode off, Julia's invalidation log on while the stack loads | the CodeInstances of the facts owner whose method is SciMLBase's, discarded when a joint owner loads (image validation, or invalidation by the joint owner's methods). Recorded; a large share is pushback PB-16. |
| **B** order B | milestones S4 and S7: `NDW_ORDER=simfirst`, strict mode off (strict mode and the invalidation log share the switch, P3's risk 10); `p3_loads.jl` | lost CodeInstances by module and owner; each lost CodeInstance of the facts owner classified by facts §2.2's route, or a G2 failure (an open issue and a work item; P6 pauses). The modules of the wrapped packages lose none of their plain code (it no longer exists for the workload's path). "After" recompiles at most N's 0.04 s, plus 0.5 s. Digests of "after" equal. |
| **X** the pirate | S7 only: `p3_pirate.jl`, strict mode on and off | strict on: refused, and the refusal's caller (`_trait_root(e.caller)`) also names SciML code, not only NetworkDynamics'; strict off: the losses of the facts owner by module. P0's control from E-153 stands. |

**What the expected numbers mean.**
- **The first simulation should fall** as images hold the facts-compiled code that NetworkDynamics' trait code reaches. Each wrapped package's own precompile workload compiles under the facts owner, and keep-compiled keeps the code it compiles for other packages' methods ([lowering §2](../reference/lowering.md#2-modes-owners-and-images)).
- **It will not fall to U's 21.5 s by wrapping alone.** Code specialized on NetworkDynamics' types is in no SciML workload. Only NetworkDynamics' own workload can put it into an image. That is P4's (its S4 makes the workload `TraitWorld.@workload`). Until the tracks merge, P6 keeps P3's workload, so the two effects stay apart.
- **It may rise at step 6.** The workload's `solve(prob, Tsit5())` comes from plain code. Once OrdinaryDiffEqCore is a trait module, the driver it reaches is compiled by facts, and only Tsit5's own workload types are in its image. F records it as it is.
- **Order B's protection extends to the core.** In E-153, P0 lost NonlinearSolveBase 209 and SciMLBase 61 CodeInstances to the plotting load, and N still lost 2,884 plain ones. After S4 and S7 those modules' code on the workload's path is of the facts owner. Its losses must be 0, or explained.
- **Expected explained losses:** the stakeholders' extensions that the plotting load activates (`SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt`, `RecursiveArrayToolsStructArraysExt`). With the core wrapped they are a stakeholder's change to the core's code: followed, with strict mode's warning where a method wins without mentioning its triggers' types ([traits §10.3](../reference/traits.md#103-strict-mode)). P3's expected pushback (d) becomes PB-21.

### 3.2 The settings and environments

- **Trees** (each on a branch `p6-inside-out` from the tag `upstream`, as the meta plan's choice 8 asks):
  - git worktrees of the clones: `ndport/pkgs/SymbolicIndexingInterface-p6`, `RecursiveArrayTools-p6`, `SciMLBase-p6`, `DiffEqCallbacks-p6`;
  - `ndport/pkgs/OrdinaryDiffEq-p6`, a worktree of the monorepo at `upstream` (53e7d1d): DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5 and OrdinaryDiffEqDifferentiation. Their trees match the manifest there (Differentiation 57ebe5c7…, Tsit5 371de3eb…; checked for this plan with `git rev-parse upstream:lib/<Name>`);
  - `ndport/pkgs/OrdinaryDiffEq-p6-ros`, a worktree at 14f664a, for OrdinaryDiffEqRosenbrock alone: at `upstream` its tree differs from the release (`dbd63471…` against the manifest's `4d635452…`);
  - **the NonlinearSolve family** (NonlinearSolve 4.32.0, NonlinearSolveBase 2.55.0, BracketingNonlinearSolve 1.12.8, NonlinearSolveFirstOrder 2.10.0, …QuasiNewton 1.15.3, …SpectralMethods 1.8.3, SimpleNonlinearSolve 2.14.6, SciMLJacobianOperators 0.1.20): not cloned yet. Each becomes a repository `ndport/pkgs/<Name>-p6` made from the depot's exact tree (`~/.julia/packages/<Name>/<slug>`), committed and tagged `upstream`. Its tree hash is checked against the manifest's `git-tree-sha1`. `clone.sh` gains a `--from-depot` mode, and `VERSIONS.tsv` a row per package marked "from depot". No network is needed.
- **Read only, never changed by P6:** `ndport/pkgs/NetworkDynamics-p3wrap` (branch `p3-wrap`, e5425fd); `ndport/pkgs/Static.jl` (branch `trait-port`, c34adbb); the main clones of Graphs, Makie, GraphMakie, NetworkLayout, Observables (at `upstream`).
- **Never touched:** `env_port` and the main clones' trees (P0, A0); `~/.julia`'s caches for them; `pkgs/NetworkDynamics-p4`, `env_p4`, `depot-p4` (P4); `pkgs/Graphs-p4`, `pkgs/GraphMakie-p4` (E-154); `env_p3`, `depot-p3` (E-153's record).
- **`ndport/env_p6`:** `env_p3`'s project, its `[sources]` pointing at the P6 trees, plus the NonlinearSolve family, OrdinaryDiffEqDifferentiation and OrdinaryDiffEqRosenbrock by path. Resolved offline. Its manifest is committed per step.
- **`ndport/depot-p6`:** `JULIA_DEPOT_PATH=ndport/depot-p6:$HOME/.julia:`. Julia keeps at most ten cache files per package (`julia-1.13/base/loading.jl:3372`). Seven steps stay under it; a step rerun is built forward, not by going back.
- **The harness:** setting `I` in `scripts/run_workload.sh` (`env_p6`, `depot-p6`, TraitWorld loaded). The log header names each P6 tree's commit and the step tag.
- **Optional, at S7:** setting `IC`, the core alone. NetworkDynamics from its main clone at `upstream` (plain), in `ndport/env_p6c` with `depot-p6`. It shows what the wrapped core gives a plain user of NetworkDynamics: the integrator's driver and the fixed point protected without NetworkDynamics being a trait module. One extra build of NetworkDynamics and its extensions, and one session.
- **The builds:** julia-1.13 at the build then current; TraitWorld at a373e30 or later, loaded from source and not edited while a P6 job runs ([INDEX](../record/INDEX.md), "Standing constraints").

### 3.3 Per step, what runs

| Step | Builds | Sessions |
|---|---|---|
| S0 | 1 | C (extended census), R+S+F+T+L (I0) |
| S1 | 1 | C, R+S+F+T+L |
| S2 | 1 | C, R+S+F+T+L, J |
| S3 | 1 | C, R+S+F+T+L |
| S4 (milestone) | 1 | C, R+S+F+T+L, B, attribution |
| S5 | 1 | C, R+S+F+T+L |
| S6 | 1 | C, R+S+F+T+L |
| S7 (milestone) | 1 | C, R+S+F+T+L, J, B, attribution, X (strict on and off) |
| optional IC | 1 | R+S+F+T+L |

### 3.4 The cost

- **About 8 builds** of 0.5–5 minutes each (estimates of §1.3), plus one optional.
- **About 22 sessions** of 1–4 minutes each.
- **Roughly 1.5–2 hours of lock time,** spread between P4's runs. One Julia job at a time, through the shared lock, niced.

---

## 4. How the two tracks meet

**The tracks.**
- **P4, outside-in:** traits at the seams. Step 1, `ComponentDynamics` in NetworkDynamics (E-152, `pkgs/NetworkDynamics-p4`, `env_p4`, `depot-p4`). Step 2, `GraphInterface` in Graphs (E-154). Step 3, `VertexDynamics`/`EdgeDynamics`. Then `ODERHS` with the integrator's `f` kept, `IndexProvider`/`ValueProvider`, `Trajectory` ([the traits plan](2026-10-21-ndport-traits.md) §4).
- **P6, inside-out:** wraps, from SciMLBase's interfaces up to the solvers.

**Why they must meet before P4's step 4.**
- `ODERHS` is declared in SciMLBase. Its consumers are the solver's packages: DiffEqBase's `promote_f`, the integrator in OrdinaryDiffEqCore.
- Bounded functions exist only inside trait modules ([traits §2](../reference/traits.md#2-trait-modules)). The integrator's `f` kept as a `Callable` needs `ODEIntegrator` in a trait module (the traits plan §1.4).
- The traits plan's steps 4 and 7 wait for an answer on DiffEqBase's pirates. P6's step 2 is that answer; its step 6 makes the integrator's package a trait module.
- `IndexProvider` (SymbolicIndexingInterface) and `Trajectory` (SciMLBase) land in packages P6 wraps at steps 1 and 2.

**When.** When both hold:
- P6 has passed S6 (OrdinaryDiffEqCore wrapped, its checks passed);
- P4 has finished its step 2 or 3, whichever is current, with its outcome recorded.

P6's S7 may finish before or after the merge. It touches no package P4 changes.

**How.**
- **A fresh environment and depot,** `ndport/env_merged` and `ndport/depot-merged`:
  - NetworkDynamics from `pkgs/NetworkDynamics-p4` (P4's branch);
  - Graphs and GraphMakie from P4's worktrees;
  - SciML from P6's trees at their latest tag;
  - Static as before.
- One build, then one run of the workload strict on, the census, and the first simulation. The merged first pass is the first number with both effects: P4's workload in NetworkDynamics' image and P6's facts code in SciML's images.
- **After the merge, one line of work.** P4's later steps put their trait declarations on P6's trees, on the same `p6-inside-out` branches. `env_merged` becomes the port's environment. `env_p4` and `env_p6` stay as their tracks' records at their last tags.

**Conflicts to avoid until then.**
- **The same trees.** P6 never changes NetworkDynamics, Graphs or GraphMakie. P4 never wraps a SciML package, moves a pirate, or edits a SciML tree.
- **The same files in `ndport/`.** Both tracks add settings to `run_workload.sh` and rows to `README.md` and `VERSIONS.tsv`. Each edit is a small commit, made after re-reading the file.
- **The lock.** P6's builds are its longest jobs. They go between P4's runs, never in a chain.
- **TraitWorld.** Both load it from source. Neither edits it while the other runs. P6 needs no TraitWorld change; its census and scripts live in `ndport/scripts/`.
- **Static.** Both read `pkgs/Static.jl` at c34adbb. Neither changes it.
- **The depots.** Each track builds into its own depot only.
- **Experiment numbers.** E-152 and E-154 are P4's, E-155 is P6's. The merge's run is recorded under E-155's outcome, with E-152's or E-154's builds named.

**What each track gives the other.**
- P6 to P4: trait modules where SciML's bounded code can live; split pairs that strict mode accepts; facts-compiled code in SciML's images, which lowers the first-call cost P4 measures.
- P4 to P6: a network type that does not change with the equations (E-152's criterion 0), so the solver's code is compiled once per network shape; NetworkDynamics' workload in its image.

---

## 5. The experiment row

E-155, for [`../record/experiments.md`](../record/experiments.md) §11, registered before S0 runs:

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-155 | W-32 P6: the SciML core under NetworkDynamics made trait modules from the bottom up, under strict mode ([the inside-out plan](../plans/2026-10-21-ndport-inside-out.md)). Tier S, product setting, strict mode on for every check except order B; NetworkDynamics wrapped as in N (`p3-wrap`); P1's load order; one run per step. Steps S1–S7: SymbolicIndexingInterface and RecursiveArrayTools; SciMLBase with `@joint_owners` and eight one-line moves; NonlinearSolveBase and BracketingNonlinearSolve; the NonlinearSolve family; DiffEqBase; OrdinaryDiffEqCore, Tsit5 and DiffEqCallbacks; OrdinaryDiffEqDifferentiation and Rosenbrock. (1) Does each step precompile and run the workload with strict mode on, without a refusal, with U's digests bit for bit? (2) How many pirates does the census show in wrapped packages (target 0), and how many methods rest on joint ownership, per package? (3) What does the first simulation (steps a–e, first pass) cost per step, against N (37.8 s) and U (21.5 s), and by module at S4 and S7? (4) In order B at S4 and S7, what does the plotting load take, by module and owner, and is every loss of the facts owner explained by a route of facts §2.2? (5) Does strict mode refuse E-153's pirate on duals with the refusal's caller in SciML's code? (6) What does each step cost to precompile? (7) How much of SciMLBase's facts-compiled image do its joint owners' loads discard? Measures unchanged upstream code compiled by facts as trait modules (no trait code, neither interop nor idiomatic). **Would change the plan:** a refusal the census does not explain (a missing joint owner, or a true pirate to classify); an exact digest difference (a G1 failure: open issue); a steady-state step outside 10 % + 5 ms of I0 (a run-time site like P3-1's: a fix in the owning package before the next step); an unexplained loss in order B (a G2 failure: open issue and work item; P6 pauses); a large share of SciMLBase's image discarded by its joint owners' loads (pushback, and possibly an open issue on joint owners' cost); SciMLBase failing to wrap under `@trait_module`'s statement-by-statement treatment (porting 0.1a's open question; a TraitWorld deviation row); the first simulation not falling by S7 (then the images do not hold what the trait code reaches, and the lever is the workloads). | proposed (2026-10-21) | `ndport/` (its own repository): `scripts/p6_census.jl`, `p6_loadinv.jl`, `p6_precompile.sh`, `run_workload.sh` (settings `I`, `IC`), `clone.sh --from-depot`, `p3_loads.jl`, `p3_pirate.jl`, `p3_hot.jl`; `logs/p6/`; the trees `pkgs/*-p6` (branch `p6-inside-out`, tags `p6-s<k>`), `env_p6`, `env_p6c`, `depot-p6` | — | `ndport/README.md`; [the inside-out plan](../plans/2026-10-21-ndport-inside-out.md) |

- When E-155 is done, its outcome and an evidence row go in one commit (CLAUDE.md, rule 1).
- The porting guideline's B5 gains the lessons (the coordinator adds them). Its 0.1a text on split packages and `delegate!` predates joint owners and is a stale copy to fix then.

---

## 6. Expected pushback

In the log's shape ([`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md)). Numbered on from the graph plan's PB-14; an ID becomes permanent when the entry is written to the log, which happens when E-155 meets it.

**PB-15. A core package needs its implementers named before it can be a trait module.**
- *The code:* DiffEqBase's `solve(prob::AbstractDEProblem, args...)` (`solve.jl:653`), NonlinearSolveBase's `solve(prob::AbstractNonlinearProblem, …)` (`src/solve.jl:76`), NonlinearSolve's default `__init(prob::NonlinearProblem, ::Nothing, …)` (`src/default.jl:25`), LinearSolve's `init(prob::LinearProblem, args...)`.
- *The idiomatic form:* an interface package with implementation packages, each extending the interface's functions on the interface's types.
- *The reference:* [traits §10.1](../reference/traits.md#101-who-may-implement), joint owners; [§10.2](../reference/traits.md#102-pirates).
- *What it costs:* one line in SciMLBase, naming three or four packages. Each name widens G2's exception for SciMLBase's code: its joint owners' changes are a stakeholder's.
- *Blocks:* no; joint owners are built.

**PB-16. Joint owners' loads may discard the owner's image** (only if check J shows it).
- *The code:* SciMLBase's facts-compiled image, and DiffEqBase or NonlinearSolve loading after it with methods of SciMLBase's functions.
- *The idiomatic form:* the interface's image stays valid when its implementations load.
- *The reference:* [facts §11](../reference/facts.md#package-images); [§2.2](../reference/facts.md#g2), the stakeholder's exception.
- *What it costs:* check J's count, every session.
- *Blocks:* no.

**PB-17. Hooks with no type of the provider's in their signature.**
- *The code:* `wrapfun_iip(ff, inputs)` (`norecompile.jl:31`), `promote_tspan` with five untyped arguments (`solve.jl:858`), `isadaptive(alg) = false` (`alg_utils.jl:312`); SciMLBase's docs call these "extension hooks for packages that provide the callable-wrapper backend" (`SciMLBase.jl:2079`–`2114`).
- *The idiomatic form:* the interface declares a function; "the" provider fills it, keyed on nothing it owns.
- *The reference:* [traits §10.1](../reference/traits.md#101-who-may-implement): an implementation follows ordinary ownership, so no trait can hold such a hook either.
- *What it costs:* joint ownership, or a move into the owner where the body allows it (`isadaptive`).
- *Blocks:* no.

**PB-18. A trait module's refusal misses pirates made by a macro.**
- *The code:* DiffEqBase's `solve` and `init` under `Base.@constprop :aggressive` (`solve.jl:150`, `:653`).
- *The idiomatic form:* annotated definitions, checked like any other.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates); [T-56](../reference/traits.md#17-deviations).
- *What it costs:* a census after loading at every step; the wrap alone would admit these pirates.
- *Blocks:* no. Already T-56; the entry records where the port meets it.

**PB-19. A recipe macro writes a pirate into every recipe package.**
- *The code:* Makie's `@recipe` writes `Makie.symbol_to_plot(::Val{:GraphPlot})` into GraphMakie (`Makie/src/recipes.jl:192`, `:542`).
- *The idiomatic form:* registering a plot type under its symbol.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates); a joint owner cannot help, since Makie cannot name every recipe package.
- *What it costs:* GraphMakie cannot be wrapped until Makie's macro registers by the plot type.
- *Blocks:* wrapping GraphMakie; not P6.

**PB-20. Wrapping a core package moves a plain caller's first call into facts compilation.**
- *The code:* the workload's `solve(prob, Tsit5())` from plain code, after S6.
- *The idiomatic form:* the solver's first call costs what it costs plain.
- *The reference:* [facts §6.2](../reference/facts.md#the-mode-rule), [§11](../reference/facts.md#package-images); [lowering §15.2](../reference/lowering.md#152-workloads).
- *What it costs:* check F at S6 against S5.
- *Blocks:* no. The images' workloads are the lever. P3's entry (e) is the same cost seen from above.

**PB-21. A plotting load brings stakeholders' extensions into the core's facts** (only if order B shows it).
- *The code:* `SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt` (a joint owner's), `RecursiveArrayToolsStructArraysExt`.
- *The idiomatic form:* extensions that declare implementations, which win at no fact.
- *The reference:* [facts §2.2](../reference/facts.md#g2), the exceptions; [traits §10.3](../reference/traits.md#103-strict-mode), the warning for an extension.
- *What it costs:* check B's explained losses at S4 and S7.
- *Blocks:* no. P3's expected entry (d), now on the core.

---

## 7. Choices for the user (for the meta plan's list)

Numbered on from the graph plan's 22:

23. **Inside out with NetworkDynamics wrapped from the start.** The core grows from SciMLBase's interfaces up to the solvers under setting N's NetworkDynamics (`p3-wrap`, read only), rather than wrapping NetworkDynamics last. Reason: E-153's numbers are against N, and P4 builds on it.
24. **What stays plain:** ForwardDiff, LinearSolve, Static, the small interface and utility packages, SteadyStateDiffEq, the plotting side, Graphs, and every extension (§1.2).
25. **SciMLBase's joint owners:** DiffEqBase, NonlinearSolveBase, NonlinearSolve, and those S0's census adds by §2.4's rule (LinearSolve expected), including packages that stay plain. No other package declares joint owners in P6.
26. **Eight one-line moves in step 2,** as Static's fix: `isempty` on three callback types and `isfunctionwrapper`, `unwrap_fw` on `FunctionWrapper` into SciMLBase (with FunctionWrappers in its `[deps]`); `isadaptive`'s fallback into SciMLBase; `interp_summary` narrowed to `cacheType <: OrdinaryDiffEqCache`; `inactive_noinl` for `check_error!` into `SciMLBaseEnzymeExt`.
27. **The plotting side's pirates classified, not resolved:** Makie's 8 and GraphMakie's 2 wait until that side is wrapped (§2.2, G10–G13).
28. **Packages not cloned are made from the depot's exact trees** (the NonlinearSolve family), checked by tree hash, without network. OrdinaryDiffEqRosenbrock gets a worktree at its release's commit.
29. **Seven steps,** zero-pirate neighbours grouped to save builds.
30. **The fixed point's path (step 4) before the solver (step 5),** in the order the workload runs.
31. **Strict mode on for every check, during precompilation too;** order B with strict mode off, because it reads the invalidation log.
32. **Quick checks per step:** one workload session and the census. Order B and the attribution only at S4 and S7; the pirate only at S7.
33. **The merge:** after P6's S6 and P4's step 2 or 3, before P4's step 4, in a fresh `env_merged` and `depot-merged`. P4's later SciML declarations go on P6's trees.

---

## 8. Risks

1. **SciMLBase's size under `@trait_module`.** Each top-level statement runs after the ones before it ([traits §2](../reference/traits.md#2-trait-modules)). Whether that holds up on SciMLBase (3,282 methods, `@reexport`, RuntimeGeneratedFunctions' `init`) is porting 0.1a's open question. A failure is a TraitWorld deviation row; the step pauses.
2. **`@max_methods 1`** in SciMLBase, DiffEqBase and OrdinaryDiffEqCore. Unions split under it ([facts F-15](../reference/facts.md#deviations), open issue 46). The steady-state check T finds a cost; the dispatch profiler names it.
3. **More run-time sites like P3-1's.** The core compiled by facts may lean on Base folding its type computations. Check T catches it on the per-step path, and the fix goes into the owning package (B5).
4. **Generated functions:** SciMLBase 9, OrdinaryDiffEqCore 12, RecursiveArrayTools 4, SymbolicIndexingInterface 1, DiffEqBase 2 (P3's risk 1). A generator runs in its definition's world (E-141).
5. **The moves change behaviour where nothing loads the mover.** `isadaptive(alg) = false` in SciMLBase answers where a `MethodError` came before when OrdinaryDiffEqCore is not loaded. Narrowing `interp_summary` gives a `MethodError` for a cache type outside `OrdinaryDiffEqCache`. The moved trees' own tests are run once, in the test environments' pattern of `env_ndtest_*`, where they run offline.
6. **A wrapped package's precompile may cost more** than its plain build (P's measured time). If a step's build exceeds 10 minutes, the step pauses and the cost is recorded.
7. **Extensions stay plain.** Rodas5P's dual methods (`DiffEqBaseForwardDiffExt`, `RecursiveArrayToolsForwardDiffExt`) are plain code, reached by facts from wrapped callers. A joint owner's extension is a joint owner too.
8. **The cap of ten cache files** per package in `depot-p6` (§3.2).
9. **Strict mode does not yet refuse pirates loaded before the code they change** (F-6). The bottom-up order keeps the implementers after the core; the census covers the rest (§2.3).
10. **Open issue 20** (whether trait modules keep refusing every pirate) and **19** (whether the standard libraries are owners of their own) may change what the census counts. P6 follows the references as they stand.

## 9. Done when

1. E-155 is registered, the trees, `env_p6`, `depot-p6` and the harness's setting `I` exist, and S0's extended census is logged.
2. S1–S7 are committed and tagged, each with P, R, S, C, F, T and L logged in `ndport/logs/p6/`.
3. The census shows no pirate in a wrapped package at every step. The methods resting on joint ownership are counted per package.
4. Order B and the attribution have run at S4 and S7; every loss of the facts owner is explained, or recorded as a G2 failure with an open issue and a work item.
5. The pirate has run at S7 with the refusal's caller printed; check J at S2 and S7.
6. `ndport/README.md` has a dated table per step, with the builds, the trees' commits, strict mode, the load order, one run each, and the load average. Each number says it measures unchanged code compiled by facts.
7. E-155's outcome and an evidence row are in one commit. The pushback entries met are in the log.
8. The meta plan shows P6 in its parts table and its state, with choices 23–33 in its list.
9. The merge with P4 (§4) is done or scheduled, with its preconditions met.
