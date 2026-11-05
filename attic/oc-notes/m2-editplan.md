# M2 edit plan — dispatch at open sets: typemap placement, C7, the declaration-time walk, the ambiguity report

Plan only (planner subagent, 2026-10-30). Scope is exactly plan §4.2's dispatch
half + §5.M2's gates. **M1b is uncommitted and in flight while this was written —
`subtype.c`, `datatype.c`, `jltypes.c`, `cgutils.cpp`, `codegen.cpp`,
`julia.h`, `julia_internal.h`, `jl_exported_funcs.inc`, `Compiler/src/{abstractinterpretation,abstractlattice,tfuncs,typelattice,typeutils}.jl`
are being edited right now; their line numbers ALREADY moved twice during this
read. Every anchor in those files is semantic anchor-text, to be re-verified
when the author is done. `typemap.c`, `method.c`, `gf.c`, `ircode.c`, `ltypes.c`,
`base/*.jl`, `Compiler/src/methodinference.jl` are NOT in flight; their line
numbers were read fresh.** Style: 4 spaces, sparse lowercase comments.
**No struct-layout change is planned (§B).**

**AMENDED after the coordinator review (2026-10-30, reviewer agents W1/W4 +
W2/W3, verdict files `/tmp/opencode/m2-reviewW1W4.md`, `m2-reviewW2W3.md`;
rulings in notes.md): a new §0 (query-world override — BLOCKER, rides with M2a,
items 1–4, 6), the §1 top-entry + guarded-instantiation fixes, §2's arm via §1's
lookup, §7's GC/lock/world pins, §8's `ml_matches` argument pins, §4's W3
one-liner, and D6 resolved. Where an inline block and an amendment disagree,
the amendment (bold "REVIEW FIX"/"binding") wins.**

## Ground truth (probed on the current `julia-oc/julia` binary today)

1. Small (linear) typemaps **already dispatch to set methods** — M1b's subtype
   fallback makes `jl_typemap_entry_assoc_exact`'s `jl_tuple1_isa` true for
   members: `w(Late())` → `:set`.
2. In a **populated typemap the same call silently returns the wrong method**:
   with 30 typed methods + `w(::Any)` + `w(::Big)`, a member dispatches to
   **`:any`** — the entry sits under `name1[Big.name]` and every walk probes the
   *query's* chain (review M1, verified). Item 4 fixes it.
3. **Closed-vs-set ordering is silently wrong**: `f(::Kind)` + `f(::Col)`,
   `@implement Leaf Col` (`Kind` not a member) → `f(Leaf())` returns `:set`,
   not `:kind`. Cause: `jl_type_morespecific` leaves the pair unordered, the
   `METHOD_SIG_LATEST_ONLY` fast path in `ml_matches_visitor` (gf.c anchor
   `if (closure->match.issubty && only)`) early-exits on the set entry, and
   exact-list order picks it. Items 2 + 7's bit clears fix it.
4. **Set-in-set is not transitive for late members** (probed):
   `@trait A; @trait B <: A; @implement Late B` → `Late <: A` is **false**
   (`jl_membership_lookup` filters `en->set != set_name → continue`). The P6
   walk's "or a superset" and C7's set-in-set rule both depend on item 1.
5. `jl_declare_membership` publishes + advances the world counter with **no
   dispatch side** (datatype.c anchor
   `entry = jl_declare_membership_world(...); jl_atomic_store_release(&jl_world_counter, world);`)
   — H4's stale caches, live today.
6. Expectation for the walk's volume (numbers.md, M0): A/B ≈ 30–40×, A/C ≈
   30–50× at `show` — the replayed-insertion walk with C7 must land near B, not A.

Global invariants (plan §4.1–4.2, reviews H2/H4/M1/M2/M10):
- **I1 exactness holds** — intersections/dispatch answers stay exact *in the
  queried world*; only a live entry flips them. Nothing here widens an answer.
- **I2 no folded positives** — M1b's policy stands; M2 moves entry worlds through
  **match ranges**, not through folds (§6; the D2 answer).
- **I3 inertness** — every new branch is behind a typename `open_set` bit or
  `jl_has_open_set` read: with no set open in a session, all new code is a false
  flag read and Base behavior is bit-identical (`detect_ambiguities(Base)`, all suites).
- **I5 cache soundness** — a cache entry or CI may serve a tuple only for worlds
  where its selected method still wins: lowering at a membership uses
  `max_world = entry.min_world - 1` (aligned to the entry's visibility under the
  n3 `min_world = world_age` ruling, notes 2026-10-30 — **not** `counter-1`).

## 0. Query-world override (BLOCKER found in plan review, binding) — subtype.c + gf.c

The review round found the one mechanism M2 cannot proceed without:
`jl_type_infer` freezes `ct->world_age = jl_typeinf_world` around every
C-driven inference run (gf.c:469; same in `jl_gdbcodetyped1` :539/:570; the
global is fixed at runtime-init in `jl_set_typeinf_func` :1047/:1082) — a world
**strictly below** every runtime-declared entry's `min_world`. `jl_membership_world()`
therefore reads the frozen world during *all* inference: M1b's arms, §1's
helpers and §2's C7 arm never see runtime entries inside inference, CIs
compiled *after* a declare are mis-anchored, and §7's walk repairs only
pre-declare CIs. The W1-as-phrased doubt (ml_matches ordering with future
entries) is unfounded — ml_matches never calls morespecific (verified:
callers are only `is_replacing` :2313, `invalidate_missing_backedges` :2522,
activate :3073/3077, hint path :4007, `Base.morespecific`) — but this, the
opposite direction, is real.

```c
// in subtype.c next to jl_membership_world():
// query-world override for C-driven subtyping contexts (inference, the §7/§8
// declaration regions). 0 = follow the task (today's behavior). inference's
// task world is the frozen jl_typeinf_world, which sits below every runtime
// entry; the world argument is the truth there.
JL_DLLEXPORT void jl_set_membership_query_world(size_t world); // per-thread, e.g. JL_THREAD_LOCAL
static size_t jl_membership_world(void)
{
    extern JL_THREAD_LOCAL size_t jl_mq_world; // 0 = unset
    if (jl_mq_world)
        return jl_mq_world;
    jl_task_t *ct = jl_get_current_task();
    return ct ? ct->world_age : 0;
}
```

Set it to the `world` argument in `jl_type_infer` and `jl_gdbcodetyped1`
(raii-style: save/restore around the call); §7/§8 set it to `entry_min_world`
for their whole region (they run under `world_counter_lock` on the declaring
task, where n3 already made `entry_min_world == ct->world_age` — set it
explicitly, do not rely on the equality, it is D1). Cleared on return.
Consequences pinned by gates: new gate **m2_post_declare_infer** — compile a
caller AFTER `@implement` (both `code_typed` and call-then-read-CI shapes) and
assert it sees the set-method; today's `m2_stale_caller` covers only the
before-declare side. Comment fix while there (review nit): `world == 0` means
*no task at all* (pre-task C startup / serialization), not "image build sees
all" — during image build and precompile a task exists with a real world_age.

