# Optional extensions: the reference

**Adopted** with the plan's D-14 (2026-11-15; the user, by adopting [the plan](../plans/2026-11-15-next-iteration.md): "Have Opus agents implement the plan"). This page holds mechanisms of the design that are **Optional** ([the folder's README](README.md#conventions-for-every-reference)): built when a measurement or a later decision asks for them. User code may not rely on what they would give. No rule and no guarantee of the other four references depends on them.

- The language: [`traits.md`](traits.md). What compiled code may assume: [`facts.md`](facts.md). Julia's interfaces: [`compiler.md`](compiler.md). The library's macros: [`lowering.md`](lowering.md).
- Each extension says what it would add, what it rests on in the other references, and its status.

## Contents

1. [Keys: code shared among members the contract sees alike](#1-keys-code-shared-among-members-the-contract-sees-alike)
2. [Deviations](#2-deviations)

---

## 1. Keys: code shared among members the contract sees alike

**What it would add.** Members that the contract sees alike would run one compiled copy of a bounded method, where Julia compiles one per type. It is purely a performance optimization (the user, 2026-11-11: "Keys should be considered purely a performance optimization. They can stay deferred.").

**Status of the whole:** Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"). A use case to investigate, traits with operations only: [open issue 147](../open-issues.md#2-design). Four of 148 memberships in the ports share a key (E-263).

### 1.1 The key

- **The key of a member** is what the contract sees of its type:
  - the **receiver type**: the member when it serves at least one operation by its own methods, or when the trait's declarations name `Self` or a parameter that no field defines; the forwarding field's type when it forwards ([traits §5.5](traits.md#55-forwarding-with-by)); none when defaults serve every operation;
  - the declared fields' types;
  - the trait's parameter values.
- **Members with equal keys share compiled code.** Every type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for that key, including code in the library's package image. Fields the trait does not declare never cause a compile.
- **A member that serves an operation by its own method has its own key,** since it is its own receiver type.
- **A field or forwarding field of an abstract type** is part of the key as it is: one copy for it, whatever it holds; operations on that part dispatch when they run.
- **What is compiled per key:** a method bounded at the argument ([traits §7.3](traits.md#73-bounded-methods)), for a plain member or a wrapper. A box's code is compiled once per trait instance, as without keys. A method whose result is built by `like(t, …)` or `withfields(t; …)` is compiled per type at `t`: its result's type is `t`'s family.
- **With several trait arguments,** a method is compiled per tuple of keys; a vararg of members per tuple of keys.
- **At an argument typed by an intersection** `All{X, Y}`, the key is the member's key for each component; members with equal keys for every component share code.
- **A key prints as the key,** wherever a signature appears: `colmean(::ColTable at Vector{Vector{Float64}}, ::Int64)` in a stack trace, a `MethodError`, `code_typed` and the list of a method's compiled copies.
- **Compiling ahead** ([traits §16](traits.md#16-compiling-ahead-closed-programs)) asks for a member's methods at its key; a key that some member already has compiles nothing new.

**What it rests on:** the contract on the trait's `TypeName` ([compiler §4.1](compiler.md#41-sets)) and the receiver each membership records ([compiler §4.2](compiler.md#42-memberships)), both built.

**Status:** Optional. The compilation per key of a method whose result is built by `like`, per type: mine (2026-11-06). Keys' printing: mine (2026-11-06).

### 1.2 The key as a type

```julia
Core.TraitKey{X, R, F}
```

- `TraitKey{X, R, F}` names the members of `X` whose receiver type is `R` and whose declared fields' types are `F`, a tuple type (§1.1).
- **The runtime computes a member's key** from its membership and the set's contract, without running Julia code: the receiver the entry records (the member, its forwarding field's type, or none), the declared fields' types at the member (`fieldtype`), and the parameter values (the pattern's match). A member of a pattern has its key from the entry like any other. The answer is memoized per (member type, set) on the member's `TypeName`, with the membership's worlds.
- `S <: TraitKey{X, R, F}` holds when `S`'s key for `X`, computed in the world asked about, is that key. It is a case of `subtype`, as `Type{T}` is, and likewise of `intersect`, `type_morespecific_`, `obviously_disjoint`, `jl_isa_compileable_sig` and `jl_compilation_sig`.
- **At an intersection** `All{X, Y}`, the key is the tuple of the member's keys for each component.
- `has_open_set(t)` ([compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)) is true for a key, as for an open set.
- A member's key needs no member hook ([compiler §10.4](compiler.md#104-the-member-hook)).
- It is never written by a user. It prints as the key: `ColTable at Vector{Vector{Float64}}`, in `show`, `show_tuple_as_call`, `MethodError` and reflection.
- **The compilation signature per key:** `TraitKey{X, R, F}` at an argument where the method is bounded, inferred once per key by the path `@nospecializeinfer` takes. Keyed instances are cached with their original tuple (`cache_with_orig`), so a concrete tuple maps to its keyed instance. Static parameters bound by a keyed argument are those the key fixes; a method whose body uses a static parameter the key does not fix is compiled per type there.

**Status:** Optional. The name `TraitKey`, beside BaseTraits' trait `Keyed`, is mine (2026-11-06). Keys computed by the runtime from memberships: mine (2026-11-06, [the work plan's review](../../attic/writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md) §6, weak point 4).

### 1.3 Calls from code compiled per key

- Code compiled per key holds the argument at the type `TraitKey{X, R, F}`. Operations and declared fields act on its parts (§1.4), whose types are concrete: each call there is at a fact.
- **Passing the argument on to another function `g`:**
  - **static** where the method of `g` selected at the key is the one selected for every member with that key in the current world. A later membership with that key invalidates the code when some method of `g` is more specific for the new member (found through the set-to-methods index, as the membership's walk finds it, [compiler §5.5](compiler.md#55-a-membership-invalidates-as-a-method-does)). A later method of `g` invalidates the caller through its dispatch edge at the key, as any insertion does;
  - **otherwise a run-time site,** dispatched on the object; the instance then receives the object (§1.4).
- Swift and Rust resolve such a call where the generic code is written, at the constraint. Julia dispatches it on the value's type, and G1 asks for Julia's answer. So that invalidation is what keeps the shared code equal to that answer, by the same mechanism as any membership's.
- **Two more fact signatures** ([facts §3](facts.md#3-fact-signatures)):

  | Form | Example | Why only a stakeholder or a pirate can change it |
  |---|---|---|
  | **A key, at the parts of a keyed argument** | in code compiled per key, `area(receiver)` with the receiver's concrete type | The parts' types are concrete: a dispatch tuple. |
  | **A keyed argument passed on,** where one method is selected for every member with that key | `g(t)` with `t` keyed for `ColTable` | A method of `g` defined later invalidates through the edge at the key; so does a later member with that key that another method of `g` would take. |

**Status:** Optional; mine (2026-11-06).

### 1.4 The calling convention

A static caller passes a keyed argument as its parts:
- the receiver, by its own convention;
- each declared field that is `@const`, or of an immutable member, by value;
- each writable declared field as a field reference: the object and an offset, so a write reaches the caller's object (§1.6);
- the object itself, boxed, where the method may keep the value, return it, or pass it to a run-time site. An escape pass of inference decides this per instance.

**The parts in a default's method.** A default's method at the trait ([traits §4.2](traits.md#42-defaults)) reaches the receiver and the declared fields through two intrinsics:

```julia
Core.trait_receiver(t, X)          # the receiver: t itself, or its forwarding field
Core.trait_field(t, X, name)       # a declared field
```

At a key, inference resolves them to the parts above. At a member, it resolves them to `t` or to the forwarding field's `getfield`. So members that share a key and forward through fields of different names share the code. Without keys, the library's own forwarding call serves ([lowering §2](lowering.md#2-trait)).

**Status:** Optional.

### 1.5 The boxed adapter

A dynamic call to a keyed instance goes through one adapter per keyed CodeInstance. The adapter reads the receiver's and the fields' offsets from a table per (member typename, set) on the member's `TypeName`. If it costs more than the target ([the evidence](../design/evidence.md) §2), there is one adapter per member instead; W-110 measures.

**Status:** Optional.

### 1.6 Field-offset intrinsics

```julia
Core.Intrinsics.getfield_at_offset(obj, T::Type, off::Int)::T
Core.Intrinsics.setfield_at_offset(obj, T::Type, off::Int, x)::Nothing
```

- Read or write the value of type `T` at byte offset `off` of `obj`, with the write barrier for a reference and Julia's alias metadata for a mutable field.
- The offset is not checked; the caller guarantees the field.
- The calling convention's field references (§1.4) use them.

**Status:** Optional.

---

## 2. Deviations

None: nothing on this page is built, and an Optional mechanism not built is no deviation. The library's forwarding call in place of `Core.trait_receiver` is lowering's own rule ([lowering §2](lowering.md#2-trait)).
