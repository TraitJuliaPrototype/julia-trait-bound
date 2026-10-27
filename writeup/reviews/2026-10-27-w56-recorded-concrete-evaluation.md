# Review: W-56, concrete evaluation with recorded dispatches (note of 2026-10-27)

Reviewed: `writeup/plans/2026-10-27-w56-recorded-concrete-evaluation.md`, against julia-1.13 26a407d988 (source read, nothing run).

## Verdict

1. **Unsound as written.** Recorded dynamic dispatches are not the whole dependency set. The compiled code the evaluation runs holds static dispatch decisions too. In the product setting (P4), that code is plain code. And the proposed edge form `1, sig, method` registers no backedge in a session.
2. **Repairable, but much larger than drafted.** The repair needs five things: run the facts CodeInstance, record the CodeInstances entered and copy their edges, use MethodInstance edges at the exact signature, hook or poison every lookup that bypasses `jl_lookup_generic_`, and suspend recording during nested inference.
3. **There is a simpler, sound route for E-162's case.** Make Base's padding helpers fully typed under the facts forms that already exist: `invoke` at declared signatures, builtins, and a typed tuple instead of an `svec`. They then fold under today's rule with ordinary edges. Keep W-56 deferred until a census shows the pattern beyond `padding`.

---

## Findings

### Blockers

**B1. Static dispatch decisions in the executed code escape the recorder.** Note §2 (last paragraph), §3 step 2.
- What is wrong:
  - The value depends on every dispatch the evaluation *performs*. Most of those are not lookups at run time. A call that inference resolved is compiled as a direct call to a CodeInstance, through its specptr or `_jl_invoke`, and passes no hook in `jl_lookup_generic_`.
  - Those decisions live in the forward edges of each CodeInstance executed.
  - The caller's edge to `result.edge` does not cover them. That is the facts CodeInstance at `Type{Dual…}`, and it holds run-time sites. Below a run-time site, the code executed belongs to *other* CodeInstances, compiled at the compileable signature (`DataType`), whose edges the fold never names.
  - So "the fold rests on the facts it actually used" (§2) is false.
- Fix:
  - Record each CodeInstance the evaluation *enters*: the top one, and each one reached through `_jl_invoke_owner` after a dynamic lookup (gf.c:4430, 4884, 4889).
  - Copy those CodeInstances' forward edges into the caller's edges. Copy the edges, not the CodeInstance: its MethodInstance is at `DataType`, so an edge to it is broken by any owner's `fieldoffset(::Type{MyT}, …)`, which breaks G2.
  - Deeper static callees are then covered through the ordinary backedge chain.
  - Refuse the fold if a copied edge is not a fact.

**B2. In the product setting the evaluation runs plain code, so the recorder sees almost nothing that matters.** `concrete_eval_call`, `Compiler/src/abstractinterpretation.jl:1041`.
- What is wrong:
  - `Core._call_in_world_total(world, f, args...)` calls `jl_apply` (`src/builtins.c:925`), then `jl_apply_generic`, which runs the default owner's code.
  - `jl_default_owner` (`src/gf.c:424`) is `nothing` for Base's neutral `array_subpadding`. So in P4, where E-162 measured, the plain CodeInstance runs.
  - Plain inference resolves `padding(::DataType, ::Int)`, `fieldoffset(::DataType, ::Int)`, `fieldcount` and `getproperty(::Type, …)` statically, one method each. None of them is a dynamic dispatch.
  - The recorder would see only the `Any`-typed calls on `svec` elements (`getproperty(::Padding, …)`, `+(::Int, ::Int)`), all facts. So the call folds with no edge for any of the kind calls whose change it must follow. That is the pre-W-52 hole of G1.19, back again.
  - Plain code's edges are not facts either (method-table edges at `DataType`), so B1's copy cannot be applied to them.
