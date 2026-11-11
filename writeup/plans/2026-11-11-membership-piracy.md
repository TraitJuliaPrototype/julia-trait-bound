# A membership by neither owner is piracy; a membership invalidates as a method does

**Status:** adopted by the user's word ("Write a proposal and implement it after the current line of work has concluded."); stage 1 built 2026-11-11 (`unified` 80aa919bed, TraitWorld dbfb488); stage 2 built the same day for concrete types (`unified` 1b2f0a9e1e); the rest of stage 2 and stage 3 are open, for the two reasons compiler C-88 names. Written as a proposal (2026-11-11, written in the main session; W-140), with its implementation planned in three stages (the same day, at the user's word: "If builds are long you can plan W140 in the meantime."). To build after W-139. Not normative: the references change when it is built.

## The user's words

> "I want to revisit one older decision: I think on reflection it is reasonable to say that declaring membership of a type in a trait if you own neither the type or the trait is piracy. Forbidden in strict mode, causes recompiles in default. What would that change/simplify?"

> "Write a proposal and implement it after the current line of work has concluded."

The older decisions it revisits: "a membership invalidates nothing" as a committed guarantee (2026-11-06, open issue 146), and "Finality should be opt in." (2026-11-09).

## The rule proposed

1. **Who may declare a membership without piracy** stays as it is ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)): the trait's owner or the type's owner, with their joint owners and extensions.
2. **A membership by a package that owns neither is a pirate's.** By default it is followed, and the code that relied on its absence is compiled again. Under strict mode it is refused. Today it is refused in every mode (`OwnershipError`).
3. **A membership invalidates as a method definition does:** the code that relied on its absence, and nothing else. Such a membership is a stakeholder's declaration or a pirate's. This replaces "a membership invalidates nothing".
4. **So compiled code may rely on a non-membership.** `isa` and `<:` fold; a call selects its method without a guard. The code records the pair (type, trait) it relied on, and a later membership of that pair invalidates it.

Rust's orphan rule is rule 1 enforced absolutely. Rule 2 is Julia's stance on type piracy, applied to memberships.

## Why the guarantee still holds

G2 says code compiled by facts is invalidated only by a stakeholder's change or a pirate's that wins ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). With rule 1, a membership of (S, X) is declared by an owner of S or of X, both stakeholders of any code that asked whether S is an X. With rule 2, any other is a pirate. So a membership that invalidates is inside G2 already, by the argument of Lemma O. G2 needs no clause of its own for memberships.

What a user can still rely on:
- **A new type joining a trait invalidates nothing:** no earlier code can have asked about a type that did not exist. This is the case of composition (E-358: twenty packages, each adding its own member).
- **An unrelated load invalidates nothing:** it declares no membership of a pair that earlier code asked about, unless it is a pirate.
- **What recompiles:** an existing type joins an existing trait after code used both. By an owner: a package extension that loads late, a declaration at the prompt, Revise. By a pirate, in default mode.

## What it removes

