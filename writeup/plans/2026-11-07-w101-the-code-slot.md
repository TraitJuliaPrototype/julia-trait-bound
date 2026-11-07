# W-101: the code slot, how it is built

Status: **adopted**, done (`unified` 7500630036; built with two changes to §2: inference's cache miss revalidates too, so §2.6 does not hold; the compiler's own bootstrap binds every call, compiler C-67) (2026-11-07, mine, under the user's standing "Continue with everything. I am away from the machine. Try to finish the unification on your own as far as possible."). Not normative: the rules are in [compiler §3.3](../reference/compiler.md#33-the-code-slot); the choices below are listed in [open issues §1](../open-issues.md#1-decisions-waiting-for-the-user) for the user to confirm.

## 1. What the reference asks

- A static call that holds only a result edge to its callee loads its target through a slot.
- When the callee is replaced, the caller is marked for revalidation, not invalidated.
- Its next lookup compares the callee's current result with the one it used. Equal: valid again. Different: inferred again.

## 2. The choices (mine)

1. **The record of result edges lives in the CodeInstance's analysis results.** At the end of optimization the compiler lists the callees that the code reaches only by an emitted `:invoke` whose statement type is the callee's result. Excluded:
   - a callee inlined anywhere in the code;
   - a callee concretely evaluated or constant-propagated anywhere;
   - a callee reached through `invoke` or a match list.

   The list is a `ResultEdges` entry on the CodeInstance's analysis results. Images keep it with the CodeInstance, and no new field is needed. It is the result-edge half of C-52.
2. **One slot per call site, not per (MethodInstance, calling convention).**
   - The slot is a module-local global that holds the CodeInstance the site last called.
   - A call checks the task's world against that CodeInstance's world range and calls its specialized entry.
   - On a miss, the runtime finds the callee's code valid in that world and refills the slot.

   Nothing writes the slots when code compiles or is invalidated. Images start them empty.
3. **A mark is an invalidation that can be undone.** A marked CodeInstance's `max_world` is lowered like an invalidated one, with a flag set. So every cache that checks worlds misses it without change:
   - dispatch;
   - `cfunction`;
   - `invoke`;
   - the slots.
4. **Which callers the walk marks:**
   - It marks a caller when the callee was invalidated through its own edges, not replaced by a definition at its signature, and the caller's only edge to it is a result edge.
   - It invalidates every other caller, including one that holds a code edge to a marked callee.
   - It goes on from a marked caller as from an invalidated one.
   - A later invalidation of a marked CodeInstance clears the flag, so the mark becomes final.
5. **Revalidation runs where code is about to run.** That means `jl_compile_method_internal` (dispatch, `invoke`, `cfunction`) and the slot's miss.
   - It runs only in the latest world.
   - For each edge to a CodeInstance not valid there:
     - a marked callee is revalidated first, depth first, and a cycle fails;
     - a result edge infers the callee again and compares its result: return type, exception type, constant and effects.
   - The callee's new CodeInstance must be valid from the world of the mark. Otherwise it fails.
   - On success:
     - the edge names the new CodeInstance;
     - its backedge is added again;
     - the flag clears;
     - `max_world` is restored.
   - On failure, the mark becomes an invalidation.
6. **Inference does not revalidate.** New code that calls a marked callee infers that callee again. A deviation row says so.
7. **A switch:** `JULIA_CODE_SLOT=0` turns the slot off: codegen binds every call's address, and the walk marks nothing. The switch is for E-283's cost measurement, and as a safety valve. (As built: the system image keeps the slots it was built with, so the switch covers the session's code only; [the review of the day](../reviews/2026-11-07-implementation-day.md) M1.)

## 3. Soundness, in brief

- Code that runs in a world past a mark must have been revalidated in that world.
- There are three ways in:
  - Dispatch and its relatives miss the lowered `max_world` and revalidate.
  - A slot misses it in the same way.
  - A call by address comes only from a caller with a code edge to the callee, or a caller that is not a result edge's. The walk invalidates or marks every such caller, so it cannot run either.
- Revalidation compares the callee's result in the latest world, from the world of the mark on. An equal result means each use the caller made of it still holds: the type, the exception type, the effects and a constant.

## 4. Steps and gates

1. The compiler's list, with a reflection test.
2. Codegen's slot and the runtime's slow path, with the switch.
3. The walk's marks and revalidation.
4. **Gate:** the synthetic cascade (`experiments/unification/stack/slot_cascade.jl`).
   - A facts caller and a plain caller, each over a plain callee that is recompiled when a method it dispatches to is added.
   - With an equal result: the callers' CodeInstances are kept, their results are the new ones, and code in the old world sees the old ones.
   - With a different result: the callers are compiled again.
   - In a package image too.
5. **E-283:** the slot's cost, and the session's count. A call through the slot against a bound call. The two workloads with the slot on and off.
6. The battery, the acceptance cases, TraitWorld's tests.
