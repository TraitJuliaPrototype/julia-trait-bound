# How many distinct methods does one plot reach through dynamic dispatch? (session 21)
# The Makie calls MakiePlots makes, traced with Julia's dispatch tracing
# (`jl_force_trace_dispatch_enable`: a precompile statement per method instance
# reached by a dynamic call, the first time in the session), on the first plot,
# then on a plot of other data in the same session. Fresh process:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x15_makie_dispatch.jl 2> dispatch.txt
import Makie, CairoMakie
function makie_calls(path::String, title::String, xlabel::String, centers::Vector{Float64}, counts::Vector{Float64}, m::Float64)
    f = Makie.Figure(; size = (600, 400))
    ax = Makie.Axis(f[1, 1]; title, xlabel, ylabel = "")
    Makie.barplot!(ax, centers, counts)
    Makie.vlines!(ax, [m]; color = :red)
    Makie.save(path, f)
    return nothing
end
println(Core.stderr, "## first plot")
ccall(:jl_force_trace_dispatch_enable, Cvoid, ())
makie_calls(joinpath(tempdir(), "x15a.png"), "t", "x", [1.0, 2.0, 3.0], [2.0, 5.0, 1.0], 2.0)
ccall(:jl_force_trace_dispatch_disable, Cvoid, ())
println(Core.stderr, "## second plot, other data")
ccall(:jl_force_trace_dispatch_enable, Cvoid, ())
makie_calls(joinpath(tempdir(), "x15b.png"), "another title", "y", collect(1.0:10.0), rand(10), 4.5)
ccall(:jl_force_trace_dispatch_disable, Cvoid, ())
println(Core.stderr, "## end")
