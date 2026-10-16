# Session 22: the cost of a lens (a field reference) against a held value. Run: julia +1.12.2 --startup-file=no -O2 poc/lens/lens_bench.jl
# What does a field reference cost? A lens holds the user's object untyped and the field's index;
# compiled code knows only the field's type R, never the user's type.
mutable struct User1; a::Int; data::Vector{Float64}; end
mutable struct User2; data::Vector{Float64}; tag::String; z::Float64; end

struct Held{R}; r::R; end                                   # a snapshot: the value itself
struct Lens{R}; obj::Any; i::Int; end                       # a field reference
@inline rep(h::Held) = h.r
@inline rep(l::Lens{R}) where {R} = getfield(l.obj, l.i)::R
@inline setrep!(l::Lens{R}, x::R) where {R} = (setfield!(l.obj, l.i, x); nothing)
# a field reference by pointer, as a runtime could do it: one load at a byte offset
struct PLens{R}; obj::Any; off::Int; end
@inline function rep(l::PLens{R}) where {R}
    GC.@preserve l begin
        p = Ptr{Ptr{Cvoid}}(pointer_from_objref(l.obj) + l.off)
        return unsafe_pointer_to_objref(unsafe_load(p))::R
    end
end

function readloop(x, n)                 # one representation read per operation call, as a worker does
    s = 0.0
    for k in 1:n
        s += @inbounds rep(x)[1 + (k & 7)]
    end
    s
end
function writeloop(l, vs, n)
    for k in 1:n
        setrep!(l, @inbounds vs[1 + (k & 1)])
    end
end
direct_read(u, n) = (s = 0.0; for k in 1:n; s += @inbounds u.data[1 + (k & 7)]; end; s)
direct_write(u, vs, n) = (for k in 1:n; u.data = @inbounds vs[1 + (k & 1)]; end)

v = collect(1.0:8.0); vs = [collect(1.0:8.0), collect(2.0:9.0)]
u1 = User1(1, v); u2 = User2(v, "t", 0.0)
n = 10^8
h = Held(v); l1 = Lens{Vector{Float64}}(u1, 2); l2 = Lens{Vector{Float64}}(u2, 1)
p1 = PLens{Vector{Float64}}(u1, fieldoffset(User1, 2)); p2 = PLens{Vector{Float64}}(u2, fieldoffset(User2, 1))
# the worker is compiled once for Lens{Vector{Float64}}, whatever the user's type
readloop(h, 10); readloop(l1, 10); readloop(p1, 10); direct_read(u1, 10); writeloop(l1, vs, 10); direct_write(u1, vs, 10)
for (name, f) in (("direct field (compiled per user type)", () -> direct_read(u1, n)),
                  ("held value (snapshot)", () -> readloop(h, n)),
                  ("lens, builtin getfield on Any, User1", () -> readloop(l1, n)),
                  ("lens, builtin getfield on Any, User2", () -> readloop(l2, n)),
                  ("lens, pointer load at offset, User1", () -> readloop(p1, n)),
                  ("lens, pointer load at offset, User2", () -> readloop(p2, n)))
    f(); t = minimum(@elapsed(f()) for _ in 1:3)
    println(rpad(name, 42), round(1e9t / n; digits = 2), " ns per read")
end
for (name, f) in (("direct field write", () -> direct_write(u1, vs, n)),
                  ("lens write, builtin setfield! on Any", () -> writeloop(l1, vs, n)))
    f(); t = minimum(@elapsed(f()) for _ in 1:3)
    println(rpad(name, 42), round(1e9t / n; digits = 2), " ns per write")
end
# liveness: a rebinding from above is seen through the lens, not through the snapshot
u1.data = [10.0, 20.0]
println("after the user rebinds u1.data: lens sees ", rep(l1)[1], ", snapshot sees ", rep(h)[1])
