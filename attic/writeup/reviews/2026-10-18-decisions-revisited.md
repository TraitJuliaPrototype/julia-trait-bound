# Review: every recorded decision, revisited for conceptual simplicity

2026-10-18 (session 29). Independent review of `writeup/decisions.md` (design repository a32778c), row by row, against what the project knows today: the three reviews of 2026-10-18, the session-29 decisions, the plan `plans/2026-10-17-policy-in-compiler-plan.md`, the lessons, `experiments/factscompiler/README.md`, the four notes and the explorations the rows point at. Code read: `TraitWorld/src/{entry,core,strict,hooks,implement,trait_module,facts}.jl` at 47e4274, `experiments/factscompiler/Compiler/src/facts.jl`, `julia-1.13/Compiler/src/facts.jl` (uncommitted), the demonstrators' and forks' sources.

**Marks.** *Verified* means a source quote (`file:line`), a `git`/`grep` result or an experiment run today. *Reasoning* means my judgement. One experiment ran on the patched build (`/tmp/claude-1000/review-decisions/redef.jl`, appendix). No repository file was changed.

**The question.** The user: "look at every recorded decision and see if they recommend to change any of them given what we know now, and in the name of conceptual simplicity." The six session-29 decisions are taken as given; the review says where one of them makes another row obsolete, simpler or contradictory.

---

## 1. Scope and summary verdict

The register has 87 rows (lines 15–139). My count by main verdict (each row has one; "status wrong" is also flagged beside another verdict on six more rows):

| verdict | rows |
|---|---|
| keep | 51 |
| simplify | 5 (rows 35, 50, 54, 108, 118) |
| change | 2 (rows 56, 94) |
| retire (move to history) | 16 |
| merge | 9 rows into 6 decisions (strict mode; `Callable`; the trait-name sugar; AD tags; overrides; non-public facts) |
| status wrong | 4 as the main verdict (rows 90, 91, 93, 99); flagged on 19, 20, 63, 69, 71, 100 |

**Summary.** The core is right and small: a trait is an abstract type with a declared, checked contract; conformance is declared; code is compiled for what the bound can see (keys); compiled code depends on the method table only through facts at concrete signatures; ownership names who can change a fact; a pirate that would win is refused (strict) or followed (default); a trait object is the user's object seen through offsets. None of these should change. What has grown around them is of three kinds, and the six decisions of today let most of it go:

1. **Mechanisms that existed because the policy was a foreign cache owner in a package on stock Julia:** view caches, the frozen compiler world (`_latest_under_policy`, 29 call sites), the system-image prototype (`experiments/sysimage`, still present), trampolines and site caches, the generator path, pieces 2 and 4 of the patch (still in tree), the stock-only fallbacks, 13 `JULIA_TW_*` switches. Decisions 2, 3 and 4 make all of them deletable. Sixteen register rows, and parts of four more, describe them or their predecessors and belong in history.
2. **Concepts with a second spelling or an unused half:** `Callable{A, S, M}` with two modes plus `DynamicFn` (no demonstrator or fork uses a `Callable` bound or the compiled mode; TraitDifferentialEquations uses `DynamicFn` only); four spellings of concrete mode; `conforms(T, X)` (used by nothing outside TraitWorld); the `dynamic by` conformance form (used by nothing, tests included); `Like{t}` with the inverse (only `Self` constructors are exercised, in TraitCSV); named implementations (unbuilt, and in tension with the simplest `Dynamic`). Each is sound; each is a concept the reader must carry.
3. **Rule 4 and the word "view".** Rule 4's two halves are Julia's own behaviour (a call sees the current world; compiled code lives in the image that compiled it, kept native by piece 5). Under (B) in Julia there is nothing left for a rule to say. The four rules can be three.

