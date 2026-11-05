# AC-3 (old G1.7, G1.12): recursion through a marked entry, and recursion with
# growing types: terminates, and the value equals plain Julia's. The G2 bit on
# these frames is recorded, not pinned (D7: conservative-false through cycles).
include("ac_util.jl")
using Traits

# --- G1.7 shape: depth through the set-side method, recursing at the member ----
@trait C3
struct W3
    v::Int
end
@implement W3 C3
cv3(w::C3) = w.v
dp3(w::C3) = cv3(w) <= 0 ? 0 : 1 + dp3(W3(cv3(w) - 1))
pl3(w::W3) = w.v <= 0 ? 0 : 1 + pl3(W3(w.v - 1))
mark!(dp3)
@assert dp3(W3(5)) == 5 == pl3(W3(5)) "G1.7: recursion terminates with plain's value"

# --- G1.12 shape: recursion with growing types (a bigger type each level) ------
nest3(c::Int, x) = c <= 0 ? x : nest3(c - 1, (x,))
nestp(c::Int, x) = c <= 0 ? x : nestp(c - 1, (x,))
mark!(nest3)
@assert nest3(3, 1) === (((1,),),) === nestp(3, 1) "G1.12: growing-type recursion"

# D7 observation (record, do not pin): the G2 bits of the cycle frames
for f in (dp3, nest3)
    for c in all_cis(f)
        println("OBSERVED g2bit(", typeof(f).name.mt.name, ", min=", c.min_world,
                ") = ", (getfield(c, :flags) & 0b00010000) != 0)
    end
end

ac_finish(@__FILE__)
