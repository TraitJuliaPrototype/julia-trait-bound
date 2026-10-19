# The argument in detail

A chapter of the [rationale](../design.md): the problem in cases, and the argument in four steps with its exceptions. It explains why the design has its shape; the precise rules are in the [references](../reference/README.md), above all [the facts mode](../reference/facts.md), which wins where this chapter disagrees.

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

