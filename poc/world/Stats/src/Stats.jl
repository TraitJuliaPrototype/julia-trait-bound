# Statistics over several traits: functions that need two views of one value,
# function arguments, and a trait with a mutating operation.
module Stats
using TraitWorld
@trait_module begin

using Columns, Rows
export overview, overview2, colmap, colsum, ColStore, setcol!, normalize!, weight, weighted

"Rule 3 in practice: a function that needs both views declares both bounds."
overview(t::(ColTable, RowTable)) = (colmean(t, 1), firstrow(t))
"The same through the bundle trait."
overview2(t::Table) = (colmean(t, 1), firstrow(t))

# Callable: erased (compiled once per signature) or fast (compiled per function type)
colmap(f::Callable{Tuple{Float64},Float64}, t::ColTable, i::Int) = map(f, col(t, i))
colsum(@specialize(f::Callable{Tuple{Float64},Float64}), t::ColTable, i::Int) = sum(f, col(t, i))

"Weights by value; the library's generic rule (a target for the piracy scenario)."
weight(x::Real) = 1.0
weighted(t::ColTable, i::Int) = sum(x -> weight(x) * x, col(t, i))

"Column storage: a trait with a mutating operation accepts only projections that share the user's data (rule 4)."
@trait ColStore{R} begin
    @mutating setcol!(r::R, i::Int, v::Vector{Float64})::Nothing
end
@implement ColStore{Vector{Vector{Float64}}} begin
    setcol!(r, i, v) = (r[i] = v; nothing)
end
normalize!(t::(ColTable, ColStore), i::Int) = (c = col(t, i); setcol!(t, i, c ./ sum(c)); nothing)

@workload begin
    m = [1.0 2.0; 3.0 4.0]
    overview(m); overview2(m)
    colmap(abs, m, 1); colsum(abs2, m, 1)
    v = [[1.0, 3.0]]
    normalize!(v, 1)
    weighted(m, 1); weighted([[1.0, 2.0]], 1)
end

end
end
