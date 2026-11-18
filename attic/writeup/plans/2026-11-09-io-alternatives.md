**Status:** proposal (2026-11-09; written by a Fable agent at the user's request: "Ask Fable if another approach to IO rather than turning it into a trait would be more sensible/principled.")

# `IO`: alternatives to a trait compiled once by default

This plan weighs the decision of open issue 164 (d) (`IO` is Base's trait of streams, compiled once by default, closed after load) against other ways to solve 164's case. It is not normative. *Verified* means checked against the code, a log or a reference named here; *inferred* means reasoning the experiment in §7 tests. Numbers come from [`design/evidence.md`](../design/evidence.md) and the registry rows E-318 to E-336; where a number has no control at its load, this plan says so.

## Summary

- **164's case is small and local:** one package's display code compiled at the REPL's stream type (0.12 s of a 0.18 s step, E-318). Erasing the stream at that package's `show` boundary fixed it on the early build: 0.081 s against 0.175 s (E-323, a few lines in the fork).
- **The decision applies the erasure at the other end:** to every method Base types `io::IO`, Julia's own streams included. That turns Base's stream kernels into code compiled once, and most of the day's work (E-331 to E-336) repaired what that did to speed and to invalidation. The goal's task is still 4.5 s where the build before `IO` was a set took 1.6 s at low load; the forks' `show` step, the case that motivated 164, has not been measured since E-330, where it was 2.0 s.
- **A principled alternative exists and is partly measured:** `IO` stays Julia's closed abstract type; Base declares `IO`'s contract (operations with declared results, the split's candidates) without making `IO` a set; the erased stream is Base's own wrapper, `IOContext{IO}`, whose operations split on its field; an author erases where the design's own rule says `Dynamic` pays (large code, many members behind it: a display path), by the idiom Julia already has, `@nospecialize io::IO` plus the wrapper. E-328's `split` column is this alternative on vanilla: formatted output 0.85–1.19×, one short write per call 1.1–2.2×, display 0.98–0.99×, and plain code that knows its stream untouched.
- **Recommendation:** B (§4.2): the contract on the closed type, the eraser, opt-in erasure. Keep the general rules the day produced (E-331, E-332, E-333, E-334, E-335, E-336). Decide by the experiment of §7, which measures 164's case under both on the same build at the same load, with a control.

## 1. What 164 asked for, and what was decided

**The case** (verified: open issue 164, E-318): DataFrames' `show(io, df)` passes the stream to PrettyTables, plain code compiled per stream type. At a REPL the stream is `IOContext{REPL.LimitIO{TTYTerminal}}`, a type the fork's image workload (an `IOBuffer`) did not see. The step compiles DataFrames' keyword body and PrettyTables' code there. Each new stream type (a file's, a notebook's) compiles them again.

**The decision** (verified: [traits §9b](../reference/traits.md#9b-streams-io), [compiler §7.5](../reference/compiler.md#75-io), [decisions](../record/decisions.md) §9): `Core.IO` is an open set with the default `Dynamic`; traits §7.5's step-4 exception does not apply to it, so Base's own streams take the default; `IO` is closed after load; `Dynamic{IO}` is a member; the split's candidates are `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`.

**The user's words** (2026-11-09): "The real point here is that Base should support and default to Dynamic{IO} right?", then "Finality should be opt in. Everything else is approved." Two readings fit the first sentence:
- *Support:* `Dynamic{IO}` is an `IO`, so plain code typed `io::IO` takes an erased stream. *Default to:* an erased stream is what packages pass where coverage matters.
- *Default to:* every method typed `io::IO`, Base's included, is compiled once.

The session took the second reading, and the user approved the decisions listed under it. This plan does not reopen the approval; it asks whether the first reading, built out, is the more principled design, and names the experiment that would show it. The user's own question asks the same.

## 2. What the decision costs and needs

Everything in this section is verified unless marked.

### 2.1 Speed

- **Per call, plain code that knows its stream** (E-333, `unified` 0c836f3ef6 against vanilla v1.13.2, load 9): `print` of `Int`s 1.2×, of `Float64`s 1.5×, of `"ab"` 2.2×, `join` 2.6×, `show` of a vector 3.4×, `string(…)` 1.1×, `@printf` 1.0×; `write(io, ::Char)` 4.4× before it was `@specialize`d. The cause is the design's: a call at a known `IOBuffer` resolves the attribute at the method (compiler §6.3, step 4) and runs the instance compiled once at `IO`. The remaining 3.4× waits for open issue 166 (d), a visible change of `IOContext`'s type.
- **The sessions.** The goal's task: 1.62–1.63 s before `IO` was a set at load 2.4–3.9 (E-326); 3.9 s at load 26–30 (E-329, where an unchanged build was slowed 2.5–3× by the machine); 15.8–16.1 s with `IO` a set at load 31–36 against a control of 4.1–4.3 s at the same load (E-330); 4.44–4.51 s after E-335 at load 13.7–15.6; 4.51–4.57 s after E-336 at load 6.2 (`experiments/unification/e289/logs/f-unified-w336.log`: imports 3.5 s, read 0.31 s). No run since E-330 has had a control at its load. The one matched comparison, E-330's, was 3.8×; the later builds have not been compared to anything at the same load. *Inferred* from the loads: the goal's task is still about 2× the build before `IO` was a set.
- **E-336's imports rose** from 2.2–2.3 s (E-335, load 14) to 3.5 s (load 6.2), unexplained in the record.
- **The forks' `show` step,** 164's case: 2.0 s on E-330 against 0.18–0.19 s before. Not measured since (the registry rows E-332 to E-336 measure the goal's task only). So the benefit the decision was taken for is unverified on the build that carries it.

### 2.2 Machinery it needed, beyond what any trait needs

- `IO` closed after load, so that `x isa IO` folds and `print`, `write`, `show` carry no guard ([compiler §4.8](../reference/compiler.md#48-negatives-never-fold-positives-through-entries)); Core and Base counted as loaded at the end of Base's build.
- A final negative for an intersection no type is in, with a cell on an abstract type name (E-334, C-79): a concept created for `All{AbstractString, IO}`.
- Raising defaults for `eof`, `isopen`, `close` at `::IO`, so that the contract has a default per operation.
- Ambiguity reflection asked in the query's world, so that Base's `detect_ambiguities` goes back from 66 to 0.
- The conversion of a member's result at a call through the trait (E-333), because `IO`'s members are not checked and two of Base's streams returned `UInt`.
- Ten `@specialize` annotations in Base (nine in `loading.jl`, one on `write(io, ::Char)`; `grep -rn "@specialize" julia-unified/base` against `julia-vanilla/base`), each chosen by a measurement or a failure. The list is open-ended: the next candidates are the wrappers of 166 (d).
- Open issue 166 (d) still ahead: `IOContext(io)` built in code compiled once is `IOContext{IO}` for every caller, so `typeof(IOContext(stdout))` changes for every package.
- Base's `precompile` test fails 20 of 457 in a child without a compiler (open issue 166): code compiled once needs the JIT for a split's pointers.
- *Inferred:* under `--trim` the attribute still applies (compiler §2.6 removes the facts policy, not the attribute), so every print in a trimmed program reaches a split whose fallback is a dynamic call (§7.3), which trim's verifier rejects. Not run; facts §13.3 is Planned.

Four fixes the day produced are general and stay whatever is decided: dispatch's lookup at an unmet intersection (E-331), the firewall at a split's branches (E-332), the typemap's listing at the set's position (E-335), and backedges that keep the call's signature (E-336, which also fixes vanilla's imprecision for `@nospecialize`).

### 2.3 A guarantee it contradicts

[Facts §13.1](../reference/facts.md#131-the-product-setting): "Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation." Under the decision, plain code that calls Base's `print` at an `IOBuffer` runs 1.2–3.4× slower (§2.1) and is invalidated through an instance shared with every stream (E-336's chain: TranscodingStreams' `seekstart` invalidating `isvalid_file_crc(::IOStream)`). Nothing in the references exempts `IO` from §13.1. Either the guarantee gains an exception, or the decision does not stand with it.

### 2.4 `Dynamic{IO}` is a leaky box

Traits §9b: "`Dynamic{IO}(io)` is an `IO`: plain code typed `io::IO` takes it. It forwards the operations." Verified in `julia-unified/base/iotrait.jl`: twelve forwarding methods. Verified in Base: `displaysize(io::IO) = displaysize()` reads `ENV` (`base/stream.jl:563`) while `displaysize(io::TTY)` asks the terminal (`:574`); `mark(io::IO)` and `ismarked(io::IO) = io.mark >= 0` read a field (`base/io.jl:1427`, `:1467`); `isreadable(io::IO) = isopen(io)`. So `show(Dynamic{IO}(stdout), x)` with `:limit` sizes its output by `ENV`, not by the terminal, and `mark(Dynamic{IO}(io))` fails. Gate `n19_io_trait` tests an `IOContext`'s property through the box, not these. The hazard is latent under the decision, since erasure there happens by compiling once and the real object flows; it becomes live wherever a `Dynamic{IO}` value is made. Base already has a complete eraser: `IOContext` is an `AbstractPipe`, which forwards the read and write interface through `pipe_reader` and `pipe_writer` (`base/io.jl:470-495`), and forwards `displaysize` itself (`base/show.jl:448`).

## 3. Where the decision is right

- **It is transparent.** The real stream flows; a call on it that is not an operation dispatches to the right method when it runs. No box, no forwarding set to keep complete.
- **It covers the ecosystem without code changes.** If it works, every plain package's display code, typed `io::IO` as Julia's habit has it, is one instance for every stream, and an image's workload at an `IOBuffer` covers the REPL, a file and a notebook. No other option gives that for free.
- **It is the design's thesis applied where it bites.** A trait is an abstract type; `IO` is the abstract type Base's code is written against most. Making it a set exercised the machinery at Base scale and found four general faults (E-331, E-334, E-335, E-336) that `Callable`, Base's other set, would have met later.
- **Its contract is the right one.** The twelve operations with declared results in `iotrait.jl`, and the candidates in declaration order, carry over to every alternative below.

What is not right is where the `Dynamic` attribute is applied. [Traits §7.10](../reference/traits.md#710-costs-and-choosing): "`Dynamic` suits large code with many members behind it … `Compiled` suits kernels, where the work per call pays for code per key." Base's methods at `IO` are the kernels (`write` of a byte, `print` of a short string); a package's display path is the large code. [Traits §7.5](../reference/traits.md#75-what-decides) step 4's exception for Julia's own types says why the kernels should stay per type: "those types are few and fixed, so code per type for them is bounded." 164's problem was never the number of instances; it was one missing instance in one image. The decision answers a coverage problem at the kernels with an erasure that costs every call, and then restores the kernels one `@specialize` at a time.

## 4. The alternatives

Each is judged on: 164's case; soundness; speed per call and at load; machinery it needs or makes unnecessary; what of today's work carries over; the ports; the guarantee "a membership invalidates nothing".

### 4.1 A: the decision as built (`IO` a set, once by default, closed after load)

§2 and §3. Solves 164's case in principle; unverified on the build. Sound. Per call 1.0–3.4× on plain code; load not yet back to the control's. Needs the set, finality, the final negative at an intersection, the raising defaults, the conversion rule, 166 (d), the `@specialize` list. The ports change nothing. The guarantee holds; `IO` opted into finality, as the user allowed.

### 4.2 B: `IO` stays Julia's closed abstract type; the contract and the eraser are Base's; erasure is the author's choice

**The rules.**
1. **A closed abstract type may declare a contract:** operations with declared results, and the split's candidates. Its membership stays Julia's (`struct S <: IO`); nothing joins later, so no cell, no guard, no finality. At a value typed by it, an operation's call is inferred as the declared result and compiled as the split ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait), [compiler §7.2](../reference/compiler.md#72-the-split)), the firewall included. `IO` declares `iotrait.jl`'s twelve operations and four candidates; `read(io, ::Type{T})::T`, `position`, `displaysize` follow ([the equations plan](2026-11-09-compiled-once-equations.md) §4.2).
2. **The erased stream is Base's wrapper,** `IOContext{IO}` (164 (c): a plain abstract type with a contract names its eraser). It is an `IO`, so plain code typed `io::IO` takes it. It forwards the whole interface, as an `AbstractPipe` does, and its operations on the field `io::IO` split by rule 1. `IOContext{IOBuffer}` stays for code per type.
3. **Erasure is the author's choice,** by Julia's own idiom: a display entry declares `@nospecialize(io::IO)` and passes `IOContext{IO}(io, …)` on. Where the attribute machinery reaches `IO` (rule 4), `@nospecialize io::IO` alone does it.
4. **Optional, later: the attribute at a closed abstract type with a contract.** `Dynamic` at such an argument compiles the method once at the type, the real object flowing, the bit carried on through calls as [compiler §6.3](../reference/compiler.md#63-the-attribute-at-a-call) carries it, with the default `Compiled` (Julia's). Then `@nospecialize io::IO` is the design's `Dynamic` with propagation and the split: an upgrade of an idiom every package already understands, and no box. Nothing of the set is needed for it.

**164's case.** Rule 3 at DataFrames' `show`: measured on the early build, 0.081 s against 0.175 s (E-323, forks branch `e323`: `_erased_stream` and `@nospecialize(io::IO)` at the entry, a few lines). What remains is the REPL's own display path at its stream (about 30 ms) and Base's `show` at the cells' types (about 50 ms), which Base's image covers for common types. A notebook's or a file's stream is covered the same way. Verified: the branch's diff; the numbers in 164's text.

**Soundness.** Rule 1 adds no answer the world can change: a closed type's negatives already fold in Julia, and the candidates are read without an edge as now. The eraser builds what it declares. The declared results are asserted as now (traits §7.9); a member outside them raises at the call, as under A.

**Speed.** Plain code that knows its stream: vanilla's, exactly; nothing in Base is compiled once. Erased code: E-328's `split` column, on vanilla, is this design (`SplitIO <: AbstractPipe` with hand-routed branches over the four candidates, `experiments/unification/e328/erase_io.jl:34-51`): against the stream's type known, formatted output 0.85–1.19×, `show` of a vector 0.98×, `string(…)` 0.96×, DataFrames' display 0.98–0.99×, CSV's `write` 0.92×, one byte or one short string per call 1.14–2.2×. Against the raw buffer: `print` of `Int`s 1.18×, of `"ab"` 1.56×, `write` of `Char`s 1.4×, of bytes 2.9×, `show` of a vector 0.99×. Those costs are paid only below an erasure. Load: no instance in Base is shared across streams, so no fan-in; the goal's read step returns to its per-type instances (*inferred:* E-329's 0.05–0.06 s, against 0.31 s after E-336).

**Machinery.** Needed: four gates relaxed from "an open set" to "an open set or a closed type with a contract" (verified where they are: `declared_operation_result`, `Compiler/src/abstractinterpretation.jl:183`; `operation_split_type`, `:277`; `jl_register_candidate` and `jl_candidates_of`, `src/datatype.c:257,266`), a bit on the `TypeName` for the contract, and the eraser's forwarders written as splits. The declared result is already a method flag independent of sets (`jl_method_set_declared_result`, `src/gf.c:2892`). Made unnecessary for `IO`: `jl_set_core_set`, closed after load, the final negative at an intersection, the raising defaults, the `Dynamic{IO}` entry and its twelve forwarders, the `@specialize` list, 166 (d) as a global change, the precompile child's failures. Rule 4 needs the attribute's compilation signature at an abstract type that is not a set (compiler §6.2: "the erased key `X{p…}`" becomes the type itself); *inferred* to be small, not read.

**What carries over.** `iotrait.jl`'s operations, results and candidates; gate `n19`'s split and conversion cases; E-331, E-332, E-333, E-334 (for sets that opt in), E-335 and E-336 as general rules; the audit tools. Lost: the set's own cases of `n19` (a late `@implement IO S`).

**The ports.** DataFrames' fork: `e323`'s few lines. TraitReport's `report(io::IO, t)`: erases at its entry where it wants coverage, else per type. CSV's reader: vanilla's instances at `IOStream`. Makie's `show(io, ::MIME"image/png", fig)`: bulk writes, nothing to change. A plain package that does not erase keeps vanilla's behaviour: the status quo, not a regression.

**The guarantee.** Untouched: `IO` is not a set, and no trait's negatives are made final on its account.

**Against B.** It does not cover a plain package that never erases; A does, if A works. The box named `Dynamic{IO}` has no place in B; the user's "support Dynamic{IO}" is met by Base's eraser under Base's own name, and the spelling is the user's to choose. Rule 1 is a new category, "a closed abstract type with a contract"; it is also the natural next step for `AbstractArray` and `AbstractString`, whose values in a `Vector{AbstractArray}` would gain typed results and the split, so it is not a special case for `IO`.

**Precedent** (from my knowledge, to be checked against the primary sources before a reference cites it): Rust's `std::io::Write` is a trait; the standard library's own functions are generic over `W: Write` and monomorphize; `&mut dyn Write` is written by an author at an API boundary, never chosen by the library for its callers. Swift's `print(_:to:)` is generic over `TextOutputStream`; `any TextOutputStream` is the caller's. The design's own comparison table already records `dyn Trait` as "chosen by the callee" ([other-languages §1](../design/other-languages.md)).

### 4.3 B-display: Base erases at its display entry

A variant of B that gives A's ecosystem-wide coverage for the one path 164 is about. Base's `display` (the REPL's, a notebook's) passes `IOContext{IO}` to `show(io, mime, x)`, so every package's text display is compiled at one stream type, which a workload at `IOContext{IO}(IOBuffer())` covers. Cost: the split on the display path only (E-328: display 0.98–0.99×). Condition: a package's workload must display at the erased type; today's workloads display at an `IOBuffer`, so the first display at a REPL would still compile once per session until workloads follow. `string(…)` and `sprint` must not erase: interpolation of short strings is hot (`print` of `"ab"` 1.56×). *Inferred*, not measured; a candidate arm for §7.

### 4.4 C: a separate stream trait in the library, Base untouched

`Dynamic{Stream}` is a `Stream`, not an `IO`, so PrettyTables and every plain method typed `io::IO` cannot take it: 164's case is not reached. To reach it, the library's erased value must be an `IO`, and then it is B's eraser written outside Base, without rule 1's split (the dynamic call per operation: E-328's `erased` column, 4.2–5.3× on short writes). Dominated by B.

### 4.5 D: `IO` a set, compiled per type by default (the flagged item's option (e))

Keeps the set and everything it costs (the typemap listing, the intersections with `AbstractString`, closed after load for `isa` to fold, the ambiguity reflection, a thousand of Base's methods as methods at a set) and gives up what the set was for. A package's own stream would be compiled once by default, which no port asked for. Erasure at a boundary works as in B. Dominated by B: same speed, more machinery.

### 4.6 E: `@nospecialize` on Base's methods typed `IO`, without a set

Vanilla's mechanism: one instance per method, every call on the stream a dynamic dispatch, no declared results, no split (E-328's `erased` column: 4.2–5.3× on short writes, 1.1–2.0× on formatted output), and no propagation into a package's code, so PrettyTables still compiles per stream type: 164's case stays open. Dominated by every other option.

## 5. Comparison

| | A (as built) | B | B-display | C | D | E |
|---|---|---|---|---|---|---|
| 164's case | in principle; unmeasured on the build (E-330: 2.0 s) | measured, 0.081 s (E-323) | *inferred* | not reached | as B | not reached |
| Plain code that knows its stream | 1.0–3.4× (E-333) | 1.0× | 1.0× | 1.0× | 1.0× | 4.2–5.3× short writes |
| Erased code | the same instance | 0.85–1.19× formatted, 1.1–2.2× short writes (E-328 `split`) | as B | 4.2–5.3× | as B | as C |
| Load | fan-in through shared instances; 2× the control, *inferred* | vanilla's | vanilla's | vanilla's | the set's listing and intersections | vanilla's |
| `IO` a set | yes | no | no | no | yes | no |
| Finality for `IO` | yes | not needed | not needed | not needed | needed for `isa` | not needed |
| New concepts | final negative at an intersection; raising defaults; conversion; `@specialize` list; 166 (d) | a contract on a closed type; the eraser rule | as B | none | as A minus the default | none |
| Covers a plain package that never erases | yes | no | at `display` | no | no | no |
| Ports | nothing | a few lines (done) | nothing | rewrite at `Stream` | a few lines | nothing |
| "A membership invalidates nothing" | holds; `IO` opted out | untouched | untouched | untouched | holds | untouched |
| Base's `precompile` test, `--trim` | 20 of 457 fail; trim hazard | pass | pass | pass | pass | pass |

## 6. Recommendation

**B**, with B-display as its second arm in the experiment.

- State rule 1 in traits §3.4 and §4 (a closed abstract type may declare a contract) and in compiler §7.1 and §7.2 (the split at a value typed by such a type); state rule 2 in traits §9b (`IO`'s contract; Base's eraser `IOContext{IO}`, forwarding the whole interface, its operations split); state rule 3 as the idiom in §9b and in the porting guide. Rule 4 is Optional until a port needs propagation without the wrapper.
- Retire for `IO`: the set, closed after load, the `Dynamic{IO}` entry and its forwarders, the raising defaults, the `@specialize` additions, and 166 (d) as a global change. Keep as general rules: E-331, E-332, E-333, E-334, E-335, E-336, the ambiguity reflection in the query's world, Core and Base counted as loaded (for any Base set that opts in later). Keep `iotrait.jl` as the contract's declaration.
- Facts §13.1 then holds as written. The flagged item "`IO` compiled once by default" closes with the decision's reversal recorded in the decision log and `design/alternatives.md` ("`IO` as an open set compiled once": the measured costs, E-330 to E-336).
- If the user's intent was the second reading of §1 (Base's own methods once, for every plain package's benefit), A is the only option that gives it, and its price is §2: a Base-wide per-call cost, an exception to facts §13.1, and an open-ended `@specialize` list. That trade is the user's; this plan recommends against it on the design's own rule (§3, last paragraph).

## 7. The experiment that decides

To register as the next E-n before it runs. The machine's load is the first variable: every arm runs interleaved with the unchanged early build's form (f) as the control, as E-329 and E-330 did.

**Question 1: does A deliver 164's case, and what does it cost against B on the same library?**
- *Arms:* (A) `unified` at E-336's head with TraitWorld `unified` 4443d2c and forks `unified`; (B) `unified` bf447db25e (E-329's build: closed after load built, `IO` not a set) with the same TraitWorld and forks `e323` rebased, its `_erased_stream` wrapper given E-328's hand-routed split (an `AbstractPipe` whose `write`, `unsafe_write`, `read`, `unsafe_read`, `eof` branch over the four candidates), so that B is measured with the split and without any compiler change.
- *Measured:* the forks' session (the `show` step, `3_read_show`, `write`), a warm-up and 3 runs; the goal's task (imports, read); E-328's workloads `raw` on both builds against vanilla at the same load; Base's `precompile` test on A; the load report on both.
- *Results that would change the recommendation:* A's `show` step within 10 % of B's, every `raw` workload within 20 % of vanilla's, the goal's task within 5 % of the control's, and Base's tests passing: A stands, and the remaining objection is facts §13.1, for the user. B's `show` step not below 0.1 s on the unified build: the compile is not the stream's type alone, and 164's case needs E-318's trace again before any decision.

**Question 2: what does rule 1 cost and give in the compiler?** After question 1, if B is taken: the four gates relaxed, the eraser's forwarders as compiler splits, E-328's workloads through `IOContext{IO}` against the hand-routed proxy (within 10 %: the rule replaces the hand routing), and the erasure report at `IOContext{IO}` (stream-decided dynamic sites below 20 after `read`, `position` and `displaysize` are declared).

**Question 3: B-display.** Base's `display` erasing, with the forks' workload at `IOContext{IO}(IOBuffer())`: the forks' `show` step with no change in DataFrames' fork, and the REPL's own display workload unchanged. Within 10 % of question 1's B: the eraser moves into Base's display entry and the ports need no line.

## 8. What was verified, and what was not

- *Verified by reading:* the references cited; `base/iotrait.jl`, `base/splittarget.jl`, `base/io.jl:470-495, 1427, 1467`, `base/stream.jl:563-574`, `base/show.jl:432-448`; `Compiler/src/abstractinterpretation.jl:163-331`; `src/datatype.c:254-273`; `src/gf.c:2892`; the forks' `main..e323` diff; `experiments/unification/e328/erase_io.jl` and `logs/e328-vanilla.log`; `e289/logs/f-unified-w335.log`, `f-unified-w336.log`, `forks-unified-w330.log`; the `@specialize` counts in `julia-unified/base` and `julia-vanilla/base`; `git status` of `julia-unified` (E-336 uncommitted, 48 lines).
- *Inferred, not run:* the goal's task at matched load under A; the read step under B; the trim hazard; the cost of rule 4; B-display's numbers; that the four gates are the only places set-ness is tested on the split's path (a grep found them; the facts mode's branch-as-fact path was not read).
- *From my knowledge, to be checked against primary sources:* the Rust and Swift precedents of §4.2.
