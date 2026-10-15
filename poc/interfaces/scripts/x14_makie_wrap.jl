# How close is Makie to a trait wrapper? (session 21) Two checks, one fresh process:
#   1. sealing: wrap Makie (CairoMakie named as its implementation) in a wrapper
#      defined here, and audit what then pirates the sealed region, tolerations ignored;
#   2. closure: `verify_main` over the Makie calls MakiePlots makes, at the
#      argument types it passes (plain vectors, strings, symbols), i.e. what a
#      worker would compile against if it called Makie directly instead of by
#      declared calls. Every dynamic call whose targets cannot be enumerated is
#      a hole: code a closed build cannot compile ahead, and where run-time
#      compilation can happen.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x14_makie_wrap.jl
using TraitWorld, Printf
TraitWorld.piracy_mode!(:warn)
@eval using Columns, Stats, Reports, DataFramesWrapper, StaticArraysCoreWrapper, ColorTypesWrapper
@eval using MakiePlots
import Makie, CairoMakie

function audit(tag)
    TraitWorld._RESCAN[] = true
    empty!(TraitWorld.TOLERATED)
    empty!(TraitWorld._PIRATICAL)
    found = TraitWorld.find_pirates!()
    bypkg = Dict{String,Vector{Any}}()
    for p in found; push!(get!(bypkg, p.definer, Any[]), p.method); end
    @printf("%s: %d piratical method(s) from %d package(s); sealed: %d names\n", tag, length(found), length(bypkg), length(TraitWorld.SEALED))
    for (d, ms) in sort!(collect(bypkg); by = p -> -length(p[2]))
        println("   ", rpad(d, 24), rpad(length(ms), 5), first(string(ms[1]), 120))
    end
    return bypkg
end

println("== 1. sealing")
before = audit("without a Makie wrapper")
module MakieWrapperX
using TraitWorld
import Makie, CairoMakie
@trait_wrapper Makie CairoMakie
end
after = audit("with Makie wrapped (CairoMakie its implementation)")
println("new with the wrapper:")
for (d, ms) in sort!(collect(after); by = p -> -length(p[2]))
    old = get(before, d, Any[])
    new = filter(m -> !any(x -> x === m, old), ms)
    isempty(new) && continue
    println("  ", d, " (", length(new), "):")
    for m in new[1:min(end, 6)]; println("     ", first(string(m), 150)); end
end

println("\n== 2. closure of the calls MakiePlots makes")
function makie_calls(path::String, title::String, xlabel::String, centers::Vector{Float64}, counts::Vector{Float64}, m::Float64)
    f = Makie.Figure(; size = (600, 400))
    ax = Makie.Axis(f[1, 1]; title, xlabel, ylabel = "")
    Makie.barplot!(ax, centers, counts)
    Makie.vlines!(ax, [m]; color = :red)
    Makie.save(path, f)
    return nothing
end
const ARGT = (String, String, String, Vector{Float64}, Vector{Float64}, Float64)
makie_calls(joinpath(tempdir(), "x14.png"), "t", "x", [1.0, 2.0, 3.0], [2.0, 5.0, 1.0], 2.0)
t = @elapsed r = verify_main(makie_calls, ARGT)
@printf("verify_main: %.1f s; %d method instances reached (%d on normal paths); %d static calls, %d bounded dynamic calls\n",
        t, r.reached, r.normal, r.static_calls, r.bounded)
holes = filter(h -> !h.errorpath, r.holes)
@printf("holes: %d on normal paths, %d on error paths only; normal-path instances without native code: %d\n",
        length(holes), length(r.holes) - length(holes), length(r.uncompiled))
root(h) = h.caller.def isa Method ? string(Base.moduleroot(h.caller.def.module)) : "?"
file(h) = h.caller.def isa Method ? string(root(h), "/", basename(string(h.caller.def.file))) : "?"
tally(f, xs) = (d = Dict{String,Int}(); for x in xs; k = f(x); d[k] = get(d, k, 0) + 1; end; sort!(collect(d); by = p -> -p[2]))
println("normal-path holes by kind: ", tally(h -> string(h.kind), holes))
println("by package: ", tally(root, holes))
println("by file (top 20):")
for (k, n) in tally(file, holes)[1:min(end, 20)]; println("   ", rpad(k, 48), n); end
println("dispatch holes, by callee (top 25):")
cname(h) = (c = h.callee; first(c isa Function ? string(parentmodule(c), ".", nameof(c)) : string(c), 70))
for (k, n) in tally(cname, filter(h -> h.kind === :dispatch, holes))[1:min(end, 25)]
    println("   ", rpad(k, 72), n)
end
println("the argument types at dispatch holes, how open (top 15 abstract types):")
abs = Dict{String,Int}()
for h in holes
    h.argtypes isa AbstractVector || continue
    for T in h.argtypes
        T isa Type || continue
        isconcretetype(T) && continue
        k = first(string(T), 60); abs[k] = get(abs, k, 0) + 1
    end
end
for (k, n) in sort!(collect(abs); by = p -> -p[2])[1:min(end, 15)]; println("   ", rpad(k, 62), n); end

println("\n== 2b. each Makie call on its own, at the concrete handle types a wrapper knows")
f0 = Makie.Figure(; size = (600, 400)); ax0 = Makie.Axis(f0[1, 1]; title = "t", xlabel = "x", ylabel = "")
calls = [
    "Figure(; size)" => (() -> Makie.Figure(; size = (600, 400)), ()),
    "Axis(f[1, 1]; title, xlabel, ylabel)" => ((gp, a, b, c) -> Makie.Axis(gp; title = a, xlabel = b, ylabel = c), (typeof(f0[1, 1]), String, String, String)),
    "barplot!(ax, centers, counts)" => ((ax, x, y) -> Makie.barplot!(ax, x, y), (typeof(ax0), Vector{Float64}, Vector{Float64})),
    "vlines!(ax, at; color)" => ((ax, x) -> Makie.vlines!(ax, x; color = :red), (typeof(ax0), Vector{Float64})),
    "save(path, f)" => ((p, f) -> Makie.save(p, f), (String, typeof(f0))),
]
allholes = Any[]
for (name, (fn, at)) in calls
    rr = verify_main(fn, at)
    hs = filter(h -> !h.errorpath, rr.holes)
    append!(allholes, hs)
    @printf("  %-40s %5d instances reached, %4d normal-path holes  %s\n", name, rr.reached, length(hs), string(tally(h -> string(h.kind), hs)))
end
println("all calls: by package ", tally(root, allholes))
println("by file (top 15):")
for (k, n) in tally(file, allholes)[1:min(end, 15)]; println("   ", rpad(k, 48), n); end
