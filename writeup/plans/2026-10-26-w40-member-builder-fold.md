# W-40: a family member's builder fixed in its callers' code

Status: **proposal, revision needed** (2026-10-26; reviewed 2026-10-27, [the review](../reviews/2026-10-27-w40-member-builder-fold.md): four blockers). Not normative. Do not build §4 as written; §10 says what changes.

Serves: [W-40](../record/todo.md); open issue 49 (closed, option (b), [decisions](../record/decisions.md) "A family member's builder is fixed in the code of a caller that knows its type"); [lowering §4.6](../reference/lowering.md#46-families), [L-37](../reference/lowering.md#18-deviations); [traits §4.7](../reference/traits.md#47-families). E-161 and move 2's callbacks (E-158) wait for it.

## 1. The problem

A typed call of a family member opens the member through the family's registry at every call:
- The family's `conformance` method is `conformance(::As{X}, u::S{P}) where {P} = _conf_family(reg, X, u)` (`TraitWorld/src/implement.jl`, `_family_conformance_methods`).
- `_conf_family` looks the member's type up in `reg[]`, an `IdDict{Any,Any}`, and calls the builder it finds at the abstract type `Builder` (`implement.jl`, `_conf_family`).
- So the trait object's type is unknown to the caller. Everything after it is a dynamic call.

The cost is in [L-37](../reference/lowering.md#18-deviations) (E-156 P15, P13). In short: hundreds of nanoseconds and an allocation per call, against about a nanosecond for a member declared on its own. Move 2's callbacks pay it twice per step (E-158).

A declared type does not pay it: its `conformance` method calls a builder fixed at the declaration, a constant of the declaring module. The caller's inference sees the constant, so the trait object's type is known.

## 2. What is decided

[traits §4.7](../reference/traits.md#47-families) and [lowering §4.6](../reference/lowering.md#46-families) state the intended shape:
- **Compiling a caller that knows a member's type is a use** of the member. The member is checked and fixed then.
- Its typed calls then cost what a declared type's do.
- A member that does not conform raises `ImplementError` at the call.

The decision's wording adds a mechanism: "with edges on the methods the check read". §5 proposes another mechanism for the same outcome, and asks the user to confirm it (question 1).

The decided paragraph names no compiler interface that could run the check while a caller is inferred. The lowering review of 2026-10-26 found this independently (M5). §4.1 proposes the interface.

## 3. The proposal in brief

1. **A compiler primitive, `Compiler.fold_call(g, args...)`.** Where every argument is a constant to inference, inference calls `g(args...)` in the inference world and makes the call the constant `g` returns. Elsewhere the call is `nothing`. It is `known_type`'s pattern for values: the library writes the run-time path beside it, and both compute the same result.
2. **TraitWorld's family `conformance` method uses it** with a function that checks and fixes the member, exactly as the slow path does: one function, one registry, so the fold and the run time give one answer.
3. **A fold is kept with the code that holds it.** When a package image loads, each kept fold is evaluated again in the loading session. The same value: the code is kept, and the member is fixed in this session as a side effect. Another value, `nothing`, or an error: the code is discarded, as when an edge fails, and compiled again at its next call.
4. **What counts as a use:** compiling a caller that knows the member's type, and loading code that holds a fold for it.

No edges on the methods the check read: §5 says why they are not needed, and why they would weaken G2.

## 4. The design

### 4.1 The compiler: `Compiler.fold_call`

```julia
Compiler.fold_call(g, args...)    # g(args...) where inference folds it; else nothing
```

Lives in `Compiler/src/facts.jl`, with a case in `abstract_call_known` (`abstractinterpretation.jl`), as `known_type` and `split_call` have.

**Meaning.**
- **Where it is folded:** every argument is a constant to inference (`Const`, or a singleton type such as `Type{X}` of a concrete `X`), in either mode. Inference calls `g(args...)` in the inference world, outside a pure callback, as concrete evaluation calls a function. If `g` returns a value `v`, the call is `Const(v)` with total effects, and the optimizer removes it. If `g` returns `nothing` or throws, the call is the constant `nothing`.
- **Where it is not folded:** the interpreter, code compiled at abstract types, an argument inference does not know. The call returns `nothing` when it runs. `g` is never called at run time.
- **The fold record.** A folded call adds a record `(g, args, v)` to the frame's edges. It has no backedge: nothing invalidates it in a session.
- **At load.** For each CodeInstance an image keeps, after its edges are verified, every fold record is evaluated again: `g(args...)` in the validation world, after the image's methods are active. If the result is `v` (egal), the code stays valid. Otherwise the code is invalid, as with a failed edge.

**Rules,** for the library that calls it:
- **Same result on both paths.** Code uses `fold_call` only where the folded path and the run-time path compute the same result. This is `known_type`'s rule, and it keeps G1.
- **One answer per session.** Once `g` has returned `v` for some arguments, it returns `v` for them for the rest of the session. The library keeps the answer, as the family's registry does.
- **Side effects of a use only.** `g` may record that its answer is now fixed. It must tolerate being called more than once, speculatively (for code that never runs), from several threads, and re-entrantly; a re-entrant call returns `nothing`.
- **Data an image can keep.** `v` holds no pointer of a session. A value that would is not folded: `g` returns `nothing`.

**Why a primitive, not a generated function.** A generator runs as a pure callback: Julia refuses code reflection there, and the member check is reflection (it looks methods up and infers their results). Concrete evaluation runs ordinary code, but it records no fold, and an asserted effect is ignored over a run-time site in the facts mode ([compiler §1.5](../reference/compiler.md#15-effects)).

### 4.2 TraitWorld: the family's `conformance` method

The method `_family_conformance_methods` defines becomes, in substance:

```julia
function conformance(::As{X}, u::S{P}) where {P}
    b = Compiler.fold_call(_member_fold, reg, X, typeof(u))   # reg: a constant of the declaring module
    b === nothing || return b(u)
    return _conf_family(reg, X, u)                               # the run-time path, as today
end
```

- **The fold sits in the generated method,** so `reg` is a constant global of the declaring module, and `typeof(u)` is a constant wherever the method is specialized at a concrete member.
- **`_member_fold(reg, X, U)`** returns the member's builder, or `nothing`:
  - a builder in the registry: that builder;
  - else the slow path's work: the member check (`_check_member`), the builder (`_family_builder`), the registry entry and the override index (`_index_builder!`);
  - a member that does not conform, a builder that holds pointers of a session (`_conformance_builder` returns `nothing`), a re-entrant call: `nothing`.
- **A member that does not conform** is not folded. The call takes the run-time path, whose slow path raises `ImplementError` with the message it has today. So the error comes at the call, as decided.
- **The world.** The member check reads the latest world today (`_latest`, which is `invokelatest`). Under the fold it must read the world it is called in: the inference world, or the validation world at load. The check takes the world from the task (`Base.tls_world_age()`), as `_conformance_slow` already does.

**What does not change:**
- the run-time path (`_conf_family`, `_conf_family_slow`), for untyped callers and code compiled at abstract types;
- the untyped callers' table ([lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)). It finds a member's builder once per type, at a miss (`_umiss`, `untyped.jl`), not per call;
- the registry the declaring package's workload fills and its image keeps;
- a declaration for one member: a more specific `conformance` method, which the caller's call edge follows.

**At a `Dynamic` family member,** the split infers each branch at a concrete candidate, so each branch folds. E-156 P13's case is covered by the same change.

### 4.3 Images

- **The declaring package's own code** folds members its workload fixed. At its load the fold finds the registry its image keeps: a lookup, egal, kept.
- **Another package's code** (a solver, a user's package) folds members of a family it does not declare. Its image keeps the code and the fold records. At its load each record runs `_member_fold`: a registry hit if the member is fixed already, else the member check, once per member per session.
- **So the member is fixed in every session where code with its builder can run,** before that code runs. A later override of an operation its defaults serve is refused, as after a first use on the slow path ([lowering §4.8](../reference/lowering.md#48-overrides-and-redeclaration)). Without this, a session could hold values built with the folded builder and, after an override, others built with a new one: two implementations of one member.
- **The cost moves to load:** one member check per member not yet fixed, per session. It is to be measured (§7), with W-47 in view.

## 5. Why not edges on the methods the check read

The decision says "with edges on the methods the check read". This section argues for evaluation at load instead.

**Edges are not needed in a session.** The registry is fixed for the session. A later definition that changes what the check read is either refused (an override of a default-served operation) or does not change the member's builder (the slow path does not look again). So a folded caller compiled in the session holds the builder the slow path would give, whatever is defined after it. An edge would only cause recompilations that fold the same builder again.

**Across sessions, edges are not enough.** Edges would discard an image's code when the check's inputs changed. They would not fix the member at load. So the session could build values with the image's builder, accept an override, and then build values with another: §4.3's two implementations. Fixing the member at load needs the fold record anyway. With the record evaluated at load, the edges add nothing.

**Edges would weaken G2.** The check reads method tables at the operations' declared argument types. Where a declared argument type is abstract (`AbstractVector`, an iteration state), it asks whether any method exists (`_has_op_method`, `conformance_problems`). An edge there is a method-table edge on an abstract signature. Any package that adds an intersecting method invalidates the caller, stakeholder or not. Code compiled by facts holds no such edge today ([facts G2](../reference/facts.md#g2)).

**Evaluation at load gives the slow path's answer by construction.** The same function computes both, in the session where the code runs.

**What evaluation at load costs:**
- load time: one member check per member and session, where the registry misses;
- a new kind of record in a CodeInstance's edges, which the image's validation must handle (`Compiler/src/reinfer.jl`, `verify_method`), and which `rests_on_facts` (`facts.jl`) counts as resting on facts.

**G2 under evaluation at load.** A fold kept in an image's code is discarded at load exactly when the member's implementation differs in the loading session. Which definitions can make it differ is a property of the member check, not of the fold: see question 2.

## 6. Questions for the user

1. **Evaluation at load instead of edges** (§5). The outcome is the decided one. The mechanism differs from the decision's wording. **Recommendation:** evaluation at load. The decision log row and lowering §4.6's planned paragraph change with it.
2. **The member check at abstract declared arguments.** Where an operation's declared argument type is abstract, the check asks only whether some method exists at `(U, declared types…)`. A method added there by the owner of any other type (`op(::U, ::MyVec)`) changes the member's witness, from served by the default to served by its own method. With the slow path today, the member's implementation then depends on whether that package loaded before the member's first use. Under the fold, an image's code is then discarded at load. This predates W-40 and applies to a single type's declaration too, at its declaration. **Recommendation:** a separate open issue, not a part of W-40. Option: at an abstract declared argument, count only the methods of the member's stakeholders (the owners of the operation, of `S` and of the parameters' types).
3. **An override by the parameter type's owner, and load order** (the traits review of 2026-10-26, M11). The owner of `MyT` may override member `S{MyT}` until its first use ([traits §4.7](../reference/traits.md#47-families)). Compiling a caller is a use, and so, under this note, is loading code that folds the member. Whether another package's precompilation used the member first is not under the owner's control. **Recommendation:** accept such an override only in the parameter type's owner's own package. Any code that names `S{MyT}` when it is compiled depends on that package, so the override is always loaded first, in every load order. This changes a rule of an existing feature (T-28), so it is the user's.

## 7. Validation

An experiment row before the run (the next free ID, E-167): *does a folded typed call of a family member cost what a declared member's does, and does an image keep its folds valid across loads?* The result that would change the design: a folded call that stays above a declared member's cost, or a load that discards folds it should keep.

**Checks:**
- **Cost:** E-156 P15 again (a typed loop: expected at the declared member's cost and allocations, same build, same machine); P13 (an operation on a `Dynamic` family member); E-158 move 2's per-step overhead.
- **Code:** `code_typed` of a typed caller holds the builder as a constant, with no registry read and no call to `_conf_family_slow`.
- **Not folded:** a caller compiled at an abstract type takes the run-time path.
- **A member that does not conform:** its caller compiles; the call raises the slow path's `ImplementError`.
- **Overrides:** after a fold in a session, an override of a default-served operation is refused. After loading an image whose code folds a member, the same.
- **Images:** a package whose workload folds a member of another package's family. In a fresh session its code is kept and the member is fixed at load. With a package loaded first that gives the member another implementation, the code is compiled again, and results equal the slow path's.
- **Re-entrancy:** an operation's default that calls a bounded function on the same member.
- **Threads:** two tasks compiling callers of the same member at once.
- **Load time:** an image folding several members, loaded fresh, against the same image without folds.

The facts acceptance suite gains checks for the fold (G1: the same result folded and not; G2: a fold kept across an unrelated load). Every suite runs, as after any compiler change.

## 8. What changes where, once adopted

| Where | Change |
|---|---|
| `reference/compiler.md` | A new §4.4, `Compiler.fold_call`; §2.9, what images keep: fold records, evaluated at load; the Summary table |
| `reference/facts.md` | G1's conditions name `fold_call` beside `known_type`; G2 and §11 name a fold kept in an image as discarded at load when its value differs |
| `reference/lowering.md` | §4.6's planned paragraph: the fold, evaluation at load, a member that does not conform takes the run-time path; L-37 retired once built |
| `reference/traits.md` | §4.7: loading code compiled for a member is a use too |
| `record/decisions.md` | The row on open issue 49: the mechanism, quoting the user's answer to question 1 |
| `design/julia-changes.md` | The new change, with its commit |
| `record/experiments.md`, `design/evidence.md` | E-167's row and results; L-37's numbers replaced |

## 9. The build

1. **The patched Julia:** `fold_call` and its fold record (`facts.jl`, `abstractinterpretation.jl`, `stmtinfo.jl`), the record's evaluation at load (`reinfer.jl`), `rests_on_facts`. Compiler tests beside `split_call`'s.
   - To verify before building: whether C code walks a CodeInstance's edges by kind when an image is written or read (`src/staticdata.c`, `src/staticdata_utils.c`). If it does, the record needs a case there too.
   - The changes are Julia code in the compiler, so a system image rebuild (`TW_TARGET=julia-sysimg-release`) may do; a C change needs a full build. Either runs at night, started by the user outside the sandbox.
2. **TraitWorld,** on a branch: `_member_fold`, the member check in the caller's world, the re-entrancy guard, the generated `conformance` method. Tests in `test/` for the checks of §7 that need no image; the image checks in `experiments/`.
3. **The checks of §7,** then every suite, then the reference changes of §8 in one commit with the row of L-37 retired.

## 10. After the review (2026-10-27): what must change

[The review](../reviews/2026-10-27-w40-member-builder-fold.md) holds §5's core argument (something must fix the member at load; edges cannot), and finds four blockers in the mechanism.

**The blockers:**
- **B1, deadlock.** Inference holds `jl_typeinf_lock` and runs in the compiler's world (`src/gf.c:480`–`496`). §4.1's premise was wrong: concrete evaluation runs as a pure callback (`src/builtins.c:912`–`935`). The member check takes TraitWorld's `_LOCK`, runs inference and JIT compilation under it, may warn, and may run a generic implementation's predicate: user code. Called from inference, it can deadlock against a thread on the run-time path.
- **B2, the edge walkers.** `ForwardToBackedgeIterator` (`Compiler/src/typeinfer.jl`, used by `store_backedges`) and `verify_method` (`reinfer.jl`) read an unknown edge item as an invoke signature and a callee. Both need a case for the record. C code tolerates it: no C change.
- **B3, the world.** Inside inference the task's world is the compiler's; the check also reads the latest world in many places. A task in an older world could fix a builder that ignores an override already defined later.
- **B4, load order.** Folds are evaluated during image validation, before the package callbacks that load extensions. An override in the parameter type owner's extension would be refused or accepted by load order. Decision 63 now excludes extensions ([traits §4.7](../reference/traits.md#47-families)).

**The directions:**
0. **Keep the mechanism, with a discipline for `g`** (recommended; the review's own suggestion). The compiler calls `g` with `Core._call_in_world` in the inference world, not as a pure callback, so the records defined by packages are visible. `g` then:
   - never blocks: it takes TraitWorld's lock with `trylock`, and returns "not folded" when it is taken, so no thread waits for the lock while holding the inference lock, and none waits for the inference lock inside `g`;
   - never yields: no I/O (a warning is queued and printed by the run-time path), no contended lock, no task;
   - runs no user code: a member whose check needs a generic implementation's predicate is not folded;
   - may infer: nested inference under the recursive inference lock is what `facts_plain_return_type` already does;
   - fixes a member only when the inference world is the latest world; otherwise only a registry hit folds (B3).
   B2's walkers, B4's decision and the should-fix list below as for direction 1.
1. **The compiler infers, the library only reads** (the fallback if direction 0's discipline cannot be kept in TraitWorld's check). `g` becomes pure: no lock, no inference, no I/O, no user code. It returns a registry hit, or a plan: the operation signatures to check with their declared results, from the records. The compiler infers those signatures with its own interpreter, as `return_type`'s fold does, and hands the results to a second pure step that decides and builds. The registry insert is an atomic replace. A refusal, a warning or a member that needs a generic predicate is not folded: the run-time path handles it, as today. A member is fixed only when the inference world is the latest; otherwise only registry hits fold (B3).
2. **Fold registry hits only, and recompile callers when a member is fixed at run time.** Simpler in the compiler, but it needs a way to invalidate the callers that folded a miss, which images and closed modules make hard. Callers compiled before the first call (the solver's callbacks) would stay slow until then.

**Also to change** (the review's should-fix list):
- a fold made during constant propagation keeps its record (S1);
- a member refused or not foldable is remembered, so it is not checked at every inference and load (S2, S8);
- one function computes a member's builder, for the slow path, the table and the fold, in one world (S4);
- §5's in-session argument needs L-23 fixed: a member's declaration after its first use refused (S5);
- the records are evaluated once each, in a pre-pass at load, under `require_lock`, before `__init__` (S6);
- folding only for the native interpreter's compilation, not reflection, analysis tools, `return_type` or the split's candidate inference (S7);
- question 2 becomes a G2 deviation row once W-40 is built (S9);
- §7 gains older-world, load-order (an extension, `--pkgimages=no`), reflection and constant-propagation cases; the thread test proves little while 1.13 serialises inference.

**Next:** rewrite §4 along direction 0, then a second review before building.
