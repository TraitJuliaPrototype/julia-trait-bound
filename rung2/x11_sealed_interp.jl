# X11 — Stage A: territory-sealed workers (Julia 1.12).
#   julia +1.12.2 --startup-file=no x11_sealed_interp.jl
include(joinpath(@__DIR__, "sealed_workers.jl"))
using .SealedWorkers

# Region code lives in an ENROLLED module; Main (user/pirate space) does not.
module RegionCode
    _med(c::Vector{Float64}) = (cs = sort(c); cs[(length(cs) + 1) ÷ 2])
    _bad(c::Vector{Float64}) = Main.outside_helper(c) + 1.0   # calls non-universe code
end

data = [5.0, 1.0, 4.0, 2.0, 3.0]
live0 = RegionCode._med(data)
println("before pirate: live _med = ", live0, "   (expect 3.0)")

# THE PIRATE IS DEFINED FIRST — before any sealed compilation
Base.sort(v::Vector{Float64}) = v

UNIVERSE = (Base, Core, RegionCode)   # TraitCore proxy + region; Main is NOT enrolled

oc = SealedWorkers.compile_sealed(RegionCode._med, (Vector{Float64},), UNIVERSE)
sealed_val = oc(data)
live_val = RegionCode._med(data)
println("after pirate:  live _med = ", live_val, "   (pirate applies: ", live_val != live0, ")")
println("               SEALED oc = ", sealed_val,
        "   (pirate excluded by territory, though defined BEFORE compilation: ",
        sealed_val == live0, ")")

# closure rule, enforced: a worker that calls non-universe code fails loudly
outside_helper(c::Vector{Float64}) = c[1]
bad_result = try
    bad_oc = SealedWorkers.compile_sealed(RegionCode._bad, (Vector{Float64},), UNIVERSE)
    bad_oc(data)
    :ran_anyway
catch e
    e isa MethodError ? :method_error : :other_error
end
println("closure rule:  worker calling non-universe code → ", bad_result)

println(sealed_val == live0 && live_val != live0 && bad_result == :method_error ?
        "X11 VERDICT: PASS — sealed resolution (territory) + constructive closure rule" :
        "X11 VERDICT: inspect")
