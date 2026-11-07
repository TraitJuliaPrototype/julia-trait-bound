# C-32: a member at several values of an input parameter (for W-104's SciML slice)

Status: **proposal** (2026-11-08, mine). Not normative. It builds what [traits §3.2](../reference/traits.md#32-parameters) already states: inputs. Compiler C-32 and traits T-103 record the gap.

## 1. Why now

- **SciML's integrator view needs it.** It is declared `@trait IntegratorView{U, T, P} <: HasProperty{:ps, ParameterView{P}}` (TraitDifferentialEquations, `lib/ODECore/src/core.jl`).
- **BaseTraits' `HasProperty{N, R}` needs it** too (T-103). A type joins at each property name.
- The runtime refuses a member's second instance of a set even where the two differ only in an input. So slice 3 cannot be ported without designing around the gap, which the rules forbid.

## 2. What changes

1. **The runtime knows a set's inputs.**
   - The library passes the mask of the parameters marked `@input` when the trait is declared: `jl_set_input_params(tn, mask)`.
   - It is stored on the set's `TypeName`. Choice: a new byte `input_params`, a bit per parameter of the first eight. The alternative, a third element of `declared_fields`, mixes two things in one slot.
   - Images keep it with the `TypeName`.
2. **One instance per member, per input value.** `jl_declare_membership` refuses a second instance only where it agrees with an existing one in every input and differs elsewhere:
   - it asks the member against the set at the instance's input values, the other parameters left free (`HasProperty{:ps, R} where R`);
   - a redeclaration ends only the entry at the same input values.
3. **Subtyping takes every entry.** `subtype_membership` and `intersect_membership` already walk all of a type's entries for a set. To check:
   - the first-match shortcuts;
   - inference's positive folds through an entry (compiler §4.8), which must record the entry that matched;
   - the library's `_fwd` and the checks, which look up "the" instance of a member (`_contracts_of`, `_env`).
4. **A method's `where` variable or a stated value fixes an input** (§3.2). Where an operation's result needs an input that the call leaves open, the trait's method is refused at its definition.

## 3. Gates

- A type at two names of `HasProperty`: both hold; a third declaration at a name already held, with another value type, is refused.
- Dispatch on `HasProperty{:ps, P}` picks by the name.
- An image round trip keeps the inputs.
- TraitDifferentialEquations' `ParamIntegrator` declares `HasProperty{:ps, ParameterView{P}}` and `IntegratorView` on the unified build.
- The battery.

## 4. Size and risk

- Runtime: `datatype.c`, `jltypes.c` (the field), `julia.h`, `subtype.c` (any first-match shortcut).
- Library: `@input` passed on; the instance lookups made per input.
- One build with the system image; a day's work.
- The risk is in subtyping's shortcuts that assume one instance per member.
