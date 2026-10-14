<!-- Local copy of the design note "Traits for better Julia" (Claude Doc, https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20), exported at rev 1019 on 2026-10-14, after the Fable review (session note 17). The artifact is the live note; this copy is for offline reading and for diffing between revisions. Refresh it by exporting the tab as markdown. -->

# Traits for better Julia

Oct 13, 2026 · @Frank

## Four goals

Julia is fast once code is compiled, but compiled code is fragile. Loading a package can discard it, a new type compiles the same library code again, and whether a program will need the compiler at run time is hard to know. The trait design pursues four goals:

1. **Interactivity through pervasive, composable caching of code.** Library code that uses traits is compiled once, stored with the package that owns it, and reused in every session and every combination of packages. Loading another package never discards it, and a new user type that conforms by projection costs only the little code that is specific to that type.
2. **Simple ahead-of-time compilation****.** When the main function is fully trait specified, a build can compile/link exactly the code the program can reach. There is an incremental, well-specified path to precompiled Julia binaries.
3. **No performance cliffs.** The speed of compiled code does not depend on what else happens to be loaded. An abstract type that reaches a hot loop is reported when the package is built, at its root cause.
4. **Minimal changes to semantics****,**** minim****al perfo****rmance co****sts****.** A call computes exactly what it computes in Julia today, or raises an error: "identical or error". The most important change is that piracy is outlawed where traits are in effect. By opting out the caller of a library can restore full compilation and disable all trait checks, to achieve identical results to today's Julia.

## The core concepts

> **Ordinary code may use the trait world; the trait world uses only itself.**

The **trait world** is Base, Core, the standard libraries, every trait module, and what interface packages admit of other packages. It is closed: a trait module handles only values of trait-world types, and everything it reaches is checked, on the compiled code, to do the same. Ordinary code, which is all of Julia today, may depend on the trait world as on any package, and a package can pair a trait module with an ordinary module that uses both. What the check admits, how an interface package admits or declares, and what makes Base pass, are under "Finer points".

This two-layer design enables everything else. Compiled code in the trait world depends only on what lies below it, so nothing that happens above it can change what that code computes. Cached code therefore stays valid, which gives interactivity. Within the trait world, the same checks that ensure that the world is closed, give simple AOT. The primary way in which one can reach into the trait world from above is piracy, which this design forbids.

The core concepts are:

- **Trait**** ****a****n****d**** ****i****t****s rep****resenta****tion****.** A contract stating what library code needs from a type: operations on a representation. Every trait specifies which data it operates on. The data can be concrete, even if the type the trait is defined on is abstract. The representation is a parameter (that might be inferred), as in `M``y``T``r``ai``t``{R}``.` A trait may provide default operations. Representations can be constrained to be concretely typed.
- **I****mplementation.** A representation is typically plain, deeply concrete data that library code works on, such as `Vector{Vector{Float64}}`. An implementation, written ` @implement  ``M``y``Table``  M ``yT``ype`, defines the trait's operations once for a representation, or for a family of them, as ordinary methods that library code calls directly. As much of the implementation as possible is inferred automatically. Implementation is where the ordinary Julia world crosses into the Trait world.&#32;
- **Trait module****s**** and t****rait-****bound c****ode****.** A module whose code is fully specified in terms of traits. We say the code is trait-bound. A trait module is declared `@trait_module module M … end`. Its exported functions take arguments bounded by a trait; its internal functions need none, and are inferred from the representations those bounds admit. These make up the trait world.

### An example: a library and its user

The library, a trait module (`Columns/src/Columns.jl`). The macros stand for syntax a language feature would provide. The prototype, TraitWorld (`poc/world`), runs the library as written, with the module body in a `@trait_module begin … end` block inside `module Columns`. The user's side below uses the one-line form of `@implement`, which is design; the prototype runs the written-out forms listed under "How a type conforms to a trait" further down.

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

