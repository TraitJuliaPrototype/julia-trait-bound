# Review: the W-34 plan (what TraitWorld and the facts mode need for the SciML restructure)

Date: 2026-10-21. Reviewer: an Opus 5.5 agent, fresh eyes. Not edited after writing, except by a dated addendum.

**Reviewed:** [`../plans/2026-10-21-w34-sciml-prerequisites.md`](../plans/2026-10-21-w34-sciml-prerequisites.md) (status: proposal; untracked when reviewed).

**Read against:**
- the exploration [`../explorations/sciml-as-traits.md`](../explorations/sciml-as-traits.md) and the porting guideline's case study [`../intro/porting.md`](../intro/porting.md) B6;
- the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (P4-1, P6-1, W34-1);
- [`../reference/traits.md`](../reference/traits.md) §3.1–§3.7, §4.2, §4.3, §4.7, §5.1, §5.5, §5.8, §6.2–§6.8, §7.1–§7.5, §10.1 and its Deviations (T-2, T-5, T-6, T-7, T-22, T-54, T-57); [`../reference/lowering.md`](../reference/lowering.md) §4.6, §8.1–§8.3, §9.3, §12, §13, §13.2 and L-3, L-25, L-31, L-36; [`../reference/compiler.md`](../reference/compiler.md) §4.2, §4.3, C-14;
- [`../open-issues.md`](../open-issues.md) 48–50 and §2 items 4–6, 10, 16; [`../record/todo.md`](../record/todo.md) W-29–W-35; [`../design/evidence.md`](../design/evidence.md) §2 and the E-154 line;
- TraitWorld f06b82d: `src/implement.jl` (`_keys_implement`, `_implement_expand`, `_implement_where`, `_implement_family`, `_implement_projection`, `_op_method`, `_conformance_methods`, `_family_conformance_methods`, `_conf_family`, `_declare_conformance_now`, `_witness`, `proj_lookup`), `src/entry.jl` (`_conf_call`, `_conformance_slow`, `_assemble`), `src/core.jl` (`_DynOp`, `_Open`, `_dyn_tobj`);
- TraitDifferentialEquations fbb9bd8: `src/ODECore.jl`, `src/TraitDifferentialEquations.jl`, `baselines/`, `scripts/session.jl`.

No Julia was run (a build holds the lock). Every cost and behaviour below is from reading the code, not measured.

## Verdict

- **The inventory is careful, and most rows are right.** The move-by-move tables, the probe list and the registry rows are the right shape for the work.
- **The central decision of the plan rests on a wrong premise.** Form B does not need W-29: TraitDifferentialEquations runs Rosenbrock's dual calls today with the function entered at two bounded parameters, and the plan itself uses that as form B's control (finding 2).
- **Form A, as written, cannot be declared for `ODEFunction`,** and its per-call cost for any parametric model is open issue 49's path, not a split (findings 3, 4). Form B is the design's principled form for a plain function (finding 5).
- **T-57 does not block moves 2 and 3.** The no-block family by the type owner's own methods is a route today; T-5 and T-57 can be reconciled by reading now (findings 6, 7).
- **L-3 is on move 3's path in SciML's real ownership,** not only on a convenience: CommonSolve owns `solve`, `init` and `solve!` (finding 8).
- **Open issue 51 misses three forms within the design,** one of which checks the parameters of the link at every call (finding 10).
- **One ID collision:** W-35 is taken (finding 1).

## Findings

### 1. (blocker) W-35 is already in use

- **What:** `todo.md` at HEAD (56c5284) has `W-35`, "Porting strategies for Makie and DataFrames". The plan drafts W-35 (family forms), W-36 and W-37 as new rows, and uses W-35 in the summary, §1.2–§1.4, §2, §3.1 and §4.2.
- **Why it matters:** IDs are permanent and never reused (CLAUDE.md, rule 4).
- **Fix:** renumber to the next free IDs (W-36, W-37, W-38 if still free when the plan is adopted) and replace every use in the plan.

### 2. (blocker) Form B does not need W-29: the plan's decision is framed on a false premise

