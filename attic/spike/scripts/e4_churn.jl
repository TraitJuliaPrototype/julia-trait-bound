# E3b — bounded invalidation under unrelated churn (M0 gate d — KILL CRITERION).
# Heavy unrelated definition churn must cause zero invalidations of the erased
# workers, and post-churn calls must trigger ~zero (re)compilation.
# Run: julia +1.11.7 --project=. e4_churn.jl
using M0Spike, SnoopCompileCore

struct T1
    cols::ColR
end
t = T1([rand(100) for _ in 1:8])
register_seal!(T1; project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i])
colmean(t, 1); colstd(t, 2); meanall(t)   # workers hot

invs = @snoop_invalidations begin
    # 1) many new types, each with methods on new and existing generic functions
    for k in 1:50
        S = Symbol("ChurnT", k)
        @eval begin
            struct $S
                x::Vector{Float64}
            end
            Base.length(a::$S) = length(a.x)
            Base.getindex(a::$S, i::Int) = a.x[i]
            Base.sum(a::$S) = sum(a.x)
        end
    end
    # 2) new seals arriving (normal trait-universe growth)
    for k in 1:10
        S = Symbol("SealT", k)
        @eval struct $S
            cols::ColR
        end
        T = @eval $S
        register_seal!(T; project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i])
    end
    # 3) redefinition churn on an unrelated function
    for k in 1:20
        @eval churny(x) = x + $k
        Base.invokelatest(churny, 1)
    end
end

using SnoopCompile, MethodAnalysis
trees = invalidation_trees(invs)
println("invalidation trees from churn: ", length(trees))
hits = 0
for tr in trees
    s = sprint(show, tr)
    if occursin("M0Spike", s)
        global hits += 1
        println("!! M0Spike affected: ", first(s, 400))
    end
end
println("trees touching M0Spike: ", hits)

stats = @timed (colmean(t, 1) + colstd(t, 2) + meanall(t))
println("post-churn call: compile ", round(stats.compile_time * 1e3, digits = 2),
        " ms, recompile ", round(stats.recompile_time * 1e3, digits = 2), " ms")
println("worker MethodInstances now: colmean_worker=",
        length(methodinstances(M0Spike.colmean_worker)),
        " colstd_worker=", length(methodinstances(M0Spike.colstd_worker)),
        " meanall_worker=", length(methodinstances(M0Spike.meanall_worker)))
println(hits == 0 ? "RESULT: PASS — zero worker invalidations under unrelated churn" :
                    "RESULT: FAIL — workers invalidated by unrelated churn (kill criterion)")