## 1. Transitive set-in-set answers (probe 4) — subtype.c + datatype.c *(in-flight files: anchors semantic)*

> **REVIEW FIX (coordinator ruling, review W1-F2, 2026-10-30).** The composition
> answers the **fronts** — `jl_isa`, the induced `Type{S}` arm, `intersect`'s
> covariant arm, `jl_membership_match_sig`/dispatch, `methods(f,(T,))` matches —
> while `subtype()` answers **direct entries only** (chain = 0). The earlier text
> here ("subtype … all true") and probe 4's framing are superseded: widening
> `<:`-across-links through chain composition is a deliberate **non-decision** of
> M2, deferred to M6 (positive-fold), because it drags every subtype consumer
> (compiler tfuncs, `obviously_disjoint`, method sorting) into the blast radius.
> Accepted, recorded consequences (deviations.md D-M2-1/D-M2-2): `<:` is
> non-transitive across membership links (`Late <: B` ∧ `B <: A` ∧ ¬(`Late <: A`)),
> `isa(x, T)` diverges from `typeof(x) <: T` and `typeintersect(S, T) == S` no
> longer implies `S <: T` for composed pairs; `FULLY_COVERS` matches at composed
> queries carry `spec_types` = the query (which matches the sig through the
> chain but is not `<:` it). Internal consistency holds: inference's `isa`-fold
> needs emptiness of the intersection, which composes — no fold-to-false can
> contradict a true composed `isa`.

`jl_membership_lookup` (anchor: the loop in `// find the live entry on the
member's TypeName naming set_name` whose body begins `if (en->set != set_name) continue;`)
skips every entry not naming the target. Replacement: same scan, plus a
transitive arm, plus world-range out-params that §6 reuses.

```c
// membership lookup, one level plus the set-in-set composition (plan §4.1:
// "sets-in-sets by their own entries"). lo/hi, when non-NULL, receive the
// composed world range of the entry chain (an indirect membership holds only
// while every link lives). depth bounds the walk; jl_declare_membership
// refuses set-in-set cycles, so the bound is a belt, not the rule.
static jl_value_t *jl_membership_lookup_level(jl_value_t *x, jl_typename_t *set_name,
                                              jl_value_t **instance_out, size_t world,
                                              size_t *lo, size_t *hi, int depth)
{
    // ... direct scan exactly as today (pattern env-match, instance bind) ...
    // for entries naming another set, when the direct scan found nothing:
    if (match == NULL && depth < 8 && en->set->open_set &&
        (world == 0 || (world >= en->min_world && world <= en->max_world))) {
        jl_value_t *mid = membership_instantiate(en, env, envn);
        // ^ REVIEW FIX W2-2 (binding): the direct path's guarded instantiation
        // (subtype.c:1204-1224: positional chain pairing, free-typevar refuse)
        // factored into a helper `jl_value_t *membership_instantiate(
        // jl_membership_t *en, jl_value_t **env /* VALUES, depth-ordered */,
        // size_t envn)`, shared by the direct and transitive arms — it builds
        // the depth-ordered vals and calls jl_instantiate_type_in_env (see M1b
        // commit efb87dfbdf: jl_instantiate_type_with does NOT take
        // interleaved (tvar,value) pairs; passing the values-only env there is
        // a silent no-op). mid is a fresh allocation across a recursive call
        // that allocates again: JL_GC_PUSH it (and inst2) in the loop frame.
        size_t lo2 = 1, hi2 = ~(size_t)0;
        jl_value_t *inst2 = NULL;
        if (mid != NULL &&
            jl_membership_lookup_level(mid, set_name, &inst2, world, &lo2, &hi2, depth + 1) != NULL) {
            size_t a = en->min_world, b = en->max_world;
            if (lo2 > a) a = lo2;
            if (hi2 < b) b = hi2;
            if (world == 0 || (world >= a && world <= b)) {
                match = top_entry_v;      // REVIEW FIX W2-1 (binding): report the
                                          // TOP-of-chain entry — the link whose
                                          // `set == set_name` — not the direct
                                          // one. Consumers (§3 wantkey, the
                                          // whole-family test) read `key` and
                                          // `instance` of the entry that NAMES
                                          // the queried set; the direct link's
                                          // fields describe a different set.
                                          // Thread it up as the recursion's
                                          // match out-param.
                inst = inst2;             // compare holds the top instance (already
                *instance_out = inst2;   // subtype-compared to y by jl_membership_answer)
                if (lo) *lo = a;
                if (hi) *hi = b;
                break;
            }
        }
    }
}
```

**Chain-key rule (D5 cross-reference, ruling): the TOP link's `key` governs a
chained membership. If any link of the chain carries a non-erased key, the
composed lookup answers 0 — conservative, matches §3's "an erased query matches
only erased entries, exactly".**

`jl_membership_answer` needs no shape change, but note what it consumes (fixing
the earlier misdescription): `inst == y`, then the **`en_v->instance`
whole-family test** against the set's wrapper, then `jl_subtype(y, inst)` — so
both the whole-family test and §3's wantkey read the returned entry's fields,
which is exactly why the top entry must be the one returned (W2-1). Callers keep the
`yd->name->open_set` guard (I3). Cycle refusal in `jl_declare_membership`
(datatype.c, anchor: `if (mpname == setname) jl_error("a set is not a member of itself");`):

```c
    // set-in-set must stay acyclic: the new set may not sit above the member
    // (only a set-member can close a cycle; entry lists are small, once per declare)
    if (mpname->open_set) {
        jl_typename_t *seen[8]; size_t ns = 0;
        jl_typename_t *cur = setname;
        for (int hop = 0; hop < 8 && cur; hop++) {
            if (cur == mpname)
                jl_errorf("set-in-set membership %s <: %s would create a cycle",
                          jl_symbol_name(setname->name), jl_symbol_name(mpname->name));
            seen[ns++] = cur;
            jl_svec_t *list = jl_typename_memberships(cur);
            cur = NULL;
            for (size_t i = 0; i < (size_t)jl_svec_len(list); i++) {
                jl_typename_t *s = ((jl_membership_t*)jl_svecref(list, i))->set;
                size_t k; for (k = 0; k < ns && seen[k] != s; k++);
                if (k == ns) { cur = s; break; }
            }
        }
    }
```
(A single-path walk suffices for this build's one-entry-per-(member,set) shapes;
a diamond can evade it; the depth bound keeps answering sound-conservative —
deviations.md.)
Invariant: transitive positives are world-filtered per link (I1). Gates:
**m2_set_in_set** (subtype/isa/`Type{Late}`/dispatch at `f(::A)` after
`@implement Late B`, `@trait B <: A`, both worlds).

## 2. C7 in `type_morespecific_` (P3, review M2) — subtype.c *(in flight)*

Current datatype-case tail (as read; the chain walk ends):

```c
            tta = tta->super; super = 1;
        }
        return 0;
    }
