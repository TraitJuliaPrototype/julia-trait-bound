# How open is a real program? verify_main on two mains over the CairoMakie stack:
#   compute_main: trait ops only (ColStats/ColReports/ColPlots.histcounts);
#   plot_main:    the same plus a Makie figure rendered to a pixel buffer
#                 (ColPlots.histplot: Makie at the boundary, design B);
#   plot_concrete: one concretely typed table, so the walk enters Makie itself
#                 (in plot_main, histplot(::Any, ...) is already a hole and the
#                 walk stops there: holes are a frontier, not a total).
#   julia --startup-file=no --project=poc/verifymain/ecoenv poc/verifymain/makie_holes.jl
using TraitRegions, ColTables, ColStats, ColReports, EagerTables, LazyTables, MatrixTables
using ColPlots, CairoMakie, Printf

include(joinpath(@__DIR__, "eco_program.jl"))

function compute_main(args::Vector{String})
    acc = 0.0
    for t in tables(parse(Int, args[1]))
        centers, counts, m, s = ColPlots.histcounts(t, 1)
        acc += report(t)::Float64 + sum(counts) + m + s
    end
    return acc
end

function plot_main(args::Vector{String})
    acc = 0.0
    for t in tables(parse(Int, args[1]))
        img = ColPlots.render(ColPlots.histplot(t, 1))
        acc += report(t)::Float64 + length(img)
    end
    return acc
end

function plot_concrete(args::Vector{String})
    t = EagerTable([collect(range(0.0, Float64(j), length = parse(Int, args[1]))) for j in 1:4])
    img = ColPlots.render(ColPlots.histplot(t, 1))
    return report(t)::Float64 + length(img)
end

for f in (compute_main, plot_main, plot_concrete)
    t = @elapsed r = verify_main(f, (Vector{String},))
    show(stdout, MIME"text/plain"(), r)
    nh = count(h -> !h.errorpath, r.holes)
    kinds = Dict{Symbol,Int}()
    for h in r.holes; h.errorpath || (kinds[h.kind] = get(kinds, h.kind, 0) + 1); end
    owners = Dict{Any,Int}()
    for h in r.holes
        h.errorpath && continue
        o = TraitRegions.owner(h.caller.def.module)
        owners[o] = get(owners, o, 0) + 1
    end
    @printf("\n  [%.1f s] normal-path holes by kind: %s\n  by owner of the calling code: %s\n\n", t,
            join(("$k $v" for (k, v) in sort!(collect(kinds); by = last, rev = true)), ", "),
            join(("$k $v" for (k, v) in sort!(collect(owners); by = last, rev = true)), ", "))
end
