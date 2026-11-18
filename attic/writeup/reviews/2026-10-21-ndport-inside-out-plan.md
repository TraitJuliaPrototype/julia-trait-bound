# Review: the NetworkDynamics port, P6 (inside out, under strict mode)

**Reviewed:** [`../plans/2026-10-21-ndport-inside-out.md`](../plans/2026-10-21-ndport-inside-out.md) (status: proposal), part P6 of [the meta plan](../plans/2026-10-21-networkdynamics-port.md), work item W-32, as in the working tree on 2026-10-21 (untracked). Read against:
- CLAUDE.md;
- the meta plan as of fe0a9ff (E-152 done; choices 1–16), the user's words in its ground rules, and the decision log §4 ("Joint owners") and §8 ("Orthogonal features for the port");
- E-151 and E-153: [evidence](../design/evidence.md) §1, §3; `ndport/README.md`; [the P3 plan](../plans/2026-10-21-ndport-facts-first.md); the logs `ndport/logs/p3/census-P0.log`, `ndport/logs/p3-orderB/N-1.log`;
- [traits](../reference/traits.md) §10.1–§10.3 and T-56; [facts](../reference/facts.md) §1, §6, §7.1, §8, §10.2, §11 and F-6, F-15, F-16; [porting guideline](../intro/porting.md) 0.1a (as of d0be310);
- TraitWorld a373e30: `src/ownership.jl`, `src/strict.jl`, `src/trait_module.jl`, `test/joint.jl`;
- the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (as of fe0a9ff: P3-1, P4-1, P4-2);
- the clones in `ndport/pkgs/` (at `upstream`), the depot's copies of the packages not cloned (`~/.julia/packages/<Name>/<slug>`, matched to the manifest by version), `ndport/env_upstream`, `ndport/env_p3`, `ndport/scripts/`;
- the P4 plans [`../plans/2026-10-21-ndport-traits.md`](../plans/2026-10-21-ndport-traits.md) and [`../plans/2026-10-21-ndport-graph.md`](../plans/2026-10-21-ndport-graph.md).

**Reviewer:** Opus 5.5, 2026-10-21. Nothing was run in Julia. "Verified" means read in the code, a manifest or a log. Dependency closures were computed with a short Python script over `env_p3/Manifest.toml` (`env_upstream`'s differs only in NetworkDynamics' TraitWorld entry).

**Severity.**
- **Blocker:** a check would not show what the plan says it shows.
- **Should fix:** fix before S0 runs, or before the step it names.
- **Minor:** housekeeping, or a cheap improvement.

## Verdict

- **The approach is sound and the plan is careful.** Bottom-up wrapping with one joint-owner line, a census after loading at every step, and N as the shell is a good test of the user's question. The census arithmetic is right: every group count of §2.2 reproduces from `census-P0.log` (DiffEqBase 14 + 4 + 5 + 3 + 2 = 28; NonlinearSolveBase 12; NonlinearSolve 8 + 2; OrdinaryDiffEqCore 3; Makie 4 + 3 + 1; GraphMakie 2; 63 in all). The rebuild counts of §1.3 reproduce exactly.
- **One blocker** (finding 1): the steady-state check looks at step d only, and the dispatch profiler it calls profiles NetworkDynamics' right-hand side only. Neither sees the code that S1 (access, step e) and S3–S4 (the fixed point, step c) wrap. A regression of P3-1's kind in SciML's code would pass.
- **The joint owners are known now, and they are more than the plan says** (findings 4, 5). BracketingNonlinearSolve and NonlinearSolveFirstOrder, both wrapped by the plan, define front-end pirates; LinearSolve and SteadyStateDiffEq do too. OrdinaryDiffEqDifferentiation is a split of OrdinaryDiffEqCore of its own, so OrdinaryDiffEqCore must declare too, from S6 on. Choice 25 ("no other package declares") cannot hold.
- **Most of the eight moves are not needed, and one changes behaviour** (finding 6). DiffEqBase's five are held by its joint ownership already (traits §10.1 uses `isempty(::CallbackSet)` as its example). Narrowing `interp_summary` breaks printing an SDE solution.
- **The merge is sound in shape** but needs a pinned TraitWorld, a strict-off control for P4's side, and the right steady-state reference (finding 12).

