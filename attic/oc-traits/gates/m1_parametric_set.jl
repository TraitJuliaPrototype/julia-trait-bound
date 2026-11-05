# Gate M1-e (plan §5.M1, open question 4): a parametric set — `@trait X{P}`
# and the bare-name membership (member of every instance of the set).
using Traits
include("util.jl")

@trait PSet{T}
struct PLate end

pprobe(x) = x isa PSet{Int}          # compiled before the declaration

w_old = curworld()
x = PLate()
@assert !pprobe(x) "not a member before the declaration"

@implement PLate PSet                # bare set name: member of the whole family

@assert pprobe(x) "member of PSet{Int}"
@assert (x isa PSet{String}) "bare declaration = member of every instance"
@assert !Base.invoke_in_world(w_old, pprobe, x) "old world sees no entry"

# a second, narrower declaration is independent (family work refines this at M5)
struct PLate2 end
@implement PLate2 PSet{Float64}
@assert (PLate2() isa PSet{Float64})
@assert !(PLate2() isa PSet{Int}) "narrow declaration is narrow"
@assert !(PLate2() isa PSet) "hmm — see notes: bare query against a narrow entry"

println("m1_parametric_set: OK")
