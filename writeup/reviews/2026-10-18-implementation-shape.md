# Review: the implementation's shape after the pivot

2026-10-18. A critical review of the implementation of the trait-bound Julia design: TraitWorld (main 47e4274), the Julia patch (`julia-1.13`, branch `trait-world-1.13`, db82407fa6 plus uncommitted work), `experiments/factscompiler`, the forks (`forks/`, 06e8b97) and the demonstrators, read against `writeup/notes/1–4`, `decisions.md`, `open-issues.md`, `explorations/dataframes-port-lessons.md`, `explorations/julia-support.md` and `plans/2026-10-17-policy-in-compiler-plan.md`.

The question asked: is this fit for its purpose, validating the future shape of the design now that Julia's compiler may be modified, and where did "keep it a package" bend the implementation, the measurements or the design?

**Marks.** *Verified* means checked in the sources, by `git`/`grep`/`nm`, or by one run of the patched build. *Reasoning* means my judgement from what was verified. Line counts are `wc -l` and `git numstat`; attributions of lines to mechanisms are by the line ranges of the definitions in each file and are approximate (±10%).

---

## 0. Summary verdict

1. **The pivot is right, and it is further along in words than in code.** The facts mode as a mode of Julia's own compiler is 269 lines plus 10 hook lines (`experiments/factscompiler/Compiler/src/facts.jl`; *Verified*). The same rules as a package cost about 850 lines in `TraitWorld/src/facts.jl`, plus view caches (348), compiler warm-ups, a system-image prototype, and four patch pieces that exist only because the owner is foreign (5, 9, 10, 12). The in-tree port (plan stage 2) is **not built**: `julia-1.13/Compiler/src/facts.jl` calls `ccall(:jl_compile_by_facts, Cint, ())`, and that symbol exists in no C file and not in the built `libjulia-internal.so`; the built binary and `sys.so` predate the file (*Verified*: `grep -rn jl_compile_by_facts julia-1.13/src` finds nothing; `nm -D` finds nothing; `julia-1.13/julia -e 'isdefined(Base.Compiler, :facts_mode)'` prints `false`; `cglobal(:jl_compile_by_facts)` throws "undefined symbol"). There are now **three copies of the fact rules** (TraitWorld, the Compiler copy, the in-tree file), already diverging in their helpers.
2. **The largest distortion is attribution, not code.** The headline property every demonstrator measures, "compiled code survives unrelated loads in every order", is a property of the facts policy, and the policy is trait-independent: plain CSV code reached from a worker was protected exactly as trait code was (lesson 1.1: 661 policy CodeInstances of CSV, none lost to `using DataFrames`; *Verified* in `dataframes-port-lessons.md` §1.1). Under the planned `--compile-by-facts=all`, the plain baselines (PlainODE, PlainPlots, PlainTables, upstream DataFrames) acquire the same protection. The fresh-eye review's B2 control was never run; after the pivot it is no longer optional, it is the experiment that tells what traits add.
3. **The forks validate a function barrier, not a trait.** DataFrames' `ColumnKernels` never calls the `Column` trait's operations `cell` or `nrows` (0 uses); every kernel calls `vector(c)` and runs upstream's code on the concrete vector (7 uses; *Verified* by `grep` on `forks/DataFrames/src/other/kernels.jl`). That is a per-column function barrier compiled under the policy. Plain Julia permits the same barrier; what the trait adds there is the policy's protection (now the compiler's) and a dispatch that each kernel immediately undoes.
4. **`Dynamic` is the mechanism with the clearest case for moving into the compiler**, and the project's own README says so. Its package form is a generated function reading a lock-protected global registry through a `Base.@assume_effects :foldable` function that is not consistent (`core.jl:449–463`; *Verified*), cfunction witness tables keyed by a per-process session token, and a `sealed_call` exemption in the compiler copy for TraitWorld's own machinery, a notion the user has asked to leave the project (open-issues §2.26). The remaining cost after all of that is 2× plain Julia's `isa` branches in the raytrace (498–505 ms against 249 ms; `experiments/factscompiler/README.md`).
5. **What is sound and should be kept:** the trait language as macros (`@trait`, `@implement`, `@trait_module`), ownership (rule 3), definition checking at archetypes, concrete mode, `verify_main`, `Like`/`Self` results, `Callable`/`Erased`, the reference layout with field-offset intrinsics, type printers, strict mode behind the definition hook, and the acceptance suite. About 5,500 of TraitWorld's 8,707 lines are this, and none of it needs to move into the compiler to validate the design.
6. **Recommendation in one line:** finish (A) in-tree, run the plain baselines under it, then build the smallest (B)+(C) as a *method-level* mode and delete the package's imitation of them; move `Dynamic`'s call-site split into the inliner; stop the forks at M5 until the baselines-under-facts number exists; retire view caches, the system-image prototype, pieces 2 and 4, and the legacy spellings.

---

## 1. The state of the tree (Verified)

| Part | Size | Notes |
|---|---|---|
| `TraitWorld/src` | 8,707 lines, 16 files | 7,157 lines at b60b126 (after wrappers, sealing, filter, doors, layering were removed, session 25); +1,550 since, in about a day: `facts.jl` 447→854, `core.jl` 631→888 (witness tables, key branches), `strict.jl` 261 and `frames.jl` 78 new, `hooks.jl` 183→267, `implement.jl` 1,174→1,319 |
| Julia patch, committed | 954 insertions, 13 deletions, 16 files, 16 commits over v1.13.2 | per piece below; about 580 lines (61%) are pieces 2 and 4, already marked "revert" in the plan |
| Julia patch, uncommitted | `Compiler/src/facts.jl` 269 lines (untracked), 10 lines in `Compiler.jl`, `abstractinterpretation.jl`, `tfuncs.jl` | references `jl_compile_by_facts`, which does not exist; not built; the built `sys.so` is from 2026-10-17 09:34, the file from 2026-10-18 10:24 |
| `experiments/factscompiler/Compiler` | a copy of `julia-1.13/Compiler` + `facts.jl` (269) + the same 10 hook lines + 1 line in `bootstrap.jl` | the only running form of (A); bootstrap 23 s per session; measured with `--pkgimages=no` |
| `forks/` (one git repository) | DataFrames src +≈380 lines (kernels 178, utils 97, dataframe 49, abstractdataframe 37, sort 26, join 8, show 8), CSV +≈200 (api 73, core 24, ColumnParsers 35, two extensions 60, CSV.jl 13), Tables +42 | M0–M4 done, M5 in progress; upstream suites green at M1 only (the fork's suites not re-run since the storage change, as far as the README says) |
| Demonstrators | TDE 691 lines, TraitMakie 395, TraitTables 210, TraitCSV 171, TraitReport 125 | READMEs describe scopes that do not exist in the tree (fresh-eye S6; still true) |
| Patched build contents | pieces 1, 3, 5, 17 present (`jl_set_method_definition_hook`, `getfield_at_offset`, `jl_set_image_keep_compiled`, `register_type_printer`); no facts mode | one run: `flock … nice -n 19 julia-1.13/julia -e …` |

---

## 2. Inventory: mechanisms, sizes, what they implement, why they exist

Classes: **(a)** the design needs it; **(b)** it imitates what the compiler or runtime should do; **(c)** it works around being a package on stock Julia; **(d)** left over from an abandoned design. Line counts are approximate by definition ranges.

### 2.1 TraitWorld

| Mechanism | Where | ≈Lines | Design element | Class | Under the compiler-mode design |
|---|---|---|---|---|---|
| Fact rules: `FactsInterp`, `_fact_sig`, `_fact_splits`, `_tuple_splits`, closure kinds, `concrete_eval_eligible`, `_has_runtime_sites`, `return_type_tfunc`, `_concrete_deps`, `_native_return_type`, `find_method_matches` | `facts.jl:1–407` | 407 | rule 1 (concrete facts), rule P, A3 | (b) | **delete**: it is `experiments/factscompiler/…/facts.jl` (269 lines) |
| Second owner and owner-aware dispatch imitated: `_owner_invokes!`, `_policy_sites!`, `_call_under_policy`, `_policy_ci`, `_CallSite`/`_site_miss`/`_call_site` (arities 0–4), `_NO_POLICY`, `_keep_method`, `_typeinf_policy`, `_compile_pending!` (depth/count bounds), `_owner_ci`, `_invoke_under_policy`, `CompilerPlugins.typeinf` methods | `facts.jl:409–692` | 284 | parts (B) and (C) of the plan | (b)/(c) | **delete** with (B)+(C) in the runtime (§4) |
| The entry's call of a worker as a generated function: `_FactsCallGen`, `_facts_call`, re-entry guard, depth 8, `compilerbarrier(:const)` for asserted effects (G1.10), `_close_policy!` | `facts.jl:694–828` | 135 | "compile this call under owner X" (piece 11) | (c) | **delete**: an ordinary `:invoke` of a facts-marked method |
| `_latest_under_policy`, `_in_world_under_policy`, decision world, `_COMPILER_WORLD` | `facts.jl:373–377, 829–854`; 29 call sites across 10 files | 35 + call sites | the machinery's own code protected from loads; piece 12 | (c) | **delete**: `invokelatest` |
| Compiler warm-ups and the `_PC` precompile module (old `{R}` spelling, `project(t) = t.v`) | `TraitWorld.jl:94–158, 184–219` | ≈120 | none | (c)+(d) | delete the warm-ups; rewrite `_PC` in the current spelling |
| Reference layout: `Slot`, `Key`, `View`, `_rep`, `_loadfield`/`_storefield` with intrinsics | `core.jl:49–175` | 125 | keys, "every access reads the user's object" | (a) | keep |
| `llvmcall` loads/stores with hand-written TBAA | `core.jl:105–134` | 30 | fallback for piece 3 on stock | (c) | delete once stock is dropped (decision P-b) |
| `TObj`, `PTag` encoding/decoding of trait sets, `_traitset`, `_carries_static` | `core.jl:176–298` | 123 | a worker's signature without free static parameters | (c) | keep as the package's encoding until traits are types (piece 7, last) |
| Witness tables (`_Witness`, `_wit_table` under `_LOCK`, `_WitOp`, `_wptr` cfunctions, session token) | `core.jl:300–375` | 75 | `Dynamic` operations as one indirect call | (b) | defer; the inliner split first (§4) |
| `Dynamic{X}` (boxed `TObj` + table), `_narrow`, key branches (`_dyn_call`, `_dyn_keys_now` asserted foldable, `_DECL_KEYS`, `_note_conformances!` inferring in a check owner, `_dyn_call_keyed` generated, `_dyn_hop` arities) | `core.jl:376–559` | 185 | dynamic values | (a)+(b) | keep `Dynamic{X}` as a type; **move the split into the inliner**; hold the user's object, not a boxed `TObj` (§4) |
| Printing by bound and key, type printers | `core.jl:561–635` | 75 | pay-off 4 | (a) | keep (piece 17) |
| Declared fields as properties, `fieldget`/`fieldset!` | `core.jl:637–692` | 56 | fields | (a) | keep |
| Witnesses `Impl`/`Generic`/`Dyn`, 22 registries declared `@max_methods 1` with sentinel fallbacks, `opcall`/`_dispatch` | `core.jl:694–799` (+3 in `entry.jl`, 3 in `implement.jl`) | 106 | operations, defaults | (a)+(c) | keep; the `@max_methods 1` pattern is the package's way to add a conformance without invalidating entries |
| `Callable`: `Erased` (FunctionWrappers technique), `CObj`, `CMulti`, `enter_callable`, `DynamicFn` | `core.jl:800–888`, `entry.jl:515–614` | 200 | functions from above | (a) | keep |
| Conformance as methods: `conformance(As{X}(), u)` with `@max_methods 1`, `_conformance_slow` cached per world, family registries | `entry.jl:71–161`, `implement.jl:586–680` | ≈190 | membership; "a new conformance invalidates no entry" | (c) | keep until piece 7; it is the right runtime representation for a package |
| Entries at `Any`: `EntryPos`, `needed`, `enter`, `keeps`, `_assemble`/`_merge`, `traits_at`, `fallback`/`kwfallback`/`_plain_method` (reflection over `methods(f)` for the "types first, then traits" rule), `Untyped` tag | `entry.jl:162–513` | 350 | rule 2 (the boundary), dispatch tier | (c) | keep until piece 7; the dispatch-tier imitation (`_plain_method`) is the weakest part |
| Builder/`VSpec`/`_parts`, `_builder_for`, `_key_and_slots`, `_no_implementing_type` | `entry.jl:1–70, 402–458` | 130 | keys | (a) | keep |
| Results like the input (`LikeResult`, `_invert`, `_rebuild`, `_dyn_like`) | `entry.jl:629–731` | 103 | `Like{t}`, `Self` | (a) | keep |
| `conforms(T, X)` | `entry.jl:733–751` | 19 | membership as subtyping, stand-in | (c) | keep; **used by no demonstrator or fork** (`grep conforms(` finds none) |
| `@implement`: forms, checks, `ProjRec`/`projection`/`proj_lookup`/`_implement_projection` (forwarding under the old name), `_declared_defaults`, `check_overrides`, families | `implement.jl` | 1,319 | conformance, forwarding, generic implementations | (a) with (d) naming | keep; rename `projection` → forwarding; drop `project(t) = …` |
| `@trait` | `trait.jl` | 339 | traits | (a) | keep |
| `@trait_module`: `_process`, `_dynamic_fields`/`_dynamic_containers` (a trait's name means `Dynamic` inside the module only), `_classify`, `_rewrite_fdef` (entry + worker per method), `_finish_module`, ambiguity and bound checks | `trait_module.jl` | 839 (of which `_rewrite_fdef` 228) | syntax (piece 8), rule 3, ambiguity | (a)+(c) | keep as the package's syntax |
| Rule-2 checks on typed code: `worker_problems`, `_keeps_dynamic` | `checks.jl:1–239` | 240 | "code must not depend on the user's type" | (a) | keep |
| `checked_call`/`checked_kwcall` generated with a per-signature flag and `_check_once` at first call | `checks.jl:240–325` | 85 | checks at compile time (old piece 5) | (c) | keep for now; becomes a compile-time check when checks run in the compiler (piece 7) |
| Definition checking at archetypes, keep analysis | `defcheck.jl` | 305 | "checked once where defined" | (a) | keep |
| Concrete mode (tracer, root causes) | `concrete.jl` | 564 | pay-off 3 | (a) | keep |
| `verify_main` (IR walker, holes, targets, closed world) | `verify.jl` | 1,079 | pay-off 2 (AOT) | (a) | keep; it cannot see through the policy's `invoke`s today (open-issues §3), which (B) as an ordinary `:invoke` fixes |
| Ownership (rule 3): extensions, stakeholders, `owned_method`, `_sig_alternatives` | `ownership.jl` | 269 | rule 3 | (a) | keep |
| Definition hooks: override index, image hook, strict-mode calls | `hooks.jl` | 267 | overrides refused at definition; strict mode | (a) on the patched build | keep (piece 1) |
| Strict mode | `strict.jl` | 261 | option | (a) | keep; needs piece 14 for the exact check |
| View caches (`TWView_<hash>` packages under `~/.julia/traitworld/views`, detached niced builds, exit hook) | `viewcache.jl` | 348 | rule 4 "where code lives" for combinations no package owns | (c)+(d) (ComboCache under another name; fresh-eye S2) | **delete**; see §4 |
| Frame hiding, `MethodError` hints | `frames.jl` | 78 | readable errors | (c) | keep until a Julia registry of hidden frames exists |
| 13 `JULIA_TW_*` switches (`RUNTIME_SITES=native`, `WITNESS=0`, `FACTS_POLICY`, `NOINLINE`, `KEEP_COMPILED`, `HOOKS`, `VIEWCACHE`, …) | all files | — | diagnosis and dead alternatives | (d) | delete all but `FACTS_DEBUG`, `STRICT`, `ALL_FRAMES` |

**Totals (approximate):** (a) ≈ 5,500 lines; (b) ≈ 770; (c) ≈ 2,200; (d) ≈ 250 (mostly inside (c) files). The (b)+(c) share that exists *because the owner is foreign* (facts.jl beyond the rules, the generator, `_latest_under_policy`, warm-ups, view caches, `_COMPILER_WORLD`) is ≈ 1,300 lines; the compiler version of the same is ≈ 280 lines plus (B)+(C), which I estimate at 300–400 lines of Julia and C (§4).

### 2.2 The Julia patch (`git -C julia-1.13 log --numstat v1.13.2..HEAD`; Verified)

| Piece | Commits | Lines | Class | Verdict (plan §5 agrees unless noted) |
|---|---|---|---|---|
| 2 invalidation filter, insertion half (`gf.c`) and load half (`Compiler/src/reinfer.jl`), fixes, hook form | 4d8eeebc19, fc29488177, 28d71bf9cb, f1cf1efa1c, b058af111e, 280612ed2f, fac46840b8 | ≈520 | (d) | revert; opt-in today (`JULIA_TW_FILTER`) |
| 4 post-inference hook, default load policy | 87dcf22015 | ≈61 | (d) | revert |
| 1 method-definition hooks (before/after, image methods) | dda21fe511 | ≈112 | (a) | keep: strict mode, overrides at definition |
| 3 field-offset intrinsics with alias metadata and write barrier | 3133c31c5f | ≈126 | (a)/(b) | keep; upstream-worthy on its own |
| 5 package images keep machine code for upstream and foreign CodeInstances | 9af2f27786 | 62 | (c) foreign half; (b) upstream half | the upstream half is what makes a conformer's image hold workers for upstream keys and what made PlainReport 2× faster; keep it, measure it alone; the foreign half goes with (B) in-tree |
| 9 owner-aware bare MethodInstance edges | 5b5b98758f | 12 | (b) | keep; a bug for any owner (GPUCompiler) |
| 10 the inliner inlines exactly the CodeInstance named by `:invoke` | f72f7368f0 | 33 | (b) | keep; a stale-code hole for any owner |
| 17 registry of type printers | db82407fa6 | 62 | (b) | keep; upstream-ready |
| `TRAITWORLD.md` | several | 60 | docs | — |
| (A) facts mode, in-tree (uncommitted) | — | 269 + 10 | (A) | finish: the C half (`jl_compile_by_facts` reading `JULIA_COMPILE_BY_FACTS`, or `--compile-by-facts` in `jloptions.c`), the cache-flag bit, a build |

Note on the three copies of the rules (Verified by `cmp`): `TraitWorld/src/facts.jl` tests a closure type by name prefix *and* by whether the module binds the name to the instance (`_is_closure_type`, lines 128–138); the Compiler copy tests `F.name.singletonname`'s first byte only (`is_closure_type`). They may agree today; nothing checks that they do. The in-tree copy differs from the Compiler copy in its switch (`FACTS_IMAGE` plus a runtime ccall against an environment variable). One source of truth is needed before stage 2.

---

## 3. Path dependencies, ranked by how much they distort

### P1. The foreign cache owner, and everything that props it up (largest; distorts numbers, design text and the Julia work list)

*Verified:* `FactsInterp` with `FactsOwner` (`facts.jl:20–32`); a run-time site in policy code is rewritten to `_call_site(::_CallSite, f, args…)` or `_call_under_policy` (`_policy_sites!`, `facts.jl:475–503`); each site keeps a monomorphic cache keyed by world, `Core.Typeof` of every argument and a per-process token (`facts.jl:554–588`); misses look up the method by `jl_method_lookup_by_tt`, find or compile the policy's CodeInstance, and `Core.invoke` it; instances the policy cannot compile go into `_NO_POLICY`; bare `:invoke`s are rewritten to the owner's CodeInstance or a trampoline, and the trampoline's callees are compiled after the outermost inference under depth and count bounds (`_compile_pending!`, `facts.jl:621–645`); the worker call from an entry is a generated function whose generator runs the policy's inference and emits `invoke(f, ci, …)` with a hand-added edge and a `compilerbarrier(:const, …)` when effects are asserted below a run-time site (`facts.jl:749–800`); the compiler's own code runs in a world fixed at `__init__` (`_COMPILER_WORLD`); a system image with TraitWorld in it exists because REPL's `REPLInterpreter` breaks the image's compiler code (open-issues §1.3; `experiments/sysimage`).

*Why it exists:* the policy is an `AbstractInterpreter` in a package. Every item above is the project's own imitation of parts (B) and (C) of the plan, of piece 11 ("compile under owner X from inference"), of piece 12 (a frozen compiler world), and of piece 5. The lessons file says so in §5: "Gone with (B) and (C) in the runtime: 1.1 and 1.9 …; 2.4 and 2.5 …; patch pieces 5, 9, 10, 12 and 13 …; piece 11's two obstacles and assumption A4."

*What it distorts:*
- **Every headline number says "patched" and most say "system image".** The fresh-eye review's S1 and M6 still hold. Stock numbers are 10–500× worse (TraitMakie first PNG 4.6–11 s stock against 18–22 ms; TDE row 1 505 ms with loads before). The design is being judged on a runtime no one else has.
- **The REPL case** (5.9 s for a first new key without the system image) is a consequence of P1 alone and was the reason for the system-image prototype, which is itself a P1 workaround for a P1 workaround.
- **Assumptions A4 (no concurrent definitions) and A5 (the generator) are artefacts of P1**, not of the design, yet they appear in the design notes as assumptions of "identical or error" (`4-details.md`, "Identical or error"). With (B)+(C) in-tree they disappear, and the notes should say that they were implementation assumptions.
- **The Julia work list is skewed by it.** The "first upstream proposal" is "first-class foreign cache owners" (pieces 5, 9–13). If the policy is a mode of the native compiler, that proposal is mostly moot; what remains upstream-worthy is pieces 9, 10 and 17 as bug fixes and a small feature.
- **Size:** ≈ 1,300 package lines and 4 patch pieces for what the Compiler copy does in 280 lines, without site caches, trampolines, bounds on pending compilation or a frozen world.

*Reasoning:* the package form was a faithful prototype of (B)+(C), and it earned its keep by finding the rules (union splits in tuples, folding by Julia's asserted effects, `return_type`'s three steps, G1.10). It has now done its job. Keeping it alive beside the compiler mode doubles every change (lesson 2.4: a TraitWorld change means a system-image rebuild and recompiling everything).

### P2. The policy's benefit is trait-independent, and the demonstrators credit it to traits (distorts the thesis)

*Verified:*
- Lesson 1.1: CSV's reader, plain code reached from a worker, "keeps 661 policy CodeInstances, and loading DataFrames discards none of them (native CSV code: about 300 lost)". TraitReport form (b): "nothing of CSV's read path is recompiled" with DataFrames and InlineStrings loaded.
- The plain baselines lose exactly their abstract-signature specializations (fresh-eye B2, verified there by experiment); under the facts policy those sites would be run-time sites and the code would be kept.
- The plan's own decision rule names the control: "compare policy+traits against plain Julia with the switch at `all`" (plan §0), and the forks' plan names "upstream on the same patched build within 1.5×" as failure, but that control has piece 5 only, not the policy.

*Reasoning:* under `all`, the sentence "what the trait form adds: no load order changes its numbers" (TDE README, TraitMakie README, TraitReport README) is false for the baselines too, because they would not change either. What traits then add is: compile per key instead of per type (new types, closures, tuples of column types), checked boundaries, readable types, declared conformance in place of extensions on internal functions, listed AOT targets, and `Dynamic`'s cost against plain Julia's `isa` branches. Several of those are already contested by the baselines: PlainODE with FunctionWrappers matches TDE on rows 2 and 5 in a fresh session; PlainPlots matches TraitMakie on row 9. The honest residue is smaller than the READMEs say, and the demonstrators have not been pointed at it.

### P3. `Dynamic` by generated functions, registries and asserted effects (distorts the hot-loop numbers and introduced "sealed")

*Verified:*
- `_dyn_keys_now` is declared `Base.@assume_effects :foldable` and reads `_DECL_KEYS` and `_DYN_KEYS`, lock-protected `IdDict`s that grow at declarations and loads (`core.jl:449–463`). `:foldable` implies `:consistent`; the function is deliberately not consistent, so that the result is baked into the caller without an edge. The fallback (the witness call) keeps the code correct, so this is safe in effect and wrong in form, and the README lists the three pitfalls it caused (a generator cached per signature; constant propagation only for constants; a throwing fold taken as `Unreachable`).
- The Compiler copy exempts `_dyn_keys_now` by name in `facts_eval_refused`, and exempts *all* of TraitWorld's functions from the fact rule (`sealed_call`: "a call at abstract types is inferred as usual, with its edges"), because the machinery dispatches at abstract types (`Dynamic.t::Any`). This is the "sealed function" notion the user asked to remove (open-issues §2.26). It exists only because `Dynamic` is implemented outside the compiler.
- `Dynamic{X}` holds a boxed `TObj` (a tuple of views, each with `o::Any`, slots and held parts) and a `_Witness` (`core.jl:387–395`); constructing one takes `_LOCK` and two `IdDict` lookups (`_wit_table`, `core.jl:323–337`; the family registry in `_conf_family`). The commit message of 66253db records that "the trait object's second indirection dominates".
- Numbers (`factscompiler/README.md`): sum of `area` over 10⁶ values, plain 2 methods (`isa` branches, inlined) 3.8 ns; plain 4 methods (dynamic dispatch) 32–35; `Dynamic` old path 23–26; witness tables 14–17; key branches 10.9. Raytrace: plain 249 ms; trait with key branches 498–505 ms; the remaining gap is "one call per element: Julia does not inline members of a recursion cycle into each other, and the branches sit in a TraitWorld function on the recursion's path".

*Reasoning:* the key-branch mechanism *is* speculative devirtualization against the conformance list with a dynamic fallback; the compiler's inliner already does the same for small unions of concrete types (`isa` chains), and it can do it for `Dynamic{X}` if it is given the candidate list. Done there, the branches sit in the caller (plain Julia's shape), no edge is recorded (the fallback is correct), no generator, no foldable assertion, no `sealed` exemption, no per-process witness session token. The witness table is then a second-order optimisation of the fallback path, to measure after the split. The project's README reached the same conclusion; I agree with it and would act on it before any more package work on `Dynamic`.

A package-level simplification is available now and independent of the compiler: `Dynamic{X}` should hold the user's object (one word) and the branch should rebuild the view from constants per (trait, user type), because a `Builder` for a known pair is a constant. That removes the `TObj` allocation and one indirection and respects "no hidden type parameters" (`Dynamic{X}` stays explicit).

### P4. Traits as macros, registries and entries at `Any` (distorts the design less than it looks; leaks into user code)

*Verified:* 28 registry functions declared `@max_methods 1` with sentinel fallbacks (22 in `core.jl`); trait sets encoded as `Union{Family, PTag{Family, i, v}, …}` so workers have no free static parameters (`core.jl:189–218`); an entry per shape is an `@inline @nospecialize` method at `Any` generated by `_rewrite_fdef` (228 lines), which calls `enter` → `conformance` → `checked_call` → `_facts_call`; "types first, then traits" is imitated by `fallback`/`_plain_method`, which walks `methods(f)` and `morespecific` behind inference barriers (`entry.jl:477–513`); a trait's name means `Dynamic` only inside `@trait_module` (`_dynamic_fields`, `_dynamic_containers`), so the DataFrames fork writes `Vector{Dynamic{Column}}` and `tocolumn(c)::Dynamic{Column}` explicitly and needs a `ColumnVectors <: AbstractVector{AbstractVector}` adapter (`forks/DataFrames/src/dataframe/dataframe.jl`); `conforms(T, X)` exists and no demonstrator or fork uses it.

*Reasoning:* this is the package's imitation of piece 7 (traits in the type system). It costs 3–7 ns per typed call, boxes the trait object on untyped calls (105 ns), and makes error messages and `MethodError` candidate lists show machinery types (TraitMakie row 8, "open"). It does **not** distort the design's claims about keys or caching, and it is the right thing to keep as scaffolding: putting traits into Julia's subtyping, specificity and specialization is the deep change the plan rightly leaves for last, and nothing in the validation needs it yet. The one place the imitation leaks into semantics is `_plain_method`: a reflective re-implementation of method selection for the "trait bound below every type" rule, which plain dispatch would get right or wrong in ways this code may not mirror (ambiguities among plain methods, `Union` signatures, keyword methods). It is a soundness surface the compiler form would not have.

### P5. Leftovers of abandoned designs (distorts maintenance and the test matrix)

*Verified:*
- `ProjRec`, `projection`, `proj_lookup`, `proj_witness`, `_implement_projection`: live code (forwarding) under the name of the removed design (computed projections); `@implement _PC.PCT _PCProj project(t) = t.v` and `project(t) = t.v` in TraitWorld's own precompile module (`TraitWorld.jl:111, 114`); 19 traits in the tests in the `{R}` spelling (decisions D2, "phase 4, not done").
- View caches: a per-user package directory of generated `TWView_<hash>` packages built by a detached niced process at exit; the design text says "stored with the package that owns it". The fresh-eye review (S2) and the project's own principle note classify ComboCache-style caches as workarounds; this is the same mechanism.
- Thirteen `JULIA_TW_*` switches, among them `RUNTIME_SITES=native` (the pre-session-27 behaviour), `WITNESS=0`, `FACTS_POLICY=0`, `NOINLINE=1`, `KEEP_COMPILED=0`, `HOOKS=0`, `VIEWCACHE=0`. A test run covers one point of a 2¹³ matrix.
- Pieces 2 and 4 in the patch (≈580 lines, opt-in), three TraitWorld worktrees on old branches (`TraitWorld-dynkeep`, `-hooks`, `-untyped`) at the repository root.

### P6. Measurement path dependence (distorts the go/no-go)

*Verified from the README and plan:* BaseBenchmarks under (A) were one run per mode, with `--pkgimages=no`, on a system image compiled plainly (plan R4); the geometric mean of 1.016 is over 4,342 benchmarks of which 1,363 are `scalar` at 0.92 (ns-scale noise); without `scalar` 1.064; `io` 1.32 and `collection` 1.16 fail the user's own "no group above 20%" rule for `io`; the tails (containers of `Any`, 17–82×) are structural: a call with an `Any` argument has one method and plain Julia infers through it, the facts rule cannot, and the only cheaper alternative is an abstract edge, which is plain Julia.

*Reasoning:* the plan's text ("the overall mean passes and one group fails … Next, before the decision on (B)") reads the rule generously. The two recovery items done (`return_type` step 2, range sums) do not touch `io` or `collection`. The conclusion I draw is the opposite of "defer (B)": (A) at `all` is a good **test bed** (P-c) and a poor **user setting**, because the cost lands exactly where Base is `Any`-heavy, and the design's thesis never needed Base to be compiled by facts, only the trait world's closure. That is (B)+(C). The package has already demonstrated their semantics (16/16 acceptance, G2 0 lost over twelve loads, the forks' session 1.19 s); what is missing is their in-tree form, not evidence for them.

### P7. The forks' port strategy validates a barrier, not keys (distorts demonstrator 4)

*Verified:* `Column{T}` declares `nrows`, `cell`, `vector`; the kernels use `vector(c)` only (7 uses, 0 of `cell`/`nrows`); `colstats`, `takerows`, `refine!`, `firstcodes!`, `refcodes`, `aggregate`, `innerrows` each call `vector(c)` and run upstream's or Base's code on the concrete vector; `_dcolumn(df::AbstractDataFrame, i) = tocolumn(df[!, i])` builds a new `Dynamic` per access for anything but a `DataFrame`; `_group_rows!` combines per-column codes in plain code. CSV's `ColumnParsers` has one trait, `CSVSource`, with one operation `rawsource(s)::Any`, whose only purpose is to make `CSV.File`'s body a worker; the plan's `CSVColumn{T}` (per-cell-type parsing as conformances, the principled fix for `CSVInlineStringsExt`) is not written; the InlineStrings extension gained a workload instead, which the TraitReport README lists under "Not planned: … It would be a workaround".

*Reasoning:* per-column barriers compiled per concrete type are what plain Julia does when a careful author writes them, and what upstream partly does with `@nospecialize`. The fork's gain over upstream (10.9 s → 1.19 s) comes from three things: (i) the policy protecting the compiled closure from loads (the compiler's job after the pivot), (ii) workloads that cover the session's keys (`CSVDataFramesExt`, the DataFrames workload: both are plain-Julia remedies, and the README must count them as such, as lesson 2.3 already does for two fixes), (iii) replacing per-tuple specializations (sort, groupby) by per-column kernels combined in integer code (a real design point, and the one place where "compiled per key" beats plain Julia's shape). Only (iii) is a trait result, and it is achievable with an abstract type and a barrier too; the trait adds checking and the declared result types. Under the new design the control for the forks is **upstream under facts mode with the same workloads**, and the claim must be rewritten around (iii).

