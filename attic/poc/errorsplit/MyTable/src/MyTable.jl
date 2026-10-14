module MyTable                                  # conformer with a new representation
using TraitRegions, Stats, PrecompileTools
struct MyTab; cols::Vector{Float32}; end
@seal Col MyTab begin
    project(t) = t.cols
    vals(r)    = r
end
@compile_workload begin
    t = MyTab(Float32[1, 2, 3])
    Stats.colsum(t); Stats.sqnorm(t)
    precompile_seal(Col, MyTab)
end
end
