# An ordinary package that pirates Base (writeup/poc3-plan.md §1, demo 1 step 6):
# it owns neither `sum` nor `Vector{Int8}`. It depends on nothing, so it can
# load before the trait stack: the seal's load must find it.
module BasePirate
Base.sum(x::Vector{Int8}) = Int8(0)
end
