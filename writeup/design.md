# Trait-bound Julia: the design and its decisions

The consolidated statement of the design, as of 2026-10-18 (session 29). Where the four notes in `notes/`, the explorations or the register disagree with this document, this document is current. The notes keep the detail; links point to it.

It consolidates the four notes, the register (`decisions.md`), the compiler plan (`plans/2026-10-17-policy-in-compiler-plan.md`) and the four reviews of 2026-10-18 (`reviews/2026-10-18-*.md`), with the user's decisions of session 29 applied.

## Contents

1. Terms
2. The problem
3. The argument in four steps
4. Traits: saying what code needs
5. The three rules
6. What Julia provides
7. The decisions in force
8. What the evidence shows, and what it does not
9. The implementation: today, the target, the order of work
10. What is not claimed
11. Where the rest lives

---

## 1. Terms

Each term is defined once, here.

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
- **Conformance.** The declaration `@implement X T` that type `T` joins trait `X`.
- **Implementing type.** The type whose own methods serve at least one operation: the conforming type, or the field it forwards to. There is none when the trait's defaults serve every operation.
- **Key.** What a bound can see: the implementing type, if any, and the declared fields' types.
- **Trait object.** What library code receives for a bounded argument: the user's object, seen through the offsets of what the bound can see.
- **Entry and worker.** A bounded function's entry translates each argument by its bound. Its worker is the body, compiled per tuple of keys.
- **Trait module.** A module whose code is written against traits (`@trait_module`). Its code is *trait code*. Everything else is *plain code*.

## 2. The problem

> Sections 2 and 3 follow the spine the user proposed and adopted in session 29: start from what is true today, then add one step at a time.

Julia compiles a method for the concrete types of its arguments and caches the result. Two things go wrong with that cache.

**Problem 1: compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used.
- Where inference ran at an abstract signature, the code depends on every method that matches there.
- Any package that adds a method for its own type can change that answer, and the code is discarded. No piracy is involved. `Base.show(io, ::MyType)` in MyPackage invalidates every caller compiled at `show(::IO, ::Any)`-shaped signatures.
- Measured: `using CairoMakie` discarded code at 769 signatures on Julia 1.12, none of them concrete. With DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s.
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
- Verified on 1.13.2 (`reviews/2026-10-18-framing-and-motivation.md` §0, reproduced with the in-tree facts mode in session 29): a stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7) invalidate code at concrete signatures; a losing pirate (S6) never does.
- Proofs: `explorations/wrapping-by-facts.md` (Lemma O, Lemma D, Theorems 1–3).

### 3.2 Step 2: outlaw pirates, and fully typed code is always valid and can be cached

**Strict mode** refuses a pirate that would win at a fact of compiled code, where it is defined: at the prompt, by `include`, or as a package image's methods activate (Julia piece 1). The error names the method and the code it would have changed. The method then does not exist for plain Julia either, so a call still computes what plain Julia computes ("identical or error").

With step 2 alone, in plain Julia and without traits, fully typed code satisfies the guarantee:

> **Compiled code is never invalidated unless code it depends on changes.**

"Code it depends on" is precise: the stakeholders of its facts. "Always valid" means valid except for the following, named with the guarantee wherever it is claimed:
- **A stakeholder's definition:** edits, Revise, upgrades. This is the stated exception.
- **A package extension (or Requires block) of a stakeholder** whose method applies at a fact without mentioning its trigger's types, activated by loading the unrelated trigger. Either refused by an extension rule or admitted as the stakeholder's own change: still open (`open-issues.md` §1.10).
- **A binding the code reads, redefined from another module** (`Core.eval(Other, …)`). The theory does not cover bindings yet, and no hook sees them (`open-issues.md` §1.10).
- **A pirate already in a package image** when the code was compiled. Image validation discards the facts it breaks; piece 15 turns that into an error.

The refusal is narrow, so extending and hooking into existing code keep working:
- **Conformances are the sanctioned extension point.** A conformance is a method of a registry declared with `@max_methods 1` and a fallback, so it applies at no existing fact and invalidates nothing. In TraitCSV, InlineStrings' `String15` conforms from an extension, and the reader compiled for `Float64` columns keeps its code. This is what package extensions become.
- **Hooks on your own types are never refused.** `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`, an operation of someone's trait for your type: the definer is a stakeholder of every signature they apply to.
- **What is refused** is exactly a method of a function you do not own, for types you do not own, that would change what compiled code computes. Measured on CSV, DataFrames and CairoMakie: 65,318 methods checked, 837 pirates by the letter, none refused (`experiments/facts/g2strict`).

### 3.3 Step 3: the facts rule extends the guarantee to all code, at a cost where code is not fully typed

