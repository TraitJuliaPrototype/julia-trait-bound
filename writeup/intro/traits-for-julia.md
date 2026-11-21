# Traits for Julia

This page is for Julia users and package authors. It covers:
- the problems the design addresses;
- what you write, in brief;
- one worked example;
- the parts of the language, one by one;
- what you get;
- what it costs, and what is not done yet.

It assumes you know Julia. It does not assume you have read the design. The precise rules are in the [references](../reference/README.md), written for Julia's core developers. The terms, with their origins in other languages, are in [`../glossary.md`](../glossary.md). The measurements are in [`results.md`](results.md). Porting an existing package is in [`porting.md`](porting.md).

**Status.** This is a research prototype:
- Julia 1.13 with the design's changes (`julia-next/` in this workspace), in which traits are part of Julia's types;
- a package, TraitWorld (branch `unified`), with the macros and the checks;
- demonstrators and ports: an ODE solver and a port of SciML's front end, a plotting library, a data report with its own CSV reader and table library, ports of CSV.jl, DataFrames.jl and NetworkDynamics.jl.

Nothing is registered. Nothing is upstream. The worked example below runs as `experiments/docs-examples/intro.jl`.

What the project sets out to show, and how far each claim is supported today, is in [the goals](../goals.md).

## The problems

### 1. Your code recompiles when you load another package

- Julia compiles a function for the argument types it is called with, and keeps the result.
- Inside that function, some calls have argument types Julia cannot know in advance. Examples: an element of a `Vector{Any}`, or a field with an abstract type.
- For such a call, Julia looks at the methods that exist now and builds on what it finds. It may infer a result type from the only method that matches today.
- Then you load a package that adds a method for its own type. Julia's guess may then be wrong. Julia discards the compiled code and compiles it again at the next call. This is called *invalidation*.
- Nobody has to do anything wrong for this to happen. Defining `Base.show(io::IO, x::MyType)` for your own type is good practice, and it can invalidate code in other packages.
- Package images (the precompiled code of a package) do not help. Their code is discarded the same way.

Measured on plain Julia: `using CairoMakie` on Julia 1.12 discards compiled code at 769 call signatures.

A package's own extension can discard its compiled code too. An example with CSV.jl and DataFrames:
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
- **`Callable{A, S}`** types a function argument by its signature. **A field or element typed by a trait** holds values of mixed member types.

The worked example uses each of these. [The parts, one by one](#the-parts-one-by-one) then gives each with its rules.

## A worked example: a library and its user

### The library

The library is a trait module. Paste it into a REPL running Julia with the design's changes and TraitWorld installed, or run `experiments/docs-examples/intro.jl`.

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

# tables of any member types, held together
struct Shelf
    tables::Vector{ColTable}
end
shelf() = Shelf(ColTable[])
add!(s::Shelf, t::ColTable) = (push!(s.tables, t); s)
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

A method is compiled as Julia compiles any method: for the types of the values it is given. The value's type decides, so a call runs the same code at the prompt as in a function or a package.

- **`colmean`** is compiled for `Measurements`, and again for `Ramp`, as plain Julia compiles a method per type. `meandiff(m, r, 1)` is compiled for this pair of types.
- **The shelf** holds a `Measurements` and a `Ramp` in one vector typed by the trait, each as itself. `means` is compiled once; the call `colmean(t, i)` on an item dispatches once on the item's type and runs the code for that type, as Julia's function barrier does.
- **`colmap`** is compiled once for the signature `Float64 -> Float64`, not once per closure: `Callable` *erases by default*, so the closure is passed in a box (below).

A caller who wants other code passes the value in one of two other forms, the box and the wrapper. Each is a value, and a member of the trait. The results are the same; only the speed differs:

```julia
colmean(Dynamic{ColTable}(m), 1)       # 1.5: the box, code compiled once for ColTable
colmean(compiled_for(m), 1)            # 1.5: the wrapper, code compiled for Measurements
colmap(compiled_for(x -> 2x), m, 2)    # [6.0, 10.0]: colmap compiled for this closure
```

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
colmap(x -> 1, m, 1)      # TypeError: in Callable, expected Float64, got a value of type Int64
```

**A library author's mistake.** Suppose Columns contained this line:

```julia
colsum(t::ColTable) = sum(t)      # meant: sum(col(t, 1))
```

`sum` needs `iterate`, which `ColTable` does not declare. TraitWorld reads the method's code for the box `Dynamic{ColTable}`, which stands for every member: there `sum(t)` finds no method, so the method is not bounded. In a trait module that is a `TraitUseError` where the method is defined. It names the call, what it reaches and its line, before any user type exists:

```
TraitUseError: `colsum(t::ColTable)` is declared bounded, and is not bounded: read with `t` in a box, `Dynamic{ColTable}`:
  sum(t) reaches iterate(::Dynamic{ColTable}), which has no method (through sum → mapreduce → mapfoldl → mapfoldl_impl → foldl_impl → _foldl_impl), at line 142
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
- **Your type has a field that is already a member.** `@implement ColTable Measurements by data` forwards the trait to the field `data`. Forwarding is always written with `by`, a convenience of the library: the membership defines your type's method for each operation, which calls it on the field ([traits §5.5](../reference/traits.md#55-forwarding-with-by)).
- **Your type serves the operations itself.** Define the methods, then declare the membership.

Who may declare a membership: the package that owns the trait, or the package that owns the type ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)).

