# The goals, and where each stands

What the project sets out to show, how far each claim is supported, what is weakest, and which work serves it. This page is the home of the goals and of the standing on each axis.

- The numbers are in [the evidence](design/evidence.md), each against plain Julia or Python.
- The work is in [the work queue](record/todo.md).
- The tensions' entries are in [the open issues §2](open-issues.md#2-tensions-between-the-goals).
- What is built, and on which heads: [the state](state.md).

## 1. The goals

The user's words:

> "The entire point of this project is to show that Traits and Facts actually enable dramatically reducing (re) compilation and potentially improve speed and caching with limited to no downsides and better error messages and better AOT compilation experience. We also want to show that there is a clean and doable path for the ecosystem to transition with clear potting guidelines. Finally unification made the design of the Trait system dramatically simpler, making it easy to teach."

On speed:

> "I don't want to claim better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x))."

On compiling ahead:

> "The main point in all of this is that we want to leverage traits to handle genetics, like AOT languages like Rust and Mojo do. Keep that goal in mind."

("genetics": generics.) So for G-6 the aim is that a trait bound does for a build what it does in Rust and Mojo: generic code is checked once against the bound, and a closed build compiles it for the members it has.

The axes, each with its claim:

| Axis | The claim |
|---|---|
| G-1 Recompilation | Traits and facts dramatically reduce compilation and recompilation: compiled code is kept through unrelated loads, and trait code is compiled once where its contract allows. |
| G-2 Run-time speed | No regression against plain Julia where types are known, and a caller can opt into full speed (`compiled_for(x)`). No claim of better steady-state speed. |
| G-3 Caching | What is compiled is kept: in package images, and across sessions. |
| G-4 Downsides | Limited to none: what the design costs code that uses no trait, and code that does, is small and stated. |
| G-5 Error messages | Better than plain Julia's: an error names the contract and the place it is broken. |
| G-6 AOT | A better experience compiling ahead: trait bounds handle generics as in languages compiled ahead (Rust, Mojo). A build lists what trait code calls and compiles it for the members it has; **Fully typed code is exactly the code that compiles ahead:** a program builds where its `main` is fully typed, and nowhere else, so one check in a session answers for the build. `make_executable` and `make_library` write a small binary of fully typed code, from a `main` defined at the prompt too. |
| G-7 Transition | A clean, doable path for the ecosystem to migrate, with clear porting guidelines. An ambition for the path, not a rule that code needs no rewrite. |
| G-8 Simplicity A membership behaves as a method does (worlds, invalidation, ownership, images); its edges are the method table's own ([compiler §5.6](reference/compiler.md#56-the-memberships-method-and-the-edges), open issue 180). | Traits are abstract types: one mechanism, easy to teach. |

**Speed is a control, not a goal.** No work item pursues speed. Speed is measured to show that a change brings no regression (G-2), and what a rule costs (G-4). A slowdown found is recorded as a tension (§3), not fixed at the case.

## 2. Where each axis stands

Each standing rests on the rows of [the evidence](design/evidence.md) for its goal. The numbers are there, with their builds.

