# Compiler and runtime: the reference

**Adopted** (the user, 2026-11-06; W-105; [the folder's README](README.md)). This page defines what Julia's compiler and runtime provide to the design: each interface, what it means, and its rules. It describes the interfaces as designed. The status line of each section says how far it is built.

- Why each interface is needed, and what compiled code may assume: [`facts.md`](facts.md).
- How the language uses them: [`traits.md`](traits.md) for what a user sees, [`lowering.md`](lowering.md) for what the library's macros emit.
- The build is branch `unified` of the julia repository, on v1.13.2 (the worktree `julia-unified/`), in the stages W-98 to W-114 ([the work plan](../../attic/writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md), adopted) and the work items after them, W-101, W-123, W-128 and W-129 ([the work queue](../record/todo.md)). The inventory of its changes: [`../design/julia-changes.md`](../design/julia-changes.md).
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
| [3. The dependency record and the deep class](#3-the-dependency-record-and-the-deep-class) | What each CodeInstance assumed; G2 as a predicate over its edges at any depth; one compiled code per result |
| [4. Sets and memberships](#4-sets-and-memberships) | Open abstract types, memberships with worlds, transitive subtyping, intersections, negatives folded with an edge |
| [5. Dispatch](#5-dispatch) | Methods at sets in the method table, specificity, the ambiguity report, a membership's invalidation |
| [6. The kept forms and the definition-time check](#6-the-kept-forms-and-the-definition-time-check) | The box and the wrapper as types of `Core`; the forwarders made where a method is defined; the definition-time check. Keys: [an optional extension](extensions.md) |
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
- any signature of a call of an **owner-only function** ([facts §1](facts.md#term-owner-only), [§3](facts.md#3-fact-signatures)): the function's type is `T`'s first parameter (in a keyword call, `Core.kwcall`'s, the parameter after the `NamedTuple`);
- a dispatch tuple: concrete types that are not kinds, and `Type{T}` with `T` known;
- a tuple without a `Vararg` tail whose elements are concrete, or tuple types of concrete elements or unions of concrete elements, split by Julia's union-splitting cost at the interpreter's `max_union_splitting`;
- concrete members followed by a `Vararg{E}` tail of a concrete member `E`;
- a closure's call at kinds: the first argument a closure type, every other concrete or one of `DataType`, `UnionAll`, `Union`.

A union at a call's top level is split as Julia splits it, each split a fact signature with its own edge.

**Owner-only functions.**

```julia
Compiler.is_owner_only(F)::Bool        # F: a function's type
jl_set_owner_only(m, name)              # the declaration, on the function's binding
@compiler_options owner_only = true     # the default, a module's scope option (bit 64): @trait_module's
```

- `is_owner_only(F)` is true where the function's binding (`F`'s module and the name of its instance) carries the owner-only flag (`BINDING_FLAG_OWNER_ONLY`), which the declaration sets beside the binding's `public` flag, or where `F`'s module has the scope option `owner_only` (§2.1; a submodule inherits it) and `F`'s name is neither exported nor `public` there. A closure's type is its module's.
- The answer is read where the call is inferred. The code relies on it through its binding edge to the function: a later `public` or `export` of the function ends that code, as a redefinition of the binding does.
- Every reader of fact signatures reads the same test: inference (`facts_find_method_matches`) and the G2 predicate's test of a dispatch edge (§3.2).

**Not gated:** `invoke` and `hasmethod` at a declared signature resolve it as Julia does, with an invoke edge at the declared signature ([facts §3](facts.md#3-fact-signatures)).

An operation on a value typed by its trait: §7. With keys, an optional extension, two more forms: [extensions §1.3](extensions.md#13-calls-from-code-compiled-per-key).

**Status:** Implemented on `unified` 28fe27b2f7 (W-100), from `trait-world-1.13`'s `facts.jl`. Owner-only functions: `next-s3` e483299622 (D-9, 2026-11-15; E-458), but for a later `public` or `export`, which ends nothing (C-130); `is_owner_only`, the flag on the binding, the scope option and the binding edge for a later `public` are mine (2026-11-15).

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
- **Two more options,** set the same way and inherited and saved alike, serve the trait language's scopes ([traits §13](traits.md#13-scopes-trait-modules)):
  - `bounded=true`: a method that is not bounded at a trait argument is refused (§6.7);
  - `no_pirates=true`: a pirate is refused by the library's definition hook.
- No option decides how an argument is compiled: the value's type does (§6.2).
- A module's other compiler options (`optimize`, `compile`, `infer`, `max_methods`) apply to its code under either policy.

**Status:** The module option implemented on `unified` beafa01b36 (W-100): `facts` and the trait options, set by `Base.Experimental.@compiler_options`, inherited by submodules, saved with the module; their consumers: §2.3 (W-100) and W-109, W-111, W-114. The options `dynamic` and `first_seen` are still built: C-112.

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

A trimmed build has no facts policy. A binary is a closed world ([facts §13.3](facts.md#133-trimmed-binaries)).
- Every method is inferred plainly.
- The image marks every module as never compiled by facts (§2.1's `never`). The binary's runtime, which does not know that its image was trimmed, then finds every method plain.
- Every static call binds its callee's address.
- An operation's call on a value known only by its trait is compiled for the members the build has ([§7.6](#76-a-closed-build)).

**Status:** Implemented on `unified` cb7f55bd35 (W-100) and bb2031f820 (the modules' mark): under `--trim` every method and top-level thunk is plain, so every CodeInstance is. Trimmed binaries of the demonstrators are built and run in E-361 ([evidence §4](../design/evidence.md#4-builds-and-binaries)).

### 2.7 Fully typed mode

```julia
Expr(:meta, :fully_typed_warn)       # a method: warn
Expr(:meta, :fully_typed_enforce)    # a method: raise
Base.Experimental.@compiler_options fully_typed=enforce   # every method of the module: off, warn, enforce
```

- **Fully typed mode** ([traits §14](traits.md#14-concreteness-and-fully-typed-mode)) is a method's flag (`Method.facts` bits 4 and 8), or its module's option (trait-option bits 16 and 32), inherited and saved as the others are. The method's own flag wins.
- **A method in the mode is compiled by facts** (§2.3): the mode is about the facts the code rests on.
- **The fault of its code at a signature,** known when inference finishes: a run-time site, in it or in a callee compiled by facts (`nortsite` cleared, §1.3). The result's type is no fault.
- **Code with a fault starts with a check:** `jl_not_fully_typed(svec(mi, level, warned, kind, rt))`, a call into the runtime that reaches the library's hook (`jl_set_fully_typed_hook`) in the latest world. Under warn it runs the hook once per check; under enforce at every run, and the hook raises. Without a hook, enforce raises Julia's error.
- **The check is never folded or removed:** the code's effects are neither consistent, nor effect-free, nor nothrow.
- **Fully typed code has no check** and pays nothing.
- **Fully typed has one definition, with the setting as its parameter** ([facts §3](facts.md#3-fact-signatures), "What is final"): every call, in the code and in what it calls, is settled in the setting. A session settles a call at a fact signature; a closed build settles every call whose targets it can list.
- **The fault is the closed build's refusal** (§7.6): the mode asks whether code is fully typed when closed. Code without a fault at a signature is what a closed build compiles from that signature with no call left to run time, and no other code. Both read one rule: a run-time site is a call that neither the caller's types nor the members resolve.
- **A call settled when closed and not in a session** (a value typed `Any` passed to a function with one method that is not owner-only) is no fault of the mode. The check's report lists such calls apart: they are the difference between fully typed when closed and fully typed in a session ([traits §14](traits.md#14-concreteness-and-fully-typed-mode)).
- **The check that answers for the build is the build's own code, run in the session:** `Compiler.closed_check(mis, world, overlay)`.
  - It infers the method instances `mis` and what they reach by a closed build's rules (§7.6), every method plainly, in the build's rounds, and runs the build's verifier over the result.
  - Its code has an owner of its own, a fresh object per check, and ends with the check. No other inference finds it, so the session's code holds none of the build's splits.
  - It asks memberships in `world`, as a build asks them in the world it compiles for.
  - `overlay` is a method table with the methods a build replaces in Base ([traits §16](traits.md#16-compiling-ahead-closed-programs)). The check's inference and its verifier look methods up through it, laid over the session's, as Julia's `OverlayMethodTable` does.
  - It returns the calls a build would refuse and each instance's caller. The library's `fully_typed` is this list, with root causes from a walk of the session's own inference.
- **The mode's hook asks that check** for the signature and raises, or warns, only where it lists a call.

**Status:** Implemented on `unified` 5f2373b2d5 (W-114): the flag and the option, the policy, the check after optimization, the hook; gate `n9_fully_typed`. The library's report and errors: [lowering §14](lowering.md#14-fully-typed-mode-concrete-parts-closed-programs). Where the mode lives (the compiler finds the fault, the library explains it): mine (2026-11-07). The result's type as no fault: `unified` 22db66e23c. The fault as exactly the closed build's refusal, by the build's own check: `unified` 381cc8b953 with TraitWorld `unified` 78a78af (W-142; E-369), with traits T-100 and T-109; the check as the build's code under an owner of its own, and its overlay: mine (2026-11-12, 2026-11-14; [decisions](../record/decisions.md) §6). One definition with the setting as its parameter: mine (2026-11-15; D-10); the report's calls settled only when closed, listed apart: Planned, with [traits T-122](traits.md#19-deviations).

---

## 3. The dependency record and the deep class

### 3.1 The record

A CodeInstance's edges name everything its code assumed:
- **dispatch edges:** facts at signatures, including "no method" and "ambiguous";
- **result edges:** an emitted call whose result type, exception type, effects or constant the caller used as a type. Nothing else is a result edge;
- **code edges:** the identity of each inlined, constant-propagated or concretely evaluated callee: the method and a digest of its lowered code;
- **binding edges:** the global bindings it reads;
- **layout identities:** the types whose fields it reads, by path and layout;
- **absence edges** and **positive memberships** it folded (§4.8, §5.6).

The backedge iterator, `verify_method`, codegen's walkers and the image writer read every kind. Targets are named by identities stable across sessions where one serves (§9).

- **A positive membership is recorded as its entry.** Where inference folds a positive answer through an entry (§4.8), or a dispatch match passes through one (§5.3), the entries the answer rests on join the record: each entry in force in the world being inferred on a `TypeName` reachable from the member (its supertypes, parameters and entries' instances) whose set reaches a set the question names. A chain of memberships records each link.
- The code's worlds start no earlier than the latest of those entries'. An entry in the record takes no backedge: the membership's method takes it (§5.6). A redeclared membership keeps its answer; one taken back deletes its method, which ends the code (§4.3).
- Validation of a loaded image's record takes an entry's worlds where the entry is in force in the session, and refuses the code where it is not (§9).
- **A dispatch edge keeps the call's signature where the call reached an instance wider than its own match:** a method compiled once at a set (§6.3) or declared `@nospecialize`, and a call of `!==`, which inference infers at its one method's `(Any, Any)` whatever the call's types. The edge names the call's signature with the instance, and so does its backedge. A method defined later invalidates the caller only where it replaces the matched method over the part of the call's signature it meets. So a caller at `Int` of `k(@nospecialize(x))`, which reaches the instance `k(::Any)`, stays valid when a method `k(::String)` is defined. The callee's own invalidation reaches the caller as through any backedge.

**Status:** On `unified` 9a601902a0 (W-100): dispatch and binding edges as Julia records them; positive memberships, the entry itself, recorded at `isa`, `<:` and dispatch matches, the code's worlds from theirs, read by image validation (E-277; gate `f7_membership_edges`), with C-51. A folded negative's edge (§4.8). Result edges told apart, code edges' digests and layout identities: C-52. A dispatch edge with the call's signature where the instance is wider: `unified` 53ec4356bf (E-336; gate `n21_callsig_backedge`), mine (2026-11-09). A call of `!==`, whose one method inference infers at `(Any, Any)`, is matched at its own signature, which its edge keeps: `next-s3` 6b3175dc9c (W-157; E-477), mine (2026-11-15).

### 3.2 G2 as a predicate

When a CodeInstance of either policy is finished, the **G2 bit** in its flags records whether it is **deep G2** ([facts §1](facts.md#term-deep-g2)):
- every dispatch edge of its record is at a fact signature;
- every callee among its edges is a CodeInstance that carries the bit.

The rest of the record needs nothing more: a binding edge, an absence edge (only a membership of its pair breaks it, by an owner or a pirate: [facts §10](facts.md#10-memberships)), a positive membership, an `invoke` edge at a declared signature. An instance whose edges are bindings only carries the bit.

**How it is decided.** A callee is finished before its callers, and its bit is final then. So the bit is decided from the record's own edges and their bits, with no walk.
- **An inference cycle** is decided as one: where every member's record passes, every member carries the bit; otherwise none does.
- **An edge names the callee's code where it exists when the caller finishes.** Where inference had no CodeInstance for a callee when it reached the call (a recursion through it, a limited inference) and the callee was finished before the caller, the edge names the CodeInstance of the policy the call reaches, valid in the caller's worlds. The backedge is the same, on the instance: a definition that changes dispatch at the callee ends the caller; of the callee's code, only the CodeInstance named does.
- **A callee named by its MethodInstance alone** (it had no code when the caller finished), outside the instance's own cycle, does not carry the bit: its backedge reaches the caller from whatever code it gets.
- **An edge that names a Method alone** (a callee whose inference gave up) names no code, and holds no backedge.
- The bit is kept with the CodeInstance in images.

**Readers.** G2's claim ([facts §2.2](facts.md#22-g2-stable-caches)), strict mode's walk ([facts §11.2](facts.md#112-strict-mode)), the image's rule for what it keeps (§9), and the counts of the evidence read the bit, and nothing else.

**Status:** The bit implemented on `unified` 8ef154476f (W-100), for code of either policy and kept in images, the edge instance made for a constant-propagated result on 427760d9e9 (gate `f4_g2_bit`, E-320). Computed for plain code too: adopted with the work plan (the user, 2026-11-06), the trade-offs review's M1. The bit as the deep class, decided at a CodeInstance's finish, a cycle as one, an absence edge counted in: `next` 7063158f42 (W-155; gate `w155/gate_deep.jl`; E-417). A callee named by its MethodInstance alone counts as outside; the edge names the callee's code where it exists when the caller finishes: `next-s3` 0a07a715ca (W-157; E-477; open issue 195 (a)), mine (2026-11-15). A positive membership's edge (the instance of the membership's method, §5.6) counted in: `next` 76ae6b0ee7 (W-160) and `next-s3` e7681dfc54 (open issue 211).

### 3.3 One compiled code per result

- **An instance's code is compiled once per result.** A CodeInstance that a compile request brings and the cache does not hold takes the code of an equivalent one in the cache: of the same instance, owner, policy and result type, valid in the request's world.
- Every entry of the instance's cache is a candidate, a compiled one first. Only where there is none is the new one cached and compiled.
- A static call binds its callee's address. A callee's invalidation invalidates its callers through their edges, as in Julia.

**Status:** Implemented on `unified` 9c6c9270f3 (E-388, E-389); without result edges and the code slot on `next` 9b6dacf5c5 (W-155; E-419). `unified` still has the slot.

---

## 4. Sets and memberships

### 4.1 Sets

- **A set** is an abstract type whose `TypeName` has the `open` bit. A trait's declaration sets it; a set is open from its declaration.
- Every other abstract type is closed, Base's and Core's included.
- **`never_member`:** a bit on Core's kinds (`DataType`, `UnionAll`, `Union`, `TypeVar`, `Module`), the builtins' types, opaque closures and the memory types. A membership of one is refused.
- A set's declared supertype is `Any` or a set. A closed abstract type is never a member of a closed abstract type through a set.
- **A set's `TypeName` carries its contract,** written once by the library at the declaration and saved with it in images ([lowering §2](lowering.md#2-trait)). The same slot holds a closed abstract type's contract, which `jl_declare_contract` writes (§7.1). A set's contract holds:
  - **the operations, each an entry** (`jl_set_contract_operations(X, ops)`, an `svec` of entries): the function; the declared signature, a tuple type with the receiver at the set's instance `X{P…}` under the set's parameters and the operation's own variables (`Tuple{typeof(kget), KVec{T}, Int} where T`); the declared result in the same variables; and the default's method where a default serves the operation, else `nothing`;
  - the declared fields, with their types and whether read-only;
  - each parameter's definition;
  - whether the set erases by default (`@default_dynamic`), a bit the method definition reads to make forwarders (§6.3).

  The compiler reads it without an edge: it never changes after the declaration.
- **An operation is no method.** An entry without a default has no method at the set: the set has a method of an operation's function only where a default serves it ([traits §4.1](traits.md#41-operations), [§4.2](traits.md#42-defaults)). A closed type's entries are made from its operations' methods at `::T`, with the result `Any` (§7.1).
- **An entry declared `::Self`,** with its receiver typed by the set, declares the set at the receiver's parameters: each member's method is checked to return the receiver type, the member's or its forwarding field's ([traits §4.4](traits.md#44-self)), which is a member there. A result that names `Self` inside another type declares none.

**Status:** Implemented on `unified` 62016706d0: the `open` bit, `never_member` (the builtins' types included), a set's supertype, the contract's slot. The contract itself is written by the library (W-106). The contract on the `TypeName`: mine (2026-11-06). The operations as entries the compiler reads, with no method for an operation without a default: Implemented (D-4, 2026-11-15; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498)): the `TypeName`'s slot `operations`, written once by `jl_set_contract_operations`. The entry's form (the signature as a tuple type) is mine (2026-11-15), and so is its slot of its own beside the declared fields (W-161).

### 4.2 Memberships

- **A membership is an immutable entry on the member's `TypeName`,** never on the set's:
  - the set;
  - the member pattern: `S`, `S{T} where T`, an abstract type, a set instance, `Type{S}`;
  - the set's instance for the pattern (`X`, `X{T}`);
  - the receiver: the member itself, its forwarding field, or none where defaults serve every operation (what keys would read, [extensions §1.2](extensions.md#12-the-key-as-a-type));
  - `min_world` and `max_world`;
  - the declaring module;
  - the forwarding field, if any.
- A `TypeName`'s list of entries is replaced copy-on-write; readers take no lock.
- `jl_declare_membership(member, set_instance, declarer, by, receiver)` declares one. The library checks ownership and the contract first ([traits §5.10](traits.md#510-checks)).
- `jl_delete_membership(member, set_instance, deleter)` takes one back (§4.3). The library checks ownership first ([traits §5.13](traits.md#513-taking-a-membership-back)).
- **A pattern's variable bounded by a `Union` of types** (`I where {I <: Base.BitInteger}`) is declared as one entry per type of the union.
- **`struct S <: X`** with a set `X` makes `X` the declared supertype of `S`, as for any abstract type: subtyping answers `S <: X` by the chain. The library's `@implement X S`, which the language requires after it, declares an entry like any membership's, recording the receiver ([lowering §3](lowering.md#3-implement)). It changes no subtype answer; the readers of the entry lists see the membership: images, the member hook (§10.4), the ambiguity report (§5.4), the candidates (§7.2).

**Status:** Implemented on `unified` 62016706d0, but for a pattern variable bounded by a `Union`, which the library declares per type (W-106).

### 4.3 Worlds

- A membership is declared as a method is inserted: under the world counter's lock, the entry gets `min_world = counter + 1`, is published, and the counter advances.
- **Strict mode's check** runs between the entry's publication and the advance: the ambiguity report (§5.4) is asked for its findings in the entry's world. Under the lock nothing else can enter that world, so it is asked before the counter reaches it. On a finding the entry is **retired before it begins** (`max_world = counter`): live in no world, never removed from its lists, which readers walk without a lock. A redeclaration's old entries are in force again, the counter does not advance, and the declaration throws. The set's candidates and the image's list of memberships take the entry only once the check passes.
- A type whose only entry is retired keeps a non-empty list: the presence tests that read the list's length stay conservative.
- The library's declaration is followed by `Expr(:latestworld)`, so the declaring code sees its own membership.
- A task in an older world does not see it.
- **An entry ends as a method's deletion ends a method.** It ends in two ways, and is never removed from its lists, which readers walk without a lock; a reader skips an entry not live in its world.
  - A redeclared membership gives the old entry a `max_world`, declares a new one, and invalidates the code compiled for the old membership and the callers that folded against it.
  - **A membership taken back** (`jl_delete_membership`): under the world counter's lock its entry gets `max_world = counter` and its method (§5.6) is deleted in the same world; the walk for the removal runs (§5.5); then the counter advances. The entry leaves its set's candidate index and the image's list of memberships, and the member hook's kept answers for the pair (§10.4) go with it. A pattern's entry ends every member it made.
  - A trait's membership in its supertraits and `Dynamic{X}`'s are the trait's declaration, and a member by its definition is its type's: none is taken back alone ([traits §5.13](traits.md#513-taking-a-membership-back)).
- **`Callable`'s memberships** are entries like any set's (§7.4): every `Function` by Core's entry.

**Status:** Implemented on `unified` 62016706d0; strict mode's check and the retired entry on `unified` 0bb8f38830 (E-343). A membership taken back: `next-s3` 213c759370 (the plan's D-13, 2026-11-15; E-459); the mechanism (the entry ended and its method deleted in one world, the walk for the removal) is mine (2026-11-15).

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
- **A membership adds subtype answers, never type equalities.** Inside an invariant parameter, two types are equal where they are equal by their declared structure: the equality test consults no entry. So `Vector{Union{X, S}}` and `Vector{X}` are two types in every world, whether or not `S` is a member of `X`.
  - A variable's bound is a subtype question: `Vector{<:X}` takes both, once `S` joins.
  - `<:`, `isa`, `==`, intersection and dispatch read the one rule, at a concrete container type and at an abstract one (`AbstractVector{X}`), in code compiled before a membership and after it. So a test compiled before and the same test asked fresh agree.
  - The membership's walk replays no method that names the set only as an invariant parameter (§5.5): no type under it changes.

**Status:** Implemented on `unified` 62016706d0. No type equality from a membership: `next-s3` e967266d9e (the plan's D-11, 2026-11-15; gate `experiments/unification/w155b/gate_d11.jl`, E-456).

### 4.6 One instance per member

A membership that would give a member a second instance of a set, differing in a parameter that is not an input, is refused at `jl_declare_membership`. The runtime checks it: exactly for a concrete member; for a pattern, by intersecting it with each pattern that already reaches the set. The library reports the refusal as `ImplementError`.
- **The runtime knows a set's inputs:** the library writes them once at the declaration, before the set has a member (`jl_set_input_params(X, mask)`, a bit for each of the first eight parameters, on the set's `TypeName`; images keep it).
- The check asks the member against the set at the new instance's input values, its other parameters free. A redeclaration ends only the entry at the same input values.
- **An image's membership at activation** is treated as a declaration: a second instance is refused with a warning, and an older entry in force for the same member, set and inputs ends where the activated one begins. Two images that declare one membership leave one entry in force, the later image's.

**Status:** Implemented on `unified` 62016706d0 for a concrete member, a set's inputs on `unified` 350c5b1c59 (gate `n10_inputs`), an image's membership at activation on 07c0bee2a2, ending an older entry on 9f8d7d7c48 (gate `n12_image_instances`, E-348); a pattern, against the entries at the set and at the sets that join it, on edc2653e43 (gate `n10_inputs`, E-321).

### 4.7 Three layers

Questions about open sets are answered in three layers:
- **`<:` and `isa`** read the entries: the answer in the current world.
- **`jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint` and the type cache** stay exact in the current world: a known member keeps the exact result; a concrete non-member gives `Union{}`; an abstract type that no entry relates to the set meets it as their intersection `All{X, T}` (§4.9): the members of `X` below `T`, whenever they are declared. Dispatch's match construction and the inliner's union split see only members. A concrete type no entry of whose chain can reach the set is obviously disjoint from it, by the reachability of §4.5.
- **`jl_could_join(S, X)`** answers whether `S` could become a member of `X`. Inference's lattice uses it, to know which negatives need an edge (§4.8); dispatch's match construction does not.

**Status:** Implemented on `unified` 62016706d0; a concrete non-member's disjointness by reachability 88daaca7fe; the meet of a set and an abstract type as `All{X, T}` 8a9144928e (W-107; mine, 2026-11-07).

### 4.8 Negatives fold with an edge; positives through entries

- `has_open_set(t)` is true when `t`, a parameter of `t`, a component of a union or intersection in `t` is an open set (or, with keys, a key: [extensions §1.2](extensions.md#12-the-key-as-a-type)); it is cached on the type object. `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the `hasintersect` sites and `Conditional` refinement consult it before folding a negative.
- **A negative answer about a type and a set folds where it holds in the world, with an edge.** For a concrete type `S` and a set `X` declared by the library, "`S` is not an `X`" is folded, and the code records an absence edge at the pair (§5.6). A membership of the pair declared later invalidates that code, as a method definition invalidates a call that found no method ([traits §3.4](traits.md#34-open-and-closed), [facts §10](facts.md#10-memberships)). An image's code with such an edge is checked when the image is validated (§9).
  - It holds wherever the code is compiled: while a declarer of the pair is still loading, and for a type or set of `Main`.
  - **No edge is needed** for a closed abstract type or a type with the `never_member` bit: their answer never changes.
- **A test proves its own positive.** In the branch where `x isa X` holds, `x` is known as an `X`, where `X` is under what was known of `x` (a value typed `Any`, or by a supertype of the set). The test ran, so no edge is needed and no world is raised. Nothing else is refined: the other branch keeps what was known, and a type that could still join `X` is not dropped from the true branch. So a result annotation at a trait, `f(…)::X`, gives callers a result known as `X`.
- **A positive answer folds only through an entry,** with an edge to the membership's method (§5.6), and the fold raises the CodeInstance's `min_world` to the entry's. So a task in an older world never runs code that assumed the membership.
- **Code generation decides the positive answers inference folded.** Where compiled code tests a value whose type inference knows, a concrete member `S`, against a set `X` that `S` is under through an entry, the test is decided when the code is compiled. That holds for `isa`, `<:` of constant types, a `typeassert`, the field test of `new` (a struct's field typed by the set, the box's `object` among them), and a store into a field or an element typed by the set (`setfield!`, `memoryrefset!`: storage typed by the trait). Inference records the edge to the membership's method for each such test, as for a folded `isa`, so the code rests on the membership as any fold does: a membership taken back ends it (§5.6).
  - **The proof travels with the statement.** Inference folds `isa` and `<:` to constants. For `new`, a store and a `typeassert` it flags the statement whose type tests it proved (`IR_FLAG_TYPES_PROVEN`, beside the effect flags), each test through an entry with the entry recorded; inlining keeps the flag with the statement. Code generation decides a test through an entry only in a statement that carries it. A store's flag is not its `nothrow`: a store may still throw at its bounds.
  - **So the box a forwarder makes at a member's type tests nothing when it runs** (§6.3, [traits §7.8](traits.md#78-erasing-by-default-the-forwarder)). Where the box does not escape, code generation passes it by reference, and it needs no heap of its own (E-407).
  - A value whose type is only known as `X`, or wider, is tested when it runs, as Julia tests a value against any abstract type.
- **An intersection no type is in folds the same way.** For an abstract type `S` that is not a set and a set `X`, the pair (`S`, `X`) is relied on where `All{S, X}` is unmet in the world (§5.4). Its absence edge is met once a type under `S` is a member of `X`, so such a membership invalidates the code that relied on it.
  - Inference folds `isa` of a value of `X` against `S` to `false`.
  - Dispatch's lookup drops a method match whose argument is met only at that intersection, even one more specific than every covering match, and reports the pair's absence edge, which inference records (§5.4). So no instance is compiled at `All{S, X}`: a call `describe(t)` at `t::ColTable` matches `describe(::ColTable)` alone, not `describe(::AbstractString)`.
  - A component under a `where` (`All{AbstractVector{T}, X} where T`) is met where a member is under the component for some value of its variable.
- **Core and Base's own negatives.** Code compiled while Base is built at such an intersection is invalidated, with its callers, at the end of Base's build, in a new world; the image's later code drops the match.

**Status:** Implemented on `unified` 62016706d0 for the lattice's sites; the positive fold through an entry, with its world and its record (§3.1), on `unified` 9a601902a0 (W-100), with C-51. A negative folded with an edge: `unified` bf447db25e (W-129 (a)) for a set that opted in, 80aa919bed, 1b2f0a9e1e and a19d937eaa for every set, wherever the code is compiled (W-140); with C-77; gates `n18_closed_after_load`, `n20_unmet_lookup`, `n2_open_abstract`. The end of Base's build: `unified` b133374e9d (W-129 (b)), mine (2026-11-09). An intersection no type is in: `unified` 1906196731 (E-334, open issue 169 (a)), with C-79; mine (2026-11-09); a component under a `where`: a19d937eaa (E-365). The edges as the method table's own (§5.6): `unified` 90fb8ff97a, 8b4fde6e84 (W-141; E-367). A test's own positive: `unified` 86deee2f98 (gate `n31_isa_narrows`; E-373), mine (2026-11-14). The rule: the user (2026-11-11; [decisions](../record/decisions.md) §4). A positive decided at code generation (the user, 2026-11-15: "Yes please. Build the compiler for P1 and be cogniszent of finding principled ways of making the design fast."): `new`'s field test on `next` 8c2d3a5457, the statement's flag for `new`, a store and a `typeassert` on 5b1900641f (W-160 (a); E-436, E-441; `w160/check/new_fold.jl`, `w160/check/stores.jl`). The store's test and the statement's flag: mine (2026-11-15).

### 4.9 Intersections

```julia
Core.All{X, Y}
```

- **`All{X, Y, …}` is an intersection type,** the dual of `Union`:
  - `S <: All{X, Y}` when `S <: X` and `S <: Y`;
  - `All{X, Y} <: Z` when some component is a subtype of `Z`, and `<: All{Z, W}` when it is a subtype of each.
- **Normal form:** components flattened, sorted by the order `Union` uses, deduplicated; a component that is a subtype of another by declared supertypes absorbs it; two closed types with no common subtype give `Union{}`.
- **Normal forms read declared supertypes only.** A membership never absorbs a component of an `All` or a `Union`: `Union{S, X}` stays as written where `S` is a member of `X` by an entry. So a type expression gives the same type object in every world, and two types inside an invariant parameter are equal in every world or in none (§4.5).
- `jl_type_intersection` of two sets, or of a set and an abstract type, that no entry relates is `All{X, T}`, with their known common members' exactness kept (§4.7). A type meets an intersection as the intersection of its meets with each component.
- `type_morespecific_` ranks `All{X, Y}` above each component, and an intersection with a closed component as a closed type against an open set (§5.2).
- **At an argument typed by an intersection,** the split's candidates are the first component's that are members of every component (§7.2).
- The negative-fold rule (§4.8) treats each component.
- It takes any number of components: `All{X, Y, Z, …}`.
- **The encoding.** `All{X, Y}` is the abstract type `Core.All{Tuple{X, Y}}`, built in its normal form; `Core.All{Tuple{X, Y}}` written so is the same type. The wrapper `Core.All` is an artefact of the encoding, not a type to write. No code reads an intersection's name, supertype or parameter as those of an ordinary type: every site that does (the typemap's names, the fold gates, type instantiation, the variable-occurrence walks) has a branch for it.
- **In the normal form, further:** a variable as a component is in a covariant position, and the diagonal rule applies to it; a `Union` component distributes (`All{Union{A, B}, Y}` is `Union{All{A, Y}, All{B, Y}}`); a component that is itself an intersection under a `UnionAll` is flattened; two closed components whose intersection Julia computes exactly are replaced by it.
- **Its name** is not exported by `Core` ([open issue 148](../open-issues.md#2-design)).

**Status:** Implemented on `unified` 8a9144928e (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}"), but for the split's candidates (W-109). The encoding and the further rules: mine (2026-11-07, after [the review of the encoding](../../attic/writeup/reviews/2026-11-07-all-representation.md)). Normal forms by declared supertypes, and candidates at an intersection: mine (2026-11-06, the reviews of the draft). The equality inside an invariant parameter by declared structure: `next-s3` e967266d9e (D-11; E-456).

### 4.10 Type values

A type value is a member of a set only by an entry whose pattern is `Type{S}`. Such an entry is kept on `S`'s `TypeName`, marked as being for the type value, not on `Type`'s. `jl_isa`'s branch for a type value and `intersect` consult such entries. An entry for `S` answers `S <: X`, never `S isa X`.
- A kind of type object (`DataType`, `UnionAll`, `Union`) meets a set that takes a type value, by its own entry or by one of a set that joins it. So a call at an argument typed by a kind finds the set's method. The membership that first gives the set a type value invalidates the callers at a kind, as any membership does (§5.5).

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
- **A membership has worlds, as a method has.** Positive answers fold through their entry, with an edge to its method; negative ones with an edge (§4.8).
- **A membership invalidates as a method does:** the callers whose selection it changes, and the code that folded its absence (§5.5). Taken back, it invalidates as a method's deletion does: the callers whose selection at the member changes, and the code that folded its positive (§5.5, §5.6).
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

**Status:** Implemented on `unified` 29035cab11; the matches at an abstract query 8a9144928e (W-107). At a query in the latest world in which an entry's visibility changed, or later, a match's valid worlds start at that world, with no walk of the entries: exact at their end, narrower at their start (`unified` 89b3bcff81 and d04256a442, E-300, E-301). A match through `Callable` is a match through its entries, as at any set (`next` eaa19da272, [§7.4](#74-callables-call)).

### 5.4 The ambiguity report at a membership

At `jl_declare_membership`, the report asks which methods the membership makes applicable at the member, and whether any of them is ambiguous there. A warning names each such method, the methods it is tied with and the joint method's signature. Strict mode makes it an error: the report's findings refuse the membership (§4.3).
- **The methods asked:** each method at the new set, and at each set the new set joins by entries live in the entry's world. A retired entry, or an image's entry refused at activation, is no set of the member.
- **The call types:** the method's signature with the member in place of each argument that one of those sets types and that the member is under: as the argument's type, an arm of its union, a component of `All{X, Y}` or a variable's bound. The method's other arguments stay, so the question is asked at the method's own arity.
- **The tied methods:** the matches at those call types, read from the method table, never a dispatch cache, since a cache entry made before the membership may still answer for the call types. A match is tied with the method as `Base.isambiguous` decides: neither is more specific, the two meet at call types that are not unmet (below), and no match more specific than both covers those types. The other method may be at another set of the member, at a set the member is in through its declared supertype, at a closed declared supertype, or at `Any`: `g(::X, ::Int)` against `g(::A, ::Integer)` at `S <: A`, or `h(::X, ::Integer)` against `h(::Any, ::Int)`. A method at a closed supertype alone (`f(::A)` against `f(::X)`) is no tie: it is more specific (§5.2).
- **Through the member only:** a match counts where it covers the member itself. At each replaced argument its type is closed, or the member is under it. So a set joining a set, or a pattern member, is not reported for a method at an unrelated set that it meets only at an intersection: the types there are not this membership's.
- **One warning per method asked,** with every method tied with it. The joint method's signature is the intersection of all their signatures, where sets meet as `All{X, Y}` (§4.9). A tie is named once, at the first of its methods asked.
- **The report names the ambiguities the membership creates:** a method that applied at the call types in the world before the entry is not asked. So a later membership of an ambiguous member, a redeclaration among them, is neither warned about nor refused under strict mode; and for `struct S <: X`, where `X`'s methods apply at `S` by the definition, the membership in a second trait `Y` is the one reported, in whatever order the two are declared.
- **The world:** the search asks the entry's world, which strict mode's check asks before the counter reaches it.
- **The member as an argument only:** a set inside another type's parameter (`f(::Vector{<:X})`) is not replaced. A tie that arises only at a type with the member as its parameter (`Vector{S}`) is raised at the call, as Julia raises any ambiguity; the report does not enumerate the types built from the member.
- **An intersection no type is in.** An argument `All{X, Y, …}` is *unmet* in a world where no type of that world is in every component. Nominal supertypes form a tree, so a common type is in some set component by an entry: the entries live in that world at the set components (and at the sets that join them) are read (`jl_has_unmet_argument`). A `Callable` component is met by every function (§7.4). A `Vararg` tail whose length is not a positive constant is met by its empty tail.
- **Dispatch's lookup:** where every unmet argument's pair is one a negative is folded for (§4.8), the lookup drops the match met only there, also one that would win, at any number of matches, before the matches are sorted and their ambiguity computed, and returns the pairs' absence edges (`jl_matching_methods_cells`). Inference carries them on the lookup's result and records them with the call, so a membership that meets the intersection invalidates the caller.
- **Julia's ambiguity reflection** (`Base.isambiguous`, `detect_ambiguities`) asks the same question in the query's world: an argument met only as an unmet intersection has no value there, as an argument met only as `Union{}` has none. So two methods at a set and at a type no member of it relates (`describe(::AbstractString)` and `describe(::ColTable)`) are not reported until a membership makes them meet, and then by this report.

**Status:** Implemented on `unified` 0d529d33a9 for a concrete member, the joint method at `All{X, Y}` 8a9144928e (W-107), a pattern member at the call types both methods reach 264b7f959f (gate `m2_ambiguity_arity`, E-320). Strict mode's error with strict mode (W-114). The reflection in the query's world on `unified` b133374e9d (`has_unmet_intersection`, `base/reflection.jl`; E-330); an intersection unmet by the world's entries on `unified` 43c222c751 (gate `n20_unmet_lookup`, E-331); dispatch's lookup dropping the match with its absence edges, on `unified` 999777ab77 (gate `n20_unmet_lookup`, E-341), at every set on a19d937eaa (W-140): mine (2026-11-09, [the performance review](../../attic/writeup/reviews/2026-11-09-performance-day.md) H2; [the plan](../../attic/writeup/plans/2026-11-09-c82-unmet-match-lookup.md)). Strict mode's refusal, the search without caches and the live entries only on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343); the ambiguities a membership creates only on `unified` 2ee5569252 (gate `m2_ambiguity_predates`, E-346); each method the membership makes applicable asked against the method table at the member on `unified` 53d28eea68 (gate `m2_ambiguity_declared_super`, E-347, W-132): the search through the member only and one warning per method are mine (2026-11-10, [the plan](../../attic/writeup/plans/2026-11-10-c78-report-at-declared-supertypes.md) and [its review](../../attic/writeup/reviews/2026-11-10-plan-review-c78.md)); the tie with a method at `Any` reported like any other: decided under the user's instruction of 2026-11-10 ([decisions](../record/decisions.md) §5).

### 5.5 A membership invalidates as a method does

- **The walk.** A membership of `S` in `X` replays each method whose signature names `X`, or a set `X` joins: the method is treated as if it were inserted at `S` in place of the set (`jl_membership_dispatch_walk`). The methods are found through the set-to-methods index (§5.1), which lists a method under each set its signature names, a variable's bound included (`f(c::C) where C <: X{T}`).
- **What it invalidates:** the CodeInstances whose selected method changes at the new member, through the dispatch edges they hold, as an insertion does. A caller whose arm at `S` was pruned for want of a method is among them. A selection that becomes ambiguous changes too.
- **What it lowers:** the `max_world` of each leaf-cache and typemap-cache entry whose selected method changes, so the next call looks up again.
- **The replayed method is the one that now applies,** not one that matched before the membership: its own entry is live in the table and is passed over.
- **A caller holds no guard and no absence edge for a call:** its ordinary dispatch edge is what the walk reads, in a session and in a package image alike. So the code of an image compiled where no method at a set existed is reached as the session's code is.
- **A method at a set defined later** invalidates as any method does: the callers at types that are members. A caller at a type that is no member stays valid, and the membership reaches it when the type joins.
- **A membership adds no method.** A call that matched the replayed method in the world before the membership has the same matches after it: a call at `Any`, or at an abstract argument that met the set. The code that inferred such a call stays valid, and so does the instance of another method compiled at such a signature. A call at the member's own type, or at a union of types that were no members, did not match it: its caller is invalidated.
- **A method that names the set only as an invariant parameter** (`total(v::Vector{Shape})`) is not replayed: whoever joins `Shape`, only `Vector{Shape}` is under it. Where the set bounds a variable (`Vector{<:Shape}`), stands in a tuple or under a union, the method is replayed.
- **The replay's signature is the method's with the member in the set's place,** wherever one signature says what the membership adds:
  - at an argument, under a union, in a tuple's component, in an intersection `All{…}`;
  - in the bound that a type declares for its own parameter (`struct Cell{C<:Shape}`, and a method at `Cell` or `Type{<:Cell}`). No `Cell` at the member could be made before the membership, so no code and no cache entry is at one.
  - So the instances and callers at the other members are kept.
- **Where one signature with the member does not say what the membership adds, the replay's signature is the method's own:**
  - in a bound that the signature sets inside a parameter (`Box{<:X}`, and the kept forms `Union{Dynamic{<:X}, Compiled{<:X}}`, §6.3): `Box{Union{S, T}}` could be made before the membership and is under it only now;
  - in several places below a position's top (`g(a::Box{<:X}, b::Box{<:X})`): a new call has the member in any one of them.
  - Every type the membership adds is under the method's own signature. The replay passes over the method's own entry, and a call that matched the method before keeps its code (above), so the method's own instances and their callers stay.
- **So a new type that joins invalidates nothing:** no call was compiled at it, and the calls at wider signatures matched the trait's methods before.
- **A task in an older world keeps the old answer:** the invalidated code and the lowered entries end at the world before the membership.
- **Taken back** (§4.3), a membership runs the same walk, as a method's deletion at the member:
  - each method at the set, or at a set it joins, is replayed at the member as if deleted there: the CodeInstances whose selection at the member changes are invalidated through their dispatch edges, and the cache entries that selected such a method at the member are lowered;
  - the instances of those methods compiled at the member (a default's method compiled for `Circle`) end, with their callers;
  - the code that folded the positive ends through its edge to the membership's method, which is deleted (§5.6);
  - a call at the member that selected the member's own method keeps it: its selection does not change. So does a split compiled with the member among its branches, where its branch is the member's own method; a branch served by a method at the set ends with that method's instance at the member.
  - A pattern's members end together, each replayed as one member is.

**Status:** Implemented on `unified` 29035cab11 for the walk and the caches; its cost in proportion to the replayed method's own function, the member substituted at a parametric set, on `unified` aa997b2180 (W-123); a selection made ambiguous at a member called before, on `unified` 0bb8f38830 (gate `m2_ambiguity_called_before`, E-343). The walk invalidating code, a method under its variable's bound, the replayed method passed over at a pruned arm: `unified` a2ea2aff32; what matched before kept, an invariant parameter not replayed: a19d937eaa (W-140; E-365). The replay at the method's own signature: `next` 75a7f1795b (W-160, E-444). Gates `m2_dispatch_worlds`, `m2_stale_caller`, `n7_guards`, `n11_late_shadow`, `m2_parametric_replay`, `n25_image_before_set_method`, `n27_invariant_parameter`, `n28_wide_caller`. The rule: the user (2026-11-11); that a call records no absence edge and the walk does the work, and what the walk leaves valid: mine (2026-11-11; [decisions](../record/decisions.md) §4). With C-88.

### 5.6 The membership's method and the edges

- **Each membership has a method** of `Core.implements`, a function of the runtime. The runtime makes the method when it accepts the membership, in the declarer's module, from the entry's world. No program calls the function or defines a method of it; a method of it is deleted only when its membership is taken back (§4.3).
  - Its signature is `(Type{X}, Type{S})` for the instance `X` and the member `S`; under the pattern's variables for a family; `Type{<:S}` for an abstract member.
  - The entry is the membership's record (§4.2). The method is what compiled code's edges rest on.
- **An absence edge** is what code that folded a pair's negative records (§4.8): the signature `(Type{<:X}, Type{S})` with no method, `Type{<:S}` for an abstract `S`. Julia keeps it as it keeps a call that found no method. A membership's method that meets the signature invalidates the code from its world on. So a membership in a subtrait, of a family, or of a type under an abstract `S` meets it by Julia's type intersection.
- **A folded positive** records an edge to the method's instance, as a call to a method does.
- **A refused membership has no method in force:** at a declaration none is added; at an image's load the method the image brought is live in no world (§9).
- **In an image** both edges are saved and validated with the code, as its edges to methods are (§9).
- A call's selection needs no absence edge (§5.5).
- **A membership taken back deletes its method** in the world its entry ends (§4.3). The code that folded the positive holds an edge to the method's instance and ends with it, as callers of a deleted method end. Code compiled afterwards that folds the pair's negative records the absence edge again. A loaded image's code that relied on the membership fails validation on that edge (§9).

**Status:** Implemented on `unified` 90fb8ff97a, b66cdc66f2 and 8b4fde6e84 (W-141; E-367). Gates `n29_membership_method`, `n18_closed_after_load`, `n20_unmet_lookup`, `n12_image_instances`. The mechanism kept as the implementation, a membership defined as behaving as a method does: the user (2026-11-12; [decisions](../record/decisions.md) §4). With open issue 180. Its method deleted when the membership is taken back: `next-s3` 213c759370 (D-13, E-459).

---

## 6. The kept forms and the definition-time check
<a id="6-keys-and-the-attribute"></a>
<a id="6-keys-the-kept-forms-and-the-definition-time-check"></a>

### 6.1 The key as a type

`Core.TraitKey{X, R, F}`, code compiled per key, is an optional extension: [extensions §1.2](extensions.md#12-the-key-as-a-type). No interface of this reference depends on it.

**Status:** Optional (W-110; the plan's D-14, 2026-11-15).

### 6.2 How an argument is compiled
<a id="62-compilation-signatures"></a>

- **An argument is compiled as Julia compiles it:** for the value's type, or at the declared type where the method says `@nospecialize`. Nothing beside the values decides which instance runs. `jl_apply_generic`, its caches and the interpreter are Julia's.
- **A box's type is one per set instance,** `Core.Dynamic{X{p…}}`: code for it is compiled once for every member, and its operations dispatch on the held object (§7.1, §7.2).
- **A wrapper's type is one per object type,** `Core.Compiled{T}`: code for it is compiled for `T`, and its operations call the object's own methods, statically.
- **An argument at a set declared `@nospecialize`** is compiled once at the declared set instance, the object passed as itself. Its operations split (§7.2); passing it on is a run-time site.
- **A `where` variable bounded by a set** is the type of the value given: a member's, a box's or a wrapper's.
- Per key: an optional extension ([extensions §1.2](extensions.md#12-the-key-as-a-type)).

**Status:** Julia's rule: Implemented. Not in force on the build: Julia resolves an attribute at each argument typed by a set (C-112), so `@nospecialize` there takes the attribute's run-time path (E-402: 829 ns a call). The kept forms: §6.9.

### 6.3 The forwarders
<a id="63-the-attribute-at-a-call"></a>

**A method at a set that erases by default is entered as two methods, made where it is defined** ([traits §7.8](traits.md#78-erasing-by-default-the-forwarder)).
- **Which sets erase:** a set whose contract carries the erasing bit (§4.1), which `@default_dynamic` writes; `Core.Callable`, whose bit Core's build sets; an intersection with such a component.
- **Where:** in the method's definition, from its evaluated signature (`jl_method_def`), as lowering makes a positional default's second method from the syntax. Where the signature names a set, the runtime asks the library's expansion hook (§10.1), which reads the contracts and answers the methods the definition makes; each is then defined as written, the definition hooks run for each. At each positional argument the hook asks whether the declared type is such a set with its parameters given, an intersection with such a component, or a `where` variable bounded by one. A set whose parameters the signature leaves open (a bare parametric set, a parameter `<: B`) erases too: the forwarder takes the open variables as static parameters of its own, the same signature (`c::Column{T} where T`), so that dispatch binds them from the member's membership; the method as written keeps the type as written at the kept forms. Not where an open parameter is an input of the set (`Callable`'s, an `@input`): the member does not fix it. Nor does a `where` variable that another argument names (a struct's own constructor, `T{F}(f::F)`: the call fixes it to the member's type), nor a `Callable{A, S}` whose variables only that argument would bind (a function's type fixes none).
- **The method as written** is entered with each such argument at `Union{Core.Dynamic{<:X}, Core.Compiled{<:X}}`, and a `where` variable's bound replaced the same way.
- **Its forwarder,** one per positional arity that holds such an argument, is a method at the declared types. Its body boxes each plain one at its set by `new`, passes a kept form as it is, and calls the function, the keywords passed on whole. The box is made in the forwarder's body, not by a call: in code compiled by facts a call whose argument is typed by the set is a run-time site.
  - With one such argument whose set's parameters the other arguments fix, the argument is `@nospecialize`: the forwarder is compiled once. Where only the member's own type fixes a parameter (`ip::IndexProvider{I}`, a parameter left open), or where several arguments erase, it is compiled per member type, so that the box's parameters are known and the call is at concrete types.
  - It is entered after the method as written, and records that method, so that reflection shows one definition, and redefining or deleting the method takes its forwarders with it.
  - It is less specific than the method as written at each such argument, so a kept form never reaches it. Dispatch is Julia's.
- **At a `Callable{A, S}` argument** the hook answers, beside the forwarder, an entry at the wrapper's form (`Compiled{Z} where Z <: Callable{A, S}`): it tests the wrapper's object (§7.4) and invokes the method as written.
- **Not forwarded:** a method `@trait` makes (a default, a kept form's forwarding method), which carries `Expr(:meta, :no_forwarder)` ([lowering §2](lowering.md#2-trait)).
- Images keep both methods, as they keep a positional default's.

**What the rule lets the compiler do less.** Consequences, not promises of inlining:
- **The method as written is compiled once per set instance** for every box, and per object type for a wrapper. A new member compiles none of it.
- **The forwarder's box tests no membership when it runs.** In the forwarder's code at its declared type, the box's field test is decided by the argument's declared type. Where the forwarder's code is compiled for a member's type, inlined into a caller that knows it, the test is decided by the membership with an edge (§4.8). Where the box does not escape, it needs no heap of its own (E-407).
- **The definition-time check reads the instance of the method as written at the box** (§6.7): the instance every box runs, inferred once.

**Status:** Implemented (the plan's D-1; the user, 2026-11-15; [decisions](../record/decisions.md) §3; W-160 (b)): the expansion hook on `next` 8b1ec88a56, the library's expansion in TraitWorld `unified` 21ae901, d537141 and 2bf59b9, `:no_forwarder` in 21ae901; with C-111 for the forwarder's record of its method. The place, the method's definition from its evaluated signature; the forwarder's record of its method; `:no_forwarder`: mine (2026-11-15). The library's hook, the box in the body, the forwarder compiled per member type where the member fixes the set's parameters or several arguments erase, and the arguments not boxed: mine (2026-11-15, W-160). A set's parameters left open lifted into the forwarder's: TraitWorld `unified` fb67ac1 (open issue 204, E-497), mine (2026-11-15).

### 6.4 Calls from code compiled per key

An optional extension, with keys: [extensions §1.3](extensions.md#13-calls-from-code-compiled-per-key).

### 6.5 The calling convention

An optional extension, with keys: [extensions §1.4](extensions.md#14-the-calling-convention).

### 6.6 The boxed adapter

An optional extension, with keys: [extensions §1.5](extensions.md#15-the-boxed-adapter).

### 6.7 The definition-time check

- **The check reads one instance: the method's at the box** ([traits §7.3](traits.md#73-bounded-methods)). Its signature has `Core.Dynamic{X}` at each argument at a set `X` (a set, an intersection, a kept form, a `where` variable bounded by one), and a stand-in where a variable is left free. It is inferred and optimized by the native interpreter, under the method's policy, and cached with its edges: it is the instance a box's call runs, and an image keeps it as code.
- **What it reads:** each call in that optimized code that takes a value at the box (the box, or a value whose type is a set instance) and finds no method, directly or below a call that only throws (each callee read at its call's argument types), or only throws. Each is reported at the outermost frame of the debug information that lies in the method: the line that passes the value.
- **No interpreter of its own, no record kept apart, no list of exempt forms.** The instance's record is the check's record: its edges are what a later definition ends, as for any code.
- **Under the `bounded` option** of the method's module or the method itself, a fault raises `TraitUseError` at the method's definition, from the definition hook (§10.1). A method marked `@unbounded` (`Expr(:meta, :bounded, false)`) is exempt.
- A method whose body names a global not yet defined, or whose only faults are calls of its module's own functions with no method yet, is read again at a definition of that name, and at last at its module's end (§10.1).
- **It is Julia's own inference,** run where the method is defined in the latest world; the compiler code it runs is the system image's, which no package's method ends.
- **What the rule lets the compiler do less:** the check is the compile the box's first call needs, done once. An edit infers the edited method's instance at the box, and nothing else again ([traits §11.2](traits.md#112-definition-checking)).
- **A member's check, the same way** ([traits §5.10](traits.md#510-checks)): the serving methods' instances at the member, inferred by the native interpreter and kept with their edges; validated with an image at its load. A definition that would end one is found by the walk over backedges strict mode runs ([facts §11.2](facts.md#112-strict-mode)), and judged by inferring that call again with it before it is visible (§10.1).

**Status:** Implemented (the plan's D-3, 2026-11-15; [decisions](../record/decisions.md) §2; W-160 (c)), with C-115: the library reads the method's instance at the box from Julia's cache (TraitWorld `unified` 9c0912b), and a membership's walk keeps it (`next` 75a7f1795b, §5.5); E-440, E-444. A member's check as its instances: [traits T-129](traits.md#19-deviations). The `bounded` option: the user, 2026-11-06, Q2 (a). The check's place in the latest world: mine (2026-11-14; E-391).

### 6.8 A declared result on `Method`

- Lowering records `f(…)::RT` as the method's declared result, where `RT` is a type when the method is defined: built from constant globals, a module's constant bindings (`M.T`), literals and the method's static parameters (`Vector{T}`, `Union{Int, Nothing}`, `Vector{<:Real}`, `DataFrames.DataFrame`). An `RT` computed from the arguments (`::typeof(x)`) or read from a global that is not constant records none. The record does not claim to cover every member. Inference may read it as an upper bound, since the body asserts it.
- **An operation's declared result is no method's:** it is its entry's in the set's contract (§4.1), which covers every member, since each member's serving method is checked to infer within it ([traits §5.10](traits.md#510-checks)). §7 reads the entry. A default's method at the set carries its own declared result as any method's `f(…)::RT` does.

**Status:** Lowering's record of `f(…)::RT` implemented on `unified` 0ba6317994 and 523214899f (a module's binding) (lowering's `declared_result` meta, evaluated by `jl_method_set_source`), gate `n16_declared_result`. The record's scope (a type at the definition) is mine (2026-11-09). An operation's declared result read from its contract entry, not from a method at the set with a flag: Implemented (D-4; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498)). `Method.declared_covers` stays in the layout with no reader.

### 6.9 The kept forms in `Core`
<a id="69-casts-and-keep"></a>

```julia
struct Dynamic{X};  object::X; end      # the box
struct Compiled{T}; object::T; end      # the wrapper
```

- **Both are ordinary structs of `Core`,** with no rule of subtyping. Their memberships are the library's: each `@trait X` declares the families `Dynamic{Z} where {Z <: X}` and `Compiled{Z} where {Z <: X}` members of `X`, forwarding by `object` ([lowering §2](lowering.md#2-trait), [§7](lowering.md#7-dynamicx-and-compiledt)). `Core` defines them so that a forwarder made where a method is defined (§6.3) names them.
- **`Core.Dynamic{X}(x)`** holds a member of `X`, `X` a set instance with its parameters or an intersection of such. A bare parametric set raises `ArgumentError`; a value that is not a member raises `TypeError`, by the field test of `new` (§4.8).
  - A box of `X` is itself. A box of a subset of `X` gives its object boxed at `X`. A wrapper gives its object boxed.
- **`Core.Compiled{T}(x)`** holds `x` at its own type. A box gives its object wrapped; a wrapper is itself. The library's `compiled_for(x)` makes one ([traits §7.6](traits.md#76-compiled_forx)).
- **`Base.convert(::Type{Dynamic{X}}, x)`** is the library's method at a type of `Core` it declares the memberships of: it boxes. It is no method at a set: a late load of it ends nothing (E-404).
- Lowering knows neither name: a kept form is made by an ordinary call.

**Status:** `Core.Dynamic`: Implemented on `unified` e692e57ab7 (W-111); its constructor tests the membership when it runs and boxes a box anew, and the library's methods stand in (C-113). The wrapper is the library's type (C-113, [traits T-126](traits.md#19-deviations)). The casts and `keep` are still built (C-112). `Dynamic` in `Core`: mine (2026-11-06, the reviews of the draft). `Compiled` in `Core`, beside it: mine (2026-11-15).

---

## 7. Operations on a value typed by its trait

### 7.1 The rule

- **A call of an operation of `X`** whose receiver's inferred type is a set instance `X{p…}` (not a concrete member) is inferred as the operation's declared result at those parameter values. The declared result comes from the operation's entry in the contract (§4.1): of `X`, of a set `X` joins (a supertrait, from the set's own entries, `jl_supertrait_instances`), or of each component of an intersection. Where several entries apply to the call's types, the result is their intersection. No method at the set is read.
- **The same split for a closed abstract type with a contract** ([traits §3.4](traits.md#34-open-and-closed)): a call of one of its operations whose receiver's inferred type is the type is compiled as the split, its result `Any`. The declaring module writes the contract once on the type's `TypeName`, `jl_declare_contract(T, ops, cands)`: its operations, the module's methods at `::T`, each an entry with the result `Any` (§4.1), and its candidates (§7.2), as `svec(ops, cands)`. Images keep it with the `TypeName`. A contract is declared in the image that defines the type; one written on a type another image holds is refused, since the writer's image would not keep it (Base's build declares Core's `IO`'s; mine, 2026-11-10). Inference reads it (`jl_contract_operations(T)`) where it reads a set's methods with declared results.
- The call is compiled as a split (§7.2), with the result asserted to the declared type, never converted ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). Where no split applies, the dynamic call's result is asserted.
- **A const result taken for its effects joins its type.** A declared result makes inference non-monotone: at the set the call's result is the declared result, and constant propagation that sees the member's type reaches the member's own method. Where the constant-propagated code is taken for its effects or its exception type, its result type is joined into the call's, so compiled code never returns a type its call's type excludes (`handle1`, `unified` ef1233e79e).
- A declared field read at such a value works the same way, and so does `getproperty` at a constant name `N` where the set is a subtype of a `HasProperty{N, R}`: its result is `R`.
- Under the facts mode, each branch of the split is a fact; the fallback is a run-time site.

**Status:** The rule for an operation's call implemented on `unified` e70675a606, compiled as the split (§7.2) with the result asserted. Declared fields implemented on `unified` 50da8d8ee2: the library writes a trait's declared fields on its `TypeName` (`jl_set_declared_fields`), inference reads them along the trait's declared supertypes, and along its supertraits (their instances from the set's own entries, `jl_supertrait_instances`) on `unified` 350c5b1c59. `getproperty` at a `HasProperty{N, R}`: on `unified` 350c5b1c59, a declared field named by the input `N` ([traits §4.3](traits.md#43-fields)). The facts mode: W-100. A closed abstract type with a contract on `unified` b05ae361e0 (E-337): mine (2026-11-09). The declared result read from the contract's entries, with no method at the set: Implemented (D-4; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498); `operation_entries!`).

### 7.2 The split

```julia
Compiler.split_call(K, ::Type{RT}, f, x, args...)            # f(x, args...)::RT
Compiler.dynamic_candidates(K)::Vector{Any}                   # the first MAX_FACT_SPLITS, in order
```

- **The candidates of a set** are its concrete members in declaration order, from an index per set that the runtime keeps. An entry records its declaration's file and line; the order is by those. A concrete type joins the index at its membership, a member of a pattern at its first use (§10.4). The index is read without an edge.
- **The candidates of a closed abstract type with a contract** are the concrete subtypes its declaring module registers (`jl_register_candidate(T, C)`), in that order.
- **At an intersection** `All{X, Y}`, the candidates are those of `X`'s index that are members of every component.
- **Inference:** where `x`'s type is not concrete and the set has candidates, `f` is inferred at `x`'s type intersected with the union of the first four candidates; each split is a fact with its edge.
- **In each branch the value's type is the candidate:** the argument is `Compiled` there, so a branch that a method at the set serves runs that method's instance for the candidate, and the branch's case is the candidate, never the set.
- **The split:** the inliner splits the call over them. The last branch, the fallback, calls through the table of the call's targets (§7.3), or is the dynamic call where no table applies. The split is never fully covered.
- **A branch is inlined only where its body is a leaf:** with what it inlines itself, it calls only builtins and intrinsics (`flush(::IOBuffer)` returns `nothing`). Every other branch calls its candidate's target through a `:caller_world` pointer (§8.1), made when the caller is compiled, as the table's miss makes one (§7.3). Such a branch records no edge, since the call dispatches in the caller's world. An inlined leaf records its edge, and brings no edge of a callee. So an invalidation below a candidate's operation stops at the candidate: an instance compiled once, which every caller of the operation shares, does not carry it to them.
- **The result:** an inlined branch whose result is not known to be an `RT` is asserted to `RT`; its candidate is a checked member ([traits §5.10](traits.md#510-checks)) or one of Base's (§7.5). A branch through a pointer and the fallback assert `RT` too: the target compiled for its type asserts its result (`Base._SplitTarget`), the dynamic call is asserted where it returns. Nothing is converted. The join is `RT`.
- **Which candidates a caller splits over is fixed when it is compiled.** A member registered later reaches the fallback, and invalidates nothing.
- **No method at the set is needed.** A branch is the call at its candidate's type, which dispatches to the member's own method, or to a default's method at the set. The fallback's target is the call at the value's type (§7.3). The split reads the set for its candidates and the contract's declared result only (§7.1).
- Registration is lock-free for readers: the table is replaced on each registration.

**Status:** Implemented on `unified` e70675a606: the candidates per set, registered at a membership, at an image's activation and by the library at a pattern's member's first use, ordered by declaration (C-38); the split over the first four, the table as the fallback (§7.3). Each branch `Compiled` for its candidate on `unified` b133374e9d (found by `IO`'s `get`, whose candidates are all served by the default at `::IO`; gate `n19_io_trait`): mine (2026-11-09). A branch not inlined through a pointer, with no edge, on `unified` 0c836f3ef6, and only a leaf inlined on 7bd8b6e512 (E-332, [open issue 167](../open-issues.md#2-design) (a)); the result converted (traits §7.9) on 0c836f3ef6 (E-333): mine (2026-11-09). That the split needs no method at the set: run without one on julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498): the library's suite, the ports' suites and the forks' digests pass with no method at a set for an operation without a default.

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
- **A miss** makes the pointer and adds it. The pointer is a `:caller_world` `cfunction` (§8.1) of a target whose method asserts each argument and the result (§7.2). The target is the call at the value's concrete type, `f(x::T, args…)`: it reaches the member's own method, or a default's method at the set, and needs no method at the set for an operation without a default. It dispatches in its caller's world at each call, so the miss runs in the latest world, and Base defines the target before any code that can split: a caller may run in any world of Base's build (a generated function's generator runs in the world it was defined in). A type with no method for the call gets a pointer that raises the `MethodError` the call would.
- **Arguments and result** pass by value where the type is an isbits type of nonzero size, else boxed.
- **The fallback stays a run-time site:** it dispatches in the caller's world and records no edge. The table needs no invalidation.
- **Sessions:** pointers are valid in their session; a table saved in an image counts as empty in another.
- **Threads:** a table's state is replaced on each addition, never mutated; readers take no lock.
- **Applies to** a split whose function's type is concrete and not a kind, with at most six arguments after the value. Elsewhere the fallback is the dynamic call. In a trimmed program the fallback is the dynamic call. In a session without the compiler the table's miss makes no pointer, and the fallback takes the dynamic call.
- **Ahead of time:** for each member declared in a package, its targets and their thunks are compiled into that package's image, at each call signature whose other arguments are concrete. A target whose call has abstract further arguments is made at its first call.

**Status:** Implemented on `unified` e70675a606, ported from `trait-world-1.13` 711484a23e and 6d480d0753, but for the targets compiled ahead into images (C-39). The dynamic call where no pointer is made, on `unified` d554855579 (found by Base's `precompile` test, a session without LLVM; E-330): mine (2026-11-09).

### 7.4 `Callable`'s call

**Memberships.**
- `Core.Callable{A, S}` is a set with two input parameters. Its members are declared, as any set's: Core's build declares `Function` a member of every instance, one entry whose pattern leaves both inputs free; a callable type that is no `Function` joins the same way, by `@implement Callable T` ([traits §9](traits.md#9-functions-callable)). The kept forms are members by the library's entries, as for any set ([lowering §9](lowering.md#9-callable)).
- **Subtyping reads no method:** `F <: Callable{A, S}` is answered from entries alone, for every `A` and `S`. Positives fold through the entry and negatives fold with their edge, as at any set (§4.8). A method definition begins or ends no membership.
- **Neither input selects a method:** two methods at `Callable` instances that differ only in `A` or `S` meet at every function: a tie, which Julia reports as any (`detect_ambiguities`, a call's `MethodError`).
- `Callable` alone is every member: every function, and every type declared callable.

**The check at the box.**
- **`Core.Dynamic{Callable{A, S}}(f)`** tests that `f` has a method at `A` (`hasmethod`, in the world it runs in) and raises the `MethodError` a call at `A` would where it has none. Where the compiler knows `f`'s type, the test is a fact (`hasmethod` at a declared signature, [facts §3](facts.md#3-fact-signatures)) and folds, with its edge to `f`'s dispatch at `A`.
- **A wrapper at a `Callable{A, S}` argument** is tested the same way where it enters the method as written, and its result inferred at `A` must meet `S` (else the `TypeError` a call's result would raise): the method definition puts the test there (§6.3). The method is compiled for the wrapper's type, so the test folds with its edge.
- **A call of a box** asserts each argument to `A` (`MethodError`) and the result to `S` (`TypeError`), in the box's call method, however the box is called. It dispatches on the held function when it runs, as Julia's dynamic call does, with Julia's caches (§8).
- **A call of a wrapper** is the function's own, compiled for its type.

**What the rule lets the compiler do less:** subtyping at `Callable` reads entries, as at any set, with no walk over a function's methods and no fixed point; a method definition invalidates through a membership only as any method does.

This is `Callable`'s own handling, as Rust's `Fn` traits are the compiler's own.

**Status:** Implemented (the plan's D-2, 2026-11-15, the user: "Okay, accept the change."; [decisions](../record/decisions.md) §3; W-153): `Callable`'s inputs and `Function`'s entry, declared in Base's build (`base/Base.jl`), subtyping by entries only, julia `next` eaa19da272; the box's test, the wrapper's entry and `@implement Callable T` in TraitWorld `unified` c14d2e4 (W-161; E-500), with C-146. The box's call checked at both ends in the library: TraitWorld 5d52f0d (W-113). `Function` declared a member of every instance, and a callable type that is no `Function` by declaration: mine (2026-11-15). The wrapper's test also reads its result inferred at `A` against `S` ([GT-24](../goals.md#3-tensions-between-the-goals) (b)): mine (2026-11-15, W-161).

### 7.5 `IO`

- **`Core.IO` is a closed abstract type with a contract** (§7.1). Its members are its subtypes, as in Julia. It has no entry, and code typed `io::IO` is compiled per stream type, as in Julia.
- **Base declares the contract** in `base/iotrait.jl`, kept in the system image (§9): `jl_declare_contract(IO, ops, cands)`, the operations Base's methods at `::IO`, each result `Any` ([traits §9b](traits.md#9b-streams-io)), and the candidates `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`, in that order (§7.2), fixed with the contract: no module adds one later. A stream past them (an `IOContext`, the REPL's `LimitIO`) takes the table (§7.3).
- **At a receiver typed `IO`,** an operation's call splits as at a set (§7.2), the firewall included. The places that ask for a set ask for a set or a type with a contract: the declared result's lookup and the split's type in inference, and `jl_candidates_of` in the runtime; `jl_register_candidate` refuses a type with a contract.
- **No result is promised:** members join by their declared supertype, before their methods exist, and no check reaches them ([traits §5.10](traits.md#510-checks)), so each operation's result is `Any`, as Julia infers it at a receiver typed `IO`. A call through `IO` returns the stream's own result: Core's streams and `Filesystem.File` a `UInt` count, `IOBuffer` an `Int`.
- **The eraser `IOContext{IO}`** holds its stream in a field typed `IO`, so its forwarders' calls of the operations split. Base defines `IOContext{IO}(io)` and `IOContext{IO}(io, key => value, …)`; for an `IOContext`, the new context merges its properties, as `IOContext(io, …)` does.

**Status:** Implemented on `unified` b05ae361e0 (W-129 (c); `base/iotrait.jl`, `jl_declare_contract`; gates `n19_io_trait`, E-337); each result `Any`, nothing converted, on ef1233e79e, the candidates in the contract on 18bbbf0841 (open issue 171, C-81; gates `n19_io_trait`, `n23_contract_image`; E-340). The user (2026-11-09: "Go with the Fable plans recommendations"; [the plan](../../attic/writeup/plans/2026-11-09-io-alternatives.md) §4.2). The candidates' order: mine (2026-11-09); no result promised: mine (2026-11-10). Targets at a stream past the candidates compiled at the first call: open issue 170.

---

### 7.6 A closed build

A build under `--trim` is closed: **what is final** there is every set's members, those the build has, and every function's methods ([facts §3](facts.md#3-fact-signatures), "What is final"). That is the one input in which a closed build differs from a session. Nothing joins later, so nothing can be invalidated, and every call whose targets the build can list is settled. The rules below follow from it; they are no policy of their own. A closed build does what Rust and Mojo do with a trait bound ([traits §16](traits.md#16-compiling-ahead-closed-programs)).

What follows from it, beside the members and the split below:
- **A call at an abstract type with one method resolves** to that method, as plain inference resolves it: the methods are final.
- **An operation on a set with no member is a "no method" fact.** The list of members is final and empty, so the call raises `MethodError`, as any call no method takes. So a library's code that calls a trait's operations builds in a program that has no member of the trait.
- **A call in the latest world is the call.** Nothing is defined later, so `invokelatest(f, args…)` is inferred as `f(args…)`, and a call after `:latestworld` as any call.

- **The closed rules apply** under `--trim` (`closed_build()`), and in the build's check run in a session (§2.7), which asks them of its interpreter (`closed_build(interp)`). Every rule below reads that one answer.
- **A build compiles what is written,** as a session does: a plain member at a method of a set that erases by default is boxed by the forwarder (§6.3); code for a box is compiled once per set instance, for a wrapper per object type. A box is a concrete type, so code that passes it on, keeps it or returns a value made from it is typed in a build as in a session.
- **The split is over every member** (§7.2), where the set's members can be listed: all of them that are of the receiver's type, not the first four. With them the box `Dynamic{X}`, which its own forwarding method opens ([lowering §2](lowering.md#2-trait)).
- **The members of a set in a closed build** (`closed_candidates(X)`), from its membership entries in force:
  - an entry at a concrete type: that type;
  - an entry at a subset: the subset's members;
  - an entry at a family, `S{T} where T`, or at an abstract type: its **members by use**.
- **Members by use.** A family has as many members as its type has instantiations, and a program uses few of them as members. The build reads its own compiled code for the types it *forgets*: a value of a concrete type passed to a place whose type does not keep it.
  - **The places:** a field or an array's element; an argument of an instance compiled at such a type; a result; a variable that joins branches; an assertion (`x::Shape`); and what a constant built while the program loaded holds in such fields and elements.
  - **A member by use** of a family or an abstract type, at a set `X`, is a type under it that the build forgets at a place typed under `X`. A value reaches code typed by `X` only from such a place.
  - **Or through a test:** where the code narrows a wider value to a type under `X` (`x::X`, `x isa X` at an `Any`), the types forgotten at that wider type count too.
  - It is what Rust does with `impl<T> Column for Vec<T>`: a `dyn Column` has a table for each `Vec<T>` the program coerces, not for every `Vec`. Rapid type analysis lists a class hierarchy's receivers the same way.
- **The build compiles in rounds.** Each round's code is read for the types it forgets; a set that has more members than a split was inferred with has the noted instances, and those that invoke them, inferred again. At most 16 rounds.
- **A value of a type the build did not count raises** the `MethodError` at the branch: the answer is Julia's or an error (G1).
- **The build's report** (`JULIA_CLOSED_BUILD_REPORT` in the environment): the rounds, each set's members, and where each was forgotten.
- **Each branch is a direct call** of the member's method, or its body inlined. No pointer, no table (§7.3).
- **An invoke that names its method instance is compiled as any target.** A body inlined from an image names an invoke's target by its instance, not by its code. The build's queue compiles the instance, and the verifier takes the invoke as resolved where it did. A call that inference limited (a recursion over growing types) names a new instance at each step: at most four instances of one method are followed this way, and past them the invoke stays unresolved.
- **Past the branches the call raises** the `MethodError`. No call is left to dispatch when the program runs.
- **A call whose method's static parameter a value known only by its trait binds branches over the members** (`Core.Compiled(x)` with `x::X`, the wrapper's constructor that `compiled_for(x)` calls): the call is inferred at the union of the set's members and split as an operation's call is, each branch the call at the member's type. A session leaves such a call to dispatch when it runs.
- **Any other call that does not know its argument's member** runs the method's instance at the argument's declared type, as Julia compiles a call at an abstract type with one method; the instance's operations branch over the members.
- **A split over more than 64 members is not made.** The call stays dynamic, and the build's verifier refuses it.
- **Memberships are asked in the world the build compiles for.** The build's driver runs in the compiler's own world, where no membership of the program exists; it sets the membership query world as `jl_type_infer` does for a session.
- **Code inferred before every member was declared is inferred again.** While the build loads its program, an instance whose inference met an operation's call at a set, or a call left to dispatch on a trait argument, is noted. When the build compiles, each noted instance is invalidated, with its callers, and inferred with every member. A method at a set checked at its definition ([§6.7](#67-the-definition-time-check)) is such an instance: it was inferred with no member.

**Status:** Implemented on `unified` 97861c6b31, ddc328b343 (the instance compiled once at a call that does not know the member), 5d8da002fa (the branches at a cast to `Compiled`, the cast typed by its set) and d8cebc40fe (members by use, the rounds, the report) (W-139; E-364: five small programs and TraitTables' table program build under `--trim=safe` and run, where the plain twin with an abstract type is refused). The rule: the user (2026-11-11); members by use: the user (2026-11-11, "Build members by use."). The box as a member, the bound of 64, the second inference, the rounds, and what counts as a use (the places, the test): mine (2026-11-11). The branches at a call whose static parameter the value binds: built for a cast only (C-114), mine (2026-11-11, for the cast; 2026-11-15, for the wrapper). The rules asked of the interpreter, and an invoke that names its instance compiled: `unified` 381cc8b953, bounded on 42681be784 (Base's `Compiler/inference` test) (W-142; E-369: Base's `repeat(::Char, ::Int)` builds). With C-86, C-87. A build that compiles what is written: Planned (the plan's D-1, 2026-11-15); the build still resolves an attribute at a trait argument (C-112, C-114). The closed rules as what follows from what is final, and the three consequences stated first: mine (2026-11-15; D-10); an operation on a set with no member and a call in the latest world: Planned, with C-102 and C-103.

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
- A dynamic call is Julia's (§6.2), so entries are keyed as Julia's are.
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

- **Memberships in package images.** An image writes every entry in force that its modules declared in a list of its own (a membership taken back is not written), as it writes its methods for other modules' functions; an entry on one of its own types is also on that type's list. At load the list is activated before the image's code is validated: each entry in force is in its set's index and in the session's list of activated entries (`jl_activated_memberships`, never written into an image), from which the library makes the records of the membership's check again ([lowering §11](lowering.md#11-checks-errors-and-what-images-keep)), the entries get the loading session's worlds, the world of the image's methods. The dispatch caches' lowering (§5.5) and the ambiguity report (§5.4) run for each as at a declaration. Each membership's method is activated with the image's methods, which invalidates the session's code that relied on the pair's absence (§5.6); an entry refused at activation takes its method out of force, and an entry whose method the library's image hook left inactive (§10.1) is refused. Under strict mode in a session the report's findings at an activated membership are kept as messages for the library (`jl_take_activation_ambiguities`), which reports them after the load ([traits §12.3](traits.md#123-strict-mode)); the warning is not printed. While an image is built the warning stays. The image's folded memberships are validated as its edges to methods are.
- **Machine code only for code that runs:** CodeInstances of either policy; never `return_type`'s answers.
- **Code reached only by a dynamic call is kept** where it is deep G2, by its bit (§3.2), of either policy: plain code in the class that facts code reaches is then cached as facts code is. Code outside the class could be ended by an unrelated load.
- **An image holds the code a facts run-time site reaches whatever the values.** While an image is built, a run-time site in facts code whose argument types match exactly one method, which specializes on none of the site's abstract arguments, has that method's instance compiled into the image, at its compileable signature and the facts policy. *Specializes on none* means: at each abstract argument the method is `@nospecialize`, the argument is no trait argument, and its declared type has no free variables and is no kind. Code that needs an instance per value's type at such a site (a closure capturing untyped values) is not covered; it is written as a loop.
- **An image keeps no external code specialized at a signature type without a hash** (a value-specific instance). Its insertion at load would scan its method's specializations.
- **The member checks' instances** made while the image was built are kept with its code, with their edges, and validated with it ([traits §5.10](traits.md#510-checks)).
- **The system image keeps the indices of sets** as it keeps its method tables: its methods at sets and each function's, the sets' candidates, entries and absence signatures, the contracts of closed types (§7.1) and their candidates, and the split tables' miss (§7.3). So `IO`'s contract holds from the start, and a membership invalidates the image's code that folded its absence.
- **Compiling ahead:** for each membership a package declares, the set-to-methods index (§5.1) gives the methods at the set and its supersets to compile at the member's type ([traits §16](traits.md#16-compiling-ahead-closed-programs)).
- **A machine-code cache across sessions is the goal of the record.** The record of §3.1 is kept complete, naming its targets by identities stable across sessions:
  - a method by module path, name, signature and a digest of its lowered code;
  - a type by path and layout;
  - a membership by member, set and declarer.

  So a cache of machine code later adds a loader, not a mechanism. The cache itself is paused ([decisions](../record/decisions.md) §5).
- No part of this design stores a world, a session object or an address where a stable identity serves.

**Status:** Memberships in package images implemented on `unified` 28c401eb0c (W-108), refused at a second instance on 07c0bee2a2; the edges with W-141 (§5.6). Every activated entry in its set's index and the list of activated entries on `unified` e42047dba2 (C-83 retired, gate `n12_image_instances`, E-344); an older entry for the same member, set and inputs ended at activation on 9f8d7d7c48 (E-348). The pattern members' answers: lowering L-55. Compiling ahead: Planned ([traits §16](traits.md#16-compiling-ahead-closed-programs)). The keep rule by the G2 bit implemented on `unified` 823754556f (W-100), for code reached only dynamically from outside the package: TraitWorld's image grew 3.7 %; by the deep class on `next` 7063158f42, TraitWorld's image keeps 209 such instances where it kept 237 (E-417). The cache: paused. The rule for a signature type without a hash is implemented on `unified` 999634c858. The walk and the report at activation: mine (2026-11-07); the findings handed to the library under strict mode on `unified` 9f8d7d7c48 (gate `stack/strict_activation.jl`, E-349): mine (2026-11-10). The rule for run-time sites implemented on `unified` 6767b03893 (`Compiler/src/facts.jl` `rtsite_targets`, `typeinfer.jl` `compile!`; E-326; gate `n17_rtsite_targets`), for all modules: mine (2026-11-09). The system image's indices of sets on `unified` b133374e9d (W-129 (b), gate `n19_io_trait`): mine (2026-11-09).

---

## 10. Hooks for the library

### 10.1 Definition and image hooks

```c
void jl_set_method_definition_hook(jl_value_t *hook);   // hook(m::Method, after::Bool)
void jl_set_image_methods_hook(jl_value_t *hook);       // hook(ms::Vector{Any}, pkg::String) -> methods to leave inactive
void jl_set_module_end_hook(jl_value_t *hook);          // hook(m::Module)
void jl_set_method_expansion_hook(jl_value_t *hook);    // hook(argdata, code, m::Module) -> nothing, or (argdata, code) pairs
```

- **The definition hook** runs twice per method definition: before the method enters the table, where it may refuse it (no world is allocated), and once it is visible.
- **A refusal is an error the hook returns.** The runtime raises it at the definition, so the first frame of its backtrace is the method's definition, not the library ([traits §11.3](traits.md#113-errors-and-their-messages)). An error the hook throws is raised too, with the library's frames.
- **The image hook** runs once per package image, with its methods for other modules' functions, before any is activated. Methods it returns stay inactive.
- Both run in the latest world, outside the world-counter lock, not for a definition a hook makes, and not while the system image is built.
- **The expansion hook** runs at a method's definition where its evaluated signature names a set, before a method is made: it answers nothing, or the list of (argdata, code) pairs the one definition makes in its place (the method at the kept forms and its forwarder, §6.3). Each is defined in order, without expansion, with the definition hook run for each.
- **The module-end hook** runs when a module's definition ends (`jl_eval_module_expr`), and for a package also while its image is written. The library checks there the methods that waited for later definitions (§6.7), and refuses a `struct S <: X` without its `@implement`.
- Strict mode, the override rule, a member's check kept while it is a member ([traits §5.10](traits.md#510-checks)), the `no_pirates` and `bounded` options use them.
- In the image hook a method about to be activated is inferred as it is: a call it makes to another inactive method of the same image infers `Union{}` there.
- Both hooks first bring the library's records up to the memberships images have activated (§9). The image hook runs before its image's own memberships are in force, which its build checked with its methods.

**Status:** Implemented on `unified` 28c401eb0c (W-108). TraitWorld `unified` 701aaab uses them for the override rule and for a `struct S <: X` without its `@implement`; `bounded` bb78d02 (W-111); strict mode and `no_pirates` 7adcc94 (W-114); a member's check kept, in the definition hook's first call and the image hook, 5b3c427 (E-342). The module-end hook: mine (2026-11-06, the work plan's review, weak point 6). A returned error raised at the definition: `unified` 8f42ba7ed7 with TraitWorld `unified` 399f389 (`test/messages.jl`), mine (2026-11-12). The expansion hook: `next` 8b1ec88a56 with TraitWorld `unified` 21ae901 (W-160), mine (2026-11-15).

### 10.2 Hooks for strict mode

- **A deletion hook,** called at method deletion; it may refuse.
- **A hook for a binding redefined from another module,** at its source.
- **A report per image:** the edges that failed validation, with the winning method.
- **What a membership would replay,** read before a pirate's membership is declared: `jl_membership_replay_sigs(member, set)` lists each method at the set, or at a set it joins, with its signature at the member in the set's place (§5.5); `jl_membership_method_sig(member, set)` is the signature of the membership's method (§5.6). Both change nothing.
- **Strict mode's check at a membership** (§4.3): `jl_set_strict_memberships(on)`, set by the library's strict mode. With it on, the ambiguities at an image's activated memberships are taken with `jl_take_activation_ambiguities` (§9).
- **What a definition ended, by class:** for each method definition, deletion, membership, and image whose activation or validation ends code compiled by facts in the deep class (§3.2), the runtime keeps the cause with the instances it ended, in a list the library takes after the definition or the load (`jl_take_deep_endings()`, `[kind, cause, code, …]`): the kind `:definition`, `:deletion`, `:membership` (the cause the membership's method, §5.6) or `:validation` (the cause the edge that failed at the load, which validation notes with `jl_note_deep_ending(edge, code)`). The list is filled only where such code ends, from the invalidation and validation that end it, so a definition that ends none costs nothing; it is kept only while the library asks for it (`jl_set_deep_endings(on)`). The library judges ownership and reports a pirate ([traits §12.2](traits.md#122-pirates)).

**Status:** The deletion hook implemented on `unified` 5f2373b2d5 (`jl_set_method_deletion_hook`, W-114). The report per image is the library's, from validation's log (TraitWorld 7adcc94). The hook for a binding redefined from another module: Planned ([traits T-96](traits.md#19-deviations)). The flag for a membership on `unified` 0bb8f38830 (E-343); the ambiguities at activation on 9f8d7d7c48 (E-349). What a membership would replay, and the entry refused with its method: `unified` 7fee959383 (gate `stack/strict_pirate_membership.jl`). What a definition ended, by class: `next-s3` 5d2ec7ff85 (the plan's D-12, 2026-11-15; E-457); `jl_take_deep_endings`, `jl_set_deep_endings`, `jl_note_deep_ending` are mine (2026-11-15).

### 10.3 Field-offset intrinsics

An optional extension, with keys: [extensions §1.6](extensions.md#16-field-offset-intrinsics).

### 10.4 The member hook

```c
void jl_set_member_hook(jl_value_t *hook);   // hook(T::Type, X::Type) -> nothing, or throws
```

- **The hook checks a member of a pattern** (a family, a closed abstract type, a set) that no declaration checked.
- **The runtime calls it at the member's first use,** where no answer is kept for (member type, set):
  - at dispatch, before the instance lookup, and at a split's table miss;
  - in the compile queue: inference notes each (member type, set) that a call it resolves to a method at the set rests on, and when inference returns, before the code runs, the runtime asks the hook for each. A failing check leaves that use to dispatch, which raises the `ImplementError` there; a use in a branch not taken raises nothing.
- It is called for an argument whose chain carries an entry, or has a set as a declared supertype: a member by its definition (`abstract type A <: X end`) is reached through its `@implement`'s entry, and a type under a set by its definition with no entry yet is refused by the library ([traits §5.2](traits.md#52-with-the-types-definition)). That refusal is not kept as an answer: the declaration ends it.
- **Inference never calls it,** and no runtime lock is held while it runs. It runs in the latest world. Inference reads the kept answer: none, it notes the member for the queue; a failure, it leaves the call to dispatch. A per-(member type, set) state marks a check in progress; a check that reaches its own member again raises, and code compiled inside a check uses its member without waiting for it.
- **A package image keeps the answers that passed while it was built** ([lowering §11](lowering.md#11-checks-errors-and-what-images-keep)): the pairs (member type, set) travel with the image's memberships. At load they count as passed, so the hook is not asked again, and the library reads the list (`jl_activated_member_checks`) to make the checks' records again.
- **A check that failed can pass later** (a member by its definition, once declared). The code compiled while it failed is then compiled again, with the use resolved.
- The runtime keeps the answer per (member type, set) on the member's `TypeName`, a failure included, and every later use reads it.
- **A package image keeps the answers** found while it was built, with the methods each check relied on, and drops an answer at load where those methods dispatch differently. Checks at a first use are for members no image checked.

**Status:** Implemented on `unified` ec4f9a8714 at dispatch and fcdfd0da36 in the compile queue (gate `n24_hook_compile_queue`, E-352; leaving a failed use to dispatch: mine, 2026-11-10), with C-30 and C-31; an abstract member's subtypes reached through its entry with TraitWorld e8554d9 (C-85, E-345); a declared subtype of a set with no entry on `unified` 352b916899 with TraitWorld 0aff625 (E-350); a failed check lowers the entries made while it ran on 07c0bee2a2; at a split's table miss with W-109. Mine (2026-11-06). Checks only, and where it runs: mine (2026-11-06, the reviews of the draft).

---

## 11. Changes useful without traits

Each applies to all code.
- **An invoke keeps the exact specialization over a widened varargs tail,** where the compileable signature only widens a `Vararg` tail and the exact specialization has code.
- **An inference cycle's members inline each other:** when a cycle finishes, each optimized member is offered to the inliner of the members optimized after it.
- **The run-time `return_type` entry in the system image:** `_return_type(::NativeInterpreter, ::DataType)` is a compiler bootstrap entry; with the facts policy, so is the entry of `return_type`'s own interpreter (§1.4).
- **Reflection in the compiler's world** with an explicit `NativeInterpreter`.
- **The dispatch profiler:** `JULIA_DISPATCH_PROFILE=1` counts dynamic calls per callee method, per lookup path and per call site.
- **Base's type introspection on builtins and `invoke`:** the helpers that assert their effects (`padding`, `array_subpadding`, `fieldcount`, `isabstracttype`, `unwrap_unionall`, `isvatuple`, `datatype_alignment`) and the type joins (`typejoin`, `typesplit`, `tailjoin`, `full_va_len`, `promote_typejoin`, `_promote_typesubtract`, `rewrap_unionall`, `unwrapva`, `supertype` of a `DataType`) read a type's fields with `getfield`, take sizes, offsets and field types from builtins or the runtime, and call each other through `invoke` at the callee's own signature. A package's methods for its own types cannot make their assertions false, nor reach the code compiled over them. The same rule where Base stores a value of any type: `IOContext`'s property list through `ImmutableDict`'s own constructor, and `Val(x)` built with `new`.
- **Error paths build their exception at a concrete signature:** a helper that raises takes what it reports by its type (`Core.throw_inexacterror`'s type as `::Type{T}`, `DomainError`'s message, `string_index_err`'s string), and an exception's convenience constructor builds with `new` (`TypeError`'s three-argument form). A package's method for its own type reaches no caller of an error path.
- **The scheduler writes a task's fields with `setfield!`:** `yieldto` sets the result as `schedule` does.
- The world-checked caches of §8.1 and §8.2, and an image's rule for a signature type without a hash (§9).

**Status:** Implemented on `unified`, one commit each, below the stages' commits ([`../design/julia-changes.md`](../design/julia-changes.md) §7.1); the entry of `return_type`'s own interpreter with the facts policy (W-100). The type joins, the error paths, the scheduler's write, `Val` and `IOContext`: `next-s3` ab96564f36, 297d19aca1, 396cd65a48, 024755ee89, bc844be7c0 (W-157, the plan's D-8; E-478). Upstream proposals: the same chapter.

---

## 12. Status index

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
| keys: `TraitKey`, calls from code per key, the calling convention, the adapter, field offsets | an optional extension (W-110): [extensions §1](extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike) | §6.1, §6.4–§6.6, §10.3 |
| the forwarders, made where a method at a set that erases by default is defined | Implemented (`next` 8b1ec88a56, TraitWorld `unified` 21ae901; W-160), with C-111 (the forwarder's record of its method) | §6.3 |
| the definition-time check: the instance at the box | Implemented (D-3; TraitWorld 9c0912b, `next` 75a7f1795b; W-160 (c)), with C-115 | §6.7 |
| a declared result on `Method`; lowering's record of `f(…)::RT` | Implemented (`unified` 0ba6317994); an operation's declared result from its contract entry: Implemented (D-4; `next` 5448a8b7bf) | §4.1, §6.8 |
| the kept forms in `Core`: `Dynamic{X}`, `Compiled{T}` | `Core.Dynamic` implemented (`unified` e692e57ab7, W-111), with C-113; `Core.Compiled` Planned (D-1), with C-113; no cast, no `keep`: Planned, with C-112 | §6.9 |
| operations on a value typed by its trait; the split; the table | Implemented (`unified` e70675a606, 50da8d8ee2), with C-38, C-39; no method at the set for an operation without a default: Implemented (D-4; `next` 5448a8b7bf) | §7.1–§7.3 |
| `Callable`: every function a member, the signature checked at the box and at a wrapper's entry, the result on return | Implemented (D-2: `next` eaa19da272, TraitWorld c14d2e4; W-161), with C-146 | §7.4 |
| A closed abstract type with a contract; `IO`'s contract, its candidates, the eraser `IOContext{IO}` | Implemented (`unified` b05ae361e0, ef1233e79e, 18bbbf0841) | §7.1, §7.5 |
| world-checked caches: `:caller_world`, the per-call-site cache | Implemented (`unified` 6f936edf18, 8319275b9e); exact-type entries W-109 | §8.1, §8.2 |
| further caches at dynamic boundaries | Optional | §8.3 |
| memberships in images; the record toward a machine-code cache | memberships in images implemented (`unified` 28c401eb0c; one instance per member at activation, 07c0bee2a2); the positive-membership edge read at validation (`unified` 9a601902a0); the record's stable identities: C-52 | §9 |
| hooks, the module-end hook included; the member hook | the member hook implemented at dispatch (`unified` ec4f9a8714) and in the compile queue (fcdfd0da36; C-30, C-31); the definition, image and module-end hooks implemented (`unified` 28c401eb0c); strict mode's deletion hook implemented (`unified` 5f2373b2d5), the binding hook Planned; what a definition ended, by class (`jl_take_deep_endings`) `next-s3` 5d2ec7ff85 (D-12, E-457) | §10 |
| changes useful without traits | Implemented (`unified`, the stack's first eleven commits) | §11 |

---

## Deviations

The build's heads: [state.md §6.1](../state.md#today); its commits, stage by stage: [julia-changes §7.1](../design/julia-changes.md#71-the-stack). IDs are shared with the record's other references and never reused.

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
| C-30 | [§10.4](#104-the-member-hook) | The runtime keeps the member hook's answer per (member type, set) on the member's `TypeName`, a failure included. | The runtime keeps the state in a table of its own (`jl_member_states`), read by inference and the compile queue, and an image keeps the passed ones (`unified` b1c0b50f4c). The library keeps the answer too (`TraitWorld._CHECKED`), and the runtime calls the hook at every dispatch miss of such a call with no answer, and lowers the cache entries a failed check left. A failure is not kept by an image. | `src/gf.c` (`member_hook_at_dispatch`, `jl_member_note_use`, `jl_member_checks_passed_here`); TraitWorld `src/implement.jl` |
| C-31 | [§10.4](#104-the-member-hook) | The hook also runs in the compile queue, before code that relies on the member runs; a use whose check failed is left to dispatch, which raises the check's error. | Built for a call inference resolves at a concrete member (`unified` fcdfd0da36, gate `n24_hook_compile_queue`). A call by `invoke` at the set's method asks no hook, compiled or at run time. With several threads, another thread can run the compiled code before the queue's check of it ends. | `src/gf.c` (`jl_member_queue_drain`); `Compiler/src/abstractinterpretation.jl` (`member_check_failed`) |
| C-32 | — | *Retired* (2026-11-08): a set's inputs on `unified` 350c5b1c59 ([§4.6](#46-one-instance-per-member)); gate `n10_inputs` | — | — |
| C-33 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.7](#47-three-layers), [§5.3](#53-match-world-ranges-and-abstract-queries)); gate `n2_open_abstract` | — | — |
| C-34 | — | *Retired* (2026-11-07): fixed on `unified` 8a9144928e ([§4.9](#49-intersections)); gate `n2_all_form` | — | — |
| C-35 | — | *Retired* (2026-11-08): an image's membership that would give its member a second instance of a set is refused at activation, with a warning, on `unified` 07c0bee2a2 ([§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances`; E-296 | — | — |
| C-36 | — | *Retired* (2026-11-09): lowering records `f(…)::RT` on `unified` 0ba6317994 ([§6.8](#68-a-declared-result-on-method)); gate `n16_declared_result` | — | — |
| C-37 | — | *Retired* (2026-11-07): the split's last branch calls through the table on `unified` e70675a606 ([§7.3](#73-the-table-of-a-calls-targets)); TraitWorld test `table` | — | — |
| C-38 | [§7.2](#72-the-split) | A set's candidates are ordered by their declarations' file and line. | By the order in which the memberships are declared or activated: across images, by load order. | `src/datatype.c` (`register_candidate`) |
| C-39 | [§7.3](#73-the-table-of-a-calls-targets) | For each member declared in a package, its targets and their thunks are compiled into the package's image. | A target is made at its first miss in each session. | `base/splittable.jl` (`_split_table_miss!`) |
| C-40 | — | *Retired* (2026-11-15): the check reads the instance at the box ([§6.7](#67-the-definition-time-check)); what is built of it, and the check interpreter still in Julia: C-115 | — | — |
| C-41 | — | *Retired* (2026-11-15): the instance at the box is kept with its edges as code ([§6.7](#67-the-definition-time-check)); what is built: C-115 | — | — |
| C-42 | — | *Retired* (2026-11-07): code of both policies under Julia's own owner on `unified` 10c7e1c2cf ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy)); gate `f3_policy_code` | — | — |
| C-43 | — | *Retired* (2026-11-07): lowering carries the policy meta into every method a definition makes, on `unified` cb7f55bd35 ([§2.2](#22-the-method-flag)); gate `f2_policy_flags` | — | — |
| C-44 | — | *Retired* (2026-11-07): the policy of the code that reaches a method on `unified` c44a447f2c ([§2.3](#23-one-codeinstance-per-methodinstance-and-policy), [§2.4](#24-calls-between-policies)); gate `f6_reach_policy` | — | — |
| C-45 | [§2.4](#24-calls-between-policies) | Constant propagation from plain code into a facts callee infers the callee again under the facts policy; concrete evaluation of a facts callee from plain code uses its facts effects with a code edge. | Constant propagation and constant evaluation into a callee of the other policy run under the caller's policy, in the caller's inference; past four nested inferences of the other policy a call is answered as unknown. | `Compiler/src/facts.jl` (`typeinf_other_policy`) |
| C-46 | — | *Retired* (2026-11-08): the bit requires each inlined callee's own record to satisfy G2, the callees found from the debug info, on `unified` 1d493ca959 ([§3.2](#32-g2-as-a-predicate)); gates `f4_g2_bit`, `m3_g2_bit`, `m3_g2_counts`; E-297 | — | — |
| C-47 | [§1.4](#14-return_type) | In code compiled by facts, plain inference's answer is folded where it rests on facts (at most four concrete signatures, one covering method each, every edge at a fact). | Such an answer is asked at run time too: only a constant, a concrete type that is not a kind, or `Union{}` from the facts answer is folded. | `Compiler/src/tfuncs.jl` (`return_type_tfunc`) |
| C-48 | — | *Retired* (2026-11-07): the test bed starts and runs on `unified` c44a447f2c ([§2.5](#25-the-test-bed)); E-275, gate `f6_reach_policy` | — | — |
| C-49 | [§2.1](#21-the-module-option), [§2.3](#23-one-codeinstance-per-methodinstance-and-policy) | A method's policy follows its module's option. | A method instance's policy is read at its first use and cached in its flags (an image does not keep it); a module option set after one of the module's methods was first called leaves that method's policy as first read. | `src/gf.c` (`mi_policy`) |
| C-50 | [§2.4](#24-calls-between-policies) | The operation of `modifyfield!`, `modifyglobal!` and `memoryrefmodify!`, and a builtin that calls a function, reached by a dynamic call, dispatch with the policy of the code that calls them. | They reach with the setting's default; so does an ABI converter's generic call. | `src/builtins.c` (`jl_apply_reach`), `src/datatype.c`, `src/codegen.cpp` (`emit_abi_dispatcher`) |
| C-51 | [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries), [§3.1](#31-the-record) | A positive answer through an entry folds, with the code's worlds from the entry's and the entry in its record. | It folds at `isa`, `<:`, a dispatch match, `new`'s field tests and a store's or a `typeassert`'s type test (the statement's flag, W-160) in the frame being inferred. `typeassert`'s nothrow, `typesubtract` and the semi-concrete pass leave such an answer unfolded; the optimizer's effect query at `new` proves no such test. The optimizer's other queries by `⊑` answer through an entry without recording it: the inliner's match coverage, the deletion of a `typeassert` whose argument is under its type (`adce_pass!`). Their code rests on the membership with no edge of its own; where the statement came from an inlined callee, the callee's edges carry it. | `Compiler/src/typeutils.jl` (`positive_fold_blocked`), `Compiler/src/tfuncs.jl`, `Compiler/src/ssair/passes.jl` (`adce_pass!`), `Compiler/src/ssair/inlining.jl` |
| C-52 | [§3.1](#31-the-record), [§9](#9-images-and-the-machine-code-cache) | The record tells result edges from dispatch edges, gives a code edge the digest of its callee's lowered code, records the layouts of the types whose fields the code reads, and names its targets by identities stable across sessions. | An edge to a callee names its CodeInstance, result edge or code edge alike (the list of result edges apart is gone on `next` 9b6dacf5c5); no layout is recorded; targets are objects of the session or its images. In a session a method's identity and the binding edges serve. The rest comes with the machine-code cache (paused). | `Compiler/src/stmtinfo.jl` (`add_edges_impl`), `Compiler/src/typeinfer.jl` |
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
| C-77 | [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) | Inference folds a pair's negative at every site that consults `has_open_set`. | It folds at `isa` and `<:` (`isa_tfunc`, `subtype_tfunc`), in a frame that records the edge. `tmeet`, `isa_condition`, `typesubtract` and the constants' and conditionals' meets still refuse it. | `Compiler/src/typeutils.jl` (`negative_fold_blocked`), `tfuncs.jl` |
| C-78 | — | *Retired* (2026-11-10): the report asks each method the membership makes applicable against the method table at the member, on `unified` 53d28eea68 ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `m2_ambiguity_declared_super` (E-347) | — | — |
| C-79 | [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) | Where an intersection no type is in, inference relies on it as on any negative. | It folds at `isa` (`isa_tfunc`) and at dispatch's lookup (`drop_unmet_matches`, `src/gf.c`). `<:` (`subtype_tfunc`), `tmeet`, `typeassert`, a conditional's narrowing and a declared argument type still meet a set `X` with `AbstractString` as `All{AbstractString, X}`. An intersection of more than two components, or a component with free variables that is not an abstract type, is not asked. | `Compiler/src/tfuncs.jl`, `abstractinterpretation.jl` (`drop_unmet_final_matches`), `src/datatype.c` (`jl_unmet_final_cells`); gate `n20_unmet_lookup` (4) |
| C-80 | — | *Retired* (2026-11-09): `IO` a closed abstract type with a contract, on `unified` b05ae361e0 ([§7.5](#75-io)) | — | — |
| C-81 | — | *Retired* (2026-11-10): a closed type's candidates in its contract, kept by its image, on `unified` 18bbbf0841 ([§7.1](#71-the-rule), [§7.2](#72-the-split)); gate `n23_contract_image` | — | — |
| C-82 | — | *Retired* (2026-11-10): dispatch's lookup keeps an unmet match at an open set and drops it at a final pair with its absence edges, `Callable` and a `Vararg` tail met, on `unified` 999777ab77 ([§5.4](#54-the-ambiguity-report-at-a-membership)); gate `n20_unmet_lookup` | — | — |
| C-83 | — | *Retired* (2026-11-10): every entry an image activates is in its set's index, also one on the image's own type, on `unified` e42047dba2 ([§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances` | — | — |
| C-84 | — | *Retired* (2026-11-10): a membership activated from an image ends an older entry in force for the same member, set and inputs, on `unified` 9f8d7d7c48 ([§4.6](#46-one-instance-per-member), [§9](#9-images-and-the-machine-code-cache)); gate `n12_image_instances` (E-348) | — | — |
| C-85 | — | *Retired* (2026-11-10): an abstract member by its definition (`abstract type A <: X end`) has its `@implement`'s entry, so the member hook runs for its subtypes (it runs where an argument's chain carries an entry), TraitWorld e8554d9 ([§10.4](#104-the-member-hook)); TraitWorld test `declared.jl`, gate `stack/recheck_packages.jl` case 7 | — | — |
| C-86 | [§7.6](#76-a-closed-build) | A family's and an abstract type's members in a closed build are the types the program uses as members. | The build counts the types its optimized code forgets at a place under the set, or at a place a `PiNode` or a `typeassert` narrows from. Not counted: a value whose type no compiled code forgets (made by a foreign call or by reflection, or held in a constant deeper than three levels or past 4,096 elements); a narrowing by a call the build did not inline into a test. Such a value raises `MethodError` at the branch. An operation on a set with no member: C-102. | `closed_note_used!` in `Compiler/src/typeinfer.jl`, `closed_candidates` in `abstractinterpretation.jl`; E-364 |
| C-87 | [§7.6](#76-a-closed-build) | The split over a set's members costs what a session's does: a branch among a few, a table past them (§7.3). | In a closed build every member is a branch, an `isa` test in the entries' order; a set of more than 64 members is not split. | `MAX_CLOSED_SPLITS`; E-364 |
| C-88 | [§5.5](#55-a-membership-invalidates-as-a-method-does) | A membership invalidates exactly the callers whose selection it changes. | (c) Where the walk cannot follow the shape, it invalidates every instance of the replayed method and their callers: the set under a `Vararg`, in a variable's lower bound, or deeper than 8 levels. No method takes this path at the loads of the forks' CSV and DataFrames, where five did (E-390, `unified` 8fccf1e182; gate `n32_nested_set`), nor at the methods at the kept forms (`next` 75a7f1795b, E-444). (e) is retired with C-104 (a membership adds no type equality, D-11). (d) The runtime still carries what nothing reads for a membership: the bit `closed_after_load` (set for every set the library declares; `Callable` has none), the modules' loaded marks' use by `type_declarers_loaded`, and the switch `jl_set_membership_walk_invalidates` (a control for measurements). The walk's cost at a load is not measured (W-140's rounds). | `src/gf.c` (`jl_membership_dispatch_walk`), `src/datatype.c` (`jl_membership_final`) |
| C-89 | — | *Retired* (2026-11-12): the membership's method and the edges are [§5.6](#56-the-memberships-method-and-the-edges), with [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) and [§9](#9-images-and-the-machine-code-cache) | — | — |
| C-90 | — | *Retired* (2026-11-15): a box checks every call, however it is called; a wrapper is the function ([§7.4](#74-callables-call)) | — | — |
| C-91 | — | *Retired* (2026-11-15): the G2 bit marks the deep class, on `next` 7063158f42 ([§3.2](#32-g2-as-a-predicate), [§9](#9-images-and-the-machine-code-cache)); gate `experiments/unification/w155/gate_deep.jl`; E-417 | — | — |
| C-92 | — | *Retired* (2026-11-15): the design has no rule of its own for a call that only throws; the question is [open issue 194](../open-issues.md#2-design) | — | — |
| C-93 | — | *Retired* (2026-11-15): no code slot, on `next` 9b6dacf5c5 ([§3.3](#33-one-compiled-code-per-result)); E-419 | — | — |
| C-100 | — | *Retired* (2026-11-15): inference reads an operation's declared result from the entries of the set's contract, `jl_set_contract_operations` (`next` 5448a8b7bf; [§4.1](#41-sets), [§7.1](#71-the-rule)); E-498 | — | — |
| C-101 | — | *Retired* (2026-11-15): a call of an owner-only function is a fact at any signature, on `next-s3` e483299622 ([§1.2](#12-fact-signatures)); E-458; what is left of it is C-130 | — | — |
| C-102 | [§7.6](#76-a-closed-build) | In a closed build an operation on a set with no member is a "no method" fact: the call raises `MethodError`. | The split's type is `nothing` where no candidate is of the receiver's type (`operation_split_type`: `n == 0 && return nothing`), so the call is left as a dynamic call, and the build's verifier refuses it: 38 of the ODE program's 50 errors, the solver core's callbacks in a program without them ([open issue 184](../open-issues.md#2-design) (a)). | `Compiler/src/abstractinterpretation.jl` (`operation_split_type`, `abstract_call_gf_by_type`'s operation branch) |
| C-103 | [§7.6](#76-a-closed-build) | In a closed build a call in the latest world is the call: `invokelatest(f, args…)` is inferred as `f(args…)`, and a call after `:latestworld` as any call. | Under the closed rules `Core.invokelatest` is inferred as the builtin's own call, its result unknown, and a call after `:latestworld` is not inferred (`si.saw_latestworld`). Julia's build script rebinds `Base.invokelatest` to a direct call, which the session's check does not read (traits T-109 (1), [open issue 181](../open-issues.md#2-design) (b)). | `Compiler/src/abstractinterpretation.jl` (`abstract_call_gf_by_type`: `si.saw_latestworld`; `abstract_call_known`), `Compiler/src/tfuncs.jl` (the builtins inference does not resolve); `contrib/juliac/` (the rebinding) |
| C-104 | — | *Retired* (2026-11-15): inside an invariant parameter no membership entry is consulted, on `next-s3` e967266d9e ([§4.5](#45-subtyping), [§4.9](#49-intersections)); gate `experiments/unification/w155b/gate_d11.jl`; E-456 | — | — |
| C-105 | — | *Retired* (2026-11-15): the runtime keeps what a definition ended of the deep class, on `next-s3` 5d2ec7ff85 ([§10.2](#102-hooks-for-strict-mode)); E-457 | — | — |
| C-106 | — | *Retired* (2026-11-15): a membership taken back, on `next-s3` 213c759370 (`jl_delete_membership`, `jl_membership_removal_walk`; [§4.3](#43-worlds), [§5.5](#55-a-membership-invalidates-as-a-method-does), [§5.6](#56-the-memberships-method-and-the-edges), [§9](#9-images-and-the-machine-code-cache)); E-459 | — | — |
| C-110 | — | *Retired* (2026-11-15): [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) is built for `new`, a store and a `typeassert` (`next` 5b1900641f, W-160); `isa` and `<:` are inference's folds | — | — |
| C-111 | [§6.3](#63-the-forwarders) | The forwarder records the method it forwards to, so that reflection shows one definition, and redefining or deleting the method takes its forwarders with it. | The two are ordinary methods of the table, entered in order by the expansion hook: `methods(f)` lists the method at the kept forms and its forwarder, both at the definition's line. A forwarder is found by a mark in its code (`Expr(:meta, :erasing_forwarder)`, TraitWorld's `_is_forwarder`), not by a record of its method. A redefinition makes both again at the same signatures and replaces them; a deletion of the method at the kept forms leaves its forwarder, which then calls a method that is gone (Revise). | `src/method.c` (`method_def`), `src/gf.c` (`jl_call_expansion_hook`); TraitWorld `src/erasing.jl` (`_expand_definition`, `_is_forwarder`); W-160 (b) |
| C-112 | [§2.1](#21-the-module-option), [§6.2](#62-how-an-argument-is-compiled), [§6.9](#69-the-kept-forms-in-core), [§7.6](#76-a-closed-build) | No attribute is resolved at a call: an argument is compiled as Julia compiles it; there is no cast, no `keep`, no `Core.attributed_call`; the module options are `facts`, `bounded`, `no_pirates`. | The attribute's machinery is built. A call's trait arguments carry attribute bits (`Compiler/src/stmtinfo.jl`), resolved at the method by five steps (`src/gf.c`: `effective_nospecialize`, `set_default_attribute`, `type_is_own`, `module_package`, `jl_attribute_sig`, `jl_attribute_dynamic_bits`, `jl_attributed_mi`). Casts lower to `Core.attributed_call` (`src/julia-syntax.scm`, `lower-cast-call`; `src/builtins.c`, `jl_f_attributed_call`, `attributed_call_reach`, its cache and table of latest calls), which inference (`abstract_attributed_call`, `attributed_matches`) and the inliner (`handle_attributed_call!`) resolve. `Core.compiled_for`, `Core.with_dynamic`, `Core._cast_compiled` and `Core.keep` are in `base/boot.jl`. The module options `dynamic` and `first_seen` are bits 4 and 8 of a module's flags (`src/module.c`; `base/experimental.jl`). So `@nospecialize` at a trait argument takes the attribute's run-time path (E-402: 829 ns a call), and a method at `Callable` takes `Dynamic` without a forwarder. A standard library's type is not Julia's own there (the subject of C-55). | the files named; removed in stage 4 of [the plan](../plans/2026-11-15-next-iteration.md) (W-156) |
| C-113 | [§6.9](#69-the-kept-forms-in-core), [§4.8](#48-negatives-fold-with-an-edge-positives-through-entries) | `Core` defines the box `Dynamic{X}` and the wrapper `Compiled{T}`; a box of `X` is itself, a box of a subset or a wrapper gives its object boxed; the box's membership test is `new`'s field test. | `Core` defines `Dynamic` only. Its constructor tests the membership in Julia code (`x isa X`), which inference folds at a known member with the entry recorded, and boxes a box anew, holding its object. The library adds the methods that make a box of the same trait itself and box a subtrait's box or a wrapper's object without the test (`(::Type{Dynamic{X}})(d::Dynamic{X})`, `_new_box` by `new`); a forwarder boxes by `new` in its own body. The wrapper is the library's `TraitWorld.Compiled` ([traits T-126](traits.md#19-deviations)). | `base/boot.jl` (`Core.Dynamic`); TraitWorld `src/compiled.jl`, `src/erasing.jl` |
| C-114 | [§7.6](#76-a-closed-build) | In a closed build a call whose method's static parameter a value known only by its trait binds (the wrapper's constructor) branches over the members; nothing else of the attribute applies. | The branches are made for a cast's `Core.attributed_call` (`unified` 5d8da002fa: `abstract_attributed_call` under `closed_build`), not for such a call. The closed build still turns steps 4 and 5 of the attribute to `Compiled` at a known type (`unified` 21c9b33e39), takes a call left to dispatch on a trait argument as `Dynamic` (ddc328b343), and the verifier refuses an attributed call (`verifytrim.jl`). | `Compiler/src/abstractinterpretation.jl` (`abstract_attributed_call`, `attributed_matches` with `closed_build`), `Compiler/src/verifytrim.jl`, `src/gf.c` (`effective_nospecialize`) |
| C-115 | [§6.7](#67-the-definition-time-check) | The check reads the method's instance at the box, the instance a box's call runs: inferred by the native interpreter, cached with its edges, kept by an image; nothing else infers for the check. | Where a box's call runs an instance at another signature (the attribute's instance at the trait, for a method of a trait without the default, C-112), or Julia's cache keeps no code, the library infers the instance apart (`check_at_box`: `Base.code_typed_by_type` with a `NativeInterpreter(world; facts = true)` of its own), as it infers each callee below a call that only throws. A later definition of a function it called does not check the method again; only a name not yet defined and the module's end do (`_check_pending_bounded`, `_end_pending_bounded`). Beside it the classification is still built: `Compiler.DefinitionCheckInterpreter` (an ephemeral cache, the library's hook at each known call) and the library's `classify`. | TraitWorld `src/atbox.jl` (`check_at_box`, `_box_instance`, `box_signature`, `_stand_in`), `src/classify.jl` (`classify`, `check_definitions`, `_decide_bounded`, the pending lists); `Compiler/src/types.jl` (`DefinitionCheckInterpreter`) |
| C-116 | — | *Retired* (2026-11-15): `Callable`'s members are entries, subtyping reads no method, the signature is checked at the box and at a wrapper's entry ([§7.4](#74-callables-call)); built on `next` eaa19da272 and TraitWorld `unified` c14d2e4 (W-161); what is short: C-146 | — | — |
| C-130 | [§1.2](#12-fact-signatures) | A later `public` or `export` of an owner-only function is the owner's change: it ends the code that relied on the function's being owner-only, through its binding edge. | Nothing ends: `public` sets the binding's flag without a new partition, and `export`'s new partition is no change to what inference reads of the binding (`invalidate_code_for_globalref!` compares the loads), so code that inferred a call at an abstract signature stays, and a method by another package that the status would now allow invalidates it as Julia's edges do (G1 holds; G2's claim that such code ends only by a stakeholder or a pirate fails for it). In a package the status is final before its code is compiled: `public` and `export` stand at the module's top. | `src/module.c` (`jl_module_public_`), `Compiler/src/bindinginvalidations.jl` |
| C-146 | [§6.3](#63-the-forwarders), [§7.4](#74-callables-call) | A wrapper at a `Callable{A, S}` argument is tested where it enters every method as written. | The library's hook answers the entry only where exactly one positional argument has a `Callable` component, written in the signature (not through a `where` variable's bound), the set's parameters given (not lifted, open issue 204's case), outside a keyword body; elsewhere a wrapper of a function with no method at `A` enters untested, and the error is the call's own `MethodError` where the method calls it (E-500). | TraitWorld `src/erasing.jl` (`_wrapper_entry`) |
