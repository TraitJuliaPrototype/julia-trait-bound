# Plan: dispatch's lookup at an unmet intersection made sound (C-82, open issue 172)

Status: **proposal** (2026-11-09, night), for a Fable review before it is built. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The fault

[Compiler §5.4](../reference/compiler.md#54-the-ambiguity-report-at-a-membership) now says (rewritten 2026-11-09 after [the performance review](../reviews/2026-11-09-performance-day.md), H2):
- at an open set, a match met only at an intersection no type of the world is in **stays** in dispatch's lookup;
- only at a **final pair** (a set closed after load, [§4.8](../reference/compiler.md#48-negatives-never-fold-positives-through-entries)) is such a match left out, with the pair's cell recorded so that a late membership invalidates;
- a `Callable` component's members are the types whose methods match it.

The build (`unified` b05ae361e0) deviates (C-82), in two places:

1. **The runtime's lookup drops at every set.** `drop_unmet_matches` (`src/gf.c:7585`), called in `ml_matches` before the matches are sorted and their ambiguity computed, removes a match whose `spec_types` has an argument `jl_has_unmet_argument` judges unmet, where a fully covering match exists that it is not more specific than. It records nothing.
   - At an open set, a membership declared later that meets the intersection leaves compiled code running the covering method while dispatch is ambiguous: a folded negative, which §4.8 forbids.
   - At a final pair, the drop is sound only if the caller records the pair's cell. `ml_matches` records none, and inference's `drop_unmet_final_matches` (`Compiler/src/abstractinterpretation.jl:871`) never sees a match the runtime already removed. So a late membership at a set closed after load does not invalidate such a caller either. Gate `n20_unmet_lookup` (4) checks only the matches that would *win* (which the runtime keeps and inference drops with the cell), not the incomparable ones the runtime drops.
2. **`jl_has_unmet_argument` reads entries only** (`src/datatype.c:814`, `all_type_met` → `set_entries_meet`). `Callable`'s memberships are methods (compiler §7.4), so `All{AbstractString, Callable}` counts as unmet while `struct MyS <: AbstractString end; (s::MyS)(x) = 1` is in it. The probe `experiments/unification/audit/probe_unmet_callable.jl` (log `audit/logs/probe-unmet-callable-b05ae361e0.log`): the lookup at `(Callable, Int)` returns one match, unambiguous; `f(MyS(), 1)` raises `MethodError`; `g(x::Callable) = f(x, 1)` compiled returns `:callable`. G1 fails with no later membership.

## 2. The fix

**One place drops, and it reports what it relied on.** The runtime's lookup is where ambiguity is computed, so the drop must happen there, before the sort. It must also hand the cells to inference.

### 2.1 Runtime (`src/gf.c`, `src/datatype.c`)

- `all_type_met`: a component that is `Callable` (or any set whose memberships the runtime reads from methods, not entries) makes the intersection **met**. `Callable` is never final: any later method can make a member. No method-table walk inside the question.
- `drop_unmet_matches` becomes `drop_unmet_final_matches_rt`. It drops a match only where `jl_unmet_final_cells(spec_types)` returns an `svec`, i.e. every unmet argument is a final pair. It drops it whatever its specificity, as inference's rule does now (a match that would win is dropped too: E-334). At an open set it drops nothing.
- The dropped matches' cells are collected into an output array.
  - `ml_matches` gains an optional `jl_array_t *cells_out` (NULL for every existing caller).
  - A new exported entry `jl_matching_methods_cells(types, mt, lim, include_ambiguous, world, min_valid, max_valid, ambig, cells_out)` is `jl_matching_methods` with the output; `jl_matching_methods` passes NULL.
  - Callers that pass NULL still get the final drop. They are reflection, `Base._methods_by_ftype` for `methods`/`which`, and dispatch of an abstract signature. None of them is compiled code that must be invalidated.
- `ml_matches`' early exits (the leaf cache, `lim` reached): a final drop happens only for a non-concrete query, since a concrete type is either in a set or not; check that the cache paths cannot skip the drop for an abstract query.

### 2.2 Compiler (`Compiler/src/methodtable.jl`, `abstractinterpretation.jl`, `stmtinfo.jl`)

- `MethodLookupResult` gains `cells::Vector{Any}`: the final cells the lookup relied on (empty almost always). `findall(sig, ::InternalMethodTable)` calls `jl_matching_methods_cells`. `CachedMethodTable` caches the field with the rest. `OverlayMethodTable`'s merge concatenates the two results' cells.
- `drop_unmet_final_matches` is deleted. `find_simple_method_matches` and `find_union_split_method_matches` pass `matches.cells` into `MethodMatchInfo` (its `cells` argument already exists), so `_add_edges_impl` records them as today.
- `findsup` (`invoke`): unaffected. An `invoke` target is a method whose signature is a supertype of the invoke's types, which no unmet match is.

### 2.3 Base

- `base/reflection.jl`'s `has_unmet_intersection` keeps asking `jl_has_unmet_argument`, so `isambiguous` and `detect_ambiguities` report a `Callable` pair once fixed. At an open set reflection keeps §5.4's rule: an argument met only as an unmet intersection has no value in the query's world, and a membership that later meets it is reported at its declaration. Reflection is a report and decides no compiled code.
- `base/sysimg.jl`'s walk for final cells (E-334) is skipped when no set is closed after load. A counter of closed-after-load sets is bumped by `jl_set_closed_after_load`. Base declares none, so the walk never runs in Base's build. This is the review's M4, folded in because it touches the same rule.

## 3. Alternatives considered

- **(b) Drop in inference only, the runtime dropping nothing.** Then the lookup's `ambig` flag stays set for an incomparable match that inference drops, and inlining refuses an ambiguous lookup (`ssair/inlining.jl:1533`). Inference would have to recompute Julia's ambiguity rule over the kept matches, a second copy of `ml_matches`' logic. Rejected.
- **(c) A side channel:** the runtime keeps the last lookup's cells in a task-local slot. `CachedMethodTable`'s hits would skip it, so cells could go missing. Rejected as unsound.
- **(d) A guarded drop at an open set** (open issue 172 (b)): a cell per pair at open sets, the call static under a guard. It needs a new kind of cell. Left Open; built only if a port's session shows a dynamic call that matters (no speed target now: decisions §5, 2026-11-09).
- **(e) Read `Callable`'s members from the methods** inside `all_type_met`: a method-table query inside subtyping's helper (P-30 forbids that inside subtyping). Treating a `Callable` component as met is sound and costs nothing.

## 4. Gates

- `n20_unmet_lookup`:
  - (1) at the final pair `(X20, Char)` still one match and static, with `Base.return_types == [Int]`; add an assertion that the caller's edges hold the final cell of `(AbstractString, X20)`. This is the case the build misses today, the incomparable match the runtime drops.
  - (2) flips: at the open set `X9`, the lookup at `(X9, Char)` returns both `k9` methods, ambiguous, and `kc(x::X9) = k9(x, 'a')` compiles to a dynamic call.
  - (5) new, the probe: the lookup at `(Callable, Int)` returns both methods, ambiguous; `g(MyS())` raises the `MethodError` that `f(MyS(), 1)` raises.
  - (6) new: a caller compiled at `X9` before a membership that meets `All{Q9, X9}` and after it gives the same answer as dispatch.
  - (4) unchanged: a late membership at `X20` invalidates; add the incomparable match's caller to it.
- The battery (`stack/battery.sh`): the gates; Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `Compiler/inline`, `Compiler/inference`, `precompile`; the acceptance cases; TraitWorld's suite; both workloads.
- The forks' digests and the REPL transcript (`check_session.sh`), and TraitDifferentialEquations' suite. They show whether a port relied on the drop: a call that was static becomes dynamic, results equal.
- A count, recorded, not gated: `audit/erased_calls.jl`-style dynamic calls in TraitWorld's and the ports' facts code before and after. That says what the drop bought.

## 5. What changes in the record

- Compiler §5.4: the status names the commit; §4.8's bullet "Inference drops a method match …" becomes "the lookup drops … and reports the cell; inference records it".
- C-82 retired; open issue 172 (a) built, (b) stays Open; the decision row "Dispatch's lookup at an open set keeps …" built.
- `design/julia-changes.md`: a row; the commit amends W-129's stack before its fold.
- The registry: a row E-339 before the run (question: does any session or suite change; the count of calls made dynamic).

## 6. Risks

- **The port relied on a static call at an open set:** a call becomes dynamic. The results stay equal; only the speed changes. The count says where.
- **Reflection and dispatch disagree at an open set:** reflection reports no ambiguity where the lookup now returns an ambiguous pair. That holds today too for intersections with no value. The membership report covers the moment a value exists.
- **An abstract query in codegen that bypasses inference** (`jl_gf_invoke_lookup`, the leaf cache): the cells go missing there. To check in the code before building.
