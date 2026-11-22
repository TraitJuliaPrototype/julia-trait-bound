# The changes to Julia for upstream: the plan for the facts series and the traits series (W-19)

**Status:** proposal (2026-11-22; series G, the facts parts F0 to F12 and F4 in three are made, and the two series are built together). Written beside the patches useful without traits ([their table](../../experiments/implementation/w19/README.md)). Not normative: the references are.

**What it is.** The plan's stage 8 ([the next iteration](../plans/2026-11-15-next-iteration.md)) asks for two proposals that stand apart: the facts rule with ownership, and traits (sets, memberships, contracts, the box and the wrapper). This file cuts the final tree's diff into parts a core developer reviews one at a time, orders them, and names what does not go upstream as it is. No patch of these two series is made here.

**The source.** `git -C julia-next diff 45b6d15e34 cf0f039f51` (Julia v1.13.2 against `next` at the freeze `round-2026-11-c`), read by file and by function. The tools: `tools/funcsizes.py` (the lines a diff adds, by function of the new tree), `tools/parts.py` (those lines by part of this plan), `tools/bykind.py` (by kind). Their output: `logs/funcsizes.tsv`, `logs/parts.txt`, `logs/bykind.txt`.

## 1. The diff

**By directory** (files, lines added, lines removed):

| Directory | Files | Added | Removed |
|---|---|---|---|
| `src/` | 31 | 8,088 | 386 |
| `Compiler/` | 20 | 3,247 | 129 |
| `base/` | 19 | 398 | 97 |
| `stdlib/` | 1 | 3 | 1 |
| `test/` | 2 | 2 | 2 |
| `contrib/` | 1 | 2 | 0 |
| `doc/` | 0 | 0 | 0 |
| all | 74 | 11,740 | 615 |

**By kind** (added lines; an estimate by function name and file, `tools/bykind.py`; a function changed for two kinds counts once):

| Kind | Added lines | Of which made as patches here |
|---|---|---|
| useful without traits | about 590 | all: 18 patches, 595 added and 121 removed (`README.md`) |
| facts | about 1,450 to 1,850 | none |
| traits | about 7,800 | none |
| not assigned (comments and declarations the parser assigns to no function: `gf.c` 562, `datatype.c` 224, `abstractinterpretation.jl` 200, headers) | about 1,900 | none |

Most of the unassigned lines sit in files that are the type system's (`datatype.c`) or that both series change (`gf.c`, the headers). Read: traits is about four fifths of the diff, facts about a sixth, the general patches a twentieth.

**The largest functions touched** (added lines in the function of the new tree):

