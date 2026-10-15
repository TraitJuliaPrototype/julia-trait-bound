# MakiePlots: a trait package that calls Makie (the note, "Calls upward"),
# with CairoMakie as the backend. Makie is never wrapped: the ordinary module
# imports Makie and holds the two adapters the declared calls need; the trait
# module, Plots, reaches Makie only through declared calls, with handles for
# the figure, the axis and the plots that come back. Nothing behind the calls
# is in a worker's view, so nothing of Makie's tree is sealed or tolerated. Nothing in
# the trait world reads a Makie global: the current figure is a handle, the
# backend is this package's choice.
module MakiePlots
using TraitWorld
using PrecompileTools: @recompile_invalidations
# Makie's dependency chain invalidates code at load; recompiling it while
# this package precompiles puts the fixed code in its image (as ColPlots did)
@recompile_invalidations begin
    import Makie, CairoMakie
end

# --- the ordinary module: Makie's API in the shape the declared calls take ---------
"An axis in the first cell of a figure: a handle is not indexed inside the trait world."
axis(f::Makie.Figure; kws...) = Makie.Axis(f[1, 1]; kws...)
"A full render without a display, for measurements: the image size."
rendered(f::Makie.Figure) = size(Makie.colorbuffer(f))

# --- the trait half ------------------------------------------------------------------
@trait_module module Plots
using TraitWorld, Columns, Reports
export Figure, Axis, Plot, PointSeries, xs, ys,
       figure, axis!, scatter!, lines!, hist!, histbars!, vlines!, savefig, render

@handle Figure
@handle Axis
@handle Plot

"What a scatter plot needs from data."
@trait PointSeries{R} begin
    xs(r::R)::Vector{Float64}
    ys(r::R)::Vector{Float64}
end
@implement PointSeries{Matrix{Float64}} begin
    xs(r) = r[:, 1]
    ys(r) = r[:, 2]
end
@implement PointSeries{Tuple{Vector{Float64},Vector{Float64}}} begin
    xs(r) = r[1]
    ys(r) = r[2]
end

figure(; size::Tuple{Int,Int} = (600, 400)) = @call Makie.Figure(; size)::Figure
axis!(f::Figure; title::String = "", xlabel::String = "", ylabel::String = "") =
    @call axis(f; title, xlabel, ylabel)::Axis
scatter!(ax::Axis, t::PointSeries; color::Symbol = :black, markersize::Int = 6) =
    @call Makie.scatter!(ax, xs(t), ys(t); color, markersize)::Plot
scatter!(ax::Axis, t::ColTable, i::Int, j::Int; color::Symbol = :black, markersize::Int = 6) =
    @call Makie.scatter!(ax, col(t, i), col(t, j); color, markersize)::Plot
lines!(ax::Axis, t::ColTable, i::Int; color::Symbol = :black) = @call Makie.lines!(ax, col(t, i); color)::Plot
"A histogram binned by Makie: the column crosses, Makie bins it above."
hist!(ax::Axis, t::ColTable, i::Int; bins::Int = 24) = @call Makie.hist!(ax, col(t, i); bins)::Plot
"A histogram binned in the trait world (Reports.histcounts): only the bars cross."
function histbars!(ax::Axis, t::ColTable, i::Int; bins::Int = 24)
    centers, counts = histcounts(t, i; bins)
    return @call Makie.barplot!(ax, centers, counts)::Plot
end
vlines!(ax::Axis, at::Vector{Float64}; color::Symbol = :red) = @call Makie.vlines!(ax, at; color)::Plot
savefig(path::String, f::Figure) = @call Makie.save(path, f)::Nothing
render(f::Figure) = @call rendered(f)::Tuple{Int,Int}

# rule 7: Makie's code at the declared signatures, and the workers, live here
@workload begin
    m = [1.0 2.0; 3.0 4.0; 5.0 7.0]
    v = [[1.0, 2.0, 4.0], [3.0, 5.0, 8.0]]
    f = figure(); ax = axis!(f; title = "t", xlabel = "x"); axis!(figure())
    scatter!(ax, m); scatter!(ax, (m[:, 1], m[:, 2]); color = :blue)
    for t in (m, v)
        scatter!(ax, t, 1, 2); lines!(ax, t, 1); hist!(ax, t, 1); hist!(ax, t, 2; bins = 8)
        histbars!(ax, t, 1); histbars!(ax, t, 2; bins = 8)
    end
    vlines!(ax, [1.0])
    render(f)
    savefig(joinpath(mktempdir(), "w.png"), f)
end
end
using .Plots: Figure, Axis, Plot, PointSeries, xs, ys, figure, axis!, scatter!, lines!, hist!, histbars!, vlines!, savefig, render
export Figure, Axis, Plot, PointSeries, xs, ys, figure, axis!, scatter!, lines!, hist!, histbars!, vlines!, savefig, render
end
