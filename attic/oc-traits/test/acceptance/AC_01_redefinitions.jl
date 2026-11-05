# AC-1 (old G1.1, G1.2, G1.4, G1.6): a marked caller follows redefinitions as
# plain Julia follows them — owner redefinition of its own method, of a helper
# it calls, a winning pirate added later, a more specific method added later.
include("ac_util.jl")

# G1.1 owner redefines its own method
struct C11 end
own1(x::C11) = 1.0
mk1(x::C11) = own1(x)
pl1(x::C11) = own1(x)
mark!(mk1)
@assert mk1(C11()) == pl1(C11()) == 1.0
own1(x::C11) = 40.0
@assert mk1(C11()) == pl1(C11()) == 40.0 "G1.1: owner redefinition followed identically"

# G1.2 redefinition of a helper the implementation calls
h2(x) = x + 1
mk2(x::Int) = h2(x) * 2
pl2(x::Int) = h2(x) * 2
mark!(mk2)
@assert mk2(3) == pl2(3) == 8
h2(x) = x + 10
@assert mk2(3) == pl2(3) == 22 "G1.2: helper redefinition followed identically"

# G1.4 a winning pirate, added after the compile, is followed as plain follows it
abstract type A4 end
struct B4 <: A4 end
p4(x::A4) = :base
mk4(x::A4) = p4(x)
pl4(x::A4) = p4(x)
mark!(mk4)
@assert mk4(B4()) == pl4(B4()) == :base      # both compiled pre-pirate
p4(x::B4) = :pirate
@assert mk4(B4()) == pl4(B4()) == :pirate "G1.4: the pirate wins in both modes"

# G1.6 a more specific method at the call signature, added later, is followed
struct C6x end
s6(::C6x) = :general
mk6(x::C6x) = s6(x)
pl6(x::C6x) = s6(x)
mark!(mk6)
@assert mk6(C6x()) == pl6(C6x()) == :general
s6(::C6x) = :general2                       # redefinition
@assert mk6(C6x()) == pl6(C6x()) == :general2
struct D6 <: C6x end
s6(::D6) = :specific
@assert mk6(D6()) == pl6(D6()) == :specific "G1.6: later more-specific followed identically"

ac_finish(@__FILE__)
