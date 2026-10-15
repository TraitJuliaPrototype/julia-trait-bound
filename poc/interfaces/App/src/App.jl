# App: the application of demo 2 (writeup/poc3-plan.md §1, §4), an ordinary
# package that depends on the trait stack, the DataFrames wrapper and the Makie calls. `main` reads a
# CSV into a DataFrame, summarizes it through Reports and plots it through
# MakiePlots; `pipeline` is the trim variant: the same analysis fed by
# DelimitedFiles and writing text, with neither DataFrames nor Makie.
module App
using Columns, Stats, Reports, DataFramesWrapper, MakiePlots
using DataFrames, CSV, DelimitedFiles
using PrecompileTools: @compile_workload
export main, pipeline, sinks

const SAMPLE = joinpath(@__DIR__, "..", "data", "sample.csv")

"The application's outward sinks (plan §3.7, M8): an IO of a concrete type."
sinks() = (io = Core.stdout,)

function report(io::IO, names::Vector{String}, s::Vector{ColSummary})
    for (n, c) in zip(names, s)
        println(io, rpad(n, 6), " mean ", round(c.mean; digits = 4), "  std ", round(c.std; digits = 4),
                "  min ", c.min, "  max ", c.max, "  weighted ", round(c.wsum; digits = 4))
    end
    return nothing
end

"CSV to DataFrame, Reports' summary, a plot saved to `out`."
function main(args::Vector{String})
    path = isempty(args) ? SAMPLE : args[1]
    out = length(args) > 1 ? args[2] : "report.png"
    df = CSV.read(path, DataFrame)                      # ordinary code
    s = summarize(df)::Vector{ColSummary}               # into the trait world through the DataFrame projection
    report(Core.stdout, names(df), s)
    f = figure()
    ax = axis!(f; title = basename(path), xlabel = names(df)[1])
    histbars!(ax, df, 1)
    vlines!(ax, [s[1].mean])
    savefig(out, f)
    return 0
end

"The trim variant: DelimitedFiles in, text out, no DataFrames, no Makie."
function pipeline(args::Vector{String})
    path = isempty(args) ? SAMPLE : args[1]
    m = readdlm(path, ',', Float64; skipstart = 1)::Matrix{Float64}
    s = summarize(m)::Vector{ColSummary}
    report(Core.stdout, ["col$i" for i in 1:size(m, 2)], s)
    centers, counts = histcounts(m, 1)
    println(Core.stdout, "histogram of column 1: ", counts)
    return 0
end

@compile_workload begin
    main([SAMPLE, joinpath(mktempdir(), "r.png")])
    pipeline([SAMPLE])
end
end
