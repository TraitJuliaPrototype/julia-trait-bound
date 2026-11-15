# Review: the conceptual design after the complete prototype (2026-11-15)

**Asked by the user (2026-11-15):** "Last night we finished the conceptually complete prototype. There is a synthesis report. Please review the overall conceptual design of the project thoroughly, given the learnings and tensions recorded. Come up with principled suggestions for large scale, architectural and conceptual design changes that have a chance of removing tension. Nothing is off the table. Do not run code, just write the review and suggestions."

**How it was done.** In the main session, by reading. No code was run, and no subagent was used.
- Read: [the goals](../goals.md), [the synthesis](../plans/2026-11-14-synthesis.md), [the rationale](../design.md), the four [references](../reference/README.md) with their deviation tables, [open issues](../open-issues.md) §1 and §2, [the alternatives](../design/alternatives.md), [the evidence](../design/evidence.md)'s rows for the round and the head, [the state](../state.md), and the ports' sources for their casts (by `grep`).
- Every number is the evidence's, with its experiment. None is new.
- A statement about the code that no reference makes is marked *reasoned*.

**Status.** Proposals for the user, beside the synthesis' seven decisions. Nothing here is in force. Several proposals reverse decisions of the user; §7 lists them.

## 1. In brief

**What holds, and should stay:** the facts rule, ownership with Lemma O, G1 and G2, a trait as an abstract type with a checked contract, a membership that behaves as a method does. The evidence supports each (§2).

**The diagnosis.** The eighteen tensions and the ports' questions are not eighteen problems. Most come from four places where the design holds two of something, and rules to translate between the two:

| | The two | What joins them | The tensions it carries |
|---|---|---|---|
| R1 | two compile policies in one cache: facts and plain | result edges, the code slot, the boundary flag, the policy "of the code that reaches it" | GT-3, GT-8; open issues 99, 125, 157, 179; the code slot |
| R2 | two ways to erase a trait argument: the attribute, and the box `Dynamic{X}` | five steps, casts, `keep`, `Kept{X}`, `kept_call`, three `detect_…` tools | GT-4, GT-6; open issues 159, 161, 162, 165, 182, 184 (e), 185; E-387 |
| R3 | two homes for a contract: the trait's `TypeName`, and a method at the trait per operation | the specificity rule, `OperationError`, forwarding members' own methods, the refusal of an untyped serving method | GT-11, part of GT-9; open issues 150, 178 (a) |
| R4 | two rule sets for inference: a session's and a closed build's | a check that runs one inside the other, an overlay of Base, a list of closed rules | GT-13, GT-15, GT-16, GT-17; open issues 181, 184 (a), (b); T-100, T-104, T-109 |

**The synthesis** answers each at its symptoms: a flag on the Base methods a tool names, two of five steps removed, a cache for the check, the two rule sets "kept apart, and said so in one place". This review proposes to remove the duplication itself.

**The proposals,** in the order of what each deletes:

| | Proposal | Removes | Costs, or reverses |
|---|---|---|---|
| P1 | **One way to erase: the box, at the door.** Every trait is treated as `IO` is: code per type by Julia's rule, and an eraser type the author uses at the entry | R2 whole: the attribute, the casts, `keep`, `Kept{X}`, the trait's default | the caller's override at a call; "compiled once" by default; five decisions of the user |
| P2 | **Bounded means fully typed at the box.** The definition-time check is a reading of the instance compiled for `Dynamic{X}`; a member's check is a set of kept instances | GT-12, GT-2; C-40, C-41; open issues 115, 165, 184 (b), (c) | a wider meaning of "bounded" |
| P3 | **One criterion in place of two policies:** deep G2, asked for by the caller | GT-8 by rule; the boundary flag as a list; the code slot | facts copies of Base where Base speculates; types lost at those places until Base is patched |
| P4 | **The contract on the trait, not in the method table:** a required operation is no method | GT-11 for required operations; open issue 150; 178 (a) | `OperationError` |
| P5 | **One inference, and what is final.** A session and a build differ in one input; owner-only functions as ownership's own finality | R4's list of rules; GT-17; open issues 157, 99 at a package's own barriers | decision 3 of session 27, in an enforced form |
| P6 | **G2 collected at a load:** an image's deep-G2 code validated by who could have changed it, not edge by edge | validation's share of a load (31–45 %, E-388) | a soundness argument of its own; E-325's caveat |
| P7 | Smaller: a witness in the box; "a membership adds no type equality"; `Callable` as a contract at the door; a pirate reported by default; the prune list | GT-7, C-38; GT-18; C-90, 182, 184 (d); 177 (c) | each named in §4.7 |

**The largest single finding:** the ports' own casts undo the design's default, and the `IO` work already decided the question by measurement (§4.1). P1 is that decision applied to every trait.

## 2. What the evidence settles

These need no change. A next iteration should protect them.

- **The facts rule, on code as it is written.** One line per module: first work 1.88–1.89 s against 4.13–4.26 s, after nine unrelated loads 1.71–1.73 s against 5.17–5.29 s, 14 of 3,490 own image instances lost against 424 of 4,693 (E-392). This needs no trait.
- **Ownership as the one rule of who may change what.** It carries Lemma O, strict mode, and since 2026-11-11 memberships. Where a second rule stood beside it ("a membership invalidates nothing", finality by time), the record replaced it by ownership.
- **A membership behaves as a method does.** No load time, nothing ended in composition (E-378), nothing at a port's load beyond what the load ends without it (E-390).
- **A trait is an abstract type.** Struct parameters bounded by a trait, `Vector{<:Shape}`, `isa`, methods at traits beside methods at types: none of this exists with traits outside subtyping. Its price is in the runtime (`All`, the walk, GT-9, GT-18) and cannot be designed away. §4.7 (b) adds one rule to it.
- **A contract checked at the membership, with declared results.** It is what gives a call at an abstract position a type without speculation, and the errors of E-362, E-370 and E-385.
- **Types first in dispatch** (traits §6.2). It is what lets a library adopt traits a function at a time.

## 3. The diagnosis

### 3.1 R1: two policies, joined by edges that leak

