# The synthesis (W-138): the prototyped design assessed, and its next iteration

**Status:** proposal (2026-11-14), for the user. Written in the main session, from the evidence, the tensions, the ports' questions and the choices marked mine. Not normative: nothing here is in force until it is decided and written into a reference.

The user (2026-11-10): "The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected." And (2026-11-11): "a synthesis assessment that can thoroughly analyse the prototyped design and suggest changes and adjustments and thinks that need to be fundamentally revisited."

**What it rests on.** The measurement round (W-145, E-374 to E-388) on the freeze `unified` 21c9b33e39; three fixes after it (W-146, E-389 to E-391); the check on the head (W-147, E-392, E-393), `unified` 7b374f39ce with TraitWorld e11c7cc. The round was not run again on the head: a number is the freeze's unless a later experiment is named. Numbers and their settings: [the evidence](../design/evidence.md). Standings: [the goals](../goals.md) §2. Entries: [open issues](../open-issues.md) §1.

## 1. In brief

- **The central claim holds.** Compiled code is kept through unrelated loads, new members and a prompt's definitions, in counts and in times. The strongest single result needs no port: a package compiled by facts as it is, by one line per module, does its first work in 1.9 s against 4.1 s and its work after nine unrelated loads in 1.7 s against 5.2 s.
- **Nothing measured contradicts "limited downsides".** Plain code pays about a tenth on repeated work and nothing on first work. The membership machinery is below a tenth of every phase of a session.
- **Compiling ahead works where the program is typed down to Base.** The table program builds and runs. The ODE program does not yet.
- **Three things should be revisited at their root,** not patched:
  1. **Base's surface.** Every large loss that is left sits where trait code meets Base's plain code (§3.1). The design treats Base as given. The next iteration should treat a part of Base as the design's own object.
  2. **What decides a trait argument's attribute.** It is the least simple part of the design, the source of most of the ports' questions, and it now has one rule for a session and another for a build (§3.2).
  3. **What a check costs, and when it runs.** A check at each definition costs half a second at each edit, and three kinds of check have three cost models (§3.3).
- **Two mechanisms should be weighed for removal** (§3.6): the code slot, whose marks keep one instance and no time in the three cases measured for it (E-393), and the module and scope options of the attribute, which no port uses.
- **Not shown, and not to be claimed:** better steady-state speed; a cache across sessions; that the design is easy to teach (no reader from outside); better messages for a port's run-time failures.
- **The questions for the user are in §7:** seven decisions, each with a recommendation.

## 2. Each goal against the evidence

