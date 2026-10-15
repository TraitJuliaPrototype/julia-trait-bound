# The delegate of rule 5: Columns owns ColTable but not DataFrame, so it lets
# this extension, loaded whenever DataFrames is, conform DataFrames' type to
# its trait (writeup/poc3-plan.md §9, correction 1). The projection returns
# the DataFrame's own column vectors in a fresh outer vector: Columns'
# representation `Vector{Vector{Float64}}`, shared, not copied. A column of
# any other type is refused by name: the representation decides by its type
# (rule 4), so a DataFrame is a ColTable only when every column is a
# Vector{Float64}, and the refusal is at the boundary, never inside.
module ColumnsDataFramesExt
using Columns, DataFrames, TraitWorld

function columns(df::DataFrame)
    out = Vector{Vector{Float64}}(undef, ncol(df))
    for i in 1:ncol(df)
        c = df[!, i]
        c isa Vector{Float64} || throw(TraitBoundError(
            "column `$(names(df)[i])` of the DataFrame is a $(typeof(c)): a ColTable needs Vector{Float64} columns"))
        out[i] = c
    end
    return out
end
@implement ColTable DataFrame project(df) = columns(df)

# rule 7: the conformer's image holds the projection and the entry's builder for DataFrame
TraitWorld.@workload begin
    df = DataFrame(a = [1.0, 2.0], b = [3.0, 5.0])
    colmean(df, 1); colrange(df, 2); meandiff(df, df, 1); total(df, 2)
end
end
