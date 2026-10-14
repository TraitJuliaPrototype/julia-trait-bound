"Workload-only build: the usual representative run, nothing enumerated."
module VMAppW
using TraitRegions, Stats, MyTable, PrecompileTools
include(joinpath(@__DIR__, "..", "..", "program.jl"))
@compile_workload begin
    main(["1"]); main_plain(["1"])          # a representative run: MyTab only
end
end
