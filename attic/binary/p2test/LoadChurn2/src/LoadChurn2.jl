module LoadChurn2
using Helper
# DOMINATED newcomer: intersects every inner(::Float64) edge but can never
# win (inner(::AbstractFloat) is more specific). A spurious kill by the
# strict criterion; kept by the dominance exception.
Helper.inner(x::Real) = x + 0.0
end
