"""
TraitRegions — Rung-1 prototype of trait-bounded regions for Julia.

    @trait ColTable begin
        ncols(r)::Int
        col(r, i::Int)::Vector{Float64}
    end

    @seal ColTable MyTable begin
        project(t) = t.cols
        ncols(r)   = length(r)
        col(r, i)  = r[i]
    end

    @region ColTable begin
        colmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})
    end

Each `@region` function `f(t, args...)` is rewritten into a tiny
non-specializing entry — seal lookup, projection to the representation `R`,
then a call into `f_worker(w, r, args...)` — plus the worker itself, in which
every call `g(t, …)` has become a dynamic call through the seal's witness
table `w`. Workers therefore key on `R` (the representation), not on the user
type `T`: N sealed types over one representation share one compiled worker
per op, workers precompile into pkgimages and are reachable by types that did
not exist at precompile time, and — because dynamic calls create no inference
edges — no witness edit or unrelated method definition can invalidate them.

Design notes carried over from the M0 spike (see session-notes/):
  * witness tables are plain-`Function` NamedTuples ("dyn" path): registration
    compiles nothing, there is no stale-pointer window, steady-state cost
    matches FunctionWrappers on chunky signatures;
  * entries and registration are `@nospecialize` throughout — one compiled
    instance each, ever;
  * trait knowledge lives at seal *time* (runtime checks), the region rewrite
    is purely syntactic — so traits, seals, and regions may live in different
    packages without macro-expansion-order coupling.
"""
module TraitRegions

export @trait, @seal, @region, register!, seal_of, deep_concrete

# ---------------------------------------------------------------------------
# Runtime core
# ---------------------------------------------------------------------------

abstract type AbstractTrait end

"Marker for a trait-method return type declared as `R` (the representation)."
struct SelfR end

struct Seal
    project::Function
    w::NamedTuple          # abstract field: erased witness table
    R::Type                # inferred representation (Any if inference failed)
end

"""Overloaded per trait by `@trait`: returns the trait's `IdDict{Type,Seal}`."""
function seal_registry end

"""Overloaded per trait by `@trait`: declared methods as a NamedTuple
`name => (args = (T...,), ret = Type-or-SelfR)`, in declaration order."""
function trait_info end

"Recursive concreteness: `T`, its type parameters, and its field types, all the way down (`Vector{Any}` is concrete but not deeply concrete)."
function deep_concrete(@nospecialize(T); seen = Base.IdSet{Any}())
    T isa Type || return true          # value-type parameters (1, :a, …)
    T in seen && return true
    push!(seen, T)
    isconcretetype(T) || return false
    if T isa DataType
        all(p -> deep_concrete(p; seen), T.parameters) || return false
    end
    return all(ft -> deep_concrete(ft; seen), fieldtypes(T))
end

function seal_of(trait::Type, @nospecialize(t))
    s = get(seal_registry(trait), typeof(t), nothing)
    s === nothing && error(string(typeof(t)) * " is not sealed for trait " * string(trait))
    return s::Seal
end

"""
    register!(Trait, T, (; project, witnesses...))

Runtime seal: fail-early checks, then store the seal. Called by `@seal`, and
usable directly. Checks (claim C5 — errors name trait, type, and method):
  1. no duplicate seal for `T`;
  2. the witness set matches the trait's declared methods exactly;
  3. `project` has a method for `T`; its return type `R` is inferred
     (best-effort) and deep-concreteness of `R` is required;
  4. each witness has a method for `(R, declared argtypes...)`;
  5. best-effort: each witness's inferred return type must be a subtype of
     the declared one (`R` declarations check against the inferred `R`).

Takes the witnesses as a positional NamedTuple (not kwargs) so the whole call
is `@nospecialize`-able: sealing compiles nothing but the witness bodies.
"""
function register!(trait::Type, T::Type, @nospecialize(kw::NamedTuple))
    info = trait_info(trait)
    reg = seal_registry(trait)
    haskey(reg, T) &&
        error("duplicate seal: $T is already sealed for $trait")

    haskey(kw, :project) ||
        error("seal of $T for $trait: missing `project`")
    project = kw[:project]

    declared = keys(info)
    given = filter(!=(:project), keys(kw))
    for name in declared
        name in given ||
            error("seal of $T for $trait: missing witness `$name`")
    end
    for name in given
        name in declared ||
            error("seal of $T for $trait: `$name` is not a method of $trait")
    end

    hasmethod(project, Tuple{T}) ||
        error("seal of $T for $trait: `project` has no method for ($T,)")
    rts = Base.return_types(project, Tuple{T})
    R = (length(rts) == 1 && isconcretetype(rts[1])) ? rts[1] : Any
    if R === Any
        @warn "seal of $T for $trait: could not infer a concrete representation from `project`; seal checks degraded" T trait
    else
        deep_concrete(R) ||
            error("seal of $T for $trait: representation $R is not deeply concrete " *
                  "(abstract fields would make every worker slow for every user of $R)")
    end

    for name in declared
        f = kw[name]
        m = info[name]
        if R !== Any
            sig = Tuple{R, m.args...}
            hasmethod(f, sig) ||
                error("seal of $T for $trait: witness `$name` has no method for $sig")
            want = m.ret === SelfR ? R : m.ret
            got = Base.return_types(f, sig)
            if length(got) == 1 && got[1] !== Any && !(got[1] <: want)
                error("seal of $T for $trait: witness `$name` returns $(got[1]), " *
                      "declared $want")
            end
        end
    end

    fs = Tuple(Function[kw[name] for name in declared])
    w = NamedTuple{Tuple(declared), NTuple{length(fs), Function}}(fs)
    reg[T] = Seal(project, w, R)
    return nothing