| Axis | Verdict | The number that carries it | The number against it |
|---|---|---|---|
| G-1 Recompilation | **Shown** for the mechanism; a port's entry chain is the exception | Own image instances lost to nine unrelated loads: 0.4 % by facts, 1.0 % the forks, 9.0 % plain. The demonstrators' trait packages lose none, to loads, members or a prompt (E-376 to E-380, E-392) | The forks' work after the loads: 2.2 s against 0.19 s first; two instances (GT-8; E-392) |
| G-2 Speed | **No regression where types are known** | A call through a trait at a known type: 0.79 ns, a plain call's (E-374) | A cast `with_dynamic` from typed code: 344 ns. `compiled_for(f)` at each call: 1.34 ns, not inlined |
| G-3 Caching | **Shown for images; a cache across sessions is not needed for trait code** | A membership declared in a package puts the library's code at its type into that image, with no workload (E-375) | What a session still compiles is its own code and Julia's methods at its signatures: the same in plain Julia |
| G-4 Downsides | **Limited, and stated** | Plain first work not slower than vanilla's; repeated work's median 0.19 to 0.20 ms against 0.17 to 0.18 ms (E-381) | Inference on plain code 1.5 times vanilla's (E-389). Some forty open deviation rows |
| G-5 Messages | **Better for mistakes against a contract** | Reported at the line that makes the mistake, with the trait, the type and the declared signature (E-362, E-370, E-385) | A port's run-time failures are its plain twin's. Two failures exist only in the trait form (GT-14) |
| G-6 AOT | **Shown small; one demonstrator** | The table program: 0 errors under `--trim=safe`, 3.1 MB, runs; the check in a session agrees with the build on 17 of 18 programs (E-383, E-384) | The ODE program: 50 errors. Base: 71 % of its exported signatures fully typed (E-368) |
| G-7 Transition | **The first step is strong; the full port is uneven** | One line per module: 2.2 times faster first work, 3 times after loads (E-392). The forks: first work 0.19 s | After unrelated loads the port is behind the package compiled as it is (2.2 s against 1.7 s) |
| G-8 Simplicity | **Not tested** | One mechanism for memberships (a method's) | Five steps decide an attribute. 12,000 lines added to Julia in 138 commits; 3,100 lines of reference |

## 3. What the evidence says about the design

The eighteen tensions, the ports' questions and the choices marked mine fall into six groups. Each group names what is settled, what is open, and a proposal.

### 3.1 Trait code on plain Base: where the losses are

**The entries:** GT-3, GT-8, GT-9, GT-11; open issues 99, 125, 157, 179, 181; item 19.

- **What is measured.**
  - The forks' 2.2 s after unrelated loads is two reader instances (`CSV.read`'s body and `CSV._parse`, 0.49 and 0.40 s to compile again). They are facts code. They end because Base's plain code between them and `open`, and a call of `vcat`, is ended: by FilePathsBase's method of `open` at its own path type, and by SparseArrays' `vcat` at Base's types (E-392).
  - Upstream compiled by facts as it is loses 14 instances and no time: its work after the loads is faster than its first.
  - Inference on plain code costs 1.5 times vanilla's. What is left after E-389 is the compiler's static calls made through the runtime (GT-3).
  - Loaded after plain work, the library ends 209 of 122,403 plain instances, through its methods at open sets on `length`, `iterate` and `haskey` (GT-11).
  - A build fails in a hole of Base that the user cannot fix; the build script replaces 28 methods of Base to get past some (open issues 179, 181).
  - A function barrier in facts code loses its callee's declared result (open issue 157): DataFrames' four files that fail are this.
