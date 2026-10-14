"Verified build: the usual workload plus `verify_main(...; compile = true)`."
module VMApp
using TraitRegions, Stats, MyTable, PrecompileTools
include(joinpath(@__DIR__, "..", "..", "program.jl"))
@compile_workload begin
    main(["1"]); main_plain(["1"])          # a representative run: MyTab only
    verify_main(main, (Vector{String},); compile = true)
end
end
