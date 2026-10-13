module Stats                                    # trait + region package
using TraitRegions, LinearAlgebra
export Col

weight(x::Real) = one(x)                        # a generic the worker calls

@trait Col begin
    vals(r)::Vector{Float32}
end

@region Col begin
    colsum(t) = sum(x -> weight(x) * x, vals(t)::Vector{Float32})
    # LinearAlgebra's method on Base types: Julia's own, never piracy
    sqnorm(t) = (v = vals(t)::Vector{Float32}; dot(v, v))
end
end
