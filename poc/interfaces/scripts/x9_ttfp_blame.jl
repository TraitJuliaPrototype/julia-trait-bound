# Who causes the recompilation on the way to a first plot? One fresh process:
# the loads under @snoop_invalidations, then CSV.read, summarize and a plot
# saved to PNG under @snoop_inference. Inference of a method instance that a
# load invalidated is recompilation, blamed on the package whose method
# insertion invalidated it; the rest is fresh compilation, by the package whose
# code it is. Inference time only (code generation comes on top).
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x9_ttfp_blame.jl [plain]
using SnoopCompileCore
const PLAIN = !isempty(ARGS) && ARGS[1] == "plain"
const CSVPATH = joinpath(@__DIR__, "..", "App", "data", "sample.csv")
invs = @snoop_invalidations begin
    if PLAIN
        @eval import CairoMakie
    else
        @eval using TraitWorld, Columns, Reports, DataFramesWrapper, MakiePlots
    end
    @eval using CSV, DataFrames
end
tinf = @snoop_inference begin
    df = CSV.read(CSVPATH, DataFrame)
    if PLAIN
        f = CairoMakie.Figure(); ax = CairoMakie.Axis(f[1, 1]; title = "x")
        CairoMakie.hist!(ax, df[!, 1]; bins = 24)
        CairoMakie.save(joinpath(tempdir(), "x9.png"), f)
    else
        summarize(df)
        f = figure(); ax = axis!(f; title = "x")
        histbars!(ax, df, 1)
        savefig(joinpath(tempdir(), "x9.png"), f)
    end
end
using SnoopCompile, Printf

rootname(m::Module) = string(Base.moduleroot(m) === Main ? m : Base.moduleroot(m))
rootname(mi::Core.MethodInstance) = mi.def isa Method ? rootname(mi.def.module) : "?"

# every invalidated MethodInstance => the package whose method insertion invalidated it
trees = invalidation_trees(invs)
blame = IdDict{Core.MethodInstance,String}()
function collect!(node, who)
    node isa SnoopCompile.InstanceNode || return
    haskey(blame, node.mi) || (blame[node.mi] = who)
    for c in node.children
        collect!(c, who)
    end
end
for tree in trees
    who = tree.method isa Method ? rootname(tree.method.module) : string(tree.method)
    for n in tree.backedges
        collect!(n, who)
    end
    for p in tree.mt_backedges
        collect!(p.second, who)
    end
end
@printf("invalidation trees: %d; invalidated instances: %d\n", length(trees), length(blame))

# inference during the workload, exclusive time per frame
fresh = Dict{String,Float64}(); recomp = Dict{Tuple{String,String},Float64}()
total = 0.0
for t in SnoopCompile.flatten(tinf)
    mi = Core.MethodInstance(t)
    mi isa Core.MethodInstance || continue
    x = SnoopCompile.exclusive(t)
    global total += x
    who = get(blame, mi, nothing)
    if who === nothing
        fresh[rootname(mi)] = get(fresh, rootname(mi), 0.0) + x
    else
        k = (who, rootname(mi)); recomp[k] = get(recomp, k, 0.0) + x
    end
end
@printf("inference during the workload: %.2f s (fresh %.2f s, recompiling invalidated instances %.2f s)\n",
        total, sum(values(fresh); init = 0.0), sum(values(recomp); init = 0.0))
println("\nrecompilation, by (package whose insertion invalidated => package whose code recompiled):")
for (k, v) in sort!(collect(recomp); by = p -> -p[2])[1:min(end, 15)]
    @printf("   %-22s => %-22s %6.3f s\n", k[1], k[2], v)
end
println("\nfresh compilation, by package whose code it is:")
for (k, v) in sort!(collect(fresh); by = p -> -p[2])[1:min(end, 12)]
    @printf("   %-22s %6.3f s\n", k, v)
end

# the inserted methods behind the recompilation, by the inference time of what they invalidated
treetime = Tuple{Float64,String,String}[]
mitime = IdDict{Core.MethodInstance,Float64}()
for t in SnoopCompile.flatten(tinf)
    mi = Core.MethodInstance(t); mi isa Core.MethodInstance || continue
    mitime[mi] = get(mitime, mi, 0.0) + SnoopCompile.exclusive(t)
end
function treesum(node, acc)
    node isa SnoopCompile.InstanceNode || return acc
    acc[] += get(mitime, node.mi, 0.0)
    for c in node.children; treesum(c, acc); end
    return acc
end
for tree in trees
    acc = Ref(0.0)
    for n in tree.backedges; treesum(n, acc); end
    for p in tree.mt_backedges; treesum(p.second, acc); end
    who = tree.method isa Method ? rootname(tree.method.module) : "?"
    push!(treetime, (acc[], who, first(string(tree.reason, " ", tree.method), 150)))
end
println("\nthe inserted methods whose invalidations cost the most inference in the workload:")
for (x, who, m) in sort!(treetime; by = first, rev = true)[1:min(end, 12)]
    @printf("   %6.3f s  %-16s %s\n", x, who, m)
end
