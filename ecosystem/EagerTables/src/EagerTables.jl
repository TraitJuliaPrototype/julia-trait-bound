"""
EagerTables — conformer package: struct-of-vectors table, trivial accessor
witnesses onto the canonical representation. Knows nothing about any region
package. Seals in `__init__` (Rung-1 friction: top-level seals into another
package's registry are discarded at pkgimage save).
"""
module EagerTables

using TraitRegions, ColTables
export EagerTable

struct EagerTable
    cols::Vector{Vector{Float64}}
end

# Seals are methods (P0): a top-level @seal serializes into THIS package's
# pkgimage like any external method extension. No __init__ replay.
@seal ColTable EagerTable begin
    project(t) = t.cols
    ncols(r)   = length(r)
    col(r, i)  = r[i]
end

end
