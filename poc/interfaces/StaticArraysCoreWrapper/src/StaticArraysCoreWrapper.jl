# StaticArraysCoreWrapper: the trait wrapper of StaticArraysCore (the note, "Trait
# wrappers"). StaticArraysCore defines the static array types; their behaviour
# lives in StaticArrays (with the core alone an `SArray` has no `size`). The
# wrapper names StaticArrays as the implementation it delegates to and depends
# on it, so StaticArrays is loaded whenever an SArray can enter the trait world,
# and its methods at the core's types are the core's (rule 3).
module StaticArraysCoreWrapper
using TraitWorld
import StaticArraysCore, StaticArrays
@trait_wrapper StaticArraysCore StaticArrays
end