Most code is not fully typed. Where inference ran at an abstract signature, the edge can be broken by any owner adding a method for its own type, and there is nobody to refuse (problem 1).

**The facts rule (rule R):** compiled code depends on the method table only through facts. A call that is not at a fact signature is a *run-time site*: it dispatches at run time, as plain Julia's dynamic dispatch does, and records nothing. Nothing is skipped: a fact is invalidated exactly when a definition changes dispatch at its signature. With rule R, every compiled CodeInstance is invalidated only as step 1 says, and step 2 makes the guarantee hold for all code.
- Verified: four non-pirate definitions that invalidate on 1.13.2 (an owned method at an abstract call, S1; a new subtype under union splitting, S2; a `return_type`-dependent `map`, S3; a new type at a kind, S8) invalidate nothing in facts mode. The in-tree mode reproduced all eight cases in session 29.

**The cost sits exactly where code is not fully typed.**
- For fully typed code, facts inference *is* plain inference: the same calls inferred, the same edges, the same code.
- Elsewhere, the facts rule removes Julia's heuristics for type-unstable code: speculation over up to `max_methods` matching methods, a result type taken from the one method that matches today, compile-time evaluation over abstract calls. The result of such a call is `Any`, and `Any` spreads into the code after it.
- Measured on plain code (`all`, a test bed): BaseBenchmarks geometric mean 1.016, 1.064 without `scalar`; the concrete groups within 1.00–1.09; the tails from 1.3× (`io`) to about 80× (containers of `Any`), on containers of `Any`, abstract element types and small-union broadcasts. One run, `--pkgimages=no`, Base compiled plainly in the system image.

### 3.4 Step 4: traits say what code needs, which makes the facts rule cheap, and can enforce concreteness

Traits make code fully typed where plain Julia would lose its types, by three mechanisms:
1. **Concrete keys.** A function bounded by a trait is compiled per key: the implementing type and the declared fields' types. Its reads and calls are at concrete signatures. Type-stable code over concrete keys is fully typed, so it pays nothing for the facts rule. A trait may **enforce** concreteness (one declaration with a level: silent, warn, error; section 4.3), so that type-stable code bounded by it is always fully typed.
2. **Declared result types at abstract positions.** Where a value is heterogeneous on purpose, the heterogeneity is declared: `Dynamic{X}` for values, `Callable{A, S}` for functions. Their operations have declared result types, checked. They give back exactly what the facts rule took away, a result type at an abstract call, from a declaration rather than from the methods that exist today.
3. **Declared conformances.** The types a `Dynamic{X}` value can hold are the declared conformances, so an operation on it splits at the call site (`isa` branches, direct calls that inline, a dynamic fallback), as union splitting does, without an edge to the list (part D, section 6). This replaces the speculation the facts rule removes.

Type-unstable code was never claimed to be fast in Julia. Under the facts rule it stays correct and gets slower in the tails. The design's answer is the user's principle: a slowdown is tolerated when redesigning the code with traits recovers it (raytrace and `parse_json` so far, section 8).

### 3.5 The default: following pirates (rule P), and what it gives up

Step 2 is a switch. The default session leaves it off: a winning pirate is followed, as plain Julia follows it, and the code with that fact recompiles once.

- **The compiled code is the same either way.** Strict mode acts only at a method's definition and at image activation (verified, `TraitWorld/src/strict.jl`).
- **Two tiers of the guarantee:**
  - strict: invalidated only by a stakeholder's change. A static property of every environment that loads without a `PirateError`, with the exceptions of 3.2;
  - default: invalidated only by a stakeholder's change or a pirate that wins at one of its facts. Whether one does is an empirical property of the environment; so far, always "none" (0 CodeInstances lost over twelve loads in any order, `experiments/facts/g2all`).
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
- **Goal 2 makes goal 1 cheap.** Concreteness makes the guarantee free: fully typed code pays nothing for the facts rule. Declared results and declared conformances recover what the facts rule takes from code that is heterogeneous on purpose.
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

Section 3.4 named the three mechanisms by which traits make the facts rule cheap. This section gives the detail: code says what it needs, is compiled for exactly that, checked once, and typed without speculating over today's methods.

### 4.1 Traits and conformance

- **A trait is an abstract type with behaviour.** It declares operations (generic functions with argument and result types), fields (with types; writable unless `@const`), and associated types as parameters (`@trait Integrator{U, P}`). Defaults are written in terms of the other operations and fields.
- **Conformance is declared,** `@implement ColTable MyType`, also after the type was defined. It is never derived from the methods that exist: Base's throwing fallbacks make structural matching unsound.
- **Operations** come from the type itself or are forwarded to one field (`by data`). **Declared fields** are stored fields, by name or mapped (`name => label`). The declaration is checked: every operation and field exists, with the declared types.
- **Associated types** are first-order: one value per conformance, defined by a field's type (`data::Vector{T}` against `Vector{Float64}` gives `T = Float64`) or by an equation of `Self`, bounded by traits or types. No input parameters, no equations between type functions: these made Rust's and Swift's checking hard (`notes/2-design-choices.md` §10).
- **Who may implement:** a stakeholder, the trait's owner or the type's owner (rule 2 below). Implementations are methods.

