# The implementation in detail

The precise form of the design that [`../design.md`](../design.md) explains in prose, for core developers, as of 2026-10-19. This page and `design.md` are the source of truth: where another document disagrees with them, they are current. Where this page is more precise than `design.md`, this page holds.

This page states the terms, the problem in cases, the argument with its exceptions, the trait language in summary, the rules, what Julia provides, the decisions in force, the evidence in short, and the state of the software. Its chapters give the rest:

1. [Mechanisms](mechanisms.md): declaring and conforming, generic implementations, families, dispatch, trait modules, definition checking, `Callable`, keywords, results like the input, `Dynamic`, the layout, caching, AOT, identical or error; where the prototype differs.
2. [Changes to Julia](julia-changes.md): every change, as built, with commits, files, tests and upstream status.
3. [Evidence](evidence.md): the measurements, with builds, baselines and run counts; what is not shown.
4. [Performance](performance.md): where the costs come from, which owner each piece of code needs, the costs that remain.
5. [Comparison](comparison.md): the choices against C++, Rust, Swift and Mojo, with [`../other-languages.md`](../other-languages.md), the research behind it.
6. [Porting to traits](../intro/porting.md): a working guideline for porters, in the design's vocabulary.

What was tried and dropped is in [`alternatives.md`](alternatives.md). Open questions: [`../open-issues.md`](../open-issues.md), §1 (decisions waiting for the user) first. The full record, for agents: [`../record/INDEX.md`](../record/INDEX.md). Proofs: [`../explorations/wrapping-by-facts.md`](../explorations/wrapping-by-facts.md). Strict mode: [`../explorations/strict-mode.md`](../explorations/strict-mode.md). AOT: [`../explorations/aot-under-facts.md`](../explorations/aot-under-facts.md).

**Section numbers.** Documents written before 2026-10-19 cite these sections as `design.md` §1–§9; the numbers are the same here.

## Contents

1. Terms
2. The problem
3. The argument in four steps
4. Traits: saying what code needs
5. The three rules
6. What Julia provides
7. The decisions in force
8. What the evidence shows, and what it does not
9. The software: today, the target, the order of work

---

## 1. Terms

Each term is defined once, here. Each term's origin and precedents: [`../glossary.md`](../glossary.md).

- **Method table, dispatch.** Julia's methods, and the choice of a method for a call's argument types.
- **CodeInstance.** One compiled specialization of a method, with the assumptions inference made.
- **Invalidation.** Discarding a CodeInstance because a new method changes the result of a dispatch it assumed.
- **Owner.** A package owns its functions and types. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent. The session owns what is defined at the prompt.
- **Stakeholders of a method.** The owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one.
- **Pirate.** A method defined by none of its stakeholders. This is Julia's "type piracy", as Aqua.jl checks it, made strict for unions.
- **Stakeholders of a concrete signature.** The owner of its function and the owners of every type in it, of their supertypes, and of the types bounding their parameters.
- **Fact.** "At concrete signature `s`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
- **Run-time site.** A call in compiled code whose argument types are not a fact signature. It records nothing and dispatches at run time.
- **Facts mode.** Compiling so that code depends on the method table only through facts.
- **Trait.** An abstract type with a declared, checked contract: operations with result types, fields with types, associated types as parameters.
- **Implementation.** The declaration `@implement X T` that type `T` joins trait `X`: an implementation of `X` for `T`. Its operations are served by the type's own methods, by a field it forwards to (`by f`), or by the trait's defaults.
- **Receiver type.** The type of the value the operations are called on: the type whose own methods serve at least one operation, that is, the conforming type or the field it forwards to. There is none when the trait's defaults serve every operation.
- **Key.** What a bound can see: the receiver type, if any, and the declared fields' types.
- **Trait object.** What library code receives for a bounded argument: the user's object, seen through the offsets of what the bound can see.
- **Entry and worker.** A bounded function's entry translates each argument by its bound. Its worker is the body, compiled per tuple of keys.
- **Trait module.** A module whose code is written against traits (`@trait_module`). Its code is *trait code*. Everything else is *plain code*.

## 2. The problem

Julia compiles a method for the concrete types of its arguments and caches the result. Two things go wrong with that cache.

**Problem 1: compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used.
- Where inference ran at an abstract signature, the code depends on every method that matches there.
- Any package that adds a method for its own type can change that answer, and the code is discarded. No piracy is involved. `Base.show(io, ::MyType)` in MyPackage invalidates every caller compiled at `show(::IO, ::Any)`-shaped signatures.
- Measured: `using CairoMakie` discarded code at 769 signatures on Julia 1.12, none of them concrete.
- A package's own extension can discard its compiled code: with DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s, because DataFrames loads InlineStrings and that activates CSV's extension `CSVInlineStringsExt`, which adds methods to CSV's internal functions. This is a stakeholder's extension (3.2), not an unrelated package's method. In the trait world an extension declares an implementation instead, which discards nothing (TraitCSV's `String15`).
- Package images cannot help: the code they hold is discarded the same way. Without stable caches, neither composable caching across packages nor ahead-of-time compilation is reliable.

**Problem 2: code cannot say what it needs.**
- A field or argument is typed concretely or abstractly.
- Concretely, code is compiled per type and carries every part of the value, read or not. In SciML a new callback closure recompiles the solver (0.84–0.96 s), although the step never reads the callback. A type of 3,553 characters prints in an error.
- Abstractly (`Vector{AbstractVector}` where the code means "a vector of columns"), there is one copy of the code, but every operation is a dynamic dispatch. Inference speculates over the methods that exist today, which is the abstract edge of problem 1.
- Nothing checks what an abstract type promises. Mistakes surface deep inside the library.
- The result is silent performance cliffs, overparametrized types, and compiled code multiplied by every type that differs only in what the code never reads.

The two problems meet at abstract types: they are where code loses its types, and where compiled code becomes fragile. Section 3 makes that precise.

## 3. The argument in four steps

