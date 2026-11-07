# 2026-11-06: the unified build, stage 0

On the shared RHEL 9 host (128 cores). The synthesis plan of 2026-11-05 ([`../writeup/plans/2026-11-05-unification-synthesis.md`](../writeup/plans/2026-11-05-unification-synthesis.md)) adopted; stage 0 (W-97) begun.

## The user's words

On being asked what is needed to start implementing the plan, the user answered (2026-11-06):

> As long as load is this low, its fine to use more of the machine: You can use half the machine for compiles while it is mostly empty. Once it fills up to at least half load you restrict to four cores and sequential work. (record this as a rule) Decision 1: agreed. Decision 2, agreed, decision 3. agreed, decision 4, agreed. decision 5 agreed. decision 6. agreed decision 7 we stay on 13.2 Decision 8 agreed decision 9 agreed. 10. agreed, though the design and implementation should be aware that a machine code cache is the eventual goal. 11. agreed. 12. agreed 13 confirmed as your call. Agreed on W-S0a. Get started (and no subagents on this machien please)

And, while the work ran:

> One clarification to the rule: It is okay to spike up to half machine use. Sustained use should be considerably lower.

"Agreed on W-S0a" answers the proposal to count, as the slot's estimate, "facts callers whose only edges to invalidated callees are result edges, where the callee's result did not change", on more than the forks' session: E-238 found that none of the 1,884 MethodInstances invalidated in the forks' session were compiled again there, so a count of recompilations alone would say nothing.

## Done

