# Gate M3 §4 (D4): the G2 bit. A marked frame whose every dispatch is a fact
# gets ci.flags bit 0b10000 at finish!; a frame with a run-time site does not;
# unmarked code never carries the bit; and `ci_is_g2`-style reads work from
# Julia. (The image round trip of the bit is m3_image_roundtrip's job.)
include("util.jl")
import Compiler

const G2BIT = 0b00010000

tgt_fact(x::Int) = x + 1                 # called at a fact (dispatch tuple): fine
g2a(v::Vector{Any}) = tgt_fact(3)        # the only dispatch: at a FACT signature
Compiler.mark_facts!(g2a)
@assert g2a(Any[0]) == 4
cia = only([c for c in all_cis(g2a) if c.min_world > 0])
@assert getfield(cia, :flags) & G2BIT != 0 "fact-only marked frame carries the G2 bit: flags=$(getfield(cia, :flags))"

sinkg(a) = a
g2b(v::Vector{Any}) = sinkg(v[1])        # run-time site => G2 false
Compiler.mark_facts!(g2b)
@assert g2b(Any[1]) == 1
cib = only([c for c in all_cis(g2b) if c.min_world > 0])
@assert getfield(cib, :flags) & G2BIT == 0 "a frame with a run-time site does not claim G2: flags=$(getfield(cib, :flags))"

# unmarked code: the bit is never set, plain or marked elsewhere
g2plain(v::Vector{Any}) = tgt_fact(3)
g2plain(Any[0])
for c in all_cis(g2plain)
    @assert getfield(c, :flags) & G2BIT == 0 "unmarked frames never claim G2"
end

println("m3_g2_bit: OK")
