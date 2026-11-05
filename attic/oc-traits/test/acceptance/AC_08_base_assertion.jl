# AC-8 (old G1.19): a BASE method's :foldable assertion over a run-time site
# does not fold a dispatch no edge records, when the method is reached from
# marked code. The Base-side definition mirrors the old suite's exactly: the
# body reads a Main binding through the inference barrier. Under a plain
# setting, the (plain) Base CI pins the dispatch through its recorded edges and
# the chain follows the redefinition; under `all` the Base frame is itself a
# facts frame: the site is a run-time site, the value moves dynamically.
include("ac_util.jl")

g8(x) = 1
Core.eval(Base, :(Base.@assume_effects :foldable bfold8(x::Int) = Main.g8(Base.inferencebarrier(x))))

k8() = Base.bfold8(1)
k8p() = Base.bfold8(1)
mark!(k8)

f190 = (k8p(), k8())
g8(x) = 2
f191 = (k8p(), k8())
@assert f190 == (1, 1) "before: $f190"
@assert f191 == (2, 2) "G1.19: the Base assertion does not freeze the dispatch: $f191"

ac_finish(@__FILE__)