### 4.2 Compiled for what the bound can see

- A function bounded by a trait reaches its argument only through the trait's operations and fields.
- It is compiled per **key**: the implementing type, if any, and the declared fields' types. Not per the argument's own type.
- Types that differ only in what the trait cannot see share compiled code. Every table type forwarding `ColTable` to a `Vector{Vector{Float64}}` field runs the code the library compiled for that type. A solver step bounded by `Integrator` compiles nothing for a new callback, which the trait does not declare.
- **This is not "once for any type".** A type that supplies its own behaviour (implements an operation, overrides a default) is the implementing type and gets its own copy, compiled once, in its own image. Sharing comes from forwarding, from defaults over fields, from `Dynamic{X}`, and from `Callable` in its dynamic mode. Code shared across every conforming type through a witness, Swift's model, was considered and not chosen (`notes/2-design-choices.md` §7).
- **The reference layout.** A trait object is the user's object, read at byte offsets, with Julia's alias metadata. Nothing is copied or held; every read sees the current value; loops run at plain Julia's speed. Typed trait calls: 33 ns against 30 ns plain.
- **Inside a trait module,** a trait object is what its bound can see and nothing else. Internal functions take trait objects without bounds; definition checking follows them through.

### 4.3 Concreteness, opt-in per trait

- By default a key may be abstract, silently. An abstract part of a key behaves like a dynamic value: one worker, dispatch where it is read, opened at the next bound it is passed to.
- A trait (or a module) that asks for more says so in **one declaration with a level**: silent (the default), warn, or error. Error refuses a conformance whose key is not concrete, and a family member at an abstract parameter at its entry.
- Concrete means a concrete type with concrete parameters all the way down. Fields the trait does not declare are not looked at.
- The prototype spells the levels `@warn_on_abstract` and `@concrete_only` today; the single declaration is adopted and not yet built.

### 4.4 Overrides belong to the conformance

- Which operations a conformance serves by defaults is fixed when it is declared. Compiled code and kept values depend on it, as they depend on a struct's definition.
- A later method of an operation that a default serves for that type is refused, naming the fix. An image that brings such an override for an active conformance is refused at load.
- **A family member's conformance is fixed at its first use, not at the family's declaration.** This is forced by ownership: the owner of a member's parameter type (`MyT` in `S{MyT}`) is a stakeholder of `op(::S{MyT})` and may legitimately define it after the family was declared upstream. No worker or `Dynamic` exists for the member before its first use, so fixing it then is sound.
- **Changing a conformance interactively** needs a restart until redeclaration is built. Julia 1.13 redefines structs (verified: old values keep the old type, `@world(A, …)`, and old worlds answer as before); a conformance redeclaration can use the same mechanism.

### 4.5 `Dynamic{X}`: a value of abstract type `X`

- A value that must outlive a call, an element of a collection of mixed keys, or a field whose key changes is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations and fields.
- **It holds the user's object.** The view for (X, the object's type) is a constant per pair.
- **An operation on it is a call-site split:** `isa` branches over the declared conformances, direct calls that inline, then a dynamic fallback, the result asserted to the declared type. The split belongs in Julia's inliner, as union splitting does (part D, section 6). It dispatches in the caller's world.
- **Opened at a bound:** passed to a function bounded by `X`, it selects the worker for its key once, and the worker runs compiled.
- **A trait's name in a field or container means its `Dynamic`** (`plots::Vector{Plot}`), inside trait modules until traits are in the type system. The explicit spelling always works.
- `Dynamic{X}` is the package's spelling of "a value of abstract type `X`". Its form is transitional, until membership is subtyping (Julia piece 7); its meaning is permanent.
- Hidden type parameters for fields declared by bounds were rejected (the user: "antithetical to Julia").
- Today's package form (a boxed trait object, witness tables, key branches) is superseded. Witness tables are off by default since session 29, because a witness pointer runs in the latest world, not the caller's (verified wrong result, `reviews/2026-10-18-design-and-fixes.md` finding 2).

### 4.6 Functions as arguments: `Callable`, two modes

