# Review: the design as it stands, and the fixes of sessions 27–28 (2026-10-18)

Reviewer: Fable 5.1, independent. Written against the design repository at 0683e27 (poc-error-split), TraitWorld 47e4274, experiments cac8e72, julia-1.13 db82407fa6 plus its uncommitted `Compiler/src` changes, forks 06e8b97.

**Scope.** `writeup/README.md`, `notes/1-overview.md`, `2-design-choices.md`, `3-wrapping.md`, `4-details.md`, `decisions.md`, `open-issues.md`; `explorations/wrapping-by-facts.md`, `strict-mode.md`, `aot-under-facts.md`, `julia-support.md`, `dataframes-port-lessons.md`; `plans/2026-10-17-policy-in-compiler-plan.md`; `experiments/factscompiler/README.md`; the three earlier reviews of 2026-10-16/17; session note 27; the git logs of every sub-repository for session 28 (which has no note). Code read: `TraitWorld/src/{facts,core,implement,hooks,strict,ownership,trait}.jl`, `julia-1.13/Compiler/src/facts.jl` (uncommitted), `experiments/factscompiler/Compiler/src/facts.jl`, `julia-1.13/src/codegen.cpp` (cfunction wrappers), `julia-1.13/base/{array,reflection}.jl`.

**Method.** Three experiments ran on the patched 1.13.2 build, one Julia process at a time, niced, under the shared lock (appendix). **Verified** means a source quote, a git record or an experiment run here. **Reasoning** means an argument I did not run. Terms as in `4-details.md` "Terms": trait, conformance, key, worker, entry, run-time site, fact, `Dynamic{X}`.

## Summary verdict

The four significant inconsistencies of the fresh-eye review were fixed, in text and in the prototype, and the G1 defect of the decisions review (a late override for a family member) was closed. The core that review called coherent, rule 1 with rule P, rule 2, keys, pirates followed, is still coherent, and the acceptance suite passes 16 of 16 on the current prototype (verified, appendix A3).

Session 28 then changed the architecture, and the design documents do not know it. Three new conceptual problems come with it, two of them verified as defects:

1. **The facts mode as a global compiler setting changes what "identical or error" compares against.** With the mode on, `map(f, Real[])` returns `Vector{Any}` where today's Julia returns `Vector{Float64}` (verified, A2). The go/no-go benchmark ran in that configuration, and no correctness run was made. Under `--compile-by-facts=all` pay-off 4 ("a call computes exactly what it computes in Julia today") is false as written, and G2's object is no longer the trait world but every compiled method.
2. **Witness tables break world age.** An operation on a `Dynamic` through a witness pointer runs in the latest world, not the caller's: in a task pinned to an older world it returns the redefined method's value where plain Julia returns the old one (verified, A1). This is a G1 violation of the kind the design excludes, introduced on 2026-10-18 (TraitWorld 30527ed).
3. **Strict mode and the machinery exemption have no definition under one cache owner.** Strict mode's protected set is "code owned by `FactsOwner`"; with (A) at `all` there is no such owner, and the plan does not say what strict mode then protects. The machinery is exempted by Julia's compiler naming TraitWorld by module name (`sealed_call`), which is sealing under another name, after the user asked for the notion to leave the project.

Beside these, the notes still describe the external `FactsInterp`, "package code", and the cost model before run-time sites ran policy code; the register has no session-28 row and contradicts the plan on the Julia pieces and on run-time dispatch under the policy; and most of the "minor" stale lines the fresh-eye review listed are still there.

## Findings, ranked by damage to the thesis

### 1. The global facts mode changes semantics and the object of the guarantees, and the notes do not say so — significant, partly verified

**What changed.** The plan (`plans/2026-10-17-policy-in-compiler-plan.md` §0) makes the facts policy a mode of Julia's native inference, switched by `--compile-by-facts=no|all`. At `all` there is one interpreter and one cache: Base, every package and every trait module are compiled by facts. The plan's R3 names the risk ("`return_type` and the A3 differences are wider for all code") and P-c asks whether `all` is a user setting or a test bed.

