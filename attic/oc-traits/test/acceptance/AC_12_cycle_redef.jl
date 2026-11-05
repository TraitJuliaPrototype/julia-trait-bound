# AC-12 (old G1.15): a cycle's callee redefined deep inside invalidates the
# marked callers — the bare MI edges through the SCC are unchanged by the facts
# record (§3c's skips register NOTHING new and remove nothing). Plain twin
# included; the direct (native) partner call is checked too.
include("ac_util.jl")

cy_h(x::Int) = 1
cy_f(n::Int) = n <= 0 ? cy_h(n) : cy_g(n - 1)
cy_g(n::Int) = n <= 0 ? cy_h(n) : cy_f(n - 1)
cyc12() = cy_f(5)
mark!(cy_f)
mark!(cy_g)
mark!(cy_h)

c0 = (cyc12(), cy_g(4))
cy_h(x::Int) = 2
c1 = (cyc12(), cy_g(4))
@assert c0 == (1, 1) "before: $c0"
@assert c1 == (2, 2) "G1.15: the deep redefinition moved through the cycle: $c1"

ac_finish(@__FILE__)
