# juliac build of the full application, without trimming (demo 2 step 2):
# DataFrames and CairoMakie included, behind their interfaces.
using TraitWorld
import App
function (@main)(args::Vector{String})::Cint
    App.main(args)
    return 0
end
