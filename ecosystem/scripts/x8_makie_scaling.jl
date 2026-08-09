# X8 — where Makie shows the real speedup: MARGINAL cost per additional
# custom type. Idiomatic Makie integration (convert_arguments recipes) drags
# each user type through Makie's pipeline — recompiling per type. The region
# route erases the type before Makie sees it: Makie compiles once per
# session. A warm-up type absorbs the shared session cost in BOTH modes;
# types 1..K then show the marginal cost.
#
# Fresh process per mode: julia +1.11.7 --startup-file=no --project=. x8_makie_scaling.jl <recipe|region>
using ColPlots, ColStats, TraitRegions, ColTables
using CairoMakie
using Printf

const mode = ARGS[1]
const K = 6

for k in 0:K   # Tab0 is the warm-up type
    @eval struct $(Symbol("Tab", k))
        cols::Vector{Vector{Float64}}
    end
end

# identical binning logic in both modes; in recipe mode it is (deliberately,
# idiomatically) generic over the table type — like real recipe code
function binfor(t)
    c = t.cols[1]
    lo, hi = extrema(c)
    w = hi > lo ? hi - lo : 1.0
    counts = zeros(Float64, 24)
    @inbounds for x in c
        counts[1 + min(23, floor(Int, 24 * (x - lo) / w))] += 1.0
    end
    ([lo + (b - 0.5) * w / 24 for b in 1:24], counts)
end

if mode == "recipe"
    render_one(t) = colorbuffer(barplot(t).figure)
else
    render_one(t) = begin
        cc = histcounts(t, 1)
        fig = Figure(size = (400, 300))
        ax = Axis(fig[1, 1])
        barplot!(ax, cc[1], cc[2])
        colorbuffer(fig)
    end
end

function prep(T)
    if mode == "recipe"
        @eval Makie.convert_arguments(::Type{<:BarPlot}, t::$T) = binfor(t)
    else
        TraitRegions.register!(ColTable, T,
            (project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
    end
end

prep(Tab0)
warm = @timed Base.invokelatest(render_one, Tab0([rand(500)]))
@printf("X8 mode=%-6s  warm-up type (shared Makie session cost): %7.1f ms compile\n",
        mode, warm.compile_time * 1e3)

tot = 0.0
for k in 1:K
    T = @eval $(Symbol("Tab", k))
    prep(T)
    t = Base.invokelatest(T, [rand(500)])
    s = @timed Base.invokelatest(render_one, t)
    global tot += s.compile_time
    @printf("  type %d: %7.1f ms compile (%7.1f ms total)\n",
            k, s.compile_time * 1e3, s.time * 1e3)
end
@printf("X8 mode=%-6s  marginal compile for %d additional types: %7.1f ms\n", mode, K, tot * 1e3)
