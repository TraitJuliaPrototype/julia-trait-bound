# W-57: Base's type-introspection layer on builtins and `invoke` (the architect's memo)

Status: **adopted** (2026-10-27, mine, option A; on the user's request for "a Fable architect agent who looks for a creative principled structural solution"). Written by a Fable 5.1 agent from source, nothing run; filed unchanged below. Not normative.


Read: `reference/README.md`, `facts.md` (all), `compiler.md` §1, §2.5–2.8, §4, `design.md`, `design/alternatives.md`, `record/decisions.md` §4–§5, the two fresh-eye reviews of 2026-10-26, the W-56 note and its review, the W-40 note, open issues 27, 30, 52, 64, 66, E-162's row, the W-52/W-56/W-57 rows. Source: `julia-1.13` at b13a4fb810 (`Compiler/src/facts.jl`, `effects.jl`, `typeinfer.jl`, `abstractinterpretation.jl`; `base/reinterpretarray.jl`, `runtime_internals.jl`, `essentials.jl`, `promotion.jl`, `Base_compiler.jl`, `expr.jl`), `ndport/logs/p4-regress-rodas.log`. Nothing run.

## 1. Diagnosis

There is a structural cause, and it is not kinds-as-non-facts (correct by Lemma O: any type's owner may add `f(::Type{MyT}, …)`) nor W-52 (correct: a fold must rest on edges). It is that **Base's whole type-introspection layer is written as generic calls on kind-typed values**: `t.flags` is `getproperty(::DataType, ::Symbol)`, `sizeof(T)` is `Base.sizeof(::Any)`, and `fieldcount`, `unwrap_unionall`, `isabstracttype`, `datatype_alignment`, `fieldoffset` are generic functions called at `DataType` or `Any`. In any frame where the type value is not a constant (a loop over fields, a recursion over field types, an `svec` iteration, a `@nospecializeinfer` body) every one of these calls is a run-time site under the facts rule; W-52 then withdraws the layer's `:foldable`/`:total` assertions, so nothing above it folds and the layer itself runs at dynamic-dispatch speed (E-162's profile: 861,000 dynamic `getproperty(::Type, ::Symbol)`, 310,000 `sizeof`, 224,000 `unwrap_unionall`, 189,000 `fieldcount` per solve). The layer's assertions are *true* for a reason the code does not state: its results depend on the runtime's type data (layout, name, parameters), not on the method table; the generic calls are a spurious method-table dependency that plain Julia tolerates because abstract edges and the invalidation safety net repair it (which is problem 1 of `design.md`). This class of code is the substrate trait code must call (`reinterpret`, `promote_type`, `typejoin`, `fieldnames`); no trait rewrite recovers it, so the slowdown principle does not cover it, and the design must address it. The right shape is W-57's (builtins and the runtime for type data, `invoke` at Julia's own method where a Julia helper is meant: both already fact forms) **applied to the layer, not to one helper**: the committed W-57 stops one level too high (§2.3), and F-16 is very likely the same mechanism (§2.4). A compiler-side mechanism that folds over such sites with exact dependencies exists only as W-56, which the review priced correctly; it remains the route for *real* method-table dependencies, and the census decides whether any sits on a hot path.

## 2. Evidence

### 2.1 What the facts rule says at a kind (unchanged, correct)

- `is_fact_sig` (`facts.jl:216`) accepts dispatch tuples; `isdispatchtuple` excludes kinds (`isconcretedispatch(t) = isconcretetype(t) && !iskindtype(t)`), since a value of type `DataType` dispatches as `Type{T}`. So `Tuple{typeof(getproperty), DataType, Symbol}` is never a fact. Right: the owner of `MyT` may define `getproperty(::Type{MyT}, ::Symbol)` (packages do, for `MyT.constant` style access) and changes dispatch at `DataType` without being a stakeholder of it.
- A call at a constant type (`Type{Dual{…}}`) is a dispatch tuple and a fact. So `padding(Dual{…})`'s own frame is fine; the run-time sites arise where the type stops being a constant: `fieldtype(T, i)` under a loop index, `fT` passed to the recursion, `svec` elements typed `Any` (the W-56 review's S1).

### 2.2 What is actually dynamic in E-162 (`ndport/logs/p4-regress-rodas.log`)

