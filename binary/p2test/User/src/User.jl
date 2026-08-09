module User
using Helper
using PrecompileTools: @compile_workload
const F = Base.RefValue{Any}(hfun)
run_dyn(v) = F[](v)::Float64        # runtime dispatch into the foreign method
@compile_workload begin
    run_dyn([1.0, 2.0, 3.0])        # creates a FRESH specialization of Helper.hfun(Vector{Float64})
end
end
