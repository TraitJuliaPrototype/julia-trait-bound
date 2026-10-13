module Dominated                # piratical, but never the target of a call
using Stats
Stats.weight(x::Number) = 3one(x)
end
