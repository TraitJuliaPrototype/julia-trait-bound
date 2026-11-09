# Review of the plan for C-82: dispatch's lookup at an unmet intersection (open issue 172)

A Fable review (2026-11-09, night, finished 2026-11-10 after midnight) of [the plan](../plans/2026-11-09-c82-unmet-match-lookup.md), before it is built. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## What I read and ran

- The plan; [compiler §4.8, §5.2, §5.4, §7.4, §8.1](../reference/compiler.md) and the C-79, C-82 rows; [open issue 172](../open-issues.md) and §1's item; decisions §9 rows 403, 406, 425; [the performance review](2026-11-09-performance-day.md) H2, M4; experiments E-331, E-334, E-338, E-339; todo W-128, W-129.
- The code of the worktree `julia-unified` at 8c4b93f867 (dispatch unchanged since b05ae361e0; line numbers below are the worktree's): `src/gf.c` (`ml_matches_i` 7847–8180, `drop_unmet_matches` 7585, its call 7991, the leaf and method caches 7905–7960, the `lim` exits, `jl_matching_methods` 5096, `jl_attributed_mi` 5438, `jl_get_specialization1*` 6244–6270, `_gf_invoke_lookup` 7281–7305, `edge_is_single` 5519); `src/datatype.c` (`set_entries_meet` 789, `all_type_met` 814, `unmet_argument` 829, `jl_has_unmet_argument` 847, `jl_unmet_final_cells` 877, `jl_membership_final` 497, `jl_membership_final_cells` 531, `jl_membership_cell_register` 590, the declaration's guards 1062–1086, the bit's two writers 1289 and 1293); `src/subtype.c` (the sources of membership: entries, joins, `Callable`'s methods, type-value entries, kinds; 545–600, 1292–1297, 1463–1471); `src/builtins.c` 1090–1160; `src/runtime_ccall.cpp` 391–440; `Compiler/src/abstractinterpretation.jl` (85–110, 505–516, 652–720, 818–905); `methodtable.jl`; `stmtinfo.jl` 141–215, 520; `tfuncs.jl` 3264, 3298; `typeinfer.jl` 980–1000, 1690–1710, 1784, 1828; `reinfer.jl` 228–262, 491–530; `facts.jl` 113–126, 276–330; `ssair/inlining.jl` 1520–1545; `base/reflection.jl` 1190–1225; `base/runtime_internals.jl` 1565–1612; `base/sysimg.jl` 1–30; `base/essentials.jl` 5; `stdlib/Test/src/Test.jl` 2335–2370; `test/ambiguous.jl` 179.
- The gate `experiments/unification/gates/n20_unmet_lookup.jl`, the probe `experiments/unification/audit/probe_unmet_callable.jl` and its log; the gate runner.
- Probes on `julia-unified/julia` (niced, one job, load 9–10 of 128), scripts and logs in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/24a7c1e0-a2ec-401b-8a6e-3d7a1561fce2/scratchpad/review-c82/` (`probe_a*.jl`, `probe_b*.jl`, `probe_c.jl`, `probe_v.jl`, with `.log`s; `probe_v` also on `julia-vanilla/julia` 45b6d15e34). What each showed is cited in the findings. They are not committed; the cases worth keeping are named for the gate (M1, M2).

## What the plan gets right (verified)

- **The diagnosis.** At a set `X` closed after load, with `u(::X, ::Char)` against `u(::AbstractString, ::Any)` (incomparable) and `z(::X, ::UInt8)` against `z(::AbstractString, ::UInt8)` (`AbstractString` ranks above `X`, §5.2): the runtime drops `u`'s match and keeps `z`'s; the caller `cu` compiled at `X` has no final cell, `cz` has one; after `S <: AbstractString` joins `X`, `cz` is invalidated and `cu` is not; `u(S(), 'a')` raises the ambiguity and `cu(S(), 'a')` returns 1 (`probe_c.log` C2, C3). G1 fails today at a final pair with a late membership, exactly as §1 says.
- **`invoke` is unaffected.** `_gf_invoke_lookup` is a typemap lookup by subtype (gf.c 7281–7305), not `ml_matches`.
- **A concrete query never asks the question.** The leaf and method caches fire only for `isdispatchtuple` queries (gf.c 7905, 7938); `jl_has_unmet_argument(Tuple{typeof(f), MyS, Int})` is false and the lookup returns the ambiguity (`probe_a.log` A4, `probe_a2.log` A4').
- **The `lim` exits record nothing to record.** Each returns `jl_nothing` (gf.c 7493–7496, 8067–8070, 8081–8084, 8176), and a caller that gets `nothing` relies on no match.
- **The runtime's abstract lookups with NULL cells are safe.** `jl_get_specialization1_worlds` serves the `:caller_world` pointer, whose entry's range is capped at the world counter read before the lookup (`runtime_ccall.cpp` 419–423): a membership makes a new world and the next call looks up again. `attributed_call` queries the values' concrete types (`builtins.c` 1117). `jl_get_compile_hint_specialization` and `compileable_specialization_for_call` (`typeinfer.jl` 1690, called from the compile queues and `facts.jl` 329) choose what to compile; the site still dispatches and records no edge (`facts.jl` 276–279).
- **Images.** `verify_call` re-runs `_methods_by_ftype` in the load world (`reinfer.jl` 232–238, 491), so a drop the build made and the load world does not make fails the method edge; a final cell edge is checked by the cell's `min_world` (`reinfer.jl` 242–250); a cell an image brings joins the set's list (`datatype.c` 590–598) and `jl_membership_update_cells` opens every cell of the pair (603–620). Both routes hold after the change.
- **Base's `ambiguous` test cannot gain pairs from the `Callable` rule.** Core and Base have 26,182 methods and none at `Core.Callable` (`probe_b3.log`; `Base.Callable` is `Union{Function, Type}`, `essentials.jl` 5). The sites that could pair are TraitWorld's `retain!(f::Callable{Tuple{T}, Bool}, …)` (`TraitWorld-unified/src/BaseTraits.jl` 266) and Tables' `byrow` (`forks-unified/Tables/src/ColumnCore.jl` 105, 114); the suites in the battery cover them.

## Findings

### H1. §2.2 misses lookup sites; give the cells one home on `MethodLookupResult` and delete `MethodMatchInfo.cells` — verified

- The plan rewires `find_simple_method_matches` and `find_union_split_method_matches` only. Other sites build a `MethodLookupResult` or a `MethodMatchInfo` and would drop the cells on the floor:
  - `abstractinterpretation.jl` 97–99: the edge to a `Callable{A, S}` member's dispatch at `A` (`findall(Tuple{F, A...})`, then a 4-argument `MethodMatchInfo`). `A` can be abstract (`Tuple{X20}`), so this lookup can drop at a final pair.
  - `abstractinterpretation.jl` 695: `attributed_lookup` rebuilds `MethodLookupResult(new, r.valid_worlds, r.ambig)` for a compiled-once call.
  - `stmtinfo.jl` 520 and `tfuncs.jl` 3298: three-field constructors.
- Any site forgotten is a final drop without its cell: the bug the plan fixes, moved.
- **Change:** `cells` is a field of `MethodLookupResult` with an outer constructor that defaults it; `MethodMatchInfo` loses its own `cells` field and the 5-argument constructor; `_add_edges_impl` (`stmtinfo.jl` 158) reads `info.results.cells`. Then no constructor site can lose them. Grep `MethodLookupResult(` and `MethodMatchInfo(` across `Compiler/src` before and after.

### H2. The `Callable` rule as planned decides only reflection, and contradicts §5.4 and the decision row — verified

- Under the plan's rule nothing is dropped at an open set and `Callable` is never closed after load, so `(S, Callable)` is never a final pair and `all_type_met`'s answer at a `Callable` component decides no lookup. The probe's G1 failure is closed by the open-set rule alone: the match is kept, the lookup is ambiguous, `g` dispatches, `g(MyS())` raises what `f(MyS(), 1)` raises. §2.1's first bullet is not part of the lookup's soundness; the plan presents it as if it were.
- What the `Callable` branch does decide is reflection: `Base.isambiguous` (`reflection.jl` 1206, 1217) and so `detect_ambiguities` (`Test.jl` 2354–2361, which also reads the runtime's `ambig` flag; both change together). `isambiguous` on the probe's pair is false today and true with the filter off (`probe_b2.log`).
- [Compiler §5.4](../reference/compiler.md#54-the-ambiguity-report-at-a-membership) says "A `Callable` component's members are the types whose methods match it (§7.4), read from the methods, not the entries", and decision row 403 says the same. The plan's rule is "counts as met". They differ exactly where no type under `S` has a call method: the reference reports the pair only once a member exists; the plan reports it always. The plan's §5 does not amend the reference, so the build would contradict it.
- **Change:** keep the plan's rule (cheap; it errs toward reporting, which is the safe side for a report) and amend in the same commit: §5.4's bullet ("a `Callable` component counts as met: a method can be defined at any time"), decision row 403, open issue 172's text and §1's item (`open-issues.md` 95). State in §2.1 that the rule serves reflection and the cells' state, not the lookup. Put the check in `set_entries_meet` (`datatype.c` 789) by `sname`, not only in `all_type_met`'s loop (814): an entry `Callable in Y` is not forbidden (`jl_declare_membership`'s guards, 1062–1086) and `set_entries_meet` recurses into a joining set's entries (800–803).

### M1. An unbounded `Vararg` tail at an unmet intersection is judged unmet, but the empty tail is a value — verified

- `unmet_argument` (`datatype.c` 829–842) unwraps a `Vararg` and judges its element. `Tuple{typeof(w), Int, Vararg{All{AbstractString, X}}}` has a value: `w(1)`.
- The case (`probe_c.log` C1, `X` closed after load; `probe_a3.log` A2'' at `Callable`): `w(::Int, ::X...)` against `w(::Integer, ::AbstractString...)` is ambiguous at `w(1)` (`MethodError`). The lookup at `(Int, Vararg{X})` returns one match, unambiguous; `gw2(n::Int, xs::X...) = (w(n, xs...); nothing)` at that signature infers `nothrow` and the call is deleted (`return nothing`). `Base.return_types`, `infer_effects` and any instance compiled at the abstract tail are wrong. No such instance ran in the probes (`gw2(1)` and a `@nospecialize` tail both compile at the concrete zero-length signature, `probe_a4.log`), so the reach is reflection and the abstract-signature lookups (`precompile`, `:caller_world`).
- `jl_unmet_final_cells` (877–895) does not unwrap the vararg, so under the plan's rule the match is kept, by accident, and reflection (`jl_has_unmet_argument`) and the lookup disagree.
- **Change:** a `Vararg{T}` whose length is not a fixed positive integer is never unmet, in `unmet_argument` (so `jl_has_unmet_argument`, reflection and `jl_unmet_final_cells` agree); a gate case with the pair above: the lookup ambiguous, `gw2` not `nothrow`.

### M2. Gate (2) expects the wrong shape; the kept match costs more than a dynamic call — verified

- Inference's `findall` passes `include_ambiguous = false` (`methodtable.jl`, `_findall`). For an incomparable, not fully covering match, `ml_matches` filters it as fully ambiguous and returns the covering match alone with `ambig = true` (`probe_a2.log` A1': `h(::AbstractArray{Int}, ::Char)` against `h(::AbstractVector, ::Any)` at `(AbstractVector, Char)`; `methods_including_ambiguous` sees two). The plan's "(2) … returns both `k9` methods, ambiguous" would fail as written.
- The caller then: the return type from the covering method alone (`Int`), `nothrow` lost (`abstractinterpretation.jl` 510–514), the call dynamic (`inlining.jl` 1533).
- **Change:** gate (2) asserts `r.ambig && length(r.matches) == 1`, `methods_including_ambiguous` of two, `Base.return_types(kc) == [Int]`, `infer_effects(kc)` not `nothrow`, a `:call` of `k9`. §6 states the cost at an open set: the call dynamic and `nothrow` lost at every such site, the return type kept. The count of §4's last bullet goes into open issue 172 as the measure for (b), not only the registry.

### M3. The lone unmet match at a final pair: the plan does not say, and the runtime and inference differ today — verified

- `ml_matches_i` drops only when `len > 1` (gf.c 7990–7991). Inference's `drop_unmet_final_matches` (`abstractinterpretation.jl` 871–886) drops at any length: the `g9`-shape at a final pair gives no match, the call infers `Union{}` with the cell, and no instance is compiled at `All{S, X}` (§4.8; gate (4)'s last assertions).
- If the runtime keeps the `len > 1` guard, the lone match survives as a one-match, not-fully-covering result and the caller gets an `isa(x, All{S, X})` branch at a final pair, against §4.8.
- **Change:** drop at any `len ≥ 1` where `jl_unmet_final_cells` is an svec; a gate case (the `g9` shape at `X20`: zero matches, the cell on the caller).

### M4. The record: a taken experiment ID, and copies of the old rule — verified

- E-339 is the display erasing (`experiments.md` 435). Two reviews tonight already ask for E-340 ([C-57/C-81](2026-11-09-plan-review-c57-c81.md), [171](2026-11-09-plan-review-171.md)). Take the next free ID at registration, in order.
- Copies to fix in the same commit: C-79's row names `drop_unmet_final_matches` as its code (`compiler.md` 942); gate n20's header (lines 1–9) states E-331's rule; `src/gf.c` 7579–7584 (the comment); `base/reflection.jl` 1193–1196 ("Dispatch's lookup asks the same question": after the change it asks a narrower one); `base/sysimg.jl` 10–11 names `IO` as a set, which §7.5 says it is not.

### M5. The sysimg walk's counter has two writers — reasoning

- The bit is set by `jl_set_closed_after_load` (`datatype.c` 1293) and by the datatype path (1289, `closed != 0`). A counter bumped by the first alone misses the second. A global flag set by both is enough: the walk runs only in Base's build.

### L1. Alternative (e)'s reason is misattributed — reasoning

- `all_type_met` is not inside subtyping: its callers are `ml_matches` (through `jl_has_unmet_argument`), the cells' `intersection_met` and reflection. P-30 does not forbid a method-table read there. The reason to reject (e) is the unbounded walk (every loaded subtype of `S`, each against its methods). Write that in `alternatives.md`.

### L2. One allocation per lookup — reasoning

- `_findall` runs for every call inference sees. A `Vector{Any}` of cells per lookup is noise worth avoiding: return `jl_nothing` or an `svec` through a `jl_value_t **`, allocated only when a match is dropped; the field on `MethodLookupResult` nullable or a shared empty vector.

## The questions

1. **Sound and complete?** Yes with H1 and M1: the runtime is the only dropper, every drop is final with its cell, and the cell reaches the caller through the lookup's result at every site; images and the runtime's abstract lookups are covered as listed above. `Callable` as met covers every non-entry membership that matters: the sources are entries, joins (recursed), type-value entries (in the same lists, `subtype.c` 553–567) and `Callable`'s methods; kinds and type values never form a final pair (`abstract_member`, `datatype.c` 325–330).
2. **The runtime, before the sort, is the right place.** Ambiguity and `fully_covers` are computed there, and with `include_ambiguous = false` the incomparable match never reaches inference at all (M2), so inference cannot drop what it does not see. A world-dependent `jl_type_intersection` is ruled out by §4.9 (one type object per expression) and `Method.interferences` computed at insertion. The out-parameter is right; H1 and L2 simplify the plumbing.
3. **Dropping a would-win match at a final pair is sound in the runtime.** Only `NOT_FULLY_COVERS` matches can be unmet (a fully covering match's `spec_types` is the query; if the query itself is unmet, dropping everything with the cell is sound too, as inference does today). A match with no value in the world removes only ambiguities over no values; the cell is the one world change that makes a value; `verify_call` re-runs the same lookup at load. `jl_unmet_final_cells` must stay the single judge (M1, M3).
4. **Gates:** M2's shape; the missing cases: the vararg tail (M1); the lone match at a final pair (M3); a union-split argument (`Union{X20, Int}`) carrying the cell through `find_union_split_method_matches`; a repeated site (the `CachedMethodTable` hit) in (1); the `Callable{Tuple{X20}, Any}` member-dispatch edge (H1's site) holding the cell; reflection on the `Callable` pair (`isambiguous` true, `detect_ambiguities` of the module reports it) for (5).
5. **Contradictions and the record:** H2, M4.

## Verdict

**Build, with H1, H2, M1, M2 and M3 folded into the plan; M4, M5, L1 and L2 in the same commit where they touch the same lines.** The mechanism is right and the diagnosis is verified; what is missing is the plumbing's completeness (H1), the reference's agreement (H2), the vararg rule (M1) and the gates' precision (M2, M3).
