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
| G-1 Recompilation | **Shown, in counts and in times, on the demonstrators and on a package compiled by facts as it is. A port's entry chain is still lost to unrelated loads.** | Nine unrelated loads end 0.4 % of the own image instances of upstream CSV and DataFrames compiled by facts, against 9.0 % plain; the work after the loads takes 1.7 s against 5.2 s (E-392). The demonstrators' trait packages lose no instance to the loads, to twenty packages each adding a member in five orders, or to a prompt's new type or closure (E-377 to E-379). No unrelated load ends an own instance in the deep class, which holds 63 % of the forks' own facts instances and 79 % of upstream's by facts (E-478). | The forks' work after the loads takes 2.2 s against 0.19 s first: two reader instances, ended through Base's plain code (GT-8). An edit of a method at a trait costs 0.5 to 0.7 s in a demonstrator's session (GT-12; E-391). | W-156, W-159 |
| G-2 Run-time speed | **Parity where types are known. Erased code pays a dispatch per operation, and a box per call where a trait erases by default.** | An operation at a known type costs a plain call's 0.79 ns (E-443). The wrapper costs what the type known costs (E-501). A stream that plain code knows prints at vanilla's speed (E-337). | A plain member passed to a method of a trait that erases by default is boxed at each call. A field `::Dynamic{Shape}` costs 5.56 ns where plain Julia splits an abstract field of two subtypes at 0.79 ns (E-374). A stream erased on purpose costs up to 4.99 times (GT-5). No port's steady state has a plain run beside it on this implementation. | W-159 |
| G-3 Caching | **Shown for package images; no cache across sessions.** | Two independent packages first combined in a session (E-375): plain Julia compiles the library's algorithms at the other package's type in every session unless a workload names the combination; with a trait, the membership's declaration puts them in that package's image with no workload, and code compiled once is in the library's own image. In the table and the ODE sessions no library's code is left for a cache across sessions (E-372). | No cache across sessions. It would serve the session's own code, a membership declared in the session and the pointers of code compiled once ([the evidence, "Not shown"](design/evidence.md#5-not-shown)). A failed member check is asked again in each session (compiler C-30). | W-159 |
| G-4 Downsides | **Stated: each standing rule's cost is measured or marked not measured.** | [What each tension costs](design/evidence.md#what-each-tension-costs). Plain code on the changed Julia: repeated work's median 0.18 to 0.19 ms against vanilla's 0.17 to 0.18 ms; the library loaded late ends no plain instance (E-499). Inference on plain code costs 1.5 times vanilla's, code generation less (E-388, E-389; GT-3). | Plain code's first work is slower than vanilla's on the head, in code generation, not diagnosed ([open issue 225](open-issues.md#4-runtime-and-measurements)). The references' Deviations tables hold open rows whose cost is not measured. | W-156, W-159 |
| G-5 Error messages | **Shown for mistakes against a contract; not for a port's run-time failures.** | Fifteen mistakes made against one library in both forms (E-362, E-370, E-498): the trait form reports at the line that makes the mistake where plain Julia reports at a later call or not at all. Its messages name the trait, the type, the operation and its declared signature. | On SciML's three run-time error cases the port is no better than its plain twin: none is a mistake against a contract (E-363, E-385). Two failures exist only in the trait form (GT-14). A pirate at Base's plain function is silent also under strict mode (GT-31). | W-158 |
| G-6 Compiling ahead | **Shown on small programs and on one demonstrator's program, on the tag's build; on the head the demonstrator's program does not build.** | Eight small trait programs build under `--trim=safe` and run, 2.5 to 2.6 MB, where the plain loop over an abstract type is refused (E-384). The table program builds with 0 errors and prints the session's output; its plain twin counts 6 (E-383). `make_executable` and `make_library` write a binary from a session (E-364). `fully_typed` in a session agrees with the build on 17 of 18 programs (E-384). | On the head the table program does not build (6 errors: a call that takes a wrapper is not split over the members, compiler C-150), and the report's, the plot's and the ODE program's builds stop while loading, in plain Julia's code ([open issue 243](open-issues.md#2-design)); on the tag the ODE program counts 50 errors ([open issue 184](open-issues.md#2-design)). Below a trait program, a hole in Base fails the build where the user cannot fix it: 71 % of Base's exported signatures at broad types are fully typed (E-368; open issues 179, 181). | W-166, W-158, W-143 |
| G-7 Transition | **Partly shown: parts of three ecosystems ported with upstream's results; the first step of the path gives most of the gain.** | The ports' suites pass or have their known failures (E-373, E-496). A package compiled by facts as it is, by one line per module: first work 1.9 s against 4.1 s plain (E-392). The forks' first work 0.19 s; their REPL session 2.6 s against upstream's 14 s and pandas' 0.7 s (E-390, E-386, E-289). [The porting guideline](intro/porting.md) lays the path out in five steps. | After unrelated loads the port is behind the package compiled as it is (GT-8). No port by another author. [The ports' questions](open-issues.md#the-ports) are open. | W-156, W-19 |
| G-8 Simplicity | **Plausible, untested.** | The references and `intro/` describe one mechanism: a trait is an abstract type that types may join later; a membership behaves as a method does (E-365, E-367, E-459); a value's type decides what is compiled. | Whether the pages teach is not tested.  | W-156, W-158 |

## 3. Tensions between the goals

Where one goal presses on another, or on the design, the tension is recorded, not resolved at the case.

- **The home of an entry** is [the open issues §2](open-issues.md#2-tensions-between-the-goals): the rule, what it costs with its experiment, and a proposal.
- **This table is the index** of the tensions that stand: each with the axes it sets against each other. A tension takes the next free `GT-n`: **GT-33**.
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
| GT-31 | [Strict mode secures the deep class only](open-issues.md#gt-31-strict-mode-secures-the-deep-class-only) | G-5 against G-1 |
| GT-32 | [A callable struct that is no `Function` is no member of `Callable` until its owner declares it](open-issues.md#gt-32-a-callable-struct-that-is-no-function-is-no-member-of-callable-until-its-owner-declares-it) | G-8 against G-7 and G-4 |

## 4. The synthesis

The evidence, the tensions and the agent's choices are collected for a synthesis, from which the design is iterated.

- **A choice the agent makes while building stands as recorded:** in the reference, and in [the decision log](record/decisions.md) marked "mine". It does not wait for the user's review.
- **[The open issues §3](open-issues.md#3-the-agents-choices) lists these choices** as input to the next synthesis. Only a question that the work cannot continue without is put to the user ([§1](open-issues.md#1-questions-for-the-user)).
- **The running iteration** is [one plan](plans/2026-11-15-next-iteration.md): the decisions in one table, then stages with gates, each stage against the axes it should move. It ends with a freeze, a short measurement round and an addendum to [the synthesis](plans/2026-11-14-synthesis.md): each tension closed, smaller or standing.
