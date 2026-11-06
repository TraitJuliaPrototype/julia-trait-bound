# Compiler and runtime: the reference

This page defines what Julia's compiler and runtime provide to the design: each interface, where it lives, what it means and its rules. It describes the interfaces as designed, including the parts not built yet. Each section says how far it is built.

- What compiled code may assume, and why each interface is needed, is in [`facts.md`](facts.md). This page states the semantics an interface implements and links there for the reason.
- How the trait language uses these interfaces is in [`lowering.md`](lowering.md).
- The inventory of the changes, with commits, files and upstream status, is [`../design/julia-changes.md`](../design/julia-changes.md).
- The patched Julia is `julia-1.13/`, branch `trait-world-1.13`, on v1.13.2. TraitWorld requires it.
- Section 7 is built on branch `unified` of the julia repository, also on v1.13.2 (the worktree `julia-unified/`).
- Terms as in the [glossary](../glossary.md). The ones this page relies on most:
  - a *fact signature* is a call signature at which only its stakeholders or a pirate can change dispatch; a *fact* is what dispatch selects at one ([`facts.md`](facts.md#facts-and-fact-signatures));
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
| [1. Infer across a call only where a fact holds](#1-the-facts-inference-mode) | The facts mode of `NativeInterpreter`; `is_fact_sig`; run-time sites; the `return_type` rule; effects | — | Guarded devirtualization (Optional); revalidating cached `return_type` answers after loads (Optional; [PE-5](../record/performance-explorations.md)); standard libraries as owners of their own (Open) |
| [2. Code of two modes side by side, each under its own owner](#2-mode-and-owner-per-method) | The module option and `Method.facts`; owner `:facts`; dispatch from facts code, and through `jl_apply` to the default owner's code; calls, inlining, edges and images across owners; `--trim` plain | One function for the mode and owner; the facts owner for code compiled by facts under the test bed too; a module's other compiler options in both modes | A memo for the facts owner's normalization (Optional) |
| [3. Caches at dynamic boundaries are checked against the caller's world](#3-world-checked-caches-at-dynamic-boundaries) | `cfunction` convention `:caller_world`; exact-type and wildcard entries in the per-call-site cache | Entries with an open `max_world` | beyond a split's table (a carried witness, a runtime table of entry points, recompiling); a codegen-emitted cache (all Optional) |
| [4. Primitives for a specialized path beside a general one](#4-primitives-for-a-specialized-path-beside-a-general-one) | `Compiler.known_type`; `Compiler.split_call`; the table of a split's targets; `Compiler.fold_call` | the targets compiled ahead (C-14) | — |
| [5. Hooks for the library](#5-hooks-for-the-library) | Definition hooks; field-offset intrinsics; type printers | Deletion hook, "would invalidate" query, image-validation report | — |
| [6. Changes useful without traits](#6-changes-useful-without-traits) | Two inliner changes; the run-time `return_type` entry in the image; reflection in the compiler's world; the dispatch profiler | Upstream proposals | — |
| [7. Traits in the type system](#7-traits-in-the-type-system) | — | Membership as subtyping; one dispatch, never folding a negative membership, with guards; keys as compilation signatures; compiling by facts per method, one owner; memberships in images; then syntax: last | The code slot (Optional, §7.7); sealed sets, whose negatives fold (Optional; [PE-19](../record/performance-explorations.md)); the entries of generic implementations (Open, [open issue 140](../open-issues.md#1-decisions-waiting-for-the-user)) |

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
                           owner = facts_default() ? FACTS_OWNER : nothing,
                           facts::Bool = owner === FACTS_OWNER)
Compiler.cache_owner(interp::NativeInterpreter) = interp.owner
Compiler.facts_mode(interp::AbstractInterpreter)::Bool   # interp isa NativeInterpreter && interp.facts
```

Lives in `Compiler/src/types.jl` and `Compiler/src/facts.jl`.

**Meaning.**
- `facts`: whether this interpreter infers calls only at facts (§1.2). `false` is plain Julia's inference.
- `owner`: the cache owner of the code it infers and caches. `nothing` is plain Julia's cache; `:facts` is the cache of code compiled by facts beside plain code (§2.3).
- **The mode is the owner.** By default `facts` is whether the owner is `:facts`: an interpreter of owner `nothing` is plain in both settings, one of owner `:facts` compiles by facts in both. An interpreter with an owner of its own (TraitWorld's check results) sets both.
- Only `NativeInterpreter` has the mode. Any other `AbstractInterpreter` infers by its own rules: `facts_mode` is `false` for it.

**The process switch.**
- `Compiler.facts_default()` decides the default owner of a fresh interpreter: `:facts` with the switch on. It reads `jl_compile_by_facts()` (`src/gf.c`) once per process:
  - `JULIA_COMPILE_BY_FACTS=1` (any non-empty value but `0`): on;
  - `JULIA_COMPILE_BY_FACTS=0`: off;
  - unset or empty: the system image's default. An image built with the switch on keeps it on: the first call of `facts_default()` with the switch on sets `FACTS_IMAGE`, which the image saves. The runtime reads it when the image is restored, before any module's `__init__` runs (`jl_read_facts_image_default`), since it calls the initializers under the default owner.
- With the switch on, every method not marked otherwise is compiled by facts, under the owner `:facts`: *the test bed* (`all`). With the switch off, only facts methods are compiled by facts: *the product setting* ([`facts.md`](facts.md#the-test-bed)).
- `--trim` turns the switch off (§2.10).
- **Planned:** a command-line flag, `--compile-by-facts=no|all|traits`, in place of the environment variable; `--trim` implies `no`.

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
- a tuple without a `Vararg` tail whose arguments are concrete, or tuple types whose elements are concrete or unions of concrete types, split by Julia's union-splitting cost (`unionsplitcost`) over the tuple's elements, at the interpreter's `max_union_splitting`;
- a tuple of *concrete members* with a `Vararg{E}` tail of a concrete member `E`. A concrete member is a dispatch element that is not a kind (a concrete type, or `Type{T}` with `T` known), or a tuple type of concrete members;
- a closure's call at kinds: the first argument is a closure type (its name is generated, `#…`), and every argument is concrete or one of `DataType`, `UnionAll`, `Union`.

A union at the top level of a call's arguments is split as Julia splits unions (`max_union_splitting`, four by default). Each split must be a fact signature, so the two limits compose: up to sixteen concrete signatures per call. Each top-level split gets an edge; a union in a tuple argument is one edge at the tuple signature.

**Not gated: `invoke` and `hasmethod` at a declared signature.** Only `find_method_matches` gates a call by `is_fact_sig`. `abstract_invoke` and `hasmethod`'s tfunc resolve the declared signature with `findsup`, as plain Julia does, in facts code too, and record an invoke edge at the declared signature (`abstractinterpretation.jl:2369`, `tfuncs.jl:3269`). Julia invalidates such an edge only when the resolution of the declared signature changes: an edge at the method's own signature only when the method is replaced (`src/gf.c:2532`–`2537`). That is the sixth form of fact ([`facts.md`](facts.md#facts-and-fact-signatures)).

Why exactly these are facts is defined in [`facts.md`](facts.md#facts-and-fact-signatures). Which unions split is Julia's cost model, exactly ([facts §3](facts.md#facts-and-fact-signatures); F-15).

### 1.3 Run-time sites

**Status: Implemented.**

```julia
Compiler.FACTS_ABSTRACT_SITE::FailedMethodMatch
Compiler.unedged_effects(interp)::Effects        # EFFECTS_RTSITE under the facts mode
Effects.nortsite::Bool                           # no run-time site, here or in a callee
```

Lives in `Compiler/src/facts.jl`, `effects.jl`, `abstractinterpretation.jl` (`find_method_matches`, `abstract_call_gf_by_type`, `abstract_invoke`).

**Meaning.**
- **A run-time site is a call that records no edge.** Under the facts mode that is:
  - a call whose signature, or one of whose union splits, is not a fact: it gets no method matches (`FACTS_ABSTRACT_SITE`);
  - a call at a fact signature that Julia's method matching gives up on: more matches than `max_methods`, a call after `:latestworld`, an `invoke` it cannot resolve, a concrete-only refusal;
  - the fallback of an open split (§4.2).
- A run-time site's result is `Any`, its exception type `Any`, its effects unknown. Codegen emits a dynamic dispatch (§2.5).
- **Its effects clear `nortsite`.** The bit is part of `Effects`, so it is merged into the frame's effects and carried through calls to every caller, as `nortcall` is. It is stored in a CodeInstance's encoded effects, inverted, so zeroed bits read as no run-time site. Only the facts mode clears it; no assertion sets it. §1.5 uses it.

**Rules.**
- A call at a fact that Julia resolves is inferred as plain Julia infers it, with its edges, including constant propagation and concrete evaluation.
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
   - Every edge of every answer, transitively, must be at a fact signature, or an invoke edge at the method's own signature (§1.2). Bare MethodInstance edges and method-table edges disqualify it.
   - The merged answer is folded, with an edge (`PlainRTInfo`) from the facts code to each plain answer. A load that changes plain Julia's answer invalidates the folded code.
3. **Otherwise, a call at run time.**

**At run time**, `return_type` calls `_return_type(return_type_interp(world), tt)` in the compiler's world. `return_type_interp` is `PlainRTInterp` in both settings, so the run-time answer is the fold's: plain inference's, facts methods included.


**The answer cache.** `PlainRTInterp`'s owner is `:facts_plain_return_type`. No code that runs is taken from it: dispatch looks up code only under the owner it asks for, `nothing` or `:facts` (`jl_method_compiled_callptr_owner`, `src/gf.c:3559`). It holds only plain answers, so no plain code enters a cache that facts code is compiled from.

**Rules.**
- `PlainRTInterp` is not a `NativeInterpreter`, so it infers every method plainly, facts methods included (§2.6).
- An answer is the same as plain Julia's in the same world. Across worlds it moves exactly when plain Julia's does.

**Optional: revalidation after loads** (not pursued now: [PE-5](../record/performance-explorations.md)). When a load invalidates a cached answer, the answer's edges are checked bottom-up, and an answer whose inputs did not change is kept instead of inferred again (red-green revalidation). A differential test against stock Julia comes first: every logged query, answered by both, must give identical answers before and after the loads.

### 1.5 Effects

**Status: Implemented** (acceptance G1.10, G1.32, G1.33).

Lives in `Compiler/src/typeinfer.jl` (`adjust_effects(ipo_effects, def, frame)`) and `abstractinterpretation.jl` (`merge_override_effects!`).

**Meaning.** Under the facts mode, no asserted effect applies over a run-time site, at any depth (§1.3, `nortsite`):
- a method's `@assume_effects` is ignored when the frame's effects have `nortsite` clear: the frame or a callee holds a run-time site;
- a statement's `@assume_effects` is ignored when the statement's call has `nortsite` clear.

**Why.** An assertion would let a caller fold a call whose dispatch no edge records ([`facts.md`](facts.md#asserted-effects)).

### 1.6 Further work on mechanism 1

- **Optional: guarded devirtualization at run-time sites.** A run-time site would call a guessed target behind a type check, with the dynamic call as fallback.
  - The objection is a permanent slowdown: a site whose guard fails stays on the fallback, silently, until its caller happens to compile again.
  - The objection goes away if the slowdown is temporary: a site that keeps taking the fallback has its caller compiled again in the background, with the observed types in the split, and the new code is swapped in once it is ready (tiered recompilation, as in HotSpot, .NET and V8).
  - In the facts mode the swap is not an invalidation. The old and the new code are valid in the same worlds and compute the same results.
  - For a split it is the last option of §3.3. Only if untyped code under the test bed still matters after the other work.
- **Open: standard libraries as owners of their own.** Today Julia's standard libraries count as Julia's own code, so a standard library's method that wins at a fact is a stakeholder's change; to settle by a census (E-189; [open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).

---

## 2. Mode and owner per method

**The principle.** Code of both modes lives side by side, each with its own cache owner, caches, edges and images. Which mode and owner a method's code gets follows from the method and the mode that reaches it, never from a particular caller. A call from one mode into the other crosses explicitly. What each kind of code may assume is in [`facts.md`](facts.md#which-code-is-compiled-how).

### 2.1 The module option

**Status: Implemented**, except a module's other compiler options in the facts mode (**Planned**, [C-6](#deviations)).

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
- `Expr(:meta, :facts, 1)` and `Expr(:meta, :facts, 0)` mean the module option only, at a module's top level. A method body names its mode with its own markers (§2.2).

**Planned: the other compiler options in both modes.** A module's other compiler options (`optimize`, `compile`, `infer`, `max_methods`) apply to its code in both modes, as they apply to plain code. Today `compile` (`min`, `no`) is ignored for code of owner `:facts` ([C-6](#deviations)).

### 2.2 The method flag: boundaries and always-facts methods

**Status: Implemented.**

The interface is a meta at the start of a method's body, as `Expr(:meta, :inline)` is for `@inline`:

```julia
Expr(:meta, :facts_boundary)   # compiled in the mode of the code that reaches it
Expr(:meta, :facts_always)     # always compiled by facts
```

Julia defines no macro for them. A macro that puts the meta first in the body is enough; TraitWorld's is `@machinery` for always-facts methods, and its lowering inserts `:facts_boundary` itself ([lowering §2](lowering.md#2-modes-owners-and-images)).

Lives in `src/method.c` (`jl_method_set_source`), `src/ast.c` (the symbols), `src/ast.scm`, `src/julia-syntax.scm`, `src/module.c`.

**The method flag** (`Method.facts::UInt8`):

| Value | Meaning | Written as |
|---|---|---|
| 0 | as its module's flag says | (nothing) |
| 1 | a boundary: compiled in the mode of the code that reaches it | `Expr(:meta, :facts_boundary)` |
| 2 | always facts | `Expr(:meta, :facts_always)` |

```c
int jl_method_is_facts(jl_method_t *m);   // flag 2, or flag 0 in a module of flag 1; 0 under --trim
int jl_method_is_plain(jl_method_t *m);   // flag 0 in a module of flag 2
```

**Rules.**
- Lowering carries the meta into every method a definition lowers to: the keyword sorter and the positional forwarders of default arguments.
- The meta may be merged with other metas, as `pushmeta!` merges `@inline`'s. It is still found.
- Each marker has one meaning. `:facts_boundary` and `:facts_always` are read in a method body only. `Expr(:meta, :facts, n)` is the module option, at a module's top level (§2.1).
- TraitWorld marks entries as boundaries and its machinery as always facts ([`lowering.md`](lowering.md#82-the-entry)).

### 2.3 The owners, and the mode and owner of a MethodInstance's code

**Status: Implemented.**

Three cache owners:

| Owner | Holds | Code run from it |
|---|---|---|
| `nothing` | plain code | yes |
| `:facts` (`Compiler.FACTS_OWNER`) | code compiled by facts | yes |
| `:facts_plain_return_type` | plain answers for `return_type` (§1.4) | never |

**The rule.** The mode and owner of the code for a MethodInstance `mi`, reached from code of a given mode:

| `mi`'s method | Product setting | Test bed |
|---|---|---|
| a builtin (`Core.Builtin`, intrinsics among them) | its one CodeInstance, `nothing` | its one CodeInstance, `nothing` |
| a facts method (§2.2) | facts, `:facts` | facts, `:facts` |
| never by facts (flag 0 in a module of flag 2) | plain, `nothing` | plain, `nothing` |
| a boundary (flag 1) | the mode and owner that reach it | the mode and owner that reach it |
| any other method, reached from the runtime or the top level | plain, `nothing` | facts, `:facts` |
| any other method, reached from plain code | plain, `nothing` | plain, `nothing` (under the test bed only the compiler's code and what it calls are plain code) |
| any other method, reached from facts code | facts, `:facts` | facts, `:facts` |

So an ordinary method has one copy per mode that reaches it. A facts method has only facts code, and the compiler's code only plain code. A builtin has no code to compile: the runtime's one CodeInstance of it, of owner `nothing`, serves every caller. A builtin is recognised by its function's type, a subtype of `Core.Builtin`.

**One function** decides it, given what reaches the code: the runtime or the top level, plain code, or code of the facts owner.

```c
jl_value_t *jl_code_owner(jl_value_t *def, int reach);    // def: a method, or a module's top-level thunk; :facts or nothing
```

```julia
Compiler.code_owner(def, reach)        # reach: REACH_RUNTIME, REACH_PLAIN, REACH_FACTS
```

Every place that decides asks it: the runtime's default owner (`jl_default_owner`, for dispatch from the runtime and the single-request entry, §2.4), its dispatch from facts code (§2.5), calls between the modes in inference (`leaves_to`, §2.6), and the compile queues, through each item's owner (§2.4). It uses one predicate for "the compiler's code": the module flag 2 (`jl_method_is_plain`).

**The setting decides one thing:** the default owner of a method that is neither a facts method nor the compiler's code, and of a top-level thunk, reached from the runtime or the top level (`jl_default_owner`, and the owner of a fresh `NativeInterpreter`): `:facts` under the test bed, `nothing` in the product setting. So plain code (the compiler, and the Base methods the compiler calls) never shares a cache with code compiled by facts ([`facts.md`](facts.md#the-mode-rule)), and a CodeInstance means the same in both settings.

### 2.4 Compile requests

**Status: Implemented.**

```c
jl_value_t *jl_default_owner(jl_method_instance_t *mi);   // jl_code_owner(mi->def, reached from the runtime)
jl_code_instance_t *jl_type_infer(jl_method_instance_t *mi, size_t world, uint8_t source_mode, uint8_t trim_mode);
```

```julia
Compiler.typeinf_ext_toplevel(mi, world, source_mode, trim_mode, owner)   # the runtime's entry (jl_typeinf_func)
Compiler.typeinf_ext(interp, mi, source_mode)
Compiler.interp_for_owner(interp, owner)       # the interpreter for a queue item of owner `owner`
Compiler.interp_for_mi(interp, owner, mi)      # the same (for the compile queues)
Compiler.default_owner(mi)                     # code_owner(mi.def, REACH_RUNTIME)
```

Lives in `src/gf.c`, `Compiler/src/typeinfer.jl` and `Compiler/src/facts.jl`.

**Meaning.**
- The runtime asks for code of an owner. `jl_type_infer` asks for `mi`'s default owner. The runtime's other entries take the owner explicitly (§2.5).
- The single-request entry builds the interpreter of that owner: facts under `:facts`, plain under `nothing`.
- `typeinf_ext` hands a facts method to a facts interpreter, whoever asks (reflection, compile queues).
- A compile queue holds `CodeInstance`s of both owners. Each item is inferred by the interpreter of its own owner (`interp_for_owner`); a MethodInstance by that of its default owner.
- Reflection shows the code that runs: `typeinf_frame` infers a facts method by facts.

### 2.5 Dispatch from facts code

**Status: Implemented.**

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
- Dispatch on a narrow MethodInstance runs the code of the wider instance Julia compiles for it, copied onto the narrow instance as for the plain owner: it runs with the narrow instance's static parameters, and the next call finds it there (`jl_compile_method_internal_owner`).
- Where compilation is off (`--compile=min`) or the method has no source, the code that runs is the method's unspecialized code, or the interpreter. The CodeInstance made for it is the asking owner's, so the next call finds it. The unspecialized code read is the asking owner's, else the plain owner's; the plain owner never runs code compiled by facts.

**Dispatch through the runtime's `jl_apply`** runs the callee's default owner's code (`jl_default_owner`, §2.4):
- splats of unknown length;
- the `invoke` builtin at run time;
- `jl_call`;
- `@cfunction` callbacks, including `:caller_world` pointers (§3.1);
- finalizers and task entry.

A trait module's method is a facts method, whose default owner is `:facts`: trait code reached this way is code compiled by facts. A neutral method runs its plain code in the product setting. That is not trait code, so trait code is never invalidated through this path. The rule needs nothing of the runtime's internals: `jl_apply` asks for the default owner's code, as any call from the runtime does ([facts §5](facts.md#run-time-sites)).

### 2.6 Calls between the modes in inference

**Status: Implemented.**

```julia
Compiler.leaves_to(interp, method)    # the interpreter `method`'s code belongs to, or nothing
Compiler.facts_edge(interp, other, method, mi, caller, edgecycle, edgelimited)
Compiler.facts_const_call(interp, other, result, f, arginfo, si, match, sv, invokecall)   # the gate: concrete, semi-concrete, then constant propagation
Compiler.facts_const_prop_call(interp, other, result, f, arginfo, si, match, sv)        # constant propagation into a facts callee
Compiler.is_facts_method(m), Compiler.is_plain_method(m)
```

Lives in `Compiler/src/facts.jl`, `typeinfer.jl` (`typeinf_edge`), `abstractinterpretation.jl`.

**Meaning.** When inference reaches a method whose code belongs to the other mode (§2.3):
- the callee is inferred by the other interpreter, in an inference of its own, as a request from the runtime would be (`facts_edge`);
- the call names that `CodeInstance`, with an edge to it;
- a plain caller propagates constants into a facts callee: `facts_const_prop_call` infers the callee again for the constants with the facts interpreter, in a call stack of its own, the result local and the edges that inference's ([facts §6.3](facts.md#calls-between-the-modes)); concrete and semi-concrete evaluation cross on the callee's facts CodeInstance, with an edge to it;
- a facts caller of the compiler's plain code propagates no constants.

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
- **An `:invoke` of a given `CodeInstance` of another owner** inlines exactly that code. The caller's own cache may hold different code for the same MethodInstance. Inlining it would run code the call never asked for.
- **A call to a method whose code belongs to the other owner** (§2.6) inlines that owner's cached code. Both `resolve_todo(mi, …)` look it up there when the caller's own cache misses.
- When not inlined, the call is an `:invoke` of the other owner's `CodeInstance`.

**Rules.**
- Inlining does not infer again. The inlined code stays the other owner's, with an edge to its `CodeInstance` only.
- Edges to two `CodeInstance`s of the same MethodInstance with different owners are two edges (`add_inlining_edge!` compares the owner). Each is invalidated separately.

### 2.8 Edges for a second owner

**Status: Implemented.**

Lives in `src/gf.c` (`_invalidate_backedges`).

**Meaning.** When one `CodeInstance` is invalidated, a caller whose edge names only the MethodInstance is invalidated only if:
- the caller has the same owner; or
- the caller is a generator's cached output (owner `:uninferred`), which may have read any owner's result.

Replacing the method itself reaches callers of every owner.

**Why.** A bare MethodInstance edge stands for the caller's dependence on its own interpreter's result for that instance. An interpreter consults only its own cache. So only a `CodeInstance` of the caller's owner can break it ([`facts.md`](facts.md#edges-and-invalidation)).

### 2.9 What package images keep

**Status: Implemented**, including copies of code compiled by facts whose inferred source was discarded.

```c
void jl_set_image_keep_compiled(int on);    // for the image being built in this process
```

Lives in `src/staticdata_utils.c` (`queue_external_cis`) and `Compiler/src/precompile.jl` (`compile_and_emit_native`).

**Meaning.**
- **Machine code only for the owners whose code runs,** `nothing` and `:facts` (§2.3). Code of other owners (`return_type`'s answers, an `AbstractInterpreter`'s results) is serialized with its methods and gets no machine code: nothing calls it.
- **Code of owner `:facts`** goes through the compile queue, as plain code does. The queue infers it again by facts where its inferred source was discarded.
- **With keep-compiled on:**
  - a `CodeInstance` of the facts owner of an upstream method, compiled during precompilation and reached by no call of the package that Julia can see (a dynamic call, `invokelatest`, a call from upstream code the workload ran), is kept with its machine code, also where its inferred source was discarded. It stays valid across unrelated loads (G2).
  - Plain code reached that way is not kept, as in stock Julia: it depends on the whole method table.
- Without keep-compiled, Julia drops such code, as stock Julia does.

**Rules.**
- TraitWorld switches keep-compiled on while a package that uses it is precompiled ([`lowering.md`](lowering.md#2-modes-owners-and-images)).
- **An image keeps no external code specialized at a signature type without a hash** (a value-specific instance, such as a type value pushed into a `Type[]`): its insertion at load scans its method's list of specializations. Dropping compiled code from an image changes no result (julia-1.13 6800be7839, W-59).
  - Julia gives a type value no hash when its parameters hold a `Union` directly (`Type{Tuple{Union{Missing, Float64}}}`, `Type{Union{Missing, Int}}`): such a type has several equal forms. A type with invariant parameters around it has one (`Type{Callable{Tuple{Union{Missing, Float64}}, Bool}}`).
  - Code reached by a static call from the image's own code is kept through that caller's edges. The rule drops code that only a workload's dynamic call reached.
  - TraitWorld keys its entries for function arguments by the bound for this reason ([lowering §12](lowering.md#12-callable-and-dynamiccallable)).

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

**Status: Implemented**, with cache entries capped at the latest world ([C-3](#deviations)).

```julia
Expr(:cfunction, Ptr{Cvoid}, QuoteNode(f), rettype, :(Core.svec(argtypes...)), QuoteNode(:caller_world))
```

`@cfunction` has no argument for the convention. Code writes the expression, as TraitWorld's `Callable` does ([`lowering.md`](lowering.md#12-callable-and-dynamiccallable)). Lives in `src/codegen.cpp` (`emit_cfunction`, `emit_abi_call`) and `src/runtime_ccall.cpp` (`jl_get_abi_converter_caller_world`).

**Meaning.**
- A call through the pointer runs in the caller's world (the task's world age), as a direct call does. A plain `@cfunction` runs in the latest world, as a callback from C must.
- The pointer's thunk is a world-checked call-site cache:
  - each target the thunk has called is a cache entry: a function pointer, its `CodeInstance`, and a range of worlds;
  - the range is where both hold: the dispatch of the signature (`jl_get_specialization1_worlds`), and the target's `CodeInstance`;
  - a call whose world is in the current cache entry's range calls it directly;
  - any other call looks for a cache entry of its world, or looks the target up in its world and adds one.
- A thread with no world (a C callback) uses the latest world.
- A signature that one method covers only in part dispatches dynamically, in the caller's world.

```c
jl_value_t *jl_get_specialization1_worlds(jl_tupletype_t *types, size_t world,
                                          size_t *min_valid, size_t *max_valid);
```

The MethodInstance for `types` in `world`, with the range of worlds where that answer holds, or `nothing` when the dispatch is not unique.

**Rules.**
- Cache entries are never freed. There is one per target and contiguous range of worlds, and targets are rooted by their MethodInstances' caches.
- The callee's code is the default owner's: a facts method's facts code, any other method's plain code in the product setting (§2.5).

### 3.2 The per-call-site dispatch cache

**Status: Implemented**, with exact-type cache entries capped at the latest world ([C-3](#deviations)).

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
- **Optional: beyond the table of a split's targets** (§4.3; E-145, [`design/evidence.md`](../design/evidence.md)):
  - **a runtime table of specialized entry points with their world ranges,** checked at the probe and never saved: one indirect call, no thunk and no target method per type;
  - **a witness carried in the value,** the pointer arriving with it: faster on large mixes of many types ([evidence](../design/evidence.md), E-145), at a word per value and a lookup per value made from an unknown type;
  - **recompiling in the background** with the observed types in the split (§1.6): E-145 found it pays only for skewed mixes of cheap operations on data in the cache.
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
- TraitWorld's entry uses it to decide a plain value's attribute: a typed caller inlines the entry, where it folds to `true`, and passes a `Compiled` value; an untyped caller, and code Julia does not compile (a statement at the prompt), reach the entry compiled at `Any`, where it is `false`, and pass a `Dynamic` one ([`lowering.md`](lowering.md#82-the-entry); [`traits.md`](traits.md#6-values-in-trait-code-compiled-and-dynamic)). The attribute changes speed, never results, so the rule above holds.

### 4.2 `Compiler.split_call`: the call-site split

**Status: Implemented.**

```julia
Compiler.split_call(K, ::Type{RT}, f, x, args...)            # f(x, args...)::RT
Compiler.register_dynamic_candidate!(K, C)                    # C: a candidate type of K
Compiler.dynamic_candidates(K)::Vector{Any}                   # the first MAX_FACT_SPLITS registered, in order
```

Lives in `Compiler/src/facts.jl` (`abstract_split_call`, `SplitCallInfo`), `ssair/inlining.jl` (`process_simple!`, `compute_inlining_cases`, `handle_call!`, `ir_inline_unionsplit!`), `stmtinfo.jl`.

**Meaning.** `split_call(K, RT, f, x, args...)` is `f(x, args...)` where `x` is a value of an open set of types, the candidates registered for `K`.
- **Inference.** When `x`'s type is not concrete and `K` has candidates, `f` is inferred at `x`'s type intersected with the union of the candidates. Each split is a fact, with its edge.
- **The split.** The inliner rewrites the statement to the call of `f` and splits it over the candidates. The last branch, the **fallback**, calls through the table of the call's targets (§4.3), or is the dynamic call where no table applies. The split is never "fully covered": a value of another type reaches the fallback.
- **The result.** Inference types the call `Any` where it splits: the fallback's result is unknown. The inliner's split asserts the fallback's result, and any case not known to be an `RT`, to `RT`, and types the join `RT`. A caller that needs the type after the call asserts it there, as TraitWorld's lowering does ([`lowering.md`](lowering.md#13-dynamicx)).
- **No edge to the registry.** Candidates are read without an edge. A type registered later reaches the fallback, and invalidates nothing.
- When `x`'s type is concrete, or `K` has no candidates, it is the call `f(x, args...)` as inference finds it.

**Rules.**
- At most `MAX_FACT_SPLITS` candidates are split: the first four registered, in the order of registration. Later ones reach the fallback.
- TraitWorld registers a trait's implementations in declaration order (the declaration's file, then its line), at each declaration and each package load, so the split covers **the first four declared**, in a session that loads a package image as in the image's own code ([`lowering.md`](lowering.md#13-dynamicx)).
- Which candidates a caller splits over is fixed when the caller is compiled. A caller compiled before a candidate is registered keeps the smaller split. So code compiled into a package image, such as a worker at a `Dynamic` position, splits over the implementations registered while the image was built, and a user's type declared later takes the fallback (measured with the gaps of [W-17](../record/todo.md)).
- Registration is lock-free for readers: the table is replaced on each registration, never mutated.
- How TraitWorld uses it for `Dynamic{X}` values and for operations and field reads at a `Dynamic` position is in [`lowering.md`](lowering.md#13-dynamicx); what code may assume about it, in [`facts.md`](facts.md#run-time-sites).

### 4.3 What follows the split: the table of a call's targets

**Status: Implemented**, with the pointers made at a type's first use, not ahead ([C-14](#deviations)), and their thunks' entries capped at the latest world ([C-3](#deviations)).

```c
void *jl_split_table_ptr(jl_value_t *tbl, jl_value_t *T);    // the pointer for type T; made at a miss
uint64_t jl_split_session(void);                              // this session's stamp, never 0
void jl_set_split_table_miss(jl_value_t *f);                  // Base._split_table_miss!, set by Base.__init__
```

Lives in `src/gf.c`, `Compiler/src/facts.jl` (`SplitTable`, `SplitState`, `split_table`, `split_state_add`), `Compiler/src/ssair/inlining.jl` (`split_fallback_table`, `split_table_call!`), `base/splittable.jl` (`_SplitTarget`, `_SplitTargetFacts`, `_split_pointer`, `_split_table_miss!`).

**Meaning.** A value of a type outside a split's candidates is called through a table of the call's targets, keyed by its type. The last branch of the split is:

```julia
T  = Core.typeof(x)
fp = foreigncall(:jl_split_table_ptr, Ptr{Cvoid}, (Any, Any), table, T)
r  = foreigncall(fp, R, (Any, Any, A...), f, x, args...)
```

- **The table** belongs to the call's signature: the function's type `F`, the other arguments' types `A`, the result type `R`, and whether the calling code is compiled by facts. Sites with the same signature share one, made when the first of them is compiled (`split_table`) and embedded in their code.
- **The probe** looks up the address of `T` in the table's state (open addressing). A hit returns the pointer.
- **A miss** calls `Base._split_table_miss!(table, T)` in the caller's world. It makes the pointer and adds it. A type with no method for the call gets a pointer too: calling it raises the `MethodError` the call would.
- **The pointer** is a `:caller_world` `cfunction` (§3.1) of the target `_SplitTarget{F, T, R, A}()`, whose method is `(f::F)(x::T, args::A...)::R`, with `f` and `x` passed boxed. Under the facts mode the target is `_SplitTargetFacts`, compiled by facts whoever calls it (`Expr(:meta, :facts_always)`): code compiled by facts reaches code compiled by facts at run time, as with `jl_apply_generic_facts` (§2.5).
- **Arguments and result** (`split_ccall_type`): a value passes by value where its type is an isbits type of nonzero size, else boxed (`Any`), so a mutable object keeps its identity and a struct with references is never copied field by field. The target asserts each argument to its type at the site (`_SplitTarget{F, T, R, A}`), so its call is static where the site's other argument types are concrete; an argument the site holds at an abstract type is passed as `Any` and dispatched inside the target. `R` is the split's declared result; it returns by value under the same rule (`Nothing` as no value), else boxed, and the target asserts it, so a value of another type raises a `TypeError`, never a conversion.

**Rules.**
- **The fallback stays a run-time site.** It dispatches in the caller's world, through the thunk's world-checked cache, and records no edge ([`facts.md`](facts.md#dynamic-split)). A redefinition is followed as a dynamic call follows it. The table needs no invalidation.
- **Sessions.** Pointers are valid in their session only. A state carries its session's stamp, checked by the probe on every call. A table saved in a package image counts as empty in another session and fills again. Sites compiled into different images keep tables of their own.
- **Threads.** A table's state is replaced on each addition, never mutated (copy-on-write, published atomically). The pointer is made before the update. Readers take no lock.
- **Where it applies:** an open split (§4.2) whose function's type is concrete and not a kind, with at most `MAX_SPLIT_TABLE_ARGS` (6) arguments after the value. Elsewhere the fallback is the dynamic call.
- **Ahead of time** (Planned, [C-14](#deviations)): for each declared implementation the targets and their thunks are compiled into the declaring package's image, as the untyped table's pattern methods are ([`lowering.md`](lowering.md#151-compiling-ahead-from-declarations)). A session's first use of the type then only fills the table.
- **Not in a trimmed program** (`--trim`), which makes no code at run time: there the fallback is the dynamic call. Whether code precompiled into a package image with a table, and reused by a `--trim` build, keeps a miss path that needs code made at run time is to verify when the trimmed rows are built.
- The table answers what Rust's vtables and Swift's witness tables answer. Its key is the type in the object's header, as for C++'s and the JVM's vtables.

### 4.4 `Compiler.fold_call`

**Status: Implemented.**

```julia
Compiler.fold_call(g, args...)            # a value fixed where the code is compiled; nothing where it is not
Compiler.Undecided()                      # g's answer for not now
Compiler.AtLoad()                         # g's first argument when a fold is evaluated again at load
Compiler.FoldRecord(g, args, value)       # the fold, kept in the caller's edges
```

Lives in `Compiler/src/facts.jl` (`abstract_fold_call`, `fold_holds`), `abstractinterpretation.jl` (`abstract_call_known`), `ssair/inlining.jl` (`process_simple!`), `typeinfer.jl` (`ForwardToBackedgeIterator`), `reinfer.jl` (`verify_method`).

**Meaning.**
- **At run time** `fold_call(g, args...)` is `nothing`; `g` is not called.
- **Where it folds:** in a frame of the native interpreter compiled for the global cache, with every argument a constant to inference. Inference calls `g(args...)` with `Core._call_in_world` in the inference world. A value `v` is the call's result, `Const(v)` with total effects; the inliner replaces the call by `v` whatever its size; the frame's edges keep `FoldRecord(g, args, v)`. `nothing`, `Undecided()` or an error leave the call unfolded: it is `nothing`, as at run time.
- **Not folded:** reflection's top frame, constant propagation and semi-concrete evaluation, other interpreters.
- **The record has no backedge:** nothing invalidates it in a session. `rests_on_facts` counts it as resting on facts.
- **At load,** image validation evaluates each record again: `g(AtLoad(), args...)` in the validation world. A different value (by egal), `nothing` or an error makes the code invalid, as a failed edge does.

**Rules,** for the library:
- Code uses it only between paths that compute the same result, as `known_type` (§4.1).
- One answer per session: once `g` returns `v` for some arguments, it returns `v` for them.
- Called from inference, `g` waits for no lock, does not yield or write, and runs no user code; it fixes nothing except in the latest world. A value holds no pointer of a session.

**Why the design needs it:** a family member's builder fixed in its callers' code ([`lowering.md`](lowering.md#46-families)).

---

## 5. Hooks for the library

### 5.1 Method-definition and image-activation hooks

**Status: Implemented.**

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
- Strict mode uses both ([`traits.md` §10](traits.md#10-who-may-implement-pirates-strict-mode)).

### 5.2 Field-offset intrinsics

**Status: Implemented**, except fields stored inline that hold references ([C-7](#deviations)).

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

**Status: Implemented.**

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
- TraitWorld prints trait objects by bound and key with it ([`traits.md` §12](traits.md#12-printing)).

### 5.4 Planned: hooks for strict mode's intended design

**Status: Planned** for two pieces; strict mode's report at an image's load uses an internal interface (below). Strict mode's intended design ([`facts.md` §10.3](facts.md#strict-intended); [W-66](../record/todo.md)) needs:
- **A deletion hook (1′):** called at method deletion (`jl_method_table_disable`). It may refuse.
- **A hook for a binding redefined from another module** (facts §2.2's exception), at its source.

**Used as it is, an internal interface:** validation's own log, `Compiler.ReinferUtils.debug_method_invalidation(true)` (`Compiler/src/reinfer.jl`), apart from the runtime's `jl_debug_method_invalidation`. Each edge that fails is an entry `(edge, "insert_backedges_callee", codeinst, matches)`, and each CodeInstance made invalid is an entry `(child, "verify_methods", cause)`. Julia also writes an `insert_backedges_callee` entry for a binding's edge that holds where the binding has no partitions: whether code was rejected is its `verify_methods` entry, or its world range after the load (`max_world`), not that entry. A fold that holds writes none. TraitWorld keeps it on in strict mode and reads it after each load. It may change with Julia. Its Julia form would pass the entries per image to a callback from `_include_from_serialized`.

A "what would this definition invalidate" query is not needed: code of the facts owner holds facts at concrete signatures, and the walk through the plain code it rests on decides (facts §10.2).

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

**Meaning.** The run-time entry, `_return_type(::PlainRTInterp, ::DataType)` (§1.4), and `_return_type(::NativeInterpreter, ::DataType)` are compiler bootstrap entries, so the system image holds their code, with the inference and optimizer methods inference reaches by dynamic dispatch for `PlainRTInterp`, as for `NativeInterpreter`. Otherwise the first `collect` of a generator or `map` over an empty collection in every session compiles the compiler for that interpreter (E-209).

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

**Status: Planned.** Built in stages on branch `unified` of the julia repository, from v1.13.2 ([the plan](../plans/2026-11-05-unification-synthesis.md); W-83, W-97 to W-104). Nothing of it is in `julia-1.13/`. Whether level 1 (membership as subtyping, §7.2) and level 2 (one dispatch, §7.3, §7.4) are adopted is decided by the user at the plan's gates B and C.

**The intended shape:**
- **Membership as subtyping,** by declaration after the type is defined: `T <: ColTable`, `x isa ColTable` ([`traits.md` §14](traits.md#14-membership)). Memberships: §7.2.
- **One dispatch:** a bounded method is a Julia method at its set. A set ranks above `Any` and below every other type at a position (§7.1, §7.3).
- **Guards** where a later membership could change a compiled call (§7.1, §7.4).
- **Keys as compilation signatures:** code compiled per key by Julia's own specialization, with no entries, workers or views (§7.5).
- **Compiling by facts as a property of the method,** with one CodeInstance per MethodInstance and policy (§7.6); a slot that lets a caller survive a callee's recompilation to an equal result, if a measurement asks for it (§7.7).
- **Memberships in package images,** and a record of each CodeInstance's dependencies complete enough for a machine-code cache across sessions (§7.8).
- **Syntax:** `trait`, `implement`, `Self`, a trait's name in a field meaning a value that keeps its attribute (`Kept{X}`), bounds in `where` clauses and on struct parameters.

**What it replaces:**
- the encodings TraitWorld needs today: entry methods at `Any`, tags for trait sets, sentinel methods, `conforms`, views and witnesses ([lowering §17](lowering.md#17-encodings-until-traits-are-in-the-type-system));
- in the product setting, the second cache owner of §2: plain code and code compiled by facts of one method do not live side by side. The owner stays a token for the test bed `all` and for `return_type`'s cache (§7.6).

**Why last.** It changes the type system, so it comes once the demonstrators' numbers support the proposal.

### 7.1 Memberships and dispatch

**Status: Planned** (W-83's level 2, one dispatch; [open issue 136](../open-issues.md#closed-items), closed). Built by W-99 (dispatch) and W-102 (guards); until the guards exist, a membership invalidates as a method insertion would ([C-18](#deviations)).

A bounded method `f(x::X)` is a method at the set `X`. Memberships and dispatch follow these rules:

- **Memberships only grow.** A membership `S ∈ X` holds from the world in which it is declared.
- **Positive answers fold, negative ones never.** Inference (`isa`, `<:`) and dispatch may rely on `S ∈ X`. They never rely on `S ∉ X` for an open set.
- **Except where the answer is final:**
  - a set whose members join only with their own definition (`struct S <: A`), as every abstract type of plain Julia, so plain Julia carries no guards;
  - Base's abstract types, which are closed: their members come only from `struct S <: A`;
  - Core's kinds (`DataType`, `UnionAll`, `Union`, `Module`, `TypeVar`, the builtins, opaque closures, the memory types), which are never members of a set.
- **A guard** stands at a compiled call `f(s::S)` where a method of `f` on an open set that `S` is not a member of would beat the method selected now (a fallback `f(::Any)`, a method on a less specific set, or none):
  - it reads a cell per (type, set), holding the membership's `min_world`, against the caller's world;
  - the cell is fixed when the guard compiles: a load and a compare, never a lookup in a table;
  - then it calls the bounded method, else the method selected now;
  - the guarded call's result is the bounded method's declared result joined with the selected method's.
- **Specificity per argument:** a plain type other than `Any` first, then a set, then `Any`. Between sets, a subtrait first. So a later membership never beats a method on the type's own supertypes.
- **Memberships invalidate nothing.** Methods invalidate as in Julia, under ownership ([facts §2.2](facts.md#g2)). Ownership decides who may declare a membership ([traits §10.1](traits.md#101-who-may-implement)).
- **Sealed sets** (Optional; [PE-19](../record/performance-explorations.md)): a set whose memberships are all declared with the member type's definition or in the member's own package (not in an extension) may fold its negatives too. How a set is declared sealed is not settled.

The evidence: E-252 (memberships declared in extensions arrive after code that depends on them is compiled), E-255 (Core's kinds), E-259 (the guards in the ports' sessions, and a guard's cost, [evidence §2](../design/evidence.md#2-run-time)).

### 7.2 Memberships

**Status: Planned** (W-98). Built in part on branch `unified`; its audit is W-97.

**A set** is an abstract type whose `TypeName` has the `open` bit.
- A trait declaration sets it. `abstract type A end` leaves it clear. A set is open from its declaration.
- Base's abstract types are closed.
- Core's kinds carry a `never_member` bit. A membership of one of them is refused.

**A membership** is an immutable entry on the member's `TypeName`, never on the set's:
- its fields: the set; the member pattern (`S`, or `S{T} where T` for a family); the set's instance for the pattern (`X`, `X{T}`); the key (§7.5); `min_world` and `max_world`; the declaring module; the forwarding field, if any;
- the list of a `TypeName`'s entries is replaced copy-on-write, so readers take no lock;
- `struct S <: X` for an open `X` adds an entry with the type. It is final: it holds from the type's definition;
- `jl_declare_membership(member, set_instance, key, declarer, by)` declares one. The library checks ownership and the contract before the call ([traits §4.9](traits.md#49-checks-at-the-declaration), [§10.1](traits.md#101-who-may-implement)); the runtime records the declarer.

**Every membership is explicit.** The runtime derives no membership from another:
- `@implement B S` declares `S`'s entry for `B`. `S`'s entry for each supertrait `A` of `B` comes from `S`'s own implementation of `A` ([traits §3.6](traits.md#36-supertraits-and-bundles)). An implementation of a bundle declares an entry for each trait of the bundle and one for the bundle.
- `@trait B <: A` declares `B`'s entry for `A`. So `B <: A`.
- `<:`, `isa`, intersection and dispatch read entries and derive nothing. So `isa(x, T)` and `typeof(x) <: T` agree.
- **Open:** how a generic implementation (`R: Indexable`, [traits §4.8](traits.md#48-generic-implementations)) and a family over an abstract type get their entries ([open issue 140](../open-issues.md#1-decisions-waiting-for-the-user)).

**Worlds.** A membership is declared as a method is inserted:
- under the world counter's lock, the entry gets `min_world = counter + 1`, is published, and the counter advances;
- `@implement` lowers to the declaration followed by `Expr(:latestworld)`, so the declaring code sees its own membership, as it sees its own method definitions;
- a task in an older world does not see it.

**Memberships only grow.** An entry is never removed. A redeclared implementation gives the old entry a `max_world`, declares a new one, and invalidates the code compiled at the old key and the callers that folded against it (a walk by key). It is a stakeholder's change ([facts §2.2](facts.md#g2)).

**Subtyping.** `jl_subtype(S, X)` consults `S`'s entries where `S`'s supertype chain fails to meet `X` and `X` is open, in both chain walks of `subtype`. A matching entry's instance is compared with `X`'s parameters as a supertype's are, invariantly. A miss is `false`. A set's parameters are associated types: one value per member ([traits §3.4](traits.md#34-parameters-and-associated-types)).

**Three layers** for questions about open sets:
- `<:` and `isa` read the entries: the answer in the current world.
- `jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint` and the type cache stay exact in the current world. A known member keeps the exact result; a non-member gives `Union{}`. So dispatch's match construction and the inliner's union split see only members.
- `jl_could_join(S, X)` answers the forward-looking question: whether `S` could become a member of `X`. Inference's lattice and the guard's shadow query (§7.4) use it; dispatch's match construction does not.

**Negatives are never folded for an open set** (§7.1), and the test is structural:
- `has_open_set(t)` is true when `t`, a parameter of `t` or a member of a union in `t` is an open set. It is cached on the type object.
- `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the `hasintersect` sites and `Conditional` refinement consult it before folding a negative. So `isa(t, Tuple{X})` with `t::Tuple{S}` is not folded to `false`.

**Positives fold through entries only.** A fold of `S <: X` to `true` raises the CodeInstance's `min_world` to the entry's, so a task in an older world never runs code that assumed the membership.

**`Type{S}` as a member** ([traits §4](traits.md#4-implementations), open issue 91's decision): the entry's pattern is `Type{S}`. `jl_isa`'s branch for a type value and `intersect` consult such entries.

**Inference asks in the world it infers for.** Membership queries during inference run at the query's world, not at the world the compiler runs in.

### 7.3 One dispatch

**Status: Planned** (W-99). Built in part on branch `unified`; its audit is W-97.

- **A bounded method is a plain method** at `Tuple{typeof(f), X, …}`. Nothing is generated beside it: no entry at `Any`, no worker, no untyped fallback, no keyword sorter of its own.
- **The method table:** a method whose signature names an open set goes into its typemap's linear list, never under a typename's index. A query at a member reaches it, since the member's supertype chain never names the set.
- **Specificity per argument** (§7.1) lives in `type_morespecific_`: at a position, a closed type other than `Any` is more specific than an open set. Open against open is ordered by a set-in-set entry (`B <: A`), else unordered. So `Method.interferences`, `detect_ambiguities` and Julia's insertion walk order these pairs as they order any others, and inserting `f(::X)` reaches only the specializations of `f(::Any)` and the "no method" facts.
- **Match world ranges:** a match through an entry carries the entry's `min_world` into its valid worlds, at fixed, vararg and union positions.
- **Abstract queries:** a bounded method at an abstract query whose type is not a member is pruned, as any method with an empty intersection is.
- **The ambiguity report at a membership:** at `jl_declare_membership`, for each function with a method on the new set and a method on another set the member is in, and no method on both, a warning names the pair. It is an error where strict mode protects ([traits §10.3](traits.md#103-strict-mode)). A pair that a third method dominates at every member is not reported. An index from each set to the methods that name it serves the report.
- **A membership lowers dispatch caches and invalidates no code** (§7.1): the `max_world` of each leaf-cache and typemap-cache entry whose selected method changes at the new member is lowered, so the next call looks up again. Compiled code that a membership could change carries a guard (§7.4).

### 7.4 Guards and cells

**Status: Planned** (W-102).

- **The shadow query.** Inference at a call `f(s::S)` with `S` concrete selects a method `m₀`. It also asks for the methods of `f` on open sets `Z` that `S` could join (`jl_could_join`) and that would beat `m₀` at `(S,)`. A method matched through `S`'s supertype chain, other than `f(::Any)`, has none. Each such pair `(Z, position)` is a shadow.
- **The cell.** For each shadow, inference records an edge to a membership cell: one mutable object per (member type object, set) for a parametric member, per (member typename, set) otherwise. The compiler creates it on demand and hangs it on the member's `TypeName`. Its `min_world` is `typemax` until an entry matches, then the entry's.
- **The guard** is a load of the cell's `min_world`, a compare against the task's world, and a two-way branch, emitted as the inliner's union split emits its branches. The slow branch is a full dispatch with no edge; the fast branch is the static call to `m₀`. LLVM hoists the load out of a loop.
- **The guarded call's result** is the bounded method's declared result joined with `m₀`'s ([§7.5](#75-keys-attributes-and-the-check), the declared result on `Method`); `Any` where none is declared.
- **Where guards do not arise:** inside bounded code (an argument there is a member by construction); at a final non-member (§7.1); where `m₀` matched through the chain and is not `f(::Any)`; at a function with no method on an open set.
- **A method on an open set defined later** invalidates the compiled callers that its insertion reaches (§7.3), and they compile again with the guard.

### 7.5 Keys, attributes and the check

**Status: Planned** (W-102).

**A key is a type.** `Core.Keyed{X, R, F}` names the members of `X` whose receiver type is `R` and whose declared fields' types are `F` ([traits §6.7](traits.md#67-what-compiled-code-is-compiled-for)):
- `S <: Keyed{X, R, F}` holds when `S`'s entry for `X` has that key. It is a case of `subtype` as `Type{T}` is, and likewise of `intersect`, `type_morespecific_`, `obviously_disjoint`, `jl_isa_compileable_sig` and `jl_compilation_sig`;
- the erased key is `X` itself;
- `Keyed` is never written by a user. It prints as the key wherever it appears: `ColTable at Vector{Vector{Float64}}`, in `show`, in stack traces (`show_tuple_as_call`), in `MethodError` hints and in reflection ([traits §12](traits.md#12-printing)).

**Per-key code through the compilation signature.** A bounded method carries bits for its bound positions:
- at a `Compiled` position, the compilation signature maps a concrete member `S` to `Keyed{X, R, F}` from `S`'s entry, by the path `@nospecializeinfer` takes (`get_nospecializeinfer_sig`'s analogue), so inference runs once per key, not per member;
- at a `Dynamic` position, the compilation signature is the erased key `X`;
- so one `(method, tuple)` has two compilation signatures: the key for a static caller that knows `S`, the erased key for a dynamic one. Keyed instances are cached with their original tuple (`cache_with_orig`), so the leaf cache maps each concrete tuple to its keyed instance.

**The calling convention of a keyed argument** is the key's parts, for a static caller:
- the receiver by its own convention;
- each declared field that is `@const`, or of an immutable member, by value;
- each writable declared field as a field reference (the object and an offset), so a write reaches the user's object;
- the object itself, boxed, where the method may keep the value (the keep analysis, an escape pass of inference).

**The boxed adapter** serves a dynamic call: one wrapper per keyed CodeInstance that reads the receiver's and the fields' offsets from a table per (member typename, set) on the member's `TypeName`. If it costs more than the dynamic call does today ([evidence §2](../design/evidence.md#2-run-time)), there is one wrapper per member instead (W-102 measures it).

**Attributes are the choice of compilation signature:**
- `Dynamic{X}`, `Compiled{X}` and `Kept{X}` are Core types holding the object; each is a member of `X` at the erased key by a rule of `subtype`, not by an entry;
- `Dynamic{X}` reaches the erased instance; `Compiled{X}` dispatches on its object's type to the keyed instance; `Kept{X}` branches on its flag first;
- casts are constructors of these types; `convert(Kept{X}, x)` is how a plain value enters a field declared with a set's name;
- `Callable`'s `Dynamic` form keeps the `:caller_world` thunk ([§3.1](#31-the-cfunction-calling-convention-caller_world)).

**A declared result on `Method`.** Lowering records `f(…)::RT` as the method's declared result. Inference may read it as an upper bound, because the body asserts it. The guards (§7.4), `Callable` and `return_type` use it.

**The definition-time check** ([traits §9](traits.md#9-checks-and-when-they-run)) is one inference of the method at its erased signature under a check flag of the native interpreter. Only the contract's operations resolve on the bounded argument. Any other use of it is a run-time site, reported as `TraitUseError` or recorded as the method's classification "open".

### 7.6 Compiling by facts, per method

**Status: Planned** (W-100).

- **The policy is the method's:** `facts` or plain, from the module option ([§2.1](#21-the-module-option)) and the method flag ([§2.2](#22-the-method-flag-boundaries-and-always-facts-methods)), which keep their spellings and are saved with the method, so package images keep them. The compiler's own code is plain whoever calls it ([facts §6.4](facts.md#the-compilers-own-code)). Under `facts`, inference commits only at fact signatures ([facts §3](facts.md#facts-and-fact-signatures)) and marks run-time sites ([§1.3](#13-run-time-sites)). The decision is keyed by the caller's method.
- **One CodeInstance per MethodInstance, policy and flags.** In the product setting there is no second owner. The test bed `all` is a default policy for the session, switched by the environment variable, not an owner of its own.
- **The dependency record** of a CodeInstance names everything its code assumed:
  - dispatch edges, bindings and folds, as today;
  - result edges: a call emitted as a call whose result type, exception type, effects or constant the caller used as a type. Nothing else is a result edge: constant propagation, concrete evaluation and inlining depend on the callee's code, and record a code edge;
  - the identity of each inlined method: the method and a digest of its lowered code;
  - the layouts of the types whose fields the code reads;
  - membership cells (§7.4) and the entries of folded positives (§7.2).
- **G2 is a predicate on the record,** computed once when the CodeInstance is finished and kept as a bit in its flags: every dispatch edge is at a fact signature, every inlined method's own record satisfies G2, and result edges may go anywhere. Strict mode and the concreteness checks read it.
- **A facts caller of a plain callee.** Without the slot of §7.7, a caller compiled by facts that calls a plain callee by an emitted call holds an ordinary edge to it, and is invalidated with it ([facts §6.5](facts.md#65-under-traits-in-the-type-system)).
- `fold_call`, `known_type`, `split_call` with the table of a call's targets, and `return_type`'s rule (§1.4, §4) carry over unchanged.

### 7.7 The code slot

**Status: Optional:** built if the estimate of how many callers it would keep (E-261) shows a material share of the sessions' invalidated code.

- One slot per (MethodInstance, calling convention) holds the current valid specialization's pointer and its validity. It is written when a CodeInstance of that MethodInstance compiles and when one is invalidated.
- A static call that holds a result edge to its callee loads its target through the slot. Every other call binds the callee's address, as today.
- When a callee is replaced, a caller that holds only result edges to it is marked for revalidation, not invalidated. The next lookup of the caller compares each result edge against the callee's current result: equal, and the caller is valid again in the current world; different, and it is inferred again.
- With the slot, G2 covers a facts caller of a plain callee whose result is unchanged by the callee's recompilation.

### 7.8 Images, and the machine-code cache

**Status: Planned** (W-103).

- **Memberships in package images.** An image writes the entries it declares on other modules' typenames in a list of its own, as it writes its methods for other modules' functions. At load the list is activated before the image's code is validated: the entries get the loading session's worlds. Validation knows the membership edge kind.
- **A machine-code cache across sessions is the goal of the record.** The record of §7.6 is kept complete, and names its targets by identities stable across sessions (a method by module path, name, signature and a digest of its lowered code; a type by path and layout), so that a cache of machine code later adds a loader, not a mechanism. The cache itself is paused ([decisions](../record/decisions.md) §5).
- No part of §7 stores a world, a session object or an address where a stable identity serves.

---

## Deviations

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| C-1 | — | *Retired*: see [§2.3](#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code)]. | — | — |
| C-2 | — | *Retired*: see [§2.3](#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code), the setting. | — | — |
| C-3 | [§3.1](#31-the-cfunction-calling-convention-caller_world), [§3.2](#32-the-per-call-site-dispatch-cache), [§4.3](#43-what-follows-the-split-the-table-of-a-calls-targets) | A cached entry stays valid until invalidation lowers what it copies. | Exact-type entries and `:caller_world` entries are capped at the latest world when made. After any method definition, every such cached site misses once and looks up again. Wildcard entries are not capped. Every pointer of a split table misses once in its thunk after each method definition: an allocation and a lookup, per pointer (acceptance G1.24, julia-1.13 `split-table`). | `src/gf.c:4670`–`4673`; `src/runtime_ccall.cpp:424` |
| C-4 | — | *Retired*: see [§2.5](#25-dispatch-from-facts-code)]. | — | — |
| C-5 | — | *Retired*: see [§2.5](#25-dispatch-from-facts-code). | — | — |
| C-6 | [§2.1](#21-the-module-option) | A module's other compiler options apply to its code in both modes (Planned). | The module option `compile` (`min`, `no`) is ignored for code of owner `:facts`. | `src/gf.c:3928`–`3933` |
| C-7 | [§5.2](#52-field-offset-intrinsics) | The intrinsics read and write a field of any stored type. | A field stored inline whose type holds references is refused with an error, in codegen (runtime call) and in the runtime. | `src/runtime_intrinsics.c` (`jl_getfield_at_offset`, `jl_setfield_at_offset`); `src/intrinsics.cpp` (`emit_getfield_at_offset`) |
| C-8 | [§4.2](#42-compilersplit_call-the-call-site-split) | `split_call(K, RT, f, x, args...)` is `f(x, args...)::RT` on every path. | Only the split asserts `RT`. When `x`'s type is concrete or `K` has no candidates, the inliner rewrites the call to `f(x, args...)` without the assertion. So it does when no split is built although `x`'s type is open: the candidates and the other arguments' unions exceed `max_union_splitting`, no candidate is admitted by `x`'s type, or inlining is off. Inference types the open call `Any` in every case. The method itself asserts it, so compiled and interpreted code can differ on a result that is not an `RT`. TraitWorld asserts the result after the call. | `Compiler/src/facts.jl` (`split_call`); `Compiler/src/ssair/inlining.jl` (`process_simple!`) |
| C-9 | [§1.4](#14-return_type) | A plain answer is folded when every edge of it rests on facts. | The walk gives up after 2000 `CodeInstance`s, and the site is answered at run time. The walk is not memoized, so each fold walks again. | `Compiler/src/facts.jl` (`rests_on_facts`) |
| C-10 | — | *Retired*: see [§1.4](#14-return_type)]. | — | — |
| C-11 | — | *Retired*: see [§1.4](#14-return_type). | — | — |
| C-12 | — | *Retired*: see [§2.9](#29-what-package-images-keep). | — | — |
| C-13 | — | *Retired*: see [§1.5](#15-effects). | — | — |
| C-14 | [§4.3](#43-what-follows-the-split-the-table-of-a-calls-targets) | The targets and thunks of a split table for declared implementations are compiled ahead, into the declaring package's image. | Each pointer is made at the type's first use at the call's signature in the session: its maker, thunk and target compiled (E-145). | `base/splittable.jl` (`_split_table_miss!`) |
| C-15 | — | *Retired*: see [§1.3](#13-run-time-sites). | — | — |
| C-16 | [§2.5](#25-dispatch-from-facts-code) | A CodeInstance made for an owner's call is that owner's, so its next call finds it. | Where inference failed, the copy of the unspecialized code at the instance's own signature is made for the owner `nothing`; the facts owner misses it and makes another at each such call (stock Julia's plain owner misses there too). A rare path: only after inference failed. | `julia-1.13/src/gf.c:4069` (`jl_compile_method_internal_owner`); `experiments/factscompiler/w89/README.md` |
| C-17 | — | *Retired*: see [§5.4](#54-planned-hooks-for-strict-modes-intended-design), validation's own log. | — | — |
| C-18 | [§7.1](#71-memberships-and-dispatch), [§7.3](#73-one-dispatch) | A membership lowers dispatch caches and invalidates no code; a guard covers a compiled call that a later membership could change ([§7.4](#74-guards-and-cells)). | Until the guards exist (W-102), `jl_declare_membership` replays Julia's method-insertion walk for every method at the set or a superset, as if the member's tuple had been inserted: compiled callers the membership could change are invalidated, and each declaration logs how many. | branch `unified` c3f0b4bc11: `src/datatype.c:288` (the call), `src/gf.c:2105` (the replay in the insertion walk) |
| C-19 | [§7.2](#72-memberships) | A type value is a member of a set only by an entry for `Type{S}`; `S <: X` and `S isa X` are different questions. | An entry for `S` also answers `S isa X` and `Type{S} <: X`, so a bounded method on `X` is called with the type object `S` ([the audit](../reviews/2026-11-06-oc-build-audit.md) A1). | branch `unified` c3f0b4bc11: `src/subtype.c` (`jl_membership_holds`, `subtype`'s `Type{T}` arm, `jl_isa`); `experiments/unification/audit/probes.jl` P1 |
| C-20 | [§7.5](#75-keys-attributes-and-the-check) | `Dynamic{X}`, `Compiled{X}` and `Kept{X}` are members of `X`: subtyping, intersection and dispatch agree. | Subtyping and `isa` erase a wrapper to its set, intersection and the method table's match do not: a call with a `Dynamic{X}` reaches the fallback, not the method on `X` (A2). | branch `unified` c3f0b4bc11: `src/subtype.c` (`intersect`); probe P2 |
| C-21 | [§7.2](#72-memberships) | Any member pattern a type can be written in is a membership. | A pattern with more than eight type variables is accepted and never matches (A3). | branch `unified` c3f0b4bc11: `src/subtype.c` (`jl_membership_env_match`); probe P3 |
| C-22 | [§7.2](#72-memberships) | Every membership is explicit; `isa(x, T)` and `typeof(x) <: T` agree. | `isa`, intersection and dispatch compose memberships through set-in-set entries, `<:` does not (A8). | branch `unified` c3f0b4bc11: `src/subtype.c` (`jl_membership_lookup_level`'s `chain`), `src/typemap.c`, `src/gf.c` (`membership_superset_sets`); probe P4 |
| C-23 | [§7.2](#72-memberships) | Set-in-set memberships never form a cycle. | A cycle closing through a set's second entry is accepted (A6). | branch `unified` c3f0b4bc11: `src/datatype.c` (`jl_declare_membership`); probe P5 |
| C-24 | [§7.1](#71-memberships-and-dispatch) | Core's kinds, the builtins included, are never members. | A builtin function's type is accepted as a member (A9). | branch `unified` c3f0b4bc11: `src/jltypes.c` (the `never_member` bits); probe P6 |
| C-25 | [§7.2](#72-memberships) | `@implement` lowers to the declaration followed by `Expr(:latestworld)`; the runtime does not set a task's world. | `jl_declare_membership` sets the declaring task's `world_age` to the entry's world (A12). | branch `unified` c3f0b4bc11: `src/datatype.c` (`jl_declare_membership`) |
