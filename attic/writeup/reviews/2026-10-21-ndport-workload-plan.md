# Review: the NetworkDynamics port, P1 (the workload and its baselines)

**Reviewed:** [`../plans/2026-10-21-ndport-workload.md`](../plans/2026-10-21-ndport-workload.md) (status: proposal), part P1 of [the meta plan](../plans/2026-10-21-networkdynamics-port.md), work item W-32. Read against the user's request (session note 32, the end), CLAUDE.md, [`../intro/porting.md`](../intro/porting.md) §0.1 and §0.6, and the code in `ndport/pkgs/`: NetworkDynamics 1.3.0 (ec6afc0), SciMLBase 3.58.0, the OrdinaryDiffEq.jl clone at 53e7d1d (DiffEqBase, OrdinaryDiffEqCore, OrdinaryDiffEqTsit5), GraphMakie 0.6.6, NetworkLayout 0.4.11, Graphs 1.15.0, and `julia-1.13/base` (`timing.jl`, `loading.jl`).

**Reviewer:** Opus 5.5, 2026-10-21. Nothing was run in Julia. "Verified" means read in the code or in a log. The two manifests were compared with a short Python script.

**Severity.**
- **Blocker:** the workload will not run as written, or a number it produces would not mean what the plan says.
- **Should fix:** fix before the first timed run.
- **Minor:** housekeeping, or a cheap improvement.

## Verdict

- The plan is sound in shape and cheap enough:
  - one fixed tier-S workload in steps;
  - a control (h0) for the change of equations (h1);
  - four settings with clear roles;
  - digests with exact and tolerance fields;
  - a trimming rule for the 2-minute budget.
- Nearly every API call matches NetworkDynamics 1.3.0 and SciML as cloned. The cited line numbers are right, with one exception (finding 15).
- **Two findings make numbers mean something other than the plan says:**
  - **Finding 1:** the solves share one parameter vector. Every solve after the first starts with lines already tripped.
  - **Finding 2:** the compile counters are never switched on, so every `compile` and `recompile` column would read 0.
- Four findings should be fixed before the first timed run:
  - finding 3: the trace cannot attribute compile time to the core loop;
  - finding 4: exact equality across compilers is not guaranteed;
  - finding 5: the registry row must come before the `all` precompilation;
  - finding 6: Julia's cap of ten cache files per package.
- Several facts in the plan are stale against today's logs (finding 13).

---

## Findings

### 1. (blocker) Every solve after the first starts with tripped lines: the problems alias the parameters

**Evidence (verified).**
- `ODEProblem(nw, s0::NWState, tspan)` copies `pflat` once, when the problem is built (`NetworkDynamics.jl/src/post_utils.jl:127–131`).
- OrdinaryDiffEqCore's `__init` aliases the problem's parameters unless told otherwise. With `alias.alias_p` at its default `nothing`, `p = prob.p` (`OrdinaryDiffEq.jl/lib/OrdinaryDiffEqCore/src/solve.jl:475–479`).
- The component affect writes `p[:K] = 0` into `integrator.p`, which is `prob.p`.

**Consequence.**
- Step d solves the same problem with Tsit5 and then with Rodas5P. The Rodas5P solve starts with every line Tsit5 tripped already at `K = 0`, and from a state that is no longer a fixed point.
- Step g's `init(prob, Tsit5())` has the same problem.
- The Rodas5P digest and the live figure then describe another scenario. The cascade they show depends on what ran before them.
- Equality between passes and settings still holds, because the order is fixed. That hides the problem rather than revealing it.
- The `sol.prob.p` of the Tsit5 solution also changes under it after the later solves.

**Fix.** Build a fresh problem for each solve and for the integrator, with `ODEProblem(nw, s0, tspan)`. Alternatively pass `alias = ODEAliasSpecifier(alias_p = false)`. State this in step d. Add one digest field: `K` of the tripped lines in `prob.p` before each solve, which must be the defaults.

### 2. (blocker) `Base.cumulative_compile_time_ns()` reads 0 unless compile timing is switched on