- A neutral method has plain code only (compiler §2.3). So code compiled by facts rests on plain code of Base.
- The G2 predicate is one level deep: every dispatch edge at a fact, every inlined callee's record G2, and "result edges may go anywhere" (compiler §3.2). The code slot was to cover what lies below a result edge (§3.3).
- **Measured:** every own instance a load ends, for upstream by facts and for the forks, is reached through a plain callee in Base (E-355, E-392). The slot's marks keep one instance and no time (E-393). The forks' two instances cost 0.49 and 0.40 s.
- **The irony the round shows:** the port is behind the package compiled as it is after unrelated loads (2.22–2.25 s against 1.71–1.73 s). More typing gives more static edges into Base. While Base may speculate below them, more typing is more exposure.
- G2's scope carries the exception "a facts caller's code edges into plain code" ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). Wrapping by facts, as first stated, had none: the code, *and every callee compiled for it*, rests on facts only ([alternatives](../design/alternatives.md), "Layering and its workarounds"). The unified build gave that up for the cost of Base's facts copies (open issue 125).

### 3.2 R2: two ways to erase, and a bit that no type carries

- **By attribute:** the method's instance compiled once at the trait; the object is passed as itself; five steps decide (traits §7.5), with bits beside the call (compiler §6.3, §6.9).
- **By box:** `Dynamic{X}`, a concrete type that holds a member.
- **They differ in meaning, not only in speed.** Through the box a call `g(d)` selects `g`'s method for the box; the object's own type and its other traits are not seen (traits §7.7). Through the attribute, a call that passes the argument on dispatches on the object. `keep` turns one into the other by what the caller knew. Open issue 165's `sum(keep(t))` is this: a `MethodError` under one attribute, a result under the other. So "both run the same methods and give the same results" (traits §7.4) already fails wherever a box appears.
- **The attribute is in no type, so it is lost wherever only types travel:**
  - an untyped parameter (GT-4, open issue 162);
  - a record made before the signature is known (159);
  - a library's own type around a user's function (161);
  - a closure, a generator, a higher-order function (165);
  - storage (`Kept{X}`, `kept_call`, `detect_kept_storage`);
  - a build (E-387: one rule for a session, another for a build).

  Six questions of the ports are one question: where did the bit go.
- **The ports' casts undo the design's default.** In TraitTables and TraitCSV, every cast in library code is on a value the code knows only by its trait, read from storage or returned by an operation: `take(compiled_for(c), idx)`, `summarize(compiled_for(t.cols[k]), …)`, `sortperm_col(compiled_for(column(t, name)))` (TraitTables `src/TableCore.jl` 75, 90, 188), `fillcolumn(compiled_for(emptylike(c)), …)` (TraitCSV `src/CSVCore.jl` 123). Each asks for what a plain Julia call does at a value of unknown type: dispatch once, then run the code for the type. The cast is needed only because a trait module's fallback makes such a value `Dynamic` (step 5). NetworkDynamics' kernel cast on its boxed model (162) is the box's form of it: an `unwrap` at a call.
- **The counts agree** (the synthesis §3.2): `Dynamic{X}` written 94 times, 12 casts, 5 traits with a `Dynamic` default, no module option. The ports erase by the box.
- **The record decided this once, by measurement.** `IO` as a trait compiled once: the goal's task 15.8–16.1 s against 4.08–4.28 s (E-330). What held: code per stream type as in Julia, and an eraser type, `IOContext{IO}`, used by the author at the entry (traits §9b; GT-10: "The fix that held is a contract on the closed type, chosen by the author who erases").

### 3.3 R3: the contract is stored as methods

