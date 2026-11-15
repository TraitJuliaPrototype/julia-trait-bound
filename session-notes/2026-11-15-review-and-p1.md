# Session note, 2026-11-15: the review of the conceptual design, and P1

The main session. No subagent. Heads at the start: `julia-unified` 7b374f39ce, TraitWorld `unified` e11c7cc, the design repository `w141-record` 2f3b24d.

## 1. The review

The user: "Last night we finished the conceptually complete prototype. There is a synthesis report. Please review the overall conceptual design of the project thoroughly, given the learnings and tensions recorded. Come up with principled suggestions for large scale, architectural and conceptual design changes that have a chance of removing tension. Nothing is off the table. Do not run code, just write the review and suggestions."

- Written by reading; no code run: [`writeup/reviews/2026-11-15-conceptual-design.md`](../writeup/reviews/2026-11-15-conceptual-design.md) (bc948ad).
- Four roots of the recorded tensions (two compile policies, two ways to erase, two homes for a contract, two rule sets for inference) and seven proposals, P1 to P7.

## 2. P1, discussed

The user: "I want to discuss P1 more thoroughly. The use case that weighs on my mind is SciML. I typically want this to be Dynamic{RHS}, and that should be the default for inexperienced Devs, but I want to be able to opt for maximum speed if I know what I am doing. We previously briefly had the Dynamic only design but the other problem we encountered was putting user provided stuff into storage (Vector{T})... So the simpler choice Dynamic{T} <: T that mirrors what Rust does, is very tempting, but we need to understand its design implications first in the context of Julia."

- My answer: P1 as the review had it needed the library's switch, which the user ruled out on 2026-10-21. Corrected: the choice in the value's type. `compiled_for(x)` returns a wrapper that is a member; a trait's default is a generated forwarding method; storage holds the form it is given.
- Three questions put to the user: is a view that is not the object acceptable; who is the inexperienced developer (SciML's callers, or anyone who writes a method); how far the wrapper reaches.

The user: "1 is acceptable, 2 if Callable wants it anyway that's how it should be, 3 does it matter in fully typed code?"

- My answer to 3: not for speed or typing. For which method runs, in one case: a function with methods at a trait and at a subtrait of the same object. I proposed the narrow reach (the wrapper sees what the box sees).

The user: "I would say that we want wide reach. If a subtrait provides a higher performance specialisation we don't want to miss that. Any reason not to?"

- My answer: none strong enough; the wide reach is also the simpler mechanism (one wrapper type, made in plain code). What is accepted with it: the box runs the methods at the trait it was erased at, the wrapper the most specific trait methods; an ambiguity the box hides; the wrapper is still not the object, so a method at the object's own type needs `unwrap`.

The user: "But if a type satisfies the trait by a specialized function that gets seen anyway... So provisionally I would accept P1 with the addendum. Record this and then do the suggested probes to settle the other P from the review."

- Right: an operation served by the member's own method is reached through both forms. The limit holds only for a function outside the contract.
- The quotation is as the user corrected it afterwards ("Probes, not proves"): the message read "the suggested proves".

## 3. Recorded

- The review's addendum (P1 as it stands, the implications in Julia, the storage table).
- [The decision log](../writeup/record/decisions.md), Pending: P1 provisionally accepted. Not in a reference: not in force.
- [Open issue 186](../writeup/open-issues.md).
- [The work queue](../writeup/record/todo.md): W-151 (P1: a prototype in the library, then the references), W-152 (the probes for P2 to P7).
- [The registry](../writeup/record/experiments.md): E-394 to E-400, each before its run.

## 4. The probes

Run the same day, on `unified` 7b374f39ce with TraitWorld e11c7cc and the forks 439bae7; seconds to two minutes each; load below 1 of 128. Scripts and logs: `experiments/unification/w152/` (experiments 1e39190). The outcomes: the registry's rows E-394 to E-400, [the evidence](../writeup/design/evidence.md) §1, the review's second addendum.

- **P4 holds** (E-394): the library's late load ends 201 plain instances, all through required operations' methods at open sets; the same operations at the box end none.
- **P3: the predicate holds, the demand rule is too wide for now** (E-395): no deep-G2 instance ended by the nine loads; 40 of the 49 ended carry the bit; 56 % of the forks' facts instances are not deep. A cheap rule found: a call that only throws as a run-time site (41 % to 61 % deep).
- **P5 (b) holds** (E-396): 14.7 % of the forks' run-time sites and 22 to 41 % of the trait packages' are at the package's own functions that only it extends.
- **P2 holds** (E-397): the check and the reading at the box agree at 157 of 165 methods.
- **P7 (c) holds** (E-398): no dispatch by a `Callable`'s signature in the ports; seven guards.
- **P6 is ended by its criterion** (E-399): deep-G2 code holds 13 to 19 % of a load's lookups.
- **P7 (b)** (E-400): the case on the head; the fix needs a build.
- Found on the way: the G2 bit is missing on instances with binding edges only (open issue 187); compiler C-88 (e) restated from the case.

Not done: P1's prototype (W-151). No reference was changed but compiler C-88 (e)'s row.

## 5. `Callable`, and the plan

The user: "Explain the Callable point concisely"

- My answer: today a function is a member of `Callable{A, S}` where it has a method at `A`, so subtyping reads the method table. The proposal: every function is a member, and the signature is checked where the function is boxed. What it gives up is dispatch by a function's signature, which the ports do not use (E-398).

The user: "Two questions: Do we lose early Error messages? What about something like map that wants to match signature and type through a variable?"

- Early errors: kept at a call. The forwarder boxes a plain function, and the box's constructor checks; a wrapper is checked at the method's entry by a test of `hasmethod`. Lost only for a struct parameter's bound.
- Variables: one that another argument binds keeps working (`retain!`, `Tables.byrow`, `ODEProblem`, the callbacks). One that only the function's methods bind stops working; none found among the census's 20 methods, read and not checked mechanically.

The user: "Okay, accept the change. What would be the best way to act on the Synthesis+Review? Would it make sense to write a consolidated implementation plan that a new session can pick up?"

- Recorded: [the decision log](../writeup/record/decisions.md), Pending (accepted, not in force); [open issue 188](../writeup/open-issues.md); the review's third addendum; W-153.
- My answer to the question: yes. One plan, since the two documents overlap and the probes changed three of the review's proposals; staged, each stage with a gate from an existing experiment; the measured state tagged first; the library before Julia, the references before the build, the ports after.
- Written: [`writeup/plans/2026-11-15-next-iteration.md`](../writeup/plans/2026-11-15-next-iteration.md), a proposal. Its table D-1 to D-15 holds what the user decided (D-1 provisionally, D-2), what waits for the user's confirmation, and what is mine. Its stages are W-151 and W-153 to W-159 in the work queue, proposed.
- Nothing was built. W-151's prototype is not started.

