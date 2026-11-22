# Lessons learned

What the work taught, stated as it holds now. Each lesson is one sentence in bold, what it rests on, and where its numbers are.

- The design itself is in the [references](../reference/README.md); the reasons for its shape in [the rationale](../design.md).
- What was tried and not taken is in [the alternatives](alternatives.md).
- Numbers are in [the evidence](evidence.md), by experiment (E-n). Tensions between the goals (GT-n) are in [the open issues](../open-issues.md) §1.
- The long form of each lesson, with the documents it came from, is in the agents' tier: [the harvest notebook](../record/harvest-2026-11.md) (L-n below), [the playbook](../record/playbook.md) and [the project's context](../record/context.md).

## 1. The design

- **The guarantee is the facts rule's. Traits make living under it cheap and checked.**
  - Code compiled by facts as it is written, one line per module and no trait, keeps its code through unrelated loads and does its first work faster (E-392).
  - So every claim is attributed to one of the two: the facts rule, or traits. (L24, L83)
- **In plain Julia, lost code is an open-world problem, not a piracy problem.** An abstract call depends on every method that matches, and any owner may add one. Under the facts rule only a stakeholder's change or a winning pirate ends code; piracy is what is left. (L17, L101)
- **Only concrete facts survive unrelated loads.** A fact "the methods matching this abstract signature are exactly these" is broken by any package that defines a subtype with a method. The proof is in [the proofs](proofs.md). (L101)
- **The guarantee is as strong as the code under it.** A port's code that rests on Base's plain code is lost when that code is lost (GT-8, E-392, E-478). Base's surface is part of the design's object. One standard library method (SparseArrays' `vcat` at Base's types) is the largest single cause in every round. (L30)
- **A trait is an abstract type that members may join later, with a contract checked at each membership.** Stating the design as that one premise, and deriving what follows, removed more rules than any review found. Where a port puts a trait beside an abstract type of the same meaning, the two are one thing. (L81, L82)
- **A membership behaves as a method does:** its worlds, what it invalidates, who may declare it, how an image holds it. It then needs no rules of its own. The parsimony is owed to the user; what implements it is whatever is simplest. (L28, L97)
- **One decider for what is compiled for a value: the value's own type.** It is Rust's and Swift's rule. A rule with several deciders (a default, a cast, the position, the first sight) produced most of the ports' questions. (L40, L46)
- **Whether code is compiled for a caller's value is the caller's to say, in the language.** A switch inside a library is `@nospecialize` turned around. (L46)
- **Erase at the boundary where large code serves many value types, not at the kernels.** A trait laid over a type the whole ecosystem specializes on moves every caller (`IO`: GT-10, E-330, E-333). (L93)
- **A stored value offers every capability its type has, to whoever asks.** Seeing it through the one trait it was stored under blocked legends, inspectors and pooled columns alike. (L77)
- **A guarantee has a payer.** "A membership invalidates nothing" was paid by plain code's inference at every call a later membership could change (GT-1). Ask who pays before adopting a guarantee. (L91)
- **A guarantee that rarely costs is cheap to offer:** if pirates never win, strict mode never raises. (L106)
- **What a design fixes at a declaration, it defends by refusals that depend on load order.** A fact that a later definition invalidates composes. (L2)
- **Running library code inside inference to fix a fact is a deep hole** (locks, worlds, edge records, load order). Make the fact a relation the type system knows. (L73)
- **A closed build compiles plainly.** What traits add to compiling ahead is a list of what an erased value can be (GT-15). (L107)
- **Associated types in first-order form only.** Symbolic reasoning about them is where other languages paid ([other languages](other-languages.md)). (L108)

## 2. Simplifying a design

- **State the goals and the lessons, withhold the mechanisms, and let independent designers start from the brief.** Three designs arrived at one core, the facts rule. (L100)
- **Try the named precedent as the design first.** Its known failure comes with the name. (L37, L40)
- **A mechanism that exists because of where the prototype had to live is not the design.** Classify each: needed, imitating the platform, working around the vehicle, left over. (L14, L23)
- **A concept no port uses is found by `grep` and is a candidate to remove.** (L13)
- **A spelling with five readings is a finding about the design.** (L51)
- **An idea dropped for want of a rule returns when the rule exists;** a mechanism rejected for stated reasons returns when each reason is answered by name. (L6, L47)
- **Before a large change, review what it trades against what was achieved,** goal by goal, with the experiment that measures each loss. (L84)

## 3. Speed

- **A slowdown chased at one case does not hold.** Speed gates with numbers drew the work into patches. The claim that lasts is no regression where types are known ([the goals](../goals.md), G-2). (L92)
- **Where a rule of the design lets the compiler do less, it does:** a membership test decided with an edge, a box that needs no heap, a check read from an instance that exists.
- **Under the facts rule the cost sits in a few shapes of code:** containers of `Any`, abstract elements with one result type, calls at abstract types whose result is then `Any`. Each has a rewrite or a rule ([the porting guideline](../intro/porting.md)). (L4, L43, L102)
- **Profile before judging a design by a first number.** A tenfold loss was one conservative path taken for the normal case (E-290). (L90)

