# Trait-bound Julia: the design

This is a design for traits in Julia, written for Julia's core developers. It is built as a patched Julia 1.13.2 and a package, TraitWorld, and measured on four demonstrators: an ODE solver, a plotting library, a data report with its own CSV reader (TraitCSV) and table library, and ports of CSV.jl and DataFrames.jl.

This page is the rationale: the problem, the argument for the design's shape, and what is not claimed. The design itself, precisely, is in the four [references](reference/README.md): [traits](reference/traits.md), [the facts mode](reference/facts.md), [the compiler and runtime](reference/compiler.md) and [lowering](reference/lowering.md). They are the source of truth: where this page disagrees with them, they win. The numbers are in [the evidence](design/evidence.md), each with its build and its experiment (`E-n` in the [registry](record/experiments.md)). Designs that were tried and dropped are in [Alternatives considered](design/alternatives.md); the terms are in the [glossary](glossary.md).

## 1. The problem

Julia compiles a method for the concrete types of its arguments and caches the result. Two things go wrong with that cache.

**Problem 1: compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used. Where inference ran at an abstract signature, that is every method that matches there, so any package that adds a method for its own type changes the answer, and the code is discarded (invalidated). A package that defines `Base.show(io, ::MyType)` invalidates every caller compiled at a `show(::IO, ::Any)`-shaped signature, though it touches nothing foreign.
- Loading CairoMakie on Julia 1.12 discards code at 769 signatures, none concrete ([findings §1](design-findings.md#1-measurements-behind-the-motivation)).
- A package's own extension can discard its code: with DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s, because DataFrames loads InlineStrings, which activates CSV's extension ([evidence](design/evidence.md#summary-what-the-evidence-shows-and-what-it-does-not)).
- Package images, Julia's caches of compiled code per package, cannot help: their code is discarded the same way. Without stable caches, neither composable caching across packages nor ahead-of-time compilation (AOT) is reliable.

**Problem 2: code cannot say what it needs.**
- A field or argument is typed concretely or abstractly.
- Concretely, code is compiled per type and carries every part of the value, read or not. In SciML a new callback closure recompiles the solver, although the step never reads the callback, and an integrator's type prints in an error as 3,553 characters ([findings §17](design-findings.md#17-where-unreadable-errors-come-from-and-what-bounds-change-session-22); E-5).
- Abstractly (`Vector{AbstractVector}` for "a vector of columns"), there is one copy of the code, but every operation is a dynamic dispatch, and inference speculates over the methods that exist today. Nothing checks what an abstract type promises; mistakes surface deep inside the library.
- The result: silent performance cliffs, overparametrized types, and compiled code multiplied by every type that differs only in what the code never reads.

The two problems meet at abstract types: there code loses its types, and there compiled code becomes fragile.

## 2. The argument in four steps

The argument starts from what is true of Julia today and adds one step at a time. Its terms, defined precisely in [facts §1](reference/facts.md#terms) and [§3](reference/facts.md#facts-and-fact-signatures):
- A package **owns** the functions and types it defines. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent.
- The **stakeholders** of a signature are the owners of its function and of its types. A **pirate** is a method defined by none of the stakeholders of its own signature: Julia's "type piracy".
- A **fact signature** is a signature at which only a stakeholder or a pirate can change dispatch: a tuple of concrete types, or a few close relatives of one (the members of a small union, a closure's call, a concrete `Vararg` tail). What dispatch selects there is a **fact**. A type passed as a value to a function its caller does not own (`make(T)` with `T::DataType`) is not a fact signature: any owner of a type `X` may add `make(::Type{X})`.
- Code is **fully typed** when every call in it, and in all the code compiled into it, is at a fact signature.

### 2.1 Step 1: fully typed code is already invalidated only by stakeholders and pirates

This is true of plain Julia today.
- Plain inference infers a fully typed call at its concrete signature. So every edge of fully typed code (a dependency compiled code records on the method table) is a fact: "at `s`, dispatch selects `r`".
- **Lemma O:** a method that applies at a concrete signature and is no pirate is defined by one of its stakeholders. So only a stakeholder or a pirate can change a fact.
- A stakeholder's definition is "the code changing": an edit, an upgrade, an extension of the package that owns the function or a type.
- A pirate changes compiled code only if it wins at a fact. **Lemma D:** one that loses changes nothing, in any load order.
- Verified on stock 1.13.2 and on the patched build: a stakeholder's method, a winning pirate and a redefined `const` invalidate code at concrete signatures; a losing pirate never does ([evidence §1](design/evidence.md#1-the-guarantee); [the framing review](reviews/2026-10-18-framing-and-motivation.md) §0). Proofs: [wrapping by facts](explorations/wrapping-by-facts.md) (Lemma O, Lemma D, Theorems 1–3).

### 2.2 Step 2: refuse the pirates that would win, and fully typed code is never invalidated

Step 1 leaves one source of invalidation that is not the code changing: a winning pirate. **Strict mode** is a switch that refuses it where it is defined ([facts §10.2](reference/facts.md#strict-mode)). The error, `PirateError`, names the method and the code it would have changed. The refused method does not exist for plain Julia either, so every call still computes what plain Julia computes, or raises: **identical or error**.

With the switch on, fully typed code has the guarantee the design is built on:

> **Fully typed code is never invalidated unless code it depends on changes.**

"Code it depends on" is precise: the stakeholders of its facts. "Never" has exceptions, named with the guarantee wherever it is claimed ([facts §2.2](reference/facts.md#g2)):
- **A stakeholder's definition:** edits, Revise, upgrades; the stated exception. A standard library's method on Base's types counts as one, since Julia is one owner (open: [§1.19](open-issues.md#1-decisions-waiting-for-the-user)).
- **A stakeholder's package extension** whose method applies at a fact without mentioning its trigger's types, activated by the unrelated trigger. It is followed as the stakeholder's own change, never refused; in strict mode a warning names the method and the code it affects ([facts §10.3](reference/facts.md#strict-intended)).
- **A binding redefined from another module** (`Core.eval(Other, …)`): the theory does not cover bindings yet, and no hook sees them ([open issues §1.1](open-issues.md#1-decisions-waiting-for-the-user)).
- **A method on a closure's type from outside its module:** the closure form of fact signature assumes there is none.
- **A pirate already in a package image** when the code was compiled: image validation discards the facts it breaks. The intended design makes that an error ([facts §10.3](reference/facts.md#strict-intended)).

The refusal is narrow, so extending and hooking into existing code keep working:
- **Hooks on your own types are never refused:** `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`. The definer is a stakeholder of every signature they apply to.
- **Implementations are the extension point.** An implementation, the declaration that a type joins a trait (§2.4), applies at no existing fact, so it invalidates nothing. Package extensions become implementations: TraitCSV's extension declares one for InlineStrings' `String15`, and the reader compiled for `Float64` columns keeps its code.
- **What is refused** is exactly a method of a function you do not own, for types you do not own, that would win at a fact of protected code. Of 65,318 methods in CSV, DataFrames and CairoMakie, 837 are pirates by the letter, and none would be refused (`experiments/facts/g2strict.jl`, on the package prototype; [evidence §1](design/evidence.md#1-the-guarantee)).

The step holds for any fully typed code. The design applies the switch to trait code, defined in step 3.

### 2.3 Step 3: the facts rule extends the guarantee to code that is not fully typed

Most code is not fully typed. Where inference ran at an abstract signature, any owner's method for its own type breaks the edge, and there is nobody to refuse (problem 1).

**The facts rule:** compiled code depends on the method table only through facts. A call that is not at a fact signature is a **run-time site**: it dispatches at run time, as plain Julia's dynamic dispatch does, and records nothing that a later method could break. Nothing is skipped: a fact is invalidated exactly when a definition changes dispatch at its signature. So code **compiled by facts** is invalidated only as step 1 says, fully typed or not, and step 2's refusal gives it the guarantee ([facts §2–§5](reference/facts.md#the-guarantees)).
- Verified: four definitions by owners that invalidate on 1.13.2 (an owned method at an abstract call, a new subtype under union splitting, a `return_type`-dependent `map`, a new type at a kind) invalidate nothing under the rule ([evidence §1](design/evidence.md#1-the-guarantee)).
- **Which code.** A **trait module** is a module declared `@trait_module`, whose code is written against traits ([traits §2](reference/traits.md#2-trait-modules)); its code is **trait code**, all other code **plain code**. By default (the product setting) trait modules are compiled by facts, whoever calls them, and plain code keeps all of Julia's behaviour. The test bed **`all`** compiles every method by facts, to test the rule on code as it is written today ([facts §6](reference/facts.md#which-code-is-compiled-how), [§12](reference/facts.md#settings)).
- **Strict mode's scope is trait code:** it refuses a pirate that would win at a fact of trait code, or of code compiled by facts that trait code depends on ([facts §10.2](reference/facts.md#strict-mode)). So in strict mode trait code is never invalidated except by a stakeholder's change: step 2's guarantee, carried by the facts rule to the trait code that is not fully typed.
- One caveat: code compiled by facts that calls Julia's compiler directly holds edges to plain code, under plain Julia's invalidation ([facts §6.4](reference/facts.md#the-compilers-own-code); [open issues §2](open-issues.md#2-design), item 27).

**The cost sits exactly where code is not fully typed.**
- For fully typed code, inference by facts *is* plain inference: the same calls, edges and code.
- Elsewhere, the rule removes Julia's heuristics for type-unstable code: speculation over the methods that match today, a result type from the one method that matches today, inlining and compile-time evaluation at abstract calls. Such a call's result is `Any`, which spreads into the code after it.
- Under `all`, Julia's BaseBenchmarks run at a geometric mean of 1.037 against plain; the tails, up to 27.8×, are on containers of `Any`, abstract element types and small unions ([evidence §1](design/evidence.md#1-the-guarantee)).
- On a whole session with upstream packages only, `all` saves the recompilation that loads cause and pays per round of work in Makie's containers of `Any`; a plotting session comes out ahead for the first few dozen rounds ([evidence §3](design/evidence.md#3-first-calls-and-sessions); E-140).

### 2.4 Step 4: traits say what code needs, which makes the facts rule cheap

A **trait** is an abstract type with a declared, checked contract: operations with argument and result types, and fields with types ([traits §3](reference/traits.md#3-trait-declarations)). A type joins a trait by a declared **implementation**, `@implement X T`, checked when it is declared and never inferred from the methods that exist; the type then **conforms** to the trait ([traits §4](reference/traits.md#4-implementations)). A trait named at an argument is a **bound**; the **bounded function** reaches the argument only through the trait's operations and fields ([traits §5](reference/traits.md#5-bounded-functions)).

Traits make code fully typed where plain Julia would lose its types, by three mechanisms:
1. **Concrete keys.** A bounded function is compiled per **key**, what the bound can see of the value: the **receiver type** (the type whose own methods serve the operations: the conforming type, or the field it forwards to) and the declared fields' types ([traits §6.7](reference/traits.md#67-what-compiled-code-is-compiled-for)). Its reads and calls are at fact signatures, so type-stable code over concrete keys is fully typed and pays nothing for the facts rule. A trait may **enforce** concreteness, in one declaration with a level (silent, warn, error; [traits §11](reference/traits.md#11-concreteness-and-concrete-mode)), so that type-stable code bounded by it is always fully typed.
2. **Declared result types at abstract positions.** Where a value is heterogeneous on purpose, or the code does not know its type, it is `Dynamic`; where the code knows its concrete type, `Compiled`. The type the code knows decides where a plain value enters, as in Rust and Swift; a trait or an annotation at a position gives another default there, a value keeps its attribute once it has one, and a cast, by the library or the caller, always wins ([traits §6](reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)). The heterogeneity is declared: a kept value (`Dynamic{X}`, `Compiled{X}`, or `Kept{X}`, which a trait's name in a field means in a trait module), a value of any type that conforms to `X`, reached through `X`'s operations ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)); `Callable{A, S}`, a function called with arguments `A` that returns an `S` ([traits §5.8](reference/traits.md#58-callable-functions-at-a-declared-signature)). Their operations have declared, checked result types. They give back what the facts rule takes away, a result type at an abstract call, from a declaration rather than from the methods that exist today.
3. **Declared implementations.** A `Dynamic{X}` holds a value of one of the declared implementations' types. So an operation on it **splits** at the call site, as union splitting does: `isa` branches over at most four declared implementations, each a direct call; any other type is called through a table of the call's targets keyed by its type, without an edge to the list ([facts §9](reference/facts.md#dynamic-split); [compiler §4.3](reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)). This takes the place of the speculation the facts rule removes.

**Heterogeneous collections are the clearest case.** In plain Julia they are containers with an abstract element type: `Vector{AbstractShape}`, `Vector{Any}`, `Dict{String,Any}`.
- The element type says neither which operations the loop needs nor what they return. Plain Julia makes such loops tolerable by its heuristics, which the facts rule removes: these containers are its tails (`filter!` on a `Vector{Any}`).
- `Vector{AbstractShape}` is a poor substitute for what the code means, "something I can iterate whose items provide `Shape`". A collection trait with a declared item bound, `Iterable{Shape}`, says that directly. The loop is compiled per key. Items of an abstract type are `Dynamic`, and each operation on one is the `Dynamic` split, not a call at `Any`; items of a concrete type are `Compiled`.
- A user's existing `Vector{Any}` is passed as it is. The function's **entry**, the small method that receives a caller's values and translates each by its bound, sees it as a view that wraps each element when it is read: no copy, and the user's vector stays the one read and written. This is the shape of Rust's `impl Iterator<Item = &dyn Shape>` and Swift's `some Sequence<any Shape>`: the code states the bound, the producer chooses the representation ([other languages](design/other-languages.md)).
- Collection traits are built in BaseTraits, the trait world's standard library ([traits §8.1–8.4](reference/traits.md#81-basetraits-traits-for-bases-concepts)). Within the split's limit of four implementations the idiomatic loops recover the tails, at 1–5 ns per element against 38–276 ns for trait code calling Base on the same containers; beyond four each value of another type costs a probe and an indirect call, 9–18 ns at 16–64 implementations ([evidence §2](design/evidence.md#2-run-time); E-134, E-144, E-145).

So the tails on heterogeneous collections argue for traits with the facts mode, not against it (2.6). What is measured where trait code calls Base's generic algorithms on plain containers is the cost of calling into ordinary code, which the facts mode exists to make smooth and correct (the evidence calls it interop), not the cost of idiomatic trait code. Type-unstable code was never claimed to be fast in Julia; under the facts rule it stays correct and gets slower in the tails. The design's principle: a slowdown is tolerated when redesigning the code with traits recovers it.

### 2.5 The default: following pirates, and what it gives up

Step 2 is a switch. The default session leaves it off: a winning pirate is followed, as plain Julia follows it, and the code with that fact compiles again, once.

- **The compiled code is the same either way.** Strict mode acts only when a method is defined or an image's methods are activated.
- **Two tiers of the guarantee,** for trait code ([facts §2.3](reference/facts.md#two-tiers)):
  - strict: invalidated only by a stakeholder's change. A static property of every environment that loads without a `PirateError`, with the exceptions of 2.2;
  - default: invalidated only by a stakeholder's change or a pirate that wins at one of its facts. Whether one does is an empirical property of the environment ([evidence §1](design/evidence.md#1-the-guarantee)).
- **What the default gives up:**
  - the kind of guarantee: a theorem becomes a measurement;
  - who learns: an error at the pirate's definition becomes a silent recompile;
  - trust in package images: in strict mode's intended design, a pirate loaded before an image is an error; by default it is a recompile;
  - order independence: by default the set of methods is order-independent, and only when code compiles depends on order. In strict mode compiled code's validity is order-independent, but the set of methods depends on order (a pirate defined after the code is refused, one defined before it is selected) until a planned lint, `verify_main` listing the facts of trait code that select such a pirate, restores the symmetry ([facts §10.3](reference/facts.md#strict-intended)).
- **Why it may be presented as a later, separate choice:** strict mode changes nothing at run time; identical or error and the measurements do not depend on it; both tiers are stated; the exceptions of 2.2 are listed wherever the guarantee is claimed.

### 2.6 How the two goals interact

- **Goal 1:** composable caching of compiled code, and AOT: compiled code never invalidated unless code it depends on changes (steps 1–3).
- **Goal 2:** code says what it needs, and compiled code serves every type that provides it (step 4; [traits §6.7](reference/traits.md#67-what-compiled-code-is-compiled-for)).

How they depend on each other:
- **Goal 2 makes goal 1 cheap:** fully typed code pays nothing for the facts rule, and declared results and implementations recover what the rule takes from code that is heterogeneous on purpose.
- **The facts rule makes goal 1 unconditional:** code that is not fully typed keeps the guarantee, with run-time sites instead of fragile edges, and pays in speed only there.
- **Goal 1 makes goal 2 worth having:** code compiled per key is cached in the image of the package that compiled it and never discarded by an unrelated load, so the per-key copies are compiled once, not once per session.
- **AOT follows from goal 2:** dispatch through trait code goes to declared targets that a build can list ([traits §13](reference/traits.md#13-compiling-ahead)).

| Code | Guarantee | Cost of the facts rule |
|---|---|---|
| fully typed, plain Julia or trait code | step 1 today; never invalidated with step 2, which the design applies to trait code | none: inference by facts is plain inference |
| trait code over concrete keys, type-stable | as above, enforceable per trait | none |
| trait code at declared abstract positions (`Dynamic{X}`, `Callable`) | never invalidated by an unrelated load | a dispatch or indirect call per use, result type declared; the call-site split for `Dynamic` |
| plain code that is not fully typed | only under the test bed `all` | Julia's heuristics lost at its run-time sites: the tails of 2.3 |

## 3. The design in brief

The pieces the argument relies on, in one example. Each is defined precisely in a reference.

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

- `@trait` declares the contract ([traits §3](reference/traits.md#3-trait-declarations)). A trait may also declare associated types: its parameters, one value per implementation.
- `@implement` is checked when it is declared, never inferred from the methods that exist. The operations are served by the type's own methods, by one field it forwards to (always named with `by`), or by the trait's defaults ([traits §4](reference/traits.md#4-implementations)).
- `colmean` is compiled for what its bound can see, the key: once for `Vector{Vector{Float64}}`, and every table type that forwards to such a field runs that code from the library's image ([traits §6.7](reference/traits.md#67-what-compiled-code-is-compiled-for)).
- Mixed values are declared: kept values, `Kept{X}` (a trait's name in a field), `Dynamic{X}` or `Compiled{X}` ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)), `Callable{A, S}` for functions at a declared signature ([traits §5.8](reference/traits.md#58-callable-functions-at-a-declared-signature)). Every value in trait code is `Compiled` or `Dynamic`: values carry, annotations give defaults where a plain value enters trait code, and explicit casts always win ([traits §6](reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)).
- **Three rules carry it:** facts (compiled trait code depends on the method table only through facts; trait code may call any Julia code), ownership (only a stakeholder or a winning pirate can change a fact; the same rule says who may implement), and the boundary (only values cross into trait code, each translated once by its bound). Two guarantees follow: identical or error, and stable caches, which is that no unrelated load invalidates code compiled by facts ([facts §2](reference/facts.md#the-guarantees)).
- **Julia provides** the facts rule as a mode of its own inference, code compiled by facts beside plain code, dynamic dispatch from facts code to facts code, and the call-site split for `Dynamic` ([the compiler reference](reference/compiler.md); [changes to Julia](design/julia-changes.md)).

What is built, and what is not yet: [the state](state.md). What the measurements show, with builds and baselines: [the evidence](design/evidence.md); where the costs come from: [performance](design/performance.md).

## 4. What is not claimed

- No change to results beyond values that Julia decides by inference, such as the element type of an empty `map`.
- "Never invalidated" is strict mode's tier, for trait code; the prototype of strict mode lacks parts of its intended design ([facts §10.3](reference/facts.md#strict-intended)).
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
