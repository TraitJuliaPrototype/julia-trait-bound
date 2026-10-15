<!-- Local copy of the design note "Traits for better Julia" (Claude Doc, https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20), exported at rev 1019 on 2026-10-14, then kept in step by hand: rev 1022 (extension triggers, split packages), rev 1058 (trait wrappers replace interface packages, calls upward, sealing over views), rev 1110 (four rules: 2 = old 2-4, 3 = old 5, 4 = old 6 and 7; interactions table cut; generic implementations and joint projections moved to Finer points; earlier forms of the design moved to design-findings §14; open-typed arguments walked at the entry), all 2026-10-15, session 20; rev 1112 (new section "Between nested types and `Any`"), rev 1116 (that section revised after Fable's review; trade-off 1 and the wrapper section say "as written"; "inlined" out of the conformance table), session 21. The artifact is the live note; this copy is for offline reading and for diffing between revisions. Refresh it by exporting the tab as markdown. -->

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

The **trait world** is every trait module and every wrapped package: Base, Core and the standard libraries, wrapped as one, and any package written without traits that a trait wrapper brings in. It is closed: a trait module accepts only values of trait-world types, and everything it reaches is checked, on the compiled code, to do the same. Ordinary code, which is all of Julia today, may depend on the trait world as on any package, and a package can pair a trait module with an ordinary module that uses both. What the check admits, how a wrapper brings a package in, and how trait-world code calls a package that stays outside, are under "Finer points".

This two-layer design enables everything else. Compiled code in the trait world depends only on what lies below it, so nothing that happens above it can change what that code computes. Cached code therefore stays valid, which gives interactivity. Within the trait world, the same checks that ensure that the world is closed, give simple AOT. The primary way in which one can reach into the trait world from above is piracy, which this design forbids.

The core concepts are:

- **Trait**** ****a****n****d**** ****i****t****s rep****resenta****tion****.** A contract stating what library code needs from a type: operations on a representation. Every trait specifies which data it operates on. The data can be concrete, even if the type the trait is defined on is abstract. The representation is a parameter (that might be inferred), as in `M``y``T``r``ai``t``{R}``.` A trait may provide default operations. Representations can be constrained to be concretely typed.
- **I****mplementation.** A representation is typically plain, deeply concrete data that library code works on, such as `Vector{Vector{Float64}}`. An implementation, written ` @implement  ``M``y``Table``  M ``yT``ype`, defines the trait's operations once for a representation, or for a family of them, as ordinary methods that library code calls directly. As much of the implementation as possible is inferred automatically. Implementation is where the ordinary Julia world crosses into the Trait world.&#32;
- **Trait module****s**** and t****rait-****bound c****ode****.** A module whose code is fully specified in terms of traits. We say the code is trait-bound. A trait module is declared `@trait_module module M … end`. Its exported functions take arguments bounded by a trait; its internal functions need none, and are inferred from the representations those bounds admit.
- **Entry and worker.** A bounded function has an entry, ordinary code that translates its arguments by their bounds and does nothing else, and a body compiled once per representation, the worker.
- **Trait wrappers.** A package that brings a package written without traits into the trait world and stands in for its owner there: which of its code passes, which packages implement it, which of its types conform to which traits, which of its functions are doors. Base, Core and the standard libraries come in through the Base wrapper, implicit in every trait module. A library written with traits needs no wrapper.

### An example: a library and its user

The library, a trait module (`Columns/src/Columns.jl`). The macros stand for syntax a language feature would provide. The prototype, TraitWorld (`poc/world`), runs the library as written, with the module body in a `@trait_module begin … end` block inside `module Columns`. The user's side below uses the one-line form of `@implement`, which the prototype runs for concrete types; the written-out forms are under "How a type conforms to a trait" further down.

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

Four rules make the principle precise. Rule 1 is layering itself; rule 2 says how a value crosses into the trait world and what it is there; rules 3 and 4 say who may change code in the trait world, what a call sees, and where compiled code lives.

1. **Layering.** Ordinary code may use the trait world; the trait world uses only itself. A trait module calls trait modules and wrapped packages, checked on the compiled code, and accepts only values of trait-world types. Code outside runs for it only as a call upward: at a declared signature, through a pointer, with no inference edge, its result translated by its bound. A function handed down from above is such a call, a `Callable` argument, unless it is compiled with the caller, above the trait world's cache; so is a declared call to a named outside function, `@call Makie.scatter!(…)::Nothing`; so are Base's doors; and what comes back without operations is a handle. Code from above reaches the trait world only as values handed down: trait objects, through their projections, and functions bounded by `Callable`. A package can pair a trait module with an ordinary module that uses both.
2. **The boundary translates, once per bound.** A value enters the trait world where ordinary code calls in, at a bound, translated by it: a trait bound projects the value through its type's projection for that trait, a declared type asserts, a `Callable` bound makes a function a call upward. Inside, a trait object is its trait's representation and nothing else: it is passed to functions without a bound, which are compiled for it like any argument, and to a bounded argument only where its own trait is expected, or a supertrait whose declared representation map derives the other view. A function that uses a value under two traits, itself or through what it calls, therefore declares both bounds at its boundary, and the ordinary caller's one value is projected once per bound: two views, which share data only where both projections share the user's data, or where the type declares one projection for both.
3. **One ownership rule.** A package may add a method to the trait world only where it owns the function, or one of the types, in every signature the method applies to; a `Union` with a foreign type is no way around this. Julia counts as one owner. Implementations and projections are methods too, so this is also the rule for who may implement a trait, and it applies to an implementation's own methods: an operation that is someone else's function, such as `Base.size`, is implemented for someone else's type only by an owner of one of them, while the trait's owner declares the existing methods instead. Ownership can be delegated by its owner, never claimed. A delegate is a package extension triggered only by packages its methods mention, so it is loaded whenever a call could use it. An extension owns what its parent owns; its triggers confer nothing, or two parents' extensions with the same trigger could both implement one method. A package written without traits is owned in the trait world by its trait wrapper, at most one per package, which delegates to the implementation packages it names among its own dependencies, so they too are loaded whenever a call could use them; Julia is one such package, owned by the Base wrapper.
4. **What a call sees, and where its code lives.** A call in the trait world sees the owners of its function and of the representations involved with their trait-world dependencies: trait packages, wrappers with the packages and implementations they bring in and the dependencies of those, and Julia always. A package reached only by calls upward is in no view. Its code is compiled against exactly the methods it sees. For an implementation written in the session, the view is the trait package's view plus the implementation's own methods, not the session's imports; what is redefined at the prompt recompiles as today. At a dynamic site, the method selected at run time must come from an owner or a delegate of the function or of one of the argument types (rule 3): a downstream trait module's method for its own type is accepted, a method from above or a pirate raises. With rules 1 and 3, loading a package can only add methods for its own functions and types, which no compiled code reaches, or pirate from outside the trait world, which is refused at the load. Compiled code for a combination of packages lives in a package that depends on all of them: the trait module for its own representations, a conformer for the representations it brings, a package extension or the application when packages meet only there, and the session when nothing depends on all of them.

Rule 2 in practice: a function that needs both views says so, and its caller passes one value.

```julia
summary(t::(ColTable, RowTable)) = (colmean(t, 1), firstrow(t))   # t carries one view per trait
```

Together, rules 1, 3 and 4 give the central guarantee: loading a package can never change what code in the trait world computes; it can only add code for new types, or be an error.

### What code in a trait module may do

A trait object is a view of the user's data, not a value: code reaches the user's data only through the trait's operations, and a function from above only by calling it as a `Callable`. Every other value is an ordinary Julia value of a trait-world type.

The module's exported functions are its boundary: their trait-object arguments carry bounds, which say what an ordinary caller's value must conform to and what the entry projects. Internal functions need no bounds. A trait object passed to one is inferred like any other argument, and the function is compiled for it as part of the worker that calls it; helpers of an implementation take the representation itself, `r::R`; unexported types are ordinary trait-world types. The handle still admits only the trait's operations, so an internal use that the exported bounds do not cover is reported when the worker is built, at its line, with the bound to add, and a bound no path uses can be warned. Internal functions must infer concretely from the representations the bounds admit, which concrete mode checks through any number of layers; their code compiles with the worker, so rule 4 is unchanged. An exported function's argument without a bound takes trait-world values only, so a user type passed there runs as ordinary code (rule 1). Bounds on internal functions remain allowed, for dispatch and as documentation.

| In a trait module | Allowed | Why |
| --- | --- | --- |
| the trait's operations on a trait object: `col(t, i)`, `ncols(t)` | yes | the only way to reach the user's data |
| several trait objects in one function, of one trait or several | yes | compiled once per tuple of representations |
| an argument with several bounds, `t::(ColTable, RowTable)` | yes | one projection per bound (rule 2) |
| passing a trait object to the module's own functions, or on where its own trait is expected | yes | statically within the module, through the entry otherwise (rule 2) |
| methods with type annotations beside trait-bounded ones: `f(m::AbstractMatrix)`, `f(t::ColTable)` | yes | types first, then trait bounds |
| a call upward: a function bounded by `Callable{Tuple{Float64}, Float64}`, a declared call into a package that stays outside such as Makie, an outward door such as printing to `stdout` or logging | yes | through a pointer at a declared signature, no inference edge, the result checked, handles for what comes back (rule 1, Calls upward); in a build, outward doors are static calls to the application's declared sinks |
| any code on values of trait-world types: loops, arrays, closures, `try`, the module's other functions | yes | ordinary Julia, compiled per representation |
| importing and calling Base, a standard library, a trait module or a wrapped package | yes | checked on the compiled code: globals of trait-world types, no undeclared door; the Base wrapper is implicit (Finer points) |
| methods of functions or for types the package owns, implementations and projections among them | yes | ownership (rule 3) |
| passing a trait object where a different trait is expected | no | declare both bounds, so the caller projects each (rule 2) |
| a trait object anywhere else, as a bare value: passed to an ordinary function, stored, returned, `typeof(t)`, `t.field` | no | code must not depend on the user's type |
| two methods with unrelated trait bounds on one position and no method for both | no | ambiguous for a type with both projections; checked when the function is defined |
| calling a package written without traits directly, unwrapped | no | rule 1: wrap it, or declare the calls; the check says which |
| a method whose function and types the package does not own | no | piracy, rejected when the module is built (rule 3) |
| inward doors: eval, invokelatest, deserialization, reflection, getglobal by name | only as a declared call | a value denoting code from above has no admitting bound |
| arguments of open types from ordinary callers: `Any`, `Vector{Any}` | after a walk | the entry checks their parts, at a cost proportional to them, and concrete mode reports the type; a part that is no trait-world value, or a function without a `Callable` bound, makes the call run as ordinary code |
| loading a package that pirates a sealed package | no | refused at the load, naming the pirate (Sealing); the opt-out is plain Julia |
| abstract types, under concrete mode | no | opt-in: a warning or an error that names the root cause |

Implementations and dynamic operations follow the same rules. The prototype checks the rows that are not design: rule 2 and the escapes on the typed code of each worker signature, reported with their lines; ownership and imports when the module is defined; ambiguous bounds when it is complete; the rest at the first call of a signature, or while a package image is built. Doors and declared calls are checked on the typed code too, and the sealed-load row is, on the prototype, a warning, or a deletion after the load in its refuse mode (Sealing).

## How the concepts achieve the goals

### Between nested types and `Any`

Julia code today chooses, field by field, between types that carry the types of all their parts and `Any`. The trait world makes that choice per conformance and per call mode instead, and code above a bound keeps the trait's contract whichever way it goes.

In Julia, a type's parameters carry the types of its parts, and code is compiled per concrete type. A value built in layers, a plot holding an observable holding a user's array, has a type that grows with every layer, and code that handles it is compiled per combination of what lies below. The way to stop the growth is a field of an abstract type or `Any`, which drops what the type said: unless the function has few methods or the caller asserts the result, the compiler knows neither which method a call reaches nor what it returns, each target still compiles per runtime type when first reached, any load can add targets, and a build cannot list them.

A trait bound separates what a Julia type carries in one: the contract, the trait's operations with their declared result types, and the representation, the data the code runs on. Code above a bound reaches a value only through the contract, and is compiled for as much of the representation as the conformance or the call mode chooses:

| Position | Compiled | A call on the value | Compiled for | A load elsewhere |
| --- | --- | --- | --- | --- |
| Julia: a type parameter | per nested type | direct | the whole type | can invalidate it |
| Julia: an `Any` field | the caller once, each target per runtime type when first reached | dynamic, result `Any` unless asserted | nothing | can add targets |
| own representation | the library per type, in the conformer's image | direct | the type, reached through its operations | changes nothing (rule 4) |
| projection | the projection per type, the library per representation | direct | the representation | changes nothing (rule 4) |
| dynamic operations | the library once per set of dynamic operations, in the conformer's image | indirect, result type declared | the shared representation | changes nothing (rule 4) |
| dynamic call | the library once per signature, the function by its caller | indirect, result type declared | the signature | changes nothing (rule 4) |
| compiled call | per function type, in the caller's image | direct | the function's type | can invalidate it, as today |

A conformance that projects, and a dynamic position, end the growth there: code above compiles per tuple of the representations at its own bounds, whatever was built below. Within one function the compiled code still multiplies over that function's bounds, as `meandiff` does over its pair; across layers it adds up, because each layer's representations are chosen by that layer, not assembled from the layers beneath. Growth continues only by choice and in the chooser's image: a type that is its own representation, a parametric family, a generic implementation, a compiled call, or a dynamic call with an open result type. The argument is structural; it is not yet measured on a stack of trait modules.

The dynamic positions are not `Any`. Result types are declared and asserted, so the code after a call infers concretely; the targets are conformances and declared signatures, which only owners and delegates add (rule 3), so no load from outside adds one and a build can list them. The cost is the direct call: about 4 ns for a dynamic call and 6.3 ns, 7× plain Julia, for a per-element dynamic operation, so they suit calls made per plot, per attribute or per callback, not per element. On the prototype a build lists each function passed as a dynamic call and compiles it as a direct call, but a dynamic operation's pointer is created at the first call in a session, 107 ms in a fresh one against 1.4 ms for a projection, and `verify_main` does not see it; compiling it with its conformance, into an image, is design. A field of an abstract type inside a trait module remains possible: its dispatch is closed by ownership (rule 4), its results are not inferred, and concrete mode reports it in a hot loop.

Plain Julia can reach the same shape by discipline, converting to a few concrete types first and asserting results after dynamic calls: on the prototype a hand-written convert-then-plot function costs 36 ms per new table type, the trait route 35–47 ms. Three things are new. The bound is enforced, so nothing before the projection specializes on the user's type. The targets of the dynamic positions are closed by ownership and listed for a build. And code compiled per type lives in the image of the package that chose the type, where no other load invalidates it, so that position costs build time and disk rather than session latency.

Makie is the case in point. Its pipeline specializes on the user's argument types before `convert_arguments` reaches its own representations, 297 ms per new table type on the prototype, and between its compute steps it keeps attributes and observables at `Any`, among other reasons because an attribute can change type over time. Julia's dispatch tracing shows what that `Any` hides: a first bar chart with a line reaches 1,940 distinct methods, other values of the same types add one, and each new argument type or attribute shape adds 35–84; a static walk from the five calls stops at 75 calls whose targets it cannot list. In the trait world the conversion is the projection at Makie's boundary, onto families of its own: positions as `Point{N, Float64}` or `Point{N, Float32}` by the data's element type (Makie once converted everything to `Float32` and stopped, for precision), colors as `RGBAf`, numbers mapped through a colormap, or vectors of these. An attribute with several representations is a field whose type is a union of Makie's own, dynamic inside and closed by ownership, so its code compiles per representation in Makie's images and never per user type; a recipe is a downstream trait module's method for its own plot type, selected at such a site (rule 4). This is a sketch, mapped part by part in the findings document; Makie as written is reached by calls upward (Trade-offs).

What stays is the trade-off at each position, as in every language with both generics and dynamic dispatch: more representations cost compiled code, a projection costs a copy where it does not share and loses what its representation cannot hold, a dynamic position costs an indirect call. A trait object cannot be stored, so a library that keeps users' values of different types keeps their representations. What a user should see of a worker is its bound and representation, as concrete mode prints it (`scaled_sum` at Series at Vector{Float64}); the prototype's stack traces still print the machinery's nested `TObj{ColTable, Tuple{View{…}}}`.

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
- **Compiled against what it sees.** Each specialization is compiled against the methods of the packages it depends on only (rule 4), so inference, union splitting and return-type queries see nothing else. A later definition by one of those packages recompiles it. A definition elsewhere, for the definer's own types, can never apply. One that would apply is piracy, and the load that brings it is refused.
- **Every combination has an owner image.** The entry lives in the trait module's package image, the projection in the conformer's, and a worker at a new representation in the conformer's too; code for packages that meet only in an application lives in a package extension or the application, and the session comes last (rule 4). Each piece is compiled where it lives, because a downstream image cannot add native code to an upstream one.

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

In plain Julia, a generic function called on a value of unknown type has no list of targets: it compiles at first use in a session, and fails a trimmed build, or crashes a binary built with the unsafe option. Here the list exists, and a function passed as a `Callable` argument adds one target at its declared signature. On the prototype, `verify_main` enumerates the entries' targets from the types the program can pass (here 8 targets), and the program compiles to a 2.09 MB trimmed executable; without the list, the binary dies at its first trait call.

### No performance cliffs

Four cliffs disappear by construction, and the fifth becomes a report at build time.

- **Loads cannot change speed.** The methods at an abstract call site change only with their owners (rule 4), so an unrelated load cannot push inference over `max_methods` and turn a fast call dynamic. Return-type queries fold at compile time.
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

Under layering, a load can affect code in the trait world only through a method from outside what that code sees which would change it (rule 4): piracy. Every package in a view is sealed by the load that brings it there (Sealing), and a load that seals checks what is already loaded as well as what comes later: a pirate of a sealed package is a conflict whichever side loaded first, refused in strict mode and tolerated with a warning and a recompile otherwise, so no call sees a pirate that was not tolerated, and no call errors on one. The opt-out restores plain Julia.

```julia
using MyTable                         # projects MyTab; Stats' worker calls weight(::Float32); Stats and Base are sealed
using Pirate                          # defines Stats.weight(::Float32), owning neither: refused, naming the method and Stats
tolerate!(:Pirate)                    # opt out for this session (a sketch): plain Julia, the pirate applies
using Pirate                          # loads; Stats' worker for Float32 recompiles against it, with a warning
colsum(MyTab(Float32[1, 2, 3]))       # what plain Julia computes
```

- **Two exceptions.** Element types that Julia derives from inference, such as that of `map` over an empty collection, are answered within the trait world, and can differ from plain Julia's where Julia documents them as inference-dependent. An open `Callable` result type, inferred at the boundary in ordinary code, depends on what is loaded there; it is part of the worker's key and checked at every call, and concrete mode reports it when it infers to `Any`.

## Working with existing Julia

Base, the standard libraries and most packages were written without traits, and a library that adopts them already has callers, type-based methods and higher-order functions. Three mechanisms let trait modules use existing code as it is, and let a library adopt traits one function at a time without changing what existing calls do. How Base and other packages written without traits join the trait world through wrappers, and how a package like Makie is reached through calls upward, are under "Finer points".

### Traits over existing functions

A trait's operations may be existing generic functions. Capability traits then state Base's informal interfaces as contracts, without rewriting Base:

```julia
@trait Indexable{R} begin                          # the operations are Base's own functions
    Base.length(r::R)::Int
    Base.getindex(r::R, i::Int)::eltype(R)
end

@implement Indexable{A} where {A <: AbstractVector}   # no body: Base's methods, checked when declared
```

Conformance is declared, never derived from the methods that happen to exist. Derivation would be unsound three ways: Base's fallbacks exist and throw (`getindex` has a method for every `AbstractArray`, and `IteratorSize` answers `HasLength()` for every type); types conform by accident (a `Number` iterates and indexes, a `String` indexes by byte); and whether a call infers changes with what is loaded. A declaration for a family through one of Base's abstract types takes Base's documented interface at its word instead: a subtype that breaks the `AbstractArray` contract throws in both worlds, as "identical or error" requires, and concrete mode reports it when the package is built. By rule 3 such declarations come from the trait's owner or from Julia, so a small library of capability traits, such as `Iterable`, `Indexable` and `HasLength`, with conformances for Base's families, is all it takes. Trait-bound code still calls Base directly. Inference confirms such a declaration only at concrete argument types, and misses a fallback that throws on some paths only; every call asserts its result, so "identical or error" holds regardless.

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
- **The library sets a default, the caller decides.** `Callable{A, S, M}` carries the mode `M`. `DynamicCall`, the default, makes the function a pointer to its code compiled for `A` in ordinary code at the call site: the worker is compiled once per signature, in the trait module's image, and each call through the pointer is indirect. `CompiledCall` compiles the worker per function type instead, with the function's body inferred into it, as ordinary code in the caller's image (rule 4), a direct call the compiler may inline: plain Julia's speed and plain Julia's invalidation for that piece. Such a worker is the library's code compiled outside the library's cache, so a library that makes `CompiledCall` the default of a function gives up goal 1 for that function by choice, which is why the system default is `DynamicCall`. A bound without the parameter accepts either mode and supplies the default. The caller overrides per value with `compiled_call(f)` or `dynamic_call(f)`, wrappers whose type fixes the mode and which the entry strips; the long form, `Callable{Tuple{Float64}, Float64, DynamicCall}(f)`, also fixes the signature, as FunctionWrappers does today. The value's type wins because the library's cache has no stake either way; its users do, which is what the default is for. Concrete mode reports a dynamic call inside a loop and names the caller's fix.
- **Layering holds for the trait world's cache either way.** No cached worker imports, infers into or compiles the code above: a dynamic call goes through its pointer, and a compiled call's worker, which does infer into the function, is ordinary code that lives with the caller, outside the cache and outside rule 4's view.
- **An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in ordinary code, becomes part of the worker's key, and is checked at every call.
- **Functions from the trait world are always compiled calls.** Base's `abs2`, a trait module's own functions and closures created inside a trait module are trait-world values: whatever the default, the worker is compiled for them and calls them directly within the trait world, cached by rule 4. `map`, `filter` and `sum(f, …)` work inside the trait world as today.
- **AOT.** A `Callable` argument names its signature, so a build compiles each function passed at it, and `verify_main` lists them as targets.

A function called at two signatures carries two bounds, `f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int})`, one translation per signature, as rule 2 allows for any value. Keyword arguments, varargs and functions that return functions are under "Finer points" below. The cost of a dynamic call is about 4 ns per call on the prototype.

## Finer points

One principle runs through this section; it is rules 1 and 2 read operationally. Only values cross the boundary, each where a bound stands, and the bound says how the value is translated. Code never crosses into the trait world's cache: no cached worker is compiled against code from above, and a compiled call's worker is compiled above, outside that cache. There is no bound for the way up, so what goes up goes as itself.

- **A bound is a translation.** A trait bound projects; a declared type asserts; a `Callable` bound makes a function a dynamic call, a pointer at a declared signature, or a compiled call, a worker compiled above on the function's type, as the mode in the bound or on the value says; no bound means a trait-world value. The translation is the same wherever the bound stands: a positional argument, a keyword, an element of a vararg, the result of a call upward.
- **Everything in a call that is not a value stays inside.** Defaults, keyword sorting, splatting and dispatch are plain Julia, run in the worker after translation. The entry translates and does nothing else.
- **A bound is a crossing point and has an entry,** on a named function or a closure alike. That is what exported has meant so far.

The subsections below apply it: the forms of conformance, generic implementations and joint projections, parametric types, keyword, default and variable arguments, functions that cross, trait wrappers, calls upward, and sealing.

### How a type conforms to a trait

The one-line form covers a type that holds a representation or is one. The written-out forms name the projection, give a type operations of its own at a shared representation, join several traits, or implement a trait for a representation the author does not own. Every form defines methods, so rule 3 says who may write it, and the methods are trait-bound code wherever they are written. The prototype runs every form for concrete types; parametric families (Parametric user types) are design.

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
@implement ColTable Window copies project(t) = [t.v[t.lo:t.hi]]   # refused by a trait with mutating operations (the checks below)

# 4. The operations in one block: for the author's own type, the same as 2; for a representation
#    the author does not own, only the trait's owner or a delegate it names (rule 3)
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

Form 4 may be generic over a family of representations (Generic implementations, below). What each form compiles:

| Form | Compiled anew | Operation calls |
| --- | --- | --- |
| a field or a written projection (1, 3, 5) | the projection | static, the representation's implementation |
| an own representation (2, 4) | the library's functions, once for the type | static, direct |
| dynamic operations (6) | the type's own operations, as pointers | indirect, 7× plain Julia per element on the prototype |
| a family declaration (7) | nothing | the existing methods, static |

Every check runs at the declaration, never at a call:

- ownership: the author owns the type or the trait, or is a delegate one of them names (rule 3);
- the representation is deeply concrete: the field's type, the projection's result, or the type itself. A field declared `AbstractVector` is refused with the field named; the fix is a concrete field, or a projection that materializes;
- every operation has a method or a default, with the declared result types;
- a projection declares whether it shares the user's data or copies it, and a trait with mutating operations accepts only projections that share;
- the methods' code stays in the trait world (rule 1);
- methods win over a field when a type has both, so writing operations is always deliberate; several conforming fields need the name `data`, or a written projection.

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

A function bounded by both then receives one value: one projection instead of two, views that share data by construction, workers compiled per representation instead of per pair, and a static call when the value is passed on to a function with either bound. Rule 2 remains the general case for types projected separately. On the library side, a bundle trait names a combination, `@trait Table{R} <: (ColTable{R}, RowTable{R})`, so that `summary(t::Table)` needs one bound.

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

- **Defaults are evaluated inside.** Plain Julia evaluates a default in the method's scope, with the earlier arguments at hand, and so does the trait world: in the worker, after projection, so `baseline = t` sees the trait object and `i = ncols(t)` may call an operation. A positional default is what Julia makes of it, a shorter exported method whose body calls the full one with its own trait object (rule 2). Evaluating defaults at the entry instead would run trait-world code in ordinary code, on the user's value rather than its projection.
- **The entry projects, the worker sorts.** The entry point projects every bounded argument, positional or keyword, and passes the supplied keywords on as a named tuple; the worker fills the defaults and calls the body. The sorter is compiled per set of supplied keywords, by name and type, and the body once per full signature, as Julia does it, so an omitted keyword costs nothing and a constant default folds.
- **A keyword is typed like a positional argument:** by a trait bound, a declared type, or the value supplied. A declared type is asserted at the entry, as plain Julia asserts keyword types; a trait bound projects, and a value whose type does not conform is refused at the entry, as in a positional position. A bounded keyword without a default is required, as in plain Julia.
- **No dispatch on keywords,** as in plain Julia. A trait bound on a keyword chooses no method; it projects and restricts, so the dispatch rules above need no amendment, and the ambiguity of two unrelated bounds cannot arise through a keyword.
- **A default for a bounded parameter** is trait-world code whose value is either a trait object of that trait, passed on by rule 2, or a value of a representation the trait is implemented for, taken in without projection. Its type is inferred when the worker is compiled, with the other concreteness checks; a default of another type is an error there, not at a call.
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

### Trait wrappers: code written without traits

Most code was written without traits. A trait wrapper brings such a package into the trait world and stands in for its owner there: everything the trait world needs to know about the package lives in the wrapper, and a library written with traits needs none. Base, Core and the standard libraries are the first wrapped package, through the Base wrapper.

Base is in the trait world wholesale, and so is what a wrapper admits of its package: membership is a property of compiled code, decided by the check, not a property of a package's name. Base's source handles any value, so it is not trait-world code. A specialization of a Base method at trait-world types, reached from a worker, is trait-world code when it passes the check below. Julia's package images already hold such specializations; the design adds that nothing above can invalidate them.

A value without parts, a `Float32`, a `String`, is a trait-world value wherever it was made. A value with parts is one when all its parts are, a handle excepted, whose part nothing reaches (Calls upward), and the check accepts a value when its type decides that: `Vector{Float64}` does, `Vector{Any}` does not. A specialization's values come from four places, and each is closed:

- **Arguments** are translated by their bound at the entry, or admitted as trait-world values. A type that decides, deeply concrete, is admitted by its type; a type that does not decide, a field declared `Real`, a `Vector{Any}`, has its abstract parts walked by the entry, at a cost proportional to them, and concrete mode reports such an argument type. Representations must decide by their type (How a type conforms to a trait).
- **Globals** it reads must have a trait-world type: a constant or typed binding, deeply concrete. `ENV` passes; `stdout`, the logger's state and `Main` do not.
- **Constructors** make values from parts and add nothing to check.
- **Calls** return values of specializations checked the same way, Base's and any wrapped package's, transitively, on static paths. A dynamic site inside selects at run time, and the dispatch check of rule 4 admits only a method of an owner or a delegate of the function or of an argument type, so the target is Base's, an owner's, a delegate's, or a refusal; the target's specialization is checked when it compiles, which a build enumerates and a session reaches at the first call.

What of the package passes is decided by the check, as for Base: the wrapper's author runs it at the wrapper's build and learns how much, for a solver most of `solve`. A plotting system as written today passes nowhere and is not wrapped but called (Calls upward). A wrapper holds three things:

- **The implementations it delegates to.** A package split into a core of types and functions and implementation packages, StaticArraysCore with StaticArrays, ColorTypes with Colors, ColorVectorSpace and ImageCore, StatsAPI with StatsBase, has its behaviour outside the core: with the core alone an `SArray` has no `size`. The core's wrapper names the implementations and depends on them, so they are loaded whenever the core's types can enter the trait world, and as delegates their methods are the core's (rule 3). An implementation it does not name is a pirate of the core, refused at its load (Sealing), so the wrapper names every implementation in use.
- **Conformances and doors.** Which of the package's types conform to which traits, declared as the Base wrapper declares Base's families (Traits over existing functions), and which of its functions are doors.
- **Tolerations,** of pirates in the dependencies it seals with its package (Sealing).

A wrapper decides what trait-world code compiles against, so a package has at most one wrapper in an environment: a second is refused at its load, and trait modules and other wrappers reach the package through it, as a GeometryBasics wrapper reaches `SArray` through the StaticArraysCore wrapper. When the package adopts traits it owns itself, and its wrapper becomes a re-export.

Base qualifies although it was written without traits because Core, Base and the standard libraries of one Julia version depend only on each other and ship together, so rule 1 holds by construction and rule 3 by designation, with Julia as one owner; the standard libraries of the system image are in every view, so LinearAlgebra's methods on Base's functions are seen everywhere, and a standard library upgraded from the registry is a package with a wrapper of its own. `Main`, the REPL and Pkg are ordinary code. The Base wrapper also carries the traits over Base's informal interfaces, `Indexable` over `getindex` with its conformances for Base's families, so the curation the note asks for has an owner. The standard libraries of the system image are part of Julia and come in through the Base wrapper: most pass the check as Base does, LinearAlgebra, Random, Dates, Statistics; for those with inward doors the Base wrapper declares calls with checked results, Distributed's `remotecall_fetch(f, …)::Vector{Float64}`, whose deserialized result is checked at the boundary and is then a trait-world value whatever its origin, and Serialization's `deserialize`; Logging's sinks are its outward doors. The prototype's check walks the typed code of each worker into Base, with a budget, the door list and the check of globals; on stock Julia it sees static calls only, so a door behind a dynamic call is not found.

### Calls upward: code that stays outside

Code outside the trait world runs for it only as a call upward (rule 1): at a declared signature, through a pointer, with no inference edge, the result translated by its bound, so no worker's cache depends on anything behind it. One mechanism has three uses: a function handed down, bounded by `Callable` (Function arguments); a declared call to a named function of a package that stays outside, `@call Makie.scatter!(f, xs, ys)::Nothing`, whose body is ordinary code compiled outside the module's cache, in a package that depends on Makie; and Base's doors. A result that comes back without operations is a handle, the mirror image of a trait object: its content is reached by no operation, `==` and `hash` are identity, `show` prints the handle's type, and `h.ref` and `typeof(h)` are refused; it is a value only to hand to the next call upward.

The doors are Base's functions that make values from non-values, and they have a direction. Outward doors send trait-world values up and return nothing: logging, `display`, printing to `stdout`. They are calls upward with no inference edge, allowed, reported by concrete mode as dynamic calls, and nailed to the application's declared sinks in a build. Inward doors bring values in: `eval`, `invokelatest`, deserialization, reflection over the method table, `getglobal` on a module, task storage, raw memory. They are allowed only as declared calls with a checked result, and since no bound admits a value denoting code from above, a `Module`, a `Type`, a `Method`, a bare function, reflection and `eval` as sources of values stay out on their own. The door list lives in the Base wrapper, and with the implementations and conformances that wrappers name it is all that is curated here; the rest is structural. A Base function that reaches a door at some specialization falls out there: on a static path when the worker is compiled, behind a dynamic site when the target compiles, which a build enumerates and a session reaches at the first call; the finding names the worker and the line, and concrete mode reports the dynamic sites, so a module that claims the closure runs with it on. `print(io, x)` on an `IOBuffer` is in, `rand()` is in, `task_local_storage()` is out, and `print(x)` is a dynamic call.

A package whose work is state and effects, a plotting system, passes the check nowhere and is never wrapped: trait-world code calls it. Declared calls add no methods and decide nothing about what trait-world code compiles against, so anyone may declare them, and any number of packages may declare calls into one package.

```julia
module Plots                            # a trait package that calls Makie; the syntax is a sketch
using Makie
@trait_module module Surface
    export figure, scatter!, save
    @trait PointSeries{R} begin
        xs(r::R)::Vector{Float64}
        ys(r::R)::Vector{Float64}
    end
    @handle Figure                                            # a value from Makie, opaque inside
    figure() = @call Makie.Figure()::Figure                    # declared calls: no inference into Makie
    scatter!(f::Figure, t::PointSeries) = @call Makie.scatter!(f, xs(t), ys(t))::Nothing
    save(path::String, f::Figure) = @call Makie.save(path, f)::Nothing   # Makie's globals and effects live behind the call
end
end
```

- **Globals become declared calls.** Trait-world code never reads a Makie global: the current figure is a call returning a handle, the theme a call taking trait-world values and returning nothing, `display` a call returning nothing. The package also fixes the trait-world spelling of Makie's concepts, colors as tuples, markers as symbols, attributes as named tuples.
- **Compiled code lives where rule 4 puts it.** The trait module's workers are in the package's trait-world cache, whose view excludes Makie (rule 4); Makie is reached only through declared calls. Makie's code at the declared signatures is ordinary code: in Makie's image for what Makie precompiles, otherwise in this package's, whose precompile workload is exactly the declared signatures, so time to first plot from a trait module equals an ordinary module's. Redefining a Makie method invalidates that cache as today and nothing in the trait world; the pointer is refreshed by world age at the next call. In a build the declared calls are targets compiled as ordinary code, and whether Makie trims is Makie's problem.
- **One surface, by convention.** A handle type belongs to the package that declares it, so trait packages that pass figures to each other share one package of declared calls into Makie, whose image then holds Makie's code at those signatures once. That is a convention among trait packages, not a kind of package.
- **Audited, not sealed.** What lies behind declared calls is in no view (rule 4), so its pirates change no trait-world code: the package's build reports the pirates in Makie's tree, as Aqua does today, as the place from which to push fixes upstream, and sealing leaves it alone.

### Sealing

Sealing is rule 3 enforced at the load, over rule 4's views: every package in a worker's view is sealed by the load that brings it there. Loading a trait package seals it, so nobody pirates `Columns` at its types; loading a wrapper seals the package it wraps, the implementations it names, and their dependencies; the Base wrapper, implicit in every trait module, seals Julia. Code reached only by calls upward is in no view and is never sealed. From then on a definition that would pirate a sealed package is refused: a method on functions and types all owned by sealed packages, by a package that is neither an owner nor a delegate of any of them (rule 3). `Base.convert` for Base's types from anywhere but Base is one; OffsetArrays' `getindex` for Base's ranges, which changes what a working Base method returns, is another.

- **Refuse at the load, never at a call.** The place of refusal is where methods enter the table: for a package image, before any of its methods is inserted, so that a refused package is absent rather than half loaded, which needs a transactional image load (trade-off 8); for code evaluated later, at the definition; for a seal that arrives after the pirate, at the seal's load, naming the pirate. A refusal at the pirate's precompile is an early warning only, since a compile cache made in another environment is reused. The method table itself stays plain Julia's. An earlier version of this note kept the pirate and poisoned the affected code to raise at the call, which fails late; making the pirate invisible inside the trait world was rejected twice, because one method with two versions disagrees silently across the worlds. A wrapper's own load checks the session as it stands, and a pirate that it does not declare as tolerated fails that load in strict mode.
- **Owners keep their freedom.** Adding methods for your own types to any function, implementing traits for your own types and redefining your own code all work as today. Julia counts as one owner, and an owner can delegate, for example to a package extension that implements its trait (rule 3). Sealing freezes nothing.
- **The opt-out is plain Julia.** A pirate that is tolerated, declared by a wrapper or accepted per package in a project, recompiles the signatures it touches against it, with a warning; the two worlds always agree, and the guarantees hold for everything it does not reach. The interim is this with everything tolerated: warn and recompile by default, refusal as the strict mode, until the ecosystem passes, which Aqua's piracy check already pushes it towards. On stock Julia the prototype's default warns and keeps the pirate; its refuse mode deletes the pirate's methods after the load, since stock Julia cannot refuse one, which makes it depend on the load order.
- **What you get.** In a session whose packages are trait packages, wrappers and their dependencies, nothing pirates what the trait world compiles against, in whichever order they load: every cache stays valid, every worker runs against what it was compiled for, and a build sees the whole trait world. Base is sealed in any session that uses traits at all, and the sealed region is what the project file says: its trait packages and the wrappers they load.
- **Measured on Makie's tree.** Sealing Makie's whole dependency tree on the prototype found 1091 pirate methods. 1042 are implementations of split cores, StaticArrays for StaticArraysCore (794), Colors, ColorVectorSpace and ImageCore for ColorTypes (226), StatsBase for StatsAPI (22), which their cores' wrappers name wherever trait-world code uses those types, and which lie behind calls upward otherwise. Of the other 49, OffsetArrays' 12 methods and one deprecated StatsBase method are on Base's functions at Base's types, refused or tolerated in every session that loads them; once DataFrames is wrapped, which seals DataAPI, so are Tables' 4 and StatsBase's 3 methods of DataAPI's functions at Base's types; the remaining 29 lie behind the calls into Makie.

## Trade-offs

The design restricts what trait-bound code may do, and only there. Its most important costs:

1. **Calls out are calls upward.** Code in a trait module reaches a package that stays outside, such as Makie, only through declared calls, with handles for what comes back (Finer points). A package whose work is state and effects, which is what Makie as written is, is reached that way and never run inside.
2. **A stranger's piracy refuses a load.** Once a sealed package is loaded, loading a pirate fails, naming it. The error reaches whoever loads the pirate, not its author, and the opt-out is plain Julia for the signatures it touches. This is the most contested part. Measured on Makie's tree, 1042 of 1091 pirates are implementations their cores' wrappers would name; of the 49 others, 13 pirate Base itself, the rest sibling packages' functions at Base's types, most behind calls upward (Sealing).
3. **Values crossing in must be closed.** Arguments from ordinary code must be trait objects, `Callable` functions, or values of trait-world types: a type that decides is admitted by its type, any other is walked at the entry, at a cost proportional to its parts. Base's outward doors, `stdout`, the logger and `display`, are dynamic calls upward; its inward doors, `eval`, deserialization and reflection, are available only as declared calls with a checked result.
4. **Trait objects go in, not out.** Code in a trait module never sees the user's type, so it cannot build a new value of it: a function that returns "a table like the input" needs a constructor operation declared in the trait, an inverse of the projection. A value used under two traits is projected twice unless its type declares one projection for both, and whether a change through one view shows through the other depends on whether the projections share data (rule 2).
5. **Types come first.** A type that matches a type-annotated method takes it, even when it also has a projection for a trait-bounded method of the same function: a user's subtype of `AbstractMatrix` then runs as ordinary code. Reaching the trait method needs a type that no type method catches, or a newtype.
6. **Code written without traits is curated.** Capability traits with their conformances for Base's families, and each wrapper's implementations and conformances, are declared by hand: a type nobody declared does not conform, even when it has the methods, and a package has one wrapper per environment.
7. **Dynamic operations and dynamic calls are indirect.** A type whose own operations run at a shared representation, instead of being its own representation, pays an indirect call per use: on the prototype 6.3 ns, 7× plain Julia for a per-element operation. A function from above passed as a dynamic call is an indirect call too, about 4 ns; the library sets the default and the caller may override it per value. Implementations for a Base-typed representation can come only from the trait's owner or a delegate it names. Representations must be deeply concrete, so views get materialized.
8. **Runtime work, not yet proven.** Trait-bound code needs its own compiled instances, so Base code used by both worlds compiles twice, plus an invalidation filter, a dispatch check, a hook on method insertion that refuses a pirate before an image's methods enter the table, and the check of globals and doors on compiled code. None of this exists yet, and whether layering accounts for all load-time invalidation is not yet measured. The prototypes show one requirement on that runtime: its entry code must have no static inference edge into Base's generic code, such as formatting an error message from untyped values, or loading DataFrames or Makie invalidates every entry.
9. **Smaller restrictions.** Offering traits is per module and bottom-up: a package converts its own modules one at a time, from the bottom of its dependencies up, while using packages written without traits, wrapped or through calls upward, is not. One semantic exception (inference-dependent element types), and the ownership rule's orphan case: implementing a foreign trait for a foreign type needs one of their owners, a delegate or a newtype.

## Possible extensions

### Smaller extensions

- **Constructor operations.** A trait may declare how to build a value of the user's type from a representation, so trait modules can return values like their inputs.
- **Representation maps for supertraits.** `@trait B <: A` is already relied on by rule 2, by dispatch and by bundle traits; open is the syntax of the map by which B's operations call A's statically.
- **Inline entries.** Callers that already know the type inline the projection lookup and call the worker directly.
- **Concrete mode by default.** Warnings for every worker, so the cliff is caught before anyone opts in.

## Other options considered

- **One representation per type:** each type projects once, for every trait it joins. Rejected as too restrictive: what a type means differs between traits, so rule 2 keeps one view per bound.
- **The edge-level rule:** let trait-bound code call ordinary packages freely, but compile only concrete calls against the current methods and make abstract ones dynamic. Rejected for its built-in cliff at abstract calls, copies of much library code, and no closed world for AOT.
- **Absorbing dependencies:** each package brings its ordinary dependencies into its own world. Rejected because two packages that absorb Makie conflict as soon as one defines a recipe.
- **Deriving conformance from the methods that exist:** a type is `Indexable` if `length` and `getindex` have methods for it. Rejected: Base's fallbacks exist and throw, types conform by accident, and whether a call infers changes with what is loaded.
- **Trait bounds that compete with types:** trait-bounded methods ranked like abstract types, with ambiguities found where a type with a projection meets a type method. Rejected because the conflict would surface only in an application that loads both packages.
- **Explicit wrapping at the call:** `f(ColTable(x))`, with trait objects as nominal types. Rejected because adopting traits would change every caller.
- **Function types in the type system:** arrow types such as `Float64 -> Float64`. A far larger change to Julia than one trait whose only operation is checked at every call.
- **Better invalidation precision:** invalidate only code whose dispatch really changes. Largely upstream in Julia 1.12 already, and not enough on its own.
- **A global invalidation filter:** ignore later definitions everywhere. Unsound for ordinary code.

Measurements, proof-of-concept results, the detailed tables (caching, ownership, open issues, staging) and the full comparison of these options are in `writeup/design-findings.md` in the repository, with the earlier forms of this design and why they changed; the prototypes of this design are described with all their results in `poc/world/README.md` (TraitWorld) and `poc/interfaces/README.md` (the prototype around DataFrames and Makie).