- `@trait` defines a method at the trait for each operation and arity ([lowering §2](../reference/lowering.md#2-trait)). It carries the declared result, forwards for `Dynamic{X}`, holds a default's body, and otherwise raises `OperationError`.
- For a required operation that is Base's function, that is a method at an open set on Base's function. In the record:
  - GT-11: at a late load `length(::HasLength)` ends 191 log entries, `iterate(::Iterable{T})` 71, `haskey(::Keyed, ::Any)` 10 (E-356); 209 of 122,403 plain instances (E-381);
  - method matching costs 7–25 % more with a method at a set on Base's hottest functions (E-269; part of GT-9);
  - open issue 150: the trait's method hides `mul!`'s untyped fallback, so `LinearOp` has a function of its own, `apply!`, and a method that takes any receiver "does not serve" (traits §5.10);
  - a forwarding member's own methods (178 (a)); a further argument "typed only where it binds an input", found by an ambiguity with Base's `haskey` (lowering §2).
- The contract is already kept on the `TypeName`, for a set and for a closed type (compiler §4.1, §7.1). Its entries point at methods. So the other home exists; it does not yet carry a declared result by itself.

### 3.4 R4: a session's rules and a build's rules

- A closed build has a list of rules of its own (compiler §7.6): the attribute's defaults turned, the split over every member, a cast that branches, `Core.attributed_call` refused, code inferred again in rounds.
- "Fully typed" means what a build compiles, which is wider than code with no run-time site in a session (GT-17). The mode raises only where the session sees a site (T-100, GT-16). The check is the build's code run in the session, against an overlay of the build's Base (181); it agrees on 17 of 18 programs (E-384).
- A trimmed build compiles every method plainly (facts §13.3). So a binary's code is inferred by another rule than the session's code compiled by facts.
- The three rules (facts, plain, closed) differ in one thing: which calls count as settled. The references state them as three mechanisms.

### 3.5 Checks: one question asked by four engines

- The member check, the definition-time check, strict mode's inference at a load and the fully typed check are each an inference with its own interpreter, cache and time of asking (the synthesis §3.3).
- Two refusals are one operation. Strict mode refuses a method that would end code compiled by facts. The override rule refuses a method that would end a member's check (traits §5.10, §5.11). Both are "a definition that would invalidate protected code is refused". They are built twice: a walk over backedges for the first, "one intersection per kept call under the function" for the second.

## 4. The proposals

### 4.1 P1: one way to erase: the box, at the door

**Every trait is treated as `IO` is.**
- **A method at a trait is compiled as any Julia method:** for the argument's type. `@nospecialize` means what it means in Julia. A value of unknown type passed to a method dispatches once and runs the code for its type: Julia's function barrier, with no cast.
- **`Dynamic{X}` is the trait's eraser:** a concrete member of `X`. Code that receives one is compiled for it, by Julia's rule: once per trait instance. It stays erased wherever it goes, through untyped parameters, closures, records and storage, because it is a type.
- **A library erases at its doors:** `solve(m::Model, u0) = _solve(Dynamic{Model}(m), u0)`; a `Network` boxes its models where it is built. `unwrap(d)` at a call is the barrier back to code per type.
- **A caller who wants code for the type calls past the door,** at the typed core. Open issue 185 (a) recommends this split of core and umbrella already.
- **Storage:** a struct parameter bounded by a trait records the choice in the struct's type, as now (traits §8.2). Storage typed by the trait holds a member or a box; each carries its own choice by its type. `Vector{Dynamic{Shape}}` is the erased collection, as Rust's `Vec<Box<dyn Shape>>`.

**What leaves the design:** steps 1, 2, 4 and 5 of traits §7.5; the casts and `Core.attributed_call`; `keep`, `Kept{X}`, `kept_call`; `@default_dynamic`, `@default_compiled`; the module options `dynamic` and `first_seen`; `detect_unused_casts`, `detect_kept_storage`, `detect_dynamic_fallbacks`; step 4's exception with C-55; C-56; L-56; the closed build's attribute rule; W-148's rule (a `where` variable is Julia's: the type of what was passed).

**What it removes.**
- GT-4 and 162: a box and `unwrap` are values and pass any parameter.
- GT-6: a typed caller gets code for the type, except through a door, which is written.
- 159: a record stores what it is given; the door that knows the signature erases. Upstream SciML's specialization levels (`FullSpecialize`, `NoSpecialize`) are such a door's argument.
- 161: the library boxes at construction. That was option (c), rejected as "a port built around the rule". Under P1 it is the rule.
- 165: in erased code `f` is a box, so `map(f, xs)` is a call at a concrete signature (with P2).
- 184 (e), 185, and E-387's split: a build compiles what is written.
- Half of 182: `Dynamic{Callable{A, S}}` checks every call, however it is called; a function passed as itself is Julia's.
- **Erased code becomes fully typed.** A call that passes a box on is at a concrete signature: a fact. Code compiled once that passes its argument on holds a run-time site today (compiler §6.3), which is why a build could not follow it.

**What it costs.**
- **No override at a call.** `compiled_for(x)` leaves the language. G-2's claim becomes: code for the type is the default; a library that erases says where, and offers the entry that does not.
- **Nothing is compiled once unless a door says so.** A new model type at a typed core compiles the core, as in Julia and in Rust. E-310's 0.57 s against 6.6 s came from the port's `keep` at construction and a cast at its kernel; under P1 the same shape is a box at construction and `unwrap` at the kernel.
- **`Callable`'s default goes too.** A function is compiled per function type unless it is boxed.
- **The box is a restricted view.** It is so today (traits §7.7). What varies by member must be an operation, as in Rust and Swift. "Both attributes give the same results" is replaced by P2's statement: a bounded method gives the same results for a member and for its box.
- It reverses decisions of the user (§7).

**If the override must stay (P1′).** One default and one cast, with nothing carried: a method's `@nospecialize t::X` means that the method erases at its entry (its body runs on `Dynamic{X}(t)`), and `compiled_for(x)` at a call skips that one method's erasure. No trait default, no fallback by scope, no `keep`. Below the door everything is Julia's. A cast at a method that does not erase changes nothing, and costs nothing: the value is compiled for its type anyway.

**A probe (not run).** The subset exists in the build. TraitTables' `TableCore` and NetworkDynamics' batch kernel written with boxes and `unwrap` only, in a module with `first_seen = false` and no trait default; E-310's, E-314's and E-374's rows again; the count of annotations before and after.

### 4.2 P2: bounded means fully typed at the box

**With P1.**
- **A method is bounded at a trait argument when its instance for `Dynamic{X}` is fully typed there and makes no call that finds no method.** That instance is ordinary code at a concrete type, inferred by the native interpreter under the facts rule, cached with edges, kept by images.
- **The definition-time check reads that instance's record.** It is no second inference: no check interpreter (C-40), no classification kept apart from the code (C-41), no list of exempt forms (constructors, equations' functions, `like`).
- **What it certifies:** behind the box only the contract's operations reach the member, and each member is checked to serve them. So the method works, erased, for every member that will ever join. This is Rust's check of a generic body, with the box as the archetype, and the archetype is a real type.
- **`sum(t)` is then judged by what it does.** At a box of `ColTable` Base's `sum` reaches `iterate(::Dynamic{ColTable})`, which has no method: the report names `iterate`, reached from `sum`. At a box of an `Iterable{Float64}` the same call is bounded, and Base's `sum` is compiled once for the box. No list of BaseTraits algorithms is needed for that.