One term first. Code is **fully typed** when every call in it is at a *fact signature*, and so is every call in the code compiled into it, transitively. A fact signature is a tuple of concrete types, its union splits, the splits of unions of concrete element types inside tuple arguments (up to four), or a closure's call at kinds (section 5, rule 1). A type passed as a value to a function its caller does not own (`make(::Type{T})` at `T::DataType`) is a kind, and the call is not fully typed.

### 3.1 Step 1: fully typed code is already invalidated only by stakeholders and pirates

This is true of plain Julia today.
- Plain inference infers a fully typed call at its concrete signature, so every edge of fully typed code is a fact: "at signature `s`, dispatch selects `r`".
- **Lemma O:** a method that applies at a concrete signature and is no pirate is defined by a stakeholder of that signature. So only a stakeholder or a pirate can change a fact.
- A stakeholder's definition is "the code changing": an edit, an upgrade, an extension of the package that owns the function or a type in the signature.
- A pirate changes compiled code only if it wins at a fact. One that loses changes nothing, in any load order (Lemma D).
- Verified on 1.13.2 (`../reviews/2026-10-18-framing-and-motivation.md` §0, reproduced with the in-tree facts mode): a stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7) invalidate code at concrete signatures; a losing pirate (S6) never does.
- Proofs: `../explorations/wrapping-by-facts.md` (Lemma O, Lemma D, Theorems 1–3).

### 3.2 Step 2: outlaw pirates, and fully typed code is always valid and can be cached

**Strict mode** refuses a pirate that would win at a fact of compiled code, where it is defined: at the prompt, by `include`, or as a package image's methods activate (Julia piece 1). The error names the method and the code it would have changed. The method then does not exist for plain Julia either, so a call still computes what plain Julia computes ("identical or error").

With step 2 alone, in plain Julia and without traits, fully typed code satisfies the guarantee:

> **Compiled code is never invalidated unless code it depends on changes.**

"Code it depends on" is precise: the stakeholders of its facts. "Always valid" means valid except for the following, named with the guarantee wherever it is claimed:
- **A stakeholder's definition:** edits, Revise, upgrades. This is the stated exception.
- **A package extension (or Requires block) of a stakeholder** whose method applies at a fact without mentioning its trigger's types, activated by loading the unrelated trigger. Either refused by an extension rule or admitted as the stakeholder's own change: still open ([`../open-issues.md`](../open-issues.md) §1.10).
- **A binding the code reads, redefined from another module** (`Core.eval(Other, …)`). The theory does not cover bindings yet, and no hook sees them (`open-issues.md` §1.10).
- **A pirate already in a package image** when the code was compiled. Image validation discards the facts it breaks; piece 15 turns that into an error.

The refusal is narrow, so extending and hooking into existing code keep working:
- **Implementations are the sanctioned extension point.** An implementation is a method of a registry declared with `@max_methods 1` and a fallback, so it applies at no existing fact and invalidates nothing. In TraitCSV, InlineStrings' `String15` conforms from an extension, and the reader compiled for `Float64` columns keeps its code. This is what package extensions become.
- **Hooks on your own types are never refused.** `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`, an operation of someone's trait for your type: the definer is a stakeholder of every signature they apply to.
- **What is refused** is exactly a method of a function you do not own, for types you do not own, that would change what compiled code computes. Measured on CSV, DataFrames and CairoMakie: 65,318 methods checked, 837 pirates by the letter, none refused (`experiments/facts/g2strict`; measured on the previous prototype, under the package policy; not rerun on the compiler).

### 3.3 Step 3: the facts rule extends the guarantee to all code, at a cost where code is not fully typed

Most code is not fully typed. Where inference ran at an abstract signature, the edge can be broken by any owner adding a method for its own type, and there is nobody to refuse (problem 1).

**The facts rule (rule R):** compiled code depends on the method table only through facts. A call that is not at a fact signature is a *run-time site*: it dispatches at run time, as plain Julia's dynamic dispatch does, and records nothing. Nothing is skipped: a fact is invalidated exactly when a definition changes dispatch at its signature. With rule R, every compiled CodeInstance is invalidated only as step 1 says, and step 2 makes the guarantee hold for all code.
- Verified: four non-pirate definitions that invalidate on 1.13.2 (an owned method at an abstract call, S1; a new subtype under union splitting, S2; a `return_type`-dependent `map`, S3; a new type at a kind, S8) invalidate nothing in facts mode. The in-tree mode reproduces all eight cases.

**The cost sits exactly where code is not fully typed.**
- For fully typed code, facts inference *is* plain inference: the same calls inferred, the same edges, the same code.
- Elsewhere, the facts rule removes Julia's heuristics for type-unstable code: speculation over up to `max_methods` matching methods, a result type taken from the one method that matches today, compile-time evaluation over abstract calls. The result of such a call is `Any`, and `Any` spreads into the code after it.
- Measured on an earlier build, with (A) as a forked Compiler package and Base compiled plainly in the system image, before parts B–D and the inliner changes (to rerun on the current test bed): BaseBenchmarks geometric mean 1.016, 1.064 without `scalar`; the concrete groups within 1.00–1.09; the tails from 1.3× (`io`) to about 80× (containers of `Any`), on containers of `Any`, abstract element types and small-union broadcasts. One run, `--pkgimages=no`.

### 3.4 Step 4: traits say what code needs, which makes the facts rule cheap, and can enforce concreteness

Traits make code fully typed where plain Julia would lose its types, by three mechanisms:
1. **Concrete keys.** A function bounded by a trait is compiled per key: the receiver type and the declared fields' types. Its reads and calls are at concrete signatures. Type-stable code over concrete keys is fully typed, so it pays nothing for the facts rule. A trait may **enforce** concreteness (one declaration with a level: silent, warn, error; section 4.3), so that type-stable code bounded by it is always fully typed.
2. **Declared result types at abstract positions.** Where a value is heterogeneous on purpose, the heterogeneity is declared: `Dynamic{X}` for values, `Callable{A, S}` for functions. Their operations have declared result types, checked. They give back exactly what the facts rule takes away, a result type at an abstract call, from a declaration rather than from the methods that exist today.
3. **Declared implementations.** The types a `Dynamic{X}` value can hold are those of the declared implementations, so an operation on it splits at the call site (`isa` branches, direct calls that inline, a dynamic fallback), as union splitting does, without an edge to the list (part D, section 6). This takes the place of the speculation the facts rule removes.

