# Review: a membership is a method (W-141), as built through stage 2

The user (2026-11-12), after the night's report: "Your task is to review this and make the judgement call if it's worth it or if there are further alternatives worth considering."

Written in the main session (no subagent). *Verified* means read in the code or seen in a run of my own; *inferred* means reasoning from them.

**What was read:** the proposal and its addendum; the build plan; `experiments/unification/w141/README.md`; open issue 180; the diff `unified` b1c0b50f4c..b66cdc66f2 (`src/datatype.c`, `gf.c`, `method.c`, `staticdata.c`, `subtype.c`, `Compiler/src/typeutils.jl`, `stmtinfo.jl`, `base/boot.jl`); gate `n29_membership_method`, `n10_inputs`.

**What was run** (2026-11-12, `unified` f6ad3008b4, one run each, load 2 of 128): `w141/probe_valuesig.jl`, `w141/probe_refused.jl`; logs in `w141/logs/`.

## The verdict

**Adopt it. It is worth it for the definition, not for the size of the code.** Three conditions:

1. The definition names the existing concept exactly: **method existence**, not dispatch (§1).
2. The references keep four rules as the membership's own (§2). The night's report expects two of them to dissolve; they do not.
3. One alternative is tried before the references are written: the member as an argument type (§4, A1).

The mechanism of stage 1 stands on its own, whatever is decided on the rest: it costs nothing measurable, and Julia's edges replace the cells.

## 1. What the concept is

The proposal says "a membership is a method" and then lists exceptions: the method is never called, two that apply are no ambiguity, the body is read and not run.

These are not exceptions once the concept is named. Julia has two uses of a method table: dispatch (which method runs) and existence (`hasmethod`, `applicable`). A membership uses only the second.

> `S <: X` holds where `Core.implements` has a method that applies to the pair.

- Existence has no ambiguity: R11 (open issue 180 (d)) is then the rule, not a deviation from one. Only the tools need to leave `Core.implements` out.
- A folded negative is what a folded `hasmethod` that answered `false` is: an edge at the signature with no method. This is the part Julia already has in full.
- The method is not called, so its body carries data (the receiver). That is a convention of this one function, to be said once.

*Verified* against the built state: this is what the runtime does (`record_memberships!`, `add_absence_edge!`).

## 2. What is not a method's, and stays a rule of the membership

The proposal's table has ten rows. As built: six hold, two do not (ambiguity, deletion), two hold in part (what a declaration recompiles; `methods` as the list of members).

| The membership's own rule | Why a method does not give it | State |
|---|---|---|
| **One instance per member** (compiler §4.6) | Two methods at `(Type{X{Int}}, Type{S})` and `(Type{X{Float64}}, Type{S})` are two methods, both valid. Coherence is refused by the runtime | built as today |
| **The same rule at an image's load** | Julia activates an image's methods; it has no way to refuse one. R12's note "goes away when the method is the only record" does not hold (*inferred*): with one record the refusal has to disable a method at activation, a step Julia does not have | open issue 180 (e), reworded |
| **The reach to callers of the trait's methods** | A caller of `area(::Shape)` holds an edge on `area`. A new or removed method of `implements` does not reach it. The walk stays, in both directions | the walk at a declaration is built; at a removal not (180 (c)) |
| **The contract and its check** | The method says that `S` is a member, not that it can be one | `@implement`'s, as today |

And two kinds of member have no method: a member by its definition (`struct S <: X`) and `Callable`'s. `members(X)` is therefore not `methods(Core.implements, …)`.

**Consequence for the size of the code.** The index that subtyping reads stays; the walk stays; a step at an image's activation stays. What can go with "the method as the only record" is the entry's own worlds, the library's second ownership rule and part of the image's list. I expect a modest reduction, not the one the proposal lists. The case for adoption does not rest on it.

## 3. Findings on the built state

