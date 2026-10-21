# The NetworkDynamics port: the large-scale test (meta plan)

Status: **adopted** (the user, 2026-10-21; work item [W-32](../record/todo.md)). In progress. This is the meta document: the overall plan, the state, and links to the plans of each part. The parts' plans are written as the work reaches them.

## The goal

- **A large-scale test of the design** on code written without traits: NetworkDynamics.jl, the SciML packages under it, and GraphMakie with Makie and Observables.
- **A workload** that exercises a wide range of each ecosystem:
  - define a system of equations;
  - build a network from them and simulate it;
  - plot the network with GraphMakie;
  - a plot driven by Observables, to look at trajectories quickly while they are simulated;
  - change the equations and run everything again.
  - The simplest version runs in a couple of minutes at most, so that we can iterate.
- **Move pieces into the trait world,** iteratively, a function at a time.
- **Find early the structurally correct, principled traits** each ecosystem needs, and revisit them periodically.
- **Reap the biggest possible benefits of traits and of the facts mode with minimal changes to the code.**

## Ground rules

- **The design is not changed by this exercise.** The references in `../reference/` hold.
  - Where idiomatic trait code pushes back against the design, the port records it in the pushback log (below). It does not change the reference.
  - Where the port really needs a part of a reference whose status is Planned, the port pauses and that part is implemented first. The pause is a work item of its own.
- **The porting guideline is updated as we go.** [`../intro/porting.md`](../intro/porting.md) is brought up to date before the port starts. Every part adds its lessons there.
- **Two tracks** (the user, 2026-10-21): outside in, traits at the seams where the user's types enter (P4); inside out, the core wrapped bottom-up under strict mode, free of pirates at every step (P6).
- **Orthogonal features may be added for the port** (the user, 2026-10-21: "For things like split packages I think you can decide yourself to add features that are highly orthogonal. Don't make changes to existing designs and features though..."): joint owners are the first ([decision log §4](../record/decisions.md)).
- **Agents.** Opus agents write each part's plan, and other Opus agents review it with fresh eyes. A Fable agent is used only for one question: which traits are structurally correct and principled for each ecosystem.
- **The machine's rules hold** ([`../record/INDEX.md`](../record/INDEX.md), "Standing constraints"):
  - one Julia job at a time, niced, through the shared lock;
  - quick tests, not benchmarks, unless a part is performance work.
- **Experiments are registered before they run** ([`../record/experiments.md`](../record/experiments.md)), with logs committed under `ndport/logs/`.

## Where things are

- **`ndport/`** (the workspace root; its own repository, ignored by the design repository): the workload, the environments, the scripts, the logs, and a README with dated tables of its own results.
- **`ndport/pkgs/`**: the clones, each its own git repository. Each is on a branch `trait-port` that starts at the resolved release, tagged `upstream`, so `git diff upstream` is the port. The versions, commits and tree-hash checks are in `ndport/VERSIONS.tsv`, written by `ndport/scripts/clone.sh`.

| Package | Version | Repository (subdirectory) |
|---|---|---|
| NetworkDynamics | 1.3.0 | JuliaDynamics/NetworkDynamics.jl |
| SciMLBase | 3.58.0 | SciML/SciMLBase.jl |
| DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5 | 7.21.4, 4.19.0, 2.1.5 | SciML/OrdinaryDiffEq.jl (`lib/…`), one commit |
| DiffEqCallbacks | 4.19.5 | SciML/DiffEqCallbacks.jl |
| SymbolicIndexingInterface | 0.3.55 | SciML/SymbolicIndexingInterface.jl |
| RecursiveArrayTools | 4.5.5 | SciML/RecursiveArrayTools.jl |
| GraphMakie | 0.6.6 | MakieOrg/GraphMakie.jl |
| Makie | 0.24.16 | MakieOrg/Makie.jl (`Makie`) |
| NetworkLayout | 0.4.11 | JuliaGraphs/NetworkLayout.jl |
| Graphs | 1.15.0 | JuliaGraphs/Graphs.jl |
| Observables | 0.5.5 | JuliaGizmos/Observables.jl |

- OrdinaryDiffEqRosenbrock 2.7.5 comes from the registry: its release is at another commit of the same repository. It is cloned when the port reaches it.
- **Environments:**
  - `ndport/env_upstream`: the registry's packages, unchanged;
  - `ndport/env_port`: the clones through `[sources]`, with TraitWorld.

## The parts

Each part has its own plan, written by an Opus agent and reviewed by another before work on it starts. The plans live in `writeup/plans/`.

