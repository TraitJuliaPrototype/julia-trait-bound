module Legit                    # extends Stats and Base for its own type
using Stats
struct LegitNum <: Real; x::Float64; end
Stats.weight(x::LegitNum) = 0.5
Base.show(io::IO, x::LegitNum) = print(io, "LegitNum(", x.x, ")")
end
