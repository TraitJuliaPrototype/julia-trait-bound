# The goals, and where each stands

What the project sets out to show, how far each claim is supported today, what is weakest, and which work serves it. This page is the home of the goals and of the standing on each axis. The numbers are in [the evidence](design/evidence.md); the work is in [the work queue](record/todo.md); the tensions' entries are in [the open issues](open-issues.md) §1.

Assessed 2026-11-10, in the main session, from the evidence and `state.md` as they stand on `unified` fcdfd0da36 with TraitWorld 048c44e. Nothing was run for the assessment. A standing changed since names its experiment.

## 1. The goals

The user (2026-11-10):

> "The entire point of this project is to show that Traits and Facts actually enable dramatically reducing (re) compilation and potentially improve speed and caching with limited to no downsides and better error messages and better AOT compilation experience. We also want to show that there is a clean and doable path for the ecosystem to transition with clear potting guidelines. Finally unification made the design of the Trait system dramatically simpler, making it easy to teach."

And on speed, the same day:

> "I don't want to claim better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x)). I want to stop pursuing speed for now. We have gained enough to be satisfied. The IO work also shows the difficulty of reasonable solutions to isolated slowdowns in an existing ecosystem."

So the axes, each with its claim:

| Axis | The claim |
|---|---|
| G-1 Recompilation | Traits and facts dramatically reduce compilation and recompilation: compiled code is kept through unrelated loads, and trait code is compiled once where its contract allows. |
| G-2 Run-time speed | No regression against plain Julia where types are known, and a caller can opt into full speed (`compiled_for(x)`). No claim of better steady-state speed. |
| G-3 Caching | What is compiled is kept: in package images, and across sessions. |
| G-4 Downsides | Limited to none: what the design costs code that uses no trait, and code that does, is small and stated. |
| G-5 Error messages | Better than plain Julia's: an error names the contract and the place it is broken. |
| G-6 AOT | A better experience compiling ahead: a build can list what trait code calls. |
| G-7 Transition | A clean, doable path for the ecosystem to migrate, with clear porting guidelines. An ambition for the path, not a rule that code needs no rewrite. |
| G-8 Simplicity | Traits are abstract types: one mechanism, easy to teach. |

