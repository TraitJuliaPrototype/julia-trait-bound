# Gate scripts

Run against the in-tree build (plan §5):

    cd julia-oc && ../oc-traits/../.. ; # from the repo root:
    julia-oc/julia --startup-file=no --project=oc-traits oc-traits/gates/m1_late_implement.jl

Scripts print `<name>: OK` on success and assert otherwise. The M-number in the
file name is the milestone whose gate it belongs to:

- `m1_late_implement.jl`  — late membership appears only in newer worlds
- `m1_compiled_isa.jl`    — code compiled before the membership answers both
  worlds (isa, subtype, tuple-parameter, typeassert forms; review H3)
- `m1_worlds_minworld.jl` — positive folds carry the entry's `min_world`
  (review M6)
- `m1_typevalue_isa.jl`   — the type *value* `S` answers `isa X` through the
  `Type{S}` entry; non-members stay exact (reviews L10, H2)
- `m1_parametric_set.jl`  — `@trait X{P}` and the bare-name membership (member
  of every instance); narrow declarations are narrow (open question 4)
- `m1_open_family_fold.jl` — B1: same-open-family parameter negatives must not
  fold to permanent `Const(false)`; compiled calls agree with runtime truth
- `m1_late_open_stale.jl`  — B2: types interned before a set opens must see the
  membership anyway (memoized `has_open_set` invalidation)
- `m1_parametric_member.jl` — M1: parametric `@implement Mem{T} Set{T}` binds
  narrow (pattern/instance tvar sharing), not family-wide
- `m1_union_isa.jl`        — M3: type value `S isa Union{X, ...}` answers
  through union arms; isa ≡ dispatch
- `m1_wrappers.jl`         — M4: Keyed/Dynamic/Compiled/Kept constructible and
  printable; x-side erasure end-to-end
- `util.jl`               — CI walker (`Base.specializations` + `ci.next`)
