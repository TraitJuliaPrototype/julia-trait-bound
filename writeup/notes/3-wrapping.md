# Traits for better Julia: code written without traits

> **Status (2026-10-16, session 23).** Superseded by **wrapping by facts** (`writeup/explorations/wrapping-by-facts.md`), adopted by the user. Code written without traits is called directly; compiled trait-world code depends on the method table only through dispatch facts at concrete signatures, and nothing is skipped. Trait wrappers, delegates, sealing, doors and declared calls are no longer needed. This note is kept until it is rewritten after the prototype has shown whether the design lives up to its promise.


Base, the standard libraries and nearly every package were written without traits. This note covers how trait modules use that code, and how a library adopts traits without breaking its callers:
- **Adopting traits:** a library adopts them one function at a time, its type-based methods keeping their meaning.
- **Traits over existing functions:** state Base's informal interfaces as contracts, with conformances declared for Base's families.
- **Trait wrappers:** bring a package into the trait world unchanged, standing in for its owner.
- **Calls upward:** reach code that stays outside, such as a plotting system, through declared calls.
- **Sealing:** enforces ownership over everything the trait world compiles against.

The rules this note relies on, layering (rule 1), ownership (rule 3) and views (rule 4), are in [the design in detail](4-details.md#the-four-rules). Why the design layers at all, and how C++ fared with the same rule, is in [design choices](2-design-choices.md#5-layering-trait-bound-code-calls-only-trait-bound-code).

## Adopting traits, one function at a time

**Existing methods keep their meaning.** A library that adopts traits keeps its type-based methods. A trait bound ranks above `Any` and below every type:

```julia
describe(v::Vector{Float64}) = …     # as today
describe(m::AbstractMatrix) = …      # as today
describe(t::ColTable) = …            # new: every other type that conforms to ColTable
describe(x) = …                      # the old fallback, for everything else
```

Adding the trait method changes only calls that used to reach the fallback or raise a `MethodError`. So a library can adopt traits one function at a time, and every existing call keeps its meaning: a value that does not conform reaches the most specific ordinary method that applies. A value of a user type that reaches a type-annotated method, such as a user's subtype of `AbstractMatrix`, is not translated by a bound; that call runs as ordinary code, with today's semantics and today's speed. The ranking rules among traits are in [the design in detail](4-details.md#dispatch-types-first-then-traits).

**Conversion goes bottom-up, by module.** A package converts its own modules one at a time, from the bottom of its dependencies up. Using packages written without traits, wrapped or through calls upward, is not converting them.

## Traits over existing functions

A trait's operations may be existing generic functions. Capability traits then state Base's informal interfaces as contracts, without rewriting Base:

```julia
@trait Indexable{T} begin                          # the operations are Base's own functions
    T = eltype(Self)
    Base.length(a::Indexable)::Int
    Base.getindex(a::Indexable, i::Int)::T
end

@implement Indexable A where {A <: AbstractVector}   # no body: Base's methods, checked when declared
```

**Conformance is declared, never derived from the methods that happen to exist.** Deriving it would be unsound three ways:
- Base's fallbacks exist and throw: `getindex` has a method for every `AbstractArray`, and `IteratorSize` answers `HasLength()` for every type.
- Types conform by accident: a `Number` iterates and indexes, a `String` indexes by byte.
- Whether a call infers changes with what is loaded.

**Family declarations take Base's documented interface at its word.** A declaration for a family through one of Base's abstract types relies on the interface Base documents. A subtype that breaks the `AbstractArray` contract throws in both worlds, as "identical or error" requires, and concrete mode reports it when the package is built.

**Who declares them.** By ownership (rule 3), such declarations come from the trait's owner or from Julia. So a small library of capability traits, `Iterable`, `Indexable` and `HasLength` with conformances for Base's families, is all it takes. It lives in the Base wrapper.

**What stays unchecked.** Trait-bound code still calls Base directly. Inference confirms such a declaration only at concrete argument types, and misses a fallback that throws on some paths only. Every call asserts its result, so "identical or error" holds regardless.

## Trait wrappers

**What a wrapper is.** A trait wrapper brings a package written without traits into the trait world and stands in for its owner there. Everything the trait world needs to know about the package lives in the wrapper, and a library written with traits needs none. Base, Core and the standard libraries are the first wrapped package, through the Base wrapper, implicit in every trait module.

**What is admitted is decided by a check, not by the package's name.** Base's source handles any value, so it is not trait-world code. A specialization of a Base method at trait-world types, reached from a worker, is trait-world code when it passes the check below. Julia's package images already hold such specializations; the design adds that nothing above can invalidate them.

**Which values are trait-world values:**
- A value without parts, a `Float32` or a `String`, is a trait-world value wherever it was made.
- A value with parts is one when all its parts are, except a handle, whose part nothing reaches (Calls upward).
- The check accepts a value when its type decides that: `Vector{Float64}` does, `Vector{Any}` does not.

**Where a specialization's values come from.** Each source is closed:
- **Arguments** are translated by their bound at the entry, or admitted as trait-world values. A type that decides, being deeply concrete, is admitted by its type. A type that does not decide, such as a field declared `Real` or a `Vector{Any}`, has its abstract parts walked by the entry, at a cost proportional to them, and concrete mode reports such an argument type.
- **Globals** it reads must have a trait-world type: a constant or typed binding, deeply concrete. `ENV` passes; `stdout`, the logger's state and `Main` do not.
- **Constructors** make values from parts and add nothing to check.
- **Calls** return values of specializations checked the same way, Base's and any wrapped package's, transitively, on static paths. A dynamic site inside selects at run time, and the dispatch check admits only a method of an owner or a delegate of the function or of an argument type. The target's specialization is checked when it compiles, which a build enumerates and a session reaches at the first call.

**How much of a package passes** is decided by the check, as for Base. The wrapper's author runs it at the wrapper's build and learns how much passes: for a solver, most of `solve`. A plotting system as written today passes nowhere and is not wrapped but called (Calls upward).

**What a wrapper holds:**
- **The implementations it delegates to.** Many packages are split into a core of types and functions plus implementation packages:
  - StaticArraysCore with StaticArrays;
  - ColorTypes with Colors, ColorVectorSpace and ImageCore;
  - StatsAPI with StatsBase.

  Such a package has its behaviour outside the core: with the core alone, an `SArray` has no `size`. The core's wrapper names the implementations and depends on them, so they are loaded whenever the core's types can enter the trait world. As delegates their methods count as the core's (rule 3). An implementation the wrapper does not name is a pirate of the core, refused at its load (Sealing), so the wrapper names every implementation in use.
- **Conformances and doors:** which of the package's types conform to which traits, declared as the Base wrapper declares Base's families, and which of its functions are doors.
- **Tolerations** of pirates in the dependencies it seals with its package (Sealing).

**One wrapper per package.** A wrapper decides what trait-world code compiles against, so a package has at most one wrapper in an environment.
- A second wrapper is refused at its load.
- Trait modules and other wrappers reach the package through it, as a GeometryBasics wrapper reaches `SArray` through the StaticArraysCore wrapper.
- When the package adopts traits, it owns itself and its wrapper becomes a re-export.

## Base and the standard libraries

**Why Base qualifies although it was written without traits.** Core, Base and the standard libraries of one Julia version depend only on each other and ship together. So layering holds by construction, and ownership by designation, with Julia as one owner.
- The standard libraries of the system image are in every view, so LinearAlgebra's methods on Base's functions are seen everywhere.
- A standard library upgraded from the registry is a package with a wrapper of its own.
- `Main`, the REPL and Pkg are ordinary code.

**What the Base wrapper carries:**
- **The capability traits** over Base's informal interfaces (`Indexable` over `getindex`), with conformances for Base's families, so the curation has an owner.
- **The standard libraries.** Most pass the check as Base does: LinearAlgebra, Random, Dates, Statistics.
- **Declared calls with checked results** for those with inward doors:
  - Distributed's `remotecall_fetch(f, …)::Vector{Float64}`, whose deserialized result is checked at the boundary and is then a trait-world value whatever its origin;
  - Serialization's `deserialize`.
- **Outward doors:** Logging's sinks.

**On the prototype,** the check walks the typed code of each worker into Base, with a budget, the door list and the check of globals. On stock Julia it sees static calls only, so a door behind a dynamic call is not found.

## Calls upward: code that stays outside

**What a call upward is.** Code outside the trait world runs for it only as a call upward (rule 1): at a declared signature, through a pointer, with no inference edge, the result translated by its bound. So no worker's cache depends on anything behind it. One mechanism has three uses:
- a function handed down, bounded by `Callable` ([the design in detail](4-details.md#function-arguments-callable));
- a declared call to a named function of a package that stays outside, `@call Makie.scatter!(f, xs, ys)::Nothing`. Its body is ordinary code compiled outside the module's cache, in a package that depends on Makie;
- Base's doors.

**Handles.** A result that comes back without operations is a handle, the mirror image of a trait object:
- its content is reached by no operation;
- `==` and `hash` are identity, and `show` prints the handle's type;
- `h.ref` and `typeof(h)` are refused.

A handle is a value only to hand to the next call upward.

**Doors have a direction.** The doors are Base's functions that make values from non-values.
- **Outward doors** send trait-world values up and return nothing: logging, `display`, printing to `stdout`. They are calls upward with no inference edge: allowed, reported by concrete mode as dynamic calls, and nailed to the application's declared sinks in a build.
- **Inward doors** bring values in: `eval`, `invokelatest`, deserialization, reflection over the method table, `getglobal` on a module, task storage, raw memory. They are allowed only as declared calls with a checked result. Since no bound admits a value denoting code from above (a `Module`, a `Type`, a `Method`, a bare function), reflection and `eval` stay out as sources of values on their own.

**What is curated.** The door list lives in the Base wrapper. Together with the implementations and conformances that wrappers name, it is all that is curated; the rest is structural.
- A Base function that reaches a door at some specialization falls out there: on a static path when the worker is compiled, behind a dynamic site when the target compiles. The finding names the worker and the line.
- `print(io, x)` on an `IOBuffer` is in, `rand()` is in, `task_local_storage()` is out, and `print(x)` is a dynamic call.

**A plotting system is called.** A package whose work is state and effects passes the check nowhere and is never wrapped: trait-world code calls it. Declared calls add no methods and decide nothing about what trait-world code compiles against. So anyone may declare them, and any number of packages may declare calls into one package.

```julia
module Plots                            # a trait package that calls Makie; the syntax is a sketch
using Makie
@trait_module module Surface
    export figure, scatter!, save
    @trait PointSeries begin
        xs(s::PointSeries)::Vector{Float64}
        ys(s::PointSeries)::Vector{Float64}
    end
    @handle Figure                                            # a value from Makie, opaque inside
    figure() = @call Makie.Figure()::Figure                    # declared calls: no inference into Makie
    scatter!(f::Figure, t::PointSeries) = @call Makie.scatter!(f, xs(t), ys(t))::Nothing
    save(path::String, f::Figure) = @call Makie.save(path, f)::Nothing   # Makie's globals and effects live behind the call
end
end
```

- **Globals become declared calls.** Trait-world code never reads a Makie global:
  - the current figure is a call returning a handle;
  - the theme is a call taking trait-world values and returning nothing;
  - `display` is a call returning nothing.

  The package also fixes the trait-world spelling of Makie's concepts: colors as tuples, markers as symbols, attributes as named tuples.
- **Compiled code lives where rule 4 puts it.**
  - The trait module's workers are in the package's trait-world cache, whose view excludes Makie; Makie is reached only through declared calls.
  - Makie's code at the declared signatures is ordinary code: in Makie's image for what Makie precompiles, otherwise in this package's image, whose precompile workload is exactly the declared signatures. So time to first plot from a trait module equals an ordinary module's.
  - Redefining a Makie method invalidates that cache as today and nothing in the trait world; the pointer is refreshed by world age at the next call.
  - In a build, the declared calls are targets compiled as ordinary code, and whether Makie trims is Makie's problem.
- **One surface, by convention.** A handle type belongs to the package that declares it. So trait packages that pass figures to each other share one package of declared calls into Makie, whose image then holds Makie's code at those signatures once. That is a convention among trait packages, not a kind of package.
- **Audited, not sealed.** What lies behind declared calls is in no view, so its pirates change no trait-world code. The package's build reports the pirates in Makie's tree, as Aqua does today, as the place to push fixes upstream, and sealing leaves them alone.

A Makie rewritten in the trait world, with traits for colors, observables and recipes that users conform to, is sketched in [design choices](2-design-choices.md#3-compiled-for-what-the-bound-can-see).

## Sealing

**What sealing is.** Sealing is ownership (rule 3) enforced at the load, over the views of rule 4: every package in a worker's view is sealed by the load that brings it there.
- Loading a trait package seals it, so nobody pirates `Columns` at its types.
- Loading a wrapper seals the package it wraps, the implementations it names, and their dependencies.
- The Base wrapper, implicit in every trait module, seals Julia.
- Code reached only by calls upward is in no view and is never sealed.

**What is refused.** From the seal on, a definition that would pirate a sealed package is refused: a method on functions and types all owned by sealed packages, added by a package that is neither an owner nor a delegate of any of them. Two examples:
- `Base.convert` for Base's types, from anywhere but Base;
- OffsetArrays' `getindex` for Base's ranges, which changes what a working Base method returns.

**Refuse at the load, never at a call.** Refusal happens where methods enter the method table:
- **for a package image:** before any of its methods is inserted, so that a refused package is absent rather than half loaded. That needs a transactional image load;
- **for code evaluated later:** at the definition;
- **for a seal that arrives after the pirate:** at the seal's load, naming the pirate.

A refusal at the pirate's precompile is an early warning only, since a compile cache made in another environment is reused. The method table itself stays plain Julia's. Two alternatives were rejected:
- Keeping the pirate and poisoning the affected code to raise at the call fails late; an earlier version of the design did this.
- Making the pirate invisible inside the trait world was rejected twice, because one method with two versions disagrees silently across the worlds.

A wrapper's own load checks the session as it stands, and a pirate it does not declare as tolerated fails that load in strict mode.

**Owners keep their freedom.** Adding methods for your own types to any function, implementing traits for your own types, and redefining your own code all work as today. An owner can delegate, for example to a package extension that implements its trait, and anyone can write a named implementation. Sealing freezes nothing.

**The opt-out is plain Julia.**
- A pirate that is tolerated, declared by a wrapper or accepted per package in a project, recompiles the signatures it touches against it, with a warning. The two worlds always agree, and the guarantees hold for everything it does not reach.
- The interim is this with everything tolerated: warn and recompile by default, refusal as the strict mode, until the ecosystem passes. Aqua's piracy check already pushes it that way.
- On stock Julia, the prototype's default warns and keeps the pirate. Its refuse mode deletes the pirate's methods after the load, since stock Julia cannot refuse one, which makes it depend on the load order.

**What you get.** In a session whose packages are trait packages, wrappers and their dependencies, nothing pirates what the trait world compiles against, in whichever order they load:
- every cache stays valid;
- every worker runs against what it was compiled for;
- a build sees the whole trait world.

Base is sealed in any session that uses traits at all, and the sealed region is what the project file says: its trait packages and the wrappers they load.

**Measured on Makie's tree.** Sealing Makie's whole dependency tree on the prototype found 1091 pirate methods.
- **1042 are implementations of split cores,** which their cores' wrappers name wherever trait-world code uses those types, and which lie behind calls upward otherwise:
  - StaticArrays for StaticArraysCore: 794;
  - Colors, ColorVectorSpace and ImageCore for ColorTypes: 226;
  - StatsBase for StatsAPI: 22.
- **Of the other 49:**
  - OffsetArrays' 12 methods and one deprecated StatsBase method are on Base's functions at Base's types, refused or tolerated in every session that loads them;
  - once DataFrames is wrapped, which seals DataAPI, so are Tables' 4 and StatsBase's 3 methods of DataAPI's functions at Base's types;
  - the remaining 29 lie behind the calls into Makie.

Wrapping Makie itself, with CairoMakie as its implementation, adds 46 pirates, nearly all pairs of a core and its implementation that four more core wrappers would name, and one real pirate (`experiments/interfaces/README.md`, x14).

## What this costs

1. **A stranger's piracy refuses a load,** and the error reaches whoever loads the pirate, not its author. This is the most contested part of the design. The numbers above say it lands mostly on split cores, which wrappers resolve.
2. **Code written without traits is curated:**
   - capability traits with their conformances for Base's families;
   - each wrapper's implementations, conformances and doors.

   A type nobody declared does not conform, even when it has the methods.
3. **Calls out are calls upward.** A plotting system is called through declared calls with handles, not run inside. Its time to first plot is an ordinary module's, and its code is outside the trait world's guarantees.
4. **One wrapper per package and environment.** Two trait packages that would wrap one package differently must agree on one wrapper.

The prototypes around DataFrames and Makie, with their measurements (sealing audits, time to first plot, binaries), are described in `experiments/interfaces/README.md`.
