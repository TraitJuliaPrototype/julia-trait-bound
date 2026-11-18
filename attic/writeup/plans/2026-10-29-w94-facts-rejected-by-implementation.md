# W-94: facts code "rejected" at load by another package's implementation

**Status: adopted (mine), 2026-10-29.** Open issue 126; W-94; experiment E-243 (`experiments/w94/`). Not normative: the rules are in the references.

## 1. The question

E-238 counted 30 `conformance(::As{Column}, ::Vector{…})` CodeInstances of Tables' methods, and 5 of CSV's, as code of the facts owner rejected at load when CSV's `@implement CSVColumn A where {A <: Vector}` loads ([the W-92 note](2026-10-29-w92-forks-invalidation.md) §4, item 4). Each holds a member fold, `Compiler.fold_call(_member_fold, reg, X, typeof(u))` ([lowering §4.6](../reference/lowering.md#46-families)). [Facts §2.2](../reference/facts.md#g2) lists no exception for it. The user's decision: investigate, then either state an exception in §2.2 or record a deviation and fix it.

## 2. The mechanism

**The code is not rejected.** Every one of the 37 fold-holding CodeInstances that E-238's log names is valid after the loads, and gives the stored value again (E-243).

- Image validation (`julia-1.13/Compiler/src/reinfer.jl`, `verify_method`) computes, for each edge, a world range `min_valid2:max_valid2`. A call edge that holds gives `typemax(UInt)`.
- A fold record that holds is given `maxworld`, the validation world (`reinfer.jl:246`). The code's validity is the same either way: the code's range starts capped at the validation world.
- Validation's log writes an entry `insert_backedges_callee` for every edge whose bound is not `typemax(UInt)` (`reinfer.jl:286`). So it names every fold, holding or not. Julia's own code does the same for a binding's edge without partitions (`reinfer.jl:247`–`259`).
- E-238's `rejections.jl` and `census.jl` counted every such entry as a rejection: 70 of the 1,010 CodeInstances (37 by a fold, 33 by a binding).
- A CodeInstance that validation makes invalid gets a `verify_methods` entry (`reinfer.jl:346`) and keeps a `max_world` below the latest world. None of the 70 has either.

**What the fold depends on, and why CSV changes none of it.** At load, `_member_fold(AtLoad(), reg, Column, U)` (`TraitWorld/src/implement.jl:964`) returns, in order:
1. the builder in the family's registry, saved with the declaring package's image;
2. the builder of an image's record of the member (`_member_record`, W-84), if dispatch selects the methods the record was made with at the member's signatures (`_member_sigs`, `implement.jl:1030`): the conformance of each trait in `Column`'s closure at `U`, and `Column`'s operations at `U`;
3. otherwise the member is checked and its builder made again.

CSV's subtrait and its implementation define `conformance(::As{CSVColumn}, ::A) where {A <: Vector}`, `CSVColumn`'s operations at `Vector`, and methods of `Column`'s operations on `CSVColumn`'s kept forms (`TraitWorld/src/trait.jl:540`). None applies at `conformance(::As{Column}, ::U)` or at `Column`'s operations at a `Vector`. Every fold in E-238's loads took path 1 or 2 (`logs/diag-atload-forks.log`).

The minimal case (`experiments/w94/repro.jl`: a family over `AbstractVector`, then a package implementing a subtrait for every `Vector`) shows the same. The first package's fold is logged at its own load, before the second package exists. Its code stays valid, and the first call compiles nothing for it.

## 3. The verdict

Neither a fact change nor an over-broad dependency.
- **G2 holds here.** By facts §2.2, a new implementation of a trait wins at no existing fact. A fold is evaluated again at load, and its answer rests only on the member's own traits' methods (path 2) or on the declaring image (path 1). A subtrait's implementation changes neither. No exception belongs in §2.2.
- **The defect is in the log, and in the counting.** A fold that holds is reported as a failed edge. That is a deviation of the patched Julia from what [compiler §5.4](../reference/compiler.md#54-planned-hooks-for-strict-modes-intended-design) says the log holds: C-17.
- TraitWorld's strict mode reads the same log, and already skips fold and binding entries (`TraitWorld/src/strict.jl:432`). Nothing it reports changes.

## 4. What changes

- **julia-1.13, branch `w94` (00dcc9994c), not built:** a fold that holds gives `typemax(UInt)`, as a call edge that holds. The computed validity is unchanged; the log names only folds that fail. Checked without a build (`experiments/w94/patch_verify.jl`: the branch's `verify_method` evaluated into the running Julia): the minimal case logs no fold, and E-238's loads log the same 33 bindings and 53 failed call edges and no fold.
- **Compiler reference §5.4:** the log's entries stated precisely; a binding's entry is Julia's own and is not a rejection; readers decide rejection by `verify_methods` or `max_world`. **C-17** for the fold's entry, until the branch is built and merged.
- **Facts reference §2.2, "What invalidates nothing":** an implementation of another trait for a family's member, a subtrait's included; why a fold kept in an image does not depend on it.
- **E-238's write-up:** a dated correction. Image code rejected at load: 940 CodeInstances, not 1,010; Tables 5, CSV 0, Base's external code about 195. The roots of the steps and their times are unaffected; so are the W-92 note's other candidates.

## 5. To do when the branch is built

- Merge `w94` into `trait-world-1.13` with the next build; retire C-17 then.
- A regression check would read the log after a load and require no fold entry for code that stays valid (the minimal case, `repro.jl`, does so by hand).
