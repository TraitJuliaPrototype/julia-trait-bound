module FakeImpl                 # declares it implements Stats: an owner
using Stats
Stats.weight(x::Float32) = 2one(x)
end
