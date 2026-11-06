# The unification work plan under the draft reference

Status: proposal (2026-11-06), for the user; not normative.

**The request** (the user, 2026-11-06): "Send out a second Opus agent that compares the unification work plan that was started with the new design and figures out how the work plan would have to change and how it could be simplified."

**By whom:** an Opus agent the user asked for explicitly. It only read files: it ran no Julia, built nothing and edited no other file.

**Compared:**
- **The old plan:**
  - the work items W-98 to W-104 (`../record/todo.md`);
  - their specification, compiler §7 of `../reference/`;
  - [the synthesis plan](2026-11-05-unification-synthesis.md) §4–§7;
  - [the audit](../reviews/2026-11-06-oc-build-audit.md).
- **The new design:**
  - [the draft reference](../reference-unified/README.md) at 76de721;
  - [the analysis](2026-11-06-traits-are-abstract-types.md), with its ledger of what is eliminated;
  - decisions §9.
- **The build:** branch `unified` at c3f0b4bc11, and the uncommitted diff in `src/subtype.c`, `src/builtins.c` and `src/jl_exported_funcs.inc`.

What the draft means for the ports and the prototypes is left to the parallel review (`../reviews/2026-11-06-unified-reference-prototypes.md`).

---

## 0. Summary

- **The old stages were cut for another model.** That model had trait objects, Core wrapper types (`Dynamic`, `Compiled`, `Kept`), two dispatch tiers, and TraitWorld migrated onto the build. The draft removes all of these.
  - Stages 1 and 2 (W-98, W-99) survive almost whole.
  - Stage 5 (W-102) is now five pieces of work, of very different risk.
  - Stage 6 (W-103) splits: images belong early, the rest of the surface late.
  - Stage 7 (W-104) gives its workloads to an early slice. Its "level 3 decided on paper" is already decided by the draft (Q2 (a)).
- **The main change of order: exercise the premise end to end first.**
  - A first slice: W-98, W-99, a new small library, and two workloads.
  - It adds no Compiler change beyond the fold gates the branch already builds.
  - Everything the draft calls a choice of speed comes after the slice: keys, the attribute, the split, guards, the facts policy and the code slot (traits §7: "Results never depend on it").
- **The branch.**
  - The uncommitted in-walk subtyping is the draft's compiler §4.4, §4.5 and §4.10. It addresses C-19, C-21, C-22 and C-26 (unverified: the tree does not build yet).
  - The Core wrapper types and `Core.Keyed` are now unneeded, so C-20 retires by deleting them.
  - The arms of `typemap.c` and `gf.c` that compose matches become unneeded too.
- **What no stage covers yet:**
  - `All`;
  - `Callable`'s derived memberships;
  - the library itself;
  - the member hook;
  - the attribute's mechanism (`Core.attributed_call`, `first_seen`);
  - memberships in images, needed early;
  - a hook at a module's end, which Julia lacks.
- **Weak points** (§6):
  - **Callable** (no principled option keeps all the draft's properties; the user decides): `Callable`'s derived memberships need plain inference inside `jl_subtype`.
  - **Keys:** underspecified for `struct S <: X`, for members of a pattern, and for operations called at a key.
  - **Normalization depends on the world:** `Union` and `All` normalize by subtyping, which now depends on the world.
  - **`Dynamic{X}`:**
    - its stated membership pattern misses intersections;
    - `Core` would have to name a type of the library.
  - **Casts** are recognized by their name in the front end.
  - **Julia has no hook at a module's end.**

---

## 1. Stage by stage

Each stage below lists:
- **Old:** its sources in the old plan;
- **Stays**, **Changes**, **Dropped** and **Added**, with the draft's sections;
- **Gate:** its gate.

### W-98, stage 1: the type system

**Old:** the todo row W-98; old compiler §7.2; synthesis §4 stage 1; the audit A1–A15.

**Stays** (draft compiler §4.1–§4.5, §4.10, §4.11):
- open sets;
- `never_member`;
- entries on the member's `TypeName`, published copy-on-write;
- worlds: the insertion protocol plus `Expr(:latestworld)` (C-25);
- transitivity, read inside subtyping's walk (C-22, C-26);
- invariance with `X{<:T}`;
- `Type{S}` entries (C-19);
- a cycle check over every path (C-23);
- the builtins never members (C-24);
- patterns of any size (C-21);
- a set open from its declaration, the epoch dropped (A5);
- A10, A11, A13.

**Changes:**
- **`struct S <: X`** makes `X` the declared supertype and adds no entry (§4.2). The uncommitted `builtins.c` already does this.
- **A set's supertype** is `Any` or a set (§4.1).
- **Entries carry no key.** Keys come with N5 (§6.1). Simplification S2 and weak point 4 say why.

**Dropped:**
- the Core types `Keyed`, `Dynamic`, `Compiled` and `Kept`;
- the bit `generic_wrapper` and every arm of subtyping that reads it;
- the walk by key on a redeclared membership, which moves to N5: until keys exist, a redeclaration is handled as any membership is (C-18).

**Added by the draft:**
- **One instance per member** (§4.6).
- **The contract's place on the set's `TypeName`** (§4.1): only the field and its serialization here; `@trait` writes it in N1.
- **`All`** (§4.9). This plan moves it to N2 (S3).

**Gate:**
- the probes P1 to P8 as gates;
- the m1/m2 gates re-pinned: `m1_wrappers` and `m2_keyed_rules` dropped, `m1_typevalue_isa` and `m2_set_in_set` re-pinned (the audit);
- Base's four test files within 10 % of the vanilla control;
- `detect_ambiguities(Base)` at 0;
- the old gate's tests in both worlds (the review's H3, M6, L10);
- new: the cost of a query whose type has many entries on its chain (weak point 9).

