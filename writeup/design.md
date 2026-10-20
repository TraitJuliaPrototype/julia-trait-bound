# Trait-bound Julia: the design

This is a design for traits in Julia, written for Julia's core developers. It is built as a patched Julia 1.13.2 and a package, TraitWorld, and measured on four demonstrators: an ODE solver, a plotting library, a data report with its own CSV reader and table library, and ports of CSV.jl and DataFrames.jl.

This page is the rationale: the problem, the argument for the design's shape, and what is not claimed. The design itself, precisely, is in the four [references](reference/README.md): [traits](reference/traits.md), [the facts mode](reference/facts.md), [the compiler and runtime](reference/compiler.md) and [lowering](reference/lowering.md). They are the source of truth: where this page disagrees with them, they win. The numbers are in [the evidence](design/evidence.md), each with its build and experiment. Designs that were tried and dropped are in [Alternatives considered](design/alternatives.md); the terms are in the [glossary](glossary.md).

## 1. The problem

Julia compiles a method for the concrete types of its arguments and caches the result. Two things go wrong with that cache.

**Problem 1: compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used.
- Where inference ran at an abstract signature, the code depends on every method that matches there.
- Any package that adds a method for its own type can change that answer, and the code is discarded. No piracy is involved. A package that defines `Base.show(io, ::MyType)` invalidates every caller compiled at a `show(::IO, ::Any)`-shaped signature.
- Loading CairoMakie on Julia 1.12 discarded code at 769 signatures, none of them concrete.
- A package's own extension can discard its compiled code: with DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s, because DataFrames loads InlineStrings, and that activates CSV's extension.
- Package images cannot help: the code they hold is discarded the same way. Without stable caches, neither composable caching across packages nor ahead-of-time compilation is reliable.

**Problem 2: code cannot say what it needs.**
- A field or argument is typed concretely or abstractly.
- Concretely, code is compiled per type and carries every part of the value, read or not. In SciML a new callback closure recompiles the solver, although the step never reads the callback, and an integrator's type prints in an error as 3,553 characters.
- Abstractly (`Vector{AbstractVector}` where the code means "a vector of columns"), there is one copy of the code, but every operation is a dynamic dispatch, and inference speculates over the methods that exist today.
- Nothing checks what an abstract type promises. Mistakes surface deep inside the library.
- The result is silent performance cliffs, overparametrized types, and compiled code multiplied by every type that differs only in what the code never reads.

The two problems meet at abstract types: they are where code loses its types, and where compiled code becomes fragile.

## 2. The argument in four steps

The argument starts from what is true of Julia today and adds one step at a time.

