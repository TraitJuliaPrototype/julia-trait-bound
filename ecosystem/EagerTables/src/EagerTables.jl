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

_seal!() = TraitRegions.register!(ColTable, EagerTable,
    (project = t -> t.cols,
     ncols   = r -> length(r),
     col     = (r, i) -> r[i]))

__init__() = _seal!()

end