**Decisions that jointly imply something the register does not record** (details in §4):
- decision 2 (`all` is a test bed; the user setting needs (B)+(C)) gives strict mode its object back (protected code = facts-owned code), which the design review's finding 3 had lost under one owner; and it makes the plan's go/no-go threshold (P-a) moot, since Base is never compiled by facts in the product setting;
- decision 4 (`Dynamic` in the compiler) with "no sealing" (row 127) forces the machinery exemption (`sealed_call`) out, which open-issues 1.11 lists as a question rather than a consequence;
- rule 3 (owners of a parameter's type are stakeholders) with decision 4 of session 27 (overrides refused) *forces* "a family member's conformance is fixed at its first use" (row 35): a downstream package that owns `T` may legitimately define `op(::S{T})`, so the family's decision cannot be fixed at its declaration. The register states the rule without the reason;
- decision 1 of session 29 (strict first) and decision 3 of session 25 (AOT compiles the plain call) imply that `--trim` switches the facts mode off; under (B) a flagged method would otherwise be compiled by facts in the build too;
- rows 56 (named implementations: "the choice travels with the value") and the implementation review's `Dynamic{X}` holding the user's object cannot both hold: a witness must travel in the value. One of them yields.

**Contradictions inside the register:** row 63 ("AD tags … not yet in TraitDifferentialEquations") against row 114 ("implemented (s27), yes (8c25ae3)"); row 69's strict-mode clause ("outside pirates raise where they would win") against row 72 (that mode "not pursued"); row 99 ("an experiment to run later", prototype "yes since s28") against the plan's part (C); row 100 ("not yet") against rows 106–108 (TraitTables and TraitCSV exist). *Verified*, §3.

---

## 2. The ten most valuable changes, ranked by gain in simplicity per cost

### 1. Three rules, not four (and the guarantee first)

**What it removes.** Rule 4 (`4-details.md:106–112`) as a rule, and the words "view" and "owners' view" from the register (rows 19, 20). Its first half, "a call sees the current world", is assumption A2 of `wrapping-by-facts.md:44`, Julia's own behaviour, not a rule of the design. Its second half, "where compiled code lives", lists where Julia puts compiled code anyway (the image of the package that compiled it, kept native by piece 5); with (B) in Julia (decision 2) a facts-compiled CodeInstance is placed exactly as a plain one. Also removed: "a trait module may not define a pirate" as a separate clause of rule 3. Under strict mode first (decision 1), it is the same refusal applied to everyone; for a pirate that wins nowhere it is a lint, and the lint can stay in `@trait_module` without being a rule.

**What stays.** Rule R (facts), rule O (ownership: stakeholders; a winning pirate refused in strict mode, followed by default), rule B (the boundary: only values cross; a bound translates once; compiled per key). The guarantee ("compiled code is never invalidated unless code it depends on changes") stated before them, with its two tiers, as the framing review's §5.1–5.2 drafts.

**What it costs.** A rewrite of `4-details.md` "The four rules", `1-overview.md` and `3-wrapping.md`; nothing in code. The notes must be rewritten anyway (framing review §5.7).

**Evidence.** *Verified:* rule 4's text; `viewcache.jl` 348 lines, which the implementation review classifies as a workaround to delete; `_latest_under_policy` at 29 sites, gone with (B) (`grep`, implementation review §2.1). *Reasoning:* no proof in `wrapping-by-facts.md` uses rule 4; Theorems 1–3 use R, P, Lemma O and Lemma D only.

### 2. One `Callable`, one mode; `DynamicFn` is not a second concept

**What it removes.** The mode parameter `M` of `Callable{A, S, M}`, the types `CompiledCall` and `DynamicCall`, the wrappers `compiled_call(f)` and `dynamic_call(f)`, the sentence "the library sets a default, the caller overrides", the owner-dependent clause "functions from the trait world are always compiled calls" (`4-details.md:496–502`), and `DynamicFn` as a name of its own (row 60). What is left: `Callable{A, S}`, a function from above called through a pointer at its declared signature, checked at every call; stored or passed, the same type. A function the library wants to specialize on takes an *unbounded* argument, which `4-details.md:150` already allows ("takes the value at its own type, and the worker is compiled for that type").

**What it costs.** A user-accepted decision (rev 988, row 54) changes: a caller can no longer force specialization on a bounded position per value. The memory note "CompiledCall/DynamicCall over erased/specialized; never promise inlining" is naming feedback, not a requirement for two modes; the simplification promises less, not more.

**Evidence.** *Verified:* no demonstrator or fork uses a `Callable{` bound, `compiled_call`, `CompiledCall` or `dynamic_call` (`grep` over `TraitDifferentialEquations/src`, `TraitMakie/src`, `TraitTables/src`, `TraitCSV/src`, `TraitReport/src`, `forks/*/src`: none). TraitDifferentialEquations uses `dynamic_fn` and `DynamicFn{RHSSig{P,T}, Nothing}` (`ODECore.jl:73, 101–102, 129–130`; `TraitDifferentialEquations.jl:39, 59, 76, 110`). `DynamicFn{A,S}` is defined as `CObj{A,S,Erased{A,S}}` (`TraitWorld/src/entry.jl:605`): the dynamic-mode `Callable` under another name. The design's own rationale for dynamic by default (`2-design-choices.md:312`: "compiling per closure costs much and rarely pays") argues for one mode.

### 3. Strict mode is one decision with two tiers; its work items are the thesis

**What it removes.** Three rows (70, 71, 134) saying three things about one mode ("adopted as an option", "intended design, deferred", "first for the framing"), and row 69's wrong description of it. One row: *strict mode is the stated guarantee; the default session relaxes it (rule P); the gap between the stated guarantee and the prototype is the work list* (framing review §5.4: pieces 1′, 14, 15; `twolibs`; the extension rule; bindings; the session as owner; strict under `all`).

**What it also settles.** Decision 2 restores strict mode's object: with (B), protected code is "owned by the facts owner" again, which is what `strict.jl:52–57` implements (`ci.owner isa FactsOwner`, or a trait module's native method). The design review's finding 3 ("undefined under one owner") was a finding about the `all` setting, which is now a test bed. Record that.

**What it costs.** Register and notes. Pieces 1′, 14 and 15 join the Julia list (row 94 must change, change 9).

**Evidence.** *Verified:* `decisions.md:69` ("a strict mode (outside pirates raise where they would win) is optional") describes the `HiddenMethodError` mode that `decisions.md:72` and `strict-mode.md` §5 reject; `strict.jl:52–57`; framing review §5.3 (a), verified there: strict mode changes nothing at run time.