**The member's check, the same way.**
- The instances of a member's serving methods at the declared argument types are compiled ahead anyway (traits §16). The check is their inferred results against the declared ones.
- Kept as instances, with edges, they are validated at a load by Julia's validation. Strict mode infers nothing again (GT-2: 67 ms on 180 ms, E-382). A method below an operation's body that widens a result ends the check through its edge (open issue 115's proposal).
- "A method that would end a kept check is refused" is then strict mode's walk, run for check instances: one mechanism for §3.5's two refusals.

**What it removes.** GT-12 (an edit infers the edited method, once, in the cache: 0.5 s at every edit today, E-391); GT-2; C-40, C-41; open issues 115, 165, 184 (c) (a keyword method is inferred as any), 184 (b) (a session and a build read the same kept instances).

**What it costs.** "Bounded" widens: `typeof(t)` and `Wrapped(t)` are bounded, since they act on the box. That is consistent: the classification's other purpose, code per key, is deferred (§4.7 (e)).

**Without P1,** the same idea holds in a weaker form: the check reads the record of the instance compiled once at the trait, where a run-time site with an argument typed by the set is the use outside the contract. *Reasoned;* not checked against `classify.jl`.

**A probe (not run).** `check_definitions` against `fully_typed(f, (Dynamic{X}, …))` over TraitWorld's suite and the ports' trait modules: where the two verdicts differ, and why.

### 4.3 P3: one criterion in place of two policies

- **Deep G2:** a CodeInstance's record is deep G2 when every dispatch edge is at a fact signature and every callee it holds any edge to, code or result, is deep G2.
- **A request from code compiled by facts asks for a deep-G2 instance.**
  - A plain instance that is deep G2 serves it as it is. For fully typed code, inference by facts is plain inference (design §2.3), so most of Base's code at concrete signatures is shared, not copied. This is open issue 125's first proposal.
  - Where the plain instance is not deep G2, the callee is inferred by the facts rule for that caller. It is the test bed's rule for a neutral method (compiler §2.5), applied to static calls from code compiled by facts, and to nothing else.
  - A run-time site keeps reaching plain code: it holds no edge.
- **Policy is then no property of a neutral method.** A module's `facts` option says that its methods ask. An instance has a property, not a policy.

**What it removes.**
- GT-8, by rule. G2's scope loses its exception, and the rule holds as first stated (§3.1).
- The boundary flag as a list chosen "by measurement, not a rule of the design" (compiler §2.2). The synthesis' decision 1 puts the flag on the methods `cause.jl` names for a port; that list changes with every environment.
- The code slot (compiler §3.3, C-64 to C-69): no facts caller rests on a callee that can be compiled again to an equal result. Its cost: 8.5 % on an image build's test, 15 % more machine code in TraitWorld's image (E-283). What is left of its purpose is plain code under Revise, which is not this design's claim.
- Strict mode's walk "through the plain code of rule 2" (facts §11.2), but for the compiler's own code.

**What it costs.**
- **Facts copies of Base where Base speculates.** At an image's build: the part of Base's reached code that is not G2 as plain code is 0.9–4.4 s per image (E-266). In a session, for what no image holds: 0.24–0.34 s on the earlier build without sharing (open issue 125).
- **Types.** In a facts copy, a place where plain Base speculated is a run-time site with the result `Any`, and callers above it lose their types (open issues 99, 157). That list is Base's surface: E-368's tool finds it (five functions hold 73 % of the holes). Each entry is a patch to Base that stands without traits, or a declared result (§4.5).
- It reverses, in a form that shares, the unified build's choice against a second owner ([alternatives](../design/alternatives.md), "The unified build").

**The gate that goes with it:** Base is deep G2 at the signatures typed code calls it with. Open issue 179 states this as a desirable; under P3 it is what the guarantee rests on, and the audit is a gate.

**A probe (not run).** E-392's forks with the boundary flag on every callee below the two entries whose record is not deep G2: the instances lost, the work after the loads, and `fully_typed` on the two entries to see what lost its types. It is the synthesis' first measurement, read as a test of the rule.

### 4.4 P4: the contract on the trait, not in the method table

- **A required operation is an entry of the contract and no method.** The entry carries the declared signature and result. At a receiver typed by the trait, inference reads the declared result from the contract on the `TypeName` (compiler §4.1), where it reads the trait's method's flag today (§6.8). The call dispatches to the member's own method.
- **`Dynamic{X}`'s forwarding is a method at `Dynamic{<:X}`:** a concrete family the library owns, as any package's method at its own type.
- **A default stays a method at the trait.** It has a body, and every caller reaches it (traits §4.2).

**What it removes.**
- GT-11 for required operations. BaseTraits' operations on Base's functions (`length`, `iterate`, `getindex`, `haskey`) are all required.
- The share of GT-9 that is method matching with a method at a set on Base's hottest functions (E-269).
- Open issue 150: a member's untyped fallback serves. `mul!` can be `LinearOp`'s operation, and the rule "a method that takes any receiver does not serve" goes.
- 178 (a): no trait's method to stand beside a forwarding member's own.
- `OperationError`, and lowering §2's rule for which further arguments the trait's method types.

**What it costs.** A call of an operation outside its declared signature raises Julia's `MethodError`, with a hint from the contract. *Reasoned:* that the split's fallback and the table need no method at the set; I did not check the code.

**A probe (not run).** `w134/probe_insert.jl` with BaseTraits' required operations as contract entries: E-381's 209 instances again.

### 4.5 P5: one inference, and what is final

**The observation.** The three rules differ in one input.
- A call is inferred across where its dispatch is **settled:** only a stakeholder or a pirate can change it, or nothing can.
- **Facts in a session:** nothing is final but what Julia fixes (a closed type's negatives, the types that are never members). Settled is a fact signature.
- **A closed build:** every set and every function is final. Every call the build can list is settled.
- **Plain inference:** everything is taken as final, and invalidation repairs it.

**The proposal (a): state it so.**
- Compiler §7.6's rules follow and are not listed: the split covers every member, because the list is final; an operation on a set with no member is a "no method" fact, and raises (open issue 184 (a), C-86's last clause); a call in the latest world is the call (181 (b)); a call at `Any` with one method resolves (GT-17).
- "Fully typed" has one definition with the setting as its parameter: fully typed in a session, and fully typed when closed, which is what builds. GT-17's two words fall out, and GT-16's rule stands as it is.
- A trimmed build is then the facts rule with everything final, not a third policy (facts §13.3).

**The proposal (b): owner-only functions, ownership's own finality.**
- A function whose methods only its owner may define. A method of it by anyone else is a pirate's, whatever types it names.
- Then every call of it, at any signature, is settled by ownership: a fact, with Julia's ordinary edge. Lemma O holds with the wider reading of a pirate. By default a pirate is followed and the edge invalidates (G1); a scope with `no_pirates` and strict mode refuse it.
- It gives code compiled by facts plain Julia's inference at a package's own helpers. Open issue 157's case, `datalimits(p) = limits(p.pos)`, is a call of TraitMakie's own function with one method: settled, typed by the method's declared result (compiler §6.8), with no assertion at each barrier. Open issue 99's asserted results are the same case where the callee is the package's own function.
- **Scope:** by declaration, or by default for the functions of a module compiled by facts that are neither exported nor `public`. Not Base's internals by default: packages extend them (session 26's measurement with OffsetArrays, StatsBase and Unitful).
- It reverses decision 3 of session 27 ("facts at non-public functions, dropped"). That rule was unsound because ownership let another package extend the function at its own type. Here that method is a pirate by definition, and refused where pirates are.

