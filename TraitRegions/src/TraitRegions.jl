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

export @trait, @seal, @region, register!, seal_of, deep_concrete,
       register_op!, precompile_seal, reinit, universe_id, fingerprint,
       sealed, each_seal, unseal!

# ---------------------------------------------------------------------------
# Runtime core
# ---------------------------------------------------------------------------

abstract type AbstractTrait end

"Marker for a trait-method return type declared as `R` (the representation)."
struct SelfR end

struct Seal
    project::Function
    w::NamedTuple          # abstract field: erased witness table
    raw::NamedTuple        # same witnesses, concrete types (@full_compile path)
    R::Type                # inferred representation (Any if inference failed)
end

"""
Seals ARE methods (P0 of the Rung-3 plan): `@seal` defines
`seal_info(::Type{Trait}, ::Type{T}) = <const Seal>` at the conformer's top
level. The method and its constant Seal serialize into the conformer's own
pkgimage and merge into the global table at load — Julia's existing method
machinery replaces the dict registry, deleting the seal-side
`__init__` replay dance entirely.
"""
seal_info(::Type, ::Type) = nothing   # fallback: not sealed

_check_not_sealed(trait::Type, T::Type) =
    seal_info(trait, T) === nothing || error("duplicate seal: $T is already sealed for $trait")

"All seals of `trait`, enumerated from the method table: Vector{Pair{Type,Seal}}."
function each_seal(trait::Type)
    out = Pair{Type,Seal}[]
    for m in methods(seal_info)
        sig = m.sig
        sig isa DataType && length(sig.parameters) == 3 || continue
        Tt, TT = sig.parameters[2], sig.parameters[3]
        Tt isa DataType && Tt <: Type && Tt.parameters[1] === trait || continue
        TT isa DataType && TT <: Type || continue
        T = TT.parameters[1]
        T isa Type || continue
        s = seal_info(trait, T)
        s isa Seal && push!(out, T => s)
    end
    return out
end

"Remove a seal (interactive edits, tests): deletes the `seal_info` method."
function unseal!(trait::Type, T::Type)
    seal_info(trait, T) === nothing && return nothing
    Base.delete_method(which(seal_info, Tuple{Type{trait}, Type{T}}))
    _bump_universe!()
    return nothing
end

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
    s = seal_info(trait, typeof(t))
    s === nothing && error(string(typeof(t)) * " is not sealed for trait " * string(trait))
    return s::Seal
end

"""
Run all fail-early seal checks and construct the Seal (no storage). Checks
(claim C5 — errors name trait, type, and method): witness set matches the
declaration exactly; `project` has a method for `T` and infers a deeply
concrete representation `R`; each witness has a method at `(R, argtypes...)`
with a compatible best-effort return type. Positional NamedTuple so the call
is `@nospecialize`-able.
"""
function build_seal(trait::Type, T::Type, @nospecialize(kw::NamedTuple))
    info = trait_info(trait)

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
        # Silent check-skipping is exactly the cliff C5 exists to prevent:
        # an un-inferable projection means NO witness can be checked.
        error("seal of $T for $trait: could not infer a concrete representation " *
              "from `project` — every seal check would be skipped. Annotate the " *
              "projection's return type or fix its type stability.")
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
    raw = NamedTuple{Tuple(declared)}(fs)   # concrete closure types preserved
    return Seal(project, w, raw, R)
end

"""
Check, build, and define the seal as a method of `seal_info` evaluated in
`mod` — so a seal made at a conformer package's top level is an ordinary
external method extension, serialized in that package's pkgimage and merged
at load like any other method. No `__init__` replay needed for seals.
"""
function _define_seal!(mod::Module, trait::Type, T::Type, @nospecialize(kw::NamedTuple))
    _check_not_sealed(trait, T)
    s = build_seal(trait, T, kw)
    fn = GlobalRef(TraitRegions, :seal_info)
    Base.eval(mod, :($fn(::Type{$trait}, ::Type{$T}) = $s))
    _bump_universe!()
    return nothing
end

"Runtime seal (scripts/tests). For package top level, prefer `@seal` (serializes with the caller)."
register!(trait::Type, T::Type, @nospecialize(kw::NamedTuple)) =
    _define_seal!(TraitRegions, trait, T, kw)

