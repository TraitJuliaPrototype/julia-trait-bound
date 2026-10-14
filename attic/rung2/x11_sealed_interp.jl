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

# -- the reviewer's counterexample: DYNAMIC calls escape the sealed table ----
module RegionCode2
    const WIT = Base.RefValue{Any}(sort)          # Function-typed witness slot
    _medw(c::Vector{Float64}) = (cs = WIT[](c)::Vector{Float64}; cs[(length(cs) + 1) ÷ 2])
end
oc2 = SealedWorkers.compile_sealed(RegionCode2._medw, (Vector{Float64},), (Base, Core, RegionCode2))
leak = oc2(data)   # dynamic call; sort-pirate PREDATES oc2's compilation world
println("PRE-compile pirate + dynamic call, table-sealed only: ", leak,
        "  (leaks — residual hole: ", leak != live0, ")")

# -- but the OC's own creation world covers POST-compile pirates, even dynamic:
Base.reverse(v::Vector{Float64}) = v              # second pirate, AFTER oc2 was compiled
RegionCode2.WIT[] = reverse
data2 = [9.0, 1.0, 8.0, 2.0]                      # even length: reversal moves the median slot
direct = RegionCode2._medw(data2)                 # plain call, live world → pirate applies
inoc = oc2(data2)                                 # same dynamic call inside the OC
println("POST-compile pirate (reverse): direct call = ", direct,
        " | inside sealed OC = ", inoc,
        "  (OC world-pins dynamic calls at creation: ", inoc != direct, ")")

println(sealed_val == live0 && live_val != live0 && bad_result == :method_error &&
        leak != live0 && inoc != direct ?
        "X11 VERDICT: territory seals static calls (even pre-compile pirates); the OC creation world seals dynamic calls against post-compile pirates; RESIDUAL HOLE = pre-compile pirate reached dynamically — closed by compiling sealed workers at registration time" :
        "X11 VERDICT: inspect")
