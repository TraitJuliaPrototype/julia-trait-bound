"Top layer: a trait module in concrete mode whose hot loop calls down the stack."
module CTop
using TraitWorld
@warn_on_abstract @trait_module begin
import CBottom, CMid2
export Series, vals, scaled_sum, scaled_sum_typed

@trait Series{R} begin
    vals(r::R)::Vector{Float64}
end
@implement Series{Vector{Float64}} begin
    vals(r) = r
end

function scaled_sum(t::Series, c::CBottom.Config)
    s = 0.0
    for x in vals(t)
        s += x * CMid2.factor(c)
    end
    s
end
function scaled_sum_typed(t::Series, c::CBottom.TypedConfig)
    s = 0.0
    for x in vals(t)
        s += x * CMid2.factor(c)
    end
    s
end

@workload begin
    v = [1.0, 2.0]
    scaled_sum(v, CBottom.Config(0.5)); scaled_sum_typed(v, CBottom.TypedConfig(0.5))
end
end
end
