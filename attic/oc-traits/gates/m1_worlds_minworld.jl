# Gate M1-c (plan §5.M1, review M6's test): a positive folded through an entry
# must raise the CodeInstance's min_world to the entry's, so an old world can
# never run code that assumes a membership it cannot see.
using Traits
include("util.jl")

@trait X3
struct Late3 end

probe_early(y) = y isa X3             # compiles before the entry: no fold possible

w_before = curworld()
e = @implement Late3 X3
@assert e.min_world >= w_before + 1 "the declaring world must be above any world seen before (single-bump protocol)"

probe_late(y) = y isa X3              # compiles after: a positive fold is allowed

x = Late3()
@assert probe_early(x) && probe_late(x)

# behavior: no old world sees the membership
@assert !Base.invoke_in_world(w_before, isa, x, X3)
@assert !Base.invoke_in_world(w_before, probe_early, x)
try   # probe_late is invalid in the old world: its method is not reachable there
    Base.invoke_in_world(w_before, probe_late, x)
    error("probe_late must not be callable in the old world")
catch err
    err isa MethodError || rethrow()
end

# bookkeeping: every cached CI of the late probe is either from before the
# entry (then it never folded — it could not) or bounded at/above the entry
for ci in all_cis(probe_late)
    @assert ci.min_world > w_before ? ci.min_world >= e.min_world : true
end
@assert any(ci -> ci.min_world <= w_before, all_cis(probe_early)) "early CI predates the entry"

println("m1_worlds_minworld: OK")
