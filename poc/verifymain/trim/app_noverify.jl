# Counterfactual: the same trimmed build without verify_main's entry points.
using TraitRegions, VMApp
TraitRegions.mode!(:recompile)
function (@main)(args::Vector{String})::Cint
    VMApp.main(args)
    return 0
end