A user of the library (`analysis.jl`), in ordinary Julia:

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
colmean(m, 1)                         # 1.5, in the worker Columns compiled when it was built
colmean(r, 1)                         # 1.5, in a worker compiled once for Ramp
meandiff(m, r, 1)                     # 0.0, a worker for this pair of representations
```

`@implement ColTable T` with nothing else reads the type. Methods of the trait's operations for `T` make it its own representation, checked as an implementation. Otherwise the field named `data`, or the one field whose type conforms to the trait, is the projection; that field's type must conform and be concrete, or the declaration fails with the field named. The two ways differ in cost. A projection adds no compiled code: `Measurements` runs the workers Columns compiled when it was built. An own representation compiles the library's functions once for the type, and `meandiff` once for each pair of representations it meets. A projection written out, operations of a type's own, one projection for several traits, and implementations for representations one does not own are the written-out forms, under "How a type conforms to a trait" below.

&#91;embedded content: a trait-conformant call · 3 compile classes\]

The entry is compiled once, the projection per type, and the worker with the library code it reaches per representation, or per tuple of representations when a function takes several trait objects. Dashed calls are dynamic, over targets the projections list; solid calls are compiled within the trait world.

### The rules of the trait world

Seven rules make the principle precise. Rule 1 is layering itself. Rules 2 to 4 say how a value crosses into the trait world and what it is there; rules 5 to 7 say who may change code in the trait world, what a call sees, and where compiled code lives.

1. **Layering.** Ordinary code may use the trait world; the trait world uses only itself. A trait module reaches code outside trait modules only through an interface package: Base through BaseInterface, implicit in every trait module, and anything else through an interface that admits it, checked on the compiled code, or declares calls into it. It handles only values of trait-world types. Code from above reaches it only as values handed down: trait objects, through their projections, and functions bounded by `Callable`, which it calls at a declared signature without depending on their code. A package can pair a trait module with an ordinary module that uses both.
2. **Projection per trait, at the boundary.** A value enters the trait world once for each trait it is used under, where ordinary code calls in, through its type's projection for that trait. Inside, it is that trait's representation and nothing else.
3. **Bounds propagate to the boundary.** Inside the trait world, a trait object is passed to functions without a bound, which are compiled for it like any argument, and to a bounded argument only where its own trait is expected, or a supertrait whose declared representation map derives the other view. A function that uses a value under two traits, itself or through what it calls, declares both bounds at its boundary, so that the ordinary caller's one call projects each.
4. **Several bounds, several views.** An argument with several bounds is projected once per bound, and the views need not share a representation, unless the type declares one projection for several traits. Whether a change made through one view shows through another depends on whether both share the same data, as in plain Julia. A projection declares whether it shares the user's data or copies it, and a trait with mutating operations accepts only projections that share.
5. **One ownership rule.** A package may add a method to the trait world only where it owns the function, or one of the types, in every signature the method applies to; a `Union` with a foreign type is no way around this. Julia counts as one owner. Implementations and projections are methods too, so this is also the rule for who may implement a trait, and it applies to an implementation's own methods: an operation that is someone else's function, such as `Base.size`, is implemented for someone else's type only by an owner of one of them, while the trait's owner declares the existing methods instead. Ownership can be delegated by its owner, never claimed. A delegate is a package extension triggered only by packages its methods mention, so it is loaded whenever a call could use it.
6. **What a call sees.** A call in the trait world sees the packages that define its function and the representations involved, with their dependencies, Core, Base and the standard libraries of the system image always among them, and nothing else: its code is compiled against exactly their methods. For an implementation written in the session, the view is the trait package's view plus the implementation's own methods, not the session's imports; what is redefined at the prompt recompiles as today. At a dynamic site, the method selected at run time must be owned by a trait-world package that owns the function or one of the argument types (rule 5): a downstream trait module's method for its own type is accepted, a method from above or a pirate raises. With rules 1 and 5, loading a package can only add methods for its own functions and types, which no compiled code reaches, or pirate from outside the trait world, which is refused at the load.
7. **Where compiled code lives.** Compiled code for a combination of packages lives in a package that depends on all of them: the trait module for its own representations, a conformer for the representations it brings, a package extension or the application when packages meet only there, and the session when nothing depends on all of them.

Rule 3 in practice: a function that needs both views says so, and its caller passes one value.

```julia
summary(t::(ColTable, RowTable)) = (colmean(t, 1), firstrow(t))   # t carries one view per trait
```

Together, rules 1, 5 and 6 give the central guarantee: loading a package can never change what code in the trait world computes; it can only add code for new types, or be an error.

How common interactions between packages resolve:

| Situation | Decided by |
| --- | --- |
| Module B uses module A's trait; a user projects a type onto A's representation | rule 2: projected once; rule 7: B's image holds the code if B depends on A |
| Two traits from two modules in one function, `f(t::X, u::Y)` | rule 2: two representations, compiled per pair; rule 7: cached by a package that depends on both |
| One value used under different traits by different modules | rules 3 and 4: the caller projects one view per trait, or one for all if the type declares a joint projection |
| Two third parties want to implement trait X for a representation | rule 5: only X's owner or the representation's owner, or a delegate one of them names |
| A library keeps `f(m::AbstractMatrix)` beside a new `f(t::ColTable)` | dispatch: types first, then trait bounds |
| A user passes a closure to a trait module | rule 1: a `Callable` argument, called at its declared signature |
| An ordinary package pirates `Base.sum(::Vector{Int8})` | rule 6: the only way to affect code in the trait world; refused at the load (Sealing) |
| A trait module tries the same | rule 5: rejected when the module is built |
| Two trait modules export functions with the same name | no conflict: different functions in different modules |

### What code in a trait module may do

A trait object is a handle, not a value: code reaches the user's data only through the trait's operations, and a function from above only by calling it as a `Callable`. Every other value is an ordinary Julia value of a trait-world type.

The module's exported functions are its boundary: their trait-object arguments carry bounds, which say what an ordinary caller's value must conform to and what the entry projects. Internal functions need no bounds. A trait object passed to one is inferred like any other argument, and the function is compiled for it as part of the worker that calls it; helpers of an implementation take the representation itself, `r::R`; unexported types are ordinary trait-world types. The handle still admits only the trait's operations, so an internal use that the exported bounds do not cover is reported when the worker is built, at its line, with the bound to add, and a bound no path uses can be warned. Internal functions must infer concretely from the representations the bounds admit, which concrete mode checks through any number of layers; their code compiles with the worker, so rule 7 is unchanged. An exported function's argument without a bound takes trait-world values only, so a user type passed there runs as ordinary code (rule 1). Bounds on internal functions remain allowed, for dispatch and as documentation.

| In a trait module | Allowed | Why |
| --- | --- | --- |
| the trait's operations on a trait object: `col(t, i)`, `ncols(t)` | yes | the only way to reach the user's data |
| several trait objects in one function, of one trait or several | yes | compiled once per tuple of representations |
| an argument with several bounds, `t::(ColTable, RowTable)` | yes | one projection per bound (rule 4) |
| passing a trait object to the module's own functions, or on where its own trait is expected | yes | statically within the module, through the entry otherwise (rule 3) |
| methods with type annotations beside trait-bounded ones: `f(m::AbstractMatrix)`, `f(t::ColTable)` | yes | types first, then trait bounds |
| a function argument bounded by `Callable{Tuple{Float64}, Float64}` | yes | a declared call up, its result checked (rule 1) |
| any code on values of trait-world types: loops, arrays, closures, `try`, the module's other functions | yes | ordinary Julia, compiled per representation |
| importing and calling Base, a standard library or any package that an interface package admits | yes | checked on the compiled code: globals of trait-world types, no undeclared door; BaseInterface is implicit (Finer points) |
| methods of functions or for types the package owns, implementations and projections among them | yes | ownership (rule 5) |
| passing a trait object where a different trait is expected | no | declare both bounds, so the caller projects each (rule 3) |
| a trait object anywhere else, as a bare value: passed to an ordinary function, stored, returned, `typeof(t)`, `t.field` | no | code must not depend on the user's type |
| two methods with unrelated trait bounds on one position and no method for both | no | ambiguous for a type with both projections; checked when the function is defined |
| calling a package that stays outside, such as Makie | through an interface package | declared calls upward, handles for what comes back (Interface packages); an ordinary module of the same package can call both |
| calling a package that no interface package admits or declares | no | rule 1: add or write an interface package; the check says how thin it can be |
| a method whose function and types the package does not own | no | piracy, rejected when the module is built (rule 5) |
| outward doors: printing to `stdout`, logging macros, `display` | yes | dynamic calls upward with no inference edge; in a build, static calls to the application's declared sinks |
| inward doors: eval, invokelatest, deserialization, reflection, getglobal by name | only as a declared call with a checked result | a value denoting code from above has no admitting bound |
| arguments of open types from ordinary callers: `Any`, `Vector{Any}`, functions without a `Callable` bound | no | the same; such a call runs as ordinary code |
| loading a package that pirates a sealed package | no | refused at the load, naming the pirate (Sealing); the opt-out is plain Julia |
| abstract types, under concrete mode | no | opt-in: a warning or an error that names the root cause |

Implementations and dynamic operations follow the same rules. The prototype checks the rows that are not design: rule 3 and the escapes on the typed code of each worker signature, reported with their lines; ownership and imports when the module is defined; ambiguous bounds when it is complete; the rest at the first call of a signature, or while a package image is built. The door rows and the interface rows are design, and the sealed-load row is, on the prototype, a warning at the first call of a signature.

## How the concepts achieve the goals

### Interactivity: compiled once, reused everywhere

Cached code is reusable because it is compiled per representation, not per type, and it survives because of layering: only the packages it depends on can change it.

```julia
using Columns                                   # Columns' workers come from its package image
struct Mine; data::Vector{Vector{Float64}}; end
@implement ColTable Mine                        # conforms through its field: the projection is the only new code
colmean(Mine([[1.0, 2.0]]), 1)                  # runs the compiled worker
using CairoMakie                                # outside the trait world Columns depends on: changes none of its code
```

- **Per representation.** `Mine` shares its representation with every type that projects onto it, so `colmean` runs code that Columns compiled when it was built. On the prototype, implementing a projection for a new type costs 123–128 ms in a fresh session and its first calls 19 ms, most of it inference in the checks; the target is a few milliseconds.
- **Compiled against what it sees.** Each specialization is compiled against the methods of the packages it depends on only (rule 6), so inference, union splitting and return-type queries see nothing else. A later definition by one of those packages recompiles it. A definition elsewhere, for the definer's own types, can never apply. One that would apply is piracy, and the load that brings it is refused.
- **Every combination has an owner image.** The entry lives in the trait module's package image, the projection in the conformer's, and a worker at a new representation in the conformer's too; code for packages that meet only in an application lives in a package extension or the application, and the session comes last (rule 7). Each piece is compiled where it lives, because a downstream image cannot add native code to an upstream one.

Layering holds only if no value of an outside type leaks in. Dynamic dispatch from trait-bound code therefore checks that the selected method comes from what the call sees, and raises an error otherwise: a leak becomes an error, never a wrong result.

### Simple AOT: the reachable code is declared

Because of layering, a trait-bound program's calls stay inside the trait world, and dispatch over runtime types goes through projections, whose targets are listed. A build can therefore compile exactly what the program can reach.

```julia
function main(args::Vector{String})
    acc = 0.0
    for t in read_tables(args)        # element types chosen at run time
        acc += report(t)::Float64      # dispatch over the projections: finitely many targets
    end
    println(Core.stdout, acc)
