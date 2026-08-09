# X10 — Rung-2-lite: constructive piracy-immunity via world-pinned (sealed)
# execution, plus blame diagnostics for the unsealed path.
#
# A pirate method on `Base.sort` at the representation's element type lands
# AFTER the universe world is pinned. Ordinary region ops and the plain twin
# see it (behavior changes + recompilation); `sealed` calls provably cannot.
#   julia +1.11.7 --startup-file=no --project=. x10_pirate.jl
using ColStats, ColReports, EagerTables, PlainStack, TraitRegions, ColTables
using SnoopCompileCore, BenchmarkTools, Printf

t = EagerTable([[5.0, 1.0, 4.0, 2.0, 3.0]])   # unsorted on purpose: the median moves if sort lies
PlainStack.getcol(x::EagerTable, i::Int) = x.cols[i]
PlainStack.ncols_direct(x::EagerTable) = length(x.cols)

normal0 = ColStats.summarize(t)
sealed0 = sealed(ColTable, :summarize, t)
plain0  = summarize_p(t)
@assert normal0 == sealed0 == plain0
b_norm = @belapsed ColStats.summarize($t)
b_seal = @belapsed sealed(ColTable, :summarize, $t)
@printf("before pirate: all agree (%.3f). sealed-call overhead: %.0f ns vs %.0f ns normal\n",
        normal0, b_seal * 1e9, b_norm * 1e9)

# ---- the pirate: defined after the last registration event ------------------
invs = @snoop_invalidations @eval Base.sort(v::Vector{Float64}) = v   # lies: returns unsorted

s_norm  = @timed ColStats.summarize(t)
s_seal  = @timed sealed(ColTable, :summarize, t)
s_plain = @timed summarize_p(t)

@printf("normal region op:  %.3f  (changed: %s, recompile %.1f ms)\n",
        s_norm.value, s_norm.value != normal0, (s_norm.compile_time + s_norm.recompile_time) * 1e3)
@printf("plain twin:        %.3f  (changed: %s, recompile %.1f ms)\n",
        s_plain.value, s_plain.value != plain0, (s_plain.compile_time + s_plain.recompile_time) * 1e3)
@printf("SEALED region op:  %.3f  (changed: %s, recompile %.1f ms)\n",
        s_seal.value, s_seal.value != sealed0, (s_seal.compile_time + s_seal.recompile_time) * 1e3)

# ---- blame: the invalidation report names the pirate ------------------------
using SnoopCompile
trees = invalidation_trees(invs)
println("\nblame report (unsealed path):")
for tr in trees
    n = 0
    victims = Set{Module}()
    for root in tr.backedges
        n += SnoopCompile.countchildren(root)
        foreach(c -> c.mi.def isa Method && push!(victims, c.mi.def.module), root.children)
    end
    for (_, root) in tr.mt_backedges
        n += SnoopCompile.countchildren(root)
        foreach(c -> c.mi.def isa Method && push!(victims, c.mi.def.module), root.children)
    end
    println("  pirate `", tr.method, "`\n    killed ", n, " CodeInstances; directly hit modules: ",
            join(string.(collect(victims)), ", "))
end
println("\nverdict: ", s_seal.value == sealed0 && s_norm.value != normal0 ?
        "PASS — pirate applies in the live world, PROVABLY not inside sealed execution" :
        "UNEXPECTED — inspect")
