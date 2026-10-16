module Out
struct T end
Base.numerator(::T) = 1                # owned: Out owns T. Matches TW's numerator(::Any) edge.
end
