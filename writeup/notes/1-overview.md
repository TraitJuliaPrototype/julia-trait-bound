# Traits for better Julia

The overview of the design. It covers why, what it pays, a small example, and where the rest is written down.

1. **Overview** (this note): motivation, pay-offs, the core idea, an example.
2. **[Design choices](2-design-choices.md):** what the design decides, how C++, Rust, Swift and Mojo decided the same questions, what went wrong for them, and why we chose as we did.
3. **[Code written without traits](3-wrapping.md):** how Base, existing packages and a plotting system like Makie are used from the trait world: wrappers, calls upward, sealing.
4. **[The design in detail](4-details.md):** the rules, ownership, how types conform, checking, dynamic values, keywords, caching, AOT, in Julia's terms.

Measurements and prototypes are under "Further reading" below.

## Why

**Julia is fast once code is compiled, but compiled code is fragile.**
- Loading a package can discard compiled code: an unrelated method may change what an inferred call would select.
- A new type compiles the same library code again.
- Whether a program will need the compiler at run time is hard to know, which makes ahead-of-time compilation a matter of trial and error.

On the prototype, an ad-hoc session took 22 s to its first plot, about 13 s of it recompiling Makie code that the dependencies of a CSV reader had invalidated.

**Julia's types force a choice in large systems.**
- **A concrete type is data:** its fields and the types of its parts. What a value can do is not in its type but in the methods that apply to it, which any package can add or change.
- **An abstract type** can name intended behaviour, but nothing checks it.
- **Fast code needs concrete types where it runs.** So the concrete type must be known where the inner loop is compiled, and every signature and type parameter above it carries that type.

A value built in layers, a plot holding an observable holding a user's array, therefore has a type that grows with every layer:
- code is compiled per combination of what lies below;
- error messages print those types in full: one SciML stack frame line measured 33,673 characters.

The way out is a field typed `Any`, which stops the growth by giving up everything the type said: what the value can do, what a call returns, which methods it may reach. Makie keeps its attributes at `Any`; SciML carries the full types.

## The idea

> **A trait is an abstract type with behaviour.**

**Traits.** A trait declares what a value can do:
- **operations,** functions with declared argument and result types;
- **optionally fields,** with declared types.

Optionally, it guarantees that whatever conforms becomes concrete with respect to that behaviour. It is what abstract types should have been. Abstract types stay in Julia, and traits are a kind of them.

**Conformance.** A type joins a trait by declaring it, `@implement ColTable MyType`, also after the type was defined. The declaration is checked: every operation exists with the declared result types.

**The representation.**
- A conforming value is translated to a representation, plain data that library code works on, like `Vector{Vector{Float64}}`. It is either the value itself or the projection of one of its fields.
- Library code is compiled once per representation, not per user type. Many types share one representation, and so they share compiled code.

**Reading like abstract types.** Where a trait is used, it reads like an abstract type:
- an argument `t::ColTable` is compiled per representation;
- a field or container `plots::Vector{Plot}` holds values of any conforming type, behind the trait's operations.

The bound determines how a value becomes concrete, so signatures do not carry concrete types.

**The trait world.** Library code written with traits lives in trait modules. Together with Base and the packages wrapped for it, they form the trait world, which is closed:

> **Ordinary code may use the trait world; the trait world uses only itself.**

Compiled code in the trait world depends only on what lies below it, so nothing that happens above can change what it computes.

**Ownership.** Only one thing could reach into the trait world from above: a method that changes what a call inside selects. Julia already has a name for it, *type piracy*: adding a method to a function you do not own, for types you do not own.
- A function belongs to the module that creates it, wherever its methods come from: `Base.show` is Base's.
- A type belongs to the module that defines it.
- A method belongs to whoever owns its function or one of its types. `Base.show(io::IO, x::MyType)` in MyPackage is MyPackage's method on Base's function, and many packages own methods of one function.

Julia treats piracy as bad practice; the trait world makes it an error where traits are in effect. That is the one change to Julia's semantics the design depends on. ([The design in detail: Ownership](4-details.md#ownership).)

## The pay-offs

1. **Interactivity through cached code.**
   - Library code is compiled once, stored with the package that owns it, and reused in every session and every combination of packages.
   - Loading another package never discards it.
   - A new type that conforms by projection costs only the little code specific to that type.
2. **Simple ahead-of-time compilation.**
   - Dispatch over the types a program meets at run time goes through declared conformances, whose targets are listed.
   - A build can compile exactly the code the program can reach, and a trimmed binary does not die at its first generic call.
   - On the prototype, a program of this kind compiles to a 2.09 MB trimmed executable.
