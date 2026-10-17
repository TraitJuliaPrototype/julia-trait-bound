# Traits for better Julia: code written without traits

> **Status (2026-10-17).** The design here is wrapping by facts (`writeup/explorations/wrapping-by-facts.md`), adopted in session 23 and validated in session 24. It replaced trait wrappers, calls upward and sealing.

Base, the standard libraries and nearly every package were written without traits. This note covers how trait modules use that code, and how a library adopts traits without breaking its callers:
- **Adopting traits:** a library adopts them one function at a time, its type-based methods keeping their meaning.
- **Traits over existing functions:** Base's informal interfaces stated as contracts, with conformances declared for Base's families.
- **Calling code written without traits:** directly, as ordinary code does. What the trait world adds is how such calls are compiled: it records dispatch facts at concrete signatures, and everything else dispatches at run time.
- **Pointer calls:** a choice of speed, never of correctness.
- **Four cases:** Base, Cairo, ForwardDiff's duals in a solver, and Makie, CSV and DataFrames in any order.
- **Pirates:** followed as in plain Julia; trait modules may not define them.
- **Strict mode:** an option, off by default, in which defining a pirate that would invalidate trait-world code is an error.
- **What Julia must provide.**

The rules this note relies on, concrete facts (rule 1), ownership (rule 3) and where compiled code lives (rule 4), are in [the design in detail](4-details.md#the-four-rules).

## Adopting traits, one function at a time

**Existing methods keep their meaning.** A library that adopts traits keeps its type-based methods. A trait bound ranks above `Any` and below every type:

```julia
describe(v::Vector{Float64}) = …     # as today
describe(m::AbstractMatrix) = …      # as today
describe(t::ColTable) = …            # new: every other type that conforms to ColTable
describe(x) = …                      # the old fallback, for everything else
```

Adding the trait method changes only calls that used to reach the fallback or raise a `MethodError`. So a library can adopt traits one function at a time, and every existing call keeps its meaning: a value that does not conform reaches the most specific ordinary method that applies. A value of a user type that reaches a type-annotated method, such as a user's subtype of `AbstractMatrix`, is not translated by a bound; that call runs as ordinary code, with today's semantics and today's speed. The ranking rules among traits are in [the design in detail](4-details.md#dispatch-types-first-then-traits).

**Conversion goes module by module, in any order.** A trait module may call the package's ordinary modules, and ordinary modules may call it. Calling packages written without traits is not converting them.

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

**Who declares them.** By ownership (rule 3), such declarations come from the trait's owner or from Julia. So a small trait package of capability traits, `Iterable`, `Indexable` and `HasLength`, with conformances for Base's families, is all it takes.

**What stays unchecked.** Trait-bound code still calls Base directly. Inference confirms such a declaration only at concrete argument types, and misses a fallback that throws on some paths only. Every call asserts its result, so "identical or error" holds regardless.

<a id="trait-wrappers"></a>
## Calling code written without traits

**Trait-world code calls any Julia code directly,** as ordinary code does: Base, Cairo, ForwardDiff, CSV, Makie. Nothing is declared for it: no wrapper, no declared call, no handle type.

```julia
@trait_module module Plots                # a trait module that calls Makie; a sketch
using CairoMakie
export plotseries

@trait PointSeries begin
    xs(s::PointSeries)::Vector{Float64}
    ys(s::PointSeries)::Vector{Float64}
end

function plotseries(path::String, s::PointSeries)
    f = Figure()                          # Makie's values are ordinary values here
    scatter!(Axis(f[1, 1]), xs(s), ys(s)) # what the operations return goes to Makie as it is
    save(path, f)
end
end
```

**What stays a rule is the boundary (rule 2).** A trait object is never passed bare to an ordinary function. What its operations and fields return are ordinary values, which any code may take. So definition checking still covers everything that touches the user's data, and logging, printing and debug code can be added anywhere. These were the two objections that ended C++0x's rule that constrained code calls only constrained code ([design choices §5](2-design-choices.md#5-layering-trait-bound-code-calls-only-trait-bound-code), written for the earlier layering rule).

**Ordinary code may still convert explicitly.** A package may pair a trait module with an ordinary module that converts its users' values. That is a style, not a rule.

### What the compiler records

Trait-world code is compiled by the trait world's own compiler policy, in its own cache: TraitWorld's `FactsInterp`, an `AbstractInterpreter` with its own cache owner. The workers and every callee they reach, Base's or any package's, are compiled under it (rule 1):
- **At a call with concrete argument types,** it records a *fact*: "at signature `s`, dispatch selects `r`".
  - `r` may be a method, "no method", or "ambiguous".
  - Union splitting gives several facts.
  - The trait world's own decisions are facts too: "type `T` uses the trait's default for `length`" is the fact `D(length, Tuple{T}) = default`, so the owner adding `length(::T)` recompiles the code to the new method.
- **At any other call,** it records nothing. The call dispatches at run time, in the current world, as plain Julia's dynamic dispatch does. Typical such sites are printing with `@nospecialize`, fields typed `Any`, keyword sorters, and promotion on abstract types.
- **Nothing is skipped.** A fact is invalidated exactly when a definition changes dispatch at its signature. That is Julia's own invalidation for edges at concrete signatures, which is exact in all nine cases tested (`experiments/facts/`, E3).

**Why concrete facts only.** An abstract fact, "the methods matching `S` are exactly these", is broken by any package that defines a new subtype together with a method. That package is no pirate and no stakeholder of anything the code computes with. So concrete facts are what makes the cache stable under loads (Theorem 2 in `wrapping-by-facts.md`).

**Finer points,** each found in validation (`wrapping-by-facts.md`, "Validation", rules 1–7):
- **`return_type` is plain Julia's question.** The policy answers it itself when its answer is a concrete type or `Union{}`. Otherwise it takes plain Julia's answer at the match's own signature, folded only when that answer rests on concrete facts. Otherwise the call is left to run time.
- **No compile-time evaluation over a run-time site.** Asserted effects (`@assume_effects`) could claim foldability over a call the policy dispatches at run time, so such callees are not folded.
- **Kinds count as concrete for closures only.** A closure called with types as values (`DataType`, `UnionAll`) has a fact; only the closure's owner adds methods to it. For other functions such a call stays a run-time site.
- **The entry's call of the worker is a fact** at the call's concrete signature.
- **TraitWorld's own machinery** is compiled by the policy where it can be, and kept in TraitWorld's image.

### Pointer calls: a choice of speed

A callee can instead be called through a pointer into plain Julia's own compiled code: about 4 ns per call, no inlining across it, the result asserted. The pointer calls plain Julia's code, so the result is plain Julia's.

Two forms exist:
- a `Callable` argument in `DynamicCall` mode ([the design in detail](4-details.md#function-arguments-callable));
- `DynamicFn{A, S}`, a stored function of fixed type made by `dynamic_fn` in ordinary code, for a library's model or callback types.

They let a solver compile once per signature rather than once per function. Neither is needed for correctness: a wrong choice can make code slow, never wrong.

### Four cases

| Case | How | Cost |
|---|---|---|
| **A. Base** | ordinary calls; arithmetic, arrays, `sum`, `sort!`, `lu!` on concrete types are concrete facts | as plain Julia on hot paths; printing and promotion paths with abstract argument types dispatch at run time (tens of ns, mostly cold paths) |
| **B. Cairo** | ordinary calls; a `CairoContext` is an ordinary value; `ccall` side effects as in plain Julia | none, or about 4 ns per call as a pointer call |
| **C. ForwardDiff** | `Dual{Tag, Float64, N}` is just a key type. Its arithmetic is ForwardDiff's own methods, as concrete facts. The solver's Jacobian duals use a solver-owned tag. The user's `f!` is a key type (compiled per function) or a pointer call (`DynamicFn`). | as plain Julia. No library-owned dual type and no ForwardDiff wrapper |
| **D. Makie, CSV, DataFrames** | nothing is refused; only stakeholders of fact signatures, or pirates that win at them, invalidate trait-world code | none measured; a winning pirate costs a recompile, which "identical or error" requires |

**Measured** (patched Julia 1.13.2, `experiments/facts/`):
- **Loads.** Both trait libraries ran their work first. Then twelve packages loaded one at a time, with work after each: CSV, DataFrames, CairoMakie, ChurnStorm (100 types with Base methods and 20 redefinitions), BasePirate, OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations and StaticArrays. Of the CodeInstances compiled under the policy, 0 were lost after every load. With the same packages loaded before, the same 7871 instances were valid.
- **First calls,** in every load order:

| | no loads | loads after | loads before |
|---|---|---|---|
| TraitDifferentialEquations, first solve | 57–60 ms | 55–60 ms | 57–60 ms |
| Rodas5 with ForwardDiff's `Dual`, first solve | 72–74 ms | 75 ms | 77 ms |
| TraitMakie, first PNG | 87 ms | 89–96 ms | 90–97 ms |

- **Hot loops** consist of concrete facts only (E1, before direct calls). The one run-time site that showed in profiles, at 1.6%, was the declared-call path to Cairo, which direct calls remove. The others were cold: building `Dynamic` values, and reflection and printing in Base.

<a id="sealing"></a>
## Pirates

**Who can change trait-world code** (Theorem 2 in `wrapping-by-facts.md`). Code whose facts are all concrete stays valid under loads in any order, unless a loaded package either:
- **is a stakeholder of one of its fact signatures:** it owns the function, a type occurring in the signature, or a supertype of one; or
- **brings a pirate that wins** dispatch at one of those signatures; or
- **activates a package extension** of a stakeholder, with a method that applies at one of those signatures without mentioning its trigger's types (the one case where an unrelated load counts).

Two lemmas give this:
- **Ownership (Lemma O):** a method that is no pirate and applies at a concrete signature is defined by a stakeholder of it, counting supertypes' owners ([the design in detail: Ownership](4-details.md#ownership)). A package extension counts as its parent, but loads with its triggers.
- **Dominance (Lemma D):** a method that does not win at `s` leaves dispatch at `s` unchanged, whatever the order of insertion. That makes the result order-independent.

In both cases plain Julia's own result changes, so no design that computes what plain Julia computes could keep the code.

**Pirates are followed, as in plain Julia.**
- A pirate that wins at a fact breaks it, and the code recompiles against the pirate, once.
- A pirate that loses, or does not apply, changes nothing.
- Nothing is refused at load. Refusing a pirate at load (sealing, an earlier form of the design) broke plain users of the pirate's package, depended on the load order, and came after the deleted method's invalidations.

**Trait modules may not define pirates.** A trait module's method must have the module's package as a stakeholder, checked when the module is defined (rule 3).

**Measured** (E2, after the demonstrators' workloads with the stack of case D loaded first):
- The code compiled for them has 3,533 CodeInstances, 3,043 concrete facts and 207 abstract facts.
- **None** of the concrete facts selects a pirate from outside Julia.
- The stack brings OffsetArrays' 12 pirates of Base, and StatsBase's and Durations'. None of them wins anywhere the demonstrators call.
- **Limits:** two small libraries and one stack of packages. Run-time sites were not counted, and neither were keys with StaticArrays types.

**Split-core packages** such as StaticArrays, which defines `Base.size(::SArray)` for a type StaticArraysCore owns, are pirates by the letter. They are followed like any other pirate. They matter only for strict mode, and there only if the implementation loads after trait code was compiled at the core's types and wins at one of its facts.

## Strict mode, an option

Strict mode is an option, off by default. **In strict mode, defining a winning pirate is an error.** Details are in `writeup/explorations/strict-mode.md`.
- **When:** at a method definition, including a package image's methods at its load.
- **What is refused:** a method that would be selected at a concrete fact signature held by valid compiled trait-world code, that is, a method that would invalidate trait-world code, defined by a package that is no stakeholder of that signature. It owns neither the function nor a type in it; an extension counts as its parent.
- **The error** names the method and the trait-world code it would change.
- **What is accepted as today:** a stakeholder's definitions, which recompile the code as before, and pirates that win at no trait-world fact.
- **A pirate defined before** the trait code is compiled is followed, as in plain Julia. The code is then compiled against it, so the pirate can never invalidate it afterwards: a later winning change by the same pirate is refused.

**What it buys:** trait-world code is never invalidated by a pirate. "Identical or error" still holds, since a refused method does not exist for plain Julia either.

**What it costs:** an error where the core would recompile. If pirates never win, the mode never errors. In the load sequence of case D, no trait-world code was invalidated by any of the twelve loads, so the mode would have refused nothing there.

**What it needs:** Julia piece 1, a method-definition hook that may refuse a definition. It is implemented in the patched build.

**In a build,** a pirate lint is planned: `verify_main` lists the calls reached from trait code that select a pirate ([the design in detail: AOT](4-details.md#aot-the-reachable-code-is-declared)).

## What Julia must provide

The compiler policy is package code. What it needs from Julia proper is in `writeup/explorations/julia-support.md`, "Review for wrapping by facts and strict mode":
- **Piece 5:** native code for the policy's CodeInstances in package images. Without it every session compiles the policy's code: on stock Julia the first solve takes 0.44 s instead of about 50 ms.
- **Piece 9:** a bare MethodInstance edge is broken only by a CodeInstance of the caller's own owner.
- **Piece 10:** the inliner uses the CodeInstance it is given. TraitWorld works around it with a `@noinline`, about 5 ns per typed call.
- **Piece 11:** "compile this call under owner X" from inference, through the `CompilerPlugins.typeinf` hook Julia 1.13 already declares. It removes assumption A4.
- **Piece 12:** a frozen world for an external interpreter's compiler.
- **Piece 13:** coverage and allocation tracking for foreign CodeInstances.

Pieces 5 and 9–13 make up the first upstream proposal, "first-class foreign cache owners". GPU compilers, Enzyme and Cassette-like tools need the same pieces. Strict mode adds piece 1, a method-definition hook that may refuse a definition.

No invalidation hook, no dispatch check in codegen and no trimming of foreign CodeInstances are needed.

## What this costs

1. **Calls at abstract types dispatch at run time,** also where plain Julia would infer through them. They cost tens of ns each; in the demonstrators they lie on cold paths.
2. **Base code reached from trait code is compiled again,** in the policy's cache. Measured under the policy:
   - a broadcast 15.0 ns against 14.7 natively, `map(sin, v)` 27.5 ns against 24.1;
   - a DataFrames and CSV workload that no image holds: first call 0.60 s against 0.45 s natively, steady state within 10%.
3. **A winning pirate recompiles** the code that has a fact where it wins, as in plain Julia, or is refused in strict mode.
4. **Conformances for Base's families are curated.** A type nobody declared does not conform, even when it has the methods.
5. **New trait code after big loads is slow,** for now: defining a small module and its first call take 2.7 s and 0.8 s after big loads, against 1.0 s and 0.09 s. The cure is TraitWorld's checks in the compiler (Julia piece 7) and piece 12.
6. **Assumptions.** Values decided by inference precision may differ from plain Julia's, as they differ within plain Julia (A3). No method may be defined on another thread while trait code compiles, until piece 11 (A4). Both are in [identical or error](4-details.md#identical-or-error).

The prototypes and their measurements are in `experiments/facts/README.md`. The earlier wrappers, calls upward and sealing, with their measurements, are in `experiments/interfaces/README.md`.