- Fix:
  - Evaluate the facts CodeInstance itself: `invoke(f, result.edge::CodeInstance, args...)`. 1.13 supports `invoke` with a CodeInstance (`base/docs/basedocs.jl:2081`). Check that it compiles the CodeInstance on demand.
  - Its run-time sites then go through `jl_apply_generic_facts` (`gf.c:4872`, `facts_callee_owner`) and run facts code.
  - Refuse the fold whenever a plain CodeInstance is entered:
    - in the product setting, owner `nothing`;
    - under `all`, a `jl_method_is_plain` method, because of C-2.
  - Every runtime `jl_apply` falls under this refusal: `jl_f__apply_iterate` over a non-tuple, `jl_call`, finalizers. These run the default owner's code (compiler §2.5).

**B3. The edge form `1, sig, method` gives no backedge in a session.** Note §3 step 2, and §4's question.
- What is wrong:
  - `ForwardToBackedgeIterator` (`Compiler/src/typeinfer.jl:737–742`, also :759) skips the count and the signature, then skips `Method` items ("ignore `Method`-edges").
  - The form is fully covering, so it adds no `sig, Core.methodtable` edge either.
  - It is checked only by `verify_call` at image load (`reinfer.jl:228–233`).
  - So a stakeholder's `fieldoffset(::Type{Dual…}, ::Int)` defined after the fold invalidates nothing in the session. G1.10, G1.19 and G1.32 redefine the dispatched method and would fail.
- Fix:
  - For each distinct record, run the compiler's own lookup at the recorded signature in the inference world (`find_method_matches`).
  - Emit what plain inference emits: `MethodMatchInfo` through `_add_edges_impl` (`stmtinfo.jl:49ff`). Its edge is a MethodInstance at the exact signature (`specialize_method`), with a backedge on that MethodInstance. Only a method that intersects `Type{Dual…}` breaks it, so G2 holds.
  - "No method" and "ambiguous" then come out in the existing forms: `sig, Core.methodtable` plus the count form.
  - Require the lookup to select the recorded method, and narrow the caller's valid worlds to the lookup's range.

**B4. Lookups that bypass `jl_lookup_generic_` escape the recorder.**

