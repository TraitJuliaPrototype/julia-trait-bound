# Open issues

Everything known to be open, as of 2026-10-17 (session 25): the design, the prototype, the runtime and measurements, and the documents. Decisions already taken are in `decisions.md`.

## 1. Decisions waiting for the user

Deferred by the user in session 25, to take up when wanted:
1. **Strict mode's intended design** (compiled trait code never invalidated except by edits): `strict-mode.md` §2b. Needs Julia pieces 1′, 14 and 15, a transitive check, `twolibs` as acceptance, and the extension rule.
2. **AOT annotations for calls into ordinary code** (A–E): `aot-under-facts.md` §6. The remaining binaries (TraitDifferentialEquations with ForwardDiff; CSV and DataFrames) also wait.

(Conversions in trait wrappers dissolved with wrapping by facts, s23.)

(Session 23 settled the runtime as methods and D1–D9: session note 23, `decisions.md`.)

## 2. Design

**Keys and fields**
1. A field declared with an abstract type in a trait that does not require concreteness: its key is abstract, so every read is followed by a dispatch.
2. Fields stored inline that are not isbits (an immutable struct holding references): read through `getfield`, or loaded inline by a runtime.
3. A layout that copies the fields, opt-in per trait, for GPU kernels and other isbits-only targets; valid only for traits without writable fields.
4. Forwarding for a whole family of user types, `Series{T} by data`: designed (4-details "Parametric user types"), not prototyped.
5. Mutable and immutable state families: `u` writable in one and `const` in the other. Either two traits, or field constness that depends on the family (solvers.md §11.7).

**Parameters and types**

