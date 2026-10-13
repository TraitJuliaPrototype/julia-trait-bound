# A user of Columns (the user file of the design note's example): three ways
# to make a type usable by the library.
#   julia --project=poc/reprparam/env poc/reprparam/analysis.jl
using Columns, TraitRegions

# 1. Project onto a representation the library implements: one line, no new compiled code.
struct Measurements; series::Vector{Vector{Float64}}; end
@seal ColTable Measurements project(t) = t.series

# 2. Be your own representation, with an implementation of your own.
struct Ramp; base::Vector{Float64}; n::Int; end     # column i is base .* i, never stored
@implement ColTable Ramp begin
    ncols(r) = r.n
    col(r, i) = r.base .* i
    value(r, i, j) = r.base[j] * i
end

# 3. Share the library's representation, with operations of your own.
struct Reversed; cols::Vector{Vector{Float64}}; end
@seal ColTable Reversed begin
    project(t) = t.cols
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
    value(r, i, j) = r[end - i + 1][j]
end

for t in (Measurements([[1.0, 2.0], [3.0, 5.0]]), Ramp([1.0, 2.0], 2), Reversed([[1.0, 2.0], [3.0, 5.0]]))
    println(rpad(nameof(typeof(t)), 13), "mean of column 1: ", colmean(t, 1), "   range of column 2: ", colrange(t, 2))
end
