# Open issues

Everything known to be open, as of 2026-10-16 (end of session 23): the design, the prototype, the runtime and measurements, and the documents. Decisions already taken are in `decisions.md`.

## 1. Decisions waiting for the user

1. ~~Conversions in trait wrappers~~: dissolved by wrapping by facts (s23).
2. **Conversions in trait wrappers (old wording):** whether a trait wrapper may offer conversions for foreign types that share code, now that conformance never converts (4-details "Types that only convert"). Wrapping is deferred, so this can wait.

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
23. Indexes for the load-time checks (sealing, the dispatch check), so they never scan all methods (prediction 7).
24. Inference-dependent element types (`promote_op`): the declared exception to "identical or error"; solvers must declare them instead (solvers.md §11.8).
25. The compile cost of recipes and models defined at the prompt; views exclude modules under `Main` (findings §15, makie-rewrite.md §8.8).

## 3. TraitWorld (the prototype)

State: `main` at d65bb57, 346 tests plus 1 broken (pre-existing), on stock and on patched Julia 1.13.2. The runtime as methods, keys in the reference layout, no implementing type under defaults, overrides refused at checkpoints, fields matching parameters and immutable types held are in (session note 23).

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
2. The patched 1.13.2 build exists (`julia-1.13/`). Its filter protects code from a definition only if the definer owns no type in the code's signature (review F1, fixed in 280612ed2f; before, a user's redefinition of its own implementation left the worker stale). Measured with it (session note 23): CSV and DataFrames loaded after TraitMakie invalidate no PlotCore code and 14 machinery methods (285 on stock). CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations still invalidate 2–4 ODECore methods and 323 machinery methods: these loads bring pirates of Base (OffsetArrays, StatsBase, Durations), which invalidate by design, and owned methods (InlineStrings, Unitful) that reach Base methods compiled for trait-world callers, which the insertion half does not protect (the load half's callee rule has no insertion counterpart). A pirate-free load set is needed to separate the two.
3. Not yet measured on 1.13: plain-Julia time to first PNG, ComboCache end to end, an x12 control on 1.12.2 with the pinned TraitWorld.
4. The trimmed-binary acceptance build (2.09 MB `verify_main` program) has not been rebuilt since keys; run it alone, under a memory guard.
5. The first call after large loads: TraitDifferentialEquations' first solve takes 0.7–1.05 s with CSV, DataFrames and CairoMakie loaded (73 ms without); TraitMakie's first PNG takes 0.31–0.37 s with CSV and DataFrames before (0.1–0.2 s without; 0.09 s after, patched).

## 4b. The review of session 23

The findings F2–F11 and nine decisions of `reviews/2026-10-16-wrapping-under-keys.md` are open, except F1 (fixed). What Julia must provide, in order: `explorations/julia-support.md`.

## 5. Documents

1. `explorations/makie-rewrite.md` and `explorations/solvers.md` were written with representations and projections. Their trait sketches are to be read with keys (each has a banner); the demonstrators' code (TraitDifferentialEquations, TraitMakie step 1) now shows the keys form.
2. `design-findings.md` is the evidence log in session order. Sections 3, 7, 9–12 and 14 describe earlier forms of the design (its status header says which sections are current).
3. The live Claude Doc is frozen at revision 1146; its export is in `attic/writeup/`.
