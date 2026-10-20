# Traits by example

This page builds a small geometry library with traits, one step at a time, and uses every part of the trait language on the way. Each step links to the precise rules in [Traits: the reference](../reference/traits.md). Why traits exist, and what they buy, is in [Traits for Julia](traits-for-julia.md). The terms are in the [glossary](../glossary.md).

Every example of an implemented feature runs as written. The scripts are in [`experiments/docs-examples/`](../../experiments/docs-examples/), with a README that says how to run them. A part that shows planned syntax says so in a note.

## Contents

1. [Setting up](#1-setting-up)
2. [Declaring a trait](#2-declaring-a-trait)
3. [Implementing a trait for a type](#3-implementing-a-trait-for-a-type)
4. [Functions bounded by a trait](#4-functions-bounded-by-a-trait)
5. [Forwarding to a field](#5-forwarding-to-a-field)
6. [Traits with fields](#6-traits-with-fields)
7. [Several traits on one value](#7-several-traits-on-one-value)
8. [Defaults, and when overrides are fixed](#8-defaults-and-when-overrides-are-fixed)
9. [Keywords, defaults and varargs](#9-keywords-defaults-and-varargs)
10. [Types first, then traits](#10-types-first-then-traits)
11. [Results like the input](#11-results-like-the-input)
12. [Collections of mixed types: `Dynamic`](#12-collections-of-mixed-types-dynamic)
13. [Parameters and associated types](#13-parameters-and-associated-types)
14. [Functions as arguments: `Callable`](#14-functions-as-arguments-callable)
15. [Generic implementations](#15-generic-implementations)
16. [When something does not conform](#16-when-something-does-not-conform)
17. [Asking for concrete types](#17-asking-for-concrete-types)
18. [Strict mode](#18-strict-mode)
19. [Traits in a package](#19-traits-in-a-package)
20. [Planned syntax](#20-planned-syntax)

---

## 1. Setting up

You need the patched Julia 1.13.2 build (`julia-1.13/` in this workspace) and the TraitWorld package. TraitWorld does not run on stock Julia.

The library is a *trait module*: a module marked `@trait_module`. Bounded functions exist only in trait modules. The user's code is ordinary Julia.

```julia
using TraitWorld

@trait_module module Geometry
using TraitWorld
export Shape, area, perimeter, describe, ratio, bigger, title    # and the names added below

# the library's traits and functions go here
end

using .Geometry
```

**A note on order.** A trait module is defined in one piece. The sections below show the library in parts, each marked "In `Geometry`". All of them go inside the one `@trait_module module Geometry … end`, in the order shown. The complete module is in `experiments/docs-examples/tutorial.jl`.

Rules: [reference §2](../reference/traits.md#2-trait-modules).

---

## 2. Declaring a trait

A trait says what the library needs from a value: operations with declared argument and result types.

In `Geometry`:

```julia
@trait Shape begin
    area(s::Shape)::Float64
    perimeter(s::Shape)::Float64
    describe(s::Shape)::String = "a shape of area $(area(s))"
end
```

- `area` and `perimeter` are **operations**. Each takes the shape first, and declares its result type.
- `describe` has a body: it is a **default**, written in terms of the other operations. A type may keep it or override it.
- Declaring the trait defines no method for any type. No type conforms yet.

Rules: [reference §3](../reference/traits.md#3-trait-declarations).

---

## 3. Implementing a trait for a type

A type joins a trait by a declaration, `@implement`. It is never inferred from the methods that happen to exist. The user's code below is ordinary Julia, after `using .Geometry`.

**The type implements the operations itself.** Define the methods, then declare the implementation in one line:

```julia
struct Circle
    r::Float64
end
Geometry.area(c::Circle) = π * c.r^2
Geometry.perimeter(c::Circle) = 2π * c.r
@implement Shape Circle            # checked now: both operations exist, with the declared results
```

`Circle` keeps the default `describe`.

**The operations in a block.** The block defines the methods and declares the implementation together. Here `Rect` also overrides the default:

```julia
struct Rect
    w::Float64
    h::Float64
end
@implement Shape Rect begin
    area(r) = r.w * r.h
    perimeter(r) = 2 * (r.w + r.h)
    describe(r) = "a $(r.w) by $(r.h) rectangle"
end
```

In the block, the names are the trait's operations, unqualified. The first argument is typed as `Rect`; the others get their declared types.

**Calling the operations.** They are ordinary generic functions. Called from plain code, they reach the type's own methods only:

```julia
area(Circle(1.0))          # 3.141592653589793: Circle's own method
describe(Rect(2.0, 3.0))   # "a 2.0 by 3.0 rectangle": Rect's own method, from its block
describe(Circle(1.0))      # MethodError: Circle uses the default, which serves trait code
conforms(Circle, Shape)    # true
```

Defaults, and the forwarding of [§5](#5-forwarding-to-a-field), serve the library's code: functions bounded by the trait, next.

**Who may write `@implement`:** the package that defines the trait, or the package that defines the type. Here the user's code defines `Circle` and `Rect`, so it may.

Rules: [reference §5.1, §5.2](../reference/traits.md#51-with-a-block-of-methods), [§12.1](../reference/traits.md#121-who-may-implement).

---

## 4. Functions bounded by a trait

A trait in an argument annotation is a **bound**. The function accepts a value of any type that conforms.

In `Geometry`:

```julia
ratio(s::Shape) = area(s) / perimeter(s)
bigger(a::Shape, b::Shape) = area(a) > area(b)
title(s::Shape) = uppercasefirst(describe(s))
```

Inside, `s`, `a` and `b` are *trait objects*: the user's values, seen through `Shape`. From the user's code:

```julia
ratio(Circle(1.0))                      # 0.5
ratio(Rect(2.0, 3.0))                   # 0.6
bigger(Rect(2.0, 3.0), Circle(1.0))     # true
title(Circle(1.0))                      # "A shape of area 3.141592653589793": the default
title(Rect(2.0, 3.0))                   # "A 2.0 by 3.0 rectangle": Rect's override
```

What a bounded function may do with its trait object:
- call the trait's operations;
- read the trait's declared fields (next sections), and write them unless they are `@const`;
- pass it to another bounded function, or to an internal function of the trait module;
- call any Julia code on ordinary values, such as the `Float64` that `area` returns.

What it may not do: pass the trait object to an ordinary function (`length(s)`), return it bare (`bigger(a, b) = area(a) > area(b) ? a : b`), or ask `typeof(s)`. Code outside could then depend on what the trait does not declare. These are reported when the module is defined ([§16](#16-when-something-does-not-conform)). To return "a shape like the input", see [§11](#11-results-like-the-input).

**What it is compiled for.** `ratio` is compiled for what `Shape` can see of its argument: its *key*. For `Circle`, the key is `Circle`, the *receiver type* whose methods serve the operations. So `ratio` is compiled once for `Circle` and once for `Rect`, as plain Julia would.

Rules: [reference §6](../reference/traits.md#6-bounded-functions), [§4](../reference/traits.md#4-keys-what-code-is-compiled-for).

---

## 5. Forwarding to a field

A type that holds a shape can conform through that field.

```julia
struct Tile
    label::String
    shape::Rect
end
@implement Shape Tile by shape     # forwards to its field `shape`

struct Window
    frame::Rect
    pane::Rect
end
@implement Shape Window by pane    # forwards to `pane`; `frame` is invisible to the library

area(Tile("door", Rect(1.0, 2.0)))                  # error: Tile has no method of `area`
ratio(Tile("door", Rect(1.0, 2.0)))                 # 0.3333333333333333
ratio(Window(Rect(3.0, 3.0), Rect(1.0, 2.0)))       # 0.3333333333333333
```

- Forwarding is always written with `by`. No field is special: without `by`, `@implement Shape Tile` would say that `Tile` implements the operations itself, and fail, listing `by shape` as the fix.
- The trait's operations are served by the field's type, `Rect`. So `Rect` is the receiver type, and the key of both `Tile` and `Window` is `Rect`.
- **Both run the code already compiled for `Rect`.** The `label` and `frame` fields are invisible to the library, and a new type that forwards to a `Rect` compiles nothing new in it.
- Forwarding gives the bounded functions the field's behaviour. It adds no methods to `Tile` itself: `area(Tile(…))` called directly from plain code has no method.
- Forwarding does not chain: the field's type must implement the operations itself.

Rules: [reference §5.2, §5.3](../reference/traits.md#53-forwarding-with-by).

---

## 6. Traits with fields

A trait may declare fields, as a struct does. Code bounded by it reads and writes them.

In `Geometry`:

```julia
@trait Placed begin
    x::Float64
    y::Float64
end
move!(p::Placed, dx::Float64, dy::Float64) = (p.x += dx; p.y += dy; nothing)

@trait Named begin
    @const name::String
end
greet(n::Named) = "hello, $(n.name)"
```

The user's types have the fields:

```julia
mutable struct Sprite
    name::String
    x::Float64
    y::Float64
    body::Circle
end
@implement Placed Sprite          # Sprite has `x` and `y`, of type Float64
@implement Named Sprite

struct Book
    title::String
    pages::Int
end
@implement Named Book name => title          # the declared field `name` is stored as `title`

sp = Sprite("ball", 0.0, 0.0, Circle(0.5))
move!(sp, 1.0, 2.0)
(sp.x, sp.y)                       # (1.0, 2.0): the write reached the user's object
greet(sp)                          # "hello, ball"
greet(Book("Julia", 300))          # "hello, Julia"
```

- A declared field is a stored field of the conforming type. A trait object reads it in place: nothing is copied.
- A writable field needs a mutable type, a field that is not `const`, and exactly the declared type. `@const` fields may be in immutable types.
- A trait with fields only has no receiver type. Its key is the fields' types. So every type with two `Float64` fields `x` and `y` runs the same compiled `move!`, whatever else it holds.

Rules: [reference §3.3](../reference/traits.md#33-fields), [§5.4](../reference/traits.md#54-field-mappings).

---

## 7. Several traits on one value

`Sprite` can also be a `Shape`, through its `body` field:

```julia
@implement Shape Sprite by body    # forwards to `body`, a Circle
```

A function may require several traits of one argument. In `Geometry`:

```julia
report(s::(Shape, Placed)) = "$(describe(s)) at ($(s.x), $(s.y))"
```

```julia
report(sp)        # "a shape of area 0.7853981633974483 at (1.0, 2.0)"
```

- The value must conform to each trait. Each trait may be served differently: `Shape` by the field `body`, `Placed` by `Sprite`'s own fields.
- Both views read the same object, so they always agree.
- A library can name a combination as a bundle, `@trait Sprite2D <: (Shape, Placed)`, and write `s::Sprite2D`.

Rules: [reference §6.1](../reference/traits.md#61-bounds), [§3.6](../reference/traits.md#36-supertraits-and-bundles), [§5.5](../reference/traits.md#55-several-traits-at-once).

---

## 8. Defaults, and when overrides are fixed

`Circle` uses the default `describe`. That choice is part of its implementation, fixed when `@implement Shape Circle` ran. Compiled code depends on it, as it depends on a struct's fields.

So a later override is refused:

```julia
title(Circle(1.0))                          # "A shape of area 3.141592653589793"
Geometry.describe(c::Circle) = "a circle"
# ImplementError: `describe` of Shape gets a method for Circle (…), but the implementation
# of Shape for Circle serves it by the trait's default. … define the method before
# `@implement`, or in its block, and restart the session
```

To override a default, define the method before `@implement`, or in its block, as `Rect` did. To change an existing implementation, change the declaration and restart Julia.

Rules: [reference §3.2](../reference/traits.md#32-defaults), [§5.9](../reference/traits.md#59-checks-at-the-declaration).

---

## 9. Keywords, defaults and varargs

They work as in plain Julia. Their defaults are evaluated inside the trait code, so they may use the trait object.

In `Geometry`:

```julia
fits(s::Shape; within::Shape = s, margin::Float64 = 0.0) = area(s) + margin <= area(within)
scaled_area(s::Shape, k::Float64 = 2.0) = k^2 * area(s)
largest(ss::Shape...) = maximum(area(s) for s in ss; init = 0.0)
```

```julia
fits(Circle(1.0); within = Rect(2.0, 3.0))       # true
fits(Rect(2.0, 3.0); within = Circle(1.0))       # false
scaled_area(Rect(2.0, 3.0))                      # 24.0
largest(Circle(1.0), Rect(2.0, 3.0), Tile("door", Rect(1.0, 2.0)))   # 6.0
fits(Circle(1.0); margin = 1)                    # TypeError: margin is declared Float64
fits(Circle(1.0); within = 42)                   # TraitBoundError: 42 conforms to nothing
```

- A keyword may be bounded, like `within`. It is translated at the call; it selects no method.
- The elements of a vararg may be of different types: `largest` takes a `Circle`, a `Rect` and a `Tile` at once.

Rules: [reference §8](../reference/traits.md#8-keywords-defaults-and-varargs).

---

## 10. Types first, then traits

A bounded method ranks below every type annotation, concrete or abstract, and above an untyped method.

In `Geometry`:

```julia
kind(v::AbstractVector) = "a vector"
kind(s::Shape) = "a shape"
kind(x) = "something else"          # untyped, after the bounded method: the fallback
```

```julia
kind([1.0, 2.0])      # "a vector"
kind(Circle(1.0))     # "a shape"
kind(42)              # "something else"
```

- So a library can adopt traits one function at a time. Existing calls that reached a typed method keep reaching it.
- Two bounds that are unrelated, `f(s::Shape)` and `f(p::Placed)`, need a method for both, `f(x::(Shape, Placed))`. Otherwise the module's definition fails with `TraitBoundError`.

Rules: [reference §6.5](../reference/traits.md#65-dispatch-types-first-then-traits).

---

## 11. Results like the input

A library sometimes returns "a shape like this one": of the caller's own type. It declares a **constructor operation** with the result `Self`, and a function whose result is `::Like{s}`.

In `Geometry`:

```julia
@trait Scalable begin
    scale(s::Scalable, k::Float64)::Self
end
doubled(s::Scalable)::Like{s} = scale(s, 2.0)
nudged(p::Placed)::Like{p} = withfields(p; x = p.x + 1.0)
```

```julia
@implement Scalable Circle begin
    scale(c, k) = Circle(k * c.r)
end
@implement Scalable Rect begin
    scale(r, k) = Rect(k * r.w, k * r.h)
end
@implement Scalable Tile by shape  # forwards to its `shape` field, a Rect

doubled(Circle(1.0))                      # Circle(2.0)
doubled(Tile("door", Rect(1.0, 2.0)))     # Tile("door", Rect(2.0, 4.0)): the label is kept
nudged(sp)                                # a new Sprite, x = 2.0; `sp` is unchanged
```

- `Self` is each implementation's receiver type: `Circle` for `Circle`, `Rect` for `Tile`.
- For a type that forwards, the result is the user's object rebuilt with the field replaced.
- `withfields` replaces declared fields, for a trait with fields.

Rules: [reference §3.5](../reference/traits.md#35-self), [§7](../reference/traits.md#7-results-declared-types-like-withfields).

---

## 12. Collections of mixed types: `Dynamic`

A scene holds shapes of different types. Its field is declared with the trait's name.

In `Geometry`:

```julia
struct Scene
    shapes::Vector{Shape}       # in a trait module: Vector{Dynamic{Shape}}
end
Scene() = Scene(Shape[])
add!(sc::Scene, s::Shape) = (push!(sc.shapes, s); sc)
function totalarea(sc::Scene)
    a = 0.0
    for s in sc.shapes
        a += area(s)
    end
    return a
end
```

```julia
sc = Scene()
add!(sc, Circle(1.0)); add!(sc, Rect(2.0, 3.0)); add!(sc, Tile("door", Rect(1.0, 2.0)))
totalarea(sc)                     # 11.141592653589793

d = Dynamic{Shape}(Circle(2.0))   # in plain code, write Dynamic out
area(d)                           # 12.566370614359172
ratio(d)                          # 1.0
```

- `Dynamic{X}` is a value of any type that conforms to `X`. Inside a trait module, a trait's name in a field or a container means its `Dynamic`. Outside, write `Dynamic{Shape}`.
- Storing a trait object where a `Dynamic` is declared keeps it: `push!` in `add!`.
- `totalarea` is compiled once, whatever the scene holds.
- An operation on a `Dynamic` tests the declared implementations first, with direct calls, and falls back to a dynamic call. Its result has the declared type, so the loop stays typed.
- Passed to a bounded function, `ratio(d)`, a `Dynamic` runs the code compiled for what it holds.
- A shape type declared later works at once, and discards no compiled code.

Rules: [reference §10](../reference/traits.md#10-dynamicx-values-of-any-conforming-type).

---

## 13. Parameters and associated types

The next steps use a second library, `Signals`, for sequences of samples.

```julia
@trait_module module Signals
using TraitWorld
export Samples, nsamples, sample, total, mean64     # and the names added below

# the parts below go here
end
using .Signals
```

A trait's parameters are its **associated types**: each implementation has one value for each.

In `Signals`:

```julia
@trait Samples{T} begin
    T = eltype(Self)                     # T is defined by an equation of the receiver type
    nsamples(s::Samples)::Int
    sample(s::Samples{T}, i::Int)::T
end
@implement Samples A where {A <: Vector{<:Real}} begin   # a family: every vector of real numbers
    nsamples(s) = length(s)
    sample(s, i) = s[i]
end

function total(s::Samples)
    acc = zero(sample(s, 1))
    for i in 1:nsamples(s)
        acc += sample(s, i)
    end
    return acc
end
mean64(s::Samples{Float64}) = total(s) / nsamples(s)     # the bound fixes T
```

The user's parametric type conforms as a family, its `T` tied to the trait's `T`:

```julia
struct Series{T}
    data::Vector{T}
end
Signals.nsamples(s::Series) = length(s.data)
Signals.sample(s::Series, i::Int) = s.data[i]
Base.eltype(::Type{Series{T}}) where {T} = T      # so the trait's equation gives T
@implement Samples{T} Series{T} where {T}

total([1.0, 2.0, 3.5])            # 6.5
total([1, 2, 3])                  # 6, an Int: T = Int for Vector{Int}
total(Series(Float32[1, 2]))      # 3.0f0
mean64(Series([1.0, 4.0]))        # 2.5
mean64([1, 2])                    # TraitBoundError: the bound fixes T = Float64, and Vector{Int} has T = Int
```

- A parameter is defined by an equation (`T = eltype(Self)`), by a field's type, or by the implementation (`@implement ArrayLike{Float32, 1} MyVec`, for a trait with no equation for its parameters).
- An equation always holds. `@implement Samples{T} Series{T} where {T}` states `T`, and the stated value must agree with the equation: `eltype(Series{Float32})` must be `Float32`. Without the `eltype` method it is `Any`, and the implementation is refused with `ImplementError`.

> **Planned, not implemented:** the check of a stated value against the equation. Today a stated value replaces the equation's, so the example also runs without the `eltype` method ([reference T-37](../reference/traits.md#19-deviations)).
- A bound may fix a parameter, `Samples{Float64}`, or leave it open, `Samples`.
- Each member of a family is fixed at its first use. Workers compile per member.

> **Planned, not implemented:** naming a parameter with `where` in a bound, `f(s::Samples{T}) where {T}`, and reading `T` in the body. Today such a method is a plain method that never applies. Get the type from a value instead: `zero(sample(s, 1))` above. See [§20](#20-planned-syntax).

Rules: [reference §3.4](../reference/traits.md#34-parameters-and-associated-types), [§5.6, §5.7](../reference/traits.md#57-families).

---

## 14. Functions as arguments: `Callable`

Julia has no type for "a function from `Float64` to `Float64`". A trait module takes a function at a declared signature with `Callable{A, S}`: arguments of the tuple type `A`, a result of type `S`.

In `Signals`:

```julia
function transform(f::Callable{Tuple{Float64}, Float64}, s::Samples{Float64})
    out = Vector{Float64}(undef, nsamples(s))
    for i in 1:nsamples(s)
        out[i] = f(sample(s, i))
    end
    return out
end
function sumby(f::Callable{Tuple{Float64}, Float64, CompiledCall}, s::Samples{Float64})
    acc = 0.0
    for i in 1:nsamples(s)
        acc += f(sample(s, i))
    end
    return acc
end
```

```julia
transform(x -> 2x, [1.0, 2.0])                  # [2.0, 4.0]
transform(compiled_call(x -> x / 2), [1.0])     # [0.5]: the caller asks for a compiled call
sumby(abs2, [1.0, 2.0])                         # 5.0
sumby(dynamic_call(x -> x + 1), [1.0, 2.0])     # 5.0: the caller asks for a dynamic call
transform(x -> 1, [1.0])                        # TypeError: the result is an Int, not a Float64
```

- Any function conforms: closures, callable structs, generic functions. Every call checks the arguments and the result.
- **Two modes, chosen for speed, never for results:**
  - `DynamicCall`, the default: the library is compiled once per signature, and calls the function through a pointer. A new closure compiles nothing in the library.
  - `CompiledCall`: the library is compiled for the particular function, at plain Julia's speed. An ODE right-hand side wants this.
- The library sets the default in the bound (`sumby` asks for `CompiledCall`). The caller overrides it per value with `compiled_call(f)` or `dynamic_call(f)`.
- Functions from Base or from a trait module, such as `abs2`, are called directly in either mode.

**Storing a function.** A library type holds a function as a `DynamicFn{A, S}`, made in plain code by `dynamic_fn`.

In `Signals`:

```julia
struct Threshold
    test::DynamicFn{Tuple{Float64}, Bool}
end
function countif(th::Threshold, s::Samples{Float64})
    n = 0
    for i in 1:nsamples(s)
        th.test(sample(s, i)) && (n += 1)
    end
    return n
end
```

```julia
th = Threshold(dynamic_fn(Tuple{Float64}, Bool, x -> x > 1.0))
countif(th, [0.5, 1.5, 2.5])      # 2
```

Rules: [reference §9](../reference/traits.md#9-callable-functions-at-a-declared-signature).

---

## 15. Generic implementations

One implementation can cover every type that conforms to another trait.

In `Signals`:

```julia
@trait Sequence begin
    Base.length(s::Sequence)::Int                       # existing functions as operations
    Base.getindex(s::Sequence, i::Int)::Float64
end
@implement Sequence A where {A <: AbstractVector{Float64}}    # by Base's own methods

@trait Signal begin
    nvalues(s::Signal)::Int
    value(s::Signal, i::Int)::Float64
end
@implement Signal R where {R: Sequence} begin                # every Sequence is a Signal
    nvalues(r) = length(r)
    value(r, i) = r[i]
end
energy(s::Signal) = sum(value(s, i)^2 for i in 1:nvalues(s); init = 0.0)
```

A user's type that implements `Sequence` becomes a `Signal` too:

```julia
struct Ring
    vals::Vector{Float64}
end
Base.length(r::Ring) = length(r.vals)
Base.getindex(r::Ring, i::Int) = r.vals[mod1(i, length(r.vals))]
@implement Signals.Sequence Ring          # Ring's own methods of length and getindex

energy([1.0, 2.0])        # 5.0
energy(Ring([3.0, 4.0]))  # 25.0
```

- `R: Sequence` reads "`R` conforms to `Sequence`".
- A more specific implementation, for one type, beats the generic one.
- A generic implementation makes members only of a trait without declared fields.

> **Planned, not implemented:** checks that two generic implementations do not overlap. **Open:** what a condition in the `where` braces may say. See [reference §5.8](../reference/traits.md#58-generic-implementations).

Rules: [reference §5.8](../reference/traits.md#58-generic-implementations).

---

## 16. When something does not conform

Mistakes are reported where they are made, before a value reaches the library.

**A result of the wrong type**, at `@implement`:

```julia
struct Square
    side::Int
end
Geometry.area(s::Square) = s.side^2          # an Int
Geometry.perimeter(s::Square) = 4.0 * s.side
@implement Shape Square
# ImplementError: the implementation of Shape for Square does not conform:
#   `area` at Tuple{Square} returns `Int64`, declared `Float64`
```

**A missing operation**, at `@implement`:

```julia
struct Dot end
Geometry.area(::Dot) = 0.0
@implement Shape Dot
# ImplementError: Dot has methods for some operations of Shape but not for perimeter: define them, …
```

**A value of no conforming type**, at the call:

```julia
ratio(42)          # MethodError: no method matching ratio(::Int64), with a hint:
                   # "Argument 1 of `ratio` is bounded by Shape; a Int64 conforms to none of them …"
```

**A mistake in the library**, at the module's definition. Suppose a library contains:

```julia
@trait_module module Sloppy
using TraitWorld, ..Geometry
halfarea(s::Shape) = area(s) / 2
outline(s::Shape) = length(s)          # meant: perimeter(s)
end
```

- Every bounded function is checked once when the module is defined, against `Shape` alone, not against any type. The report names the line: "`length` has no method for a trait object carrying Shape". A trait object can do only what its traits declare.
- In a package being precompiled, this is an error and the build fails. In a script or at the prompt, it is a warning, and the call raises `TraitUseError`:

```julia
Sloppy.halfarea(Circle(1.0))     # 1.5707963267948966
Sloppy.outline(Circle(1.0))      # TraitUseError
```

**A pirate in a trait module.** A trait module may not define a method of a function it does not own for types it does not own:

```julia
@trait_module module Meddler
using TraitWorld
Base.sum(x::Vector{Int8}) = 0
end
# OwnershipError: … is defined by Meddler, which owns neither its function nor its types …
```

**Printing.** Types print by bound and key, not as the machinery's types. A trait object's type, in messages and stack frames, prints as `Shape at Circle`. A `Dynamic` prints as `Dynamic{Shape} at Circle`.

Rules: [reference §11](../reference/traits.md#11-checks-and-when-they-run), [§12](../reference/traits.md#12-who-may-implement-pirates-strict-mode), [§14](../reference/traits.md#14-printing).

---

## 17. Asking for concrete types

By default a key may be abstract. Then the code reads that part through a dynamic dispatch. A trait that wants every key concrete says so in its body.

```julia
@trait_module module Weights
using TraitWorld
export Weighted, weight, wscaled
@trait Weighted begin
    @concrete_only
    weight(w::Weighted)::Float64
end
@implement Weighted A where {A <: AbstractVector{Float64}} begin
    weight(a) = sum(a)
end
wscaled(w::Weighted, k::Vector{Any}) = weight(w) * k[1]
end
using .Weights

struct Crate
    data::AbstractVector{Float64}      # an abstract field type
end
@implement Weighted Crate by data
# ImplementError: field `data` of Crate is declared `AbstractVector{Float64}`, which is not concrete,
# and Weighted asks for concrete keys (`@concrete_only`) …

struct Box
    data::Vector{Float64}
end
@implement Weighted Box by data        # fine
```

`fully_typed` reports the calls whose argument types are not known, with their root cause:

```julia
isfullytyped(fully_typed(Geometry.totalarea, (Geometry.Scene,)))         # true
isfullytyped(fully_typed(Weights.wscaled, (Vector{Float64}, Vector{Any})))   # false: k[1] is Any
```

`@warn_on_abstract` or `@error_on_abstract` in front of `@trait_module`, or of one function, checks this at each worker's first run.

> **Planned, not implemented:** one declaration with a level (silent, warn, error) replaces `@concrete_only`, `@warn_on_abstract` and `@error_on_abstract`. Its spelling is open.

Rules: [reference §3.7](../reference/traits.md#37-concreteness), [§13](../reference/traits.md#13-concrete-mode).

---

## 18. Strict mode

By default, a pirate in plain code is followed, as in plain Julia: trait code it changes compiles again. Strict mode refuses a pirate that would change compiled trait code.

```julia
@trait_module module Norms
using TraitWorld
export Values, vals, sq
@trait Values begin
    vals(v::Values)::Vector{Float64}
end
@implement Values Vector{Float64} begin
    vals(v) = v
end
sq(v::Values) = (s = 0.0; for x in vals(v); s += abs2(x); end; s)
end
using .Norms

sq([1.0, 2.0, 3.0])                 # 14.0: compiled, calling abs2(::Float64)
TraitWorld.strict!(true)            # or start Julia with JULIA_TW_STRICT=1
module Meddler2
Base.abs2(x::Float64) = 2.0 * x * x      # Base's function, Base's type: a pirate
end
# PirateError: strict mode refuses `abs2(Float64)`, defined by Main.Meddler2.
#   It would change what trait-world code computes, at the call `Tuple{typeof(abs2), Float64}`. …
sq([1.0, 2.0, 3.0])                 # 14.0: the pirate was never defined
```

- Strict mode applies to trait code. What it secures: compiled trait code is never invalidated by a pirate. Plain code is not protected by it.
- A pirate that changes no compiled trait code is accepted.
- Methods for your own types are never pirates. A package extension's method counts as its parent package's: where the parent owns the function or a type, it is followed, not refused.

> **Planned, not implemented:** a warning when a package extension's method changes compiled trait code, naming the method and the trait code.
- Strict mode is off by default. It changes nothing at run time.

Rules: [reference §12.3](../reference/traits.md#123-strict-mode).

---

## 19. Traits in a package

This section shows the layout of a package; it is taken from the demonstrators and is not among the scripts.

- A package is an ordinary module around its trait module:

  ```julia
  module MyShapes
  using TraitWorld
  include("GeometryCore.jl")         # @trait_module module GeometryCore … end
  using .GeometryCore
  export Shape, area, perimeter
  end
  ```
- **Compiling ahead.** While a package that declares `@implement X T` is precompiled, the trait code that `T` needs is compiled into its image, and the checks run. A failing check fails the build. In a fresh session, the first call with `T` costs a few milliseconds.
- `TraitWorld.@workload begin … end` adds a precompile workload, as PrecompileTools' `@compile_workload` does.
- **Extensions declare implementations,** never methods of the library's internal functions. TraitCSV supports InlineStrings' `String15` in an extension that contains only this:

  ```julia
  @implement CSVColumn Vector{String15} begin
      parsecell!(c, s, a, b) = b - a + 1 <= 15 ? (push!(c, String15(SubString(s, a, b))); true) : false
      emptylike(c) = String15[]
  end
  ```
  Loading InlineStrings then discards none of the reader's compiled code.
- `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program reaches through trait code, for `juliac --trim`.

Rules: [reference §15](../reference/traits.md#15-compiling-ahead).

---

## 20. Planned syntax

> **None of this is implemented.** Written today, each form fails or means something else, as stated. The syntax is the design's; it may still change.

**A parameter shared between bounds,** and read in the body:

```julia
dot(a::Samples{T}, b::Samples{T}) where {T} = sum(sample(a, i) * sample(b, i) for i in 1:nsamples(a); init = zero(T))
```

Today the annotation is read as a plain type, and the method never applies.

**Forwarding for a whole family:**

```julia
struct Labelled{T}; label::String; data::Vector{T}; end
@implement Samples Labelled{T} by data where {T}   # every Labelled{T} forwards to `data`
```

Today, declare each member: `@implement Samples Labelled{Float64} by data`.

**A function argument with an open result type, or with keywords:**

```julia
apply(f::Callable{Tuple{Float64}, S}, x::Float64) where {S} = f(x)               # S inferred at the call
fit(f::Callable{Tuple{Vector{Float64}}, Float64, @NamedTuple{tol::Float64}}, x::Vector{Float64}) = f(x; tol = 1e-6)
```

Today the first is a plain argument, so the method never applies to a function. The second is refused when the method is defined: today `Callable`'s third parameter is its mode.

**`Compiled` and `Dynamic`, chosen where a value enters:**

```julia
paint(io::IO, m::Mark) = draw(m, io)                    # Compiled where the caller knows m's type, Dynamic where not
paint_once(io::IO, m::Dynamic{Mark}) = draw(m, io)      # compiled once, for every Mark
render(io::IO, ms::Iterable{Mark}) = (for m in ms; paint(io, compiled_for(m)); end)   # each item's own code
@trait Model begin
    @dynamic                                             # values of other types enter as Dynamic{Model}
    rhs!(m::Model, du::Vector{Float64}, u::Vector{Float64}, t::Float64)::Nothing
end
solve(m::Compiled{Model}, u0::Vector{Float64}) = …     # the library asks for code per model type
Plots.paint_once(io, with_dynamic(d))                  # the caller converts
```

Today a `Dynamic` is opened at every bound and every plain value runs code compiled for its type; `Compiled`, `compiled_for`, `with_dynamic` and `@dynamic` are not defined; `x::Dynamic{X}` in a bounded function accepts only `Dynamic` values ([reference §6.6](../reference/traits.md#66-compiled-and-dynamic-how-values-enter)).

**A value seen through several traits:** `Dynamic{(Shape, Placed)}`.

**Membership as subtyping:** `Circle(1.0) isa Shape`, `Circle <: Shape`. Today both are `false`; use `conforms(Circle, Shape)`.

**Named implementations:** `Via{Fast}(m)`, a wrapper that selects a second implementation.

The full list, with where each is decided: [reference §18](../reference/traits.md#18-status-index).