6. Input parameters (several values per type), associated type constructors beyond one family, and results bounded by their own trait (`view`, Swift's `SubSequence`).
7. Whether an operation may return a small `Union` of concrete types, and what concrete mode reports for it (makie-rewrite.md §8.4).
8. Numeric traits: numbers that conform after the fact or forward to a field, and promotion across implementing types. Definition checking of code that computes with an element type needs a numeric archetype or a bound (solvers.md §11.6).
9. Automatic-differentiation tags as part of a key; units (solvers.md §11.4, §11.11).
10. `Callable` bounds whose argument types are chosen by the callee, a type-level function of the algorithm's configuration (solvers.md §11.9).

**Bounds, dispatch, arguments**

11. How `Vector{<:ColTable}` takes a user's vector: element by element into a new vector of trait objects, or as a whole.
12. Bounds over several arguments at once, `lines(x, y)`, where today a conversion builds one value from both; this ties to promotion (makie-rewrite.md §8.1).
13. "Live" bounds: an argument that is a value or a source of values (`Live{X}`, makie-rewrite.md §8.3).
14. The joint-method rule for wide families such as `plot(x)` over data traits (makie-rewrite.md §8.9).

**Dynamic values and functions**

15. A dynamic mode for a type's own operations, pinned per integrator with a world-age rule: the solvers' model mode (solvers.md §11.1). It is plan item 7 in the README, to build when TraitDifferentialEquations needs it.
16. Opening a `Dynamic` at the conformer's own concrete type, a checked downcast, for callbacks that change parameters (solvers.md §11.2).
17. How a closure created inside a trait module is stored as a dynamic function: by dispatch, or by a pointer (makie-rewrite.md §8.5).
18. Assignment from above into a field declared by a trait name, `plot.color = x` at the prompt: whether `setproperty!` from ordinary code there is an entry (makie-rewrite.md §8.7).
19. Tasks and concurrency: trait objects and `Dynamic` values across tasks; spawning a trait-world closure (makie-rewrite.md §8.6).
20. Reporting a function from above that always throws when its pointer is made (`Union{}` result at the declared signature; solvers.md §11.10).

**Checks and guarantees**

21. Checking held parts after each call upward: obsolete under the reference layout, kept only for the opt-in copying layout of item 3.
22. An example and a test that a value crossing upward behaves as it does inside (C++0x's `late_check`, 2-design-choices, prediction 3).
23. Indexes for strict mode's attribution of methods to packages, so that it never scans all methods (prediction 7). Sealing and the dispatch check, for which this was first written, are gone.
24. Inference-dependent element types (`promote_op`): the declared exception to "identical or error"; solvers must declare them instead (solvers.md §11.8).
25. The compile cost of recipes and models defined at the prompt; views exclude modules under `Main` (findings §15, makie-rewrite.md §8.8).

## 3. TraitWorld (the prototype)

State (session 25): `main` at 893f0bb, 343 tests on the patched 1.13.2 build (308 on stock, where strict mode's 32 tests and the hook tests are skipped).
- **In:** the compiler policy of wrapping by facts, strict mode as a prototype, `verify_main` with dynamic values' targets, the closed-build replacement of the policy's call.
- **Removed:** wrappers, sealing, the filter, doors, layering, the native piracy audit and guard.
- **Earlier:** the runtime as methods, keys in the reference layout, overrides refused at checkpoints (session note 23).

**Open from session 25:**
- **Trim's own verifier.** `--trim=safe` reports the machinery's slow paths behind the run-time `CLOSED_WORLD` flag, so builds use `unsafe-warn`. To do: make them invisible to trim in a closed build, for example by a constant decided at generation, like `_policy_path()`.
- **`verify_main` walks from `main` only.** Packages' `__init__` functions run at startup too. JLLWrappers' `unique!` needed two entry points by hand in the first binary.
- **Strict mode's prototype checks direct callers only.** Dependence through native code (`return_type` folds, the machinery) is caught only by the safety net (`strict-mode.md` §2b, item 2).
- **New trait code after big loads:** 2.7 s to define a small module, against 1.0 s; the checks' recursion (Julia pieces 7 and 12, or a walk without recursion).
- **Threads:** assumption A4 until Julia piece 11 (through 1.13's `CompilerPlugins` hook).
- **The hunt's C24b:** a harness bug.


**Behind the notes**
1. Overrides after a conformance are refused at checkpoints (declarations, a trait module's end, a signature's first call), not when the method is defined: that needs a hook at method insertion.
2. Which functions keep a trait object is decided once, when the trait module is complete. A method added at the prompt to a callee that keeps does not update its callers' flags; the error in the "results like the input" path is the safety net. Operations on a kept value of a mutable type cost about 900 ns (`keepsum`), mostly the dynamic operation.
3. Field mappings (`name => stored`) work. Agreement of a subtrait's conformance with its supertrait's is not checked.
4. Forwarding for a whole family; named implementations; archetype checks for keyword, vararg and `Callable` workers with declared results.
5. AOT for results like the input: the inverse per user type is not listed for `verify_main`.
6. Concrete mode does not yet trace field types of keys as root causes.
7. Bounds cannot use a method's `where` variables (`f(s::Sampled{T}) where {T}`): such an annotation is read as a plain type. Results through an opened `Dynamic` are not inferred; library code asserts them.
8. Family conformances (`@implement X{T} S{T} where {T}`, and by fields) go through the slow path: a builder per type per session, cached.

**Performance**

9. Typed calls cost 33 ns against 30 ns for plain Julia (`total(t, 16)`), without allocation. Untyped calls (the caller does not know the argument's type) cost 105–117 ns and 64 bytes (270–295 ns before TraitWorld 5efbb4c: the entry built the tuples for a result like the input on every call). What remains is two dynamic calls (`enter`, `checked_call`), the boxed trait object and the boxed result; removing them would compile part of the entry per user type.
10. A worker that has not been called in a session runs `_check_once` and the piracy guard at its first call; after any world change the guard audits the signature again (the PoC's stand-in for rule 4), which costs tens to hundreds of milliseconds after large loads.
11. A fresh session's `@implement` of a forwarding type: not re-measured since the rewrite (it was about 470 ms).

**Dependent code**

12. `experiments/world` benchmarks and packages use the old `{R}` spelling, which still works. `experiments/interfaces` (the DataFrames and Makie prototype) uses computed projections and is pinned to TraitWorld before keys.
13. The old `{R}` spelling of traits is still accepted; removing it, and converting the 23 traits in the tests, is phase 4 of the plan (D2, not done in session 23).

## 4. Runtime and measurements

1. With a view cache on stock 1.13.2, `summarize` recompiles for 71–74 ms once CSV and Makie are loaded (3.3 ms in session 21 on 1.12). It is unclear whether 1.13 or TraitWorld causes this (`experiments/baseline-1.13.md`).
2. *(Resolved by wrapping by facts, session 24: with nothing skipped, 0 facts-owned CodeInstances are lost to any of twelve loads, in any order; `wrapping-by-facts.md` §Validation. Kept for the record.)* The patched 1.13.2 build exists (`julia-1.13/`). Its filter protects code from a definition only if the definer owns no type in the code's signature (review F1, fixed in 280612ed2f; before, a user's redefinition of its own implementation left the worker stale). Measured with it (session note 23): CSV and DataFrames loaded after TraitMakie invalidate no PlotCore code and 14 machinery methods (285 on stock). CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations still invalidate 2–4 ODECore methods and 323 machinery methods: these loads bring pirates of Base (OffsetArrays, StatsBase, Durations), which invalidate by design, and owned methods (InlineStrings, Unitful) that reach Base methods compiled for trait-world callers, which the insertion half does not protect (the load half's callee rule has no insertion counterpart). A pirate-free load set is needed to separate the two.
3. Not yet measured on 1.13: plain-Julia time to first PNG, ComboCache end to end, an x12 control on 1.12.2 with the pinned TraitWorld.
4. *(Done in session 25 for TraitMakie: 4.07 MB, 0.05 s, the PNG identical to the session's; `aot-under-facts.md` §7.)* The `experiments/world` program (2.09 MB) has not been rebuilt since keys.
5. *(Resolved in session 24: TraitDifferentialEquations' first solve 55–60 ms and TraitMakie's first PNG 89–97 ms in every load order. Open in its place: **new** trait code defined after big loads, 2.7 s to define a small module and 0.8 s for its first call, against 1.0 s and 0.09 s; the definition-time checks, Julia pieces 7 and 12.)* Before: TraitDifferentialEquations' first solve takes 0.7–1.05 s with CSV, DataFrames and CairoMakie loaded (73 ms without); TraitMakie's first PNG takes 0.31–0.37 s with CSV and DataFrames before (0.1–0.2 s without; 0.09 s after, patched).

## 4b. The review of session 23

Triage after wrapping by facts (session 25) of `reviews/2026-10-16-wrapping-under-keys.md`:
- **Fixed:** F1.
- **Dissolved:** F2 (implementations in ordinary modules have no place in the layering: there is no layering for calls), F4 and F8 (sealing), F5 (the wrapper's role for foreign types: there are no wrappers), F6 (results from above with a trait bound: `Dynamic{X}`, adopted), F7 (opaque values handed down: trait code may pass any value to any code), F10 (automatic differentiation: ForwardDiff's own `Dual`, session 24).
- **Still open:**
  - **F3:** family conformances over Base's abstract types, and later methods by the members' owners. Since session 24, conformances are decided in the caller's world and cached per world (G1.13), which may settle it; an acceptance case is needed.
  - **F9:** the walk of abstract parts at the entry against the reference layout.
  - **F11:** stale statements, to go with the rewrite of the notes.
- **Its decision 4** (who declares a foreign type's conformance) still stands without wrappers: the trait owner's package extension, as the prototype does.

What Julia must provide, in order: `explorations/julia-support.md`, reviewed in session 25.

## 5. Documents

1. `explorations/makie-rewrite.md` and `explorations/solvers.md` were written with representations and projections. Their trait sketches are to be read with keys (each has a banner); the demonstrators' code (TraitDifferentialEquations, TraitMakie step 1) now shows the keys form.
2. `design-findings.md` is the evidence log in session order. Sections 3, 7, 9–12 and 14 describe earlier forms of the design (its status header says which sections are current).
3. The live Claude Doc is frozen at revision 1146; its export is in `attic/writeup/`.