### A method at a trait

A method whose argument is typed by a trait is an ordinary method:

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

- It accepts a value of any member type. The value is passed as itself: inside, `t` is your `Measurements`. At a trait that erases by default (below), `t` is a box or a wrapper instead.
- A method is *bounded* at `t` when its code works for every member that will ever join. TraitWorld reads the method's code for the box `Dynamic{ColTable}`, through which only the trait's operations and fields reach the member. A method is bounded where no call there finds no method or only throws; otherwise it is *unbounded*. Library code in a trait module must be bounded, unless a method is marked `@unbounded` ([traits §7.3](../reference/traits.md#73-bounded-methods)).
- On ordinary values, such as the column `col` returns, it calls any Julia code.

**What it is compiled for.** A method is compiled for the types of the values it is given, as in Julia ([traits §7.1](../reference/traits.md#71-how-an-argument-is-compiled)). A member reaches it in one of three forms. The results are the same; only the speed differs:
- the member itself: code compiled for its type, as plain Julia compiles per type;
- the box `Dynamic{ColTable}(m)`: code compiled once, for the trait. Each operation on the value dispatches when it runs, and its result has the declared type;
- the wrapper `compiled_for(m)`: code compiled for the type of the object it holds.

What decides is the value's type, as in Julia. Nothing beside the call decides, so a call runs the same code at the prompt as in compiled code. The choice is made in three places ([traits §7.5](../reference/traits.md#75-what-decides)):
1. the caller, with a value: `colmean(compiled_for(m), 1)` or `colmean(Dynamic{ColTable}(m), 1)`. Storage keeps the form it is given;
2. the trait, for a plain member: a trait that declares `@default_dynamic` in its body *erases by default*. Its methods take a plain member boxed, and a box or a wrapper as it is. `Callable` erases by default;
3. a library, at its doors: it boxes where it chooses, `solve(m::Model, u0) = _solve(Dynamic{Model}(m), u0)`.

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
- is compiled in the compiler's facts mode ([What you get](#what-you-get), point 1);
- refuses an unbounded method at a trait (`TraitUseError`);
- refuses piracy of its own (below).

Its statements are Julia's; nothing is rewritten. Code outside trait modules calls its methods as it calls any function, and a trait module can call any Julia code: Base, CSV.jl, Cairo, ForwardDiff.

### The box and the wrapper

For a mixed collection, or a field whose value can change type, type the field or element by the trait: `tables::Vector{ColTable}` holds the members' own values. Storage keeps the form it is given ([traits §8](../reference/traits.md#8-storage)).
- `Dynamic{X}(x)`, the box, holds a member of `X` and is itself a member of `X`. Code that receives it runs the code compiled once, for the trait. `unwrap(d)` gives the object back ([traits §7.7](../reference/traits.md#77-dynamicx)). A `Vector{Dynamic{X}}` boxes each member stored in it.
- `compiled_for(x)`, the wrapper, holds `x` with its type. It is a member of every trait `x` is in, and code that receives it is compiled for `x`'s type ([traits §7.6](../reference/traits.md#76-compiled_forx)).
- Neither is the object: `typeof`, `===` and `isa Measurements` answer for the box or the wrapper, and `unwrap` gives the object.
- An operation on a value the code knows only by its trait has the declared result type ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). In a session it tests the value's type against the trait's members, up to four, and calls each one's method directly; any other member is called through a table. In a program built ahead of time it tests against every member the program uses ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).

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

- Every function or closure is a member. The signature is checked where the function is passed: `colmap(uppercase, m, 1)` raises a `MethodError` there, since `uppercase` has no method for a `Float64`.
- `Callable` erases by default: a plain function is passed in a box, so the library is compiled once for the signature, not once per function, Julia's own functions included ([traits §9](../reference/traits.md#9-functions-callable)).
- Every call of the box is checked: a result that is not a `Float64` raises a `TypeError`.
- The library calls `f` as `f(x)`, or passes it on to Base's `map`: that passes the box, and `map` is compiled once for it.
- A caller passes `compiled_for(f)` to have the library compiled for this function, at plain Julia's speed, with the signature checked where it enters. An ODE right-hand side wants this.

### Piracy and strict mode

- *Type piracy* is defining a method of a function you do not own, for types you do not own. An example from the project's tests: a package defines `+` for ForwardDiff's `Dual` numbers. It owns neither `+` (Base's) nor `Dual` (ForwardDiff's).
- **A trait module's internal functions are its own.** A function of a trait module that the module neither exports nor declares `public` is *owner-only*: a method of it from another package is a pirate's, whatever types it names, the other package's own types included. `@owner_only f` declares an exported function so too. To let other packages add methods, the owner exports the function or declares it `public` ([traits §12.2](../reference/traits.md#122-pirates)).
- By default, a pirate's method is followed, as in plain Julia. Code compiled by facts that it changes is compiled again, once, and a warning names the pirate, who defined it and the code it ended. `TraitWorld.report_pirates!(false)` turns the warning off. [Traits by example §16](traits-by-example.md#16-when-something-does-not-fit) shows one.
- A trait module refuses a pirate of its own (`OwnershipError`).
- **Strict mode** refuses a pirate, of either kind, when it would change code compiled by facts ([traits §12.3](../reference/traits.md#123-strict-mode)). It is off by default. Turn it on with `TraitWorld.strict!(true)` or `JULIA_TW_STRICT=1`.

## What you get

The numbers on this page are measured on the implementation, on a shared host. [`results.md`](results.md) gives each with its build, its baseline and its experiment, and [the evidence](../design/evidence.md) has the full tables.

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
- CSV.jl and DataFrames as they are, compiled in the facts mode by one added line per module: 0.4 % of their compiled code is discarded, against 9.0 % in plain Julia. The same work afterwards takes 1.7 s against 5.2 s.
- Small libraries written with traits (a reader, a table, a plot): none of their compiled code is discarded, and nothing is compiled again afterwards. The same libraries written without traits lose 28 compiled instances and take 0.33 s.
- The ports of CSV.jl and DataFrames lose 1.0 %, and it is their entry functions, through functions of Base: the limit above.

**This protection comes from the compiler's facts mode, and it works for any code.** What traits add:
- **The mode costs type-stable trait code nothing.** A method at a trait is compiled for the member's type. If its code is type-stable, all its calls have known types, and those are compiled as plain Julia compiles them. Plain code that is not type-stable gets slower in this mode (see "What it costs").
- **The code is compiled once and cached.** It lives in the package image of the package that compiled it, and stays valid there.

### 2. Errors at the line you wrote, before any value exists

- A trait module's methods are checked when they are defined. A use the trait does not allow is reported at its line, before any user type exists.
- A user's membership is checked at `@implement`, before any value reaches the library.
- A boxed `Callable` checks its result at every call.
- Not everything is caught early: the check at `@implement` infers the member's methods; it cannot prove that every conversion inside them succeeds.

### 3. Mixed collections and functions without recompiling

- A vector typed by a trait holds members of any type; the code over it is compiled once, and each operation on an item calls the member's method directly: in a session for up to four member types, in a program built ahead of time for every member the program uses.
- A type that joins later works at once, through the table, and discards no compiled code.
- `Callable{Tuple{Float64}, Float64}` says "a function from `Float64` to `Float64`", and checks it. A new closure compiles nothing in the library.

### 4. A new type, a new closure, a new member: little to compile

- A package that adds a member to a library's trait, with the library's work on it: its package image holds 42 compiled instances, where the same package written without traits holds 146. The library's generic code is not compiled again for the member.
- Twenty packages that each add a member to one trait discard none of each other's code, in any load order.
- A new right-hand side for the ODE solver costs 59 ms at the prompt. The solver is not compiled again.

## What it costs

### No faster steady state

- The claim is no regression: trait code whose types are known runs as plain Julia's does, and a caller opts into code compiled per type with `compiled_for(x)`. A trait operation at a known type costs what a plain call costs ([`results.md`](results.md#what-it-costs)).
- The project does not claim that trait code runs faster than well-written plain Julia.

### First-run sessions are still slower than Python's

Whole sessions in a fresh process, start to exit ([`results.md`](results.md)):
- a report with the project's own small reader and table library (read, summarize, plot a histogram): 0.8 s, against 0.63–0.65 s for Python with pandas and matplotlib;
- an ODE solve with a plot, then a second model: 1.9 s, against 1.45 s for the same task in Python and 9.2 s for plain Julia with its ecosystem's packages;
- a scripted session with the ports of CSV.jl and DataFrames at a REPL: 2.6 s, against 0.7 s for pandas and 13.5 s for plain Julia.

Most of the time is Julia's start and the loading of package images.

### It needs a patched Julia

- TraitWorld runs only on Julia 1.13 with the design's changes (`julia-next/` in this workspace). It does not run on stock Julia.
- The changes are meant as proposals to Julia. None is upstream yet.

### Code that is not type-stable can become slower

- In the facts mode, Julia does not guess at calls whose types are unknown. It dispatches them at run time, and their results are typed `Any`. Type-stable code over concrete types is unaffected.
- This applies to trait modules. The worst cases are loops over containers of `Any`. How much a broad benchmark suite loses with all code compiled in this mode is not measured on this implementation.
- **How traits recover it.** Where values are mixed on purpose, declare it: a field or element typed by the trait, `Dynamic{X}`, or `Callable`. Their operations have declared result types, so the code after them stays typed.
- The rule the project follows: a slowdown is acceptable when rewriting the code with traits recovers it.
- To find such code, `fully_typed(f, (ArgType1, ArgType2))` reports the calls in `f`, and in what it calls, that neither the types nor the traits' members resolve. Code with none is exactly the code that builds ahead of time into a binary. `@warn_not_fully_typed` and `@enforce_fully_typed` check it when the code runs ([traits §14](../reference/traits.md#14-concreteness-and-fully-typed-mode)).

### Loading, editing, and code that uses no trait

- **Loading:** a membership is checked when it is declared, and a package's memberships are activated when its image loads. Loading TraitWorld and the packages that use it is most of each session's time above.
- **A member that joins after its caller was compiled** is reached through a table. Each session makes the table's entry on the first call: 18 ms for a member's two operations in the measured case.
- **Editing a method at a trait** runs its check again: about 0.5 s per edit in a session, 0.65–0.70 s for the first.
- **Code that uses no trait** runs on the same patched Julia, where dispatch and subtyping also look at memberships. Measured on CSV.jl and DataFrames without traits: the first run takes 3.3–3.5 s against 3.3 s on Julia 1.13.2, and repeated small operations 0.18–0.19 ms against 0.17–0.18 ms.
- **Loading TraitWorld after plain work** discards none of the plain code compiled before it.

[`results.md`](results.md) has each number with its measurement.

### Not "compiled once for any type"

- A method at a trait is compiled for each member's type that reaches it as itself or in a wrapper, once, in the image of the package that compiled it.
- Code is compiled once for all members where the argument is a box: at a trait that erases by default, such as `Callable`, and where a caller or a library boxes.

### What is not done yet

- **Ahead-of-time binaries:** a build (`juliac --trim`) has every member of a trait, so it compiles generic code for them, as Rust does. Small programs build and run; the four demonstrators' programs build, run and give a session's output ([`results.md`](results.md#ahead-of-time-binaries)). Not yet: an ODE program that passes callbacks it knows to the solver, and a port's program at scale.
- **Threads:** not tested.
- **Revise:** a membership can be declared again or taken back (`delete_membership`) in a running session, but Revise does not yet take back the membership of an `@implement` line deleted from a file.
- **Keys:** sharing one compiled copy among members that the trait sees alike (a type that forwards to a field, say) is Optional, not built ([traits §7.2](../reference/traits.md#72-the-key)).
- **Named implementations,** a second way for a type to join a trait, are Planned ([traits §17](../reference/traits.md#17-named-implementations)).
- **Scale:** the ports are the largest compositions tried; [`results.md`](results.md) says which parts of them run.

## Where to go next

- [`traits-by-example.md`](traits-by-example.md): the language, one feature at a time.
- [`results.md`](results.md): what the demonstrators show, with fair baselines.
- [`porting.md`](porting.md): porting an existing package, one function at a time.
- [`../design.md`](../design.md): the argument behind the design; the precise rules are in the [references](../reference/README.md).
