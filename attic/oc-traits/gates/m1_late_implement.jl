# Gate M1-a (plan §5.M1): late @implement — the membership appears in the new
# world, not in an old one. Probe compiled BEFORE the declaration, so the same
# CodeInstance answers both worlds through the runtime check (no recompile).
using Traits
include("util.jl")

@trait X1
struct Late1 end

probe(y) = y isa X1

w_old = curworld()
s = Late1()
@assert !probe(s) "`s isa X1` must be false before the membership"

e = @implement Late1 X1
@assert e isa Core.MembershipEntry
# mutation semantics: the entry is visible from the declaring statement's world;
# top-level statements each open a world, so all we pin is: newer than the read
@assert e.min_world > w_old "entry must become visible after the world was read"
@assert e.max_world == typemax(UInt) "published entries are open-ended"

@assert probe(s) "member in the new world"
@assert !Base.invoke_in_world(w_old, probe, s) "old world sees no entry"
@assert Base.invoke_in_world(curworld(), probe, s) "current world sees the entry"

# a second membership of the same member in a second set: independent entries
@trait X1b
@implement Late1 X1b
@assert probe(s) && (s isa X1b)

println("m1_late_implement: OK")
