# Review: the plan for T-98, strict mode refusing a membership that makes methods ambiguous

The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

Written by a Fable agent at the user's request, the exception to the rule against subagents on the shared host. Hostile but fair. *Verified* means read in the code at the cited lines or seen in a run of my own; *inferred* means reasoning from them. The plan reviewed: [`plans/2026-11-10-t98-strict-membership-ambiguity.md`](../plans/2026-11-10-t98-strict-membership-ambiguity.md). All line numbers are `julia-unified` at `unified` 999777ab77, the build of the binary in place.

**What was read:**
- `src/datatype.c`: `publish_entry` (174–202), `register_candidate` (217–238), `index_entry` (245–259), `jl_register_candidate` (318–325), `jl_membership_update_cells` (641–674), `activation_conflicts`, `jl_activate_memberships`, `jl_memberships_activated` (689–772), `entry_live_at` and `set_entries_meet` (804–845), `jl_unmet_final_cells` (923–935), the readers at 989–1000 and 1045–1065, `jl_declare_membership` (1103–1218);
- `src/gf.c`: the `ml_matches` wrappers (1263–1295), `lookup_leafcache` (1931–1947), `jl_methods_at_set` (2812–2826), `is_replacing` (3285–3307), `method_morespecific_via_interferences` (4017–4029), `invalidate_intersecting` (4079–4213), `membership_superset_sets` (4485–4500), `jl_membership_dispatch_walk` (4836–5009), `jl_method_table_insert` (5011–5024), `jl_matching_methods` (5107–5121), `chain_has_memberships` (6990–6998), `drop_unmet_matches` (7622–7667), `ml_matches_i` (7903–8235), the ambiguity report (8237–8507);
- `src/subtype.c`: the task's query world (1190–1226), `list_may_reach` (1277–1313), the reach memo and `typename_reaches_r` (1513–1655), `jl_membership_holds_at` (1659–1665), `jl_type_has_memberships` (1860–1877), `jl_membership_changed` and `jl_membership_world_range` (1879–1917);
- `src/staticdata.c` 3517–3530 (the image's memberships) and 4533–4553 (activation); `src/julia.h` 596–610 (`jl_membership_t`);
- TraitWorld: `src/strict.jl`, `src/implement.jl` 120–143, `src/runtime.jl` 9–13, `src/trait.jl` 58 and 111, `src/callable.jl` 19, `test/strict.jl`;
- traits §6.3, §11.3, §12.3, T-98; facts §11.2, §11.3; compiler §4.2, §4.3, §5.4, §5.5, §10.2, C-18, C-35, C-82; lowering §13; the gates `m2_ambiguity_report`, `m2_ambiguity_arity`, `m3_ambiguity_dominance`; the experiments' `Traits` stub (`experiments/unification/src/Traits.jl`).

**Not read:** every reader of `jl_typename_memberships` in `subtype.c` line by line (1454–1501, 1993, 2050, 5012, 5050 only through a grep of their world filters); `membership_range_visit`; `invalidate_mt_cache`; `jl_membership_log`; `get_intersect_matches`.

**What was run** (`source env.sh`, niced, one job at a time, load 6–9 of 128; scripts and outputs in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/24a7c1e0-a2ec-401b-8a6e-3d7a1561fce2/scratchpad/review-t98/`), on `julia-unified/julia` with `--project=experiments/unification`:
- `probe_control.jl`, `MODE=nocall` (the gate's shape) and `MODE=call` (the member called once, through a compiled function, before its second membership);
- `probe_stale.jl`: what a method match answers after the second membership, and what `Base.isambiguous` says;
- `probe_guard.jl`: a method match asked at the counter and at the counter + 1, inside one function;
- `probe_cache_and_guard.jl`: a first attempt; its guard reading was invalid (fresh global bindings advance the world counter by one each, so the "future" world was current by the time it was asked), superseded by `probe_guard.jl`.

No file but this one was written. No build.

## Summary

The plan's structure is right: check under the lock, between publishing the entry and advancing the counter, so that a refused membership is never visible. Three things in the mechanism are wrong, two of them fatal to it as written:

- **The search answers nothing at `min_world` before the counter advances.** `ml_matches_i` refuses a world above the counter at its first line; `ambiguous_at` goes through it. Verified by reading and by a run.
- **The search reads the dispatch caches, and they hide the ambiguity whenever the member was called before.** Verified by a run: today, with the member called once before its second membership, the report prints no warning and the call afterwards returns the old method's result instead of raising. The walk does not lower the cache entry; the plan would carry that hole into the strict guarantee.
- **The rollback by restoring the lists breaks an invariant lock-free readers rely on** ("entries are never removed") and races with the candidate hook. Retire the entry instead, as the activation path already does for a refused image entry, and publish only what the search reads before the check.

With those changes the design is sound and no more complex than the plan. The image half should be a report at load, not a refusal, and not tonight.

## Findings, by severity

### H1. The search before the counter advances finds nothing — verified

- `src/gf.c` 7903–7909: `ml_matches_i` returns `jl_nothing` when `world > jl_world_counter` ("the future is not enumerable"). `ambiguous_at` (8306–8331) calls `ml_matches(..., world = entry_min_world, ...)` and returns 0 on any result that is not an array (8314–8315).
- The plan runs the search at `min_world = world + 1` between steps 2 and 3, with the counter still at `world`. So every `ambiguous_at` is 0, the strict check accepts every membership, and the plan's gate fails at its first case.
- Run (`probe_guard.jl`): `_methods_by_ftype(Tuple{typeof(f), Int}, …)` at the counter answers 1 match; at the counter + 1, `nothing`.
- The obvious patch, moving the check after the advance, is the alternative the plan rightly rejects (§3, "publish, then end").
- Why the guard is not needed here: under `world_counter_lock` the world `counter + 1` is fully determined. Method insertion takes the same lock (`jl_method_table_insert`, 5015–5022), so nothing can enter that world before the declaration's own entry; enumerating it under the lock is exact.
- **Change:** hoist the guard out of `ml_matches_i` into its two wrappers, `ml_matches` and `ml_matches_c` (1274–1295), and let `ambiguous_at` call `ml_matches_i` directly (it is static in the same file), setting and restoring the task's query world as the wrappers do. A comment states why the lock makes the next world enumerable. `jl_matching_methods` and every other caller keep the guard.

### H2. The search reads the dispatch caches, which hide the ambiguity whenever the member was called before — verified by a run

- `ml_matches_i` 7957–8026: for a dispatch tuple it answers from the leaf cache (`lookup_leafcache`, 1931–1947: any entry whose `[min_world, max_world]` covers the asked world) or from the method cache, with a single match and no search. `ambiguous_at`'s query for a concrete member is such a tuple (8419–8424: the two signatures with the member in place of the sets, intersected). The caches are lowered only by the walk's tail (4973–4994), which the plan runs after its check.
- Today's order (walk, then report) does not save it either. Run (`probe_control.jl`): `MODE=nocall`, the gate's shape, prints the warning and `f(SC())` raises — the harness is right. `MODE=call`, with `g() = f(SC())` called once before `@implement XC SC`: no warning, and afterwards both the dynamic `f(SC())` and the compiled `g()` return `:y`. Run (`probe_stale.jl`): after the second membership, `_methods_by_ftype(Tuple{typeof(f), SS}, …)` at the current world returns one method, `f(::YS)`, valid `[39620, ∞)`: a cache entry from before the membership whose `max_world` was never lowered. `Base.isambiguous` on the two methods says `true`, and `SS <: XS` is `true`.
- The cause, inferred from reading: `invalidate_intersecting` (4094–4213) fills `oldmi` only when `is_replacing` (3285–3307) says a specialization's dispatch is replaced. In a replay, `d[]` holds the replayed method itself (4079–4081, 4105–4106), and `is_replacing` is not told to skip it. With `m2` the replayed method, `ambig` set (4114) and `!jl_type_morespecific(m->sig, m2->sig)`, it returns 0 at 3301–3304 ("previously ambiguous"). So `replaced_dispatch` is 0, `oldmi` stays empty, and the tail `if ((oldmi && jl_array_nrows(oldmi)) || !dummy)` (4973) skips the cache lowering and the leaf-cache drop. Without a prior call there is no specialization and no cache entry, the full search runs, and the report fires: the gates pass.
- This is a deviation on its own: from compiler §5.5 ("a membership lowers the `max_world` of each leaf-cache and typemap-cache entry whose selected method changes at the new member") and, at the call, from traits §6.3 ("as in Julia: … raises `MethodError`"). The compiled call's guard (§5.6) did not fire either; whether it re-dispatched through the stale cache or carries no guard at this shape, I did not determine.
- For the plan: through `ml_matches` with the caches, the strict check would accept an ambiguous membership whenever the member had been called before — a hole in the strict guarantee at the most common case, a type in use gaining a second trait. And the plan's gate ("afterwards a call `f(S())` runs `f(::Y)`") passes for the wrong reason in that shape.
- **Changes:**
  1. `ambiguous_at` passes `mc = NULL`: both cache paths are under `if (mc)` (7957) and the cache write is too (8214); `cache_result` is already 0. The strict check then never depends on the walk's completeness, and the question of H1's ordering disappears.
  2. The stale cache is fixed separately, at `is_replacing`: it takes the replay's method to skip, or `invalidate_intersecting` passes `d` without it. Until built, a deviation row under compiler §5.5 with the gate of L1 (c).
  3. The gate list gains the called-before shape, under strict mode (refused) and without (warned, and the call raises) — L1.

### H3. The rollback by restoring the lists is unsafe; retire the entry instead — verified by reading

- `src/datatype.c` 993: `JL_GC_PROMISE_ROOTED(en); // entries are never removed from a TypeName's list`. Readers take no lock and do not root the list (compiler §4.2; e.g. `membership_superset_sets`, `src/gf.c` 4493–4500, calls `jl_subtype`, a safepoint, while iterating an unrooted `list`). A reader on another thread that loaded the new svec in the window keeps iterating it after the plan's restore makes it unreachable: a collection in that window frees it under the reader. Lock-free publication is sound only because nothing is ever unpublished.
- `register_candidate` (217–238) is written under `candidates_lock` only, and `jl_register_candidate` (318–325) is called from Julia at a member's first use, on any thread, without `world_counter_lock`. Restoring "the object read before step 2" drops a registration that landed in between.
- `jl_declared_memberships` (1203–1206) is pushed before the advance and is not in the plan's rollback; `src/staticdata.c` 3517–3530 writes every entry of it into the image, filtering by nothing but "in an image already".
- The redeclaration path ends every live entry of the same pattern and inputs (1191–1197), not "the old entry".
- **Change** — the shape the activation path already uses for a refused image entry (711–733: `max_world = world - 1`, "never in force"):
  - Before the check, publish only what the search reads: `publish_entry` (the member's svec: subtyping, `jl_typename_reaches`, the report's own list at 8352) and `index_entry` (`jl_set_entries`: `drop_unmet_matches` → `jl_unmet_final_cells` → `set_entries_meet` reads it at the query world, 7630, 928–930, 834–841, so the joint method at `All{X, Y}` is not dropped as unmet).
  - On a hit: `jl_atomic_store_release(&entry->max_world, world)` — with `min_world = world + 1` the entry is live in no world (`entry_live`, `entry_live_at` false everywhere; `jl_activate_memberships` 721 skips it in an image); each ended old entry's `max_world` back to `~0`; unlock, pop, throw. No list is touched.
  - On success: `register_candidate`, the two pushes to `jl_declared_memberships`, the advance, the cells, the walk, the report, as today.
  - Two readers filter by `min_world` only and must take `max_world` too: the report's collection of the member's sets (`src/gf.c` 8355) and the walk's superset sets (4497). Today they already count an image entry refused at activation as present (the same shape, `min_world = world`, `max_world = world - 1`), a latent over-report on C-35's path. With a retired entry at `min_world = counter + 1` and the counter unchanged, the next declaration gets the same `min_world`, and 8355 would put the refused set among the member's sets: a second, legitimate membership could then be refused for an ambiguity with a set the member is not in. Fix both to `min_world <= w && w <= max_world`.
  - The presence checks `jl_svec_len(memberships) != 0` (`src/subtype.c` 1871, `src/gf.c` 6995) go conservative for a type whose only entry is retired. Acceptable; compiler §4.3 says so.

### M1. The window is invisible to every other task, given H3's order — verified by reading, with two sites to confirm

- The query world is task-local (`src/subtype.c` 1198–1221: `ct->membership_world`); setting it to `min_world` affects the declaring task only.
- Readers of the member's svec filter by world: `entry_live` at 559, 1259, 1285, 1635, 1996, 5015 and `narrow_by_entry` at 1284, 1634 (`subtype.c`); `entry_live_at` at 840, 994, 1057 (`datatype.c`). The grep shows no `entry_live` at the readers 2050 and 5050 of `subtype.c`; the main session checks those two before building.
- `jl_membership_changed(min_world)` in `publish_entry` (189) raises `membership_last_change` (1885–1891). In the window, and after a refusal, a query at the counter takes the walk (`jl_membership_range_is_fast` false, 1894–1897), and a match's range ends at `world` (`narrow_by_entry` 1579–1581): matches computed meanwhile expire at the next world for nothing. Conservative, as the plan says. The reach memo (1513–1573) is capped at the counter (1605) and narrowed by the new entry, so a query in the search puts an empty range (`lo = min_world > hi = counter`) that never answers (1551): no pollution.
- The leaf cache, the method cache, the cells and `jl_declared_memberships` are untouched before the check. Inference on another thread reads candidates by `jl_candidates_of`; with H3's order they are registered on success only. The image writer reads `jl_declared_memberships` at exit (`staticdata.c` 3517), not concurrently with a declaration.
- `jl_set_entries` is written under `world_counter_lock` only (242); the retired entry stays in it and its readers filter by `entry_live_at`.

### M2. The same answer before and after the advance, after H1 and H2 — inferred

- The search's inputs are then: the member's svec and `jl_set_entries` (published), `mt->defs` (complete under the lock), `open_set_methods` (unchanged), subtyping at the query world. The caches are not inputs once `mc = NULL`; the cells are not read by the search.
- The walk only adds to interference sets (4120–4137, 4943–4949), and `ml_matches_i` reads them only as a shortcut for "more specific" (4017–4025, 8070, 8102); a missing pair keeps both matches. `ambiguous_at`'s own tests are type-based (8308, 8325–8326). So a check before the walk reports no fewer ambiguities than one after it. L1 (c)'s gate, under strict mode, exercises exactly this order.

### M3. The error: the place and the type are right; one path is not wrapped — verified by reading

- TraitWorld already wraps `_declare!`'s `ErrorException` into `ImplementError(X, member, msg)` at `@implement` (`src/implement.jl` 128–133), the path the cycle and second-instance refusals take. The plan's "`_declare!` catches the runtime's error under strict mode" needs no new code there. Traits §11.3's `ImplementError` row gains: an ambiguity under strict mode, with each pair and the joint method to define.
- Not wrapped: `@trait X <: Y` (`src/trait.jl` 58), the dynamic pattern (111), `Callable`'s patterns (`src/callable.jl` 19). A supertrait declaration refused for an ambiguity would raise a bare `ErrorException`. Wrap 58 and 111 the same way.
- The throw: compose the message under the lock into an `ios_t` while `found` is rooted (methods, not only their names, so the joint signature prints as the warning prints it, 8254–8258); `JL_UNLOCK`, `JL_GC_POP`, then `jl_errorf`. The same shape as the cycle refusal (1143–1147).
- The flag `jl_set_strict_memberships(int)`: set in `strict!` and in `_strict_init!` (`JULIA_TW_STRICT`). A precompile subprocess inherits the environment, so a package's ambiguous membership fails its precompile under strict mode: "refused at the membership" holds for images built under strict mode.
- `jl_membership_ambiguity_report` returns early when `allow_new_worlds` is off (8337–8338); `jl_declare_membership` already errors there (1136–1139). No gap.

### M4. The image half: report at load, do not refuse, not tonight — recommendation

- Facts §11.3, first row: a pirate loaded before an image is *reported* at the image's load and the code compiled again, not refused (`_load_pirates`, `PirateAtLoadError`), because it came first. An image's membership that meets an ambiguity only with the session's or an earlier package's methods is the same situation.
- An ambiguity among the image's own memberships and methods was refused at its precompile (M3); it cannot reach a load.
- Refusing at activation (the plan's C-35-style inactivation) invalidates the image's code compiled with the membership, for a condition its precompile could not see; keeping it leaves a `MethodError` at the ambiguous call, which G1 allows.
- **Change:** do not build the activation half. `jl_memberships_activated` keeps the report; under strict mode the message is an error-level report at load (TraitWorld's `_strict_at_load!` is the place, which needs the report's findings handed to Julia — the plan's `found` list, returned from activation — or its stderr line). T-98 is narrowed, not retired: "at an image's activation, an ambiguity with code loaded earlier is reported, not refused"; the choice goes to open-issues §1 for the user.

### L1. Gates: the plan's §4, plus

- (a) The plan's case, and the joint-method case, and strict mode off (the plan has these).
- (b) After a refusal: `S <: X` false, `jl_candidates_of(X)` without `S`, the counter unchanged; then the same `@implement` after the joint method is defined succeeds (the retired entry at the same `min_world` does not get in the way: H3's two readers).
- (c) **The called-before shape:** `g() = f(S())` called once, then `@implement X S`. Under strict mode: refused (H1 and H2 (1) together). Without strict mode: the warning prints and `f(S())` and `g()` raise. The second half fails on the head and stays an expected failure until H2 (2) is built: a new gate `m2_ambiguity_called_before` beside `m2_ambiguity_report`, named in the deviation row.
- (d) A redeclaration refused: `S` in `X{1}` already, `@implement X{2} S` meeting an ambiguity; afterwards `S <: X{1}` still true (the old entry's `max_world` restored).
- (e) `@trait Z <: Y` refused under strict mode raises `ImplementError` (M3).
- (f) A pattern member (`S{T} where T`), the report's abstract path (8434–8500), refused.
- (g) `m2_ambiguity_report`, `m2_ambiguity_arity`, `m3_ambiguity_dominance` unchanged; the battery.

### L2. The record

- traits §6.3 and §12.3 (status lines); T-98 narrowed to the load half (M4); traits §11.3's `ImplementError` row.
- facts §11.3's status: the membership row refused at a declaration; at an image's load reported.
- compiler §4.3: the step "strict mode's check" between publication and the advance; "an entry refused by strict mode is retired before it begins (`min_world = counter + 1`, `max_world = counter`): live in no world, never removed from its lists"; the counter does not advance on a refusal. §5.4: the report's contract (no longer warn-only; the search bypasses the caches and asks the next world under the lock). §5.5: a deviation row for H2's stale cache with its gate. §10.2: the flag.
- lowering §13: the refusal at `@implement` and at `@trait X <: Y`.
- `design/julia-changes.md`: a row for the build.
- The decision log, mine: retire rather than remove; the check reads no cache; the load half reported. Open-issues §1: the load half for the user.
- The experiment registry: the row before the run, with the gates of L1 and the battery.
- `state.md`: the strict-mode line.
- The C comment at 8237–8242: "WARN-ONLY contract" replaced by the new contract.

### L3. Minor

- `ambiguous_at` → `ml_matches_i(mt, NULL, q, -1, 1, 1, world, 0, &min, &max, &ambig, NULL)`; `drop_unmet_matches` takes `cells_out = NULL` (7635).
- Lock order unchanged: `world_counter_lock` → `open_set_methods_lock` (`jl_methods_at_set`, 2816) → `candidates_lock`.
- `membership_ambiguities(member, set_instance, world, found)`: with `found` non-NULL it prints nothing; one entry per function and pair of sets, as the warning (8390–8413).
- The plan's §3 first alternative is right for the wrong case: the check needs the entry in the lists not only for the joint method at `All{X, Y}` but for `sig_at_member`'s intersection and the match itself (`S <: X` is the entry).

## Verdict

**Build with the changes listed**, not as written:
- H1: the guard hoisted into the wrappers; `ambiguous_at` asks `ml_matches_i` at `min_world` under the lock.
- H2 (1): the check reads no cache (`mc = NULL`); H2 (2) and (3): the stale-cache bug recorded as a deviation with gate L1 (c), fixed at `is_replacing` as its own change.
- H3: retire, never remove; publish only the svec and `jl_set_entries` before the check; candidates, `jl_declared_memberships`, the advance, the cells and the walk on success only; the two `min_world`-only readers fixed.
- M3: no new catch at `@implement`; wrap the supertrait path.
- M4: no activation half; T-98 narrowed; the load half reported, the choice to the user.

Without H1 the feature does nothing; without H2 (1) it has a hole where it matters most; without H3 it is a use-after-free waiting for a second thread.
