"""
SealedWorkers — Stage A / Rung 2: compile workers under an AbstractInterpreter
whose method table only resolves into an ALLOWLISTED set of root modules (the
trait-bound universe: TraitCore-proxy + region code). Wrapped as world-pinned
`Core.OpaqueClosure`s.

This is *territory*-based sealing, complementing X10's *time*-based
(`invoke_in_world`) sealing: a pirate method defined in a non-enrolled module
is invisible to sealed compilation even if it was defined BEFORE the worker
was compiled — and a region call that resolves outside the universe fails
loudly (the closure rule, enforced constructively).

Julia 1.12 only (uses the Compiler stdlib interface). Kill-tolerant spike.
"""
module SealedWorkers

export compile_sealed, SealedInterp

const CC = Base.Compiler

_rootmodule(m::Module) = (p = parentmodule(m); p === m ? m : _rootmodule(p))

# ---------------------------------------------------------------------------
# Method-table view: delegate to the internal table, then drop every match
# whose defining module is outside the universe. Sealed resolution = the
# remaining (universe-internal) methods win, exactly as if the outside
# definitions did not exist.
# ---------------------------------------------------------------------------

struct SealedMT <: CC.MethodTableView
    inner::CC.InternalMethodTable
    allowed::Base.IdSet{Module}
end

function _allowed(t::SealedMT, mod::Module)
    while true
        mod in t.allowed && return true
        p = parentmodule(mod)
        p === mod && return false
        mod = p
    end
end

function CC.findall(sig::Type, table::SealedMT; limit::Int = -1)
    res = CC.findall(sig, table.inner; limit)
    res === nothing && return nothing
    ms = res.matches
    keep = Any[m for m in ms if _allowed(table, (m::Core.MethodMatch).method.module)]
    length(keep) == length(ms) && return res
    if isempty(keep)
        # The C matcher drops methods fully shadowed by a more-specific one —
        # so a filtered-out pirate leaves its universe-internal victims
        # missing from the match list. Recover them: search the generic
        # function's method list for allowed applicable methods directly.
        ft = sig isa DataType ? sig.parameters[1] : nothing
        if ft isa DataType && isdefined(ft, :instance)
            candidates = Core.MethodMatch[]
            for m in methods(ft.instance)
                _allowed(table, m.module) || continue
                ti = ccall(:jl_type_intersection_with_env, Any, (Any, Any), sig, m.sig)
                inter, env = ti::Core.SimpleVector
                inter === Union{} && continue
                sig <: m.sig || continue   # applicable to every call matching `sig`
                push!(candidates, Core.MethodMatch(sig, env::Core.SimpleVector, m, true))
            end
            # keep only the most specific recovered methods
            filter!(c -> !any(o -> o !== c && Base.morespecific(o.method.sig, c.method.sig),
                              candidates), candidates)
            append!(keep, candidates)
        end
    end
    return CC.MethodLookupResult(keep, res.valid_worlds, res.ambig)
end

CC.findsup(sig::Type, table::SealedMT) = CC.findsup(sig, table.inner)
CC.isoverlayed(::SealedMT) = true   # resolution differs from the global table

# ---------------------------------------------------------------------------
# The interpreter: stock inference/optimization, sealed resolution, own cache
# partition (cache_owner) so sealed CodeInstances never mix with the live ones.
# ---------------------------------------------------------------------------

struct SealedInterp <: CC.AbstractInterpreter
    world::UInt
    mt::SealedMT
    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams
    inf_cache::Vector{CC.InferenceResult}
end

function SealedInterp(allowed::Base.IdSet{Module}; world::UInt = Base.get_world_counter())
    SealedInterp(world, SealedMT(CC.InternalMethodTable(world), allowed),
                 CC.InferenceParams(), CC.OptimizationParams(), CC.InferenceResult[])
end

CC.InferenceParams(si::SealedInterp) = si.inf_params
CC.OptimizationParams(si::SealedInterp) = si.opt_params
CC.get_inference_world(si::SealedInterp) = si.world
CC.get_inference_cache(si::SealedInterp) = si.inf_cache
CC.cache_owner(::SealedInterp) = :SealedWorkers
CC.method_table(si::SealedInterp) = si.mt

"""
    compile_sealed(f, argtypes, allowed_modules) -> OpaqueClosure

Infer and optimize `f(::argtypes...)` with resolution restricted to
`allowed_modules` (root modules), and wrap the result as a world-pinned
OpaqueClosure.
"""
function compile_sealed(f, argtypes::Tuple, allowed)
    interp = SealedInterp(Base.IdSet{Module}(allowed))
    irs = Base.code_ircode(f, argtypes; interp)
    isempty(irs) && error("compile_sealed: no method of $f for $argtypes")
    length(irs) == 1 || error("compile_sealed: ambiguous, $(length(irs)) methods")
    ir, _ = irs[1]
    # The OC-from-IR constructor requires argtypes[1] == typeof(env); we pass
    # no environment, so slot 1 must be Tuple{} (the function itself is a
    # singleton and unused in the body).
    ir = CC.copy(ir)
    ir.argtypes[1] = Tuple{}
    return Core.OpaqueClosure(ir; do_compile = true)
end

end # module
