# The NetworkDynamics port, P6: inside out, under strict mode

Status: **adopted; part P6 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md).** Revised 2026-10-21 after the review [`../reviews/2026-10-21-ndport-inside-out-plan.md`](../reviews/2026-10-21-ndport-inside-out-plan.md); every finding accepted. Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) §10 and [`../reference/facts.md`](../reference/facts.md) above all).

**The user's words** (2026-10-21), on outside-in against inside-out:
- "I wonder whether inside-out under strict mode is a sensible strategy for trait porting core packages, even if they are not going to run under strict mode eventually. It forces the design to be piracy free at any step and can be done iteratively..."
- "Joint ownership is approved, build it to enable inside out. Note whether a different package structure could avoid it (or heavy use of implement over piracy), but if building joint ownership is simpler than restructuring SciML that is the pragmatic choice. Dual track is also go. For things like split packages I think you can decide yourself to add features that are highly orthogonal. Don't make changes to existing designs and features though..."

**The question:** can the SciML core under NetworkDynamics become trait modules from the bottom up, one step at a time, each step free of pirates under strict mode, with upstream's results? And what does each step buy: load protection for the solver's own code, and a cheaper first simulation once package images hold the code compiled by facts?

**What P6 does not do.**
- It writes no trait and no bounded function. Traits are P4's (the outside-in track).
- It changes neither a reference nor TraitWorld. It uses what is built: `@trait_module`, `@joint_owners`, strict mode, `owned_method`. A TraitWorld bug it finds becomes a deviation row or an open issue.
- It edits no SciML code to resolve a pirate. Its only changes to SciML's packages are the wrap's lines, the `@joint_owners` declarations and TraitWorld in `[deps]`. The moves that a different structure would allow are recorded (Appendix A), not made.
- It runs quick checks, not benchmarks. Measurement rounds belong to P5.