**Evidence.**
- *Verified (A2).* With the compiler copy and `JULIA_FACTS_COMPILER=1`, for `g(x::Real) = 1.0; f2(x::Real) = g(x)`: `typeof(map(f2, Real[]))` is `Vector{Any}`, `f2.(Real[])` is `Vector{Any}`, `Base.promote_op(f2, Real)` is `Any`. With the mode off, all three give `Float64`. The copy's own `return_type(f2, Tuple{Real})` is `Any` on, `Float64` off. So a returned value of Base changes under the mode, through `Base._return_type` at run time, in exactly the configuration the BaseBenchmarks run used.
- *Verified (absence).* Plan §2.4 calls for `Base.runtests` in facts mode "compared with the flag off", each difference listed. `experiments/factscompiler/` has `scripts/{bench,compare,twtests}.jl` and `results/{full0,full1,full1c,smoke0,smoke1,uniontest}`; nothing runs Base's tests, and the README reports no correctness result. The decision rule of §3 was applied to speed alone.
- *Verified (text).* `1-overview.md:100` ("A call computes exactly what it computes in Julia today, in the current world, or raises"); `4-details.md:757` (the G1 statement) and `:779` (A3 as a narrow exception: `return_type`, `promote_op`, empty collections). Under `all` A3 is not an exception at the trait world's boundary; it is a difference between two Julias.

**Why it damages the thesis.** The thesis sells "minimal changes to semantics". With `all` as a user setting, the semantics of Base change in every program that lets inference pick an element type, and the design has no statement of how often or where. With `all` as a test bed only, the real design is (B)+(C), of which only a sketch exists (plan §6), and the notes describe neither.

Second, G2's object moves. Theorem 2 speaks of "a trait-world CodeInstance whose facts are all concrete". At `all` every CodeInstance is such, so G2 becomes "no package load invalidates any compiled code except a stakeholder's or a winning pirate's". That is a stronger and more interesting claim than the thesis makes, and it is unmeasured: plan §3 lists "compiled code lost per load over the load matrix" under "what (A) gains", and the README reports no such number. Pay-off 1 ("library code compiled once per key... never invalidated by unrelated loads") then is a property of the compiler mode, with traits adding keys; the notes attribute it to traits.

Third, the "trait world" as a term dissolves as a compilation boundary and survives as a checking boundary (rule 2, definition checking, the ownership check for trait modules). `4-details.md:11–12` defines it by the compiler policy and its cache.

**Resolution.**
- Decide P-c now, before stage 2. If `all` is a user setting: answer `return_type` at run time by plain inference, as the compile-time path already does (`PlainRTInterp` exists in both facts files; route `Base._return_type` to it under the mode). Then A3-class values are plain Julia's by construction, and the remaining differences are inference-only (`Union{}` where every method at a run-time site throws). Run `Base.runtests` in the mode before any further benchmark.
- Restate the guarantees: G1 relative to dynamic dispatch (unchanged) plus a list of inference-decided values and how each is answered; G2 as a property of facts-compiled code, with the trait world as one instance.
- Split the term: *facts mode* (how code is compiled) from *trait module* (what is checked). Rewrite `4-details.md` Terms, `1-overview.md` "The trait world" and "What it costs", `3-wrapping.md` "What the compiler records".

### 2. Witness tables run `Dynamic` operations in the latest world: a G1 defect — significant, verified

**Design.** `4-details.md:633`: "An operation of `X` on a `Dynamic{X}` dispatches on the trait object inside, in the caller's world, and asserts the declared result type." Rule 4 (`:107`): "A call sees the current world, as a plain Julia call does." Decision register, `Dynamic{X}`: "operations dispatch".

**Prototype.** TraitWorld 30527ed (2026-10-18): a `Dynamic` holds a `_Witness` with one pointer per operation, filled on the first call by `_wit_fill!` → `_wptr`, which is `@cfunction($(W()), RT, (Ref{TO}, ...))` of `_WitOp{F,RT}` (`core.jl:356–376`). The call is `ccall(p, ...)` (`core.jl:541`), guarded by the process token and `args isa AT`, not by a world.

**Verified (A1).** Five conformances, `tsum(v::Vector{Dynamic{Shape}})` compiled with S1–S4 as key branches and S5 on the witness path. After `area(::S1) = 100.0` and `area(::S5) = 500.0`:

| call | prototype | plain Julia |
|---|---|---|
| latest world, `tsum` | 609.0 | 609.0 |
| `invoke_in_world(w0, tsum, d)` | **510.0** | 15.0 |
| `invoke_in_world(w0, one_area, d[5])` (witness key) | **500.0** | 5.0 |
| after a late conformance S6 | 615.0 | 615.0 |