- **What it shows.** The guarantee is as strong as the code under it. The design made the packages' code stable and left Base as it is. Each case above is Base's code deciding something across an abstract call, in the product setting.
- **What was tried.** Base compiled by facts in the test bed `all` removes the invalidations (a late `using DataFrames` recompiles 0.02 s against 6.1 s, E-177) and costs an empty session 24 to 25 s without an image of its own (PE-23). No method of Base carries the boundary flag (mine, by E-279).
- **Proposal.** A part of Base becomes the design's object: **the surface trait code calls**.
  - (a) *Typed and stable at the signatures typed code calls it with.* The tool exists (`fully_typed` over Base's exported functions, E-368): five functions hold 73 % of the holes. Each fix is a patch to Base that stands without traits (W-19).
  - (b) *The boundary flag on the Base methods that `cause.jl` names for a port,* so that a load's method at another type ends a run-time site's cache entry and not the caller. It is in the design ([compiler §2.2](../reference/compiler.md#22-the-boundary)) and unused. To measure first on the forks' two instances.
  - (c) *The sets on Base's functions are Base's own,* defined before any package is compiled (GT-11 (a)). The late load is the prototype's, not the design's; state it so.
  - (d) *Standard libraries as owners of their own* (item 19): SparseArrays' `vcat` is then a pirate's method, and strict mode names it.
  - Not proposed: Base by facts as a whole in the product setting. Its cost is known and large, and (a) to (c) aim at the same callees.

### 3.2 The attribute: compiled once, or for the type

**The entries:** GT-4, GT-5, GT-6, GT-7; open issues 159, 161, 162, 165, 182, 185; the closed build's rule (E-387); the two cast costs (E-374).

- **What is measured.**
  - Compiling once is the design's second source of saved compilation, and it works where it is used: NetworkDynamics' new equations 0.57 s against 6.6 s where the default did not apply (E-310).
  - It costs a call 8.3 ns against 2.38 ns where the caller knew the type (GT-6), and a pointer made in each session, 18 ms a member (GT-7).
  - A cast at a parameter no trait types has no effect, silently: NetworkDynamics' steady state was 2 times slower until its kernel was typed by the trait (GT-4, open issue 162).
  - A build cannot follow code compiled once that passes its argument on. So a build now compiles a trait argument for its type where the call knows it (E-387, mine): one rule for a session, another for a build.
  - The ports' code: 12 casts, 5 traits with a `Dynamic` default, `Dynamic{X}` written 94 times, no module option for the attribute at all.
- **What it shows.** The attribute answers one question (per type or once) through five steps ([traits §7.5](../reference/traits.md#75-what-decides)), and most of the ports' questions are about which step applied. The rules are each right; together they are what a newcomer will not hold in mind.
- **Proposal.**
  - (a) *Remove the steps no port uses:* the module's `dynamic` option and the scope's `first_seen`. Three sources are left: the cast at the call, the value (`Dynamic{X}`, a kept value), the trait's default with the method's `@nospecialize` and `@specialize`.
  - (b) *Keep the session's rule and the build's rule apart, and say so in one place:* a session compiles once to save compilation; a build has no later caller and compiles for the type. The results are the same. This is the choice of E-387; it should be the user's.
  - (c) *A cast without effect is an error of the definition-time check in a trait module,* not only a test's finding (open issue 162 (c) made the default): the silent case is the one that cost a port a factor of two.
  - (d) *`Dynamic{Callable}` without a signature* (open issue 159 (a)) and *`keep(f)` passed to plain code in `Callable`'s contract* (open issue 165 (a), (b), (d)): both are needed by every port that stores or passes on a user's function, and both are recommended and not built.
  - (e) *The `Callable` check on the value, not the name* (open issue 182 (a)): the built rule is unsound for an assigned copy or a captured function. To measure on the ODE port's solver first.
  - Not proposed: the attribute resolved by what the caller knows (GT-6's proposal) in a session. It would undo the saving of E-310 in exactly the case it was built for.

### 3.3 Checks: three kinds, three cost models

**The entries:** GT-2, GT-12, GT-16, GT-17; open issues 115, 116, 177; compiler C-30, C-41.

- **What is measured.**
  - The definition-time check: 0.65 s at a session's first edit since E-391 (2.6 s before), and 0.5 s at every later one. It infers the method and what it calls afresh each time (GT-12).
  - The member check: kept by an image when it passed; asked again in each session when it failed or no image ran it (C-30).
  - Strict mode's inference of an image's memberships at load: 67 ms on 180 ms (GT-2).
  - The fully typed check: 2 to 5 s for a small program, 4 to 11 s for a demonstrator's (E-369). It is asked on demand, and the mode raises only where the session sees a site (GT-16).
- **What it shows.** Each check is inference with a different interpreter, cache and time of asking. The one a user meets at every keystroke of an interactive session is the costliest per use.
- **Proposal.**
  - (a) *The definition-time check keeps its results as inference keeps its own,* with edges, ended as code is (GT-12 (b); C-41). An edit then infers the edited method only. This is the one change that moves what an interactive user feels.
  - (b) *Keep the two meanings of fully typed apart by name* (GT-17 (a)): what a build compiles, and code with no call dispatched at run time in a session. The second has no word now.
  - (c) *Keep GT-16's rule:* fully typed code pays nothing; the exact question is `fully_typed`'s, asked in tests and before a build.
  - (d) *Strict mode's default* is the question behind open issue 177 (c). It costs a load a third more. Recommended: off in a session, on in a package's tests and precompilation.

### 3.4 Memberships as methods

**The entries:** GT-1, GT-14, GT-18; open issues 178, 180; compiler C-88.

- **Settled by the round.** A membership invalidates as a method does (decided 2026-11-11), and it costs nothing that shows: no load time, nothing ended in composition, and since E-390 nothing at a port's load that the load does not end without it.
- **What is left.**
  - A membership is seen from its world (GT-14): a failure plain Julia's subtyping does not have, with a message that names a method and a world.
  - A union of a set with a type that later joins it is not followed inside a parameter (GT-18; C-88 (e)): unsound in a case no port or gate writes.
  - A membership cannot be taken back (open issue 180 (c)), so Revise does not work on memberships.
  - The walk stays conservative for a `Vararg`, the set in several places, and a bound the signature sets (C-88 (c)).
- **Proposal.** (a) The hint on that `MethodError` and `TypeError` (GT-14 (a)). (b) GT-18's limit stated in the reference (its (a)). (c) The walk for a removal (180 (c)): it is the one item here a daily user would miss. (d) The forwarding member's own methods removed (178 (a)): the round shows the trait's method costs nothing there.

### 3.5 Builds

**The entries:** GT-13, GT-15, GT-17; open issues 179, 181, 184; compiler C-86.

- **Settled.** A closed build compiles generic code for the members it has, found by use. The table program builds. The check in a session is the build's own.
- **What is left.** The ODE program's 50 errors: 38 are the solver core's callbacks, operations on values of traits that have no member in a program without callbacks (184 (a)); the rest are a family's member that no image checked (184 (b)), Rodas5 and a sort. Below every trait program, Base (§3.1).
- **Proposal.** (a) An operation on a value known by its trait, in a program with no member, compiles to the `MethodError` it would raise (184 (a); C-86). (b) The check in a session runs a family member's check as the build's queue does (184 (b)). With both, the program without callbacks should build: the next demonstrator to count. (c) `invokelatest` under the closed rules is the call (181 (b)).

### 3.6 What to weigh for removal

- **The code slot** ([compiler §3.3](../reference/compiler.md#33-the-code-slot)). It keeps a caller whose callee is compiled again to an equal result.
  - *Its cost:* a slot per call site, marks and revalidation in the runtime, result edges in the compiler; 8.5 % on an image build's test, 15 % more machine code in TraitWorld's image (E-283); and the defect of E-389 came from it.
  - *Its benefit, measured for this synthesis* (E-393): with the marks off in the session, upstream by facts loses the same 14 own image instances and one more of the work's; the forks lose 49 where they lost 48; the ODE session is the same. The work after the loads is no slower without the marks (1.52–1.61 s against 1.71–1.73 s; 2.15–2.18 s against 2.22–2.25 s).
  - *What that does not cover:* a session with edits (Revise's redefinitions to an equal result), which is what the slot was designed for and no workload of the round does; and the slots stay in the images in this control.
  - *Proposal:* measure a session of edits with and without the marks. If it shows nothing either, retire the slot: one mechanism less in the compiler, the runtime and code generation, and one less in the stack proposed upstream.
- **The attribute's module and scope options** (§3.2 (a)): no port uses them.
- **The member's own forwarding methods** (§3.4 (d)).

## 4. The transition

- **The path's first step carries most of the gain** (E-392). A package's code compiled by facts as it is, by one line per module:

  | Upstream CSV and DataFrames | first work | after nine unrelated loads | own image instances lost |
  |---|---|---|---|
  | plain | 4.13–4.26 s | 5.17–5.29 s | 424 of 4,693 |
  | by facts, one line per module | 1.88–1.89 s | 1.71–1.73 s | 14 of 3,490 |
  | the forks (ported) | 0.18–0.19 s | 2.22–2.25 s | 48 of 4,799 |

- **So the guideline's order is right, and its claim should be sharper:** step one is safe and large; a port buys first work (ten times again) and typed interfaces, and must then mind its entry chain (§3.1).
- **A front end.** A port's core wants a typed front end; an ecosystem's API accepts everything. Recommended (open issue 185 (a)): the core typed, the umbrella package a thin shim in upstream's names. This answers the user's question of 2026-11-14; it is not built.
- **What a port should not do** (GT-10): turn an ecosystem-wide abstract type into a set to cure one slow step. `IO` showed it.
- **The ports' open questions** that a second port of each kind would meet again: 157 (a function barrier), 159 (a stored function), 162 (a silent cast), 165 (a function passed on). §3.1 and §3.2 propose an answer to each.

## 5. The choices marked mine

Open issues §1 lists about ninety. They stand as recorded. Those with the most weight on the design, for the user to look at first:

| The choice | Why it has weight | Where |
|---|---|---|
| A closed build compiles a trait argument for its type wherever the call knows it | A build and a session now decide the attribute differently | compiler §7.6; E-387 |
| The membership walk substitutes the member below a position's top | The guarantee's soundness rests on it; 200 lines; a first version was unsound and caught by its gate | compiler §5.5; E-390 |
| A `Callable`'s check is decided by the declaration, by the argument's name | Unsound for a copy or a captured function (C-90) | compiler §7.4; open issue 182 |
| Kept values: the storage's type decides, with `Kept{X}` | The user decided the rule; the mechanism is mine | traits §7.8 |
| `All{X, Y}` as an abstract type of Core, with branches wherever a type's name is read | The widest change to the runtime's type code | compiler §4.9 |
| No method of Base carries the boundary flag | §3.1 proposes to use it | compiler §2.2 |
| Strict mode reports and never refuses at an image's load | It decides what strict mode is for | traits §12.3 |
| The check for a build is the build's own code, with the build's Base as an overlay | "Fully typed is what compiles ahead" holds through it | compiler §2.7; open issue 181 |
| The definition-time check runs in inference's world, with an explicit list of entries in the compiler's bootstrap | The list must follow the compiler's internals | compiler §6.7; E-391 |
| An instance's code is compiled once per result | It repairs the code slot's defect; §3.6 asks whether the slot stays | compiler §3.3; E-389 |

Two are unsound in cases no port or gate writes, and their fixes are design directions: C-88 (e) (GT-18) and C-90 (open issue 182).

## 6. What the evidence does not show

- **Scale.** The largest workload is NetworkDynamics' (44 s). The loads are nine packages. One machine, lightly loaded.
- **The round on the head.** Three fixes landed after the freeze. What each touched was measured again; the rest was not.
- **A cache across sessions.** Not built (the user, 2026-11-14). The round's judgment: it would serve the session's own code and Julia's methods at its signatures, which is plain Julia's case too, and three small trait costs (a membership declared in the session, the pointers of code compiled once, a failed check).
- **Teaching.** No reader from outside has used `intro/`.
- **The second port of anything.** Each ecosystem was ported once, by the design's author. The ports' questions are the best evidence there is of what a second author would meet.
- **Three tensions have no number on this build:** GT-5, GT-10 (`IO` is no set now), GT-18.

## 7. Decisions for the user

Each has a recommendation. None blocks the upstream patches (W-19), which stand without traits.

1. **Base's surface as the design's object** (§3.1): typed at the signatures typed code calls, the boundary flag where a port's entry chain goes through Base, the sets on Base's functions Base's own. *Recommended: yes; start with the boundary flag on the forks' two instances, as a measurement.*
2. **The attribute's rules** (§3.2): remove the module and scope options; a cast without effect is the check's error; build `Dynamic{Callable}` and `keep(f)` in `Callable`'s contract. *Recommended: yes to all three.*
3. **A build compiles for the type, a session once** (§3.2 (b); E-387). *Recommended: confirm.*
4. **The definition-time check keeps its results** (§3.3 (a)). *Recommended: yes; it is the largest cost an interactive user meets.*
5. **The code slot** (§3.6): its marks keep nothing that shows at unrelated loads (E-393). *Recommended: one more control, a session of edits; retire it if that shows nothing either.*
6. **A membership taken back** (§3.4 (c)), so that Revise works on memberships. *Recommended: yes, before any reader from outside.*
7. **The next demonstrators:** the ODE program without callbacks through a build (§3.5), and a reader from outside for `intro/` (G-8). *Recommended: both, before more ports.*

## 8. Addendum (2026-11-22): the iteration assessed

Written by the round's agent (W-159) from the round at the freeze `round-2026-11-c` (julia `next` cf0f039f51, TraitWorld `unified` 42d60e1; E-511 to E-528; `experiments/implementation/w159/README.md`) and the iteration's experiments (E-401 to E-510, E-529, E-530). Each number names its experiment. A comparison with the tag `prototype-2026-11` is the regression control (E-524 to E-526); the standings against plain Julia are in [the goals](../goals.md) §2 and [the evidence](../design/evidence.md).

### 8.1 Each tension

**Closed in the iteration.**
- Before the round, by decision and build: GT-1, GT-4, GT-6, GT-10, GT-11, GT-13, GT-15, GT-17, GT-18, GT-19, GT-23, GT-24 (the open issues' ledger, "Closed by the pass of 2026-11-18").
- GT-31, by its criterion: strict mode refuses case 05's pirate at the user's line (E-518).

**Smaller.**
- GT-12 (the check at each edit): the table's first edit is defined in 0.235 s, the second in 9.3 ms; the plain twin 70.5 and 6.7 ms (E-512). At the control 0.69 and 0.51 s (E-524). The criterion for "smaller" (under 0.35 s) is met.
- GT-3 (the compiler compiled plainly), in its load count: upstream's load ends 132 of the compiler's instances against vanilla's 122 (E-516); at the control 615. The session's and inference's cost not measured again (E-386, E-389).

**Standing, with the round's cost.**
- GT-2: strict mode adds 40 % to TraitTables with TraitCSV's load, 215 against 153 ms (E-516); the criterion was under 10 %.
- GT-8, larger: the forks lose 150 of 5,705 own image instances to nine loads (2.6 %), their work after the loads 12 times their first (E-511); at the control 48 of 4,799 (E-524). The library's own hooks are lost the same way: 15 instances at a port's load (E-516; open issue 254).
- GT-9: plain code's first work 0.07 s above vanilla's (E-515); at the control it is 0.37 s below vanilla's (E-525). After the bisection's first step three commits are left: the G2 bit for the deep class (D-5), a split's inlined branch naming its CodeInstance, the code slot's removal (D-7) (E-527). **The bisection is done (E-527):** one commit, the code slot removed (D-7): the commit before it does the first work in 2.88 s, as the control; with the slot gone 3.36 s; vanilla 3.26 s.
- GT-32: the ODE port writes 19 `@implement Callable` (E-522); the forks' suite has one error, `ByRow(Dict)` (E-523; open issue 240).
- GT-5, GT-7, GT-14, GT-16, GT-21: not measured in the round; their costs stand as recorded (E-340, E-443, E-362, E-369, E-416).

**New.**
- GT-33 (every declared result read at a trait checked where it is passed on): 56 marked instances and 20 checks in the report's session, 13 and 2 in the table's; the compiles unchanged; no time (E-530).

### 8.2 Each decision of the plan

| | What it gave | What it cost |
|---|---|---|
| D-1 one way to erase | the attribute's surface in the library from 88 lines to 24 (E-504); Julia 1,116 lines removed, 218 added (E-506); known types at a plain call's 0.79 ns, `compiled_for` at 2.38 ns as plain (E-513); NetworkDynamics' steady state 312 against the control's 427 ms (E-514, E-524) | a plain member boxed at each call: 8.66 ns against 2.38 ns with `compiled_for`, and against 7.88 ns at the control (E-513, E-524); the annotations did not fall (8.4) |
| D-2 `Callable` a contract at the box | subtyping reads no method table; no guard pair needs dispatch by signature (E-500); the wrapper 0.79 ns, against 1.34 ns at the control (E-513, E-524) | the box by default 25.25 ns a call (E-513); 134 of 174 callable types in the forks' session need a declaration (E-500; GT-32); a type passed as a constructor is no member (open issue 240) |
| D-3 bounded means fully typed at the box | the edit's check reads the box's instance: GT-12 smaller (E-512) | the verdict depends on the optimizer: a reading of the method as written costs 1.8 to 2.3 times (E-529; open issue 251); the member's check at its instances not built (traits T-129), so GT-2 stands and GT-33's mark is needed |
| D-4 a required operation is an entry of the contract | the library's late load ends 0 of 120,780 plain instances (E-515); 209 at the control (E-525) | a call outside an operation's declared signature is Julia's `MethodError` with a hint: 11 lines, 752 bytes, against plain Julia's 6 lines, 353 bytes (E-518) |
| D-5 G2 is the deep class | no unrelated load ends an instance in the class (E-478); upstream by facts loses 0.4 % (E-511) | the guarantee reaches the class: 63.1 % of the forks' own facts instances, 79.0 % of upstream's (E-478); the forks lose 2.6 % (E-511); its commit is among the three the bisection leaves (E-527) |
| D-6 a call that only throws is a run-time site | not built (GT-21) | the share it would add rests on plain callers: 1,983 to 1,986 of 4,799 from facts code, 2,917 from every caller (E-416) |
| D-7 the code slot retired | no instance lost and no time at unrelated loads without it; TraitWorld's image 5.29 against 5.33 MB (E-419) | plain code's first work: 0.46 s more than the commit before it (E-527), which brings the build from 0.38 s under vanilla's to 0.07 s above it; before the bisection the note read: its commit is among the three the bisection leaves (E-527) |
| D-8 Base's surface by the census | the deep share from 41.8 % to 63.1 % (the forks), 39.6 % to 79.0 % (upstream by facts) (E-478) | plain code: nothing measurable, the system image +0.16 % (E-479); the long tail is open issue 218 |
| D-9 owner-only functions | run-time sites at a package's own helpers: the trait demonstrators 0 of 136, the forks 134 of 8,128 (E-458); TraitMakie's eleven asserted barriers removed | a sibling package's method of a core's internal interface is a pirate's (open issue 212) |
| D-10 one statement of what is final | the closed build's rules follow from it; the five programs build with 0 errors (E-519) | compiler C-156's rows; no number |
| D-11 a membership adds no type equality | the gate 33 of 33 (E-456) | none measured |
| D-12 a pirate reported by default | the report, 21 checks, no measurable cost at the nine loads (E-457); case 05 reported, and refused under strict mode (E-518) | none measured |
| D-13 a membership taken back | 27 of 27 checks (E-459) | none measured; Revise itself untested (lowering L-64) |
| D-14 the prune list | fewer forms in the references and the library | no experiment measures it |

### 8.3 What the iteration did not move

- **G-3:** no cache across sessions, and no new measurement of what an image holds against a session (E-521 restates E-372's classes; open issue 228: an instance in the image without code, E-528).
- **The annotations a port writes:** from the control to the freeze, TraitTables 4 to 5, the forks 5 to 6, the ODE port 24 to 30, TraitReport 2 to 0, NetworkDynamics 3 to 1; the ODE port's boxes 78 to 85, its `unwrap` 7 to 18 (E-526). "Few annotations" is not shown.
- **Plain code's first work:** 0.07 s above vanilla's (E-515), where the control was below it (E-525); the bisection decides which commit (E-527). **The bisection is done (E-527):** one commit, the code slot removed (D-7): the commit before it does the first work in 2.88 s, as the control; with the slot gone 3.36 s; vanilla 3.26 s.
- **G-8:** teaching is not tested.

### 8.4 For the next synthesis

- **The cost of the mark (GT-33):** the narrower mark (the members' check made to reach each case) against a time for one call that passes a result on, which E-530 does not have.
- **The bounded check's verdict and the optimizer (open issue 251):** a verdict per method as written costs 1.8 to 2.3 times the check (E-529); its cost at an edit is GT-12's.
- **The forks' loss to unrelated loads (GT-8):** 2.6 % lost and the work after the loads 12 times the first (E-511), through Base's `vcat` and `open`; Base compiled by facts, the boundary flag, or Base's surface by the census (GT-8 (a) to (c)), and open issue 218.
- **The library's runtime on Base's plain code (open issue 254):** its hooks rest on Base's plain callees at abstract types and are compiled again at a port's load (E-515, E-516); whether the library is held to the deep class by its own porting rule, with a gate, or its runtime is treated as Julia's own code.