### 4. Retire the foreign-owner era to history, and delete what is still in the tree

**What it removes.** Sixteen rows, and parts of four more, that describe mechanisms of designs the project has left (layering, wrappers, sealing, the filter, the held layout, the external interpreter in a package, the system image, the trampolines, witness tables): rows 17, 41, 62, 72, 75, 77, 83, 84, 95, 97, 98, 109, 115, 117, 128 and 20 (as a rule); and the clauses 53's "built anyway", 90's stock half, 91's filter half, 35's "at checkpoints on stock". And the artefacts that still exist: `experiments/sysimage` (present: `build.jl`, `build.sh`, `README.md`), `viewcache.jl` (348 lines), the frozen compiler world (29 sites), patch pieces 2 and 4 (commits 4d8eeebc19…fac46840b8 and 87dcf22015, still on `trait-world-1.13`), the three worktrees at the repository root, the `{R}` spelling (10 traits in `test/runtests.jl`, `_PC`'s `project(t) = t.v` at `TraitWorld.jl:111, 114`), 10 of the 13 `JULIA_TW_*` switches, the `projection` names (56 occurrences in `implement.jl`).

**What it costs.** Deletion work in TraitWorld and the patch, and a "History" section in the register (or `attic/`). No design cost: every item is replaced by (A)+(B)+(C)+(D) or by nothing.

**Evidence.** *Verified* by `git log`, `ls` and `grep` (appendix). The implementation review's §4.3 lists the same set independently.

### 5. `Dynamic{X}` holds the user's object; its operations are a call-site split

**What it removes.** Row 108 ("`Dynamic{X}` keeps only the views of `X` and its supertraits"): with no views in the value there is nothing to keep; the view for (trait, user type) is a constant, rebuilt at the branch or in the fallback. Rows 53 ("built anyway as witness tables") and 128 go to history; the world-age defect (design review finding 2) and the order-dependent branch set (finding 4) disappear with the package mechanisms. The `_narrow`, `TObj` boxing and the `_LOCK`-protected registries on the `Dynamic` path go too.

**What it records.** `Dynamic{X}` is then the package's spelling of "a value of abstract type `X`": a box whose element conforms to `X`. Once membership is subtyping (piece 7), `Vector{Plot}` holds exactly that without a wrapper. The register should say `Dynamic{X}` is transitional in form, permanent in meaning (the dynamic position, as `2-design-choices.md` §8 chose it). That sentence also decides change 6.

**What it costs.** Decision 4 already commits to (D); this only fixes what the value is. The explicit spelling respects "no hidden type parameters".

**Evidence.** *Verified:* `core.jl:387–395` (a `Dynamic` holds a boxed `TObj` and a `_Witness`; implementation review §3 P3); design review A1 (world age). *Reasoning:* implementation review §4.2.

### 6. Named implementations (`via(M, x)`): defer until traits are in the type system, and name the conflict

**What it removes.** From the core: a witness dimension in every key ("workers are compiled per key and witness", `4-details.md:370`), in `Dynamic` equality and printing (`:379`), and in the entry ("stripping `via`"). Nothing is built (row 56: prototype "no"); no demonstrator needs it; the newtype is the plain-Julia escape the design already lists (`2-design-choices.md:386`).

**The conflict.** "The choice travels with the value" needs the witness *in* the value. Change 5's `Dynamic` (the user's object) and piece 7's membership-as-subtyping (a conforming value is a plain object) have no place for it. Either `Dynamic` keeps a witness forever, or named implementations are a value-level wrapper (`Via{Fast}(x)`, a newtype that conforms), which is what plain Julia offers today. The second is one concept fewer.

**What it costs.** The user's "Liberal it is" stands as the answer to *who may implement*; only the mechanism is deferred, and the register should say which of the two forms it will take.

### 7. Concrete mode: one declaration with a level

**What it removes.** Four spellings of one knob: `@concrete_only`, `@warn_on_abstract` (per trait), `@error_on_abstract`, `@warn_on_abstract` (per module), and `check_concrete` in tests (`grep`: `trait.jl`, `implement.jl:83–101`, `concrete.jl:552–563`, `4-details.md:255–261, 723, 753`). One declaration, `@concrete silent|warn|error`, at a trait or a module, is the same decision with one name. The design review's finding 8 (per-parameter grain, `IntegratorView{T, P}`) becomes an argument of the same declaration later, instead of a fifth macro.

**What it costs.** A rename; decision 1 of session 27 is unchanged in substance.

### 8. Overrides refused: keep the rule, lose the restart

**What stays.** "An override belongs to the conformance" (rows 35, 119) is right: the key would change and kept values hold the old one (`4-details.md:204`).

