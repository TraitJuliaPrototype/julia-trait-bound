# Review: the NetworkDynamics port's traits plan (P2, and P4's first step)

Date: 2026-10-21. Reviewer: an Opus 5.5 agent, fresh eyes. Not edited after writing, except by a dated addendum.

**Reviewed:** [`../plans/2026-10-21-ndport-traits.md`](../plans/2026-10-21-ndport-traits.md) (status: proposal).

**Read against:**
- the meta plan [`../plans/2026-10-21-networkdynamics-port.md`](../plans/2026-10-21-networkdynamics-port.md);
- the exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md);
- the P1 plan, E-151 ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), `ndport/logs/p1/`, the attribution `ndport/logs/p1-diag/U-1.log`);
- the P3 plan [`../plans/2026-10-21-ndport-facts-first.md`](../plans/2026-10-21-ndport-facts-first.md) and its review [`2026-10-21-ndport-facts-first-plan.md`](2026-10-21-ndport-facts-first-plan.md);
- [`../reference/traits.md`](../reference/traits.md) §2, §4.7, §5.3, §5.4, §6.8, §7 and its Deviations; [`../reference/lowering.md`](../reference/lowering.md) §9.3, §15.2; [`../intro/porting.md`](../intro/porting.md) 0.1a–0.7, A12;
- NetworkDynamics 1.3.0 at `upstream` (`ndport/pkgs/NetworkDynamics.jl`): `NetworkDynamics.jl`, `network_structure.jl`, `construction.jl`, `coreloop.jl`, `utils.jl`, `aggregators.jl`, `gbufs.jl`, `callbacks.jl`, `initialization.jl`, `linear_analysis.jl`, `post_utils.jl`, `symbolicindexing.jl`, `precompile_workload.jl`, the tests named in the plan;
- TraitWorld e9f4bfe: `core.jl`, `entry.jl`, `attributes.jl`, `untyped.jl`, `implement.jl`, `checks.jl`, `trait_module.jl` (the entry's generation).

No Julia was run. Every cost below is from reading the code, not measured.

## Verdict

- **The step's central claim holds for the workload.** Every path by which a component function's type reaches SciML goes through the `Network`'s type parameters. Erasing the batches (both containers, all ten parameters) makes that type the same for `swing!` and `swing2!` (§1 below). The plan's `sametype` check tests exactly this.
- **The trait declaration is correct** in TraitWorld's current spelling (§2).
- **The barrier allocates, by the code:** about four allocations per crossing, one per batch per pass, so ND's flat-allocation test fails by construction. Three of the four can be removed in NetworkDynamics now, with upstream's own pattern (finding 4).
- **Layout B does not need two submodules** (finding 5).
- **One blocker:** the working tree and the environment are shared with P0 and with P3's running E-153 (finding 1).
- **The checks are cheap, but they miss most feed-forward kinds and the external inputs.** These are exactly the paths the batch function restates (finding 7).

## Findings

### 1. (blocker) One working tree and one environment for P0, P and P3's N

- S0 adds TraitWorld to ND's `[deps]` and resolves `env_port` again. Setting P0 is `env_port` with the clone at `upstream`. So from S0 on, P0 and P load whatever branch is checked out, with a manifest written for the other branch.
- P3's E-153 is registered as running. Its setting N uses the branch `p3-wrap` in the same clone (the P3 plan §1.4 item 9, and the scripts table, `p3_wrap_nd.sh`). Commits on `trait-port` and runs of N cannot share one working tree.
- The P3 review's finding 1 says the same, and that "the P4 draft needs the same rule".
- **Fix:**
  - a worktree for `trait-port`: `git -C pkgs/NetworkDynamics.jl worktree add ../NetworkDynamics-trait-port trait-port`;
  - an environment `ndport/env_p4/`: `env_port`'s project, with NetworkDynamics' `[sources]` path at the worktree, resolved offline;
  - setting P uses it, and `env_port` stays as E-151 measured it;
  - criterion 3's "rerun P0 before S0" then needs no checkout.

### 2. (should fix) The claim needs its scope and its list of paths

The plan states that the `Network`'s type "no longer depends on the equations". Read against the code, that holds for a change of **functions and dimensions**. It does not hold for a change of the network's **structure**. The table below lists every path by which the model reaches the integrator or the nonlinear solver after S8.

| Path | Where | After S8 | In the plan |
|---|---|---|---|
| Vertex batches, `VTup` | `network_structure.jl:88–90`, `:109` | `Vector` of one concrete type | S8 |
| Edge batches, `NetworkLayer{GT, ETup, AF}.ETup` | `network_structure.jl:168–172`; `construction.jl:199–214` | the same | S8 ("the batch containers") |
| The batch's ten parameters `F, G, FFT, DIM, PDIM, INDIMS, OUTDIMS, EXTDIM, IV` (+ `M`) | `network_structure.jl:181–203`; `utils.jl:1–10` (`StaticInt` strides) | `Any, Any, FeedForwardType, Int, Int, Int` or `@NamedTuple{src::Int, dst::Int}`, …, `Vector{Int}`, `Kept{ComponentDynamics}` | S2, S3, S8 |
| The aggregator, `AF` | `construction.jl:211`; `SequentialAggregator{F}` `aggregators.jl:134` | independent of the batches | not mentioned. **`NaiveAggregator{F, ETup, G}` turns the batches into a tuple again** (`aggregators.jl:18–25`, `Tuple(batches)`): its type then follows the number of edge batches. Not the workload's aggregator |
| Gather buffers, `GBT` | `gbufs.jl:7–21`, `:36–53` | independent of the batches | — |
| Caches, `CT` | `construction.jl:218–221` | `DiffCache` of `Vector{Float64}`; the chunk is a length, not a type | — |
| The mass matrix, `MM` | `construction.jl:217`, `:423` | follows the components' mass matrices | not mentioned: a change from ODE to DAE components still changes the type |
| Loopback map `LM`, external-input map `EM` | `construction.jl:229`, `:232` | `nothing` or a map | not mentioned: adding loopback edges or external inputs still changes the type |
| `ODEFunction(nw)`: `f`, `sys = nw`, the mass matrix, `jac_prototype` | `post_utils.jl:83`; `network_structure.jl:336–346` | derived from `Network` | covered by `sametype`. `sparse = true` changes `jac_prototype`'s type, constant across a change of equations |
| The fixed point: `NetworkFixedT{NW}`, NonlinearSolve's function, ForwardDiff's tag | `initialization.jl:63–68`, `:81–84` | derived | covered |
| Linearization: the closure `h!` and its ForwardDiff tag | `linear_analysis.jl:83–84` | derived | covered |
| `NWState{U, P, T, NW}`, `NWParameter{P, NW}` | `symbolicindexing.jl:27`, `:105` | derived | covered |
| Callbacks: the wrappers hold `nw::Network` (abstract). The batched condition captures `obsf = SII.observed(ccw.nw, …)`, whose type follows the concrete network, and so do `VectorContinuousCallback`, `CallbackSet` and the integrator | `callbacks.jl:414–420`, `:477–517`, `:247–270` | derived | covered. The user's `ComponentCondition{C, DIM, PDIM}` and `ComponentAffect` types (`callbacks.jl:49`, `:98`) are the same closures in every pass |
| `ODEProblem`'s `initializealg` | `post_utils.jl:51`, `:96–101` | `BrownFullBasicInit()` without `jac_prototype` | — |

**What still compiles for a new key** is more than "the two batch functions at each element type":
- the batch functions per **argument signature**:
  - the pass: `Val{:g}`, `Val{:f}`, `Val{:fg}`;
  - the buffers: `(nothing, nothing)`, `(aggbuf, nothing)`, `(gbuf, extbuf)`;
  - the element types: `Float64`, and the duals of the fixed point, of the linearization and of Rodas5P;
  - `du === nothing` with `t === nothing` from `get_buffers` under symbolic access (`coreloop.jl:103–109`);
- `_vertex!` and `swing2!` at each of these signatures;
- in step b: `FunctionDynamics`' constructor and `Kept{ComponentDynamics}(x)`. That constructor runs `Compiled{X}(x)` → `_assemble` → the family member check and builder at first use (`core.jl:584–587`, `:474–479`; `implement.jl:803–830`);
- at the first crossing: the entry's table entries (`untyped.jl:65–100`, `:221–258`).

This is all small, and the plan's expectation stands.

**Fix:** state the scope in §2.1 ("a change of component functions and dimensions; not of mass matrices, loopback edges, external inputs, execution style or aggregator"). Add the table, or a pointer to this review, so that the attribution run (§3) is read against a list.

### 3. (should fix) The direct tests of the claim are not success criteria; step b is outside the gate

- `sametype=true` (§2.5) is the claim itself, and is cheap, but §3 does not list it as a criterion.
- Criterion 2 gates on milliseconds at n = 2.
  - A count is less noisy. U-1.log attributes about 2,300 of "changed" c–e's 6,536 new CodeInstances to SciML's and SII's modules (top modules only): c 857, d 1,259, e 219.
  - After the step, those should be near zero.
- The port moves work into step b: construction now builds `FunctionDynamics` and `Kept`, and runs the member check (finding 2). Criterion 2 sums only c, d, e.
- **Fix:**
  - criterion 0: `sametype=true` after S8, a gate;
  - criterion 2: the sum over **b–e**;
  - and, from the attribution run, "changed" b–e CodeInstances owned by SciMLBase, DiffEqBase, OrdinaryDiffEqCore, the NonlinearSolve packages and SymbolicIndexingInterface, at most about 50 (pick the number before the run).
  - A count above it names the leak directly, before the milliseconds are read.

### 4. (should fix) The barrier allocates about four times per crossing, and three of the four can go now

**What the code does at `run_vertex_batch!(compiled_for(batch.model), …)` from plain code:**
- The entry is the tabled form (`trait_module.jl:946–987`). The value is a `Kept` holding `Compiled` (`attributes.jl:253–255`), so the entry looks up the pattern pointer `_pentry`.
- For a family member, `_umiss` marks the type `_UNTABLED`, valid for one world (`untyped.jl:78–89`). `_pmiss` stores `C_NULL` (`untyped.jl:233–237`). Each call pays the table lookup and then falls through to `enter`.
- `enter` → `_enter_compiled(p, _dyn_held(t))` with `t::Any` (`entry.jl:215–223`): a dynamic call that returns the trait object. `_assemble` reaches `_conf_family` (an `IdDict` lookup by type, `implement.jl:803–806`) and the builder.
- The trait object is not isbits: `View` has `o::Any` (`core.jl:68–74`). Returned from a dynamic call it is boxed. **One allocation.**
- `checked_call(fname, newnames...)` (`trait_module.jl:926`) has a trait object of unknown type, so the call is dynamic. Its arguments are boxed:
  - `batch`, an immutable with pointer fields, stored inline in the `Vector`;
  - `inbufs`, a tuple;
  - `t::Float64`;
  - `du`, `u`, `o` and `p` are arrays, already on the heap; `ex` and `fg` are singletons.
  
  **Three allocations.**
- So about 4 allocations per crossing, 3 crossings per right-hand side in tier S: about 12 per call. The count grows with the number of batches. So `inhomogeneous_test.jl:93` (`rhs_allocs(small) == rhs_allocs(large) ≤ 4`) fails on the equality, not only on the bound. Upstream keeps that count flat with one `Ref` per pass (`utils.jl:56–70`).
- **S2's justification is wrong in this setting.** "Over a vector of a concrete element type, a plain loop instead of the `Ref` of arguments (no boxing, no allocation)" holds only while the loop body makes no dynamic call. The barrier is a dynamic call.
- **An estimate, not measured:**
  - a table lookup, two dynamic calls, an `IdDict` lookup and four small allocations: a few hundred ns per crossing;
  - tier S step d has a few thousand right-hand-side calls, so a few ms. That is within criterion 3's 5 ms slack;
  - so criterion 3 likely passes and criterion 5 likely fails. The plan can predict that rather than discover it.

**Fix, in NetworkDynamics, within the language:**
- The bounded functions take `(m::ComponentDynamics, batches, k::Int, args::Base.RefValue)`.
- `process_batches!` builds `args = Ref((ex, fg, inbufs, du, u, o, p, t))` once per pass, as upstream's `unrolled_foreach` does, and passes the vector of erased batches with the index.
  - A `Ref` is a heap object already, so passing it boxes nothing.
  - Julia keeps boxes of small `Int`s preallocated.
  - Inside the worker, `args[]` and `batches[k]` are of concrete types.
- Then a right-hand side allocates at most one `Ref` per pass that has batches, plus the trait object per crossing.
- Keep S2's plain loop: it now carries no boxed arguments.

**What remains is TraitWorld's:** the trait object built behind a dynamic call on the generic path for family members.
- The pattern pointer builds the views inside the callee (`_UCall`, lowering §9.3).
- Serving family members there would remove the last allocation. That changes lowering §9.3, so it is not this exercise's to do.
- Record PB-4 now, with these paths and the numbers from `rhs_check.jl` after the fix, and ask the user whether it becomes a work item.
- Also in PB-4: a family member's table entry is valid for one world. Each world change adds an entry for the type, and the lookup scans them (`untyped.jl:88–96`). In a session that defines many methods (Revise), the barrier's lookup grows.

**PB-4's "idiomatic form" needs the same correction.** A plain function barrier also boxes its non-pointer arguments; upstream's `Ref` exists for that. The fair comparison is with one dynamic call per crossing and no allocation per batch.

### 5. (should fix) Layout B needs one trait submodule, not two; PB-3 is not forced, PB-2 is misframed

- S3 makes the model a **type parameter** `M` of `ComponentBatch`, with field `model::M`. So `network_structure.jl` never names the trait where the struct is defined (`:181`).
- Only two places build a model:
  - the inner constructor's `kept` keyword;
  - `constructorof`.
  
  `VertexBatch` and `EdgeBatch` (`construction.jl:381–414`, included after `gbufs.jl`) can build it and pass it to the inner constructor. A method body naming a binding defined later resolves it when it runs. `constructorof` can call such a function.
- So one `@trait_module module BatchLoop` in a file included after `gbufs.jl` (`NetworkDynamics.jl:71`) can hold everything:
  - the trait, `FunctionDynamics` and its methods, the `@implement`;
  - the two batch functions.
  
  It ends after everything it calls exists (the range helpers, `get_src_dst`, `ThreadedExecution`), so its definition check sees them. No code moves.
- **PB-3:** drop it, or keep it only if P refuses this layout.
- **PB-2:** the restatement of `_needs_*` in `_vertex!` is needed in either layout, for a reason the plan does not give. The erased batch no longer carries the static facts: `fftype(batch)` is an abstract field, and `pdim(batch)` is an `Int`. Calling the batch-based helpers would give `Union` arguments at the user's function.
  - Whether a bounded method of the parent's `_needs_u` may be defined inside the trait submodule (traits §2: bounds "exist only inside trait modules"; the owner is the package root) is a one-line check at S4.
  - If it is accepted, PB-2 does not arise in layout B either.
- **The layout decision cannot be taken yet.** E-153 has not run, and the P3 plan is in review. Give a default so that S0 is not blocked: layout B with one submodule. Layout A follows when E-153 shows N holds, by moving the file's content up (the plan's own §2.2, last bullet).

