using Columns, UserTypes
m, r = Measurements([[1.0, 2.0], [3.0, 5.0]]), Ramp([1.0, 2.0], 2)
@show colmean(m, 1) colmean(r, 1) colmean(Reversed([[1.0, 2.0], [3.0, 5.0]]), 1) meandiff(m, r, 1)
