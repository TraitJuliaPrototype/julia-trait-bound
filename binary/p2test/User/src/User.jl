module User
using Helper
using PrecompileTools: @compile_workload
const F = Base.RefValue{Any}(first(Helper.FS))
run_dyn(v) = F[](v)::Float64
function run_all(v)
    acc = 0.0
    for f in Helper.FS
        F[] = f
        acc += run_dyn(v)
    end
    acc
end
@compile_workload begin
    run_all([1.0, 2.0, 3.0])   # creates 100 fresh foreign specializations
end
end
