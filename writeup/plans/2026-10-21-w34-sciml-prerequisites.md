# W-34: what TraitWorld and the facts mode need for the SciML restructure

Status: **proposal; W-34. Reviewed ([`../reviews/2026-10-21-w34-sciml-prerequisites.md`](../reviews/2026-10-21-w34-sciml-prerequisites.md): three blockers); to be revised before it is adopted.** Its draft IDs W-35…W-37 collide with the queue (W-35 is taken): renumber at the revision. ([the work queue](../record/todo.md)). Not normative. Written 2026-10-21. No Julia ran for it: a full build (W-33) held the lock.

The user (2026-10-21): "Tackle anything that is needed in TraitWorld/Facts to validate the Fable strategy." The standing rules for the port ([the meta plan](2026-10-21-networkdynamics-port.md), "Ground rules"; [decision log §4](../record/decisions.md), "Orthogonal features for the port"):
- the port does not change the design;
- agents may add highly orthogonal features the port needs;
- existing designs and features change only by the user's decision: such a need becomes an open issue;
- a Planned part of a reference that the work really needs is implemented first: the work pauses, and the part becomes a work item.

**Inputs.** The SciML exploration ([`../explorations/sciml-as-traits.md`](../explorations/sciml-as-traits.md): the moves 0–5 of §4, the pushback PB-A to PB-J of §5) with the user's correction that DiffEq.jl's solvers are an open set ([the porting guideline, B6](../intro/porting.md#b6-case-study-scimls-architecture-as-traits), "The solvers are an open set"); [the pushback log](../explorations/ndport-pushback.md) (W34-1, P4-1 to P6-5); the references' Planned parts and Deviations ([traits](../reference/traits.md), [lowering](../reference/lowering.md), [facts](../reference/facts.md), [compiler](../reference/compiler.md)); [the work queue](../record/todo.md) (W-21 to W-34); [the open issues](../open-issues.md) §1–§3; TraitDifferentialEquations' `src/ODECore.jl` and `src/TraitDifferentialEquations.jl` (main, fbb9bd8); [the meta plan](2026-10-21-networkdynamics-port.md) and [the traits plan](2026-10-21-ndport-traits.md) (§1.4, §1.7, §4). TraitWorld at f06b82d.

## Summary

- **Most of what the route needs is Implemented.** Traits with operations, fields and parameters; `@default_with_dynamic_self`; a struct parameter bounded by a trait; kept values in fields and vectors; families over a bare variable; stakeholders' typed methods; strict mode; joint owners.
- **One deviation blocks two moves.** A family implementation with a block, declared by the type's owner outside the trait's module, defines nothing a call finds or is refused ([traits T-57](../reference/traits.md#17-deviations)). In SciML that is every integrator family (move 2) and every parametric algorithm type (move 3). It is the first work item, W-35.
- **One Planned part is needed for move 4:** forwarding for a whole family ([traits §4.7](../reference/traits.md#47-families), T-7). Work item W-37.
- **The tuple of `Callable`s (W-29) may leave the critical path.** Rosenbrock's Jacobian calls the right-hand side at dual numbers. If `ODERHS`'s operation takes abstract buffers and the model is dispatched as a `Dynamic` value ("form A", §1.2), the dual call needs no tuple. If the record keeps the function at a `Callable` bound ("form B", the exploration's), it needs W-29. The first prototype decides.
- **One gap is outside the design:** an algorithm trait cannot name its integrator per problem (W34-1, PB-A). Open issue 51 for the user, with options.
- **One deviation limits a convenience, not the validation:** the default algorithm through a bounded method on a foreign function (the extension-trait form) meets [lowering L-3](../reference/lowering.md#18-deviations). Work item W-36, a study first; open issue 52 only if the study finds no encoding that leaves existing features as they are.
- **Validation is six cheap experiments,** E-156 to E-161: probes of the forms in TraitWorld (minutes), then one prototype per move in TraitDifferentialEquations (TDE) and small packages beside it, not in SciML. The real SciML step that follows is the NetworkDynamics port's step 4 (`ODERHS`), with the form E-157 picks.
- **The NetworkDynamics port meanwhile:** the Graph step's G3 (traits T-59 is fixed), then the P4/P6 merge, then step 3 (`VertexDynamics`/`EdgeDynamics`), which needs nothing from W-34. Step 4 waits for E-157.

## 0. The route with the open-set correction

The exploration's moves, as the guideline's B6 states them:

| Move | What | Changed by the correction |
|---|---|---|
| 0 | Wrap by facts (done: E-153, E-155) | no |
| 1 | The right-hand side as a trait `ODERHS`; the function kept at a bound | no |
| 2 | Callbacks and the integrator view as traits; callbacks out of the integrator's type | the integrator interface is a trait every solver implements (`Integrator{U, T, P} <: IntegratorView{U, T, P}`) |
| 3 | The algorithms as an open set; the front end's body in its owner | yes: `ODEAlgorithm` is a trait each solver package implements for its own types; `init` stays a typed method; `solve!(integ::Integrator)` is bounded |
| 4 | Symbolic access as traits; the `getproperty` sugar plain | no |
| 5 | The solution as a trajectory | no |

## 1. The inventory, move by move

Status words:
- **Implemented:** the reference says so, and a test or a demonstrator uses the form.
- **Implemented, unprobed:** the reference says so, and no test uses this form. E-156 probes it.
- **Planned, Optional, Open:** the reference's status.
- **Deviation:** a row of a Deviations table.
- **Not in the design:** the references do not offer it. Then: orthogonal (agents may add it) or a change (an open issue).

"Needed" means needed to validate the move, not to finish SciML.

### 1.1 Move 0: wrap by facts (done)

| Capability | Status | Needed | Action |
|---|---|---|---|
| Constant propagation from plain code into facts code ([facts §6.3](../reference/facts.md#63-calls-between-the-modes), F-17) | Planned; W-33 being built | for plain callers of a wrapped package (P6-1), and for move 4's plain side | none beyond W-33 |
| Extensions that rewrite a wrapped core's facts at load (P6-3) | Implemented as designed (followed, with a warning) | no | the attribution at the inside-out track's check J |

### 1.2 Move 1: the right-hand side as a trait

Two forms, to be decided by E-157:
- **Form A:** `ODERHS{P}` with `rhs!(f::ODERHS{P}, du::AbstractVector, u::AbstractVector, p::P, t)::Nothing`, `@default_with_dynamic_self`. The problem's `f` is a struct parameter bounded by `ODERHS`. A user's model (a `Network`) conforms by its own `rhs!`. `ODEFunction` conforms as a family; its `rhs!` calls its typed `f.f`. The solver is compiled once per `(U, T, P)`, whatever the model; the model's own method is compiled per model, at any element type, duals included.
- **Form B** (the exploration's §4 move 1): `ODERHS{T, P}` with `Vector{T}` buffers; the record keeps the plain function at `Callable{RHSSig{P, T}, Nothing}`, as TDE's `ODEProblem` does. A dual call needs the function at a second signature.

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| A trait with an operation and a declared result; `@default_with_dynamic_self` | traits §3.1, §6.3 | Implemented | yes | — |
| A struct parameter bounded by a trait (not a `Callable`): the problem's type the same for every model | §7.4 | Implemented, unprobed (TDE bounds by `Callable` only) | yes | E-156 P10 |
| `ODEFunction` as a family over a partly fixed type, `A where {A <: ODEFunction{true}}`, in the trait's own module | §4.7 | Implemented, unprobed | yes | E-156 P4 |
| A user's type as a family with stated parameter values, `@implement ODERHS{Vector{Float64}} N where {N <: Network}` | §4.6, §4.7 | Implemented, unprobed (the traits plan §1.4: "to be checked") | yes | E-156 P3 |
| Subtraits with parameters, `ODEJacobian{P} <: ODERHS{P}`, `ODEMassMatrix <: ODERHS` | §3.6 | Implemented, unprobed with parameters | yes (Rodas) | E-156 P5 |
| A default `jac!` whose body names the trait's parameter | §3.2 | Deviation T-2 (`UndefVarError`) | helpful; `eltype(u)` works around it | W-35 |
| An operation with abstract buffers on a `Dynamic` value, called at `Float64` and at duals (form A) | §3.1, §6.8 | Implemented, unprobed at duals | yes (form A) | E-156 P6 |
| A function kept at two signatures in one struct parameter (form B) | §3.7, §7.4, §7.5 | Planned: W-29, then W-30, W-31 | only for form B | pause item if E-157 picks form B |
| A dual chunk chosen by the algorithm | open issues §2 item 10 | Open | only for form B | within the design: the problem keeps the user's function plain beside the kept one ([principled traits §10.3](../explorations/ndport-principled-traits.md#103-kept-values-hide-the-users-object)); `init` enters it at the signatures the algorithm's chunk gives (a bound naming the integrator's parameters, §7.4) |
| A type conforming at two element types (form B for a user's type) | §3.4, "Not offered" | Not in the design | no, if form A holds | form A avoids it; otherwise open issue (with §2 item 6) |
| The per-step cost: a split per `rhs!` on a `Dynamic` model | facts §9 | Implemented | yes | measured in E-157 |
| A typed call of a family member builds its trait object per call (304 bytes) | open issue 49 | waiting for the user | only if the step calls through a typed family member | watch in E-157: a per-step allocation raises 49's priority |
| A `Callable` entered by an untyped call at a typed entry | open issue 43, L-36 | Deviation | per problem, not per step | watch |
| `f(du, u, p, t)` within six arguments | T-51 | Deviation, not met | no | — |

**Verdict.** Tsit5 needs nothing Planned. Rosenbrock needs nothing Planned under form A, and W-29 under form B.

### 1.3 Move 2: callbacks and the integrator view

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `IntegratorView{U, T, P}` with fields (`u`, `t`, `dt`, `p`, `u_modified`) and operations (`add_tstop!`, `terminate!`, `set_proposed_dt!`, and an interpolation operation for continuous callbacks) | §3.1, §3.3 | Implemented (TDE: fields only) | yes | E-158 |
| An integrator family declared by its owner outside the trait's module (OrdinaryDiffEqCore's `ODEIntegrator`, SciMLBase's trait) | §4.7 | Deviation T-57 (no implementation a call finds, or refused) | yes, for SciML's shape | **W-35** |
| A family over a type with its own `getproperty`, every declared field mapped | §3.3, §4.4 | Implemented, unprobed for a family | yes | E-156 P9 |
| `u` writable in one integrator family and `const` in another | open issues §2 item 5 | Open | no | route: `@const u` (contents written in place); `set_u!` an operation |
| `Callback{U, T, P}` with `condition` and `affect!` taking `Dynamic{IntegratorView{U, T, P}}` | §3.1, §7.1 | Implemented unparametrized (TDE); parametric unprobed | yes | E-156 P8 |
| `Vector{Callback{U, T, P}}` as a field of the integrator, in a trait module | §7.2 | Implemented, unprobed with parameters | yes | E-156 P8 |
| Callbacks built by the user before `U`, `T`, `P` are known, entered at `init` at the integrator's signatures | §7.4 (a bound naming the struct's other parameters) | Implemented | yes | E-158 |
| A trait object passed to a `Callable`'s argument declared `Dynamic{X}` | L-31 | Deviation | no | make the view explicitly, as TDE does |
| A callback reading `integ.p` at its own type | §7.1; open issues §2 item 16 | typed when `P` is in the view's parameters; the downcast is Open | no | `P` stays in the key |

**Verdict.** In one package (TDE), move 2 needs nothing new. In SciML's shape (the view in SciMLBase, the integrator in OrdinaryDiffEqCore), it needs T-57 retired.

### 1.4 Move 3: the algorithms as an open set; the front end in its owner

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `ODEAlgorithm` (`alg_order(a)::Int`, `isadaptive(a)::Bool = true`) implemented by each solver package for its own parametric types, as a family | §4.7, §10.1 | Deviation T-57 | yes | **W-35** |
| `Integrator{U, T, P} <: IntegratorView{U, T, P}` (`step!`, `done`, `add_tstop!`, …) implemented by each solver's integrator family | §3.6, §4.7 | T-57; parametric subtrait unprobed | yes | W-35; E-156 P5 |
| `init(prob, alg::Tsit5)`: a typed method of the owner's function, naming the solver's type | §10.1, §5.5 | Implemented (a stakeholder's method) | yes | — |
| The plain front end `solve(prob, alg) = solve!(init(prob, alg))`; `solve!(integ::Integrator)` bounded, entered from plain code | §5.1, §6.2 | Implemented | yes | E-159 |
| The link from an algorithm to its integrator per problem, checked at `@implement` | §3.4 "Not offered"; open issues §2 item 6 | Not in the design (W34-1, PB-A) | no: the first-call check suffices to validate | **open issue 51** |
| Strict mode with no joint owners: no pirate by the letter in the core | §10.2, §10.3 | Implemented (strict mode a prototype; F-6) | yes | E-159 counts it |
| The default algorithm by the extension-trait form: a bounded method on CommonSolve's `solve` with a trait the umbrella owns | §5.5 | Deviation L-3 (only the function's owner adds a bounded method of a new shape) | no: the umbrella's own function validates the open set | **W-36**; open issue 52 if needed |
| A default algorithm over more than four solvers as `Vector{Dynamic{…}}` | facts §9; PB-J | Implemented (a table beyond four; C-14) | no | — |
| Associated constants (`alg_order`) | §3.4 "Not offered"; PB-B | operations with declared results stand in | yes | — |
| `init` as an operation returning `Kept{Integrator}` | §3.1 (results of a kept form not stated) | unprobed | only for open issue 51's option (b) | E-156 P11 |

**Verdict.** The open set needs T-57 retired. The checked link between algorithm and integrator is the user's question (open issue 51); the validation runs with the first-call check.

### 1.5 Move 4: symbolic access as traits

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `IndexProvider` (`sym` untyped; `Union{Nothing, Int}` results) and `ValueProvider{U, P}` | §3.1; open issues §2 item 7 (decided half) | Implemented | yes | E-160 |
| Forwarding for a family: the problem, solution and integrator families forwarding to their model field | §4.7 | Planned (T-7; open issues §2 item 4) | yes; one declaration per member stands in | **W-37** |
| SII's `symbolic_container` chain (integrator → `f` → `sys`) | §4.3: "Forwarding does not chain" | the rule | no | the outer types implement by methods that read the field; pushback W34-2 (§3.3) |
| `observed(ip, sym)` returning a closure | §5.8: results that are `Callable`s are Planned | Planned | no: `::Function` stands in, a run-time site per call | a work item only if E-160 or the workload finds it hot |
| The `getproperty` sugar in the package's ordinary module; trait code reads declared fields | traits §2, §3.3 | Implemented | yes | E-160 |
| A plain caller of the sugar inferring the field's type | facts §6.3, F-17 | Planned; W-33 | yes, for the plain side | E-160 after W-33 |

### 1.6 Move 5: the solution as a trajectory

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `Trajectory{U, T}` (`times`, `state`, `at`) | §3.1, §3.4 | Implemented | yes | E-161 |
| The solution keeping its problem as a kept value (`prob::ODEProblemTrait` in a trait module) | §7.2 | Implemented | yes | E-161 |

Nothing new.

### 1.7 Not needed to validate the route

Recorded so that no one builds them for W-34: trait casts (Optional, §6.9, PB-C: a default operation covers the solver's question); the checked downcast (open issues §2 item 16, PB-E: `P` stays in the key); T-51 (move 1's function has four arguments); `Callable` with keywords, T-48, T-39 (front ends stay plain, PB-H); a copying layout for GPU (open issues §2 item 3); AD tags as part of a key (open issues §2 item 9).

## 2. The prototypes, in order

Each prototype is small, outside SciML, and states what it shows and what it buys.
- **Where:** TDE on a branch `w34` (it holds the problem, callback and integrator traits already); new solver and indexing packages under `TraitDifferentialEquations/examples/`, as `LorenzModels` is. Scripts and logs in `experiments/w34-sciml/` (its README holds the dated results). TDE's main changes only when the user adopts a form ("the demonstrators follow the design").
- **Settings for every row:** the product setting; the patched Julia at W-33's build; TraitWorld at the commit named in the row; strict mode off unless stated; one or two runs; quick checks of minutes, no benchmark rounds. A timing is a regression check, not a measurement.
- **Results:** every prototype keeps TDE's `RESULT` lines (`scripts/session.jl`) bit for bit where it touches TDE's solvers, and compares a new path against a plain control in the same session.
- **The lock:** one Julia job at a time, after W-33's build releases it.

The order, cheapest and most decisive first:
1. E-156, the probes (TraitWorld only; minutes). Feeds W-35.
2. E-157, move 1 (TDE). Decides form A or B, and so whether W-29 is on the path.
3. E-161, move 5 (TDE; small).
4. E-158, move 2 (TDE, one package).
5. W-35 (TraitWorld), then E-159, move 3 (TDE split, a third solver package).
6. W-37 (TraitWorld) and W-33, then E-160, move 4.

Then the first real SciML step: the NetworkDynamics port's step 4 (`ODERHS`, §4), with its own plan and row.

### 2.1 E-156: probes of the forms the moves need

Build: one script per probe in `experiments/w34-sciml/probes/`, each a few lines, each printing PASS, FAIL or ERROR with the exception.

| Probe | Form | Expected |
|---|---|---|
| P1 | a family with a block declared by the type's owner outside the trait's module: `@implement X S{T} where {T} begin … end` and `@implement X A where {A <: S} begin … end` | fails (T-57) |
| P2 | the same two forms inside the trait's module | passes by T-57's text; T-5 says the first is not lowered. One of the two rows is stale |
| P3 | a family with stated values over a bare variable, `@implement ODERHS{Vector{Float64}} N where {N <: Net}` | passes |
| P4 | a family over a partly fixed type, `A where {A <: Fn{true}}` | passes |
| P5 | a parametric subtrait `ODEJacobian{P} <: ODERHS{P}`; a bound on the subtrait beats the supertrait | passes |
| P6 | `rhs!` with abstract buffers on a `Dynamic{ODERHS{Vector{Float64}}}`, called at `Float64` and at ForwardDiff duals: results, the caller's `code_typed` after the call, allocations | passes; no allocation |
| P7 | a default whose body names the trait's parameter | fails (T-2) |
| P8 | `Vector{Callback{U, T, P}}` as a field of a struct in a trait module; a plain callback pushed; `condition` called with a `Dynamic{IntegratorView{U, T, P}}`; `integ.p` typed in the callback | passes |
| P9 | a family over a mutable type with its own `getproperty`, every declared field mapped, operations served by existing methods of the trait module's own functions | passes |
| P10 | a struct parameter bounded by `ODERHS` under `@default_with_dynamic_self`: two model types give one problem type | passes |
| P11 | an operation declared to return `Kept{Integrator}` (only for open issue 51's option (b)) | unknown |

Registry row:

> | E-156 | W-34: do the forms the SciML moves rely on work in TraitWorld ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.1)? Eleven probes, P1–P11: families with blocks outside and inside the trait's module (T-57, T-5), a family with stated values, a family over a partly fixed type, a parametric subtrait, an operation with abstract buffers on a `Dynamic` value at `Float64` and at duals, a parametric callback trait in a vector field, a family over a type with its own `getproperty`, a trait-bounded struct parameter under `@default_with_dynamic_self`, a kept form as an operation's result. Product setting, strict mode off, one run, TraitWorld f06b82d. Measures TraitWorld's forms (neither interop nor idiomatic code). **Would change the plan:** a probe failing where its reference section says Implemented (a deviation row; the fix joins W-35); P2 contradicting T-5 or T-57 (the stale row corrected); P6 failing or allocating (form A of move 1 is not viable; W-29 is on the critical path); P10 giving two problem types (move 1's latency claim fails: a deviation row, W-35); P11 failing (open issue 51's option (b) is not available without a change). | proposed | `experiments/w34-sciml/probes/` | — | `experiments/w34-sciml/README.md` |

### 2.2 E-157: move 1, the right-hand side as a trait (TDE)

Build, on TDE's branch `w34`:
- SciML's split of record and problem: TDE's own `ODEFunction{F, TJ, TMM}` (a plain function, an optional Jacobian, a mass matrix), and the problem holding it at a parameter bounded by `ODERHS`.
- Form A: `ODERHS{P}` as in §1.2; `ODEJacobian{P} <: ODERHS{P}` with `jac!`; `ODEMassMatrix`. `ODEFunction` conforms as a family. Rodas5's Jacobian by duals through `rhs!` on the `Dynamic` model.
- A user's type `ChainModel{G}`: a callable struct whose parameter `G` stands for NetworkDynamics' graph type, conforming by its own `rhs!`.
- Form B as the control: TDE's current `ODEProblem` (two `Callable` parameters today; the tuple after W-30).

Checks:
1. TDE's `RESULT` lines unchanged under both forms (Tsit5, Rodas5, `Float32`, a gradient).
2. A second `ChainModel{G}` (a new `G`) and a new plain function: no new CodeInstance of the solver's functions (`tsit5_solve`, `rodas5_solve`, the steps).
3. A `rhs!` that returns `du`: refused at `@implement` for `ChainModel`, at first use for an `ODEFunction` member.
4. The steady state of a Tsit5 solve (Lorenz; a 40-state chain), three repetitions in one session: form A against `compiled_for` and against form B; allocations per step.
5. Rodas5 at duals: form A without W-29.

What it buys, if it holds: a new model or graph type compiles nothing in the solver (in the workload a new graph type compiles 17.7 s, E-154); the signature checked; no hand-written wrapper.

Registry row:

> | E-157 | W-34, move 1 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.2): can the right-hand side be a trait `ODERHS` with the model kept `Dynamic` at the problem's bounded parameter (form A, abstract buffers), and does it match the `Callable` record (form B)? (1) Are TDE's `RESULT` lines unchanged in both forms? (2) Does a new model type or function compile no CodeInstance of the solver's functions? (3) Is a `rhs!` returning `du` refused (at `@implement`; at an `ODEFunction` member's first use)? (4) Is a Tsit5 solve's steady state within 10 % + 1 ms of `compiled_for`, with no allocation per step? (5) Does Rodas5's Jacobian at duals run under form A without W-29? Product setting, strict mode off, two runs, TraitWorld after E-156 (commit named in the outcome). Measures idiomatic trait code (a user's model type) and interop (an `ODEFunction` calling a plain function), each named. **Would change the plan:** (1) a difference (a bug); (2) new solver code under form A (the bounded parameter does not erase: deviation row, W-35); (4) an allocation per step (open issue 49 or 43 on the step's path: raised to the user as blocking move 1); (5) form A failing at duals (W-29 becomes a pause item for move 1, and a type at two element types goes to the user with open issues §2 item 6); form A slower than form B beyond the margin (form B, with W-29). | proposed | TDE branch `w34`; `experiments/w34-sciml/m1/` | — | `experiments/w34-sciml/README.md` |

### 2.3 E-161: move 5, the solution as a trajectory (TDE)

Build: `Trajectory{U, T}` in `ODECore`; `ODESolution` conforms and keeps its problem in a field `prob::ODEProblemTrait` (a kept value); a plotting-like helper `points(s::Trajectory{Vector{Float64}, Float64}, i::Int)::Vector{NTuple{2, Float64}}`.

Checks: `RESULT` lines unchanged; `typeof(sol)` the same for two model types; the helper compiled once per key.

> | E-161 | W-34, move 5 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.3): with the solution a `Trajectory` that keeps its problem as a kept value, (1) are TDE's `RESULT` lines unchanged, (2) is the solution's type the same for two model types, (3) is a helper bounded by `Trajectory` compiled once per key? Product setting, strict mode off, one run. Measures idiomatic trait code. **Would change the plan:** (2) negative (a kept field still carries the model's type: deviation row); (3) code per model (the key carries more than `U, T`: deviation row). | proposed | TDE branch `w34`; `experiments/w34-sciml/m5/` | — | `experiments/w34-sciml/README.md` |

### 2.4 E-158: move 2, callbacks and the integrator view (TDE, one package)

Build:
- `IntegratorView{U, T, P}` with the fields of §1.3 and the operations `add_tstop!`, `terminate!`, `interp!(i, out, t)`; Tsit5's and Rodas5's integrators conform as families.
- `Callback{U, T, P}`: a discrete callback, and a vector continuous callback that finds its root by bisection on `interp!`.
- The user-facing `DiscreteCallback(cond, affect!)` and `VectorContinuousCallback(cond, affect!, n)` keep the plain functions. `init` enters them into records whose `Callable` bounds name `(U, T, P)`; the integrator keeps `Vector{Callback{U, T, P}}`.
- The control: the same solver with the callbacks as typed parameters of the integrator (in `baselines/PlainODE`).

Checks:
1. Event times and states equal to the control, bit for bit.
2. A new callback closure compiles nothing in the driver; the integrator's type is the same for two callback sets.
3. In a callback, `integ.p` is typed `P`, and a write to its contents reaches the solve.
4. A callback type without `affect!` is refused at `@implement`.
5. The steady state with two callbacks against the control, three repetitions.

> | E-158 | W-34, move 2 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.4): with callbacks as `Callback{U, T, P}` kept in a vector of the integrator, entered at `init`, and seeing the integrator as `Dynamic{IntegratorView{U, T, P}}` with operations, (1) are event times and states equal to a typed control (PlainODE) bit for bit, discrete and vector continuous? (2) Does a new callback compile nothing in the driver, with one integrator type for two callback sets? (3) Is `integ.p` typed in a callback? (4) Is a callback type without `affect!` refused at `@implement`? (5) Is the steady state with two callbacks within 10 % + 1 ms of the control? Product setting, strict mode off, two runs. Measures idiomatic trait code. **Would change the plan:** (1) a difference (a bug); (2) driver code per callback (the record or the vector carries the callback's type: deviation row); (5) outside the margin (the split per callback per step costs more than the design's numbers, evidence §2: a performance issue, open issues §4 item 35, before move 2 reaches SciML). | proposed | TDE branch `w34`; `baselines/PlainODE`; `experiments/w34-sciml/m2/` | — | `experiments/w34-sciml/README.md` |

### 2.5 E-159: move 3, the solvers as an open set (TDE split; after W-35)

Build:
- `ODECore` holds the traits (`ODERHS` or `ODEProblemTrait`, `ODEAlgorithm`, `IntegratorView`, `Integrator`, `Callback`), the plain front end `solve(prob, alg) = solve!(init(prob, alg))`, the function `init`, and the bounded `solve!(integ::Integrator)`.
- A new package `examples/TraitBS3` (an adaptive Bogacki–Shampine solver): an algorithm type `BS3{L}` and an integrator `BS3Integrator{U, T, P}`, each a family implemented from outside `ODECore`, and `init(prob, alg::BS3)`. No edit in `ODECore`.
- The control: the same BS3 written plainly in `baselines/PlainODE`.
- The default algorithm: (i) an umbrella package's own function `solve_default(prob)`; (ii) the extension-trait form: the umbrella owns `DefaultSolvable`, implements it for the core's problem type, and adds `solve(prob::DefaultSolvable)` to the core's `solve`.

Checks:
1. TDE's `RESULT` lines unchanged; BS3 equal to its plain control bit for bit.
2. Strict mode on: the census finds no pirate in `ODECore`, TDE or `TraitBS3`, with no `@joint_owners`.
3. An integrator family without `step!` is refused at its first use (`ImplementError` naming `step!`); an `init` returning a type that does not conform raises `TraitBoundError` at `solve!` naming `Integrator` (W34-1's gap, documented).
4. The default algorithm: (i) works; (ii) is refused today (L-3), accepted after W-36.
5. The steady state of a Tsit5 solve unchanged by the split.

> | E-159 | W-34, move 3 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.5): can a package outside the core add a solver (`TraitBS3`: `ODEAlgorithm` and `Integrator` implemented as families from outside, `init` a typed method) with no edit in the core, under strict mode and without joint owners? (1) Are TDE's `RESULT` lines unchanged, and BS3 equal to its plain control bit for bit? (2) Does the census find no pirate with no `@joint_owners`? (3) Is an integrator without `step!` refused at its first use, and a non-conforming `init` result refused at `solve!` (`TraitBoundError`)? (4) Does the umbrella's default work as its own function, and is the extension-trait form refused (L-3) before W-36 and accepted after? (5) Is the Tsit5 steady state unchanged by the split (10 % + 1 ms)? Product setting; strict mode on for (2), off otherwise; one run; TraitWorld after W-35. Measures idiomatic trait code. **Would change the plan:** (1) a difference (a bug); (2) a pirate (the front end's split between owner and solver is wrong: the plan's §1.4 revised); (3) a missing method accepted (a T- deviation row); (4)(ii) still refused after W-36 (open issue 52); (5) a regression (the bounded `solve!` from plain code costs per step: a lowering deviation row). | proposed | TDE branch `w34`; `examples/TraitBS3`; `baselines/PlainODE`; `experiments/w34-sciml/m3/` | — | `experiments/w34-sciml/README.md` |

### 2.6 E-160: move 4, symbolic access as traits (after W-33; W-37 for the family form)

Build: a small package `examples/TraitIndexing` with `IndexProvider` and `ValueProvider` as in [the traits plan §1.4](2026-10-21-ndport-traits.md); a model with named states and parameters; TDE's problem, solution and integrator conforming (the problem by `by f`; the families per member until W-37, then by `by f where`); getters `getsym(provider, sym)` in the trait module; the sugar `sol.ps[:σ]` in TDE's ordinary module.

Checks:
1. Values equal to direct field reads.
2. Two model types share the getter's code (CodeInstances per index shape, not per provider).
3. A trait caller reads the declared field at its offset (`code_typed`).
4. A plain caller of the sugar infers the field's type after W-33, and the union before.

> | E-160 | W-34, move 4 ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.6): with symbolic access as `IndexProvider`/`ValueProvider` and the `getproperty` sugar in the ordinary module, (1) are values equal to direct reads, (2) is a getter compiled per index shape and not per provider, (3) does trait code read declared fields at their offsets, (4) does a plain caller of the sugar infer the field's type on W-33's build (and the union on the build before)? Product setting, strict mode off, one run. Measures idiomatic trait code (1–3) and plain callers of a wrapped package (4). **Would change the plan:** (2) code per provider (the provider is not `Dynamic` where the plan assumes: the attribute rule's application rechecked); (4) the union after W-33 (W-33's acceptance missed a case: a facts deviation row). | proposed | `examples/TraitIndexing`; TDE branch `w34`; `experiments/w34-sciml/m4/` | — | `experiments/w34-sciml/README.md` |

## 3. New work items and open issues: drafts

For the coordinator to enter, each in one commit with this plan's adoption. None is entered by this plan.

### 3.1 Work items

> | W-35 | **The family and default forms the SciML moves need:** a family implementation with a block, declared by the type's owner outside the trait's module (traits T-57); T-5 checked against T-57 and the stale row corrected; a trait's parameter in a default's body (T-2); and every probe of E-156 that fails where the reference says Implemented. Tests in TraitWorld; the rows retired with their expected-failure checks flipped. | the user (2026-10-21): "Tackle anything that is needed in TraitWorld/Facts to validate the Fable strategy." | queued (after W-33's build; E-156 first) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §1.3, §1.4, §2.1; `../reference/traits.md` §4.7, §3.2 |
>
> | W-36 | **A bounded method of a new shape on another package's function, by a package that owns a trait the bound names** (traits §5.5; lowering L-3): study an encoding of the entry that no two packages overwrite and that is no pirate by the letter; build it if it leaves existing features as they are; otherwise open issue 52. Needed by move 3's default algorithm in the extension-trait form, not by the validation. | the user (2026-10-21), as W-35 | queued (after E-159's (4)(i)) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §1.4; `../reference/lowering.md` L-3 |
>
> | W-37 | **Forwarding for a whole family,** `@implement X S{T} by f where {T}` (traits §4.7, Planned; T-7; open issues §2 item 4). Needed by move 4 (problems, solutions and integrators forwarding to their model). | the user (2026-10-21), as W-35 | queued (before E-160's family form) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §1.5; `../reference/traits.md` §4.7 |

Changes to existing rows:
- **W-34:** status "in progress: the inventory written (this plan); E-156 next".
- **W-29, W-30, W-31:** unchanged. A note in W-29's links: on W-34's critical path only if E-157 picks form B.

### 3.2 Open issues

> 51. **An algorithm's integrator per problem** (W-34; pushback W34-1; the SciML exploration's PB-A; [the porting guideline, B6](intro/porting.md#b6-case-study-scimls-architecture-as-traits)). DiffEq.jl's solvers are an open set: each solver package adds algorithm types, and `init(prob, alg)` builds an integrator whose type depends on the algorithm and on the problem's state, element and parameter types together. Rust writes `trait Algorithm<P: Problem> { type Integrator: Integrator<P>; fn init(&self, p: &P) -> Self::Integrator; }`. The design has no trait generic over another trait's implementer ([traits §3.4](reference/traits.md#34-parameters-and-associated-types), "Not offered"; §2 item 6). Today each end is checked at its `@implement`, and the link at the first call: `solve!` raises `TraitBoundError` for an integrator that does not conform. Options:
>     - (a) Keep the first-call check (B6's form). As an orthogonal tool, a solver package may check in its tests or precompile workload that `init`'s inferred result for listed problem types conforms to `Integrator`. No change to the language.
>     - (b) `init` as an operation of `ODEAlgorithm` with a kept result, `init(a::ODEAlgorithm, prob)::Kept{Integrator}`: one barrier per solve; the result's parameters are not checked, and plain callers of `solve` get an uninferred result. No change to the language if an operation may declare a kept form as its result (E-156, P11).
>     - (c) Input parameters on traits, or associated types that depend on another trait's implementer: the Rust form, checked at `@implement`. A change to traits §3.1 and §3.4 and to the lowering.
>
>     The agent's recommendation: (a) now; (c) kept with §2 item 6 until a second case needs it.

> 52. *(To file only if W-36 ends here.)* **A non-owner's first bounded method of a shape** (W-36; [lowering L-3](reference/lowering.md#18-deviations); [traits §5.5](reference/traits.md#55-dispatch-types-first-then-traits)). TraitWorld's entries are methods at `Any`, one per function and shape. An entry that a package adds to another package's function names no type it owns, and two packages adding the same shape would overwrite each other's entry in their package images. Options: (a) wait for traits in the type system (W-27), where the compiler generates entries; (b) the function's owner declares the shape, so its entry exists (CommonSolve would depend on TraitWorld); (c) one shared entry per function and shape that the first package creates and later packages find, owned by TraitWorld (the study names how images keep it); (d) the umbrella offers its own function (`solve_default(prob)`), and `solve(prob)` without an algorithm keeps a plain method.

### 3.3 Pushback entries (for the log)

- **W34-2. SII's container chain against "forwarding does not chain"** (traits §4.3). `symbolic_container(integrator)` is `integrator.f`, whose container is `f.sys`. A family cannot forward through two fields. The outer types implement `IndexProvider` by methods that read the inner field. Blocks: no.
- **W34-3** *(only if E-157's (5) fails).* A model conforming at two element types (`Float64` and duals) is not offered (traits §3.4); Rosenbrock's Jacobian then waits for W-29.

### 3.4 Choices for the user to review (mine)

1. **The prototypes live in TDE on a branch** and in packages under `TraitDifferentialEquations/examples/`, not in SciML and not in TDE's main, until a form is adopted.
2. **Form A is tried first for move 1,** beside the exploration's form B. Reason: it may take W-29 off the critical path and serve a user's model at duals without a tuple.
3. **Callbacks are entered at `init`,** at the integrator's `(U, T, P)`; the user-facing callback structs keep plain functions. Reason: the user builds callbacks before the state's types are known, and a function is seen through the signatures it entered with (traits §6.5).
4. **`u` is `@const` in the view,** written in place, with `set_u!` an operation (open issues §2 item 5 not needed).
5. **BS3 as the third-party solver:** small, adaptive, explicit, and not in TDE today.
6. **The order of §2,** with move 5 before move 2 because it is small.
7. **Not taken for W-34:** trait casts, the checked downcast, T-51, keyword `Callable`s, `Callable` results (§1.7), until a prototype or the workload needs one.

## 4. The NetworkDynamics port meanwhile

The meta plan's state: P4 steps 1 and 2 done (E-152, E-154); P6 done (E-155); traits T-58 and T-59 fixed (TraitWorld f06b82d); W-33 building. In order, each under the lock, between W-34's jobs:

1. **The Graph step's G3** ([the graph plan](2026-10-21-ndport-graph.md), G3): the feed-forward check bounded by `GraphInterface{V}`, again, on TraitWorld f06b82d, in `pkgs/NetworkDynamics-p4`. Its check: the `ff` network, the test subset, one workload session; E-154's outcome gets a dated addendum. Small; first.
2. **The P4/P6 merge** (meta plan choice 35): due now (P6 done, P4 step 2 done). A fresh `env_merged` and `depot-merged`, new `port` branches, one TraitWorld commit (f06b82d, or W-35's if it has landed), W-33's Julia build; strict mode off, then on. The steady-state reference: P4 after open issue 48's fix (step d 33.1–41.2 ms). Expected beside it: P6-1's cost gone for plain callers with W-33. Its row is the merge's own; P5's measurement plan is due here too.
3. **P4 step 3, `VertexDynamics`/`EdgeDynamics`** ([the traits plan §4](2026-10-21-ndport-traits.md#4-the-order-after-the-first-step)): NetworkDynamics' own idiomatic trait code; it needs nothing from W-34. Its plan and review as usual. It runs while TraitWorld work (W-35) is coded, the lock taken in turn.
4. **P4 step 4, `ODERHS`:** move 1 in the real stack, after E-157 picks the form. Tsit5 first; Rodas5P under form A, or after W-29 under form B ([the traits plan §1.7](2026-10-21-ndport-traits.md#17-planned-parts-and-blocking-deviations-pause-or-route-around) routes around until then). Its own plan, review and row. Its headline: a new graph type compiles nothing in SciML (17.7 s in all today, E-154).
5. **Steps 5–7 of the traits plan** are moves 4, 5 and 2 in the real stack. Each waits for its prototype (E-160, E-161, E-158).
6. **Move 3 in the real stack** restructures SciML's front end. The user chose to pursue the restructure (open issue 50's answer); meta plan choice 28 (no code edits in SciML for pirates) holds until move 3's own plan, after E-159, proposes the edit.

## 5. What would change this plan

- E-156 finds a failing form that a move needs and the reference does not cover: an open issue, and the move waits.
- E-157 picks form B: W-29, W-30 and W-31 move ahead of E-158.
- The user picks option (b) or (c) of open issue 51: move 3's prototype changes shape; (c) is a design change and a work item of its own.
- W-36 ends in open issue 52: the extension-trait form waits for the user; the validation does not.
- W-33's acceptance fails: E-160's (4) and the merge's expectation are void until it is fixed.
