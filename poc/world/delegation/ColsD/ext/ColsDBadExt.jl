# Triggered by GridLib and OtherD, but its method mentions only GridLib's type:
# whether a call sees it would depend on whether OtherD happens to be loaded.
module ColsDBadExt
using ColsD, GridLib, OtherD, TraitWorld
@implement ColT{GridRep2} begin
    n(r) = size(r.m, 2)
end
end