- Julia has no type for "a function from `Float64` to `Float64`". A function handed down from plain code enters only at a declared signature: `Callable{A, S, M}`, arguments `A`, result `S`, mode `M`. Its one operation is checked at every call.
- **Two modes, both kept** (the user, session 29): "We need compiled call to have an ODE RHS that has the right type signature. Julia's type system can't express that otherwise."
  - `DynamicCall`, the default: a pointer to the function's code at `A`; the worker is compiled once per signature, in the library's image; an indirect call per use (about 4 ns).
  - `CompiledCall`: the worker is compiled per function type, with the function inferred into it, and the signature still declared and checked. This is what an ODE right-hand side needs: plain Julia's speed with a typed contract. An unbounded argument would specialize but check no signature.
  - The library sets the default; the caller overrides per value (`compiled_call(f)`, `dynamic_call(f)`). The mode is a choice of speed, never of correctness.
- `DynamicFn{A, S}`, made by `dynamic_fn`, is a `Callable` in `DynamicCall` mode as a value of fixed type, for functions stored in a library's types.
- Functions from trait code (Base's `abs2`, a trait module's own functions and closures) are called directly.
- Automatic differentiation tags are labelled by a `Callable`'s primal signature (`Tag{Sig{A, S}, V}`), so loss closures of one signature share the solver's code (implemented in TraitDifferentialEquations).

### 4.7 The rest of the trait language

- **Results like the input:** constructor operations returning `Self`, `Like{t}`, `withfields`, a result rebuilt as the user's type at the entry. Only `Self` constructors are exercised so far (TraitCSV).
- **Definition checking:** library code is checked once at archetypes, where it is defined, for every type that will ever conform. A mistake is reported at its line before any user type exists. At the prompt it warns; the call raises.
- **Dispatch:** types first, then traits. A trait bound ranks above `Any` and below every type. This is what lets a library adopt traits one function at a time.
- **Keeping is detected, not declared:** a function whose code may keep a trait object receives the whole user's object; others receive what their bounds see. An optimization with a safe fallback.
- **Printing by bound and key:** `ColTable at Vector{Vector{Float64}}` (Julia piece 17).
- **Named implementations** (`via(M, x)`, anyone may write one) are deferred until traits are in the type system. The preferred form is a value-level wrapper that conforms (`Via{Fast}(x)`, a newtype), since the simplest `Dynamic` and membership as subtyping have no place for a witness inside the value.

### 4.8 AOT follows from declared targets

- Dispatch between trait code, and over the types a program meets at run time, goes through declared conformances. A `Callable` argument adds one target at its signature; a `Dynamic` value adds the conformances whose types reach where it is made. `verify_main` lists them.
- Plain code reached from trait code (CSV, Cairo) keeps plain Julia's AOT properties; `verify_main` reports its open sites as holes.
- A `--trim` build compiles the plain call in the closed world, so the facts mode is off in a build. Nothing loads in a binary, so there is no cache to protect, and "identical or error" holds by definition.
- So AOT is a consequence of goal 2 (declared targets), not of the facts.

## 5. The three rules

Three rules deliver the guarantee and the two goals. The former rule 4 ("what a call sees, where compiled code lives") is Julia's own behaviour and is no longer a rule.

