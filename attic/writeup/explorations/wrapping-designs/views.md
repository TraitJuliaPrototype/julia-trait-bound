# Wrapping by views: trait-world code dispatches in its own packages' method table

**Idea.** There are no wrapper declarations. Trait-world code calls Base, Cairo, ForwardDiff, and user functions directly. Everything it runs (including the Base code it calls) is compiled and dispatched in a **view** of the method table. The view contains the methods of the packages the calling code depends on, plus the methods of the packages that own the argument types. Each package's methods are a snapshot: what the package defined when it was loaded. A method from outside the view can never enter compiled trait-world code. In the default strict mode it can only stop that code, with an error at the one dispatch where plain Julia would have called it. Pirates no longer cost invalidation or refusal. Rare cases cost an error.

## 1. Rules and hooks

Notation:
- `owners(S)` is the set of modules that define the type names occurring anywhere in a concrete call signature `S`. This includes the function's type, type parameters and closure types.
- `closure*(X)` is the least set that contains `X` and the **platform**, is closed under package dependencies, and contains every package extension whose parent and triggers are all in it.
- The platform is Core, Base and Julia's own stdlibs. It is not "whatever is in the sysimage". An application may add packages to the platform (see §4).
- Non-package code (Main, REPL, `include`d scripts) has `closure*` equal to all loaded modules, because session code sees the session.
- `module(m)` is the package whose loading or evaluation inserted method `m`. It is the image of origin, Main, or the package Revise edits. It is not `Method.module`, which `@eval Base …` can fake.

**R1 (views).** A dispatch made by code of module `c` at concrete signature `S` sees exactly the methods `m` with `module(m) ∈ V(c,S) := closure*({c} ∪ owners(S))`.
- An overwrite counts only in views that see the overwriter. Otherwise the overwritten method stays visible: this is the snapshot.
- Two visible definitions of the same signature from packages where neither depends on the other are an ambiguity.
- R1 applies to trait-world methods and to every callee they reach: Base, Cairo, ForwardDiff, user functions. Each callee uses its own module as `c`.
- The result is one canonical trait-world specialization per MethodInstance, with no view tokens in cache keys.

