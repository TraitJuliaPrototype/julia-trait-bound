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
12. [Kept values: collections of mixed types](#12-kept-values-collections-of-mixed-types)
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

Rules: [reference §4.1, §4.2](../reference/traits.md#41-with-a-block-of-methods), [§10.1](../reference/traits.md#101-who-may-implement).

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

**What it is compiled for: `Compiled` and `Dynamic`.** Every value seen through a trait is one or the other. This is its *attribute*. The results are the same; only the speed differs.
- **`Compiled`:** `ratio` runs code compiled for what `Shape` can see of the value, its *key*. For `Circle`, the key is `Circle`: its own methods serve the operations, so it is the *receiver type*. So `ratio` is compiled once for `Circle` and once for `Rect`, as plain Julia would.
- **`Dynamic`:** `ratio` runs code compiled once, for every type. Each operation on `s` dispatches when it runs, and its result has the declared type.

**The rule: values carry. Annotations give defaults where a plain value enters trait code. Explicit casts always win.**
- **Where a plain value enters.** A *plain value* carries no attribute yet. It gets one where it is first seen through a trait, here at the bound. It is `Compiled` if the code that passes it knows its concrete type, and `Dynamic` if not.
  - Inside a function, a value of a concrete type is `Compiled`. A value of an abstract type, such as an item of a `Vector{Any}`, is `Dynamic`.
  - The prompt knows no types. So the calls above, typed at the prompt, pass `Dynamic` values.
- **Values carry.** A value keeps its attribute through calls, bounds and storage. `ratio` passes `s` on to `area` as it came.
- **Defaults.** A library may set the default for plain values. Each default decides only for a value that enters trait code at that place.
  - A trait may declare one in its body: `@default_with_dynamic_self` or `@default_compiled_for_self`.
  - A bound may carry one: `s::Compiled{Shape}` or `s::Dynamic{Shape}`. Such a bound still accepts any value that conforms.
  - Plain values come from plain callers, at the functions a module exports or declares `public`. On any other function, an annotation warns: write a cast at the call instead.
- **Casts.** `compiled_for(x)` and `with_dynamic(x)` are the only casts. A cast always wins. Of two casts, the later wins.

```julia
circle_ratio(c::Circle) = ratio(c)    # in a function: Compiled, compiled for Circle
ratio(compiled_for(Circle(1.0)))      # at the prompt: Compiled, by a cast
ratio(with_dynamic(Circle(1.0)))      # Dynamic, by a cast
```

Rules: [reference §5](../reference/traits.md#5-bounded-functions), [§6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic), [§6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for).

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

Rules: [reference §4.3](../reference/traits.md#43-forwarding-with-by).

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

Rules: [reference §3.3](../reference/traits.md#33-fields), [§4.4](../reference/traits.md#44-field-mappings).

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
- Both traits see the same object, so they always agree.
- A library can name a combination as a bundle, `@trait Sprite2D <: (Shape, Placed)`, and write `s::Sprite2D`.

Rules: [reference §5.1](../reference/traits.md#51-bounds), [§3.6](../reference/traits.md#36-supertraits-and-bundles), [§4.5](../reference/traits.md#45-several-traits-at-once).

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

Rules: [reference §3.2](../reference/traits.md#32-defaults), [§4.9](../reference/traits.md#49-checks-at-the-declaration).

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

- A keyword may be bounded, like `within`. Its value is seen through the trait at the call; it selects no method.
- The elements of a vararg may be of different types: `largest` takes a `Circle`, a `Rect` and a `Tile` at once.
- Bounded keywords and vararg elements get their attribute as positional arguments do ([§4](#4-functions-bounded-by-a-trait)).

Rules: [reference §5.7](../reference/traits.md#57-keywords-defaults-and-varargs).

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

Rules: [reference §5.5](../reference/traits.md#55-dispatch-types-first-then-traits).

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

- `Self` is the type of the value seen through the trait: `Circle` for `Circle`, and `Rect` for `Tile`, which forwards to its `Rect`.
- For a type that forwards, the result is the user's object rebuilt with the field replaced.
- `withfields` replaces declared fields, for a trait with fields.

Rules: [reference §3.5](../reference/traits.md#35-self), [§5.6](../reference/traits.md#56-results-declared-types-like-withfields).

---

## 12. Kept values: collections of mixed types

A scene holds shapes of different types. Its field is declared with the trait's name.

In `Geometry`:

```julia
struct Scene
    shapes::Vector{Shape}       # in a trait module: Vector{Kept{Shape}}, each shape with its attribute
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
sc.shapes[1]                      # Kept{Shape}: Dynamic at Circle: added at the prompt
add!(sc, compiled_for(Circle(1.0)))
sc.shapes[4]                      # Kept{Shape}: Compiled at Circle: the cast is kept

d = Dynamic{Shape}(Circle(2.0))   # in plain code, write the form out
area(d)                           # 12.566370614359172
ratio(d)                          # 1.0
```

- A *kept value* is a value of any type that conforms to a trait, kept where the code does not know its type. It has one of three forms:
  - `Dynamic{X}`, a value whose attribute is `Dynamic`;
  - `Compiled{X}`, a value whose attribute is `Compiled`;
  - `Kept{X}`, a value with either attribute.
- **Inside a trait module, a trait's name in a field or as a container's element type means `Kept{X}`.** `Vector{Shape}` is a `Vector{Kept{Shape}}`. Each value keeps the attribute it came with.
- `Dynamic{Shape}` and `Compiled{Shape}` written there mean those types as written: such a field holds values of that attribute only.
- Outside trait modules, write the form out: `Dynamic{Shape}`, `Compiled{Shape}`, or `Kept{Shape}` for both.
- **Storing keeps the attribute.** `push!` in `add!` stores the trait object as it came. A value read back has the attribute it was stored with.
- A plain value stored where a trait's name is declared is first seen there. It takes the trait's default: `Compiled`, unless the trait declares `@default_with_dynamic_self`.
- **The constructors never change an attribute.** `Dynamic{Shape}(x)` and `Compiled{Shape}(x)` make a kept value from a plain one. Given a value of the other attribute, they refuse with `TraitBoundError`, naming the cast to write.
- `totalarea` is compiled once, whatever the scene holds.
- An operation on a kept value runs the method of the type it holds. Its result has the declared type, so the loop stays typed. The first four implementations declared take the fastest path; any other costs one lookup and an indirect call.
- Passed to a bounded function, `ratio(d)`, a `Dynamic` stays `Dynamic`: the code compiled once runs. `ratio(compiled_for(d))` runs the code compiled for what it holds.
- A shape type declared later works at once, and discards no compiled code.

Rules: [reference §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), [§6.5](../reference/traits.md#65-values-carry), [§6.8](../reference/traits.md#68-costs-and-choosing).

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
    T = eltype(Self)                     # T is defined by an equation of Self
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

> **Planned, not implemented:** the check of a stated value against the equation. Today a stated value replaces the equation's, so the example also runs without the `eltype` method ([reference T-37](../reference/traits.md#17-deviations)).
- A bound may fix a parameter, `Samples{Float64}`, or leave it open, `Samples`.
- Each member of a family is fixed at its first use. Code is compiled per member.

> **Planned, not implemented:** naming a parameter with `where` in a bound, `f(s::Samples{T}) where {T}`, and reading `T` in the body. Today such a method is a plain method that never applies. Get the type from a value instead: `zero(sample(s, 1))` above. See [§20](#20-planned-syntax).

Rules: [reference §3.4](../reference/traits.md#34-parameters-and-associated-types), [§4.6, §4.7](../reference/traits.md#46-stating-parameters).

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
function sumby(f::Compiled{Callable{Tuple{Float64}, Float64}}, s::Samples{Float64})
    acc = 0.0
    for i in 1:nsamples(s)
        acc += f(sample(s, i))
    end
    return acc
end
```

```julia
transform(x -> 2x, [1.0, 2.0])                  # [2.0, 4.0]
transform(compiled_for(x -> x / 2), [1.0])      # [0.5]: the caller casts to Compiled
sumby(abs2, [1.0, 2.0])                         # 5.0
sumby(with_dynamic(x -> x + 1), [1.0, 2.0])     # 5.0: the caller casts to Dynamic
transform(x -> 1, [1.0])                        # TypeError: the result is an Int, not a Float64
```

- Any function conforms: closures, callable structs, generic functions. Every call checks the arguments and the result.
- **`Compiled` or `Dynamic`, chosen for speed, never for results** ([§4](#4-functions-bounded-by-a-trait)):
  - `Dynamic`, `Callable`'s default: the library is compiled once per signature, and calls the function through a pointer. A new closure compiles nothing in the library.
  - `Compiled`: the library is compiled for the particular function, at plain Julia's speed. An ODE right-hand side wants this.
- `Callable`'s default is `@default_with_dynamic_self`. It applies to functions from outside the trait world, such as a closure written in the user's code. Functions from Base or from a trait module, such as `abs2`, are `Compiled` where the code that passes them knows them.
- The library sets a default in the bound: `sumby` asks for `Compiled`. A cast by the caller, `compiled_for(f)` or `with_dynamic(f)`, always wins.

**Storing a function.** In a trait module, `Callable{A, S}` in a field means `Kept{Callable{A, S}}`: the function is kept with its attribute.

In `Signals`:

```julia
struct Threshold
    test::Callable{Tuple{Float64}, Bool}      # in a trait module: Kept{Callable{…}}
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
th = Threshold(x -> x > 1.0)                       # Callable's default: Dynamic
countif(th, [0.5, 1.5, 2.5])                       # 2
Threshold(compiled_for(x -> x > 1.0)).test         # Compiled: the cast is kept
```

`countif` is compiled once, whatever function `th` keeps.

**A struct parameter bounded by `Callable`.** Code over the struct can be compiled per function, when the caller asks. In a trait module, a struct parameter whose bound is a trait or a `Callable` is bounded by it.

In `Signals`:

```julia
struct Gate{F <: Callable{Tuple{Float64}, Bool}}
    test::F
end
countgate(g::Gate, s::Samples{Float64}) = count(i -> g.test(sample(s, i)), 1:nsamples(s))
```

```julia
Gate(x -> x > 1.0)                  # Gate{Dynamic{Callable{…}}}: the same type for every function
Gate(compiled_for(x -> x > 1.0))    # Gate{F} with F the closure's type: compiled per function
countgate(Gate(x -> x > 1.0), [0.5, 1.5, 2.5])   # 2
```

- The struct's constructor is a bound. The value's attribute, by the same rule as at a bounded function, decides the parameter.
- `Dynamic`: the parameter is `Dynamic{Callable{A, S}}`, and code over the struct is compiled once.
- `Compiled`: the parameter is the function's own type, and code over the struct is compiled per function, at plain Julia's speed.

Rules: [reference §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature), [§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait), [§7.5](../reference/traits.md#75-functions-kept).

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

> **Planned, not implemented:** checks that two generic implementations do not overlap. **Open:** what a condition in the `where` braces may say. See [reference §4.8](../reference/traits.md#48-generic-implementations).

Rules: [reference §4.8](../reference/traits.md#48-generic-implementations).

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

**Printing.** Types print by bound and key, not as the machinery's types. A trait object's type, in messages and stack frames, prints as `Shape at Circle`. A kept value prints with its form and attribute: `Dynamic{Shape} at Circle`, `Kept{Shape}: Compiled at Circle`.

Rules: [reference §9](../reference/traits.md#9-checks-and-when-they-run), [§10](../reference/traits.md#10-who-may-implement-pirates-strict-mode), [§12](../reference/traits.md#12-printing).

---

## 17. Asking for concrete types

By default a conforming type, or a trait's parameter, may be abstract. Then the code reads that part through a dynamic dispatch. A trait that wants a part concrete names it in its body: `Self`, the type seen through the trait, or a parameter. *Concrete* means a concrete type, or a small `Union` of them (at most four, as `Union{Missing, Int}`), with type parameters concrete in the same sense, all the way down.

```julia
@trait_module module Weights
using TraitWorld
export Weighted, weight, wscaled
@trait Weighted begin
    @enforce_concrete_only Self
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
# and Weighted asks for a concrete Self (`@enforce_concrete_only`) …

struct Box
    data::Vector{Float64}
end
@implement Weighted Box by data        # fine
```

- `@warn_on_abstract Self` accepts the implementation and warns.
- `@enforce_concrete_only T Self` names a parameter too: `T = eltype(Self)` must then be concrete, so a `Vector{Any}` does not conform.
- Without names, the declaration names `Self` and every parameter.

A bounded function can ask the same of its arguments, for one function. The names are `where` variables its bounds name, and bounded arguments, each standing for its `Self`:

```julia
@trait_module module Strictly
using TraitWorld, ..Signals
export firstsample
@enforce_concrete_only T firstsample(s::Samples{T}) where {T} = sample(s, 1)
end
using .Strictly

firstsample([1.5, 2.0])          # 1.5
firstsample(Real[1.5, 2.0])      # TraitBoundError: `firstsample`: `T` is Real, which is not concrete …
```

`fully_typed` reports the calls whose argument types are not known, with their root cause:

```julia
isfullytyped(fully_typed(Geometry.totalarea, (Geometry.Scene,)))         # true
isfullytyped(fully_typed(Weights.wscaled, (Vector{Float64}, Vector{Any})))   # false: k[1] is Any
```

`@warn_not_fully_typed` or `@enforce_fully_typed` in front of `@trait_module`, or of one function, checks this at a bounded function's first run.

Rules: [reference §11](../reference/traits.md#11-concreteness-and-concrete-mode).

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
- Methods for your own types are never pirates.
- A package extension's method counts as its parent package's change. It is followed, not refused. Where it changes compiled trait code, a warning names the method and the trait code.
- Strict mode is off by default. It changes nothing at run time.

Rules: [reference §10.3](../reference/traits.md#103-strict-mode).

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

Rules: [reference §13](../reference/traits.md#13-compiling-ahead).

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

Today the first is a plain argument, so the method never applies to a function. The second is refused when the method is defined: `Callable` takes two parameters.

**A value seen through several traits:** `Dynamic{(Shape, Placed)}`.

**Membership as subtyping:** `Circle(1.0) isa Shape`, `Circle <: Shape`. Today both are `false`; use `conforms(Circle, Shape)`.

**Named implementations:** `Via{Fast}(m)`, a wrapper that selects a second implementation.

The full list, with where each is decided: [reference §16](../reference/traits.md#16-status-index).
