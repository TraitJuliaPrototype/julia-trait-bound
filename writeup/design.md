# Trait-bound Julia: the design

This is a design for traits in Julia, written for Julia's core developers. It is built as a patched Julia 1.13 (the unified build) and a package, TraitWorld, and measured on demonstrators and ports: an ODE solver and the SciML port, a plotting library, a data report with its own CSV reader and table library, ports of CSV.jl and DataFrames.jl, and NetworkDynamics.

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

The argument starts from what is true of Julia today and adds one step at a time. Its terms, defined precisely in [facts §1](reference/facts.md#1-terms) and [§3](reference/facts.md#3-fact-signatures):
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

Step 1 leaves one source of invalidation that is not the code changing: a winning pirate. **Strict mode** is a switch that refuses it where it is defined ([facts §11.2](reference/facts.md#112-strict-mode)). The error, `PirateError`, names the method and the code it would have changed. The refused method does not exist for plain Julia either, so every call still computes what plain Julia computes, or raises: **G1, identical or error** ([facts §2.1](reference/facts.md#21-g1-identical-or-error)).

With the switch on, fully typed code has the guarantee the design is built on:

> **Fully typed code is never invalidated unless code it depends on changes.**

"Code it depends on" is precise: the stakeholders of its facts. "Never" has exceptions, named with the guarantee wherever it is claimed ([facts §2.2](reference/facts.md#22-g2-stable-caches)):
- **A stakeholder's change:** edits, Revise, upgrades, a stakeholder's package extension, a redeclared membership. A standard library's method on Base's types counts as one, since Julia is one owner.
- **A stakeholder's extension activated by an unrelated package,** whose method applies at a fact without naming its triggers' types: followed as the stakeholder's own change, never refused; in strict mode a warning names the method and the code it affects.
- **A binding redefined from another module** (`Core.eval(Other, …)`): strict mode refuses it at its source ([facts §11.3](reference/facts.md#113-strict-modes-errors-at-their-sources)).
- **A method on a closure's type from outside its module:** the closure form of fact signature assumes there is none.

The refusal is narrow, so extending and hooking into existing code keep working:
- **Hooks on your own types are never refused:** `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`. The definer is a stakeholder of every signature they apply to.
- **Memberships are the extension point.** A membership, the declaration that a type joins a trait (§2.4), changes no fact: compiled code never relies on a type's not being a member, and a call that a later membership could change is guarded ([facts §10](reference/facts.md#10-memberships)). So a membership invalidates nothing. A trait's author may close the trait after load instead: its non-memberships are then final once the declaring packages have loaded, and only a membership declared later invalidates ([traits §3.4](reference/traits.md#34-open-and-closed)); Base's `IO` does ([traits §9b](reference/traits.md#9b-streams-io)). Package extensions declare memberships: TraitCSV's extension declares one for InlineStrings' `String15`, and the reader compiled for `Float64` columns keeps its code.
- **What is refused** is exactly a method of a function you do not own, for types you do not own, that would win at a fact of protected code. Of 65,318 methods in CSV, DataFrames and CairoMakie, 837 are pirates by the letter, and none would be refused (`experiments/facts/g2strict.jl`, on the package prototype; [evidence §1](design/evidence.md#1-the-guarantee)).

The step holds for any fully typed code. The design applies the switch to code compiled by facts, defined in step 3. A trait module defines no pirate of its own: it refuses one at its definition, whether it would win or not ([traits §12.2](reference/traits.md#122-pirates), [§13](reference/traits.md#13-scopes-trait-modules)), as Rust's orphan rule does for new code.

### 2.3 Step 3: the facts rule extends the guarantee to code that is not fully typed

Most code is not fully typed. Where inference ran at an abstract signature, any owner's method for its own type breaks the edge, and there is nobody to refuse (problem 1).

**The facts rule:** compiled code depends on the method table only through facts. A call that is not at a fact signature is a **run-time site**: it dispatches at run time, as plain Julia's dynamic dispatch does, and records nothing that a later method could break ([facts §5](reference/facts.md#5-run-time-sites)). Nothing is skipped: a fact is invalidated exactly when a definition changes dispatch at its signature. So code **compiled by facts** is invalidated only as step 1 says, fully typed or not, and step 2's refusal gives it the guarantee, **G2, stable caches** ([facts §2.2](reference/facts.md#22-g2-stable-caches)).
- Verified: four definitions by owners that invalidate on 1.13.2 (an owned method at an abstract call, a new subtype under union splitting, a `return_type`-dependent `map`, a new type at a kind) invalidate nothing under the rule ([evidence §1](design/evidence.md#1-the-guarantee)).
- **Which code.** Each method has a **policy**: facts, plain, or its caller's ([facts §6](reference/facts.md#6-which-code-is-compiled-how)). A **trait module**, a module declared `@trait_module`, compiles its methods by facts, whoever calls them; its code is **trait code**, all other code **plain code** ([traits §13](reference/traits.md#13-scopes-trait-modules)). In the **product setting** everything else keeps all of Julia's behaviour. The test bed **`all`** compiles every method but the compiler's by facts, to test the rule on code as it is written today ([facts §13](reference/facts.md#13-the-settings)).
- **One CodeInstance per MethodInstance and policy** ([compiler §2.3](reference/compiler.md#23-one-codeinstance-per-methodinstance-and-policy)): a method reached from both kinds of code has a copy of each, in the same cache. Whether a CodeInstance meets G2 is a bit on it, computed from what it recorded ([compiler §3.2](reference/compiler.md#32-g2-as-a-predicate)); a package image keeps code that a session reaches only dynamically where the bit is set ([compiler §9](reference/compiler.md#9-images-and-the-machine-code-cache)).
- **Strict mode's scope is code compiled by facts:** it refuses a pirate that would win at one of its facts ([facts §11.2](reference/facts.md#112-strict-mode)). So in strict mode such code is never invalidated except by a stakeholder's change: step 2's guarantee, carried by the facts rule to code that is not fully typed.
- **The compiler is compiled plainly,** whoever calls it ([facts §6.4](reference/facts.md#64-the-compilers-own-code)). Code compiled by facts that holds a code edge into plain code is compiled again when that code changes. The loss is cacheability, not correctness; [open issues](open-issues.md) §1 lists it among the decisions that make speed hard.

**The cost sits exactly where code is not fully typed.**
- For fully typed code, inference by facts *is* plain inference: the same calls, edges and code.
- Elsewhere, the rule removes Julia's heuristics for type-unstable code: speculation over the methods that match today, a result type from the one method that matches today, inlining and compile-time evaluation at abstract calls. Such a call's result is `Any`, which spreads into the code after it.
- Under `all`, Julia's BaseBenchmarks run at a geometric mean of 1.037 against plain; the tails, up to 27.8×, are on containers of `Any`, abstract element types and small unions ([evidence §1](design/evidence.md#1-the-guarantee)).
- On a whole session with upstream packages only, `all` saves the recompilation that loads cause and pays per round of work in Makie's containers of `Any`; a plotting session comes out ahead for the first few dozen rounds ([evidence §3](design/evidence.md#3-first-calls-and-sessions); E-140).

### 2.4 Step 4: traits say what code needs, which makes the facts rule cheap

A **trait** is an abstract type with two additions ([traits §1](reference/traits.md#1-overview), [§3](reference/traits.md#3-traits-are-abstract-types)):
- **Open membership:** a type may become a member after its own definition, by a declared **membership**, `@implement X T`. A membership is checked against the trait's contract when it is declared and never inferred from the methods that exist ([traits §5](reference/traits.md#5-joining-a-trait)).
- **A contract:** operations with argument and result types, declared fields, and the values of the trait's parameters ([traits §4](reference/traits.md#4-declaring-a-trait)).

Everything else is Julia's. A trait is written wherever a type is written; a method at a trait, `f(t::ColTable)`, is a method, and dispatch is Julia's ([traits §6](reference/traits.md#6-methods-at-traits)). A member's value is passed as itself, unwrapped ([traits §3.5](reference/traits.md#35-values)).

Traits make code fully typed where plain Julia would lose its types, by three mechanisms:
1. **Code compiled per member's type.** A method at a trait is compiled for each member's type that reaches it, as a method at an abstract type is. Its calls on the argument are at fact signatures, so type-stable trait code pays nothing for the facts rule. A trait may require that its members' declared fields and parameters are concrete, so that code over them is fully typed ([traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode)). Definition checking classifies each method: **fully bounded** where it reaches its argument only through the contract, **open** otherwise ([traits §7.3](reference/traits.md#73-fully-bounded-methods)); a fully bounded method could share one compiled copy among members with equal keys (Optional, [traits §7.2](reference/traits.md#72-the-key)).
2. **The attribute, and declared results at abstract positions.** Each trait argument at each call has an **attribute** ([traits §7.4](reference/traits.md#74-the-attribute-compiled-and-dynamic)): `Compiled` runs the code compiled for the value's type; `Dynamic` runs code compiled once at the trait, and each operation on the value dispatches when it runs, with a result of the declared type. Both run the same methods and give the same results. What decides, strongest first: a cast at the call, an attribute the value carries, the method's own marks, the trait's default, the module's fallback ([traits §7.5](reference/traits.md#75-what-decides)). Heterogeneity is declared: `Dynamic{X}` holds a member of `X` and keeps the attribute through storage ([traits §7.7](reference/traits.md#77-dynamicx)); `Callable{A, S}` is the set of functions a call at `A` reaches, with the result `S` checked on return ([traits §9](reference/traits.md#9-functions-callable)). Declared results give back what the facts rule takes away, a result type at an abstract call, from a declaration rather than from the methods that exist today ([facts §9](reference/facts.md#9-operations-on-a-value-typed-by-its-trait)).
3. **Declared memberships, split.** An operation on a value the code knows only by its trait **splits**, as union splitting does: the compiled code tests the value's type against the trait's members, up to four, calls each one's method directly, and calls through a table of the call's targets for the rest, without an edge to the list ([traits §7.9](reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait); [compiler §7.2](reference/compiler.md#72-the-split), [§7.3](reference/compiler.md#73-the-table-of-a-calls-targets)). This takes the place of the speculation the facts rule removes.

**Heterogeneous collections are the clearest case.** In plain Julia they are containers with an abstract element type: `Vector{AbstractShape}`, `Vector{Any}`, `Dict{String,Any}`.
- The element type says neither which operations the loop needs nor what they return. Plain Julia makes such loops tolerable by its heuristics, which the facts rule removes: these containers are its tails (`filter!` on a `Vector{Any}`).
- With traits the code says what it means: `area_sum(shapes::Iterable{<:Shape})`, "something I can iterate whose items are members of `Shape`". A `Vector{Shape}` holds the members' own values; each operation on an item is the split, with a declared result, not a call at `Any`. A `Vector{Dynamic{Shape}}` keeps the attribute with each item. This is the shape of Rust's `impl Iterator<Item = &dyn Shape>` and Swift's `some Sequence<any Shape>`: the code states the bound, the producer chooses the representation ([other languages](design/other-languages.md)).
- Collection traits are in BaseTraits, the library's traits for Base's interfaces, of which Base's types are members ([traits §10.1](reference/traits.md#101-basetraits)). On the julia-1.13 builds, within the split's limit of four members the idiomatic loops recovered the tails, at 1–5 ns per element against 38–276 ns for trait code calling Base on the same containers; beyond four, each value of another type cost a probe and an indirect call, 9–18 ns at 16–64 members ([evidence §2](design/evidence.md#2-run-time); E-134, E-144, E-145).

So the tails on heterogeneous collections argue for traits with the facts mode, not against it (§2.6). What is measured where trait code calls Base's generic algorithms on plain containers is the cost of calling into ordinary code, which the facts mode exists to make smooth and correct (the evidence calls it interop), not the cost of idiomatic trait code. Type-unstable code was never claimed to be fast in Julia; under the facts rule it stays correct and gets slower in the tails. The design's principle: a slowdown is tolerated when redesigning the code with traits recovers it.

### 2.5 The default: following pirates, and what it gives up

Step 2 is a switch. The default session leaves it off: a winning pirate is followed, as plain Julia follows it, and the code with that fact compiles again, once.

- **The compiled code is the same either way.** Strict mode acts only when a method is defined or an image's methods are activated.
- **Two tiers of the guarantee** for code compiled by facts ([facts §2.3](reference/facts.md#23-two-tiers)):
  - strict: invalidated only by a stakeholder's change. A static property of every environment that loads without a `PirateError`, with the exceptions of §2.2;
  - default: invalidated only by a stakeholder's change or a pirate that wins at one of its facts. Whether one does is an empirical property of the environment ([evidence §1](design/evidence.md#1-the-guarantee)).
- **What the default gives up:**
  - the kind of guarantee: a theorem becomes a measurement;
  - who learns: an error at the pirate's definition becomes a silent recompile;
  - trust in package images: in strict mode, a pirate loaded before an image is an error at its source ([facts §11.3](reference/facts.md#113-strict-modes-errors-at-their-sources)); by default it is a recompile;
  - order independence: by default the set of methods is order-independent, and only when code compiles depends on order. In strict mode compiled code's validity is order-independent, but the set of methods depends on order (a pirate defined after the code is refused, one defined before it is selected); a lint, `verify_main`, reports a fact of code compiled by facts that selects a pirate defined before it, and restores the symmetry ([facts §11.3](reference/facts.md#113-strict-modes-errors-at-their-sources)).
- **Why it may be presented as a later, separate choice:** strict mode changes nothing at run time; G1 and the measurements do not depend on it; both tiers are stated; the exceptions of §2.2 are listed wherever the guarantee is claimed.

### 2.6 How the two goals interact

- **Goal 1:** composable caching of compiled code, and AOT: compiled code never invalidated unless code it depends on changes (steps 1–3).
- **Goal 2:** code says what it needs, and compiled code serves every type that provides it (step 4).

How they depend on each other:
- **Goal 2 makes goal 1 cheap:** fully typed code pays nothing for the facts rule, and declared results and memberships recover what the rule takes from code that is heterogeneous on purpose.
- **The facts rule makes goal 1 unconditional:** code that is not fully typed keeps the guarantee, with run-time sites instead of fragile edges, and pays in speed only there.
- **Goal 1 makes goal 2 worth having:** code compiled per member's type is cached in the image of the package that compiled it and never discarded by an unrelated load, so the copies are compiled once, not once per session.
- **AOT follows from goal 2:** dispatch through trait code goes to declared targets that a build can list ([traits §16](reference/traits.md#16-compiling-ahead-closed-programs)).

**What G2's scope costs.** G2 covers code compiled by facts, not the plain code it calls ([facts §2.2](reference/facts.md#22-g2-stable-caches)). With one CodeInstance per MethodInstance and policy, facts code holds code edges into plain callees, and when a load invalidates such a callee, the caller is compiled again unless its callee's result is unchanged: the **code slot** then keeps the caller ([compiler §3.3](reference/compiler.md#33-the-code-slot)). Measured ([evidence §4c](design/evidence.md#4c-the-unifications-trade-offs-measured-on-todays-build)):
- the slot keeps about a quarter of the code loads invalidate (E-261, [evidence §1](design/evidence.md#1-the-guarantee));
- a session of loads pays 0.2–0.3 s with the slot, 0.7–1.0 s without it (E-265);
- an image that keeps plain code satisfying G2 keeps 50–92 % of the compile time its facts copies of Base held (E-266).

| Code | Guarantee | Cost of the facts rule |
|---|---|---|
| fully typed, plain Julia or trait code | step 1 today; never invalidated with step 2, which the design applies to code compiled by facts | none: inference by facts is plain inference |
| trait code at members' types, type-stable | as above; concreteness enforceable per trait | none |
| trait code at declared abstract positions (`Dynamic{X}`, `Callable`) | G2: never invalidated by an unrelated load | a dispatch or indirect call per use, result type declared; the split |
| plain code that is not fully typed | only under the test bed `all` | Julia's heuristics lost at its run-time sites: the tails of §2.3 |

## 3. The design in brief

The pieces the argument relies on, in one example. Each is defined precisely in a reference.

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
end

@implement ColTable Vector{Vector{Float64}} begin   # the library's own membership
    ncols(t) = length(t)
    col(t, i) = t[i]
end

struct Measurements; label::String; data::Vector{Vector{Float64}}; end
@implement ColTable Measurements by data     # forwards to its field `data`

colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))
```

- `@trait` declares the contract ([traits §4](reference/traits.md#4-declaring-a-trait)). A trait may have parameters, associated types with one value per member ([traits §3.2](reference/traits.md#32-parameters)).
- `@implement` is checked when it is declared, never inferred from the methods that exist. The operations are served by the type's own methods, by one field it forwards to (named with `by`), or by the trait's defaults ([traits §5](reference/traits.md#5-joining-a-trait)). After it, `Measurements <: ColTable`.
- `colmean` is a method at a trait. Called with a `Measurements`, it is compiled for `Measurements`; where its argument is `Dynamic`, it is compiled once, at `ColTable` ([traits §7.1](reference/traits.md#71-three-ways-to-compile-an-argument)). With keys (Optional), every table that forwards to a `Vector{Vector{Float64}}` field would share one copy ([traits §7.2](reference/traits.md#72-the-key)).
- Mixed values are declared: `Dynamic{X}` ([traits §7.7](reference/traits.md#77-dynamicx)), `keep(x)` to store an argument with its attribute ([§7.8](reference/traits.md#78-keeping-an-argument-with-its-attribute)), `Callable{A, S}` for functions at a declared signature ([§9](reference/traits.md#9-functions-callable)). A caller chooses the attribute at a call with a cast, `compiled_for(x)` or `with_dynamic(x)` ([§7.6](reference/traits.md#76-casts)).
- **Two rules carry it:** facts (compiled code depends on the method table only through facts; trait code may call any Julia code) and ownership (only a stakeholder or a winning pirate can change a fact; the same rule says who may declare a membership, [traits §12.1](reference/traits.md#121-who-may-declare-a-membership)). Two guarantees follow: G1, identical or error, and G2, stable caches ([facts §2](reference/facts.md#2-the-guarantees)).
- **Julia provides** sets and memberships in subtyping and dispatch, the policy per method and the facts inference, the attribute at a call, the split, and the guards that let a membership invalidate nothing ([the compiler reference](reference/compiler.md); [changes to Julia](design/julia-changes.md)).

What is built, and what is not yet: [the state](state.md). What the measurements show, with builds and baselines: [the evidence](design/evidence.md); where the costs come from: [performance](design/performance.md).

## 4. What is not claimed

- No change to results beyond values that Julia decides by inference, such as the element type of an empty `map` ([facts §2.1](reference/facts.md#21-g1-identical-or-error)).
- "Never invalidated" is strict mode's tier, for code compiled by facts; strict mode is Planned ([facts §2.3](reference/facts.md#23-two-tiers)).
- No "compiled once for any type": code compiled once at a trait (`Dynamic`) still calls each member's own methods, each compiled for its type, once, in its own image.
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
