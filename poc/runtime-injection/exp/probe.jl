Base.include(Base.StaticData, "/home/hellmann/Repos/julia-trait-bound/attic/binary/julia/base/staticdata.jl")
const CNT = Ref(0)
@eval Base.StaticData function _tw_protected(codeinst::CodeInstance)
    $(CNT)[] += 1
    _tw_filter_on() || return false
    def = get_ci_mi(codeinst).def
    return def isa Method && _tw_in_trait_world(def.module)
end
Base._require_world_age[] = Base.get_world_counter()
@eval using CSV
println("verify_method calls via _tw_protected: ", CNT[], "  filter flag: ", Base.StaticData._tw_load_filter[])
m = which(Base.StaticData.insert_backedges, (Vector{Any}, Union{Nothing,Vector{Any}}, Vector{Any}, Vector{Any}))
println(m, " world ", m.primary_world)