### W-99, stage 2: dispatch; gate B

**Old:** the todo row W-99; old compiler §7.1, §7.3; synthesis §4 stage 2.

**Stays** (draft compiler §5.1–§5.5):
- the linear placement in the typemap;
- C7 in `type_morespecific_`;
- the index from each set to its methods;
- the stopgap (C-18), with its volume measured;
- the ambiguity report with dominance;
- A4 (the query world carried in the query);
- A7 (the report's arity);
- D-M2-8's index entry.

**Changes:**
- Dispatch now gets memberships from subtyping itself. So the composed-match arms in `typemap.c` and `gf.c` go.
- A match's world range comes from `jl_membership_world_range` (uncommitted `subtype.c:1391`).
- The order between two sets is `jl_typename_reaches` (`subtype.c:1280`).

**Dropped:** A2. With no wrapper types, the case does not exist.

**Added by the draft:** an intersection ranked above each component, and the report naming `f(::All{…})` (§5.2, §5.4). Both move to N2 with `All`.

**Gate:**
- the old criteria: the m2 gates, a lookup in 200 methods within 2×, the suites inert, the stopgap's volume on a scripted shape;
- **gate B becomes a build gate.** The user has adopted the premise, so no adoption is decided here. A gate that fails becomes an open issue against the draft.

### W-100, stage 3: the facts policy and the record

**Old:** the todo row W-100; old compiler §7.6, facts §6.5; synthesis §4 stage 3.

**Stays** (draft compiler §1, §2, §3.1, §3.2, §11; facts §2–§8, §13):
- first, a build from scratch with stage times, and the smallest Compiler change alone;
- then the slices:
  - the policy gate;
  - the module and method flags;
  - the record's kinds and their consumers;
  - G2 as a predicate;
  - `return_type`'s rule;
  - the changes to the inliner.

**Changes:**
- **The module flags** also store `bounded`, `no_pirates`, `dynamic` and `first_seen` (§2.1). Their consumers come with N5 and N6.
- **The record's kinds** include membership cells and positive memberships (§3.1). Their producers come with N7, and the edges of a derived `Callable` membership with N8.

**Dropped:**
- `fold_call` and `known_type`. The draft gives them no user: the analysis's ledger, §3 ("family builders", "`known_type`'s use at the entry"); neither name occurs in `reference-unified/`.
- `split_call` and its table move to N4. Their inference does not need the facts policy.

**Gate:** unchanged:
- the acceptance cases, plain and under `all`;
- the share of the G2 bit;
- Base's suites;
- `detect_ambiguities(Base)`.

**The order changes:** this stage is off the first slice's path (S1). Its risk is the build that hangs. A probe of that risk (the build from scratch and the one-bit Compiler change) can take the first free build slot after W-99.

### W-101, stage 4: the code slot

- **Unchanged:** draft compiler §3.3, facts §4.3; E-261 justifies it.
- **Placed:** after W-100, off the slice's path.

### W-102, stage 5: keys, attributes, guards, the check; gate C

**Old:** the todo row W-102; old compiler §7.4, §7.5; synthesis §4 stage 5.

**This row is retired** and split into N4 to N8 (§5). Under the draft it holds work of very different risk and value:
- **The operation rule and the split** (§6.8, §7.1–§7.3, §8): small. Most of it exists on julia-1.13: part (D), piece 18, the per-call-site cache.
- **Keys and the definition-time check** (§6.1, §6.2, §6.5–§6.7, §10.3, §10.4): the old core of stage 5. The hand-written prototype stays its first step.
- **The attribute** (§6.3, §6.9): new. Five steps, casts, `keep`, `first_seen`, `dynamic`.
- **Guards and cells** (§5.6, §6.4's cells per (key, function)): as before, plus the cells of §6.4.
- **`Callable`** (§7.4): new. Its memberships are derived from the method table.

**Dropped** from the old row:
- `convert(Kept{X}, x)`;
- the wrappers' dispatch;
- the gate item "`Vector{Kept{X}}` as U2";
- "TraitWorld's suite on the compiler's keys" (the library is new, S5);
- `Keyed`'s rules, renamed `TraitKey` (P-12).

**Gate C** becomes build gates, one for each piece.

### W-103, stage 6: the surface and images

**Old:** the todo row W-103; old compiler §7.8; synthesis §4 stage 6.

**This row is retired** and split:
- **N3: images and hooks.** Memberships on foreign `TypeName`s listed in an image and activated before validation (§9); the contract and the open bit saved; the definition and image hooks (§10.1); a hook at a module's end (weak point 6). The old gate goes with it: two packages in a fresh depot.
- **N9: the rest of the surface:**
  - strict mode and `no_pirates` (§10.2; traits §12; lowering §13);
  - compiling ahead (§9; lowering §12);
  - printing and hints (traits §11.4, §15);
  - BaseTraits (lowering §10);
  - concreteness and fully typed mode (traits §14);
  - `verify_main` (traits §16).

**The order changes:** images move before any package declares a membership. The synthesis plan already rated this risk "latent from stage 1" (§7, R-7).

### W-104, stage 7: workloads and the ports' cases

**Old:** the todo row W-104; synthesis §4 stage 7.

- **Stays:** the ports' cases (W-83, the evidence plan's E2), each against plain Julia's results and the evidence. Written after the prototypes review and after N3.
- **Moves:** the two workloads, one shaped like `Column` and one like `ODEAlgorithm`, go to N1, where they gate the first slice.
- **Dropped:** "level 3 decided on paper". The draft has decided it: methods classified per argument, `bounded`, scopes as bundles of options (Q2 (a), decisions §9).
- **Gate:** unchanged in shape:
  - results identical to plain Julia's;
  - code compiled per key, not per member;
  - the sessions against [the evidence](../design/evidence.md) §3.

---

## 2. The work on branch `unified`

**Committed:** 2a2b2ba749, efb87dfbdf and c3f0b4bc11, +2,627/−171 lines.

**Uncommitted:** `subtype.c`, `builtins.c` and `jl_exported_funcs.inc` (+347/−662 across the three). The tree does not build: `typemap.c:553, 572, 915` and `gf.c:3798, 5409` still call the removed `jl_membership_match_sig` and `jl_membership_match_range`.

| Where | Survives unchanged | Rework | Unneeded |
|---|---|---|---|
| `julia.h`, `jltypes.c` | the bits `open_set` and `never_member`, with the kinds, opaque closures and memory types; `memberships` on `TypeName`; `Core.MembershipEntry`; the 32-bit memo word | the entry's `key` field stays unused until N5 | `generic_wrapper`; `Core.Keyed`, `Dynamic`, `Compiled`, `Kept` (`jltypes.c`, `base/boot.jl`'s constructors); the 15-bit `open_set_epoch` |
| `datatype.c` | the publication of `jl_declare_membership` (`:218`), its validation, the stopgap's call (`:295`) | the cycle check: 8 hops over the first entry (`:247`) becomes `jl_typename_reaches` (C-23); setting the task's world (`:304`) goes (C-25); `jl_set_open_set` refused once the binding is published; one instance per member (§4.6) | the epoch machinery (`:109`–`:144`) |
| `builtins.c` (uncommitted) | the hook of `_setsuper!` dropped; a set's supertype is `Any` or a set; each builtin's type `never_member` (C-24) | — | — |
| `subtype.c` (uncommitted) | the in-walk rule: `subtype_membership` (`:1240`), `subtype_entry` (`:1209`), `intersect_membership` (`:4284`), `jl_typename_reaches`, `jl_membership_world_range`; `jl_isa`'s type-value path reads only `Type{S}` entries (C-19); no fixed bound on pattern variables (C-21); `could_join`; the gates of `has_open_set`; C7 | prune entries by reachability before counting choices (weak point 9); the query world in `jl_stenv_t` (A4) | the wrapper arms (`:1939`, `:1960`, `:2536`, `:6031`; `could_join`'s `:1422`, `:1466`); `subtype_keyed` and `keyed_erased_set` (the erased key is `X{p…}` itself, §6.1) |
| `typemap.c` | the linear placement of methods at sets | world ranges from `jl_membership_world_range` | the composed-match arms (`:553`, `:572`, `:915`) and the `future_min` bound |
| `gf.c` (+1,208) | `invalidate_intersecting` extracted; the index from each set to its methods; the replay `jl_membership_dispatch_walk` (`:3818`, C-18); the GC roots | `membership_superset_sets` (`:3541`) by reachability; the report's query arity (`:6073`, A7); the per-thread query world (`:472`–`:615`, `:1232`) carried instead (A4) | `jl_membership_match_range` in `ml_matches_visitor` (`:5409`) |
| `codegen.cpp`, `cgutils.cpp`, `Compiler/src/*.jl` | refusing folds of `isa` and `<:` for pairs a membership could change; the negative-fold gates (§4.8) | `tmeet` (A10) | the wrapper cases |

