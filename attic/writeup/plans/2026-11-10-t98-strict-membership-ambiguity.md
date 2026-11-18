# Plan: strict mode refuses a membership that makes methods ambiguous (traits T-98)

Status: **adopted with the review's changes** (2026-11-10; [the review](../reviews/2026-11-10-plan-review-t98.md)); built in `unified` 0bb8f38830 with TraitWorld 960b99e, E-343. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The deviation

- [Traits §12.3](../reference/traits.md#123-strict-mode): "An ambiguity at a membership (§6.3) is an error." [Facts §11.3](../reference/facts.md#113-strict-modes-errors-at-their-sources)'s table: "a membership that makes methods at two traits ambiguous for a type: refused at the membership".
- T-98: it is the runtime's warning, as without strict mode (`src/gf.c`, `jl_membership_ambiguity_report`).
- Why the runtime warns only: the report runs inside `jl_declare_membership` after the entry is published and the world counter advanced, under `world_counter_lock` ("WARN-ONLY contract: nothing here may throw", `src/gf.c` ~8237). Once published, a membership cannot be taken back: nothing ends one, and ending one would invalidate what relied on it, against "a membership invalidates nothing".
- So a strict-mode membership that meets an ambiguity exists, and the strict tier's promise (code compiled by facts invalidated only by a stakeholder's change; an ambiguity is a dispatch error waiting at a call) is broken by a warning.

## 2. The fix: check before the world advances, and roll back

`jl_declare_membership` (`src/datatype.c` ~1103–1215) does, under the lock:
1. the refusals (a cycle, another instance), then `min_world = world + 1`;
2. `publish_entry` (the member's `TypeName` list gains the entry, `min_world` set), `index_entry` (the set's list in `jl_set_entries`), `register_candidate`, a redeclaration's old entry ended at `world`;
3. `jl_atomic_store_release(&jl_world_counter, min_world)`: now tasks can see it;
4. the cells opened, the stopgap's dispatch walk, the ambiguity report, all at `min_world`.

Between 2 and 3 the entry is in the lists but invisible: every task's world is at most `world`, and the entry begins at `min_world`. The report's questions run in an explicit query world (`jl_set_membership_query_world`), so at `min_world` they see it.

**The change:**
- A runtime flag `jl_set_strict_memberships(int)`, set by TraitWorld's `strict!()` and cleared by `strict!(false)`.
- `jl_membership_ambiguity_report` becomes `membership_ambiguities(member, set_instance, world, jl_array_t *found)`: the same pairs and the same test (`ambiguous_at`), each ambiguity pushed to `found` as `(function name, X, Y, joint signature)`, or printed where `found` is NULL (today's warning). No change to which pairs it reports.
- With the flag on, between steps 2 and 3, at query world `min_world`: if the search finds any, the entry is rolled back and the declaration throws.
  - **The rollback:** the member's membership `svec`, the set's entry list and the candidate list restored to the objects read before step 2 (each list is replaced, never mutated, so the old object is the old state), and a redeclaration's old entry's `max_world` back to `~0`. `jl_membership_changed(world)` (called in `publish_entry`) stays: it lowers dispatch caches, which is conservative, never wrong.
  - Then unlock, and throw an `ErrorException` naming the member, the set, and each pair with its joint method's signature, as the warning names them.
- With the flag off: steps 3 and 4 as today, the report a warning.
- **TraitWorld:** `strict!()` sets the flag; `_declare!` catches the runtime's error under strict mode and raises `ImplementError(X, S, msg)`, the error a membership's check raises (traits §11).
- **Images:** an image's memberships are activated by `jl_activate_memberships`, not declared. Strict mode's check at load (`_strict_at_load!`) reports them; an image's membership that makes an ambiguity is left inactive with a warning, as an image's membership at another instance is today (C-35's path, `activation_conflicts`). Whether to build that half now is for the review.

## 3. Alternatives

- **Compute the ambiguity before publishing, without the entry:** the report's test asks the method table at the joint call types, where the method at the new set matches only once the member is in it. Without the entry, the joint method at `All{X, Y}` that would dominate does not match either, so the check would refuse memberships it should accept. Rejected: the check needs the world with the entry.
- **Publish, then end the membership:** a membership visible for one world that then ends, against "a membership invalidates nothing". Rejected.
- **TraitWorld re-derives the ambiguity in Julia:** a second copy of the report's logic, with the member substituted into parametric signatures. Rejected.

## 4. Gates

- TraitWorld's `test/strict.jl`: two traits `X`, `Y` with `f(::X)`, `f(::Y)` and no joint method; `S` a member of `Y`; under `strict!()`, `@implement X S` raises `ImplementError`; afterwards `S <: X` is false, `jl_candidates_of(X)` lacks `S`, the world counter has not advanced, and a call `f(S())` runs `f(::Y)`. With a joint method `f(::All{X, Y})` defined first, the same `@implement` succeeds. With strict mode off, it succeeds with the warning (today's behaviour, gate `m2_ambiguity_report`).
- The gates `m2_ambiguity_report`, `m2_ambiguity_arity`, `m3_ambiguity_dominance` unchanged; the battery.

## 5. Records

- traits §12.3 and T-98 retired; facts §11.3's status; compiler §5.4 (strict mode's error) and §10.2; lowering §13; the decision log, mine.

## 6. After the review

[The review](../reviews/2026-11-10-plan-review-t98.md): build, with its changes. What was done (`unified` 0bb8f38830, TraitWorld 960b99e; checked by E-343):
- **H1:** the world guard moved from `ml_matches_i` into its wrappers; the report's search calls `ml_matches_i` at the entry's world, under the lock.
- **H2 (1):** the search passes no method cache. **H2 (2):** the stale cache fixed in the same build: a membership's replay passes its own method to `is_replacing` to skip. Gate `m2_ambiguity_called_before` (without strict mode the dynamic and the compiled call raise and the report warns; under strict mode refused).
- **H3:** the entry and the set's index are published before the check; a finding retires the entry (`max_world = counter`), puts a redeclaration's old entries back in force and throws; the candidates, the image's list and the counter on success only. The report's set collection and the walk's superset sets count only entries live in their world.
- **M1, M2:** the window's readers checked (`subtype.c`'s readers at the lines the review left: an identity search and one filtered by `entry_counts`).
- **M3:** `@implement` already turned the runtime's refusal into `ImplementError`; a trait's supertrait and `Dynamic{X}` memberships do now (`_declare_checked!`). The message lists each ambiguity and its joint method. The flag is set by `strict!()` and by `JULIA_TW_STRICT=1`, which reaches a precompile process.
- **M4:** no activation half: T-98 narrowed to an error-level report at an image's load; the choice in open issues §1.
- **L1:** TraitWorld's `test/strict_membership.jl`: refused, no world advanced, the candidates without the member, a member called before, a pattern member, the joint method then accepted, a redeclaration refused keeping its old entry. Not built: a supertrait refused at `@trait Z <: Y` (no small case found).
- **L2:** the records (traits §6.3, §11.1, §11.3, §12.3, T-98; facts §11.3; compiler §4.3, §5.4, §5.5, §10.2; lowering §13; julia-changes; the decision log, mine; open issues §1).