end

verify_main(main, (Vector{String},); entrypoints = true)   # lists every target for juliac --trim
```

In plain Julia, a generic function called on a value of unknown type has no list of targets: it compiles at first use in a session, and fails a trimmed build, or crashes a binary built with the unsafe option. Here the list exists, and a function passed as a `Callable` argument adds one target at its declared signature. On the prototype, `verify_main` enumerates the entries' targets from the types the program can pass (here 2 builders and 6 workers), and the program compiles to a 2.09 MB trimmed executable; without the list, the binary dies at its first trait call.

### No performance cliffs

Four cliffs disappear by construction, and the fifth becomes a report at build time.

- **Loads cannot change speed.** The methods at an abstract call site change only with their owners (rule 6), so an unrelated load cannot push inference over `max_methods` and turn a fast call dynamic. Return-type queries fold at compile time.
- **Types cannot multiply compile cost.** Code compiles per representation, not per user type: a type that conforms by projection adds no compiled code, and a type that is its own representation compiles the library once for itself, by its own choice.
- **Nothing recompiles under you.** No unrelated load invalidates the trait world's cache. A compiled-call worker, which lives in the caller's image, and code redefined at the prompt recompile as today.
- **Trait operations cost nothing.** Implemented per representation, they are direct calls that inline: on the prototype, library code making one operation call per element ran at 1.00–1.01× plain Julia at 4096 elements, through a generic implementation at 1.00–1.03×. The entry adds a fixed cost, about 110 ns per call on the prototype, which is 2.8–3× at 16 elements and nothing at 4096. Only dynamic operations, and functions from above passed as dynamic calls, are indirect calls.
- **Abstract types in hot loops are found at their root cause.** Code in a trait module sees only representations, which are deeply concrete, and trait operation results, which are asserted to their declared types. An abstract value in a hot loop can therefore only come from the module's own code or the code it calls, and concrete mode traces it there, through any number of layers.

```julia
@warn_on_abstract @trait_module module CTop
using CBottom: Config                  # a trait module too (rule 1); Config has a field declared Real
using CMid2: factor                    # factor reaches that field through two packages

@trait Series{R} begin
    vals(r::R)::Vector{Float64}
end

function scaled_sum(t::Series, c::Config)
    s = 0.0
    for x in vals(t)
        s += x * factor(c)
    end
    s
end
end
```

On the prototype, with CBottom, CMid1 and CMid2 as trait modules too, this module prints while it is built:

```
Warning: @warn_on_abstract: `scaled_sum` at Series at Vector{Float64} uses abstract types on its normal path; 1 root cause:
  1. field `scale` of `CBottom.Config` is declared `Real` (CBottom.jl:8)
       3 uses, 2 in loops; first in a loop: CTop.jl:18  *(::Float64, ::Any)
       ← CMid2.factor(::CBottom.Config) returns Any (CTop.jl:18)
       ← dynamic call +(::Any, ::Int64) returns Any (CMid2.jl:6)
       ← CMid1.gain(::CBottom.Config) returns Any (CMid2.jl:6)
       ← dynamic call *(::Real, ::Int64) returns Any (CMid1.jl:6)
```

In this example that one field makes the loop 74× slower. `@error_on_abstract` turns the warning into an error, and `check_concrete` gives the same report in tests.

### Identical or error: piracy outlawed where traits are in effect

Under layering, a load can affect code in the trait world only through a method from outside what that code sees which would change it (rule 6): piracy. Loading a trait package seals it, and loading an interface package seals what it wraps, Base included through BaseInterface. A load that seals checks what is already loaded as well as what comes later: a pirate of a sealed package is a conflict whichever side loaded first, refused in strict mode and tolerated with a warning and a recompile otherwise, so no call sees a pirate that was not tolerated, and no call errors on one. The opt-out restores plain Julia.

```julia
using MyTable                         # projects MyTab; Stats' worker calls weight(::Float32); Stats and Base are sealed
using Pirate                          # defines Stats.weight(::Float32), owning neither: refused, naming the method and Stats
tolerate!(:Pirate)                    # opt out for this session (a sketch): plain Julia, the pirate applies
using Pirate                          # loads; Stats' worker for Float32 recompiles against it, with a warning
colsum(MyTab(Float32[1, 2, 3]))       # what plain Julia computes
```

- **Refuse at the load, never at a call.** The place of refusal is where methods enter the table: for a package image, before any of its methods is inserted, so that a refused package is absent rather than half loaded, which needs a transactional image load (trade-off 8); for code evaluated later, at the definition; for a seal that arrives after the pirate, at the seal's load, naming the pirate. A refusal at the pirate's precompile is an early warning only, since a compile cache made in another environment is reused. The method table itself stays plain Julia's. An earlier version of this note kept the pirate and poisoned the affected code to raise at the call, which fails late; making the pirate invisible inside the trait world was rejected twice, because one method with two versions disagrees silently across the worlds.
- **Owners keep their freedom.** Adding methods for your own types to any function, implementing traits for your own types and redefining your own code all work as today. Julia counts as one owner, and an owner can delegate, for example to a package extension that implements its trait (rule 5).
- **The opt-out is plain Julia.** A pirate that is tolerated, declared by an interface package for the tree it wraps or accepted per package in a project, recompiles the signatures it touches against it, with a warning; the two worlds always agree, and the guarantees hold for everything it does not reach. The interim is this with everything tolerated: warn and recompile by default, refusal as the strict mode, until the ecosystem passes, which Aqua's piracy check already pushes it towards. On stock Julia the prototype runs the check with warnings.
- **Two exceptions.** Element types that Julia derives from inference, such as that of `map` over an empty collection, are answered within the trait world, and can differ from plain Julia's where Julia documents them as inference-dependent. An open `Callable` result type, inferred at the boundary in ordinary code, depends on what is loaded there; it is part of the worker's key and checked at every call, and concrete mode reports it when it infers to `Any`.

## Working with existing Julia

Base, the standard libraries and most packages were written without traits, and a library that adopts them already has callers, type-based methods and higher-order functions. Five mechanisms let trait modules use existing code as it is, and let a library adopt traits one function at a time without changing what existing calls do. How Base itself is in the trait world, and how a package like Makie is reached through an interface package, are under "Finer points".

### Traits over existing functions

A trait's operations may be existing generic functions. Capability traits then state Base's informal interfaces as contracts, without rewriting Base:

```julia
@trait Indexable{R} begin                          # the operations are Base's own functions
    Base.length(r::R)::Int
    Base.getindex(r::R, i::Int)::eltype(R)