The branch keys (S1–S4) answered in the old world correctly (510 = 10 + 500); the witness key did not. The cause is Julia's cfunction entry: `codegen.cpp:7498–7503` loads `jl_world_counter` and stores it into the task's world age before the call (`emit_tls_world_age_store(ctx, world_v)`), because a cfunction is an entry point from C. A `@cfunction` pointer is therefore the wrong primitive for a call that must run in the caller's world.

**Why it damages the thesis.** "Identical or error" is the thesis's one semantic promise, and this is a silent wrong result in the kind of place world age exists for: tasks pinned to an older world, `invoke_in_world`, test runners, and the pinned dynamic mode the design itself plans for models (open issue 2.15). The acceptance suite tests the older world for entries (G1.14) but not for `Dynamic`. The notes' "First calls from package images need no compilation" (`4-details.md:642`) is also no longer true for the witness path: `_wptr` generates a cfunction per (operation, trait-object type) per session, and `verify.jl:461` disables the path in a trimmed build.

**Resolution.** Keep the pointer but check the world: store with each pointer the CodeInstance (or its world range) that the pointer's code was compiled against, compare `Base.tls_world_age()` at the call, and take the dispatching path otherwise; or keep one table per world. Add acceptance case G1.16 ("an operation on a `Dynamic` in an older world"). Write the witness-table mechanism and its limits into `4-details.md` "Dynamic values" (today the note has no word on it).

### 3. Strict mode and the machinery exemption have no definition under one owner — significant, reasoning with code

**Strict mode.** `strict.jl:52–57`: protected code is `ci.owner isa FactsOwner`, or a native CodeInstance of a method in a trait module. Plan §0 keeps strict mode in TraitWorld under `all`, and §5 keeps piece 1 "strict mode refuses pirates through it"; §5 also says there is "no `FactsOwner`". Then:
- the protected set is the trait modules' own methods (workers, compiled natively under the mode, are methods of trait modules), and nothing they call: Base code compiled by facts for a worker is not "trait-world code";
- dependence through callees, the exception of `strict-mode.md` §2b item 2, becomes the common case; piece 14 (the transitive "would invalidate" query) is deferred;
- the alternative, "any winning pirate anywhere is an error", is the global refusal the design rejected under sealing (`3-wrapping.md:151`: it "broke plain users of the pirate's package").

The plan's decisions P-a to P-c do not mention strict mode. `decisions.md:70–71` and `open-issues.md` §1.1 still describe it in terms of `FactsOwner`.

**The machinery exemption.** Open issue 2.26 records the user's direction: no sealing of abstract types or functions, "this notion should leave the project entirely", with two things to settle. The in-tree draft does the opposite of settling them: `julia-1.13/Compiler/src/facts.jl:94–102` (`sealed_call`) infers a call as usual when `nameof(Base.moduleroot(ft.name.module)) === :TraitWorld`, and `:138` exempts `_dyn_keys_now` by name. Julia's compiler names a package. The exemption is abstract facts for one package's functions, which is a sealed function by any other name (its docstring says so: "the general form is a declaration a module makes for its functions"). TraitWorld's own interpreter has the same exemption (`facts.jl:154–160`, `_machinery_call`), with the honest statement that G2 for the machinery is empirical (`wrapping-by-facts.md`, rule 7).

**Why it damages the thesis.** Strict mode is the design's answer to "never invalidated", and it is what the user said they would love. If the pivot leaves it undefined, the notes promise a mode that cannot be built in the architecture the plan chooses. The machinery exemption is the one place where rule 1 is not followed, and the plan now bakes it into Julia's compiler as a special case.

**Resolution.**
- Decide strict mode's object under one owner before stage 2. Options: (i) protected code = facts-compiled code reachable from trait modules' entries, found by piece 14's transitive query (the intended design of §2b, now necessary rather than hardening); (ii) strict mode is a property of the `traits` setting only, and `all` has none; (iii) global refusal, with the plain-user cost stated. Write the choice into `strict-mode.md`, `decisions.md:70–71` and `3-wrapping.md` "Strict mode".
- Name the exemption as what it is, without the word sealing: the trait runtime is platform code, inferred as Julia's compiler infers its own code (abstract edges allowed, G2 for it empirical, as for `jl_typeinf_world`). State in `4-details.md` rule 1 that this is the one class of code outside rule 1. Long-term, piece 7 removes the machinery calls at `Any` (entries generated by the compiler), which dissolves the question; say so in 2.26.

