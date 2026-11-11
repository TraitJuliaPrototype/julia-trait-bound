# Traits for Julia

This page is for Julia users and package authors. It covers:
- the problems the design addresses;
- what you write, in brief;
- one worked example;
- the parts of the language, one by one;
- what you get;
- what it costs, and what is not done yet.

It assumes you know Julia. It does not assume you have read the design. The precise rules are in the [references](../reference/README.md), written for Julia's core developers. The terms, with their origins in other languages, are in [`../glossary.md`](../glossary.md). The measurements are in [`results.md`](results.md). Porting an existing package is in [`porting.md`](porting.md).

**Status, 2026-11-11.** This is a research prototype:
- a patched build of Julia 1.13 (the unified build, `julia-unified/` in this workspace), in which traits are part of Julia's types;
- a package, TraitWorld (branch `unified`), with the macros and the checks;
- demonstrators and ports: an ODE solver and a port of SciML's front end, a plotting library, a data report with its own CSV reader and table library, ports of CSV.jl, DataFrames.jl and NetworkDynamics.jl.

Nothing is registered. Nothing is upstream. The worked example below runs as `experiments/docs-examples/intro.jl`.

What the project sets out to show, and how far each claim is supported today, is in [the goals](../goals.md).

## The problems

### 1. Your code recompiles when you load another package

- Julia compiles a function for the argument types it is called with, and keeps the result.
- Inside that function, some calls have argument types Julia cannot know in advance. Examples: an element of a `Vector{Any}`, or a field with an abstract type.
- For such a call, Julia looks at the methods that exist now and builds on what it finds. It may infer a result type from the only method that matches today.
- Then you load a package that adds a method for its own type. Julia's guess may no longer hold. Julia discards the compiled code and compiles it again at the next call. This is called *invalidation*.
- Nobody has to do anything wrong for this to happen. Defining `Base.show(io::IO, x::MyType)` for your own type is good practice, and it can invalidate code in other packages.
- Package images (the precompiled code of a package) do not help. Their code is discarded the same way.

Measured on plain Julia: `using CairoMakie` on Julia 1.12 discards compiled code at 769 call signatures.

A package's own extension can discard its compiled code too. With DataFrames loaded, CSV.jl's first read takes 2.5 s instead of 0.19 s:
- DataFrames loads InlineStrings;
- that activates CSV.jl's extension for InlineStrings;
- the extension adds methods to CSV.jl's internal functions.

