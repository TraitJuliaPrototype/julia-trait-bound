# Review: the state of the documentation (2026-11-09)

The user (2026-11-09): "send a second Fable agent out to look at the state of the documentation, especially whether the reference is consistent and reflected in the other documents."

A Fable agent, at the user's explicit request (the exception to the rule of no subagents on the shared host). Read only; no document but this one is changed. The main session records what is done with each finding.

**What was read:**
- `CLAUDE.md`, `reference/README.md`, `record/INDEX.md` (the first half; the reviews table), `state.md`;
- the four references in full: `traits.md`, `facts.md`, `compiler.md`, `lowering.md`, with their Deviations tables;
- `design.md`, `glossary.md` (the index and the entries on open and closed, keys, the split, strict mode, the policies, guards, the slot), `design/julia-changes.md`, `design/alternatives.md` (the `IO` topic), `design/evidence.md` (the builds, §1, §2's `IO` rows, §3's rows of today);
- `open-issues.md` §1 in full and items 159–170; `record/decisions.md` §9's rows of 2026-11-09, "Pending" and the superseded `IO` rows; `record/todo.md` W-100 to W-129; `record/experiments.md` E-329 to E-338;
- `intro/traits-for-julia.md` (status, strict mode, the guarantee, "What is not done yet"), `intro/traits-by-example.md` §18–§20, `intro/porting.md` (status, the table of constructs, 0.4, A10, A11, B1.8), the heads of `intro/results.md`, `design/performance.md`, `design/other-languages.md`, `design/implementation.md`, `design/mechanisms.md`;
- in the code: `julia-unified/base/iotrait.jl` in full; the exported runtime entries the references name (`src/datatype.c`, `src/gf.c`, `src/typemap.c`), `base/show.jl`'s `IOContext{IO}`; TraitWorld-unified's `src/trait.jl` (`@closed_after_load`), `src/classify.jl` (`@open`, `@bounded`), `src/scope.jl`, `src/strict.jl`, the test files; the gates and audit tools of `experiments/unification/`.

**Not read:** `intro/traits-by-example.md` §1–§17, `intro/results.md` beyond its header, `design/other-languages.md`, `design/performance.md`, the second half of `record/INDEX.md`, `open-issues.md` §2 before item 159 and §3–§6, the decision log before §9, `record/experiments.md` before E-329; the plans, the earlier reviews and the session notes (history, out of scope as targets); the ports' code.

