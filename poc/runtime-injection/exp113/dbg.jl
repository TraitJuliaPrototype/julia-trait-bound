const R = Base.Compiler.ReinferUtils
Base.include(R, ENV["PATCHED"])
const C = Ref(0); const V = Ref(0)
@eval R function _tw_protected(codeinst::CodeInstance)
    $(C)[] += 1
    _tw_filter_on() || return false
    def = get_ci_mi(codeinst).def
    return def isa Method && _tw_in_trait_world(def.module)
end
@eval R function _tw_outside_owned(m::Method)
    $(V)[] += 1
    r = _tw_root(m.module)
    (_tw_in_trait_world(m.module) || _tw_is_julia(r)) && return false
    sig = Base.unwrap_unionall(m.sig)
    sig isa DataType || return false
    for p in sig.parameters
        p isa Core.TypeofVararg && continue
        _tw_owned_by(p, r, 0) && return true
    end
    return false
end
Base.Compiler.activate_codegen!()
Base._require_world_age[] = Base.get_world_counter()

using Out; using TW
println("tw_protected calls ", C[], " outside_owned calls ", V[], " flag ", R._tw_load_filter[], " skipped ", R._tw_skipped[])
