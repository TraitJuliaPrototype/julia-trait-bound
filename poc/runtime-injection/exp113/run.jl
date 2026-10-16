# usage: julia run.jl plain|inject [noout]; Out (owns T, defines numerator(::T)) loads before TW (a trait module)
const INJ = ARGS[1] == "inject"
const R = VERSION >= v"1.13-" ? Base.Compiler.ReinferUtils : Base.StaticData   # where image validation lives
INJ && Base.include(R, ENV["PATCHED"])
# each step a top-level statement of its own, so that it runs in the world after the redefinitions
INJ && VERSION >= v"1.13-" && Base.Compiler.activate_codegen!()   # 1.13 validates images in the typeinf world
INJ && (Base._require_world_age[] = Base.get_world_counter())     # the loader runs in the require world
a2 = get(ARGS, 2, ""); a2 == "pirate" ? (using Pir) : a2 == "noout" || (using Out)
using TW
m = which(TW.g, (Vector{Any},))
valid = any(ci -> ci.max_world == typemax(UInt), (mi.cache for mi in Base.specializations(m) if isdefined(mi, :cache)))
kept = isdefined(R, :_tw_skipped) ? R._tw_skipped[] : 0
println(VERSION, " ", join(ARGS, " "), ": TW.g's cached code valid after load = ", valid, "; edges kept by the filter ", kept)
