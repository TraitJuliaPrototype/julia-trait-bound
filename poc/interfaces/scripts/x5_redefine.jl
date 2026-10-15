# Demo 1 step 5 (writeup/poc3-plan.md §1): a worker of a trait module is
# redefined in the session; only its dependents recompile, and DataFrames'
# and Makie's caches are untouched. Fresh process:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x5_redefine.jl
# A trait-bounded definition evaluated later goes through the trait module's
# own transform (`TraitWorld.@stmt` inside the module), so it replaces the
# worker and keeps the entry.
using SnoopCompileCore, Printf
using TraitWorld, Columns, Stats, Reports, DataFramesWrapper, MakiePlots
using DataFrames, CSV
const SAMPLE = joinpath(@__DIR__, "..", "App", "data", "sample.csv")
df = CSV.read(SAMPLE, DataFrame)
plot_once() = (f = figure(); ax = axis!(f); histbars!(ax, df, 1); scatter!(ax, df, 1, 2); render(f))
summarize(df); zscores(df, 1); plot_once()                      # hot
s0 = summarize(df)[1].std
invs = @snoop_invalidations Core.eval(Reports, :(TraitWorld.@stmt colstd(t::ColTable, i::Int) = (c = col(t, i); m = colmean(t, i); sqrt(sum(abs2, c .- m) / length(c)))))
using SnoopCompile
trees = invalidation_trees(invs)
victims = Dict{Module,Int}()
for tr in trees, root in [tr.backedges; last.(tr.mt_backedges)]
    SnoopCompile.countchildren(root)
    stack = Any[root]
    while !isempty(stack)
        n = pop!(stack)
        n.mi.def isa Method && (victims[Base.moduleroot(n.mi.def.module)] = get(victims, Base.moduleroot(n.mi.def.module), 0) + 1)
        append!(stack, n.children)
    end
end
println("X5 redefining Reports.colstd: ", length(trees), " invalidation tree(s); invalidated instances per package root:")
for (m, n) in sort(collect(victims); by = p -> -p[2])
    println("   ", rpad(string(m), 22), n)
end
s1 = @timed summarize(df)
@printf("   next summarize(df): %.1f ms (%.1f ms compiling, %.1f ms of it recompiling), std changed %s -> %s\n", s1.time * 1e3, s1.compile_time * 1e3, s1.recompile_time * 1e3, round(s0; digits = 4), round(s1.value[1].std; digits = 4))
s2 = @timed zscores(df, 1)
@printf("   next zscores(df, 1): %.1f ms (%.1f ms compiling)\n", s2.time * 1e3, s2.compile_time * 1e3)
s3 = @timed plot_once()
@printf("   next plot: %.1f ms (%.1f ms compiling)\n", s3.time * 1e3, s3.compile_time * 1e3)
