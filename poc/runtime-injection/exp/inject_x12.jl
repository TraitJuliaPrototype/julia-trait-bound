# Stock Julia 1.12.2: install the load-time half of the trait-world filter at run time,
# by including the patched base/staticdata.jl into Base.StaticData (no rebuild), then run x12.
if get(ENV, "INJECT", "1") == "1"
    t_inj = @elapsed Base.include(Base.StaticData, "/home/hellmann/Repos/julia-trait-bound/attic/binary/julia/base/staticdata.jl")
    Base._require_world_age[] = Base.get_world_counter()   # the loader runs in the require world: let it see the new methods
    println("injected patched staticdata.jl in ", round(t_inj; digits = 3), " s")
end
include("/home/hellmann/Repos/julia-trait-bound/poc/interfaces/scripts/x12_viewcache.jl")
isdefined(Base.StaticData, :_tw_skipped) && println("load filter: image edges kept ", Base.StaticData._tw_skipped[])
