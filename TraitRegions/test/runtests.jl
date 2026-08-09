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