1. **Facts.** Compiled trait code depends on the method table only through facts.
   - A *fact signature* is: a tuple of concrete types; its union splits; the splits of unions of concrete element types inside tuple arguments (up to four); a closure's call at kinds.
   - Any other call is a run-time site: it dispatches at run time and records nothing. Under part C, a run-time site in facts-compiled code runs facts-compiled code.
   - Compile-time evaluation only over facts, or where Julia's own asserted effects fold (Base and Core methods asserted foldable). That exception inherits Base's assertion: the same exposure plain Julia has.
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
- **Identical or error (G1).** A call in trait code computes what plain Julia computes in the current world, or raises. It rests on one assumption about values that inference decides (A3: `return_type` of empty collections, `Union{}` results). The package prototype adds two implementation assumptions (A4: no method defined concurrently with compiling trait code; A5: the generator's behaviour), which part B removes.
- **Stable caches (G2),** in the two tiers of 3.5.

## 6. What Julia provides

The design needs Julia's compiler and runtime. Stock-Julia support is dropped (the user, session 29). TraitWorld requires the patched build.

**The compiler parts, as built in session 29** (julia-1.13, commits 880ae49dad, c3415abde6, 25c630dd34, feaad9e45c, f6838f96fc; acceptance 17/17, TraitWorld 47 test sets):

| Part | What it is, as built |
|---|---|
| **(A)** facts as a mode of Julia's own inference | `NativeInterpreter` has a `facts` field. A call is inferred, with its edges, only at a fact signature: a dispatch tuple, its union splits, unions of concrete elements inside tuple arguments, a closure's call at kinds, and a concrete `Vararg` tail (the user: "Anything that satisfies 'can only be changed by stakeholders or pirates' is fine"). `return_type` folds only an answer that cannot be wider than plain inference's, else plain inference's answer when it rests on facts, else at run time, where plain inference answers it in its own cache owner. Asserted effects are trusted only in Base and Core methods (method and statement level). The compiler's own code stays plain. |
| **(B)** code compiled by facts beside plain code | A module option, `Base.Experimental.@compiler_options facts=true` (declared by `@trait_module`, inherited by submodules), makes its methods *facts methods*: compiled by facts under the owner `:facts`, whoever calls them; everything a facts frame calls is compiled by facts under that owner. A method can be a **boundary** (`Expr(:meta, :facts, 0)`, `Method.facts`): compiled in its caller's mode, as a trait entry is (rule 2). Plain inference of a facts method is a separate facts inference, and the call names that CodeInstance; reflection of a facts method is facts inference. Package images keep `:facts` code (through the compile queue). |
| **(C)** dispatch from facts code | Code of owner `:facts` calls `jl_apply_generic_facts` and `jl_invoke_facts` at run-time sites: the same method lookup, then the `:facts` CodeInstance, compiled on a miss. |
| **(D)** the `Dynamic` call-site split | `Compiler.dynamic_call(K, f, x, args...)`: inferred as `f` at the union of `K`'s registered candidates (≤ 4, each split a fact), plus a fallback; the inliner union-splits it with the dynamic call as the last branch (never "fully covered"). Candidates are registered without an edge (conformances at declaration and package load, values when made): a later conformance reaches the fallback and invalidates nothing. |

**The switch:** `JULIA_COMPILE_BY_FACTS=1`, or a system image built with it (`experiments/factscompiler/scripts/build_facts_sysimage.sh`), compiles *all* code by facts (owner `nothing`): the test bed (the user, session 29). Without it, only facts methods (trait modules) are compiled by facts: the product setting. `--trim` turns the facts mode off (a closed world compiles plain code).

**Julia pieces** (numbering of `explorations/julia-support.md`):
- **Keep:** 1 (method-definition and image-activation hooks, which strict mode needs), 3 (field-offset intrinsics), 17 (type printers), 9 (owner-aware bare MethodInstance edges) and 10 (the inliner uses the CodeInstance it is given), in the form a second owner needs; 5's upstream half (machine code for upstream CodeInstances in images: also plain Julia's gain, to be measured alone).
- **Add, for the strict tier:** 1′ (a deletion hook), 14 (a read-only "what would this definition invalidate" query, transitive), 15 (image validation reports the winning method).
- **Revert:** 2 (invalidation policy hook, the old filter) and 4 (post-inference hook): still in the tree, inert (opt-in), to revert.
- **Moot:** 11, 12, 13 (artefacts of the external interpreter).
- **Later:** 7 (traits in the type system: membership as subtyping), last.

**Upstream proposals, in order:** pieces 10, 9 and 17 as fixes and a small feature; (A) as "a facts mode for the native compiler", with the benchmark table; pieces 1, 1′, 14, 15 with strict mode; (B) and (C) as per-method inference modes after they carry the demonstrators; traits in the type system last.

## 7. The decisions in force

Only the current decisions. The full register with history is `decisions.md`; "s" is the session.

