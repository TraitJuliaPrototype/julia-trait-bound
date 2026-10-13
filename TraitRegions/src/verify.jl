# ---------------------------------------------------------------------------
# verify_main: does a program only ever run compiled code? (design doc,
# "Verified mains and compiled binaries").
#
# Walk the optimized code reachable from `main(argtypes...)` and classify
# every call:
#
#   static       an `invoke` of a known CodeInstance: compiled with its caller;
#   bounded      a dynamic call whose possible targets are finitely many and
#                known now (concrete or small-Union argument types, methods
#                on concrete types, or @nospecialize positions whose declared
#                type has no type variable): enumerated and followed;
#   trait        a dynamic call made by the trait machinery (seal lookup,
#                projection, worker call from an entry, witness call in a
#                worker): its targets are enumerable from the seals, because
#                erasure maps every sealed type to one of finitely many
#                representations; enumerated and followed;
#   root         a closure handed to the runtime (task, atexit hook,
#                finalizer): enumerated and followed as an entry of its own;
#   guard        the piracy guard's slow path: not followed, a verified build
#                audits at build time instead (`findings`);
#   hole         anything else: a dynamic call whose target depends on a
#                runtime type nobody enumerated. It may need the JIT.
#
# A hole is on an error path when every path from it ends in a `throw` that
# nothing catches: not a `try` in its own function, nor one in any caller on
# the path to it. Exits and endless loops are normal paths. Such a hole runs
# only while the program is dying of an exception.
#
# The verdict holds for the world and the seals that exist when it runs: a
# later method definition, package load or seal can change it.
# Holes are judged on the IR `code_typed` produces now, which is what Julia
# compiles; inlining decisions are re-made, so this is a model of the compiled
# code, checked against `--trace-compile` in poc/verifymain.
# ---------------------------------------------------------------------------

const _CC = Core.Compiler

struct Hole
    kind::Symbol            # :dispatch, :callee, :splat, :latest, :builtin, :inference, :eval, :closure, :trait_arg, :noscan
    errorpath::Bool
    caller::Core.MethodInstance
    stmt::Int
    callee::Any
    argtypes::Any
    line::String
end

struct _Site
    kind::Symbol            # :bounded, :trait, :root, :guard, or a hole kind
    doomed::Bool            # every path from it ends in an uncaught throw (in this function)
    intry::Bool             # inside a `try` of this function
    stmt::Int
    callee::Any
    argtypes::Any
    targets::Vector{Core.MethodInstance}
    line::String
end

struct _Scan
    invokes::Vector{Tuple{Core.MethodInstance,Bool,Bool}}   # static callee, doomed, intry
    sites::Vector{_Site}
    throws::Bool            # every path from the entry ends in an uncaught throw
    returns::Bool           # some path from the entry returns a value
end

"Result of [`verify_main`](@ref)."
struct MainReport
    entry::Any
    reached::Int                    # MethodInstances in the closure
    normal::Int                     # of which reached on a normal path
    static_calls::Int
    bounded::Int                    # dynamic calls with an enumerated target set
    trait_sites::Int                # dynamic calls made by the trait machinery
    targets::Vector{Pair{Symbol,Any}}   # their targets: kind => signature
    roots::Int                      # closures handed to the runtime, followed
    guard_sites::Int
    holes::Vector{Hole}
    uncompiled::Vector{Any}         # normal-path MethodInstances without native code
    checked_native::Bool            # false while generating a package image
    findings::Vector{Pair{Any,Vector{PiracyFinding}}}
end

"`true` iff no hole lies on a normal path and every normal-path method instance has native code."
isclosed(r::MainReport) = !any(h -> !h.errorpath, r.holes) && isempty(r.uncompiled)

# --- registries -------------------------------------------------------------

struct _Registry
    workers::IdDict{Any,Tuple{Any,Symbol,Tuple}}    # worker => (trait, op, argtypes)
    seals::IdDict{Any,Vector{Pair{Type,Seal}}}      # trait => seals
    ops::Vector{Tuple{Any,Symbol}}                  # (trait, op)
end

function _traits_of(f, pos::Int, acc::Base.IdSet{Any})
    for m in methods(f)
        sig = m.sig
        sig isa DataType && length(sig.parameters) == 3 || continue
        Tt = sig.parameters[pos]
        Tt isa DataType && Tt <: Type && Tt.parameters[1] isa Type && push!(acc, Tt.parameters[1])
    end
    return acc
end

