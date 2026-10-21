# W-34: what TraitWorld and the facts mode need for the SciML restructure

Status: **adopted; W-34** ([the work queue](../record/todo.md)); revised 2026-10-21 after [its review](../reviews/2026-10-21-w34-sciml-prerequisites.md), whose 21 findings the coordinator accepted. Not normative. No Julia ran for it: the facts it states about TraitWorld are by reading, and E-156 probes them.

The user (2026-10-21): "Tackle anything that is needed in TraitWorld/Facts to validate the Fable strategy." The standing rules for the port ([the meta plan](2026-10-21-networkdynamics-port.md), "Ground rules"; [decision log §4](../record/decisions.md), "Orthogonal features for the port"):
- the port does not change the design;
- agents may add highly orthogonal features the port needs;
- existing designs and features change only by the user's decision: such a need becomes an open issue;
- a Planned part of a reference that the work really needs is implemented first: the work pauses, and the part becomes a work item.

**Inputs.** The SciML exploration ([`../explorations/sciml-as-traits.md`](../explorations/sciml-as-traits.md): the moves 0–5 of §4, the pushback PB-A to PB-J of §5) with the user's correction that DiffEq.jl's solvers are an open set ([the porting guideline, B6](../intro/porting.md#b6-case-study-scimls-architecture-as-traits)); [the pushback log](../explorations/ndport-pushback.md) (W34-1, P4-1 to P6-5); the references' Planned parts and Deviations; [the work queue](../record/todo.md); [the open issues](../open-issues.md); TraitDifferentialEquations (TDE) at fbb9bd8 (`src/ODECore.jl`, `src/TraitDifferentialEquations.jl`); [the meta plan](2026-10-21-networkdynamics-port.md) and [the traits plan](2026-10-21-ndport-traits.md). The build for every experiment below: julia-1.13 2943086604 (W-33: constant propagation crosses from plain code into facts code, [facts §6.3](../reference/facts.md#63-calls-between-the-modes)), TraitWorld f06b82d.

## Summary

- **Most of what the route needs is Implemented.** Traits with operations, fields and parameters; `Callable` bounds on struct parameters; kept values in fields and vectors; families by the type owner's own methods; stakeholders' typed methods; shared `where` variables between bounds; strict mode; joint owners; constant propagation across the modes.
- **Move 1 runs today in form B.** TDE keeps the right-hand side at two struct parameters bounded by `Callable`, one at the plain signature and one at the library's duals; Rodas5 uses the second. W-29 and W-30 make it one parameter, a tidier form, not a prerequisite. SciML's chunk chosen per problem is entered at `init` (§1.2).
- **Form A** (the model dispatched as a `Dynamic` trait object with abstract buffers) is optional. It weakens the signature check, and for a parametric model each call takes open issue 49's path. It waits for the user's decision on open issue 49.
- **Moves 2 and 3 need no TraitWorld work first.** A family without a block, by the type owner's own methods, avoids traits T-5 and T-57. The block forms are a convenience (W-37).
- **L-3 is on move 3's main path in SciML's ownership:** CommonSolve owns `solve`, `init` and `solve!`. A route within the design exists (typed methods on the core's own types, forwarding to functions the core owns). The study of L-3 is W-36, beside E-159.
- **One gap is outside the design:** an algorithm trait cannot name its integrator per problem (W34-1). Open issue 51, with six options; the recommendation is a driver bounded by both traits at shared parameters, which checks the link's parameters at every call, with no change.
- **Validation is five experiments, E-156 to E-160,** outside SciML: probes (minutes), then one prototype per move in TDE and small packages beside it. E-161 is form A's, after open issue 49.
- **The NetworkDynamics port meanwhile:** the Graph step's G3, the P4/P6 merge, and step 3; step 4 (`ODERHS`) after E-157.

## 0. The route with the open-set correction

| Move | What | Changed by the correction |
|---|---|---|
| 0 | Wrap by facts (done: E-153, E-155) | no |
| 1 | The right-hand side at a declared signature; the problem as a trait | no |
| 2 | Callbacks and the integrator view as traits; callbacks out of the integrator's type | the integrator interface is a trait every solver implements (`Integrator{U, T, P} <: IntegratorView{U, T, P}`) |
| 3 | The algorithms as an open set; the front end's body in its owner | yes: `ODEAlgorithm` is a trait each solver package implements for its own types; `init` stays a typed method; the driver is bounded |
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
| Constant propagation from plain code into facts code ([facts §6.3](../reference/facts.md#63-calls-between-the-modes)) | Implemented (julia-1.13 2943086604) | for plain callers of a wrapped package (P6-1) | the P4/P6 merge confirms it on the workload (§4) |
| Concrete evaluation across the modes | Open (open issue 52) | no | — |
| Extensions that rewrite a wrapped core's facts at load (P6-3) | Implemented as designed (followed, with a warning) | no | the attribution at the inside-out track's check J |

### 1.2 Move 1: the right-hand side

**Form B, the main form** (the exploration's, B6's, and TDE's): the problem keeps the user's function at struct parameters bounded by `Callable`, which name the problem's other parameters ([traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait), §5.8). `Dynamic` by `Callable`'s default, `compiled_for(f)` for the caller who wants the solver compiled per function. Every call is checked against the declared signature, and the result asserted. A model type with behaviour of its own implements the problem trait itself (TDE's `LorenzProblem`); a callable model (`Network`) enters form B unchanged.

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| A function at two bounded struct parameters, each one field, the function entered at each (`ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}, D <: Callable{DualSig{P, N}, Nothing}}`) | §7.4, §5.8 | Implemented (TDE: Rodas5 calls `prob.fd` at duals) | yes | — |
| The same as one parameter bounded by a tuple | §3.7, §7.5 | Planned: W-29, W-30, W-31 | no: tidier | — |
| A dual chunk chosen per problem by the algorithm | open issues §2 item 10 | Open | for SciML's Rosenbrock | within the design: the problem keeps the user's function plain beside the kept one ([principled traits §10.3](../explorations/ndport-principled-traits.md#103-kept-values-hide-the-users-object)); `init` enters it at a struct parameter of the integrator whose bound names the integrator's chunk. E-157 tests it |
| In SciML: `ODEFunction` has no parameter for `u`'s or `p`'s type | §7.4 (the bound names the struct's other parameters) | — | yes | the bounded parameters sit on the problem or the integrator, which have `uType`, `tType`, `P`; `ODEFunction` keeps the plain function. E-157 builds this split |
| A Jacobian when given, otherwise by duals | §3.2 | Implemented | yes (Rodas) | `jac!` an operation of the problem trait with a default; `ODEFunction`'s own method branches on `f.jac === nothing` (folded per member). A subtrait `ODEJacobian` stays for model types that declare one (a conditional family over "`TJ` is not `Nothing`" is not expressible) |
| A default whose body names the trait's parameter | §3.2 | Deviation T-2 | no: `eltype(u)` works | W-37 |
| The problem trait with a model's own `rhs!`; the problem's type independent of the function (`Dynamic`) | §6.3, §7.4 | Implemented (TDE) | yes | E-157 |
| A model type of the trait world is `Compiled` at a bound | §6.3 | Implemented | — | E-156's model types live in a plain module. NetworkDynamics' `Network` holds users' functions, so it is not of the trait world |
| `Trajectory{U, T}`: move 5's trait (§1.6), folded in here | §3.1 | Implemented | yes | E-157 check 6 |
| A per-call cost: a `Dynamic{Callable}` call | evidence §2 | Implemented (3.95 ns, no allocation for `Vector` arguments) | yes | E-157 measures per call |
| A non-isbits immutable argument (`NamedTuple` `p`, a `SubArray` state) is boxed per call | lowering §12, §13 (by reading) | — | yes | E-157 adds a `NamedTuple` `p` |
| A `Callable` entered by an untyped call at a typed entry | open issue 43, L-36 | Deviation | per problem, not per step | watch |
| `f(du, u, p, t)` within six arguments | T-51 | Deviation, not met | no | — |

**Form A, optional:** the problem's `f` a struct parameter bounded by a trait `ODERHS`, under `@default_with_dynamic_self`, with `rhs!(f::ODERHS, du::AbstractVector, u::AbstractVector, p, t)::Nothing`.
- **Declared without parameters.** `ODERHS{P}` cannot be implemented by `ODEFunction`: nothing in its type defines `P`, and a type conforming at every `P` is not offered (§3.4, §4.7). A `P` parameter on `ODEFunction` only to state it would be a hidden type parameter (open issue 54).
- **What it loses:** the check of `p`'s and the buffers' types; only `du isa AbstractVector` and the `Nothing` result are checked.
- **What it would buy:** a model called at duals without entering a second signature.
- **Its cost, by reading:** an operation on a `Dynamic` value is a split, then the table. For a concrete type declared by the one-line form that is a probe and an indirect call (2.5–18.5 ns, evidence §2). For a family member (every `ODEFunction{…}`, a `Network{…}`, a `ChainModel{G}`) each call opens through the family's registry (`_conf_family`): open issue 49's 304 bytes and a dynamic call, some 100 ns by reading, six to seven calls per Tsit5 step.
- **So form A waits for open issue 49,** which is on its path by construction. Then E-161.

**Verdict.** Move 1 needs nothing new: Tsit5 and Rosenbrock run in form B today; SciML's per-problem chunk is entered at `init`.

### 1.3 Move 2: callbacks and the integrator view

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `IntegratorView{U, T, P}` with fields (`u`, `t`, `dt`, `p`, `u_modified`) and operations (`add_tstop!`, `terminate!`, an interpolation `interp!` for continuous callbacks) | §3.1, §3.3 | Implemented (TDE: fields only) | yes | E-158 |
| An integrator family declared by its owner outside the trait's module, without a block, by the owner's own methods (`@implement IntegratorView ODEIntegrator{…} where {…}`) | §4.7 | Implemented, unprobed outside the trait's module | yes | E-156 P1b |
| The same with a block | §4.7 | Deviations T-5 (`S{T} where {T}`: not a family in any module), T-57 (`A where {A <: S}`: refused outside the trait's module) | no: the no-block form | W-37 |
| A family over a type with its own `getproperty`, every declared field mapped | §3.3, §4.4 | Implemented, unprobed for a family | yes (SciML's `DEIntegrator` has one) | E-156 P9 |
| `u` writable in one integrator family and `const` in another | open issues §2 item 5 | Open | no | `@const u` (contents written in place); `set_u!` an operation |
| `Callback{U, T, P}` with `condition` and `affect!` taking `Dynamic{IntegratorView{U, T, P}}`; `Vector{Callback{U, T, P}}` in the integrator | §3.1, §7.1, §7.2 | Implemented unparametrized (TDE); parametric unprobed | yes | E-156 P8 |
| Callbacks built before `U`, `T`, `P` are known, entered at `init` | §7.2, §7.5 | a parametric record whose fields are typed `Callable{…U, T, P…}` (`Kept{Callable{…}}` in a trait module), as TDE's `FunctionCallback` unparametrized; unprobed with parameters. A bounded struct parameter cannot do it: no field names `U`, `T`, `P` outside the bound (§7.4; lowering §13.2) | yes | E-156 P8 |
| A trait object passed to a `Callable`'s argument declared `Dynamic{X}` | L-31 | Deviation | no | make the view explicitly, as TDE does |
| A callback reading `integ.p` at its own type | §7.1; open issues §2 item 16 | typed when `P` is in the view's parameters; the downcast is Open | no | `P` stays in the key |

**Verdict.** Nothing new, in one package or across packages.

### 1.4 Move 3: the algorithms as an open set; the front end in its owner

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `ODEAlgorithm` (`alg_order(a)::Int`, `isadaptive(a)::Bool = true`), implemented by each solver package for its own parametric types, without a block | §4.7, §10.1 | Implemented, unprobed outside the trait's module | yes | E-156 P1b |
| `Integrator{U, T, P} <: IntegratorView{U, T, P}` (`step!`, `done`, …), implemented by each solver's integrator family | §3.6, §4.7 | parametric subtrait unprobed | yes | E-156 P5 |
| `init(prob, alg::Tsit5)`: a typed method naming the solver's type | §10.1, §5.5 | Implemented (a stakeholder's method) | yes | — |
| CommonSolve owns `solve`, `init` and `solve!`. A bounded `CommonSolve.solve!(integ::Integrator)` by SciMLBase is a non-owner's first bounded method of that shape | §5.5 allows; lowering L-3 refuses | Deviation L-3, on the main path | yes, in SciML's ownership | route within the design: typed methods on the core's own types (`CommonSolve.solve!(integ::DEIntegrator) = _drive!(integ)`, `CommonSolve.init(prob::AbstractODEProblem, alg) = __init(prob, alg)`), forwarding to functions the core owns; the core declares the bounded shapes (`_drive!(integ::Integrator, …)`, `__init(prob::ODEProblemTrait, alg)`), which solver packages then extend for their own types. W-36 studies retiring L-3 |
| The link from an algorithm to its integrator per problem | §3.4 "Not offered"; open issues §2 item 6 | Not in the design (W34-1) | its parameters can be checked within the design | **open issue 51** |
| A non-conforming integrator at the driver | §5.5 | `MethodError` with a hint naming the bound (T-22); `TraitBoundError` only for parameter values that disagree (§5.1) | yes | E-159 check 3 |
| Strict mode with no joint owners | §10.2, §10.3 | Implemented (strict mode a prototype; F-6) | yes | E-159, with a negative control |
| The default algorithm by the extension-trait form (a bounded method on CommonSolve's `solve` with a trait the umbrella owns) | §5.5 | Deviation L-3 | no: the umbrella's own function validates the open set | W-36 |
| Associated constants (`alg_order`) | §3.4 "Not offered"; PB-B | operations with declared results stand in | yes | — |

**Verdict.** Nothing new to validate. L-3 has a route; retiring it (W-36) serves the extension-trait form and a simpler spelling of the driver.

### 1.5 Move 4: symbolic access as traits

| Capability | Reference | Status | Needed | Action |
|---|---|---|---|---|
| `IndexProvider` (`sym` untyped; `Union{Nothing, Int}` results) and `ValueProvider{U, P}` | §3.1; open issues §2 item 7 (decided half) | Implemented | yes | E-160 |
| SII's container chain (integrator → `f` → `sys`) | §4.3: forwarding does not chain | the rule | no | the outer types implement by their own methods that read the field, declared as no-block families (§1.3); pushback W34-2 |
| Forwarding for a whole family | §4.7 Planned; T-7 | Planned | no: helpful | — |
| `observed(ip, sym)` returning a closure | §5.8: `Callable` results Planned | Planned | no: `::Function` stands in, a run-time site per call | a work item only if E-160 or the workload finds it hot |
| The `getproperty` sugar in the package's ordinary module; trait code reads declared fields | traits §2, §3.3 | Implemented | yes | E-160 |
| The sugar inside the trait module, called from plain code | facts §6.3 | Implemented (W-33) | yes, as the contrast | E-160 check 4 |

### 1.6 Move 5: the solution as a trajectory

`Trajectory{U, T}` (§3.1) and a solution keeping its problem as a kept value (§7.2) are Implemented. TDE's `ODESolution{T}` has no model axis already. One check in E-157 (check 6) covers the move.

### 1.7 Not needed to validate the route

Trait casts (Optional, §6.9, PB-C: a default operation covers the solver's question); the checked downcast (open issues §2 item 16, PB-E: `P` stays in the key); T-51; `Callable` with keywords, T-48, T-39 (front ends stay plain, PB-H); forwarding for a family (T-7); a copying layout for GPU (open issues §2 item 3); AD tags as part of a key (open issues §2 item 9).

## 2. The prototypes, in order

- **Where:** TDE on a branch `w34`; new packages under `TraitDifferentialEquations/examples/`, as `LorenzModels` is. Scripts and logs in `experiments/w34-sciml/`, whose README keeps the dated results. TDE's main changes only when a form is adopted.
- **Settings for every row:** julia-1.13 2943086604, TraitWorld f06b82d (or the commit the outcome names), the product setting, strict mode off unless stated, TDE's load order (the package, then the example packages, then the script), two runs unless stated, the machine's load noted in the log. Quick checks of minutes; a timing is a regression check, not a measurement.
- **Results:** where a prototype touches TDE's solvers, TDE's `RESULT` lines (`scripts/session.jl`) stay equal bit for bit.
- **The lock:** one Julia job at a time, niced.

The order:
1. **E-156,** the probes (minutes). Open issue 49 goes to the user at the same time (it is on form A's path).
2. **E-157,** move 1 in form B, with move 5's check.
3. **E-158,** move 2.
4. **E-159,** move 3, with a CommonSolve stand-in; W-36's study beside it.
5. **E-160,** move 4.
6. **W-37** (the block forms), and **W-38** if E-156 confirms P1c.
7. **E-161,** form A, only after the user decides open issue 49.

Then the first real SciML step: the NetworkDynamics port's step 4 (`ODERHS`, §4), with its own plan and row.

### 2.1 E-156: probes of the forms the moves need

One script per probe in `experiments/w34-sciml/probes/`, each printing PASS, FAIL or ERROR with the exception and the predicted outcome. Model types are defined in a plain module.

| Probe | Form | Predicted (by reading) |
|---|---|---|
| P1a | a family with a block, `@implement X S{T} where {T} begin … end`, inside and outside the trait's module | not a family in either: a call reports "conforms to none" (T-5) |
| P1a′ | `@implement X A where {A <: S} begin … end` outside the trait's module | refused by the precheck (T-57); inside: works |
| P1b | the family without a block, `S{T} where {T}` and `A where {A <: S}`, declared by the type's owner outside the trait's module, the methods defined before | works; members checked at first use |
| P1c | the same declared by a third package that owns neither the trait nor `S` | accepted: the no-block joint-form branch runs no ownership check (§4.9 says refused). If confirmed: a new T- row, W-38 |
| P5 | a parametric subtrait `Integrator{U, T, P} <: IntegratorView{U, T, P}`; a bound on the subtrait beats the supertrait | works |
| P7 | a default whose body names the trait's parameter | `UndefVarError` (T-2) |
| P8 | a parametric callback record with fields `Callable{Tuple{U, T, Dynamic{IntegratorView{U, T, P}}}, Bool}`; `Vector{Callback{U, T, P}}` as a field of an integrator; a callback reading `integ.p` typed | works |
| P9 | a no-block family over a mutable type with its own `getproperty`, every declared field mapped, operations by existing methods | works |
| P10 | a struct parameter bounded by a trait under `@default_with_dynamic_self`: two model types from a plain module give one problem type | works |
| P11 | the driver `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P}) where {U, T, P}`: a mismatched pair raises `TraitBoundError` | works (open issue 51, option (a+)) |
| P12 | `init` as an operation of the problem trait, `init(prob::ODEProblemTrait{U, T, P}, alg)::Integrator{U, T, P}`; the driver opens the `Dynamic` result once with `compiled_for` | unprobed (option (d)) |
| P13 | form A: an operation with abstract buffers on a `Dynamic` value at `Float64` and at duals, for a concrete one-line model and for a family member; nanoseconds and allocations per call | the concrete model: no allocation; the family member: allocates (open issue 49) |

> | E-156 | W-34: do the forms the SciML moves rely on work in TraitWorld as the references say ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.1)? Probes P1a–P13, each with its prediction by reading: families with and without a block, inside and outside the trait's module, and by a third package (T-5, T-57, the ownership check of the no-block family); a parametric subtrait; a trait parameter in a default (T-2); a parametric callback record of `Callable` fields and a vector of parametric callbacks; a family over a type with its own `getproperty`; a trait-bounded struct parameter under `@default_with_dynamic_self` with model types from a plain module; a driver bounded by two traits at shared parameters; `init` as an operation with a trait-typed result; form A's per-call cost for a concrete and a family-member model. julia-1.13 2943086604, TraitWorld f06b82d, product setting, strict mode off, each probe in a fresh session after TraitWorld, one run, the machine's load noted. Measures TraitWorld's forms (neither interop nor idiomatic code). **Would change the plan:** a probe failing where its reference says Implemented (a deviation row; the fix a work item, and the move that needs it waits); P1b failing (moves 2 and 3 wait for W-37); P1c accepted (a new T- row, W-38); P10 giving two problem types (move 1's latency claim fails: a deviation row); P11 failing (open issue 51's recommended option is not available); P13's concrete model allocating (form A is not viable at all). | proposed | `experiments/w34-sciml/probes/` | — | `experiments/w34-sciml/README.md` |

### 2.2 E-157: move 1 in form B, with move 5's check (TDE)

Build, on TDE's branch `w34`:
- SciML's split of record and problem: TDE's own plain `ODEFunction{F, TJ, TMM}` (the user's function, an optional Jacobian, a mass matrix) and the problem, which enters `f` at its bounded parameters (plain and dual signatures) as `ODEProblem` does today.
- `jac!` an operation of the problem trait with a default; the given Jacobian used when `TJ` is not `Nothing`.
- The chunk per problem: a second path where the problem keeps `f` plain beside the kept one, and `init` enters it at the integrator's dual signature with a chunk chosen from the state's length.
- A callable model `ChainModel{G}` (`G` stands for NetworkDynamics' graph type), defined in a plain module, entering form B unchanged.
- `Trajectory{U, T}` with `ODESolution` conforming.

Checks:
1. TDE's `RESULT` lines unchanged (Tsit5, Rodas5, `Float32`, a gradient), on both chunk paths.
2. Per `rhs!` call, in a loop of a few seconds: nanoseconds and allocations, `Dynamic` against `compiled_for`; with a `NamedTuple` `p` as well as a `Vector`.
3. Allocations per step of a Tsit5 solve (a 40-state chain, 1,000 steps).
4. A second `ChainModel{G}` and a new plain function: no new CodeInstance of the solver's functions under `Dynamic`.
5. An `f` that returns `du`: refused at its first call (`TypeError`) under `Dynamic`; at first use under `compiled_for`.
6. A helper bounded by `Trajectory` is compiled once per key; the solution's type is the same for two models.

What it buys, if it holds: a new model or function compiles nothing in the solver, with the signature checked. In the workload a new graph type compiles 17.7 s in the whole stack (E-154); SciML's share of that is not measured, and the port's step 4 measures it.

> | E-157 | W-34, move 1 in TDE, form B ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.2): with SciML's split of a plain `ODEFunction` record and a problem keeping the function at bounded `Callable` parameters, (1) are TDE's `RESULT` lines unchanged, also with the chunk entered at `init`? (2) What does an `rhs!` call cost and allocate, `Dynamic` against `compiled_for`, with a `Vector` and a `NamedTuple` `p`? (3) How many allocations per Tsit5 step (40 states, 1,000 steps)? (4) Does a new model type or function compile no CodeInstance of the solver's functions? (5) Is an `f` returning `du` refused at its first call? (6) Is a `Trajectory` helper compiled once per key, with one solution type for two models? julia-1.13 2943086604, TraitWorld f06b82d, product setting, strict mode off, TDE's load order, two runs, the machine's load noted. Measures interop (library trait code calling plain functions). **Would change the plan:** (1) a difference (a bug); (2) a `Dynamic` call above ~10 ns or allocating with `Vector` arguments (a performance issue, open issues §4 item 35, before step 4); (2) a `NamedTuple` `p` allocating per call (a lowering deviation row; SciML's `p` is often immutable); (3) allocations per step (the step's path names the cause); (4) new solver code (the bounded parameter does not erase: a deviation row); (6) code per model (the key carries more than `U, T`: a deviation row). | proposed | TDE branch `w34`; `experiments/w34-sciml/m1/` | — | `experiments/w34-sciml/README.md` |

### 2.3 E-158: move 2, callbacks and the integrator view (TDE)

Build:
- `IntegratorView{U, T, P}` with the fields of §1.3 and the operations `add_tstop!`, `terminate!`, `interp!(i, out, t)`; Tsit5's and Rodas5's integrators conform as no-block families.
- `Callback{U, T, P}`; the user-facing `DiscreteCallback(cond, affect!)` keeps the plain functions; `init` builds a parametric record with `Callable` fields at `(U, T, P)`; the integrator keeps `Vector{Callback{U, T, P}}`.
- Stage 2, after stage 1 passes: a scalar continuous callback, its bisection on `interp!` shared verbatim with the control.
- The control: the same solver with typed callbacks (`baselines/PlainODE`).

Checks:
1. Event times and states equal to the control, bit for bit.
2. A new callback closure compiles nothing in the driver; one integrator type for two callback sets.
3. In a callback, `integ.p` is typed `P`, and a write to its contents reaches the solve.
4. A callback type without `affect!` is refused at `@implement`.
5. Per step with two callbacks: nanoseconds and allocations against the control.

> | E-158 | W-34, move 2 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.3): with callbacks as `Callback{U, T, P}` kept in a vector of the integrator, entered at `init` as records of `Callable` fields, and seeing the integrator as `Dynamic{IntegratorView{U, T, P}}` with operations, (1) are event times and states equal to a typed control (PlainODE) bit for bit, discrete first, then a scalar continuous callback? (2) Does a new callback compile nothing in the driver, with one integrator type for two callback sets? (3) Is `integ.p` typed in a callback? (4) Is a callback type without `affect!` refused at `@implement`? (5) What does a step with two callbacks cost and allocate against the control? julia-1.13 2943086604, TraitWorld f06b82d, product setting, strict mode off, TDE's load order, two runs, the machine's load noted. Measures idiomatic trait code. **Would change the plan:** (1) a difference (a bug); (2) driver code per callback (the record or the vector carries the callback's type: a deviation row); (5) a cost per callback per step beyond the split's numbers (evidence §2: a performance issue, open issues §4 item 35, before move 2 reaches SciML). | proposed | TDE branch `w34`; `baselines/PlainODE`; `experiments/w34-sciml/m2/` | — | `experiments/w34-sciml/README.md` |

### 2.4 E-159: move 3, the solvers as an open set (TDE split)

Build:
- `examples/MiniCommonSolve`: a plain stand-in that owns `solve`, `init` and `solve!`, as CommonSolve does.
- `ODECore` holds the traits (`ODEProblemTrait`, `ODEAlgorithm`, `IntegratorView`, `Integrator`, `Callback`), typed methods of the stand-in's functions on its own types forwarding to functions it owns (§1.4's route), and the bounded shapes `__init(prob::ODEProblemTrait, alg)` and `_drive!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P})`.
- Rodas5 moves out of TDE into `examples/TraitRodas`: its algorithm and integrator implemented as no-block families from outside `ODECore`, its `__init` a method of `ODECore`'s declared shape. No edit in `ODECore` for it.
- The negative control: `examples/FrontEndElsewhere`, a package that defines the front end's body for `ODECore`'s abstract problem type on the stand-in's `solve`, as DiffEqBase does.
- The default algorithm: (i) an umbrella package's own function `solve_default(prob)`; (ii) the extension-trait form, a bounded `MiniCommonSolve.solve(prob::DefaultSolvable)` by the umbrella.

Checks:
1. TDE's `RESULT` lines unchanged, Rodas5 included, from its own package.
2. Strict mode on: the census finds no pirate in `ODECore`, TDE, `TraitRodas` or the umbrella, with no `@joint_owners`; it finds `FrontEndElsewhere`'s methods.
3. An integrator without `step!` refused at its first use (`ImplementError` naming `step!`); an integrator that conforms to nothing raises `MethodError` with the hint at the driver; one whose parameters differ from the problem's raises `TraitBoundError` (option (a+) of open issue 51).
4. The default algorithm: (i) works; (ii) refused today (L-3).
5. The Tsit5 steady state per step unchanged by the split.

> | E-159 | W-34, move 3 in TDE ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.4): with a plain stand-in owning `solve`, `init`, `solve!` (as CommonSolve), and Rodas5 moved into its own package (algorithm and integrator as no-block families from outside the core, `__init` at a shape the core declares), (1) are TDE's `RESULT` lines unchanged? (2) With strict mode on and no `@joint_owners`, does the census find no pirate in the core, TDE, the Rodas package and the umbrella, and find the negative control's front-end methods? (3) Is an integrator without `step!` refused at its first use, a non-conforming one met by `MethodError` with the hint, and one at other parameters than the problem's by `TraitBoundError`? (4) Does the umbrella's own default function work, and is the extension-trait form refused (L-3)? (5) Is a Tsit5 step's cost unchanged by the split? julia-1.13 2943086604, TraitWorld f06b82d, product setting, strict mode on for (2) and off otherwise, the load order: TDE, the stand-in, the Rodas package, the umbrella, the negative control last; one run, the machine's load noted. Measures idiomatic trait code. **Would change the plan:** (1) a difference (a bug); (2) a pirate in the restructured packages, or none in the negative control (the census is blind: a facts or traits deviation row); (3) a missing method accepted (a T- row), or the mismatch not refused (open issue 51's (a+) unavailable); (4)(i) failing (the route of §1.4 does not hold: the open set waits for W-36); (5) a regression (the route costs per step: a lowering row). | proposed | TDE branch `w34`; `examples/MiniCommonSolve`, `examples/TraitRodas`, `examples/FrontEndElsewhere`; `experiments/w34-sciml/m3/` | — | `experiments/w34-sciml/README.md` |

### 2.5 E-160: move 4, symbolic access as traits

Build: a small package `examples/TraitIndexing` with `IndexProvider` and `ValueProvider` as in [the traits plan §1.4](2026-10-21-ndport-traits.md); a model with named states and parameters; TDE's problem, solution and integrator implementing them by their own methods (no-block families); getters `getsym(provider, sym)` in the trait module; the sugar `sol.ps[:σ]` once in TDE's ordinary module and once inside the trait module.

Checks:
1. Values equal to direct field reads.
2. Two model types share the getter's code (CodeInstances per index shape, not per provider).
3. Trait code reads a declared field at its offset (`code_typed`).
4. A plain caller of the sugar infers the field's type in both layouts: outside the trait module by plain constant propagation, inside by W-33's.

> | E-160 | W-34, move 4 ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §2.5): with symbolic access as `IndexProvider`/`ValueProvider`, (1) are values equal to direct reads, (2) is a getter compiled per index shape and not per provider, (3) does trait code read declared fields at their offsets, (4) does a plain caller of the `getproperty` sugar infer the field's type with the sugar in the ordinary module (move 4's layout) and inside the trait module (W-33's case)? julia-1.13 2943086604, TraitWorld f06b82d, product setting, strict mode off, TDE's load order, one run, the machine's load noted. Measures idiomatic trait code (1–3) and plain callers of a wrapped package (4). **Would change the plan:** (2) code per provider (the attribute rule's application rechecked); (4) a union inside the trait module (W-33's acceptance missed a case: a facts row); (4) a union outside (a bug in the layout, not in the design). | proposed | `examples/TraitIndexing`; TDE branch `w34`; `experiments/w34-sciml/m4/` | — | `experiments/w34-sciml/README.md` |

### 2.6 E-161: form A of move 1 (after open issue 49)

Only after the user decides open issue 49. Form A (§1.2) beside form B in E-157's setting.

> | E-161 | W-34, move 1 in form A ([the W-34 plan](../plans/2026-10-21-w34-sciml-prerequisites.md) §1.2, §2.6), after open issue 49's decision: with the model kept `Dynamic` at a bounded parameter of trait `ODERHS` (no parameters; abstract buffers), (1) are TDE's `RESULT` lines unchanged, Rodas5's dual calls through the trait? (2) What does an `rhs!` call cost and allocate for a concrete model and a family member, against form B? (3) What does the solver check of the user's function, against form B? julia-1.13 at the build that carries open issue 49's decision, its TraitWorld commit, product setting, strict mode off, TDE's load order, two runs, the machine's load noted. Measures idiomatic trait code. **Would change the plan:** (2) a family member allocating per call (form A stays optional); form A within form B's cost and checking enough for the user (form A offered beside form B in the guideline). | proposed | TDE branch `w34`; `experiments/w34-sciml/m1a/` | — | `experiments/w34-sciml/README.md` |

## 3. New work items and open issues: drafts

For the coordinator to enter. None is entered by this plan.

### 3.1 Work items

> | W-36 | **A bounded method of a new shape on another package's function, by a package that owns a trait the bound names** (traits §5.5; lowering L-3). In SciML's ownership CommonSolve owns `solve`, `init` and `solve!`, so move 3's driver meets it; a route exists (the W-34 plan §1.4). Study an encoding of the entry that no two packages overwrite in their images and that is no pirate by the letter; build it if it leaves existing features as they are; otherwise open issue 53. | the user (2026-10-21): "Tackle anything that is needed in TraitWorld/Facts to validate the Fable strategy." | queued (beside E-159) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §1.4; `../reference/lowering.md` L-3 |
>
> | W-37 | **The block forms of a family, and a trait's parameter in a default:** `@implement X S{T} where {T} begin … end` lowered as a family (traits T-5); `@implement X A where {A <: S} begin … end` outside the trait's module (T-57: the precheck evaluates the receiver under its `where`, or tests ownership of the bound's base type); the trait's parameters in a default's body (T-2); and every E-156 probe that fails where the reference says Implemented. A convenience for the moves: the no-block family is the route. | the user (2026-10-21), as W-36 | queued (after E-159) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §1.3, §2.1; `../reference/traits.md` §4.7, §3.2 |
>
> | W-38 | *(Only if E-156's P1c confirms it.)* **The ownership check of a family without a block:** the joint form by fields (`_implement_projection`'s family branch) defines the implementation without `_check_implementation`, so a third package's declaration is accepted (traits §4.9 refuses it). A new T- row first. | the user (2026-10-21), as W-36 | waiting (E-156) | `../plans/2026-10-21-w34-sciml-prerequisites.md` §2.1, P1c |

Changes to existing rows:
- **W-34:** in progress: the inventory adopted; E-156 next.
- **W-29, W-30, W-31:** unchanged. Not on W-34's path: form B runs with two bounded parameters.

### 3.2 Open issue 51 (ready to paste)

> 51. **An algorithm's integrator per problem** (W-34; pushback W34-1; the SciML exploration's PB-A; [the porting guideline, B6](intro/porting.md#b6-case-study-scimls-architecture-as-traits); [the W-34 plan](plans/2026-10-21-w34-sciml-prerequisites.md) §1.4). DiffEq.jl's solvers are an open set: each solver package adds algorithm types, and `init(prob, alg)` builds an integrator whose type depends on the algorithm and on the problem's state, element and parameter types together. Rust writes `trait Algorithm<P: Problem> { type Integrator: Integrator<P>; fn init(&self, p: &P) -> Self::Integrator; }`. The design has no trait generic over another trait's implementer ([traits §3.4](reference/traits.md#34-parameters-and-associated-types), "Not offered"; §2 item 6). Today each end is checked at its `@implement` (the integrator's family at its first use), and the link at the first call: an integrator that conforms to nothing meets `MethodError` with a hint naming the bound at the driver ([traits §5.5](reference/traits.md#55-dispatch-types-first-then-traits)). Options:
>     - (a) Keep the first-call check. As an orthogonal tool, a solver package may check in its tests or precompile workload that `init`'s inferred result for listed problem types conforms to `Integrator`. No change.
>     - (a+) The driver bounded by both traits at shared parameters: `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P}) where {U, T, P}`. A shared `where` variable requires equal values, so an integrator at other parameters than the problem's raises `TraitBoundError` at every call ([traits §5.1](reference/traits.md#51-bounds)). No change.
>     - (b) `init` as an operation of `ODEAlgorithm` with a trait-typed result, `init(a::ODEAlgorithm, prob)::Integrator`: a `Dynamic` result ([traits §6.2](reference/traits.md#62-how-plain-values-enter-the-trait-world)), whose parameters the algorithm's trait cannot name. One barrier per solve if the driver opens it with `compiled_for`; plain callers of `solve` get an uninferred result. No change.
>     - (c) Input parameters on traits, or associated types that depend on another trait's implementer: the Rust form, checked at `@implement`. A change to traits §3.1 and §3.4 and to the lowering.
>     - (d) `init` as an operation of the problem trait, which has the parameters: `init(prob::ODEProblemTrait{U, T, P}, alg)::Integrator{U, T, P}`, its implementation dispatching to the solver packages' typed methods (`alg_init(alg::Tsit5, prob)`, a stakeholder's). The link, parameters included, is a declared contract, checked at each return. One `Dynamic` result per solve; the driver opens it once with `compiled_for`, or each `step!` pays the split (and open issue 49 for a family-member integrator). No change.
>     - (e) The configured algorithm as a joint family: each solver package owns `Tsit5For{U, T, P}`, the algorithm configured for a problem's associated types, implementing `ODEAlgorithmFor{U, T, P}` whose operation `init(a::ODEAlgorithmFor{U, T, P}, …)::Integrator{U, T, P}` names the trait's own parameters. A typed `configure(alg::Tsit5, prob)` makes the value. Rust's `Algorithm<P>`, checked per member at its first use; one more type per solver. No change.
>
>     The agent's recommendation: (a+) now, since it costs nothing and checks the link's parameters at every call; (d) probed (E-156, P12) as the closest to Rust's checked link without a change; (c) kept with §2 item 6 until a second case needs it.

### 3.3 Open issue 53 (only if W-36 ends there)

> 53. **A non-owner's first bounded method of a shape** (W-36; [lowering L-3](reference/lowering.md#18-deviations); [traits §5.5](reference/traits.md#55-dispatch-types-first-then-traits)). TraitWorld's entries are methods at `Any`, one per function and shape. An entry that a package adds to another package's function names no type it owns, and two packages adding the same shape would overwrite each other's entry in their images. SciML meets it at CommonSolve's `solve`, `init` and `solve!`. Options: (a) wait for traits in the type system (W-27), where the compiler generates entries; (b) the function's owner declares the shape, so its entry exists (CommonSolve would depend on TraitWorld); (c) one shared entry per function and shape, owned by TraitWorld, created by the first package that needs it and found by the others (W-36 names how images keep it); (d) the route of the W-34 plan §1.4: typed methods on the core's own types, forwarding to functions the core owns.

### 3.4 Pushback entries (for the log)

- **W34-2. SII's container chain against "forwarding does not chain"** (traits §4.3). `symbolic_container(integrator)` is `integrator.f`, whose container is `f.sys`. The outer types implement `IndexProvider` by their own methods that read the field, as no-block families. Blocks: no.
- **W34-1, corrected:** a non-conforming integrator meets `MethodError` with the hint at the driver, not `TraitBoundError`; the parameters of the link can be checked by option (a+).

### 3.5 Stale copies for the adoption commit

- [B6](../intro/porting.md#b6-case-study-scimls-architecture-as-traits): "`solve!` refuses an integrator that does not conform (`TraitBoundError`)" (§3.4 above); "Needs the tuple of `Callable`s for implicit methods' dual signatures (W-29)" in move 1 (form B runs with two parameters); PB-D's summary line.
- [The pushback log](../explorations/ndport-pushback.md), W34-1: "raises `TraitBoundError`".
- [The exploration](../explorations/sciml-as-traits.md), move 1's "Measured by proxy": it puts the ~390 ns crossing into a family member (an entry's crossing, P4-1) beside the 3.95 ns `Callable` call (form B's) and concludes "tens of nanoseconds" per step; the first does not apply to form B. Also "Needs: the tuple of `Callable`s … (W-29)" and PB-D.

### 3.6 Choices for the meta plan's list (mine)

38. **The prototypes live in TDE on a branch `w34`** and in packages under `TraitDifferentialEquations/examples/`, not in SciML and not in TDE's main, until a form is adopted.
39. **Form B is move 1's form;** form A is tried only after open issue 49 is decided (E-161).
40. **SciML's chunk per problem is entered at `init`,** with the function kept plain beside the kept one in the problem.
41. **A Jacobian when given is a branch in `ODEFunction`'s own `jac!`,** a default otherwise; the subtrait `ODEJacobian` only for model types that declare one.
42. **Callbacks are entered at `init`** into parametric records of `Callable` fields; the user-facing callback structs keep plain functions.
43. **`u` is `@const` in the view,** written in place, with `set_u!` an operation.
44. **The open set is shown by moving Rodas5 out of TDE,** with a negative control for the census, and a stand-in for CommonSolve so that L-3 bites where it would in SciML.
45. **The integrator's link is checked by option (a+) of open issue 51** in the prototypes, pending the user's decision.
46. **Move 5 is one check of E-157,** not an experiment of its own.
47. **Not taken for W-34:** trait casts, the checked downcast, T-51, keyword `Callable`s, `Callable` results, forwarding for a family (§1.7), until a prototype or the workload needs one.

## 4. The NetworkDynamics port meanwhile

The meta plan's state: P4 steps 1 and 2 done (E-152, E-154); P6 done (E-155); traits T-58 and T-59 retired (TraitWorld f06b82d); W-33 done (julia-1.13 2943086604). In order, each under the lock, between W-34's jobs:

1. **The Graph step's G3** ([the graph plan](2026-10-21-ndport-graph.md)): the feed-forward check bounded by `GraphInterface{V}`, on TraitWorld f06b82d, in `pkgs/NetworkDynamics-p4`. Its check: the `ff` network, the test subset, one workload session; E-154's outcome gets a dated addendum. Small; first.
2. **The P4/P6 merge** (meta plan choice 35): due (P6 done, P4 step 2 done). A fresh `env_merged` and `depot-merged`, new `port` branches, TraitWorld f06b82d, julia-1.13 2943086604; strict mode off, then on. The steady-state reference: P4 after open issue 48's fix (step d 33.1–41.2 ms). Expected beside it: P6-1's cost gone for SciMLBase's plain callers, by W-33. P5's measurement plan is due here too.
3. **P4 step 3, `VertexDynamics`/`EdgeDynamics`** ([the traits plan §4](2026-10-21-ndport-traits.md#4-the-order-after-the-first-step)): NetworkDynamics' own idiomatic trait code; nothing from W-34. Its plan and review as usual.
4. **P4 step 4, `ODERHS`:** move 1 in the real stack, in form B, after E-157. Tsit5 and Rodas5P both: the dual signatures run with two bounded parameters, the chunk entered at `init`. Its own plan, review and row. It measures SciML's share of a new graph type's 17.7 s (E-154).
5. **Steps 5–7 of the traits plan** are moves 4, 5 and 2 in the real stack. Each waits for its prototype (E-160, E-157 check 6, E-158).
6. **Move 3 in the real stack** restructures SciML's front end. The user chose to pursue the restructure (open issue 50's answer); meta plan choice 28 (no code edits in SciML for pirates) holds until move 3's own plan, after E-159, proposes the edit.

## 5. What would change this plan

- E-156 finds a failing form that a move needs and the reference does not cover: an open issue, and the move waits.
- P1b fails: moves 2 and 3 wait for W-37.
- E-157's per-call cost or allocations miss their bounds: step 4 waits for the performance work it names.
- The user picks option (c) of open issue 51: a design change and a work item of its own; (d) or (e): E-159's driver changes shape.
- W-36 ends in open issue 53: the extension-trait form waits for the user; the validation does not.
