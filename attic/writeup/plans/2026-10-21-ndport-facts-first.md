# The NetworkDynamics port, P3: the facts mode first

Status: **done (2026-10-21, E-153); part P3 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md).** Revised 2026-10-21 after the review [`../reviews/2026-10-21-ndport-facts-first-plan.md`](../reviews/2026-10-21-ndport-facts-first-plan.md) and the first wrap. Not normative: the references hold ([`../reference/facts.md`](../reference/facts.md) above all).

**The question** (the user's goal, [W-32](../record/todo.md): "reap the biggest possible benefits of Trait and Facts mode with minimal changes to the code"): what do NetworkDynamics, SciML, GraphMakie with Makie, and Observables gain from the facts mode before any trait is written, and what is the smallest change that gets it?

**What P3 does not do.**
- It writes no trait. Traits belong to P2 and P4.
- It changes no reference. Pushback goes to the pushback log (§9).
- It runs quick checks, not benchmarks. Measurement rounds belong to P5.

Paths are relative to the repository root. `ndport/` is the workspace. The settings U, P0, A0 and S, the workload (tier S), the harness and the digests come from [the P1 plan](2026-10-21-ndport-workload.md). Line references are to the clones in `ndport/pkgs/`.

## 0. Summary

- **Under the test bed `all` (A0), with no change,** the whole stack is code compiled by facts.
  - G1 and G2 are promised for all of it, with the exceptions in [facts §2.2](../reference/facts.md#g2) and the shared cache of [F-2](../reference/facts.md#deviations). G2 across loads under `all` is not checked yet (F-11, E-29). P3's order-B run in A0 checks it.
  - E-151 measured what `all` costs ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), the NetworkDynamics row): loads twice as long, the first pass 5 s shorter, the steady state close to U, and every digest equal bit for bit.
