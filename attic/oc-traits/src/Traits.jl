module Traits

# The traits-v2 library surface (plan §4.6, milestone M6; this is the first
# @trait/@implement cut that lands with M1). Semantics:
# writeup/reference/traits.md; mechanism: oc-notes/plan.md §4.1-4.2.

export @trait, @implement, isopen, declare_membership

## Runtime hooks (src/datatype.c on the julia-oc branch)

# open a set: set the TypeName's open bit. @trait calls this right after the
# abstract declaration; a `struct S <: X` only picks up the final membership if
# X's bit was already set when S was created.
_open_set!(@nospecialize(T)) = ccall(:jl_set_open_set, Cvoid, (Any,), T)

# is this set open? (authoritative: reads the C bit, not a Julia-side table)
function isopen(@nospecialize(T))::Bool
    dt = T isa DataType ? T : Base.unwrap_unionall(T)
    dt isa DataType || return false
    return ccall(:jl_is_open_set, Cint, (Any,), dt) != 0
end

# the entry point behind @implement; see julia_internal.h for the protocol
function declare_membership(@nospecialize(member), @nospecialize(set_instance),
                            @nospecialize(key), mod::Module, @nospecialize(by))
    return ccall(:jl_declare_membership, Any, (Any, Any, Any, Any, Any),
                 member, set_instance, key, mod, by)
end

## The declaration forms

"""
    @trait X
    @trait X <: A        # A itself open: membership carries over by set-in-set entries
    @trait X{P}
    @trait X{P, Q} <: A

Declare the abstract type `X` as an *open set*: types may become members of it
after its definition — subtypes by `struct S <: X` (a membership final as the
supertype), unrelated types later by `@implement S X`.
"""
macro trait(ex)
    root, head = _trait_head(ex)
    open_fn = _open_set!   # embed the value: resolves independent of hygiene
    return quote
        $(esc(Expr(:abstract, head)))
        ($open_fn)($(esc(root)))
        nothing
    end
end

"""
    @implement S X
    @implement S{T} X{T}      # parametric form: one shared set of parameters

Declare `S` — a `DataType`, a member pattern like `S{T} where T`, or a curly form
with free parameter symbols — a member of the open set `X` *now*, in a fresh
world: `s isa X` becomes true for `S` values in this world and every later one,
and stays false in older worlds. The declared key is the erased key (`nothing` ≡
`Keyed{X, Nothing, Nothing}`); returns the `Core.MembershipEntry`.

In the parametric form (review M1) the member pattern and the set instance are
built over the SAME freshly minted type variables, so the entry binds narrow:
`@implement S{T} X{T}` makes `S{Int}` a member of `X{Int}` (and of the bare
family `X`, whose query a whole-family declaration answers), and not of
`X{String}`. A set expression naming none of the parameters must be the bare
family (its wrapper chain pairs positionally with the pattern's); one naming
only some of them is rejected.
"""
macro implement(s, x)
    mod = __module__
    decl = declare_membership
    ps = _param_syms(mod, s)
    if isempty(ps)
        xs = _param_syms(mod, x)
        isempty(xs) ||
            error("@implement: $(first(xs)) is a free parameter in the set expression but not in the member pattern")
        return quote
            ($decl)($(esc(s)), $(esc(x)), nothing, $mod, nothing)
        end
    end
    tvs = Core.TypeVar.(ps)
    tvmap = IdDict{Any,Any}(ps .=> tvs)
    tup = Expr(:tuple, QuoteNode.(tvs)...)   # the minted variables, as runtime values
    wrap = _wrap_tvs
    mexpr = :($wrap($(esc(_subst_params(s, tvmap))), $tup))
    xs = _param_syms(mod, x)
    all(p -> p in ps, xs) ||
        error("@implement: $(first(setdiff(xs, ps))) is a free parameter in the set expression but not in the member pattern")
    if isempty(xs)
        # bare family instance: pass the set expression through — its own wrapper
        # chain pairs with the pattern chain in jl_membership_lookup (equal depth)
        iexpr = esc(x)
    elseif length(xs) == length(ps)
        iexpr = :($wrap($(esc(_subst_params(x, tvmap))), $tup))
    else
        error("@implement: every parameter of the member pattern must occur in the set expression, or give the bare family name")
    end
    return quote
        ($decl)($mexpr, $iexpr, nothing, $mod, nothing)
    end
end

## Helpers

## Parametric @implement support (review M1)

# free parameter symbols of a declaration side: plain symbols in type-argument
# position that the calling module does not define; names bound by an explicit
# `where` in the same expression are not free
function _param_syms(mod::Module, ex)
    ps = Symbol[]
    _collect_free!(ps, mod, ex, Set{Symbol}())
    return ps
end

function _collect_free!(ps::Vector{Symbol}, mod::Module, ex, bound::Set{Symbol})
    ex isa Expr || return
    if ex.head === :where
        for v in ex.args[2:end]
            if v isa Symbol
                push!(bound, v)
            elseif Meta.isexpr(v, :braces) || Meta.isexpr(v, :curly)
                for w in v.args
                    w isa Symbol && push!(bound, w::Symbol)
                end
            end
        end
        _collect_free!(ps, mod, ex.args[1], bound)
    elseif ex.head === :curly
        for a in ex.args[2:end]     # the head names the type itself, never a parameter
            if a isa Symbol
                !(a in bound) && !(a in ps) && !isdefined(mod, a) && push!(ps, a)
            else
                _collect_free!(ps, mod, a, bound)
            end
        end
    end
    return
end

# replace the free parameter symbols by their minted variables (QuoteNode: the
# object itself, evaluated as a value, so pattern and instance share it)
function _subst_params(ex, tvmap::IdDict{Any,Any})
    if ex isa Symbol
        tv = get(tvmap, ex, nothing)
        return tv === nothing ? ex : QuoteNode(tv::Core.TypeVar)
    elseif ex isa Expr && ex.head === :curly
        args = Any[ex.args[1]]
        for a in ex.args[2:end]
            push!(args, _subst_params(a, tvmap))
        end
        return Expr(ex.head, args...)
    elseif ex isa Expr && ex.head === :where
        return Expr(ex.head, _subst_params(ex.args[1], tvmap), ex.args[2:end]...)
    end
    return ex
end

# wrap the evaluated body in UnionAlls over the shared tvars, first parameter
# outermost — the same order for both sides, so jl_membership_lookup's
# positional pairing lines the chains up
function _wrap_tvs(@nospecialize(body), tvs::Tuple)
    body isa Type || error("@implement: $(body) is not a type")
    for i in lastindex(tvs):-1:1
        body = Base.UnionAll(tvs[i], body)::Type
    end
    return body
end

# `X` | `X{Ps...}` | `X <: A` | `X{Ps...} <: A`  →  (root name, declaration head)
function _trait_head(ex)
    if ex isa Symbol
        return ex, ex
    elseif Meta.isexpr(ex, :curly)
        ex.args[1] isa Symbol || error("@trait: bad type name in $ex")
        return ex.args[1]::Symbol, ex
    elseif Meta.isexpr(ex, :<:)
        lhs = ex.args[1]
        root = lhs isa Symbol ? lhs : Meta.isexpr(lhs, :curly) && lhs.args[1] isa Symbol ? lhs.args[1]::Symbol :
               error("@trait: bad left-hand side in $ex")
        return root, ex
    else
        error("@trait expects `X`, `X <: A`, `X{Ps...}`, or `X{Ps...} <: A`, got $ex")
    end
end

end # module
