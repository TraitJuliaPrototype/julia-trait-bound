"""
ColPlots — plotting over ColTable by wrapping CairoMakie, in two designs:

  * **Design B (`histplot`, the design's answer)**: the region worker does
    only the shared data reduction (`histcounts` — a region op returning
    plain arrays); Makie is called at the BOUNDARY, outside any region.
    Makie never acquires edges into trait-bound code; data crosses, code
    doesn't.
  * **Design A (`histplot_naive`, deliberately "wrong")**: the region worker
    itself calls CairoMakie — giving the worker inference edges into a huge
    non-trait-bound package. Exists to measure what the closure rule
    prevents.
"""
module ColPlots

using TraitRegions, ColTables, ColStats
using CairoMakie
using PrecompileTools: @compile_workload

export histplot, histplot_naive, histcounts, render

const NBINS = 24

@region ColTable [ColStats.colmean, ColStats.colstd] begin
    # Design B worker: pure data reduction, returns plain arrays
    function histcounts(t, i::Int)
        c = col(t, i)::Vector{Float64}
        lo = c[1]; hi = c[1]
        @inbounds for k in eachindex(c)
            x = c[k]
            lo = ifelse(x < lo, x, lo); hi = ifelse(x > hi, x, hi)
        end
        w = hi > lo ? (hi - lo) : 1.0
        counts = zeros(Float64, NBINS)
        @inbounds for k in eachindex(c)
            counts[1 + min(NBINS - 1, floor(Int, NBINS * (c[k] - lo) / w))] += 1.0
        end
        centers = [lo + (b - 0.5) * w / NBINS for b in 1:NBINS]
        (centers, counts, colmean(t, i), colstd(t, i))
    end

    # Design A worker: Makie called INSIDE the region (deliberately wrong)
    function histplot_naive(t, i::Int)
        c = col(t, i)::Vector{Float64}
        fig = CairoMakie.Figure(size = (400, 300))
        ax = CairoMakie.Axis(fig[1, 1])
        CairoMakie.hist!(ax, c; bins = NBINS)
        fig
    end
end

"Design B boundary: worker-computed arrays handed to Makie on the dynamic side."
function histplot(t, i::Int)
    centers, counts, m, s = histcounts(t, i)
    fig = Figure(size = (400, 300))
    ax = Axis(fig[1, 1], title = "mean=$(round(m, digits=3)) std=$(round(s, digits=3))")
    barplot!(ax, centers, counts)
    vlines!(ax, [m]; color = :red)
    fig
end

"Force a full render without a display."
render(fig) = colorbuffer(fig)

__init__() = TraitRegions.reinit(@__MODULE__)

struct _PCDummy
    cols::Vector{Vector{Float64}}
end

@compile_workload begin
    TraitRegions.reinit(ColStats)
    TraitRegions.reinit(@__MODULE__)
    d = _PCDummy([[1.0, 2.0, 3.0, 2.5], [4.0, 5.0, 6.0, 5.5]])
    TraitRegions.register!(ColTable, _PCDummy,
        (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
    render(histplot(d, 1))
    render(histplot_naive(d, 2))
    precompile_seal(ColTable, _PCDummy)
    empty!(TraitRegions.seal_registry(ColTable))
end

end
