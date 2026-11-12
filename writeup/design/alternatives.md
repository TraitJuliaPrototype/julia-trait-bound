
- **A `Kept{X}` assigned into storage typed by the trait stores its object** (a method `convert(::Type{T}, ::Kept{<:T})`). Not taken: the method invalidates 6,863 log entries of plain code at the library's load, against 65 without it (`experiments/unification/w149/`). `unwrap(k)` is assigned there.
