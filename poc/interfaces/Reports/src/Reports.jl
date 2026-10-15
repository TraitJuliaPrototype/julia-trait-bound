# Reports: a trait package composing Columns and Stats (writeup/poc3-plan.md §4).
# Its boundary shows keyword and default arguments (§3.5): defaults are
# evaluated in the worker, after projection; a bounded keyword is projected at
# the entry. Its histogram reduction is what MakiePlots plots: the worker
# reduces, Makie is called above with plain arrays (design B of the ecosystem
# PoC, attic/ecosystem/ColPlots).
module Reports
using TraitWorld
@trait_module begin

using Columns, Stats
export ColSummary, summarize, zscores, histcounts, colstd

"Summary statistics of one column: a plain trait-world value."
struct ColSummary
    mean::Float64
    std::Float64
    min::Float64
    max::Float64
    wsum::Float64      # Stats.weighted, the piracy target of demo 1
end

"Sample standard deviation of column `i`."
function colstd(t::ColTable, i::Int)
    c = col(t, i)
    m = colmean(t, i)
    s = 0.0
    for x in c
        s += (x - m)^2
    end
    return sqrt(s / max(length(c) - 1, 1))
end

"Summaries of the columns `cols`, all of them by default: the default calls an operation, so it runs in the worker."
function summarize(t::ColTable; cols = 1:ncols(t))
    out = ColSummary[]
    for i in cols
        c = col(t, i)
        push!(out, ColSummary(colmean(t, i), colstd(t, i), minimum(c), maximum(c), weighted(t, i)))
    end
    return out
end

"z-scores of column `i` against a baseline table, the table itself by default; a supplied baseline is projected at the entry."
zscores(t::ColTable, i::Int; baseline::ColTable = t) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colstd(baseline, i), eps())

"The histogram reduction, computed in the trait world: bin centers and counts. A plot is made of them above."
function histcounts(t::ColTable, i::Int; bins::Int = 24)
    c = col(t, i)
    lo, hi = extrema(c)
    w = hi > lo ? hi - lo : 1.0
    counts = zeros(Float64, bins)
    for x in c
        counts[1 + min(bins - 1, floor(Int, bins * (x - lo) / w))] += 1.0
    end
    centers = [lo + (b - 0.5) * w / bins for b in 1:bins]
    return (centers, counts)
end

@workload begin
    v = [[1.0, 2.0, 4.0], [3.0, 5.0, 8.0]]
    m = [1.0 2.0; 3.0 4.0; 5.0 7.0]
    for t in (v, m)
        summarize(t); summarize(t; cols = 1:1); summarize(t; cols = [2])
        zscores(t, 1); zscores(t, 1; baseline = t)
        histcounts(t, 1); histcounts(t, 2; bins = 8)
        colstd(t, 1)
    end
end

end
end
