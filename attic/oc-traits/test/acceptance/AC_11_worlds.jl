# AC-11 (old G1.14): a call in an older world does not see a later membership.
# A marked caller compiled AFTER the declare keeps M2's world bounds on its
# dispatch edges; running it at a pre-declare world raises (no method applies
# there), the latest world answers — identical to the plain twin (M2's machinery
# and the facts edges coexist; the AC is a regression shield).
include("ac_util.jl")
using Traits

@trait S11
f11(::S11) = 2.0
struct L11 end
mk11(x::L11) = f11(x)
pf11(x::L11) = f11(x)
mark!(mk11)

w0 = curworld()
e11 = @implement L11 S11
@assert mk11(L11()) == 2.0 "latest world sees the membership"

o_old = try
    Base.invoke_in_world(w0, mk11, L11())
catch e
    e
end
p_old = try
    Base.invoke_in_world(w0, pf11, L11())
catch e
    e
end
@assert o_old isa MethodError "old world raises MethodError, got $(typeof(o_old))"
@assert p_old isa MethodError "the plain twin raises identically"
@assert mk11(L11()) == pf11(L11()) == 2.0 "G1.14: latest world answers in both modes"

# the marked CI is world-bounded from the declare world up (M2 seam holds with
# the facts record in place)
ci = only([c for c in all_cis(mk11) if c.min_world > 0])
@assert ci.min_world >= e11.min_world "marked CI min_world $(ci.min_world) >= entry min $(e11.min_world)"

ac_finish(@__FILE__)
