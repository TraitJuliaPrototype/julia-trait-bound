# Compiler and runtime: the reference

**Draft** (W-105; [the folder's README](README.md)). This page defines what Julia's compiler and runtime provide to the design: each interface, what it means, and its rules. It describes the interfaces as designed. The status line of each section says how far it is built.

- Why each interface is needed, and what compiled code may assume: [`facts.md`](facts.md).
- How the language uses them: [`traits.md`](traits.md) for what a user sees, [`lowering.md`](lowering.md) for what the library's macros emit.
- The build is branch `unified` of the julia repository, on v1.13.2 (the worktree `julia-unified/`), in the stages W-98 to W-104 ([the work queue](../record/todo.md)). The inventory of its changes: [`../design/julia-changes.md`](../design/julia-changes.md).
- Terms:
  - a **set** is an abstract type whose members may join after their definition: a trait;
  - a **membership** makes a type, a family, an abstract type or a set a member of a set;
  - a **fact signature** is a call signature at which only its stakeholders or a pirate can change dispatch ([facts §3](facts.md#3-fact-signatures));
  - a **run-time site** is a call compiled as a dynamic dispatch, with no edge;
  - the **policy** of a method is whether its code is compiled by facts or plainly.

## Summary

| Part | What it provides |
|---|---|
| [1. The facts inference](#1-the-facts-inference) | Inference that commits across a call only at a fact; run-time sites; `return_type`'s plain answers; effects |
| [2. The policy per method](#2-the-policy-per-method) | Which methods are compiled by facts; one CodeInstance per MethodInstance and policy; calls between policies |
| [3. The dependency record and the code slot](#3-the-dependency-record-and-the-code-slot) | What each CodeInstance assumed; G2 as a predicate; callers that survive a callee's recompilation |
| [4. Sets and memberships](#4-sets-and-memberships) | Open abstract types, memberships with worlds, transitive subtyping, intersections |
| [5. Dispatch](#5-dispatch) | Methods at sets in the method table, specificity, the ambiguity report, guards |
| [6. Keys and the attribute](#6-keys-and-the-attribute) | Code per key, per type or once, chosen per call; the calling convention; the definition-time check |
| [7. Operations on a value typed by its trait](#7-operations-on-a-value-typed-by-its-trait) | Declared results, the split over members, the table of targets, `Callable`'s call |
| [8. World-checked caches](#8-world-checked-caches-at-dynamic-boundaries) | Caches at dynamic boundaries checked against the caller's world |
| [9. Images and the machine-code cache](#9-images-and-the-machine-code-cache) | Memberships in package images; a record complete enough for a cache of machine code |
| [10. Hooks for the library](#10-hooks-for-the-library) | Definition and image hooks; field-offset intrinsics |
| [11. Changes useful without traits](#11-changes-useful-without-traits) | Inliner and reflection changes |

---

## 1. The facts inference

**The principle.** In code compiled by facts, a call is inferred, with an edge, only at a fact. Every other call is a run-time site, dispatched when it runs. So such code is invalidated only by stakeholders and pirates ([facts §2](facts.md#2-the-guarantees)).

### 1.1 The policy and the interpreter

```julia
Compiler.NativeInterpreter(world::UInt = get_world_counter(); facts::Bool = false, …)
Compiler.facts_mode(interp::AbstractInterpreter)::Bool
```

- `facts` says whether the interpreter infers calls only at facts. `false` is Julia's own inference.
- An inference of a MethodInstance runs with `facts` set to its method's policy (§2). Code of either policy is cached under Julia's own cache owner, with the policy in the CodeInstance's flags (§2.3).
- Only `NativeInterpreter` has the mode. Any other `AbstractInterpreter` infers by its own rules.

**Status:** Planned (W-100).

### 1.2 Fact signatures

```julia
Compiler.is_fact_sig(T)::Bool          # T: a call's argument types, as a Tuple type
Compiler.MAX_FACT_SPLITS = 4
```

`is_fact_sig(T)` is true when `T` is one of:
- a dispatch tuple: concrete types that are not kinds, and `Type{T}` with `T` known;
- a tuple without a `Vararg` tail whose elements are concrete, or tuple types of concrete elements or unions of concrete elements, split by Julia's union-splitting cost at the interpreter's `max_union_splitting`;
- concrete members followed by a `Vararg{E}` tail of a concrete member `E`;
- a closure's call at kinds: the first argument a closure type, every other concrete or one of `DataType`, `UnionAll`, `Union`.

A union at a call's top level is split as Julia splits it, each split a fact signature with its own edge.

**Not gated:** `invoke` and `hasmethod` at a declared signature resolve it as Julia does, with an invoke edge at the declared signature ([facts §3](facts.md#3-fact-signatures)).

A key in a call's signature: §6.4. An operation on a value typed by its trait: §7.

**Status:** Planned (W-100).

### 1.3 Run-time sites

```julia
Effects.nortsite::Bool          # no run-time site, here or in a callee
```

- **A run-time site is a call that records no edge.** Under the facts mode that is:
  - a call whose signature, or one of whose splits, is not a fact;
  - a call at a fact that Julia's method matching gives up on: more matches than `max_methods`, a call after `:latestworld`, an `invoke` it cannot resolve;
  - the fallback of a split over a set's members (§7.2).
- Its result type is `Any`, its exception type `Any`, its effects unknown, except where a declared result types it (§7.1). Codegen emits a dynamic dispatch.
- **It clears `nortsite`,** an effects bit carried to every caller as `nortcall` is, stored inverted in a CodeInstance's effects.

**Status:** Planned (W-100).

### 1.4 `return_type`

`Core.Compiler.return_type` asks what **plain** inference gives for a call. `collect` of a generator, `map` over an empty collection, broadcasting and `promote_op` use the answer, so it must be plain Julia's in the same world, under either policy.

```julia
Compiler.PlainRTInterp(world::UInt) <: AbstractInterpreter      # its own cache owner
```

**At compile time,** in code compiled by facts, `return_type` is decided in this order:
1. The facts answer, when it cannot be wider than plain inference's: a constant, a concrete type that is not a kind, or `Union{}`. It is folded.
2. Plain inference's answer, when it rests on facts:
   - the signature splits into at most four concrete signatures;
   - each has exactly one method that covers it;
   - every edge of each answer, transitively, is at a fact signature or an invoke edge at the method's own signature.

   The answer is folded, with an edge from the caller to each plain answer.
3. Otherwise a call at run time.

**At run time** the answer is plain inference's, from `PlainRTInterp`, which infers every method plainly. Its answers live under a cache owner of their own. No code runs from that cache.

**Status:** Planned (W-100). Optional: revalidating cached answers after loads ([PE-5](../record/performance-explorations.md)).

### 1.5 Effects

Under the facts mode no asserted effect applies over a run-time site, at any depth: a method's `@assume_effects` is ignored where its frame's `nortsite` is clear, and a statement's where its call's is ([facts §8](facts.md#8-asserted-effects)).

**Status:** Planned (W-100).

---

## 2. The policy per method

### 2.1 The module option

```julia
Base.Experimental.@compiler_options facts=true
```

- `facts=true` makes every method of the module compiled by facts, unless the method says otherwise. It emits `Expr(:meta, :facts, 1)` at the module's top level.
- The module flag (`jl_module_t.facts`): 0 plain, 1 facts, 2 never by facts (the compiler's own modules). A submodule takes its parent's flag when created. The flag is saved with the module in images.
- **Four more options,** set the same way and inherited and saved alike, serve the trait language's scopes ([traits §13](traits.md#13-scopes-trait-modules)):
  - `bounded=true`: an open method at a trait argument is refused (§6.7);
  - `no_pirates=true`: a pirate is refused by the library's definition hook;
  - `dynamic=true`: the default attribute of every trait argument of the module's methods is `Dynamic` (§6.3);
  - `first_seen=true`: where nothing else decides, a trait argument's attribute is what the caller knows (§6.3, step 5).
- A module's other compiler options (`optimize`, `compile`, `infer`, `max_methods`) apply to its code under either policy.

**Status:** Planned (W-100, W-103).

### 2.2 The method flag

```julia
Expr(:meta, :facts_boundary)   # compiled in the policy of the code that reaches it
Expr(:meta, :facts_always)     # always compiled by facts
```

- `Method.facts::UInt8`: 0 as its module says; 1 a boundary; 2 always facts. Lowering carries the meta into every method a definition makes (keyword sorters, positional forwarders). It is saved with the method.

**Status:** Planned (W-100).

### 2.3 One CodeInstance per MethodInstance and policy

- **The policy of a method's code:**

  | Method | Policy |
  |---|---|
  | always facts, or in a module of flag 1 | facts |
  | in a module of flag 2 (the compiler) | plain |
  | a boundary | the policy of the code that reaches it |
  | any other (a *neutral* method) | the session's default: plain in the product setting, facts under the test bed (§2.5) |

- **A CodeInstance records its policy** in its flags. A lookup asks for the policy the method has; a CodeInstance of the other policy never stands in.
- So a neutral method in the product setting has plain code only, whoever calls it. A boundary has up to one CodeInstance per policy.
- Under `--trim` every method is plain (§2.6).

**Status:** Planned (W-100).

### 2.4 Calls between policies

- **In inference,** a callee whose policy differs from the caller's is inferred under its own policy, in an inference of its own. The caller records:
  - a **result edge** where it emits the call and uses its result type, exception type, effects or a constant result as a type;
  - a **code edge** where it inlines the callee, propagates constants into it or evaluates it at compile time.
- **Constant propagation from plain code into a facts callee** infers the callee again for the constants under the facts policy, in a call stack of its own; the result is the caller's, the edges that inference's.
- **Concrete and semi-concrete evaluation** of a facts callee from plain code use its effects as facts inferred them, with a code edge to its CodeInstance; not over a run-time site.
- A facts caller of the compiler's own plain code propagates no constants into it.
- **At run time,** every dispatch runs the selected method's code of its policy, whoever dispatches: generic calls, `invoke`, `_apply_iterate`, `invokelatest`, `jl_apply`, `@cfunction` pointers, finalizers, task entry.

**Status:** Planned (W-100).

### 2.5 The test bed

- With `JULIA_COMPILE_BY_FACTS=1` (Planned spelling: `--compile-by-facts=all`), every neutral method's policy is facts: *the test bed* `all`. The compiler stays plain.
- An image records the policy of each CodeInstance, so it is correct under either setting. The other setting finds no code of its policy and compiles it. The test bed keeps a depot of its own, for speed.

**Status:** Planned (W-100).

### 2.6 `--trim`

A trimmed build has no facts policy: every method is inferred plainly, and the image writes no facts flags. A binary is a closed world ([facts §13.3](facts.md#133-trimmed-binaries)).

**Status:** Planned (W-100).

---

## 3. The dependency record and the code slot

### 3.1 The record

A CodeInstance's edges name everything its code assumed:
- **dispatch edges:** facts at signatures, including "no method" and "ambiguous";
- **result edges:** an emitted call whose result type, exception type, effects or constant the caller used as a type. Nothing else is a result edge;
- **code edges:** the identity of each inlined, constant-propagated or concretely evaluated callee: the method and a digest of its lowered code;
- **binding edges:** the global bindings it reads;
- **layout identities:** the types whose fields it reads, by path and layout;
- **membership cells** (§5.6) and **positive memberships** it folded (§4.8).

The backedge iterator, `verify_method`, codegen's walkers and the image writer read every kind. Targets are named by identities stable across sessions where one serves (§9).

**Status:** Planned (W-100).

### 3.2 G2 as a predicate

When a CodeInstance is finished, a bit in its flags records whether its record satisfies G2:
- every dispatch edge is at a fact signature;
- every inlined callee's own record satisfies G2;
- result edges may go anywhere.

Strict mode and the concreteness checks read it.

**Status:** Planned (W-100).

### 3.3 The code slot

- **One slot per (MethodInstance, calling convention)** holds the current valid code's pointer and its validity. It is written when a CodeInstance of that MethodInstance compiles and when one is invalidated.
- **A static call that holds only a result edge to its callee** loads its target through the slot. Every other call binds the callee's address.
- **When a callee is replaced,** a caller holding only result edges to it is marked for revalidation, not invalidated. Its next lookup compares each result edge with the callee's current result:
  - equal: the caller is valid again in the current world;
  - different: the caller is inferred again.
- So G2 covers a facts caller of a plain callee whose result its recompilation leaves unchanged ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Planned (W-101).

---

## 4. Sets and memberships

### 4.1 Sets

- **A set** is an abstract type whose `TypeName` has the `open` bit. A trait's declaration sets it; a set is open from its declaration.
- Every other abstract type is closed, Base's and Core's included.
- **`never_member`:** a bit on Core's kinds (`DataType`, `UnionAll`, `Union`, `TypeVar`, `Module`), the builtins' types, opaque closures and the memory types. A membership of one is refused.
- A set's declared supertype is `Any` or a set. A closed abstract type is never a member of a closed abstract type through a set.
- **A set's `TypeName` carries its contract,** written once by the library at the declaration and saved with it in images ([lowering §2](lowering.md#2-trait)):
  - the operations, each with the trait's method that carries its declared result (§6.8);
  - the declared fields, with their types and whether read-only;
  - each parameter's definition;
  - the default attribute bit (§6.3).

  The compiler reads it without an edge: it never changes after the declaration.

**Status:** Planned (W-98, W-102). Built in part on branch `unified` (C-24). The contract on the `TypeName`: mine (2026-11-06).

### 4.2 Memberships

- **A membership is an immutable entry on the member's `TypeName`,** never on the set's:
  - the set;
  - the member pattern: `S`, `S{T} where T`, an abstract type, a set instance, `Type{S}`;
  - the set's instance for the pattern (`X`, `X{T}`);
  - the receiver: the member itself, its forwarding field, or none where defaults serve every operation (§6.1);
  - `min_world` and `max_world`;
  - the declaring module;
  - the forwarding field, if any.
- A `TypeName`'s list of entries is replaced copy-on-write; readers take no lock.
- `jl_declare_membership(member, set_instance, declarer, by, receiver)` declares one. The library checks ownership and the contract first ([traits §5.10](traits.md#510-checks)).
- **A pattern's variable bounded by a `Union` of types** (`I where {I <: Base.BitInteger}`) is declared as one entry per type of the union.
- **`struct S <: X`** with a set `X` makes `X` the declared supertype of `S`, as for any abstract type. It needs no entry. The library's `@implement X S`, which the language requires after it, records `S`'s receiver on `S`'s `TypeName`, with its world, as an entry would ([lowering §3](lowering.md#3-implement)).

**Status:** Planned (W-98). Built in part (C-21).

### 4.3 Worlds

- A membership is declared as a method is inserted: under the world counter's lock, the entry gets `min_world = counter + 1`, is published, and the counter advances.
- The library's declaration is followed by `Expr(:latestworld)`, so the declaring code sees its own membership.
- A task in an older world does not see it.
- **Memberships only grow.** A redeclared membership gives the old entry a `max_world`, declares a new one, and invalidates the code compiled at the old key and the callers that folded against it.
- **`Callable`'s memberships** follow its members' methods (§7.4): a method definition can begin or end one. They are the one kind that can end.

**Status:** Planned (W-98). C-25.

### 4.4 Transitivity

- `A <: B` and `B <: C` give `A <: C`, whichever link is a declared supertype, a membership, or a set's membership in a set.
- **`<:`, `isa`, intersection and dispatch read the same relation,** so `isa(x, T)` and `typeof(x) <: T` agree.
- The entries of every type on a member's supertype chain are consulted.
- A composed membership holds from the latest `min_world` of its links; with several chains, from the earliest of those.
- A membership that would close a cycle among sets is refused, by a check over every path.

**Status:** Planned (W-98). C-22, C-23.

### 4.5 Subtyping

- **A membership is one more supertype of its member, inside subtyping's walk.** Where `S`'s supertype chain does not meet an open `X`, `jl_subtype` takes the entries of `S` and of each type on its chain. For each entry, it continues the same walk from the entry's instance, in the same environment, as it continues from a declared supertype. The pattern's variables join the walk as existential variables. The choice among a type's entries is made as a union's is.
- So set-in-set entries are followed transitively, and a miss is `false`.
- **Parameters are invariant.** With `S`'s entry for `X{Int}`: `S <: X{Int}`, `S <: X{<:Real}` and `S <: X{>:Int}` hold; `S <: X{Real}` does not.
- **A method's `where` variables and `X{<:T}`'s existential variables** are the walk's own. So dispatch at `f(::X{<:T})` and `f(::X{T}) where {T}` sees members as `<:` does.
- **Only entries whose set reaches the queried set are choices.** Reachability between two `TypeName`s is memoized per world range. So a type with many entries on its chain (BaseTraits' families on `AbstractVector`) costs a walk only for the entries that can lead to the set asked about.

**Status:** Planned (W-98). C-26.

### 4.6 One instance per member

A membership that would give a member a second instance of a set, differing in a parameter that is not an input, is refused at `jl_declare_membership`. The runtime checks it: exactly for a concrete member; for a pattern, by intersecting it with each pattern that already reaches the set. The library reports the refusal as `ImplementError`.

**Status:** Planned (W-98).

### 4.7 Three layers

Questions about open sets are answered in three layers:
- **`<:` and `isa`** read the entries: the answer in the current world.
- **`jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint` and the type cache** stay exact in the current world: a known member keeps the exact result; a non-member gives `Union{}`. Dispatch's match construction and the inliner's union split see only members.
- **`jl_could_join(S, X)`** answers whether `S` could become a member of `X`. Inference's lattice and the guards' shadow query (§5.6) use it; dispatch's match construction does not.

**Status:** Planned (W-98).

### 4.8 Negatives never fold; positives through entries

- **A negative answer is never folded for an open set.** `has_open_set(t)` is true when `t`, a parameter of `t`, a component of a union or intersection in `t` is an open set or a key (§6.1); it is cached on the type object.
- `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the `hasintersect` sites and `Conditional` refinement consult it before folding a negative.
- **Exceptions** (the answer is final): a closed abstract type; a type with the `never_member` bit.
- **A positive answer folds only through an entry,** and the fold raises the CodeInstance's `min_world` to the entry's. So a task in an older world never runs code that assumed the membership.

**Status:** Planned (W-98, W-102 for the fold's world).

### 4.9 Intersections

```julia
Core.All{X, Y}
```

- **`All{X, Y, …}` is an intersection type,** the dual of `Union`:
  - `S <: All{X, Y}` when `S <: X` and `S <: Y`;
  - `All{X, Y} <: Z` when some component is a subtype of `Z`, and `<: All{Z, W}` when it is a subtype of each.
- **Normal form:** components flattened, sorted by the order `Union` uses, deduplicated; a component that is a subtype of another by declared supertypes absorbs it; two closed types with no common subtype give `Union{}`.
- **Normal forms read declared supertypes only.** A membership never absorbs a component of an `All` or a `Union`: `Union{S, X}` stays as written where `S` is a member of `X` by an entry. So a type expression gives the same type object in every world.
- `jl_type_intersection` of two sets is `All{X, Y}` with their known common members' exactness kept; `type_morespecific_` ranks `All{X, Y}` above each component, and an intersection with a closed component as a closed type against an open set (§5.2).
- **At an argument typed by an intersection,** the key is the tuple of the member's keys for each component (§6.1); the split's candidates are the first component's that are members of every component (§7.2).
- The negative-fold rule (§4.8) treats each component.
- It takes any number of components: `All{X, Y, Z, …}`.

**Status:** Planned (W-98; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}"). Normal forms by declared supertypes, keys and candidates at an intersection: mine (2026-11-06, the reviews of the draft).

### 4.10 Type values

A type value is a member of a set only by an entry whose pattern is `Type{S}`. Such an entry is kept on `S`'s `TypeName`, marked as being for the type value, not on `Type`'s. `jl_isa`'s branch for a type value and `intersect` consult such entries. An entry for `S` answers `S <: X`, never `S isa X`.

**Status:** Planned (W-98). C-19.

### 4.11 Inference's world

Membership queries during inference run at the world being inferred for, carried from `ml_matches` and the insertion walk into the membership lookup, not at the world the compiler runs in.

**Status:** Planned (W-98, W-99).

---

## 5. Dispatch

A method whose signature names a set is a plain method at that set. Memberships and dispatch follow these rules:
- **Memberships only grow.** Positive answers fold; negative ones never, for an open set (§4.8).
- **Memberships invalidate no code.** A call that a later membership could change carries a guard (§5.6).
- **Methods invalidate as in Julia,** under ownership ([facts §2.2](facts.md#22-g2-stable-caches)).

### 5.1 The method table

A method whose signature names an open set goes into its typemap's linear list, never under a typename's index. A query at a member reaches it, since the member's supertype chain need not name the set. A set-to-methods index serves the ambiguity report (§5.4) and compiling ahead (§9).

**Status:** Planned (W-99). Built in part.

### 5.2 Specificity

In `type_morespecific_`, at each argument:
- a closed type other than `Any` is more specific than an open set;
- between open sets, by subtyping: a set whose membership in another makes it a subtype is more specific; else unordered;
- an intersection is more specific than each component; one with a closed component counts as closed against an open set.

So `Method.interferences`, `detect_ambiguities` and the insertion walk order these pairs as any others. Inserting `f(::X)` reaches only the specializations of `f(::Any)` and the "no method" facts. The `obviously_disjoint` short-circuit is bypassed where either side has an open set.

**Status:** Planned (W-99). Built in part.

### 5.3 Match world ranges and abstract queries

- A match through an entry carries the entry's `min_world` into its valid worlds, at fixed, vararg and union argument positions.
- At an abstract query whose type is not a member, a method at a set is pruned, as any method with an empty intersection is.

**Status:** Planned (W-99).

### 5.4 The ambiguity report at a membership

At `jl_declare_membership`, for each function with a method at the new set and a method at another set the member is in, with no method more specific for the member, a warning names the pair and the joint method's signature. Strict mode makes it an error. A method that dominates every common member suppresses it.

**Status:** Planned (W-99).

### 5.5 A membership lowers dispatch caches

A membership lowers the `max_world` of each leaf-cache and typemap-cache entry whose selected method changes at the new member, so the next call looks up again. It invalidates no CodeInstance: compiled calls it could change carry guards (§5.6).

**Status:** Planned (W-99, W-102). Until the guards exist: C-18.

### 5.6 Guards and cells

- **The shadow query.** Inference at a call `f(s::S)` with `S` concrete selects a method `m₀`. It also asks for the methods of `f` at open sets `Z` that `S` could join (`jl_could_join`) and that would beat `m₀` at `S`. A method matched through `S`'s supertype chain, other than `f(::Any)`, has none. Each such (set, argument) is a shadow.
- **The cell.** For each shadow, inference records an edge to a membership cell: one mutable object per (member type object, set) for a parametric member, per (member typename, set) otherwise. The compiler creates it on demand and hangs it on the member's `TypeName`. Its `min_world` is `typemax` until an entry matches, then the entry's.
- **The guard** loads the cell's `min_world`, compares it with the task's world, and branches, as the inliner's union split branches. The slow branch is a full dispatch with no edge; the fast branch is the static call to `m₀`. The load is hoisted out of loops.
- **The guarded call's result** is the join of `m₀`'s and the declared result of the shadowing method (§6.8); `Any` where none is declared.
- **`Callable`'s memberships** (§7.4) have cells as any membership does; a method definition of the member's type lowers the cells it changes.
- **No guard arises:**
  - at a final non-member (§4.8);
  - where `m₀` matched through the chain and is not `f(::Any)`;
  - at a function with no method at an open set.
- A method at an open set defined later invalidates the compiled callers its insertion reaches; they compile again with the guard.

**Status:** Planned (W-102).

---

## 6. Keys and the attribute

### 6.1 The key as a type

```julia
Core.TraitKey{X, R, F}
```

- `TraitKey{X, R, F}` names the members of `X` whose receiver type is `R` and whose declared fields' types are `F`, a tuple type ([traits §7.2](traits.md#72-the-key)).
- **The runtime computes a member's key** from its membership and the set's contract, without running Julia code: the receiver the entry records (the member, its forwarding field's type, or none), the declared fields' types at the member (`fieldtype`), and the parameter values (the pattern's match). A member of a pattern has its key from the entry like any other. The answer is memoized per (member type, set) on the member's `TypeName`, with the membership's worlds.
- `S <: TraitKey{X, R, F}` holds when `S`'s key for `X`, computed in the world asked about, is that key. It is a case of `subtype`, as `Type{T}` is, and likewise of `intersect`, `type_morespecific_`, `obviously_disjoint`, `jl_isa_compileable_sig` and `jl_compilation_sig`.
- **At an intersection** `All{X, Y}`, the key is the tuple of the member's keys for each component.
- **The erased key** is the set's instance `X{p…}` itself.
- It is never written by a user. It prints as the key: `ColTable at Vector{Vector{Float64}}`, in `show`, `show_tuple_as_call`, `MethodError` and reflection.

**Status:** Planned (W-102); the name `TraitKey`, beside BaseTraits' trait `Keyed`, is mine (2026-11-06). Keys computed by the runtime from memberships: mine (2026-11-06, [the work plan's review](../plans/2026-11-06-work-plan-under-the-draft-reference.md) §6, weak point 4).

### 6.2 Compilation signatures

At each argument whose declared type is a set, or a parameter bounded by one, a method's compilation signature is one of:
- **per key:** `TraitKey{X, R, F}`, the member's key (§6.1), where the method is fully bounded at the argument (§6.7) and the attribute is `Compiled`. Inference runs once per key, by the path `@nospecializeinfer` takes;
- **per type:** the member's type, where the method is open at the argument and the attribute is `Compiled`;
- **once:** the erased key `X{p…}`, where the attribute is `Dynamic`.

A value whose type is `Dynamic{X}` has the erased key by its type ([traits §7.7](traits.md#77-dynamicx)).

- So one (method, argument tuple) has up to two compilation signatures per trait argument, chosen per call (§6.3): up to 2ⁿ for n trait arguments, each compiled only where a call asks for it.
- Keyed instances are cached with their original tuple (`cache_with_orig`), so a concrete tuple maps to its keyed or its erased instance. A plain dynamic call's attribute is a function of the method and the tuple (§6.3), so the leaf cache keys entries by the tuple alone; `Core.attributed_call` has a cache of its own (§6.9).
- **Static parameters** bound by a keyed argument are those the key fixes. A method whose body uses a static parameter the key does not fix is open at that argument.

**Status:** Planned (W-102).

### 6.3 The attribute at a call

- **Each trait argument of a call has an attribute bit,** `Compiled` or `Dynamic`, which chooses its compilation signature.
- **It is resolved, strongest first** ([traits §7.5](traits.md#75-what-decides)):
  1. a cast written at the call (§6.9);
  2. an attribute the value carries:
     - an argument inside an instance compiled per key or per type is `Compiled`, inside an instance compiled once `Dynamic`. The instance's attribute is part of its CodeInstance, so inference knows it at every call that passes the argument on;
     - a value of type `Dynamic{X}` is `Dynamic`;
     - a value read from a field whose declared type is a struct parameter bounded by a set: inference tracks the attribute the parameter records, `Dynamic` for a `Dynamic{X}`, else `Compiled`;
  3. the method's attribute bits at the argument, from `@nospecialize` (`Dynamic`) and `@specialize` (`Compiled`) at an argument typed by a set, saved with the method as its `nospecialize` bits are; then the module's option;
  4. the set's default bit, except for a value whose type Julia's own modules or the set's own package define;
  5. the method's module's fallback: with `first_seen` (§2.1), `Compiled` at a static call whose caller infers the argument's concrete type, `Dynamic` at a dynamic call; otherwise `Compiled`.
- **A static call** resolves the bits in the caller's inference and invokes the instance.
- **A dynamic call with bits from 1 or 2** is a call of `Core.attributed_call` (§6.9): a cast written at the call, or a run-time site that passes on a trait argument of an instance compiled per key or once (codegen emits it there). It selects the method by the arguments' types as `jl_apply_generic` does, then resolves the rest (3 to 5) at the method.
- **A plain dynamic call** carries no bits. The runtime resolves 3 to 5 at the method: a function of the method, the tuple and the module's options. So `jl_apply_generic` and its caches stay Julia's.
- **The interpreter** passes the bits of casts written at the call, and resolves the rest at the method.

**Status:** Planned (W-102); the order is mine (2026-11-06), on the user's "Dynamic or not as a trait and library default, that the user can override"; the fallback by scope is the user's (2026-11-06). Bits only through `Core.attributed_call`: mine (2026-11-06, the work plan's review, S6).

### 6.4 Calls from code compiled per key

- Code compiled per key holds the argument at the type `TraitKey{X, R, F}`. Operations and declared fields act on its parts (§6.5), whose types are concrete: each call there is at a fact.
- **Passing the argument on to another function `g`:**
  - **static** where the method of `g` selected at the key is the one selected for every member with that key in the current world. A guard reads a cell per (key, `g`). A later membership with that key lowers the cell when some method of `g` is more specific for the new member (found through the set-to-methods index at `jl_declare_membership`). A later method of `g` invalidates the caller through its dispatch edge at the key, as any insertion does;
  - **otherwise a run-time site,** dispatched on the object with the `Compiled` bit; the instance then receives the object (§6.5).
- Swift and Rust resolve such a call where the generic code is written, at the constraint. Julia dispatches it on the value's type, and G1 asks for Julia's answer. So the guard is what keeps the shared code equal to that answer, by the same mechanism as a membership's guard (§5.6).

**Status:** Planned (W-102); mine (2026-11-06).

### 6.5 The calling convention

A static caller passes a keyed argument as its parts:
- the receiver, by its own convention;
- each declared field that is `@const`, or of an immutable member, by value;
- each writable declared field as a field reference: the object and an offset, so a write reaches the caller's object (§10.3);
- the object itself, boxed, where the method may keep the value, return it, or pass it to a run-time site. An escape pass of inference decides this per instance.

**The parts in the trait's methods.** The trait's method for an operation (§6.8) reaches the receiver and the declared fields through two intrinsics:

```julia
Core.trait_receiver(t, X)          # the receiver: t itself, or its forwarding field
Core.trait_field(t, X, name)       # a declared field
```

At a key, inference resolves them to the parts above. At a member, it resolves them to `t` or to the forwarding field's `getfield`. So members that share a key and forward through fields of different names share the code.

**Status:** Planned (W-102).

### 6.6 The boxed adapter

A dynamic call to a keyed instance goes through one wrapper per keyed CodeInstance. The wrapper reads the receiver's and the fields' offsets from a table per (member typename, set) on the member's `TypeName`. If it costs more than the target in [the evidence](../design/evidence.md) §2, there is one wrapper per member instead (W-102 measures).

**Status:** Planned (W-102).

### 6.7 The definition-time check

- **One inference of a method at the erased signature** of each set argument, under a check flag of the native interpreter. There, operations of the set and its supertraits resolve to their declared results (§6.8), declared fields to their declared types, and calls passing the argument to a method at the set or a supertrait to that method.
- **Any other use of the argument** is recorded with its line, and inference continues past it at `Any`. The record decides the method's classification per argument, fully bounded or open. The classification is kept with edges to the unannotated functions it followed, so a later definition of one classifies the method again.
- **Under the `bounded` option** of the method's module or the method itself, an open argument raises `TraitUseError` listing every recorded use, at the method's definition or at the definition that opens it. A method marked `@open` (`Expr(:meta, :bounded, false)`) is exempt.
- Unannotated functions of the same module to which the method passes the argument are followed. A method that calls a function not yet defined is classified at its module's end, or at its first call.
- **A function of `Self` that an equation names** (`T = eltype(Self)`), called on the argument, resolves to the parameter's value, a constant of the key: `eltype(t)` keeps a method fully bounded where the trait defines `T = eltype(Self)`. So do Rust's associated types in generic code.

**Status:** Planned (W-102; the classification and the `bounded` option: the user, 2026-11-06, Q2 (a)). The rule for equations is mine (2026-11-06; open issue 137). The classification kept with edges, and `@open`: mine (2026-11-06, the reviews of the draft).

### 6.8 A declared result on `Method`

- Lowering records `f(…)::RT` as the method's declared result. Inference may read it as an upper bound, since the body asserts it.
- **The trait's method for an operation** carries the operation's declared result, with a flag that it covers every member: each member's serving method is checked to infer within it ([traits §5.10](traits.md#510-checks)). §7 relies on the flag.

**Status:** Planned (W-102).

### 6.9 Casts and `keep`

- **Lowering turns a call with cast arguments,** `f(compiled_for(x), y)` or `f(with_dynamic(x))`, into `Core.attributed_call(bits, f, args…)`, a builtin that dispatches as the call with those attribute bits. Inference resolves it statically where it can. A cast anywhere else is a lowering error. A cast of a `Dynamic{X}` to `Compiled` passes the held object.
- **The front end reserves the names** `compiled_for` and `with_dynamic` as it reserves `ccall`: in a call's arguments they are the casts whatever the scope binds, and a local variable or a definition of either name is a lowering error.
- **A cast at an argument the selected method does not type by a set** has no effect. Inference records each such cast it finds; `detect_unused_casts(mod)` lists them.
- `Core.attributed_call` keeps a cache of its own, keyed by the tuple and the bits.
- **`Core.Dynamic{X}`** is an ordinary struct of `Core`, with no rule of subtyping: its memberships are declared by the library ([lowering §7](lowering.md#7-dynamicx-keep-casts)). `Core` defines it so that `keep` can make one.
- **`keep(x)`** for an argument `x` at a set `X` resolves where the instance is compiled: `Dynamic{X}(x)` in an instance compiled once for the argument, `x` otherwise. Where the code is not compiled, it is resolved at the method's default attribute.
- Julia's call-site `@inline` and `@noinline` are the precedent: a statement about one call, written at the call.

**Status:** Planned (W-102); mine (2026-11-06). Reserved names, `Dynamic` in `Core`: mine (2026-11-06, the reviews of the draft).

---

## 7. Operations on a value typed by its trait

### 7.1 The rule

- **A call of an operation of `X`** whose receiver's inferred type is a set instance `X{p…}` (not a key and not a concrete member) is inferred as the operation's declared result at those parameter values. The declared result comes from the trait's method's flag (§6.8).
- The call is compiled as a split (§7.2), with the result asserted to the declared type (`TypeError`).
- A declared field read at such a value works the same way, and so does `getproperty` at a constant name `N` where the set is a subtype of a `HasProperty{N, R}`: its result is `R`.
- Under the facts mode, each branch of the split is a fact; the fallback is a run-time site.

**Status:** Planned (W-102).

### 7.2 The split

```julia
Compiler.split_call(K, ::Type{RT}, f, x, args...)            # f(x, args...)::RT
Compiler.register_dynamic_candidate!(K, C)
Compiler.dynamic_candidates(K)::Vector{Any}                   # the first MAX_FACT_SPLITS, in order
```

- **The candidates of a set** are its concrete members in declaration order, from an index per set that the runtime keeps. An entry records its declaration's file and line; the order is by those. A concrete type joins the index at its membership, a member of a pattern at its first use (§10.4). The index is read without an edge.
- **At an intersection** `All{X, Y}`, the candidates are those of `X`'s index that are members of every component.
- `register_dynamic_candidate!(K, C)` registers candidates for a key `K` that is not a set.
- **Inference:** where `x`'s type is not concrete and the set has candidates, `f` is inferred at `x`'s type intersected with the union of the first four candidates; each split is a fact with its edge.
- **The split:** the inliner splits the call over them. The last branch, the fallback, calls through the table of the call's targets (§7.3), or is the dynamic call where no table applies. The split is never fully covered.
- **The result:** each case not known to be an `RT`, and the fallback, are asserted to `RT`; the join is `RT`.
- **Which candidates a caller splits over is fixed when it is compiled.** A member registered later reaches the fallback, and invalidates nothing.
- Registration is lock-free for readers: the table is replaced on each registration.

**Status:** Planned (W-102).

### 7.3 The table of a call's targets

```c
void *jl_split_table_ptr(jl_value_t *tbl, jl_value_t *T);
```

- A value of a type outside a split's candidates is called through a table of the call's targets, keyed by its type:

  ```julia
  T  = Core.typeof(x)
  fp = foreigncall(:jl_split_table_ptr, Ptr{Cvoid}, (Any, Any), table, T)
  r  = foreigncall(fp, R, (Any, Any, A...), f, x, args...)
  ```

- **The table** belongs to the call's signature: the function's type, the other arguments' types, the result type, and the caller's policy. Sites with that signature share it.
- **A miss** makes the pointer in the caller's world and adds it. The pointer is a `:caller_world` `cfunction` (§8.1) of a target whose method asserts each argument and the result. A type with no method for the call gets a pointer that raises the `MethodError` the call would.
- **Arguments and result** pass by value where the type is an isbits type of nonzero size, else boxed.
- **The fallback stays a run-time site:** it dispatches in the caller's world and records no edge. The table needs no invalidation.
- **Sessions:** pointers are valid in their session; a table saved in an image counts as empty in another.
- **Threads:** a table's state is replaced on each addition, never mutated; readers take no lock.
- **Applies to** a split whose function's type is concrete and not a kind, with at most six arguments after the value. Elsewhere the fallback is the dynamic call. In a trimmed program the fallback is the dynamic call.
- **Ahead of time:** for each member declared in a package, its targets and their thunks are compiled into that package's image, at each call signature whose other arguments are concrete. A target whose call has abstract further arguments is made at its first call.

**Status:** Planned (W-102).

### 7.4 `Callable`'s call

**Memberships.**
- `Core.Callable{A, S}` is a set with two input parameters. `F <: Callable{A, S}` holds where a call of an `F` at `A` selects a method (`hasmethod`), for every `S`. So dispatch picks by the arguments' signature, and `S` takes no part in membership.
- **The answer is a query of `F`'s method table** in the world asked about, memoized per (`F`, `A`) with its world range; a method definition of `F` lowers the memo's range. A query that reaches itself again answers no. Subtyping runs no inference.
- **`Dynamic{Z}` with `Z <: Callable{A, S}`** is a member by the entry the library declares, as for any set ([lowering §9](lowering.md#9-callable)), never by a query of its call method.
- **Negatives are never folded:** a call whose method a later membership could change is guarded (§5.6). Compiled code that relies on a membership holds an edge to `F`'s dispatch at `A`, and is invalidated with it.
- `Callable` alone is any type with a call method.

**The call.**
- **A call of a value the code knows as a `Callable{A, S}`** (declared so as an argument, a field or an element, or a `Dynamic{Callable{A, S}}`) has the result type `S`, asserted on return (`TypeError`). Where inference proves the result, the assertion costs nothing. Each argument must be of `A`, or the call raises `MethodError`.
- **In an instance compiled once** for the argument, the call goes through a `:caller_world` pointer (§8.1) to the function's code compiled for `A`. The pointer is made at the first call per (signature, function type). The result is asserted to `S` (`TypeError`).
- **In an instance compiled per key,** whose key is the function's type, the call is direct.

This is `Callable`'s own handling, as Rust's `Fn` traits are the compiler's own. Swift's function types are matched by signature in overload resolution.

**Status:** Planned (W-102). Dispatch by signature, `S` checked on return: the user (2026-11-06). The method-table query inside subtyping and its memo: mine (2026-11-06).

---

## 8. World-checked caches at dynamic boundaries

**The principle.** Every cache that skips a dispatch at run time holds world ranges and is checked against the caller's world. A cache never decides which method runs; it remembers what dispatch decided, for the worlds where that holds.

### 8.1 The `cfunction` calling convention `:caller_world`

```julia
Expr(:cfunction, Ptr{Cvoid}, QuoteNode(f), rettype, :(Core.svec(argtypes...)), QuoteNode(:caller_world))
```

- A call through the pointer runs in the caller's world (the task's world age), as a direct call does.
- The pointer's thunk is a world-checked cache:
  - each target is an entry: a function pointer, its CodeInstance, and a range of worlds where both the dispatch of the signature and the CodeInstance hold;
  - a call in the current entry's range calls it directly; any other looks up its world and adds an entry.
- A thread with no world (a C callback) uses the latest world. A signature one method covers only in part dispatches dynamically, in the caller's world.
- An entry stays valid until invalidation lowers what it copies: its range ends at the copied method-cache entry's and CodeInstance's `max_world`.

**Status:** Planned (W-102).

### 8.2 The per-call-site dispatch cache

- Julia's `call_cache` holds method-cache entries per call site. Two kinds are added:
  - **wildcard entries:** a method-cache entry with no `Vararg`, no type variables and no guard signatures, whose parameters are concrete or `Any`, matched where every non-`Any` position has the argument's exact type;
  - **exact-type entries:** for any other entry, a new entry at the call's exact argument types.
- A plain dynamic call carries no attribute bits (§6.3), so entries are keyed as Julia's are.
- Each entry's range is the copied entry's; a call outside it looks up again.

**Status:** Planned (W-102).

### 8.3 Further work

Optional, each only if a measurement asks for it:
- a runtime table of compiled entry points with their world ranges;
- a witness carried in the value;
- recompiling in the background with the observed types;
- a cache emitted by codegen with direct calls.

**Status:** Optional.

---

## 9. Images and the machine-code cache

- **Memberships in package images.** An image writes the entries it declares on other modules' typenames in a list of its own, as it writes its methods for other modules' functions. At load the list is activated before the image's code is validated: the entries get the loading session's worlds. Validation knows the membership cell and positive-membership edge kinds.
- **Machine code only for code that runs:** CodeInstances of either policy; never `return_type`'s answers.
- **An image keeps no external code specialized at a signature type without a hash** (a value-specific instance). Its insertion at load would scan its method's specializations.
- **The checks' records** of members checked while the image was built (traits §5.10) are kept with it.
- **Compiling ahead:** for each membership a package declares, the set-to-methods index (§5.1) gives the methods at the set and its supersets to compile at the member's key ([traits §16](traits.md#16-compiling-ahead-closed-programs)).
- **A machine-code cache across sessions is the goal of the record.** The record of §3.1 is kept complete, naming its targets by identities stable across sessions:
  - a method by module path, name, signature and a digest of its lowered code;
  - a type by path and layout;
  - a membership by member, set and declarer.

  So a cache of machine code later adds a loader, not a mechanism. The cache itself is paused ([decisions](../record/decisions.md) §5).
- No part of this design stores a world, a session object or an address where a stable identity serves.

**Status:** Planned (W-103; the cache paused).

---

## 10. Hooks for the library

### 10.1 Definition and image hooks

```c
void jl_set_method_definition_hook(jl_value_t *hook);   // hook(m::Method, after::Bool)
void jl_set_image_methods_hook(jl_value_t *hook);       // hook(ms::Vector{Any}, pkg::String) -> methods to leave inactive
void jl_set_module_end_hook(jl_value_t *hook);          // hook(m::Module)
```

- **The definition hook** runs twice per method definition: before the method enters the table, where it may throw to refuse it (no world is allocated), and once it is visible.
- **The image hook** runs once per package image, with its methods for other modules' functions, before any is activated. Methods it returns stay inactive.
- Both run in the latest world, outside the world-counter lock, not for a definition a hook makes, and not while the system image is built.
- **The module-end hook** runs when a module's definition ends (`jl_eval_module_expr`), and for a package also while its image is written. The library classifies there the methods that waited for later definitions, and refuses a `struct S <: X` without its `@implement`.
- Strict mode, the override rule, the `no_pirates` and `bounded` options use them.

**Status:** Planned (W-103). The module-end hook: mine (2026-11-06, the work plan's review, weak point 6).

### 10.2 Hooks for strict mode

- **A deletion hook,** called at method deletion; it may refuse.
- **A hook for a binding redefined from another module,** at its source.
- **A report per image:** the edges that failed validation, with the winning method.

**Status:** Planned (W-103).

### 10.3 Field-offset intrinsics

```julia
Core.Intrinsics.getfield_at_offset(obj, T::Type, off::Int)::T
Core.Intrinsics.setfield_at_offset(obj, T::Type, off::Int, x)::Nothing
```

- Read or write the value of type `T` at byte offset `off` of `obj`, with the write barrier for a reference and Julia's alias metadata for a mutable field.
- The offset is not checked; the caller guarantees the field.
- The calling convention's field references (§6.5) use them.

**Status:** Planned (W-102).

### 10.4 The member hook

```c
void jl_set_member_hook(jl_value_t *hook);   // hook(T::Type, X::Type) -> nothing, or throws
```

- **The hook checks a member of a pattern** (a family, a closed abstract type, a set) that no declaration checked. Its key needs no hook (§6.1).
- **The runtime calls it at the member's first use,** where no answer is kept for (member type, set):
  - at dispatch, before the instance lookup, and at a split's table miss or `keep`;
  - in the compile queue, before a CodeInstance that relies on the member is published. A failing check compiles that use as the `ImplementError`.
- **Inference never calls it,** and no runtime lock is held while it runs. It runs in the latest world. A per-(member type, set) state marks a check in progress; a check that reaches its own member again raises.
- The runtime keeps the answer per (member type, set) on the member's `TypeName`, a failure included, and every later use reads it.
- **A package image keeps the answers** found while it was built, with the methods each check relied on, and drops an answer at load where those methods dispatch differently. Checks at a first use are for members no image checked.

**Status:** Planned (W-102); mine (2026-11-06). Checks only, and where it runs: mine (2026-11-06, the reviews of the draft).

---

## 11. Changes useful without traits

Each applies to all code.
- **An invoke keeps the exact specialization over a widened varargs tail,** where the compileable signature only widens a `Vararg` tail and the exact specialization has code.
- **An inference cycle's members inline each other:** when a cycle finishes, each optimized member is offered to the inliner of the members optimized after it.
- **The run-time `return_type` entry in the system image:** `_return_type(::PlainRTInterp, ::DataType)` is a compiler bootstrap entry.
- **Reflection in the compiler's world** with an explicit `NativeInterpreter`.
- **The dispatch profiler:** `JULIA_FACTS_DISPATCH_PROFILE=1` counts dynamic calls per callee method and per call site.

**Status:** Planned (W-100). Upstream proposals: [`../design/julia-changes.md`](../design/julia-changes.md).

---

## 12. Status index

| Interface | Status | Section |
|---|---|---|
| the facts inference, fact signatures, run-time sites, `return_type`, effects | Planned (W-100) | §1 |
| the policy per method; one CodeInstance per MethodInstance and policy; calls between policies | Planned (W-100) | §2 |
| the dependency record; G2 as a predicate | Planned (W-100) | §3.1, §3.2 |
| the code slot | Planned (W-101) | §3.3 |
| sets and their contracts, memberships, worlds, transitivity, subtyping in the walk | Planned (W-98); built in part | §4.1–§4.5 |
| one instance per member | Planned (W-98) | §4.6 |
| three layers; negatives never fold; positives through entries | Planned (W-98) | §4.7, §4.8 |
| intersections `All{X, Y, Z, …}` | Planned (W-98) | §4.9 |
| type values as members | Planned (W-98) | §4.10 |
| methods at sets in the table; specificity; match ranges | Planned (W-99); built in part | §5.1–§5.3 |
| the ambiguity report at a membership | Planned (W-99) | §5.4 |
| guards and cells | Planned (W-102) | §5.6 |
| `TraitKey`; compilation signatures per key, per type, once | Planned (W-102) | §6.1, §6.2 |
| the attribute bits at a call | Planned (W-102) | §6.3 |
| calls from code compiled per key | Planned (W-102) | §6.4 |
| the calling convention; the boxed adapter | Planned (W-102) | §6.5, §6.6 |
| the definition-time check and the classification | Planned (W-102) | §6.7 |
| a declared result on `Method`; the operation's flag | Planned (W-102) | §6.8 |
| casts at the call; `keep` | Planned (W-102) | §6.9 |
| operations on a value typed by its trait; the split; the table | Planned (W-102) | §7.1–§7.3 |
| `Callable`: dispatch by signature, its call, the result checked on return | Planned (W-102) | §7.4 |
| world-checked caches | Planned (W-102) | §8 |
| memberships in images; the record toward a machine-code cache | Planned (W-103) | §9 |
| hooks, the module-end hook included; field-offset intrinsics; the member hook | Planned (W-102, W-103) | §10 |
| changes useful without traits | Planned (W-100) | §11 |

---

## Deviations

Branch `unified` at c3f0b4bc11 (the stage-1 rework, W-98, is begun and uncommitted). IDs are shared with the record's other references and never reused.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-18 | [§5.5](#55-a-membership-lowers-dispatch-caches) | A membership lowers dispatch caches and invalidates no code; a guard covers a compiled call a later membership could change. | Until the guards exist, `jl_declare_membership` replays the method-insertion walk for every method at the set or a superset, as if the member's tuple had been inserted: compiled callers the membership could change are invalidated, and each declaration logs how many. | `src/datatype.c:288`, `src/gf.c:2105` |
| C-19 | [§4.10](#410-type-values) | A type value is a member only by an entry for `Type{S}`. | An entry for `S` also answers `S isa X` and `Type{S} <: X`, so a method at `X` is called with the type object `S`. | `src/subtype.c` (`jl_membership_holds`, `subtype`'s `Type{T}` arm, `jl_isa`); `experiments/unification/audit/probes.jl` P1 |
| C-20 | [§6.1](#61-the-key-as-a-type), [§6.9](#69-casts-and-keep), [traits §7.7](traits.md#77-dynamicx) | `Dynamic{X}` is an ordinary struct of `Core`, a member of `X` by a membership the library declares; the key's type is `Core.TraitKey`. | The branch defines `Core.Keyed`, `Core.Dynamic`, `Core.Compiled` and `Core.Kept`, the last three members of `X` by an erasure rule in subtyping that intersection and the method table's match do not follow: a call with a `Dynamic{X}` reaches the fallback, not the method at `X`. | `src/subtype.c` (`intersect`), `base/boot.jl`; probe P2 |
| C-21 | [§4.2](#42-memberships) | Any member pattern is a membership. | A pattern with more than eight type variables is accepted and never matches. | `src/subtype.c` (`jl_membership_env_match`); probe P3 |
| C-22 | [§4.4](#44-transitivity) | Membership is transitive; `<:`, `isa`, intersection and dispatch read one relation; the entries of a member's supertype chain are consulted. | `isa`, intersection and dispatch compose memberships through set-in-set entries; `<:` reads direct entries only; entries along the supertype chain are not consulted. | `src/subtype.c` (`jl_membership_answer_direct`); probes P4, P7 |
| C-23 | [§4.4](#44-transitivity) | A membership that would close a cycle among sets is refused. | A cycle closing through a set's second entry is accepted. | `src/datatype.c` (`jl_declare_membership`); probe P5 |
| C-24 | [§4.1](#41-sets) | The builtins' types are never members. | A builtin function's type is accepted as a member. | `src/jltypes.c` (the `never_member` bits); probe P6 |
| C-25 | [§4.3](#43-worlds) | The declaration is followed by `Expr(:latestworld)`; the runtime does not set a task's world. | `jl_declare_membership` sets the declaring task's world age to the entry's world. | `src/datatype.c` (`jl_declare_membership`) |
| C-26 | [§4.5](#45-subtyping) | A membership is a supertype inside subtyping's walk, so `X{<:T}`, `X{>:T}` and `where` variables see members. | The fallback asks the entries in a fresh query outside the walk: with `S`'s entry for `X{Int}`, `S <: X{<:Real}` and dispatch at `f(::X{<:Integer})` are false. | `src/subtype.c` (`jl_membership_holds`); probe P8 |
