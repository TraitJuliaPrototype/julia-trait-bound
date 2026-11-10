# Review: the plan "a member's check holds while it is a member" (the result re-checked at a serving method's definition)

The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

Written by a Fable agent at the user's request, the exception to the rule against subagents on the shared host. Hostile but fair. *Verified* means read in the source or seen in a probe of my own; *reasoning* means inferred from them. The plan under review: [`2026-11-10-recheck-at-redefinition.md`](../plans/2026-11-10-recheck-at-redefinition.md).

**What was read:**
- the plan; the 171 plan's review (M4, M5); open issue 168; the decision rows for E-340;
- traits §5.10, §5.11, §7.9, §11.1, §11.3, §12.1–§12.3; lowering §11 and L-55; facts §2.1, §9, §10; compiler §7.1–§7.3, §10.1, §10.2, §10.4;
- TraitWorld `src/check.jl` (`check_member`, `_check_contract!`, `_serving_method`, `_first_serving`, `_open_further`), `src/implement.jl` (`_implement!`, `_implement_one!`, `_definition_hook`, `_image_methods_hook`, `_DEFAULT_SERVED`, `_record_defaults!`, `_forget_defaults!`, `check_first_use`, `_check_pattern_member`, `_define_fwd!`), `src/strict.jl` (`_would_win`, `_strict_after!`, `_strict_on_definition`), `src/classify.jl` (`_check_bounded`, `_decide_bounded`), `src/BaseTraits.jl` (the operations on Base's functions), `test/core.jl` (the override test), `test/runtests.jl`;
- the runtime: `src/method.c` (`jl_method_def`, the two hook calls), `src/gf.c` (`call_library_hook`, `jl_method_table_insert`'s overwrite path, `jl_method_table_disable`, `jl_method_table_invalidate`), `base/reflection.jl` (`infer_return_type`), `Compiler/src/typeinfer.jl` (`typeinf_type`, `typeinf_frame`);
- the gate `experiments/unification/gates/n22_declared_assert.jl`.

**What was run** (`source env.sh`, niced, one job at a time, load 4.7 of 128; scripts and outputs in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/24a7c1e0-a2ec-401b-8a6e-3d7a1561fce2/scratchpad/review-recheck/`, `probe_plain.jl`, `probe_tw.jl`, `probe_cost.jl`):
- plain `julia-unified/julia`: a same-signature redefinition deleted again (A); a definition hook of my own inferring the new method before it is inserted (B); `infer_return_type` at an ambiguous call (C) and at a call with no method (D);
- with TraitWorld: today's behaviour at a redefinition (1), at a method defined at a forwarding member (2), at a more specific method for a pattern member checked at its first use (3); the cost of the definition hook per definition and of the inference (4); a membership redeclared with a block and a trait redeclared (5).

No file but this one was written. No build.

## Summary

The rule is right and it is the trait's contract, not a strict-mode matter: traits §5.10 already ties the check to "the methods that serve the member" (line 471), and §5.11 refuses a later method unconditionally. Three things in the plan are wrong or missing, and they change the mechanism:

- **The mechanism should refuse before the method is inserted, inferring the new method itself, not the call after it.** The after-hook with `delete_method` cannot run in the image hook (which only calls the before branch, and the image's methods are inactive), cannot delete during precompile, spends two worlds and the old method's compiled code on every refusal, and interferes with `_check_bounded`'s and strict mode's own deletions. Inferring an uninserted method at the call types works on this build (probe B), and `_would_win` already exists for the before branch.
- **`rt <: declared` is not the right test on its own.** `infer_return_type` answers `Union{}` for an ambiguous call and for a call with no method (probes C, D), and `Union{} <: Int`. A method that makes the operation ambiguous at the member would pass.
- **The records cover less than the plan implies.** Per-session records cover memberships declared in the session and pattern members checked at their first use in the session (BaseTraits' members among them). They do not cover a package's concrete memberships loaded from its image, which is the Revise-on-a-package case and the package-extension case. The plan's §3 "Images" paragraph claims a path the after-hook cannot take. The reference must say what is covered, and L-55 must take the rest.

Beside these: forwarding members are unguarded (probe 2), pattern members need the records made on the first-use path (where §5.11's defaults are not collected today either), a trait's redeclaration goes unseen by a record that stores the declared type, and the records list in §6 is short.

## Findings, by severity

### H1. Refuse before insertion, by inferring the new method; not after, by deleting it — verified

- The plan (§3) checks in `_definition_hook(m, after = true)` with `Base.infer_return_type(f, tt)` in the latest world, then `Base.delete_method`.
- What that costs and misses:
  - `_image_methods_hook` calls only `_definition_hook(m, false)` (`src/implement.jl:196`), and the image's methods are not in the table when it runs (compiler §10.1: "before any is activated"). An after-check cannot run there, so the plan's "left inactive with a warning, through `_image_methods_hook`" has no path.
  - A deletion is refused while a package is precompiled (`gf.c:3738–3742`, "Method deletion is not possible during Module precompile"); `_check_bounded` guards that with `jl_generating_output()` (`src/classify.jl:432`). The plan says nothing; the build would die with the wrong error.
  - A refusal after insertion spends two worlds, and the overwrite has already invalidated the old method's compiled code and cleared its dispatch bits (`gf.c:4336–4347`: `jl_method_table_invalidate(m, max_world, 0)`, `dispatch_status` set to 0). Deleting the new method restores dispatch (probe A: `f(::Int) = 1; f(::Int) = UInt(2); delete_method(new); f(1) == 1`, verified on this build) but not the code or the bits.
  - Two after-checks that both delete (`_check_bounded`, strict mode's `_strict_after!`) and this one must be ordered so that at most one deletes; "already disabled" is an error (`gf.c:3876`).
- The before branch has what it needs:
  - `_would_win(m, sig, world)` (`src/strict.jl:58–65`) tells whether the new method takes the call at `tt`, before insertion; strict mode uses it there.
  - An uninserted method can be inferred at the call types: probe B set a definition hook, and in its before branch `Compiler.typeinf_type(interp, m, Tuple{typeof(g), Int}, sparams)` returned `UInt64` with `m.primary_world == ~0`. Use `Compiler.typeinf_frame(interp, Compiler.specialize_method(m, sig, sparams), false)` and `widenconst(ignorelimited(frame.result.result))`: cache mode `:no` (`Compiler/src/typeinfer.jl:1507–1512`), so nothing is cached for a method that may not exist (probe B's `typeinf_type` cached a CodeInstance with `min_world` 11759 for a method inserted at world 39623). The sparams come from `jl_type_intersection_with_env(sig, m.sig)`, as `_params_at` gets them.
  - A refusal before insertion needs no deletion: it works in precompile (the `ImplementError` fails the build, as §5.11's does) and in the image hook (the inactive method is inferred as it is; a call it makes to another inactive method of the same image infers `Union{}` and passes, a known limit, stated).
  - The one difference from inferring the call: a self-recursive serving method resolves its own call to the old method. Acceptable; one sentence in the status.
- **Change:** the re-check goes in the before branch of `_definition_hook`, next to the override check, in this order: records under `m`'s function; the sig filter; `_would_win`; the ambiguity test (H2); then inference of `m` itself at `sig`. A generated serving method (`isdefined(m, :generator)`) is inferred the same way inside `try`; on an inference failure the result counts as `Any`, as `infer_return_type` would answer at the membership. Drop the `delete_method` path and the `jl_generating_output` question with it.

### H2. `Union{}` passes the test: an ambiguity or a missing method is accepted — verified

- `Base.infer_return_type` merges the matches' results (`base/reflection.jl:665–669`). Probe C: `h(::Mc, ::Any) = 1; h(::Any, ::Int) = 2` gives `infer_return_type(h, (Mc, Int)) === Union{}` while `h(Mc(), 1)` raises `MethodError`. Probe D: no method gives `Union{}` too.
- So a later method that makes the operation ambiguous at the member passes `rt <: declared`, and the member is no longer complete: every call, through the trait or dynamic, raises. G1 holds (both sides raise), but the invariant the plan states ("a member's check holds while it is a member") does not, and the membership's check would have refused the same state (`_serving_method` finds no fully covering method; `check.jl:172–184`).
- **Change:** with H1's order, after `_would_win` says the new method changes the call: if neither `m.sig` nor the current serving method's signature is more specific than the other (`jl_type_morespecific` both ways 0), refuse with "would make `f` ambiguous at `S`" (the §6.3 ambiguity rule, which is an error under strict mode and a warning otherwise, says what the severity is: I would refuse here, since the membership's check refuses it). Only then infer. A gate line for it.

### H3. What the records cover, stated honestly; the rest is L-55's — verified by reading, reasoning on coverage

- Records are made where `_check_contract!` runs in this session: at `@implement` for one type, and at a pattern member's first use (`check_first_use` runs in every session, L-55). So BaseTraits' members (all patterns, `src/BaseTraits.jl:164–191`) are covered in the session that uses them.
- Not covered: a concrete membership (`@implement X S` for a concrete `S`) loaded from a package's image. That is the common package case, so:
  - Revise on a tracked package: its memberships come from the image; a redefinition of a serving method is not re-checked. The plan's §1 names Revise-style redefinition as the first case; for packages it is not covered.
  - a package extension's more specific method at a member of another package: the extension is precompiled; the image hook would check it only against in-session records.
  - the pirate in the default tier: the same.
- The plan's §3 says "Only checks made in the session are protected; L-55 covers the rest", which is right, but §1 and §2 read as if the rule held for every member, and §3's image paragraph claims a path that does not exist (H1).
- **Change:**
  - traits §5.10's status says what is covered: memberships declared in the session and pattern members checked in it; a concrete membership from an image is L-55's.
  - L-55's row gains the result records, and names the fix: at a package's load, rebuild the records from the image's memberships (the runtime's entries hold the member, the instance and `by`, which is all `_call_types` needs; no inference is needed to rebuild a record). A W-item for it. This is also the principled form of the records: the contract and the membership are the record; the session dictionary is a cache of them.
  - a `@test_broken` in the new test file for the uncovered case, tied to L-55, so the gap is in a gate and not only in a row.

### M1. Forwarding members are unguarded — verified (probe 2)

- For a member by `by`, `_check_contract!` skips the operations loop (`check.jl:155–167`): nothing is recorded. The serving methods are the membership's generated forwarders (`_define_fwd!`, `implement.jl:261–291`).
- Probe 2: `@implement Meas2 Outer by i`, then `msz2(::Outer) = UInt(5)` at the prompt overwrites the generated forwarder (same signature, no error); the call through the trait raises `TypeError`, the dynamic call returns 5.
- **Change:** the forwarders are the membership's, as the defaults are: a later method that would take a call one of them serves at the member is refused (§5.11's rule and mechanism). `_define_fwd!` records `(X, member, tt)` under `op.f` in `_DEFAULT_SERVED` for each generated method, and `_forget_defaults!` drops them with the membership. No inference, no new dictionary, one sentence in §5.11 ("the forwarding's methods, like the defaults, are fixed at the membership"). A gate line: the overwrite is refused, the forwarder still serves.

### M2. The records must be made on the first-use path, where §5.11's defaults are not collected today — verified by reading

- `_implement_one!` passes `defaults` to `check_member` and records them on success (`implement.jl:119`, `:139`). `_check_pattern_member` calls `check_member(bare(X), T; stated, how)` without it (`implement.jl:492`), so `_check_contract!` records no default (`check.jl:175`, `defaults === nothing`). The override rule does not hold for a pattern's members today: a later `greet(::Fam{Int})` at a member a default serves is accepted.
- Probe 3 shows the result escape at a pattern member (`msz3(::Fam{Float64}) = UInt(3)` after the first-use check: `TypeError` through the trait).
- **Change:** collect both kinds of record in `check_member` (one vector, or two), and record them in `check_first_use` after a passed check as `_implement_one!` does; forget them where `_CHECKED`'s answer is dropped. Say in §5.11's status that the override rule now holds for pattern members. A gate line for each.

### M3. A record that stores the declared type goes stale at a trait's redeclaration — verified (probe 5)

- `@trait Meas` can be redeclared in a session (probe 5: the contract's result changed from `Int` to `Integer`, no error). The plan's record stores `declared`; after the trait widens its result, a method widened to match is refused against the old `Int`. The Revise flow "widen the trait and the member together" hits this whenever the trait's file is evaluated first, which is the usual order.
- **Change:** the record names the operation (`X`, member, `op.name`, arity, `tt`, `env`, `R`), and the check reads the declared result from the current contract (`_eval_in(c, op.result, env, R)`); an operation the contract no longer has voids the record. The reverse order (the method's file first) is refused once and accepted on Revise's retry; the message names the declared result, so the developer sees why. One sentence in the status.

### M4. A redeclared membership: forget the records before its block is defined — verified by reading

- `_implement!` calls `_forget_defaults!` before `_define_block!` (`implement.jl:91–92`), so a redeclaration's block is not refused against the old membership's records. The result records need the same place, or a redeclaration with a block that changes a result is refused at the block instead of being checked as a membership. Probe 5 confirms a redeclaration with a block works today.
- **Change:** one `_forget_records!(X, member)` for both kinds, called at line 91. A gate line: a membership redeclared with a block whose method changes its result within the declaration.

### M5. Strict mode's invalidation log is left on when the before branch throws — verified by reading, pre-existing

- `_definition_hook(m, false)` calls `_strict_on_definition(m, false)`, which starts the log (`strict.jl:211`), before the override check, which may throw (`implement.jl:174–185`). The after branch, which stops the log, never runs for a refused method. The new refusal makes this path common.
- **Change:** run the override check and the re-check before `_strict_on_definition(m, false)`, or stop the log in a `try`/`catch` around them. Not a gate; a line in the commit.

### L1. Names and lines in the plan

- The plan's §3 names `_check_one!` (`src/check.jl` ~190–205); the function is `_check_contract!` (`check.jl:150–207`), the result check at 193–202. The plan's §1 cites `src/implement.jl:168` for the hook: right.

### L2. Records the plan forgets, beside its §6 — verified by grep

- compiler §10.1's list of the hooks' users (line 780) and lowering §11's table rows for a method's definition and an image's activation (lines 210, 212); traits §11.1's row for a method's definition (line 943) and §11.3's `ImplementError` row (line 973: "a serving method defined after the member's check whose result leaves the declared result; a method that would make an operation ambiguous at a member");
- traits §7.9 (line 741) and facts §9 (line 316) say the assertion catches "a serving method redefined after it": after this plan the escapes left are the abstract-further-argument methods, a concrete membership from an image (L-55), a membership declared below the library (`declare_membership`, as `n22` does), and inference's own limits. Both sentences change;
- `design/alternatives.md`: the plan's §4 (invalidate and re-check at the next use; warn only; the assertion alone) goes there, since the references never mention alternatives;
- `open-issues.md` §1: the choice, mine, for the user to confirm, with H3's coverage statement; open issue 168's recommendation (line 312: "proposed, not built");
- `state.md`; L-55's row (H3); a W-item for the load-time rebuild of the records; the decision log row, mine, naming traits §5.10, §5.11, §11.1, §11.3, §7.9, facts §9, lowering §11, compiler §10.1;
- `n22`'s header comment stays true (it declares below the library); a line saying so would stop a reader taking it for the library's behaviour.

### L3. Cost — measured

- The hook today: 234 µs per definition at the prompt (500 trivial definitions through `@eval`, probe 4, the `eval` included); an `IdDict` miss 30 ns. The added lookup is noise.
- The bound per definition that hits records: one subtype test per record under the function, then `_would_win` and one inference per record the method takes. Inference of a trivial serving method: 0.23 ms uncached, 54 µs from the cache. Records accrue per concrete member type and operation: BaseTraits' `Base.length`, `getindex`, `firstindex`, `setindex!`, `push!`, `resize!`, `haskey`, `size` get one per concrete type checked at its first use (`iterate(c, state)` and `get(d, k, default::D)` are open, no record). A pirate `getindex(::AbstractArray, ::Int)` in a session with hundreds of checked vector types infers at each: tens of milliseconds, once, at the pirate's definition. Acceptable; the status states the bound.
- A thread defining methods while another declares a membership races on the dictionary, as `_DEFAULT_SERVED` does today. Threads are untested (facts §2.1); a line.

### L4. A serving method deleted — reasoning

- Not in the plan's cases. After `delete_method` of a serving method (Revise deletes before it redefines), the member has no method; a call through the trait and a dynamic call both raise. Consistent, so no G1 fault; the invariant is broken until the redefinition, which the re-check then judges against the record (probe D's `Union{}` is why the record, not the current state, must be the reference). Refusing the deletion would break Revise. **Change:** one sentence in §5.10: a serving method deleted leaves the member without one until a method serves it again; its calls raise `MethodError`.

### L5. The error for a definer who does not know the trait — reasoning

- The pirate case refuses a method in a module that may not use traits at all. §5.11 already does this unconditionally, so the shape has precedent, but the message must carry everything: the member, the operation, the trait, the declared and the inferred type, and the two fixes (return the declared type; or do not define it at this member). The override message's two fixes (`implement.jl:183`) are the model. A gate checks the message with `occursin`, as the override test does.

## The questions, answered

1. **The rule, and whose matter it is.** Right, and the trait's contract: §5.10 line 471 already makes the check conditional on the serving methods staying the same, and §5.11 refuses a later method unconditionally; strict mode is about facts code and pirates, not about a member's own methods. Revise and a change of result "for good reason" are the contract's business: the fix is a conversion in the method or the trait owner's change of the declaration (M3 for the order). A pirate is refused with the same unconditional shape as §5.11 (L5). Coverage is the caveat (H3): for a package's concrete memberships the rule holds only once L-55 rebuilds the records at load.
2. **Mechanism.** Inference is the right predicate but the after-definition form is the wrong time: refuse before insertion by inferring the new method itself (H1), after `_would_win` and an ambiguity test (H2). Deletion restores dispatch on this build (probe A) but not the compiled code, the dispatch bits or the two worlds, and cannot run in precompile or the image hook. Missed definitions: a forwarding member's (M1, fix by §5.11's mechanism), a pattern member's if the records are not collected on the first-use path (M2), a method through a supertype's method is covered (the sig filter and `_would_win` see it), a default-served operation is §5.11's, a deletion is not covered and need not be (L4). In an image's load, with H1, the inactive method is inferred as it is and left inactive on a failure, for in-session records only (H3).
3. **Cost.** Acceptable (L3): the lookup is 30 ns against 234 µs per definition; inference only for a record the method takes, bounded by the records under its function.
4. **Gates.** The plan's five cases, plus: a pattern member at first use then a more specific method (probe 3); a forwarding member's overwrite refused (probe 2); an ambiguity-making method refused (probe C); Revise's order, `delete_method` then the definition; a member of two traits sharing the operation, the second `@implement`'s block; the trait redeclared wider, then the method (M3); a membership redeclared with a block (M4); a pirate from another module, and the same in strict mode where facts code calls there (`PirateError` first, by the hook's order); a package that redefines its serving method after `@implement` failing to precompile with `ImplementError`; the image hook with an in-session membership and a precompiled pirate (the stack's two-package harness, `ahead_two_packages.jl` as the template); the uncovered image case as `@test_broken` (H3); the message's content (L5). `n22` stays as the runtime-level gate.
5. **Contradictions and forgotten records.** No reference contradicts the rule; §5.10's own wording calls for it. The after-hook form contradicts compiler §10.1's image hook (H1). L2's list. The simpler principled alternative is H3's: the contract and the membership are the record, and a session dictionary caches them; build the dictionary tonight with contents that the load-time rebuild can produce, and let L-55 produce them.

## Verdict

**Build with the changes listed.** In this order tonight:
1. H1 and H2: the re-check in the before branch, `_would_win`, the ambiguity refusal, inference of the new method with `typeinf_frame`; M5's order of the strict log.
2. M2 and M4: both kinds of record collected in `check_member`, recorded at `@implement` and at a first use, forgotten at a redeclaration before its block; M3's record shape (the operation named, the declared result read from the current contract).
3. M1: the forwarders fixed at the membership through `_DEFAULT_SERVED`.
4. The gates of question 4, in `test/recheck.jl` and the stack harness.
5. H3's coverage statement in §5.10's status, L-55's row and the W-item; L2's records; the decision row, mine; open issues §1.
