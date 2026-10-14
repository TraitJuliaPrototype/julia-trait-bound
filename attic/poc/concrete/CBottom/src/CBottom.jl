"Bottom layer: a configuration whose field is declared abstract."
module CBottom
export Config, TypedConfig
struct Config; scale::Real; end            # the cause: an abstract field
struct TypedConfig; scale::Float64; end    # the fix
scale(c) = c.scale
end