end

@implement Indexable{A} where {A <: AbstractVector}   # no body: Base's methods, checked when declared
```

Conformance is declared, never derived from the methods that happen to exist. Derivation would be unsound three ways: Base's fallbacks exist and throw (`getindex` has a method for every `AbstractArray`, and `IteratorSize` answers `HasLength()` for every type); types conform by accident (a `Number` iterates and indexes, a `String` indexes by byte); and whether a call infers changes with what is loaded. A declaration for a family through one of Base's abstract types takes Base's documented interface at its word instead: a subtype that breaks the `AbstractArray` contract throws in both worlds, as "identical or error" requires, and concrete mode reports it when the package is built. By rule 5 such declarations come from the trait's owner or from Julia, so a small library of capability traits, such as `Iterable`, `Indexable` and `HasLength`, with conformances for Base's families, is all it takes. Trait-bound code still calls Base directly. Inference confirms such a declaration only at concrete argument types, and misses a fallback that throws on some paths only; every call asserts its result, so "identical or error" holds regardless.

### Generic implementations

A trait may provide default operations, written in terms of the others, which an implementation can override. An implementation may cover a family of representations, or every representation that implements other traits. Workers are still compiled per concrete representation, so calls stay static.

```julia
@trait ColTable{R} begin
    ncols(r::R)::Int
    col(r::R, i::Int)::Vector{Float64}
    firstcol(r::R)::Vector{Float64} = col(r, 1)       # a default
end

# every Indexable representation whose elements are Vector{Float64} (a sketch of the syntax)
@implement ColTable{R} where {R: Indexable, eltype(R) == Vector{Float64}} begin
    ncols(r) = length(r)
    col(r, i) = r[i]
end
```

With this, `Vector{Vector{Float64}}` is a `ColTable` because it is `Indexable`, and so is any representation a user implements `Indexable` for: ColTable follows from the capability traits, through declarations. A more specific implementation beats a generic one, and the overlap is checked when the specific one is defined: its package depends on the trait's package, so it sees every generic implementation. Layering gives the check its order. Two generic implementations that overlap without one being more specific are rejected. A default never throws "not implemented": a missing operation is an error when the implementation is declared, not when it is called.

### Several traits, one projection

A representation can implement several traits, and a type can be projected once for several of them:

```julia
@implement (ColTable, RowTable) Measurements     # one projection for both: the field data, or project(t) = … written out
```

A function bounded by both then receives one value: one projection instead of two, views that share data by construction, workers compiled per representation instead of per pair, and a static call when the value is passed on to a function with either bound. Rule 4 remains the general case for types projected separately. On the library side, a bundle trait names a combination, `@trait Table{R} <: (ColTable{R}, RowTable{R})`, so that `summary(t::Table)` needs one bound.

### Dispatch: types first, then traits

A library that adopts traits keeps its type-based methods. A trait bound ranks above `Any` and below every type:

```julia
describe(v::Vector{Float64}) = …     # as today
describe(m::AbstractMatrix) = …      # as today
describe(t::ColTable) = …            # new: every other type with a ColTable projection
describe(x) = …                      # the old fallback, for everything else
```

Adding the trait method changes only calls that used to reach the fallback or raise a `MethodError`, so a library can adopt traits one function at a time and every existing call keeps its meaning: a value without a projection reaches the most specific ordinary method that applies, of whatever shape. Among trait bounds, a subtrait beats its supertrait and more bounds beat fewer. Two methods with unrelated bounds on one position, such as `f(t::ColTable)` and `f(t::RowTable)`, need a method for both, `f(t::(ColTable, RowTable))`, checked when the function is defined: the check needs only the function's own methods, so no later load can create an ambiguity. The entry sits at `Any` in Julia's method table and chooses among the bounds from the registered projections, which folds for a known type, so caching and AOT are unchanged. A value of a user type that reaches a type-annotated method, such as a user's subtype of `AbstractMatrix`, is not projected: that call runs as ordinary code, with today's semantics and today's speed.

### Function arguments: Callable

Julia has no type for "a function from `Float64` to `Float64`": `Function` says nothing about arguments or results, and a closure's type belongs to the code that creates it, above the trait world. A function handed down from ordinary code is therefore a call upward. The built-in trait `Callable{A, S}` makes it a declared one: arguments of the tuple type `A`, and a result of type `S`, a `Tuple` when there are several.

```julia
@trait_module module Stats
using Columns
export colmap, colsum

# the default, a dynamic call: the worker compiled once per signature, an indirect call per element
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))

# the library's default is a compiled call: a worker per function type, a direct call the compiler may inline
colsum(f::Callable{Tuple{Float64}, Float64, CompiledCall}, t::ColTable, i::Int) = sum(f, col(t, i))
end

