# Porting to traits: a guideline

**Status, 2026-11-11.** The current design ([the references](../reference/README.md)). The examples are quoted from the ports on the unified build, each run by its package's suite; each quote is checked against the port's file (`experiments/docs-checks/check_quotes.py`):
- the forks of Tables, CSV and DataFrames (`forks-unified`, branch `unified`);
- TraitDifferentialEquations (`TraitDifferentialEquations-unified`);
- TraitMakie (`TraitMakie-unified`);
- NetworkDynamics (`ndport/pkgs/NetworkDynamics-unified`).

For people about to port a Julia package written without traits. It teaches and points: each rule's home is a reference.
- The language by example: [`traits-by-example.md`](traits-by-example.md).
- Why the design has its shape: [`../design.md`](../design.md).
- The terms: [`../glossary.md`](../glossary.md).
- The numbers: [`results.md`](results.md) and [the evidence](../design/evidence.md).

**A port does not change the design.** Where idiomatic trait code meets a rule that blocks a principled solution, the port records an [open issue](../open-issues.md): the case, the rule, a proposal. It does not build around the rule. A part the port needs whose status is Planned, or a Deviations row that blocks it, becomes a work item.

## Contents

- [The language in one screen](#the-language-in-one-screen)
- [Part 0. The method](#part-0-the-method)
- [Part A. Rules every port confirms](#part-a-rules-every-port-confirms)
- [Part B. What each port teaches](#part-b-what-each-port-teaches)
- [How this document is kept](#how-this-document-is-kept)

---

## The language in one screen

Write to TraitWorld's language, never to its internals: names that start with `_`, or that the references do not name.

| Construct | What a port uses it for | Home |
|---|---|---|
| `module M; using TraitWorld; @trait_module; … end` | a module compiled by facts, its methods at traits fully bounded, its pirates refused | [traits §13](../reference/traits.md#13-scopes-trait-modules) |
| `@trait_module bounded = false no_pirates = false` | an unchanged package compiled by facts, before its traits exist | [§13](../reference/traits.md#13-scopes-trait-modules) |
| `@trait X begin op(x::X, …)::R; … end` | the operations generic code needs, each with its result type | [§4.1](../reference/traits.md#41-operations) |
| `f::T`, `@const f::T` in the trait | stored data the code writes, or only reads | [§4.3](../reference/traits.md#43-fields) |
| `@trait X{T} begin T = eltype(Self); … end` | a parameter the member defines: by an equation of `Self`, a field's type, or stated | [§3.2](../reference/traits.md#32-parameters) |
| `op(x::X)::R = …` in the trait | a default, written with the other operations | [§4.2](../reference/traits.md#42-defaults) |
| `@trait B <: A`, `@trait B <: (A1, A2)` | supertraits | [§4.5](../reference/traits.md#45-supertraits) |
| `@default_dynamic`, `@default_compiled` in the trait | the trait's default attribute | [§4.6](../reference/traits.md#46-the-traits-default-attribute) |
| `@implement X T`, `@implement X T begin … end` | a type joins by its own methods | [§5.1](../reference/traits.md#51-the-forms)–[§5.4](../reference/traits.md#54-with-a-block-of-methods) |
| `@implement X T by f` | a type joins by forwarding to its field `f` | [§5.5](../reference/traits.md#55-forwarding-with-by) |
| `@implement X{T} S{T} where {T}`, `@implement X{T} AbstractVector{T} where {T}` | a family; an abstract type as a member | [§5.8](../reference/traits.md#58-families), [§5.9](../reference/traits.md#59-abstract-types-and-traits-as-members) |
| `f(t::X, i::Int)`, `f(a::X{T}, b::X{T}) where {T}`, `f(t::All{X, Y})` | methods at traits | [§6](../reference/traits.md#6-methods-at-traits), [§3.6](../reference/traits.md#36-intersections) |
| `@open f(…) = …` | a method that uses its trait argument beyond the contract on purpose, such as an adapter that stores it | [§7.3](../reference/traits.md#73-fully-bounded-methods) |
| `compiled_for(x)`, `with_dynamic(x)` at a call; `@specialize`, `@nospecialize` at a trait argument | the attribute: code compiled per type, or once | [§7.5](../reference/traits.md#75-what-decides), [§7.6](../reference/traits.md#76-casts) |
| `Dynamic{X}(x)`, `keep(x)`, `unwrap(d)` | a value kept beyond the call, with its attribute | [§7.7](../reference/traits.md#77-dynamicx), [§7.8](../reference/traits.md#78-keeping-an-argument-with-its-attribute) |
| `@nospecialize(io::IO)` at a display entry, `IOContext{IO}(io)` passed on | a stream erased: one compiled display for every stream type | [§9b](../reference/traits.md#9b-streams-io) |
| `field::X`, `Vector{X}`; `struct S{F <: X}; f::F; end` | storage typed by a trait; a struct parameter that records the attribute | [§8](../reference/traits.md#8-storage) |
| `f::Callable{Tuple{Float64}, Float64}` | a function argument at a declared signature | [§9](../reference/traits.md#9-functions-callable) |
| `Iterable{T}`, `Indexable{T}`, `retain!` | Base's concepts as traits, for a user's container | [§10](../reference/traits.md#10-collections) |
| `like(t, x)`, `withfields(t; …)` | a value like the input | [§6.5](../reference/traits.md#65-results) |
| `@joint_owners P1 P2` | the owners of a split package | [§12.1](../reference/traits.md#121-who-may-declare-a-membership) |
| `TraitWorld.strict!(true)` | refuse a pirate that would change code compiled by facts | [§12.3](../reference/traits.md#123-strict-mode) |
| `@enforce_concrete_only`, `@warn_on_abstract`, `@enforce_fully_typed`, `fully_typed(f, types)` | concrete parts; calls whose argument types are unknown | [§14](../reference/traits.md#14-concreteness-and-fully-typed-mode) |
| `check_definitions(M)`, `detect_unused_casts(M)`, `detect_dynamic_fallbacks(M)` | the checks a port's tests run | [§11](../reference/traits.md#11-checks-and-errors), [§7.6](../reference/traits.md#76-casts), [§14](../reference/traits.md#14-concreteness-and-fully-typed-mode) |

**Where the code or the design differs today**, the cases a port meets:
- **A trait argument passed to a higher-order function, or captured by a generator, makes a method open** ([open issue 165](../open-issues.md#2-design)). Write a loop over the elements, which is fully bounded, or mark the method `@open`.
- **A cast at a parameter no trait types has no effect** ([open issue 162](../open-issues.md#2-design)). Type a parameter that passes a trait's value on by its trait, and test that `detect_unused_casts(M)` is empty.
- **A record that holds a function before its signature is known holds it plain** ([open issue 159](../open-issues.md#2-design)): the library's default decides when the function is entered.
- **An argument typed by a bare `where` variable bounded by a trait** (`x::C`, `C <: X`) is compiled per type whatever its attribute ([compiler C-54](../reference/compiler.md#deviations); [open issue 163](../open-issues.md#2-design)).
- **A cast in a call with keyword arguments or a splatted argument is not lowered** ([lowering L-56](../reference/lowering.md#15-deviations)). Cast at a positional call.
- **The classification is not kept:** a later definition of a function that a method passes its trait argument to does not classify the method again ([compiler C-41](../reference/compiler.md#deviations)). Run `check_definitions(M)` in the tests.
- **A vararg of members is compiled per tuple of types,** not per tuple of keys, until keys are built ([traits §6.6](../reference/traits.md#66-keywords-defaults-varargs), Optional).

---

## Part 0. The method

**The path, in order.** Each step leaves a package that runs, with upstream's results. A package may stop after any step. What each step gains and costs is measured on the ports ([the evidence](../design/evidence.md) has the builds and the run counts); the commit is the port's that shows the step.

| Step | What changes in the package | What it gains | What it costs today |
|---|---|---|---|
| 1. Baselines | nothing: upstream on the unified build, a workload a user would run, digests of its results | the yardstick for every later step (0.6) | — |
| 2. Compiled by facts, as it is (0.1) | one line per module | **Most of the protection against loads.** Upstream CSV and DataFrames with their five dependencies: nine unrelated packages loaded afterwards end 0.4 % of their compiled instances, against 9.2 % plain; the work after the loads takes 0.48–0.66 s against 4.18–4.20 s, its first run 0.67–0.70 s against 3.03–3.06 s (E-355). Shown by forks `2306541` (CSV), `3939802` (DataFrames) | code that is not type-stable is slower at its run-time sites; a test that asserts an inferred type through one sees `Any` ([open issue 157](../open-issues.md#2-design)) |
| 3. The traits written down (0.2), the seams ported a function at a time (0.3) | the functions users extend become operations; generic code becomes methods at traits; extensions become memberships | Checked memberships and definitions: a mistake is an error where it is written. A new member ends no compiled code, in any load order (E-358). A member's package image holds the member's own code, not the library's again: 0.29× the instances of a plain twin's (E-360). Shown by forks `90b653a`, `30f77b3` | the entry functions are still lost to unrelated loads through the plain code of Base they call: the forks' work after the loads takes 0.96–0.98 s against 0.063 s first ([open issues](../open-issues.md#1-decisions-waiting-for-the-user) §1, GT-8). A method at a trait is checked again at each edit: 0.4 s, 2.8 s the first time in a session (GT-12) |
| 4. The attribute per position (0.4) | a default per trait, `keep` at a store, a cast at the hot loop | A new user type compiles its own code, not the library: NetworkDynamics' new equations 0.57 s against 6.6 s with the models stored as themselves (E-309, E-327); a second ODE model 0.05 s (E-324). Shown by NetworkDynamics `4e5f5a2`, `c9339fd` | code compiled once dispatches each operation when it runs; a hot loop left `Dynamic` by mistake ran at half speed until its kernel was typed by the trait (E-314; [open issue 162](../open-issues.md#2-design)) |
| 5. Pirates moved, strict mode (0.1) | each pirate moved to an owner; `no_pirates` on; the environment run under strict mode | the guarantee as a property of the environment, not a measurement ([the rationale §2.5](../design.md#25-the-default-following-pirates-and-what-it-gives-up)) | strict mode infers an image's memberships at its load (GT-2) |

**What a port does not do.** Each is a tension recorded for the design, not a problem for a port to solve ([the goals §3](../goals.md#3-tensions-between-the-goals)):
- **It does not turn a type the whole ecosystem specializes on into a trait to cure one slow step** (GT-10). A trait laid over such a type moves every caller. Where one entry compiles too much, it erases with the type's own eraser (0.4, A11).
- **It does not rewrite code to avoid the functions of Base that a load can invalidate** (GT-8). The tool `experiments/unification/w134/cause.jl` lists them for an environment; the list is evidence for the design.
- **It does not load TraitWorld late.** A package that uses the library loads it first; loaded after plain work, the library's methods on Base's functions end plain code compiled before it (GT-11).
- **It does not design around a rule** (the note at the top of this page).

### 0.1 Compiling an unchanged package by facts

- **The facts mode** ([facts §3](../reference/facts.md#3-fact-signatures), [§5](../reference/facts.md#5-run-time-sites)): a call is inferred only at a *fact signature*, where its argument types are known. Every other call is a *run-time site*: dispatched when it runs, its result typed `Any`.
- **What it buys** ([facts §2](../reference/facts.md#2-the-guarantees)): plain Julia's results or an error (G1); compiled code that no unrelated package's load discards (G2).
- **What it costs:** nothing for fully typed code. At a run-time site plain Julia infers from the methods that match today; the facts mode does not. After one run-time site, a call on its `Any` result is one too. Code over `Vector{Any}` gets slower ([evidence §1](../design/evidence.md#1-the-guarantee)).
- **How:** `@trait_module bounded = false no_pirates = false` in the package's module, before its first method. Its code is compiled by facts; nothing else changes.
  - DataFrames' fork does this for its whole module (`forks-unified/DataFrames/src/DataFrames.jl:139`), CSV's for its own (`forks-unified/CSV/src/CSV.jl:21`).
  - What it buys: the path's step 2 above (E-355). In the forks, plain packages loaded after CSV invalidated 752 of the forks' and TraitMakie's image instances while the reader was plain code; compiled by facts, the reader's image code stays valid, and the goal's read takes 0.03 s against 0.27 s (E-302).
  - **What it does not cover:** code compiled by facts keeps a dependency on each plain function it calls and builds on, Base's included. When a load invalidates such a function, its callers compiled by facts are compiled again ([facts §2.2](../reference/facts.md#22-g2-stable-caches), the scope).
- **Credit the right part.** The protection against loads is the facts mode's, for any code it compiles. Traits add checked memberships, code that says what it needs, and the choice between code compiled per type and code compiled once ([the rationale](../design.md)).
- **Submodules inherit the options.** The submodule that holds the trait code declares `@trait_module` again, every option on: DataFrames' `ColumnKernels` (`forks-unified/DataFrames/src/other/kernels.jl:15`), CSV's `ColumnParsers` (`forks-unified/CSV/src/ColumnParsers.jl:18`).
- **A package extension is a module of its own:** plain unless it declares `@trait_module`. One that only declares memberships needs none.
- **Pirates:** under `no_pirates` a pirate is refused at its definition (`OwnershipError`, [traits §12.2](../reference/traits.md#122-pirates)). Before turning it on, move each pirate to the package that owns the function or a type. A split package names its joint owners ([§12.1](../reference/traits.md#121-who-may-declare-a-membership)).
- **Workloads cover broad typical cases** (a `String` column, an `Int` column), not the workload's own data ([decisions §5](../record/decisions.md)).

### 0.2 Find the principled traits first

A trait names what generic code needs from a value, not how a type stores it.

- **Read the generic functions, not the types.** For each function users pass their own types to, list what it calls on the argument. That list is a trait.
- **Find the seams:** the functions users extend for their own types (a right-hand side, a callback, a column, a plot's positions). Each is an operation.
- **Traits for open sets, types for closed ones.** A set is open when packages other than its owner add members: columns, problems, callbacks, component models. A trait states what every member provides, checked at `@implement`. A set that one package holds whole, as a solver package holds its caches, stays a type hierarchy. `Number`, `Real` and `AbstractVector` stay; an abstract type can itself be a member of a trait:

  ```julia
  @trait Column{T} begin                                   # forks-unified/Tables/src/ColumnCore.jl:38
      T = eltype(Self)
      nrows(c::Column)::Int
      cell(c::Column{T}, i::Int)::T
      emptycells(c::Column{T}, n::Int)::Vector{T}
      take(c::Column, rows::AbstractVector{Int})::AbstractVector
      vector(c::Column)::AbstractVector
  end
  @implement Column{T} AbstractVector{T} where {T} begin   # :46: every vector is a column
      nrows(c) = length(c)
      cell(c, i) = @inbounds c[firstindex(c) + i - 1]
      emptycells(c, n) = Vector{eltype(c)}(undef, n)
      take(c, rows) = c[rows]
      vector(c) = c
  end
  ```
- **Operations or fields:** a declared field where code reads or writes stored data, `@const` where it only reads; an operation otherwise, with its result type. A default is written with the other operations:

  ```julia
  @trait ODEProblemTrait{T, P} begin     # TraitDifferentialEquations-unified/lib/ODECore/src/core.jl:56
      @const u0::Vector{T}
      @const tspan::Tuple{Float64, Float64}
      @const p::P
      rhs!(prob::ODEProblemTrait{T, P}, du::Vector{T}, u::Vector{T}, t::Float64)::Nothing
      jacobian!(prob::ODEProblemTrait{T, P}, J::Matrix{T}, u::Vector{T}, t::Float64)::Nothing = fd_jacobian!(prob, J, u, t)
      rhs_function(prob::ODEProblemTrait{T, P})::Any = nothing
  end
  ```
- **Questions about a type become declarations.** A library that asks types questions (`isinplace(f)`, `has_jac(f)`) answers each in the trait:
  - the call's form is the operation's signature, `rhs!(…)::Nothing`;
  - element and parameter types are the trait's parameters;
  - an optional capability is a default (the finite differences above), or a trait of its own.
- **A capability only some members have is a trait of its own,** and code that can use it has a method at both: `PooledColumn{T}` beside `Column{T}` (`forks-unified/Tables/src/ColumnCore.jl:60`).
- **Declared fields and operations, not `getproperty` switches.** A switch on a property's name (`integrator.ps`) stays sugar on the concrete type. Where a property is part of the contract, a supertrait names it:

  ```julia
  @trait IntegratorView{U, T, P} <: (HasProperty{:ps, ParameterView{P}}, HasSystem, ValueProvider{U, P}, IndexProvider{Symbol}) begin
      @const u::U                        # TraitDifferentialEquations-unified/lib/ODECore/src/core.jl:98
      ...
  ```
- **An informal interface becomes a trait over its existing functions.** Declare the operations with qualified names, and let the existing types join by their existing methods. A block of methods for an existing function serves only types the declaring package owns ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)).
- **How each type joins:**
  - by its own methods, in a block or after them;
  - by forwarding to a field that holds the data: `@implement Positions Live{Matrix{Float64}} by val` (`TraitMakie-unified/src/TraitMakie.jl:232`);
  - as a family, or as an abstract type: `@implement Positions AbstractVector{P} where {P <: AbstractVector{<:Real}}` (`TraitMakie-unified/src/PlotCore.jl:51`).
- **Extension is by membership, never by overloading the entry.** The owner writes the entry (`solve`, `DataFrame(x)`) once. A package that adds a member declares the membership, in an extension that names its triggers ([§12.1](../reference/traits.md#121-who-may-declare-a-membership)):

  ```julia
  @implement PooledColumn{T} PooledArray{T, R, 1, RA} where {T, R, RA}   # forks-unified/Tables/ext/TablesPooledArraysExt.jl:11
  ```
- **Concreteness is decided when the trait is published** ([§14](../reference/traits.md#14-concreteness-and-fully-typed-mode)): added later, it refuses members that joined.
- **Names:** an operation is a function of the trait's module, and a common name clashes on `using`. The forks name Tables' operations `tablenames`, `tablecolumn` and `tablerows`, not `nrow`, which DataAPI exports.

### 0.3 The order: seams first, a function at a time

- **Start where user types enter.** A function users pass their own types to is the first to take a trait.
- **One function at a time.** At each argument a closed type ranks before a trait ([traits §6.2](../reference/traits.md#62-specificity)). So upstream's methods on its own types and the port's methods at traits stand side by side, and a later membership never takes a call from a method on the type's own supertypes.
- **The kernels in a trait module with every option on.** A kernel reads a value only through the trait's operations. Where it needs Base's or a library's code over many values, it gathers them into a plain `Vector{T}` first: that code is compiled per element type and shared by every member (DataFrames' `describe`; `forks-unified/DataFrames/src/other/kernels.jl`, the module's comment).
- **A constructor from a trait goes through a named method at the trait.** `DataFrame(x)` stays plain and calls `fromsource(t::TableSource, copycols)`.
- **Keyword APIs:** the plain layer takes the keywords and builds a concrete options struct; the method at the trait takes it positionally.
- **Extensions add memberships, and plain methods for their triggers' types only.**

### 0.4 Where `Dynamic`, where `Compiled`

The attribute chooses speed, never results ([traits §7.4](../reference/traits.md#74-the-attribute-compiled-and-dynamic)).

- **Per position, not per problem.** A library's specialization levels become one attribute per position: the stored function, the callbacks, the model. The trait's default, the method's `@specialize` or `@nospecialize`, and the caller's cast decide ([§7.5](../reference/traits.md#75-what-decides)).
- **A new user type should not compile the library again.** Where user types enter and a large library stands behind, the trait's default is `Dynamic`, as for NetworkDynamics' component models:

  ```julia
  @trait ComponentDynamics begin          # ndport/pkgs/NetworkDynamics-unified/src/component_dynamics.jl:7
      @default_dynamic
      hasf(m::ComponentDynamics)::Bool
      ...
  ```
  `Callable`'s default is `Dynamic` too.
- **Store with `keep`, so the attribute survives the store:**

  ```julia
  _kept_model(::Type{VertexModel}, x::VertexDynamics) = keep(x)   # …/NetworkDynamics-unified/src/network_structure.jl:229
  ```
  The network's type then names none of the user's functions, and new equations compile no code over the network: 0.59–0.66 s, against 6.6 s with the models stored as themselves (E-309, E-314).
- **Open the hot loop with a cast,** at a parameter typed by the trait:

  ```julia
  _run_batch!(dispatchT(batch), compiled_for(batch.model), batches, k, args)              # …/coreloop.jl:147
  @inline _run_batch!(::Type{VertexModel}, m::VertexDynamics, batches, k, args) = run_vertex_batch!(m, batches, k, args)   # :154
  ```
  The batch's kernel is compiled per model. With `m` untyped the cast had no effect: the steady state took 436–475 ms against 228–257 ms (E-314; open issue 162).
- **A stored user function:** a constructor with a `Callable` argument at the declared signature, whose variables come from the other arguments, and `keep`:

  ```julia
  @open function ODEProblem(f::Callable{RHSSig{P,T},Nothing}, u0::AbstractVector{T}, tspan, p::P;
                      @nospecialize(callback = nothing)) where {T,P}     # …/ODECore/src/frontend.jl:63
      k = keep(f)
      ...
  ```
  By default the solver is compiled once per state and parameter type; `ODEProblem(compiled_for(f), …)` compiles it for the function. The constructor is `@open`: it stores its argument with its type.
- **Keep the user's types at the surface.** A user's type that only the user's own functions read never reaches the core. TDE's problem keeps the right-hand side partially evaluated on the parameters, `(du, u, t)`, so the solver is compiled per state type whatever the parameters.
- **Hand a callback the integrator by its trait, `Dynamic`:** `affect!(cb::Callback{U, T, P}, integ::Dynamic{IntegratorView{U, T, P}})::Nothing` (`…/ODECore/src/core.jl:122`). A new callback compiles its own function, not the solver.
- **Mixed collections:** a field or element typed by the trait, `columns::Vector{Column}` (`forks-unified/DataFrames/src/dataframe/dataframe.jl:181`). Each item is the member's own value. An operation on it calls the member's method directly for the trait's first four members, and through a table beyond them ([§7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)).
- **What the caller passes:** at the prompt values are `Dynamic`; in a function that knows their types, `Compiled` ([§7.5](../reference/traits.md#75-what-decides), step 5). Test a `Compiled` path from inside a function, or with `compiled_for`.

**A value of a plain abstract type, which plain code specializes on.** A stream is the common case: `show(io, x)` hands `io` to code compiled per stream type, and at a REPL the stream is a type no workload at an `IOBuffer` sees ([traits §9b](../reference/traits.md#9b-streams-io)).
- **A display needs nothing from the port.** The REPL's display and Base's `TextDisplay` erase the stream themselves: `show` is called with `IOContext{IO}`, so a package's `show` methods stay plain code and are compiled once for every stream ([traits §9b](../reference/traits.md#9b-streams-io)). The workload displays once at `IOContext{IO}(IOBuffer())`, by the MIME entry the REPL takes: `show(IOContext{IO}(IOBuffer()), MIME"text/plain"(), x)`.
- **Elsewhere, erase at the entry where large code serves many value types.** The rule is §7.10's: `Dynamic` suits large code with many members behind it; `Compiled` suits kernels. Outside a display, such an entry declares `@nospecialize(io::IO)` and passes the stream on erased:

  ```julia
  function Base.show(@nospecialize(io::IO), t::Table)   # traits §9b: one compiled body for every stream
      render(IOContext{IO}(io), t)
  end
  ```
  Below the entry the stream is one type, so the body and everything it calls is compiled once, and a package image's workload at an `IOBuffer` covers the REPL's stream, a file's and a notebook's. Above it, code that knows its stream keeps Julia's code per type.
- **Use the type's own eraser, never a box of the port's.** `Dynamic{X}` is a member of its trait only ([§7.7](../reference/traits.md#77-dynamicx)): it is not an `IO`, so code typed `io::IO` refuses it. Base's `IOContext{IO}` is an `IO`; it forwards the whole stream interface, a terminal's size and colour included, and carries the context's properties (`:limit`, `:compact`). A wrapper written in a port forwards the operations its author thought of and takes the default for the rest: `displaysize` from the environment, not the terminal.
- **Small per-call kernels stay per type.** Below an erased entry each operation on the stream branches over Julia's four common streams, about 4 ns ([§7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). Formatted output does far more work per operation, so it pays within 20 % (`print` of numbers 0.85–1.19×, a table's display 0.92–0.99×); a byte or a short string per call pays 1.6–2.2× (E-328). So the erasure sits at the display entry, not at `string(…)`, `sprint` or a `print` of short strings, and a loop that writes a byte per call is reached from code that knows its stream.
- **The workload runs at the erased type, by the path the REPL takes.** A package image holds what its workload ran: a display at `IOContext{IO}(IOBuffer())` is the REPL's display, a text display's and an erased entry's. A workload at a plain `IOBuffer` covers an `IOBuffer` only.
- **What the erasure fixes, and what it leaves.** It removes the port's own code compiled per stream type: DataFrames' `show` step 0.081 s against 0.175 s (E-323). What a step still compiles after it is outside the port: the REPL's own path at its stream (about 30 ms) and Base's code at the cells' types (about 50 ms). Credit the right part, as in 0.1.

### 0.5 What to keep plain

- Bookkeeping, macros, printing, options parsing, `getproperty` sugar.
- **Rebuilding: plain and thin,** behind a function barrier. What a trait declares is rebuilt with `withfields` and `like` ([§6.5](../reference/traits.md#65-results)); such a method is open, marked `@open` in a trait module.
- Abstract type hierarchies that are right as they are.
- **Not the front end.** A package's entry functions (`solve`, `read`) belong to a trait module, as the code under them does. A front end compiled plainly is lost to unrelated loads as any plain code is, and it is the first thing each call runs.
- Code that is not type-stable gets slower when compiled by facts. Keep it out of the facts mode where trait code does not call it, or make it fully typed.

### 0.6 How to check

- **Per step:** the workload's digests against upstream's, and a chosen part of upstream's suite: minutes at most. **At milestones:** the full suites. Outside performance work, no benchmarks.
- **Every step keeps results equal.** The attribute and the mode change speed, never results. Compare with `==`: the same arithmetic gives the same bits.
- **The tests a port adds:**
  - `check_definitions(M)` empty for each trait module;
  - `detect_unused_casts(M)` empty (the ports' tests check it);
  - `fully_typed(f, types)` for each hot loop.
- **The tools:**
  - `--trace-compile=stderr --trace-compile-timing`, with a mark per step: what each step compiles;
  - `JULIA_DISPATCH_PROFILE=1`: dynamic calls per callee, lookup path and call site ([compiler §11](../reference/compiler.md#11-changes-useful-without-traits));
  - `verify_main`: what a program reaches ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).
- **Time a step twice in one session:** the second time separates run time from compiling. Say how many runs.
- **A control at the same load.** On a shared machine a session's time moves 2–3× with the load. A number compared across builds is run beside its control: the unchanged build's form of the same session, interleaved, at the same load (E-329, E-330, E-336). Say the load (`/proc/loadavg`) and the number of runs. A number without a control at its load compares with nothing.
- **Measure the step the change was made for, on every build that carries it.** A fix that moves the goal's task can leave that step where it was.
- **A compile at a type the workload never saw** names one of two things: a broad case missing from the workload, or a value type that plain code specializes on, which an entry erases (0.4). `--trace-compile` tells which.
- **An erased entry's own checks:** the digests equal; the display's run time after its first call within 10 % (E-323: +9 % on a 10⁴-row frame); the step's compiles traced, since what still compiles names what still carries the stream's type.

---

## Part A. Rules every port confirms

One line per rule; the evidence is in part B, the rule's home in the references.

- **A1. Say what code needs:** fields and containers typed by a trait, results declared ([traits §4](../reference/traits.md#4-declaring-a-trait), [§8](../reference/traits.md#8-storage); B1, B3).
- **A2. Make the hot path fully typed:** a run-time site's result is `Any` ([facts §5](../reference/facts.md#5-run-time-sites); B1).
- **A3. The kernels in a trait module with every option on; the package around them compiled by facts** ([§13](../reference/traits.md#13-scopes-trait-modules); B1).
- **A4. Extensions become memberships,** naming each trigger ([§12.1](../reference/traits.md#121-who-may-declare-a-membership); B1).
- **A5. Keep plain what is plain,** and adopt traits one function at a time ([§6.2](../reference/traits.md#62-specificity); 0.3, 0.5).
- **A6. Upstream's tests decide** (B1).
- **A7. A kernel reads a value through its trait's operations; heavy library code runs over gathered values** (B1).
- **A8. Store a trait argument with `keep`; type a parameter that passes it on by its trait** ([§7.8](../reference/traits.md#78-keeping-an-argument-with-its-attribute), [§7.6](../reference/traits.md#76-casts); B2, B4).
- **A9. Take user types `Dynamic` where a large library stands behind; open the hot loop with a cast** ([§7.5](../reference/traits.md#75-what-decides); B2, B4).
- **A10. Erase a value plain code specializes on at the entry where large code serves many value types; kernels stay per type** ([§7.10](../reference/traits.md#710-costs-and-choosing), [§9b](../reference/traits.md#9b-streams-io); 0.4, B1).
- **A11. A plain abstract type's value is erased by that type's own eraser,** `IOContext{IO}` for a stream, never by a box of the port's ([§9b](../reference/traits.md#9b-streams-io), [§7.7](../reference/traits.md#77-dynamicx); 0.4, B1).

---

## Part B. What each port teaches

### B1. Tables, DataFrames, CSV

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 (`forks-unified`, branch `unified`). Traits: `Column{T}`, `PooledColumn{T}`, `TableSource` in Tables' `ColumnCore`; `CSVSource`, `CSVColumn{T} <: Column{T}`, `TextColumn{T} <: Column{T}` in CSV's `ColumnParsers`.

1. **The package compiled by facts, the kernels fully bounded.** DataFrames and CSV are trait modules with `bounded` and `no_pirates` off; `ColumnKernels` and `ColumnParsers` have every option on (0.1).
2. **A kernel reads through the operations,** and heavy code runs over gathered cells: `describe` gathers into `emptycells(c, n)::Vector{T}` and runs Statistics there, compiled once per `T` (A7).
3. **A capability is a trait of its own:** `PooledColumn` beside `Column`, joined by PooledArrays' and CategoricalArrays' vectors in Tables' extensions (A4).
4. **A type passed as a value:** `stringtype = String15` passes a type; the reader makes `S[]` and calls `TextColumn`'s operations on it, and CSV's InlineStrings extension declares memberships only (`forks-unified/CSV/ext/CSVInlineStringsExt.jl:87`).
5. **A function applied per row is open on purpose** where it asks for its result type: `@open function byrow(f::Callable{Tuple{T}}, c::Column{T}) where {T}` computes `Base.promote_op(f, T)`, as `map` does (`forks-unified/Tables/src/ColumnCore.jl:105`; [traits §9](../reference/traits.md#9-functions-callable)).
6. **Mixed columns in one vector:** `DataFrame`'s `columns::Vector{Column}` holds each vector itself; the kernels over it (`joinkeys`, `_group_rows!`) take `Vector{Column}`.
7. **Upstream's tests decide** (A6). The forks pass their upstream suites but for four known failures in DataFrames (E-315): three `@inferred` tests see `Any` through run-time sites in facts code ([open issue 157](../open-issues.md#2-design)), and one in Tables' integration.
8. **A stream's type, which plain code specializes on:** DataFrames' `show(io, df)` hands the stream to PrettyTables, plain code compiled per stream type, and at a REPL the stream was `IOContext{REPL.LimitIO{TTYTerminal}}`, which no workload at an `IOBuffer` sees. The REPL's display now erases the stream ([traits §9b](../reference/traits.md#9b-streams-io)): DataFrames' code stays as upstream's, and its workload displays once at `IOContext{IO}(IOBuffer())` (0.4). The `show` step 0.087 s against 0.16–0.20 s without the line, and the session's `write` step 0.12 s against 0.5 s, since the REPL's display of the returned path is compiled once too (E-338).

### B2. Differential equations

TraitDifferentialEquations (`TraitDifferentialEquations-unified`): a solver core (`ODECore`), Rosenbrock and implicit methods, nonlinear solvers, and SciML's front end. Traits: `ODEProblemTrait{T, P}`, `IntegratorView{U, T, P}`, `Callback{U, T, P}`, `EventCallback{U, T, P}`, `StepView{U, T}`, and SymbolicIndexingInterface's concepts in `TraitIndexing`.

1. **The problem's function enters at a declared signature,** kept with its attribute (0.4): compiled once per state and parameter type by default, per function under `compiled_for`.
2. **The parameters stay at the surface:** the problem keeps the right-hand side partially evaluated on them.
3. **Callbacks see the integrator as `Dynamic{IntegratorView{…}}`:** a new callback compiles its own function only.
4. **Properties of the contract are supertraits:** `HasProperty{:ps, ParameterView{P}}` (0.2).
5. **A record that holds a function before its signature is known** (`ODEFunction`, a callback's functions) holds it plain, and the library's default decides when the function is entered ([open issue 159](../open-issues.md#2-design)).
6. Measured: setting D (load, solve, plot, then a second model) 2.00–2.04 s; the second model 0.05 s, so a new right-hand side compiles no solver (E-324; [results](results.md#sessions-against-python)).

### B3. Plotting and the report

TraitMakie (`TraitMakie-unified`) and TraitReport (`TraitReport-unified`). Traits: `Positions`, `Sample`, `ColorSpec`, `Colormap`, `MarkerShape`, `Scale`, `Plot` in `PlotCore`; `Table`, `Job` in `ReportCore`.

1. **The plain layer converts, the trait code draws:** `x, y` become the n × 2 `Matrix{Float64}` that `Positions` serves (`TraitMakie-unified/src/PlotCore.jl:38`).
2. **A wrapper joins by forwarding:** `Live{Matrix{Float64}}` forwards `Positions` to its field `val`, so it shares the code compiled for the field's type.
3. **Families over Base's types:** every vector of real vectors is a `Positions` (`PlotCore.jl:51`), every `Vector` of reals a `Sample`.
4. Measured: the goal's task (CSV → `DataFrame` → summary → histogram PNG) 1.59–1.63 s in a fresh process, against Python's 0.63–0.65 s; with the project's own reader and table library 0.74–0.78 s (E-324; [results](results.md)).

### B4. Networks of dynamical systems: NetworkDynamics

NetworkDynamics (`ndport/pkgs/NetworkDynamics-unified`), with Graphs' and GraphMakie's ports. Traits: `ComponentDynamics`, `VertexDynamics <: ComponentDynamics`, `EdgeDynamics <: ComponentDynamics`.

1. **The components' traits default to `Dynamic`,** and a batch keeps its model with `keep` (0.4). The default applies to the library's own type that wraps a user's function, `FunctionDynamics{typeof(f)}`, since a type counts as the library's own only with its parameters ([open issue 161](../open-issues.md#2-design), (a)).
2. **The kernel opens the model with a cast at a parameter typed by the trait** (0.4; [open issue 162](../open-issues.md#2-design)).
3. Measured: new equations in a running session 0.57 s; the workload's steady state 237–241 ms, against 776–780 ms on the earlier build (E-327).

---

## How this document is kept

- Each example names the file and line it is quoted from; that package's suite runs it. When the design changes, the ports follow it, and the examples here follow the ports.
- A port adds to part B what it learns, and to part A a rule that every port confirms.
- A rule a port finds weak becomes an [open issue](../open-issues.md), with the case, the rule and a proposal.
