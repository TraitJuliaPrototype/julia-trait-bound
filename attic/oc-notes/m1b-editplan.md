# M1b edit plan — the subtype/isa fallback, the exact layers, the fold gates

Plan only (planner subagent, 2026-10-30). Every quoted hunk was read from the working tree
(vanilla `45b6d15e34` + M1a, now committed as `2a2b2ba749` "datatype: membership entries and
open-set substrate" on `oc-build`) today; line numbers are as-read — trust the text. Style: 4 spaces, sparse lowercase comments. **No struct-layout change is planned (§B).**
Nothing outside `julia-oc/src`, `julia-oc/Compiler/src` is touched (§A).

Global invariants (plan §4.1; reviews H2/H3/L10/M3/M6):
- **I1 exactness:** `jl_type_intersection`, `jl_has_empty_intersection`, `obviously_disjoint`,
  `jl_isa`'s type-value branch stay exact *in the current world*: a non-member pair still yields
  `Union{}`/false; only a **known member** (entry live in the queried world) flips them.
- **I2 no folded negatives, no entry-derived folded positives:** the compiler folds a negative
  only where no open set could join, and never folds an entry-derived positive (M6 machinery is
  M2 — §10); runtime checks answer per world.
- **I3 one flag read on the slow path:** the fallback is consulted only after a chain was
  exhausted and `yd->name->open_set` (or a wrapper rule) fires; with no set open every new read
  is false and plain behavior is bit-identical.
- **I4 wrappers are rules, never instantiated** (M3): M1b implements x-side erasure to
  parameter 1; Keyed-vs-Keyed and y-side key matching are M2 (TODO marked).

**Shared helper.** Recon named it `jl_membership_answer(xdt, set_name, world, &instance_out)`;
the sites need the match environment, so it splits into `jl_membership_lookup` (pattern unify →
instance) and `jl_membership_answer` (compare instance to `y` like the chain case compares
params — `forall_exists_equal` per param in `e`; `e == NULL` probes use type equality). World:
`jl_current_task->world_age`; world 0 (image build) sees all entries.

**Discrepancies vs recon notes (files win).** The intersect chain block at :4292–4303 sits in
**`intersect()`**, not `intersect_all()` (that is the union driver at :4381) — item 5 patches
`intersect`. `jl_declare_membership` is **not** in `jl_exported_funcs.inc` (only
`julia_internal.h`). `jl_isa`'s fall-through to the `Type{S}` path is blocked by
`jl_has_intersect_type_not_kind` (false for an abstract set) — item 3 patches directly. There is
no `conditional_tfunc`/`Conditionals` in this 1.13 `typeutils.jl` (lattice refactor): the
refinement site is `isa_condition` (abstractinterpretation.jl); there is no `CurCode` — worlds
are `sv.world.valid_worlds` + `update_valid_age!` (§10).

## 0. M1a ground truth (read, not assumed)

- `julia.h`: typename bits `open_set/never_member/generic_wrapper/_unused:2`,
  `_Atomic(jl_svec_t*) memberships`; `jl_membership_t {set, member, instance, key, min_world,
  max_world, declarer, by}`; datatype memoized group `uint32_t` with `has_open_set:1`.
- `julia_internal.h` ~:898: `jl_typename_memberships(tn)`, `jl_declare_membership`. Globals ride
  the `sysimg_global` pattern; never write `extern`.
- `datatype.c`: `jl_declare_membership_world` (copy-on-write, atomic release), validation in
  `jl_declare_membership` (refuses never-member / closed set / wrapper patterns / self), the
  `jl_new_datatype` hook (`T <: X` open → final entry, min_world = counter).
- Core: `MembershipEntry`, `Keyed{X,R,F}`, `Dynamic/Compiled/Kept` (`generic_wrapper:1`),
  `never_member` kinds. **Missing until M1b:** `jl_set_open_set`, `jl_is_open_set`,
  `jl_has_open_set`, `jl_could_join` — `Traits.jl` already ccalls the first two.
- `jl_subtype(x,y)` takes no world; `jl_stenv_t` (:102–119) has no world field; the fallback
  reads `jl_current_task->world_age` (precedent subtype.c:299).
- M1a amended the TypeName field-list test in `test/core.jl` (:47) for the new `memberships`
  field. M1b changes no layout ⇒ no such amendment; if one ever sneaks in, that test is the tripwire.

## 1. `subtype()` main chain walk + the fallback (recon 1)

`src/subtype.c` :1575–1582 (current):

```c
        while (xd != jl_any_type && xd->name != yd->name) {
            if (xd->super == NULL) {
                assert(xd->parameters && jl_is_typename(xd->name));
                jl_errorf("circular type parameter constraint in definition of %s", jl_symbol_name(xd->name->name));
            }
            xd = xd->super;
        }
        if (xd == jl_any_type) return 0;
```

becomes `if (xd == jl_any_type) { if (yd->name->open_set) return jl_membership_answer(x, yd, e);
return 0; }` (braced, 4-space). Insert the helper block after the `static int
forall_exists_equal(...);` forward decl (:1101):

```c
// membership fallback (plan §4.1): after a supertype chain missed, a declared
// membership may still relate the pair. one helper for the subtype, isa,
// disjointness and intersection probes; entries live on the member's TypeName
// and are filtered by world. world 0 is the image builder: it sees everything.
static size_t jl_membership_world(void)
{
    return jl_current_task ? jl_current_task->world_age : 0;
}

// unify a member pattern against a member type, binding the pattern's tvars to
// x's parameters. the library can only declare `S` or `S{T...} where T...` with
// the tvars bare in S's parameters (exploration §2.5); env receives the bindings
// for jl_instantiate_type_with.
static int jl_membership_env_match(jl_value_t *member, jl_value_t *x, jl_value_t **env, size_t *envn)
{
    size_t i, j, n = 0;
    jl_tvar_t *vars[8];
    jl_value_t *m = member;
    *envn = 0;
    for (i = 0; i < 8; i++)
        env[i] = NULL;
    while (jl_is_unionall(m)) {
        if (n >= 8)
            return 0;
        vars[n++] = ((jl_unionall_t*)m)->var;
        m = ((jl_unionall_t*)m)->body;
    }
    jl_value_t *xu = jl_unwrap_unionall(x);
    if (!jl_is_datatype(m) || !jl_is_datatype(xu))
        return 0;
    if (n == 0)
        return m == x; // ground member pattern: the member itself
    jl_datatype_t *md = (jl_datatype_t*)m, *xd = (jl_datatype_t*)xu;
    if (md->name != xd->name || jl_nparams(md) != jl_nparams(xd))
        return 0;
    for (i = 0; i < jl_nparams(md); i++) {
        jl_value_t *pi = jl_tparam(md, i), *xi = jl_tparam(xd, i);
        int isvar = 0;
        for (j = 0; j < n; j++) {
            if (pi == (jl_value_t*)vars[j]) {
                if (*envn > j && env[j] != xi)
                    return 0; // a variable bound twice must bind the same value
                env[j] = xi;
                if (*envn < j + 1)
                    *envn = j + 1;
                isvar = 1;
                break;
            }
        }
        if (!isvar && !obviously_egal(pi, xi))
            return 0;
    }
    for (j = 0; j < n; j++)
        if (env[j] == NULL)
            return 0; // every pattern variable must be pinned by the member
    return 1;
}

// find the live entry on the member's TypeName naming set_name whose pattern
// matches x; on success the entry's instance, bound to the match, is stored in
// *instance_out (a slot the caller keeps rooted). returns the entry or NULL.
static jl_value_t *jl_membership_lookup(jl_value_t *x, jl_typename_t *set_name,
                                        jl_value_t **instance_out, size_t world)
{
    jl_value_t *xu = jl_unwrap_unionall(x);
    *instance_out = NULL;
    if (!jl_is_datatype(xu))
        return NULL;
    jl_svec_t *list = jl_typename_memberships(((jl_datatype_t*)xu)->name);
    jl_value_t *inst = NULL, *match = NULL;
    JL_GC_PUSH3(&list, &inst, &match);
    size_t i, l = jl_svec_len(list);
    for (i = 0; i < l; i++) {
        jl_value_t *entry_v = jl_svecref(list, i);
        jl_membership_t *en = (jl_membership_t*)entry_v;
        if (en->set != set_name)
            continue;
        if (!(world == 0 || (world >= en->min_world && world <= en->max_world)))
            continue;
        jl_value_t *env[8];
        size_t envn;
        if (!jl_membership_env_match(en->member, x, env, &envn))
            continue;
        inst = (envn == 0 ? en->instance : jl_instantiate_type_with(en->instance, env, envn));
        match = entry_v;
        break;
    }
    *instance_out = inst;
    JL_GC_POP();
    return match;
}

// the answer: does a membership entry relate x to the set datatype yd? the instance
// is compared to yd the way the chain's matched-name case compares parameters
// (forall_exists_equal per param). e == NULL (the env-free probes: emptiness and
// the exported predicates) uses component equality instead.
static int jl_membership_answer(jl_value_t *x, jl_datatype_t *yd, jl_stenv_t *e)
{
    jl_value_t *ask = x;
    if (jl_is_type_type(jl_unwrap_unionall(x)) && !jl_has_free_typevars(x)) {
        // the induced Type{S} membership: Type{S} answers as S (§2.8, open issue 91)
        jl_value_t *tp0 = jl_tparam0((jl_datatype_t*)jl_unwrap_unionall(x));
        if (jl_is_datatype(tp0))
            ask = tp0;
    }
    size_t world = jl_membership_world();
    jl_value_t *inst = NULL;
    if (jl_membership_lookup(ask, yd->name, &inst, world) == NULL)
        return 0;
    if (inst == (jl_value_t*)yd)
        return 1;
    jl_value_t *iu = jl_unwrap_unionall(inst);
    if (!jl_is_datatype(iu) || ((jl_datatype_t*)iu)->name != yd->name ||
        jl_nparams(iu) != jl_nparams(yd))
        return 0; // M1: set-parameter matching below the name is M5's family work
    if (e == NULL) {
        size_t i;
        for (i = 0; i < jl_nparams(iu); i++)
            if (!obviously_egal(jl_tparam(iu, i), jl_tparam(yd, i)))
                return 0;
        return 1;
    }
    int ans = 1;
    e->invdepth++;
    size_t i;
    for (i = 0; i < jl_nparams(iu); i++) {
        jl_value_t *ai = jl_tparam(iu, i), *bi = jl_tparam(yd, i);
        if (!(ai == bi || forall_exists_equal(ai, bi, e))) {
            ans = 0;
            break;
        }
    }
    e->invdepth--;
    return ans;
}

// env-free form for the exact layers (items 4, 5) and the exported predicates
static int jl_membership_answer_noenv(jl_value_t *x, jl_datatype_t *yd)
{
    return yd->name->open_set && jl_membership_answer(x, yd, NULL);
}
```

`answer` allocates nothing; `lookup` roots list/instance (re-run
`make -C src analyze-subtype` / `clang-sagc-subtype`). No `never_member` test is needed here —
entries cannot exist on a never-member TypeName (M1a refuses them). Invariant: one flag read
after the chain failed (I3); world filter ⇒ old worlds see nothing.

## 2. `subtype()` UnionAll pre-walk (recon 2)

:1526–1539 (current head of the block):

```c
    jl_value_t *ux = jl_unwrap_unionall(x);
    jl_value_t *uy = jl_unwrap_unionall(y);
    if ((x != ux || y != uy) && y != (jl_value_t*)jl_any_type && jl_is_datatype(ux) && jl_is_datatype(uy) &&
        !jl_is_type_type(ux)) {
        assert(ux);
        if (uy == (jl_value_t*)jl_any_type)
            return 1;
        jl_datatype_t *xd = (jl_datatype_t*)ux, *yd = (jl_datatype_t*)uy;
        while (xd != NULL && xd != jl_any_type && xd->name != yd->name) {
            xd = xd->super;
        }
        if (xd == jl_any_type)
            return 0;
    }
```

The `jl_datatype_t *xd = ...; while ...; if (xd == jl_any_type) return 0;` part becomes:

```c
        jl_datatype_t *xd = (jl_datatype_t*)ux, *yd = (jl_datatype_t*)uy;
        if (xd->name->generic_wrapper && xd->name != yd->name)
            return subtype(jl_tparam0(xd), y, e, param); // §6; the recursion re-enters unwrapped
        while (xd != NULL && xd != jl_any_type && xd->name != yd->name) {
            xd = xd->super;
        }
        if (xd == jl_any_type) {
            if (yd->name->open_set)
                return jl_membership_answer(x, yd, e); // same fallback, or the bare-name case never runs
            return 0;
        }
```

For a parametric set `yd` is the wrapper body (`X{T}`, tvars free); the lookup binds the
pattern's tvars to `x`'s parameters, then `forall_exists_equal` answers per the chain's
matched-name convention — `S <: X` (bare wrapper) resolves here.

## 3. `jl_isa` type-value branch + `Type{S}` in `subtype` (recon 3, review L10)

(a) `jl_isa` else at :2546–2548 (current):

```c
                else {
                    return 0;
                }
```

becomes (the recon's expected fall-through to :2550/:2552 does not happen for a set:
`jl_has_intersect_type_not_kind(X)` is false, so :2552's guard would skip the `Type` path):

```c
                else {
                    if (!((jl_datatype_t*)t2)->name->open_set)
                        return 0; // vanilla: a type object's typeof is a Core kind
                    // L10: an open set answers the Type{S} question through the
                    // member's entries; jl_subtype has the induced rule (§1)
                    JL_GC_PUSH1(&x);
                    x = (jl_value_t*)jl_wrap_Type(x);
                    int ans = jl_subtype(x, t);
                    JL_GC_POP();
                    return ans;
                }
```

`jl_is_concrete_type(t) return 0` (:2523, :2562) stays: sets are abstract (§9 refuses
non-abstract `@trait`), so that fast path never fires for one.

(b) `subtype()` :1552–1562 — `Type{S} <: X` is answered by this fast path *before* the chain,
so the fallback never sees it (current, inside the `!jl_is_typevar(tp0)` arm, after the long
comment): `return jl_typeof(tp0) == (jl_value_t*)yd;` becomes:

```c
                if (jl_typeof(tp0) == (jl_value_t*)yd)
                    return 1;
                if (yd->name->open_set && jl_is_datatype(tp0) && !jl_has_free_typevars(tp0))
                    return jl_membership_answer(tp0, yd, e); // Type{S} answers via S's entries
                return 0;
```

Invariant: `isa(Late4, X4)` ≡ `Late4 ∈₍world₎ X4`; `Int`/`Late4b` exact-false in every world (I1).

## 4. `obviously_disjoint` (recon 4)

:559–570; the inner `if (temp == jl_any_type) return 1;` becomes:

```c
                if (temp == jl_any_type) {
                    // H2: a known membership keeps the pair non-disjoint; a
                    // non-member still is, exactly, in the current world
                    if (jl_membership_answer_noenv(a, bd))
                        return 0;
                    if (jl_membership_answer_noenv(b, ad))
                        return 0;
                    return 1;
                }
```

(`ad`/`bd` are the originals in this branch — the else path reassigns only on a chain match.)
Reached from `intersect_types` (pre-check for `jl_type_intersection` :4448 and
`jl_has_empty_intersection` :4472) and `type_morespecific_` (`specificity=1`, C7 is M2).

## 5. `intersect()` datatype case (recon 5 — *inside `intersect`, see header discrepancy*)

:4292–4303 (current):

```c
        if (param == 2) return jl_bottom_type;
        while (xd != jl_any_type && xd->name != yd->name)
            xd = xd->super;
        if (xd == jl_any_type) {
            xd = (jl_datatype_t*)x;
            while (yd != jl_any_type && yd->name != xd->name)
                yd = yd->super;
            if (yd == jl_any_type)
                return jl_bottom_type;
            return intersect_sub_datatype((jl_datatype_t*)y, xd, e, 1, param);
        }
        return intersect_sub_datatype((jl_datatype_t*)x, yd, e, 0, param);
```

only the `if (yd == jl_any_type)` body changes (rest of the quoted block untouched):

```c
            if (yd == jl_any_type) {
                // exact in the current world (H2): a known member intersects to
                // itself, continuing as the matched-name case would have; the
                // ground pair usually went through the jl_subtype fast path at
                // the top (which consults §1) — this catches union branches,
                // where e->Loffset suppresses it. non-members stay bottom.
                if (jl_membership_answer_noenv(x, (jl_datatype_t*)y))
                    return (jl_value_t*)x;
                if (jl_membership_answer_noenv(y, (jl_datatype_t*)x))
                    return (jl_value_t*)y;
                return jl_bottom_type;
            }
```

(the walked `yd` is `Any` here — the originals are the `x`/`y` parameters; the exact M1 answer
is the member type itself, no new `intersect_sub_datatype` call).

## 6. `generic_wrapper` erasure (recon 6)

Datatype case head :1548–1551 (quoted above through `jl_datatype_t *xd = ...`); insert after
that declaration line in `subtype()` (the pre-walk got the same two lines in item 2):

```c
        if (xd->name->generic_wrapper && xd->name != yd->name) {
            // Dynamic{S}/Compiled{S}/Kept{S} are members of S's set at the erased
            // key; Keyed{X,R,F} vs a non-Keyed y erases to X (§2.6-2.7, review M3).
            // TODO M2: Keyed-vs-Keyed and the key match when y is a set the
            // entry's key refines (rides with C7).
            return subtype(jl_tparam0(xd), y, e, param);
        }
```

Same-name wrapper pairs fall through to the matched-name case as datatypes; erasure is a rule,
not an entry (M1a refuses wrapper declarations); the `Keyed` erasure only makes `Keyed{X,R,F} <:
X` answerable — gates never build Keyed values.

## 7. `jl_could_join` (+ companions) — new exported predicates (recon 7)

In `subtype.c` after §1's helpers:

```c
// forward-looking conservative predicate for the inference lattice and the
// compiler's negative folds (H2/H3): could a future declaration make S (or
// something structurally inside it) a subtype of X? conservatively true is
// always safe — its only job is refusing a negative fold. never used by
// dispatch's match construction. M2's stopgap refines the future-world picture.
JL_DLLEXPORT int jl_could_join(jl_value_t *S, jl_value_t *X)
{
    jl_value_t *su = jl_unwrap_unionall(S);
    jl_value_t *xu = jl_unwrap_unionall(X);
    if (jl_is_uniontype(xu))
        return jl_could_join(S, ((jl_uniontype_t*)xu)->a) || jl_could_join(S, ((jl_uniontype_t*)xu)->b);
    if (jl_is_uniontype(su))
        return jl_could_join(((jl_uniontype_t*)su)->a, X) || jl_could_join(((jl_uniontype_t*)su)->b, X);
    if (!jl_is_datatype(su) || !jl_is_datatype(xu))
        return 1; // unknown shapes are conservative
    if (jl_is_type_type(su)) {
        // Type{S} joins X exactly when S does (the induced entry, §2.8)
        jl_value_t *tp0 = jl_tparam0((jl_datatype_t*)su);
        if (jl_is_datatype(tp0) && !jl_has_free_typevars(tp0))
            return jl_could_join(tp0, X);
    }
    if (xu->name->open_set)
        return su->name != xu->name && !su->name->never_member;
    if (su->name == xu->name && jl_nparams(su) == jl_nparams(xu)) {
        // inside a container a membership can flip the answer at a position
        // (Tuple{S} vs Tuple{X}); invariant parameters count too, since a union
        // inside one can collapse (H3's Vector{Union{S,X}} case). per position.
        size_t i, np = jl_nparams(su);
        for (i = 0; i < np; i++) {
            jl_value_t *pi = jl_tparam(su, i), *qi = jl_tparam(xu, i);
            if (jl_is_vararg(pi))
                pi = jl_unwrap_vararg(pi);
            if (jl_is_vararg(qi))
                qi = jl_unwrap_vararg(qi);
            if (!jl_is_type(pi) || !jl_is_type(qi))
                return 1;
            if (jl_could_join(pi, qi))
                return 1;
        }
        return 0;
    }
    return 0;
}

// the caller found S <: X true — was that answer from an entry rather than the
// chain? anything it cannot resolve is 1 (refuse the fold). mirrors subtype's walk.
JL_DLLEXPORT int jl_subtype_via_membership(jl_value_t *S, jl_value_t *X)
{
    if (S == jl_bottom_type || X == (jl_value_t*)jl_any_type)
        return 0;
    jl_value_t *su = jl_unwrap_unionall(S);
    jl_value_t *xu = jl_unwrap_unionall(X);
    if (!jl_is_datatype(su) || !jl_is_datatype(xu) || jl_is_uniontype(xu))
        return 1;
    if (((jl_datatype_t*)su)->name->generic_wrapper)
        return jl_subtype_via_membership(jl_tparam0((jl_datatype_t*)su), X); // §6 erasure answered it
    if (jl_is_type_type(su) && xu->name->open_set)
        return 1; // the induced Type{S} rule is always entry-answered
    jl_datatype_t *xd = (jl_datatype_t*)su;
    while (xd != jl_any_type && xd->name != xu->name) {
        if (xd->super == NULL)
            return 1;
        xd = xd->super;
    }
    return xd == jl_any_type; // the chain missed: only an entry could say true
}

// orientation-free pair relevance used by codegen (item 10e)
JL_DLLEXPORT int jl_membership_flip_possible(jl_value_t *a, jl_value_t *b)
{
    if (!jl_has_open_set(a) && !jl_has_open_set(b))
        return 0;
    return jl_could_join(a, b) || jl_could_join(b, a);
}
```

Declare all three in `julia_internal.h` beside `jl_declare_membership` (§9).

## 8. `has_open_set` upkeep (recon 8)

`src/jltypes.c`, `jl_precompute_memoized_dt` (:1843 head quoted in §0 shape): after
`dt->maybe_subtype_of_cache = 1;` add

```c
    // own name first, so a recursive bound reading this bit mid-loop sees it (H3)
    dt->has_open_set = (dt->name->open_set || dt->name->generic_wrapper);
```

and inside the existing parameter loop, after `if (jl_is_vararg(p)) p = ((jl_vararg_t*)p)->T;`
(:1868–69):

```c
        if (!dt->has_open_set && p && jl_has_open_set(p))
            dt->has_open_set = 1;
```

The walker in `src/datatype.c` after `jl_new_typename_in`:

```c
// structural open-set question (H3): true when an open set or an attribute wrapper
// occurs in the type, incl. under Union/UnionAll/parameters. recursion stops at
// each parameter DataType's memoized bit — computed before any type naming it is
// built — so it terminates; the same convention as maybe_subtype_of_cache and
// has_concrete_supertype (jltypes.c), which never re-enter a partial type's params.
int jl_has_open_set_in(jl_value_t *v) JL_NOTSAFEPOINT
{
    jl_value_t *uw = jl_is_unionall(v) ? jl_unwrap_unionall(v) : v;
    if (jl_is_datatype(uw)) {
        jl_datatype_t *dt = (jl_datatype_t*)uw;
        return dt->name->open_set || dt->name->generic_wrapper || dt->has_open_set;
    }
    if (jl_is_uniontype(uw))
        return jl_has_open_set_in(((jl_uniontype_t*)uw)->a) ||
               jl_has_open_set_in(((jl_uniontype_t*)uw)->b);
    if (jl_is_typevar(uw))
        return jl_has_open_set_in(((jl_tvar_t*)uw)->ub); // ub stops at a DataType's bit
    return 0;
}
```

Recursive-bound corner (`T <: Vector{T}`): the ub is a complete DataType object → its *bit* is
read, never its params, so no cycle; the only mid-construction read is the type's own
pre-initialized bit → conservative 0. The own-name live check covers the `@trait` window (the
set's body DataType predates its open bit; nothing names it earlier — notes item 8). The
memoized word rides image serialization as a scalar (M1a confirmed), no staticdata work. Types
built before any `@trait` keep bit 0 forever ⇒ Base builds see zero gate activations (I3).

## 9. ccallables (recon 9)

`src/datatype.c`, after `jl_declare_membership`:

```c
// open a set (Traits.@trait). errors unless T is an abstract type; does not
// advance the world (the declaration that created T already did).
JL_DLLEXPORT void jl_set_open_set(jl_value_t *T)
{
    jl_value_t *uw = jl_unwrap_unionall(T);
    if (!jl_is_datatype(uw) || !((jl_datatype_t*)uw)->name->abstract)
        jl_error("jl_set_open_set: only an abstract type can be an open set");
    ((jl_datatype_t*)uw)->name->open_set = 1;
}

JL_DLLEXPORT int jl_is_open_set(jl_value_t *T)
{
    jl_value_t *uw = jl_unwrap_unionall(T);
    return jl_is_datatype(uw) && ((jl_datatype_t*)uw)->name->open_set;
}

JL_DLLEXPORT int jl_has_open_set(jl_value_t *v)
{
    return jl_has_open_set_in(v);
}
```

`julia_internal.h`: declare `jl_has_open_set_in, jl_has_open_set, jl_is_open_set,
jl_set_open_set, jl_could_join, jl_subtype_via_membership, jl_membership_flip_possible` beside
`jl_declare_membership`.

`src/jl_exported_funcs.inc` — the `XX(name) \` list (generates `ijl_` renames; loose
alphabetical clusters; ccalls resolve via dynsym regardless, but this is the convention):
after `XX(jl_cstr_to_string) \` (:97) `XX(jl_could_join) \`; after `XX(jl_has_free_typevars) \`
(:233) `XX(jl_has_open_set) \`; before `XX(jl_isa) \` (:264) `XX(jl_is_open_set) \`; after
`XX(jl_set_module_infer) \` (:409) `XX(jl_set_open_set) \`; after `XX(jl_subtype) \` (:435)
`XX(jl_subtype_via_membership) \`; plus (recommended — closes the recon's false premise)
`XX(jl_declare_membership) \` and `XX(jl_membership_flip_possible) \` in their spots.

## 10. Compiler half — fold gates (recon 10), codegen, the M6 deferral

**Verified mechanism:** worlds live in `sv.world.valid_worlds`; `update_valid_age!(sv,
WorldRange(...))` is `Compiler/src/inferencestate.jl:989`; CI `min_world =
first(sv.world.valid_worlds)` (`typeinfer.jl:611/:1011/:1190`). The tfuncs are invoked from
`builtin_tfunction(interp, f, argtypes, sv)` (`abstractinterpretation.jl:2068`) — **`sv` is in
scope there but not passed into the tfunc table**. Raising `min_world` on an entry fold needs
`sv` (or a report-out) threaded through `add_tfunc`/that site, *and* `jl_subtype_via_membership`
extended with the entry's `min_world` — genuinely M2-sized. **M1b policy (taken; the gates show
it suffices): an entry-derived positive never folds — the fold site returns `Bool` (or the join
for meets) and the per-world runtime check answers; no CI depends on an entry, so no raise is
needed.** A negative folds only when no open set involved could join.

Gate helpers, `Compiler/src/typeutils.jl` after `isnotbrokensubtype` (:49):

```julia
# membership fold gates (plan §4.1, review H3/M6): a negative about a pair that a
# future declaration could join never folds; a positive answered by a membership
# entry never folds either until M6's min_world bookkeeping lands (M2). both are
# cheap flag reads in a session without open sets (I3).
function negative_fold_blocked(@nospecialize(a), @nospecialize(b))::Bool
    (ccall(:jl_has_open_set, Cint, (Any,), a) != 0 || ccall(:jl_has_open_set, Cint, (Any,), b) != 0) || return false
    return ccall(:jl_could_join, Cint, (Any, Any), a, b) != 0 ||
           ccall(:jl_could_join, Cint, (Any, Any), b, a) != 0
end
function positive_fold_blocked(@nospecialize(a), @nospecialize(b))::Bool
    (ccall(:jl_has_open_set, Cint, (Any,), a) != 0 || ccall(:jl_has_open_set, Cint, (Any,), b) != 0) || return false
    return ccall(:jl_subtype_via_membership, Cint, (Any, Any), a, b) != 0
end
```

### 10a. `tfuncs.jl` (:859–933 as read)

- `isa_tfunc`: before `return Const(true)` (the `⊑(𝕃, v, t)` arm):
  `positive_fold_blocked(widenconst(v), t) && return Bool`; before each of the two
  `return Const(false)` sites (the `isa(v, Const) || isa(v, Conditional)` arm — restructure
  `isdispatchelem(v) && return Const(false)` to a multi-line `if` — and the
  `!hasintersect(v, t)`/`!iskindtype(v)` arm): `negative_fold_blocked(<widenconst(v) or v>, t)
  && return Bool`. The `t === Bottom` arm (:879–884) stays — an untypish RHS has no set question.
- `subtype_tfunc`: before `return Const(true)`: `positive_fold_blocked(a, b) && return Bool`;
  before `return Const(false)`: `negative_fold_blocked(a, b) && return Bool`.
- `typeassert_nothrow` (:866–875): fold the `if` into a block and before `return true` add
  `positive_fold_blocked(widenconst(v), isType(t) ? t.parameters[1] : t.val) && return false`
  — a nothrow proved through an entry must not drop the throw path.
- `typeassert_tfunc` is `tmeet(𝕃, v, t)` — gated at 10b.

### 10b. `abstractlattice.jl` — `tmeet` (the meet moved here in 1.13); current:

```julia
function tmeet(::JLTypeLattice, @nospecialize(a::Type), @nospecialize(b::Type))
    ti = typeintersect(a, b)
    valid_as_lattice(ti, true) || return Bottom
    return ti
end
```

becomes:

```julia
function tmeet(::JLTypeLattice, @nospecialize(a::Type), @nospecialize(b::Type))
    ti = typeintersect(a, b)
    if !valid_as_lattice(ti, true)
        # the empty meet is a negative: refuse it (the join instead — wide but
        # live) when a later world could inhabit the pair (H3)
        negative_fold_blocked(a, b) && return typejoin(a, b)
        return Bottom
    end
    return ti
end
```

Covers `typeassert_tfunc` and the lattice's other type meets; over-wide results are safe for
every consumer found (narrowing, union splitting) — the deliberate `≤`-contract break is §D-1.

### 10c. `typeutils.jl` — `typesubtract` (:126–129 current head quoted 10b-style);

`if a <: b && isnotbrokensubtype(a, b) / return Bottom` becomes:

```julia
    if a <: b && isnotbrokensubtype(a, b)
        # subtracting to Bottom keeps the else-branch dead only while the positive
        # answer holds: an entry answer does not bound older worlds (M6)
        positive_fold_blocked(a, b) && return a
        return Bottom
    end
```

plus the same guard line at the top of the tuple-splits arm (`elseif b isa DataType`, before
the `notbottom` loop). `a <: b` *false* paths already return `a` — conservative, no gate. The
other `hasintersect` consumers (48 sites) conclude from the *exact* C intersection; only the
H3-named negative-fold sites needed gates (done); the remainder is an M2 audit (E-255 census).

### 10d. `abstractinterpretation.jl` — `isa_condition` (the 1.13 shape of the plan's
"`typeutils.jl` Conditionals"), second arm :2002:

```julia
        if !has_free_typevars(tty_lb) && !has_free_typevars(tty_ub)
            negative_fold_blocked(tty, tty_ub) && return nothing # H3: refine neither side
            thentype = typeintersect(tty, tty_ub)
```

(one line inserted; the `Const(rt)` arm :1985–1996 reacts to `isa_tfunc`, already gated — a
vetoed fold yields no `Const`; `egal_condition` compares values, untouched.)

### 10e. `src/cgutils.cpp` — `emit_isa` (:1968–1997): inference gating is not enough — codegen
re-derives static answers in a *later* world than the method's `min_world` (a CI compiled after
the entry but valid from before it would bake the wrong constant; `probe_early` is exactly this).
Current:

```c
    std::optional<bool> known_isa;
    jl_value_t *intersected_type = type;
    if (x.constant)
        known_isa = jl_isa(x.constant, type);
    else if (jl_is_not_broken_subtype(x.typ, type) && jl_subtype(x.typ, type)) {
        known_isa = true;
    } else {
        intersected_type = jl_type_intersection(x.typ, type);
        if (intersected_type == (jl_value_t*)jl_bottom_type)
            known_isa = false;
    }
```

becomes:

```c
    std::optional<bool> known_isa;
    jl_value_t *intersected_type = type;
    if (x.constant) {
        // a membership flips this answer in another world: keep the runtime
        // check when the pair is membership-relevant (plan §4.1 M1b)
        bool v = jl_isa(x.constant, type);
        if (!(v ? jl_subtype_via_membership(jl_typeof(x.constant), type)
                : jl_membership_flip_possible(jl_typeof(x.constant), type)))
            known_isa = v;
    }
    else if (jl_is_not_broken_subtype(x.typ, type) && jl_subtype(x.typ, type) &&
             !jl_subtype_via_membership(x.typ, type)) {
        known_isa = true;
    } else {
        intersected_type = jl_type_intersection(x.typ, type);
        if (intersected_type == (jl_value_t*)jl_bottom_type) {
            if (jl_membership_flip_possible(x.typ, type))
                intersected_type = type; // keep the check, against `type` itself
            else
                known_isa = false;
        }
    }
```

With `intersected_type = X2` (abstract) the function's tail reaches its generic
`jl_subtype(typeof(x), type)` runtime call, and the `msg == "typeassert"` form goes through
`jl_typeassert` (both world-checked — verified against the tail at :2008–2072). codegen.cpp
needs no change: the typeassert always emits via `emit_typecheck`→`emit_isa`
(codegen.cpp:4198–4214).

### 10f. `base/boot.jl` — **nothing needed** (say so in the commit): `MembershipEntry`, `Keyed`,
`Dynamic`, `Compiled`, `Kept` are C-declared (`jl_init_types` + `add_builtin`, M1a).

## A. Files touched

| File | Why |
|---|---|
| `julia-oc/src/subtype.c` | §1–5 + §6 + §7 (helper, two chain walks, `Type{S}`, `jl_isa`, disjoint, intersect, erasure, exported predicates) |
| `julia-oc/src/datatype.c` | §8–9 (`jl_set_open_set`, `jl_is_open_set`, `jl_has_open_set_in`, `jl_has_open_set`) |
| `julia-oc/src/jltypes.c` | §8 upkeep in `jl_precompute_memoized_dt` |
| `julia-oc/src/julia_internal.h` | §9 declarations; **no struct change** |
| `julia-oc/src/jl_exported_funcs.inc` | §9 `XX(...)` entries |
| `julia-oc/src/cgutils.cpp` | §10e `emit_isa` |
| `julia-oc/Compiler/src/typeutils.jl` | gates + 10c |
| `julia-oc/Compiler/src/tfuncs.jl` | 10a |
| `julia-oc/Compiler/src/abstractlattice.jl` | 10b |
| `julia-oc/Compiler/src/abstractinterpretation.jl` | 10d |

Not touched: `base/boot.jl` (10f), `julia.h` (no layout), `staticdata.c`/image activation (M6),
`typemap.c`/`gf.c`/`type_morespecific_`/stopgap walk (M2), `codegen.cpp` (verified unnecessary).

## B. Build & test checklist

1. `make -C julia-oc/src -j4`, then `make -C julia-oc/src analyze-subtype analyze-datatype
   analyze-jltypes` (+ `clang-sagc-*`) per AGENTS.md; resolve GC findings in §1's helpers.
2. Full `make -j4` via `oc-build.sh` (exclusive slot, niced). **Layout:** this plan adds no
   `julia.h` fields (all state exists from M1a) ⇒ the staged-image purge is *not* required.
   If any layout field does sneak in, first:
   `rm usr/lib/julia/{basecompiler,sysbase,sys}.{so,o,a} usr/share/julia/basecompiler.ji usr/share/julia/sysbase.ji && rm -rf usr/share/julia/compiled`.
3. `make fix-whitespace` before committing.
4. `make test-subtype test-core test-ambiguous`; record wall/peak vs the M0 control (±10 %,
   `numbers.md`); `detect_ambiguities(Base)` unchanged. Expect zero behavior deltas: no set is
   open inside Base's own builds (I3).
5. Gates ×4 (repo root, per gates/README.md):
   `julia-oc/julia --startup-file=no --project=oc-traits oc-traits/gates/m1_<name>.jl`.
6. For any Compiler-side iteration after a rebuild: `JULIA_TEST_FAILFAST=1` subsets /
   `make test-revise-*` as applicable.

## C. Why each gate passes

- **m1_late_implement.** `probe(y) = y isa X1` (compiled pre-entry): the `isdispatchelem`
  `Const(false)` fold is vetoed (could_join ⇒ 10a) → `Bool`; `emit_isa`'s intersection-bottom
  fold is vetoed (10e) → per-call runtime `jl_subtype`. False pre-entry, true post, false in
  `invoke_in_world(w_old)` (world filter, item 1). Entry + `min_world == w_old+1` come from M1a's
  publish protocol; `X1b` shows independent entries (`lookup` filters `entry->set`).
- **m1_compiled_isa.** `isaq/subq/tupq`: negatives at `X2` never fold (10a); the runtime
  `<:`/`isa` answer per world through items 1–2 — `tupq` needs §7's container recursion
  (`has_open_set(Tuple{X2,Int})` via §8 + per-position `could_join`). `castq`: `isa(x, Late2)`
  folds freely (no set in it); the then-block's `x::X2` keeps its runtime check (compiled while
  `Late2 ⊑ X2` false) and the `tmeet`/typeassert vetoes (10a/10b) keep the code after it live ⇒
  `TypeError` pre-membership and in the old world, `=== x` in the new.
- **m1_worlds_minworld.** `probe_early` compiled *after* the entry: the positive would fold
  (`Late3 ⊑ X3` via entry) — `positive_fold_blocked` (`via_membership`: chain misses `X3`'s name
  ⇒ 1) refuses ⇒ `Bool` + runtime check ⇒ false under `invoke_in_world(w_before)` (:23) with no
  `min_world` machinery. `probe_late`'s CIs satisfy :34 trivially (its method is defined in the
  entry's world ⇒ `ci.min_world ≥ e.min_world` by construction); :36's early CI predates the
  entry with its method. `probe_late` in `w_before` is a `MethodError` (method table — M1b
  doesn't touch it).
- **m1_typevalue_isa.** `Late4 isa X4`: 3a wraps to `subtype(Type{Late4}, X4)`; 3b's patched
  fast path asks `Late4`'s entries — none ⇒ false pre-declaration (exactly), true post, false
  old-world (filter); `!(Int isa X4)`/`!(Late4b isa X4)` exact (no entries, I1). :28 exactness:
  plain values go through `jl_subtype(typeof(v), X4)` → no entries → false; unions absorb
  nothing (§4/§5 stay bottom for non-members).

## D. Open questions for the main session

1. **`tmeet`'s `≤` contract** (10b): the veto returns `typejoin(a,b)`, not a meet — safe for
   every consumer read so far; record in `deviations.md`, or return `b` (typeassert-faithful) if
   any consumer needs the invariant.
2. **`XX(jl_declare_membership)`** in `jl_exported_funcs.inc`: add (recommended) or keep
   `julia_internal.h`-only as today?
3. **M2 `min_world` for folded positives** (10 intro): thread `sv`/an out-param at
   `abstractinterpretation.jl:2068` + `update_valid_age!` and extend `jl_subtype_via_membership`
   with the entry's `min_world` — or keep "never fold entry-derived positives" permanently
   (costs `Const(true)` precision for members)? Decide at M2 with the record (§4.4) in hand.
4. **Parametric `@trait X{P}`**: designed for (§1–2) but untested by the gates — add a 3-line
   gate now vs cover it in M5's family tests?
5. **World 0** = image-build sees all entries (§1 comment): confirm no long-lived runtime task
   runs at `world_age == 0` after image restore (none expected; M6 re-checks).
6. `Traits.jl`'s `_open_set!` uses `ccall(:jl_set_open_set, Cvoid, (Any,), T)` — matches §9;
   errors surface as `ErrorException`. No library edit needed.