# ---------------------------------------------------------------------------
# Cross-region op registry: ops ARE methods too (P0, mirroring seals).
# `@region` defines `op_info(::Type{Trait}, ::Val{:name}) = (worker, argts)`
# in the region package's own module — serialized in its pkgimage, merged at
# load. The reinit/__init__ replay dance is gone.
# ---------------------------------------------------------------------------

op_info(::Type, ::Val) = nothing   # fallback: no such op

"A3 guard, run before the op_info method definition: refuse cross-package hijack."
function _check_op_free(trait::Type, name::Symbol, @nospecialize(worker::Function))
    existing = op_info(trait, Val(name))
    if existing !== nothing && existing[1] !== worker
        error("region op `$name` for trait $trait is already provided by " *
              "$(parentmodule(existing[1])); refusing cross-package op hijack")
    end
    return nothing
end

"All ops of `trait` from the method table: Vector{Pair{Symbol,Tuple{Function,Tuple}}}."
function each_op(trait::Type)
    out = Pair{Symbol,Tuple{Function,Tuple}}[]
    for m in methods(op_info)
        sig = m.sig
        sig isa DataType && length(sig.parameters) == 3 || continue
        Tt, Vt = sig.parameters[2], sig.parameters[3]
        Tt isa DataType && Tt <: Type && Tt.parameters[1] === trait || continue
        Vt isa DataType && Vt <: Val || continue
        name = Vt.parameters[1]
        name isa Symbol || continue
        entry = op_info(trait, Val(name))
        entry === nothing || push!(out, name => entry)
    end
    return out
end

# ---------------------------------------------------------------------------
# Rung-2-lite: the universe WORLD. Every registration event (seal or region
# op) advances it; nothing else does. `sealed` calls resolve in this pinned
# world, so a method defined after the last registration — a pirate — does
# not exist inside sealed region execution: piracy-immunity as a definition,
# not an observation. This is `Base.invoke_in_world` doing what Rung 3's
# sealed resolution would do natively (pinning *time*; it cannot pin
# *territory* — no allowlist — which is what the full Rung-2 interpreter
# spike would add).
# ---------------------------------------------------------------------------

const UNIVERSE_WORLD = Ref{UInt}(0)

_bump_universe!() = (UNIVERSE_WORLD[] = Base.get_world_counter(); nothing)

__init__() = _bump_universe!()

"""
    sealed(Trait, :op, t, args...)

Run region op `:op` with method resolution pinned to the universe world (the
world as of the last seal/op registration). Definitions made since — e.g. a
pirated Base method at the representation's types — are invisible: the
sealed call keeps executing the pre-pirate code, with zero recompilation.
"""
function sealed(trait::Type, opname::Symbol, @nospecialize(t), args...)
    entry = op_info(trait, Val(opname))
    entry === nothing && error("no region op `$opname` for trait $trait")
    s = seal_of(trait, t)
    world = UNIVERSE_WORLD[]
    r = Base.invoke_in_world(world, s.project, t)
    return Base.invoke_in_world(world, entry[1], s.w, r, args...)
end

"Runtime op registration (scripts/tests): defines the op_info method via eval."
function register_op!(trait::Type, name::Symbol, @nospecialize(worker::Function), @nospecialize(argts::Tuple))
    _check_op_free(trait, name, worker)
    @eval op_info(::Type{$trait}, ::Val{$(QuoteNode(name))}) = ($worker, $argts)
    _bump_universe!()
    return nothing
end

"Dynamic cross-region call: the honest Rung-1 lowering (op lookup + dynamic dispatch per call)."
function dyncall(trait::Type, name::Symbol, @nospecialize(w), @nospecialize(r), args...)
    entry = op_info(trait, Val(name))
    entry === nothing &&
        error("no witness or region op `$name` for trait $trait (witness tables and the op registry were both consulted)")
    return entry[1](w, r, args...)
end

"Precompile-time check that a statically-wired import really is a region op of this trait."
function check_import(trait::Type, mod::Module, name::Symbol)
    entry = op_info(trait, Val(name))
    entry === nothing &&
        error("@region imports: `$name` is not a registered op of trait $trait (is $mod loaded?)")
    worker = getproperty(mod, Symbol(name, "#worker"))
    entry[1] === worker ||
        error("@region imports: `$mod.$name` does not match the registered worker for trait $trait")
    return nothing