end

# ---------------------------------------------------------------------------
# @trait
# ---------------------------------------------------------------------------

function _parse_trait_sig(ex)
    ex isa Expr && ex.head === :(::) ||
        error("@trait: expected `name(r, args...)::RetType`, got $ex")
    call, ret = ex.args
    call isa Expr && call.head === :call ||
        error("@trait: expected a method signature, got $ex")
    name = call.args[1]
    name isa Symbol || error("@trait: method name must be a symbol, got $name")
    length(call.args) >= 2 ||
        error("@trait: method `$name` needs at least the representation argument")
    argts = Any[]
    for a in call.args[3:end]     # first arg is `r` — untyped by definition
        if a isa Expr && a.head === :(::)
            push!(argts, a.args[end])
        else
            push!(argts, :Any)
        end
    end
    retex = ret === :R ? :(TraitRegions.SelfR) : ret
    return name, argts, retex
end

"""
    @trait Name begin
        method(r, args...)::RetType
        ...
    end

Declare a trait over an (unnamed) representation. `RetType` may be `R`,
meaning "the representation type itself". Generates the trait tag type, its
seal registry, and its declared-method table.
"""
macro trait(name, block)
    name isa Symbol || error("@trait: trait name must be a symbol")
    block isa Expr && block.head === :block || error("@trait: expected a begin/end block")
    entries = Any[]
    for ex in block.args
        ex isa LineNumberNode && continue
        mname, argts, retex = _parse_trait_sig(ex)
        push!(entries, :($mname = (args = ($(argts...),), ret = $retex)))
    end
    isempty(entries) && error("@trait: trait $name declares no methods")
    regname = Symbol("##seals#", name)
    return esc(quote
        struct $name <: TraitRegions.AbstractTrait end
        const $regname = Base.IdDict{Type, TraitRegions.Seal}()
        TraitRegions.seal_registry(::Type{$name}) = $regname
        TraitRegions.trait_info(::Type{$name}) = ($(entries...),)
        $name
    end)
end

# ---------------------------------------------------------------------------
# @seal
# ---------------------------------------------------------------------------

function _parse_seal_def(ex)
    if ex isa Expr && ex.head === :(=) && ex.args[1] isa Expr && ex.args[1].head === :call
        call, body = ex.args
    elseif ex isa Expr && ex.head === :function
        call, body = ex.args
    else
        error("@seal: expected witness definitions `name(args...) = body`, got $ex")
    end
    name = call.args[1]
    name isa Symbol || error("@seal: witness name must be a symbol, got $name")
    args = call.args[2:end]
    return name, :(($(args...),) -> $body)
end

"""
    @seal Trait T begin
        project(t) = ...
        witness(r, args...) = ...
    end

Seal type `T` for `Trait`: the definitions become anonymous witness functions
passed to [`register!`](@ref), which runs all fail-early checks at this point.
"""
macro seal(trait, T, block)
    block isa Expr && block.head === :block || error("@seal: expected a begin/end block")
    kws = Any[]
    for ex in block.args
        ex isa LineNumberNode && continue
        name, fn = _parse_seal_def(ex)
        push!(kws, Expr(:(=), name, fn))
    end
    return esc(:(TraitRegions.register!($trait, $T, ($(kws...),))))
end

# ---------------------------------------------------------------------------
# @region
# ---------------------------------------------------------------------------

_count_symbol(ex, s::Symbol) =
    ex === s ? 1 :
    ex isa Expr ? sum(a -> _count_symbol(a, s), ex.args; init = 0) : 0

"Rewrite `g(t, xs...)` → `getfield(w, :g)(r, xs...)` recursively; `t` may not appear anywhere else."
function _rewrite_body(ex, tname::Symbol, w::Symbol, r::Symbol)
    ex isa Expr || return ex
    if ex.head === :call && length(ex.args) >= 2 && ex.args[2] === tname
        ex.args[1] isa Symbol ||
            error("@region: trait call with non-symbol callee: $(ex)")
        rest = [_rewrite_body(a, tname, w, r) for a in ex.args[3:end]]
        return :(getfield($w, $(QuoteNode(ex.args[1])))($r, $(rest...)))
    end
    return Expr(ex.head, (_rewrite_body(a, tname, w, r) for a in ex.args)...)
