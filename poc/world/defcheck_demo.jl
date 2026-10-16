# Definition checking at archetypes (session 22).
#   julia +1.12.2 --startup-file=no --project=poc/world/env poc/world/defcheck_demo.jl [skip|noskip]
# 1. Columns' functions are checked once, against ColTable alone, at archetypes.
# 2. A library with mistakes is checked before any representation exists.
# 3. A representation defined in the session: first calls with the per-signature
#    check skipped (methods checked at definition) or run (as before).
ENV["JULIA_TW_VIEWCACHE"] = "0"                  # no view caches: measure the checks themselves
using TraitWorld, Printf
mode = isempty(ARGS) ? "skip" : ARGS[1]
TraitWorld.DEFCHECK_SKIP[] = mode == "skip"
using Columns
import Columns: ncols, col

println("== 1. Columns at archetypes")
t = @elapsed ps = check_definitions(Columns)
@printf("check_definitions(Columns): %.1f ms, %d problems, %d methods recorded\n", 1000t, length(ps), length(TraitWorld._DEF_CHECKED))
for m in TraitWorld._DEF_CHECKED
    println("   ", m.name, "  ", TraitWorld.archetype_sig(m))
end

println("\n== 2. a library with mistakes, no representation anywhere")
module BadLib
using TraitWorld
@trait_module begin
using Columns
export spread, leak, fine
spread(t::ColTable) = size(t)                       # not an operation of ColTable
leak(t::ColTable) = typeof(t)                        # depends on the user's type
fine(t::ColTable) = firstcol(t) .* ncols(t)          # operations only
end
end
try
    check_definitions(BadLib)
    println("no problems found")
catch e
    e isa TraitUseError || rethrow()
    for p in e.problems
        println("   ", p)
    end
end
println("recorded clean: ", [m.name for m in TraitWorld._DEF_CHECKED if parentmodule(m) === BadLib])

println("\n== 3. a representation defined now, first calls ($mode)")
struct Ramp2                                         # its own representation: Columns' code compiles for it
    base::Vector{Float64}
    n::Int
end
ncols(r::Ramp2) = r.n
col(r::Ramp2, i::Int) = r.base .* i
@implement ColTable Ramp2
r = Ramp2([1.0, 2.0, 3.0], 3)
for (name, f) in (("colmean", () -> colmean(r, 2)), ("colrange", () -> colrange(r, 2)), ("meandiff", () -> meandiff(r, r, 1)))
    t1 = @elapsed f()
    t2 = @elapsed f()
    @printf("   %-9s first %7.2f ms, second %.4f ms\n", name, 1000t1, 1000t2)
end
