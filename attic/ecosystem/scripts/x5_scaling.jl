# X5 + X2 — worker instances scale with #representations, not #types; and
# workers arrive precompiled from pkgimages.
#   julia +1.11.7 --startup-file=no --project=. x5_scaling.jl
using ColStats, ColReports, EagerTables, LazyTables, MatrixTables, TraitRegions, ColTables

# X2 evidence: BEFORE any call, worker specializations exist and are cached
# (they came from ColStats'/MatrixTables' pkgimages, not this session)
for f in (ColStats.var"colmean#worker", ColStats.var"summarize#worker")
    mis = collect(Base.specializations(first(methods(f))))
    pre = [(mi.specTypes.parameters[3], isdefined(mi, :cache)) for mi in mis]
    println("X2 ", f, ": ", pre)
end

# now use every conformer + 10 extra user types on the canonical rep
for k in 1:10
    S = Symbol("User", k)
    @eval struct $S
        cols::Vector{Vector{Float64}}
    end
    T = @eval $S
    TraitRegions.register!(ColTable, T,
        (project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
end
te = EagerTable([rand(50) for _ in 1:4])
tl = LazyTable(rand(50), 4)
tm = MatTable(rand(50, 4))
for t in (te, tl, tm)
    report(t); report_dyn(t); ColStats.summarize(t); ColStats.colmean(t, 1)
end
for k in 1:10
    T = @eval $(Symbol("User", k))
    t = Base.invokelatest(T, [rand(50) for _ in 1:4])
    Base.invokelatest(report, t)
    Base.invokelatest(ColStats.colmean, t, 1)
end

println("\nX5 after 13 types over 2 representations (canonical + Matrix):")
for f in (ColStats.var"colmean#worker", ColStats.var"summarize#worker", ColReports.var"report#worker")
    mis = collect(Base.specializations(first(methods(f))))
    concrete = [mi.specTypes.parameters[3] for mi in mis if isconcretetype(mi.specTypes.parameters[3])]
    println("  ", f, ": ", length(concrete), " concrete worker instance(s): ", concrete)
end
