# Unification (W-83): a synthesis plan for the build

Status: **proposal** (2026-11-05, mine; W-83, W-27). Not normative. Written from the four pieces of unification work that lie in the repository (§1), on the user's request (2026-11-05): "There is a bunch of unification work lying around. This includes an original plan, a critical review, and some preliminary implementation work and notes from oc. Review what is there, and carefully create a fresh synthesis plan. No code, no running Julia, just a fresh markdown." Nothing was built or run for this plan. Every number quoted from oc's notes is unverified and says so.

## Contents

0. [Summary](#0-summary)
1. [What is there](#1-what-is-there)
2. [The design as synthesized](#2-the-design-as-synthesized)
3. [Decisions for the user](#3-decisions-for-the-user)
4. [The stages](#4-the-stages)
5. [What each stage retires in the record](#5-what-each-stage-retires-in-the-record)
6. [How the work is done](#6-how-the-work-is-done)
7. [Risks, in order](#7-risks-in-order)
8. [What the user decides now, and what the next session does first](#8-what-the-user-decides-now-and-what-the-next-session-does-first)

---

## 0. Summary

- **Four documents, one direction.** The evidence plan fixed the frame and passed gate A: level 2 of unification takes option (e), a negative membership never folds and a guard reads a cell ([compiler §7.1](../reference/compiler.md#71-memberships-and-dispatch), the user, 2026-10-29). The exploration turned the frame into mechanisms on upstream Julia (sets as `TypeName` memberships, keys as `Keyed{X, R, F}`, one dispatch under (e), a per-method facts policy with a dependency record, a machine-code store). The review corrected four load-bearing claims and verified the inventory of upstream places. oc's attempt built the first two of those mechanisms on a vanilla 1.13.2 base and stopped in the third.
- **What stands after all four:** the type system and dispatch halves as oc built them, under the review's corrections (exact intersection, structural negative-fold exclusion, C7 in `type_morespecific_`, the typemap's linear placement, cells per member type for parametric entries); the facts policy as a method property with a dependency record and G2 as a predicate on the record; keys through the `nospecializeinfer` path with a projection convention; the store out, `Callable` on `OpaqueClosure` out, sealed sets out.
- **What is open, in order of weight:** whether to build the code slot that makes result-edge revalidation sound (the review's H1 against oc's P1); how memberships compose through supertraits (oc composed chains in the runtime; the exploration has every entry explicit); the world protocol of `@implement`; the spelling of the `facts` policy (oc used an environment variable and session dictionaries); which Julia base and when to rebase on 1.14; and whether to adopt oc's branch after an audit or to rebuild from it as reference.
- **The recommendation:** adopt oc's `oc-build` branch at `c3f0b4bc11` after an independent audit (§4 stage 0), rework its two design divergences (§3 decisions 4 and 5), then build in stages 0 to 7, each with a gate (§4): the record and the audit; the type system; dispatch (gate B); the compiler policy and the record; the slot as a staged hypothesis measured before it is built; keys and guards (gate C); the surface and images; the workloads and the ports' cases. Level 3 is decided on paper after that.
- **The first week** is paper and audit: the references' Planned sections, the decision log, the registry rows for oc's measurements, the audit of 2,627 lines, and one no-build experiment on today's patched build (the red-green estimate, W-S0a). No Julia is built until the audit says what to keep.

---

## 1. What is there

### 1.1 The four sources

| Source | Where | Status in the record | What it settles | What it leaves |
|---|---|---|---|---|
| **The evidence plan** (2026-10-29) | [`2026-10-29-unification-evidence.md`](2026-10-29-unification-evidence.md) | proposal, mine; gate A passed (e); next "P1, then P2's memo under (e)" | three levels (membership in subtyping, one dispatch, one surface); the quick runs E-252 to E-259 and their reading per level (§6); level 1 supported, level 2 under (e), level 3 a simplification of the language, not of existing code | P1 (the build of level 1) and P2's memo were never started as planned; the exploration and oc's attempt took their place |
| **The exploration** (2026-10-29, a fresh-eyes Fable agent) | [`unified-build-from-vanilla-julia.md`](../explorations/unified-build-from-vanilla-julia.md) | exploration, not adopted; commit 4721a03 | each feature as an extension of an upstream mechanism (§1); the type system (§2), dispatch and the compiler (§3), the store (§4), the scope declarations (§5); stages S0–S5 (§6); decisions D1–D9 for the user (§9); the inventory of upstream places (§10), which the review verified line by line | D1–D9 undecided; the review's corrections not folded in |
| **The critical review** (2026-10-29) | [`2026-10-29-unified-build-review.md`](../reviews/2026-10-29-unified-build-review.md) | current; "not yet acted on in `writeup/`" ([INDEX](../record/INDEX.md)) | H1 result-edge revalidation unsound without a re-resolving call slot; H2 the over-approximating intersection is the wrong layer (three layers instead); H3 the negative-fold exclusion must be structural; H4 S1 alone unsound for dispatch; M1 the typemap's typename index; M2 C7 belongs in `type_morespecific_`; M3–M5 keys and the adapter; M6 worlds and images; M7 what a result edge may cover; M8 the store's two wrong claims; M9 `Callable`; M10 cells per member type; M11 no `invokelatest` precedent; verdicts on D1–D9 | its suggested order (addendum, W-S0a, W-S2a, S1 with the stopgap, S3's prototype) not taken up in the record |
| **oc's attempt** (2026-10-30/31, a QWEN38 class model) | [`attic/oc-notes/`](../../attic/oc-notes/README.md), [`attic/oc-traits/`](../../attic/oc-traits/gates/README.md); Julia branch `oc-build` of the `julia` repository | unfinished, not adopted; P1–P8 credited to the user are not in the decision log, so not in force; nothing registered as E- or W- | a plan M0–M7 folding the review in ([plan](../../attic/oc-notes/plan.md)); M0 (the C7 placement count), M1a, M1b and M2 built, gated and committed (§1.4); a dated log of rulings from the trenches ([notes](../../attic/oc-notes/notes.md)); eight deviations ([deviations](../../attic/oc-notes/deviations.md)); numbers with builds ([numbers](../../attic/oc-notes/numbers.md)); 22 gate scripts and 21 acceptance cases | M3 (the facts policy and the record) stopped on a hang in the system image's build; its working tree is not in any repository here (§1.4); M4–M7 unbuilt |

The user's standing words that frame all four: the overarching order (2026-10-29: finish the ports, then principled performance work, then "the major open question remains: Do we go for unification?"); gate A (2026-10-29: "Okay, given the evidence, we pursue (e). The exploratory note had an everything from 4 components framing. I think the evidence backs this up now. Sealed AbstractTypes make sense but are an optimisation for later (the spelling of this will be tricky)"); the fresh-eyes question (2026-10-29: "a fundamental reframing", not an incremental change); and on oc (2026-11-05: "oc-build was an attempt to implement the plan using a QWEN38 class model. Might be useful but didn't get close to finishing.").

### 1.2 What the exploration proposes, in one table

| Feature | Mechanism (exploration) | Stage | Review's verdict |
|---|---|---|---|
| Sets with late membership | a `TypeName` with an `open` bit; entries on the member's `TypeName`, world-stamped; a fallback in `subtype` after the chain fails; no negative folds for open sets; Base's sets closed, Core's kinds never members (§2.1–§2.2, §2.8) | S1 | storage and fallback right; the fold exclusion must be structural (H3); the intersection must stay exact (H2); S1 needs a dispatch stopgap (H4); positive folds need a `min_world` bound, images an activation list, redeclaration a walk by key (M6) |
| Keys | `Keyed{X, R, F} <: X`, a refinement set; the compilation signature of a `Compiled` position; the erased key `X` for `Dynamic`; a projection calling convention; the boxed adapter (§2.6, §3.4–§3.5) | S3 | `Keyed` is a subtype special case, not a declaration (M3); per-key inference needs the `nospecializeinfer` path, and the first-seen rule makes two compilation signatures per `(method, tt)` (M4); the boxed adapter is per member or reads offsets at run time (M5) |
| One dispatch | a bounded method is a method at the set; a membership lowers dispatch-cache worlds and invalidates no code; guards from shadow matches, reading cells; C7 in `ml_matches` (§3.1–§3.3) | S2 | the typemap's typename index must see memberships (M1); C7 belongs in `type_morespecific_`, which also shrinks the insertion cost (M2); cells per member type object for parametric entries (M10); the codegen precedent is wrong (M11) |
| Compiling by facts | a policy per method generalizing `concrete_only`; a dependency record on the `CodeInstance` with result edges, inlined-code identities, layouts, cells; G2 a predicate on the record; result edges revalidate instead of invalidating, so no second cache owner (§3.8) | S0 | the policy and the record yes; revalidation unsound against direct-call binding until a per-`MethodInstance` slot re-resolves the call (H1); a result edge covers only an emitted call whose result was used as a type (M7) |
| The store | machine code in shards by origin set, relinked by stable identity, validated by `verify_method_graph` (§4) | S4 | direction right; the JIT's object code cannot be written out, so a shard is a second code generation; cross-image calls are already slot-indirect (M8) |
| The surface | `facts`, `bounded`, `concrete`, `no_pirates` at module and method granularity; a trait module the four together (§5) | S5 | — |
| `Callable` | on `OpaqueClosure` with a world-following pointer cache (§2.7) | S3 | re-creates the thunk it removes; defer (M9) |

### 1.3 What the review changes, and what it confirms

The review's four high findings change the design; its mediums change the build; its lows are precision. What it confirms is as important: the frame, the inventory, the storage choice, the policy as a method property, the record, the erased key as `@nospecializeinfer`'s signature, the store's identity and exclusions. Its suggested order was: correct H1–H3 in the exploration; W-S0a (the red-green estimate, no build); W-S2a under both C7 placements; S1 with H4's stopgap and H3's exclusion; S3's prototype with M4's rule and M5's measurement before D2.

### 1.4 What oc built, found, and left

**Built, on branch `oc-build` of the `julia` repository, over the vanilla base `45b6d15e34` (v1.13.2):**

| Commit | Milestone | What |
|---|---|---|
| `2a2b2ba749` | M1a | the substrate: `open_set`, `never_member`, `generic_wrapper` bits on `jl_typename_t`; an atomic `memberships` list per typename; `Core.MembershipEntry` with `min_world` and `max_world`; `jl_declare_membership` under the world-counter lock; `has_open_set` in the memoized bits of `jl_datatype_t`; Core's kinds marked `never_member`; `Keyed`, `Dynamic`, `Compiled`, `Kept` as Core types |
| `361d3014f8` | — | a niced, memory-guarded build script for the worktree |
| `efb87dfbdf` | M1b | the subtype fallback in both chain walks; exact intersection with known members; `obviously_disjoint`, `jl_isa`'s type-value branch; `jl_could_join`; `has_open_set` consulted by `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, the lattice; an epoch that invalidates the memoized bit when a set opens later; wrapper erasure; constructors for the Core wrappers |
| `c3f0b4bc11` | M2 | methods at open sets in the typemap's linear list; C7 in `type_morespecific_` (with a bypass of the `obviously_disjoint` short-circuit); a set-to-methods index; match world ranges from entries (`jl_membership_match_range`); the declaration-time replay walk (the stopgap, P6) plus the dispatch-cache walk; the ambiguity report at a membership; a per-thread query-world override so inference sees entries; GC roots for the index |

Size: 24 files, +2,627/−171 lines. The largest changes are in `src/gf.c` (about 1,200 changed lines), `src/subtype.c` (about 870) and `src/datatype.c` (250). Gates: 22 scripts in [`attic/oc-traits/gates/`](../../attic/oc-traits/gates/README.md), reported 22 of 22 on the final M2 binary. Base's `subtype`, `core` and `ambiguous` suites reported inert within ±10 % at every milestone (`numbers.md`; the walls read *faster* than the control, which oc attributes to noise). The library stub [`Traits.jl`](../../attic/oc-traits/src/Traits.jl) is 188 lines: `@trait`, `@implement` (with a parametric form), three ccalls. No contract checks, no fields, no operations.

**M3 (the facts policy and the record)** was planned ([m3-editplan](../../attic/oc-notes/m3-editplan.md), 1,248 lines, with the coordinator's binding amendments §R), gated (9 scripts `m3_*`, 21 acceptance cases `AC_01` to `AC_20` in [`attic/oc-traits/test/acceptance/`](../../attic/oc-traits/test/acceptance/)) and implemented in part (14 files, +305/−37, plus a new `facts.jl` of 844 lines). Every full build of it hung in the system image's AOT emission stage (`--output-o` of `Base.Compiler`): 46 minutes and billions of allocations where the stage takes about a minute, an inference cascade under `jl_create_native_impl` ([the round-3 report](../../attic/oc-notes/logs-m3-round3-report.md)). The cause was not found. The report's two candidates: the bisection baseline never existed as a built tree (the system image had been built from M2's then-uncommitted working copy), and a content-sensitive emit-time inference loop in `abstract_call_method`'s region. A parallel 13-way bisection was withdrawn as invalid (shared machine, fixed windows). **The M3 working tree is not in any repository here:** the WIP commit `966bba2923` on `oc-build-wip` does not exist in the `julia` clone of this workspace. What survives of M3 is its edit plan, its gates, its acceptance cases and the report.

**Found in the trenches** (each a ruling in `notes.md`; each real, each a day someone else would lose again):

- Widening a self-described bit group of `jl_datatype_t` requires updating the matching `jl_svecset(...->types, …)` entry *and* auditing every Julia-side mask literal in `base/runtime_internals.jl` and `Compiler/src/typeutils.jl`, because `getfield` boxes per the self-description at a bootstrap world where promotion does not exist yet.
- Modern lowering defines types with `super = NULL` and a later `Core._setsuper!`, so the "membership final as the supertype" hook belongs in `jl_set_datatype_super` (`builtins.c`), not in `jl_new_datatype`.
- `jl_type_morespecific` short-circuits on `obviously_disjoint` before C7's arm is reached; the arm needs a bypass when either side has an open set.
- `jl_instantiate_type_with` does not take interleaved (tvar, value) pairs; the entry's instance is instantiated with `jl_instantiate_type_in_env`.
- `jl_type_infer` freezes the task's world at `jl_typeinf_world`, below every runtime entry's `min_world`, so inference never saw a membership until a query-world override existed. The override leaked across throws in two wrappers and needed `JL_TRY` restores.
- The entry's `min_world` must come from the counter under the lock, not from the declaring task's world (which lags the counter by one in a bare script); oc's answer was a "single-bump" protocol that also syncs the task's world from inside the C function.
- Vararg and union positions in signatures were skipped by the first version of every membership walk (the match range, the index, the substitution), each a stale-dispatch defect found by review.
- A C global index must be rooted in both GC implementations; two full collections freed it.
- The staged system images are not made stale by `src/` changes; after a struct-layout change they must be deleted by hand.
- The composed `future_min` bound must be the minimum over every chain, not the first chain scanned; a composed bound at a union position needs the union split.

**Left as deviations** (D-M2-1 to D-M2-8 in [`deviations.md`](../../attic/oc-notes/deviations.md)), of which two are design divergences this plan reworks (§3, decision 4): `<:` answers direct entries only while `isa`, intersection and dispatch compose chains (so `<:` is not transitive across memberships, and `isa(x, T)` can differ from `typeof(x) <: T`); a composed match carries a `spec_types` that matches the signature through the chain but is not `<:` it. The rest are small: the `_setsuper!` hook publishes without the lock (sound as argued); a struct subtyping a set opened *later* gets no entry (unreachable through `@trait`); the cycle guard is single-path; a longjmp under the lock leaks it (upstream's own class); the ambiguity report over-warns for fixed-versus-vararg pairs; a set mentioned only in a typevar bound is flagged but not indexed.

**Measured** (unverified; the builds are named in `numbers.md`):

- The C7 placement count (M0, on the patched build `00dcc9994c`, U5's five sessions): the flag placement would reach 92–99 % of every function's dispatch entries at a bounded method's definition; the `morespecific` placement with exact intersection reaches about the member entries only (0–13 for the real bounded functions, 11–23 per hypothetical `Base.show` on a set). This is W-S2a under both placements, as the review asked, and it confirms P3 and D5.
- The declaration-time walk (M2): 24 memberships into one open set, each member with a compiled specialization through the catch-all, cost 48 dispatch-replacement events against a naive ceiling of 576, in 0.014 s. One conservative declaration (a set under `Vararg`) lowered 2,898 live method-cache entries: the whole cache.
- A 200-method function with one bounded method looked up members within 1.04× of a control without the set.
- The 22-gate battery runs in 6.7 s.

### 1.5 Where the sources disagree

| Point | Exploration | Review | oc | This plan (§3) |
|---|---|---|---|---|
| Result-edge revalidation | yes, reusing `verify_method_graph`, no second owner (D3) | unsound without a re-resolving slot (H1); keep the second owner until the slot exists | "P1: we build the code slot", credited to the user; the second owner never built | the slot as a staged hypothesis: the record first, the estimate W-S0a, the slot in its own stage with a gate (decision 3) |
| C7's placement | in `ml_matches`, per match (§2.4) | in `type_morespecific_` (M2) | P3: `type_morespecific_`; M0 confirmed | `type_morespecific_` (decision 2) |
| Intersection | over-approximates for open sets (§2.3) | stays exact; `could_join` for forward-looking questions (H2) | as the review | as the review |
| Stage order | S0, S1, S3 (keys), S2 (dispatch), S4, S5 (D1) | split S0; S1 needs the stopgap; the typemap before S2 | M1 type system, M2 dispatch with the stopgap, M3 policy, M4 slot, M5 keys and guards, M6 surface, M7 workload | oc's order, with the slot conditional and images earlier (§4) |
| Transitive membership | every member of `B` is a member of `A` by its own entry; the runtime derives nothing (§2.2) | — | the fronts compose chains; `<:` does not (D-M2-1, D-M2-2) | explicit entries, no composition (decision 4) |
| The world protocol | the method-insertion protocol (§2.1) | positive folds bounded by the entry's `min_world` (M6) | a single bump that also sets the task's world | the method protocol plus `:latestworld` after `@implement` (decision 5) |
| The `facts` declaration | module and method options, a block form (§5) | — | an environment variable for `all`; session dictionaries for marks; persistence deferred | the module and method flags, serialized (decision 6) |
| The base | upstream, "1.14 once released" | — | P7: v1.13.2 at `45b6d15e34`, verified citations | 1.13.2 for the build; 1.14 as its own item after stage 3 (decision 7) |
| The boxed adapter | per key, reading the member's layout (§3.4) | per member, or offsets read at run time; measure first (M5, D2) | P2: variant (ii), one wrapper per keyed instance with a run-time offset table; a measured fallback | as oc, decided by the measurement in stage 5 (decision 8) |
| Where the record lives | `writeup/` per the rules | — | P8: `oc-notes/` only, no E- or W- IDs | everything in the record (decision 11) |

---

## 2. The design as synthesized

Condensed statements of what is built, each with its source and its state. The exploration carries the derivations; the review's findings are cited where they corrected it. "Built" means on `oc-build` at `c3f0b4bc11`, unverified until stage 0's audit. Nothing here is in force until it is in a reference (§4, stage 0).

### 2.1 The type system

- A set is a `TypeName` with an `open` bit; `never_member` marks Core's kinds; Base's typenames are born closed (exploration §2.1, §2.8; D8 accepted). **Built.**
- Memberships live on the member's `TypeName` as immutable entries `{set, member, instance, key, min_world, max_world, declarer, by}` in a copy-on-write list. `struct S <: X` for an open `X` adds a final entry with the type. **Built** (the hook moved to `jl_set_datatype_super`).
- **Every membership is explicit.** `@implement B S` declares `S`'s entries for `B` and for every supertrait of `B` (traits §3.6 requires the type's own implementation of each supertrait anyway). `@trait B <: A` declares `B`'s entry for `A`. The runtime never composes chains; `<:`, `isa`, intersection and dispatch read direct entries only (exploration §2.2; §3 decision 4). **To rework:** oc's composing fronts and D-M2-1, D-M2-2 go.
- `jl_subtype` consults the member's list where the chain fails and the right-hand side's name is open, in both chain walks. **Built.**
- **Three layers** (review H2): `<:` and `isa` read entries; `jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint` and the type cache stay exact in the current world (a known member keeps the exact result, a non-member gives `Union{}`); `jl_could_join(S, X)` answers the forward-looking question for the inference lattice and the shadow query, never for dispatch's match construction. **Built.**
- **The negative-fold exclusion is structural** (review H3): `has_open_set(t)` walks parameters and unions, cached on the type object; `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the `hasintersect` sites and `Conditional` refinement consult it before folding a negative. **Built.** Whether the epoch machinery (a 15-bit field and a lazy recomputation, built for sets opened by hand after types named them) is needed under the rule "a set is open from its declaration" is an audit question (stage 0).
- Positives fold only through entries, and a fold raises the consumer's `min_world` to the entry's (review M6). **Not built:** oc blocks every entry-answered positive fold until the raise exists.
- Worlds: a declaration takes `world_counter_lock`, stamps `min_world = counter + 1`, publishes, advances the counter; `@implement` lowers to the call followed by `Expr(:latestworld)`, as a method definition does (§3 decision 5). A redeclared key gives the old entry a `max_world` and runs an invalidation walk by key (M6). **To rework** (oc's single bump); the walk by key **not built**.
- `Keyed{X, R, F} <: X` is a subtype special case like `Type{T}` (review M3); `Dynamic{X}`, `Compiled{X}`, `Kept{X}` are Core structs holding `object::Any` (`Kept` a flag), members of `X` at the erased key by rule, not by entry. **Built** as types with erasure; the key's real form (`R`, `F`) waits for stage 5.
- `Type{S}` memberships answer through `jl_isa`'s type-value branch and `intersect` (review L10; open issue 91). **Built.**
- Inference's membership queries run at the query world, not at `jl_typeinf_world`. oc built a per-thread override; the cleaner form is a world threaded into the membership lookup from `ml_matches` and the insertion walk, which have one. An audit question (stage 0), not a decision.

### 2.2 One dispatch under (e)

- A bounded method is a plain method at `Tuple{typeof(f), X, …}`: no entry at `Any`, no worker, no untyped fallback, no keyword sorter of its own (exploration §3.1). This retires lowering L-3, L-47, L-48, L-50 and open issue 135. **Built** (the method table accepts them; nothing generates anything else).
- Methods naming an open set go into the typemap's linear list, never under `name1` (review M1). **Built**, with the 1.04× lookup check.
- C7 lives in `type_morespecific_`'s datatype case: at a position, a closed non-`Any` typename above an open one; open against open by set-in-set entries, else unordered (review M2, oc's P3, M0's count). **Built**, with the `obviously_disjoint` bypass.
- A membership lowers the `max_world` of leaf-cache and typemap-cache entries whose selected method changes, and invalidates no code (compiler §7.1). **Until guards exist (stage 5), the stopgap:** `jl_declare_membership` replays the insertion walk of `jl_method_table_activate` for every method at the set or a superset, as if the member's tuple had been inserted (review H4 option (a); oc's P6), and logs its volume. A staged deviation with an ID (§3 decision 9). **Built.**
- Match world ranges: an entry-derived match carries the entry's `min_world` into `valid_worlds`, at every position shape (fixed, vararg, union), with the bound the minimum over the chains that apply. **Built**, after three review rounds; under explicit entries (§2.1) the chain cases disappear.
- The ambiguity report at a membership: a set-to-methods index; at `jl_declare_membership`, for each function with a method on the new set and a method on another set the member is in, and no method on the tuple of both, a warning (an error under `no_pirates`); dispatch dominance suppresses it (D-M2-7's tightening). **Built** (the dominance tightening not).
- Abstract queries (review L7): a bounded method at an abstract non-member query is pruned exactly today, and the stopgap keeps compiled decisions sound when the membership lands; the forward-looking partial match (`spec_types = X`, never fully covering) arrives with the guards. **Built** as the sound half.
- Guards (exploration §3.3, review M10, M11): inference's shadow query records, per shadow `(Z, i)`, a cell per (member type object for parametric entries, else member typename; set), created by the compiler and hung on the member's `TypeName`, `min_world = typemax` until an entry matches; codegen loads the cell, compares against the task's world (`emit_tls_world_age_load`), and branches as `ir_inline_unionsplit!` does; the slow branch is a full dispatch whose result joins the bounded method's declared result with the selected method's. **Not built** (stage 5).

### 2.3 Compiling by facts: the policy and the record

- The policy is per method, from its scope (`facts` on a module, a method, a block); the compiler's own code is plain whoever calls it (facts §6.4). Under `facts`, inference commits at fact signatures only (facts §3) and marks run-time sites with the `nortsite` effect bit (compiler §1.3). The precedent is `concrete_only`, keyed by the callee; this is keyed by the caller's method (review L3). **Not built** (oc's M3, lost).
- **One CodeInstance per `(MethodInstance, policy, flags)`; no second cache owner** in the product setting. The test bed `all` is a session-wide default policy, not an owner token. This is the half of D3 the review accepts, plus oc's P1 reading of it. Its consequence without the slot (§2.4) is stated as a deviation: a facts caller that calls a plain callee by an emitted call holds an ordinary edge to it and is invalidated with it (G2's scope narrower than facts §2.2 states today).
- The dependency record: `CodeInstance.edges` gains result edges (an emitted call whose `rettype`, `exctype`, effects or constant the caller used as a type; nothing else, review M7), inlined-code identities (method plus a digest of the lowered code), layout identities, membership edges (the entry, for the `min_world` bound) and the existing fold records and binding edges. Consumers taught: the backedge iterator, `verify_method`, codegen's content walkers, the image writer. **Not built**; the edit plan's §3 and §R list every consumer verified at the base.
- G2 is a predicate on the record, computed at `finish!` and stored as a bit on `ci.flags` (every dispatch edge at a fact signature; every inlined identity's own record satisfies G2; result edges may go anywhere). Strict mode and `concrete` enforcement read it. **Not built.**
- `fold_call`, `known_type`, `split_call`'s inference half and the table of a call's targets, `return_type`'s plain answers, the inliner fixes: ported from the patched branch, which has each with its tests (julia-changes §2). **Not built** on this base.

### 2.4 The code slot (conditional)

- One slot per `(MethodInstance, ABI)` holding the current valid specialization pointer with its validity; written when a CodeInstance compiles and when one is invalidated. A static call that holds a *result* edge to its callee loads through the slot; every other call binds the address as today (review H1's fix). On a callee's replacement, callers with only result edges take the revalidation sentinel; the lookup paths (`jl_method_compiled_callptr`, `jl_rettype_inferred`) compare the edge against the callee's current result and promote or re-infer. **Not built.** Whether to build it is §3 decision 3; the no-build estimate W-S0a comes first.

### 2.5 Keys, the projection, attributes, the check

- Per-key inference via the `nospecializeinfer` path (review M4): a bounded method carries bound-position bits; the analogue of `get_nospecializeinfer_sig` maps a concrete member `S` at a `Compiled` position to `Keyed{X, R, F}` from `S`'s entry, and a `Dynamic` position to `X`. Two compilation signatures per `(method, tt)`: the key for static callers, the erased `X` for dynamic ones (`cache_with_orig` forced for keyed instances, review M3).
- The projection convention for static callers: the receiver by its own convention, `@const` and immutable fields by value, a two-word reference for each writable declared field, the boxed object where the keep analysis says the method may keep it (exploration §3.4).
- The boxed adapter, variant (ii): one wrapper per keyed CodeInstance reading receiver and field offsets from a table per (member typename, set) on the member's `TypeName`; cost target under E-256's 80–96 ns, goal E-164's band; the fallback is a wrapper per member, recorded before switching (oc's P2; §3 decision 8).
- Attributes: `Dynamic{X}` reaches the erased instance; `Compiled{X}` dispatches on the held object's type to the keyed instance; `Kept{X}` branches on its flag; casts are constructors; a set's name in a field means `Kept{X}` (traits §7).
- A declared result type recorded on `Method` as a bound inference may read because the body asserts it (D9, review L9).
- The definition-time check is one inference at the erased signature under a `bounded_check` flag (exploration §3.7): only the contract's operations resolve; any other use of the bounded argument is a run-time site, reported (`TraitUseError`) or classified "open"; the classification is a bit on the method.
- `Keyed` prints as the design prints keys (`ColTable at Vector{Vector{Float64}}`), in `show`, stack traces and `MethodError` hints (review L4; a rule in traits §12).
- **None of this is built.** It is stage 5, the largest stage.

### 2.6 The surface and images

- `@trait X … end` with operations, result types, fields and associated types; `@implement X S by field … end` running the contract checks in Julia (TraitWorld's `implement.jl` and `checks.jl` are the reference for the checks' semantics, traits §4 and §9) and then declaring the entries; `Self`; bounds in `where` and on struct parameters.
- The four declarations as module and method options, serialized with the method (`Method.facts` and the module option of the patched branch are the shape; `Expr(:meta)` on a method; a block form for `facts` only). A trait module is the four together. The environment variable switches the test bed `all` only (§3 decision 6).
- **Image activation for memberships:** a package image writes the entries it declares on foreign typenames in a list of its own (as `extext_methods`), activated at load before the image's code is validated; `verify_method` learns the membership edge kind and re-stamps worlds. This closes the soundness gap oc's reviewers found (R-7): entries serialize today with build-session worlds and `jl_activate_methods` has no membership arm. It moves earlier than oc placed it: before any port-shaped workload (stage 6, not after it).
- `no_pirates`: refusal at definition and at load through the method-definition and image hooks (the patched branch's piece 1), with the walk over the record for "would win at a fact" (facts §10.3).

### 2.7 What stays out, and why

- The machine-code store (D6; the user, 2026-10-28: "Pause the store, move for (b) when we pick it up again."): the record is built complete so that the store later adds a loader, not a mechanism; nothing is serialized or relinked. Review M8's two corrections (a second code generation at exit; cross-image calls already slot-indirect) go into the store's note when it is taken up (W-66).
- `Callable`'s `Dynamic` form on `OpaqueClosure` (D7): deferred by the review (M9); the `cfunction` thunk with `:caller_world` stays.
- Sealed sets (PE-19): the user's "optimisation for later".
- The 1.14 rebase: after stage 3 (§3 decision 7).
- `--trim` and `verify_main` under the policy; `Both{X, Y}` beyond what the ports need; the dynamic candidates' count per split beyond today's four.

---

## 3. Decisions for the user

Each row: what, the options, my recommendation, and where it would land once decided (the reference first, then the decision log). The decisions the review accepted as stated (D4 worlds, D8 the bootstrap bits, D9 the declared result on `Method`, D7 deferred) are listed once at the end, to confirm in one word.

| # | Decision | Options | Recommendation | Lands in |
|---|---|---|---|---|
| 1 | **The base of the build:** adopt oc's `oc-build` at `c3f0b4bc11` after an independent audit, or rebuild from the vanilla base with oc's code as reference. | (a) audit, then adopt what passes and rework the rest; (b) restart, reading oc for the trench findings. | **(a).** 2,627 lines with 22 behaviour gates, the three Base suites inert, and the review's corrections built in. The audit (stage 0) decides file by file; the two design divergences are reworked (decisions 4 and 5). Restarting re-pays the trench findings of §1.4 for nothing. | the decision log; `design/julia-changes.md` gains a section for the new branch |
| 2 | **C7's placement and the cost at a bounded method's definition** (exploration D5, review M2, oc's P3). | (a) in `type_morespecific_`, closed above open at a position; (b) per match in `ml_matches`. | **(a)**, as the review argued and M0's count confirmed (the flag placement would reach 92–99 % of a function's entries; the `morespecific` placement reaches the member entries). D5 is accepted with it: the warning for a bounded method on a foreign function stays the practical rule. | compiler §7.1's specificity rule (already there in words); the decision log; E- row for M0's count |
| 3 | **The code slot and result-edge revalidation** (exploration D3, review H1 and M7, oc's P1). | (a) build the slot in its own stage, after the record, with a synthetic-cascade gate; until then facts callers of plain callees are invalidated with them (a staged deviation); the second owner is never built. (b) keep the second owner as the product setting's design (the review's fallback). (c) decide after W-S0a. | **(c) then (a).** W-S0a (no build, minutes on the patched build) counts, in the forks' and C's sessions, the callers that hold only result edges to callees recompiled to an equal result. If the count is a material share of E-233's 1,884, the slot pays and is built in stage 4 with M7's definition of a result edge. If not, the deviation stands and the slot waits; the second owner is still not rebuilt, because the ports showed its cost (open issue 125: 0.24–0.34 s per session for Base's facts copies). | facts §6.3 and §2.2 (the scope of G2 without the slot, as a Planned revision); compiler §2 narrowed to the test bed; the decision log |
| 4 | **How memberships compose through supertraits.** | (a) every entry explicit: `@implement B S` declares entries for `B` and its supertraits; the runtime composes nothing; `<:` is transitive by construction. (b) oc's composed fronts with `<:` direct-only (D-M2-1, D-M2-2). (c) composition in `<:` too (the review's "blast radius" oc refused). | **(a).** It is the exploration's rule, it matches traits §3.6 (a type implements each supertrait by its own implementation), and it removes the chain walks, the min-over-chains bound, the diamond cycle guard and the two deviations. The cost is one entry per supertrait per member, written by the library. | traits §3.6 and §14 (a sentence); compiler §7.2 (the storage); the decision log |
| 5 | **The world protocol of a membership.** | (a) the method-insertion protocol (`min_world = counter + 1` under the lock, then advance) with `@implement` lowering to the call plus `Expr(:latestworld)`, so the declaring task sees its own declaration as it sees its own method definitions; (b) oc's single bump with the task's world synced from C. | **(a).** It is one protocol for methods and memberships, and it keeps C out of the task's world. The gates `m1_late_implement` and `m1_worlds_minworld` are re-pinned under it. | compiler §7.2; the decision log |
| 6 | **The spelling of the policy declarations.** | (a) module and method options as the patched branch has them (`Base.Experimental.@compiler_options facts=true`, `Method.facts`, `Expr(:meta)`), serialized with the method; the environment variable for the test bed `all` only; (b) oc's environment variable plus session dictionaries (`mark_facts!`), persistence deferred. | **(a).** The marks must survive into package images from the first facts-compiled package; the patched branch has the lowering (`src/ast.scm`, `julia-syntax.scm`, `method.c`, `module.c`) to port. The block form of `facts` follows. | facts §6 (Planned revision); traits §2; the decision log |
| 7 | **The Julia base, and the 1.14 rebase.** | (a) v1.13.2 at `45b6d15e34` for the build; rebase on 1.14.0 final after stage 3, as one work item (the scan names the collisions: `reset_safe` at effects bits 15–16, no inference lock, binding partitions, the `PossiblyAmbiguous` marker in `reinfer.jl`); (b) rebase first. | **(a).** The type-system and dispatch stages touch files 1.14 changed little; the compiler stage touches the files it changed most, so the rebase comes right after it, before keys. Entry lists, cells and the index are copy-on-write or atomic from day one so the rebase is a test, not a redesign. | the decision log; `julia-changes.md`; W- item for the rebase |
| 8 | **The key's form and the boxed adapter** (exploration D2, review M5, oc's P2). | (a) projection for static callers; variant (ii) for the boxed path (one wrapper per keyed instance, offsets from a per-(typename, set) table), measured in stage 5 against E-256 and E-164, with the per-member wrapper as the recorded fallback; (b) offsets in the key. | **(a)**, decided by the measurement, not now. The `jl_membership_t.key` field holds `nothing` (the erased key) until stage 5 defines the real form. | traits §6.7's status; compiler §7.x; the decision log at stage 5 |
| 9 | **The stopgap at a membership** (review H4 option (a), oc's P6). | (a) the replayed insertion walk at `jl_declare_membership`, logged, until guards land; then only the dispatch-cache walk stays; (b) refuse methods at open sets outside the library's generated ones until guards exist. | **(a)**, as a deviation with an ID (compiler C-) that stage 5 retires. It is less code and it measures what a membership costs (the volume row). | compiler §7.1 (a Deviations row); the decision log |
| 10 | **The store stays out** (oc's P4). | (a) out; the record complete; the slot's write points in a file of their own; (b) the per-environment shard as a stage. | **(a)**, as the user paused it on 2026-10-28. | the decision log (a confirmation) |
| 11 | **The record.** | (a) everything under the rules: oc's measurements re-run on the audited build and registered as E- rows, its gates copied into `experiments/` as the unification acceptance suite, the work as W- items, decisions in the log, deviations in the references' tables; `oc-notes` stays in the attic as history; (b) oc's P8 (notes beside the build). | **(a).** P8 contradicts "every kind of fact has one home". | `record/experiments.md`, `record/todo.md`, `record/decisions.md` |
| 12 | **`Keyed` in the user's view** (review L4). | (a) a compilation-signature type the user never writes and may see, printed as the key everywhere (`show`, `show_tuple_as_call`, `MethodError` hints); (b) hidden from reflection by a printer only. | **(a)**, with the rule in traits §12. The rule against hidden type parameters was about struct parameters; this one is visible and named. | traits §12; the decision log |
| 13 | **Confirm the review's accepted verdicts:** D4 (memberships advance the world counter, `min_world` on entries, positive folds bounded), D8 (Base's sets closed and Core's kinds never members as bootstrap bits), D9 (the declared result on `Method`), D7 deferred (`Callable` keeps the thunk), M1 (linear placement), M10 (cells per member type object), M11 (the guard's codegen shape). | confirm, or name one to revisit. | confirm. | compiler §7.2–§7.x (Planned); the decision log |

---

## 4. The stages

Each stage names what it builds, where, what it removes from today's encoding, its riskiest assumption, the smallest experiment that decides it, and its gate. Gates run on the shared host under `source env.sh` (4 cores, builds under `tools-local/loadguard.sh`), one Julia job at a time; full builds alone. A stage is done when its gate is recorded (an E- row with the build) and its reference sections flip from Planned to Implemented with their deviation rows. The order follows oc's, which the review's H4 forces (dispatch's stopgap before anything dispatches at a set), with two changes: the slot is conditional (decision 3), and image activation moves before the workloads.

### Stage 0. The record and the audit (paper; no build)

1. **The references first.** Planned sections, written from §2 of this plan: compiler §7.2 (memberships: storage, worlds, the three layers, the structural exclusion), §7.3 (one dispatch: the typemap, C7, the stopgap, the ambiguity report), §7.4 (guards and cells), §7.5 (keys as `Keyed`, the two compilation signatures, the projection, the adapter), §7.6 (the policy per method, the record, G2 as a predicate, the slot); facts §6 revised to the policy per method with G2's scope stated with and without the slot; traits §6.7, §12, §14 status lines; lowering §17 gains "what each stage removes". The exploration's status line points here for D1 and D3 and for §2.3, §2.4 and §3.3's codegen sentence, which the review corrected; the review's INDEX row flips to "acted on".
2. **The decisions** of §3 that the user confirms, in the log with the user's words and the sections they changed.
3. **The work items** registered (W-): one per stage, plus W-S0a and the 1.14 rebase; each with its source (this plan and the user's words).
4. **The experiments** registered (E-): M0's C7 count (re-run on the patched build, 4 cores, the script in [`c7count/`](../../attic/oc-notes/c7count/), ~10 min); W-S0a, the red-green estimate (the forks' session: of E-233's 1,884 invalidated instances, how many callers hold only result edges to callees recompiled to an equal result, under M7's definition; a script over `debug_method_invalidation`'s log and the caches; minutes); the gate battery and the three suites on the audited build, as the stage-1 and stage-2 rows.
5. **The audit of `oc-build`** (a Fable critic, reading the diff against §2 and the review; it may run the gates and the suites, nothing else): verdict per file (keep, rework, drop) with `file:line`; the D-M2 rows re-judged; the two divergences (decisions 4 and 5) sized; the epoch machinery and the query-world override judged against the simpler forms named in §2.1; the gates audited as code (oc found three defects in its own gates). The audit's findings go to a review document; what is done with each is recorded where it is done.
6. **The acceptance suite** of unification: oc's 22 gates, 9 M3 gates and 21 acceptance cases copied into `experiments/unification/` with a README that says what each pins and which stage runs it; the old G1 cases (`experiments/facts/acceptance_compiler.jl`, 35 checks) mapped to stages per oc's disposition table (m3-editplan §E).
7. **The build discipline** written into `session-notes/00-environment-and-workflow.md` (§6 of this plan).

**Gate:** the user has decided §3; the Planned sections exist; the audit's verdicts are in; W-S0a's number is in the registry. About a week of paper.

### Stage 1. The type system (rework of M1)

- **What:** the audited M1a and M1b with decisions 4 and 5 applied: explicit entries, no chain composition; the method-insertion protocol and `:latestworld`; the epoch removed if the audit agrees; `Type{S}` entries; the fold raise's hook left for stage 5. The library stub gains `@implement` for supertraits (entries for each).
- **Where:** `src/julia.h`, `src/datatype.c`, `src/subtype.c`, `src/jltypes.c`, `src/builtins.c`, `Compiler/src/tfuncs.jl`, `typelattice.jl`, `typeutils.jl`, `base/boot.jl`.
- **Removes:** nothing of TraitWorld yet; it removes the need for L-5 (`conforms`), T-23, L-43's world rule, L-4's edges, L-25.
- **Riskiest assumption:** that Julia's type code keeps its invariants with a subtype relation not derivable from `super` (the type cache's bits, `Union` normalization, `detect_ambiguities`). oc's suites say yes within the gate; the audit says whether the gate measured it.
- **Gate:** the 10 M1 gates; Base's `subtype`, `core`, `ambiguous`, `typemap` suites within 10 % of a control built on the same host (a new control: oc's numbers are from another machine); `detect_ambiguities(Base)` unchanged; the review's H3, M6 and L10 tests (compiled before the membership, answered after it, in both worlds).

### Stage 2. Dispatch (rework of M2); then gate B

- **What:** the audited M2 with the chain machinery removed (decision 4): the linear placement, C7 with the `obviously_disjoint` bypass, the set-to-methods index, match ranges from direct entries, the stopgap walk and the dispatch-cache walk (logged), the ambiguity report with dominance, the query world threaded from `ml_matches` if the audit prefers it to the override.
- **Where:** `src/gf.c`, `src/typemap.c`, `src/subtype.c`, `src/datatype.c`, the GC roots.
- **Removes:** the need for L-3, L-47, L-48, L-50, open issue 135, T-83's report in TraitWorld.
- **Riskiest assumption:** the stopgap's volume at a membership on a real port (M2 measured a scripted shape: 48 of 576 events, 0.014 s; and 2,898 cache entries for one conservative declaration). The forks' session is the measurement (W-92's shape: subtraits over `Column`).
- **Gate:** the 12 M2 gates; the volume row on a port-shaped script; the 200-method lookup within 2×; the suites inert; `detect_ambiguities(Base)` unchanged. **Gate B:** the user decides whether level 1 is adopted (membership in subtyping with dispatch sound under the stopgap). W-27 unqueues with it.

### Stage 3. The compiler policy and the record (M3, rebuilt)

Before anything else, the build pathology (§1.4):

- **E-first:** a fresh worktree at the audited base, built from scratch with per-stage timing recorded (Base, `Base.Compiler`'s `--output-o`, the system image: oc had no such row and bisected against a baseline that never existed). Then the smallest Compiler change alone, the `nortsite` effect bit at bit 15 (the patched branch's 0c589fd385 as the model), through a full build. If it builds, each further slice is one mechanism and one full build. If it hangs, the serial bisection the round-3 report designed (one probe at a time, windows of 700 s or more, the system image's own inputs as the baseline) runs before any design work, and the cause goes into the registry.

Then, in slices, each a commit with a green build:

1. the policy gate at `find_method_matches`, keyed by the caller's method flag (`is_fact_sig`, `fact_splits_ok`, `union_split_cost` ported from the patched branch's `facts.jl`); run-time sites and the `nortsite` bit;
2. the method and module flags of decision 6 (lowering and `method.c`, `module.c` from the patched branch); the environment switch for `all`;
3. the record kinds and their consumers (m3-editplan §3, with §R's corrections: the fold-materialization arm in the inliner, `widenconst` in `known_type`, the `ResultEdge` child through `:recursive_phase`, the content walkers listed in R-6);
4. G2 as a predicate and the bit on `ci.flags` (bit 4, with the image keep-mask), strict mode's and `concrete`'s readers;
5. `fold_call` with its record and `fold_holds`, `known_type`, `split_call`'s inference half and the table of a call's targets (the C ABI rule and the `:caller_world` thunk come with it);
6. `return_type` plain at non-fact signatures, with the image entries of the patched branch;
7. the inliner fixes useful without traits (the varargs tail, the cycle members).

- **Where:** `Compiler/src/{abstractinterpretation,typeinfer,tfuncs,effects,reinfer,inferencestate,types,facts}.jl`, `ssair/inlining.jl`, `src/gf.c`, `src/method.c`, `src/module.c`, `src/ast.scm`, `src/julia-syntax.scm`, `src/staticdata*.c`, `base/splittable.jl`.
- **Removes:** compiler §2's two modes side by side as the intended shape (the owner stays a token for the test bed and for `return_type`'s cache); C-16 and the owner-copy family; TraitWorld's policy hooks around the second owner.
- **Riskiest assumption:** that one cache per `(MethodInstance, policy)` with facts code calling plain code by ordinary edges keeps G2 in the ports' sessions as well as the second owner did (E-29: 0 of 15,030 lost in the product setting). The g2all-shaped count on the forks' and the demonstrators' sessions says.
- **Gate:** the acceptance cases plain and under `all` (oc's AC_01 to AC_20 as the start, the old G1 cases per the disposition table); the 9 M3 gates; the G2-bit share on a scripted session at or above 99 % with 0 non-stakeholder losses; Base's suites bit-identical in behaviour and within 10 %; `detect_ambiguities(Base)` unchanged. Then the **1.14 rebase** as its own item (decision 7).

### Stage 4. The code slot (if decision 3 says so)

- **What:** §2.4: `src/codeslot.c`, the write points in `gf.c`, the slot load at result-edge call sites in `codegen.cpp`, the sentinel hooks in the lookup paths, the result-edge validation in `reinfer.jl` against the callee's current result.
- **Riskiest assumption:** a caller that embedded anything but the callee's result type (a constant, an effect used for a fold) must hold a code edge; the record's classification asserts it (M7).
- **Gate:** the synthetic cascade (`f` calls `g` emitted; `g` redefined to an equal result: `f` survives and computes the same; to a different result: `f` re-infers), plain and facts; the session-level count (sentinel promotions against re-inferences on a replayed session), against W-S0a's estimate.
- **If skipped:** the deviation of decision 3 stands with its ID; nothing else changes.

### Stage 5. Keys, the projection, guards; then gate C

- **What:** §2.5 and §2.2's guards: `Keyed`'s rules in `subtype`, `intersect`, `type_morespecific_`, `obviously_disjoint`, `jl_isa_compileable_sig`, `jl_compilation_sig`, `cache_method`; the `nospecializeinfer` analogue and the two compilation signatures; the projection `specsig` and the boxed adapter (ii) with its table; the keep analysis as an inference escape pass; `declared_rettype` on `Method`; the shadow query, cells, the guard's `CallInfo` and codegen; the fold raise on positives (M6); the kept wrappers' dispatch; `convert(Kept{X}, x)`; the check as an inference mode; the library's contract checks moved over from TraitWorld. Immutable members and `@const` fields first; writable fields second.
- **Where:** `Compiler/src/abstractinterpretation.jl`, `utilities.jl`, `stmtinfo.jl`, `ssair/inlining.jl`; `src/gf.c`, `src/codegen.cpp`, `src/cgutils.cpp`, `src/method.c`; the library.
- **Removes:** the rewrite into workers and entries (lowering §8, L-3's mechanism, L-36, L-10, L-15, L-16), views and witnesses (§5, §6, L-1, L-2, L-21), the entry's attribute decision (T-94), the checker's reimplementation (T-91 to T-93); about 6,000 lines of `TraitWorld/src` by the exploration's count (an upper bound, review L2); the stopgap's code half (decision 9's row retires; the dispatch-cache walk stays).
- **Riskiest assumptions:** the leaf cache mapping concrete tuples to keyed instances under `cache_method`'s invariants (the fallback: keyed instances keep a small cache of their own in `gf.c`); the projection for writable fields (no two-word argument in `specsig` today); the adapter's cost. **Smallest experiment first:** the hand-written prototype of the exploration's S3 (one bound, two members sharing a key, the adapter for immutable members), measured against E-164's shapes, before the general rule.
- **Gate:** two members with one key give one keyed CodeInstance and one inference; a typed call in E-164's band (0.8 ns); the dynamic boxed call under E-256's 80–96 ns; CodeInstances per new member type O(keys); a guard site compiled before a late membership dispatches correctly after it, in both worlds, with the load hoisted out of a loop (one load in the LLVM IR); the writable-field kernel (sum a column, set a cell); `Vector{Kept{X}}` as U2 measured; TraitWorld's suite on the compiler's keys; E-215's schema independence (no new instance for a second schema); U9's census reproduced (7 sites, none in a loop, none in bounded code). **Gate C:** the user decides whether level 2 is adopted.

### Stage 6. The surface and images

- **What:** §2.6: the macros complete (operations, fields, associated types, families, `by`, the checks with TraitWorld's semantics), the four declarations, `Keyed`'s printing, `no_pirates`' hooks and walk, the image activation list for memberships with the membership edge in `verify_method`, the walk by key on a redeclared implementation; L-50's case (a bounded constructor beside the default ones) as a test.
- **Where:** the library; `src/staticdata.c`, `src/staticdata_utils.c`, `Compiler/src/reinfer.jl`, `src/gf.c`'s hooks, `base/show.jl`.
- **Removes:** the printer registry (piece 17); L-27, L-35 (`verify_main`'s walk) when `--trim` is taken up; TraitWorld's `hooks.jl` around strict mode where the walk moves into the runtime.
- **Riskiest assumption:** images declaring memberships on foreign typenames, loaded in any order and with images older than the declaring package reused (E-252's R6, R7, R8, R12): the activation list must re-stamp worlds and validation must see the entries before the image's code.
- **Gate:** a two-package image session in a fresh depot (the second package declares a membership on the first's type, precompiled; both load orders; an image older than the extension); the acceptance suite under each declaration alone and under all four; the errors of traits §9 and §10 for the named cases.

### Stage 7. The workloads and the ports' cases

- **What:** the two shapes oc planned (a `Column` trait with 3–4 members sharing at most two keys and a `groupreduce`-style kernel with one `Dynamic` position; an `ODEAlgorithm`-style open set with a capability predicate and a bounded `solve` on a foreign function), written fresh from the record's shapes; then the evidence plan's E2 cases in the unified form, each measured against today's evidence: SciML's front end on CommonSolve's `solve` (refused today by L-3 only), Makie's `Block` as an abstract type with `Axis` a subtype, `Scale` on `typeof(log10)`, `Lines`/`Scatter` as two families under one name, DataFrames' subtrait methods on a supertrait's operations (W-92) and its untyped API layer, NetworkDynamics' `GraphInterface{V}` beside `AbstractGraph`, L-50's bounded constructor.
- **Gate:** results identical to plain Julia's on each; instances per key, not per member; the guard census in U9's order; the sessions no slower than [the evidence](../design/evidence.md) §3 (the forks 3.89–4.14 s, TraitReport about 0.59 s, the trait demonstrators' session 0.96 s); the invalidation count at late loads in the acceptance suite's late-load cases. Then **level 3** (one language surface: the classification of plain functions as fully bounded or open, decision 41's reversal) decided on paper, with E-258's 4 of 74 and open issues 137 and 138 as its evidence.

**After the stages:** the 1.14 rebase if not done after stage 3; the store (W-66) on the record; sealed sets (PE-19); `Callable` on `OpaqueClosure` (D7) if a measurement names the thunk's cost; the demonstrators and the ports moved to the new library, by the rule that the demonstrators follow the design.

---

## 5. What each stage retires in the record

| Stage | Deviations retired | Open issues answered | Added as deviations (staged) |
|---|---|---|---|
| 1 | traits T-23 (`x isa X`, `T <: X`), lowering L-5, L-43, L-4, L-25 | 91's mechanism (`Type{S}` memberships) | positives not folded until stage 5 |
| 2 | lowering L-3, L-47, L-48, L-50; traits T-83, T-95; open issue 135 | 135 (a bounded constructor is a method at its bound) | the stopgap (decision 9); the ambiguity report's over-warn until dominance lands |
| 3 | compiler C-16, the owner-copy family; TraitWorld's policy hooks | 125 (no facts copies of Base, by construction) | G2's narrower scope without the slot (decision 3) |
| 4 | the deviation of decision 3 | — | — |
| 5 | lowering L-1, L-2, L-6, L-10, L-15, L-16, L-21, L-36; traits T-75, T-91 to T-94; the stopgap's code half | 124's mechanism (a subtrait is a Julia subtype), 112's cause (typed derived values no longer a patch), 137 and 138 as level 3's input | the adapter variant until measured; writable fields after immutable ones |
| 6 | compiler piece 17 (the printer registry); lowering L-27, L-35; facts F-6 (the deletion and binding hooks under `no_pirates`) | 139's message rule (the library's) | — |
| 7 | — | W-83's cases from the ports | — |

IDs are permanent: each retired row stays as its ID, marked *Retired*, pointing at the section that holds its subject.

---

## 6. How the work is done

oc's workflow ([workflow.md](../../attic/oc-notes/workflow.md)) is worth keeping in its shape, with four changes from what went wrong.

- **Roles.** A coordinator (the main session) owns the build slot, the notes, the gates and every commit; a planner writes a per-site edit plan with tree-verified context; a plan reviewer audits it against the tree; an author implements under the slot and never edits gates, tests or notes; an implementation reviewer reads the diff, not the plan's claims. Two rounds, then the coordinator rules. This caught five blockers in M2 that the gates had missed.
- **Change 1: reviewers of another model class.** oc's reviewers were fresh sessions of the same class as its author; the attic rates the result unverified. Plan and implementation reviews are by a Fable critic agent (`fable-critic`), briefed with the files and the invariants, not with the author's reasoning.
- **Change 2: the tree is never the only copy.** Every day's work is committed on a stage branch that is pushed; the WIP of M3 was lost with the old machine. Gates and acceptance cases live in `experiments/`, versioned, not beside a worktree.
- **Change 3: every full build records its stages.** Base, `Base.Compiler`'s `--output-o`, the system image, each with wall and peak RSS, in the registry row of the stage. A build that exceeds a stage's recorded time by 2× is killed and bisected serially. Staged images are deleted after any struct-layout change.
- **Change 4: the record is the home.** Numbers go to the registry with their build, decisions to the log, deviations to the references, the chronology to a session note. No parallel notes.
- **The machine.** `source env.sh`; 4 cores; one Julia job at a time; full builds alone under `tools-local/loadguard.sh`; the load checked before every build; quick gates (the 22-gate battery took 6.7 s on the old machine) rather than suites where a gate decides; the three Base suites only at a stage's gate.
- **Risk tiers** as oc's: the type system, dispatch, the compiler, codegen and images under the full pipeline; gate, test and library edits with one reviewer; notes and measurements by the coordinator.

---

## 7. Risks, in order

| Risk | Where it bites | What decides it, cheapest first | Fallback |
|---|---|---|---|
| **The system image's build hangs on Compiler changes** (M3's pathology) | stage 3's first slice | the from-scratch baseline with per-stage timing; the one-bit slice; serial bisection with long windows | the slices restructured so no struct of the Compiler changes shape before the system image is rebuilt from its own inputs; if a change to `abstract_call_method`'s region is the trigger, the gate moves to `find_method_matches`'s caller |
| **The slot's codegen** (H1) | stage 4 | W-S0a says whether to build it; the synthetic cascade says whether it is sound | the deviation of decision 3 stands; no second owner either way |
| **The projection for writable fields** | stage 5 | immutable members first; the forks' kernels that write through `Column` (E-214) second | boxed object plus `setfield_at_offset` for writable fields, as the patched intrinsics do today |
| **The leaf cache with `Keyed`** | stage 5's first day | `cache_with_orig` forced; guard signatures off; the hand-written prototype | a small cache per keyed instance inside `gf.c` |
| **The boxed adapter's cost** (M5) | stage 5 | the measurement against E-256 and E-164 | per-member wrappers, recorded |
| **Image activation of memberships** (R-7) | stage 6, but latent from stage 1 for any precompiled package that declares a membership | the two-package session in a fresh depot | memberships refused during precompilation until the list exists (a loud refusal beats a silent stale world) |
| **The stopgap's volume on a real port** | stage 2 | the forks' session's volume row | the warning for a bounded method on a foreign function; the conservative path narrowed to the member's typenames |
| **The typemap's linear list on `show`-class functions** | stage 2 | the 200-method check (1.04× reported) | the four walks consulting the query's membership list |
| **Memberships advancing the world meet C-3** (review L5) | from stage 1 in the demonstrators' sessions | counted in the volume row | fix C-3 (uncapped exact-type entries) before the demonstrators move |
| **The 1.14 rebase** | after stage 3 | the scan's list; the `reset_safe` collision at bit 15 is known | a release branch per stage until the rebase |
| **Reviewers confirming the author** | every stage | the critic agent, briefed without the author's reasoning | the coordinator's own probes as acceptance tests, as oc did in M2's round 2 |

---

## 8. What the user decides now, and what the next session does first

**Decisions now** (§3, the short form):

1. Adopt `oc-build` after an audit, or restart (recommended: adopt after audit).
2. C7 in `type_morespecific_`, and D5 with it (recommended: yes; M0's count).
3. The slot: decide after W-S0a (recommended), or build it unconditionally as oc's P1 said, or keep the second owner.
4. Memberships explicit, the runtime composes nothing (recommended), or oc's composed fronts.
5. The method-insertion protocol with `:latestworld` for `@implement` (recommended).
6. The policy as module and method flags, serialized; the environment variable for `all` only (recommended).
7. v1.13.2 for the build; 1.14 after stage 3 (recommended).
8. The adapter decided by stage 5's measurement (recommended).
9. The stopgap as a staged deviation (recommended).
10. The store out (recommended; confirms 2026-10-28).
11. Everything in the record (recommended).
12. `Keyed` visible and printed as the key (recommended).
13. The review's accepted verdicts confirmed.

**The next session, in order:** the Planned sections and the log entries for what the user decided (stage 0, items 1–3); the registry rows (item 4); W-S0a run on the patched build (minutes, `jl --name w83-s0a`); the audit brief to a Fable critic (item 5); the acceptance suite copied into `experiments/unification/` (item 6). No Julia is built before the audit's verdicts are in.
