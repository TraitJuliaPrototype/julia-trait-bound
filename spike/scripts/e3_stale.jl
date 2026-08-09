# E3a — stale-pointer probe (M0 gate c): after redefining a witness method,
# does the FunctionWrapper in the seal execute stale code?
# Run: julia +1.11.7 --project=. e3_stale.jl
using M0Spike

struct T1
    cols::ColR
end
t = T1([[1.0, 2.0, 3.0], [10.0, 20.0, 30.0]])

wit_project(t) = t.cols
wit_ncols(r) = length(r)
wit_col(r, i) = r[i]

register_seal!(T1; project = wit_project, ncols = wit_ncols, col = wit_col)

v1 = colmean(t, 1)
println("before redefinition: colmean = ", v1, "   (expect 2.0)")

# Redefine the witness method (interactive-session edit).
wit_col(r, i) = r[i] .* 100.0

v2 = colmean(t, 1)
println("after redefinition:  colmean = ", v2, "   (200.0 ⇒ fresh, 2.0 ⇒ STALE)")

# The prototype's remedy: rebuild the wrapper table (re-register).
empty!(M0Spike.SEALS)
register_seal!(T1; project = wit_project, ncols = wit_ncols, col = wit_col)
v3 = colmean(t, 1)
println("after table rebuild: colmean = ", v3, "   (expect 200.0)")

println(v2 == 200.0 ? "RESULT: wrappers track redefinition (no stale window here)" :
                      "RESULT: STALE-POINTER WINDOW CONFIRMED — wrapper executed old code; rebuild fixes it: " * string(v3))