---

## 4. Simpler, more principled alternatives, per mechanism

The constraint is the user's: fixes that reflect the future ecosystem, Julia patches over workarounds, no hidden type parameters, names from the API user's view.

### 4.1 Must be in the compiler or runtime (and how small)

| Element | Minimal in-tree form | Size (estimate) | Replaces |
|---|---|---|---|
| **(A) facts as an inference mode** | `facts.jl` as it is in the Compiler copy, with the mode a field of the inference frame rather than a global (`facts::Bool` on `NativeInterpreter` or `InferenceParams`), set from `jl_options` (`--compile-by-facts=no|all|traits`) and a bit in the package-image cache flags | ≈ 300 lines (exists, minus the global) | `TraitWorld/src/facts.jl:1–407`; the Compiler copy; two of three rule copies |
| **(B) a second owner: "this method is compiled by facts"** | a method flag (as `nospecializeinfer` and `purity` are flags), set by `@trait_module` on its workers; inference of a flagged method, and of everything reached from a facts frame, runs with `facts = true` and `cache_owner = FactsOwner` (a sentinel in `Core`); `CodeInstance.owner` already exists; images store and compile native code for that owner (the foreign half of piece 5, ≈ 15 lines in `staticdata_utils.c`/`precompile.jl`); `typeinf(::FactsOwner, mi, mode)` resolved in `Compiler` (the `CompilerPlugins` entry 1.13 already declares) | ≈ 100 lines Julia, ≈ 30 C | `FactsInterp`, `_FactsCallGen`/`_facts_call`, `_typeinf_policy`, `_compile_pending!`, `_owner_ci`, `_invoke_under_policy`, `_owner_invokes!`, `_COMPILER_WORLD`, `_latest_under_policy` (29 sites), `_check_interp`, the system-image prototype, assumptions A4 and A5, piece 11's two obstacles (one interpreter type, so one frame stack; asserted effects handled where `finish!` taints effects for frames with run-time sites) |
| **(C) owner-aware dynamic dispatch** | codegen for a facts frame emits run-time calls through `jl_apply_generic_owner(owner, F, args, n)`: the same method-cache lookup as `jl_apply_generic`, then `jl_compile_method_internal` for that owner (compiling under (B) on a miss) | ≈ 150 lines C (a variant of `jl_apply_generic` + `jl_compile_method_internal` taking an owner) | `_policy_sites!`, `_call_under_policy`, `_policy_ci`, `_CallSite`/`_site_miss`/`_call_site`, `_NO_POLICY`, `_keep_method`, lesson 1.9's monomorphic site caches and their session tokens |
| **(D) `Dynamic` call-site split** | in `ssair/inlining.jl`: for a call whose receiver is `Dynamic{X}`, ask a registered hook for the candidate concrete types of `X` (TraitWorld's `_DECL_KEYS`), emit `isa` guards with direct calls of the operation at each (which inline), then the ordinary dynamic call; no edge to the candidate list (the fallback is correct); bounded as union splitting is | ≈ 150 lines | `_dyn_call_keyed`, `_dyn_keys_now` and its `:foldable` assertion, `_dyn_hop`, `_note_conformances!`, `sealed_call` and the `_dyn_keys_now` exemption in the Compiler copy |
| Pieces 1, 3, 9, 10, 17 | as they are | — | — |
| Piece 5, upstream half | as it is; measure alone (it is also plain Julia's gain) | — | — |
| Piece 14 (read-only "would invalidate" query) | later, for strict mode's exact check | small | `strict.jl`'s backedge walk and invalidation-log safety net |

*Reasoning on (B):* marking *methods* rather than call sites is what makes the entry's worker call an ordinary `:invoke`: the worker method is flagged, so any CodeInstance of it is facts-compiled whoever calls it, and its callees inherit the mode through the frame. The plain caller's edge to the worker's CodeInstance is owner-aware (piece 9) and the inliner respects the named CodeInstance (piece 10). The trait module's macro sets the flag, so the user never sees it, which satisfies "names from the API user's perspective": the user-facing fact is "trait-module code is compiled by facts".

*Reasoning on the switch:* `all` stays as the test bed and the measurement of (A)'s cost (P-c); `traits` is the product setting. Both exist with the same (A) code.

### 4.2 Can stay a package

Everything in class (a) of §2.1: the macros, ownership, conformance as methods, entries and workers, keys and the reference layout, `Callable`/`Erased`, `Like`, definition checking, concrete mode, `verify_main`, strict mode's rule (behind piece 1), printing. The `@max_methods 1` registry pattern and `PTag` encoding are acceptable scaffolding until piece 7, which should wait for the measurements the plan already says it should wait for.

Two package-level simplifications worth doing now:
- **`Dynamic{X}` holds the user's object**, not a boxed `TObj`; the view for (X, typeof(o)) is a constant per pair, rebuilt at the branch or in the fallback. One indirection fewer, no allocation per `Dynamic` beyond the box, no `_narrow`.
- **Workers call operations on `Dynamic` through one path**: after (D), `_dyn_call` is `f(opened(d), args…)::RT`, and the witness tables are deleted unless the raytrace after (D) still needs them.

### 4.3 Can be deleted

- `viewcache.jl` (348) and its exit hook, `JULIA_TW_VIEWCACHE*`. The design problem it stood in for (lesson 2.2: workers for (key owner, function owner) pairs no package owns) is plain Julia's problem too, and the honest answer is the one the lessons give: a glue extension per pair, or a first-session compile that is then kept by the owner's image once (B) stores facts code in images. An environment-level cache is a separate, later experiment with its own measurement, not a default mechanism.
- `experiments/sysimage` (keep the README as history).
- Pieces 2 and 4 of the patch (≈580 lines), `JULIA_TW_FILTER`.
- `_PC`'s `{R}`/`project` spelling, the `{R}` spelling in 19 test traits (phase 4 of the keys plan), the `projection` names.
- Ten of the thirteen `JULIA_TW_*` switches.
- The llvmcall TBAA fallback once stock Julia is dropped (decision P-b: the design needs the patched build anyway; stock support costs 30 lines here and a second behaviour in `_invoke_under_policy`, `_policy_ci`, `_vc_in_image`, `_HAS_FIELD_INTRINSICS`).
- The compiler warm-ups in `TraitWorld.jl:184–219`.
- The three old worktrees at the repository root (their branches stay in `TraitWorld`'s history).

---

## 5. The demonstrators

### 5.1 What they validate today

| Demonstrator | What its rows show (Verified from READMEs and baselines) | Whose property it is after the pivot |
|---|---|---|
| TDE rows 1, 7 (first solve 6.4–8.0 ms in every order; 0 lost over 12 loads) | the policy protects the closure; PlainODE loses 19 of 74 CodeInstances rooted at `@nospecialize solve` and recompiles 54 ms after loads | the compiler's (A); a hardened PlainODE or PlainODE-under-facts is expected to match |
| TDE rows 2, 4, 5 (a second model function 6–8 ms; a second callback 5 ms; a second loss 17–21 ms) | compile per signature, not per closure | **traits' claim, but PlainODE with FunctionWrappers and a signature-labelled tag matches it in a fresh session** (README baseline table); the trait adds the check and the uniformity, not the number |
| TDE rows 9, 10 (12 frames; `Tsit5Integrator{Float64, Vector{Float64}}`) | readable types and traces | traits' (design); measured, holds |
| TDE row 11 (run time 1.19× at n = 3, within 1% at n = 1000) | the reference layout costs little | traits' (layout); holds |
| TraitMakie rows 1–3 (18–22 ms in every order; PlainPlots 100 ms after loads) | the policy | the compiler's |
| TraitMakie row 4 (a new type: conformance 0.1–0.2 s; 6.4 s after loads without the image) | `@implement`'s checks; P1's REPL cost | the checks are traits'; the 6.4 s is P1 |
| TraitMakie row 6 (colour shape change 9–112 ms) | `Dynamic` works | traits' |
| TraitMakie row 7 (4.07 MB binary; `--trim=safe` 26 errors from the machinery) | AOT | traits' (target lists); the 26 errors are the package's machinery |
| TraitReport form (t) vs (pt) (0.52–0.56 s vs 0.50–0.52 s fresh; 66–80 ms vs 102–147 ms under loads) | a fresh session: no difference; under loads: the policy | the compiler's |
| TraitReport row 11 (`String15` conformance: 44 ms in later sessions, via a view cache; CSV.jl 3.9–5.0 s) | an extension as a conformance invalidates nothing | half traits' (declared conformance instead of methods on internal functions), half the policy's; the 44 ms depends on a view cache (S2) and the comparison is not like for like (S4) |
| Forks M0–M5 (session 10.9 s → 1.19 s) | policy + workloads + per-column kernels | mostly the compiler's and workloads'; per-column kernels are a design point (P7) |

### 5.2 Which measurements change meaning under the compiler-mode design

- **All "lost to loads" rows become controls of the compiler mode**, not of traits. Report them once, for plain code under `all`, as the (A) result; drop them from the trait READMEs' "what the trait form adds".
- **The "patched vs stock" split disappears**: the patched build *is* the compiler with the mode; stock has no comparable configuration. The honest table per row becomes: plain Julia (mode off) / plain code (mode `all`) / trait code (mode `traits`), on the same build.
- **System-image rows vanish** with (B): there is no foreign compiler code to protect.
- **View-cache rows vanish** with the deletion of view caches: first-session numbers become primary (S2 asked for this anyway).
- **Fresh-session headlines** (0.52 s, 6.4 ms, 18 ms) keep their meaning and keep their caveat: precompiled keys with workloads extended to the measured calls; the baselines match.
- **Piece 5's share** must be measured alone (PlainReport 2× faster with it, TraitReport README) and credited to Julia, not to traits.
- **The forks' falsification clause** ("upstream on the same patched build within 1.5×") must be re-pointed at upstream under `all` with the fork's workloads applied to upstream too.

### 5.3 Is demonstrator 4 the right next demonstrator, and is its strategy sound?

*Reasoning:* it is the right *subject* (the user's interactive case, real packages, a pandas comparison), and the forks-not-rewrites decision was correct (upstream suites as the correctness bar). The *strategy* is sound only in part:
- `Vector{Dynamic{Column}}` as storage is the design's stated proposal and is sound under the new design (a `Dynamic` in the compiler is still a value with a dynamic operation). But the port does not use it as a trait: kernels unwrap at once (`vector(c)`). As long as that is the shape, `Vector{AbstractVector}` with a per-column barrier function compiled by facts gives the same code and the same protection. The port should either use the operations where upstream specializes per tuple (sort, groupby, join: `cell`/`isless` per column through the trait with declared result types, or a `RefColumn` fast path through declared operations), or state plainly that the storage change is a barrier discipline made systematic.
- "One function at a time" is right and is what the design promises; it has been done for about ten functions. The upstream suites have not been re-run since M3 as far as the README records; the plan requires them at every milestone.
- `CSVSource` is not the plan's `CSVColumn{T}`; the InlineStrings workload is the workaround the project said it would not make. M5 should implement `CSVColumn` conformances or drop the row-11 claim for the forks.
- The port's biggest numbers depend on P1 and on workloads; without the upstream-under-facts control the port cannot show what it was built to show.

**What to stop, restart, re-point:**
- **Stop** M6–M9 until the in-tree (A) exists and the plain baselines and upstream DataFrames have been run under it. Every hour on kernels before that is spent on a comparison whose control is missing.
- **Stop** adding package machinery for `Dynamic` (witness tables, key branches) and the system image; the next `Dynamic` work is (D) in the inliner.
- **Restart** the three small demonstrators' baselines as "plain under `all`" once (A) is in-tree; they are cheap to precompile and already have load matrices and `invalidated.jl`.
- **Re-point** the READMEs' "what it demonstrates" at the trait-specific residue: compile per key (with PlainODE's FunctionWrappers number beside it), definition-time errors, readable types, declared conformance in place of extensions on internals, `Dynamic` against `isa` branches, AOT target lists; and state the policy's protection once, as the compiler's.
- **Keep frozen as history:** `experiments/interfaces`, `experiments/sysimage`, the view-cache measurements, TraitReport forms (a), (a′), (b), the session-23–27 numbers.

---

## 6. Recommended target architecture and migration order

### 6.1 Target

```
Julia (patched → upstream proposals)
  (A) facts mode in the native interpreter      ≈300 lines  [exists as a copy; move in-tree, build]
  (B) method flag "compiled by facts" + owner    ≈130 lines  [new]
  (C) owner-aware dynamic dispatch               ≈150 lines  [new, C]
  (D) Dynamic call-site split in the inliner     ≈150 lines  [new]
  pieces 1, 3, 9, 10, 17; piece 5 upstream half  ≈400 lines  [exist]
  switch: --compile-by-facts=no|all|traits

TraitWorld (package)
  @trait, @implement, @trait_module (sets the (B) flag on workers), ownership,
  conformance as methods, entries/workers, keys and layout, Callable/Erased, Like,
  definition checking, concrete mode, verify_main, strict mode, printing      ≈5,500 lines
  Dynamic{X}: a type holding the user's object; operations call f(opened(d))::RT;
  the candidate-type hook for (D)                                            ≈150 lines

Deleted
  facts.jl (all of it), viewcache.jl, frames.jl's hiding (replace by a Julia registry later),
  warm-ups, _PC legacy, 10 switches, sysimage prototype, pieces 2 and 4, 3 worktrees
  ≈ 2,000 package lines, ≈ 580 patch lines
```

### 6.2 Migration order, ranked by value

1. **Finish (A) in-tree and build it** (plan stage 2). Write the C half (`jl_compile_by_facts`, or better the `jloptions.c` option), the cache-flag bit, one source of truth for the rules (delete the Compiler copy's and TraitWorld's once the in-tree one passes TraitWorld's tests and `experiments/facts/acceptance.jl`), a build under the memory watchdog. Until this exists no number is free of R4 and every measurement needs a 23 s bootstrap and `--pkgimages=no`. *Value: unblocks everything below.*
2. **The one experiment that most reduces uncertainty: the plain baselines under `all`.** PlainODE, PlainPlots, PlainTables and upstream DataFrames+CSV (with the forks' workloads applied) under `--compile-by-facts=all`, the existing load matrices, `invalidated.jl`'s lost-CodeInstance counts and the step times. Before step 1 exists, a weaker form is possible today with `Compiler.activate!` and `--pkgimages=no`: compile the work in-session, load the twelve packages, count lost CodeInstances (times are meaningless without images; counts are not). *Value: decides which claims the trait READMEs may keep.* My expectation (Reasoning): the baselines lose nothing under `all`, TDE rows 1/7 and TraitMakie rows 1–3 and TraitReport rows 7/8 become controls, and the trait residue is rows TDE 2/4/5 (with the FunctionWrappers caveat), 9, 10, TraitMakie 6/8, TraitReport 11 (declared conformance).
3. **(B)+(C) in-tree as a method-level mode**, then delete `facts.jl`'s imitation half, the generator, `_latest_under_policy`, the warm-ups, the system image; re-run the acceptance suite (16), `g2all`, TraitWorld's tests, the forks' session. *Value: removes P1 and assumptions A4/A5 from the design; makes every "patched" number a "compiler mode" number; makes `verify_main` see workers (ordinary `:invoke`).*
4. **`Dynamic`: the package simplification (hold the user's object), then (D) in the inliner**; re-measure `dynmicro` and the raytrace; delete witness tables if (D) suffices; delete `sealed_call`. *Value: the hot-loop story (2× plain today) and the end of "sealed".*
5. **Re-point the demonstrators** (§5.3); rewrite the three READMEs' claims and scopes to the tree (S6 is still open); drop view caches and report first sessions.
6. **Forks: resume at M5 with `CSVColumn`**, the upstream-under-`all` control as configuration 2′, the suites re-run at each milestone, and the kernels re-shaped so that at least sort and groupby use declared operations rather than `vector(c)`.
7. **Housekeeping:** revert pieces 2 and 4; remove the dead switches; convert the `{R}` tests and `_PC`; rename `projection`; remove the worktrees from the repository root (keep the branches).
8. **Upstream proposals, re-ordered:** pieces 10, 9, 17 as bug fixes and a small feature now; "a facts mode for the native compiler" (A) with the BaseBenchmarks table when stage 2 is measured; (B)+(C) as "per-method inference modes" only after they have carried the demonstrators; traits in the type system last, unchanged.

### 6.3 Decisions this review asks of the user

- **P-b (stock Julia support): drop it.** It costs a second behaviour in six places and the llvmcall fallback, and the design's own text says the policy belongs in the platform.
- **P-c (`all` as a user setting): treat it as a test bed**, by the user's own rule (`io` 1.32).
- **The forks' pause** until step 2 exists, against continuing M6–M9 on the present control.
- **Whether `Dynamic` work continues in the package** (witness tables, key branches) or waits for (D).

---

## 7. What is sound and should be kept (so that the critique is not read as a teardown)

- **The facts rules themselves** (`_fact_sig`, splits in tuples, closures at kinds, folding only by Julia's asserted effects, the three steps of `return_type`): found by validation (E3's nine cases exact; 16/16 acceptance; 48 adversarial cases), stated in 269 lines, and already shown to cost 1.6% geometric mean on BaseBenchmarks. This is the project's central technical result and it survives the pivot intact.
- **Runtime as methods** (conformance as a `@max_methods 1` method with a fallback; entries as `@inline @nospecialize` methods): typed calls at 33 ns against 30 plain, no allocation, and a representation the compiler form can keep.
- **Keys and the reference layout** with the field-offset intrinsics: loops at plain speed (0.121 against 0.120 ns per element), the one measured layout result that no baseline contests.
- **Ownership (rule 3) and Lemma O**, corrected in session 27: the soundness argument for G2 does not depend on where the policy lives.
- **Definition checking at archetypes and concrete mode**: the two mechanisms that make "checked where it is defined" real; TraitCSV's `sizehint!` refusal and the CTop/CBottom root-cause report are the kind of evidence the design needs more of.
- **The forks as a correctness bar** (upstream suites unchanged, forks drop-in by `[sources]`), the measurement harness (fresh processes, raw timestamps, one job under a lock, load logged), and the candour of the baseline tables.
- **The pivot decision itself**, and the Compiler-package route to it (`Compiler.activate!` with no Julia rebuild) was the cheapest possible way to get the BaseBenchmarks number.

---

## Appendix: verification log

- `wc -l TraitWorld/src/*.jl`; `git -C TraitWorld show b60b126:src/<f> | wc -l` for each file; `git -C TraitWorld diff --stat b60b126..HEAD`.
- `git -C julia-1.13 log --numstat v1.13.2..HEAD`; `git -C julia-1.13 status --short`; `git -C julia-1.13 diff` (the 10 uncommitted hook lines).
- `grep -rn jl_compile_by_facts julia-1.13/src julia-1.13/base julia-1.13/Compiler/src` → only the two comments and the `ccall` in `Compiler/src/facts.jl`.
- `nm -D julia-1.13/usr/lib/libjulia-internal.so | grep -i "compile_by_facts|set_method_definition_hook|set_image_keep_compiled"` → the two hook symbols present, no `compile_by_facts`.
- `ls -la --time-style=full-iso` of `Compiler/src/facts.jl` (2026-10-18 10:24), `usr/lib/julia/sys.so` (2026-10-17 09:34), `usr/bin/julia` (2026-10-16 15:45).
- One run: `JULIA_NUM_PRECOMPILE_TASKS=4 flock /tmp/claude-1000/julia-review.lock nice -n 19 timeout 900 julia-1.13/julia --startup-file=no -e '…'` → `1.13.2`; `facts_mode defined: false`; `getfield_at_offset: true`; `register_type_printer: true`; `def hook: true`; `cglobal(:jl_compile_by_facts)` → undefined symbol.
- `cmp` of the three `facts.jl` copies; `diff` of the Compiler copy against the in-tree file (header and switch differ).
- `git -C forks diff upstream --stat` and the diffs of `Tables/src/ColumnCore.jl`, `DataFrames/src/other/kernels.jl`, `dataframe.jl`, `groupeddataframe/*.jl`, `join/core.jl`, `abstractdataframe/*.jl`, `CSV/src/*.jl`, `CSV/ext/*.jl`.
- `grep -nE '\b(cell|nrows)\(' forks/DataFrames/src -r` → none; `grep -c 'vector(' forks/DataFrames/src/other/kernels.jl` → 7; the same on `TraitTables/src/TableCore.jl` → 17 uses of `cell`/`nrows` (the small demonstrator does use the operations).
- `grep -rn "conforms(" TraitMakie/src TraitDifferentialEquations/src TraitTables/src TraitCSV/src TraitReport/src forks/*/src` → none.
- `grep -c "@max_methods 1 function" TraitWorld/src/*.jl` → 22 + 3 + 3; `grep -c "_latest_under_policy\|_in_world_under_policy"` → 29 sites in 10 files; `grep -oh 'JULIA_TW_[A-Z_]*'` → 13 switches.
- Read in full: `TraitWorld/src/{TraitWorld,facts,core,entry,hooks}.jl`; in part: `trait_module.jl` (85–215, 405–650), `checks.jl` (240–325), `implement.jl` (586–700, 859–930), `viewcache.jl` (126–255), `defcheck.jl` (1–60), `strict.jl` (1–70); `experiments/factscompiler/{README.md,Compiler/src/facts.jl,recovery/RTTrait.jl,recovery/dynmicro.jl,scripts/twtests.jl}`; `experiments/sysimage/README.md`; `experiments/facts/README.md` (head); all five demonstrator READMEs; `forks/README.md`; `writeup/reviews/2026-10-17-demonstrators-fresh-eye.md`; the design notes, decisions, open issues, lessons, julia-support and the two plans.
