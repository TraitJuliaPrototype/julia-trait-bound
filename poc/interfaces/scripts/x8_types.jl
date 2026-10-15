# X8, ported from attic/ecosystem/scripts/x8_makie_scaling.jl: the marginal
# cost per additional user type (writeup/poc3-plan.md §1, demo 1 step 3; M4).
# A warm-up type absorbs the shared session cost in every mode; types 1..K
# then show the marginal cost, with the type's registration inside it.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x8_types.jl <recipe|trait|plainpre>
#   recipe   idiomatic Makie: convert_arguments per type (Makie's pipeline compiles per type)
#   trait    the one-line conformance, Reports.histcounts in the trait world, bars through MakieInterface
#   plainpre hand erasure: a generic bin-then-plot function with no trait machinery (compiles per type)
using Printf
const mode = ARGS[1]
const K = 6
if mode == "trait"
    using TraitWorld, Columns, Reports, MakieInterface
else
    using CairoMakie
end
for k in 0:K
    @eval struct $(Symbol("Tab", k)); data::Vector{Vector{Float64}}; end
end
function binfor(t)
    c = t.data[1]
    lo, hi = extrema(c)
    w = hi > lo ? hi - lo : 1.0
    counts = zeros(Float64, 24)
    @inbounds for x in c
        counts[1 + min(23, floor(Int, 24 * (x - lo) / w))] += 1.0
    end
    ([lo + (b - 0.5) * w / 24 for b in 1:24], counts)
end
if mode == "recipe"
    render_one(t) = size(colorbuffer(barplot(t).figure))
elseif mode == "trait"
    render_one(t) = (f = figure(); ax = axis!(f); histbars!(ax, t, 1); render(f))
else
    render_one(t) = begin
        centers, counts = binfor(t)
        fig = Figure(size = (600, 400)); ax = Axis(fig[1, 1]); barplot!(ax, centers, counts)
        size(colorbuffer(fig))
    end
end
function prep(T)
    if mode == "recipe"
        @eval Makie.convert_arguments(::Type{<:BarPlot}, t::$T) = binfor(t)
    elseif mode == "trait"
        @eval @implement ColTable $T
    end
end
prep(Tab0)
warm = @timed Base.invokelatest(render_one, Tab0([rand(500)]))
@printf("X8 mode=%-8s warm-up type (shared session cost): %7.1f ms compile (%7.1f ms total)\n",
        mode, warm.compile_time * 1e3, warm.time * 1e3)
tot = 0.0
for k in 1:K
    T = @eval $(Symbol("Tab", k))
    t = Base.invokelatest(T, [rand(500)])
    s = @timed begin
        Base.invokelatest(prep, T)
        Base.invokelatest(render_one, t)
    end
    global tot += s.compile_time
    @printf("  type %d: %7.1f ms compile (%7.1f ms total)\n", k, s.compile_time * 1e3, s.time * 1e3)
end
@printf("X8 mode=%-8s marginal compile for %d additional types: %7.1f ms (%.1f per type)\n", mode, K, tot * 1e3, tot * 1e3 / K)
