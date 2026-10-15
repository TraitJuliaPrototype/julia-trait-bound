# ColorTypesWrapper: the trait wrapper of ColorTypes (the note, "Trait wrappers").
# ColorTypes defines the color types; Colors (parsing, conversions),
# ColorVectorSpace (arithmetic, only filling holes) and ImageCore implement
# them. The wrapper names the three and depends on them. ImageCore brings
# OffsetArrays, which redefines `getindex` for Base's ranges: piracy of Julia,
# tolerated here (the Project.toml) until fixed upstream.
module ColorTypesWrapper
using TraitWorld
import ColorTypes, Colors, ColorVectorSpace, ImageCore
@trait_wrapper ColorTypes Colors ColorVectorSpace ImageCore
end
