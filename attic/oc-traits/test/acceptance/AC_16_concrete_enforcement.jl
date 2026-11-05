# AC-16 (new; §4c, D8's blessing): the `concrete` enforcement — a `concrete`
# mark plus a run-time site raises NotFullyTypedError from `code_typed` (naming
# the first untyped call); the same body UNMARKED compiles; the same body under
# `all` (facts, but not concrete) compiles; marked `concrete` and fully typed
# compiles. Never fires for plain or plain-facts frames.
include("ac_util.jl")

sink16(a) = a

cbad16(v::Vector{Any}) = sink16(v[1])        # concrete mark + a run-time site
markc!(cbad16)
err = try
    code_typed(cbad16, (Vector{Any},); optimize=false)
    nothing
catch e
    e
end
@assert err !== nothing "concrete + run-time site raises"
@assert typeof(err).name.name === :NotFullyTypedError "the named error type, got $(typeof(err))"
println("OBSERVED NotFullyTypedError: ", sprint(showerror, err))

cplain16(v::Vector{Any}) = sink16(v[1])      # unmarked: compiles
@assert !isempty(code_typed(cplain16, (Vector{Any},); optimize=false)) "unmarked compiles"

cfacts16(v::Vector{Any}) = sink16(v[1])      # facts-marked but NOT concrete: compiles
mark!(cfacts16)
@assert !isempty(code_typed(cfacts16, (Vector{Any},); optimize=false)) "facts without concrete does not enforce"

cok16(v::Vector{Int}) = v[1] + 1             # concrete mark, fully typed: compiles
markc!(cok16)
@assert !isempty(code_typed(cok16, (Vector{Int},); optimize=false)) "concrete + fully typed compiles"

ac_finish(@__FILE__)