**Inputs.**
- The meta plan: its ground rules and its list of choices.
- E-151, E-152 and E-153: [evidence §1, §3](../design/evidence.md); `ndport/README.md`; [the P3 plan](2026-10-21-ndport-facts-first.md).
- The pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md): P3-1 (Static's promotion, facts §8), P4-1, P4-2.
- The census `ndport/logs/p3/census-P0.log` (TraitWorld e9f4bfe, before joint owners).
- Joint owners as built: [traits §10.1](../reference/traits.md#101-who-may-implement), [§10.2](../reference/traits.md#102-pirates), [§10.3](../reference/traits.md#103-strict-mode); [facts §1](../reference/facts.md#1-terms), [§10.2](../reference/facts.md#strict-mode); `TraitWorld/src/ownership.jl` (`@joint_owners`, `owns`), `TraitWorld/test/joint.jl` (TraitWorld a373e30).
- The alternatives entry "Split packages" ([`../design/alternatives.md`](../design/alternatives.md)).
- The wrap: [porting guideline 0.1a and B5](../intro/porting.md); `git -C ndport/pkgs/NetworkDynamics-p3wrap diff upstream`.
- Images and keep-compiled: [lowering §2](../reference/lowering.md#2-modes-owners-and-images), [facts §11](../reference/facts.md#package-images).
- The dependency graph: `ndport/env_upstream/Manifest.toml`, `ndport/env_p3/Manifest.toml`, the clones' and the depot's `Project.toml` files.

No Julia was run for this plan. Counts of rebuilt packages come from `env_p3/Manifest.toml` by a script over the manifest. Paths are relative to the repository root; line references are to the clones in `ndport/pkgs/` at `upstream`, and to the depot's copies (`~/.julia/packages/<Name>/<slug>`, matched to the manifest by version) for packages not cloned.

---

## 0. Summary

- **The order:** the SciML core, bottom-up, in seven steps. NetworkDynamics stays wrapped on top, as in setting N (P3's `p3-wrap`, read only).
  1. SymbolicIndexingInterface and RecursiveArrayTools;
  2. SciMLBase, with its joint owners declared;
  3. NonlinearSolveBase, BracketingNonlinearSolve and SciMLJacobianOperators;
  4. the NonlinearSolve family (the fixed point's path);
  5. DiffEqBase;
  6. OrdinaryDiffEqCore, with its joint owner declared, OrdinaryDiffEqTsit5 and DiffEqCallbacks (the integrator's driver);
  7. OrdinaryDiffEqRosenbrock.
- **Left plain:** ForwardDiff, LinearSolve, Static, OrdinaryDiffEqDifferentiation (it defines a true pirate, §2.2), SteadyStateDiffEq, the small interface and utility packages, the plotting side (Makie, GraphMakie, CairoMakie, Observables, NetworkLayout) and Graphs (P4's). The reasons are in §1.2.
- **The joint owners, named now** (§2.4):
  - SciMLBase: `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve BracketingNonlinearSolve NonlinearSolveFirstOrder LinearSolve SteadyStateDiffEq OrdinaryDiffEqCore`;
  - OrdinaryDiffEqCore (from S6): `@joint_owners OrdinaryDiffEqDifferentiation`;
  - and whatever the census adds at each step.
- **The P0 census's 63 pirates, classified** (§2):
  - (a) a joint owner's method: **57**. SciML's 53 are all held by SciMLBase's declaration. Makie's 4 would need ComputePipeline to name Makie; deferred.
  - (b) a different structure could also remove it: **13**, of which 8 are SciML's and are also held by joint ownership. No move is made; Appendix A records them. The other 5 are Makie's and GraphMakie's; deferred.
  - (c) an implementation of a trait instead of the method: **0**. A pirate names no type its definer owns, and an implementation follows ordinary ownership ([traits §10.1](../reference/traits.md#101-who-may-implement)).
  - (d) a true pirate: **1** in the census, Makie's `Base.deepcopy(::Observable)`; deferred. One more outside it: OrdinaryDiffEqDifferentiation's `Base.resize!(::LinearSolve.LinearCache, i)`.
  - Classes (a) and (b) overlap: a SciML method of class (b) is held by joint ownership as well.
- **Could a different structure avoid joint ownership?** In principle, yes: move SciML's front ends into SciMLBase. That is restructuring SciML: DiffEqBase's front end alone is about 1,400 lines with its own dependencies. The one-line moves (Appendix A) would avoid no declaration, because their definers are named anyway. Joint owners are the pragmatic choice.
- **Each step shows, cheaply** (§3):
  - the workload's digests equal to U's, bit for bit;
  - with strict mode on (and shown on), no refusal, and no pirate left in a wrapped package;
  - the steady state of steps c, d and e, and a dispatch profile of a whole steady-state pass, grouped by module;
  - the first simulation's cost against N's 37.8 s and U's 21.5 s;
  - the precompile cost of the step;
  - at two milestones (S4, S7), order B and the joint owners' loads; the packages' own quick tests after S2, S6, S7.
- **TraitWorld is pinned** to 3bebf13 for S0–S7, the commit that closes open issue 48 (§3.2).
- **The tracks meet** after P6's step 6 and before P4's step 4 (`ODERHS`), in a fresh environment, on new branches (§4).
- **About 10 builds and 30 sessions** through the lock, about 2–2.5 hours of lock time, spread between P4's runs (§3.4).

---

## 1. The order

### 1.1 The dependency graph, the part that matters

Each package with the stack's packages it depends on (`env_upstream/Manifest.toml`), bottom first. "Plain" marks packages that stay plain in the middle of the stack, which the references allow.

| Package | Depends on (of the stack) |
|---|---|
| SymbolicIndexingInterface | — (leaves only: Accessors, ArrayInterface, RuntimeGeneratedFunctions, StaticArraysCore) |
| RecursiveArrayTools | SymbolicIndexingInterface |
| SciMLBase | RecursiveArrayTools, SymbolicIndexingInterface; plain: CommonSolve, SciMLOperators, SciMLStructures, ADTypes, ArrayInterface, PreallocationTools, FunctionWrappersWrappers |
| SciMLJacobianOperators | SciMLBase; plain: SciMLOperators, DifferentiationInterface |
| NonlinearSolveBase | SciMLBase, SciMLJacobianOperators, RecursiveArrayTools, SymbolicIndexingInterface; plain: SciMLLogging, DifferentiationInterface |
| BracketingNonlinearSolve | NonlinearSolveBase, SciMLBase |
| LineSearch (plain) | SciMLJacobianOperators, SciMLBase |
| LinearSolve (plain) | SciMLBase, RecursiveArrayTools |
| NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve | NonlinearSolveBase, SciMLBase; LinearSolve (the first two), SciMLJacobianOperators (FirstOrder), LineSearch (FirstOrder, Spectral), BracketingNonlinearSolve (Simple) |
| NonlinearSolve | the four above, BracketingNonlinearSolve, NonlinearSolveBase, LinearSolve, SciMLBase |
| DiffEqBase | BracketingNonlinearSolve, SciMLBase, RecursiveArrayTools, SymbolicIndexingInterface |
| OrdinaryDiffEqCore | DiffEqBase, SciMLBase, RecursiveArrayTools |
| OrdinaryDiffEqTsit5 | OrdinaryDiffEqCore, DiffEqBase |
| OrdinaryDiffEqDifferentiation (plain) | OrdinaryDiffEqCore, DiffEqBase, LinearSolve; plain: ForwardDiff |
| OrdinaryDiffEqRosenbrock | OrdinaryDiffEqDifferentiation, OrdinaryDiffEqCore, DiffEqBase, LinearSolve |
| DiffEqCallbacks | DiffEqBase, SciMLBase, RecursiveArrayTools |
| SteadyStateDiffEq (plain) | DiffEqBase, DiffEqCallbacks, NonlinearSolveBase, LinearSolve, SciMLBase |
| NetworkDynamics | NonlinearSolve, DiffEqBase, DiffEqCallbacks, SciMLBase, RecursiveArrayTools, SymbolicIndexingInterface, LinearSolve, SteadyStateDiffEq; plain: Graphs, Static, ForwardDiff |

- NetworkDynamics depends on DiffEqBase, not on OrdinaryDiffEqCore. The workload loads Tsit5 and Rosenbrock itself.
- NonlinearSolveBase depends on SciMLJacobianOperators, so both go in step 3.
- DiffEqBase depends on BracketingNonlinearSolve, and so on NonlinearSolveBase. The nonlinear base comes before DiffEqBase.
- NonlinearSolve does not depend on DiffEqBase. So the fixed point's path (step 4) can come before the solver (step 5).

### 1.2 What is wrapped, what stays plain

| Package | P6 | Why |
|---|---|---|
| SymbolicIndexingInterface, RecursiveArrayTools | wrapped (step 1) | The bottom of SciML's interfaces. The solution access of step e. No pirates. |
| SciMLBase | wrapped (step 2) | The interface: problems, solutions, callbacks, `__solve`. Owner of every split pair. |
| NonlinearSolveBase, BracketingNonlinearSolve, SciMLJacobianOperators | wrapped (step 3) | Below DiffEqBase and NonlinearSolve. E-153's order B lost 209 of NonlinearSolveBase's CodeInstances in P0. |
| NonlinearSolve, NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve | wrapped (step 4) | The fixed point's path. E-153: most of N's extra 16 s is this code, compiled by facts in the session. |
| DiffEqBase | wrapped (step 5) | `solve`'s front end, `promote_f`, the callbacks' root finding. |
| OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, DiffEqCallbacks | wrapped (step 6) | The integrator's driver. In N it is plain, because `solve` is called from plain code. |
| OrdinaryDiffEqRosenbrock | wrapped (step 7) | Rodas5P's steps. |
| NetworkDynamics | wrapped from the start (P3's `p3-wrap`, read only) | The outer shell. N is known good, and E-153's numbers are against it. |
| OrdinaryDiffEqDifferentiation | plain | It defines `Base.resize!(p::LinearSolve.LinearCache, i) = p` (`lib/OrdinaryDiffEqDifferentiation/src/linsolve_utils.jl:124`): a true pirate, which no joint owner holds and P6 does not move (§2.2). Rosenbrock's trait code reaches its code by facts. |
| ForwardDiff | plain | A leaf. Wrapped callers reach its code by facts already. Wrapping it protects only its plain callers. It also keeps E-153's pirate case (a method on ForwardDiff's duals) a foreign package's. |
| LinearSolve | plain | Large: Krylov, MKL and many extensions. Reached through wrapped callers and through SteadyStateDiffEq (plain). Its front end is of the split kind (§2.4), so SciMLBase names it. |
| SteadyStateDiffEq | plain | Not on tier S's path (`find_fixpoint` calls NonlinearSolve). Its front end is of the split kind, so SciMLBase names it. |
| Static | plain, with P3's fix | A leaf below NetworkDynamics. Wrapped callers reach it by facts. |
| CommonSolve, SciMLOperators, SciMLStructures, ADTypes, ArrayInterface, PreallocationTools, FunctionWrappersWrappers, DifferentiationInterface, LineSearch, SciMLLogging, OrdinaryDiffEqRosenbrockTableaus | plain | Small interfaces and utilities, reached by facts from wrapped callers. |
| Makie, GraphMakie, CairoMakie, Observables, NetworkLayout | plain | The plotting side is outside. Makie compiled by facts in the session costs the first plot 48.5 against 16.0 s (E-153, W). It has 10 pirates by the letter, some needing Makie's macro changed (§2). |
| Graphs | plain | P4's graph step declares `GraphInterface` in it as plain code. |
| The wrapped packages' extensions | plain | An extension is a module of its own ([porting 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)). It counts as its parent for ownership, so a joint owner's extension is a joint owner too. |

### 1.3 The steps

Each step is one commit per changed tree, tagged `p6-s<k>` (§3.2 for the monorepo's second tree). "Rebuilt" counts the step's packages and their dependents in `env_p3`'s manifest, packages and extensions apart.

| Step | Wrapped | Declarations | Pirates held | Rebuilt | Precompile (estimate) |
|---|---|---|---|---|---|
| S0 | none: the P6 trees at `upstream`, NetworkDynamics as in N | — | — (the extended census) | every path-sourced package and its dependents | 4–6 min |
| S1 | SymbolicIndexingInterface, RecursiveArrayTools | — | none needed (0 by the census) | 21 + 38 | measured: the calibration (estimate 3–5 min) |
| S2 | SciMLBase | SciMLBase's line (§2.4) | DiffEqBase's 28, NonlinearSolveBase's 12, NonlinearSolve's 10, OrdinaryDiffEqCore's 3, and the four packages' of §2.3, by joint ownership | 19 + 29 | about S1's |
| S3 | NonlinearSolveBase, BracketingNonlinearSolve, SciMLJacobianOperators | — | already held by S2's line | 17 + 18 | about S1's |
| S4 | NonlinearSolve, NonlinearSolveFirstOrder, …QuasiNewton, …SpectralMethods, SimpleNonlinearSolve | — | already held by S2's line | 6 + 3 | half of S1's |
| S5 | DiffEqBase | — | already held | 8 + 7 | half of S1's |
| S6 | OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, DiffEqCallbacks | OrdinaryDiffEqCore's line (§2.4) | OrdinaryDiffEqDifferentiation's methods on OrdinaryDiffEqCore's functions and types | 7 + 3 | 1–2 min |
| S7 | OrdinaryDiffEqRosenbrock | — | none (Rosenbrock 0 by the census) | 1 + 0 | under 1 min |

- **The estimates.** Through S5, every closure contains the same critical path: DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqDifferentiation, OrdinaryDiffEqRosenbrock, NonlinearSolve's workload and NetworkDynamics. Precompilation is bounded by that chain, not by the number of packages. So S1's measured time calibrates S2 and S3; S4 and S5 cost about half. The total is perhaps 15–25 minutes.
- **The facts mode adds a cost that has no anchor yet.** From S2 on, every dependent's workload that calls SciMLBase compiles SciMLBase's methods, and what they call, under the facts owner. E-153's "NetworkDynamics cost nothing" (18.2 against 22.0 s) was for the top of the stack, where no dependent's workload exists. If a step's build exceeds 10 minutes, the step pauses and the cost is recorded.
- **Zero-pirate neighbours are grouped** to save builds: SymbolicIndexingInterface with RecursiveArrayTools; NonlinearSolveBase with what it depends on and what DiffEqBase needs; the NonlinearSolve family; the integrator's driver with Tsit5 and DiffEqCallbacks.
- **The fixed point before the solver.** Step 4 precedes step 5 because the workload runs step c before step d, and E-153 puts most of N's extra cost in step c.
- **A step's packages are wrapped only when no pirate of theirs is left,** by the census with joint owners counted. Otherwise the step stops, and the pirate is classified (§2) before the step is retried.

### 1.4 The wrap, per package

The same three lines as P3's, and TraitWorld in `[deps]`:

```julia
module SciMLBase
using TraitWorld: TraitWorld, @trait_module, @joint_owners      # 1
@trait_module begin                                              # 2
@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve BracketingNonlinearSolve NonlinearSolveFirstOrder LinearSolve SteadyStateDiffEq OrdinaryDiffEqCore
# … the package as it is: its `@max_methods 1` block, its includes, its workload …
end # @trait_module                                              # 3
end
```

- **Two packages declare joint owners:** SciMLBase at S2, OrdinaryDiffEqCore at S6 (`@joint_owners OrdinaryDiffEqDifferentiation`). A step's census may add names (§2.4).
- **Where the declaration stands.** `@joint_owners` must stand at the top level of the owner's own module (`ownership.jl`: `owner(__module__) === __module__`). Inside the `@trait_module` block it still does, by reading the code. `test/joint.jl` declares only in a plain module. So a five-line probe in `ndport/scripts/` (`p6_joint_probe.jl`: a package-like module wrapped in `@trait_module begin … end` that declares, and a second module that defines a method of the first's function on the first's type) runs in S0's census session and settles it, without touching TraitWorld.
- **NonlinearSolveBase need not declare.** NonlinearSolve's methods of NonlinearSolveBase's `initialization_alg` name SciMLBase's problem types. NonlinearSolve owns them through SciMLBase's line (`owned_method` asks whether the definer owns the function *or a type*, `ownership.jl:231–236`).
- **TraitWorld becomes a dependency** of every wrapped package and of each declaring owner. From step 1 on, every session that loads SymbolicIndexingInterface loads TraitWorld. The load times are recorded per step.
- **`delegate!` is not used.** `KNOWN_DELEGATES` names `SciMLBase => OrdinaryDiffEq` (`TraitWorld/src/strict.jl:26`). That package is never loaded in the workload, so every acceptance in P6 comes from joint owners. The census prints which methods rest on them.

---

## 2. The pirates, classified

The P0 census by the letter (`TraitWorld.owned_method`, TraitWorld e9f4bfe, `ndport/logs/p3/census-P0.log`): DiffEqBase 28, NonlinearSolveBase 12, NonlinearSolve 10, Makie 8, OrdinaryDiffEqCore 3, GraphMakie 2; the others 0. Each keyword method (`Core.kwcall`) is counted apart from its positional method, as the census counts them.

### 2.1 The classes

| Class | Meaning | Count | P6's choice |
|---|---|---|---|
| (a) | a joint owner's method, held by the owner's declaration | 57 (SciML 53, Makie 4) | SciML: declared at S2. Makie: deferred. |
| (b) | a different structure could also remove it: a move to the package that owns the function or a type, or a narrowing to an owned type | 13 (SciML 8, also in (a); Makie 3; GraphMakie 2) | no move made; recorded in Appendix A. Makie's and GraphMakie's: deferred. |
| (c) | avoidable by an implementation of a trait instead of a method | 0 | — |
| (d) | a true pirate, to remove or move | 1 (Makie); one more outside the census (OrdinaryDiffEqDifferentiation) | deferred; Differentiation stays plain |

- The classes overlap where both hold. A SciML method of class (b) is held by joint ownership too, since its definer is named anyway. So 57 + 5 + 1 = 63.
- The porting guideline (0.1a) says to look for a one-line move before declaring. That applies where a move would avoid a declaration. Here none does.

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
| G4 | Base's `isempty` on SciMLBase's callback types | DiffEqBase | 3 | `Base.isempty(cb::CallbackSet)` `callbacks.jl:81`; `isempty(::AbstractContinuousCallback) = false` `:84`; `isempty(::AbstractDiscreteCallback) = false` `:85` | a, b | Held by joint ownership: the types are SciMLBase's ([traits §10.1](../reference/traits.md#101-who-may-implement) uses this method as its example). Structure: one line each into SciMLBase (Appendix A). | joint owner |
| G5 | SciMLBase's wrapper predicates on FunctionWrappers' type | DiffEqBase | 2 | `SciMLBase.isfunctionwrapper(x::FunctionWrapper) = true` `DiffEqBase.jl:116`; `unwrap_fw(fw::FunctionWrapper) = fw.obj[]` `norecompile.jl:26` | a, b | Held by joint ownership: the functions are SciMLBase's (`SciMLBase.jl:2076`, `:2126`). Structure: one line each into SciMLBase's `function_wrappers.jl`, with FunctionWrappers in its `[deps]` (Appendix A). | joint owner |
| G6 | the nonlinear front end and entries | NonlinearSolveBase | 12 | `solve(prob::AbstractNonlinearProblem, args...)` `src/solve.jl:76`; `init` `:231`; `__solve` `:634`; `__init` `:647`; `CommonSolve.solve(::HomotopyProblem, ::Nothing, …)` `src/homotopy_sweep.jl:898`; `solve(::HomotopyProblem)` `:904` (NonlinearSolveBase 2.55.0) | a | As G1, for NonlinearSolveBase. | joint owner |
| G7 | the default algorithm, chosen when `alg` is `nothing` | NonlinearSolve | 8 | `SciMLBase.__init(prob::NonlinearProblem, ::Nothing, args...)` `src/default.jl:25`; `__solve` `:40`; on `AbstractSteadyStateProblem`, an alias of `AbstractNonlinearProblem` (`SciMLBase.jl:351`), `:59`, `:65` (NonlinearSolve 4.32.0) | a | Structure: SciMLBase would choose the default, but it knows no solver; or a registry keyed by problem type. Implementation: no owned type; the algorithm is `nothing`. | joint owner |
| G8 | NonlinearSolveBase's initialization hook | NonlinearSolve | 2 | `NonlinearSolveBase.initialization_alg(prob::AbstractNonlinearProblem, autodiff)` `default.jl:71`; on `HomotopyProblem` `:88` | a | Structure: no; the result is NonlinearSolve's own polyalgorithm type, which NonlinearSolveBase cannot name. Held by SciMLBase's line, since the signature names SciMLBase's types. | joint owner |
| G9 | OrdinaryDiffEqCore's methods of SciMLBase's functions | OrdinaryDiffEqCore | 3 | `isadaptive(alg) = false` `alg_utils.jl:312`; `SciMLBase.interp_summary(::Type{cacheType}, dense::Bool) where {cacheType}` `interp_func.jl:73`; `EnzymeRules.inactive_noinl(::typeof(check_error!), args...)` `enzyme_rules.jl:25` | a, b | Held by naming OrdinaryDiffEqCore in SciMLBase's line, as the reference's own example does. Structure: `isadaptive`'s fallback into SciMLBase (it changes SciMLBase's contract); `inactive_noinl` into `SciMLBaseEnzymeExt` (equivalent); `interp_summary` only narrowed to `Union{OrdinaryDiffEqCache, StochasticDiffEqCache}` (Appendix A). | joint owner |
| G10 | Makie's methods of ComputePipeline's functions | Makie | 4 | `ComputePipeline.add_input!(::ComputeGraph, ::Symbol, ::ShaderAbstractions.UpdatableArray)` `Makie/src/compute-plots.jl:5`, `:16` (the code's own TODO asks whether it belongs in ComputePipeline); `map_latest!(f, ::Observable, …)` `interaction/observables.jl:89` | a | ComputePipeline is a package of Makie's repository; it would name Makie. Structure: `add_input!` into a ComputePipeline extension on ShaderAbstractions. | deferred (Makie plain) |
| G11 | one-line moves on the plotting side | Makie | 3 | `Observables.to_value(::Computed)` `compute-plots.jl:900`, `Base.notify(::Computed)` `:901`: into ComputePipeline, which owns `Computed` and depends on Observables; `GeometryBasics.collect_with_eltype(::Type{T}, ::ShaderAbstractions.Buffer{T})` `conversions.jl:2435`: into ShaderAbstractions, which depends on GeometryBasics | b | One line each. | deferred |
| G12 | Base's `deepcopy` changed for Observables' type | Makie | 1 | `Base.deepcopy(obs::Observable) = Observable{Any}(to_value(obs))` `attributes.jl:51` | d | Moving it would change `deepcopy` for every user of Observables. The principled form is a function of Makie's own at its call sites. | deferred |
| G13 | Makie's `@recipe` registers a plot type by `Val{symbol}` | GraphMakie | 2 | `Makie.symbol_to_plot(::Val{:GraphPlot})`, `(::Val{:EdgePlot})`; the method's line is in Makie's macro (`recipes.jl:192`, `:542`) | b | A different structure in Makie's macro: register by the plot type, which the recipe package owns (the macro already writes `plotsym(::Type{<:PlotType})`). No joint owner fits: Makie cannot name every recipe package. | deferred |

**Outside the P0 census** (read in the depot's copies and the clones; §2.3):

| # | Group | Package | Examples (file:line) | Class | Now |
|---|---|---|---|---|---|
| G14 | the bracketing front end | BracketingNonlinearSolve 1.12.8 (S3) | `CommonSolve.solve(prob::IntervalNonlinearProblem; …)` `src/BracketingNonlinearSolve.jl:46`; `solve(prob::IntervalNonlinearProblem, nothing, args...; …)` `:50` (`nothing` is the argument's name, so the argument is `Any`) | a | joint owner. Plain function definitions, which the wrap checks: without the name, S3 fails with `OwnershipError`. |
| G15 | a default algorithm | NonlinearSolveFirstOrder 2.10.0 (S4) | `SciMLBase.__init(prob::NonlinearLeastSquaresProblem, ::Nothing, args...; …)` `src/solve.jl:558` | a | joint owner |
| G16 | the linear and eigenvalue front ends | LinearSolve 5.18.2 (plain) | `SciMLBase.init(prob::LinearProblem, args...; …)` `src/common.jl:382`; `init(prob::LinearProblem, alg::Nothing, args...; …)` `src/default.jl:593`; `SciMLBase.solve(prob::EigenvalueProblem, args...; …)` `src/eigenvalue.jl:172`; with `::Nothing` `:175` | a | joint owner, though plain |
| G17 | the steady-state front end | SteadyStateDiffEq 2.18.1 (plain) | `SciMLBase.solve(prob::SteadyStateProblem, args...; …)` `src/solve.jl:129` | a | joint owner, though plain |
| G18 | OrdinaryDiffEqCore's interface, filled by Differentiation | OrdinaryDiffEqDifferentiation 3.12.4 (plain) | `import OrdinaryDiffEqCore: get_chunksize, resize_J_W!, alg_autodiff, get_fresh_jacobian` `lib/OrdinaryDiffEqDifferentiation/src/OrdinaryDiffEqDifferentiation.jl:45`; `alg_autodiff(alg::OrdinaryDiffEqAdaptiveImplicitAlgorithm) = alg.autodiff` `src/alg_utils.jl:4–8`; `DiffEqBase.prepare_alg(alg::Union{OrdinaryDiffEqAdaptiveImplicitAlgorithm, …}, u0::AbstractArray{T}, p, prob)` `:29` | a | joint owner of OrdinaryDiffEqCore, from S6 |
| G19 | Base's `resize!` on LinearSolve's cache | OrdinaryDiffEqDifferentiation | `Base.resize!(p::LinearSolve.LinearCache, i) = p` `src/linsolve_utils.jl:124` | d | Differentiation stays plain (choice 26). Options recorded in Appendix A. |

- SimpleNonlinearSolve, NonlinearSolveQuasiNewton, NonlinearSolveSpectralMethods, SciMLJacobianOperators and LineSearch show none in the review's reading: their methods name an algorithm or cache type of their own.
- The extended census at S0 checks these readings.

**The answer the user asked for, per group.**
- **G1, G2, G6, G14–G17:** a different structure avoids them only by moving SciML's front ends into SciMLBase, or SciMLBase's problem types out of it. That is restructuring SciML. Joint owners are simpler.
- **G3, G7, G8, G18:** hooks, defaults and internal interfaces declared in one package and filled by another, with no type of the filler's in the signature. A structure without them needs a backend value of the filler's type in every call, or the two packages merged. Joint owners are simpler.
- **G4, G5, G9:** one-line moves exist (Appendix A). They avoid no declaration, because DiffEqBase and OrdinaryDiffEqCore are named anyway. So P6 makes none.
- **G10–G13, G19:** outside the wrapped set in P6. Recorded for when their packages are wrapped.
- **Implementations of traits avoid none of them** (class (c), above).

### 2.3 What the P0 census does not cover

- **Packages outside its list.** It covered 17 packages. G14–G19 come from reading the others. S0's **extended census** covers every loaded package (§3.1, check C), and it reproduces P0's 63 on the 17 packages as the control of the new script.
- **Methods the wrap's own check misses.** A trait module refuses a pirate at its definition only for definitions it recognizes ([T-56](../reference/traits.md#17-deviations)). DiffEqBase's `solve` and `init` are defined under `Base.@constprop :aggressive` (`solve.jl:150`, `:653`), so the wrap alone would not refuse them. **The census after loading is the check,** at every step.
- **Extensions.** `owner` maps an extension to its parent, so an extension's pirate counts against its parent. The extended census lists extensions apart, attributed to their parents.
- **Pirates loaded before the code they would change.** Strict mode does not refuse these yet ([facts F-6](../reference/facts.md#deviations), Planned). In a bottom-up order, the wrapped core loads before its implementers, so their methods arrive after the core's code. A plain leaf below the core cannot name the core's types. The census covers what remains.

### 2.4 The joint-owner declarations

- **SciMLBase (S2):** `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve BracketingNonlinearSolve NonlinearSolveFirstOrder LinearSolve SteadyStateDiffEq OrdinaryDiffEqCore`. It holds G1–G9 and G14–G17.
- **OrdinaryDiffEqCore (S6):** `@joint_owners OrdinaryDiffEqDifferentiation`. It holds G18, and any of OrdinaryDiffEqCore's other implementers the census finds (Tsit5 and Rosenbrock showed 0 in P0).
- **Why at S6, not S7.** Strict mode refuses at the owner's trait code, whatever the definer's mode. Once OrdinaryDiffEqCore is a trait module, Differentiation (plain, loaded after it by `using OrdinaryDiffEqRosenbrock`) defines methods that can win at facts in OrdinaryDiffEqCore's image.
- **The rule for additions,** at every step:
  - A plain package's pirate on a function or type of a package P6 will wrap is classified **before the step that wraps that owner**, not before the step that would wrap its definer.
  - Its definer is named in the owner's line if its pirates are of the split kind: a front end, `__solve`/`__init`, a default algorithm, or a hook or internal function of the owner's interface.
  - A pirate of another kind (class (d)) keeps its definer plain, and the step wraps around it, as for Differentiation.
- **A package is named even if it stays plain** (LinearSolve, SteadyStateDiffEq, Differentiation). Strict mode refuses a winning pirate whatever its definer's mode, and naming it keeps the result independent of which facts the owner's image happens to hold.
- **What each name costs** ([traits §10.1](../reference/traits.md#101-who-may-implement), "What it costs"): the joint owner's methods are a stakeholder's change. They may discard the owner's code compiled by facts (facts §2.2's exception), and strict mode does not refuse them.
  - The cost reaches beyond the owner. NonlinearSolveBase has `initialization_alg(initprob, autodiff) = nothing` (`src/initialization.jl:57`). NonlinearSolve adds a method for `AbstractNonlinearProblem` (`default.jl:71`), which wins at every concrete nonlinear problem. NonlinearSolve is a stakeholder there only through SciMLBase's line. So SciMLBase's declaration widens G2's exception in NonlinearSolveBase's trait code.
  - Check J measures it at S4 and S7 (§3.1).
- **Later, for the plotting side:** ComputePipeline would name Makie (G10).

---

## 3. What each step must show, cheaply

### 3.1 The checks

| Check | How | Pass |
|---|---|---|
| **P** precompile | `env_p6` through the lock, `JULIA_NUM_PRECOMPILE_TASKS=4`, niced, `JULIA_TW_STRICT=1`; `scripts/p6_precompile.sh` (as `p4_precompile.sh`) | builds; no `OwnershipError`; no `PirateError` when images load; the wall time and the number rebuilt recorded; the log prints strict mode's state |
| **R** results | the workload, P1's order, `NDW_STRICT=1`; `compare_digests.py --exact` against E-151's U log | all digests equal, bit for bit |
| **S** strict mode | the R session's log, which prints `TraitWorld.STRICT[]` | strict mode reported on; no `PirateError`, at load or later. A warning for a package extension's winning method is allowed; each is listed with the method and the code it affects. |
| **S+** strict mode's positive control | S2, one session: a probe (`scripts/p6_strict_probe.jl`) that defines, after the stack has run, a pirate that wins at a fact of SciMLBase's facts-compiled code | refused; the refusal's caller (`_trait_root(e.caller)`) names SciMLBase. E-153's P0 control stands; it is not repeated. |
| **C** census | `scripts/p6_census.jl` (new), strict mode on; every loaded package, extensions apart. Per pirate: the definer, the owners of the function and of each type. Per package: `wrapped` (its root module has the facts option), `pirates` (with joint owners counted), `joint` (the methods that are pirates without joint owners and owned with them). At S0, also P0's 17 packages with P0's counting, as the script's control. | pirates in wrapped packages: 0. Pirates elsewhere that name a function or type of a package P6 will wrap: listed, each classified before the step that wraps its owner (§2.4). S0: P0's 63 reproduced. |
| **F** first simulation | the R session's first pass: steps a–e, and c and d apart | recorded against I0 and U's 21.5 s. No pass rule: the expectation is a fall, step c at S4 and step d at S6. At the milestones, the attribution (`NDW_DIAG=1`): new CodeInstances per step by module and owner. |
| **T** steady state | the R session's "again" pass: steps **c, d and e**, each against I0 | each within 10 % + 5 ms of I0's. Steps f and g are recorded. |
| **H** the dispatch profile | `scripts/p6_profile.jl` (new, as `p3_hot.jl` but over the pass): one "again" pass of steps c–e under `JULIA_FACTS_DISPATCH_PROFILE=1`, the profile reset before it and printed after it, the run-time sites grouped by the callee's module. At every step, in the C session (the census needs no timing). | no new run-time site on the steady state in the step's newly wrapped modules, or each one explained. A new site on the per-step path is fixed in the owning package before the next step, as P3-1's ([porting B5](../intro/porting.md)). |
| **L** loads | the R session's load lines | recorded; TraitWorld is loaded from step 1 on |
| **Q** the packages' own quick tests | offline test subsets in the `env_ndtest_*` pattern (`ndport/env_p6test`, `depot-p6`), a few minutes each | after S2: SymbolicIndexingInterface's and RecursiveArrayTools' core tests; SciMLBase's interpolation and solution-interface tests. After S6: DiffEqBase's callback tests; OrdinaryDiffEqTsit5's basic tests. At S7: `nd_tests.jl`. Each passes as at `upstream`. |
| **J** joint owners' loads | S4 and S7: `scripts/p6_loadinv.jl` (new), strict mode off, Julia's invalidation log on while the stack loads | the CodeInstances of the facts owner discarded when a joint owner loads (image validation, or invalidation by the joint owner's methods), **by module, for every wrapped package**. Recorded; a large share is pushback P6-2. |
| **B** order B | S4 and S7: `NDW_ORDER=simfirst`, strict mode off (strict mode and the invalidation log share the switch, P3's risk 10); `p3_loads.jl` | lost CodeInstances by module and owner; each lost CodeInstance of the facts owner classified by facts §2.2's route, or a G2 failure (an open issue and a work item; P6 pauses). "After" recompiles at most N's 0.04 s, plus 0.5 s. Digests of "after" equal. |
| **X** the pirate | S7: `p3_pirate.jl`, strict mode on and off | strict on: refused, and the refusal's caller also names SciML code, not only NetworkDynamics'; strict off: the losses of the facts owner by module. P0's control from E-153 stands. |

**What the expected numbers mean.**
- **I0 is the reference** for F and T: the P6 trees at `upstream` on the pinned TraitWorld. It should reproduce N (E-153: first simulation 37.8 s; steady state of step d 15.3 ms) within the 10 % + 5 ms margin. If it does not, the difference is TraitWorld's (§3.2), and I0's numbers stand as P6's reference.
- **The first simulation should fall** as images hold the facts-compiled code that NetworkDynamics' trait code reaches. Each wrapped package's own precompile workload compiles under the facts owner, and keep-compiled keeps the code it compiles for other packages' methods ([lowering §2](../reference/lowering.md#2-modes-owners-and-images)).
- **It will not fall to U's 21.5 s by wrapping alone.** Code specialized on NetworkDynamics' types is in no SciML workload. Only NetworkDynamics' own workload can put it into an image. That is P4's (its S4 makes the workload `TraitWorld.@workload`). Until the tracks merge, P6 keeps P3's workload, so the two effects stay apart.
- **It may rise at step 6.** The workload's `solve(prob, Tsit5())` comes from plain code. Once OrdinaryDiffEqCore is a trait module, the driver it reaches is compiled by facts, and only Tsit5's own workload types are in its image. F records it as it is.
- **Order B's protection extends to the core.** In E-153, P0 lost NonlinearSolveBase 209 and SciMLBase 61 CodeInstances to the plotting load, and N still lost 2,884 plain ones. After S4 and S7 those modules' code on the workload's path is of the facts owner. Its losses must be 0, or explained.
- **Expected explained losses in B:**
  - the stakeholders' extensions that the plotting load activates (`SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt`, `RecursiveArrayToolsStructArraysExt`). With the core wrapped they are a stakeholder's change to the core's code: followed, with strict mode's warning where a method wins without mentioning its triggers' types ([traits §10.3](../reference/traits.md#103-strict-mode)). Pushback P6-7;
  - the FunctionWrappers' own plain call methods, behind `promote_f` (`DiffEqBase/src/solve.jl:1038–1060`) and the callbacks' wrappers (`OrdinaryDiffEqCore/src/solve.jl:90–155`): plain code, which the load may discard;
  - the owner `:facts_plain_return_type` (E-153's N log lists 15 lost, `logs/p3-orderB/N-1.log:21`): plain inference's answers behind `return_type` ([facts §7.1](../reference/facts.md#return-type)). They change exactly when plain Julia's do; B counts them apart.

### 3.2 The settings and environments

- **TraitWorld, pinned.**
  - Every wrapped package depends on TraitWorld, loaded from source. A TraitWorld commit rebuilds every wrapped package and its dependents, and moves I0.
  - **S0–S7 use TraitWorld 3bebf13,** named in each log header. It closes open issue 48: family members are served by the table of declared implementations, and held values convert at fact signatures.
  - If TraitWorld must change mid-track, I0 and the last step run again on the new commit, and the README's table says so.
- **Trees.** Each is on a branch from the tag `upstream`. Worktrees and branches add refs to P0's clone repositories, as P3 and P4 did (the meta plan's choice 8); P0's working trees stay untouched.
  - git worktrees of the clones, branch `p6-inside-out`: `ndport/pkgs/SymbolicIndexingInterface-p6`, `RecursiveArrayTools-p6`, `SciMLBase-p6`, `DiffEqCallbacks-p6`;
  - `ndport/pkgs/OrdinaryDiffEq-p6`, a worktree of the monorepo at `upstream` (53e7d1d), branch `p6-inside-out`: DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5 and OrdinaryDiffEqDifferentiation. Their trees match the manifest there (Differentiation 57ebe5c7…, Tsit5 371de3eb…; `git rev-parse upstream:lib/<Name>`);
  - `ndport/pkgs/OrdinaryDiffEq-p6-ros`, a second worktree of the same repository, at 14f664a, for OrdinaryDiffEqRosenbrock alone. At `upstream` its tree differs from the release (`dbd63471…` against the manifest's `4d635452…`). Git refuses one branch in two worktrees, and tags are per repository, so this tree has the branch `p6-inside-out-ros` and the tags `upstream-ros` (14f664a) and `p6-s7-ros`. `VERSIONS.tsv` has a row for each tree;
  - **the NonlinearSolve family** (NonlinearSolve 4.32.0, NonlinearSolveBase 2.55.0, BracketingNonlinearSolve 1.12.8, NonlinearSolveFirstOrder 2.10.0, …QuasiNewton 1.15.3, …SpectralMethods 1.8.3, SimpleNonlinearSolve 2.14.6, SciMLJacobianOperators 0.1.20): not cloned yet. Each becomes a repository `ndport/pkgs/<Name>-p6`, made from the depot's exact tree (`~/.julia/packages/<Name>/<slug>`), committed and tagged `upstream`, on branch `p6-inside-out`. Its tree hash is checked against the manifest's `git-tree-sha1`. `clone.sh` gains a `--from-depot` mode, and `VERSIONS.tsv` a row per package marked "from depot". No network is needed.
- **Read only, never changed by P6:** `ndport/pkgs/NetworkDynamics-p3wrap` (branch `p3-wrap`, e5425fd); `ndport/pkgs/Static.jl` (branch `trait-port`, c34adbb); the main clones of Graphs, Makie, GraphMakie, NetworkLayout, Observables (at `upstream`); LinearSolve, SteadyStateDiffEq and OrdinaryDiffEqDifferentiation as the manifest has them (registry, or the monorepo worktree).
- **Never touched:** `env_port` and the main clones' working trees (P0, A0); `~/.julia`'s caches for them; `pkgs/NetworkDynamics-p4`, `env_p4`, `depot-p4` (P4); `pkgs/Graphs-p4`, `pkgs/GraphMakie-p4` (E-154); `env_p3`, `depot-p3` (E-153's record).
- **`ndport/env_p6`:** `env_p3`'s project, its `[sources]` pointing at the P6 trees, plus the NonlinearSolve family and OrdinaryDiffEqRosenbrock by path. Resolved offline. Its manifest is committed per step.
- **`ndport/depot-p6`:** `JULIA_DEPOT_PATH=ndport/depot-p6:$HOME/.julia:`. Julia keeps at most ten cache files per package (`julia-1.13/base/loading.jl:3372`). Seven steps stay under it; a step rerun is built forward, not by going back.
- **The harness:** setting `I` in `scripts/run_workload.sh` (`env_p6`, `depot-p6`, TraitWorld loaded). The log header names TraitWorld's commit, each P6 tree's commit, the step tag and strict mode's state.
- **Optional, at S7:** setting `IC`, the core alone. NetworkDynamics from its main clone at `upstream` (plain), in `ndport/env_p6c` with `depot-p6`. It shows what the wrapped core gives a plain user of NetworkDynamics: the integrator's driver and the fixed point protected without NetworkDynamics being a trait module. One extra build of NetworkDynamics and its extensions, and one session.
- **The builds:** julia-1.13 at the build then current, named in each header. TraitWorld is not edited while a P6 job runs ([INDEX](../record/INDEX.md), "Standing constraints").

### 3.3 Per step, what runs

Sessions: R is the workload (R, S, F, T, L); C+H is the census and the profile, in one session.

| Step | Builds | Sessions |
|---|---|---|
| S0 | 1 | C+H (with the census's control and the joint-owner probe), R (I0) |
| S1 | 1 | C+H, R |
| S2 | 1, plus 1 for `env_p6test` | C+H, R, S+, Q |
| S3 | 1 | C+H, R |
| S4 (milestone) | 1 | C+H, R, B, attribution, J |
| S5 | 1 | C+H, R |
| S6 | 1 | C+H (with Tsit5's fold check, §8), R, Q |
| S7 (milestone) | 1 | C+H, R, B, attribution, J, X (strict on and off), Q (`nd_tests.jl`) |
| the merge (§4) | 1 | R strict off, R strict on, C+H |
| optional IC | 1 | R |

### 3.4 The cost

- **About 10 builds:** 8 for S0–S7, 1 for the test environment, 1 for the merge, plus one optional. Perhaps 15–25 minutes of precompilation in all (§1.3).
- **About 30 sessions** of 1–4 minutes each.
- **About 2–2.5 hours of lock time,** spread between P4's runs. One Julia job at a time, through the shared lock, niced.

---

## 4. How the two tracks meet

**The tracks.**
- **P4, outside-in:** traits at the seams. Step 1, `ComponentDynamics` in NetworkDynamics (E-152, done; `pkgs/NetworkDynamics-p4`, `env_p4`, `depot-p4`). Step 2, `GraphInterface` in Graphs (E-154). Step 3, `VertexDynamics`/`EdgeDynamics`. Then `ODERHS` with the integrator's `f` kept, `IndexProvider`/`ValueProvider`, `Trajectory` ([the traits plan](2026-10-21-ndport-traits.md) §4).
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
- **One TraitWorld commit** for the merge, named in the headers. Both tracks' last steps are rebuilt and run once on it first, if they ran on another: P6's last step in `env_p6`, P4's last step in `env_p4`.
- **A fresh environment and depot,** `ndport/env_merged` and `ndport/depot-merged`:
  - NetworkDynamics from `pkgs/NetworkDynamics-p4`, at P4's last step's tag;
  - Graphs and GraphMakie from `pkgs/Graphs-p4` and `pkgs/GraphMakie-p4`, at E-154's tags;
  - SciML from P6's trees at their latest `p6-s<k>` tags;
  - Static as before.
- **New branches.** Each tree gets a branch `port` from its last tag (P6's `p6-s<k>`, P4's last step). The tracks' branches (`p6-inside-out`, `p6-inside-out-ros`, `trait-port`, `trait-port-p4`) stay as their records, as `env_p4` and `env_p6` do.
- **The merge's checks:** P; R with strict mode **off** first, then R with strict mode on (E-152 and E-154 ran strict off, so this is P4's code's first strict run, and a refusal must be attributable); C+H; F; T; L.
- **The steady-state reference after the merge** is P4's, not I0: NetworkDynamics is then P4's code. The reference is **P4 after open issue 48's fix** (TraitWorld 3bebf13): step d 33.1–41.2 ms, a right-hand side 5 allocations and 208 bytes (two runs, `ndport/logs/p4-issue48/`). If the merge's TraitWorld commit is another, P4's last step runs again on it, and that run is the reference.
- **GraphMakie's two pirates** (G13) are written into GraphMakie by Makie's `@recipe`. With strict mode on, they matter if `GraphMakie-p4`'s trait submodule holds facts they change. That is P4's to check at the merge.
- The merged first pass is the first number with both effects: P4's workload in NetworkDynamics' image and P6's facts code in SciML's images.
- **After the merge, one line of work** on the `port` branches. `env_merged` becomes the port's environment. P4's later trait declarations in SciML go there.

**Conflicts to avoid until then.**
- **The same trees.** P6 never changes NetworkDynamics, Graphs or GraphMakie. P4 never wraps a SciML package, declares joint owners, or edits a SciML tree.
- **The same files in `ndport/`.** Both tracks add settings to `run_workload.sh` and rows to `README.md` and `VERSIONS.tsv`. Each edit is a small commit, made after re-reading the file.
- **The lock.** P6's builds are its longest jobs. They go between P4's runs, never in a chain.
- **TraitWorld.** Both load it from source. Neither edits it while the other runs. P6 needs no TraitWorld change; its census, probes and scripts live in `ndport/scripts/`.
- **Static.** Both read `pkgs/Static.jl` at c34adbb. Neither changes it.
- **The depots.** Each track builds into its own depot only.
- **Experiment numbers.** E-152 and E-154 are P4's, E-155 is P6's. The merge's run is recorded under E-155's outcome, with P4's builds named.

**What each track gives the other.**
- P6 to P4: trait modules where SciML's bounded code can live; split pairs that strict mode accepts; facts-compiled code in SciML's images, which lowers the first-call cost P4 measures.
- P4 to P6: a network type that does not change with the equations (E-152), so the solver's code is compiled once per network shape; NetworkDynamics' workload in its image.

---

## 5. The experiment row

E-155, for [`../record/experiments.md`](../record/experiments.md) §11, registered before S0 runs:

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-155 | W-32 P6: the SciML core under NetworkDynamics made trait modules from the bottom up, under strict mode ([the inside-out plan](../plans/2026-10-21-ndport-inside-out.md)). Tier S, product setting; strict mode on for every check except order B and the joint owners' loads (J); NetworkDynamics wrapped as in N (`p3-wrap`); P1's load order; one run per step; one pinned TraitWorld commit. Steps S1–S7: SymbolicIndexingInterface and RecursiveArrayTools; SciMLBase with `@joint_owners` (eight packages); NonlinearSolveBase, BracketingNonlinearSolve and SciMLJacobianOperators; the NonlinearSolve family; DiffEqBase; OrdinaryDiffEqCore (with `@joint_owners OrdinaryDiffEqDifferentiation`), Tsit5 and DiffEqCallbacks; OrdinaryDiffEqRosenbrock. (1) Does each step precompile and run the workload with strict mode on (shown on), without a refusal, with U's digests bit for bit? (2) How many pirates does the census show in wrapped packages (target 0), and how many methods rest on joint ownership, per package? (3) Do steps c, d and e stay within 10 % + 5 ms of I0 in the steady state, and does the dispatch profile of a steady-state pass show new run-time sites in the newly wrapped modules? (4) What does the first simulation (steps a–e, first pass) cost per step, against I0 and U (21.5 s), and by module at S4 and S7? (5) In order B at S4 and S7, what does the plotting load take, by module and owner, and is every loss of the facts owner explained by a route of facts §2.2? (6) Does strict mode refuse a pirate winning in SciMLBase's code (S2) and E-153's pirate on duals with the refusal's caller in SciML's code (S7)? (7) What does each step cost to precompile? (8) How much code of the facts owner do joint owners' loads discard, by module, at S4 and S7? (9) Do the wrapped packages' own quick tests pass as at `upstream`? Measures upstream's code with the declarations of the plan's §2.4, compiled by facts as trait modules (no trait code, neither interop nor idiomatic). **Would change the plan:** a refusal the census does not explain (a missing joint owner, or a true pirate to classify); strict mode not on in a run (the run is void); an exact digest difference (a G1 failure: open issue); a steady-state step outside 10 % + 5 ms of I0, or a new run-time site on the per-step path (a fix in the owning package before the next step, as P3-1's); an unexplained loss in order B (a G2 failure: open issue and work item; P6 pauses); a large share of a wrapped package's image discarded by joint owners' loads (pushback, and possibly an open issue on joint owners' cost); SciMLBase failing to wrap under `@trait_module`'s statement-by-statement treatment (porting 0.1a's open question; a TraitWorld deviation row); a package's own test failing where it passes at `upstream` (a G1 failure off the workload's path); the first simulation not falling by S7 (then the images do not hold what the trait code reaches, and the lever is the workloads). | proposed (2026-10-21) | `ndport/` (its own repository): `scripts/p6_census.jl`, `p6_profile.jl`, `p6_strict_probe.jl`, `p6_joint_probe.jl`, `p6_loadinv.jl`, `p6_precompile.sh`, `run_workload.sh` (settings `I`, `IC`), `clone.sh --from-depot`, `p3_loads.jl`, `p3_pirate.jl`, `nd_tests.jl`; `logs/p6/`; the trees `pkgs/*-p6` (branch `p6-inside-out`, tags `p6-s<k>`) and `pkgs/OrdinaryDiffEq-p6-ros` (branch `p6-inside-out-ros`), `env_p6`, `env_p6test`, `env_p6c`, `depot-p6`; at the merge `env_merged`, `depot-merged` | — | `ndport/README.md`; [the inside-out plan](../plans/2026-10-21-ndport-inside-out.md) |

- When E-155 is done, its outcome and an evidence row go in one commit (CLAUDE.md, rule 1).
- The porting guideline's B5 gains the lessons (the coordinator adds them).

---

## 6. Expected pushback

In the log's shape ([`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md)), numbered by part as the log does: P6-1, P6-2, …. An entry is written to the log, and its ID becomes permanent, when E-155 meets it.

**P6-1. A core package needs its implementers named before it can be a trait module.**
- *The code:* DiffEqBase's `solve(prob::AbstractDEProblem, args...)` (`solve.jl:653`), NonlinearSolveBase's `solve(prob::AbstractNonlinearProblem, …)` (`src/solve.jl:76`), BracketingNonlinearSolve's `solve(prob::IntervalNonlinearProblem, …)` (`src/BracketingNonlinearSolve.jl:46`), NonlinearSolve's default `__init(prob::NonlinearProblem, ::Nothing, …)` (`src/default.jl:25`), LinearSolve's `init(prob::LinearProblem, args...)` (`src/common.jl:382`), OrdinaryDiffEqDifferentiation's `alg_autodiff` on OrdinaryDiffEqCore's algorithm types (`src/alg_utils.jl:4`).
- *The idiomatic form:* an interface package with implementation packages, each extending the interface's functions on the interface's types.
- *The reference:* [traits §10.1](../reference/traits.md#101-who-may-implement), joint owners; [§10.2](../reference/traits.md#102-pirates).
- *What it costs:* a line in SciMLBase naming eight packages, and one in OrdinaryDiffEqCore. Three of the named stay plain. Each name widens G2's exception for the owner's code: its joint owners' changes are a stakeholder's.
- *Blocks:* no; joint owners are built.

**P6-2. A declaration in one package widens G2's exception in another's code** (only if check J shows it).
- *The code:* NonlinearSolveBase's fallback `initialization_alg(initprob, autodiff) = nothing` (`src/initialization.jl:57`), which NonlinearSolve's method (`default.jl:71`) overrides at every concrete nonlinear problem. NonlinearSolve is a stakeholder there only through SciMLBase's line. The same holds for the owner's own image: SciMLBase's facts code when DiffEqBase loads after it.
- *The idiomatic form:* an interface's image stays valid when its implementations load.
- *The reference:* [facts §11](../reference/facts.md#package-images); [§2.2](../reference/facts.md#g2), the stakeholder's exception; [traits §10.1](../reference/traits.md#101-who-may-implement), "What it costs".
- *What it costs:* check J's counts by module, every session.
- *Blocks:* no.

**P6-3. Hooks with no type of the provider's in their signature.**
- *The code:* `wrapfun_iip(ff, inputs)` (`norecompile.jl:31`), `promote_tspan` with five untyped arguments (`solve.jl:858`), `isadaptive(alg) = false` (`alg_utils.jl:312`); SciMLBase's docs call these "extension hooks for packages that provide the callable-wrapper backend" (`SciMLBase.jl:2079`–`2114`).
- *The idiomatic form:* the interface declares a function; "the" provider fills it, keyed on nothing it owns.
- *The reference:* [traits §10.1](../reference/traits.md#101-who-may-implement): an implementation follows ordinary ownership, so no trait can hold such a hook either.
- *What it costs:* joint ownership, or a move into the owner where the body allows it.
- *Blocks:* no.

**P6-4. A trait module's refusal misses pirates made by a macro.**
- *The code:* DiffEqBase's `solve` and `init` under `Base.@constprop :aggressive` (`solve.jl:150`, `:653`).
- *The idiomatic form:* annotated definitions, checked like any other.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates); [T-56](../reference/traits.md#17-deviations).
- *What it costs:* a census after loading at every step; the wrap alone would admit these pirates.
- *Blocks:* no. Already T-56; the entry records where the port meets it.

**P6-5. A recipe macro writes a pirate into every recipe package.**
- *The code:* Makie's `@recipe` writes `Makie.symbol_to_plot(::Val{:GraphPlot})` into GraphMakie (`Makie/src/recipes.jl:192`, `:542`).
- *The idiomatic form:* registering a plot type under its symbol.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates); a joint owner cannot help, since Makie cannot name every recipe package.
- *What it costs:* GraphMakie cannot be wrapped whole until Makie's macro registers by the plot type.
- *Blocks:* wrapping GraphMakie; not P6.

**P6-6. Wrapping a core package moves a plain caller's first call into facts compilation.**
- *The code:* the workload's `solve(prob, Tsit5())` from plain code, after S6.
- *The idiomatic form:* the solver's first call costs what it costs plain.
- *The reference:* [facts §6.2](../reference/facts.md#the-mode-rule), [§11](../reference/facts.md#package-images); [lowering §15.2](../reference/lowering.md#152-workloads).
- *What it costs:* check F at S6 against S5.
- *Blocks:* no. The images' workloads are the lever. P3's expected entry (e) is the same cost seen from above.

**P6-7. A plotting load brings stakeholders' extensions into the core's facts** (only if order B shows it).
- *The code:* `SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt` (a joint owner's), `RecursiveArrayToolsStructArraysExt`.
- *The idiomatic form:* extensions that declare implementations, which win at no fact.
- *The reference:* [facts §2.2](../reference/facts.md#g2), the exceptions; [traits §10.3](../reference/traits.md#103-strict-mode), the warning for an extension.
- *What it costs:* check B's explained losses at S4 and S7.
- *Blocks:* no. P3's expected entry (d), now on the core.

**P6-8. A folded constructor may stop folding under facts** (only if Tsit5's fold check or check T at S6 shows it).
- *The code:* Tsit5's `perform_step!` builds its tableau on every step with `@OnDemandTableauExtract` (`OrdinaryDiffEqTsit5/src/tsit_perform_step.jl:9`; `OrdinaryDiffEqCore/src/misc_utils.jl:213–224`), from a constructor marked `@fold`, that is `Base.@assume_effects :foldable` (`misc_utils.jl:274`; `tsit_tableaus.jl:103`, `:244`, `:289`).
- *The idiomatic form:* constants asserted foldable fold, whatever owner compiles them.
- *The reference:* [facts §8](../reference/facts.md#8-asserted-effects); F-16.
- *What it costs:* about thirty conversions per step, with no dynamic dispatch, so the dispatch profile shows nothing; T's step d and the fold check do.
- *Blocks:* no. A fix would go into the owning package, as P3-1's.

---

## 7. Choices for the user (for the meta plan's list)

Numbered from 25 (the graph plan takes 17–24):

25. **Inside out with NetworkDynamics wrapped from the start.** The core grows from SciMLBase's interfaces up to the solvers under setting N's NetworkDynamics (`p3-wrap`, read only), rather than wrapping NetworkDynamics last. Reason: E-153's numbers are against N, and P4 builds on it.
26. **What stays plain:** ForwardDiff, LinearSolve, Static, OrdinaryDiffEqDifferentiation (its `resize!` pirate, G19, is not moved), SteadyStateDiffEq, the small interface and utility packages, the plotting side, Graphs, and every extension (§1.2). S7 wraps Rosenbrock alone above a plain Differentiation.
27. **The joint owners:** SciMLBase names DiffEqBase, NonlinearSolveBase, NonlinearSolve, BracketingNonlinearSolve, NonlinearSolveFirstOrder, LinearSolve, SteadyStateDiffEq and OrdinaryDiffEqCore. OrdinaryDiffEqCore names OrdinaryDiffEqDifferentiation, from S6. A step's census may add names by §2.4's rule. OrdinaryDiffEqCore in SciMLBase's line is needed for G9 once no move is made; the reference's own example names it.
28. **No code edits in SciML to resolve pirates.** The one-line moves are recorded as possible restructurings (Appendix A, for [`../design/alternatives.md`](../design/alternatives.md), "Split packages"). Narrowing `interp_summary` to `OrdinaryDiffEqCache` is not among them: it would break showing an SDE solution.
29. **The plotting side's pirates classified, not resolved:** Makie's 8 and GraphMakie's 2 wait until that side is wrapped (§2.2, G10–G13).
30. **Packages not cloned are made from the depot's exact trees** (the NonlinearSolve family), checked by tree hash, without network. OrdinaryDiffEqRosenbrock gets a second worktree at its release's commit, with its own branch and tags.
31. **Seven steps,** zero-pirate neighbours grouped to save builds; SciMLJacobianOperators with NonlinearSolveBase, which depends on it.
32. **The fixed point's path (step 4) before the solver (step 5),** in the order the workload runs.
33. **Strict mode on for every check, during precompilation too, and shown on in each log;** a positive control at S2; order B and J with strict mode off, because they read the invalidation log.
34. **Quick checks per step:** the workload session, and the census with the dispatch profile of a steady-state pass. The packages' own quick tests after S2, S6 and S7. Order B, the attribution and J at S4 and S7; the pirate at S7.
35. **The merge:** after P6's S6 and P4's step 2 or 3, before P4's step 4, in a fresh `env_merged` and `depot-merged`, on new `port` branches; one TraitWorld commit; strict off, then strict on; the steady-state reference P4 after open issue 48's fix (step d 33.1–41.2 ms, `ndport/logs/p4-issue48/`).
36. **TraitWorld pinned** to 3bebf13 for S0–S7 (open issue 48 closed).

---

## 8. Risks

Each with the step where it starts and the check that catches it.

1. **SciMLBase's size under `@trait_module`** (S2; P and Q). Each top-level statement runs after the ones before it ([traits §2](../reference/traits.md#2-trait-modules)). Whether that holds up on SciMLBase (3,282 methods, `@reexport`, RuntimeGeneratedFunctions' `init`) is porting 0.1a's open question. A failure is a TraitWorld deviation row; the step pauses.
2. **Tsit5's folded tableau** (S6; T on step d, and a fold check). Upstream relies on folding a `@fold` constructor on every step (P6-8). From S6 this code is reached from OrdinaryDiffEqCore's trait code, so it is compiled by facts. It folds only if its frame has no run-time site (facts §8); F-16 shows the two owners can disagree. **The fold check,** in S6's C+H session: `code_typed` of `perform_step!` for the workload's Tsit5 cache type, under the facts owner, shows no construction of `Tsit5ConstantCacheActual`. Rosenbrock uses no `@fold`.
3. **Callback conditions typed by `promote_op`** (S6; T on step d). OrdinaryDiffEqCore's `_condition_return_type` calls `Base.promote_op(condition, …)` on the user's condition (`OrdinaryDiffEqCore/src/solve.jl:186–189`) and wraps it with that return type. NetworkDynamics' conditions are facts methods, and for a facts method the answer at run time can be wider than the folded one ([facts §7.1](../reference/facts.md#return-type); open issues §2, item 30). Then the wrapper returns `Any`, boxed: the same results, slower root finding. That path serves `ContinuousCallback`. NetworkDynamics gathers its component callbacks into a `VectorContinuousCallback` (`NetworkDynamics.jl/src/callbacks.jl:123`), whose path uses `Nothing` (`OrdinaryDiffEqCore/src/solve.jl:109–129`). S6's C+H session confirms which path the workload takes.
4. **More run-time sites like P3-1's** (every step; H and T). The core compiled by facts may lean on Base folding its type computations. The profile of a whole steady-state pass, grouped by module, shows them; the fix goes into the owning package (B5).
5. **FunctionWrappers** (S5, S6; B). DiffEqBase's `promote_f` wraps an in-place right-hand side under `AutoSpecialize` (`DiffEqBase/src/solve.jl:1038–1060`); OrdinaryDiffEqCore wraps the callbacks (`solve.jl:90–155`). Calls go through a C function pointer into FunctionWrappers' plain code; NetworkDynamics' methods behind it stay facts methods. No cost hazard, but order B may lose the wrappers' plain CodeInstances (§3.1, expected losses).
6. **RuntimeGeneratedFunctions** (S1, S2; R). SymbolicIndexingInterface uses them in 10 places, SciMLBase in 3. Their bodies come from a global cache, not from methods. Low risk; R covers what the workload touches.
7. **Generated functions** (S1, S2, S5, S6; R, Q). The census's counts of methods with generators: SciMLBase 11, OrdinaryDiffEqCore 27, DiffEqBase 3, SymbolicIndexingInterface 2, RecursiveArrayTools 4. A generator runs in its definition's world (E-141).
8. **Unions at run-time sites** (every step; H). The facts mode splits a union by its own rule ([facts F-15](../reference/facts.md#deviations), open issue 46). `@max_methods 1` (in SciMLBase, `SciMLBase.jl:3–4`, inside an `if`, through `@eval`; in DiffEqBase and OrdinaryDiffEqCore) changes nothing at a run-time site (porting 0.1a).
9. **Off the workload's path** (S2, S6; Q). `DefaultCache`'s `promote_op`s (`OrdinaryDiffEqCore/src/caches/basic_caches.jl:175–180`) and the ensembles' `Core.Compiler.return_type` (`SciMLBase/src/ensemble/basic_ensemble_solve.jl:517`, `:581`) answer by inference of facts methods. The packages' tests reach some of them.
10. **A wrapped package's precompile may cost more** than its plain build (P). If a step's build exceeds 10 minutes, the step pauses and the cost is recorded.
11. **Extensions stay plain** (S5 on; B). Rodas5P's dual methods (`DiffEqBaseForwardDiffExt`, `RecursiveArrayToolsForwardDiffExt`) are plain code, reached by facts from wrapped callers. A joint owner's extension is a joint owner too.
12. **The cap of ten cache files** per package in `depot-p6` (§3.2).
13. **Strict mode does not yet refuse pirates loaded before the code they change** (F-6). The bottom-up order keeps the implementers after the core; the census covers the rest (§2.3).
14. **TraitWorld changes mid-track** (§3.2). I0 and the last step run again on the new commit.
15. **Open issue 20** (whether trait modules keep refusing every pirate) and **19** (whether the standard libraries are owners of their own) may change what the census counts. P6 follows the references as they stand.

## 9. Done when

1. E-155 is registered; the trees, `env_p6`, `depot-p6` and the harness's setting `I` exist; TraitWorld is pinned at 3bebf13; S0's extended census reproduces P0's 63 and is logged, with the joint-owner probe.
2. S1–S7 are committed and tagged, each with P, R, S, C, H, F, T and L logged in `ndport/logs/p6/`, strict mode shown on.
3. The census shows no pirate in a wrapped package at every step. The methods resting on joint ownership are counted per package.
4. The positive control has run at S2; the packages' quick tests after S2, S6 and S7.
5. Order B, the attribution and J have run at S4 and S7; every loss of the facts owner is explained, or recorded as a G2 failure with an open issue and a work item.
6. The pirate has run at S7 with the refusal's caller printed.
7. `ndport/README.md` has a dated table per step, with the builds, the trees' commits, strict mode, the load order, one run each, and the load average. Each number says it measures upstream's code with the declarations, compiled by facts.
8. E-155's outcome and an evidence row are in one commit. The pushback entries met are in the log.
9. The meta plan shows P6 in its parts table and its state, with choices 25–36 in its list.
10. The merge with P4 (§4) is done or scheduled, with its preconditions met.

---

## Appendix A. Moves a different structure would allow (for the alternatives)

For [`../design/alternatives.md`](../design/alternatives.md), "Split packages". Each removes a pirate by the letter. None removes a declaration: DiffEqBase and OrdinaryDiffEqCore are named as joint owners anyway (§2.4). P6 makes none of them.

| # | The method | Where | The move | What it changes |
|---|---|---|---|---|
| 1 | `Base.isempty(cb::CallbackSet)` | DiffEqBase, `lib/DiffEqBase/src/callbacks.jl:81` | into SciMLBase, which owns `CallbackSet` | nothing for users |
| 2 | `Base.isempty(cb::AbstractContinuousCallback) = false` | `callbacks.jl:84` | into SciMLBase | nothing for users |
| 3 | `Base.isempty(cb::AbstractDiscreteCallback) = false` | `callbacks.jl:85` | into SciMLBase | nothing for users |
| 4 | `SciMLBase.isfunctionwrapper(x::FunctionWrapper) = true` | DiffEqBase, `src/DiffEqBase.jl:116` | into SciMLBase's `function_wrappers.jl`; FunctionWrappers joins SciMLBase's `[deps]` (it is already in the manifest, through FunctionWrappersWrappers) | a new direct dependency of SciMLBase |
| 5 | `SciMLBase.unwrap_fw(fw::FunctionWrapper) = fw.obj[]` | DiffEqBase, `src/norecompile.jl:26` | as 4 | as 4 |
| 6 | `SciMLBase.isadaptive(alg) = false` | OrdinaryDiffEqCore, `lib/OrdinaryDiffEqCore/src/alg_utils.jl:312` | into SciMLBase, as its own function's fallback | SciMLBase's contract (`alg_traits.jl:98–110`, documented for `AbstractDEAlgorithm`): `false` where a `MethodError` came before, in every session without OrdinaryDiffEqCore |
| 7 | `SciMLBase.interp_summary(::Type{cacheType}, dense::Bool) where {cacheType}` | OrdinaryDiffEqCore, `src/interp_func.jl:73` | narrowed to `cacheType <: Union{OrdinaryDiffEqCache, StochasticDiffEqCache}`, both OrdinaryDiffEqCore's | nothing for users. Narrowing to `OrdinaryDiffEqCache` alone breaks showing an SDE solution: SDE solutions reuse `InterpolationData` (`solve.jl:819`; `dense/generic_dense.jl:861`), and their cache is a `StochasticDiffEqCache` (`algorithms.jl:169`), not an `OrdinaryDiffEqCache` |
| 8 | `EnzymeCore.EnzymeRules.inactive_noinl(::typeof(check_error!), args...) = true` | OrdinaryDiffEqCore, `src/enzyme_rules.jl:25` | into `SciMLBaseEnzymeExt` (trigger Enzyme), which holds SciMLBase's Enzyme rules | nothing: only Enzyme reads the rule |

Related, recorded with them:
- **`promote_tspan(u0, p, tspan, prob, kwargs)`** (DiffEqBase, `solve.jl:858`, with `_promote_tspan` below it): about eight lines could move into SciMLBase. It removes one pirate of G3, and no declaration.
- **`Base.resize!(p::LinearSolve.LinearCache, i) = p`** (OrdinaryDiffEqDifferentiation, `src/linsolve_utils.jl:124`), a true pirate. The options:
  - move it into LinearSolve: one line, but `resize!` of a `LinearCache` then answers for every user, and LinearSolve needs a clone;
  - a function of OrdinaryDiffEq's own at its three call sites (`OrdinaryDiffEqNonlinearSolve/src/utils.jl:1367`, `OrdinaryDiffEqPDIRK/src/pdirk_caches.jl:24`, `OrdinaryDiffEqSDC/src/sdc_caches.jl:55`; none loaded by the workload);
  - Differentiation stays plain (P6's choice 26).
- **The plotting side:** Makie's G11 (three one-line moves into ComputePipeline and ShaderAbstractions), G10's `add_input!` into a ComputePipeline extension on ShaderAbstractions, G13's registration by plot type in Makie's `@recipe`.
