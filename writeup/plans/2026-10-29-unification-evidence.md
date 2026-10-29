# Unification (W-83): the evidence to gather and the prototypes

Status: **proposal; §2.2 and U9 done (E-252 to E-259); gate A: [open issue 136](../open-issues.md)**, whose option (e) is the version to investigate (the user, 2026-10-29: "Yes. This is the version we want to investigate.") (2026-10-29, mine; for the user). The quick runs (the user, 2026-10-29: "Run U6 and U5 and the other cheap measurements.") are E-252 to E-258, and U9, option (e)'s guards, is E-259; their results are in §6. Not normative. Phase 4 of [the plan](../record/todo.md) ("Then the major open question remains: Do we go for unification?", the user 2026-10-29). It builds on [the exploration](../explorations/abstract-types-as-traits.md) (2026-10-28) and on the cases the three ports and NetworkDynamics recorded in W-83's row.

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

- **julia-1.13, a branch:** a membership registry, a cell per (type, set) holding the membership's `min_world` (U9: a scanned table costs 357–375 ns per read, a cell nothing measurable); `jl_subtype` and `jl_isa` read it when the supertype chain fails, for a set flagged as open; `isa_tfunc` and `subtype_tfunc` never fold a negative for such a set; `typeintersect` over-approximates for it.
- **TraitWorld, a branch on it:** `@implement` registers the membership; `conforms` becomes `<:` (L-5); the kept forms collapse (L-6, T-75).
- **Checks:** Base's `subtype` and `core` tests; `detect_ambiguities(Base)` unchanged; the `subtype` tests' time within 10%; every suite; acceptance in both settings; the four sessions.
- **This is U3,** with §13.4's four items as its specification, item 3 refined by U7 and U9: Core's kinds are never late members; Base's abstract types are closed, their members only through `struct S <: A` (§6).

### P2. Level 2: one dispatch

A design memo comes first, since two parts are new.
- **Dispatch caches.** Julia caches dispatch per concrete type. A membership added after a call at `S` was cached must invalidate that entry, as a method added at `S` would, or the call must never fold the negative membership (open issue 136, options (a) and (e)). U6 shows that this happens across packages too, for memberships declared in extensions (§6).
- **Under (e), the guard** reads the cell for (type, set), fixed when the guard compiles: a load and a compare against the caller's world, never a table lookup (U9). Base's abstract types are closed, so Base's generic functions carry no guards; Core's kinds are never members (U7).
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

## 6. Results of the quick runs

Each experiment's README holds its numbers and builds (`experiments/w83/`; julia-1.13 00dcc9994c, TraitWorld 33dd55e); the registry rows E-252 to E-259 summarize them.

| Run | Result |
|---|---|
| U6 (E-252) | Lemma M's premise fails for memberships in extensions: the member's own package compiles before an extension it triggers (R6) or its own (R7); an extension compiles before another whose trigger set is not a strict subset of its own (R8); an image older than the extension is reused (R12). It holds for a package strictly downstream of the extension (R1–R5, R9b, R10). |
| U5 (E-253) | No hit among 127 bounded methods (lowering L-3 already restricts them). With consent through the declarer's own abstract type, 31 of 52 sets are members by owner, all the ports' domain sets among them; the 21 open sets adopt Base's types. A `Base.show` on an open set is shielded except for `Factorization` and `IO`. |
| U8 (E-254) | TraitWorld's `conforms` decides in the newest world, and in the product setting `@implement` invalidates its `Main` caller (11 MethodInstances; lowering L-43, L-4). A registry with a `min_world` per entry, read in the caller's world with no edge, passes in plain Julia. |
| U7 (E-255) | Negative folds on an open set: 0.003–0.9 % of all negative folds, none in a demonstrator's loop. About 90 % of negative folds are the compiler's bookkeeping against Core's kinds. |
| U4 (E-256) | `f(@nospecialize x)` lies between `Compiled{Any}` and `Dynamic{Any}`. A `Dynamic` value at a bound costs an entry per call (80–96 ns, 80 B; 32–45 CodeInstances per new held type; traits T-94). |
| U2 (E-257) | A mixed `Vector{Any}` costs 15–57 % more than `Vector{Kept{X}}` at 2–4 types (0.2–0.7 ns per element), 7–13 % at 8. Raw members cost no more than `Kept`. |
| U1 (E-258) | 4 of 74 generic functions fully bounded with today's traits, 13 with documented interfaces as contracts, 20 if returning the argument were allowed (open issues 137, 138; traits T-91 to T-93). |
| U9 (E-259) | Option (e) of open issue 136 stands: 7 guard sites over five sessions (3 distinct), all at the plain-to-trait boundary, none in a loop, none in bounded code; 3 on a `MethodError` path, 4 on the capability predicate `is_nonlinear_algorithm` (a declared `::Bool` removes its widening). The sealed variant folds 4 of 7. A cell per (type, set) costs nothing measurable; a table lookup 27–28 ns. Open, Base's abstract types would put guards on 1,326–4,619 specializations per session. |