**H1. Two records, and they can disagree; the pattern is every refusal after the method is added** (*verified*). `declare_membership` adds the method to the table before the checks (the cycle, one instance per member, strict mode's ambiguities). A refused membership written by hand leaves its method in the table, never activated: `probe_refused.jl` finds one entry at the signature, `primary_world` unset, invisible to `methods` and `hasmethod`. R12 is the same pattern at an image's load, where the method *is* activated.
- Harmless in a session. Not checked: whether a package image that caught such a refusal activates the method at load.
- The fix at the rule: one record. Until then, add the method after the checks, under the same lock.
- Recorded: open issue 180 (h).

**M1. The half-built state should not stay.** While the entry and the method both exist, each site that ends or refuses an entry has to do the same to the method. I read the three sites that end an entry (`datatype.c` 691, 715, 1391). The two redeclarations give the same signature, so the new method replaces the old (*inferred* from the one-instance rule; not run). The refusals are H1. Either the step to one record is taken, or the method is demoted to the edge's carrier and no program may write one. I recommend the first.

**M2. A method that cannot be deleted breaks the row it was adopted for.** With `@implement` lowered to a method, Revise will delete it when the line is removed, and get an error. Until the walk runs at a removal, the references carry this as a deviation; `intro/` must not say "as a method: delete it".

**L1. The hand-written form has three rules a method does not have:** a canonical spelling (the other is refused), a body that is a literal, no deletion. A1 removes the first.

## 4. Alternatives

**A1. The member as an argument type: `implements(::Type{X}, ::S)`. Worth trying before the references are written.**
- `x isa X` then reads: `applicable(Core.implements, X, x)`. A concrete member, a family and an abstract member have one spelling; the runtime's refusal of "the other spelling" goes.
- Measured on plain functions (`probe_valuesig.jl`): 2,000 abstract members insert at a constant 0.52 to 0.57 ms each, where `Type{<:A}` grows to 12.5 ms each; `methods` 1.4 ms against 19.6 s. Concrete members as `Type{S}`: 0.72 ms each, the same.
- It removes R1's leftover ("abstract members of one trait cost each other").
- It does not remove R11: `Test.detect_ambiguities` reports nothing for 20 abstract members under either spelling, so the library's 12 pairs come from types that are in both subtraits. That overlap is real under any spelling.
- Not tried in the runtime. The risk: the member now stands in argument position, where the machinery for methods at a set looks (`jl_has_open_set_in`, the dispatch walk); `jl_is_implements_sig` already exempts the function. A negative's signature becomes `(Type{<:X}, S)` for every kind of member.
- Cost of the trial: the two signature builders and the reader of a hand-written method in `datatype.c`; the gates.

**A2. One function per trait.** It gives each trait its own list of negative edges, so R5 needs no change to Julia. Not recommended: a hidden name per trait, and the piracy rule no longer reads at one function. R5 has a local fix (180 (a)), and no real session needs it yet (0 to 6 negatives): bin B.

**A3. Stop at stage 1: the method as the mechanism only, no method written by a program.** The definition would stay "behaves as a method" (W-140). It is the fallback if the step to one record fails. Not recommended as the aim: the lowering of `@implement` to a method is what lets images, Revise and the tools treat a membership as they treat a method, without code of their own.

## 5. The two open choices

- **Adopt the definition:** yes, in §1's wording, with §2's four rules stated as the membership's own.
- **Strict mode's rule for a third party's membership:** the pirate method's rule. One rule is the reason for adopting; the one case of 126 where the rules differ is the library's own membership of Core's `Dynamic`, settled by naming the library a joint owner.

## 6. The order I propose

1. H1: the method is added after the checks.
2. A1: the trial, with the gates. Its result fixes the spelling in the definition.
3. The references, `intro/`, the glossary, the decision log, in one commit: the definition, the four rules, deletion as a deviation.
4. Bin A: the method as the only record, scoped by §2 (the index and the step at an image's activation stay).
5. Bin B: 180 (a) the index of negative edges; 180 (c) the walk at a removal.

## What was done with each finding

- H1: open issue 180 (h); `w141/README.md` R16; `probe_refused.jl`.
- The four rules, the size of the code, R12's note: open issue 180 (e) reworded, 180 (i).
- A1: open issue 180 (j); `w141/README.md` R17; `probe_valuesig.jl`.
- The verdict: open issues §1, the W-141 item. The decision's row in the log is written with the references (step 3), as the rule for decisions asks.

## Addendum, 2026-11-12: the premise changed, and the verdict with it

The user, on the review: "Conceptual parsimony for the user only requires implementation to behave like a method. The implementation can be whatever is simplest/cleanest/fastest." Then: "I want that."

The verdict above ("adopt the definition") is superseded. With that premise:
- **Nothing is adopted as a definition.** "Behaves as a method" is what the references say already (W-140).
- **Stage 2 is removed** (the method written by a program). H1, M2 and L1 go with it; the runtime's own declaration adds its method after the checks.
- **The method as the only record is not built** (§6, step 4): it was justified by the definition.
- **A1 is no design question:** the signature is internal. It stays as a fix if abstract members come to cost (open issue 180 (j)).
- **Stage 1 is kept over cells, by a thin margin:** about 70 lines fewer, no edge kind, image format or validation branch of its own, and which negatives a membership ends rests on Julia's type intersection. In sessions the two cost the same.
- **§2's four rules and §5's strict-mode choice stand.** A membership refused at an image's load now takes its method out of force.

Done: `unified` 8b4fde6e84; compiler §5.6, C-89 retired; the decision log §4; open issue 180 rewritten, (b), (e), (g), (h), (i) closed; `design/alternatives.md`.

**Found on the way:** `design/alternatives.md` had been cut from 512 lines to 3 by commit 6f75a0b (2026-11-12). It is restored from the commit before, with the three entries added since.