colmap(x -> 2x, Measurements([[1.0, 2.0]]), 1)                 # [2.0, 4.0], a dynamic call: the library's default
colmap(compiled_call(x -> 2x), Measurements([[1.0, 2.0]]), 1)  # the caller overrides: a worker compiled for this closure
colsum(dynamic_call(x -> 2x), Measurements([[1.0, 2.0]]), 1)   # the caller overrides the other way
colsum(abs2, Measurements([[1.0, 2.0]]), 1)                    # 5.0: abs2 is Base's, a compiled call whatever the default
```

- **Anything callable conforms:** closures, callable structs, generic functions. `Callable` is the one trait whose conformance is not declared, and that is sound because its only operation is checked at every call: the arguments have the declared types, and a result of another type is an error where plain Julia would widen. A function without a method for `A` raises a `MethodError` when called, as in plain Julia.
- **The library sets a default, the caller decides.** `Callable{A, S, M}` carries the mode `M`. `DynamicCall`, the default, makes the function a pointer to its code compiled for `A` in ordinary code at the call site: the worker is compiled once per signature, in the trait module's image, and each call through the pointer is indirect. `CompiledCall` compiles the worker per function type instead, with the function's body inferred into it, as ordinary code in the caller's image (rule 7), a direct call the compiler may inline: plain Julia's speed and plain Julia's invalidation for that piece. Such a worker is the library's code compiled outside the library's cache, so a library that makes `CompiledCall` the default of a function gives up goal 1 for that function by choice, which is why the system default is `DynamicCall`. A bound without the parameter accepts either mode and supplies the default. The caller overrides per value with `compiled_call(f)` or `dynamic_call(f)`, wrappers whose type fixes the mode and which the entry strips; the long form, `Callable{Tuple{Float64}, Float64, DynamicCall}(f)`, also fixes the signature, as FunctionWrappers does today. The value's type wins because the library's cache has no stake either way; its users do, which is what the default is for. Concrete mode reports a dynamic call inside a loop and names the caller's fix.
- **Layering holds for the trait world's cache either way.** No cached worker imports, infers into or compiles the code above: a dynamic call goes through its pointer, and a compiled call's worker, which does infer into the function, is ordinary code that lives with the caller, outside the cache and outside rule 6's view.
- **An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in ordinary code, becomes part of the worker's key, and is checked at every call.
- **Functions from the trait world are always compiled calls.** Base's `abs2`, a trait module's own functions and closures created inside a trait module are trait-world values: whatever the default, the worker is compiled for them and calls them directly within the trait world, cached by rule 7. `map`, `filter` and `sum(f, …)` work inside the trait world as today.
- **AOT.** A `Callable` argument names its signature, so a build compiles each function passed at it, and `verify_main` lists them as targets.

A function called at two signatures carries two bounds, `f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int})`, one translation per signature, as rule 4 allows for any value. Keyword arguments, varargs and functions that return functions are under "Finer points" below. The cost of a dynamic call is about 4 ns per call on the prototype.

## Finer points

One principle runs through this section; it is rules 1 and 2 read operationally. Only values cross the boundary, each where a bound stands, and the bound says how the value is translated. Code never crosses into the trait world's cache: no cached worker is compiled against code from above, and a compiled call's worker is compiled above, outside that cache. There is no bound for the way up, so what goes up goes as itself.

- **A bound is a translation.** A trait bound projects; a declared type asserts; a `Callable` bound makes a function a dynamic call, a pointer at a declared signature, or a compiled call, a worker compiled above on the function's type, as the mode in the bound or on the value says; no bound means a trait-world value. The translation is the same wherever the bound stands: a positional argument, a keyword, an element of a vararg, the result of a call upward.
- **Everything in a call that is not a value stays inside.** Defaults, keyword sorting, splatting and dispatch are plain Julia, run in the worker after translation. The entry translates and does nothing else.
- **A bound is a crossing point and has an entry,** on a named function or a closure alike. That is what exported has meant so far.

The subsections below apply it: the forms of conformance, parametric types, keyword, default and variable arguments, functions that cross, Base and the standard libraries, interface packages, and sealing.

### How a type conforms to a trait

The one-line form covers a type that holds a representation or is one. The written-out forms name the projection, give a type operations of its own at a shared representation, join several traits, or implement a trait for a representation the author does not own. Every form defines methods, so rule 5 says who may write it, and the methods are trait-bound code wherever they are written. The prototype runs forms 3 to 7; forms 1 and 2 are design.

```julia
# 1. A field, inferred: the projection is t.data, or the one field whose type conforms
struct Measurements; data::Vector{Vector{Float64}}; end
@implement ColTable Measurements

# 2. Methods, inferred: the type is its own representation
import Columns: ncols, col
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp

# 3. A projection written out: when two fields conform, when the representation is computed,
#    or when it must be copied
struct Halves; left::Vector{Vector{Float64}}; right::Vector{Vector{Float64}}; end
@implement ColTable Halves project(t) = t.left
struct Window; v::Vector{Float64}; lo::Int; hi::Int; end
@implement ColTable Window copies project(t) = [t.v[t.lo:t.hi]]   # refused by a trait with mutating operations (rule 4)

# 4. The operations in one block: for the author's own type, the same as 2; for a representation
#    the author does not own, only the trait's owner or a delegate it names (rule 5)
@implement ColTable{Ramp} begin
    ncols(r) = r.n
    col(r, i) = r.base .* i
end
@implement ColTable{Matrix{Float64}} begin      # in Columns, or in an extension Columns names
    ncols(r) = size(r, 2)
    col(r, i) = r[:, i]
end

# 5. One projection for several traits, inferred or written out; a bundle trait names the
#    combination on the library side
struct Grid; data::Matrix{Float64}; end         # Matrix{Float64} implements ColTable and RowTable
@implement (ColTable, RowTable) Grid
@implement Table Grid

# 6. Operations of the type's own at a shared representation: the library's compiled worker,
#    calling these operations indirectly
struct Reversed; data::Vector{Vector{Float64}}; end
@implement ColTable Reversed dynamic begin
    project(t) = t.data
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
end

# 7. Existing methods declared for a family, by the trait's owner or Julia: no body
@implement Indexable{A} where {A <: AbstractVector}
```

Form 4 may be generic over a family of representations (Generic implementations, above). What each form compiles:

| Form | Compiled anew | Operation calls |
| --- | --- | --- |
| a field or a written projection (1, 3, 5) | the projection | static, the representation's implementation |
| an own representation (2, 4) | the library's functions, once for the type | static, inlined |
| dynamic operations (6) | the type's own operations, as pointers | indirect, 7× plain Julia per element on the prototype |
| a family declaration (7) | nothing | the existing methods, static |

Every check runs at the declaration, never at a call:

- ownership: the author owns the type or the trait, or is a delegate one of them names (rule 5);
- the representation is deeply concrete: the field's type, the projection's result, or the type itself. A field declared `AbstractVector` is refused with the field named; the fix is a concrete field, or a projection that materializes;
- every operation has a method or a default, with the declared result types;
- the methods' code stays in the trait world (rule 1);
- methods win over a field when a type has both, so writing operations is always deliberate; several conforming fields need the name `data`, or a written projection.

### Parametric user types

A parametric type conforms as a family, declared with `where` as Base's families are in form 7, or per instantiation. On a parametric type the one-line form means the whole family.

```julia
struct Series{T}; data::Vector{Vector{T}}; end
@implement ColTable Series{Float64}                 # one instantiation
@implement ColTable Series{T} where {T <: Real}     # a family: refused here, Columns implements Vector{Vector{Float64}} only; the message names Series{Float64}
@implement ColTable Series                          # the whole family, Series{T} where {T}: the same check
```

The ownership and method checks run at the declaration, for the family as a whole:

- **A field:** the family of field types must be covered by one implementation's or projection's family, which subtyping decides. A generic implementation's predicate must be decidable on the family's structure, else the declaration is refused.
- **Methods:** the operations' methods must cover the family, with results that infer to the declared types at the family's signature, where results the trait declares in terms of `R` are evaluated at the family.
- **Concreteness:** field types may depend on the parameters but are abstract in no other way, so every instantiation with concrete parameters is a concrete representation. An instantiation with an abstract parameter, `Series{Real}`, is refused at the entry by its type, as a type without a projection is: one check on the type, folded per signature.
- **A refusal names the instantiations that would conform.**

Workers compile per instantiation, as per representation always, and `verify_main` enumerates the instantiations a program passes. Conformance is never derived at a call from what happens to exist then; the entry's one check is on the type.

### Keyword, default and variable arguments

Keyword, default and variable arguments work as in plain Julia, with one placement rule: a default is trait-world code, evaluated in the worker after projection, never at the entry. The prototype does not run keyword or optional arguments in trait-bounded functions yet.

```julia
@trait_module module Columns
export colmean, colzscore

