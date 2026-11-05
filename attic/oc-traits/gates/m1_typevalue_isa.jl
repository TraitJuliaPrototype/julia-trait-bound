# Gate M1-d (plan §5.M1, review L10): a type *value* answers `isa` against an
# open set through the Type{S} entry — jl_isa's datatype-type branch,
# obviously_disjoint and the intersection datatype case stay exact.
using Traits
include("util.jl")

@trait X4
struct Late4 end
struct Late4b end

vprobe(y) = y isa X4                  # defined early: callable in both worlds

w_old = curworld()
@assert !(Late4 isa X4) "type value not a member before the declaration"
@assert !isa(Late4, X4)
@assert !(Int isa X4) "never a member"

@implement Late4 X4

@assert (Late4 isa X4) "Type{Late4} answers through the entry"
@assert isa(Late4, X4)
@assert !(Late4b isa X4) "non-member stays a non-member, exactly"
@assert !(Int isa X4)
@assert !Base.invoke_in_world(w_old, vprobe, Late4) "old world: false"  # early-defined probe: a closure made here is too new for w_old

# exactness (review H2): the set and a non-member simply do not intersect —
# a value of Late4b is never `isa X4`, and no union absorbs it by accident
@assert !(Late4b() isa X4) && !(1 isa X4)

println("m1_typevalue_isa: OK")
