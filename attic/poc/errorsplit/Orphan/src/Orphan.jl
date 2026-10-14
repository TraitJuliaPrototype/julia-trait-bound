module Orphan                   # seals a foreign type for a foreign trait
using TraitRegions, Stats
@seal Col Vector{Float32} begin
    project(t) = t
    vals(r)    = r
end
end
