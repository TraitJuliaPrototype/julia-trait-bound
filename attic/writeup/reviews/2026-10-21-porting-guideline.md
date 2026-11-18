# Review: the porting guideline, rewritten for the NetworkDynamics port, 2026-10-21

A fresh-eyes review of [`../intro/porting.md`](../intro/porting.md) as rewritten for W-32 (part P0 of [the meta plan](../plans/2026-10-21-networkdynamics-port.md)), uncommitted on top of 5bb75aa (545 lines; `git diff writeup/intro/porting.md`).

**Method.** Read the guideline against the references (`writeup/reference/traits.md`, `facts.md`, `lowering.md`, `compiler.md`), TraitWorld's source at e9f4bfe (`src/trait_module.jl`, `implement.jl`, `ownership.jl`, `strict.jl`, `TraitWorld.jl`), the demonstrators' sources the examples quote (TraitDifferentialEquations, TraitMakie, TraitTables, TraitCSV, `forks/`), the evidence and open issues it cites, and the clones in `ndport/pkgs/`. Every link and anchor was checked; all resolve. No Julia was run. "Verified" means read in code; "reasoning" marks an inference.

**Verdict.** The rewrite is a large improvement: the one-screen table, the deviations a port meets, and Part 0 give a porter an orientation the old version lacked, and almost every example matches its source. Four statements are wrong (findings 1–4), one of them the first thing a function-at-a-time port meets. Part 0 is not yet actionable for *this* port: it does not say how to make an unchanged package a trait module, or what that will refuse in SciML (findings 9–10), and it misses the informal-interface pattern that gives the biggest gain for the fewest changes (finding 11). The document states several rules three times (Part 0, Part A, "Proposed for part A") and copies numbers that belong to the evidence (findings 18–20). It can lose about 120 lines without losing content (finding 25).

Severities: **wrong** (a statement that is false, or a dangling source), **should fix** (misleading, missing for the port, or against CLAUDE.md), **minor**.

---

## A. Correctness

### 1. "Upstream's methods and the port's can stand side by side" is false for untyped upstream methods (wrong; verified)

Line 133. TraitWorld refuses a bounded method when the function already has an untyped method of the shape its entry needs: "`f` already has an untyped method of the shape its trait-bounded method needs for an entry; define the trait-bounded methods first, then the untyped fallback" (`TraitWorld/src/trait_module.jl:824`–`826`). An untyped method defined after the entry and replacing it raises `TraitBoundError` (`:1058`–`1068`). And only the function's owner may add a bounded method of a shape the function has none of yet (`:827`–`829`). This is [lowering L-3](../reference/lowering.md#18-deviations); traits §5.5's status line names it. Untyped methods of the same shape are common in the packages to port (`solve(prob, args...; kwargs...)`-style front ends, `f(x)` fallbacks), so this is the first deviation a function-at-a-time port meets, and the guideline's deviation list (lines 54–60) omits it.

Fix. Replace

> Upstream's methods and the port's can stand side by side.

with

