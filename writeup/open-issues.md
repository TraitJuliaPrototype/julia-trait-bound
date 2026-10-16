# Open issues

Everything known to be open, as of 2026-10-16 (end of session 22): the design, the prototype, the runtime and measurements, and the documents. Decisions already taken are in `decisions.md`.

## 1. Decisions waiting for the user

1. **TraitWorld's runtime as methods** (`explorations/keys-plan.md` §6, `experiments/keys-proto/`).
   - **The proposal:**
     - conformances become methods, `view(::Type{X}, u::U)`;
     - entries become ordinary `@inline` methods that are `@nospecialize` on trait arguments;
     - the entry caches, builders and the generation counter are removed.
   - **Measured** in the prototype: 26–30 ns per call against 25–29 ns for plain Julia, with no allocation and one worker for all user types. TraitWorld now costs 209–460 ns.
   - It rewrites about a third of TraitWorld. Users see only the speed.
2. **Conversions in trait wrappers:** whether a trait wrapper may offer conversions for foreign types that share code, now that conformance never converts (4-details "Types that only convert").

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

State: commit `3e4bd5a` on `main`, 311 tests plus 1 broken (pre-existing), on stock Julia 1.13.2.

**Behind the notes**
1. The implementing type is always present in the key; the notes say none when defaults serve every operation (329e945).
2. Overrides after a conformance are not refused.
3. Fields define parameters only in the form `u::U`, not by matching (`data::Vector{T}`).
4. Immutable user types are read through the boxed object rather than held, which costs a box per call from typed code.
5. Field mappings (`name => stored`) work. Agreement of a subtrait's conformance with its supertrait's is not checked.
6. Forwarding for a whole family; named implementations; archetype checks for keyword, vararg and `Callable` workers with declared results.
7. AOT for results like the input: the inverse per user type is not listed for `verify_main`.
8. Concrete mode does not yet trace field types of keys as root causes.

**Performance**

9. The fixed cost per call of an entry is 209–230 ns for a type that implements the operations and 424–460 ns for a forwarding type (`total(t, 16)`). Plain Julia is 33 ns. It was 108–119 ns at 2830a19. It grew with associated types, results like the input and the key layout. The rewrite of section 1, item 1, removes the path that costs it.
10. A worker reached directly allocates 48 bytes per call under the current layout (the prototype's layout does not).
11. A fresh session's `@implement` of a forwarding type takes about 470 ms against 145–157 ms before (`bench_m1`); not yet investigated.

**Dependent code**

12. `experiments/world` benchmarks and packages use the old `{R}` spelling, which still works. `experiments/interfaces` (the DataFrames and Makie prototype) uses computed projections and is pinned to TraitWorld before keys; its measurements (sealing audits, 3 ms view caches, binaries) were taken before keys.
13. The old `{R}` spelling of traits is still accepted; removing it, and converting the 23 traits in the tests, is phase 4 of the plan.

## 4. Runtime and measurements

1. With a view cache on stock 1.13.2, `summarize` recompiles for 71–74 ms once CSV and Makie are loaded (3.3 ms in session 21 on 1.12). It is unclear whether 1.13 or TraitWorld causes this (`experiments/baseline-1.13.md`).
2. The injected load filter does not help when outside packages load after the trait code; that needs the insertion half in C, i.e. the patched 1.13 build (postponed).
3. Not yet measured on 1.13: plain-Julia time to first PNG, ComboCache end to end, an x12 control on 1.12.2 with the pinned TraitWorld.
4. The trimmed-binary acceptance build (2.09 MB `verify_main` program) has not been rebuilt since keys; run it alone, under a memory guard.

## 5. Documents

1. `explorations/makie-rewrite.md` and `explorations/solvers.md` were written with representations and projections. Their trait sketches are to be read with keys (each has a banner). Rewrite them when the demonstrators start.
2. `design-findings.md` is the evidence log in session order. Sections 3, 7, 9–12 and 14 describe earlier forms of the design (its status header says which sections are current).
3. The live Claude Doc is frozen at revision 1146; its export is in `attic/writeup/`.
