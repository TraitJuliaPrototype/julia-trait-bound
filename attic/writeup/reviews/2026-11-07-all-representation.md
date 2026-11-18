# Review: `All{X, Y, …}` as an abstract DataType

**Date:** 2026-11-07. **Reviewer:** an independent critical review (Fable 5.1, in a subagent; the no-subagents rule for this host was set aside by the caller for this task). Not edited after writing, except by a dated addendum.

## What was reviewed

- Commit `04327f3912` on `julia-unified`, branch `w107-probe`: `Core.All{T<:Tuple}` in `base/boot.jl`; `jl_type_all` (`src/jltypes.c:654-733`); the `apply_type` special case (`src/builtins.c:1645-1648`); `subtype_all_right`, `subtype_all_left` and the fast-path guards (`src/subtype.c:553-554, 2043-2073, 2181-2184, 2208-2213, 2645-2647`); `jl_is_all_type` (`src/julia_internal.h`); `show_datatype` (`base/show.jl`).
- The design: `writeup/reference/compiler.md` §4.4, §4.7, §4.8, §4.9; `writeup/reference/traits.md` §3.6.
- The gate `experiments/unification/gates/n2_all_probe.jl` (passes) and the untracked `n2_all_dispatch.jl` (fails at its first intersection assertion, as planned).
- Experiments: short Julia scripts on the built tree (`julia-unified/julia`, 1.13.2 at `04327f3912`), with and without `--project=experiments/unification`. Their outputs are quoted below. The scripts live in the session's scratchpad; the gate additions in §6 reproduce them.

Line numbers are those of the worktree at `04327f3912`.

## Summary

The DataType form is sound where the commit special-cases it, and wrong wherever it does not. The commit's premise is "everything that does not special-case it sees an ordinary abstract type, so the change stays small." That is the hazard, not the benefit. An ordinary abstract type has one supertype chain, invariant parameters and a wrapper that every instance is a subtype of. `All{Tuple{X, Y}}` has none of these properties, and the runtime reads them as if it did. Verified consequences, all on the current build:

- A method at a closed `All` is unreachable once its typemap level splits by typename; an `All` as a query type finds no method at a closed type. Inference turns `length(x)` under `x isa All{…}` into a thrown `MethodError`, and the compiled code throws it at run time (finding 1).
- A negative `isa` against an `All` is folded, and the compiled code stays wrong after the membership that makes it true (finding 2).
- The diagonal rule does not see a variable inside `All`; a method matches and then fails with `UndefVarError: T` (finding 3).
- Instantiating `All{T, X} where T` makes a second object for one type, or throws (finding 4).
- `name.wrapper{parameters...}` and `Serialization` turn `All{X, Y}` into `Tuple{X, Y}` (finding 5).

None of these need traits to show; most show with closed components. None is deep. Each is one `jl_is_all_type` branch at a site that reads `name`, `super`, `parameters` or `wrapper`. A new kind would fail at the same sites with "unknown shape" instead of a confident wrong answer, but at a much larger cost (§5). **Verdict: keep the DataType form, on the condition that the encoding is declared as such in the reference and the sites listed in §5 get their branch before W-107's next step builds on this one.** The passing gate tests `<:` on top-level types in a fresh session only; it would not have caught any finding here. §6 lists the gate additions.

## Findings

### 1. The typemap trusts the supertype chain; `All` has none — blocker

The typemap keys non-leaf arguments by typename and finds them by walking the query's `super` chain. `All`'s chain is `All → Any`; no value's chain contains `All`.

- Insert side. `jl_typemap_level_insert_` (`src/typemap.c:1443-1458`) routes a signature to the linear list only when `jl_has_open_set(sig)`. A closed `All` has no open set, so it goes into `name1[All]` once the level splits (`MAX_METHLIST_COUNT` is 6, `src/typemap.c:12`). Evidence, 17 methods `f(::Int, ::T)` and `f(::Int, ::C)` with `C = All{AbstractArray{Int}, AbstractVector}`:
  ```
  Vector{Int} <: C = true
  f(1, Int[]) = MethodError
  Base.hasmethod(f, (Int, Vector{Int})) = false
  ```
  With open components the open bit routes the method to the linear list and the same test passes (`g(1, Int[]) = :all` before and after the split). So the hole is for closed `All`s; finding 9 makes those rare, not absent.
