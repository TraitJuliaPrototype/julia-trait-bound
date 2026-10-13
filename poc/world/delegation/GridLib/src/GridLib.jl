# A trait module that owns two representation types.
module GridLib
using TraitWorld
@trait_module begin
export GridRep, GridRep2
struct GridRep; m::Matrix{Float64}; end
struct GridRep2; m::Matrix{Float64}; end
end
end