### 6. (should fix) The pushback entries that the code already settles

- **PB-4:** settled by reading (finding 4). Write it with the paths now. E-152 adds the numbers.
- **PB-7 (Polyester):** `Polyester.@batch` hands the loop's variables to `Polyester.batch`.
  - The definition check refuses a trait object passed bare, or stored in a tuple (`checks.jl:150–158`, `:191–195`).
  - It accepts a closure that captures one (`checks.jl:101–111`; `_hastobj` looks at the argument's type, not at a closure's fields).
  - Which of these Polyester's expansion is decides the outcome. Expand the macro once at S7 before writing the branch, and record the answer.

### 7. (should fix) The checks do not reach the restated logic for most feed-forward kinds, nor external inputs or `@set`

- Tier S has one vertex kind: `g = 1` is a `StateMask`, which is `PureStateMap` (`component_functions.jl:81–92`). Its edges are static and `PureFeedForward` (`AntiSymmetric(line!)`). It has no external inputs and no loopback edges.
- The ND test subset adds none of them. By grep, no `FeedForward`, `ff=` or `extin` appears in `massmatrix_test.jl`, `doctor_test.jl`, `diffusion_test.jl` or `inhomogeneous_test.jl`. The tests that have them (`external_inputs_test.jl`, `loopback_test.jl`, `callbacks_test.jl`, `symbolicindexing_test.jl`, `sparsity_test.jl`) load ModelingToolkitBase, Chairmarks or Symbolics.
- Unchecked as a result:
  - the vertex pass with feed-forward (`coreloop.jl:55`);
  - `FeedForward`, `NoFeedForward` and `PureFeedForward` vertices;
  - `EXTDIM` in the key;
  - S3's `constructorof` under `@set batch.compf = …` (`sparsity.jl:108–170`).