| Part | What | Plan | Status |
|---|---|---|---|
| P0 | **The porting guideline brought up to date** with everything learned so far: TraitWorld's language as it stands, the demonstrators' lessons, what to do first in a package written without traits | [`../intro/porting.md`](../intro/porting.md) (no separate plan); its review [`../reviews/2026-10-21-porting-guideline.md`](../reviews/2026-10-21-porting-guideline.md) | done (2026-10-21); updated as the port goes |
| P1 | **Setup, the workload and its baselines:** the clones and environments; the workload script in steps, with a simplest version of a couple of minutes; the baselines (upstream on the patched Julia, the product setting, the test bed `all`); what each step must show | [`2026-10-21-ndport-workload.md`](2026-10-21-ndport-workload.md); its review [`../reviews/2026-10-21-ndport-workload-plan.md`](../reviews/2026-10-21-ndport-workload-plan.md) | done (2026-10-21): E-151 |
| P2 | **The principled traits of each ecosystem:** graphs, NetworkDynamics' components and network, SciML's problems, integrators, solutions and symbolic indexing, Makie's plots and GraphMakie, Observables. The question goes to a Fable agent; its answer is an exploration, from which an Opus agent writes the plan | [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) (Fable), then `2026-10-21-ndport-traits.md` (with P4's first step) | the exploration done; the plan [`2026-10-21-ndport-traits.md`](2026-10-21-ndport-traits.md) adopted after its review ([`../reviews/2026-10-21-ndport-traits-plan.md`](../reviews/2026-10-21-ndport-traits-plan.md)) |
| P3 | **The facts mode first:** what the unchanged packages gain when compiled by facts (as trait modules, and under `all`), before any trait is written; which guarantees hold for the workload | [`2026-10-21-ndport-facts-first.md`](2026-10-21-ndport-facts-first.md); its review [`../reviews/2026-10-21-ndport-facts-first-plan.md`](../reviews/2026-10-21-ndport-facts-first-plan.md) | done (2026-10-21): E-153 |
| P4 | **The port, a function at a time,** one plan per ecosystem in the order P2 gives; each step keeps the workload's results equal to upstream's and records what it buys | the first step in [`2026-10-21-ndport-traits.md`](2026-10-21-ndport-traits.md) §2 (E-152); step 2 [`2026-10-21-ndport-graph.md`](2026-10-21-ndport-graph.md) | step 1 done (E-152): new equations compile 0.45 s instead of 15 s; the steady state 33–41 against 15 ms after open issue 48's fix |
| P6 | **Inside out, under strict mode** (the user, 2026-10-21: "Dual track is also go"): the core packages wrapped as trait modules from the bottom of the dependency graph up, each step free of pirates; split packages by joint owners (built: traits §10.1). Beside P4's traits at the seams | [`2026-10-21-ndport-inside-out.md`](2026-10-21-ndport-inside-out.md), its review [`../reviews/2026-10-21-ndport-inside-out-plan.md`](../reviews/2026-10-21-ndport-inside-out-plan.md) | adopted; E-155 starting |
| P5 | **What is measured, and when:** each step's time in a fresh session, the run after changing the equations, the gains of P3 and P4. Quick checks after each step; a measurement round only at milestones | to be written | not started |

## The pushback log

