# Open issues

What is open in the design, the implementation, the measurements and the documents, each item as it stands now.

- **The design** is the [references](reference/README.md); the rationale is [`design.md`](design.md); the decisions, with who made them, are in [the decision log](record/decisions.md).
- **The numbers** are in [the evidence](design/evidence.md); each experiment E-n is a row of [the registry](record/experiments.md).
- **Item numbers and the tensions' IDs (`GT-n`) are permanent.** A gap in the numbering is a closed item. The closed items are in [the ledger](../attic/writeup/record/issues-closed.md); the page with each entry's history is [the snapshot of 2026-11-18](../attic/writeup/record/issues-open-2026-11-18.md).
- **How an item is kept:** a principled choice, or one that simplifies at little cost, is adopted; one that experience with trait code would inform waits for the ports; one that evidence can settle names its experiment. Only a choice with a well-articulated trade-off waits for the user (§1).

<a id="1-decisions-waiting-for-the-user"></a>

## 1. Questions for the user

**Q-1. Eight pushed commits name a model in their co-author line.**
- *The case:* the commits "The README for the package as it is; its history to HISTORY.md" in TraitWorld, TraitDifferentialEquations, TraitMakie, TraitTables, TraitCSV, TraitReport, forks and ndport end with "Co-Authored-By: Claude Opus 5.5". An agent wrote them so, and they were pushed before the main session saw it.
- *The options:* (a) leave them; (b) amend each and push with force. The harness refused (b) without the user's word.
- *The recommendation:* (b). Each is the head commit of its branch, and no one else uses the remotes.

- The tensions (§2) and the agent's choices (§3) are input to the next synthesis ([the goals §4](goals.md#4-the-synthesis)). They do not wait for a review one by one.
- A question goes here when the work cannot continue without the user's answer: the question, the options, the recommendation, and the reference section where the answer would land.

## 2. Tensions between the goals

Each entry is a rule of the references that sets one goal against another. The index, with each entry's axes, is [the goals §3](goals.md#3-tensions-between-the-goals). No entry is worked on for speed.

### GT-2. Strict mode infers an image's memberships at its load

