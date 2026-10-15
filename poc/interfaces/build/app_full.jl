# juliac build of the full application, without trimming (demo 2 step 2):
# DataFrames (wrapped) and CairoMakie (behind declared calls) included.
using TraitWorld
import App
function (@main)(args::Vector{String})::Cint
    App.main(args)
    return 0
end
