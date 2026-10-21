# Porting to traits: a guideline

For people about to port a Julia package written without traits into the trait world. It teaches and points: each rule's home is a [reference](../reference/README.md), and each section links to it. Why the design has its shape: [`../design.md`](../design.md). The terms: [`../glossary.md`](../glossary.md). The current numbers: [`../design/evidence.md`](../design/evidence.md). Status: **in progress**; every port adds what it learns ([how this document is kept](#how-this-document-is-kept)).

**A port does not change the design.** Where idiomatic trait code pushes back against a reference, the port records it in its pushback log, or as an [open issue](../open-issues.md), and goes on with the reference as it stands. A part the port needs whose status is Planned, or a Deviations row that blocks it, becomes a work item; the port pauses for it.

Each example is quoted from the file it names; that package's suite runs it.

## Contents

- [The language in one screen](#the-language-in-one-screen)
- [Part 0. Porting a package written without traits: the method](#part-0-porting-a-package-written-without-traits-the-method)
- [Part A. Rules every port confirms](#part-a-rules-every-port-confirms)
- [Part B. What each port teaches](#part-b-what-each-port-teaches)
- [Proposed for part A](#proposed-for-part-a)
- [How this document is kept](#how-this-document-is-kept)

---

## The language in one screen

Write to TraitWorld's language, never to its internals (names that start with `_`, or that the references do not name). The one exception today: the companion `convert` methods of B3.

| Construct | What a port uses it for | Home |
|---|---|---|
| `@trait_module module Core … end`, `@trait_module begin … end` | the module whose code is trait code, compiled by facts | [traits §2](../reference/traits.md#2-trait-modules) |
| `@trait X begin op(x::X, …)::R; f::T; … end` | the operations and fields generic code needs, each with its type | [§3](../reference/traits.md#3-trait-declarations) |
| `@trait X{T} begin T = eltype(Self); … end` | associated types: by a field, an equation of `Self`, or stated | [§3.4](../reference/traits.md#34-parameters-and-associated-types) |
| `@default_with_dynamic_self`, `@default_compiled_for_self` | the trait's default attribute for plain values | [§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations) |
| `@enforce_concrete_only T Self`, `@warn_on_abstract P` | concrete parameters and `Self`, per trait or per function | [§11.1](../reference/traits.md#111-per-trait-concrete-parameters-and-self) |
| `@implement X T begin … end`, `@implement X T`, `@implement X T by f` | a type joins: its own methods, or forwarding to a field | [§4.1–4.3](../reference/traits.md#4-implementations) |
| `@implement X S{P} where {P}`, `@implement X R where {R: Y}` | families; generic implementations | [§4.7](../reference/traits.md#47-families), [§4.8](../reference/traits.md#48-generic-implementations) |
| `f(t::X, i::Int)`, `f(a::X{T}, b::X{T}) where {T}` | bounded functions; `where` variables in bounds | [§5.1](../reference/traits.md#51-bounds) |
| `f(g::Callable{Tuple{Float64}, Float64}, …)` | a function argument at a declared signature | [§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature) |
| `::Like{t}`, `withfields` | "a value like the input" | [§5.6](../reference/traits.md#56-results-declared-types-like-withfields) |
| `compiled_for(x)`, `with_dynamic(x)`; `x::Dynamic{X}` on a bound | the attribute: code compiled per key, or compiled once | [§6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic) |
| `field::X`, `Vector{X}` in a trait module; `Dynamic{X}`, `Compiled{X}`, `Kept{X}` | values kept beyond a call, with their attribute | [§7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx) |
| `struct S{F <: Callable{…}}; f::F; end` | a struct parameter bounded by a trait: the field keeps the value as its bound gives it | [§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait) |
| `Iterable{X}`, `Indexable{X}`, `Keyed{K, X}` | loops over a user's container, its items seen through `X` | [§8](../reference/traits.md#8-collections) |
| `TraitWorld.strict!(true)`, `TraitWorld.delegate!(Core => Impl)` | refuse a pirate that would change trait code | [§10.3](../reference/traits.md#103-strict-mode) |
| `@joint_owners P1 P2` | in a package's module: the packages named own its functions and types with it (split packages) | [§10.1](../reference/traits.md#101-who-may-implement) |
| `@warn_not_fully_typed`, `@enforce_fully_typed`, `fully_typed(f, types)` | find the calls whose argument types are unknown | [§11.3](../reference/traits.md#113-fully-typed-mode) |
| `TraitWorld.@workload begin … end` | a precompile workload for a trait module | [§13](../reference/traits.md#13-compiling-ahead) |

**Where the code differs today**, the rows a port meets ([traits §17](../reference/traits.md#17-deviations), [lowering §18](../reference/lowering.md#18-deviations), [compiler](../reference/compiler.md#deviations)):
- **L-3:** an untyped method of a bounded method's shape must come after the bounded methods, and only the function's owner may add a bounded method of a shape the function has none of yet. Define the bounded method first, in the owner's package.
- **T-2:** a trait's parameter is not in scope in a default's body. Call a helper that reads it from an argument's type, as TDE's default `jacobian!` calls `fd_jacobian!(prob, J::Matrix{T}, …) where {T}`.
- **T-5, T-38:** a family with a block over a parametric type expression (`S{P} where {P} begin … end`) is not lowered as a family; for a trait whose parameters are defined by equations, the one-line `S{P} where {P}` is refused too. The variable form works: `A where {A <: S}`.
- **T-12:** TraitWorld's own tests and workload use an earlier spelling (`@trait ColTable{R}`). Copy trait code from the references and the demonstrators, not from TraitWorld's tests.
- **T-19:** keyword, vararg and `Callable` functions are checked at their first call, not at the module's end. A workload or a test must call each one.
- **T-32:** with a block, an existing method for an operation the block leaves out is not used. Put every override in the block.
- **T-39:** a user's container is not taken at a bounded keyword. **T-48:** a function whose only bounded arguments are keywords does not work. Bound a positional argument.
- **T-49:** an operation with an argument declared `Self` fails on a `Dynamic` value.
- **T-51:** a `Dynamic` function takes at most six arguments.
- **T-52:** a type that conforms through a generic implementation but whose operations do not conform is accepted with a warning. Read the warnings.
- **T-53, T-54:** a kept value or function passed to a bound of another trait or signature is accepted, though the reference refuses it. Do not rely on it.
- **C-6:** a module's other compiler options are meant to apply to its facts code too; `compile` is ignored there today.

Planned, so not to be written yet: tuples of traits anywhere but bounds, `@implement` and supertrait lists ([§3.7](../reference/traits.md#37-tuples-of-traits), W-29); forwarding for a whole family ([§4.7](../reference/traits.md#47-families)); `Callable` with keywords or an open result type ([§5.7](../reference/traits.md#57-keywords-defaults-and-varargs), [§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)); redeclaring an implementation in a session ([§4.9](../reference/traits.md#49-checks-at-the-declaration)). Trait casts are Optional ([§6.9](../reference/traits.md#69-trait-casts)). Every construct's status: [traits §16](../reference/traits.md#16-status-index).

---

## Part 0. Porting a package written without traits: the method

The method for a new port. It cites part A's rules and part B's evidence rather than restating them.

**The principles, and where each is.** They hold for any package. [B6](#b6-case-study-scimls-architecture-as-traits) applies them to SciML; [the SciML exploration, §3](../explorations/sciml-as-traits.md#3-the-principles-for-the-design-as-it-stands) gives the argument.
- [0.2](#02-find-the-principled-traits-first): traits for open sets, types for closed ones; questions about a type become declarations; capabilities per type, with defaults; declared fields and operations, not `getproperty` switches; extension by implementation, never by overloading the entry.
- [0.3](#03-the-order-seams-first-a-function-at-a-time) and A4: extensions add methods for their triggers' types only.
- [0.4](#04-where-dynamic-where-compiled): the attribute chosen per position, not per problem; values cross by their bound, code never crosses; the key holds what the hot code must know, and no more.
- [0.5](#05-what-to-keep-plain): front ends plain and thin.
- [0.6](#06-how-to-check): every step keeps results equal.

**The first steps, in order:**
1. Baselines and environments: the upstream packages unchanged, on the patched Julia, with a workload a user would run.
2. The facts mode on the unchanged code (0.1), with the dispatch profiler.
3. The package as a trait module (0.1a), its pirates and extensions resolved.
4. The traits written down (0.2).
5. The seams, a function at a time (0.3), with results equal to upstream at every step.
6. Each step recorded, with what it buys (0.6).

### 0.1 What the facts mode gives an unchanged package

- **Two settings** ([facts §12](../reference/facts.md#settings)):
  - **the product setting**, the default: only trait modules are compiled by facts, and what they reach;
  - **the test bed `all`** (`JULIA_COMPILE_BY_FACTS=1`, with a depot of its own): everything but the compiler is compiled by facts. It tests the facts rule on code as written; it is not a user setting.
- **Compiled by facts:** a call is inferred only at a *fact signature*, where its argument types are known ([facts §3](../reference/facts.md#facts-and-fact-signatures)). Every other call is a *run-time site*: dispatched when it runs, as plain Julia does, with the result `Any`.
- **What it buys** ([facts §2](../reference/facts.md#the-guarantees)): plain Julia's results or an error (G1); no load of an unrelated package discards the compiled code (G2), with the exceptions [facts §2.2](../reference/facts.md#g2) names.
- **What it costs:** nothing for fully typed code. At a run-time site, plain Julia would speculate over the methods that match today (up to `max_methods`): type the result from them, inline them, evaluate them at compile time. The facts mode does none of this ([facts §4.2](../reference/facts.md#inferred-across-a-call)). After one run-time site, every call on its `Any` result is one too.
- **Code that trait code reaches is compiled by facts too, whoever owns it** (Base's, and every package's), in the product setting ([facts §6.2](../reference/facts.md#the-mode-rule)). Trait code that loops over a `Vector{Any}` through Base's functions pays tens to hundreds of times plain code's cost per element ([evidence §2](../design/evidence.md#2-run-time), "idiomatic loops over heterogeneous containers", the interop column).
- **Credit the right part.** Protection against loads is the facts mode's property, for any code it compiles. Traits add code compiled per key instead of per type, checks at the declaration, declared implementations instead of methods on internals, readable types, and code that says what it needs, which makes the facts mode cheap ([the rationale §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap)).
- **Measure the facts mode first, before any trait.** Run the workload three ways: upstream on the patched Julia; the package wrapped as a trait module (0.1a), in the product setting; and unchanged under `all`. In the product setting an unchanged package is plain code and gains nothing.

### 0.1a Making an unchanged package a trait module

- **How:** in the package's module file, `using TraitWorld`, then `@trait_module begin … end` around the package's `include`s ([traits §2](../reference/traits.md#2-trait-modules)). Submodules inherit the mode. TraitWorld becomes a dependency (with `[sources]`, mind B1 item 9).
  - A port uses `@trait_module`, which also brings TraitWorld's checks: ownership, pirates, and strict mode's protection of trait code. The bare compiler option `Base.Experimental.@compiler_options facts=true`, which `@trait_module` sets ([compiler §2.1](../reference/compiler.md#21-the-module-option), [facts §6.1](../reference/facts.md#kinds-of-methods)), is a diagnostic for experiments, not a porting step.
- **Each top-level statement runs after the ones before it** ([traits §2](../reference/traits.md#2-trait-modules)). Whether that holds up on a package of SciMLBase's or Makie's size is still to be seen.
- **Package extensions are modules of their own.** An extension of a trait module is plain unless it is wrapped too. An extension that only declares implementations needs no wrapping (A4).
- **Pirates are refused at their definition** (`OwnershipError`, [traits §10.2](../reference/traits.md#102-pirates)). Find them before wrapping, and move them to a plain module.
  - **Split packages meet this at once.** DiffEqBase defines `solve(prob::AbstractDEProblem, args...; …)` (`ndport/pkgs/OrdinaryDiffEq.jl/lib/DiffEqBase/src/solve.jl:653`), a method of SciMLBase's function for SciMLBase's type.
  - **The owner names its joint owners** (`@joint_owners DiffEqBase …` in SciMLBase; [traits §10.1](../reference/traits.md#101-who-may-implement), "Joint owners"). Their methods of the owner's functions on the owner's types are then no pirates, in a trait module and for strict mode. Wrap the owner first: the declaration is the owner's.
  - Before declaring, check whether a pirate is a one-line move to the package that owns the function or a type; then move it (as Static's promotion rule was fixed where the rule is).
  - `TraitWorld.delegate!(Core => Impl)` is data for strict mode only, where the owner has declared nothing.
- **Compiler options** the package sets (`@max_methods 1` in SciMLBase, DiffEqBase, OrdinaryDiffEqCore and Makie; `@optlevel` in Observables): meant to apply in both modes; `compile` is ignored for facts code today (C-6). `@max_methods` changes nothing at a run-time site, where the facts mode speculates over nothing.
- **Workloads:** once the module has bounded functions, the package's `@compile_workload` becomes `TraitWorld.@workload` inside the trait module, which fixes the entries first ([lowering §15.2](../reference/lowering.md#152-workloads)).

### 0.2 Find the principled traits first

A trait names what generic code needs from a value, not how a type stores it.

- **Read the generic functions, not the types.** For each function users pass their own types to, list what it calls on the argument: `length`, `getindex`, `f(du, u, p, t)`, `integ.u`. That list is a trait.
- **Find the seams:** the functions users extend for their own types (a right-hand side, a callback, a plot recipe, a column). Each seam is an operation.
- **Traits for open sets, types for closed ones** ([§14](../reference/traits.md#14-membership), "Abstract types stay").
  - A set is open when packages other than its owner add members: problems, right-hand sides, callbacks, and DiffEq's solvers, which each solver package adds (B6). A trait states what every member provides, checked at `@implement`.
  - A set is closed when one package holds every member, as a solver package holds its caches and tableaus: types, selected by dispatch.
  - An abstract tree may stay beside a trait, as documentation and for typed dispatch; a typed method still wins over a bound. `Number`, `Real` and `Integer` stay. For containers, a BaseTraits bound says what generic code needs ([§8](../reference/traits.md#8-collections)).
- **Operations or fields:** a declared field where code reads or writes stored data ([§3.3](../reference/traits.md#33-fields)); an operation otherwise, with its result type ([§3.1](../reference/traits.md#31-operations)). A computed property is no field: the library converts such a type ([§4.10](../reference/traits.md#410-types-that-only-convert)).
  - **Declared fields and operations, not `getproperty` switches.** A switch on a property's name (`integrator.ps`, `sol.t`) is sugar for scripts. It stays in the ordinary layer, on the concrete type. Trait code reads declared fields and calls operations for what is computed.
  - Julia resolves such a switch only where it sees the name as a constant. Constants are carried from plain callers into code compiled by facts ([facts §6.3](../reference/facts.md#calls-between-the-modes)), so a plain caller's `x.field` stays typed; trait code reads declared fields and operations, never the switch.
- **Associated types:** element and parameter types become the trait's parameters ([§3.4](../reference/traits.md#34-parameters-and-associated-types)):

  ```julia
  @trait ODEProblemTrait{T, P} begin             # TraitDifferentialEquations/src/ODECore.jl
      @const u0::Vector{T}                       # T and P defined by the fields' types
      @const tspan::Tuple{Float64, Float64}
      @const p::P
      rhs!(prob::ODEProblemTrait{T, P}, du::Vector{T}, u::Vector{T}, t::Float64)::Nothing
      jacobian!(prob::ODEProblemTrait{T, P}, J::Matrix{T}, u::Vector{T}, t::Float64)::Nothing = fd_jacobian!(prob, J, u, t)
  end
  ```
- **Questions about a type become declarations.** A library that asks a type questions through functions (`isinplace(f)`, `has_jac(f)`, `alg_order(alg)`) answers each in the trait:
  - the call's form (`isinplace`) is the operation's declared signature: `rhs!(…)::Nothing`;
  - element and parameter types are the trait's parameters (above);
  - an optional capability (`has_jac`) is a subtrait, `ODEJacobian <: ODERHS` ([§3.6](../reference/traits.md#36-supertraits-and-bundles)), with the library's fallback (finite differences) as the trait's default operation ([§3.2](../reference/traits.md#32-defaults));
  - a number that decides types (a dimension) is an explicit type parameter of the implementing type; one that does not is an operation with a declared result, `alg_order(a::ODEAlgorithm)::Int`. Traits have no associated constants ([§3.4](../reference/traits.md#34-parameters-and-associated-types), "Not offered").
- **Capabilities per type, with defaults.** Membership is per type ([§14](../reference/traits.md#14-membership)). A record whose optional field is given conforms to the subtrait, as a family member; one whose field is `nothing` does not. The library asks nothing: it calls the operation, which is the type's own or the default. Asking a kept value for a capability is a trait cast, which is Optional ([§6.9](../reference/traits.md#69-trait-casts)).
- **`Self`** where code returns "a value like the input": `emptylike(c::CSVColumn)::Self`, or `::Like{t}` ([§3.5](../reference/traits.md#35-self), [§5.6](../reference/traits.md#56-results-declared-types-like-withfields)).
- **How each type joins** ([§4](../reference/traits.md#4-implementations)):
  - **An informal interface becomes a trait over its existing functions.** Graphs' `nv`, `ne`, `outneighbors`, SymbolicIndexingInterface's functions: declare the operations with qualified names, and let existing types join by their existing methods, one line or as a family over the abstract type, as BaseTraits does for Base's containers ([§3.1](../reference/traits.md#31-operations), [§4.7](../reference/traits.md#47-families), [§8.1](../reference/traits.md#81-basetraits-traits-for-bases-concepts)). The package's code does not change.

    ```julia
    # a sketch, not yet run
    @trait Graph begin
        Graphs.nv(g::Graph)::Int
        Graphs.outneighbors(g::Graph, v::Int)::Vector{Int}
    end
    @implement Graph G where {G <: Graphs.AbstractGraph}
    ```
    Limits: a block of methods for an existing function only for types the package owns ([§10.1](../reference/traits.md#101-who-may-implement)); a bounded method on another package's function only where the package owns a trait the bound names ([§5.5](../reference/traits.md#55-dispatch-types-first-then-traits)), and L-3. A function that returns another object to work on (`symbolic_container(x)`) is forwarding where the object is a stored field (`by`, [§4.3](../reference/traits.md#43-forwarding-with-by)), and a type that only converts where it is computed.
  - by its own methods: a block, or one line after the methods;
  - by forwarding to a field that holds the data, `@implement Positions Live{Matrix{Float64}} by val`: the type shares the code compiled for the field's type;
  - as a family, for every instance of a parametric type; by a generic implementation, for every type that conforms to other traits.
- **Extension is by implementation, never by overloading the entry** ([§10.1](../reference/traits.md#101-who-may-implement), [§5.5](../reference/traits.md#55-dispatch-types-first-then-traits)).
  - The owner writes the entry (`solve`, `init`) once.
  - A package that adds a member implements the trait for its own type, or adds a typed method naming its own type: a stakeholder's method, which dispatch takes before any bound.
  - A package that adds a convenience form (a `solve` without an algorithm) declares a trait it owns and adds a bounded method with it. L-3 limits this today.
  - A method of a foreign function for a foreign abstract type is a pirate. Joint owners hold such methods where a split package keeps its shape (0.1a); the principled form puts the body in the owner (B6, move 3).
- **Supertraits and tuples:** `@trait CSVColumn{T} <: Column` when every implementation of the one is one of the other; `t::(ColTable, RowTable)` when a function needs both ([§3.6](../reference/traits.md#36-supertraits-and-bundles), [§3.7](../reference/traits.md#37-tuples-of-traits)).
- **Concreteness is decided when the trait is published** ([§11.1](../reference/traits.md#111-per-trait-concrete-parameters-and-self)): adding it later breaks conforming types.
- **Names:** an operation is a function of the trait's module; a common name clashes on `using` (B1 item 7).
- **Write the traits down before the port, and revisit them** as the port meets real code.

### 0.3 The order: seams first, a function at a time

- **Layout:** an ordinary module around the trait module (A7). The ordinary layer keeps the public API: keyword parsing, conversions, name checks, printing. The trait module holds the work.
- **Start where new user types enter.** A function users pass their own types to is the first to bound.
- **One function at a time.** A bound ranks below every type in dispatch ([§5.5](../reference/traits.md#55-dispatch-types-first-then-traits)). Upstream's typed methods and the port's bounded ones stand side by side. Add the bounded method in the package that owns the function, above upstream's untyped method of the same shape (L-3).
- **Keyword APIs:** the ordinary layer takes the keywords and builds a concrete options struct; the bounded function takes it positionally (`SolverOptions` in `TraitDifferentialEquations/src/TraitDifferentialEquations.jl:69`). A keyword body compiles per set of keywords, so a workload covers the sets users pass (B1 item 11). `Callable` with keywords is Planned ([§5.7](../reference/traits.md#57-keywords-defaults-and-varargs)).
- **Extensions add implementations, and methods for their triggers' types only** (A4). That is the rule for implementations ([§10.1](../reference/traits.md#101-who-may-implement)), carried to plain methods. A method that wins at a signature naming none of its triggers' types changes trait code at every load (pushback P6-3; B6, G-L).
- **Workloads:** `@implement X T` in a package compiles ahead the bounded functions with one trait position and concrete other arguments; not varargs, nor several trait positions ([§13](../reference/traits.md#13-compiling-ahead), [lowering L-15](../reference/lowering.md#18-deviations)). A `TraitWorld.@workload` covers the rest.

### 0.4 Where `Dynamic`, where `Compiled`

The attribute chooses speed, never results ([§6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic), [§6.8](../reference/traits.md#68-costs-and-choosing)).

- **Per position, not per problem.** A library's specialization levels (SciML's six, B6) become one attribute per position: the stored function, the callbacks, the model. The callee's signature gives the default; the caller overrides per value with a cast ([§6.4](../reference/traits.md#64-casts)).
- **The key holds what the hot code must know, and no more.** For a solver: the algorithm with its cache, the state, the element type, the parameters, and for implicit methods the dual chunk and the linear solver. Cut everything else by a position: functions by `Callable`, callbacks by `Vector{Callback}`, the options' functions by `Callable` fields, a solution's problem by a kept value. A value that decides types in hot code goes in the key as an explicit type parameter (B5); a knob that need not vary is a constant (B2).
- **A new user type should not compile the library again.** Where user types enter and a large library stands behind, take them `Dynamic`: `@default_with_dynamic_self` on the trait, or `Dynamic{X}` on a public function's bound (exported or `public`; elsewhere the annotation warns, [§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations)). `Callable` is `Dynamic` by default. Loops over the data run `compiled_for` the data (A12).
- **A kernel whose work per call is large:** `@default_compiled_for_self` on its trait.
- **Leave the choice to the caller** where both are useful: one port's experience (B2, "A stored function").
- **Stored user functions,** including RuntimeGeneratedFunctions: a struct parameter bounded by `Callable` at the declared signature ([§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait), B2).
  - **Values cross by their bound; code never crosses.** The function enters once, at the constructor, and is seen at its declared signature from then on ([§6.2](../reference/traits.md#62-how-plain-values-enter-the-trait-world), [§6.5](../reference/traits.md#65-values-carry)). No wrapper is installed before the call, and no state type is an exception: the bound converts nothing. The signature is checked at every call, and the result asserted ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)).
  - A generated function's type is not of the trait world, so at a bare `Callable` it is `Dynamic`: the library compiles once per signature, not per generated function. The package's own closures are of the trait world and run `Compiled` where the code knows their type ([§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations)).
  - T-51 limits a `Dynamic` function to six arguments. NetworkDynamics' edge function `g(ysrc, ydst, x, insrc, indst, p, t)` has seven, eight with external inputs: a blocking deviation, so a work item.
  - Reflection on the function (a type inferred from `g`'s methods) runs on the plain function, before it is kept.
- **Dual numbers through caches:** the buffer's element type is the problem's `T`; tag duals by the primal signature; fix the chunk (B2).
- **What the caller passes:** values typed at the prompt, or by a top-level statement without a loop in a test or script, are `Dynamic` ([§6.2](../reference/traits.md#62-how-plain-values-enter-the-trait-world)). Test a `Compiled` path from inside a function, or with `compiled_for`.
- **Items of mixed type:** take the user's container by its bound (`xs::Iterable{Shape}`, [§8.3](../reference/traits.md#83-a-users-container-taken-as-it-is)). A copy into `Vector{Dynamic{X}}` costs a pass and loses aliasing; the view over the user's container costs none within the split's four implementations ([evidence §2](../design/evidence.md#2-run-time), "idiomatic loops over heterogeneous containers").
- **Which four:** the first four implementations declared take the fastest path, as known where the calling code was compiled. A library's image knows its own and its dependencies' implementations; with four of its own, a user's type takes the path beyond them ([§6.8](../reference/traits.md#68-costs-and-choosing)).

### 0.5 What to keep plain

- Bookkeeping, macros, printing to a terminal, options parsing, name checks, `getproperty` sugar: the ordinary layer (A5).
- **Front ends and rebuilding (`remake`): plain and thin,** behind a function barrier (B2, "A front end"). Their cost is per call. Bounded keywords are limited today (T-39, T-48). What a trait declares is rebuilt with `withfields` and `Like{t}` ([§5.6](../reference/traits.md#56-results-declared-types-like-withfields)), the rest by the constructor.
- Abstract type hierarchies that are right as they are.
- **Plain means: not in a trait module.** A plain function that trait code calls is compiled by facts on that path ([facts §6.2](../reference/facts.md#the-mode-rule)). Keep it plain only where trait code does not call it, or make it fully typed.
- **Notification graphs:** TraitMakie keeps its `onchange` plain, and its trait code never calls it; it has no Observables. Where trait code reads an observable, its value's type is what the code knows: type the observable (`Observable{T}`), or read it at the boundary and assert. Makie has many `Observable{Any}`: measure with the dispatch profiler before porting Observables.

### 0.6 How to check

- **Per step:** the workload, with a digest of its results compared to upstream's, and a chosen part of upstream's suite: minutes at most. **At milestones:** the full suites (A6). Outside performance work, no benchmarks: a speed suspicion becomes an open issue. One Julia job at a time ([`../record/INDEX.md`](../record/INDEX.md), "Standing constraints").
- **Every step keeps results equal.** The attribute and the mode change speed, never results ([facts §2.1](../reference/facts.md#g1)). A step that changes a digest is a bug, not a design question.
- **Compare with `==`**, not `≈`: the same arithmetic gives the same bits. Where `==` fails, check the site for `@muladd` or `@fastmath` before calling it a port bug, and record the case.
- **A scripted session** that a user would type, run trait and plain (A8; B3's REPL harness).
- **The tools:**
  - `check_definitions(M)`: a trait module's definition check, on demand ([§9](../reference/traits.md#9-checks-and-when-they-run));
  - `fully_typed(f, argtypes)` and `@warn_not_fully_typed`: the calls with unknown argument types and their root cause ([§11.3](../reference/traits.md#113-fully-typed-mode));
  - `JULIA_FACTS_DISPATCH_PROFILE=1`: dynamic calls per callee and call site ([compiler §6.5](../reference/compiler.md#65-the-dispatch-profiler));
  - `--trace-compile=stderr --trace-compile-timing` with a mark per step: what each step compiles, and `# recompile` where a load discarded code;
  - `verify_main`: what a program reaches through trait code ([§13](../reference/traits.md#13-compiling-ahead)).
- **Time a step twice in one session:** the second time separates run time from compilation. Time a first call whole. One harness per claim; say how many runs; keep a column without loads.
- **Under `all`, a depot of its own** ([facts §12.2](../reference/facts.md#the-test-bed)): `JULIA_DEPOT_PATH=$TMPDIR/depot-facts:$HOME/.julia:`. The trailing `:` adds Julia's bundled depots, not the user's.

### 0.7 Pushback

- Record where idiomatic trait code meets a rule that hurts: the code, the idiomatic form, the reference section, whether it blocks.
- A question for the user becomes an [open issue](../open-issues.md). A blocking Planned part or deviation becomes a work item.
- Never change a reference to make a port pass.
- Where code and a reference disagree and no Deviations row covers it, report it: whoever changes that reference adds the row (CLAUDE.md).

---

## Part A. Rules every port confirms

One line per rule; the evidence is in part B, the rule's home in the references.

- **A1. Say what code needs:** fields and containers of a trait's name, results declared ([§7.2](../reference/traits.md#72-a-traits-name-as-a-storage-type); B1, B3).
- **A2. Make the hot path fully typed:** what makes a run-time site and the fixes, [facts §3](../reference/facts.md#facts-and-fact-signatures); B1 item 10, B4.
- **A3. Public functions reach their work in a trait module,** bounded where user types enter ([lowering §2](../reference/lowering.md#2-modes-owners-and-images); B1 item 7, B2 "A front end", B3 "A report").
- **A4. Extensions become implementations,** naming each trigger; their plain methods name a trigger's types too ([§10.1](../reference/traits.md#101-who-may-implement); 0.3; B1 item 5, B3 "Tables", B4, B5).
- **A5. Keep plain what is plain,** and adopt traits one function at a time (0.5; `forks/README.md`, "Kept plain").
- **A6. Upstream's tests decide** (B1 item 9).
- **A7. A package is an ordinary module around its trait module** ([§2](../reference/traits.md#2-trait-modules); every demonstrator).
- **A8. Keep a plain control, feature by feature, and compare outputs** (B2 "A scripted session", B3 "Keep the control").
- **A9. Declare result types that catch the common mistake; assert where the type is unknown** ([§4.9](../reference/traits.md#49-checks-at-the-declaration), [§7.6](../reference/traits.md#76-equality-and-inference); B1 item 8, B2 "What a declared result catches", B3 "Recipes").
- **A10. A kernel reads a value through its trait's operations; heavy library code runs over gathered cells** (B1 items 1–2, B3 "Tables").
- **A11. A type passed as a value becomes a value that stands for it** (B1 item 5, B3 "Tables").
- **A12. Take user types `Dynamic` at public entries; run loops `compiled_for` the data** ([§6.8](../reference/traits.md#68-costs-and-choosing); B3 "Recipes", B3 "Tables").

---

## Part B. What each port teaches

### B1. Tables, DataFrames, CSV

Forks of Tables 1.14.0, DataFrames 1.8.2, CSV 1.1.0 (`forks/`, `git diff upstream`); paused. The upstream suites passed at forks 8c6366a ([`forks/README.md`](../../forks/README.md), "Test status"). Traits: `Column{T}`, `TableSource`, `CSVColumn{T} <: Column`, `TextColumn{T} <: Column`.

1. **A kernel reads through the operations.** `refine!(perm, c, rev)` sorts with `lt = (i, j) -> isless(cell(c, i), cell(c, j))`; the join reads `cell(l, i)`. A closure over a trait object may go to Base: definition checking follows it ([§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object)). One operation is the API's way back (`vector(c)`, so `df.a === v`); kernels do not call it.
2. **Heavy library code runs over gathered cells.** `describe` gathers into `emptycells(c, n)::Vector{T}` and runs Statistics there: compiled once per `T`, shared by every column kind; only the gather loop is per key.
3. **A `where` variable names an associated type:** `f(c::Column{T}) where {T}` gives `Dict{T, Int}()` ([§5.1](../reference/traits.md#51-bounds)). An empty comprehension gives `T` only through inference ([facts §2.1](../reference/facts.md#g1)).
4. **What a type does by itself is an operation.** Row selection keeps a pooled column pooled, so `take(c, rows)` is an operation; reference pools go through DataAPI's functions.
5. **A type passed as a value becomes a value that stands for it.** `stringtype = String15` passes a type; the port's reader makes `S[]` and calls `TextColumn`'s operations on it, and the InlineStrings extension declares implementations only.
   - Guard a run-time `conforms(Vector{S}, TextColumn)` with a static test (`S <: AbstractString`); unguarded, every cell of `CSV.Rows` asks, and upstream's allocation test fails (`forks/README.md`).
   - A family pattern must not admit more than it means: `Vector{<:Union{Missing, InlineString}}` admits `Vector{Missing}`. Spell out the members.
6. **The values the reader fills are the conforming values:** `CSVColumn{T}` conforms for `Vector`, and the parse loop is one bounded function, `parsecells!(c::CSVColumn, …)`.
7. **A constructor from a trait goes through a named bounded function:** `DataFrame(x)` stays plain and calls `fromsource(t::TableSource, copycols)`. A `nrow` operation collides with `DataAPI.nrow` on `using`; the operations are `tablenames`, `tablecolumn`, `tablerows`.
8. **A declared result is checked at the implementation:** `tablecolumn(t, i) = tocolumn(columns(t.table)[i])` is refused, "returns `Any`, declared `Dynamic{Column}`". Assert inside: `tocolumn(…)::Dynamic{Column}`.
9. **Upstream's tests catch what the port's checks miss:** a `Missing` string type, a per-cell allocation, an extension that fails to precompile (only its tests error).
   - A path source in `[sources]` must also be in `[deps]` or `[extras]`.
   - Pkg may not refresh a path package's `weakdeps` and `extensions` after its `Project.toml` changes: check that a new extension loads.
   - Upstream's `@inferred` tests hold only where the port asserts its results: `DataFrame(::TableSource)` asserts.
10. **Run-time sites in real code, and their fixes** (A2):
    - an abstract argument type (`Any` fields, `Vector{Any}`, `Dict{Symbol, Any}`, non-constant globals);
    - a type held as a `DataType` (`allocatecolumn(T, …)`): carry it as a value that stands for it, `Val(T)` or a type parameter;
    - union-typed options meeting at one call: normalize them where they enter, assert where they are read. Two union-typed arguments of three types each are already a run-time site;
    - a large stage's result typed `Any`: assert it, `p = _prepare(buf; kw...)::Prepared`;
    - `parentmodule(@__MODULE__)._file(…)`: `const _CSV = parentmodule(@__MODULE__)`;
    - a loop over mixed data: a BaseTraits bound first ([§8.3](../reference/traits.md#83-a-users-container-taken-as-it-is)); for Base's own internals over `Vector{Any}`, `invoke` at the declared signature is a fact ([facts §3](../reference/facts.md#facts-and-fact-signatures)).
11. **Where compiled code lives.**
    - Code for a key from one package and a function from another lives in no image unless a glue extension with a workload compiles it (`CSV/ext/CSVDataFramesExt.jl`): a plain-Julia remedy ([open issues §2](../open-issues.md#2-design), item 28).
    - A workload covers keyword sets and IO types: a keyword body compiles per set, a printer per IO type. Render into an `IOContext{IOBuffer}` with the terminal's properties, then write once.
    - A standard library counts as Julia's code, so its methods on Base's types are followed ([open issues §1](../open-issues.md#1-decisions-waiting-for-the-user), item 19). SparseArrays' `vcat` wins at `vcat(::Int64, ::Vector{Int64})`, which CSV's reader reaches through `[0; v]`, so loading it recompiles the reader. In a hot path, avoid concatenation syntax on Base's types.
12. **A storage change behind an adapter:** `DataFrame.columns::Vector{Dynamic{Column}}`, with `_columns(df)` a view that reads and writes through the kept values; the storage sites and the suite run unchanged.

### B2. Differential equations

`TraitDifferentialEquations` (TDE: Tsit5, Rodas5, callbacks, gradients), its user package `examples/LorenzModels`, its control `baselines/PlainODE` ([`TraitDifferentialEquations/README.md`](../../TraitDifferentialEquations/README.md)).

**A problem is a trait, with the library's own type as its canonical implementation.** `ODEProblemTrait{T, P}` (0.2) declares what the solver needs. TDE's `ODEProblem` implements it as a joint family; a user's problem type implements `rhs!` itself, and the solver compiles for it in the user's image.

```julia
@implement ODEProblemTrait{T, LorenzParams{T}} LorenzProblem{T} where {T}   # examples/LorenzModels
```

**A stored function, with the attribute left to the caller** ([§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)). The constructor is the bound: by default the field is `Dynamic{Callable{A, S}}`, and the solver compiles once per state and parameter type; under `compiled_for(f)` it is the function itself.

```julia
struct ODEProblem{T,P,F<:Callable{RHSSig{P,T},Nothing},D<:Callable{DualSig{P,DUAL_CHUNK},Nothing}}
    f::F; u0::Vector{T}; tspan::Tuple{Float64,Float64}; p::P; fd::D
end
solve(ODEProblem(compiled_for(lorenz!), u0, tspan, p), Tsit5())   # compiled for lorenz!
```
- The bound may name the struct's other parameters (`RHSSig{P, T}`).
- For a second signature (the Jacobian's duals), a second bounded parameter, given the function itself: a kept value is seen at the signatures it entered with ([§6.5](../reference/traits.md#65-values-carry)). One parameter bounded by a tuple of `Callable`s is Planned ([§3.7](../reference/traits.md#37-tuples-of-traits), W-29; TDE adopts it in W-30).

**A front end.** `solve` is neither specialized nor inferred on the problem (`Base.@nospecializeinfer`, `@nospecialize`), with a function barrier behind it; otherwise each caller's first call infers the solver's front end again. The front end is plain code, and a load can discard it: IntervalArithmetic's ForwardDiff extension did, and a new callback took over ten times as long (the README's dated table). Keep it thin.

**A knob fixed, not a type parameter.** The dual chunk is a constant (`DUAL_CHUNK = 8`), so it is no part of the problem's type.

**What a declared result catches.** With `rhs!(…)::Nothing`, an in-place function that ends with `du .= …` is refused: a problem type at `@implement`; a plain function under `compiled_for` at its first use, as a family member that does not conform (`ImplementError`); a `Dynamic` one at its first call (`TypeError`). The check does not prove conversions: a `Float64` buffer in a problem generic in `T` fails at run time under `gradient`. Give the buffer the problem's `T`.

**The state's element type is the problem's:** a loss promotes it (`LorenzProblem(eltype(p).(u0), …)`); the solver reads `T` from `u0::Vector{T}`.

**Callbacks** are types with implementations (`@implement Callback Bounce`), kept as `Vector{Callback}`, and see the integrator as an explicit `Dynamic{IntegratorView}(i)`: callback code compiles once. A callback that writes a parameter asserts its type, `integ.p::LorenzParams{Float64}` (opening a kept value at its own type is Open, [§7.1](../reference/traits.md#71-the-three-forms)).

**Gradients:** ForwardDiff is called directly. A loss as `Dynamic{Callable{Tuple{Vector{D}}, D}}(loss)` makes ForwardDiff's driver compile once per signature; TDE tags the duals by the loss's primal signature.

**The plain control shows what the trait form saves:** PlainODE's default `jacobian!(m, J::Matrix{Float64}, …)` is ambiguous with a user's `jacobian!(m::Lorenz{T}, J::Matrix{T}, …)`; a trait's default belongs to the implementation.

**A scripted session:** `scripts/session.jl trait|plain` runs new functions, problem types, callbacks, losses, Rodas5, `Float32` and an edit, and both print the same `RESULT` lines.

### B3. Plotting and the report

TraitMakie, and TraitReport with TraitTables and TraitCSV ([`TraitMakie/README.md`](../../TraitMakie/README.md), [`TraitReport/README.md`](../../TraitReport/README.md)).

**Attributes are kept values; assignment converts.** A plot's colour, marker and data are fields of a trait's name, `Kept{X}`; `p.color = :red` converts to the field's type ([§7.3](../reference/traits.md#73-assigning-from-plain-code)). To translate first, define `Base.convert` to `Kept{X}`; the ordinary layer's checks run there, so `p.color = :magenta` is refused with the named colours.

```julia
Base.convert(::Type{Kept{ColorSpec}}, x) = Kept{ColorSpec}(_color(x))    # TraitMakie/src/TraitMakie.jl
```
- Three companion methods per trait let values that carry an attribute pass unchanged (`TraitMakie/src/TraitMakie.jl:73`–`76`). They name TraitWorld's internal types: the one exception to "write to the language".
- Fields without a trait (`step::Symbol`) are checked where they are used.

**Recipes kept `Dynamic`, loops compiled per key.** The axis keeps `Dynamic{Plot}`; the public `add_*` functions take `Dynamic{Positions}`; each recipe calls its loop with `compiled_for` and asserts the result:

```julia
datalimits(p::Lines) = limits(compiled_for(p.pos))::NTuple{4,Float64}    # TraitMakie/src/PlotCore.jl
```

**A parent rebuilds its children from its own fields before each use** (`refresh!` of `Hist`, `Stairs`, `Band`): a child follows every change of the parent, and a live source, without a notification graph.

**Live data conforms by forwarding,** per parameter value (`@implement Positions Live{Matrix{Float64}} by val`); forwarding for a whole family is Planned.

**Tables.** TraitTables keeps columns as `Vector{Column}`; each summary runs `summarize(compiled_for(t.cols[k]), name)`. TraitCSV passes candidate column types as empty columns and returns parsed columns `Dynamic`:

```julia
col = fillcolumn(compiled_for(emptylike(c)), s, spans[k])::Union{Nothing,Dynamic{Column}}   # TraitCSV/src/CSVCore.jl
```
- Its InlineStrings extension declares `@implement CSVColumn Vector{String15}` and nothing else.
- A `sizehint!` on a trait object fails the package's precompilation, naming the line: not an operation of `CSVColumn`.
- TraitTables names a cell type from the cells; a `where` variable names it directly (B1 item 3).

**A report calls plain packages from its trait module.** TraitReport's trait module calls CSV and DataFrames as they are; a `DataFrame` does not conform, so the report converts it (`columns(df)::Columns`, [§4.10](../reference/traits.md#410-types-that-only-convert)).

**Controls compare outputs.** PlainPlots draws the same figures; the test compares PNGs pixel by pixel. PlainTables prints the same summaries (`TraitReport/scripts/check.sh`).

**Names are validated in the ordinary layer,** with messages that list the choices: a bound cannot refuse `:magenta`, since every symbol is one conforming type.

**A scripted REPL session checks interactivity.** Feed a session to a real REPL on a pseudo-terminal (`script -qec "julia -i" /dev/null < session.jl`), print `CHECK <what> ok` lines, strip terminal escapes, allow only deliberate `ERROR` lines. The REPL displays every result, which tests do not: `string` of a `String15` stays a `String15`, so convert where the type matters, `String(string(cell(c, i)))`.

### B4. Small examples and acceptance cases

`experiments/facts/framing/` and `experiments/examples/`; their READMEs give each case and its last run.

- **Check, do not assume:** S1–S10 (`inval_cases.jl`) show which definitions invalidate code at concrete signatures: a stakeholder's method, a winning pirate, a redefined `const`.
- **A splat is a fact only with concrete elements** (`vararg_splat.jl`; [facts §3](../reference/facts.md#facts-and-fact-signatures)): splat collections of a concrete element type, or write `reduce(vcat, parts)`.
- **Customize by implementations, never by a pirate** (`strict/dual_pirate.jl`; [§10.3](../reference/traits.md#103-strict-mode)). At the prompt the definer is `Main`: the owner writes `@eval Owner f(…) = …`.
- **An extension's method at a fact is followed, with a warning in strict mode; an extension of implementations invalidates nothing** (`s9_extension.jl`, `extension/glue.jl`).
- **Print types through a type printer**, not a method on `Type` ([compiler §5.3](../reference/compiler.md#53-type-printers)): `show(::IO, ::Type{<:X})` widens a function plain code calls at abstract signatures.
- **Configure by arguments or fields**, not by a `const` another module redefines ([facts §2.2](../reference/facts.md#g2); `pirate_tiers.jl binding`).
- **A `Dynamic` answers in the caller's world**, the set of methods a call sees, fixed when it starts (Julia's world age; `g1_16_dynamic_world.jl`).
- **Errors at the declaration, not deep in a trace** (`errors/definition_errors.jl`; [§4.9](../reference/traits.md#49-checks-at-the-declaration)).
- **Fully typed mode names the line, the root cause and a fix** (`warnings/teach.jl`; [§11.3](../reference/traits.md#113-fully-typed-mode)).
- **One `Dynamic` position, many implementations, one compiled copy** (`heterogeneous/collections.jl`).
- **One declaration per session:** a second `@implement`, or an override after it, is refused; restart Julia (`redefinition/prompt.jl`; [§4.9](../reference/traits.md#49-checks-at-the-declaration)).

### B5. Networks of dynamical systems: NetworkDynamics, SciML, GraphMakie (W-32)

The meta plan: [`../plans/2026-10-21-networkdynamics-port.md`](../plans/2026-10-21-networkdynamics-port.md). The pushback log: [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md). This section holds what the port measured; the architecture its lessons point to is the case study, [B6](#b6-case-study-scimls-architecture-as-traits).

- **Wrapping a 15,000-line package works with three lines.** NetworkDynamics as a whole in `@trait_module` precompiles (18 s against 22 s plain), nothing is refused, and the workload's results equal upstream's bit for bit (E-153).
- **After wrapping, profile the steady state before anything else.** Time a step twice in one session (0.6), then run the dispatch profiler and `fully_typed` on the hot function. In NetworkDynamics the second solve took 30 s against 20 ms upstream. The cause was outside the package: Static.jl's promotion of `Int` with `StaticInt` falls back to `typejoin`, which plain Julia folds and code compiled by facts does not ([facts §8](../reference/facts.md#8-asserted-effects); pushback P3-1).
- **Fix such a case where the rule is.** One promotion rule in Static.jl removed every run-time site on that path, and the steady state became faster than upstream's. The fix serves plain users too. It is not a workaround in the port.
- **What the wrap buys:** the package's compiled code survives loads. After the plotting packages loaded, the next simulation recompiled 0.04 s against 4.7 s unwrapped, and strict mode refused a pirate on ForwardDiff's duals that the unwrapped stack accepts (E-153; [evidence §1](../design/evidence.md#1-the-guarantee)).
- **Wrap the library, not the application.** With the workload's own module a trait module too, everything it reaches is compiled by facts in the session: the first plot took 48 against 16 s. A trait module's reach should be code a package image holds.
- **A trait at the library's internal calling convention can come first.** One trait (`ComponentDynamics`) and one family over the library's own parametric type serve the core loop's vertex and edge batches. The user's functions stay typed inside the key and leave every other type: the network's type is the same for both equations, and new equations compile 0.45 s instead of 15 s, nothing of it in SciML (E-152).
- **Values that decide types in hot code** (a dimension zero or not) go in the key, as type parameters of the implementing type.
- **A crossing has a cost per call; budget it.** Crossing from a kept value into a library's family member costs about what a plain function barrier does (~390 ns and one allocation on this build, E-152). A crossing per batch inside a right-hand side called thousands of times still shows: the steady state was 2–3× slower. Put the crossing where the work behind it is large, or measure it first in one session against the typed path.
- **Code that leans on static values folding** (a tuple sliced by a computed range) needs a typed path once those values are run-time values; `fully_typed` on the helper finds it.
- **A package's loop macro** (`Polyester.@batch`) hands its loop variables to that package's functions, not to a closure: the definition check refuses a trait object there. Read the expansion first.
- **Beside upstream's per-style methods,** one method on a `Union` of styles is ambiguous: one method per style, each calling a shared internal function.
- **After wrapping a package that other plain packages call on hot paths, profile the callers' steady state too.** A plain caller's `x.field` on a wrapped package's `getproperty` overload is typed by constant propagation into the facts code ([facts §6.3](../reference/facts.md#calls-between-the-modes)); without it, the steady-state solve doubled with SciMLBase wrapped and its callers plain (pushback P6-1). Check `x.field` against `getfield` (`ndport/scripts/p6_constprop_probe.jl`): every read should be as narrow.
- **Wrap the entry point of a call chain early.** Inside out, the cost of a wrapped core under plain callers lasted only until the package whose trait code calls those callers was wrapped (DiffEqBase), since plain packages reached from trait code are compiled by facts (E-155).
- **Profile the steady state by owner at each step;** the profiler's default-owner column shows plain callers that lost types. Order B and the image rejections at load (`ndport/scripts/p6_loadinv.jl`) explain load-time rises with no compilation in them.
- **Strict mode's refusal names the first fact only;** to see whose code a pirate would change, list the trait roots of its callee's backedges (`ndport/scripts/p6_pirate_roots.jl`).
- **`@joint_owners` works inside the wrap's `@trait_module begin … end`;** the census after loading tells whether the list of names is complete.
- **A full workload with strict mode on and Makie loaded refuses OffsetArrays' `reshape` pirate** (Base's own code is protected): expected, not a regression (pushback P6-2).
- **A trait over an informal interface** (E-154): check its name against the package's exports (`Graphs.Graph` is `SimpleGraph`); declare it in the interface's owner as plain code, so only the consumers' bounded functions are trait code; make common-word names `public` rather than exported; test it against the package's own generic test types and against a type whose method returns the wrong type; declare concrete arguments (`v::V`) so the member check infers each operation; bound the readers, not the front end that stores the user's object.
- **Before moving untyped code into a bounded function, check what its closures capture** (traits T-59), and test bounded calls from typed callers: a top-level loop over mixed types passes `Dynamic` values (traits T-58).
- **In a shared harness, select a variant by `Val`, not by a `Symbol` keyword:** a keyword made every default pass infer the variant's network too, 5 s more at the first step.
- **The first call of what a trait module reaches is compiled by facts in the session.** No image holds that code yet. NetworkDynamics' first fixed point took 21.9 s against 6.5 s plain, because NonlinearSolve's code reached from the trait module was compiled by facts. A precompile workload that covers the path moves this into the image.

### B6. Case study: SciML's architecture as traits

An analysis of SciML's source against the references, not a port: no Julia ran for it. It applies part 0's principles. The argument in full: [the SciML exploration](../explorations/sciml-as-traits.md). What the port measured on the same packages: B5. "SciML" here means SciMLBase, DiffEqBase, OrdinaryDiffEqCore and its solver packages, DiffEqCallbacks and SymbolicIndexingInterface, as cloned in `ndport/pkgs/`.

**The goals** ([exploration §1](../explorations/sciml-as-traits.md#1-the-goals-scimls-architecture-achieves)): what a user of SciML can do that a monolithic solver would not allow, and what the mechanism costs today.

| | Goal | Mechanism | What it costs |
|---|---|---|---|
| G-A | an open set of problem kinds | a tree of abstract types | a type has one kind; what a kind promises is a convention, with fallbacks that throw |
| G-B | an open set of algorithms: each solver package adds its own | methods of `__init`, `alg_order`, `alg_cache`, `perform_step!` on the solver's types | the front end's own methods live in DiffEqBase: pirates by the letter, 57 of 63 |
| G-C | one front end: `solve`, `init`, `step!` | CommonSolve's functions; DiffEqBase's keyword handling | about 1,400 lines per family, plain, which a load can discard (B2) |
| G-D | an open set of state and number types | `uType`, `tType`, `pType` parameters; promotion rules | promotion methods that win at signatures without their triggers' types (P6-3) |
| G-E | peak speed | everything a type parameter (`ODEIntegrator` has 26) | new equations recompile the core loop and the driver |
| G-F | low latency | six specialization levels; the function wrapped at fixed signatures | chosen per problem, not per position; listed exceptions |
| G-G | optional capabilities (Jacobian, mass matrix) | fields that are `nothing` when absent; predicates on the value | a given Jacobian's signature is unchecked until it runs |
| G-H | symbolic access: `sol[x]`, `integrator.ps[k]` | SymbolicIndexingInterface's method sets; `getproperty` switches | the switches' cost depends on the caller's mode (P6-1) |
| G-I | interactive stepping: `step!`, `add_tstop!`, `terminate!` | an informal method set on `DEIntegrator` | a new integrator type learns what it lacks at run time |
| G-J | events | callback types in the integrator's type | a new callback recompiles the driver |
| G-K | rebuilding a problem (`remake`) | keywords, plain | fine |
| G-L | refinement by extensions | 20 extensions of SciMLBase | a few win at signatures without their triggers' types |

**The pattern behind the costs.** SciML has one tool for an open set, the abstract type with methods, and one for speed, the type parameter. So the open sets have unchecked contracts, extension lands on the entry function, and speed and latency compete for the same type parameters.

**The same goals in Rust and Swift** ([exploration §2](../explorations/sciml-as-traits.md#2-the-same-goals-in-a-trait-idiomatic-language)):
- The open sets are traits with associated types. A solver crate adds `impl Algorithm<P> for Tsit5`, a model crate `impl OdeProblem for Network`. Neither touches `solve`.
- The front end is one generic function its owner writes; nobody overloads it. The orphan rule refuses DiffEqBase's shape, a method of a foreign function for a foreign type.
- Speed or latency is chosen per position, in the signature: `impl Trait` is compiled per type, `dyn Trait` once. SciML's function wrapper is `Box<dyn Fn(…)>` written in the type.
- The questions become declarations: `isinplace` is the one signature of `rhs`, `has_jac` a provided method or a supertrait, `alg_order` an associated constant. An integrator that lacks a required method does not compile.
- Swift compiles generic code once by default and specializes as an optimization. Its protocols require properties, as our traits declare fields. It allows a conformance from a third module, which its designers regret.

**SciML's mechanisms in the design** ([exploration §2.3](../explorations/sciml-as-traits.md#23-scimls-mechanisms-against-rusts-and-the-designs)):

| SciML today | The design |
|---|---|
| an abstract tree whose fallbacks throw | a trait, its operations checked at `@implement` ([§3](../reference/traits.md#3-trait-declarations), [§4.9](../reference/traits.md#49-checks-at-the-declaration)) |
| `uType`, `tType`, `pType`; `isinplace`; `f.jac === nothing`, `__has_jac` | the trait's parameters; the declared signature `rhs!(…)::Nothing`; a subtrait `ODEJacobian <: ODERHS` with a default operation (0.2) |
| `AbstractODEAlgorithm`, `alg_order(::Tsit5) = 5`, `__init(prob, alg::MyAlg)` | an `ODEAlgorithm` trait that each solver package implements for its own types; `init` a typed method naming the solver's own type, a stakeholder's ([§10.1](../reference/traits.md#101-who-may-implement), [§5.5](../reference/traits.md#55-dispatch-types-first-then-traits); below) |
| `solve(prob::AbstractDEProblem)` in DiffEqBase | a pirate by the letter, held by joint owners; principled: the body in the owner ([§10.1](../reference/traits.md#101-who-may-implement)) |
| `AutoSpecialize`'s function wrapper; `FullSpecialize` | `Callable{A, S}` at a struct parameter, `Dynamic` by default; `compiled_for(f)` at the constructor ([§5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature), [§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)) |
| the dual signatures | one bounded `Callable` parameter per signature, given the function itself (TraitDifferentialEquations' form; Rosenbrock runs on it); a tuple of `Callable`s ([§3.7](../reference/traits.md#37-tuples-of-traits), W-29) would make it one parameter |
| `DefaultODEAlgorithm`'s integer switch | `Vector{Dynamic{…}}`: the split over four, a table beyond ([facts §9](../reference/facts.md#dynamic-split)) |
| callback types in the integrator's type; `affect!(integrator)` with the whole integrator | `Vector{Callback}` ([§7.2](../reference/traits.md#72-a-traits-name-as-a-storage-type)); each callback sees `Dynamic{IntegratorView{U, T, P}}`, a trait of fields ([§3.3](../reference/traits.md#33-fields)) |
| SymbolicIndexingInterface's method sets; `getproperty(::DEIntegrator, :ps)` | `IndexProvider`, `ValueProvider`, forwarding with `by` ([§4.3](../reference/traits.md#43-forwarding-with-by)); a declared field or an operation, the sugar plain (0.2) |
| `remake` | plain (0.5) |

**The solvers are an open set.** Each solver package (OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock, Sundials) adds algorithm types, and the front end runs any of them. So the algorithm is a trait, and so is the integrator it builds:
- **`ODEAlgorithm`,** owned by SciMLBase: what the front end asks of any algorithm without the problem, as operations with declared results and defaults (`alg_order`, `isadaptive`). Each solver package implements it for its own algorithm types. A type that depends on the algorithm alone, such as a Rosenbrock method's tableau, can be a parameter each implementation states ([§4.6](../reference/traits.md#46-stating-parameters)).
- **`Integrator{U, T, P}`:** the stepping interface of G-I (`step!`, `add_tstop!`, `terminate!`, `set_proposed_dt!`), as operations. It extends the callbacks' `IntegratorView`, whose declared fields `u`, `t` and `p` define the parameters. Each integrator type implements it: OrdinaryDiffEqCore's `ODEIntegrator` as a family, Sundials its own.
- **`init` stays a typed method** naming the solver's own algorithm type, a stakeholder's method. It returns that solver's integrator. The owner's driver, `solve!(integ::Integrator)`, is a bounded function.
- **Inside a solver package the set is closed:** its caches, tableaus, `perform_step!` and controllers are types, selected by dispatch. The abstract algorithm tree stays beside the trait, for typed dispatch over related algorithms.

```julia
# a sketch, not yet run
@trait ODEAlgorithm begin                     # in SciMLBase
    alg_order(a::ODEAlgorithm)::Int
    isadaptive(a::ODEAlgorithm)::Bool = true
end
@implement ODEAlgorithm Tsit5 begin           # in OrdinaryDiffEqTsit5, which owns Tsit5
    alg_order(a::Tsit5) = 5
end
```

**The gap, recorded as pushback.** Rust ties the two traits together: `Algorithm<P>` names `type Integrator: Integrator<P>`, an integrator type per problem type. The design has no trait generic over another trait's implementer: no input parameters, no generic associated types ([§3.4](../reference/traits.md#34-parameters-and-associated-types), "Not offered"; [PB-A](../explorations/sciml-as-traits.md#5-pushback-where-the-principled-form-meets-the-references)). The cache depends on the algorithm and the state together, so it is no associated type of either. The closest form is the one above: each end checked at its `@implement`, the link between them at the first call, where `solve!` refuses an integrator that does not conform (a `MethodError` with the bound's hint, [§5.5](../reference/traits.md#55-dispatch-types-first-then-traits)). Every new solver package meets this gap.

**The shortest route** ([exploration §4](../explorations/sciml-as-traits.md#4-the-shortest-route)): the moves in order. Each keeps the results equal (0.6).

0. **Wrap by facts** (done; B5). Buys the guarantees: compiled code that survives loads, and strict mode. Not the shape: each move below removes a cost B5 met.
1. **The right-hand side as a trait; the function kept at a `Callable` bound.** `ODERHS{T, P}` with `rhs!(…)::Nothing`, and the subtraits `ODEJacobian` and `ODEMassMatrix`. `ODEFunction` conforms as a family, a user's model by its own `rhs!`. The record's `f` is a struct parameter bounded by `Callable`, as in TDE's `ODEProblem` (B2).
   - Replaces the function wrapper and the specialization levels for `f`, on the in-place path.
   - Buys: a new function or model compiles nothing in the solver, and its signature is checked.
   - Measured by proxy at NetworkDynamics' own seam (B5, E-152). Implicit methods' dual signatures run on one bounded `Callable` parameter per signature (TraitDifferentialEquations' form); a tuple of `Callable`s (W-29) would tidy it. A `Callable` call costs a few nanoseconds (~4 ns, `Dynamic`); the ~390 ns of P4-1 is an entry's crossing into a family member, not this call.
2. **Callbacks and the integrator as traits.** `Callback` with `condition` and `affect!`, kept as `Vector{Callback}`; callbacks see `IntegratorView`; the options' functions are `Callable` fields; every integrator type implements `Integrator`.
   - Replaces the callbacks and the options' functions as axes of the integrator's type, and the informal integrator interface.
   - Buys: a new callback compiles nothing in the solver; a new solver's integrator is checked at its `@implement`.
   - Not yet measured. The workload's line trips are events, so this move reaches it.
3. **The algorithms as an open set; the front end's body in its owner.** `ODEAlgorithm`, implemented by each solver package. The body of `solve` and `init` for `AbstractDEProblem` moves to SciMLBase, which owns the types; solver packages keep their typed methods on their own algorithm types. The default algorithm is a value of an owned type, chosen by the umbrella package through a bounded method with a trait it owns (0.2).
   - Replaces the joint-owner declarations that hold DiffEqBase's front-end methods, and the per-algorithm functions with fallbacks.
   - Buys: no pirate by the letter in the core, so strict mode holds without joint owners' exception ([§10.1](../reference/traits.md#101-who-may-implement), "What it costs"); a checked contract where an algorithm joins.
   - Needs L-3 retired (PB-F). It buys guarantees, not speed, so it comes after moves 1 and 2. It restructures SciML, which the port does not do: joint owners stand in for it (0.1a).
4. **Symbolic access as traits; the sugar plain.** `IndexProvider` and `ValueProvider`; `symbolic_container`'s delegation as `by` forwarding where the container is a field; `ps` an operation; the `getproperty` switches in the packages' ordinary modules.
   - Buys: getters compiled per index shape, not per provider. Trait callers read declared fields, so P6-1's cost falls away on the trait side; on the plain side, constant propagation into facts code (facts §6.3) keeps the sugar typed.
5. **The solution as a trajectory.** `Trajectory{U, T}` with `times`, `state` and `at`; `ODESolution` conforms and keeps its problem as a kept value. Buys: plotting compiled once per key, and a solution type independent of the model.

**What stays plain.**
- Each solver package's caches, tableaus, `perform_step!` and controllers: closed within the package, and fully typed over the key, so the facts mode costs them nothing.
- `remake`, the promotion helpers and the keyword front ends: per call, behind a barrier (0.5).
- The AD-rule extensions: methods on owned functions for their triggers' types.
- LinearSolve and NonlinearSolve behind their own front ends, until move 3 reaches them; ensembles.
- The abstract trees of problems and algorithms, beside the traits.

**Pushback** ([exploration §5](../explorations/sciml-as-traits.md#5-pushback-where-the-principled-form-meets-the-references)). Where the principled form meets a reference; none proposes a change (0.7).
- **PB-A.** A trait generic over another trait's implementer: the algorithm-to-integrator link is checked at the first call (above).
- **PB-B, PB-C.** No associated constants; asking a kept value for a capability is a trait cast (Optional). The stand-ins are 0.2's: operations with declared results, explicit type parameters, defaults where the fallback is correct.
- **PB-D.** The dual signatures take one bounded `Callable` parameter each; a tuple of `Callable`s (W-29, Planned) would make it one. SciML's chunk per problem is entered at `init` (the W-34 plan).
- **PB-E.** Boxing `p` behind a stable type (`AutoDespecialize`) needs a checked downcast of a kept value ([open issues §2](../open-issues.md#2-design), item 16). Until then `P` stays in the key.
- **PB-F.** The convenience `solve` without an algorithm is a bounded method on a foreign function, which L-3 limits today.
- **PB-G.** The `getproperty` sugar called from plain code: answered by constant propagation into facts code ([facts §6.3](../reference/facts.md#calls-between-the-modes); open issue 50, closed).
- **PB-H, PB-I, PB-J.** Keyword-heavy front ends stay plain (0.5); a `Dynamic` function takes at most six arguments (T-51; 0.4); a default algorithm over six solvers puts two beyond the split's four (0.4, "Which four").

---

## Proposed for part A

Rules one port shows; each links to its evidence.

- **A field users assign to converts at `X` when the value must be translated** (TraitMakie; B3 "Attributes").
- **Leave a function's attribute to the caller, one struct serving both** (TDE; B2 "A stored function").
- **Configure trait code by arguments or fields, not by a redefined `const`** (B4).
- **Splat only collections of a concrete element type** (B4).
- **Cover keyword sets and IO types in workloads** (the forks; B1 item 11).

---

## How this document is kept

- Part 0 is the method for a new port; it cites parts A and B and the references.
- Part A holds rules every port confirms, one line each.
- **Each port owns its section of part B** and adds to it as it goes, in the present tense: what holds, shown by the port.
- A case study in part B (B6) is an analysis of a package's architecture against the references, not a port. It says so, links its exploration, and keeps apart from the measured section of the same packages.
- A port proposes a rule for part A under "Proposed for part A", naming its evidence. Whoever merges (the coordinator of the port in progress) moves it into part A once a second port confirms it.
- Re-read the file before each edit: several ports edit it.
- Style: short sentences, bullets, one idea per sentence, an example for each rule, in the current spelling. Numbers live in [`../design/evidence.md`](../design/evidence.md); link them.