**Evidence (verified).**
- `julia-1.13/base/timing.jl:75–89`: the counters (`jl_cumulative_compile_time_ns`, `jl_cumulative_recompile_time_ns`) advance only after `Base.cumulative_compile_timing(true)`. `@time` and `@timed` switch it on around their expression.
- The plan's `@first` model (`TraitDifferentialEquations/scripts/rows.jl:24–34`) reads only `time_ns` and `gc_num`.

**Fix.**
- Call `Base.cumulative_compile_timing(true)` once in `workload.jl`, before the loads.
- Or use `@timed` around the `invokelatest` call. It returns `compile_time` and `recompile_time`.

Either way, the loads' compile time is then visible too.

### 3. (should fix) The trace run cannot name "the core loop and below" by package

**Evidence.**
- `Base.@trace_compile` prints one `precompile(...)` line per compilation root, with its time (`timing.jl:734`). Code inferred and compiled inside a root, such as `process_batches!` under `solve` when no dynamic call separates them, carries no line of its own.
- §3.3 asks for "the share of the pass spent compiling the core loop (`NetworkDynamics.process_batches!` and below), the solvers, the callbacks, the fixed point, and Makie". The trace alone can answer this only where a dynamic boundary happens to sit, for example at a FunctionWrapper.

**Fix.** Reuse E-141's instrument `experiments/loadcosts/tde_diag.jl`. Per window, it tallies the new CodeInstances by module and by owner, with compile and recompile time. It needs nothing beyond Base. Keep `@trace_compile` beside it for the roots.
- For inference time by method, `@snoop_inference` (`snoop_rows.jl`, the same directory) works too. SnoopCompileCore is in `~/.julia/packages`, but it is not in either environment.
- Load it through a stacked environment in the trace run only, and say so in the run's header. `env_upstream` itself stays unchanged.

### 4. (should fix) Exact equality across compilers is expected but not guaranteed. "Any difference is a bug" is too strong for S and A0

**Evidence.**
- §4: "P0, A0 and S equal U in every exact field. The code is the same". §3.2 says the opposite of S: "The patched build's plain code is not stock (the inliner changes)".
- A0 compiles everything by facts. G1 promises "what plain Julia computes" ([`../explorations/wrapping-by-facts.md`](../explorations/wrapping-by-facts.md), Theorem 1). Julia's semantics leave `muladd` (OrdinaryDiffEq's `@muladd`) and `@simd` reductions free to differ in the last bit with the inlining context.
- The PNG sizes are listed as exact fields. Anti-aliased pixels move with the last bit of a coordinate, so a size can differ while the PNG's hash is "reported, not compared". The two rules contradict each other.

**Fix.**
- Make P0 = U exact: the same compiler and the same code, so a difference is a bug.
- For A0 and S against U:
  - exact differences are recorded, together with the first differing field;
  - the tolerance fields must hold;
  - a tolerance failure is the bug.
- Move the PNG byte sizes to "reported". Compare the pixel dimensions exactly.
- Change E-151's criterion to match (finding 9).

### 5. (should fix) The registry row must exist before the `all` precompilation, not just before the first timed run

**Evidence.**
- CLAUDE.md: "The row comes before the run". E-151's own criterion includes "NetworkDynamics, SciML or Makie failing to precompile or run under `all`". The `all` precompilation (§1.2) therefore already answers part of E-151's question.
- The product-setting precompilation of `env_port` has already run (`ndport/logs/setup/precompile-port.log`).

**Fix.**
- Add E-151 now, with status running, before the `all` and stock precompilations.
- Record the two existing setup logs in its Where column.
- Dry runs that only choose `K` and `limit` stay outside it, as the plan says.

### 6. (should fix) Julia keeps at most ten cache files per package. Another setting in the shared depot can evict U's

**Evidence (verified).**
- `julia-1.13/base/loading.jl:3372, 3450–3466`: `MAX_NUM_PRECOMPILE_FILES = 10`. When a new cache is written, the oldest by mtime is deleted.
- The cache file's slug hashes the project, the system image and the Julia binary (`loading.jl:3334–3354`), so U, P0 and S each get their own file.
- `~/.julia/compiled/v1.13/Makie/` holds exactly ten caches today (2026-10-16 to 2026-10-21; U's of 16:11 and P0's of 16:14 among them).
- S's precompilation into the same depot, and every later environment that builds Makie (demonstrators, experiments), evicts one each. A U run weeks later can then precompile Makie, about 135 s, inside its timed session. The plan detects this only after the fact ("a run whose log shows `Precompiling` is invalid").

