# AC-2 (old G1.5): calls into Base, LinearAlgebra and Printf from marked code
# compute plain Julia's values, and the calls at concrete splits are recorded as
# fact dispatch edges (the (sig, callee) pair the C7/invalidation machinery uses).
include("ac_util.jl")
using LinearAlgebra, Printf

const m2 = [2.0 0.0; 0.0 3.0]

cdet2(m::Matrix{Float64}) = det(m)
cfmt2(m::Matrix{Float64}) = sprint(io -> (@printf(io, "%.3f", 1.0)))
mark!(cdet2)
mark!(cfmt2)

@assert cdet2(m2) == 6.0 == det(m2) "det from marked code"
@assert cfmt2(m2) == "1.000" "Printf from marked code"

ci = only([c for c in all_cis(cdet2) if c.min_world > 0])
hasdet = any(1:length(ci.edges)-1) do i
    s = ci.edges[i]
    s isa DataType && s.name === Tuple.name && s.types[1] === typeof(det) &&
        (ci.edges[i+1] isa Core.MethodInstance || ci.edges[i+1] isa Core.CodeInstance)
end
@assert hasdet "det call recorded a (sig, callee) fact edge: $(collect(ci.edges))"
@assert Compiler.decode_effects(ci.ipo_purity_bits).nortsite "no run-time site in this frame"

# the printf path reaches Printf through closures; print the census, pin the value
cif = only([c for c in all_cis(cfmt2) if c.min_world > 0])
println("OBSERVED cfmt edges: ", length(cif.edges), " items, rettype=", cif.rettype)

ac_finish(@__FILE__)