function _registry()
    workers = IdDict{Any,Tuple{Any,Symbol,Tuple}}()
    seals = IdDict{Any,Vector{Pair{Type,Seal}}}()
    ops = Tuple{Any,Symbol}[]
    traits = _traits_of(op_info, 2, Base.IdSet{Any}())
    _traits_of(seal_info, 2, traits)                # traits with seals but no ops
    for trait in traits
        seals[trait] = each_seal(trait)
        for (name, entry) in each_op(trait)
            workers[entry[1]] = (trait, name, entry[2])
            push!(ops, (trait, name))
        end
    end
    return _Registry(workers, seals, ops)
end

# --- target method instances -------------------------------------------------

"The MethodInstance a call with signature `S` runs (its compileable specialization)."
function _target_mi(@nospecialize(S), world::UInt)
    match = Base._which(S; world, raise = false)
    match === nothing && return nothing
    csig = _CC.get_compileable_sig(match.method, match.spec_types, match.sparams)
    if csig !== nothing && csig !== match.spec_types
        m2 = Base._which(csig; world, raise = false)
        m2 === nothing || (match = m2)
    end
    return _CC.specialize_method(match)
end

"A type that dispatch sees as one runtime type (values of `DataType` etc. dispatch as `Type{value}`)."
_isleaf(@nospecialize(A)) =
    _CC.isType(A) ? !Base.has_free_typevars(A) : (Base.isdispatchelem(A) && !(A <: Type))

function _union_split(argtypes::Vector{Any}, limit::Int)
    combos = Vector{Any}[Any[]]
    for A in argtypes
        parts = _isleaf(A) ? Any[A] : A isa Union ? Base.uniontypes(A) : nothing
        parts === nothing && return nothing
        all(_isleaf, parts) || return nothing
        length(combos) * length(parts) > limit && return nothing
        combos = Vector{Any}[Any[c..., p] for c in combos for p in parts]
    end
    return combos
end

"""
`@nospecialize` makes Julia compile one instance for a position only if the
declared type there mentions no type variable of the method: for
`f(@nospecialize(x::T)) where T` it still specializes per runtime type.
"""
function _nospecialized(m::Method, i::Int)
    k = min(i, m.nargs - 1)                  # a Vararg tail shares the last bit
    (m.nospecialize >> (k - 1)) & 1 == 1 || return false
    ps = Base.unwrap_unionall(m.sig).parameters
    d = ps[min(i + 1, length(ps))]
    if Base.isvarargtype(d)
        d = isdefined(d, :T) ? d.T : Any
    end
    return !Base.has_free_typevars(d)
end

"Targets of a dynamic call to a known function, or `nothing` if they depend on unenumerated runtime types."
function _bounded_targets(@nospecialize(f), argtypes::Vector{Any}, world::UInt)
    ft = Core.Typeof(f)
    out = Core.MethodInstance[]
    combos = _union_split(argtypes, 32)
    if combos !== nothing
        for c in combos
            mi = _target_mi(Tuple{ft, c...}, world)
            mi === nothing || push!(out, mi)
        end
        return out
    end
    any(A -> A === Union{}, argtypes) && return out
    ms = Base._methods_by_ftype(Tuple{ft, argtypes...}, -1, world)
    ms isa Vector || return nothing
    for match in ms
        m = match.method
        sp = match.spec_types
        sp isa DataType || return nothing
        for (i, A) in enumerate(argtypes)
            _isleaf(A) && continue
            # the method itself fixes this position (a method for a concrete type) ...
            i + 1 <= length(sp.parameters) && !Base.isvarargtype(sp.parameters[i+1]) &&
                _isleaf(sp.parameters[i+1]) && continue
            # ... or does not specialize on it
            _nospecialized(m, i) && continue
            return nothing
        end
        csig = _CC.get_compileable_sig(m, match.spec_types, match.sparams)
        mi = _target_mi(csig === nothing ? match.spec_types : csig, world)
        mi === nothing || push!(out, mi)
    end
    return out
end

# --- reading optimized code ----------------------------------------------------

function _constval(src, sptypes, @nospecialize(x))
    t = _CC.argextype(x, src, sptypes)
    t isa _CC.Const && return Some{Any}(t.val)
    T = _CC.widenconst(t)
    Base.issingletontype(T) && return Some{Any}(T.instance)
    return nothing
end

_argT(src, sptypes, @nospecialize(x)) = _CC.widenconst(_CC.argextype(x, src, sptypes))

