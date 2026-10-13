# Spike 4: compiled trait-world code is not invalidated by definitions elsewhere.
using TraitWorld, Columns, UserTypes
m, r = Measurements([[1.0, 2.0]]), Ramp([1.0, 2.0], 2)
colmean(m, 1); colmean(r, 1); total(m, 2); total([[1.0]], 1)
log = ccall(:jl_debug_method_invalidation, Any, (Cint,), 1)
# a new trait module with a new trait over an existing function, a projection onto ColTable,
# a new representation, and an unrelated package load
@trait_module module Other
using TraitWorld, ..Columns
export Sized, size2
@trait Sized{R} begin
    Base.size(r::R)::Tuple{Int,Int}
end
@implement Sized{Matrix{Float64}}          # Base's own methods
pirate_try() = @eval @implement Sized{Vector{Float64}} begin size(r) = (length(r), 1) end
size2(t::Sized) = prod(size(t))
both(t::(Sized, ColTable)) = size2(t) + ncols(t)
end
struct Grid; m::Matrix{Float64}; end
@implement ColTable Grid project(t) = [t.m[:, j] for j in 1:size(t.m, 2)]
@implement Other.Sized Grid project(t) = t.m
Other.size2(Grid(rand(2, 3))); Other.both(Grid(rand(2, 3)))
try; Other.pirate_try(); println("BAD: pirate implementation accepted"); catch e; println("rejected: ", sprint(showerror, e)[1:160], "…"); end
using Printf, Statistics
ccall(:jl_debug_method_invalidation, Any, (Cint,), 0)
victims = [x for x in log if x isa Core.MethodInstance]
println("invalidated method instances: ", length(victims))
for v in victims
    mod = v.def isa Method ? v.def.module : nothing
    println("  ", v, "   [", mod, "]")
end
println("Columns code among them: ", count(v -> v.def isa Method && v.def.module === Columns, victims),
        "; TraitWorld machinery: ", count(v -> v.def isa Method && v.def.module === TraitWorld, victims))