colmean(t::ColTable, i::Int = 1) = sum(col(t, i)) / length(col(t, i))   # two exported methods: colmean(t) calls colmean(t, 1) inside

# a bounded keyword that defaults to a trait object the worker holds, and a typed keyword with a constant default
colzscore(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colstd(baseline, i), tol)
end

colzscore(m, 1)                     # one worker: baseline is t, tol is eps(), both filled inside
colzscore(m, 1; baseline = r)       # r is projected for ColTable at the entry, as a positional argument would be
colzscore(m, 1; tol = 1)            # an error at the entry: tol is declared Float64, as in plain Julia
```

- **Defaults are evaluated inside.** Plain Julia evaluates a default in the method's scope, with the earlier arguments at hand, and so does the trait world: in the worker, after projection, so `baseline = t` sees the trait object and `i = ncols(t)` may call an operation. A positional default is what Julia makes of it, a shorter exported method whose body calls the full one with its own trait object (rule 3). Evaluating defaults at the entry instead would run trait-world code in ordinary code, on the user's value rather than its projection.
- **The entry projects, the worker sorts.** The entry point projects every bounded argument, positional or keyword, and passes the supplied keywords on as a named tuple; the worker fills the defaults and calls the body. The sorter is compiled per set of supplied keywords, by name and type, and the body once per full signature, as Julia does it, so an omitted keyword costs nothing and a constant default folds.
- **A keyword is typed like a positional argument:** by a trait bound, a declared type, or the value supplied. A declared type is asserted at the entry, as plain Julia asserts keyword types; a trait bound projects, and a value whose type does not conform is refused at the entry, as in a positional position. A bounded keyword without a default is required, as in plain Julia.
- **No dispatch on keywords,** as in plain Julia. A trait bound on a keyword chooses no method; it projects and restricts, so the dispatch rules above need no amendment, and the ambiguity of two unrelated bounds cannot arise through a keyword.
- **A default for a bounded parameter** is trait-world code whose value is either a trait object of that trait, passed on by rule 3, or a value of a representation the trait is implemented for, taken in without projection. Its type is inferred when the worker is compiled, with the other concreteness checks; a default of another type is an error there, not at a call.
- **Functions from above with keywords.** `Callable{A, S, M, K}` names them in a fourth parameter, a named tuple type: `Callable{Tuple{Float64}, Float64, DynamicCall, @NamedTuple{tol::Float64}}`, with no keywords when `K` is absent. The boundary checks that the function accepts those keywords, which `hasmethod` can, though a method taking `kw...` accepts any name, so the check is only as strong as the declaration; the result is inferred at that call, and inside, the trait world calls it with exactly those keywords.
- **AOT.** Each set of supplied keywords is a signature, so `verify_main` lists the sets a program passes, and a trimmed build compiles them.
- **Varargs.** A vararg is several crossing points with one bound, read per element as plain Julia reads `xs::Int...`. Each element is translated, and a vararg of trait objects is several trait objects in one function, compiled per tuple of representations, which `verify_main` enumerates. A vararg without a bound takes trait-world values only. Concrete mode reports Julia's widening of long tuples.

### Functions that cross the boundary

A function is code, and code never crosses. A function from above enters only as a `Callable`: a dynamic call through a pointer at a declared signature, or a compiled call, a worker compiled above for its type (Function arguments, above). The remaining cases follow from the direction of the crossing.

```julia
colfun(t::ColTable, i::Int) = x -> x * colmean(t, i)      # returned up: a trait-world closure, called from above on Float64
scaler(t::ColTable) = (u::ColTable) -> meandiff(t, u, 1)   # a bounded closure: it has an entry, so the caller passes its own objects
colmaker(f::Callable{Tuple{Int}, Callable{Tuple{Float64}, Float64}}, t::ColTable)   # a function from above that returns a function
tables(f::Callable{Tuple{Int}, ColTable}, n::Int)          # a function from above that returns tables: each result projected
```

- **Functions returned up** are trait-world values and go up as themselves. Called from above on trait-world values, a closure is ordinary code using the trait world, as a call to `sum` is, and it keeps the trait objects it captured, already projected. To take the caller's own objects it needs a bound in its signature, and a bounded signature has an entry, named or not. An unbounded closure called with a value from above is no trait-world call: it runs as plain Julia, and concrete mode refuses it, as the table's row on open types says.
- **Results of a function from above** are values crossing downward, so the result bound translates them as an argument's bound would. A result bound that is a `Callable` yields a dynamic call, a pointer at the inner signature taken at every call, or a compiled call, with the function type inferred at the boundary as an open result type is; the function from above overrides by returning `compiled_call(g)` or `dynamic_call(g)`. A result bound that is a trait projects every result, with the representation inferred at the boundary as an open result type is, part of the worker's key and checked per call.
- **Trait objects never go up,** neither returned nor passed to a function from above: the way up has no bound, and a projected value has no self above. What goes up is what operations return, trait-world values.
- **AOT.** A returned closure is a trait-world type, so calls to it from ordinary code are calls into the trait world that `verify_main` lists, and a `Callable` result's signatures are build targets like any `Callable`.

### Base and the standard libraries

Base is in the trait world wholesale, and so is what an interface package admits of any other package: membership is a property of compiled code, declared by an interface and validated by the check, not a property of a package's name. Base's source handles any value, so it is not trait-world code. A specialization of a Base method at trait-world types, reached from a worker, is trait-world code when it passes the check below. Julia's package images already hold such specializations; the design adds that nothing above can invalidate them.

A value without parts, a `Float32`, a `String`, is a trait-world value wherever it was made. A value with parts is one when all its parts are, and the check accepts a value when its type decides that: `Vector{Float64}` does, `Vector{Any}` does not. A specialization's values come from four places, and each is closed:

- **Arguments** are translated by their bound at the entry, or admitted as trait-world values. A type that decides, deeply concrete, is admitted by its type; a type that does not decide, a field declared `Real`, a `Vector{Any}`, has its abstract parts walked by the entry, at a cost proportional to them, and concrete mode reports such an argument type. Representations must decide by their type (rule 4).
- **Globals** it reads must have a trait-world type: a constant or typed binding, deeply concrete. `ENV` passes; `stdout`, the logger's state and `Main` do not.
- **Constructors** make values from parts and add nothing to check.
- **Calls** return values of specializations checked the same way, Base's and any package's, transitively, on static paths. A dynamic site inside selects at run time, and the dispatch check of rule 6 admits only a method owned by a trait-world package that owns the function or an argument type, so the target is Base's, an owner's, or a refusal; the target's specialization is checked when it compiles, which a build enumerates and a session reaches at the first call.

What remains are the doors, Base's functions that make values from non-values, and they have a direction. Outward doors send trait-world values up and return nothing: logging, `display`, printing to `stdout`. They are calls upward with no inference edge, allowed, reported by concrete mode as dynamic calls, and nailed to the application's declared sinks in a build. Inward doors bring values in: `eval`, `invokelatest`, deserialization, reflection over the method table, `getglobal` on a module, task storage, raw memory. They are allowed only as declared calls with a checked result, and since no bound admits a value denoting code from above, a `Module`, a `Type`, a `Method`, a bare function, reflection and `eval` as sources of values stay out on their own. The door list lives in BaseInterface, the interface package to Base that is implicit in every trait module, and it is the only curated thing here; the rest is structural. A Base function that reaches a door at some specialization falls out there: on a static path when the worker is compiled, behind a dynamic site when the target compiles, which a build enumerates and a session reaches at the first call; the finding names the worker and the line, and concrete mode reports the dynamic sites, so a module that claims the closure runs with it on. `print(io, x)` on an `IOBuffer` is in, `rand()` is in, `task_local_storage()` is out, and `print(x)` is a dynamic call.

Base qualifies although it was written without traits because Core, Base and the standard libraries of one Julia version depend only on each other and ship together, so rule 1 holds by construction and rule 5 by designation, with Julia as one owner; the standard libraries of the system image are in every view, so LinearAlgebra's methods on Base's functions are seen everywhere, and a standard library upgraded from the registry is a package with an interface of its own. `Main`, the REPL and Pkg are ordinary code. The same check admits a solver's numerics at concrete types and finds the doors of a plotting system everywhere, which is the right answer for both. BaseInterface also carries the traits over Base's informal interfaces, `Indexable` over `getindex` with its conformances for Base's families, so the curation the note asks for has an owner. Each standard library has an interface of its own, so a trait package seals only what it uses: most admit their code by the check, LinearAlgebra, Random, Dates, Statistics; those with inward doors offer declared calls with checked results, Distributed's `remotecall_fetch(f, …)::Vector{Float64}`, whose deserialized result is checked at the boundary and is then a trait-world value whatever its origin, and Serialization's `deserialize`; Logging is the home of the outward sinks. The prototype's layering check walks the typed code of each worker and reports a call into a package the module never imported, but it stops at Base and trusts it wholesale; the global check and the door list are design.

### Interface packages

An interface package gives trait-world code a surface to something that is not a trait module: Base, a standard library, a solver, Makie. It is a category of its own, beside trait packages and ordinary packages, and the only way a trait module reaches non-trait code. It admits what passes the check, by the check, and declares the rest: its author runs the check on the wrapped package at the interface's build and learns how thin the interface can be. For a solver most of `solve` passes, and the interface is traits over problem types and little else. For Makie nothing reachable from `plot` passes, so the interface is all declared calls and handles. Such an interface has two halves. The trait half is a trait module: traits for what the outside needs from data, bounded functions, conformances, and handles for values from outside that must come back; a handle is the mirror image of a trait object, no operations, only a value to hand to the next declared call, never inspected. The ordinary half holds the declared calls: ordinary code that calls the outside package, reads and writes its globals, and returns a trait-world value, a handle, or nothing. From a worker a declared call is a dynamic call upward with no inference edge and a result checked against its declaration, so the worker's cache cannot depend on anything behind it. Anyone may write an interface package, since admitting, declaring, sealing and tolerating add no methods and never touch rule 5; two interfaces to one package do not conflict, their surfaces being different traits with different owners and their tolerance lists unioned at load. A package may ship an interface module for its own ordinary dependencies, which is the answer for a trait package with twenty of them.

```julia
module MakieInterface                   # an interface package to Makie; the syntax is a sketch
using Makie
@trait_module module Plots
    export figure, scatter!, show
    @trait PointSeries{R}
        xs(r::R)::Vector{Float64}
        ys(r::R)::Vector{Float64}
    end
    @handle Figure                                            # a value from Makie, opaque inside
    figure() = @call Makie.Figure()::Figure                    # declared calls: no inference into Makie
    scatter!(f::Figure, t::PointSeries) = @call Makie.scatter!(f, xs(t), ys(t))::Nothing
    show(f::Figure) = @call Makie.display(f)::Nothing          # Makie's globals live behind the call
