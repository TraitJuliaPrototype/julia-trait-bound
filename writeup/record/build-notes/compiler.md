# Build notes: compiler

This page is in the agents' tier ([the record's index](../INDEX.md)).
It holds what the pass of 2026-11-18 over [the compiler reference](../../reference/compiler.md) took out of it: where each rule is in the code, the commits that built it, its gates, who decided it, its experiments.
The reference is the source of truth for the rule; this page is its build log, by section, in the reference's order.

### The top of the page

- **Taken from the page's text:** **Adopted** (the user, 2026-11-06; W-105; [the folder's README](../../reference/README.md)).
- **Taken from the page's text:** It describes the interfaces as designed.
- **Taken from the page's text:** The status line of each section says how far it is built.
- **Taken from the page's text:** The build is branch `unified` of the julia repository, on v1.13.2 (the worktree `julia-unified/`), in the stages W-98 to W-114 ([the work plan](../../../attic/writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md), adopted) and the work items after them, W-101, W-123, W-128 and W-129 ([the work queue](../todo.md)).
- **Taken from the page's text:** The inventory of its changes: [`../design/julia-changes.md`](../../design/julia-changes.md).

### §1.1 The policy and the interpreter

- **The status line as it stood:** The interpreter's mode implemented on `unified` 28fe27b2f7 (W-100); an inference of a method instance for its code run under its method's policy, both policies under Julia's own owner, 10c7e1c2cf.

### §1.2 Fact signatures

- **The status line as it stood:** Implemented on `unified` 28fe27b2f7 (W-100), from `trait-world-1.13`'s `facts.jl`. Owner-only functions: `next-s3` e483299622 (D-9, 2026-11-15; E-458), but for a later `public` or `export`, which ends nothing (C-130); `is_owner_only`, the flag on the binding, the scope option and the binding edge for a later `public` are mine (2026-11-15).

### §1.3 Run-time sites

- **The status line as it stood:** Implemented on `unified` 28fe27b2f7 (W-100); the split's fallback (§7.2) marks one under the facts mode with W-100's policy.

### §1.4 `return_type`

- **The status line as it stood:** Implemented on `unified` b87d863b9e (W-100) for steps 1 and 3 and the run-time answer (`PlainRTInterp` is `NativeInterpreter(; plainrt = true)`, owner `:plain_rt`); step 2: C-47. Optional: revalidating cached answers after loads ([PE-5](../performance-explorations.md)).

### §1.5 Effects

- **The status line as it stood:** Implemented on `unified` 28fe27b2f7 (W-100).

### §2.1 The module option

- **The status line as it stood:** The module option implemented on `unified` beafa01b36 (W-100): `facts` and the trait options, set by `Base.Experimental.@compiler_options`, inherited by submodules, saved with the module; their consumers: §2.3 (W-100) and W-109, W-111, W-114. The options `dynamic` and `first_seen` are still built: C-112.

### §2.2 The method flag

- **The status line as it stood:** The method flag implemented on `unified` beafa01b36 (W-100), carried into every method a definition makes cb7f55bd35 (gate `f2_policy_flags`). The boundary flag as the second policy per method: implemented on `unified` c44a447f2c (W-100; §2.3); gate `f6_reach_policy`. Which of Base's methods carry it: none, in the product setting (mine, 2026-11-07): facts code rests on plain code of Base whose own records satisfy G2 (E-279, [evidence](../../design/evidence.md#4c-the-unifications-trade-offs-measured-on-todays-build)).

### §2.3 One CodeInstance per MethodInstance and policy

- **The status line as it stood:** Implemented on `unified` 10c7e1c2cf and c44a447f2c (W-100): the policy bit in a CodeInstance's flags, set from the policy it is compiled in and kept in images; the lookups of Julia's own owner take only a CodeInstance of the policy wanted; the policy of the code that reaches a method, through inference and the engine's reservations; gate `f6_reach_policy`. Code inferred anew by the image's queue and the JIT's under its own policy: `unified` dde5f9f5dc, gate `n15_image_policy`. With C-49. Under `--trim`: Planned.
- **Taken from the section's text:** **Code inferred anew by a queue that compiles** (the JIT's, an image's native compile) is inferred under its own policy: a MethodInstance under its method's, as the queue reaches it; a CodeInstance whose source is gone or that is no longer valid, under the policy it records.

### §2.4 Calls between policies

- **The status line as it stood:** Implemented on `unified` 10c7e1c2cf (W-100) for inference: a callee of the other policy is inferred in an inference of its own and the caller rests on its CodeInstance. At run time, on c44a447f2c: entries of compiled code of each policy, the builtins' variants, the interpreter's policy, the runtime's entries with the setting's default; gate `f6_reach_policy`. With C-45 and C-50.

### §2.5 The test bed

- **The status line as it stood:** Implemented on `unified` 4ba5b7025f and c44a447f2c (W-100): a session under it starts and runs, and its user code is compiled by facts (E-275; gate `f6_reach_policy`). A session's start-up compiles Base's start-up code by facts, 24–25 s ([PE-23](../performance-explorations.md)). The spelling `--compile-by-facts=all`: Planned.

### §2.6 `--trim`

