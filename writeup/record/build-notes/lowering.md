# Build notes: lowering

This page is in the agents' tier ([the record's index](../INDEX.md)).
It holds what the pass of 2026-11-18 over [the lowering reference](../../reference/lowering.md) took out of it: where each rule is in the code, the commits that built it, its gates, who decided it, its experiments.
The reference is the source of truth for the rule; this page is its build log, by section, in the reference's order.

### The top of the page

- **Taken from the page's text:** **Adopted** (the user, 2026-11-06; W-105; [the folder's README](../../reference/README.md)). This page defines what the trait library's macros expand to on Julia's interfaces ([`compiler.md`](../../reference/compiler.md)), within the facts mode's contract ([`facts.md`](../../reference/facts.md)). It decides nothing the other three references decide; where it seems to, they win.

### §1 Summary

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 for `@trait`, `@implement`, a pattern's members, a method at a trait and `Dynamic{X}` (L-51); `@trait_module` in TraitWorld `unified` bb78d02 (W-111; §6); the wrapper in 5e2ef71 (W-151; §7), with [traits T-125, T-126](../../reference/traits.md#19-deviations).

### §2 `@trait`

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2, with L-54. A further argument typed only where it binds an input: TraitWorld 4be0097, mine (2026-11-07), found by BaseTraits' `Keyed` (an ambiguity with Base's `haskey` for every dictionary). The operations as entries, a method at the trait only for a default, and `Dynamic{X}`'s forwarding methods: Implemented (D-4, 2026-11-15; TraitWorld `unified` c838f76 with julia `next` 5448a8b7bf; W-161, E-498); a further argument typed where its declared type names no variable: mine (2026-11-15, found by the library's test of ambiguities, Base's `show(io::IO, x)`). The wrapper's membership: TraitWorld 5e2ef71 (W-151); its forwarding methods: TraitWorld c838f76 (W-161); the erasing record read where a method is defined and `:no_forwarder`: TraitWorld 21ae901 (W-160); `:no_forwarder`: mine (2026-11-15).

