# A trait module that delegates implementations for other packages' representations to extensions.
module ColsD
using TraitWorld
@trait_module begin
export ColT, n, twice
@trait ColT{R} begin
    n(r::R)::Int
end
twice(t::ColT) = 2 * n(t)
end
end
