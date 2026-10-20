# Traits for Julia

This page is for Julia users and package authors. It covers:
- the problems the design addresses;
- what you write;
- what you get;
- one worked example;
- what it costs, and what is not done yet.

It assumes you know Julia. It does not assume you have read the design. The precise rules are in the [references](../reference/README.md), written for Julia's core developers. The terms, with their origins in other languages, are in [`../glossary.md`](../glossary.md). The measurements are in [`results.md`](results.md). Porting an existing package is in [`porting.md`](porting.md).

**Status, 2026-10-19.** This is a research prototype:
- a package, TraitWorld;
- a patched build of Julia 1.13.2, which TraitWorld needs;
- four demonstrators: an ODE solver, a plotting library, a data report, and ports of CSV.jl and DataFrames.jl. The data report brings its own CSV reader and table library, two packages that count as part of it.

Nothing is registered. Nothing is upstream.

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

In the trait world an extension declares an implementation instead, which discards no trait code (TraitCSV's `String15`). This is a gain from traits as a coding pattern, even in a well-trodden part of the ecosystem: the compiler's facts mode alone does not prevent it.

### 2. A vector of mixed types is slow, or forces you to over-parametrize

Say you keep shapes of several types in one vector. Plain Julia offers two choices.
- **An abstract element type,** `Vector{AbstractShape}`. There is one copy of the code. But each call on an element is a dynamic dispatch at run time, about 30 ns. Julia is faster only when it happens to see few matching methods, and that changes when someone adds a shape type.
- **A type parameter for each part,** such as `struct Scene{T <: Tuple}`. The calls are fast. But code is compiled for every combination of types, and the types grow with every layer.

A real case: in SciML, a callback's type is part of the integrator's type. So a new callback closure compiles the solver again, 0.84–0.96 s, although the solver step never reads the callback.

### 3. Errors surface deep inside a library, with huge types

- An abstract type names what you intend. Nothing checks it.
- If your type lacks a method the library needs, you get a `MethodError` deep in the library's stack, at the first call.
- Concrete types are printed in full in error messages. A SciML integrator's type runs to 3,553 characters. One stack-frame line measured 33,673 characters.

### 4. You cannot say "a function from `Float64` to `Float64`"

- A function's type says which function it is, not what it takes and returns.
- An argument `f::Function` accepts any function. A mistake shows at the first call, deep inside.
- An argument without a type annotation compiles the library again for every new function, closures included.
- FunctionWrappers.jl avoids the recompiling, but nothing checks the signature.

## What you write

TraitWorld provides a few macros and types. The syntax below is TraitWorld's, checked against its test suite.

### A trait

A trait says what a library needs from a value: operations with declared argument and result types.

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end
```

A trait can also declare fields with types (writable unless marked `@const`), defaults written in terms of the other operations, and type parameters:

```julia
@trait Integrator{U, P} begin
    u::U                 # the state
    @const p::P          # the parameters, read-only
    t::Float64
end
```

A trait can require that what it sees of a conforming type be concrete. Put `@concrete_only` in the trait's body to refuse an implementation that is not, or `@warn_on_abstract` to warn (the spelling will change to one declaration with a level). Without either, an abstract field type is allowed, and code reads it with dynamic dispatch.

A trait is a kind of abstract type: you write it where you would write an abstract type, and it names a set of types. It follows different rules:
- **A type joins a trait after the fact.** The type's definition does not name the trait; an implementation does, written later, by the package that owns the type or the one that owns the trait. A type joins an abstract type only in its own definition.
- **A type can join several traits.** An abstract type gives a type one chain of supertypes.
- **Joining is checked.** The implementation must provide the trait's operations and fields, with their types. Subtyping an abstract type promises nothing that is checked.
- **A supertrait is a requirement.** `@trait B <: A` says a type that implements `B` implements `A` too. It is not a place in a tree.
- **Types win in dispatch.** A method for a type, concrete or abstract, is chosen before a method bounded by a trait, so a library can adopt traits one function at a time.

Abstract types stay in Julia: numbers keep `Number` and `Real`. `conforms(T, X)` asks whether a type implements a trait; `T <: X` will ask the same once traits are part of Julia's types (today it is `false`). The full comparison is in [the traits reference §16](../reference/traits.md#16-membership).

### An implementation: your type implements a trait

You declare that a type implements a trait with `@implement`. TraitWorld checks the declaration when you write it: every operation must exist, with the declared result type.

There are two ways to implement a trait:
- **Your type has a field that already implements it.** `@implement ColTable Measurements by data` forwards the trait to the field `data`. No field is special: forwarding is always written with `by`.
- **Your type implements the operations itself.** Define the methods, then declare the implementation.

Who may declare an implementation: the package that owns the trait, or the package that owns the type. A third package that owns neither may not.

### A bounded function

A function whose argument is annotated with a trait is *bounded* by it:

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

- It accepts a value of any type that implements `ColTable`.
- Inside, on `t` it can use only what the trait declares, here `ncols` and `col`. On ordinary values, such as the column `col` returns, it calls any Julia code.
- It is compiled for what the trait can see, not for your whole type. A type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for `Vector{Vector{Float64}}`. Its other fields never cause a recompile.
- A method with a type annotation, concrete or abstract, wins over a bounded one; only an untyped method loses to it. So a library can adopt traits one function at a time.
- **`Compiled` or `Dynamic`.** Where the calling code knows the value's type, the function runs code compiled for what the trait can see of it, as plain Julia compiles per type. Where it does not (an item of a `Vector{Any}`, a call typed at the prompt), the function runs code compiled once, and each operation dispatches when it runs, with its declared result type. The results are the same. `compiled_for(x)` and `with_dynamic(x)` choose for one value; a library can write `t::Compiled{ColTable}` or `t::Dynamic{ColTable}`.

### A trait module

Library code that uses traits lives in a *trait module*, marked `@trait_module module … end`. A trait module:
- is compiled in a new mode of the patched compiler (see "What you get", point 1);
- has its bounded functions checked when it is defined;
- may not commit piracy (below).

Code outside trait modules is ordinary Julia. It calls bounded functions as it calls any function. A trait module can call any Julia code: Base, CSV.jl, Cairo, ForwardDiff.

### `Dynamic{X}`: a value of any type that implements `X`

For a mixed collection, or a field whose value can change type, use `Dynamic{X}`.
- `Dynamic{X}(v)` holds your value `v`, seen through trait `X`.
- Inside a trait module, a trait's name in a field or a container means its `Dynamic`. A field `shapes::Vector{Shape}` is a `Vector{Dynamic{Shape}}`.
- Outside a trait module, write `Dynamic{Shape}` out.
- Calling an operation on a `Dynamic` value tests for the known types first, with direct calls that inline. It falls back to a dynamic call for the rest.
- Passing a `Dynamic` value to a bounded function runs the code compiled once; `compiled_for(d)` runs the code compiled for the value's type.

### `Callable`: a function with a declared signature

```julia
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))
```

- `f` may be any function or closure. The library calls it as `f(x)`.
- Every call is checked: a result that is not a `Float64` raises an error.
- **`Dynamic` or `Compiled`.** The library may choose in the bound; the caller can convert one value.
  - `Dynamic`, `Callable`'s default: the library is compiled once for the signature, not once per function. Each call is an indirect call, about 4 ns.
  - `Compiled` (`f::Compiled{Callable{A, S}}`): the library is compiled for this particular function, at plain Julia's speed, with the signature still checked. An ODE right-hand side wants this.
  - The caller converts with `compiled_for(f)` or `with_dynamic(f)`. The attribute changes speed, never results.

### Piracy and strict mode

- *Type piracy* is defining a method of a function you do not own, for types you do not own. An example from the project's tests: a package defines `+` for ForwardDiff's `Dual` numbers. It owns neither `+` (Base's) nor `Dual` (ForwardDiff's).
- By default, a pirate's method is followed, as in plain Julia. Code that the pirate changes is compiled again, once.
- **Strict mode** is an option that refuses another package's method, on a function and for types that package does not own, when the method would change compiled trait code (library code in trait modules). Plain code is not protected by it. It is off by default. Turn it on with `TraitWorld.strict!(true)` or `JULIA_TW_STRICT=1`.

## A worked example: a library and its user

### The library

The library is a trait module. It is meant to be pasted into a REPL running the patched Julia with TraitWorld installed. Run as written on the build of 2026-10-19; at a REPL, enter the user's declarations one at a time (`struct Counts` before its `@implement`). In a package, put the trait module in its own file and `include` it from the package's module, as TraitTables does.

```julia
using TraitWorld

