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
> - Decisions the trait world makes from the method table are facts too. For example, "type `T` uses the trait's default for `length`" is the fact `D(length, Tuple{T}) = default`.
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
- run-time dispatch and pointer calls record nothing.

*By induction over execution steps:*
- a direct site runs `D_w(s)`;
- a run-time site runs plain dispatch;
- a pointer call runs plain Julia's code;
- an assertion passes the value through or raises.

*Corollary:* G1 depends on no declaration. A wrong performance setting can make code slow, never wrong.

The silent wrong results of review F1 came from an invalidation that was skipped, which P forbids. Lesson 4 is covered too: the default decision is a fact, and the owner adding `length(::T)` changes it, so the code recompiles to the new method.

**Theorem 2 (G2).** A trait-world CodeInstance whose facts are all concrete stays valid under loads in any order, unless a loaded package either:
- **(a)** is a stakeholder of one of its fact signatures: it owns the function or a type occurring in the signature; or
- **(b)** brings a pirate that *wins* dispatch at one of those signatures.

*Lemma D (dominance):* a method that does not win at `s` leaves `D(s)` unchanged, whatever the order of insertion. That gives order independence.

*Lemma O (ownership):* a non-pirate that applies to a concrete `s` is defined by a stakeholder of `s`.

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

Running notes: `session-notes/2026-10-17-24-validating-wrapping-by-facts.md`. Implementation: TraitWorld f558180, julia `trait-world-1.13` 5b5b98758f.

**Verdict.** The design holds. G1 holds up to assumption A3, and G2 holds for both demonstrators with nothing skipped (rule P). Two independent reviews and an adversarial hunt found nine problems, all in the *implementation* of rule R, and all fixed. The cost on general code is small. What remains open is listed at the end.

**G1 evidence:**
- `experiments/facts/acceptance.jl`: 12 of 12 checks. These cover:
  - redefinitions by owners and of helpers;
  - winning pirates;
  - calls into Base, LinearAlgebra and Printf;
  - a more specific method added later at the call signature;
  - recursion through an entry, also with growing types;
  - `return_type` at abstract and widened signatures, and after a redefinition;
  - compile-time evaluation over a run-time site with asserted effects.
- `experiments/facts/hunt/`: 48 adversarial cases (about 125 checks). All pass except one value that plain Julia itself answers in two ways (A3: `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` once folded) and one harness bug.

**G2 evidence** (CSV, DataFrames and CairoMakie loaded before or after):

| | no loads | loads after | loads before |
|---|---|---|---|
| TraitDifferentialEquations, first solve | 57–60 ms | 55–59 ms | 57–60 ms |
| TraitMakie, first PNG | 87 ms | 89–96 ms | 90–97 ms |
| code compiled under the policy that the loads invalidate | | 0 | |
| trait modules and their ordinary layers: code invalidated | | 0 | |

With the old skip predicate the TraitMakie row was 83, 83 and 141 ms. Load order no longer matters.

**Speed:**
- typed trait calls 37 ns (plain 30 ns; 33 ns before the policy); untyped 112–120 ns;
- general code compiled under the policy (a DataFrames/CSV workload no image holds under it): first call 0.58 s against 0.44 s natively, the same steady state. A numeric kernel is within 10%, from calls into separately compiled callees.

**What the implementation of rule R needed** (each a finding; details in the notes):
1. **The entry's hop to the worker.**
   - The entry invokes the worker's CodeInstance under the policy directly (`invoke(f, ci, args...)`, made by a generator for the world it is inferred in).
   - It records the **dispatch fact at the call's signature**, `(sig, ci)`, with the lookup's world bounds.
   - The call is `@noinline`. Julia's inliner resolves `:invoke ci` in the caller's own cache, and would inline native code while dropping its edge (piece 10).
   - The generator throws on re-entry, so that inference gives up without caching.
   - Under threads the generator is not safe, because it runs inference in a pure callback (piece 11).
2. **Owner-aware bare MethodInstance edges** (piece 9). Without them, native invalidation of a shared MethodInstance invalidated code compiled under the policy.
3. **`return_type` is plain Julia's question.**
   - It is folded from native inference at the match's own signature, and only when that answer rests on concrete facts.
   - Otherwise it runs at run time.
   - The policy's own inference types run-time sites `Any`, so it must not answer.
4. **Asserted effects** (`@assume_effects :foldable`, `Base.@pure`) must not license compile-time evaluation over a run-time site: no concrete or semi-concrete evaluation of such a callee, and a constant barrier at the entry. Otherwise the folded value holds no fact for the site.
5. **The policy's compiler runs in a fixed world,** as Julia's own does. Otherwise loads invalidate its native code specialized for the interpreter (seconds after big loads).
6. **TraitWorld's machinery is wrapped by facts too.**
   - Its slow paths (conformance builders, the first-call checks, module finishing) are compiled under the policy and kept in TraitWorld's image.
   - Pure type computations are generated constants.
   - Without this, the abstractly typed reflective machinery was what loads invalidated (2.5 s first solve before).

**Open:**
- **New trait code defined after big loads.** Defining a module and its first call cost 2.7 s and 0.8 s, against 1.0 s and 0.09 s without loads. The machinery's rule-2, door and concrete-mode checks stay native for precision, and are reached through run-time dispatch in their own mutual recursion. This is an implementation cost of TraitWorld's checks; the cure is checks in the compiler (piece 7) or a non-recursive walk.
- **Threads:** piece 11.
- **Trimmed binaries** generate the plain call (`--trim`). The policy in a closed world is untested.
- **Loading trait libraries.** The machinery exemption (TraitWorld's functions inferred as usual) can invalidate machinery code under the policy, since trait modules extend `param` and `implementation`. This is sound but unmeasured.
- **The skip predicate and invalidation filter** are now opt-in (`JULIA_TW_FILTER=1`) and can be removed, with sealing, wrappers and declared calls.
- **Strict pirate mode:** E2 with larger code and other stacks.

## Decisions for the user

1. **Adopt "wrapping by facts"** as the design for code written without traits. It replaces trait wrappers, sealing and doors, and drops the layering rule for calls (the trait world may call anything; concrete facts give cache validity).
2. **Pirates:** follow plain Julia, with a recompile only when a pirate wins (the core), or the strict mode as default.
3. **The Julia work in progress:** whether to stop pieces 2 and 6 and redirect the effort to the trait-world compiler policy and native code for its CodeInstances.