"Resolve a callee: `(:const, f)`, `(:field, objtype, name, obj)` or `(:unknown, type)`."
function _callee(src, sptypes, @nospecialize(x))
    if x isa Core.SSAValue
        d = src.code[x.id]
        if Meta.isexpr(d, :call) && length(d.args) >= 3
            g = _constval(src, sptypes, d.args[1])
            if g !== nothing && something(g) === Core.getfield && d.args[3] isa QuoteNode
                return (:field, _argT(src, sptypes, d.args[2]), d.args[3].value, d.args[2])
            elseif g !== nothing && something(g) === Core.compilerbarrier
                h = _constval(src, sptypes, d.args[3])
                h === nothing || return (:const, something(h))
            end
        end
    end
    v = _constval(src, sptypes, x)
    v === nothing || return (:const, something(v))
    return (:unknown, _argT(src, sptypes, x))
end

"Name of the field `x` was loaded from, if it is a `getfield(obj, :name)` result."
function _fieldof(src, @nospecialize(x))
    x isa Core.SSAValue || return nothing
    d = src.code[x.id]
    while d isa Core.PiNode && d.val isa Core.SSAValue
        d = src.code[d.val.id]
    end
    Meta.isexpr(d, :call) && length(d.args) >= 3 && d.args[3] isa QuoteNode || return nothing
    return d.args[3].value
end

function _succs(src)
    code = src.code
    n = length(code)
    succ = [Int[] for _ in 1:n]
    for i in 1:n
        st = code[i]
        nxt = i < n ? i + 1 : 0
        if st isa Core.GotoNode
            push!(succ[i], st.label)
        elseif st isa Core.GotoIfNot
            push!(succ[i], st.dest); nxt > 0 && push!(succ[i], nxt)
        elseif st isa Core.ReturnNode
        elseif st isa Core.EnterNode
            st.catch_dest == 0 || push!(succ[i], st.catch_dest); nxt > 0 && push!(succ[i], nxt)
        elseif src.ssavaluetypes[i] === Union{} &&
               (Meta.isexpr(st, :call) || Meta.isexpr(st, :invoke) || Meta.isexpr(st, :foreigncall))
        else
            nxt > 0 && push!(succ[i], nxt)
        end
    end
    return succ
end

"Statements inside a `try` of this function (an over-approximation: from each `EnterNode` up to a `leave`)."
function _intry(src, succ)
    n = length(src.code)
    intry = falses(n)
    for e in 1:n
        src.code[e] isa Core.EnterNode || continue
        stack = Int[e + 1]
        while !isempty(stack)
            j = pop!(stack)
            1 <= j <= n && !intry[j] || continue
            Meta.isexpr(src.code[j], :leave) && continue
            intry[j] = true
            append!(stack, succ[j])
        end
    end
    return intry
end

function _reaches_return(src, succ)
    n = length(src.code)
    seen = falses(n)
    stack = Int[1]
    while !isempty(stack)
        j = pop!(stack)
        1 <= j <= n && !seen[j] || continue
        seen[j] = true
        st = src.code[j]
        st isa Core.ReturnNode && isdefined(st, :val) && return true
        append!(stack, succ[j])
    end
    return false
end

_throw_ccall(name) = name isa Symbol && (occursin("throw", String(name)) || occursin("error", String(name)))

"""
Statements from which every path ends in a throw that this function does not
catch: least fixpoint from the throw sinks (`throw`, `rethrow`, error ccalls,
invokes of functions that only throw, dynamic calls inferred `Union{}` other
than `exit`). Exits and endless loops are not doomed.
"""
function _doomed(src, succ, intry, throws_only)
    code = src.code
    n = length(code)
    sink = falses(n)
    for i in 1:n
        intry[i] && continue
        st = code[i]
        src.ssavaluetypes[i] === Union{} || continue
        if Meta.isexpr(st, :call)
            # inference proved the call never returns: every target throws, or
            # exits, or loops. As trim does, take it as a throw, except `exit`.
            f = st.args[1]
            f isa GlobalRef && isdefined(f.mod, f.name) && (f = getglobal(f.mod, f.name))
            sink[i] = f !== Base.exit
        elseif Meta.isexpr(st, :foreigncall)
            name = st.args[1]
            name isa QuoteNode && (name = name.value)
            sink[i] = _throw_ccall(name)
        elseif Meta.isexpr(st, :invoke)
            # the call site is typed Union{}; the callee only fails to throw if
            # it can neither throw nor return on its own (it exits or loops). A
            # callee that can return is typed Union{} here through what the
            # caller knows (constant propagation): it throws in this context.
            c = st.args[1]
            cmi = c isa Core.CodeInstance ? c.def : c
            isdefined(Core, :ABIOverride) && cmi isa Core.ABIOverride && (cmi = cmi.def)
            sink[i] = cmi isa Core.MethodInstance && throws_only(cmi)
        end
    end
    doomed = copy(sink)
    changed = true
    while changed
        changed = false
        for i in n:-1:1
            doomed[i] && continue
            s = succ[i]
            isempty(s) && continue
            if all(j -> 1 <= j <= n && doomed[j], s)
                doomed[i] = true
                changed = true
            end
        end
    end
    return doomed
