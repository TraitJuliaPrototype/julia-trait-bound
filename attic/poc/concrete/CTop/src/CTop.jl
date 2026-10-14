"Top layer: a trait-bound region whose hot loop calls down the stack."
module CTop
using TraitRegions, PrecompileTools
import CBottom, CMid2
export Series, Signal, scaled_sum

@trait Series begin
    vals(r)::Vector{Float64}
end

struct Signal; v::Vector{Float64}; end
@seal Series Signal begin
    project(t) = t.v
    vals(r)    = r
end

@warn_on_abstract @region Series begin
    function scaled_sum(t, c::CBottom.Config)
        s = 0.0
        for x in vals(t)
            s += x * CMid2.factor(c)
        end
        s
    end
    function scaled_sum_typed(t, c::CBottom.TypedConfig)
        s = 0.0
        for x in vals(t)
            s += x * CMid2.factor(c)
        end
        s
    end
end

@compile_workload begin
    sig = Signal([1.0, 2.0])
    scaled_sum(sig, CBottom.Config(0.5)); scaled_sum_typed(sig, CBottom.TypedConfig(0.5))
end
end