## 4. Images and workloads

- **A membership's declaration puts code into an image that a workload would have to name** (E-375).
- **A cache recurs only where its keys recur.** Compilation is keyed on the library, on the user's model or data, or on the call's shape. Keep the user's types out of a library's keys; normalize at the entry. (L65)
- **Measure what a mechanism would hold before building it.** On the sessions measured, a cache across sessions had no library code left to hold; the images held it (E-372). (L98)
- **Once compiled code is kept, the load is what remains,** and it follows the dependency tree and Julia's validation of edges. (L67)
- **Say what is trait-specific and what is packaging.** Lean trees, loading stubs, normalization and erasure of the user's function are open to plain code. (L68)

## 5. The ports

- **The first step carries most of the gain:** the package compiled by facts as it is (E-392). The control set up to falsify a port carried the strongest result. (L5)
- **The change that pays is where a user's types enter a library's types.** Erase there, and everything above keeps its type (the NetworkDynamics port). (L53)
- **The parameters in the outermost layer only;** inside, the right-hand side partially evaluated. (L66)
- **The key holds what the hot code must know and no more:** the cell type, not the column's container; the numerical key, not the user's model. (L78)
- **Closed sets are types; open sets are traits.** A port that says what it leaves plain is shorter and more honest. (L59, L79)
- **The first trait of a port is an interface the ecosystem already has informally.** (L49, L58)
- **A port's silent hazards are found by a tool, not by a failure:** a type computation that Base folds for plain code, constant propagation into a `getproperty` switch. Run the dispatch profiler after the first step. (L54, L55, L103)
- **An annotation that fixes a time hides a cause.** Run the fully typed report first; declare the callee's result before asserting at the call. (L76)
- **A port never bends the design at the case; it records where the design pushed back.** And a port's change that follows a rule of the references is the port following the design, not a workaround. (L56, L94)
- **Upstream's own suites, run unchanged, are the bar of a port.** (L8)
- **A session's suites cannot see what a build compiles differently.** A plain call at a value known only by its trait is per type in a session and once at the trait in a trimmed build; the wrapper carries the member's own code into both. A change of how code erases is checked by a trimmed build (E-506, E-507, E-508).
- **The casts gave a session nothing the box, the wrapper and the forwarder do not give.** Their machinery left Julia with every suite and session as before (E-504, E-505, E-506).
- **Each ecosystem was ported once, by the design's author.** A porting rule needs a second port. (L49)
- **A library compiled by facts keeps its own hooks safe from unrelated loads only where it calls Base's generic code at values typed `Any` from its own code, or through a run-time site by intent.** The same call inside Base's plain code commits, and puts every caller outside the deep class: a dependency's `promote_rule` ended 15 of the library's instances at each port's load. (E-531)

## 6. Claims and measuring

- **The registry row comes before the run,** with the result that would change the design. When the outcome takes the other branch, the plan changes. (L10, L72)
- **Measure the case the claim is about, with the control that isolates the cause.** No fitted workload; like with like; the build on every number. (L9, L29)
- **A baseline is plain Julia or Python.** A comparison with an earlier iteration is a regression control.
- **Say which tier a guarantee is,** theorem or measurement, and name the exceptions of "never". (L18)
- **A claim of "the same as plain Julia" is checked by a redefinition, in both modes.** (L27)
- **A number says whether it measures interop or idiomatic trait code.** (L44)
- **A first-call time is compilation plus run time.** Time the step again in the same session. (L105)
- **A harness proves its images valid.** One depot per setting; no cache measured on the session that recorded it. (L71)
- **A deviation without an expected-failure check is a claim nobody re-verifies.** (L45)
- **A build that stops is first a question about the procedure.** Three trimmed builds stopped after a rebuild of Julia because no package image was valid, not because of a change of the design; the control at the tag stopped the same way (E-509).
- **A cost measured beside a rule is not the rule's until a profile says where the time goes.** A plain package's load a tenth slower was recorded as the price of dispatch edges at the call's own signature, with two guessed causes; the profile showed a third, a duplicate check over boxed pairs, and the fix left the rule and removed the cost. (E-534)
- **A check that the gates do not make is made by hand after every merge, or it is lost.** The library's hooks were made run-time sites and the gates, the suites and the examples passed; the trimmed programs, which only the round built, had one unresolved call for two merges. (E-538)

## 7. The record

- **Every kind of fact has one home.** A status copied into four documents disagreed within days. (L20, L34)
- **A reference drifts back into a build log unless the status line's shape forbids it.** (L33)
- **Cite code by name, never by line.** (L64)
- **A finding gets an ID and a home the day it is made.** (L11)

## 8. The method

- **Evidence before the build.** Unification passed its first gate on quick runs of minutes. (L85)
- **A plan, a hostile review, the review's changes, then the build.** (L96)
- **A design's claim about Julia's internals is checked against the code by a second reader.** (L86)
- **Sort every open question into bins by what it blocks.** "Conceptually complete" then has a definition. (L99)
- **Record a tension between the goals; do not resolve it at the case.** The synthesis reads them together.
- **What the facts build finds wrong in plain Julia goes upstream as an improvement to plain Julia.** (L31)
