# P1b test — task-scoped sealed dispatch: DYNAMIC calls from a sealed frame
# resolve through the filtered matcher, closing X11's residual hole (a
# pre-compilation pirate reached through a Function-typed witness slot).
#   binary/julia/julia --startup-file=no binary/test_sealed_dispatch.jl
module RegionCode
    const WIT = Base.RefValue{Any}(sort)   # dynamic witness slot
    _medw(c::Vector{Float64}) = (cs = WIT[](c)::Vector{Float64}; cs[(length(cs) + 1) ÷ 2])
end

set_universe(u) = ccall(:jl_set_universe_filter, Cvoid, (Any,), u)
sealed_on() = ccall(:jl_set_sealed_mode, Int8, (Int8,), Int8(1))
sealed_off(old) = ccall(:jl_set_sealed_mode, Int8, (Int8,), old)

function sealed_call(f, args...)
    old = sealed_on()
    try
        return f(args...)
    finally
        sealed_off(old)
    end
end

data = [5.0, 1.0, 4.0, 2.0, 3.0]
live0 = RegionCode._medw(data)
println("pre-pirate: _medw = ", live0, " (expect 3.0)")

# pirate FIRST — before any sealed compilation or call. Time-based pinning
# cannot exclude it; only territory can.
Base.sort(v::Vector{Float64}) = v

const UNIVERSE = Any[Base, Core, Base.Compiler, RegionCode]

# warm everything OUTSIDE sealed mode (PoC scope: compilation inside sealed
# frames is unsupported until P2's universe-keyed caches)
sealed_call(RegionCode._medw, data)   # compiles sealed_call machinery + target (unfiltered: no universe set yet)
live_val = RegionCode._medw(data)

set_universe(UNIVERSE)
sealed_val = sealed_call(RegionCode._medw, data)
ccall(:jl_set_universe_filter, Cvoid, (Ptr{Cvoid},), C_NULL)

println("live _medw   = ", live_val, "  (pirate applies via dynamic slot: ", live_val != live0, ")")
println("sealed _medw = ", sealed_val, "  (PRE-compile pirate excluded on a DYNAMIC call: ", sealed_val == live0, ")")

ok = live_val != live0 && sealed_val == live0
println(ok ? "P1b SEALED DISPATCH: PASS — X11's residual hole closed natively" :
             "P1b SEALED DISPATCH: inspect")
exit(ok ? 0 : 1)
