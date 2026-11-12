# Traits by example

This page builds a small geometry library with traits, one step at a time, and uses every part of the trait language on the way. Each step links to the precise rules in [Traits: the reference](../reference/traits.md). Why traits exist, and what they buy, is in [Traits for Julia](traits-for-julia.md). The terms are in the [glossary](../glossary.md).

Every example runs as written on the unified build. The scripts are in [`experiments/docs-examples/`](../../experiments/docs-examples/), with a README that says how to run them: `tutorial.jl` runs §2–§17 and checks every result stated here, `strict.jl` runs §18.

## Contents

1. [Setting up](#1-setting-up)
2. [Declaring a trait](#2-declaring-a-trait)
3. [Joining a trait](#3-joining-a-trait)
4. [Methods at a trait](#4-methods-at-a-trait)
5. [Forwarding to a field](#5-forwarding-to-a-field)
6. [Traits with fields](#6-traits-with-fields)
7. [Several traits on one value](#7-several-traits-on-one-value)
8. [Defaults, and when overrides are fixed](#8-defaults-and-when-overrides-are-fixed)
9. [Keywords, defaults and varargs](#9-keywords-defaults-and-varargs)
10. [Types first, then traits](#10-types-first-then-traits)
11. [Results like the input](#11-results-like-the-input)
12. [Collections of mixed types](#12-collections-of-mixed-types)
13. [Parameters](#13-parameters)
14. [Functions as arguments: `Callable`](#14-functions-as-arguments-callable)
15. [Abstract types and traits as members](#15-abstract-types-and-traits-as-members)
16. [When something does not fit](#16-when-something-does-not-fit)
17. [Asking for concrete types](#17-asking-for-concrete-types)
18. [Strict mode](#18-strict-mode)
19. [Traits in a package](#19-traits-in-a-package)
20. [Planned](#20-planned)

---

## 1. Setting up

You need the unified build of Julia 1.13 (`julia-unified/` in this workspace) and the TraitWorld package. TraitWorld does not run on stock Julia.

The library is a *trait module*: an ordinary module that declares `@trait_module` before its first method. Traits, memberships and methods at traits work in any module; a trait module adds checks and compiles its code in the facts mode. The user's code is ordinary Julia.

```julia
using TraitWorld

module Geometry
using TraitWorld
@trait_module
export Shape, area, perimeter, describe, ratio, bigger, title    # and the names added below

# the library's traits and methods go here
end

using .Geometry
```

The sections below show the library in parts, each marked "In `Geometry`". All of them go inside the one module, in the order shown. The complete module is in `experiments/docs-examples/tutorial.jl`.

Rules: [reference §13](../reference/traits.md#13-scopes-trait-modules).

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

- `Shape` is an abstract type. It has no members yet.
- `area` and `perimeter` are **operations**: generic functions, declared with their result types.
- `describe` has a body: it is a **default**, written in terms of the other operations. It is the trait's own method for `describe`; a member may keep it or define its own.

Rules: [reference §4](../reference/traits.md#4-declaring-a-trait).

---

## 3. Joining a trait

A type becomes a **member** by a declared **membership**, `@implement`. It is never inferred from the methods that happen to exist. The user's code below is ordinary Julia, after `using .Geometry`.

**The type serves the operations itself.** Define the methods, then declare the membership in one line:

```julia
struct Circle
    r::Float64
end
Geometry.area(c::Circle) = π * c.r^2
Geometry.perimeter(c::Circle) = 2π * c.r
@implement Shape Circle            # checked now: both operations exist, with the declared results
```

`Circle` keeps the default `describe`.

**The operations in a block.** The block defines the methods and declares the membership together. Here `Rect` also defines its own `describe`:

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

**A member is a subtype.** The operations are ordinary generic functions, and the default is a method at `Shape`, so every caller reaches it:

```julia
Circle <: Shape            # true
Circle(1.0) isa Shape      # true
area(Circle(1.0))          # 3.141592653589793: Circle's own method
describe(Rect(2.0, 3.0))   # "a 2.0 by 3.0 rectangle": Rect's own method, from its block
describe(Circle(1.0))      # "a shape of area 3.141592653589793": the trait's default
```

**Who may write `@implement`:** the package that defines the trait, or the package that defines the type. Here the user's code defines `Circle` and `Rect`, so it may.

Rules: [reference §3.1](../reference/traits.md#31-membership), [§5](../reference/traits.md#5-joining-a-trait), [§12.1](../reference/traits.md#121-who-may-declare-a-membership).

---

## 4. Methods at a trait

A method whose argument is typed by a trait accepts a value of any member type.

In `Geometry`:

```julia
ratio(s::Shape) = area(s) / perimeter(s)
bigger(a::Shape, b::Shape) = area(a) > area(b)
title(s::Shape) = uppercasefirst(describe(s))
```

Inside, `s`, `a` and `b` are the user's values themselves. From the user's code:

```julia
ratio(Circle(1.0))                      # 0.5
ratio(Rect(2.0, 3.0))                   # 0.6
bigger(Rect(2.0, 3.0), Circle(1.0))     # true
title(Circle(1.0))                      # "A shape of area 3.141592653589793": the default
title(Rect(2.0, 3.0))                   # "A 2.0 by 3.0 rectangle": Rect's own
```

**Fully bounded and open.** A method that reaches its argument only through the trait is *fully bounded* there. It may:
- call the trait's operations;
- read the trait's declared fields (§6), and write them unless they are `@const`;
- pass the argument on to another argument typed by the trait;
- call any Julia code on ordinary values, such as the `Float64` that `area` returns.

Anything else makes it *open* at that argument: passing it to an ordinary function (`length(s)`), asking `typeof(s)`, capturing it in a closure. A trait module refuses an open method where it is defined ([§16](#16-when-something-does-not-fit)); `@open` before a method allows it.

**What it is compiled for: `Compiled` and `Dynamic`.** Each trait argument at each call has an *attribute*. The results are the same; only the speed differs.
- **`Compiled`:** `ratio` runs code compiled for the value's type: once for `Circle`, once for `Rect`, as plain Julia compiles per type.
- **`Dynamic`:** `ratio` runs code compiled once, at `Shape`. Each operation on `s` dispatches when it runs, and its result has the declared type.

**What decides, strongest first:**
1. **A cast at the call:** `compiled_for(x)` or `with_dynamic(x)`.
2. **An attribute the value carries:** an argument keeps its attribute when the code passes it on, and a `Dynamic{Shape}` (§12) is `Dynamic`.
3. **The library's choice:** `@specialize s::Shape` or `@nospecialize s::Shape` at an argument, or the module's option `dynamic`.
4. **The trait's default:** `@default_dynamic` or `@default_compiled` in its body.
5. **Otherwise, for a method of a trait module, what the caller knows:** a caller compiled with the value's type passes `Compiled`. The prompt, or an item of a `Vector{Any}`, passes `Dynamic`. So the calls above, typed at the prompt, run the code compiled once. For a method outside a trait module the argument is `Compiled`, as Julia compiles a method at an abstract type.

```julia
circle_ratio(c::Circle) = ratio(c)    # in a function: Compiled, compiled for Circle
ratio(compiled_for(Circle(1.0)))      # at the prompt: Compiled, by a cast
ratio(with_dynamic(Circle(1.0)))      # Dynamic, by a cast
```

Rules: [reference §6](../reference/traits.md#6-methods-at-traits), [§7.3–§7.6](../reference/traits.md#73-fully-bounded-methods).

---

## 5. Forwarding to a field

A type that holds a shape can join through that field.

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

area(Tile("door", Rect(1.0, 2.0)))                  # 2.0
ratio(Tile("door", Rect(1.0, 2.0)))                 # 0.3333333333333333
ratio(Window(Rect(3.0, 3.0), Rect(1.0, 2.0)))       # 0.3333333333333333
describe(Tile("door", Rect(1.0, 2.0)))              # "a 1.0 by 2.0 rectangle": Rect's own, at the field
```

- Forwarding is always written with `by`. Without it, `@implement Shape Tile` would say that `Tile` serves the operations itself, and fail.
- The membership defines `Tile`'s own method for each required operation, calling it on the field; an operation with a default is served by the trait's method, which calls it on the field.
- The field's type must be a member by its own methods. Forwarding does not chain.

Rules: [reference §5.5](../reference/traits.md#55-forwarding-with-by).

---

## 6. Traits with fields

A trait may declare fields, as a struct does. Code at the trait reads and writes them.

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
    name::String
    pages::Int
end
@implement Named Book

sp = Sprite("ball", 0.0, 0.0, Circle(0.5))
move!(sp, 1.0, 2.0)
(sp.x, sp.y)                       # (1.0, 2.0): the write reached the user's object
greet(sp)                          # "hello, ball"
greet(Book("Julia", 300))          # "hello, Julia"
```

- A declared field is the member's stored field of that name. `p.x` reads it in place.
- A writable field needs a mutable type, a field that is not `const`, and exactly the declared type: an immutable `struct Frozen; x::Float64; y::Float64; end` is refused as a `Placed` (`ImplementError`). `@const` fields may be in immutable types.

Rules: [reference §4.3](../reference/traits.md#43-fields).

---

## 7. Several traits on one value

`Sprite` can also be a `Shape`, through its `body` field:

```julia
@implement Shape Sprite by body    # forwards to `body`, a Circle
```

A method may require several traits of one argument, with an intersection. In `Geometry`:

```julia
report(s::All{Shape, Placed}) = "$(describe(s)) at ($(s.x), $(s.y))"
```

```julia
report(sp)                         # "a shape of area 0.7853981633974483 at (1.0, 2.0)"
Sprite <: All{Shape, Placed}       # true
Circle <: All{Shape, Placed}       # false
```

- The value must be a member of each trait. Each may be served differently: `Shape` by the field `body`, `Placed` by `Sprite`'s own fields.
- A library can name an intersection with a `const`: `const Sprite2D = All{Shape, Placed}`.

Rules: [reference §3.6](../reference/traits.md#36-intersections).

---

## 8. Defaults, and when overrides are fixed

`Circle` uses the default `describe`. That choice is part of its membership, fixed when `@implement Shape Circle` ran. Compiled code depends on it.

So a later method is refused where it is defined:

```julia
Geometry.describe(c::Circle) = "a circle"     # ImplementError: define it before the membership, or in its block
title(Circle(1.0))                            # "A shape of area 3.141592653589793": unchanged
```

To define a member's own method for an operation with a default, define it before `@implement`, or in its block, as `Rect` did.

Rules: [reference §4.2](../reference/traits.md#42-defaults), [§5.11](../reference/traits.md#511-overrides-and-redeclaration).

---

## 9. Keywords, defaults and varargs

They work as in plain Julia.

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
fits(Circle(1.0); within = 42)                   # TypeError: 42 is no Shape
```

- A keyword may be typed by a trait, like `within`. It selects no method, as in Julia.
- The elements of a vararg may be of different types: `largest` takes a `Circle`, a `Rect` and a `Tile` at once.

Rules: [reference §6.6](../reference/traits.md#66-keywords-defaults-varargs).

---

## 10. Types first, then traits

A trait is an abstract type, and dispatch is Julia's, with one rule for ties: a type's own supertypes rank before a trait.

In `Geometry`:

```julia
kind(v::AbstractVector) = "a vector"
kind(s::Shape) = "a shape"
kind(x) = "something else"
```

```julia
kind([1.0, 2.0])      # "a vector"
kind(Circle(1.0))     # "a shape"
kind(42)              # "something else"
```

- So a library can adopt traits one function at a time. Existing calls that reached a typed method keep reaching it.
- Two methods at unrelated traits, `f(s::Shape)` and `f(p::Placed)`, are ambiguous for a member of both. The membership that makes a type a member of both reports it; a method at `All{Shape, Placed}` resolves it.

Rules: [reference §6.2](../reference/traits.md#62-specificity), [§6.3](../reference/traits.md#63-ambiguity).

---

## 11. Results like the input

A library sometimes returns "a shape like this one": of the caller's own type.

In `Geometry`:

```julia
@trait Scalable begin
    scale(s::Scalable, k::Float64)::Self
end
@open doubled(s::Scalable) = like(s, scale(s, 2.0))
@open nudged(p::Placed) = withfields(p; x = p.x + 1.0)
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

- `Self` is the member's type, or the forwarding field's: `scale` on a `Tile` returns a `Rect`.
- `like(t, x)` is a value like `t` built from `x`: `x` itself for a member that serves the trait by its own methods; for one that forwards, `t` rebuilt with the field replaced by `x`.
- `withfields(t; …)` is `t` rebuilt with declared fields replaced.
- A method whose result is built by `like` or `withfields` is open at that argument: its result has the member's own type, so it is compiled per type. A trait module accepts it marked `@open` ([§4](#4-methods-at-a-trait)).

Rules: [reference §4.4](../reference/traits.md#44-self), [§6.5](../reference/traits.md#65-results).

---

## 12. Collections of mixed types

A scene holds shapes of different types. Its field is typed by the trait.

In `Geometry`:

```julia
struct Scene
    shapes::Vector{Shape}
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
sc.shapes[1]                      # Circle(1.0): the scene holds the shape itself
sc.shapes[1] isa Scalable         # true, whoever added it

d = Dynamic{Shape}(Circle(2.0))
d isa Shape                       # true
area(d)                           # 12.566370614359172
ratio(d)                          # 1.0
unwrap(d)                         # Circle(2.0)
```

- A `Vector{Shape}` holds members of any type. A shape passed to `add!` is stored as itself, at the prompt and from compiled code alike.
- **`Dynamic{X}`** holds a member of `X` and is itself a member of `X` (and of `X`'s supertraits). Code that receives it runs the code compiled once, at the trait. `Dynamic{Shape}(42)` raises a `TypeError`.
- **A library that wants each item's attribute carried** types its storage `Kept{Shape}`:

  ```julia
  ks = Kept{Shape}[]
  push!(ks, Dynamic{Shape}(Circle(1.0))); push!(ks, Circle(1.0))
  typeof(ks[1]) === typeof(ks[2])   # true: one type, the attribute beside the object
  isdynamic(ks[1])                  # true
  kept_call(area, ks[1])            # 3.141592653589793, by the code compiled once
  kept_call(area, ks[2])            # the same, by the code compiled for Circle
  unwrap(ks[1])                     # Circle(1.0)
  ```

  A method stores its argument there with `push!(ks, keep(s))`: **`keep(s)`** is the argument with the attribute it has in the current code. `keep` is for a `Kept` slot or a struct parameter (§14), not for storage typed by the trait: there it would store a box at one caller and the shape at another.
- `totalarea` is compiled once, whatever the scene holds. `area(s)` on an item tests its type against `Shape`'s members, up to four, and calls each one's method directly; any other member is called through a table. Its result has the declared type, so the loop stays typed.
- A shape type declared later works at once, and discards no compiled code.

Rules: [reference §7.7–§7.9](../reference/traits.md#77-dynamicx), [§8](../reference/traits.md#8-storage).

---

## 13. Parameters

The next steps use a second library, `Signals`, for sequences of samples.

```julia
module Signals
using TraitWorld
@trait_module
export Samples, nsamples, sample, total, mean64     # and the names added below

# the parts below go here
end
using .Signals
```

A trait's parameters are associated types: each member has one value for each.

In `Signals`:

```julia
@trait Samples{T} begin
    T = eltype(Self)                     # T is defined by an equation of Self
    nsamples(s::Samples)::Int
    sample(s::Samples{T}, i::Int)::T
end
@implement Samples{T} Vector{T} where {T <: Real} begin   # a family: every vector of real numbers
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
mean64(s::Samples{Float64}) = total(s) / nsamples(s)     # the type fixes T
```

The user's parametric type joins as a family, its `T` tied to the trait's `T`:

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
Vector{Int} <: Samples{Int}       # true
mean64([1, 2])                    # MethodError: Vector{Int} is a Samples{Int}, not a Samples{Float64}
```

- A parameter is defined by an equation (`T = eltype(Self)`), by a field's type, or stated at the membership (`@implement ArrayLike{Float32, 1} MyVec`).
- An equation always holds. A stated value must agree with it: for a type whose `eltype` is `Any`, `@implement Samples{Float64} Odd` is refused (`ImplementError`).
- Parameters are invariant, as Julia's are: `Samples{Float64}` fixes `T`, `Samples` leaves it open.
- Each member of a family is checked at its first use.

A `where` variable shared between arguments requires equal values, as in Julia:

```julia
module Dots
using TraitWorld, ..Signals
@trait_module
export dotp
function dotp(a::Samples{T}, b::Samples{T}) where {T}
    acc = zero(T)
    for i in 1:nsamples(a)
        acc += sample(a, i) * sample(b, i)
    end
    return acc
end
end
using .Dots

dotp([1.0, 2.0], [3.0, 4.0])     # 11.0
dotp([1.0], [1])                 # MethodError: T is Float64 for one and Int for the other
```

`dotp` is a loop: a generator, `sum(sample(a, i) * sample(b, i) for i in …)`, captures `a` and `b` in a closure, which makes the method open ([§4](#4-methods-at-a-trait); [open issue 165](../open-issues.md#2-design)).

Rules: [reference §3.2](../reference/traits.md#32-parameters), [§5.7, §5.8](../reference/traits.md#57-stating-parameters).

---

## 14. Functions as arguments: `Callable`

Julia has no type for "a function from `Float64` to `Float64`". `Callable{A, S}` is the trait of functions called with arguments of the tuple type `A`, returning an `S`.

In `Signals`:

```julia
function transform(f::Callable{Tuple{Float64}, Float64}, s::Samples{Float64})
    out = Vector{Float64}(undef, nsamples(s))
    for i in 1:nsamples(s)
        out[i] = f(sample(s, i))
    end
    return out
end
function sumby(@specialize(f::Callable{Tuple{Float64}, Float64}), s::Samples{Float64})
    acc = 0.0
    for i in 1:nsamples(s)
        acc += f(sample(s, i))
    end
    return acc
end
```

```julia
sin isa Callable{Tuple{Float64}, Float64}       # true: sin has a method at Float64
transform(x -> 2x, [1.0, 2.0])                  # [2.0, 4.0]
transform(compiled_for(x -> x / 2), [1.0])      # [0.5]: the caller casts to Compiled
sumby(abs2, [1.0, 2.0])                         # 5.0
sumby(with_dynamic(x -> x + 1), [1.0, 2.0])     # 5.0: the caller casts to Dynamic
transform(x -> 1, [1.0])                        # TypeError: the result is an Int, not a Float64
transform(uppercase, [1.0])                     # MethodError: uppercase has no method at Float64
```

- A function is a member of `Callable{A, S}` where it has a method for a call at `A`. Its own methods decide it; nothing is declared. Unlike the memberships of §3, `Callable`'s are not declared.
- `S` is checked on return.
- **`Compiled` or `Dynamic`, chosen for speed, never for results** ([§4](#4-methods-at-a-trait)):
  - `Dynamic`, `Callable`'s default: the library is compiled once per signature. A new closure compiles nothing in the library.
  - `Compiled`: the library is compiled for the particular function, at plain Julia's speed. An ODE right-hand side wants this. `sumby` asks for it with `@specialize`.
  - A function Julia defines, such as `abs2`, or one of the library's own package, is `Compiled`.
- A cast by the caller, `compiled_for(f)` or `with_dynamic(f)`, always wins.
- The library calls `f` itself, as `transform` does. Passing `f` on to Base's `map` is a use outside the contract, so the method is open ([open issue 165](../open-issues.md#2-design)).

**Storing a function.** A field typed by `Callable` holds any member:

```julia
struct Threshold
    test::Callable{Tuple{Float64}, Bool}
end
function countif(th::Threshold, s::Samples{Float64})
    n = 0
    for i in 1:nsamples(s)
        th.test(sample(s, i)) && (n += 1)
    end
    return n
end

countif(Threshold(x -> x > 1.0), [0.5, 1.5, 2.5])     # 2
```

`countif` is compiled once, whatever function the threshold holds; each call checks its result.

**A struct parameter bounded by `Callable`.** The parameter records the attribute:

```julia
struct Gate{F <: Callable{Tuple{Float64}, Bool}}
    test::F
end

Gate(x -> x > 1.0)                                                # F is the closure's type: code compiled per function
Gate(Dynamic{Callable{Tuple{Float64}, Bool}}(x -> x > 1.0))       # F is the Dynamic: code compiled once
```

Rules: [reference §9](../reference/traits.md#9-functions-callable), [§8.2](../reference/traits.md#82-a-struct-parameter-bounded-by-a-trait).

---

## 15. Abstract types and traits as members

One membership can make every member of a closed abstract type, or of another trait, a member.

```julia
module Seqs
using TraitWorld
@trait_module
export Sequence, Signal, nvalues, value, energy
@trait Sequence begin
    Base.length(s::Sequence)::Int                       # existing functions as operations
    Base.getindex(s::Sequence, i::Int)::Float64
end
@implement Sequence AbstractVector{Float64}             # every such vector, by Base's own methods
@trait Signal begin
    nvalues(s::Signal)::Int
    value(s::Signal, i::Int)::Float64
end
@implement Signal Sequence begin                        # every Sequence is a Signal
    nvalues(r) = length(r)
    value(r, i) = r[i]
end
function energy(s::Signal)
    e = 0.0
    for i in 1:nvalues(s)
        e += value(s, i)^2
    end
    return e
end
end
using .Seqs
```

A user's type that is a `Sequence` becomes a `Signal` too:

```julia
struct Ring
    vals::Vector{Float64}
end
Base.length(r::Ring) = length(r.vals)
Base.getindex(r::Ring, i::Int) = r.vals[mod1(i, length(r.vals))]
@implement Sequence Ring          # Ring's own methods of length and getindex

energy([1.0, 2.0])        # 5.0
energy(Ring([3.0, 4.0]))  # 25.0
Ring <: Signal            # true: membership is transitive
```

- A block's methods are methods at that type: `nvalues(r::Sequence) = length(r)`.
- A type's own method is more specific and wins.
- A membership of a trait in a trait applies only to a trait without declared fields.
- Each member reached this way is checked at its first use.

Rules: [reference §5.9](../reference/traits.md#59-abstract-types-and-traits-as-members).

---

## 16. When something does not fit

Mistakes are reported where they are made, before a value reaches the library.

**A result of the wrong type**, at `@implement`:

```julia
struct Square
    side::Int
end
Geometry.area(s::Square) = s.side^2          # an Int
Geometry.perimeter(s::Square) = 4.0 * s.side
@implement Shape Square                      # ImplementError: `area` infers Int64, declared Float64
```

**A missing operation**, at `@implement`:

```julia
struct Dot end
Geometry.area(::Dot) = 0.0
@implement Shape Dot                         # ImplementError: no method of `perimeter` at Dot
```

The message names each missing operation with its declared signature, and the type's methods of that function that do not cover it.

**A value of no member type**, at the call: `ratio(42)` raises a `MethodError`, with a hint that names `Shape`.

**A mistake in the library**, where the method is defined. Suppose a library contains:

```julia
module Sloppy
using TraitWorld, ..Geometry
@trait_module
halfarea(s::Shape) = area(s) / 2
outline(s::Shape) = length(s)          # meant: perimeter(s)
end
```

`outline` is open at `s`: `length` is not an operation of `Shape`. The trait module refuses it with a `TraitUseError` that names the line and the use. The check runs against `Shape` alone, before any member type exists.

**A pirate in a trait module.** A trait module may not define a method of a function it does not own for types it does not own:

```julia
module Meddler
using TraitWorld
@trait_module
Base.sum(x::Vector{Int8}) = 0          # OwnershipError
end
```

Rules: [reference §11](../reference/traits.md#11-checks-and-errors), [§12.2](../reference/traits.md#122-pirates).

---

## 17. Asking for concrete types

By default a member's declared fields and parameters may be abstract. Then code reads that part through a dynamic dispatch. A trait that wants a part concrete names it in its body: `Self`, the member's type, or a parameter. *Concrete* means a concrete type, or a `Union` of at most four concrete types, with type parameters concrete in the same sense.

```julia
module Weights
using TraitWorld
@trait_module
export Weighted, weight, wscaled
@trait Weighted begin
    @enforce_concrete_only Self
    weight(w::Weighted)::Float64
end
@implement Weighted AbstractVector{Float64} begin
    weight(a) = sum(a)
end
wscaled(w::Weighted, k::Vector{Any}) = weight(w) * k[1]
end
using .Weights

struct Crate
    data::AbstractVector{Float64}      # an abstract field type
end
@implement Weighted Crate by data      # ImplementError: the forwarding field is not concrete

struct Box
    data::Vector{Float64}
end
@implement Weighted Box by data        # fine
```

- `@warn_on_abstract Self` accepts the membership and warns.
- Without names, the declaration names `Self` and every parameter.

A method can ask the same of its arguments. The names are `where` variables its traits fix, and trait arguments:

```julia
module Strictly
using TraitWorld, ..Signals
@trait_module
export firstsample
@enforce_concrete_only T firstsample(s::Samples{T}) where {T} = sample(s, 1)
end
using .Strictly

firstsample([1.5, 2.0])          # 1.5
firstsample(Real[1.5, 2.0])      # TraitUseError: `T` is Real, which is not concrete
```

`fully_typed` reports the calls whose argument types are not known, with their root cause:

```julia
isfullytyped(fully_typed(Geometry.totalarea, (Geometry.Scene,)))             # true
isfullytyped(fully_typed(Weights.wscaled, (Vector{Float64}, Vector{Any})))   # false: k[1] is Any
```

`@warn_not_fully_typed` or `@enforce_fully_typed`, before `@trait_module` or before one method, checks this when the code first runs.

Rules: [reference §14](../reference/traits.md#14-concreteness-and-fully-typed-mode).

---

## 18. Strict mode

By default, a pirate is followed, as in plain Julia: code compiled by facts that it changes compiles again. Strict mode refuses a pirate that would change such code.

```julia
module Norms
using TraitWorld
@trait_module
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
# PirateError: names the method and the code compiled by facts it would change
sq([1.0, 2.0, 3.0])                 # 14.0: the pirate was never defined
```

- Strict mode applies to code compiled by facts. What it secures: such code is invalidated only by a change of code it depends on.
- A pirate that changes no code compiled by facts is accepted.
- Methods for your own types are never pirates.
- A package extension's method counts as its parent package's change. It is followed, not refused, with a warning where it changes code compiled by facts.
- Strict mode is off by default. It changes nothing at run time.

Rules: [reference §12.3](../reference/traits.md#123-strict-mode).

---

## 19. Traits in a package

This section shows the layout of a package; it is taken from the demonstrators and is not among the scripts.

- A package's module declares `@trait_module` itself, or holds a submodule that does:

  ```julia
  module MyShapes
  using TraitWorld
  @trait_module
  @trait Shape begin … end
  export Shape, area, perimeter
  end
  ```
- **Compiling ahead.** While a package that declares `@implement X T` is precompiled, the methods at `X` that `T` reaches are compiled into its image, and the checks run. A failing check fails the build.
- **Extensions declare memberships,** never methods of the library's internal functions. TraitCSV supports InlineStrings' `String15` in an extension that declares one membership of `Vector{String15}`. Loading InlineStrings then discards none of the reader's compiled code.
- `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program reaches through trait code, for `juliac --trim`. Its report names the targets a build must be told (`add_entrypoints(report)` tells it) and the calls left to run time. No demonstrator builds as a trimmed binary yet: the build refuses a call on a value known only by its trait ([results](results.md#what-is-not-shown-yet)).

Rules: [reference §16](../reference/traits.md#16-compiling-ahead-closed-programs).

---

## 20. Planned

> **Not implemented.** The syntax is the design's; it may still change.

- **Named implementations:** a second way for a type to join a trait, used only where a caller names it, `Via{Fast}(m)` ([reference §17](../reference/traits.md#17-named-implementations)).
- **Keys:** members that a trait sees alike (types that forward to fields of one type, say) sharing one compiled copy. Optional, built late ([reference §7.2](../reference/traits.md#72-the-key)).

The full list, with where each is decided: [reference §18](../reference/traits.md#18-status-index).
