# Review: open issue 158 and the guarantee "a membership invalidates nothing" (2026-11-08)

The user (2026-11-08): "Send out a Fable agent to carefully think about open issue 158 and figure out if there are ways to minimize the impact of the guarantee."

Done by a `fable-critic` agent, the standing exception for a really high-impact choice ([CLAUDE.md](../../CLAUDE.md), "Gates do not stop the work"). Design analysis, not implementation. Nothing in a repository was changed but this file; nothing was committed.

**What was read:** [CLAUDE.md](../../CLAUDE.md); [open issues](../open-issues.md) 146 (closed), 157–160 and §1's "Flagged" entry; [compiler §4.1, §4.7–§4.11, §5, §6.8, §7, §9](../reference/compiler.md) and its Deviations (C-36, C-51, C-58, C-59); [facts §2.1, §10](../reference/facts.md); [traits §4.2, §5.5, §5.10, §5.11, §7.7, §10.1, §12.1](../reference/traits.md); [lowering §3](../reference/lowering.md); [the references' choices P-1 to P-32](../reference/README.md); [decisions §9](../record/decisions.md); [alternatives](../design/alternatives.md) (sealing; level 2's options; the unified build's options); [the unification review's M1](2026-11-08-unification-review.md) and [the trade-offs review](2026-11-06-unification-tradeoffs.md); [E-259's write-up](../../experiments/w83/u9/README.md), E-280 to E-282 in [the evidence](../design/evidence.md) and [the registry](../record/experiments.md); PE-19 and PE-21.

**Code read:** `julia-unified/Compiler/src/abstractinterpretation.jl` (`call_shadows`, the guarded call's result and effects), `Compiler/src/ssair/inlining.jl` (`ir_inline_unionsplit!`, `handle_call!`), `Compiler/src/typeutils.jl` (`negative_fold_blocked`), `src/gf.c` (`shadow_at`, `jl_call_shadows`, `invalidate_unguarded_callers`, `_typename_invalidate_backedges`, the membership walk's missing-edge branch), `src/subtype.c` (`jl_could_join`, `obviously_disjoint`), `src/datatype.c` (`jl_membership_cell`, `jl_declare_membership`), `base/loading.jl` (where extensions load); TraitWorld-unified `src/trait.jl` (`_trait_method`), `src/BaseTraits.jl`, `src/ownership.jl`; `forks-unified/CSV/src/tables.jl:250`.

