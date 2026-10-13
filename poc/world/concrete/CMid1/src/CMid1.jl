"Middle layer 1."
module CMid1
using TraitWorld
@trait_module begin
import CBottom
gain(c) = CBottom.scale(c) * 2
end
end