Type-unstable code was never claimed to be fast in Julia. Under the facts rule it stays correct and gets slower in the tails. The design's answer is the user's principle: a slowdown is tolerated when redesigning the code with traits recovers it (the raytrace through `Dynamic`, section 8; `parse_json`'s tail is recovered by a plain-Julia fix as well, a typed capture).

### 3.5 The default: following pirates (rule P), and what it gives up

Step 2 is a switch. The default session leaves it off: a winning pirate is followed, as plain Julia follows it, and the code with that fact recompiles once.

- **The compiled code is the same either way.** Strict mode acts only at a method's definition and at image activation (verified, `TraitWorld/src/strict.jl`).
- **Two tiers of the guarantee:**
  - strict: invalidated only by a stakeholder's change. A static property of every environment that loads without a `PirateError`, with the exceptions of 3.2;
  - default: invalidated only by a stakeholder's change or a pirate that wins at one of its facts. Whether one does is an empirical property of the environment. On the package prototype (`experiments/facts/g2all`) none did over twelve loads; on the compiler under `all`, 2 of 3,340 upstream CodeInstances were lost to nine loads and are not yet attributed, and one recompilation is diagnosed (a standard library's `vcat`, section 8).
- **What the default gives up:**
  - the kind of guarantee: a theorem becomes a measurement;
  - who learns: an error at the pirate's definition becomes a silent recompile;
  - trust in package images: with piece 15, a pirate loaded before an image is an error; by default it is a recompile;
  - order independence: by default the set of methods is order-independent and only when code compiles depends on order; under strict mode compiled code's validity is order-independent, but the set of methods depends on order unless the symmetric lint runs (`verify_main`).
- **Why it may be presented as a later, separate choice:** strict mode changes nothing at run time (verified); "identical or error" and the measurements do not depend on it (verified); both tiers are stated; the exceptions of 3.2 are listed wherever the guarantee is claimed. One condition is not met yet: strict mode under the `all` setting is unmeasured.

### 3.6 How the two goals interact

The two goals are not independent.
- **Goal 1:** composable caching of compiled code, and AOT: compiled code never invalidated unless code it depends on changes (steps 1–3).
- **Goal 2:** code says what it needs, and compiled code serves every type that provides it (step 4, section 4).

How they depend on each other:
- **Goal 2 makes goal 1 cheap.** Concreteness makes the guarantee free: fully typed code pays nothing for the facts rule. Declared results and declared implementations recover what the facts rule takes from code that is heterogeneous on purpose.
- **The facts rule makes goal 1 unconditional.** Code that is not fully typed does not lose the guarantee; it becomes run-time sites instead of fragile edges, and pays in speed only there.
- **Goal 1 makes goal 2 worth having.** Code compiled per key is cached in the image that compiled it and is never discarded by an unrelated load, so the per-key copies are compiled once, not once per session.
- **AOT follows from goal 2:** dispatch through trait code goes to declared targets that a build can list (section 4.8).

| Code | Guarantee | Cost of the facts rule |
|---|---|---|
| fully typed (plain Julia or trait code) | step 1 today; always valid with step 2 | none: facts inference is plain inference |
| trait code over concrete keys, type-stable | as above, enforceable per trait | none |
| trait code at declared abstract positions (`Dynamic{X}`, `Callable`) | always valid | a dispatch or indirect call per use, result type declared; the call-site split (D) for `Dynamic` |
| plain code that is not fully typed | always valid only with the facts rule | Julia's heuristics lost at its run-time sites: the tails of 3.3 |

## 4. Traits: saying what code needs

Section 3.4 named the three mechanisms by which traits make the facts rule cheap. This section gives the detail: code says what it needs, is compiled for exactly that, checked once, and typed without speculating over today's methods. The mechanisms in full: [`mechanisms.md`](mechanisms.md).

### 4.1 Traits and implementations

- **A trait is an abstract type with behaviour.** It declares operations (generic functions with argument and result types), fields (with types; writable unless `@const`), and associated types as parameters (`@trait Integrator{U, P}`). Defaults are written in terms of the other operations and fields.
- **An implementation is declared,** `@implement ColTable MyType`, also after the type was defined. It is never derived from the methods that exist: Base's throwing fallbacks make structural matching unsound.
- **Operations** come from the type itself or are forwarded to one field (`by data`). **Declared fields** are stored fields, by name or mapped (`name => label`). The declaration is checked: every operation and field exists, with the declared types.
- **Associated types** are first-order: one value per implementation, defined by a field's type (`data::Vector{T}` against `Vector{Float64}` gives `T = Float64`) or by an equation of `Self`, bounded by traits or types. No input parameters, no equations between type functions: these made Rust's and Swift's checking hard ([`comparison.md`](comparison.md) §7).
- **Who may implement:** a stakeholder, the trait's owner or the type's owner (rule 2 below). Implementations are methods.

### 4.2 Compiled for what the bound can see