end

function _line(src, mi, i)
    try
        lin = Base.IRShow.buildLineInfoNode(src.debuginfo, mi, i)
        if !isempty(lin)
            n = lin[end]
            return string(n.file, ":", n.line)
        end
    catch
    end
    m = mi.def
    return m isa Method ? string(m.file, ":", m.line) : ""
end

# ccalls that run arbitrary code or the compiler
const _EVAL_CCALLS = (:jl_apply, :jl_toplevel_eval, :jl_toplevel_eval_in, :jl_eval_string,
                      :jl_compile_hint, :jl_expand, :jl_expand_with_loc)

_dispatching_builtin(@nospecialize(f)) =
    f === Core._apply || f === Core._apply_iterate || f === Core._call_in_world_total ||
    f === Core.invoke || f === Core.invoke_in_world || f === Core.invokelatest ||
    f === Core.finalizer || f === Core.modifyfield! || f === Core.modifyglobal! ||
    f === Core.memoryrefmodify!

function _is_return_type(@nospecialize(f))
    f === _CC.return_type && return true
    isdefined(Base, :Compiler) && isdefined(Base.Compiler, :return_type) && f === Base.Compiler.return_type
end

# --- the walk ----------------------------------------------------------------------

mutable struct _Walk
    reg::_Registry
    world::UInt
    scans::IdDict{Core.MethodInstance,_Scan}
    active::Base.IdSet{Core.MethodInstance}
end

function _get_scan(cx::_Walk, mi::Core.MethodInstance)
    sc = get(cx.scans, mi, nothing)
    sc === nothing || return sc
    mi in cx.active && return nothing                  # a cycle: callers assume "may return"
    push!(cx.active, mi)
    sc = try
        _scan(mi, cx)
    finally
        delete!(cx.active, mi)
    end
    cx.scans[mi] = sc
    return sc
end

"A `Union{}`-typed call of `mi` is a throw unless `mi` can neither throw nor return (it exits or loops)."
function _throws_only(cx::_Walk, mi::Core.MethodInstance)
    sc = _get_scan(cx, mi)
    return sc !== nothing && (sc.throws || sc.returns)
end

"Closure handed to the runtime: `(f, argtypes)` if statement `st` registers one."
function _runtime_closure(src, sptypes, @nospecialize(st))
    if Meta.isexpr(st, :foreigncall)
        name = st.args[1]
        name isa QuoteNode && (name = name.value)
        name === :jl_new_task && length(st.args) >= 6 &&
            return (:task, Any[_argT(src, sptypes, st.args[6])])
        return nothing
    end
    Meta.isexpr(st, :invoke) || Meta.isexpr(st, :call) || return nothing
    off = Meta.isexpr(st, :invoke) ? 1 : 0
    length(st.args) >= 2 + off || return nothing
    fv = _constval(src, sptypes, st.args[1+off])
    fv === nothing && return nothing
    f = something(fv)
    ats = Any[_argT(src, sptypes, a) for a in st.args[2+off:end]]
    if f === Core.Task && length(ats) >= 1
        return (:task, Any[ats[1]])
    elseif f === Base.atexit && length(ats) == 1
        return (:atexit, Any[ats[1]])
    elseif (f === Base.finalizer || f === Core.finalizer) && length(ats) == 2
        return (:finalizer, Any[ats[1], ats[2]])
    end
    return nothing
end