**Probed** (scratch, not an experiment of the record; `julia-unified/usr/bin/julia` on the tree at 98fcbdfbba, TraitWorld-unified 0ac3364, `nice -n 19`, one thread, 8 s each, load 2.6–3.1 of 128; scripts and logs in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/a9f9efb8-5843-497f-a1f1-98fb0f1442ed/scratchpad/probe158*.{jl,log}`). The numbers below are for orientation. If any is cited, the main session should register the probe as an experiment and commit its script and log (CLAUDE.md: logs are committed, never only in a scratchpad).

## Summary

- The widened result is intrinsic to a guard whose slow branch is a dynamic call. It cannot be narrowed soundly while the call stays guarded (H2). It bites only where the shadowing method's declared result is undeclared or names the set's parameters (`T`, `V`, `Union{Nothing, Tuple{T, Any}}`); a closed declared result does not widen (verified). But every guarded call loses its effects and its exception type, widened or not (H3).
- Two separate levers remove guards without touching the guarantee's letter:
  - **(a) of the issue**, sharpened: a method at a set that can only raise at a member (a required operation's, once forwarding and `Dynamic{X}` have methods of their own) is no shadow. It removes every guard BaseTraits puts into plain code, since all of BaseTraits' operations are required (verified). It also closes H1 for forwarding.
  - **(d), new: finality by ownership.** `jl_could_join` says every concrete type could join every set (verified). Ownership ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)) and the loader say who can declare a membership and when: the trait's owner or the type's, while it loads. Once both have finished loading, the negative is final: no guard, and `isa`/`<:` fold. It covers the DataFrames case, which (a) does not. It subsumes (b). Its one narrowing: a membership declared after its declarers have loaded (`eval`, `Requires`, Revise, the REPL into a package's module) invalidates the code that folded its absence, as a late method definition does.
- **H1, a soundness gap in the build:** a caller compiled with a pruned `MethodError` arm before any method of its function is at a set is never re-guarded when such a method arrives (the insertion's intersection is exact, so the missing edge survives). A later membership then leaves the caller throwing where Julia answers (verified by probe). E-281's "invalidates nothing" rests partly on this. The fix is at the method's insertion, by `jl_could_join`, under every option.
- **(c)** narrows the guarantee itself and brings back E-252's invalidation at extensions' loads. It is the fallback if the count shows hot guards that (a) and (d) leave.
- Count first (W-124), with the counter recording what (a) and (d) would each remove.

## Findings, by severity

### H1. A pruned `MethodError` arm compiled before a method at a set exists is never re-guarded; a later membership leaves it stale — verified (probe D)

- The shape: `h(r) = g(r.x) + 1` with `r.x::Union{Vector{Int}, P}`, `g` with a method at `Vector{Int}` only. Inference prunes the `P` arm; the inliner emits `Core.throw_methoderror(g, x)` for it (seen in `code_typed`). Inference records a missing-method edge for `Tuple{typeof(g), P}`.
- Then `@trait Q begin g(q::Q)::Any = 7.5 end` inserts a method at a set. The invalidation log is empty. Two paths could have reached `h`, and neither does:
  - `invalidate_unguarded_callers` (`gf.c:4093`) walks the *specializations* of `g`'s other methods and asks `shadow_at`. The pruned arm has no specialization.
  - `_typename_invalidate_backedges` (`gf.c:3355`) intersects the missing edge with the new method's signature by `jl_type_intersection2`. By [compiler §4.7](../reference/compiler.md#47-three-layers) that intersection is exact: `P` is a concrete non-member, `obviously_disjoint` (`subtype.c:593`) says disjoint, the edge survives.
- Then `@implement Q P` (served by the default). The log is empty again, by design. `h`'s CodeInstance stays valid (`max_world` is `typemax`); its cached result is `Int64` while fresh inference of `g(::P)` gives `Float64`; `h(RP(P(…)))` throws `MethodError` where Julia gives `8.5`. With forwarding instead of a default (`@implement Q P by v`, probe C of the first run) the same: a `MethodError` from the stale arm.
- **Why it matters:** [facts §10](../reference/facts.md#10-memberships)'s argument for G1 is "no code relies on a non-membership". This code does: the pruned arm is a folded negative that no guard covers, because the shadow did not exist when the arm was compiled, and the shadow's arrival did not reach it. It is not memory-unsafe (the arm throws; it does not read a value at a wrong type). It is a wrong answer against Julia's, in the direction G1 forbids for plain code.
- **When it bites:** a trait whose operation is an existing function arrives after callers at a type that later joins were compiled: a package loaded after another, a session's code before a `using`, and every image (the sysimage included) for a function that gets a method at a set later. For BaseTraits' functions, probe E counts the population already in the loaded session: 76 missing-method edges at a concrete receiver (below, M1).
- **E-281 is affected:** it found BaseTraits' methods invalidate no instance at load. Part of that zero is this gap: the loaded images' 31 pruned arms at `Nothing` for `getindex`, `iterate` and `length` (probe E) were not re-guarded, so they are stale the day `Nothing` joins (nobody will declare that; the mechanism is still wrong).
- **The fix,** needed under every option below: at the insertion of a method at a set, a missing edge whose concrete argument could join the set (layer 3, `jl_could_join`, as `could_meet` already does for the other arguments) counts as intersecting, so the caller is invalidated and compiles again with its guard. This is Julia's own mechanism with the right relation; the membership itself still invalidates nothing. Its cost is paid once, at the method's insertion: for BaseTraits' load, the 76 edges of probe E and whatever the session compiled since. Under (a), a required operation's method need not invalidate them at all (it is no shadow), so BaseTraits' load stays at zero; only a default's or a user's method at a set pays.

### H2. The widened result is intrinsic to the guard, and it bites only where the shadow's declared result is open — verified (probes B, C4)

- Where the cell is closed in the task's world, no entry for (type, set) exists in that world or any earlier one (memberships only grow). The fast branch's static call to `m₀` is exactly what dispatch would select. That is all the fast branch may assume. It may not assume anything about the result of the slow branch, which is a dynamic call with no edge, in whatever world the task runs ([compiler §5.6](../reference/compiler.md#56-guards-and-cells); C-58 only makes the test coarser, not less sound).
- So the call's result must cover the slow branch's. The only bound is the shadowing method's declared result, flagged to cover every member ([§6.8](../reference/compiler.md#68-a-declared-result-on-method)). At a member not yet declared, the set's parameters are unknown, so a declared result that names them (`getindex::T`, `iterate::Union{Nothing, Tuple{T, Any}}`, `get::Union{V, D}`) is `Any` (`gf.c:2691`, verified). A closed declared result (`length::Int`, `haskey::Bool`, `firstindex::Int`, `size::Tuple{Int, Int}`) joins without widening: probe B gives `Any` for `r.c[j]` and `Int64` for `length(r.c)` at `r.c::Union{Nothing, Vector{Int}}` with BaseTraits loaded; C4 gives `Int64` for a user set's method declared `::Int`.
- The three sound ways to keep a narrow type are therefore: no slow branch (the negative is final: (b), (d)); no shadow (a); or no guard and invalidation instead (c). A fourth, asserting `m₀`'s result on the slow branch (call it (e)), is unsound against Julia's semantics: the same call in the same world would return a value from one caller and raise `TypeError` from another, depending on when each was compiled. Rejected.
- The issue's "how common" is right in shape: a `Union{Nothing, T}` that reaches an operation without narrowing. Probe B confirms the idiom boundary: a field read again widens (`r.c === nothing ? … : r.c[j]`), a local tested once does not (`c = r.c; c === nothing ? … : c[j]` gives `Int64`).

### H3. Every guarded call loses its effects and its exception type, widened or not — verified (probes C1, C4)

- `abstractinterpretation.jl:553–558`: a guarded call sets `exctype = Any` and `effects = Effects()`, the all-unknown effects. C4: a caller whose guarded result stays `Int64` has effects `(!c,!e,!n,!t,!s,!m,!u,!o,!r)` against the plain arm's `(!c,+e,!n,+t,+s,?m,+u,+o,+r)`.
- So a guarded `length(x)` cannot be removed when unused, hoisted, or folded, and its caller's effects degrade with it. This is a cost on top of H2, and on code the counter would list as "not widened".
- Sound and cheap: the join of `m₀`'s effects with the shadowing method's. For a required operation's method under (a) there is no guard. For a default, its body's effects at the set are inferable once; the library can record them with the declared result. Not a design change; a compiler improvement.

### H4. `jl_could_join` says every concrete type could join every set; ownership and the loader say who can declare, and when — verified in code; the consequence is reasoning

- `subtype.c:1915–1921`: for a concrete `S` with another typename than the set, the answer is `!never_member`. No owner, no module, no world enters. The shadow query (`shadow_at`), the negative-fold gate (`negative_fold_blocked`, `typeutils.jl:56`) and `could_meet` all rest on it.
- [Traits §12.1](../reference/traits.md#121-who-may-declare-a-membership) says who may declare `S <: X`: the trait's owner or the type's, their joint owners, and an extension each of whose triggers owns the trait or a type the declaration names. [Lowering §3](../reference/lowering.md#3-implement) says `@implement` runs at the top level of the declaring module. `base/loading.jl:2630, 2888` (verified): a package's extensions load inside its `require`, after its `__init__`.
- So for most pairs the set of possible declarers is known, finite, and finished: `Nothing` and `Indexable` can be joined only by TraitWorld, which has loaded. The compiler guards and refuses to fold against a membership that no code left to run can declare. That is the lever behind option (d) below. It is the "sealed sets" the user set aside on 2026-10-29 ("an optimisation for later; the spelling of this will be tricky"), with no spelling: it falls out of ownership.

### M1. Which shapes guard, and how common — the rule verified; the frequency estimated

From `shadow_at` (`gf.c:2607`, verified), a call at a concrete `S` is guarded when all hold:
- some method `mz` of the function types that argument by a set (the set, a union's arm, an intersection, a parameter, a varargs tail);
- `S` is concrete, not a kind, not a member, and could join (today: always);
- `m₀` is none (a `MethodError` arm), or takes the argument as `Any`, or at a set; a method matched through `S`'s own supertypes is no shadow;
- `mz`'s other arguments could meet the call's.

The shapes in plain code, with BaseTraits loaded:
- **The `MethodError` arm:** `Union{Nothing, T}`, `Union{Missing, T}`, `Union{Symbol, T}`, a `Vector{Union{Nothing, T}}` element, a `Dict` value, at `getindex`, `iterate`, `length`, `haskey`, `get`, `size`, `firstindex`, `setindex!`, `push!`, `resize!`. Widens to `Any` at the operations with an open result (`getindex`, `iterate`, `get`); loses effects at all. Probe E counts the population compiled before the library loaded, in the sysimage, the compiler and TraitWorld's image: 3,160 missing-method edges in all, 77 at BaseTraits' functions, 76 at a concrete receiver: `getindex` 62 (`Nothing` 23, `Compiler.IRCode` 17, `Compiler.IncrementalCompact` 17, `SimpleVector` 5), `iterate` 11 (`Nothing` 7), `resize!` 2, `length` 1 (`Nothing`). These are H1's population, not guards; they show the shape's rate in Base's own code: about one in forty missing edges, tens per image. Code compiled after the load at the same rate carries that many guards: tens per session, not thousands. An estimate, not a measurement; CSV-style code with `Union{Nothing, T}` fields runs higher.
- **The catch-all:** `f(::Any)` beside a method at a set (`is_nonlinear_algorithm`, E-259's case). No function of BaseTraits has one (`length`, `getindex`, `iterate`, `size`, `haskey`, `get`, `push!`, `resize!`, `firstindex`, `setindex!` have no `::Any` method in Base; reasoning from Base's methods, not counted). So this shape arises only from a user's trait.
- **A less specific set** (`m₀` at a superset): trait code, not plain code.
- **A negative test:** `isa(x, X)`, `typeof(x) <: X`, `x::X` at a concrete type (DataFrames' case). Not a guard; an unfolded `Bool` and a run-time query (M3).

What (a) removes: every guard whose shadow is a required operation's method, which is every guard BaseTraits puts into plain code (all its operations are required, verified in `BaseTraits.jl`). What (d) removes: every guard and refused fold at a pair whose declarers have loaded, including DataFrames' `<:` test and any user trait's default or catch-all at a type of a loaded package. What neither removes: a guard at a type or trait of `Main`, or of the package being precompiled, against a default or a user method at a set.

### M2. The shadow query is per argument; a membership that makes two methods ambiguous is not guarded — reasoning, not probed

- `shadow_at` returns "no shadow" when `m₀` types the argument by a closed type other than `Any` (`gf.c:2629`). [Compiler §5.2](../reference/compiler.md#52-specificity) orders a closed type above a set *at each argument*; `type_morespecific` needs every argument.
- So with `m₀ = f(::Vector, ::Any)` and `mz = f(::X, ::Int)`, a membership `Vector <: X` makes the pair ambiguous at `f(Vector, Int)`: fresh dispatch raises, the compiled caller keeps calling `m₀`. [§5.4](../reference/compiler.md#54-the-ambiguity-report-at-a-membership)'s report covers pairs of methods at two sets only.
- Small fix: `shadow_at` drops the early return when `mz` is narrower than `m₀` at any other argument. Not a cost question; a G1 question. Listed here because it is the same code.

### M3. An unfolded negative `isa` or `<:` at a concrete type is a run-time subtype query — reasoning; codegen not read

- `negative_fold_blocked` keeps the test as `Bool`. Codegen has no branch for open sets (`grep open_set codegen.cpp` is empty), so the test runs `jl_isa`/`jl_subtype` with the entries' walk and the reachability memo. Tens of nanoseconds, where a guard's cell read is one load.
- Sound and cheap: lower `isa(x::S, X)` with `S` concrete and the answer unfolded to the cell's read for `(S, X)`, with the task's world as the guard compares it. The same cell the guard uses. Independent of the options; it makes DataFrames' test cheap where (d) does not fold it (a type of `Main`).

### M4. `Keyed`'s untyped key widens the shadow population — verified in `trait.jl` and `BaseTraits.jl`

- `_trait_method` drops a further argument's type unless it binds an input or a `where` variable (lowering §2). `getindex(d::Keyed, k::K)` becomes `getindex(d::Keyed{K, V}, k)`. So `getindex(::Nothing, ::Int)` has two shadows, `Indexable`'s and `Keyed`'s, and `getindex(::S, ::Anything)` at any concrete `S` has `Keyed`'s. Under (a) moot. Under the current rule, every `getindex` call at a non-member with no method is guarded twice.

### L1. The probes are not in the record

- The numbers above live in a scratchpad. Nothing in this review may be copied into the evidence without an experiment row and a committed log.

## What the guard's branches may assume: the soundness answer in one place

- **Fast branch:** the cell is closed in the task's world, so no membership for (type, set) exists in that world. The static call to `m₀` is dispatch's answer. Precise result, `m₀`'s effects.
- **Slow branch:** a dynamic call, dispatched in the task's world, no edge. Its result is bounded only by a declared result that covers every member. Its effects are unknown.
- **The join is forced** by the slow branch's existence. Removing the widening means removing the slow branch: the negative is final (no guard), or the shadow is not one, or the code is invalidated instead of guarded.
- **Worlds:** C-58 (the guard tests closedness, not `min_world ≤ world`) sends a task in an older world to the slow branch once the cell opens; that branch gives the older world's answer. Sound, less precise, irrelevant to cost.

## The options, ranked

| # | Option | Keeps the guarantee's letter | Removes | Leaves | Cost |
|---|---|---|---|---|---|
| 1 | **(a) sharpened:** a method at a set that can only raise at a member is no shadow; forwarding and `Dynamic{X}` get methods of their own | yes | every BaseTraits guard in plain code; H1 for forwarding; M4 | guards at defaults and user methods at sets | P-1 revised for forwarding; one method per operation at each forwarding member and at `Dynamic` per trait; a flag on the trait's method |
| 2 | **(d) finality by ownership:** a negative at a pair whose declarers have all loaded is final | the letter for memberships declared at load; one narrowing, stated below | the rest in package code: defaults, catch-alls, `isa`/`<:` tests (DataFrames' case) | pairs with a `Main` type or trait, the package being precompiled, a joint owner not loaded | a closed bit per module; declarers per `TypeName` from the library's `owner`; a final-negative edge kind on the cell; the trigger rule read with each standard library as its own owner |
| 3 | **The H1 fix:** insertion of a method at a set invalidates missing edges by `jl_could_join` | yes | a G1 gap | — | invalidation at the method's insertion, as Julia's; zero for required operations under (a) |
| 4 | **C-36:** lowering records `f(…)::RT` | yes | the `Any` at a user method at a set with a closed declared result | the guard, the run-time test, the effects | small |
| 5 | **H3's effects join** and **M3's lowering of `isa` to the cell** | yes | the effects loss; the run-time subtype query | — | compiler work, small |
| 6 | **(b) negative memberships** | yes | one pair per declaration | everything else | by hand; subsumed by (d) |
| 7 | **(c) a membership invalidates the code that pruned an arm** | no | all guards at that shape | guards at catch-alls (or those too, then (c) is C-18) | E-252's invalidation at extensions' loads; images' pruned arms invalidated at each load of such a membership |
| 8 | **(e) assert `m₀`'s result on the slow branch** | yes | the widening | — | unsound against Julia's semantics (H2); rejected |

### (a), sharpened: a method at a set that can only raise at a member is no shadow

- **The claim:** after a membership of `S` in `X` is accepted, the trait's method for a required operation is never the method selected at `S` with the declared argument types, unless it raises.
  - The check ([traits §5.10](../reference/traits.md#510-checks)) accepts a member only with a serving method of its own, one inherited through its chain (more specific than the set's by [§5.2](../reference/compiler.md#52-specificity)), or forwarding. Under (a), forwarding defines the operations' methods at the member (or the family's pattern), and `Dynamic{Z} where {Z <: X{…}}` gets one per operation when the trait is declared. Both are method definitions, which invalidate as in Julia, through the missing edges a pruned arm records (a method at the member's own type intersects them).
  - What remains of the trait's method's body is `throw(MethodError(…))` (`_trait_method`, verified: that is its `NoForward` branch today). A pruned `MethodError` arm throws the same error without it. A failed first-use member ([§5.10](../reference/traits.md#510-checks): it stays a member, every use raises `ImplementError`) raises either way.
  - So the call's result and its effects at `S` are unchanged by the membership alone. No guard is needed. One more "No guard arises" line in [§5.6](../reference/compiler.md#56-guards-and-cells), keyed on a flag the library sets on the method.
- **Soundness depends on three things being true:** the completeness check is enforced for every membership (it is: a declaration, or a first use); forwarding never reaches the trait's method (under (a) it cannot); `Dynamic{X}` never reaches it (under (a) it cannot; `jl_could_join(S, Dynamic{…})` is already 0 for any other typename, `subtype.c:1915`, verified).
- **What it costs:**
  - P-1 for forwarding. Every caller still reaches the forwarding member's methods; they are ordinary methods at the member. With keys (Optional, P-29) the member's method becomes a trampoline into the key's code; no sharing is lost.
  - A forwarding `@implement X S by f` is now one method insertion per operation. Their invalidation is Julia's, and for a new type `S` it reaches nothing. For a foreign type (`@implement Indexable Nothing by …`, if anyone did it) it reaches every pruned `Nothing` arm, which is right: that is the one moment the answer changes.
  - `Dynamic`'s methods name a set inside a parameter, so they go to the typemap's linear list ([§5.1](../reference/compiler.md#51-the-method-table); PE-21) and into the shadow query's scan of every call of that function. Two more entries at `getindex` (`Indexable`'s and `Keyed`'s). Better: index them under `Dynamic`'s own typename; a method whose receiver's head is a closed type needs no linear slot.
  - The override rule ([§5.11](../reference/traits.md#511-overrides-and-redeclaration)) extends to a forwarding member's methods, as the library already records overrides per operation.
- **What it does not cover:** defaults, user methods at sets, negative tests. DataFrames' case stays.

### (d), new: finality by ownership

- **The rule.** A negative `S ∉ X` is final when every module that may declare `S <: X` has finished loading. The declarers are, by [traits §12.1](../reference/traits.md#121-who-may-declare-a-membership): the owner of `X`, the owner of `S`, their joint owners, and their extensions (an extension may declare only pairs that name a trigger's type or trait, so an extension not yet loaded can declare nothing about types that exist). "Finished loading": for a package, `require` returned, its `__init__` and the extensions its load triggered included (`loading.jl:2630, 2888`); for a module under `Main`, its `end`; `Main` never; the package being precompiled not until its session ends. Core and Base at startup. `Callable` excluded: its memberships are methods, not declarations, and [§7.4](../reference/compiler.md#74-callables-call) already edges them.
- **The narrowing, stated for the user.** A membership declared *after* its declarers finished loading (`eval` into the module, a `Requires` block, Revise, the REPL evaluating into a package's module) invalidates the code that folded its absence, as a method defined then invalidates its callers. "A membership invalidates nothing" becomes "a membership declared while its declarer loads invalidates nothing". Every `@implement` at a package's top level, in its `__init__` or in its extensions keeps the full guarantee. The ecosystem builds around that; nothing it can write at load is affected.
- **Images.** The fold is recorded as a *final negative* on the (type, set) cell, a kind beside the membership cell and the positive membership ([§3.1](../reference/compiler.md#31-the-record)). An image's final negative is valid at load iff the cell is unopened in the session; the declarers are loaded by then, since they are the image's dependencies. An environment that gained an extension declaring the pair (E-252's R12) opens the cell at the extension's load, so the image's folded code is refused at validation and compiled again: a load-time cost confined to that code, consistent with [facts §12](../reference/facts.md#12-package-images); today that code would carry a guard and load. A late declaration in a session invalidates the final-negative edges through the same path a redeclaration uses ([§4.3](../reference/compiler.md#43-worlds)).
- **Prerequisites.**
  - The extension-trigger test reads each standard library as the owner of its own types. Otherwise, with Julia one owner, an extension of the trait's owner triggered by a standard library loaded later (`TraitWorldSparseArraysExt`) may declare `Nothing <: Indexable` after TraitWorld closed. This is open issue 19's direction, needed here for one rule only.
  - Memberships are declared by code that runs at load, or the declaration counts as late. [Lowering §3](../reference/lowering.md#3-implement) already says the top level.
  - A joint owner named but not loaded keeps the pair open until it loads (SciML's split packages pay guards for DiffEqBase's traits until OrdinaryDiffEqCore loads; acceptable).
- **Mechanism, at the design level.** A closed bit on `Module`, set by `require` and the module-end hook; on each `TypeName`, its declarer modules, written by the library from `owner`, `@joint_owners` and the extension map at the module-end hook (the library's `owner` already resolves extensions to parents and standard libraries to Julia, `ownership.jl:78`); `jl_could_join(S, X)` returns 0 when every declarer of `S`'s typename and `X`'s is closed and none is `Main`; the cell gets a final flag and a backedge list; `jl_declare_membership` on a final cell invalidates the list. All three callers of `jl_could_join` benefit at once: the shadow query, the negative-fold gate, `could_meet`.
- **What it gives.** The CSV case (both declarers closed, even without (a)); the DataFrames case (`DataFrameColumns ∉ TableSource` folds, so the arm is pruned and `@inferred` passes); every user trait's default and catch-all at types of loaded packages; the `isa` and `<:` tests. Code of `Main` keeps its guards: development at the REPL loses nothing it has today.
- **What it does not give.** Guards in a package's own image for its own types against loaded traits' defaults (the module is open while precompiled); with (a) these are few.
- **Why it is principled.** It states a fact about the program, not a performance setting: a membership nobody left to run can declare does not exist. Rust's orphan rule decides conformance by the same reasoning: only the trait's crate or the type's crate may write the `impl`, so a missing `impl` is final (from memory, not fetched; Swift allows retroactive conformance from any module, so it is no precedent here). Here the "crate" is the loaded package, and the decision happens when the last declarer has loaded.

### The H1 fix

- At `jl_method_table_insert` of a method whose signature names a set, `_typename_invalidate_backedges` treats a missing edge as intersecting when the edge's concrete argument could join the set at that position (`could_meet`'s relation). The invalidated caller compiles again with the guard, or, under (d), with the fold where the pair is final.
- Under (a), a required operation's method is no shadow, so it need not invalidate anything: BaseTraits' load keeps E-281's zero. A default or a user's method at a set pays for the missing edges at its function, as any new method pays in Julia.

### (b), negative memberships

- A declaration per (type, set), by the trait's owner or the type's. BaseTraits would declare `Nothing` and `Missing` at each container trait. It leaves every other type guarded and every other owner declaring by hand. (d) gives the same answer for every pair at once, without a declaration, and with the same ownership rule deciding who could have said otherwise. Not taken.

### (c), a membership invalidates the code that pruned an arm

- It is the stopgap C-18 narrowed to missing edges. Implementable: Julia invalidates sysimage code through missing edges today.
- It narrows the guarantee itself, for every membership: an `@implement` in a package extension invalidates the pruned arms of every image loaded before it (E-252's R6–R8, R12), at every load. That is the cost the user committed against on 2026-11-06.
- Its place: the fallback if the counter finds hot guards in plain code that (a) and (d) leave, which can only be defaults and catch-alls at `Main`'s or the precompiling package's types.

### (e), assert instead of widen

- Rejected (H2): the call's behaviour would depend on when its caller was compiled.

### Interactions

- **Defaults** (P-1 for defaults is untouched): a default is a shadow. (d) makes it guard-free at loaded packages' types; (a) does not.
- **Forwarding:** (a) revises P-1; (d) is indifferent.
- **`Dynamic{X}`:** under (a) its methods are the library's, per trait; under (d) `Dynamic`'s declarer is the library, loaded.
- **Packages loaded later:** a new trait's methods arrive by method insertion, with the H1 fix reaching pruned arms; a new package's types are open while it loads and final after; a new extension declares at its load, before its parent or trigger closes.
- **Compiling ahead and images ([§9](../reference/compiler.md#9-images-and-the-machine-code-cache)):** (a) adds methods, nothing else; (d) adds one record kind and one validation rule (the cell unopened); the machine-code cache across sessions names a final negative by (member, set, declarers), all stable identities.
- **Keys (P-29):** a forwarding member's method under (a) is a trampoline into the key's code; the receiver recorded on the membership stays the field.
- **Strict mode:** a late membership that invalidates folded code is a stakeholder's change, as a late method is; strict mode has nothing new to refuse.

## What to measure: the counter (W-124)

**Record, at inference, under a flag** (`Compiler`'s `call_shadows` and `negative_fold_blocked`; no behaviour change):
- per guarded call: the frame's method (module, file, line), the frame's policy (plain, facts), the function, the member type, the sets, `m₀`'s kind (none, `f(::Any)`, a set method), the shadowing method, the result before and after the join (equal, a wider union, `Any`), and two predicates computed and recorded, not acted on: "the shadow is a required operation's method" ((a) would remove it) and "every declarer of the pair is closed and none is `Main`" ((d) would remove it; an approximation by the typenames' root modules is enough);
- per refused negative fold: the frame, the site's tfunc, the two types, the same two predicates;
- per method inserted at a set: the missing edges at its function whose concrete argument could join (H1's population; what the fix would invalidate).

**Record, at run time, under the same flag:** a counter per guarded site, incremented on the fast branch, so hot sites are found by hits, not by guessing loops.

**Sessions:** the goal's task (f) (E-288/E-289's harness); the forks' session; CSV's and DataFrames' upstream suites (the counter must list the issue's two sites); TraitReport (t); setting D; NetworkDynamics' workload; Base's `arrayops` and `dict` (E-282's); and one control of plain code only: upstream CSV reading the goal's file with TraitWorld loaded and no trait code of the ports.

**Report per session:** guarded sites, how many widen to `Any`, how many lose effects only, how many are in plain code; the top 20 by hits; refused folds by site; H1's population; and for each, whether (a) or (d) removes it. Numbers cite the build, the setting, the load order and the runs, as the rule for a number asks.

**Criterion:** if (a) and (d) together leave a guarded site in plain code in the top 20 by hits with a widened result, (c) is reconsidered for that shape alone.

## Recommendation

1. **Fix H1 now,** in the compiler stage's next slice: missing edges by `jl_could_join` at the insertion of a method at a set, with a gate (the probe's part D as the case). It is a G1 gap, not a cost question, and it changes E-281's reading.
2. **Adopt (a), sharpened** as the issue proposes, with the flag on the trait's method ("raises at a member") as the rule's carrier, forwarding and `Dynamic{X}` as methods at the member, and `Dynamic`'s methods indexed under their own typename. It keeps the guarantee's letter, needs no declaration, and removes every guard BaseTraits puts into plain code. The issue's recommendation stands; its reasoning is confirmed.
3. **Propose (d) to the user as the principled finality,** with the one narrowing stated verbatim: "a membership declared while its declarer loads invalidates nothing; one declared later invalidates the code that folded its absence, as a late method definition does". It subsumes (b), needs no spelling, and covers the DataFrames case and every default and catch-all at loaded packages' types. Record it as an open-issue proposal and, if adopted, in facts §10, compiler §4.7, §4.8, §5.6, traits §12.1, with open issue 19's rule for the trigger test.
4. **Build C-36** regardless: user methods at sets with a closed declared result should not widen at `Main`'s types either.
5. **Join effects and lower unfolded `isa` to the cell** (H3, M3): small compiler work, no design change.
6. **Count first (W-124)** as the plan says, with the predicates above, so the decision on (d) and the fallback (c) rest on the ports' sessions.
7. **Do not take (c)** unless the count forces it for a named shape.

## Not settled

- The frequency of guards in the ports' sessions and in plain code with the library loaded: only probe E's population of pruned arms in the loaded images (76 at BaseTraits' functions) is measured; the rest is estimated at the same rate. W-124's counter settles it.
- Whether the H1 fix's invalidation at the insertion of a *default* on a Base function is affordable in a real session; BaseTraits has no default, so no session measures it yet.
- M2's multi-argument ambiguity: reasoned from `shadow_at` and `type_morespecific_`'s per-argument rule; not probed.
- M3: codegen was not read; the claim that an unfolded `isa` runs a subtype query is inferred from the absence of an open-set branch in `codegen.cpp`.
- (d)'s exact wording of "finished loading" for a package being precompiled, and whether a `@compile_workload` placed before a package's last `@implement` should be reported.
- Whether the probes' numbers enter the record: they need an experiment row and committed scripts and logs; the scratchpad paths are at the top.