@trait_module module Columns
using TraitWorld
export ColTable, ncols, col, colmean, meandiff, colmap, Shelf, shelf, add!, means

@trait ColTable begin                                  # what the library needs from a table
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end

@implement ColTable Vector{Vector{Float64}} begin      # the library's own implementation
    ncols(t) = length(t)
    col(t, i) = t[i]
end

colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
meandiff(a::ColTable, b::ColTable, i::Int) = colmean(a, i) - colmean(b, i)

# a function argument with a declared signature, Float64 -> Float64
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))

# tables of any conforming types, kept together
struct Shelf
    tables::Vector{ColTable}       # in a trait module: a Vector{Dynamic{ColTable}}
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

# 2. A type that implements the operations itself.
struct Ramp                           # column i is base .* i, never stored
    base::Vector{Float64}
    n::Int
end
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp              # checked now: both operations exist, with the declared results

m = Measurements("run 1", [[1.0, 2.0], [3.0, 5.0]])
r = Ramp([1.0, 2.0], 2)

colmean(m, 1)              # 1.5
colmean(r, 2)              # 3.0
meandiff(m, r, 1)          # 0.0
colmap(x -> 2x, m, 2)      # [6.0, 10.0]

s = shelf()
add!(s, m); add!(s, r)     # two types in one collection
means(s, 1)                # [1.5, 1.5]
```

### What happens

- **At the prompt** the values are `Dynamic`: the prompt knows no types, so each function runs its code compiled once, for every type, and each operation dispatches when it runs. The results are the same as below.
- **In a function that knows the types** (a script's functions, a package, or `colmean(compiled_for(m), 1)` at the prompt) the values are `Compiled`:
  - **`Measurements`.** The trait sees only the `data` field, a `Vector{Vector{Float64}}`. So `colmean(m, 1)` runs the code compiled for `Vector{Vector{Float64}}`. Any other type that forwards to such a field shares that code. If Columns is a package whose precompile workload runs that code, it is cached in Columns' package image.
  - **`Ramp`.** It implements the operations itself, so Columns' functions are compiled once for `Ramp`.
  - **`meandiff(m, r, 1)`** is compiled for this pair of types.
- **The shelf** holds a `Measurements` and a `Ramp` in one vector. `means` is compiled once, whatever the shelf holds.
- **`colmap`** is compiled once for the signature `Float64 -> Float64`, not once per closure.

### The mistakes, and where they are caught

**A user's type that does not fit.** The trait declares that `col` returns a `Vector{Float64}`:

```julia
struct Counts; n::Int; end
ncols(c::Counts) = c.n
col(c::Counts, i::Int) = fill(i, 3)       # a Vector{Int}
@implement ColTable Counts
```

The `@implement` line raises an `ImplementError`. Its message includes:

```
`col` at Tuple{Counts, Int64} returns `Vector{Int64}`, declared `Vector{Float64}`
```

The error comes at the declaration, before any `Counts` value is passed to the library.

**A function with the wrong result type:**

```julia
colmap(x -> 1, m, 1)      # TypeError: the closure returned an Int, the signature says Float64
```

**A library author's mistake.** Suppose Columns contained this line:

```julia
colsum(t::ColTable) = sum(t)      # meant: sum(col(t, 1))
```

`ColTable` does not declare `sum`. TraitWorld checks every bounded function once, when the trait module is defined. It checks the function against the trait alone, not against any particular type. The report names the line, and reads roughly:

```
TraitUseError: library code breaks a rule of the trait world:
  Columns.jl:21: a trait object carrying ColTable is passed to `sum`, an ordinary function:
  it can do only what its traits declare. Declare `sum` as an operation, or use the operations