| Callee | Dynamic calls per solve | Where from | Source of the site |
|---|---|---|---|
| `getproperty(::Type, ::Symbol)` (`Base_compiler.jl:51`) | 861,000 | `isabstracttype:1115`, `datatype_fieldcount:1281,1293,1299` | `t.name`, `t.flags`, `t.parameters`, `t.types` on a non-constant `DataType` |
| `getproperty(::Any, ::Symbol)` (`:57`) | 344,400 | `array_subpadding` over `svec` elements | `Any` spread from the `svec` |
| `sizeof(::Any)` (`essentials.jl:838`) | 310,000 | `padding` | the generic wrapper of `Core.sizeof`, called at `DataType` |
| `unwrap_unionall` (`essentials.jl:542`) | 224,000 | `isabstracttype:1113` | called at `Any`/`DataType` |
| `fieldcount`, `datatype_fieldcount`, `isabstracttype`, `fieldoffset`, `datatype_alignment`, `padding`, `CyclePadding` | 34,000–189,000 each | the helpers themselves | called at `DataType` |

`Any` spreads: `t.name` is a run-time site, so `t.name.names` and `length(…)` after it dispatch too (`length(::SimpleVector)` would be a fact on its own). One `getfield` at the root un-spreads the rest.

### 2.3 W-57 as committed (b13a4fb810) most likely still does not fold

- `padding!` now calls `invoke(fieldcount, Tuple{Any}, T)` and `CyclePadding` calls `invoke(datatype_alignment, Tuple{DataType}, T)`. The invoke edges are facts. But the invoked bodies are inferred at `DataType` and read type fields generically:
  - `fieldcount` (`runtime_internals.jl:1308`): `datatype_fieldcount(t)` reads `t.name`, `t.parameters`, `t.types`, calls `isabstracttype(t)`, which calls `unwrap_unionall(t)` and reads `t.name.flags`: five run-time sites per call.
  - `datatype_alignment` (`:592`): `dt.layout` is `getproperty(::DataType, ::Symbol)`: a run-time site.
