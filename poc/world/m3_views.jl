# M3: several bounds, several views; joint projections; projections that copy (rule 4).
#   julia --startup-file=no --project=poc/world/env poc/world/m3_views.jl
using TraitWorld, Columns, Rows, Stats
const TW = TraitWorld
const PROJECTIONS = Ref(0)

# separate projections: one per trait, onto different representations
struct Sep; cols::Vector{Vector{Float64}}; rows::Matrix{Float64}; end
@implement ColTable Sep project(t) = (PROJECTIONS[] += 1; t.cols)
@implement RowTable Sep project(t) = (PROJECTIONS[] += 1; t.rows)
# one projection for both traits: Matrix{Float64} implements ColTable (Columns) and RowTable (Rows)
struct Joint; m::Matrix{Float64}; end
@implement (ColTable, RowTable) Joint project(t) = (PROJECTIONS[] += 1; t.m)

m = [1.0 2.0; 3.0 4.0]
for (label, x) in (("separate projections", Sep([[1.0, 3.0], [2.0, 4.0]], m)), ("one joint projection", Joint(m)))
    PROJECTIONS[] = 0
    r = overview(x)
    println(rpad(label, 24), "overview = ", r, "   projections run: ", PROJECTIONS[])
end
# what the worker receives: one view per trait, each with its own representation
function views(x)
    b = TW._builder(overview, 1, 1, typeof(x))
    tobj = b(x)
    [(nameof(typeof(v).parameters[1]), typeof(v).parameters[3]) for v in tobj.views]
end
println("\nviews of Sep:   ", views(Sep([[1.0]], m)))
println("views of Joint: ", views(Joint(m)))
spec(f) = [mi.specTypes for mi in Base.specializations(only(filter(mm -> TW._tobj_lb(Base.unwrap_unionall(mm.sig).parameters[2]) !== nothing, collect(methods(f)))))]
println("overview's workers so far:")
foreach(s -> println("  ", s), filter(!isnothing, spec(overview)))
println("\nthe bundle trait: overview2(t::Table) = ", overview2(Joint(m)))

# rule 4: mutation through a view depends on whether the projection shares the user's data
struct Live; cols::Vector{Vector{Float64}}; end
@implement (ColTable, ColStore) Live project(t) = t.cols                   # shares
x = Live([[1.0, 3.0]])
normalize!(x, 1)
println("\nnormalize! through a sharing projection changes the user's data: ", x.cols[1])
struct Frozen; cols::Vector{Vector{Float64}}; end
e = try
    @eval @implement ColStore Frozen copies project(t) = deepcopy(t.cols)
    nothing
catch err
    err isa LoadError ? err.error : err
end
println("a copying projection for ColStore: ", sprint(showerror, e))
@implement ColTable Frozen copies project(t) = deepcopy(t.cols)            # fine: ColTable does not mutate
println("a copying projection for ColTable is accepted: colmean = ", colmean(Frozen([[2.0, 4.0]]), 1))
