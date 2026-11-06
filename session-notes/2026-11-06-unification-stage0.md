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