**Fix.**
- Give S a depot of its own, `ndport/depot-stock/` (see "The two open choices").
- Before each run, check that the needed caches are loadable. A two-line Julia call of `Base.isprecompiled` over the environment's direct dependencies is enough. Skip the run with a message if one is missing; never let it precompile.
- Note the cap in the README's "How to run".

### 7. (should fix) The live figure: say what the buffer holds, so the switch to three vertices has their history

**Evidence.**
- Step g keeps "an `Axis` with `ω(t)` of a selected vertex, from an `Observable` buffer", and switches the selection to three vertices at the end.
- If the buffer holds only the selected vertex's values, the three newly selected vertices have no history. The user asked for "a plot with Observables to quickly look at different trajectories as they are simulated". Switching between trajectories is the point.

**Fix.**
- Buffer `ω` of all vertices at every frame, from a copy of `NWState(integ)`'s values. `NWState(integ)` aliases `integ.u` and `integ.p` (`symbolicindexing.jl:257`).
- Alternatively, read history from `integ.sol(ts; idxs = …)`.
- Derive the plotted lines with `lift` from the buffer and the selection.
- Plot a fixed number of series, or one `series!` over a `Vector{Vector{Point2f}}`, so that x and y never change length separately.
- Fix the colour range of the node colours (`colorrange`) so the PNGs do not depend on autoscaling.
- Say which four frames are saved.

### 8. (should fix) Choose `K` and `limit` so that the cascade is robust, and record its margins

**Evidence.**
- The trip lines and their order are exact fields. A cascade with two near-simultaneous trips, or a flow that grazes its limit, can change order or membership after a later reordering of sums (§4, "in later parts").
- The trajectory then leaves every tolerance. A port step would look wrong when it is right.

**Fix.**
- In the dry run, require that successive trips are at least about 0.05 time units apart, and that each crossing is transversal (`|dP/dt|` at the trip clearly non-zero).
- Write the smallest separation into the script's header and the digest.
- Run the dry run's candidate values in one session, in a loop. That avoids one 2-minute session per candidate.
- Also digest `is_connected(g)`. A Watts–Strogatz rewiring can isolate a vertex, and then the alternating `P_ref` no longer balances in every component.

### 9. (should fix) E-151: make the criteria decidable and consistent

- "Any exact digest difference between settings (a bug, fixed before P2)" conflicts with finding 4. P2, the traits question, does not depend on digests. Write instead:
  - "P0 differing from U in an exact field, or any setting failing a tolerance field: a bug, fixed before P3."
- "The change of equations compiling little upstream" needs a number. For example: "changed" minus "params" (compile time) below a quarter of "first" minus loads. Name the measure (compile time from finding 2, or wall time).
- The row lists "stock 1.13.2 once" while §1.2 and §3.2 keep S optional. Decide it before the row is written (see below).
- **Numbering:** the registry's rule is "the next free number". E-150 is not in the registry; it appears only in a plan and a review of 2026-10-20 as a design that moved to W-17. Use E-150, or note that it is reserved.
- The row is long. Its question could be the three questions alone; the setting list belongs in Where or the plan.

### 10. (minor) The claim "the callbacks carry its type" is not what the code does

**Evidence (verified).**
- `ContinuousCallbackWrapper`, `DiscreteCallbackWrapper` and `PresetTimeCallbackWrapper` hold `nw::Network`, an abstract field (`callbacks.jl:414, 632, 781`). Their type parameters are the component callback, the condition closure and the index types.
- The network's type reaches the integrator through `ODEFunction.sys`. `unwrapped_f` keeps `typeof(f.sys)` (`SciMLBase.jl/src/scimlfunctions.jl:3284–3310`).