- **The rule for cores by load** in `CLAUDE.md`, the record's standing constraints, `setup.md` and the workflow note; `tools-local/build.sh` applies it to a Julia build (wide at the start below half load, narrowed to `-j4` when the others' load reaches half, paused above 110; stage times and sampled peak RSS in the log). "Sustained use considerably lower" read as at most 16 cores in all (mine). No subagents on the shared host, in the same places.
- **The trees:** `julia-unified/` (branch `unified` at c3f0b4bc11, from `origin/oc-build`) and `julia-vanilla/` (detached at `45b6d15e34`), each with `julia-1.13`'s source cache copied in. `unified` built from 11:47 (load 5–7; at `-j4`, see below).
- **The decisions** 1–13 in the decision log §5, with the user's words.
- **The references' Planned sections:** compiler §7 rewritten as the unified build (§7.2 memberships, §7.3 one dispatch, §7.4 guards and cells, §7.5 keys, attributes and the check, §7.6 compiling by facts per method, §7.7 the code slot (Optional), §7.8 images and the machine-code cache), C-18 (the stopgap); facts §6.5 and a scope note in §2.2; traits §3.6, §6.7, §12, §14 and the status index; lowering §17's table of what removes each encoding.
- **Open issue 140** (mine, found while writing compiler §7.2): under explicit memberships, generic implementations and families over abstract types have no stated way to get their entries before the first call; three proposals.
- **The work items** W-97 to W-104 (one per stage); **the registry rows** E-260 (the C7 count re-run), E-261 (W-S0a), E-262 (the builds, the gates and Base's suites).
- **Alternatives** not taken, in `design/alternatives.md` ("The unified build: options not taken"); the evidence plan's order and the exploration's D1–D9 marked as replaced by the synthesis plan; the review marked acted on.
- **The build of `unified`** (11:47–12:01): `tools-local/build.sh` ran at `-j4`, not `-j64`: `nproc` honours `OMP_NUM_THREADS=1` from `env.sh`. And I edited the script while it ran, which garbled its last lines. Both fixed (`getconf`, and the script runs from a private copy). The binary runs (`1.13.2 c3f0b4bc11`).
- **The vanilla control** started 12:01:54 at `-j64` (load 8).
- **E-262 (2):** the 22 gates pass on `unified`.
- **The audit** ([`../writeup/reviews/2026-11-06-oc-build-audit.md`](../writeup/reviews/2026-11-06-oc-build-audit.md)), in the main session. Probes on the built branch show two high defects. A1: `@implement S X` makes `S isa X` true and calls a bounded method with the type object. A2: `Dynamic{X} <: X` holds, but a call with one reaches the fallback. Six medium: patterns beyond eight variables match nothing; the per-thread query world; the epoch and its cap of 32,767 sets; the single-path cycle check; the ambiguity report's arity; the chain composition. Recorded as compiler C-19 to C-25, and in W-98 and W-99.
- **E-262 done.** The control built in 790 s at `-j64`. Base's four test files pass on both builds; `unified` is 2–6 % slower, one run each; `detect_ambiguities(Base)` is 0 on both.
- **The environments** for E-260 and E-261 are being instantiated in the workspace depot (they never were on this host): `env_tables`, the forks', TDE's, Makie's, `TraitDifferentialEquations/scripts/env` and `TraitMakie/scripts/env` done by 12:16.

## The user reverses decision 4

> I have reconsidered explicit membership. It must be transitive. So A <: B <: C has to imply A <: C. I have never seen a type system that doesn't have that. We need to explicitly think about invariance, covariance and contravariance with respect to parameters. Does U <: V imply T{U} <: T{V} I lean towards: yes if all parameters satisfy it. This decision might simplify other aspects of the design, too.

- Transitivity recorded as in force: the decision log (the explicit row moved to the superseded section), compiler §7.2, traits §3.6 and §14, alternatives, C-22 restated, the audit's addendum (A8 reverses: the attempt's composition is kept and extended to `<:` and to supertype chains).
- Open issue 140 narrowed by it: generic implementations and families over abstract types become memberships of a set or an abstract type in a set. What remains is a family whose parameter an equation defines that is not a pattern.
- Variance written up as open issue 141. My proposal refines the user's lean: each parameter's variance is derived from the contract. Covariant where the contract only produces the parameter (where "yes" is sound); contravariant where it only consumes it (`Callable`'s arguments); invariant otherwise. The diagonal rule is the point to settle.
- Probe P7: the branch does not read entries along a member's supertype chain (`PS7 <: PAbs7`, `PAbs7` a member of `PX7`, but `!(PS7 <: PX7)`).
- **E-260 and E-261 done** (the environments installed 12:08–12:21, no errors). E-260 reproduces the attempt's C7 count exactly: decision 2 stands. E-261: the slot keeps 341 of 1,233 and 1,622 of 6,430 invalidated CodeInstances, and 67 of 120 and 91 of 100 facts callers of invalidated plain code. By decision 3's rule the slot is built (W-101); compiler §7.7 Planned; the decision log row marked mine.
- **W-97 done.** The build discipline is in `00-environment-and-workflow.md`. Nothing pushed: the commits of the design and experiments repositories are local, waiting for the user's word.

## Pushing, and the variance of parameters

> You may push at will. Let me get this right: Standard AbstractTypes in Julia are invariant, but there is a separate spelling AbstractArray{<:T} (that looks a lot like a trait bound) that makes it covariant? If we unify Traits and AbstractTypes, then we should follow that rule. Trait{U} <: Trait{<:T} if U <: T. That way we can also spell a callable with arbitrary return type Callable{T, <:Any}.

- Pushing at will recorded in `CLAUDE.md` and the standing constraints.
- Open issue 141 closed: parameters invariant, `X{<:T}` and `X{>:T}` where a type is used; the diagonal-rule question disappears (a parameter of a trait stays an invariant position). Compiler §7.2, traits §3.4, §5.8 (`Callable{A, <:Any}`), §14; alternatives.
- Probe P8: the branch's fallback answers `S <: X{<:Real}` false (A15, high, C-26). The fix is also the simplest reading of the decision: an entry is a supertype within subtyping's walk.

## Stage 1 begun; the disk quota; the move

The user (12:41):

> Go ahead with Stage 1. Continue with the next stages unless something comes up that really requires my attention. Remember: Principled solutions. Simplify rather than add wherever possible.

- **12:52–13:00, W-98 begun in `julia-unified`, uncommitted:**
  - `subtype.c`: the branch's membership section (about 720 lines) replaced by the in-walk rule. An entry is one more supertype inside subtyping's walk: its pattern's variables join the walk as existential variables, and the choice among a type's entries is made as a union's is. It covers transitivity, `X{<:T}`, `Type{S}` entries, `jl_isa`, intersection, and C7's order between two sets (`jl_typename_reaches`). `jl_membership_world_range` is the world range for dispatch. Removed: `jl_membership_match_range`, `jl_membership_match_sig`, `jl_lookup_membership` and the chain lookup.
  - `builtins.c`: the `_setsuper!` hook dropped (a declared supertype is a supertype). A set's supertype must be `Any` or a set. Each builtin's type never a member (A9).
  - `jl_exported_funcs.inc`: `jl_lookup_membership` dropped.
- **About 13:00 the home filesystem's quota ran out.** `datatype.c`, `jltypes.c`, `julia.h` and `julia_internal.h` in `julia-unified/src` were emptied, cause not established. The session restored them from `HEAD`. That lost its applied edit of `julia_internal.h` (12:59): the epoch's declaration removed, the removed functions' declarations replaced by `jl_typename_reaches` and the others. The edit is in the session's transcript. Its retry left an empty `src/julia_internal.h.tmp-edit`; the header itself is intact. The edit of `jltypes.c` (A9 for `jl_builtin_type`) never applied.
- **Still to do for W-98, so the tree does not build yet:**
  - the header edit, redone;
  - `jltypes.c`;
  - `datatype.c`: a full cycle check through `jl_typename_reaches`, a set open from its declaration, the epoch removed;
  - `gf.c` and `typemap.c`, which still call the removed `jl_membership_match_range` and `jl_membership_match_sig`;
  - `datatype.c` and `jl_internal_funcs.inc`, which still name `jl_lookup_membership`;
  - then the rest of W-98's list.
  
  The last build of `unified` is of c3f0b4bc11 (11:48–12:01).
- **The workspace moved** from `/home/hellmann/julia-trait-bound` to `/p/projects/coen/julia-trait-bound`: the user's `mv`, then `rsync --remove-source-files`, done by 13:35. The checks and repairs, in a later session:
  - Every repository's objects pass `git fsck`.
  - Every tracked file matches its index; the only changes are the WIP above and untracked logs.
  - The 16 worktrees' links repaired with `git worktree repair`.
  - The three Julia trees' 198 absolute symlinks into the old path re-pointed, with their `usr/manifest` records; the three builds load stdlibs again.
  - `base/build_h.jl`'s `SOURCEDIR` still names the old path until the next `make` regenerates it, which rebuilds the system image.
  - The depot's packages precompile once more.

## The references before the build: "traits are abstract types"

After the move, the user (2026-11-06):

> We were working on unification when we were interrupted. An earlier session recorded the state of the interrupted work. Before we resume the unification push, there is an important point though: Unification changes and simplifies the referecne design substantially. Unification states "Traits are AbstractTypes" From this it follows that Traits can occur everywhere AbstractTypes can, and that they are parametrized the way AbstractTypes are parametrized, including Trait{<:T} and the like. This explicitly contradicts a number of things that are currently in the reference design. It also should eliminate a lot of the reference design. So before we continue implementation work on the unified perspective, we need to actually fix and simplify the reference. Carefully go through the four reference documents and work out the implications of unification.

And, while the analysis was written:

> If the ports have to be substantially changed that is fine. They were built under old assumptions and should be considred informative rather than limitative.

- The four references read in full at f19f5ac (traits 1,651 lines, compiler 1,020, facts 638, lowering 835), with the decision log's §5, open issues 135–141, the exploration's unified model (§3–§5) and the evidence plan's three levels.
- **The analysis:** [`../writeup/plans/2026-11-06-traits-are-abstract-types.md`](../writeup/plans/2026-11-06-traits-are-abstract-types.md), a proposal (W-105):
  - F1–F18, what follows with no decision. F1 reverses decision 41; F8 reverses "defaults and forwarding serve trait code only".
  - 27 statements in force that the premise contradicts, compiler §7's "a trait's name in a field means `Kept{X}`" among them.
  - What goes.
  - Eight choices with recommendations (Q1–Q8), three small ones, eleven gaps.
  - Every section's disposition.
- No port or fork declares a field mapping (grep, for Q7).
- W-98 waits for W-105: Q4, Q5, Q8 and F12 change what stage 1 builds. The uncommitted stage-1 work in `julia-unified` is left as it was.

## The draft reference

The user (2026-11-06), after the analysis:

> SO we should have a new reference that describes the unified design as a greenfield fresh document that does not refer to the previous design and changes. This should be a new reference folder with four new documents. Then I would like to understand the changes this implies for Dynamic and for error messages. Specifically I think its valuable if we can have Dynamic or not as a trait and library default, that the user can override. Is that still feasible in the new design? Also do we keep the keys optimization where two trait bound methods for different types that have the same key can reuse code?

And, while the draft was written:

> I am looking at some other questions right now: Q7: (a), Q2: (a), Q5 (a) spelled All{X,Y,Z,...}, Also I think Callable deserves special handling. Q8 (c) declared membership stays as a design goal. q-a,b,c your call. For the Gaps: Make decisions, think about existing languages, only where no principled option exists, come back to me.

- **The draft:** [`../writeup/reference-unified/`](../writeup/reference-unified/README.md), with a README and `traits.md`, `facts.md`, `compiler.md`, `lowering.md`, written from the ground up. Its README lists every choice (P-1 to P-19) with who made it.
- **The attribute, as the user asked:** for each trait argument at each call, strongest first:
  - a cast written at the call;
  - what the value carries (code per key or compiled once passes its argument on so; a `Dynamic{X}`; a struct parameter's record);
  - the library's default (`@nospecialize`/`@specialize` at the argument, then the module's option);
  - the trait's default (`@default_dynamic`/`@default_compiled`);
  - otherwise `Compiled`.

  The mechanism: up to two compilation signatures per method and argument tuple, and attribute bits passed with a call.
- **Keys stay:** a method fully bounded at an argument is compiled per key; members with equal keys share it.
- **Errors:** `TraitBoundError` and `TraitArgumentError` have no cases left: Julia's `MethodError` (with the library's hints) and `TypeError` take them. `ImplementError`, `OwnershipError`, `TraitUseError` and `PirateError` stay ([traits §11](../writeup/reference-unified/traits.md#11-checks-and-errors)).
- **The gaps decided, mine,** with Rust's and Swift's precedents (decision log §9). Each is marked mine for the user to confirm:
  - defaults reached by every caller;
  - casts at the call;
  - `Dynamic{X}` as Rust's `dyn`/Swift's `any`;
  - the guarded call from per-key code;
  - the contract on the `TypeName`;
  - candidates from the runtime's index;
  - a family states its instance (open issue 140);
  - `eltype(t)` in the contract (open issue 137);
  - the member hook;
  - `TraitKey`;
  - `like` per type;
  - a trait counting as concrete.
- **Two items come back to the user** (open issue 142):
  - `Callable`'s form;
  - the attribute's last step (`Compiled`, Julia's rule, or what the caller knows).
- Nothing built; W-98 still waits.

## Callable by signature; the fallback by scope; a review of the prototypes

The user (2026-11-06):

> I think we need dispatch to pick by signature. falling back to first seen is better for trait modules, falling back to compiled is better for plain Julia. Send out a fable reviewer that checks what the new unified reference would imply for the prototypes we built.

- **`Callable`:** memberships derived from the method table. `F <: Callable{A, S}` where a call at `A` selects a method whose plain-inferred result is `S`; `A` is an input, `S` an associated type. A derived membership follows the method table: it is the one kind that can end, and only by a definition of the member's methods (a stakeholder's or a pirate's). Code relying on one holds an edge to it; negatives are guarded as for any membership. The form is mine (traits §9, compiler §7.4, facts §10 of the draft).
- **The fallback:** a module option `first_seen`, on in `@trait_module`; `Compiled` elsewhere (traits §7.5, §13; compiler §2.1, §6.3).
- Open issue 142 closed; decision log §9 updated; 96d3915.
- **A Fable reviewer** (the `fable-critic` agent) was sent at the user's explicit request, an exception to the standing "no subagents on the shared host" (load 25 of 128 at the start). It reads only: no Julia, no builds. It writes `writeup/reviews/2026-11-06-unified-reference-prototypes.md`.

## The work plan under the draft

The user (2026-11-06):

> Send out a second Opus agent that compares the unification work plan that was started with the new design and figures out how the work plan would have to change and how it could be simplified.

- An Opus agent (general-purpose) was sent at the user's explicit request, again an exception to "no subagents on the shared host" (load 26 of 128). It only read: no Julia, no builds, no other file edited.
- Its proposal: [`writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md`](../writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md).
  - W-98 and W-99 survive almost whole; the uncommitted in-walk subtyping is the draft's compiler §4.4, §4.5, §4.10. The tree does not build yet: `typemap.c:553, 572, 915` and `gf.c:3798, 5409` still call the removed `jl_membership_match_sig` and `jl_membership_match_range` (checked in the main session).
  - Delete rather than fix: the Core wrappers, `generic_wrapper`, `Keyed`, the composed matches (C-20 retires by deletion).
  - The premise first: a slice of W-98, W-99 and a new small library with two workloads, compiled per type, before keys, the attribute, the split, guards and the facts policy.
  - W-102 and W-103 retired into N1–N9 (placeholders for new W- IDs).
  - Weak points 1–14 of the draft. Checked in the main session against the draft: weak point 1 holds (compiler §7.4 has subtyping derive memberships by running inference; and an inferred result changes with any callee's redefinition, so traits §9's and facts §10's "only by a definition of `F`'s methods" is false); weak point 4 holds (compiler §4.2 "needs no entry" against §6.1 "`S`'s entry … has that key"); weak point 3 holds (lowering §2's pattern `Dynamic{X{P…}}` misses `Dynamic{All{…}}`); compiler §2.1 says "three more options" and lists four.
- Nothing applied yet: the draft's fixes wait for the Fable review, so both are worked in one pass. For the user: `Callable`'s result (weak point 1) and whether to adopt the revised stages.

## The prototypes' review; one pass over the draft

- The Fable review arrived: [`writeup/reviews/2026-11-06-unified-reference-prototypes.md`](../writeup/reviews/2026-11-06-unified-reference-prototypes.md). 2 high, 8 medium, 10 low. H1 is the work plan's weak point 1 found independently: `Callable` by plain inference is unsound (the result depends on every callee and on inference's limits) and cannot run inside subtyping. H2: `bounded` on in `@trait_module` refuses the ports' constructors and adapters and the draft's own `keep`/`typeof` idiom.
- One pass over the draft took both reviews' findings, on the user's standing instruction ("Make decisions, think about existing languages, only where no principled option exists, come back to me"): P-20 to P-28, mine, in the README and decisions §9; the review's addendum lists every finding's disposition; the plan's status line its own.
  - H2: `bounded` stays in the bundle (the user's Q2 (a)); `@open` marks a method open on purpose (P-20). The review's opt-in is in `alternatives.md`.
  - Keys computed by the runtime from the membership and the contract, so `S <: TraitKey` follows the membership's worlds and the member hook only checks (P-12, P-18).
  - `Dynamic{X}` a struct of `Core`, its pattern `Dynamic{Z} where {Z <: X{P…}}`, parameters required (P-5).
  - Attribute bits only through `Core.attributed_call` (P-24); cast names reserved as `ccall` (P-23); normal forms by declared supertypes (P-21); intersections' keys and candidates (P-22); `trait_receiver`/`trait_field` (P-25); a module-end hook (P-26); `HasProperty` by `getproperty` at a constant name (P-27); smaller rules (P-28).
- For the user: open issue 143 (`Callable`'s result type: (a) declared results, (b) inferred outside subtyping, (c) arguments only, recommended (c)); open issue 144 (confirm P-20 to P-28); the work plan's revised stages.

## Callable's result; bounded by default; experiments

The user (2026-11-06):

> For Callable S go with checked on return. Keep it simple. For trait modules bound Vs open, the idea at some point was that exported methods must be bound and others can stay internal. But I really don't have a strong preference right now if we default to boundedness for trait modules as long as there is a switch. Are there any further experiments to run to clarify or check decisions?

- `Callable` (open issue 143 closed): a function is a member of `Callable{A, S}` where it has a method at `A` (`hasmethod`), for every `S`; `S` is checked on return; a `where` variable only in `S` is unbound (the result type as a value, `Base.promote_op`). The method-table query inside subtyping, memoized per (`F`, `A`) with its world range, is mine. `Dynamic{Callable{A, S}}`'s membership is the library's declared family.
- `bounded`: on by default in trait modules with the switches `@open` and `bounded = false` (P-20, the user's default). The exported-only rule is in `alternatives.md` as not taken for now.

## Two censuses (E-263, E-264); facts mode and caching

The user (2026-11-06): "Go for it." (on running experiments 1 and 2 of the list: keys shared in the ports; `@open` marks under `bounded`). During the run: "What do we know about the unified designs impact on facts mode and machine code caching?" (answered from the draft, the synthesis plan and the evidence: one CodeInstance per method instance and policy, G2 under it unmeasured on the unified build, E-261's code slot recovering 67 of 120 and 91 of 100 facts callers, memberships invalidating nothing by option (e), methods at traits now in Base's method tables (M6, unmeasured); the store paused with the record complete; E-234 and E-205 placing the savings in plain code.)

- Registered first (E-263, E-264), then run on julia-1.13 with TraitWorld in three sessions (`experiments/w105/census/`), no subagents, nothing timed, load 3–15 of 128.
- **E-263:** 4 of 148 memberships share a key, each a TraitMakie `Live{…}` wrapper with what it wraps; every other member serves its operations by its own methods, so its key is its own type. Below the registered tenth: open issue 145 proposes keys as Optional (the user's call: the user had asked whether keys stay).
- **E-264:** 3 of 52 public and 14 of 77 internal methods at traits are open by the draft's rule (13 functions); P-20 stands. 11 structs with a parameter bounded by a trait have default constructors the rule calls open: the draft now exempts constructors that set such a parameter (mine).

## The trade-offs of unification

The user (2026-11-06):

> The original implementation made a lot of progress to our main goal of cutting load times, recompiles, session times, and enabling caching and better type signatures and error messages. Painless AOT and machine code caches that leverage the gnew guarantees were also well in sight. The unification offers substantial conceptual simplifications. The question is what the trade off is and whether they can be recovered later through further work. The unification plan should focus on identifying these trade offs and exploring mitigations. As always Swift, Rust and Mojo provide crucial real world experience. Have a Fable agent look at all this from this perspective.

- A Fable agent (`fable-critic`) was sent at the user's explicit request, again an exception to "no subagents on the shared host" (load 4.6 of 128). It reads only (web sources allowed for Swift, Rust and Mojo), runs no Julia, and writes `writeup/reviews/2026-11-06-unification-tradeoffs.md`: per goal, what the original implementation achieved, what the unified draft keeps or loses, whether and how a loss is recoverable later, what has to be done now to keep that door open, mitigations and experiments.
- The trade-offs review arrived: `writeup/reviews/2026-11-06-unification-tradeoffs.md`. The guarantee machinery carries over; four trade-offs: G2 without the second owner (E-261: 100–120 facts callers lost per session of loads, the slot keeps 67 and 91), the stopgap until guards, keys Optional, plain code's cost of the type system. No loss found unrecoverable. Folded into the work plan's proposal as §8 (gates X1–X7 before the stages they decide); its draft changes wait for the plan's adoption. Verified in the main session: the boundary flag, 188 against 17 ms, E-259's sites, 2,898 entries.

## The work plan adopted; keys Optional; X1, X5, X6

The user (2026-11-06):

> Adopt, keys as optional is approved. Run the X now

And, while the experiments ran:

> A general thought: Simplifying the design by delaying performance optimizations like keys and guards sounds good. The trade off is ecosystem. If certain performance characteristics are guaranteed that enables to build around them, even if they don't have a measurable effect now.

- **The registry first:** E-265 to E-271 for X1 to X7 (16baab3). X2, X3, X4 and X7 wait for the unified build's stages.
- **The runs:** no subagents; 4 cores per job, two jobs side by side (load 3–5 of 128); X1 and X5 two runs each.
  - **X1 (E-265):** the forks' session pays 0.2–0.3 s with the slot, 0.7–1.0 s without; g2all nothing. The loss is CSV's facts code on CSV's own plain methods.
    - The first attempt ran both cases in one process and counted twice; the second stopped at a scoping error. Both are kept as attempts.
  - **X5 (E-266):** M1 keeps 50–92 % of the facts copies' compile time.
  - **X6 (E-267):** the memoized query's answers depend on the order of questions; the membership changes inside method insertion under its lock. The draft's §7.4 now reads a function's methods as its memberships (P-30, mine).
- **The adoption:**
  - N1–N9 are W-106 to W-114, keys (W-110) Optional, W-102 and W-103 merged;
  - every status line of the draft remapped;
  - §8's draft changes applied (P-31, P-32);
  - open issue 145 closed.
- **The user's thought** became open issue 146, with a proposal: separate guarantees from mechanisms, and commit to "a membership invalidates nothing" and to keys' guarantee, with their stages late. The evidence's TraitCSV case (extension by implementation keeps the reader's code; CSV.jl's extension by methods discarded it, 2.5 against 0.19 s) shows the ecosystem pattern the guards' guarantee makes safe.

## Keys: built late; the open decisions

The user (2026-11-06):

> A usecase for keys:  Operation only traits. That just guarantee functions of a certain signature exist. Keep them optional and build them late. Needs more investigation but is probably not urgent. Give me the open decisions concisely with recommendations

- Keys: Optional, built late (P-29, W-110; decision log). Open issue 146's keys part decided; guards and the guarantee/mechanism rule remain open there.
- The use case is open issue 147 (§2, not urgent). Under the draft's key, a member serving an operation by its own method is its own key, so operation-only traits share nothing. The investigation: a key that names what the operations resolve to.

## The open decisions, adopted

The user (2026-11-06):

> Adopt all recommendations. Go

- **Open issue 146 closed:**
  - the references separate guarantees from mechanisms (their conventions);
  - "a membership invalidates nothing" is committed, with guards after the first slice (W-112 queued) and E-268 measuring the stopgap until then.
- **Open issue 144 closed:** P-21 to P-28, P-30 and `@open` confirmed, with every choice marked mine, by the adoption.
- **The references adopted:**
  - `writeup/reference-unified/` moved to `writeup/reference/`;
  - the earlier references moved to `attic/writeup/reference/`, following the attic's rule that a path maps to `attic/<same path>`, and `reference-unified/` keeps Moved pages;
  - T-1–T-95, F-1–F-23, L-1–L-50 and C-1–C-17 are Retired rows; C-18–C-26 continue;
  - 870 links in current documents (five repositories) pointed to anchors that only the earlier references had: rewritten to the attic, so they keep working;
  - open issues 137, 138, 140 closed with the adoption;
  - the glossary, `design.md` and `intro/` carry a status line until W-115–W-117 rewrite them; W-118 triages the open issues on the prototype's mechanisms.
- W-71 dropped: the adoption settles it. W-19 waits, with W-100 as the first candidate. Open issue 2 stays deferred.
- W-98 resumes.

## W-98 built

After the adoption, stage 1 on `julia-unified` (no subagents; builds by `tools-local/build.sh`, load 6–11 of 128).
- **The rework, `unified` fd800b27b9:**
  - the in-walk rule kept;
  - Core's wrappers and `Keyed` deleted, with their arms in subtyping, intersection and specificity;
  - type values by `Type{S}` entries on `S`'s TypeName;
  - the declaration: a cycle check over every path, one instance per concrete member, a redeclaration ending the old entry, no task-world sync;
  - sets open from their declaration, with the epoch gone;
  - a contract slot, the entry's receiver;
  - the typemap's and gf's composed-match arms replaced by the world range of the memberships a query reads.
- **The first build** restored the old system images into the new runtime and crashed: the images were cleared and rebuilt. `base/boot.jl` still defined the wrappers' constructors.
- **The gates:**
  - the stub library follows the references (`@implement X S`, the set opened before publication, `Expr(:latestworld)`);
  - gates that pinned the earlier rules were re-pinned: a type value a member through its type's entry (A1), membership not subtyping, a narrow entry not answering the bare set, opening a set late;
  - the wrapper gates were replaced; the audit's probes became a gate;
  - a bug in the new stub (a parameter named `T` shadowed by the type's local) was found by `m2_set_in_set`;
  - 22 of 22 pass. Base's four test files are within 4 % of vanilla.
- **E-270 (X4)** failed its 2× criterion on the first build (3.6–7.8×). A fast path for non-members and reachability memoized per world range brought it to 1.7–1.8×.
- **The user, during the build:**

  > Side question: The old version had a bunch of Julia improvements Bugfixes and tweaks. Are those still relevant? Should we fold them in as we go? If so, we had the idea to split the Julia work into independent comits. Might be the right moment to do so.

  The 65 commits of `trait-world-1.13` were classified for the answer.

## The Julia work as a stack

- **The user:**

  > Force push is fine. No one else is using this remote.

  and, after a compaction:

  > Go. I am stepping away from the session for several hours so don't stop to ask or report.
- **The stack** on v1.13.2, branch `series` in `julia-unified`, then force-pushed as `unified` ([julia-changes §7.1](../writeup/design/julia-changes.md#71-the-stack)):
  - twelve changes useful without traits, one commit each: the three W-57 Base commits, the two per-call-site cache commits, the dispatch profiler (its two commits merged, without the split by owner, renamed `JULIA_DISPATCH_PROFILE`), `:caller_world`, the `return_type` image entry, the image rule for hashless signatures, the reflection fix (its facts half left), the two inliner changes (their facts gates left; each its own commit);
  - W-98 as two commits: the type system (`e0487d74d9`), dispatch at sets with the stopgap (`7db137f922`). Its comments lost the old plan's and reviews' IDs and point at the references; a comparison after stripping comments shows the code equal to fd800b27b9's plus the general commits. The comments of the stopgap's walk in `gf.c` were left, since W-99 replaces it;
  - not carried yet: `known_type`, the type printers' registry (no stage uses them yet); the facts mode and the other pieces wait for their stages;
  - the W-57 commits' messages were rewritten without the facts mode's terms (same trees).
- **The checks:** every commit changing C built on its own; full builds with tests at commit 12 and at the top (`experiments/unification/stack/README.md`).
- **A regression found:** Base's `core` test took 74 s against vanilla's 59 s, with 4.4 against 2.2 GB peak memory, on every build with the general commits. Reverting the inliner commits changed nothing. Timing `core.jl` per top-level expression (`core_by_expr.jl`) found line 5406: a splat of about 1.2×10⁸ arguments into a varargs method. The exact-type entries (a9d3dcb345 on `trait-world-1.13` too) made a type with one parameter per argument and kept it in the call cache. Commit 4 now makes such entries for a varargs method only up to as many arguments as Julia's compilation signatures spell out (`get_max_varargs`); `core` is back at 59 s and 2.2 GB.
- **Also checked:** the image rule of commit 9 drops a `UnionAll` specialization too. That is the same condition that sends an insertion at load to the linear scan (`jl_specializations_get_linfo_` reads the unwrapped body's hash), so it is as intended.
- **Kept:** fd800b27b9, the build W-98's gates and E-270 measured, on branch `w98-fd800b27b9`. E-270's questions were run again on the top: the same.
- **Records:** julia-changes §7, compiler §4 statuses and §8, §9, §11 (the stack's commits; the profiler's name; `_return_type`'s entry for `NativeInterpreter`), traits §3.1, the references' README, W-19, W-98, W-100, W-109, `state.md`, decisions §8, open issues §1 (the carried set as a choice marked mine; the stale line about W-71 replaced), E-270's README, evidence and registry row.
- **A slip:** `git add -A base` took a core dump from the earlier crash (`base/core-login02-2010139`) into the type-system commit; it was taken out before anything was pushed. Both dumps are still on disk, untracked.

## W-99: dispatch

On the restructured stack, the next stage of the adopted plan (the user had said "Go" and stepped away).
- **What W-98 had built already:** methods at sets in the typemap's linear list, the set-to-methods index, match world ranges, specificity at sets, the stopgap's walk with its volume log (`JULIA_MEMBERSHIP_LOG`), the 200-method lookup gate (`m2_typemap_linear`).
- **A7, the ambiguity report:** it asked with `Tuple{typeof(f), member}` whatever the methods' arity and called an empty match an ambiguity. Running the new gate showed two more defects: the warning named the method table, which every function shares in 1.13 (`WARNING: method methodtable …`), and it was given once per pair of sets across all functions. Now: each method's signature with the member in place of its set, intersected; `Base.isambiguous`'s rule at the intersection; the function, the two sets and the joint signature named; once per function and pair of sets (commit 15). Gate `m2_ambiguity_arity`. The earlier attempt's `m3_ambiguity_dominance` pins a fixed-arity method at one set beating a `Vararg` at another, which the references do not have (dispatch itself raises there); noted in the gates README, not run.
- **A4, the query world:** a per-thread override, so a task switch inside a region handed it to another task, and each region needed a `JL_TRY`. Now a field at the end of `jl_task_t`, saved and restored by exception handlers beside `world_age`; the three `JL_TRY` wrappers went (commit 16). Carrying it in the subtyping environment, as the audit proposed, cannot reach inference's own `<:` and `typeintersect` calls; the decision is marked mine. Gate `m2_query_world_task`. C-28 retired.
- **E-269 (X3)** found, before any method at a set was installed, dynamic calls over 50 container types 33 % slower than vanilla's, on `trait-world-1.13` too: commit 4's exact-type entries at a megamorphic site evicted each other and allocated at every call. Commit 4 now makes none at a site whose four slots hold exact entries for the method instance (`length` over 25 tuple types: 121 ns vanilla, 203 before, 114 after; 4 types: 18 ns).
- **Gates:** 24 of 24 at commit 16.
- **E-269 (X3)** failed its gate on two counts:
  - a method at an open set on `length` made method matching 60 % slower for every non-member (`iterate` 19 %, `getindex` 7 %), flat in the number of members: intersecting a concrete non-member with a set skipped `obviously_disjoint` and took 349 ns against vanilla's 30. Now a concrete type no entry of whose chain can reach the set is obviously disjoint from it (commit 17);
  - with no method at a set at all, dynamic calls over 50 container types were 24–33 % slower than vanilla's: the stack's commit 4 still allocated at mixed megamorphic sites. Its exact entries now live in the leaf cache and are reused.
  - The quick BaseBenchmarks subset showed nothing beyond its noise (two vanilla runs differ by a geomean of 0.975).
  - The `threads` test file failed its BLAS-threads case identically on vanilla: env.sh's `JULIA_CPU_THREADS=4`.

## The user, at night

> Okay, don't stop at gates, even if they fail. Make a choice and record it. Ask a Fable agent to review the choice but only if it is really high impact. I am going to bed. Keep implementing.

Recorded in CLAUDE.md. No choice tonight was high-impact enough for a Fable review.

## W-106: the library core

- **Where:** TraitWorld, branch `unified` (orphan), worktree `TraitWorld-unified/`: a fresh library; the prototype on `main` stays for the ports on the old build (mine).
- **Built:** `@trait` (operations, defaults, fields, parameters by fields, equations and statement, supertraits, the trait's method per operation, the contract on the TypeName, `Dynamic{X}`'s membership); `@implement` (block, `by`, several traits, stated parameters, families, abstract types and traits as members, a `Union`-bounded variable split per type, `struct S <: X`); the checks with `ImplementError`; `Dynamic{X}`, `unwrap`, `like`, `withfields`.
- **The member hook** in the runtime (commit 18): at a dispatch miss, before the instance lookup. Two things found on the way:
  - the library's own trait-method detection missed a reference that lowering hoists into its own statement;
  - the check's method matching cached an entry for the failing member's call, so the second call skipped the hook: a failed check now lowers those entries.
  The hook's half in the compile queue is not built (compiler C-31): a call compiled with the member's type known reaches the trait's method unchecked.
- **A design finding:** the ODE workload's `step!(::Euler, u, f, t, dt)` was ambiguous with the trait's method typed as declared. The trait's method now types only its receiver and the arguments that bind parameters (lowering §2; mine).
- **Gates:** the library's tests, F1–F8, F10, F11, F14 as acceptance cases, both workloads equal to plain Julia's; the stopgap's volume (2,905 cache entries lowered at a parametric trait's first membership, tens after).

## The stack's final shape for the night

- After commit 4's entries were reused from the leaf cache, a site that sees many types still cost 50 % more than vanilla (`length` over 25 tuple types 189 against 121 ns; 50 containers 170 against 137). Dropped from the stack (PE-20); the wildcard entries stay. Commit 5's message no longer leans on it.
- Method matching at a set still cost a non-member 48 %: the typemap computed the world range of the memberships the query reads (945 ns for an inference query with a `Vararg` tail) even for an empty intersection of a query with no entries anywhere. Now only where a membership can narrow it (`jl_type_has_memberships`), in the W-99 commit with the disjointness.
- The stack: 17 commits (eleven general, two W-98, three W-99, one W-106).

## W-107: the probe of All

- **The representation** (mine, high impact, so a Fable review): `Core.All{T<:Tuple}` an abstract `DataType`; `All{X, Y}` applied as `Union{…}` is and built in its normal form, `All{Tuple{X, Y}}`; subtyping on the right each component, on the left some component, each try from the saved environment; the fast paths abstain. The alternative, a new kind beside `Union`, touches every place Julia and its compiler switch on kinds.
- **The first build** aborted in `boot.jl`: `All{T<:Tuple}` lowers to a `TypeVar` call, and the declaration came before `TypeVar`'s constructors. Moved after them.
- **The probe passes:** the normal form (order, duplicates, nesting, `Any`, `Union{}`, absorption by declared supertypes, closed types with nothing in common), subtyping with `Union`, `UnionAll`, `Vararg` and invariance, the normal form unchanged by a later set-in-set membership, printing. The 24 gates and E-262's four files pass with it.
- **The name:** `Core` does not export `All`, since DataAPI exports `struct All{T<:Tuple}` and DataFrames re-exports it: open issue 148.

## W-107: done (2026-11-07, early morning)

- **The review's proposals built** on `w107-probe` (5a161a28a4): the typemap and the fold gates see through `All`; the diagonal rule and the occurrence walks treat components as covariant; instantiation and `apply_type` keep the normal form; the left rule backtracks; `Union` components distribute; two closed components collapse; the `Tuple` guard. The addendum of the review lists each.
- **A hole of the stack, found by the review's gate** `methods(length, (C,))`, which was empty for a single set as well: a set and an abstract type met as `Union{}`. So `g(@nospecialize(x::AbstractVector)) = f(x)` called `f(::Any)` for a member where `f(::X)` exists, and code compiled at a set raised `MethodError` at `length(x)`. They now meet as `All{X, T}` (C-33, mine; no other answer is sound once memberships end single inheritance).
- **The first fix overflowed the stack:** meeting an `All` with a set built an `All` and met it again. A type now meets each component once, and the results' intersection is taken in the normal form.
- **TraitWorld's acceptance cases turned ambiguous twice,** each a real finding:
  - `overview.jl` and `acceptance.jl` declared a trait `Shape` each and the same `struct Circle` in `Main`, so `Circle` was a member of two unrelated sets with a default each; the stack had hidden it, since two unrelated sets did not intersect. The tests now run each file in a module of its own.
  - F11 (`@implement GTable Indexable{Vector{Float64}}` after the block's methods): `Method.interferences`, recorded at insertion, said the two methods were ambiguous; the later set-in-set membership orders them. Matching now asks such a pair again in the query's world (mine).
- **Rank, report, name:** the rank of an intersection by its components; the report's joint method as the two signatures' intersection, `f(::All{X, Y})`; `jl_static_show` prints `All{X, Y}`; TraitWorld exports `All` (open issue 148 (b), mine).
- **E-269 at no method at a set rose to +8–11 %** on the probe. `perf stat` and `perf record` by instructions: an unwrap per `obvious_subtype` call, exported calls for the open-set bit and the current task on the hot paths. Fixed by inline reads; left: +2.2 % instructions, +4–8 % time (PE-22).
- **Folded** as the stack's commit 18, 8a9144928e (the probe's tree, `git commit-tree`, so the build stayed valid). Battery: gates 32 of 32, the four files and the stage-top files, `detect_ambiguities(Base)` 0, TraitWorld, both workloads.

## W-108: begun

- Memberships in package images: the session's declarations kept in a rooted list; an image writes those its modules declared (an entry's `min_world` written as `~0`, as a typemap entry's), and activates them at load in the methods' world, before validation, then runs the stopgap's walk and the ambiguity report as a declaration does.
- The definition, image and module-end hooks in the runtime; in TraitWorld the override rule (records of the operations a default serves at a member, per session) and the refusal of a `struct S <: X` without `@implement` at the module's end.
- **Done:** `unified` 28c401eb0c (commit 19), TraitWorld 701aaab. The image gate passed on the first build. F8's acceptance case defined a member's method after its `@implement`, which §5.11 refuses: the method moved before the membership. Deviations: the check and override records in images (L-55), the one-instance check at activation (C-35). Battery: gates 33 of 33, the stage-top files with `precompile`, both workloads.

## W-109: begun (2026-11-07, small hours)

- **A declared result on `Method`** (two fields after `purity`, so no field index moves); the library sets it on each trait's method after `@trait` defines it, evaluated with the method's own variables. Lowering's `f(…)::RT` is not recorded (C-36).
- **The rule** sits at the top of `abstract_call_gf_by_type`, before method matching, so a trait with more than three members still infers its declared result. A first version left the call dynamic and trusted the type: a member's method redefined after `@implement` to return a `String` would have broken it. The inliner now asserts the result (`DeclaredResultInfo`), and a redefinition raises `TypeError`.
- **The split:** the runtime's candidates per set (registered at a membership, at an image's activation, by the library at a pattern member's first use); inference narrows the receiver to the union of the first four and lets Julia's union splitting branch; a non-inlined case is typed by its own CodeInstance's result and asserted. The typed code of a five-member trait shows four `isa` branches with the bodies inlined and the last branch asserted.
- **The table**, ported from `trait-world-1.13` without its facts variant. The first build failed: the new functions sat between `ir_inline_unionsplit!`'s docstring and the function.
- **A W-108 bug found on the way:** `jl_add_methods` replaces an image's methods by their typemap entries during the restore, so the image hook passed entries, which the library skipped.
- **A build interrupted:** Compiler sources edited while the build compiled the Compiler; the build was stopped and started again with all files touched.
- Next: declared fields (the compiler needs the set's declared fields from something the runtime keeps), the classification, `bounded` and `@open`.
- **Declared fields:** a field `declared_fields` on `TypeName` (atomic, the 22nd); the first build's rule did not fire, since `getproperty` inside the Compiler is `Core`'s, not `Base`'s. Base's `core` test lists `TypeName`'s atomic fields and was updated.
- **The classification** in TraitWorld: an `AbstractInterpreter` of the library's with an ephemeral cache, so functions it follows are inferred again; a trait's own methods are skipped (their bodies are the contract); uses are recorded once each (constant propagation infers a call twice). `check_definitions`, `@bounded` (refused at definition by the definition hook), `@open`.
- **W-109 done:** `unified` 50da8d8ee2 (commits 20–23), TraitWorld 59134ef.

## W-100: begun (2026-11-07, morning)

- **Where:** branch `w100` of the julia repository, from the stack's top 50da8d8ee2, its commits confined to the facts mode for a later rebase onto vanilla (mine).
- **E-272, the earlier attempt's hang:** the `nortsite` bit alone builds in 700 s. No hang.
- **Slices, each with a full build and the battery:**
  - the facts inference (28fe27b2f7): `NativeInterpreter(; facts=true)`, `is_fact_sig` from `trait-world-1.13`, run-time sites that clear `nortsite`, asserted effects not applied over them;
  - the flags (beafa01b36): the module's `facts` and the four trait options by `@compiler_options`, the method's flag from `:facts_boundary` / `:facts_always`. The first build's options did not take: the interpreter reads only two-argument metas at top level, so an option is one integer, bit and value;
  - one CodeInstance per policy (10c7e1c2cf): the policy bit set when a CodeInstance is made, the lookups of Julia's own owner filtered by it, three flag writes that would have cleared it fixed; a callee of the other policy inferred in an inference of its own, at most four nested. Boundaries stay plain (C-44); constant propagation across policies runs in the caller's (C-45);
  - G2's bit (8ef154476f): every dispatch edge at a fact; E-273 counts 62 % of a workload's plain code;
  - `return_type` (b87d863b9e): folded in facts code only where it cannot be wider; otherwise at run time by a plain interpreter of its own. The gate's empty `map` would give `Vector{Any}` without it.
- **Left in W-100:** the record's kinds (§3.1), the test bed (§2.5: under it the system image's plain code cannot stand in, so all of Base compiles again; a long run), the image's keep rule by the G2 bit (§9), the boundary's second policy.
- **The image's keep rule** (823754556f): code reached only dynamically, of a method outside the package, kept where G2 holds; TraitWorld's image +3.7 %. Base's `precompile` test then reached a branch for a kept `Int16` specialization that read a backedge's `def` as a `Method`, a latent bug of the test; fixed as its other branch reads it.
- **The test bed** (4ba5b7025f): the switch `JULIA_COMPILE_BY_FACTS=1` and the compiler's modules never by facts. E-274: a session under it does not start. The compiler, plain, calls Base's neutral methods, which the switch makes facts and whose system-image code may not stand in: each call needs facts code only the compiler makes (open issue 149, for the user: the recommendation is the boundary's second policy). A stopgap (plain code for what a task runs inside inference) got past start-up and crashed staging a generated function; not kept.
- **State at the end of the night:** `unified` at 50da8d8ee2 (W-107, W-108, W-109 done); W-100 on branch `w100` at 4ba5b7025f, its slices passing the battery in the product setting; the test bed blocked on open issue 149.
