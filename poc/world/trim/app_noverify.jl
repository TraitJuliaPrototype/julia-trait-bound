# The same program without verify_main: trim cannot see the entries' dynamic targets.
using TraitWorld
import App
function (@main)(args::Vector{String})::Cint
    App.main(args)
    return 0
end
