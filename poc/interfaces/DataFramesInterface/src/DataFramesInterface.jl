# DataFramesInterface: the interface package to DataFrames.jl (writeup/poc3-plan.md
# §3.1, §4, §9). DataFrames is a data source: a DataFrame enters Columns' trait
# through the projection in Columns' own extension, ColumnsDataFramesExt, which
# loads with DataFrames (rule 5: an interface owns neither the trait nor the
# type). This package wraps DataFrames' tree (sealing and tolerations, M6) and
# declares the calls back: a constructor returning a handle, and queries on it.
module DataFramesInterface
using TraitWorld
import DataFrames
@interface_package DataFrames

@trait_module module Frames
using TraitWorld, Columns
export Frame, frame, nrows_of, ncols_of

"A DataFrame held by trait-world code: opaque, a value for the next declared call."
@handle Frame

"A DataFrame built above from trait-world columns, sharing them."
frame(names::Vector{String}, cols::Vector{Vector{Float64}}) =
    @call DataFrames.DataFrame(cols, names; copycols = false)::Frame
"A table's columns as a DataFrame: what the operations return goes up, the trait object never does."
frame(names::Vector{String}, t::ColTable) = frame(names, [col(t, i) for i in 1:ncols(t)])
nrows_of(f::Frame) = @call DataFrames.nrow(f)::Int
ncols_of(f::Frame) = @call DataFrames.ncol(f)::Int

@workload begin
    h = frame(["a", "b"], [[1.0, 2.0], [3.0, 4.0]])
    nrows_of(h); ncols_of(h)
    frame(["a", "b"], [[1.0], [2.0]]); frame(["a", "b"], [1.0 2.0; 3.0 4.0])
end
end
using .Frames: Frame, frame, nrows_of, ncols_of
export Frame, frame, nrows_of, ncols_of

# rule 7: the entry of `frame` at the DataFrame projection, reached from ordinary code
TraitWorld.@workload begin
    h = frame(["a", "b"], DataFrames.DataFrame(a = [1.0, 2.0], b = [3.0, 4.0]))
    nrows_of(h)
end
end