**Speed work is stopped** (the user's words above). No work item pursues speed. Speed is measured only as a control: that a change brings no regression (G-2), and what a rule costs (G-4). A slowdown found is recorded as a tension (§3), not fixed at the case.

## 2. Where each axis stands

| Axis | Standing | What supports it | The weakest point | Work that serves it |
|---|---|---|---|---|
| G-1 Recompilation | **Shown in counts on the unified build; a port's entry chain is still lost.** | On the unified build, nine unrelated loads end 0.4 % of the own instances of upstream CSV and DataFrames compiled by facts and 1.0 % of the forks', against 9.2 % plain; upstream's work after the loads is 6–9× faster by facts (E-355; [evidence §1](design/evidence.md#1-the-guarantee)). The demonstrators' images lose no instance of a trait package, where a plain twin's work after the loads costs 16× its repeated run (E-357). Twenty packages each adding a member to one trait end no instance and give the same counts in every load order (E-358). At the REPL a new type or closure ends nothing, and an edit behind a cast ends no caller (E-359). A package's image for a member with its work holds 0.29× the instances and 0.40× the added bytes of the plain twin's (E-360). The ports' sessions against upstream's ([evidence §3](design/evidence.md#3-first-calls-and-sessions)). 99.8 % and 99.9 % of the facts instances of two workloads satisfy G2 (E-278). | The few instances a port loses are its entry chain, through plain callees in Base: the forks' work after the loads takes 0.96–0.98 s against 0.063 s (GT-8). An edit of a method at a trait takes 2.8 s to evaluate the first time in a session, 0.4 s after (GT-12). An argument typed by a bare variable bounded by a set is compiled per value type (C-54). | W-128 (C-54), W-119 |
| G-2 Run-time speed | **Parity where types are known, on the earlier build; not restated on the unified build.** | A typed trait call costs what a plain call costs; a `Callable` held `Dynamic` 3.95 ns against 0.87 ns direct and 20.3 ns dynamic (the earlier build; [evidence §2](design/evidence.md#2-run-time)). Plain code beside the membership machinery: Base's tests 2–6 % slower, one run (E-262). | No measurement on the unified build of a typed call, a `compiled_for` call and an erased call against plain. | W-17 (measured once, as a control) |
| G-3 Caching | **Weak.** | Package images hold facts code that loads do not invalidate (E-302). A membership from an image keeps its check (E-344). A member's image holds its own instances and none of the library's generic code again (E-360). | Images keep no check states, so each session asks again (L-55, C-30). No image holds the pointer to a member that joined after its caller was compiled: about 9 ms per operation and member in each session (E-358, GT-7). No cache across sessions (W-120). | W-128 (L-55, C-30), W-120 (to revisit) |
| G-4 Downsides | **Stated in parts, not as a whole.** | The costs measured are in [evidence §4c](design/evidence.md#4c-the-unifications-trade-offs-measured-on-todays-build) and the flagged entries ([open issues](open-issues.md) §1). A plain session on the unified build (E-356): the first work not slower than vanilla's, DataFrames' repeated steps 8–18 % slower (GT-9); the library loaded late ends 197 plain instances and costs 0.25 s (GT-11). | No one account of what a user of plain Julia pays once the library is loaded, and what trait code pays. The deviations tables are long. | W-138 |
| G-5 Error messages | **No evidence.** | The mechanisms are built: a member's check raises at the use (E-350, E-352), strict mode reports a pirate, an ambiguity and a broken membership (E-349, E-353), fully typed mode explains (traits §14). | No comparison of the messages with plain Julia's for the same mistakes. The evidence has no section. | W-136 |
| G-6 AOT | **The weakest axis.** | One trimmed TraitMakie binary of 4.07 MB, on the previous prototype ([evidence §4](design/evidence.md#4-builds-and-binaries)). | Nothing on the unified build. No binary of TraitDifferentialEquations, CSV or DataFrames. | W-135 |
| G-7 Transition | **Partly shown.** | Three ecosystems ported, with upstream's results ([state §4](state.md#4-the-ports-w-104)). [`intro/porting.md`](intro/porting.md). A first step on the path, measured on the unified build: a package's code compiled by facts as it is, by one line per module, gives the plain results, 4.5× on first work and 6–9× after unrelated loads (E-355). | The path's steps are not laid out in order, each with what it costs and gains. The ports' questions (open issues 157 to 162) are open. The guideline is not checked against the ports as they are now. | W-104, W-137, W-19 |
| G-8 Simplicity | **Plausible, untested.** | The four references and `intro/` describe one mechanism. | No reader from outside. The intro's examples are not checked on the head. | W-137 |

## 3. Tensions between the goals

Where one goal presses on another, or on the design, the tension is recorded, not resolved at the case (the user, 2026-11-10: "I want to continue the strategy of recording pressure and tension between the goals (as we did for pushback on the design from speed and port work). The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected.").

- **The home of an entry** is [the open issues](open-issues.md) §1, "Flagged: tensions between the goals": the rule, what it costs with its experiment, and a proposal.
- **This table is the index:** each tension, the axes it sets against each other, and its entry. A tension takes the next free `GT-n`.
- **The ports' pressure on the design** is open issues 157 to 162 ([§2](open-issues.md#2-design)) and, for the earlier build, [the NetworkDynamics port's log](explorations/ndport-pushback.md).

| ID | The tension | Between | Entry |
|---|---|---|---|
| GT-1 | "A membership invalidates nothing", with negatives that never fold | G-1 against G-2 and G-4 | open issues §1, flagged |
| GT-2 | Strict mode infers an image's memberships at its load | G-5 against G-4 (load time) | open issues §1, flagged |
| GT-3 | "The compiler is compiled plainly", and Base in the product setting | G-4 and G-7 against G-1 | open issues §1, flagged |
| GT-4 | A cast decides only at an argument typed by a trait | G-8 against G-2 | open issues §1, flagged; open issue 162 |
| GT-5 | A closed type's contract promises no result | G-8 and G-7 against G-2 | open issues §1, flagged |
| GT-6 | The attribute resolves at the method's declared type | G-1 against G-2 | open issues §1, flagged |
| GT-7 | The firewall's pointer per call, and its making per member in each session | G-1 against G-2 and G-3 | open issues §1, flagged |
| GT-8 | G2 covers less on the unified build than on the earlier one: facts code is lost through plain callees | G-8 against G-1 | open issues §1, flagged |
| GT-9 | The membership machinery costs code that uses no trait | G-8 against G-4 | open issues §1, flagged |
| GT-10 | An isolated slowdown in an existing ecosystem has no reasonable local fix | G-7 against G-2 | open issues §1, flagged |
| GT-11 | A method at an open set on one of Base's functions ends plain callers when the library loads | G-7 and G-8 against G-4 | open issues §1, flagged |
| GT-12 | The definition-time check runs at each edit | G-5 against G-1 | open issues §1, flagged |

## 4. The synthesis

The evidence, the tensions and the agent's choices are collected for one synthesis, from which the design is iterated (W-138). Until then:
- **A choice the agent makes while building stands as recorded:** in the reference, and in the decision log marked "mine". It does not wait for the user's review (the user, 2026-11-10: "I don't want to review all decisions made by you.").
- **Open issues §1 lists these choices as input to the synthesis.** Only a question that the work cannot continue without is put to the user.
- **The order of work follows the weakest axes** ([the work queue](record/todo.md), "The plan").
