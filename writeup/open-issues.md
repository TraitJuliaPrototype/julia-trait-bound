# Open issues

Everything known to be open, as of 2026-10-20: the design, the prototype, the runtime and measurements, and the documents. The current design is the [references](reference/README.md), with the rationale in [`design.md`](design.md); the decisions, with their origins, are in [`record/decisions.md`](record/decisions.md). The current measurements are `design/evidence.md`; what Julia gained is `design/julia-changes.md`.

Only open items are listed in sections 1–5. Items keep their numbers, so that references such as "§1.10" stay valid; the gaps are closed items, which are listed at the end, under [Closed items](#closed-items), with how and where they were closed. Commits are in the repository named (julia-1.13, TraitWorld, a demonstrator).

## 1. Decisions waiting for the user

Deferred by the user (s25), to take up when wanted:
1. **Strict mode's intended design** (trait code never invalidated except by edits; strict mode applies to trait code, decided 2026-10-20): `strict-mode.md` §2b; [facts §10.3](reference/facts.md#strict-intended). Needs Julia pieces 15 (image-validation report), 14 (transitive check) and 1′ (deletion hook), which must join the first upstream proposal; `twolibs` in the acceptance suite; the warning for a package extension's winning method (decided 2026-10-20, closed item 1.10; [facts F-14](reference/facts.md#deviations)). Still to decide, from item 10 (framing review §5.4): bindings as something a pirate can change (no hook exists; [facts §2.2](reference/facts.md#g2)); the session as owner at the prompt. Still to measure: strict mode under `all` (837 pirates by the letter in g2strict, none refused, Base's facts not yet checked).
2. **AOT annotations for calls into ordinary code** (A–E): `aot-under-facts.md` §6. The remaining binaries (TraitDifferentialEquations with ForwardDiff; CSV and DataFrames) also wait.

From the three reviews of 2026-10-18 (`reviews/2026-10-18-*.md`; what the user decided then is in `decisions.md`):
13. *(Reworded in s29: "never run" is no longer true.)* **Base's tests in facts mode** (plan §2.4) ran once, on an early build (julia-1.13 880ae49dad), and did not finish. The strings tests failed only on inference-precision checks at abstract signatures, as expected. `core` stalled on issue #10981's `vcat(x...)`, which led to the decision that concrete `Vararg` tails are facts (`decisions.md`). The other files did not run. *Half closed (s29):* the facts mode no longer changes values decided at run time: `return_type` there is answered by plain inference in its own cache owner (`PlainRTInterp`, julia-1.13 880ae49dad; [compiler §1.4](reference/compiler.md#14-return_type)). Open: Base's tests and BaseBenchmarks again, on the current compiler (§4.13). Was: "were never run; the go/no-go benchmark ran in a configuration that changes values (design review, finding 1)."
15. **The concreteness declaration's spelling** (decisions review change 7, adopted): one declaration with a level (silent, warn, error) at a trait or a module; the per-parameter grain (`IntegratorView{T, P}`, design review) as an argument of the same declaration later.
16. **The demonstrators' claims after the control** ([evidence](design/evidence.md#summary-what-the-evidence-shows-and-what-it-does-not); [state §6.3](state.md#63-the-order-of-work)): which rows remain trait results once the plain baselines run under `all`; each README's "what it demonstrates" re-pointed. *(Progress in s29: the control ran for PlainTables + TraitMakie and for upstream CSV + DataFrames, `design/evidence.md` §1. Load protection is the facts rule's property, for any code. PlainODE and PlainPlots under `all` were not run. The READMEs' status and measurement sections now point at `design/evidence.md`; their "what it demonstrates" sections are not re-pointed yet.)*
17. **The refusal message for a late override** (`TraitWorld/src/hooks.jl:151`): "or in its block" is not available after the fact (design review); the message should name redeclaration once it exists, and a restart until then.

From the compiler as built (`decisions.md`, "Pending"):
18. **Should concrete mode warn about a variable of a small `Union`?** Today it does not: the union's splits are facts, so the code is fully typed. The example `experiments/examples/warnings/teach.jl`, case e, waits for this decision (pending). Related: §2.7.

From the writeup review of 2026-10-19 (`reviews/2026-10-19-writeup-review.md`):
19. **Should standard libraries be separate owners?** Today Julia (Core, Base, the standard libraries) is one owner ([facts §1](reference/facts.md#term-owner); `TraitWorld/src/ownership.jl` `owner(m)` returns `:Julia` for every standard library, `strict.jl` skips `:Julia`), so a standard library's method on Base types (SparseArrays' `vcat` for `Number` and `Vector`, loaded by StatsBase) is a stakeholder's change: followed, never refused. TraitWorld's `_type_root` already treats a standard library's types as its own. Found by the writeup review of 2026-10-19 (finding 1).
20. **Pirates in trait modules:** refuse every pirate at definition, as the prototype does (`OwnershipError`, [traits §12.2](reference/traits.md#122-pirates)), or only winning pirates under strict mode, as the argument says ([the argument §3.2](design/argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached), [facts §10](reference/facts.md#pirates))? The disagreement is listed in "Found in the writeup cleanup", item 1. Found by the writeup review of 2026-10-19 (finding 28).

## 2. Design

**From the acceptance suite and the design of `Dynamic`:**
- **A world-checked call-site cache for `Dynamic` beyond four implementations** (Optional, [compiler §3.3](reference/compiler.md#33-further-work-on-mechanism-3)): built for `DynamicCall`'s pointers ([compiler §3.1](reference/compiler.md#31-the-cfunction-calling-convention-caller_world)); for `Dynamic`, to prototype and measure against the split and the fallback.

**From the references (2026-10-19): Open items without an entry before**
- **The setting as part of a package image's key.** Images are not keyed by the setting (product or test bed), nor by `--trim` ([facts F-7](reference/facts.md#deviations)).
- **`verify_main` under the test bed** reports a run-time site in Base (`convert(Type{AbstractString}, ::Any)` inside `DomainError`) as a hole. Whether Base's own run-time sites under `all` count as holes ([facts F-8](reference/facts.md#deviations)).

**Keys and fields**
1. A field declared with an abstract type in a trait that does not require concreteness: its key is abstract, so every read is followed by a dispatch.
2. Fields stored inline that are not isbits (an immutable struct holding references): read through `getfield`, or loaded inline by a runtime.
3. A layout that copies the fields, opt-in per trait, for GPU kernels and other isbits-only targets; valid only for traits without writable fields.
4. Forwarding for a whole family of user types, `@implement X Series{T} by data where {T}`: planned ([traits §5.7](reference/traits.md#57-families)), not prototyped.
5. Mutable and immutable state families: `u` writable in one and `const` in the other. Either two traits, or field constness that depends on the family (solvers.md §11.7).

**Parameters and types**

6. Input parameters (several values per type), associated type constructors beyond one family, and results bounded by their own trait (`view`, Swift's `SubSequence`).
7. Whether an operation may return a small `Union` of concrete types, and what concrete mode reports for it (makie-rewrite.md §8.4). The reporting half is the pending decision §1.18.
8. Numeric traits: numbers that conform after the fact or forward to a field, and promotion across receiver types. Definition checking of code that computes with an element type needs a numeric archetype or a bound (solvers.md §11.6).
9. Automatic-differentiation tags as part of a key; units (solvers.md §11.4, §11.11).
10. `Callable` bounds whose argument types are chosen by the callee, a type-level function of the algorithm's configuration (solvers.md §11.9).

**Bounds, dispatch, arguments**

11. How `Vector{<:ColTable}` takes a user's vector: element by element into a new vector of trait objects, or as a whole.
12. Bounds over several arguments at once, `lines(x, y)`, where today a conversion builds one value from both; this ties to promotion (makie-rewrite.md §8.1).
13. "Live" bounds: an argument that is a value or a source of values (`Live{X}`, makie-rewrite.md §8.3).
14. The joint-method rule for wide families such as `plot(x)` over data traits (makie-rewrite.md §8.9).

**Dynamic values and functions**

15. A dynamic mode for a type's own operations, pinned per integrator with a world-age rule: the solvers' model mode (solvers.md §11.1). It is plan item 7 in the README, to build when TraitDifferentialEquations needs it.
16. Opening a `Dynamic` at the conforming value's own concrete type, a checked downcast, for callbacks that change parameters (solvers.md §11.2).
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

**From the compiler as built:**
27. **The B1 boundary: facts code that calls compiler functions directly** (the performance review of 2026-10-19, B1). TraitWorld's machinery calls `argextype`, `widenconst` and `sptypes_from_meth_instance`. Such calls hold edges to plain compiler code, whose validity is plain Julia's. Documented, not fixed ([facts §6.4](reference/facts.md#the-compilers-own-code); [lowering L-17](reference/lowering.md#18-deviations)). The reason: a rule that ran such calls in the compiler's world would break packages that extend the compiler for their own interpreter types. The loss is cacheability, not correctness: the control's nine-package load lost no facts code in the modules it counted (TraitMakie 0; TraitWorld's own code was not counted separately).
28. **AOT from declared targets: the forks' workload extensions** ([traits §15](reference/traits.md#15-compiling-ahead); [lowering §15.1](reference/lowering.md#151-compiling-ahead-from-declarations); [state §6.3](state.md#63-the-order-of-work)). Compiling ahead from declarations is built (TraitWorld `src/ahead.jl`): while a package that declares an implementation is precompiled, the workers for its key, the pattern methods for untyped callers, an entry method for the type and their first-call checks go into its image. Still open: replacing hand-written workload extensions such as the forks' `CSVDataFramesInlineStringsExt` (CSV + DataFrames + InlineStrings, forks 9d512a1), which the performance review calls a workaround, by it; what it leaves out, functions with several trait positions or a vararg ([lowering L-15](reference/lowering.md#18-deviations)); and what its entry methods invalidate (item 29).

**From the code reviews of the references (2026-10-19):**
29. **Entries compiled ahead without new methods: accepted for now; flagged for future review** (the user, 2026-10-20: "invalidating plain callers is fine, but flag this for future review"). The reason: only plain code is invalidated, trait code never; results stay the same; the plain code is compiled again once, at its next call; and the alternatives below give up the untyped caller's direct dispatch. Stated as the intended shape in [traits §15](reference/traits.md#15-compiling-ahead) and [lowering §9.3](reference/lowering.md#93-entries-compiled-ahead); T-24 and L-22 are retired. For the review: the entry method compiled ahead for a declared type is a new method of the library's function, so in the product setting it invalidates plain callers at abstract argument types and the entry's own untyped specialization, at the declaring package's precompilation and at each load of its image (`experiments/docs-examples/ahead_invalidation.jl`). Code compiled by facts is not affected. To review: whether the per-type entry should be reached without a new method of the library's function, for example through the untyped table's pointer, at the cost of the faster dispatch it gives an untyped caller (one dispatch to a method of its own), or the entry method dropped, since the pattern method already gives untyped callers code compiled once per key.
30. **One answer for `return_type` in the product setting.** The compile-time fold infers a facts method plainly (`PlainRTInterp`); the run-time route, a `NativeInterpreter` of owner `nothing`, hands it to facts inference, which can answer wider ([facts F-10](reference/facts.md#deviations), [compiler C-11](reference/compiler.md#deviations)). The intended answer is plain inference's ([facts §7.1](reference/facts.md#return-type), rule 3). To decide how: `PlainRTInterp` for the run-time route in both settings, accepting a second cache's inference for plain methods ([compiler C-10](reference/compiler.md#deviations)), or another route to the same answer.


### Found in the writeup cleanup (session 29, 2026-10-19): the design and the code disagree

Found while writing `design/mechanisms.md` and `intro/` from the code. Each is to decide (design or code) and then align:
1. **Pirates in trait modules:** the prototype refuses any pirate defined in a trait module at the module's definition (`OwnershipError`); the argument ([§3.2](design/argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached)) describes strict mode's refusal of a winning pirate plus a lint; [traits §12.2](reference/traits.md#122-pirates) records the refusal as built, and whether it stays as Open (§1.20). The code is stricter than the design.
2. **Generic implementations' predicates:** the design requires patterns on the constraints' parameters, never computed conditions; a test uses `eltype(R) == Vector{Float64}`; there is no overlap check.
3. **`@implement X T dynamic by f`** (the `Dyn` witness, pointers per session, not in a closed world) still exists in the prototype; [traits §5.9](reference/traits.md#59-dynamic-operations) records it as Open.
4. **`Dynamic{X}` contents:** [traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type) says it holds the user's object ([lowering L-8](reference/lowering.md#18-deviations)); the code keeps a narrowed trait object (`_narrow`), which holds or reads the user's object. What a reader sees is the same; the narrowing should be stated or removed.
5. **In the design, not built:**
   - `Callable{A,S,M,K}` with keywords (the code has three parameters);
   - bounded closures, a `Callable` returning a `Callable`;
   - forwarding for a whole family;
   - the supertrait agreement check;
   - `Dynamic` serialization and a trait's own `==`;
   - inverses listed for AOT.

   The code also caps dynamic calls at 6 arguments and refuses a vararg of `Callable`.
6. **The concreteness levels** are still three macros (`@concrete_only`, `@warn_on_abstract`, `@error_on_abstract`); the single declaration with a level is adopted, not built.
7. **The `{R}` spelling and `project(t) = …`** remain in TraitWorld's own precompile workload and many tests; [state §6.2](state.md#62-the-target) lists them for deletion.
8. **TraitWorld has no README.**
9. **The demonstrators' READMEs** still say `JULIA_TW_VIEWCACHE=0` in their "Running" sections; view caches are deleted.
10. **TraitDifferentialEquations' README** says 10 `RESULT` lines; the session note records 9 on the new compiler: recount.

## 3. TraitWorld (the prototype)

State (2026-10-19): TraitWorld 227781a, 48 test sets, on the patched julia-1.13. It requires the patched build: stock support is dropped. Its own policy is deleted: Julia's compiler compiles trait modules by facts (TraitWorld c533f3a). Contents: [state §6.1](state.md#61-today-2026-10-19).

**Open from session 25:**
- **Trim's own verifier.** `--trim=safe` reports the machinery's slow paths behind the run-time `CLOSED_WORLD` flag, so builds use `unsafe-warn`. To do: make them invisible to trim in a closed build, for example by a constant decided at generation, like `_policy_path()`.
- **`verify_main` walks from `main` only.** Packages' `__init__` functions run at startup too. JLLWrappers' `unique!` needed two entry points by hand in the first binary.
- **Strict mode's prototype checks direct callers only.** Dependence through native code (`return_type` folds, the machinery) is caught only by the safety net (`strict-mode.md` §2b, item 2).
- *(Reworded in s29: piece 11 is moot.)* **Threads:** untested (`design/evidence.md` §5). Julia piece 11 is moot under (B) ([compiler §2](reference/compiler.md#2-mode-and-owner-per-method)). [facts §2.1](reference/facts.md#g1) rests G1 on one exception, values decided by inference (assumption A3 of the old notes), and lists threads as untested; A4 (no method defined while trait code is compiled) was the package interpreter's. Was: "assumption A4 until Julia piece 11 (through 1.13's `CompilerPlugins` hook)."
- **The hunt's C24b:** a harness bug.


**Behind the notes**
2. Which functions keep a trait object is decided once, when the trait module is complete. A method added at the prompt to a callee that keeps does not update its callers' flags; the error in the "results like the input" path is the safety net. Operations on a kept value of a mutable type cost about 900 ns (`keepsum`), mostly the dynamic operation.
3. Field mappings (`name => stored`) work. Agreement of a subtrait's implementation with its supertrait's is not checked.
4. Forwarding for a whole family; named implementations; archetype checks for keyword, vararg and `Callable` workers with declared results.
5. AOT for results like the input: the inverse per user type is not listed for `verify_main`.
6. Concrete mode does not yet trace field types of keys as root causes.
7. Bounds cannot use a method's `where` variables (`f(s::Sampled{T}) where {T}`): such an annotation is read as a plain type. Results through an opened `Dynamic` are not inferred; library code asserts them.
8. Family implementations (`@implement X{T} S{T} where {T}`, and by fields) go through the slow path: a builder per type per session, cached.

**Dependent code**

12. `experiments/world` benchmarks and packages use the old `{R}` spelling, which still works. `experiments/interfaces` (the DataFrames and Makie prototype) uses computed projections and is pinned to TraitWorld before keys.
13. The old `{R}` spelling of traits is still accepted; removing it, and converting the 23 traits in the tests, is phase 4 of the plan (D2, not done in session 23).

**Found by the solvers agent (TraitDifferentialEquations 5f18148, a7d4dfd):**
1. A bound with a `where` variable (`m::ODEModel{T} … where {T}`) is not a trait bound: the method stays plain and never matches. The solver cannot read a model's associated type to promote `u0` (behind-the-notes item 7, now with a demonstrator case).
2. A trait's parameter is not in scope in a default's body (`state(m::M{T}, u0)::Vector{T} = Vector{T}(u0)`: `UndefVarError T`).
4. A `Callable` entry should check, in both modes, that `f` has a method at `A` with a result not disjoint from `S`, and raise a `TraitBoundError` naming them; today the error comes at the first call, and compiled mode first warns misleadingly ("always throws: a fallback").
5. A `Callable` bound's signature must be constant: `Callable{RHSSig{P,T}, …}` with static parameters silently becomes a plain argument (one entry per parameter type needed).
6. `@implement` in the same block as the struct gives a misleading ownership error and suggests wrong syntax.

**Found under (B):** `verify_main` scans code reached from facts code as facts code; an instance reached in both modes is scanned in the first mode met (a limitation).

**From the demonstrators and the order of work:**
1. **A precompile workload for TraitWorld's machinery** ([state §6.3](state.md#63-the-order-of-work); the user's "diagnose, then fix" list of 2026-10-19). The machinery has been compiled by facts since `@machinery` (TraitWorld 624f742). Not built. It goes with the clean-case regression, §4.12.
2. **Found by the demonstrator agents, not fixed yet** (each README's "What TraitWorld should provide" or "TraitWorld issues found"):
   - a generic `convert(::Type{Dynamic{X}}, x)` for every trait; only the method for a trait object exists (`TraitWorld/src/core.jl`); TraitMakie defines three methods per trait instead;
   - forwarding for a whole family (`@implement Positions Live{T} by val where {T}`; behind-the-notes item 4);
   - a bound error that lists the declared implementations;
   - family registries named by `gensym` collide across packages (`TraitWorld/src/implement.jl`, `_family_registry`); the forks advance the counter as a workaround;
   - a family member's result types are checked less strictly than a single type's;
   - `@concrete_only` would refuse `Vector{Union{Missing, Int}}`, the standard column with missing values (not tried).

## 4. Runtime and measurements

3. Not yet measured on 1.13: plain-Julia time to first PNG, ComboCache end to end, an x12 control on 1.12.2 with the pinned TraitWorld.
4. *(Done in session 25 for TraitMakie: 4.07 MB, 0.05 s, the PNG identical to the session's; `aot-under-facts.md` §7.)* The `experiments/world` program (2.09 MB) has not been rebuilt since keys.

**From the performance work** (its review, `reviews/2026-10-19-performance-phase.md`; `design/evidence.md` §5; [state §6.3](state.md#63-the-order-of-work)). The user's order (2026-10-19): diagnose, then fix, then acceptance checks.

*Not diagnosed:*

10. **Upstream CSV + DataFrames pay about 990 ms after the loads under `all`** (plain Julia 4.0 s). Diagnosed (2026-10-19, `experiments/factscompiler/step0/`): the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails). Ideas: keep the plain answers in package images (they are only types); answer `return_type` from facts in more cases where the facts mode's answer provably equals plain inference's. One residue of this kind is diagnosed (TraitReport): StatsBase loads SparseArrays, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`; a standard library counts as Julia's own code, so this is a stakeholder's change, not a pirate, and the facts mode follows it by design (`design/evidence.md` §1; §1.19). Wanted: a full list of what is lost or compiled, naming the winning methods.
11. **TraitDifferentialEquations' new callback closure after the loads:** 171 ms, against 12 ms without loads (24 ms in an earlier run). One run per order (*n = 1*). Not diagnosed (`design/evidence.md` §3).
12. **A clean-case regression of `@implement`:** TraitMakie's forwarding `@implement` took 36 ms and its first PNG 40 ms before the performance phase; now 77 ms and 107 ms without loads. Probably the cost of compiling TraitWorld's machinery by facts (`@machinery`), not yet measured by owner. Wanted: what a clean `@implement` compiles, by owner. The fix may be the machinery workload (§3, "New in session 29", item 1).

*To rerun:*

13. **Reruns on the current compiler** (julia-1.13 61852d8fb1 or later):
    - Python's baseline for TraitReport (session 27: 0.58–0.69 s; its virtual environment was lost from `/tmp`);
    - TraitReport form (t) under loads, like for like with session 27's form (t) (session 29 measured form (b) under loads);
    - the forks' session harness after the `String15` fixes (its `String15` step, 1.56–1.67 s, predates them);
    - BaseBenchmarks under `all` (last run in session 28, before parts B–D; the inliner changes apply under `all` too);
    - Base's test suite under the facts mode, to the end (§1.13).

*Tests:*

14. **Acceptance checks for the session-29 changes** (`design/julia-changes.md` §5): the two inliner changes (a varargs wrapper in a recursion; cycle members inlining each other), the compiler-plain edges (§2.27), and held views.

## 4b. The review of session 23

Still open from `reviews/2026-10-16-wrapping-under-keys.md` (triaged in session 25; the fixed and dissolved findings are under Closed items):
- **F3:** family implementations over Base's abstract types, and later methods by the members' owners. Since session 24, implementations are decided in the caller's world and cached per world (G1.13), which may settle it; an acceptance case is needed.
- **F9:** the walk of abstract parts at the entry against the reference layout.
- **F11:** stale statements, to go with the rewrite of the notes.
- **Its decision 4** (who declares an implementation for a foreign type) still stands without wrappers: the trait owner's package extension, as the prototype does.

What Julia must provide, in order: `explorations/julia-support.md`, reviewed in session 25.

## 5. Documents

1. `explorations/makie-rewrite.md` and `explorations/solvers.md` were written with representations and projections. Their trait sketches are to be read with keys (each has a banner); the demonstrators' code (TraitDifferentialEquations, TraitMakie step 1) now shows the keys form.
2. `design-findings.md` is the evidence log in session order. Sections 3, 7, 9–12 and 14 describe earlier forms of the design (its status header says which sections are current).
3. The live Claude Doc is frozen at revision 1146; its export is in `attic/writeup/`.

---

## Closed items

Closed, decided or superseded items, under their numbers, with how and where each was closed. The designs they concern are explained in [`design/alternatives.md`](design/alternatives.md).

### §1

Raised in session 26 (new trait code after big loads; analysis in session note 26 and §4.5); decided by the user in session 26: §1.3 the policy in the platform, as a prototype; §1.4 option (a), with (b) recorded as an alternative design and an experiment to run later (`decisions.md`):
3. **Closed (s29):** superseded. The facts policy is a mode of Julia's own compiler, parts (A)–(C) (julia-1.13 880ae49dad, c3415abde6). TraitWorld's own policy and its interpreter code are deleted (TraitWorld c533f3a). The checks use Julia's `NativeInterpreter`, run in the compiler's world (julia-1.13 bb82a82bbf, TraitWorld f79727c). So no package defines the interpreter that REPL's could break. Recorded in `design/julia-changes.md` §1–2. *(Prototype built in session 26, `experiments/sysimage`: TraitWorld in the patched system image. REPL first, a new key's first call 0.22 s instead of 5.9 s. TraitReport's work after OffsetArrays, StatsBase and Unitful 1.7 s instead of 5.4 s. Startup 0.125 s against 0.10 s. Open: the demonstrators' rows on it, and the cleaner form of the policy in Julia's Compiler.)* **Where the policy's compiler code lives.** Julia's Compiler keeps the interpreter in an abstract field (`InferenceState.interp::AbstractInterpreter`), so the compiler code TraitWorld's image holds for `FactsInterp` has abstract edges such as `cache_owner(::AbstractInterpreter)`. Any package that defines its own interpreter breaks them. REPL defines one (`REPLCompletions.REPLInterpreter`), and in an interactive session REPL loads before TraitWorld, so the image's compiler code fails validation and the first new key costs 5.9 s instead of 0.13 s. GPUCompiler, Enzyme, JET and Cthulhu define interpreters too. Julia's own compiler avoids this by running in `jl_typeinf_world`, frozen at the system image. **Recommendation:** the future state, with the facts policy as part of the platform, compiled into the system image and run in a frozen compiler world like Julia's own. A prototype is a system image of the patched build with TraitWorld in it, measured against the REPL case. A workaround, not recommended: TraitWorld depends on REPL, which fixes REPL but not the other interpreters.
4. **Closed (s29):** option (a) was dropped in session 27 (item 7). Option (b) is built as part (C): run-time sites in facts code run facts code (julia-1.13 c3415abde6). The machinery's slow paths are compiled by facts (`@machinery`, TraitWorld 624f742). A new model type's `@implement` now takes 142–164 ms in every load order (`design/evidence.md` §3). **Run-time sites in the machinery's code.** Under the policy, a call at abstract argument types dispatches at run time into *native* code. For the machinery's own internal functions (`_analyze_keeps`, `_implement_oneline`, …), that native code is invalidated by large loads, so `@implement` still takes 1.2–1.5 s after CSV, DataFrames and CairoMakie (0.64 s without). Options:
   - *(Adopted and implemented in session 26, scoped to calls within the caller's own package: TraitWorld 6bcca9f. `@implement` 0.09–0.21 s without loads, about 0.52 s after.)*
   - **(a) a rule refinement:** a call at abstract argument types of a function that is not `public` in its owner's module is a fact, since only the owner adds methods to its internal functions, and extending another package's non-public function counts as piracy. This uses Julia's own `public` declarations. Recommended: it reflects how an ecosystem with declared public APIs would work, and it is small.
   - **(b) run-time dispatch under the policy:** a run-time site looks up and invokes the policy's code for the run-time types (a Julia piece: dispatch under a cache owner). It would also protect ordinary code reached dynamically, Makie's for example, but it changes "run-time sites behave as plain Julia" and costs per call.

Raised in session 27, from the fresh-eye consistency review (`reviews/2026-10-17-consistency-fresh-eye.md`; the user asked for the review and for work to continue without questions, so these waited):
5. *(Decided in session 27: opt-in per trait, `@concrete_only` / `@warn_on_abstract`; implemented, decisions.md.)* **Concreteness: opt-in or required?** The notes and the register say opt-in per trait; the prototype requires it for every trait and checks every field of the implementing type, declared or not (review §1). Options: (a) required by default with a per-trait opt-out, matching the prototype and pay-off 3 as stated; (b) opt-in as written, then implemented, with the check narrowed to the key. Either way the sentence "a `DataFrame` cannot conform, since it is not deeply concrete" (TraitReport README, decisions "TraitTables and TraitCSV") states a prototype limit; session 27 measured the independent rationale: column code on `Vector{AbstractVector}` loses compiled code to loads (PlainTables loses 17 of 49 methods), `Vector{Dynamic{Column}}` loses none (TraitReport README, "Form (t)"). *Recommendation:* (b), since nothing in the facts proofs needs concreteness and abstract keys are sound as run-time sites; pay-off 3 then reads "for traits that require it".
6. *(Decided in session 27, the text corrected; decisions.md.)* **Stakeholders and Lemma O** (review §2): the notes define stakeholders so that methods on abstract types count as pirates; strict mode and the prototype use method-signature ownership. Restate Lemma O and Theorem 2 with supertype owners as stakeholders, and name the exception: package extensions triggered by unrelated packages.
7. *(Decided in session 27: dropped; acceptance 16/16; decisions.md.)* **Facts at non-public functions** (review §3; also item 3 of session 26's "Next"): the rule is in no note, breaks Theorem 2's premise as stated, and the scoping to the caller's package still records Base-internal calls from Base code as facts. Options: amend rule 3 (extending another package's non-public function is piracy) and exclude Julia's own modules from the rule; or confine the rule to TraitWorld's machinery. *Evidence (session 27):* acceptance check G2.1 fails with the rule on and passes with it off (`JULIA_TW_INTERNAL_FACTS=0`): a module that owns a type extends another module's non-public function called on type values, and the trait code is invalidated. Under the decision's amended rule 3 that module is a pirate, and the invalidation is the pirate being followed; under rule 3 as the notes state it, it is a G2 failure.
8. *(Decided in session 27: refused, the keys design; family members fixed at first use; restart for interactive changes; decisions.md.)* **Overrides after a conformance** (review §4): "refused" (4-details "Declaring a trait", the keys design, `check_overrides`) against "a fact that recompiles to the new method" (rule P, wrapping by facts). Options: drop the refusal under rule P, or keep it as a declared-API rule with a corrected justification.

The review's minor findings (stale lines, numbers that disagree, "the policy is package code" against the adopted "policy in the platform") are document fixes, listed in its "Minor" section and in §5.

(Conversions in trait wrappers dissolved with wrapping by facts, s23.)

(Session 23 settled the runtime as methods and D1–D9: session note 23, `decisions.md`.)

Raised in session 29, from the three reviews of 2026-10-18. **Decided by the user** (`decisions.md`): strict mode first for the framing; `all` a test bed; stock-Julia support dropped; `Dynamic` in the compiler directly; the forks paused; slowdowns tolerated if a trait redesign recovers them. Closed since:
9. **Closed (s29):** *(Closed in session 29: P-a is moot. `all` is a test bed, so (B) is needed regardless of BaseBenchmarks; the principle governs trait code and the plain code it reaches; decisions.md "Session 29, continued", change 9.)* **The slowdown principle and plan P-a.** Whether the principle replaces the numeric threshold of the plan's go/no-go rule (≤ 5% mean, no group above 20%), as `decisions.md` reads it, and which tails must be shown recoverable (containers of `Any`, abstract element types, `io` 1.32).
11. **Closed (s29):** the second half too. (D) is built, so the machinery is not on the path of a `Dynamic` operation, and `sealed_call` is gone (julia-1.13 f6838f96fc, TraitWorld 703f814). The machinery is compiled by facts through Julia's per-method mode (`@machinery`, TraitWorld 624f742), not exempted by module name. Strict mode protects `:facts` code (TraitWorld 3db6592). Recorded in [compiler §2](reference/compiler.md#2-mode-and-owner-per-method) and [state §6.1](state.md#61-today-2026-10-19). *(Half closed in session 29: under (B), strict mode protects facts-owned code, as `strict.jl:52–57` does; one owner exists only in the `all` test bed. Open: the machinery's exemption, which goes with (D), see §2.26.)* **Strict mode and TraitWorld's exemption under one owner** (design review, finding 3): which code strict mode protects when there is no foreign owner, and how the machinery is compiled without the `sealed_call` exemption by module name (sealing by another name, §2.26).
12. **Closed (s29):** witness tables are deleted. `Dynamic` operations are call-site splits in the compiler, part (D) (TraitWorld 3db6592 dropped the tables; julia-1.13 f6838f96fc, TraitWorld 703f814). The split dispatches in the caller's world. Recorded in [traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type) and [facts §9](reference/facts.md#dynamic-split). *(Decided in session 29: witness tables off by default, `JULIA_TW_WITNESS=1` turns them on; the defect goes with `Dynamic` in the compiler.)* **The witness-table world-age defect** (design review, finding 2, verified): in an older world after an implementation is redefined, a `Dynamic` call through a witness table returns the new method's result. The package keeps it until `Dynamic` moves to the compiler; whether to turn witness tables off by default (`JULIA_TW_WITNESS=0`) meanwhile.
14. **Closed (s29):** written into the design, not reverted. [facts §3](reference/facts.md#facts-and-fact-signatures) defines a fact signature with the tuple splits (1.8). It says that run-time sites in facts code run facts code (1.1, part C). It replaces the fold on Base's asserted effects (1.2) by "no asserted effect applies to a frame with a run-time site" (julia-1.13 67f5c0bcc8). Decisions: `decisions.md` "Session 29, continued", change 10, and "Session 29, the compiler as built". The notes 1–4 go to the attic instead of being rewritten (`plans/2026-10-19-notes-cleanup-plan.md`). **The session-28 rule changes** (lessons 1.1 run-time sites run policy code, 1.2 folds on Base's asserted effects, 1.8 tuple-split facts): written into the notes, or reverted (design review, finding 5).

Decided by the user on 2026-10-20 (`record/decisions.md`):
10. **Closed (2026-10-20):** the extension rule is decided (the user: "Extension method probably should be followed? But with warning?"). A package extension's method that wins at a fact of trait code without mentioning its triggers' types is followed, as its parent package's change, a stakeholder's; in strict mode a warning names the method and the trait code it affects ([traits §12.3](reference/traits.md#123-strict-mode), [facts §2.2](reference/facts.md#g2), [§10.3](reference/facts.md#strict-intended)). Today it is followed silently ([facts F-14](reference/facts.md#deviations)). This also answers "whether a parent's own extension may override its parent's method": it is its parent's change. The item's other parts, unchanged, are in item 1: Julia pieces 15, 14 and 1′ in the first upstream proposal, `twolibs`, bindings, the session as owner at the prompt, strict mode measured under `all`. Was: "**What strict mode first commits to** (framing review §5.4): Julia pieces 15 (image-validation report), 14 (transitive check) and 1′ (deletion hook), which must join the first upstream proposal; `twolibs` in the acceptance suite; whether a parent's own extension may override its parent's method; bindings as something a pirate can change (no hook exists); the session as owner at the prompt; strict mode measured under `all` (837 pirates by the letter in g2strict, none refused, Base's facts not yet checked)."

- **`Callable` in `DynamicCall` mode runs in the latest world** (closed 2026-10-19: the calling convention `:caller_world`, piece 18; acceptance G1.20 and G1.21 pass. Was: `TraitWorld/src/core.jl:705`, a `@cfunction` pointer). After a redefinition, a call in an older world computes the new method's result (101 against plain Julia's 2). A violation of "identical or error" of the witness tables' kind. Fix: the world-checked call-site cache ([compiler §3](reference/compiler.md#3-world-checked-caches-at-dynamic-boundaries)), or a pointer checked against its world range at each call.

### §2

- **Facts code behind `jl_apply`** (closed 2026-10-20, decided): a dispatch through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs the callee's default owner's code. A trait module's method's default owner is the facts owner, so trait code reached this way is code compiled by facts; a neutral method runs its plain code, which is not trait code, so trait code is never invalidated through this path. This needs no reliance on the runtime's internals. Implemented as built; facts F-3 is retired ([facts §5](reference/facts.md#run-time-sites); [compiler §2.5](reference/compiler.md#25-dispatch-from-facts-code)). Was: "Dispatch through the runtime's `jl_apply` … runs the default owner's code, so plain code for neutral methods in the product setting. Whether every way facts code dispatches should run facts code."

26. **Closed (s29):** both questions are answered by part (D) (julia-1.13 f6838f96fc, TraitWorld 703f814). The machinery is not on the path of a `Dynamic` operation, and `sealed_call` is gone. The `isa` branches come from the call-site split: an operation on a `Dynamic` value branches over the registered conformances (at most four) and falls back to a dynamic call. Witness tables are deleted. Recorded in [traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type), [§12.4](reference/traits.md#124-no-sealing) and [facts §9](reference/facts.md#dynamic-split). **No sealing, of abstract types or functions** (user, session 28; to think about later). The facts-mode recovery test (`plans/2026-10-17-policy-in-compiler-plan.md` §3) suggested sealed abstract types and sealed functions, so that calls at abstract types become facts. The user's view: this notion should leave the project entirely. One should not seal an abstract type but use a trait instead: the trait's declared signatures and result types, checked for every conformance, are the closed contract. To settle:
    - *(Answered in session 29 by `Dynamic` in the compiler: with the call-site split (D) in the caller, the machinery is not on the path of a `Dynamic` operation, and `sealed_call` goes.)* how TraitWorld's own machinery is exempted under the facts mode in the compiler without a "sealed" notion (the prototype's `sealed_call` names TraitWorld's functions);
    - what replaces the `isa` branches plain Julia emits over a known set of methods, once the call goes through `Dynamic` with witness tables.

### §3

History, the state of TraitWorld in session 25:
History, state (session 25): `main` at 893f0bb, 343 tests on the patched 1.13.2 build (308 on stock, where strict mode's 32 tests and the hook tests are skipped).
- **In:** the compiler policy of wrapping by facts, strict mode as a prototype, `verify_main` with dynamic values' targets, the closed-build replacement of the policy's call.
- **Removed:** wrappers, sealing, the filter, doors, layering, the native piracy audit and guard.
- **Earlier:** the runtime as methods, keys in the reference layout, overrides refused at checkpoints (session note 23).

From "Open from session 25":
- **Closed (s29):** new trait code costs about the same in every load order. A new model type in TraitDifferentialEquations: `@implement` 142–164 ms, first solve 82–133 ms. A new data type in TraitMakie: 77–97 ms, first PNG 89–161 ms. Measured as these rows, not as session 25's small module (`design/evidence.md` §3). The fixes: the machinery compiled by facts (TraitWorld 624f742), the compiler's own code plain whoever calls it (julia-1.13 c4f7e76a2f), the checks on the native interpreter in the compiler's world (julia-1.13 bb82a82bbf, TraitWorld f79727c). **New trait code after big loads:** 2.7 s to define a small module, against 1.0 s; the checks' recursion (Julia pieces 7 and 12, or a walk without recursion).

From "Behind the notes":
1. **Closed (s29):** stock support is dropped (`decisions.md` "Session 29"). On the patched build, piece 1's definition hook refuses the override when the method is defined (`TraitWorld/src/hooks.jl`, `_override_violation`). The checkpoint `check_overrides` remains. Overrides after a conformance are refused at checkpoints (declarations, a trait module's end, a signature's first call), not when the method is defined: that needs a hook at method insertion.

**Performance**

9. **Closed (s29)** as a measurement: re-measured on the facts compiler. Typed calls 36–38 ns against 33.8–34.5 ns for the same loop with `len` an argument. The old 30 ns used a literal `16`, which unrolls the loop. Untyped calls 115–129 ns against about 55 ns for a plain untyped call (`design/evidence.md` §2). The untyped cost is accepted: type-unstable code was never claimed fast (`design/performance.md`, "Costs that remain"). Typed calls cost 33 ns against 30 ns for plain Julia (`total(t, 16)`), without allocation. Untyped calls (the caller does not know the argument's type) cost 105–117 ns and 64 bytes (270–295 ns before TraitWorld 5efbb4c: the entry built the tuples for a result like the input on every call). What remains is two dynamic calls (`enter`, `checked_call`), the boxed trait object and the boxed result; removing them would compile part of the entry per user type.
10. **Closed (s29):** the piracy guard was removed in session 25, and rule 4 is gone ([design §4](design.md#4-the-rules)). The first-call check (`worker_problems`) now reflects a worker by facts inference, the code that runs, shared with its compilation and kept in images (TraitWorld 93c8a08). The forks' first `String15` read went from 1.74 s to 0.04 s. That gain is shared with a workload extension (forks 9d512a1); the two were not separated (`design/evidence.md` §3). A worker that has not been called in a session runs `_check_once` and the piracy guard at its first call; after any world change the guard audits the signature again (the PoC's stand-in for rule 4), which costs tens to hundreds of milliseconds after large loads.
11. **Closed (s29):** measured. TraitMakie's forwarding `@implement` in a fresh process: 77 ms without loads, 96–97 ms with them (`design/evidence.md` §3, *n = 1*). This is slower than the 36 ms measured earlier in session 29: see §4.12. A fresh session's `@implement` of a forwarding type: not re-measured since the rewrite (it was about 470 ms).

**Session 27, prototype gap:** **Closed (s29):** the policy's `invoke` of a CodeInstance is gone with the policy (TraitWorld c533f3a). `verify_main` now scans `:facts` code by owner, and code reached from facts code as facts code (TraitWorld 3db6592). TraitMakie's row 5 (dispatch targets) has not been measured since. `verify_main` in a session does not scan the workers behind the policy's `invoke` of a CodeInstance (it counts them as static calls), so it lists no trait sites or targets there; only a trimmed build, which compiles the plain calls, shows them. TraitMakie row 5 waits for it.

From "Found by the solvers agent":
3. **Closed (s29):** a conformance that implements no required operation now lists each one with its declared signature at the type, and the type's methods of it; the `project(t) = …` advice is gone (TraitWorld 3ba6c05). TraitDifferentialEquations' two broken tests for this pass (TraitDifferentialEquations 62e9fa4). `ImplementError` messages: a missing operation or a wrong argument type names neither the operation nor its declared signature; the text still says `project(t) = …` and "representation". Wanted: "`rhs!` has no method for Tuple{…}; existing: …".

**Session 29, found under (B):** **Closed (s29), except the limitation in the last sentence:** fixed in TraitWorld 3db6592. TraitWorld's machinery read the user's object as `Any` through generic helpers (`_loadpart(::Type, ::Any, ::Slot)`): run-time sites under facts, hidden before by `sealed_call`. Fixed: the helpers take the view. `verify_main` now scans code reached from facts code as facts code; an instance reached in both modes is scanned in the first mode met (a limitation).

### §4

1. **Closed (s29):** superseded. View caches are deleted (`viewcache.jl`, TraitWorld c533f3a), and stock support is dropped. With a view cache on stock 1.13.2, `summarize` recompiles for 71–74 ms once CSV and Makie are loaded (3.3 ms in session 21 on 1.12). It is unclear whether 1.13 or TraitWorld causes this (`experiments/baseline-1.13.md`).
2. *(Resolved by wrapping by facts, session 24: with nothing skipped, 0 facts-owned CodeInstances are lost to any of twelve loads, in any order; `wrapping-by-facts.md` §Validation. Kept for the record.)* The patched 1.13.2 build exists (`julia-1.13/`). Its filter protects code from a definition only if the definer owns no type in the code's signature (review F1, fixed in 280612ed2f; before, a user's redefinition of its own implementation left the worker stale). Measured with it (session note 23): CSV and DataFrames loaded after TraitMakie invalidate no PlotCore code and 14 machinery methods (285 on stock). CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations still invalidate 2–4 ODECore methods and 323 machinery methods: these loads bring pirates of Base (OffsetArrays, StatsBase, Durations), which invalidate by design, and owned methods (InlineStrings, Unitful) that reach Base methods compiled for trait-world callers, which the insertion half does not protect (the load half's callee rule has no insertion counterpart). A pirate-free load set is needed to separate the two.
5. **Closed (s29):** both causes are gone, and new trait code costs about the same in every load order (§3, "Open from session 25"). Cause (i): the policy's compiler code is deleted; the checks run Julia's native compiler in the compiler's world (julia-1.13 bb82a82bbf, TraitWorld f79727c). Cause (ii): the machinery's slow paths are compiled by facts (TraitWorld 624f742), and the compiler's own code stays plain (julia-1.13 c4f7e76a2f). Numbers: `design/evidence.md` §3. *(Resolved in session 24: TraitDifferentialEquations' first solve 55–60 ms and TraitMakie's first PNG 89–97 ms in every load order. Open in its place: **new** trait code defined after big loads, 2.7 s to define a small module and 0.8 s for its first call, against 1.0 s and 0.09 s; the definition-time checks, Julia pieces 7 and 12.)* **Session 26, two causes found:**
   - **(i) The policy's compiler code** fails validation at load when an interpreter-defining package, REPL in every interactive session, loads before TraitWorld: a new key's first call 5.9 s instead of 0.13 s (decision §1.3).
   - **(ii) The machinery's internal functions** are native code that large loads invalidate: `@implement` 1.2–1.7 s after loads, 0.6 s without (decision §1.4). Moving `@implement`'s expansion and checks under the policy (TraitWorld a5e4778) gained little, because their run-time sites reach native internal functions.

   Earlier measurements: Before: TraitDifferentialEquations' first solve takes 0.7–1.05 s with CSV, DataFrames and CairoMakie loaded (73 ms without); TraitMakie's first PNG takes 0.31–0.37 s with CSV and DataFrames before (0.1–0.2 s without; 0.09 s after, patched).
6. *(Fixed in session 26: Julia's type-printer registry, db82407fa6; TraitWorld 6239b1e.)* **TraitWorld invalidates ordinary code** (session 26, TraitReport row 4). `Base.show(io::IO, T::Type{<:CObj})` and `Base.show(io::IO, T::Type{<:TObj})` (`TraitWorld/src/core.jl`) are no pirates, but they invalidate every caller compiled for `show(::IO, ::Type)`: CSV's `parsecolchunk!`, Base's `temp_cleanup_atexit` and others. That costs 1.0 s on CSV's first read with DataFrames loaded. Without the two methods: 2.64 s against 3.6 s. Fix: print trait objects' types another way. The general point: a trait package's own methods of Base functions at abstract signatures widen what plain code compiled, so they need the same care as any package's.
7. *(Fixed in session 26, TraitWorld 29f0a8e. The cause was not piece 5: TraitWorld's load hooks and package callback were native code, invalidated by the loads they watch and compiled again four times per load. They run under the policy now. `using TraitReport`: 0.79–0.82 s patched, 0.71–0.72 s stock.)* **The patched build's images load slowly** (session 26, TraitReport row 5): `using TraitMakie` takes 0.69 s patched against 0.23 s stock, and CSV, DataFrames, Statistics and TraitMakie together take 1.40 s against 0.82 s. Suspects: native code for foreign CodeInstances (piece 5), the verification of owner-aware edges (piece 9), the facts' validation at load. Not profiled yet.
8. *(Fixed in session 26, TraitWorld 6239b1e: under the policy the view cache is on only with piece 5, and its exit hook is registered only when something new is noted.)* **The view cache flushes at every exit** (session 26, TraitReport row 6): 0.14 s with TraitMakie alone, also when nothing new was compiled. It is still on by default (`JULIA_TW_VIEWCACHE`).
9. *(Form (b) measured in session 26: the report's work takes 60 ms on the patched build with DataFrames and InlineStrings loaded; nothing of CSV's read path is recompiled.)* **Plain Julia's invalidation in TraitReport form (a):** DataFrames loads InlineStrings, which activates `CSVInlineStringsExt`. Its methods of CSV's own functions invalidate CSV's precompiled read path in either load order: `CSV.File` takes 0.19 s with CSV alone, 2.46–2.53 s with DataFrames. Form (b) tests whether the facts policy removes this (prediction: yes, for a numeric file). Worth reporting to CSV upstream (the extension has no workload); not our workaround to make.

**Session 27, Julia piece 11 deferred:** **Closed (s29):** piece 11 is moot under (B) (`decisions.md`, session 27 row "Julia piece 11"; [compiler §1.5](reference/compiler.md#15-effects)). How asserted effects meet run-time sites is decided: no asserted effect applies to a frame with a run-time site (julia-1.13 67f5c0bcc8; acceptance G1.10, G1.19). Two obstacles (`explorations/julia-support.md`, last section): 1.13's `typeinf_edge` cannot join a policy frame to a native caller's stack (so the replacement runs the owner's inference synchronously), and the barrier for asserted effects over run-time sites (G1.10) has no place in the plugin replacement. Needs a decision on how asserted effects meet run-time sites.

### §4b, the review of session 23

Triage after wrapping by facts (session 25) of `reviews/2026-10-16-wrapping-under-keys.md`:
- **Fixed:** F1.
- **Dissolved:** F2 (implementations in ordinary modules have no place in the layering: there is no layering for calls), F4 and F8 (sealing), F5 (the wrapper's role for foreign types: there are no wrappers), F6 (results from above with a trait bound: `Dynamic{X}`, adopted), F7 (opaque values handed down: trait code may pass any value to any code), F10 (automatic differentiation: ForwardDiff's own `Dual`, session 24).

### §5

5. **Closed (s29):** superseded. `design.md` is the consolidated current design (design repository 562c06f, which also marked the register's retired rows as history). It states the policy in the compiler and strict mode as a prototype. Notes 1–4 go to the attic rather than being fixed line by line (`plans/2026-10-19-notes-cleanup-plan.md`). The fresh-eye review's minor findings (`reviews/2026-10-17-consistency-fresh-eye.md`, "Minor"): stale lines in `2-design-choices.md` outside its banner, register rows 19, 20, 69, 91, numbers that disagree between documents, "the policy is package code" (1-overview, 3-wrapping) against the adopted "policy in the platform", strict mode "not built" against its prototype.
4. **Closed (s29):** superseded. [`record/decisions.md`](record/decisions.md) states the adopted rule (tags labelled by the primal signature, implemented in TraitDifferentialEquations), and `notes/1-overview.md` goes to the attic (`plans/2026-10-19-notes-cleanup-plan.md`). The gradient rows are measured: a second loss 17–18 ms in every load order (`design/evidence.md` §3). `notes/1-overview.md` ("Fields as the key") says a new loss under automatic differentiation "compiles the step again, as today". The adopted decision labels tags by the loss's primal signature (`Tag{Sig{A, S}, V}`), so that a second loss of the same signature compiles nothing; the sentence holds only without it. Fix when TraitDifferentialEquations row 5 is built (review of session 26).
