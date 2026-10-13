using Test
using TraitRegions

@trait ColTable begin
    ncols(r)::Int
    col(r, i::Int)::Vector{Float64}
end

struct TableA
    cols::Vector{Vector{Float64}}
end
struct TableB              # different layout, same representation after project
    a::Vector{Float64}
    b::Vector{Float64}
end
struct BadReturn
    cols::Vector{Vector{Float64}}
end
struct AbstractRep
    cols::Vector{Any}
end

@seal ColTable TableA begin
    project(t) = t.cols
    ncols(r)   = length(r)
    col(r, i)  = r[i]
end

@seal ColTable TableB begin
    project(t) = [t.a, t.b]
    ncols(r)   = length(r)
    col(r, i)  = r[i]
end

@region ColTable begin
    # helper (first arg is not the trait object) — passed through untouched
    _mean(c::Vector{Float64}) = sum(c) / max(length(c), 1)

    colmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})

    function meantotal(t)
        n = ncols(t)::Int
        acc = 0.0
        for i in 1:n
            acc += _mean(col(t, i)::Vector{Float64})
        end
        acc / max(n, 1)
    end
end

@testset "correctness" begin
    ta = TableA([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    tb = TableB([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
    @test colmean(ta, 1) == 2.0
    @test colmean(tb, 2) == 5.0
    @test meantotal(ta) == meantotal(tb) == 3.5
end

@testset "fail-early seal checks" begin
    @test_throws "not sealed" colmean(BadReturn([[1.0]]), 1)
    # duplicate seal
    @test_throws "already sealed" @seal ColTable TableA begin
        project(t) = t.cols
        ncols(r)   = length(r)
        col(r, i)  = r[i]
    end
    # missing witness
    @test_throws "missing witness `col`" TraitRegions.register!(ColTable, BadReturn,
        (project = t -> t.cols, ncols = r -> length(r)))
    # unknown witness
    @test_throws "not a method of" TraitRegions.register!(ColTable, BadReturn,
        (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i],
         extra = r -> 1))
    # wrong declared return type, caught at seal time
    @test_throws "returns" TraitRegions.register!(ColTable, BadReturn,
        (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> Float32.(r[i])))
    # non-deeply-concrete representation rejected
    @test_throws "not deeply concrete" TraitRegions.register!(ColTable, AbstractRep,
        (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
end

@testset "escape check" begin
    # `t` used outside trait-call position must be a macro-time error
    @test_throws LoadError @eval @region ColTable begin
        leak(t, i::Int) = (x = t; ncols(t))
    end
    @test_throws LoadError @eval @region ColTable begin
        leak2(t) = sum(map(x -> x, [t]))
    end
end

@testset "sharing: one worker per representation" begin
    ms = methods(var"colmean#worker")
    @test length(ms) == 1
    # one abstract instance from inferring the @nospecialize entry (constant),
    # and exactly ONE concrete instance shared by TableA and TableB
    concrete = filter(mi -> isconcretetype(mi.specTypes.parameters[3]),
                      collect(Base.specializations(ms[1])))
    @test length(concrete) == 1
end

# @trait/@region generate structs and consts, so they are top-level-only
# (same restriction as @enum)
@trait Chunky begin
    whole(r)::R
end
struct CT
    v::Vector{Float64}
end
@seal Chunky CT begin
    project(t) = t.v
    whole(r)   = r
end
@region Chunky begin
    total(t) = sum(whole(t)::Vector{Float64})
end

@testset "R-returning trait methods" begin
    @test total(CT([1.0, 2.0])) == 3.0
end

# --- cross-region composition, @full_compile, precompile enumeration --------

@region ColTable begin
    # `colmean` is a region op, not a witness: lowers to the dynamic op-registry call
    doublemean(t, i::Int) = 2 * colmean(t, i)
end

# a second "package" statically importing ops from the first
module StaticImporter
    using Main: TraitRegions, ColTable
    TraitRegions.@region ColTable [Main.colmean] begin
        triplemean(t, i::Int) = 3 * colmean(t, i)   # static call into Main's worker
    end
end

@region ColTable begin
    @full_compile fastmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})
end

@testset "cross-region + fc + enumeration" begin
    ta = TableA([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    @test doublemean(ta, 1) == 4.0                      # dynamic op-table route
    @test StaticImporter.triplemean(ta, 1) == 6.0       # static-wired route
    @test fastmean(ta, 1) == 2.0                        # @full_compile route
    # fc worker specialized on the concrete witness tuple, not the erased one
    fcmis = collect(Base.specializations(first(methods(var"fastmean#worker"))))
    @test any(fcmis) do mi
        p = mi.specTypes.parameters[2]
        p isa DataType && p <: NamedTuple && p.parameters[2] != NTuple{2,Function}
    end
    # enumeration precompiles workers for a seal's representation
    @test TraitRegions.precompile_seal(ColTable, TableA) >= 4
    # universe id drifts when a new seal arrives
    u1 = universe_id()
    struct Extra; cols::Vector{Vector{Float64}}; end
    TraitRegions.register!(ColTable, Extra,
        (project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
    @test universe_id() != u1
end

# --- Rung-2-lite: world-pinned (sealed) execution ---------------------------

@testset "sealed execution survives piracy" begin
    ta = TableA([[3.0, 1.0, 2.0]])
    normal_before = doublemean(ta, 1)
    sealed_before = sealed(ColTable, :doublemean, ta, 1)
    @test normal_before == sealed_before == 4.0
    # redefine the region helper AFTER the universe world was pinned
    # (no Base piracy here — that would leak into later testsets)
    @eval _mean(c::Vector{Float64}) = 99.0
    @test sealed(ColTable, :doublemean, ta, 1) == 4.0        # pinned world: old helper
    @test doublemean(ta, 1) == 198.0                          # live world: new helper
end

# --- the error split (design doc, Stage 1) ----------------------------------
# Main is a pirate whenever it defines a method on a Base function for Base
# types only. These testsets define one such pirate, so they run last.

@testset "ownership rule" begin
    @test TraitRegions.owner(Base) === :Julia
    @test TraitRegions.owner(Core) === :Julia
    @test TraitRegions.owner(TraitRegions) === TraitRegions
    @test TraitRegions.owner(StaticImporter) === Main            # REPL code is Main's
    # LinearAlgebra-style stdlib methods on Base functions are Julia's own, not piracy
    @test !TraitRegions.is_piratical(first(methods(sum, (Vector{Float64},))))
    # a method mentioning one of the definer's types is owned (Aqua's rule)
    @test !TraitRegions.is_piratical(which(TraitRegions.seal_info, Tuple{Type{ColTable}, Type{TableA}}))
    # orphan rule: Main owns neither TraitRegions' private trait nor a Base type
    TraitRegions.mode!(:error)
    @test_throws "orphan seal" TraitRegions._check_orphan(Main, TraitRegions._PCTrait, Vector{Vector{Float64}})
    @test TraitRegions._check_orphan(Main, ColTable, Vector{Vector{Float64}}) === nothing   # Main owns ColTable
    TraitRegions.mode!(:warn)
end

@testset "catch blocks rethrow PiracyError" begin
    ex = TraitRegions._rethrow_piracy(:(try f() catch; 0 end))
    @test ex.args[2] isa Symbol                                 # a catch variable was added
    @test occursin("PiracyError", string(ex.args[3]))
end

@trait Int8Bag begin
    items(r)::Vector{Int8}
end
struct Bag
    v::Vector{Int8}
end
@seal Int8Bag Bag begin
    project(t) = t.v
    items(r)   = r
end
@region Int8Bag begin
    bagsum(t) = sum(items(t)::Vector{Int8})
    # dynamic call into another op; the catch must not swallow PiracyError
    safesum(t) = try
        bagsum(t)
    catch
        -1
    end
end

@testset "guard: piracy against trait-bound code" begin
    b = Bag(Int8[1, 2, 3])
    @test bagsum(b) == 6
    @test isempty(TraitRegions.audit_all())
    # a legitimate method for Main's own type changes nothing
    @eval Base.show(io::IO, ::Bag) = print(io, "Bag")
    @test bagsum(b) == 6
    # the pirate: Main owns neither `sum` nor `Vector{Int8}`
    @eval Base.sum(v::Vector{Int8}) = 42
    TraitRegions.mode!(:error)
    err = try bagsum(b); nothing catch e; e end
    @test err isa PiracyError
    @test occursin("sum(v::Vector{Int8})", sprint(showerror, err))
    @test_throws PiracyError safesum(b)                         # not swallowed by `catch`
    @test !isempty(TraitRegions.audit_all())
    TraitRegions.mode!(:warn)
    @test (@test_logs (:warn, r"PiracyError") bagsum(b)) == 42   # warned once, runs on the pirate
    @test (@test_logs bagsum(b)) == 42                           # not warned again
    TraitRegions.mode!(:recompile)
    @test (@test_logs bagsum(b)) == 42
    TraitRegions.mode!(:warn)
end