### 4. Key branches at `Dynamic` call sites make speed depend on declaration order — moderate, reasoning with code

`core.jl:449–466`: `_dyn_keys_now(X)` is `@assume_effects :foldable`, reads `_DECL_KEYS` (conformances declared so far, noted at each `_bump!` and package load) and `_DYN_KEYS` (values made), and returns the first `_DYN_MAX_BRANCHES = 4` in order of first appearance. It is folded when the caller is compiled, without an edge. `_dyn_call_keyed` (`:517–550`) emits an exact type test per key with a direct call, and the witness call for the rest.

- *Sound* (reasoning, and A1's late conformance S6 gave the right value): a key not in the branches reaches the witness or dispatching path, which computes the same thing.
- *Order-dependent speed:* which four conformances get a branch depends on what was declared, loaded or made before the caller compiled. The README's own numbers give the gap: branch 10.9 ns against witness 14–17 ns per element at 10⁶ values, 2.05 against 6.6 ns at 10³ (`experiments/factscompiler/README.md`, "Key branches"). This is the `max_methods` cliff the design claims to remove, in new clothes: `4-details.md:711`: "Loads do not change speed... no load can push inference over `max_methods` and turn a fast call dynamic." Here a load before the caller compiles decides which keys are fast.
- *Images:* a package image holds whatever branch set existed at its precompile; a session cannot change it.
- *Not in the notes:* `4-details.md` "Dynamic values" describes dispatch and a 20–80 ns cost; neither witness tables nor branches appear.

**Resolution.** Make the branch set a function of something load-order independent: the conformances declared in the caller's package and its dependency closure (what rule 4 already names as the owners of compiled code), not "declared so far". Then two sessions compile the same branches and the cliff is a per-package choice. State the bound (4) and the fallback cost in `4-details.md`, and qualify `:711`.

### 5. Three rule changes of sessions 27–28 are in the prototype, flagged "needs soundness review", and absent from or contradicted by the notes — moderate, verified

| change | prototype | notes | assessment |
|---|---|---|---|
| **1.1** run-time sites run the policy's CodeInstance of the method found (trampoline, `_CallSite` caches) | TraitWorld 1d93677, 5b50482, 9ddd4a0; `facts.jl:446–600` | `4-details.md:14` and `:673` ("records nothing and dispatches at run time... no load can invalidate it"); `decisions.md:99` lists option (b), run-time dispatch under the policy, as "an experiment to run later", prototype "no"; `open-issues.md` §1.4 the same | G1 holds (the site's dispatch is plain; verified by the acceptance suite, A3). What changes is the cost model and rule 4: every package reached dynamically from trait code is compiled a second time into the policy's cache, and that copy lives in the image of whichever package compiled it (`_compile_pending!`). `1-overview.md:184` says "Base code"; it is now any code. The register row is wrong. |
| **1.2** folding by Julia's own asserted effects over run-time sites (`_julia_asserted_foldable`) | TraitWorld c62e23e; `facts.jl:179–200` | `3-wrapping.md:98`: "No compile-time evaluation over a run-time site... such callees are not folded"; `wrapping-by-facts.md` rule 4 the same | Defensible on Base's own contract (`@_total_meta` is Base's promise), and plain Julia folds the same call. But the lessons' justification "only a pirate... can make either stale; strict mode refuses those" (`dataframes-port-lessons.md` §1.2) is not right: the folded callee's policy code holds no concrete fact for the inner site, so strict mode has nothing to refuse at. Say instead: inherited from Base's assertion, same exposure as plain Julia. |
| **1.8** facts at tuples with unions of concrete elements (`_fact_splits`, ≤ 4 splits) | TraitWorld 5b50482; `facts.jl:74–126`; strict mode checks per split (`strict.jl:81–86`); tests `runtests.jl:777–782` | rule 1 (`4-details.md:81`) and Terms (`:13`) say "concrete signature" | Sound by Lemma O applied to each split: the splits' types are concrete, so a method that changes dispatch at one is a stakeholder's or a winning pirate's (reasoning). Rule 1 should define a *fact signature*: a dispatch tuple, the splits of unions of concrete types inside tuple arguments, or a closure's call at kinds. |

**Resolution.** Write the fact-signature definition and the Base-fold exception into rule 1 and `3-wrapping.md` "Finer points"; correct `decisions.md:99` and `open-issues.md` §1.4; restate the cost "compiled again" and rule 4's placement for code reached at run-time sites; add the three to `wrapping-by-facts.md` "Validation" as rules 8–10 with their acceptance cases (G1.10 covers user-asserted effects; nothing covers a Base-asserted fold or a tuple split under redefinition).

### 6. The register and the open issues do not record session 28 — moderate, verified

- `decisions.md:3` "as of 2026-10-17 (session 26)"; `writeup/README.md:3` "current as of 2026-10-17 (session 27)". No row for: the pivot to the compiler mode, `all` as a switch, sealing dropped, witness tables, key branches, run-time sites under the policy, Base-asserted folds, tuple-split facts, the DataFrames port's decisions (`CSVSource`, `CSVDataFramesExt`, `Vector{Dynamic{Column}}` behind an adapter), P-a to P-c pending.
- Contradictions between register and plan: `decisions.md:94` and root `README.md:47–48` keep "first-class foreign cache owners" (pieces 5, 9–13) as the first upstream proposal; plan §5 reverts 5 (foreign half), 9 and 10 and drops 11–13. `decisions.md:97` adopts "the policy in the platform" as TraitWorld in the system image; the plan replaces that by (A) in `Compiler/src`. `decisions.md:69` says a callee is "compiled into the trait world's cache or called through a pointer"; under `all` there is one cache.
- `open-issues.md` §4b still lists F3 and F9 as open (below: F3 was settled by decision 4, F9 is moot). §1.4 still presents (b) as an experiment.
- Pending decisions P-a, P-b, P-c live only in the plan; §1 of open-issues does not list them.

**Resolution.** A session-28 note (the user's directive, what was built, what was measured, what is pending); register rows for each item above; P-a to P-c in open-issues §1; mark the superseded rows.

### 7. Residues of the earlier reviews' "minor" findings, and one new wording conflict — minor, verified

Fixed by sessions 27–28: the four significant findings (table below), `open-issues.md:3`, `1-overview.md:97` (pay-off 3 conditional), `4-details.md:405, :712`, `aot-under-facts.md:20`, TraitReport's "cannot conform", `3-wrapping.md:151` (the one refusal at load).

Still there:
- **Rule 3's wording contradicts the Ownership section.** `4-details.md:99`: "the owners of the types in every signature it applies to"; `:38` (corrected in session 27): "The test is on the method's signature, not on the concrete signatures it applies to." `2-design-choices.md:219` has the old wording too. The prototype follows `:38` (`ownership.jl:213–219`).
- `1-overview.md:187`, `3-wrapping.md:182` "the compiler policy is package code"; `1-overview.md:196`, `3-wrapping.md:86`, `4-details.md:12` describe `FactsInterp` as the design (fresh-eye 5, now doubly stale).
- `1-overview.md:207` "strict mode, not built" against `decisions.md:70` (fresh-eye 6); `decisions.md:69` still defines strict mode as "outside pirates raise where they would win".
- `decisions.md:91` (the filter protects the machinery, "adopted... yes"), `:19` ("delegation by the owner only"), `:20` (rule 4 as "owners' view") (fresh-eye 7).
- `4-details.md:502` "Functions from the trait world are always compiled calls... any package's functions" against `entry.jl:519–586` (fresh-eye 8).
- `4-details.md:438` the dispatch tier "above `Any`" not marked as needing the language (fresh-eye 9).
- `2-design-choices.md:127, :186, :367, :411–412, :335` pre-facts lines outside the banner (fresh-eye 10).
- Numbers: `1-overview.md:198` and `4-details.md:718` "37–39 ns"; `4-details.md:646` "a fixed entry cost of about 215 ns"; `1-overview.md:200–201` "55–60 ms", "87–97 ms" against session 27's 6.4–8.0 and 18–22 ms (fresh-eye 11; demonstrators S6).
- `3-wrapping.md:155–159` E2 presented as evidence about policy code (fresh-eye 12).
- `1-overview.md:178` the AD-tag sentence, recorded as to-fix in `open-issues.md` §5.4 since session 26.
- `open-issues.md:69` "views exclude modules under `Main`"; `3-wrapping.md:202` cost 5's cure; `writeup/README.md:28` `runtime.md` as "current".

### 8. Decision 1's grain and decision 4's message — minor

- The decisions review asked for concreteness per parameter or declared field (its condition 1), because TraitDifferentialEquations' `IntegratorView{T, P}` wants `T` concrete and `P` free. Decision 1 adopted "per trait" (`decisions.md:118`). The library then cannot opt in for the state type without binding the parameters. Not wrong, but the review's case was not answered.
- `_override_violation` (`hooks.jl:150–152`) still names the fix "define the method before `@implement`, or in its block, and restart the session"; after the fact "in its block" is not available (probe iii-b of the decisions review). Minor.

### 9. State of the in-tree port — a state finding, verified

`julia-1.13/Compiler/src/facts.jl:16` calls `ccall(:jl_compile_by_facts, Cint, ())`; `grep` finds no such symbol in `julia-1.13/src`. The uncommitted in-tree draft cannot load as it stands. Its comment says the environment variable "overrides either way", so a plain system image with `JULIA_COMPILE_BY_FACTS=1` would write facts-compiled package images into the plain image's cache until `CacheFlags` carries the mode (plan §4 says it must). Record both so the next session does not take the draft for a working stage 2.

## What is coherent and holds

- Rule 1 with rule P, rule 2, keys, the implementing type, forwarding, declared fields, decisions 1–4 as written in `4-details.md`, and pirates followed by default: stated alike in the four notes, the register and `wrapping-by-facts.md`, and run by the prototype.
- The acceptance suite: 16 of 16 on TraitWorld 47e4274 (A3), including G1.14 (older world, for entries) and G2.1 (the case decision 3 fixed).
- Decision 2's restatement of Lemma O and Theorem 2 with supertype owners and the extension exception is consistent across `4-details.md` Ownership, `3-wrapping.md` Pirates and `wrapping-by-facts.md`; only rule 3's one-line wording lags (finding 7).
- The DataFrames port answers the demonstrators review's B1 and S3 in the right way: a real REPL session, upstream unmodified as the baseline, five runs with medians and load logging (`forks/README.md`, M0).
- The plan is candid about R1–R5 and measured before committing to (B); the go/no-go result is reported with its tails.

## Earlier findings and their status

| Review, finding | Status | Where |
|---|---|---|
| Fresh-eye 1, concreteness opt-in vs required | **fixed, text and prototype** (decision 1): `key_concrete`, `@concrete_only`/`@warn_on_abstract`, family members refused at the entry (`implement.jl:71–101, 648–649`); per-parameter grain not adopted (finding 8) | TraitWorld 87c1fc1; `4-details.md:255–261` |
| Fresh-eye 2, Lemma O and stakeholders | **fixed in text** (decision 2); prototype already judged by the method's signature; rule 3's one-line wording still old (finding 7) | `4-details.md:38–40, :64`; `wrapping-by-facts.md:69, :74` |
| Fresh-eye 3, facts at non-public functions | **fixed in prototype, made moot** (decision 3: dropped; acceptance 16/16) | TraitWorld eef27bc |
| Fresh-eye 4, overrides refused vs followed | **fixed, text and prototype** (decision 4; justification restated; refusal at load named) | `4-details.md:203–207`; `wrapping-by-facts.md:25, :56, :66` |
| Fresh-eye 5, policy "package code" vs platform | **not fixed**, and superseded again by the pivot (finding 1, 7) | `1-overview.md:187`, `3-wrapping.md:182` |
| Fresh-eye 6, strict mode status and definition | **not fixed** (finding 7); and undefined under the pivot (finding 3) | `1-overview.md:207`, `decisions.md:69` |
| Fresh-eye 7, register rows 91, 19, 20, 15 | row 15 fixed; **91, 19, 20 not fixed** | `decisions.md` |
| Fresh-eye 8, "functions from the trait world" | **not fixed** | `4-details.md:502` |
| Fresh-eye 9, dispatch tier needs the language | **not fixed** | `4-details.md:438` |
| Fresh-eye 10, pre-facts lines in 2-design-choices | **not fixed** (banner extended by one clause) | `2-design-choices.md:127, :186, :367, :411` |
| Fresh-eye 11, numbers that disagree | **not fixed** | `1-overview.md:198–201`, `4-details.md:646, :718` |
| Fresh-eye 12, E2 as evidence about policy code | **not fixed** | `3-wrapping.md:155–159` |
| Fresh-eye 13, housekeeping | header fixed; the rest not | `open-issues.md:69`, `3-wrapping.md:202`, `README.md:28` |
| Decisions review, probe v (family override not refused, G1 defect) | **fixed in prototype** (hook and `check_overrides` cover family members; read, not re-run) | TraitWorld 96b75c2; `hooks.jl:120–135`, `implement.jl:709–714` |
| Decisions review, decision 1 conditions 2–5 (depth stated, key check at the family slow path, text restated, demonstrators declare) | **fixed** (depth: `4-details.md:259`; slow path: `implement.jl:648`; text: `1-overview.md:97`, `4-details.md:405, :712`, `aot-under-facts.md:20`, TraitReport README) | — |
| Decisions review, decision 4 conditions (justification, refusal at load, load-order dependence, message, register) | **fixed** except the message's "or in its block" (finding 8) | `4-details.md:203–207`, `3-wrapping.md:151` |
| Wrapping-under-keys F1 (filter kept stale code) | **moot**: filter removed under wrapping by facts; G1.1–G1.2 cover the case | `acceptance.jl` |
| F2, F4, F5, F6, F7, F8, F10 | **dissolved or adopted**, as `open-issues.md` §4b records; F7's rule now at `4-details.md:150` | — |
| F3 (family conformances, later methods by members' owners) | **settled by decision 4** (a member's late override is refused, the cost F3 warned about accepted); still listed open in `open-issues.md:137` | `4-details.md:205` |
| F9 (the walk at the entry) | **moot**: no walk in the notes (`4-details.md:169`: run-time sites); still listed open at `open-issues.md:138` | — |
| F11 (stale statements) | **partly**: `4-details.md:646` "215 ns" still there | — |
| Demonstrators B1 (REPL case) | **addressed for the port** (forks M0: a real REPL on a pseudo-terminal); not for the three demonstrators | `forks/README.md` |
| Demonstrators B2 (hardened baselines) | **not done**; superseded in part by upstream-as-baseline in the forks | plan §0 |
| Demonstrators S1 (stock numbers), S2 (view caches), S7 (samples) | S7 addressed in the forks' harness; S2 "view caches off" stated in the port's claim; S1 waits on P-b | plan §0 |
| Demonstrators S5 (AOT, no current evidence) | **not addressed** | — |
| Demonstrators S6 (stale overview numbers) | **not fixed** | `1-overview.md:197–201` |

## Is the design one coherent thing? (question 3)

Not yet. There are now three layers of description:
1. **The notes** (`1-overview`, `3-wrapping`, `4-details`, Terms): the external policy, `FactsInterp` with its own cache, run-time sites into native code, Base compiled twice, "first-class foreign cache owners" as the upstream story. Current as of session 26.
2. **The register and open issues**: session 27's decisions, with session 26's platform prototype and option (b) "to run later". Current as of session 27, minus the late-session-27 runtime changes (1.1, 1.2).
3. **The plan, the lessons and the factscompiler README**: the compiler mode, one owner, run-time sites under the policy, tuple-split facts, Base-asserted folds, witness tables, key branches, sealing dropped. Current, but only in the plan.

Where the notes describe an earlier design as current: `1-overview.md:62–70` (the trait world "compiled by the trait world's own compiler policy" as a cache boundary), `:184–187` (costs), `:196`; `3-wrapping.md:84–101` (what the compiler records; the "Finer points" contradict 1.2), `:180–192` (what Julia must provide: pieces the plan reverts); `4-details.md:11–14` (Terms), `:86`, `:673`; `2-design-choices.md` §5–7 (banner says so) and the lines of finding 7. Where the register contradicts the plan: rows 69, 94, 97, 99; root `README.md` plan items 2 and 6.

The decisions that contradict each other: none head-on among the adopted rows; the conflicts are register versus plan (finding 6) and register versus prototype (row 99 versus 1d93677; row 69's strict-mode clause versus row 70).

## The most important unresolved conceptual problems, ranked (question 4)

1. **What `all` means for G1 and for the thesis** (finding 1). Resolution: decide P-c; route run-time `return_type` through plain inference under the mode; run Base's tests; restate G1/G2 and the terms.
2. **World age in witness tables** (finding 2). Resolution: world-checked pointers or per-world tables; acceptance G1.16; the mechanism written into "Dynamic values".
3. **Strict mode under one owner, and the machinery exemption without "sealing"** (finding 3). Resolution: choose the protected set (piece 14 transitive, or `traits` setting only, or global with the cost stated); name the exemption as platform code inferred like the compiler's own, with piece 7 as the way it disappears.
4. **Order-dependent speed from key branches** (finding 4). Resolution: branch on the caller's dependency closure, not on "declared so far"; qualify "Loads do not change speed".
5. **Unreviewed rule changes 1.1, 1.2, 1.8** (finding 5). Resolution: define *fact signature* in rule 1; state the Base-fold exception; restate the cost model and rule 4 for code reached at run-time sites; acceptance cases for a Base-asserted fold and a tuple split under redefinition.
6. **Currency of the record** (findings 6, 7). Resolution: a session-28 note, register rows, P-a to P-c in open-issues §1, and one pass over the stale lines listed above before the next review.

## Appendix: experiments

All on `julia-1.13/julia` (patched 1.13.2), `--startup-file=no`, `JULIA_NUM_PRECOMPILE_TASKS=4`, `flock /tmp/claude-1000/julia-review.lock nice -n 19 timeout 900`, one at a time. Scripts in `/tmp/claude-1000/review-design/`.

**A1. `dyn_world.jl`** (`--project=TraitWorld`, TraitWorld 47e4274). Trait `Shape{R}` with `area(::R)::Float64`; S1–S5 conform in the module; `tsum(v::Vector{Dynamic{Shape}})`; `one_area(d::Dynamic{Shape})`.
```
witness tables on: true  facts: true
keys branched when tsum compiles: Tuple{Shape at Main.TS.S1, Shape at Main.TS.S2, Shape at Main.TS.S3, Shape at Main.TS.S4}
before: tsum = 15.0  (plain 15.0)
witness ptrs after first call (S5 is the 5th key): Ptr{Nothing}[Ptr{Nothing}(0x00007624da14def0)]
after redefinition: tsum = 609.0  (plain 609.0)  OK
in the older world: tsum = 510.0  (plain 15.0)  WRONG
in the older world, witness key alone: 500.0  (plain 5.0)  WRONG
with a late conformance: tsum = 615.0  (plain 615.0)  OK
keys now: Tuple{Shape at Main.TS.S1, Shape at Main.TS.S2, Shape at Main.TS.S3, Shape at Main.TS.S4}
```
The redefinitions were `Core.eval(TS, :(area(s::S1) = 100.0))` and `:(area(s::S5) = 500.0)` after the first call; `w0 = Base.get_world_counter()` taken before them; the older-world calls are `Base.invoke_in_world(w0, …)`.

**A2. `facts_rt.jl`, `facts_rt2.jl`** (`experiments/factscompiler`, `--pkgimages=no --project=env`, `Compiler.activate!(; reflection = true, codegen = true)`, `JULIA_FACTS_COMPILER=0` then `1`; the bootstrap takes 23 s per process).
```
=== JULIA_FACTS_COMPILER=0 ===
copy's return_type(f2, Tuple{Real})                         = Float64
copy's return_type(_iterator_upper_bound, Generator{f2})     = Float64
copy's return_type(first, Tuple{typeof(gen)})               = Float64
Base today (system-image compiler): typeof(map(f2, Real[])) = Vector{Float64}, typeof(f2.(Real[])) = Vector{Float64}, promote_op(f2, Real) = Float64
=== JULIA_FACTS_COMPILER=1 ===
copy's return_type(f2, Tuple{Real})                         = Any
copy's return_type(_iterator_upper_bound, Generator{f2})     = Any
copy's return_type(first, Tuple{typeof(gen)})               = Any
Base today (system-image compiler): typeof(map(f2, Real[])) = Vector{Any}, typeof(f2.(Real[])) = Vector{Any}, promote_op(f2, Real) = Any
```
with `g(x::Real) = 1.0; f2(x::Real) = g(x)`. (The label "system-image compiler" in the script's last line was my assumption; the result shows `Base._return_type` is answered by the activated compiler, in facts mode.) The first script, with `f(x) = x + 1.0`, gave `Any` in both modes for `return_type(f, Tuple{Real})` (plain inference gives up on `+(::Real, ::Float64)` too) and `Real` against `Any` for `return_type(sum, Tuple{Vector{Real}})`.

**A3. `experiments/facts/acceptance.jl`** (`--project=TraitWorld`): 16 of 16 pass (G1.1–G1.15, G2.1), 8.7 s wall.

**Read, not run:** `codegen.cpp:7458–7506` (the cfunction entry stores `jl_world_counter` into the task's world age); `core.jl:296–560`; `facts.jl` (TraitWorld, in-tree, copy); `hooks.jl:120–180`; `strict.jl:50–110`; `implement.jl:60–125, 560–720`; `ownership.jl:200–269`; the git logs of all nine repositories since 2026-10-17 12:00.