## Answers to the six questions

1. **Order and wrappability.** Bottom-up holds except for one inversion: NonlinearSolveBase depends on SciMLJacobianOperators, which the plan wraps a step later (finding 2). Each step's set is wrappable: its dependencies are wrapped or deliberately plain (LineSearch, SciMLOperators, DifferentiationInterface, LinearSolve, SteadyStateDiffEq sit plain in the middle, which the references allow). The rebuild counts reproduce; the precompile estimates fall too steeply (finding 3).
2. **The classification.** The 63 are classified correctly by the letter of `owned_method`. But class (b) is applied where class (a) already holds (finding 6). LinearSolve is a missing joint owner, and so are BracketingNonlinearSolve, NonlinearSolveFirstOrder and SteadyStateDiffEq (finding 4). OrdinaryDiffEqDifferentiation needs OrdinaryDiffEqCore's declaration (finding 5).
3. **Hazards of Static's kind.** Real ones exist in the wrapped code: Tsit5's per-step tableau relies on folding a `@assume_effects :foldable` constructor; OrdinaryDiffEqCore types callback conditions with `promote_op` over a facts method (finding 7). The per-step checks as written would not catch them early (finding 1).
4. **Cost.** Cheap enough, about 2–2.5 hours with the additions. Missing: a steady state for steps c and e, a profiler over the solver, the packages' own quick tests, a positive control for strict mode (findings 1, 8, 9). Check J is in the wrong steps (finding 10).
5. **The merge.** Sound in shape; see finding 12 for what it needs.
6. **Gaps and conflicts.** Finding 6 (minimal changes), findings 11 and 13 (git refs, IDs and numbering), finding 15 (the experiment row's wording).

## Findings

### 1. Blocker: the steady-state check does not look at the code each step wraps

- **What the plan says** (§3.1, check T; §8, risk 3): the "again" pass, **step d** only, within 10 % + 5 ms of I0; on a failure, the dispatch profiler `p3_hot.jl`. "Check T catches it on the per-step path."
- **What the code does** (verified):
  - `ndport/scripts/p3_hot.jl` builds the network, solves once, then profiles `nw(du, u, p, 0.0)` a hundred times: the right-hand side, NetworkDynamics' code. P6 never changes that code. The profile never runs SciML's integrator, root finding, fixed point or access.
  - Step d is the Tsit5 and Rodas5P solves. S1 wraps SymbolicIndexingInterface and RecursiveArrayTools, whose code is mostly in step e (the access). S3 and S4 wrap the fixed point's path, step c (U's steady state 3.0 ms; README, E-152's table). A run-time-site regression there would pass check T.
  - P3-1's lesson (pushback log) was to run the profiler on the steady state *after wrapping a package*, on that package's code.
- **Fix:**
  - Check T over steps c, d and e of the "again" pass (the harness already prints them; E-152's table), each against I0. Keep f and g recorded.
  - A `scripts/p6_hot.jl`: one "again" pass of steps c–e under `JULIA_FACTS_DISPATCH_PROFILE=1`, with the profile reset before it and printed after it, the sites grouped by the callee's module.
  - Run it **at every step**, in the R session or as one more session. Pass: no new run-time site in the step's newly wrapped modules on the steady state, or each one explained. This is the early warning question 3 asks for; it is a short session, not a benchmark.

### 2. Should fix: SciMLJacobianOperators is below NonlinearSolveBase

- `env_p3/Manifest.toml`: NonlinearSolveBase's `deps` include SciMLJacobianOperators; LineSearch depends on it too. The plan's §1.1 table omits the edge and puts SciMLJacobianOperators in S4, above NonlinearSolveBase (S3).
- So S4's closure (17 + 18) contains NonlinearSolveBase and rebuilds S3's packages, and S3 wraps NonlinearSolveBase over a package that S4 then changes under it.
- **Fix:** move SciMLJacobianOperators into S3 (its closure is the same 17 + 18, so S3 grows to that and S4 shrinks). Add LineSearch, DifferentiationInterface and SciMLLogging to §1.1 as plain packages in the middle, and the edge SteadyStateDiffEq → DiffEqCallbacks.

### 3. Should fix: the precompile estimates fall faster than the closures do

- The per-step closures (verified: S1 21 + 38, S2 19 + 29, S3 15 + 18, S4 17 + 18, S5 8 + 7, S6 7 + 3, S7 2 + 1) all contain, through S5, the same critical path: DiffEqBase → OrdinaryDiffEqCore → OrdinaryDiffEqDifferentiation → OrdinaryDiffEqRosenbrock, NonlinearSolve's workload, and NetworkDynamics.
  - DiffEqBase depends on BracketingNonlinearSolve, and NonlinearSolveBase on SciMLJacobianOperators, so S3 and S4 rebuild the whole ODE chain too.
  - Precompilation is bounded by that chain, not by the number of packages. S2–S4 should cost about what S1 costs, and S5 about half; the plan's 2, 1.5, 1.5, 1 minutes are low.
- **The facts mode adds an unanchored cost.** From S2 on, every dependent's workload that calls SciMLBase compiles SciMLBase's methods, and what they call, under the facts owner, beside the plain code its other callers compile. E-153's "ND cost nothing" (18.2 against 22.0 s) was for the top of the stack, where no dependent's workload exists.
- **Fix:** take S1's measured time as the calibration; estimate S2–S4 as about S1 each; keep risk 6's 10-minute stop. Total builds perhaps 15–25 minutes rather than about 12.

### 4. Should fix: the joint owners are known now, and the line names too few

The P0 census covered 17 packages. Reading the depot's copies of the others (verified):

| Package | Wrapped in P6 | Pirates of the front-end kind | Where |
|---|---|---|---|
| BracketingNonlinearSolve 1.12.8 | S3 | `CommonSolve.solve(prob::IntervalNonlinearProblem; …)`; `CommonSolve.solve(prob::IntervalNonlinearProblem, nothing, args...; …)` (here `nothing` is an argument's *name*, so the argument is `Any`) | `src/BracketingNonlinearSolve.jl:46`, `:50` |
| NonlinearSolveFirstOrder 2.10.0 | S4 | `SciMLBase.__init(prob::NonlinearLeastSquaresProblem, ::Nothing, args...; …)` | `src/solve.jl:558` |
| LinearSolve 5.18.2 | plain | `SciMLBase.init(prob::LinearProblem, args...; …)`; `SciMLBase.init(prob::LinearProblem, alg::Nothing, args...; …)`; `SciMLBase.solve(prob::EigenvalueProblem, args...; …)`; `SciMLBase.solve(prob::EigenvalueProblem, ::Nothing, args...; …)` | `src/common.jl:382`; `src/default.jl:593`; `src/eigenvalue.jl:172`, `:175` |
| SteadyStateDiffEq 2.18.1 | plain | `SciMLBase.solve(prob::SteadyStateProblem, args...; …)` | `src/solve.jl:129` |

- SimpleNonlinearSolve, NonlinearSolveQuasiNewton, NonlinearSolveSpectralMethods, SciMLJacobianOperators and LineSearch showed none in this reading: their methods name an algorithm or cache type of their own.
- The plan's description of LinearSolve is slightly off: it has no `solve(::LinearProblem, ::Nothing, …)`; it has the two `init` methods and the two `EigenvalueProblem` methods.
- **BracketingNonlinearSolve's are plain function definitions,** which the wrap does check (T-56 exempts only other macros, blocks and `Core.eval`). Without its name, S3 fails at P with `OwnershipError`.
- **Fix:**
  - Write the line now: `@joint_owners DiffEqBase NonlinearSolveBase NonlinearSolve BracketingNonlinearSolve NonlinearSolveFirstOrder LinearSolve SteadyStateDiffEq`, plus what S0's census adds.
  - Update the counts that depend on it: §0 ("45 … one line … three"), §1.3's S2–S4 rows, §2.4, choice 25, PB-15.
  - S0's census stays, as the check that the list is complete.

### 5. Should fix: OrdinaryDiffEqCore must declare joint owners too, from S6

- **OrdinaryDiffEqDifferentiation 3.12.4 is a split of OrdinaryDiffEqCore** (verified, depot copy):
  - `import OrdinaryDiffEqCore: get_chunksize, resize_J_W!, alg_autodiff, get_fresh_jacobian` (`src/OrdinaryDiffEqDifferentiation.jl:45`), then methods on OrdinaryDiffEqCore's types, such as `alg_autodiff(alg::OrdinaryDiffEqAdaptiveImplicitAlgorithm) = alg.autodiff` (`src/alg_utils.jl:4–8`): OrdinaryDiffEqCore's function on OrdinaryDiffEqCore's types, a pirate by the letter;
  - `DiffEqBase.prepare_alg(alg::Union{OrdinaryDiffEqAdaptiveImplicitAlgorithm, …}, u0::AbstractArray{T}, p, prob)` (`src/alg_utils.jl:29`): DiffEqBase's function on OrdinaryDiffEqCore's and Base's types;
  - `Base.resize!(p::LinearSolve.LinearCache, i) = p` (`src/linsolve_utils.jl:124`): a true pirate of the plain kind (Base's function, LinearSolve's type).
- So S7's "none expected" is wrong, and choice 25 ("no other package declares joint owners in P6") cannot hold. The reference's own example already names OrdinaryDiffEqCore as a joint owner of SciMLBase (traits §10.1).
- **The timing matters.** Strict mode refuses at the *owner's* trait code, whatever the definer's mode. Once OrdinaryDiffEqCore is a trait module (S6), Differentiation (plain, loaded after it by `using OrdinaryDiffEqRosenbrock`) defines methods that can win at facts in OrdinaryDiffEqCore's image. Whether they do depends on that image's workload. Naming Differentiation only at S7 is too late.
- **Fix:**
  - At S6: `@joint_owners OrdinaryDiffEqDifferentiation` in OrdinaryDiffEqCore (and OrdinaryDiffEqTsit5 or OrdinaryDiffEqRosenbrock only if S0's census shows them; P0's showed 0).
  - `resize!` on `LinearCache` needs a decision before S7. The options:
    - move it into LinearSolve (one line, but `resize!` of a `LinearCache` then answers for every user, and LinearSolve needs a clone);
    - a function of OrdinaryDiffEq's own at its three call sites (`OrdinaryDiffEqNonlinearSolve/src/utils.jl:1367`, `OrdinaryDiffEqPDIRK/src/pdirk_caches.jl:24`, `OrdinaryDiffEqSDC/src/sdc_caches.jl:55`; none loaded by the workload);
    - Differentiation stays plain, and S7 wraps Rosenbrock alone above it.
  - **Generalize the census rule** (§3.1, check C): a plain package's pirate on a function or type of a package P6 will wrap is classified *before the step that wraps that owner*, not "before the step that would wrap its definer". The plan already does this for SciMLBase and LinearSolve; the rule should say it.

### 6. Should fix: five moves change nothing, and one move changes behaviour

- **Joint ownership already holds DiffEqBase's G4 and G5.** `owned_method` asks whether the definer owns the function *or a type*, joint owners counted (`ownership.jl:231–236`). With DiffEqBase named:
  - `isempty(::CallbackSet)` and the two callback `isempty`s name SciMLBase's types;
  - `isfunctionwrapper` and `unwrap_fw` are SciMLBase's functions (`SciMLBase.jl:2076`, `:2126`).
  - Traits §10.1 gives `Base.isempty(::SciMLBase.CallbackSet)` in DiffEqBase as its example of what joint ownership allows.
  - So the five moves resolve no pirate. They edit three trees and add FunctionWrappers to SciMLBase's `[deps]`. That is against the exercise's "minimal changes".
- **G9 (OrdinaryDiffEqCore's 3) is held by naming OrdinaryDiffEqCore,** which finding 5 needs anyway, and the reference's example already does. Then no move is needed at all.
- **If the moves are kept, the narrowing changes behaviour.**
  - OrdinaryDiffEqCore's `solve` builds an `InterpolationData` for SDE solutions too (`solve.jl:819`, the `W` branch; `dense/generic_dense.jl:861`: "SDE/SDDE solutions reuse … InterpolationData"). Their cache is a `StochasticDiffEqCache`, declared in OrdinaryDiffEqCore (`algorithms.jl:169`) and not a subtype of `OrdinaryDiffEqCache`.
  - Narrowed to `cacheType <: OrdinaryDiffEqCache`, `interp_summary(Type{<:StochasticDiffEqCache}, dense)` has no method, and showing an SDE solution throws a `MethodError`. If narrowed, use `Union{OrdinaryDiffEqCache, StochasticDiffEqCache}`.
  - `isadaptive(alg) = false` in SciMLBase answers `false` where a `MethodError` came before, in every session without OrdinaryDiffEqCore. Small, but a change of SciMLBase's contract (`alg_traits.jl:98–110` documents it for `AbstractDEAlgorithm`).
  - `inactive_noinl` into `SciMLBaseEnzymeExt` (trigger Enzyme) is equivalent: only Enzyme reads the rule.
- **The classes are applied unevenly.** `promote_tspan` (G3) "could move" but stays (a); `isempty` (G4) is (b) although (a) already holds it.
- **The guideline pulls the other way.** Porting 0.1a (d0be310) says to check for a one-line move before declaring. Read with the ground rule, that applies where the move *avoids* a declaration. Here it avoids none.
- **Fix:**
  - P6 makes no code edits for pirates: SciMLBase names its joint owners (finding 4), OrdinaryDiffEqCore names its (finding 5).
  - §2 still lists the possible moves as class (b), as the user's question asked ("note whether a different package structure could avoid it"), and they go to `design/alternatives.md` with the joint-owners entry.
  - Choice 26 becomes "no moves; the moves recorded".
  - If the user prefers the moves, fix the narrowing, record `isadaptive`'s change, and count which pirates each move removes that joint owners do not.

### 7. Should fix: name the hazards of Static's kind that are in the wrapped code

Question 3, answered from the source (verified):

- **Tsit5's tableau, every step (S6).** `perform_step!` opens with `@OnDemandTableauExtract Tsit5ConstantCacheActual T T2` (`OrdinaryDiffEqTsit5/src/tsit_perform_step.jl:9`). The macro calls the constructor on every step (`OrdinaryDiffEqCore/src/misc_utils.jl:213–224`). The constructor is `@fold`, which is `Base.@assume_effects :foldable` (`misc_utils.jl:274`; `tsit_tableaus.jl:103`, `:244`, `:289`). Upstream relies on folding it to constants.
  - From S6 this code is reached from OrdinaryDiffEqCore's trait code, so it is compiled by facts. It folds only if its frame has no run-time site (facts §8). F-16 shows the two owners can disagree on folding.
  - If it does not fold, every step recomputes about thirty conversions: slower, with no dynamic dispatch, so the dispatch profiler shows nothing. Check T on step d at S6 shows it; a `code_typed` look at `perform_step!` for the workload's cache type shows it at once.
  - Rosenbrock uses no `@fold` (verified).
- **Callback conditions typed by `promote_op` (S6).** `_condition_return_type` calls `Base.promote_op(condition, …)` on the user's condition (`OrdinaryDiffEqCore/src/solve.jl:186–189`) and wraps the condition in a `FunctionWrappersWrapper` with that return type.
  - NetworkDynamics' conditions are facts methods. Facts §7.1's exception (open issues §2, item 30): for a facts method, the answer at run time can be wider than the folded one. Then the wrapper returns `Any`, boxed, as the code's comment says.
  - Results stay the same; root finding gets slower. That path serves `ContinuousCallback`; `VectorContinuousCallback` uses `Nothing` (`solve.jl:109–129`). Check which kind the workload's line trips use, and watch step d at S6.
- **FunctionWrappers.** DiffEqBase's `promote_f` wraps an in-place right-hand side under `AutoSpecialize` (`DiffEqBase/src/solve.jl:1038–1060`), and OrdinaryDiffEqCore wraps the callbacks (`solve.jl:90–155`). Calls then go through a C function pointer.
  - The wrapper's own call method is FunctionWrappers' plain code. NetworkDynamics' methods behind it stay facts methods.
  - No cost hazard, but order B may lose the wrappers' plain CodeInstances. Say so in B's expected losses.
- **RuntimeGeneratedFunctions** (SymbolicIndexingInterface, 10 uses; SciMLBase, 3): the bodies come from a global cache, not from methods. Low risk; check R covers what the workload touches.
- **Generated functions:** cite the census's counts (methods with generators: SciMLBase 11, OrdinaryDiffEqCore 27, DiffEqBase 3, SymbolicIndexingInterface 2, RecursiveArrayTools 4), not risk 4's.
- **`@max_methods 1`** (`SciMLBase.jl:3–4`, inside an `if`, through `@eval`): changes nothing at a run-time site (porting 0.1a). Risk 2 attributes union splitting to it; F-15 is the facts mode's own split rule. Reword.
- **Off the workload's path:** `DefaultCache`'s `promote_op`s (`OrdinaryDiffEqCore/src/caches/basic_caches.jl:175–180`); ensembles' `Core.Compiler.return_type` (`SciMLBase/src/ensemble/basic_ensemble_solve.jl:517`, `:581`). The packages' tests (finding 8) reach some of them.
- **Fix:** add these to §8 as named risks with the step where each starts, and the check that catches each.

### 8. Should fix: run each wrapped package's own quick tests at two points

- The workload is one path through each package. Wrapping runs every statement of SciMLBase, DiffEqBase and OrdinaryDiffEqCore in a trait module. G1's "or error" can surface off the workload's path: an error from statement-by-statement evaluation (porting 0.1a's open question), or a `return_type` answer that differs (finding 7).
- The plan runs the moved trees' tests once (risk 5) and nothing else. P4 ran NetworkDynamics' test subset (`scripts/nd_tests.jl`, `env_ndtest_p4`).
- **Fix:** offline test subsets in the `env_ndtest_*` pattern, a few minutes each, at two points:
  - after S2: SymbolicIndexingInterface's and RecursiveArrayTools' core tests; SciMLBase's interpolation and solution-interface tests;
  - after S6: DiffEqBase's callback tests; OrdinaryDiffEqTsit5's basic tests;
  - at S7: `nd_tests.jl`, which exercises more of the stack than tier S.

### 9. Should fix: strict mode needs a positive control before S7

- Check S passes if nothing is refused. It also passes if strict mode is not on: if `JULIA_TW_STRICT` does not reach a precompile worker, or the harness does not set it. The only positive control is X, at S7.
- The P3 review's finding 2 was the same gap at P3.
- **Fix:**
  - Each R and P log prints strict mode's state (`TraitWorld.STRICT[]`, `src/strict.jl`).
  - At S2, one session of `p3_pirate.jl` with strict mode on, or a smaller probe that defines a pirate winning in SciMLBase's facts code. The refusal's caller should name SciMLBase. E-153's P0 control stands; it need not be repeated.

### 10. Should fix: check J is at the wrong steps, and too narrow

- **A joint owner's load can discard another wrapped package's code, not only the declaring package's.**
  - NonlinearSolveBase has `initialization_alg(initprob, autodiff) = nothing` (`src/initialization.jl:57`).
  - NonlinearSolve adds `initialization_alg(prob::AbstractNonlinearProblem, autodiff)` (`src/default.jl:71`). It wins at every concrete nonlinear problem.
  - NonlinearSolve is a stakeholder there only through SciMLBase's line (the signature names SciMLBase's type). So SciMLBase's declaration widens G2's exception in NonlinearSolveBase's trait code.
- At S2 nothing of NonlinearSolveBase is wrapped, so J at S2 sees only SciMLBase's own image.
- **Fix:**
  - J reports the discarded facts CodeInstances by module, for every wrapped package.
  - Run J at S4 (both nonlinear packages wrapped) and S7, not S2.
  - PB-16's text says the declaration in one package widens the exception in another's code.

### 11. Should fix: the monorepo's two worktrees cannot share a branch or a tag

- §3.2 puts `ndport/pkgs/OrdinaryDiffEq-p6` (at 53e7d1d) and `ndport/pkgs/OrdinaryDiffEq-p6-ros` (at 14f664a) in one repository, "each on a branch `p6-inside-out`".
  - Git refuses to check out one branch in two worktrees.
  - Tags `p6-s<k>` are per repository, so S7's two commits cannot both be `p6-s7`. The tag `upstream` is already 53e7d1d.
- **Fix:**
  - Branch `p6-inside-out-ros` and tags `upstream-ros` (14f664a) and `p6-s7-ros` for the second worktree; one `VERSIONS.tsv` row each.
  - Say that worktrees and branches add refs to P0's clone repositories, as P3 and P4 did (meta choice 8); the working trees stay untouched.

### 12. Should fix: what the merge needs

- **TraitWorld, pinned.**
  - Every wrapped package depends on TraitWorld, loaded from source. A TraitWorld commit rebuilds every wrapped package and its dependents, and moves I0.
  - "a373e30 or later" (§3.2) lets that happen mid-track. P4's open issue 48 is TraitWorld work.
  - Fix:
    - one TraitWorld commit for S0–S7, in each log header;
    - if it must change, rerun I0 and the last step on the new commit;
    - at the merge, both tracks' last steps on the merge's commit.
- **Strict mode on P4's side.** E-152 ran strict mode off, and E-154 is registered strict off. A merged run with strict mode on is P4's code's first strict run. A refusal there cannot be attributed. Fix: the merged workload strict off, then strict on.
- **The steady-state reference.** After the merge, NetworkDynamics is P4's (step d 46.8 ms with P4-1's crossing, against N's 15.3 ms). Check T compares with P4's last step, not I0.
- **The branches.** "P4's later steps put their trait declarations on P6's trees, on the same `p6-inside-out` branches" mixes the tracks' records. Fix: a new branch per tree from its last `p6-s<k>` tag (for example `port`); `p6-inside-out` stays P6's record, as `env_p6` does.
- **The checks of the merge:** name them (P, R, S, C, F, T, L), name the P4 tags and worktrees used (`Graphs-p4`, `GraphMakie-p4`), and count the build and sessions in §3.4.
- **GraphMakie's two pirates** (G13) are written by Makie's `@recipe` in GraphMakie. Under strict mode on, they matter if `GraphMakie-p4`'s trait submodule holds facts that they change. That is P4's to check at the merge.

### 13. Minor: IDs and numbering already collide

- **Pushback IDs.** The log now numbers by part: P3-1, P4-1, P4-2 (fe0a9ff). The plan's PB-15…PB-21 follow the plans' private series. Fix: P6-1, P6-2, … when written to the log; IDs are permanent (CLAUDE.md rule 4).
- **Choice numbers.** The meta plan's list now ends at 16 (E-152's 15 and 16), so the graph plan's 15–22 and this plan's 23–33 collide. Fix: number on adoption, from the meta plan's last number.
- **Stale line in §5.** "Its 0.1a text on split packages and `delegate!` predates joint owners and is a stale copy to fix then": 0.1a was rewritten for joint owners in d0be310. Drop the line. Reconcile 0.1a's "check for a one-line move first" with finding 6 instead.

### 14. Minor: the cost arithmetic

- §3.3 lists 8 builds plus the optional one, and 24 sessions plus IC's. §0 says 9 builds and 22 sessions; §3.4 says about 8 and 22.
- With findings 1, 8, 9, 10 and 12 the count is about 30 sessions and 10 builds. Lock time is about 2–2.5 hours: still cheap, still between P4's runs.
- **Redundant:** nothing much. L is free. J at S2 moves to S4 (finding 10).

### 15. Minor: the experiment row, the census and order B

- **E-155's wording.**
  - "Measures unchanged upstream code": the declarations, and any moves, change it. Say "upstream's code with the declarations of §2.4".
  - "Strict mode on for every check except order B": J runs strict off too.
- **The census.**
  - S0's extended census should reproduce P0's 63 on the 17 packages, as the control of the new script.
  - Say how an extension's pirates count. `owner` maps an extension to its parent, so they would count against a wrapped parent. P0's census listed root modules only.
- **Order B's owners.** E-153's N log lists a third owner, `:facts_plain_return_type` (15 lost; `logs/p3-orderB/N-1.log:21`). Say how B classifies it: plain inference's answers behind `return_type` (facts §7.1), which change exactly when plain Julia's do.
- **`@joint_owners` inside `@trait_module`** is untested: `test/joint.jl` declares in a plain module. The plan's reading of `ownership.jl` is right (`owner(__module__) === __module__` holds there). A five-line probe in `ndport/scripts/` before S2 settles it without touching TraitWorld.
- **§1.2's LinearSolve row:** "reached only through wrapped callers": SteadyStateDiffEq (plain) calls it too. Harmless; reword.

## What was done with each finding

Not yet acted on.
