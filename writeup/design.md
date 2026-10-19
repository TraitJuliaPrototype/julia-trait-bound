# Trait-bound Julia: the design

This is a design for traits in Julia, written for Julia's core developers. It is built as a patched Julia 1.13.2 and a package, TraitWorld, and measured on four demonstrators. This page is the rationale: the problem, the argument, why the design has its shape, and what is not claimed.

The design itself, precisely, is in the four [references](reference/README.md): [traits](reference/traits.md), [the facts mode](reference/facts.md), [the compiler and runtime](reference/compiler.md) and [lowering](reference/lowering.md). They are the source of truth: where this page disagrees with them, they win. Designs that were tried and dropped, and why, are in [Alternatives considered](design/alternatives.md). The terms are in the [glossary](glossary.md).

## 1. The problem

Julia compiles a method for the concrete types of its arguments and caches the result. Two things go wrong with that cache.

**Compiled code does not stay valid.** Compiled code depends on the method table: on which methods match at the signatures inference used. Where inference ran at an abstract signature, the code depends on every method that matches there, and any package that adds a method for its own type can change the answer. No piracy is needed. A package that defines `Base.show(io, ::MyType)` discards every caller compiled at a `show(::IO, ::Any)`-shaped signature. Loading CairoMakie on Julia 1.12 discarded code at 769 signatures, none of them concrete. Even a package's own extension can do it: with DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s, because an extension of CSV adds methods to CSV's internal functions. Package images hold code that is discarded in the same way. So neither composable caching of compiled code across packages nor ahead-of-time compilation (AOT) is reliable. The cases are in [§2 of the details](design/argument.md#2-the-problem).

**Code cannot say what it needs.** A field or an argument is typed either concretely or abstractly. Typed concretely, the code is compiled per type and carries every part of the value, whether it reads it or not: in SciML a new callback closure recompiles the solver, although the step never reads the callback, and an integrator's type prints in an error as 3,553 characters. Typed abstractly, there is one copy of the code, but every operation is a dynamic dispatch, and inference speculates over the methods that exist today. Nothing checks what an abstract type promises, so mistakes surface deep inside a library. The results are silent performance cliffs, overparametrized types, and compiled code multiplied over types that differ only in what the code never reads.

The two problems meet at abstract types. That is where code loses its types, and where compiled code becomes fragile.

## 2. The argument

The argument starts from what is true of Julia today and adds one step at a time. It needs one idea first. Call code *fully typed* when every call in it, and in all the code compiled into it, is made at concrete argument types, or at a few close relatives of them: the splits of a small union, or a closure's call. Such a signature is a *fact signature*, and what dispatch selects there is a *fact*. The exact definition is [rule 1](reference/facts.md).

**Step 1: fully typed code is already invalidated only by its stakeholders and by pirates.** The *stakeholders* of a concrete signature are the packages that own its function or one of its types. A *pirate* is a method defined by none of the stakeholders of its own signature: Julia's "type piracy". A short lemma shows that only a stakeholder or a pirate can add a method that applies at a concrete signature. A stakeholder's method is the code changing: an edit, an upgrade. A pirate matters only if it wins at a fact; a pirate that loses changes nothing, in any load order. This holds in plain Julia, it is verified on 1.13.2, and it is proved ([details §3.1](design/argument.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).

**Step 2: refuse the pirates, and fully typed code stays valid.** *Strict mode* refuses a pirate at its definition if it would win at a fact of compiled code, and the error names the method and the code it would have changed. With step 2 alone, in plain Julia and without traits, fully typed code satisfies the guarantee the design is built on:

> **Compiled code is never invalidated unless code it depends on changes.**

"Code it depends on" means the stakeholders of its facts. A few cases fall outside the guarantee and are named wherever it is claimed: a stakeholder's own edits, some package extensions, bindings redefined from another module, and pirates already in a package image ([details §3.2](design/argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached)). The refusal is narrow. A method for your own type is never refused, and neither is an implementation of a trait. On CSV, DataFrames and CairoMakie, 837 of 65,318 methods are pirates by the letter, and none would be refused.

**Step 3: the facts rule extends the guarantee to all code.** Most code is not fully typed. The *facts rule* says that compiled code depends on the method table only through facts. A call that is not at a fact signature becomes a *run-time site*: it dispatches at run time, as Julia's dynamic dispatch does, and records nothing that a later method could break. Nothing is skipped: a fact is invalidated exactly when a new definition changes dispatch at its signature. The price is paid only where code is not fully typed. There the facts rule removes Julia's heuristics for type-unstable code, such as speculating over the few methods that match today, and the result of such a call is `Any`. On an earlier build, BaseBenchmarks ran at a geometric mean of 1.016 against plain Julia, with tails up to about 80× on containers of `Any` ([details §3.3](design/argument.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed)).

**Step 4: traits say what code needs, which makes the facts rule cheap.** Traits make code fully typed where plain Julia would lose its types. A function bounded by a trait is compiled for the concrete types its bound can see, so its calls are at fact signatures. Where values are mixed on purpose, the design declares it, and the declaration gives back what the facts rule took away: a result type, and the list of types to split over. A trait can also require concreteness, so that code bounded by it is always fully typed ([details §3.4](design/argument.md#34-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap-and-can-enforce-concreteness)). Type-unstable code was never claimed to be fast in Julia. Under the facts rule it stays correct and gets slower in the tails, and the design accepts a slowdown when rewriting the code with traits recovers it.

**Strict mode is a switch.** By default a session follows a winning pirate, as plain Julia does, and the code that held the broken fact compiles again once. The compiled code is the same in both settings. What the default gives up is the kind of guarantee: in strict mode, validity is a property of every environment that loads without an error; by default it is a measured property of the environment. Both tiers are stated wherever the guarantee is claimed ([details §3.5](design/argument.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up)).

**The two goals depend on each other.** The first goal is composable caching and AOT: compiled code that stays valid (steps 1 to 3). The second is code that says what it needs, compiled once for everything that provides it (step 4). Traits make the first goal cheap. The facts rule makes it unconditional. The first goal makes the second worth having: code compiled per key is kept in the package image that compiled it and is never discarded by an unrelated load, so it is compiled once, not once per session. And AOT follows from the second goal, since dispatch through trait code goes to declared targets that a build can list ([details §3.6](design/argument.md#36-how-the-two-goals-interact)).

## 3. Traits

A trait is an abstract type with a declared, checked contract: operations with argument and result types, fields with types, and associated types as parameters.

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end

@implement ColTable Vector{Vector{Float64}} begin   # the library's own implementation
    ncols(t) = length(t)
    col(t, i) = t[i]
end

struct Measurements; label::String; data::Vector{Vector{Float64}}; end
@implement ColTable Measurements by data     # forwards to its field `data`

colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))
```

**A type joins a trait by a declaration**, `@implement ColTable Measurements by data`, which may come after the type was defined. The declaration is one line. Its operations are served by the type's own methods, by one field the type forwards to (always named with `by`: no field is special), or by the trait's defaults. It is checked when it is made: every operation and field must exist with the declared types. It is never inferred from the methods that happen to exist, since Base's throwing fallbacks make such matching meaningless ([traits §5](reference/traits.md#5-implementations)).

**A bounded function is compiled for what its bound can see.** `colmean` reaches its argument only through `ColTable`'s operations. So it is compiled per *key*: the type whose methods serve the operations, here the field's type `Vector{Vector{Float64}}`, and the types of any fields the trait declares. Every table type that forwards to such a field runs the code the library already compiled, from the library's own package image. A solver step bounded by an integrator trait compiles nothing for a new callback, because the trait does not declare the callback. This is not "compiled once for any type": a type that supplies its own behaviour gets its own copy, once, in its own image. What library code receives is a *trait object*: the user's own object, read at the byte offsets of what the bound can see, so nothing is copied and loops run at plain Julia's speed ([traits §4](reference/traits.md#4-keys-what-code-is-compiled-for); [lowering §5–6](reference/lowering.md#5-keys-and-views)).

**Concreteness is opt-in per trait.** By default a key may be abstract. An abstract part then behaves like a dynamic value. A trait that wants more says so in one declaration with a level: silent, warn or error ([traits §3.7](reference/traits.md#37-concreteness)).

**Overrides belong to the implementation.** Which operations a type serves by the trait's defaults is fixed when the implementation is declared, because compiled code and kept values depend on it, as they depend on a struct's definition. A later override is refused, with the fix named ([traits §3.2](reference/traits.md#32-defaults)).

**Mixed values are declared.** A value that must outlive a call, or a collection whose elements have different keys, is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations. An operation on it is split at the call site over the declared implementations, with a direct call for each and a dynamic call last, as Julia splits a small union. Inside a trait module, a trait's name in a field means its `Dynamic`, as an abstract type's name there means a boxed value ([traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type)).

**Functions are passed at a declared signature.** Julia has no type for "a function from `Float64` to `Float64`". A function handed to trait code enters as a `Callable{A, S}`, with argument types `A` and result type `S`, checked at every call. It is called through a pointer by default, compiled once per signature. Where speed matters, as for an ODE right-hand side, the library or the caller asks for a compiled call, specialized on the function, with the signature still checked. The mode chooses speed, never results ([details §4.6](reference/traits.md#9-callable-functions-at-a-declared-signature)).

**The rest follows the same lines** ([traits](reference/traits.md)). Library code is checked once, where it is written, against stand-ins for every type that will ever conform, so mistakes surface at the library's build. In dispatch, types come first and traits second, which lets a library adopt traits one function at a time. Functions can return results "like the input", rebuilt as the caller's type. Errors print types by bound and key, `ColTable at Vector{Vector{Float64}}`, not at their full concrete type.

**AOT follows from declared targets.** Dispatch between trait code, and over the types a program meets at run time, goes through declared implementations and declared function signatures, so a build can list everything it can reach ([traits §15](reference/traits.md#15-compiling-ahead); [lowering §15](reference/lowering.md#15-compiling-ahead-workloads-closed-builds)).

## 4. The rules

Three rules carry the design. Their precise form is [the facts mode reference](reference/facts.md) for rules 1 and 2, and [the traits reference](reference/traits.md#6-bounded-functions) for rule 3.

1. **Facts.** Compiled trait code depends on the method table only through facts. Every other call is a run-time site. Trait code may call any Julia code.
2. **Ownership.** A method's stakeholders are the owners of its function and of the types in its signature, and anyone else's method is a pirate. Only a stakeholder or a winning pirate can change a fact. Implementations are methods, so the same rule says who may implement a trait for a type: the trait's owner or the type's owner.
3. **The boundary.** Only values cross into trait code, and each is translated once by its bound. Inside, a trait object is what its bound can see and nothing else. Code is compiled per key.

Two guarantees follow. **Identical or error:** a call in trait code computes what plain Julia computes in the current world, or raises. The one exception is values that Julia itself decides by inference, such as the element type of an empty `map`. **Stable caches:** compiled code is invalidated only by the code it depends on, in the two tiers of step 2.

## 5. What Julia provides

The design needs Julia's compiler and runtime, and TraitWorld requires the patched build. The patch adds the facts rule to Julia's own compiler in four parts ([the compiler reference](reference/compiler.md); inventory with commits: [Changes to Julia](design/julia-changes.md)).

- **(A)** The facts rule as a mode of Julia's own inference.
- **(B)** Code compiled by facts beside plain code, chosen per module: a trait module's methods are compiled by facts whoever calls them, and kept in package images.
- **(C)** Dynamic dispatch from code compiled by facts runs code compiled by facts.
- **(D)** The call-site split for `Dynamic` values, in Julia's inliner, over candidates registered without an edge, so a new implementation invalidates nothing.

The compiler itself always runs as plain code, whoever calls it. Two changes to the inliner, found while measuring and useful to plain Julia too, apply to all code. A switch compiles all code by facts; that setting is a test bed for the facts rule on code as it is written today. The product setting compiles only trait modules by facts. A trimmed binary compiles plain code, since in a closed world nothing loads and there is no cache to protect. A few smaller pieces support strict mode, the trait object's layout and printing. The general fixes are ready for upstream; the facts mode itself would be proposed as a mode of the native compiler, with its benchmark table.

## 6. What the evidence shows

All numbers come from one machine, on the patched build, mostly from single runs or a few. The tables, with builds, baselines and run counts, are in [The evidence](design/evidence.md); the costs and where they come from are in [Performance](design/performance.md).

**The steps of the argument hold.** Small cases verify steps 1 and 3: on 1.13.2 a stakeholder's method, a winning pirate and a redefined `const` invalidate code at concrete signatures, and a losing pirate never does; four definitions that invalidate code that is not fully typed invalidate nothing in facts mode. The acceptance suite's 23 checks pass, in the product setting and under the test bed; they include a function passed in the default, pointer-based mode, which runs in the caller's world. Strict mode refuses winning pirates and nothing else in a real stack, measured on the previous prototype.

**Load protection belongs to the facts rule, for any code.** In a control, upstream CSV.jl and DataFrames, compiled with everything by facts and without any trait, lost 2 of 3,340 compiled methods to nine unrelated package loads, against 570 of 4,712 in plain mode, and their first work took 0.7 s instead of 3.6 s. Traits are not what protects code from loads. They make the facts rule cheap, check code where it is written, and type mixed values.

**Traits add speed and stability on top.** The ports of CSV.jl and DataFrames to traits run a scripted session's first calls in 2.85 s against upstream's 10.40 s. A sum over `Dynamic` values runs at 0.92–1.40 ns per element, against plain Julia's 0.87–0.91 ns with two types and 29.5–33 ns with four. Typed trait calls cost 36–38 ns against 33.8–34.5 ns for the same loop in plain Julia. New trait code costs about the same in every load order: a new model type in the differential-equations demonstrator takes 142–164 ms to declare and 82–133 ms to solve first, with or without CSV, DataFrames and CairoMakie loaded. A second loss closure for a gradient compiles in 17–18 ms, because code is compiled per key, not per closure. The solver runs a Lorenz step in 158 ns, against OrdinaryDiffEq's 346 ns. A CSV-to-PNG report runs in a fresh process in 0.76 s, against 0.72 s for the same code without traits and 0.58–0.69 s for Python with pandas and matplotlib. A trimmed plotting binary is 4.07 MB.

**Traits also protect against what the facts rule cannot.** CSV's extension for InlineStrings adds methods to CSV's own functions. That is a stakeholder's change, which the facts rule follows, and with DataFrames loaded it discards the reader's code. The trait form declares an implementation in its extension instead, and loading the extension discards none of the reader's code. Extension by implementations, never by methods on a library's internals, protects even well-trodden parts of the ecosystem.

**Not shown yet.** After the nine loads, upstream CSV and DataFrames still pay about 990 ms with everything compiled by facts (plain Julia: 4.0 s). The cost is the plain inference that keeps run-time `return_type` answers identical to plain Julia's: the loads change what plain inference can know, so its answers are computed again. Another residue is: a standard library's `vcat`, loaded by StatsBase, wins inside CSV's parser. The design counts the standard libraries as Julia's own code, so that is a stakeholder's change, not a pirate; whether they should be separate owners is open. Declaring a forwarding implementation in the plotting demonstrator got slower in the clean case, probably because TraitWorld's own machinery is compiled by facts. Strict mode with everything compiled by facts, threads, Revise-style edits, composition beyond libraries of a few hundred lines, and binaries of the larger demonstrators are untested. The deviations of the implementation from the design are listed in each reference; [the state of the prototype](state.md) summarizes them.

## 7. What is not claimed

- No change to results beyond values that Julia decides by inference.
- "Never invalidated" is the strict tier, and the prototype of strict mode lacks parts of its intended design.
- No "compiled once for any type": a type that supplies behaviour gets its own copy, once, in its own image.
- No claim that traits protect code from loads: the facts mode does, for any code.
- No numbers for TraitWorld on stock Julia: the design needs the patched build. Stock numbers appear only as baselines, and say so.
- No threads, no Revise.
- Imports are not at pandas' speed, because of Julia's startup and package loading.

## Where to read on

- The design, precisely: the [references](reference/README.md), each with its deviations. The [state of the prototype](state.md) in one page.
- The measurements: [evidence](design/evidence.md) and [performance](design/performance.md); the [changes to Julia](design/julia-changes.md) with commits and upstream status; the [comparison with C++, Rust, Swift and Mojo](design/comparison.md).
- [Alternatives considered](design/alternatives.md): what was tried, rejected or replaced, and why. [Open issues](open-issues.md), the [glossary](glossary.md).
- For programmers: [Traits for Julia](intro/traits-for-julia.md), [Traits by example](intro/traits-by-example.md) and [Results](intro/results.md). The record, for agents, with the decision log: [`record/INDEX.md`](record/INDEX.md).
