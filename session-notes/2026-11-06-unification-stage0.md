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
