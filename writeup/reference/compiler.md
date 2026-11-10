# Compiler and runtime: the reference

**Adopted** (the user, 2026-11-06; W-105; [the folder's README](README.md)). This page defines what Julia's compiler and runtime provide to the design: each interface, what it means, and its rules. It describes the interfaces as designed. The status line of each section says how far it is built.

- Why each interface is needed, and what compiled code may assume: [`facts.md`](facts.md).
- How the language uses them: [`traits.md`](traits.md) for what a user sees, [`lowering.md`](lowering.md) for what the library's macros emit.
- The build is branch `unified` of the julia repository, on v1.13.2 (the worktree `julia-unified/`), in the stages W-98 to W-114 ([the work plan](../plans/2026-11-06-work-plan-under-the-draft-reference.md), adopted) and the work items after them, W-101, W-123, W-128 and W-129 ([the work queue](../record/todo.md)). The inventory of its changes: [`../design/julia-changes.md`](../design/julia-changes.md).
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
| [4. Sets and memberships](#4-sets-and-memberships) | Open abstract types, memberships with worlds, transitive subtyping, intersections, sets closed after load |
| [5. Dispatch](#5-dispatch) | Methods at sets in the method table, specificity, the ambiguity report, guards |
| [6. Keys and the attribute](#6-keys-and-the-attribute) | Code per key, per type or once, chosen per call; the calling convention; the definition-time check |
| [7. Operations on a value typed by its trait](#7-operations-on-a-value-typed-by-its-trait) | Declared results, the split over members, the table of targets, `Callable`'s call, `IO`'s contract |
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

**Status:** The interpreter's mode implemented on `unified` 28fe27b2f7 (W-100); an inference of a method instance for its code run under its method's policy, both policies under Julia's own owner, 10c7e1c2cf.

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

**Status:** Implemented on `unified` 28fe27b2f7 (W-100), from `trait-world-1.13`'s `facts.jl`.

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

**Status:** Implemented on `unified` 28fe27b2f7 (W-100); the split's fallback (§7.2) marks one under the facts mode with W-100's policy.

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

**Status:** Implemented on `unified` b87d863b9e (W-100) for steps 1 and 3 and the run-time answer (`PlainRTInterp` is `NativeInterpreter(; plainrt = true)`, owner `:plain_rt`); step 2: C-47. Optional: revalidating cached answers after loads ([PE-5](../record/performance-explorations.md)).

### 1.5 Effects

Under the facts mode no asserted effect applies over a run-time site, at any depth: a method's `@assume_effects` is ignored where its frame's `nortsite` is clear, and a statement's where its call's is ([facts §8](facts.md#8-asserted-effects)).

**Status:** Implemented on `unified` 28fe27b2f7 (W-100).

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

**Status:** The module option implemented on `unified` beafa01b36 (W-100): `facts` and the four trait options, set by `Base.Experimental.@compiler_options`, inherited by submodules, saved with the module; their consumers: §2.3 (W-100) and W-109, W-111, W-114.

### 2.2 The method flag

```julia
Expr(:meta, :facts_boundary)   # compiled in the policy of the code that reaches it
Expr(:meta, :facts_always)     # always compiled by facts
```

- `Method.facts::UInt8`: 0 as its module says; 1 a boundary; 2 always facts. Lowering carries the meta into every method a definition makes (keyword sorters, positional forwarders). It is saved with the method.
- **The boundary flag is the second policy per method.** A neutral method has plain code only (§2.3), so facts code that calls it rests on code that loads may invalidate. A boundary gives facts code a facts copy that no load discards, for the methods where that matters. Which of Base's methods carry it is a choice of the setting, made by measurement ([evidence](../design/evidence.md)), not a rule of the design.

**Status:** The method flag implemented on `unified` beafa01b36 (W-100), carried into every method a definition makes cb7f55bd35 (gate `f2_policy_flags`). The boundary flag as the second policy per method: implemented on `unified` c44a447f2c (W-100; §2.3); gate `f6_reach_policy`. Which of Base's methods carry it: none, in the product setting (mine, 2026-11-07): facts code rests on plain code of Base whose own records satisfy G2 (E-279, [evidence](../design/evidence.md#4c-the-unifications-trade-offs-measured-on-todays-build)).

### 2.3 One CodeInstance per MethodInstance and policy

- **The policy of a method's code:**

  | Method | Policy |
  |---|---|
  | in a module of flag 2 (the compiler), whatever its own flag ([facts §6.4](facts.md#64-the-compilers-own-code)) | plain |
  | always facts, or in a module of flag 1 | facts |
  | a boundary | the policy of the code that reaches it |
  | any other (a *neutral* method) | plain in the product setting; under the test bed, the policy of the code that reaches it (§2.5) |

- **What reaches code:**
  - compiled code and the interpreter reach with the policy of the code they run;
  - the runtime's own entries reach with the setting's default: plain in the product setting, facts under the test bed. They are the C API (`jl_call`, `jl_apply` from C), task entry, finalizers, `@cfunction` pointers, a module's `__init__`, staging a generated function, and a compile request (`precompile`, the compile queues).
  - A top-level thunk's policy is its module's: facts for flag 1, plain for flag 2, the setting's default otherwise.
- **A CodeInstance records its policy** in its flags. A lookup asks for the policy the code is wanted in; a CodeInstance of the other policy never stands in.
- **Code inferred anew by a queue that compiles** (the JIT's, an image's native compile) is inferred under its own policy: a MethodInstance under its method's, as the queue reaches it; a CodeInstance whose source is gone or that is no longer valid, under the policy it records. Never under the policy of the interpreter that runs the queue.
- So a neutral method in the product setting has plain code only, whoever calls it. A method that takes the policy of the code reaching it has up to one CodeInstance per policy.
- Under `--trim` every method is plain (§2.6).

**Status:** Implemented on `unified` 10c7e1c2cf and c44a447f2c (W-100): the policy bit in a CodeInstance's flags, set from the policy it is compiled in and kept in images; the lookups of Julia's own owner take only a CodeInstance of the policy wanted; the policy of the code that reaches a method, through inference and the engine's reservations; gate `f6_reach_policy`. Code inferred anew by the image's queue and the JIT's under its own policy: `unified` dde5f9f5dc, gate `n15_image_policy`. With C-49. Under `--trim`: Planned.

### 2.4 Calls between policies

- **In inference,** a callee whose policy differs from the caller's is inferred under its own policy, in an inference of its own. The caller records:
  - a **result edge** where it emits the call and uses its result type, exception type, effects or a constant result as a type;
  - a **code edge** where it inlines the callee, propagates constants into it or evaluates it at compile time.
- **Constant propagation from plain code into a facts callee** infers the callee again for the constants under the facts policy, in a call stack of its own; the result is the caller's, the edges that inference's.
- **Concrete and semi-concrete evaluation** of a facts callee from plain code use its effects as facts inferred them, with a code edge to its CodeInstance; not over a run-time site.
- A facts caller of the compiler's own plain code propagates no constants into it.
- **A callee that takes the policy of the code reaching it** is inferred under the caller's policy, in the caller's inference.
- **At run time,** every dispatch runs the selected method's code of its policy (§2.3), for the policy of the code that dispatches:
  - **from compiled code:** generic calls, `invoke`, and the builtins that call a function: `_apply_iterate`, `invokelatest`, `invoke_in_world`, `_call_in_world_total`, `Core.invoke`, and the operation of `modifyfield!`, `modifyglobal!` and `memoryrefmodify!`. Compiled code of each policy calls an entry of its own, and the builtin passes the policy on to every dispatch it makes;
  - **from the interpreter:** the policy of the code it runs;
  - **from the runtime's own entries** (§2.3): the setting's default.

**Status:** Implemented on `unified` 10c7e1c2cf (W-100) for inference: a callee of the other policy is inferred in an inference of its own and the caller rests on its CodeInstance. At run time, on c44a447f2c: entries of compiled code of each policy, the builtins' variants, the interpreter's policy, the runtime's entries with the setting's default; gate `f6_reach_policy`. With C-45 and C-50.

### 2.5 The test bed

- With `JULIA_COMPILE_BY_FACTS=1` (Planned spelling: `--compile-by-facts=all`), every neutral method takes the policy of the code that reaches it, and the runtime's own entries reach with facts: *the test bed* `all`.
- So every method that user code reaches is compiled by facts. The compiler stays plain, and so do the neutral methods it reaches; their plain code in the system image serves it.
- An image records the policy of each CodeInstance, so it is correct under either setting. The other setting finds no code of its policy and compiles it. The test bed keeps a depot of its own, for speed.

**Status:** Implemented on `unified` 4ba5b7025f and c44a447f2c (W-100): a session under it starts and runs, and its user code is compiled by facts (E-275; gate `f6_reach_policy`). A session's start-up compiles Base's start-up code by facts, 24–25 s ([PE-23](../record/performance-explorations.md)). The spelling `--compile-by-facts=all`: Planned.

### 2.6 `--trim`

A trimmed build has no facts policy: every method is inferred plainly, and the image writes no facts flags. A binary is a closed world ([facts §13.3](facts.md#133-trimmed-binaries)).

**Status:** Implemented on `unified` cb7f55bd35 (W-100): under `--trim` every method and top-level thunk is plain, so every CodeInstance is; not run here, since no trimmed binary is built in this workspace. With C-53.

### 2.7 Fully typed mode

```julia
Expr(:meta, :fully_typed_warn)       # a method: warn
Expr(:meta, :fully_typed_enforce)    # a method: raise
Base.Experimental.@compiler_options fully_typed=enforce   # every method of the module: off, warn, enforce
```

- **Fully typed mode** ([traits §14](traits.md#14-concreteness-and-fully-typed-mode)) is a method's flag (`Method.facts` bits 4 and 8), or its module's option (trait-option bits 16 and 32), inherited and saved as the others are. The method's own flag wins.
- **A method in the mode is compiled by facts** (§2.3): the mode is about the facts the code rests on.
- **The fault of its code at a signature,** known when inference finishes:
  - a run-time site, in it or in a callee compiled by facts (`nortsite` cleared, §1.3);
  - else a result of an abstract type that is neither a union of at most four concrete types, a type's type, nor a set or an intersection of sets.
- **Code with a fault starts with a check:** `jl_not_fully_typed(svec(mi, level, warned, kind, rt))`, a call into the runtime that reaches the library's hook (`jl_set_fully_typed_hook`) in the latest world. Under warn it runs the hook once per check; under enforce at every run, and the hook raises. Without a hook, enforce raises Julia's error.
- **The check is never folded or removed:** the code's effects are neither consistent, nor effect-free, nor nothrow.
- **Fully typed code has no check** and pays nothing.

**Status:** Implemented on `unified` 5f2373b2d5 (W-114): the flag and the option, the policy, the check after optimization, the hook; gate `n9_fully_typed`. The library's report and errors: [lowering §14](lowering.md#14-fully-typed-mode-concrete-parts-closed-programs). Where the mode lives (the compiler finds the fault, the library explains it): mine (2026-11-07).

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

- **A positive membership is recorded as its entry.** Where inference folds a positive answer through an entry (§4.8), or a dispatch match passes through one (§5.3), the entries the answer rests on join the record: each entry in force in the world being inferred on a `TypeName` reachable from the member (its supertypes, parameters and entries' instances) whose set reaches a set the question names. A chain of memberships records each link.
- The code's worlds start no earlier than the latest of those entries'. An entry in the record takes no backedge: memberships only grow, and a redeclared one keeps its answer (§4.3).
- Validation of a loaded image's record takes an entry's worlds where the entry is in force in the session, and refuses the code where it is not (§9).
- **A dispatch edge keeps the call's signature where the call reached an instance wider than its own match:** a method compiled once at a set (§6.3) or declared `@nospecialize`. The edge names the call's signature with the instance, and so does its backedge. A method defined later invalidates the caller only where it replaces the matched method over the part of the call's signature it meets. So a caller at `Int` of `k(@nospecialize(x))`, which reaches the instance `k(::Any)`, stays valid when a method `k(::String)` is defined. The callee's own invalidation reaches the caller as through any backedge.

**Status:** On `unified` 9a601902a0 (W-100): dispatch and binding edges as Julia records them; positive memberships, the entry itself, recorded at `isa`, `<:` and dispatch matches, the code's worlds from theirs, read by image validation (E-277; gate `f7_membership_edges`), with C-51. Membership cells with the guards (W-112); result edges apart, as the list the code slot reads (W-101, §3.3); code edges' digests and layout identities: C-52. A dispatch edge with the call's signature where the instance is wider: `unified` 53ec4356bf (E-336; gate `n21_callsig_backedge`), mine (2026-11-09).

### 3.2 G2 as a predicate

When a CodeInstance of either policy is finished, a bit in its flags records whether its record satisfies G2:
- every dispatch edge is at a fact signature;
- every inlined callee's own record satisfies G2;
- result edges may go anywhere.

Strict mode, the concreteness checks and the image's rule for what it keeps (§9) read it.

**Status:** The bit implemented on `unified` 8ef154476f (W-100), for code of either policy and kept in images, inlined callees' records consulted on 1d493ca959, the edge instance made for a constant-propagated result on 427760d9e9 (gate `f4_g2_bit`, E-320); its readers: strict mode and the concreteness checks (W-114), the image's keep rule (§9, W-100). Computed for plain code too: adopted with the work plan (the user, 2026-11-06), the trade-offs review's M1.

### 3.3 The code slot

- **A static call that holds only a result edge to its callee** loads its target through a slot. Every other call binds the callee's address.
  - The record lists these callees with the CodeInstance (§3.1).
  - A callee qualifies when every call of it in the code is emitted as an `:invoke` typed by its result, and no statement inlines it, evaluates it concretely or propagates constants into it.
  - The callee's CodeInstance is Julia's own and in its MethodInstance's cache.
- **The slot is the call site's.**
  - It holds the CodeInstance the site last called.
  - A call checks the task's world against that CodeInstance's world range, and calls its entry.
  - On a miss, the runtime finds the callee's code valid in that world, with the result the caller was compiled against, compiling it where needed. It puts that code in the slot.
  - **Where no such code can be made,** it puts an entry with the call's signature that dispatches the call when it runs, in the task's world, and asserts the caller's result type. A boxed call runs the method's code in the interpreter. The entry is valid in every world.
  - Nothing else writes a slot. An image's slots start empty.
- **When a callee is invalidated through its own edges,** a caller whose only edge to it is a result edge is marked for revalidation, not invalidated.
  - A callee replaced by a definition at its signature invalidates its callers.
  - A marked CodeInstance's world range is lowered as an invalidation lowers it, so every cache that checks worlds misses it.
  - The walk goes on from a marked caller as from an invalidated one.
  - A later invalidation of a marked CodeInstance makes the mark final.
- **Its next lookup in the latest world revalidates it.** The lookups are dispatch, `invoke`, a `cfunction`, a slot's miss, and inference's cache miss. Each edge to a callee not valid there is checked:
  - A marked callee is revalidated first.
  - For a result edge, the callee is inferred again, and its result is compared with the one the caller used: return type, exception type, constant and effects.
  - Equal, and valid from the world of the mark on: the caller is valid again, and the edge names the callee's new CodeInstance.
  - Otherwise the mark is final, and the caller is inferred again.
- So G2 covers a facts caller of a plain callee whose result its recompilation leaves unchanged ([facts §2.2](facts.md#22-g2-stable-caches)).
- `JULIA_CODE_SLOT=0` records no result edges: the code it compiles binds every call, and the walk marks nothing. The system image keeps the slots it was built with.

**Status:** Implemented on `unified` 7500630036 (W-101): the record's `ResultEdges` (`Compiler/src/typeinfer.jl`), the slot in codegen (`emit_code_slot`), the marks and revalidation (`src/gf.c`). Gate `experiments/unification/stack/slot_cascade.jl`: a plain caller, a facts caller and an image's caller kept through a callee's recompilation; compiled again when the result changes; the old world sees the old code. A call through a slot costs 0.08 ns more where calls are independent of each other, nothing measurable where each waits for the last (E-283). The entry where no code can be made on `unified` 49ab4294b6 (`code_slot_fallback`; the gate's case "the last resort", through a test switch). With C-64 to C-67 and C-69.

---

## 4. Sets and memberships

### 4.1 Sets

- **A set** is an abstract type whose `TypeName` has the `open` bit. A trait's declaration sets it; a set is open from its declaration.
- Every other abstract type is closed, Base's and Core's included.
- **`never_member`:** a bit on Core's kinds (`DataType`, `UnionAll`, `Union`, `TypeVar`, `Module`), the builtins' types, opaque closures and the memory types. A membership of one is refused.
- A set's declared supertype is `Any` or a set. A closed abstract type is never a member of a closed abstract type through a set.
- **A set's `TypeName` carries its contract,** written once by the library at the declaration and saved with it in images ([lowering §2](lowering.md#2-trait)). The same slot holds a closed abstract type's contract, the list of its operations' methods that `jl_declare_contract` writes (§7.1). A set's contract holds:
  - the operations, each with the trait's method that carries its declared result (§6.8);
  - the declared fields, with their types and whether read-only;
  - each parameter's definition;
  - the default attribute bit (§6.3).

  The compiler reads it without an edge: it never changes after the declaration.

**Status:** Implemented on `unified` 62016706d0: the `open` bit, `never_member` (the builtins' types included), a set's supertype, the contract's slot. The contract itself is written by the library (W-106). The contract on the `TypeName`: mine (2026-11-06).

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

**Status:** Implemented on `unified` 62016706d0, but for a pattern variable bounded by a `Union`, which the library declares per type (W-106).

### 4.3 Worlds

- A membership is declared as a method is inserted: under the world counter's lock, the entry gets `min_world = counter + 1`, is published, and the counter advances.
- **Strict mode's check** runs between the entry's publication and the advance: the ambiguity report (§5.4) is asked for its findings in the entry's world. Under the lock nothing else can enter that world, so it is asked before the counter reaches it. On a finding the entry is **retired before it begins** (`max_world = counter`): live in no world, never removed from its lists, which readers walk without a lock. A redeclaration's old entries are in force again, the counter does not advance, and the declaration throws. The set's candidates and the image's list of memberships take the entry only once the check passes.
- A type whose only entry is retired keeps a non-empty list: the presence tests that read the list's length stay conservative.
- The library's declaration is followed by `Expr(:latestworld)`, so the declaring code sees its own membership.
- A task in an older world does not see it.
- **Memberships only grow.** A redeclared membership gives the old entry a `max_world`, declares a new one, and invalidates the code compiled at the old key and the callers that folded against it.
- **`Callable`'s memberships** follow its members' methods (§7.4): a method definition can begin or end one. They are the one kind that can end.

**Status:** Implemented on `unified` 62016706d0; strict mode's check and the retired entry on `unified` 0bb8f38830 (E-343).

### 4.4 Transitivity

- `A <: B` and `B <: C` give `A <: C`, whichever link is a declared supertype, a membership, or a set's membership in a set.
- **`<:`, `isa`, intersection and dispatch read the same relation,** so `isa(x, T)` and `typeof(x) <: T` agree.
- The entries of every type on a member's supertype chain are consulted.
- A composed membership holds from the latest `min_world` of its links; with several chains, from the earliest of those.
- A membership that would close a cycle among sets is refused, by a check over every path.

**Status:** Implemented on `unified` 62016706d0.

### 4.5 Subtyping

- **A membership is one more supertype of its member, inside subtyping's walk.** Where `S`'s supertype chain does not meet an open `X`, `jl_subtype` takes the entries of `S` and of each type on its chain. For each entry, it continues the same walk from the entry's instance, in the same environment, as it continues from a declared supertype. The pattern's variables join the walk as existential variables. The choice among a type's entries is made as a union's is.
- So set-in-set entries are followed transitively, and a miss is `false`.
- **Parameters are invariant.** With `S`'s entry for `X{Int}`: `S <: X{Int}`, `S <: X{<:Real}` and `S <: X{>:Int}` hold; `S <: X{Real}` does not.
- **A method's `where` variables and `X{<:T}`'s existential variables** are the walk's own. So dispatch at `f(::X{<:T})` and `f(::X{T}) where {T}` sees members as `<:` does.
- **Only entries whose set reaches the queried set are choices.** Reachability between two `TypeName`s is memoized per world range. So a type with many entries on its chain (BaseTraits' families on `AbstractVector`) costs a walk only for the entries that can lead to the set asked about.

**Status:** Implemented on `unified` 62016706d0.

### 4.6 One instance per member

A membership that would give a member a second instance of a set, differing in a parameter that is not an input, is refused at `jl_declare_membership`. The runtime checks it: exactly for a concrete member; for a pattern, by intersecting it with each pattern that already reaches the set. The library reports the refusal as `ImplementError`.
- **The runtime knows a set's inputs:** the library writes them once at the declaration, before the set has a member (`jl_set_input_params(X, mask)`, a bit for each of the first eight parameters, on the set's `TypeName`; images keep it).
- The check asks the member against the set at the new instance's input values, its other parameters free. A redeclaration ends only the entry at the same input values.

**Status:** Implemented on `unified` 62016706d0 for a concrete member, a set's inputs on `unified` 350c5b1c59 (gate `n10_inputs`), an image's membership at activation on 07c0bee2a2 (gate `n12_image_instances`); a pattern, against the entries at the set and at the sets that join it, on edc2653e43 (gate `n10_inputs`, E-321).

### 4.7 Three layers

Questions about open sets are answered in three layers:
- **`<:` and `isa`** read the entries: the answer in the current world.
- **`jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint` and the type cache** stay exact in the current world: a known member keeps the exact result; a concrete non-member gives `Union{}`; an abstract type that no entry relates to the set meets it as their intersection `All{X, T}` (§4.9): the members of `X` below `T`, whenever they are declared. Dispatch's match construction and the inliner's union split see only members. A concrete type no entry of whose chain can reach the set is obviously disjoint from it, by the reachability of §4.5.
- **`jl_could_join(S, X)`** answers whether `S` could become a member of `X`. Inference's lattice and the guards' shadow query (§5.6) use it; dispatch's match construction does not.

**Status:** Implemented on `unified` 62016706d0; a concrete non-member's disjointness by reachability 88daaca7fe; the meet of a set and an abstract type as `All{X, T}` 8a9144928e (W-107; mine, 2026-11-07).

### 4.8 Negatives never fold; positives through entries

- **A negative answer is never folded for an open set.** `has_open_set(t)` is true when `t`, a parameter of `t`, a component of a union or intersection in `t` is an open set or a key (§6.1); it is cached on the type object.
- `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the `hasintersect` sites and `Conditional` refinement consult it before folding a negative.
- **Exceptions** (the answer is final): a closed abstract type; a type with the `never_member` bit; a pair (type, set) whose set is closed after load and whose declarers have finished loading.
- **A positive answer folds only through an entry,** and the fold raises the CodeInstance's `min_world` to the entry's. So a task in an older world never runs code that assumed the membership.
- **Closed after load** ([traits §3.4](traits.md#34-open-and-closed)) is a bit on the set's `TypeName`, written by the library at the declaration (`@closed_after_load`).
  - **The declarers of a pair** are the set's owner and the type's owner, with their joint owners ([traits §12.1](traits.md#121-who-may-declare-a-membership)). A module is loaded once its package has finished loading, after its `__init__`. `Main`, and a package while it is precompiled or loaded, are not. Core and Base are loaded once Base's build has run its last definition, so the code the system image compiles after that relies on their final negatives (no `__init__` runs while an image is generated).
  - **Where both declarers have loaded,** the pair's negative is final: inference folds it, and a call whose shadow is a method at that set carries no guard (§5.6).
  - **Code that relied on a final negative records it** as an edge on the pair's cell. A membership declared later invalidates that code, as a method definition invalidates its callers. An image's code with such an edge is checked when the image is validated.
- **An intersection no type is in is final at a set closed after load.** For an abstract type `S` that is not a set and a set `X` closed after load, the pair (`S`, `X`) is final where `X`'s declarers and `S`'s module have loaded and `All{S, X}` is unmet in the world (§5.4). Its cell holds once a type under `S` is a member of `X`, so such a membership invalidates the code that relied on it.
  - Inference folds `isa` of a value of `X` against `S` to `false`.
  - Dispatch's lookup drops a method match whose argument is met only at that intersection, even one more specific than every covering match, and reports the pair's cell, which inference records as an edge (§5.4). So no instance is compiled at `All{S, X}`: with `ColTable` closed after load, a call `describe(t)` at `t::ColTable` matches `describe(::ColTable)` alone, not `describe(::AbstractString)`.
  - Code compiled while Base is built, before Core and Base count as loaded, at such an intersection is invalidated, with its callers, once they count as loaded, in a new world; the image's later code drops the match.

**Status:** Implemented on `unified` 62016706d0 for the negative folds; the positive fold through an entry, with its world and its record (§3.1), on `unified` 9a601902a0 (W-100), with C-51. Closed after load: Implemented on `unified` bf447db25e (W-129 (a)), with C-76, C-77; gate `n18_closed_after_load`, E-329. Core and Base loaded at the end of Base's build: `unified` b133374e9d (W-129 (b)), mine (2026-11-09). Opt-in: the user (2026-11-09, "Finality should be opt in."); the bit per set and the edge on the cell: mine (2026-11-09). An intersection no type is in, final at a set closed after load: Implemented on `unified` 1906196731 (E-334, open issue 169 (a); gate `n20_unmet_lookup` (4)), with C-79; mine (2026-11-09).

### 4.9 Intersections

```julia
Core.All{X, Y}
```

- **`All{X, Y, …}` is an intersection type,** the dual of `Union`:
  - `S <: All{X, Y}` when `S <: X` and `S <: Y`;
  - `All{X, Y} <: Z` when some component is a subtype of `Z`, and `<: All{Z, W}` when it is a subtype of each.
- **Normal form:** components flattened, sorted by the order `Union` uses, deduplicated; a component that is a subtype of another by declared supertypes absorbs it; two closed types with no common subtype give `Union{}`.
- **Normal forms read declared supertypes only.** A membership never absorbs a component of an `All` or a `Union`: `Union{S, X}` stays as written where `S` is a member of `X` by an entry. So a type expression gives the same type object in every world.
- `jl_type_intersection` of two sets, or of a set and an abstract type, that no entry relates is `All{X, T}`, with their known common members' exactness kept (§4.7). A type meets an intersection as the intersection of its meets with each component.
- `type_morespecific_` ranks `All{X, Y}` above each component, and an intersection with a closed component as a closed type against an open set (§5.2).
- **At an argument typed by an intersection,** the key is the tuple of the member's keys for each component (§6.1); the split's candidates are the first component's that are members of every component (§7.2).
- The negative-fold rule (§4.8) treats each component.
- It takes any number of components: `All{X, Y, Z, …}`.
- **The encoding.** `All{X, Y}` is the abstract type `Core.All{Tuple{X, Y}}`, built in its normal form; `Core.All{Tuple{X, Y}}` written so is the same type. The wrapper `Core.All` is an artefact of the encoding, not a type to write. No code reads an intersection's name, supertype or parameter as those of an ordinary type: every site that does (the typemap's names, the fold gates, type instantiation, the variable-occurrence walks) has a branch for it.
- **In the normal form, further:** a variable as a component is in a covariant position, and the diagonal rule applies to it; a `Union` component distributes (`All{Union{A, B}, Y}` is `Union{All{A, Y}, All{B, Y}}`); a component that is itself an intersection under a `UnionAll` is flattened; two closed components whose intersection Julia computes exactly are replaced by it.
- **Its name** is not exported by `Core` ([open issue 148](../open-issues.md#2-design)).

**Status:** Implemented on `unified` 8a9144928e (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}"), but for the key at an intersection (W-110) and the split's candidates (W-109). The encoding and the further rules: mine (2026-11-07, after [the review of the encoding](../reviews/2026-11-07-all-representation.md)). Normal forms by declared supertypes, keys and candidates at an intersection: mine (2026-11-06, the reviews of the draft).

### 4.10 Type values

A type value is a member of a set only by an entry whose pattern is `Type{S}`. Such an entry is kept on `S`'s `TypeName`, marked as being for the type value, not on `Type`'s. `jl_isa`'s branch for a type value and `intersect` consult such entries. An entry for `S` answers `S <: X`, never `S isa X`.
- A kind of type object (`DataType`, `UnionAll`, `Union`) meets a set that takes a type value, by its own entry or by one of a set that joins it. So a call at an argument typed by a kind finds the set's method. Before the set takes a type value, such a call is guarded ([§5.6](#56-guards-and-cells)): the kind's cell holds once the set takes one.

**Status:** Implemented on `unified` 62016706d0; the kinds on f14be868df, 0c9e44cb3d (gate `m1_typevalue_isa`, E-321).

### 4.11 Inference's world

Membership queries during inference run at the world being inferred for, not at the world the compiler runs in.
- That world is the task's **query world.** Inference, method matching (`ml_matches`, with the world it is given) and a declaration's walk set it for the length of their query.
- It is restored as the task's world age is, by an exception handler too. Another task never sees it.
- Elsewhere a membership question is asked in the task's world age.

**Status:** Implemented on `unified` 48864e547d.

---

## 5. Dispatch

A method whose signature names a set is a plain method at that set. Memberships and dispatch follow these rules:
- **Memberships only grow.** Positive answers fold; negative ones never, for an open set (§4.8).
- **Memberships invalidate no code.** A call that a later membership could change carries a guard (§5.6).
- **Methods invalidate as in Julia,** under ownership ([facts §2.2](facts.md#22-g2-stable-caches)).

### 5.1 The method table

A method whose signature names an open set goes into the linear list of the typemap's level at the set's position, never under a typename's index there. A query at a member reaches it, since the member's supertype chain need not name the set. At the other positions the method is indexed as any other: `ncols(t::ColTable)` is filed under `typeof(ncols)`, then listed one level down. A set-to-methods index serves the ambiguity report (§5.4) and compiling ahead (§9).

**Status:** Implemented on `unified` 29035cab11; `jl_open_set_methods_of(X)` reads the index for compiling ahead (5f2373b2d5, W-114; [lowering §12](lowering.md#12-compiling-ahead)). A membership ends only the fast path that a method at the set is the only one at its signature: the method stays the one `which` selects there, so validation does not read it as deleted and an image keeps its code (e81cd49a67). Listed at the set's position, indexed at the others: `unified` 45fa624462 (E-335), mine (2026-11-09).

### 5.2 Specificity

In `type_morespecific_`, at each argument:
- a closed type other than `Any` is more specific than an open set;
- between open sets, by subtyping: a set whose membership in another makes it a subtype is more specific; else unordered;
- an intersection is more specific than each component; one with a closed component counts as closed against an open set.

So `Method.interferences`, `detect_ambiguities` and the insertion walk order these pairs as any others. Inserting `f(::X)` reaches only the specializations of `f(::Any)` and the "no method" facts. The `obviously_disjoint` short-circuit is bypassed where either side has an open set.

- **A later membership can make two methods meet, or order two sets.** `Method.interferences` is recorded when a method is inserted; a method at a set and one at a type that later joins it were disjoint then. Method matching therefore asks a pair in which either signature names an open set with the methods' specificity, in the query's world (§4.11), and reads the record only for a pair of closed signatures.

**Status:** Implemented on `unified` 62016706d0; intersections and a pair at two sets asked again 8a9144928e (W-107); a pair with one method at a set 0ce5b7f752 (W-114, found by BaseTraits: a `KeySet` and a `BitMatrix` read as ambiguous). Mine (2026-11-07).

### 5.3 Match world ranges and abstract queries

- A match through an entry carries the entry's `min_world` into its valid worlds, at fixed, vararg and union argument positions.
- **At an abstract query,** a method at a set matches at their intersection `All{X, T}` (§4.7). A closed method that covers the query is more specific (§5.2), so the method at the set is dropped from the matches, as any method a covering more specific one hides.
- At a query at a set, a method at an abstract type matches likewise.
- A concrete query that is not a member meets no method at the set.
- **A match through `Callable`** (at a method whose signature names it) carries the worlds of the member's call methods, at the argument positions where the signature names `Callable` (§7.4): a method's definition or deletion changes no other match's worlds.

**Status:** Implemented on `unified` 29035cab11; the matches at an abstract query 8a9144928e (W-107). At a query in the latest world in which an entry's visibility changed, or later, a match's valid worlds start at that world, with no walk of the entries: exact at their end, narrower at their start (`unified` 89b3bcff81 and d04256a442, E-300, E-301). A match through `Callable` on c8ef0e581e, 1daebeab81, 23022b0ec7 (E-324).

### 5.4 The ambiguity report at a membership

At `jl_declare_membership`, for each function with a method at the new set and a method at another set the member is in, or at one of the member's declared supertypes, with no method more specific for the member, a warning names the pair and the joint method's signature: the two signatures' intersection, where the two meet as `All{X, Y}` (§4.9). Strict mode makes it an error: the report's findings refuse the membership (§4.3). A method that dominates every common member suppresses it.
- The search reads the method table, never a dispatch cache, since a cache entry made before the membership may still answer for the call types; it asks the entry's world, which strict mode's check asks before the counter reaches it.
- It counts only the sets of entries live in the entry's world: a retired entry, or an image's entry refused at activation, is no set of the member.
- The question is asked at the methods' own arity: each method's signature with the member in place of its set, the two intersected. An empty intersection is no ambiguity.
- At those call types the two methods are ambiguous as `Base.isambiguous` decides: both match, neither is more specific, and no matching method more specific than both covers the types.
- One warning per function and pair of sets.
- **An intersection no type is in.** An argument `All{X, Y, …}` is *unmet* in a world where no type of that world is in every component. Nominal supertypes form a tree, so a common type is in some set component by an entry: the entries live in that world at the set components (and at the sets that join them) are read (`jl_has_unmet_argument`). A `Callable` component, or a set it joins, makes the intersection met: its members are the types whose methods match it (§7.4), and any later method can make one. A `Vararg` tail whose length is not a positive constant is met by its empty tail.
- **Dispatch's lookup at an open set:** a match met only at unmet arguments stays. A later membership may meet the intersection, and compiled code relies on no negative at an open set (§4.8). So `describe(::ColTable)` against `describe(::AbstractString)`, which meet only at `All{AbstractString, ColTable}`, are both matches, and a call at `ColTable` dispatches. Leaving such a match out under a guard on the pair's cell (§5.6) is **Open** ([open issue 172](../open-issues.md#2-design)).
- **Dispatch's lookup at a final pair:** where every unmet argument's pair is final (§4.8), the lookup drops the match met only there, also one that would win, at any number of matches, before the matches are sorted and their ambiguity computed, and returns the pairs' final cells (`jl_matching_methods_cells`). Inference carries them on the lookup's result and records them with the call, so a membership that meets the intersection invalidates the caller.
- **Julia's ambiguity reflection** (`Base.isambiguous`, `detect_ambiguities`) asks the same question in the query's world: an argument met only as an unmet intersection has no value there, as an argument met only as `Union{}` has none. So two methods at a set and at a type no member of it relates (`describe(::AbstractString)` and `describe(::ColTable)`) are not reported until a membership makes them meet, and then by this report.

**Status:** Implemented on `unified` 0d529d33a9 for a concrete member, the joint method at `All{X, Y}` 8a9144928e (W-107), a pattern member at the call types both methods reach 264b7f959f (gate `m2_ambiguity_arity`, E-320). Strict mode's error with strict mode (W-114). The reflection in the query's world on `unified` b133374e9d (`has_unmet_intersection`, `base/reflection.jl`; E-330); an intersection unmet by the world's entries on `unified` 43c222c751 (gate `n20_unmet_lookup`, E-331); dispatch's lookup keeping the match at an open set and dropping it at a final pair with its cells, on `unified` 999777ab77 (gate `n20_unmet_lookup`, E-341): mine (2026-11-09, [the performance review](../reviews/2026-11-09-performance-day.md) H2; [the plan](../plans/2026-11-09-c82-unmet-match-lookup.md)). The report at a member's declared supertype: C-78. Strict mode's refusal, the search without caches and the live entries only on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343).

### 5.5 A membership lowers dispatch caches

A membership lowers the `max_world` of each leaf-cache and typemap-cache entry whose selected method changes at the new member, so the next call looks up again. A selection that becomes ambiguous changes too. The walk replays a method at the new set whose own entry is live in the table: the replayed method is the one that now applies, not one that matched before the membership. It invalidates no CodeInstance: compiled calls it could change carry guards (§5.6).

**Status:** Implemented on `unified` 29035cab11; that the walk invalidates no code, on `unified` 79b948420e (W-112): a compiled call a membership could change carries its guard (§5.6); the walk's cost in proportion to the replayed method's own function, the member substituted at a parametric set, on `unified` aa997b2180 (W-123). Gates `m2_dispatch_worlds`, `m2_stale_caller`, `n7_guards`, `m2_parametric_replay`; a selection made ambiguous at a member called before, on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343).

### 5.6 Guards and cells

- **The shadow query.** Inference at a call `f(s::S)` with `S` concrete selects a method `m₀`. It also asks for the methods of `f` at open sets `Z` that `S` could join (`jl_could_join`) and that would beat `m₀` at `S`. A method matched through `S`'s supertype chain, other than `f(::Any)`, has none. Each such (set, argument) is a shadow.
- **The cell.** For each shadow, inference records an edge to a membership cell: one mutable object per (member type object, set) for a parametric member, per (member typename, set) otherwise. The compiler creates it on demand and hangs it on the member's `TypeName`. Its `min_world` is `typemax` until an entry matches, then the entry's.
- **The guard** loads the cell's `min_world`, compares it with the task's world, and branches, as the inliner's union split branches. The slow branch is a full dispatch with no edge; the fast branch is the static call to `m₀`. The load is hoisted out of loops.
- **The guarded call's result** is the join of `m₀`'s and the declared result of the shadowing method (§6.8); `Any` where none is declared.
- **`Callable`'s memberships** (§7.4) have cells as any membership does; a method definition of the member's type lowers the cells it changes.
- **No guard arises:**
  - at a final non-member (§4.8);
  - where `m₀` matched through the chain and is not `f(::Any)`;
  - at a function with no method at an open set;
  - at a method that can only raise at a type that joins later: its declared result is `Union{}` (§6.8), or it serves no such type, marked by `Expr(:meta, :serves_no_member)` in its body. The mark is read when the method is defined, before its insertion. The trait's method for a required operation carries it ([traits §5.5](traits.md#55-forwarding-with-by)).
- A method at an open set defined later invalidates the compiled callers its insertion reaches, a caller with a pruned arm at a type the set could take included; they compile again with the guard. A method that can only raise invalidates none of them.

**Status:** Implemented on `unified` 79b948420e (W-112): the shadow query over each function's methods at sets (a set under a union's arm, an intersection, a parameter or a varargs tail included); a cell per (member type, set), registered with each set, opened by a declaration or an image's activation, registered when an image brings it; the guard in the inliner's union split, its fallback the dynamic call; a method at a set defined later invalidates the callers it shadows, a pruned arm included (`unified` 07c0bee2a2, gate `n11_late_shadow`, E-296). A method that can only raise is no shadow: by its declared result `Union{}` on `unified` 07c0bee2a2, by the mark on 40401f67d8 (E-297: CSV's load after REPL's 0.7 s against 5.4–5.8 s, the forks' session 5.1–5.5 s); mine (open issue 158 (a), 2026-11-08). Gate `n7_guards`; E-280. They deliver a committed guarantee, a membership invalidates nothing ([facts §10](facts.md#10-memberships); the user, 2026-11-06, open issue 146). With C-58, C-59. `Callable`'s cells with W-113.

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

**Status:** Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"); a use case to investigate: [open issue 147](../open-issues.md#2-design). The name `TraitKey`, beside BaseTraits' trait `Keyed`, is mine (2026-11-06). Keys computed by the runtime from memberships: mine (2026-11-06, [the work plan's review](../plans/2026-11-06-work-plan-under-the-draft-reference.md) §6, weak point 4).

### 6.2 Compilation signatures

At each argument whose declared type is a set, or a parameter bounded by one, a method's compilation signature is one of:
- **per key:** `TraitKey{X, R, F}`, the member's key (§6.1), where the method is fully bounded at the argument (§6.7) and the attribute is `Compiled`. Inference runs once per key, by the path `@nospecializeinfer` takes. Optional with keys: until they are built, such an argument is compiled per type;
- **per type:** the member's type, where the method is open at the argument and the attribute is `Compiled`;
- **once:** the erased key `X{p…}`, where the attribute is `Dynamic`.

A value whose type is `Dynamic{X}` has the erased key by its type ([traits §7.7](traits.md#77-dynamicx)).

- So one (method, argument tuple) has up to two compilation signatures per trait argument, chosen per call (§6.3): up to 2ⁿ for n trait arguments, each compiled only where a call asks for it.
- Keyed instances are cached with their original tuple (`cache_with_orig`), so a concrete tuple maps to its keyed or its erased instance. A plain dynamic call's attribute is a function of the method and the tuple (§6.3), so the leaf cache keys entries by the tuple alone; `Core.attributed_call` has a cache of its own (§6.9).
- **Static parameters** bound by a keyed argument are those the key fixes. A method whose body uses a static parameter the key does not fix is open at that argument.

**Status:** Implemented on `unified` e692e57ab7 (W-111) per type and once, chosen per call by the attribute (§6.3). Inference infers a call at the instance that runs: the set's type at an argument compiled once. A dynamic call's instance compiled once by an attribute is cached with the call's own types. Per key: Optional (W-110). With C-54.

### 6.3 The attribute at a call

- **Each trait argument of a call has an attribute bit,** `Compiled` or `Dynamic`, which chooses its compilation signature.
- **It is resolved, strongest first** ([traits §7.5](traits.md#75-what-decides)):
  1. a cast written at the call (§6.9);
  2. an attribute the value carries:
     - an argument inside an instance compiled per key or per type is `Compiled`, inside an instance compiled once `Dynamic`. The instance's attribute is part of its CodeInstance, so inference knows it at every call that passes the argument on;
     - a value of type `Dynamic{X}` is `Dynamic`;
     - a value read from a field whose declared type is a struct parameter bounded by a set: inference tracks the attribute the parameter records, `Dynamic` for a `Dynamic{X}`, else `Compiled`;
  3. the method's attribute bits at the argument, from `@nospecialize` (`Dynamic`) and `@specialize` (`Compiled`) at an argument typed by a set, saved with the method as its `nospecialize` bits are; then the module's option;
  4. the set's default bit, except for a value whose type Julia's own modules or the set's own package define, with every type among its parameters, recursively (a value parameter is the type's own);
  5. the method's module's fallback: with `first_seen` (§2.1), `Compiled` at a static call whose caller infers the argument's concrete type, `Dynamic` at a dynamic call; otherwise `Compiled`.
- **A static call** resolves the bits in the caller's inference and invokes the instance.
- **A dynamic call with bits from 1 or 2** is a call of `Core.attributed_call` (§6.9): a cast written at the call, or a run-time site that passes on a trait argument of an instance compiled per key or once (codegen emits it there). It selects the method by the arguments' types as `jl_apply_generic` does, then resolves the rest (3 to 5) at the method.
- **A plain dynamic call** carries no bits. The runtime resolves 3 to 5 at the method: a function of the method, the tuple and the module's options. So `jl_apply_generic` and its caches stay Julia's.
- **The interpreter** passes the bits of casts written at the call, and resolves the rest at the method.

**Status:** Implemented on `unified` e692e57ab7 (W-111): a static call's bits resolved in the caller's inference, a dynamic call's at the method by the runtime, `Core.attributed_call` from casts and from a run-time site that passes on a trait argument of code compiled once; an argument `Compiled` whose type the caller does not know makes the call dispatch on it when it runs, a function barrier; gate `n6_attribute`. With C-54, C-55. A call's dispatch fact at its own signature, for G2 too, on `unified` 0ee9e4f8a6 (gate `n21_callsig_backedge`, E-340). The order is mine (2026-11-06), on the user's "Dynamic or not as a trait and library default, that the user can override"; the fallback by scope is the user's (2026-11-06). Bits only through `Core.attributed_call`: mine (2026-11-06, the work plan's review, S6). Step 4's exception taking the type's parameters: `unified` 7fb94ae02b, gate `n6_attribute`; mine (2026-11-08, [open issue 161](../open-issues.md#2-design)).

### 6.4 Calls from code compiled per key

- Code compiled per key holds the argument at the type `TraitKey{X, R, F}`. Operations and declared fields act on its parts (§6.5), whose types are concrete: each call there is at a fact.
- **Passing the argument on to another function `g`:**
  - **static** where the method of `g` selected at the key is the one selected for every member with that key in the current world. A guard reads a cell per (key, `g`). A later membership with that key lowers the cell when some method of `g` is more specific for the new member (found through the set-to-methods index at `jl_declare_membership`). A later method of `g` invalidates the caller through its dispatch edge at the key, as any insertion does;
  - **otherwise a run-time site,** dispatched on the object with the `Compiled` bit; the instance then receives the object (§6.5).
- Swift and Rust resolve such a call where the generic code is written, at the constraint. Julia dispatches it on the value's type, and G1 asks for Julia's answer. So the guard is what keeps the shared code equal to that answer, by the same mechanism as a membership's guard (§5.6).

**Status:** Optional (W-110), with keys; mine (2026-11-06).

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

**Status:** Optional (W-110), with keys.

### 6.6 The boxed adapter

A dynamic call to a keyed instance goes through one wrapper per keyed CodeInstance. The wrapper reads the receiver's and the fields' offsets from a table per (member typename, set) on the member's `TypeName`. If it costs more than the target in [the evidence](../design/evidence.md) §2, there is one wrapper per member instead (W-110 measures).

**Status:** Optional (W-110), with keys.

### 6.7 The definition-time check

- **One inference of a method at the erased signature** of each set argument, under a check flag of the native interpreter. There, operations of the set and its supertraits resolve to their declared results (§6.8), declared fields to their declared types, and calls passing the argument to a method at the set or a supertrait to that method.
- **Any other use of the argument** is recorded with its line, and inference continues past it at `Any`. The record decides the method's classification per argument, fully bounded or open. The classification is kept with edges to the unannotated functions it followed, so a later definition of one classifies the method again.
- **Under the `bounded` option** of the method's module or the method itself, an open argument raises `TraitUseError` listing every recorded use, at the method's definition or at the definition that opens it. A method marked `@open` (`Expr(:meta, :bounded, false)`) is exempt, and so is a constructor of a struct whose parameter is bounded by a set where it sets that parameter, Julia's default constructor included ([traits §8.2](traits.md#82-a-struct-parameter-bounded-by-a-trait)).
- Unannotated functions of the same module to which the method passes the argument are followed. A method that calls a function not yet defined is classified at its module's end, or at its first call.
- **A function of `Self` that an equation names** (`T = eltype(Self)`), called on the argument, resolves to the parameter's value, a constant of the key: `eltype(t)` keeps a method fully bounded where the trait defines `T = eltype(Self)`. So do Rust's associated types in generic code.

**Status:** The classification implemented in TraitWorld `unified` 59134ef (`classify`, `check_definitions`), with C-40 and C-41; its interpreter the compiler's own on `unified` 98fcbdfbba with TraitWorld 0ac3364 (W-123), so loading the library invalidates none of the compiler's code; `bounded` per method (`@bounded`) and `@open` there; the module's `bounded` option with `@trait_module` (TraitWorld `unified` bb78d02, W-111). The classification and the `bounded` option: the user, 2026-11-06, Q2 (a). The rule for equations is mine (2026-11-06; open issue 137). The classification kept with edges, and `@open`: mine (2026-11-06, the reviews of the draft).

### 6.8 A declared result on `Method`

- Lowering records `f(…)::RT` as the method's declared result, where `RT` is a type when the method is defined: built from constant globals, a module's constant bindings (`M.T`), literals and the method's static parameters (`Vector{T}`, `Union{Int, Nothing}`, `Vector{<:Real}`, `DataFrames.DataFrame`). An `RT` computed from the arguments (`::typeof(x)`) or read from a global that is not constant records none. The record does not claim to cover every member. Inference may read it as an upper bound, since the body asserts it.
- **The trait's method for an operation** carries the operation's declared result, with a flag that it covers every member: each member's serving method is checked to infer within it ([traits §5.10](traits.md#510-checks)). §7 relies on the flag.
- **An operation declared `::Self`,** with its receiver typed by the set, declares the set at the receiver's parameters: each member's method is checked to return the receiver type, the member's or its forwarding field's ([traits §4.4](traits.md#44-self)), which is a member there. A result that names `Self` inside another type declares none.

**Status:** The trait's method's declared result and its flag implemented on `unified` e70675a606, set by the library (TraitWorld `unified` e9a63f7); lowering's record of `f(…)::RT` on `unified` 0ba6317994 and 523214899f (a module's binding) (lowering's `declared_result` meta, evaluated by `jl_method_set_source`), gate `n16_declared_result`. Read by a guarded call's join (§5.6) and as a raise-only method's `Union{}`; the operation's rule (§7.1) reads only a result with the flag. The record's scope (a type at the definition) is mine (2026-11-09).

### 6.9 Casts and `keep`

- **Lowering turns a call with cast arguments,** `f(compiled_for(x), y)` or `f(with_dynamic(x))`, into `Core.attributed_call(bits, f, args…)`, a builtin that dispatches as the call with those attribute bits. Inference resolves it statically where it can. A cast anywhere else is a lowering error. A cast of a `Dynamic{X}` to `Compiled` passes the held object.
- **The front end reserves the names** `compiled_for` and `with_dynamic` as it reserves `ccall`: in a call's arguments they are the casts whatever the scope binds, and a local variable or a definition of either name is a lowering error. **Open** ([open issue 160](../open-issues.md#2-design); mine: recognized by their binding); the reservation is what is built.
- **A cast at an argument the selected method does not type by a set** has no effect. Inference records each such cast it finds; `detect_unused_casts(mod)` lists them.
- `Core.attributed_call` keeps a cache of its own, keyed by the tuple and the bits, and a table of its latest calls, keyed by the bits and the function's and arguments' types and read without a lock, so that a call whose arguments are no types makes no tuple type.
- **`Core.Dynamic{X}`** is an ordinary struct of `Core`, with no rule of subtyping: its memberships are declared by the library ([lowering §7](lowering.md#7-dynamicx-keep-casts)). `Core` defines it so that `keep` can make one.
- **`keep(x)`** for an argument `x` at a set `X` resolves where the instance is compiled: `Dynamic{X}(x)` in an instance compiled once for the argument, `x` otherwise. An `x` that is itself a `Dynamic` gives its object held anew, as `Dynamic{X}(d)` does: never a `Dynamic` of a `Dynamic`. Where the code is not compiled, it is resolved at the method's default attribute.
- Julia's call-site `@inline` and `@noinline` are the precedent: a statement about one call, written at the call.

**Status:** Implemented on `unified` e692e57ab7 (W-111): the casts lowered to `Core.attributed_call` and reserved, the builtin with its cache, `Core.Dynamic`, `keep` resolved by inference, a `Dynamic` held anew on `unified` ef93ff7844 (mine, 2026-11-08); the table of latest calls on `unified` b61e326170 (E-313: 43 ns a call against 109 ns, a dynamic call 17 ns; mine, 2026-11-09); `detect_unused_casts` in the library (TraitWorld `unified` bb78d02). With C-56 and lowering L-56. Mine (2026-11-06). Reserved names, `Dynamic` in `Core`: mine (2026-11-06, the reviews of the draft).

---

## 7. Operations on a value typed by its trait

### 7.1 The rule

- **A call of an operation of `X`** whose receiver's inferred type is a set instance `X{p…}` (not a key and not a concrete member) is inferred as the operation's declared result at those parameter values. The declared result comes from the trait's method's flag (§6.8).
- **The same split for a closed abstract type with a contract** ([traits §3.4](traits.md#34-open-and-closed)): a call of one of its operations whose receiver's inferred type is the type is compiled as the split, its result `Any`. The declaring module writes the contract once on the type's `TypeName`, `jl_declare_contract(T, ops, cands)`: its operations, the module's methods at `::T`, each carrying the operation's flag with the result `Any` (§6.8), and its candidates (§7.2), as `svec(ops, cands)`. Images keep it with the `TypeName`. A contract is declared in the image that defines the type; one written on a type another image holds is refused, since the writer's image would not keep it (Base's build declares Core's `IO`'s; mine, 2026-11-10). Inference reads it (`jl_contract_operations(T)`) where it reads a set's methods with declared results.
- The call is compiled as a split (§7.2), with the result asserted to the declared type, never converted ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). Where no split applies, the dynamic call's result is asserted.
- **A const result taken for its effects joins its type.** A declared result makes inference non-monotone: at the set the call's result is the declared result, and constant propagation that sees the member's type reaches the member's own method. Where the constant-propagated code is taken for its effects or its exception type, its result type is joined into the call's, so compiled code never returns a type its call's type excludes (`handle1`, `unified` ef1233e79e).
- A declared field read at such a value works the same way, and so does `getproperty` at a constant name `N` where the set is a subtype of a `HasProperty{N, R}`: its result is `R`.
- Under the facts mode, each branch of the split is a fact; the fallback is a run-time site.

**Status:** The rule for an operation's call implemented on `unified` e70675a606, compiled as the split (§7.2) with the result asserted. Declared fields implemented on `unified` 50da8d8ee2: the library writes a trait's declared fields on its `TypeName` (`jl_set_declared_fields`), inference reads them along the trait's declared supertypes, and along its supertraits (their instances from the set's own entries, `jl_supertrait_instances`) on `unified` 350c5b1c59. `getproperty` at a `HasProperty{N, R}`: on `unified` 350c5b1c59, a declared field named by the input `N` ([traits §4.3](traits.md#43-fields)). The facts mode: W-100. A closed abstract type with a contract on `unified` b05ae361e0 (E-337): mine (2026-11-09).

### 7.2 The split

```julia
Compiler.split_call(K, ::Type{RT}, f, x, args...)            # f(x, args...)::RT
Compiler.register_dynamic_candidate!(K, C)
Compiler.dynamic_candidates(K)::Vector{Any}                   # the first MAX_FACT_SPLITS, in order
```

- **The candidates of a set** are its concrete members in declaration order, from an index per set that the runtime keeps. An entry records its declaration's file and line; the order is by those. A concrete type joins the index at its membership, a member of a pattern at its first use (§10.4). The index is read without an edge.
- **The candidates of a closed abstract type with a contract** are the concrete subtypes its declaring module registers (`jl_register_candidate(T, C)`), in that order.
- **At an intersection** `All{X, Y}`, the candidates are those of `X`'s index that are members of every component.
- `register_dynamic_candidate!(K, C)` registers candidates for a key `K` that is not a set.
- **Inference:** where `x`'s type is not concrete and the set has candidates, `f` is inferred at `x`'s type intersected with the union of the first four candidates; each split is a fact with its edge.
- **In each branch the value's type is the candidate:** the argument is `Compiled` there, so a branch that a method at the set serves runs that method's instance for the candidate, and the branch's case is the candidate, never the set.
- **The split:** the inliner splits the call over them. The last branch, the fallback, calls through the table of the call's targets (§7.3), or is the dynamic call where no table applies. The split is never fully covered.
- **A branch is inlined only where its body is a leaf:** with what it inlines itself, it calls only builtins and intrinsics (`flush(::IOBuffer)` returns `nothing`). Every other branch calls its candidate's target through a `:caller_world` pointer (§8.1), made when the caller is compiled, as the table's miss makes one (§7.3). Such a branch records no edge, since the call dispatches in the caller's world. An inlined leaf records its edge, and brings no edge of a callee. So an invalidation below a candidate's operation stops at the candidate: an instance compiled once, which every caller of the operation shares, does not carry it to them.
- **The result:** an inlined branch whose result is not known to be an `RT` is asserted to `RT`; its candidate is a checked member ([traits §5.10](traits.md#510-checks)) or one of Base's (§7.5). A branch through a pointer and the fallback assert `RT` too: the target compiled for its type asserts its result (`Base._SplitTarget`), the dynamic call is asserted where it returns. Nothing is converted. The join is `RT`.
- **Which candidates a caller splits over is fixed when it is compiled.** A member registered later reaches the fallback, and invalidates nothing.
- Registration is lock-free for readers: the table is replaced on each registration.

**Status:** Implemented on `unified` e70675a606: the candidates per set, registered at a membership, at an image's activation and by the library at a pattern's member's first use, ordered by declaration (C-38); the split over the first four, the table as the fallback (§7.3). Each branch `Compiled` for its candidate on `unified` b133374e9d (found by `IO`'s `get`, whose candidates are all served by the default at `::IO`; gate `n19_io_trait`): mine (2026-11-09). `register_dynamic_candidate!` for a key: with keys (W-110). A branch not inlined through a pointer, with no edge, on `unified` 0c836f3ef6, and only a leaf inlined on 7bd8b6e512 (E-332, [open issue 167](../open-issues.md#2-design) (a)); the result converted (traits §7.9) on 0c836f3ef6 (E-333): mine (2026-11-09).

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
- **A miss** makes the pointer and adds it. The pointer is a `:caller_world` `cfunction` (§8.1) of a target whose method asserts each argument and the result (§7.2). It dispatches in its caller's world at each call, so the miss runs in the latest world, and Base defines the target before any code that can split: a caller may run in any world of Base's build (a generated function's generator runs in the world it was defined in). A type with no method for the call gets a pointer that raises the `MethodError` the call would.
- **Arguments and result** pass by value where the type is an isbits type of nonzero size, else boxed.
- **The fallback stays a run-time site:** it dispatches in the caller's world and records no edge. The table needs no invalidation.
- **Sessions:** pointers are valid in their session; a table saved in an image counts as empty in another.
- **Threads:** a table's state is replaced on each addition, never mutated; readers take no lock.
- **Applies to** a split whose function's type is concrete and not a kind, with at most six arguments after the value. Elsewhere the fallback is the dynamic call. In a trimmed program the fallback is the dynamic call. In a session without the compiler the table's miss makes no pointer, and the fallback takes the dynamic call.
- **Ahead of time:** for each member declared in a package, its targets and their thunks are compiled into that package's image, at each call signature whose other arguments are concrete. A target whose call has abstract further arguments is made at its first call.

**Status:** Implemented on `unified` e70675a606, ported from `trait-world-1.13` 711484a23e and 6d480d0753, but for the targets compiled ahead into images (C-39). The dynamic call where no pointer is made, on `unified` d554855579 (found by Base's `precompile` test, a session without LLVM; E-330): mine (2026-11-09).

### 7.4 `Callable`'s call

**Memberships.**
- `Core.Callable{A, S}` is a set with two input parameters. `F <: Callable{A, S}` holds where a call of an `F` at `A` selects a method (`hasmethod`), for every `S`. So dispatch picks by the arguments' signature, and `S` takes no part in membership.
- **Each method of `F` is a membership.** A method `f(x::T₁, …)` makes `F` a member of `Callable{A, S}` for every `A <: Tuple{T₁, …}`, in the method's worlds; one method must cover `A`, as for `hasmethod`. Subtyping reads `F`'s methods as it reads entries, through the method table's index by the function's type, and checks `A` against each method's argument types in the same subtyping environment. Subtyping runs no inference and keeps no memo of its own.
- **A question that reaches itself** (a method of `F` whose argument is bounded by a `Callable` that `F` must satisfy) is subtyping's own assumption within the query, recomputed at each query: the answer is the least fixed point, the same in every order of questions.
- **Defining a method declares the membership,** and deleting or replacing it ends it. What relied on the old answer is found as for any membership (§5.5, §5.6).
- **`Dynamic{Z}` with `Z <: Callable{A, S}`** is a member by the entry the library declares, as for any set ([lowering §9](lowering.md#9-callable)), never by a query of its call method.
- **Negatives are never folded:** a call whose method a later membership could change is guarded (§5.6). Compiled code that relies on a membership holds an edge to `F`'s dispatch at `A`, and is invalidated with it.
- `Callable` alone is any type with a call method.

**The call.**
- **A call of a value the code knows as a `Callable{A, S}`** (declared so as an argument, a field or an element, or a `Dynamic{Callable{A, S}}`) has the result type `S`, asserted on return (`TypeError`). Where inference proves the result, the assertion costs nothing. Each argument must be of `A`, or the call raises `MethodError`.
- **In an instance compiled once** for the argument, the call goes through a `:caller_world` pointer (§8.1) to the function's code compiled for `A`. The pointer is made at the first call per (signature, function type). The result is asserted to `S` (`TypeError`).
- **In an instance compiled per key,** whose key is the function's type, the call is direct.

This is `Callable`'s own handling, as Rust's `Fn` traits are the compiler's own. Swift's function types are matched by signature in overload resolution.

**Status:** Implemented on `unified` 7195706721, 5f0a8ffd50 (W-113): `Core.Callable` an open set from Core's build, compiled once by default; a concrete callable type a member by its methods visible in the query world, read by subtyping as choices beside its entries, a question that reaches itself answering no within the query; a method's definition opens Callable's cells, its deletion lowers the dispatch cache entries that went through Callable; a match through Callable holds an edge to the member's dispatch at `A`; a call through a value known as `Callable{A, S}` infers `S`, asserted. Gate `n8_callable`. A match's worlds bounded by the member's methods on c8ef0e581e, 1daebeab81, 23022b0ec7 (at the positions where the method's signature names `Callable`, §5.3; E-324). With C-61, C-62; the arguments checked against `A` (§7.4) on 1d493ca959 and c248dbfd8c. Dispatch by signature, `S` checked on return: the user (2026-11-06). Methods read as memberships, with no memo: mine (2026-11-06, E-267). An abstract type a member only by an entry: mine (2026-11-07).

### 7.5 `IO`

- **`Core.IO` is a closed abstract type with a contract** (§7.1). Its members are its subtypes, as in Julia. It has no entry, cell or guard, and code typed `io::IO` is compiled per stream type, as in Julia.
- **Base declares the contract** in `base/iotrait.jl`, kept in the system image (§9): `jl_declare_contract(IO, ops, cands)`, the operations Base's methods at `::IO`, each result `Any` ([traits §9b](traits.md#9b-streams-io)), and the candidates `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`, in that order (§7.2), fixed with the contract: no module adds one later. A stream past them (an `IOContext`, the REPL's `LimitIO`) takes the table (§7.3).
- **At a receiver typed `IO`,** an operation's call splits as at a set (§7.2), the firewall included. The places that ask for a set ask for a set or a type with a contract: the declared result's lookup and the split's type in inference, and `jl_candidates_of` in the runtime; `jl_register_candidate` refuses a type with a contract.
- **No result is promised:** members join by their declared supertype, before their methods exist, and no check reaches them ([traits §5.10](traits.md#510-checks)), so each operation's result is `Any`, as Julia infers it at a receiver typed `IO`. A call through `IO` returns the stream's own result: Core's streams and `Filesystem.File` a `UInt` count, `IOBuffer` an `Int`.
- **The eraser `IOContext{IO}`** holds its stream in a field typed `IO`, so its forwarders' calls of the operations split. Base defines `IOContext{IO}(io)` and `IOContext{IO}(io, key => value, …)`; for an `IOContext`, the new context merges its properties, as `IOContext(io, …)` does.

**Status:** Implemented on `unified` b05ae361e0 (W-129 (c); `base/iotrait.jl`, `jl_declare_contract`; gates `n19_io_trait`, E-337); each result `Any`, nothing converted, on ef1233e79e, the candidates in the contract on 18bbbf0841 (open issue 171, C-81; gates `n19_io_trait`, `n23_contract_image`; E-340). The user (2026-11-09: "Go with the Fable plans recommendations"; [the plan](../plans/2026-11-09-io-alternatives.md) §4.2). The candidates' order: mine (2026-11-09); no result promised: mine (2026-11-10). Targets at a stream past the candidates compiled at the first call: open issue 170.

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

**Status:** Implemented on `unified` 6f936edf18.

### 8.2 The per-call-site dispatch cache

- Julia's `call_cache` holds method-cache entries per call site. Two kinds are added:
  - **wildcard entries:** a method-cache entry with no `Vararg`, no type variables and no guard signatures, whose parameters are concrete or `Any`, matched where every non-`Any` position has the argument's exact type;
  - **exact-type entries:** for any other entry, an entry at the call's exact argument types, kept in the method cache's leaf cache, so later misses reuse it; for a varargs method only up to as many arguments as Julia's compilation signatures spell out for it.
- A plain dynamic call carries no attribute bits (§6.3), so entries are keyed as Julia's are.
- Each entry's range is the copied entry's; a call outside it looks up again.

**Status:** Implemented on `unified` 8319275b9e for wildcard entries. Exact-type entries: W-109, in a form whose cost at a site that sees many types is vanilla's ([PE-20](../record/performance-explorations.md)).

### 8.3 Further work

Optional, each only if a measurement asks for it:
- a runtime table of compiled entry points with their world ranges;
- a witness carried in the value;
- recompiling in the background with the observed types;
- a cache emitted by codegen with direct calls.

**Status:** Optional.

---

## 9. Images and the machine-code cache

- **Memberships in package images.** An image writes every entry its modules declared in a list of its own, as it writes its methods for other modules' functions; an entry on one of its own types is also on that type's list. At load the list is activated before the image's code is validated: each entry in force is in its set's index and in the session's list of activated entries (`jl_activated_memberships`, never written into an image), from which the library makes the records of the membership's check again ([lowering §11](lowering.md#11-checks-errors-and-what-images-keep)), the entries get the loading session's worlds, the world of the image's methods. The cells' update, the dispatch caches' lowering (§5.5) and the ambiguity report (§5.4) run for each as at a declaration. Validation knows the membership cell and positive-membership edge kinds.
- **Machine code only for code that runs:** CodeInstances of either policy; never `return_type`'s answers.
- **Code reached only by a dynamic call is kept** where its G2 bit is set (§3.2), of either policy: plain code that facts code reaches is then cached as facts code is.
- **An image holds the code a facts run-time site reaches whatever the values.** While an image is built, a run-time site in facts code whose argument types match exactly one method, which specializes on none of the site's abstract arguments, has that method's instance compiled into the image, at its compileable signature and the facts policy. *Specializes on none* means: at each abstract argument the method is `@nospecialize`, the argument is no trait argument, and its declared type has no free variables and is no kind. Code that needs an instance per value's type at such a site (a closure capturing untyped values) is not covered; it is written as a loop.
- **An image keeps no external code specialized at a signature type without a hash** (a value-specific instance). Its insertion at load would scan its method's specializations.
- **The checks' records** of members checked while the image was built (traits §5.10) are kept with it.
- **The system image keeps the indices of sets** as it keeps its method tables: its methods at sets and each function's, the sets' candidates, entries and cells, the contracts of closed types (§7.1) and their candidates, and the split tables' miss (§7.3). So `IO`'s contract holds from the start, and a membership opens the image's cells.
- **Compiling ahead:** for each membership a package declares, the set-to-methods index (§5.1) gives the methods at the set and its supersets to compile at the member's key ([traits §16](traits.md#16-compiling-ahead-closed-programs)).
- **A machine-code cache across sessions is the goal of the record.** The record of §3.1 is kept complete, naming its targets by identities stable across sessions:
  - a method by module path, name, signature and a digest of its lowered code;
  - a type by path and layout;
  - a membership by member, set and declarer.

  So a cache of machine code later adds a loader, not a mechanism. The cache itself is paused ([decisions](../record/decisions.md) §5).
- No part of this design stores a world, a session object or an address where a stable identity serves.

**Status:** Memberships in package images implemented on `unified` 28c401eb0c (W-108), refused at a second instance on 07c0bee2a2; the edge kinds with W-100 and W-112. Every activated entry in its set's index and the list of activated entries on `unified` e42047dba2 (C-83 retired, gate `n12_image_instances`, E-344); a second entry in force for one member and set: C-84. The pattern members' answers: lowering L-55. Compiling ahead: Planned ([traits §16](traits.md#16-compiling-ahead-closed-programs)). The keep rule by the G2 bit implemented on `unified` 823754556f (W-100), for code reached only dynamically from outside the package: TraitWorld's image grew 3.7 %. The cache: paused. The rule for a signature type without a hash is implemented on `unified` 999634c858. The walk and the report at activation: mine (2026-11-07). The rule for run-time sites implemented on `unified` 6767b03893 (`Compiler/src/facts.jl` `rtsite_targets`, `typeinfer.jl` `compile!`; E-326; gate `n17_rtsite_targets`), for all modules: mine (2026-11-09). The system image's indices of sets on `unified` b133374e9d (W-129 (b), gate `n19_io_trait`): mine (2026-11-09).

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
- Strict mode, the override rule, a member's check kept while it is a member ([traits §5.10](traits.md#510-checks)), the `no_pirates` and `bounded` options use them.
- In the image hook a method about to be activated is inferred as it is: a call it makes to another inactive method of the same image infers `Union{}` there.
- Both hooks first bring the library's records up to the memberships images have activated (§9). The image hook runs before its image's own memberships are in force, which its build checked with its methods.

**Status:** Implemented on `unified` 28c401eb0c (W-108). TraitWorld `unified` 701aaab uses them for the override rule and for a `struct S <: X` without its `@implement`; `bounded` bb78d02 (W-111); strict mode and `no_pirates` 7adcc94 (W-114); a member's check kept, in the definition hook's first call and the image hook, 5b3c427 (E-342). The module-end hook: mine (2026-11-06, the work plan's review, weak point 6).

### 10.2 Hooks for strict mode

- **A deletion hook,** called at method deletion; it may refuse.
- **A hook for a binding redefined from another module,** at its source.
- **A report per image:** the edges that failed validation, with the winning method.
- **Strict mode's check at a membership** (§4.3): `jl_set_strict_memberships(on)`, set by the library's strict mode.

**Status:** The deletion hook implemented on `unified` 5f2373b2d5 (`jl_set_method_deletion_hook`, W-114). The report per image is the library's, from validation's log (TraitWorld 7adcc94). The hook for a binding redefined from another module: Planned ([traits T-96](traits.md#19-deviations)). The flag for a membership on `unified` 0bb8f38830 (E-343).

### 10.3 Field-offset intrinsics

```julia
Core.Intrinsics.getfield_at_offset(obj, T::Type, off::Int)::T
Core.Intrinsics.setfield_at_offset(obj, T::Type, off::Int, x)::Nothing
```

- Read or write the value of type `T` at byte offset `off` of `obj`, with the write barrier for a reference and Julia's alias metadata for a mutable field.
- The offset is not checked; the caller guarantees the field.
- The calling convention's field references (§6.5) use them.

**Status:** Optional (W-110), with keys.

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

**Status:** Implemented on `unified` ec4f9a8714 at dispatch, with C-30 and C-31; a failed check lowers the entries made while it ran on 07c0bee2a2; at a split's table miss and `keep` with W-109 and W-111. Mine (2026-11-06). Checks only, and where it runs: mine (2026-11-06, the reviews of the draft).

---

## 11. Changes useful without traits

Each applies to all code.
- **An invoke keeps the exact specialization over a widened varargs tail,** where the compileable signature only widens a `Vararg` tail and the exact specialization has code.
- **An inference cycle's members inline each other:** when a cycle finishes, each optimized member is offered to the inliner of the members optimized after it.
- **The run-time `return_type` entry in the system image:** `_return_type(::NativeInterpreter, ::DataType)` is a compiler bootstrap entry; with the facts policy, so is the entry of `return_type`'s own interpreter (§1.4).
- **Reflection in the compiler's world** with an explicit `NativeInterpreter`.
- **The dispatch profiler:** `JULIA_DISPATCH_PROFILE=1` counts dynamic calls per callee method, per lookup path and per call site.
- **Base's type introspection on builtins and `invoke`:** the helpers that assert their effects (`padding`, `array_subpadding`, `fieldcount`, `isabstracttype`, `unwrap_unionall`, `isvatuple`, `datatype_alignment`) read a type's fields with `getfield`, take sizes, offsets and field types from builtins or the runtime, and call each other through `invoke` at the callee's own signature. A package's methods for its own types cannot make their assertions false.
- The world-checked caches of §8.1 and §8.2, and an image's rule for a signature type without a hash (§9).

**Status:** Implemented on `unified`, one commit each, below the stages' commits ([`../design/julia-changes.md`](../design/julia-changes.md) §7.1); the entry of `return_type`'s own interpreter with the facts policy (W-100). Upstream proposals: the same chapter.

---

## 12. Status index

| Interface | Status | Section |
|---|---|---|
| the facts inference, fact signatures, run-time sites, `return_type`, effects | Implemented (`unified`, W-100), with C-45, C-47 | §1 |
| the policy per method; one CodeInstance per MethodInstance and policy; calls between policies; the test bed; `--trim` | Implemented (`unified`, W-100), with C-49, C-50, C-53; no method of Base a boundary (E-279) | §2 |
| fully typed mode | Implemented (`unified` 5f2373b2d5, W-114) | §2.7 |
| the dependency record; G2 as a predicate | the record's positive memberships and G2's bit implemented (`unified` 9a601902a0, 8ef154476f), with C-51, C-52; cells W-112 | §3.1, §3.2 |
| the code slot | Implemented (W-101), the last resort `unified` 49ab4294b6; with C-64 to C-67 and C-69 | §3.3 |
| sets and their contracts, memberships, worlds, transitivity, subtyping in the walk | Implemented (`unified` 62016706d0) | §4.1–§4.5 |
| one instance per member | Implemented (`unified` 62016706d0; a pattern edc2653e43) | §4.6 |
| three layers; negatives never fold; positives through entries | Implemented (`unified` 62016706d0); positives' world and record on `unified` 9a601902a0, with C-51; closed after load `unified` bf447db25e, with C-76, C-77; an intersection no type is in, final at a set closed after load, `unified` 1906196731 (E-334), with C-79 | §4.7, §4.8 |
| intersections `All{X, Y, Z, …}` | Implemented (`unified` 8a9144928e), but for the key and the split at an intersection (W-110, W-109) | §4.9 |
| type values as members | Implemented (`unified` 62016706d0; the kinds f14be868df, 0c9e44cb3d) | §4.10 |
| methods at sets in the table; specificity; match ranges | Implemented (`unified` 29035cab11, 62016706d0; intersections 8a9144928e) | §5.1–§5.3 |
| the ambiguity report at a membership | Implemented (`unified` 0d529d33a9, a pattern member 264b7f959f); strict mode's error W-114; dispatch's lookup at an unmet intersection on `unified` 999777ab77 | §5.4 |
| dispatch caches lowered at a membership | Implemented (`unified` 29035cab11; no code invalidated 79b948420e) | §5.5 |
| guards and cells | Implemented (`unified` 79b948420e, W-112), with C-58, C-59 | §5.6 |
| `TraitKey`; compilation signatures per key, per type, once | per type and once implemented (`unified` e692e57ab7, W-111), with C-54; Optional (W-110): `TraitKey`, per key | §6.1, §6.2 |
| the attribute bits at a call | Implemented (`unified` e692e57ab7, W-111), with C-54, C-55, C-57 | §6.3 |
| calls from code compiled per key | Optional (W-110) | §6.4 |
| the calling convention; the boxed adapter | Optional (W-110) | §6.5, §6.6 |
| the definition-time check and the classification | Implemented (TraitWorld `unified` 59134ef), with C-40, C-41 | §6.7 |
| a declared result on `Method`; the operation's flag; lowering's record of `f(…)::RT` | Implemented (`unified` e70675a606, 0ba6317994) | §6.8 |
| casts at the call; `keep` | Implemented (`unified` e692e57ab7, W-111), with C-56, L-56 | §6.9 |
| operations on a value typed by its trait; the split; the table | Implemented (`unified` e70675a606, 50da8d8ee2), with C-38, C-39 | §7.1–§7.3 |
| `Callable`: dispatch by signature, its call, the result checked on return | Implemented (`unified` 5f0a8ffd50, W-113), with C-61, C-62; the arguments checked against `A` on 1d493ca959 | §7.4 |
| A closed abstract type with a contract; `IO`'s contract, its candidates, the eraser `IOContext{IO}` | Implemented (`unified` b05ae361e0, ef1233e79e, 18bbbf0841) | §7.1, §7.5 |
| world-checked caches: `:caller_world`, the per-call-site cache | Implemented (`unified` 6f936edf18, 8319275b9e); exact-type entries W-109 | §8.1, §8.2 |
| further caches at dynamic boundaries | Optional | §8.3 |
| memberships in images; the record toward a machine-code cache | memberships in images implemented (`unified` 28c401eb0c; one instance per member at activation, 07c0bee2a2); the positive-membership edge read at validation (`unified` 9a601902a0); the record's stable identities: C-52 | §9 |
| hooks, the module-end hook included; field-offset intrinsics; the member hook | the member hook implemented at dispatch (`unified` ec4f9a8714; C-30, C-31); the definition, image and module-end hooks implemented (`unified` 28c401eb0c); strict mode's deletion hook implemented (`unified` 5f2373b2d5), the binding hook Planned; field-offset intrinsics Optional (W-110) | §10 |
| changes useful without traits | Implemented (`unified`, the stack's first eleven commits) | §11 |

---

## Deviations

The build's heads: [state.md §6.1](../state.md#today); its commits, stage by stage: [julia-changes §7.1](../design/julia-changes.md#71-the-stack). IDs are shared with the record's other references and never reused.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-1 to C-17 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/compiler.md` | — | — |
| C-18 | — | *Retired* (2026-11-07): a membership invalidates no code on `unified` 79b948420e; guards cover the calls it could change ([§5.5](#55-a-membership-lowers-dispatch-caches), [§5.6](#56-guards-and-cells)); gates `n7_guards`, `m2_stale_caller` | — | — |
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
| C-30 | [§10.4](#104-the-member-hook) | The runtime keeps the member hook's answer per (member type, set) on the member's `TypeName`, a failure included. | The library keeps it, in a table of its own (`TraitWorld._CHECKED`); the runtime calls the hook at every dispatch miss of such a call, and lowers the cache entries a failed check left. | `src/gf.c` (`member_hook_at_dispatch`); TraitWorld `src/implement.jl` |
| C-31 | [§10.4](#104-the-member-hook) | The hook also runs in the compile queue, before a CodeInstance that relies on the member is published; a failing check compiles that use as the `ImplementError`. | Only at dispatch: a call compiled with the member's type known reaches the trait's method without a check, and a member that fails raises `MethodError` there. | `src/gf.c` |
| C-32 | — | *Retired* (2026-11-08): a set's inputs on `unified` 350c5b1c59 ([§4.6](#46-one-instance-per-member)); gate `n10_inputs` | — | — |
| C-33 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.7](#47-three-layers), [§5.3](#53-match-world-ranges-and-abstract-queries)); gate `n2_open_abstract` | — | — |
| C-34 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.9](#49-intersections)); gate `n2_all_form` | — | — |
| C-35 | — | *Retired* (2026-11-08): an image's membership that would give its member a second instance of a set is refused at activation, with a warning, on `unified` 07c0bee2a2 ([§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances`; E-296 | — | — |
| C-36 | — | *Retired* (2026-11-09): lowering records `f(…)::RT` on `unified` 0ba6317994 ([§6.8](#68-a-declared-result-on-method)); gate `n16_declared_result` | — | — |
| C-37 | — | *Retired* (2026-11-07): the split's last branch calls through the table on `unified` e70675a606 ([§7.3](#73-the-table-of-a-calls-targets)); TraitWorld test `table` | — | — |
| C-38 | [§7.2](#72-the-split) | A set's candidates are ordered by their declarations' file and line. | By the order in which the memberships are declared or activated: across images, by load order. | `src/datatype.c` (`register_candidate`) |
| C-39 | [§7.3](#73-the-table-of-a-calls-targets) | For each member declared in a package, its targets and their thunks are compiled into the package's image. | A target is made at its first miss in each session. | `base/splittable.jl` (`_split_table_miss!`) |
| C-40 | [§6.7](#67-the-definition-time-check) | One inference of the method at the erased signature, under a check flag of the native interpreter, records each use of a trait argument outside the contract; the classification is per argument. | The library infers the method with the compiler's check interpreter (`Compiler.DefinitionCheckInterpreter`: an ephemeral cache, so every function it follows is inferred again, and the library's hook at each known call), a type beside the native interpreter rather than a flag of it, and records each call that takes a value typed by a trait outside the contract: per method, each use against the trait the value is known by. | `Compiler/src/types.jl` (`DefinitionCheckInterpreter`); TraitWorld `src/classify.jl` |
| C-41 | [§6.7](#67-the-definition-time-check) | The classification is kept with edges to the functions it followed and runs again at a later definition of one; a method that calls a function not yet defined is classified at its module's end or first call; a constructor that sets a bounded parameter is never refused. | It runs when `classify` or `check_definitions` is called, and under `bounded` at the method's definition. A method whose calls reach no method yet, or that names a global of its module not yet defined, waits: a definition of that name classifies it again, and its module's end a last time (TraitWorld c9f701e). It is not kept with edges, so a later definition of a function it followed does not classify it again; no constructor is exempt. | TraitWorld `src/classify.jl` |
| C-42 | — | *Retired* (2026-11-07): code of both policies under Julia's own owner on `unified` 10c7e1c2cf ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy)); gate `f3_policy_code` | — | — |
| C-43 | — | *Retired* (2026-11-07): lowering carries the policy meta into every method a definition makes, on `unified` cb7f55bd35 ([§2.2](#22-the-method-flag)); gate `f2_policy_flags` | — | — |
| C-44 | — | *Retired* (2026-11-07): the policy of the code that reaches a method on `unified` c44a447f2c ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy), [§2.4](#24-calls-between-policies)); gate `f6_reach_policy` | — | — |
| C-45 | [§2.4](#24-calls-between-policies) | Constant propagation from plain code into a facts callee infers the callee again under the facts policy; concrete evaluation of a facts callee from plain code uses its facts effects with a code edge. | Constant propagation and constant evaluation into a callee of the other policy run under the caller's policy, in the caller's inference; past four nested inferences of the other policy a call is answered as unknown. | `Compiler/src/facts.jl` (`typeinf_other_policy`) |
| C-46 | — | *Retired* (2026-11-08): the bit requires each inlined callee's own record to satisfy G2, the callees found from the debug info, on `unified` 1d493ca959 ([§3.2](#32-g2-as-a-predicate)); gates `f4_g2_bit`, `m3_g2_bit`, `m3_g2_counts`; E-297 | — | — |
| C-47 | [§1.4](#14-return_type) | In code compiled by facts, plain inference's answer is folded where it rests on facts (at most four concrete signatures, one covering method each, every edge at a fact). | Such an answer is asked at run time too: only a constant, a concrete type that is not a kind, or `Union{}` from the facts answer is folded. | `Compiler/src/tfuncs.jl` (`return_type_tfunc`) |
| C-48 | — | *Retired* (2026-11-07): the test bed starts and runs on `unified` c44a447f2c ([§2.5](#25-the-test-bed)); E-275, gate `f6_reach_policy` | — | — |
| C-49 | [§2.1](#21-the-module-option), [§2.3](#23-one-codeinstance-per-methodinstance-and-policy) | A method's policy follows its module's option. | A method instance's policy is read at its first use and cached in its flags (an image does not keep it); a module option set after one of the module's methods was first called leaves that method's policy as first read. | `src/gf.c` (`mi_policy`) |
| C-50 | [§2.4](#24-calls-between-policies) | The operation of `modifyfield!`, `modifyglobal!` and `memoryrefmodify!`, and a builtin that calls a function, reached by a dynamic call, dispatch with the policy of the code that calls them. | They reach with the setting's default; so does an ABI converter's generic call. | `src/builtins.c` (`jl_apply_reach`), `src/datatype.c`, `src/codegen.cpp` (`emit_abi_dispatcher`) |
| C-51 | [§4.8](#48-negatives-never-fold-positives-through-entries), [§3.1](#31-the-record) | A positive answer through an entry folds, with the code's worlds from the entry's and the entry in its record. | It folds at `isa`, `<:` and a dispatch match in the frame being inferred. `typeassert`'s nothrow, `typesubtract`, the optimizer's own `isa` queries and the semi-concrete pass leave such an answer unfolded. | `Compiler/src/typeutils.jl` (`positive_fold_blocked`), `Compiler/src/tfuncs.jl` |
| C-52 | [§3.1](#31-the-record), [§9](#9-images-and-the-machine-code-cache) | The record tells result edges from dispatch edges, gives a code edge the digest of its callee's lowered code, records the layouts of the types whose fields the code reads, and names its targets by identities stable across sessions. | Result edges are listed apart, on the CodeInstance's analysis results (W-101); a code edge names its callee's CodeInstance; no layout is recorded; targets are objects of the session or its images. In a session a method's identity and the binding edges serve. The rest comes with the machine-code cache (paused). | `Compiler/src/stmtinfo.jl` (`add_edges_impl`), `Compiler/src/typeinfer.jl` |
| C-53 | [§2.6](#26---trim) | A trimmed image writes no facts flags. | It keeps the module's and the methods' flags; nothing reads them under `--trim`, and its CodeInstances are all plain. | `src/staticdata.c` |
| C-54 | [§6.2](#62-compilation-signatures), [§6.3](#63-the-attribute-at-a-call) | At each argument whose declared type is a set, or a parameter bounded by one, the attribute chooses the compilation signature. | An argument typed by a `where` variable bounded by a set (`x::C` with `C <: X`) is compiled for the value's type whatever its attribute; where the body uses `C`, what the intended state is: [open issue 163](../open-issues.md#2-design). A set whose type names the method's variables (`X{T}`) takes its attribute, compiled once at its instance with the variables' values (`unified` 1d493ca959, c248dbfd8c, ef93ff7844; gate `n13_attribute_free_vars`; TDE's three checks pass, E-298). | `src/gf.c` (`is_trait_arg_type`) |
| C-55 | [§6.3](#63-the-attribute-at-a-call) | A set's default does not apply to a value whose type Julia's own modules define. | Julia's own modules are `Core` and `Base`: a standard library's type takes the set's default as a package's type would. A module of a script (under `Main`) counts as a package of its own. | `src/gf.c` (`type_is_own`, `module_package`) |
| C-56 | [§6.9](#69-casts-and-keep) | Where the code is not compiled, `keep(x)` is resolved at the method's default attribute. | It is `x`. | `base/boot.jl` (`Core.keep`) |
| C-57 | — | *Retired* (2026-11-10): a call's dispatch fact at its own signature, for G2 too, on `unified` 0ee9e4f8a6 ([§6.3](#63-the-attribute-at-a-call), [§3.2](#32-g2-as-a-predicate)); gate `n21_callsig_backedge` | — | — |
| C-58 | [§5.6](#56-guards-and-cells) | The guard compares the cell's `min_world` with the task's world. | It tests whether the cell is still closed (`min_world` is `typemax`): once a membership opens it, a task in an older world takes the dynamic call too, which gives that world's answer. | `Compiler/src/ssair/inlining.jl` (`ir_inline_unionsplit!`) |
| C-59 | [§5.6](#56-guards-and-cells) | The guard's load is hoisted out of loops. | It is an atomic load that LLVM leaves in a loop whose body calls a function. | `Compiler/src/ssair/inlining.jl` |
| C-60 | — | *Retired* (2026-11-08): a call of a value known as `Callable{A, S}` checks its arguments against `A` where inference cannot prove them, and raises `MethodError` where it proves them outside, on `unified` 1d493ca959 and c248dbfd8c ([§7.4](#74-callables-call)); gate `n14_callable_args`; E-297 | — | — |
| C-61 | [§7.4](#74-callables-call) | In an instance compiled once for the argument, the call goes through a `:caller_world` pointer to the function's code compiled for `A`. | It is a dynamic call, its result asserted. | `Compiler/src/abstractinterpretation.jl` |
| C-62 | [§7.4](#74-callables-call), [§4.8](#48-negatives-never-fold-positives-through-entries) | A positive answer at `Callable` folds, with an edge to the member's dispatch at `A`. | Outside dispatch (`isa`, `<:`) it is not folded: there is no entry to rest it on. | `Compiler/src/typeutils.jl` (`record_memberships!`) |
| C-63 | — | *Retired* (2026-11-09): a match through `Callable` is bounded by the member's methods' worlds at the positions where the signature names it, on `unified` c8ef0e581e, 1daebeab81, 23022b0ec7 ([§7.4](#74-callables-call), [§5.3](#53-match-world-ranges-and-abstract-queries)); gate `n8_callable`; E-324 | — | — |
| C-64 | [§3.3](#33-the-code-slot) | Reflection shows the code that runs. | `code_llvm` and `code_native` compile a CodeInstance of their own, with no record of result edges: they show each call bound by address, where the code that runs calls through a slot. | `Compiler/src/typeinfer.jl` (`slot_result_edges`: only for cached CodeInstances) |
| C-65 | [§3.3](#33-the-code-slot), [§9](#9-images-and-the-machine-code-cache) | A loaded image's caller of a callee that the session changed before the load is marked and revalidated, as a caller in the session is. | Validation at load does not mark: such a caller is dropped and compiled again. | `base/staticdata.jl` (`verify_method_graph`) |
| C-66 | [§3.3](#33-the-code-slot) | A cycle of marked CodeInstances is revalidated as one. | Revalidation goes depth first; a CodeInstance met again on its own path fails, and the cycle's CodeInstances are compiled again. | `src/gf.c` (`revalidate_code_instance`) |
| C-67 | [§3.3](#33-the-code-slot), [facts §6.4](facts.md#64-the-compilers-own-code) | Every static call with only a result edge goes through a slot. | The compiler's own code, compiled while it bootstraps itself, binds every call: its call targets need not be cached then. Its callers are invalidated as before. | `Compiler/src/typeinfer.jl` (`slot_result_edges`, `bootstrapping_compiler`) |
| C-68 | — | *Retired* (2026-11-08): the slot's entry where no code can be made, on `unified` 49ab4294b6 ([§3.3](#33-the-code-slot)); gate `slot_cascade.jl` | — | — |
| C-69 | [§3.3](#33-the-code-slot), [§9](#9-images-and-the-machine-code-cache) | A marked caller is kept through an image written before its revalidation. | The image writer writes a marked caller as invalid (its lowered `max_world`): the image drops it. | `src/staticdata.c`; [the review](../reviews/2026-11-07-implementation-day.md) L3 |
| C-70 | — | *Retired* (2026-11-09): a kind meets a set that takes a type value, on `unified` f14be868df, 0c9e44cb3d ([§4.10](#410-type-values)); gate `m1_typevalue_isa`; E-321 | — | — |
| C-71 | — | *Retired* (2026-11-08): a member that fails its check at dispatch lowers the cache entries made for it while the check ran, on `unified` 07c0bee2a2 ([§10.4](#104-the-member-hook)); TraitWorld's test F10b; E-296 | — | — |
| C-72 | — | *Retired* (2026-11-08): the walk visits the replayed method's own function and substitutes the member at a parametric set, on `unified` aa997b2180 ([§5.5](#55-a-membership-lowers-dispatch-caches)); gate `m2_parametric_replay`; E-292 | — | — |
| C-73 | — | *Retired* (2026-11-08): a method at an open set reaches, at its insertion, the callers whose pruned arm its set could shadow, on `unified` 07c0bee2a2 ([§5.6](#56-guards-and-cells)); gate `n11_late_shadow`; E-296 | — | — |
| C-74 | — | *Retired* (2026-11-09): code a compile queue infers anew is inferred under its method's policy on `unified` dde5f9f5dc ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy)); gate `n15_image_policy`, E-311 | — | — |
| C-75 | — | *Retired* (2026-11-09): the edge instance made for a constant-propagated result carries the G2 bit, on `unified` 427760d9e9 ([§3.2](#32-g2-as-a-predicate)); gate `f4_g2_bit`; E-320 | — | — |
| C-76 | [§4.8](#48-negatives-never-fold-positives-through-entries) | The declarers of a pair are the set's owner and the type's owner, with their joint owners. | The set's module and the module of every `TypeName` in the type, each loaded with the package it is nested in; joint owners are not consulted. A joint owner that loads after the owners declares late, and its membership invalidates. | `src/datatype.c` (`jl_membership_final`, `type_declarers_loaded`) |
| C-77 | [§4.8](#48-negatives-never-fold-positives-through-entries) | Where both declarers have loaded, inference folds the pair's negative. | It folds at `isa` and `<:` (`isa_tfunc`, `subtype_tfunc`) and leaves out the guard (`jl_call_shadows`), in a frame that records the final cell. `tmeet`, `isa_condition`, `typesubtract` and the constants' and conditionals' meets still refuse it. | `Compiler/src/typeutils.jl` (`negative_fold_blocked`), `tfuncs.jl`, `abstractinterpretation.jl` (`call_shadows`) |
| C-78 | [§5.4](#54-the-ambiguity-report-at-a-membership) | The report at a membership covers a method at a set the member is in and one at the member's declared supertypes. | It covers methods at sets only: a member of a set `X` declared `<: AbstractString` gets no warning for `f(::X)` against `f(::AbstractString)`, and a call compiled before runs `f(::X)` for it where a dynamic call raises the ambiguity. | `src/gf.c` (`jl_declare_membership`'s report); gate `n20_unmet_lookup` (3) |
| C-79 | [§4.8](#48-negatives-never-fold-positives-through-entries) | Where an intersection no type is in is final, inference relies on it as on any final negative. | It folds at `isa` (`isa_tfunc`) and at dispatch's lookup (`drop_unmet_matches`, `src/gf.c`). `<:` (`subtype_tfunc`), `tmeet`, `typeassert`, a conditional's narrowing and a declared argument type still meet a set `X` closed after load with `AbstractString` as `All{AbstractString, X}`. An intersection of more than two components, or a component with free variables that is not an abstract type, is not asked. | `Compiler/src/tfuncs.jl`, `abstractinterpretation.jl` (`drop_unmet_final_matches`), `src/datatype.c` (`jl_unmet_final_cells`); gate `n20_unmet_lookup` (4) |
| C-80 | — | *Retired* (2026-11-09): `IO` a closed abstract type with a contract, on `unified` b05ae361e0 ([§7.5](#75-io)) | — | — |
| C-81 | — | *Retired* (2026-11-10): a closed type's candidates in its contract, kept by its image, on `unified` 18bbbf0841 ([§7.1](#71-the-rule), [§7.2](#72-the-split)); gate `n23_contract_image` | — | — |
| C-82 | — | *Retired* (2026-11-10): dispatch's lookup keeps an unmet match at an open set and drops it at a final pair with its cells, `Callable` and a `Vararg` tail met, on `unified` 999777ab77 ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `n20_unmet_lookup` | — | — |
| C-83 | — | *Retired* (2026-11-10): every entry an image activates is in its set's index, also one on the image's own type, on `unified` e42047dba2 ([§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances` | — | — |
| C-84 | [§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache) | A membership activated from an image ends an older entry in force for the same member, set and inputs, as a declaration does. | Activation ends none: two images can leave two entries in force for one member (a joint owner's redeclaration in a later image). The library takes the latest. | `src/datatype.c` (`jl_activate_memberships`) |
