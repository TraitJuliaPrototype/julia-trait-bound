# X4 — invalidation immunity at ecosystem scale.
#   julia +1.11.7 --startup-file=no --project=. x4_churn.jl storm   (ChurnStorm)
#   julia +1.11.7 --startup-file=no --project=. x4_churn.jl makie   (using CairoMakie as field churn)
using ColStats, ColReports, PlainStack, EagerTables, TraitRegions, ColTables
using SnoopCompileCore

t = EagerTable([rand(100) for _ in 1:6])
PlainStack.getcol(x::EagerTable, i::Int) = x.cols[i]
PlainStack.ncols_direct(x::EagerTable) = length(x.cols)
report(t); report_dyn(t); report_p(t)   # both stacks hot
u1 = universe_id()

invs = ARGS[1] == "storm" ? (@snoop_invalidations (using ChurnStorm)) :
                            (@snoop_invalidations (using CairoMakie))

using SnoopCompile
trees = invalidation_trees(invs)
ours(tr) = (s = sprint(show, tr); any(m -> occursin(m, s),
            ("ColStats", "ColReports", "ColTables", "TraitRegions", "PlainStack")))
n_ours = count(ours, trees)
s1 = @timed (report(t) + report_dyn(t))
s2 = @timed report_p(t)
println("X4 [", ARGS[1], "] invalidation trees: total=", length(trees), "  touching our stack=", n_ours)
for tr in filter(ours, trees)
    println("  -> ", first(sprint(show, tr), 200))
end
println("   post-churn: region compile ", round((s1.compile_time)*1e3, digits=2),
        " ms | plain compile ", round(s2.compile_time*1e3, digits=2), " ms")
println("   universe_id unchanged: ", universe_id() == u1)
