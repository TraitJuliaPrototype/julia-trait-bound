# How much variety does Makie's `Any` hide? (session 21, from Fable's review of note rev 1112)
# x15 varied only the values of the second plot. Here each later phase changes argument
# types or attribute shapes, and the dynamic-dispatch targets new in each phase are counted.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x16_makie_variety.jl 2> variety.txt
#   awk '/^## /{ph=$2; next} /^precompile/ && !seen[$0]++ {n[ph]++} END{for(p in n) print p, n[p]}' variety.txt | sort
# Measured: A 1879, B 1, C 64, D 35, E 41, F 84, G 1.
import Makie, CairoMakie
function makie_calls(path::String, title::String, xlabel::String, centers, counts, m; color = :red)
    f = Makie.Figure(; size = (600, 400))
    ax = Makie.Axis(f[1, 1]; title, xlabel, ylabel = "")
    Makie.barplot!(ax, centers, counts)
    Makie.vlines!(ax, m; color)
    Makie.save(path, f)
    return nothing
end
function phase(name, f)
    println(Core.stderr, "## ", name)
    ccall(:jl_force_trace_dispatch_enable, Cvoid, ())
    f()
    ccall(:jl_force_trace_dispatch_disable, Cvoid, ())
end
d = tempdir()
phase("A first plot (Vector{Float64}, Vector{Float64}, [Float64]), as x15",
      () -> makie_calls(joinpath(d, "va.png"), "t", "x", [1.0, 2.0, 3.0], [2.0, 5.0, 1.0], [2.0]))
phase("B same types, other values, as x15's second plot",
      () -> makie_calls(joinpath(d, "vb.png"), "another title", "y", collect(1.0:10.0), rand(10), [4.5]))
phase("C centers Vector{Int}, counts Vector{Float32}, m Vector{Float32}",
      () -> makie_calls(joinpath(d, "vc.png"), "t", "x", [1, 2, 3], Float32[2, 5, 1], Float32[2]))
phase("D centers UnitRange{Int}, counts Vector{Float64}, color a Vector{Symbol} on two vlines",
      () -> makie_calls(joinpath(d, "vd.png"), "t", "x", 1:3, [2.0, 5.0, 1.0], [1.0, 2.0]; color = [:red, :blue]))
phase("E color an RGBf, m Vector{Int}",
      () -> makie_calls(joinpath(d, "ve.png"), "t", "x", [1.0, 2.0, 3.0], [2.0, 5.0, 1.0], [2]; color = Makie.RGBf(0, 0, 1)))
phase("F barplot with numeric color (colormap), same data types as A",
      () -> begin
          f = Makie.Figure(; size = (600, 400))
          ax = Makie.Axis(f[1, 1]; title = "t", xlabel = "x", ylabel = "")
          Makie.barplot!(ax, [1.0, 2.0, 3.0], [2.0, 5.0, 1.0]; color = [2.0, 5.0, 1.0], colormap = :viridis)
          Makie.save(joinpath(d, "vf.png"), f)
      end)
phase("G A again (should add nothing)",
      () -> makie_calls(joinpath(d, "vg.png"), "t2", "x2", [1.0, 2.0, 3.0, 4.0], [2.0, 5.0, 1.0, 3.0], [2.5]))
println(Core.stderr, "## end")