function _scan(mi::Core.MethodInstance, cx::_Walk)
    reg, world = cx.reg, cx.world
    invokes = Tuple{Core.MethodInstance,Bool,Bool}[]
    sites = _Site[]
    m = mi.def
    m isa Method || return _Scan(invokes, sites, false, true)
    res = try
        Base.code_typed_by_type(mi.specTypes; optimize = true, debuginfo = :source, world)
    catch
        nothing
    end
    src = nothing
    if res !== nothing
        for (ci, _) in res
            ci isa Core.CodeInfo || continue
            (ci.parent === nothing || ci.parent.def === m) && (src = ci; break)
        end
    end
    if src === nothing
        push!(sites, _Site(:noscan, false, false, 0, m, mi.specTypes, Core.MethodInstance[], _line(nothing, mi, 0)))
        return _Scan(invokes, sites, false, true)
    end
    sptypes = _CC.sptypes_from_meth_instance(mi)
    succ = _succs(src)
    intry = _intry(src, succ)
    doomed = _doomed(src, succ, intry, c -> _throws_only(cx, c))
    throws = !isempty(doomed) && doomed[1]
    returns = _reaches_return(src, succ)
    site(kind, i, callee, ats, ts = Core.MethodInstance[]) =
        push!(sites, _Site(kind, doomed[i], intry[i], i, callee, ats, ts, _line(src, mi, i)))
    hole(kind, i, callee, ats) = site(kind, i, callee, ats)
    # the trait of the worker this code belongs to, if any: its witness calls are that trait's
    F = mi.specTypes.parameters[1]
    encl = F isa DataType && isdefined(F, :instance) ? get(reg.workers, F.instance, nothing) : nothing
    projections = Int[]          # projection sites, resolved once the entry's traits are known
    traits_here = Base.IdSet{Any}()
    for i in eachindex(src.code)
        st = src.code[i]
        rc = _runtime_closure(src, sptypes, st)
        if rc !== nothing
            kind, ats = rc
            if all(_isleaf, ats)
                t = _target_mi(Tuple{ats...}, world)
                site(:root, i, kind, ats, t === nothing ? Core.MethodInstance[] : Core.MethodInstance[t])
            else
                hole(:closure, i, kind, ats)
            end
            # a Task constructor that was not inlined only stores the closure: nothing else to follow
            Meta.isexpr(st, :invoke) && kind === :task && continue
            Meta.isexpr(st, :foreigncall) && continue
        end
        if Meta.isexpr(st, :invoke)
            c = st.args[1]
            cmi = c isa Core.CodeInstance ? c.def : c
            isdefined(Core, :ABIOverride) && cmi isa Core.ABIOverride && (cmi = cmi.def)
            cmi isa Core.MethodInstance && push!(invokes, (cmi, doomed[i], intry[i]))
        elseif Meta.isexpr(st, :call)
            cl = _callee(src, sptypes, st.args[1])
            ats = Any[_argT(src, sptypes, a) for a in st.args[2:end]]
            if cl[1] === :const
                f = cl[2]
                if f isa Core.IntrinsicFunction || (f isa Core.Builtin && !_dispatching_builtin(f))
                    continue
                elseif f === Core.finalizer
                    rc === nothing && hole(:closure, i, :finalizer, ats)
                elseif f === Core._apply_iterate
                    g = length(st.args) >= 3 ? _callee(src, sptypes, st.args[3]) : (:unknown, Any)
                    if g[1] === :const && (g[2] isa Core.IntrinsicFunction || (g[2] isa Core.Builtin && !_dispatching_builtin(g[2])))
                        continue
                    end
                    flat = Any[]
                    ok = g[1] === :const
                    for a in st.args[4:end]
                        T = _argT(src, sptypes, a)
                        if T isa DataType && T <: Tuple && (isempty(T.parameters) || !Base.isvarargtype(T.parameters[end]))
                            append!(flat, T.parameters)
                        else
                            ok = false
                        end
                    end
                    ts = ok ? _bounded_targets(g[2], flat, world) : nothing
                    ts === nothing ? hole(:splat, i, g[2], flat) : site(:bounded, i, g[2], flat, ts)
                elseif f isa Core.Builtin
                    hole(f === Core.invokelatest || f === Core.invoke_in_world || f === Core._call_in_world_total ?
                         :latest : :builtin, i, f, ats)
                elseif f === _guard_slow || f === _warn_piracy
                    site(:guard, i, f, ats)
                elseif haskey(reg.workers, f)
                    # entry -> worker at the seal's representation
                    trait, _, _ = reg.workers[f]
                    push!(traits_here, trait)
                    raw = _fieldof(src, st.args[2]) === :raw
                    extras = ats[3:end]
                    if all(_isleaf, extras)
                        ts = Core.MethodInstance[]
                        for (_, s) in reg.seals[trait]
                            W = raw ? typeof(s.raw) : typeof(s.w)
                            t = _target_mi(Tuple{typeof(f), W, s.R, extras...}, world)
                            t === nothing || push!(ts, t)
                        end
                        site(:trait, i, f, ats, ts)
                    else
                        hole(:trait_arg, i, f, ats)
                    end
                elseif f === seal_info
                    ts = Core.MethodInstance[]
                    for (trait, seals) in reg.seals, (T, _) in seals
                        t = _target_mi(Tuple{typeof(seal_info), Type{trait}, Type{T}}, world)
                        t === nothing || push!(ts, t)
                    end
                    site(:trait, i, f, ats, ts)
                elseif f === op_info
                    ts = Core.MethodInstance[]
                    for (trait, name) in reg.ops
                        t = _target_mi(Tuple{typeof(op_info), Type{trait}, Val{name}}, world)
                        t === nothing || push!(ts, t)
                    end
                    site(:trait, i, f, ats, ts)
                elseif _is_return_type(f)
                    hole(:inference, i, f, ats)
                elseif rc === nothing
                    ts = _bounded_targets(f, ats, world)
                    ts === nothing ? hole(:dispatch, i, f, ats) : site(:bounded, i, f, ats, ts)
                end
            elseif cl[1] === :field
                objT, name = cl[2], cl[3]
                if objT === Seal && name === :project
                    push!(projections, i)
                elseif objT isa DataType && objT <: NamedTuple && isconcretetype(objT) &&
                       name isa Symbol && fieldtype(objT, name) === Function
                    # witness call in a worker: the seals of its trait with this table type and representation
                    R = isempty(ats) ? Any : ats[1]
                    if all(_isleaf, ats)
                        ts = Core.MethodInstance[]
                        for (trait, seals) in reg.seals, (_, s) in seals
                            encl === nothing || trait === encl[1] || continue
                            typeof(s.w) === objT && (R === s.R) || continue
                            w = getfield(s.w, name)
                            t = _target_mi(Tuple{typeof(w), ats...}, world)
                            t === nothing || push!(ts, t)
                        end
                        site(:trait, i, name, ats, ts)
                    else
                        hole(:trait_arg, i, name, ats)
                    end
                else
                    hole(:callee, i, string(objT, ".", name), ats)
                end
            else
                hole(:callee, i, cl[2], ats)
            end
        elseif Meta.isexpr(st, :foreigncall)
            name = st.args[1]
            name isa QuoteNode && (name = name.value)
            name in _EVAL_CCALLS && hole(:eval, i, name, nothing)
        elseif Meta.isexpr(st, :new_opaque_closure) || Meta.isexpr(st, :cfunction)
            hole(:closure, i, st.head, nothing)
        elseif Meta.isexpr(st, :invoke_modify)
            hole(:builtin, i, :invoke_modify, nothing)
        end
    end
    for i in projections
        ts = Core.MethodInstance[]
        traits = isempty(traits_here) ? keys(reg.seals) : traits_here
        for trait in traits, (T, s) in reg.seals[trait]
            t = _target_mi(Tuple{typeof(s.project), T}, world)
            t === nothing || push!(ts, t)
        end
        site(:trait, i, :project, Any[Any], ts)
    end
    return _Scan(invokes, sites, throws, returns)
