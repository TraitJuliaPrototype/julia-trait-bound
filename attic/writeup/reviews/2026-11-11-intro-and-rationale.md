# Review: the introduction and the rationale against the goals (2026-11-11)

The user (2026-11-11): "Look at the documentation next, especially the introduction material and the high level rationale and arguments."

Done in the main session (no subagents on the shared host). It is the review part of W-137, taken up ahead of the plan's order at the user's word, and widened to the rationale. Each finding says what was done with it, in the same commit as this review unless it says otherwise.

**The question asked of each page:** does it argue for, and report on, the goals as they stand since 2026-11-10 ([`goals.md`](../goals.md)); does it claim more than the evidence on the unified build supports; can a newcomer follow it.

**What was read:**
- in full: `README.md`, `goals.md`, `design.md`, `state.md`, `intro/traits-for-julia.md`, `intro/traits-by-example.md`, `intro/porting.md`, `intro/results.md`, the review of 2026-11-09 of the documentation;
- in part: `design/evidence.md` (the header, §1, the summary), `design/performance.md` (the header and the first table), `reference/facts.md` §1 and §2.2, `reference/traits.md` §3.4 and §7.4 to §7.8, `open-issues.md` §1's flagged tensions GT-3 and GT-6 to GT-13, the work queue's plan and W-135 to W-138, the registry's rows E-324, E-337, E-355 to E-361.

**Not read:** the glossary beyond its index, `design/other-languages.md`, `design/alternatives.md`, `design/julia-changes.md`, the references but for the sections named, the evidence's §2 to §5.

**What was run** (`unified` binary 36b653bb3b with local changes, TraitWorld-unified 05991fc; one Julia job at a time, niced; load 6–9 of 128):
- `experiments/docs-examples/`: `intro.jl` 18 pass, `tutorial.jl` 83 pass (85 with the two checks added for H3), `strict.jl` 5 pass. The messages the pages quote are the messages printed. Logs `logs/*-05991fc.log`.
- `experiments/docs-checks/check_links.py writeup`: no problem in `intro/`, `design.md`, `goals.md` or `state.md`.
- `experiments/docs-checks/check_quotes.py` (new, M2): the porting guide's 23 citations of the ports' files.
- `experiments/docs-examples/keep_at_prompt.jl` (new, H3).

**Not run:** no build, no benchmark, no session timing. Every number the pages now carry is copied from the evidence, with its experiment.

## Findings

### High

#### H1. The teaching pages and the rationale claimed more than G2 gives on the unified build