| Path | Where | What it depends on | Required |
|---|---|---|---|
| `invoke` builtin | `jl_gf_invoke` gf.c:4940; `jl_gf_invoke_by_method` gf.c:4960 (per-method `invokes` cache) | resolution of the *declared* signature | an invoke edge (`sig, MI`), not a dispatch at the value's signature (§3 conflates the two) |
| split-table fallback | `jl_split_table_ptr` gf.c:1161; `:caller_world` thunks (compiler §3.1, §4.3) | the target `_SplitTarget…` CodeInstance's static call | copy that CodeInstance's edges (B1), or poison |
| `applicable` | `jl_f_applicable` builtins.c:1673, then `jl_method_lookup` gf.c:3472 | method or no method at a signature | record as B3, or poison |
| `hasmethod`, `_hasmethod`, `which`, `methods`, `_methods_by_ftype` | `jl_gf_invoke_lookup` gf.c:4907; `jl_matching_methods` | the method table, at possibly abstract signatures | poison (hasmethod's tfunc form at most) |
| `return_type`, `promote_op` | run-time inference | the method table through inference, with no dispatch | poison, or `PlainRTInfo` edges |

- Fix: whitelist. Recording keeps only lookups in `jl_lookup_generic_` and `jl_gf_invoke*`. Any other method-table query, or a split-table probe, poisons the recording, and nothing folds.

**B5. Nested inference pollutes the recording, so folds depend on compile order.** Note §4, "Re-entrancy".
- What is wrong:
  - The evaluation can JIT a callee. `jl_type_infer_owner` clears `in_pure_callback` and takes the recursive `jl_typeinf_lock` (gf.c:484–496) on the same task.
  - The compiler's own dispatches would land in the recording: hundreds of them, many not at facts. `widenconst` alone is called 64,968 times in `ndport/logs/p4-regress-hot.log`.
  - This is not unsound, since a non-fact record refuses the fold. But the first inference of a call refuses whenever its callees' facts code at `DataType` is not compiled yet, which is the normal case for E-162. Later inferences fold.
  - So whether `reinterpret` folds, and what a package image holds, depends on compile order, and E-162's regression may well stay.
- Fix:
  - Keep a stack of recorders on the task.
  - Save, clear and restore it in `jl_type_infer_owner`, `jl_call_in_typeinf_world` (gf.c:585), `jl_gdbcodetyped1`, the codegen entry and staged-function expansion.
  - Push and pop it inside one C builtin, for example `Core._call_in_world_recorded(world, ci, f, args...) -> (value, records)` with `JL_TRY`, not in separate begin/end ccalls.

### Should fix

**S1. §1's diagnosis is incomplete.** `base/reinterpretarray.jl:769–818`.
- `padding` returns `Core.svec(pads...)` (:783). `CyclePadding{SimpleVector}` iterates with `iterate(::SimpleVector)` (`essentials.jl:996`), which yields `Any`.
- So `array_subpadding`'s *own* frame holds run-time sites at `Any`, whatever the kind calls do: `y[1].offset`, `+` (:762), `intersect(ps, pad)`, `ps.offset > pad.offset` (:814–816).
- The profile shows both kinds of site (`p4-regress-rodas.log`):
  - `getproperty` at `Base_compiler.jl:57`, the `::Any` method: 344,400 calls;
  - `getproperty` at `:51`, the `::Type` method: 861,000 calls.
- At the top, `padding` is inferred at `Type{Dual…}`, the exact signature, so its own kind calls are facts there. The kind run-time sites arise in the recursive `padding(fT, offset)`, where `fT` comes from `fieldtype(T, i)` with a non-constant `i`. Confirm this with `code_typed` before choosing a route (Q3).

**S2. The note does not say where the records live.**
- `ConcreteResult` (`stmtinfo.jl:177`) carries one CodeInstance, and `compute_edges!` (`typeinfer.jl:812`) collects edges from `stmt_info`.
- The records need a `CallInfo`, or a `ConstCallInfo` whose `add_edges_impl` includes them.
- Semi-concrete evaluation (irinterp) adds no new edges, so recorded folds must be disabled there.
- The folded call's effects then get `nortsite` set, from `EFFECTS_TOTAL`. Say so explicitly, because callers may now fold over it.

**S3. Errors.**
- Plain `concrete_eval_call` turns a throw into `Bottom` (`abstractinterpretation.jl:1042–1047`). The recorded path must not reuse that catch.
- A throw can come from the pure callback itself. `hasmethod` with the default world raises, because `jl_get_world_counter` returns `typemax` in a pure callback (gf.c:45; `reflection.jl:1095`).
- It can also come from a `MethodError` that a later method would fix.
- §3's "nothing folds" is right. State that it does not reuse plain's catch, and test it.

**S4. Eligibility is underspecified.** §3, "where a call's effects are not foldable only because an assertion was dropped".
- The stored effects do not record this. Compute `adjust_effects(ipo_effects, def)` (`typeinfer.jl:495`) at the call and test `is_foldable`.
- Statement-level assertions (`merge_override_effects!`, `abstractinterpretation.jl:3654`) are not addressed. Say whether they are in scope.

**S5. The cost of the hook when off.**
- "A separate entry the concrete evaluator calls through" cannot work. Compiled code calls `jl_apply_generic`/`jl_apply_generic_facts` directly, so a separate entry sees none of those dispatches. Delete this option.
- The hook belongs at the end of `jl_lookup_generic_`, beside `dp_count` (gf.c:4845). There it covers the site, leaf, assoc and full paths, including wildcard and exact-type site entries.
- Pass `ct` from `jl_apply_generic` and `jl_apply_generic_facts`, which already read `jl_current_task`.
- Add a record before `jl_method_error` (gf.c:4834) for "no method" and ambiguity.
- The cost is one load and one branch, like `dp_on`. Measure it with the call benchmarks only.

**S6. Task and world discipline.**
- Dispatches on tasks the evaluation spawns are not seen. Poison on task creation or switch while recording.
- `invokelatest` keeps the evaluation's world in a pure callback (`builtins.c:887–888`), so it is safe.
- `invoke_in_world` with another world must poison. Record the world with each entry, and refuse if it differs from the evaluation's world.

**S7. The reference changes are not named.** The note changes these:
- facts §2.1 "Why it holds", last bullet;
- facts §4.1 bullet 4;
- facts §4.2, "no compile-time evaluation over the call";
- facts §8, the rule itself;
- compiler §1.3 and §1.5;
- a new compiler section for the recorder and its builtin.

Per CLAUDE.md the decision goes into the references and the decision log. The validation run also needs an experiments row before it is run.

### Consider

- **C1. Edge volume.** Each fold creates MethodInstances at exact signatures, for example `getproperty(::Type{Dual{…}}, ::Symbol)`, and adds one edge per distinct record plus the copied edges. Deduplicate them. Report the edges per CodeInstance and the image size.
- **C2. Stripped edges.** `--strip-ir` empties CodeInstance edges (`staticdata.c:2606`). B1's copy then has nothing to copy: refuse the fold when edges are stripped.
- **C3. Binding reads at run time** (`getglobal`, `isdefinedglobal`, `builtins.c:1339`). Plain Julia does not track them under an assertion either: they are the asserter's `:consistent` promise. Facts §1 counts bindings as edges, though. Record them, or state that they are excluded.
- **C4. The `is_fact_sig` check on records is nearly vacuous.** A signature built from values (`arg_type_tuple`, with `Type{T}` for types) is a dispatch tuple, except for kinds with free type variables. The real gates are B1–B4.
- **C5. The stakeholder wording in §2.** `Dual{Tag{F,V},V,N}` contains the user's function type. The stakeholders are every owner at any depth, not only "Julia's and `Dual`'s". G2 is unaffected.
- **C6. Compile-time cost.** The first fold per `(S, T)` runs `padding`'s facts code at `DataType`, which is the dispatch-heavy path itself, once per session at compile time. It also compiles that code under the facts owner. Count both.

---

## Answers

### 1. Are the recorded dispatches facts? What escapes?

Each dispatch at a value signature is a fact, with one exception: a kind with free type variables gives a non-fact signature. So the records are not the issue. What escapes the recorder is the issue:

| Case | Seen by a hook in `jl_lookup_generic_`? | Dependency of the value | Escapes? |
|---|---|---|---|
| Calls on `Type{T}` values | yes. Build the record with `arg_type_tuple`, so it is `Type{T}` as the method cache sees it. Type arguments never enter site entries (compiler §3.2); they go through assoc | dispatch at `Type{T}`: a fact | no, if the MethodInstance edge of B3 is used |
| `getfield` on `DataType`, `fieldoffset`'s ccall, `Core.sizeof` | no dispatch | the type's layout, fixed once made; no method table | no (not a method-table dependency) |
| Statically compiled calls in executed code | **no** | edges of each CodeInstance executed | **yes (B1)**; with plain code in P4, almost everything (B2) |
| `invoke` | only if `jl_gf_invoke` is hooked | the declared signature's resolution: an invoke edge | yes as drafted (B4) |
| `invokelatest` | yes (it calls `jl_apply`) | dispatch in the evaluation world (pure callback keeps the world, builtins.c:887) | no; but it runs **default-owner code**, which is plain in P4 (B2) |
| Keyword calls | yes: `Core.kwcall` at a concrete `NamedTuple`, then the sorter (a generated name) | dispatch tuples | no |
| `Core._apply_iterate` | `iterate` and the final call go through `jl_apply_generic` | facts, but the **default owner's** code runs | executed code plain in P4 (B2) |
| `isdefined`, global bindings | static ones: no (they are in the executed CodeInstance's edges); dynamic `getglobal`: no | Binding edges | static: yes (B1); dynamic: asserter's, as in plain (C3) |
| `hasmethod`, `which`, `methods`, `applicable`, `return_type` | no | method table, possibly at abstract signatures | **yes (B4)**; `hasmethod` with the default world raises in a pure callback |
| `jl_invoke` of cached specializations | no lookup | the code of a CodeInstance at the compileable signature | **yes (B1)**; an edge to that CodeInstance would break G2 |
| Split-table fallback, `:caller_world` thunks | no | the target's static call | **yes (B4)** |

**Is G1 still true?** Not as drafted. B2 alone reopens the G1.19 hole in P4, and B3 reopens it in every setting within a session. With B1–B5 fixed, the argument does hold:
- In a later world, execution replays identically up to its first difference.
- That difference is one of four things: a recorded dispatch, a static decision in an executed facts CodeInstance, a binding, or state.
- The first two are edges. The binding is an edge, or the asserter's responsibility, as in plain Julia. State is the asserter's `:consistent`.

### 2. Feasibility in 1.13

- **Recording:**
  - the end of `jl_lookup_generic_` (gf.c:4845), with a record before `jl_method_error` (:4834);
  - `jl_gf_invoke` and `jl_gf_invoke_by_method`, as invoke edges;
  - `_jl_invoke_owner`, for the CodeInstance entered and its owner;
  - poisons in `jl_method_lookup`, `jl_gf_invoke_lookup` outside `invoke`, `jl_matching_methods`, `jl_split_table_ptr`, task creation and switch.

  The dispatch profiler (gf.c:4521ff) is the template: it already sits on all four lookup paths.
- **Cost when off:** one load and one branch. The separate-entry option is infeasible (S5).
- **Pure callback:**
  - `_call_in_world_total` (`builtins.c:913`) sets `in_pure_callback` and clamps the world. Recording belongs in a sibling builtin that also invokes a CodeInstance (B2) and pushes and pops the recorder under `JL_TRY`.
  - Inference re-entered from the evaluation clears `in_pure_callback` and takes the recursive `jl_typeinf_lock` (gf.c:484–496). It must also suspend the recorder (B5).
  - The recorder is per task, so the lock does not contend with it. The evaluation runs while this thread holds `jl_typeinf_lock`, as plain concrete evaluation does.
- **Edges:** 1.13 has these forms (`stmtinfo.jl:49–100`, `typeinfer.jl:732–770`):
  - a single CodeInstance or MethodInstance, with a backedge on the callee MethodInstance;
  - `n, sig, items…`, with backedges only for CodeInstance and MethodInstance items, plus `sig, Core.methodtable` when not fully covering;
  - `invokesig, CI/MI`;
  - `Binding`;
  - `FoldRecord`, with no backedge.

  "Dispatch at `sig` selects `m`" must be a MethodInstance at `sig` (B3). Load-time checking works for it, through `verify_call` with `n = 1` and `fully_covers` (`reinfer.jl:228–233`, 474ff).

### 3. Is there a simpler route?

- **Constant propagation of `padding` with a `Const` type: no.**
  - `padding` loops over the fields with a non-constant index, so `fieldtype(T, i)` merges the field types (`tfuncs.jl:1600–1625`).
  - Its recursion goes through inference's recursion limiting.
  - Constant propagation does not unroll loops.
  - Decisively, `array_subpadding`'s own frame iterates an `svec` and holds `Any` run-time sites (S1). No amount of precision in `padding` clears `nortsite` there.
- **Letting the assertion apply over run-time sites when all arguments are constants: no.** That is W-52's hole, restricted to constants. G1.10, G1.19 and G1.32 all use constant arguments and would fail. Made sound, it becomes W-56.
- **Recommended: make the padding helpers fully typed in Base, with the facts forms that exist** (`base/reinterpretarray.jl:769–834`, about 50 lines):
  1. `padding` returns `Tuple{Vararg{Padding}}`, which is egal-consistent like the `svec`. `CyclePadding`'s field is typed `Tuple{Vararg{Padding}}`. Iteration is then at the concrete-`Vararg` fact form, and every `Padding` operation is at a concrete signature.
  2. Every call on a `DataType`-typed value in the recursion goes through a fact form:
     - `invoke(fieldoffset, Tuple{DataType, Int}, T, i)` and `invoke(padding, Tuple{DataType, Int}, fT::DataType, off)`: `invoke` at a declared signature, facts §3, sixth form. Its edge is broken only when the declared signature's resolution changes, so a `fieldoffset(::Type{MyT}, …)` leaves it alone.
     - builtins instead of `getproperty` on kinds: `Core.sizeof`, `Core.fieldtype`, `getfield(T, :layout)` for the alignment and the field count.
     - no error paths with interpolation, which add run-time sites through `print`.
  3. Check it quickly, in seconds rather than a measurement round. Run `code_typed` and `infer_effects` of `array_subpadding` at `(Type{Dual…}, Type{Float64})` under the facts interpreter, in both settings: the effects keep `nortsite`, and `reinterpret` shows the constant. Then run E-162's step d once.
- **What it costs and changes:**
  - Only Base: a system image rebuild, no C runtime change, no new edge kind or reference rule.
  - G1 and G2 follow from the existing rules.
  - One observable change from upstream: the patched Base no longer consults a user's `fieldoffset` or `getproperty` overload on their own type when it computes padding. Plain code of the patched Julia does the same, so G1 compares like with like. Record it in `design/julia-changes.md`.
  - It fixes `array_subpadding`, `struct_subpadding`, `packedsize` and `ispacked`.
  - It does not generalize. Other asserted helpers that walk field types with kind calls stay unfolded.
- **Recommendation:**
  - Take the Base route for E-162 now.
  - Keep W-56 deferred, with a census first: grep Base and the port's dependencies for `@assume_effects`/`@_foldable_meta` functions that recurse or loop over field types, or iterate an `svec`. Build W-56 only if the census finds such helpers on hot paths.
  - If W-56 is built, B1–B5 are its design, not its details.

### 4. Gaps in the validation plan

- **No check that the fold happens.** A refusing recorder passes G1.10–G1.33 vacuously and only shows up as a timing. Add `code_typed` checks that the call is a constant, plus a count of recorded folds and refusals.
- **G1.10, G1.19, G1.32 and G1.33 change meaning.** They currently check "does not fold". Under W-56 they must check "folds, and follows the redefinition in the session". With the drafted edge form they would fail (B3).
- **The product setting.** The acceptance checks run plain and under `all` (facts §2.1). B2 lives in the product setting: run the new checks there.
- **One negative check per path in Q1's table:**
  - a stakeholder's method at a recorded signature defined after the fold (the note's check), in the product setting;
  - a static call inside executed code, redefined by its owner;
  - a caught `MethodError`, then the method added;
  - `invoke`;
  - `applicable` or `hasmethod`;
  - `_apply_iterate` over a non-tuple;
  - a split-table fallback in evaluated trait code;
  - a fold whose evaluation must JIT, folding the same way on first and later compiles (B5).
- **G2 with kind overloads.** Load a package that defines `Base.fieldoffset(::Type{Other}, ::Int)`, `Base.getproperty(::Type{Other}, ::Symbol)` and `Base.sizeof(::Type{Other})`, and count invalidated folds. This catches any edge at `DataType` or at a compileable MethodInstance.
- **Images.**
  - A fold saved in a package image is discarded when a stakeholder's method is loaded first (`verify_call`).
  - After load, a redefinition in the session invalidates it (backedge).
  - The image contents do not depend on compile order.
- **Cost.**
  - Off: the call benchmarks, quick.
  - On: compile time, edges per CodeInstance, image size.
- **Process.** An experiments row with the question and the result that would change the design, written before the run. E-162 compares with 33–47 ms measured on 2943086604; state the build and setting of both sides.

---

**Addendum (2026-10-27, filing).** Reviewed by an Opus agent, fresh eyes, source only. Acted on: W-56 deferred; the recommended route (Base's padding helpers fully typed) taken as W-57; the census of asserted Base helpers that walk field types queued with it.
