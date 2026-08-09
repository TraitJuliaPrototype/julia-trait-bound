"""
ColTables — the interface package: one trait, canonical representation
`Vector{Vector{Float64}}`. Deliberately tiny and dependency-light; its
stability is the point.
"""
module ColTables

using TraitRegions
export ColTable

@trait ColTable begin
    ncols(r)::Int
    col(r, i::Int)::Vector{Float64}
end

end
