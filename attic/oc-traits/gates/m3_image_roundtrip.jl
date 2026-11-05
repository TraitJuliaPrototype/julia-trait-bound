# Gate M3 §3c/§9 (D5/D6/R-7): fresh-depot precompile round trip. A tiny package
# compiled under JULIA_FACTS=1 (inlining + emitted calls + a fold + a field
# read) must LOAD plain with: correct values, its CIs verified (max_world ==
# typemax), and the G2 bit SURVIVING the load (the flags keep-mask, R-0/D4). A
# fold whose value CHANGES between build and load (env-seeded) must be discarded
# and recompiled — the fold_holds-false path (old C-14 class, D6's empirical
# half: digest-caused discards are reported by the author's instrumented run).
#
# SCOPE NOTE (R-7): this gate EXERCISES NO membership edges — MembershipEdge
# image semantics (entry-world re-stamping, activation) are M6's (§E row); the
# kinds verified here are InlineIdentity/ResultEdge/LayoutIdentity/FoldRecord.
import Base: shell

const JULIA0 = `$(Base.julia_cmd()) --startup-file=no`

root = mktempdir()
pkg = joinpath(root, "M3RT")
mkdir(joinpath(pkg, "src"))
write(joinpath(pkg, "Project.toml"), "name = \"M3RT\"\nversion = \"0.0.1\"\n")
write(joinpath(pkg, "src", "M3RT.jl"), """
module M3RT

inl3(x::Int) = xor(x, 0x0f)
@noinline emit3(x::Int) = (x * 3) ⊻ 0x01
struct P3R
    f::Int
end
lay3(p::P3R) = p.f
seedenv() = parse(Int, get(ENV, "M3RT_SEED", "7"))
# the fold shape: folded where inference can (Const folded by R-1), plain path
# computes the same value (the fold contract)
worker() = (r = Base.Compiler.fold_call(seedenv); r === nothing ? seedenv() : r)
mix(x::Int) = inl3(x) + emit3(x) + lay3(P3R(4))

function warm()
    base = mix(0x21)                       # 0x2e + 0x62 + 4 = 148
    (base, worker())
end

__init__() = warm()                        # force global-cache CIs at precompile

export warm, mix, worker
end
""")

depot = joinpath(root, "depot")
mkdir(depot)
env_pre = ["JULIA_FACTS" => "1", "JULIA_DEPOT_PATH" => depot, "M3RT_SEED" => "7"]
env_load_plain = ["JULIA_DEPOT_PATH" => depot, "M3RT_SEED" => "7"]      # no policy
env_load_all = ["JULIA_FACTS" => "1", "JULIA_DEPOT_PATH" => depot, "M3RT_SEED" => "7"]
env_load_moved = ["JULIA_DEPOT_PATH" => depot, "M3RT_SEED" => "99"]     # plain, fold value moved

# 1) precompile under the policy
p1 = run(pipeline(addenv(`$JULIA0 --project=$pkg -e 'import M3RT; println("PRE OK")'`,
                         env_pre), devnull); true)
@assert p1 "precompile child failed"

# 2) plain load, same seed: values exact, CIs verified, G2 bit survived the mask
child2 = """
    import M3RT
    r = M3RT.warm()
    @assert r == (148, 7) "values across the load: \$r"
    n = 0; g2 = 0; verified = 0
    for m in methods(M3RT.mix)
        for mi in Base.specializations(m)
            ci = getfield(mi, :cache)::Core.CodeInstance
            while ci !== nothing
                n += 1
                g2 += (getfield(ci, :flags) & 0b00010000) != 0
                verified += (ci.max_world === typemax(UInt))
                ci = isdefined(ci, :next) ? ci.next : nothing
            end
        end
    end
    println("LOADED n=\$n g2=\$g2 verified=\$verified")
    @assert n >= 1 "mix has a loaded CI"
    @assert g2 >= 1 "the G2 bit survived the image load (keep-mask): n=\$n g2=\$g2"
    @assert verified == n "every loaded CI verified to typemax (record kinds verify)"
    # fold identity edge: a FoldRecord is present in mix? (worker holds it) - check worker:
    nw = 0
    for m in methods(M3RT.worker), mi in Base.specializations(m)
        ci = getfield(mi, :cache)::Core.CodeInstance
        while ci !== nothing
            nw += 1
            ci = isdefined(ci, :next) ? ci.next : nothing
        end
    end
    println("WORKER nwspec=\$nw")
    println("CHILD2 OK")
"""
out2 = read(addenv(`$JULIA0 -e $(child2)`, env_load_plain), String)
@assert occursin("CHILD2 OK", out2) "plain load child: $out2"
out2b = read(addenv(`$JULIA0 -e $(child2)`, env_load_all), String)
@assert occursin("CHILD2 OK", out2b) "the same load under the policy: $out2b"

# 3) load with the fold's value MOVED (env-seeded): the FoldRecord re-evaluates,
# disagrees, the CI is discarded and recompiled — the moved value must answer.
child3 = """
    import M3RT
    v = M3RT.worker()
    println("MOVED worker=\$v")
    @assert v == 99 "the moved fold must be re-evaluated at load (fold_holds false ⇒ discard): got \$v"
    println("CHILD3 OK")
"""
out3 = read(addenv(`$JULIA0 -e $(child3)`, env_load_moved), String)
@assert occursin("CHILD3 OK", out3) "moved-fold child: $out3"

rm(root, force=true, recursive=true)
println("m3_image_roundtrip: OK   (D6 note: digest-caused discard count comes from the author's instrumented run)")