end

_argname(a) = a isa Symbol ? a :
              (a isa Expr && a.head === :(::)) ? a.args[1] :
              error("@region: unsupported argument form $a (positional, optionally `::T`-annotated, only)")

"An op takes the (erased, hence untyped) trait object first: bare-symbol first arg."
function _is_region_op(fdef)
    call = fdef.args[1]
    call isa Expr && call.head === :(::) && (call = call.args[1])
    call isa Expr && call.head === :call || return false
    length(call.args) >= 2 || return false
    first_arg = call.args[2]
    first_arg isa Expr && first_arg.head === :parameters && length(call.args) >= 3 &&
        (first_arg = call.args[3])
    return first_arg isa Symbol
end

function _rewrite_op(trait, fdef)
    if fdef.head === :(=) || fdef.head === :function
        call, body = fdef.args[1], fdef.args[2]
    else
        error("@region: expected a function definition, got $(fdef.head)")
    end
    retanno = nothing
    if call isa Expr && call.head === :(::)
        retanno = call.args[2]
        call = call.args[1]
    end
    call isa Expr && call.head === :call ||
        error("@region: expected `f(t, args...)`, got $call")
    any(a -> a isa Expr && (a.head === :parameters || a.head === :kw), call.args) &&
        error("@region: keyword/optional arguments are not supported in region ops")
    fname = call.args[1]
    fname isa Symbol || error("@region: op name must be a symbol")
    length(call.args) >= 2 || error("@region: op `$fname` needs the trait object as first argument")
    tname = _argname(call.args[2])
    extras = call.args[3:end]
    extranames = map(_argname, extras)

    worker = Symbol(fname, "#worker")
    w = gensym(:w); r = gensym(:r)
    newbody = _rewrite_body(body, tname, w, r)
    n = _count_symbol(newbody, tname)
    n == 0 || error("@region: in op `$fname`, `$tname` escapes trait position " *
                    "($n occurrence(s) outside first-argument-of-call); " *
                    "regions may touch the trait object only through trait calls")

    workerdef = :(Base.@noinline function $worker($w, $r, $(extras...))
        $newbody
    end)
    if retanno !== nothing
        workerdef = :(Base.@noinline function $worker($w, $r, $(extras...))::$retanno
            $newbody
        end)
    end
    entrydef = :(function $fname(Base.@nospecialize($tname), $(extras...))
        s = TraitRegions.seal_of($trait, $tname)
        $worker(s.w, s.project($tname), $(extranames...))
    end)
    return workerdef, entrydef, fname, worker
end

"""
    @region Trait begin
        f(t, args...) = ...
        ...
    end

Rewrite each function into a non-specializing per-`T` entry plus a worker
keyed on the representation. Within an op, the trait object may be used
*only* as the first argument of a call — every such call becomes a witness
call; any other use of it is a macro-time error. Distinguishing rule: the
trait object is always untyped (it is erased), so a definition whose first
argument is a bare symbol is an op; a definition whose first argument carries
a `::` annotation is a helper and passes through untouched.

Trait calls should carry their declared return type at the use site
(`col(t, i)::Vector{Float64}`) to keep worker bodies type-stable; without an
assert the call is still correct but downstream code pays dynamic dispatch.
"""
macro region(trait, block)
    block isa Expr && block.head === :block || error("@region: expected a begin/end block")
    out = Any[]
    for ex in block.args
        if ex isa Expr && (ex.head === :function || (ex.head === :(=) && ex.args[1] isa Expr &&
                           (ex.args[1].head === :call ||
                            (ex.args[1].head === :(::) && ex.args[1].args[1] isa Expr && ex.args[1].args[1].head === :call))))
            if _is_region_op(ex)
                workerdef, entrydef, _, _ = _rewrite_op(trait, ex)
                push!(out, workerdef, entrydef)
            else
                push!(out, ex)   # helper: first argument is `::`-annotated
            end
        else
            push!(out, ex)   # LineNumberNodes, using, const, plain code
        end
    end
    return esc(Expr(:block, out..., :nothing))
end

# ---------------------------------------------------------------------------
# Precompile the machinery itself (registration, lookup, checks) so sealing a
# type in a fresh session costs the user's witness bodies and nothing else.
# The private trait/region live at top level (structs cannot be defined in
# the workload's local scope); only the calls run in the workload.
# ---------------------------------------------------------------------------

using PrecompileTools: @compile_workload

struct _PCDummy
    cols::Vector{Vector{Float64}}
end

@trait _PCTrait begin
    ncols(r)::Int
    col(r, i::Int)::Vector{Float64}
end

@region _PCTrait begin
    _pc_op(t, i::Int) = sum(col(t, i)::Vector{Float64}) + ncols(t)
end

@compile_workload begin
    register!(_PCTrait, _PCDummy,
              (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
    _pc_op(_PCDummy([[1.0, 2.0]]), 1)
    empty!(seal_registry(_PCTrait))
end

end # module
