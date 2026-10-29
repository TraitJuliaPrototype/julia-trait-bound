# W-91: `Callable` entries a package image can keep

Status: **adopted** (2026-10-29, mine; W-91). Not normative. Measured in E-241 (the registry has the numbers).

## 1. The cause

- A function argument enters trait code through `enter_callable` ([lowering §12](../reference/lowering.md#12-callable-and-dynamiccallable)). It is compiled once per signature: its argument types `A` and result type `S` were passed as two type values, `enter_callable(::Type{A}, ::Type{S}, attr, f, Val(known))`.
- Julia gives a type value no hash when its parameters hold a `Union` directly: `Tuple{Union{Missing, Float64}}`, `Union{Missing, Int}`. Such a type has several equal forms (`Tuple{Union{A, B}} == Union{Tuple{A}, Tuple{B}}`), so no hash agrees with equality. A signature that holds such a type value has no hash either.
- The patched Julia's package images keep no external code at a signature without a hash ([compiler §2.9](../reference/compiler.md#29-what-package-images-keep)): its insertion at load scans the method's list of such specializations (W-59).
- Code reached by a call that an image's own code makes statically is kept anyway, through that caller's edges. Code reached by a dynamic call, which a workload records, is dropped. An entry compiled for untyped arguments reads `A` from an argument's key and calls `enter_callable` dynamically: the forks' `byrow` over a column with missing values. So every session compiles it again: `enter_callable` 131 ms of the forks' session (E-233, E-234).

## 2. The options

- **A. The entry keyed by the bound.** `enter_callable(::Type{Callable{A, S}}, attr, f, Val(known))`. `Callable{A, S}` is a type with invariant parameters, which Julia hashes by its parameters: `Type{Callable{Tuple{Union{Missing, Float64}}, Bool}}` has a hash. The helpers the entry calls take the bound too: `_check_at_signature`, `_wrap_callable`, `_erased_at`, `_fptr`, `enter_kw_callable`; `enter_callables` gets its signatures as bounds. The lowering passes `Callable{A, S}` where it passed `A, S`; at a constant signature it folds to a constant.
- **B. Images keep specializations without a hash.** A change in julia-1.13: undo or narrow W-59's rule. Its cost at load is real (3 s of a load under the facts image, W-59). A narrower rule needs a threshold, or a hash that agrees with type equality, which Julia does not have for these types.

## 3. The choice

A. The type value without a hash is made by TraitWorld's own calling convention, and the bound is the natural key of the entry: the worker is compiled per `CObj{A, S}`, and the caches key on the signature. It adds no machinery, and keeps the Julia rule that protects the load. B would change Julia for a cost TraitWorld introduces.

## 4. Same pattern, not covered

From the census of the forks' session (E-241, `experiments/w91-callable-entries/`):
- **The open result type,** `_callable_result(f, ::Type{A})` (`Callable{A, S} where S`, traits §5.8): the run-time inference of `S`, 6–7 ms per signature in the forks' session. Its key is the bound with `S` open, a `UnionAll`, which has no hash either; the bound cannot key it. Proposal for the user: take `A` as data, as `Core.Compiler.return_type` does (`@nospecialize`), since the body is a run-time call whatever it is compiled for. Not done: `@nospecialize` is an escape hatch by the user's rule.
- **The pointer's thunk,** `_fptr(Callable{A, S}, F)`, is per function type `F`. For a function made in the session no image can keep it.
- **Trait types with a `Union` in their key** (`Column{Union{Missing, Float64}}`, whose `Self` is open): `_family`, `_kept_at`, `_kept_narrowed`, `_dyn_tobj`, `_narrow`, `_erased_key_of` and the like, mostly of the facts owner, and `_op_result`, `_result_decl`, `_seam1` at `Type{Union{…}}`. In the forks' session they are compiled inside other roots, at the imports or at the first sight of a column type; none is a compile root of its own after the load. The trait type is the API; keying them otherwise is not a local change. Recorded here; a candidate for W-83's unification or a performance exploration.
- **Plain code:** DataFrames' `batch_compacttype` closures over `Type{Union{Missing, Int64}}` (about 45 ms, E-234) and 66 of Base's specializations in the forks' session. Only option B would keep them.