**R2 (concrete edges only).** Compiled trait-world code records dispatch decisions only at concrete signatures. At a non-concrete call site it compiles a view dispatch (H3). Inference assumes only the declared result type (a trait operation's declared type, asserted) or `Any`, and never a type deduced from "the methods that currently exist".

**R3 (hidden methods stop, never enter).** Suppose a method in the session is hidden from a trait-world dispatch, and plain Julia would select it there or be ambiguous because of it. Then that dispatch raises `HiddenMethodError(pirate, module, S)`. Hidden methods never cause recompilation into code that uses them.
- **Strict** is the default.
- An application may opt into **lenient** mode, where hidden methods are ignored. This trades G1 for G1′ (§2).

Hooks (all assumed available, per fact 1):
- **H0 (view compiler).**
  - An AbstractInterpreter whose method-table view applies R1 and R2, with its own CodeInstance owner, which gives a second code cache.
  - Methods of trait-world modules always run from this cache, even when plain code calls them (an entry trampoline).
  - `return_type`, `applicable`, `hasmethod` and `which` called from trait-world code are answered in the view under R3.
  - The view machinery reads the method table at run time with no inference edges (fact 8).
- **H1 (insertion hook).** It never refuses a method. It records `module(m)`. It keeps overwritten methods available to views that do not see the overwriter. It adds *pirate-shaped* methods to a per-function **hidden-capable index**. A method is pirate-shaped when its module owns neither the function nor a type occurring outside a `Union` in its signature.
- **H2 (invalidation predicate).** A new method `m′` invalidates trait-world CodeInstance `X` iff some edge `(c,S)` of `X` has `S <: sig(m′)`, `m′` visible at `(c,S)`, and `m′` is selected or ambiguous there.
  - If `m′` is hidden there and plain Julia would select it, H2 instead marks the site, and `X` is recompiled with a `HiddenMethodError` trap at that site (strict mode).
  - Image validation of `X` checks two things: the packages of `P(X)` (below) have the recorded content hashes, and no indexed hidden-capable method wins at an edge of `X`. No other edge verification against the full table is done.
- **H3 (checked dynamic call).** `disp_V(c,S)` plus the R3 check, cached per (closure id of `c`, `S`). The cache is flushed only for entries whose `S` a newly inserted method applies to.

Escape hatch (not a rule): `@plain f(args)::T` calls in the latest world with plain-Julia semantics and asserts the result (fact 5). It is never needed for correctness. It is only for code that deliberately wants the session's meaning.

## 2. Guarantees, assumptions, proof sketch

**G1 (strict).** A trait-world call either computes exactly what plain Julia computes in the current session, or raises an error. The error is either the error plain Julia raises, or a `HiddenMethodError` naming the method plain Julia would have run.
**G1′ (lenient).** The result equals plain Julia's result with, at every dispatch, the methods hidden from that dispatch removed. Pirates from outside a package's dependencies never change its results.
**G2.** Take a compiled trait-world specialization `X` for MethodInstance `(m₀,S₀)`, and let `P(X) := closure*({module(m₀)} ∪ owners(S₀))`.
- `X` is valid in every session with the same versions of `P(X)`, in any load order.
- Loading a package outside `P(X)` never invalidates `X`.
- In strict mode the one exception is a package with a method that plain Julia would actually select at a dispatch `X` performs. That package is not "unrelated", and `X` errors at that site instead of recompiling against it.
**G3.** In a binary, the package set is the application's closure. The reachable methods are the static edges plus, for each dynamic site, the visible methods of that closure applicable to the site's type. Both sets are finite and listable. R3 checks become build-time checks, because every method is known.

**Assumptions.**
- **A1:** Julia's inference and codegen are correct relative to the method table they are given.
- **A2:** Execution is deterministic given its dispatch decisions. G1 excludes results that depend on inference precision, such as the eltype of an empty `map`, which is load-dependent in plain Julia too. It also excludes reflection outside H0, timing and thread scheduling.
- **A3:** Code of module `M` can only name bindings of modules in `closure*({M})`, and fields of a type are declared in its owner's closure. Packages satisfy this. `@eval` into foreign modules is attributed by H1's loading context.
- **A4:** A package is loaded once. An extension is loaded together with its last trigger, before any value of a trigger type exists.

**Lemma 1 (non-pirates are never hidden).**
- Claim: suppose `m` applies to concrete `S`, and `module(m)` owns the function or owns a type at a non-`Union` position of `sig(m)`. Then `module(m) ∈ V(c,S)` for every `c`.
- Proof: the matching component of `S` is that type, or a type defined in a module that must depend on `module(m)` to name it (A3). So `module(m) ∈ closure*(owners(S))`.
- Consequence: hidden methods are exactly the pirates relative to that dispatch.

**Lemma 2 (closedness).** Every static edge `(c,S)` of `X` satisfies `V(c,S) ⊆ P(X)`.
- By induction over the inference tree: each callee is visible, so its module is in `V ⊆ P`.
- Each type in a callee's `S` comes from `S₀`, is a declared field type, or is constructed by code in `P`, so it is owned in `P` (A3).
- Abstract values have no edges (R2).

**Corollary.**
- By A4, every module of `P(X)` was loaded before `X` existed.
- By Lemma 2, a method from a module loaded later is invisible at every edge of `X`.
- So `X`'s dispatch decisions depend only on the methods of `P(X)`, and those are fixed by their content hashes. Only edits by REPL or Revise to modules of `P(X)` change them, and H2 then invalidates (fact 2, fact 4).

**Invariants**, with `disp_V(c,S)` the R1 dispatch and `disp_J(S)` plain Julia's dispatch over the full table:
- **I1:** for every valid trait-world `X` and every static edge `(c,S→m)` of `X`, `disp_V(c,S) = m`.
- **I2 (strict):** for every untrapped edge, `disp_J(S) = m`.

**Preservation by event:**
- *Method insertion `m′`, from a package load, REPL or Revise.*
  - I1: `disp_V(c,S)` can change only if `m′` is visible at `(c,S)`, applies and wins. By the corollary, that needs `module(m′) ∈ P(X)`, which only happens for edits. H2 then invalidates exactly those `X`.
  - I2: `disp_J(S)` changes only if `m′` applies and wins. If `m′` is visible, I1 has already invalidated `X`. If it is hidden, H2 places a trap.
  - Deletion and overwrite are handled the same way.
- *Package-image load of `X`.* `P(X)` has the same hashes, so the visible method sets at all edges are identical (Lemma 2), which gives I1. The index check gives I2.
- *Compiling a new `X`.* H0 infers against `disp_V` (I1 at creation) and checks the index (I2).
- *Dynamic dispatch.* H3 returns `disp_V(c,S)`. Strict mode errors unless `disp_J(S)` equals it.
- *Call through a pointer or `@plain`.* The callee runs plain Julia, so its result is plain Julia's by definition. The result is asserted. There is no edge, so there is nothing to preserve.

**Theorem (G1).** Assume I1, I2 and H3. Then a trait-world call takes the same steps as plain Julia, by induction over steps. Non-dispatch steps (builtins, `ccall`, field access) are identical (A2). Every dispatch selects the same method, or raises an error where plain Julia also errs, or raises `HiddenMethodError`. In lenient mode, drop I2 and the same induction gives G1′.

## 3. Test cases

**A (Base).**
- Arithmetic, arrays, `sum` and `sort` dispatch on Base or platform types. `lu!` comes from LinearAlgebra, which is platform.
- LinearAlgebra extends Base's functions on Base's arrays (piracy by the letter). Putting it in the platform keeps `A^2` from Base's `literal_pow` coherent.
- `print`/`show` on `Any` (fact 9) is an H3 dispatch at the concrete `S`. A user's or package's `show(::IO, ::Foo)` is visible because the owner of `Foo` is in `owners(S)`.
- Costs (estimates, unmeasured):
  - Static calls: the same machine code as plain Julia.
  - Dynamic calls: one cached lookup per (closure id, `S`), similar to Julia's dynamic dispatch (tens of ns).
  - Compilation: a second "pristine Base" copy of the Base specializations the trait world uses, compiled once and cached in images (memory and disk duplication).

**B (Cairo.jl).**
- The plotting library depends on Cairo, so Cairo's methods are in its view. `ccall` is a builtin, so side effects behave as in plain Julia.
- `CairoContext` and surfaces pass through as ordinary values or opaque handles, with no wrappers. Finalizers are run by the runtime in plain Julia.
- Cost: zero overhead. G3: the `ccall` targets are listable.

**C (ForwardDiff).**
- The user calls `ForwardDiff.gradient(p -> loss(solve(prob(p))), p0)`. The key of `solve` contains `Dual{Tag{typeof(closure),Float64},Float64,N}`.
- `owners` includes ForwardDiff and the user's module, so all `Dual` arithmetic, `promote_rule`, `convert`, NaNMath and SpecialFunctions extensions are visible, through `closure*` and extensions.
- None of these are pirates, so by Lemma 1 nothing about duals is ever hidden: R3 cannot fire, and G1 is exact.
- The solver's own Jacobian duals use a tag type owned by the solver package, and nested `Dual{JTag,Dual{UTag,…}}` is covered the same way.
- No library-owned dual type is needed.
- Conformance of `Dual` to the solver's number trait is one declaration in the solver's ForwardDiff extension. That declaration is visible exactly when both packages are present.
- Cost: the solver compiles once per dual key, as plain Julia would, and is cached in the user's image. Loading Makie afterwards touches nothing.

**D (Makie + CSV + DataFrames, any order).**
- None of these packages is in any trait-world `P(X)`, so H2 never invalidates trait-world code.
- Load order is irrelevant, because views depend on module sets, not on insertion order.
- The Base pirates of OffsetArrays, StatsBase and Durations enter the hidden-capable index (H1: O(1) per method). Their check against trait-world edges on the same functions is a subtype test with no recompilation (milliseconds, versus the measured 0.7–1 s of invalidation).
- Strict mode errors only where such a pirate would *win* at a concrete signature the trait world actually uses. Gap-filling pirates mostly apply where Base has no more specific method, i.e. where the trait world would otherwise get a `MethodError`. This frequency is to be measured.
- A DataFrame passed in as a handle and printed dispatches with DataFrames in `owners(S)`.
- Explicit conversion in a plain layer (fact 6) remains the recommended route for data.

## 4. What it gives up; the strongest objection

**Gives up:**
1. **The global method table inside the trait world.** Some code relies on a pirate outside its own dependencies that is not attached to the argument types, for example Base's broadcast calling a Base function that a third-party pirate gap-fills. Such code gets `HiddenMethodError` (strict mode) or Base's own behaviour (lenient mode). The remedies are an application-level `platform += Pkg` (one line; it changes the cache key, so the trait world recompiles once for that application) or `@plain`.
2. A duplicate code cache for Base code used by both worlds.
3. Inference at abstract call sites (R2). Type-unstable trait-world code runs slower than plain Julia.
4. H0 must answer reflection (`applicable`, `hasmethod`, `return_type`) in the view.

**Why not a plain world-age snapshot?** Freezing one world `w` is the simplest view, but it is wrong in two ways:
- It hides legitimate non-pirate methods loaded later: ForwardDiff loaded after the solver, user types, Revise edits.
- It treats a method's age, not its owner, as the reason for visibility.

Per-package snapshots, combined with "owners of the argument types are always visible", keep every non-pirate (Lemma 1) and drop only what piracy makes load-dependent.

**Strongest objection.** "This splits the meaning of a generic function by module, which Julia's single method table exists to prevent (Haskell's orphan-instance problem). Strict mode only moves lesson 3's pain from load time to call time."

**Answer:**
1. By Lemma 1 the split concerns only methods that are pirates *at that dispatch*. Plain Julia already gives those a load-dependent meaning: the same package computes differently depending on what else is loaded. For every other method the view and the global table agree. So the trait world never differs silently. It errors, names the pirate, and points to the one-line fix.
2. Refusal and invalidation fire on *intersection* with any edge. R3 fires only when the pirate would actually be *selected* on concrete types the trait world uses, never at load time, and never recompiles anything. Lesson 3's failure modes (unloadable stacks, 0.7–1 s re-compiles) are therefore gone. What remains is an explicit, local, rare error where the alternative is a silently different result.
3. The guarantee is crisp: compiled trait-world code depends on exactly `P(X)`, and that set is listable from the key (Lemma 2). One set gives the cache key (G2), the binary's method list (G3), and the complete list of places where plain Julia could disagree (G1).