**What changes.** The sentence "this is why Julia long refused to redefine a struct" (`:204`) now cuts the other way. *Verified today* on the patched 1.13.2 (`redef.jl`): `struct A; x::Int; end` redefined at top level as `struct A; x::Int; y::Int; end` is accepted; the old value keeps the old type, which prints as `@world(A, 39302:39308)`; the method on the old type still applies to the old value (`f(a1) = 2`), the new method to the new (`f(a2) = 3`); `invoke_in_world(w0, f, a1)` answers in the old world. A conformance redeclaration can use the same mechanism: a new conformance in a new world, with kept `Dynamic` values and compiled workers holding the old one. The register's "restart for interactive changes" then reads "until redeclaration is built (Julia's binding partitions)", and the row's "at checkpoints on stock" clause goes (decision 3). Also fix `hooks.jl:151` ("or in its block" is not available after the fact; design review finding 8).

**What it costs.** Later implementation; no change to the decision.

### 9. The Julia work list follows the pivot; P-a is moot

**What changes.** Row 94 ("first upstream proposal: first-class foreign cache owners, pieces 5, 9–13") contradicts plan §5 (reverts 2, 4, the foreign half of 5, 9, 10; drops 11–13) and decision 2 (which brings (B)+(C), and with them 5, 9, 10 "in the form the runtime needs for a second owner", plan §5 last line). The list that follows from decisions 1–4: (A) facts as a mode; (B) a per-method facts flag and owner; (C) owner-aware dynamic dispatch; (D) the `Dynamic` call-site split; pieces 1, 1′, 14, 15 for the guarantee; 3 and 17 independent; 11 moot (its two obstacles are artefacts of the generator, `julia-support.md:177–183`); 2 and 4 reverted. The first upstream proposal is "a facts mode for the native compiler, with per-method inference modes", not foreign owners.

**What is moot.** Plan §3's decision rule (≤ 5 % geomean, no group above 20 %; row 139, open-issues 1.9) gated (B) on the cost of `all` for Base. Decision 2 makes `all` a test bed, so Base is never compiled by facts in the product setting, and (B) is forced regardless of the number. Decision 6 ("slowdowns tolerated if a trait redesign recovers them") then governs only what trait code and the plain code it reaches pay (the `describe` and `SkipMissing` tails of the lessons, raytrace as a trait), not BaseBenchmarks. Record this; open-issue 1.9 closes.

**What it costs.** Register rows 94, 125, 139; plan §8; root `README.md` item 6.

### 10. Rule 1 says what a fact signature is, and drops the pointer knob

**What changes.** Rule 1 (`4-details.md:81–86`) gets one definition of a *fact signature*: a dispatch tuple of concrete types; its union splits; the splits of unions of concrete element types inside tuple arguments (lesson 1.8, `_fact_splits`, up to 4); a closure's call at kinds (rule 5 of `wrapping-by-facts.md`). It states the one fold exception: folding where Julia's own asserted effects fold (lesson 1.2), justified as "inherited from Base's assertion, the same exposure as plain Julia", not by strict mode (design review finding 5). And it drops the sentence "a callee is compiled under the policy, or called through a pointer into plain Julia's code, a choice of speed only" (`4-details.md:86`; row 69; `3-wrapping.md:103–111`): under (C) every callee reached from facts code runs facts code, and the pointer form survives only as `Callable`. Lesson 1.1 ("run-time sites run the policy's code") is then not a rule change but the definition of (C).

**What it costs.** Notes; the acceptance suite gains a case for a Base-asserted fold and a tuple split under redefinition (design review finding 5).

---

## 3. Every row of the register

Rows are named by their line in `writeup/decisions.md` (a32778c) and a short title. "History" means the row moves to a history section or `attic/`.

### The core (lines 15–22)