end

function _has_native(mi::Core.MethodInstance, world::UInt)
    isdefined(mi, :cache) || return false
    ci = mi.cache
    while true
        ci.owner === nothing && _isvalid(ci, world) && ci.invoke != C_NULL && return true
        isdefined(ci, :next) || return false
        ci = ci.next
    end
end

# reach levels: an error path, a normal path, a normal path inside a `try`
# (where even a throw is followed by more execution)
const _ERR, _NORMAL, _PROTECTED = 0x00, 0x01, 0x02
_sublevel(lv::UInt8, doomed::Bool, intry::Bool) =
    lv == _PROTECTED ? _PROTECTED : lv == _ERR ? _ERR : intry ? _PROTECTED : doomed ? _ERR : _NORMAL

"""
    verify_main(f, argtypes::Tuple = (); compile = false, entrypoints = false) -> MainReport

Check that calling `f` with arguments of types `argtypes` can only reach code
that is compiled ahead of time: every dynamic call either has finitely many
targets known now, or is trait dispatch, whose targets the seals enumerate;
closures handed to the runtime (tasks, `atexit`, finalizers) are followed as
entries of their own. Reports the remaining holes (separating those reached
only on the way to an uncaught `throw`), the trait targets, normal-path method
instances without native code, and a build-time piracy audit of every
enumerated worker. The verdict holds for the current world and seals.

`compile = true` compiles the entry and every enumerated target (call it from
the application package's `@compile_workload` so they land in its image).
`entrypoints = true` registers them with `Base.Experimental.entrypoint` for
`juliac --trim`; when the build is trimmed, it also marks it a closed world
and switches the guard off in the binary: a trimmed binary cannot load code,
this audit is final, and the guard's reflection does not survive trimming.
"""
function verify_main(@nospecialize(f), @nospecialize(argtypes::Tuple = ()); compile::Bool = false, entrypoints::Bool = false)
    world = Base.get_world_counter()
    cx = _Walk(_registry(), world, IdDict{Core.MethodInstance,_Scan}(), Base.IdSet{Core.MethodInstance}())
    reg = cx.reg
    entry = Base.signature_type(f, argtypes)
    root = _target_mi(entry, world)
    root === nothing && error("verify_main: no method for $entry")
    level = IdDict{Core.MethodInstance,UInt8}()
    work = Tuple{Core.MethodInstance,UInt8}[(root, _NORMAL)]
    while !isempty(work)
        mi, lv = pop!(work)
        old = get(level, mi, nothing)
        old !== nothing && old >= lv && continue
        level[mi] = lv
        sc = _get_scan(cx, mi)
        sc === nothing && continue
        for (c, d, t) in sc.invokes
            push!(work, (c, _sublevel(lv, d, t)))
        end
        for s in sc.sites, t in s.targets
            push!(work, (t, _sublevel(lv, s.doomed, s.intry)))
        end
    end
    static_calls = bounded = trait_sites = guard_sites = roots = 0
    holes = Hole[]
    targets = Pair{Symbol,Any}[]
    tseen = Base.IdSet{Any}()
    dyn_roots = Base.IdSet{Any}()   # a trimmed image needs every dynamic target, error paths included
    for (mi, lv) in level
        sc = cx.scans[mi]
        static_calls += length(sc.invokes)
        for s in sc.sites
            if s.kind === :bounded || s.kind === :root
                s.kind === :bounded ? (bounded += 1) : (roots += 1)
                for t in s.targets
                    push!(dyn_roots, t.specTypes)
                end
            elseif s.kind === :trait
                trait_sites += 1
                for t in s.targets
                    t in tseen && continue
                    push!(tseen, t)
                    fT = t.specTypes.parameters[1]
                    kind = fT === typeof(seal_info) ? :seal_info :
                           fT === typeof(op_info) ? :op_info :
                           any(w -> typeof(w) === fT, keys(reg.workers)) ? :worker :
                           s.callee === :project ? :project : :witness
                    push!(targets, kind => t.specTypes)
                end
            elseif s.kind === :guard
                guard_sites += 1
            else
                ep = _sublevel(lv, s.doomed, s.intry) == _ERR
                push!(holes, Hole(s.kind, ep, mi, s.stmt, s.callee, s.argtypes, s.line))
            end
        end
    end
    sort!(holes; by = h -> (h.errorpath, string(h.kind), string(h.callee)))
    # build-time piracy audit: the guard is off in a verified closed-world build
    findings = Pair{Any,Vector{PiracyFinding}}[]
    for (kind, S) in targets
        kind === :worker || continue
        p = S.parameters
        fs = audit(p[1].instance, Tuple{p[2:end]...}; compile = false)
        isempty(fs) || push!(findings, S => fs)
    end
    allroots = Any[entry; [S for (_, S) in targets]; collect(dyn_roots)]
    if compile
        for S in allroots
            ccall(:jl_compile_hint, Int32, (Any,), S)
        end
    end
    if entrypoints
        for S in allroots
            Base.Experimental.entrypoint(S)
        end
        if Base.JLOptions().trim != 0
            # a trimmed binary is a closed world audited here: no method can be
            # added later, and the guard's reflection would not survive trimming
            CLOSED_WORLD[] = true
            MODE[] = :recompile
        end
    end
    generating = ccall(:jl_generating_output, Cint, ()) == 1
    uncompiled = Any[]
    if !generating
        for (mi, lv) in level
            lv != _ERR && !_has_native(mi, Base.get_world_counter()) && push!(uncompiled, mi.specTypes)
        end
    end
    return MainReport(entry, length(level), count(!=(_ERR), values(level)), static_calls, bounded,
                      trait_sites, targets, roots, guard_sites, holes, uncompiled, !generating, findings)