```

Reached only when `jl_type_morespecific`'s two `jl_subtype` probes (which already
consult entries — probe: an *abstract-member* declaration orders correctly
today) and the same-name/tuple paths declined. Replace the `return 0;` with:

```c
            tta = tta->super; super = 1;
        }
        if (!invariant) {
            // c7 (plan P3, review M2): at a position, a closed non-Any typename
            // orders above an open one; open-vs-open goes by the set-in-set
            // entries, else unordered. attribute wrappers erase to their held set
            // (review M3); a key strictly refines its own set. with no open sets
            // this is two false bit reads (I3). invariant (container-parameter)
            // positions keep vanilla semantics — bounded positions are arguments.
            jl_datatype_t *ua = (jl_datatype_t*)jl_unwrap_unionall(a);
            jl_datatype_t *ub = (jl_datatype_t*)jl_unwrap_unionall(b);
            if (ua->name->generic_wrapper && ua->name != ub->name) {
                // Keyed/Dynamic/Compiled/Kept erase to parameter 1; erasure is
                // strict when it lands on b's own name (Keyed{X,..} vs X)
                jl_value_t *held = jl_tparam0(ua);
                if (((jl_datatype_t*)jl_unwrap_unionall(held))->name == ub->name)
                    return 1;
                return type_morespecific_(held, b, a0, b0, invariant, env);
            }
            if (ub->name->open_set && a != (jl_value_t*)jl_any_type && !ua->name->open_set)
                return 1; // closed (non-Any) beats open — the C7 rule
            if (ua->name->open_set && ub->name->open_set && ua->name != ub->name)
                // REVIEW FIX W1-3 (binding): NOT a bare jl_subtype — a fresh
                // env re-quantifies the tvars bound in `env` at these recursion
                // points. Use §1's world-parameterized lookup: the question is
                // "does ub's name answer through ua's entries", answered as
                // jl_membership_lookup_level(unwrap(a), ub->name, NULL, world,
                // NULL, NULL, 0) != NULL ? 1 : 0, unordered (return 0) when no
                // chain. `world` from the §0 query-world override (see below).
                return membership_set_in_set(ua, ub, world);
        }
        return 0;
```

**World mechanism (binding, review W1 findings 2+4 — see §0): the C7 arm and the
probes above it must answer at one world.** A plain `world` parameter on
`type_morespecific_` alone would be inconsistent — `obviously_disjoint`
(subtype.c:572-575) and the two `jl_subtype` probes (5903/5905) consume the task
world before it is reached. The §0 per-thread query-world override covers the
whole path; no signature changes here.

Keyed-vs-Keyed needs no code: two interned `Keyed{X,R,F}` are `a == b` (top of
function, returns 0 = equal); differing parts hit the same-name arm's
`!jl_types_equal(apara, bpara) → return 0` (unordered) ✓; `Dynamic{X}` vs `X`
lands on the strict-erasure `return 1` ✓ (generic_wrapper covers all four).

Also in item 3's neighborhood, `jl_could_join` (anchor `if (xud->name->open_set) {`):
a `Keyed`/wrapper **y** is entry territory — before that arm add

```c
    if (xud->name->generic_wrapper)
        return jl_could_join(S, jl_tparam0(xud)); // a wrapper's set answers the question
```
(else `isa(v, Keyed{X,Nothing,Nothing})` could fold `Const(false)` forever while
erased entries are being declared — M1b left erased keys legal).

What C7 buys, mechanically (§5.M2's volume claim): activate's
`morespec[j] = jl_type_morespecific(d[j]->sig, type)` (gf.c:3072–3073) then
`continue`s past every chain-matched method (3100–3101) instead of recording an
interference + `_invalidate_dispatch_backedges` storm — that *is* M0's B ≪ A.
And the LATEST_ONLY fast path in *dispatch* (`ml_matches_visitor`, gf.c anchor
`if (closure->match.issubty && only)`) becomes correct once unordered means
genuinely unordered — with C7, probe 3's pair is ordered, the Kind-method sorts
first. Invariant: morespecific stays a partial order (sets above Any already;
two closed unrelated names cannot share a member — review M2); no
`jl_method_match_t`/`interferences` state change (P3). Gate:
**m2_closed_open_order** (probe 3 flipped to `:kind`; abstract-member ordering
stays; `f(::X)` vs `f(::Any)` still Any-loses; Keyed/Dynamic orderings above).

## 3. Keyed y-side key match — subtype.c *(finishes M1b's TODO M2)*

Anchor (M1b, in flight): the block at the head of subtype's datatype case —
`if (xd->name->generic_wrapper && xd->name != yd->name) { ... TODO M2:
Keyed-vs-Keyed and the key match when y is a set the entry's key refines (rides
with C7). return subtype(jl_tparam0(xd), y, e, param); }`. §2 gave morespecific
its half; the subtyping half is y-side: `S <: Keyed{X,R,F}` iff `S ∈ X` and the
entry's key is `(R,F)`. Implement inside `jl_membership_answer` (anchor:
`if (!jl_is_datatype(yu) || !((jl_datatype_t*)yu)->name->open_set)\n        return 0;`):

```c
    jl_value_t *yu = jl_unwrap_unionall(y);
    if (!jl_is_datatype(yu))
        return 0;
    jl_typename_t *yn = ((jl_datatype_t*)yu)->name;
    jl_typename_t *askset = yn->open_set ? yn : NULL;
    jl_value_t *wantkey = NULL;
    if (askset == NULL && yn == ((jl_datatype_t*)jl_unwrap_unionall(jl_keyed_type))->name) {
        // Keyed{X, R, F} is the members of X carrying key (R,F) (§2.6, review M3).
        // M2 knows one key form: the erased one (nothing ⇄ Keyed{X,Nothing,Nothing}).
        // real key objects arrive with M5's compilation-sig rule (open question D5).
        jl_value_t *kr = jl_tparam1((jl_datatype_t*)yu), *kf = jl_tparam2((jl_datatype_t*)yu);
        if (kr != jl_nothing || kf != jl_nothing)
            return 0; // a non-erased key can only match a non-erased entry — no folds, no matches yet
        askset = ((jl_datatype_t*)jl_unwrap_unionall(jl_tparam0((jl_datatype_t*)yu)))->name;
        wantkey = jl_nothing;
    }
    if (askset == NULL || !askset->open_set)
        return 0;
    // ... existing Type{S} `ask` rewrite and lookup against askset ...
    // on a hit with wantkey != NULL, additionally require en->key == jl_nothing
    // — n.b. (W2-1) `en` here is the TOP-of-chain entry returned by §1, the one
    // naming askset; the direct link's key belongs to a different set.