- A function bounded by a trait reaches its argument only through the trait's operations and fields.
- It is compiled per **key**: the receiver type, if any, and the declared fields' types. Not per the argument's own type.
- Types that differ only in what the trait cannot see share compiled code. Every table type forwarding `ColTable` to a `Vector{Vector{Float64}}` field runs the code the library compiled for that type. A solver step bounded by `Integrator` compiles nothing for a new callback, which the trait does not declare.
- **This is not "once for any type".** A type that supplies its own behaviour (implements an operation, overrides a default) is the receiver type and gets its own copy, compiled once, in its own image. Sharing comes from forwarding, from defaults over fields, from `Dynamic{X}`, and from `Callable` in its dynamic mode. Code shared across every conforming type through a witness, Swift's model, is not chosen ([`comparison.md`](comparison.md) §3).
- **The reference layout.** A trait object of a mutable value is the user's object, read at byte offsets, with Julia's alias metadata: nothing is copied, every read sees the current value, and loops run at plain Julia's speed. An immutable value is held, since none of its fields can be rebound. When it is itself the receiver, it is held whole, with no object or slot to read through (a *held view*), so a `Dynamic` of it is one box, as a plain abstractly typed value is. A key used both held and read through has one worker per view type. Typed trait calls: 36 ns against 33.7 ns for the same loop in plain Julia.
- **Inside a trait module,** a trait object is what its bound can see and nothing else. Internal functions take trait objects without bounds; definition checking follows them through.

### 4.3 Concreteness, opt-in per trait

- By default a key may be abstract, silently. An abstract part of a key behaves like a dynamic value: one worker, dispatch where it is read, opened at the next bound it is passed to.
- A trait (or a module) that asks for more says so in **one declaration with a level**: silent (the default), warn, or error. Error refuses an implementation whose key is not concrete, and a family member at an abstract parameter at its entry.
- Concrete means a concrete type with concrete parameters all the way down. Fields the trait does not declare are not looked at.
- The prototype spells the levels `@warn_on_abstract` and `@concrete_only` today; the single declaration is adopted and not yet built.

### 4.4 Overrides belong to the implementation

- Which operations an implementation serves by defaults is fixed when it is declared. Compiled code and kept values depend on it, as they depend on a struct's definition.
- A later method of an operation that a default serves for that type is refused, naming the fix. An image that brings such an override for an active implementation is refused at load.
- **A family member's implementation is fixed at its first use, not at the family's declaration.** This is forced by ownership: the owner of a member's parameter type (`MyT` in `S{MyT}`) is a stakeholder of `op(::S{MyT})` and may legitimately define it after the family was declared upstream. No worker or `Dynamic` exists for the member before its first use, so fixing it then is sound.
- **Changing an implementation interactively** needs a restart until redeclaration is built. Julia 1.13 redefines structs (verified: old values keep the old type, `@world(A, …)`, and old worlds answer as before); an implementation's redeclaration can use the same mechanism.

### 4.5 `Dynamic{X}`: a value of abstract type `X`

- A value that must outlive a call, an element of a collection of mixed keys, or a field whose key changes is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations and fields.
- **It holds the user's object.** The view for (X, the object's type) is a constant per pair.
- **An operation on it is a call-site split:** `isa` branches over the declared implementations, direct calls that inline, then a dynamic fallback, the result asserted to the declared type. The split belongs in Julia's inliner, as union splitting does (part D, section 6). It dispatches in the caller's world.
- **Opened at a bound:** passed to a function bounded by `X`, it selects the worker for its key once, and the worker runs compiled.
- **A trait's name in a field or container means its `Dynamic`** (`plots::Vector{Plot}`), inside trait modules until traits are in the type system. The explicit spelling always works.
- `Dynamic{X}` is the package's spelling of "a value of abstract type `X`". Its form is transitional, until membership is subtyping (Julia piece 7); its meaning is permanent.
- **No hidden type parameters** for fields declared by bounds: stored state of a fixed type uses explicit parameters, and of a changing type, `Dynamic{X}`.
- **As built:** an operation on a `Dynamic` value is a `Compiler.dynamic_call` site (part D, section 6); a `Dynamic` of an immutable value that is itself the receiver is one box holding the value (a held view, 4.2). The design does not use tables of pointers: a plain pointer runs in the latest world, not the caller's ([`alternatives.md`](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split)).
- **A world-checked call-site cache, built for `DynamicCall`'s pointers (4.6); for `Dynamic`, proposed** between the split and the fallback. Each entry holds a type, the entry point of the code compiled for it, and the world range in which that code is valid (a CodeInstance's `min_world`/`max_world`, which invalidation shortens). A call compares the type and the current world against an entry, then calls indirectly; a miss dispatches as now and adds an entry. The world check keeps the call in the caller's world and follows invalidation; entries are a session's cache, never saved, so images keep only the compiled code; entries are appended atomically. It is the polymorphic inline cache of Self and of JavaScript and Java virtual machines, made aware of Julia's worlds; it would serve more than four implementations at a few nanoseconds per call, and it serves `Callable`'s `DynamicCall` mode (4.6), where it is built per pointer.

### 4.6 Functions as arguments: `Callable`, two modes

