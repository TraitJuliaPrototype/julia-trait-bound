# Fresh-eye review of reference/compiler.md (2026-10-26)

**Reviewed:** `writeup/reference/compiler.md` at design-repository commit c6662bf, against the patched Julia `julia-1.13/` at fa4e7f5798 (branch `trait-world-1.13`, v1.13.2-45) and TraitWorld main 4410407. Source line numbers below are those of fa4e7f5798.

**Method.** I read `reference/README.md`, `compiler.md` in full, `facts.md` in full, the sections of `lowering.md` and `traits.md` that `compiler.md` links or that link back to it (lowering §2, §8.2, §12, §13, §15–16, §18; traits §2, §13), the glossary, `design/julia-changes.md`, the linked open issues (27, 30, 35, 46, 50, 52, §1.1, §1.19) and the decision rows on the compiler. For every interface the page names I located the symbol in `julia-1.13/` and read the code behind the claims: `Compiler/src/facts.jl` whole; the facts-related parts of `typeinfer.jl`, `abstractinterpretation.jl`, `tfuncs.jl`, `ssair/inlining.jl`, `stmtinfo.jl`, `precompile.jl`, `bootstrap.jl`, `types.jl`; `src/gf.c` (the switch, split tables, hooks, backedge invalidation, invoke-edge invalidation, compiled-callptr lookup, the compile fallback, `jl_get_specialization1_worlds`, the call-site cache, the facts dispatch entries, the profiler); `src/runtime_ccall.cpp` and `src/codegen.cpp` (the `:caller_world` thunk, `applygeneric_for`/`invoke_for`, `invokelatest`, `_apply_iterate`); `src/module.c`, `src/method.c`, `src/julia-syntax.scm`, `src/ast.scm`, `src/staticdata.c`, `src/staticdata_utils.c`, `src/intrinsics.cpp`, `src/runtime_intrinsics.c`; `base/splittable.jl`, `base/experimental.jl`, `base/show.jl`, `base/reflection.jl`, `base/Base.jl`. I ran Julia once (under the required wrapper, about 10 s): it showed the system image at `julia-1.13/usr` is built from 6d480d0753 (2026-10-21 00:53 UTC) plus the constant-propagation change (`facts_const_prop_call` present, `facts_const_call` absent, `is_fact_sig` with one method `(Any,)`, `union_split_cost` absent), so fa4e7f5798 is in the source but not in the build; the same run checked `is_closure_type` on a closure, `sum`, `Fix1`, `kwcall` and a keyword body. I checked every anchor the page links. I did not run the acceptance suite, TraitWorld's tests, any image build or any `--trim` build; I did not verify TraitWorld beyond grep of the symbols it uses; I did not re-derive the stock semantics of `jl_get_specialization1_worlds` or of `findsup` beyond reading them. The owner-aware backedge rule (§2.8), the per-call-site cache entries (§3.2), the `:caller_world` thunk (§3.1), the hooks (§5.1), `--trim` (§2.10), the image rules (§2.9), the mode rule (§2.3–2.6), inlining across owners (§2.7), the meta lowering into keyword sorters and positional forwarders (§2.2), `known_type` (§4.1) and the split table (§4.3) match the code as read, with the exceptions below.

**Counts.** High 1, Medium 7, Low 11.

---

## High

### H1. A call at a fact signature that Julia's method matching rejects is a dynamic call with no edge, but is not a run-time site: §1.5's rule does not reach it

**Location.** `writeup/reference/compiler.md:121`–`128` (§1.3) and `:174`–`178` (§1.5); `julia-1.13/Compiler/src/abstractinterpretation.jl:129`–`137`, `:393`, `:415`; `julia-1.13/Compiler/src/facts.jl:333`–`346`.