| line | row | verdict | reason |
|---|---|---|---|
| 15 | A trait is an abstract type with behaviour; concreteness opt-in | **keep** | the one idea everything else serves; opt-in (s27) is right since nothing in the facts proofs needs concreteness |
| 16 | Conformance is declared | **keep** | the C++0x lesson; Base's throwing fallbacks make structural matching unsound |
| 17 | Layering | **retire** → history | superseded in s23; rows 69 and 83 already say so |
| 18 | The boundary translates once per bound (rule 2) | **keep**; simplify wording with change 2 | "a function from above enters only as a `Callable`" stays, with one mode |
| 19 | Ownership (rule 3) | **keep**; **status wrong** | "delegation by the owner only" is stale: delegates are data for strict mode (row 74), extensions count as parent; the wording should match `4-details.md:38` (the method's own signature), not `:99` |
| 20 | Views and placement (rule 4) | **retire** as a rule; **status wrong** | both halves are Julia's own behaviour (change 1); "views" are gone; prototype "yes (view caches)" names a mechanism to delete |
| 21 | Identical or error | **keep** | A4 and A5 are implementation assumptions that (B) removes; A3 narrows again with `all` a test bed; say so |
| 22 | Types first, then traits | **keep** | needed for adoption one function at a time; mark "needs the language" (the entry at `Any` and `_plain_method`, `entry.jl:477–513`, imitate it) |

### Keys (lines 28–42)

| line | row | verdict | reason |
|---|---|---|---|
| 28 | Keys replace representations | **keep** | the central design result; measured |
| 29 | The implementing type | **keep** | the definition that makes "no implementing type under defaults" and the override rule coherent |
| 30 | Implementation separate from conformance | **keep** | lets a bare `Vector{Vector{Float64}}` implement without conforming |
| 31 | Forwarding `by f` replaces projections | **keep** | nothing copied, nothing stale |
| 32 | Computed and copying projections removed | **keep** (a rejection) | the honest answer is explicit conversion |
| 33 | Declared fields are stored fields | **keep** | computed properties would reintroduce projections |
| 34 | The reference layout | **keep**; **merge** its "keeping" clause into row 61 | one mechanism, two rows |
| 35 | Overrides belong to the conformance; family members fixed at first use; refusal at load; restart | **keep**; **simplify** (change 8); **merge** with 119 | restart → redeclaration by binding partitions (verified); "at checkpoints on stock" goes with decision 3; record *why* first use: rule 3 makes the owner of a member's parameter a stakeholder, so the family's decision cannot be fixed at its declaration (§4) |
| 36 | Fields define parameters by matching | **keep** | first-order, decidable |
| 37 | Membership through a generic implementation only without declared fields | **keep** | fields need mapping, so a declaration |
| 38 | Forwarding carries through generic implementations | **keep** | untested since s22; a test or "design only" in the column |
| 39 | Forwarding does not chain | **keep** | one level is simpler and the user converts explicitly beyond it |
| 40 | A subtrait's conformance agrees with its supertrait's | **keep** | unbuilt; `implement.jl:467` checks implementation, not agreement of mappings |
| 41 | Held/lens split, exit check, re-entering `Dynamic` | **retire** → history | withdrawn in s22 |
| 42 | Internal functions take trait objects without bounds | **keep** | what makes definition checking cover a module |

### Parameters, checking, dynamic values (lines 48–63)

| line | row | verdict | reason |
|---|---|---|---|
| 48 | Associated types in first-order form | **keep** | keeps the design out of the Rust/Swift solver space (`2-design-choices.md` §10) |
| 49 | Definition checking at archetypes | **keep** | G4; cheap because operations declare results |
| 50 | `Dynamic{X}` | **keep**; **simplify** (change 5) | the value is the user's object; operations are a call-site split (D) |
| 51 | A trait's name in a field means its `Dynamic` | **keep**; **merge** with 107 | confined to trait modules until piece 7; the explicit spelling always works (the forks use it) |
| 52 | Hidden type parameters rejected | **keep** | the user's standing preference |
| 53 | Pointer tables rejected; built anyway as witness tables | **keep** the rejection; **retire** "built anyway" → history; **merge** with 128 | the rejection was vindicated by the world-age defect (design review A1) |
| 54 | `Callable{A, S, M}`, two modes, caller overrides | **simplify** (change 2) | one mode; no user of the other |
| 55 | Results like the input (`Self`, `Like{t}`, `withfields`, the inverse) | **keep** | sound (ConstructionBase precedent); note that only `Self` constructors are exercised (TraitCSV `emptylike`, `CSVCore.jl:20`); the inverse (`entry.jl:695–725`) is unexercised and unlisted for AOT |
| 56 | Named implementations `via(M, x)` | **change**: defer to piece 7, name the conflict (change 6) | unbuilt; conflicts with change 5; the newtype is the escape meanwhile |
| 57 | Selection by imported scope rejected | **keep** | an entry does not know its caller's module |
| 58 | Printing by bound and key | **keep** | piece 17 is independent and upstream-ready |
| 59 | `conforms(T, X)` stand-in | **keep** as the stand-in | used by nothing outside TraitWorld (`grep`); say so, or drop from the public surface |
| 60 | `DynamicFn{A, S}` by `dynamic_fn` | **merge** into 54 | `DynamicFn{A,S} = CObj{A,S,Erased{A,S}}` (`entry.jl:605`): the same type |
| 61 | Keeping is detected, not declared | **keep**; demote to an optimization | an analysis with a safe fallback (box), not a rule; merge row 34's clause here |
| 62 | AD by a library-owned dual type | **retire** → history | superseded s24 |
| 63 | AD tags by the primal signature | **status wrong**; **merge** with 114 | implemented: TDE 8c25ae3, `TraitDifferentialEquations.jl:83–110` (`Sig{A,S}`, `Tag{Sig{…}, Float64}`) |

### Code written without traits (lines 69–79, 83–84)

| line | row | verdict | reason |
|---|---|---|---|
| 69 | Wrapping by facts | **keep** (core); **status wrong** on two clauses; **simplify** (change 10) | the strict clause describes the rejected `HiddenMethodError` mode; "compiled into the trait world's cache or called through a pointer" is pre-(C) |
| 70 | Strict mode adopted as an option | **merge** with 71, 134 (change 3) | one decision, two tiers |
| 71 | Intended design, deferred | **status wrong** → planned; **merge** | decision 1 makes its items the thesis's work list |
| 72 | `HiddenMethodError` mode not pursued | **keep** (rejected) → history | the hostile review's reasons stand |
| 73 | The symmetric check as a lint | **keep** | the "before" order's answer; promote the sentence to the overview |
| 74 | Delegates as data | **keep**; record the tension | a curated list is ownership *claimed on the owner's behalf*, against row 19's "never claimed"; acceptable as a transitional social mechanism, and the register should say so |
| 75 | Skip predicate rejected | **keep** → history | rule P is the design |
| 76 | AOT builds compile the plain call | **keep**; record the implication | under (B), `--trim` must switch the facts flag off, or flagged methods compile by facts in the build (§4) |
| 77 | A closed build replaces the policy's call | **retire** with (B) | an artefact of the generator path (`_facts_call`); with an ordinary `:invoke` and the mode off there is nothing to replace |
| 78 | AOT annotations deferred | **keep** deferred | A and B are cheap once binaries are rebuilt |
| 79 | Pay-off 2 restated | **keep** | honest; still to be measured on three binaries |
| 83 | Trait wrappers, calls upward, sealing over views | **retire** → history | superseded s23 |
| 84 | Conversions in wrappers | **retire** → history | dissolved s23 |

### Runtime and workspace (lines 90–100)

| line | row | verdict | reason |
|---|---|---|---|
| 90 | Julia 1.13.2; stock and patched | **status wrong** | decision 3: patched only; the stock paths (`llvmcall` TBAA, `_invoke_under_policy`'s stock branch, view caches on stock) go |
| 91 | Registries `@max_methods 1`; protected by the filter | **status wrong**; **retire** the filter half | the filter is gone from TraitWorld (b60b126; no `JULIA_TW_FILTER` switch remains); the `@max_methods 1` pattern stays until piece 7 (22 registries, `core.jl`) |
| 92 | Workspace | **keep** | housekeeping: remove `TraitWorld-dynkeep/`, `-hooks/`, `-untyped/` from the root (branches stay) |
| 93 | The plan | **status wrong** | no TraitTables/TraitCSV/TraitReport, no forks, no pivot; "wrapping and sealing later" twice superseded |
| 94 | The Julia work, reviewed (s25) | **change** (change 9) | contradicts plan §5 and decision 2; pieces 1′, 14, 15 missing; 11 moot; the upstream story is the facts mode, not foreign owners |
| 95 | Filter, sealing, wrappers, declared calls, layering removed | **retire** → history | done (b60b126); the patch's pieces 2 and 4 still to revert |
| 96 | Runtime as methods | **keep** | the right package representation until piece 7 (33 vs 30 ns) |
| 97 | The policy in the platform (system image) | **retire** → history | superseded s28; `experiments/sysimage` still present: delete, keep the README |
| 98 | Facts at non-public functions | **retire** → history; **merge** with 117 | dropped s27; one row suffices |
| 99 | Run-time dispatch under the policy | **status wrong** | it is part (C) of the plan and in the prototype (1d93677); not "an experiment to run later" |
| 100 | TraitTables, TraitCSV, DataFrames redesigned around traits | **keep** the design; **status wrong** | "not yet" against rows 106–108 (both exist, s27); the forks are paused (s29), and the implementation review found them validating a barrier, not the trait (P7) |

### Session 27 (lines 106–119)

| line | row | verdict | reason |
|---|---|---|---|
| 106 | `CSVColumn{T} <: Column` | **keep** | the principled replacement of the InlineStrings extension; note the forks wrote `CSVSource` instead |
| 107 | A trait's name in containers inside functions | **merge** with 51 | one sugar rule, one row |
| 108 | `Dynamic{X}` keeps only `X`'s views | **simplify** → dissolves (change 5) | with the user's object in the value there are no views to keep |
| 109 | No bare `MethodInstance` invokes; trampolines; compile-after-inference | **retire** with (B)+(C) | the imitation of owner-aware dispatch (implementation review §2.1); the "on stock" clause is moot |
| 110 | Family builders in a registry of the declaring module | **keep** as implementation until piece 7 | the register should not list it as a design decision |
| 111 | Definition checking at the module's end; a warning at the prompt | **keep** | the warning is a stated deviation for interactive work |
| 112 | Stack traces hide the machinery's frames | **keep** (implementation) | a Julia registry of hidden frames later, as piece 17 |
| 113 | `MethodError` hint names the bound | **keep** | cheap, useful |
| 114 | Gradients through `solve` with the `Sig` tag | **keep**; **merge** with 63 | one decision, implemented |
| 115 | Julia piece 11 deferred | **retire** | moot under (B): both obstacles are the generator's (`julia-support.md:177–183`) |
| 116 | Stakeholders and Lemma O restated | **keep** | the soundness argument for G2; correct across the notes except `4-details.md:99` |
| 117 | Facts at non-public functions dropped | **merge** with 98 → history | — |
| 118 | Concreteness opt-in per trait, two macros | **keep**; **simplify** (change 7) | one declaration with a level |
| 119 | Overrides after a conformance refused | **merge** with 35 | the same decision recorded twice; the restart clause as in change 8 |

### Session 28 (lines 125–128)

| line | row | verdict | reason |
|---|---|---|---|
| 125 | The facts policy in Julia's compiler: (A), (B), (C); `all` measured before (B) | **keep**; amend | (B) is forced by decision 2, no longer gated by the measurement (change 9) |
| 126 | Facts fold where Base's effects fold; run-time sites run policy code; tuple-split facts | **keep**; write into rule 1 (change 10) | 1.2's justification corrected; 1.1 is (C)'s definition; 1.8 is part of "fact signature" |
| 127 | No sealing | **keep**; record the consequence | with (D) the machinery exemption (`sealed_call`, compiler copy `facts.jl:81–95`) must go; open-issues 1.11 lists it as a question |
| 128 | Witness tables and key branches | **retire** → history | superseded by decision 4; the world-age defect stands as the reason |

### Session 29 (lines 134–139)

| line | row | verdict | reason |
|---|---|---|---|
| 134 | Strict mode first for the framing | **keep**; **merge** with 70, 71 | — |
| 135 | `--compile-by-facts=all` is a test bed | **keep**; record what it implies | strict mode's object is restored (change 3); P-a is moot (change 9); A3 narrows |
| 136 | Stock-Julia support dropped | **keep**; apply | rows 35, 90, 109 and the stock fallbacks follow |
| 137 | `Dynamic` in the compiler directly | **keep**; apply | rows 53, 108, 128 and open-issues 2.26's first bullet follow (change 5) |
| 138 | The forks paused | **keep** | the control (upstream under `all`) is missing; the forks validated a barrier (P7) |
| 139 | Slowdowns tolerated if a trait redesign recovers them | **keep**; scope it | it governs trait code's tails, not BaseBenchmarks; P-a moot (change 9); open-issues 1.9 closes |

---

## 4. Decisions that jointly imply something not recorded, or that conflict

1. **Decision 2 → strict mode's object** (change 3). With (B), the protected set is "facts-owned CodeInstances" again; `strict.jl:52–57` already says so. The design review's finding 3 applied to `all`, now a test bed. The register should close that half of open-issues 1.11.
2. **Decision 2 → P-a moot** (change 9). The go/no-go threshold gated (B) on Base's cost; decision 2 forces (B). Decision 6 then scopes to trait code and what it reaches.
3. **Decision 4 + no sealing → the exemption goes.** `sealed_call` exempts TraitWorld's functions from the fact rule because `Dynamic`'s entry dispatches at `Any` inside the machinery (compiler copy `facts.jl:78–95`, README:88–91). With (D), the operation on a `Dynamic` is a call-site split in the caller, and the machinery is not on the path. Open-issues 2.26's first bullet is answered by decision 4, and the register should say so instead of leaving it to "settle".
4. **Rule 3 + overrides refused → family members fixed at first use** (row 35). A downstream package that owns `MyT` is a stakeholder of `op(::S{MyT})` (`4-details.md:36`: a type counts as a parameter), so it may define that method after the family conformance `@implement X S{T} where {T}` was declared upstream and before `S{MyT}` is ever used. Fixing the family's decision at its declaration would refuse a legitimate definition. The first-use rule is therefore forced, and sound (no worker or `Dynamic` exists for the member before its first use). The register gives the rule without this reason; 4-details:205 says only "as for a single type". *Reasoning*, from the notes' own definitions.
5. **Decision 1 (strict first) + AOT compiles the plain call → `--trim` switches facts off.** Today `_closed_build()` decides it in the generator (`aot-under-facts.md` §1, row 77). Under (B) the flag on a method would apply in the build unless `--trim` implies `--compile-by-facts=no`. Record it with row 76; it also removes row 77.
6. **Row 56 (named implementations) against change 5 (`Dynamic` is the user's object).** "The choice travels with the value" (`4-details.md:369`) needs a witness in the value; the simplest `Dynamic` and membership-as-subtyping have none. Decide which yields (§2, change 6). Not recorded anywhere.
7. **Row 74 (delegates as a curated list) against row 19 ("ownership is never claimed").** A list in TraitWorld naming StaticArrays a delegate of StaticArraysCore is a claim made for the owner. Acceptable while the owner cannot declare it (it is not under the project's control), and the register should mark it as that, not as a rule.
8. **Row 100's claim "a new schema compiles nothing while each column's code is compiled per column type"** is contradicted by lesson 2.2: DataFrames' workers for CSV's column types exist in no image until a glue extension compiles them. The design statement is right about what compiles; the register's row should carry the placement caveat, which rule 4's retirement (change 1) moves to "what Julia provides" (piece 5).

---

## 5. A simplified statement of the core

In the repository's style, as the register's first section could read after the changes above. Short sentences; one idea each.

**The guarantee.**
- Compiled code is never invalidated unless code it depends on changes.
- "Code it depends on" is the packages that own the function or a type (or a supertype) in one of its call signatures, and their extensions.
- Strict mode gives this as a theorem for every environment that loads without a `PirateError`. The default session relaxes it: a winning pirate is followed, once, as plain Julia follows it.

**Three rules.**
1. **Facts.** Compiled trait-world code depends on the method table only through facts: "at fact signature `s`, dispatch selects `r`". A fact signature is a tuple of concrete types, its union splits, the splits of concrete-element unions inside tuple arguments, or a closure's call at kinds. Any other call dispatches at run time and records nothing. Nothing is skipped. Compile-time evaluation only over facts, or where Julia's own asserted effects fold.
2. **Ownership.** A method's stakeholders are the owner of its function and the owners of the types in its own signature. Anyone else's method is a pirate. Only a stakeholder or a winning pirate can change a fact (Lemma O). In strict mode a pirate that would win at a fact of compiled trait-world code is refused where it is defined: at the prompt, by `include`, as an image's methods activate. By default it is followed.
3. **The boundary.** Only values cross into the trait world. A bound translates each once: a trait bound takes the user's object and the offsets of what it can see; a declared type asserts; `Callable{A, S}` takes a function from above as a pointer at a declared signature, checked at every call. Inside, a trait object is what its bound can see and nothing else. Code is compiled per key.

**Concepts.**
- **Trait:** an abstract type with a declared, checked contract: operations with result types, fields with types, associated types as parameters. Concreteness is opt-in per trait, one declaration with a level.
- **Conformance:** a declaration that a type joins a trait: operations from the type or forwarded to one field; declared fields mapped to stored fields. Checked at the declaration. Which operations the defaults serve is fixed there; compiled code and kept values depend on it, as they depend on a struct's definition, and it changes only by redeclaration.
- **Key:** what a bound can see: the implementing type, if any, and the declared fields' types. Workers are compiled per tuple of keys. A trait object is the user's object seen through offsets.
- **`Dynamic{X}`:** a value of any type conforming to `X`, reached through `X`'s operations. It holds the user's object. An operation on it is a call-site split over the declared conformances with a dynamic fallback, result asserted. It is the package's spelling of "a value of abstract type `X`" until membership is subtyping.
- **`Callable{A, S}`:** a function from above, one mode. A function the library specializes on takes an unbounded argument.
- **Dispatch:** types first, then traits. A trait bound ranks above `Any` and below every type.

**What Julia provides.**
- (A) facts as a mode of inference; (B) a per-method flag and owner for facts-compiled code, with native code in images; (C) owner-aware dynamic dispatch; (D) the `Dynamic` call-site split in the inliner.
- Pieces 1, 1′, 14, 15 for the refusal; 3 (field offsets) and 17 (type printers), independent.
- `--trim` compiles the plain call in the closed world; the facts mode is off in a build.
- Everything else is package code: the macros, checks, definition checking, concrete mode, `verify_main`, printing.

**What is not claimed.** No change to results beyond values inference decides (A3). No "once for any type": a type that supplies behaviour gets its own copy, once, in its own image. The guarantee's strict tier is the prototype plus pieces 1′, 14, 15, the extension rule and bindings.

---

## Appendix: verification log

- `decisions.md` read in full (lines cited); `4-details.md`, `1-overview.md`, `2-design-choices.md`, `3-wrapping.md`, `open-issues.md`, the plan, the lessons, `factscompiler/README.md`, `wrapping-by-facts.md`, `strict-mode.md`, `aot-under-facts.md`, `julia-support.md`, `keys-plan.md`, `associated-types.md` §5; the three reviews of 2026-10-18; session notes 23 (D5, D6), 25, 29; root `README.md`, `writeup/README.md`.
- Commits named in the register: all found in TraitWorld except 329e945, dda875f, 6c7f088, which are design-repository commits (notes rewrites), as their text says; TDE 8c25ae3 found.
- `grep` (appendix of §2): `Callable{`, `compiled_call`, `CompiledCall`, `dynamic_call` in every demonstrator and fork source: none; `DynamicFn`/`dynamic_fn` in TDE only; `conforms(` outside TraitWorld: none; `dynamic by` in sources and tests: none; `Like{`/`withfields`: none outside TraitWorld (TraitCSV uses `::Self`); `Dynamic{` in TDE, TraitMakie, TraitTables, TraitCSV, the DataFrames fork; `@trait … <: (`: one test; `JULIA_TW_*`: 13 switches; `_latest_under_policy`/`_in_world_under_policy`: 29 sites; `{R}` traits in `runtests.jl`: 10; `projection|ProjRec|proj_` in `implement.jl`: 56; `@max_methods 1` registries: 22 in `core.jl`.
- `strict.jl:52–57` (protected set), `entry.jl:605, 613` (`DynamicFn`), `entry.jl:643–726` (`LikeResult`, `_invert`, `_rebuild`), `hooks.jl:151` and `implement.jl:705, 712` (messages), `trait_module.jl:111–177, 412` (the sugar inside trait modules only), `implement.jl:785, 1234` (`:dynamic` flag), compiler copy `facts.jl:78–95` (`sealed_call`), in-tree `facts.jl:16` (`jl_compile_by_facts`, uncommitted), `julia-1.13 status` (three modified files, `facts.jl` untracked), `git -C julia-1.13 log v1.13.2..HEAD` (pieces 2 and 4 present), `ls experiments/sysimage` (present).
- **Experiment** `/tmp/claude-1000/review-decisions/redef.jl`, patched 1.13.2, `flock … nice -n 19 timeout 900 julia-1.13/julia --startup-file=no`:
  ```
  f(a1) = 2
  redefinition accepted: (:x, :y)
  typeof(a1) === A ? false   (old value keeps old type)
  f(a2) methods: ERROR MethodError: no method matching f(::A)
  f(a2) = 3   f(a1) = 2  (old method on old type still applies)
  Base.invoke_in_world(w0, f, a1) = 2
  old type: @world(A, 39302:39308)  new type: A  same name: true
  ```