### 6.1 What the runs say for each level

This reading is the main session's (mine).

- **Level 1, membership in subtyping: supported.**
  - U7: never folding a negative costs nothing measurable, provided Core's kinds are never late members: `DataType`, `UnionAll`, `Union`, `Module`, `TypeVar`, the builtins, opaque closures and the memory types. Then the compiler's bookkeeping folds stay folded. Whether `Type{T}` may be a member is open.
  - Sets that Core and Base own can be `closed` by ownership, at no measured cost.
  - U8: the `min_world` registry works with no Julia change (part B). TraitWorld's `conforms` is not built that way.
  - U2: `Kept{X}` stays as the storage form for mixed containers. A `Dynamic` wrapper inside `Vector{Any}` costs a second load: 15–57 % at 2–4 types, 0.2–0.7 ns per element. Raw members cost no more than `Kept`.
  - U2: an operation on an item typed `X` must be the compiler's split at the call, not a method call at `X` (a run-time site, 127–234 ns).
- **Level 2, one dispatch, as the exploration states it: not supported.**
  - U6 refutes Lemma M. An extension is loaded before `P`'s code compiles only when `P` is a package (not an extension), neither the extension's parent nor one of its triggers, and has all triggers in its tree. For an extension `P`, only extensions with a strictly smaller trigger set are loaded. Images record the environment they were written in. R6, R7, R8 and R12 fail.
  - So memberships that C3 and C4 allow can win at compiled facts. C2 repairs none of the failures.
  - Either memberships are dispatch facts that invalidate as methods do (a membership is a definition, as C4 says, its invalidation included), and "an implementation invalidates nothing" weakens to "an implementation invalidates only what a stakeholder's method would"; or dispatch never folds a negative membership and guards the calls a later membership could change; or memberships in extensions are excluded or kept late. The options and the proposal ((e), which U9 supports, E-259; (a) as the alternative) are [open issue 136](../open-issues.md).
  - U9: under (e) guards arise only at the boundary, from capability predicates written as dispatch and from `MethodError` paths. None is in a loop, none in bounded code. (e) needs Base's abstract types closed and the registry a cell per (type, set).
  - U5: zero hits of the forbidden combination among 127 bounded methods, partly because L-3 already restricts them. With consent passing through an owner's abstract type, 31 of 52 sets are members by owner (all the ports' domain sets); the 21 open sets are those that take Base's types. The hypothetical `Base.show` is shielded for all members but `Factorization` and `IO`.
- **Level 3, one language surface: a simplification of the language, not of existing code.**
  - U1: it buys little sharing for existing code: 4 of 74 fully bounded with today's traits, 13 with documented interfaces as contracts, 20 if returning the argument were allowed. Code opens through calls to other generic functions and through iterator adaptors.
  - U4: `@nospecialize` is between `Compiled{Any}` and `Dynamic{Any}`: native code once, but inference per type at callers that know it.
  - U4: today's entry rebuilds the trait object on every call, also for a `Dynamic` value (80–96 ns, 80 B per call; 32–45 entry CodeInstances per new held type). That is a cost of today's encoding (traits T-94), not of the model.

**Gate A** waits for the user's decision on open issue 136. Level 1 (P1) does not depend on it.
