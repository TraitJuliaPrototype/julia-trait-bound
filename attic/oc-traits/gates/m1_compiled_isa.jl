# Gate M1-b (plan §5.M1, review H3's tests): isa, subtype and cast questions
# compiled BEFORE a late membership — same CodeInstances answer both worlds.
using Traits
include("util.jl")

@trait X2
struct Late2 end

isaq(x) = x isa X2                    # isa with a concrete static type
subq() = Late2 <: X2                  # datatype fast path, as a value question
tupq() = Tuple{Late2, Int} <: Tuple{X2, Int}   # parameter-wise through a tuple
castq(x) = x isa Late2 ? x::X2 : error("not Late2")   # typeassert on an S

w_old = curworld()
x = Late2()
@assert !isaq(x) && !subq() && !tupq()
try
    castq(x)
    error("cast must fail before the membership")
catch err
    err isa TypeError || rethrow()
end

@implement Late2 X2

@assert isaq(x) "isa true in the new world (old CI, runtime check)"
@assert subq() && tupq() "subtype questions true after the declaration"
@assert castq(x) === x "the cast goes through"

@assert !Base.invoke_in_world(w_old, isaq, x) "isa false in the old world"
@assert !Base.invoke_in_world(w_old, subq) "subtype false in the old world"
@assert !Base.invoke_in_world(w_old, tupq)
try
    Base.invoke_in_world(w_old, castq, x)
    error("cast must still fail in the old world")
catch err
    err isa TypeError || rethrow()
end

println("m1_compiled_isa: OK")
