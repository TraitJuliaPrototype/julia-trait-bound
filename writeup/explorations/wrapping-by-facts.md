# Using code written without traits: wrapping by facts

Exploration of 2026-10-16 (session 23), for the user's request: "Try to come up with a much cleaner and simpler design for wrapping Julia code that is provably correct. Don't work on the basis of the current design, but do take some of the learnings on board."

## Method

I wrote a brief stating the goals (G1 identical or error, G2 stable cache, G3 closed for AOT, G4 early errors), ten lessons from the prototypes and the review, and four test cases:
- A: Base;
- B: Cairo;
- C: ForwardDiff duals in a solver;
- D: Makie, CSV and DataFrames in any order, some of which pirate Base.

The brief describes none of the current design's mechanisms. Three agents each designed from it alone, from different angles:
- **proof first:** a formal model of method tables, worlds and compiled code;
- **views as snapshots:** per-package method visibility;
- **a minimal trusted base and an FFI-like boundary.**

Their designs are in `writeup/explorations/wrapping-designs/`. All three, independently, arrive at the same core.

## The core: one rule and one prohibition

> **R (concrete facts).** Code compiled for the trait world, and every callee compiled for it, depends on the method table only through *facts* of the form "at concrete signature `s`, dispatch selects `r`".
> - `r` may be a method, "no method", or "ambiguous".
> - Union splitting gives several concrete facts.
> - Which operations a conformance serves by defaults is fixed when it is declared; a later method that would change that is refused (decision 4, session 27; the prototype never recorded it as a fact).
>
> A call site whose argument types are not concrete records nothing and dispatches at run time, in the current world.

> **P (nothing skipped).** No invalidation that the facts call for is ever suppressed. A fact is invalidated exactly when a definition changes dispatch at its signature, and that is Julia's own invalidation for edges at concrete signatures.

Nothing else is needed for correctness: no wrappers, delegates, sealing regions, doors, declared calls, handle types, invalidation filter, or protected machinery.

## What is guaranteed, and why

**Model** (from the proof-first design):
- **Methods** have owners.
- **A world** is a version of the method table.
- **A compiled CodeInstance** holds facts: its edges, taken transitively.
- **A signature is closed** if it is a finite union of concrete signatures.

**Assumptions:**
- **A0:** Julia's compiler is sound with respect to the facts it records.
- **A1:** Julia never under-invalidates.
- **A2:** a call runs in the world current at its entry, as in plain Julia.
- **A3:** results that depend on inference itself, such as the eltype of an empty `map`, are excluded, as plain Julia does not fix them either.

**Theorem 1 (G1).** Trait-world code valid in world `w` computes what plain Julia computes in `w`, with the same effects, or raises.

*Invariant:* every valid trait-world CodeInstance has all its facts true in the current table.

*Every event preserves it:*
- compilation records only true facts;
- a definition, deletion or redefinition changes dispatch only at signatures where it applies and wins, and P invalidates exactly the code with a fact there;
- an image load admits code only if its facts hold now;
- run-time dispatch and pointer calls record nothing;
- a definition that would change a conformance's default decision is refused, so that decision stays true.

*By induction over execution steps:*
- a direct site runs `D_w(s)`;
- a run-time site runs plain dispatch;
- a pointer call runs plain Julia's code;
- an assertion passes the value through or raises.

*Corollary:* G1 depends on no declaration. A wrong performance setting can make code slow, never wrong.

The silent wrong results of review F1 came from an invalidation that was skipped, which P forbids. Lesson 4 is covered differently since session 27: the default decision is fixed at the declaration, and the owner adding `length(::T)` later is refused (an override belongs to the conformance), so no code is left stale.

**Theorem 2 (G2).** A trait-world CodeInstance whose facts are all concrete stays valid under loads in any order, unless a loaded package either:
- **(a)** is a stakeholder of one of its fact signatures: it owns the function, a type occurring in the signature, or a supertype of one (corrected in session 27); or
- **(b)** brings a pirate that *wins* dispatch at one of those signatures.

