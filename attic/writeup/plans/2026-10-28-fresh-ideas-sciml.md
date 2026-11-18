# Fresh ideas: SciML in the trait world, and the weak points it exposes

Status: **proposal** (2026-10-28, a fresh-eye agent's ideas, Opus; not adopted). Not normative.

The user: "Remember that one purpose of the ports is to identify weak points in the design." And: "The guiding principle should be principled solutions. If a tweak in the trait design can enable a principled solution in the port architecture, that's the most valuable finding we can have."

Read for it: the references (`traits.md`, `facts.md` §1–§2), the porting guide (part 0, B2, B5, B6), TraitDifferentialEquations (TDE, branch `w34` at 6234487: `README.md`, `src/ODECore.jl`), E-156 to E-158 (`experiments/w34-sciml/README.md`), `ndport/README.md`, upstream as cloned in `ndport/pkgs/` (SciMLBase, the OrdinaryDiffEq monorepo with DiffEqBase and the solver sublibraries, DiffEqCallbacks). Then, after forming a view, the exploration (`explorations/sciml-as-traits.md`), the W-34 plan, the lean-core memo §1.3 and open issues §1, §2. No Julia ran for this page. Line numbers are of the files as of 2026-10-28.

## Summary

- **The architecture I propose** keys the solver on a *numerical key*: the algorithm with its cache, the state type, the time type, the linear solver and the AD chunk. Everything a user brings crosses a `Dynamic` position by default: the model, the parameters, the callbacks, the options' functions. This agrees with W-63 and the lean-core memo.
- **Where I differ:** the existing plans design around five rules of the trait language. Each workaround costs code, a copy, or an escape to `Any`. Each rule can be changed in a small, principled way. The five are the main content of this page (§2):
  1. **Generic operations and generic `Callable`s** (a signature with its own `where` variable, chosen per call). One function then serves the plain and the dual element types, every chunk, and nested AD. It retires `rhs_function::Any`, `DualJacobian`, the second bounded parameter, and the need for tuples of `Callable`s in TDE. Julia can do what Rust cannot here (`dyn` with generic methods), because it compiles per signature at the first call. TraitWorld already has the mechanism (T-54's `_erased_at`); W-31 is about to remove it.
  2. **Input parameters** (a type conforming at several values of a parameter). Callbacks of DiffEqCallbacks serve every problem type; a library callback type cannot be written today. `Callable` stops being the one exception.
  3. **Field paths in mappings** (`t => core.t`). A view over another view needs no copy-in and copy-out adapter. It removes `ParamIntegrator`'s synchronization, which grows to a dozen fields with DiffEqCallbacks and is a correctness hazard.
  4. **A kept `Compiled` function is called through code compiled for its type,** not by run-time dispatch. Today `compiled_for` on a callback makes it 20 times slower than `Dynamic` (E-158 finding 5).
  5. **A position whose bound defaults to `Dynamic` has a known key,** so compiling ahead reaches a driver with several trait positions.
- **Open issue 82 gets a second case from SciML:** a callback that needs an integrator capability (`get_du`, a temporary cache, the error estimate) that only some integrators provide. I support option (a).
- **One architectural difference without a design change:** the trait is the *model*, not the problem. The problem is SciMLBase's concrete record keyed on the state type.

---

## 1. The architecture I propose

### 1.1 What varies, and how often

SciML's inputs vary at three rates. The architecture follows the rates.

| Rate | What | Who owns it | Its place |
|---|---|---|---|
| per ecosystem | algorithms, linear solvers, AD backends | solver packages, LinearSolve, ADTypes | traits for the open sets; **in the key** |
| per model | the right-hand side, its parameters, the state type | the user, ModelingToolkit, NetworkDynamics | the state type **in the key**; the function and the parameters **behind a `Dynamic` position** |
| per solve | callbacks, `saveat`, tolerances, the options' functions | the user | **behind `Dynamic` positions**, or plain values in a concrete options record |

- The solver's step loop is compiled per numerical key: `(algorithm type with cache, U, T, linear solver, chunk)`.
- Nothing is compiled per function, per parameter type, or per callback, unless the caller casts with `compiled_for`.
- This is how JAX and Diffrax key their compilation: on the structure, shapes and dtypes of the state and of `args`, never on their values ([Diffrax `ODETerm`](https://docs.kidger.site/diffrax/api/terms/): `vector_field(t, y, args)`, `args` a PyTree). Diffrax traces the vector field into the compiled step, so it is always "compiled per function". The trait design makes that the caller's choice.
- SUNDIALS erases more: the right-hand side is a C function pointer with `void *user_data` (`CVRhsFn`), and even the state is erased behind an operations table ([N_Vector](https://sundials.readthedocs.io/en/latest/nvectors/NVector_API_link.html): content plus an `ops` table of function pointers). Boost.Odeint erases nothing: state, algebra and operations are template parameters of each stepper ([odeint: state types, algebras and operations](https://www.boost.org/doc/libs/1_86_0/libs/numeric/odeint/doc/html/boost_numeric_odeint/odeint_in_detail/state_types__algebras_and_operations.html)). The numerical key sits between the two: the state is compiled for, the function is erased.

### 1.2 The traits

| Trait | The open set | Owner | Implemented by | Default attribute |
|---|---|---|---|---|
| `ODEModel` | right-hand sides | SciMLBase | `PartialFn(f, p)` for a plain function; NetworkDynamics' `Network`; a user's model type | `Dynamic` (`@default_with_dynamic_self`) |
| `ODEJacobian`, `ODEMassMatrix`, `ODEJvp` | capabilities of a model | SciMLBase | models that can do better than the default | as `ODEModel` |
| `ODEAlgorithm` | algorithms | SciMLBase | each solver package, for its own types | `Compiled` (in the key) |
| `LinearSolver{in M}` | linear solvers | SciMLBase or LinearSolve | the core's dense LU; LinearSolve's solvers | `@default_compiled_for_self` |
| `JacobianBackend` | AD backends | SciMLBase (or ADTypes) | ForwardDiff, FiniteDiff, Enzyme, by extensions | `Compiled` |
| `StepState{U, T}` | integrators as the driver and callbacks see them | SciMLBase | OrdinaryDiffEqCore's integrator family; Sundials | `Dynamic` at callbacks |
| `IntegratorView{U, T, P} <: StepState{U, T}` | the integrator with its parameters | SciMLBase | a zero-copy view (§2.3) | `Dynamic` |
| `Callback{in U, in T, in P}`, `EventCallback{…}` | callbacks | SciMLBase | `DiscreteCallback`, `ContinuousCallback`; every DiffEqCallbacks type; users | `Dynamic` |
| `Trajectory{U, T}`, `DenseOutput{U, T}` | solutions, interpolants | SciMLBase | `ODESolution{U, T}`; each algorithm's interpolant | `Dynamic` |

`in` marks an input parameter (§2.2). The others are associated types, as today.

### 1.3 The model is the trait; the problem is a record

- TDE and the lean-core memo make the problem a trait (`ODEProblemTrait{T, P}`, with declared fields `u0`, `tspan`, `p`).
- I would make the **model** the trait, and keep the problem as SciMLBase's concrete record `ODEProblem{U, T, M, P}`:
  - Every problem has `u0`, `tspan` and `p`. They are data, not behaviour. A trait of fields over them buys a contract nobody else implements.
  - Users of SciML never write problem types. They write functions, `ODEFunction`s, ModelingToolkit systems, NetworkDynamics networks. All of these are models.
  - NetworkDynamics' `Network` is a callable model, not a problem (E-152's seam was the component's calling convention).
- The model keeps its parameters inside (`PartialFn(f, p)`, W-63). The record keeps `p` beside it for the API (`prob.p`, `remake`) and for callbacks.
- **What it buys:** `init(alg::Tsit5, prob::ODEProblem{U, T}, opts)` is a typed method on the solver package's own type and SciMLBase's concrete record. No bound, so no L-3 (E-156 P14), and no `CoreProblem` conversion step. The lean-core memo reaches the same place by converting every problem to `CoreProblem`; this makes the conversion the problem's constructor.
- `ODEModel` has no `P` and no `T`. Its operation is generic over the element type (§2.1):

```julia
# a sketch, not run; needs §2.1
@trait ODEModel begin
    @default_with_dynamic_self
    rhs!(m::ODEModel, du::Vector{E}, u::Vector{E}, t::Float64)::Nothing where {E <: Real}
end
@trait ODEJacobian <: ODEModel begin
    jacobian!(m::ODEJacobian, J::Matrix{E}, u::Vector{E}, t::Float64)::Nothing where {E <: Real}
end
```

### 1.4 Capabilities by defaults that take the context

- SciML asks `f.jac === nothing` (73 lines in Rosenbrock and Differentiation, lean-core memo §1.3).
- TDE keeps a marker function at `J` (`no_jacobian`), so a problem with a Jacobian and one without are two types.
- **The principled form:** the capability's operation takes what its default needs, here the backend, and the default uses it:

```julia
# a sketch, not run
@trait ODEModel begin
    rhs!(m::ODEModel, du::Vector{E}, u::Vector{E}, t::Float64)::Nothing where {E <: Real}
    jacobian!(m::ODEModel, b::Kept{JacobianBackend}, J::Matrix{Float64}, u::Vector{Float64}, t::Float64)::Nothing =
        backend_jacobian!(b, J, m, u, t)          # by the solver's backend; calls rhs! at its duals
end
```

- A model with an analytic Jacobian overrides `jacobian!` and ignores the backend.
- No marker, no query, no second type. The solver always calls `jacobian!`.
- This works because the trait's owner (SciMLBase) knows the capability. For a capability a third package adds, see §2.6 (open issue 82).
- The default calls `rhs!` at the backend's dual type. That needs §2.1.

### 1.5 The front end, ownership and keywords

- **`solve` and `init` stay plain and thin,** behind a function barrier (porting 0.5; B2's measured lesson). They normalize the keywords into a concrete `SolverOptions{T}`, enter the user's functions and callbacks, and call `init` with the record.
- **The body of `solve` for `AbstractDEProblem` belongs in SciMLBase,** which owns the type (move 3). DiffEqBase's front-end methods are then no pirates, and joint owners are a migration aid, not the end state.
- **Algorithm-specific options** stay in the algorithm struct, as upstream does (`Rodas5P(; autodiff, linsolve, …)`). The options record holds only what every algorithm reads.
- **Keywords need no design change here.** `Callable` with keywords (Planned) is not on this path.

### 1.6 Inside a solver package: closed sets

- Caches, tableaus, `perform_step!` and controllers stay types selected by dispatch, as the porting guide says (B6, "What stays plain"). Each package holds every member.
- They are fully typed over the numerical key, so the facts mode costs them nothing.
- `Rodas5P{AD, F, …}`'s parameters for the backend and the linear solver stay type parameters: they belong in the key. The bounded struct parameter form (§7.4) gives them their contract: `F <: LinearSolver{Matrix{T}}`, `AD <: JacobianBackend`.

### 1.7 Solutions

- `ODESolution{U, T}`: times, states, a retcode, and the interpolant as `Kept{DenseOutput{U, T}}`. Plotting and `sol(t)` are compiled per `(U, T)`, whatever the algorithm and the model.
- The solution keeps the problem record for `remake`, as a kept value or with the model erased. Its type then names neither.

---

## 2. Weak points of the design, and the changes that fix them

Each item gives the concrete case, the rule that blocks it (file:line), the change, and what it costs elsewhere. The first five are changes to the references. They are ordered by what they unblock.

### 2.1 Generic operations and generic `Callable`s: a signature with its own `where`

**The case.**
- A right-hand side is one generic Julia function: `lorenz!(du, u, p, t)`. The solver calls it at `Float64`, at its duals for the Jacobian (chunk 8, or a chunk picked from the state's length at `init`), and at duals of duals when a gradient goes through an implicit solve.
- TDE today:
  - one bounded struct parameter per signature (`F` at `CoreRHSSig{T}`, `D` at `CoreDualSig{DUAL_CHUNK}`, `J`), with library markers where one is absent (`no_dual`, `core_no_jacobian`);
  - the chunk fixed at 8 so that it is no part of the problem's type;
  - for a chunk chosen at `init`, an escape: `rhs_function(prob)::Any` hands out the raw function, and `DualJacobian{P, N, FD}` enters it again (E-157 pushback);
  - W-29 and W-30 would replace the two parameters with a tuple of `Callable`s. A tuple is still a finite list. It does not cover a chunk chosen at `init`, nor nested duals.
- BaseTraits has the same gap: `retain!(f, xs)` cannot write `f::Callable{Tuple{T}, Bool}` for the item type `T` (`traits.md:1154`).
- A problem type of the user's own (`LorenzProblem{T}`) declares `rhs!` at `Vector{T}` only. AD through it needs a sibling problem built by user code (porting B2, "the state's element type is the problem's").

**The rules that block it.**
- `traits.md:71`: the grammar's `Operation` has no `where`; an operation's argument types name only the trait's parameters and `Self`.
- `traits.md:707`: "The argument types `A` are a constant type." A bound naming a method's `where` variables is refused.
- `traits.md:1052` and `:856` (§7.5, §6.5): a function is kept at the signatures it entered with; another signature is refused (W-31 will enforce it).

**The change.** Two forms, both read as "at every `E`":
- **A generic operation:** `rhs!(m::ODEModel, du::Vector{E}, u::Vector{E}, t::Float64)::Nothing where {E <: Real}`. An implementation provides a method covering every `E` in the bound. The result type may name `E`.
- **A generic `Callable`:** in a bound or a struct parameter's bound, a `Callable` over a `UnionAll` signature, `F <: (Callable{Tuple{Vector{E}, Vector{E}, Float64}, Nothing} where {E <: Real})`, means "callable at every `E` within the bound". (Julia reads `where` as "some `E`". For a function bound only "every `E`" is useful to the callee. The spelling is open; a distinct one, such as `Callable{…, Nothing, E <: Real}`, avoids the clash.)
- **A `where` fixed by another argument** (the dependent case: `solve(f::Callable{RHSSig{P, T}, Nothing}, u0::Vector{T}, p::P) where {T, P}`) is accepted when every variable of `A` is fixed by another argument. That is the rule struct parameters follow already (`traits.md:1012`). Methods and structs then agree.

**What each attribute does with it.**
- `Compiled`: the function is inferred into the caller per `E`, as plain Julia.
- `Dynamic`: one compiled entry per concrete signature, made at its first call and cached in the kept value. This is what TraitWorld's `_erased_at` does today for T-54 (`TraitWorld/src/entry.jl`, `enter_callable`), and what TDE's `fd` relies on ("a `Dynamic` one's pointer is made at its first call").
- Every call stays checked: the arguments against the concrete signature, the result asserted.
- At entry, the function is checked for a method applicable at the bound's signature (`hasmethod` at the `UnionAll`). A method that does not cover every `E` fails at its first call at that `E`, with the checked call's `MethodError`.

**Why this is principled, and where other languages stand.**
- Rust refuses it for trait objects: a dispatchable method "must not have any type parameters" ([the Rust reference, dyn compatibility](https://doc.rust-lang.org/reference/items/traits.html)). A generic method needs `where Self: Sized`, so `dyn VectorField` cannot have `eval<S: Scalar>`. Rust's ODE crates go around it: diffsol asks the user for the Jacobian's action `J(x) v` as an operation of its own, or generates it with Enzyme through DiffSL ([diffsol](https://docs.rs/diffsol/latest/diffsol/)). No dual numbers cross the trait.
- Swift calls a generic requirement on an existential by passing type metadata and witness tables at run time, running unspecialized generic code ([Pestov and McCall, "Implementing Swift Generics", LLVM 2017](https://llvm.org/devmtg/2017-10/slides/Pestov-McCall-ImplementingGenerics.pdf)).
- Julia can do better than both: it compiles the instance for each concrete `E` at the first call. A `Dynamic` value with a generic operation costs one cached entry per signature used. The design gets dyn-compatible generic methods at the price of a small per-value cache.

**What it retires or simplifies.**
- TDE's `ODEProblem` (or the lean core's model record) has one bounded parameter for `f`. No `D`, no `no_dual`, no `DUAL_CHUNK` constant, no `rhs_function::Any`, no `DualJacobian` entering the function a second time.
- The chunk is chosen per problem at `init` with nothing entered again: the kept `f` is called at `FDual{N}`.
- Nested AD and reverse-mode tracked numbers work through the same bound.
- §1.4's default `jacobian!` is expressible: it calls `rhs!` at the backend's duals.
- W-30 is not needed for TDE. W-29's tuple of `Callable`s stays for signatures of different shape (in place and out of place, different arities).
- `retain!(f::Callable{Tuple{T}, Bool}, xs::(MutableIndexable{T}, Resizable)) where {T}` becomes writable (the dependent form).
- A sibling at another element type is an operation: `with_state(prob::ODEProblemTrait{T, P}, u0::Vector{E})::ODEProblemTrait{E, P} where {E}`, a `Dynamic` result (`traits.md:770`). A library's `gradient` can promote a user's own problem type.

**What it costs elsewhere.**
- **W-31 must change before it lands.** W-31 refuses a function kept at one signature at a bound of another (T-54). With this change, a function kept at a generic signature is accepted at any instance of it; a function kept at a fixed signature is still refused elsewhere. The mechanism W-31 would delete is the one this change needs.
- Definition checking needs an archetype for `E`: a rigid type with the bound's properties (`<: Real`). The associated-types exploration already plans parameter archetypes as named variables (`explorations/associated-types.md` §2).
- `verify_main` lists one target per concrete signature a call site uses. In compiled code `E` is concrete at each call, so the list is finite. A call at an `E` unknown to the caller is a run-time site.
- Each kept `Dynamic` function grows a small cache of entries. One per element type in use: two or three in a solver.
- The check at entry is weaker than for a constant signature: coverage of every `E` is not proved, only that a method applies at the bound.

This is open issue §2.10 ("`Callable` bounds whose argument types are chosen by the callee"), waiting for "the SciML port's algorithm packages". The port's answer: W-63's partial evaluation removes `P` from the signature, but not the element type. The duals still need it.

### 2.2 Input parameters: a type conforming at several values of a parameter

**The case.**
- DiffEqCallbacks is a package of callback types: `SavingCallback`, `PresetTimeCallback`, `TerminateSteadyState`, `ManifoldProjection`, `PeriodicCallback`. Each serves every problem: any state type, any parameter type.
- In the design a callback type implements `Callback{U, T, P}` at one value of each. `@implement Callback{Vector{Float64}, Float64, LorenzParams{Float64}} Bounce` serves Lorenz problems only (E-158 pushback: "A callback type for every `P` is not offered").
- The ways round: make every library callback a plain record entered at `init` (what `DiscreteCallback` does, through `FunctionCallback`), or give it a parameter of its own (`Bounce{P}`) that the user writes. The first turns every DiffEqCallbacks type into closures. The second leaks the problem's types into the user's code.
- The same shape recurs:
  - a linear solver serves every matrix type it can factor: `LinearSolver{in M}`;
  - the algorithm-to-integrator link (PB-A, W34-1): Rust's `trait Algorithm<P> { type Integrator: Integrator<P>; }`;
  - `Callable{A, S}` itself: `A` is an input parameter. The design names it "the one trait with several values per type" (`traits.md:278`).

**The rule that blocks it.**
- `traits.md:278`: "Not offered: a type conforming at several values of a parameter … `Callable` is the one trait with several values per type."
- Decided in session 22 (`record/decisions.md:61`: "No input parameters"); deferred, not rejected, in `explorations/associated-types.md:196`, and listed as open issue §2.6 "to revisit with the ports".

**Why multiple dispatch does not suffice here.** The associated-types exploration says "Julia rarely needs them, because multiple dispatch already relates several types in one function" (`associated-types.md:91`). That holds at a call. It does not hold for a **stored** value. The integrator keeps its callbacks as `Vector{Kept{Callback{U, T, P}}}`. The kept value must be seen through the trait at the integrator's `(U, T, P)`. Without input parameters, the trait cannot say "this callback type serves these inputs".

**The change.**
- A trait may mark parameters as inputs: `@trait Callback{in U, in T, in P}`. Its other parameters stay associated types.
- An implementation may cover a set of inputs, by a `where` over the trait's input parameters: `@implement Callback{U, T, P} SavingCallback{S} where {U <: AbstractVector, T <: Real, P, S}`.
- **An input parameter is never left open at a bound.** It is fixed by a constant or by a `where` variable shared with another argument (`cb::Callback{U, T, P}, integ::StepState{U, T}`). This removes the ambiguity the exploration feared (`x::Convertible{T}` with `T` open).
- **Overlap** follows the generic implementations' rules (`traits.md:500`–`505`): patterns only, the more specific wins, two overlapping without an order refused.
- **Who may implement:** a stakeholder of the implementation's signature: the owner of the trait, of the type, or of a type in the inputs. This is the facts mode's own definition (`facts.md:69`, "the owners of the types in its own signature"), and Rust's orphan rule with a local type parameter. It changes `traits.md:1200` ("the trait's owner or the type's owner") by one clause.
- **Checks:** each (type, inputs) pair is checked at its first use, as a family member is (`traits.md:466`–`469`).
- **Kept values** are made at concrete inputs, `Kept{Callback{U, T, P}}(cb)`. The implementation is looked up once there and held in the kept value. Calls cost what they cost today.
- `Callable{A, S}` becomes an ordinary trait with an input parameter `A` and the result `S`. The special case leaves §3.4.

**What it costs elsewhere.**
- `conforms(T, X)` and, later, `T <: X` need the inputs: `conforms(Bounce, Callback{Vector{Float64}, Float64, P})`. A trait with inputs has no meaning without them.
- The registry of implementations is keyed by (type, inputs). Family members already are, in effect.
- Definition checking treats inputs as rigid archetypes, as associated types.
- An extension's implementation must mention its triggers (`traits.md:1202`): unchanged, since an input type's owner is a stakeholder.

### 2.3 Field paths in mappings: a declared field stored in a field of a field

**The case.**
- W-63 keeps the parameters out of the core. The core's integrator has no `p`; callbacks still read `integ.p` at the parameters' type.
- TDE's answer is `ParamIntegrator{U, T, P}`: copies of the core's `t`, `dt` and two flags, copied in before each user callback and the flags copied back after (`ODECore.jl`, `_sync_in!`, `_sync_out!`). The code says why: "a declared field is a stored field (traits reference §3.3), so the adapter cannot forward the live fields".
- The lean-core memo extends this to what DiffEqCallbacks reads: `u`, `uprev`, `t`, `tprev`, `dt`, `p`, `iter`, `sol`, `opts`, `alg`, `f`, "scalars copied by the adapter before each callback and back after". Upstream's DiffEqCallbacks reads `integrator.t` 36 times, `.u` 34, `.sol.prob` 20 (`.tspan` among them), `.opts.abstol` 7, `.tprev` 8 (counted by grep in `ndport/pkgs/DiffEqCallbacks.jl/src`).
- The copy is a cost per callback call. It is also a correctness hazard: a field the callback writes and the adapter does not copy back is lost without an error. A field the core changes inside a callback's operation (`add_tstop!` then `integ.t` after an interpolation) is stale.

**The rules that block it.**
- `traits.md:235`: "A declared field is a stored field the conforming type must have: same name (unless mapped …)."
- `traits.md:423`: a mapping is `declared => stored`, one level.
- `traits.md:305`: a subtrait's implementation agrees with its supertrait's: the same forwarding field. So `IntegratorView <: StepState` cannot forward the `StepState` part to a field and take `p` from the outer type.

**The change.**
- A mapping may name a **path of stored fields**: `t => core.t`, `tspan => sol.prob.tspan`, `abstol => opts.abstol`.
- Each hop is a stored field, read by `getfield`. A hop may be a kept value or a trait-bounded field; then the next name is a declared field of its trait. No hop computes anything, so §3.3's ban on computed properties (`traits.md:241`) stands.
- **Writes** go to the last hop. The writable-field rules (`traits.md:239`) apply to the last hop. The hops before it may be `const`.
- **The key** holds each hop's declared type. A `Dynamic` hop reads through its operation, so it costs a dispatch per read.
- A subtrait may be implemented by forwarding its supertrait's part along a path and adding its own fields: `IntegratorView` over `(core::Dynamic{StepState{U, T}}, p::P)`.

```julia
# a sketch, not run
struct ParamView{U, T, P}                 # immutable: nothing to copy, nothing to sync
    core::Dynamic{StepState{U, T}}
    p::P
end
@implement IntegratorView{U, T, P} ParamView{U, T, P} where {U, T, P} begin
    u => core.u, t => core.t, dt => core.dt, u_modified => core.u_modified, terminated => core.terminated
    add_tstop!(v, τ) = step_tstop!(v.core, τ)
end
```

(The mapping inside a block is a sketch of a spelling; the reference has mappings only after the type or after `by`.)

**What it buys.**
- No copy, no sync, no stale field. A callback's write reaches the integrator.
- The DiffEqCallbacks fields map onto the upstream integrator's own nesting (`sol.prob.tspan`, `opts.abstol`), so OrdinaryDiffEqCore's `ODEIntegrator` conforms to a flat `IntegratorView` without restructuring.

**What it costs elsewhere.**
- The lowering of field reads gains a loop over hops. A `Dynamic` hop is an operation call.
- The forwarding-field rule (`traits.md:411`, "may not also be a writable declared field") extends to every hop.
- Printing a key (`ColTable at …`) needs the hops' types.
- The held/lens split withdrawn in session 22 (`design/alternatives.md:52`) concerned copying layouts and computed views. A path of stored fields is neither. The user should check this reading against that record.

### 2.4 A kept `Compiled` function is called through code compiled for its type

**The case.** E-158 finding 5: a `compiled_for` closure kept in a `Kept{Callable}` field costs 270–280 ns per call (hot members), a `Dynamic` one 12.7 ns. The user who casts to get speed gets twenty times less.

**The rule.** `traits.md:1049`: "`Compiled{Callable{A, S}}`: the function itself; a call selects its code by its type." That is run-time dispatch on a value of unknown type.

**The change.**
- In storage, a value's attribute decides only what happens **when it is passed to a bound**: a `Compiled` value then opens, and the bound's code is compiled for its key. A call of a kept function (or an operation on a kept value) from code that does not know its type goes through an entry compiled for the held type at the signature, made at the first call, for either attribute.
- `Compiled` then means what §6.1 says it means, "code compiled for what the trait sees of the value's type runs for it", including at a stored call.

**What it costs elsewhere.** A kept `Compiled` value carries the same per-signature entry cache as a `Dynamic` one (§2.1). The lowering's two paths for kept functions become one. Nothing in the references' meaning of the attributes changes; only the stated mechanism.

### 2.5 Compiling ahead reaches a driver with several trait positions

**The case.** The lean-core memo, pushback 3: "Compile ahead does not reach the solver's driver: workloads are its way into images."

**The rule.** `traits.md:1342`: "Another trait position is not a concrete argument: its key is not known."

**The change.** A trait position whose bound's default is `Dynamic` (a trait declaring `@default_with_dynamic_self`, `Callable`, or a `Dynamic{X}` annotation) has a known key for plain values: the erased key. Compiling ahead from `@implement ODEAlgorithm Tsit5` then covers the bounded functions whose other trait positions default to `Dynamic`, at their erased keys.

**What it costs elsewhere.** More code in each image: one instance per declared implementation of the compiled position. `JULIA_TW_AHEAD=0` stays the switch. A caller that casts `compiled_for` still compiles at its first call, as today.

### 2.6 Capabilities of a stored value (open issue 82): a SciML case

**The case.**
- A callback sees the integrator as a `Dynamic{IntegratorView{U, T, P}}`. DiffEqCallbacks also calls `get_tmp_cache(integrator)` (8 times), `get_du`, `addsteps!`, `has_tstop`, and reads `controller_cache.EEst`. Upstream's informal interface lets an integrator lack some of these; a callback learns it at run time.
- In the design, `IntegratorView` must either declare all of them, each with a default that "never throws 'not implemented'" (`traits.md:220`), or split them into capability traits (`HasDu`, `HasTmpCache`, `HasErrorEstimate`).
- With capability traits, a callback bounded `integ::(IntegratorView{U, T, P}, HasDu{U})` cannot receive the stored view: "a value is seen through the traits it entered with" (`traits.md:856`). The core that makes the view (SciMLBase) does not know which capabilities Sundials' integrator has.
- So this is the DataFrames case of open issue 82 again, from a second library: the capability belongs to a third package's type, and the consumer is a fourth package's callback.

**What I'd decide.** Option (a) of open issue 82: a kept value is seen through every trait its held object conforms to, checked at the bound. Two additions from this case:
- The check is per held type, not per value, so it can be cached by type. A callback called at every step pays a lookup, not a conformance computation.
- §1.4's pattern (an operation with a default that takes the context) stays the first choice where the trait's owner knows the capability. Option (a) is for capabilities a later package adds.

### 2.7 Smaller points

- **An optional kept function.** `ContinuousCallback`'s `affect_neg!`, `initialize`, `finalize`; a given Jacobian. A bounded struct parameter cannot be absent (E-157 pushback), so TDE keeps marker functions. Proposal: state in §7.2 that `Union{Nothing, X}` in storage means `Union{Nothing, Kept{X}}`, and that a bounded parameter may be `Nothing`. Small; it removes the markers and keeps union splitting.
- **Defaults that name the trait's parameters** (T-2): §1.4's default needs `T` for buffers. A deviation, not a design point; it moves up the queue if §1.4 is adopted.
- **An operation's result declared with a trait** (E-156 P12, P14: asserted to the trait's type, so every call raises). The design is right (`traits.md:770`); the implementation is not. It blocks the link of §2.2 written as Rust writes it.
- **Boxing of immutable non-bits arguments** at `Dynamic` calls (the view, a named-tuple `p`; open issues §4 item 35): every callback call allocates. A lowering point, not a design point. §2.3's `ParamView` is immutable and non-bits too, so this matters for it.

---

## 3. Where I differ from the existing plans

| Topic | The plans | This page |
|---|---|---|
| The stance | The exploration: "None of these proposes a change" (§5). The lean core: "The recommended architecture changes no reference" (§3.4). | Five reference changes (§2.1–§2.5), each removing a workaround the plans carry. |
| Dual signatures | One bounded parameter per signature (form B); W-29/W-30 tuple; chunk at `init` via `rhs_function::Any` and `DualJacobian` | One generic `Callable` (§2.1). W-30 not needed for TDE; W-31 to be reconsidered before it removes `_erased_at`. |
| Callbacks for every problem | Plain records entered at `init`; callback types state `P` (E-158) | Input parameters (§2.2): DiffEqCallbacks' types implement `Callback{U, T, P}` for every `P`. |
| The callbacks' view | `ParamIntegrator`, copy in and out; extended to a dozen fields in the lean core | Field paths (§2.3): a zero-copy view. |
| `compiled_for` callbacks | Accepted as slower (E-158 finding 5: "by design") | A kept `Compiled` value is called through its own compiled entry (§2.4). |
| Compiling the driver ahead | Workloads only (lean core, pushback 3) | `Dynamic`-default positions have a known key (§2.5). |
| What is the trait | The problem (`ODEProblemTrait{T, P}` with fields) | The model (`ODEModel`); the problem a concrete record (§1.3). The lean core's `CoreProblem` becomes the record itself. |
| The Jacobian's presence | A marker function at `J`; `f.jac === nothing` replaced by `jacobian!` | `jacobian!` with the backend as an argument and a default (§1.4); no marker. |
| The algorithm–integrator link | Open issue 51 (a+): a driver bounded by both traits at shared parameters | Agree for now; with §2.2 and the P12 fix, the Rust form (`init` returning `Dynamic{Integrator}`, opened once per solve) becomes available and checked. |
| Open issue 82 | Recommendation (a), from DataFrames | Agree; a second case from SciML (§2.6), with the check cached per held type. |

Where I agree without reservation:
- W-63: the parameters at the surface. Diffrax's `args` and SUNDIALS' `user_data` make the same choice.
- The front end plain and thin, behind a barrier (B2's measured lesson).
- Solver internals closed per package, typed, fully typed over the key.
- The body of `solve` in SciMLBase (move 3); joint owners as a migration aid.
- Trajectories keyed on `(U, T)`.

---

## 4. The smallest experiments that would decide

Each is minutes, outside SciML, on TDE or a probe script. None ran.

| # | Question | How | Result that decides |
|---|---|---|---|
| X1 | Is a generic `Callable` sound and as cheap as today's `Dynamic` call? | Prototype the bound on a struct parameter on top of `_erased_at` (T-54's path). TDE's `ODEProblem` with one `F`; Rodas5 at chunk 8 and at a chunk picked at `init`; a gradient through Rodas5 (nested duals). Compare `RESULT` lines with `main`; count solver CodeInstances for a new function; time a `Dynamic` call per signature. | Identical results; zero new solver CodeInstances; per-call cost within E-157's ~6 ns overhead. Then §2.1 is worth a decision, and W-31 waits for it. |
| X2 | Do input parameters cost anything per call? | A probe: `@trait Callback{in U, in T, in P}`; a library type `Saver` implementing it for every `(U, T, P)` (prototyped as a family keyed by (type, inputs)); two problems with different `P` in one session. Per-call cost against E-158's hot members (32–41 ns per step for two callbacks). | The same per-call cost; one member check per (type, inputs) at first use. |
| X3 | Does a field path remove the adapter's cost and hazard? | `ParamView` with paths against `ParamIntegrator` in E-158's check-5 harness. Add a callback that writes `integ.dt`-like state and reads `integ.t` after `add_tstop!`. | Lower cost per callback call, and the write visible to the core (the copy version loses it). |
| X4 | Can a kept `Compiled` function be called at a `Dynamic` call's cost? | A per-signature entry compiled for the held type in a `Kept{Callable}` field; E-158 check 5's `compiled_for` row. | 270–280 ns falls to near the `Dynamic` 12.7 ns. |
| X5 | How much does a `Dynamic`-default position move into the image? | `--trace-compile` of TDE's first solve with `@implement ODEAlgorithm` compiling ahead at erased keys. | The driver's CodeInstances leave the first call. |
| X6 | Does option (a) of open issue 82 serve an integrator capability? | A callback bounded `(IntegratorView, HasDu)` beside one bounded `IntegratorView`, given a `Dynamic` view of two integrator types, one with `HasDu`. Cost per call with the check cached by type. | The capable method runs for the capable integrator only; the check costs a lookup per call. |

X1 first: it decides whether W-31 should proceed as written, and it has the largest reach (duals, chunks, nested AD, `retain!`, sibling problems).

---

## 5. Sources

- References: `writeup/reference/traits.md` (lines cited above), `writeup/reference/facts.md:69`.
- TDE: `TraitDifferentialEquations/src/ODECore.jl` (`ODEProblem`, `CoreProblem`, `ParamIntegrator`, `_sync_in!`, `rhs_function`), `README.md`.
- Experiments: `experiments/w34-sciml/README.md` (E-156 P12, P14; E-157 pushback; E-158 findings 1, 5 and pushback).
- Upstream: `ndport/pkgs/OrdinaryDiffEq.jl/lib/DiffEqBase/src/solve.jl:1011` (`promote_f`, the function wrapped at fixed signatures with a chunk `CS`), `lib/OrdinaryDiffEqCore/src/integrators/type.jl:155` (`ODEIntegrator`, 26 type parameters), `lib/OrdinaryDiffEqRosenbrock/src/algorithms.jl:121` (`$Alg{AD, F, StepLimiter, StageLimiter, CJ}`), `ndport/pkgs/SciMLBase.jl/src/despecialized_parameters.jl` (upstream's own move toward keying without `p`), `ndport/pkgs/DiffEqCallbacks.jl/src` (field reads counted).
- Other languages: [Rust reference, traits and dyn compatibility](https://doc.rust-lang.org/reference/items/traits.html); [diffsol](https://docs.rs/diffsol/latest/diffsol/) (`OdeEquations`, `OdeEquationsImplicit`, the Jacobian's action supplied by the user or by Enzyme through DiffSL); [Diffrax terms](https://docs.kidger.site/diffrax/api/terms/) and [solvers](https://docs.kidger.site/diffrax/api/solvers/abstract_solvers/); [SUNDIALS N_Vector](https://sundials.readthedocs.io/en/latest/nvectors/NVector_API_link.html); [Boost.Odeint](https://www.boost.org/doc/libs/1_86_0/libs/numeric/odeint/doc/html/boost_numeric_odeint/odeint_in_detail/state_types__algebras_and_operations.html); [Pestov and McCall, Implementing Swift Generics](https://llvm.org/devmtg/2017-10/slides/Pestov-McCall-ImplementingGenerics.pdf).
