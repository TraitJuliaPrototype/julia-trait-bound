# Gate for review finding M1: a PARAMETRIC member pattern declared through the
# library (@implement Mem{T} Set{T}) must bind narrow, not answer as the bare
# family (tvar identity between pattern and instance, review p10 repro).
using Traits
include("util.jl")

@trait QSet{T}
struct Mem2{T} end
@implement Mem2{T} QSet{T}           # parametric pattern + parametric instance

m = Mem2{Int}()
@assert (m isa QSet{Int}) "matching instance answers true"
@assert !(m isa QSet{String}) "narrow query must stay false — no family-wide answer"
@assert (m isa QSet) "member of the bare family"

@assert !(Mem2{String}() isa QSet{Int}) "sibling instance is not a member (exact)"

# the chain-declared path (shared tvars) as the reference behavior
struct Mem3{W} <: QSet{W} end
@assert (Mem3{Float64}() isa QSet{Float64})
@assert !(Mem3{Float64}() isa QSet{Int})
@assert (Mem3{Float64}() isa QSet)

println("m1_parametric_member: OK")