**Fix.** Correct the sentence in §2.4. It matters for P2 and P4: NetworkDynamics' callbacks already erase the network, and its `sys` field does not.

### 11. (minor) h1 changes two things: the function's type and the parameter count

**Evidence (verified).**
- `ComponentBatch{T,F,G,FFT,DIM,PDIM,…}` carries the dimensions as static types (`network_structure.jl:181–202`, `utils.jl:1–9`). Adding `κ` changes `PDIM` as well as `F`.

**Fix.**
- Either let h1 keep the parameter list (for example, cubic damping on `γ`) and move "a new parameter" to tier M, beside h2.
- Or keep h1 as it is, and say in §3.3 that it changes both.
- Say also whether h1 starts from h0's `γ` or the original one.

### 12. (minor) Smaller API points

- **Edge parameters without defaults.** `psym=[:K, :limit]` without defaults leaves both `NaN`, so `find_fixpoint` raises `NetworkInitError` ("Some input states/parameters contained NaN", `initialization.jl:108–121`). The example writes `psym=[:K=>1.63, :limit=>1]`. Write the chosen values as defaults in the same way.
- **Frame times.** Ten calls of `step!(integ, 0.6, true)` reach 5.999999999999999, not 6.0, because the times accumulate in floating point. Step to absolute times, `tₖ = 0.6k`, with `step!(integ, tₖ - integ.t, true)`. Alternatively use a frame interval that is exact in binary.
- **Digests outside the timed window.** Each step "prints one digest line". The digest's hashing and printing must run after the timer stops, or "first" counts their compilation.
- **One more symbolic access.** Add `SII.getp`/`epidxs` beside `getu` in step e: the example's cached accessors, which are cheap.
- **Two cheap additions that widen the coverage.** Each is new code per network type, so "changed" counts them too.
  - `remake(prob; p = …)` in h0, SciML's own way to change parameters without new types. It is exactly the control's case.
  - `isfixpoint(s0)` and `jacobian_eigenvals(s0)` in step c (`linear_analysis.jl:8, 237`): NetworkDynamics' linear analysis with a ForwardDiff Jacobian.

### 13. (minor) Stale facts in the plan, against today's logs

- §1.1: "Its precompilation is running". It is done: 445 packages and extensions in 320 s; `using` of the five main packages takes 5.4 s (`ndport/logs/setup/precompile-upstream.log`). "352 packages" counts the manifest. Say that the 445 include extensions.
- §1.2: `env_port` in the product setting is "close to a full precompilation again". Measured: 72 packages in 175 s, 432 already precompiled (`precompile-port.log`). The manifest was created by a fresh offline resolve, not by copying; the versions and trees still agree (below).
- §2.4: loads "10–20 s". Measured: 5.4 s without Rosenbrock, DiffEqCallbacks, Observables and SymbolicIndexingInterface. The risk "loads over 40 s" in §6 can go.
- §6: "three or four near-full precompilations, each perhaps 20–40 minutes". The measured full one took 320 s. Under `all` it will be slower, but by an unknown factor; say "unknown, measured in P1".

### 14. (minor) `check_env.py`: a fifteenth path-tracked package, and untracked files

**Evidence (verified).** Comparing the two manifests gives the same version for every package. The differences:
- the fourteen clones are tracked by path;
- TraitWorld is added;
- **ComputePipeline 0.1.8** is tracked by path (`../pkgs/Makie.jl/ComputePipeline`), through Makie's own `[sources]`. Its tree at the clone's commit is the release's (7bc84b76…).

**Fix.**
- Let `check_env.py` allow ComputePipeline, and check its tree with `git rev-parse upstream:ComputePipeline`.
- Add `git status --porcelain` to the clean-clone check: `git diff upstream` ignores untracked files.
- `ndport/.gitignore` ignores `env_port/Manifest.toml`. Copy the manifest P1 runs against into `logs/setup/`, so that the baseline's environment is on record.

### 15. (minor) Citations and settings to state

