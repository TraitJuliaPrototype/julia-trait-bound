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
| P2 | **The principled traits of each ecosystem:** graphs, NetworkDynamics' components and network, SciML's problems, integrators, solutions and symbolic indexing, Makie's plots and GraphMakie, Observables. The question goes to a Fable agent; its answer is an exploration, from which an Opus agent writes the plan | [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) (Fable), then `2026-10-21-ndport-traits.md` (with P4's first step) | the exploration done; the plan being written |
| P3 | **The facts mode first:** what the unchanged packages gain when compiled by facts (as trait modules, and under `all`), before any trait is written; which guarantees hold for the workload | `2026-10-21-ndport-facts-first.md` | being written |
| P4 | **The port, a function at a time,** one plan per ecosystem in the order P2 gives; each step keeps the workload's results equal to upstream's and records what it buys | to be written, one per ecosystem | not started |
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

## State

| Date | Step |
|---|---|
| 2026-10-21 | W-32 and this plan. `ndport/` created; the upstream environment resolved on the patched Julia (julia 1.13.2, 352 packages); the clones checked out at the resolved releases (`ndport/VERSIONS.tsv`). |
| 2026-10-21 | P0 done: the porting guideline rewritten, reviewed, revised; its review's findings outside the guideline recorded (open issues 46, 47; facts F-15; traits T-55). P1: the workload (tier S) and its harness built; the dry run upstream 74 s, of which changing the equations recompiles about 18 s; E-151 registered; the stack precompiling under `all`. P2: the Fable exploration done. |
| 2026-10-21 | P1 done (E-151): about 70 s per session in every setting; the same results bit for bit upstream, in the port's environment, under `all` and on stock 1.13.2; new equations compile 15.6–16.0 s upstream, 6,810 CodeInstances in the fixed point, the solves and the access, almost none in Makie. P3's plan written, in review. |
