# The NetworkDynamics port, P1: setup, the workload and its baselines

Status: **adopted; part P1 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md).** Revised 2026-10-21 after the review [`../reviews/2026-10-21-ndport-workload-plan.md`](../reviews/2026-10-21-ndport-workload-plan.md) and the first dry runs. Not normative.

P1 gives the port a fixed workload, the environments to run it in, and the numbers and results every later step is compared against. No trait code is written in P1.

Paths below are relative to the repository root. `ndport/` is its own git repository. It is not pushed. It is E-151's experiment directory (CLAUDE.md puts experiments in `experiments/<dir>/`; the meta plan puts this one in `ndport/`).

## 1. Setup

### 1.1 Done

- **`ndport/pkgs/`:** the clones, each on branch `trait-port` from the release, tagged `upstream` (`ndport/pkgs/VERSIONS.tsv`; every tree hash matches).
  - `pkgs/OrdinaryDiffEq.jl` at 53e7d1d holds DiffEqBase 7.21.4, OrdinaryDiffEqCore 4.19.0 and OrdinaryDiffEqTsit5 2.1.5. At that commit, Tsit5's tree is the release's (371de3eb…).
  - OrdinaryDiffEqRosenbrock's tree at that commit is not its release's, so it stays a registry package.
- **`ndport/env_upstream`:** 352 packages, resolved on the patched Julia 1.13.2. It precompiled in 320 s: 445 packages including extensions (`ndport/logs/setup/precompile-upstream.log`).
- **`ndport/env_port`:**
  - the clones through `[sources]`, plus TraitWorld (`../../TraitWorld`);
  - resolved offline; every version equals `env_upstream`'s;
  - ComputePipeline 0.1.8 is path-tracked too, through Makie's own `[sources]`;
  - precompiled in the product setting in 175 s: 72 packages, the rest already compiled (`ndport/logs/setup/precompile-port.log`).
- **The workload:** `ndport/scripts/workload_steps.jl` (the steps) and `ndport/scripts/workload.jl` (the driver). Dry runs are in `ndport/logs/dev/`.

### 1.2 To do

- **`ndport/scripts/check_env.py`** (Python, no Julia):
  - every package in `env_port`'s manifest has `env_upstream`'s version;
  - the clones, ComputePipeline (its tree checked with `git rev-parse upstream:ComputePipeline`) and TraitWorld are tracked by path;
  - every clone has an empty `git diff upstream` and an empty `git status --porcelain`.
  - `env_port/Manifest.toml` is ignored by git, so the run's copy goes to `ndport/logs/setup/`.
- **Two depots of their own:**
  - `ndport/depot-facts/` for `all`;
  - `ndport/depot-stock/` for stock 1.13.2.
  - Each is used as `JULIA_DEPOT_PATH=<depot>:$HOME/.julia:`, the same for precompilation and runs.
  - Reasons:
    - Julia keeps at most ten cache files per package (`julia-1.13/base/loading.jl:3372`). Makie has ten in `~/.julia` today. A shared depot would let one setting evict another's caches.
    - `/tmp` is RAM.
  - Both depots and an `XDG_CACHE_HOME` directory (for fontconfig) go into `ndport/.gitignore`.
- **E-151 in the registry (§5), with status running, before the `all` and stock precompilations.** The two setup logs above go in its Where column.
- **Precompilation of `env_port` under `all`, then of `env_upstream` on stock,** one at a time, through the lock. Their durations are unknown; each is logged in `ndport/logs/setup/`.

## 2. The workload

### 2.1 The model (tier S)

Taken from NetworkDynamics' cascading-failure example (`ndport/pkgs/NetworkDynamics.jl/docs/examples/cascading_failure.jl`):

- **Vertices:** the swing equation, `VertexModel(f=swing!, g=1, sym=[:δ, :ω], psym=[:P_ref, :I=>1, :γ=>0.1])`.
- **Lines:** static, `EdgeModel(g=AntiSymmetric(line!), outsym=:P, psym=[:K=>6.0, :limit=>1.0])`.
- **Graph:** `watts_strogatz(20, 4, 0.2; seed=42)`, 40 lines. Its digest includes `is_connected(g)`.
- **Power:** `P_ref` alternates `±1` over the 20 vertices, so it balances.
- **The cascade:**
  - At `t = 1`, a `PresetTimeComponentCallback` trips the most loaded line (line 8).
  - Continuous callbacks trip each line whose `|P|` exceeds `limit`.
  - In the dry run, Tsit5 and Rodas5P both trip 16 of 40 lines, in the same order.