- Step e cites `docs/src/symbolic_indexing.md` for `SII.getu`. The only place is `docs/examples/cascading_failure.jl`.
- **Strict mode.** CLAUDE.md rule 5 requires that a number say whether strict mode is on. TraitWorld reads `JULIA_TW_STRICT` (`TraitWorld/src/strict.jl:17–20`).
  - The harness should set the switches explicitly: `JULIA_TW_STRICT` unset (off), and `JULIA_COMPILE_BY_FACTS` unset (in U, P0 and S; under A0 the facts system image switches it on, facts §12, and `=0` would switch it off).
  - Each log should record the switches.
  - Strict mode on is a P3 question.
- **BLAS threads.** Set `OPENBLAS_NUM_THREADS=1` in the harness. Rodas5P factorizes through LinearSolve; `--threads=1` does not limit BLAS on a 16-core shared machine.
- **The load rule.** "Load above 4 is repeated" needs a cap, say one repeat, after which the load is recorded with the result.
- Record the TraitWorld commit and a clean `git status` for P0 and A0. TraitWorld is loaded from source by path while other work changes it (INDEX, "Standing constraints").

### 16. (minor) Where the logs live

- CLAUDE.md puts experiments' scripts and logs in `experiments/<dir>/`. The adopted meta plan puts them in `ndport/`, a repository of its own that the design repository ignores. The registry row then points outside the design repositories.
- Say in the README, and in E-151's Where column, that `ndport/` is that experiment's directory, and where it is kept (it is not pushed).

---

## Item 2: does the workload cover the ecosystems, and does "changed" measure the right thing?

- **Coverage (tier S) is good for its budget:**
  - NetworkDynamics: components, `AntiSymmetric`, `dealias`, defaults, `find_fixpoint` (NonlinearSolve and SteadyStateDiffEq), component callbacks of two kinds, `NWState`/`NWParameter`, `VIndex`/`EIndex`, `vidxs`/`eidxs`;
  - SciML: an explicit and an implicit solver with a ForwardDiff Jacobian, continuous and preset-time callbacks, the integrator interface, interpolation, SymbolicIndexingInterface;
  - Graphs: a generator;
  - GraphMakie and NetworkLayout: a layout with colours;
  - Makie and Observables: `Observable`, `lift`, `on`, a figure saved headless.
- **What it leaves out, with finding 12's additions:** `remake`, the linear analysis, `getp`. The rest belongs in tier M as planned.
- **Running headless is fine.**
  - CairoMakie's `save` needs no display.
  - The fontconfig cache is the only expected warning. `XDG_CACHE_HOME` under `ndport/` handles it, since `~/.cache` is not writable in the sandbox.
- **"changed" is designed correctly.**
  - A new vertex function gives a new `ComponentBatch` and a new `Network` type.
  - `ODEFunction.sys` carries that type into the integrator, whether or not `AutoSpecialize` wraps the right-hand side (`DiffEqBase/src/solve.jl:1038–1056`).
  - `NetworkFixedT{Network{…}}` carries it into NonlinearSolve's polyalgorithm. That is probably the largest single recompile.
- **The control is right in kind.** h0 has no new types; h1 has new types. The difference is the cost of a new component type.
  - f and g in h1 are an in-pass control for Makie: its inputs (`Vector{Float64}` colours) do not change type, so Makie should compile nothing in h1. Say so in §3.3, and treat Makie compiling in h1 as a finding.
  - The control is complete with findings 2 and 3, which make compile time measurable and attributable, and finding 11, which separates the function from the shape.

## Item 3: timing, settings, digests

- **The timing method is right:** whole first calls through `invokelatest`, one fresh process per run, niced, behind the lock, with the load average logged. It needs finding 2.
- **The settings are right in role.** n = 2 for U and P0 is indicative and cheap.
  - A0 in P1 matters mainly to learn early whether the stack precompiles and runs under `all`. One run is enough there; P3 owns the measurements.
  - P1 then has about seven runs plus one trace run: roughly 20 minutes of sessions after the precompilations. That is not excessive.
- **The digests are cheap and well chosen,** with findings 4 and 8 applied.
- **The tolerances are consistent with the solver settings,** if the cascade is robust (finding 8).

## The two open choices

### Keep the stock baseline S?

