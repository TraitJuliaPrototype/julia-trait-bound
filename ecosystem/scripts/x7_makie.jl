# X7 — Makie TTFP for a never-seen table type: Design B (boundary) vs
# Design A (Makie inside worker) vs plain Makie on a raw Vector.
# Fresh process per mode: julia +1.11.7 --startup-file=no --project=. x7_makie.jl <B|A|plain>
using ColPlots, ColStats, TraitRegions, ColTables
using CairoMakie
using Printf

struct FreshTable
    cols::Vector{Vector{Float64}}
end

const mode = ARGS[1]
t = FreshTable([rand(500) for _ in 1:4])

if mode in ("B", "A")
    reg = @timed TraitRegions.register!(ColTable, FreshTable,
        (project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
else
    reg = @timed nothing
end

fc = mode == "B" ? (@timed ColPlots.render(histplot(t, 1))) :
     mode == "A" ? (@timed ColPlots.render(histplot_naive(t, 1))) :
                   (@timed begin
                        fig = Figure(size = (400, 300))
                        ax = Axis(fig[1, 1])
                        hist!(ax, t.cols[1]; bins = 24)
                        colorbuffer(fig)
                    end)

@printf("X7 mode=%-5s register: %6.1f ms compile   first-plot: %7.1f ms compile (%7.1f ms total)\n",
        mode, reg.compile_time * 1e3, fc.compile_time * 1e3, fc.time * 1e3)
