module Helper
inner(x::AbstractFloat) = x
for k in 1:100
    f = Symbol("f", k)
    @eval function $f(v::AbstractVector)
        a = v[1] * $k + v[2]
        b = a * 0.5 + $k * v[end]
        c = muladd(a, b, Float64($k))
        d = ifelse(a > b, a - c, b + c)
        a + b + c + d + sqrt(abs(inner(b)) + $k)
    end
end
const FS = Any[getfield(Helper, Symbol("f", k)) for k in 1:100]
end
