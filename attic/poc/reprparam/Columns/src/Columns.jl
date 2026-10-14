"Column statistics, written once against a trait (the library file of the design note's example)."
module Columns
using TraitRegions, PrecompileTools
export ColTable, colmean, colrange, total

@trait ColTable{R} begin                       # what the library needs from a table
    ncols(r::R)::Int
    col(r::R, i::Int)::Vector{Float64}
    value(r::R, i::Int, j::Int)::Float64        # one element: a fine-grained operation
end

@implement ColTable{Vector{Vector{Float64}}} begin   # the library's own representation
    ncols(r) = length(r)
    col(r, i) = r[i]
    value(r, i, j) = r[i][j]
end

@region ColTable begin                         # library code, compiled per representation
    colmean(t, i::Int) = (c = col(t, i); sum(c) / length(c))
    colrange(t, i::Int) = (c = col(t, i); maximum(c) - minimum(c))
    function total(t, len::Int)                 # one call of `value` per element
        s = 0.0
        for i in 1:ncols(t), j in 1:len
            s += value(t, i, j)
        end
        s
    end
end

# Compiled into this package's image: the workers at the library's representation,
# for seals that use the implementation and for seals with operations of their own.
struct _Implemented; cols::Vector{Vector{Float64}}; end
@seal ColTable _Implemented project(t) = t.cols
struct _OwnOps; cols::Vector{Vector{Float64}}; end
@seal ColTable _OwnOps begin
    project(t) = t.cols
    ncols(r) = length(r)
    col(r, i) = r[i]
    value(r, i, j) = r[i][j]
end
@compile_workload begin
    for t in (_Implemented([[1.0, 2.0]]), _OwnOps([[1.0, 2.0]]))
        colmean(t, 1); colrange(t, 1); total(t, 2)
    end
end
end