- **What the plan says:** the summary ("If the record keeps the function at a `Callable` bound, form B, it needs W-29"), §1.2's row "A function kept at two signatures in one struct parameter (form B) … Planned: W-29 … pause item if E-157 picks form B", the verdict ("Rosenbrock needs … W-29 under form B"), E-157's question (5), §3.3's W34-3, §4 item 4 and §5's second bullet.
- **What holds:** TDE's `ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}, D <: Callable{DualSig{P, DUAL_CHUNK}, Nothing}}` keeps the same function at two bounded parameters (`src/ODECore.jl`; the front end `_problem(f, u0, tspan, p) = ODEProblem(f, u0, tspan, p, f)`). Rodas5's Jacobian calls `prob.fd` at the library's duals (`ad_jacobian!`). Its `RESULT` lines include Rodas5. This is within the design: §7.4 allows several bounded parameters, each typing one field, and a plain function entering two positions is first seen at each. W-29/W-30 make it one parameter; they are a tidier form, not a prerequisite.
- **The plan contradicts itself:** §2.2 names exactly this record as form B's control ("TDE's current `ODEProblem` (two `Callable` parameters today; the tuple after W-30)").
- **What remains open for form B:** only SciML's chunk chosen per problem (open issues §2 item 10). The plan's own route (keep the function plain beside the kept one, enter it at `init` at the algorithm's chunk) covers it.
- **Fix:** restate form B as "runs today with two bounded parameters; W-29/W-30 tidy it". Drop E-157's (5) as a discriminator, W34-3, and the "W-29 on the critical path" branches of §3.1, §4 item 4 and §5.

### 3. (blocker) Form A's `ODERHS{P}` cannot be declared for `ODEFunction`

- **What:** form A is `rhs!(f::ODERHS{P}, du::AbstractVector, u::AbstractVector, p::P, t)::Nothing`, with "`ODEFunction` conforms as a family", probed as P4 (`A where {A <: Fn{true}}`).
- **Why it fails:** `P` is an associated type: one value per implementation (§3.4). Neither SciML's `ODEFunction` (21 parameters, none for `p`) nor the plan's `ODEFunction{F, TJ, TMM}` has a field or a parameter that defines `P`. A joint family needs every variable of the trait's parameters to occur in the type (§4.7). A stated value cannot be a function of the member. So the family cannot state `P`, and a type conforming at every `P` is "not offered" (§3.4). Adding a `P` parameter to `ODEFunction` only to satisfy the trait is a hidden type parameter, which the user has rejected.
- **The same for a user's model:** `@implement ODERHS{Vector{Float64}} N where {N <: Network}` (P3) fixes `p`'s type for every network. A network solved with dual parameters (forward sensitivities in `p`) does not conform. This is the "type at two element types" question that form A was meant to avoid, moved from `u` to `p`.
- **Fix:** if form A stays, declare `ODERHS` without parameters, `rhs!(f::ODERHS, du::AbstractVector, u::AbstractVector, p, t)::Nothing`, and say what is lost (no check of `p`'s type). Change P3 and P4 accordingly, and predict P4's present form as refused.

### 4. (should fix, high) Form A's per-call cost for a family member is open issue 49's path, by reading

- **The question asked:** does form A pay P4-1's ~390 ns crossing per right-hand-side call?
- **Not that path.** Under form A the solver calls an *operation* on a `Dynamic` value: `Compiler.split_call` over the first four candidates, else the table of the call's targets (lowering §13; compiler §4.3). For a declared concrete type that is a probe and an indirect call: 2.5–18.5 ns, no allocation (evidence §2, E-145). It is not a bounded function's entry, so P4-1's crossing does not apply.
- **But a family member opens through the registry on every call.** The target is `_DynOp`, which calls `_Open{X}()(x)`, then `_dyn_tobj`, then `_assemble`, then `conformance(As{X}(), x)`. For a family member that method is `_conf_family`: a lookup in the family's `IdDict` and a call on the builder at an abstract type, per call (`implement.jl`, `_conf_family`; `core.jl`, `_dyn_tobj`). The trait object's type is then unknown, so the operation itself is a dynamic call, with `t` boxed. This is exactly open issue 49 (304 bytes per call in its probe), plus a dynamic dispatch.
- **Every case form A cares about is a family member:** every `ODEFunction{…}` (parametric in the user's function), the plan's `ChainModel{G}`, NetworkDynamics' `Network{…}`. Only a concrete type declared with the one-line form has a constant builder.
- **Order of magnitude, unmeasured:** some 100 ns and a few hundred bytes per call, six to seven calls per Tsit5 step. TDE's Lorenz step is 158–199 ns (evidence §2), so form A could multiply it. Form B's call is a `Dynamic{Callable}` call, 3.95 ns (evidence §2, `callbench.log`), with no allocation for `Vector` arguments.
- **Both forms box a non-isbits immutable argument per call** (the split table and `_CallWrap` pass non-bits values boxed): a `NamedTuple` or `ComponentArray` `p`, a `SubArray` state. TDE's `p` is a `Vector{Float64}` or `nothing`, so E-157 would not see it.
- **Fix:**
  - State the prediction in §1.2 and in P6.
  - Split P6 into a concrete one-line model and a family-member model, and expect allocation for the second.
  - Put open issue 49 to the user now, since it is on form A's path by construction and changes how an existing feature is built.
  - In E-157, measure nanoseconds and allocations per `rhs!` call, a few seconds of a loop, before the solve's steady state. Add a `NamedTuple` `p` to check 4.

### 5. (should fix) Form B is the more principled form for a function; form A weakens the check

- **The design's tool for "a function at a declared signature" is `Callable`** (§5.8): anything callable conforms without an `@implement`, every call is checked against the declared signature, and the reference's own example of §7.4 and §7.5 is TDE's `ODEProblem`. The exploration's principle 5 ("the signature is checked at every call") rests on it.
- **Form A with abstract buffers gives that up.** Only `du isa AbstractVector` and the `Nothing` result are checked. The plan's "What it buys: … the signature checked" (§2.2) is true of form B, not of form A.
- **In Rust terms,** form A is a trait method generic in the buffer type behind `dyn`, which Rust refuses as not object-safe. The design allows it, because the split's table is per call signature. That is a legitimate Julia capability, but not "the idiomatic form" the guideline argues from.
- **A model type with behaviour of its own** keeps the trait route the design already has: it implements the problem trait itself (TDE's "a problem type that implements `rhs!` itself is the receiver type"). A callable model (`Network`) enters form B unchanged.
- **Fix:** make form B the primary form for move 1 (as the exploration and B6 have it), with form A an optional experiment for its open dual chunk, after open issue 49. Choice 2 of §3.4 changes accordingly.

### 6. (should fix) T-5 against T-57: the code answers P2 now

By reading TraitWorld f06b82d:
- **`@implement X S{T} where {T} begin … end` (the current spelling, a block, the target not a bare variable).** `_keys_implement` matches the `where` branch only when the body is a `Symbol`. It falls through to `(X{S{T} where {T}}, block)`. `_implement_expand` then takes the single-type path with `Rex` the `UnionAll`. The operations' methods cover every member. But `implementation(::Type{X}, ::Type{S})` matches only the `UnionAll`. The `conformance` method has no builder (`_declare_conformance_now` returns `b = nothing` for a non-concrete type), so `_conformance_slow` finds no witness for `S{Int}`, and the call reports "conforms to none". **This happens in any module.** With trait parameters (`X{T}`), `withR` writes `X{T, S{T} where {T}}` with `T` free, and `_param_methods` fails at the declaration. T-5's text is right.
- **`@implement X A where {A <: S} begin … end`.** `_implement_where` takes the family branch, and `_op_method`'s precheck evaluates `A` without its `where`. Outside the module that owns the operation's function this is refused. Inside, the precheck is skipped and it works. T-57's text is right for this form.
- **The earlier spelling `@implement X{S{T}} where {T} begin … end`** reaches `_implement_family`, whose precheck evaluates `S{T}` with `T` unbound: refused outside the owner's module, working inside.
- So T-57's "inside the trait's module both work" holds for the second form and the earlier spelling, not for the first form in the current spelling. That is T-5.
- **Two small fixes:**
  - route a `where` target with a block and a non-symbol body to `_implement_family` (T-5);
  - make the precheck evaluate the receiver under its `where` clause, or test ownership of the bound's base type (T-57).
- **Side finding, to probe in E-156:** the no-block family branch of `_implement_projection` (`pexs === nothing`, the joint form by fields) defines `implementation`, `projection` and the family's `conformance` without `_check_implementation`. So no ownership check runs (§4.9, "Who"). A third package's `@implement IntegratorView Foreign{T} where {T}` would be accepted. If confirmed, it is a new T- row.
- **Fix:** write these predictions into P1 and P2. Correct T-57's text with the fix. Bound the renumbered W-35's scope to these two fixes, T-2, and only the E-156 failures a move needs.

### 7. (should fix) T-57 does not block moves 2 and 3: the no-block family is a route

- **The form:** the type's owner defines the operations' methods for its own type as ordinary methods (not pirates: they name its type), then declares `@implement Integrator ODEIntegrator{…} where {…}` without a block. This is §4.7's first line, "every `S{P}`, by `S`'s own methods". TDE (`IntegratorView`), NetworkDynamics-p4 (`ComponentDynamics`) and Graphs (E-154) use the no-block family.
- **By reading it is not affected by T-57:**
  - the `S{T} where {T}` form goes through `_implement_projection`'s family branch, with no `_op_method` and no precheck;
  - `A where {A <: S}` goes through `_implement_where`'s family branch without a block.
  - Members are checked at their first use against the existing methods (`_member_problems`).
- **Consequences:**
  - The summary's "one deviation blocks two moves" and §1.3's and §1.4's verdicts overstate T-57.
  - E-158 and E-159 need not wait for the renumbered W-35; W-35 is the block's convenience.
  - "In SciML that is every integrator family … and every parametric algorithm type" holds only for the block form.
- **Fix:** add probe P1b: the no-block family over `S{T} where {T}` and `A where {A <: S}`, declared by the type's owner outside the trait's module, with the methods defined before. Move W-35 after E-159 in §2's order.

### 8. (should fix) L-3 is on move 3's path in SciML's ownership, not only on a convenience

- **What:** in SciML, CommonSolve owns `solve`, `init`, `solve!` and `step!` (the exploration's G-C). SciMLBase owns the types and would own the traits.
- **Why it matters:** SciMLBase adding the bounded driver `CommonSolve.solve!(integ::Integrator)` is a bounded method of a shape CommonSolve's function has none of, by a non-owner. Lowering L-3 refuses that. §5.5 allows it ("where the package owns a trait the bound names"), so it is the same deviation W-36 studies. It lies on move 3's main path, not only on the default algorithm.
- **The prototype hides it:** in E-159, `ODECore` owns `init`, `solve` and `solve!`, so L-3 never applies to the driver.
- **A second instance in the prototype itself:** `TraitBS3`'s `init(prob::ODEProblemTrait, alg::BS3)` is a bounded method (a bound on `prob`). It is accepted only if `ODECore` already has a bounded `init` of that shape. Once the solvers leave `ODECore`, nothing guarantees that.
- **A route within the design:** a typed method on the core's own abstract integrator type, `CommonSolve.solve!(integ::DEIntegrator) = _drive!(integ)`, forwarding to a bounded function the core owns. Types first (§5.5); SciML's integrators already subtype `DEIntegrator`.
- **Fix:**
  - §1.4: classify L-3 as on move 3's path in the real stack, with the route.
  - E-159: add a small plain stand-in for CommonSolve that owns `solve`, `init` and `solve!`, so that L-3 bites where it would in SciML. Test the route. State that `ODECore` declares the bounded shapes that solver packages extend.
  - W-36 can start beside E-159, not after it.

### 9. (should fix) A non-conforming integrator raises `MethodError`, not `TraitBoundError`

- **The reference:** a value that conforms to none of the bounds reaches the fallback, else `MethodError` with a hint naming the bound (§5.5; the hint's text T-22). `TraitBoundError` is for a value conforming at other parameter values, or a shared `where` variable that disagrees (§5.1).
- **Where it is wrong:** E-159's check 3 and its registry row, open issue 51's draft, pushback W34-1 ("`solve!` raises `TraitBoundError`") and the guideline's B6 ("refuses an integrator that does not conform (`TraitBoundError`)").
- **Also missing:** with `solve!(integ::Integrator)` the first-call check tests conformance only, not that the integrator's `U, T, P` are the problem's. See finding 10, form (a+).
- **Fix:** correct the plan's check and drafts. List the stale copies in B6 and W34-1 for the adoption commit.

### 10. (should fix) Open issue 51: options sound, but incomplete

The three options are stated correctly, and (c) is rightly a change. Three forms within the design are missing, and (b) is mis-stated.
- **(a+) The parameters of the link, checked at every call.** Write the driver as `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P}) where {U, T, P}`. A `where` variable shared between bounds requires equal values (`TraitBoundError` otherwise, §5.1). This needs no change, and it is cheap.
- **(d) `init` as an operation of the problem trait, which has the parameters.** `init(prob::ODEProblemTrait{U, T, P}, alg)::Integrator{U, T, P}`:
  - a result declared with a trait, naming the trait's own parameters (§3.1, §6.2: such a result is `Dynamic`);
  - its implementation dispatches to the solver packages' typed methods (`alg_init(alg::Tsit5, prob)`, a stakeholder's).
  - The link, parameters included, is then a declared contract, checked at each return.
  - The cost is one `Dynamic` per solve. The driver opens it once with `compiled_for`, a function barrier per solve. Otherwise each `step!` pays the split, and open issue 49 for a family-member integrator.
- **(e) The configured algorithm, as a joint family.** Each solver package owns `Tsit5For{U, T, P}` (the algorithm configured for a problem's associated types). It implements `ODEAlgorithmFor{U, T, P}` as a joint family whose operation `init(a::ODEAlgorithmFor{U, T, P}, …)::Integrator{U, T, P}` names the trait's own parameters. This is Rust's `Algorithm<P>` with `P`'s associated types as the configured value's parameters. It is checked per member at its first use. A typed `configure(alg::Tsit5, prob)` makes the value. It costs one more type per solver.
- **(b) as drafted:** "`Kept{Integrator}` as the result" is a type; the design's form is `::Integrator`, a `Dynamic` result (§6.2), so P11 is not "unknown" for the reference, only unprobed. "One barrier per solve" holds only if the driver opens it, as in (d).
- **Fix:** add (a+), (d) and (e) to the draft. Recommend (a+) now and probe (d) in E-156 (P11 widened to it): it is the closest to Rust's checked link without a change. Keep (c) with §2 item 6.

### 11. (should fix) A callback record cannot bound its functions by signatures that name `U, T, P`

- **What:** §1.3 says that callbacks entered at `init` at the integrator's signatures rely on §7.4 ("a bound naming the struct's other parameters"), Implemented.
- **Why it fails:** §7.4's rules require every other parameter to be named by a field outside a bound, and the lowering refuses "a free parameter no other field names" (lowering §13.2). A record `CallbackRecord{U, T, P, C <: Callable{Tuple{U, T, Dynamic{IntegratorView{U, T, P}}}, Bool}}` has no field of type `U`, `T` or `P`.
- **A route that should work:** a parametric struct whose fields are typed `Callable{…U, T, P…}`. In a trait module that means `Kept{Callable{…}}`, as TDE's unparametrized `FunctionCallback` does. It is unprobed with parameters.
- **Fix:** correct the row's reference. Add the parametric record to P8.

### 12. (should fix) E-160 does not depend on W-33 in move 4's layout

- **What:** E-160's check 4 expects a plain caller of the `getproperty` sugar to infer the field's type after W-33, and the union before.
- **Why it is wrong:** in move 4's layout the sugar lives in the package's ordinary module (exploration principle 6; the plan's E-160 build: "the sugar `sol.ps[:σ]` in TDE's ordinary module"). A plain caller of plain code propagates constants without W-33. W-33 matters for move 0's state, where the switch sits inside the trait module (P6-1).
- **Fix:**
  - Restate check 4 as the contrast: the sugar inside the trait module (W-33's case) against outside (move 4's, no W-33 needed). That shows that move 4 and W-33 are two answers to P6-1.
  - E-160 then need not wait for W-33, except for the inside half.
  - §1.5's row "Planned; W-33 … yes, for the plain side" changes accordingly.

### 13. (should fix) W-37 (forwarding for a family) is not needed by move 4

- **Forwarding does not chain** (§4.3). SII's chain integrator → `f` → `sys` cannot be forwarded from the problem, solution or integrator to `sys`, family or not; W34-2 already notes it.
- **The route the plan names for the chain also covers the families:** the outer types implement `IndexProvider` by their own methods that read the field, declared as a no-block family (finding 7). That is what SII does today.
- **Fix:** mark W-37 "helpful, not needed" in §1.5 and §3.1, and take it off E-160's path. Implementing it remains legitimate work on a Planned part, if wanted.

### 14. (should fix) "`ODEFunction` with a Jacobian" as a subtrait member is not expressible in general

- **What:** E-157 builds `ODEJacobian{P} <: ODERHS{P}`, with `ODEFunction` conforming as a family.
- **Why it fails:** membership must depend on whether `TJ` is `Nothing`. A family's `where` bound cannot say "not `Nothing`" except as `TJ <: Function`, which excludes callable-struct Jacobians. The exploration's PB-C notes the related T-6.
- **A route within the design:** `jac!` as an operation of `ODERHS` with a default (finite differences or duals). `ODEFunction`'s own method branches on its type parameter (`f.jac === nothing`, folded per member). The subtrait stays for model types that declare a Jacobian.
- **Fix:** choose the route in §1.2 and E-157, or add a probe of the conditional family to E-156.

### 15. (minor) E-159: move an existing solver out, and give the census a negative control

- **Moving TDE's Rodas5 into its own package** tests the open set with no new numerics. TDE's existing `RESULT` lines are then the bit-for-bit control, with no plain BS3 to write.
- **Check 2 cannot fail as built.** Typed methods on owned types are never pirates, so the census finds none by construction. Add the negative control: the front end's body in a separate "DiffEqBase-like" package, which the census flags.

### 16. (minor) E-161 adds little

TDE's `ODESolution{T}` already has no model axis. With the problem's type independent of the model (P10), check (2) re-measures E-157's check 2. Fold `Trajectory` into E-157 or E-158 as one check, or leave it to the port's steps 5–7.

### 17. (minor) E-158's continuous callback is new numerics in two packages

TDE and PlainODE have no continuous callbacks today. Root finding on `interp!` is numerics, not the trait mechanism. Make the continuous callback minimal (a scalar condition, bisection shared verbatim with the control), or a second stage after the discrete one passes.

### 18. (minor) E-157's margins and its stated scope

- **"10 % + 1 ms"** on a Lorenz solve of well under a millisecond accepts anything. Use per-call nanoseconds and allocations per step as the primary measure (finding 4), and state the solve's length.
- **"What it buys":** "a new graph type compiles 17.7 s (E-154)" is the whole stack's figure (evidence: "the graph's type stays in the network's"). SciML's share is unmeasured. Say so instead of implying that move 1 buys the 17.7 s.
- **Check 3:** `ChainModel{G}` is parametric, so it conforms as a family and is checked at its first use, not at `@implement`.

### 19. (minor) P10 and E-157's check 2 must say where the model types are defined

`@default_with_dynamic_self` does not apply to a type of the trait world (§6.3): defined in a trait module, with fields of the trait world all the way down. Such a model is `Compiled`, and two of them give two problem types by design.
- Define the probe's model types in a plain module, and say so.
- Note that NetworkDynamics after move 0 is a trait module whose `Network` holds users' functions, so it is not of the trait world.

### 20. (minor) Registry rows: the settings rule 5 asks for

The rows name the build, the setting, strict mode and the runs. They do not name the load order or the machine's load. They should name the W-33 build's commit, not "W-33's build": W-33 changes inference across the modes, and a regression there would be read as a W-34 result.

### 21. (minor) A stale sentence in the exploration

Move 1's "Measured by proxy" puts the ~390 ns crossing into a family member beside the 3.95 ns `Callable` call, and concludes "tens of nanoseconds" per step. The first applies to an entry's crossing, the second to form B's call; form A's cost is neither (finding 4). Correct it in the adoption commit, with B6's "Needs the tuple of `Callable`s … (W-29)" and PB-D (finding 2).

## On the order (§2) and the port's next steps (§4)

**Prototypes,** cheapest and most decisive first:
1. E-156 with the predictions of findings 3, 4, 6, 7, 10 and 11 written in. Put open issue 49 to the user at the same time.
2. E-157 with form B as the primary form and the per-call measure; form A only for a concrete and a family-member model.
3. E-158, which needs no TraitWorld work (finding 7).
4. E-159 with the stand-in CommonSolve (finding 8), and the W-36 study beside it.
5. The renumbered W-35, for the block form.
6. E-160 without waiting for W-33, except its inside-the-trait-module half.
7. E-161, folded into an earlier row.

**The NetworkDynamics port meanwhile:** G3, the P4/P6 merge and P4 step 3 are sound and independent of W-34. Step 4 waits for E-157, and under form A also for open issue 49. §4 item 4's "or after W-29 under form B" goes (finding 2).

**The dependency on W-33:** only E-160's inside half and the merge's expectation for plain callers depend on it. The rest needs the lock, not the feature.

## Not checked

- Nothing was run. The no-block family from outside the trait's module (finding 7), the cost of form A on a family member (finding 4) and the missing ownership check (finding 6) are by reading and need E-156.
- SciML's sources were not read beyond what the exploration cites, except CommonSolve's ownership of the front-end functions, which the exploration states (G-C).
