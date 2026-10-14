"""
ChurnStorm — adversarial churn generator. Loading it defines (at RUNTIME,
via `__init__`, so the churn hits the running session, not the precompile
process): 100 new types with methods on Base functions, and 20 rounds of
method redefinition. A well-behaved trait-region stack must survive with
zero worker invalidations.
"""
module ChurnStorm

function __init__()
    for k in 1:100
        S = Symbol("Storm", k)
        @eval begin
            struct $S
                x::Vector{Float64}
            end
            Base.length(a::$S) = length(a.x)
            Base.getindex(a::$S, i::Int) = a.x[i]
            Base.sum(a::$S) = sum(a.x)
            Base.isempty(a::$S) = isempty(a.x)
        end
    end
    for k in 1:20
        @eval _churny(x) = x + $k
        Base.invokelatest(_churny, 1)
    end
    return nothing
end

end
