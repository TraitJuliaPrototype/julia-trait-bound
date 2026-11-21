# Porting to traits: a guideline

For people about to port a Julia package written without traits. It teaches and points: each rule's home is a reference.
- The language by example: [`traits-by-example.md`](traits-by-example.md).
- Why the design has its shape: [`../design.md`](../design.md).
- The terms: [`../glossary.md`](../glossary.md).
- The numbers: [`results.md`](results.md) and [the evidence](../design/evidence.md).

**The examples are quoted from the ports,** each run by its package's suite. Each quote is checked against the port's file (`experiments/docs-checks/check_quotes.py`):
- the forks of Tables, CSV and DataFrames (`forks`);
- TraitDifferentialEquations (`TraitDifferentialEquations`);
- TraitMakie (`TraitMakie`);
- NetworkDynamics (`ndport/pkgs/NetworkDynamics-unified`).

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
| `module M; using TraitWorld; @trait_module; … end` | a module compiled by facts, its methods at traits bounded, its pirates refused | [traits §13](../reference/traits.md#13-scopes-trait-modules) |
| `@trait_module bounded = false no_pirates = false` | an unchanged package compiled by facts, before its traits exist | [§13](../reference/traits.md#13-scopes-trait-modules) |
| `@trait X begin op(x::X, …)::R; … end` | the operations generic code needs, each with its result type | [§4.1](../reference/traits.md#41-operations) |
| `f::T`, `@const f::T` in the trait | stored data the code writes, or only reads | [§4.3](../reference/traits.md#43-fields) |
| `@trait X{T} begin T = eltype(Self); … end` | a parameter the member defines: by an equation of `Self`, a field's type, or stated | [§3.2](../reference/traits.md#32-parameters) |
| `op(x::X)::R = …` in the trait | a default, written with the other operations | [§4.2](../reference/traits.md#42-defaults) |
| `@trait B <: A`, `@trait B <: (A1, A2)` | supertraits | [§4.5](../reference/traits.md#45-supertraits) |
| `@default_dynamic` in the trait | the trait erases by default: its methods take a plain member boxed | [§4.6](../reference/traits.md#46-erasing-by-default), [§7.8](../reference/traits.md#78-erasing-by-default-the-forwarder) |
| `@implement X T`, `@implement X T begin … end` | a type joins by its own methods | [§5.1](../reference/traits.md#51-the-forms)–[§5.4](../reference/traits.md#54-with-a-block-of-methods) |
| `@implement X T by f` | a type joins by forwarding to its field `f` | [§5.5](../reference/traits.md#55-forwarding-with-by) |
| `@implement X{T} S{T} where {T}`, `@implement X{T} AbstractVector{T} where {T}` | a family; an abstract type as a member | [§5.8](../reference/traits.md#58-families), [§5.9](../reference/traits.md#59-abstract-types-and-traits-as-members) |
| `f(t::X, i::Int)`, `f(a::X{T}, b::X{T}) where {T}`, `f(t::All{X, Y})` | methods at traits | [§6](../reference/traits.md#6-methods-at-traits), [§3.6](../reference/traits.md#36-intersections) |
| `@unbounded f(…) = …` | a method that uses its trait argument beyond the contract on purpose, such as an adapter that stores it | [§7.3](../reference/traits.md#73-bounded-methods) |
| `Dynamic{X}(x)` | the box: the member erased; code for it is compiled once per trait instance | [§7.7](../reference/traits.md#77-dynamicx) |
| `compiled_for(x)` | the wrapper: the member with its type; code for it is compiled for the object's type | [§7.6](../reference/traits.md#76-compiled_forx) |
| `unwrap(t)` | the object a box or a wrapper holds | [§7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper) |
| `@nospecialize(io::IO)` at a display entry, `IOContext{IO}(io)` passed on | a stream erased: one compiled display for every stream type | [§9b](../reference/traits.md#9b-streams-io) |
| `field::X`, `Vector{X}`, `Vector{Dynamic{X}}`; `struct S{F <: X}; f::F; end` | storage typed by a trait; it keeps the form it is given | [§8](../reference/traits.md#8-storage) |
| `f::Callable{Tuple{Float64}, Float64}` | a function argument at a declared signature | [§9](../reference/traits.md#9-functions-callable) |
| `Iterable{T}`, `Indexable{T}`, `retain!` | Base's concepts as traits, for a user's container | [§10](../reference/traits.md#10-collections) |
| `like(t, x)`, `withfields(t; …)` | a value like the input | [§6.5](../reference/traits.md#65-results) |
| `@joint_owners P1 P2` | the owners of a split package | [§12.1](../reference/traits.md#121-who-may-declare-a-membership) |
| `TraitWorld.strict!(true)` | refuse a pirate that would change code compiled by facts | [§12.3](../reference/traits.md#123-strict-mode) |
| `@enforce_concrete_only`, `@warn_on_abstract`, `@enforce_fully_typed`, `fully_typed(f, types)` | concrete parts; calls whose argument types are unknown | [§14](../reference/traits.md#14-concreteness-and-fully-typed-mode) |
| `check_definitions(M)` | the check a port's tests run | [§11](../reference/traits.md#11-checks-and-errors) |

**What a port meets today:**
- **An interface that sibling packages extend is `public` in the core package.** A function of a trait module is owner-only by default, so a sibling package's method of it is a pirate's ([open issue 212](../open-issues.md#2-design)).
- **A callable struct that is no `Function` is declared a member of `Callable`** by its owner: `@implement Callable MyCallable` ([traits §9](../reference/traits.md#9-functions-callable); [GT-32](../open-issues.md#2-tensions-between-the-goals)).
- **A test that asserts an inferred type through a run-time site sees `Any`** ([open issue 157](../open-issues.md#2-design)). A kernel whose result callers rely on becomes an operation of the trait, with a default.
- **A vararg of members is compiled per tuple of types** ([traits §6.6](../reference/traits.md#66-keywords-defaults-varargs)).
- What else the implementation does not do as the references state is in their Deviations tables ([the state](../state.md)).

---

## Part 0. The method

**The path, in order.** Each step leaves a package that runs, with upstream's results. A package may stop after any step. What each step gains and costs is measured on the ports ([the evidence](../design/evidence.md) has the builds and the run counts).

| Step | What changes in the package | What it gains | What it costs |
|---|---|---|---|
| 1. Baselines | nothing: upstream on Julia with the design's changes, a workload a user would run, digests of its results | the yardstick for every later step (0.6) | — |
| 2. Compiled by facts, as it is (0.1) | one line per module | **Most of the protection against loads.** Upstream CSV and DataFrames: nine unrelated packages loaded afterwards end 14 of 3,490 of their compiled instances, against 424 of 4,693 plain. The work after the loads takes 1.71–1.73 s against 5.17–5.29 s, its first run 1.88–1.89 s against 4.13–4.26 s (E-392) | code that is not type-stable is slower at its run-time sites; a test that asserts an inferred type through one sees `Any` ([open issue 157](../open-issues.md#2-design)) |
| 3. The traits written down (0.2), the seams ported a function at a time (0.3) | the functions users extend become operations; generic code becomes methods at traits; extensions become memberships | Checked memberships and definitions: a mistake is an error where it is written. A new member ends no compiled code, in any load order (E-378). A member's package image holds the member's own code, not the library's again: 42 instances against a plain twin's 146 (E-380) | the entry functions are still lost to unrelated loads through the plain code of Base they call: the forks' work after the loads takes 2.22–2.25 s against 0.18–0.19 s first ([GT-8](../open-issues.md#2-tensions-between-the-goals); E-392). A method at a trait is checked again at each edit: 0.65 s for a session's first edit, then 0.48–0.50 s ([GT-12](../open-issues.md#2-tensions-between-the-goals); E-391) |
| 4. Erasing per position (0.4) | a default per trait, a box where a value is stored, a wrapper at the hot loop | a new user type compiles its own code, not the library | erased code dispatches each operation when it runs; a plain member passed to a method of a trait that erases by default is boxed at each call |
| 5. Pirates moved, strict mode (0.1) | each pirate moved to an owner; `no_pirates` on; the environment run under strict mode | the guarantee as a property of the environment, not a measurement ([the rationale §2.5](../design.md#25-the-default-following-pirates-and-what-it-gives-up)) | strict mode infers an image's memberships at its load ([GT-2](../open-issues.md#2-tensions-between-the-goals)) |

**What a port does not do.** Each is a tension recorded for the design, not a problem for a port to solve ([the open issues §2](../open-issues.md#2-tensions-between-the-goals)):
- **It does not turn a type the whole ecosystem specializes on into a trait to cure one slow step.** A trait laid over such a type moves every caller. Where one entry compiles too much, it erases with the type's own eraser (0.4, A11).
- **It does not rewrite code to avoid the functions of Base that a load can invalidate** (GT-8). The tool `experiments/implementation/w134/cause.jl` lists them for an environment; the list is evidence for the design.
- **It does not design around a rule** (the note at the top of this page).

**A change that follows a rule of the references is not a workaround.** Erasing a stream at a display entry, declaring a result, making a sibling's interface `public`: each is the design used as intended. A workaround is code that exists only because a rule blocks the principled form; that case becomes an open issue.

### 0.1 Compiling an unchanged package by facts

- **The facts mode** ([facts §3](../reference/facts.md#3-fact-signatures), [§5](../reference/facts.md#5-run-time-sites)): a call is inferred only at a *fact signature*, where its argument types are known. Every other call is a *run-time site*: dispatched when it runs, its result typed `Any`.
- **What it buys** ([facts §2](../reference/facts.md#2-the-guarantees)): plain Julia's results or an error (G1); compiled code that no unrelated package's load discards (G2).
- **What it costs:** nothing for fully typed code. At a run-time site plain Julia infers from the methods that match today; the facts mode does not. After one run-time site, a call on its `Any` result is one too. Code over `Vector{Any}` gets slower ([evidence, G-4](../design/evidence.md)).
- **How:** `@trait_module bounded = false no_pirates = false` in the package's module, before its first method. Its code is compiled by facts; nothing else changes.
  - DataFrames' fork does this for its whole module (`forks/DataFrames/src/DataFrames.jl:139`), CSV's for its own (`forks/CSV/src/CSV.jl:21`).
  - What it buys: the path's step 2 above (E-392).
  - **What it does not cover:** code compiled by facts keeps a dependency on each plain function it calls and builds on, Base's included. When a load invalidates such a function, its callers compiled by facts are compiled again ([facts §2.2](../reference/facts.md#22-g2-stable-caches), the scope).
- **Credit the right part.** The protection against loads is the facts mode's, for any code it compiles. Traits add checked memberships, code that says what it needs, and the choice between code compiled per type and code compiled once ([the rationale](../design.md)).
- **Submodules inherit the options.** The submodule that holds the trait code declares `@trait_module` again, every option on: DataFrames' `ColumnKernels` (`forks/DataFrames/src/other/kernels.jl:15`), CSV's `ColumnParsers` (`forks/CSV/src/ColumnParsers.jl:18`).
- **A package extension is a module of its own:** plain unless it declares `@trait_module`. One that only declares memberships needs none.
- **Pirates:** under `no_pirates` a pirate is refused at its definition (`OwnershipError`, [traits §12.2](../reference/traits.md#122-pirates)). Before turning it on, move each pirate to the package that owns the function or a type. A split package names its joint owners ([§12.1](../reference/traits.md#121-who-may-declare-a-membership)), and its core declares the interface its siblings extend `public`.
- **Workloads cover broad typical cases** (a `String` column, an `Int` column), not the workload's own data.

**What makes a run-time site in ordinary code, and the answer for each.** Ordinary packages are full of them. The tool that lists them is `fully_typed(f, types)`; the dispatch profiler (`JULIA_DISPATCH_PROFILE=1`) says which ones run often.

| The source | The answer |
|---|---|
| a container of `Any`, or of an abstract type (`Vector{AbstractVector}` of columns) | storage typed by a trait, read through its operations (0.2); heavy code over gathered values (0.3) |
| a type passed as a value and dispatched on (`stringtype = String15`) | a membership the type's package declares; the reader calls the trait's operations on a value of the type (B1) |
| an option typed by a union | a concrete options struct built by the plain layer (0.3) |
| keyword splats | the plain layer takes the keywords; the method at the trait takes the struct positionally (0.3) |
| a result type computed by inference (`collect`, a broadcast, a comprehension) | **declare the element type:** the library knows it and does not write it. `emptycells(c, n)::Vector{T}` in place of a `collect` |
| a record built from a value typed `Any` (a system handle read through an operation declared `::Any`): the constructor is a run-time site, and its result `Any` | a declared result on the function that builds the record |
| an option kept in a run-time field that chooses a type (`Val(n)` of a `Union{Nothing, Int}` field) | a type parameter of the option's record, set where the program makes it (`Rodas5{L, CS}`) |
| a `@nospecialize(f)` helper that takes a function | take the kept form and `unwrap` it, or declare `@nospecialize(f::Callable{A, S})` |
| a function barrier whose callee others may extend | an operation of the trait with a declared result ([open issue 157](../open-issues.md#2-design)) |

**The silent hazards of step 2.** Results stay equal, nothing warns, and code gets slow:
- a package that leans on Base folding a type computation for plain code (a promotion through `typejoin`): under the facts rule each such call dispatches when it runs;
- a plain caller's constant propagation into a `getproperty` switch of the package.

Run the dispatch profiler on the workload after the step. It names the callee and the call site.

### 0.2 Find the principled traits first

A trait names what generic code needs from a value, not how a type stores it.

**Before the first trait: an inventory.** List what the port will need from the design, move by move, against the references' status lines and Deviations tables. Probe each part that is Implemented and unused so far with a small case, minutes each. A part that is Planned becomes a work item before the port reaches it.

**Where a plain package compiles per user type or loses its code.** Look for these shapes first; each names a seam:
1. a package extension that adds methods to another package's internal functions;
2. types passed as values and dispatched on when the code runs;
3. storage of an abstract element type, with a function barrier per item;
4. specializations per tuple of the user's types (group, sort, join over columns);
5. types per schema (a type parameter that holds names and types; generated functions);
6. `@nospecialize` barriers as the cure: they bound compile time, and every call behind one is a run-time site;
7. printing through a generic printer at abstract types.

**Compilation is keyed three ways:** on the library, on the user's model or data, and on the call's shape (a keyword tuple, a range against a vector). Code is kept in an image only where its keys recur. So keep the user's types out of the library's keys: normalize at the entry, and keep the user's parameters in the outermost layer.

- **Read the generic functions, not the types.** For each function users pass their own types to, list what it calls on the argument. That list is a trait.
- **Find the seams:** the functions users extend for their own types (a right-hand side, a callback, a column, a plot's positions). Each is an operation.
- **The first trait is an interface the ecosystem already has informally.** Generic functions that types extend (Graphs' `nv`, `ne`, `outneighbors`) become a trait over the existing functions. Declare the operations with qualified names, and let the existing types join by their existing methods, as a family over the abstract type. A block of methods for an existing function serves only types the declaring package owns ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)).
- **Traits for open sets, types for closed ones.** A set is open when packages other than its owner add members: columns, problems, callbacks, component models. A trait states what every member provides, checked at `@implement`. A set that one package holds whole, as a solver package holds its caches, stays a type hierarchy. `Number`, `Real` and `AbstractVector` stay; an abstract type can itself be a member of a trait:

  ```julia
  @trait Column{T} begin                                   # forks/Tables/src/ColumnCore.jl:38
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
- **The trait's parameter holds what the hot code must know, and no more:** the cell type, not the column's container type; the state's element type, not the user's model.
- **Operations or fields:** a declared field where code reads or writes stored data, `@const` where it only reads; an operation otherwise, with its result type. A default is written with the other operations:

  ```julia
  @trait ODEProblemTrait{T, P} begin     # TraitDifferentialEquations/lib/ODECore/src/core.jl:60
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
- **A capability only some members have is a trait of its own,** and code that can use it has a method at both: `PooledColumn{T}` beside `Column{T}` (`forks/Tables/src/ColumnCore.jl:60`).
- **Declared fields and operations, not `getproperty` switches.** A switch on a property's name (`integrator.ps`) stays sugar on the concrete type. Where a property is part of the contract, a supertrait names it:

  ```julia
  @trait IntegratorView{U, T, P} <: (HasProperty{:ps, ParameterView{P}}, HasSystem, ValueProvider{U, P}, IndexProvider{Symbol}) begin
      @const u::U                        # TraitDifferentialEquations/lib/ODECore/src/core.jl:102
      ...
  ```
- **How each type joins:**
  - by its own methods, in a block or after them;
  - by forwarding to a field that holds the data: `@implement Positions Live{Matrix{Float64}} by val` (`TraitMakie/src/TraitMakie.jl:232`);
  - as a family, or as an abstract type: `@implement Positions AbstractVector{P} where {P <: AbstractVector{<:Real}}` (`TraitMakie/src/PlotCore.jl:51`).
- **Extension is by membership, never by overloading the entry.** The owner writes the entry (`solve`, `DataFrame(x)`) once. A package that adds a member declares the membership, in an extension that names its triggers ([§12.1](../reference/traits.md#121-who-may-declare-a-membership)):

  ```julia
  @implement PooledColumn{T} PooledArray{T, R, 1, RA} where {T, R, RA}   # forks/Tables/ext/TablesPooledArraysExt.jl:11
  ```
- **Concreteness is chosen when the trait is published** ([§14](../reference/traits.md#14-concreteness-and-fully-typed-mode)): added later, it refuses members that joined.
- **Names:** an operation is a function of the trait's module, and a common name clashes on `using`. The forks name Tables' operations `tablenames`, `tablecolumn` and `tablerows`, not `nrow`, which DataAPI exports. A trait's name must not collide with an exported alias.

### 0.3 The order: seams first, a function at a time

- **Start where user types enter.** A function users pass their own types to is the first to take a trait.
- **One function at a time.** At each argument a closed type ranks before a trait ([traits §6.2](../reference/traits.md#62-specificity)). So upstream's methods on its own types and the port's methods at traits stand side by side, and a later membership never takes a call from a method on the type's own supertypes.
- **The kernels in a trait module with every option on.** A kernel reads a value only through the trait's operations. Where it needs Base's or a library's code over many values, it gathers them into a plain `Vector{T}` first: that code is compiled per element type and shared by every member (DataFrames' `describe`; `forks/DataFrames/src/other/kernels.jl`, the module's comment).
- **A constructor from a trait goes through a named method at the trait.** `DataFrame(x)` stays plain and calls `fromsource(t::TableSource, copycols)`.
- **Keyword APIs:** the plain layer takes the keywords and builds a concrete options struct; the method at the trait takes it positionally.
- **Extensions add memberships, and plain methods for their triggers' types only.**
- **A specialization belongs at a subtrait or in an operation,** where a boxed member reaches it, not at a member's own type ([traits §7.10](../reference/traits.md#710-costs-and-choosing)).

### 0.4 Where to erase, where to compile per type

A member is passed as itself, in a box or in a wrapper. The choice is in the value's type. It changes speed, never results ([traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)).

- **Per position, not per problem.** A library's specialization levels become one choice per position: the stored function, the callbacks, the model. The trait's default, a box made at the library's door, and the caller's wrapper decide ([§7.5](../reference/traits.md#75-what-decides)).
- **A new user type should not compile the library again.** Where user types enter and a large library stands behind, the trait erases by default, as NetworkDynamics' component models do:

  ```julia
  @trait ComponentDynamics begin          # ndport/pkgs/NetworkDynamics-unified/src/component_dynamics.jl:7
      @default_dynamic
      hasf(m::ComponentDynamics)::Bool
      ...
  ```
  `Callable` erases by default too.
- **Storage keeps the form it is given** ([§8](../reference/traits.md#8-storage)). A method of a trait that erases by default receives a box, and stores it as it is:

  ```julia
  _kept_model(::Type{VertexModel}, x::VertexDynamics) = x   # …/NetworkDynamics-unified/src/network_structure.jl:229
  ```
  The network's type then names none of the user's functions, and new equations compile no code over the network.
- **A loop over values known only by their trait that wants each member's own code hands the value over as `compiled_for(x)`:** a kernel over a column's cells, `summarize(compiled_for(c), name)`. A plain call there is compiled per type in a session only, and once at the trait in a trimmed build.
- **Open the hot loop with the wrapper.** `compiled_for` of a box is the wrapper of its object, so the kernel is compiled per model:

  ```julia
  _run_batch!(dispatchT(batch), compiled_for(batch.model), batches, k, args)              # …/coreloop.jl:147
  @inline _run_batch!(::Type{VertexModel}, m::VertexDynamics, batches, k, args) = run_vertex_batch!(m, batches, k, args)   # :154
  ```
  The call dispatches once on the wrapper's type; the batch's work runs in code compiled for the model.
- **A stored user function:** a constructor with a `Callable` argument at the declared signature, whose variables come from the other arguments:

  ```julia
  @unbounded function ODEProblem(f::Callable{RHSSig{P,T},Nothing}, u0::AbstractVector{T}, tspan, p::P; callback = nothing) where {T,P}     # …/ODECore/src/frontend.jl:68
  ```
  A plain function arrives boxed, so the solver is compiled once per state and parameter type. `ODEProblem(compiled_for(f), …)` passes the wrapper, and the solver is compiled for the function. The constructor is `@unbounded`: an adapter, it stores its argument in the form given.
- **A record made before a signature is known keeps each value in the form given:** `ODEFunction(f; jac = compiled_for(j))` holds a plain `f` and a wrapped `j` ([§8.2](../reference/traits.md#82-a-struct-parameter-bounded-by-a-trait)).
- **Keep the user's types at the surface.** A user's type that only the user's own functions read never reaches the core. The ODE library's problem keeps the right-hand side partially evaluated on the parameters, `(du, u, t)`, so the solver is compiled per state type whatever the parameters.
- **Hand a callback the integrator in a box:** `affect!(cb::Callback{U, T, P}, integ::Dynamic{IntegratorView{U, T, P}})::Nothing` (`…/ODECore/src/core.jl:126`). A new callback compiles its own function, not the solver.
- **Mixed collections:** a field or element typed by the trait, `columns::Vector{Column}` (`forks/DataFrames/src/dataframe/dataframe.jl:181`). Each item is stored in the form given. An operation on it calls the member's method directly for the trait's first four members, and through a table beyond them ([§7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)).
- **A call gives the same code at the prompt and in compiled code:** the value's type decides ([§7.5](../reference/traits.md#75-what-decides)). To time the code compiled per type of an erasing library, pass `compiled_for(x)`.
- **Neither form is the object.** A method that asks what only the object can answer (its type, a function outside the contract) asks it of `unwrap(t)`, or before the value is boxed ([§7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)).

**A value of a plain abstract type, which plain code specializes on.** A stream is the common case: `show(io, x)` hands `io` to code compiled per stream type, and at a REPL the stream is a type no workload at an `IOBuffer` sees ([traits §9b](../reference/traits.md#9b-streams-io)).
- **A display needs nothing from the port.** The REPL's display and Base's `TextDisplay` erase the stream themselves: `show` is called with `IOContext{IO}`, so a package's `show` methods stay plain code and are compiled once for every stream. The workload displays once at `IOContext{IO}(IOBuffer())`, by the MIME entry the REPL takes: `show(IOContext{IO}(IOBuffer()), MIME"text/plain"(), x)`.
- **Elsewhere, erase at the entry where large code serves many value types.** The rule is §7.10's: erase large code with many members behind it; compile kernels per type. Outside a display, such an entry declares `@nospecialize(io::IO)` and passes the stream on erased:

  ```julia
  function Base.show(@nospecialize(io::IO), t::Table)   # traits §9b: one compiled body for every stream
      render(IOContext{IO}(io), t)
  end
  ```
  Below the entry the stream is one type, so the body and everything it calls is compiled once, and a package image's workload at an `IOBuffer` covers the REPL's stream, a file's and a notebook's. Above it, code that knows its stream keeps Julia's code per type.
- **Use the type's own eraser, never a box of the port's.** `Dynamic{X}` is a member of its trait only ([§7.7](../reference/traits.md#77-dynamicx)): it is not an `IO`, so code typed `io::IO` refuses it. Base's `IOContext{IO}` is an `IO`; it forwards the whole stream interface, a terminal's size and colour included, and carries the context's properties (`:limit`, `:compact`). A wrapper written in a port forwards the operations its author thought of and takes the default for the rest: `displaysize` from the environment, not the terminal.
- **Small per-call kernels stay per type.** Formatted output does far more work per operation than the erased stream's dispatch, so it pays little: `show` of a vector 1.09×, `string(…)` 1.20×. A byte or a short string per call pays several times: `write(io, ::UInt8)` 3.60×, `write(io, ::Char)` 4.99×, `print "ab"` 2.63× (E-340). So the erasure sits at the display entry, not at `string(…)`, `sprint` or a `print` of short strings, and a loop that writes a byte per call is reached from code that knows its stream.
- **The workload runs at the erased type, by the path the REPL takes.** A package image holds what its workload ran: a display at `IOContext{IO}(IOBuffer())` is the REPL's display, a text display's and an erased entry's. A workload at a plain `IOBuffer` covers an `IOBuffer` only.
- **What the erasure fixes, and what it leaves.** It removes the port's own code compiled per stream type. What a step still compiles after it is outside the port: the REPL's own path at its stream and Base's code at the cells' types. Credit the right part, as in 0.1.

### 0.5 What to keep plain

- Bookkeeping, macros, printing, options parsing, `getproperty` sugar.
- **Closed library families:** an abstract type hierarchy that one package holds whole is right as it is.
- **Code that is dynamic by design:** an observable's graph, construction-time and metadata code.
- **Rebuilding: plain and thin,** behind a function barrier. What a trait declares is rebuilt with `withfields` and `like` ([§6.5](../reference/traits.md#65-results)); such a method is bounded: at a box it gives a box.
- **Not the front end.** A package's entry functions (`solve`, `read`) belong to a trait module, as the code under them does. A front end compiled plainly is lost to unrelated loads as any plain code is, and it is the first thing each call runs.
- Code that is not type-stable gets slower when compiled by facts. Keep it out of the facts mode where trait code does not call it, or make it fully typed.

### 0.6 How to check

- **Per step:** the workload's digests against upstream's, and a chosen part of upstream's suite: minutes at most. **At milestones:** the full suites. Outside performance work, no benchmarks.
- **Every step keeps results equal.** The kept forms and the mode change speed, never results. Compare with `==`: the same arithmetic gives the same bits. Fused arithmetic (`@muladd`) can differ in the last bit where code is inlined differently.
- **The tests a port adds:**
  - `check_definitions(M)` empty for each trait module;
  - `fully_typed(f, types)` for each hot loop.
- **The tools:**
  - `--trace-compile=stderr --trace-compile-timing`, with a mark per step: what each step compiles;
  - `JULIA_DISPATCH_PROFILE=1`: dynamic calls per callee, lookup path and call site ([compiler §11](../reference/compiler.md#11-changes-useful-without-traits));
  - `fully_typed(main, types)`: what a program reaches, and where a build would refuse it ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).
- **Time a step twice in one session:** the second time separates run time from compiling. Say how many runs.
- **A control at the same load.** On a shared machine a session's time moves 2–3× with the load. A number is compared with plain Julia's form of the same session, run beside it, interleaved, at the same load. Say the load (`/proc/loadavg`) and the number of runs. A number without a control at its load compares with nothing.
- **Measure the step the change was made for.** A fix that moves the whole task can leave that step where it was.
- **A compile at a type the workload never saw** names one of two things: a broad case missing from the workload, or a value type that plain code specializes on, which an entry erases (0.4). `--trace-compile` tells which.
- **An erased entry's own checks:** the digests equal; the display's run time after its first call; the step's compiles traced, since what still compiles names what still carries the stream's type.

---

## Part A. Rules every port confirms

One line per rule; the evidence is in part B, the rule's home in the references. A rule enters this part when a second port confirms it; until then it is one port's experience, in part B.

- **A1. Say what code needs:** fields and containers typed by a trait, results declared ([traits §4](../reference/traits.md#4-declaring-a-trait), [§8](../reference/traits.md#8-storage); B1, B3).
- **A2. Make the hot path fully typed:** a run-time site's result is `Any` ([facts §5](../reference/facts.md#5-run-time-sites); B1).
- **A3. The kernels in a trait module with every option on; the package around them compiled by facts** ([§13](../reference/traits.md#13-scopes-trait-modules); B1).
- **A4. Extensions become memberships,** naming each trigger ([§12.1](../reference/traits.md#121-who-may-declare-a-membership); B1).
- **A5. Keep plain what is plain,** and adopt traits one function at a time ([§6.2](../reference/traits.md#62-specificity); 0.3, 0.5).
- **A6. Upstream's tests decide.** A fork keeps upstream's name and UUID, so upstream's suite runs unchanged (B1).
- **A7. A kernel reads a value through its trait's operations; heavy library code runs over gathered values** (B1).
- **A8. Store a trait argument in the form it arrives in; ask the object's own questions of `unwrap(t)`** ([§8](../reference/traits.md#8-storage), [§7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper); B2, B4).
- **A9. Erase by default where user types enter and a large library stands behind; open the hot loop with the wrapper** ([§7.5](../reference/traits.md#75-what-decides), [§7.10](../reference/traits.md#710-costs-and-choosing); B2, B4).
- **A10. Erase a value plain code specializes on at the entry where large code serves many value types; kernels stay per type** ([§7.10](../reference/traits.md#710-costs-and-choosing), [§9b](../reference/traits.md#9b-streams-io); 0.4, B1).
- **A11. A plain abstract type's value is erased by that type's own eraser,** `IOContext{IO}` for a stream, never by a box of the port's ([§9b](../reference/traits.md#9b-streams-io), [§7.7](../reference/traits.md#77-dynamicx); 0.4, B1).

---

## Part B. What each port teaches

### B1. Tables, DataFrames, CSV

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 (`forks`). Traits: `Column{T}`, `PooledColumn{T}`, `TableSource` in Tables' `ColumnCore`; `CSVSource`, `CSVColumn{T} <: Column{T}`, `TextColumn{T} <: Column{T}` in CSV's `ColumnParsers`.

**The architecture's principle: compile per cell type, not per column type.** The trait's parameter is the cell type. Layouts are a closed set, so they stay types. A capability is an operation with a default, or a trait of its own.

1. **The package compiled by facts, the kernels bounded.** DataFrames and CSV are trait modules with `bounded` and `no_pirates` off; `ColumnKernels` and `ColumnParsers` have every option on (0.1).
2. **A kernel reads through the operations,** and heavy code runs over gathered cells: `describe` gathers into `emptycells(c, n)::Vector{T}` and runs Statistics there, compiled once per `T` (A7).
3. **A capability is a trait of its own:** `PooledColumn` beside `Column`, joined by PooledArrays' and CategoricalArrays' vectors in Tables' extensions (A4).
4. **A type passed as a value:** `stringtype = String15` passes a type; the reader makes `S[]` and calls `TextColumn`'s operations on it, and CSV's InlineStrings extension declares memberships, with helper functions of its own, and adds no method to CSV's functions (`forks/CSV/ext/CSVInlineStringsExt.jl:87`).
5. **A function applied per row is unbounded on purpose** where it asks for its result type: `@unbounded function byrow(f::Callable{Tuple{T}}, c::Column{T}) where {T}` computes `Base.promote_op(f, T)`, as `map` does (`forks/Tables/src/ColumnCore.jl:105`; [traits §9](../reference/traits.md#9-functions-callable)).
6. **Mixed columns in one vector:** `DataFrame`'s `columns::Vector{Column}` holds each vector itself; the kernels over it (`joinkeys`, `_group_rows!`) take `Vector{Column}`.
7. **Upstream's tests decide** (A6). The forks' session gives upstream's digests at 26 steps. Tables' and CSV's upstream suites pass. DataFrames' has four errors: `@inferred` tests that see `Any` through run-time sites in facts code ([open issue 157](../open-issues.md#2-design); E-373).
8. **A stream's type, which plain code specializes on:** DataFrames' `show(io, df)` hands the stream to PrettyTables, plain code compiled per stream type, and at a REPL the stream is `IOContext{REPL.LimitIO{TTYTerminal}}`, which no workload at an `IOBuffer` sees. The REPL's display erases the stream ([traits §9b](../reference/traits.md#9b-streams-io)): DataFrames' code stays as upstream's, and its workload displays once at `IOContext{IO}(IOBuffer())` (0.4).
9. **The first step gives most of the protection.** Upstream compiled by facts as it is loses 14 of 3,490 instances to nine unrelated loads; the forks lose 48 of 4,799, their entry functions, through plain functions of Base (E-392; GT-8).

### B2. Differential equations

TraitDifferentialEquations (`TraitDifferentialEquations`): a solver core (`ODECore`), Rosenbrock and implicit methods, nonlinear solvers, and SciML's front end. Traits: `ODEProblemTrait{T, P}`, `IntegratorView{U, T, P}`, `Callback{U, T, P}`, `EventCallback{U, T, P}`, `StepView{U, T}`, and SymbolicIndexingInterface's concepts in `TraitIndexing`.

**The architecture's principle: the model is the trait, the problem is a record.** A library's inputs vary at three rates: per ecosystem, per model, per call. Compiled code is keyed on the slowest that the hot code needs.

**The route, in six moves,** each leaving a library that runs:
0. compiled by facts as it is;
1. the right-hand side at a declared signature, the problem as a trait;
2. callbacks and the integrator's view as traits, the callbacks out of the integrator's type;
3. the algorithms as an open set that each solver package joins, the front end's body in its owner;
4. symbolic access as traits, the `getproperty` sugar plain;
5. the solution as a trajectory.

1. **The problem's function enters at a declared signature,** in the form given (0.4): compiled once per state and parameter type for a plain function, per function under `compiled_for`.
2. **The parameters stay at the surface:** the problem keeps the right-hand side partially evaluated on them.
3. **Callbacks see the integrator as `Dynamic{IntegratorView{…}}`:** a new callback compiles its own function only.
4. **Properties of the contract are supertraits:** `HasProperty{:ps, ParameterView{P}}` (0.2).
5. **A record that holds a function before its signature is known** (`ODEFunction`, a callback's functions) keeps each value in the form given; the constructor that knows the signature boxes a plain one.
6. **A split package's internal interface is `public` in the core:** the solver packages add methods of the integrator's step interface ([open issue 212](../open-issues.md#2-design)).
7. **A list of user values whose trait instance needs types the user has not given yet** (callbacks before the problem's types) is entered where those types are known, into storage typed by the trait. A list the caller gives keeps its own type (a tuple), never a `Vector{Any}`.
8. Measured: at the prompt a new closure costs 59 ms and a new parameter struct 223 ms, and neither ends compiled code (E-379).

### B3. Plotting and the report

TraitMakie (`TraitMakie`) and TraitReport (`TraitReport`). Traits: `Positions`, `Sample`, `ColorSpec`, `Colormap`, `MarkerShape`, `Scale`, `Plot` in `PlotCore`; `Table`, `Job` in `ReportCore`.

**The architecture's principle: marks are a closed set, recipes an open one.** The primitives the backend draws are types; what users add are members of traits.

1. **The plain layer converts, the trait code draws:** `x, y` become the n × 2 `Matrix{Float64}` that `Positions` serves (`TraitMakie/src/PlotCore.jl:38`).
2. **A wrapper type joins by forwarding:** `Live{Matrix{Float64}}` forwards `Positions` to its field `val`, so it shares the code compiled for the field's type.
3. **Families over Base's types:** every vector of real vectors is a `Positions` (`PlotCore.jl:51`), every `Vector` of reals a `Sample`.
4. Measured: the report's task (CSV → table → summary → histogram PNG) in a fresh process takes 0.78–0.80 s in its trait form, against Python's 0.63–0.65 s (E-389, E-289; [results](results.md)).

### B4. Networks of dynamical systems: NetworkDynamics

NetworkDynamics (`ndport/pkgs/NetworkDynamics-unified`), with Graphs' and GraphMakie's ports. Traits: `ComponentDynamics`, `VertexDynamics <: ComponentDynamics`, `EdgeDynamics <: ComponentDynamics`.

1. **The one change that pays is in the library on top, not in the solver.** The user's component functions reached the network's type, and through it the problem, the integrator, the solution and every symbolic getter. With the model held in a box, the network's type is the same for every set of equations.
2. **The components' traits erase by default,** and a batch stores its model as it arrives, a box (0.4).
3. **The kernel opens the model with the wrapper,** once per batch (0.4).
4. **An informal interface becomes a trait over its existing functions:** Graphs' `AbstractGraph`, one family line. A function that returns an open iterator needs a second function with a declared result.
5. Measured: its suite passes and the workload's digests are unchanged ([the state](../state.md)). New equations against upstream's are not measured on this implementation ([the evidence](../design/evidence.md), "Not shown").

---

## How this document is kept

- Each example names the file and line it is quoted from; that package's suite runs it. When the design changes, the ports follow it, and the examples here follow the ports.
- A port adds to part B what it learns, and to part A a rule that a second port confirms.
- A rule a port finds weak becomes an [open issue](../open-issues.md), with the case, the rule and a proposal.
