# X6 — fingerprint/universe drift on witness edit.
#   julia +1.11.7 --startup-file=no --project=. x6_fingerprint.jl
using ColStats, ColReports, EagerTables, TraitRegions, ColTables

t = EagerTable([[1.0, 2.0, 3.0]])
println("before edit: colmean=", ColStats.colmean(t, 1))
u1 = universe_id()
f1 = fingerprint(TraitRegions.seal_of(ColTable, t))

# interactive-session edit of a witness: re-seal with a changed implementation
delete!(TraitRegions.seal_registry(ColTable), EagerTable)
TraitRegions.register!(ColTable, EagerTable,
    (project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i] .* 10.0))
s = @timed ColStats.colmean(t, 1)
println("after edit:  colmean=", s.value, "  (recompile cost: ",
        round(s.compile_time * 1e3, digits = 2), " ms — witness body only)")
println("fingerprint drifted: ", fingerprint(TraitRegions.seal_of(ColTable, t)) != f1,
        "   universe_id drifted: ", universe_id() != u1)