> Upstream's typed methods and the port's bounded ones stand side by side. An untyped method of the same shape does not, today ([lowering L-3](../reference/lowering.md#18-deviations)): the bounded methods must be defined before it, in the source order, and only the function's owner may add a bounded method of a shape the function has none of yet. So a port adds the bounded method in the package that owns the function, above upstream's untyped method.

and add to the list at line 54:

> - an untyped method must come after the bounded methods of its shape, and only the function's owner may add a bounded method of a new shape ([lowering L-3](../reference/lowering.md#18-deviations)): define the bounded method first, in the owner's package;

### 2. "about 100 ns per element" has no source (wrong; verified)

Line 159: "Making `Dynamic{X}(x)` per element in plain code, at a run-time site, costs about 100 ns per element ([open issues §2](../open-issues.md#2-design), item 31)." Item 31 gives 157 ns (the review's figure) and 5 ns since the branch `basetraits` (E-134); "100 ns" appears nowhere else in the repository outside this line and an unrelated plan. The number is neither current nor sourced.

Fix. Replace the second sentence with

> A copy into `Vector{Dynamic{X}}` costs a pass and loses aliasing; the view over the user's container costs none within the split's four implementations ([evidence §2](../design/evidence.md#2-run-time), "idiomatic loops over heterogeneous containers", E-134, E-143, E-144).

### 3. The `convert` boilerplate cites an open issue that does not exist, and contradicts the document's own rule (wrong; verified)

Line 466: "Four methods per trait is clumsy, and they name TraitWorld's own types for trait objects and casts ([open issues §3](../open-issues.md#3-traitworld-the-prototype))." Open issues §3 has no item on these methods (searched for `convert`, `Kept`, `CompiledFor`). And line 32 tells the porter "Write to TraitWorld's language, never to its internals": the four methods (`TraitMakie/src/TraitMakie.jl:73`–`76`) name `TObj`, `TraitWorld.CompiledFor` and `TraitWorld.WithDynamic`.

Fix. Open an issue in §3 ("a library's `convert` to `Kept{X}` needs three companion methods that name TraitWorld's internals") and link it by number, or drop the link. State the exception where the rule is: after line 32's sentence add "The one exception today: the companion `convert` methods of B3."

### 4. "`AbstractVector` stay" is attributed to traits §14, which does not say it (wrong; verified)

Line 117: "`Number`, `Real` and `AbstractVector` stay ([§14](../reference/traits.md#14-membership))." §14 says "`Number`, `Real` and `Integer` stay as they are". BaseTraits' `Indexable` exists for what generic code needs from an `AbstractVector` (§8.1), and the user's words in open issue 31 ("`Vector{AbstractType}` is a poor substitute for an Iterable trait") point the other way for containers.

Fix. Replace "`Number`, `Real` and `AbstractVector` stay" with "`Number`, `Real` and `Integer` stay". If the intent is that an abstract array type stays where a package dispatches on it, say that as a port's observation in Part B, not as §14's rule.

### 5. Code that trait code reaches is compiled by facts: all of it, not only Base's; and "keep plain" does not keep it plain (should fix; verified)

Line 81: "**Base's code that trait code reaches is compiled by facts too,** in the product setting." The rule is wider: every neutral method reached from the facts owner is compiled by facts ([facts §6.2](../reference/facts.md#the-mode-rule), the table; [lowering §2](../reference/lowering.md#2-modes-owners-and-images), "what a worker calls … Base"). So Observables, Graphs or any package a trait module calls is compiled by facts on that path. Two consequences the guideline gets wrong by omission:
- 0.5 and A5 say to keep notification graphs, callbacks and bookkeeping plain. Keeping them out of a trait module keeps them plain only for plain callers. Called from trait code, `notify` and the `Observable{Any}` reads inside it are compiled by facts, with run-time sites.
- B3's "`onchange` is plain" holds because TraitMakie's trait code never calls it.

Fix. Replace the bold lead of line 81 with "**Code that trait code reaches is compiled by facts too, whoever owns it** (Base's, and every package's), in the product setting." Add to 0.5: "Plain means: not in a trait module. A plain function that trait code calls is compiled by facts on that path ([facts §6.2](../reference/facts.md#the-mode-rule)); keep it plain only where trait code does not call it, or make it fully typed."

### 6. The mechanism of the slowdown is stated too narrowly (minor)

Line 80: "inline a callee that has one method, and type its result." Plain Julia speculates over every method that matches today, up to `max_methods`, and takes their result types, inlines and evaluates at compile time ([facts §4.2](../reference/facts.md#inferred-across-a-call)). Replace with "speculate over the methods that match today (up to `max_methods`): type the result from them, inline them, evaluate them at compile time."

### 7. Line 86 asks for a product-setting run of an unchanged package, which line 83 says gains nothing (should fix)

Line 83: "In the product setting, an unchanged package gains nothing." Line 86: "run the package's workload upstream, in the product setting, and under `all`." Run as written, the second run measures the first again. The plan's P3 means the package wrapped as a trait module (meta plan, P3: "as trait modules, and under `all`").

Fix. Replace with "run the package's workload three ways: upstream on the patched Julia; with the package's code wrapped as a trait module (0.1a), in the product setting; and unchanged under `all`."

### 8. Smaller correctness points (minor)

- Line 321: the quoted line omits the assertion its source has and rule A9 asks for. Source (`TraitCSV/src/CSVCore.jl:124`): `col = fillcolumn(compiled_for(emptylike(c)), s, spans[k])::Union{Nothing,Dynamic{Column}}`. Quote it so.
- Line 420: "One parameter bounded by a tuple of `Callable`s is Planned ([§3.7], W-30)." The language item is W-29; W-30 is TDE adopting it. Write "(§3.7, W-29; TDE adopts it in W-30)".
- Line 136: "`@implement X T` in a package compiles ahead the bounded functions `T` needs." Add "with one trait position and concrete other arguments; not varargs or several trait positions ([§13](../reference/traits.md#13-compiling-ahead), [lowering L-15](../reference/lowering.md#18-deviations))."
- Line 62: "tuples of traits outside bounds, `@implement` and supertrait lists" reads as if `@implement` and supertrait lists were Planned. Write "tuples of traits anywhere but bounds, `@implement` and supertrait lists".
- Line 332: "The upstream suites of all three pass" is a present-tense status from forks 8c6366a, session 29, on an earlier compiler; the forks are paused. Write "passed at forks 8c6366a ([`forks/README.md`], "Test status")".

### 9. The deviation list misses rows a large port will meet (should fix; verified)

Lines 54–60 list T-2, T-5, T-32, T-48, T-51, T-53/54. Add, beside L-3 (finding 1):
- **T-12:** TraitWorld's own tests and precompile workload use the earlier spelling (`@trait ColTable{R}`, `@implement X{MyType}`). "Do not copy trait code from TraitWorld's tests; copy from the references and the demonstrators."
- **T-19:** keyword, vararg and `Callable` functions are checked at their first call, not at the module's end. "A keyword-heavy API's definition errors show only when it is called: the workload or a test must call each such function."
- **T-38:** the T-5 bullet's second workaround ("declare the family on one line", `S{P} where {P}`) is refused for a trait whose parameters are defined by equations; only the variable form `A where {A <: S}` works there.
- **T-39:** a container is not taken at a bounded keyword.
- **T-49:** an operation with an argument declared `Self` fails on a `Dynamic` value.
- **T-52:** a type that conforms through a generic implementation and whose operations do not conform is accepted with a warning: read the warnings.
- **C-6** ([compiler §2.1](../reference/compiler.md#21-the-module-option)): a module's other compiler options are not applied to its facts code. SciMLBase, DiffEqBase, OrdinaryDiffEqCore and Makie set `@max_methods 1`, Observables `@optlevel 0` (`ndport/pkgs/*/src/*.jl`, top of each module).

### 10. A blocking deviation is not a Planned part, but it must pause the port too (should fix)

Lines 13 and 0.7 say a *Planned* part the port needs becomes a work item. The first blocker this port is likely to meet is a *deviation*: T-51 (a `Dynamic` function takes at most six arguments) against NetworkDynamics' edge output function `g(ysrc, ydst, x, insrc, indst, p, t)`, seven arguments, eight with external inputs (`ndport/pkgs/NetworkDynamics.jl/src/component_functions.jl:357`, reasoning from the documented signature). Replace "A part the port needs whose status is Planned becomes a work item; the port pauses for it." with "A part the port needs whose status is Planned, or a Deviations row that blocks it, becomes a work item; the port pauses for it."

---

## B. Usefulness for the NetworkDynamics, SciML and Makie port

### 11. Part 0 does not say how to make an unchanged package a trait module, nor what that refuses (should fix; verified)

0.1 says "put it in a trait module" and "move its pirates out". A porter of SciML needs the mechanics and the expected failures. Add a section **0.1a Making an unchanged package a trait module**:

- **How:** in the package's module file, `using TraitWorld` and then `@trait_module begin … end` around the package's `include`s ([traits §2](../reference/traits.md#2-trait-modules), the block form). Submodules inherit the mode. TraitWorld becomes a dependency; with `[sources]`, mind B1 item 9.
- **Each top-level statement runs after the ones before it** (`@stmt`, `trait_module.jl:88`). Not yet tried on a package of SciMLBase's or Makie's size: a P3 question.
- **Package extensions are modules of their own.** An extension of a trait module is plain unless it is wrapped too. Decide per extension; an extension that only declares implementations needs no wrapping (A4).
- **Pirates are refused at their definition (`OwnershipError`).** Find them before wrapping: strict mode lists the winning ones; `experiments/facts/g2strict.jl` lists pirates by the letter. **Split packages meet this at once:** DiffEqBase defines `solve(prob::AbstractDEProblem, args...; …)` (`ndport/pkgs/OrdinaryDiffEq.jl/lib/DiffEqBase/src/solve.jl:653`), a method of a function it does not own for a type it does not own. `TraitWorld.delegate!` serves strict mode only: the trait module's check, `owned_method` (`TraitWorld/src/ownership.jl:213`), does not read delegates, and the known delegates name `SciMLBase => OrdinaryDiffEq`, not DiffEqBase or OrdinaryDiffEqCore (`strict.jl:26`). This is a pushback entry and touches [open issue 1.20](../open-issues.md#1-decisions-waiting-for-the-user) (whether trait modules keep refusing every pirate).
- **Compiler options** the package sets (`@max_methods 1`, `@optlevel 0`): see C-6 (finding 9). `@max_methods` has no effect at a run-time site, where the facts mode speculates over nothing.
- **Workloads:** the package's `@compile_workload` (NetworkDynamics, SciMLBase, Makie, OrdinaryDiffEqTsit5 have one) becomes `TraitWorld.@workload` inside the trait module once it has bounded functions: the macro fixes the entries first (`TraitWorld.jl:168`).
- **Question for the author:** is `Base.Experimental.@compiler_options facts=true` alone (the facts mode without TraitWorld's checks, [compiler §2.1](../reference/compiler.md#21-the-module-option)) acceptable for P3's measurement? The references say user code writes `@trait_module`; the guideline should say which P3 uses.

### 12. The highest-value, lowest-change pattern is missing: an informal interface becomes a trait over the existing functions (should fix)

Graphs' `AbstractGraph` interface (`nv`, `ne`, `outneighbors`, …), SymbolicIndexingInterface's functions, and RecursiveArrayTools' array interface are informal traits written as generic functions that types extend. The references already give the port a near-zero-change path, and Part 0.2 does not name it:
- declare the trait with qualified operation names, `Graphs.nv(g::Graph)::Int` ([traits §3.1](../reference/traits.md#31-operations): "A qualified name uses that existing function");
- existing types join by their existing methods, one line or as a family over the abstract type, `@implement Graph G where {G <: AbstractGraph}`, as BaseTraits declares Base's containers ([§4.2](../reference/traits.md#42-one-line), [§4.7](../reference/traits.md#47-families), [§8.1](../reference/traits.md#81-basetraits-traits-for-bases-concepts));
- limits: a block of methods for an existing function only for types the declaring package owns ([§10.1](../reference/traits.md#101-who-may-implement)); a bounded method on another package's function only where the package owns a trait the bound names ([§5.5](../reference/traits.md#55-dispatch-types-first-then-traits)), and L-3 (finding 1).
- SymbolicIndexingInterface's `symbolic_container(x)` is forwarding to a field in all but name: a candidate for `by` ([§4.3](../reference/traits.md#43-forwarding-with-by)) where the container is a stored field, and for a type that only converts ([§4.10](../reference/traits.md#410-types-that-only-convert)) where it is computed (reasoning).

Add this as the first bullet of 0.2's "How each type joins", with the example.

### 13. Stored user functions, closures and RuntimeGeneratedFunctions: say where they go (should fix)

NetworkDynamics keeps the user's component functions (often RuntimeGeneratedFunctions from ModelingToolkit) in its component structs. B2's pattern (a struct parameter bounded by `Callable`) is the fit, but Part 0 does not connect them. Add to 0.4:
- a stored user function is a struct parameter bounded by `Callable` at the declared signature ([§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait), B2);
- a RuntimeGeneratedFunction has a type per body, and is not of the trait world: at a bare `Callable` it is `Dynamic`, so the library compiles once per signature, not per generated function ([§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations)). The package's own closures are of the trait world and run `Compiled` where the code knows their type;
- T-51 limits a `Dynamic` function to six arguments (finding 10);
- reflection on the function (NetworkDynamics infers the feed-forward type from `g`'s methods, `component_functions.jl:532`) must run on the plain function before it is kept (reasoning).

### 14. Keyword-heavy APIs: the pattern is scattered over four places (should fix)

`solve(prob, alg; kwargs...)` and Makie's attribute keywords are the main entry points of this port. The guideline has the pieces in A2 ("normalize options to concrete types where they enter"), A3's example (`_options(; kw...)`), B1 item 11 (workloads per keyword set) and the deviations (T-48, and T-19, T-39 from finding 9), but no rule. Add to 0.3:

> - **Keyword APIs:** the ordinary layer takes the keywords and builds a concrete options struct (`SolverOptions` in TDE's `solve`, `TraitDifferentialEquations/src/TraitDifferentialEquations.jl:69`); the bounded function takes it positionally. A keyword body compiles per set of keywords, so a workload covers the sets users pass. `Callable` with keywords is Planned ([§5.7](../reference/traits.md#57-keywords-defaults-and-varargs)).

### 15. Observables of `Any`: the guideline and the plan disagree (should fix)

The plan moves Observables into the trait world; 0.5 says notification graphs stay plain, from TraitMakie, which has no Observables. Makie's source has 38 `Observable{Any}` occurrences (`ndport/pkgs/Makie.jl/Makie/src`); every read of one is a run-time site with an `Any` result when compiled by facts, and it is compiled by facts wherever trait code reaches it (finding 5). Mark 0.5's item "Notification graphs …" as TraitMakie's experience without Observables, and add: "where trait code reads an observable, its value's type is what the code knows: type the observable (`Observable{T}`), or read it at the boundary and assert. Measure with the dispatch profiler before porting Observables."

### 16. Smaller usefulness points (minor)

- **ForwardDiff:** NetworkDynamics and OrdinaryDiffEq's Rosenbrock methods take Jacobians with duals through caches (PreallocationTools). B2's lessons (the buffer's element type is the problem's `T`; tag duals by the primal signature; fix the chunk) apply; add one line in 0.4 pointing to them.
- **Annotations on internal functions warn** ([§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations), Rules). A port that writes `Dynamic{X}` on a function neither exported nor `public` gets a warning at the module's end; add to 0.4's first bullet "on a public function's bound (exported or `public`)".
- **`invoke` over `Vector{Any}`** (A2, line 226) is a correct fact but the decided direction for loops over mixed data is a BaseTraits bound (open issue 31, decided; [§8.3](../reference/traits.md#83-a-users-container-taken-as-it-is)). Put the bound first, `invoke` as the fallback for Base's internals only.
- **A first-day checklist.** Part 0 reads as background, then advice. A numbered list at its top makes it actionable: (1) baselines and environments; (2) the facts mode on the unchanged code, three runs (finding 7), with the dispatch profiler; (3) the package as a trait module (finding 11), pirates and extensions resolved; (4) the traits written down (0.2, finding 12); (5) the seams, a function at a time (0.3); (6) record each step.
- **Test suites per step** (line 134) against "a check takes minutes at most" (line 173): OrdinaryDiffEq's and Makie's suites take far longer. Write "after each step, the workload and a chosen part of upstream's suite, minutes at most; the full suites at milestones (meta plan P5)."
- **`==` and fused arithmetic** (line 134): OrdinaryDiffEq's stage loops use `@muladd` (evidence §2 notes it), which lets LLVM fuse depending on what is inlined. Where the facts mode inlines differently from plain code, a last-bit difference could appear without a port bug (reasoning; not observed). Say what to do when `==` fails: check the site for `muladd`/`@fastmath` before calling it a bug, and record the case.

### 17. What only matters to the earlier demonstrators (minor)

Candidates to shorten or cut, as noise for this port:
- B1 item 12 (DataFrames' 46 storage sites), B1 item 5's counts (18 implementations, 8 widths, seven internal functions), B1 item 6's CSV details: keep the rule, drop the counts.
- B4's items that restate references: strict mode and the delegate (traits §10.3), the `Dynamic` world (facts §2.1), errors at the declaration (§4.9), redeclaration (§4.9): one line each with the link.
- B4's "A hook on your own type hurts plain callers only at narrow abstract signatures": about plain code's invalidation, not about porting.
- B3's `Hist`/`refresh!` paragraph: keep only the rule ("a parent rebuilds its children from its fields before each use"); it matters for Makie's compound recipes.

Keep: B1 item 9 (`[sources]` quirks: `ndport/env_port` uses `[sources]`), B1 item 11 (where compiled code lives; SparseArrays' `vcat`), B2 entirely, B3's scripted REPL session.

---

## C. CLAUDE.md conformance

### 18. Numbers copied from reviews instead of linked to the evidence (should fix)

CLAUDE.md: "The current numbers behind a claim: `writeup/design/evidence.md` … Other documents link to it rather than copy."
- Line 81: "36.8 ns per element against 1.1 ns in plain code, and 242 ns against 2.2 ns" from the review of 2026-10-20 (F1). The evidence's current row for the same loops gives 38–43 and 274–276 ns interop against 2.2–2.4 and 2.4 ns plain (E-134). Replace the numbers with "tens to hundreds of times plain code's cost per element ([evidence §2](../design/evidence.md#2-run-time), "idiomatic loops over heterogeneous containers", interop column)."
- Line 218: "45 times slower than plain in the review's measurement" and line 226 "ran at plain speed in the review's measurement (F2)": interop numbers from a review ("F1–F4 measure interop", its own addendum). Drop the factor or cite the evidence row.
- Line 159: finding 2.
- Line 424: "a new callback then took 171 ms instead of 12 ms" has no build. Name the build and the README table row, or write "took over ten times as long ([`TraitDifferentialEquations/README.md`], its dated table)".
- Line 357: "192 bytes per cell" is a failure's illustration; acceptable, but name where it is recorded (`forks/README.md`).

### 19. History language in Part B (minor)

CLAUDE.md: intro documents state the current state, no "was", "now", "no longer". Part B tells what ports showed, which the header permits ("Say what a port showed"), but several sentences narrate instead of stating the lesson:
- line 376: "`@inferred(DataFrame(Tables.columns(df)))` inferred `Any`; the port's constructor now asserts its result." → "Upstream's `@inferred` tests hold only where the port asserts its results: `DataFrame(::TableSource)` asserts."
- line 370: "`tablecolumn(t, i) = tocolumn(columns(t.table)[i])` was refused" → "is refused".
- line 367: "`TableSource`'s `nrow` collided with `DataAPI.nrow`" → "a `nrow` operation collides with `DataAPI.nrow`".
- line 354: "CSV's `stringtype = String15` passed a type, and upstream's InlineStrings extension added methods to seven internal functions." → present tense: "passes", "adds".
- line 450: "was ambiguous" → "is ambiguous".

### 20. One home per rule: the document states several rules three times (should fix)

- 0.4 "Take user types `Dynamic` … loops `compiled_for`", Proposed item 3, B3 "Recipes kept `Dynamic`".
- 0.4 "Leave the choice to the caller", Proposed item 2, B2 "A stored function".
- A2 bullet "splat", B4 "A splat is a fact only with concrete elements", Proposed item 5.
- B1 item 11 "workloads must cover keyword combinations", Proposed item 6.
- B4 "configure trait code by arguments", Proposed item 4.
- B3 "assignment converts", Proposed item 1, and traits §7.3 (whose third bullet is the same rule).
- A5 = 0.5; A7 = 0.3's layout = traits §2's last rule, verbatim; A3's first bullet = 0.1's last bullet.

And the governance is inconsistent: Part A admits a rule only after a second port confirms it, but Part 0 is "distilled from the ports of part B" and states the Proposed items as method already. Fix: say in the header that Part 0 is the editor's method and cites A and B; promote to A the proposals that two ports already show (item 3: TraitMakie and TraitTables, by the text's own "Shown by" line) and drop them from the list; for those Part 0 relies on with one port only (item 2: TDE), either mark them in Part 0 as one port's experience or keep them out of Part 0 until confirmed; make each A item a one-line rule with links to its B items and no repeated example.

### 21. Rules restated from the references (minor)

The guideline "teaches and points" (line 3), but some passages copy a reference's rule without adding porting advice: 0.4's "Know what the caller passes" (traits §6.2, with the same examples), A9's second and third bullets (§4.9, §7.6), A7 (§2), B4's strict-mode items (§10.3). Keep the porting consequence, link the rule. For example A7 becomes one line: "A package is an ordinary module around its trait module ([§2](../reference/traits.md#2-trait-modules)); see 0.3's layout."

### 22. Terms (minor)

- "the editor" (lines 9, 538) and "the reference's owner" (line 190) are undefined roles. Name them (the agent or person who merges; for a Deviations row, whoever changes the reference, per CLAUDE.md's table).
- "world" (line 522, "A `Dynamic` answers in the caller's world") is a core developers' term. Explain it: "the set of methods a call sees, fixed when the call starts (Julia's world age)".
- Project identifiers in Part 0 ("the NetworkDynamics port's part P3", line 86) belong to B5 and the plan; in Part 0 say "measure the facts mode first".

### 23. Examples are not run where intro examples run (minor)

CLAUDE.md: intro's examples run in `experiments/docs-examples/`. The guideline's examples are quotations from the demonstrators, each with its file, and the demonstrators' suites run them; none is in `docs-examples`. Say so in the header: "Each example is quoted from the file it names; that package's suite runs it." The ODEProblemTrait, `datalimits`, `Table`, `sortperm_col`, `defaulttypes`, `solve` front end, `ODEProblem` struct and `convert` examples all match their sources at the current commits (checked), except line 321 (finding 8).

---

## D. Length and structure

### 24. Readability (should fix)

545 lines, in five layers that a porter must reconcile: the language table, Part 0 (125 lines), Part A (130), Part B (205), Proposed (10). Part 0 and the table are the useful front; Part A is mostly Part 0 and Part B again, with "Shown by" lines; Part B mixes lessons with records of what happened. The process paragraph ("How this document is kept") stands before the content a reader came for.

### 25. A proposed shape (about 420 lines with findings 11–15 added)

1. Header: purpose, the rule that a port does not change the design (as now), and one line on how the document is kept (the full process to the end).
2. The language in one screen, with the completed deviation list (findings 1, 9).
3. Part 0, the method: the first-day checklist (finding 16), 0.1 and 0.1a (findings 5, 7, 11), 0.2 with the informal-interface pattern first (finding 12), 0.3 with keyword APIs (finding 14), 0.4 with stored functions (finding 13), 0.5 corrected (findings 5, 15), 0.6, 0.7.
4. Part A: one line per rule, links to B (finding 20); about 40 lines instead of 130.
5. Part B: lessons in present tense, counts and narrative trimmed (findings 17, 19); B4 reduced to the items with porting advice. About 150 lines instead of 205.
6. Proposed for part A: only rules no other part states.
7. How this document is kept (moved from the top).

---

## What was done with each finding

(To be filled by whoever acts on this review.)