With traits an extension declares a membership instead, and a membership discards no compiled code (TraitCSV's `String15`).

### 2. A vector of mixed types is slow, or forces you to over-parametrize

Say you keep shapes of several types in one vector. Plain Julia offers two choices.
- **An abstract element type,** `Vector{AbstractShape}`. There is one copy of the code. But each call on an element is a dynamic dispatch at run time. Julia is faster only when it happens to see few matching methods, and that changes when someone adds a shape type.
- **A type parameter for each part,** such as `struct Scene{T <: Tuple}`. The calls are fast. But code is compiled for every combination of types, and the types grow with every layer.

A real case: in SciML, a callback's type is part of the integrator's type. So a new callback closure compiles the solver again, 0.84–0.96 s, although the solver step never reads the callback.

### 3. Errors surface deep inside a library, with huge types

- An abstract type names what you intend. Nothing checks it.
- If your type lacks a method the library needs, you get a `MethodError` deep in the library's stack, at the first call.
- Concrete types are printed in full in error messages. A SciML integrator's type runs to 3,553 characters.

### 4. You cannot say "a function from `Float64` to `Float64`"

- A function's type says which function it is, not what it takes and returns.
- An argument `f::Function` accepts any function. A mistake shows at the first call, deep inside.
- An argument without a type annotation compiles the library again for every new function, closures included.

## What you write

TraitWorld provides a few macros. Everything else is Julia: a trait is an abstract type.

- **`@trait`** declares a trait: what a library needs from a value, as operations with argument and result types.
- **`@implement`** declares that a type is a member of a trait. The declaration is checked where it is written.
- **A method whose argument is typed by a trait** accepts a value of every member type.
- **`@trait_module`** marks a library's module. Its methods at traits are checked when they are defined, and its code is compiled so that loading other packages does not discard it.
- **`Callable{A, S}`** types a function argument by its signature. **A field or element typed by a trait,** with `keep`, holds values of mixed member types.

The worked example uses each of these. [The parts, one by one](#the-parts-one-by-one) then gives each with its rules.

## A worked example: a library and its user

### The library

The library is a trait module. Paste it into a REPL running the unified build with TraitWorld installed, or run `experiments/docs-examples/intro.jl`.

```julia
using TraitWorld

module Columns
using TraitWorld
@trait_module
export ColTable, ncols, col, colmean, meandiff, colmap, Shelf, shelf, add!, means

@trait ColTable begin                                  # what the library needs from a table
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end

@implement ColTable Vector{Vector{Float64}} begin      # the library's own membership
    ncols(t) = length(t)
    col(t, i) = t[i]
end

colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
meandiff(a::ColTable, b::ColTable, i::Int) = colmean(a, i) - colmean(b, i)

# a function argument with a declared signature, Float64 -> Float64
function colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int)
    c = col(t, i)
    out = similar(c)
    for k in eachindex(c)
        out[k] = f(c[k])
    end
    return out
end

# tables of any member types, kept together
struct Shelf
    tables::Vector{ColTable}
end
shelf() = Shelf(ColTable[])
add!(s::Shelf, t::ColTable) = (push!(s.tables, keep(t)); s)
function means(s::Shelf, i::Int)
    out = Float64[]
    for t in s.tables
        push!(out, colmean(t, i))
    end
    return out
end
end

using .Columns
```

### Its user, in ordinary Julia

```julia
import .Columns: ncols, col

# 1. A type that holds a table: it forwards the trait to its field.
struct Measurements
    label::String
    data::Vector{Vector{Float64}}
end
@implement ColTable Measurements by data   # `label` is invisible to Columns

# 2. A type that serves the operations itself.
struct Ramp                           # column i is base .* i, never stored
    base::Vector{Float64}
    n::Int
end
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp              # checked now: both operations exist, with the declared results

m = Measurements("run 1", [[1.0, 2.0], [3.0, 5.0]])
r = Ramp([1.0, 2.0], 2)

Measurements <: ColTable   # true
colmean(m, 1)              # 1.5
colmean(r, 2)              # 3.0
meandiff(m, r, 1)          # 0.0
colmap(x -> 2x, m, 2)      # [6.0, 10.0]

s = shelf()
add!(s, m); add!(s, r)     # two types in one collection
means(s, 1)                # [1.5, 1.5]
```

### What happens

Each trait argument at each call is `Compiled` or `Dynamic`. `Compiled` runs the code compiled for the value's type. `Dynamic` runs code compiled once, for the trait, in which each operation on the value dispatches when it runs. [`Compiled` or `Dynamic`](#a-method-at-a-trait) below says what decides.

- **At the prompt** the values are `Dynamic`: the prompt knows no types, so each method runs its code compiled once, at the trait, and each operation dispatches when it runs. The results are the same as below.
  - So a timing at the prompt, `@time colmean(m, 1)`, times the code compiled once. To time the code compiled for `Measurements`, call from a function, or cast: `colmean(compiled_for(m), 1)`.
  - `keep` at the prompt stores a `Dynamic{ColTable}` that holds the value; from a function that knows the type it stores the value itself. Code that reads the shelf through `ColTable` sees no difference. Code that asks more of an item (its type, another trait) does ([open issue 175](../open-issues.md#2-design)).
- **In a function that knows the types** (a script's functions, a package, or `colmean(compiled_for(m), 1)` at the prompt) the values are `Compiled`: `colmean` is compiled for `Measurements`, and again for `Ramp`, as plain Julia compiles a method per type. `meandiff(m, r, 1)` is compiled for this pair of types.
- **The shelf** holds a `Measurements` and a `Ramp` in one vector typed by the trait. `means` is compiled once; the call `colmean(t, i)` on an item tests the item's type against `ColTable`'s members and calls each one's code directly.
- **`colmap`** is compiled once for the signature `Float64 -> Float64`, not once per closure.

### The mistakes, and where they are caught

**A user's type that does not fit.** The trait declares that `col` returns a `Vector{Float64}`:

```julia
struct Counts; n::Int; end
ncols(c::Counts) = c.n
col(c::Counts, i::Int) = fill(i, 3)       # a Vector{Int}
@implement ColTable Counts
```

The `@implement` line raises an `ImplementError`, which names the operation, the result it infers and the declared one:

```
ImplementError: Counts cannot be a member of ColTable
  - col's method at Counts infers its result as Vector{Int64}, outside the declared Vector{Float64}
```

The error comes at the declaration, before any `Counts` value is passed to the library, and `Counts` is no member.

**A function with the wrong result type:**

```julia
colmap(x -> 1, m, 1)      # TypeError: in typeassert, expected Float64, got a value of type Int64
```

**A library author's mistake.** Suppose Columns contained this line:

```julia
colsum(t::ColTable) = sum(t)      # meant: sum(col(t, 1))
```

`ColTable` does not declare `sum`, so the method is open at `t`. In a trait module that is a `TraitUseError` where the method is defined. It names the use outside the contract and its line, before any user type exists:

```
TraitUseError: colsum is declared bounded, and is open:
  sum(ColTable) at line 112 is not in the contract of ColTable
```

**A value of no member type.** `colmean(42, 1)` raises a `MethodError`, as plain Julia would.

## The parts, one by one

What the example used, each with its rules.

### A trait

A trait says what a library needs from a value: operations with declared argument and result types.

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end
```

A trait can also declare stored fields with types (writable unless marked `@const`), defaults written in terms of the other operations, and type parameters ([traits §4](../reference/traits.md#4-declaring-a-trait)):

```julia
@trait Integrator{U, P} begin
    u::U                 # the state
    @const p::P          # the parameters, read-only
    t::Float64
end
```

A trait is an abstract type, with two additions:
- **A type joins it after its own definition,** by a declared *membership*. The type's definition need not name the trait; the package that owns the type, or the one that owns the trait, declares the membership later.
- **Joining is checked.** The membership must provide the trait's operations and fields, with their types.

Everything else is as for an abstract type:
- `T <: ColTable` asks whether `T` is a member; `x isa ColTable` asks it of a value.
- A type can be a member of several traits.
- `@trait B <: A` makes `A` a supertrait: every member of `B` is a member of `A`.
- In dispatch, a type's own supertypes rank before a trait, so a library can adopt traits one function at a time ([traits §6.2](../reference/traits.md#62-specificity)).

### A membership: your type joins a trait

You declare that a type is a member with `@implement`. TraitWorld checks the declaration when you write it: every operation must exist, with the declared result type.

There are two ways to serve the operations:
- **Your type has a field that is already a member.** `@implement ColTable Measurements by data` forwards the trait to the field `data`. Forwarding is always written with `by`.
- **Your type serves the operations itself.** Define the methods, then declare the membership.

Who may declare a membership: the package that owns the trait, or the package that owns the type ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)).

### A method at a trait

A method whose argument is typed by a trait is an ordinary method:

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

- It accepts a value of any member type. The value is passed as itself: inside, `t` is your `Measurements`.
- A method that reaches `t` only through the trait (its operations and fields, or passing it to another argument typed by the trait) is *fully bounded*. One that does anything else with `t` is *open*. Library code in a trait module may only be fully bounded, unless a method is marked `@open` ([traits §7.3](../reference/traits.md#73-fully-bounded-methods)).
- On ordinary values, such as the column `col` returns, it calls any Julia code.

**`Compiled` or `Dynamic`.** Each trait argument at each call has one of two *attributes*. The results are the same; only the speed differs ([traits §7.4](../reference/traits.md#74-the-attribute-compiled-and-dynamic)).
- `Compiled`: the code compiled for the value's type runs, as plain Julia compiles per type.
- `Dynamic`: code compiled once, at the trait, runs. Each operation on the value dispatches when it runs, and its result has the declared type.

What decides, strongest first ([traits §7.5](../reference/traits.md#75-what-decides)):
1. a cast at the call: `colmean(compiled_for(m), 1)` or `colmean(with_dynamic(m), 1)`;
2. an attribute the value carries: a `Dynamic{ColTable}` is `Dynamic`, and an argument passed on keeps its attribute;
3. the library's choice for the argument (`@nospecialize t::X` gives `Dynamic`, `@specialize t::X` gives `Compiled`) or for its module (the option `dynamic`);
4. the trait's default, `@default_dynamic` or `@default_compiled` in its body;
5. otherwise, for a method of a trait module, what the caller knows: a caller that knows the value's type passes `Compiled`; the prompt, or an item of a `Vector{Any}`, passes `Dynamic`. For a method outside a trait module: `Compiled`, as Julia compiles a method at an abstract type.

### A trait module

Library code that uses traits declares `@trait_module` in its module, before the module's first method ([traits §13](../reference/traits.md#13-scopes-trait-modules)):

```julia
module Columns
using TraitWorld
@trait_module
...
end
```

A trait module:
- is compiled in the patched compiler's facts mode ([What you get](#what-you-get), point 1);
- refuses an open method at a trait (`TraitUseError`);
- refuses piracy of its own (below).

Its statements are Julia's; nothing is rewritten. Code outside trait modules calls its methods as it calls any function, and a trait module can call any Julia code: Base, CSV.jl, Cairo, ForwardDiff.

### `Dynamic{X}` and `keep`

For a mixed collection, or a field whose value can change type, type the field or element by the trait: `tables::Vector{ColTable}` holds the members' own values.
- `Dynamic{X}(x)` holds a member of `X` and is itself a member of `X`. Code that receives it runs the code compiled once, at the trait. `unwrap(d)` gives the object back ([traits §7.7](../reference/traits.md#77-dynamicx)).
- `keep(x)` stores a trait argument with the attribute it has in the current code: as itself where it is `Compiled`, as a `Dynamic{X}` where it is `Dynamic` ([traits §7.8](../reference/traits.md#78-keeping-an-argument-with-its-attribute)).
- An operation on a value the code knows only by its trait tests the value's type against the trait's members, up to four, and calls each one's method directly; any other member is called through a table. Its result has the declared type ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)).

### `Callable`: a function with a declared signature

```julia
function colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int)
    c = col(t, i)
    out = similar(c)
    for k in eachindex(c)
        out[k] = f(c[k])
    end
    return out
end
```

- `f` may be any function or closure with a method for a `Float64` argument. The library calls it as `f(x)`.
- The library calls `f` itself. Passing it on to Base's `map` is a use outside `Callable`'s contract, which a trait module refuses; how a library passes a function on is [open issue 165](../open-issues.md#2-design).
- Every call is checked: a result that is not a `Float64` raises a `TypeError`.
- `Callable`'s default attribute is `Dynamic`: the library is compiled once for the signature, not once per function. A function Julia defines, or one of the library's own package, is `Compiled` ([traits §9](../reference/traits.md#9-functions-callable)).
- A caller casts with `compiled_for(f)` to have the library compiled for this function, at plain Julia's speed, with the signature still checked. An ODE right-hand side wants this.

### Piracy and strict mode

- *Type piracy* is defining a method of a function you do not own, for types you do not own. An example from the project's tests: a package defines `+` for ForwardDiff's `Dual` numbers. It owns neither `+` (Base's) nor `Dual` (ForwardDiff's).
- By default, a pirate's method is followed, as in plain Julia. Code that the pirate changes is compiled again, once.
- **Strict mode** refuses another package's method, on a function and for types that package does not own, when the method would change code compiled by facts ([traits §12.3](../reference/traits.md#123-strict-mode)). It is off by default. Turn it on with `TraitWorld.strict!(true)` or `JULIA_TW_STRICT=1`.

## What you get

The numbers on this page are measured on the unified build, on a shared host. [`results.md`](results.md) gives each with its build, its baseline and its experiment, and [the evidence](../design/evidence.md) has the full tables.

### 1. Compiled code that loading other packages does not discard

The patched compiler compiles trait modules in its *facts mode* ([the rationale §2](../design.md#2-the-argument-in-four-steps)):
- A call whose argument types are all known is compiled as plain Julia compiles it.
- A call whose argument types are not all known is not guessed at. It is dispatched when it runs, as Julia's dynamic dispatch does.
- So compiled code depends only on calls whose types are all known. Only two kinds of change can alter one of those:
  - the package that owns the function, or one of the types, changes it: an edit, an upgrade, one of its package extensions;
  - a pirate whose method wins at that call.
- So an unrelated package's load does not discard the code, in any load order, with one limit: code compiled this way still builds on the plain functions it calls, Base's among them. When a load invalidates one of those, its callers are compiled again.
- A new type that joins a trait discards no compiled code. An existing type that joins later discards only the code that relied on its not being a member; only the trait's owner or the type's owner declares a membership, and anyone else's is piracy.
- By default a pirate is followed, and the code it changes is compiled again. With strict mode on, the pirate is refused. Then compiled code is discarded only when code it depends on changes.
- A few exceptions remain in both settings, listed in [the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated).

Measured, with nine unrelated packages loaded after the work ([`results.md`](results.md)):
- CSV.jl and DataFrames as they are, compiled in the facts mode by one added line per module: 0.4 % of their compiled code is discarded, against 9.2 % in plain Julia. The same work afterwards takes 0.48–0.66 s against 4.2 s.
- Small libraries written with traits (a reader, a table, a plot): none of their compiled code is discarded, and the work afterwards takes 30 ms, as before the loads. The same libraries written without traits take 0.48 s.
- The ports of CSV.jl and DataFrames lose 1.0 %, and it is their entry functions, through functions of Base: the limit above.

**This protection comes from the compiler's facts mode, and it works for any code.** What traits add:
- **The mode costs type-stable trait code nothing.** A method at a trait is compiled for the member's type. If its code is type-stable, all its calls have known types, and those are compiled as plain Julia compiles them. Plain code that is not type-stable gets slower in this mode (see "What it costs").
- **The code is compiled once and cached.** It lives in the package image of the package that compiled it, and stays valid there.

### 2. Errors at the line you wrote, before any value exists

- A trait module's methods are checked when they are defined. A use the trait does not allow is reported at its line, before any user type exists.
- A user's membership is checked at `@implement`, before any value reaches the library.
- A `Callable` checks its result at every call.
- Not everything is caught early: the check at `@implement` infers the member's methods; it cannot prove that every conversion inside them succeeds.

### 3. Mixed collections and functions without recompiling

- A vector typed by a trait holds members of any type; the code over it is compiled once, and each operation on an item calls the member's method directly for up to four member types.
- A type that joins later works at once, through the table, and discards no compiled code.
- `Callable{Tuple{Float64}, Float64}` says "a function from `Float64` to `Float64`", and checks it. A new closure compiles nothing in the library.

### 4. A new type, a new closure, a new member: little to compile

- A package that adds a member to a library's trait, with the library's work on it: its package image holds 0.29× the compiled code of the same package written without traits. The library's generic code is not compiled again for the member.
- Twenty packages that each add a member to one trait discard none of each other's code, in any load order.
- A new right-hand side for the ODE solver: 0.05 s for the second model. The solver is not compiled again.

## What it costs

### No faster steady state

- The claim is no regression: trait code whose types are known runs as plain Julia's does, and a caller opts into code compiled per type with `compiled_for(x)`. It is measured on the earlier build, not yet on this one ([`results.md`](results.md#what-it-costs)).
- The project does not claim that trait code runs faster than well-written plain Julia.

### First-run sessions are still slower than Python's

Whole sessions in a fresh process, start to exit ([`results.md`](results.md)):
- reading a CSV file into a `DataFrame`, summarizing it and plotting a histogram: 1.8 s, against 0.63–0.65 s for Python with pandas and matplotlib;
- the same report with the project's own small reader and table library: 0.8 s;
- an ODE solve with a plot, then a second model: 2.0 s, against 1.4 s for the same task in Python.

Most of the time is Julia's start and the loading of package images.

### It needs a patched Julia

- TraitWorld runs only on the unified build of Julia 1.13 (`julia-unified/` in this workspace). It does not run on stock Julia.
- The changes are meant as proposals to Julia. None is upstream yet.

### Code that is not type-stable can become slower

- In the facts mode, Julia does not guess at calls whose types are unknown. It dispatches them at run time, and their results are typed `Any`. Type-stable code over concrete types is unaffected.
- This applies to trait modules. In the test bed, which compiles all code in this mode, Julia's benchmark suite (4,342 benchmarks) is 3.7 % slower on the geometric mean; the worst cases, on containers of `Any`, are up to 28× slower (measured on the julia-1.13 build of 2026-10-21).
- **How traits recover it.** Where values are mixed on purpose, declare it: a field or element typed by the trait, `Dynamic{X}`, or `Callable`. Their operations have declared result types, so the code after them stays typed.
- The rule the project follows: a slowdown is acceptable when rewriting the code with traits recovers it.
- To find such code, `fully_typed(f, (ArgType1, ArgType2))` reports the calls in `f`, and in what it calls, whose argument types are not known; `@warn_not_fully_typed` and `@enforce_fully_typed` check it when the code runs ([traits §14](../reference/traits.md#14-concreteness-and-fully-typed-mode)).

### Loading, editing, and code that uses no trait

- **Loading:** a membership is checked when it is declared, and a package's memberships are activated when its image loads. Loading TraitWorld and the packages that use it is most of each session's time above.
- **A member that joins after its caller was compiled** is reached through a table. Each session makes the table's entry on the first call: about 9 ms per operation and member.
- **Editing a method at a trait** runs its check again: 0.4 s per edit, and 2.8 s for the first edit in a session.
- **Code that uses no trait** runs on the same patched Julia, where dispatch and subtyping also look at memberships. Measured on DataFrames without traits: its first run is not slower, and repeated small operations are 8–18 % slower than on stock Julia.
- **Load TraitWorld first.** Loaded after plain code has been compiled, the library's methods on Base's functions (`length`, `iterate`) discard some of that code: 197 compiled instances and 0.25 s in the measured session.

[`results.md`](results.md) has each number with its measurement.

### Not "compiled once for any type"

- A method at a trait is compiled for each member's type that reaches it with `Compiled`, once, in the image of the package that compiled it.
- Code is compiled once for all members where the argument is `Dynamic`, and for `Callable` at its default.

### What is not done yet

- **Ahead-of-time binaries:** a build (`juliac --trim`) has every member of a trait, so it compiles generic code for them, as Rust does. A small program builds and runs; no demonstrator builds as a trimmed binary yet.
- **Threads:** not tested.
- **Revise and redefinition:** changing a membership in a running session needs a restart.
- **Keys:** sharing one compiled copy among members that the trait sees alike (a type that forwards to a field, say) is Optional, not built ([traits §7.2](../reference/traits.md#72-the-key)).
- **Named implementations,** a second way for a type to join a trait, are Planned ([traits §17](../reference/traits.md#17-named-implementations)).
- **Scale:** the ports are the largest compositions tried; [`results.md`](results.md) says which parts of them run.

## Where to go next

- [`traits-by-example.md`](traits-by-example.md): the language, one feature at a time.
- [`results.md`](results.md): what the demonstrators show, with fair baselines.
- [`porting.md`](porting.md): porting an existing package, one function at a time.
- [`../design.md`](../design.md): the argument behind the design; the precise rules are in the [references](../reference/README.md).
