# Unification (W-83): the evidence to gather and the prototypes

Status: **proposal; §2.2 running** (2026-10-29, mine; for the user). The quick runs are E-252 to E-258 (the user, 2026-10-29: "Run U6 and U5 and the other cheap measurements."). Not normative. Phase 4 of [the plan](../record/todo.md) ("Then the major open question remains: Do we go for unification?", the user 2026-10-29). It builds on [the exploration](../explorations/abstract-types-as-traits.md) (2026-10-28) and on the cases the three ports and NetworkDynamics recorded in W-83's row.

## 1. The question, in three levels

"Unification" is three decisions. Each needs the one before it, and each is worth something alone.

| Level | What changes | Where in the exploration |
|---|---|---|
| **1. Membership in subtyping** | `@implement X S` makes `S <: X` and `s isa X` true in Julia. Storage collapses: `Vector{X}` holds raw members (`Compiled`) and `Dynamic{X}` wrappers, with `Dynamic{X} <: X`. Dispatch keeps today's two tiers. | §13 (candidate (c): never fold a negative), §5.2 |
| **2. One dispatch** | A bounded method is a Julia method at `X`, not an entry at `Any`. One kind of membership, under the coherence rule (C3 as a warning in trait modules, C4 in strict mode) and the tie order C7. | §11, §14 |
| **3. One language surface** | Trait modules dissolve into declarations on a scope; a function is classified fully bounded or open where it is defined; a set's name is a bound everywhere (decision 41 reversed). | §3 rules 4–5, §5.1, §15 |

The decision for each level rests on four kinds of evidence:
- **Soundness:** G1, G2 and Lemma O hold in every load order (the acceptance suite, U6, U8).
- **Cost:** Julia's subtyping and dispatch stay as fast; the four sessions are no slower than [today's](../design/evidence.md).
- **Simplification:** what disappears from the references, the deviation tables, the open issues and TraitWorld, against what is added.
- **The ports' cases:** each case recorded in W-83, written in the unified form.

## 2. Evidence without a Julia build

Each item is an Opus agent's task; registry rows come first. The no-build experiments are minutes to an afternoon each.

### 2.1 On paper

- **E1. The simplification ledger.** For each level: which rules of the references, which deviations (for example L-1 to L-6, L-3, L-47, L-48, L-50, T-23, T-75, T-83), which open issues (for example 82, 112, 124's mechanism, 132) and which TraitWorld files go, change or stay. A count of TraitWorld's lines in the entry and kept-form machinery. Added rules listed beside them.
- **E2. The ports' cases, replayed.** Each case from W-83's row in the unified form, with what it would change in the port:
  - Makie: `AbstractPlot` as an alias of `Plot`; `Block` and a `Layoutable` trait; `Scale` on `typeof(log10)`; `Lines`/`Scatter` as two families under one name.
  - SciML: `Trajectory` beside `AbstractDiffEqArray`; `ODEProblemTrait` beside `AbstractODEProblem`; the front end on CommonSolve's `solve` (refused today by L-3 only).
  - NetworkDynamics: `GraphInterface{V}` beside `AbstractGraph`; `VertexModel`/`EdgeModel` beside the traits.
  - DataFrames: subtrait methods on a supertrait's operations (W-92); the untyped API layer over `Any`.
  - L-50: a bounded constructor beside Julia's default constructors.

### 2.2 Quick runs on today's build

| ID | Question | Decides |
|---|---|---|
| U6 | Does an extension load before a dependent's precompile workload (Lemma M)? | whether the coherence rule (§11) is the right cut; otherwise C2 |
| U5 | How often do the ports bound a foreign function by a set with foreign members, and does a typed method shield each hit (§14.4)? Now over all four ports. | the coherence rule's real cost |
| U8 | Does a function compiled before `@implement` see the membership after it, with no recompile, in the right world? | the `min_world` rule for the registry (level 1) |
| U7 | How often does inference fold a negative membership, and where? (a counter in a forked `Compiler`) | whether "never fold a negative" is free (level 1) |
| U4 | Is `f(@nospecialize x)` under facts the same as a `Dynamic` position? | rule 5's reading (level 3) |
| U2 | Is `Vector{X}` of raw members and wrappers as cheap as `Vector{Kept{X}}`? | the storage collapse (level 1) |
| U1 | How much generic code is fully bounded as written? Now on the ports' plain layers (DataFrames' API layer, MakieCompat, ndport's plain code) and a slice of Base's `abstractarray.jl`. | whether level 3 pays beyond the language |

## 3. Prototypes (builds)

### P1. Level 1: membership in subtyping

- **julia-1.13, a branch:** a membership registry whose entries have a `min_world`; `jl_subtype` and `jl_isa` read it when the supertype chain fails, for a set flagged as open; `isa_tfunc` and `subtype_tfunc` never fold a negative for such a set; `typeintersect` over-approximates for it.
- **TraitWorld, a branch on it:** `@implement` registers the membership; `conforms` becomes `<:` (L-5); the kept forms collapse (L-6, T-75).
- **Checks:** Base's `subtype` and `core` tests; `detect_ambiguities(Base)` unchanged; the `subtype` tests' time within 10%; every suite; acceptance in both settings; the four sessions.
- **This is U3,** with §13.4's four items as its specification.

### P2. Level 2: one dispatch

A design memo comes first, since two parts are new.
- **Dispatch caches.** Julia caches dispatch per concrete type. A membership added after a call at `S` was cached must invalidate that entry, as a method added at `S` would. Lemma M says this happens only in a stakeholder's own session (`Main`); the mechanism must still exist.
- **Specificity.** The tie order C7 in `jl_type_morespecific`. Ambiguity between unrelated sets reported when a common member appears (T-83's report).

Then the prototype: the entry moves from `Any` to `X`; the untyped fallbacks go (L-3, L-47, L-50). It is validated on the cases that need it: SciML's front end on CommonSolve's `solve`, Makie's `Block`. Invalidations are counted in the acceptance suite's late loads.

### P3. Level 3

On paper only, until levels 1 and 2 are decided. A prototype at most of the classification as a report outside trait modules.

## 4. Order and gates

1. E1, E2 and the quick runs (U6, U8, U4, U2, then U5, U7, U1) in parallel. Several agents; no build.
2. **Gate A:** the user decides whether to build P1, and whether P2's memo is written.
3. P1, a build alone (`jl --exclusive`). **Gate B:** level 1 adopted or not.
4. P2's memo, then P2. **Gate C:** level 2.
5. Level 3 decided on paper.

Until gate B, W-27 stays queued.

## 5. What waits for it

- **L-50's Julia change** (precompilation removing a method its own package defined). Level 2 removes its need: a bounded constructor becomes a method at `X`, not at the default constructor's signature. By the rule against work that unification would obsolete, it waits.
- The open issues that name W-83 (112, and the cases in W-83's row).