- **The status line as it stood:** Implemented on `unified` cb7f55bd35 (W-100) and bb2031f820 (the modules' mark): under `--trim` every method and top-level thunk is plain, so every CodeInstance is. Trimmed binaries of the demonstrators are built and run in E-361 ([evidence §4](../../design/evidence.md#4-builds-and-binaries)).

### §2.7 Fully typed mode

- **The status line as it stood:** Implemented on `unified` 5f2373b2d5 (W-114): the flag and the option, the policy, the check after optimization, the hook; gate `n9_fully_typed`. The library's report and errors: [lowering §14](../../reference/lowering.md#14-fully-typed-mode-concrete-parts-closed-programs). Where the mode lives (the compiler finds the fault, the library explains it): mine (2026-11-07). The result's type as no fault: `unified` 22db66e23c. The fault as exactly the closed build's refusal, by the build's own check: `unified` 381cc8b953 with TraitWorld `unified` 78a78af (W-142; E-369), with traits T-100 and T-109; the check as the build's code under an owner of its own, and its overlay: mine (2026-11-12, 2026-11-14; [decisions](../decisions.md) §6). One definition with the setting as its parameter: mine (2026-11-15; D-10); the report's calls settled only when closed, listed apart: Planned, with [traits T-122](../../reference/traits.md#19-deviations).

### §3.1 The record

- **The status line as it stood:** On `unified` 9a601902a0 (W-100): dispatch and binding edges as Julia records them; positive memberships, the entry itself, recorded at `isa`, `<:` and dispatch matches, the code's worlds from theirs, read by image validation (E-277; gate `f7_membership_edges`), with C-51. A folded negative's edge (§4.8). Result edges told apart, code edges' digests and layout identities: C-52. A dispatch edge with the call's signature where the instance is wider: `unified` 53ec4356bf (E-336; gate `n21_callsig_backedge`), mine (2026-11-09). A call of `!==`, whose one method inference infers at `(Any, Any)`, is matched at its own signature, which its edge keeps: `next-s3` 6b3175dc9c (W-157; E-477), mine (2026-11-15).

### §3.2 G2 as a predicate

- **The status line as it stood:** The bit implemented on `unified` 8ef154476f (W-100), for code of either policy and kept in images, the edge instance made for a constant-propagated result on 427760d9e9 (gate `f4_g2_bit`, E-320). Computed for plain code too: adopted with the work plan (the user, 2026-11-06), the trade-offs review's M1. The bit as the deep class, decided at a CodeInstance's finish, a cycle as one, an absence edge counted in: `next` 7063158f42 (W-155; gate `w155/gate_deep.jl`; E-417). A callee named by its MethodInstance alone counts as outside; the edge names the callee's code where it exists when the caller finishes: `next-s3` 0a07a715ca (W-157; E-477; open issue 195 (a)), mine (2026-11-15). A positive membership's edge (the instance of the membership's method, §5.6) counted in: `next` 76ae6b0ee7 (W-160) and `next-s3` e7681dfc54 (open issue 211).

### §3.3 One compiled code per result

- **The status line as it stood:** Implemented on `unified` 9c6c9270f3 (E-388, E-389); without result edges and the code slot on `next` 9b6dacf5c5 (W-155; E-419). `unified` still has the slot.

### §4.1 Sets

- **The status line as it stood:** Implemented on `unified` 62016706d0: the `open` bit, `never_member` (the builtins' types included), a set's supertype, the contract's slot. The contract itself is written by the library (W-106). The contract on the `TypeName`: mine (2026-11-06). The operations as entries the compiler reads, with no method for an operation without a default: Implemented (D-4, 2026-11-15; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498)): the `TypeName`'s slot `operations`, written once by `jl_set_contract_operations`. The entry's form (the signature as a tuple type) is mine (2026-11-15), and so is its slot of its own beside the declared fields (W-161).

### §4.2 Memberships

- **The status line as it stood:** Implemented on `unified` 62016706d0, but for a pattern variable bounded by a `Union`, which the library declares per type (W-106).

### §4.3 Worlds

- **The status line as it stood:** Implemented on `unified` 62016706d0; strict mode's check and the retired entry on `unified` 0bb8f38830 (E-343). A membership taken back: `next-s3` 213c759370 (the plan's D-13, 2026-11-15; E-459); the mechanism (the entry ended and its method deleted in one world, the walk for the removal) is mine (2026-11-15).

### §4.4 Transitivity

- **The status line as it stood:** Implemented on `unified` 62016706d0.

### §4.5 Subtyping

- **The status line as it stood:** Implemented on `unified` 62016706d0. No type equality from a membership: `next-s3` e967266d9e (the plan's D-11, 2026-11-15; gate `experiments/unification/w155b/gate_d11.jl`, E-456).

### §4.6 One instance per member

- **The status line as it stood:** Implemented on `unified` 62016706d0 for a concrete member, a set's inputs on `unified` 350c5b1c59 (gate `n10_inputs`), an image's membership at activation on 07c0bee2a2, ending an older entry on 9f8d7d7c48 (gate `n12_image_instances`, E-348); a pattern, against the entries at the set and at the sets that join it, on edc2653e43 (gate `n10_inputs`, E-321).

### §4.7 Three layers

- **The status line as it stood:** Implemented on `unified` 62016706d0; a concrete non-member's disjointness by reachability 88daaca7fe; the meet of a set and an abstract type as `All{X, T}` 8a9144928e (W-107; mine, 2026-11-07).

### §4.8 Negatives fold with an edge; positives through entries

- **The status line as it stood:** Implemented on `unified` 62016706d0 for the lattice's sites; the positive fold through an entry, with its world and its record (§3.1), on `unified` 9a601902a0 (W-100), with C-51. A negative folded with an edge: `unified` bf447db25e (W-129 (a)) for a set that opted in, 80aa919bed, 1b2f0a9e1e and a19d937eaa for every set, wherever the code is compiled (W-140); with C-77; gates `n18_closed_after_load`, `n20_unmet_lookup`, `n2_open_abstract`. The end of Base's build: `unified` b133374e9d (W-129 (b)), mine (2026-11-09). An intersection no type is in: `unified` 1906196731 (E-334, open issue 169 (a)), with C-79; mine (2026-11-09); a component under a `where`: a19d937eaa (E-365). The edges as the method table's own (§5.6): `unified` 90fb8ff97a, 8b4fde6e84 (W-141; E-367). A test's own positive: `unified` 86deee2f98 (gate `n31_isa_narrows`; E-373), mine (2026-11-14). The rule: the user (2026-11-11; [decisions](../decisions.md) §4). A positive decided at code generation (the user, 2026-11-15: "Yes please. Build the compiler for P1 and be cogniszent of finding principled ways of making the design fast."): `new`'s field test on `next` 8c2d3a5457, the statement's flag for `new`, a store and a `typeassert` on 5b1900641f (W-160 (a); E-436, E-441; `w160/check/new_fold.jl`, `w160/check/stores.jl`). The store's test and the statement's flag: mine (2026-11-15).
- **Taken from the section's text:** Where the box does not escape, code generation passes it by reference, and it needs no heap of its own (E-407).

### §4.9 Intersections

- **The status line as it stood:** Implemented on `unified` 8a9144928e (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}"), but for the split's candidates (W-109). The encoding and the further rules: mine (2026-11-07, after [the review of the encoding](../../../attic/writeup/reviews/2026-11-07-all-representation.md)). Normal forms by declared supertypes, and candidates at an intersection: mine (2026-11-06, the reviews of the draft). The equality inside an invariant parameter by declared structure: `next-s3` e967266d9e (D-11; E-456).
- **Taken from the section's text:** **Its name** is not exported by `Core` ([open issue 148](../../open-issues.md#2-design)).

### §4.10 Type values

- **The status line as it stood:** Implemented on `unified` 62016706d0; the kinds on f14be868df, 0c9e44cb3d (gate `m1_typevalue_isa`, E-321).

### §4.11 Inference's world

- **The status line as it stood:** Implemented on `unified` 48864e547d.

### §5.1 The method table

- **The status line as it stood:** Implemented on `unified` 29035cab11; `jl_open_set_methods_of(X)` reads the index for compiling ahead (5f2373b2d5, W-114; [lowering §12](../../reference/lowering.md#12-compiling-ahead)). A membership ends only the fast path that a method at the set is the only one at its signature: the method stays the one `which` selects there, so validation does not read it as deleted and an image keeps its code (e81cd49a67). Listed at the set's position, indexed at the others: `unified` 45fa624462 (E-335), mine (2026-11-09).

### §5.2 Specificity

- **The status line as it stood:** Implemented on `unified` 62016706d0; intersections and a pair at two sets asked again 8a9144928e (W-107); a pair with one method at a set 0ce5b7f752 (W-114, found by BaseTraits: a `KeySet` and a `BitMatrix` read as ambiguous). Mine (2026-11-07).

### §5.3 Match world ranges and abstract queries

- **The status line as it stood:** Implemented on `unified` 29035cab11; the matches at an abstract query 8a9144928e (W-107). At a query in the latest world in which an entry's visibility changed, or later, a match's valid worlds start at that world, with no walk of the entries: exact at their end, narrower at their start (`unified` 89b3bcff81 and d04256a442, E-300, E-301). A match through `Callable` is a match through its entries, as at any set (`next` eaa19da272, [§7.4](../../reference/compiler.md#74-callables-call)).

### §5.4 The ambiguity report at a membership

- **The status line as it stood:** Implemented on `unified` 0d529d33a9 for a concrete member, the joint method at `All{X, Y}` 8a9144928e (W-107), a pattern member at the call types both methods reach 264b7f959f (gate `m2_ambiguity_arity`, E-320). Strict mode's error with strict mode (W-114). The reflection in the query's world on `unified` b133374e9d (`has_unmet_intersection`, `base/reflection.jl`; E-330); an intersection unmet by the world's entries on `unified` 43c222c751 (gate `n20_unmet_lookup`, E-331); dispatch's lookup dropping the match with its absence edges, on `unified` 999777ab77 (gate `n20_unmet_lookup`, E-341), at every set on a19d937eaa (W-140): mine (2026-11-09, [the performance review](../../../attic/writeup/reviews/2026-11-09-performance-day.md) H2; [the plan](../../../attic/writeup/plans/2026-11-09-c82-unmet-match-lookup.md)). Strict mode's refusal, the search without caches and the live entries only on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343); the ambiguities a membership creates only on `unified` 2ee5569252 (gate `m2_ambiguity_predates`, E-346); each method the membership makes applicable asked against the method table at the member on `unified` 53d28eea68 (gate `m2_ambiguity_declared_super`, E-347, W-132): the search through the member only and one warning per method are mine (2026-11-10, [the plan](../../../attic/writeup/plans/2026-11-10-c78-report-at-declared-supertypes.md) and [its review](../../../attic/writeup/reviews/2026-11-10-plan-review-c78.md)); the tie with a method at `Any` reported like any other: decided under the user's instruction of 2026-11-10 ([decisions](../decisions.md) §5).

### §5.5 A membership invalidates as a method does

- **The status line as it stood:** Implemented on `unified` 29035cab11 for the walk and the caches; its cost in proportion to the replayed method's own function, the member substituted at a parametric set, on `unified` aa997b2180 (W-123); a selection made ambiguous at a member called before, on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343). The walk invalidating code, a method under its variable's bound, the replayed method passed over at a pruned arm: `unified` a2ea2aff32; what matched before kept, an invariant parameter not replayed: a19d937eaa (W-140; E-365). The replay at the method's own signature: `next` 75a7f1795b (W-160, E-444). Gates `m2_dispatch_worlds`, `m2_stale_caller`, `n7_guards`, `n11_late_shadow`, `m2_parametric_replay`, `n25_image_before_set_method`, `n27_invariant_parameter`, `n28_wide_caller`. The rule: the user (2026-11-11); that a call records no absence edge and the walk does the work, and what the walk leaves valid: mine (2026-11-11; [decisions](../decisions.md) §4). With C-88.

### §5.6 The membership's method and the edges

- **The status line as it stood:** Implemented on `unified` 90fb8ff97a, b66cdc66f2 and 8b4fde6e84 (W-141; E-367). Gates `n29_membership_method`, `n18_closed_after_load`, `n20_unmet_lookup`, `n12_image_instances`. The mechanism kept as the implementation, a membership defined as behaving as a method does: the user (2026-11-12; [decisions](../decisions.md) §4). With open issue 180. Its method deleted when the membership is taken back: `next-s3` 213c759370 (D-13, E-459).

### §6.1 The key as a type

- **The status line as it stood:** Optional (W-110; the plan's D-14, 2026-11-15).

### §6.2 How an argument is compiled

- **The status line as it stood:** Julia's rule: Implemented. Not in force on the build: Julia resolves an attribute at each argument typed by a set (C-112), so `@nospecialize` there takes the attribute's run-time path (E-402: 829 ns a call). The kept forms: §6.9.

### §6.3 The forwarders

- **The status line as it stood:** Implemented (the plan's D-1; the user, 2026-11-15; [decisions](../decisions.md) §3; W-160 (b)): the expansion hook on `next` 8b1ec88a56, the library's expansion in TraitWorld `unified` 21ae901, d537141 and 2bf59b9, `:no_forwarder` in 21ae901; with C-111 for the forwarder's record of its method. The place, the method's definition from its evaluated signature; the forwarder's record of its method; `:no_forwarder`: mine (2026-11-15). The library's hook, the box in the body, the forwarder compiled per member type where the member fixes the set's parameters or several arguments erase, and the arguments not boxed: mine (2026-11-15, W-160). A set's parameters left open lifted into the forwarder's: TraitWorld `unified` fb67ac1 (open issue 204, E-497), mine (2026-11-15).
- **Taken from the section's text:** Where the box does not escape, it needs no heap of its own (E-407).

### §6.7 The definition-time check

- **The status line as it stood:** Implemented (the plan's D-3, 2026-11-15; [decisions](../decisions.md) §2; W-160 (c)), with C-115: the library reads the method's instance at the box from Julia's cache (TraitWorld `unified` 9c0912b), and a membership's walk keeps it (`next` 75a7f1795b, §5.5); E-440, E-444. A member's check as its instances: [traits T-129](../../reference/traits.md#19-deviations). The `bounded` option: the user, 2026-11-06, Q2 (a). The check's place in the latest world: mine (2026-11-14; E-391).

### §6.8 A declared result on `Method`

- **The status line as it stood:** Lowering's record of `f(…)::RT` implemented on `unified` 0ba6317994 and 523214899f (a module's binding) (lowering's `declared_result` meta, evaluated by `jl_method_set_source`), gate `n16_declared_result`. The record's scope (a type at the definition) is mine (2026-11-09). An operation's declared result read from its contract entry, not from a method at the set with a flag: Implemented (D-4; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498)). `Method.declared_covers` stays in the layout with no reader.

### §6.9 The kept forms in `Core`

- **The status line as it stood:** `Core.Dynamic`: Implemented on `unified` e692e57ab7 (W-111); its constructor tests the membership when it runs and boxes a box anew, and the library's methods stand in (C-113). The wrapper is the library's type (C-113, [traits T-126](../../reference/traits.md#19-deviations)). The casts and `keep` are still built (C-112). `Dynamic` in `Core`: mine (2026-11-06, the reviews of the draft). `Compiled` in `Core`, beside it: mine (2026-11-15).
- **Taken from the section's text:** It is no method at a set: a late load of it ends nothing (E-404).

### §7.1 The rule

- **The status line as it stood:** The rule for an operation's call implemented on `unified` e70675a606, compiled as the split (§7.2) with the result asserted. Declared fields implemented on `unified` 50da8d8ee2: the library writes a trait's declared fields on its `TypeName` (`jl_set_declared_fields`), inference reads them along the trait's declared supertypes, and along its supertraits (their instances from the set's own entries, `jl_supertrait_instances`) on `unified` 350c5b1c59. `getproperty` at a `HasProperty{N, R}`: on `unified` 350c5b1c59, a declared field named by the input `N` ([traits §4.3](../../reference/traits.md#43-fields)). The facts mode: W-100. A closed abstract type with a contract on `unified` b05ae361e0 (E-337): mine (2026-11-09). The declared result read from the contract's entries, with no method at the set: Implemented (D-4; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498); `operation_entries!`).
- **Taken from the section's text:** A contract is declared in the image that defines the type; one written on a type another image holds is refused, since the writer's image would not keep it (Base's build declares Core's `IO`'s; mine, 2026-11-10).
- **Taken from the section's text:** Where the constant-propagated code is taken for its effects or its exception type, its result type is joined into the call's, so compiled code never returns a type its call's type excludes (`handle1`, `unified` ef1233e79e).

### §7.2 The split

- **The status line as it stood:** Implemented on `unified` e70675a606: the candidates per set, registered at a membership, at an image's activation and by the library at a pattern's member's first use, ordered by declaration (C-38); the split over the first four, the table as the fallback (§7.3). Each branch `Compiled` for its candidate on `unified` b133374e9d (found by `IO`'s `get`, whose candidates are all served by the default at `::IO`; gate `n19_io_trait`): mine (2026-11-09). A branch not inlined through a pointer, with no edge, on `unified` 0c836f3ef6, and only a leaf inlined on 7bd8b6e512 (E-332, [open issue 167](../../open-issues.md#2-design) (a)); the result converted (traits §7.9) on 0c836f3ef6 (E-333): mine (2026-11-09). That the split needs no method at the set: run without one on julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498): the library's suite, the ports' suites and the forks' digests pass with no method at a set for an operation without a default.

### §7.3 The table of a call's targets

- **The status line as it stood:** Implemented on `unified` e70675a606, ported from `trait-world-1.13` 711484a23e and 6d480d0753, but for the targets compiled ahead into images (C-39). The dynamic call where no pointer is made, on `unified` d554855579 (found by Base's `precompile` test, a session without LLVM; E-330): mine (2026-11-09).

### §7.4 `Callable`'s call

- **The status line as it stood:** Implemented (the plan's D-2, 2026-11-15, the user: "Okay, accept the change."; [decisions](../decisions.md) §3; W-153): `Callable`'s inputs and `Function`'s entry, declared in Base's build (`base/Base.jl`), subtyping by entries only, julia `next` eaa19da272; the box's test, the wrapper's entry and `@implement Callable T` in TraitWorld `unified` c14d2e4 (W-161; E-500), with C-146. The box's call checked at both ends in the library: TraitWorld 5d52f0d (W-113). `Function` declared a member of every instance, and a callable type that is no `Function` by declaration: mine (2026-11-15). The wrapper's test also reads its result inferred at `A` against `S` ([GT-24](../../goals.md#3-tensions-between-the-goals) (b)): mine (2026-11-15, W-161).

### §7.5 `IO`

- **The status line as it stood:** Implemented on `unified` b05ae361e0 (W-129 (c); `base/iotrait.jl`, `jl_declare_contract`; gates `n19_io_trait`, E-337); each result `Any`, nothing converted, on ef1233e79e, the candidates in the contract on 18bbbf0841 (open issue 171, C-81; gates `n19_io_trait`, `n23_contract_image`; E-340). The user (2026-11-09: "Go with the Fable plans recommendations"; [the plan](../../../attic/writeup/plans/2026-11-09-io-alternatives.md) §4.2). The candidates' order: mine (2026-11-09); no result promised: mine (2026-11-10). Targets at a stream past the candidates compiled at the first call: open issue 170.

### §7.6 A closed build

- **The status line as it stood:** Implemented on `unified` 97861c6b31, ddc328b343 (the instance compiled once at a call that does not know the member), 5d8da002fa (the branches at a cast to `Compiled`, the cast typed by its set) and d8cebc40fe (members by use, the rounds, the report) (W-139; E-364: five small programs and TraitTables' table program build under `--trim=safe` and run, where the plain twin with an abstract type is refused). The rule: the user (2026-11-11); members by use: the user (2026-11-11, "Build members by use."). The box as a member, the bound of 64, the second inference, the rounds, and what counts as a use (the places, the test): mine (2026-11-11). The branches at a call whose static parameter the value binds: built for a cast only (C-114), mine (2026-11-11, for the cast; 2026-11-15, for the wrapper). The rules asked of the interpreter, and an invoke that names its instance compiled: `unified` 381cc8b953, bounded on 42681be784 (Base's `Compiler/inference` test) (W-142; E-369: Base's `repeat(::Char, ::Int)` builds). With C-86, C-87. A build that compiles what is written: Planned (the plan's D-1, 2026-11-15); the build still resolves an attribute at a trait argument (C-112, C-114). The closed rules as what follows from what is final, and the three consequences stated first: mine (2026-11-15; D-10); an operation on a set with no member and a call in the latest world: Planned, with C-102 and C-103.

### §8.1 The `cfunction` calling convention `:caller_world`

- **The status line as it stood:** Implemented on `unified` 6f936edf18.

### §8.2 The per-call-site dispatch cache

- **The status line as it stood:** Implemented on `unified` 8319275b9e for wildcard entries. Exact-type entries: W-109, in a form whose cost at a site that sees many types is vanilla's ([PE-20](../performance-explorations.md)).

### §8.3 Further work

- **The status line as it stood:** Optional.

### §9 Images and the machine-code cache

- **The status line as it stood:** Memberships in package images implemented on `unified` 28c401eb0c (W-108), refused at a second instance on 07c0bee2a2; the edges with W-141 (§5.6). Every activated entry in its set's index and the list of activated entries on `unified` e42047dba2 (C-83 retired, gate `n12_image_instances`, E-344); an older entry for the same member, set and inputs ended at activation on 9f8d7d7c48 (E-348). The pattern members' answers: lowering L-55. Compiling ahead: Planned ([traits §16](../../reference/traits.md#16-compiling-ahead-closed-programs)). The keep rule by the G2 bit implemented on `unified` 823754556f (W-100), for code reached only dynamically from outside the package: TraitWorld's image grew 3.7 %; by the deep class on `next` 7063158f42, TraitWorld's image keeps 209 such instances where it kept 237 (E-417). The cache: paused. The rule for a signature type without a hash is implemented on `unified` 999634c858. The walk and the report at activation: mine (2026-11-07); the findings handed to the library under strict mode on `unified` 9f8d7d7c48 (gate `stack/strict_activation.jl`, E-349): mine (2026-11-10). The rule for run-time sites implemented on `unified` 6767b03893 (`Compiler/src/facts.jl` `rtsite_targets`, `typeinfer.jl` `compile!`; E-326; gate `n17_rtsite_targets`), for all modules: mine (2026-11-09). The system image's indices of sets on `unified` b133374e9d (W-129 (b), gate `n19_io_trait`): mine (2026-11-09).
- **Taken from the section's text:** The cache itself is paused ([decisions](../decisions.md) §5).

### §10.1 Definition and image hooks

- **The status line as it stood:** Implemented on `unified` 28c401eb0c (W-108). TraitWorld `unified` 701aaab uses them for the override rule and for a `struct S <: X` without its `@implement`; `bounded` bb78d02 (W-111); strict mode and `no_pirates` 7adcc94 (W-114); a member's check kept, in the definition hook's first call and the image hook, 5b3c427 (E-342). The module-end hook: mine (2026-11-06, the work plan's review, weak point 6). A returned error raised at the definition: `unified` 8f42ba7ed7 with TraitWorld `unified` 399f389 (`test/messages.jl`), mine (2026-11-12). The expansion hook: `next` 8b1ec88a56 with TraitWorld `unified` 21ae901 (W-160), mine (2026-11-15).

### §10.2 Hooks for strict mode

- **The status line as it stood:** The deletion hook implemented on `unified` 5f2373b2d5 (`jl_set_method_deletion_hook`, W-114). The report per image is the library's, from validation's log (TraitWorld 7adcc94). The hook for a binding redefined from another module: Planned ([traits T-96](../../reference/traits.md#19-deviations)). The flag for a membership on `unified` 0bb8f38830 (E-343); the ambiguities at activation on 9f8d7d7c48 (E-349). What a membership would replay, and the entry refused with its method: `unified` 7fee959383 (gate `stack/strict_pirate_membership.jl`). What a definition ended, by class: `next-s3` 5d2ec7ff85 (the plan's D-12, 2026-11-15; E-457); `jl_take_deep_endings`, `jl_set_deep_endings`, `jl_note_deep_ending` are mine (2026-11-15).

### §10.4 The member hook

- **The status line as it stood:** Implemented on `unified` ec4f9a8714 at dispatch and fcdfd0da36 in the compile queue (gate `n24_hook_compile_queue`, E-352; leaving a failed use to dispatch: mine, 2026-11-10), with C-30 and C-31; an abstract member's subtypes reached through its entry with TraitWorld e8554d9 (C-85, E-345); a declared subtype of a set with no entry on `unified` 352b916899 with TraitWorld 0aff625 (E-350); a failed check lowers the entries made while it ran on 07c0bee2a2; at a split's table miss with W-109. Mine (2026-11-06). Checks only, and where it runs: mine (2026-11-06, the reviews of the draft).

### §11 Changes useful without traits

- **The status line as it stood:** Implemented on `unified`, one commit each, below the stages' commits ([`../design/julia-changes.md`](../../design/julia-changes.md) §7.1); the entry of `return_type`'s own interpreter with the facts policy (W-100). The type joins, the error paths, the scheduler's write, `Val` and `IOContext`: `next-s3` ab96564f36, 297d19aca1, 396cd65a48, 024755ee89, bc844be7c0 (W-157, the plan's D-8; E-478). Upstream proposals: the same chapter.

### §12 Status index

The rows as they stood, where the pass changed them:

| Interface | Status | Section |
|---|---|---|
| the facts inference, fact signatures, run-time sites, `return_type`, effects | Implemented (`unified`, W-100), with C-45, C-47; owner-only functions `next-s3` e483299622 (D-9, E-458), with C-130 | §1 |
| the policy per method; one CodeInstance per MethodInstance and policy; calls between policies; the test bed; `--trim` | Implemented (`unified`, W-100), with C-49, C-50; no method of Base a boundary (E-279) | §2 |
| fully typed mode | Implemented (`unified` 5f2373b2d5, W-114); one definition with the setting as its parameter, the session's calls listed apart: Planned (D-10, traits T-122) | §2.7 |
| the dependency record; G2 as a predicate, the deep class | the record's positive memberships and G2's bit implemented (`unified` 9a601902a0, 8ef154476f), with C-51, C-52; a folded negative's edge (W-129, W-140); the bit as the deep class `next` 7063158f42 | §3.1, §3.2 |
| one compiled code per result | Implemented (`unified` 9c6c9270f3); no code slot on `next` 9b6dacf5c5 | §3.3 |
| sets and their contracts, memberships, worlds, transitivity, subtyping in the walk | Implemented (`unified` 62016706d0); no type equality from a membership `next-s3` e967266d9e (D-11, E-456) | §4.1–§4.5 |
| one instance per member | Implemented (`unified` 62016706d0; a pattern edc2653e43) | §4.6 |
| three layers; negatives fold with an edge; positives through entries | Implemented (`unified` 62016706d0); positives' world and record on `unified` 9a601902a0, with C-51; negatives folded with their edge at every set `unified` a19d937eaa (W-140), with C-77; an intersection no type is in `unified` 1906196731 (E-334), with C-79; a positive decided at code generation, at `new`, a store and a `typeassert`: `next` 5b1900641f (W-160) | §4.7, §4.8 |
| intersections `All{X, Y, Z, …}` | Implemented (`unified` 8a9144928e), but for the split at an intersection (W-109) | §4.9 |
| type values as members | Implemented (`unified` 62016706d0; the kinds f14be868df, 0c9e44cb3d) | §4.10 |
| methods at sets in the table; specificity; match ranges | Implemented (`unified` 29035cab11, 62016706d0; intersections 8a9144928e) | §5.1–§5.3 |
| the ambiguity report at a membership | Implemented (`unified` 0d529d33a9, a pattern member 264b7f959f); strict mode's error W-114; dispatch's lookup at an unmet intersection on `unified` 999777ab77 | §5.4 |
| a membership invalidates as a method does | Implemented (`unified` 29035cab11 the walk and the caches; a19d937eaa the code, W-140), with C-88; taken back, as a method's deletion: `next-s3` 213c759370 (D-13, E-459) | §4.3, §5.5 |
| the membership's method and the edges | Implemented (`unified` 90fb8ff97a, b66cdc66f2, 8b4fde6e84) | §5.6 |
| an argument compiled as Julia compiles it | Julia's rule, with C-112 | §6.2 |
| keys: `TraitKey`, calls from code per key, the calling convention, the adapter, field offsets | an optional extension (W-110): [extensions §1](../../reference/extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike) | §6.1, §6.4–§6.6, §10.3 |
| the forwarders, made where a method at a set that erases by default is defined | Implemented (`next` 8b1ec88a56, TraitWorld `unified` 21ae901; W-160), with C-111 (the forwarder's record of its method) | §6.3 |
| the definition-time check: the instance at the box | Implemented (D-3; TraitWorld 9c0912b, `next` 75a7f1795b; W-160 (c)), with C-115 | §6.7 |
| a declared result on `Method`; lowering's record of `f(…)::RT` | Implemented (`unified` 0ba6317994); an operation's declared result from its contract entry: Implemented (D-4; `next` 5448a8b7bf) | §4.1, §6.8 |
| the kept forms in `Core`: `Dynamic{X}`, `Compiled{T}` | `Core.Dynamic` implemented (`unified` e692e57ab7, W-111), with C-113; `Core.Compiled` Planned (D-1), with C-113; no cast, no `keep`: Planned, with C-112 | §6.9 |
| operations on a value typed by its trait; the split; the table | Implemented (`unified` e70675a606, 50da8d8ee2), with C-38, C-39; no method at the set for an operation without a default: Implemented (D-4; `next` 5448a8b7bf) | §7.1–§7.3 |
| `Callable`: every function a member, the signature checked at the box and at a wrapper's entry, the result on return | Implemented (D-2: `next` eaa19da272, TraitWorld c14d2e4; W-161), with C-146 | §7.4 |
| A closed abstract type with a contract; `IO`'s contract, its candidates, the eraser `IOContext{IO}` | Implemented (`unified` b05ae361e0, ef1233e79e, 18bbbf0841) | §7.1, §7.5 |
| world-checked caches: `:caller_world`, the per-call-site cache | Implemented (`unified` 6f936edf18, 8319275b9e); exact-type entries W-109 | §8.1, §8.2 |
| memberships in images; the record toward a machine-code cache | memberships in images implemented (`unified` 28c401eb0c; one instance per member at activation, 07c0bee2a2); the positive-membership edge read at validation (`unified` 9a601902a0); the record's stable identities: C-52 | §9 |
| hooks, the module-end hook included; the member hook | the member hook implemented at dispatch (`unified` ec4f9a8714) and in the compile queue (fcdfd0da36; C-30, C-31); the definition, image and module-end hooks implemented (`unified` 28c401eb0c); strict mode's deletion hook implemented (`unified` 5f2373b2d5), the binding hook Planned; what a definition ended, by class (`jl_take_deep_endings`) `next-s3` 5d2ec7ff85 (D-12, E-457) | §10 |
| changes useful without traits | Implemented (`unified`, the stack's first eleven commits) | §11 |

### Deviations

- **The table's head as it stood:** The build's heads: [state.md §6.1](../../state.md#today); its commits, stage by stage: [julia-changes §7.1](../../design/julia-changes.md#71-the-stack). IDs are shared with the record's other references and never reused.

The open rows as they stood, where the pass took text out of them (the retired rows are in [the ledger's part](../../../attic/writeup/record/deviations-retired-compiler.part.md)):

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-30 | [§10.4](../../reference/compiler.md#104-the-member-hook) | The runtime keeps the member hook's answer per (member type, set) on the member's `TypeName`, a failure included. | The runtime keeps the state in a table of its own (`jl_member_states`), read by inference and the compile queue, and an image keeps the passed ones (`unified` b1c0b50f4c). The library keeps the answer too (`TraitWorld._CHECKED`), and the runtime calls the hook at every dispatch miss of such a call with no answer, and lowers the cache entries a failed check left. A failure is not kept by an image. | `src/gf.c` (`member_hook_at_dispatch`, `jl_member_note_use`, `jl_member_checks_passed_here`); TraitWorld `src/implement.jl` |
| C-31 | [§10.4](../../reference/compiler.md#104-the-member-hook) | The hook also runs in the compile queue, before code that relies on the member runs; a use whose check failed is left to dispatch, which raises the check's error. | Built for a call inference resolves at a concrete member (`unified` fcdfd0da36, gate `n24_hook_compile_queue`). A call by `invoke` at the set's method asks no hook, compiled or at run time. With several threads, another thread can run the compiled code before the queue's check of it ends. | `src/gf.c` (`jl_member_queue_drain`); `Compiler/src/abstractinterpretation.jl` (`member_check_failed`) |
| C-51 | [§4.8](../../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§3.1](../../reference/compiler.md#31-the-record) | A positive answer through an entry folds, with the code's worlds from the entry's and the entry in its record. | It folds at `isa`, `<:`, a dispatch match, `new`'s field tests and a store's or a `typeassert`'s type test (the statement's flag, W-160) in the frame being inferred. `typeassert`'s nothrow, `typesubtract` and the semi-concrete pass leave such an answer unfolded; the optimizer's effect query at `new` proves no such test. The optimizer's other queries by `⊑` answer through an entry without recording it: the inliner's match coverage, the deletion of a `typeassert` whose argument is under its type (`adce_pass!`). Their code rests on the membership with no edge of its own; where the statement came from an inlined callee, the callee's edges carry it. | `Compiler/src/typeutils.jl` (`positive_fold_blocked`), `Compiler/src/tfuncs.jl`, `Compiler/src/ssair/passes.jl` (`adce_pass!`), `Compiler/src/ssair/inlining.jl` |
| C-52 | [§3.1](../../reference/compiler.md#31-the-record), [§9](../../reference/compiler.md#9-images-and-the-machine-code-cache) | The record tells result edges from dispatch edges, gives a code edge the digest of its callee's lowered code, records the layouts of the types whose fields the code reads, and names its targets by identities stable across sessions. | An edge to a callee names its CodeInstance, result edge or code edge alike (the list of result edges apart is gone on `next` 9b6dacf5c5); no layout is recorded; targets are objects of the session or its images. In a session a method's identity and the binding edges serve. The rest comes with the machine-code cache (paused). | `Compiler/src/stmtinfo.jl` (`add_edges_impl`), `Compiler/src/typeinfer.jl` |
| C-77 | [§4.8](../../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries) | Inference folds a pair's negative at every site that consults `has_open_set`. | It folds at `isa` and `<:` (`isa_tfunc`, `subtype_tfunc`), in a frame that records the edge. `tmeet`, `isa_condition`, `typesubtract` and the constants' and conditionals' meets still refuse it. | `Compiler/src/typeutils.jl` (`negative_fold_blocked`), `tfuncs.jl` |
| C-79 | [§4.8](../../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries) | Where an intersection no type is in, inference relies on it as on any negative. | It folds at `isa` (`isa_tfunc`) and at dispatch's lookup (`drop_unmet_matches`, `src/gf.c`). `<:` (`subtype_tfunc`), `tmeet`, `typeassert`, a conditional's narrowing and a declared argument type still meet a set `X` with `AbstractString` as `All{AbstractString, X}`. An intersection of more than two components, or a component with free variables that is not an abstract type, is not asked. | `Compiler/src/tfuncs.jl`, `abstractinterpretation.jl` (`drop_unmet_final_matches`), `src/datatype.c` (`jl_unmet_final_cells`); gate `n20_unmet_lookup` (4) |
| C-86 | [§7.6](../../reference/compiler.md#76-a-closed-build) | A family's and an abstract type's members in a closed build are the types the program uses as members. | The build counts the types its optimized code forgets at a place under the set, or at a place a `PiNode` or a `typeassert` narrows from. Not counted: a value whose type no compiled code forgets (made by a foreign call or by reflection, or held in a constant deeper than three levels or past 4,096 elements); a narrowing by a call the build did not inline into a test. Such a value raises `MethodError` at the branch. An operation on a set with no member: C-102. | `closed_note_used!` in `Compiler/src/typeinfer.jl`, `closed_candidates` in `abstractinterpretation.jl`; E-364 |
| C-87 | [§7.6](../../reference/compiler.md#76-a-closed-build) | The split over a set's members costs what a session's does: a branch among a few, a table past them (§7.3). | In a closed build every member is a branch, an `isa` test in the entries' order; a set of more than 64 members is not split. | `MAX_CLOSED_SPLITS`; E-364 |
| C-88 | [§5.5](../../reference/compiler.md#55-a-membership-invalidates-as-a-method-does) | A membership invalidates exactly the callers whose selection it changes. | (c) Where the walk cannot follow the shape, it invalidates every instance of the replayed method and their callers: the set under a `Vararg`, in a variable's lower bound, or deeper than 8 levels. No method takes this path at the loads of the forks' CSV and DataFrames, where five did (E-390, `unified` 8fccf1e182; gate `n32_nested_set`), nor at the methods at the kept forms (`next` 75a7f1795b, E-444). (e) is retired with C-104 (a membership adds no type equality, D-11). (d) The runtime still carries what nothing reads for a membership: the bit `closed_after_load` (set for every set the library declares; `Callable` has none), the modules' loaded marks' use by `type_declarers_loaded`, and the switch `jl_set_membership_walk_invalidates` (a control for measurements). The walk's cost at a load is not measured (W-140's rounds). | `src/gf.c` (`jl_membership_dispatch_walk`), `src/datatype.c` (`jl_membership_final`) |
| C-102 | [§7.6](../../reference/compiler.md#76-a-closed-build) | In a closed build an operation on a set with no member is a "no method" fact: the call raises `MethodError`. | The split's type is `nothing` where no candidate is of the receiver's type (`operation_split_type`: `n == 0 && return nothing`), so the call is left as a dynamic call, and the build's verifier refuses it: 38 of the ODE program's 50 errors, the solver core's callbacks in a program without them ([open issue 184](../../open-issues.md#2-design) (a)). | `Compiler/src/abstractinterpretation.jl` (`operation_split_type`, `abstract_call_gf_by_type`'s operation branch) |
| C-103 | [§7.6](../../reference/compiler.md#76-a-closed-build) | In a closed build a call in the latest world is the call: `invokelatest(f, args…)` is inferred as `f(args…)`, and a call after `:latestworld` as any call. | Under the closed rules `Core.invokelatest` is inferred as the builtin's own call, its result unknown, and a call after `:latestworld` is not inferred (`si.saw_latestworld`). Julia's build script rebinds `Base.invokelatest` to a direct call, which the session's check does not read (traits T-109 (1), [open issue 181](../../open-issues.md#2-design) (b)). | `Compiler/src/abstractinterpretation.jl` (`abstract_call_gf_by_type`: `si.saw_latestworld`; `abstract_call_known`), `Compiler/src/tfuncs.jl` (the builtins inference does not resolve); `contrib/juliac/` (the rebinding) |
| C-111 | [§6.3](../../reference/compiler.md#63-the-forwarders) | The forwarder records the method it forwards to, so that reflection shows one definition, and redefining or deleting the method takes its forwarders with it. | The two are ordinary methods of the table, entered in order by the expansion hook: `methods(f)` lists the method at the kept forms and its forwarder, both at the definition's line. A forwarder is found by a mark in its code (`Expr(:meta, :erasing_forwarder)`, TraitWorld's `_is_forwarder`), not by a record of its method. A redefinition makes both again at the same signatures and replaces them; a deletion of the method at the kept forms leaves its forwarder, which then calls a method that is gone (Revise). | `src/method.c` (`method_def`), `src/gf.c` (`jl_call_expansion_hook`); TraitWorld `src/erasing.jl` (`_expand_definition`, `_is_forwarder`); W-160 (b) |
| C-112 | [§2.1](../../reference/compiler.md#21-the-module-option), [§6.2](../../reference/compiler.md#62-how-an-argument-is-compiled), [§6.9](../../reference/compiler.md#69-the-kept-forms-in-core), [§7.6](../../reference/compiler.md#76-a-closed-build) | No attribute is resolved at a call: an argument is compiled as Julia compiles it; there is no cast, no `keep`, no `Core.attributed_call`; the module options are `facts`, `bounded`, `no_pirates`. | The attribute's machinery is built. A call's trait arguments carry attribute bits (`Compiler/src/stmtinfo.jl`), resolved at the method by five steps (`src/gf.c`: `effective_nospecialize`, `set_default_attribute`, `type_is_own`, `module_package`, `jl_attribute_sig`, `jl_attribute_dynamic_bits`, `jl_attributed_mi`). Casts lower to `Core.attributed_call` (`src/julia-syntax.scm`, `lower-cast-call`; `src/builtins.c`, `jl_f_attributed_call`, `attributed_call_reach`, its cache and table of latest calls), which inference (`abstract_attributed_call`, `attributed_matches`) and the inliner (`handle_attributed_call!`) resolve. `Core.compiled_for`, `Core.with_dynamic`, `Core._cast_compiled` and `Core.keep` are in `base/boot.jl`. The module options `dynamic` and `first_seen` are bits 4 and 8 of a module's flags (`src/module.c`; `base/experimental.jl`). So `@nospecialize` at a trait argument takes the attribute's run-time path (E-402: 829 ns a call), and a method at `Callable` takes `Dynamic` without a forwarder. A standard library's type is not Julia's own there (the subject of C-55). | the files named; removed in stage 4 of [the plan](../../plans/2026-11-15-next-iteration.md) (W-156) |
| C-114 | [§7.6](../../reference/compiler.md#76-a-closed-build) | In a closed build a call whose method's static parameter a value known only by its trait binds (the wrapper's constructor) branches over the members; nothing else of the attribute applies. | The branches are made for a cast's `Core.attributed_call` (`unified` 5d8da002fa: `abstract_attributed_call` under `closed_build`), not for such a call. The closed build still turns steps 4 and 5 of the attribute to `Compiled` at a known type (`unified` 21c9b33e39), takes a call left to dispatch on a trait argument as `Dynamic` (ddc328b343), and the verifier refuses an attributed call (`verifytrim.jl`). | `Compiler/src/abstractinterpretation.jl` (`abstract_attributed_call`, `attributed_matches` with `closed_build`), `Compiler/src/verifytrim.jl`, `src/gf.c` (`effective_nospecialize`) |
| C-115 | [§6.7](../../reference/compiler.md#67-the-definition-time-check) | The check reads the method's instance at the box, the instance a box's call runs: inferred by the native interpreter, cached with its edges, kept by an image; nothing else infers for the check. | Where a box's call runs an instance at another signature (the attribute's instance at the trait, for a method of a trait without the default, C-112), or Julia's cache keeps no code, the library infers the instance apart (`check_at_box`: `Base.code_typed_by_type` with a `NativeInterpreter(world; facts = true)` of its own), as it infers each callee below a call that only throws. A later definition of a function it called does not check the method again; only a name not yet defined and the module's end do (`_check_pending_bounded`, `_end_pending_bounded`). Beside it the classification is still built: `Compiler.DefinitionCheckInterpreter` (an ephemeral cache, the library's hook at each known call) and the library's `classify`. | TraitWorld `src/atbox.jl` (`check_at_box`, `_box_instance`, `box_signature`, `_stand_in`), `src/classify.jl` (`classify`, `check_definitions`, `_decide_bounded`, the pending lists); `Compiler/src/types.jl` (`DefinitionCheckInterpreter`) |
| C-146 | [§6.3](../../reference/compiler.md#63-the-forwarders), [§7.4](../../reference/compiler.md#74-callables-call) | A wrapper at a `Callable{A, S}` argument is tested where it enters every method as written. | The library's hook answers the entry only where exactly one positional argument has a `Callable` component, written in the signature (not through a `where` variable's bound), the set's parameters given (not lifted, open issue 204's case), outside a keyword body; elsewhere a wrapper of a function with no method at `A` enters untested, and the error is the call's own `MethodError` where the method calls it (E-500). | TraitWorld `src/erasing.jl` (`_wrapper_entry`) |

## Upstream places

The inventory of the places in upstream Julia's source that the design touches (files and functions, for a rebase or a patch series) is in the attic's exploration [`unified-build-from-vanilla-julia.md`](../../../attic/writeup/explorations/unified-build-from-vanilla-julia.md), §1, with its sources. The commits that touch each place are in [the inventory](../../design/julia-changes.md).
