# The deviations' ledger: retired rows

Moved here by the documentation clean-up of 2026-11-18 (W-162). Every row is unchanged, in its table's order.

- **The open rows** are in each reference's Deviations table: [traits](../../../writeup/reference/traits.md#19-deviations), [facts](../../../writeup/reference/facts.md#16-deviations), [compiler](../../../writeup/reference/compiler.md#deviations), [lowering](../../../writeup/reference/lowering.md#15-deviations).
- **IDs are permanent.** A row that is retired later is added here, under its reference, with what holds its subject now.
- **A retired row tells no story of what it was:** it names the section that holds its subject. How each was fixed is in the build notes (`writeup/record/build-notes/`) and the decision log.
- **Links** are those of the rows' old place, `writeup/reference/<the reference>.md` ([the rule for paths](../../README.md#the-rule-for-paths)).

## Traits (T-)

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 to T-95 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/traits.md` | — | — |
| T-97 | — | *Retired* (2026-11-14): the warning at an extension's method, at its definition and at its image's load ([§12.3](#123-strict-mode)); stack gate `strict_extension_method` | — | — |
| T-98 | — | *Retired* (2026-11-10): under strict mode an ambiguity at an image's membership activated at load is reported after the load, at error level, in TraitWorld 0aff625 with `unified` 9f8d7d7c48 ([§12.3](#123-strict-mode), [compiler §9](compiler.md#9-images-and-the-machine-code-cache)); gate `stack/strict_activation.jl` (E-349) | — | — |
| T-102 | — | *Retired* (2026-11-14): `like` and `withfields` call the constructor by position, with nothing looked up when they run ([lowering §8](lowering.md#8-like-and-withfields)); `test/core.jl`, stack gate `like_precompiled` | — | — |
| T-103 | — | *Retired* (2026-11-08): `HasProperty` in TraitWorld `unified` a658203 with `unified` 350c5b1c59 ([§10.1](#101-basetraits), [§3.2](#32-parameters)); tests `basetraits.jl`, gate `n10_inputs` | — | — |
| T-106 | — | *Retired* (2026-11-09): `IO`'s contract is Base's, on a closed type ([§9b](#9b-streams-io)) | — | — |
| T-107 | — | *Retired* (2026-11-14): the report's holes are the build's own check's ([§16](#16-compiling-ahead-closed-programs)); what is left is in T-109 | — | — |
| T-110 | — | *Retired* (2026-11-12): [§14](#14-concreteness-and-fully-typed-mode) holds the rule, built. | | |
| T-111 | — | *Retired* (2026-11-14): `detect_kept_storage` reports such stores ([§7.8](#78-keeping-an-argument-with-its-attribute)); test `kept.jl`. TraitDifferentialEquations' six sites are the port's (W-104) | — | — |
| T-113 | — | *Retired* (2026-11-15): [§4.6](#46-erasing-by-default) and [§7.8](#78-erasing-by-default-the-forwarder) state what the library records; what stands in for Julia's forwarders is T-125 | — | — |
| T-114 | — | *Retired* (2026-11-15): [§7.3](#73-bounded-methods) and [§11.2](#112-definition-checking) state what the library reads; how it infers that instance: [compiler C-115](compiler.md#deviations) | — | — |
| T-120 | — | *Retired* (2026-11-15): an operation without a default is an entry of the contract and no method at the trait, in TraitWorld `unified` c838f76 with julia `next` 5448a8b7bf ([§4.1](#41-operations), [§11.4](#114-hints)); E-498 | — | — |
| T-121 | — | *Retired* (2026-11-15): a method of another package's owner-only function is a pirate's, and `@owner_only`, in TraitWorld `s3` 4210852, 4f34916 ([§12.2](#122-pirates)); `test/owner_only.jl`, E-458 | — | — |
| T-123 | — | *Retired* (2026-11-15): the report by default, in TraitWorld `s3` 2770c10 ([§12.2](#122-pirates)); `test/report.jl`, E-457 | — | — |
| T-124 | — | *Retired* (2026-11-15): `delete_membership` in TraitWorld `s3` 9e0e3f4 with `next-s3` 213c759370 ([§5.13](#513-taking-a-membership-back)); `test/delete.jl`, E-459; Revise's part is lowering L-64 | — | — |
| T-126 | — | *Retired* (2026-11-18): the library's exported `compiled_for` is the wrapper's function ([§7.6](#76-compiled_forx)), TraitWorld `unified` ea72682 (W-156; E-505); that the wrapper's type is the library's and not `Core`'s is compiler C-113 | — | — |
| T-127 | — | *Retired* (2026-11-18): the library offers no cast, `keep`, `Kept`, `kept_call`, `isdynamic`, `detect_` function or `@default_compiled`; `@trait_module` takes `facts`, `bounded`, `no_pirates`, `owner_only` and refuses `dynamic` and `first_seen` ([§7.5](#75-what-decides), [§13](#13-scopes-trait-modules)); `verify_main` and `fully_typed` read wrappers ([§14](#14-concreteness-and-fully-typed-mode), [§16](#16-compiling-ahead-closed-programs)); TraitWorld `unified` ea72682 (W-156; E-505). What Julia still carries is compiler C-112; the closed build at the wrapper of a value known only by its trait is compiler C-114 | — | — |
| T-128 | — | *Retired* (2026-11-18): the demonstrators erase by the trait's default or at a door and choose code per type with the wrapper ([§7.4](#74-the-two-kept-forms-the-box-and-the-wrapper) to [§7.8](#78-erasing-by-default-the-forwarder), [§8](#8-storage)): TraitTables 3f3e5a9, TraitCSV 57ccb3c, TraitReport a41c595, TraitMakie 4ef82e1, the forks 2176f57, TraitDifferentialEquations a4bc47d (W-156; E-504). What is left is the library's: the module option the ports write (T-127) and the wrapper's function bound by name (T-126) | — | — |
| T-130 | — | *Retired* (2026-11-18): a function of `Self` that an equation names answers through a kept form as for its object ([§7.3](#73-bounded-methods), [§7.4](#74-the-two-kept-forms-the-box-and-the-wrapper)); TraitWorld `unified` a8d11af (W-166; E-507); `test/bytype.jl` | — | — |

## The facts mode (F-)

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| F-1 to F-23 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/facts.md` | — | — |
| F-25 | [§11.2](#112-strict-mode) | *Retired:* built (TraitWorld `unified` bb4ad00, with `next` 7063158f42); the walk by the deep class is §11.2's | — | — |

## Compiler and runtime (C-)

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-1 to C-17 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/compiler.md` | — | — |
| C-18 | — | *Retired*: a membership's invalidation is [§5.5](#55-a-membership-invalidates-as-a-method-does) | — | — |
| C-19 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.10](#410-type-values)); gate `m1_typevalue_isa` | — | — |
| C-20 | — | *Retired* (2026-11-06): `Core` has no wrappers and no `Keyed` on `unified` 62016706d0; `Dynamic{X}` is W-106's struct ([traits §7.7](traits.md#77-dynamicx)); gate `m1_no_wrappers` | — | — |
| C-21 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.2](#42-memberships)); gate `m1_audit_probes` (P3) | — | — |
| C-22 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.4](#44-transitivity)); gates `m2_set_in_set`, `m1_audit_probes` (P4, P7) | — | — |
| C-23 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.4](#44-transitivity)); gate `m1_audit_probes` (P5) | — | — |
| C-24 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.1](#41-sets)); gate `m1_audit_probes` (P6) | — | — |
| C-25 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.3](#43-worlds)); gate `m1_audit_probes` | — | — |
| C-26 | — | *Retired* (2026-11-06): fixed on `unified` 62016706d0 ([§4.5](#45-subtyping)); gates `m1_audit_probes` (P8), `m1_parametric_set` | — | — |
| C-27 | — | *Retired* (2026-11-09): a pattern is checked against the entries at the set and at the sets that join it, on `unified` edc2653e43 ([§4.6](#46-one-instance-per-member)); gate `n10_inputs`; E-321 | — | — |
| C-28 | — | *Retired* (2026-11-06): the query world is the task's, restored by exception handlers, on `unified` 48864e547d ([§4.11](#411-inferences-world)); gate `m2_query_world_task` | — | — |
| C-29 | — | *Retired* (2026-11-09): a pattern member is asked at the call types both methods reach, and the warning names the joint signature, on `unified` 264b7f959f ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `m2_ambiguity_arity`; E-320 | — | — |
| C-32 | — | *Retired* (2026-11-08): a set's inputs on `unified` 350c5b1c59 ([§4.6](#46-one-instance-per-member)); gate `n10_inputs` | — | — |
| C-33 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.7](#47-three-layers), [§5.3](#53-match-world-ranges-and-abstract-queries)); gate `n2_open_abstract` | — | — |
| C-34 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.9](#49-intersections)); gate `n2_all_form` | — | — |
| C-35 | — | *Retired* (2026-11-08): an image's membership that would give its member a second instance of a set is refused at activation, with a warning, on `unified` 07c0bee2a2 ([§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances`; E-296 | — | — |
| C-36 | — | *Retired* (2026-11-09): lowering records `f(…)::RT` on `unified` 0ba6317994 ([§6.8](#68-a-declared-result-on-method)); gate `n16_declared_result` | — | — |
| C-37 | — | *Retired* (2026-11-07): the split's last branch calls through the table on `unified` e70675a606 ([§7.3](#73-the-table-of-a-calls-targets)); TraitWorld test `table` | — | — |
| C-40 | — | *Retired* (2026-11-15): the check reads the instance at the box ([§6.7](#67-the-definition-time-check)); what is built of it, and the check interpreter still in Julia: C-115 | — | — |
| C-41 | — | *Retired* (2026-11-15): the instance at the box is kept with its edges as code ([§6.7](#67-the-definition-time-check)); what is built: C-115 | — | — |
| C-42 | — | *Retired* (2026-11-07): code of both policies under Julia's own owner on `unified` 10c7e1c2cf ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy)); gate `f3_policy_code` | — | — |
| C-43 | — | *Retired* (2026-11-07): lowering carries the policy meta into every method a definition makes, on `unified` cb7f55bd35 ([§2.2](#22-the-method-flag)); gate `f2_policy_flags` | — | — |
| C-44 | — | *Retired* (2026-11-07): the policy of the code that reaches a method on `unified` c44a447f2c ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy), [§2.4](#24-calls-between-policies)); gate `f6_reach_policy` | — | — |
| C-46 | — | *Retired* (2026-11-08): the bit requires each inlined callee's own record to satisfy G2, the callees found from the debug info, on `unified` 1d493ca959 ([§3.2](#32-g2-as-a-predicate)); gates `f4_g2_bit`, `m3_g2_bit`, `m3_g2_counts`; E-297 | — | — |
| C-48 | — | *Retired* (2026-11-07): the test bed starts and runs on `unified` c44a447f2c ([§2.5](#25-the-test-bed)); E-275, gate `f6_reach_policy` | — | — |
| C-53 | — | *Retired* (2026-11-10): a trimmed image marks every module as never compiled by facts, `unified` bb2031f820 ([§2.6](#26---trim); E-361) | — | — |
| C-54 | — | *Retired* (2026-11-12): [§6.2](#62-compilation-signatures) holds the rule, built. | | |
| C-55 | — | *Retired* (2026-11-15): no type is exempt from a trait's default ([traits §7.8](traits.md#78-erasing-by-default-the-forwarder)); what Julia still carries of the attribute: C-112 | — | — |
| C-56 | — | *Retired* (2026-11-15): there is no `keep` ([§6.9](#69-the-kept-forms-in-core)); what Julia still carries of it: C-112 | — | — |
| C-57 | — | *Retired* (2026-11-10): a call's dispatch fact at its own signature, for G2 too, on `unified` 0ee9e4f8a6 ([§6.3](#63-the-attribute-at-a-call), [§3.2](#32-g2-as-a-predicate)); gate `n21_callsig_backedge` | — | — |
| C-58 | — | *Retired*: no call carries a guard ([§5.5](#55-a-membership-invalidates-as-a-method-does)) | — | — |
| C-59 | — | *Retired*: no call carries a guard ([§5.5](#55-a-membership-invalidates-as-a-method-does)) | — | — |
| C-60 | — | *Retired* (2026-11-08): a call of a value known as `Callable{A, S}` checks its arguments against `A` where inference cannot prove them, and raises `MethodError` where it proves them outside, on `unified` 1d493ca959 and c248dbfd8c ([§7.4](#74-callables-call)); gate `n14_callable_args`; E-297 | — | — |
| C-61 | — | *Retired* (2026-11-15): a box's call dispatches when it runs, as Julia's dynamic call does ([§7.4](#74-callables-call)) | — | — |
| C-62 | — | *Retired* (2026-11-15): `Callable`'s positives fold through entries as any set's ([§7.4](#74-callables-call)) | — | — |
| C-63 | — | *Retired* (2026-11-09): a match through `Callable` is bounded by the member's methods' worlds at the positions where the signature names it, on `unified` c8ef0e581e, 1daebeab81, 23022b0ec7 ([§7.4](#74-callables-call), [§5.3](#53-match-world-ranges-and-abstract-queries)); gate `n8_callable`; E-324 | — | — |
| C-64 | — | *Retired* (2026-11-15): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)); removed from the build on `next` 9b6dacf5c5 (C-93) | — | — |
| C-65 | — | *Retired* (2026-11-15): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)); removed from the build on `next` 9b6dacf5c5 (C-93) | — | — |
| C-66 | — | *Retired* (2026-11-15): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)); removed from the build on `next` 9b6dacf5c5 (C-93) | — | — |
| C-67 | — | *Retired* (2026-11-15): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)); removed from the build on `next` 9b6dacf5c5 (C-93) | — | — |
| C-68 | — | *Retired* (2026-11-08): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)) | — | — |
| C-69 | — | *Retired* (2026-11-15): no code slot in the design ([§3.3](#33-one-compiled-code-per-result)); removed from the build on `next` 9b6dacf5c5 (C-93) | — | — |
| C-70 | — | *Retired* (2026-11-09): a kind meets a set that takes a type value, on `unified` f14be868df, 0c9e44cb3d ([§4.10](#410-type-values)); gate `m1_typevalue_isa`; E-321 | — | — |
| C-71 | — | *Retired* (2026-11-08): a member that fails its check at dispatch lowers the cache entries made for it while the check ran, on `unified` 07c0bee2a2 ([§10.4](#104-the-member-hook)); TraitWorld's test F10b; E-296 | — | — |
| C-72 | — | *Retired* (2026-11-08): the walk visits the replayed method's own function and substitutes the member at a parametric set, on `unified` aa997b2180 ([§5.5](#55-a-membership-invalidates-as-a-method-does)); gate `m2_parametric_replay`; E-292 | — | — |
| C-73 | — | *Retired*: a method at a set defined later is [§5.5](#55-a-membership-invalidates-as-a-method-does); gate `n11_late_shadow` | — | — |
| C-74 | — | *Retired* (2026-11-09): code a compile queue infers anew is inferred under its method's policy on `unified` dde5f9f5dc ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy)); gate `n15_image_policy`, E-311 | — | — |
| C-75 | — | *Retired* (2026-11-09): the edge instance made for a constant-propagated result carries the G2 bit, on `unified` 427760d9e9 ([§3.2](#32-g2-as-a-predicate)); gate `f4_g2_bit`; E-320 | — | — |
| C-76 | — | *Retired*: a negative folds wherever the code is compiled ([§4.8](#48-negatives-fold-with-an-edge-positives-through-entries)) | — | — |
| C-78 | — | *Retired* (2026-11-10): the report asks each method the membership makes applicable against the method table at the member, on `unified` 53d28eea68 ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `m2_ambiguity_declared_super` (E-347) | — | — |
| C-80 | — | *Retired* (2026-11-09): `IO` a closed abstract type with a contract, on `unified` b05ae361e0 ([§7.5](#75-io)) | — | — |
| C-81 | — | *Retired* (2026-11-10): a closed type's candidates in its contract, kept by its image, on `unified` 18bbbf0841 ([§7.1](#71-the-rule), [§7.2](#72-the-split)); gate `n23_contract_image` | — | — |
| C-82 | — | *Retired* (2026-11-10): dispatch's lookup keeps an unmet match at an open set and drops it at a final pair with its absence edges, `Callable` and a `Vararg` tail met, on `unified` 999777ab77 ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `n20_unmet_lookup` | — | — |
| C-83 | — | *Retired* (2026-11-10): every entry an image activates is in its set's index, also one on the image's own type, on `unified` e42047dba2 ([§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances` | — | — |
| C-84 | — | *Retired* (2026-11-10): a membership activated from an image ends an older entry in force for the same member, set and inputs, on `unified` 9f8d7d7c48 ([§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances` (E-348) | — | — |
| C-85 | — | *Retired* (2026-11-10): an abstract member by its definition (`abstract type A <: X end`) has its `@implement`'s entry, so the member hook runs for its subtypes (it runs where an argument's chain carries an entry), TraitWorld e8554d9 ([§10.4](#104-the-member-hook)); TraitWorld test `declared.jl`, gate `stack/recheck_packages.jl` case 7 | — | — |
| C-89 | — | *Retired* (2026-11-12): the membership's method and the edges are [§5.6](#56-the-memberships-method-and-the-edges), with [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) and [§9](#9-images-and-the-machine-code-cache) | — | — |
| C-90 | — | *Retired* (2026-11-15): a box checks every call, however it is called; a wrapper is the function ([§7.4](#74-callables-call)) | — | — |
| C-91 | — | *Retired* (2026-11-15): the G2 bit marks the deep class, on `next` 7063158f42 ([§3.2](#32-g2-as-a-predicate), [§9](#9-images-and-the-machine-code-cache)); gate `experiments/unification/w155/gate_deep.jl`; E-417 | — | — |
| C-92 | — | *Retired* (2026-11-15): the design has no rule of its own for a call that only throws; the question is [open issue 194](../open-issues.md#2-design) | — | — |
| C-93 | — | *Retired* (2026-11-15): no code slot, on `next` 9b6dacf5c5 ([§3.3](#33-one-compiled-code-per-result)); E-419 | — | — |
| C-100 | — | *Retired* (2026-11-15): inference reads an operation's declared result from the entries of the set's contract, `jl_set_contract_operations` (`next` 5448a8b7bf; [§4.1](#41-sets), [§7.1](#71-the-rule)); E-498 | — | — |
| C-101 | — | *Retired* (2026-11-15): a call of an owner-only function is a fact at any signature, on `next-s3` e483299622 ([§1.2](#12-fact-signatures)); E-458; what is left of it is C-130 | — | — |
| C-104 | — | *Retired* (2026-11-15): inside an invariant parameter no membership entry is consulted, on `next-s3` e967266d9e ([§4.5](#45-subtyping), [§4.9](#49-intersections)); gate `experiments/unification/w155b/gate_d11.jl`; E-456 | — | — |
| C-105 | — | *Retired* (2026-11-15): the runtime keeps what a definition ended of the deep class, on `next-s3` 5d2ec7ff85 ([§10.2](#102-hooks-for-strict-mode)); E-457 | — | — |
| C-106 | — | *Retired* (2026-11-15): a membership taken back, on `next-s3` 213c759370 (`jl_delete_membership`, `jl_membership_removal_walk`; [§4.3](#43-worlds), [§5.5](#55-a-membership-invalidates-as-a-method-does), [§5.6](#56-the-memberships-method-and-the-edges), [§9](#9-images-and-the-machine-code-cache)); E-459 | — | — |
| C-110 | — | *Retired* (2026-11-15): [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) is built for `new`, a store and a `typeassert` (`next` 5b1900641f, W-160); `isa` and `<:` are inference's folds | — | — |
| C-112 | — | *Retired* (2026-11-18): no attribute is resolved at a call; the casts, `Core.attributed_call`, `Core.keep`, the attribute's bits and the module options `dynamic` and `first_seen` are gone ([§2.1](#21-the-module-option), [§6.2](#62-how-an-argument-is-compiled), [§6.9](#69-the-kept-forms-in-core), [§7.6](#76-a-closed-build)); `next` 1ded4d77e7, 17a260206c, a9e2a0addd with TraitWorld `unified` a2bf677 (W-156; E-506); gates `n33_compiled_as_julia`, `f2_policy_flags` | — | — |
| C-113 | — | *Retired* (2026-11-18): `Core.Compiled{T}` beside `Core.Dynamic{X}`, the box made by `new` with no conversion ([§6.9](#69-the-kept-forms-in-core)); `next` 4bf381040c with TraitWorld `unified` 6ad7098 (W-156; E-506); gates `n33_compiled_as_julia`, `m1_no_wrappers` | — | — |
| C-114 | — | *Retired* (2026-11-18): a closed build branches over the members at a call whose static parameter a value known only by its trait binds, and runs the instance at the call's types for any other call at such a value ([§7.6](#76-a-closed-build)); `next` dc760be0b2 (W-156; E-506); TraitWorld `test/verify.jl`; what is short: C-150 | — | — |
| C-116 | — | *Retired* (2026-11-15): `Callable`'s members are entries, subtyping reads no method, the signature is checked at the box and at a wrapper's entry ([§7.4](#74-callables-call)); built on `next` eaa19da272 and TraitWorld `unified` c14d2e4 (W-161); what is short: C-146 | — | — |
| C-147 | — | *Retired* (2026-11-18): two instances of a set that may differ in an input meet as `All{X{A}, X{B}}`, and two methods at them tie ([§4.9](#49-intersections), [§7.4](#74-callables-call)); built on `next` 7397ab6f70 and 02139b2168 (W-165); gates `n8_callable`, `n10_inputs`; E-503; what is short: C-149 | — | — |
| C-148 | — | *Retired* (2026-11-18): `Callable` is closed after load as every set, and a set written with free parameters is asked as the set, so the lookup drops the match and its ambiguity ([§4.8](#48-negatives-fold-with-an-edge-positives-through-entries)); built on `next` a29ffdd428 (W-165); gate `n20_unmet_lookup` (5); E-503 | — | — |
| C-150 | — | *Retired* (2026-11-18): a call that takes the wrapper of a value known only by its trait branches over the members ([§7.6](#76-a-closed-build)); `next` f5328f94c5 (`closed_wrapper_set`, `closed_member_split` with its bound) with TraitWorld `unified` 9d4f782 (W-166; E-508). The table program builds under `--trim=safe` with 0 errors and runs; TraitWorld `test/verify.jl`, "verify_main: the wrappers of five members". What stops the other programs' builds is open issue 243 | — | — |

## Lowering (L-)

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-1 to L-50 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/lowering.md` | — | — |
| L-51 | — | *Retired* (2026-11-07): `Dynamic{X}` is `Core.Dynamic` on `unified` e692e57ab7 ([§7](#7-dynamicx-keep-casts)); gate `n6_attribute` | — | — |
| L-52 | — | *Retired* (2026-11-10): the use raises at dispatch and in compiled code ([§3](#3-implement); TraitWorld 0aff625, 048c44e with `unified` fcdfd0da36; `test/declared.jl`, E-350, E-352). What remains is the hook's: [compiler C-31](compiler.md#deviations) | — | — |
| L-53 | — | *Retired* (2026-11-07): built in TraitWorld `unified` dd72b10 ([§3](#3-implement)); test `Union-bounded family` | — | — |
| L-54 | — | *Retired* (2026-11-15): [§2](#2-trait) states the library's forwarding call; `Core.trait_receiver` is an optional extension ([extensions §1.4](extensions.md#14-the-calling-convention)) | — | — |
| L-55 | — | *Retired*: what an image keeps is [§11](#11-checks-errors-and-what-images-keep); gate `experiments/unification/l55/kept_checks.jl` | — | — |
| L-56 | — | *Retired* (2026-11-15): there are no casts ([§7](#7-dynamicx-and-compiledt)); what Julia still carries of them: [compiler C-112](compiler.md#deviations) | — | — |
| L-57 | — | *Retired* (2026-11-14): the error names the constructor to define ([§8](#8-like-and-withfields)); `test/core.jl` | — | — |
| L-59 | — | *Retired* (2026-11-15): [§2](#2-trait) declares the wrapper's family, as the library does; the erasing bit is L-65 | — | — |
| L-63 | — | *Retired* (2026-11-15): `@trait` writes the operations as entries (`jl_set_contract_operations`), a method at the trait only for a default, and the kept forms' forwarding methods, in TraitWorld `unified` c838f76 ([§2](#2-trait)); E-498 | — | — |
| L-65 | — | *Retired* (2026-11-15): §2's mark `Expr(:meta, :no_forwarder)` and the contract's record of the default, read where a method is defined by the library's expansion hook, are built (TraitWorld `unified` 21ae901, julia `next` 8b1ec88a56; W-160); `@default_compiled` is [traits T-127](traits.md#19-deviations)'s | — | — |
| L-68 | — | *Retired* (2026-11-15): the box's constructor tests `hasmethod(f, A)`, and `@implement Callable T` declares a callable type ([§9](#9-callable)); built in TraitWorld `unified` c14d2e4 (W-161), the ports' guard pairs gone (E-500) | — | — |
| L-67 | — | *Retired* (2026-11-18): `@trait` defines one method of each equation's function at each kept form's type ([§2](#2-trait)); TraitWorld `unified` a8d11af (W-166; E-507) | — | — |