- Query side. `jl_type_extract_name` returns `All`'s typename and `jl_type_extract_name_precise` says it is precise for a non-abstract name, otherwise the scan uses `tname_intersection_dt` (`src/typemap.c:30-100, 399-416`), which walks `super`. Both miss every method keyed by a closed typename. Evidence:
  ```
  methods(length, (C,)) = # 0 methods
  h(@nospecialize(x::AbstractArray{Int})) = x isa C ? length(x) : -1
  Base.infer_return_type(h, (AbstractArray{Int},)) = Int64
  h(Int[1,2,3]) → ERROR: MethodError: no method matching length(::Vector{Int64})
                   This error has been manually thrown, explicitly, ...
  ```
  `tmeet(AbstractArray{Int}, C)` is `C` (by the subtype shortcut, `C <: AbstractArray{Int}` through the left rule), inference finds no `length(::C)`, and the branch becomes a throw. The value is a `Vector{Int}`.
- The same query-side hole exists for a set as the query type, outside this commit: with `Vector{Int}` a member of `PX` and the table split, `typeintersect(PX, Vector{Int}) = Vector{Int}` but `methods(f, (Int, PX))` is empty. §4.4's "`<:`, `isa`, intersection and dispatch read the same relation" does not hold at a split level for sets either.

Proposal:
- Insert: route an argument that is an `All` (at any depth, as `jl_has_open_set` is at any depth) to the linear list. Cheapest: a `has_all` bit beside `has_open_set` on `jl_datatype_t`, computed the same way; or make the routing test `jl_has_open_set(sig) || jl_has_all_type(sig)`.
- Query: in `jl_type_extract_name` return `NULL` for an `All`, so the level scans; in `tname_intersection` (both the typevar and the datatype arms) answer 1 for an `All`, or test each component. For a set as the query type, `tname_intersection_dt` needs the membership answer (`membership_may_reach` or a conservative 1 when the set is open); that is a stack fix, but the two should land together, since the `All` fix is pointless while the set fix is missing.

### 2. The negative-fold gate does not see through `All` — blocker

`jl_could_join(S, X)` (`src/subtype.c:1630-1675`) decides by `xud->name->open_set`. `All`'s typename is closed and its name differs from `S`'s, so the answer is 0: "no future declaration can make `S <: All{PX, PY}`." `isa_tfunc` (`Compiler/src/tfuncs.jl:886-910`) and `tmeet` then fold the negative. Evidence:
```
@implement PX SX
q(x::SX) = x isa A              # A = All{PX, PY}
q(SX()) = false                  # code: Any[:(return false)]
@implement PY SX
(SX() isa A, SX <: A) = (true, true)
q(SX()) = false                  # the compiled code; a fresh inference gives :(_2 isa Main.A)
```
This breaks §4.8's guarantee ("a negative answer is never folded for an open set") for every intersection with an open component. `jl_subtype_via_membership` (the positive gate) keys on the same bit; by its shape it answers 0 for an `All` on the right, which folds a positive that came through entries (reasoning from the code, not run). That matters once W-100 ties positive folds to `min_world`.

Proposal: in `jl_could_join`, before the head rule: if `X` is an `All`, return 1 when every component `Xi` satisfies `jl_subtype(S, Xi) || jl_could_join(S, Xi)`; if `S` is an `All`, return 1 when any component could join `X`. In `jl_subtype_via_membership`, if `X` is an `All`, return 1 when any component's answer came through an entry. Add the stale-fold script to the gate.

### 3. The diagonal rule does not see a variable inside `All` — high

