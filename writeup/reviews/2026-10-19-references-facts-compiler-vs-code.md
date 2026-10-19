# Review: `reference/facts.md` and `reference/compiler.md` against the code (2026-10-19)

A fresh-eyes check of the two references against the patched Julia (`julia-1.13/`, branch `trait-world-1.13`, HEAD f13117cd74), TraitWorld (`strict.jl`, `hooks.jl`, `verify.jl`, `compiler.jl`) and the acceptance checks (`experiments/facts/acceptance_compiler.jl`). Method: every interface named in `compiler.md` was located by name in the diff `v1.13.2..HEAD`; every rule marked Implemented in `facts.md` was traced to the code that enforces it; every Deviations row was checked at its cited line. No Julia was run: findings marked "by reading" rest on the code as read, not on an experiment.

Severity follows the brief: **high** = an Implemented statement the code contradicts, a missing interface, a guarantee stated more broadly than code and tests support, a missing or wrong deviation; **medium** = imprecise semantics, a debatable status; **low** = names, wording, line numbers. Within a severity, findings are ordered by the damage they do to the thesis.

Counts: **4 high, 9 medium, 10 low.**

---

## High

### H1. `return_type` at run time in the product setting infers a facts method by facts, not plainly; the fold and the run-time route can answer differently

- **Document:** `writeup/reference/facts.md:320` ("Under the facts mode the answer is plain inference's, in the same world"), `:330` (rule 3: "Otherwise the answer is computed at run time, by plain inference"), `:116` (the A3 list of where answers can still differ); `writeup/reference/compiler.md:153` ("Otherwise it is a plain `NativeInterpreter`"), `:158-159` (Rules), `:740` (C-10: "two inferences of the same answer").
- **Code:** `julia-1.13/Compiler/src/facts.jl:259` (`return_type_interp(world) = facts_default() ? PlainRTInterp(world) : NativeInterpreter(world)`); `Compiler/src/typeinfer.jl:1802-1818` (`_return_type` → `typeinf_type`), `:1441-1445` (`typeinf_type` → `typeinf_ext`), `:1371-1374` (`typeinf_ext` leaves to `leaves_to`), `facts.jl:69-78` (`leaves_to`: from owner `nothing`, a facts method goes to `facts_interp`); the compile-time fold `facts.jl:355` (`typeinf_ext_toplevel(PlainRTInterp(world), mi, …)`), for which `leaves_to` returns `nothing` (`facts.jl:70`).
- **What the code does.** In the product setting the run-time route is a `NativeInterpreter` with owner `nothing`. Its `typeinf_ext` hands every facts method (a trait module's worker, an always-facts method) to facts inference. The compile-time fold, in both settings, uses `PlainRTInterp`, which is not a `NativeInterpreter` and infers the same method plainly. So `return_type(worker, T)` folded inside facts code answers plain inference; the same query at run time in the product setting answers facts inference, which can be wider wherever the worker's body has a run-time site (`Any` instead of a concrete type; `map(worker, [])` then allocates `Vector{Any}`). Under `all` both routes are `PlainRTInterp`.
- **Why it matters.** §7.1 is marked Implemented and states one answer; the code gives two, and the one plain code in the product setting sees at run time is not plain Julia's (stock Julia infers the worker plainly). C-10 describes the two routes as redundant work; they are not the same answer. `compiler.md` §1.4 ("Otherwise it is a plain `NativeInterpreter`") and §2.6 (`leaves_to` applies to `NativeInterpreter` with owner `nothing`) together imply this, but neither page says it, and `facts.md:339` ("Reflection shows the code that runs. For a facts method it is facts inference") pulls the other way.
- **Fix.** Decide which answer `return_type` of a facts method gives. Either (a) use `PlainRTInterp` in both settings (`facts.jl:259`), accepting C-10's second inference, which makes §7.1 true as written; or (b) define the product setting's answer as "plain inference in which facts methods are inferred by facts" (what every plain caller in that setting sees), and change the fold to match. Until the code matches the decision, add a deviation row (F-10, and C-11 under §1.4) naming `facts.jl:259` and `:355`, and add "a facts method's own result" to the A3 list at `facts.md:116`.

### H2. G2's evidence is not what the references cite: the load sequence counts no `:facts` code, the fuller script is stale, `acceptance_loads.jl` does not exist, and the numbering skips G1.16

- **Document:** `facts.md:122` ("The acceptance checks G1.1–G1.23"), `:152` ("G2.1 … and G1.17 … check it in a session … The load sequences of `experiments/factscompiler/control/` check it across packages"), `:127` (G2 "Status: Implemented"), `:536` (status index).
- **Code and tests:** `experiments/facts/acceptance_compiler.jl:70-469`: 23 checks named G1.1–G1.15, G2.1, G1.17–G1.23; there is no G1.16 (the brief's report is confirmed). `acceptance_compiler.jl:9` cites `acceptance_loads.jl` for G2; `experiments/facts/` holds no such file (verified by listing). `experiments/factscompiler/control/lost.jl:23` tallies only CodeInstances with `ci.owner === nothing`, for the roots `PlainTables`/`TraitMakie` or `CSV`/`DataFrames`/… (`lost.jl:10-11`); trait-module code is owner `:facts` in both settings (`src/gf.c:424` `jl_default_owner`), so the control's "lost 0" counts no trait-module code. The script that did count the facts owner across loads, `experiments/facts/g2all.jl:38` (`ci.owner isa TW.FactsOwner`, and `g2strict.jl`, which includes it), names `TraitWorld.FactsOwner`, which no longer exists (`grep FactsOwner TraitWorld/src` is empty; TraitWorld now uses `CC.FACTS_OWNER`, `TraitWorld/src/compiler.jl:16`). It cannot run.
- **Why it matters.** G2 is the design's central promise. Across package loads it is supported today only by a control that, by its own header, measures plain code under `all` (`lost.jl:1-3`), and by open-issues item 27's reading of that control. The in-session checks (G2.1, G1.17) are real but cover one extension and one later implementation.
- **Fix.** In §2.1 write "G1.1–G1.15, G1.17–G1.23 and G2.1 (23 checks; G1.16 retired)". In §2.2 cite exactly: G2.1 and G1.17 (session); `experiments/factscompiler/control/lost.jl` as a control for code of the default owner under `all` (say what it counts: CodeInstances of the listed roots with owner `nothing`, after nine loads), not as a G2 check of trait code; and either port `g2all.jl` to `ci.owner === :facts` and cite it as the cross-package check (with `g2strict.jl` for the strict tier), or state that no current check counts `:facts` code across loads. The stale header of `acceptance_compiler.jl:9` and `g2all.jl` need the code owner's attention (not changed here).

### H3. Package images compile machine code for `return_type`'s answer cache (and for other foreign owners), although both references say no code is ever generated from it

- **Document:** `compiler.md:155` ("No code is ever generated from it"), `:267` (owners table, `:facts_plain_return_type`: "Code generated from it: never"); `facts.md:329` ("That result lives under a cache owner of its own and is never used for code").
- **Code (by reading):** `julia-1.13/Compiler/src/precompile.jl:210-224` (`collect_foreign_cis!`: every CodeInstance with `owner !== nothing` and open `max_world` in the package's own methods) and `:225-244` (`add_foreign_codeinfos!`: skips only `FACTS_OWNER`; every other owner's CodeInstance with cached source is pushed to `codeinfos` for codegen), called at `:197-200`, also for the external list. A `PlainRTInterp` answer at a compileable signature keeps its source (`maybe_compress_codeinfo` keeps the tree for `isa_compileable_sig(mi)` even when discard is allowed), so its CodeInstances qualify. The same applies to TraitWorld's `_CheckOwner` results (`TraitWorld/src/compiler.jl:57`), which `compiler.jl:54-56` says "compiles nothing the program runs".
- **Why it matters.** Nothing dispatches to that code (`gf.c:3497-3511` filters by owner), so this is image size and build time, not correctness. But it is an Implemented statement the code contradicts, and it undercuts the stated reason the answer cache is separate.
- **Fix.** Either exclude `:facts_plain_return_type` (and, by a predicate, owners that declare "never run") in `add_foreign_codeinfos!`, or add C-11: "the image builder emits machine code for every foreign owner's CodeInstance of the package's own methods whose source is cached, the `return_type` answers and TraitWorld's check results included; nothing calls it" with `precompile.jl:225-244`.

### H4. "A form not listed is a run-time site" is not what inference does: `invoke` at a declared signature and `hasmethod` record edges at non-fact signatures

- **Document:** `facts.md:174` ("A form not listed is a run-time site, until it is shown to meet the criterion and added"), `:186-190` (the "not fact signatures" list), `:210-211` (§4.2 "No edge is recorded"); `compiler.md:118` ("a call whose signature … is not a fact gets no method matches"), `:149` ("or a call edge at the method's own signature").
- **Code:** `julia-1.13/Compiler/src/abstractinterpretation.jl:2369` (`abstract_invoke`: `findsup(lookupsig, …)` with no facts gate; `invoke(f, Tuple{AbstractArray}, x)` is inferred, with an invoke edge at the declared signature, in facts code too); `Compiler/src/tfuncs.jl:3269-3280` (`hasmethod`'s tfunc: `findsup`, `InvokeCallInfo`, no gate); only `find_method_matches` is gated (`abstractinterpretation.jl:369`). Invalidation of such edges: `src/gf.c:2470-2475` (an invoke edge at `m.sig` is never invalidated by a new method, only by replacing `m`; a narrower declared type only when a new method replaces the resolution of that type as a whole). `facts.jl:329` (`rests_on_facts` accepts `e == m.sig`) relies on exactly this.
- **Why it matters.** The edges are sound by the criterion: only the function's owner, the declared types' owners or a pirate can change what `invoke` resolves to. So G1 and G2 are not hurt. But the reference's closed list is wrong, and the reader of §4.2 ("No edge is recorded") cannot know that `invoke` in facts code is inferred as in plain Julia, nor why `rests_on_facts` accepts a non-concrete edge.
- **Fix.** Add a sixth form to `facts.md` §3 and `compiler.md` §1.2: "an `invoke` at a declared signature (and `hasmethod` at one): dispatch of the declared signature as a whole; Julia invalidates it only when its resolution changes (`gf.c:2470`)". Say in §4.2 that `invoke` is not a run-time site. Rename the clause at `compiler.md:149` "an invoke edge at the method's own signature".

---

## Medium

### M1. The split limit and "an edge per split" are stated more tightly than the code

- **Document:** `facts.md:179` ("Its union splits, at most four"), `:180` ("at most four splits in all"), `:184`; `:201-202` ("The caller records the fact as an edge, one per split").
- **Code:** `facts.jl:208-221` (`facts_find_method_matches`): top-level unions are split by Julia's `max_union_splitting` (four by default), each split then tested by `is_fact_sig`; `facts.jl:153-165` (`fact_splits_ok`): tuple-element unions are bounded by `MAX_FACT_SPLITS` *per top-level split*. A call may therefore stand for up to 16 concrete signatures. For a tuple-element union the code records one edge at the non-concrete tuple signature (`facts.jl:220`, `find_simple_method_matches(interp, atype, …)`), not one per split; only `return_type`'s `concrete_splits` (`facts.jl:262-284`) enumerates them. `compiler.md:98-102` is accurate on the first point.
- **Fix.** In §3 say the two limits compose; in §4.1 say "one edge per top-level split; a tuple-element union is one edge at the tuple signature (Julia's intersection check makes it exact)".

### M2. The closure-at-kinds form rests on an unstated assumption, not on Lemma O

- **Document:** `facts.md:181` ("Only the closure's own module adds methods to a closure's type").
- **Code:** `facts.jl:124-125`, `:192-203` (`is_closure_type`: the type's singleton name begins with `#`; `kinds_ok`). `TraitWorld/src/strict.jl:103-104` (`_would_win` needs `s <: m.sig`) and `:117-118` (a closure's call at kinds is not split): the strict check before a definition cannot see a method at `Type{X}` winning at the fact `Tuple{typeof(clo), DataType}`; the safety net (`strict.jl:197`) would.
- **What is unstated.** By §1's definitions, the owner of a type `X` who defines `(::typeof(clo))(::Type{X})` is a stakeholder of its own method and no pirate, yet it changes dispatch at the recorded fact `Tuple{typeof(clo), DataType}`. Julia invalidates the edge (the intersection is non-empty), so G1 holds; G2 for this form rests on the practice that nobody names a closure's type, not on the criterion. The `#` test also admits lowering-generated functions (`#f#N` keyword bodies), which is fine for the same practical reason.
- **Fix.** State the assumption in the row ("assumption: no other module defines methods on a generated function type; the test is the `#` prefix") and link it from §2.2's exceptions; or restrict the form to `Type{T}`-free kinds where the fact cannot be refined.

### M3. The statement-level rule for asserted effects does not achieve what §8 says it achieves

- **Document:** `facts.md:350-354` ("no asserted effect applies. This covers both levels … a statement's"; "Why: … The fold would rest on a dispatch that no edge records"); `compiler.md:169-171` ("a statement's `@assume_effects` is ignored once the frame has a run-time site").
- **Code:** `abstractinterpretation.jl:3644-3647` (`merge_override_effects!` skips the override only when `sv.facts_rtsite` is already set, so a statement before the frame's first run-time site keeps it; and the test is on *this* frame); `typeinfer.jl:376-377` (the method-level rule, which is right). A statement `Base.@assume_effects :foldable g(y)` at a fact signature, where `g`'s own frame holds the run-time site, overrides `g`'s non-foldable effects in the caller's frame; a caller of that frame may then fold it, over a dispatch no edge records. The order-dependence is harmless for the frame's effects (the later run-time site taints them anyway) but the ssaflags of the earlier statement keep the override.
- **Fix.** Either drop a statement override whose callee frame had a run-time site (the callee's CodeInstance can carry the flag), or state the limit: in `facts.md` §8 as "a statement's assertion is dropped once the frame has met a run-time site; an assertion over a call whose callee holds the run-time site still applies" with a deviation row, and in `compiler.md` §1.5.

### M4. The `Dynamic` split's result type: inference types the statement `Any`; the declared type enters by the inliner's join and by the lowering's assertion; C-8 misses a case

- **Document:** `facts.md:379` ("the join is typed `RT`"), `:217`; `compiler.md:548`; C-8 (`compiler.md:738`).
- **Code:** `facts.jl:465-467` (open case: `CallMeta(Any, Any, …)`); `Compiler/src/ssair/inlining.jl` (`ir_inline_unionsplit!`: asserts cases and the fallback to `fallback_rt`, join typed `tmeet(typ, fallback_rt)`; `handle_call!`: `fallback_rt` only when `info.open && info.rt !== Any`; `process_simple!`: the statement is always rewritten to `f(x, args...)`); `TraitWorld/src/trait.jl:314` (the lowering writes `…::$retx` after the call). When no `UnionSplit` is built (the union of candidates plus other arguments' unions exceeds `max_union_splitting`, no candidate admitted by `x`'s type, inlining off), the rewritten call carries no assertion. The frame's inferred types after the call are `Any` in every case; only the lowering's `::RT` narrows them.
- **Fix.** In §9 and §4.2: "inference types the call `Any`; the lowering asserts the declared type after it; the optimizer's split asserts each case and the fallback". Extend C-8 with the no-split case.

### M5. G2's one-sentence statement is broader than the code; the exceptions list carries the truth

- **Document:** `facts.md:129` ("is invalidated only by a definition that changes dispatch at one of its facts, or by a redefinition of a binding it reads"), against `:146` (direct calls into the compiler hold edges to plain code) and `:222` (§4.3: "or a CodeInstance it has an edge to is invalidated"); F-2 (`:567`).
- **Code:** `typeinfer.jl:1050-1052` and `facts.jl:97-102` (`facts_edge`: a facts frame names the plain compiler CodeInstance, whose edges are plain Julia's); under `all`, `facts.jl:60-62` and `typeinfer.jl:1657` (plain results for compiler callees share owner `nothing` with facts-mode results; a facts-mode request can find a plain result with non-fact edges).
- **Fix.** Add to the statement: "or by invalidation of a CodeInstance of the other mode that it names (§6.3, §6.4; under `all`, F-2)". The Scope bullet "plain code that code compiled by facts runs" should say the facts CodeInstance itself is recompiled then.

### M6. The fold's condition "rests on facts only" omits what the code accepts, and C-9 has no F- counterpart

- **Document:** `facts.md:327`; `compiler.md:149`, C-9 (`:739`).
- **Code:** `facts.jl:305-338` (`rests_on_facts`): accepts `Core.Binding` edges and `(m.sig, ci)` invoke edges (see H4), rejects `Int` groups, method-table edges and bare `MethodInstance` edges; gives up at 2000 CodeInstances. `facts.md` §7.1 is Implemented without the limit; its Deviations have no row for it.
- **Fix.** Add "(or an invoke edge at the method's own signature)" at `:327`; add F-10 pointing to C-9, since a `facts.md` rule is the one deviated from.

### M7. F-2 and C-2 describe the same gap and do not agree

- **Document:** `facts.md:567` (F-2 names both directions: a Base method the compiler calls can reuse a facts result, and facts code can reuse a plain result "whose edges are not all facts. Not checked"); `compiler.md:732` (C-2 names only the first).
- **Fix.** Add the reverse direction to C-2; it is the one that touches G2 under `all` (`facts.md:492` already excepts it).

### M8. The product-setting rule for which interpreters see facts inference is split across the two pages and contradicts §7.2's list

- **Document:** `facts.md:340` ("`code_typed`, `infer_return_type`, `verify_main` and TraitWorld's first-call check all see that code"); `compiler.md:377-378` (Rules: `leaves_to` only from owner `nothing`; "TraitWorld's checking interpreter … infer facts methods by their own rules").
- **Code:** `TraitWorld/src/compiler.jl:57` (`_check_interp`: owner `_CheckOwner()`, `facts = false`) and `:66-69` (`_check_kw_at`: the checks' own cache for archetype signatures, a plain `NativeInterpreter` with owner `nothing` otherwise); `facts.jl:73` (an interpreter with an owner of its own infers by its own rules). The definition checks (archetypes) infer workers plainly; only the real-type path sees facts inference.
- **Fix.** Qualify `facts.md:340`: "TraitWorld's first-call check at a real type"; say that the definition checks infer workers plainly in their own cache, by design.

### M9. The `all` test bed's G2 claim for other packages' code: "untested" understates F-4

- **Document:** `facts.md:492` ("Strict mode under `all` is untested"), `:418`; F-4 (`:569`).
- **Code:** `TraitWorld/src/strict.jl:87-92` (`_trait_world_code`: owner `:facts`, or owner `nothing` in Base/Core/stdlib/TraitWorld/a trait module, `trait_module.jl:37-47`). Under `all`, a package's code compiled by facts under owner `nothing` is outside strict mode's protection, so the strict tier's G2 does not hold for it; `g2strict.jl` is stale (H2).
- **Fix.** "Strict mode under `all` protects only the code F-4 names; untested."

---

## Low

### L1. Line numbers off by one in four rows
- F-1 (`facts.md:566`): `typeinfer.jl:1653` → `:1654`. C-2 (`compiler.md:732`): `typeinfer.jl:1658` → `:1657`. C-3 (`:733`): `gf.c:4610` → `:4611`. C-4 (`:734`): `gf.c:3732` → `:3733`. All other citations checked resolve (`facts.jl:47, 52, 60, 69, 85, 87, 105, 259, 305, 355, 465`; `gf.c:424, 3775, 3782, 4802, 4810`; `module.c:749`; `julia.h:2330`; `runtime_ccall.cpp:424`; `strict.jl:87, 123, 158, 197`; `hooks.jl:230`; `verify.jl:353, 839`; `trait_module.jl:38`; `test/verify_dynamic.jl:41`; F-7's `facts.jl:8` is the sentence at `:8-9`).

### L2. F-1's sentence about compile queues is stale after f13117cd74
- `facts.md:566` ("a queue that does not [apply `interp_for_mi`] compiles the compiler by facts under `all`"). The same commit added `facts.jl:74` (`leaves_to` leaves a plain method to plain inference from the default owner too), which `typeinf_ext` applies to every request (`typeinfer.jl:1371-1374`); the JIT queue (`add_codeinsts_to_jit!`, `typeinfer.jl:1612-1620`, `interp_for_owner` only) is covered by it. The residual difference is the two predicates (`is_compiler_code` vs `jl_method_is_plain`), which the row already names. Drop the sentence.

### L3. The process switch's values and side effect
- `compiler.md:76` ("any value but `0`: on"): `gf.c:1115-1116` treats an empty value as unset. `facts.jl:20` sets `FACTS_IMAGE[] = true` on the first call whenever the variable is `1`; that is how "an image built with the switch on keeps it on" (`compiler.md:78`) works. Say so.

### L4. "Concrete member" admits `Type{T}`
- `compiler.md:99` ("a concrete type that is not a kind"); `facts.jl:151` (`isdispatchelem(p) && !iskindtype(p)`: a dispatch element, so `Type{T}` with `T` known too). Same at `facts.md:182`.

### L5. Package images: machine code for other packages' methods needs keep-compiled
- `facts.md:453` ("With machine code"); `src/staticdata_utils.c:554-565` (only with `jl_image_keep_compiled`), which TraitWorld switches on only while generating an image and unless `JULIA_TW_KEEP_COMPILED=0` (`TraitWorld/src/TraitWorld.jl:73-76`). Add "(with keep-compiled, `compiler.md` §2.9)".

### L6. An Open item without an open-issues entry
- `compiler.md:347` says the `jl_apply` question has "no entry in `open-issues.md` yet"; `facts.md:231` and `:532` mark it Open with F-3. The README's convention is that Open links the question. Add the entry or say "recorded in F-3 only".

### L7. "Fact" is used for two things on `compiler.md`'s first page
- `compiler.md:10` ("a *fact* is a call signature that only its stakeholders or a pirate can change") against `facts.md:66` (a fact is a dispatch result at a concrete signature) and `:73` (a fact signature). Use "fact signature" at `compiler.md:10`.

### L8. The invoke-style edge named as "a call edge"
- `compiler.md:149`; see H4. Also `facts.md:117`: `return_type(pass, Tuple{Type{Int}})` example is fine.

### L9. §2.5's Open list and F-3 agree; the `@cfunction` entry could name the rule
- `compiler.md:344`, `:477` and `facts.md:568` agree that `:caller_world` pointers run the default owner's code. `facts.md:237` lists `@cfunction` pointers among the ways "this holds" under a Meaning paragraph; the status line and F-3 qualify it. Move the sentence under "intended" wording or cite F-3 inline.

### L10. The acceptance file's header
- `experiments/facts/acceptance_compiler.jl:9` cites `acceptance_loads.jl` (see H2). A code comment; noted for the owner.

---

## The guarantees, as the checks define them (brief 3)

- **G1** (`facts.md:95-122`). The checks G1.1–G1.15 and G1.17–G1.23 cover what §2.1 lists (redefinitions by owners, a winning pirate, calls into Base/LinearAlgebra/Printf, `return_type` after redefinitions, folds over run-time sites, `Dynamic` values of later implementations, older worlds, the two cache changes). Stated within what they support, with these caveats: the A3 list should include H1's case; M3's statement-level hole is untested; the closure form (M2) is untested for the `Type{X}` case. "Threads are untested" is stated.
- **G2** (`facts.md:127-152`). In a session: G2.1 and G1.17 (both in the file). Across loads: no current check counts `:facts` code (H2). The statement should name transitive edges (M5). The two-tier table (`:159-162`) is consistent with F-4 once M9's wording is fixed.

## Consistency between the two pages (brief 5)

- `facts.md` §7.1 rule 3 cannot be provided by `compiler.md`'s interfaces as they are: `return_type_interp` in the product setting is the interpreter §2.6 says leaves facts methods to facts inference (H1).
- `facts.md` §3's closed list of forms vs `compiler.md`'s ungated `abstract_invoke` (H4).
- `facts.md` §8's "both levels" vs `compiler.md` §1.5's "once" (M3).
- `facts.md` §9's "join typed `RT`" vs `compiler.md` §4.2 and C-8 (M4).
- F-2 vs C-2 (M7); F-1 vs C-1 agree on the predicates (both name the module walk and the flag) and both carry the fixed queue history; the "Where" lists agree.
- `facts.md` §6.2's table and `compiler.md` §2.3's table agree with each other and with `leaves_to`, `typeinf_ext_toplevel`, `jl_default_owner` and `facts_callee_owner`.

## Verified as stated (not findings)

Every interface in `compiler.md` exists with the stated name, signature and location: `NativeInterpreter(world; inf_params, opt_params, facts, owner)`, `cache_owner`, `facts_mode`, `facts_default` (`types.jl:391-423`, `facts.jl:17-23`); `is_fact_sig`, `MAX_FACT_SPLITS`; `FACTS_ABSTRACT_SITE`, `InferenceState.facts_rtsite`; `PlainRTInterp`, `return_type_interp`, `facts_plain_return_type`, `PlainRTInfo`; `adjust_effects(ipo_effects, def, frame)`, `merge_override_effects!`; `@compiler_options facts=true|false|:yes|:no` (`experimental.jl:204-208`), the module flag and its inheritance (`module.c:524, 729-750`), `Method.facts` and the meta, merged metas and the lowering carry (`method.c:1005-1016`, `ast.scm:538-545`, `julia-syntax.scm:562, 583`), `jl_method_is_facts` (0 under `--trim`), `jl_method_is_plain`; the three owners; `jl_default_owner`, `jl_type_infer`, `typeinf_ext_toplevel` (5 and 4 arguments), `typeinf_ext`, `interp_for_owner`, `interp_for_mi`, `default_owner`; `jl_apply_generic_facts`, `jl_invoke_facts` and the codegen sites for direct calls, `invoke`, `_apply_iterate`/`_apply`, `invokelatest`/`invoke_in_world` (`codegen.cpp:4297-4325`, emitted inline, not through the builtin), `:invoke_modify`; the Open list for `jl_apply` (`julia.h:2330`); `leaves_to`, `facts_edge`, `is_facts_method`, `is_plain_method`; no constant propagation across modes (`abstractinterpretation.jl:896`); cross-owner inlining in both `resolve_todo`, `handle_invoke_expr!` for a foreign `:invoke`, `add_inlining_edge!` comparing owners; owner-aware bare edges with the `:uninferred` exception (`gf.c:2367-2374`); `jl_set_image_keep_compiled`, `queue_external_cis` (both branches), the `:facts` copies without source; `--trim` writing flags 0 and 1 (`staticdata.c:1227, 1729`); `:caller_world` (`codegen.cpp` flags `|2`, the five-word entry, the world test; `runtime_ccall.cpp:374-465`), `jl_get_specialization1_worlds`, partial coverage dispatches dynamically, a thread without a world uses the latest; `call_cache_any_ok`, `sig_match_any`, `call_cache_exact` with the type-argument exclusion and the cap; `known_type` folded in `abstract_call_known` with total effects; `dynamic_call`, `register_dynamic_candidate!` (copy-on-write, lock-free readers), `dynamic_candidates` (first four), `DynamicSplitInfo`, the inliner's open split; both hooks with their guards (not during a system image build; not for a hook's own definitions; the image hook warns and activates all on error; external methods only); the intrinsics' tfuncs and effects (`tfuncs.jl:759-766, 3076, 3094, 3117`); type printers (`invokelatest`, copy-on-write); `only_vararg_widened`; `cycle_results`; the bootstrap entry; reflection in the compiler's world for a `NativeInterpreter` when no reflection compiler is set; the dispatch profiler. Deviations C-1, C-3 to C-9, F-3 to F-9 are real and correct at their lines (modulo L1). TraitWorld's `@machinery`, entries, `conformance` methods and ahead-compiled entries carry the metas the references say (`compiler.jl:43`, `trait_module.jl:709`, `implement.jl:675`, `ahead.jl:182`); strict mode's rules 1–3, its two walks and its safety net match F-4/F-5; the image hook runs `_strict_image_refusals` (`hooks.jl:246`) and reports at load.
