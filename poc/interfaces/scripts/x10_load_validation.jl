# What happens to cached code when package images load (Julia 1.12's
# Base.StaticData, Julia code called from base/loading.jl): per image, how long
# validation takes, how many of its own CodeInstances survive, and for the
# CodeInstances it carries for other packages' methods (external), how many
# survive validation and get installed. Instrumented by redefining
# `_insert_backedges` before anything loads; one fresh process per scenario:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x10_load_validation.jl adhoc|app
const SCEN = ARGS[end]
Core.eval(Base.StaticData, quote
    const _TW_STATS = Any[]
    function _insert_backedges(edges::Vector{Any}, stack::Vector{CodeInstance}, visiting::IdDict{CodeInstance,Int}, external::Bool=false)
        t0 = time_ns()
        n = length(edges); valid = 0; inserted = 0; already = 0
        bymod = Dict{String,Int}(); invalid_bymod = Dict{String,Int}()
        for i = 1:length(edges)
            codeinst = edges[i]::CodeInstance
            validation_world = get_world_counter()
            verify_method_graph(codeinst, stack, visiting, validation_world)
            @ccall jl_promote_ci_to_current(codeinst::Any, validation_world::UInt)::Cvoid
            minvalid = codeinst.min_world
            maxvalid = codeinst.max_world
            mi = get_ci_mi(codeinst)
            m = mi.def isa Method ? string(Base.moduleroot(mi.def.module)) : "?"
            if maxvalid ≥ minvalid
                valid += 1
            else
                invalid_bymod[m] = get(invalid_bymod, m, 0) + 1
            end
            if maxvalid ≥ minvalid && external
                caller = get_ci_mi(codeinst)
                inferred = @ccall jl_rettype_inferred(codeinst.owner::Any, caller::Any, minvalid::UInt, maxvalid::UInt)::Any
                if inferred !== nothing
                    already += 1
                else
                    @ccall jl_mi_cache_insert(caller::Any, codeinst::Any)::Cvoid
                    inserted += 1
                    bymod[m] = get(bymod, m, 0) + 1
                end
            end
        end
        owner = n == 0 ? "?" : (ci = edges[1]::CodeInstance; m0 = get_ci_mi(ci); m0.def isa Method ? string(Base.moduleroot(m0.def.module)) : "?")
        external && !isempty(_TW_STATS) && (owner = _TW_STATS[end][9] * " (external)")
        push!(_TW_STATS, (external, n, valid, inserted, already, (time_ns() - t0) / 1e9, bymod, invalid_bymod, owner))
        nothing
    end
end)
# package loading runs in a fixed world (Base._require_world_age, set when Base starts):
# move it past the redefinition, so that loads use the instrumented version
Base._require_world_age[] = Base.get_world_counter()
t = @elapsed if SCEN == "app"
    @eval using App
else
    @eval using TraitWorld, Columns, Reports, DataFramesWrapper, MakiePlots
    @eval using CSV, DataFrames
end
println("scenario $SCEN: loaded in ", round(t; digits = 2), " s")
stats = Base.StaticData._TW_STATS
total = sum((x[6] for x in stats); init = 0.0)
println("validation (_insert_backedges) over all images: ", round(total; digits = 2), " s in ", length(stats), " calls")
trait = ["TraitWorld", "BaseTraits", "Columns", "Rows", "Stats", "Reports", "DataFramesWrapper", "MakiePlots", "App"]
by = Dict{String,Float64}()
for x in stats
    k = replace(x[9], " (external)" => "")
    by[k] = get(by, k, 0.0) + x[6]
end
println("by the image's own package (internal and external lists together):")
for (k, v) in sort!(collect(by); by = p -> -p[2])[1:min(end, 15)]
    println("   ", rpad(k, 26), round(v; digits = 3), " s", k in trait ? "   <- trait world" : "")
end
println("trait-world images together: ", round(sum((v for (k, v) in by if k in trait); init = 0.0); digits = 3), " s")
