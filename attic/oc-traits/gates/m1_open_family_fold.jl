# Gate for review finding B1: a negative at a PARAMETER position of the same
# open family must not fold to a permanent Const(false). Behavioral pin: a call
# compiled in a new world must agree with the runtime subtyping truth.
using Traits
include("util.jl")

@trait X2
@trait PS{T}
struct Baz end

negq() = PS{Union{Baz, X2}} <: PS{X2}    # compiled before Baz joins X2

@assert !negq() "not a subtype before the declaration"

@implement Baz X2

rt = PS{Union{Baz, X2}} <: PS{X2}
@assert negq() == rt "compiled call must agree with the runtime truth after the
declaration — the negative must not have been folded while a member was missing"
rt && @assert negq() "runtime true after declaration (and so the call too)"

# control: a closed container with an open-set parameter stays live as before
negc() = Tuple{Baz, Int} <: Tuple{Int, Int}
@assert !negc() "closed parameter pair is still false (exact)"

println("m1_open_family_fold: OK")