end
end
```

- **Globals become declared calls.** Trait-world code never reads a Makie global: the current figure is a call returning a handle, the theme a call taking trait-world values and returning nothing, `display` a call returning nothing. The package also fixes the trait-world spelling of Makie's concepts, colors as tuples, markers as symbols, attributes as named tuples.
- **Compiled code lives where rule 7 puts it.** The trait half's workers are in the package's trait-world cache, whose view the check keeps clear of Makie, reached only through declared calls. Makie's code at the declared signatures is ordinary code: in Makie's image for what Makie precompiles, otherwise in this package's, whose precompile workload is exactly the declared signatures, so time to first plot from a trait module equals an ordinary module's. Redefining a Makie method invalidates that cache as today and nothing in the trait world; the pointer is refreshed by world age at the next call. In a build the declared calls are targets compiled as ordinary code, and whether Makie trims is Makie's problem.
- **The package reviews the tree it wraps.** It declares the pirates in Makie's dependencies it tolerates, in its project file, read before its dependencies load (Sealing, below), so that loading it is an explicit, reviewed acceptance rather than every user's private one, and the place from which to push the fix upstream.

### Sealing

Sealing has two sources. Loading a trait package seals the package itself, so nobody pirates `Columns` at its types. Loading an interface package seals what it wraps, its dependency closure, both halves, and BaseInterface, implicit in every trait module, seals Base and Core. From then on a definition that would pirate a sealed package is refused: a method on a function and types all owned by sealed packages, by a package that owns none of them and is no delegate (rule 5). `Base.convert` for Base's types from anywhere but Base is one; a method on Makie's functions at Makie's types from anywhere but Makie is another. Owners keep their freedom: adding methods for your own types and redefining your own code stay as today and recompile what depends on them (rule 6). Sealing enforces ownership over what an interface reaches; it freezes nothing.

- **When.** Where methods enter the table: for a package image, before any of its methods is inserted, so the refused package is absent, which needs the transactional load of trade-off 8; for code evaluated later, at the definition; for a seal that arrives after the pirate, at the seal's load. The error names the pirate, the method and the owner it would need. A refusal at the pirate's precompile is an early warning only, because a compile cache made in another environment is reused. An interface package's own load checks the tree it seals and the session as it stands, and a pirate that it does not declare as tolerated fails that load in strict mode.
- **What you get.** In a session whose packages are interface packages and their closures, nothing pirates anything, in whichever order they load: every cache stays valid, every worker runs against what it was compiled for, and a build sees the whole world. BaseInterface is implicit in every trait module, so Base is sealed in any session that uses traits at all, and the sealed region is what the project file says: its trait packages and the interface packages they load.
- **The opt-out is plain Julia,** as under "Identical or error": a tolerated pirate recompiles the signatures it touches against it, with a warning, so the two worlds always agree. The interim is everything tolerated.

## Trade-offs

The design restricts what trait-bound code may do, and only there. Its most important costs:

1. **Calls out go through interface packages.** Code in a trait module reaches ordinary code such as Makie only through declared calls, with handles for what comes back, which an interface package to Makie provides once for everyone (Finer points). A package whose work is state and effects, which is what a plotting system is, is reached that way and never run inside. Adoption is no longer bottom-up: a trait module may use any package through an interface package, which anyone can write and the check tells how thin it can be; only offering traits needs a trait module.
2. **A stranger's piracy refuses a load.** Once a sealed package is loaded, loading a pirate fails, naming it. The error reaches whoever loads the pirate, not its author, and the opt-out is plain Julia for the signatures it touches. This is the most contested part.
3. **Values crossing in must be closed.** Arguments from ordinary code must be trait objects, `Callable` functions, or concretely typed values of trait-world types. Base's outward doors, `stdout`, the logger and `display`, are dynamic calls upward; its inward doors, `eval`, deserialization and reflection, are available only as declared calls with a checked result.
4. **Trait objects go in, not out.** Code in a trait module never sees the user's type, so it cannot build a new value of it: a function that returns "a table like the input" needs a constructor operation declared in the trait, an inverse of the projection. A value used under two traits is projected twice unless its type declares one projection for both, and whether a change through one view shows through the other depends on whether the projections share data (rule 4).
5. **Types come first.** A type that matches a type-annotated method takes it, even when it also has a projection for a trait-bounded method of the same function: a user's subtype of `AbstractMatrix` then runs as ordinary code. Reaching the trait method needs a type that no type method catches, or a newtype.
6. **Conformance to Base's interfaces is curated.** Capability traits and their conformances for Base's families are declared by hand, and a type nobody declared does not conform, even when it has the methods.
7. **Dynamic operations and dynamic calls are indirect.** A type whose own operations run at a shared representation, instead of being its own representation, pays an indirect call per use: on the prototype 6.3 ns, 7× plain Julia for a per-element operation. A function from above passed as a dynamic call is an indirect call too, about 4 ns; the library sets the default and the caller may override it per value. Implementations for a Base-typed representation can come only from the trait's owner or a delegate it names. Representations must be deeply concrete, so views get materialized.
8. **Runtime work, not yet proven.** Trait-bound code needs its own compiled instances, so Base code used by both worlds compiles twice, plus an invalidation filter, a dispatch check, a hook on method insertion that refuses a pirate before an image's methods enter the table, and the check of globals and doors on compiled code. None of this exists yet, and whether layering accounts for all load-time invalidation is not yet measured.
9. **Smaller restrictions.** Offering traits is per module and bottom-up: a package converts its own modules one at a time, from the bottom of its dependencies up, while using ordinary packages through interfaces is not. One semantic exception (inference-dependent element types), and the ownership rule's orphan case: implementing a foreign trait for a foreign type needs one of their owners, a delegate or a newtype.

## Possible extensions

### Smaller extensions

- **Constructor operations.** A trait may declare how to build a value of the user's type from a representation, so trait modules can return values like their inputs.
- **Representation maps for supertraits.** `@trait B <: A` is already relied on by rule 3, by dispatch and by bundle traits; open is the syntax of the map by which B's operations call A's statically.
- **Inline entries.** Callers that already know the type inline the projection lookup and call the worker directly.
- **Concrete mode by default.** Warnings for every worker, so the cliff is caught before anyone opts in.

## Other options considered

- **Region blocks inside ordinary modules:** the first prototype's `@region`. Replaced by trait modules, because every rule of the design applies per module, and a block over one trait cannot declare the traits of several arguments.
- **One representation per type:** each type projects once, for every trait it joins. Rejected as too restrictive: what a type means differs between traits, so rule 4 keeps one view per bound.
- **A closed trait world stated per module:** each trait module checked against its own imports. Replaced by layering, a property of the dependency graph that also says where compiled code lives.
- **Making outside definitions invisible inside trait-bound code,** called sealed resolution in an earlier version: rejected because the same call would have two answers, and rejected again on 2026-10-14 as an immune trait world, because one method with two versions disagrees silently across the worlds through `hash`, `isless` or `convert` on values that cross. Sealing now names something else: the enforcement of ownership over what an interface package reaches.
- **The edge-level rule:** let trait-bound code call ordinary packages freely, but compile only concrete calls against the current methods and make abstract ones dynamic. Rejected for its built-in cliff at abstract calls, copies of much library code, and no closed world for AOT.
- **Absorbing dependencies:** each package brings its ordinary dependencies into its own world. Rejected because two packages that absorb Makie conflict as soon as one defines a recipe.
- **A trait layer for all of Base:** wrap Base in traits before anything works. Unnecessary once Base joins the trait world by designation; capability traits cover only the interfaces that conformance needs.
- **Deriving conformance from the methods that exist:** a type is `Indexable` if `length` and `getindex` have methods for it. Rejected: Base's fallbacks exist and throw, types conform by accident, and whether a call infers changes with what is loaded.
- **Trait bounds that compete with types:** trait-bounded methods ranked like abstract types, with ambiguities found where a type with a projection meets a type method. Rejected because the conflict would surface only in an application that loads both packages.
- **Explicit wrapping at the call:** `f(ColTable(x))`, with trait objects as nominal types. Rejected because adopting traits would change every caller.
- **Function types in the type system:** arrow types such as `Float64 -> Float64`. A far larger change to Julia than one trait whose only operation is checked at every call.
- **Better invalidation precision:** invalidate only code whose dispatch really changes. Largely upstream in Julia 1.12 already, and not enough on its own.
- **A global invalidation filter:** ignore later definitions everywhere. Unsound for ordinary code.
- **Linked representations per module:** `@trait_module Table{R} with ColTable{R}, RowTable{R}`, one representation for every function in a module. Rejected: a bundle trait links per function already, and a type links by one field whose type implements both; a module-wide link would make every function require conformance to both, which loses adoption one trait at a time, and a module generic over one representation cannot express a function over two, such as `meandiff(a::ColTable, b::ColTable)`.
- **Poisoning pirated code at the call,** an earlier version of this note: the affected worker kept its code and raised when called. Rejected because it fails late and the retained code can never run; refusing at the load fails first.
- **An allowlist of trait-compatible Base:** rejected; Base's functions call each other, so the list would be transitive and per version. The check on compiled code with a door list is automatic and follows each version by itself.

Measurements, proof-of-concept results, the detailed tables (caching, ownership, open issues, staging) and the full comparison of these options are in `writeup/design-findings.md` in the repository; the prototype of this design, TraitWorld, is described with all its results in `poc/world/README.md`.