Where idiomatic trait code pushes back against the design, the entry goes to [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (to be created at the first entry): the code, what the idiomatic form would be, the reference section it meets, and whether it blocks the port. An entry that needs the user's decision also becomes an open issue. A Planned reference part that the port needs becomes a work item, and the port pauses for it.

## Choices for the user to review

The user (2026-10-21): "Make your own choices and document the ones I should review later." Choices about the port are listed here; a choice that touches the design also goes to [`../open-issues.md`](../open-issues.md) §1.

1. **The workload's model** (P1): swing equations on `watts_strogatz(20, 4, 0.2; seed = 42)`, `K = 6`, line limit 1.0, alternating `P_ref = ±1`; the most loaded line trips at `t = 1`, and 16 of 40 lines follow. ModelingToolkit is left to a later tier (its load alone exceeds the budget).
2. **The settings** (P1): the stock baseline S is kept, run once, in its own depot (`ndport/depot-stock/`); the test bed's depot is on disk (`ndport/depot-facts/`), not in `/tmp` (a RAM disk). Reason: Julia keeps at most ten cache files per package, and the shared depot is near that for Makie.
3. **Equality of results** (P1): the port's environment must equal upstream exactly; `all` and stock within tolerances (states `rtol = 1e-5`, `atol = 1e-7`); trips closer than 0.05 in time compared as unordered groups.
4. **E-151 rather than E-150** for the baselines: the implementation plan of 2026-10-20 names E-150 for W-17.
5. **The guideline's answer on facts compilation without traits:** a port uses `@trait_module`; the bare `Base.Experimental.@compiler_options facts=true` is only a diagnostic in experiments (the references: traits §2, facts §6.1, compiler §3).

6. **Static.jl is patched** (P3): one promotion rule (`promote_rule(::Type{<:StaticInt}, ::Type{<:Signed})`), the fix where the rule is ([pushback P3-1](../explorations/ndport-pushback.md)). Static.jl is cloned beside the others for it; Static's own tests state the intent and pass.
7. **The layout of the port** (P4): NetworkDynamics as a whole is the trait module (the three-line wrap of P3), not trait submodules inside a plain package. Reason: the wrap precompiles, is refused nothing, gives upstream's results and a faster steady state.
8. **Separate working trees per setting:** P0 keeps the clones at `upstream`; P3's wrap and P4's port each have a git worktree, an environment and a depot of their own (`pkgs/NetworkDynamics-p3wrap`, `env_p3`, `depot-p3`; `pkgs/NetworkDynamics-p4`, `env_p4`, `depot-p4`). Reason: a shared clone would change P0's code under it.

9. **One trait now** (P4): `ComponentDynamics` at NetworkDynamics' internal calling convention; the user-facing `VertexDynamics`/`EdgeDynamics` later, as a generic implementation of it.
10. **Model-static values as type parameters** of the library's implementation (`FunctionDynamics{…, PDIM, EXTDIM}`), standing in for associated constants (PB-1).
11. **`KAExecution` keeps typed batches** (GPU kernels need isbits data); Polyester is decided at S7 (PB-7).
12. **The barrier:** upstream's own pattern (one `Ref` per pass, the batches as a vector and an index). The remaining allocation per crossing (the trait object, on the generic path for family members) is left to the user as PB-4; ND's allocation assertions are reported as expected failures.
13. **The test subset** runs in environments of its own, with `testutils.jl`'s `test_execution_styles` copied without its CUDA block.
14. **The criteria:** the network's type equal for both equations (a gate); at most 50 new CodeInstances of SciML and SymbolicIndexingInterface in "changed" b–e (the headline); b–e compiling at most 2 s; the steady state within 10 % + 5 ms of the wrapped package, a failure confirmed by one rerun.
15. **The first step's departures from its plan** (E-152, by its agent): a typed `_sum_upto_dim` for `Int` strides (S2); `any(filt, batches) || return nothing` and `dispatchT(batch)` (S6); one `process_batches!` method per execution style instead of one on a `Union` (S6); Polyester kept typed (S7, pushback P4-2).
16. **The port continued while open issue 48 was decided:** step 1 stays as built; the Graph step and the inside-out track go on. Open issue 48 is closed by the user's choice (c), built in TraitWorld 3bebf13; the remaining steady-state gap is the step's crossings per right-hand side, a question for the port's next steps.

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

## State

| Date | Step |
|---|---|
| 2026-10-21 | W-32 and this plan. `ndport/` created; the upstream environment resolved on the patched Julia (julia 1.13.2, 352 packages); the clones checked out at the resolved releases (`ndport/VERSIONS.tsv`). |
| 2026-10-21 | P0 done: the porting guideline rewritten, reviewed, revised; its review's findings outside the guideline recorded (open issues 46, 47; facts F-15; traits T-55). P1: the workload (tier S) and its harness built; the dry run upstream 74 s, of which changing the equations recompiles about 18 s; E-151 registered; the stack precompiling under `all`. P2: the Fable exploration done. |
| 2026-10-21 | P1 done (E-151): about 70 s per session in every setting; the same results bit for bit upstream, in the port's environment, under `all` and on stock 1.13.2; new equations compile 15.6–16.0 s upstream, 6,810 CodeInstances in the fixed point, the solves and the access, almost none in Makie. P3's plan written, in review. |
| 2026-10-21 | P3, first results: NetworkDynamics wrapped whole in `@trait_module` precompiles and gives upstream's results; it needed one fix in Static.jl (pushback P3-1; without it the steady state was 1,500 times slower), and with it the steady state is faster than upstream's. Open issues and deviations from the reviews: facts F-16, traits T-56. |
| 2026-10-21 | P3 done (E-153): the wrap protects the simulation's code from the plotting load (the next pass recompiles 0.04 against 4.7 s) and makes strict mode refuse a pirate in it; its cost is the first simulation (+16 s: facts compilation in the session). The workload itself as a trait module costs the first plot 48 against 16 s. P4 step 1 (E-152) in progress, by an Opus agent in `pkgs/NetworkDynamics-p4`. |
| 2026-10-21 | The user: inside out under strict mode as a second track (P6), joint owners approved. Joint owners built (TraitWorld a373e30, traits §10.1); the P6 plan being written; the Graph step's plan written (`2026-10-21-ndport-graph.md`, review after E-152). |
| 2026-10-21 | P4 step 1 done (E-152): the network's type independent of the equations; new equations compile 0.43–0.49 s against 15 s, nothing in SciML; results bit-equal; the steady state 46.8 against 15.3 ms from the crossing into a family member (open issue 48, pushback P4-1). The P6 plan written, in review. |
| 2026-10-21 | Open issue 48 decided by the user (c) and built (TraitWorld 3bebf13): family members served by the table, held-value conversions at fact signatures; NetworkDynamics' right-hand side 5 allocations against 32, step d 33–41 against 47 ms (N 15.3). Open issue 49 (a typed call of a family member) and traits T-57 found. The P6 plan revised after its review; the Graph plan reviewed (start now, smaller). |
