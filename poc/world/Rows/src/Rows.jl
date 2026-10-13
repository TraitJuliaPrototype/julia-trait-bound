# Row access, a second trait module; and the bundle of both views.
module Rows
using TraitWorld
@trait_module begin

using Columns
export RowTable, nrows, row, firstrow, Table

"What the library needs to read a table by rows."
@trait RowTable{R} begin
    nrows(r::R)::Int
    row(r::R, i::Int)::Vector{Float64}
end

@implement RowTable{Matrix{Float64}} begin
    nrows(r) = size(r, 1)
    row(r, i) = r[i, :]
end

firstrow(t::RowTable) = row(t, 1)

"A table read both ways: `t::Table` means `t::(ColTable, RowTable)`."
@trait Table{R} <: (ColTable, RowTable)

@workload begin
    firstrow([1.0 2.0; 3.0 4.0])
end

end
end
