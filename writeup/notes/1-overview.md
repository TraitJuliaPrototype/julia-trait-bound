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

**Julia compiles a function for the whole type of each argument.**
- **A concrete type is data:** its fields and the types of its parts. What a value can do is not in its type but in the methods that apply to it, which any package can add or change.
- **A method is compiled for the argument's full concrete type,** even when its body never reads some of its parts. In SciML a callback's type is part of the integrator's type, so a new callback closure recompiles the solver, 0.84–0.96 s, although the step never reads the callback.
- **An abstract type** can name intended behaviour, but nothing checks it, and fast code needs the concrete type where it runs. So every signature and type parameter above the inner loop carries that type.

A value built in layers, a plot holding an observable holding a user's array, therefore has a type that grows with every layer:
- code is compiled per combination of what lies below, including the parts it never reads;
- error messages print those types in full: one SciML stack frame line measured 33,673 characters.

The way out is a field typed `Any`, which stops the growth by giving up everything the type said: what the value can do, what a call returns, which methods it may reach. Makie keeps its attributes at `Any`; SciML carries the full types.

## The idea

> **A trait is an abstract type with behaviour.**

**Traits.** A trait declares what a value can do:
- **operations,** functions with declared argument and result types;
- **fields,** with declared types, readable, and writable unless declared `@const`.

A field's type may be a parameter of the trait, an *associated type*: `@trait Integrator{U, P}` declares the fields `u::U` and `p::P`. Optionally, a trait guarantees that whatever conforms becomes concrete with respect to that behaviour: that its associated types are concrete. A trait is what abstract types should have been. Abstract types stay in Julia, and traits are a kind of them.

**Conformance.** A type joins a trait by declaring it, `@implement ColTable MyType`, also after the type was defined.
- **The operations** are implemented by the type itself, or forwarded to one of its fields whose type implements them.
- **The declared fields** are stored fields of the type, by name or mapped, `name => label`.

The declaration is checked: every operation and field exists, with the declared types.

**Compiled for what the bound can see.**
- A function bounded by a trait reaches its argument only through the trait's operations and fields.
- So it is compiled for the types those involve, not for the argument's own type. These types are the bound's *key*: the *implementing type*, whose methods serve the operations (the argument's type, or the field it forwards to; none when the trait's defaults serve them all), and the types of the declared fields.
- Types that differ only in what the trait cannot see share compiled code:
  - every table type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code the library compiled for `Vector{Vector{Float64}}`;
  - a solver step bounded by an `Integrator` trait is compiled per the types of what the trait declares (state, parameters, step size, cache, options), so a new callback, which the trait does not declare, compiles nothing.
- A type that implements the operations itself, or overrides a default, is part of the key, by its own choice; a type that keeps the defaults is not.

**Reading like abstract types.** Where a trait is used, it reads like an abstract type:
- an argument `t::ColTable` is compiled for what its bound can see;
- a field or container `plots::Vector{Plot}` holds values of any conforming type, behind the trait's operations.

The bound determines how a value becomes concrete, so signatures do not carry concrete types.

**The trait world.** Library code written with traits lives in trait modules. Together with Base and the packages wrapped for it, they form the trait world, which is closed:

> **Ordinary code may use the trait world; the trait world uses only itself.**

Compiled code in the trait world depends only on what lies below it, so nothing that happens above can change what it computes.

**Ownership.** Only one thing could reach into the trait world from above: a method that changes what a call inside selects. Julia already has a name for it, *type piracy*: adding a method to a function you do not own, for types you do not own.
- Owners are packages. A function belongs to the package that creates it, wherever its methods come from: `Base.show` is Julia's.
- A type belongs to the package that defines it.
- A method may be defined only by a package that owns its function or one of its types: its stakeholders. `Base.show(io::IO, x::MyType)` in MyPackage is allowed because MyPackage owns `MyType`; many packages define methods of one function, each as a stakeholder of its own methods.

Julia treats piracy as bad practice; the trait world makes it an error where traits are in effect. That is the one change to Julia's semantics the design depends on. ([The design in detail: Ownership](4-details.md#ownership).)

## The pay-offs

1. **Interactivity through cached code.**
   - Library code is compiled once per key, stored with the package that owns it, and reused in every session and every combination of packages.
   - Loading another package never discards it.
   - A new type that forwards to a field of a known type costs no new library code, and a new value that the bound does not see, such as a callback, costs none either.
2. **Simple ahead-of-time compilation.**
   - Dispatch over the types a program meets at run time goes through declared conformances, whose targets are listed.
   - A build can compile exactly the code the program can reach, and a trimmed binary does not die at its first generic call.
   - On the prototype, a program of this kind compiles to a 2.09 MB trimmed executable.
3. **No performance cliffs.**
   - The speed of compiled code does not depend on what else is loaded.
   - An abstract type that reaches a hot loop is reported when the package is built, at its root cause.
   - Library code is checked once, where it is defined, for every type that will ever conform; a mistake is reported at its line before any user type exists.
4. **Minimal changes to semantics.**
   - A call computes exactly what it computes in Julia today, or raises an error: "identical or error".
   - Piracy is refused where traits are in effect. Whoever loads a pirate can opt out for it, and gets plain Julia for what it touches.
   - Readable types and error messages follow from signatures that carry bounds, not nested concrete types.

