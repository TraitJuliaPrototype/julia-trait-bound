# Building the unified design into Julia from the upstream base

Status: **exploration** (2026-10-29, a fresh-eyes Fable agent; not adopted). Not normative. Serves W-83 and W-27. **Its decisions D1–D9 are decided through [the synthesis plan](../plans/2026-11-05-unification-synthesis.md) (the user, 2026-11-06), with [the review's](../reviews/2026-10-29-unified-build-review.md) corrections: the intended design is [compiler §7](../reference/compiler.md#7-traits-in-the-type-system). Where this document differs (§2.3's intersection, §2.4's C7 placement, §3.3's codegen sentence, §3.8's revalidation, D1's order, D3), the reference holds.**

The user's question (2026-10-29): "I want a fresh eyes Fable agent to think about how to build this (especially the type system and compiler changes) together with the caching of machine code, from a vanilla Julia base. This is not an incremental change but a fundamental reframing."

**What is taken as decided** (not relitigated here): the framing of five co-designed features on two foundations ([abstract-types-as-traits §15](abstract-types-as-traits.md#15-the-project-as-a-set-of-co-designed-features)); memberships and dispatch under option (e) ([compiler §7.1](../reference/compiler.md#71-memberships-and-dispatch), Planned; [decisions §5](../record/decisions.md), 2026-10-29); the evidence E-252 to E-259 ([experiments §12](../record/experiments.md#12-unification-w-83)). The semantics to build are the references' ([traits](../reference/traits.md), [facts](../reference/facts.md), [compiler](../reference/compiler.md), [lowering](../reference/lowering.md)).

**What is read as evidence, not as a constraint:** the patched Julia (`julia-1.13/`, 65 commits on v1.13.2, [julia-changes](../design/julia-changes.md)) and TraitWorld's encoding ([lowering §17](../reference/lowering.md#17-encodings-until-traits-are-in-the-type-system), L-1 to L-50; 13,565 lines in `TraitWorld/src`). No Julia ran. Upstream files are cited at the base of the patched branch, `45b6d15e34` (v1.13.2); line numbers are of that commit, read with `git -C julia-1.13 show 45b6d15e34:<path>`.

## Contents

0. [Summary](#0-summary)
1. [The frame: each feature as a Julia mechanism](#1-the-frame-each-feature-as-a-julia-mechanism)
2. [The type system](#2-the-type-system)
3. [Dispatch and the compiler](#3-dispatch-and-the-compiler)
4. [Caching machine code](#4-caching-machine-code)
5. [The scope declarations](#5-the-scope-declarations)
6. [The build path from upstream Julia](#6-the-build-path-from-upstream-julia)
7. [Risks and open questions](#7-risks-and-open-questions)
8. [Where this departs from the project's current assumptions](#8-where-this-departs-from-the-projects-current-assumptions)
9. [Suggested record changes](#9-suggested-record-changes)
10. [Sources](#10-sources)

---

## 0. Summary

**The central proposal.** Build the five features as five extensions of mechanisms upstream Julia already has, and let one new data structure carry the caching goal: the *dependency record* of a CodeInstance.

- **A set** (an abstract type with declared, possibly late membership) is a `TypeName` with an `open` flag and a membership list; `jl_subtype` consults the list when the supertype chain fails and the right-hand side is open. Entries carry a `min_world`, as methods do. Negatives never fold for open sets; Core's kinds are never members; Base's sets are closed.
- **A key** (what a bound can see of a value) is a *refinement set* of the trait: `Keyed{X, R, F}`, a set whose members are the members of `X` with receiver `R` and declared field types `F`. Per-key specialization is then Julia's own "compile at a supertype of the dispatch tuple", the mechanism behind `@nospecialize`, with `jl_compilation_sig` mapping a member's concrete type to its key. One `MethodInstance` per key; the leaf cache maps each concrete tuple to it. The worker takes the value's *projection* (receiver and declared fields) in its calling convention; the adapter from the boxed value is the wrapper codegen already generates per specialization. No entries, no views, no witnesses.
- **`Dynamic` is `@nospecialize` with a declared contract:** a `Dynamic` position is compiled at the erased key, operations on it are the call-site split. `Compiled` is specialization at the key. The attribute rule is the choice of compilation signature, per position.
- **A bounded method is a Julia method at the set.** Dispatch is Julia's. Under option (e), a membership lowers the `max_world` of dispatch-cache entries it changes (as a method insertion does) and invalidates no code; a compiled call at a type that could still join a set carries a guard reading a per-(type, set) cell in the caller's world. The tie order C7 lives in `ml_matches`, not in `jl_type_morespecific`.
- **Compiling by facts is an inference policy per method** (upstream's `concrete_only` flag is the precedent: "inference refuses to commit (records no backedge) at non-concrete call sites", `src/julia.h:564`), and **G2 is a property computed from a CodeInstance's dependency record**, not from a cache owner. The record names facts (dispatch at concrete signatures), result edges to callees, the lowered code inlined, layouts read, bindings, folds, membership cells. With *result edges that revalidate* instead of invalidate (red-green, reusing `reinfer.jl`'s `verify_method_graph` in the session), facts code may hold edges to plain callees, and the second cache owner's volume (facts copies of Base) goes away. The owner token stays only as the session discriminator where one method is compiled under two policies.
- **Caching machine code** is then a store of CodeInstances whose records are complete and environment-free, identified by content fingerprints (W-66's F1 to F3, extended), relinked at load *by stable names* rather than by build ids, validated by `verify_method_graph`, and promoted into the session's caches by the loader's existing path. That is a new relocation kind in `staticdata.c` and a new image flavour, not a new compiler.

**The stages** (§6), each useful and testable alone: S0 the facts policy and the dependency record, rebased onto upstream as a PR series; S1 memberships in the type system (the plan's P1); S3 keys as refinement sets and the projection convention; S2 one dispatch under (e); S4 the machine-code store; S5 the language surface. S3 comes before S2 because a method at a set needs per-key code from the compiler, and S3 removes the largest part of the encoding (entries, views, the rewrite: lowering §5 to §9, L-1, L-2, L-3, L-6, L-36, T-94).

**The decisions for the user** are in §9: the stage order; the key's shape (projection, or offsets in the key); the policy as a method property with result-edge revalidation in place of a second owner; memberships advancing the world counter; the cost of a bounded method on an open set at its definition; the store's vehicle (machine code relinked by name) and its exclusion of `Main`; `Callable` on `OpaqueClosure`'s representation; declared result types recorded on methods.

---

## 1. The frame: each feature as a Julia mechanism

The reframing in one table. Each feature extends something upstream has, so each stage is a change to a named place, not a parallel system.

| Feature | Upstream mechanism it extends | Where | What changes |
|---|---|---|---|
| 1. Abstract types as traits (declared, late membership) | `DataType.super` and the chain walk in `subtype` (`src/subtype.c:1535`, `:1580`) | `jl_typename_t`, `src/subtype.c`, `Compiler/src/tfuncs.jl` | a membership list per `TypeName` with worlds; a fallback in `subtype`; no negative folds for open sets |
| 2. `Dynamic{X}` | `@nospecialize`: compile at a supertype of the dispatch tuple (`jl_compilation_sig`, `src/gf.c:1170`; `get_compileable_sig`, `Compiler/src/abstractinterpretation.jl:159`) | `src/gf.c`, `Compiler` | the erased key as the compilation signature of a `Dynamic` position; the split at operations |
| 3. `Callable` | `OpaqueClosure`: a function value at a declared signature with a compiled pointer (`src/opaque_closure.c`) | `src/opaque_closure.c`, `src/codegen.cpp` | a world-following variant: the pointer checked against the caller's world, as the patched `:caller_world` convention does |
| 4. Compiling by facts | `TypeName.concrete_only` (`src/julia.h:564`; `is_concrete_only`, `Compiler/src/inferencestate.jl:1127`; used by `broadcasted`, `base/broadcast.jl:197`) and `CodeInstance.edges` | `Compiler/src/abstractinterpretation.jl` (`find_method_matches`, `:365`), `typeinfer.jl` (`store_backedges`, `compute_edges!`) | the policy per method; run-time sites; the dependency record with result edges and inlined-code identities |
| 5a. Declared facts scope | module compiler options (`jl_module_t.optlevel, compile, infer, max_methods`) and method flags (`Method.nospecializeinfer, constprop, max_varargs`) | `src/module.c`, `src/method.c`, `base/experimental.jl` | four options at module and method granularity |
| 5b. Bounded scope, keys | the compilation signature and codegen's per-specialization wrappers (`gen_invoke_wrapper`, `emit_call_specfun_other`, `src/codegen.cpp:5209`) | `src/gf.c`, `src/codegen.cpp`, `Compiler` | `Keyed{X, R, F}`; the projection convention; the check as an inference mode |
| 5c. Concretely typed | the `nortsite` effect bit (patched W-52) | `Compiler/src/effects.jl` | a certificate read from the record |
| 5d. No pirates | the method-definition and image hooks (patched piece 1) | `src/gf.c`, `src/staticdata_utils.c` (`jl_activate_methods`, `:894`) | upstream hooks; the walk over the record |
| Caching | package images: `jl_write_values`, `jl_update_all_fptrs` (`src/staticdata.c:1367`, `:2269`), `queue_external_cis` (`staticdata_utils.c:521`), `verify_method_graph` (`Compiler/src/reinfer.jl:95`) | `src/staticdata.c`, `Compiler/src/reinfer.jl`, `base/loading.jl` | a relocation by stable name; an image flavour without a worklist; promotion into the session |

Two foundations run through the table: the trait declaration (features 1, 2, 3, 5b read it: operations with result types, fields, associated types) and ownership (features 4, 5d and the membership rule read it).

---

## 2. The type system

### 2.1 Sets and memberships

**A set is a `TypeName` with an `open` bit.** `jl_typename_t` has five unused bits (`uint8_t _unused:5`, `src/julia.h:560`). One becomes `open`: this set may gain members after its definition. `abstract type A end` leaves it clear; a trait declaration sets it. A closed set with a contract is allowed (Base's `AbstractArray` with a written contract, later): contracts and openness are separate properties.

**Where membership lives: on the member's `TypeName`,** not on the set's. Reasons:
- `subtype` walks from the left-hand side (`xd = xd->super`); the fallback walks the member's list, so the lookup is local to the type being asked about;
- a type has few memberships; a set may have thousands of members (BaseTraits over Base's vectors);
- a package image that declares memberships for its own types writes them with the types.

A membership entry is an immutable object:

```
MembershipEntry
  set        :: TypeName          # X
  member     :: Type              # the member pattern: S, or S{T} where T (a UnionAll for a family)
  instance   :: Type              # the set instance for the pattern: X, X{Float64}, X{T} (shares the pattern's variables)
  key        :: Type              # Keyed{X, R, F} for the pattern (§2.6); R and F may name the pattern's variables
  min_world  :: UInt              # the world in which it was declared
  declarer   :: Module            # for ownership and for the store's identity
  by         :: Symbol or Nothing # the forwarding field, or nothing
```

The list is a `SimpleVector` replaced copy-on-write (readers take no lock, as the patched registries do). The entry objects are stable: a guard's cell (§3.3) and the store's identity (§4) refer to entries, never to the vector.

**Worlds.** A declaration takes the world-counter lock, assigns `min_world = jl_world_counter + 1`, publishes the entry, and advances the counter: the same protocol as `jl_method_table_insert` (`src/gf.c:3204`). So a task in an older world does not see it (U8 part B, E-254), and the REPL's `invoke_in_world` answers as it does for methods. A membership is never removed: a struct redefinition makes a new type, and a redeclared implementation replaces the entry's `key` under the owner's rules (traits §4.9) with a new `min_world`, which is a stakeholder's change.

**Declaration.** `jl_declare_membership(member, set_instance, key, declarer)` in `src/datatype.c` beside `jl_new_abstracttype` (`:102`). `@implement X S …` lowers to the contract checks (Julia code, the library's) followed by this call. `struct S <: X` for an open `X` is `jl_new_datatype` with `super = X` as today, plus an entry whose `min_world` is the type's: such a membership is final (it cannot be undone), which is what "declared with the type" means in [compiler §7.1](../reference/compiler.md#71-memberships-and-dispatch).

**Ownership** is checked by the declaring code (the library), not by the runtime: the runtime records `declarer`. Strict mode's walk (§5) reads it.

### 2.2 Subtyping and `isa`

**`jl_subtype(S, X)`** (`src/subtype.c:2350`, the walk at `:1535` and `:1580`): where the chain reaches `Any` without meeting `X`'s name, and `X`'s name is `open`, consult `S`'s membership list for an entry with `set == X.name`; match `S` against the entry's `member` pattern with `jl_subtype_env`; instantiate the entry's `instance` in that environment; compare parameters as the chain case does (invariantly, `:1590` onward). A miss is `false`. The branch costs one flag read on the common path (`yd->name->open`), taken only after the chain has failed.

**Sets as members of sets** (`@trait B <: A`): `B`'s `TypeName` holds an entry `set == A`. `jl_subtype(B, A)` is then true by the same fallback, with `B`'s parameters mapped as the entry says (traits §3.6). A member of `B` is a member of `A` by its own entry (the design's rule); the runtime does not derive it.

**`jl_isa`** (`:2513`) follows `jl_subtype` for a non-concrete `t`, so it needs nothing of its own.

**Inference.** `isa_tfunc` (`Compiler/src/tfuncs.jl:877`) returns `Const(false)` on three paths: `isa(v, Const)`, `isdispatchelem(v)`, and `!hasintersect(v, t)`. Each becomes `Bool` when `t`'s name is open and `v` is not a *final* non-member of `t`. A final non-member is: a Core kind (`DataType`, `UnionAll`, `Union`, `Module`, `TypeVar`, the builtins, opaque closures, the memory types), or a type whose typename is marked `closed_member` (§2.8: Core's and Base's types never join a set? No: Base's *sets* are closed; Base's *types* may join a trait, as BaseTraits does, so they are not final non-members). `subtype_tfunc` (`:917`) likewise. `typeassert_tfunc` (`:859`) uses `typeintersect`, which §2.3 widens. U7 (E-255) measured the loss: 0.003–0.9 % of negative folds, none in a loop, provided the kinds are excluded.

**The compile-time positive** is kept: `S <: X` true at compile time stays true (memberships only grow), so `isa_tfunc` folds it to `Const(true)` with no edge. This is the one direction the whole design rests on.

### 2.3 Intersection, unions, ambiguity

**`jl_type_intersection(S, X)`** (`src/subtype.c:4699`; `intersect` at `:3818` walks `xd->super` for datatypes) returns `S` for an open `X` that `S` is not a known member of, never `Union{}`. Julia's own contract allows it ("usually this will be the smallest such type or one close to it", `base/runtime_internals.jl`). A known member keeps the exact result. `jl_has_empty_intersection` (`:4472`) says "not empty" for the same pair.

What this touches, and what it must keep:
- `ml_matches` (`src/gf.c:4926`) prunes methods with an empty intersection, then tests `jl_subtype`. With the wider intersection a bounded method `f(::X)` is *considered* at `(S,)` and rejected by `jl_subtype`. That is one more subtype call per bounded method of `f`, at the first call per signature (the result is cached).
- `jl_method_table_insert` (`:3204`) finds the specializations a new method may affect through `get_intersect_matches` (`:2064`) and intersection with `specTypes`. With the wider intersection, inserting `f(::X)` reaches every specialization of `f` at a type that is not a final non-member. §3.2 says what it then does with them.
- `Method.interferences` (`src/julia.h:333`) records methods whose signatures intersect and are not ordered. A method on an open set interferes with every method of the function at a non-final type. §2.4 orders the pairs that C7 orders; the rest are candidates for an ambiguity report.
- `jl_type_union` (`src/jltypes.c:650`, `simple_subtype` at `:566`) absorbs a member into a supertype by a positive `subtype`. `Union{S, X}` stays two members until the membership exists, and is the same set of values either way: sound.
- `jl_typeintersect`'s use in the type cache and in `Union` normalization never records a negative, so no cached type object encodes "not a member".

**Ambiguity between two open sets** (`f(::X)`, `f(::Y)`, `X` and `Y` unrelated): reported when a common member appears, at `jl_declare_membership`. The declaration knows `S`, the new set, and `S`'s other sets; for each function with a method on the new set and a method on one of the others, and no method on a tuple of both (traits §3.7), it reports. This is T-83's report, moved into the runtime, where it is order-independent. It is a warning by default (the call still raises Julia's ambiguity error), an error in a `no_pirates` scope.

### 2.4 Specificity and C7

`jl_type_morespecific(a, b)` (`src/subtype.c:5552`; the datatype case walks `tta->super` at `:5484`) is a relation between *signatures*. C7 is a rule about *how a given argument matched*: a type's own supertypes before memberships added later. It cannot be a property of two signatures alone (`Matrix{Float64}` orders `AbstractMatrix` before `ColTable`; another member might have `ColTable` as its only match). So C7 does not live in `jl_type_morespecific`. It lives in `ml_matches`:

- `jl_subtype_env` (`:2282`) gains an out-flag: whether a membership entry was used at any position. `ml_matches` keeps it per match (a bit in `jl_method_match_t`, `src/julia.h:947`).
- Among applicable methods that `jl_type_morespecific` leaves unordered, a match that used no membership at a position beats a match that used one there. Among matches that used memberships, the subset relation among sets (`jl_subtype(B, A)` by entries) orders them; otherwise they are ambiguous, and §2.3's report has already fired or fires at the first such call.
- `jl_type_morespecific` itself needs one addition: a set that is a member of another set is more specific than it (through the entry), so that `f(::B)` beats `f(::A)` for `B <: A` by declaration. Everything else about sets it treats as it treats unrelated abstract types: not ordered.

Where the dispatch result is cached (the leaf cache and the typemap cache, `jl_mt_assoc_by_type`, `src/gf.c:1984`), the C7 decision is cached with it, for the entry's world range. §3.2 says when a membership changes that range.

`detect_ambiguities` and `Test`'s ambiguity check compare signatures pairwise; a set against a tree type must count as ordered by C7 at every member, so these tools read the same flag: "this pair is ordered per argument by C7", which `Method.interferences` can record as a distinct state.

### 2.5 Parameters and associated types

A set's parameters are associated types: one value per member (traits §3.4). In the entry that is the pair (`member` pattern, `instance`): `Vector{T} where T` maps to `KVec{T}`; `MyVec` maps to `ArrayLike{Float32, 1}`. Subtyping reads it as it reads `super` for a parametric type: the pattern's variables are bound by matching the member, and the instance is instantiated with them. Invariance is then literal: `Vector{Int} <: KVec{Int}`, not `<: KVec{Real}`; `KVec{<:Real}` is a `UnionAll` as `AbstractVector{<:Real}` is.

**A parameter defined by an equation** (`T = eltype(Self)`) is evaluated when the member is known, never inside `jl_subtype`: at the declaration for a concrete member; for a family member, at the member's first instantiation, by the library's member check (the fold of W-40 today), which then declares the instantiated entry. So the runtime holds only patterns and values; no Julia code runs under the subtyping lock. A family whose equation cannot be written as a pattern over the family's variables declares members lazily, as today (lowering §4.6).

**Input parameters** (`HasProperty{:ps, R}`) are several entries per member, one per input value, as the design already states ("a family per input value").

### 2.6 Keys as refinement sets

The key of a member in `X` is its receiver type and its declared fields' types (traits §6.7). The proposal gives it a type:

```
Core.Keyed{X, R, F} <: X        # an abstract type; a set in its own right; never instantiated
```

- `S <: Keyed{X, R, F}` holds iff `S ∈ X` and `S`'s entry for `X` has key `(R, F)`. The entry stores the key, so the subtyping fallback answers it in the same walk.
- `Keyed{X, R, F}` is closed in the sense that matters: it has no members beyond `X`'s, and a member's key is fixed by its entry.
- It is a *supertype of every member with that key*. That is what makes it usable as a compilation signature (§3.4): Julia requires `jl_subtype(dispatch tuple, mi.specTypes)` wherever a `MethodInstance` serves a call (`cache_method`, `src/gf.c:1634`; `jl_normalize_to_compilable_mi`, `:3888`).
- The erased key is `Keyed{X, Nothing, Nothing}`, or simply `X`: the compilation signature of a `Dynamic` position.
- It prints as the design prints trait objects, `ColTable at Vector{Vector{Float64}}`, by a method of `Base.show` on `Type{<:Keyed}`; no printer registry is needed once the type is Core's.

**What is in `F`.** The declared fields' *types*, not their offsets. Two member types that forward to a field of the same type at different offsets have one key. Their shared code reads the field through the projection (§3.4), not at an offset it knows. The alternative, offsets in the key, is §9's decision D2.

### 2.7 `Dynamic`, `Compiled`, `Kept` and `Callable` as Core types

- `struct Dynamic{X}; object::Any; end`, `struct Compiled{X}; object::Any; end`, `struct Kept{X}; object::Any; compiled::Bool; end`, in Core. Each has a *generic* membership entry on its own `TypeName`: `Dynamic{X} where X` is a member of `X`, with key the erased key (so `Dynamic{X} <: X` and `Dynamic{X} <: Keyed{X, Nothing, Nothing}`). `Kept{X}` and `Compiled{X}` likewise; their attribute is read at a bound (§3.5).
- U2 (E-257) keeps `Kept{X}` as the storage form for mixed containers; the Core types make that form a type in any code, not a rewrite inside trait modules (L-6 goes; traits §7.2's "outside trait modules, write the form out" stays as a rule about *meaning*, and §5 says what a bounded scope's lowering does with a set's name in a field).
- A second type parameter holding the object's concrete type (`Compiled{X, S}`) is **not** taken: it is a hidden parameter in the user's eyes and it makes `Vector{Compiled{X}}` a container of boxed objects of many types, which U2 measured as the slower form.
- `Callable{A, S}` is a Core set whose membership is structural: every callable type is a member, and the check is at the call (traits §5.8). Its `Dynamic` form reuses `OpaqueClosure`'s representation (`src/opaque_closure.c:137`, `jl_new_opaque_closure`; the object holds a specialization pointer for a declared `argt` and return bounds) with one change: an `OpaqueClosure` fixes its world at creation (`oc->world = world`, `:129`); a `Dynamic{Callable}` must follow the caller's world. So the pointer is looked up through a world-checked cache, which the patched `:caller_world` convention already is (compiler §3.1). The two meet in one object: an opaque closure whose `world` field is replaced by a cache of (world range, pointer) pairs. The `Compiled` form is the function's own type: a key.

### 2.8 What Core and Base declare

- **Core's kinds are never members** (`DataType`, `UnionAll`, `Union`, `TypeofBottom`, `Module`, `TypeVar`, `Core.Builtin`'s subtypes, `OpaqueClosure`, `GenericMemory` and its views): their typenames carry a `never_member` bit, and `jl_declare_membership` refuses them. U7 showed why: 90 % of the compiler's negative folds are about these.
- **Base's abstract types are closed:** `open` is clear on every typename Base defines. BaseTraits' families over `AbstractVector` are memberships of Base's *concrete* types in *open traits*; they never add members to `AbstractVector`. A written contract for `AbstractArray` (level 3's hope) would be a closed set with a contract: checked at `struct S <: AbstractArray`, sharing code by keys, and never late. That is consistent with E-259's condition (i).
- **`Type{T}` as a member** (open issue 91's decision for `Type{S}` in a set) is representable: the entry's `member` pattern is `Type{S}`; `isa_tfunc`'s kind-type path (`iskindtype(v)`) already refuses to fold negatives for kinds, so no new rule is needed. Whether a membership of `Type{S}` makes `S`'s typename "open-adjacent" for the compiler's bookkeeping folds (`v::DataType` could be a member?) is the one point U7 left open; the proposal says no: a membership of `Type{S}` is a membership of a concrete singleton type, and `DataType` stays a final non-member.

---

## 3. Dispatch and the compiler

### 3.1 One method table; a bounded method is a method

`f(t::ColTable, i::Int) = …` in a bounded scope defines a method with signature `Tuple{typeof(f), ColTable, Int}`. It enters the one method table (`jl_method_table`, 1.13's global table with per-typename caches, `jl_methtable_t`, `src/julia.h:931`) through `jl_method_table_insert`. Nothing is generated beside it: no entry at `Any`, no worker, no `Untyped` fallback, no keyword sorter of its own (Julia's `kwcall` sorter is lowered as for any method). Lowering L-3, L-47, L-48, L-50 and open issue 135 disappear with that sentence; T-95 (the declared result asserted on the fallback) cannot arise, since the fallback is another method.

What the method's lowering adds, from the bounded scope (§5): the declared result type recorded on the method (§3.3), the positions' attributes (§3.5), and the body's operations lowered to calls on the projection (§3.6).

### 3.2 Dispatch caches and memberships

Julia caches dispatch in two places: the leaf cache (concrete tuple to `MethodInstance`, `jl_methcache_t.leafcache`, `src/julia.h:922`) and the typemap cache (`cache`), each entry with a world range. A method insertion lowers the `max_world` of the entries it changes (`jl_method_table_insert` → the cache invalidation it runs for intersecting entries) and invalidates compiled code through backedges.

**A membership does the first and not the second.** `jl_declare_membership(S, X, …)` runs the cache walk for the signature family `Tuple{F, …, S, …}` against the bounded methods on `X` (and on `X`'s supersets): every cache entry at a tuple containing `S` (or a type the pattern covers) whose selected method is beaten by a method on `X` gets `max_world = world - 1`. The next call at that tuple looks up again and finds the bounded method. No `CodeInstance` is touched: "memberships invalidate nothing" ([compiler §7.1](../reference/compiler.md#71-memberships-and-dispatch)). The walk costs what a method insertion's cache walk costs, once per declaration.

A per-call-site cache (the patched `call_cache` entries, compiler §3.2) copies a cache entry's world range, so it follows.

### 3.3 Guards: in inference, in codegen, hoisted

**When a guard is needed.** Inference at a call `f(s::S)` with `S` concrete (`find_method_matches`, `Compiler/src/abstractinterpretation.jl:365`) selects `m₀`. It then asks the method table a second question: *shadow matches*: the methods of `f` on open sets `Z` with `S ∉ Z` now, `S` not a final non-member of `Z`, whose signature would apply at `(S,)` if `S` joined `Z`, and which would beat `m₀` (by `jl_type_morespecific`, with C7: a method on a set never beats a method matched through `S`'s own chain, so `m₀` matched through the chain, other than `f(::Any)`, has no shadow). `ml_matches` can answer it in the same pass by returning the methods it rejected only at the `jl_subtype` step of §2.3, with the position that failed. Most functions have no bounded method; the typemap's per-typename split finds that in one step, so the question is free where it is empty.

**The guard.** For each shadow `(Z, position i)`, inference records a *membership cell* edge and emits:

```
cell = jl_membership_cell(S.name, Z.name)        # fixed when the code is compiled: an object with one field
if cell.min_world <= current_world
    r = dispatch f(args...) in current_world      # a run-time site: no edge
else
    r = m₀(args...)                               # the static call, as without the guard
end
```

- The cell is one mutable object per (member typename, set typename), created on demand by the compiler, held in a dictionary on the member's `TypeName`. Its `min_world` is `typemax` until a membership entry with that set is declared, then the entry's `min_world`. A parametric membership that does not cover `S`'s parameters still sets the cell: the cell is a conservative "may be a member" flag, and the slow branch is a full dispatch, which decides the parameters. The cell is a *different* object from the entry, because the guard compiles before the entry exists.
- The read is a load and a compare against the task's world. In a loop LLVM hoists it (E-259: no measurable cost hoisted, +0.2 to +0.6 ns where not). Codegen emits it as it emits a world-age check for `invokelatest` (`src/codegen.cpp`, the `emit_invoke` family at `:5424`, `:5441`).
- The guarded branch's result type is the declared result of the bounded method joined with `m₀`'s. For that, a bounded method's declared result is recorded on the method: a field `declared_rettype` on `jl_method_t` (beside `recursion_relation`, `src/julia.h:365`), set by lowering from `f(…)::RT`, `nothing` where none is declared. It is a general change: `Callable` results and `return_type` queries can read it too. Without a declaration the branch is `Any`, as a run-time site is (E-259: the one real case, `is_nonlinear_algorithm`, declares `::Bool` and loses nothing).
- The guard is also the *first-seen point* for the attribute (traits §6.2): the slow branch dispatches on the value as it is, and the bounded method's compilation signature decides `Compiled` or `Dynamic` (§3.5).

**Where guards do not arise.** Inside bounded code an argument's membership is positive by construction (the call is at `Keyed{…}`, a member). Code at a final non-member. Code where `m₀` was matched through the chain and is not `f(::Any)`. Code calling a function with no bounded methods. U9 found 7 sites in five sessions.

**Memberships and existing guards.** A membership changes nothing compiled: the guard reads the cell. A *method* insertion `f(::Z)` after `P` compiled at `(S,)` without a guard must reach `P`: Julia's insertion walk with the wider intersection (§2.3) finds `P`'s edge at `(S,)` and invalidates it, and `P` compiles again with the guard. That is the one cost (e) carries: adding a bounded method on an open set invalidates the compiled callers of that function at every type that is not a final non-member. For a library's own function the callers are few. For `Base.show(::IO, ::X)` they are many (E-259's hypothetical: 8–18 guards per session afterwards, and the invalidation at the definition before that). So the trait module's warning for a bounded method on a foreign function (exploration §14.4) stays as the practical rule, and sealed sets (PE-19) are the later remedy for sets whose members join by their own definitions.

### 3.4 Per-key specialization through the compilation signature

Julia already compiles one `MethodInstance` for many dispatch tuples: `@nospecialize` widens a position to the declared type in `jl_compilation_sig` (`src/gf.c:1170`), `cache_method` (`:1634`) stores the leaf-cache entry for the concrete tuple pointing at the widened instance, and `get_compileable_sig` (`Compiler/src/abstractinterpretation.jl:159`) does the same for inference's static calls. Keys use the same path with one more rule:

- **At a bound position whose attribute is `Compiled`,** the compilation signature replaces the concrete type `S` by `Keyed{X, R, F}` from `S`'s entry for `X` (§2.6). A second member with the same key maps to the same `MethodInstance` after its own leaf-cache miss. The instance's `specTypes` is a supertype of every such tuple, which keeps Julia's invariant.
- **At a bound position whose attribute is `Dynamic`,** the compilation signature is the erased key, `X`: the position is `nospecialize`d to the declared type, which is what the design's rule 5 says `Dynamic` is.
- A position bounded by a tuple of traits `(X, Y)` is `Keyed{(X, Y), …}`; a tuple of traits is a set of its own (traits §3.7), declared by its first use, with memberships derived from its members' entries at declaration time.
- `where` variables in bounds (`v::KVec{T}`) are static parameters of the instance, bound from the entry's instance as from a supertype's parameters today.

**The projection convention.** A `Keyed` argument's calling convention (`specsig`) is not a boxed pointer to the whole value. It is the key's *parts*:
- the receiver `R`, by `R`'s own convention (an isbits receiver by value; a mutable one by reference);
- each declared field, by its type's convention, where the field is `@const` or the member is immutable;
- a *field reference* (object pointer and byte offset, two words) for each writable declared field, so a write reaches the user's object (traits §5.2);
- the object itself, boxed, where the method may keep the value (the keep analysis, lowering §8.4, becomes an inference pass that marks the method's escapes).

The **adapter** from the boxed value to the parts is what codegen already generates per specialization for the boxed entry point (`jl_fptr_args` to `specsig`, `gen_invoke_wrapper`, `src/codegen.cpp:7040`). The new wrapper kind reads the receiver and fields from the member's layout, which the entry's `by` and the member's `DataType.layout` give, with the patched field-offset intrinsics' codegen (compiler §5.2) or plain `getfield` where the field is inline. A static caller that knows `S` emits the projection in place; a dynamic call goes through the boxed wrapper. This is TraitWorld's layout table (lowering §6) as a calling convention: `View` holding parts, `Held` for an immutable receiver, the object for writable fields.

**Per-key code in images and the store.** The instance's `specTypes` names `Keyed{X, R, F}`: the library's set, the receiver type and field types. It names no member type. So the compiled code is as sharable as its key, and an image or a store entry for it is valid for any member with that key, in any environment that has `X`, `R` and `F`. Compiling ahead from `@implement X S` in package `P` is then a `precompile` request for every bounded method at `S`'s key (traits §13), which upstream keeps as "external code reached from the worklist" (`queue_external_cis`, `src/staticdata_utils.c:521`, flag `JL_MI_FLAGS_MASK_PRECOMPILED`).

### 3.5 Attributes are the choice of compilation signature

- `Compiled` at a position: the key; the code is per key. `Dynamic`: the erased key; the code is per position, once. The position's attribute comes from the annotation (`x::Dynamic{X}`), else the trait's default, else the first-seen rule (traits §6.2–§6.3), applied by the compiler where it compiles the call: a static call at a known type takes the key; a dynamic call through `jl_apply_generic` takes what the method's position bits say, `Dynamic` unless the position declares `Compiled`. U4 (E-256) saw exactly this split in plain Julia's `@nospecialize`: specialized where the caller knows the type, erased where it does not. The design's rule 5 is thus the mechanism, and its divergence (2), the entry rebuilding a trait object per call (T-94), does not exist: there is no entry.
- A kept value (`Kept{X}`, `Compiled{X}`, `Dynamic{X}`) at a bound is a dispatch tuple with the wrapper type. `Dynamic{X}` is a member at the erased key: it reaches the erased instance directly. `Compiled{X}` reaches a small instance that dispatches on the held object's type to the keyed instance: one more dispatch, through the per-call-site cache (the patched `call_cache_exact`, 9–18 ns beyond four types in E-164). This is lowering §9.3's table as Julia's own cache. A `Kept{X}` branches on its `compiled` flag first.
- Casts (`compiled_for`, `with_dynamic`) are constructors of the wrapper types, as today (traits §6.4); nothing in the compiler changes for them.
- A plain value written into a field declared with a set's name (traits §7.3) is converted by `convert(Kept{X}, x)`, a method of Core's `Kept`.

### 3.6 Operations in bounded scopes; the split

In a bounded scope, a call on a bounded argument `t` lowers by the contract:
- `op(t, args...)` where `op` is an operation of `t`'s bound and `t` is `Compiled`: `op(receiver(t), args...)::RT`, a call at the receiver's type, a fact where `R` is concrete, followed by the declared result's assertion. Where the implementation serves `op` by a default, the default's method; where by forwarding, the field's type is the receiver. The witness (lowering §5) is folded away: the entry's `by` and the implementation's choice per operation are known where the method is compiled, because the key names `R`, and the trait's record (a Julia-side table per set, as today) says how `R` serves each operation.
- a declared field `t.f`: the part, or a load through the field reference; a write, a store through it.
- `op(t, args...)` where `t` is `Dynamic` (the erased key) or a kept value: `Compiler.split_call(X, RT, op, object(t), args...)`, unchanged from compiler §4.2–§4.3: inferred at the first four declared members, split at the call site, the table of targets beyond. U2 (E-257) confirms this must stay a call-site split, not a method call at `X`. The candidates are now read from `X`'s *members*, which the runtime holds (§2.1): `register_dynamic_candidate!` is `jl_declare_membership`.
- any other call with `t` bare: refused by the check (§3.7) in a bounded scope that enforces; otherwise it is a plain call with the object (the function is then "open", exploration rule 4) and the method is compiled per concrete type, as plain Julia compiles it.

### 3.7 The definition-time check as an inference mode

The check (traits §9; TraitWorld's `defcheck.jl`, `checks.jl`, 748 lines) becomes one inference of the method at its *erased* signature under a `bounded_check` flag of the native interpreter:
- the bounded argument has lattice type `X` (the erased key): only the contract's operations resolve, to the declared results;
- every call that reaches the argument otherwise is a run-time site, which the flag reports with its statement and the function it tried to call: `TraitUseError` (traits §5.3), or, in a scope that classifies rather than enforces, the mark "open";
- the result is the method's *classification*, stored on the method (a bit beside `declared_rettype`), read by `fully_typed` and by the store (§4.5).

Inference at the erased key is what the method's `Dynamic` instance is compiled from anyway, so the check costs one inference the compiler would do at the first `Dynamic` call. T-91 to T-93 (the checker's gaps) are gaps of a reimplementation that this replaces.

### 3.8 Compiling by facts as a property of the CodeInstance

**The policy is per method.** A method has a policy from its scope (§5): `facts` or `plain`; the compiler's own code is `plain` whoever calls it (facts §6.4). Inference under `facts` gates `find_method_matches` by the fact-signature criterion (facts §3) and marks run-time sites with the `nortsite` effect bit (compiler §1.3). This is what the patched build does; the point here is that upstream has the shape already: `concrete_only` on a `TypeName` makes inference "refuse to commit (record no backedge) at non-concrete call sites" for calls *to* that function (`is_concrete_only`, `Compiler/src/inferencestate.jl:1127`; `abstract_call_gf_by_type` at `:143` of `abstractinterpretation.jl`). The facts policy is the same refusal, decided by the *caller's* method instead of the callee's function, with the fact-signature forms in place of "concrete". A PR that generalizes `concrete_only` to a per-method `commit` policy is the upstream form of mechanism (A).

**The dependency record.** A `CodeInstance` already carries `edges` (`src/julia.h:475`; the format `verify_method` reads, `Compiler/src/reinfer.jl:162`: `MethodInstance`, `CodeInstance`, `Int` match counts with signatures, bindings, `invoke` signatures). The record this design needs adds four kinds, each a value in the same `SimpleVector`:
- **a result edge** to a callee `CodeInstance`: the caller depends on the callee's `rettype`, `exctype`, `ipo_purity_bits` and `rettype_const`, not on its code (the callee was called, not inlined);
- **an inlined-code identity**: the method and the hash of the lowered code that was inlined (W-66's F1), for callees whose code is in the caller;
- **a layout identity** for every type whose fields the code reads (F3);
- **a membership cell** for each guard, and each positive membership folded (the entry object).

`compute_edges!` (`Compiler/src/typeinfer.jl:790`) and the inliner's `add_inlining_edge!` write them; `store_backedges` (`:761`) registers the callee-side backedges for the first two as today. Folds (`FoldRecord`, compiler §4.4) are already there. Bindings are there (and in 1.14 per partition, with the optimizer's `GLOBALS` pass, [the 1.14 scan](../record/julia-1.14-scan-2026-10-27.md) §3).

**G2 is then a predicate on the record:** every dispatch edge is at a fact signature (or an `invoke` edge at a declared signature); every inlined identity is of a method whose own record satisfies G2 (so inlining stays within facts code, as compiler §2.7 requires); result edges may go anywhere. The predicate is computed once at `finish!` and stored as a bit (the patched `nortsite` is its negation's half: "no run-time site"; this is "no fragile edge"). It is what the store admits (§4.1) and what strict mode protects.

**Result edges revalidate instead of invalidating.** Today `invalidate_code_instance` (`src/gf.c:2168`) walks backedges and lowers every caller's `max_world`, transitively. With result edges the walk changes for one case: a caller that holds only a *result* edge to the replaced instance is marked with the revalidation sentinel (`WORLD_AGE_REVALIDATION_SENTINEL`, `Compiler/src/reinfer.jl:10`), not discarded; when it is next needed, `verify_method_graph` (`:95`) checks the edge against the callee's *new* instance in the current world: equal result, the caller's world range is restored (`jl_promote_ci_to_current`, `src/gf.c:1942`); otherwise it is inferred again. This is red-green revalidation, which Julia's image loader already performs on every package load; the change is to run it in the session, lazily, for this one edge kind. HotSpot and rustc do the same (the project's [precedents research](../record/incremental-precedents-research-2026-10-27.md)).

**What this does to the second cache owner.** The patched build compiles facts copies of Base's methods under owner `:facts` because a facts caller that holds an edge to a *plain* callee would be invalidated with it (facts §6.3). With result edges that revalidate, the facts caller may name the plain callee's instance and survive its recompilation whenever the result is unchanged, which for a fully typed callee at a concrete signature it always is. So:
- the facts copies of neutral methods are no longer needed for G2; the facts caller calls the plain instance;
- inlining a plain callee into facts code stays refused unless the callee's own record satisfies G2 (else the fragile edges would come along), which is compiler §2.7's rule;
- the owner token remains only where one method must hold two compiled forms at once: the test bed `all` (every method by facts) beside the product setting in one depot, and reflection. In the product setting there is one instance per `MethodInstance` and policy, and the policy is the method's. The owner is then upstream's `owner` field used as upstream uses it: a token for a second interpreter, here the test bed's.

This is §9's decision D3. It removes the largest conceptual piece of the patched build (compiler §2, two modes side by side) in favour of one general improvement to Julia's invalidation, which also serves plain code (a callee recompiled to the same result no longer cascades).

---

## 4. Caching machine code

### 4.1 What makes a CodeInstance cacheable across sessions

A `CodeInstance` with machine code can be reused in another session, environment or load order when four things hold:

1. **Its record is complete:** every assumption the code makes is an edge of §3.8: dispatch facts, result edges, inlined identities, layouts, bindings (with the value's hash for a constant read as a constant), folds, membership cells and folded positives. Nothing the code assumed is outside the record. The facts policy makes this true for dispatch (no heuristic match is folded); the inliner's and optimizer's folds must be recorded too (constant folding of a global's value is a binding edge; `fold_call` is a record; the effects used for concrete evaluation are in the callee's result).
2. **Its record is environment-free:** each edge names its target by a *stable identity*, not by a session object. A method: module path, name, signature, and the hash of its lowered code. A type: module path, name, parameters structurally, and its layout hash. A binding: module path and name, with the partition kind. A membership cell: (member identity, set identity). A constant: its value hash where it has no identity.
3. **Its machine code is relocatable by those identities:** references to other instances' specialization pointers, to type tags, to globals and to constants are symbols resolved at load, not addresses.
4. **Its result does not depend on session history beyond the record:** G1's criterion ([the store's note](../plans/2026-10-28-facts-cache-store.md) §4). Inference's own history (what was inlined because it was cached first) may change the *code*, never the *result*; the record says which code this is.

Under the unified design, bounded code over concrete keys satisfies 1 and 2 by construction: its dispatch is at keys and receivers, its layouts are the key's, its membership folds are positive. Plain code satisfies them only where it is fully typed. The share is therefore a property of how much code is bounded, which the ports decide; E-194 and E-234 measured today's: in the forks' session the saving a cache would bring is mostly plain code, and a facts-only store keeps about a tenth of it. Per-key compilation moves code from "plain, per concrete type" to "bounded, per key", so the share grows with unification; §7 names the experiment that measures it.

### 4.2 The identity of an entry

An entry is identified by:
- the `MethodInstance`'s identity: the method (stable identity, with its lowered-code hash F1) and `specTypes` by structure (keys are structural: `Keyed{X, R, F}` names sets and types by path);
- the policy and the compile flags (`CacheFlags`, `base/loading.jl:1721`: `check_bounds`, `inline`, `opt_level`, `debug_level`), the Julia build, the target CPU;
- and, as *content*, the record's fingerprints (F1 of the method and of each inlined method, F3 layouts, constants' hashes), compared at load.

What it is **not** keyed on: the environment's manifest, the dependency images' build ids, the load order, the world. Build ids cascade (E-194: a foundational package's change invalidates 86–90 % of entries under a build-id closure); fingerprints cut off early (E-195: all 2,143 of C's entries kept across an unrelated update).

### 4.3 How it relates to package images, invalidation, worlds and edges

- **A package image** (`.ji` plus the pkgimage `.so`) is a store entry set written at precompilation, linked to its dependencies by build id (`link_ids_relocs`, `buildid_depmods_idxs`, `src/staticdata.c:341`–`:349`; the loader checks each dependency's build id, `base/loading.jl:1316`). Its code is validated at load by `verify_method_graph` and promoted into the session (`jl_promote_ci_to_current`). The store keeps the same validation and promotion, with a different linkage (§4.4) and without a worklist: an entry is any instance, from any session.
- **Invalidation in the session** is the same walk for both: a store entry promoted into the session has backedges registered (`store_backedges`) like an image's, and is invalidated or revalidated as §3.8 says. An entry that fails validation is dropped for the session; the store keeps it (a cache entry is evidence, not a contract; the user's rule for W-66).
- **Worlds** are never stored. An entry's world range comes from validation in the loading session (facts §11, "Entries stored across sessions"), which is how images work today.
- **Edges** are the record; the store serializes them by identity. The loader's uniquing pass (described in `src/staticdata.c`'s header comment) already resolves *types and methods the image newly defines* against the session's objects; the store's loader resolves *every* reference by identity. A reference that resolves to nothing (the type is not defined in this session) makes the entry miss without side effect.

### 4.4 A global or per-environment cache of native code: the shards

**The vehicle is machine code**, as open issue 95's option (b) says: E-205 found code generation twice inference in C (7.56 s of 10.7 s compile), so a store of optimized IR has a ceiling of 1.5 s where machine code has one of 13 s (E-180, the retired environment-keyed cache: 19.4 to 6.1 s).

**A shard** is an image without a worklist:
- written by `jl_emit_native` with `external_linkage` (`src/aotcompile.cpp:784`) from a set of `CodeInstance`s a session compiled and whose records satisfy §4.1, grouped by their origin set (the packages their identities name; E-188: C's facts code falls into 213 origin sets, no package touching more than a quarter);
- its data part written by `jl_write_values` (`src/staticdata.c:1367`) restricted to the instances, their methods' identities and the record, with one **new relocation kind: by stable name**, in place of `link_ids_relocs` by build id. `get_reloc_for_item`/`get_item_for_reloc` (described at the top of `staticdata.c`) gain a tag for "resolve by identity at load";
- its code part's function table (`jl_image_fptrs_t`, resolved by `jl_update_all_fptrs`, `:2269`) likewise names callee specializations by identity;
- one shard per (origin set, Julia build, flags); stored under the depot (`compiled/v1.x/shards/`), written by atomic rename, bounded by least-recent use; shared by every environment on the machine, since nothing in it names an environment.

**Loading** happens after each package load, outside inference (the store's note §3.4): the shards whose origin sets are now fully loaded are opened, their references resolved by identity, their content fingerprints compared, their instances relocated, their records handed to `verify_method_graph`, and the valid ones promoted. The same path serves a *per-environment* cache (a shard per environment hash, no identity resolution needed) as a first step, which is E-180 rebuilt on the record; the global form is the second step, and the identity relocation is the only difference between them.

**Recording** happens when the code is made: `finish!` (`Compiler/src/typeinfer.jl:104`) keeps the record; the JIT keeps the object code it emitted (`jl_compile_codeinst_now`, `src/jitlayers.cpp:646`) for instances the policy admits, or the shard writer re-emits them at exit from kept IR. Upstream's `precompile_keep_ir` mode is the switch to generalize.

### 4.5 What can never be cached, and why

- Code that embeds a value with identity (a mutable global's object used as a constant, a `Ptr`, a task-local): the record cannot name it. It is relinked through its binding where it is read through one; otherwise the entry is not stored.
- Code of `Main` and of anonymous modules: no stable identity across sessions (a struct redefined at the prompt is a new type with the same name). Excluded by default; a content identity (name plus layout hash plus definition order) is a possible opt-in later.
- Code whose record is incomplete: plain code with heuristic matches at abstract signatures (no facts); a generated function whose generator reads session state (its expansion's hash is F1 where the generator is pure; otherwise excluded); an opaque closure made in a particular world.
- `return_type`'s plain answers (compiler §1.4): plain inference's edges are not facts; an answer is cached as a *result* only with its full plain record, which a load may break, so it is recomputed, as today, and the facts code that folded it keeps a result edge to it.
- Code compiled with compilation off or by the interpreter.
- Across Julia builds, targets and flags: never; they are part of the identity.

### 4.6 Closed builds

A `--trim` build is the closed case: nothing loads, so the record is not needed for validity, and the facts policy is off (facts §12.3). What unification gives trimming is enumerability: every `Dynamic` operation's targets are the set's members, every guard's slow branch is a dispatch over the known methods, every `Callable` is at a declared signature. `verify_main` becomes a query over the record and the membership lists rather than a walk TraitWorld writes (lowering L-27, L-35 go). The store's shards are not inputs of a trimmed build; a trimmed build compiles from source in the closed world, as today.

---

## 5. The scope declarations

Four declarations, each one sentence of meaning, at module and function granularity (a block form only for `facts`, as a statement-level policy inference can honour per call; the others classify a method):

| Declaration | Meaning | Where it lands | Granularity |
|---|---|---|---|
| `facts` | this code's inference commits only at fact signatures; its run-time sites are dynamic dispatches; its record satisfies G2 where its inlined callees do | `jl_module_t` flag (as `optlevel`, `infer`), `jl_method_t` flag (as `nospecializeinfer`); `Base.Experimental.@compiler_options facts=true`; `Expr(:meta, :facts)` on a method | module, method, block |
| `bounded` | a set's name on an argument is a bound; operations lower by the contract (§3.6); the method is checked at its definition (§3.7); a set's name in a field or element type means `Kept{X}` | lowering (the front end, `src/julia-syntax.scm` and the macro layer) and the check; a `jl_method_t` classification bit | module, method |
| `concrete` | the method's compiled code at its keys has no run-time site: the `nortsite` bit, enforced (`NotFullyTypedError`) or warned | `Compiler/src/effects.jl`; the check at `finish!` | module, method; a trait's `@enforce_concrete_only` for its keys (traits §11.1) |
| `no_pirates` | a pirate is refused at its definition; a definition that would win at a fact of this scope's compiled code is refused where it would win (strict mode's intended design, facts §10.3) | the definition and image hooks (`jl_method_table_insert`, `jl_activate_methods`); the walk over backedges and the record | module; and a session switch |

A **trait module** is the four together, one spelling. A plain package may declare `facts` and `no_pirates` alone and gain load stability and cacheability for its fully typed code (E-212: upstream CSV and DataFrames under `all` lose 2 of 3,337 instances to nine loads).

**Rules at the edges**, stated once per pair:

| From | To | What happens at the call |
|---|---|---|
| bounded | plain | ordinary values cross as themselves; a bounded argument crosses only as a value seen through its bound (`compiled_for`, `with_dynamic`, a kept form) or is refused by the check; a `Like` result is rebuilt (traits §5.6). The call's policy is the caller's (`facts` if the scope says so). |
| plain | bounded | an ordinary method call: static where the type is known (the projection emitted in place, the key's instance called), dynamic otherwise (`jl_apply_generic`, the leaf cache, the boxed adapter). The position's attribute decides the compilation signature (§3.5). A guard where §3.3 says. |
| facts | plain | the callee's instance is named by a result edge, inlined only if its record satisfies G2; a dynamic call runs the callee's plain code. |
| plain | facts | the callee's facts instance is named with an ordinary edge; constant propagation and concrete evaluation cross on the callee's effects as inferred under facts (facts §6.3, unchanged). |
| `no_pirates` | anything | nothing at the call; the scope acts at definitions and loads. |

What the edge table does *not* contain any more: entries, workers, `Untyped`, the boundary meta on generated methods, the table of declared implementations. The boundary principle ("only values cross, by their bound; code never crosses") is the first row, and it is a consequence of the projection convention rather than a rule.

---

## 6. The build path from upstream Julia

Each stage is a branch on upstream (1.14 once released, per [the scan](../record/julia-1.14-scan-2026-10-27.md): inference without the global lock, `reset_safe` at effects bits 15–16, binding partitions in IR). Each is useful alone, has a test that decides it, and names what it removes from TraitWorld's encoding.

### S0. The facts policy and the dependency record, as a PR series

- **What:** the per-method `commit` policy generalizing `concrete_only` (mechanism (A)); run-time sites and `nortsite`; the `return_type` rule; the result-edge kind and inlined-code identities in `CodeInstance.edges`; red-green revalidation for result edges in `invalidate_code_instance`; the hooks (definition, image, deletion, binding); `known_type`; the per-call-site cache's exact-type entries; `split_call` with its tables; `fold_call`. All exist on the patched branch but the record and the revalidation.
- **Where:** `Compiler/src/{abstractinterpretation,typeinfer,tfuncs,effects,reinfer}.jl`, `src/gf.c`, `src/staticdata_utils.c`.
- **Removes:** nothing of the encoding yet; it removes the *need* for owner `:facts` copies of neutral methods (compiler §2.3's table collapses to "the policy is the method's"), and C-16, C-5's family of owner-copy deviations.
- **Riskiest assumption:** that result edges with revalidation keep G1 (a caller kept across a callee's recompilation computes the same) and that they save enough. **Smallest prototype, no Julia change:** in the forks' session (E-233: 1,884 `MethodInstance`s invalidated by method insertions), log each invalidated instance's old and new `rettype`, `exctype`, effects and constant; count the callers that would have been kept. Minutes, a script over `Compiler.ReinferUtils.debug_method_invalidation`'s log (compiler §5.4) and the caches.
- **Test:** the acceptance suite (G1.1–G1.35) plain and under `all`; `g2all` counts.

### S1. Memberships in the type system (the plan's P1)

- **What:** the `open` and `never_member` bits; the membership list and `jl_declare_membership`; the fallback in `subtype`; `isa_tfunc`, `subtype_tfunc` never folding a negative for an open set; `typeintersect` and `jl_has_empty_intersection` over-approximating; the world protocol; `Core.Dynamic`, `Compiled`, `Kept` with generic entries; `Keyed{X, R, F}` as a type (its use comes in S3).
- **Where:** `src/julia.h`, `src/datatype.c`, `src/subtype.c`, `src/jltypes.c`, `Compiler/src/tfuncs.jl`, `base/boot.jl`.
- **Removes:** L-5 (`conforms`), T-23, L-43's world rule, L-4's edges from `conforms` into the registries (E-254), L-25 (candidates registered from the entries), part of L-6 (the kept forms are types everywhere).
- **Riskiest assumption:** that Julia's own type code keeps its invariants with an over-approximating intersection and a subtype relation that is not derivable from `super`: the type cache's `has_concrete_subtype`/`maybe_subtype_of_cache` bits (`src/julia.h:645`–`:646`), `Union` normalization, `detect_ambiguities`. **Smallest prototype:** the bits, the list, the fallback and the two tfuncs, with one trait and two members declared from Julia (`ccall(:jl_declare_membership, …)`), then Base's `subtype`, `core` and `ambiguous` tests, and their time within 10 % (the plan's P1 checks).
- **Test:** `S <: X` and `x isa X` after a late `@implement`, in the old and the new world, with no recompile (E-254's script, part B, against the runtime instead of a Julia registry); `detect_ambiguities(Base)` unchanged.

### S3. Keys as refinement sets; the projection convention; the check

- **What:** `Keyed{X, R, F}` answered by the entries; the rule in `jl_compilation_sig` and `get_compileable_sig` for bound positions; the projection `specsig` and the boxed adapter in codegen; the lowering of operations and fields in a bounded scope; the declared result on methods; the check as the `bounded_check` inference mode; `Dynamic` positions as the erased compilation signature; `Callable` on `OpaqueClosure`'s object with a world-following pointer cache.
- **Where:** `src/gf.c` (`jl_compilation_sig`, `cache_method`), `src/codegen.cpp` (`gen_invoke_wrapper`, `emit_call_specfun_other`, the argument lowering), `Compiler/src/abstractinterpretation.jl` (`get_compileable_sig`, `abstract_call_gf_by_type`), `src/method.c` (the declared result), `src/julia-syntax.scm` and a macro layer (the bounded scope's lowering), `src/opaque_closure.c`.
- **Removes:** the rewrite into workers and entries (lowering §8, L-3's mechanism, L-36, L-10, L-15, L-16), views and witnesses (§5, §6, L-1, L-2, L-21), the tables of untyped callers (§9.3, L-39 to L-41 retired already), the entry's attribute decision (`enter`, T-94), the checks' reimplementation (T-91 to T-93, L-10), the field-offset intrinsics' use from Julia code (they stay as codegen's). About 6,000 lines of `TraitWorld/src` (`entry.jl`, `core.jl`, most of `trait_module.jl`, `untyped.jl`, `defcheck.jl`, `checks.jl`, `attributes.jl`).
- **Riskiest assumption:** that per-key instances with a projection convention give what TraitWorld's workers give (E-164: a typed trait call 0.8 ns as plain; the view 17.6–18.8 ns at 64 types) *and* that the leaf cache keyed by concrete tuples pointing at keyed instances behaves under Julia's invariants (`cache_method`'s guard signatures, `jl_isa_compileable_sig`, `:1414`). **Smallest prototype:** hand-written: a method `f(t::Keyed{X, Vector{Float64}, …})` and the `jl_compilation_sig` rule for one bound, two member types sharing the key, with the adapter generated; measure the typed call, the dynamic call and the number of instances against TraitWorld's worker on the same shapes (E-164's `shapes_defs.jl`). A build, a day of codegen work for the adapter in its simplest form (immutable members, `@const` fields).
- **Test:** TraitWorld's suite on the compiler's keys; the demonstrators' numbers (evidence §2, §3) no worse; the schema-independence test (E-215: no new instance for a second schema).

### S2. One dispatch under (e)

- **What:** bounded methods as methods at sets; the membership cache walk in `jl_declare_membership`; shadow matches and guards in inference; the cell objects; guard codegen; the C7 flag in `ml_matches` and `jl_method_match_t`; `jl_type_morespecific` for set-in-set; the ambiguity report at the membership; the invalidation at a bounded method's insertion with the wider intersection; `interferences` with the "ordered by C7" state.
- **Where:** `src/gf.c` (`ml_matches`, `jl_mt_assoc_by_type`, `jl_method_table_insert`, `jl_declare_membership`), `src/subtype.c` (`jl_subtype_env`'s flag, `jl_type_morespecific`), `Compiler/src/abstractinterpretation.jl` (`find_method_matches`, the guard's `CallInfo`), `Compiler/src/stmtinfo.jl` (a `GuardedCallInfo`), `Compiler/src/ssair/inlining.jl` (the guard's shape is `ir_inline_unionsplit!`'s, `:526`), `src/codegen.cpp`.
- **Removes:** L-3 (entries at `Any`, the shape rule, "only the owner adds a shape"), L-47, L-48, L-50, open issue 135, T-83 (the report is the runtime's), T-95, the `Untyped` machinery, the joint-method and ambiguity checks at a module's end (`check_bounds`, `check_entry_ambiguities`).
- **Riskiest assumption:** the invalidation volume when a bounded method is inserted on an open set (§3.3's last paragraph) and the shadow-match cost in inference. **Smallest prototype, no Julia change:** on today's build, for each function with a bounded method in the ports (U5's 127), count its specializations whose signature holds a non-final type at the bounded position (the instances an insertion with the wider intersection would reach), and for `Base.show` the same count in each session. Minutes. Then the build: shadow matches and guards for one function, G1 checks with a late membership from a task in the old and the new world.
- **Test:** the acceptance suite with late memberships (G1.17, G1.25 rewritten for one dispatch); U9's census shows the same 7 sites; `detect_ambiguities(Base)` unchanged; SciML's front end on CommonSolve's `solve` and Makie's `Block` (the plan's P2 cases).

### S4. The machine-code store

- **What:** the identity serialization (methods, types, bindings, cells by stable name); the relocation kind by identity in `staticdata.c`; shards written at exit from kept object code, grouped by origin set; loading after each package load with `verify_method_graph` and promotion; the per-environment form first (identity resolution trivial), the global form second.
- **Where:** `src/staticdata.c` (`jl_write_values`, `get_reloc_for_item`, `jl_update_all_fptrs`, a `jl_restore_shard`), `src/aotcompile.cpp` (`jl_emit_native` with external linkage), `src/jitlayers.cpp` (keeping object code), `base/loading.jl` (the store's directory, insertion after loads), `Compiler/src/reinfer.jl` (validation of a record with result edges and cells).
- **Removes:** nothing of the encoding; it retires the keep-compiled switch's special cases (compiler §2.9: an image keeps what the record admits) and PE-13's question (plain code that is fully typed is admitted by the same predicate).
- **Riskiest assumption:** that machine code can be relinked by identity: specialization pointers to callees in other shards and images, type tags of types the loading session has instantiated under other addresses, and `gvars`. Upstream's pkgimage already relinks against the system image and dependency images by index (`jl_image_fptrs_t.clone_idxs`, `sysimg_gvars`), so the question is whether an index can be replaced by a lookup without losing the direct-call form (the alternative: calls between shards through the `invoke` pointer in the `CodeInstance`, one indirection). **Smallest prototype:** one toy package; a session compiles ten instances of it at keys; write them as a shard with identities; a second session with a *different* environment (another unrelated package added) loads the shard; compare each instance's result and code against a fresh compile (E-0's cases from the store's note, which were planned for IR and apply to machine code unchanged).
- **Test:** the forks' session and C's with the store warm: against E-234's estimate (3.89–4.14 to 2.99–3.22 s) and E-180's measurement (19.4 to 6.1 s); nothing kept that a fresh compile would compute differently.

### S5. The surface

- **What:** `trait`, `implement`, `Self`, bounds in `where` clauses and on struct parameters as syntax under a syntax version (1.14's `syntax.julia_version`, #60018); the four scope declarations as module and method options; `Base.show` for `Keyed`; the strict-mode errors for deletions and cross-module bindings (F-6); `verify_main` as a compiler query.
- **Removes:** the macro layer; the printer registry (compiler §5.3); the lowering reference as a description of an encoding.
- **Riskiest assumption:** none technical; the risk is agreement upstream.

**Order and why.** S0 → S1 → S3 → S2 → S4 → S5. S0 is a prerequisite for the record (S4) and makes the rest upstream-shaped. S1 is the plan's P1. S3 before S2 (a departure from P1 → P2, §8): a method at a set dispatches to code the compiler must have compiled per key, and S3 is where the encoding's largest part goes. S4 can start after S0 in parallel (the per-environment form needs only the record). S5 last. Gates: after S1 (the plan's gate B); after S3 (the typed-call numbers); after S2 (gate C); after S4 (the sessions against Python).

---

## 7. Risks and open questions

Honestly, in order of weight.

| Risk | Where Julia resists | What decides it (cheap first) |
|---|---|---|
| **Machine code relinked by identity** (S4) | `staticdata.c`'s relocation model is positional (by index into linked images); pkgimage function tables are resolved by index (`jl_update_all_fptrs`); type tags in code are addresses | the toy-shard prototype of S4; before it, a count of how many relocations in one pkgimage target *external* objects (a reading of `link_ids_relocs` sizes), to size the lookup |
| **Invalidation at a bounded method's insertion** (S2) | `jl_method_table_insert` with the wider intersection reaches every specialization at a non-final type | the no-build count of S2; then the warning for foreign functions as the rule; sealed sets later (PE-19) |
| **The compilation signature at a key** (S3) | `cache_method` and `jl_normalize_to_compilable_sig` assume the compiled instance's `specTypes` is a supertype of the tuple *and* "compileable" (`jl_isa_compileable_sig`); `Keyed` must pass both; the leaf cache's guard signatures must not misfire for members with different keys | S3's hand-written prototype |
| **The projection convention for writable fields and kept values** (S3) | codegen's `specsig` has no two-word "object plus offset" argument; the keep analysis is a new escape pass | the prototype restricted to immutable members first; writable fields second; measure the forks' kernels (E-214), which write through `Column` |
| **Inference's lattice with unfolded negatives** (S1) | `Conditional`s, `typeassert_tfunc`, `tmerge` use `typeintersect`'s `Union{}` to prune | U7's count says the loss is negligible; the P1 build's Base test time is the check |
| **`jl_type_morespecific` and ambiguity tooling with sets** (S2) | `morespecific` is a signature relation; C7 is per argument; `interferences`, `detect_ambiguities`, `Test` read signatures | the "ordered by C7" state in `interferences`; `detect_ambiguities(Base)` unchanged after S1 and S2 |
| **Result-edge revalidation's soundness** (S0) | `invalidate_code_instance`'s walk is transitive by design; a kept caller may embed the callee's *constant* result or effects used for a fold; the record must say which | the result edge carries exactly what was used (`rettype`, `exctype`, effects, constant); the no-build script of S0 estimates the gain; the acceptance suite checks G1 |
| **Associated types by equations in families** (S1) | `jl_subtype` cannot call Julia | the pattern-or-lazy rule of §2.5; the ports' families (TDE's 24 sets, NetworkDynamics' 4) checked for equations that are not patterns |
| **Concurrency** (1.14) | inference without the global lock; the membership list, cells and shard loading must be copy-on-write or atomic | the 1.14 scan's recommendation; the tables already are |
| **Two policies for one method** (S0) | the test bed `all` compiles Base by facts beside the product setting's plain Base in one depot | keep the owner token for the test bed only; the product setting has one instance per policy and the policy is the method's |

**What would make the reframing fail:**
- If relinking by identity cannot keep direct calls between shards and images, the store degrades to calls through `CodeInstance.invoke` pointers (one indirection per cross-shard call). It still removes code generation from sessions; it loses some run-time speed. Not fatal.
- If the leaf cache cannot be made to map concrete tuples to `Keyed` instances without breaking `cache_method`'s invariants, keys need their own cache beside the leaf cache (TraitWorld's table reborn inside `gf.c`). Not fatal; a loss of simplicity.
- If shadow matches and guards turn out common once Base's abstract types gain contracts *and* openness, (e) fails. The proposal keeps Base's sets closed, so this does not arise; it is a limit on level 3, not on the build.
- If bounded code stays a small share of what sessions compile (U1: 5–27 % of existing generic code is bounded as written), the store's gain stays the facts-only tenth of E-234. The ports decide this, not the compiler. The per-environment shard form admits fully typed plain code too, which is most of the rest; it is the honest fallback.

**Open questions put to no experiment yet:**
- How a tuple of traits `(X, Y)` is named as a set: a `Core.Both{X, Y}` typename per pair, created at first use, with entries derived from the members' entries at `jl_declare_membership` time (each new membership of `S` in `Y` checks whether `S` is in `X` and declares `S ∈ Both{X, Y}`). The derivation is a product; its cost is bounded by the number of tuples in use.
- Whether `Keyed` carries offsets (D2). The projection convention says no.
- The spelling of sealed sets (PE-19), unchanged.

---

## 8. Where this departs from the project's current assumptions

Each departure names what it replaces and why.

1. **Keys before one dispatch** (S3 before S2; the plan has P1 then P2). A bounded method as a Julia method needs per-key code from the compiler; building S2 on TraitWorld's workers would keep the entry's half-life. S3 also removes the most encoding.
2. **No second cache owner in the product setting.** The patched build's compiler §2 (modes side by side, owner `:facts`, facts copies of Base, `leaves_to`, cross-owner inlining) is replaced by a per-method policy plus result edges that revalidate. The owner token stays for the test bed. Why: G2 is a property of a record, and a general revalidation also serves plain Julia.
3. **The key is a type** (`Keyed{X, R, F}`, a refinement set), and per-key compilation is `@nospecialize`'s mechanism with one more rule. Lowering L-1 (the key as the trait type's last parameter) and L-2 (trait sets as unions of families and tags) are not reproduced in Core.
4. **The entry is the compiler's boxed adapter, not a method.** There is no method at `Any`; "types first, then traits" is C7 inside `ml_matches`; `known_type` is no longer needed for the attribute decision (it stays as a general primitive).
5. **Memberships live on the member's `TypeName`,** world-stamped, and advance the world counter. The references say "a membership holds from the world in which it is declared" without saying who advances the counter; this says the declaration does, as a method insertion does.
6. **The declared result type is recorded on the method** (a Julia change with uses beyond traits). The references treat it as an assertion in the body only.
7. **`Callable`'s `Dynamic` form is an `OpaqueClosure` that follows the world**, not a `cfunction` thunk. The `:caller_world` convention's cache moves into the closure object.
8. **The definition-time check is an inference mode** at the erased key, not a separate checker. T-91 to T-93 are then not deviations to fix but code to delete.
9. **The store keeps machine code relinked by identity,** as open issue 95 (b) says, and admits any instance whose record is complete, plain fully typed code included (PE-13's question answered by the predicate, not by policy).
10. **A bounded method on an open set invalidates at its definition** the compiled callers at non-final types. The references say "methods invalidate as in Julia under ownership"; this names the volume and makes the warning for foreign functions the practical rule.

---

## 9. Suggested record changes

For the main session to place. Nothing here is written anywhere else yet.

**Decisions to put to the user** (open issues §1):
- **D1. Stage order:** S0, S1, S3, S2, S4, S5 (keys before one dispatch), against the plan's P1 then P2.
- **D2. The key's shape:** receiver and field *types* with a projection convention (shared code per key, writes through field references), or receiver, field types *and offsets* (shared code per layout, reads at constant offsets, more copies). Recommended: the projection; measure the copies if the ports show many layouts per key.
- **D3. The facts policy as a method property, with result edges that revalidate, in place of facts copies under a second owner** in the product setting; the owner token kept for the test bed `all`. This retires compiler §2's "two modes side by side" as the intended shape and makes revalidation a general Julia improvement.
- **D4. Memberships advance the world counter** and carry `min_world`, like methods; the REPL and `invoke_in_world` follow (E-254 part B).
- **D5. The cost at a bounded method's definition on an open set** (callers at non-final types invalidated) is accepted as the price of (e), with the warning for a bounded method on a foreign function as the rule, and sealed sets as the later remedy.
- **D6. The store's vehicle:** machine code in shards by origin set, relinked by identity, admitting every instance whose record is complete (bounded code, and fully typed plain code), excluding `Main`; the per-environment form first.
- **D7. `Callable`'s `Dynamic` form on `OpaqueClosure`'s representation** with a world-following pointer cache, replacing the `cfunction` thunk.
- **D8. Base's sets closed by default and Core's kinds never members** are runtime bits set at bootstrap (`base/boot.jl`), not library data.
- **D9. A declared result type recorded on `Method`** as a general change.

**Open issues to add** (§2):
- A tuple of traits as a set of its own (`Both{X, Y}`): derivation at membership time; cost.
- Whether `Type{S}` memberships affect the compiler's bookkeeping folds (the remainder of U7's open point).
- The `interferences` state "ordered by C7" and what `detect_ambiguities` reports for set-versus-tree pairs.

**Work items** (todo):
- **W-S0a (no build, minutes):** the red-green estimate: of the instances invalidated in the forks' and C's sessions, how many callers hold only result edges to callees recompiled to an equal result. Registry row first.
- **W-S0b:** the PR series for the policy and the record on upstream 1.14-alpha: `commit` policy generalizing `concrete_only`; result edges; revalidation; hooks.
- **W-S1:** P1 as planned, with `Keyed` declared but unused, `Core.Dynamic/Compiled/Kept` as Core types.
- **W-S2a (no build, minutes):** the insertion count: specializations at non-final types per function with a bounded method, and for `Base.show`, in each port session.
- **W-S3:** the hand-written key prototype (one bound, two members, the adapter), measured against E-164.
- **W-S4a:** the toy shard with identity relocation, two environments, E-0's cases.
- **W-S4b (no build):** the count of external relocations in one pkgimage (the lookup's size).

**References to touch when adopted:** compiler §2 (the owner's role narrowed to the test bed), §7 (the shape of membership storage, cells, `Keyed`, the adapter), §3.1 (`Callable` on `OpaqueClosure`); facts §6 (the policy as a method property; result edges in G2's statement), §11 (the store's admission predicate); lowering (the encodings' removal list per stage); traits §6.7 (the key as `Keyed`), §14 (`<:` by entries). Alternatives: the second owner as the product setting's design; offsets in the key; a per-type table for guards (E-259 measured it).

---

## 10. Sources

Upstream Julia at `45b6d15e34` (v1.13.2), read with `git -C julia-1.13 show 45b6d15e34:<path>`:
- `src/julia.h`: `jl_code_instance_t` (`:452`, `edges` at `:475`, `owner` at `:455`), `jl_method_instance_t` (`:404`), `jl_datatype_t` (`:630`, `super` at `:633`, the bits at `:645`–`:646`), `jl_typename_t` (`:538`, `_unused:5` at `:560`, `concrete_only` at `:564`), `jl_method_t` (`interferences` `:333`, `recursion_relation` `:365`, `nospecialize` `:369`), `jl_methcache_t` (`:918`), `jl_methtable_t` (`:931`), `jl_method_match_t` (`:947`).
- `src/subtype.c`: `subtype` (`:1421`; the chain walks `:1535`, `:1580`), `jl_subtype_env` (`:2282`), `jl_subtype` (`:2350`), `jl_isa` (`:2513`), `intersect` on datatypes (`:3818`), `jl_has_empty_intersection` (`:4472`), `jl_type_intersection` (`:4699`), `type_morespecific_` (`:5341`; the super walk `:5484`), `jl_type_morespecific` (`:5552`).
- `src/jltypes.c`: `simple_subtype` (`:566`), `jl_type_union` (`:650`), `has_concrete_supertype` (`:1324`).
- `src/gf.c`: `jl_type_infer` (`:422`), `jl_mi_cache_insert` (`:766`), `jl_compilation_sig` (`:1170`), `jl_isa_compileable_sig` (`:1414`), `cache_method` (`:1634`), `jl_promote_ci_to_current` (`:1942`), `jl_mt_assoc_by_type` (`:1984`), `get_intersect_matches` (`:2064`), `invalidate_code_instance` (`:2168`), `_invalidate_backedges` (`:2216`), `jl_method_table_disable` (`:2754`), `jl_method_table_insert` (`:3204`), `jl_compile_method_internal` (`:3576`), `jl_normalize_to_compilable_sig` (`:3861`), `jl_normalize_to_compilable_mi` (`:3888`), `jl_apply_generic` (`:4391`), `ml_matches` (`:4926`).
- `src/typemap.c`: `jl_typemap_assoc_by_type` (`:926`), `jl_typemap_level_assoc_exact` (`:1175`), `jl_typemap_insert` (`:1513`).
- `src/datatype.c`: `jl_new_typename_in` (`:70`), `jl_new_abstracttype` (`:102`), `jl_new_datatype` (`:865`).
- `src/opaque_closure.c`: `new_opaque_closure` (`:31`, `oc->world` `:129`), `jl_new_opaque_closure` (`:137`).
- `src/codegen.cpp`: `emit_call_specfun_other` (`:5209`, `:5348`), `emit_invoke` (`:5424`, `:5441`), `emit_call` (`:5656`).
- `src/jitlayers.cpp`: `jl_compile_codeinst_now` (`:646`), `jl_compile_codeinst_impl` (`:869`).
- `src/aotcompile.cpp`: `jl_emit_native_impl` (`:784`), `jl_dump_native_impl` (`:2075`).
- `src/staticdata.c`: the relocation model (the file's header comment; `link_ids_relocs`, `buildid_depmods_idxs` `:341`–`:349`), `jl_write_values` (`:1367`), `jl_update_all_fptrs` (`:2269`), `jl_restore_package_image_from_stream` (`:4393`; `jl_activate_methods` at `:4461`).
- `src/staticdata_utils.c`: `queue_external_cis` (`:521`), `jl_activate_methods` (`:894`).
- `Compiler/src/abstractinterpretation.jl`: `abstract_call_gf_by_type` (`:122`; `is_concrete_only` at `:143`), `get_compileable_sig` (`:159`), `find_method_matches` (`:365`), `abstract_invoke` (`:2303`).
- `Compiler/src/inferencestate.jl`: `is_concrete_only` (`:1127`). `base/broadcast.jl:197` sets it for `broadcasted`.
- `Compiler/src/tfuncs.jl`: `typeassert_tfunc` (`:859`), `isa_tfunc` (`:877`), `subtype_tfunc` (`:917`).
- `Compiler/src/typeinfer.jl`: `finish!` (`:104`), `maybe_compress_codeinfo` (`:443`), `store_backedges` (`:761`), `compute_edges!` (`:790`), `typeinf_edge` (`:1036`).
- `Compiler/src/reinfer.jl`: the sentinel (`:10`), `verify_method_graph` (`:95`), `verify_method` (`:162`), `verify_call` (`:469`).
- `Compiler/src/ssair/inlining.jl`: `ir_inline_unionsplit!` (`:526`), `compileable_specialization` (`:770`), `resolve_todo` (`:835`).
- `base/loading.jl`: dependency build ids at load (`:1316`–`:1328`), `CacheFlags` (`:1721`).

The project's documents: the references; [abstract-types-as-traits](abstract-types-as-traits.md) §11, §13, §15, §16; [the unification plan](../plans/2026-10-29-unification-evidence.md); [the facts-keyed cache](../plans/2026-10-27-facts-keyed-cache.md) and [its store](../plans/2026-10-28-facts-cache-store.md); [AOT under facts](aot-under-facts.md); [julia-changes](../design/julia-changes.md); [the 1.14 scan](../record/julia-1.14-scan-2026-10-27.md); [performance explorations](../record/performance-explorations.md) PE-10 to PE-19; [evidence](../design/evidence.md) §2–§3; experiments E-164, E-180, E-188, E-194, E-195, E-205, E-212, E-233, E-234, E-252 to E-259.
