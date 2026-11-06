# Audit of `oc-build` at c3f0b4bc11, the start of the unified build (2026-11-06)

**What:** the earlier attempt's Julia branch `oc-build` at c3f0b4bc11 over v1.13.2 (`45b6d15e34`): 24 files, +2,627/−171 lines. It is now branch `unified` ([julia-changes §7](../design/julia-changes.md#7-the-unified-build-branch-unified)). The audit is W-97's item 5 ([the synthesis plan](../plans/2026-11-05-unification-synthesis.md) §4, stage 0): a verdict per file, the attempt's deviations re-judged, the two divergences from the design sized, the epoch and the query-world override judged, the gates read as code.

**By whom:** the main session, not a separate agent. The user ruled out subagents on the shared host on 2026-11-06. So this is not the independent read the plan asked for. Its findings rest on runs of the built branch, not on the author's reasoning.

**Against:** [compiler §7](../reference/compiler.md#7-traits-in-the-type-system) as written on 2026-11-06 (decisions 1–13), and the review of 2026-10-29.

**Method:**
- Read the whole diff. `src/gf.c` and `src/subtype.c` were read line by line; the rest of `gf.c`'s walk and report were read for structure.
- Built the branch on the shared host with `tools-local/build.sh`, at `-j4` because of the script's core-count defect, since fixed. Cold build 11:47–12:01, BUILD exit 0 by make (the log's final line is missing; see E-262).
- Ran the 22 `m1_*`/`m2_*` gates: 22 of 22 pass (`experiments/unification/logs/e262-gates-unified-c3f0b4bc11.log`).
- Wrote and ran probes for each suspected defect: `experiments/unification/audit/probes.jl`, log `experiments/unification/logs/audit-probes-c3f0b4bc11.log`.

**Counts:** high 2, medium 6, low 6.

---

## Verdict per file

