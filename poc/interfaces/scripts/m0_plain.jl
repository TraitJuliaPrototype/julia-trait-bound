# M0, the plain twin of demo 1 (writeup/poc3-plan.md §5): DataFrames and
# CairoMakie without traits, in a fresh process. Time to first result, first
# plot, and the marginal cost of a new table type written the idiomatic way
# (a generic function that compiles per type). The numbers demo 1 is compared with.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/m0_plain.jl
using Printf
ms(s) = @sprintf("%.1f ms (%.1f ms compiling)", s.time * 1e3, (s.compile_time + s.recompile_time) * 1e3)
const SAMPLE = joinpath(@__DIR__, "..", "App", "data", "sample.csv")

t0 = @timed @eval using DataFrames, CSV
t1 = @timed @eval using CairoMakie
println("using DataFrames, CSV: ", round(t0.time; digits = 2), " s;  using CairoMakie: ", round(t1.time; digits = 2), " s")
df = CSV.read(SAMPLE, DataFrame)

# the plain twin of Reports.summarize: generic over the table, as idiomatic code is
struct PSummary; mean::Float64; std::Float64; min::Float64; max::Float64; wsum::Float64; end
pcol(df::DataFrame, i::Int) = df[!, i]::Vector{Float64}
pncols(df::DataFrame) = ncol(df)
pweight(x::Real) = 1.0
function psummarize(t; cols = 1:pncols(t))
    out = PSummary[]
    for i in cols
        c = pcol(t, i)
        m = sum(c) / length(c)
        s = 0.0
        for x in c; s += (x - m)^2; end
        w = sum(x -> pweight(x) * x, c)
        push!(out, PSummary(m, sqrt(s / max(length(c) - 1, 1)), minimum(c), maximum(c), w))
    end
    return out
end
function phistcounts(t, i::Int; bins::Int = 24)
    c = pcol(t, i)
    lo, hi = extrema(c)
    w = hi > lo ? hi - lo : 1.0
    counts = zeros(Float64, bins)
    for x in c
        counts[1 + min(bins - 1, floor(Int, bins * (x - lo) / w))] += 1.0
    end
    ([lo + (b - 0.5) * w / bins for b in 1:bins], counts)
end
function pplot(t)
    centers, counts = phistcounts(t, 1)
    fig = Figure(size = (600, 400))
    ax = Axis(fig[1, 1]; title = "sample.csv", xlabel = "x")
    barplot!(ax, centers, counts)
    vlines!(ax, [sum(pcol(t, 1)) / length(pcol(t, 1))]; color = :red)
    size(colorbuffer(fig))
end

s1 = @timed psummarize(df)
println("plain summarize(df), first result: ", ms(s1))
s2 = @timed psummarize(df; cols = [2, 3])
println("plain summarize(df; cols=[2,3]):   ", ms(s2))
p1 = @timed pplot(df)
println("plain first plot (bin, barplot!, colorbuffer): ", ms(p1))

# a new table type, the idiomatic way: two methods, and the generic code compiles again for it
struct Measurements; data::Vector{Vector{Float64}}; end
c1 = @timed @eval begin
    pcol(t::Measurements, i::Int) = t.data[i]
    pncols(t::Measurements) = length(t.data)
end
m = Measurements([df[!, i] for i in 1:3])
r1 = @timed psummarize(m)
r2 = @timed pplot(m)
println("plain new type: methods ", ms(c1), "; first summarize ", ms(r1), "; first plot ", ms(r2))