```

The lookup must hand back the entry (it already returns it; `answer` currently
discards it — keep it). Callers that gate on `yd->name->open_set` (UnionAll
pre-walk anchor `if (yd->name->open_set)\n                return jl_membership_answer(x, y); // same fallback`,
the datatype-case fallback, `jl_isa`'s L10 arm, `obviously_disjoint`,
`intersect`) gain `|| yd->name == keyed-name` — one-line helper
`static int jl_is_keyed_name(jl_datatype_t *yd)` so all five read the same.
`jl_subtype_via_membership` gets `... == keyed-or-wrapper name) return 1;`
beside its generic_wrapper arm (conservative 1 = refuse the fold — safe). M2
gates build no Keyed values — the rules are pinned as *types*
(`(S isa Keyed{X,Nothing,Nothing})::Bool`, `f(::Keyed{...})` ordering).
Invariant I1: an erased query matches only erased entries, exactly, per world.
Gate **m2_keyed_rules**.

## 4. Typemap placement: methods naming open sets live in `linear`, never `name1` (review M1) — typemap.c *(not in flight)*

`jl_typemap_level_insert_` (typemap.c:1400–1466) routes an entry by the type at
offset `offs` — `Any`-bucket, `arg1`/`targ` leaf caches, then `tname`/`name1`,
falling through to `cache->linear` only when nothing claims it. Lookups (all
four: `jl_typemap_assoc_by_type` :926, `jl_typemap_level_assoc_exact` :1175,
`jl_typemap_intersection_visitor` :589, and the `tname_intersection_dt`
:399 pre-filter) probe `name1` by the **query's** chain names — a membership is
not in any query chain (probe 2). (Review W3 verified: every walk visits the
level-0 `linear` unconditionally, so bounded entries placed there are total; the
only early-returning walks are `subtype=0` lookup mode, which reaches only
`jl_method_table->defs` via `jl_methtable_lookup` — the builtin-only table where
`jl_has_open_set` is false (I3), so the type-equality premise holds. Keep this
one-liner as a comment at the head check.) Insert at the head of `jl_typemap_level_insert_`,
right after the `t1`-computation block (anchor:
`if (t1 == (jl_value_t*)jl_typeofbottom_type)\n        t1 = (jl_value_t*)jl_assume(jl_typeofbottom_type)->super;`):

```c
    // bounded methods (plan §4.2, review M1): an entry whose signature names an
    // open set must stay in the linear list, which every walk visits — name1
    // probes key on the query's supertype chain, and a membership is not in any
    // chain. one memoized bit read (epoch-aware); false for every method when no
    // set is open (I3). this also holds when a list overflows MAX_METHLIST_COUNT
    // and jl_method_convert_list_to_cache re-inserts every entry: open-set sigs
    // are routed back to linear at the level they are reached, where every
    // lookup that intersects the earlier positions arrives (assoc_exact and
    // assoc_by_type walk linear after the name probes, before the any bucket;
    // the intersection visitor and the any bucket always visit it).
    if (jl_has_open_set((jl_value_t*)newrec->sig)) {
        jl_typemap_list_insert_(map, &cache->linear, (jl_value_t*)cache, newrec);
        return;
    }
```

Consequences, all verified reads:
- **Ordering**: a concrete (leaf) query that matches a typed method returns from
  the name probes *before* linear — closed matches keep winning exact dispatch
  with no morespecific call; the set entry is reached only when the probes miss,
  which is C7's rule shape.
- **Split safety**: `jl_method_convert_list_to_cache` (:1293) re-runs
  `jl_typemap_level_insert_`, which re-hits this check → the invariant survives splits.
- **Cost**: one extra `jl_typemap1_match` per bounded method per level-reaching
  lookup — E-253's census (131 across four ports) makes this the right trade;
  gate **m2_typemap_linear** times it (2× bar).
- **Freshness**: the read is the memoized bit with the B2 epoch — a sig built
  before the set opened recomputes lazily, so `@trait`-then-define routes
  correctly. Known gaps → deviations.md: a method at an abstract type *then* the
  type opened by hand (`@trait` always opens at declaration; gates use it), and
  image-loaded methods skipping `jl_method_table_add` (M6).
Invariant: with no set ever opened, zero routing changes (bit false at
`jl_typemap_alloc`-time for every Base sig) → Base typemaps byte-identical. Gate:
m2_typemap_linear + `make test-typemap` + the M1 suite times.

## 5. The set→methods index (review M10) — gf.c *(not in flight)*

`jl_method_table_add` (gf.c:2777) is the single runtime insertion funnel
(`jl_typemap_insert(&mt->defs, ...)` at :2791 — review sweep corrected the
one-line drift; re-verify at authoring). Hook after that insert, inside
`JL_LOCK(&mt->cache->writelock)`:

```c
    // index the methods whose signatures name an open set (review M10): rare
    // (E-253: 131 across four ports), so a globally rooted flat vec of
    // (set typename, method) pairs with a linear scan is the whole design.
    jl_index_open_set_methods(method);
```

```c
// gf.c, near update_max_args (:2133)
static jl_array_t *open_set_methods JL_GLOBALLY_ROOTED = NULL; // pairs: name, method
static jl_mutex_t open_set_methods_lock;

static void open_set_walk_names(jl_value_t *v, jl_method_t *m, int depth)
{
    // structural: register m under every open-set typename inside the sig
    // (direct argument positions today; nested occurrences are indexed too, so
    // the §7 walk can see them and choose its conservative path); depth caps at 8.
    v = jl_unwrap_unionall(v);
    if (depth > 8 || !jl_is_datatype(v))
        return;
    jl_datatype_t *dt = (jl_datatype_t*)v;
    if (dt->name->open_set) {
        JL_LOCK(&open_set_methods_lock);
        if (!open_set_methods)
            open_set_methods = jl_alloc_vec_any(0);
        jl_array_ptr_1d_push(open_set_methods, (jl_value_t*)dt->name);
        jl_array_ptr_1d_push(open_set_methods, (jl_value_t*)m);
        JL_UNLOCK(&open_set_methods_lock);
    }
    for (size_t i = 0; i < jl_nparams(dt); i++)
        open_set_walk_names(jl_tparam(dt, i), m, depth + 1);
}

static void jl_index_open_set_methods(jl_method_t *m)
{
    if (!jl_has_open_set((jl_value_t*)m->sig)) // one bit; false for every Base method (I3)
        return;
    open_set_walk_names((jl_value_t*)m->sig, m, 0);
}

// used by §7/§8: copy out the methods indexed under `tn`
static jl_array_t *jl_methods_at_set(jl_typename_t *tn)
{
    jl_array_t *out = jl_alloc_vec_any(0);
    JL_GC_PUSH1(&out);
    JL_LOCK(&open_set_methods_lock);
    if (open_set_methods) {
        size_t i, l = jl_array_nrows(open_set_methods);
        for (i = 0; i + 1 < l; i += 2)
            if (jl_array_ptr_ref(open_set_methods, i) == (jl_value_t*)tn)
                jl_array_ptr_1d_push(out, jl_array_ptr_ref(open_set_methods, i + 1));
    }
    JL_UNLOCK(&open_set_methods_lock);
    JL_GC_POP();
    return out;
}
```
(Global-rooted pair-vector under a lock follows the `_jl_debug_method_invalidation`
precedent; pairs are never removed — a stale one is filtered at use.)