**What is wrong.** §1.3 says a call is a run-time site when its signature (or a split) is not a fact, and that "a call at a fact is inferred as plain Julia infers it, with its edges". §1.5 says no asserted effect applies to a frame with a run-time site, because "an assertion would let a caller fold a call whose dispatch no edge records". The code marks a frame (`sv.facts_rtsite = true`) only when `find_method_matches` returns `FACTS_ABSTRACT_SITE` (`abstractinterpretation.jl:134`). But `facts_find_method_matches` hands a fact signature on to `find_simple_method_matches` / `find_union_split_method_matches` (`facts.jl:342`, `:345`), which return a different `FailedMethodMatch` when more than `max_methods` methods match (`abstractinterpretation.jl:393`, `:415`). That happens at fact signatures of the `Vararg` form (`Tuple{typeof(vcat), Vararg{Int}}`, which `is_fact_sig` accepts: verified by the run) and at union splits with many applicable methods. Such a call gets `Any` and records no edge, exactly like a run-time site, yet the frame is not marked, so a method-level or statement-level `@assume_effects` on it still applies (`typeinfer.jl:491`, `abstractinterpretation.jl:3651`). A caller may then fold the frame over a dispatch no edge records; a stakeholder's later definition at that signature invalidates nothing, and the fold is stale: G1 is broken through the one path §1.5 exists to close. The same holds for the `si.saw_latestworld` early return (`abstractinterpretation.jl:129`–`132`) and for every other `CallMeta(Any, Any, Effects(), NoCallInfo())` return in the facts mode (`abstract_invoke`'s bail-outs, `abstractinterpretation.jl:2369`–`2370`). The exposure needs an `@assume_effects` on a frame with such a call; under the test bed `all` Base's `:foldable` helpers over `Vararg` are the obvious place, and facts F-16 (a Base method asserted `:foldable` still folded over run-time sites under `all`, "not diagnosed") may be this mechanism. Plain Julia has the same un-edged call, but the facts mode claims to close it ("nothing is skipped", facts §2.1).

*Verified* by reading the three code paths; not run.

**Fix.**
- Code: mark the frame for every call in the facts mode that records no edge, not only for `FACTS_ABSTRACT_SITE`: in `abstract_call_gf_by_type`, `isa(matches, FailedMethodMatch) && facts_mode(interp) && sv isa InferenceState && (sv.facts_rtsite = true)`, and the same at the `saw_latestworld` return; or make `facts_find_method_matches` turn a "too many methods" result into `FACTS_ABSTRACT_SITE`. Then test F-16's case again.
- Text: in §1.3 define the run-time site by what it records, not only by the signature: "a call that records no edge: a call at no fact signature, and a call at a fact signature that Julia's method matching gives up on (more than `max_methods` methods, a call after `:latestworld`)". Change §1.3's rule to "A call at a fact that Julia resolves is inferred as plain Julia infers it, with its edges". Add a deviation row (C-15) for the unmarked cases until the code is fixed, and point facts §4.1 ("The caller records the fact as an edge") and facts §8 at it.

---

## Medium

### M1. §1.4 step 1 is stated as exact, but a facts answer that is a constant or a concrete type can be wider than plain inference's `Union{}`

**Location.** `writeup/reference/compiler.md:147`; `julia-1.13/Compiler/src/tfuncs.jl:3181`–`3185`; `writeup/reference/facts.md:121`.

**What is wrong.** Step 1 folds the facts mode's own answer "when it cannot be wider than plain inference's: a constant, a concrete type that is not a kind, or `Union{}`". Facts inference is wider than plain inference at every run-time site, so its result contains plain's; but plain's result can be `Union{}` where facts' is a constant: `g(x) = (h(x); 1)` with every method of `h` at `x`'s abstract type throwing gives plain `Union{}` and facts `Const(1)`, folded as `Int`. facts §2.1 lists exactly this ("`Union{}` where every method at a run-time site throws") as a G1 exception, so the two references disagree on whether step 1 is exact.

*Reasoning* from the code at `tfuncs.jl:3183`; not run.

**Fix.** Replace "when it cannot be wider than plain inference's" with "when it can differ from plain inference's only where plain's is `Union{}`: a constant, a concrete type that is not a kind, or `Union{}` ([facts §2.1](facts.md#g1), the exception)".

### M2. The references, `julia-changes.md` and the work queue disagree on whether fa4e7f5798's two changes are built; "Implemented" does not say whether it means the source or the build

**Location.** `writeup/reference/compiler.md:16` ("Implemented: in the patched Julia today"), `:99` ("planned: today at most `MAX_FACT_SPLITS` concrete tuples"), `:379` ("planned: F-18, W-41"); `writeup/reference/facts.md:606`, `:609` (F-15, F-18 "not attempted"); `writeup/design/julia-changes.md:30`–`31` ("fa4e7f5798 (committed; built the night of 2026-10-22)"); `writeup/record/todo.md:50`, `:52` ("built tonight").

