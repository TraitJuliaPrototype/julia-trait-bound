"Workload-only build of the ecosystem program."
module EcoAppW
using TraitRegions, ColTables, ColStats, ColReports, EagerTables, LazyTables, MatrixTables, PrecompileTools
include(joinpath(@__DIR__, "..", "..", "eco_program.jl"))
@compile_workload begin
    main(["1"])                              # a representative run: EagerTable only
end
end