One term first. Code is **fully typed** when every call in it, and in all the code compiled into it, is at a *fact signature*: a tuple of concrete types, or a few close relatives of one (the splits of a small union, a closure's call, a concrete `Vararg` tail). What dispatch selects at a fact signature is a *fact*. The exact definition is [facts §3](reference/facts.md#facts-and-fact-signatures). A type passed as a value to a function its caller does not own (`make(::Type{T})` at `T::DataType`) is a kind, and such a call is not fully typed.

### 2.1 Step 1: fully typed code is already invalidated only by stakeholders and pirates

This is true of plain Julia today.
- The *stakeholders* of a concrete signature are the packages that own its function or one of its types. A *pirate* is a method defined by none of the stakeholders of its own signature: Julia's "type piracy".
- Plain inference infers a fully typed call at its concrete signature, so every edge of fully typed code is a fact: "at signature `s`, dispatch selects `r`".
- **Lemma O:** a method that applies at a concrete signature and is no pirate is defined by a stakeholder of that signature. So only a stakeholder or a pirate can change a fact.
- A stakeholder's definition is "the code changing": an edit, an upgrade, an extension of the package that owns the function or a type in the signature.
- A pirate changes compiled code only if it wins at a fact. One that loses changes nothing, in any load order (Lemma D).
- Verified on 1.13.2 ([the framing review](reviews/2026-10-18-framing-and-motivation.md) §0, reproduced with the in-tree facts mode): a stakeholder's method, a winning pirate and a redefined `const` invalidate code at concrete signatures; a losing pirate never does.
- Proofs: [wrapping by facts](explorations/wrapping-by-facts.md) (Lemma O, Lemma D, Theorems 1–3).

### 2.2 Step 2: refuse the pirates that would win, and trait code is never invalidated

Step 1 leaves one source of invalidation that is not the code changing: a winning pirate. **Strict mode** refuses it where it is defined: at the prompt, by `include`, or as a package image's methods activate. The error names the method and the code it would have changed. The method then does not exist for plain Julia either, so a call still computes what plain Julia computes ("identical or error").

The step holds for any fully typed code. The design applies it to trait code ([facts §10](reference/facts.md#pirates)): the code of trait modules, compiled by facts. Then trait code satisfies the guarantee the design is built on:

> **Compiled trait code is never invalidated unless code it depends on changes.**

"Code it depends on" is precise: the stakeholders of its facts. "Never" has exceptions, named with the guarantee wherever it is claimed:
- **A stakeholder's definition:** edits, Revise, upgrades. This is the stated exception.
- **A package extension of a stakeholder** whose method applies at a fact without mentioning its trigger's types, activated by loading the unrelated trigger. It is the stakeholder's own change: followed, never refused. In strict mode a warning names the method and the trait code it affects ([facts §10.3](reference/facts.md#strict-intended)).
- **A binding the code reads, redefined from another module** (`Core.eval(Other, …)`). The theory does not cover bindings yet, and no hook sees them ([open issues](open-issues.md) §1.1).
- **A pirate already in a package image** when the code was compiled. Image validation discards the facts it breaks; the intended design makes that an error.

The refusal is narrow, so extending and hooking into existing code keep working:
- **Implementations are the sanctioned extension point.** An implementation is a method that applies at no existing fact, so it invalidates nothing. In TraitCSV, InlineStrings' `String15` conforms from an extension, and the reader compiled for `Float64` columns keeps its code. This is what package extensions become.
- **Hooks on your own types are never refused.** `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`, an operation of someone's trait for your type: the definer is a stakeholder of every signature they apply to.
- **What is refused** is exactly a method of a function you do not own, for types you do not own, that would change what compiled trait code computes. On CSV, DataFrames and CairoMakie, 837 of 65,318 methods are pirates by the letter, and none would be refused (`experiments/facts/g2strict`, on the previous prototype; [evidence](design/evidence.md)).

### 2.3 Step 3: the facts rule extends the guarantee to code that is not fully typed

Most code is not fully typed. Where inference ran at an abstract signature, the edge can be broken by any owner adding a method for its own type, and there is nobody to refuse (problem 1).

**The facts rule:** compiled code depends on the method table only through facts. A call that is not at a fact signature is a *run-time site*: it dispatches at run time, as plain Julia's dynamic dispatch does, and records nothing that a later method could break. Nothing is skipped: a fact is invalidated exactly when a definition changes dispatch at its signature. With the facts rule, every CodeInstance compiled by facts is invalidated only as step 1 says, and step 2 makes the guarantee hold for it.
- Verified: four non-pirate definitions that invalidate on 1.13.2 (an owned method at an abstract call, a new subtype under union splitting, a `return_type`-dependent `map`, a new type at a kind) invalidate nothing in facts mode.
- Trait modules are compiled by facts, whoever calls them. A switch compiles all code by facts: the test bed `all`, for the facts rule on code as it is written today ([facts §6](reference/facts.md)).

**The cost sits exactly where code is not fully typed.**
- For fully typed code, facts inference *is* plain inference: the same calls inferred, the same edges, the same code.
- Elsewhere, the facts rule removes Julia's heuristics for type-unstable code: speculation over the methods that match today, a result type taken from the one method that matches today, inlining at abstract types, compile-time evaluation over abstract calls. The result of such a call is `Any`, and `Any` spreads into the code after it.
- Under the test bed `all`, BaseBenchmarks are within a few per cent of plain overall; the concrete groups are unchanged, and the tails are on containers of `Any`, abstract element types and small unions ([evidence](design/evidence.md) §2).
- The same trade-off on a whole session with upstream packages only: a plotting session under `all` saves the recompilation that loads cause, and pays per round of work in Makie's containers of `Any`; it comes out ahead for the first few dozen rounds ([evidence](design/evidence.md) §3, E-140).

### 2.4 Step 4: traits say what code needs, which makes the facts rule cheap

Traits make code fully typed where plain Julia would lose its types, by three mechanisms:
1. **Concrete keys.** A function bounded by a trait is compiled per key: the receiver type and the declared fields' types. Its reads and calls are at fact signatures. Type-stable code over concrete keys is fully typed, so it pays nothing for the facts rule. A trait may **enforce** concreteness, in one declaration with a level (silent, warn, error; [traits §3.7](reference/traits.md#37-concreteness)), so that type-stable code bounded by it is always fully typed.
2. **Declared result types at abstract positions.** Where a value is heterogeneous on purpose, the heterogeneity is declared: `Dynamic{X}` for values, `Callable{A, S}` for functions. Their operations have declared result types, checked. They give back exactly what the facts rule takes away, a result type at an abstract call, from a declaration rather than from the methods that exist today.
3. **Declared implementations.** The types a `Dynamic{X}` value can hold are those of the declared implementations, so an operation on it splits at the call site (`isa` branches, direct calls, a dynamic call last), as union splitting does, without an edge to the list ([facts §9](reference/facts.md#dynamic-split)). This takes the place of the speculation the facts rule removes.

**Heterogeneous collections are the clearest case.** In plain Julia a heterogeneous collection is a container with an abstract element type: `Vector{AbstractShape}`, `Vector{Any}`, `Dict{String,Any}`.
- The element type says only that each element is some subtype. It says neither which operations the loop needs nor what they return.
- Plain Julia makes such loops tolerable by its heuristics, and the facts rule removes exactly these. So these containers are its tails (`filter!` on a `Vector{Any}`).
- `Vector{AbstractShape}` is a poor substitute for what the code means: "something I can iterate whose items provide `Shape`". Traits say that directly: a collection trait with a declared item bound, items `Dynamic{Shape}`. The loop is compiled per key, the item type is known from the bound, and each operation on an item is the `Dynamic` split, not a call at `Any`.
- A user's existing `Vector{Any}` crosses through a view that wraps each element when it is read: no copy, and the user's vector stays the one that is read and written. This is the shape of Rust's `impl Iterator<Item = &dyn Shape>` and Swift's `some Sequence<any Shape>`: the code states the bound, the producer chooses the representation ([other languages](design/other-languages.md)).

So the tails on heterogeneous collections argue for traits with the facts mode: the facts rule makes the guarantee unconditional, and traits give heterogeneous code the declarations that make it fast. The costs measured where trait code calls Base's generic algorithms on plain containers are the cost of calling into ordinary code, which the facts mode exists to make smooth and correct; they are not the cost of idiomatic trait code. Collection traits are planned and not built ([open issue 31](open-issues.md)); until then the recovery is a copy into `Vector{Dynamic{X}}`, which costs a pass and loses aliasing (open issue 11).

Type-unstable code was never claimed to be fast in Julia. Under the facts rule it stays correct and gets slower in the tails. The design's answer is the principle that a slowdown is tolerated when redesigning the code with traits recovers it.

### 2.5 The default: following pirates, and what it gives up

Step 2 is a switch. The default session leaves it off: a winning pirate is followed, as plain Julia follows it, and the code with that fact compiles again once.

- **The compiled code is the same either way.** Strict mode acts only at a method's definition and at image activation.
- **Two tiers of the guarantee** ([facts §2.2](reference/facts.md#g2)):
  - strict: trait code is invalidated only by a stakeholder's change. A static property of every environment that loads without a `PirateError`, with the exceptions of 2.2;
  - default: invalidated only by a stakeholder's change or a pirate that wins at one of its facts. Whether one does is an empirical property of the environment, measured in [the evidence](design/evidence.md) §1.
- **What the default gives up:**
  - the kind of guarantee: a theorem becomes a measurement;
  - who learns: an error at the pirate's definition becomes a silent recompile;
  - trust in package images: in strict mode's intended design, a pirate loaded before an image is an error; by default it is a recompile;
  - order independence: by default the set of methods is order-independent and only when code compiles depends on order; in strict mode compiled code's validity is order-independent, but the set of methods depends on order unless the symmetric lint runs.
- **Why it may be presented as a later, separate choice:** strict mode changes nothing at run time; "identical or error" and the measurements do not depend on it; both tiers are stated; the exceptions of 2.2 are listed wherever the guarantee is claimed.

### 2.6 How the two goals interact

- **Goal 1:** composable caching of compiled code, and AOT: compiled code never invalidated unless code it depends on changes (steps 1–3).
- **Goal 2:** code says what it needs, and compiled code serves every type that provides it (step 4; [traits §4](reference/traits.md#4-keys-what-code-is-compiled-for)).

How they depend on each other:
- **Goal 2 makes goal 1 cheap.** Concreteness makes the guarantee free: fully typed code pays nothing for the facts rule. Declared results and declared implementations recover what the facts rule takes from code that is heterogeneous on purpose.
- **The facts rule makes goal 1 unconditional.** Code that is not fully typed does not lose the guarantee; it becomes run-time sites instead of fragile edges, and pays in speed only there.
- **Goal 1 makes goal 2 worth having.** Code compiled per key is cached in the image that compiled it and is never discarded by an unrelated load, so the per-key copies are compiled once, not once per session.
- **AOT follows from goal 2:** dispatch through trait code goes to declared targets that a build can list ([traits §15](reference/traits.md#15-compiling-ahead)).

| Code | Guarantee | Cost of the facts rule |
|---|---|---|
| fully typed (plain Julia or trait code) | step 1 today; never invalidated with step 2, for trait code | none: facts inference is plain inference |
| trait code over concrete keys, type-stable | as above, enforceable per trait | none |
| trait code at declared abstract positions (`Dynamic{X}`, `Callable`) | never invalidated by an unrelated load | a dispatch or indirect call per use, result type declared; the call-site split for `Dynamic` |
| plain code that is not fully typed | only under the test bed `all` | Julia's heuristics lost at its run-time sites: the tails of 2.3 |

## 3. The design in brief

The pieces the argument relies on, each defined precisely in a reference.

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

- **A trait** is an abstract type with a declared, checked contract: operations with argument and result types, fields with types, associated types ([traits §3](reference/traits.md)).
- **A type joins a trait by a declaration,** checked when it is made and never inferred from the methods that exist. Its operations are served by the type's own methods, by one field it forwards to (always named with `by`), or by the trait's defaults ([traits §5](reference/traits.md#5-implementations)).
- **A bounded function is compiled for what its bound can see:** the key. `colmean` is compiled once for `Vector{Vector{Float64}}`, and every table type that forwards to such a field runs that code from the library's image ([traits §4](reference/traits.md#4-keys-what-code-is-compiled-for)).
- **Mixed values are declared:** `Dynamic{X}` for values ([traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type)), `Callable{A, S}` for functions at a declared signature ([traits §9](reference/traits.md#9-callable-functions-at-a-declared-signature)).
- **Three rules carry it:** facts (compiled trait code depends on the method table only through facts; trait code may call any Julia code), ownership (only a stakeholder or a winning pirate can change a fact; the same rule says who may implement), and the boundary (only values cross into trait code, each translated once by its bound). Two guarantees follow: identical or error, and stable caches ([facts §2](reference/facts.md)).
- **Julia provides** the facts rule as a mode of its own inference, code compiled by facts beside plain code, dynamic dispatch from facts code to facts code, and the call-site split for `Dynamic` ([the compiler reference](reference/compiler.md); [changes to Julia](design/julia-changes.md)).

What is built, and what is not yet: [the state](state.md). What the measurements show, with builds and baselines: [the evidence](design/evidence.md); where the costs come from: [performance](design/performance.md).

## 4. What is not claimed

- No change to results beyond values that Julia decides by inference, such as the element type of an empty `map`.
- "Never invalidated" is strict mode's tier, for trait code; the prototype of strict mode lacks parts of its intended design.
- No "compiled once for any type": a type that supplies behaviour gets its own copy, once, in its own image.
- No claim that traits protect code from loads: the facts mode does, for any code it compiles. Traits make it cheap.
- No claim that code calling into plain Julia at abstract types is as fast as in plain Julia: that is where the facts rule costs, and where traits are the remedy.
- No numbers for TraitWorld on stock Julia: the design needs the patched build. Stock numbers appear only as baselines, and say so.
- No threads, no Revise.
- Imports are not at pandas' speed, because of Julia's startup and package loading.

## Where to read on

- The design, precisely: the [references](reference/README.md), each with its deviations. The [state of the prototype](state.md) in one page.
- The measurements: [evidence](design/evidence.md) and [performance](design/performance.md); the [changes to Julia](design/julia-changes.md) with commits and upstream status; the design against [C++, Rust, Swift and Mojo](design/other-languages.md).
- [Alternatives considered](design/alternatives.md): what was tried, rejected or replaced, and why. [Open issues](open-issues.md), the [glossary](glossary.md).
- For programmers: [Traits for Julia](intro/traits-for-julia.md), [Traits by example](intro/traits-by-example.md) and [Results](intro/results.md).
- For agents: the [record](record/INDEX.md), with the decision log and the [registry of experiments](record/experiments.md).
