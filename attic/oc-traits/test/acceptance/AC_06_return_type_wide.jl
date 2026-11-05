# AC-6 (old G1.11): `return_type` at signatures a method's compilation
# signature widens (`@nospecialize`, function arguments, long Vararg splats,
# broadcast over the function itself) — marked code == plain (the gate admits
# none of these as facts; the answers stay plain's).
include("ac_util.jl")

ns6(@nospecialize x) = x
passf6(f) = f
pass6(t) = t
vaa6(xs...) = xs

kw6() = (Base.promote_op(ns6, Int), Base.promote_op(passf6, typeof(sin)),
         Base.promote_op(vaa6, ntuple(_ -> Int, 10)...), typeof(ns6.(Int[])))
kwp() = (Base.promote_op(ns6, Int), Base.promote_op(passf6, typeof(sin)),
         Base.promote_op(vaa6, ntuple(_ -> Int, 10)...), typeof(ns6.(Int[])))
mark!(kw6)

pw = kwp()
qw = kw6()
@assert pw == qw "G1.11: widened compilation signatures answer identically: plain $pw, policy $qw"

ac_finish(@__FILE__)
