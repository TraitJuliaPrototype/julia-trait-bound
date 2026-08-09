"""
LazyTables — conformer with bespoke witnesses: columns are materialized on
demand (`col i = base .* i`). The projection smuggles `n` in a header row
because witness signatures may mention only the representation. Region
workers run these bespoke witnesses through the same compiled code as
everyone else's — no new worker compilation for this package.
"""
module LazyTables

using TraitRegions, ColTables
export LazyTable

struct LazyTable
    base::Vector{Float64}
    n::Int
end

_seal!() = TraitRegions.register!(ColTable, LazyTable,
    (project = t -> Vector{Float64}[[Float64(t.n)], t.base],
     ncols   = r -> Int(r[1][1]),
     col     = (r, i) -> r[2] .* Float64(i)))

__init__() = _seal!()

end
