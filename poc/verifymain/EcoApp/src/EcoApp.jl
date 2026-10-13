"Verified build of the ecosystem program."
module EcoApp
using TraitRegions, ColTables, ColStats, ColReports, EagerTables, LazyTables, MatrixTables, PrecompileTools
include(joinpath(@__DIR__, "..", "..", "eco_program.jl"))
@compile_workload begin
    main(["1"])                              # a representative run: EagerTable only
    verify_main(main, (Vector{String},); compile = true)
end
end