How each pay-off follows from the rules is in [The design in detail](4-details.md). What each costs, and what other languages paid for the same choices, is in [Design choices](2-design-choices.md).

## An example: a library and its user

The library is a trait module. The macros stand for syntax a language feature would provide; the prototype, TraitWorld, runs this code in an earlier spelling (Status).

```julia
@trait_module module Columns
export ColTable, colmean, colrange, meandiff

@trait ColTable begin                               # what the library needs from a table
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end

@implement ColTable Vector{Vector{Float64}} begin   # the library's own implementation
    ncols(t) = length(t)
    col(t, i) = t[i]
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

# 1. A type that holds a table: it forwards the trait to its field.
struct Measurements
    label::String
    data::Vector{Vector{Float64}}
end
@implement ColTable Measurements      # data's type implements ColTable; label is invisible to Columns

# 2. A type that implements the operations itself.
struct Ramp                           # column i is base .* i, never stored
    base::Vector{Float64}
    n::Int
end
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp              # checks the methods; Columns' functions compile once for Ramp

m, r = Measurements("run 1", [[1.0, 2.0], [3.0, 5.0]]), Ramp([1.0, 2.0], 2)
colmean(m, 1)                         # 1.5, in the code Columns compiled when it was built
colmean(r, 1)                         # 1.5, in code compiled once for Ramp
meandiff(m, r, 1)                     # 0.0, compiled for this pair of keys
```

**What happens:**
- **Measurements.** Its bound sees `Vector{Vector{Float64}}`, the type of the field it forwards to, so `colmean(m, 1)` runs code that was compiled and cached when Columns was built. Any other type holding such a field shares it. Loading CairoMakie afterwards changes none of it.
- **Ramp.** It implements the operations, so its bound sees `Ramp`, and Columns' functions are compiled once for it, in the user's session or package.
- **Inside `colmean`.** The argument is a *trait object*: what the bound can see, and nothing else. Library code can call `ncols` and `col` on it, which is why it can be checked once for every type that will ever conform.
- **Errors at the library's build.** A mistake such as `size(t)` is reported when Columns is built: "`size` has no method for a trait object carrying ColTable".

**Fields as the key.** A trait whose fields are typed by its associated types compiles per those types:

```julia
@trait Integrator{U, P, C} begin
    u::U                              # the state, writable
    p::P                              # the parameters, writable: a callback may rebind them
    t::Float64
    dt::Float64
    @const cache::C                   # the algorithm's cache
end
step!(i::Integrator) = …              # compiled per (U, P, C): callbacks, the solution and anything else
                                      # the integrator holds are not in the key
```

Keys do not remove every recompile. A `Float32` state, or a new loss under automatic differentiation (its dual numbers' tag carries the loss's type), changes `U`, and compiles the step again, as today.

## What it costs

Each cost is discussed in [Design choices](2-design-choices.md#what-the-choices-cost).
- **A stranger's piracy refuses a load,** where it would change code the trait world compiled against. The error reaches whoever loads the pirate.
- **Code outside the trait world is reached through declared calls.** A plotting system like Makie, as written today, is called that way, not run inside ([Code written without traits](3-wrapping.md)).
- **Dynamic positions cost an indirect call or a dispatch:** functions passed as dynamic calls, values kept as `Dynamic{X}`.
- **Code written without traits is curated:** conformances for Base's families, and one wrapper per package that the trait world uses.
- **Runtime work is not proven.** The runtime pieces (an invalidation filter, a dispatch check, refusing a pirate at load) exist only as prototypes on stock and patched Julia.

## Status

As of 2026-10-16:
- **TraitWorld,** the prototype, runs on stock Julia 1.13.2, 311 tests. It covers:
  - traits with operations, fields and associated types; conformances by implementation and by forwarding, with field mappings; keys;
  - the checks, including definition checking at archetypes;
  - dynamic values, results like the input, printing by bound and key;
  - sealing; caches per key; `verify_main` for trimmed binaries.
- **Its loops run at plain-Julia speed,** but its fixed cost per call is still 200–460 ns. A rewrite that makes conformances methods (a prototype runs at plain speed per call) waits for a decision.
- **The runtime pieces** exist as experiments: the load filter injected into stock 1.13.2, and a patched Julia with the filter at method insertion (on 1.12; the 1.13 build is postponed).
- **The demonstrators,** TraitDifferentialEquations and TraitMakie, are skeletons with plans.

What is decided, and its status, is in `writeup/decisions.md`; what is open in `writeup/open-issues.md`.

## Further reading

- `writeup/decisions.md`: every design decision with its status; `writeup/open-issues.md`: what is open.
- `writeup/design-findings.md`: measurements, prototype results, the earlier forms of the design and why they changed.
- `writeup/other-languages.md`: the research behind the design choices, with sources.
- `writeup/explorations/`: the demonstrators' designs (solvers, Makie), the runtime, associated types, and the plan for keys in TraitWorld.
- `experiments/`: the measurements (`baseline-1.13.md`, `lens/`, `keys-proto/`) and the earlier prototypes (`world/`, `interfaces/`).
- `attic/writeup/`: the single note these four notes replace (revision 1146), the proposals behind dynamic values and definition checking, the earlier proof-of-concept plans.
