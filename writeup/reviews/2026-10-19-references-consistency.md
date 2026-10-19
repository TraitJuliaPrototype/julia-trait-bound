# Fresh-eyes consistency review of the references and the documents around them (2026-10-19)

Reviewed at design-repository commit aac8b79: `reference/README.md`, the four references (`traits.md`, `facts.md`, `compiler.md`, `lowering.md`), `design.md`, `design/argument.md`, `state.md`, `glossary.md`, `README.md`, `open-issues.md`, `intro/traits-for-julia.md`, `intro/traits-by-example.md`, `intro/porting.md`, and the retired pointer pages `design/implementation.md`, `design/mechanisms.md`; `design/julia-changes.md`, `design/evidence.md`, `design/comparison.md`, `design/alternatives.md` and `intro/results.md` were grepped, not read in full. Reviews, explorations, plans, notes and the record were treated as history.

**Method.** Every document was read as an outsider. Claims were checked against each other and, where cheap, against code: TraitWorld at 227781a (the commit the Deviations tables cite; it is TraitWorld's current HEAD, *verified*). A link checker was run over every relative link and anchor in the eighteen documents above (about 750 links in the six largest alone): **every file and anchor resolves** (*verified*; the checker was probed with a deliberately bad anchor and reports it). So the findings below are about content, not broken links.

**Counts.** High 6, Medium 16, Low 16.

Severity: **high** = a contradiction about the design or a false statement; **medium** = an inconsistency a reader trips over; **low** = wording, a stale term, a link text.

---

## High

### H1. The glossary still says the one-line form infers a field (today's decision contradicted)

- `glossary.md:163`: "Without `by`, `@implement` infers the field: the one field whose type implements the trait, else the field named `data`."
- Contradicts the decision (`record/decisions.md:22`: "it never picks a field, neither one named `data` nor the only conforming one"), `reference/traits.md:377`, `design.md:58`, `intro/traits-for-julia.md:94`, `intro/traits-by-example.md:187`.
- *Verified against code:* at 227781a `_implement_oneline` (`TraitWorld/src/implement.jl:1147`, `:1198`–`1216`) never picks a field; it raises and lists the fields whose type conforms with their `by` lines.
- This was the only place outside the history directories where the old rule survives (grep over `writeup/` for "named `data`", "the only field", "infers the field", "without `by`"; the other hit is `explorations/keys-plan.md:89`, history).
- **Fix:** replace the sentence by "Without `by`, the one-line form means the type implements the operations itself; it never picks a field, not one named `data`, not the only conforming one ([traits §5.2](../reference/traits.md#52-one-line))."

### H2. Two references plan different owners for the test bed

- `reference/facts.md:267` ("Planned: an owner of its own for plain code under `all`"), `:280` ("Plain code's owner … under `all` it is an owner of its own"), and F-2 (`:567`: "Under `all`, plain code has an owner of its own").
- `reference/compiler.md:276` (table: "Planned: facts, the test bed's owner"), `:290` ("Under the test bed, code compiled by facts gets an owner of its own"), the summary `:30` ("an owner of its own for the test bed"), and C-2 (`:732`: "Under the test bed, code compiled by facts has an owner of its own"); `state.md:83` follows compiler.md.
- These are two different designs: in facts.md's, the default owner `nothing` keeps holding facts code under `all` and the compiler's plain code moves to a new owner; in compiler.md's, `nothing` holds plain code and facts code of neutral methods moves. They differ in what `jl_default_owner`, `jl_type_infer`, the compile queues and the images do under `all`. The two deviation rows (F-2, C-2) record one deviation with opposite content.
- Also `reference/facts.md:78` says "The design uses two owners for code that runs"; with either plan there are three under `all`.
- **Fix:** decide which code moves (cache owners are Julia's interface, so compiler.md wins on the spelling; the facts reference should state only the property "plain results and results compiled by facts never share a cache"), then make F-2 and C-2 say the same thing and correct `facts.md:78`.

### H3. The package-extension rule is Open in one place and Planned in two others

- `reference/facts.md:143` (§2.2 G2 exceptions): "**Open:** refused by an extension rule, or admitted as the stakeholder's change (open issues §1.10)."
- `reference/facts.md:438` (§10.3, status **Planned** at `:430`): "a package extension's winning method at a fact whose signature contains none of its triggers' types | at the extension's load"; F-6 (`:571`) records the missing error as a deviation, that is, as decided design.
- `reference/traits.md:820` ("A pirate … brought by a package extension, is refused too") with status **Planned** at `:823`.
- `open-issues.md:14` (§1.10) still lists "whether a parent's own extension may override its parent's method" as waiting for the user, and `intro/traits-for-julia.md:289` says "(still being decided)".
- By the README (`reference/README.md:26`), Planned means decided; Open means not. One item cannot be both.
- **Fix:** until the user decides §1.10, mark the row in §10.3 and the sentence in traits §12.3 **Open**, drop the extension clause from F-6 (a deviation needs a decided rule), and keep §2.2 as is.

### H4. `Dynamic` beyond four implementations has four statuses

- `reference/traits.md:756`: **Planned** ("a faster path beyond four implementations").
- `reference/facts.md:365` and the status index `:545`: **Open**.
- `reference/compiler.md:31`, `:504`: **Optional** ("When a demonstrator has five implementations").
- `reference/lowering.md:483`: "**Planned** as an option".
- **Fix:** one status in all four. Optional fits the stated condition (built when a demonstrator needs it); then traits §10 and lowering §13 say "Optional (compiler §3.3)", and facts §9 says "Optional" instead of Open (nothing is undecided: the fallback is the design, a faster path is an addition).

### H5. Documents still name the retired pages as the rules, or give them precedence

- `open-issues.md:3`: "The current design is `design.md` and `design/implementation.md`; the decisions in force are in its §7". Both halves are stale: implementation.md is a pointer page and its §7 says the decisions are in the record.
- `intro/traits-for-julia.md:10`: "The precise rules are in `../design/implementation.md`"; `:372`: "`../design.md`: the precise rules and the argument behind them" (design.md is now the rationale; the rules are in the references).
- `intro/porting.md:3`: "the four steps, the rules and the terms precisely in `../design/implementation.md`".
- `design/comparison.md:3`–`4`: "A chapter of The implementation in detail … Where this chapter and `implementation.md` disagree, `implementation.md` wins." This contradicts `reference/README.md:3` (the references win).
- `design/evidence.md:3`, `design/performance.md:3`, `design/alternatives.md:3`: "A chapter of The implementation in detail (implementation.md)".
- (`record/INDEX.md:157`, `:163`–`166` say implementation.md is "current, with `design.md` the source of truth" and the chapters are "a chapter of implementation.md, which wins": the record is history, but it is the index agents read first.)
- **Fix:** point each at the references: "The precise rules are in the [references](../reference/README.md)"; in comparison.md: "Where this chapter and the references disagree, the references win"; in open-issues.md: "The current design is the references; the decisions, with their origins, are in `record/decisions.md`."

### H6. `state.md` says the design has four rules; `design.md` has three

- `state.md:12`: "The design: four rules, keys instead of representations …".
- `design.md:74`–`80`: "Three rules carry the design" (facts, ownership, the boundary). `design/alternatives.md:77` and the closed item `open-issues.md:248` ("rule 4 is gone") agree with three.
- **Fix:** "three rules" in state.md.

---

## Medium

### M1. `compiler.md` defines "fact" as what the other references call a "fact signature"

- `reference/compiler.md:10`: "a *fact* is a call signature that only its stakeholders or a pirate can change".
- `reference/facts.md:66`: a fact is "at the concrete signature `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`"; `:73`: the *fact signature* is the signature. `design.md:19` and `glossary.md:337`–`338` follow facts.md.
- **Fix:** in compiler.md: "a *fact signature* is a call signature that only its stakeholders or a pirate can change; a *fact* is what dispatch selects at one".

### M2. `compiler.md` uses a status, **Optional**, that the conventions do not have

- `reference/compiler.md:18` adds "Optional: built only if a measurement or a demonstrator asks for it"; `reference/README.md:26` lists Implemented, Planned, Open only. lowering.md's "Planned as an option" (`:483`) is the symptom.
- **Fix:** either add Optional to the README's list (with compiler.md's definition, and the rule that an Optional item needs no deviation row), or fold compiler.md's Optional items into Open with a link to open-issues.

### M3. "Boundary method" is defined as a method of a trait module, but two of the three kinds are not

- `reference/facts.md:84`: "a method of a trait module that is compiled in its caller's mode"; `:258`: "a method of a trait module … TraitWorld's entries, `conformance` methods, and the entry methods compiled ahead".
- `reference/lowering.md:85`, `:121`: `@trait` and `@implement` expand in the declaring module, "a trait module or plain code"; `reference/traits.md:142`: "A user's types usually conform in plain code". So `conformance` methods usually live in plain modules. `reference/lowering.md:396`: the entry compiled ahead is defined "in `T`'s module", the user's.
- `reference/compiler.md:238`–`249` ties the flag to the method, not the module, which is right.
- No behavioural difference follows (in a plain module a boundary and a neutral method get the same code), but the definition is false as stated.
- **Fix:** "a method carrying the boundary flag, compiled in its caller's mode, wherever it is defined: TraitWorld's entries, `conformance` methods and the entries compiled ahead".

### M4. The lowering reference records a deviation (L-6) from a rule the traits reference does not state

- `reference/traits.md:746`: "**Outside trait modules,** write `Dynamic{X}` out", under a section whose status (`:754`) lists no Planned change for this.
- `reference/lowering.md:666` (L-6): "the reference says: a trait's name as a type means its `Dynamic`"; `:651` (§17): the rewrite "stands in for a trait's name as an abstract type in any field or container"; `reference/compiler.md:721` (§7, Planned, last): syntax includes "a trait's name in a field meaning its `Dynamic`". `intro/traits-for-julia.md:361` presents writing `Dynamic{X}` out as a limitation "until" traits are in the type system.
- lowering.md "decides nothing they decide" (`reference/lowering.md:5`); here it states an intention traits.md lacks.
- **Fix:** either traits §10 adds "Planned, with traits in the type system (§16): a trait's name in any field or container means its `Dynamic`, outside trait modules too", or L-6 and the §17 row are reworded to the encoding only (the source rewrite) without claiming a different rule.

### M5. `Dynamic` of a parametric trait: result types inferred (traits) or `Any` (lowering)

- `reference/traits.md:733`: "A parametric trait's `Dynamic` fixes the parameters its operations' result types use, `Dynamic{StateVector{Float64}}`, so code after a call infers."
- `reference/lowering.md:499`: "`RT` is the declared result type, or `Any` where it names `Self` or a parameter."
- If both are true, an operation returning `T` on a `Dynamic{StateVector{Float64}}` is asserted to `Any`, and the code after it does not infer. One of the two is the design; the other is a deviation or wrong.
- **Fix:** decide; if lowering describes the as-built, add an L- row ("the split asserts `Any` where the declared type names a parameter"), else correct traits §10.

### M6. `compiler.md` §3.1 states as a rule what `facts.md` lists as a deviation

- `reference/compiler.md:477` (Rules): "The callee's code is the default owner's: a facts method's facts code, any other method's plain code (§2.5)."
- `reference/facts.md:237`: a run-time site runs facts code "for every way code compiled by facts dispatches: … `@cfunction` pointers"; F-3 (`:568`) records that `@cfunction` callbacks run the default owner's code as a deviation; `reference/compiler.md:340` calls the same thing Open.
- **Fix:** in §3.1 replace the rule by "Today the callee's code is the default owner's (§2.5, Open; [facts F-3])", so the rule section does not contradict the Open item two sections later.

### M7. Open items that do not link the open-issues entry, and a stale "no entry yet"

- `reference/compiler.md:347`: "no entry in `../open-issues.md` yet" — there is one: `open-issues.md:33` ("Facts code behind `jl_apply`"). The convention (`reference/README.md:26`) wants the Open status to link the question.
- `reference/facts.md:231` (Open, links compiler.md and F-3), `:449` (Open, "F-7" only), `:497` (Open, "F-8" only): the entries exist at `open-issues.md:33`–`35`.
- **Fix:** link `../open-issues.md#2-design` from each, and delete the "no entry yet" clause.

### M8. "Fact signature" is defined with four forms in the glossary and the argument, five in the references

- `glossary.md:338` and `design/argument.md:28` list: concrete tuple, union splits, unions inside tuple arguments, a closure's call at kinds. `reference/facts.md:176`–`182` and `reference/compiler.md:96`–`100` add the concrete `Vararg` tail; `intro/porting.md:158`, `:176` say it was "decided since".
- **Fix:** add the fifth form to both, or make the glossary and argument.md defer to facts §3 instead of restating.

### M9. The acceptance suite is 22 checks in some places and 23 in others

- 23: `state.md:30`, `design.md:99`, `design/julia-changes.md:73`, `:81`, `reference/facts.md:122` ("G1.1–G1.23").
- 22: `state.md:101` ("acceptance 22/22"), `design/evidence.md:17`, `:121`.
- state.md contradicts itself within one page.
- **Fix:** 23 everywhere (G1.22 and G1.23 were added with the call-site cache, `julia-changes.md:78`–`79`), or say "22 before the cache, 23 after".

### M10. The typed and untyped call costs are given as different numbers for the same quantity

- Typed: `state.md:17` "0.8 ns | 0.8 ns" (per call, after cross-owner inlining, `design/julia-changes.md:28`); `design.md:103`, `design/evidence.md:42`, `intro/results.md:64`, `design/performance.md:15` "36–38 ns against 33.8–34.5 ns" (a loop of 16; before the change). Neither says which build.
- Untyped: `state.md:18` "about 29 ns" (through the table, TraitWorld 68ecef5); `intro/traits-for-julia.md:349`, `intro/results.md:65` "about 120 ns"; `design/evidence.md:43` "115–129 ns"; `design/performance.md:96` "116 ns" (before the table).
- These documents are not normative, and `state.md:89` says numbers change after the measurement round, but today a reader meets 0.8 ns and 36 ns for "a typed call" one page apart.
- **Fix:** one table in evidence.md with the build for each row; the other pages cite it and say "per call" or "per loop of 16", and "before/after the untyped table".

### M11. The glossary's "Defined in" lines carry section numbers of the retired page

- Lines with "§n" that were `implementation.md`'s sections, now mapped onto reference anchors they do not match: `glossary.md:81` ("§4.1" → traits §5), `:95` ("§5 rule 3" → facts.md; rule 3 is in traits.md per `design.md:76`), `:114` ("§4.1", "§4.4"), `:175` ("§16" → lowering §6), `:183`, `:193` ("§4.2"), `:201` ("§16"), `:209` ("traits §6.5, 'How the prototype does it'": no such heading), `:215` ("§6 … part (B)" → compiler.md), `:233` ("§4.3"), `:260` ("§6 part (D)"), `:310`, `:316`, `:341` ("§5 rule 1/2"), `:364` and `:391` ("`mechanisms.md` §19" → facts.md#g1), `:137` (Family → "traits §3.2", which is Defaults), `:101` ("traits §5; traits §5, §7").
- Several also begin with "[glossary](glossary.md)", a link to the page itself (`:81`, `:114`, `:175`, `:183`, `:193`, `:209`, `:215`, `:300`, `:310`, `:316`, `:328`, `:341`, `:347`, `:358`, `:373`, `:378`, `:384`).
- **Fix:** rewrite each "Defined in" as "[traits §n](…)", "[facts §n](…)", "[lowering §n](…)" with the reference's own numbering, and drop the self-links.

### M12. The glossary says the world-checked call-site cache is "not built"; the compiler reference says two are built

- `glossary.md:262`–`269`: "(proposed) … Not built." and, in the same entry, "It is built for `DynamicCall`'s pointers".
- `reference/compiler.md:450` (§3.1, `:caller_world` thunk: a world-checked call-site cache, Implemented), `:481` (§3.2, Implemented). What is not built is a cache for `Dynamic` beyond four (H4).
- **Fix:** rename the entry "World-checked call-site cache" without "(proposed)"; say it is built for `DynamicCall` pointers and for every dynamic call site (compiler §3), and that its use for `Dynamic` beyond four is Optional.

### M13. Prose pointers to sections of the retired pages

- `open-issues.md` names `design/implementation.md` or `design/mechanisms.md` sections 25 times (lines 3, 15, 17, 24, 25, 30, 77, 78, 83, 84, 86, 87, 98, 105, 111, 139, 153, 219, 220, 221, 227, 248, 272, 283). The headings still exist as pointers, so a reader lands on a one-line redirect.
- `design/julia-changes.md:24` ("`implementation.md` §6"), `:29` ("§4.6"), `:65` ("§3.3"); `design/alternatives.md:77`; `design/comparison.md:182`, `:238`, `:262`, `:317`, `:318` ("`mechanisms.md` §n").
- **Fix:** replace each with the reference section (the pointer pages give the mapping); in open-issues.md, at least items still open (§1.16, §1.19, §1.20, §2 "Keys and fields", §2.27, §2.28, §3).

### M14. The lowering reference narrows "no receiver type"

- `reference/traits.md:318`: "An implementation whose operations are all served by defaults has no receiver type."
- `reference/lowering.md:233`: no receiver type only when, in addition, "the declarations do not name `Self`, and fields define every parameter" (`record/decisions.md:20` confirms the extra conditions are the prototype's).
- A type whose operations are all defaults but whose trait names `Self` therefore has a receiver type (itself) and its own compiled copy, which traits §4 denies.
- **Fix:** either traits §4 states the two conditions (they are observable: which types share code), or lowering records an L- row.

### M15. Compiling ahead: "every bounded function" (traits) against "whose only trait position is that one" (lowering)

- `reference/traits.md:865`: "every bounded function whose bound includes `X`, at `T`'s key, where the other arguments are concrete".
- `reference/lowering.md:573`: "the workers whose only trait position is that one"; L-15 records only that vararg positions are skipped. A function with two trait positions (`meandiff(a::ColTable, b::ColTable)`) is compiled ahead by traits §15's wording and not by lowering §15.1's.
- **Fix:** say in traits §15 whether functions with several trait positions are covered (and at which key for the other positions); if not, add it to L-15.

### M16. Planned forms accepted today with another meaning, without a T- row

- `reference/README.md:36`: a Planned item is a deviation where the implementation "accepts it with another meaning".
- `Callable{A, S, M, K}` (`reference/traits.md:664`, Planned): `intro/traits-by-example.md:813` says "Today neither is a `Callable` bound", that is, the argument is silently plain (as T-17/T-18 record for the other two forms). No row.
- `x isa X`, `T <: X` (`reference/traits.md:890`, Planned): accepted and `false`. The status line says so; by the convention it is a row.
- `Dynamic{(X, Y)}` (`:756`): what happens today is not stated anywhere.
- **Fix:** add rows (T-23 …) for the first two; state the third's behaviour or add a row.

---

## Low

### L1. Terms with more than one meaning

- **mode:** facts/plain (`reference/facts.md:77`), a `Callable`'s `DynamicCall`/`CompiledCall` (`reference/traits.md:682`), concrete mode (`:834`), strict mode (`:810`). `reference/compiler.md:543` already warns about one clash. Suggest "inference mode" for the first wherever it stands alone, and a glossary entry "Mode".
- **entry:** a bounded function's entry (`reference/traits.md:573`) against cache entries (`reference/compiler.md:461`–`476`, `:485`–`499`; `reference/lowering.md:383` `UEntry`). Suggest "cache entry" / "table entry" in compiler.md and lowering.md.
- **owner:** a package (`reference/facts.md:59`) against a cache owner, used bare in `:271` ("The owner that reaches it is the facts owner") and compiler.md's tables. Suggest "cache owner" wherever a symbol is meant.
- **boundary:** rule 3 (`design.md:80`, values crossing) against the boundary method (M3). Related but not the same; the glossary has neither.

### L2. History labels inside the references

- Piece numbers from `explorations/julia-support.md`, undefined in the references: `reference/compiler.md:387`, `:397`, `:411`, `:450`, `:564`, `:589`, `:612`, `:715`, `:721`; `reference/lowering.md:74`, `:634`, `:640`, `:678`.
- Commits in body text: `reference/lowering.md:372` ("julia-changes c7f1eae1c0"), `:469` ("commit dc67242"); a fixed bug in a deviation row, `reference/compiler.md:731` ("fixed in f13117cd74").
- Dated documents: `reference/compiler.md:161` (a plan), `:347` ("the review of 2026-10-19").
- "assumption A3", a label from the old notes: `reference/facts.md:113`, `:501`, `:516`; `glossary.md:362`.
- **Fix:** name the thing, not the piece ("the definition hooks"); define A3 in facts §2.1 or drop the label; move commits to julia-changes.md.

### L3. Link texts that name anchors or files that do not exist (the links themselves resolve)

- `reference/lowering.md:61` (`compiler.md#facts-methods-and-boundaries`, `facts.md#facts-and-run-time-sites`), `:72` (`facts.md#what-a-package-image-keeps`, `compiler.md#package-images`), `:274`, `:380`, `:385`, `:466`, `:468`, `:500`, `:618`, `:620`, `:634`, `:640`, `:372` (`compiler.md#inlining-across-owners`).
- `reference/facts.md:231`: "[Changes to Julia, mechanism 2](compiler.md#…)" — "Changes to Julia" is julia-changes.md's title.
- `state.md:128`, `:132`, `:148`: link texts say `../open-issues.md`, `../plans/…`, `../record/…` for files beside state.md.
- **Fix:** use the section's title as the text.

### L4. Section numbers of the retired page used as names

- `design.md:19` "[rule 1](reference/facts.md)", `:76` "rules 1 and 2": facts.md numbers no rules. `design/argument.md:28` "(section 5, rule 1)", `:74` "section 4.3", `:76` "section 6", `:78` "section 8", `:105` "section 4.8". `state.md:100` "(4.9)", "(4.8)".
- **Fix:** "facts §3" and so on.

### L5. Small slips in `intro/traits-for-julia.md`

- `:285` "[the argument §3](…) §3" and `:293` "[the argument §3.2](…) §3.2": doubled.
- `:15` "four demonstrators" lists five things; `state.md:13` names five packages; `design.md:3` says four. Say which count is meant (TraitTables and TraitCSV inside TraitReport).
- `:360`–`363` lists "a bounded function cannot name the trait's type parameters with `where`" under "until traits are in the type system"; `reference/traits.md:566` (T-16) treats it as Planned on its own, not tied to §16.

### L6. The standard-libraries question is flagged Open in two references and not in the third

- `reference/traits.md:794` and the status index `:954` state "Julia (Core, Base, the standard libraries) is one owner" as Implemented; `reference/facts.md:145`, `:517` and `reference/compiler.md:178` mark it Open (`open-issues.md:24`).
- **Fix:** add "Open: whether the standard libraries are owners of their own (open issues §1.19)" to traits §12.1.

### L7. F-1 and C-1 record one deviation with small differences

- Line numbers: `reference/facts.md:566` cites `typeinfer.jl:1653` and `:1657`; `reference/compiler.md:731`–`732` cite `:1654` and `:1658`.
- F-1's last sentence ("a queue that does not compiles the compiler by facts under `all`") reads as a live bug; C-1 says the queue bug is fixed.
- **Fix:** keep the detail in C-1 and let F-1 say "as compiler C-1" with the same lines.

### L8. Equality of `Dynamic` values is stated in as-built terms

- `reference/traits.md:748`: "equal when they hold the same trait object". The intended representation holds the user's object (`:731`; lowering L-8).
- **Fix:** "when they hold the same user's object (`===`)".

### L9. "A trait module's methods … whoever calls them" overstates by the entries

- `reference/traits.md:136` says every method of a trait module is compiled by facts whoever calls it; `reference/facts.md:258` and `reference/lowering.md:67` make entries (and `conformance` methods) boundaries compiled in the caller's mode.
- **Fix:** "a trait module's workers and internal functions".

### L10. Stale state lines in `open-issues.md`

- `:105` "TraitWorld 375a930, 47 test sets" against the references at 227781a and 48 sets (`state.md:101`, `design/julia-changes.md:82`).

### L11. Glossary details

- `:126` gives `via(Fast, m)` and then `Via{Fast}(x)`; `reference/traits.md:897` has only the second.
- `:118` states "a more specific implementation … must declare the same parameter values" as a fact; it is Planned (T-9).
- `:274` "(about 4 ns, measured on the earlier prototype)": a measurement in a term's definition.

### L12. Two or three settings

- `reference/facts.md:30` lists three ("product", "`all`", "a trimmed build"); `:95`, `:418` say "both settings"; `:85` defines a setting as "which code the default owner compiles by facts", under which `--trim` is a third.
- **Fix:** "two settings and `--trim`".

### L13. The record's index still calls implementation.md current with design.md the source of truth

- `record/INDEX.md:157`, `:163`–`166`. History, but agents start there.

### L14. The Planned command-line flag is in facts.md and state.md, not in compiler.md

- `reference/facts.md:491` and `state.md:113` give `--compile-by-facts=no|all|traits` as the Planned spelling; `reference/compiler.md:74`–`80` (the process switch) does not mention it. By `reference/README.md:50` a compiler switch belongs to compiler.md.

### L15. A retired term in a reference

- `reference/lowering.md:559`: "in the implementing type's module" (now "receiver type", `glossary.md:402`).

### L16. One open question in traits.md is written as advice to work around it

- `reference/traits.md:564` ("Until `where` variables in bounds are built, get an associated type … from an operation that returns it in a container"), `:463` ("Until it is built, write one declaration per member"), `:755` ("define `Base.convert(…)` for your trait"). The convention (`reference/README.md:28`) writes Planned items as intended; the workarounds belong in the tutorial (`intro/traits-by-example.md:486`, `:804` already have them) or in the status line only.

---

## What was verified against code

- TraitWorld HEAD is 227781a, the commit both `traits.md:971` and `lowering.md:8` cite.
- The one-line form never picks a field (`TraitWorld/src/implement.jl:1147`–`1216`): H1's glossary sentence is false against the code as well as the decision.
- F-4 matches `TraitWorld/src/strict.jl:87`–`92` and `trait_module.jl:38`–`46`: strict mode protects owner `:facts`, and owner `nothing` only for Base, Core, the standard libraries, TraitWorld and trait modules.
- T-19 / L-10 match `TraitWorld/src/defcheck.jl:84`–`96`: keyword, vararg and `Callable` workers are checked per signature.
- Every relative link and anchor in the eighteen documents resolves.

Everything else above is reasoning from the texts.

## What was not checked

- Whether every "Where" line number in the four Deviations tables points at the named function (four were spot-checked, all correct).
- The numbers in `design/evidence.md` against the raw results.
- `design/comparison.md`, `design/alternatives.md`, `design/evidence.md`, `design/performance.md` and `intro/results.md` beyond the grep for retired-page pointers and the numbers in M10.
