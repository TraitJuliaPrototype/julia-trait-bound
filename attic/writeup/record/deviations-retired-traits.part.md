| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 to T-95 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/traits.md` | — | — |
| T-97 | — | *Retired* (2026-11-14): the warning at an extension's method, at its definition and at its image's load ([§12.3](#123-strict-mode)); stack gate `strict_extension_method` | — | — |
| T-98 | — | *Retired* (2026-11-10): under strict mode an ambiguity at an image's membership activated at load is reported after the load, at error level, in TraitWorld 0aff625 with `unified` 9f8d7d7c48 ([§12.3](#123-strict-mode), [compiler §9](compiler.md#9-images-and-the-machine-code-cache)); gate `stack/strict_activation.jl` (E-349) | — | — |
| T-102 | — | *Retired* (2026-11-14): `like` and `withfields` call the constructor by position, with nothing looked up when they run ([lowering §8](lowering.md#8-like-and-withfields)); `test/core.jl`, stack gate `like_precompiled` | — | — |
| T-103 | — | *Retired* (2026-11-08): `HasProperty` in TraitWorld `unified` a658203 with `unified` 350c5b1c59 ([§10.1](#101-basetraits), [§3.2](#32-parameters)); tests `basetraits.jl`, gate `n10_inputs` | — | — |
| T-106 | — | *Retired* (2026-11-09): `IO`'s contract is Base's, on a closed type ([§9b](#9b-streams-io)) | — | — |
| T-107 | — | *Retired* (2026-11-14): the report's holes are the build's own check's ([§16](#16-compiling-ahead-closed-programs)); what is left is in T-109 | — | — |
| T-110 | — | *Retired* (2026-11-12): [§14](#14-concreteness-and-fully-typed-mode) holds the rule, built. | | |
| T-111 | — | *Retired* (2026-11-14): `detect_kept_storage` reports such stores ([§7.8](#78-keeping-an-argument-with-its-attribute)); test `kept.jl`. TraitDifferentialEquations' six sites are the port's (W-104) | — | — |
| T-113 | — | *Retired* (2026-11-15): [§4.6](#46-erasing-by-default) and [§7.8](#78-erasing-by-default-the-forwarder) state what the library records; what stands in for Julia's forwarders is T-125 | — | — |
| T-114 | — | *Retired* (2026-11-15): [§7.3](#73-bounded-methods) and [§11.2](#112-definition-checking) state what the library reads; how it infers that instance: [compiler C-115](compiler.md#deviations) | — | — |
| T-120 | — | *Retired* (2026-11-15): an operation without a default is an entry of the contract and no method at the trait, in TraitWorld `unified` c838f76 with julia `next` 5448a8b7bf ([§4.1](#41-operations), [§11.4](#114-hints)); E-498 | — | — |
| T-121 | — | *Retired* (2026-11-15): a method of another package's owner-only function is a pirate's, and `@owner_only`, in TraitWorld `s3` 4210852, 4f34916 ([§12.2](#122-pirates)); `test/owner_only.jl`, E-458 | — | — |
| T-123 | — | *Retired* (2026-11-15): the report by default, in TraitWorld `s3` 2770c10 ([§12.2](#122-pirates)); `test/report.jl`, E-457 | — | — |
| T-124 | — | *Retired* (2026-11-15): `delete_membership` in TraitWorld `s3` 9e0e3f4 with `next-s3` 213c759370 ([§5.13](#513-taking-a-membership-back)); `test/delete.jl`, E-459; Revise's part is lowering L-64 | — | — |
