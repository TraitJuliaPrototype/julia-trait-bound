# Compiler and runtime: the reference

This page defines what Julia's compiler and runtime provide to the design: each interface, where it lives, what it means and its rules. It describes the interfaces as designed, including the parts not built yet. Each section says how far it is built.

- What compiled code may assume, and why each interface is needed, is in [`facts.md`](facts.md). This page states the semantics an interface implements and links there for the reason.
- How the trait language uses these interfaces is in [`lowering.md`](lowering.md).
- The inventory of the changes, with commits, files and upstream status, is [`../design/julia-changes.md`](../design/julia-changes.md).
- The patched Julia is `julia-1.13/`, branch `trait-world-1.13`, on v1.13.2. TraitWorld requires it.
- Terms as in the [glossary](../glossary.md). The ones this page relies on most:
  - a *fact* is a call signature that only its stakeholders or a pirate can change ([`facts.md`](facts.md#facts-and-fact-signatures));
  - a *run-time site* is a call compiled as a dynamic dispatch, with no edge;
  - a *cache owner* is the key under which Julia caches a `CodeInstance` (`CodeInstance.owner`); plain Julia's is `nothing`;
  - a *facts method* is a method whose code is always compiled by facts.

**Status labels.** Every section carries one:
- **Implemented:** in the patched Julia today.
- **Planned:** decided, not built.
- **Optional:** built only if a measurement or a demonstrator asks for it.
- **Open:** not decided. The link names the question.

Where the implementation differs from this page, the row in [Deviations](#deviations) says how.

## Summary

The interfaces follow four mechanisms. Mechanisms 1 and 2 are the facts compiler. Mechanisms 3 and 4 are general improvements to Julia that the facts mode made necessary. Around them are hooks the library needs, changes useful without traits, and one planned last step: traits in the type system.

| Mechanism | Implemented | Planned | Optional or Open |
|---|---|---|---|
| [1. Infer across a call only where a fact holds](#1-the-facts-inference-mode) | The facts mode of `NativeInterpreter`; `is_fact_sig`; run-time sites; the `return_type` rule; effects | Revalidating cached `return_type` answers after loads | Guarded devirtualization (Optional); standard libraries as owners of their own (Open) |
| [2. Code of two modes side by side, each under its own owner](#2-mode-and-owner-per-method) | The module option and `Method.facts`; owner `:facts`; dispatch from facts code; calls, inlining, edges and images across owners; `--trim` plain | One function for the mode and owner; an owner of its own for the test bed | A memo for the facts owner's normalization (Optional); facts code behind `jl_apply` (Open) |
| [3. Caches at dynamic boundaries are checked against the caller's world](#3-world-checked-caches-at-dynamic-boundaries) | `cfunction` convention `:caller_world`; exact-type and wildcard entries in the per-call-site cache | Entries with an open `max_world` | `Dynamic` beyond four implementations; a codegen-emitted cache (both Optional) |
| [4. Primitives for a specialized path beside a general one](#4-primitives-for-a-specialized-path-beside-a-general-one) | `Compiler.known_type`; `Compiler.dynamic_call` | — | — |
| [5. Hooks for the library](#5-hooks-for-the-library) | Definition hooks; field-offset intrinsics; type printers | Deletion hook, "would invalidate" query, image-validation report | — |
| [6. Changes useful without traits](#6-changes-useful-without-traits) | Two inliner changes; the run-time `return_type` entry in the image; reflection in the compiler's world; the dispatch profiler | Upstream proposals | — |
| [7. Traits in the type system](#7-traits-in-the-type-system) | — | Membership as subtyping, then syntax: last | — |

## Contents

1. [The facts inference mode](#1-the-facts-inference-mode)
2. [Mode and owner per method](#2-mode-and-owner-per-method)
3. [World-checked caches at dynamic boundaries](#3-world-checked-caches-at-dynamic-boundaries)
4. [Primitives for a specialized path beside a general one](#4-primitives-for-a-specialized-path-beside-a-general-one)
5. [Hooks for the library](#5-hooks-for-the-library)
6. [Changes useful without traits](#6-changes-useful-without-traits)
7. [Traits in the type system](#7-traits-in-the-type-system)
8. [Deviations](#deviations)

---

## 1. The facts inference mode

**The principle.** A call is inferred, with an edge, only at a fact. Every other call is a run-time site, dispatched when it runs. Code inferred this way is invalidated only by stakeholders and pirates ([`facts.md`](facts.md#the-guarantees)).

### 1.1 The interpreter

**Status: Implemented.**

```julia
Compiler.NativeInterpreter(world::UInt = get_world_counter();
                           inf_params = InferenceParams(), opt_params = OptimizationParams(),
                           facts::Bool = facts_default(), owner = nothing)
Compiler.cache_owner(interp::NativeInterpreter) = interp.owner
Compiler.facts_mode(interp::AbstractInterpreter)::Bool   # interp isa NativeInterpreter && interp.facts
```

Lives in `Compiler/src/types.jl` and `Compiler/src/facts.jl`.

**Meaning.**
- `facts`: whether this interpreter infers calls only at facts (§1.2). `false` is plain Julia's inference.
- `owner`: the cache owner of the code it infers and caches. `nothing` is plain Julia's cache; `:facts` is the cache of code compiled by facts beside plain code (§2.3).
- The two fields are independent. Under the test bed, the default owner `nothing` holds code compiled by facts (§2.3).
- Only `NativeInterpreter` has the mode. Any other `AbstractInterpreter` infers by its own rules: `facts_mode` is `false` for it.

**The process switch.**
- `Compiler.facts_default()` is the default of `facts`. It reads `jl_compile_by_facts()` (`src/gf.c`) once per process:
  - `JULIA_COMPILE_BY_FACTS=1` (any value but `0`): on;
  - `JULIA_COMPILE_BY_FACTS=0`: off;
  - unset: the system image's default. An image built with the switch on keeps it on (`FACTS_IMAGE`).
- With the switch on, every method not marked otherwise is compiled by facts under the default owner: *the test bed* (`all`). With it off, only facts methods are: *the product setting* ([`facts.md`](facts.md#the-test-bed)).
- `--trim` turns the switch off (§2.10).

**Rules.**
- A package image records the system image, not the switch. Package images built under the test bed belong in a depot of their own.

### 1.2 Fact signatures

**Status: Implemented.**

```julia
Compiler.is_fact_sig(T)::Bool          # T: a call's argument types, as a Tuple type
Compiler.MAX_FACT_SPLITS = 4
```

Lives in `Compiler/src/facts.jl`.

**Meaning.** `is_fact_sig(T)` is true when `T` is one of:
- a dispatch tuple (`isdispatchtuple(T)`);
- a tuple without a `Vararg` tail whose arguments are concrete, or tuple types whose elements are concrete or unions of concrete types, with at most `MAX_FACT_SPLITS` concrete tuples in all;
- a tuple of *concrete members* with a `Vararg{E}` tail of a concrete member `E`. A concrete member is a concrete type that is not a kind, or a tuple type of concrete members;
- a closure's call at kinds: the first argument is a closure type (its name is generated, `#…`), and every argument is concrete or one of `DataType`, `UnionAll`, `Union`.

A union at the top level of a call's arguments is split as Julia splits unions (`max_union_splitting`, four by default). Each split must be a fact signature.

Why exactly these are facts is defined in [`facts.md`](facts.md#facts-and-fact-signatures). The limit of four is Julia's own bound on union splitting.

### 1.3 Run-time sites

**Status: Implemented.**

```julia
Compiler.FACTS_ABSTRACT_SITE::FailedMethodMatch
InferenceState.facts_rtsite::Bool
```

Lives in `Compiler/src/facts.jl`, `abstractinterpretation.jl` (`find_method_matches`, `abstract_call_gf_by_type`), `inferencestate.jl`.

**Meaning.**
- Under the facts mode, a call whose signature, or one of whose union splits, is not a fact gets no method matches. It is a run-time site:
  - its result is `Any`, its exception type `Any`, its effects unknown;
  - it records no edge;
  - codegen emits a dynamic dispatch (§2.5).
- The frame records that it has a run-time site (`facts_rtsite`). §1.5 uses it.

**Rules.**
- A call at a fact is inferred as plain Julia infers it, with its edges, including constant propagation and concrete evaluation.
- The semantics of a run-time site, and what code around it may assume, are in [`facts.md`](facts.md#run-time-sites).

### 1.4 `return_type`

**Status: Implemented**, except where marked.

`Core.Compiler.return_type` asks what *plain* inference gives for a call. Its answer is observable: `collect` of a generator, `map` over an empty collection, broadcasting and `promote_op` use it. Under the facts mode the answer must be plain Julia's, in the same world ([`facts.md`](facts.md#return-type)).

```julia
Compiler.PlainRTInterp(world::UInt) <: AbstractInterpreter      # cache_owner: :facts_plain_return_type
Compiler.return_type_interp(world::UInt)                         # the interpreter of run-time queries
Compiler.facts_plain_return_type(interp, sig, sv)                # the compile-time fold
Compiler.PlainRTInfo(sigs, cis) <: CallInfo                      # its edges
```

Lives in `Compiler/src/facts.jl` and `tfuncs.jl` (`return_type_tfunc`); the run-time entry in `typeinfer.jl` (`return_type`).

**At compile time**, in facts code, `return_type_tfunc` decides in this order:
1. **The facts answer, when it cannot be wider than plain inference's:** a constant, a concrete type that is not a kind, or `Union{}`. It is folded, as plain Julia folds it.
2. **Plain inference's answer, when it rests on facts.**
   - The signature is split into at most `MAX_FACT_SPLITS` concrete signatures.
   - Each split must have exactly one matching method that covers it.
   - Plain inference answers each split in `PlainRTInterp`.
   - Every edge of every answer, transitively, must be at a fact signature, or a call edge at the method's own signature. Bare MethodInstance edges and method-table edges disqualify it.
   - The merged answer is folded, with an edge (`PlainRTInfo`) from the facts code to each plain answer. A load that changes plain Julia's answer invalidates the folded code.
3. **Otherwise, a call at run time.**

**At run time**, `return_type` calls `_return_type(return_type_interp(world), tt)` in the compiler's world. Under the test bed, `return_type_interp` is `PlainRTInterp`. Otherwise it is a plain `NativeInterpreter`.

**The answer cache.** `PlainRTInterp`'s owner is `:facts_plain_return_type`. No code is ever generated from it. It holds only plain answers, so no plain code enters a cache that facts code is compiled from.

**Rules.**
- `PlainRTInterp` is not a `NativeInterpreter`, so it infers every method plainly, facts methods included (§2.6).
- An answer is the same as plain Julia's in the same world. Across worlds it moves exactly when plain Julia's does.

**Planned: revalidation after loads.** When a load invalidates a cached answer, the answer's edges are checked bottom-up, and an answer whose inputs did not change is kept instead of inferred again (red-green revalidation). A differential test against stock Julia comes first: every logged query, answered by both, must give identical answers before and after the loads ([`../plans/2026-10-19-return-type-after-loads-plan.md`](../plans/2026-10-19-return-type-after-loads-plan.md) §3).

### 1.5 Effects

**Status: Implemented.**

Lives in `Compiler/src/typeinfer.jl` (`adjust_effects(ipo_effects, def, frame)`) and `abstractinterpretation.jl` (`merge_override_effects!`).

**Meaning.** Under the facts mode, no asserted effect applies to a frame with a run-time site:
- a method's `@assume_effects` is ignored for that frame's effects;
- a statement's `@assume_effects` is ignored once the frame has a run-time site.

**Why.** An assertion would let a caller fold a call whose dispatch no edge records ([`facts.md`](facts.md#asserted-effects)).

### 1.6 Further work on mechanism 1

- **Optional: guarded devirtualization at run-time sites.** A run-time site would call a guessed target behind a type check. Only if untyped code under the test bed still matters after the other work.
- **Open: standard libraries as owners of their own.** Today Julia's standard libraries count as Julia's own code, so a standard library's method that wins at a fact is a stakeholder's change ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).

---

## 2. Mode and owner per method

**The principle.** Code of both modes lives side by side, each with its own cache owner, caches, edges and images. Which mode and owner a method's code gets follows from the method and the mode that reaches it, never from a particular caller. A call from one mode into the other crosses explicitly. What each kind of code may assume is in [`facts.md`](facts.md#which-code-is-compiled-how).

### 2.1 The module option

**Status: Implemented.**

```julia
module M
Base.Experimental.@compiler_options facts=true      # or facts=false
end
```

Lives in `base/experimental.jl`, `src/interpreter.c`, `src/module.c`.

**Meaning.**
- `facts=true` (also `:yes`) makes every method of the module a facts method, unless the method says otherwise (§2.2).
- `facts=false` (also `:no`) turns the option off.
- The macro emits `Expr(:meta, :facts, 1)` or `Expr(:meta, :facts, 0)` at the module's top level. Evaluating it sets the module's flag.

**The module flag** (`jl_module_t.facts`):

| Value | Meaning | Set by |
|---|---|---|
| 0 | plain (the default) | `facts=false`, or nothing |
| 1 | facts | `facts=true` |
| 2 | never by facts: compiled plainly whoever calls it | `jl_set_module_facts(Compiler, 2)`, at the Compiler's start |

```c
void jl_set_module_facts(jl_module_t *m, int value);   // 0, 1 or 2
int  jl_get_module_facts(jl_module_t *m);              // 1 when the flag is 1
```

**Rules.**
- A submodule takes its parent's flag when it is created. So a submodule defined after the option inherits it.
- Flag 2 is for the compiler's own code (§2.6). No Julia-level syntax sets it.
- `@trait_module` declares `facts=true` ([`traits.md` §2](traits.md#2-trait-modules)).

### 2.2 The method flag: boundaries and always-facts methods

**Status: Implemented.**

A macro puts the meta first in a method's body, as `@inline` puts `Expr(:meta, :inline)` there:

```julia
macro boundary(fdef)       # compiled in the mode of the code that reaches it
    pushfirst!(fdef.args[2].args, Expr(:meta, :facts, 0)); esc(fdef)
end
macro always_facts(fdef)   # always compiled by facts
    pushfirst!(fdef.args[2].args, Expr(:meta, :facts, 1)); esc(fdef)
end
```

Lives in `src/method.c` (`jl_method_set_source`), `src/ast.scm`, `src/julia-syntax.scm`, `src/module.c`.

**The method flag** (`Method.facts::UInt8`):

| Value | Meaning | Written as |
|---|---|---|
| 0 | as its module's flag says | (nothing) |
| 1 | a boundary: compiled in the mode of the code that reaches it | `Expr(:meta, :facts, 0)` |
| 2 | always facts | `Expr(:meta, :facts, 1)` |

```c
int jl_method_is_facts(jl_method_t *m);   // flag 2, or flag 0 in a module of flag 1; 0 under --trim
int jl_method_is_plain(jl_method_t *m);   // flag 0 in a module of flag 2
```

**Rules.**
- Lowering carries the meta into every method a definition lowers to: the keyword sorter and the positional forwarders of default arguments.
- The meta may be merged with other metas, as `pushmeta!` merges `@inline`'s. It is still found.
- The same `Expr(:meta, :facts, n)` means the module option at a module's top level (§2.1) and the method flag in a method body. Inside a body, `0` means "boundary", not "plain".
- TraitWorld marks entries as boundaries and its machinery as always facts ([`lowering.md`](lowering.md#82-the-entry)).

### 2.3 The owners, and the mode and owner of a MethodInstance's code

**Status: Implemented**, except the single function (**Planned**) and the test bed's own owner (**Planned**).

Three cache owners:

| Owner | Holds | Code generated from it |
|---|---|---|
| `nothing` | plain Julia's code; under the test bed, code compiled by facts too | yes |
| `:facts` (`Compiler.FACTS_OWNER`) | code compiled by facts beside plain code | yes |
| `:facts_plain_return_type` | plain answers for `return_type` (§1.4) | never |

**The rule.** The mode and owner of the code for a MethodInstance `mi`, reached from code of a given mode:

| `mi`'s method | Product setting | Test bed |
|---|---|---|
| a facts method (§2.2) | facts, `:facts` | facts, `:facts` |
| never by facts (flag 0 in a module of flag 2) | plain, `nothing` | plain, `nothing` |
| a boundary (flag 1) | the mode and owner that reach it | the mode and owner that reach it |
| any other method, reached from plain code or from the runtime | plain, `nothing` | facts, `nothing` (Planned: facts, the test bed's owner) |
| any other method, reached from facts code | facts, `:facts` | facts, the owner that reaches it |

So an ordinary method has one copy per mode that reaches it. A facts method has only facts code, and the compiler's code only plain code.

**Planned: one function.** One function returns the mode and owner of a MethodInstance's code, given the mode and owner that reach it. Every place that infers, compiles, dispatches, inlines or caches code asks it:
- the single-request entry from the runtime (§2.4);
- the compile queues, including the one that builds images (§2.4);
- calls between the modes in inference (§2.6);
- the runtime's dispatch from facts code (§2.5);
- the inliner's lookup of the other owner's code (§2.7).

It uses one predicate for "the compiler's code": the module flag 2. Its name is not fixed. Today the rule is decided in several places ([C-1](#deviations)).

**Planned: an owner of its own for the test bed.** Under the test bed, code compiled by facts gets an owner of its own, so it never shares a cache with plain code (the compiler, and the Base methods the compiler calls). Today they share the default owner's cache ([C-2](#deviations)).

### 2.4 Compile requests

**Status: Implemented.**

```c
jl_value_t *jl_default_owner(jl_method_instance_t *mi);   // :facts for a facts method, else nothing
jl_code_instance_t *jl_type_infer(jl_method_instance_t *mi, size_t world, uint8_t source_mode, uint8_t trim_mode);
```

```julia
Compiler.typeinf_ext_toplevel(mi, world, source_mode, trim_mode, owner)   # the runtime's entry (jl_typeinf_func)
Compiler.typeinf_ext(interp, mi, source_mode)
Compiler.interp_for_owner(interp, owner)       # the interpreter for a queue item of owner `owner`
Compiler.interp_for_mi(interp, owner, mi)      # the same, with the compiler's code plain under the test bed
Compiler.default_owner(mi)
```

Lives in `src/gf.c`, `Compiler/src/typeinfer.jl` and `Compiler/src/facts.jl`.

**Meaning.**
- The runtime asks for code of an owner. `jl_type_infer` asks for `mi`'s default owner. The runtime's other entries take the owner explicitly (§2.5).
- The single-request entry builds the interpreter of that owner: facts under `:facts`; under `nothing`, facts under the test bed except for the compiler's code.
- `typeinf_ext` hands a facts method to a facts interpreter, whoever asks (reflection, compile queues).
- A compile queue holds `CodeInstance`s of both owners. Each item is inferred by the interpreter of its own owner (`interp_for_owner`). Under the test bed, the compiler's code in a queue is inferred plainly (`interp_for_mi`).
- Reflection shows the code that runs: `typeinf_frame` infers a facts method by facts.

### 2.5 Dispatch from facts code

**Status: Implemented** for the calls codegen emits. **Open** for dispatch through the runtime's `jl_apply`.

```c
jl_value_t *jl_apply_generic_facts(jl_value_t *F, jl_value_t **args, uint32_t nargs);
jl_value_t *jl_invoke_facts(jl_value_t *F, jl_value_t **args, uint32_t nargs, jl_method_instance_t *mi);
```

Lives in `src/gf.c` and `src/codegen.cpp` (`applygeneric_for`, `invoke_for`).

**Meaning.**
- Code of owner `:facts` calls these at its run-time sites instead of `jl_apply_generic` and `jl_invoke`.
- They do the same method lookup, with the same caches (§3.2). They then run the callee's code of owner `:facts`, compiled on a miss. The exception is a method never by facts, which runs its plain code.
- Codegen emits them for:
  - direct calls;
  - `invoke` of a MethodInstance;
  - `_apply_iterate` and `_apply` with known tuples;
  - `invokelatest` and `invoke_in_world`;
  - `modifyfield!` and its kin through `:invoke_modify`.
- Dispatch on a narrow MethodInstance runs the code of the wider instance Julia compiles for it.

**Open: facts code behind `jl_apply`.** Dispatch through the runtime's `jl_apply` runs plain code:
- splats of unknown length;
- the `invoke` builtin at run time;
- `jl_call`;
- `@cfunction` callbacks, including `:caller_world` pointers (§3.1);
- finalizers and task entry.

This computes the same results. The plain code reached this way is plain Julia's, with plain Julia's validity. Whether these should run facts code is not decided (the review of 2026-10-19, [`../reviews/2026-10-19-compiler-implementation.md`](../reviews/2026-10-19-compiler-implementation.md) §2.4; no entry in [`../open-issues.md`](../open-issues.md) yet).

**Optional: a memo for the facts owner's normalization.** A call that arrives with a narrow MethodInstance looks up the wider instance's code on every call ([C-4](#deviations)). No measured workload reaches it. If one does, the fix is a memo from the narrow instance to the wider one's code, which invalidation of the wider code clears.

### 2.6 Calls between the modes in inference

**Status: Implemented.**

```julia
Compiler.leaves_to(interp, method)    # the interpreter `method`'s code belongs to, or nothing
Compiler.facts_edge(interp, other, method, mi, caller, edgecycle, edgelimited)
Compiler.is_facts_method(m), Compiler.is_plain_method(m)
```

Lives in `Compiler/src/facts.jl`, `typeinfer.jl` (`typeinf_edge`), `abstractinterpretation.jl`.

**Meaning.** When inference reaches a method whose code belongs to the other mode (§2.3):
- the callee is inferred by the other interpreter, in an inference of its own, as a request from the runtime would be (`facts_edge`);
- the call names that `CodeInstance`, with an edge to it;
- the caller does not propagate constants into it, nor evaluate it concretely.

Neither owner infers the other's methods by its own rules.

**The compiler is plain.**
- The Compiler module has flag 2 (§2.1). Its submodules inherit it.
- A facts frame's call into the compiler leaves to plain inference. A facts caller of `Compiler.typeinf_frame` would otherwise compile the abstract interpreter by facts.
- Code compiled by facts dispatches to the compiler's plain code (§2.5).
- **The boundary:** facts code that calls compiler functions directly (TraitWorld calls `argextype`, `widenconst`, `sptypes_from_meth_instance`) holds edges to plain compiler code. Its validity there is plain Julia's ([`facts.md`](facts.md#which-code-is-compiled-how)). Running such calls in the compiler's world instead would break code that extends the compiler for its own interpreter types.

**Rules.**
- `leaves_to` applies only to `NativeInterpreter`. It leaves to facts only from the plain owner `nothing`, never from another owner's interpreter.
- Other interpreters (`PlainRTInterp`, TraitWorld's checking interpreter, Cthulhu-style tools) infer facts methods by their own rules in their own caches.

### 2.7 Inlining across owners

**Status: Implemented.**

Lives in `Compiler/src/ssair/inlining.jl` (`handle_invoke_expr!`, `resolve_todo`, `compileable_specialization`) and `stmtinfo.jl` (`add_inlining_edge!`).

**Meaning.**
- **An `:invoke` of a given `CodeInstance` of another owner** inlines exactly that code (piece 10). The caller's own cache may hold different code for the same MethodInstance. Inlining it would run code the call never asked for.
- **A call to a method whose code belongs to the other owner** (§2.6) inlines that owner's cached code. Both `resolve_todo(mi, …)` look it up there when the caller's own cache misses.
- When not inlined, the call is an `:invoke` of the other owner's `CodeInstance`.

**Rules.**
- Inlining does not infer again. The inlined code stays the other owner's, with an edge to its `CodeInstance` only.
- Edges to two `CodeInstance`s of the same MethodInstance with different owners are two edges (`add_inlining_edge!` compares the owner). Each is invalidated separately.

### 2.8 Edges for a second owner

**Status: Implemented** (piece 9).

Lives in `src/gf.c` (`_invalidate_backedges`).

**Meaning.** When one `CodeInstance` is invalidated, a caller whose edge names only the MethodInstance is invalidated only if:
- the caller has the same owner; or
- the caller is a generator's cached output (owner `:uninferred`), which may have read any owner's result.

Replacing the method itself reaches callers of every owner.

**Why.** A bare MethodInstance edge stands for the caller's dependence on its own interpreter's result for that instance. An interpreter consults only its own cache. So only a `CodeInstance` of the caller's owner can break it ([`facts.md`](facts.md#edges-and-invalidation)).

### 2.9 What package images keep

**Status: Implemented** (piece 5, and facts copies without source).

```c
void jl_set_image_keep_compiled(int on);    // for the image being built in this process
```

Lives in `src/staticdata_utils.c` (`queue_external_cis`) and `Compiler/src/precompile.jl` (`compile_and_emit_native`).

**Meaning.**
- **Code of other owners in the package's own methods** is compiled into the image from its cached IR. Calls between such `CodeInstance`s are `:invoke`s of them.
- **Code of owner `:facts`** goes through the compile queue, as plain code does. The queue infers it again by facts where its inferred source was discarded.
- **With keep-compiled on:**
  - a `CodeInstance` of an upstream method, compiled during precompilation and reached by no call of the package that Julia can see (a dynamic call, `invokelatest`, a call from upstream code the workload ran), is kept with its machine code;
  - code of owner `:facts` whose inferred source was discarded is kept too.
- Without keep-compiled, Julia drops such code, as stock Julia does.

**Rules.**
- TraitWorld switches keep-compiled on while a package that uses it is precompiled ([`lowering.md`](lowering.md#2-modes-owners-and-images)).

### 2.10 `--trim`

**Status: Implemented.**

Lives in `src/module.c` (`jl_method_is_facts`), `src/gf.c` (`jl_compile_by_facts`), `src/staticdata.c` (`jl_write_module`, `jl_write_values`).

**Meaning.** A trimmed binary is plain code.
- While a trimmed image is built, no method is a facts method and the switch is off. Every method is inferred plainly.
- The image writes no facts flags: every module's flag is 0, and every method flag that was not 0 becomes 1 (a boundary, so the caller's mode, which is plain).

**Why.** A trimmed binary is a closed world: nothing loads later, so plain code keeps its guarantees ([`facts.md`](facts.md#trimmed-binaries)).

---

## 3. World-checked caches at dynamic boundaries

**The principle.** Every cache that skips a dispatch at run time holds world ranges and is checked against the caller's world, as Julia's method cache already is. A cache never decides which method runs. It only remembers what dispatch decided, for the worlds where that holds.

### 3.1 The `cfunction` calling convention `:caller_world`

**Status: Implemented** (piece 18), with entries capped at the latest world ([C-3](#deviations)).

```julia
Expr(:cfunction, Ptr{Cvoid}, QuoteNode(f), rettype, :(Core.svec(argtypes...)), QuoteNode(:caller_world))
```

`@cfunction` has no argument for the convention. Code writes the expression, as TraitWorld's `Callable` does ([`lowering.md`](lowering.md#12-callable-and-dynamicfn)). Lives in `src/codegen.cpp` (`emit_cfunction`, `emit_abi_call`) and `src/runtime_ccall.cpp` (`jl_get_abi_converter_caller_world`).

**Meaning.**
- A call through the pointer runs in the caller's world (the task's world age), as a direct call does. A plain `@cfunction` runs in the latest world, as a callback from C must.
- The pointer's thunk is a world-checked call-site cache:
  - each target the thunk has called is an entry: a function pointer, its `CodeInstance`, and a range of worlds;
  - the range is where both hold: the dispatch of the signature (`jl_get_specialization1_worlds`), and the target's `CodeInstance`;
  - a call whose world is in the current entry's range calls it directly;
  - any other call looks for an entry of its world, or looks the target up in its world and adds one.
- A thread with no world (a C callback) uses the latest world.
- A signature that one method covers only in part dispatches dynamically, in the caller's world.

```c
jl_value_t *jl_get_specialization1_worlds(jl_tupletype_t *types, size_t world,
                                          size_t *min_valid, size_t *max_valid);
```

The MethodInstance for `types` in `world`, with the range of worlds where that answer holds, or `nothing` when the dispatch is not unique.

**Rules.**
- Entries are never freed. There is one per target, and targets are rooted by their MethodInstances' caches.
- The callee's code is the default owner's: a facts method's facts code, any other method's plain code (§2.5).

### 3.2 The per-call-site dispatch cache

**Status: Implemented**, with exact-type entries capped at the latest world ([C-3](#deviations)).

Julia's `call_cache` (`src/gf.c`) holds method-cache entries per call site, keyed by the call's return address. Stock Julia puts only leaf signatures there. The patched build adds two kinds of entries, for every dynamic call, plain and facts.

**Wildcard entries** (`call_cache_any_ok`, `sig_match_any`):
- A method-cache entry qualifies when:
  - its signature is not a leaf signature, has no `Vararg`, no type variables, and no guard signatures;
  - its parameters are concrete types (not kinds, not `Type{…}`) or `Any`, with at least one `Any`, and the function's own type concrete;
  - its simple signature, if any, is implied by the signature.
- The site holds the method-cache entry itself. A call matches it when every non-`Any` position has exactly the argument's type.
- Its world range is the entry's own, so invalidation lowers it.

**Exact-type entries** (`call_cache_exact`):
- For any other entry that is not a leaf signature (a `@nospecialize` method, guard signatures, `Any` in the signature), the site gets a new entry for the call's exact argument types, mapping to the same MethodInstance.
- It is matched by exact types only.
- Its range runs from the method-cache entry's first world to its last, capped at the latest world when the entry is made.
- No entry is made when the function or an argument is a type, since a type argument is matched as `Type{T}`, not by its type.

**Rules.** A site cache entry never outlives what it copies: a call in a world outside its range looks up again.

### 3.3 Further work on mechanism 3

- **Planned: entries with an open `max_world`.** An exact-type entry and a `:caller_world` entry refer to the method-cache entry and the `CodeInstance` they copy, whose `max_world` invalidation lowers. A hit compares the world with both ranges. A method definition then costs a cached site nothing unless it invalidates what the site calls ([C-3](#deviations)).
- **Optional: `Dynamic` beyond four implementations.** Raise the split limit for `dynamic_call` only (§4.2), or put a per-site table of types and `:caller_world` pointers at the split's fallback. When a demonstrator has five implementations.
- **Optional: a codegen-emitted cache with direct calls.** Only if profiles show lookup, not the call or the callee, dominating.
- **Not planned:** a hook by which a package substitutes the target of a call, for untyped trait calls.

---

## 4. Primitives for a specialized path beside a general one

**The principle.** Library code may write two paths that compute the same result. The compiler picks one from what inference knows. The choice changes speed, never the result.

### 4.1 `Compiler.known_type`

**Status: Implemented.**

```julia
Compiler.known_type(x)::Bool
```

Lives in `Compiler/src/facts.jl` and `abstractinterpretation.jl` (`abstract_call_known`).

**Meaning.**
- Where a call is compiled, inference folds it to whether it knows `x`'s concrete type there: a constant, with total effects.
- Where it is not folded (the interpreter, code compiled at abstract types), it is `false`.
- GCC's `__builtin_constant_p`, for types.

**Rules.**
- Code branches on it only between paths that compute the same result. Anything else makes a result depend on how the code was compiled.
- TraitWorld's entry takes the inlined path for typed callers and the table of declared implementations where the type is not known ([`lowering.md`](lowering.md#82-the-entry)).

### 4.2 `Compiler.dynamic_call`: the call-site split

**Status: Implemented** (part D).

```julia
Compiler.dynamic_call(K, ::Type{RT}, f, x, args...)          # f(x, args...)::RT
Compiler.register_dynamic_candidate!(K, C)                    # C: a candidate type of K
Compiler.dynamic_candidates(K)::Vector{Any}                   # the first MAX_FACT_SPLITS registered
```

Lives in `Compiler/src/facts.jl` (`abstract_dynamic_call`, `DynamicSplitInfo`), `ssair/inlining.jl` (`process_simple!`, `compute_inlining_cases`, `ir_inline_unionsplit!`), `stmtinfo.jl`. Not to be confused with TraitWorld's `dynamic_call(f)`, a `Callable` mode.

**Meaning.** `dynamic_call(K, RT, f, x, args...)` is `f(x, args...)` where `x` is a value of an open set of types, the candidates registered for `K`.
- **Inference.** When `x`'s type is not concrete and `K` has candidates, `f` is inferred at `x`'s type intersected with the union of the candidates. Each split is a fact, with its edge.
- **The split.** The inliner rewrites the statement to the call of `f` and splits it over the candidates, with the dynamic call as the last branch. The split is never "fully covered": a value of another type reaches the fallback.
- **The result.** The fallback's result, and any case not known to be an `RT`, is asserted to `RT`. The join is typed `RT`.
- **No edge to the registry.** Candidates are read without an edge. A type registered later reaches the fallback, and invalidates nothing.
- When `x`'s type is concrete, or `K` has no candidates, it is the call `f(x, args...)` as inference finds it.

**Rules.**
- At most `MAX_FACT_SPLITS` candidates are split: the first four registered. Later ones reach the fallback.
- Which candidates a caller splits over is fixed when the caller is compiled. A caller compiled before a candidate is registered keeps the smaller split.
- Registration is lock-free for readers: the table is replaced on each registration, never mutated.
- How TraitWorld uses it for `Dynamic{X}` is in [`lowering.md`](lowering.md#13-dynamicx); what code may assume about it, in [`facts.md`](facts.md#run-time-sites).

---

## 5. Hooks for the library

### 5.1 Method-definition and image-activation hooks

**Status: Implemented** (piece 1).

```c
void jl_set_method_definition_hook(jl_value_t *hook);   // hook(m::Method, after::Bool); nothing removes it
void jl_set_image_methods_hook(jl_value_t *hook);       // hook(ms::Vector{Any}, pkg::String) -> methods to leave inactive, or nothing
```

Lives in `src/gf.c` (`jl_method_table_insert`, `jl_run_image_methods_hook`) and `src/staticdata.c`, `src/staticdata_utils.c` (`jl_activate_methods`).

**Meaning.**
- **The definition hook** is called twice per method definition:
  - with `after = false` before the method enters the method table. It may throw to refuse the definition: the method then never becomes visible and no world is allocated;
  - with `after = true` once the method is visible.
- **The image hook** is called once per package image, with the image's methods that extend functions of other modules, before any is activated. Methods in the vector it returns stay inactive: they never become visible.

**Rules.**
- Both run in the latest world, outside the world-counter lock.
- Neither runs for a definition a hook itself makes.
- The definition hook does not run while the system image is built.
- If the image hook throws, Julia warns and activates every method.
- The caller roots the hook functions.
- Strict mode uses both ([`traits.md` §12](traits.md#12-who-may-implement-pirates-strict-mode)).

### 5.2 Field-offset intrinsics

**Status: Implemented** (piece 3), except fields stored inline that hold references ([C-7](#deviations)).

```julia
Core.Intrinsics.getfield_at_offset(obj, T::Type, off::Int)::T
Core.Intrinsics.setfield_at_offset(obj, T::Type, off::Int, x)::Nothing
```

Lives in `src/intrinsics.cpp`, `src/runtime_intrinsics.c`, `Compiler/src/tfuncs.jl`.

**Meaning.**
- `getfield_at_offset` reads the value of type `T` stored at byte offset `off` of `obj`: the bits of an isbits `T`, or a reference.
- `setfield_at_offset` stores `x` there. It checks `x isa T` (a `TypeError` otherwise) and applies the write barrier for a reference.
- Codegen emits the load or store with the alias metadata of a mutable field, so loops that read it while storing into an array still vectorize. A reference is loaded as a tracked pointer and checked for null (`UndefRefError`).
- The result type is `T` when `T` is a known constant, else `Any`.

**Rules.**
- The offset is not checked. The caller guarantees that `obj`'s type has a field of type `T` at `off`, as with `pointerref`.
- `getfield_at_offset` reads mutable memory: it is not `:consistent`. `setfield_at_offset` is not effect-free.
- Codegen emits the inline form when `T` is a constant, `off` an `Int` and `obj` held by reference. Otherwise it calls the runtime.
- Trait objects read the user's object through them ([`lowering.md`](lowering.md#6-trait-objects-layout-fields-writes)).

### 5.3 Type printers

**Status: Implemented** (piece 17).

```julia
Base.Experimental.register_type_printer(name::Core.TypeName, printer)   # printer(io, T); nothing removes it
Base.Experimental.show_type_plain(io::IO, T::Type)
```

Lives in `base/experimental.jl` and `base/show.jl` (`_show_type`).

**Meaning.**
- Every type whose name is `name` prints by `printer(io, T)`, wherever Julia prints a type: by `show`, nested in other types, in method signatures and stack traces.
- `show_type_plain` prints `T` as Julia does without a printer. Parameters of `T` still print through their own printers.

**Rules.**
- Registering a printer invalidates no compiled code. A method `show(::IO, ::Type{<:X})` would invalidate every caller compiled for `show(::IO, ::Type)`.
- The printer is called with `invokelatest`.
- The registry is copy-on-write: readers take no lock.
- TraitWorld prints trait objects by bound and key with it ([`traits.md` §14](traits.md#14-printing)).

### 5.4 Planned: hooks for strict mode's intended design

**Status: Planned.** Strict mode's intended design ([`../explorations/strict-mode.md`](../explorations/strict-mode.md) §2b; [open issues §1.1, §1.10](../open-issues.md#1-decisions-waiting-for-the-user)) needs three more pieces:
- **A deletion hook (1′):** called at method deletion (`jl_method_table_disable`). It may refuse.
- **A "what would this definition invalidate" query (14):** read-only and transitive. It is `jl_method_table_insert`'s invalidation walk without the stores, asked from the definition hook before the method becomes visible.
- **Image validation that reports the winning method (15):** when validation rejects a `CodeInstance` of a package image, it reports the edge and the method that now wins.

---

## 6. Changes useful without traits

Each of these applies to all code, plain Julia's included.

**Planned:** propose them upstream; the two inliner changes after broader measurement in plain Julia. Their upstream status is in [`../design/julia-changes.md` §4](../design/julia-changes.md#4-upstream-status).

### 6.1 An invoke keeps the exact specialization over a widened varargs tail

**Status: Implemented.**

Lives in `Compiler/src/ssair/inlining.jl` (`compileable_specialization`, `only_vararg_widened`).

**Meaning.**
- When the inliner emits an `:invoke` for a call inferred at a dispatch tuple, it normally invokes the compileable signature.
- When the compileable signature only widens a varargs tail to `Vararg`, and the exact specialization has code in the cache, the invoke names the exact specialization.
- Otherwise the widened specialization would be inferred again at `Any` arguments and box every argument.

**Rules.** Julia's other widenings stay: a type or a function passed to an argument that does not specialize on it. They keep the number of compiled specializations small.

### 6.2 An inference cycle's members inline each other

**Status: Implemented.**

Lives in `Compiler/src/typeinfer.jl` (`finish_cycle`) and `optimize.jl` (`InliningState.cycle_results`).

**Meaning.**
- When an inference cycle finishes, its members are optimized callees first: the frames after a caller, before it.
- Each optimized member is offered to the inliner of the members optimized after it.
- A recursion through wrappers then keeps one call per turn, at the edge back to an earlier frame, instead of one call per member.

### 6.3 The run-time `return_type` entry in the system image

**Status: Implemented.**

Lives in `Compiler/src/bootstrap.jl`.

**Meaning.** `_return_type(::NativeInterpreter, ::DataType)` is a compiler bootstrap entry, so the system image holds its code. Otherwise the first `collect` of a generator or `map` over an empty collection in every session compiles it.

### 6.4 Reflection in the compiler's world

**Status: Implemented.**

Lives in `base/reflection.jl` (`invoke_interp_compiler`).

**Meaning.** Reflection with an explicit `NativeInterpreter` (`code_typed(f, types; interp)` and its kin) runs the native compiler in the compiler's world, as reflection without one does. It applies when no reflection compiler is set.

**Why.** Otherwise the compiler runs in the latest world, on code that later definitions invalidate.

### 6.5 The dispatch profiler

**Status: Implemented.** A tool, off by default.

```sh
JULIA_FACTS_DISPATCH_PROFILE=1 julia …
```

```c
void jl_facts_dispatch_profile_reset(void);   // zero the counts, to profile one region
void jl_facts_dispatch_profile_print(void);   // print now; it also prints at exit
```

Lives in `src/gf.c`.

**Meaning.** It counts dynamic calls:
- **per callee method,** by the path the lookup took (the per-call-site cache, the leaf cache, the method cache's search, the full lookup), separately for calls from code of owner `:facts` and from code of the default owner;
- **per call site,** by the calling code's return address and the callee.

At exit it prints the 40 methods and the 40 call sites with the most calls.

**Rules.** Off, it costs one load and a branch per dynamic call.

---

## 7. Traits in the type system

**Status: Planned, last** (pieces 7 and 8, [`../explorations/julia-support.md`](../explorations/julia-support.md)).

**The intended shape:**
- **Membership as subtyping,** by declaration after the type is defined: `T <: ColTable`, `x isa ColTable` ([`traits.md` §16](traits.md#16-membership)).
- **A trait bound as a dispatch tier** above `Any` and below every type.
- **Entries and workers generated by the compiler.**
- **Syntax** (piece 8): `trait`, `implement`, `Self`, a trait's name in a field meaning its `Dynamic`, bounds in `where` clauses.

**Why last.** It removes the encodings TraitWorld needs today: entry methods at `Any`, tags for trait sets, sentinel methods, `conforms`. It changes the type system, so it comes once the demonstrators' numbers support the proposal.

---

## Deviations

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-1 | [§2.3](#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code) | One function decides the mode and owner of a MethodInstance's code, with one predicate for the compiler's code (module flag 2). | Six places decide it: the single-request entry, `interp_for_owner`, `interp_for_mi`, `leaves_to`, and the runtime's `jl_default_owner` and `facts_callee_owner`. Two predicates: the module flag (`jl_method_is_plain`) and a module walk (`is_compiler_code`). They differ for a boundary or always-facts method inside the Compiler. A queue that missed the rule compiled the compiler by facts under the test bed (fixed in f13117cd74). | `Compiler/src/typeinfer.jl:1654`; `Compiler/src/facts.jl:47`, `:69`, `:85`, `:105`; `src/gf.c:424`, `:4802`; `src/module.c:749` |
| C-2 | [§2.3](#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code) | Under the test bed, code compiled by facts has an owner of its own. | It shares the default owner `nothing` with plain code (the compiler, and the Base methods the compiler calls). A Base method called by the compiler can reuse a result compiled by facts: correct, but slower. | `Compiler/src/facts.jl:52`, `:60`, `:87`; `Compiler/src/typeinfer.jl:1658` |
| C-3 | [§3.1](#31-the-cfunction-calling-convention-caller_world), [§3.2](#32-the-per-call-site-dispatch-cache) | A cached entry stays valid until invalidation lowers what it copies. | Exact-type entries and `:caller_world` entries are capped at the latest world when made. After any method definition, every such cached site misses once and looks up again. Wildcard entries are not capped. | `src/gf.c:4610`; `src/runtime_ccall.cpp:424` |
| C-4 | [§2.5](#25-dispatch-from-facts-code) | Dispatch for the facts owner caches its answer as for the plain owner. | A call that arrives with a narrow MethodInstance normalizes to the wider one on every call. The plain owner copies the wider code onto the narrow instance; the facts owner keeps nothing. | `src/gf.c:3732` |
| C-5 | [§2.5](#25-dispatch-from-facts-code) | Code of owner `:facts` is found under that owner. | Where compilation is off (`--compile=min`) or the method has no source, the facts owner's fallback makes an owner-`nothing` copy of the unspecialized code. The `:facts` lookup misses it on every call and makes it again. | `src/gf.c:3782` ff. |
| C-6 | [§2.1](#21-the-module-option) | A module's other compiler options apply to its code in both modes. | The module option `compile` (`min`, `no`) is ignored for code of owner `:facts`. | `src/gf.c:3775` |
| C-7 | [§5.2](#52-field-offset-intrinsics) | The intrinsics read and write a field of any stored type. | A field stored inline whose type holds references is refused with an error, in codegen (runtime call) and in the runtime. | `src/runtime_intrinsics.c` (`jl_getfield_at_offset`, `jl_setfield_at_offset`); `src/intrinsics.cpp` (`emit_getfield_at_offset`) |
| C-8 | [§4.2](#42-compilerdynamic_call-the-call-site-split) | `dynamic_call(K, RT, f, x, args...)` is `f(x, args...)::RT` on every path. | Only the split asserts `RT`. When `x`'s type is concrete or `K` has no candidates, the inliner rewrites the call to `f(x, args...)` without the assertion. The method itself asserts it, so compiled and interpreted code can differ on a result that is not an `RT`. TraitWorld asserts the result after the call. | `Compiler/src/facts.jl:465`; `Compiler/src/ssair/inlining.jl` (`process_simple!`) |
| C-9 | [§1.4](#14-return_type) | A plain answer is folded when every edge of it rests on facts. | The walk gives up after 2000 `CodeInstance`s, and the site is answered at run time. The walk is not memoized, so each fold walks again. | `Compiler/src/facts.jl:305` |
| C-10 | [§1.4](#14-return_type) | Plain answers for `return_type` live in one cache. | In the product setting, the compile-time route caches in `:facts_plain_return_type` and the run-time route in the default owner's cache: two inferences of the same answer. | `Compiler/src/facts.jl:259`, `:355` |