| Decision | Origin | Detail |
|---|---|---|
| A trait is an abstract type with behaviour; abstract types stay, traits are a kind of them | s22 | 4.1; `notes/2-design-choices.md` §1 |
| Conformance is declared, never derived | early | 4.1 |
| Keys: code is compiled for what the bound can see (implementing type, declared fields' types) | s22 | 4.2; `notes/4-details.md` "Terms" |
| Implementation separate from conformance; forwarding `by f`; no computed projections; declared fields are stored fields; forwarding does not chain | s22 | `notes/4-details.md` "How a type conforms" |
| The reference layout: a trait object reads the user's object at offsets | s22, s23 | 4.2 |
| Associated types in first-order form; fields define parameters by matching | s22 | 4.1; `explorations/associated-types.md` |
| Concreteness opt-in per trait, one declaration with a level (silent, warn, error) | s27 (the user: "Per trait"); one declaration s29 | 4.3 |
| Overrides belong to the conformance; family members fixed at first use (forced by rule 2); refused at load; restart until redeclaration is built | s27 decision 4; s29 | 4.4 |
| Definition checking at archetypes, at the module's end; a warning at the prompt | s22, s27 | 4.7 |
| `Dynamic{X}`: a value of abstract type `X`, holding the user's object; operations by a call-site split in the compiler | s22; s29 (the user: "move to the compiler directly") | 4.5 |
| Witness tables off by default until `Dynamic` is in the compiler | s29 (the user: "Witness table: Yes") | 4.5 |
| A trait's name in a field or container means its `Dynamic` (inside trait modules) | s22, s27 | 4.5 |
| No hidden type parameters | s22 (the user) | 4.5 |
| `Callable{A, S, M}` with two modes, `DynamicCall` the default, the caller overrides | rev 988; kept s29 (the user: "We need compiled call to have an ODE RHS that has the right type signature") | 4.6 |
| AD tags labelled by the primal signature | s23, implemented s27 | 4.6 |
| Results like the input (`Self`, `Like{t}`, `withfields`) | s22 | 4.7 |
| Keeping detected, not declared | s23 (the user: "If feasible, detection is the way") | 4.7 |
| Types first, then traits, in dispatch | early | 4.7 |
| Printing by bound and key | s22 | 4.7 |
| Named implementations deferred to piece 7; a value-level wrapper preferred | s29 | 4.7 |
| AOT builds compile the plain call; `--trim` turns facts off | s25; s29 | 4.8 |
| **The guarantee, strict mode first;** rule P the default relaxation | s29 (the user: "Strict mode first for framing is yes") | 3.2, 3.5 |
| **The framing in four steps:** fully typed code is already valid but for stakeholders and pirates; strict mode outlaws pirates; the facts rule extends the guarantee to all code at a cost where code is not fully typed; traits make it cheap and can enforce concreteness | adopted (s29, the user's proposal: "1-3 is a yes") | 3 |
| **"Fully typed"** is the name of the property: every call at a fact signature, transitively, kinds excluded | adopted (s29, the user) | 3 |
| **A fully-typed certificate:** concrete mode reports, per worker, whether it has run-time sites; a worker without them is fully typed and pays nothing for facts; `@concrete_only` traits (the `error` level) refuse workers that are not | adopted (s29, the user), to build | 3.4, 4.3 |
| Strict mode: one decision with two tiers; the intended design's items are the work list | s25, s29 | 3.5; `open-issues.md` §1.10 |
| Under (B), strict mode protects facts-owned code | s29 (implied by `all` a test bed) | 3; `TraitWorld/src/strict.jl` |
| The symmetric check as a build lint | s25 | 3.5 |
| Three rules: facts (with the definition of a fact signature), ownership, the boundary | s29 | 5 |
| Facts at tuple splits; folds where Base's asserted effects fold; run-time sites run facts-compiled code | s28, written into rule 1 s29 | 5 |
| Stakeholders by the method's own signature; supertype owners count; the extension exception named | s27 decision 2 | 1; 3.2 |
| Delegates as data, transitional | s25; marked s29 | 5 |
| No sealing, of abstract types or functions: a closed contract is a trait | s28 (the user) | — |
| The facts policy in Julia's compiler: (A), (B), (C), (D) | s28; (D) s29 | 6 |
| `--compile-by-facts=all` is a test bed | s29 (the user) | 6 |
| Stock-Julia support dropped | s29 (the user) | 6 |
| Slowdowns are tolerated if redesigning the code with traits recovers them. This governs trait code and the plain code it reaches; the plan's numeric threshold for `all` (P-a) is moot, since (B) is needed regardless | s29 (the user: "tolerate slow downs if they can be recovered by redesigning code through traits") | 8 |
| The forks (demonstrator 4) paused | s29 (the user) | 9 |
| The runtime as methods: a conformance is a method; entries are ordinary methods; workers per key | s23 | `explorations/keys-plan.md` §6 |
| Workspace: the design repository with separate repositories inside; local only | early | `README.md` |

## 8. What the evidence shows, and what it does not

All numbers are from the patched Julia 1.13.2 build, on one machine, unless stated. They predate parts B, C and D.

**The four steps of section 3:**
- *Step 1, verified* in small cases: a stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7) invalidate code at concrete signatures; a losing pirate (S6) never does (`reviews/2026-10-18-framing-and-motivation.md` §0, `inval.jl`; reproduced with the in-tree facts mode in session 29). Proved in `explorations/wrapping-by-facts.md`.
- *Step 2, verified* as a prototype: strict mode refuses winning pirates and nothing else in a real stack (below). Its intended design (pieces 1′, 14, 15, the extension rule, bindings) is not built.
- *Step 3, verified:* the four cases that are not fully typed (S1–S3, S8) invalidate on 1.13.2 and not in facts mode; acceptance and `g2all` below. Its cost is measured on plain code (BaseBenchmarks, below).
- *Step 3's claim that facts are free for fully typed code:* follows from the definition (the same calls inferred at the same signatures), and fits the concrete groups of BaseBenchmarks (1.00–1.09). **Not measured** directly: a benchmark of fully typed code, facts mode against plain, comparing the compiled code itself.
- *Step 4:* the recovery cases below (raytrace, `parse_json`) are the evidence so far. **Decided, not built yet:** a certificate from concrete mode that a worker has no run-time sites, hence is fully typed and pays nothing for facts (s29).

**Shown:**
- **Facts at concrete signatures keep code valid.** Acceptance 16/16, 48 adversarial cases; 0 facts-compiled CodeInstances lost over twelve loads in any order (`experiments/facts`).
- **Strict mode refuses nothing in a real stack.** 837 pirates by the letter among 65,318 methods, none winning; 0.54 s extra on a 4.1 s load.
- **Trait calls cost little.** Typed calls 33 ns against 30 ns plain; loops through the reference layout at plain speed.
- **Compiling per key, not per closure.** TraitDifferentialEquations: a new callback closure 13–15 ms (25–31 ms with loads) and a second loss closure 17–21 ms, against SciML's 0.84–0.96 s and 2.48 s; the first solve 6.4–8.0 ms in every load order. Caveat: PlainODE (FunctionWrappers, untyped callbacks, the same signature-labelled tag) matches the second loss in a fresh session and is faster for a first callback (5.1 ms); the trait form's advantage is under loads (first callback 29 against 144 ms) and its checks.
- **Trait code survives loads where its plain twin does not.** TraitReport under nine loaded packages: the trait form 66–80 ms with no compiled code lost; the same libraries without traits 102–147 ms, 17 of 49 methods lost. TraitMakie's first PNG 18–22 ms in every load order, PlainPlots about 100 ms after loads. Caveat: the protection comes from the facts mode, which is trait-independent (661 facts-compiled CodeInstances of plain CSV code survived `using DataFrames`).
- **Fresh sessions at Python's speed for small libraries.** TraitReport 0.52–0.56 s against Python's 0.58–0.69 s. Caveat: the plain baseline with the same workloads takes 0.50–0.52 s.
- **`Vector{Dynamic{Column}}` keeps column code when the plain form loses it:** PlainTables loses 17 of 49 methods to loads, the trait form none.
- **The facts mode's cost on plain code** (`all`, a test bed): BaseBenchmarks geometric mean 1.016, 1.064 without `scalar`; `io` 1.32; tails on containers of `Any`, abstract element types, small-union broadcasts. One run, `--pkgimages=no`, with Base compiled plainly in the system image.
- **Traits recover the tails tried so far.** Raytrace: an open set of primitives through `Dynamic` costs the same with 2 or 4 types (470–484 ms), where plain Julia's fast path holds only for 2 (240 ms; 693 ms with 4); still 2× plain's `isa` branches, which part D addresses. `parse_json` with typed captures: 1.17× the fixed plain code.
- **AOT:** a trimmed TraitMakie binary of 4.07 MB under the facts policy (session 25), `--trim=unsafe-warn`.

**Not shown:**
- **The control that separates the facts mode from traits:** the plain baselines (PlainODE, PlainPlots, PlainTables) and upstream DataFrames under `all`, with the same workloads. Every "survives loads" row is a property of the facts mode until this runs. It is step 2 of the order of work.
- **Interactive work at the REPL with new keys,** without the system-image workaround: it needs part B.
- **Base's tests in facts mode:** not run before session 29 (a run on the facts system image started in session 29). The go/no-go benchmark ran in the Compiler copy, whose run-time `return_type` changed values.
- **The volume of the "explosion" of compiled code.** It is structural (32 specializations against 1 in a small experiment), but unmeasured on a real library.
- **Binaries** for TraitDifferentialEquations with ForwardDiff, and for CSV and DataFrames; `--trim=safe`.
- **Strict mode under `all`;** threads; Revise-style edits; composition beyond libraries of a few hundred lines.
- **The DataFrames port** (10.9 s → 1.19 s for the session, pandas 0.32 s) mostly shows the facts policy and workloads: its kernels unwrap each column (`vector(c)`) instead of using the declared operations, and CSV's trait is `CSVSource`, not the planned `CSVColumn{T}`.

## 9. The implementation: today, the target, the order of work

### 9.1 Today (end of session 29)

- **Julia** (`julia-1.13/`): parts (A)–(D) built (section 6), with the patch pieces 1, 3, 5, 9, 10, 17; pieces 2 and 4 inert, to revert.
- **TraitWorld** (7,3xx lines, requires the patched build): the trait language, ownership, conformances as methods, entries (boundaries) and workers, keys and layout, `Callable`, `Like`, definition checking, concrete mode with the **fully-typed certificate** (`fully_typed(f, argtypes)`; `@error_on_abstract` refuses code with run-time sites), `verify_main` (scanning by owner), strict mode (protecting `:facts` code), printing. Its own policy (`FactsInterp`, site caches, trampolines, view caches, witness tables, key branches, warm-ups) is deleted. `Dynamic` operations are `Compiler.dynamic_call` sites.
- **Tests:** TraitWorld 47 sets; `experiments/facts/acceptance_compiler.jl` 17/17; the demonstrators' suites pass (TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations; TraitReport's and TraitMakie's REPL sessions; TDE's session equal to PlainODE's; the forks' CSV suite; DataFrames after a port fix: see the session note); the examples agent's cases (`experiments/examples/run_all.sh`).
- **Not measured yet:** everything (the user: measurements wait until `Dynamic` is in the compiler; it is now). The control experiment is prepared (`experiments/factscompiler/control/`).