`subtype_unionall` decides `diagonal` syntactically: `vb.occurs_cov > 1 && !var_occurs_invariant(u->body, u->var)` (`src/subtype.c:1026`). `var_occurs_inside` (`src/subtype.c:3599-3630`) counts a parameter of any non-`Tuple` DataType as invariant (`ins_i = inside || !want_inv || !istuple`). `always_occurs_cov` (`src/subtype.c:4151-4180`) does the same. The subtype rules treat the components as covariant (they pass `param` through), so the bookkeeping and the rules disagree. Evidence:
```
Tuple{Int, Float64} <: (Tuple{T, T} where T)                 = false
Tuple{Int, Float64} <: (Tuple{Union{T, String}, T} where T)  = false
Tuple{Int, Float64} <: (Tuple{All{T, Real}, T} where T)      = true
f(::All{T, Real}, ::T) where T = T
f(1, 2.0) → UndefVarError: `T` not defined in static parameter matching
```
The method matches, `envout` gets `TypeVar(T, Union{}, Union{Int, Float64})` because the bound is not a leaf and the variable is counted as not invariant, and the call fails. The intersection side has the same walkers (`intersect_unionall`, line 4109 and 4192), so method ordering and ambiguity inherit it.

Proposal: teach `var_occurs_inside`, `always_occurs_cov` and `var_occurs_invariant` that an `All`'s `Tuple` parameter is a covariant position (recurse into its components with the enclosing `inside`/`param`). Then state in §4.9 how a variable as a component reads: `All{T, X}` is covariant in `T`, and the diagonal rule applies. The alternative, refusing a bare typevar as a component, closes the hole at no cost in expressiveness that the ports have asked for.

### 4. Instantiation bypasses the normal form — high

`inst_type_w_` re-normalizes a `Union` after substitution (`src/jltypes.c:2760-2790`, `jl_type_union`) and a `Vararg`; an `All` is a DataType and goes through `inst_datatype_inner` (`src/jltypes.c:2187`) and the type cache. `jl_apply_type` from C (`src/jltypes.c:1503-1512`) takes the wrapper fast path and never calls `jl_type_all` either. Evidence:
```
(All{T, Integer} where T){Integer}  = All{Integer, Integer}     (=== Integer: false)
(All{T, PX} where T){PX}            = All{PX, PX}               (jl_types_equal with PX: 0)
(All{T, PY} where T){PX}            = All{PY, PX}               (=== All{PX, PY}: false; jl_types_equal: 0)
(All{T, Integer} where T){Union{}}  → ERROR: Tuple field type cannot be Union{}
```
Consequences: two objects per type (the rule "one type object per expression" fails), cached forever under `All`'s typename; `jl_types_equal` false through `obviously_unequal` (different typenames), so two methods at `Vector{All{PX, PY}}` and `Vector{(All{T, PY} where T){PX}}` are "unordered" rather than equal; and a thrown error where `Union{}` is the answer. Instantiation at `Union{}` is routine (intersection environments, `jl_instantiate_unionall` in inference), so the error is reachable without anyone writing `All{Union{}}`.

