# Alternatives considered

Designs that were tried, rejected or replaced, by topic. Each topic says what the design was, why it went, and what took its place. The current design is the [references](../reference/README.md), with the rationale in [`../design.md`](../design.md); nothing on this page is current unless it says so.

Dates and sessions are given briefly ("s23" is session 23). The register's superseded rows, with their full wording, are in [`../decisions.md`](../record/decisions.md#superseded-withdrawn-and-retired); closed issues are at the end of [`../open-issues.md`](../open-issues.md#closed-items). The notes before 2026-10-19 (four rules, layering, sealing, representations) are in [`../../attic/writeup/notes-2026-10-18/`](../../attic/writeup/notes-2026-10-18/), and the order in which things happened is in [`../record/design-history.md`](../record/design-history.md).

## Contents

- Representations and projections, replaced by keys
- Layering and its workarounds: interface packages, trait wrappers, calls upward, doors, replaced by the facts rule
- Seven rules, then four, then three
- The facts policy as package code, replaced by the facts mode in Julia's compiler
- Code in the wrong owner
- Facts at non-public functions, dropped
- Asserted effects: three rules in turn
- The invalidation filter and other Julia pieces, reverted or moot
- Dynamic values: pointer tables and witness tables, replaced by the call-site split
- Named implementations by module, deferred
- Strict mode: variants not chosen
- Sealing, rejected
- Stock Julia support, dropped
- The inliner changes: a facts-only form, then a narrower general form
- Concreteness required for every trait, made opt-in
- Overrides: followed or refused
- `Callable` with one mode, rejected
- `Callable`'s modes and the opening of `Dynamic` at every bound, replaced by `Compiled` and `Dynamic`
- Storage as always `Dynamic`, and `stored`, replaced by values that carry through storage
- Automatic differentiation by a library-owned dual number, superseded
- Other options considered and not taken
- Plans, thresholds and settings superseded
- Claims withdrawn
- Terms retired
- Split packages: restructuring, or implementations, instead of joint owners

---

## Representations and projections, replaced by keys

**What it was (until s22, 2026-10-16).** An implementation projected the user's value onto a *representation*, by any projection, computed or copied, with a written inverse (`unproject`). Library code was compiled per representation, and per type only by choice. The research of `../record/other-languages-research-2026-10-16.md` (s22) describes this form in its "Ours" column, and counted "projection as an enforced position" as new.

**Why it went.** Computed projections copied, needed inverses and stale views, and packed several fields into one type.

