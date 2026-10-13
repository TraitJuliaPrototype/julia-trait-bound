# A delegate: triggered by GridLib, implementing ColT for GridLib's representation.
module ColsDGridExt
using ColsD, GridLib, TraitWorld
@implement ColT{GridRep} begin
    n(r) = size(r.m, 2)
end
# rule 7: code for ColsD and GridLib together lives in the package that depends on both
TraitWorld.@workload begin
    twice(GridRep(zeros(2, 3)))
end
end