**For an open function,** open issue 157 (a) stays the answer: the declared result of every method the call could select, asserted at the call.

### 4.6 P6: G2 collected at a load

- An image's code is validated edge by edge, as plain Julia's is (facts §12). Validation is 31–45 % of a load, and the imports are the larger part of each session (E-388; the state §5).
- **The theorem says more than the loader uses.** A fact of deep-G2 code can change only by:
  - a stakeholder's change: every stakeholder of a fact was loaded when the code was compiled, so its image is named in the dependent image's header, which Julia checks already;
  - a stakeholder's extension that the build did not load;
  - a membership the session has and the build had not, of a type in the fact;
  - a pirate, or a method evaluated in the session before the load.
- **So deep-G2 code can be validated by those few definitions,** checked against an index of the image's fact signatures by function and type. The cost follows the number of foreign definitions, not the number of edges.
- **The caveat is measured:** the G2 bit would skip 80 % of the instances a load brings, but 17 % of the costliest edges; those sit in plain code that fails G2 (E-325). P3 moves code from that class into the other.
- This is the candidate index of 2026-10-27 and open issue 73's "facts images without edge validation under strict mode" ([alternatives](../design/alternatives.md), "Strict mode: variants not chosen" and "Validation remembered"), parked with the store. It needs a soundness review of its own: W-64's and W-66's arguments each took one.
- **Why it belongs in the design:** it is the one gain on G-3 that the guarantee pays for and the loader does not collect.

### 4.7 P7: smaller proposals

**(a) A witness in the box** (with P1; GT-7, C-38, C-39, open issue 170).
- The box holds, beside the object, the member's table for the contract's operations. It is made once per member and trait instance at the membership, where the check infers each operation anyway, and kept by the image.
- Each entry has its worlds and is checked at the call, as a `:caller_world` pointer's entry is (compiler §8.1). The defect of session 28's witness tables was a pointer without a world.
- Then an operation costs the same for the first member and the hundredth, in any load order. The split is the optimizer's choice where the members are few, as union splitting is.
- No pointer is made per session (8.3–8.6 ms per operation and member, E-358).
- Cost: 8 bytes a box; a leaf is inlined only where the optimizer splits. [Alternatives](../design/alternatives.md) lists it as Optional.

**(b) A membership adds subtype answers, never type equalities** (GT-18, C-88 (e)).
- Inside an invariant parameter, two types are equal by their declared structure only. `Vector{Union{X, S}}` is not `Vector{X}` in any world; `Vector{<:X}` takes both.
- Normal forms follow this rule already (compiler §4.9). The proposal extends it to the equality test.
- It closes the unsound case without a replay. *Reasoned;* it needs a probe in `subtype.c`.

**(c) `Callable` as a contract at the door.**
- Today a function is a member where it has a method at `A`: subtyping reads the method table, with a least fixed point for a question that reaches itself (compiler §7.4).
- What that has cost since: C-61, C-62, C-90 with open issue 182 (unsound for a copy or a capture), 184 (d), the narrowing of absence edges (E-372: 2.75 s to 1.25 s).
- What it gives: dispatch by a function's signature (the user, 2026-11-06: "I think we need dispatch to pick by signature").
- **A census first:** how many methods in the ports are selected by a `Callable`'s `A` against another method. If few, every function is a member, and the check is the box's: a method at `A` where the function enters, `S` on return. Subtyping then reads no method table.

**(d) A pirate is reported by default** (open issue 177 (c); design §2.5, "who learns").
- When Julia ends deep-G2 code for a method whose definer is no stakeholder, it says so. The invalidation holds the method and the code already. No walk before the definition, no load cost.
- Three tiers: reported (the default), refused (strict mode), and silent only by choice.

**(e) The prune list.**
- **Keys:** to a page of optional extensions. Four of 148 memberships share a key (E-263). They take traits §7.1 to §7.3, compiler §6.1 and §6.4 to §6.6, §10.3, three rows of facts §3, and the opening of the chapter a newcomer reads to learn the attribute.
- **`like`, `withfields`, forwarding with `by`:** conveniences from the time of keys. Keep them as the library's, outside the language's core description.
- **The code slot:** retired with P3. Without P3, the synthesis' control (a session of edits) tests plain Julia's case, not this design's.
- **`@trait_module`:** `facts`, `bounded`, `no_pirates`.

## 5. Each tension against the proposals

| Tension | Under the proposals |
|---|---|
| GT-1 | settled; unchanged |
| GT-2 | removed by P2: check instances are validated with the image |
| GT-3 | Base under facts callers: P3. The compiler stays plain |
| GT-4 | removed by P1 |
| GT-5 | unchanged. A checked contract for a closed type is a clean-up of Base's streams, not a rule |
| GT-6 | removed by P1 |
| GT-7 | P7 (a) |
| GT-8 | removed by P3, at the price of §4.3's types |
| GT-9 | the method-matching share: P4. The rest stays, stated |
| GT-10 | P1 is its lesson, generalized |
| GT-11 | removed by P4 for required operations |
| GT-12 | removed by P2 |
| GT-13, GT-15 | decided; derived under P5 |
| GT-14 | stays; the synthesis' hint |
| GT-16 | stays as ruled; one definition under P5 |
| GT-17 | removed by P5 (a) |
| GT-18 | P7 (b) |

Open issues: 99 and 157 by P5 (b) and P3; 125 by P3; 147 to the prune list; 150 and 178 (a) by P4; 159, 161, 162, 185 by P1; 165 by P1 with P2; 177 (c) by P7 (d); 179 and 181 by P3 and P5; 182 by P1 and P7 (c); 184 (a) by P5, (b) and (c) by P2, (d) by P7 (c), (e) by P1. 180 (c), a membership taken back, stays as the synthesis has it.

## 6. Against the synthesis' seven decisions

