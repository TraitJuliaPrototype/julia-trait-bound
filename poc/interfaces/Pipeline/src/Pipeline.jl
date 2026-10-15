# The trim variant of the application (writeup/poc3-plan.md §1, demo 2 step 3):
# the same analysis as App.main, fed by a small concrete CSV reader and writing
# text, with neither DataFrames nor Makie among its dependencies, so that the
# trait-world pipeline can be trimmed and verified on its own.
module Pipeline
using Columns, Stats, Reports
using PrecompileTools: @compile_workload
export pipeline

const SAMPLE = joinpath(@__DIR__, "..", "..", "App", "data", "sample.csv")

# The output is written with one `print` per value: a trimmed build cannot
# resolve `rpad` (it measures text width through a generic fold), a `println`
# of more than a handful of arguments (Vararg{Any}) or the `show` of a vector.
function report(io::IO, names::Vector{String}, s::Vector{ColSummary})
    for (n, c) in zip(names, s)
        print(io, n)
        for _ in ncodeunits(n):5
            print(io, ' ')
        end
        print(io, " mean ", round(c.mean; digits = 4))
        print(io, "  std ", round(c.std; digits = 4))
        print(io, "  min ", c.min)
        print(io, "  max ", c.max)
        print(io, "  weighted ", round(c.wsum; digits = 4))
        print(io, '\n')
    end
    return nothing
end
function printvec(io::IO, v::Vector{Float64})
    print(io, '[')
    for i in eachindex(v)
        i > 1 && print(io, ", ")
        print(io, v[i])
    end
    print(io, ']')
    return nothing
end

"""
A CSV of Float64 columns with a header line as a `Matrix{Float64}`: a small
concrete reader, so that the ordinary code around the trait world has no
dynamic dispatch of its own (DelimitedFiles' `readdlm` dispatches on its
options at run time, which a trimmed build cannot resolve). The file is read
whole: `readlines` closes its stream through a closure field of type
`Function`, which a trimmed build cannot call.
"""
function readcsv(path::String)
    lines = split(read(path, String), '\n'; keepempty = false)
    names = String.(split(lines[1], ','))
    n = length(lines) - 1
    m = Matrix{Float64}(undef, n, length(names))
    for i in 1:n
        parts = split(lines[i + 1], ',')
        for j in 1:length(names)
            m[i, j] = parse(Float64, parts[j])
        end
    end
    return names, m
end

"CSV in (a Matrix{Float64} is a ColTable), Reports' summary and histogram out as text."
function pipeline(args::Vector{String})
    path = isempty(args) ? SAMPLE : args[1]
    names, m = readcsv(path)
    s = summarize(m)::Vector{ColSummary}                       # entries return what their workers return, which ordinary code asserts
    report(Core.stdout, names, s)
    centers, counts = histcounts(m, 1)::Tuple{Vector{Float64},Vector{Float64}}
    print(Core.stdout, "histogram of column 1: ")
    printvec(Core.stdout, counts)
    print(Core.stdout, '\n')
    return 0
end

@compile_workload begin
    pipeline([SAMPLE])
end
end