- Effects flow through an invoke edge like any call (`abstract_invoke` merges the callee's effects), so `nortsite` is cleared in `padding!`, `padding` loses `:foldable`, `array_subpadding` loses `:total`, and `reinterpret` computes padding at every call, as before: fewer dynamic calls, no fold.
- Check in a minute, no build: `include` the rewritten helpers in a scratch module, then `Base.infer_effects(array_subpadding, (Type{Dual{…}}, Type{Float64}); interp = Compiler.NativeInterpreter(; facts = true))`. Required: `nortsite` set and `is_foldable`. Expected today: `nortsite` clear.

### 2.4 F-16 is the same mechanism, probably

- `typejoin` (`promotion.jl:22–26`) carries `@_foldable_meta` and `@_nospecializeinfer_meta`. With `@nospecializeinfer`, inference runs its body at `Any` even for constant arguments, so constant propagation does not fold it; plain Julia folds it by concrete evaluation on the assertion. Its body reads `a.name`, `a.parameters`, `a.super` on kinds: run-time sites under facts, so the assertion is withdrawn and `promote_type(Int, StaticInt{2})`'s `typejoin` fallback gives `Any`. With the default owner under `all` a plain CodeInstance can be reused (C-2) and folds: `Type{Number}`. That matches F-16's two answers. Check: `infer_effects(typejoin, (Any, Any); interp = facts)`: `nortsite` clear today.
- The same holds for every `@_foldable_meta` helper that reads type fields on a non-constant: `typesplit`, `tailjoin`, `typejoin_union_tuple`, `unwrap_unionall`, `rewrap_unionall`, `isvatuple`, `fieldcount`, `isabstracttype`, `isconcretetype`, `isbitstype`, `datatype_*`, `fieldname`, `fieldtypes`, `promote_typejoin*`.

### 2.5 Julia's own contract for assertions

`base/expr.jl:609`: "These assertions are made for all world ages. It is thus advisable to limit the use of generic functions that may later be extended to invalidate the assumption (which would cause undefined behavior)"; `:consistent` is defined over the method's whole world range (`:644–:656`). So in plain Julia a `:foldable` helper that consults an extensible generic function at a kind is already the asserter's undefined behaviour; Base's introspection assertions are sound only because their true dependency is the runtime's type data. Option A makes the code say that; option D (§3) would trust the promise instead.

## 3. Options

Each: the idea; soundness against G1 and G2 (with the counterexample where one exists); cost; reference changes; validation in minutes.

### A. The introspection layer on builtins and `invoke` (W-57's shape, applied to the layer, with a tool) — recommended

- **Idea.** In Base's type-level helpers, every read of a type's field is `getfield(t, :f)`; every size, field type, field count, offset and alignment is a builtin or a runtime call (`Core.sizeof`, `Core.fieldtype`, `jl_get_field_offset`, `jl_field_index`, the layout pointer); a Julia helper called on a non-constant type is reached through `invoke` at its own signature (`Base.@invoke`), which is the sixth fact form. Results and error paths unchanged. The `svec` elements of `padding` asserted as W-57 does, or returned as a typed tuple.
- **Scope.** The roots, not every read: a rough count of type-field reads in `runtime_internals.jl` (70), `essentials.jl` (22), `promotion.jl` (27), `tuple.jl` (8), `boot.jl` (7), `reinterpretarray.jl` (3), `namedtuple.jl` (2); perhaps 100–150 edits in seven files, mechanical, reviewed once. The tool decides which matter (below).
- **G1.** Holds trivially: both modes of the patched Julia run the same source. Deviation from stock Julia: Base's introspection no longer consults a user's `getproperty`, `sizeof`, `fieldcount` or `fieldoffset` overload on the user's *type* when it computes layout facts. In stock Julia such an overload makes `isabstracttype(MyT)` or `reinterpret` wrong; this is a robustness fix, upstream-worthy on its own. No counterexample: the helpers compute from the runtime's data in both builds.
- **G2.** Strengthened: the helpers hold no method-table edge at all; the `invoke` edges break only when Julia replaces the method.
- **Cost.** The sweep; a system image rebuild per batch (alone, under the memory guard, after E-163/E-164); a review of the semantic deviation. No compiler change, no new edge kind, no guarantee reworded. Also a broad gain beyond folding: `typejoin`, `promote_type`, `fieldnames` at non-constant types in facts code (the `Vector{Any}` tails call `typejoin` per element) run their bodies as fully typed code instead of one dynamic dispatch per field read.
- **What it does not cover.** A helper whose dependency on the method table is real: `promote_rule(T, S)` at non-constant `T, S`, `eltype`, `convert`, `show`. There the run-time site is the truth and the facts mode is right not to fold. If such a helper is hot, only W-56 (C) folds it soundly.
- **The tool.** Not a reading census. Two existing instruments: `TraitWorld.fully_typed(f, argtypes)` (`certificate.jl:33`) walks facts-inferred code and lists run-time sites on normal paths; the dispatch profiler (`JULIA_FACTS_DISPATCH_PROFILE=1`, compiler §6.5) lists the dynamic callees of a workload, as it did for E-162. Plus one small addition worth having: a log in `adjust_effects`/`merge_override_effects!` (`typeinfer.jl:493`, `abstractinterpretation.jl:3654`), on an environment variable, printing once per method which assertion was withdrawn and the first run-time site below it. Run the demonstrators' quick rows under it: the list is the work list, in order of hits.
- **References.**
  - `facts.md` §8: a second paragraph, "Type-level code that is to fold": a call on a type value is a fact only at a constant type, through `invoke` at the method's own signature, or as a builtin or runtime call; Base's introspection helpers are written so (the list in `julia-changes.md`). §3's "not fact signatures" bullet on kinds already says why.
  - `compiler.md` §1.5: status names the deviation row; §6.5 gains the withdrawn-assertion log (a tool, off by default).
  - A new facts deviation row (next free F-number; F-16 stays its own row until re-checked): "Base's introspection helpers read type fields and call each other at kinds, so asserted helpers over them do not fold in code compiled by facts: `reinterpret`'s padding (E-162), `typejoin` (F-16 candidate); the sweep's progress in `julia-changes.md`".
  - `design/julia-changes.md`: the sweep as a piece, with the deviation from stock and the upstream intent.
  - `todo.md` W-57 rewritten: "the layer, with the tool; the padding helpers first, through `fieldcount`, `datatype_fieldcount`, `isabstracttype`, `unwrap_unionall`, `datatype_alignment`, `sizeof`"; W-56's trigger stated (below).
  - `open-issues.md` 66: the diagnosis of §2.3 and the route.
- **Validation (minutes).**
  1. No build: scratch module with the rewritten padding chain; `infer_effects` under `NativeInterpreter(; facts = true)` in both settings: `nortsite` set, `is_foldable`; `code_typed` of a `reinterpret` caller shows the constant.
  2. After the build: acceptance G1.10, G1.19, G1.32, G1.33 unchanged (they assert over sites that stay run-time sites); E-162's step d once in P4: near 33–47 ms; the dispatch profiler on the Rodas5P solve: the `getproperty(::Type, …)` row gone.
  3. G2: a scratch package defining `Base.getproperty(::Type{Other}, ::Symbol)`, `Base.sizeof(::Type{Other})`, `Base.fieldoffset(::Type{Other}, ::Int)` loaded after trait code ran `reinterpret`: 0 facts CodeInstances invalidated (`g2all`'s count).
  4. F-16's script (`ndport/scripts/p3_promote3.jl`) after `typejoin` is swept: one answer under both owners.

### B. An introspection form of fact signature (the closure form's structure for Julia's own type functions)

- **Idea.** Calls at kinds to a flagged set of Julia's functions (`getproperty(::Type, …)`, `sizeof`, `fieldcount`, `unwrap_unionall`, …) are inferred as plain Julia infers them, abstract edge included, under the assumption that no package adds methods for its own type to them; exactly what facts §3 does for a closure's call at kinds.
- **G1.** Holds: the edge is recorded and Julia invalidates on `getproperty(::Type{MyT}, ::Symbol)`.
- **G2.** A new named exception, like the closure one: a method on a kind for a flagged Julia function, by the type's owner, invalidates facts code compiled at the kind. Not a pirate (the definer is a stakeholder of its own method), so strict mode cannot refuse it, only warn. Counterexample to G2 as stated: any package with `Base.getproperty(::Type{<:MyT}, ::Symbol)` invalidates every introspection helper trait code compiled at `DataType`, and everything above it. This is the invalidation storm the design removes; evidence §1 lists "a new type at a kind" among the four motivating cases.
- **Cost.** A flag per method and a branch in `facts_find_method_matches`; the exposure measured by the control loads. Small to build.
- **Why not first.** It is a declared sealed set by another name (the user, s28: the notion should leave the project), it keeps the fragility for the flagged functions, and A removes the dependency instead of assuming it away. Keep as the fallback if A's sweep proves unbounded (it does not look so).
- **References.** facts §3 (a seventh form, with its assumption), §2.2 (the exception), compiler §1.2, a decision row.

### C. W-56 made sound: concrete evaluation with recorded dispatches and entered CodeInstances

- **Idea.** The review's B1–B5: evaluate the callee's *facts* CodeInstance (`invoke` with a CodeInstance), record each dynamic dispatch at the end of `jl_lookup_generic_` and each CodeInstance entered, copy the entered facts CodeInstances' edges, emit MethodInstance edges at the recorded concrete signatures, poison on bypassing lookups, suspend the recorder in nested inference, refuse the fold if plain code is entered. Then a fold rests on exactly the facts it used.
- **G1 and G2.** Sound with all five; the review's table is the proof obligation. Note: the review's B1 reason for copying edges rather than naming the entered CodeInstance ("an edge to it is broken by any owner's `fieldoffset(::Type{MyT}, …)`") does not hold under the facts mode, where that CodeInstance has no edge at `DataType`; an edge to the entered facts CodeInstance is G2-safe. The copy is still needed under `all` (C-2, owner `nothing`).
- **Cost.** A runtime hook on every dynamic dispatch (one load and branch when off), a recorder with task and world discipline, a new builtin, compile-time execution of the `DataType`-level code once per fold site, edge volume, image checks. The largest change proposed on the compiler since (D).
- **What only it gives.** Folds of asserted helpers with *real* method-table dependencies at non-constant types (`promote_type(T, S)` in a loop over element types), and packages' own asserted helpers without patching them.
- **Trigger.** Build it when the tool of A finds such a helper on a hot path of a demonstrator or the port, and A cannot reach it. Not before.
- **References.** As the review's S7 lists (facts §2.1, §4.1, §4.2, §8; compiler §1.3, §1.5, a new section for the recorder).

### D. An assertion as the asserter's promise, as Julia defines it (undo W-52's reach, or more)

- **Idea.** Under Julia's contract (§2.5) a `:consistent` assertion holds for all world ages; a fold over a run-time site is then the asserter's responsibility, and G1 is restated "up to the asserter's promise".
- **G1 counterexample.** G1.10, G1.19, G1.32: redefine `g` below an asserted `h2`; plain code follows it through its abstract edge, facts code keeps the fold. Formally the asserter's undefined behaviour; practically Base's assertions lean on the safety net, and the fold goes stale silently where plain Julia recompiles.
- **Why not.** The design's stance, confirmed by the user twice (s29, 2026-10-26), is that validity is checked, not promised; "G1 depends on no declaration". A narrower variant (trust Julia's assertions over run-time sites whose callees are Julia's own) is B by another route.

### E. Base's type helpers plain whoever calls them (a module or method flag, as the Compiler has)

- **G1.** Holds: plain code's behaviour. **G2.** A new exception like §6.4's: facts code holds edges into plain introspection code with abstract edges; a user's `getproperty(::Type{MyT}, …)` invalidates trait code through it. Under `all` the helpers leave the test bed.
- **Cost.** Cheap; but it restores the storm for the substrate every trait module touches, and the s26 pointer-calls design was replaced by (C) for this reason. Fallback only.

### F. `fold_call` generalized to asserted helpers

- A `FoldRecord` with no backedge, re-evaluated at image load. In-session G1 hole: a stakeholder's `fieldoffset(::Type{Dual…}, ::Int)` after the fold is not followed. Sound for W-40 only because TraitWorld refuses the later definitions that would matter (overrides); Base has no such invariant. No.

### G. Rewrite loops over fields as recursions over the constant tuple `fieldtypes(T)`

- Keeps every call at a constant type without `invoke`. Fragile: inference's recursion limiting widens `Type{…}` arguments of a self-recursive method, and a `svec`/`ntupleany` boundary reintroduces `Any`. Not chosen; A's `invoke` form does not depend on constant propagation.

### H. Kinds inferred plainly for every function (`kinds_ok` for all, not only closures)

- G1 holds (edges recorded); G2 loses "a new type at a kind" wholesale (`convert(::Type{T}, x)` for `T<:MyAbstract`, `promote_rule`, `show(::IO, ::Type{MyT})` all invalidate facts code at kinds). The storm back for one of the four motivating cases. No.

## 4. Ranking and recommendation

1. **A**, now: the right shape, no change to a guarantee, and the only option that removes the dependency rather than assuming or recording it. Order of work:
   1. The minute check of §2.3 on the committed W-57 (no build). If `nortsite` is clear, extend the padding chain down to `fieldcount`, `datatype_fieldcount`, `isabstracttype`, `unwrap_unionall`, `datatype_alignment`, `Base.sizeof` → `Core.sizeof`, `fieldoffset`'s ccall; re-check; commit as W-57 part 1.
   2. The withdrawn-assertion log (two lines in the compiler, off by default) and a run of the quick suites and the demonstrators' quick rows under it and under `fully_typed`: the ordered list.
   3. The sweep by that list, file by file; `typejoin`'s family early (F-16). One build per batch; the four checks of A each time.
   4. The references and the deviation row with step 1; `julia-changes.md` with each batch; the upstream note (robustness fix) when the sweep is done.
2. **C** (W-56 sound) stays deferred, with its trigger written in the todo row: a hot asserted helper with a real method-table dependency that A cannot reach. The review's B1–B5 are its design.
3. **B** as the recorded fallback if the sweep is unbounded, with its G2 exception named and measured.
4. D, E, F, G, H: recorded in `alternatives.md` under "Asserted effects" with the reasons above.

## 5. What this makes of the open work

- **W-52:** stays as built; it is the rule that exposed the layer's spurious dependency. Its acceptance checks stay as they are.
- **W-57:** becomes "the layer, with the tool", not one helper; part 1 is the padding chain to the bottom; the committed patch is a half step.
- **W-56:** deferred with a trigger, not a date.
- **F-16:** diagnosed by the `typejoin` check of §2.4; closed by the sweep or by C-2's fix, whichever the check names.
- **Open issue 64** (a family member's witness depends on any owner's methods at abstract declared arguments) is the same principle one level up: a type-level computation is folded only with a stakeholder-only dependency; the recommendation there (count only the stakeholders' methods) is A's stance for TraitWorld's own check.
- **`return_type`'s exception (F-20, item 30)** is untouched: it is the one type-level computation the design already delegates with a checked dependency (`rests_on_facts`); A adds nothing to it.
- **W-40's `fold_call`:** untouched; the memo notes it is sound only under the library's closed-world invariant, which should be said in compiler §4.4's rules if it is not (it is, as "one answer per session" plus the refusal of overrides in lowering §4.8).

## 6. Open questions for the user

Only two have no principled answer here:

1. **The trigger for W-56.** If the tool finds a hot asserted helper with a real method-table dependency at non-constant types (likely candidates: `promote_type` chains over element types in collection code), is the recorder worth its cost, or is the run-time cost there accepted as the facts rule's price? A has no answer; it is a cost decision.
2. **Upstream.** Whether the Base sweep is proposed upstream as a robustness fix (Base's introspection independent of user overloads on types) once it is done, or kept as a patch of this build. It changes stock behaviour in a corner; the proposal needs the user's name on it.