Proposal: in `inst_type_w_`'s datatype path, when `tn` is `All`'s typename: instantiate the components (the `Tuple` parameter's parameters) and return `jl_type_all` of them, with the `nothrow` discipline the `Union` branch has (a `Union{}` or non-type component under `nothrow` gives `NULL`/`Union{}`, not an error). Route `jl_apply_type`'s wrapper fast path for `All` through the same function. Then the cache never sees an unnormalized `All`.

### 5. The parameter is not a parameter: `wrapper{parameters...}` gives a `Tuple` — high

`jl_f_apply_type` (`src/builtins.c:1645-1648`) makes `Core.All{P}` mean "the intersection of `{P}`", which `jl_type_all` returns as `P`. So the normal form `Core.All{Tuple{X, Y}}` cannot be written, and every reflection path that rebuilds a DataType from `name.wrapper` and `parameters` gets a `Tuple`. Evidence:
```
Core.All{Tuple{Int, String}}            = Tuple{Int64, String}
C.name.wrapper{C.parameters...}         = Tuple{AbstractArray{Int64}, AbstractVector}
deserialize(serialize(C))               = Tuple{AbstractArray{Int64}, AbstractVector}
C <: Core.All                            = false
```
`Serialization` (`stdlib/Serialization/src/Serialization.jl:1539`, `ty = tname.wrapper` then applied to the parameters) is used by `Distributed`; the round trip silently changes the type. `C <: Core.All` false breaks the invariant that every instance of a typename is a subtype of its wrapper; `typejoin` (`base/promotion.jl:101`) and `limit_type_size` (`Compiler/src/typelimits.jl:179-186`) survive it only because both fall back to `Any` when the test fails (verified: `typejoin(C, All{AbstractArray{Int}, AbstractMatrix}) = Any`; `limit_type_size(t, c, c, 1, 3) = Any`).

Proposal: make the written one-argument form with a `Tuple` type the normal form itself: `jl_f_apply_type(Core.All, Tuple{X, Y})` calls `jl_type_all` on `X, Y`. A one-argument form with a non-`Tuple` stays "the intersection of one", which is itself. Then `wrapper{parameters...}`, `Serialization` and `show` round-trip. For the wrapper: in `subtype_all_right`, when the parameter is a bare typevar and `x` is an `All`, fall through to the ordinary same-name invariant-parameter rule, so `All{Tuple{X, Y}} <: (All{T} where T <: Tuple)` holds; keep 0 for a non-`All` `x`. State in §4.9 that `Core.All` (the wrapper) is an encoding artefact, not a type to write.

### 6. The left rule's local backtracking is incomplete — high

`subtype_all_left` (`src/subtype.c:2058-2073`) picks the component inside the walk: try one, `restore_env`, try the next, commit on the first local success. A failure later in the same walk cannot return to the choice. The outer `exists_subtype` loop (`src/subtype.c:2491-2513`) re-enumerates only the decisions recorded in `Runions`, and this choice is not one. Evidence, with `QX ⊂ QY{Float64}` by a set-in-set entry and `V ⊂ QY{Int}`:
```
B = All{V, QX}                      (V sorts first: a singleton)
(B <: QY{Float64}, B <: QY{Int}) = (true, true)
Tuple{B, Int} <: (Tuple{QY{T}, T} where T)      = true     (via V)
Tuple{B, Float64} <: (Tuple{QY{T}, T} where T)  = false    (true via QX; V binds T = Int first)
```
The answer is never a wrong "true" (each try is a full proof), so this is incompleteness, not unsoundness. Dispatch reads "not a subtype" as "no match", and `jl_type_morespecific` reads it as an order, so it can drop a match or misorder two methods at abstract queries. The right rule (each component in one environment, like tuple parameters) is correct as written.

Proposal: make the component choice a `Runions` decision. Replace the loop by a chain of `pick_union_decision(e, 1)` over the components, as `pick_union_element` (`src/subtype.c:199-207`) does for a `Union` on the right, and let `subtype` continue with the chosen component. The outer loop then enumerates it with full backtracking, and `local_forall_exists_subtype`'s push/pop of the union state covers invariant positions. Keep `restore_env` out of it.

### 7. `Union`'s normal form reads memberships — high, adjacent

§4.9 states: "A membership never absorbs a component of an `All` or a `Union`: `Union{S, X}` stays as written where `S` is a member of `X` by an entry. So a type expression gives the same type object in every world." `jl_type_all` honours this (its absorption skips any pair with an open set). `jl_type_union` does not: `simple_subtype` (`src/jltypes.c:566-580`) calls `jl_subtype`, which reads entries. Evidence:
```
u1 = Union{S2, PZ}      # before @implement PZ S2
u2 = Union{S2, PZ}      # after
(u1, u2, u1 === u2) = (Union{S2, PZ}, PZ, false)
```
Not this commit's code, but the commit's claim ("sorted as Union sorts"; "a type expression gives the same type in every world") rests on the stated rule. A signature `f(::Union{S2, PZ})` is a different type object depending on when it is evaluated, `Vector{Union{S2, PZ}}` and `Vector{PZ}` differ by invariance, and a type built at precompile time differs from the same expression evaluated after load.

Proposal: in `jl_type_union`'s absorption (`simple_subtype`, the `hasfree == 0` arm), skip a pair where either side has an open set, exactly as `jl_type_all` does. Add the test to the gate. Record the deviation in compiler.md until fixed.

### 8. `typeintersect` on an `All` is confidently wrong today — medium

This is W-107's next step by plan. The point for the representation: the DataType default is not "unknown" but `Union{}`. `intersect` (`src/subtype.c:5007-5072`) intersects the `Tuple` parameter invariantly for two `All`s and walks chains otherwise; only the subtype shortcut in `intersect_types` (`src/subtype.c:5211-5230`) gives right answers. Evidence:
```
typeintersect(All{PX, PY}, PX)            = All{PX, PY}     (shortcut)
typeintersect(All{PX, PY}, All{PX, PZ})   = Union{}         (should be All{PX, PY, PZ})
typeintersect(PX, PY)                     = Union{}         (should be All{PX, PY})
```
`tmeet` then narrows to `Bottom` and `ml_matches` sees disjoint signatures. With finding 2 fixed, the fold gates block the worst of it; without the `intersect` branches nothing else on this form can be tested. Build them before the dispatch gate, not after.

### 9. Two closed components with an exact intersection keep two names for one set — medium

`C = All{AbstractArray{Int}, AbstractVector}` denotes the values of `AbstractVector{Int}`. Evidence:
```
AbstractVector{Int} <: C = true
C <: AbstractVector{Int} = false
morespecific(Tuple{C}, Tuple{AbstractVector{Int}}), morespecific(Tuple{AbstractVector{Int}}, Tuple{C}) = (false, true)
```
Two methods at these two types are ordered, not equal. Such closed `All`s are also the ones finding 1's insert side bites.

Proposal: extend the normal form. For two closed components `x, y` (no open set, no free variables), let `r = jl_type_intersection(x, y)`; if `r <: x` and `r <: y`, `r` is exactly the intersection (Julia's result is always a supertype of it), so replace both by `r`. "Nothing in common gives `Union{}`" is the special case `r = Union{}`. A closed `All` then survives only where Julia's intersection is inexact.

### 10. `Union` components are invisible to union splitting; `UnionAll` components are not flattened — medium

`jl_type_all` accepts a `Union` as a component and keeps it inside the DataType. The Compiler's union splitting (`switchtupleunion`, `uniontypes`), `typesubtract`, `Conditional` refinement and `ml_matches`' union handling see no union. `jl_is_all_type` does not look through a `UnionAll`, so `All{(All{T, PX} where T), PY}` is not flattened (reasoning, not run). §4.9 is silent on both.

Proposal: distribute in the normal form: `All{Union{A, B}, Y}` becomes `Union{All{A, Y}, All{B, Y}}` (the union-length limits apply), so unions stay on the outside where Julia's machinery is; and flatten through a `UnionAll` component by rewrapping (`All{(All{T, X} where T), Y}` becomes `All{T, X, Y} where T`), or refuse it.

### 11. `jl_type_all` reads the parameter of a non-normal `All` as a `Tuple` — low

The flatten loop (`src/jltypes.c:668`) calls `jl_nparams(jl_tparam0(t))` for any `jl_is_all_type(t)`. The wrapper's body has a typevar there. Evidence: `Core.All{Int, Core.All.body}` dumps core in `jl_type_all`. Proposal: make `jl_is_all_type` require a `Tuple` type as the parameter, or type-error on anything else at the top of `jl_type_all`; `subtype_all_*` already guard it.

### 12. Reflection and the Compiler see an ordinary abstract type — low

`supertype(C)` is `Any`; `fieldcount(C)` throws (abstract); `typejoin` and `limit_type_size` give `Any` (sound, imprecise, and only through the wrapper test of finding 5); `tmerge` gives `Union{…}` of `All`s; `isType`, `widenconst`, `has_free_typevars` are right; `instanceof_tfunc` on `All{Type{X}, PX}` is imprecise. The fields a contract declares (§6, §7) need their own hook on an `All` whatever the representation. Nothing to fix now; note that fixing finding 5 makes `typejoin(C1, C2)` return `Core.All` (the wrapper), which is sound as a lattice element and meaningless as a type, and that `tmerge` then widens it to `Any`.

## The questions asked

1. **Sound for the design's rules?** World-independent normal form: yes for `All` (the absorption skips open sets; closed-closed subtyping and intersection never read entries), no for `Union` (finding 7). One type object per expression: no (finding 4; the C-level `jl_apply_type` and `intersect`'s same-name branch build through the cache too). `All` on either side of `<:`: the rules hold as stated; the left rule is incomplete (finding 6) and the diagonal rule is bypassed (finding 3). Inside `Union`, `UnionAll`, `Vararg`, invariant parameters: as the gate shows, for one object; two objects (finding 4) are equal by mutual subtyping in invariant positions but not by `===` or `jl_types_equal`. Paths that build an unnormalized `All{Tuple{…}}`: `inst_type_w_`/`inst_datatype_inner` for every substitution (`jl_instantiate_unionall`, `jl_instantiate_type_in_env`, `jl_rewrap_unionall`, `jl_substitute_var`), `jl_apply_type` from C, `intersect`'s same-name branch. Deserialization (staticdata) and `typejoin`/`tmerge` do not build one.
2. **The Compiler.** `typeintersect` wrong (finding 8), so `tmeet` narrows to `Bottom` with the fold gate blind (finding 2). `limit_type_size`, `typejoin`, `tmerge`: sound and imprecise (finding 12). Union splitting: blind (finding 10). `fieldcount`: abstract, so `getfield` is `Any`.
3. **The left rule and the union state.** No wrong "true". Wrong "false" when the first component that succeeds locally binds a variable the rest of the walk cannot keep (finding 6). The `Lunions`/`Runions` positions consumed by a failed try are not rewound by `restore_env`; the next try reads fresh positions, which is consistent, only wasteful. A left `Union` inside a component is enumerated by the outer loop and distributes correctly over the local choice.
4. **A kind instead.** See §5.
5. **Else.** Finding 1's query side and finding 7 are holes in the stack that this commit inherits and that its claims rest on.

## 5. A kind, or this form with branches

Findings 1, 2, 3, 5 and 9 share one cause: code that reads `name`, `super`, `parameters` or `wrapper` of an ordinary DataType and gets a confident wrong answer. A new kind (`jl_alltype_t`) would reach the same sites and fall into their "unknown shape" arm: `jl_type_extract_name` returns `NULL` (a scan), `jl_could_join` returns 1 (no fold), `var_occurs_inside` needs a branch either way, `typejoin` gives `Any`, `Serialization` has no wrapper to misuse. Sound by default, imprecise by default. Its cost: a type tag and GC layout, `jl_init_types` and the bootstrap, `jl_egal`/`type_object_id`/`typekey` for the type cache, staticdata's tags and relocation, `jl_is_type`/`jl_is_kind` and every `switch` on kinds in `jltypes.c`/`subtype.c`, codegen's type tests, `Serialization`, and the many `isa(t, DataType)`/`isa(t, Union)`/`isa(t, UnionAll)` chains in the Compiler and Base (not counted) that would be sound without a branch and precise only with one. That is weeks, against days for the list below, and it buys default soundness at sites not yet known.

A middle option, flagging `All`'s `TypeName` `open_set`, routes an `All` through every set hook the stack has (typemap linear list, `jl_could_join` conservative, the fold gates, the match-world range). It plugs findings 1 (insert side) and 2 at once, costs negative folds on closed `All`s (rare after finding 9), and still needs the query-side branch (finding 1), the diagonal branch (finding 3), the normalization branch (finding 4) and the encoding fix (finding 5). It also makes `type_morespecific_`'s open-vs-closed rules (`src/subtype.c:6266-6268`) read an `All` as a set, which §5.2 does not want. Use it only as a stopgap if the stage must land before the branches.

**Verdict: keep the DataType form, with these conditions.**

1. The reference states the encoding: `Core.All{Tuple{X, Y}}` is the normal form and is writable (finding 5); `Core.All` the wrapper is an artefact; a variable as a component is covariant and subject to the diagonal rule (finding 3); `Union` components distribute, `UnionAll` components flatten (finding 10); two closed components with an exact intersection are replaced by it (finding 9). No code may read an `All`'s `name`, `super` or `parameters` as those of an ordinary type. Mark it in §4.9 and in the glossary.
2. Explicit `jl_is_all_type` branches, in this order: `jl_could_join` and `jl_subtype_via_membership` (2); the typemap's insert routing, `jl_type_extract_name` and `tname_intersection`, together with the set fix on the query side (1); `inst_type_w_` and `jl_apply_type` (4); `jl_f_apply_type` and `subtype_all_right`'s typevar case (5); `var_occurs_inside`, `always_occurs_cov` (3); `subtype_all_left` on the union state (6); `jl_type_union`'s absorption (7); the normal form's closed-closed rule (9) and the `Tuple` guard (11); then `intersect` (8).
3. The gates below, before the dispatch gate is attempted.

## 6. Gate additions

For `n2_all_probe.jl` or a new `n2_all_form.jl`, each a one-line assertion from the evidence above:
- `(All{T, PX} where T){PX} === PX`; `(All{T, PY} where T){PX} === All{PX, PY}`; `(All{T, Integer} where T){Union{}} === Union{}`.
- `Core.All{Tuple{PX, PY}} === All{PX, PY}`; `C.name.wrapper{C.parameters...} === C`; `deserialize(serialize(C)) === C`; `C <: Core.All`.
- Seventeen methods at closed types plus one at `C`: the concrete call resolves; `methods(length, (C,))` is non-empty; `h` above returns `3`.
- `q(SX())` is `true` after `@implement PY SX`.
- `Tuple{Int, Float64} <: (Tuple{All{T, Real}, T} where T)` is `false`; `f(::All{T, Real}, ::T) where T` raises `MethodError`, not `UndefVarError`.
- `Tuple{All{V, QX}, Float64} <: (Tuple{QY{T}, T} where T)` is `true`.
- `Union{S2, PZ}` is the same object before and after `@implement PZ S2`.
- `Core.All{Int, Core.All.body}` raises a `TypeError`, not a crash.
- `All{AbstractArray{Int}, AbstractVector} === AbstractVector{Int}` (finding 9, once adopted).

## Addendum (2026-11-07): what was done with each finding

The main session built each proposal on branch `w107-probe` 5a161a28a4 (rebased onto `unified` ec4f9a8714), outside the stack until W-107 is done. The gate additions of §6 are `experiments/unification/gates/n2_all_form.jl`; intersection and dispatch are `n2_all_dispatch.jl`.

| Finding | Done | Where |
|---|---|---|
| 1. The typemap and the supertype chain | The insert routing, `jl_type_extract_name` and `tname_intersection` treat an intersection, and on the query side an open set, as meeting any name. The query side for sets is on the stack. The gate's `methods(length, (C,))` found a further hole, also for one set: on the stack a set and an abstract type met as `Union{}`. They now meet as `All{X, T}`. | `w107-probe` 5a161a28a4; `unified` ec4f9a8714 (gate `m2_set_query_split`); compiler §4.7, §5.3, C-33, gate `n2_open_abstract` |
| 2. The fold gates | `has_open_set` is set for an intersection; `jl_could_join` and `jl_subtype_via_membership` see through it. | `w107-probe`; gate `n2_all_form` (`q`) |
| 3. The diagonal rule | `var_occurs_inside` and `always_occurs_cov` walk an intersection's components as covariant. | `w107-probe`; gate `n2_all_form` |
| 4. Instantiation | `inst_type_w_` rebuilds an intersection through `jl_type_all`; `jl_apply_type` normalizes. | `w107-probe`; gate `n2_all_form` |
| 5. The parameter | `apply_type` takes `Core.All{Tuple{X, Y}}` as the components; the wrapper and serialization round-trip. | `w107-probe`; gate `n2_all_form` |
| 6. The left rule's backtracking | `subtype_all_left` chooses its component as a union's member is chosen. | `w107-probe`; gate `n2_all_form` |
| 7. `Union`'s normal form | `jl_type_union`'s absorption reads declared supertypes only. | `unified` ec4f9a8714; gate `m2_union_normal_form` |
| 8. Intersection | A type meets an intersection as the intersection of its meets with each component; two sets that no entry relates meet as `All{X, Y}`. | `w107-probe`; gate `n2_all_dispatch` |
| 9. Two closed components | Replaced by Julia's intersection where it is exact. | `w107-probe`; gate `n2_all_form` |
| 10. `Union` and `UnionAll` components | A `Union` component distributes. A component that is an intersection under a `UnionAll` is not flattened yet. | `w107-probe`; gate `n2_all_form`; C-34 |
| 11. The `Tuple` guard | A non-`Tuple` parameter raises `TypeError`. | `w107-probe`; gate `n2_all_form` |
| 12. Reflection | Nothing, as proposed. | — |

Question 1's glossary entry waits for the glossary's rewrite (W-115). The encoding is in compiler §4.9.