**What replaced it (6c7f088, adopted s22, built s23): keys.** Code is compiled for what the bound can see: the receiver type, if any, and the declared fields' types ([traits §6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)).
- Forwarding to a field (`by f`) replaces projections.
- Computed and copying projections and `unproject` are removed. A computed projection is refused at the implementation with "computes a value" (`test/like.jl`; an `ImplementError`).
- A type whose data needs another layout is converted explicitly by the library ([traits §4.10](../reference/traits.md#410-types-that-only-convert)). The representation design did the same implicitly at the boundary, and so hid the copy and needed a written inverse.

**Withdrawn with it (s22):** the held/lens split, the exit check, and the re-entering `Dynamic` of the keys plan's sections 1 and 4 (`../explorations/keys-plan.md` §5), replaced by the reference layout. Checking held parts after each call upward is obsolete under the reference layout, and kept only for an opt-in copying layout ([`../open-issues.md`](../open-issues.md) §2.21).

**Also rejected:** one forwarding field per type, for every trait it joins. What a type means differs between traits.

**What remains of it.** The prototype's projection names and its `{R}` spelling (the receiver type as the trait's last parameter, `@trait ColTable{R}`, `ncols(r::R)`) are still accepted, and used in TraitWorld's precompile workload and many tests; they are to be deleted ([state §6.2](../state.md#62-the-target)). `experiments/interfaces` (the DataFrames and Makie prototype) uses computed projections and is pinned to TraitWorld before keys. `../explorations/makie-rewrite.md` and `../explorations/solvers.md` were written with representations, and each has a banner.

## Layering and its workarounds: interface packages, trait wrappers, calls upward, doors, replaced by the facts rule

**Layering (until s23).** Ordinary code may use the trait world; the trait world uses only itself. This is, word for word, the C++0x rule that helped end definition checking in C++ (HOPL4 §6.2.5; [`other-languages.md` §4](other-languages.md#4-generic-code-is-checked-at-its-definition)). The research of s22 predicted that layering would be attacked for gradual adoption and for scaffolding (prediction 2), and the design answered with wrappers and calls upward.

**Its workarounds, in turn:**
- **Interface packages (rev 1004, 2026-10-14).** Code not written with traits was reached only through an interface package: a trait half with traits, bounded functions and handles, and an ordinary half of declared calls that also hid the outside package's globals. Doors had a direction: outward (logging, display, stdout, as dynamic calls upward without an inference edge) and inward (eval, deserialization, reflection, only as declared calls with a checked result). A trait package sealed itself, and an interface package sealed what it wrapped: a later definition that would pirate a sealed package was refused at precompile, load or definition. The opt-out was plain Julia ([`../design-findings.md`](../design-findings.md) §3; session note 16).
- **Trait wrappers (rev 1058, 2026-10-15; in use in sessions 20–22),** one per package, with implementations as delegates, replaced interface packages. Calls upward (`@call`, `@handle`) and sealing over views (pirates refused at load) went with them. Built in the representation form (`experiments/interfaces`, pinned before keys).

**What replaced them: wrapping by facts (s23, the user: "Full go-ahead for the 'wrap by facts' strategy").** Code compiled for the trait world, and every callee compiled for it, depends on the method table only through dispatch facts at concrete signatures; calls with non-concrete argument types dispatch at run time; no invalidation is skipped. The trait world may call any Julia code. Each callee was compiled into the trait world's cache or called through a pointer into plain Julia's code, a choice that affected speed only. On pirates, the trait world followed plain Julia, with strict mode as an option. Evidence E0–E3; validated in s24 (G1 up to the assumptions A3–A5, G2 for trait-world code with nothing skipped; acceptance 16/16, `g2all` 0 lost; `FactsInterp` in TraitWorld c62efbf). Wrapping by facts is the facts rule of today, moved into Julia's compiler (next topic but one).

**Removed from TraitWorld (s25, b60b126):** the machinery's skip filter, sealing, trait wrappers, declared calls (`@call`/`@handle`), doors, the layering check, the native piracy audit and guard. The patched Julia kept the hooks, opt-in, until pieces 2 and 4 were reverted.

**Why.** The facts rule makes the restriction unnecessary. Trait code calls any Julia code directly, with ordinary values; only the trait object is confined. That is what C++ wanted and could not have with definition checking.

**What dissolved with them:**
- whether wrappers offer conversions for foreign types, once implementations never convert (s23): there are no wrappers;
- in the review of s23 (`../reviews/2026-10-16-wrapping-under-keys.md`): F2 (implementations in ordinary modules have no place in the layering), F4 and F8 (sealing), F5 (the wrapper's role for foreign types), F7 (opaque values handed down);
- prediction 2 of `../record/other-languages-research-2026-10-16.md`.

## Seven rules, then four, then three

- **Seven rules** until rev 1110 (2026-10-15), with interface packages ([`../design-findings.md`](../design-findings.md), header).
- **Four rules** (rev 1110 to s29): layering for calls, the boundary (rule 2), ownership (rule 3) and views and placement (rule 4). The "trait world" and "ordinary code" were worlds.
- **Rule 4, retired (s29, change 1 of `../reviews/2026-10-18-decisions-revisited.md`).** "Views and placement: compiled code is compiled against its owners' view and lives where the type was chosen." Both halves are Julia's own behaviour: what a call sees, and where compiled code lives ([traits §6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)). Rule 4's early binding had been meant as a deliberate choice, paying the price C++0x's `merge` and `copy` showed (Siek; prediction 10 of `../record/other-languages-research-2026-10-16.md`). Under the facts rule a stakeholder's later method breaks the fact and recompiles, as in plain Julia, so the prediction dissolves for methods, and "shared compiled code not inlined across packages" (prediction 9) dissolves as a rule.
- **"A trait module may not define a pirate"** became strict mode's refusal of a winning pirate, plus a lint.
- **Ownership's earlier wording (rule 3, s22):** owners are packages, and delegation is by the owner only. Today delegates are data for strict mode, marked transitional; extensions count as their parent; a pirate is judged by the method's own signature (s27, decision 2).
- **Today:** three rules: facts, ownership, the boundary ([the facts mode reference](../reference/facts.md)). The ownership section's long form in the old notes is stated by [facts §1](../reference/facts.md#terms), [the rationale §2](../design.md#2-the-argument-in-four-steps) and [traits §10](../reference/traits.md#10-who-may-implement-pirates-strict-mode); Lemma O is in `../explorations/wrapping-by-facts.md`.

## The facts policy as package code, replaced by the facts mode in Julia's compiler

**The package policy (s23–s28).** TraitWorld carried its own compiler policy: an external `AbstractInterpreter` (`FactsInterp`, in `facts.jl`) with its own cache, run in a frozen compiler world, with view caches per key, warm-ups, site caches and trampolines.
- **View caches per key** gave first calls of about 3 ms in every load order (s21, on 1.12). On stock 1.13.2 with a view cache, `summarize` recompiled for 71–74 ms once CSV and Makie were loaded (3.3 ms in s21 on 1.12); it was unclear whether 1.13 or TraitWorld caused it (`experiments/baseline-1.13.md`). They were deleted with the policy (`viewcache.jl`, TraitWorld c533f3a).
- **Bare invokes and trampolines (s27).** Policy code never ran native code through bare `MethodInstance` invokes: such an invoke named the policy's CodeInstance, or called a trampoline that found or compiled it; the callees were compiled after the outermost inference, so images kept them; calls that only throw kept plain Julia's code; on stock Julia the trampoline called plain Julia's code (a19ba7e, 2e408cc, 1fdc36d). It strengthened G2 for code reached through recursion cycles. Retired in s29 with (B) and (C).
- **The machinery's registries** (`trait_fields`, `projection`, `op_*`, …) were declared with `@max_methods 1` and sentinel methods, so code compiled at abstract types held no edge to them, and trait modules registered with the invalidation filter when they started (s23). The filter half went in b60b126; the `@max_methods 1` pattern stays until piece 7.
- **A closed build replaced the policy's call by the plain call** (s25, found by the first binary; TraitWorld 893f0bb), so that entries from session images were inferred again for the closed world. Retired in s29: an artefact of the generator path, with nothing to replace under (B).
- **Assumptions of the package's interpreter:** A4 (no method defined concurrently with compiling trait code) and A5 (the generator's behaviour). Part (B) removes them; the interpreter is deleted. "Identical or error" now rests on A3 alone.
- **Pointer calls into plain Julia's code** as one of two ways to reach a callee went too: under (C) every callee reached from facts code runs facts code, and the pointer form survives only as `Callable`.
- `verify_main` in a session did not scan the workers behind the policy's `invoke` of a CodeInstance (it counted them as static calls), so only a trimmed build showed them. It now scans `:facts` code by owner (TraitWorld 3db6592).

**Where the policy's compiler code lived (s26).** Julia's Compiler keeps the interpreter in an abstract field (`InferenceState.interp::AbstractInterpreter`), so the compiler code TraitWorld's image held for `FactsInterp` had abstract edges such as `cache_owner(::AbstractInterpreter)`. Any package that defines its own interpreter broke them. REPL defines one (`REPLCompletions.REPLInterpreter`), and in an interactive session REPL loads before TraitWorld, so the image's compiler code failed validation and the first new key cost 5.9 s instead of 0.13 s. GPUCompiler, Enzyme, JET and Cthulhu define interpreters too. Julia's own compiler avoids this by running in `jl_typeinf_world`, frozen at the system image. A workaround, TraitWorld depending on REPL, was not recommended: it fixes REPL but not the other interpreters.

**The policy in the platform (s26, the user), superseded in s28.** The policy's compiler compiled with the system image and run in a frozen compiler world, like Julia's own, as a prototype: a patched system image with TraitWorld in it (`experiments/sysimage`). Measured: with REPL first, a new key's first call 0.22 s instead of 5.9 s; TraitReport's work after OffsetArrays, StatsBase and Unitful 1.7 s instead of 5.4 s; startup 0.125 s against 0.10 s.

**What replaced it: the facts policy in Julia's compiler** (s28, the user; plan `../plans/2026-10-17-policy-in-compiler-plan.md`): (A) facts as a mode of Julia's own inference, (B) a second cache owner, (C) owner-aware dynamic dispatch, with (A) measured before committing to (B). (A) was first a forked Compiler package (`experiments/factscompiler`), then ported in-tree in s29 (julia-1.13 880ae49dad, c3415abde6), with (D) added. TraitWorld's own policy and its interpreter code are deleted (TraitWorld c533f3a). The checks use Julia's `NativeInterpreter`, run in the compiler's world (julia-1.13 bb82a82bbf, TraitWorld f79727c), so no package defines an interpreter that REPL's could break.

## Code in the wrong owner

The facts mode makes "who compiles this code, under which rules" a property of each method. Before each piece of code had the owner it needs ([`performance.md`](performance.md#1-every-piece-of-code-has-an-owner-and-its-performance-follows-from-the-owner)), code in the wrong owner caused most of the large regressions:

| Code | Owner it had | What that cost | Owner it has now |
|---|---|---|---|
| The compiler, called from facts code (TraitWorld's checks) | `:facts`: everything a facts frame calls was compiled by facts | the abstract interpreter ran as type-unstable facts code, 6× slower | plain, whoever calls it (module flag "never by facts" on Compiler) |
| TraitWorld's machinery (checks, finding builders, hooks) | plain | invalidated by every big load, then re-inferred in a larger method table: 2 s per new implementation | facts (`@machinery`, the per-method mode) |
| The compiler's code for the checks' custom interpreter | plain, run at the latest world | invalidated by loads, JIT-compiled again: 3.7 s | the compiler's own world (a `NativeInterpreter` with its own cache owner; Base reflection runs it in the typeinf world) |
| The first-call check's inference of a worker's call graph | a private cache (`_CheckOwner`) | 3,100 CodeInstances per new key, shared with nothing and never in an image | the code that runs (reflection by facts: shared with the worker's compilation and kept in images; TraitWorld 93c8a08) |

Earlier causes of the same kind, found in s26: the policy's compiler code failing validation when REPL loads first (above), and the machinery's internal functions as native code that large loads invalidate (`@implement` 1.2–1.7 s after loads, 0.6 s without). Moving `@implement`'s expansion and checks under the policy (TraitWorld a5e4778) gained little, because their run-time sites reached native internal functions.

**The piracy guard** (`_check_once`, the prototype's stand-in for rule 4) audited a worker's signature at its first call and after any world change, which cost tens to hundreds of milliseconds after large loads. It was removed in s25.

## Facts at non-public functions, dropped

**What it was (s26, the user).** In code compiled under the policy, a call at abstract argument types of a function that is not `public` (nor exported) in its owner's module was recorded as a fact, as at a concrete signature: only the owner adds methods to its internal functions, and extending another package's non-public function would count as piracy. In implementing it, it was scoped to calls from the same package (TraitWorld 6bcca9f): applied to Base's internals, which packages extend as a matter of course, it let OffsetArrays, StatsBase and Unitful invalidate trait code. With it, `@implement` took 0.09–0.21 s without loads and about 0.52 s after (against 1.2–1.5 s after CSV, DataFrames and CairoMakie, and 0.64 s without, before).

**Why it went (s27, the user: decision 3).** Rule 3 lets a package that owns a type extend another package's internal function at that type, so such facts broke G2: acceptance check G2.1 failed with the rule (`JULIA_TW_INTERNAL_FACTS=1`) and passes without it. The speed it bought came from bare invokes running native code, fixed in s27 (TraitWorld eef27bc; acceptance 16/16). The consistency review of s27 had also found that the rule was in no note, broke Theorem 2's premise as stated, and still recorded Base-internal calls from Base code as facts.

**The alternative recorded with it, (b): run-time dispatch under the policy.** A run-time site looks up and invokes the policy's code for the run-time types, so that dynamically reached code, ordinary code included, is protected too, at the cost of changing "run-time sites behave as plain Julia" and a cost per call. It was built in the package in s28 (TraitWorld 1d93677) and is part (C) of the compiler today.

## Asserted effects: three rules in turn

1. **s28, in the package:** facts fold where Base's asserted effects fold (`../explorations/dataframes-port-lessons.md` 1.2; TraitWorld c62e23e).
2. **s29, the compiler as built:** under the facts mode, asserted effects are trusted only in Base and Core methods, at method and statement level. An assertion over a run-time site let a plain caller fold a facts method's result that no edge records (acceptance G1.10).
3. **Today (the implementation review of 2026-10-19, `../reviews/2026-10-19-compiler-implementation.md`):** no asserted effect applies to a frame with a run-time site. One rule; it also covers a Base method asserted over a run-time site (G1.19; julia-1.13 feaad9e45c, 67f5c0bcc8).

## The invalidation filter and other Julia pieces, reverted or moot

**A global invalidation filter**, ignoring later definitions, is unsound for ordinary code. The prototype's filter was Julia pieces 2 (the invalidation policy hook, the old trait-world filter, both halves) and 4 (the post-inference hook). The facts compiler superseded them, and both are reverted (julia-1.13 c4f7e76a2f); `Compiler/src/reinfer.jl` is upstream's again, and their commits remain in the branch's history (4d8eeebc19 to 87dcf22015).
- What the filter did, measured in s23: it protected code from a definition only if the definer owned no type in the code's signature (review F1, fixed in 280612ed2f; before, a user's redefinition of its own implementation left the worker stale). CSV and DataFrames loaded after TraitMakie invalidated no PlotCore code and 14 machinery methods (285 on stock). CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations still invalidated 2–4 ODECore methods and 323 machinery methods: pirates of Base (OffsetArrays, StatsBase, Durations), which invalidate by design, and owned methods (InlineStrings, Unitful) reaching Base methods compiled for trait-world callers, which the insertion half did not protect.
- Wrapping by facts settled it in s24: with nothing skipped, 0 facts-owned CodeInstances were lost to any of twelve loads, in any order (`../explorations/wrapping-by-facts.md`, "Validation").
- **Better invalidation precision** alone is largely upstream in Julia 1.12, and not enough on its own.

**The Julia work list of s25** (`../explorations/julia-support.md`, "Review for wrapping by facts and strict mode"): drop pieces 2, 4 and 6 (a dispatch check in codegen) from the upstream list; keep 1, 3, 5, 7, 8 and 9–12; add 13 (instrumentation of foreign CodeInstances); no trimming piece for foreign CodeInstances; in the order 10, 9, 11 (through 1.13's declared `CompilerPlugins.typeinf` hook), 12, 5, 13, 1, 3, then 7 and 8. The first upstream proposal was to be "first-class foreign cache owners" (5, 9–13). Superseded in s29 (change 9 of the decisions review) by the work list of [the compiler reference](../reference/compiler.md).

**Pieces 11, 12 and 13 are moot,** artefacts of the external interpreter. Piece 11 was deferred in s27 over two obstacles: 1.13's `typeinf_edge` cannot join a policy frame to a native caller's stack (so the replacement ran the owner's inference synchronously), and the barrier for asserted effects over run-time sites (G1.10) had no place in the plugin replacement (`../explorations/julia-support.md`, last section). Under (B) it is moot. Piece 16 (`@interpreted`) belongs to the deferred AOT annotations.

## Dynamic values: pointer tables and witness tables, replaced by the call-site split

- **Pointer tables, rejected (s22)** for world age, serialization and races. Rust's `dyn` and Swift's `any` call through a table of function pointers.
- **Witness tables and key branches, built in the package anyway (s28; TraitWorld 30527ed, d3bb298).** The review of 2026-10-18 (`../reviews/2026-10-18-design-and-fixes.md`, finding 2) verified the defect: a witness pointer runs in the latest world, not the caller's, so in an older world after an implementation was redefined, a `Dynamic` call through a witness table returned the new method's result. In s29 they were first turned off by default (`JULIA_TW_WITNESS=1` turned them on; the user: "Witness table: Yes"), and then deleted (TraitWorld 3db6592) when `Dynamic` moved to the compiler (the user: "move to the compiler directly"; julia-1.13 f6838f96fc, TraitWorld 703f814). The same defect remains in `DynamicCall`'s pointer ([traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)). Prediction 13 of [`other-languages.md`](other-languages.md#predictions-from-other-languages-and-their-status) records it: the other languages' standard mechanism, tried and dropped.
- **`sealed_call`**, the prototype's exemption for TraitWorld's machinery on the path of a `Dynamic` operation, went with (D): the machinery is not on that path.
- **Dispatch on a `Dynamic` by run-time dispatch alone** (20–80 ns per operation) was replaced by the call-site split.
- **Shared code through witnesses**, Swift's model, one copy for every conforming type: not chosen. It buys sharing with an indirect call per operation and Swift's performance cliffs ([`other-languages.md` §3](other-languages.md#3-compiled-for-what-the-bound-can-see)).
- **The narrowed `Dynamic` (s27, TraitWorld f4b54a5).** `Dynamic{X}` kept only the views of `X` and its supertraits, so the bounds that open it run the workers compiled for what they see (a `Column` made from a `CSVColumn` trait object had compiled new workers for the pair of views). In s29 (change 5) this dissolved into "`Dynamic{X}` holds the user's object". The narrowing is still in the code (`_narrow`, `src/core.jl:358`; [`../open-issues.md`](../open-issues.md) §2, "the design and the code disagree", item 4).
- **The first `Dynamic` (s22):** a kept trait object; operations dispatch; opened at a bound; equality like `AnyHashable`.
- **The boxed copy, replaced by the held view (s29, the user: "Add a lean held view"; TraitWorld 375a930).** A `Dynamic` of an immutable value that is itself the receiver was a trait object pointing to a boxed copy of the value (two pointer chases), with an `o === nothing` branch per read: 1.45–1.61 ns per element in the sum over `Dynamic{Shape}`, and recursion through `Dynamic` at 1.65× plain-closed. The held view holds the value whole: 0.92–1.40 ns, and 1.26–1.31×.
- `Dynamic` operations called through a varargs wrapper were replaced by fixed-arity calls.
- **Behind the split, a table again (2026-10-21, E-145; [compiler §4.3](../reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)).** The split's last branch calls through a table of the call's targets keyed by the value's type. The s22 objections are answered: world age by `:caller_world` pointers (the defect of s28's witness tables), serialization by a session stamp checked on every call, races by states replaced and never mutated. It is in the compiler, not the package, and the split stays in front.

## Named implementations by module, deferred

**What was adopted (the user: "Liberal it is").** Named implementations by module, `via(M, x)`: anyone may write one, it is used only where a caller names it, witnesses are carried by the value ("ColTable via Fast"), and ambiguity surfaces at the call.

**Deferred (s29, change 6 of the decisions review)** until traits are in the type system (Julia piece 7). The simplest `Dynamic`, and membership as subtyping, have no place for a witness inside the value. The preferred form, when it comes, is a value-level wrapper that conforms, a newtype: `Via{Fast}(x)` ([traits §15](../reference/traits.md#15-named-implementations)).

**Rejected: selecting implementations by imported scope,** as Scala's implicits do. An entry is compiled once and does not know its caller's module.

## Strict mode: variants not chosen

- **`HiddenMethodError` at calls** that would select a pirate from outside the code's dependencies (the views design), rejected in s25. It was the first reading of the user's request; a hostile review found that it needs a second cache, checked run-time calls and a cache owner per mode, and reduces no invalidation (`../explorations/strict-mode.md` §5).
- **"Never invalidated" by a skip predicate** for pirates, rejected in s25: it gives up rule P, and the refusal mode gives the same without it (`../explorations/strict-mode.md` §5).
- **Strict mode as the default:** not chosen for now. The default session follows pirates, and strict mode is the stated guarantee's switch ([the rationale §2.5](../design.md#25-the-default-following-pirates-and-what-it-gives-up)).
- **Strict mode as an option only (s25)**, then the base of the framing (s29, the user: "Strict mode first for framing is yes"). The s25 statement: a method definition (at the prompt, by `include`, or an image's methods at load) is refused if it would win at a concrete fact held by trait-world code and its package is not a stakeholder of that signature; trait-world code is then never invalidated by a pirate; G1 holds; nothing changes at run time; if pirates never win, it never errors. The user: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error." Prototype: TraitWorld 7b328a5 (`src/strict.jl`), 32 tests; `g2all` refused nothing, 0 misses; +0.54 s on a 4.1 s load of CSV, DataFrames and CairoMakie.

## Sealing, rejected

**What it was.** Sealing a package against later pirates (interface packages and trait wrappers, above). Later, the facts-mode recovery test (`../plans/2026-10-17-policy-in-compiler-plan.md` §3) suggested sealed abstract types and sealed functions, so that calls at abstract types become facts.

**Rejected (s28, the user).** The notion should leave the project entirely. One should not seal an abstract type but use a trait instead: the trait's declared signatures and result types, checked for every implementation, are the closed contract. The `isa` branches plain Julia emits over a known set of methods come from the call-site split instead: an operation on a `Dynamic` value branches over the registered implementations (at most four) and falls back to a dynamic call. TraitWorld's `sealed_call` exemption for its own machinery went with (D) ([`../open-issues.md`](../open-issues.md#closed-items), 2.26).

## Stock Julia support, dropped

**What it was (s23).** The move to Julia 1.13.2: TraitWorld ran on stock 1.13.2 and on the patched build (`julia-1.13/`, a worktree of `julia/` on `trait-world-1.13`, built in s23). On stock, strict mode's 32 tests and the hook tests were skipped (343 tests patched, 308 stock, in s25; 364 and 319 in s27), and overrides after an implementation were refused at checkpoints (declarations, a trait module's end, a signature's first call, `check_overrides`) rather than when the method is defined, which needs a hook at method insertion.

**Dropped (s29, the user; plan P-b).** TraitWorld requires the patched build; its stock-only paths go. Stock Julia appears only as a baseline, and says so. The checkpoint `check_overrides` remains in the code beside the definition hook (`TraitWorld/src/hooks.jl`, `_override_violation`).

## The inliner changes: a facts-only form, then a narrower general form

- **First, under facts only (s29, the performance phase).** An invoke kept the fact signature: the inliner did not widen a non-inlined call to its compileable signature in facts code (julia-1.13 da4726c5cc); and an inference cycle's members inlined each other in facts code only (4102b7a7a7), so that the plain baselines stayed stock, although it would help plain recursions too. As written, the first overrode `@nospecialize` for non-inlined calls from facts code and missed concrete-`Vararg` facts. The general form proposed for upstream: prefer an existing exact specialization.
- **The first version of the performance note said both were harmless in plain Julia** and needed only a facts version. The review (`../reviews/2026-10-19-performance-phase.md`, A1, verified on stock 1.13.2) showed otherwise: a varargs `@inline` wrapper inside a two-type recursion runs 56× slower in plain Julia too (22.5 ms against 0.40 ms, 16.8 MB against 0 bytes), with the same `Vararg{Any}` specializations.
- **Ungated (the user: "Apply to all code"; julia 61852d8fb1).** A first general form, "keep any exact specialization inference made", crashed the system image build: an exact specialization at a non-concrete signature is not code to call. Restricted to dispatch tuples, it then also overrode Julia's widening of kinds (a `Type{Float64}` passed to a `::DataType` argument), the review's B2: that changed what the certificate sees and grew the system image by 2.2%. The final rule keeps the exact specialization only when the compileable signature merely widens a varargs tail; the system image grows 0.4%. So the plain baselines are patched-plain, and stock comparisons use the stock binary.

## Concreteness required for every trait, made opt-in

- **What it was:** the prototype required concreteness for every trait and checked every field of the receiver type, declared or not (review of s27, `../reviews/2026-10-17-consistency-fresh-eye.md` §1). The sentence "a `DataFrame` cannot conform, since it is not deeply concrete" (TraitReport README) stated that prototype limit.
- **The options:** (a) required by default with a per-trait opt-out, matching the prototype and pay-off 3 as then stated; (b) opt-in as written, with the check narrowed to the key. (b) was recommended, since nothing in the facts proofs needs concreteness and abstract keys are sound as run-time sites. Session 27 measured the independent rationale: column code on `Vector{AbstractVector}` loses compiled code to loads (PlainTables loses 17 of 49 methods), `Vector{Dynamic{Column}}` loses none.
- **Decided (s27, decision 1; the user: "Per trait", "silent unless trait sets @warn_on_abstract or @concrete_only"):** opt-in per trait (TraitWorld 87c1fc1).
- **Three macros, then one declaration (s29, change 7):** `@concrete_only`, `@warn_on_abstract` (in two forms) and `@error_on_abstract` were to be replaced by one declaration with a level, the per-parameter grain to come later as its argument.
- **Replaced (2026-10-21, the user):** concreteness per part. A trait names the parameters and `Self` it requires concrete (`@enforce_concrete_only T Self`, or warns, `@warn_on_abstract`), and a bounded function the parts of its arguments; concrete mode got spellings of its own (`@enforce_fully_typed`, `@warn_not_fully_typed`). The reason: a guarantee the trait's author states per part, where one level for a whole trait or module could not say that `P` must be concrete but `U` need not. `@concrete_only` and `@error_on_abstract` are refused with the new spellings. Traits §11.

## Overrides: followed or refused

The consistency review of s27 found two statements in conflict: "refused" (the keys design, `check_overrides`) against "a fact that recompiles to the new method" (rule P, wrapping by facts). The options were to drop the refusal under rule P, or to keep it as a declared-API rule with a corrected justification. Decided in s27 (decision 4; the user: "restart only for now (though Julia now allows struct redefinition! so might revisit this later)", "Refuse on load is fine"): refused, because the key would change and kept values hold the old one; family members fixed at first use; refusal at load accepted; a restart for interactive changes. The "at checkpoints on stock" clause went with stock support (s29, change 8).

## `Callable` with one mode, rejected

Change 2 of the decisions review (`../reviews/2026-10-18-decisions-revisited.md`) proposed one mode. Rejected (s29, the user: "We need compiled call to have an ODE RHS that has the right type signature. Julia's type system can't express that otherwise."): an unbounded argument specializes but checks nothing, so a compiled call with a declared signature needs `CompiledCall`. `Callable{A, S, M}` with a default mode and the caller's override dates from rev 988; at the same time `@specialize` was retired, and "static and inlined" was corrected to "a direct call the compiler may inline" ([`../design-findings.md`](../design-findings.md) §3).

## `Callable`'s modes and the opening of `Dynamic` at every bound, replaced by `Compiled` and `Dynamic`

Replaced on 2026-10-20 by one language for every trait position ([traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic); the user's rule and its refinements: [`../plans/2026-10-20-dynamic-and-compiled.md`](../plans/2026-10-20-dynamic-and-compiled.md) §0; decision log, the rows of 2026-10-20). What it replaced, and the forms considered on the way:
- **`Callable{A, S, M}` with the modes `DynamicCall` and `CompiledCall`** (rev 988; kept in s29 against one mode, above), with `compiled_call(f)`, `dynamic_call(f)`, `DynamicFn{A, S}`, `dynamic_fn`. Now `Callable{A, S}` declares `@dynamic`, and the attributes and conversions are the general ones. **No synonyms** (the user: "Synonyms: no."): the old spellings are not kept beside the new.
- **A `Dynamic` opened at every bound,** an automatic function barrier: a `Dynamic` passed to a bounded function ran the worker for its object's key. Replaced: a value keeps its attribute, and `compiled_for` opens it where the code asks.
- **An abstract part of a key opened at the next bound** (traits §11 before): replaced by the same rule; a value of abstract type is `Dynamic` at the next bound.
- **A trait's name in a bound's parameters meaning its `Dynamic`** (`Iterable{Shape}` as `Iterable{Dynamic{Shape}}`, decided 2026-10-20 with BaseTraits): replaced by item positions, whose items are `Compiled` or `Dynamic` by the item type.
- **The default `Compiled` for every plain value,** by its type at run time, whatever the caller knew (the first form of the rule, §0 before its refinement): replaced by "the type the code knows decides". It mirrored Julia; the refined rule mirrors Rust and Swift, and gives a `Dynamic` path where the code does not know the type.
- **A warning where a boundary's attribute disagrees with the trait's default:** removed (the user: "Let's remove the warning entirely"). It would fire on every deliberate `Compiled{Callable}`.
- **Who decides by the value's form under a bare bound** (proposal §1b): folded into the refined rule.
- **`dynamic by`** (traits §4.9): removed; `Dynamic` positions and `@dynamic` cover it.
- **The lowering, a second worker per bounded function taking `Dynamic{<:X}`:** not chosen. Every bounded function would get two methods, definition checking would cover both, and several bounds at one position would need `Dynamic{(X, Y)}` first. Chosen instead: a trait object at an erased key, one more key of the one worker ([lowering §5](../reference/lowering.md#5-keys-and-views); implementation plan C1, confirmed by the user).
- **The untyped callers' table and the entries compiled ahead per type as the path of an untyped caller:** not chosen, since an untyped caller is `Dynamic` ([lowering §9.2](../reference/lowering.md#92-untyped-callers-the-erased-worker)). The table serves the `Compiled` values of untyped callers instead (`compiled_for`, [lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)). The entries compiled ahead per type (`f(::T)`, an `invoke` of the generic entry) are deleted: a dispatch at run time reaches them and makes the caller `Compiled`.

## Storage as always `Dynamic`, and `stored`, replaced by values that carry through storage

Replaced on 2026-10-21 (W-18; [traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic), [§7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), [§7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait); [the plan](../plans/2026-10-21-values-carry-through-storage.md), [the review](../reviews/2026-10-21-values-carry-through-storage.md); the decision log, the row of 2026-10-21). The user: "I thought of Values carry as just that: It persists through storage."
- **A trait's name in storage meaning its `Dynamic`** (from rev 1125, kept when the attributes came on 2026-10-20 as "a field … declared with a trait is `Dynamic`"): a value stored lost a `Compiled` attribute, the caller's `compiled_for` among them, which re-created the library's switch. It followed Rust's `Box<dyn P>` and Swift's `[any P]`, which store a value at an abstract type only behind a table because they compile ahead; Julia compiles per type when the code runs.
- **`stored(Callable{A, S}, f)`,** a function applying the bound by hand where a library keeps a function (W-2): replaced by struct parameters bounded by a trait, whose constructor is the bound.
- **The kept form as the union `Union{Compiled{X}, Dynamic{X}}`:** not chosen (the user: "One concrete type"). Julia boxes a union of types that hold a pointer: measured while W-18 was built (the union form, before TraitWorld 1d09112), reading 200 items of a `Vector{Any}` through the view allocated 3,248 bytes against 48 with `Kept{X}`.
- **The attribute as a type parameter** (as `Callable{A, S, M}` had): serves one stored value, at a struct parameter (kept, §10.5), not heterogeneous storage: left open per item it is an abstract type, boxed like the union; fixed per container it forces one attribute on every item.
- **A slot declared `Dynamic{X}` converting what it receives** (the plan's first revision, §4.2): rejected after the review (F1). It moved the library's switch from a function to a field.
- **`Dynamic{X}` written in a trait module's storage meaning `Kept{X}` with `Dynamic` as a default** (the plan's revision 2): replaced by the plain type (the user: "The plain type"), after the review of the traits reference (F2). The default decided almost nothing, since stored values carry, and it made one spelling widen in one place and refuse in the others.
- **Constructors as casts** (`Dynamic{X}(t)` for a `Compiled` trait object; `Dynamic{Callable{A, S}}(compiled_for(f))` dropping the cast silently): replaced by one spelling for a cast (the user: "make compiled_for(x)/with_dynamic(x) the only way to do the cast"). Constructors make or keep, and refuse a change.
- **Of two explicit casts, the caller's winning, or an error:** not chosen (the user: "The library wins"). The later cast wins.
- **A function of several signatures stored as a `Dynamic` of all of them** (SciML's `FunctionWrappersWrapper`), for TraitDifferentialEquations' Jacobian at the duals: not needed. A `Dynamic` function at another signature is the same function there, through a pointer of its own; the problem keeps the function at two bounded parameters.
- **A write through a view always storing the user's object** (the review, F5): not chosen; it drops a cast written back. A write stores what reads back the same.

## Automatic differentiation by a library-owned dual number, superseded

In s23, TraitDifferentialEquations was to use a dual number type owned by the library (`LDual{N}`, option 2), with ForwardDiff joining the trait world later through a trait wrapper. Superseded in s24 by wrapping by facts: Rodas5 uses ForwardDiff's own `Dual` with the solver's tag, called directly (TraitDifferentialEquations 702402d). AD in the review of s23 (F10) dissolved with it.

## Other options considered and not taken

- **Guarded devirtualization at run-time sites, postponed (2026-10-19):** a failed guard leaves its site on the slow path, silently, until the caller compiles again: a permanent cliff decided by what loaded when ([the speed plan](../plans/2026-10-19-principled-speed-plan.md) §2). Refined (2026-10-20, the user): the objection is to the permanent slowdown, and it goes away if the caller is compiled again in the background with the observed types and the new code is swapped in. In that form it is Optional ([compiler §1.6, §3.3](../reference/compiler.md#33-further-work-on-mechanism-3); [open issues](../open-issues.md) item 37).
- **A cache in place of the `Dynamic` split:** not an option. The split is the only path that inlines and types each branch's result; a cache can only make the fallback cheaper.
- **What follows the split** (E-145, 2026-10-21; chosen: a table of the call's targets keyed by the value's type, [compiler §4.3](../reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)). Not chosen:
  - **the dynamic call** (built until then): 40 to 90 ns and an allocation per element at 16 to 64 types, since Julia's four-entry per-site cache thrashes;
  - **a longer split:** a loop's code grows to 19 KB at 16 types and 190 KB at 64, and compiles in 15 and 41 ms per site;
  - **a per-site cache** of (type, pointer) pairs: it thrashes beyond its size (40 ns at 64 types with 8 entries);
  - **a table per trait** shared by its operations: fewer tables, but its pointers could not be typed by the site's arguments; the table per call signature is Julia's way of compiling per signature;
  - **the split's "default case"** (the call of `f` at the value's declared type as the last branch, composed in TraitWorld with `known_type`): a call at an abstract type is not a fact, so the facts mode would never emit it in trait code; and the library would re-decide what the compiler knows ([the review](../reviews/2026-10-21-what-follows-the-split.md) finding 1–2).
  - Optional, not built: **a witness carried in the value** (up to 1.5× faster on large mixes, 8 bytes per value) and **recompiling with the observed types** ([compiler §3.3](../reference/compiler.md#33-further-work-on-mechanism-3)).
- **Deriving implementations from the methods that exist.** Rejected: Base's throwing fallbacks make it unsound ([`other-languages.md` §2](other-languages.md#2-implementations-are-declared)).
- **The edge-level rule:** compile only concrete calls against the current methods and make abstract ones dynamic. Rejected in s22 for its cliff at abstract calls and for having no closed world for AOT. Adopted later in substance as the facts rule (s23, s28): the cliff is accepted as run-time sites, recovered by traits, and AOT is restated through declared targets.
- **Absorbing dependencies:** each package brings its ordinary dependencies into its own world. Rejected: two packages that absorb Makie conflict as soon as one defines a recipe.
- **Trait bounds that compete with types,** ranked like abstract types. Rejected: the conflict would surface only in an application that loads both packages.
- **Explicit wrapping at the call,** `f(ColTable(x))`. Rejected: adopting traits would change every caller.
- **Function types in the type system,** `Float64 -> Float64`. A far larger change to Julia than one trait whose only operation is checked at every call.
- **Hidden type parameters** for fields declared by bounds: a struct implicitly parametric in the types of fields declared by bounds. Rejected as un-Julian (the user, 2026-10-16: "Hidden type parameters seem antithetical to Julia").
- **A `Keep{X}` bound** for functions that keep a trait object: not needed, since keeping is detected (s23, the user: "If feasible, detection is the way").

## Plans, thresholds and settings superseded

- **The plan of s23:** TraitWorld at the current design, then the demonstrators (TraitDifferentialEquations, then TraitMakie), then an upstream proposal; wrapping and sealing later. Superseded by the order of work in [state §6.3](../state.md#63-the-order-of-work).
- **The plan's numeric threshold for `all` (P-a):** a go/no-go rule of at most 5% mean slowdown and no group above 20%. Replaced as the criterion by the user's principle that a slowdown is tolerated if a trait redesign recovers it (s29), and then moot (change 9): `all` is a test bed, so (B) is needed regardless of BaseBenchmarks. The principle governs trait code and the plain code it reaches.
- **`--compile-by-facts=all` as a user setting.** Made a test bed (s29, plan P-c): in the Compiler copy it changed values (`map(f, Real[])` was `Vector{Any}`), and it gives plain code the protection the thesis attributed to traits. The in-tree mode answers a run-time `return_type` by plain inference in its own cache owner (`PlainRTInterp`), so `map(f, Real[])` is `Vector{Float64}`, as in plain Julia.
- **The forks (demonstrator 4)** were paused at M5 (s29, the user: "Pause the forks for now"), then run on the new compiler.
- **Workload extensions written by hand** (the forks' `CSVDataFramesInlineStringsExt`) are a workaround, to be replaced by AOT from declared targets ([traits §13](../reference/traits.md#13-compiling-ahead)).

## Claims withdrawn

- **"Performance: no cliffs"** as a section of the notes. Its claims are restated by [the rationale §2](../design.md#2-the-argument-in-four-steps) and measured in [`evidence.md`](evidence.md).
- **"Loads do not change speed" as a property of traits.** The control showed that load protection belongs to the facts rule, for any code ([`evidence.md` §1](evidence.md#1-the-guarantee)).
- **Numbers of earlier prototypes** that the current documents no longer cite: first calls through view caches ("about 3 ms in every load order"), first-call numbers from before s29, and a 2.09 MB trimmed binary of `experiments/world` that predates keys and has not been rebuilt. The evidence log in session order is [`../design-findings.md`](../design-findings.md).
- **The research's "Ours" column of s22** (`../record/other-languages-research-2026-10-16.md`) describes the design of that date: compiled "per representation", "dynamic operations, dynamic call (per conformance)", no storable dynamic value, "owner, or a delegate the owner names (rule 3)", "the image of the package that chose the type (rule 4)", "dynamic Julia, above the trait world". [`other-languages.md`](other-languages.md) has the current column.

## Terms retired

| Old term | Now | Changed |
|---|---|---|
| conformance (the noun) | implementation | 2026-10-19 |
| implementing type, implementing value | receiver type, receiver | 2026-10-19 |
| representation, projection | key: code compiled for what the bound can see | s22 |
| layering, trait wrappers, calls upward, sealing | the facts rule: trait code may call any Julia code | s23–s29 |
| the trait world and ordinary code, as worlds | trait code and plain code, compiled by facts or plainly | s29 |

The verb stays: a type still *conforms to* a trait, and the query is still `conforms(T, X)`. The glossary's [retired terms](../glossary.md#retired-terms).

## Seeing a value through another trait: trait casts, or tuples of traits

- **What it was:** a function kept at one signature was the same function at another: passed to a `Callable` bound of another signature, it was seen there with its attribute, unchecked until its first call (W-18, mine, confirmed with open issue 39). A kept value of one trait passed to a bound of another was seen through it where its object conformed, without a rule saying so.
- **The options (2026-10-21):** (a) *trait casts*, the user's name: seeing a value through another trait as one casts between abstract types, the attribute kept, checked at the cast; implicit at a bound, or explicit by a kept form's constructor; (b) a value enters through every trait it will be seen through, as a tuple of traits, and is seen through those only.
- **Decided (the user: "Trait casts sound like a possible future extension then … We could define a tuple of Traits as a valid Trait"):** (b). A trait cast stays a possible direction (traits §6.9, Optional). The reasons: entering through a tuple covers the cases met (TraitDifferentialEquations' right-hand side at two signatures); a trait object inside bounded code may hold only the parts its traits see, so a cast there could fail for reasons the code cannot see, and the code compiled for it covers only its traits, which definition checking relies on.

## Split packages: restructuring, or implementations, instead of joint owners

- **The case:** DiffEqBase defines methods of SciMLBase's functions on SciMLBase's types (`__solve`, `__init` on `AbstractDEProblem`; `Base.isempty(::CallbackSet)`): 28 pirates by the letter, NonlinearSolve and NonlinearSolveBase 22, OrdinaryDiffEqCore 3 (E-153's census). A trait module refuses them.
- **Restructuring:** move each method to the package that owns the function or a type (the solve front end into SciMLBase, or the abstract problem types into DiffEqBase). It changes SciML's package structure and its dependents.
- **Implementations instead of methods:** declare SciMLBase's interface functions as a trait's operations, and let DiffEqBase implement the trait for its own types. It works where DiffEqBase owns a type; where both the function and the types are SciMLBase's, there is no owned type to implement for.
- **`delegate!`:** data for strict mode only; it does not lift the refusal in a trait module.
- **Chosen: joint owners**, declared by the owner (the user, 2026-10-21: "if building joint ownership is simpler than restructuring SciML that is the pragmatic choice"). Which of the census's pirates a different structure or an implementation would remove is assessed in the inside-out plan of W-32 (P6).