**The draft's deviations:**
- **C-18 stands** until N7.
- **C-19, C-21, C-22, C-26:** the uncommitted rule addresses them; probes P1, P3, P4, P7 and P8 confirm it once the tree builds.
- **C-23, C-25:** still to do in `datatype.c`.
- **C-24:** addressed by the uncommitted `builtins.c` (probe P6).
- **C-20:** retires by deletion, not by the fix the audit proposed (A2).

The session note's list "still to do for W-98" stands: the header edit, `jltypes.c`, `datatype.c`, the callers in `gf.c` and `typemap.c`. Add to it the deletions above.

---

## 3. What the draft needs that no stage covers

| Item | Draft | Placed in |
|---|---|---|
| The library: `@trait` (an open type, its contract, the trait's method per operation, supertraits as memberships), `@implement` (checks, block, `by`, entry, `Expr(:latestworld)`), `Core.membership(T, X)`, `like`, `withfields` | lowering §2, §3, §5, §8; traits §4, §5.1–§5.7, §6.5 | N1 |
| `Dynamic{X}` as an ordinary struct with a membership; `unwrap`, equality, `show` | traits §7.7, §8.3; lowering §7 | N1 (see weak point 3) |
| A set's contract on its `TypeName` | compiler §4.1 | W-98 (the field), N1 (written), N4 (read) |
| One instance per member | compiler §4.6 | W-98 |
| `All{X, Y, Z, …}` with its rank and the report's joint method | compiler §4.9, §5.2, §5.4; traits §3.6 | N2 |
| A hook at a module's end (`struct S <: X` without `@implement`, classification left for later) | traits §5.2, §13; lowering §6 | N3 |
| Memberships, contracts and check records in images | compiler §9; lowering §11 | N3 |
| A declared result on `Method`, and the trait's method covering every member | compiler §6.8 | N4 |
| The members' index per set (the candidates) | compiler §7.2 (P-15) | N4 |
| `TraitKey`; compilation per key and per type; the calling convention; the adapter; field-offset intrinsics | compiler §6.1, §6.2, §6.5, §6.6, §10.3 | N5 |
| The classification and the `bounded` option | compiler §6.7; traits §7.3 | N5 |
| The member hook | compiler §10.4; lowering §4 | N5 (see weak point 4) |
| The attribute: five steps, `Core.attributed_call`, `keep`, `first_seen`, `dynamic`, the trait's default | compiler §6.3, §6.9; traits §7.4–§7.8 | N6 |
| Cells per (key, function) for calls from per-key code | compiler §6.4 | N7 |
| `Callable`'s derived memberships and its call | compiler §7.4; traits §9 | N8 (after weak point 1) |
| BaseTraits, hints, `verify_main`, concreteness, printing of keys | traits §10, §11.4, §14–§16 | N9 (keys' printing: N5) |

---

## 4. Simplifications

**S1. The premise first, speed later.** A first slice runs the language with Julia's own rule, code per type, before any keys, attributes, splits, guards or facts policy.
- **Saves:**
  - The slice adds no Compiler change beyond the fold gates the branch already builds. So the hang in the system image's build (synthesis §7, first risk) is off the critical path.
  - The user sees the premise run on real-shaped code after three stages, not seven.
- **Costs:**
  - The slice is slower: it dispatches at run time at slots typed by a trait, and memberships invalidate by the stopgap.
  - Its typed results come only through `Dynamic{X}`: the trait's method carries Julia's own return annotation, which types every call that reaches it.
  - The facts option of `@trait_module` is a no-op until W-100 (a deviation row).

**S2. Memberships without keys.**
- Entries say who is a member. Keys go in a table per (member type, set), filled by `@implement` for concrete members and by the runtime for members of a pattern (weak point 4).
- **Saves:**
  - W-98 needs no design of keys.
  - `struct S <: X` and members of a pattern get keys by one mechanism.
  - It removes the draft's conflict between compiler §4.2 ("needs no entry") and §6.1 ("`S`'s entry … has that key").
- **Costs:** a second list on `TypeName`, with world ranges for a redeclared key.

**S3. `All` as its own stage after W-99** (N2), not inside W-98.
- **Saves:** W-98 lands on code that is already mostly written. The risk of `All` is a new type constructor in subtyping, intersection, specificity, the type cache and serialization; it is isolated and measured on its own.
- **Costs:** the first slice has no several bounds on one argument and no bundles. Neither workload needs them; the ports do (`NWState(int::All{…})`).

**S4. Delete, do not fix.**
- Drop the Core wrapper types, `generic_wrapper`, `Keyed`, the composed-match arms and their `future_min` bounds.
- **Saves:**
  - the audit's high finding A2;
  - about ten arms across `subtype.c`, `typemap.c` and `gf.c`;
  - two gates.
- **Costs:** none in the draft.

**S5. A new library, not a migrated TraitWorld.** The draft's lowering is about 250 lines of reference. The library is written from it.
- **Saves:**
  - the old stage 5's migration of TraitWorld's entries, workers and views (about 6,000 lines by the exploration's count);
  - the per-stage table of retired L- and T- rows (synthesis §5).

  TraitWorld stays the prototype on julia-1.13.
- **Costs:**
  - the checks and their messages are rewritten (TraitWorld's code serves as a source);
  - the ports move to the new library, which the user has accepted.

**S6. The attribute without a new generic call.**
- Bits travel only through `Core.attributed_call`, which has a cache of its own: casts, and the attribute an argument carries out of code compiled once into a run-time site.
- A plain dynamic call resolves steps 3 to 5 at the method. That is a function of (method, tuple, module option).
- **Saves:** `jl_apply_generic_attr`, and keying the leaf cache and the per-call-site cache by bits (compiler §6.3, §8.2). The hot generic call path stays Julia's.
- **Costs:** codegen emits `attributed_call` at run-time sites that pass an argument on with its attribute.

**S7. Cherry-pick, not rewrite.** The draft keeps these unchanged from julia-1.13, so they move by their commits (`../design/julia-changes.md` §1–§3):
- `:caller_world` (piece 18);
- `split_call` and its table (D);
- the field-offset intrinsics (3);
- the per-call-site cache;
- the hooks;
- the inliner's two general fixes.

- **Saves:** design and review time in N4, N5 and W-100.
- **Costs:**
  - conflicts where those commits touch the two-owner code;
  - C-3's capping comes along unless fixed on the way.

**S8. W-100 trimmed.** `fold_call` and `known_type` go; the split moves to N4.
- **Saves:** two of the seven slices.
- **Costs:** none.

**S9. Guards measured before they are built** (decision for the user, weak point 13).
- If the stopgap's volume on N1's workloads and on the ports' sessions is small, guards could become Optional and the stopgap the design.
- **Saves:** the shadow query, the cells and codegen's guards: the largest piece of compiler work after keys.
- **Costs:** facts §10's "a membership invalidates nothing" becomes "a membership invalidates what it changes", a stakeholder's change under G2.

---

## 5. The proposed stage list

**Rows:**
- **Rewritten in place:** W-98, W-99, W-100, W-104.
- **Unchanged:** W-101.
- **Retired:** W-102, each pointing to N4–N8; W-103, pointing to N3 and N9.
- **New:** N1 to N9, placeholders for new W- IDs.

| ID | Row | Scope | Gate | Draft |
|---|---|---|---|---|
| W-98 | rewritten | Finish the uncommitted rule; delete the wrappers and `Keyed`; the cycle check, open from its declaration, no epoch, no world set by the runtime; one instance per member; the contract's field; pruning by reachability | probes P1–P8 as gates; m1/m2 re-pinned; Base's suites within 10 %; a query with many entries | compiler §4.1–§4.8, §4.10, §4.11 |
| W-99 | rewritten | Dispatch on the in-walk rule; match ranges; A4; A7; the stopgap logged | m2 gates; 200 methods within 2×; the stopgap's volume; gate B as a build gate | compiler §5.1–§5.5 |
| N1 | new | The library core (§3, first rows); `Dynamic{X}`; `struct S <: X`; checks at the declaration; two workloads in scripts (`--compiled-modules=no` for a package that declares a membership until N3) | results equal a plain-Julia version's and TraitWorld's; acceptance cases for F1–F8, F10, F11, F14; the stopgap's volume on the workloads; no new Compiler change | traits §3–§6, §7.7, §8; lowering §2, §3, §5, §7, §8 |
| N2 | new | `All`: subtyping on both sides, intersection, rank, a normal form independent of the world (weak point 2), hash and serialization, `show`, `@implement (X, Y) S`, the joint method in the report | a battery for `All` with `UnionAll`, `Union` and `Vararg`; dispatch with `All` bounds; suites within 10 % | compiler §4.9, §5.2, §5.4; traits §3.6 |
| N3 | new | Memberships, contracts and records in images; the definition and image hooks (cherry-picked); a hook at a module's end; the override records | two packages in a fresh depot, both load orders, an image older than the extension; a missing `@implement` refused at the module's end | compiler §9, §10.1; traits §5.2, §5.11; lowering §11 |
| N4 | new | The declared result on `Method`; the operation rule; the members' index; the split and its table; `:caller_world`; the per-call-site cache (cherry-picked) | typed results at slots typed by a trait; a late member takes the table and invalidates nothing; `TypeError` on a wrong result; julia-1.13's cases for the split | compiler §6.8, §7.1–§7.3, §8; traits §7.9 |
| W-100 | rewritten | The policy per method and the record, trimmed (S8); the probe of the hang first | as before | compiler §1–§3.2, §11; facts §2–§8, §13 |
| N5 | new | Keys: the hand-written prototype, then `TraitKey`, the compilation signatures, the calling convention, the adapter, the intrinsics, the key table, the classification and `bounded`, the check of a pattern's member at its first use, keys' printing | the old W-102's key gates (one CodeInstance per key; E-164's band; the adapter under E-256; O(keys) per new member; E-215; the writable-field kernel); `TraitUseError` lists every use | compiler §6.1, §6.2, §6.5–§6.7, §10.3, §10.4; traits §7.1–§7.3, §15 |
| N6 | new | The attribute: the steps, `attributed_call` (S6), `keep`, the module options, the trait's default | one case per step of traits §7.5; identical results under every attribute | compiler §6.3, §6.9; traits §7.4–§7.8 |
| N7 | new | Guards and cells, membership cells and cells per (key, function); C-18 retires (or Optional, S9) | the old W-102's guard gates; U9's census; the volume against W-99's | compiler §5.6, §6.4; facts §10 |
| W-101 | unchanged | The code slot | the synthetic cascade; the session count | compiler §3.3 |
| N8 | new | `Callable`, once weak point 1 is decided | dispatch by signature; a definition that ends a membership; the erased call | compiler §7.4; traits §9 |
| N9 | new | Strict mode, `no_pirates`, compiling ahead, BaseTraits, hints, concreteness, `verify_main` | julia-1.13's strict-mode cases; compiling ahead in a two-package session; a closed program | traits §10–§12, §14, §16; lowering §10, §12, §13; compiler §10.2 |
| W-104 | rewritten | The ports' cases, after the prototypes review and N3 | as before | — |

**The order:**
1. W-98, W-99, N1: **the first slice.**
2. N2, N3: the ports can begin.
3. N4, W-100, N5, N6, N7, W-101, N8, N9: speed, stability and the surface.
4. W-104.

N4 needs neither W-100 nor N5. W-100 and N5 may swap.

**Where the risk sits, and what comes first because of it:**
- **On paper, before any build:**
  - weak point 1 (`Callable`), the user's;
  - weak points 3, 4 and 7, choices of mine in the draft (P-4, P-5, P-12, P-18) that this plan would change: for the user to confirm;
  - the reference fixes of weak points 2, 5, 6, 8, 11, 12 and 14.

  These change what N1, N5, N6 and N8 build.
- **In the build:** `All`'s subtyping is the highest risk of the slice's neighbours. If it fails, Q5 reopens. So N2 begins with a short probe of subtyping and normalization alone.
- **The hang in W-100:** its probe takes a free build slot early. It decides nothing about the premise.
- **Keys:** the hand-written prototype stays N5's first step, as in the old plan.

---

## 6. Weak points

Each gives the case, the rule that blocks it, and a proposal.

1. **`Callable`'s derived memberships need inference inside subtyping.** **No principled option keeps every property the draft states; the user decides.**
   - **The case:**
     - `apply(sqrt)` against `apply(f::Callable{Tuple{Int}, Int})` asks `typeof(sqrt) <: Callable{Tuple{Int}, Int}`. Per compiler §7.4 (`:566`, `:569`), that runs plain inference of `sqrt` at `Int` inside `jl_subtype`.
     - `jl_subtype` also runs during method insertion's walk under the world counter's lock, inside the typemap's traversal, and in regions that may not run Julia code.
     - A body that calls `apply(f)` needs `f`'s result in order to infer `f`: the derivation is circular.
   - **A false claim:** traits §9 (`:796`) and facts §10 (`:335`) say a derived membership ends "only by a definition of `F`'s methods". It does not: an inferred result changes with any callee's redefinition, and with inference's limits.
   - **Options:**
     - **(a)** `S` from the declared result of the method selected at `A` (compiler §6.8). This changes only with `F`'s methods, needs no inference, and keeps the claim true. A function without a declared result is a member of `Callable{A, <:Any}` only, so lambdas need annotations.
     - **(b)** A hook at run time derives the membership into a stored entry, with edges like a CodeInstance's. Subtyping reads only stored entries. Inference treats a pair not yet derived as one that could join: a guard or a run-time site. The claim in traits §9 and facts §10 is corrected.
     - **(c)** Dispatch by `A` only, which is a question of the method table. `S` is asserted at the call. This is the analysis's Q6 (a) with dispatch by arguments.

2. **Normalization depends on the world.**
   - **The case:**
     - `Union{S, X}` is normalized through `simple_subtype` → `jl_subtype` (`jltypes.c:566`–`578`), and `All`'s normal form absorbs subtypes (compiler §4.9, `:326`).
     - Both now read memberships, so the same expression gives different type objects before and after `@implement X S`, or before and after a membership of a set in a set.
     - Such a fold of a positive does not raise the CodeInstance's `min_world`, which §4.8 requires.
   - **The proposal** (mine, to confirm, since it narrows `All`'s stated normal form):
     - Normalization never absorbs through a membership. It uses only declared supertypes and the disjointness of closed types.
     - `@trait B <: A` with one supertrait may make `A` the declared supertype, which holds from `B`'s birth.

3. **`Dynamic{X}`.**
   - **The pattern misses intersections.** Lowering §2 (`:63`) declares the family `Dynamic{X{P…}} where {P…}`. Parameters are invariant, so `Dynamic{All{X, Y}}`, which traits §3.6 and §7.7 use, is a member of nothing.
     - The proposal: the pattern `Dynamic{A} where {A <: X}`. Membership in subtraits and intersections then follows by transitivity.
   - **`Core` would name a type of the library.** `Core.keep` and `Core.attributed_call` construct or unwrap a `Dynamic{X}` (compiler §6.9).
     - The proposal: `Dynamic` is an ordinary struct defined in `Core`, still with no rule in subtyping, its membership declared by `@trait`. This changes P-5 (mine): to confirm.

4. **Keys are underspecified.**
   - **The case:**
     - **`struct S <: X`:** it "needs no entry" (compiler §4.2, `:260`), yet `S <: TraitKey{X, R, F}` "holds when `S`'s entry … has that key" (§6.1, `:416`).
     - **A member of a pattern** gets its key only from the member hook at run time, and "inference never calls it" (§10.4, `:688`). So code compiled before that member's first use at run time keeps a run-time site: precompiled code included, and with BaseTraits every `AbstractVector`.
     - **`subtype` against a `TraitKey`** would change its answer when the hook runs, with no world.
   - **The proposal** (changes P-12 and P-18, mine: to confirm):
     - The runtime computes a key from the membership and the contract alone: receiver, fields' types, parameters. That needs no Julia code.
     - Keys go in their own table (S2).
     - `TraitKey{X, R, F} <: X` is the only rule of subtyping for it. The leaf cache maps each tuple to its keyed instance explicitly.
     - The hook shrinks to the check at first use. It runs from the compile queue before a CodeInstance that relies on the member is published, with a failing check compiled as the error. Inference already runs user code in generators, which is the precedent.

5. **Operations at a key.**
   - **The case:**
     - The trait's method finds a forwarding field through `Core.membership(typeof(t), X)`, "a constant where the type is known" (lowering `:50`).
     - At a `TraitKey`, the type is not known. Members that share a key may forward through fields of different names.
     - No inference rule says how `col(t, i)` with `t::TraitKey{X, R, F}` reaches the parts of §6.5.
   - **The proposal:**
     - Two intrinsics, `Core.trait_receiver(t, X)` and `Core.trait_field(t, X, name)`. Inference resolves them to the parts at a key, and to `getfield` at a member.
     - The trait's methods are written with them.
     - Or the forwarding field's name becomes part of the key, at a small loss of sharing.

6. **Julia has no hook at a module's end.**
   - **The case:** traits §5.2 and §13, and lowering §6 ("Julia's hook", `:127`), rely on one.
   - **The proposal:**
     - a callback at the end of `jl_eval_module_expr`, in N3;
     - for packages, also while the image is written.

7. **Casts are recognized by their name.**
   - **The case:** lowering §7 (`:148`) has the front end recognize `compiled_for(x)` in a call's arguments. Lowering cannot know that this name is `Core.compiled_for`: bindings resolve later, and a local name would shadow it.
   - **The proposal** (P-4 is mine; the spelling is the user's to confirm):
     - a macro at the call, `@cast f(compiled_for(x), y)`, expanding to `Core.attributed_call`;
     - or lowering emits a check of the binding that inference folds.

8. **`jl_apply_generic_attr`** (compiler §6.3, `:450`) changes the generic call path and both dispatch caches for a choice of speed. The proposal is S6.

9. **The cost of subtyping when a chain carries many entries.**
   - **The case:**
     - `subtype_membership` (uncommitted, `:1240`) counts every live entry on the chain and tries each as an existential choice. Julia retries a choice by re-running the whole query, so a non-member costs a full run per entry, and the cost multiplies through chains of sets in sets.
     - BaseTraits' families on `AbstractVector` and `AbstractDict` put many entries on common chains.
   - **The proposal:**
     - count only entries whose set reaches `y` (`jl_typename_reaches`, already there);
     - memoize reachability per pair of `TypeName`s and world range;
     - a gate in W-98.

10. **Every `Type{S}` entry lives on `Type`'s `TypeName`.** That is one list for the whole session, scanned by every `Type{T} <: X`.
    - **The proposal:** keep such entries on `S`'s `TypeName`, marked as being for the type value.

11. **One instance per member has two homes.**
    - **The case:** compiler §4.6 (`:295`) puts the check in the runtime; lowering §3 puts it in the library. For a pattern, the check is a question of unification that neither states.
    - **The proposal:**
      - the runtime checks it: exactly for a concrete member, and for a pattern by intersecting it with each pattern that already reaches the set;
      - the library reports.

12. **`All` with a closed component and C7.**
    - **The case:** where `S <: B` (closed) and `S <: All{X, Y}`, compiler §5.2 does not say which method is more specific.
    - **The proposal:** an `All` ranks as its most specific component, so a closed component makes it closed for C7.

13. **Guards or the stopgap.** This is a choice of design, the user's (S9).
    - Measure first: W-99 on a script, then N1 on the workloads.

14. **The classification is stored as bits of the `Method`.**
    - **The case:** it depends on the same module's unannotated callees (compiler §6.7), and a callee's redefinition changes it.
    - **The proposal:**
      - The classification is a result of inference at the erased signature, with edges.
      - `bounded`'s refusal runs at the definition and again at the module's end (weak point 6).

**Small inconsistencies, for the reference's next pass:**
- compiler §2.1 says "Three more options" (`:126`) and lists four;
- the conflicts named in weak points 1 and 4.

---

## 7. If the user agrees

None of this is done; this plan edits nothing. If the user agrees, these follow:
- **In `../record/todo.md`:**
  - W-98, W-99, W-100 and W-104 rewritten;
  - W-102 and W-103 retired, each pointing to its new rows;
  - N1 to N9 registered under new W- IDs.
- **The status lines** in `../reference-unified/` that name W-102 and W-103, updated to the new IDs.
- **Weak points 1 to 14:**
  - each as an open issue;
  - or as a fix to the draft;
  - or, for a choice of mine the plan changes, a row in the decision log marked mine, for the user to confirm.
- **`../state.md` §6.3:** the order in brief.
- **Rows E- for each gate**, before its run.