1. **Base's surface as the design's object.** Yes, as a rule (P3) with the audit as its gate. The flag on listed methods is the probe, not the design.
2. **The attribute's rules.** P1 in their place. If P1 is not taken: yes to all three.
3. **A build compiles for the type, a session once.** Not as a rule. It writes R2 and R4 into the reference. Under P1 there is nothing to confirm.
4. **The definition-time check keeps its results.** P2 goes further: the check is no inference of its own. If P2 is not taken: yes.
5. **The code slot.** Retire it. E-393 is the evidence for facts code; a session of edits is plain code's case.
6. **A membership taken back.** Yes.
7. **The next demonstrators.** Yes to both. The reader from outside should read the reduced design.

Where I agree with the synthesis against its own tension entry: GT-6's proposal (the attribute by what the caller knows) is not the fix. It adds a sixth step to a side channel. P1 removes the channel.

## 7. What changes hands

**Decisions of the user that a proposal reverses:**

| Decision | Date | Reversed by |
|---|---|---|
| "Dynamic or not as a trait and library default, that the user can override" | 2026-11-06 | P1 (P1′ keeps an override) |
| "falling back to first seen is better for trait modules, falling back to compiled is better for plain Julia" | 2026-11-06 | P1 |
| kept values with `Kept{X}`; the `where` variable as the value's type under either attribute | 2026-11-11 | P1 |
| G-2's wording, "the possibility to opt into full speed (compiled_for(x))" | 2026-11-10 | P1: the opt-in is the value passed as itself, at the typed entry |
| "I think we need dispatch to pick by signature" | 2026-11-06 | P7 (c), if the census says so |
| facts at non-public functions, dropped (decision 3) | session 27 | P5 (b), enforced |
| no second owner in the product setting (the unified build's plan, adopted) | 2026-11-06 | P3, in a form that shares |

Not reversed: sealing stays out (P5 (b) is ownership, and seals no type); "Finality should be opt in" (2026-11-09) holds; keys stay optional.

**Each axis:**

| Axis | Gains | Gives up |
|---|---|---|
| G-1 | the entry chain kept (P3); an edit at a plain method's cost (P2) | "compiled once" by default (P1) |
| G-2 | no slow default to opt out of (P1); a uniform erased call (P7 (a)) | the cast at a call |
| G-3 | validation by ownership (P6) | — |
| G-4 | GT-11 gone, GT-9 smaller (P4); the slot's 15 % of machine code (P3) | facts copies of Base (P3) |
| G-5 | pirates reported (P7 (d)); the check names what a call reaches | `OperationError` (P4) |
| G-6 | erased code fully typed (P1); one definition of fully typed (P5) | — |
| G-7 | six port questions closed (P1); no second vocabulary for operations (P4) | doors to write |
| G-8 | the attribute chapter, the check interpreter, the slot, the closed rules as a list | — |

**What a newcomer would learn after P1 to P5:** a fact; an owner; a trait (a contract, and who is a member); the box; the door. Everything else is Julia's.

## 8. An order, and the probes

1. **Decide P1 first.** It deletes the most, and P2, P7 (a) and part of P5 are simpler after it. Its probe needs no change to Julia.
2. **P4 and P7 (b), (d):** small and independent of the rest.
3. **P3 with Base's audit as a gate.** Its probe is the synthesis' first measurement.
4. **P2,** then the ports follow.
5. **P5:** a restatement of facts §3 and compiler §7.6, then owner-only functions.
6. **P6:** a measurement and a soundness review before any design.

Each probe is in its section. None was run. Each takes minutes and uses tools the experiments repository has (`cause.jl`, `probe_insert.jl`, `fully_typed`, `check_definitions`).

**For upstream,** the stack then splits into two proposals that stand apart: the facts rule with ownership (no change to the type system), and traits (sets, memberships, contracts, the box). The first carries the round's strongest result alone.

## 9. Limits of this review

- **Nothing was run.** P2's, P4's and P7 (b)'s feasibility is reasoned from the references, not read from the code.
- **Each ecosystem was ported once, by the design's author.** P1 rests on how those ports are written. A second author might use the casts more.
- **P1's cost is not measured:** what a library's users lose without a default that compiles once. The ports' doors would show it.
- **P3's cost in types is not measured.** It is the reason the unified build chose otherwise.
- **Noticed in passing:**
  - [the goals](../goals.md) §1: the row of G-8 holds, in its first cell, a sentence that belongs to its claim;
  - G-7's standing gives the first step's first work, and not its repeated work. The only number I found for code as written under the facts rule is the earlier build's (E-140: ahead for the first few dozen rounds). The first step of the path should carry its steady-state number on the head;
  - I did not find, in what I read, why upstream by facts does its first work in 1.9 s against 4.1 s plain. It is the round's headline, and its attribution belongs beside it.

---

## Addendum (2026-11-15, the main session): P1 corrected in discussion, and provisionally accepted

Written after the review, from a discussion with the user the same day. Nothing was run for it. The user's words in full: [the session note](../../session-notes/2026-11-15-review-and-p1.md).

**What was wrong in §4.1.** It let the caller's override leave the language: "a caller who wants code for the type calls past the door". That is the library's switch, which the user ruled out on 2026-10-21: "The type ODEProblem has to store the function and if compiled_for(f) is lost on storage this forces us back into the library provided switch (that already exists in SciML)." The user's case (2026-11-15): "The use case that weighs on my mind is SciML. I typically want this to be Dynamic{RHS}, and that should be the default for inexperienced Devs, but I want to be able to opt for maximum speed if I know what I am doing."

**P1 as it stands now: values carry, by type.** The rule of 2026-10-21 ("Values carry. Annotations provide defaults when a plain value enters trait code. Explicit casts always win.") is kept, with the choice in the value's type and no bit beside the call.

- **Two kept forms of a member of `X`,** both concrete types, both members of `X`:
  - the box `Dynamic{X}(x)`: erased; code for it is compiled once per trait instance;
  - the wrapper that `compiled_for(x)` returns: code for it is compiled per type of `x`, and its operations forward to `x` statically.
- **`compiled_for(x)` is a value,** not a statement about a call. It is made in plain code, before any trait is known. Storage keeps it, a record made before the signature is known keeps it, an untyped parameter passes it.
- **The wrapper is a member of every trait its object is a member of** (the user, 2026-11-15: "I would say that we want wide reach. If a subtrait provides a higher performance specialisation we don't want to miss that."). Each `@trait` declares the wrapper's family as a member, forwarding by its field, as it declares `Dynamic{Z}`'s today ([lowering §2](../reference/lowering.md#2-trait)).
- **A trait's default is a generated forwarding method** (the user, 2026-11-15, on whether anyone who writes a method gets the default: "if Callable wants it anyway that's how it should be"). For a trait that declares `@default_dynamic`, a method `f(t::X, …)` is defined at the two kept forms, and one forwarder, `f(@nospecialize(t::X), …) = f(Dynamic{X}(t), …)`, takes a plain member. It is made where the method is defined, as a positional default makes a second method. Dispatch and the runtime do not change. A trait without the default takes a plain member as it is: Julia's rule.
- **A view is not the object** (the user, 2026-11-15: "1 is acceptable"). In a method at a trait that erases by default, `typeof(t)`, `t === x` and `t isa Circle` answer for the box or the wrapper. This replaces [traits §3.5](../reference/traits.md#35-values)'s "nothing converts or wraps it" for such traits.

**SciML under it.**

```julia
struct ODEProblem{T, P, F <: RHS{T, P}}; f::F; u0::Vector{T}; tspan; p::P; end
ODEProblem(f::RHS{T, P}, u0::Vector{T}, tspan, p::P) where {T, P} =
    ODEProblem{T, P, typeof(f)}(f, u0, tspan, p)

ODEProblem(lorenz!, u0, tspan, p)                 # F = Dynamic{RHS{Float64, P}}: the default
ODEProblem(compiled_for(lorenz!), u0, tspan, p)   # F = the wrapper: code per function
```

- The default needs nothing from whoever writes a method at `RHS`.
- The expert's spelling is today's, and the struct's parameter records the choice. No switch of the library's.
- Open issue 159: `ODEFunction(f; jac = compiled_for(j))` stores a plain `f` and a wrapped `j`; the problem's constructor boxes `f` and leaves `j`.
- Open issue 162: a box or a wrapper passes an untyped helper as itself.
- A box at a second signature (the duals) is made again where the signature is known, as now (traits §7.7).

**Storage.** The earlier trouble had two causes: storage that decided, and `keep` deciding by what the caller knew (open issue 175). With the choice in the type:

| Storage | Holds | Read back |
|---|---|---|
| a struct parameter `F <: X` | the form it was given | that form, statically |
| `Vector{X}`, a field `::X` | either form, each by its own type | a dispatch at the next call |
| `Vector{Dynamic{X}}` | boxes; a plain member is converted when stored | static, fully typed; a wrapper's choice is erased there |
| the user's own `Vector{Circle}` | — | a copy, a lazy view, or a library type that names it |

- `Kept{X}` is no concept then; it can stay as an inline form of `Vector{X}`.
- The last row is what remains: Julia has no borrowed reference into an array's element, so erasing a user's container without a copy needs a view type.
- The conversion of the third row is a method of `convert` at the library's own type. To probe that it invalidates little: the method `convert(::Type{T}, ::Dynamic{<:T})` logged 7,005 entries (`experiments/unification/w149/`), and this one is not that.

**What `Dynamic{X} <: X` means in Julia.**
1. A view is not the object (above).
2. **What varies by member is an operation.** An operation served by the member's own method is reached through both forms, a method specialized for the member's type included (the user, 2026-11-15: "if a type satisfies the trait by a specialized function that gets seen anyway"). A function outside the contract with a method at the member's own type is not reached through either form.
3. **The box runs the methods at the trait it was erased at; the wrapper runs the most specific trait methods of its object.** The results are equal where a subtrait's method refines its supertrait's, which Julia assumes of every more specific method. Two boxes of one object at a trait and at its subtrait differ in the same way.
4. **The wrapper can meet an ambiguity the box does not:** a function with methods at two unrelated traits of the object. It is the ambiguity the report at a membership names (traits §6.3).
5. **Erased code can be slower by algorithm, not only by dispatch.** A box that entered through `Iterable` stays at `Iterable`'s method. A library that wants the subtrait's method under erasure writes a barrier, `total(unwrap(t))`.
6. **The wrapper is not the object.** A method at the object's own type, of a function outside the contract, needs `unwrap(t)`: static under the wrapper, one dispatch under the box. So in trait code a specialization belongs at a subtrait or in an operation; the porting guideline should say so.
7. **A box is under none of the member's declared supertypes.** A boxed function is no `Function`, a boxed vector no `AbstractVector`. For a closed type the eraser is a subtype of it, as `IOContext{IO}` is.
8. **Julia converts no argument,** only what is assigned to a field or an element. Hence the forwarding method for arguments and `convert` for storage.
9. **A box needs the trait's parameters,** so it is made where they are known.
10. **Questions outside the contract are asked before the value is boxed** (a function's arity by reflection, for one).
11. A member of a bits type is allocated when it is boxed, as it is today when it is passed to code compiled once.

**What leaves the design,** against §4.1's list: unchanged, but `compiled_for` stays as a function that returns the wrapper, `@default_dynamic` stays as the declaration that makes the forwarders, and `keep` is not needed (a method's argument is already a kept form). `with_dynamic(x)` is `Dynamic{X}(x)` where the trait is known.

**What §7 said and no longer holds.** P1 does not reverse G-2's wording: `compiled_for(x)` is the opt-in. It does not reverse "Dynamic or not as a trait and library default, that the user can override" (2026-11-06). It still replaces the fallback by scope (2026-11-06), `Kept{X}` and the `where` variable's rule (2026-11-11), and traits §3.5 for traits that erase by default.

**The user's verdict (2026-11-15):** "So provisionally I would accept P1 with the addendum. Record this and then do the suggested proves to settle the other P from the review."

**What was done with it.**
- Recorded as pending in [the decision log](../record/decisions.md#pending) and as [open issue 186](../open-issues.md#1-decisions-waiting-for-the-user). It is not in a reference, so it is not in force.
- The work: W-151 (a prototype in the library, then the references) and W-152 (the probes for P2 to P7, E-394 to E-400) in [the work queue](../record/todo.md).

---

## Second addendum (2026-11-15, the main session): the probes, and what they settle

Run at the user's word ("Record this and then do the suggested proves to settle the other P from the review."), as W-152. Seven probes, E-394 to E-400, on `unified` 7b374f39ce with TraitWorld e11c7cc and the forks 439bae7; each a run of seconds to two minutes; counts of one run, no times. Scripts, logs and tables: `experiments/unification/w152/README.md`. Numbers: [evidence §1](../design/evidence.md#the-reviews-probes-w-152-e-394-to-e-400).

| | The probe | What it found | Verdict |
|---|---|---|---|
| P2 | E-397: the check against the method read at the box | the same verdict at 157 of 165 methods; the 7 the check alone reports are a stored value, an adapter, `promote_op`; in a control both find four of five mistakes, and the fifth (`typeof(t)`) is no fault at a box | **holds.** To build with P1's prototype |
| P3 | E-395: deep G2 on the nine loads | no deep-G2 instance ended (0 of some 50,000); every ended instance not deep; the bit carried by 40 of 49. But 56 % of the forks' own facts instances are not deep, through 1,596 callees in 385 method names; inferred by facts all the way down, 19 % of 701 direct callees widen | **the predicate holds exactly; the demand rule costs more than §4.3 assumed** |
| P4 | E-394: methods at sets against methods at the box | the library's late load ends 201 plain instances, all by required operations' methods at sets; the same operations at the box end none | **holds** |
| P5 (b) | E-396: run-time sites by the callee's owner | owner-only functions: 14.7 % of the forks' 4,606 sites, 21.7 % and 41.4 % of the trait demonstrators' and the ODE packages'; plain inference gives a concrete type at half or more of them | **holds;** the larger lever in idiomatic trait code, the smaller in a port |
| P6 | E-399: what a load validates, by deep G2 | deep-G2 instances are 50 to 64 % of what a load brings, with 13 to 19 % of the calls by signature | **ended by its criterion,** for now |
| P7 (b) | E-400: GT-18's case | at a concrete container type only `<:` equates the two types; at an abstract one a fresh `isa`, a compiled `isa` and dispatch give two answers | the rule matches what the runtime does at a concrete type; **needs a build** |
| P7 (c) | E-398: the `Callable` census | no two methods told apart by a `Callable`'s signature; seven pairs use membership as a guard beside an untyped fallback | **holds:** dispatch by signature is not in use |

### What changes in the review's proposals

**P3 is split in two.**
- **Take the predicate.** Deep G2 is the class that unrelated loads do not end. The bit as built is one level deep and does not tell (40 of 49). So G2's claim, the image's keep rule, strict mode's walk and the evidence's counts should read the deep class. It is a walk over edges that exist; `w152/p3/deep.jl` is a first form of the tool.
- **Do not take the demand rule yet.** §4.3 read GT-8 as a loss at an entry chain. The census says the exposure is wide: more than half of a port's facts instances rest on a callee that is not G2, and a rule that gave each a facts copy would infer most of the port again and widen a fifth of the direct results. The reach comes first from few places.
- **A cheap rule to take now: a call that only throws is a run-time site for a facts caller.** Its result is `Union{}`, so no type is lost, and no edge is held. It moves the forks from 41 % to 61 % deep, and upstream by facts from 40 % to 63 %.
- **Then Base's surface, by the census's list,** not by the entry chain: error paths that take a `Type` (`Core.throw_inexacterror`), `DomainError(::Any, ::Any)`, type joins at `Any` (behind `collect` and `map`), the task code under a lock, `push!(::Vector{Any}, ::Any)`. Each is a patch to Base or a boundary. The gate: the share of a port's facts instances that are deep G2, counted by the tool.
- **The fact rule's kinds show in the types lost.** `iterate(::Dict{Symbol, DataType})` gives `Tuple{Any, Int64}` by facts: a constructor called with a value of a kind is a run-time site ([facts §3](../reference/facts.md#3-fact-signatures)). It is by the rule, and it is a place where P5's settled calls would help: a constructor's own type is its owner's.
- **The code slot's case is unchanged:** E-393 for facts code, and now the class that tells without it.

**P6 waits for P3's list.** The lookups a load pays for sit in code that is not G2, as E-325 found for the bit. Validation by ownership would skip half the instances and an eighth to a fifth of the lookups. It is worth taking up again when the deep class holds most of an image.

**P7 (b) is smaller than §4.7 said.** No rule of equality needs inventing for a concrete type: the runtime never equates the two. The fault is `<:` between the types, and `isa` and dispatch at an abstract container type. The fix is in `subtype.c`'s equality test for an invariant parameter; it needs a build and the gates.

**P7 (c): the question for the user is sharper.** The ports dispatch on "is it a `Callable` at this signature at all", never on which signature. With every function a member and the check at the box, each of the seven pairs becomes one test of `hasmethod` in one method. It would take the method table out of subtyping (compiler §7.4). It reverses "I think we need dispatch to pick by signature" (2026-11-06).

**P2, P4 and P5 (b) stand as written.** For P4 the open part is to build: inference reading the declared result from the contract with no method at the set.

### An order, revised

1. **W-151:** P1's prototype in the library, with P2's reading of the box as its check.
2. **P4,** in the library and the runtime's rule for an operation's call. It removes GT-11 as measured.
3. **Deep G2 as the predicate, and the throw-only rule** (P3's first two parts); open issue 187's bit.
4. **Base's surface by the census** (W-19's patches, open issue 179), with the deep share as its gate.
5. **Owner-only functions** (P5 (b)), with the ports' asserted barriers as its test (open issues 157, 99).
6. **For the user:** `Callable` as a contract at the box (P7 (c)).
7. **Later:** P7 (b)'s fix with a build; P6 after step 4; P5 (a) as a restatement of the references.

### Limits

- One run per count, one machine, the round's sessions. The classes are structural, so the counts do not move with load; the times were not taken.
- E-397 reads the top frame on today's build. It shows agreement, not the cost of the check.
- E-395 (c) infers under the test bed. It shows the result types, not what the port's own code would then lose above them.
- E-394 shows what the methods at sets cost. That the split works without them is not shown.