*Lemma D (dominance):* a method that does not win at `s` leaves `D(s)` unchanged, whatever the order of insertion. That gives order independence.

*Lemma O (ownership):* a non-pirate that applies to a concrete `s` is defined by a stakeholder of `s`, where stakeholders include the owners of supertypes of the types in `s`, and a pirate is judged by the method's own signature (each `Union` member separately). (Corrected in session 27: stated with "the owners of the types in `s`" only, the lemma was false for methods on abstract types.) **Exception:** a package extension counts as its parent but loads with its triggers; its method that applies at `s` without mentioning a trigger's type is loaded by an unrelated package. Theorem 2 holds for loads that activate no such extension (case (c) of 3-wrapping.md).

*Necessity:*
- In cases (a) and (b), plain Julia's own result changes, so no design with G1 can keep the code.
- An *abstract* fact, "the methods matching `S` are exactly these", is broken by any package that defines a new subtype together with a method. That package is no pirate and no stakeholder of anything the code computes with. So concrete facts are necessary and sufficient for this form of G2.

**Theorem 3 (G3).** What a program can reach is finite and listable:
- the fact closure of its entry keys (the edges);
- the run-time sites, each with its argument types.

In an AOT build, run-time sites resolve among the build's methods. The guarantee is relative to the trim verifier for plain code reached through run-time sites or pointers.

**G4** is unaffected: definition checking at archetypes stays a package-level check.

## How the four cases work

| Case | How | Cost |
|---|---|---|
| **A. Base** | ordinary calls; arithmetic, arrays, `sum`, `sort!`, `lu!` on concrete types are concrete facts | as plain Julia on hot paths; printing and promotion paths with abstract argument types dispatch at run time (tens of ns, mostly cold paths) |
| **B. Cairo** | ordinary calls; `CairoContext` is an ordinary value; `ccall` side effects as in plain Julia | none, or about 4 ns per call when compiled as a pointer call (see "Cost knobs") |
| **C. ForwardDiff** | `Dual{Tag,Float64,N}` is just a key type. Its arithmetic is ForwardDiff's own methods, as concrete facts. The solver's Jacobian duals use a solver-owned tag. The user's `f!` is either a key type (compiled per function) or a pointer call (`DynamicFn`). | as plain Julia. No library-owned dual type and no ForwardDiff wrapper are needed |
| **D. Makie, CSV, DataFrames** | nothing is refused; only stakeholders of fact signatures, or pirates that *win* at them, invalidate trait-world code | expected near zero (see the evidence below); a winning pirate costs a recompile, which G1 requires |

## What changes against the current design

**Gone:**
- **The layering rule for calls.** "The trait world uses only itself" served cache validity; concrete facts now serve it, so trait-world code may call any Julia code.
- **Trait wrappers, delegates, sealing regions, doors, `@call`/`@handle`.**
- **The invalidation filter in both halves,** and the machinery's protection.
- **The library-owned dual type** (TraitDifferentialEquations step 3), and the pending decision about conversions in wrappers.

**Kept:**
- traits, conformances, keys, entries, workers per key;
- `Dynamic{X}`;
- definition checking (G4);
- explicit conversion in an ordinary layer, now as a style rather than a rule.

`Callable` and `DynamicFn` become what they really are: a choice of calling a function by pointer, so that the solver compiles once per signature rather than per function. That choice is about performance, not about correctness.

**Ownership** stays, as the explanation of who can invalidate code (Lemma O). It no longer requires refusing anything. Strictness about pirates becomes an optional mode.

## Cost knobs

None of these affects G1:
1. **Callees that are not closed.** Base code compiled for concrete keys can still contain abstract sites (`@nospecialize` printing, `Any` fields, keyword sorters, promotion). R compiles such callees in the trait world's own cache, where the abstract sites become run-time dispatch (the default). Alternatively a call site becomes a **pointer call** into plain Julia's own compiled code: about 4 ns, no inlining across it, result asserted.
2. **Admitting a package** (FFI design) or adding it to the platform (views design) only decides what is inlined. Under the default it is unnecessary.
3. **Strict pirates** (views design), an optional mode. Code compiled for the trait world sees only the methods of the packages its key depends on. Where a pirate from outside would win at a dispatch it performs, that dispatch raises `HiddenMethodError` rather than recompiling against the pirate. This turns lesson 3's recompiles into rare, named errors, at the price of per-package method visibility. Not part of the core.