**What was run** (scripts in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/24a7c1e0-a2ec-401b-8a6e-3d7a1561fce2/scratchpad/doc-review/`):
- `check_links.py`: every markdown link's file and anchor, and every prose citation "traits §x.y", "compiler §x.y", "facts §x.y", "lowering §x.y" (and bare "§x.y" inside a reference), checked against the headings. Output `links.txt`: 112 problems in 45 current files, 75 of them in `open-issues.md`'s closed items, the decision log, the registry, the work queue and `alternatives.md` (old section numbers in rows that are history by content); the rest are M5 below. Within the four references: one bad anchor (M5).
- `check_heads.sh`: the build heads named in the references' headers against `state.md` §6.1. Output `heads.txt`: four stale copies (M1).
- `probe_io_convert.jl` on `julia-unified/julia` (its binary reports b05ae361e0), niced, one job: whether plain code at a value typed `IO` returns a different type than through the stream's own type. Output `probe_io_convert.out` (H4).

**Not run:** builds, benchmarks, the gates, the suites.

## Findings, by severity

### High

#### H1. `design.md` still says Base's `IO` is a trait closed after load — verified

- `design.md:58`: "A trait's author may close the trait after load instead: … Base's `IO` does ([traits §9b])."
- The references, since b05ae361e0: `traits.md:858` "`IO` is Julia's closed abstract type, with a contract"; `compiler.md:692` "`Core.IO` is a closed abstract type with a contract (§7.1). … It has no entry, cell or guard". `base/iotrait.jl` declares a contract and candidates and no set; `TraitWorld-unified/src/trait.jl:102` is the only writer of `jl_set_closed_after_load`.
- `design.md` is the one current document outside the history files that still describes the morning's design (`IO` a set closed after load). Every other current document I checked follows the references: `state.md:25`, `open-issues.md` 164 (closed), `decisions.md:408` and the superseded rows `:422–424`, `alternatives.md:451–461`, `evidence.md:99, 199`, `todo.md:162`, `intro/porting.md:48, 206–216`.
- **Fix:** the references win. `design.md:58` should read: a trait's author may close the trait after load ([traits §3.4]); Base's `IO` is instead a closed abstract type with a contract, erased by `IOContext{IO}` where its author chooses ([traits §9b]).

#### H2. Strict mode is "Planned (W-114)" in `facts.md` and "Implemented (W-114)" in the three other references; `design.md` copies the stale one — verified

- `facts.md:148` (§2.3 Two tiers), `:372` (§11.2), `:389` (§11.3), `:442` (§13.3), `:470` and `:473` (the status index): "Planned (W-114)".
- `traits.md:1031` (§12.3): "Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114) … With T-96, T-97, T-98"; `lowering.md:257` (§13) the same; `compiler.md:790` (§10.2): the deletion hook implemented (`jl_set_method_deletion_hook`, `src/gf.c:6842`); `compiler.md:197` (§2.6): `--trim` implemented on cb7f55bd35 (W-100), with C-53.
- The code: `TraitWorld-unified/src/strict.jl`, `test/strict.jl`; `todo.md` W-114 row: done 2026-11-07.
- `design.md:171` copies `facts.md`: "strict mode is Planned ([facts §2.3])"; `todo.md` W-116's row records that choice ("strict mode Planned in §4"). `intro/traits-for-julia.md:176, 330` and `intro/traits-by-example.md:782–814` teach it as built, correctly.
- A second stale status on the same page: `facts.md:108` (§2.1): "20 of 21 cases pass … one waits for `@enforce_fully_typed` (W-114)"; `:460` the same. W-114's row in `todo.md` says `AC_16` re-judged, 21 of 21; `state.md:48` says the 21 acceptance cases pass.
- **Fix:** traits, compiler and lowering win on the mechanism; `facts.md` wins on what it guarantees. Flip `facts.md` §2.3, §11.2, §11.3 to Implemented (TraitWorld 7adcc94, `unified` 5f2373b2d5; W-114), naming T-96 (no binding hook), T-97 (no warning for an extension's method) and T-98 (the ambiguity at a membership is a warning under strict mode) beside the rows of §11.3's table they weaken; §13.3 to Implemented (cb7f55bd35, W-100, with C-53, not run here); §2.1 to 21 of 21. Then `design.md:171`: "strict mode is built; its tier holds with the deviations T-96 to T-98".

#### H3. The split is "Planned (W-109)" in `facts.md` §9 and Implemented in traits §7.9 and compiler §7.1–§7.3; and `facts.md` §9 does not know today's conversion or the closed type with a contract — verified

- `facts.md:322` (§9) and `:468` (the status index): "Planned (W-109)".
- `compiler.md:621, 643, 668` (§7.1–§7.3): Implemented on e70675a606 and later; `traits.md:746` (§7.9): Implemented on e70675a606 with TraitWorld e9a63f7; the conversion on 0c836f3ef6.
- The rule differs too. `facts.md:316`: "The result is the operation's declared result, asserted on every branch that is not known to give it. A result of another type raises a `TypeError`." `traits.md:741`: "A member's result is converted to it, as a return annotation `f(…)::R` converts, and asserted: a result that does not convert raises"; `traits.md:947, 977`: `TypeError`, `MethodError` (a result that does not convert); `compiler.md:639`: "A branch through a pointer and the fallback convert to `RT`". `facts.md:308` covers "a value of an open set of types" only; `compiler.md:616` and `traits.md:168` extend the rule to a closed abstract type with a contract.
- **Fix:** `facts.md` §9 to Implemented (W-109; `unified` e70675a606, 0c836f3ef6; with C-38, C-39, C-81), its result rule restated as traits §7.9's (converted, then asserted; `MethodError` where it does not convert), and one sentence that a closed type with a contract takes the same rule ([compiler §7.1]).

#### H4. The contract changes plain code's results at a value typed `IO`, and the guarantees' page says plain code keeps all of Julia's behaviour — verified by a probe

- `facts.md:421` (§13.1): "Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation." `facts.md:90` (§2.1): code compiled by facts "raises where plain code does not only where a value lacks a declared result type". `decisions.md:408` cites facts §13.1 as what the decision preserves: "Base's methods typed `io::IO` are compiled per stream type, as in Julia, so plain code keeps Julia's speed and invalidation ([facts §13.1])".
- `compiler.md:616–619`: the rule for a closed type with a contract is inference's, in either policy ("Under the facts mode, each branch of the split is a fact"). `base/iotrait.jl` declares the contract unconditionally.
- The probe (`probe_io_convert.jl`, binary b05ae361e0), all plain code, no trait module, no TraitWorld: a stream `S <: IO` whose `write(::S, ::UInt8)` returns `UInt(7)`. Through the stream's type, `write(s, 0x01)` returns `UInt64 7`. Through a `Vector{IO}`'s element, it returns `Int64 7`. A stream whose `write` returns a `String` returns it through its type and raises `MethodError` through the element. On vanilla both calls return what the method returns.
- So on the unified build, plain code at a value typed `IO` sees a result type Julia's plain code does not, and raises where Julia's does not. `traits.md:862` says the call converts the count to `Int` and `traits.md:169` says "For a closed type, Julia's rules apply unchanged"; neither says the conversion applies in plain code, nor that a caller through `IO` sees another type than a caller through the stream's type. `design.md:170` ("No change to results beyond values that Julia decides by inference") does not name it either. Open issue 168 records the unchecked members, not this.
- This is the user's decision as built, not a mistake of the implementation. The finding is that the guarantees' page and the rationale do not state its consequence.
- **Fix:** `facts.md` wins on what compiled code may assume, so it must say it: §13.1 names the exception (at a value typed by a closed type with a contract, an operation's result is the declared result in plain code too, converted; it raises where the member's result does not convert); §2.1's "or raises" clause names the closed type's operations beside the trait's and `Callable`'s. `traits.md` §3.4 drops "unchanged" at `:169` and §9b says that a caller through `IO` sees an `Int` where the stream returns another integer. `design.md:170` names it under what is not claimed. The decision row's citation of facts §13.1 then stands.

### Medium

#### M1. The build heads in the references' headers are stale again, in four places — verified (`check_heads.sh`)

- `state.md:79–80` (the one home): `unified` b05ae361e0, TraitWorld-unified 4443d2c.
- `reference/README.md:84`: "Latest: `unified` 350c5b1c59"; `:85`: "TraitWorld `unified` e967ca0".
- `compiler.md:876` (the Deviations header): "Branch `unified` at 5f0a8ffd50 (…)", though the same sentence lists commits up to W-123, and none of W-129's nine commits.
- `lowering.md:281`: "TraitWorld `unified` e7ff8e2 (the first slice, W-106)"; `traits.md:1177` names no build at all.
- The review of 2026-11-08 (M5) corrected the first two; they went stale within a day. CLAUDE.md: a copy names its source and build, or it goes stale.
- **Fix:** stop copying. The README and the three headers link `state.md` §6.1 for the heads and keep only what is theirs (the README: the stages built; the Deviations headers: the IDs' rule). If a copy is kept, `check_heads.sh` (above) belongs in `experiments/` with a README, run before a commit that moves a head.

#### M2. Status lines that lag their own reference: a bare "W-n" reads as pending where the work is done — verified

- `traits.md:249` (§4.1): "the result's assertion at a call through the trait: W-109" against `traits.md:746` (§7.9 Implemented on e70675a606).
- `traits.md:528` (§6.1): "how a method is compiled (§7.3): W-109" against `traits.md:650` (§7.3's classification implemented in TraitWorld 59134ef, bb78d02).
- `lowering.md:39` (§1): "`@trait_module`, `keep` and casts W-111" against `lowering.md:135, 162` (Implemented, bb78d02, e692e57ab7).
- `lowering.md:71` (§2): "the flag of compiler §6.8 with W-109" against `compiler.md:595` (the flag implemented on e70675a606, TraitWorld e9a63f7).
- `lowering.md:123` (§5): "The per-method options with what reads them: W-109 (`@bounded`, `@open`), W-100 (`@facts`)" against `traits.md:650` and `compiler.md:145` (both built; `TraitWorld-unified/src/classify.jl:387, 396`).
- **Fix:** each status line says Implemented or Planned and names the commit; a W-item alone is not a status. The README's convention (`reference/README.md:21–26`) could say so in one line.

#### M3. The stack's own rule is broken again by W-129, as the review of 2026-11-08 found for the slot — verified

- `design/julia-changes.md:119`: "A stage's rework replaces its commits instead of adding fixes on top".
- `julia-changes.md:201–209`, rows 72–80: b133374e9d opens `Core.IO` as a set with `Dynamic{IO}` and raising defaults; d554855579, 0c836f3ef6, 7bd8b6e512, 43c222c751, 1906196731, 45fa624462, 53ec4356bf are fixes on top; b05ae361e0 undoes 72's headline ("`Core.IO` is no set; … `Dynamic{IO}` are gone"). The row's own text says what was removed.
- `compiler.md:378` (§4.8's status) cites b133374e9d for "Core and Base loaded at the end of Base's build", a commit whose main change is reverted; `decisions.md:400` cites it for the declared results.
- The review of 2026-11-08, M2, found the same for the code slot's four commits and recommended folding before any upstream proposal (W-19); nothing in `todo.md` W-129 or W-19 records a fold.
- **Fix:** fold rows 71–80 into self-contained commits (closed after load; the general rules E-331 to E-336; the contract on the closed type) and name the folded commits in §4.8, §7.5 and the decision rows; or record in `julia-changes.md` §7 that the rule is set aside while a stage is measured, with the fold as W-129's last step.

#### M4. Open issue 160 is waiting for the user, and the reference states the opposite without marking it Open — verified

- `open-issues.md:77`: "Open issue 160: the cast names recognized by their binding, not reserved (proposal (a), mine)"; `:213–221` the item.
- `traits.md:696` (§7.6): "The names are reserved, as `ccall` is"; `compiler.md:600` (§6.9) the same; `reference/README.md:71` (P-23). None links 160 (`grep 160 reference/traits.md` finds nothing).
- CLAUDE.md: a decision waiting for the user is marked Open in the reference, with the issue linked; the reference "does not describe a guess". §7.3 does this for 165 (`traits.md:632`) and C-54 for 163 (`compiler.md:917`).
- **Fix:** `traits.md` §7.6 and `compiler.md` §6.9: the reservation marked Open ([open issue 160]), with today's behaviour stated as the implementation's; the README's P-23 row points at 160.

#### M5. Section citations and anchors in current documents that do not resolve — verified (`check_links.py`)

- In the references: `lowering.md:113` links `README.md#the-choices-in-this-draft`; the heading is "The choices in these references". `facts.md:136, 338` cite "§3.1" and "§5.6" as the page's own sections (they are the compiler's §3.1, §5.6; the sentence names the compiler two clauses earlier, so a reader recovers it).
- In the chapters: `design/other-languages.md:307, 308, 310, 312` cite facts §10.2 and §10.3 (strict mode is §11.2, §11.3 since W-105); `:407` traits §4.10 (gone); `design/performance.md:101` lowering §9.3; `record/performance-explorations.md:21` compiler §1.6 (none exists).
- In `open-issues.md`: 40 citations of old section numbers, all in "Closed items" (`:427–860`), and two dead anchors (`:520` `intro/porting.md#b6-…`, `:559` `state.md#61-today-2026-10-19`). Closed items are history by content inside a current document; CLAUDE.md leaves history alone, so the choice is the main session's: fix them, or state at `:343` that closed items cite the section numbers of their day.
- **Fix:** the eleven citations outside `open-issues.md` corrected to the current sections; the script kept in `experiments/` as the tool CLAUDE.md asks for where a pattern recurs (it does: the review of 2026-10-26 of `lowering.md` found 94 stale line citations).

#### M6. The glossary does not know the terms today's design introduced — verified

- `traits.md:168` (§3.4) defines a closed abstract type's contract and `:863` (§9b) the erased stream and the eraser `IOContext{IO}`; `compiler.md:632, 693` the candidates of a closed type.
- `glossary.md:113–118` ("Open and closed"): a trait is open, an abstract type is closed, closed after load; nothing on a closed type with a contract. `:240–245` ("Split"): "tests the value's type against the trait's members"; nothing on a closed type's candidates. No entry "Contract", "Candidates", "Eraser" or "Erased"; the index (`:10–78`) has none.
- CLAUDE.md: the reference defines a term where it first matters; the glossary links there. W-115's row says the glossary was rewritten for the current references on 2026-11-09, before `IO`'s change.
- **Fix:** entries "Contract" (a trait's; a closed type's, [traits §3.4]), "Candidates of a split" ([compiler §7.2]) and "Eraser, erased stream" ([traits §9b]); one clause each in "Open and closed" and "Split".

### Low

#### L1. Every reference calls itself a draft; the README says adopted

- `traits.md:3`, `facts.md:3`, `compiler.md:3`, `lowering.md:3`: "**Draft** (W-105 …)". `reference/README.md:3`: adopted by the user on 2026-11-06.
- `README.md:24` defines a status label **Proposed** for a choice waiting for the user; no section uses it. The references mark such choices "mine (date)" and list them in open issues §1 (`open-issues.md:49–94`), which works; the README should describe that convention instead.

#### L2. "The stages W-98 to W-114" names the stages of 2026-11-07

- `compiler.md:7`, `julia-changes.md:116`. The stack carries W-101, W-123, W-128 and W-129 too (`julia-changes.md:175–209`; `state.md:10`).

#### L3. The compiler's status index omits two of today's deviations

- `compiler.md:849` (§4.7, §4.8): "with C-76, C-77" and not C-79; `:863` (§7.1–§7.3): "with C-38, C-39" and not C-81; `:865` names neither.

#### L4. Code comments name the retired C-18

- `julia-unified/src/datatype.c:720, 1162`, `src/gf.c:4074`: "compiler C-18", retired 2026-11-07 (`compiler.md:881`). Found by the review of 2026-11-08 (M5), still there. Not a document; noted because the references' IDs are the code's too.

#### L5. Stale "as of" headers on pages whose rows name their builds

- `julia-changes.md:3, 5`: "as of 2026-10-28", "Size (00dcc9994c): 65 commits"; `evidence.md:3`: "as of 2026-10-28"; `open-issues.md:3`: "as of 2026-10-27". Each row below names its build, so the numbers are sound; the headers are not. `record/INDEX.md:19` still describes `design/mechanisms.md` as "the detail `design.md` compresses" while `:14` and `:266` say it is retired.

#### L6. `todo.md`'s W-129 row points at a flag that is gone

- `todo.md:162`: "(b) built … correct and far slower, both thresholds crossed, flagged ([open issues §1])". §1 (`open-issues.md:24–47`) carries no such flag; the decision of the afternoon replaced it (`decisions.md:408, 422`). The row should say the flag was resolved by the decision.

#### L7. "At `T`'s key" where keys are Optional

- `traits.md:1108` (§16): "compiled into that package's image … at `T`'s key"; `lowering.md:232` (§12): "a compile request at `S`'s key". Keys are Optional (`traits.md:618`); until built, the request is at `S`'s type (`lowering.md:238` says so one paragraph later). Say "at `S`'s type (per key, Optional)".

#### L8. The contract slot holds two kinds of object, and §4.1 names one

- `compiler.md:289` (§4.1): a set's `TypeName` carries its contract, "written once by the library". `compiler.md:616` (§7.1): a closed type's contract is the operations' methods, written by `jl_declare_contract`. `decisions.md:400`: the one slot holds either (a set's: the library's object; a closed type's: the methods' `svec`). §4.1 should say that the slot holds the library's object for a set and the runtime's list for a closed type with a contract (§7.1).

## What holds up

- **Today's change is reflected where it matters.** `IO` as a closed abstract type with a contract, the eraser `IOContext{IO}`, closed after load, the unmet intersection as a final negative, the typemap rule and the call-signature backedge appear consistently in `state.md` §2 and §6.3, `open-issues.md` §1 and items 164–170, `decisions.md` §9 (each row naming its reference sections and build; the morning's `IO` rows marked superseded with the replacing row), `alternatives.md` (164's options not taken, with the reasons and E-numbers), `evidence.md` (E-329 to E-338 with builds, loads and controls), `todo.md` W-129, `intro/porting.md` (0.4, A10, A11, B1.8). The one stale description of the morning's design outside the history files is H1.
- **`traits.md` §9b and `compiler.md` §7.5 agree with each other and with the code.** The nine operations, the four declared results and the four candidates in their order are exactly `base/iotrait.jl`'s. `IOContext{IO}(io, key => value, …)` is in `base/show.jl:342`.
- **Sampled Implemented claims exist in the code:** `jl_declare_contract`, `jl_register_candidate`, `jl_candidates_of` (`src/datatype.c:265–301`), `jl_set_closed_after_load` (`:1293`), `jl_set_input_params`, `jl_set_declared_fields`, `jl_open_set_methods_of` (`src/gf.c:2565`), the deletion hook (`:6842`); the typemap's branch for a set at a level's position (`src/typemap.c:1453–1468`); the call signature on the backedge (`src/gf.c:3322–3325`); TraitWorld's `@closed_after_load` in the trait's body (`src/trait.jl:194`), `@open`, `@bounded`, `@trait_module`, `strict.jl`; the gates the references cite (`n16` to `n21`, `m2_typemap_linear`, `m2_parametric_replay`, `n6_attribute`) in `experiments/unification/gates/`; the audit tools open issues 166–168 cite, with a README, in `experiments/unification/audit/`.
- **The Deviations tables follow the rules:** IDs contiguous and never reused (T-1 to T-106, F-1 to F-24, C-1 to C-81, L-1 to L-58); retired rows marked *Retired* with a pointer and a commit; open rows name a file, a function or a gate.
- **Open sections link their issues** (§12.1 to §1.19, §7.3 to 165, C-54 to 163), but for M4.
- **The references contain no history words** in the sense CLAUDE.md forbids; the few "was", "until" and "replaced" are rules, not stories.
- **The teaching pages** teach the current design: strict mode as built, keys and named implementations as Optional and Planned, the eraser in the porting guide; `intro/results.md` names its build.

## Recommendations, in order

1. H1 and H4 together: `design.md` §2.2 and §4, `facts.md` §2.1 and §13.1, `traits.md` §3.4 and §9b, in one commit with the decision row's citation checked.
2. H2 and H3: `facts.md`'s status lines and §9's rule brought to the other references'; `design.md:171` with it.
3. M1 and M2: the heads out of the references' headers (or `check_heads.sh` adopted), and the five lagging status lines.
4. M4: open issue 160 linked from §7.6 and §6.9, marked Open.
5. M3: W-129's commits folded, or the exception recorded.
6. M5 and M6: the eleven citations, the glossary's three entries; `check_links.py` adopted into `experiments/` with a README.
7. The lows with the next pass over the record.
