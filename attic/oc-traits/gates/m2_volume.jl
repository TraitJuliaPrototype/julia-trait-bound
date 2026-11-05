# Gate M2 item 5/§5.M2's volume gate: a scripted table (N specializations of
# vt compiled pre-membership through the catch-all), N late memberships; the
# §7/§8 stat deltas and the per-declare wall stay in the B-band (invalidations
# > 0 and far below the naive-A estimate = every specialization per declare).
# Emits the VOLUME row for numbers.md.
using Traits
include("util.jl")

stat(w) = ccall(:jl_membership_stat, Csize_t, (Cint,), w)
N = 24

@trait VOL
vt(::VOL) = :set
vt(x) = :any                      # the pre-membership answer for every member

TS = DataType[]
for i in 1:N
    sym = Symbol("VT", i)
    @eval struct $sym end
    push!(TS, Core.eval(@__MODULE__, sym))   # the definition evaluates to nothing here
end
foreach(T -> vt(T()), TS)         # compile the N specializations of vt
foreach(T -> @assert(vt(T()) === :any, "pre-membership table value"), TS)

b = map(stat, 1:6)
t0 = time_ns()
for T in TS
    Traits.declare_membership(T, VOL, nothing, @__MODULE__, nothing)
end
wall = (time_ns() - t0) / 1e9
d = map(stat, 1:6) .- b           # replays, visits, morespec-skips, spec-invalidations, cache-lowerings, latest-only-clears

foreach(T -> @assert(vt(T()) === :set, "member dispatch after the walk"), TS)

naive = N * N                     # invalidating every cached spec at every declare
@assert d[4] > 0 "spec invalidations happened"
@assert d[4] <= naive "invalidations within the naive-A ceiling ($naive)"
@assert d[1] >= N "every declare replayed"
@assert wall < 10 "per-declare wall sane (shared machine): $(round(wall, digits=3)) s"

println("VOLUME | declares=$N replays=$(d[1]) visits=$(d[2]) morespec_skips=$(d[3]) ",
        "spec_inval=$(d[4]) cache_lowerings=$(d[5]) latest_only_clears=$(d[6]) wall_s=$(round(wall, digits=3))")
println("m2_volume: OK")