- `intro/traits-for-julia.md`, "What you get" 1: "So an unrelated package's load cannot discard the code, in any load order." `design.md` §4: "the facts mode does [protect code from loads], for any code it compiles."
- [facts §2.2](../reference/facts.md#22-g2-stable-caches), the scope: G2 does not cover "a facts caller's code edges into plain code". Base is plain code in the product setting.
- E-355, on the unified build: every instance that code compiled by facts loses to nine unrelated loads is reached through a plain callee in Base. For the ports of CSV and DataFrames these are the reader's entry functions, and their work after the loads takes 0.96–0.98 s against 0.063 s (GT-8).
- So the sentence a newcomer reads first is false for the project's own flagship port. The reference and the open issues were right; the teaching pages and the rationale had not followed.
- **Done:** the intro states the limit beside the claim, with E-355's and E-357's numbers; `design.md` §2.3 cites E-355, §2.6 states what G2's scope costs on the unified build before the earlier build's estimates, §4 says "for the code it compiles, and not for the plain code that code builds on"; `intro/results.md` gives the table and says that a port cannot fix it; `intro/porting.md` 0.1 says what compiling by facts does not cover.

#### H2. The rationale argued for two goals; the project has eight

- `design.md` §2.6 was "How the two goals interact": composable caching with AOT, and code that says what it needs. `goals.md` (2026-11-10) names eight axes. `design.md` did not link it.
- Three axes had no argument at all in the rationale: error messages (G-5), the transition (G-7), simplicity (G-8). §1 states the errors problem ("Nothing checks what an abstract type promises", the 3,553 characters) and the argument never returned to it.
- Two were asserted as consequences where the goals page calls them weak or not shown: "Goal 1 makes goal 2 worth having: code … is cached in the image … and never discarded" (G-3: weak), "AOT follows from goal 2" (G-6: no demonstrator builds trimmed, E-361).
- The user's decision on speed (2026-11-10: "I don't want to claim better steady state speed") was in no list of what is not claimed, in `design.md` or in `intro/`.
- "Goal 1" and "Goal 2" beside "G-1" and "G-2" named different things.
- **Done:** `design.md`: the head links the goals; §2.6 is "How the two parts depend on each other" (stable code, declared needs), and says which two dependencies are measured and which two are arguments on the weak axes; a new §2.7, "The argument and the goals", maps each axis to what carries it and gives the short arguments for G-5, G-7 and G-8, citing the references for every rule; §4 adds: no claim of better steady-state speed, no claim that code using no trait pays nothing, no trait program in a trimmed binary. The standings stay in `goals.md`; `design.md` links them and copies none.

#### H3. The attribute changes a program's answers where `keep` stores a value

- Taught three times: "The results are the same; only the speed differs" (`traits-for-julia.md`), "chosen for speed, never for results" (`traits-by-example.md` §14), "The attribute chooses speed, never results" (`porting.md` 0.4); the rule is [traits §7.4](../reference/traits.md#74-the-attribute-compiled-and-dynamic).
- The tutorial's own §12: `add!(sc, Circle(1.0))` at the prompt stores a `Dynamic{Shape}`; from a function that knows the type, the circle. A `Dynamic{Shape}` is a `Shape` only ([§7.7](../reference/traits.md#77-dynamicx)). So `sc.shapes[1] isa Scalable`, `sc.shapes[1] == Circle(1.0)` and `count(s -> s isa Scalable, sc.shapes)` differ between the prompt and a script (`keep_at_prompt.jl`: false, false, 0 against true, true, 1).
- A newcomer meets it in the first session: the tutorial shows `sc.shapes[1]` printing as a `Dynamic{Shape}` and `sc.shapes[4]` as a `Circle` in one vector, with no word on what that changes.
- **The pattern:** a value kept in its box reaches code that asks more of it than the trait. It recurs at every `keep`: ten sites in the ports, one of which already unwraps by hand.
- **Done:** [open issue 175](../open-issues.md#2-design), with the case, the rules, the count and three proposals for the synthesis. The tutorial's §12 teaches "read a kept item through its trait", with two checks added to `tutorial.jl`; `traits-for-julia.md` says it under "What happens". The reference is not changed: §7.4's sentence stands until the issue is decided.

#### H4. `intro/results.md` reported the axis that is no goal, and none of the evidence for the main claim

- The page led with four sessions against Python, and `traits-for-julia.md` headed them "Sessions within reach of Python": 1.6 s against 0.63 s, and 3.0–3.3 s against 0.7 s. No goal claims parity with Python.
- The evidence for G-1 on the unified build (E-355, E-357, E-358, E-359, E-360) was on neither page. The costs measured with it (E-356; GT-7, GT-9, GT-11, GT-12) were on neither page.
- Its session totals (E-324) were a build behind `state.md`'s headline (E-337): 1.59–1.63 s there, 1.76–1.80 s here.
- It used the core developers' terms that `intro/` is to avoid, unexplained: "G2 bit", "CodeInstance", "stakeholder", "facts instances", "guarded call", "setting D", "form (f)".
- **Done:** the page is rewritten by claim: the loads (E-355, E-357), new members, types and edits (E-358 to E-360), the sessions against Python with E-337's totals and E-324's steps, each build named; then what it costs, and what is not shown. One term is defined in place ("compiled instance"). `traits-for-julia.md`'s "What you get" 1 carries the loads' numbers, its point 4 is the members, and the sessions moved under "What it costs" as "First-run sessions are still slower than Python's".

### Medium

#### M1. Costs a user meets were missing from the introduction

- "Imports and memberships take a little longer", with no number. Not said: code that uses no trait is 8–18 % slower on DataFrames' small repeated steps (E-356, GT-9); the library loaded late ends 197 plain instances (GT-11); an edit of a method at a trait takes 0.4 s, 2.8 s the first time (E-359, GT-12); a member that joined after its caller costs about 9 ms per operation in each session (E-358, GT-7); no trimmed binary (E-361).
- **Done:** `traits-for-julia.md`, "What it costs": "No faster steady state", "First-run sessions are still slower than Python's", "Loading, editing, and code that uses no trait", and trimmed binaries under "What is not done yet". This is not G-4's whole account (W-138); it is what the evidence has today.

#### M2. The porting guide was not laid out as a path, and four of its quotes had moved

- W-137 asks for "the steps in order, each with what it costs and gains, … each step with the port's commit that shows it, and GT-10's lesson stated". The guide had six steps in a list, without costs or gains. E-355, which measures the path's first step, was not in it.
- **Done:** "The path, in order" in part 0: five steps, each with what changes, what it gains with its experiment and the port's commit, and what it costs today; then "What a port does not do" with the lessons of GT-10, GT-8 and GT-11.
- **The pattern, and its tool:** the guide quotes the ports' code by file and line, and the ports move. `experiments/docs-checks/check_quotes.py` checks every citation: of 23, four had moved or differed (`core.jl:97`, `frontend.jl:62`, `coreloop.jl:154` without its `@inline`, `TraitMakie.jl:229`). Corrected; the tool's README has the counts.
- **Left:** the guide's part B is not read line by line against the ports' heads; W-137 keeps that.

#### M3. Three versions of "what decides the attribute"

- [traits §7.5](../reference/traits.md#75-what-decides) has five steps; step 5 is the scope's fallback: what the caller knows in a trait module, `Compiled` elsewhere. `traits-for-julia.md` wrote "otherwise, in a trait module, what the caller knows" and nothing for elsewhere; `traits-by-example.md` §4 dropped the trait module; they differed on step 3.
- **Done:** both pages give step 3 and step 5 as the reference does.

#### M4. "Never inferred from the methods that exist", and `Callable`

- The tutorial's §3 and `design.md` §2.4 say a membership is never inferred from the methods that exist. §14 says of `Callable`: "Its own methods decide it; nothing is declared." Both are the reference's ([traits §9](../reference/traits.md#9-functions-callable)), and the pages did not mark the second as the exception.
- **Done:** one sentence in the tutorial's §14.

#### M5. "Open" names three things

- An open trait, an open method (`@open`), and "where types are open". The first is who may join; the second gives up the contract's bound. A reader meets "an open method at an open trait" in the first hour.
- **Done:** [open issue 176](../open-issues.md#2-design), with a proposal (*unbounded*, `@unbounded`). No page is changed: the names are the references'.

#### M6. Numbers in the rationale without their build

- `design.md` §2.3's BaseBenchmarks and E-140, and §2.6's E-261, E-265 and E-266, read as today's and are the julia-1.13 build's (E-261 to E-266 are estimates for the unified rule made on it).
- **Done:** each says its build.

#### M7. The tutorial's §19 presented compiling ahead as working

- "`verify_main` … lists every target a program reaches through trait code, for `juliac --trim`." The list exists; no demonstrator builds trimmed (E-361, GT-13).
- **Done:** one sentence, with a link.

### Proposals not carried out

- **P1. The order of `traits-for-julia.md`.** "What you write" gives the five-step list of what decides the attribute, `keep`, the split's limit of four and strict mode before the first running example. A newcomer would be better served by the worked example first, and the attribute after it. Not done: it rearranges the page, and the tutorial already has the gentler order.
- **P2. The evidence's summary.** `design/evidence.md` ends with a summary organised by "the four steps of section 3" (the rationale's numbering of October) and by the measurement round of 2026-10-20, with E-355 added as one bullet. `goals.md` §2 is now the standing by axis. Two summaries, one of them a build behind. Proposal: the evidence's sections by axis (G-1 to G-8), its summary replaced by a link to `goals.md` §2. It belongs with the account of G-4 (W-138).
- **P3. The motivation's numbers.** `design.md` §1 cites `design-findings.md`, a history log, for the 769 signatures (Julia 1.12) and the 3,553 characters. Neither has a row in the evidence on 1.13.
- **P4. Error messages beside plain Julia's** in `intro/`: the pages show the trait messages only. W-136.

### Low

- **L1.** `README.md`'s convention "one Julia job at a time" is a copy of the machine's rule that CLAUDE.md has since changed (cores by load). **Done:** the line links the record's standing constraints.
- **L2.** `design.md` §2.2's count of pirates (837 of 65,318, none refused) is of the package prototype, and says so. Strict mode on a stack of ports on the unified build is not measured (`intro/results.md`, "not shown yet").
- **L3.** `state.md` is headed 2026-11-09, with §6.1 "Today (2026-11-10)"; its §5 is a table of how the sessions' times fell, which is history by content. Not changed here.

## What holds up

- **Every example of `intro/` runs on the head,** and every message the pages quote is the message printed.
- **The four-step argument** reads as an argument: each step adds one thing, says what it rests on, and names its exceptions where it claims the guarantee. Lemma O's short form in `design.md` is the reference's (facts §1 counts a type's supertraits among its supertypes, which the lemma needs).
- **The pages credit the right part:** load protection is the facts mode's, for any code; traits make it cheap. E-355's "one line" is the strongest single number for that sentence, and is now on the pages.
- **The tutorial** covers the language in the reference's order with one running library, and marks what is Planned.
- **Links and section citations** in `intro/`, `design.md`, `goals.md` and `state.md` resolve.

## Addendum, 2026-11-11: the proposals carried out

The user, on the list of what was left: "Do that too".

- **P1, done.** `intro/traits-for-julia.md`: "What you write" is now five lines; the worked example follows it; the rules of each part come after, as "The parts, one by one". "What happens" defines `Compiled` and `Dynamic` in two sentences, since the example now precedes them.
- **P2, done, in a narrower form.** `design/evidence.md`'s summary is a table from each axis to the sections that hold its numbers, and it leaves the standing to `goals.md` §2. The sections are not renumbered: "evidence §1" to "§4c" are cited across the documents.
  - The old summary was not only a copy. Eight of its numbers were in no row of the body (among them the motivation's CSV read of 2.5 s against 0.19 s, which `design.md` §1 cites, and the run of 2026-10-27's rows for a new problem type and a new closure). So its lists are kept as a section of their own, "The earlier build's rounds: what they showed", under their builds. Its bullet on E-355 is dropped, since §1 has it; its list of what is not shown is dropped, since §5 and §1 have each item.
  - §5 says first that what is not shown today, by axis, is the goals' weakest points.
- **Part B of the porting guide, read against the ports' heads** (forks ddc20f6, TraitDifferentialEquations 6658c65, TraitMakie c9e294b, TraitReport a4bcf33, NetworkDynamics d8c9c49, TraitWorld 05991fc). Checked by `git grep` in each port: the 22 traits part B names and their modules; the kernels over `Vector{Column}`; `byrow`'s `promote_op`; the extensions' memberships; the workload's display at `IOContext{IO}(IOBuffer())`; `fromsource`; the right-hand side partially evaluated; `FunctionDynamics{typeof(f), …}`; the library's tools and macros that "The language in one screen" names; the deviations C-41, C-54 and L-56 and the open issues 157 to 165 it cites, all still open.
  - One sentence was wrong: CSV's InlineStrings extension "declares memberships only". It declares memberships, has helper functions of its own, and adds no method to CSV's functions. Corrected.
  - Not checked: the numbers of part B against new runs. They name their experiments.
- **P3, left:** the motivation's numbers (769 signatures on Julia 1.12; the 3,553 characters) on 1.13 need a run on stock Julia. With the synthesis.
- W-137 is done.