end

function Base.show(io::IO, ::MIME"text/plain", r::MainReport)
    nh = count(h -> !h.errorpath, r.holes)
    ne = length(r.holes) - nh
    verdict = isclosed(r) ? "CLOSED: every call on a normal path reaches enumerated, compiled code" :
              nh > 0 ? "OPEN: $nh dynamic call(s) on normal paths need targets nobody enumerated" :
              "OPEN: $(length(r.uncompiled)) method instance(s) on normal paths lack native code"
    println(io, "verify_main ", r.entry, "\n  ", verdict)
    println(io, "  closure: ", r.reached, " method instances (", r.normal, " on normal paths), ",
            r.static_calls, " static calls")
    kinds = Dict{Symbol,Int}()
    for (k, _) in r.targets; kinds[k] = get(kinds, k, 0) + 1; end
    println(io, "  dynamic calls: ", r.bounded, " bounded; ", r.trait_sites, " trait dispatch sites -> ",
            length(r.targets), " targets (", join(("$v $k" for (k, v) in sort!(collect(kinds))), ", "),
            "); ", r.roots, " runtime closure roots; ", r.guard_sites, " guard")
    groups = Dict{Tuple{Bool,Symbol,String},Vector{Hole}}()
    for h in r.holes
        push!(get!(groups, (h.errorpath, h.kind, _calleestr(h)), Hole[]), h)
    end
    for ep in (false, true)
        ks = sort!([k for k in keys(groups) if k[1] == ep]; by = k -> (-length(groups[k]), k[2], k[3]))
        n = ep ? ne : nh
        println(io, ep ? "  holes on uncaught-error paths only: " : "  holes on normal paths: ", n,
                n > 0 ? " (" * string(length(ks)) * " distinct)" : "")
        lim = ep ? 8 : 25
        for k in first(ks, lim)
            hs = groups[k]
            h = first(hs)
            println(io, "    ", rpad(string(k[2]), 10), rpad(k[3], 60), " ×", length(hs), "  ", h.line)
        end
        length(ks) > lim && println(io, "    … ", length(ks) - lim, " more")
    end
    if r.checked_native
        println(io, "  normal-path method instances without native code: ", length(r.uncompiled))
        for S in first(r.uncompiled, 10)
            println(io, "    ", S)
        end
        length(r.uncompiled) > 10 && println(io, "    … ", length(r.uncompiled) - 10, " more")
    else
        println(io, "  native code: not checked (generating a package image)")
    end
    print(io, "  build-time piracy audit of enumerated workers: ",
          isempty(r.findings) ? "clean" : string(sum(length ∘ last, r.findings)) * " finding(s)")