end

"Deprecated no-op: ops are methods now (serialized with the region package); nothing to replay."
reinit(::Module) = nothing

"""
    precompile_seal(Trait, T)

Precompile every registered region op's worker for `T`'s representation.
Call from a conformer package's precompile workload (after sealing) so the
conformer's pkgimage owns the workers for any representation it introduces.
"""
function precompile_seal(trait::Type, T::Type)
    s = seal_info(trait, T)
    s === nothing && error("precompile_seal: $T is not sealed for $trait")
    n = 0
    for (_, (worker, argts)) in each_op(trait)
        precompile(worker, (typeof(s.w), s.R, argts...)) && (n += 1)
    end
    return n
end

# ---------------------------------------------------------------------------
# Fingerprints and universe id (best-effort, Rung-1)
# ---------------------------------------------------------------------------

"Best-effort fingerprint of a witness: method signature + source location."
function fingerprint(@nospecialize(f::Function))
    h = hash(0x7261)
    for m in methods(f)
        h = hash((m.sig, m.file, m.line), h)
    end
    return h
end

fingerprint(s::Seal) = reduce(hash, (fingerprint(f) for f in values(s.w)); init = fingerprint(s.project))

"Hash of every seal of every registered trait — drifts when any witness is edited."
function universe_id()
    h = hash(0x756e69)
    traits = Base.IdSet{Any}()
    for m in methods(op_info)
        sig = m.sig
        sig isa DataType && length(sig.parameters) == 3 || continue
        Tt, Vt = sig.parameters[2], sig.parameters[3]
        Tt isa DataType && Tt <: Type && Vt isa DataType && Vt <: Val || continue
        h = hash(Vt.parameters[1], h)
        push!(traits, Tt.parameters[1])
    end
    for trait in traits
        for (T, s) in each_seal(trait)
            h = hash((T, fingerprint(s)), h)
        end
    end
    return h
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
    return esc(quote
        struct $name <: TraitRegions.AbstractTrait end
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
    return esc(:(TraitRegions._define_seal!($(__module__), $trait, $T, ($(kws...),))))
end

# ---------------------------------------------------------------------------
# @region
# ---------------------------------------------------------------------------

_count_symbol(ex, s::Symbol) =
    ex === s ? 1 :
    ex isa Expr ? sum(a -> _count_symbol(a, s), ex.args; init = 0) : 0

"""
Rewrite `g(t, xs...)` recursively; `t` may not appear anywhere else.
Three lowerings, chosen per call site:
  * `g` in the region's declared imports → **static** call to the other
    region package's worker (`Mod.var"g#worker"(w, r, xs...)`) — the
    faked-native lowering: inlinable, no table, no dynamic dispatch;
  * otherwise → `haskey(w, :g)` branch (folds at compile time, since the
    witness-table type is concrete in the worker): witness call if `g` is a
    witness, else `dyncall` through the op registry — the honest Rung-1
    dynamic cross-region lowering.
"""
function _rewrite_body(ex, tname::Symbol, w::Symbol, r::Symbol, trait, imports::Dict{Symbol,Any})
    ex isa Expr || return ex
    if ex.head === :call && length(ex.args) >= 2 && ex.args[2] === tname
        g = ex.args[1]
        g isa Symbol ||
            error("@region: trait call with non-symbol callee: $(ex)")
        rest = [_rewrite_body(a, tname, w, r, trait, imports) for a in ex.args[3:end]]
        if haskey(imports, g)
            workerref = Expr(:., imports[g], QuoteNode(Symbol(g, "#worker")))
            return :($workerref($w, $r, $(rest...)))
        end
        q = QuoteNode(g)
        return :(haskey($w, $q) ? getfield($w, $q)($r, $(rest...)) :
                 TraitRegions.dyncall($trait, $q, $w, $r, $(rest...)))
    end
    return Expr(ex.head, (_rewrite_body(a, tname, w, r, trait, imports) for a in ex.args)...)
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

_argtype(a) = (a isa Expr && a.head === :(::)) ? a.args[end] : :Any

function _rewrite_op(trait, fdef, imports::Dict{Symbol,Any}, fc::Bool)
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
    argts = map(_argtype, extras)

    worker = Symbol(fname, "#worker")
    w = gensym(:w); r = gensym(:r)
    newbody = _rewrite_body(body, tname, w, r, trait, imports)
    n = _count_symbol(newbody, tname)
    n == 0 || error("@region: in op `$fname`, `$tname` escapes trait position " *
                    "($n occurrence(s) outside first-argument-of-call); " *
                    "regions may touch the trait object only through trait calls")

    workerdef = if retanno === nothing
        :(Base.@noinline function $worker($w, $r, $(extras...))
            $newbody
        end)
    else
        :(Base.@noinline function $worker($w, $r, $(extras...))::$retanno
            $newbody
        end)
    end
    # @full_compile entries hand the worker the *concrete* witness tuple:
    # Julia then monomorphizes the whole call chain per witness set.
    table = fc ? :(s.raw) : :(s.w)
    entrydef = :(function $fname(Base.@nospecialize($tname), $(extras...))
        s = TraitRegions.seal_of($trait, $tname)
        $worker($table, s.project($tname), $(extranames...))
    end)
    return workerdef, entrydef, fname, worker, argts
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
_is_fdef(ex) = ex isa Expr && (ex.head === :function || (ex.head === :(=) && ex.args[1] isa Expr &&
               (ex.args[1].head === :call ||
                (ex.args[1].head === :(::) && ex.args[1].args[1] isa Expr && ex.args[1].args[1].head === :call))))

"""
    @region Trait [Mod.op, Mod.op2, ...] begin ... end

Optional second argument: statically-wired cross-region imports (the
faked-native lowering). Ops may be preceded by `@full_compile` to opt into
per-witness-set monomorphization. Region packages loaded from a pkgimage
must call `TraitRegions.reinit(@__MODULE__)` in `__init__` to replay op
registrations.
"""
macro region(trait, rest...)
    length(rest) in (1, 2) || error("@region: expected `@region Trait [imports] begin ... end`")
    block = rest[end]
    block isa Expr && block.head === :block || error("@region: expected a begin/end block")
    imports = Dict{Symbol,Any}()
    if length(rest) == 2
        iv = rest[1]
        iv isa Expr && iv.head === :vect ||
            error("@region: imports must be a vector literal like [ColStats.colmean, ...]")
        for item in iv.args
            item isa Expr && item.head === :. && item.args[2] isa QuoteNode ||
                error("@region: each import must be `Module.opname`, got $item")
            imports[item.args[2].value] = item.args[1]
        end
    end
    out = Any[]
    regs = Any[]     # op_info method definitions + checks, all top-level
    for ex in block.args
        fc = false
        inner = ex
        if ex isa Expr && ex.head === :macrocall && ex.args[1] === Symbol("@full_compile")
            fc = true
            inner = ex.args[end]
        end
        if _is_fdef(inner)
            if _is_region_op(inner)
                workerdef, entrydef, fname, worker, argts = _rewrite_op(trait, inner, imports, fc)
                push!(out, workerdef, entrydef)
                push!(regs, :(TraitRegions._check_op_free($trait, $(QuoteNode(fname)), $worker)))
                push!(regs, :(TraitRegions.op_info(::Type{$trait}, ::Val{$(QuoteNode(fname))}) =
                                  ($worker, ($(argts...),))))
            else
                push!(out, inner)   # helper: first argument is `::`-annotated
            end
        else
            push!(out, ex)   # LineNumberNodes, using, const, plain code
        end
    end
    for (name, mod) in imports
        push!(regs, :(TraitRegions.check_import($trait, $mod, $(QuoteNode(name)))))
    end
    push!(out, regs..., :(TraitRegions._bump_universe!()))
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

# top level, not in the workload: the seal_info method must exist in the
# world the workload block was lowered in (1.12 enforces this strictly)
@seal _PCTrait _PCDummy begin
    project(t) = t.cols
    ncols(r)   = length(r)
    col(r, i)  = r[i]
end

@compile_workload begin
    _pc_op(_PCDummy([[1.0, 2.0]]), 1)
    precompile_seal(_PCTrait, _PCDummy)
end

end # module
