module TW
const __trait_module__ = true          # recognized by the load filter as trait-world code
g(v::Vector{Any}) = numerator(v[1])    # abstract call: an edge to numerator(::Any) with its 3 matches
g(Any[3])                              # workload: g's code goes into the image
end
