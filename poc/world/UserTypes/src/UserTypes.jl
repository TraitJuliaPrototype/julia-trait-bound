# An ordinary package whose types join Columns' trait in the three ways of the note.
module UserTypes
using TraitWorld, Columns
using PrecompileTools: @compile_workload
export Measurements, Ramp, Reversed

# 1. Project onto a representation the library implements: one line.
struct Measurements; series::Vector{Vector{Float64}}; end
@implement ColTable Measurements project(t) = t.series

# 2. Be your own representation, with your own implementation (trait-bound code).
struct Ramp; base::Vector{Float64}; n::Int; end      # column i is base .* i, never stored
@implement ColTable{Ramp} begin
    ncols(r) = r.n
    col(r, i) = r.base .* i
    value(r, i, j) = r.base[j] * i
end

# 3. Share the library's representation, with operations of your own (dynamic).
struct Reversed; cols::Vector{Vector{Float64}}; end
@implement ColTable Reversed dynamic begin
    project(t) = t.cols
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
end

# rule 7: the conformer's image holds what it brings (projections, Ramp's workers)
@compile_workload begin
    m, r = Measurements([[1.0, 2.0]]), Ramp([1.0, 2.0], 2)
    colmean(m, 1); colmean(r, 1); colmean(Reversed([[1.0, 2.0]]), 1); meandiff(m, r, 1)
    total(m, 2); total(r, 2); colrange(m, 1); colrange(r, 1)
end

end