The mechanism exists already, for one kind of trait: a trait closed after load ([traits §3.4](../reference/traits.md#34-open-and-closed), [compiler §4.8](../reference/compiler.md#48-negatives-never-fold-positives-through-entries)) folds its negatives, records the pair's cell as an edge, and is invalidated by a late membership. The proposal makes that the rule for every trait.

| Today | With the rule |
|---|---|
| A negative never folds at an open trait (compiler §4.8) | It folds, with an edge on the pair's cell |
| A guard on every call that a later membership could change; the shadow query at inference (compiler §5.6) | No guard. The call records the pairs its choice rests on |
| A guarded call's result is joined with the shadowing method's declared result, `Any` where none (compiler §5.6; open issue 158's `@inferred` failures) | The call's own result |
| A method at a trait defined later invalidates callers with a pruned arm at a type that *could* join (compiler §5.6; GT-1's other side, GT-11) | It invalidates callers at types that *are* members |
| `@closed_after_load`, its bit, "settled" and "not settled" ([traits §3.4](../reference/traits.md#34-open-and-closed)) | Gone: one kind of trait |
| G2's clause "or a membership declared late at a trait closed after load" | Gone |
| A third-party membership refused in every mode | A pirate: followed by default, refused under strict mode |

Tensions it should close or shrink: GT-1 (closed), GT-9 and GT-11 (to measure). It does not touch GT-7 (code compiled once reaches a later member through the table, relying on no negative), GT-14 (a membership still has a world) or the closed build.

## Choices inside it

- **(a) Fold everywhere, or keep guards while a declarer loads?** Today a trait closed after load keeps its guards for code compiled while a declarer is still loading. *Proposed:* fold everywhere, with the edge. A package that uses a type with a trait's method and declares the membership later in its own source recompiles that code while it is precompiled, once. It is the package's own change. This removes the guard, the cell's fast path and "settled" entirely. *The alternative* keeps all three for the loading window.
- **(b) What strict mode refuses.** The user's words: "Forbidden in strict mode". *Proposed:* every membership by neither owner is refused under strict mode, with `PirateError`, whether or not compiled code relied on its absence. A method pirate is refused only where it would win at a fact of code compiled by facts ([traits §12.3](../reference/traits.md#123-strict-mode)); a membership makes every method at the trait apply, so "wins nowhere" is rare and not worth a walk.
- **(c) The prompt.** `Main` owns what it defines. `@implement Shape Vector{Float64}` at the prompt, for a package's `Shape`, is a pirate's: followed by default, with recompiles. Today it is refused.
- **(d) A positive membership** stays as it is: relied on through its entry, with the world.

## What to measure, before and after

**Deferred** (the user, 2026-11-11: "Small measurements are fine. Larger measurement campaigns that take more than a few minutes should be avoided until we have reached a conceptually complete state of the prototype."). While the stages are built, each is checked by the gates, the library's tests and small cases of minutes: one composition order of E-358 with a few packages, one plain step, open issue 158's two cases. The rounds listed below wait for the conceptually complete state.

Each on the same build but for the change, a registry row first.
- Composition: E-358's twenty packages in five load orders. Expected: no instance ended, as today.
- The plain session: E-356. Expected: DataFrames' repeated steps closer to vanilla's (GT-9); fewer than 197 plain instances ended by the library's load (GT-11).
- Unrelated loads: E-355, upstream and the forks. Expected: no more instances lost.
- The library's load at a REPL: the log entries at TraitWorld's load (GT-1: about 3,600).
- Open issue 158's two cases in upstream CSV and DataFrames: the `@inferred` failure and the bytes per cell.
- The gates: `m2_*` pin guards and cells and are re-pinned; `n18_closed_after_load` becomes the rule's gate for every trait.

**Would stop the work:** a load order in E-358 that ends instances; or unrelated loads losing more than today.

## Steps

1. A registry row and the measurements above on the build before.
2. Julia: every open set takes the path of a set closed after load, from its declaration; the shadow query and the guard removed; a method at a set invalidates at members only. The library: `@closed_after_load` removed; a third-party membership declared with a warning by default, refused under strict mode.
3. The gates and the library's tests; then the measurements after.
4. The references (facts §2.2, §10; traits §3.4, §6.2, §12.1 to §12.3; compiler §4.8, §5.5, §5.6), the decision log, the goals' tensions, `intro/`.

## The implementation, in three stages

Planned 2026-11-11 from the code as it is (`unified` 97861c6b31, TraitWorld 19862aa). The mechanism is already there for a trait closed after load; the stages widen it, measure, and only then delete. Each stage is one build of Julia and one round of the measurements above.

**Where the rule lives today.**
- `jl_membership_final(S, X)` (`src/datatype.c`): "S is not an X" is final where `X`'s `TypeName` has the bit `closed_after_load` and the declarers (the module of `X`, the module of every `TypeName` in `S`) have finished loading (`module_loaded`).
- Inference folds a final negative and records the pair's final cell as an edge (`jl_membership_final_cell`, `…_add_backedge`); a membership declared later invalidates through the cell.
- Where the negative is not final: the shadow query (`jl_call_shadows`, `jl_could_join`), the guard (`GuardedCallInfo`, the inliner's guarded split) and the widened result.
- The library: `@closed_after_load` in `@trait` (`jl_set_closed_after_load`); `OwnershipError` for a membership by neither owner (`ownership.jl:228`).

**Stage 1: every trait is closed after load; a third-party membership is a pirate's.** Small, and it keeps every guard for code compiled while a declarer loads.
- Julia: `jl_set_open_set` sets `closed_after_load` (one line). `Callable` and the other core sets keep their own rule.
- The library: `@closed_after_load` accepted and ignored, with a note. A membership by neither owner: declared, with a warning that names the owners (default); `PirateError` under strict mode. The prompt (`Main`) is such a declarer for a package's trait and a package's type.
- Checks: the gate `n18_closed_after_load` run for a trait without the option; the `m2_*` gates that pin a guard after both declarers have loaded are re-pinned (19 files to read; those that declare trait and type in `Main` keep their guards, since `Main` is never loaded); TraitWorld's suite (`ownership.jl`, `strict.jl`).
- Measure: everything in "What to measure". This stage alone answers whether composition and the unrelated loads hold, and what the plain session gains (GT-9).

**Stage 2: fold while a declarer loads, too.** Choice (a) of this proposal.
- Julia: `jl_membership_final` drops the condition on `module_loaded`, for open sets. Then no pair is "not final": the shadow query finds nothing to guard.
- A method at a set, at its insertion, invalidates the callers at types that are members (the dispatch edge they hold), no longer those with a pruned arm at a type that could join (`jl_could_join`'s use at insertion).
- Measure: the library's load at a REPL (GT-1's 3,600 log entries; GT-11's 197 instances), a package that declares a membership after its own code used the pair (its precompile recompiles, once), the image validation of an edge on a final cell.
- **Would stop here:** a package's precompile that loops (code and membership invalidating each other); images whose final-cell edges fail validation in a common load order.

**Stage 3: delete what no path reaches.** Only after stage 2's measurements hold.
- Julia: the shadow query and `jl_could_join` (13 uses in C, 2 in the compiler), `GuardedCallInfo` and the guarded split (9 uses in the compiler), the guard's cell fast path, `module_loaded` for memberships, the `closed_after_load` bit and `any_closed_after_load` (the system image's second pass in `base/sysimg.jl` stays, for Core and Base's own negatives).
- The library: `@closed_after_load`, `GuardedCallInfo` in the fully typed walk (4 uses), the mark `serves_no_member` if nothing reads it.
- The gates that pin guards and cells (`m2_*`) are rewritten as gates of the new rule or retired, each by its ID.
- The references, the decision log, the tensions' index and `intro/`, in the commit that removes the code.

**Order of the measurements and their rows.** One registry row per stage (the baseline is the build before stage 1): E-n for stage 1, a second for stage 2. Stage 3 changes no behaviour and has the gates as its check.

**What is not in it.** The table of a call's targets and its pointer (GT-7), a membership's world (GT-14), the closed build (compiler §7.6), keys.

## Risks

- Base's types joined to the library's traits (BaseTraits) are declared by the trait's owner at the library's load. Code in the system image that asked about those pairs before the library loads is invalidated at its load, once per session unless an image holds the result. This is GT-11's shape and has to be measured, not assumed.
- A package extension declaring a membership for its parent loads after code that used the pair (open issue 173). It recompiles that code; today it is late at a set closed after load and silent elsewhere.
