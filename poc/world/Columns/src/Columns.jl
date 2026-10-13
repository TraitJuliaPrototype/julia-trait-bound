# A library of column statistics, written as a trait module.
module Columns
using TraitWorld
@trait_module begin

export ColTable, ncols, col, value, colmean, colrange, meandiff, total

"What the library needs from a table of Float64 columns."
@trait ColTable{R} begin
    ncols(r::R)::Int
    col(r::R, i::Int)::Vector{Float64}
    value(r::R, i::Int, j::Int)::Float64 = col(r, i)[j]      # a default
end

# the library's own representation
@implement ColTable{Vector{Vector{Float64}}} begin
    ncols(r) = length(r)
    col(r, i) = r[i]
    value(r, i, j) = r[i][j]
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

@workload begin
    v = [[1.0, 2.0], [3.0, 5.0]]
    colmean(v, 1); colrange(v, 1); meandiff(v, v, 1); total(v, 2)
end

end
end