```

A *trait object* is what a bounded function sees: your value, through the trait. When Columns is precompiled as a package, this is an error. At the REPL it is a warning, and the call raises it.

**A value of no conforming type.** `colmean(42, 1)` raises a `MethodError`, as plain Julia would.

## What you get

The numbers on this page are from the patched Julia of 2026-10-20 (julia-1.13 3b8085c222), unless marked. [`results.md`](results.md) has them with their baselines.

### 1. Compiled code that loading other packages does not discard

The patched compiler compiles trait modules in a new mode. (The design calls it the facts mode: [the rationale §2](../design.md#2-the-argument-in-four-steps).)
- A call whose argument types are all known is compiled as plain Julia compiles it.
- A call whose argument types are not all known is not guessed at. It is dispatched when it runs, as Julia's dynamic dispatch does.
- So compiled code depends only on calls whose types are all known. Only two kinds of change can alter one of those:
  - the package that owns the function, or one of the types, changes it: an edit, an upgrade, and (still being decided) one of its package extensions;
  - a pirate whose method wins at that call.
- So an unrelated package's load cannot discard the code, in any load order.
- By default a pirate is followed, and the code it changes is compiled again. With strict mode on, the pirate is refused. Then compiled code is discarded only when code it depends on changes.
- A few exceptions remain in both settings, listed in [the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated).

**This protection comes from the compiler's facts mode, and it works for any code.** Upstream CSV.jl and DataFrames compiled in it lose 2 of 3,337 pieces of compiled code to nine unrelated loads, against 561 of 4,684 in Julia's usual mode, and their first work takes 0.52 s instead of 3.3 s ([`results.md`](results.md)). What traits add:
- **The mode costs type-stable bounded code nothing.** A bounded function is compiled for the types the trait sees. If those are concrete, and its code is type-stable, all its calls have known types, and those are compiled as plain Julia compiles them. A typed call into trait code costs 0.8 ns, as a plain call does. Plain code that is not type-stable gets slower in this mode (see "What it costs").
- **The code is compiled once and cached.** It lives in the package image of the package that compiled it, and stays valid there.

Not discarding code is not the same as no extra cost after loads: some first calls cost more after big loads than without them ([`results.md`](results.md)).

### 2. Errors at the line you wrote, before any value exists

- A library's bounded functions are checked when the trait module is defined. A call the trait does not allow is reported at its line, before any user type exists.
- A user's implementation is checked at `@implement`, before any value reaches the library.
- A `Callable` checks its result at every call.
- Not everything is caught early. In the ODE demonstrator, a problem type with a `Float64` buffer fails only at run time, under automatic differentiation, 28 frames deep. The check at `@implement` cannot prove that this conversion fails.

### 3. Readable types

- A bounded argument prints as the trait and the type its code was compiled for: `ColTable at Vector{Vector{Float64}}`. The `label` of a `Measurements` never appears.
- The ODE demonstrator's integrator type is `Tsit5Integrator{Float64, Vector{Float64}}`, with or without callbacks. SciML's is 3,553 characters.
- TraitWorld hides most of its own frames in stack traces (the entry's frame remains).
- Printing by trait needs the patched Julia.

### 4. Mixed collections at near plain speed

- Summing areas over a vector of `Dynamic{Shape}` (build of 2026-10-19): 1–1.4 ns per element when the data is in cache. Plain Julia: about 0.9 ns when it sees two shape types, about 30 ns when it sees four. On a million elements: 4.5–5.7 ns against plain's 4 ns.
- The fast path holds for up to four conforming types. Further types go through a dynamic call. The cost with more than four types is not measured.
- A type that conforms later works at once. It goes through the dynamic call, and discards no compiled code.

### 5. Functions with a checked signature

- `Callable{Tuple{Float64}, Float64}` says "a function from `Float64` to `Float64`", and checks it.
- In the default mode, a new closure compiles nothing in the library. In the ODE demonstrator, a new callback closure costs about 13 ms with no other packages loaded. In SciML it recompiles the solver: 0.84–0.96 s.
- Plain Julia can avoid the recompile with FunctionWrappers.jl. The project's plain twin of the ODE solver does so, and is as fast or faster for a first callback in a fresh session (measured on the previous prototype). What `Callable` adds is the declared, checked signature, and a choice of modes.

## What it costs

### It needs a patched Julia

- TraitWorld runs only on the patched build of Julia 1.13.2 (`julia-1.13/` in this workspace). It does not run on stock Julia.
- The changes are meant as proposals to Julia. None is upstream yet.

### Code that is not type-stable can become slower

- In the new mode, Julia no longer guesses at calls whose types are unknown. It dispatches them at run time, and their results are typed `Any`. Type-stable code over concrete types is unaffected.
- This applies to trait modules and to the plain code they call.
- With *all* code in this mode, Julia's benchmark suite (4,342 benchmarks) is 3.7% slower on the geometric mean. The worst cases, on containers of `Any`, are up to 28× slower.
- **How traits recover it.** Where values are mixed on purpose, declare it with `Dynamic{X}` or `Callable`. Their operations have declared result types, so the code after them stays typed.
  - A ray tracer over four shape types (build of 2026-10-19): plain Julia about 850 ms, the trait form about 320 ms.
  - With two shape types, plain Julia stays faster: about 250 ms.
- The rule the project follows: a slowdown is acceptable when rewriting the code with traits recovers it.
- To find such code, `fully_typed(f, (ArgType1, ArgType2))` reports the calls in `f`, and in what it calls, whose argument types are not known.

### Imports and implementations take a little longer

- A trait form's `using` takes 0.02–0.2 s longer than its plain twin's in the demonstrators.
- `@implement` checks the implementation: 22–89 ms for a new type in the demonstrators.
- A call into trait code from code that does not know its argument types takes 29 ns per call, against 19 ns for a plain dynamic call.

### Not "compiled once for any type"

- A type that implements operations itself gets its own compiled copy, compiled once.
- Code is shared through forwarding, defaults, `Dynamic` and `Callable` in its default mode.

### What is not done yet

- **Threads:** not tested.
- **Revise and redefinition:** changing an implementation in a running session needs a restart.
- **`where` variables in bounds:** a bounded function cannot yet name the trait's type parameters with `where`.
- **Traits in the type system:** a trait is not yet a supertype that `isa` and subtyping understand. Until then:
  - outside trait modules, `Dynamic{X}` is written out;
  - `conforms(T, X)` answers "does type `T` implement trait `X`?" as a function.
- **Strict mode** is a prototype. On a stack with CSV, DataFrames and CairoMakie it refuses nothing; its load cost is 0.5 s on a 4.1 s load (measured on the previous prototype).
- **Ahead-of-time binaries:** a trimmed TraitMakie binary is 4.07 MB (measured on the previous prototype).
- **Scale:** the demonstrators are libraries of a few hundred to a few thousand lines. Larger compositions are untested.

## Where to go next

- [`results.md`](results.md): what the demonstrators show, with fair baselines.
- [`porting.md`](porting.md): porting an existing package, one function at a time.
- [`../design.md`](../design.md): the argument behind the design; the precise rules are in the [references](../reference/README.md).
