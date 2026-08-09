module LoadChurn
using Helper
# a more-specific method for the generic every Helper fn calls: defining it
# invalidates all 100 CIs — including User's tagged, natively-cached ones
Helper.inner(x::Float64) = x
end
