# An ordinary package that pirates: it owns neither Stats.weight nor Float64.
module Pirate
using Stats
Stats.weight(x::Float64) = 2.0
end