### 2.2 The steps

Each step is a function in `workload_steps.jl`. The digest of a step is computed and printed after its timer stops.

| Step | What it does | API (NetworkDynamics 1.3.0, `ndport/pkgs/NetworkDynamics.jl/`) |
|---|---|---|
| a. components | the vertex and edge models | `VertexModel`, `EdgeModel`, `AntiSymmetric` (`src/component_functions.jl:117, 251, 306`) |
| b. network | the graph; `Network(g, vertex, edge; dealias=true)` | `src/construction.jl` |
| c. state | `P_ref` and `γ` as defaults by symbolic index; the fixed point; `NWState`; the linear analysis | `set_default!`, `find_fixpoint` (`src/initialization.jl:52`; NonlinearSolve), `set_defaults!`, `NWState(nw)`; `isfixpoint`, `jacobian_eigenvals` (`src/linear_analysis.jl:8, 237`) |
| d. solve | line trips; Tsit5, then Rodas5P (a ForwardDiff Jacobian through the network) | `ComponentCondition`, `ComponentAffect`, `ContinuousComponentCallback`, `PresetTimeComponentCallback`, `set_callback!`, `add_callback!` (`src/callbacks.jl`); `ODEProblem(nw, s, (0, 6))` (`src/post_utils.jl:127`) |
| e. access | the solution through symbolic indices | `sol(ts; idxs=vidxs(nw, :, :ω))`, `sol(ts; idxs=EIndex(i, :P))`, `NWState(sol, t)` (`src/symbolicindexing.jl:266`); `SII.getu`, `SII.getp` with `eidxs`, `epidxs` (`docs/examples/cascading_failure.jl`) |
| f. graph plot | `graphplot`, `layout=Spring(seed=1)`; node colours from `ω` at the end and edge colours from `\|P\|`, with a fixed `colorrange`; PNG by CairoMakie | `ndport/pkgs/GraphMakie.jl/src/recipes.jl`; `ndport/pkgs/NetworkLayout.jl/src/spring.jl:37` |
| g. live figure | below | Observables `Observable`, `lift`, `on`; SciMLBase `init`, `step!`; `NWState(integ)` (`src/symbolicindexing.jl:257`) |
| h. change | h0 and h1, below | the same |

**Step g, the live figure:**
- One `Figure` holds two parts:
  - the graph plot, with its node colours an `Observable` and a fixed `colorrange`;
  - an `Axis` with `ω(t)` of a selected vertex, derived by `lift` from a buffer of all vertices' `ω` and a selection `Observable`.
- The integrator is `init(prob′, Tsit5())`. It steps to absolute frame times `tₖ = 0.6k`, for k = 1…10.
- At each frame, both observables are updated from a copy of `NWState(integ)`'s values.
- At the end, the selection switches to other vertices. Their history is already in the buffer.
- A few PNGs are saved, named by frame.

**Every solve and the integrator use a fresh parameter vector,** `remake(prob; p = copy(prob.p))`. The affect writes `K = 0` into the parameters, and OrdinaryDiffEqCore aliases `prob.p` by default (`ndport/pkgs/OrdinaryDiffEq.jl/lib/OrdinaryDiffEqCore/src/solve.jl:475–479`).

**Step h, the change:**
- **h0, parameters only:** a new `γ = 0.2` through the defaults and `remake`. Steps c–g run again. No new types.
- **h1, new equations:** `swing2!` adds a cubic damping `-κ ω³` with a new parameter `κ = 0.5`. Steps a–g run again, from the original `γ`.
  - This changes two things: the function's type `F`, and the parameter count `PDIM`.
  - Both are type parameters of `ComponentBatch` (`src/network_structure.jl:181`), so there is a new `Network{…}` type (`:88`).
  - A change of the function alone, keeping the parameters, is a tier-M item.

ModelingToolkit is not in tier S: `NetworkDynamicsMTKExt` needs ModelingToolkitBase, SymbolicUtils, Symbolics and Moshi, which are not in the environment.

### 2.3 The passes, in one fresh session

1. **Loads,** in a fixed order, timed per group:
   - (TraitWorld, in `env_port` only);
   - `Graphs, NetworkDynamics`;
   - `OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock, DiffEqCallbacks, SymbolicIndexingInterface`;
   - `CairoMakie, GraphMakie, Observables`.
2. **first:** a–g with `swing!`. Time to first X.
3. **again:** a–g with `swing!`. The steady state. Its digests must equal the first pass's.
4. **params:** h0.
5. **changed:** h1.

