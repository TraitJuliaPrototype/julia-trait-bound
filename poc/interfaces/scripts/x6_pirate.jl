# Demo 1 step 6 (writeup/poc3-plan.md §1, §3.3, §9.3): a pirate of a sealed
# package. Four fresh processes:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x6_pirate.jl refuse        # stack first, then `using Pirate`: refused
#   … x6_pirate.jl refuse-first   # `using Pirate` first, then the stack: the seal's load finds it
#   … x6_pirate.jl tolerate       # Pirate tolerated: it loads with a warning, workers run plain Julia's answer
#   … x6_pirate.jl warn           # the interim mode: reported and kept
# Pirate (poc/world/Pirate) defines `Stats.weight(::Float64)`, owning neither;
# Reports.summarize's `wsum` field is `Stats.weighted`, which calls it.
using Printf
const MODE = ARGS[1]
ENV["JULIA_TRAITWORLD_SEAL"] = MODE == "warn" ? "warn" : "refuse"      # read when TraitWorld loads, which may be after the pirate
MODE == "refuse-first" || @eval using TraitWorld
MODE == "tolerate" && push!(TraitWorld.TOLERATED, "Pirate")      # what `[traits] tolerate = ["Pirate"]` in the project file does
MODE == "refuse-first" || TraitWorld.piracy_mode!(MODE == "warn" ? :warn : :refuse)
v = [[1.0, 2.0, 3.0]]
if MODE == "refuse-first"
    # BasePirate (poc/interfaces/BasePirate) pirates `Base.sum(::Vector{Int8})` and depends on nothing:
    # loaded before any trait package, it is found when the first seal arrives
    @eval using BasePirate
    println("BasePirate loaded first: sum(Int8[1, 2]) = ", sum(Int8[1, 2]), ", method owner ", which(sum, (Vector{Int8},)).module)
    t = @elapsed @eval using Columns, Stats, Reports
    @printf("the stack's load took %.2f s; after it: sum(Int8[1, 2]) = %d, method owner %s\n", t, sum(Int8[1, 2]), which(sum, (Vector{Int8},)).module)
else
    @eval using Columns, Stats, Reports
    s0 = summarize(v)[1].wsum
    @printf("before: summarize(v)[1].wsum = %.1f; sealed: %s\n", s0, join(sort(collect(TraitWorld.SEALED)), ", "))
    t = @elapsed @eval using Pirate
    @printf("using Pirate took %.2f s (the scan included)\n", t)
    println("weight(1.0) = ", Stats.weight(1.0), "  method owner: ", which(Stats.weight, (Float64,)).module)
    s1 = @timed summarize(v)
    @printf("after: summarize(v)[1].wsum = %.1f (%.1f ms, %.1f ms compiling)\n", s1.value[1].wsum, s1.time * 1e3, (s1.compile_time + s1.recompile_time) * 1e3)
end