| Lines | Function | File | Series |
|---|---|---|---|
| 186 | `membership_subst_sig` | `src/gf.c` | traits |
| 176 | `jl_membership_dispatch_walk` | `src/gf.c` | traits |
| 169 | `jl_declare_membership` | `src/datatype.c` | traits |
| 142 | `invalidate_intersecting` | `src/gf.c` | traits |
| 140 | `jl_type_all` | `src/jltypes.c` | traits |
| 108 | `jl_membership_removal_walk` | `src/gf.c` | traits |
| 106 | `membership_ambiguities` | `src/gf.c` | traits |
| 105 | `typeinf_ext_toplevel` (and the build's rounds after it) | `Compiler/src/typeinfer.jl` | traits (a closed build), facts (policy) |
| 103 | `declared_result_of` | `src/method.c` | traits |
| 98 | `membership_subst_nested` | `src/gf.c` | traits |
| 92 | `abstract_call_gf_by_type` | `Compiler/src/abstractinterpretation.jl` | facts and traits |
| 92 | `closed_note_used!` | `Compiler/src/typeinfer.jl` | traits |
| 92 | `jl_get_abi_converter_caller_world` | `src/runtime_ccall.cpp` | general (made: `up/16`) |
| 70 | `member_hook_at_dispatch` | `src/gf.c` | traits |
| 70 | `jl_could_join` | `src/subtype.c` | traits |

`abstract_call_gf_by_type` is the one function where the two series interleave line by line: the facts inference's matching (`facts_find_method_matches`), the closed build's splits and the sets' record of memberships share its body.

## 2. The parts

Each part is a patch a core developer reviews alone. *Lines* are added lines from `tools/parts.py` (the function-level estimate; a part's comments are counted only where they sit inside its functions). *Gate*: `experiments/implementation/gates/`; *Julia's tests*: the files of Julia's own suite the part changes or that cover it.

### 2.1 Series G: useful without traits (made)

The 18 branches `up/01` to `up/18`, each on v1.13.2 alone: `README.md`. 595 lines added, 121 removed. Two more candidates found in the diff are listed in §2.4 (S1, S2).

### 2.2 Series F: the facts rule with ownership

| Part | Subject | Files and functions | Lines | Depends on | Reference | Gate, tests |
|---|---|---|---|---|---|---|
| F0 | The fields: `Method.facts`, `jl_module_t.facts`, the CodeInstance flag `JL_CI_FLAGS_FACTS`, the MethodInstance's cached policy bits | `julia.h`, `jltypes.c` (the field lists), `method.c`, `module.c`, `staticdata.c` (saved with the method and module) | about 60 | — | compiler §2.1, §2.2 | `test/core.jl` (field lists) |
| F1 | The `nortsite` effect bit: a call that records no edge clears it, carried to callers as `nortcall` is | `Compiler/src/effects.jl`, `optimize.jl` (`flags_for_effects`) | 55 | — | compiler §1.3, §1.5 | `f1_facts_sites` |
| F2 | The policy: `@compiler_options facts=true`, `Expr(:meta, :facts_boundary)`, `:facts_always`; lowering carries the meta into every method a definition makes; `jl_method_policy` | `base/experimental.jl` (the `facts` option only), `module.c` (`jl_set_module_facts`, `jl_method_policy`, `facts_all`), `method.c` (`jl_method_set_source`), `ast.c`, `julia-syntax.scm` | 150 | F0 | compiler §2.1, §2.2 | `f2_policy_flags` |
| F3 | The facts inference: `is_fact_sig`, a call inferred with an edge only at a fact signature, a run-time site elsewhere; `NativeInterpreter(; facts)` | `Compiler/src/facts.jl` (`is_fact_sig`, `vararg_fact`, `fact_splits_ok`, `facts_find_method_matches`, …), `abstractinterpretation.jl` (`abstract_call_gf_by_type`, `abstract_call_unknown`, `infercalls`), `types.jl` | 390 | F1 | compiler §1.1, §1.2 (without owner-only), §1.3 | `f1_facts_sites` |
| F4 | One CodeInstance per MethodInstance and policy; calls between policies: dispatch runs the code of the selected method's policy for the code that dispatches (`jl_apply_generic_plain`/`_facts`, `jl_invoke_*`, the builtins' variants, the interpreter's policy, the engine's reservation per policy) | `gf.c` (`mi_policy`, `_jl_invoke`, `apply_generic_reach`, `jl_type_infer_policy`, `jl_compile_method_internal_policy`, `jl_rettype_inferred_policy`), `codegen.cpp` (`applygeneric_for`, `invoke_for`, `mk_reach_builtin_map`), `builtins.c` (`jl_apply_reach`), `interpreter.c`, `engine.cpp`, `Compiler/src/cicache.jl`, `facts.jl` (policy helpers, `typeinf_other_policy`), `typeinfer.jl` (`typeinf_ext_toplevel`'s policy, the compile queues) | 614; made in three (`w19-facts-split`): F4a the CodeInstance per policy 231, F4b the calls at run time 310, F4c inference across policies 75 | F2, F3 | compiler §2.3, §2.4 | `f3_policy_code`, `f6_reach_policy`, `n15_image_policy` |
| F5 | `return_type` gives plain inference's answer under either policy (`PlainRTInterp`) | `tfuncs.jl` (`return_type_tfunc`), `typeinfer.jl` (`return_type`), `facts.jl` | about 60 | F4 | compiler §1.4 | `f5_return_type` |
| F6 | The test bed: `JULIA_COMPILE_BY_FACTS=1`, neutral methods take the policy of the code reaching them | `module.c` (`jl_compile_by_facts_all`), `gf.c` | about 20 | F4 | compiler §2.5 | `f6_reach_policy` |
| F7 | The deep class: the G2 bit on every CodeInstance from its edges; an inference cycle decided as one; an edge names the callee's code where it exists when the caller finishes | `facts.jl` (`edges_satisfy_g2`, `name_callee_code`), `typeinfer.jl` (`finish!`, `finish_cycle`, `codeinst_as_edge`), `gf.c` (`jl_ci_set_g2`) | about 150 | F3, S1 | compiler §3.2 | `f4_g2_bit`; `w155/gate_deep.jl` |
| F8 | Images and `--trim` under the policy: an image keeps code reached only dynamically where it is deep G2; it holds the code a facts run-time site reaches whatever the values (`rtsite_targets`); a trimmed build is plain and writes every module as never facts | `staticdata_utils.c` (`queue_external_cis`), `staticdata.c`, `facts.jl` (`rtsite_targets`), `typeinfer.jl` (`compile!`, `collectinvokes!`) | 155 | F4, F7 | compiler §2.6, §9 | `n15_image_policy`, `n17_rtsite_targets` |
| F9 | Ownership: owner-only functions (`jl_set_owner_only`, the binding flag; the module scope option `owner_only` with its `export` and `public` lists); a call of one is a fact at any signature | `module.c` (`jl_set_owner_only`, `jl_binding_owner_only_p`), `julia.h` (`BINDING_FLAG_OWNER_ONLY`), `facts.jl` (`is_owner_only`, `owner_only_call`), `experimental.jl` (`owner_only`) | about 45 | F3 | compiler §1.2; facts §3 | `n36_library_deep` (with the library); none without it: a gate to write |
| F10 | What a definition ended of the deep class, by kind and cause, for the library's report of a pirate | `gf.c` (`deep_ending_*`, `jl_take_deep_endings`, `jl_note_deep_ending`), `reinfer.jl`, the collectors' roots | 65 | F7 | compiler §10.2 | the library's `test/strict.jl` |
| F11 | Fully typed mode: a method's meta or its module's option; code with a fault starts with a check that reaches a hook | `ast.c`, `method.c`, `module.c` (`jl_method_fully_typed`), `gf.c` (`jl_not_fully_typed`), `facts.jl` (`insert_fully_typed_check!`, `fully_typed_fault`), `optimize.jl` | 60 | F3 | compiler §2.7 | `n9_fully_typed` |
| F12 | One compiled code per result: a compile request takes the code of any equivalent cached entry, a compiled one first, of the same policy | `typeinfer.jl` (`equivalent_cached_ci`) | 25 | F4 (the policy in its test) | compiler §3.3 | `slot_cascade`; `w145/profile/chain_position.jl` |

**Series F in all:** about 1,900 lines with F0. **The smallest series that gives a working facts mode** (E-392's measurement: upstream CSV and DataFrames by facts with one line per module, 14 of 3,490 own image instances lost to nine unrelated loads against 424 of 4,693 plain): F0, F1, F2, F3, F4, F5, F7, F8, with S1. About 1,700 lines estimated; **made** (`w19-facts`): 1,191 lines added with S1 and its test, and the series alone reproduces the measurement (14 of 3,461 lost; the work after the loads 1.43–1.45 s against plain's 5.14–5.16 s; E-534). **F6 and F9 to F12 are made too** (45, 93, 95, 127 and 25 lines; F9 adds the module's options word and has the gate `g-f9_owner_only`): the series whole is 32 files, 1,555 lines added. E-392 ran before owner-only (F9) existed; F9 is ownership's own part, and F10 and F11 serve the library.

### 2.3 Series T: traits

| Part | Subject | Files and functions | Lines | Depends on | Reference | Gate, tests |
|---|---|---|---|---|---|---|
| T1 | Core's types and slots: `TypeName.memberships`, `.contract`, `.declared_fields`, `.operations`, the bits `open_set`, `never_member`, `erases`, `closed_after_load`, `input_params`; `DataType.has_open_set` (the flags word widened to 32 bits, with Base's masks); `Core.All`, `Core.Callable` | `julia.h`, `jltypes.c` (`jl_init_types`, `post_boot_hooks`, `jl_precompute_memoized_dt`), `base/boot.jl`, `base/runtime_internals.jl` (the masks), `test/core.jl` | 220 | — | compiler §4.1 | `test/core.jl` |
| T2 | Sets and memberships: the declaration and its checks (a cycle, one instance per member, a redeclaration), entries with worlds, transitive subtyping inside `jl_subtype`'s walk, the query world, reachability memoized, a non-member's fast path | `datatype.c` (`jl_declare_membership`, `jl_set_open_set`, `publish_entry`, `index_entry`, inputs, patterns), `subtype.c` (`subtype_membership`, `jl_subtype_via_membership`, `reach_memo_*`, `jl_membership_query_world`, `obviously_disjoint`, …) | 1,730 | T1 | compiler §4.2 to §4.7, §4.11 | `m1_*`, `m2_set_*`, `n10_inputs`; `test/subtype.jl` against vanilla (E-262's four suites) |
| T3 | Intersections `All{X, Y}` in their normal form | `jltypes.c` (`jl_type_all`), `subtype.c` (`intersect_with_all`, `intersect_membership`), `base/show.jl` (`show_datatype`) | 390 | T2 | compiler §4.9 | `n2_all_*` |
| T4 | Dispatch at sets: methods at sets in the typemap's linear list, match world ranges through entries, specificity at sets, the ambiguity report at a membership, `isambiguous` at an unmet intersection | `typemap.c`, `gf.c` (`index_func_set_method`, `jl_methods_at_set`, `ml_matches*`, `membership_ambiguities`, …), `datatype.c` (`ambiguity_message`), `base/reflection.jl`, `Compiler/src/methodtable.jl` | 640 | T2 | compiler §5.1 to §5.4 | `m2_ambiguity_*`, `m2_typemap_linear`, `m2_dispatch_worlds` |
| T5 | A membership invalidates as a method does: the walk over the methods at the set, substituting the member; the removal walk | `gf.c` (`jl_membership_dispatch_walk`, `membership_subst_sig`, `membership_subst_nested`, `invalidate_intersecting`, `jl_membership_removal_walk`, …) | 1,080 | T4 | compiler §5.5 | `n27_invariant_parameter`, `n28_wide_caller`, `n32_nested_set` |
| T6 | The membership's method (`Core.implements`); folds and their edges: a negative as an absence edge, a positive through an entry (`new`'s field test, `IR_FLAG_TYPES_PROVEN`, `emit_isa`), `isa` narrowing | `method.c` (`jl_new_membership_method`), `datatype.c` (`absence_*`), `Compiler/src/typeutils.jl`, `abstractinterpretation.jl` (`prove_type_test!`, `abstract_eval_new`, `isa_condition`), `tfuncs.jl`, `cgutils.cpp`, `codegen.cpp`, the lattices | 380 | T4, F7 (the edges' class) | compiler §4.8, §5.6 | `n29_membership_method`, `f7_membership_edges`, `n31_isa_narrows` |
| T7 | Final negatives: every set closed after load, a module's loaded mark, unmet intersections dropped at a final pair | `datatype.c` (`jl_membership_final*`, `jl_unmet_final_cells`, `type_declarers_loaded`), `gf.c` (`drop_unmet_matches`), `base/loading.jl`, `base/Base.jl`, `base/sysimg.jl` | 300 | T6 | compiler §4.8, §5.4 | `n18_closed_after_load`, `n20_unmet_lookup` |
| T8 | Memberships in package images: the list, activation in the methods' world before validation, refused conflicts, the member checks kept | `staticdata.c`, `datatype.c` (`jl_activate_memberships`, `activation_conflicts`), `gf.c` (`jl_member_checks_activated`) | 300 | T2, T5 | compiler §9 | `n3_image_memberships`, `n12_image_instances` |
| T9 | The library's hooks: definition, image, module end, expansion, deletion, the member hook (at dispatch and in the compile queue), strict mode's | `gf.c` (`jl_call_*_hook`, `call_library_hook`, `member_*`), `method.c` (`method_def`), `task.c`, `init.c` | 525 | T2 | compiler §10 | `n24_hook_compile_queue`; the library's suite |
| T10 | Declared results, fields, contracts and operations: `Method.declared_result`, lowering's record of `f(…)::RT`, a set's contract entries, a closed type's contract (`jl_declare_contract`), inference reads them | `method.c` (`declared_result_of`), `datatype.c` (`jl_set_contract_operations`, `jl_declare_contract`, `jl_set_declared_fields`), `abstractinterpretation.jl` (`declared_operation_result`, `declared_field_in`), `julia-syntax.scm` | 400 | T2 | compiler §4.1, §6.8, §7.1 | `n16_declared_result`, `n22_declared_assert`, `n23_contract_image` |
| T11 | The split over a set's candidates and the table of a call's targets | `Compiler/src/splittable.jl`, `base/splittable.jl`, `base/splittarget.jl`, `ssair/inlining.jl` (`split_*`, `handle_call!`, `ir_inline_unionsplit!`), `abstractinterpretation.jl` (`operation_split_type`), `datatype.c` (candidates), `gf.c` (`jl_split_table_ptr`) | 620 | T10, `up/16` (`:caller_world`) | compiler §7.2, §7.3 | `n19_io_trait` |
| T12 | `Callable{A, S}`: every function a member by one entry, the signature checked at the box, the result on return | `boot.jl`, `jltypes.c`, `base/Base.jl`, `abstractinterpretation.jl` (`callable_*`), `inlining.jl` (`handle_callable_call!`) | 110 | T2, T15 | compiler §7.4 | `n8_callable`, `n26_callable_late_method` |
| T13 | `IO`'s contract, `IOContext{IO}`, the display at `IOContext{IO}` | `base/iotrait.jl`, `base/show.jl`, `base/multimedia.jl`, `stdlib/REPL/src/REPL.jl` | 50 | T10, T11 | compiler §7.5; traits §9b | `n19_io_trait`; `test/show.jl`, REPL's suite |
| T14 | The kept forms `Dynamic{X}`, `Compiled{T}`; the forwarders made by the expansion hook; `TypeName.erases`; the despecialization that skips an argument at a set | `base/boot.jl`, `gf.c` (`is_trait_arg_type`, `jl_compilation_sig`), `method.c` (`method_def`) | 65 | T9 | compiler §6.2, §6.3, §6.9 | `n33_compiled_as_julia` |
| T15 | The `trusted` effect and its checks | `effects.jl`, `optimize.jl` (`IR_FLAGS_TRUSTED`), `inlining.jl` (`check_trusted_result!`), `boot.jl` (`_callable_result`) | 50 | T10, F1 (the `Effects` struct) | compiler §7.1, §7.4 | `n35_trusted_result` |
| T16 | A closed build (`--trim`): splits over the members by use, the build's rounds, the check in a session (`closed_check`), the verifier | `abstractinterpretation.jl` (`closed_*`), `typeinfer.jl` (`closed_note_used!`, rounds, `closed_check`), `verifytrim.jl`, `precompile.jl`, `inlining.jl` (`closed_set_signature`) | 880 | T11, T12, F4, F8, F11 | compiler §7.6 | `n34_closed_invoke_compiled`; `w166/build_c.sh` |
| T17 | The definition-time check's interpreter (`DefinitionCheckInterpreter`) and its bootstrap entries | `Compiler/src/types.jl`, `bootstrap.jl` | 85 | — (a library uses it) | compiler §6.7 | the library's suite |
| TX | The collectors' roots for the new structures; exports; `jl_static_show_func_sig`; header declarations | `gc-stock.c`, `gc-mmtk.c`, `jl_exported_*.inc`, `rtutils.c`, `julia_internal.h` | 260 | with each part above | — | `w163/sagc.sh` (0 findings) |

**Series T in all:** about 8,500 lines with TX and its share of the unassigned comments.

### 2.4 Shared parts and candidates for series G

| Part | Subject | Files | Lines | Kind |
|---|---|---|---|---|
| S1 | **The call's own signature in a dispatch edge and its backedge** where the call reached an instance wider than its match (a `@nospecialize` method; a call of `!==`, inferred at `(Any, Any)`): a method defined later invalidates the caller only where it replaces the matched method over the part of the call's signature it meets. Plain Julia gains: a caller at `Int` of `k(@nospecialize(x))` stays valid when `k(::String)` is defined | `Compiler/src/stmtinfo.jl` (`_add_edges_impl`, `CallSigBackedge`), `typeinfer.jl` (`ForwardToBackedgeIterator`, `store_backedges`), `gf.c` (`_invalidate_dispatch_backedges`), the image's backedges | about 80 | **general**: the inventory marks it facts (rows 79, 83, s3-8); it is useful without facts for a `Base.@nospecializeinfer` method only (a plain `@nospecialize` method is inferred at the call's types, and its backedge is precise already): `preserve_handle` 443 to 1. **Made: `up/19-callsig-backedge`.** It costs a plain load nothing measurable (641–655 against vanilla's 654–663 ms; E-534): the duplicate check of `store_backedges` walks the iterator as v1.13.2's. With `!==` declared `@nospecializeinfer` and its clause matching at the call's types, `!==` keeps one instance and a package's method of it ends 240 instances against 4,610: a candidate `up/20`; in the series it is in F7 |
| S2 | One compiled code per result (F12) without the policy clause | `typeinfer.jl` | 25 | **general, to check**: whether plain Julia compiles an instance twice where the first entry by ABI has no code (E-389 counted it on a build with two policies) |
| S3 | The module options word: `facts`, `bounded`, `no_pirates`, `owner_only`, `fully_typed` parsed by one `@compiler_options` change and stored in `jl_module_t.facts` and `.trait_options` | `base/experimental.jl`, `module.c`, `julia.h` | about 60 | shared: split per option (below, E2) |
| S4 | The `Effects` struct gains `nortsite` (facts) and `trusted` (traits) | `effects.jl` | about 30 | shared: two patches on one struct |
| S5 | The calling convention `:caller_world` | made: `up/16` | 188 | general; the split's table (T11) uses it |

## 3. The order and the dependency graph

```
G (18 patches, each alone) ─────────────────────────────────────────────── stand alone, reviewable first
S1 (call-signature backedges) ───────────────────────────────────────────── stands alone
F0 ─ F2 ─┐
F1 ──────┴─ F3 ─ F4 ─┬─ F5
                     ├─ F6
           S1 ─ F7 ──┴─ F8              F3 ─ F9 (ownership)     F7 ─ F10     F3 ─ F11     F4 ─ F12
T1 ─ T2 ─┬─ T3
         ├─ T4 ─ T5 ─ T8
         │    └─ T6 (with F7) ─ T7
         ├─ T9 ─ T14
         └─ T10 ─ T11 (with up/16) ─ T13
                  └─ T15 (with F1) ─ T12
T16 (a closed build) needs T11, T12, F4, F8, F11      T17 stands alone (a library uses it)
```

- **Reviewable first, standing alone:** the 18 patches of series G; S1; F1 (an effect bit nobody clears until F3); T17 (an interpreter nobody uses until a library does).
- **The smallest facts series** that reproduces E-392: F0, F2, F1, F3, F4, F5, S1, F7, F8, in that order. Then F9 (ownership), F10, F11, F12.
- **The smallest traits series** that gives sets and dispatch at them: T1, T2, T4, T5, T6 (needs F7's class only for its G2 clause; without facts the absence edge is an ordinary missing-method edge), T8, T9. Contracts and operations (T10, T11, T13, T15, T12) follow; the box and the wrapper (T14); a closed build (T16) last, on both series.

## 4. Where facts and the type system are entangled in the final tree

**The claim** ("the facts rule with ownership … changes nothing in the type system"). Against the diff: the facts parts touch no file of the type system's sets. `subtype.c`, `jltypes.c` (but for the field lists), `typemap.c` and `datatype.c` (but for one call site, E5) are changed only by series T. The facts runtime (`mi_policy`, `_jl_invoke`'s reach, the entries per policy) reads no set, membership or entry. **The claim holds for the type system. It does not hold for dispatch's bookkeeping:** S1 changes what a backedge records and when a definition invalidates; that change is general and goes first.

**The places where the two are entangled**, and what untangling needs:

| | Where | What | Untangling |
|---|---|---|---|
| E1 | `julia.h`: `jl_method_t` | One change adds traits' `declared_result` and `declared_covers` and facts' `facts` byte; fully typed mode's bits 4 and 8 sit in the facts byte | Three patches: F0 (`facts`, bits 0 to 1), F11 (bits 2 to 3), T10 (`declared_result`, `declared_covers`) |
| E2 | `module.c`, `facts.jl` (`is_owner_only`): owner-only by the module | The module's `owner_only` option is bit 64 of `trait_options`, the word of the trait language's scope options (`bounded`, `no_pirates`, `fully_typed`); `is_owner_only` calls `jl_get_module_trait_options` | A field or a neutrally named options word that F9 adds; `bounded` and `no_pirates` come with T9 |
| E3 | `facts.jl` (`is_owner_only`), `julia.h` (`BINDING_FLAG_OPEN_OPERATION`) | A trait's operation is not owner-only by its module's default | F9 without the open-operation flag; T10 adds the flag and the one line in `is_owner_only` |
| E4 | `facts.jl` (`edges_satisfy_g2`, `name_callee_code`, `is_membership_mi`, `is_absence_sig`) | The deep class admits a membership's method and an absence edge (`Core.implements`) | F7 without the two clauses; T6 adds them. Without sets no such edge exists, so the facts series' class is the same |
| E5 | `datatype.c` (`jl_declare_membership`, `jl_memberships_activated`), `gf.c` (`deep_ending_*`) | The deep-endings list has the kind `:membership`, pushed from the membership code | F10 with `:definition`, `:deletion`, `:validation`; T5 or T8 adds `:membership` and its call sites |
| E6 | `facts.jl` (`rtsite_target`) | "Specializes on none" requires that the argument is no trait argument (`is_trait_arg_type`) | F8 without the clause; T14 adds it |
| E7 | `gf.c` (`jl_lookup_generic_`, `apply_generic_reach`) | One function changed by four subjects: the reach per policy (F4), the member hook at a miss (T9), the dispatch profiler and the wildcard entries (G, made) | Textually separate hunks; the order G, F4, T9 applies cleanly, but with `up/15` and F4 both applied the profiler's call site must become `apply_generic_reach`'s `ip` (`dp_ip = ip`): done in `w19-g-facts` |
| E8 | `Compiler/src/types.jl` (`NativeInterpreter`) | The fields `facts` (F3) and `closed` (T16), and `DefinitionCheckInterpreter` (T17), in one struct's change | One field per part |
| E9 | `effects.jl` | `nortsite` (F1) and `trusted` (T15) in one `Effects` change (S4) | Two patches on one struct, F1 first |
| E10 | `staticdata.c` | The image writes the modules' facts flags and trimmed-image marks (F8) beside the indices of sets, the candidates and the contracts (T8) | Separate hunks in the same writer; F8 first |
| E11 | Fully typed mode (F11) and a closed build (T16) | The mode's fault is the facts inference's run-time site; its check (`closed_check`) is the closed build's own code run in a session | F11 states the fault without `closed_check`; T16 adds the check and the mode's hook reads it |
| E12 | `abstractinterpretation.jl` (`abstract_call_gf_by_type`) | The facts inference's matching and the sets' record of memberships and the closed build's splits in one function | Separable by hunk; F3 first, then T6, then T16 |
| E13 | `base/runtime_internals.jl` | The flags masks widened to 32 bits for `has_open_set` | With T1; nothing of facts |
| E14 | `gf.c` (`jl_method_policy`, `mi_policy_uncached`, `mi_policy_facts_at`), `method.c`, `adjust_effects` | The test bed's and the fully typed mode's clauses (F6, F11) sit inside the functions of F2 and F4 | Each clause is one condition; it comes with its part |
| E15 | `gf.c` (`jl_type_infer`, `jl_call_in_typeinf_world`) | The membership query world and the member queue's drain (T2, T9) inside F4's function | Added by the traits parts |
| E16 | `Compiler/src` (`merge_override_effects!`, `adjust_cycle_frame!`) | `IR_FLAGS_TRUSTED` (T15) in the lines of F1 and F3 | Added by T15 |
| E17 | `staticdata.c` (`queue_external_cis`) | `up/17`'s check and the `JULIA_DEBUG_EXTERNAL_CIS` counters in F8's loop | The order G, F8 |

So a facts-only series exists. Untangling is mechanical (E1 to E13): no part of facts calls code of the sets, and every place where facts reads a trait concept is a clause that only answers differently when a set exists.

## 5. What does not go upstream as it is

Each with the question a core developer would ask.

- **Names.**
  - `Core.Dynamic{X}`, `Core.Compiled{T}`: why in `Core`, and why these names for a box and a wrapper? Base would want them in a module of the trait language, or names that say what they hold.
  - `Core.Callable{A, S}`: a set of `Core` whose members are declared by one entry in `base/Base.jl` (`Function`), with two inputs opened by the runtime at Core's build. Is a function type set the language's (with a syntax) or a library's?
  - `Core.All{T<:Tuple}`: an intersection type as an abstract type with one tuple parameter, printed `All{X, Y}`. Why not a kind of its own, as `Union` is?
  - `Core.implements`: a function whose methods are memberships, defined by the runtime, refused to programs; tools that list ambiguities see its methods ([open issue 180](../open-issues.md) (d)).
  - `jl_set_module_trait_option`, `trait_options`, `facts` as a module field name: a core developer would ask for names that say what each option does.
- **Hooks whose shape is the library's.** The definition hook (twice per method, may refuse), the image hook (methods left inactive), the module-end hook, the expansion hook (one definition makes (argdata, code) pairs), the member hook (called at dispatch and in the compile queue), the fully typed hook, the deletion hook. Seven entry points for one library. Question: which are language semantics (the member check, the expansion), which a tool's (strict mode's reports)? Proposal: the language part as rules in the runtime, one notification interface for tools.
- **The test bed** (`JULIA_COMPILE_BY_FACTS=1`): an environment variable that changes what every neutral method compiles to. A core developer would ask for a command-line option (compiler §2.5 plans `--compile-by-facts=all`) or its removal.
- **The deep endings list and the strict-mode hooks** (`jl_set_deep_endings`, `jl_take_deep_endings`, `jl_set_strict_memberships`, `jl_take_activation_ambiguities`): state the runtime keeps for one library's report. Question: a general invalidation log (Julia has `jl_debug_method_invalidation`) with a kind and a cause, in place of a second list.
- **What nothing reads** (compiler C-88 (d)): the bit `closed_after_load` (set for every set), the modules' loaded marks' use by `type_declarers_loaded`, the switch `jl_set_membership_walk_invalidates`. Removed before upstream.
- **`Method.declared_covers`**: kept with no reader (inventory row 133). Removed.
- **The closed build's report** (`JULIA_CLOSED_BUILD_REPORT`) and `JULIA_DEBUG_EXTERNAL_CIS`: debugging switches. A core developer would ask for them behind a debug build or removed.
- **The closed build's rules inside inference** (T16, 880 lines in `abstractinterpretation.jl` and `typeinfer.jl`): a second inference mode with rounds, members by use and splits. Question: an `AbstractInterpreter` of its own, as `juliac`'s driver could own, instead of `closed_build(interp)` tests in Julia's interpreter.
- **The display at `IOContext{IO}`** (T13: `REPL.show_limited`, `TextDisplay`): changes what type every `show` method sees at the REPL. Question: what plain packages' `show` methods that dispatch on the stream's type do then (a method at `IOContext{Base.TTY}`).
- **`DataType.flags` widened to 32 bits** (T1): every DataType gets a word; Base's masks change. Question: the cost in memory, and whether a bit on `TypeName` serves.
- **Lowering's record of `f(…)::RT` as a declared result** (T10): a method's return annotation becomes something inference trusts at a set. Question: what it means for plain methods with a return annotation (none: it is read only at a set), stated in the patch.
- **Rewrites of `test/precompile.jl`** (`(be.def::Core.MethodInstance).def::Method`): follows neither S1 nor F7 (`precompile` passes on both without it): a traits change by the two series alone, but needed on the two built together (`w19-g-facts`: the test's line 977 runs there; which part makes it run is not found); it goes with that part, with the reason.

## 6. How to continue

1. Series G: review the 18 branches (`README.md`), then S1, made as `up/19` (its test in `test/worlds.jl`, with `Base.@nospecializeinfer`).
2. Series F: F0 to F12 are made on v1.13.2, F4 in three, and built with series G (`w19-g-facts`; E-534). Left: the tests of F9 to F12 moved from the experiments' gates into Julia's `test/`; `precompile` run on the facts head; F4a and F4b built alone.
3. Series T: on F, in the order of §3.