## 6. Match world ranges — the entry feeds `min_valid` (I2/I5) — subtype.c + gf.c

A match of a bounded method at a member exists only while its entry lives;
without a bound, `ml_matches` reports `min_valid = 1` (gf.c:5229–5233 only raise
it to `m->primary_world`), `cache_method` stamps the leaf entry with it
(:1843/:1901), and a task in an older world would hit the *post-membership*
leaf entry and select the bounded method — unsound. Fix, at the match site.
New helper in subtype.c beside the lookup (in julia_internal.h, not the XX list
— gf.c is the same dylib):

```c
// world range of the membership (chain) that made `ti` (the intersection of a
// dispatch query with a signature) applicable: for each signature position
// naming an open (or Keyed) set, ask the query-side type's entries — reuse the
// §1 lookup (its lo/hi out-params and returned entry do the composition and
// the erased-key check). returns 0 when no position consulted an entry.
JL_DLLEXPORT int jl_membership_match_range(jl_value_t *sig, jl_value_t *ti, size_t world,
                                           size_t *lo, size_t *hi)
```
It unwraps the two UnionAll chains position-wise (the M1 fix's pairing
convention), applies `answer`'s `Type{S}`-answers-as-`S` rewrite to query-side
arguments, intersects every consulting entry's range — the same call M6's
positive-fold raise will make with an `sv`-side consumer (D2).

`ml_matches_visitor` (gf.c anchor: `closure->matc = make_method_match(` preceded
by the world-range block ending `if (closure->match.max_valid > max_world)\n        closure->match.max_valid = max_world;`) gains, right before `make_method_match`:

```c
    // a match that holds only through membership entries is valid only while
    // those entries live (I2: this is the dispatch-side world bound — inference
    // intersects it into sv.world.valid_worlds the way it does method worlds)
    if (jl_has_open_set((jl_value_t*)ml->sig)) {
        size_t lo = 1, hi = ~(size_t)0;
        if (jl_membership_match_range((jl_value_t*)ml->sig, closure->match.ti,
                                      closure->world, &lo, &hi)) {
            if (closure->match.min_valid < lo)
                closure->match.min_valid = lo;
            if (closure->match.max_valid > hi)
                closure->match.max_valid = hi;
        }
    }
```
Raising the *env* range is conservative for every other match in the same query
(cache entries and callers just re-resolve in older worlds — they answer with
the pre-membership dispatch, which is what those worlds must see anyway). The
same helper is what the M6 positive-fold raise will reuse (D2). Invariant I5.
Gate: **m2_stale_caller** pins `invoke_in_world`-old-world calls selecting the
old method even after a post-membership cached dispatch exists.

## 7. The declaration-time walk: P6 stopgap + permanent cache walk (review H4/§3.2) — gf.c + datatype.c

**Shape.** For the new entry (`member`, `set X`), every method whose signature
names a set the member (transitively) joins is re-resolved *as if its sig, with
the member substituted for the set, were inserted now* — the else-branch of
`jl_method_table_activate` (gf.c:3069–3161, not in flight): `get_intersect_matches`
→ `morespec[]` → ambiguity/interference/LATEST_ONLY bookkeeping → per-`mi`
`jl_type_intersection2` + `is_replacing` + `_invalidate_dispatch_backedges` →
`oldmi` → `invalidate_mt_cache` + leafcache flush (:3164–3191) +
`invalidate_missing_backedges` (:2487–2560). Substituting the **member**,
`Tuple{F,…,S,…}`, not the set, is forced because exact intersections and every
name probe key on `S.name`; M1b's `intersect` patch (anchor
`if (jl_membership_answer(x, y))`) makes those intersections *see* the
just-published entry — no widening anywhere.

**Extraction.** Move the else-branch verbatim into

```c
static int invalidate_intersecting(jl_value_t *type, jl_method_t *method,
                                   jl_method_t *const *d, size_t n, char *morespec,
                                   size_t max_world, jl_array_t *oldmi,
                                   int replay, struct membership_stats *stats)
```
— the body unchanged except: (a) `if (replay && d[j] == method) continue;` (the
replay's own method can be visited — its typemap entry is live, unlike a real
insertion where the new entry is invisible until :3197); (b) the two
`dispatch_bits` writes run only `if (!replay)`; (c) `stats` counts visits /
morespec-skips / spec invalidations / cache lowerings when non-NULL.
`jl_method_table_activate`'s else branch becomes one call with `replay=0,
stats=NULL` (line-identical behavior; upstream-merge friction accepted per P5 —
the alternative is 90 duplicated lines, D4).

**Driver** (gf.c):

```c
// plan §4.2 / P6: at a membership, replay "insert m with the member substituted"
// for every method m at the set or a set the member joins. call under
// world_counter_lock, after publishing the entry, before advancing the counter.
// GC (review sweep 7): the driver IS the caller that roots — JL_GC_PUSH2
// (&dummy, &substsing) (plus oldmi) at the top of the per-method loop:
// get_intersect_matches allocates internally BEFORE consuming dummy, and the
// substituted sig is freshly built per iteration. (The old §B claim "the dummy
// needs no push until stored" is withdrawn.)
// World (§0): jl_set_membership_query_world(entry_min_world) for the whole
// region (set before the loop, restore after) — do not lean on the n3 equality
// with ct->world_age here; pass/set the value explicitly (D1).
JL_DLLEXPORT void jl_membership_dispatch_walk(jl_value_t *member, jl_value_t *set_instance,
                                              size_t entry_min_world)
{
    size_t max_world = entry_min_world - 1;   // I5: align to entry visibility (n3 semantics), not the counter
    // 1. sets to walk: set_instance's name plus its superset closure (the entry
    //    lists on each visited set's own TypeName — the §1 data, lists are tiny).
    // 2. for each set Y, each m in jl_methods_at_set(Y->name):
    //      - substituted sig: the member pattern (its UnionAll re-wrapped over
    //        the sig's vars; family declarations share the tvar objects, M1's
    //        fix) for direct positional occurrences of Y's name;
    //      - rare shape (set inside a parameter, or under Vararg): conservative
    //        full pass — jl_method_table_invalidate(m, max_world, 0) (:2663)
    //        plus m's specializations into oldmi plus the §7 tail;
    //      - dummy = jl_typemap_alloc(substsing, simpletype-or-NULL, jl_emptysvec,
    //        (jl_value_t*)m, ~(size_t)0, 1) — never inserted; get_intersect_matches'
    //        asserts pass (min ~0, max 1, not in defs);
    //      - oldvalue = get_intersect_matches(mt->defs, dummy, &replaced, max_world)
    //        (replaced==NULL: a replay replaces nothing);
    //      - morespec[] per activate's loop; invalidate_intersecting(..., replay=1);
    //      - clear m's fast path (probe 3 abused the stale bit):
    //          jl_atomic_fetch_and_relaxed(&m->dispatch_status,
    //              ~(METHOD_SIG_LATEST_ONLY | METHOD_SIG_LATEST_WHICH));
    //        mirrored in the core for every visited d[j] whose bit activate clears;
    //      - tail exactly as activate: invalidate_missing_backedges with
    //        type = substituted sig; if (nrows(oldmi)) the invalidate_mt_cache +
    //        leafcache-max_world + empty-leafcache block under JL_LOCK(&mc->writelock).
}
```

Lock order: `world_counter_lock` → `mc->writelock` → `m->writelock` — identical
to `jl_method_table_insert`'s (gf.c:3204–3217) — plus §5's `open_set_methods_lock`
as the **innermost** nesting inside the `world_counter_lock` region (the only
writer, `jl_index_open_set_methods`, runs before insert takes world_counter_lock,
so the order never inverts; review W4-10). The whole §7/§8 region must stay
**throw-free** (a throw under JL_LOCK leaks the lock — the accepted-error pattern
is already at gf.c:3210 and datatype.c:254; §8 is warn-only, `jl_printf`).
World-visibility of the entry
during the walk: `jl_type_intersection`/`jl_subtype` read the *declaring task's*
`world_age` (= `entry_min_world` under n3) → the just-published entry is visible
to the walk; that is exactly what makes the intersections non-empty. **This
depends on the n3 `min_world = world_age` ruling as landed** — with the original
`counter+1`, the walk would answer pre-membership and find nothing; record the
dependency in the commit message (D1). With §0's override the walk sets the
world explicitly, which makes the D1 dependency a set-and-forget one line. Stats:

```c
static struct { size_t declares, replays, visits, morespec_skips,
                spec_invalidations, cache_lowerings, latest_only_clears; } membership_stats;
