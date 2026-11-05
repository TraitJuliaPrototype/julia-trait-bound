# Gate for review finding M4: the four attribute wrapper types must be usable
# (bound as their UnionAll wrappers, printable — the binding bug made `Dynamic{Int}`
# throw "expected UnionAll" and Keyed printing segfault) and the erasure rule
# must hold end-to-end (plan §6, reviews M3/I4).
using Traits
include("util.jl")

# constructible and printable as types
println("wrappers: ", Core.Dynamic{Int}, " ", Core.Compiled{String},
        " ", Core.Kept{Int}, " ", Core.Keyed{Int, Int, Int})
@assert Core.Dynamic{Int} isa Type

@trait X7
struct W7 end
@implement W7 X7

w = W7()
d = Core.Dynamic{X7}(w)
c = Core.Compiled{X7}(w)
k = Core.Kept{X7}(w, false)
@assert (d isa X7) "Dynamic erases to membership of the parameter's set"
@assert (c isa X7) "Compiled likewise"
@assert (k isa X7) "Kept likewise"
@assert !(d isa Union{String, Int}) "erasure does not widen (exact)"
@assert ((x -> x isa X7)(W7()) && !(Int isa X7)) "guards"   # compiled membership visible; Int stays out
@assert !(Int isa X7)

println("m1_wrappers: OK")
