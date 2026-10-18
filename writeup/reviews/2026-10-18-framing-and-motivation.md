# Review: the framing and motivation of the trait-bound Julia design

2026-10-18. Independent critical review of `writeup/notes/1-overview.md` and the proposed reframing (the user's two goals). Sources read: `README.md`, `writeup/README.md`, `notes/1–4`, `decisions.md`, `open-issues.md`, `explorations/strict-mode.md`, `wrapping-by-facts.md`, `dataframes-port-lessons.md`, `plans/2026-10-17-policy-in-compiler-plan.md`, `other-languages.md`, `experiments/factscompiler/README.md`, `forks/README.md`, the three demonstrators' READMEs, `design-findings.md` §1, session notes 26 and 27.

Every claim below is marked **Verified** (checked against a source or an experiment run today) or **Reasoning** (my inference). Scratch work: `/tmp/claude-1000/review-framing/` (`inval.jl`, `explosion.jl`, their logs). No repository file was changed.

## 0. The experiment this review rests on

`inval.jl` defines eight small situations and checks, after each definition, whether the compiled caller's CodeInstance is still valid (`max_world == typemax`). It was run on stock Julia 1.13.2 (juliaup binary, plain inference) and in facts mode (`experiments/factscompiler`, `JULIA_FACTS_COMPILER=1`, on `julia-1.13/julia`). Logs: `inval-stock.log`, `inval-facts.log`.

| # | What is defined after the caller compiled | Pirate? | Stock: caller invalidated? | Facts mode: invalidated? | Facts mode: price |
|---|---|---|---|---|---|
| S1 | `Other1.T`, `Lib1.foo(::T)`; caller calls `foo(v[1])` with `v::Vector{Any}` (one method matched) | no (Other1 owns `T`) | **yes** | no | caller's result `Int64` → `Any` |
| S2 | `Other2.C <: Shape`, `area(::C)`; caller loops over `Vector{Shape}` with 2 methods (union split under `max_methods`) | no | **yes** | no | result `Float64` → `Any` |
| S3 | `Other3.NR <: Real`, `w(::NR) = "s"`; caller `map(w, xs::Vector{Real})` on `Real[]` | no | **yes**; value changes `Vector{Float64}` → `Vector{Any}` | no | **value is `Vector{Any}` already before the load** (plain gives `Vector{Float64}`) |
| S4 | `Lib4` itself adds `bar(::Int)` over its `bar(::Integer)`; fact `bar(::Int)` | no (stakeholder; what a package extension does) | yes | **yes** | — |
| S5 | `Pirate5` adds `Lib5.baz(::Signed)` over `baz(::Integer)`; fact `baz(::Int)` | yes, wins | yes | **yes** | — |
| S6 | `Pirate6` adds `Lib5.baz(::Real)`, loses at `baz(::Int)` | yes, loses | no | no | — |
| S7 | `Lib7` redefines `const K` that the caller read | n/a (a binding) | yes | **yes** | — |
| S8 | `Other8.U`, `make(::Type{U})`; caller passes a `DataType` value | no | **yes** | no | result `Int64` → `Any` |

**Verified** from this table:
- In stock Julia, four of the five non-pirate situations invalidate (S1, S2, S3, S8). None involves piracy. This is the mechanism of the session-26 finding (TraitWorld's own `Base.show(io::IO, ::Type{<:CObj})` cost CSV 1.0 s) and of `design-findings.md` §1: on 1.12, `using CairoMakie` invalidated 769 method-table signatures, none concrete; 216 of 217 roots abstract.
- In facts mode, the non-pirate situations stop invalidating. What remains: a stakeholder's definition (S4), a winning pirate (S5), a binding redefinition (S7). A losing pirate never invalidates in either mode (S6; the design's E3).
- The price is visible in the same run: the results of S1, S2, S8 are `Any`, and S3 computes a different value than plain Julia in the same world, before any load. That last point is the plan's risk R3 made concrete: under the `all` setting there is no plain inference left for `return_type` to fall back on (`facts_plain_return_type` returns `nothing` because `w(::Float64)` does not fully cover `Real`; the run-time `return_type` then runs in facts mode and answers `Any`). TraitWorld's external interpreter would have asked native inference and matched plain Julia. "Identical or error" is weaker under `all` than the notes state for trait code.

`explosion.jl` (stock): 30 wrapper structs sharing `data::Vector{Float64}` plus a field the library never reads; a 25-line summary function. Plain: 32 specializations, 6.8 ms of first calls in total (about 0.2 ms per type, since the callees are in the system image); behind a function barrier: 1 shared body, 0.2 ms in total. **Verified:** the per-type multiplication is structural; its cost per type depends entirely on the body's size (the repository's real cases: 167–297 ms per table type in Makie, 0.84–0.96 s per callback in SciML, 0.45 s per tuple of column types in DataFrames' sort).

## 1. The current framing (`1-overview.md`)

### What it says

"Why" gives two headings: *compiled code is fragile* (loads discard it; a new type recompiles; AOT is trial and error) and *Julia compiles for the whole type* (type is data; a method is compiled for the full concrete type; abstract types are unchecked and slow). "The idea" leads with the slogan "a trait is an abstract type with behaviour", then conformance, keys ("compiled for what the bound can see"), reading like abstract types, the trait world and the facts rule, ownership. Four pay-offs follow: cached code, simple AOT, no performance cliffs, minimal semantic change. Then an example, costs, status.

### Where it is right

- The two problems are the right two, and both are measured (session 20's Makie recompilation; SciML's callback; the 33,673-character frame). **Verified** against `design-findings.md` §1 and the demonstrators' READMEs.
- The cost list and the status are honest: the facts cliff ("calls at abstract types dispatch at run time, also where plain Julia would infer through them"), the recompile of Base code, the Julia pieces, the open items. Few design documents list their costs this plainly.
- The demonstrators have fair baselines (PlainODE, PlainPlots, PlainTables), and the READMEs say where the baseline matches the trait form. **Verified.**

### Where it fails a skeptical core developer (ranked by damage)

1. **It argues from mechanism, not from need, at the one place the argument lives.** The decisive step is: load-time invalidation in Julia comes almost entirely through inference at abstract signatures, and compiled code that depends on the method table only at concrete signatures is touched only by stakeholders and winning pirates. The overview states the rule as a boxed quote and jumps to "Ownership. Who can change such a fact?" with no numbers and no example. The 769/0 figure, the 216/217 figure and a two-line example like S1 belong here. Without them the reader meets "traits", "keys", "trait world", "facts", "stakeholders" before learning what each buys. **Reasoning**, supported by the fact that `2-design-choices.md` §3 ("What is new over discipline") answers the core developer's first question and the overview never does.
2. **The lede is buried.** The strongest results are: trait-world libraries lose no compiled code to nine or twelve other packages in either load order while the same libraries without traits lose a third (TraitReport form (t) vs (pt), 17 of 49 methods); a package extension becomes a conformance that invalidates nothing (44 ms vs CSV.jl's 3.9–5.0 s in every session); callbacks and loss closures cost milliseconds instead of seconds. These appear in Status and in READMEs, not in Why. **Verified** against TraitReport and TraitDifferentialEquations READMEs.
3. **Overclaims and stale claims a core developer will catch:**
   - `README.md`: "never invalidated by unrelated loads" and the overview's pay-off 3 "No performance cliffs". The notes themselves list the exceptions: a package extension triggered by an unrelated load (Theorem 2 case c); TraitWorld's own machinery loses about 190–200 of 2,064 native CodeInstances to the same loads (TraitReport README); new trait code after big loads costs 2.7 s / 6.4 s without the system image; and the facts cliff is a cliff: `collection` benchmarks 17–82× slower, raytrace 3.5×, `io` 1.32 geomean (`factscompiler/README.md`). "No cliffs from loads" is defensible; "no performance cliffs" is not. **Verified.**
   - "Simple ahead-of-time compilation", with the binary "to be rebuilt" since keys and the trim verifier reporting 26 errors on the machinery's slow paths (TraitMakie row 7). The AOT story is also now "a trimmed build compiles the plain call" (decision, session 25), so the facts machinery plays no part in AOT; the overview still lists AOT under the same breath as caching.
   - "Minimal changes to semantics … identical or error" against A3 (values decided by inference), which the `all` setting widens (S3 above). The overview's pay-off 4 should name A3 and the setting.
   - Status: "strict mode, not built" while `decisions.md` records a prototype with 32 tests (7b328a5). Numbers disagree: 22 s to first plot (overview) against 15.7–16.2 s (TraitMakie README, `design-findings` §15); typed calls 37–39 ns (overview, status) against 33 ns (decisions, open-issues). The fresh-eye review of session 27 lists these; they are still in the text. **Verified.**
   - "The runtime needs work in Julia … is package code" against the adopted "policy in the platform" (session 26) and the session-28 pivot to a mode of Julia's own compiler (`plans/2026-10-17-policy-in-compiler-plan.md`). The overview describes an architecture the project has left.
4. **It does not say what is new over discipline, up front.** PlainODE matches the trait form on rows 2 and 5 in a fresh session; PlainPlots matches first-PNG and run time without loads; form (pt) equals form (t) in a fresh session. The trait form wins under loads and in checking. The overview should say this in its first screen, because a core developer's reflex is "this is `@nospecialize`, function barriers and PrecompileTools". The answer (the bound is enforced; targets are closed; code compiled per type lives in the chooser's image; nothing is invalidated by loads) exists in `2-design-choices.md` §3 and should be the overview's. **Verified** (baselines in the READMEs).
5. **The slogan leads, the type-system change hides.** "A trait is an abstract type with behaviour … membership is subtyping … a conformance adds a supertype after the type is defined" is a change to Julia's type system, and the overview presents it as a reading convention. A core developer will want the one paragraph that says: this needs the language (two parts are approximated in the package), here is what is approximated and how. It is in README "The plan" item 1, not in the overview.

## 2. The proposed reframing, point by point

### 2.1 Goal 1: "composable caching and AOT reduce to: compiled code is never invalidated unless the code changes"

**Reasoning, with verified parts.** Necessary, not sufficient, and AOT does not reduce to it.

- *Composable caching* needs two things: compiled code stays valid under any combination of loads, and the code for a combination exists in some image. The second is rule 4 (where compiled code lives) and Julia piece 5 (native code for upstream instances compiled by a downstream package). `dataframes-port-lessons.md` §2.2 shows it is not automatic: DataFrames' workers for CSV's column types exist in no image until a glue extension (`CSVDataFramesExt`) compiles them, and TraitReport (a′) shows piece 5 helps plain Julia as much as the trait world (0.96–0.99 s → 0.07 s of work). **Verified.** A framing that reduces caching to non-invalidation leaves placement out, and placement is where half the Julia work is (pieces 5, 9, 10).
- *AOT* needs a listable set of dispatch targets (G3, Theorem 3), not non-invalidation: in a binary nothing loads, so there is no cache to protect, and the adopted design compiles the plain call in a closed world (`aot-under-facts.md`, decision s25). What makes trait code trimmable is that dispatch over trait positions goes through declared conformances, `Callable` signatures and `Dynamic` targets that `verify_main` lists. That belongs to goal 2 (expressing what code needs), not goal 1. **Verified** against `4-details.md` "AOT" and `decisions.md`.
- *"Unless the code changes"* must be defined, or it is circular. The design's definition is: unless a stakeholder of one of its facts defines, deletes or redefines a method (an edit, an upgrade, a package extension activating), or a binding it reads changes (S7). "The code" includes its dependencies' code. The framing should say so; otherwise a reader takes "the code" to mean the library's own source.

### 2.2 "What invalidation does: code that the compiled code depended on is no longer valid"

**Reasoning.** Half right, and the half that is wrong matters. In Julia, compiled code depends not on code but on *dispatch answers*: "at signature `s`, these methods match / this method wins". A new method that matches `s` but does not win changes nothing (S6, **verified**; E3). A new method that wins, or that makes an abstract match set larger, does. So the right statement is: compiled code depends on the method table through its inference edges, and an edge at an abstract signature depends on *every* method that matches it, which any package can add for its own type. That is what makes stock Julia's invalidation an open-world problem rather than a piracy problem. The framing also omits binding edges (S7) and results folded from `return_type` (S3), which are dependency classes of their own.

### 2.3 "The principal way code gets invalidated is piracy"

**Verified false for Julia as it is; true only under the facts premise; and empirically vacuous even then.**

- Stock Julia: S1, S2, S3, S8 invalidate with no pirate present. `design-findings.md` §1: `using CairoMakie` on 1.12.2 invalidated 769 method-table signatures, none concrete, 216 of 217 roots abstract. The session-26 finding was TraitWorld's own non-pirate `show` methods costing 1.0 s. Makie's tree carries 1,091 pirates by the letter (`2-design-choices.md`, cost 2) and E2 found 0 concrete facts of the demonstrators' code at which any of them wins; `g2all` lost 0 CodeInstances over twelve loads with strict mode off. Piracy is not the principal way; abstract speculation is.
- Under rule R (facts at concrete signatures only), Lemma O makes the residual exactly: stakeholders' definitions, winning pirates, package extensions of stakeholders triggered by unrelated loads, and bindings. **Verified** (S4, S5, S7 invalidate in facts mode; S1, S2, S3, S8 do not).
- So the hidden premise is rule R itself, and the framing must state it as the first design step, not as a consequence: *"To make 'only edits and pirates invalidate' true, compiled code must depend on the method table only at concrete signatures. Julia's inference does not do that today; the facts policy does."* Stated that way, the premise's cost is also visible: every call plain inference would have typed through an abstract signature becomes a dynamic call with result `Any` (S1, S2, S8; `factscompiler/README.md` tails; `dataframes-port-lessons.md` 1.5). The user's framing hides this cost, and it is the one a core developer will raise first, because it is a cost for all of Base in the `all` setting (geomean 1.016, 1.064 without `scalar`; `io` 1.32).
- Even under the premise, winning pirates have not been observed to matter (E2, `g2all`, `g2strict`: refused nothing). The honest sentence is: "pirates are the only non-stakeholder way left, they are named by ownership, and so far none has won anywhere the demonstrators call."

### 2.4 Is the ownership/stakeholder theory adequate as the definition of piracy?

**Reasoning, with verified sources.** As a *definition* it is Julia's own (the manual, Aqua.jl) made strict for `Union`s; the design's contribution is not the definition but Lemma O and Theorem 2, which connect it to concrete facts and say who can change one. The framing should claim that, not "we provide a theory that allows us to define piracy", which a core developer will read as reinventing Aqua.

Gaps, in order of weight:
1. **Package extensions and Requires blocks** are the one unrelated-load hole; named in the notes since session 27 (Theorem 2 case c). The strict-mode fix (refuse an extension's winning method at a fact without its triggers' types) is deferred (`strict-mode.md` §2b item 3). This is exactly the CSV × InlineStrings pattern that motivates TraitCSV, so it is not a corner case.
2. **Bindings** are not in the theory at all (no mention in notes 1–4 or the explorations; only `rests_on_facts` in the compiler copy skips `Core.Binding` edges). A `const` redefinition invalidates (S7, both modes). A package can redefine another package's binding (`Core.eval(Other, …)`): piracy of a binding, undefined in the theory.
3. **The session as an owner.** Strict mode refuses `abs2(::Float64)` defined at the prompt (`strict-mode.md` §2a). Monkey-patching Base interactively is common; the friction is real and unstated in the overview.
4. **Split-core packages** (StaticArrays over StaticArraysCore): pirates by the letter, handled by a curated delegate list "as data". Adequate, but a social mechanism, and the overview does not mention it.
5. **Julia as one owner** including "the standard libraries of the system image": stdlibs outside the system image (upgradable ones) are packages; fine, but the text should say which. The owner of a supertype counts as a stakeholder, so Julia is a stakeholder of every signature (through `Any`); harmless, since Julia is always loaded, but a Julia upgrade is then the universal invalidation, which "unless the code changes" should admit.
6. **`public`** was tried as a basis for more facts and dropped (decision 3, s27) because rule 3 lets a type's owner extend another package's internal function. Correct, and worth one sentence in the framing, since a core developer will propose it.
7. **Ownership of a generic function** by "the package where its first method defines the name" is fragile for functions created by `@eval` into another module or by macros; constructors (`Type{T}`) and `kwcall` are fine by the type rule. Minor.

Verdict: adequate for the thesis once the extension exception and bindings are stated as part of it, not as footnotes.

### 2.5 "We prevent piracy while allowing extending and hooking into existing code"

**Verified against decisions:** the design does not prevent piracy. Rule P follows pirates as plain Julia does; a trait module may not define one; strict mode (optional, off, prototype) refuses a pirate that would win at a trait-world fact; sealing was removed (s25) and the user's own session-28 direction removes "sealed" notions altogether (open-issues 2.26). "Prevent" would commit the design to strict mode by default, the extension rule, the deletion hook (piece 1′) and image validation reporting (piece 15), all deferred (`strict-mode.md` §2b).

The honest claim: pirates are *identified* (ownership), *contained* (they can touch only code with a fact where they win, and only by recompiling it to what plain Julia computes), and *refusable* (strict mode). "Extending and hooking" is delivered by conformances (also from extensions: the `String15` case), named implementations (design, not built), `Callable`, and ordinary stakeholder methods. One caveat the framing should own: a hook such as `Base.show(io, ::MyType)` is a stakeholder's method, allowed, and in stock Julia it still invalidates every plain caller compiled at `show(::IO, ::Any)`-shaped signatures (S1, the session-26 finding). Only code compiled under facts is immune. So "allowing hooking" without cost is true for trait-world code or under the `all` setting, not for plain Julia alongside.

### 2.6 Is "never → practically never" only a performance tweak?

**Reasoning.** No; it changes the kind of guarantee, and the project's direction is the reverse of the framing's.

- With "practically never" (rule P, strict mode off), the property "this image's code is valid in environment E" is empirical: true in every environment tested, false in any that loads a winning pirate. With "never" (strict mode's intended design), it is a static property of the environment: a load that would falsify it fails with an error naming the method. That is the difference between a measurement and a theorem, and for package images it is the difference between re-validating every fact at load and trusting the image.
- Who pays changes: under "never", plain users of the pirate's package get an error for code they never called (`strict-mode.md` §1, "the refused package does not get its method, also for its plain users"). That is a policy decision about the ecosystem, not a performance knob.
- Load order changes meaning only in *when* code compiles, not in *what it computes* (G1 holds either way), but under "never" the "before" order still follows the pirate unless the symmetric check (a lint) is on. So "never" is not reached by strict mode alone; §2b lists five sources, with edits as the stated exception.
- AOT is indifferent (a closed world has no loads).
- Direction: the design today sits at "practically never" with "never" deferred as the intended design of an optional mode. The framing presents "never" as the base and relaxation as a later tweak. The notes should present it the other way: rule P is the base because it is what plain Julia does and what "identical or error" needs; strict mode is the hardening.

### 2.7 Goal 2: "we can't express what our code actually needs"

**The problem is real and is the right second goal.** `Vector{AbstractVector}` versus `Vector{Column}` is the right example: PlainTables loses 17 of 49 methods to loads, `Vector{Dynamic{Column}}` loses none (**verified**, TraitReport README). The facts cliff is also the reason goal 2 is not optional: assertions recover half of raytrace, a `Union` written out recovers all of it but closes the set, and the trait form with key branches reaches 498–505 ms against plain's 249 ms *independent of how many types exist* (plain goes 240 → 693 ms from 2 to 4 types; `factscompiler/README.md`). **Verified.**

Four corrections:
1. **"Compiled code works with any type that provides it without recompilation" is an overclaim** that contradicts the design's own choice. Keys compile a worker per implementing type and per tuple of declared field types (`4-details.md` "Terms", "Key"; TraitMakie row 4: a new type that implements the operations costs a conformance of 0.10–0.23 s plus a first PNG compiled for it). Sharing happens in three places only: forwarding to a field of a known key; `Dynamic{X}` positions (dispatch per operation, now witness tables and key branches); `DynamicCall` functions. The sentence as written describes Swift's model (one copy, dictionary passing), which `2-design-choices.md` §7 rejects for its cliffs. The defensible sentence: *compiled for what the bound can see; a type that only holds the data shares the library's code; a type that supplies behaviour gets its own copy, once, in its own image.*
2. **Witness tables and `Dynamic{X}` fit as the dynamic position,** the Swift-like half: an operation on a `Dynamic` dispatches on the conformance (15–20 ns with witness tables, 2–11 ns per element with key branches at 1,000–10⁶ elements), with a declared result type so that code after the call compiles. Key branches are the analogue of plain Julia's union-split `isa` branches, but over declared conformances known at compile time, so adding a conformance invalidates nothing (S2 is exactly what they replace). The framing should name this pair: bounded arguments = specialization over keys (Rust-like, coarser than Julia's); `Dynamic` = witness dispatch (Swift-like); run-time sites = plain dynamic dispatch.
3. **"Explosion of compiled code" is structural but not measured as volume.** The repository measures per-type latency (X1 25 ms; Makie 167–297 ms per table type; SciML 0.84–0.96 s per callback; DataFrames sort 0.45 s per tuple of column types; `typeof(integrator)` 3,553 and 24,426 characters). It has no count of CodeInstances or image bytes per added type, and `2-design-choices.md` §3 admits "the argument is structural; it is not yet measured on a stack of trait modules". My `explosion.jl`: 32 specializations against 1, but 0.2 ms per type for a 25-line body. Use "compiled once per type, for parts it never reads" with the measured latencies; reserve "explosion" until a volume measurement exists (CodeInstances per type across a real library; the demonstrators' image sizes with N conformers).
4. **The two goals are not independent; say so.** Goal 2 serves goal 1: `Dynamic` containers remove the abstract-container speculation that is the main invalidation source (S2); keys shrink what a user's image must compile; declared result types give back what the facts cliff takes. Goal 1 serves goal 2: per-key code is worth caching only if loads cannot discard it. They are two faces of one decision: *what compiled code may depend on* (facts, ownership) and *what compiled code is compiled for* (keys, `Dynamic`). The framing should present them as a pair with that sentence, and should add the two pay-offs goal 2 brings that the user's text omits: checking the library against its contract where it is defined (errors at the build, 12 frames against 29), and readable types.

### 2.8 Does the reframing clarify the relation to Rust, Swift, C++?

**Reasoning.** Yes, if the pair is stated as in 2.7(2). Goal 1 has no counterpart in those languages: Rust and Mojo compile whole programs, Swift has ABI-stable dictionary passing, C++ re-instantiates per translation unit; none has a JIT with a cross-package cache that an open method table can invalidate. Goal 2 is exactly where their traits live (bounds, associated types, `dyn`/`any`). The reframing therefore separates what is Julia's own problem from what is borrowed, which the current overview does not. Two cautions: the user's "once for any type" sentence *is* Swift's model and would place the design where it has chosen not to be; and `other-languages.md` is stale (written with "projection" and "representation", table row "Storable dynamic value: no", "What is new" items 1 and 3 describe the removed design). **Verified.**

## 3. The framing I would defend

> **Superseded by §5 (Revision 2: strict mode first),** on the user's direction. The analysis in §§1–2 stands; the outline and the draft below are kept for comparison.

### Outline

1. **Problem statement** (two sentences): Julia compiles a method for the concrete types of its arguments and caches the result. The cache does not stay valid, and the code it holds is compiled for more than it needs.
2. **Problem 1: compiled code does not stay valid.** Inference at abstract signatures depends on every method that matches; any package adds one for its own type; no piracy involved (S1; 769/0; the session-26 `show` case). Package images cannot help. Numbers: the ad-hoc session, CSV × DataFrames 2.5 s.
3. **Problem 2: code cannot say what it needs.** Concrete types carry everything, abstract types promise nothing checked and speculate over today's methods; the per-field choice between nested types and `Any`; the measured latencies and the 3,553-character type; errors deep inside.
4. **The design, step 1 (for problem 1): facts.** Compiled code depends on the method table only at concrete signatures; everything else is plain dynamic dispatch; nothing skipped. Consequence (Lemma O): only stakeholders' edits, winning pirates, extensions of stakeholders, and bindings can invalidate. Ownership names the stakeholders; Julia already calls the pirate case type piracy. Pirates are followed (rule P), refusable (strict mode). Measured: 0 lost over twelve loads; no pirate won. **The price, stated here:** abstract calls become `Any`; Base's benchmarks 1.6% geomean, tails to 80×; `return_type` values can differ (A3).
5. **The design, step 2 (for problem 2, and to pay step 1's price): traits.** A declared, checked contract: operations with result types, fields with types. Bounded arguments compiled per key; `Dynamic{X}` for fields and containers, with witness dispatch and declared results; conformances as the extension mechanism (package extensions become conformances); definition checking at the library's build. Then the recovery numbers (raytrace), the load-independence numbers, the callback and loss numbers.
6. **AOT, as a consequence of step 2:** every dynamic position has declared targets; a build lists them; plain code reached from trait code keeps plain Julia's holes; a trimmed build compiles the plain call.
7. **What is new over discipline** (one paragraph, with the PlainODE/PlainPlots/(pt) baselines): same fresh-session speed; what differs is behaviour under loads, enforcement of the bound, closed targets, and checks at definition.
8. **What is not claimed:** no change to what a call computes beyond A3; no refusal of pirates by default; no "once for any type"; "explosion" not measured as volume; the binary not rebuilt since keys; a stack of trait modules not measured; the `all` setting's cost for Base is a go/no-go measurement, not a result.
9. **What Julia must provide**, in the pivot's terms: a mode of the compiler behind a switch (A), then (B)/(C) only if the measurement says so; pieces 1, 3, 17 kept.

Against the user's version: **adopts** the two-goal structure, the `Vector{Column}` example, ownership as the naming of who can invalidate, and the positioning benefit. **Amends** goal 1 to "depends on the method table only at concrete signatures" with piracy as the named residual, states the facts cost next to it, adds placement, moves AOT to goal 2, and replaces "once for any type" with "compiled for what the bound can see". **Rejects** "piracy is the principal way" (false in stock Julia), "we prevent piracy" (rule P), "never → practically never is a performance tweak" (a different guarantee, and the project's direction is reversed), and the independence of the two goals.

### Draft: the first ~40 lines of a rewritten overview

```
# Traits for better Julia

Julia compiles a method for the concrete types of its arguments and caches the result. Two things
go wrong with that cache. This design fixes both, and each fix needs the other.

## The problem

**1. Compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used.
- Where inference ran at an abstract signature, it depends on every method that matches there. Any
  package that adds a method for its own type changes the answer, and the code is discarded. No
  piracy is involved: `Base.show(io, ::MyType)` in MyPackage invalidates every caller compiled at
  `show(::IO, ::Any)`-shaped signatures.
- On Julia 1.12, `using CairoMakie` discarded code at 769 signatures, none of them concrete. In an
  ad-hoc session, most of the 16 s to a first plot was Makie code recompiled after a CSV reader's
  dependencies loaded. With DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s.
- Package images cannot help: the code they hold is discarded the same way.

**2. Code cannot say what it needs.**
- A field or an argument is typed either concretely (fast; compiled per type; carrying every part
  of the value, read or not) or abstractly (`Vector{AbstractVector}`: one copy, every operation a
  dynamic dispatch, inference speculating over the methods that exist today).
- Libraries choose per field between nested concrete types (SciML: a new callback recompiles the
  solver, 0.84–0.96 s; an integrator type of 3,553 characters) and `Any` (Makie's attributes).
- Nothing checks that a value does what the abstract type promises; mistakes surface deep inside
  the library, at run time, printed at full type.
- A binary cannot list what a dynamic call may reach, so ahead-of-time compilation is trial and error.

## The idea

**For 1: compiled code depends on the method table only through facts at concrete signatures.**
"At `foo(::Int)`, dispatch selects this method." A call whose argument types are not concrete
dispatches at run time, as plain Julia's dynamic dispatch does; nothing is skipped, and Julia's own
invalidation for such edges is exact.
- Then only three things can invalidate compiled code: an edit by a stakeholder of one of its facts
  (the owner of the function or of a type in the signature, or their package extension), a pirate
  that wins there, or a binding it reads being redefined. Julia already names the second case: type
  piracy. Pirates are followed, as today; an optional strict mode refuses them.
- Measured: twelve packages loaded before or after trait-world code discarded none of it.
- The price: a call that plain inference typed through an abstract signature is dynamic, and its
  result is `Any`. Over Base's benchmarks that is 1.6% on average and up to 80× in loops over
  containers of `Any`. Traits are how code says what it needs and gets that back.

**For 2: a trait is an abstract type with a declared, checked contract:** operations with argument
and result types, and fields with types. A type joins by declaration. Code bounded by a trait
reaches its argument only through the contract, so it is compiled for what the bound can see …
```

(The 16 s figure is TraitMakie's README; the overview's 22 s is session 20's on 1.12 and should be reconciled before use.)

### Sections of the notes that would have to change

- `README.md` first paragraph: "never invalidated by unrelated loads" → "invalidated only by stakeholders of its facts or pirates that win there", and name the extension exception.
- `1-overview.md`: "Why" restructured as above; "The idea" reordered (facts before traits, ownership inside facts); pay-offs reduced to three (code that stays valid; code compiled for what it needs and checked; AOT by declared targets) with "identical or error" as a constraint and A3 named; pay-off 3 retitled "no cliffs from loads" with the facts cliff and its recovery; "What it costs" moved up to follow each step; Status corrected (strict mode prototype; 33 vs 37–39 ns; 22 vs 16 s; "the policy is package code" → the mode of Julia's compiler, with (A)/(B)/(C) and the go/no-go result).
- `4-details.md` "Ownership": add bindings as a dependency class; the session as an owner and strict mode's friction at the prompt; "Caching" and "Performance: no cliffs": the facts cliff with numbers; "Identical or error": A3 is wider under the `all` setting (S3 as the example); "AOT": say that facts play no part in a trimmed build.
- `3-wrapping.md`: "What the compiler records" and "What Julia must provide" rewritten for the pivot (the policy as a compiler mode; which pieces stay); "Pirates": the empirical status of winning pirates stated as such.
- `2-design-choices.md`: the banner's promise ("to be revised") honoured: §5, §6, §7 and costs 1–3, 6, 8 are the removed design; add the facts cliff to "What the choices cost"; the table's "Ours" column checked against keys and `Dynamic`.
- `other-languages.md`: "projection/representation" wording, "Storable dynamic value: no", "What is new" items 1 and 3; add the sentence that goal 1 has no counterpart in the four languages and goal 2 is where their traits live.
- `decisions.md` / `open-issues.md`: a row for the pivot (session 28) and for "no sealing" (2.26 exists); the missing session-28 note.
- Demonstrator READMEs: a line each on what the baseline matches, lifted into the overview's "What is new over discipline".

## 5. Revision 2: strict mode first

The user (via the coordinator, 2026-10-18): "I am thinking we should work the argument from strict mode first. The fact that it will not be the default comes later. This is a change." This section supersedes §3's outline and draft. Everything in §§1–2 still holds; §2.5 and §2.6 are refined here.

**One new verification.** `TraitWorld/src/strict.jl` (header, `_strict_on_definition`, `_strict_image_refusals`) and `julia-1.13/TRAITWORLD.md` (piece 1: `jl_set_method_definition_hook`, `jl_set_image_methods_hook`): strict mode acts only when a method is defined or an image's methods are about to be activated. Nothing changes at run time or in compiled code. **Verified.** This is the condition that makes "strict first, default later" honest (5.3).

### 5.1 The derivation, from the guarantee down

**The guarantee.** *Compiled code is never invalidated unless code it depends on changes.* "Code it depends on" is defined, not left to intuition: the packages that own the function or a type (or a supertype) in one of its call signatures, and their package extensions. Nobody else can touch it: not a load, not a package adding methods for its own types, not a pirate.

Three steps make it true, and each is forced by the one before.

1. **Compiled code depends on the method table only through facts at concrete signatures** (rule R). Why forced: an inference edge at an abstract signature depends on every method that matches it, and a package that adds one for its own type is a legitimate owner. There is nobody to refuse (S1, S2, S8: all invalidate on stock Julia, none is piracy; 769 signatures from `using CairoMakie`, none concrete). So the guarantee is unreachable while compiled code holds abstract edges; under rule R the abstract call is a run-time dispatch and records nothing (S1, S2, S8 survive in facts mode). This is also where the price is paid: the call's result is `Any` where plain inference typed it; traits are how code gets it back (step 2 of problem 2).
2. **At a concrete signature, only a stakeholder or a pirate can change dispatch** (Lemma O; Lemma D for order independence). Stakeholders are the owners above; a change by them *is* "the code changing": an edit, an upgrade, an extension. A pirate is the one remaining way for an unrelated package to change what the code computes. Julia already names it: type piracy, Aqua's rule, made strict for `Union`s and judged on the method's own signature.
3. **A pirate that would win at a fact of compiled trait-world code is refused** when it is defined: at the prompt, by `include`, or as a package image's methods activate (piece 1). The error names the method and the code it would have changed. A refused method does not exist for plain Julia either, so "identical or error" holds: a call computes what plain Julia computes in the world that has no such method.

With steps 1–3 the guarantee reads: *a valid trait-world CodeInstance is invalidated only by a definition from a stakeholder of one of its facts.* That is Theorem 2 with case (b) removed by refusal. Lemma O is then no longer a footnote about who may invalidate; it is the lemma that makes the refusal sound (only pirates are refused, and only pirates can be non-stakeholders).

**What still invalidates, by design, and must be named with the guarantee:**
- a stakeholder's definition (S4): edits, Revise, upgrades; the stated exception;
- a package extension (or Requires block) of a stakeholder whose method applies at a fact without mentioning its trigger's types, activated by an unrelated load (Theorem 2 case c): either refused by the extension rule of `strict-mode.md` §2b item 3, or admitted as "the stakeholder chose it" (5.4 below: a decision);
- a binding the code reads being redefined (S7): by its owner an edit; by `Core.eval` into another module a pirate of a binding, which no hook today sees (5.4);
- a pirate loaded *before* the code was compiled: followed, compiled against, and never again changeable by a non-stakeholder. For code in a package image this is the one case where a pirate still discards cached code (image validation rejects the facts; §2b item 1, piece 15 turns it into an error).

**Extending and hooking, under strict mode.** The refusal is narrow, and the framing must show how narrow:
- *Conformances are the sanctioned extension point.* `@implement X T` is a method the trait's owner or the type's owner writes (rule 3), of the conformance registry with `@max_methods 1` and a fallback, so a new conformance applies at no existing fact and invalidates nothing; in TraitCSV, InlineStrings' `String15` conforms from an extension and the reader compiled for `Float64` columns keeps its code (44 ms against CSV.jl's 3.9–5.0 s). This is what package extensions become.
- *Hooks on your own types are not piracy.* `Base.show(io::IO, ::MyType)`, `Base.sum(v::Vector{MyType})`, an operation of someone's trait for your type: MyPackage is a stakeholder of every signature these apply to, so strict mode never refuses them, and under rule R they apply at no fact compiled before `MyType` existed. The hook invalidates nothing. (In stock Julia the same hook invalidates every plain caller at `show(::IO, ::Any)`-shaped edges, S1; that is the problem, not the hook.)
- *Named implementations* for the foreign-trait, foreign-type case: anyone may write one; it changes no code that does not name it (design, not built).
- *Delegates* for split-core packages (StaticArrays for StaticArraysCore), as data.
- *What is refused* is exactly: a method of a function you do not own, for types you do not own, that would change what someone's compiled code computes. Measured on the CSV, DataFrames and CairoMakie stack: 65,318 methods checked, 837 pirates by the letter, none refused (`g2strict`); E2: no pirate wins at any fact of the demonstrators.

### 5.2 Then the default: rule P as the relaxation

Step 3 is a switch. With it off, a winning pirate is followed, as plain Julia follows it: the code with a fact where it wins recompiles against it, once; a pirate that loses changes nothing (S6, Lemma D). The compiled code is the same in both settings; only what happens at a pirate's definition differs. In every load sequence measured, no pirate won, so the default has so far given up nothing in practice: 0 CodeInstances lost over twelve loads in any order, with the mode off.

The notes should state the guarantee in two tiers and say which the default session gives:
- **strict:** invalidated only by a stakeholder's change (static, per environment that loads without a `PirateError`; modulo the named gaps);
- **default (rule P):** invalidated only by a stakeholder's change or a pirate that wins at one of its facts; whether one does is an empirical property of the environment, so far always "none".

### 5.3 What the relaxation gives up, precisely, and whether it is separable

Revisiting §2.6 with strict mode as the base. Rule P gives up:

1. **The kind of guarantee.** Strict: a theorem about every environment that loads. Default: a measurement about the environments tried. "Practically never" is the second; it is a true statement about the evidence, not a property of the design.
2. **Who learns, and when.** Strict: an error at the pirate's definition or load, naming the method and the trait code (and the pirate's package loses the method for its plain users too; that is the point, and the friction). Default: a silent recompile, as today, visible only with `--trace-compile` or snoop tooling; the trait library's author never learns that a pirate changed its code's behaviour.
3. **Trusting package images.** Strict with piece 15: a pirate loaded before an image is an error, so an image's facts, once validated, are not discarded by any later non-stakeholder. Default: an image's facts are revalidated at load as Julia does today and recompiled where a pirate wins; the cost of validation exists either way, the outcome differs (error against recompile).
4. **What is order-independent.** Default: the *set of methods* is order-independent (every load succeeds; Rust's coherence motivation, "any two crates must combine"); only *when* code compiles depends on order. Strict without the symmetric lint: the set of methods depends on order (a pirate loaded before trait code is followed, after it is refused); compiled code's validity does not. Strict with the lint (`verify_main`, §4 of `strict-mode.md`): neither depends on order, at the price of an error in the "before" order where plain Julia would run.
5. **Nothing else.** G1 holds in both; steady-state speed, fresh-session numbers and the validated G2 for stakeholder-free loads are identical; images are the same bytes.

**Can it honestly be presented as a later, separable choice?** Yes, under five conditions, all checkable:
- (a) strict mode changes nothing at run time or in compiled code (**verified**, `strict.jl`; the mode is a property of the session or application, not of images);
- (b) the design's correctness (G1) and the demonstrators' headline numbers do not rely on it (**verified**: `g2all`, the rows, all with the mode off);
- (c) the notes state both tiers and name the default as the weaker one, with the evidence that the gap has not opened;
- (d) the gap between the stated strict guarantee and the prototype (§2b) is either closed or listed as such wherever the guarantee is claimed, so the thesis does not claim a guarantee no build provides;
- (e) the interaction with the `all` setting is measured before strict becomes a user-facing default anywhere: with all code compiled by facts, every compiled fact in Base and every package is in scope, and the 837 pirates by the letter in a common stack (OffsetArrays' 12 pirates of Base among them) may win at some of them; `g2strict` only counted trait-world facts. **Not measured; a to-do, not a result.**

A sixth point is a design question, not a condition: the "before" order. Strict mode alone gives "never invalidated by a pirate" but not "never affected by a pirate" (a pirate loaded first is followed). The framing must say which it claims; the symmetric check as a build lint is the current answer, and it should be in the overview, not only in the exploration.

### 5.4 What this ordering commits the design and the prototype to

Today strict mode is "adopted as an option; intended design deferred" (`decisions.md`; `open-issues.md` §1.1; `strict-mode.md` §2b). Putting it first turns the deferred list into the definition of the thesis. What is not done, and what each needs:

| # | Gap between the stated guarantee and the prototype | Needed | Status |
|---|---|---|---|
| 1 | A pirate loaded before a trait package's image: validation rejects the image's facts, code recompiles following the pirate | **piece 15:** image validation reports the edge and the winning method; strict mode errors instead of recompiling | Julia, small (`Compiler/src/reinfer.jl`); not started |
| 2 | Dependence through native code (`return_type` folds, the machinery's exempt functions): the prototype checks direct callers only; the safety net catches misses after the fact (0 misses so far) | **piece 14:** a read-only "which CodeInstances would this definition invalidate" query, transitive, before activation; replaces the backedge walk and the safety net | Julia, small; not started |
| 2′ | A second trait library extending the machinery's registries | `twolibs` as an acceptance check (0 of 7,461 lost, measured once) | TraitWorld; not in the suite |
| 3 | Package extensions and Requires blocks of stakeholders, activated by unrelated loads, with methods at facts without their triggers' types | the extension rule (refuse), **or** a decision that a parent's own extension overriding its own method is "the code changing" and is admitted; either way the case named in the guarantee | design decision, then TraitWorld |
| 4 | `Base.delete_method` bypasses the definition hook | **piece 1′:** a deletion hook; refuse deletions by non-owners | Julia, small |
| 5 | Bindings: a `const` or global redefined from another module (`Core.eval(Other, …)`), invalidating code that read it (S7) | extend "pirate" to bindings (a binding belongs to its module's package); a binding-definition hook, or accept as an edit and say so | design; not in the theory |
| 6 | The exact attribution of the defining package (`@eval Base …` from a package; Revise) | piece 1's loading context | Julia, small |
| 7 | The session as owner: a user's `Base.abs2(::Float64)` at the prompt is refused when it would win at a trait fact | nothing to build; a stated cost (interactive monkey-patching of Base) and a per-session switch | documentation |
| 8 | Strict mode under the `all` setting (the pivot's switch): scope grows from trait-world facts to every compiled fact | `g2strict` repeated with `--compile-by-facts=all`; a decision whether the flag has a `strict` form | measurement; not done |
| 9 | Indexes for the check (prediction 7: no scan of all methods): today 0.49 s to walk 837 pirates, 0.16 s to check 65,318 methods at a 4.1 s load | acceptable now; an index by function and type if it grows | TraitWorld |
| 10 | Edits remain the one exception, including Revise and dependency upgrades | nothing; stated | — |

Items 1, 2, 4 are the Julia pieces the pivot's plan (§5 of `2026-10-17-policy-in-compiler-plan.md`) must keep or add: it keeps piece 1; pieces 1′, 14 and 15 are not in its table and would join the first upstream proposal. Items 3 and 5 are design decisions the ordering forces now, because the guarantee's sentence must name its exceptions.

### 5.5 Outline (revised)

1. **Problem statement**, two sentences: Julia compiles per concrete argument types and caches; the cache does not stay valid, and what it holds is compiled for more than it needs.
2. **Problem 1: compiled code does not stay valid**, with the S1-shaped example (a hook on your own type invalidates plain callers), 769/0, the ad-hoc session, CSV × DataFrames 2.5 s; package images cannot help.
3. **Problem 2: code cannot say what it needs**: concrete carries everything, abstract promises nothing checked and speculates over today's methods; nested types against `Any`; the latencies, the 3,553-character type, errors deep inside; no list of targets for a binary.
4. **The guarantee** (5.1), then the three steps that force it: facts (with the price), ownership and Lemma O, refusal. Then what still invalidates (the named list). Then extending and hooking under it (conformances, hooks on own types, named implementations, delegates; what exactly is refused; 837 checked, none refused).
5. **The default** (5.2): the switch off; rule P; same code; the evidence that the gap has not opened; the two tiers.
6. **Traits, for problem 2 and for the price of step 1**: contract, keys, `Dynamic` with witness dispatch and declared results, definition checking; the recovery and load-independence numbers.
7. **AOT** as a consequence of declared targets (not of the facts).
8. **What is new over discipline**, with the baselines.
9. **What is not claimed**: no change to results beyond A3 (wider under `all`); "never" is the strict tier and the prototype lacks items 1–5 of 5.4; no "once for any type"; "explosion" not measured as volume; binaries not rebuilt; strict under `all` not measured.
10. **What Julia must provide**: the compiler mode (A), pieces 1, 1′, 14, 15 for the guarantee, 3 and 17; (B)/(C) only if the measurement says so.

### 5.6 Draft: the first ~40 lines (revised)

```
# Traits for better Julia

Julia compiles a method for the concrete types of its arguments and caches the result. Two things
go wrong with that cache. This design fixes both, and each fix needs the other.

## The problem

**1. Compiled code does not stay valid.**
- Compiled code depends on the method table: on which methods match at the signatures inference used.
- Where inference ran at an abstract signature, it depends on every method that matches there. Any
  package that adds a method for its own type changes the answer, and the code is discarded. No
  piracy is involved: `Base.show(io, ::MyType)` in MyPackage invalidates every caller compiled at
  `show(::IO, ::Any)`-shaped signatures.
- On Julia 1.12, `using CairoMakie` discarded code at 769 signatures, none of them concrete. With
  DataFrames loaded, CSV's first read takes 2.5 s instead of 0.19 s. Package images cannot help:
  the code they hold is discarded the same way.

**2. Code cannot say what it needs.**
- A field or an argument is typed either concretely (compiled per type, carrying every part of the
  value, read or not) or abstractly (`Vector{AbstractVector}`: one copy, every operation a dynamic
  dispatch, inference speculating over the methods that exist today).
- Libraries choose per field between nested types (SciML: a new callback recompiles the solver,
  0.84–0.96 s; an integrator type of 3,553 characters) and `Any` (Makie's attributes). Nothing checks
  what an abstract type promises; mistakes surface deep inside the library, printed at full type.

## The guarantee

> **Compiled code is never invalidated unless code it depends on changes.**

"Code it depends on" is the packages that own the function or a type in one of its call signatures,
and their extensions. Nothing else can touch it: not a load, not a package adding methods for its own
types, not a pirate. Three steps make it true; each forces the next.
1. **Compiled code depends on the method table only through facts at concrete signatures:** "at
   `foo(::Int)`, dispatch selects this method." A call at abstract types dispatches at run time, as
   plain Julia's dynamic dispatch does. Nothing else is recorded; nothing is skipped. This is forced:
   an edge at an abstract signature is broken by any owner adding a method for its own type, and
   there is nobody to refuse. Its price: that call's result is `Any` where plain inference typed it.
2. **At a concrete signature only a stakeholder or a pirate can change dispatch.** A stakeholder owns
   the function or a type in the signature; its change is the code changing. A pirate owns neither.
   Julia already has the name, type piracy; here it is the one way an unrelated package could change
   what compiled code computes.
3. **A pirate that would win at a fact of compiled trait code is refused** when it is defined: at the
   prompt, by `include`, or as a package image loads. The error names the method and the code it would
   have changed. The method does not exist for plain Julia either, so a call still computes what plain
   Julia computes. Hooks on your own types (`show`, `sum`, a conformance) are never refused.

Measured on CSV, DataFrames and CairoMakie: 65,318 methods checked, 837 pirates by the letter, none
refused; twelve packages loaded before or after trait code discarded none of it.

**The default session leaves step 3 off:** a winning pirate is followed, as plain Julia follows it, and
the code recompiles once. The compiled code is the same either way; so far no pirate has won.
```

(The 16 s figure of §3's draft is dropped here for want of a reconciled number; add it back once the overview's 22 s and TraitMakie's 15.7–16.2 s agree.)

### 5.7 Sections of the notes and the register that must change for this ordering

Beyond the list in §3 (which stands), the reordering touches:

- **`README.md`**, first paragraph and "The plan": "a strict mode for pirates is kept as an option" → the guarantee's third step, with the default session named as the relaxation; the upstream list gains pieces 1′, 14, 15.
- **`1-overview.md`**: "The idea" gets "The guarantee" as its first heading (5.6); "Ownership" merges into step 2; pay-off 1's "Loading another package discards it only where that package is a stakeholder of one of its facts, or brings a pirate that wins there" splits into the two tiers; pay-off 4's "Pirates are followed, as in plain Julia" moves to "The default"; Status: strict mode's prototype (32 tests, `g2strict`), the §2b gaps as open items; "What it costs" gains "a refused method is gone for the pirate's plain users too" and "monkey-patching Base at the prompt is refused where it would change trait code".
- **`4-details.md`**: "Ownership → What ownership buys" items 3 and 4 reordered (refusal first, following under the default); "The four rules", rule 3: "Pirates elsewhere are followed" → "a pirate that would win at a fact is refused (strict); the default session follows it"; "The central guarantees": G2 stated in two tiers, with the named exceptions (stakeholders, extensions, bindings, pirates loaded before); "Identical or error → Pirates are followed": the example reversed (the refusal first, then what the default does); a new paragraph on bindings as a dependency class.
- **`3-wrapping.md`**: the sections "Pirates" and "Strict mode, an option" swap roles: "Pirates: refused where they would win" then "The default: following pirates"; "What Julia must provide": piece 1 moves from "strict mode adds" into the core, with 1′, 14, 15; "What this costs" item 3 restated.
- **`2-design-choices.md`** §6 ("Ownership, and who may implement"): "Sealing enforces the rule at load" is gone; strict mode's refusal at definition is what enforces it; the Rust coherence comparison gains the order-independence trade of 5.3 item 4; "What the choices cost" item 2 ("A stranger's piracy refuses a load") returns in its strict-mode form, with the measured friction (none in the stack tested).
- **`wrapping-by-facts.md`**: Theorem 2 gains the corollary "under strict mode, case (b) is refused, so a CodeInstance is invalidated only by (a) and (c)"; "Decisions for the user" item 2 ("follow plain Julia … or the strict mode as default") records the new answer: strict is the stated guarantee, following is the default session; "Cost knobs" item 3 updated.
- **`strict-mode.md`**: §2b from "deferred" to the work plan behind the thesis; add bindings (5.4 item 5), the `all` interaction (item 8), the extension-override decision (item 3), the session-as-owner cost; §4 (symmetric check) promoted to the overview's "before order" sentence.
- **`plans/2026-10-17-policy-in-compiler-plan.md`** §5 table: pieces 1′, 14, 15 added as "keep/new"; §0's switch: whether `--compile-by-facts` carries a strict form; §7 a new risk: strict under `all`.
- **`decisions.md`**: the strict-mode row's status from "adopted as an option" to "the stated guarantee; the default session relaxes it (rule P)", with the user's words of 2026-10-18; the "intended design … deferred" row to "planned"; a new row for the ordering decision; the AOT lint row (symmetric check) linked to the "before" order.
- **`open-issues.md`** §1.1 becomes a plan with the table of 5.4; new items: bindings; the extension-override decision; strict under `all`; prompt-level friction and Revise attribution.
- **`other-languages.md`**, "What is new" item 3: "ownership-checked dynamic dispatch" → "ownership-checked method definition: a pirate that would change compiled code is refused where it is defined" (closer to Swift's conformance-registry uniqueness, enforced at the other end); the Rust coherence paragraph: our rule refuses pirates only where they would change compiled code, so most "orphan" methods are allowed.
- **Demonstrator READMEs**: TraitDifferentialEquations row 8 ("strict mode's refusal: deferred") becomes the primary half of the row; TraitReport row 11 and TraitMakie row 2 cite the strict tier; `experiments/facts/g2strict.jl` becomes the headline acceptance check, and `twolibs.jl` joins the suite.

## 4. Files

- This review: `/tmp/claude-1000/review-framing/2026-10-18-framing-and-motivation.md`
- Experiments: `/tmp/claude-1000/review-framing/inval.jl`, `inval-stock.log`, `inval-facts.log`, `explosion.jl`, `explosion-stock.log`
- Sources most relied on: `/home/hellmann/Repos/julia-trait-bound/writeup/notes/1-overview.md`, `4-details.md` (Ownership, The four rules, Keys, AOT), `3-wrapping.md` (Pirates, Strict mode), `writeup/explorations/wrapping-by-facts.md` (Lemma O, Theorem 2, Validation), `writeup/explorations/strict-mode.md` §2b, `writeup/plans/2026-10-17-policy-in-compiler-plan.md` §3, `experiments/factscompiler/README.md`, `experiments/factscompiler/Compiler/src/facts.jl`, `writeup/design-findings.md` §1, `TraitReport/README.md` "Form (t)", `TraitDifferentialEquations/README.md` (PlainODE table), `TraitMakie/README.md` rows 2 and 4.
