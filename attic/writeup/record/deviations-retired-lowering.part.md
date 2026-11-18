| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-1 to L-50 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/lowering.md` | — | — |
| L-51 | — | *Retired* (2026-11-07): `Dynamic{X}` is `Core.Dynamic` on `unified` e692e57ab7 ([§7](#7-dynamicx-keep-casts)); gate `n6_attribute` | — | — |
| L-52 | — | *Retired* (2026-11-10): the use raises at dispatch and in compiled code ([§3](#3-implement); TraitWorld 0aff625, 048c44e with `unified` fcdfd0da36; `test/declared.jl`, E-350, E-352). What remains is the hook's: [compiler C-31](compiler.md#deviations) | — | — |
| L-53 | — | *Retired* (2026-11-07): built in TraitWorld `unified` dd72b10 ([§3](#3-implement)); test `Union-bounded family` | — | — |
| L-54 | — | *Retired* (2026-11-15): [§2](#2-trait) states the library's forwarding call; `Core.trait_receiver` is an optional extension ([extensions §1.4](extensions.md#14-the-calling-convention)) | — | — |
| L-55 | — | *Retired*: what an image keeps is [§11](#11-checks-errors-and-what-images-keep); gate `experiments/unification/l55/kept_checks.jl` | — | — |
| L-56 | — | *Retired* (2026-11-15): there are no casts ([§7](#7-dynamicx-and-compiledt)); what Julia still carries of them: [compiler C-112](compiler.md#deviations) | — | — |
| L-57 | — | *Retired* (2026-11-14): the error names the constructor to define ([§8](#8-like-and-withfields)); `test/core.jl` | — | — |
| L-59 | — | *Retired* (2026-11-15): [§2](#2-trait) declares the wrapper's family, as the library does; the erasing bit is L-65 | — | — |
| L-63 | — | *Retired* (2026-11-15): `@trait` writes the operations as entries (`jl_set_contract_operations`), a method at the trait only for a default, and the kept forms' forwarding methods, in TraitWorld `unified` c838f76 ([§2](#2-trait)); E-498 | — | — |
| L-65 | — | *Retired* (2026-11-15): §2's mark `Expr(:meta, :no_forwarder)` and the contract's record of the default, read where a method is defined by the library's expansion hook, are built (TraitWorld `unified` 21ae901, julia `next` 8b1ec88a56; W-160); `@default_compiled` is [traits T-127](traits.md#19-deviations)'s | — | — |
| L-68 | — | *Retired* (2026-11-15): the box's constructor tests `hasmethod(f, A)`, and `@implement Callable T` declares a callable type ([§9](#9-callable)); built in TraitWorld `unified` c14d2e4 (W-161), the ports' guard pairs gone (E-500) | — | — |