end

function _calleestr(h::Hole)
    c = h.callee
    s = c isa Function ? string(nameof(c)) : string(c)
    h.argtypes isa Vector || return s
    return s * "(" * join(("::" * string(T) for T in h.argtypes), ", ") * ")"
end

# --- seal code at the signatures the workers call -------------------------------

"""
Witness signatures the registered ops' workers actually call for seal `s`
(at representation `s.R`): declared witness argument types may be abstract
(`pick(r, i)` declares `i::Any`), while workers call at concrete types.
"""
function _seal_witness_sigs(trait::Type, s::Seal, world::UInt)
    out = Any[]
    s.w isa NamedTuple || return out        # an implementation: no operations of the seal's own
    seen = Base.IdSet{Any}()
    for (_, entry) in each_op(trait)
        worker, argts = entry[1], entry[2]
        all(_isleaf, argts) || continue
        mi = _target_mi(Tuple{typeof(worker), typeof(s.w), s.R, argts...}, world)
        mi === nothing || _witness_calls!(out, mi, s, world, seen)
    end
    return out
end

function _witness_calls!(out, mi::Core.MethodInstance, s::Seal, world::UInt, seen)
    mi in seen && return nothing
    push!(seen, mi)
    res = try
        Base.code_typed_by_type(mi.specTypes; optimize = true, world)
    catch
        return nothing
    end
    isempty(res) && return nothing
    src = first(res)[1]
    src isa Core.CodeInfo || return nothing
    sptypes = _CC.sptypes_from_meth_instance(mi)
    W = typeof(s.w)
    for st in src.code
        if Meta.isexpr(st, :call)
            cl = _callee(src, sptypes, st.args[1])
            if cl[1] === :field && cl[2] === W && cl[3] isa Symbol
                ats = Any[_argT(src, sptypes, a) for a in st.args[2:end]]
                all(_isleaf, ats) && push!(out, Tuple{typeof(getfield(s.raw, cl[3])), ats...})
            end
        elseif Meta.isexpr(st, :invoke)
            # statically wired or inlined cross-region calls hand the same table on
            c = st.args[1]
            cmi = c isa Core.CodeInstance ? c.def : c
            cmi isa Core.MethodInstance && any(p -> p === W, cmi.specTypes.parameters) &&
                _witness_calls!(out, cmi, s, world, seen)
        end
    end
    return nothing
end
