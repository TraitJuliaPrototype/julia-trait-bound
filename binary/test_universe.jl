# Test the patched binary's native universe filter (sealed resolution below
# the matcher). Run with the PATCHED julia:
#   binary/julia/julia --startup-file=no binary/test_universe.jl
module RegionCode
    _med(c::Vector{Float64}) = (cs = sort(c); cs[(length(cs) + 1) ÷ 2])
end

data = [5.0, 1.0, 4.0, 2.0, 3.0]
live0 = RegionCode._med(data)
println("pre-pirate: _med = ", live0, " (expect 3.0)")

Base.sort(v::Vector{Float64}) = v          # pirate in Main, MORE SPECIFIC than Base's

# --- the native filter: Main is not enrolled --------------------------------
const UNIVERSE = Any[Base, Core, RegionCode]   # rooted here, as the API requires
set_universe(u) = ccall(:jl_set_universe_filter, Cvoid, (Any,), u)
clear_universe() = ccall(:jl_set_universe_filter, Cvoid, (Ptr{Cvoid},), C_NULL)

# 1) matcher-level check: with the filter on, the pirate does not exist and —
#    crucially — Base's shadowed sort IS found (the A5 case, fixed natively)
set_universe(UNIVERSE)
ms = Base._methods_by_ftype(Tuple{typeof(sort), Vector{Float64}}, -1, Base.get_world_counter())
clear_universe()
mods = [m.method.module for m in ms]
println("filtered match modules: ", mods,
        "  (pirate excluded: ", !(Main in mods), ", shadowed Base method recovered: ", any(m -> m !== Main, mods), ")")

# 2) end-to-end: compile _med under the filter (crude global scope for PoC),
#    then run the result vs the live pirated world
set_universe(UNIVERSE)
sealed_ir, _ = only(Base.code_ircode(RegionCode._med, (Vector{Float64},)))
clear_universe()
sealed_ir_c = Core.Compiler.copy(sealed_ir)
sealed_ir_c.argtypes[1] = Tuple{}
oc = Core.OpaqueClosure(sealed_ir_c; do_compile = true)
sealed_val = oc(data)
live_val = RegionCode._med(data)
println("live _med = ", live_val, " (pirate applies: ", live_val != live0, ")")
println("sealed oc = ", sealed_val, " (pirate excluded natively: ", sealed_val == live0, ")")

ok = !(Main in mods) && any(m -> m !== Main, mods) && live_val != live0 && sealed_val == live0
println(ok ? "NATIVE UNIVERSE FILTER: PASS" : "NATIVE UNIVERSE FILTER: inspect")
exit(ok ? 0 : 1)