**Yes. Run it once in P1, in a depot of its own, and require tolerance equality, not exact equality.**

- **The cost is small:**
  - one precompilation of about the measured 320 s;
  - about 1.5 GB of caches (the `.so` files the upstream precompilation wrote today total 1.5 GB);
  - one run of 2–3 minutes.
- **What it buys:**
  - The baseline users have today. The user asked for stock Julia and upstream packages as fair baselines.
  - The inliner changes kept apart from the port's gains. Patched-plain is not stock (`../design/evidence.md`, conventions).
  - A correctness cross-check of the patched compiler on a 445-package stack, through the tolerance fields.
- **Its own depot:** `JULIA_DEPOT_PATH=ndport/depot-stock:$HOME/.julia:`. This avoids the eviction of finding 6, and keeps S's 1.5 GB out of the depot every other job uses.
- **Repeat it only at P5's milestones,** as proposed.

### Put the `all` depot on disk at `ndport/depot-facts/`?

**Yes.**

- **Against `/tmp`:**
  - `/tmp` is a 16 GB tmpfs, that is RAM, on a 30 GB machine shared with simulations.
  - This stack's caches will take one to several GB. The upstream `.so` files alone are 1.5 GB; under `all` the size is unknown.
  - The contents vanish at a reboot, and the `all` precompilation of SciML and Makie is the most expensive and least known step of P1.
- **Against sharing with `experiments/checks`:** a depot of its own also keeps that stack's caches out of `/tmp/claude-1000/depot-facts` (570 MB today), which `experiments/checks/run_all.sh` uses. It should stay small and quick to rebuild.
- **The only cost:** TraitWorld is compiled once more for this depot, which is trivial.
- **Conditions:**
  - add `/depot-facts/`, `/depot-stock/` and the XDG cache directory to `ndport/.gitignore`;
  - use the same `JULIA_DEPOT_PATH` for the precompilation and the runs;
  - name the depots in the README's "How to run".
- [`../intro/porting.md`](../intro/porting.md) §0.6 gives `$TMPDIR/depot-facts` only as an example ("such as"), so this does not conflict with it.

---

## What was checked and holds

- **The API, as written, against the code:**
  - `VertexModel(f, g=1, sym, psym)` and `EdgeModel(g=AntiSymmetric(…), outsym, psym)`;
  - `Network(g, v, e; dealias=true)`: one batch each, since batching hashes the function, not the object (`construction.jl:259`);
  - `set_default!`, `find_fixpoint(nw)` (SSRootfind, x0 zeros), `set_defaults!`, `NWState(nw)`;
  - `s.v[1, :ω]`, `s.p.e[:, :K]` (colon indexing as in `docs/src/symbolic_indexing.md:44`);
  - `ComponentCondition`/`ComponentAffect` with `ctx.eidx` and `ctx.t` (`callbacks.jl:76–81`);
  - `ContinuousComponentCallback`, `PresetTimeComponentCallback`, `set_callback!`, `add_callback!`;
  - `ODEProblem(nw, s, tspan)` (`post_utils.jl:127`). Its default `BrownFullBasicInit` runs only for DAEs, so it needs no OrdinaryDiffEqNonlinearSolve, which is not in the manifest (`OrdinaryDiffEqCore/src/solve.jl:960–963`);
  - `NWState(integ)` and `NWState(sol, t)` (`symbolicindexing.jl:257, 266`);
  - `step!(integ, dt, stop_at_tdt)` (`SciMLBase/src/integrator_interface.jl:1338`);
  - `watts_strogatz(…; seed)` (`randgraphs.jl:337`, MersenneTwister);
  - `Spring(seed=1)`;
  - `graphplot` with `layout`, `node_color` and `edge_color` (`GraphMakie/src/recipes.jl:152–167`).
- The sum of `P_ref = ±1` over 20 vertices is zero, which a fixed point with `ω = 0` needs.
- The upstream and port manifests agree in every version, apart from the path tracking (finding 14).
- The tier and trimming rules, MTK out of tier S, and the failure handling of §6 ("nothing is patched in the clones to get around it") are all consistent with the meta plan and the porting guideline.