## What the runtime must provide

1. **A trait-world compiler policy.** An `AbstractInterpreter` with its own CodeInstance owner that records only concrete facts and compiles abstract sites as run-time dispatch. A sysimage instance whose edges are already concrete can be reused as it is.
2. **Native code for that compiler's CodeInstances in package images, and in trimmed builds.** Today Julia saves only inferred code for external interpreters (runtime.md §2). This extends piece 5 of `julia-support.md`, and is the one deep piece.
3. **Almost nothing for invalidation.** For edges at concrete signatures, Julia's own invalidation is exact (experiment E3 below). One fix is needed, since a second cache owner shares MethodInstances with the native one: a *bare* MethodInstance edge must be broken only by a CodeInstance of the caller's own owner (`julia-support.md` piece 9, found in validation, see below).
4. **Optional:** the pointer call with a re-resolving trampoline (`@cfunction`-like, exists today), and the insertion hook for the strict-pirate mode.

**Consequence for the Julia work in progress** (pieces 1–6 of `julia-support.md`):
- **Piece 2,** the invalidation policy hook, and **piece 6,** the dispatch check, are not needed under this design.
- **Piece 1,** the definition hook, is needed only for the optional strict mode and for diagnostics.
- **Pieces 3, 4 and 5** stay useful, and piece 5 grows to cover the trait world's own cache.

## Evidence (2026-10-16, stock Julia 1.13.2; `experiments/facts/README.md`)

**E0: what invalidated ODECore.** With CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations, the two chains that reached ODECore started at abstract edges: TraitWorld's printing (`_show_key(::IOBuffer, ::Any)`) and `promote_type(::Type{Int64}, ::Type)`. No chain started at a concrete fact. TraitMakie's mostly concrete code was not invalidated at all.

**E3: is stock invalidation exact at concrete signatures?** Yes, in all nine cases tested:
- a new method invalidates the caller if it wins at the signature (more specific, `AbstractFloat`, a `Union`) or makes the call ambiguous;
- it invalidates nothing if it loses or does not apply.

So rule P is Julia's own behaviour, and no predicate is needed.

**E2: winning pirates.** The demonstrators' closure, after their workloads ran with the D stack loaded first, has:
- 3,533 CodeInstances, 3,043 concrete facts and 207 abstract facts;
- **0** concrete facts at which dispatch selects a pirate from outside Julia.

The stack brings OffsetArrays' 12 pirates of Base, and StatsBase's and Durations'. None of them wins anywhere the demonstrators' code calls. Following plain Julia costs nothing here, so the strict mode is not needed as a default.

**E1: abstract sites on hot paths.** 42 methods hold the abstract facts, and 6 of them were sampled at all (94,426 samples over 30 runs of the work).
- The only measurable one, at 1.6%, is TraitWorld's declared-call path to Cairo (`invokelatest` plus a result wrapper). Under this design Cairo calls become direct, so that site disappears.
- The rest is cold machinery (building `Dynamic` values) and reflection or printing paths in Base.

The demonstrators' hot loops consist of concrete facts only.

**Limits:**
- two small libraries and one stack of packages;
- "hot" means sampled time in these workloads.

E2 should be repeated with larger trait-world code (more of Base) and other stacks, before the strict mode is ruled out for good.

## Validation (session 24, 2026-10-17; patched 1.13.2, no skip predicate)

Running notes: `session-notes/2026-10-17-24-validating-wrapping-by-facts.md`. Implementation: TraitWorld (final commit of session 24), julia `trait-world-1.13` 5b5b98758f. Experiments: `experiments/facts/`.