- These are the four places where `_vertex!` and `_edge!` restate upstream's logic, and where an exact-equality bug would hide.
- **Fix:** `rhs_check.jl` builds a few small networks without ModelingToolkit:
  - a vertex of each feed-forward kind, each with a loopback edge where ND requires one;
  - one model with `extin`;
  - for each: compare `du`'s bits and the bits of `get_buffers`' `o`, `aggbuf` and `extbuf` with upstream's;
  - compare `get_jac_prototype(nw)` with upstream's (SparseConnectivityTracer is ND's own dependency).
  
  Seconds each.

### 8. (minor) Numbers from the dry run instead of E-151

- The summary, §3 criterion 2 and the E-152 row cite `dry3.log` ("about 16 s", "4,360 + 8,757 + 2,650 ms"). The home of these numbers is [evidence §3](../design/evidence.md#3-first-calls-and-sessions), E-151:
  - "changed" compiles 15.6–16.0 s in U, 15.8–15.9 s in P0, two runs each;
  - the attribution run (U-1.log, not a measurement) gives 4,126 + 8,533 + 2,527 ms for c–e.
- **Fix:** cite E-151 and the evidence; use P0's E-151 values as "Before".

### 9. (minor) Register E-152 before the first `rhs_check.jl` run

The U reference run of `rhs_check.jl` comes before S0, and it is E-152's data. The meta plan's ground rule says experiments are registered before they run. **Fix:** add the row, status running, before that run, not "before the first P run".

### 10. (minor) What the member check checks

- §2.6 says a member check "cannot infer a user's `f` at untyped arguments" and passes because "the result is `Nothing` from `compf!`'s own `nothing`".
- With abstract declared arguments, `conformance_problems` only asks that a method exists (`implement.jl:256–264`). Inference does not run, so `compf!`'s `nothing` plays no part.
- A member with `f === nothing` (the static edge) passes the same way.
- **Fix:** correct the sentence.

### 11. (minor) `@propagate_inbounds` component functions lose the loop's `@inbounds`

- Upstream's `apply_compf` and `apply_compg` are `@propagate_inbounds` (`coreloop.jl:213–233`). ND's own precompile workload declares its components `Base.@propagate_inbounds` (`precompile_workload.jl:4–11`).
- On the trait path, the user's function is called from `FunctionDynamics`' methods through the operation. Nothing propagates the loop's `@inbounds` there.
- Results stay equal; speed may not. Note it where criterion 3 is read. `swing!` does not use it.

### 12. (minor) Threads

- [Evidence §5](../design/evidence.md#5-not-shown) lists threads as untested in the facts mode. The worker runs `Threads.@threads`.
- S7's check exercises the threaded style with whatever thread count the session has.
- **Fix:** run `rhs_check.jl` with `-t 2` for that style.

### 13. (minor) Criterion 3 with two runs

- 10 % + 5 ms is tight for step g (200 ms, Makie) on a shared machine.
- "The port stops before step 2" should follow a confirmed failure: rerun the failing step's setting once before pausing.

### 14. (minor) Run the ND test subset after S6 and S8 too

- It takes minutes, and it covers every execution style and more than 25 batches (`inhomogeneous_test.jl:89–93`). Run only at S9, it finds a break after three more commits.
- **Fix:** run it after S6 and S8 as well. The allocation assertions are expected to fail; list them.

## The questions asked, briefly

1. **Does only the new model's batch worker compile?** Yes for the workload, once S8 erases both containers and all ten parameters. Every SciML path is derived from the `Network` type (the table in finding 2). The scope is functions and dimensions, not structure. Also compiled for a new key: the workers per argument signature, the construction and the member check in step b.
2. **`ComponentDynamics` in today's spelling:** correct.
   - The keys form, with the trait's name on the receiver (`trait.jl:237–240`).
   - Operations on existing functions, qualified.
   - Untyped buffer arguments: only a method's existence is checked.
   - The one-line variable-form family (BaseTraits uses it, `BaseTraits.jl:83–90`), members checked at first use.
   - `@default_with_dynamic_self` makes a plain `Kept{X}(x)` hold `Dynamic` (`core.jl:584–587`), and `compiled_for` makes it `Compiled` (`attributes.jl:155`).
   - One worker per key and argument signature: yes. The barrier allocates (finding 4).
3. **Layouts:**
   - B is sound now, with one submodule (finding 5).
   - A is sound only once E-153 shows ND precompiles and runs wrapped. It has not run.
   - The include order allows B without moving code.
4. **Steps:** a function at a time, near enough. S2 and S3 each touch three functions of one concern. The checks are minutes: P is ND's precompile, R about a minute (KernelAbstractions' CPU kernels may make it longer than 30 s), W one session. The coverage gaps are in finding 7.
5. **Criteria and E-152:** measurable and cheap. A failure changes the plan, as §3 says. Add the direct tests and step b (finding 3). Cite E-151 (finding 8).
6. **Gaps and conflicts:**
   - the shared working tree with P3, a blocker (finding 1);
   - the dry-run numbers, against CLAUDE.md's rule that a copy of a number names its home (finding 8);
   - the registration order (finding 9).
   
   No conflict with the meta plan's ground rules: nothing Planned is needed, and pushback goes to the log. The P3 plan's §8 and §1.4 item 6 agree with layout A's workload change.
