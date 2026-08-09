module Helper
export hfun
# deliberately tiny: inlineable, so the standalone-native gate refuses it
hfun(v::AbstractVector) = v[1] * 2.0 + v[2]
end
