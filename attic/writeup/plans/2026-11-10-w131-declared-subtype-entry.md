# Plan: a `struct S <: X` member keeps its check from an image (W-131)

Status: **adopted with the review's changes** (2026-11-10; [the review](../reviews/2026-11-10-plan-review-w131.md)); built in TraitWorld `unified` e8554d9, E-345. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The gap

- [Traits §5.10](../reference/traits.md#510-checks): a member's check holds while it is a member. Since W-130 (E-344) the records of the check come back for a membership loaded from an image, made again from the runtime's list of activated memberships.
- [Traits §5.2](../reference/traits.md#52-with-the-types-definition): `struct S <: X` makes `X` the supertype of `S`; `@implement X S` declares and checks the membership. TraitWorld makes **no runtime entry** for it (`src/implement.jl`, `_implement_one!`: "`struct S <: X` needs no entry: X is S's declared supertype"), since `S <: X` holds nominally.
- So a `struct S <: X` member loaded from an image has nothing in the list: its records are not made again, and a later method at `S` that breaks its check is accepted (gate `stack/recheck_packages.jl`, case 5, asserts it). The same form also escapes:
  - the ambiguity report at a membership (compiler §5.4) and strict mode's refusal (T-98): a `struct S <: X` member of two traits with ambiguous methods gets no warning at its `@implement`;
  - lowering §3's own intended step for it ("records the receiver on `S`'s `TypeName` in place of step 6", L-52): not built, so nothing at all marks the membership in the runtime.
- The user's words for the form (2026-11-06, Q8 (c)): "declared membership stays as a design goal". Traits §5.2: "A membership is always declared, and checked where it is declared."

## 2. The proposal: `@implement X S` declares the entry for a declared subtype too

- `_implement_one!` calls `_declare!(S, inst, mod, by, receiver)` for a `struct S <: X` member as for any concrete member, with the instance the check computed (`X{p…}` where `S <: X{p…}` by its declaration).
- The runtime accepts it: on the concrete path `S <: set_at_inputs` and `S <: inst` both hold by the declared supertype, so it is treated as a first declaration at that instance (`redeclare`, ending nothing). A stated instance that disagrees with the declared supertype is refused as a second instance, which is right.
- Then for this form, as for every membership: the image keeps the entry, activation lists it, W-130's sync makes its records again; the receiver is on the entry (L-52's "receiver recorded"); the ambiguity report runs at its declaration, and strict mode refuses an ambiguity.
- `abstract type A <: X end; @implement X A`: `A` is a pattern member; its members are checked at their first use, which makes their records in the session (unchanged). Declaring its entry too is the same change at a pattern; proposed for the same reasons.

## 3. What changes besides

- Subtyping: `S <: X` already holds by the supertype; an entry adds a second witness. `jl_type_has_memberships(S)` becomes true, so subtype queries at `S` take the membership path (§4.11's cost for a member). Inference's folds of `S <: X` may record the entry as a positive-membership edge (compiler §3.1) where the nominal answer needed none; the entry never ends, so the edge never invalidates.
- The declaration's world: the entry allocates a world and runs the cells' update and the stopgap's walk (C-18) for `S`, as every membership does.
- References: traits §5.2 (the membership is declared like any other; `S <: X` holds from the definition, the entry from the `@implement`); lowering §3 (step 6 runs for the form; L-52's receiver on the entry); the use before the `@implement` (L-52's other half) unchanged.

## 4. Alternatives

- **The runtime's record on `S`'s `TypeName`** (lowering §3 as written): a new slot and an image field, read by the sync; a second kind of membership record beside the entry. Rejected for one kind.
- **A module-owned list** of the package's `struct S <: X` members, written by the macro into a global the package's image keeps, read by the sync for each loaded module: no runtime change, but a library-side shadow of the runtime's entries, and the ambiguity report and strict mode still miss the form. Rejected.
- **Leave it uncovered** (W-131 open): the form is used by TraitWorld's tests and the references' examples, none of the four ports. Rejected under tonight's rule.

## 5. Gates

- `stack/recheck_packages.jl` case 5 flips: `Tri2`'s method outside the declared result refused.
- TraitWorld's suite (core.jl's `struct S <: X` cases, the module-end hook's case); `test/strict_membership.jl` with a `struct S <: X` member of two traits refused under strict mode; the battery (the acceptance cases with memberships), the ports' checks and TDE's suite.
- A count: the entries TraitWorld's own image activates before and after (its declared subtypes).

## 6. Records

- traits §5.2, §5.10's status, §7.9; lowering §3, L-52, L-55; compiler §5.4 (the report covers the form); facts §9; the decision log, mine; W-131 done; open issues §1.

## 7. After the review

[The review](../reviews/2026-11-10-plan-review-w131.md): build, with its changes. What was done (TraitWorld e8554d9):
- **H1:** the abstract form's subtypes were never checked: the runtime calls the member hook only where an argument's chain carries an entry. The entry at `A` starts the check: compiler C-85, retired by the commit; TraitWorld's `test/declared.jl` (in a session, the trait without a supertrait) and the gate's case 7 (an abstract member from an image).
- **H2:** `_params_at` reads the declared supertype's parameters first and refuses a stated value or a field's type that differs, by name, at a plain and an input parameter; the bare `@implement Hold HB` for `HB <: Hold{Int}` is accepted.
- **M1:** under strict mode, a refused declaration of the definition's trait leaves the type its subtype: traits §6.3 states it, the module-end hook names the refusal; C-78 named as the fix that makes the order irrelevant (open issues §1).
- **M2, M3:** the plan's §3 was wrong on edges and sections: the chain answers `S <: X`, so the entry adds no edge there; the hook's extra calls at the concrete form pass. Stated in compiler §4.2.
- **M4:** W-131's row; E-345; compiler §4.2's "needs no entry" changed; the candidates named and tested; the `by` case; strict mode in both orders; `alternatives.md`.
- Not done: the use of `S` through `X` before its `@implement` (L-52's remaining half).

