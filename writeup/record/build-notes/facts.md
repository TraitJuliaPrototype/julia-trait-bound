# Build notes: facts

This page is in the agents' tier ([the record's index](../INDEX.md)).
It holds what the pass of 2026-11-18 over [the facts reference](../../reference/facts.md) took out of it: where each rule is in the code, the commits that built it, its gates, who decided it, its experiments.
The reference is the source of truth for the rule; this page is its build log, by section, in the reference's order.

### The top of the page

- **Taken from the page's text:** **Adopted** (the user, 2026-11-06; W-105; [the folder's README](../../reference/README.md)). This page defines the facts mode: the contract between compiled code and the method table. It says what code compiled by facts may assume about other code, what it records, which code is compiled by facts, and what the two guarantees promise. It describes the mode as designed. The status line of each section says how far it is built.

### §1 Terms

- **Taken from the section's text:** the link's label "open issues §1.19" (the item is open issue 19, in §4 of the open issues)

### §2.1 G1: identical or error

- **The status line as it stood:** Implemented on `unified` cb7f55bd35 (W-100), with compiler C-45, C-47, C-51; a membership invalidates the code it changes ([compiler §5.5](../../reference/compiler.md#55-a-membership-invalidates-as-a-method-does), `unified` a19d937eaa). The acceptance suite (`experiments/unification/test/acceptance/`): 21 of 21 cases pass in the product setting and under the test bed (E-277; `AC_16` with W-114).

### §2.2 G2: stable caches

- **The status line as it stood:** Implemented on `unified` (W-100): the facts inference records only facts, bindings and edges to callees (compiler §1, §3.1); a membership invalidates as a method does: `unified` a19d937eaa (W-140). The deep class as the bit each CodeInstance records: `next` 7063158f42 (W-155; [compiler §3.2](../../reference/compiler.md#32-g2-as-a-predicate)): the nine unrelated loads end no instance that carries it (E-417); strict mode's walk by the class: F-25.

### §2.3 Two tiers

- **The status line as it stood:** Implemented: strict mode in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114; [traits §12.3](../../reference/traits.md#123-strict-mode)), with traits T-96, T-97.

### §3 Fact signatures

- **The status line as it stood:** Implemented on `unified` 28fe27b2f7 (W-100; [compiler §1.2](../../reference/compiler.md#12-fact-signatures)). With keys, an optional extension, two more forms: [extensions §1.3](../../reference/extensions.md#13-calls-from-code-compiled-per-key). Owner-only functions: `next-s3` e483299622 with TraitWorld `s3` 4210852, 4f34916 (the plan's D-9, 2026-11-15; E-458), but for a later `public` or `export`, which ends nothing ([compiler C-130](../../reference/compiler.md#deviations)). The default for trait modules, not for every module that declares `facts`: mine (2026-11-15; E-431, GT-23 (c)). Their declaration's form, and the reading of a later `public` as the owner's change: mine (2026-11-15). What is final as the one input from which a session's and a closed build's rules follow, and fully typed with the setting as its parameter: mine (2026-11-15; the plan's D-10).
- **Taken from the section's text:** (E-431)

### §4.3 Edges and invalidation

- **The status line as it stood:** Implemented on `unified` (W-100) for facts, binding edges, edges to callees as CodeInstance edges and positive memberships (compiler §3.1, with C-52); with no code slot on `next` 9b6dacf5c5 (W-155).

### §5 Run-time sites

- **The status line as it stood:** Implemented on `unified` 28fe27b2f7 (W-100; [compiler §1.3](../../reference/compiler.md#13-run-time-sites)).

### §6.1 Kinds of methods

- **The status line as it stood:** Implemented on `unified` beafa01b36, c44a447f2c (W-100; [compiler §2.1–§2.3](../../reference/compiler.md#2-the-policy-per-method)); no method of Base is a boundary (E-279).

### §6.2 The policy rule

- **The status line as it stood:** Implemented on `unified` 10c7e1c2cf, c44a447f2c (W-100; [compiler §2.3](../../reference/compiler.md#23-one-codeinstance-per-methodinstance-and-policy)), with compiler C-49.

### §6.3 Calls between policies

- **The status line as it stood:** Implemented on `unified` 10c7e1c2cf, c44a447f2c (W-100; [compiler §2.4](../../reference/compiler.md#24-calls-between-policies)), with compiler C-45, C-50.

### §6.4 The compiler's own code

- **The status line as it stood:** Implemented on `unified` 4ba5b7025f, 95fe10427c (W-100).

### §7.1 `return_type`

- **The status line as it stood:** Implemented on `unified` b87d863b9e (W-100; [compiler §1.4](../../reference/compiler.md#14-return_type)), with compiler C-47. Optional: revalidating cached answers after loads ([PE-5](../performance-explorations.md)).

### §7.2 Reflection

- **The status line as it stood:** Implemented on `unified` (W-100) for a method's callees, inferred under their own policy; the top frame under the default interpreter's, plain (F-24). The definition-time check reads the instance at the box ([compiler §6.7](../../reference/compiler.md#67-the-definition-time-check), C-115).

### §8 Asserted effects

- **The status line as it stood:** Implemented on `unified` 3363088725, 28fe27b2f7 (W-100): the `nortsite` bit carries a run-time site to every caller, and an assertion does not apply over it.

### §9 Operations on a value typed by its trait

- **The status line as it stood:** Implemented on `unified` e70675a606 and 50da8d8ee2 (W-109; [compiler §7.1–§7.3](../../reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)), asserted, never converted, on ef1233e79e (E-340), with compiler C-38, C-39. The declared result read from the contract, with no method at the set for an operation without a default: Implemented (D-4; julia `next` 5448a8b7bf with TraitWorld `unified` c838f76 (W-161, E-498)).

### §10 Memberships

- **The status line as it stood:** Implemented on `unified` a19d937eaa (W-140; [compiler §4.8](../../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§5.5](../../reference/compiler.md#55-a-membership-invalidates-as-a-method-does), [§5.6](../../reference/compiler.md#56-the-memberships-method-and-the-edges)), with compiler C-77, C-79, C-88. Gates `n7_guards`, `n18_closed_after_load`, `n25_image_before_set_method`, `n26_callable_late_method`. The rule: the user (2026-11-11); it replaces "a membership invalidates nothing" ([alternatives](../../design/alternatives.md)). A membership taken back: `next-s3` 213c759370 with TraitWorld `s3` 9e0e3f4 (the plan's D-13, 2026-11-15; E-459).

### §11.1 What a winning pirate does

- **The status line as it stood:** Implemented on `unified` (W-100): Julia's invalidation at the fact a pirate's method wins, and image validation at load (compiler §9). The report by default: TraitWorld `s3` 2770c10 with `next-s3` 5d2ec7ff85 (the plan's D-12, 2026-11-15; `test/report.jl`, E-457).

### §11.2 Strict mode

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114; [lowering §13](../../reference/lowering.md#13-strict-mode)): the walk before the definition, the check of validation's log after it, the image hook. A pirate's membership: TraitWorld a2ca7be with `unified` 7fee959383, with [traits T-112](../../reference/traits.md#19-deviations). The walk by the deep class: F-25.
- **Taken from the section's text:** Planned (the plan's D-3, 2026-11-15), with [traits T-129](../../reference/traits.md#19-deviations). (The part's status moved to the status line.)

### §11.3 Strict mode's errors at their sources

- **The status line as it stood:** Implemented with §11.2 (W-114), `verify_main` in TraitWorld, but for two rows: a binding redefined from another module is followed ([traits T-96](../../reference/traits.md#19-deviations)); an extension's winning method is followed without the warning (T-97). An ambiguity at a membership is refused at a declaration (`unified` 0bb8f38830, E-343) and reported after the load at an image's activation (`unified` 9f8d7d7c48, TraitWorld 0aff625, E-349).

### §12 Package images

- **The status line as it stood:** The memberships activated before validation: implemented on `unified` 28c401eb0c ([compiler §9](../../reference/compiler.md#9-images-and-the-machine-code-cache)). Images with the facts mode's code and its edges, positive memberships validated: `unified` (W-100). The keep rule by the deep class: `next` 7063158f42 (E-417). A folded negative's edge (W-129, W-140, W-141); the check records made again from an image's memberships (TraitWorld 6871ea9, E-344), the pattern answers: lowering L-55; the store paused.
- **Taken from the section's text:** (paused) (the part's status, Optional, is in the status line)

### §13.1 The product setting

- **The status line as it stood:** Implemented on `unified` (W-100).

### §13.2 The test bed `all`

- **The status line as it stood:** Implemented on `unified` 4ba5b7025f, c44a447f2c (W-100; [compiler §2.5](../../reference/compiler.md#25-the-test-bed)): a session's start-up compiles Base's start-up code by facts, 24–25 s ([PE-23](../performance-explorations.md)).

### §13.3 Trimmed binaries

- **The status line as it stood:** Implemented on `unified` cb7f55bd35 and bb2031f820 (W-100; [compiler §2.6](../../reference/compiler.md#26---trim)); trimmed binaries are built and run in E-361 ([evidence §4](../../design/evidence.md#4-builds-and-binaries)). `verify_main`: TraitWorld (W-114). Stated as the facts rule with everything final: mine (2026-11-15; D-10).

### §15 Status index

- **The table as it stood** (the pass rewrote its status column to follow the new status lines):

| Item | Status | Where |
|---|---|---|
| G1, identical or error | Implemented (`unified`, W-100); 21 of 21 acceptance cases in both settings (E-277) | §2.1 |
| G2, stable caches, for the deep class; exceptions named | Implemented (`unified`, W-100); a membership's invalidation (W-140); the deep class `next` 7063158f42 (W-155) | §2.2 |
| fact signatures | Implemented (`unified`, W-100); with keys, two more forms: an optional extension ([extensions §1.3](../../reference/extensions.md#13-calls-from-code-compiled-per-key)); owner-only functions `next-s3` e483299622 (D-9, E-458), with compiler C-130 | §1, §3 |
| run-time sites; each callee runs its own policy's code | Implemented (`unified`, W-100) | §4.2, §5 |
| kinds of methods; the policy rule; one CodeInstance per MethodInstance and policy | Implemented (`unified`, W-100) | §6 |
| `return_type`; reflection | Implemented (`unified`, W-100), with compiler C-47 | §7 |
| no asserted effect over a run-time site | Implemented (`unified`, W-100) | §8 |
| operations on a value typed by its trait: the split | Implemented (`unified` e70675a606, 50da8d8ee2, W-109; asserted ef1233e79e), with compiler C-38, C-39; the declared result from the contract, no method at the set for an operation without a default: Implemented (D-4; `next` 5448a8b7bf) | §9 |
| a membership invalidates as a method does | Implemented (`unified` a19d937eaa, W-140), with compiler C-77, C-79, C-88; taken back as a method's deletion: `next-s3` 213c759370 (D-13, E-459) | §10 |
| pirates followed; strict mode and its errors at their sources | Implemented (`unified`, W-100; strict mode TraitWorld 7adcc94 with `unified` 5f2373b2d5, W-114), with traits T-96, T-97, F-25; a pirate reported by default where it ends deep-G2 code: TraitWorld `s3` 2770c10, `next-s3` 5d2ec7ff85 (D-12, E-457) | §11 |
| package images, memberships activated before validation | Implemented (`unified` 28c401eb0c; W-100's facts and edges) | §12 |
| the store across sessions | paused | §12 |
| product setting, test bed, `--trim` | Implemented (`unified`, W-100); strict mode TraitWorld 7adcc94 (W-114) | §13 |
| what is final; a call settled; fully typed in a setting (a session, a closed build); a trimmed build as the facts rule with everything final | Implemented as the build's rules ([compiler §7.6](../../reference/compiler.md#76-a-closed-build)), stated as one input: mine (2026-11-15; D-10); Planned: compiler C-102, C-103 and the report's two lists (traits T-122) | §1, §3, §13.3 |
| standard libraries as owners | Open | §1 |

### §16 Deviations

- **The sentence above the table as it stood:** Where the unified build falls short of this page.
- **The retired rows** moved to the ledger's part `attic/writeup/record/deviations-retired-facts.part.md`: F-1 to F-23, F-25.
- **Taken from the open row F-24:** (157's case; found 2026-11-08 by E-311). (the row reads: (157's case).)
- **Taken from the open row F-24:** (`unified` 50261bb4c7: `typeinf_type` infers it uncached; gate `n15_image_policy`) (the row reads: (`typeinf_type` infers it uncached; gate `n15_image_policy`))
