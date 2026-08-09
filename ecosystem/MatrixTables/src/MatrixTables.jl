"""
MatrixTables — conformer introducing a NOVEL representation
(`Matrix{Float64}`): every region op needs a second worker instance per op,
owned by THIS package's pkgimage via `precompile_seal` in its workload
(which is why this conformer, unlike EagerTables, depends on ColStats).
`col` materializes a column view — the priced return-normalization cost.
"""
module MatrixTables

using TraitRegions, ColTables
using ColStats   # dependency exists to own precompiled workers for the new R
using PrecompileTools: @compile_workload
export MatTable

struct MatTable
    m::Matrix{Float64}
end

@seal ColTable MatTable begin
    project(t) = t.m
    ncols(r)   = size(r, 2)
    col(r, i)  = r[:, i]
end

@compile_workload begin
    TraitRegions.reinit(ColStats)
    d = MatTable([1.0 2.0; 3.0 4.0])
    ColStats.colmean(d, 1); ColStats.summarize(d)
    precompile_seal(ColTable, MatTable)
end

end