Other load orders belong to P3.

### 2.4 Tier S's cost (dry run)

From `ndport/logs/dev/dry2.log`: `env_upstream`, patched build, product setting, one run, before the review's changes to the script.

| Part | ms |
|---|---|
| loads | Graphs + NetworkDynamics 2,660; solvers 130; CairoMakie + GraphMakie + Observables 2,780 |
| first | a 960, b 1,690, c 8,530, d 12,930, e 3,310, f 15,910, g 2,820 |
| again, params | each step under 100, except f (100–330) and g (130–140) |
| changed | a 53, b 60, c 5,210, d 9,780, e 2,580, f 580, g 450 |
| the whole run | 71.6 s |

- Tier S fits the 2-minute budget.
- **Upstream compiles about 18 s again when the equations change:** the fixed point, both solvers and the solution's access.
- Makie compiles 0.3–0.5 s in "changed" although its inputs keep their types. That is a finding for P3: where it comes from.
- **If the steps added since the dry run push tier S over 2 minutes,** Rodas5P moves to tier M first, then the linear analysis.
- **Why the change recompiles:** the network's type reaches the integrator through `ODEFunction.sys`. SciMLBase keeps that type when it wraps the right-hand side under `AutoSpecialize` (`ndport/pkgs/SciMLBase.jl/src/scimlfunctions.jl:3284–3310`).
  - NetworkFixedT carries it into NonlinearSolve.
  - NetworkDynamics' callback wrappers hold the network in an abstract field (`src/callbacks.jl:414, 632, 781`).
- **Known output:** OrdinaryDiffEqCore warns `dt_epsilon` ("Initial timestep too small") for solves that start at the fixed point. It goes to stderr and does not change results.

### 2.5 The tiers

