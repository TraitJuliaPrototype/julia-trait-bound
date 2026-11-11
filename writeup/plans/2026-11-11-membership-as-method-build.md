# A membership is a method: the build plan

**Status:** adopted as a build plan (2026-11-11, the user: "make a plan that builds it"); the design itself is not adopted yet. It builds [the proposal](2026-11-11-membership-as-method.md) (W-141) in stages. Each stage has a check that can stop it, and each problem found is flagged where the synthesis reads it. Written in the main session. Not normative: the references change when the user adopts the design.

## The user's words

> "Okay, next up is 1. It is a conceptual simplification so I heavily lean towards adopting it. But I want to be sure the trade offs are manageable. So make a plan that builds it, but keep attention to managing and flagging where it might make problems. Record all this."

## How problems are managed and flagged

- **One log of findings:** [`experiments/unification/w141/README.md`](../../experiments/unification/w141/README.md), a table with one row per trade-off: what was expected, what was found, how it was handled, what is left. Its registry row is E-367.
- **A problem that sets one goal against another** becomes a tension (open issues §1, a row in the goals' §3).
- **A problem that a rule of the proposal cannot carry** stops the stage. The stage's branch stays; the references are not changed; the finding goes to open issues §1 under W-141.
- **Each stage is its own commit** on `julia-unified` and the library, so a stage can be taken back alone.
- **Measurements are small** (minutes): the gates, the suites, one order of the composition case, one load profile. The rounds wait for the conceptually complete state (W-145).

## The trade-offs watched

| # | Trade-off | Where it would show | The check |
|---|---|---|---|
| R1 | One function holds every membership of a session: thousands of methods under one name | definition time per membership, ambiguity checks, `methods` | stage 0: a plain function with 5,000 such methods |
| R2 | A trait with inputs puts a type with free variables under `Type{…}` | the instance per member, read from the method's signature | stage 0: plain dispatch on `Type{X{T}}`, `Type{<:S{T}}` |
| R3 | An abstract type's pair, and an intersection no type is in, need an edge a missing method can carry | negatives at abstract types (`n20_unmet_lookup`) | stage 0 on paper and by a case; stage 1's gates |
| R4 | Image validation asks a method lookup per folded pair, where a cell was a pointer compare | load time of images with many folded negatives | stage 1: the load profile of TraitTables and the library |
| R5 | Insertion into one large method table at each membership | `@implement`'s cost, the library's load | stage 1: the library's load, E-358's twenty packages in one order |
| R6 | Subtyping in an older world reads the index, the method has the worlds | `invoke_in_world` cases of the gates | stage 2's gates |
| R7 | The cost to code that uses no trait (GT-9) must not grow | the plain control | stage 1 and 2: one plain step of E-356, small |
| R8 | Bootstrap: memberships before generic functions work | Core's own sets | found at stage 0: only the library declares memberships, after Base; `Callable` has its own rule. No risk |
| R9 | Strict mode's rule changes with the method's rule (the proposal's choice (c)) | `strict.jl`, `ownership.jl` of the library | stage 3 |
| R10 | Revise and deletion: a membership taken back | a method deleted | stage 2: by hand, one case |

## Stages

**Stage 0: probes, no build.** R1, R2, R3 on plain Julia functions in a session of the head. *Stops the work:* dispatch cannot give the instance per member for a trait with inputs; or definition past a few thousand methods costs more than milliseconds each.

**Stage 1: every membership has its method; folds rest on it.**
- `Core.implements` exists. `jl_declare_membership` also defines the method `implements(::Type{X}, ::Type{<:S})` in the declarer's module, in the same world.
- A folded negative records a missing-method edge at the pair. Cells, their table, their image format and their branch in validation are removed.
- A folded positive records an ordinary edge to the method. `MembershipEntry` stops being a kind of edge.
- The entries stay as the index subtyping reads.
- *Checks:* the gates (`n18_closed_after_load`, `n20_unmet_lookup`, `f7_membership_edges`, `n3_image_memberships`, the rest), the library's suite, TraitTables and TDE; R4, R5, R7 small.
- *Stops here:* R4 or R5 costs more than the cells did by a margin that shows in the library's load; or R3 has no sound edge.

**Stage 2: the method is the declaration.**
- `@implement` lowers to the method's definition and the check. Julia's method insertion indexes a method of `implements` as a membership; an image's methods are indexed when they are activated. The image's own list of memberships and their activation are removed.
- A deleted method ends its membership (R10).
- *Checks:* every gate that declares a membership, the suites, the image gates in both load orders; R6.

**Stage 3: the rules that become a method's.**
- Ownership and piracy read from the method's rule; the library's membership rule in `ownership.jl` removed; strict mode by the method's rule (R9).
- The references, `intro/`, the glossary and the decision log: only when the user adopts.

## What the user gets in the morning

The findings table, with each trade-off's row filled; the stage reached; and a recommendation to adopt, to adopt with named deviations, or not to.
