# A library of column statistics, written as a trait module.
module Columns
using TraitWorld
@trait_module begin

using BaseTraits
export ColTable, ncols, col, value, firstcol, colmean, colrange, meandiff, total, describe

"What the library needs from a table of Float64 columns."
@trait ColTable{R} begin
    ncols(r::R)::Int
    col(r::R, i::Int)::Vector{Float64}
    value(r::R, i::Int, j::Int)::Float64 = col(r, i)[j]      # defaults
    firstcol(r::R)::Vector{Float64} = col(r, 1)
end

# Generic: every Indexable representation whose elements are columns, through
# declarations only (BaseTraits declares Base's vectors and tuples Indexable)
@implement ColTable{R} where {R: Indexable, eltype(R) == Vector{Float64}} begin
    ncols(r) = length(r)
    col(r, i) = r[i]
end

# Specific implementations beat the generic one
@implement ColTable{Vector{Vector{Float64}}} begin
    ncols(r) = length(r)
    col(r, i) = r[i]
    value(r, i, j) = r[i][j]
end
@implement ColTable{Matrix{Float64}} begin
    ncols(r) = size(r, 2)
    col(r, i) = r[:, i]
    value(r, i, j) = r[j, i]
end

colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
colrange(t::ColTable, i::Int) = (c = col(t, i); maximum(c) - minimum(c))
meandiff(a::ColTable, b::ColTable, i::Int) = colmean(a, i) - colmean(b, i)

"One operation call per element: the benchmark of per-element cost."
function total(t::ColTable, len::Int)
    s = 0.0
    for i in 1:ncols(t), j in 1:len
        s += value(t, i, j)
    end
    return s
end

# dispatch, types first: an existing library keeps its type-based methods
describe(v::Vector{Float64}) = "a vector of $(length(v)) numbers"
describe(m::AbstractMatrix) = "a $(size(m, 1))×$(size(m, 2)) matrix"
describe(t::ColTable) = "a table of $(ncols(t)) columns"
describe(x) = "something else"

@workload begin
    v = [[1.0, 2.0], [3.0, 5.0]]
    colmean(v, 1); colrange(v, 1); meandiff(v, v, 1); total(v, 2); describe(v)
    m = [1.0 2.0; 3.0 4.0]
    colmean(m, 1); total(m, 2)
    tv = ([1.0, 2.0], [3.0, 5.0])
    colmean(tv, 1); total(tv, 2)
end

end
end