- **In the product setting, an unchanged package gains nothing.** Only trait code, and what it reaches, is compiled by facts ([facts §12.1](../reference/facts.md#product-setting)).
- **N, NetworkDynamics wrapped in `@trait_module`, works** (§1.4, the first results):
  - the wrap is three lines and one dependency;
  - it precompiles, and nothing is refused;
  - its digests are bit-equal to U's;
  - its steady state is faster than U's.
- **N's prerequisite is a one-method fix in Static.jl.** Without it, N's steady state is about 1,500 times slower than U's. This is P3's first lesson (§1.5).
- **W** makes the workload's own module a trait module as well, on top of N (§1.3). It needs the same Static fix.
- **DiffEqBase and OrdinaryDiffEqCore** cannot be wrapped as they are. Each has pirates by the letter (§1.6).
- **The benefits still to show** (§2):
  - **load-order protection:** the user simulates first and plots later. The headline number is the recompile time after the plotting load, by module.
  - **strict mode refusing a pirate `+` on ForwardDiff's duals,** with P0 under strict mode as the control.
- **The remaining runs:** about 9 sessions (§4). The first is P0's order-B session, which acts as the gate.

---

## 1. What the facts mode promises this stack

### 1.1 The guarantees, read for this stack

- **G1, identical or error** ([facts §2.1](../reference/facts.md#g1)):
  - code compiled by facts computes what plain code computes, in the same world, or raises;
  - P3 has neither of the things that can raise (a `Dynamic` operation, a `Callable`).
  - So every setting's digests must equal U's.
  - The tolerance fields of [P1 §4](2026-10-21-ndport-workload.md#4-equality-of-results) are the port's pass/fail rule. An exact difference is recorded with its first differing field, and it becomes an open issue.
- **G2, stable caches** ([facts §2.2](../reference/facts.md#g2)): only a stakeholder's change, or a pirate that wins at one of its facts, invalidates code compiled by facts. The other routes facts §2.2 names also apply here:
  - an invalidated CodeInstance of the other mode that the code names: a folded `return_type` answer ([facts §7.1](../reference/facts.md#return-type)), or the compiler's plain code ([facts §6.4](../reference/facts.md#the-compilers-own-code));
  - a binding redefined.
- **The stated exceptions this stack can meet:**
  - **stakeholders' extensions activated by an unrelated load:** four of them come with the plotting load (§2.1);
  - **the standard libraries count as Julia's** ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user));
  - **plain inference's answers behind a run-time `return_type`.**
- **Not promised** ([facts §13](../reference/facts.md#not-promised)):
  - the speed of code that is not fully typed;
  - protection for plain code in the product setting;
  - threads.

### 1.2 Under `all` (A0): no change

- **Every method but the compiler's is compiled by facts** ([facts §12.2](../reference/facts.md#the-test-bed)).
- **Caveats:**
  - **F-2:** the stack's code compiled by facts shares a cache owner with the compiler's plain results. Lost CodeInstances are therefore counted per package, as in `experiments/factscompiler/control/lost.jl`.
  - **F-7:** a package image does not record the setting. So `all` has its own depot, `ndport/depot-facts/`.
- **What E-151 measured** ([evidence §3](../design/evidence.md#3-first-calls-and-sessions); one run under `all`, indicative):

  | | U | `all` |
  |---|---|---|
  | loads | 5.4–5.6 s | 11.9 s |
  | first pass | 39.7–40.4 s | 34.5 s |
  | steady state, a solve (step d) | 19.6–19.8 ms | 15.3 ms |
  | steady state, the GraphMakie PNG (step f) | 35–38 ms | 83 ms |
  | new equations | 15.9–16.3 s | 15.1 s |

  - Makie compiles almost nothing in the "changed" pass. The plotting steps' 0.6 s there comes from NetworkDynamics and SymbolicIndexingInterface reading the state.
- **Why A0 did not meet Static's problem** (§1.5): facts inference under the default owner, as under `all`, folds `typejoin`. The facts owner does not. Facts §8 does not distinguish the owners. The coordinator records this as facts F-16.

### 1.3 In the product setting: trait code only

An unchanged package is plain code ([porting guideline 0.1](../intro/porting.md#01-what-the-facts-mode-gives-an-unchanged-package)). Trait code, and every neutral method it reaches by inference or by a call the code generator emits, is compiled by facts ([facts §5](../reference/facts.md#run-time-sites), [§6.2](../reference/facts.md#the-mode-rule)).

| Code on the workload's path | U, P0 | A0 | N (ND wrapped) | W (N plus the workload's module) |
|---|---|---|---|---|
| the workload's functions (`swing!`, `line!`, the steps) | plain | facts | facts where ND calls them (the core loop calls `swing!`); plain elsewhere | facts |
| NetworkDynamics: construction, the core loop, symbolic indexing, its callbacks | plain | facts | facts, whoever calls | facts |
| what ND's methods call: NonlinearSolve in `find_fixpoint`, SciMLBase's constructors in `ODEProblem(nw, …)`, ForwardDiff, Graphs, Static | plain | facts | facts on those paths | facts |
| the solver: `solve`, OrdinaryDiffEqCore's integrator, the steps, DiffEqCallbacks | plain | facts | plain (`solve` is called from plain code); the core loop it calls is facts | facts |
| solution access: SciMLBase, SymbolicIndexingInterface, RecursiveArrayTools | plain | facts | plain, except ND's methods | facts |
| Makie, GraphMakie, CairoMakie, Observables | plain | facts | plain | facts, except code entered through `jl_apply` (tasks, finalizers, `@cfunction`) |
| what package images hold for these paths | plain | facts | ND's image: only its 20-line workload's path (`src/precompile_workload.jl`) under the facts owner; the rest is compiled in the session | the same as N; everything else is compiled in the session |
| G2 covers | nothing | all of it (F-2) | ND's code and what it reaches | what the workload reaches, except through `jl_apply` |

**First-pass expectations.**
- **N:** above P0's in steps b–e. The code ND reaches is compiled by facts in the session, while P0 takes it from plain images. Measured: the first fixed point took 21.9 s against U's 6.5 s (§1.4).
- **W:** well above N's. It compiles the solver's driver and Makie's figure pipeline by facts in the session. Makie alone took 134 s to precompile under `all`.
  - A packaged application with a workload would put that code into an image. That is a change to the user's code, not to the stack.
  - P3 states the guideline's rule from this table: an application that is a trait module needs a package with a workload. W's one run gives the number.

**W's environment.** W must not run in `env_port`. Its trait code reaches Static, and unfixed Static makes every step slow there (§1.5). It also must not change `env_port`, which P0 and A0 keep at `upstream`. So W runs in `env_p3`, on top of N, with Static fixed.

### 1.4 Setting N: the wrap, and its first results

**Where it lives** (decided after the review's finding 1):
- **a git worktree** `ndport/pkgs/NetworkDynamics-p3wrap`, on the branch `p3-wrap`;
- **its own environment** `ndport/env_p3`: `env_port`'s project, with NetworkDynamics and Static (`ndport/pkgs/Static.jl`, branch `trait-port`) tracked by path;
- **its own depot** `ndport/depot-p3/`, ahead of `~/.julia`;
- **setting N** in `scripts/run_workload.sh`.
- `env_port`, the clones' main trees and `~/.julia` stay at `upstream`, so P0 and A0 are unchanged.

**The wrap** (`git -C pkgs/NetworkDynamics-p3wrap diff upstream`):
- `using TraitWorld: TraitWorld, @trait_module` and `@trait_module begin` after `module NetworkDynamics`, and `end` before the module's `end`;
- TraitWorld in `[deps]`.
- What `@trait_module` then does:
  - it sets the module option on NetworkDynamics' root module;
  - it wraps each top-level statement, `include`d files too, to run after the ones before it;
  - it rewrites structs only where a trait's name appears, so here it changes none;
  - it follows each definition that `_is_fdef` recognizes with an ownership check and `_check_entries_intact`;
  - at the end, it runs `_refuse_overrides` and `check_definitions`, which fail a build on a problem.
- Everything else passes through unchanged: macros (`@compile_workload`, `@generated`, `@kernel`), `@eval` loops and functors.
- The ownership check's gap is recorded by the coordinator as a traits T- row (review, finding 7).
- PrecompileTools' `@compile_workload` stays as it is until the module has bounded functions. Then it becomes `TraitWorld.@workload` ([lowering §15.2](../reference/lowering.md#152-workloads)).
- No traits are named yet, so the refusal of a trait's name on arguments outside trait modules ([traits §2](../reference/traits.md#2-trait-modules)) changes nothing. Once P4 declares traits, NetworkDynamics' extensions that name them must be trait modules too, or take `Kept{X}`.

**The first results** (julia-1.13 6d480d0753, TraitWorld e9f4bfe, one session each, strict mode off, P1's load order, load average 0.8–1.3; `ndport/logs/p3-dev/`, `ndport/logs/p3/`):

| | U (E-151) | N, Static unchanged | N, Static fixed |
|---|---|---|---|
| precompiling NetworkDynamics | 22.0–22.3 s | 18.2 s; nothing refused | — |
| `using NetworkDynamics` | — | 2.8 s | — |
| a solve, steady state | 19.7 ms | 30.2 s | 15.3 ms |
| the first fixed point (step c, first pass) | 6.5 s | 24.7 s | 21.9 s |
| new equations ("changed") | 15.9–16.3 s | — | 15.9 s |
| the session | 69.9–70.7 s | 222.0 s | 86.9 s |
| digests | — | — | equal to U's, bit for bit |

- **What "N holds" means for the P4 draft:** N precompiles, every digest equals U's, and its first pass is recorded against P0's. With the Static fix, all three hold.
- **What N costs:** about 17 s more per fresh session. That is the code ND reaches, compiled by facts in the session, mostly NonlinearSolve's on the fixed point's path.
- **What N does not change:** the cost of new equations, about 16 s. That is P4's target, the batch barrier.
- **To do:** commit the wrap on `p3-wrap` and the Static fix on Static's `trait-port`. Until then, the log headers name both trees at their `upstream` commits.

### 1.5 P3's first result: Static's promotion, a run-time site on every step

- **The symptom:** in N with Static unchanged, one call of the right-hand side takes 3 ms and allocates 140 kB. The dispatch profiler (`ndport/logs/p3-dev/hot-N.log`) shows the cause: about 1.7 million dynamic calls of `getproperty`, plus `supertype`, `convert` and `Static.known`, in code of the facts owner.
- **The cause** (`ndport/scripts/p3_sites.jl`, `p3_promote*.jl`):
  - NetworkDynamics computes `x * StaticInt(N)`.
  - Static's `promote_rule` (Static 1.4.6, `src/Static.jl:602`–`607`) gives `Union{}` in both orders for `Int` and `StaticInt`.
  - So `promote_type` falls back to `typejoin`. Base asserts `typejoin` `:foldable`, but `typejoin` has run-time sites: it handles types as values.
  - Facts §8 drops an asserted effect over a run-time site. Nothing folds, and the product is a run-time site.
  - This is the facts mode as designed, for the facts owner.
- **The fix** is one method in Static, which owns `StaticInt`:

  ```julia
  Base.promote_rule(::Type{<:StaticInt}, T2::Type{<:Signed}) = promote_type(T2, Int)
  ```
  - Static's core tests pass. Its allocation tests need AllocCheck, which is not in the environment.
- **The lesson,** for the porting guideline's B5 (added by the coordinator):
  - Before wrapping, run the workload's steady state once with the dispatch profiler.
  - A plain package's incomplete `promote_rule` turns arithmetic into run-time sites wherever trait code reaches it.
  - The principled fix belongs in the package that owns the type. It is a fix plain Julia's inference also benefits from.
  - It is a slowdown the design tolerates ([facts §13](../reference/facts.md#not-promised)), recovered here by a fix in plain code, not by traits.
- **Pushback** (§9 f): Base's own fallback depends on an assertion that the facts mode must drop.

### 1.6 Why NetworkDynamics first, and what blocks the others

| | NetworkDynamics | DiffEqBase | OrdinaryDiffEqCore |
|---|---|---|---|
| Pirates by the letter | none: the wrap refused nothing (§1.4) | several, among them `Base.isempty(::CallbackSet)` (`callbacks.jl:81`), `SciMLBase.isfunctionwrapper(::FunctionWrapper)` (`DiffEqBase.jl:116`), and `solve`, `init`, `__solve` and `__init` on SciMLBase's `AbstractDEProblem`. The census lists them all | at least `SciMLBase.interp_summary(::Type{cacheType}, ::Bool) where {cacheType}` (`interp_func.jl:73`) |
| Compiler options | none | `@max_methods 1` | `@max_methods 1` |
| What a wrap rebuilds | NetworkDynamics alone | most of the solver stack | Tsit5, Rosenbrock, NetworkDynamics |
| What a wrap protects | the core loop, construction, symbolic indexing, the fixed point's path | `solve`'s front end, `promote_f` | the integrator's driver |

- `TraitWorld.delegate!` serves strict mode only. The wrap's ownership check (`owned_method`, `TraitWorld/src/ownership.jl:213`) does not read it ([open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).
- The integrator's driver stays plain in N. If P0 loses it to the plotting load, only W or a wrapped OrdinaryDiffEqCore protects it (§8).

---

## 2. The benefits still to show

### 2.1 Load-order protection: simulate first, plot later

**Order B**, one session per setting:
1. the loads `TraitWorld` (where the setting needs it), `Graphs, NetworkDynamics`, and the solvers;
2. steps a–e, first and again;
3. a snapshot of the valid CodeInstances;
4. the load `CairoMakie, GraphMakie, Observables`, with Julia's invalidation log on;
5. the losses counted;
6. steps a–e again ("after"), timed;
7. steps f and g for the first time.

**What the plotting load brings** (`env_port/Manifest.toml`):
- 167 packages beyond the 186 of the simulation's group, among them Unitful, IntervalArithmetic, Distributions, StatsBase, OffsetArrays and StructArrays;
- extensions of the stack's own packages: `SciMLBaseMakieExt`, `SciMLBaseDistributionsExt`, `DiffEqBaseUnitfulExt` and `RecursiveArrayToolsStructArraysExt`, plus extensions of Accessors, ConstructionBase, FillArrays, SparseMatrixColorings and StaticArrayInterface;
- IntervalArithmetic's and Unitful's ForwardDiff extensions, which add methods for their own types.

**What is measured** (review, finding 5):
- **The headline:** "after"'s compile and recompile time against "again", by module. This is what the user pays.
- **Lost CodeInstances on the same code in every setting:** those of NetworkDynamics' methods and of the workload's functions. They are plain in P0 and of the facts owner in N and W. Full counts by owner and root module are given beside them, with Base and the standard libraries apart.
- **The route of each lost CodeInstance of the facts owner,** found by mapping the invalidation log's MethodInstances to CodeInstances (as `_strict_after!` in `TraitWorld/src/strict.jl` does):
  - (a) a fact broken directly. Its definer either owns the method (a stakeholder's change; extensions are marked with their parent) or not (a pirate);
  - (b) through a CodeInstance of another owner: a `return_type` answer, or the compiler's plain code;
  - (c) a binding.
  - A loss outside (a)–(c) is unexplained. That is a G2 failure: an open issue and a work item, and P4 waits. The outcome maps each class to facts §2.2's list.
- The digests of "after" equal the first pass's.

**The gate.** P0 runs first.
- If P0 loses almost none of the stack's code (under 100 CodeInstances, and under 0.5 s of recompilation in "after"), the plotting load is no stimulus for this stack. Then A0, N and W can only confirm G2, not show a benefit, and E-153's outcome says so.
- After a weak gate, W's order-B run is still made, for its first pass (§1.3). The A0 run is still made, for E-29.

**W's plotting part.**
- After the plotting load, the script runs `Core.eval(NDW, :(using CairoMakie, GraphMakie, Observables))` and then `Base.include(NDW, "workload_plot.jl")`.
- The definitions get the module option, so they are compiled by facts. They do not get the wrap's checks. The plotting file defines no method of another package's function.

### 2.2 Strict mode: a pirate that wins in the stack's code

**The case** (from `experiments/examples/strict/dual_pirate.jl`):
- steps a–d, so that Rodas5P computes its Jacobian through the network with ForwardDiff's duals;
- then `Main.Pirate`, which owns neither `+` nor `Dual`, defines `Base.:+(a::Dual{T,Float64,N}, b::Dual{T,Float64,N}) where {T,N}`. It counts its calls and returns ForwardDiff's value.
- then Rodas5P again, with a fresh parameter vector.

**The control** (review, finding 2):
- Strict mode also protects plain code of Base's methods ([facts §10.2](../reference/facts.md#strict-mode), the note), and Rodas5P runs Base's code on duals.
- So a refusal can come from Base's code alone. **P0 with strict mode on** shows whether it does.
- Every refusal prints the caller `e.caller`: its owner, its method and module, and `TraitWorld._trait_root(e.caller)`.

| Run | Expected | The claim it tests |
|---|---|---|
| N, strict off | accepted; the stack calls the pirate; code of the facts owner is lost (G2's stated exception); digest of d equal | a winning pirate is followed |
| N, strict on | `PirateError`; the pirate never runs; digest of d equal | holds only if a refusal names a CodeInstance of the facts owner whose method is NetworkDynamics' or the workload's (`swing!`, `line!`) |
| P0, strict on | refused if the pirate wins in a Base method's code at duals; accepted otherwise | the control |

- If P0 refuses as well, then strict mode's refusal in this stack is decided by Base's code. The outcome says so. N's protection of trait code is then shown by the strict-off run instead: which CodeInstances of the facts owner are lost.
- **The switch:** `NDW_STRICT=1` sets `JULIA_TW_STRICT=1`, and the log header says `strict=on`. Strict mode is then on from the start, so the stack's image loads are checked too. Refusals at load are reported apart from the pirate's.
- The case "a pirate defined before the stack loads" is F-6 (Planned). P3 does not run it.

### 2.3 Steady state and first calls

- **E-151 answers this for `all`** (§1.2).
- **N's answer** is in §1.4: the steady state is faster than U's, and the first fixed point is slower.
- **W's answer** comes from its order-B run.
- The dispatch profiler on N's "again" pass (optional) checks that no run-time site remains on the per-step path after the Static fix.

---

## 3. The scripts

All scripts are in `ndport/scripts/`. They run through `run_workload.sh`, which provides the lock, `nice`, the timeout, the check that everything is precompiled, the depot, and the header with the builds, the setting, strict mode and the load average. `run_workload.sh` takes the script as an argument (review, finding 8).

| Script | Status | What it prints |
|---|---|---|
| `p3_hot.jl`, `p3_sites.jl`, `p3_promote*.jl` | done | the dispatch profile of N's steady state; the run-time sites and Static's promotion |
| `p3_census.jl` (P0) | to write | `P <pkg> methods=<n> pirates=<k> generated_defs=<g>`; one `PIRATE <pkg> <signature> <file:line> function_owner=<o> type_owners=<…>` per pirate, for the stack's packages (NetworkDynamics, SciMLBase, DiffEqBase, OrdinaryDiffEqCore, Tsit5, Rosenbrock, DiffEqCallbacks, SymbolicIndexingInterface, RecursiveArrayTools, NonlinearSolve, Graphs, NetworkLayout, GraphMakie, Makie, Observables, Static), by `TraitWorld.owned_method` |
| `p3_loads.jl` | to write | `G <load> <s> lost_same=<n>/<m> lost nothing=<n>/<m> facts=<n>/<m> by=<module=n …>`; `R <route a/b/c> <defining method> <module> owned=<bool> ext_of=<parent or -> n=<lost>`; `T after <step> …` with compile and recompile by module; `D after …`; `S <setting> recompile_after_ms=<n> lost_same=<n> unexplained=<n>` |
| `p3_pirate.jl` | to write | `R <setting> strict=<on/off> defined=<accepted/PirateError> calls_stack=<n> calls_plain=<n> lost_facts=<n> lost_nothing=<n> digest_d_equal=<bool>`; per refusal, `CALLER owner=<o> method=<m> module=<mod> root=<trait root>`; the error's text, first 600 characters |
| the split of `workload_steps.jl` | to do | P1's `workload_steps.jl` keeps steps a–e and the passes. `workload_plot.jl` holds f and g. `workload.jl` includes the plotting part after the plotting group, so P1's order and digests do not change |

## 4. The runs

One Julia job at a time, through the shared lock, niced. No run precompiles.

| # | Run | Setting | Sessions | Status |
|---|---|---|---|---|
| — | the wrap built; N in P1's order, Static unchanged and fixed | N | 2 + 1 build | done |
| 0 | the split checked: one U run whose digests equal E-151's | U | 1 | to do |
| 1 | the census | P0 | 1 | to do |
| 2 | order B: **P0 first (the gate)**, then N, A0 (E-29's result) and W | P0, N, A0, W | 4 | to do |
| 3 | the pirate: N strict off, N strict on, P0 strict on | N, P0 | 3 | to do |
| 4 | N in P1's order, a second run, if the P4 draft needs n = 2 | N | 0–1 | to decide |
| — | optional: the dispatch profiler on N's "again"; the attribution run in N | N | ≤ 2 | optional |

- About 9 sessions remain, of 1–4 minutes each.
- W's session may take longer (§1.3). It runs once, and its time is recorded.

---

## 5. Risks

1. **Generated functions:** definitions in `src/`: NetworkDynamics 3, SciMLBase 9, DiffEqBase 2, OrdinaryDiffEqCore 12, RecursiveArrayTools 4, SymbolicIndexingInterface 1, Makie 3.
   - A generator runs in its definition's world (E-141).
   - `p3_loads.jl` marks lost CodeInstances whose method is generated.
2. **RuntimeGeneratedFunctions, Polyester, KernelAbstractions:** tier S reaches none of them.
   - It runs `SequentialExecution` and `SequentialAggregator` (`construction.jl:45`–`46`) on one thread, with no MTK and no initialization formulas.
   - In tier L, their tasks and `@cfunction` pointers enter through `jl_apply`, which runs plain code in the product setting ([facts §5](../reference/facts.md#run-time-sites)).
3. **`@inbounds`, `@simd`, `@muladd`:**
   - bounds checks are elided in a callee only where it is inlined, so a run-time site costs speed, not results;
   - an exact difference in the digests is recorded and becomes an open issue (§1.1).
4. **`invokelatest`** (Observables' `notify`, Makie): from code compiled by facts it runs facts code ([facts §5](../reference/facts.md#run-time-sites)). In N it stays plain.
5. **Makie's compute graph:** values in `RefValue{Any}` and callbacks typed `::Function` are run-time sites under A0 and W (E-151: step f 83 against 35–38 ms under `all`). This is no bug.
6. **More promotion-like run-time sites.** Static was found on N's hot path. W reaches the solver and Makie by facts, and may meet others. W's steady state against P0's shows them. Each one found goes to the dispatch profiler and becomes a fix in the owning package, as for Static.
7. **Unions under `@max_methods 1`:** open issue 46 (F-15). The dispatch profiler stays optional.
8. **The cap of ten cache files per package** (`julia-1.13/base/loading.jl:3372`).
   - N and W use `depot-p3`, so `~/.julia` and `depot-facts` keep P0's and A0's caches.
   - Static's fix rebuilds Static's dependents in `depot-p3` only.
9. **F-2, F-7:** counts under `all` cover the stack's packages only. Each setting uses its own depot.
10. **Strict mode and the invalidation log** use the same switch. `p3_loads.jl` reads the log only with strict mode off.
11. **TraitWorld is loaded from source** in N and W. No run starts while TraitWorld is being edited ([INDEX](../record/INDEX.md), "Standing constraints").

## 6. The registry row

E-153 is in [`../record/experiments.md`](../record/experiments.md) §11, with status running. Its revised text, to replace the row's Question and Where:

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-153 | W-32 P3: what does the facts mode give the unchanged NetworkDynamics stack (tier S; [the P3 plan](../plans/2026-10-21-ndport-facts-first.md))? (1) Does NetworkDynamics run as a trait module (N: the three-line wrap, in the product setting) with U's results, and at what cost in the steady state and the first pass? (2) When the plotting packages load after the first solve (order B), what recompiles in "after", by module, in P0, N, A0 and W (W: N plus the workload's module as a trait module); is every lost CodeInstance of code compiled by facts explained by a route of facts §2.2? (3) Does strict mode refuse a pirate `+` on ForwardDiff's duals that wins in NetworkDynamics' trait code, with P0 under strict mode as the control? (4) Which definitions would a wrap refuse, per package (the census)? **Would change the plan:** an unexplained loss (a G2 bug: open issue and work item; P4 waits); further run-time sites like Static's on the per-step path (a fix in the owning package before P4); P0 losing almost nothing to the plotting load (then P3 confirms G2 but shows no benefit, and P4 is ordered by the cost of new types); W's first pass acceptable (then the guideline's first step for an application is a trait module); strict mode accepting the pirate in N while a CodeInstance of the facts owner holds the fact (a strict-mode bug). **First results:** the wrap precompiles and refuses nothing; with Static unchanged, the steady state is ~1,500× U's (Static's `promote_rule`; [the plan](../plans/2026-10-21-ndport-facts-first.md) §1.5); with a one-method fix in Static, N's digests equal U's bit for bit and a solve takes 15.3 against 19.7 ms. | running (2026-10-21) | `ndport/` (its own repository, not pushed): `scripts/run_workload.sh` (setting N), `p3_hot.jl`, `p3_sites.jl`, `p3_promote*.jl`, `p3_census.jl`, `p3_loads.jl`, `p3_pirate.jl`; `logs/p3/`, `logs/p3-dev/`; `pkgs/NetworkDynamics-p3wrap` (branch `p3-wrap`), `pkgs/Static.jl` (branch `trait-port`), `env_p3`, `depot-p3` | — | `ndport/README.md`; [the P3 plan](../plans/2026-10-21-ndport-facts-first.md) |

- E-153 gives E-29 (G2 across loads under `all`) a result on this stack. When E-153 is done, E-29's row links it.
- The outcome and the evidence row go in one commit (CLAUDE.md, rule 1).

## 7. Done when

1. The wrap is committed on `p3-wrap`, and the Static fix on Static's `trait-port`.
2. The split of `workload_steps.jl` is checked against E-151's digests.
3. The census is logged. NetworkDynamics shows no pirate, and DiffEqBase's and OrdinaryDiffEqCore's lists exist.
4. Order B has run in P0, N, A0 and W, gate first:
   - the recompile time of "after" is recorded by module;
   - every lost CodeInstance of code compiled by facts is classified by route, or recorded as a G2 failure with an open issue and a work item;
   - every digest holds.
5. The three pirate runs give §2.2's table. Each refusal's caller is printed.
6. `ndport/README.md` has dated tables per setting, with the builds (julia-1.13, TraitWorld, the clones, ND's and Static's branches), strict mode, the load order, the number of runs and the load average. Each number says what it measures: upstream code without traits, compiled plainly or by facts. None of it is idiomatic trait code.
7. E-153's outcome and an evidence row are in one commit, and E-29's row links E-153.
8. The porting guideline's B5 has P3's lessons: the wrap, Static's promotion, and what N costs and protects. The coordinator adds them. The pushback log exists, with §9's entries that were met.
9. The meta plan shows P3 done, with a line in its state table.

## 8. What P3 feeds into P4

- **N is P4's starting point,** with the Static fix as its prerequisite. The P4 draft builds on setting N, and the branch `p3-wrap` becomes the port's first step (E-152). P4 switches ND's `@compile_workload` to `TraitWorld.@workload` with its first bounded function. A larger workload there would also remove most of N's 17 s of session cost.
- **Which code must become trait code** for the product setting to protect the workload: the modules whose code P0 loses to the plotting load, minus what N protects. If the integrator's driver is on that list, the choice is a wrapped OrdinaryDiffEqCore (after moving its pirates) or the application as a trait module (W).
- **The cost of new equations** (16 s, unchanged by N) is P4's main target: rank 1 of P2, the batch barrier.
- **Pirates to move first,** per package, from the census. They depend on [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user).
- **Extensions that win at facts of the solver's code** become extensions that declare implementations (A4).
- **Run-time sites on the per-step path,** like Static's, are fixed in their owning package before a trait is written there (A2).

## 9. Pushback P3 expects

Each entry goes to [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) when P3 meets it. The log is created with the first entry. An entry that needs the user's decision also becomes an open issue.

**a. The pirates of split packages stop a wrap.**
- *The code:* DiffEqBase's methods on SciMLBase's types and functions; OrdinaryDiffEqCore's `interp_summary(::Type, ::Bool)`.
- *The idiomatic form:* the interface package and its implementation act as one owner for the wrap, as `delegate!` makes them for strict mode.
- *The reference:* [traits §10.2](../reference/traits.md#102-pirates), [§10.3](../reference/traits.md#103-strict-mode); [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user).
- *Blocks:* wrapping DiffEqBase and OrdinaryDiffEqCore. It does not block N.

**b. Protection follows the trait module, not the user's problem.**
- *The code:* with NetworkDynamics wrapped, `solve(prob, Rodas5P())` from plain code compiles the integrator plainly.
- *The idiomatic form:* the network's solve is protected once NetworkDynamics is.
- *The reference:* [facts §6.2](../reference/facts.md#the-mode-rule), [§12.1](../reference/facts.md#product-setting).
- *Blocks:* no. W, or a wrapped OrdinaryDiffEqCore, covers it.

**c. A package needs TraitWorld to get G2 before it has a trait.**
- *The code:* the wrap adds TraitWorld to NetworkDynamics' dependencies for the module option and the checks.
- *The idiomatic form:* the module option alone ([porting guideline 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module) calls it a diagnostic).
- *The reference:* [traits §2](../reference/traits.md#2-trait-modules), [compiler §2.1](../reference/compiler.md#21-the-module-option).
- *Blocks:* no.

**d. A plotting load brings stakeholders' extensions into the solver's facts** (only if order B shows it).
- *The code:* `SciMLBaseMakieExt`, `DiffEqBaseUnitfulExt` and the others of §2.1.
- *The idiomatic form:* extensions that declare implementations, which win at no fact.
- *The reference:* [facts §2.2](../reference/facts.md#g2), the exceptions; [traits §10.1](../reference/traits.md#101-who-may-implement).
- *Blocks:* no.

**e. A trait module above the stack compiles it again in the session.**
- *The code:* N's first fixed point takes 21.9 s against 6.5 s. W compiles more still.
- *The idiomatic form:* the images hold what a trait module above the stack needs.
- *The reference:* [facts §11](../reference/facts.md#package-images), [lowering §15.2](../reference/lowering.md#152-workloads).
- *Blocks:* no. It is a cost for the guideline to state and for P4's workloads to remove.

**f. Base's type computations fold only under an assertion the facts mode drops.**
- *The code:* `promote_type`'s fallback `typejoin`, asserted `:foldable` with run-time sites inside. Any package with an incomplete `promote_rule` (Static 1.4.6) makes arithmetic a run-time site in trait code. Under the default owner it folds (facts F-16).
- *The idiomatic form:* type computations on known types fold, whatever owner compiles them.
- *The reference:* [facts §8](../reference/facts.md#asserted-effects); F-16.
- *Blocks:* no. It is fixed in Static. Other packages may need the same fix.
