# The NetworkDynamics port, P3: the facts mode first

Status: **proposal; part P3 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md).** Not normative: the references hold ([`../reference/facts.md`](../reference/facts.md) above all). Written 2026-10-21, before any P3 run.

**The question** (the user's goal, [W-32](../record/todo.md): "reap the biggest possible benefits of Trait and Facts mode with minimal changes to the code"): what do NetworkDynamics, SciML, GraphMakie with Makie, and Observables gain from the facts mode before any trait is written, and what is the smallest change that gets it?

**What P3 does not do.**
- It writes no trait. Traits are P2's and P4's.
- It changes no reference. Where the stack pushes back, the entry goes to the pushback log (§9).
- It runs quick checks, not benchmarks. Measurement rounds are P5's.

Paths are relative to the repository root. `ndport/` is the workspace (its own repository). The settings U, P0, A0 and S, the workload (tier S), the harness and the digests are [the P1 plan](2026-10-21-ndport-workload.md)'s. Line references into packages are to the clones in `ndport/pkgs/`.

## 0. Summary

- **Under the test bed `all` (A0), with no change at all,** every line of the stack is code compiled by facts. G1 and G2 hold for all of it, with the exceptions [facts §2.2](../reference/facts.md#g2) names and the shared cache of [F-2](../reference/facts.md#deviations). The stack precompiled under `all`: 476 packages in 353 s (§5.9).
- **In the product setting, an unchanged package gains nothing.** It is plain code. Only trait code, and what it reaches, is compiled by facts ([facts §12.1](../reference/facts.md#product-setting)). There are three ways to make trait code, from the smallest change up:
  - **W, the workload's own module as a trait module.** No package changes. Everything the workload's code reaches by inference or by a generic call is compiled by facts, whoever owns it ([facts §6.2](../reference/facts.md#the-mode-rule)). This is TraitReport's form (b) ([evidence §3](../design/evidence.md#3-first-calls-and-sessions)).
  - **N, NetworkDynamics wrapped in `@trait_module`:** three lines in its module file, and TraitWorld as a dependency. ND's code is compiled by facts whoever calls it. The solver's driver, reached from the user's plain `solve`, stays plain.
  - **DiffEqBase or OrdinaryDiffEqCore wrapped:** blocked by pirates by the letter (§1.5). P3 only lists them.
- **The first package to wrap is NetworkDynamics** (§1.5). It has the hot path and the seams, it owns what it defines, nothing in the stack depends on it, and it sets no compiler options.
- **The benefits to show, each with a quick check** (§2):
  - **load-order protection:** the user simulates first and plots later. Loading CairoMakie, GraphMakie and Observables after the first solve brings 167 more packages. Among them are Unitful, IntervalArithmetic and Distributions, and four extensions of the stack's own packages (§2.1). P3 counts the CodeInstances that load discards, in P0, A0, W and N.
  - **strict mode:** a pirate `+` on ForwardDiff's duals, defined after the first Rodas5P solve. It wins inside the network's Jacobian. It is followed by default and refused in strict mode (§2.2).
  - **the cost of `all`:** the steady-state passes against U (§2.3), and loads and first calls (§2.4).
- **The registry row** is E-153 (§6). **What P3 feeds into P4** is in §8: which code must be trait code for the product setting to protect the workload, and which pirates must move first.

---

## 1. What the facts mode promises this stack

### 1.1 The guarantees, read for this stack

- **G1, identical or error** ([facts §2.1](../reference/facts.md#g1)):
  - code compiled by facts computes what plain code computes, in the same world, or raises;
  - the "raises" comes only from a `Dynamic` operation's or a `Callable`'s declared result, and P3 has neither;
  - so the workload's results must equal plain Julia's.
  - **The one exception:** values decided by inference (`return_type`, the element types of empty `map`s and broadcasts). P1's digests contain none, as far as the code shows.
  - **Last-bit differences** are not G1 failures. `muladd` and `@simd` may round differently when code is inlined differently. Every setting that compiles the stack by facts is compared against U within P1's tolerances ([P1 §4](2026-10-21-ndport-workload.md#4-equality-of-results)).
- **G2, stable caches** ([facts §2.2](../reference/facts.md#g2)):
  - no load of an unrelated package invalidates code compiled by facts;
  - only a stakeholder's change, or a pirate that wins at one of the code's facts, can.
  - **The stated exceptions this stack can meet:**
    - **A stakeholder's package extension activated by an unrelated package.** Four extensions of the stack's packages are triggered by the plotting load (§2.1). Each is its parent's change: followed, never refused.
    - **The standard libraries count as Julia's own code** ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)). SparseArrays is already loaded by NetworkDynamics, so its methods are in place before the first solve.
    - **Plain inference's answers behind a run-time `return_type`** are not covered ([facts §7.1](../reference/facts.md#return-type)). A load that changes plain inference changes them. They are recomputed, by design.
- **Not promised** ([facts §13](../reference/facts.md#not-promised)):
  - the speed of code that is not fully typed (Makie's compute graph, Observables);
  - protection for plain code in the product setting;
  - threads (the workload runs with one thread).

### 1.2 Under `all` (setting A0): no change at all

- **What holds:** every method but the compiler's is compiled by facts ([facts §12.2](../reference/facts.md#the-test-bed)). So G1 and G2 cover the whole stack: NetworkDynamics, NonlinearSolve, OrdinaryDiffEq, SciMLBase, SymbolicIndexingInterface, Makie, GraphMakie, Observables and Base.
- **The caveats:**
  - **F-2:** under `all`, code compiled by facts shares the default cache owner with the compiler's plain results. A count of lost CodeInstances therefore covers the stack's packages only, as [`experiments/factscompiler/control/lost.jl`](../../experiments/factscompiler/control/lost.jl) does. Base is counted apart.
  - **F-7:** an image does not record the setting. So `all` uses its own depot, `ndport/depot-facts/`, and nothing else writes there.
  - **`all` is the test bed, not a user setting.** It shows what the facts rule does to code as it is written. It promises nothing to a user.
- **What the evidence leads us to expect** (not a claim about this stack):
  - upstream CSV and DataFrames under `all` lost 2 of 3,337 CodeInstances to nine unrelated loads, against 561 of 4,684 in plain mode ([evidence §1](../design/evidence.md#1-the-guarantee), the control);
  - a plotting session under `all` saved 6–10 s of recompilation and paid 91–169 ms per round in Makie's machinery (E-140, [evidence §3](../design/evidence.md#3-first-calls-and-sessions)).

### 1.3 In the product setting: trait code only

An unchanged package is plain code. It gains nothing ([porting guideline 0.1](../intro/porting.md#01-what-the-facts-mode-gives-an-unchanged-package)). The facts mode reaches this stack only through trait code. That code is compiled by facts, and so is every neutral method it reaches by inference or by a call the code generator emits ([facts §5](../reference/facts.md#run-time-sites), [§6.2](../reference/facts.md#the-mode-rule)).

**Which code of the workload is compiled by facts, per setting:**

| Code on the workload's path | U, P0 | A0 (`all`) | N (ND wrapped) | W (workload's module wrapped) |
|---|---|---|---|---|
| the workload's functions (`swing!`, `line!`, the steps) | plain | facts | facts where ND's code calls them (the core loop calls `swing!`); plain elsewhere | facts |
| NetworkDynamics: construction, the core loop, symbolic indexing, its callbacks | plain | facts | facts, whoever calls | facts |
| what ND's methods call: NonlinearSolve in `find_fixpoint`, SciMLBase's constructors in `ODEProblem(nw, …)`, ForwardDiff, Graphs | plain | facts | facts on those paths | facts |
| the solver: `solve`, OrdinaryDiffEqCore's integrator, the Tsit5 and Rodas5P steps, DiffEqCallbacks | plain | facts | plain: the workload calls `solve` from plain code; the step calls ND's core loop, which is facts | facts |
| solution access: SciMLBase, SymbolicIndexingInterface, RecursiveArrayTools | plain | facts | plain, except ND's methods it calls | facts |
| Makie, GraphMakie, CairoMakie, Observables | plain | facts | plain | facts, except code entered through the runtime's `jl_apply` (tasks, finalizers, `@cfunction` pointers): plain |
| what package images hold | plain code | code compiled by facts | ND's image: ND's code under the facts owner (its workload runs ND's methods); the others plain | plain code; W's code is compiled by facts in the session |
| covered by G2 | nothing | all of it (F-2) | ND's code and what it reaches | what the workload reaches, except through `jl_apply` |

**The cost each form pays for its first call:**
- **A0:** images under `all` hold code compiled by facts.
- **N:** ND's image holds ND's code compiled by facts.
- **W:** no image holds code of the facts owner for the workload's paths. W's first pass compiles everything it reaches again, by facts (§2.4). A precompiled package with a workload would put that code into an image. In P3 the workload stays a script.

### 1.4 What wrapping a package in `@trait_module` requires

The checklist for N, and for any later wrap ([traits §2](../reference/traits.md#2-trait-modules), [porting guideline 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)).

1. **The edit.** In the package's module file, `using TraitWorld`, then `@trait_module begin … end` around the package's body. The `module` line cannot carry it ([traits §2](../reference/traits.md#2-trait-modules)).
   - `@trait_module begin` sets the module option on the package's root module, so the whole package becomes the trait module.
   - A submodule takes its parent's flag when it is created ([compiler §2.1](../reference/compiler.md#21-the-module-option)). NetworkDynamics has no submodules.
2. **The dependency.** TraitWorld goes into the package's `[deps]`. `env_port` already tracks TraitWorld by path, so the environment is resolved again offline. `check_env.py` then allows that one new dependency.
3. **Pirates.** A pirate defined in a trait module is refused at its definition, with `OwnershipError` ([traits §10.2](../reference/traits.md#102-pirates)). During precompilation that fails the build.
   - Find the pirates first, with the census (§3, `p3_census.jl`).
   - A pirate moves out of the trait module: to its owner's package (the principled fix), or to a plain module outside the trait module (A7's layout).
   - `TraitWorld.delegate!(Core => Impl)` serves strict mode only. The wrap's ownership check (`owned_method`, `TraitWorld/src/ownership.jl:213`) does not read delegates ([porting guideline 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module); [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).
4. **Package extensions** are modules of their own. They stay plain unless they are wrapped too.
   - An extension of a trait module counts as its parent for ownership ([traits §10.1](../reference/traits.md#101-who-may-implement)).
   - In strict mode, an extension's method that wins at a fact of trait code is followed, with a warning ([traits §10.3](../reference/traits.md#103-strict-mode)).
   - NetworkDynamics' four extensions (DataFrames, MTK, Symbolics, CUDA) stay plain. Tier S loads none of them.
5. **Compiler options.**
   - `@max_methods 1` is set in SciMLBase, DiffEqBase, OrdinaryDiffEqCore and Makie; `@optlevel 0` in Observables (`Observables.jl/src/Observables.jl:9`). NetworkDynamics sets none.
   - A module's compiler options apply to its facts code as well. The exception is `compile`, which is ignored there ([C-6](../reference/compiler.md#deviations)). The stack does not set `compile`.
   - At a run-time site `@max_methods` changes nothing, since the facts mode speculates over nothing there.
6. **Precompile workloads.**
   - PrecompileTools' `@compile_workload` stays as it is until the module has bounded functions. After that it becomes `TraitWorld.@workload`, which fixes the entries first ([lowering §15.2](../reference/lowering.md#152-workloads)).
   - With TraitWorld loaded while the package builds, keep-compiled is on ([lowering §2](../reference/lowering.md#2-modes-owners-and-images)). So ND's image keeps the code its workload compiles by facts, including Base's methods on ND's paths. Its image grows. P3 records the size.
7. **A trait's name on an argument outside trait modules is refused** ([traits §2](../reference/traits.md#2-trait-modules)). Before traits exist this changes nothing. Once P4 declares traits in NetworkDynamics, its extensions and other packages that name them on arguments must be trait modules too, or take `Kept{X}`.
8. **What the wrap runs** (`TraitWorld/src/trait_module.jl`):
   - each top-level statement is expanded after the ones before it run;
   - each plain function definition is followed by an ownership check;
   - at the module's end, `_finish_module` checks the bounded functions, of which there are none yet.
   - Whether this holds on 15,000 lines is part of the test ([porting guideline 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)).
9. **Where it lives.** The wrap is a branch `p3-wrap` from `upstream` in the clone. It is not committed to `trait-port`. P4 decides whether it becomes the port's first step (§8).

### 1.5 The first candidate: NetworkDynamics

| | NetworkDynamics | DiffEqBase | OrdinaryDiffEqCore |
|---|---|---|---|
| **Pirates by the letter** (read from the source; the census decides) | none found: its methods are on its own types (`Network`, `NWState`, `SymbolicIndex`, …) or are its own functions | several: `Base.isempty(::CallbackSet)` (`DiffEqBase/src/callbacks.jl:81`; `CallbackSet` is SciMLBase's, `SciMLBase.jl/src/callbacks.jl:488`), `SciMLBase.isfunctionwrapper(::FunctionWrapper)` (`DiffEqBase.jl:116`), `__solve` and `__init` on SciMLBase's `AbstractDEProblem` ([exploration §10.6](../explorations/ndport-principled-traits.md#106-cross-package-methods-on-scimlbases-abstract-types-are-pirates-by-the-letter)) | at least one: `SciMLBase.interp_summary(::Type{cacheType}, ::Bool) where {cacheType}` (`OrdinaryDiffEqCore/src/interp_func.jl:73`) |
| **Compiler options** | none | `@max_methods 1` | `@max_methods 1` |
| **What depends on it in the stack** | nothing (only its extensions) | OrdinaryDiffEqCore, Tsit5, Rosenbrock, NetworkDynamics, and more: each wrap rebuilds them all | Tsit5, Rosenbrock, NetworkDynamics |
| **What a wrap protects** | the core loop on every step, construction, symbolic indexing, the fixed point's path into NonlinearSolve | `solve`'s front end and `promote_f` | the integrator's driver and the step loop: the largest compile in step d |
| **Role in P4** | rank 1 of the traits ([exploration §9](../explorations/ndport-principled-traits.md#9-the-ranking)): the seams where the user's equations enter | rank 3 | rank 3, 6 |

**Why NetworkDynamics.**
- It holds the workload's hot path, and it is the place where the user's types enter. P4 starts there, so the wrap is the shell P4 fills.
- It owns what it defines, as far as the source shows. DiffEqBase cannot be wrapped as it is: its pirates are refused, and `delegate!` does not lift that refusal. OrdinaryDiffEqCore has at least one pirate by the letter.
- Nothing in the stack depends on it. A wrap rebuilds ND and its extensions alone, about 12–22 s (§5.9). Wrapping DiffEqBase rebuilds most of the solver stack at every iteration.
- It sets no compiler options.

**What N does not give.** The integrator's driver stays plain in N, because the workload calls `solve` from plain code. If P0 loses the driver's code to the plotting load (§2.1), then N does not protect it. Only W, or a wrapped OrdinaryDiffEqCore, would. That answer is P3's main input to P4 (§8).

---

## 2. The benefits to show, each with a quick check

### 2.1 Load-order protection: simulate first, plot later

**The case.** A user builds and solves the network, looks at the solution, then loads the plotting packages. In P1's order everything loads before the first solve, so nothing is lost. P3 adds **order B**:
1. the loads `TraitWorld` (when the setting needs it), `Graphs, NetworkDynamics`, and the solvers;
2. steps a–e, twice (first and again);
3. a snapshot of every valid CodeInstance;
4. the load `CairoMakie, GraphMakie, Observables`, with Julia's invalidation log on;
5. the CodeInstances lost, counted;
6. steps a–e again, timed ("after"), with the same types;
7. steps f and g, for the first time.

**What the plotting load brings** (read from `ndport/env_port/Manifest.toml`):
- 167 packages beyond the 185 of the simulation's group. Among them are Unitful, IntervalArithmetic (through ExactPredicates), Distributions, StatsBase, OffsetArrays, Interpolations and StructArrays.
- **Extensions of the stack's packages that it triggers:**
  - SciMLBase's `SciMLBaseMakieExt` and `SciMLBaseDistributionsExt`;
  - DiffEqBase's `DiffEqBaseUnitfulExt`;
  - RecursiveArrayTools' `RecursiveArrayToolsStructArraysExt`;
  - extensions of Accessors, ConstructionBase, FillArrays, SparseMatrixColorings and StaticArrayInterface.
- **Third packages' extensions on the stack's functions:** IntervalArithmetic's and Unitful's ForwardDiff extensions. Their methods are for their own types, so they are not pirates.
- So the plotting load contains both kinds of load: unrelated packages, and packages that add methods relevant to the stack.

**The check** (`p3_loads.jl`, §3), in P0, A0, W and N:
- **Lost CodeInstances,** by owner (`nothing`, `:facts`) and by root module. The packages loaded before the plotting load are counted apart from Base and the standard libraries.
- **The cause of each invalidation tree,** from Julia's invalidation log: the defining method and its module, and whether that module owns the method (`owned_method`). This tells a stakeholder's change from a winning pirate.
- **The work after the load:** steps a–e timed, with compile and recompile times. Their digests must equal the first pass's.

**What each setting should show:**
- **P0** is the plain control. It shows what the load costs today: the CodeInstances lost, and the compile time of "after".
- **A0:** the stack's lost CodeInstances are each traced to a stakeholder's extension, a standard library, or a winning pirate. "After" compiles nothing beyond the answers behind `return_type` (§1.1).
- **W and N:** every lost CodeInstance of the facts owner is traced in the same way. A loss that no cause explains is a G2 failure: an open issue and a work item, and P4 waits.

**Stage C (optional): a further load.** DataFrames triggers NetworkDynamics' own extension, `NetworkDynamicsDataFramesExt`, and loads CSV's stack.
- DataFrames is not in either manifest. It needs `ndport/env_loads`: `env_port` plus DataFrames, resolved offline with every shared version kept (`PRESERVE_ALL`), and checked by `check_env.py`. DataFrames and CSV are in `~/.julia/packages`.
- If the offline resolve fails, stage C is skipped and recorded. Resolving with the network is the user's step.

### 2.2 Strict mode: a pirate that would win in the stack's code

**The case:** `experiments/examples/strict/dual_pirate.jl`, moved to the stack.
- The workload runs steps a–d. Rodas5P computes its Jacobian through the network with ForwardDiff's duals, and the aggregation `+` in the core loop adds duals.
- Then a module `Main.Pirate`, which owns neither `+` nor `Dual`, defines `Base.:+(a::Dual{T,Float64,N}, b::Dual{T,Float64,N}) where {T,N}`. It counts its calls and returns ForwardDiff's value.
- Then Rodas5P runs again with a fresh parameter vector.

**Expected** ([facts §10](../reference/facts.md#pirates), [traits §10.3](../reference/traits.md#103-strict-mode)):

| Setting | Strict mode | The definition | Stack's calls of the pirate | Code compiled by facts lost | Digest of d |
|---|---|---|---|---|---|
| N | off | accepted | > 0 | > 0: the winning pirate is followed (G2's stated exception) | equal |
| N | on | `PirateError`, naming the code it would change (T-21: perhaps only the call signature) | 0; plain code does not call it either | 0 | equal |
| W | on | `PirateError` | 0 | 0 | equal |
| A0 | on | not stated by the reference: under `all`, strict mode protects trait code and Base's, the standard libraries' and TraitWorld's code. It does not protect other packages' code (owner `nothing`) ([facts §10.2](../reference/facts.md#strict-mode), the note). Refused if the pirate wins in a Base method's code at duals; accepted otherwise | recorded | recorded | equal |

- The case "pirate defined before the stack loads" is F-6 (Planned): followed silently. P3 does not run it.
- **With strict mode on in W, order B also runs once.** If the plotting load brings a pirate that wins in the workload's code, it is a finding: a real winning pirate in the ecosystem. The evidence found none among 837 pirates by the letter in CSV, DataFrames and CairoMakie ([evidence §1](../design/evidence.md#1-the-guarantee)).

### 2.3 The run-time cost of `all`: the steady state

- **The comparison:** the passes "again" and "params" in A0 against U. These are the `T` lines of `run_workload.sh`, two runs each: P1's runs plus one more A0 run.
- **Expectation:**
  - fully typed numerical code pays nothing ([facts §13](../reference/facts.md#not-promised));
  - steps d (solve) and e (access) should be close to U;
  - steps f and g (Makie, Observables) pay for run-time sites in Makie's compute graph, as E-140's figures did (2.4× to build a figure).
- **For W and N,** the same passes against P0. N should equal P0 within noise: ND's core loop is static ([exploration §1.1](../explorations/ndport-principled-traits.md#11-networkdynamics-where-the-users-functions-reach-the-types)). W should look like A0.
- **Where the run-time sites are** (optional): one A0 run with the dispatch profiler on the "again" pass ([compiler §6.5](../reference/compiler.md#65-the-dispatch-profiler)). It lists the 40 callees and call sites with the most dynamic calls, per owner. A run-time site on the per-step path is a P4 target (A2: make the hot path fully typed).

### 2.4 First calls and loads under `all`, and in W

- **The comparison:** the `L` lines (loads per group) and the "first" pass per step, A0 against U, two runs each. Also W's and N's first pass against P0's.
- **Known so far** (one run each, right after precompiling; `ndport/logs/setup/precompile-*.log`): `using` of the direct dependencies took 11.8 s under `all`, against 5.4 s for `env_upstream` and 6.3 s for `env_port`.
- **W** compiles the stack's reached code by facts in the session (§1.3). Its first pass is the price of protecting everything without changing a package. If it costs more than three times P0's, the porting guideline gets a rule: an application that is a trait module needs a package with a workload.

### 2.5 What "changed" compiles under facts

- P1's attribution run (U) names what a change of equations compiles, by package (`NDW_DIAG=1`, [P1 §3.3](2026-10-21-ndport-workload.md#33-what-changed-compiles)). P3 repeats it in A0, and in W if time allows.
- **Two questions:**
  - Does the facts mode compile less for a new `Network` type? It infers nothing across run-time sites (ND compiled in 11.8 s under `all` against 22.0 s plain at precompile, §5.9).
  - Is Makie's 0.3–0.5 s in "changed" ([P1 §2.4](2026-10-21-ndport-workload.md#24-tier-ss-cost-dry-run)) new code, or code compiled again after an invalidation? The column `again=` says which.

---

## 3. The scripts

All scripts go in `ndport/scripts/`. P1's scripts are not changed while E-151 runs.

| Script | What it does | What it prints |
|---|---|---|
| `p3_census.jl` (P0, one session, about a minute) | Loads the stack and TraitWorld. For each package of the stack (NetworkDynamics, SciMLBase, DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock, DiffEqCallbacks, SymbolicIndexingInterface, RecursiveArrayTools, NonlinearSolve, Graphs, NetworkLayout, GraphMakie, Makie, Observables), walks the method table. It takes the methods defined in the package's own modules (extensions apart), and tests each with `TraitWorld.owned_method` | `P <pkg> methods=<n> pirates=<k> generated=<g> ext_methods=<e>`; one `PIRATE <pkg> <signature> <file:line> function_owner=<o> type_owners=<…>` per pirate; `OPT <pkg> max_methods=<…> optlevel=<…>`, read from the module's compiler options |
| `p3_wrap_nd.sh` | Creates the branch `p3-wrap` from `upstream` in `pkgs/NetworkDynamics.jl`: the three-line wrap (§1.4) and TraitWorld in `[deps]`. Commits it, resolves `env_port` offline, and copies the manifest to `logs/p3-setup/` | the diff, and `check_env.py`'s verdict |
| `ndw_trait.jl` (W's driver part) | `TraitWorld.@trait_module module NDWT include("workload_steps.jl") end; const NDW = NDWT.NDW`. The module `NDW` becomes a submodule of a trait module, and the `include` passes the trait module's treatment on | nothing of its own |
| `p3_loads.jl <setting-tag>` | Order B (§2.1). Needs steps a–e without the plotting packages: P1's `workload_steps.jl` is split into `workload_steps.jl` (a–e, the passes) and `workload_plot.jl` (f, g), which `workload.jl` includes after the plotting group. P1's order and digests do not change. The split is made after E-151's runs and checked by one U run whose digests equal E-151's. The invalidation log (`jl_debug_method_invalidation`) is used only with strict mode off: strict mode uses the same log | `G <load> <s> lost nothing=<n>/<m> facts=<n>/<m> by=<module=n …>` for the packages loaded before, Base and the standard libraries apart; `I <defining method> <module> owned=<bool> ext_of=<parent or -> trees=<n>`, the 20 largest; `T after <step> …` and `D after <step> …` as P1's lines; `S <tag> lost_facts=<n> lost_stack=<n> after_compile_ms=<n>` |
| `p3_pirate.jl <setting-tag>` | §2.2: steps a–d; the pirate in `Main.Pirate` through `try`; Rodas5P again; then a direct `+` of two duals from plain code | `R <tag> strict=<on/off> defined=<accepted/PirateError> calls_stack=<n> calls_plain=<n> lost_facts=<n> lost_nothing=<n> digest_d_equal=<bool>`; the error's text, first 600 characters |
| `run_workload.sh` (P1's), extended | New settings: **W** (`env_port`, `~/.julia`, `NDW_TRAIT_MODULE=1`, which makes `workload.jl` include `ndw_trait.jl`); **N** (`env_port` with ND at `p3-wrap`, depot `ndport/depot-p3:$HOME/.julia:`); **NA** (N under `all`, `depot-facts`; optional). `NDW_DISPATCH=1` resets the dispatch profiler before "again" and prints it after (optional) | P1's lines; the log header names the setting and ND's branch |

`summarize.py` (P1's) gives the tables. `compare_digests.py` (P1's) compares W, N and A0 against U with tolerances.

## 4. The settings and the runs

One Julia job at a time, through the shared lock, niced, as [P1 §3.1](2026-10-21-ndport-workload.md#31-the-harness). No run precompiles. Precompilation is a separate step per setting.

| Setting | Julia | Environment | Depot | Change |
|---|---|---|---|---|
| P0 (P1's) | patched | `env_port` | `~/.julia` | none |
| A0 (P1's) | patched, facts system image | `env_port` | `ndport/depot-facts/` | none |
| W | patched | `env_port` | `~/.julia` | the workload's module is a trait module; no package changed |
| N | patched | `env_port`, ND at `p3-wrap` | `ndport/depot-p3/` before `~/.julia` | ND wrapped |
| NA (optional) | patched, facts system image | as N | `ndport/depot-facts/` | ND wrapped, under `all` |

**The runs, in order** (tags: `logs/p3-census/`, `p3-setup/`, `p3-runs/`, `p3-loads/`, `p3-pirate/`, `p3-diag/`):

| # | Run | Sessions | Required |
|---|---|---|---|
| 1 | `p3_census.jl` in P0 | 1 | yes |
| 2 | `p3_wrap_nd.sh`, then precompilation of N in `depot-p3` | 1 build | yes |
| 3 | `run_workload.sh p3-runs A0 1` (A0's second run), `W 2`, `N 2` | 5 | yes |
| 4 | `p3_loads.jl` in P0, A0, W, N | 4 | yes |
| 5 | `p3_pirate.jl`: N off, N on, W on, A0 on | 4 | yes |
| 6 | the attribution run (`NDW_DIAG=1`) in A0 | 1 | yes |
| 7 | `p3_loads.jl` in W with strict mode on | 1 | yes |
| 8 | the attribution run in W and N; the dispatch profiler in A0; NA with `p3_pirate.jl` (strict mode under `all` for trait code, untested per [evidence §5](../design/evidence.md#5-not-shown)); stage C | up to 6, plus two builds | no |

The required runs are about 17 sessions of 1–3 minutes. W's first pass may take longer (§2.4). If one W session exceeds five minutes, W runs once and the time is recorded.

---

## 5. Risks

1. **Generated functions.** Counts of `@generated` in each package's `src/`:
   - NetworkDynamics 5, SciMLBase 12, DiffEqBase 3, OrdinaryDiffEqCore 13, RecursiveArrayTools 6, SymbolicIndexingInterface 1, Makie 3.
   - A generator runs in the world of its definition. An image's generated code can be made invalid by a package loaded before it (E-141).
   - `p3_loads.jl` marks lost CodeInstances whose method is generated. The attribution runs show generated code compiled again.
   - NetworkDynamics' generators (`utils.jl:144`, `:161`, `component_functions.jl:1134`) run at construction, not per step.
2. **RuntimeGeneratedFunctions.** NetworkDynamics calls `RuntimeGeneratedFunctions.init` (`NetworkDynamics.jl:48`) and uses RGFs for initialization formulas and MTK's components. Tier S reaches neither. The attribution runs confirm that no RGF is compiled. Whether an RGF's call is a fact at concrete types ([exploration §10.11](../explorations/ndport-principled-traits.md#1011-generated-functions-and-runtimegeneratedfunctions)) is tier L's question.
3. **Polyester and KernelAbstractions.**
   - Tier S uses `SequentialExecution` and `SequentialAggregator` (`construction.jl:45`–`46`) and one thread, so neither is reached. The attribution runs confirm it.
   - In tier L, their tasks and `@cfunction` pointers enter through `jl_apply`, which runs the default owner's code ([facts §5](../reference/facts.md#run-time-sites)). W and N would not protect that code.
4. **`@inbounds`, `@simd`, `@muladd`.**
   - OrdinaryDiffEqCore has 113 `@inbounds` and 12 `@simd`; Tsit5 30 and 1.
   - Results compare within tolerance, not exactly (§1.1).
   - Bounds checks are elided in a callee only where it is inlined. A run-time site keeps them. That costs speed, not results.
5. **`invokelatest`** (Observables' `notify`, `Observables.jl:203`–`213`; Makie, DiffEqBase).
   - From code compiled by facts it runs the callee's code compiled by facts ([facts §5](../reference/facts.md#run-time-sites)). It is a dynamic call, as in plain Julia.
   - In N, Observables stays plain.
6. **Makie's compute graph.** Values are held as `RefValue{Any}` and callbacks as `::Function` (`ComputePipeline.jl:36`, `:86`). Under A0 and W every resolve is a run-time site, without Julia's heuristics. Steps f and g pay that cost (§2.3). It is no bug.
7. **`@max_methods 1` at union splits.**
   - SciMLBase, DiffEqBase, OrdinaryDiffEqCore and Makie set it.
   - [Facts §3](../reference/facts.md#facts-and-fact-signatures) makes a union of up to four splits a fact signature. The facts reference does not say whether a module's `max_methods` of 1 stops such a split.
   - The dispatch profiler shows it (run 8). A difference becomes an open issue on the facts reference, not a fix in P3.
8. **Gaps in the wrap's ownership check** (read from `TraitWorld/src/trait_module.jl`, `_process` and `_is_fdef`):
   - only `function` and `=` definitions are checked, and those under `@inline`, `@noinline` and `@doc`;
   - methods made by `@eval` loops (NetworkDynamics' `metadata.jl`, `utils.jl`), by `@generated` and by other macros, and functor definitions `(x::T)(…)`, pass unchecked.
   - The census sees them all, and strict mode sees them at definition. If the census confirms the gap, it is reported for a T- row ([porting guideline 0.7](../intro/porting.md#07-pushback)). P3 does not add the row.
9. **Precompilation: time and disk** (`ndport/logs/setup/precompile-all.log`, julia-1.13 6d480d0753, facts system image of 2026-10-21 02:43):
   - Under `all`: 476 packages, extensions included, in 353 s. The largest: Makie 134 s, NonlinearSolve 35 s, TraitWorld 34 s, CairoMakie 34 s. NetworkDynamics took 11.8 s, against 22.0–22.3 s plain.
   - `env_upstream` on the patched build: 445 packages in 320 s. `env_port` in the product setting: 72 packages in 175 s.
   - `ndport/depot-facts/` holds 974 MB.
   - Makie could not download its texture atlas (no network) and made it during its precompilation, into `depot-facts`' scratch space. If an A0 log shows "Makie is caching fonts" during a run, that run's first-call times are not comparable.
   - N's precompilation rebuilds NetworkDynamics alone (about 12–22 s) into `depot-p3`. NA's rebuilds it into `depot-facts`.
10. **The cap of ten cache files per package** (`julia-1.13/base/loading.jl:3372`).
    - N's caches go to `depot-p3`, so `~/.julia`'s caches for U and P0 are not evicted.
    - Each version of ND precompiled in `depot-facts` adds a file there: upstream, `p3-wrap`, and later P4's steps. After ten, A0's cache of upstream ND is evicted. A0 is then precompiled again before it runs. `run_workload.sh`'s check refuses to run otherwise.
11. **F-2 and F-7** (§1.2): counts under `all` cover the stack's packages only, and each setting uses only its own depot.
12. **The return-type answers** are recomputed after the plotting load, by design (§1.1). In A0 and W, "after" may compile for that reason alone. The attribution's owner column separates it.
13. **`@trait_module` on a package of 15,000 lines** is untried (§1.4, item 8). A failure is a TraitWorld work item. P3 does not work around it in NetworkDynamics.
14. **TraitWorld is loaded from source** in W, N and NA. No run starts while TraitWorld is being edited ([INDEX](../record/INDEX.md), "Standing constraints"). The log names its commit and status.
15. **Strict mode and the invalidation log** use the same Julia switch. `p3_loads.jl` reads the log only with strict mode off.

## 6. The registry row

To add to [`../record/experiments.md`](../record/experiments.md) §11 before run 1, with status running. E-151 is P1's baselines. E-152 is reserved for P4's first port step.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-153 | W-32 P3: what does the facts mode give the unchanged NetworkDynamics stack (tier S; [the P3 plan](../plans/2026-10-21-ndport-facts-first.md))? (1) When the plotting packages load after the first solve (order B), how many CodeInstances are lost, and does the work after the load compile again: plain (P0), under `all` (A0), with the workload's module a trait module (W), and with NetworkDynamics wrapped in `@trait_module` (N)? Is every loss of code compiled by facts traced to a stakeholder's change or a winning pirate? (2) Does strict mode refuse a pirate `+` on ForwardDiff's duals that wins in the network's Jacobian (N, W), and what does it do under `all`? (3) What does `all` cost in loads, first calls and the steady-state passes against U, and W's first pass against P0? (4) Which definitions would a wrap refuse, per package (the census)? **Would change the plan:** a loss of code compiled by facts that no stakeholder's change or winning pirate explains (a G2 bug: open issue and work item; P4 waits); NetworkDynamics failing to precompile or run as a trait module (a TraitWorld work item ahead of P4); pirates in NetworkDynamics' census (they move before the wrap); W protecting the whole workload at a first pass under three times P0's (the guideline's first step becomes "the application as a trait module", and P4 is ordered by the cost of new types, not by protection); steps d or e under `all` taking more than twice U's steady state (the solver's path is not fully typed: P4 makes it so before traits); strict mode accepting the dual pirate in N (a strict-mode bug). | proposed (2026-10-21) | `ndport/` (its own repository, not pushed): `scripts/p3_census.jl`, `p3_wrap_nd.sh`, `ndw_trait.jl`, `p3_loads.jl`, `p3_pirate.jl`, `run_workload.sh`; `logs/p3-*/`; the clone's branch `p3-wrap` | — | `ndport/README.md`; [the P3 plan](../plans/2026-10-21-ndport-facts-first.md) |

- E-153 also gives E-29 (G2 across loads under `all`, proposed) a result on this stack. When E-153 is done, E-29's row links it.
- E-153's outcome and its evidence row go in one commit (CLAUDE.md, rule 1).

## 7. Done when

1. E-153 is in the registry, with status running, before run 1.
2. The census is logged. For NetworkDynamics, the list of pirates is empty, or each pirate's move is named. For DiffEqBase and OrdinaryDiffEqCore, the list exists.
3. NetworkDynamics precompiles as a trait module (N), and the workload runs in W and N. Every tolerance field holds against U. Exact differences are recorded.
4. Order B has run in P0, A0, W and N. Each loss of code compiled by facts is traced to its cause, or recorded as a G2 failure with an open issue and a work item. P0's loss and its compile time after the load are recorded as the control.
5. The pirate runs give §2.2's table, with every digest of step d equal.
6. A0 and U each have two runs. The loads, the first pass and the steady state are compared per step. The attribution run in A0 says what "changed" compiles and whether Makie's share is new code or recompiled code.
7. `ndport/README.md` has dated tables per setting, with the builds (julia-1.13, TraitWorld, the clones and ND's branch), strict mode, the load order, the number of runs and the load average. Every number says that it measures upstream code without traits (W and N: unchanged code compiled by facts), not idiomatic trait code.
8. E-153's outcome and an evidence row are in one commit. E-29's row links E-153.
9. The porting guideline's B5 has P3's lessons in the present tense, added by the port's coordinator. The pushback log exists if §9's entries were met.
10. The meta plan shows P3 done, with a line in its state table.

## 8. What P3 feeds into P4

- **Which code must be trait code for the product setting to protect the workload.** Take the modules whose code P0 loses to the plotting load, and remove those N protects. What remains is the list.
  - If the integrator's driver is on it, the choice is: wrap OrdinaryDiffEqCore, after moving its pirates, or make the user's code a trait module (W).
  - If W protects everything at an acceptable first pass, the guideline's first step for a user is the application as a trait module. P4 then targets the cost of a change of equations: rank 1 of P2, the batch barrier.
- **The wrap of NetworkDynamics** (`p3-wrap`) becomes P4's first step (E-152) if N holds. P4 then switches ND's `@compile_workload` to `TraitWorld.@workload` with its first bounded function (§1.4, item 6).
- **The pirates to move,** per package, from the census. They come before any wrap of DiffEqBase or OrdinaryDiffEqCore, and they depend on [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user).
- **Extensions that win at facts of the solver's code** (§2.1): each one becomes an extension that declares implementations only, when its package is ported (A4; the evidence's InlineStrings case).
- **Run-time sites on the per-step path** (§2.3; the dispatch profiler): P4's targets for A2, fully typed code, before or alongside the traits.
- **What "changed" compiles under facts** (§2.5): it confirms or reorders P2's ranking.

## 9. Pushback P3 expects

Each entry goes to [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) when P3 meets it; the log is created with the first. An entry that needs the user's decision also becomes an open issue.

**a. The pirates of split packages stop a wrap.**
- *The code:* DiffEqBase's `__solve` and `__init` on SciMLBase's `AbstractDEProblem`, `Base.isempty(::CallbackSet)`, `SciMLBase.isfunctionwrapper(::FunctionWrapper)`; OrdinaryDiffEqCore's `SciMLBase.interp_summary(::Type, ::Bool)`.
- *The idiomatic form:* the interface package and its implementation package act as one owner for the wrap, as `delegate!` already makes them for strict mode.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates) (`OwnershipError`), [§10.3](../reference/traits.md#103-strict-mode) (`delegate!`); [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user).
- *Blocks:* wrapping DiffEqBase and OrdinaryDiffEqCore. It does not block P3, whose first candidate is NetworkDynamics.

**b. Protection follows the trait module, not the user's problem.**
- *The code:* with NetworkDynamics wrapped, `solve(prob, Rodas5P())` from the user's plain code compiles the integrator plainly, although every value in it is ND's, SciMLBase's or Base's.
- *The idiomatic form:* "my network's solve is protected" once NetworkDynamics is.
- *The reference:* [facts §6.2](../reference/facts.md#the-mode-rule), [§12.1](../reference/facts.md#product-setting).
- *Blocks:* no. W, or a wrapped OrdinaryDiffEqCore, protects the driver (§8).

**c. A package needs TraitWorld to get G2 before it has a trait.**
- *The code:* the wrap adds TraitWorld to NetworkDynamics' dependencies only to set the module option and run the checks.
- *The idiomatic form:* the module option alone. The guideline calls it a diagnostic, not a porting step ([porting guideline 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module)).
- *The reference:* [traits §2](../reference/traits.md#2-trait-modules), [compiler §2.1](../reference/compiler.md#21-the-module-option).
- *Blocks:* no.

**d. A plotting load brings stakeholders' extensions into the solver's facts** (only if order B shows it).
- *The code:* `SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt` and `RecursiveArrayToolsStructArraysExt`, activated by loading CairoMakie.
- *The idiomatic form:* extensions that declare implementations, which win at no fact.
- *The reference:* [facts §2.2](../reference/facts.md#g2), the exceptions; [traits §10.1](../reference/traits.md#101-who-may-implement).
- *Blocks:* no. It is G2's stated exception, and P4 converts the extensions.

**e. A trait module at the top compiles the stack a second time** (only if W's first pass shows it).
- *The code:* W's workload reaches code that package images hold only as plain code. It compiles all of it again, by facts, in the session.
- *The idiomatic form:* the images already hold what a trait module at the top needs.
- *The reference:* [facts §11](../reference/facts.md#package-images), [lowering §15.2](../reference/lowering.md#152-workloads).
- *Blocks:* no. It is a cost for the guideline to state.

**Not pushback:** the gaps of the wrap's ownership check (§5, risk 8). They are an implementation gap, reported for a deviation row.