Between G-5 and G-4 (load time).
- **The rule** ([traits §5.10](reference/traits.md#510-checks), [§12.3](reference/traits.md#123-strict-mode)): a member's check is its serving instances, kept with their edges and validated with an image. At a load, only the instances that fail validation are inferred again.
- **What it costs today:** the implementation deviates (traits T-129). Strict mode infers every membership of an image at its load. `using TraitTables, TraitCSV` takes 248–250 ms under strict mode and 180–181 ms without it (E-382, `unified`). Strict mode only.
- **The proposal:** build T-129. The tension closes with it.

### GT-3. The compiler and Base are compiled plainly

Between G-4 and G-7, against G-1.
- **The rule** ([facts §6.4](reference/facts.md#64-the-compilers-own-code), [§13.1](reference/facts.md#131-the-product-setting)): the compiler's own code is compiled plainly, and so is Base's code in the product setting. Plain code commits across calls at abstract types, so a plain package's ordinary method can invalidate it.
- **What it costs today** (E-382, E-386, `unified`):
  - Loading upstream CSV and DataFrames logs 605 instances of the compiler, against 122 on vanilla.
  - The session takes 14.1–14.4 s, against 13.5–13.6 s on vanilla.
  - Inference on plain code takes 1.5 times vanilla's (E-389).
  - Base compiled by facts needs a system image of its own: an empty session under the test bed `all` takes 24–25 s without one (E-275).
  - Of the calls a load checks by signature, the costliest edges, 732 of 882 are in plain code that fails G2 (E-325).
- **The proposals:**
  - (1) Measure first: the compiler's module compiled by facts, in a system image so built; inference's speed and the invalidations at load.
  - (2) Where inference slows, declared results at the compiler's hot abstract positions (a trait for lattice elements, one for call infos), found by the dispatch profiler.
  - (3) Meanwhile, the stack's compiler code is held to no dynamic call of Base's generic functions, with `experiments/implementation/e289/dyncalls.jl` as a gate.
  - The library's check code typed throughout would reach Base's methods statically ([PE-28](record/performance-explorations.md)).

### GT-5. A closed type's contract promises no result

Between G-8 and G-7, against G-2.
- **The rule** ([compiler §7.1](reference/compiler.md#71-the-rule), [traits §3.4](reference/traits.md#34-open-and-closed), [§9b](reference/traits.md#9b-streams-io)): the members of a closed type with a contract are unchecked, so each operation's result is `Any`. This is correct for every stream, and it is Julia's own answer at a receiver typed `IO`.
- **What it costs today** (E-340, `unified`): through the eraser `IOContext{IO}`, `write(io, ::Char)` takes 4.99 times the time with the stream's type known, `print` of `"ab"` 2.63 times, the display of a vector 1.09 times. Base's `write(io, ::Char)` adds the counts of its byte writes, a dynamic `+` when each count is `Any`.
- **The proposal:** (a) leave it. Byte-level writes reach the eraser only from code that erased a stream on purpose, and [traits §9b](reference/traits.md#9b-streams-io) keeps such kernels per type.
- **Also considered:**
  - (b) Base's counting writes (`write(io, ::Char)`, `write(io, ::String)`) annotate each count `::Int` where the stream is erased; a stream whose count is another integer type raises there.
  - (c) The eraser's forwarders infer the result from the candidates' joined results. It needs the fallback's result too, and gains nothing while that is `Any`.

### GT-7. The split's pointer per call, and its making per member in each session

Between G-1, against G-2 and G-3.
- **The rule** ([compiler §7.2](reference/compiler.md#72-the-split)): a split's branch calls its candidate's target through a pointer and inlines only a leaf. A member that joins after a loop over the trait is compiled is called through a pointer made at its first use, one per operation and member type.
- **What it costs today** (E-443, `next`):
  - An operation on a box held of the sixth member (the table, through the pointer): 9.14 ns. Of the first member (a branch): 5.56 ns. With the type known: 0.79 ns. Julia's dynamic call of a value held as `Any`: 18.4 ns.
  - Making a pointer costs 8.3–8.6 ms per operation and member (E-358). No image holds it, so each session pays it again.
  - NetworkDynamics' workload is not measured with the pointer: E-327 measured it without.
- **The proposals:**
  - A witness carried in the box (the review's P7 (a)): about 3.6 ns a call past the fourth member, and no pointer to make.
  - The pointer made without compiling per operation and member, or made at a member's image build for each operation of its `@implement`.
  - E-327 again on `next` before the rule is final.

### GT-8. G2 covers the deep class; a port's code outside it is lost through plain callees

Between G-8 and G-1.
- **The rule** ([facts §2.2](reference/facts.md#22-g2-stable-caches), [compiler §3.2](reference/compiler.md#32-g2-as-a-predicate)): G2 holds for code compiled by facts that is deep G2. Facts code that rests on a plain callee outside the class is compiled again when a load ends that callee.
- **What it costs today:**
  - The share in the class (E-478, `next-s3`): the forks' own facts instances 63.1 %; upstream compiled by facts 79.0 %.
  - Nine unrelated loads end no own instance in the class. Below the own code they end 30 and 12, all by SparseArrays' method of Base's `_cat` at Base's types, a standard library's method (item 19).
  - The forks' work after the nine loads: 2.22–2.25 s, against 0.18–0.19 s first (E-392, `unified`); 2.3 s on `next-s3` (E-478). Upstream compiled plainly: 5.17–5.29 s after the loads, against 4.13–4.26 s first (E-392).
  - What keeps the rest out is Base's plain code where types are not known: [item 218](#2-design).
- **The proposals:**
  - (a) Base compiled by facts in the product setting, so that the callees are facts code. GT-3 sets this against the compiler compiled plainly.
  - (b) The boundary flag ([compiler §2.2](reference/compiler.md#22-the-method-flag)) on the Base methods that `experiments/implementation/w134/cause.jl` names, which makes each such call a run-time site.
  - (c) Base's surface by the census's culprits: each a patch to Base that stands without traits ([compiler §11](reference/compiler.md#11-changes-useful-without-traits)). The gate is the share of the class (`experiments/implementation/w157/census.jl`). The rest is item 218.
  - No port is changed to avoid these callees.

### GT-9. The membership machinery costs code that uses no trait

Between G-8 and G-4.
- **The rule** ([compiler §4](reference/compiler.md#4-sets-and-memberships), [§5.1](reference/compiler.md#51-the-method-table)): memberships are consulted in subtyping and in method matching, for every type.
- **What it costs today:**
  - Plain code's repeated work: a median of 0.18–0.19 ms on `next`, against 0.17–0.18 ms on vanilla (E-499).
  - DataFrames' repeated steps on a small table, 8–18 % slower than vanilla (E-356, `unified`): `describe` 19.2 against 17.6 µs, `sort` 8.0 against 6.9 µs, `groupby`-`combine` 45.2 against 40.4 µs.
  - A non-member's `<:` against a set: 1.7–1.8 times an unrelated pair's in vanilla (E-270).
  - Plain code's first work: [item 225](#4-runtime-and-measurements).
- **The proposal:** leave it, and state it as the design's cost to plain code. Which part is dynamic dispatch through the per-call-site and leaf caches is not separated ([PE-24](record/performance-explorations.md)).

### GT-12. The definition-time check runs at each edit

Between G-5 and G-1.
- **The rule** ([traits §11.2](reference/traits.md#112-definition-checking), [compiler §6.7](reference/compiler.md#67-the-definition-time-check)): the check reads the method's instance at the box, which an edit infers once, as the box's next call would.
- **What it costs today:** an edit of TraitTables' `summarize` evaluates in 0.70 s the first time and 0.49 s the second, with the check's code in the system image (E-391, `unified`). The plain twin takes 88 ms and 9 ms (E-379). On `next` the check reads the box's instance (compiler C-115), but the edit is not timed there.
- **The proposals:**
  - Time E-391's edit again once TraitTables follows the design. The tension closes if the edit then costs what the box's first call costs.
  - (b) The check's inference results kept between checks, as the native interpreter's are, and ended as code is.
  - (c) The check of an edited method deferred to its first call, with the definition's error raised there. It sets the place of the error (G-5) against the edit's time.

### GT-14. A membership is seen from the world of its declaration

Between G-1, against G-5 and G-7.
- **The rule** ([compiler §4.3](reference/compiler.md#43-worlds), [facts §10](reference/facts.md#10-memberships)): a membership has a world, as a method has. Code that runs in an earlier world does not see it: a function that evaluates a declaration or loads a package and goes on, or a task started before.
- **What it costs today** (E-362, case 08; E-385): a function declares a member and stores a value of it in a `Vector{Shape}`.
  - The trait form raises `MethodError`: "Cannot `convert` an object of type Circle to an object of type Shape. The applicable method may be too new: running in world age …".
  - The plain twin runs: a subtype is seen at once, in every world.
  - The message names a method and a world, not the membership. A program that loads plugins from a running loop meets it.
- **The proposals:**
  - (a) A hint on that `MethodError`, and on a `TypeError` at a set: where the value's type has a membership in the set in a later world, the message says so and names `invokelatest`.
  - (b) `intro/` teaches a membership as a definition, with a method's rule for running code. Since a membership invalidates as a method does, its world is a method's world in every respect, and (b) is the whole account.
  - (c) No change to the worlds: a membership seen at once would change the answers of code running in an older world.
- The tool: `experiments/implementation/w136/` (case 08, both forms).

### GT-16. Fully typed mode raises exactly where a build refuses, or fully typed code pays nothing

Between G-6 and G-5, against G-1.
- **The rule** ([traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode), [compiler §2.7](reference/compiler.md#27-fully-typed-mode)): the mode's check is a prologue that the compiler puts only into code where the session's inference found a run-time site. The prologue asks the build's check.
- **What it costs today:** a call that only the build refuses, inside plain code the method calls, is reported by `fully_typed` and not raised (traits T-100). A plain caller that inlines the method runs it without the prologue (traits T-104). The other way costs time: the build's check takes 2 to 5 s for a small program and 4 to 11 s for a demonstrator's (E-369). Asked at the first run of every signature in the mode, that would be the price of fully typed code too.
- **The proposal:** keep the rule. The exact question is `fully_typed`'s, asked in a package's tests and before a build, where seconds are acceptable.

### GT-21. Calls that only throw keep a port's code out of the deep class

Between G-1 and G-4.
- **The rule** ([compiler §3.2](reference/compiler.md#32-g2-as-a-predicate), [facts §13.1](reference/facts.md#131-the-product-setting)): the deep class follows every edge to a callee, and plain code keeps Julia's edges. Base's throwing helpers, every plain caller in Base that holds an edge to one, and a port's code above them are outside the class.
- **What it costs today:**
  - With Base's throwing helpers patched to build their exceptions at fact signatures (E-478, `next-s3`), the own image instances in the class are 68.9 % (the forks) and 79.5 % (upstream compiled by facts).
  - A rule that dispatched such a call when it runs would move the forks' own image instances in the class from 1,983 to 1,986 of 4,799 if taken in code compiled by facts only, and to 2,917 (61 %) if taken from every caller, plain code included (E-416 (c), `next`). The gain lies in plain code, whose behaviour the product setting keeps as Julia's.
  - What is left of the kind: error paths at a value whose type is abstract where it is called (`throw_boundserror` at a `Vector` or `Memory` of unknown element type, `kwerr` at abstract arguments, `AssertionError(::Any)` from `@assert`'s message). 140 culprit instances in 42 names, in 460 cones; none buys a share alone (E-478). They sit in item 218's generic paths.
- **The proposals:**
  - (a) Patch the rest as Base's surface reaches them (item 218 (d)).
  - (b) The rule in code of either policy: such a call dispatched when it runs, its result `Union{}` asserted, holding an edge that a redefinition of the callee reaches and the callee's own invalidation does not. Julia has no such edge (item 219 (a) is the same form). It changes plain code where a change below the callee makes it return: a `TypeError` where Julia goes on.
  - Or accept, as item 218 (e).

### GT-31. Strict mode secures the deep class only

Between G-5 and G-1.
- **The rule** ([facts §11.2](reference/facts.md#112-strict-mode), [traits §12.2](reference/traits.md#122-pirates), [§12.3](reference/traits.md#123-strict-mode)): strict mode's walk and the pirate report read the deep class only, so that a load costs nothing measurable (E-457).
- **What it costs today** (E-498, `next`): E-385's `05_pirate`, a module that owns neither defines `Base.uppercasefirst(::String)`. The library's `title(s)`, compiled by facts in a trait module, calls it, and rests on Base's plain `uppercasefirst`, outside the class. Under strict mode the case runs to its end and prints the pirate's result. One of E-385's fifteen mistakes reaches its end silently.
- **The proposals:**
  - (b) The report names a pirate that ends code compiled by facts outside the class too, under strict mode only, where its cost is accepted.
  - (c) Base's patches bring such callees into the class (GT-8 (c)).
  - (a) Under strict mode the walk refuses a pirate that ends any code compiled by facts, deep or not, at the walk's cost over the share outside the class.
  - The proposal is (b), with (c) as Base's surface reaches the callees.

### GT-32. A callable struct that is no `Function` is no member of `Callable` until its owner declares it

Between G-8, against G-7 and G-4.
- **The rule** ([traits §9](reference/traits.md#9-functions-callable), [compiler §7.4](reference/compiler.md#74-callables-call)): every `Function` is a member of `Callable` by Core's entry. A callable type that is no `Function` is a member only by `@implement Callable T`. Membership stays declared, so subtyping reads no method.
- **What it costs today** (E-500):
  - Of the 174 callable types loaded in the forks' session, 134 are no `Function` (Interpolations 18, FastInterpolations 23, Makie 8, Accessors 4, DataFrames 2, …). In the demonstrators' session, 35 of 67, among them ODECore's `ODESolution` and LinearAlgebra's `UniformScaling`.
  - Such an object passed where `Callable` is asked raises `MethodError`, where Julia's `map` takes it.
  - The ODE port needed 14 declarations, and its tests 5.
  - A caller may declare the type (a pirate's membership, warned) or pass a closure, `x -> itp(x)`.
  - A type passed as a constructor is no member either: upstream Tables' test `ByRow(Dict)` errors in the forks (E-504; [item 240](#2-design)).
- **The proposals:** [item 227](#2-design); for a type, item 240.

## 3. The agent's choices

Choices made while building. Each stands as recorded, in its reference and in [the decision log](record/decisions.md) marked "mine", and is input to the next synthesis.

**Erasing: the box and the wrapper**
- The closed rules apply to what a build compiles for its output, and a build loads its program with the library's hooks, the library calling its own `__init__` at load under `--trim`; a call that takes the wrapper of a value known only by its trait branches over the members, the wrapper typed `Compiled{<:X}` where its members are more than a union keeps; a loop that wants a member's own code hands it over as `compiled_for(x)`, which costs the table's session about 10 ms of load for the wrapper's instances; one method of an equation's function per kept form, not one per trait. [compiler §7.6](reference/compiler.md#76-a-closed-build), [lowering §2](reference/lowering.md#2-trait).
- In a closed build: a type that one entry makes a member of every instance of a set is a member by use at each instance (compiler C-155); the call of a function known only as bare `Callable` branches over its members by use; a constant the code holds is read for the members in its fields; the verifier takes an invoke as resolved only by code of the policy the call asks; the member split over several arguments is their product within 64 branches. [compiler §7.6](reference/compiler.md#76-a-closed-build); [decisions](record/decisions.md).
- The closed build's members as built: an argument declared at a set is not compiled at `Function` by Julia's rule for an uncalled function argument; "no member" is asked in the build's last rounds; a method at a kept form chooses by member; the call of a function known only as `Callable{A, S}`, and the box's test at it, branch over the signature's members in a closed build. [compiler §7.6](reference/compiler.md#76-a-closed-build), [§6.3](reference/compiler.md#63-the-forwarders); [decisions](record/decisions.md).
- In a closed build a call where the member's type chooses a method at a type that is no set branches over the members; a set instance's members by use are the types that flow to a place typed by it, not every type forgotten under the set; a kept form is a member by use, so the object a box holds has no box branch. [compiler §7.6](reference/compiler.md#76-a-closed-build); [decisions §15](record/decisions.md).
- A closed build runs any call at a value known only by its trait at the call's types, the set instance, and branches only where the value binds a method's static parameter; a box of another set is no member, whatever it holds; `@nospecialize` at a trait argument is Julia's, with `Base.@nospecializeinfer` where inference should stay at the trait; a `Callable` argument with `A` or `S` left open takes the function as it is. [compiler §6.2](reference/compiler.md#62-how-an-argument-is-compiled), [§6.9](reference/compiler.md#69-the-kept-forms-in-core), [§7.6](reference/compiler.md#76-a-closed-build), [traits §9](reference/traits.md#9-functions-callable); 
- Two instances of one set meet where they may differ in an input, and are disjoint where they agree in every input and differ in another parameter; so two methods at `Callable` instances tie for every function. The lookup keeps a match at an unmet intersection of two instances, as of two sets (item 239). [compiler §4.9](reference/compiler.md#49-intersections).
- The runtime asks the library where a method is defined, and the library answers the methods one definition makes; one statement flag carries inference's proof of a statement's type tests to code generation; the forwarder is compiled once where the other arguments fix the trait's parameters, per member type otherwise, and makes its box by `new`; a `where` variable another argument names, and a `Callable` whose variables only its argument binds, are not boxed; the box of one `Callable` signature is called at its own parameters; the walk replays a method at a bound at the method's own signature; the check infers apart only where Julia's cache keeps no code. [compiler §6.3](reference/compiler.md#63-the-forwarders), [§6.7](reference/compiler.md#67-the-definition-time-check), [traits §7.8](reference/traits.md#78-erasing-by-default-the-forwarder); [decisions §3](record/decisions.md).
- A trait whose parameters a method leaves open erases too: the forwarder lifts the open parameters into its static parameters and boxes at the member's instance; an input left open takes the plain member as it is. [traits §7.8](reference/traits.md#78-erasing-by-default-the-forwarder); [decisions §3](record/decisions.md).
- The wrapper is `Compiled{T}`; one forwarder per positional arity, keywords passed whole, several trait arguments boxed by one forwarder; an argument erases when typed by a trait with the default, by `Callable`, by an intersection with such a component, or by a `where` variable bounded by one; the trait's own methods are not forwarded; no type is exempt; a box of the same trait is itself; the wrapper's call method takes any arguments. [traits §7.4](reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper) to [§7.8](reference/traits.md#78-erasing-by-default-the-forwarder); [decisions §3](record/decisions.md).
- `Kept{X}` is not a type: a container typed by the trait holds each form by its own type; the forwarder is `@nospecialize`; both kept forms are in `Core`; the forwarders are made by the runtime's method definition, each recording its method, and the methods `@trait` makes are marked `:no_forwarder`; Julia's default outer constructors are forwarded; a closed build branches the wrapper's constructor over the members; nothing is compiled ahead per member for a method that erases. [traits §7.6](reference/traits.md#76-compiled_forx), [§8.1](reference/traits.md#81-fields-and-containers-typed-by-a-trait), [compiler §6.9](reference/compiler.md#69-the-kept-forms-in-core); [decisions §3](record/decisions.md).
- `Callable` at the box: every subtype of `Function` is a member by one entry of Core's, a callable type that is no `Function` by `@implement Callable T`; the box's refusal is a `MethodError` with a hint; a wrapper is checked at entry for `A`, and refused where its result inferred at `A` lies outside `S` (a result inference cannot tell apart from `S` is returned unchecked); its calls are the function's own; a box's call is a dynamic call. [traits §9](reference/traits.md#9-functions-callable), [compiler §7.4](reference/compiler.md#74-callables-call); [decisions §3](record/decisions.md).
- `Callable` in the build: `Function`'s entry is declared in Base's build, after the `IO` contract; the wrapper's test is an entry method at the wrapper's form that invokes the method as written (compiler C-146); at a forwarder the refusal is the `MethodError` of the method's own call (traits T-156); the forwarder is compiled per function, so that the test folds; a package that knows no trait makes its callable struct a `Function`, by Julia's idiom. [compiler §6.3](reference/compiler.md#63-the-forwarders), [§7.4](reference/compiler.md#74-callables-call); [decisions §3](record/decisions.md).
- Bounded at the box: the faults are no method, or a call that only throws, and a call left to run time that finds a method is no fault; free variables are read at stand-ins; a keyword method's body is read, the forwarders not; a method whose box cannot be formed is not read, and nothing is checked at a first call; an equation's function answers at the kept forms (traits T-130). [traits §7.3](reference/traits.md#73-bounded-methods), [§7.4](reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper); [decisions §2](record/decisions.md).
- A function passed as itself and known only as `Callable{A, S}` (a `@nospecialize` argument, compiled once) is called as a box is: its arguments checked against `A`, its result asserted to `S`. [compiler §7.4](reference/compiler.md#74-callables-call), [traits §9](reference/traits.md#9-functions-callable); [decisions](record/decisions.md).
- A vararg of members does not erase: its elements are passed as they are, the method compiled per tuple of their types; the bounded check reads it with each element in a box, the code a call that passes boxes runs. In the check a tuple that holds a value at the box is one, and a call left to run time that never returns only throws. [traits §7.3](reference/traits.md#73-bounded-methods), [§7.8](reference/traits.md#78-erasing-by-default-the-forwarder); [decisions](record/decisions.md).
- `withfields` on a box rebuilds the object it holds and boxes the result at the same trait; on a wrapper it gives the wrapper of the rebuilt object; at a box only the fields the trait declares are named. [traits §6.5](reference/traits.md#65-results), [lowering §8](reference/lowering.md#8-like-and-withfields); [decisions §4](record/decisions.md).

**Operations and contracts**
- A required operation is written as `(function, declared signature as a tuple type, declared result, the default's method or nothing)` in a `TypeName` slot of its own, by `jl_set_contract_operations`; a default's method keeps the rule for its further arguments; the contract's hint is given where an argument at the receiver position is a member, and not at another owner's function; `Method.declared_covers` is kept with no reader; the kept forms' forwarding methods read their object through `_fwd`; an untyped method serves an operation without a default. [compiler §4.1](reference/compiler.md#41-sets), [lowering §2](reference/lowering.md#2-trait); [decisions §1](record/decisions.md).
- A forwarding member serves each required operation by a method of its own; `Dynamic{X}` has forwarding methods of its own. [traits §5.5](reference/traits.md#55-forwarding-with-by), [lowering §2](reference/lowering.md#2-trait); [decisions](record/decisions.md).
- A default's method types only its receiver, and a further argument only where it binds an input, so a member's own method wins. [lowering §2](reference/lowering.md#2-trait); [decisions §9](record/decisions.md).
- A declared result is asserted, never converted; a closed type's contract promises no result. [traits §3.4](reference/traits.md#34-open-and-closed), [§7.9](reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait), [compiler §7.1](reference/compiler.md#71-the-rule); [decisions §9](record/decisions.md).
- A contract is declared in the image that defines the type, its candidates fixed with it. [compiler §7.1](reference/compiler.md#71-the-rule), [§7.2](reference/compiler.md#72-the-split); [decisions](record/decisions.md).
- `IO`'s contract: its operations are Base's methods at `::IO`; `eof`, `isopen` and `close`, which have none, are not operations; the candidates `IOBuffer`, `IOStream`, `TTY` and `PipeEndpoint` are registered by Base first; the contract is written on the type's `TypeName` (`jl_declare_contract(T, ops)`). [traits §9b](reference/traits.md#9b-streams-io), [compiler §7.5](reference/compiler.md#75-io); [decisions §9](record/decisions.md).
- An operation declared `::Self` declares the set at the receiver's parameters. [compiler §6.8](reference/compiler.md#68-a-declared-result-on-method); [decisions §9](record/decisions.md).
- Lowering records `f(…)::RT` for a type known at the definition only: constants, a module's constant bindings, literals and the method's static parameters. [compiler §6.8](reference/compiler.md#68-a-declared-result-on-method); [decisions §9](record/decisions.md).
- A set's inputs are a byte on its `TypeName`; a field named by an input declares a property, so `HasProperty{N, R}` is `@const N::R` with `@input N`. [traits §4.3](reference/traits.md#43-fields), [compiler §4.6](reference/compiler.md#46-one-instance-per-member); [decisions §9](record/decisions.md).
- A family's variables are in scope in its block's methods. [traits §5.8](reference/traits.md#58-families); [decisions §9](record/decisions.md).
- Two traits' operations of one function: a joint method where one answer is right for every common member, else the pair is named in the package's tests; BaseTraits' `getindex` of `Indexable` and `Keyed` stays a named pair. [traits §6.3](reference/traits.md#63-ambiguity); [decisions](record/decisions.md).
- BaseTraits' contracts follow the prior art: `Iterable` repeatable, `Indexable` with `firstindex`, `MutableIndexable` with `BitVector` and views, `Resizable{T}` by `push!` and a shrinking `resize!`, `Keyed`'s `get` with any default, sets and strings members. [traits §10.1](reference/traits.md#101-basetraits); [decisions §9](record/decisions.md).
- `Solvable` by LinearAlgebra's `ldiv!`; `LinearOp` by BaseTraits' `apply!`; `BoundedText` a constant per type, with `textbound(T)`. [traits §10.1](reference/traits.md#101-basetraits); [decisions](record/decisions.md).

**Checks and messages**
- A check's error is raised at the user's line; an operation called outside its declared signature raises Julia's `MethodError` with the contract's hint. [traits §11.3](reference/traits.md#113-errors-and-their-messages), [compiler §10.1](reference/compiler.md#101-definition-and-image-hooks); [decisions §2](record/decisions.md).
- A method is bounded or unbounded, with `@unbounded`; *open* is kept for traits and types. [traits §7.3](reference/traits.md#73-bounded-methods); [decisions §9](record/decisions.md).
- The form of a message: a signature as a call, a refused method headed as such, a field named, a declaration's code at the declaration; `ImplementError` has a field `method`; "outside the declared result" for a result that is no supertype of it; a bare option name at `@trait_module`; no hint at an operation that is another owner's function. [traits §11.3](reference/traits.md#113-errors-and-their-messages), [§11.4](reference/traits.md#114-hints); [decisions §2](record/decisions.md).
- A member's check holds while it is a member: a later method that would serve a checked call outside the declared result, make the operation ambiguous at the member, or take a call that a default or the forwarding serves is refused before it exists, with `ImplementError`; an image's such method is left inactive with a warning; a pirate in another module is refused too. [traits §5.10](reference/traits.md#510-checks), [§5.11](reference/traits.md#511-overrides-and-redeclaration); [decisions](record/decisions.md).
- A member by its definition declares its entry, and its parameters come from the definition; the order of a member's `@implement`s does not decide which membership strict mode refuses. [traits §5.2](reference/traits.md#52-with-the-types-definition), [lowering §3](reference/lowering.md#3-implement); [decisions](record/decisions.md).
- A member by its definition used before its `@implement` raises `ImplementError`. [traits §5.2](reference/traits.md#52-with-the-types-definition), [compiler §10.4](reference/compiler.md#104-the-member-hook); [decisions](record/decisions.md).
- The member hook runs in the compile queue: inference runs no check, it notes the member, and the queue asks the hook before the code runs; the runtime keeps the answer per member and set; a use whose check failed stays a dynamic call; callers compiled while a check failed are compiled again once it passes (compiler C-31). [compiler §10.4](reference/compiler.md#104-the-member-hook); [decisions](record/decisions.md).
- An image keeps the member checks that passed while it was built, as a list beside its memberships; a failure is not kept. [lowering §11](reference/lowering.md#11-checks-errors-and-what-images-keep); [decisions §7](record/decisions.md).
- `like`'s rebuilding of a forwarding member is a method made at its `@implement … by f`; `withfields` makes the constructor's call when compiled; a type without the positional constructor gets Julia's `MethodError` at the constructor, with a hint. [lowering §8](reference/lowering.md#8-like-and-withfields); [decisions §9](record/decisions.md).

**Ownership, pirates and strict mode**
- A function is declared owner-only by `@owner_only f g` at its module's top level; the compiler's test is `is_owner_only`, a flag on the function's binding beside its `public` flag, or the module's option `owner_only` with its `public` and export lists; the default holds for trait modules only, with `public` as the guideline for a function others extend; a later `public` or `export` is the owner's change and ends the code that relied on the function's being owner-only (compiler C-130). [facts §3](reference/facts.md#3-fact-signatures), [compiler §1.2](reference/compiler.md#12-fact-signatures), [traits §12.2](reference/traits.md#122-pirates); [decisions §4](record/decisions.md).
- A membership is taken back by `delete_membership(X, S)`: the entry is ended and the membership's method deleted in one world, with the insertion's walk run for the removal; who may is who may declare it; strict mode's rule is a method's deletion's; a member by its definition, a supertrait's and `Dynamic{X}`'s memberships are not taken back alone; values stored before stay; the keyword `by` names who takes it back; the library's extension for Revise lists an expression's memberships (lowering L-64). [traits §5.13](reference/traits.md#513-taking-a-membership-back), [compiler §4.3](reference/compiler.md#43-worlds); [decisions §4](record/decisions.md).
- What strict mode's check before a pirate's membership misses is undone as a method's is: the membership is taken back and refused; at an image's load a family's membership is checked for the folded answers only (traits T-112). [traits §5.13](reference/traits.md#513-taking-a-membership-back), [§12.3](reference/traits.md#123-strict-mode); [decisions §4](record/decisions.md).
- The pirate report is switched off by `TraitWorld.report_pirates!(false)` and `JULIA_TW_PIRATES=0`; the runtime's list `jl_take_deep_endings()` is filled only where deep-G2 code ends; an image's code that a pirate makes invalid at the load is reported too. [traits §12.2](reference/traits.md#122-pirates), [compiler §10.2](reference/compiler.md#102-hooks-for-strict-mode); [decisions §5](record/decisions.md).
- The warning at an extension's method under strict mode. [traits §12.3](reference/traits.md#123-strict-mode); [decisions](record/decisions.md).
- Strict mode refuses a membership that makes methods ambiguous; at an image's activation the ambiguity is reported, not refused, at error level after the load, and kept; an ambiguity among an image's own memberships and methods is refused at its precompile under strict mode. [traits §6.3](reference/traits.md#63-ambiguity), [§12.3](reference/traits.md#123-strict-mode), [compiler §10.2](reference/compiler.md#102-hooks-for-strict-mode); [decisions](record/decisions.md).
- Strict mode refuses the membership that creates an ambiguity, not a later one. [compiler §5.4](reference/compiler.md#54-the-ambiguity-report-at-a-membership); [decisions](record/decisions.md).
- The ambiguity report asks each method a membership makes applicable against the method table at the member: a match counts only where it covers the member itself; one warning per method, with every tied method and their joint signature; a tie that arises only at a type with the member as its parameter (`Vector{S}`) is left to the call; a tie with a method at `Any` is reported and refused like any other. [compiler §5.4](reference/compiler.md#54-the-ambiguity-report-at-a-membership), [traits §6.3](reference/traits.md#63-ambiguity); [decisions](record/decisions.md).
- A trait package's front end belongs to a trait module. [the porting guide](intro/porting.md); [decisions §8](record/decisions.md).

**Memberships, worlds and dispatch**
- A call records no cell; a membership replays the trait's methods at its member and invalidates the callers whose selection changes. [compiler §5.5](reference/compiler.md#55-a-membership-invalidates-as-a-method-does); [decisions §4](record/decisions.md).
- The membership walk substitutes the member below a position's top: under a union, in a tuple's component, in an intersection, in a type's declared bound. [compiler §5.5](reference/compiler.md#55-a-membership-invalidates-as-a-method-does); [decisions §5](record/decisions.md).
- An image's memberships run the walk and the ambiguity report at load, as a declaration does. [compiler §9](reference/compiler.md#9-images-and-the-machine-code-cache); [decisions §9](record/decisions.md).
- Activation ends an older entry in force for the same member, set and inputs. [compiler §4.6](reference/compiler.md#46-one-instance-per-member), [§9](reference/compiler.md#9-images-and-the-machine-code-cache); [decisions](record/decisions.md).
- A non-membership is relied on wherever the code is compiled: while a declarer loads, for a type or trait of `Main`, for a concrete type, and for an abstract type whose intersection with the trait no type is in. [compiler §4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries); [decisions §4](record/decisions.md).
- A test `x isa X` at a set narrows the true branch to the set; no negative is folded. [compiler §4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries); [decisions §5](record/decisions.md).
- An intersection no type is in, at a set closed after load, is a final negative with a cell. [compiler §4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§5.4](reference/compiler.md#54-the-ambiguity-report-at-a-membership); [decisions §9](record/decisions.md).
- `All{X, Y}` is encoded as the abstract type `Core.All{Tuple{X, Y}}`, with branches at every site that reads a type's name, supertype or parameters. [compiler §4.9](reference/compiler.md#49-intersections); [decisions §9](record/decisions.md).
- The library exports `All`; `Core` does not, so a module that uses DataAPI's `All` too qualifies one. [traits §3.6](reference/traits.md#36-intersections); [decisions §9](record/decisions.md).
- An open set meets an abstract type as `All{X, T}`: a query at an abstract type sees the methods at sets. [compiler §4.7](reference/compiler.md#47-three-layers), [§5.3](reference/compiler.md#53-match-world-ranges-and-abstract-queries); [decisions §9](record/decisions.md).
- Disjointness is decided in the runtime, by reachability and the typemap's world range; the call cache has no exact-type entries. [compiler §4.7](reference/compiler.md#47-three-layers), [§8.2](reference/compiler.md#82-the-per-call-site-dispatch-cache); [decisions §9](record/decisions.md).
- Method matching asks a pair with a method at a set, and a recorded interference between two methods at open sets, again in the query's world. [compiler §5.2](reference/compiler.md#52-specificity); [decisions §9](record/decisions.md).
- The query world is the task's, restored by exception handlers as the world age is. [compiler §4.11](reference/compiler.md#411-inferences-world); [decisions §9](record/decisions.md).
- Dispatch's lookup keeps a match met only at an intersection no type is in at an open set, and drops it at a final pair with its cells; a `Callable` component and a `Vararg` tail are met. [compiler §5.4](reference/compiler.md#54-the-ambiguity-report-at-a-membership); [decisions §9](record/decisions.md).
- A method whose signature mentions a set is listed unindexed only at the set's position. [compiler §5.1](reference/compiler.md#51-the-method-table); [decisions §9](record/decisions.md).
- A dispatch edge keeps the call's signature where the call reached an instance wider than its own match. [compiler §3.1](reference/compiler.md#31-the-record); [decisions §9](record/decisions.md).
- Sets in Base's build: Core and Base count as loaded once Base's last definition has run; a split's branch runs the serving method compiled for its candidate; `detect_ambiguities` reports a pair at a set and a type only once a membership makes them meet. [compiler §4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§5.4](reference/compiler.md#54-the-ambiguity-report-at-a-membership), [§7.2](reference/compiler.md#72-the-split), [§9](reference/compiler.md#9-images-and-the-machine-code-cache); [decisions §9](record/decisions.md).

**The deep class, the facts rule and Base**
- The deep class is the G2 bit, decided at a CodeInstance's finish from its edges' bits: an inference cycle is decided as one; a callee named by its MethodInstance alone is outside the class, and the edge names the callee's code where it exists when the caller finishes; a membership's method counts as a fact. [compiler §3.2](reference/compiler.md#32-g2-as-a-predicate); [decisions §4](record/decisions.md).
- A call that only throws keeps its edge: it is not taken as a run-time site (the plan's D-6 is not taken; GT-21). [decisions, superseded](record/decisions.md).
- Base's surface: a culprit is fixed in Base where a patch keeps every result; an error path builds its exception at a concrete signature; Base's code that knows the method it means calls it through `invoke` and reads type fields with `getfield`; a call at a value typed `Any`, an abstract type or a kind is not patched in general; no function of Base is declared owner-only; the edge of `!==` keeps the call's signature. [compiler §11](reference/compiler.md#11-changes-useful-without-traits), [§3.1](reference/compiler.md#31-the-record); [decisions §5](record/decisions.md).
- No method of Base carries the boundary flag in the product setting. [compiler §2.2](reference/compiler.md#22-the-method-flag); [decisions §9](record/decisions.md).
- An instance's code is compiled once per result: a compile request's CodeInstance takes the code of any equivalent entry of its instance's cache. [compiler §3.3](reference/compiler.md#33-one-compiled-code-per-result); [decisions §5](record/decisions.md).
- An image holds the code that a facts run-time site reaches whatever the values, for all modules. [compiler §9](reference/compiler.md#9-images-and-the-machine-code-cache); [decisions §9](record/decisions.md).
- The stack carries the changes to Julia that are useful without traits, one commit each; `known_type`, the registry of type printers and the per-call-site cache's exact-type entries are not carried; the dispatch profiler is carried without its split by owner, the reflection fix and the two inliner changes without their facts halves. [julia-changes §7.1](design/julia-changes.md#71-the-stack); [decisions §8](record/decisions.md).
- The library is TraitWorld, branch `unified`. [decisions §9](record/decisions.md).

**Fully typed, and compiling ahead**
- One statement of what is final: a call is inferred across where its dispatch is settled; what is final is the one input that differs between a session and a closed build; a trimmed build is the facts rule with everything final; fully typed is one definition with the setting as its parameter; `fully_typed`'s report lists apart the calls a build resolves and a session leaves to run time, and `isfullytyped(report; session = true)` answers for a session (traits T-122). [facts §3](reference/facts.md#3-fact-signatures), [traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode), [compiler §2.7](reference/compiler.md#27-fully-typed-mode); [decisions §6](record/decisions.md).
- Fully typed mode is in the compiler, explained by the library; an abstract result raises `AbstractTypeError`. [compiler §2.7](reference/compiler.md#27-fully-typed-mode), [traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode); [decisions §9](record/decisions.md).
- The check that answers for a build is the build's own code, run in the session; fully typed mode raises only where it lists a call (traits T-100); `make_executable` runs it first. [compiler §2.7](reference/compiler.md#27-fully-typed-mode), [traits §16](reference/traits.md#16-compiling-ahead-closed-programs); [decisions §6](record/decisions.md).
- The check infers against the Base a build compiles, read from the build script's files into an overlay method table; the session's methods are not changed; what the script changes that is no method is not read (traits T-109). [traits §16](reference/traits.md#16-compiling-ahead-closed-programs); [decisions §6](record/decisions.md).
- A closed build's members by use are the types forgotten at a place typed under the trait (a field, an element, an argument, a result, a join, an assertion, a constant's contents), or at a wider place that a test narrows to the trait. [compiler §7.6](reference/compiler.md#76-a-closed-build); [decisions §6](record/decisions.md).
- In a closed build the split holds the box `Dynamic{X}`, splits over at most 64 members, and code inferred before every member was declared is inferred again. [compiler §7.6](reference/compiler.md#76-a-closed-build); [decisions §6](record/decisions.md).
- A function written at the prompt is built from the definitions it depends on, selected by name from the prompt's history; every method of a function reached is replayed; a global the function reads must be a `const`. [traits §16](reference/traits.md#16-compiling-ahead-closed-programs); [decisions §6](record/decisions.md).
- `make_executable` and `make_library`: the build's process loads the function's file or package. [traits §16](reference/traits.md#16-compiling-ahead-closed-programs); [decisions §6](record/decisions.md).
- `verify_main` lists the members and instances at a value known only by its trait, and reports `entrypoints` and `complete`; `add_entrypoints(report)` gives them to a build. [traits §16](reference/traits.md#16-compiling-ahead-closed-programs); [decisions §6](record/decisions.md).
- A trimmed image marks every module as never compiled by facts. [compiler §2.6](reference/compiler.md#26---trim); [decisions §6](record/decisions.md).
- Compiling ahead asks for the instance that a static call at the member runs. [lowering §12](reference/lowering.md#12-compiling-ahead); [decisions §9](record/decisions.md).

<a id="2-design"></a>

## 4. Design

Each item: the case, the rule that blocks it, the proposal, and the experiment where one measured it.

### Traits

**147. Keys for traits with operations only.**
- *The case:* a trait that only guarantees that functions of given signatures exist declares no fields. Under [the key](reference/extensions.md#11-the-key), a member that serves an operation by its own method is its own receiver, so each member is its own key and keys share nothing. Only members served wholly by the trait's defaults share one.
- *The rule:* keys are an optional extension ([extensions §1](reference/extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike)); no rule of the four references depends on them ([PE-33](record/performance-explorations.md)).
- *To investigate,* if a measurement asks for keys: a key that names what the operations resolve to rather than the member's type, so that members whose operations select the same methods share a bounded method's code. Which guarantee it gives, what invalidates it, and how it relates to `Dynamic{X}`.

**134. A constant per implementation.**
- *The case:* NetworkDynamics' `ND.pdim(::Swing) = 3` and a record's `psym` are two sources of one fact, checked equal when the record is built (E-247).
- *The proposal:* an associated constant in the trait, a value declared per implementation as an associated type is, so that the record reads it.

**151. Linear algebra's further operations.**
- *The case:* the adjoint and transposed solves, several right-hand sides, the five-argument `mul!(y, A, x, α, β)` and `*` as a default ([the research](record/collection-and-linalg-traits-research-2026-11-07.md) §3.2, §3.4). SciML's adjoint sensitivities and Krylov paths need them.
- *The proposal:* `AdjointSolvable{T} <: Solvable{T}` by `ldiv!` at `adjoint(F)`, and `LinearOp`'s defaults, once a port asks.

**152. Mixed precision.**
- *The case:* `T = eltype(Self)` ties a solver's or operator's vectors to its element type, so an `LU{Float32}` cannot solve for `Float64` vectors, as iterative refinement does ([the research](record/collection-and-linalg-traits-research-2026-11-07.md) §3.6).
- *The proposal:* the vectors' element type a `where` variable of the operation.

**153. Defaults defined in terms of each other.**
- *The case:* a trait with two defaults that call each other passes a member that serves neither, which then recurses ([the research](record/collection-and-linalg-traits-research-2026-11-07.md) §3.2).
- *The proposal:* a minimal complete definition declared in the trait and checked at each membership.

**154. Keys of another type.**
- *The case:* `haskey(d::Keyed{String}, k::SubString)` is outside the contract, though Base's dictionaries take an equal key of another type (Rust's `Borrow<Q>`; [the research](record/collection-and-linalg-traits-research-2026-11-07.md) §1.2).

**155. Single-pass iteration.**
- *The case:* generators, `eachline` and `Iterators`' adapters are no `Iterable`, which promises repeatable iteration ([traits §10.1](reference/traits.md#101-basetraits)).
- *The proposal:* `IterableOnce{T}` as `Iterable`'s supertrait ([the research](record/collection-and-linalg-traits-research-2026-11-07.md) §1.1).

**156. The iteration state is `Any`.**
- *The case:* a loop over a value known only as `Dynamic{Iterable{T}}` boxes the state at each step.
- *To measure:* items per second against a `Vector`, before a port's hot loop runs on such a value.

**177. Where a port's messages fall short of upstream's.**
- *The case* (E-363, SciML's three error cases): none is a mistake against a contract, so the port's messages are those of its plain twin, 1.2 to 1.7 times as long; upstream's hand-written explanations say more in two of the three.
- *The proposals:* a `Callable` whose result infers `Union{}` at its declared arguments (it always throws: `p[1]` at `p::Nothing`) is refused where the function enters, with the declared signature ([traits §9](reference/traits.md#9-functions-callable)), so the first case is caught at `ODEProblem(…)` or `solve`; a port writes its explanations as upstream does, by a method of its own error type, which no rule gives or prevents.
- *The tool:* `experiments/implementation/w136/` (`run.sh`, `summarize.py`): each mistake in both forms, the message's lines, bytes and frames.

**226. The kept forms' forwarding methods are listed among Julia's closest candidates.**
- *The case* (E-498): E-385's `03b_wrong_operation_argument`, `scale(Circle(1.0), 2)` for `scale(s::Scalable, k::Float64)`, raises a `MethodError` at the user's line with the contract's hint: 11 lines, 743 bytes. Four of the lines name `scale(::Compiled{<:Scalable}, ::Float64)` and `scale(::Dynamic{<:Scalable}, ::Float64)`, which the call's member never reaches.
- *The rule* ([traits §4.1](reference/traits.md#41-operations), [§11.3](reference/traits.md#113-errors-and-their-messages)): a kept form serves an operation by a forwarding method of its own, a method of the operation's function like any.
- *The proposals:* (a) Julia's list of candidates skips a method marked as a kept form's forwarding where no argument of the call is a kept form (a mark the library sets, read by `show_method_candidates`); (b) accept it. The proposal is (a).

**227. A plain package's callable object is no `Callable` member** (GT-32).
- *The case* (E-500): `at(g::Callable{Tuple{Float64}, Float64}, x::Float64) = g(x)`; `at(linear_interpolation(xs, ys), 1.5)` raises `MethodError: no method matching at(::Interpolations.Extrapolation{…}, ::Float64)`. The library's hint names the declaration. After the caller's own `@implement Callable Interpolations.Extrapolation` (a pirate's membership, warned) the call runs.
- *The rule* ([traits §9](reference/traits.md#9-functions-callable), [compiler §7.4](reference/compiler.md#74-callables-call)): every `Function` is a member by Core's entry; a callable type that is no `Function` only by its declaration.
- *The counts* (E-500, `experiments/implementation/w161/d2/functors.jl`, every type with a call method in a session: a `Function`; declared; neither): the forks' session 40, 0, 134; the demonstrators' session 18, 14, 35.
- *The proposals:*
  - (a) Core's entry covers every type (`Any` in `Callable`): every value is a member, and the box's test at `A` decides alone. Then dispatch cannot tell a callable value from another at a `Callable` position: a method at `Callable` against one at another type there meets every value ([alternatives](design/alternatives.md#callable-by-its-methods-replaced-2026-11-15)).
  - (b) The porting guideline: a package's callable types are declared by their owner, or are a `Function` by Julia's idiom where the type has no other supertype.
  - (c) A closure at the call (`x -> itp(x)`) accepted as the plain form, with the hint naming it.
  - The proposal is (b) with (c); (a) for the synthesis, with a census of the pairs it would tie.

**240. A type passed as a constructor is no `Callable` member** (GT-32).
- *The case* (E-504, `experiments/implementation/w156/probes/byrow.jl`): upstream Tables' suite calls `ByRow(Dict)`, which the forks' `byrow(f::Callable{…}, xs)` serves. `Dict` is a `Type`, no `Function`, so `byrow(::Type{Dict}, ::Vector{Pair{Int, Int}})` finds no method. Julia's `map(Dict, xs)` takes it.
- *The rule* ([traits §9](reference/traits.md#9-functions-callable)): a member of `Callable` is a value of a subtype of `Function`, or of a callable type declared a member. A type is neither.
- *The proposals:*
  - (a) Types are members of `Callable` as functions are: Core's entry covers `Type`, and the box checks the signature against the type's constructors (`hasmethod(T, A)`), as for any function. Which pairs of methods it ties (one at `Type{T}` or `DataType` against one at `Callable` at the same argument) is not counted; the census of E-503 would count them.
  - (b) The caller passes a closure, `x -> Dict(x)`.
  - The proposal is (a): a constructor is Julia's ordinary function value, and (b) asks every caller of `map(T, xs)` to change. Not built; the forks keep the failing test.

**229. Which of Base's closed abstract types declare a contract.**
- *The case:* `IO` does ([traits §9b](reference/traits.md#9b-streams-io)). The rule is general ([traits §3.4](reference/traits.md#34-open-and-closed)): a closed abstract type may declare operations. `AbstractArray` and `AbstractString` are the next cases: values in a `Vector{AbstractArray}` would have their operations' calls split.
- *The rule that blocks it:* none. No one has asked which of Base's types gain from a contract, and what a contract on `AbstractArray` costs plain code typed by it.
- *The proposal:* a census first: the calls in the ports' sessions at a value typed by a closed abstract type of Base, by type and function. Then a contract where the count is large.

**230. `NTuple`, `ReshapedArray` and other packages' mutable arrays are no members of BaseTraits' collection traits.**
- *The case:* `NTuple{N, T}` is not in `Iterable{T}` or `Indexable{T}`; `ReshapedArray`, StaticArrays' `MVector` and RecursiveArrayTools' `ArrayPartition` are not in `MutableIndexable{T}` ([traits §10.1](reference/traits.md#101-basetraits)). A port that writes through such a value meets a `MethodError` at the trait's method.
- *The proposal:* `NTuple` and `ReshapedArray` joined by the library, which owns the traits; the packages' types by their owners, in the port that first needs them. [Traits §10.1](reference/traits.md#101-basetraits) states which of Base's types are members by design and which are left to their first use.

**To revisit with the ports.** Choices whose repercussions are unclear either way; experience with large-scale ports will tell.
- **8. Numeric traits:** numbers that join a trait after their definition or forward to a field, and promotion across members' types. Definition checking of code that computes with an element type needs a numeric trait for it. The SciML port shows which numeric traits definition checking needs.
- **9. Units.** Automatic-differentiation tags are labelled by the primal signature ([decisions](record/decisions.md)). The ports show whether units need more than a parameter.
- **10. `Callable` bounds whose argument types are chosen by the callee,** a type-level function of the algorithm's configuration. The SciML port's algorithm packages show whether any are left.
- **12. Bounds over several arguments at once,** `lines(x, y)`, where a conversion builds one value from both. The argument tuple can conform as a family over `Tuple`, with no change to the design; it ties to promotion. The Makie port shows whether that is enough.
- **Collection traits:** which traits and algorithms BaseTraits provides next, and two traits that declare the same function at the same arity ([traits §10.1](reference/traits.md#101-basetraits)).

### Facts and ownership

**19. Should the standard libraries be separate owners?**
- *The case:* Julia (Core, Base, the standard libraries) is one owner ([facts §1](reference/facts.md#term-owner); `TraitWorld/src/ownership.jl`: `owner(m)` returns `:Julia` for every standard library, and `strict.jl` skips `:Julia`). So a standard library's method on Base's types is a stakeholder's change: followed, never refused. SparseArrays' `vcat` for `Number` and `Vector`, loaded by StatsBase, is one; it ends the facts code below the forks that the nine unrelated loads end (GT-8).
- *To settle by E-189* (proposed, not run): a census of the standard-library methods that are pirates by the letter if each library is its own owner, and of which of them win at a fact of trait code in the demonstrators and the ports.
  - Only late-loaded libraries win (SparseArrays' `vcat`): each library its own owner.
  - A library in the system image wins (LinearAlgebra's methods of Base's functions): Julia stays one owner.
- Outside strict mode the choice changes nothing, since a winning pirate is followed by default.

**65. Who owns a method defined by `@eval Owner …`.**
- *The case:* ownership is the module a method is evaluated in. A package that evaluates a method into Base defines it as Julia's own, and strict mode does not see it as a pirate.
- *The proposal:* a method belongs to the package whose code defines it (an image's methods to the image's package); sharing ownership is declared with `@joint_owners` ([traits §12.1](reference/traits.md#121-who-may-declare-a-membership)).
- *To settle by E-189* (with item 19): the methods in package images whose module is neither the image's package nor a joint owner of it.
  - Few, all between split packages: a method in an image belongs to the image's package, and the module rule at run time is a named exception.
  - Common and legitimate: the module rule stays, named among [facts §2.2](reference/facts.md#22-g2-stable-caches)'s exceptions.

**99. Run-time sites where plain Julia would infer a union of results.**
- *The case:* in code compiled by facts, a call at abstract types is a run-time site typed `Any`, where plain Julia would infer the union of the matching methods' results. The CSV fork's reader, a trait module, shows it: its port asserted results and wrapped a type in `Val`.
- *The rule* ([facts §5](reference/facts.md#5-run-time-sites), [§6.2](reference/facts.md#62-the-policy-rule)). A call of a package's own owner-only function is a fact at any signature, inferred as plain Julia infers it ([facts §3](reference/facts.md#3-fact-signatures)): such run-time sites are 134 of the forks' 8,128, 74 of them where more methods match than Julia's `max_methods` (E-458). The case stands for a call of another owner's function, Base's or a public one.
- *The proposals:* (a) a porting rule: enter trait code at the kernels and keep plain front ends plain; (b) in the compiler, split a run-time site on a result type that all matching methods declare or infer, as union splitting does.

**157. In code compiled by facts, a function barrier loses its callee's declared result.**
- *The case:* TraitMakie's recipes keep their data in fields typed by a trait (`pos::Positions`) and call kernels compiled per type (`limits(@specialize(pos::Positions))::NTuple{4,Float64}`). Where `limits` may be extended by others (it is public, or another owner's), `datalimits(p::Lines) = limits(p.pos)` is a run-time site, and facts types its result `Any`. An operation's declared result then fails the membership check. Where `limits` is owner-only, the call is a fact, typed by the method's result ([facts §3](reference/facts.md#3-fact-signatures)): TraitMakie's barriers carry no assertion, and its suite passes (E-458).
- *The rules that block it:* a run-time site's result is `Any` under facts ([facts §5](reference/facts.md#5-run-time-sites)). A declared result is read only for a trait's operation ([compiler §6.8](reference/compiler.md#68-a-declared-result-on-method)). A dispatch made when the code runs could select a later method that declares nothing.
- *Also:* the membership check infers its top frame plainly and its callees under their own policy, so a member is checked by a mix of the two (facts F-24).
- *The proposals:*
  - (a) A run-time site in facts code types its result as the declared result `RT` of every method it could select now, asserted at the call, as an operation's is ([traits §7.9](reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). A later method returning something else raises `TypeError` there.
  - (b) An idiom, no rule: a kernel whose result callers rely on becomes an operation of the trait, with a default.
  - (c) The check infers under the serving method's own policy. It needs (a) or (b) first: with (c) alone TraitMakie fails to load (E-311).

### The compiler

**238. An entry that leaves a parameter free which is no input.**
- *The case:* the stub library's `@implement Z S` for a set `Z{P}` writes an entry at the bare name, and `S` is then a member of every instance (the gate `m1_parametric_set`). `P` is no input, so this gives `S` more than one instance, which [compiler §4.6](reference/compiler.md#46-one-instance-per-member) refuses for two declarations. Two methods `h(::Z{1})` and `h(::Z{2})` do not tie for `S`: one is selected without a report.
- *Beside it, built:* two instances that may differ in an input meet ([compiler §4.9](reference/compiler.md#49-intersections)); this case is unchanged by it, since `P` is no input: `Z{1}` and `Z{2}` are disjoint (`experiments/implementation/w165/probe_bare_entry.jl`).
- *The rule that blocks the first case:* none says what such an entry means.
- *The proposals:* (a) an entry states, or the contract defines, every parameter that is no input; an entry that leaves one free is refused at the declaration. The library does so already; the runtime would. (b) Such an entry is a membership at every instance, and the set's instances meet as inputs' do. The proposal is (a): it keeps "one instance per member" as a rule of the runtime, and (b) makes every parametric set's instances overlap.

**243. A trimmed build runs no `__init__`, so a package it loads from source can stop it.**
- *The case* (E-509): a build that finds no package image for its own Julia loads the package from source, and runs its top-level code where no `__init__` has run. Colors' constant `inv(…)` and TraitNonlinearSolve's precompile workload call LAPACK through a null pointer; TraitMakie's workload calls Cairo before Cairo_jll's `__init__` (`experiments/implementation/w166/logs/c-gdb-plot-head-noimage.log`). The builds at the tag found the images their round's sessions had written; the head's builds, after a rebuild of Julia, found none.
- *The fault* is plain Julia's: an output that is not incremental runs no `__init__`, and a workload guarded by `jl_generating_output() == 1` alone, as PrecompileTools' `@compile_workload` is, runs in such a build.
- *What is done:* the build's procedure writes the program's images with the build's own Julia first (`experiments/implementation/w166/build_c.sh`; [the playbook](record/playbook.md) §2). The demonstrators' six workloads run only where an image is built (`Base.generating_output(true)`; `experiments/implementation/w166/workload_guards.sh` finds the others).
- *Left, for upstream* (with W-19): the build's driver runs the `__init__` of the system image's JLLs and of LinearAlgebra before it loads a program, whose own top-level code always loads from source (`experiments/implementation/w166/apps/loadrun_lapack.jl` stops on vanilla v1.13.2).

**239. A call at an instance of a set is dynamic where another method is at another input value.**
- *The case:* code compiled once at an argument known as `HP{:a, Int}` calls `f`, which has methods at `HP{:a, Int}` and at `HP{:b, String}` (`N` an input). The second method matches at `All{HP{:a, Int}, HP{:b, String}}`. No type is in both, yet the lookup keeps the match and reports an ambiguity, so the call is a dynamic call. Its result is still inferred from the first method (`experiments/implementation/w165/probe_unmet_instances.jl`, E-503).
- *The rule:* [compiler §4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries) relies on an unmet intersection of an abstract type and a set, with a cell at the pair. For two sets, and so for two instances of one set ([§4.9](reference/compiler.md#49-intersections)), there is no pair to put a cell at.
- *How often:* no pair of methods in Base, the library or a port is at two instances of one set at the same argument (the census of E-503: 0 pairs). Two different sets at one argument are the same case; how many calls of the ports it makes dynamic is not counted.
- *The proposal:* a cell per instance, `Tuple{typeof(implements), Type{X{B}}, Type{S}} where S<:X{A}`, and its mirror. A membership's method meets it only for a type already in the other instance, so an image's existing members still validate. The same form would serve two different sets. Not built: it is measured first on the ports' calls at two sets.

**166. Code compiled once at a stream typed `IO` reaches its targets by dynamic calls.**
- *The case:* in code an author erases (an entry `@nospecialize(io::IO)` passing `IOContext{IO}(io)` on, [traits §9b](reference/traits.md#9b-streams-io)), a call on the stream that is not one of `IO`'s operations infers `Any`. It dispatches when it runs where more methods match than inference unions (`read(io)`, `read(f, Int32)`), or where its receiver is a wrapper built from the stream. The instance it reaches is in an image only if the image's build ran it.
- *Wrappers over a stream:* `IOContext{IO_t}`, `EachLine{IOT}`, `ReadEachIterator{T, IOT}` and JuliaSyntax's `Lexer{IO_t}` take the stream's type as a parameter. Built in code compiled once, they are abstract even where the caller knows the stream: a loop over `eachline` infers `Any`.
- *Counted* over Base's 931 methods typed `IO`, compiled once (E-331; the erasure report, `experiments/implementation/audit/erased_calls.jl`): 1,093 dynamic sites, 128 of them because of the stream (`read` 41, keyword calls 13, `displaysize` 11, `position` 11), 953 because of another argument. Base itself compiles these methods per stream type ([compiler §7.5](reference/compiler.md#75-io)).
- *The rules:* [compiler §7.2](reference/compiler.md#72-the-split) splits only an operation's call; [§9](reference/compiler.md#9-images-and-the-machine-code-cache)'s rule that an image holds what a run-time site reaches applies to facts code.
- *The proposals:*
  - (a) An image holds what a call at a closed type's candidates reaches: while an image is built, a dynamic call in code compiled once whose receiver is typed by a closed type with candidates gets the instance each candidate selects, as §9's rule does for facts run-time sites.
  - (b) Split every call at a receiver typed by a closed type with a contract over its candidates, not only an operation's, with the dynamic call as the fallback.
  - (c) More of `IO`'s interface as operations: `read` of Julia's bits types, `displaysize`, `position`, the 128 sites the stream decides.

**170. A split's table targets at a type no image saw are compiled at the first call.**
- *The case:* a call of a contract's operation at a stream typed `IO` splits over the candidates; a stream past them (the REPL's `IOContext{REPL.LimitIO{TTYTerminal}}`) gets its target compiled at the table's first miss in each session. With the REPL's display erasing ([traits §9b](reference/traits.md#9b-streams-io)), DataFrames' `show` step at the REPL compiles 44.4 ms, 7.0 ms of it a candidate's target invalidated and compiled again, for a cause not traced (E-338).
- *The rules:* [compiler §7.3](reference/compiler.md#73-the-table-of-a-calls-targets) (a miss makes the target at the call; an image compiles the targets for the members a package declares: compiler C-39, not built); [§7.2](reference/compiler.md#72-the-split) (a branch's pointer to its candidate's target).
- *The proposals:*
  - (a) C-39 for a closed type's subtypes: the image of the package that defines a subtype of a type with a contract (REPL's `LimitIO`) holds the targets of the contract's operations at the concrete types its workload makes.
  - (b) An erasing entry reads the stream's properties through the eraser.
  - (c) The target for a type whose method's instance is in an image is a dispatching thunk, compiled once per call signature.
  - The proposal is (a), the design's own rule; the invalidated candidate's target with GT-7.

**179. A fully typed Base surface for trait code.**
- *The case:* fully typed code is exactly what compiles ahead ([traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode)), so a hole in Base below a trait program fails its build, where the user cannot fix it (Base's `repeat(::Char, ::Int)` under TraitTables' table program, E-364). Trait code also keeps an edge to each plain callee in Base (GT-8).
- *The claim:* Base is fully typed at the signatures typed code calls it with; a hole there is a defect of Base, fixed in Base by a patch that stands without traits ([compiler §11](reference/compiler.md#11-changes-useful-without-traits)). The part that is dynamic by purpose (`show` and display, `IO` at its abstract type, the REPL, Pkg, loading, `eval`, reflection, the compiler) is not patched.
- *Measured* (E-368, `experiments/implementation/w143/`): of 6,179 signatures of Base's 837 exported functions over twelve broad types, 71.4 % are fully typed and 20.1 % have a hole. The holes sit in 106 functions; five hold 73 % of the sites (`typejoin`, `ntuple`, `setproperty!`, `rehash!`, `_growend_internal!`). The report over-counts calls at a union (166 signatures) and misses holes a build finds.
- *The deep class* (E-478, `next-s3`): the forks' own facts instances in the class 63.1 %, upstream by facts 79.0 % (GT-8; item 218 for the rest).
- *Open:*
  - The build's verdict per signature, in place of the session's report.
  - P3's demand rule (a facts copy of each callee outside the class) is worth another look for upstream compiled by facts: it crosses the criterion of three quarters (79.0 %), not that of 1,000 copies (1,782). The forks cross neither (63.1 %; 2,413).
  - P6 (an image's deep code validated by ownership): deep code holds 68.3 % of the instances the forks' CSV and DataFrames bring after the nine loads, and 18.4 % of the calls by signature (E-480), short of E-399's criterion of a quarter.

**180. What the membership's method leaves** ([compiler §5.6](reference/compiler.md#56-the-memberships-method-and-the-edges); E-367; the findings: `experiments/implementation/w141/README.md`).
- *(a) One list for every absence edge.* Julia keeps such edges under the function's type, and each membership scans all of them: 293 µs with 2,000 folded in the session, where a membership cell cost 7.5 µs. Sessions hold 0 to 6. *Proposal:* index these edges by the trait's name, as Julia indexes keyword calls by another argument; or one function per trait.
- *(d) Tools that list ambiguities see the runtime's methods.* A member of two subtraits is in their common supertrait twice; `Test.detect_ambiguities` reports 12 such pairs of `Core.implements` in the library, and Aqua would. No call ever selects among them. *Proposal:* the tools leave `Core.implements` out; the library's test does.
- *(f) An overlapping membership drops the dispatch cache* where its method meets one that code folded. Not measured.
- *(j) The member as an argument type:* `(::Type{X}, ::S)` as the method's signature. On plain functions, 2,000 abstract members insert at 0.52 to 0.57 ms each, where `Type{<:A}` grows to 12.5 ms each (`w141/probe_valuesig.jl`). *Proposal:* try it if abstract members of one trait come to cost each other.

**181. The build's Base is not the session's.**
- *The case:* Julia's build script replaces 28 methods of Base and the standard libraries before a build compiles (printing a type, `sprint`, logging and deprecation warnings off, some `__init__`s), and changes 12 things that are no method: the binding `Base.invokelatest`, eleven functions' `max_args`. The check and the build compile one program against two Bases; "fully typed is exactly what compiles ahead" holds only against one.
- *The rule* ([traits §16](reference/traits.md#16-compiling-ahead-closed-programs), [compiler §2.7](reference/compiler.md#27-fully-typed-mode)): the check reads the build script's files into an overlay method table. What is no method is not read, and three functions the files add are defined in the session's Base (traits T-109).
- *The proposals:*
  - (a) The list goes where Base is fully typed: each replacement marks a place where Base is not fully typed at a signature typed code calls (item 179). Printing a type is the first.
  - (c) The build compiles through the same overlay, so that the script changes nothing in its process either; only if the two lists drift.
- *The tool:* `TraitWorld.build_base_report()`; `experiments/implementation/w142/agree.sh` with the apps `bb_*`.

**184. The session's check and the build differ at a family's member that no image has checked.**
- *The case* (E-387, the ODE port's program): the problem's type names the function (`ODEProblem{…, PartialFn{typeof(f), P}, …}`), a new member of the problem's family in each program. The check run in a session leaves `_system(prob)` and three more calls unresolved; the build's own process, which runs the member's check in its compile queue (compiler C-31), resolves them.
- *The rule* ([compiler §7.6](reference/compiler.md#76-a-closed-build), [§2.7](reference/compiler.md#27-fully-typed-mode)): a member's check is its serving instances ([traits §5.10](reference/traits.md#510-checks)), which both infer the same way; the implementation does not build that yet (traits T-129).
- *The proposals:* (b) the check in a session runs a family member's check as the build's queue does; and see whether T-129 removes the difference. With it, the program without callbacks should build. For the ports' lessons: (a) the port takes callbacks as a tuple where the program knows them.
- *The tools:* `experiments/implementation/w135/build.sh ode` with `summarize.py`; `experiments/implementation/w142/ft_app.jl`.
- *On the head* (E-510, `next` d8f65ef1ea, TraitWorld `unified` 82959cf, TraitDifferentialEquations `unified` 3a1c4c3): the port follows the references where it departed (callbacks in storage typed by their traits, entered where the problem's types are known; its function kept by its signature; Rodas5's chunk a parameter of its type), and the build branches the call of a box's object over the signature's members. No rule of the design blocked the port's principled form.
  - The trimmed ODE program counts 12 errors in 4 statements, each reached by both solves and at both of the box's signatures. The split at the right-hand side's signature has a branch for TraitIndexing's `VectorGetter`, a member of every `Callable` signature by its one entry, which the program never hands to it; the branch calls the elements of a `Vector{Callable}` and collects the results (compiler C-155).
  - A program with callbacks it knows (a tuple; `experiments/implementation/w158/port/apps/ode_cb.jl`): not built on this head.
  - The plain twin (PlainODE) has plain Julia's two holes: a chunk chosen by a run-time value, and callbacks in a `Vector{Any}`.
- *Next:* compiler C-155; then the program with callbacks; then the getters' own code (a `Vector{Callable}` called and collected with no declared element type) read against traits §14.

**218. Calls at a value typed `Any`, an abstract type or a kind in Base's plain code keep the rest of a port's code out of the deep class** (GT-8).
- *The case:* below the forks' code, the culprits are Base's plain code compiled where types are not known: the generic paths of `collect` and `map` when an element type is not inferred (`similar`, `setindex!`, `Vector{T}(undef, n)` at a computed `T`, `promote_typejoin` at kinds, `indexed_iterate` at a tuple with an abstract element); the task code under a lock (a payload typed `Any` passed to `schedule`, `notify`, `push!` of a `CompositeException`); stores into containers of `Any`; keyword calls at an abstract argument; property reads at an abstract receiver. Each is a call where a stakeholder of a type in it may add a method: `Vector{MyT}(undef, n)`, `eltype(::Type{MyColl})` and `push!(::Vector{Any}, ::MyT)` are legal methods of their owners. The rule is right; the code is outside the class.
- *The rule* ([compiler §3.2](reference/compiler.md#32-g2-as-a-predicate), [facts §3](reference/facts.md#3-fact-signatures)).
- *Counts* (E-478, `next-s3`): the forks 63.1 % of own facts instances in the class, upstream by facts 79.0 %. The forks' cones hold a median of 12 culprits; no further method name buys a point alone (`Iterators.iterate` +0.9, `hasmethod` +0.8; 68.9 % after 25 names). By kind together: other 66.1 %, type joins 69.5 %, introspection 71.1 %. Upstream: 81.2 % after 13 names; with the task code and the containers of `Any`, 87.7 %.
- *The proposals,* for the synthesis:
  - (a) Ownership by declaration ([facts §3](reference/facts.md#3-fact-signatures)): Base declares owner-only the functions no package extends. On the forks, 423 (internal) to 500 (all) culprits resolved, +0.1 to +1.0 point alone; more with the constructors of Base's own types closed to others' methods. It changes who is a pirate for Base's functions, against the default for Base.
  - (b) A store's value position into a container of `Any` is no dispatch position: a method at a container of `Any` for a value it only stores (`push!`, `setindex!`, `_setindex!`, `ImmutableDict`'s constructor) is declared final at that argument, and a call there is a fact at any value. A new form of fact signature; its soundness needs Lemma O's reading for such an argument ([the proofs](design/proofs.md)).
  - (c) P3's demand rule: a facts copy of each callee outside the class, in which these calls are run-time sites. 2,413 copies (the forks) and 1,782 (upstream); 19 % of direct callees get a wider type (E-395 (c)).
  - (d) `invoke` at the callee's own signature, case by case, where Base's code knows the method it means: each a patch that stands without traits, each worth under a point.
  - (e) Accept: G2's reach in a port is the measured share; the guarantee holds for the class.
  - Not a lever: the boundary flag ([compiler §2.2](reference/compiler.md#22-the-method-flag)) on a culprit's caller gives a facts copy of that method only; the culprit below still keeps it out.
  - The proposal: (c) looked at again for upstream compiled by facts (item 179); (a) and (b) for the synthesis; (d) only where a culprit carries a share alone.
- *The tool:* `experiments/implementation/w157/census.jl`, `diag/culprit.jl`.

**219. A query that rests on dispatch names the matched instance, so any code of it ends the caller.**
- *The case:* `hasmethod(f, Tuple{…})`, folded by inference, records an edge to the matched method's MethodInstance. The answer rests on dispatch only, yet the edge ends the caller when any code of that instance is invalidated, so the caller is outside the class. 11 of the forks' `hasmethod` instances, and 33 culprit instances named by instance alone (E-478); `hasmethod` alone buys +0.8 point.
- *Also:* the box's test at `Callable` is such a query, `hasmethod(f, A)` folded in every forwarder at a `Callable` argument and in every wrapper's entry ([compiler §7.4](reference/compiler.md#74-callables-call)). Not counted.
- *The rule* ([compiler §3.2](reference/compiler.md#32-g2-as-a-predicate)): an edge to an instance is ended by any invalidation of its code.
- *The proposals:* (a) an edge kind "dispatch at an instance": a backedge on the instance that a definition changing dispatch there reaches, and the invalidation of one of its CodeInstances does not; GT-21 (b) needs the same form; (b) accept.

**231. A pattern member's candidates in a split, when an image keeps the check's answers.**
- *The case:* a member that joins by a pattern is registered as a candidate of a closed type's split at its first use ([compiler §7.2](reference/compiler.md#72-the-split)). An image keeps the answers of the checks that passed (compiler C-30). Whether a session that loads the image, and never runs the first use, has the candidate registered is not stated and not tested.
- *The proposal:* a gate: an image whose workload uses a pattern member through a split, loaded in a session that calls the split first. Then a sentence in [compiler §7.2](reference/compiler.md#72-the-split), or a deviation row.

### The ports

**245. A mixed list of callbacks given before the problem's types are known.**
- *The case:* a user hands SciML's callback records mixed with callbacks of types of their own, before the problem's state and parameter types exist. The ODE port enters a tuple or a vector item by item once the types are known; a `Vector{Any}` the user builds is entered at `Any` (NetworkDynamics builds one: `get_callbacks`).
- *The rule:* a trait instance `Callback{U, T, P}` needs the three types ([traits §8.1](reference/traits.md)); no trait without parameters names "a callback for some problem".
- *The proposal:* probe a trait without parameters whose operation's variables another argument binds ([traits §4.1](reference/traits.md)), with the instances' members as its members; until then the port's lesson stands: a tuple, or a vector of a small union. NetworkDynamics' `add_nw_cb` takes the ODE port's two callback records and refuses a callback of another type.

**110. Two traits for reading items by position: `Column` and `Indexable`.**
- *The case:* the DataFrames port's `CellVector` is `asvector` for a `Column`, written again.
- *The answer, without a change to the design:* `Indexable` has `firstindex` ([traits §10.1](reference/traits.md#101-basetraits)), so the port's `Column` joins by a block ([traits §5.4](reference/traits.md#54-with-a-block-of-methods)): `@implement Indexable{T} Column{T} where {T} begin getindex(c, i) = cell(c, i); firstindex(c) = 1 end`, and `CellVector` becomes `asvector`. Taken when the DataFrames port is next rebuilt.

**112. A recipe child's untyped node graph undoes the late-load protection** (TraitMakie's compatibility layer, MakieCompat).
- *The case:* the old recipe API's recipe children only; the workload's path makes the core's primitives directly and recompiles nothing after a late load. A child recipe's arguments are nodes of its parent's graph, which resolve to `Any` in plain code, as upstream's ComputePipeline does. The child's creation then compiles abstract instances (among them `hist.jl`'s `Histogram` conversion), which DataFrames' `AbstractVector` subtypes invalidate at a late load (E-226; not measured on `next`).
- *The rule:* none blocks a fix.
- *The proposal:* typed derived values in the `PlotCore` slice of the workload's path (inputs kept, derived values declared), not a patch to the compatibility layer.

**122. Two types for a value that changes: `Observable` and the core's `Live`.**
- *The case* (E-240): `Observable{T}` cannot join `Positions` or `Sample` by forwarding without forwarding for a whole family and an Observables dependency in the core, so MakieCompat mirrors an `Observable` into a `Live`.
- *The proposal:* forwarding for a family ([traits §5.5](reference/traits.md#55-forwarding-with-by), [§5.8](reference/traits.md#58-families)); then `Observable{T}` joins directly, in an extension, and the mirror goes.

**129. `DiffEqArray` over any state type.**
- *The case* (E-242): TraitArrayTools' `DiffEqArray` holds vector states only, so `sol(ts; idxs)` returns a plain `Vector`, and upstream's `sol(ts; idxs).u` does not run.
- *The proposal:* `DiffEqArray` over any state type. It changes the type's parameter, so it is decided before it is built.

**212. A split package's internal interface, extended by its sibling packages, is owner-only in a trait module.**
- *The case* (E-458): the ODE port's ODECore, a trait module, keeps the integrator's step interface internal (`step_tstop!`, `step_interp!`, `step_dt_reset!`, `step_terminate!`). TraitRodas, a solver package of the same port, adds methods of it. Upstream's split packages work so. The four methods are a pirate's, and TraitRodas declares `no_pirates`, so it fails to precompile unless ODECore declares the interface `public`.
- *The rule* ([facts §3](reference/facts.md#3-fact-signatures), [traits §12.2](reference/traits.md#122-pirates)): a function of a trait module is owner-only by default; a pirate is refused under `no_pirates`.
- *The proposals:*
  - (a) The guideline, a porting rule: an interface that sibling packages extend is `public` in the core package. `public` is Julia's own statement that a name is an interface.
  - (b) Joint owners: the core names its solver packages, which inverts the dependency and lists every future solver.
  - (c) A declaration in the core, `@extensible f g`, the opposite of `@owner_only`, for an interface others extend that is not meant for callers.
  - The proposal is (a).

<a id="4-runtime-and-measurements"></a>

## 5. Implementation and measurements

**249. The definition-time check reads the other branch of a split as "no method".**
- *The case:* where a call's argument is abstract and its one method covers part of it, the optimizer emits a type test, the invoke, and else `Core.throw_methoderror`. The check at the box counts that branch as a fault, though a method exists at the types the code knows ([traits §7.3](reference/traits.md#73-bounded-methods): such a call is Julia's function barrier). Met twice in TraitNonlinearSolve (`nl_with_problem(::NLCoreSolution, …)`; `solve_nonlinear(…, ::Any)` in a keyword body); the port writes a declared result and two assertions there (`experiments/implementation/w158/port/README.md`).
- *The proposal:* no fault where a method matches at the types known (`Base._methods_by_ftype`); a test with the two cases; then the port's two assertions removed.

**250. In a session `Base.infer_return_type` gives `Any` for the ODE and the nonlinear `solve` at concrete types.**
- *The case:* `solve_ode` and `solve_nonlinear` at concrete argument types, and callers in `Main` compiled after a run, infer `Any`; their callees infer concrete types, and the build's check resolves the result's use. Not diagnosed.
- *The proposal:* find the statement that loses the type (`fully_typed` on the front end in a session against the build's check); a test that holds the front ends' inferred results.

**116. A member first used while Julia writes an image is checked again at load.**
- *The case:* code compiled at output runs after the build's `atexit` hooks, so the list of checks an image keeps ([lowering §11](reference/lowering.md#11-checks-errors-and-what-images-keep)) misses a member whose first use is there: 1 of the forks' 27 members (`Vector{Union{Missing,String15}}`). A cost at load, no wrong answer.
- *The proposal:* a Julia hook after code is compiled at output, or the member used in the package's workload before output.

**225. Plain code's first work is slower on `next`: more code generation.**
- *The case* (E-499; the session `plain.jl`, upstream CSV and DataFrames compiled plainly, the same hour, 3 runs): the first work takes 3.31–3.47 s on `next`, against 3.25–3.30 s on vanilla, and is a regression against the tag `prototype-2026-11`. The same holds with the library loaded first. The repeated work is unchanged (0.18–0.19 ms).
- *The profile of one first call* (`w161/d4/prof_first.jl`): on `next` 2,640 of 3,466 samples are in code generation (`jl_compile_codeinst`, 76 %), 834 in inference. The membership machinery takes no measurable share.
- *The rule:* not identified.
- *The proposal:* bisect `next`'s commits with `experiments/implementation/w161/d4/plain.sh`, one build each, at the freeze, where builds are made anyway.

**228. An instance a package's workload compiles for a call dispatched at run time is missing from its image.**
- *The case* (E-501): the ODE session (E-372) solves Robertson with Rodas5. `rodas5_solve` calls `TraitRodas._rodas5_run` past a barrier (`rodas5_init`'s result is not inferred to one type). The ODE port's image holds only the instance at the bare `Rodas5Integrator`, not the one at the session's integrator, so the session compiles it (315 ms): the first run takes 651 ms, a regression against the tag `prototype-2026-11`.
- *The counts* (`w161/d2/image_instances.jl`, the instances with valid code after loading, per function): fewer of `_rodas5_run`, `advance!`, `core_solution` (TraitRodas's), `run_to_end!`, `_steps`, `_retcode`, `step_condition`, `step_affect!` (ODECore's).
- *The rule:* not identified. A lead: the instance is TraitRodas's method compiled by the ODE port's workload, so it is external code in the port's image, which an image keeps only at a signature type with a hash ([julia-changes](design/julia-changes.md)).
- *The proposal:* find where the workload's instance goes (not compiled, not kept by the serializer, or kept and dropped at load) with `image_instances.jl` on the precompiling process. Before the measurement round, since the sessions' times rest on it.

**244. `MethodError`'s closest candidates list the library's forwarders.**
- *The case:* a call with no method at a function that has a method at a trait that erases prints, among Julia's "Closest candidates", the forwarder at the wrapper's family, which the user did not write: `sz(!Matched::Compiled{<:Sized2})`, `applyc(!Matched::Compiled{Z} where Z<:Callable{Tuple{Int64}, Int64}, ::Any)`. Six of the 102 messages the library's tests and the examples of `intro/` provoke (the tool `experiments/implementation/w158/messages/`). [Traits §11.3](reference/traits.md#113-errors-and-their-messages) says no message shows a type of the machinery.
- *The rule that produces it:* a forwarder is a method of the function ([compiler §6.3](reference/compiler.md#63-the-forwarders)), and Julia's list prints every method near the call.
- *The proposal:* Julia's candidate list skips a method that is a forwarder (the method definition records it), since the method as written is in the list.

**232. Rules about a set over many of Base's methods have no test at Base's scale.**
- *The case:* the fixes of E-331, E-334, E-335 and E-336 answer cases that appear only when a set stands on a thousand of Base's methods ([the lessons](design/lessons.md)). No gate declares such a set.
- *The proposal:* check which of those rules the build still has, now that a membership invalidates as a method does; for those it has, one gate with a set over a few hundred methods of a module made for it.

<a id="5-documents"></a>

## 6. Documents

**233. Code comments name retired deviation rows.**
- *The case:* `src/datatype.c` of the julia repository names "compiler C-18" in two comments; the row is retired. The references' IDs are the code's too.
- *The proposal:* a grep over the julia repository's `src/`, `Compiler/src/` and `base/`, and the library's `src/`, for the IDs of retired rows, as a check of the lint. Each comment is rewritten to name the section that holds the rule, in the next commit that touches the file.