**What is wrong.** The source at fa4e7f5798 has `fact_splits_ok(T, max_union_splitting)` with `union_split_cost` (`facts.jl:248`–`290`) and `facts_const_call` (`facts.jl:112`–`135`), called from the gate (`abstractinterpretation.jl:902`). The system image at `julia-1.13/usr` is built from 6d480d0753 plus the constant-propagation change (verified by the run: `Base.GIT_VERSION_INFO.commit`, `facts_const_call` undefined, `is_fact_sig` with one method). So compiler.md and F-15/F-18 describe the build, `julia-changes.md` and the work queue describe the source and claim a build that this image is not. A reader cannot tell which "today" a status line means.

*Verified* by the run and by reading the source.

**Fix.** State the convention once in `reference/README.md` and at `compiler.md:16`: "Implemented" means in the source at the commit named at the top of the page, and the Deviations table names the build where it matters. Then either retire F-15/F-18 and drop the parentheticals at `:99` and `:379` (status: Implemented in source, unbuilt), or keep them and correct `julia-changes.md:30`–`31` and `todo.md:50`, `:52` to "committed, not built in the image of 2026-10-21". Name the build commit (6d480d0753 plus 2943086604's change) wherever an acceptance number is cited for G1.30/G1.31.

### M3. lowering §12 says a `Callable`'s `cfunction` runs the function "as plain code"; compiler §2.5 and §3.1 say the default owner's code, which for a trait module's function is facts code

**Location.** `writeup/reference/lowering.md:493`; `writeup/reference/compiler.md:352`–`359`, `:491`; `julia-1.13/src/runtime_ccall.cpp:422`–`423`, `julia-1.13/src/gf.c:434`–`436`.

**What is wrong.** The `:caller_world` thunk asks `jl_type_infer(mi, world, SOURCE_MODE_ABI, trim)`, which infers under `jl_default_owner(mi)`: `:facts` for a facts method. A closure defined in a trait module, or an always-facts method, passed as a `Callable` runs its facts code through the pointer, not plain code. lowering.md's "as every call through a `cfunction` does" contradicts compiler.md, which wins on the interface.

*Verified* by reading.

**Fix.** lowering.md:493: "the function runs the code of its default owner: plain code for a plain or neutral function, facts code for a function of a trait module ([compiler §2.5](compiler.md#25-dispatch-from-facts-code), [§3.1](compiler.md#31-the-cfunction-calling-convention-caller_world))".

### M4. §1.5's status omits the method-level failure recorded as facts F-16; compiler.md has no row and no pointer

**Location.** `writeup/reference/compiler.md:170`–`176`; `writeup/reference/facts.md:607` (F-16).

**What is wrong.** §1.5 says "Implemented, except the statement level (C-13)". facts F-16 records that under `all` a Base method asserted `:foldable` is still folded over run-time sites (the `promote_type(Int, StaticInt{2})` case), undiagnosed. That is a deviation of the interface §1.5 describes, at the method level, and it is invisible from compiler.md. H1 is a candidate cause (a "too many methods" call inside the asserted frame is not marked); C-2's shared cache is the other.

*Verified* that compiler.md does not mention F-16; the cause is *reasoning*.

**Fix.** Add a row C-15 (or fold into the row H1 asks for): "§1.5 | no asserted effect applies to a frame with a run-time site, at either level | under `all` a Base method asserted `:foldable` is folded over run-time sites; as facts F-16; candidate causes H1's unmarked calls and C-2's shared cache | `ndport/scripts/p3_promote3.jl`". Change §1.5's status line to "except the statement level (C-13) and one method-level case (C-15)".

### M5. §2.2 presents `@boundary` and `@always_facts` as the macros that set the method flag; neither exists

**Location.** `writeup/reference/compiler.md:237`–`246`; `TraitWorld/src/compiler.jl:27`–`43` (`@machinery`), `TraitWorld/src/implement.jl:827`, `TraitWorld/src/trait_module.jl:709`.

**What is wrong.** The interface is the meta `Expr(:meta, :facts_boundary)` / `Expr(:meta, :facts_always)` in a method body (`src/method.c:959`–`964`, `:1014`–`1017`). The page shows two macro definitions without saying they are illustrations. Julia defines no such macros; TraitWorld's spelling is `@machinery` for always-facts and a hand-inserted `Expr(:meta, :facts_boundary)` for boundaries. A newcomer reads §2.2 as "write `@boundary f(x) = …`".

*Verified* by grep of `julia-1.13/` and `TraitWorld/src/`.

**Fix.** Replace the code block with the two `Expr(:meta, …)` forms as the interface, and one sentence: "A macro that puts the meta first in the body, as `@inline` puts `Expr(:meta, :inline)`, is enough; TraitWorld's is `@machinery` for always-facts methods ([lowering §2](lowering.md#2-modes-owners-and-images))."

### M6. §4.3 says the split table's target makes a static call; it does so only where every argument position at the site is concrete

**Location.** `writeup/reference/compiler.md:599`–`600`; `julia-1.13/Compiler/src/facts.jl:660` (`split_table_type`), `julia-1.13/Compiler/src/ssair/inlining.jl:488`; `julia-1.13/base/splittable.jl:17`–`24`.

**What is wrong.** The table's key `A` records each other argument as its concrete type or `Any` (`split_table_type`). The target asserts `args::A...`; where an `A` is `Any` the assertion is empty and `(f::F)(x::T, a::Any)` inside `_SplitTargetFacts` is a run-time site (a dynamic dispatch inside the target), not "static". Likewise `R` is `Any` for a non-concrete declared result, and then only the site's assertion to `RT` applies, not the target's.

*Verified* by reading.

**Fix.** At `:600`: "The target asserts each argument to its type at the site, so its call is static where the site's other argument types are concrete; an argument the site holds at an abstract type is passed as `Any` and dispatched inside the target. `R` is the declared result where it is concrete, else `Any`; the split asserts the fallback's result to `RT` in every case (§4.2)."

### M7. §6.3's bootstrap entry does not cover the test bed's run-time `return_type` entry

**Location.** `writeup/reference/compiler.md:723`–`729`; `julia-1.13/Compiler/src/bootstrap.jl:33`; `julia-1.13/Compiler/src/facts.jl:384`.

**What is wrong.** The bootstrap list compiles `_return_type(::NativeInterpreter, ::DataType)`. Under the test bed `return_type_interp` is `PlainRTInterp` (§1.4), so the entry called is `_return_type(::PlainRTInterp, ::DataType)`, which the list does not name. §6.3's claim "the system image holds its code" holds for the product setting; under `all` the first `collect` of a generator compiles it unless the facts system image's build happens to.

*Reasoning* from the two files; not measured.

**Fix.** Either add `Tuple{typeof(_return_type), PlainRTInterp, DataType}` to the bootstrap list, or say in §6.3 "in the product setting; under the test bed the entry is `PlainRTInterp`'s (§1.4), compiled by the facts system image's build".

---

## Low

### L1. Stale `file:line` citations

**Location.** `writeup/reference/compiler.md:105`, `:160`, `:784`–`:793`.

**What is wrong.** At fa4e7f5798 these point at other code:
- `:105` `src/gf.c:2470`–`2475` (invoke-edge invalidation) is at `src/gf.c:2532`–`2537`;
- `:160` `src/gf.c:3496` (`jl_method_compiled_callptr_owner`) is at `:3559`;
- C-1 `facts.jl:105` (`is_compiler_code`) is at `:192`; `src/gf.c:4802` (`facts_callee_owner`) is at `:4864`;
- C-3 `src/gf.c:4611` (the cap at the latest world) is at `:4670`–`4673` (`call_cache_exact`); `runtime_ccall.cpp:424` is right;
- C-4 `src/gf.c:3733` (the normalization) is at `:3790`–`3795`;
- C-5 `src/gf.c:3782 ff.` is at `:3845` ff.;
- C-6 `src/gf.c:3775` (the module option read for owner `nothing` only) is at `:3837`–`3841`;
- C-8 `facts.jl:465` (`split_call`) is at `:504`;
- C-9 `facts.jl:305` (the limit of 2000) is at `:430`;
- C-10 `facts.jl:259`, `:355` are at `:367` (`cache_owner(::PlainRTInterp)`), `:384` (`return_type_interp`), `:466` (`facts_plain_return_type`);
- C-13 `abstractinterpretation.jl:3644`–`3647` is `:3646`–`3654`.
The rest (`typeinfer.jl:1654`, `:1657`; `facts.jl:47`, `:52`, `:60`, `:69`, `:85`, `:87`; `gf.c:424`; `module.c:749`; `precompile.jl:396`, `:443`–`444`, `:455`–`489`; `abstractinterpretation.jl:2369`; `tfuncs.jl:3269`) are right.

*Verified.*

**Fix.** Update the numbers, and name the commit the numbers belong to at the top of the Deviations table ("lines as of fa4e7f5798").

### L2. Measurements in a reference

**Location.** `writeup/reference/compiler.md:518`–`521` (E-145: "up to 1.5× faster", "8 bytes per value"), `:786` (C-3: "about 1 KB allocated"), `:797` (C-14: "about 8 ms").

**What is wrong.** `reference/README.md:44`: a number appears only when it is part of the design.

**Fix.** Replace the numbers with links: "faster on large mixes of many types, at a word per value ([evidence](../design/evidence.md), E-145)"; in C-3 and C-14 "a lookup and an allocation per pointer (G1.24)", "its maker, thunk and target compiled (E-145)".

### L3. `facts_const_prop_call`'s signature is wrong, and the gate's function in the source is `facts_const_call`

**Location.** `writeup/reference/compiler.md:369`–`370`; `julia-1.13/Compiler/src/facts.jl:112`, `:148`; `julia-1.13/Compiler/src/abstractinterpretation.jl:902`.

**What is wrong.** The signature is `facts_const_prop_call(interp, other, result, f, arginfo, si, match, sv)`; the gate calls `facts_const_call(interp, other, result, f, arginfo, si, match, sv, invokecall)`, which runs concrete evaluation, semi-concrete evaluation, then `facts_const_prop_call`.

**Fix.** List `facts_const_call` with its signature and say it orders the three; keep `facts_const_prop_call` as the last step (see M2 for its status).

### L4. "Only `find_method_matches` asks `is_fact_sig`" is not exact

**Location.** `writeup/reference/compiler.md:105`; `julia-1.13/Compiler/src/facts.jl:447`, `:454`.

**What is wrong.** `rests_on_facts` (§1.4, the fold's walk) asks it too, for every edge. The sentence's point (that `invoke` and `hasmethod` are not gated) is right.

**Fix.** "Only `find_method_matches` gates a call by `is_fact_sig`; `abstract_invoke` and `hasmethod`'s tfunc …".

### L5. "The two fields are independent" misleads

**Location.** `writeup/reference/compiler.md:71`; `julia-1.13/Compiler/src/facts.jl:40`–`54`, `:60`.

**What is wrong.** Three pairs occur: `(true, :facts)`, `(false, nothing)` and, under the test bed, `(true, nothing)`; `facts_interp`, `plain_interp` and `interp_for_owner` fix the pairing. `(false, :facts)` never occurs and would cache plain code under the facts owner.

**Fix.** "The fields are set together: `:facts` always with `facts = true`; `nothing` with `facts = false` in the product setting and, today, `facts = true` under the test bed ([C-2])."

### L6. "Each split is a fact, with its edge" holds for a facts caller only

**Location.** `writeup/reference/compiler.md:563`; `julia-1.13/Compiler/src/facts.jl:706`.

**What is wrong.** `abstract_split_call` calls `abstract_call` at the candidates' union; the gating by `is_fact_sig` happens only when the interpreter is in the facts mode. TraitWorld's `@dynamic_of` and `@kept_of` use `split_call` inside entries (`TraitWorld/src/core.jl:677`, `:711`), which are boundaries compiled in a plain caller's mode; there the split follows plain rules (`max_methods`, an edge at an abstract signature where a candidate is not concrete).

**Fix.** "In the facts mode each split is a fact, with its edge; in plain code the split is inferred as plain Julia infers a union."

### L7. Terms used on this page without a definition or a link

**Location.** `writeup/reference/compiler.md:9`–`13`, `:52` (stakeholder, pirate), `:100`–`101` (kind, used before it is listed), `:359`, `:785` (neutral method).

**Fix.** Add to the term list at `:9`: stakeholder and pirate (link facts §1), neutral method (link facts §6.1), kind ("`DataType`, `UnionAll`, `Union`: the types of types").

### L8. The `Vararg` form's "concrete member" omits the recursion the code has

**Location.** `writeup/reference/compiler.md:100`; `julia-1.13/Compiler/src/facts.jl:225`–`241`.

**What is wrong.** `concrete_member(p)` is `(isdispatchelem(p) && !iskindtype(p)) || vararg_fact(p)`: a member may itself be a tuple type with a concrete `Vararg` tail (`Tuple{Tuple{Int, Vararg{Int}}}` is a fact signature). The page's "a tuple type of concrete members" does not admit a `Vararg` tail inside a member.

**Fix.** "A concrete member is a dispatch element that is not a kind, or a tuple type of concrete members, itself with or without a concrete `Vararg` tail."

### L9. History flavour in the summary

**Location.** `writeup/reference/compiler.md:25`.

**What is wrong.** "general improvements to Julia that the facts mode made necessary" tells how they came about.

**Fix.** "Mechanisms 3 and 4 are general improvements to Julia that the facts mode relies on."

### L10. The glossary's "World-checked call-site cache" does not match §3.1's thunk

**Location.** `writeup/glossary.md:327`–`331`; `writeup/reference/compiler.md:474`–`478`.

**What is wrong.** The glossary says each cache entry holds "a type, the entry point … and the world range". A `:caller_world` thunk's entries hold a pointer, a `CodeInstance` and a world range for one fixed signature; no type is compared. Only the per-call-site dispatch cache (§3.2) compares types.

**Fix.** In the glossary: "Each entry holds the entry point of the code dispatch chose and the world range in which that choice holds; a per-call-site cache also keys by the argument types."

### L11. "One entry per target" is one per target and contiguous world range

**Location.** `writeup/reference/compiler.md:490`; `julia-1.13/src/runtime_ccall.cpp:434`–`446`, `:473`–`481`.

**What is wrong.** A new lookup joins an existing entry only when its range meets the entry's (`lo <= emax + 1 && emin <= hi + 1`); the same `CodeInstance` valid in two ranges that do not meet gets a second entry. Minor; the rooting argument still holds.

**Fix.** "one per target and range of worlds that meet".

---

## Notes that are not findings

- §2.8 (owner-aware bare `MethodInstance` edges): I looked for a cross-owner dependence that is recorded as a bare edge and found none. `leaves_to` always names the other owner's `CodeInstance`; inlining across owners names it too (`inlining.jl:1759`, `:949`); `compileable_specialization` can leave a bare edge to a widened instance (`inlining.jl:861`–`865`), but the caller's assumed result rests on the exact `CodeInstance` edge kept from inference, and the widened instance's fresh code computes the same results in the same world. No finding; recorded as *reasoning*.
- §3.2's exact-type entries are sound by the cap at the latest world and because `jl_typemap_assoc_exact` returns an entry only for arguments that pass its guard signatures. *Verified* by reading `gf.c:4661`–`4684` and the stock typemap lookup.
- §5.1's five rules for the definition hook match `gf.c:2306`–`2318`, `:3397`, `:3408` exactly (before `jl_method_table_add`, after the world-counter lock, latest world, thread-local re-entrancy guard, skipped while a non-incremental image is generated).
- §2.2's claim that lowering carries the meta into positional forwarders holds: `optional-positional-defs` copies the whole prologue (`julia-syntax.scm`, the `,@prologue` lines of that definition); the keyword sorter and the no-keyword method get it through `facts-meta-only` (`:562`, `:583`).
- §2.10, §2.9 and the C-12 row match `staticdata.c:1227`–`1230`, `staticdata_utils.c:554`–`567`, `precompile.jl:411`–`414`, `:455`–`489`.

---

**Addendum (2026-10-26, filing).** `buildcheck.jl` is filed in `experiments/review-2026-10-26-references/`. H1 is the facts review's M5 (same date), found independently. M2 confirmed: `experiments/overnight-2026-10-22/logs/` holds no driver log, and `julia-1.13/usr/lib/julia/sys.so` dates from 2026-10-21, so fa4e7f5798 (W-41, W-43) is committed, not built. What was done with each finding is recorded where it was done.