### 9.2 The target

```
Julia (patched, then upstream proposals)
  (A) facts mode in the native interpreter
  (B) method flag "compiled by facts" + owner sentinel; native code in images
  (C) owner-aware dynamic dispatch
  (D) Dynamic call-site split in the inliner
  pieces 1, 1', 14, 15 (strict), 3, 9, 10, 17; piece 5's upstream half
  --compile-by-facts=no|all|traits; --trim implies no

TraitWorld (package)
  @trait, @implement, @trait_module (sets the (B) flag), ownership, conformances as methods,
  entries and workers, keys and layout, Callable (two modes), Like, definition checking,
  concrete mode, verify_main, strict mode, printing
  Dynamic{X}: holds the user's object; the candidate list for (D)

Deleted
  TraitWorld's facts.jl (the external interpreter), view caches, warm-ups, site caches, trampolines,
  stock-only paths, witness tables and key branches, sealed_call, ten of thirteen JULIA_TW_* switches,
  the {R} spelling and projection names, the system-image prototype, pieces 2 and 4,
  the three old worktrees at the repository root
```

### 9.3 The order of work (approved by the user, session 29)

1. **(A) in-tree, one source of truth for the fact rules.** Finish `julia-1.13/Compiler/src/facts.jl`, the option in `jl_options`, the bit in the package-image cache flags; build; retire the two other copies; run Base's tests in facts mode against the mode off and list every difference.
2. **The decisive control.** The plain baselines and upstream DataFrames under `all`, over the existing load matrices: lost CodeInstances and first-call times, against the trait forms. It decides which claims the demonstrators may keep.
3. **(B) and (C) in Julia.** Then delete TraitWorld's imitation and the stock-only paths; re-run the acceptance suite, `g2all`, TraitWorld's tests.
4. **`Dynamic` in the compiler.** The package form holds the user's object; then (D) in the inliner; delete witness tables, key branches and `sealed_call`; re-measure the raytrace.
5. **Re-point the demonstrators:** each README's claims at what traits add (compile per key, definition-time errors, readable types, declared conformances instead of extensions on internals, `Dynamic` against `isa` branches, AOT target lists); the facts mode's protection stated once, as the compiler's. Rewrite the notes for the strict-first framing.
6. **Housekeeping:** revert pieces 2 and 4; remove dead switches, the `{R}` spelling, the projection names, the old worktrees.
7. **Resume the forks** later, with `CSVColumn{T}`, kernels that use the declared operations, the upstream-under-`all` control, and the upstream test suites at each milestone.
8. **Upstream proposals** in the order of section 6.