### §3 `@implement`

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 for steps 2 to 6 (a `Union`-bounded variable in dd72b10), the use before the declaration raised in 0aff625 (E-350), in compiled code with `unified` fcdfd0da36 (E-352); ownership (step 1) and compiling ahead (step 8) in TraitWorld 7adcc94 (W-114), the override records (step 7) in TraitWorld 701aaab, the forwarding's and the checked results in 5b3c427, made again from an image's memberships in 6871ea9 (E-344); forwarding's methods (step 6) in TraitWorld (W-128), mine (open issue 158 (a), 2026-11-08). The check's instances as the records (steps 3, 7): Planned (D-3), with [traits T-129](../../reference/traits.md#19-deviations). `struct S <: X` decided (the user, 2026-11-06, Q8 (c)). Taking a membership back: TraitWorld `s3` 9e0e3f4 (D-13, 2026-11-15; E-459). The extension for Revise: Planned, with L-64.

### §4 Members checked at their first use

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 with the runtime's hook at dispatch and in the compile queue ([compiler §10.4](../../reference/compiler.md#104-the-member-hook), C-30, C-31); a pattern an image brought, read from the runtime's entries, in TraitWorld `unified` bd9a721; an abstract member by its definition through its entry in e8554d9 (E-345); the answers in images: L-55. The pattern rule for equations is mine (2026-11-06; [the README](../../reference/README.md#the-choices-in-these-references)).

### §5 Methods at traits

- **The status line as it stood:** A method at a trait: Julia's, implemented. The forwarder: Implemented (D-1; `next` 8b1ec88a56 with TraitWorld `unified` 21ae901, W-160), with [traits T-125](../../reference/traits.md#19-deviations); `@nospecialize` at a trait argument still takes the attribute's path on the build ([compiler C-112](../../reference/compiler.md#deviations)), which a forwarder's box made in its own body does not need. The per-method options with what reads them: `@bounded` and `@unbounded` in TraitWorld `unified` 59134ef and bb78d02 (W-109, W-111; [traits §7.3](../../reference/traits.md#73-fully-bounded-methods)); the facts flag on `unified` beafa01b36 (W-100; [compiler §2.2](../../reference/compiler.md#22-the-method-flag)).

### §6 Scopes

- **The status line as it stood:** Implemented in TraitWorld `unified` bb78d02 (W-111); the options decided (the user, 2026-11-06, Q2 (a)); the three and no other: the plan's D-1 and D-14 (2026-11-15), with [traits T-127](../../reference/traits.md#19-deviations).

### §7 `Dynamic{X}` and `Compiled{T}`

- **The status line as it stood:** `Core.Dynamic` and its methods: Implemented on `unified` e692e57ab7 and TraitWorld `unified` bb78d02 (W-111). The wrapper, its methods, the box's constructors at a box and a wrapper, and `convert`: TraitWorld 5e2ef71, 5a9d19d (W-151), with [traits T-126](../../reference/traits.md#19-deviations) and [compiler C-113](../../reference/compiler.md#deviations) (the wrapper the library's type; `compiled_for` exported as Julia's cast).

### §8 `like` and `withfields`

- **The status line as it stood:** Implemented in TraitWorld `unified` 78da5cb (`test/core.jl`; stack gate `like_precompiled`): the rebuilding as a method made at the declaration, and the hint, are mine (2026-11-14).

### §9 `Callable`

- **The status line as it stood:** Implemented in TraitWorld `unified` 5d52f0d (W-113): `Callable` is Julia's; `Dynamic{Z}`'s membership and its call, checked at both ends; the wrapper's family in 5e2ef71 (W-151). The hint for a function with no method at `A`: TraitWorld e572379 (W-114); the hint at a result that fails its check: L-58. The box's test at `A`, the wrapper's entry ([compiler §6.3](../../reference/compiler.md#63-the-forwarders)) and `@implement Callable T`: TraitWorld `unified` c14d2e4 (D-2, W-161; E-500), with [compiler C-146](../../reference/compiler.md#deviations).

### §10 BaseTraits

- **The status line as it stood:** Implemented in TraitWorld `unified` 4be0097 (W-114); `HasProperty` in a658203.

### §11 Checks, errors, and what images keep

- **The status line as it stood:** Implemented on `unified` 28c401eb0c and TraitWorld `unified` 701aaab: contracts and memberships in images; the definition hook (an override), the module-end hook (a missing `@implement`), the image hook (overrides left inactive). The records of §3, step 7, kept at a method's definition and an image's activation: TraitWorld 5b3c427 (E-342); made again from an image's memberships: TraitWorld 6871ea9 with `unified` e42047dba2 (E-344). The pattern members' answers in images: L-55. `bounded` in TraitWorld bb78d02 (W-111), reading the instance at the box in 6f86b4e (W-151); pirates, strict mode and code compiled ahead in 7adcc94 (W-114); the hints e572379. The check's instances as the records, kept and validated with an image: Planned (the plan's D-3, 2026-11-15), with [traits T-129](../../reference/traits.md#19-deviations) and [compiler C-115](../../reference/compiler.md#deviations).

### §12 Compiling ahead

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 and e81cd49a67 (W-114); gate `experiments/unification/stack/ahead_two_packages.jl`: in a fresh session that loads the member's package, the methods at the set have their code for `S` from its image, and with `JULIA_TW_AHEAD=0` none. The request as Julia's `precompile`, and nothing per member for a method that erases: Planned (D-1, 2026-11-15), with L-66.

### §13 Strict mode

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114): the walk before the definition and the log after it, the image hook, the report after a load from validation's log, the deletion hook; bindings redefined from other modules: [traits T-96](../../reference/traits.md#19-deviations). The refusal at a membership: `unified` 0bb8f38830 with TraitWorld 960b99e (E-343). A pirate's membership: TraitWorld a2ca7be with `unified` 7fee959383, with [traits T-112](../../reference/traits.md#19-deviations).

### §14 Fully typed mode, concrete parts, closed programs

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114); tests `fullytyped.jl`, `verify.jl`. The calls as the build's check's, the hook, the build's Base: TraitWorld `unified` 78a78af with `unified` 381cc8b953 (W-142; E-369), with traits T-109; mine (2026-11-12, 2026-11-14).

### §15 Deviations

- **The sentence above the table as it stood:** The library on the unified build: TraitWorld `unified` (its head: [state.md §6.1](../../state.md#today)).
- **The retired rows** moved to the ledger's part `attic/writeup/record/deviations-retired-lowering.part.md`: L-1 to L-50, L-51, L-52, L-53, L-54, L-55, L-56, L-57, L-59, L-63, L-65, L-68.