| Tier | Adds | Target |
|---|---|---|
| **S** | §2.1–2.3 | under 2 min, fresh session |
| **M** | 200 vertices; a second vertex type (`docs/examples/heterogeneous_system.jl`); dynamic lines (`EdgeModel(f=…, g=Fiducial(…))`, `test/diffusion_test.jl:101`); DiffEqCallbacks' network-level callbacks (`add_nw_cb`); a sparse Jacobian (`set_jac_prototype!`) with Rodas5P; `@obsex`; `record` to MP4 (FFMPEG_jll is in the manifest; check its artifact); a change of the function alone; h2, one vertex type replaced by another | a few minutes |
| **L** | 2,000 vertices; threaded execution (with the machine's consent); MTK components through `NetworkDynamicsMTKExt`; NetworkDynamicsInspector (WGLMakie and Bonito: a server and a browser) | each a separate decision |

- MTK belongs in tier L. Its generated component functions are new types for every new equation, which is exactly the case traits target.
- MTK and the inspector need a resolve with network access. That is the user's step.

## 3. How it is run and timed

### 3.1 The harness

**`ndport/scripts/run_workload.sh <tag> <setting> [runs]`** (to write):
- one fresh process per run, through `flock /tmp/claude-1000/julia-review.lock nice -n 19 timeout 900`;
- `--startup-file=no --threads=1`;
- the environment variables:
  - `OPENBLAS_NUM_THREADS=1`;
  - `JULIA_PKG_OFFLINE=true`, `JULIA_PKG_PRECOMPILE_AUTO=0`, `JULIA_NUM_PRECOMPILE_TASKS=4`;
  - `JULIA_TW_STRICT` unset: strict mode off. Strict mode on is a P3 question.
  - `JULIA_COMPILE_BY_FACTS` unset. The facts system image switches it on under `all`.
- **Before each run:** a short check that every direct dependency `Base.isprecompiled` in that setting's depot. If one is not, the run is skipped with a message. A run never precompiles.
- **After each run:** a log that shows `Precompiling` is invalid.
- **The log's header records:**
  - the setting and the switches;
  - the julia-1.13 commit, the TraitWorld commit and its `git status`, and the clones' commit;
  - the 1-minute load average before and after.
  - A run with load above 4 is repeated once. After that, the load is recorded with the result.
- Logs go to `ndport/logs/<tag>/<setting>-<run>.log` and are committed.

**`workload.jl`** (exists):
- It switches compile timing on before the loads (`Base.cumulative_compile_timing(true)`).
- It times each step's first call whole, through `invokelatest` of a closure, as `TraitDifferentialEquations/scripts/rows.jl`'s `@first` does.
- It prints `L <group> <s>`, `T <pass> <step> <ms> compile <ms> recompile <ms> gc <ms>`, `D <pass> <step> …` and the whole run's wall time.

**`ndport/scripts/summarize.py`** (to write): a table per setting, pass and step, with the minimum and median over runs.

### 3.2 The settings

| ID | Julia | Environment | Depot | Role |
|---|---|---|---|---|
| U | patched (`julia-1.13/julia`) | `env_upstream` | `~/.julia` | the reference |
| P0 | patched | `env_port` (clones at `upstream`; TraitWorld loaded first, `NDW_TRAITWORLD=1`) | `~/.julia` | the port's starting point |
| A0 | patched, `-J julia-1.13/usr/lib/julia/facts/sys.so` (the test bed `all`) | `env_port` | `ndport/depot-facts/` | P3's starting point: does the stack precompile and run under `all` |
| S | stock 1.13.2 (`~/.julia/juliaup/julia-1.13.2+0.x64.linux.gnu/bin/julia`) | `env_upstream` | `ndport/depot-stock/` | what users have today; the patched build's plain code is not stock (`writeup/design/evidence.md`, conventions) |

- **Before A0:** check that `facts/sys.so` is newer than the build's last commit, and record both.
- **What P1 runs:**
  - U and P0: two runs each;
  - A0: one run;
  - S: one run;
  - one attribution run in U (§3.3).
  - That is about seven sessions of 1–2 minutes. n is small, so the numbers are indicative; P5 owns the measurement rounds.
- **S is repeated only at P5's milestones.**

### 3.3 What "changed" compiles

- **The attribution run** (`NDW_DIAG=1`): E-141's instrument, `experiments/loadcosts/tde_diag.jl`. It needs nothing beyond Base. For each step's window it gives:
  - the new CodeInstances, by module and by owner;
  - how many of them replace an invalidated CodeInstance;
  - the compile and recompile times.
- **`Base.@trace_compile` beside it** names the compilation roots.
- **The packages it should separate:**
  - NetworkDynamics' core loop;
  - NonlinearSolve (the fixed point);
  - OrdinaryDiffEqCore, Tsit5 and Rosenbrock;
  - DiffEqCallbacks;
  - SymbolicIndexingInterface and RecursiveArrayTools (access);
  - Makie.
- **The run is diagnostic, not timed.** Its header says so.

### 3.4 What each number says

- **The build:** julia-1.13 and TraitWorld commits, the clones' commit, the setting, strict mode off, the load order (fixed, §2.3), the number of runs, the load average.
- **What it measures:** upstream code without traits. It measures neither interop nor idiomatic trait code.

## 4. Equality of results

- **The digest:** each step prints `D <pass> <step> key=value …`, with three kinds of field.
  - **Exact:**
    - integers, symbols and retcodes;
    - the graph's edge hash and `is_connected`;
    - the PNGs' pixel dimensions;
    - the numbers of frames and of listener calls;
    - hashes of the raw bits of `uflat`, `pflat` and the solutions.
  - **Tolerance:** values printed to 10 significant digits:
    - the fixed point and the eigenvalues;
    - `ω` and `P` at fixed times;
    - `NWState(sol, 3.0)`;
    - the trip times;
    - the node colours;
    - the layout's positions.
  - **Reported:** the solver's step counts, the PNGs' byte sizes and hashes.
- **The tolerances:**
  - states, flows and eigenvalues: `rtol = 1e-5`, `atol = 1e-7`;
  - trip times: `atol = 1e-6`;
  - positions: `atol = 1e-4`.
  - The solves use `abstol = 1e-8`, `reltol = 1e-6`.
- **The trips:**
  - The script records the smallest separation between successive trips.
  - Trips closer than 0.05 in time are compared as an unordered group; the others by order.
  - In the dry run, the closest pair is 0.008 apart (`t` ≈ 2.818 and 2.825). In the params pass (`γ = 0.2`), lines 13 and 7 trip 0.002 apart.
- **Within a run:** "again" equals "first" in every field.
- **Between settings:**
  - **P0 against U:** every exact field equal. The compiler and the code are the same, so a difference is a bug.
  - **A0 and S against U:**
    - exact differences are recorded, with the first differing field;
    - the tolerance fields must hold;
    - a tolerance failure is a bug.
  - Under `all`, G1 promises plain Julia's results, but `muladd` and `@simd` may differ in the last bit with the inlining. Stock has other inliner rules.
- **In later parts:** a port step may change the order of sums. The exact fields may then differ, which is recorded; the tolerance fields must hold.
- **`ndport/scripts/compare_digests.py <ref.log> <log> [--exact]`** (to write): prints the fields that differ and whether each is within tolerance. It exits non-zero on a failed tolerance field, or, with `--exact`, on any differing exact field.

## 5. The registry row

To be added to `writeup/record/experiments.md` before the `all` precompilation, with status running. E-151 is the next free ID: E-150 is named for W-17 by the implementation plan of 2026-10-20.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-151 | W-32 P1: the NetworkDynamics workload's baselines (tier S, upstream code without traits; [the P1 plan](../plans/2026-10-21-ndport-workload.md) §2). (1) Does tier S's first session run in under 2 minutes on the patched build? (2) Are the results the same in every setting: `env_port` exactly equal to `env_upstream`, and `all` and stock 1.13.2 within tolerance? (3) What does a change of equations (a new component function) compile again upstream, by package? **Would change the plan:** tier S over 2 minutes (trimmed by §2.4's rule); P0 differing from U in an exact field, or any setting failing a tolerance field (a bug, fixed before P3); the stack failing to precompile or run under `all` (a work item ahead of P3); "changed" compiling under 2 s upstream (then P4 aims at loads and first calls, not at the rerun). | running (2026-10-21) | `ndport/` (its own repository, not pushed): `scripts/workload.jl`, `workload_steps.jl`, `run_workload.sh`, `compare_digests.py`; `logs/setup/precompile-upstream.log`, `precompile-port.log`; `logs/p1-*/` | — | `ndport/README.md`; [the P1 plan](../plans/2026-10-21-ndport-workload.md) |

The settings: U and P0 twice each, A0 and S once each, one attribution run in U. When E-151 is done, its outcome and an evidence row in `writeup/design/evidence.md` are written in one commit (CLAUDE.md, rule 1).

## 6. Risks

- **`all` and stock precompilation:**
  - the upstream stack took 320 s on the patched build. Under `all` the factor is unknown, and SciML has not been precompiled under `all` in this project (CairoMakie has, E-140). Stock should take about the same.
  - **A failure under `all`** is recorded in E-151 and becomes a work item ahead of P3. U and P0 still give P2 and P4 their baseline.
- **Failure on the patched build (U or P0):**
  - first try stock on the same manifest. If stock works, it is a bug of the patch: an open issue and a work item.
  - Nothing is patched in the clones to get around it.
- **Cache eviction:** the cap of ten cache files per package (§1.2).
  - The depots of A0 and S are separate.
  - U and P0 share `~/.julia` with every other job, so the pre-run check guards them.
  - The README's "How to run" names the cap.
- **No network in the sandbox:**
  - runs are offline;
  - a missing artifact is a setup failure, reported to the user.
- **Headless CairoMakie:**
  - `save` needs no display.
  - If fontconfig cannot write its cache, set `XDG_CACHE_HOME` under `ndport/`.
- **Generated functions:** NetworkDynamics has `@generated` helpers (`src/utils.jl:144, 161`, `src/component_functions.jl:1134`). A generator runs in its definition's world (E-141). Watch them in A0's attribution if A0 shows unexpected compilation.
- **TraitWorld changes under P0 and A0:** TraitWorld is loaded from source by path. The log records its commit and status. No run starts while TraitWorld is being edited (INDEX, "Standing constraints").
- **The shared lock:** runs wait for it; nothing runs in parallel.

## 7. Done when

1. `check_env.py` passes, and the run's manifest copy is in `ndport/logs/setup/`.
2. E-151 is in the registry, with status running, before the `all` precompilation.
3. `env_port` is precompiled under `all` in `ndport/depot-facts/`, and `env_upstream` on stock in `ndport/depot-stock/`. The logs are committed. A failure here is the outcome, recorded per §6.
4. The scripts are committed in `ndport/`. Tier S runs to the end in U, P0, A0 and S, and every log passes the precompilation check.
5. Equality, per §4:
   - "again" equals "first" in every run;
   - P0 equals U exactly;
   - A0 and S hold every tolerance field, with their exact differences recorded.
6. Tier S's first session takes under 2 minutes in U, or §2.4's trimming rule is applied and recorded.
7. The attribution run names what "changed" compiles again, by package, and says whether Makie compiles in it.
8. `ndport/README.md` has "How to run" (the depots, the cache cap, the switches) and a dated table per setting, pass and step, with the builds and the load average.
9. E-151's outcome and its evidence row are written in one commit.
10. The meta plan shows P1 done, with a line in its state table.
