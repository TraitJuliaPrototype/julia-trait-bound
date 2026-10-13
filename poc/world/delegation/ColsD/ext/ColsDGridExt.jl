# A delegate: triggered by GridLib, implementing ColT for GridLib's representation.
module ColsDGridExt
using ColsD, GridLib, TraitWorld
@implement ColT{GridRep} begin
    n(r) = size(r.m, 2)
end
end
