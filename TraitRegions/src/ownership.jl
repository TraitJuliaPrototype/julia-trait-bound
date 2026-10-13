# ---------------------------------------------------------------------------
# Ownership — who may change what trait-bound code depends on (design doc,
# "The semantic split"). Julia itself (Base, Core and every standard library)
# is ONE owner. A package owns a method if it owns the function or any type
# mentioned in the method's signature, including type parameters, bounds and
# Union members (Aqua's rule). Package extensions inherit their parent's
# ownership. A package may declare that it implements another package's
# interface:
#
#     [traitbound]
#     implements = ["StaticArraysCore"]
#
# PoC limit: methods are attributed to `parentmodule(m)`; stock Julia records
# no loader context, so a definition laundered through `Core.eval(Owner, …)`
# counts as the owner's.
# ---------------------------------------------------------------------------

const _STDLIBS = Ref{Union{Nothing,Set{Symbol}}}(nothing)

function _stdlib_names()
    s = _STDLIBS[]
    s === nothing || return s
    s = Set{Symbol}(Symbol.(readdir(Sys.STDLIB)))
    _STDLIBS[] = s
    return s
end

"Parent package of a loaded package extension, or `nothing`."
function _extension_parent(r::Module)
    v = get(Base.EXT_PRIMED, Base.PkgId(r), nothing)   # extension => [parent, triggers...]
    v === nothing && return nothing
    return get(Base.loaded_modules, first(v), nothing)
end

"""
    owner(m::Module)

`:Julia` for Base, Core and the standard libraries; otherwise the package's
root module, with package extensions mapped to their parent. Everything
defined at the REPL (any module under `Main`) is owned by `Main`.
"""
function owner(m::Module)
    r = Base.moduleroot(m)
    (r === Base || r === Core) && return :Julia
    nameof(r) in _stdlib_names() && return :Julia
    p = _extension_parent(r)
    return p === nothing ? r : owner(p)
end

# Implementer declarations: interfaces a package may extend as if it owned
# them. Defaults cover the interface/implementation splits measured on the
# CairoMakie stack; packages override or add via Project.toml.
const DEFAULT_IMPLEMENTS = Dict{Symbol,Vector{Symbol}}(
    :StaticArrays     => [:StaticArraysCore],
    :ChainRules       => [:ChainRulesCore],
    :Colors           => [:ColorTypes],
    :ColorVectorSpace => [:ColorTypes],
    :ImageCore        => [:ColorTypes],
    :StatsBase        => [:StatsAPI],
    :Distributions    => [:StatsAPI, :StatsBase],
)

const _IMPLEMENTS = IdDict{Module,Vector{Symbol}}()

"Interfaces package `m` declares it implements (Project.toml `[traitbound] implements`)."
function implements(m::Module)
    get!(_IMPLEMENTS, m) do
        out = copy(get(DEFAULT_IMPLEMENTS, nameof(m), Symbol[]))
        dir = pkgdir(m)
        if dir !== nothing
            proj = joinpath(dir, "Project.toml")
            if isfile(proj)
                toml = Base.parsed_toml(proj)
                # plain haskey/getindex: these are compiled in the sysimage,
                # `get` with a typed default costs ~10 ms of first-use compile
                if haskey(toml, "traitbound")
                    tb = toml["traitbound"]
                    if tb isa Dict && haskey(tb, "implements")
                        for name in tb["implements"]
                            push!(out, Symbol(name::String))
                        end
                    end
                end
            end
        end
        out
    end
end

function _owners!(acc::Base.IdSet{Any}, @nospecialize(T))
    if T isa Union
        _owners!(acc, T.a); _owners!(acc, T.b)
    elseif T isa UnionAll
        _owners!(acc, T.var.lb); _owners!(acc, T.var.ub); _owners!(acc, T.body)
    elseif T isa Core.TypeofVararg
        isdefined(T, :T) && _owners!(acc, T.T)
    elseif T isa DataType
        push!(acc, owner(T.name.module))
        for p in T.parameters
            _owners!(acc, p)
        end
    elseif T isa TypeVar
        _owners!(acc, T.lb); _owners!(acc, T.ub)
    end
    return acc
end

"""
Owners of every function and type mentioned in a method signature. An
identity set on purpose: hashing values of type `Any` is a call other
packages extend, and the audit must not be invalidated by their loads.
"""
sig_owners(@nospecialize(sig)) = _owners!(Base.IdSet{Any}(), sig)

"""
    is_piratical(m::Method)

A method is piratical if its defining package owns neither the function nor
any type mentioned in its signature, and declares no implementer relation to
one of those owners.
"""
function is_piratical(m::Method)
    # registering a region op over someone else's trait is the design, not
    # piracy: `@region` defines `op_info(::Type{Trait}, ::Val{:op})` in the
    # region package, and the A3 guard already refuses cross-package hijack
    sig = Base.unwrap_unionall(m.sig)
    sig isa DataType && length(sig.parameters) >= 1 && sig.parameters[1] === typeof(op_info) && return false
    definer = owner(m.module)
    owners = sig_owners(m.sig)
    definer in owners && return false
    definer isa Module || return true
    # rare and full of TOML handling: kept behind a dynamic call so that its
    # abstract edges cannot invalidate the audit's hot path
    impl = Base.inferencebarrier(implements)(definer)::Vector{Symbol}
    for o in owners
        o isa Module && nameof(o) in impl && return false
    end
    return true
end
