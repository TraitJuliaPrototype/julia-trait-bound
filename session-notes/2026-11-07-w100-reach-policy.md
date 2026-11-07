# 2026-11-07, morning: open issue 149 decided; the policy of the code that reaches a method

## The user's words

- "Explain the open issue and its trade offs" (open issue 149, after the night's report).
- "Confirm a then continue. Recall the rules for working on this machine."

## The decision

- Option (a) of open issue 149: under the test bed a neutral method takes the policy of the code that reaches it, through the boundary's second policy (C-44). Recorded in compiler §2.3–§2.5, facts §6.2–§6.3 and the decision log; the issue closed (writeup 62f07a1).
- **Mine, for the user to confirm** (open issues §1): what reaches code. Compiled code and the interpreter reach with the policy of the code they run, splats and `invokelatest` included; the runtime's own entries (the C API, task entry, finalizers, `@cfunction`, `__init__`, staging a generated function, compile requests) with the setting's default; a top-level thunk with its module's. E-274's crash log showed why a splat must carry it: the recursion ran through the compiler's `_apply_iterate`. This narrows the user's row of 2026-10-20, which sent splats to the default owner.
- The old branch `trait-world-1.13` had a facts entry for compiled facts code only (`jl_apply_generic_facts`); its test bed relied on a facts system image, issue 149's option (b).

## The build (w100 c44a447f2c)

- A method's policy: plain, facts, or the caller's (a boundary; under the test bed a neutral method; builtins plain).
- The policy wanted passes through inference: the engine's reservation key, the CodeInstance's bit (set from the policy it is compiled in, not from its method instance), the Compiler's cache view (`InternalCodeCache.policy`), `typeinf_ext_toplevel`'s fifth argument.
- Dispatch: entries of compiled plain and facts code (`jl_apply_generic_plain`/`_facts`, `jl_invoke_plain`/`_facts`); variants of the five builtins that call a function; the interpreter's policy; `jl_apply_generic` and `jl_invoke` stay the runtime's own entries.
- Not done (C-50): the operation of `modifyfield!` and its kin, a dispatching builtin reached by a dynamic call, an ABI converter's generic call: they reach with the setting's default.

## E-275

- The test bed starts and runs. An empty session takes 24–25 s against 0.17 s: Base's start-up path is compiled by facts in every session (PE-23).
- Dynamic dispatch first measured 3–4 % above vanilla. Caching the policy on the method instance (C-49) and keeping one out-of-line copy of the dispatch body did not move it. The parent 4ba5b7025f, built once in a worktree of its own (`julia-w100base`, from the same dependency cache), measured 181–182 ns against the new build's 168–169 and vanilla's 160–163: the change makes dispatch faster, and the remaining 4–5 % predates it (PE-24; the profile puts it in the method cache's lookup).
- Gate `f6_reach_policy`: a boundary by each way of calling, `jl_call`, and a session under the test bed; it passes, and fails on the parent.
- The battery passes (`logs/w100h-*`).

## Left

- `julia-w100base/`: the parent's build, kept for PE-24's bisection if it is taken up.
- Six core dumps from E-274's crashes (3.1 GB) in the workspace root, in no repository.
- Next in W-100: the gate's acceptance cases and G2 share under the test bed; which of Base's methods are boundaries; the record's kinds (§3.1).

## E-276: the acceptance cases (W-100's gate)

- The earlier attempt's 21 cases, never run before (its build hung), ported: `mark!` sets the method flag "always facts"; each case re-runs under `JULIA_COMPILE_BY_FACTS=1`.
- 18 pass in both settings. `AC_18`, `AC_20` wait for the record's kinds; `AC_16` for `@enforce_fully_typed` (W-114).
- Six cases had errors of their own, fixed. Four asserted the earlier attempt's representation and now assert G1 and the reference's facts: per-split edge pairs (`AC_02`, `AC_13`), a CodeInstance per type value (`AC_14`), a neutral helper compiled by facts in the product setting (`AC_10`: in the product setting the marked caller rests on plain inference's folded value, which is plain Julia's).
- One defect: a compiler method marked "always facts" became facts code; the compiler's module flag now comes first (w100 95fe10427c).

## The user confirms

- "Confirm. Please delete for me." What reaches code (decisions §9) confirmed. The six core dumps and the parent's build `julia-w100base/` deleted; a bisection for PE-24 builds its commits again.

## The record's positive memberships (E-277), G2 under the test bed (E-278), Base's boundaries (E-279)

- The user: "Continue with everything. I am away from the machine. Try to finish the unification on your own as far as possible."
- **The record (compiler §3.1, §4.8), w100 9a601902a0.** A positive answer through a membership entry folds at `isa`, `<:` and a dispatch match, in the frame being inferred: the entries it rests on (every link of a chain) join the CodeInstance's edges as the entry objects themselves, and the code's worlds start at theirs. No backedge (memberships only grow). Image validation takes the entry's worlds where it is in force. Elsewhere (typeassert's nothrow, `typesubtract`, the optimizer, the semi-concrete pass) such an answer stays unfolded: C-51. The record's other kinds: result edges with the code slot (W-101); digests, layouts and stable identities with the paused machine-code cache: C-52.
- Gate `f7_membership_edges`; `AC_18` and `AC_20` re-judged to the entry as the edge (both links of a chain recorded; `jl_membership_entries_for` in place of the earlier attempt's `jl_membership_entry_for`).
- **E-278:** 99.8 % and 99.9 % of the facts code satisfies G2 under the test bed; the gate (≥ 99 %) passes.
- **E-279:** 65–72 % of facts code in a facts module rests on plain code of Base, none on plain code that misses G2. Mine: no method of Base carries the boundary flag (decisions §9, open issues §1).
- Next build: C-43 (lowering carries the policy meta into keyword sorters and positional forwarders) and `--trim` (every method plain).
