module Pirate                   # owns neither weight nor Float32
using Stats
Stats.weight(x::Float32) = 2one(x)
end
