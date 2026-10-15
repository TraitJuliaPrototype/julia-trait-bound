# MakiePlotsCSVExt: where CSV, DataFrames and MakiePlots meet (rule 4: code for
# a combination of packages lives in a package that depends on all of them, a
# package extension when they meet only in a session). It defines no methods;
# its workload runs read, summarize and plot with CSV loaded, so that its image
# holds Makie's code compiled with CSV's dependencies present: InlineStrings'
# `Base.thisind(::InlineString, ::Int)` and SentinelArrays' methods would
# otherwise invalidate Makie's cached text and array code at every such
# session's first plot (scripts/x9_ttfp_blame.jl).
module MakiePlotsCSVExt
using MakiePlots, CSV, DataFrames
import Reports
using PrecompileTools: @compile_workload
@compile_workload begin
    dir = mktempdir()
    path = joinpath(dir, "w.csv")
    write(path, "x,y,z\n" * join(("$(i / 7),$(sin(i)),$(i % 5 + 0.5)" for i in 1:50), "\n") * "\n")
    df = CSV.read(path, DataFrame)
    # the columns as the DataFrame projection gives them: Columns' DataFrames extension is not
    # loaded while another extension precompiles, and the workers and Makie calls are the same
    cols = Vector{Float64}[Vector{Float64}(c) for c in eachcol(df)]
    Reports.summarize(cols)
    f = figure(); ax = axis!(f; title = "x", xlabel = "x")
    histbars!(ax, cols, 1)
    vlines!(ax, [1.0])
    savefig(joinpath(dir, "w.png"), f)
end
end