3. **No performance cliffs.**
   - The speed of compiled code does not depend on what else is loaded.
   - An abstract type that reaches a hot loop is reported when the package is built, at its root cause.
   - Library code is checked once, where it is defined, for every representation; a mistake is reported at its line before any user type exists.
4. **Minimal changes to semantics.**
   - A call computes exactly what it computes in Julia today, or raises an error: "identical or error".
   - Piracy is refused where traits are in effect. Whoever loads a pirate can opt out for it, and gets plain Julia for what it touches.
   - Readable types and error messages follow from signatures that carry bounds, not nested concrete types.

How each pay-off follows from the rules is in [The design in detail](4-details.md). What each costs, and what other languages paid for the same choices, is in [Design choices](2-design-choices.md).

## An example: a library and its user

The library is a trait module. The macros stand for syntax a language feature would provide; the prototype, TraitWorld, runs this code.

```julia
@trait_module module Columns
export ColTable, colmean, colrange, meandiff

@trait ColTable{R} begin                        # what the library needs from a table
    ncols(r::R)::Int
    col(r::R, i::Int)::Vector{Float64}
end

@implement ColTable{Vector{Vector{Float64}}} begin   # the library's own representation
    ncols(r) = length(r)
    col(r, i) = r[i]
end

colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
colrange(t::ColTable, i::Int) = (c = col(t, i); maximum(c) - minimum(c))
meandiff(a::ColTable, b::ColTable, i::Int) = colmean(a, i) - colmean(b, i)   # two trait objects
end
```

A user of the library, in ordinary Julia:

```julia
using Columns
import Columns: ncols, col

# 1. A type that holds a representation: conform through a field.
struct Measurements
    data::Vector{Vector{Float64}}
end
@implement ColTable Measurements      # the projection is t.data, the only new code

# 2. A type that is its own representation: conform through methods.
struct Ramp                           # column i is base .* i, never stored
    base::Vector{Float64}
    n::Int
end
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp              # checks the methods; Columns' functions compile once for Ramp

m, r = Measurements([[1.0, 2.0], [3.0, 5.0]]), Ramp([1.0, 2.0], 2)
colmean(m, 1)                         # 1.5, in the code Columns compiled when it was built
colmean(r, 1)                         # 1.5, in code compiled once for Ramp
meandiff(m, r, 1)                     # 0.0, compiled for this pair of representations
```

**What happens:**
- **Measurements.** It projects onto the library's own representation, so `colmean(m, 1)` runs code that was compiled and cached when Columns was built. Loading CairoMakie afterwards changes none of it.
- **Ramp.** It is its own representation, so Columns' functions are compiled once for it, in the user's session or package.
- **Inside `colmean`.** The argument is a *trait object*. Library code can call `ncols` and `col` on it and nothing else, which is why it can be checked once for every type that will ever conform.
- **Errors at the library's build.** A mistake such as `size(t)` is reported when Columns is built: "`size` has no method for a trait object carrying ColTable".

## What it costs

Each cost is discussed in [Design choices](2-design-choices.md#what-the-choices-cost).
- **A stranger's piracy refuses a load,** where it would change code the trait world compiled against. The error reaches whoever loads the pirate.
- **Code outside the trait world is reached through declared calls.** A plotting system like Makie, as written today, is called that way, not run inside ([Code written without traits](3-wrapping.md)).
- **Dynamic positions cost an indirect call or a dispatch:** functions passed as dynamic calls, values kept as `Dynamic{X}`.
- **Code written without traits is curated:** conformances for Base's families, and one wrapper per package that the trait world uses.
- **Runtime work is not proven.** The runtime pieces (an invalidation filter, a dispatch check, refusing a pirate at load) exist only as prototypes on stock and patched Julia.

## Status

TraitWorld, the prototype on Julia 1.12, runs:
- traits, conformances, entries and workers;
- the checks, including definition checking at archetypes;
- sealing;
- caches per representation;
- `verify_main` for trimmed binaries;
- prototypes around DataFrames and Makie.

The runtime pieces it needs exist as experiments: a patched Julia with an invalidation filter at method insertion and at image load.

## Further reading

- `writeup/design-findings.md`: measurements, prototype results, the earlier forms of the design and why they changed.
- `writeup/other-languages.md`: the research behind the design choices, with sources.
- `writeup/proposal-stored-values.md`, `writeup/proposal-definition-checking.md`: the proposals behind dynamic values, definition checking and named implementations.
- `poc/world/README.md` (TraitWorld) and `poc/interfaces/README.md` (the prototype around DataFrames and Makie).
- `writeup/traits-for-better-julia.md`: the single note these four notes replace, as of the live note's revision 1146.
