# Shared harness for the acceptance cases (plan §C; the old suite's phrasing:
# policy value == plain value, or the named raise — `experiments/facts/` is the
# case source, oc-notes/m3-editplan.md §C is the disposition).
#
# Convention for AC_*.jl:
#   include("ac_util.jl")
#   <body: marked twin vs plain twin; values equal before/after the change>
#   ac_finish(@__FILE__)      # re-runs THIS file in a JULIA_FACTS=1 child and
#                             # requires the same OK line — "both settings"
import Compiler

const AC_UTIL = @__DIR__
include(joinpath(AC_UTIL, "..", "..", "gates", "util.jl"))

const ac_julia = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())`

mark!(f) = Compiler.mark_facts!(f)
markc!(f) = Compiler.mark_concrete!(f)

function ac_finish(path::AbstractString)
    tag = basename(path, ".jl")
    if get(ENV, "JULIA_FACTS", "0") == "1"
        println("$tag: OK (all)")        # we ARE the child
        return
    end
    tf = tempname()
    try
        run(pipeline(addenv(`$ac_julia $path`, ["JULIA_FACTS" => "1"]),
                     stdout=tf, stderr=tf))
        out = read(tf, String)
        @assert occursin("$tag: OK (all)", out) "re-run under JULIA_FACTS=1 must print the OK line, got: $out"
    finally
        rm(tf, force=true)
    end
    println("$tag: OK")
end