- Julia has no type for "a function from `Float64` to `Float64`". A function handed down from plain code enters only at a declared signature: `Callable{A, S, M}`, arguments `A`, result `S`, mode `M`. Its one operation is checked at every call.
- **Two modes.** A library needs a compiled call whose function argument, an ODE right-hand side, has a declared and checked signature; Julia's type system cannot express that otherwise. And most function arguments are better called dynamically.
  - `DynamicCall`, the default: a pointer to the function's code at `A`; the worker is compiled once per signature, in the library's image; an indirect call per use (about 4 ns, measured on the earlier prototype).
  - `CompiledCall`: the worker is compiled per function type, with the function inferred into it, and the signature still declared and checked. This is what an ODE right-hand side needs: plain Julia's speed with a typed contract. An unbounded argument would specialize but check no signature.
  - The library sets the default; the caller overrides per value (`compiled_call(f)`, `dynamic_call(f)`). The mode is meant as a choice of speed, never of correctness.
  - **The pointer runs in the caller's world.** A plain `@cfunction` runs its function in the latest world, as a callback from C must; after a redefinition, a call in an older world would compute the new method's result (101 where plain Julia computes 2). `DynamicCall`'s pointer uses the calling convention `:caller_world` (a patch of codegen and the runtime, [`julia-changes.md`](julia-changes.md)): its thunk is a world-checked call-site cache, one entry per target, each valid for the worlds where the dispatch and the target's CodeInstance hold. A call compares the caller's world with the current entry's range and calls through it; any other world looks up its entry. The call costs 4.47 ns (a direct call 0.87 ns, a dynamic call 20 ns). Acceptance G1.20 and G1.21 (alternating worlds; a call before the method exists gives plain Julia's `MethodError`).
- `DynamicFn{A, S}`, made by `dynamic_fn`, is a `Callable` in `DynamicCall` mode as a value of fixed type, for functions stored in a library's types.
- Functions from trait code (Base's `abs2`, a trait module's own functions and closures) are called directly.
- Automatic differentiation tags are labelled by a `Callable`'s primal signature (`Tag{Sig{A, S}, V}`), so loss closures of one signature share the solver's code (implemented in TraitDifferentialEquations).

### 4.7 The rest of the trait language

- **Results like the input:** constructor operations returning `Self`, `Like{t}`, `withfields`, a result rebuilt as the user's type at the entry. TraitWorld's tests exercise all of them (also siblings, `LSeries{Float64}` to `LSeries{Float32}`, and `Dynamic` in and out); the demonstrators use only `Self` constructors (TraitCSV).
- **Definition checking:** library code is checked once at archetypes, where it is defined, for every type that will ever conform. A mistake is reported at its line before any user type exists. At the prompt it warns; the call raises.
- **Dispatch:** types first, then traits. A trait bound ranks above `Any` and below every type. This is what lets a library adopt traits one function at a time.
- **Keeping is detected, not declared:** a function whose code may keep a trait object receives the whole user's object; others receive what their bounds see. An optimization with a safe fallback.
- **Printing by bound and key:** `ColTable at Vector{Vector{Float64}}` (Julia piece 17).
- **Named implementations** (`via(M, x)`, anyone may write one) are deferred until traits are in the type system. The preferred form is a value-level wrapper that conforms (`Via{Fast}(x)`, a newtype), since the simplest `Dynamic` and membership as subtyping have no place for a witness inside the value.

### 4.8 AOT follows from declared targets

- Dispatch between trait code, and over the types a program meets at run time, goes through declared implementations. A `Callable` argument adds one target at its signature; a `Dynamic` value adds the implementations whose types reach where it is made. `verify_main` lists them.
- Plain code reached from trait code (CSV, Cairo) keeps plain Julia's AOT properties; `verify_main` reports its open sites as holes.
- A `--trim` build compiles the plain call in the closed world, so the facts mode is off in a build. Nothing loads in a binary, so there is no cache to protect, and "identical or error" holds by definition.
- So AOT is a consequence of goal 2 (declared targets), not of the facts.

## 5. The three rules

Three rules deliver the guarantee and the two goals. Where compiled code lives, and what a call sees, are Julia's own behaviour and need no rule ([`mechanisms.md`](mechanisms.md) §17).

1. **Facts.** Compiled trait code depends on the method table only through facts.
   - A *fact signature* is: a tuple of concrete types; its union splits; the splits of unions of concrete element types inside tuple arguments (up to four); a closure's call at kinds; a tuple of concrete types ending in `Vararg{E}` with `E` concrete and not a kind. The criterion: any signature at which only a stakeholder or a pirate can change dispatch.
   - Any other call is a run-time site: it dispatches at run time and records nothing. Under part C, a run-time site in facts-compiled code runs facts-compiled code where codegen emits the call (direct calls, `invoke`, `_apply_iterate` with known tuples, `invokelatest`); dispatch that goes through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code (`../reviews/2026-10-19-compiler-implementation.md` §2.4).
   - Compile-time evaluation only over facts. No asserted effect (method or statement level) applies to a frame with a run-time site.
   - Nothing is skipped (rule P): a fact is invalidated exactly when a definition changes dispatch at its signature.
   - Trait code may call any Julia code directly.
2. **Ownership.**
   - A method's stakeholders are the owner of its function and the owners of the types in its own signature; anyone else's method is a pirate.
   - Only a stakeholder or a winning pirate can change a fact (Lemma O).
   - Strict mode refuses a pirate that would win at a fact of compiled trait code; the default session follows it.
   - Implementations are methods, so the same rule says who may implement a trait for a type.
   - Ownership is never claimed. A package extension belongs to its parent. The curated list of delegates for split-core packages (StaticArrays for StaticArraysCore) is a claim made for an owner who cannot declare it yet, kept as data and marked transitional.
3. **The boundary.**
   - Only values cross into trait code. A bound translates each once: a trait bound takes the user's object and the offsets of what it can see; a declared type asserts; `Callable` takes a function at a declared signature, in one of its two modes, checked at every call.
   - Inside, a trait object is what its bound can see and nothing else.
   - Code is compiled per key.

**The central guarantees.**
- **Identical or error (G1).** A call in trait code computes what plain Julia computes in the current world, or raises. It rests on one assumption about values that inference decides (A3: `return_type` of empty collections, `Union{}` results). Threads are untested.
- **Stable caches (G2),** in the two tiers of 3.5.

## 6. What Julia provides

The design needs Julia's compiler and runtime. TraitWorld requires the patched build and does not run on stock Julia.

**The compiler parts.** The inventory, with commits, files and upstream status, is [`julia-changes.md`](julia-changes.md). Acceptance 21/21; TraitWorld's 47 test sets; the demonstrators' suites.

| Part | What it is |
|---|---|
| **(A)** facts as a mode of Julia's own inference | `NativeInterpreter` has a `facts` field. A call is inferred, with its edges, only at a fact signature (rule 1, including a concrete `Vararg` tail). `return_type` folds only an answer that cannot be wider than plain inference's, else plain inference's answer when it rests on facts, else at run time, where plain inference answers it in its own cache owner. No asserted effect applies to a frame with a run-time site. |
| **(B)** code compiled by facts beside plain code | A module option, `Base.Experimental.@compiler_options facts=true` (declared by `@trait_module`, inherited by submodules), makes its methods *facts methods*: compiled by facts under the owner `:facts`, whoever calls them. A method can be a **boundary** (`Expr(:meta, :facts, 0)`): compiled in its caller's mode, as a trait entry is (rule 3), or **always facts** (`Expr(:meta, :facts, 1)`: TraitWorld's `@machinery`). Reflection of a facts method is facts inference. Package images keep `:facts` code. |
| **(C)** dispatch from facts code | Run-time sites in `:facts` code run the callee's facts code where codegen emits the call (`jl_apply_generic_facts`, `jl_invoke_facts`: direct calls, `invoke`, `_apply_iterate` with known tuples, `invokelatest`). Dispatch through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code (review of 2026-10-19, §2.4). |
| **(D)** the `Dynamic` call-site split | `Compiler.dynamic_call(K, RT, f, x, args...)`: inferred as `f` at the union of `K`'s registered candidates (≤ 4, each split a fact), plus an asserted fallback; the join is typed `RT`, the trait's declared result. Candidates are registered without an edge: a later implementation reaches the fallback and invalidates nothing. |
| **The compiler stays plain** | The Compiler module is *never by facts*: a facts frame's call into the compiler leaves to plain inference (`leaves_to`), and Base reflection runs the native compiler in the compiler's world also for an explicit `NativeInterpreter`. **The boundary:** facts code that calls compiler functions directly (TraitWorld's machinery calls `argextype`, `widenconst`, `sptypes_from_meth_instance`) holds edges to plain compiler code, whose validity is plain Julia's (review of 2026-10-19, B1). A rule running such calls in the compiler's world would break code that extends the compiler for its own interpreter types. The loss is cacheability, not correctness; the control's nine-package load lost no facts code in the modules it counted (TraitMakie 0); TraitWorld's own code was not counted separately. |
| **Two inliner changes, for all code** | An invoke keeps the exact specialization inference made at concrete types when the compileable signature only widens a varargs tail; an inference cycle's members inline each other (callees optimized first). Both apply to plain code too: a varargs wrapper in a plain recursion takes 21.9 ms on stock 1.13.2 and 0.36 ms with them. |

**The switch:** `JULIA_COMPILE_BY_FACTS=1`, or a system image built with it (`experiments/factscompiler/scripts/build_facts_sysimage.sh`), compiles *all* code by facts (owner `nothing`): the test bed. Without it, only facts methods (trait modules) are compiled by facts: the product setting. `--trim` turns the facts mode off (a closed world compiles plain code).

**Julia pieces** (numbering of `../explorations/julia-support.md`; as built in [`julia-changes.md`](julia-changes.md) §3):
- **Kept:** 1 (method-definition and image-activation hooks, which strict mode needs), 3 (field-offset intrinsics), 17 (type printers), 9 (owner-aware bare MethodInstance edges) and 10 (the inliner uses the CodeInstance it is given), in the form a second owner needs; 5 (machine code for upstream CodeInstances in images: also plain Julia's gain, to be measured alone).
- **Add, for the strict tier:** 1′ (a deletion hook), 14 (a read-only "what would this definition invalidate" query, transitive), 15 (image validation reports the winning method).
- **Later:** 7 (traits in the type system: membership as subtyping), last.
- Pieces 2, 4, 6 and 11–13 are not part of the design ([`alternatives.md`](alternatives.md#the-invalidation-filter-and-other-julia-pieces-reverted-or-moot)).

**Upstream proposals, in order:** the general fixes (the run-time `return_type` entry in the image; reflection in the compiler's world; after broader measurement, the two inliner changes); pieces 10, 9 and 17 as fixes and a small feature; (A) as "a facts mode for the native compiler", with the benchmark table; pieces 1, 1′, 14, 15 with strict mode; (B) and (C) as per-method inference modes; traits in the type system last.

## 7. The decisions in force

The decisions that hold today, each with the section that states it. The register, with each decision's origin, the user's words and what the prototype runs, is [`../decisions.md`](../decisions.md); designs not chosen are in [`alternatives.md`](alternatives.md).

| Decision | Detail |
|---|---|
| A trait is an abstract type with behaviour; abstract types stay, traits are a kind of them | 4.1; [`comparison.md`](comparison.md) §1 |
| An implementation is declared, never derived | 4.1 |
| Keys: code is compiled for what the bound can see (receiver type, declared fields' types) | 4.2; §1 |
| An implementation in one line (`@implement X T`), its operations served by the type's own methods, by a field it forwards to (`by f`) or by the trait's defaults; no computed projections; declared fields are stored fields; forwarding does not chain | [`mechanisms.md`](mechanisms.md) §2 |
| The reference layout: a trait object reads the user's object at offsets | 4.2 |
| Associated types in first-order form; fields define parameters by matching | 4.1; `../explorations/associated-types.md` |
| Concreteness opt-in per trait, one declaration with a level (silent, warn, error) | 4.3 |
| Overrides belong to the implementation; family members fixed at first use (forced by rule 2); refused at load; restart until redeclaration is built | 4.4 |
| Definition checking at archetypes, at the module's end; a warning at the prompt | 4.7 |
| `Dynamic{X}`: a value of abstract type `X`, holding the user's object; operations by a call-site split in the compiler | 4.5 |
| A trait's name in a field or container means its `Dynamic` (inside trait modules) | 4.5 |
| No hidden type parameters | 4.5 |
| `Callable{A, S, M}` with two modes, `DynamicCall` the default, the caller overrides | 4.6 |
| AD tags labelled by the primal signature | 4.6 |
| Results like the input (`Self`, `Like{t}`, `withfields`) | 4.7 |
| Keeping detected, not declared | 4.7 |
| Types first, then traits, in dispatch | 4.7 |
| Printing by bound and key | 4.7 |
| Named implementations deferred to piece 7; a value-level wrapper preferred | 4.7 |
| AOT builds compile the plain call; `--trim` turns facts off | 4.8 |
| **The guarantee, strict mode first;** rule P the default relaxation | 3.2, 3.5 |
| **The framing in four steps:** fully typed code is already valid but for stakeholders and pirates; strict mode outlaws pirates; the facts rule extends the guarantee to all code at a cost where code is not fully typed; traits make it cheap and can enforce concreteness | 3 |
| **"Fully typed"** is the name of the property: every call at a fact signature, transitively, kinds excluded | 3 |
| **A fully-typed certificate:** concrete mode reports, per worker, whether it has run-time sites; a worker without them is fully typed and pays nothing for facts; `@concrete_only` traits (the `error` level) refuse workers that are not (built) | 3.4, 4.3 |
| Strict mode: one decision with two tiers; the intended design's items are the work list | 3.5; `open-issues.md` §1.10 |
| Under (B), strict mode protects facts-owned code | 3; `TraitWorld/src/strict.jl` |
| The symmetric check as a build lint | 3.5 |
| Three rules: facts (with the definition of a fact signature), ownership, the boundary | 5 |
| Facts at tuple splits and at concrete `Vararg` tails; run-time sites run facts-compiled code; no asserted effect applies to a frame with a run-time site | 5 |
| Stakeholders by the method's own signature; supertype owners count; the extension exception named | 1; 3.2 |
| Delegates as data, transitional | 5 |
| No sealing, of abstract types or functions: a closed contract is a trait | [`alternatives.md`](alternatives.md#sealing-rejected) |
| The facts policy in Julia's compiler: (A), (B), (C), (D) | 6 |
| `JULIA_COMPILE_BY_FACTS=1` (`all`) is a test bed; a command-line flag `--compile-by-facts=no\|all\|traits` is the target spelling, not built | 6 |
| The two inliner changes apply to all code | 6; [`julia-changes.md`](julia-changes.md) §2 |
| The compiler's own code is plain whoever calls it; TraitWorld's slow paths compiled by facts (`@machinery`); the checks on a `NativeInterpreter` with their own cache owner | 6 |
| A held view for immutable values that are themselves the receiver | 4.2 |
| TraitWorld requires the patched build; stock Julia appears only as a baseline | 6 |
| Slowdowns are tolerated if redesigning the code with traits recovers them. This governs trait code and the plain code it reaches | 3.4, 8 |
| The forks (demonstrator 4) run on the current compiler (upstream suites pass); their further work is the last step of the order of work | 9 |
| The runtime as methods: an implementation is a method; entries are ordinary methods; workers per key | `../explorations/keys-plan.md` §6 |
| Workspace: the design repository with separate repositories inside; local only | `../../README.md` |

## 8. What the evidence shows, and what it does not

The measurements, with builds, baselines and run counts, are in [`evidence.md`](evidence.md); where the costs come from, in [`performance.md`](performance.md). All numbers are from the patched Julia 1.13.2 build, on one machine, on the final build (julia-1.13 61852d8fb1, TraitWorld 375a930) unless stated.

**The four steps of section 3:**
- *Step 1, verified* in small cases (S4–S7), with the in-tree facts mode; proved in `../explorations/wrapping-by-facts.md`.
- *Step 2, verified* as a prototype: strict mode refuses winning pirates and nothing else in a real stack (837 pirates by the letter among 65,318 methods, none winning; measured on the previous prototype). Its intended design (pieces 1′, 14, 15, the extension rule, bindings) is not built.
- *Step 3, verified:* the cases that are not fully typed (S1–S3, S8) invalidate on 1.13.2 and not in facts mode; acceptance 19/19. **The control:** under `all`, nine unrelated loads cost PlainTables 0 of 206 CodeInstances (plain mode: 14 of 218) and upstream CSV + DataFrames 2 of 3,340 (plain: 570 of 4,712). Load protection is the facts rule's property, for any code.
- *Step 3's cost:* BaseBenchmarks under `all` (an earlier build, before parts B–D): geometric mean 1.016, tails on containers of `Any`. To rerun on the current compiler.
- *Step 4:* traits recover the tail tried: the raytrace through `Dynamic` (below). `parse_json`'s tail is recovered by typed captures, 1.17× the fixed plain code (an earlier build), a fix plain Julia makes too (`local pos::Int`), so it is no evidence for traits. The fully-typed certificate is built (`fully_typed`, concrete mode).

**Shown:**
- **The facts mode by itself, on the packages people use.** Upstream CSV.jl and DataFrames compiled in the facts mode (`all`) lose 2 of 3,340 CodeInstances to nine unrelated loads, against 570 of 4,712 in plain mode, and their first work takes 0.7 s instead of 3.6 s. No trait is involved: the guarantee of step 3, and a first-call gain, for code as it is written today.
- **Traits on top, against upstream:** the trait-based ports of CSV.jl and DataFrames run a scripted session's first calls in 2.9 s against upstream's 10.4 s. Upstream's full session under `all` is not measured, so the share of each contribution is open.
- **`Dynamic` values at near plain speed.** A sum over `Dynamic{Shape}`: 0.92–1.40 ns per element against plain's 0.87–0.91 with two types and 29.5–33 with four. The raytrace over an open set of primitives: 300–336 ms against plain's 246–259 with two types and 827–882 with four (a `max_methods` effect at four).
- **Traits bring load stability where the facts rule cannot: a package's own extension.** CSV.jl's extension for InlineStrings adds methods to CSV's internal functions. Loaded with DataFrames, it discarded the reader's code: the first read took 2.5 s against 0.19 s. That is a stakeholder's change (3.2), which the facts rule follows. TraitCSV declares an implementation for `String15` in its extension instead, and loading InlineStrings discards none of the reader's code. Measured on the package prototype; not rerun on the compiler. The coding pattern traits bring (extension by implementations, never by methods on a library's internals) is what protects even well-trodden parts of the ecosystem.
- **Typed trait calls cost little.** 36–38 ns against 33.8–34.5 ns for the same loop in plain Julia.
- **New trait code costs about the same in every load order (within 1.6×).** A new model type in TraitDifferentialEquations: `@implement` 142–164 ms, first solve 82–133 ms with CSV, DataFrames and CairoMakie loaded before, after or not at all. A new data type in TraitMakie: 77–97 ms and a first PNG of 89–161 ms.
- **Compiling per key, not per closure.** A new callback closure 12–24 ms with no loads or loads before; 171 ms with the loads after the first solve (one run, not diagnosed); a second loss closure 17–18 ms in every order; ForwardDiff's own tag 0.70–0.73 s.
- **Sessions.** TraitReport in a fresh process 0.76 s (without traits 0.72 s; Python 0.58–0.69 s, measured earlier and not rerun). The forks of CSV and DataFrames: an interactive session without imports in 2.85 s against upstream's 10.40 s.
- **The solver's run time.** 158 ns per step for Lorenz against OrdinaryDiffEq's 346 ns; 7.5–7.9 µs against 6.1 µs at n = 1,000.
- **AOT:** a trimmed TraitMakie binary of 4.07 MB (built under the previous prototype's policy; not rebuilt on the compiler).

**Not shown, or not yet diagnosed:**
- The ~990 ms upstream CSV + DataFrames pay after the loads under `all` is diagnosed: the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails) ([`performance.md`](performance.md)). Open: TDE's new callback after the loads (171 ms against 12 in one run). One residue is diagnosed (TraitReport's work 333–410 ms against 41 ms). StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code (§1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open (`open-issues.md` §1.19).
- A clean-case regression: TraitMakie's forwarding `@implement` 36 → 77 ms, probably the cost of compiling TraitWorld's machinery by facts.
- Reruns: Python's baseline; TraitReport form (t) under loads; the forks' session harness after the `String15` fixes; BaseBenchmarks and Base's tests under `all`.
- Strict mode under `all`; threads; Revise-style edits; composition beyond libraries of a few hundred lines; binaries of TraitDifferentialEquations with ForwardDiff, and of CSV and DataFrames; the volume of the "explosion" of compiled code on a real library.

## 9. The software: today, the target, the order of work

### 9.1 Today (2026-10-19)

- **Julia** (`julia-1.13/`): parts (A)–(D), the compiler staying plain, the two inliner changes, with the patch pieces 1, 3, 5, 9, 10, 17. Inventory: [`julia-changes.md`](julia-changes.md).
- **TraitWorld** (requires the patched build): the trait language, ownership, implementations as methods, entries (boundaries) and workers, keys and layout (held views for immutable values), `Callable`, `Like`, definition checking (the checks on a `NativeInterpreter` with their own cache owner), concrete mode with the fully-typed certificate, `verify_main`, strict mode (protecting `:facts` code), printing. Its slow paths are compiled by facts (`@machinery`). `Dynamic` operations are `Compiler.dynamic_call` sites.
- **Tests:** TraitWorld's 47 sets; acceptance 19/19; the demonstrators' suites (TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations); the forks' upstream suites (Tables, CSV, DataFrames) and their scripted session (digests equal to upstream); the examples (`experiments/examples/run_all.sh`).
- **Measured:** [`evidence.md`](evidence.md).

### 9.2 The target

```
Julia (patched, then upstream proposals)
  (A) facts mode in the native interpreter
  (B) method flag "compiled by facts" + owner sentinel; native code in images
  (C) owner-aware dynamic dispatch
  (D) Dynamic call-site split in the inliner
  pieces 1, 1', 14, 15 (strict), 3, 9, 10, 17; piece 5's upstream half
  --compile-by-facts=no|all|traits (the target spelling, not built; today JULIA_COMPILE_BY_FACTS=1 is all); --trim implies no

TraitWorld (package)
  @trait, @implement, @trait_module (sets the (B) flag), ownership, implementations as methods,
  entries and workers, keys and layout, Callable (two modes), Like, definition checking,
  concrete mode, verify_main, strict mode, printing
  Dynamic{X}: holds the user's object; the candidate list for (D)

Not in the target
  TraitWorld's facts.jl (the external interpreter), view caches, warm-ups, site caches, trampolines,
  stock-only paths, witness tables and key branches, sealed_call, ten of thirteen JULIA_TW_* switches,
  the {R} spelling and projection names, the system-image prototype, pieces 2 and 4,
  the three old worktrees at the repository root
```

Of the last group, the `{R}` spelling and `project(t) = …` remain in TraitWorld's precompile workload and many tests ([`../open-issues.md`](../open-issues.md) §2, "the design and the code disagree", item 7), and the three old worktrees are still at the repository root. What each of these was, and why it went: [`alternatives.md`](alternatives.md).

### 9.3 The order of work

The order in force is the speed plan, [`../plans/2026-10-19-principled-speed-plan.md`](../plans/2026-10-19-principled-speed-plan.md): principled ways to make everything fast, as close as possible to the proven designs of other languages. Its steps:
- (0) ground truth;
- (1) world-checked call-site caches, which fix G1.20;
- (3) cheaper entries;
- (4) compiling ahead from declared implementations;
- (5) the machinery's startup.

Guarded devirtualization (2) is postponed: traits recover the costs it targets, and a failed guard is a silent cliff. The items below are inside those steps, or run alongside them:
1. **Diagnose the remaining load costs:** TDE's callback row after the loads (the ~990 ms under `all` is diagnosed, 8); a full list of what is lost or compiled, naming the winning methods.
2. **The clean-case cost of `@machinery`:** measure what a clean `@implement` compiles by owner; a precompile workload for the machinery.
3. **Acceptance checks** for the latest compiler changes (the inliner changes, the compiler-plain edges, held views).
4. **AOT from declared targets (section 4.8):** an implementation compiles the declared workers for its key at precompile time, replacing hand-written workload extensions (the forks' `CSVDataFramesInlineStringsExt`).
5. **Upstream proposals** in the order of section 6.
6. **The forks resumed,** with `CSVColumn{T}` and kernels that use the declared operations.

The steps already done, in order, are in [`../record/design-history.md`](../record/design-history.md).