| File | Lines | Verdict | Why |
|---|---|---|---|
| `src/julia.h` | +47 | **keep, rework** | Keep the `TypeName` bits, the `memberships` list and the entry struct. Keep the 32-bit memoized word, which `has_open_set` needs. Drop the 15-bit epoch (A5). |
| `src/julia_internal.h` | +71 | **rework** | The chain entry points go with decision 4 (`jl_membership_match_sig`, `jl_membership_holds_at`, the composed forms), and the query-world override with A4. |
| `src/datatype.c` | +250 | **keep the declaration; rework** | Keep the copy-on-write publication and the validation. Rework: the method-insertion world protocol (decision 5, A12), a full cycle walk (A6), the 8-variable limit (A3). Drop the epoch machinery (A5). |
| `src/builtins.c` | +52 | **keep** | The `_setsuper!` hook is right (the attempt's ruling). It publishes without the lock, which is sound for a type being defined (D-M2-3, re-judged below). |
| `src/jltypes.c` | +68 | **keep, rework** | Keep the Core types, the `TypeName` layout and the bootstrap bits. Add the builtin function types to `never_member` (A9). |
| `src/subtype.c` | +866/−? | **rework** | Keep the fallback in both chain walks, the exact intersection, the `obviously_disjoint` arm, `could_join`, `has_open_set`, C7 in `type_morespecific_` and the `obviously_disjoint` bypass. Remove the chain composition (decision 4, about 300 lines: `chain`, `scanall`, the top-of-chain logic, `membership_set_in_set`'s indirect arm, `jl_membership_match_sig`'s composed arm). Fix the type-value rule (A1) and the wrappers' intersection (A2). |
| `src/typemap.c` | +70 | **keep, simplify** | Keep the linear placement of methods at open sets (review M1) and the world bound on a negative answer. Under explicit memberships the bound reads only direct entries. Drop the composed-match arms. |
| `src/gf.c` | +1,208 | **keep the structure; rework** | Keep the extraction of `invalidate_intersecting` from `jl_method_table_activate`, the set-to-methods index, the replay walk (the stopgap, C-18), match ranges in `ml_matches_visitor` and the GC roots. Rework: drop the superset closure of the replay (decision 4); fix the ambiguity report's query arity (A7); replace the per-thread query-world override (A4). |
| `src/codegen.cpp`, `src/cgutils.cpp` | +46 | **keep** | Codegen's `isa`/`<:` folds refuse membership-relevant pairs, consistently with inference. |
| `src/gc-stock.c`, `src/gc-mmtk.c` | +3 | **keep** | Roots the set-to-methods index. |
| `src/jl_exported_*.inc` | +14 | **follow** | Follows the entry points kept. |
| `Compiler/src/*.jl` | +69 | **keep** | The fold gates are the structural exclusion of compiler §7.2. `tmeet`'s join is a precision loss only (A10). |
| `base/boot.jl`, `base/runtime_internals.jl`, `Compiler/src/typeutils.jl` (mask literals) | +19 | **keep** | Needed for the 32-bit memoized word. |
| `test/core.jl` | 1 | **keep** | `TypeName`'s field list. |
| `oc-build.sh`, `.gitignore` | +13 | **drop** | `tools-local/build.sh` replaces the script. |

---

## High

### A1. A type's membership makes its type value a member: `S isa X` and dispatch with the type object

**Where:** `src/subtype.c`: `jl_membership_holds` ("the induced Type{S} membership: Type{S} answers as S"); `subtype`'s `Type{T}` arm (`jl_typeof(tp0) == yd`, else `jl_membership_answer(tp0, yd)`); `jl_isa`'s type-value branch; `jl_could_join`'s `Type{S}` arm.

**Shown by** probe P1. After `@implement PS1 PX1`:
- `PS1 isa PX1` is `true`;
- `Type{PS1} <: PX1` is `true`;
- `p1(PS1)`, with `p1(::PX1) = :bounded` and `p1(::Any) = :fallback`, returns `:bounded`. The bounded method runs with the type object as its argument.

**What the design says:**
- A type value is a member only by an entry for `Type{S}` (open issue 91's decision; [traits §4](../reference/traits.md#4-implementations); compiler §7.2).
- `S <: X` and `S isa X` are different questions, as `Int <: Integer` and `Int isa Integer` are.

**Fix:** an entry for `Type{S}` answers `Type{S} <: X` and `S isa X`. An entry for `S` answers neither. The gates `m1_typevalue_isa` and `m2_set_in_set` (lines 17–18) pin the wrong rule and are re-pinned.

### A2. `Dynamic{X} <: X` holds, but intersection and dispatch disagree

**Where:** `src/subtype.c`: `subtype` erases a wrapper to its parameter (`generic_wrapper`), but `intersect` and the method table's match do not.

**Shown by** probe P2:
- `Core.Dynamic{PX2} <: PX2` and `d isa PX2` are `true`;
- `typeintersect(Core.Dynamic{PX2}, PX2)` is not `Core.Dynamic{PX2}`;
- `p2(Core.Dynamic{PX2}(1))`, with `p2(::PX2)` and `p2(::Any)`, returns `:fallback`.

**What the design says:** compiler §7.5: `Dynamic{X}` reaches the erased instance of a bounded method on `X`. Subtyping, intersection and dispatch must give one answer.

**Fix:**
- The wrapper rule goes into `intersect`, beside `Type{T}`'s, and into the typemap's match.
- A gate calls a bounded method with each wrapper. `m1_wrappers` tests only `isa`.

---

## Medium

### A3. A member pattern with more than eight type variables is accepted and never matches

**Where:** `jl_membership_env_match` (`vars[8]`, returns 0 at the ninth); `membership_instantiate` (`vals[8]`).

**Shown by** probe P3: a nine-parameter family is declared without error, and `P9{1,…,9} <: PX3` is `false`.

**Fix:** no fixed bound (allocate per pattern), or refuse such a declaration loudly. A silent `false` is a wrong answer.

### A4. The query world is a per-thread global

**Where:** `src/subtype.c` (`static __thread size_t jl_mq_world`); set and restored in `jl_type_infer`, `jl_gdbcodetyped1`, `jl_call_in_typeinf_world` and a new `ml_matches` wrapper.

**Why it matters:**
- The override belongs to the query, but it lives on the thread. A task switch inside a region would hand the override to another task on the same thread. `jl_call_in_typeinf_world` runs arbitrary Julia (`Compiler.typeinf_code`, reflection).
- The `ml_matches` wrapper adds a `JL_TRY` (a `setjmp`) to every method-table match. That is on the cache-miss path, not on every call.

**Fix:** carry the world into the membership lookup: in `jl_stenv_t` for subtyping, and as an argument from `ml_matches`, the typemap visitors and the declaration walk, which all have one. Where an entry point has no world (`jl_subtype` from a user), use the task's `world_age`. compiler §7.2 states the rule ("Inference asks in the world it infers for"); this is its form.

### A5. The `has_open_set` epoch, and its cap of 32,767 opened sets

**Where:** `src/datatype.c` (`jl_open_set_epoch`, `open_set_bit`, `open_set_witness`), the 15-bit `open_set_epoch` field, `jl_set_open_set`'s error "the open-set epoch is exhausted".

**Why it is there:** `@trait` expands to `abstract type X end` and opens the set afterwards. Types built in between would carry a stale `has_open_set`.

**Why it can go:** compiler §7.2 says "A set is open from its declaration".
- If the set is opened before its binding is published, no other type can have named it. So the bit computed at construction is right, as Julia's other memoized bits are.
- The library's `@trait` can call `Core._abstracttype`, open the set, then `_setsuper!` and `_typebody!`.
- The epoch also caps a session at 32,767 opened sets.

**Fix:**
- Open the set at its declaration.
- Refuse `jl_set_open_set` on a type whose binding is published.
- Drop the epoch, its 15 bits and the structural recomputation (about 100 lines). Keep the 32-bit word for `has_open_set`.

### A6. The set-in-set cycle check follows one path

**Where:** `jl_declare_membership`: the walk from the new set follows only the first unseen entry of each set, for 8 hops.

**Shown by** probe P5: `PC5 ∈ PD5`, `PC5 ∈ PA5`, then `PA5 ∈ PC5` is accepted. That is a cycle through `PC5`'s second entry.

**Fix:** a full walk of set-in-set entries, or set-in-set entries only at a set's own declaration (`@trait B <: A`). Under decision 4 the second is the design's case.

### A7. The ambiguity report builds a one-argument query

**Where:** `jl_membership_ambiguity_report`: the query is `Tuple{typeof(f), member}` whatever the methods' arity. A method `f(::X, ::Int)` gets an empty match, and an empty match is reported as an ambiguity.

**Fix:** build the query from the method's signature with the member at the set's positions; report only ambiguities, not empty matches. This also covers the attempt's D-M2-7 (over-warning for fixed against vararg pairs).

### A8. Memberships composed through chains (decision 4)

**Where:**
- `subtype.c`: `jl_membership_lookup_level`'s `chain` argument, `scanall` and the top-of-chain return, `membership_set_in_set`'s indirect arm, `jl_membership_match_sig`, `jl_membership_position`, `jl_isa`'s composed call;
- `typemap.c`: the composed-match arms;
- `gf.c`: `membership_superset_sets`.

**Shown by** probe P4: `PS4() isa PA4` is `true` while `PS4 <: PA4` is `false` (the attempt's D-M2-1).

**Size:** about 300 lines removed from `subtype.c`, about 40 from `typemap.c`, about 30 from `gf.c`. The gate `m2_set_in_set` is re-pinned to explicit entries. `m2_future_min_worlds` keeps its direct-entry cases.

---

## Low

- **A9. Builtin function types are not `never_member`.** Probe P6: `@implement typeof(getfield) PX6` is accepted. The kinds list of compiler §7.1 names the builtins. Fix: set the bit on each `Core.Builtin` subtype's `TypeName`.
- **A10. `tmeet` returns the join where a negative is blocked.** `Compiler/src/abstractlattice.jl`: `tmeet(S, X)` for a pair that could join gives `tmerge(S, X)`, wider than either argument. It is sound but loses precision after a `typeassert`. Fix: return `S` (the meet in any world in which `S` joined `X`).
- **A11. The walk's counters are plain globals,** written under `world_counter_lock` but read without it by `jl_membership_stat`. They are diagnostics only.
- **A12. The world protocol** (decision 5): `jl_declare_membership` sets the declaring task's `world_age` from C. Fix: drop those lines; `@implement` lowers to the call followed by `Expr(:latestworld)`. Re-pin `m1_late_implement` and `m1_worlds_minworld`.
- **A13. The stub library's `@implement S X`** takes the member first. The design writes `@implement X S`. Fix: the stub follows the design when stage 1 touches it.
- **A14. The build's log** misses `BUILD EXIT` for this build: the build script was edited while it ran (`tools-local/build.sh` now runs from a copy).

---

## The attempt's deviations, re-judged

| ID | The attempt's row | Now |
|---|---|---|
| D-M2-1, D-M2-2 | `<:` direct while `isa`, intersection and dispatch compose; a composed match's `spec_types` not `<:` the signature | go with decision 4 (A8) |
| D-M2-3 | the `_setsuper!` hook publishes without the lock | sound: the type being defined has no other reader. Keep, with the comment |
| D-M2-4 | a struct subtyping a set opened later gets no entry | goes with A5: a set is open from its declaration, so there is no "later" |
| D-M2-5 | the cycle guard is single-path | A6 |
| D-M2-6 | a throw under the lock leaks it | upstream's own class for method insertion; accepted |
| D-M2-7 | the ambiguity report over-warns for fixed against vararg pairs | part of A7 |
| D-M2-8 | a set named only in a typevar bound is flagged but not indexed | keep as a staged limitation; stage 2 adds the index entry (`set_name_nested` already finds it) |

## The gates, read as code

- **Pin defects:** `m1_typevalue_isa` and `m2_set_in_set` lines 17–18 pin A1.
- **Pin composition:** `m2_set_in_set` lines 16, 25, 30–31, 39, 46–48 pin decision 4's opposite.
- **Miss defects:** `m1_wrappers` tests `isa` for the wrappers but never dispatch (A2). No gate declares a pattern with more than eight variables (A3), a cycle through a second entry (A6), or a builtin member (A9).
- **Measure as written:** `m2_volume` and `m2_typemap_linear` count the stopgap and the placement.
- The probes of this audit become gates when their fixes land (stage 1 for A1, A3, A5, A6, A8, A9, A12; stage 2 for A2, A4, A7).

## What is done with each finding

| Finding | Where it is recorded |
|---|---|
| A1, A2, A3, A6, A8, A9, A12 | compiler Deviations C-19 to C-25; W-98 (A1, A3, A6, A8, A9, A12), W-99 (A2) |
| A4, A5, A7 | W-98 (A5), W-99 (A4, A7) |
| A10, A11, A13 | W-98's list |
| A14 | fixed: `tools-local/build.sh` (design repository) |