## 10. What is not claimed

- No change to results beyond values decided by inference (A3). In the Compiler copy the difference was wider under `all`; the in-tree mode answers `return_type` at run time by plain inference.
- "Never invalidated" is the strict tier. The prototype lacks pieces 1′, 14, 15, the extension rule and a rule for bindings.
- No "compiled once for any type": a type that supplies behaviour gets its own copy, once, in its own image.
- No claim that traits, rather than the facts mode, protect code from loads until the control of section 8 has run.
- No numbers for stock Julia: the design needs the patched build.
- No REPL interactivity for new keys before part B; no threads; no Revise.
- Imports are not at pandas' speed (Julia's startup and package loading).

## 11. Where the rest lives

- **Detail:** `notes/4-details.md` (the mechanisms), `notes/2-design-choices.md` (against C++, Rust, Swift, Mojo), `notes/3-wrapping.md` (plain code, pirates), `notes/1-overview.md`. They predate this framing; this document wins where they disagree.
- **Proofs:** `explorations/wrapping-by-facts.md`. **Strict mode:** `explorations/strict-mode.md`. **AOT:** `explorations/aot-under-facts.md`. **Julia pieces:** `explorations/julia-support.md`.
- **The register with history:** `decisions.md`. **Open issues:** `open-issues.md`, §1 first.
- **The reviews behind this document:** `reviews/2026-10-18-design-and-fixes.md`, `reviews/2026-10-18-framing-and-motivation.md` (§5), `reviews/2026-10-18-implementation-shape.md`, `reviews/2026-10-18-decisions-revisited.md`.
- **The plan for the compiler:** `plans/2026-10-17-policy-in-compiler-plan.md`; measurements in `experiments/factscompiler/README.md`.
- **Lessons from the port:** `explorations/dataframes-port-lessons.md`.
