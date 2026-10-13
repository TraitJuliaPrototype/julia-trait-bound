# Plain Julia's main_plain, trimmed: plainsum(::Any) is a hole nobody can enumerate.
using TraitRegions, VMApp
function (@main)(args::Vector{String})::Cint
    VMApp.main_plain(args)
    return 0
end