**Verdict.** The design holds, under the assumptions and rules below.
- **G1** holds up to A3 and A4.
- **G2** holds for trait-world code: nothing compiled under the policy was invalidated by any load tested, with nothing skipped (rule P).
- **Reviews:** three reviews and an adversarial hunt found problems, all in the *implementation* of rule R and the machinery, and none in the design. Each was reproduced, fixed and turned into a check.
- **Costs:** small on general code. What remains is TraitWorld's own machinery for *new* trait code after big loads, a cost for Julia piece 7.

**Assumptions, made explicit by the validation** (beside A0–A3):
- **A3, scope:** every value decided by inference precision, not only empty `map`s. This covers `return_type`, `promote_op` and the element types of broadcasts, comprehensions and LinearAlgebra destinations. Plain Julia itself answers these differently in different contexts: `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` once folded. The policy matches plain Julia wherever it can do so without a G2 cost: acceptance G1.8, G1.9 and G1.11, and every hunt case.
- **A4, no concurrent definitions:** no method is defined on another thread while trait code is being compiled. The entry's generator runs the policy's inference in a pure callback, where Julia's lock-checked world validation does not apply (Julia piece 11 removes A4).
- **A5, the generator:** a generator that throws makes inference give up on that call without caching anything (Julia's `get_staged`). The entry relies on this on re-entry, and beyond 8 nested generations.

**Rules the implementation of R needs** (each found in validation):
1. **The entry's hop is a fact.**
   - The entry calls the worker's CodeInstance under the policy directly.
   - It records the dispatch fact at the call's concrete signature, `(sig, ci)`, with the lookup's world bounds.
   - The call is `@noinline`. Julia's inliner resolves `:invoke ci` in the caller's own cache, and would inline native code while dropping its edge (piece 10).
2. **A bare MethodInstance edge belongs to its owner.** It can be broken only by a CodeInstance of the caller's own owner; replacing the method still reaches every owner (piece 9). *Lemma:* an interpreter consults only its own cache, so a bare edge, recorded for a cycle partner or an uncached result, stands for a result of the same owner. Tested in G1.15.
3. **`return_type` is plain Julia's question.** It is answered in this order:
   - the policy's own answer, with its facts as edges, when that is a concrete type or `Union{}`. It can differ from plain Julia's answer only through values inference decides (A3): `Union{}` where an abstract site's methods all throw, or a nested `return_type` in the callee.
   - otherwise plain Julia's answer from native inference at the match's own signature, folded with the edge `(sig, native ci)` only when it rests on concrete facts;
   - otherwise the call is left to run time.
4. **No compile-time evaluation over a run-time site.**
   - Asserted effects (`@assume_effects`, `Base.@pure`) can claim foldability over a site the policy dispatches at run time. A fold would then hold no fact for that site.
   - So FactsInterp refuses concrete and semi-concrete evaluation of a callee whose code under the policy has a run-time call. Missing IR, or code not owned by the policy, counts as unknown.
   - The entry also passes such a worker's result through `compilerbarrier(:const)`.
5. **Kinds are facts for closures.** A closure called with kinds (`DataType`, `UnionAll`, `Union`: types passed as values) counts as concrete. Only the closure's owner adds methods to it.
   - Without this, every broadcast had a run-time call in its element-type computation: 176 ns against 15.
   - For other functions a kind-typed fact would be broken by any method admitting a type value (`f(::Type{X})` for any `X`), so unrelated packages could invalidate trait code. Those calls stay run-time sites (G2.1).
6. **The machinery is wrapped by facts too.**
   - Conformances are decided in the caller's world and cached per world. Plain redefinitions and older worlds are followed (G1.13, G1.14).
   - Its slow paths are compiled under the policy and kept in TraitWorld's image.
   - Pure type computations are generated constants.
   - The policy's compiler runs in a world fixed at TraitWorld's initialization, and a hit in the policy's cache runs no compiler code. Otherwise loads, before or after, made Julia recompile the compiler's code for the interpreter.
7. **The machinery exemption** (TraitWorld's own functions inferred as usual) is sound by rule P. Theorem 2's premise does not hold for those CodeInstances, so G2 for the machinery is empirical: 0 lost when a second trait library loads (`twolibs.jl`).

**G1 evidence:**
- `acceptance.jl`: 16 of 16 (with G2.1). It covers:
  - redefinitions;
  - winning pirates;
  - Base, LinearAlgebra and Printf;
  - a more specific method added later;
  - recursion through entries, also with growing types;
  - `return_type` in four forms;
  - asserted effects;
  - generic conformance after a redefinition;
  - an older world;
  - a cycle's deep callee.
- `hunt/`: 48 adversarial cases, all passing except a harness bug.
- **Image loads:**
  - `pirate_before.jl`: a Base pirate defined before the image loads is followed.
  - `fold_image.jl`: a precompiled trait package with a winning method defined before it loads matches plain Julia in every order.

**G2 evidence:**
- **Load sequence** (`g2all.jl`). Both trait libraries work first. Then the following load one at a time, with work after each: CSV, DataFrames, CairoMakie, ChurnStorm (100 types with Base methods, and 20 redefinitions), BasePirate, OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations and StaticArrays.
- **Result:** every CodeInstance compiled under the policy is counted, in any module. **0 lost after every load**; work 9–15 ms after each load.
- **"Before" order:** the same 7871 facts-owned instances are valid as without loads, and the first work takes 147–153 ms, as without loads.

| | no loads | loads after | loads before |
|---|---|---|---|
| TraitDifferentialEquations, first solve | 57–60 ms | 55–60 ms | 57–60 ms |
| Rodas5 with ForwardDiff's `Dual`, first solve | 72–74 ms | 75 ms | 77 ms |
| TraitMakie, first PNG | 87 ms | 89–96 ms | 90–97 ms |

**Speed:**
- typed trait calls 37 ns (plain 30); untyped 111–116 ns;
- under the policy: a broadcast 15.0 ns against 14.7 natively, `map(sin, v)` 27.5 against 24.1;
- a DataFrames/CSV workload no image holds under the policy: first call 0.60 s against 0.45 s natively, steady state within 10%.

**Open:**
- **New trait code after big loads.**
  - A new key costs 855 ms against 360 ms without the loads; defining a module and its first call 2.7 s and 0.8 s, against 1.0 s and 0.09 s.
  - The causes: TraitWorld's rule-2, door and concrete-mode checks are native, for precision, and reached by run-time dispatch in their mutual recursion. Also, the compiler's code for the interpreter fails verification after loads once per session (piece 12: a frozen world for an external interpreter's compiler).
  - The cure is the checks in the compiler (piece 7), or a non-recursive walk, plus piece 12.
- **A4:** piece 11.
- **Trimmed binaries** generate the plain call (`--trim`). G3 under the policy is not validated.
- **Coverage and allocation tracking** skip foreign-owner CodeInstances (`needs_instrumentation`), so code under the policy runs uninstrumented.
- **Latent:** the CompilerPlugins `typeinf_edge(::FactsOwner)` hook is never called by 1.13. If it were, a facts frame could join a native call stack, and rule 2's lemma would need revisiting.
- **Depth 8:** trait-to-trait nesting deeper than 8 generations leaves dynamic calls.
- **Removable:** the skip predicate and invalidation filter (opt-in now, `JULIA_TW_FILTER=1`), sealing (its load scan still warns about pirates), wrappers and declared calls.
- **Strict pirate mode:** E2 with larger code.

## Decisions for the user

1. **Adopt "wrapping by facts"** as the design for code written without traits. It replaces trait wrappers, sealing and doors, and drops the layering rule for calls (the trait world may call anything; concrete facts give cache validity).
2. **Pirates:** follow plain Julia, with a recompile only when a pirate wins (the core), or the strict mode as default.
3. **The Julia work in progress:** whether to stop pieces 2 and 6 and redirect the effort to the trait-world compiler policy and native code for its CodeInstances.