| Axis | Standing | What supports it | The weakest point | Work that serves it |
|---|---|---|---|---|
| G-1 Recompilation | **Shown, in counts and in times, on the demonstrators and on a package compiled by facts as it is. A port's entry chain is lost to unrelated loads.** | Nine unrelated loads end 0.4 % of the own image instances of upstream CSV and DataFrames compiled by facts, against 9.1 % plain; the work after the loads takes 1.5 s against 5.3 s (E-511). The demonstrators' trait packages lose no instance to the loads, to twenty packages each adding a member in five orders, or to a prompt's new type, struct or closure (E-377, E-378, E-512). No unrelated load ends an own instance in the deep class, which holds 64 % of the forks' own facts instances, 79 % of upstream's by facts and 73 % of the ODE port's (E-478; the shares E-535). | The forks lose 2.6 % of their own image instances, CSV's reader, and their work after the loads takes 12 times their first work (GT-8; E-511). The box's runtime at a port's types is outside the deep class: 76 of the library's instances after the ODE port's load, in the port's image (E-531). An edit of a method at a trait is defined in 0.24 s the first time in a demonstrator's session, where the plain twin takes 0.07 s (GT-12; E-512). | W-143 |
| G-2 Run-time speed | **Parity where types are known. Erased code pays a dispatch per operation, and a box per call where a trait erases by default.** | An operation and a method at the trait at a known type cost a plain call's 0.79 ns; `compiled_for` costs what the type known costs (E-513). A stream that plain code knows prints at vanilla's speed (E-337). | A plain member passed to a method of a trait that erases by default is boxed at each call: 8.7 ns against 2.4 ns with `compiled_for`; a `Callable` argument boxed by default 25 ns against 0.79 ns (E-513). A field `::Dynamic{Shape}` costs 5.56 ns where plain Julia splits an abstract field of two subtypes at 0.79 ns (E-513). A stream erased on purpose costs up to 4.99 times (GT-5). NetworkDynamics' repeated work takes 312 ms where upstream's packages on vanilla take 228 ms (another solver stack, another hour; E-514): not profiled. The same workload's session takes 44 s against upstream's 91 s, and changed equations 0.7 s against 20 s. | W-169 |
| G-3 Caching | **Shown for package images; no cache across sessions.** | Two independent packages first combined in a session (E-375): plain Julia compiles the library's algorithms at the other package's type in every session unless a workload names the combination; with a trait, the membership's declaration puts them in that package's image with no workload, and code compiled once is in the library's own image. In the table and the ODE sessions what is compiled is the session's own code and Julia's (E-521). | No cache across sessions. It would serve the session's own code, a membership declared in the session and the pointers of code compiled once ([the evidence, "Not shown"](design/evidence.md#5-not-shown)). A failed member check is asked again in each session (compiler C-30). An instance the ODE port's workload reaches is in its image without code (open issue 228; E-528). Not measured again in this round. | — |
| G-4 Downsides | **Stated: each standing rule's cost is measured or marked not measured.** | [What each tension costs](design/evidence.md#what-each-tension-costs). Plain code on the changed Julia: repeated work's median 0.18 to 0.19 ms against vanilla's 0.18 ms; the library loaded late ends no plain instance and none of its own, and takes 33 ms (E-515, E-531). Base's stage of Julia's build within vanilla's; the system image 9 % larger (E-517). | Plain code's first work is 0.07 s above vanilla's on the head, in code generation: what the removed code slot had saved ([GT-9](open-issues.md#gt-9-the-membership-machinery-costs-code-that-uses-no-trait); E-515, E-527). The ODE port's load takes 0.39 s; with the library loaded first 0.31 s, of it 48 ms the library's hook for an image's methods, work an image could hold, and the membership walk's search for code at members whose type is new with the load (open issue 255; E-531). The references' Deviations tables hold open rows whose cost is not measured. | — |
| G-5 Error messages | **Shown for mistakes against a contract; not for a port's run-time failures.** | Fifteen mistakes made against one library in both forms (E-362, E-370, E-518): the trait form reports at the line that makes the mistake where plain Julia reports at a later call or not at all. Its messages name the trait, the type, the operation and its declared signature. A pirate at Base's plain function that code compiled by facts calls is reported by default and refused under strict mode, at the user's line (E-518). | On SciML's three run-time error cases the port is no better than its plain twin: none is a mistake against a contract (E-363, E-518). Two failures exist only in the trait form (GT-14). | — |
| G-6 Compiling ahead | **Shown on small programs and on the four demonstrators' programs.** | Small trait programs build under `--trim=safe` and run, where the plain loop over an abstract type is refused (E-520). The table's, the plot's, the report's and the ODE program, and an ODE program with callbacks it knows, build with 0 errors and print a session's output, 2.7 to 5.4 MB, the PNGs byte for byte; their plain twins on the same build count 6 to 86 errors and do not build (E-519). `make_executable` and `make_library` write a binary from a session (E-364). `fully_typed` in a session agrees with the build on 13 of 13 small programs (E-520) and on 17 of 18 (E-384). | Not a program at a port's scale. A value the build does not count raises `MethodError` where a session returns (compiler C-86). The check in a session keeps nothing between calls: for the ODE program it takes 10.2 s at the first call and 2.5 s at each call after it, where the trimmed build's object step takes 13 s (open issue 258; E-532, E-519). Below a trait program, a hole in Base fails the build where the user cannot fix it: 71 % of Base's exported signatures at broad types are fully typed (E-368; open issues 179, 181). | W-143, W-19 |
| G-7 Transition | **Partly shown: parts of three ecosystems ported with upstream's results; the first step of the path gives most of the gain. That ports need few annotations is not shown.** | The ports' suites pass or have their known failures: on the forks upstream CSV's suite passes whole, DataFrames' has its four `@inferred` errors (E-523). A package compiled by facts as it is, by one line per module: first work 1.8 s against 4.5 s plain (E-511). The forks' first work 0.19 s (E-511); their REPL session 2.6 s against upstream's 14 s and pandas' 0.7 s (E-390, E-386, E-289). [The porting guideline](intro/porting.md) lays the path out in five steps. | The annotations a port writes to choose how its code compiles: the ODE port 30, with 85 boxes and 19 declarations of `Callable`; the forks 6; TraitTables 5 (E-522). After unrelated loads the port is behind the package compiled as it is (GT-8). No port by another author. [The ports' questions](open-issues.md#the-ports) are open. | W-19 |
| G-8 Simplicity | **Plausible, untested.** | The references and `intro/` describe one mechanism: a trait is an abstract type that types may join later; a membership behaves as a method does (E-365, E-367, E-459); a value's type decides what is compiled. At the prompt `operations(x)` lists what a value offers, by trait, from the contracts ([traits §15.1](reference/traits.md#151-what-a-value-offers)). | Whether the pages teach is not tested. | W-150 |

## 3. Tensions between the goals

Where one goal presses on another, or on the design, the tension is recorded, not resolved at the case.

- **The home of an entry** is [the open issues §2](open-issues.md#2-tensions-between-the-goals): the rule, what it costs with its experiment, and a proposal.
- **This table is the index** of the tensions that stand: each with the axes it sets against each other. A tension takes the next free `GT-n`: **GT-35**.
- **A tension that is decided and built** leaves this table. It is in [the open issues' ledger](../attic/writeup/record/issues-closed.md), with how it was decided.
- **What each costs:** [the evidence](design/evidence.md#what-each-tension-costs).

| ID | The tension | Between |
|---|---|---|
| GT-2 | [Strict mode infers an image's memberships at its load](open-issues.md#gt-2-strict-mode-infers-an-images-memberships-at-its-load) | G-5 against G-4 (load time) |
| GT-3 | [The compiler and Base are compiled plainly](open-issues.md#gt-3-the-compiler-and-base-are-compiled-plainly) | G-4 and G-7 against G-1 |
| GT-5 | [A closed type's contract promises no result](open-issues.md#gt-5-a-closed-types-contract-promises-no-result) | G-8 and G-7 against G-2 |
| GT-7 | [The split's pointer per call, and its making per member in each session](open-issues.md#gt-7-the-splits-pointer-per-call-and-its-making-per-member-in-each-session) | G-1 against G-2 and G-3 |
| GT-8 | [G2 covers the deep class; a port's code outside it is lost through plain callees](open-issues.md#gt-8-g2-covers-the-deep-class-a-ports-code-outside-it-is-lost-through-plain-callees) | G-8 against G-1 |
| GT-9 | [The membership machinery costs code that uses no trait](open-issues.md#gt-9-the-membership-machinery-costs-code-that-uses-no-trait) | G-8 against G-4 |
| GT-12 | [The definition-time check runs at each edit](open-issues.md#gt-12-the-definition-time-check-runs-at-each-edit) | G-5 against G-1 |
| GT-14 | [A membership is seen from the world of its declaration](open-issues.md#gt-14-a-membership-is-seen-from-the-world-of-its-declaration) | G-1 against G-5 and G-7 |
| GT-16 | [Fully typed mode raises exactly where a build refuses, or fully typed code pays nothing](open-issues.md#gt-16-fully-typed-mode-raises-exactly-where-a-build-refuses-or-fully-typed-code-pays-nothing) | G-6 and G-5 against G-1 |
| GT-21 | [Calls that only throw keep a port's code out of the deep class](open-issues.md#gt-21-calls-that-only-throw-keep-a-ports-code-out-of-the-deep-class) | G-1 against G-4 |
| GT-32 | [A callable struct that is no `Function` is no member of `Callable` until its owner declares it](open-issues.md#gt-32-a-callable-struct-that-is-no-function-is-no-member-of-callable-until-its-owner-declares-it) | G-8 against G-7 and G-4 |
| GT-33 | [Every declared result read at a trait is checked where it is passed on](open-issues.md#gt-33-every-declared-result-read-at-a-trait-is-checked-where-it-is-passed-on) | soundness (facts G1) against G-2 |

## 4. The synthesis

The evidence, the tensions and the agent's choices are collected for a synthesis, from which the design is iterated.

- **A choice the agent makes while building stands as recorded:** in the reference, and in [the decision log](record/decisions.md) marked "mine". It does not wait for the user's review.
- **[The open issues §3](open-issues.md#3-the-agents-choices) lists these choices** as input to the next synthesis. Only a question that the work cannot continue without is put to the user ([§1](open-issues.md#1-questions-for-the-user)).
- **The running iteration** is [one plan](plans/2026-11-15-next-iteration.md): the decisions in one table, then stages with gates, each stage against the axes it should move. It ends with a freeze, a short measurement round and an addendum to [the synthesis](plans/2026-11-14-synthesis.md): each tension closed, smaller or standing. The round is run ([the evidence](design/evidence.md) holds its numbers); the addendum is §8 of the synthesis.
