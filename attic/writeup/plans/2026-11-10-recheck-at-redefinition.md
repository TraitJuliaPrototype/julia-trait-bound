# Plan: a member's check holds while it is a member (the result re-checked at a serving method's definition)

Status: **adopted with the review's changes** (2026-11-10; [the review](../reviews/2026-11-10-plan-review-recheck.md)); built in TraitWorld `unified` 5b3c427, E-342. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The gap

- [Traits §5.10](../reference/traits.md#510-checks): a membership is checked at its declaration, or at a pattern member's first use. Among the checks, each serving method's result must infer within the operation's declared result.
- Since open issue 171's fix (E-340, `unified` ef1233e79e), a call through the trait **asserts** the declared result and never converts it ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)). A dynamic call of the same operation returns the member's own result.
- So the two agree exactly when the member's serving methods keep satisfying the check. A serving method **defined after the check** escapes it:
  - a redefinition (`size(::M) = UInt(2)` after `size(::M) = 1` was checked);
  - a new, more specific method that takes the call (a method at `M` for a further argument type the check called with);
  - a method in another package that wins at the member (a pirate in the default tier).
- Then the call through the trait raises a `TypeError` (G1's "or raises"), while the dynamic call returns the method's value. Gate `n22_declared_assert` shows it at the runtime level.
- [The 171 plan's review](../reviews/2026-11-09-plan-review-171.md), M4/M5: the `TypeError` is acceptable under G1 only as a backstop; the invariant is the check, and TraitWorld's definition hook re-checks no result today (`src/implement.jl:168`).

## 2. The rule (traits §5.10, §5.11)

**A member's check holds while it is a member.** A method defined after a membership's check that would serve one of the member's operations at the call types the check used, with a result that infers outside the declared result, is refused at its definition: an `ImplementError` naming the member, the operation and both types. The method does not exist.

- The same shape as §5.11's rule for defaults ("a later method that would take a call a default serves at a member since its membership is refused").
- A method whose result infers within the declared result is accepted; it changes nothing the trait relies on.
- An operation whose check did not infer (a further argument declared abstract, `_open_further`) has nothing to re-check: the assertion stays its guard, as now.

## 3. The mechanism (TraitWorld)

- **The record:** where `_check_one!` (`src/check.jl` ~190–205) passes a result check, it records `(trait, member, call types, declared)` under the operation's function in `_RESULT_CHECKED::IdDict{Any, Vector{Any}}`, as `_record_defaults!` records the defaults' calls. `_forget_defaults!`'s counterpart forgets a member's records where its membership ends.
- **The check at a definition:** `_definition_hook(m, after = true)`, after strict mode's check and before `_check_bounded`:
  - read the records under `m`'s function (an `IdDict` miss for almost every definition);
  - for each record whose call types fall under `m.sig`, `Base.infer_return_type(f, tt)` in the latest world, where the new method is visible;
  - on a result outside the declared one, delete the method (`Base.delete_method`, as strict mode does for a pirate found after the definition, `src/strict.jl` `_strict_after!`) and throw the `ImplementError`.
- **Images:** a package image's method that fails the check is left inactive with a warning, through `_image_methods_hook` (§5.11's path), since a load cannot throw for one method. That needs the records: they are per session (`_CHECKED`, lowering L-55), so a check made while another image was built is not recorded in this session. Only checks made in the session are protected; L-55 covers the rest.
- **Cost:** one `IdDict` lookup per method definition; inference only for a definition that falls under a record.

## 4. Alternatives

- **Invalidate the member's check and re-check at the next use:** the next call through the trait raises `ImplementError` instead of `TypeError`. A better message, the same failure, later. Rejected: the definition is where the fault is.
- **Warn only:** the call through the trait still raises later. Rejected for the same reason; strict mode could make it an error, but the rule is about the trait's contract, not piracy.
- **Do nothing; the assertion is the guard:** what is built. The plan's point is that a contract checked once should keep holding.

## 5. Gates

- TraitWorld's suite, a new test file `test/recheck.jl`:
  - a member checked by `@implement`; its serving method redefined to a result outside the declared one: refused with `ImplementError`, the old method still in force, a call through the trait and a dynamic call both return the old value;
  - redefined within the declared result: accepted;
  - a new, more specific method at the member for another further argument type the check used: refused if outside;
  - an operation with an abstract further argument: accepted (nothing recorded);
  - a membership ended (where TraitWorld can end one): its records gone.
- The battery's TraitWorld suite and acceptance cases; the ports' suites through the battery's workloads (a port that redefines a serving method in its tests would show).

## 6. Records

- traits §5.10 (the rule) and §5.11 (the shared shape), the status naming the commit; the decision log, mine; open issue 168's recommendation (the re-check built).
- L-55's row: the records are per session as the checks are.

## 7. After the review

[The review](../reviews/2026-11-10-plan-review-recheck.md): build, with its changes. What was done with each finding (TraitWorld `unified` 5b3c427):
- **H1:** the re-check runs before the method is inserted, in the definition hook's first call and in the image hook: the new method itself is inferred at the call (`Compiler.typeinf_frame`, not cached), after `_would_win`. No deletion; a refusal works while a package is precompiled and leaves an image's method inactive.
- **H2:** a method that would make the operation ambiguous at the member is refused before inference.
- **H3:** traits §5.10's status states what is covered; L-55's row names the result records and the fix; W-130; gate `stack/recheck_packages.jl` asserts the uncovered case as accepted.
- **M1:** a forwarding member's methods are fixed calls, recorded once every trait of the declaration has its forwarders (traits §5.11).
- **M2:** the records are made at a pattern member's first use too, the defaults' among them.
- **M3:** a record names the operation and reads the declared result from the contract when the method is defined. A trait redeclared as a new type (Julia makes one) has no members: its old type's records are void.
- **M4:** a redeclaration forgets the member's records before its block is defined.
- **M5:** strict mode's invalidation log is stopped when a check before the definition throws. On the way: the image hook ran strict mode's walk too, which threw `PirateError` out of a load and left the log on; it now runs only the membership's checks, strict mode's image part being `_strict_image_refusals`.
- **L1, L2:** the names; the records listed in §6 and more (traits §7.9, §11.1, §11.3, facts §9, compiler §10.1, lowering §3 and §11, alternatives, open issues §1, the decision log).
- **L3:** the cost stated in traits §5.10's status. **L4:** a deleted serving method in §5.10. **L5:** the message names the method, the member, the operation, the declared and inferred result, and the two fixes.
- Beyond the review: a fixed call is matched by the intersection with the new method's signature and `_would_win`, not by subtyping alone, so a method that would take only part of a recorded call is seen, and one that would not win is not refused.