JL_DLLEXPORT size_t jl_membership_stat(int which); // gates ccall by index
```
plus, under `getenv("JULIA_MEMBERSHIP_LOG")`, one stderr line per declare
(`jl_printf`, `method_overwrite`-style): the §5.M2 log feeding `numbers.md`
(comparison target M0's B ≈ 2.9 % of A). `allow_new_worlds == 0` (image
building): skip the walk — entries land at package *execution*, not
serialization (M6 replays them). **Call site** (datatype.c, in-flight; anchor
inside `jl_declare_membership`:
`entry = jl_declare_membership_world(member, set_instance, key, declarer, by, min_world);`
before `jl_atomic_store_release(&jl_world_counter, world);`):

```c
    // dispatch half (plan §4.2, P6): re-resolve cached dispatch and compiled
    // decisions for the methods this member can now reach, then §8's report,
    // before the world is published. the jl_new_datatype hook does not replay:
    // a type being defined has no compiled callers or leaf entries yet.
    jl_membership_dispatch_walk(member, set_instance, min_world);
    jl_membership_ambiguity_report(member, set_instance);
```
Declare both in `julia_internal.h` beside `jl_declare_membership` (same dylib;
no `jl_exported_funcs.inc` change needed, though adding them is harmless — D6).
Invariant: H4's three stalenesses — leaf/typemap entries (§7 tail), compiled
static calls (backedge walk + `max_world` lowers), "no method" facts
(`invalidate_missing_backedges`) — all taken at the declaring world's commit
point; the dispatch-cache half is permanent (P6: M5's guards replace only the
code half). Gates: **m2_stale_caller**, **m2_closed_open_order**, **m2_set_in_set**.

## 8. Ambiguity report at a membership (exploration §2.3, review M10) — gf.c + datatype.c call above

For the new member's set-join, cross the member's other sets against the index:

```c
// order-independent report (exploration §2.3): a member of X and Y with a
// function holding a method at both and nothing more specific is a real
// ambiguity at that member — Julia's own dispatch will raise at the call; we
// warn now, at the declaration, where the whole picture exists.
JL_DLLEXPORT void jl_membership_ambiguity_report(jl_value_t *member, jl_value_t *set_instance)
{
    // sets = every set the member joins (§1's lists on the member's TypeName).
    //   (copy the set list out of the TypeName's _Atomic svec under a JL_GC_PUSH
    //    — review sweep 7: the read allocates nothing but the list must stay
    //    rooted across the report's own allocations.)
    // for each pair (X, Y), each mt with methods in both index lists:
    //   concrete member: the authoritative query. REVIEW FIX W4-9 (binding) —
    //   pin the two arguments that matter (gf.c:4926–4931, 5235–5244):
    //     ml_matches(mt, mc, sig, /*lim*/-1, /*incl_ambig*/1, /*intersections*/1,
    //                /*world*/entry_min_world, /*cache_result*/0, &min, &max, &ambig)
    //   cache_result=0: ml_matches would otherwise cache_method for a world not
    //   yet published and can set METHOD_SIG_LATEST_ONLY (gf.c:1888–1903) — §6
    //   then bounds wrong. world=entry_min_world, not the new world: inside the
    //   region the counter is still old, and ml_matches returns jl_nothing
    //   whenever world > counter (gf.c:4930) — a post-increment world yields a
    //   silently EMPTY report. WARN if it returns jl_nothing anyway. (The re-
    //   entrancy/alloc-under-lock worries are unfounded: jl_mutex is task-
    //   reentrant, ml_matches takes no locks with cache_result=0, and
    //   jl_method_table_insert already allocates under this very lock.)
    //     — exact, including the method-on-both and set-in-set suppressions;
    //   abstract/parametric member: no instance to ask — suppress if some
    //     indexed m3 has morespecific(m3->sig, mX->sig) && morespecific(m3->sig,
    //     mY->sig), else warn (a closed method on both sides not named by either
    //     set is missed — over-warn; deviations.md).
    // warn once per (mt, X, Y): unrelated set methods never intersected at
    // insertion, so Julia's own interferences never saw this pair.
    // WARN-ONLY contract: no jl_error / jl_errorf anywhere in this region —
    // a throw under world_counter_lock leaks the lock (W4-10).
    jl_printf(JL_STDERR, "WARNING: method %s at %s and %s is ambiguous for %s,"
              " a member of both sets\n", ...);
}
```
Warning only in M2; `no_pirates`'s error and the image-time hook are M6 (§4.6).
`jl_type_morespecific` here is post-C7, so a closed method on both sides *does*
suppress when the member sits under it (probe-3 shape).

## 9. Abstract queries — what §4.2's last item actually is, and its honest remainder

With exact intersections (ground truth) + M1b's known-member `intersect` answers
+ §6's range bump, the cases that exist in M2 already land right: query at a
**member** `S` → `ti = S`, `FULLY_COVERS`, invoke-legal, caller worlds bounded by
the entry; query at a **member set** (set-in-set `B ∈ X`) → the composed query
matches and `FULLY_COVERS` with `spec_types` = the query, which **matches the
sig through the chain but is not `<:` it** (W1-F2 ruling; deviations.md
D-M2-2 — H2's `spec_types ⊆ sig` is thereby weakened for composed pairs,
`invoke` legality and the inliner's `isa(x, spec_types)` split survive because
the intersect arm composes). The plan's
"`spec_types = X` (the erased key), never fully covering" form is for
**non-member abstract queries** (`f(x::AbstractFoo)` where a bounded method
*someday* applies): today they are pruned (exact `Bottom`), and §7's replay keeps
those compiled decisions sound when the declaration lands. The *forward-looking*
partial match (shadow query, guard cell) is plan M5, not M2: no M2 gate exercises
it, and building it without guard cells would regress inlining soundness (H2).
Stated deferral, one deviations.md line. Gate **m2_abstract_query** pins the two
M2-real cases plus old/new-world dispatch for the set-in-set query.

## Gates (§5.M2) — all new files, `oc-traits/gates/` (coordinator writes them; behavior pins)

| script | pins |
|---|---|
| `m2_dispatch_worlds.jl` | §5.M2's named gate: `g(s)` before/after a late `@implement` selects the right method in the right world **in both worlds** (`invoke_in_world`), incl. the leaf-entry bump from §6 (call at the member, then same call in the old world → old method) |
| `m2_stale_caller.jl` | H4: caller compiled *before* the membership at a concrete `S` (`Base.code_typed` + `all_cis` from `util.jl`): after `@implement`, its CI's `max_world` is lowered (the log/stat counters move), new-world call hits the bounded method, old-world call hits the old one, values both correct |
| `m2_set_in_set.jl` | item 1 + item 7's superset closure: late `@implement Late B` with `@trait B <: A` ⇒ `isa`/`Type{Late}`/dispatch at `f(::A)` all true/right, both worlds, while `Late <: A` stays FALSE (W1-F2 ruling: subtype answers direct entries only); cycle declaration errors |
| `m2_closed_open_order.jl` | probe 3 flipped: chain-matched closed method wins over the set method at a member (`:kind`), no ambiguity error; `f(::Any)` still loses to the set method; abstract-member ordering unchanged; erased-`Keyed` ordering (`f(::Keyed{X,Nothing,Nothing})` vs `f(::X)` vs `f(::C)`) |
| `m2_keyed_rules.jl` | item 3 as *type-level* pins only (no values): `S isa Keyed{X,Nothing,Nothing}` iff erased member; non-erased `Keyed` never matches; `Dynamic{S} isa X`; `could_join` refuses negatives at a `Keyed` y |
| `m2_typemap_linear.jl` | probe 2 flipped: member dispatches to `:set` in the populated table; then the E-259-shaped check: ~200-method function + ≥1 bounded method + member lookups within **2×** of the no-set control (best-of-5 wall on identical call loops, `@time`-style into numbers.md); `test-typemap` green |
| `m2_ambiguity_report.jl` | f at two unrelated sets + member of both ⇒ exactly one warning at the second `@implement`, no error; a method on a set-in-set `Z <: X, Y` suppresses; runtime still raises MethodError at the member (advisory) |
| `m2_abstract_query.jl` | §9's M2-real cases: set-in-set query match shape (`spec_types = B ⊆ X` via `methods(f, (typeof(g), B))`'s match records) + worlds; non-member abstract case documented remainder asserted only for *soundness* (pre-membership compiled call re-dispatches correctly post-entry via the walk) |
| `m2_volume.jl` | §5.M2's log gate: scripted show-class table + N late memberships; `jl_membership_stat` deltas; assert invalidations ≤ (M0's B-band) of the naive-A estimate and > 0; **per-declare wall time** too (W4-11: §8 runs a full `ml_matches` sort under the global lock per entry — a regression must show here, not only in counters); write rows to `numbers.md` |
| `m2_post_declare_infer.jl` | §0 blocker: compile a caller AFTER `@implement` — both `code_typed` at the member and normal-call-then-read-CI — and pin it selects/answers through the entry (inference must see runtime entries; the frozen `jl_typeinf_world` must not shadow them); the before-declare side stays `m2_stale_caller`'s |

Base: `make test-subtype test-core test-ambiguous test-typemap` in one
invocation, wall time vs the M0 control ±10 %, exit 0; `detect_ambiguities(Base)`
count unchanged; `test/core.jl:47`'s tripwire untouched (no layout).

## A. Files touched

| File | Why |
|---|---|
| `julia-oc/src/subtype.c` *(in flight)* | §1 lookup transitivity + ranges, §2 C7 + wrapper erase in `type_morespecific_` + `could_join` keyed arm, §3 y-side `Keyed` in `jl_membership_answer` (+ call-site guards), §6 `jl_membership_match_range` |
| `julia-oc/src/datatype.c` *(in flight)* | §1 cycle refusal, §7+§8 call sites in `jl_declare_membership` |
| `julia-oc/src/typemap.c` | §4 linear placement check in `jl_typemap_level_insert_` |
| `julia-oc/src/gf.c` | §5 index, §6 visitor bump, §7 `invalidate_intersecting` extraction + replay driver + stats, §8 report |
| `julia-oc/src/julia_internal.h` *(in flight)* | declarations: `jl_membership_match_range`, `jl_membership_dispatch_walk`, `jl_membership_ambiguity_report`, `jl_membership_stat` (no layout, no struct edits) |
| `julia-oc/src/jl_exported_funcs.inc` *(in flight)* | `XX(jl_membership_stat)` — D6 resolved: M1b registered all four callable entry points there; the gates ccall it, follow the precedent |

Not touched: `method.c` (no `Method` fields — the index is side tables;
`declared_rettype` is M5), `codegen.cpp`/`cgutils.cpp` (guards are M5),
`Compiler/*` (everything here is runtime-side; inference consumes the
min_valid/max_valid ranges through the existing `matching_methods` return),
`base/*.jl`, `boot.jl`, `staticdata*` (no serialization; image activation M6),
`test/*` (any new test is a gate script, coordinator's files).

## B. Build & test checklist

1. Per-file analysis first: `make -C julia-oc/src analyze-gf analyze-typemap analyze-subtype analyze-datatype --output-sync -j8`
   (+ `clang-sagc-*`); §5's pushes and §7's GC_PUSHes are written for it.
   n.b. (review sweep 7): `jl_typemap_alloc`'s dummy **must be rooted by the
   §7 driver** — `get_intersect_matches` allocates internally before consuming
   it; the earlier "no push until stored" note was wrong and is withdrawn.
2. **Wait for M1b to commit** (single-writer rule, workflow.md): re-verify every
   semantic anchor in the in-flight files against the landed tree.
3. `make -j4` via `oc-build.sh` (exclusive slot). **Layout: none.** The plan adds
   no `julia.h` struct field (index = global rooted array; stats = C globals;
   `jl_typemap_entry_t` untouched), so the staged-image purge is *not* required —
   and the tripwire stands: if `test/core.jl:47` goes red, someone changed the
   TypeName layout and §B's rule applies:
   `rm usr/lib/julia/{basecompiler,sysbase,sys}.{so,o,a} usr/share/julia/compiled && rm -rf usr/share/julia/compiled`
   (notes' build fact #1) before the next `make`.
4. `make fix-whitespace` before committing.
5. Base: `make test-subtype test-core test-ambiguous test-typemap` once; time
   vs control ±10 %; `detect_ambiguities(Base)` unchanged (I3 says why it must be).
6. Gates: each `julia-oc/julia --startup-file=no --project=oc-traits oc-traits/gates/m2_*.jl`;
   `m2_volume` and `m2_typemap_linear` write `numbers.md` rows (build commit + setting).
7. One run of every M1 gate (no regression through the C7/typemap changes).
8. Commits: M2a then M2b (§D3), messages per AGENTS.md
   ("subtype: ..." / "gf: ..."), one build between them.

## C. Why each gate passes (argument, per item)

- **m2_typemap_linear**: §4 routes set-naming sigs to `cache->linear`; every
  lookup walk visits the level's linear list after its probes (assoc_exact
  :1248, assoc_by_type :1081, intersection visitor :805, any-bucket tail) and
  split re-insertion re-hits the check → probe 2 flips to `:set`. The 2× delta is
  #bounded-methods × one match per level-reaching lookup; E-253 keeps #bounded ≈ 2.
- **m2_closed_open_order**: with §2, `jl_type_morespecific(closed-sig, set-sig)
  = 1` at the new branch; the `ml_matches_visitor` fast path then never fires for
  the set entry against a query the closed method covers (the §7 replay rebuilds
  interferences at the membership); `f(::Any)` keeps losing since
  `jl_subtype(set-sig, any-sig)` already ordered it; Keyed via the strict arm.
- **m2_stale_caller**: §7's replay intersects the old method's MIs with the
  substituted sig, the replaced-dispatch test demotes the selection, callers'
  backedges take `max_world = entry.min_world - 1`, the cache tail lowers/flushes;
  the next call re-runs `ml_matches`, §6 stamps `min_valid = entry.min_world`, so
  `invoke_in_world` to an old world misses the new entry and answers via the
  pre-membership method — whose own MI/CI survives (the walk lowers *callers*,
  not the fallback's code elsewhere).
- **m2_dispatch_worlds**: new world — linear placement (§4) + entry-visible
  subtype → set method; old world — the §6-bumped cache entry has
  `min_world > old` → miss → typemap → `intersect`/`isa` world-filter the entry →
  old method. Exact, per world (I1).
- **m2_set_in_set**: §1's transitive lookup answers the fronts (`isa`, `Type{Late}`,
  dispatch) with the composed world range while `Late <: A` stays false (W1-F2
  ruling); §7's closure walks supersets' indexed methods with the member
  substituted, and §1 makes those intersections non-empty (why item 1 gates first).
- **m2_keyed_rules**: §3 answers through the entry with the erased-key clause;
  non-erased keys stay conservatively false; `could_join`'s keyed arm refuses the
  negative fold so no `Const(false)` can bake (I2).
- **m2_ambiguity_report**: the `ml_matches`-with-ambiguity check is the same
  predicate dispatch itself uses — warn iff the call will raise; the set-in-set
  suppression is that same query, not a heuristic.
- **m2_abstract_query**: the pins are direct reads of `ml_matches` outputs; the
  soundness pin is §7's replay (missing-edge/mt-edge invalidation is activate's
  own machinery on the substituted sig).
- **m2_volume**: replay ≈ one method insertion with C7 skips; M0 measured
  B/A ≈ 3 % at show-class, so the ≤-bound with a >0 floor pins the walk as both
  real and C7-shaped — a C7 regression sends invalidations toward A (regression test).
- **Base suites + detect_ambiguities**: every new branch is behind
  `open_set`/`has_open_set` reads (I3); Base never opens a set, so typemap shape,
  morespecific results, and match ranges are unchanged; the §7 extraction is
  behavior-neutral (control times + full M1-gate re-run).

## D. Open questions for the coordinator

1. **D1 — the invalidation set when an entry lands.** Recommendation as built:
   the *typemap walk* (replayed insertion per indexed method, member
   substituted), not a global ms invalidation: precise (visits exactly the
   methods intersecting the member tuple, `f(::Any)` and the chain-matched closed
   ones included), reuses activate's `is_replacing`/backedge/cache/missing-edge
   machinery verbatim, and its volume is directly comparable to M0's B column;
   the ms alternative (invalidate everything mentioning the member's typenames,
   E-233-order) is the unmeasured hammer. **Dependency to bless:** the walk's
   intersections see the entry only because n3 stamps `min_world = declaring
   world_age` *and* the walk runs pre-counter-advance with `max_world =
   entry.min_world - 1`; if round-2 flips n3, item 7's world arithmetic and gate
   m1_worlds_minworld move with it.
2. **D2 — does M2 need the min_world-raise machinery from M1b's deferred rule?**
   No for **folds**: "entry-derived positives never fold" (M1b §10) stays — every
   member-method decision stays dynamic, answered per world through dispatch. Yes,
   minimally, for **matches**: §6's `min_valid` bump is mandatory (§6's probe
   reasoning: else a post-membership leaf entry serves pre-membership worlds).
   Same helper feeds M6's fold raise — M2 builds the shared half, not the fold half.
3. **D3 — staging into M2a/M2b.** M2a (semantics, inert-without-late-memberships):
   items 1, 2, 3, 4, 6 — build, M1 gates, m2_set_in_set/closed_open/keyed/
   typemap_linear/abstract_query; mergeable standalone (M1b's early-declaration
   usage is fully correct after M2a; late declarations stay as broken as M1b —
   no half-state is worse). M2b (the declaration-time machinery): items 5, 7, 8 —
   gates m2_dispatch_worlds, m2_stale_caller, ambiguity_report, volume. Two
   builds, both under the slot rules; if M2a's C7 surprises (P3's clause), stop
   before M2b and record.
4. **D4 — extraction vs duplication in gf.c.** §7 extracts activate's else-branch; alternative: duplicate ~90 lines behind `static`. I recommend extraction (drift risk dominates merge friction for a fork); say the word and I'll spec the duplicated variant instead.
5. **D5 — the key object representation.** §3 deliberately matches only the
   erased key (`nothing` ⇄ `Keyed{X,Nothing,Nothing}`); M5's
   `get_nospecializeinfer_sig` analogue defines the real form (svec(R,F)? the
   Keyed instance itself?) — decide at M5, and the `jl_membership_t.key` field is
   ready either way. Until then §3's conservative false is sound.
6. **D6 — RESOLVED: add `XX(jl_membership_stat)`** — M1b's precedent registers all
   four callable membership entry points in the inc; dynsym-only resolution was in
   fact never relied on. (D5 update from the W2 review: the chain-key question is
   ruled — top link governs, non-erased link ⇒ answer 0, see §1; the
   representation question stays M5.)
7. **Known gaps for `deviations.md`** (each already stated above): index misses image-loaded methods (M6); index misses methods defined before a hand-opened set (no gate uses it); §8 over-warns for a closed method on both sides at an abstract member; §1's cycle check is single-path (depth bound is the sound backstop); non-member abstract queries complete at M5 (§9).
