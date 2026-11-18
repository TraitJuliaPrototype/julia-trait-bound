# Fresh-eye review of reference/facts.md (2026-10-26)

**Reviewed:** `writeup/reference/facts.md` at design repository c6662bf; the patched Julia at `julia-1.13/` fa4e7f5798 (source) with its system image built from 6d480d0753 (the build of 2026-10-21; fa4e7f5798's changes are committed, not built); TraitWorld 4410407.

**Method.** I read `facts.md` as an outsider, then `reference/README.md`, `compiler.md` in full, the sections of `traits.md` (§10) and `lowering.md` (§2, §9.3, §15.1) that `facts.md` links, the glossary, `open-issues.md`, the facts rows of `record/decisions.md`, and `design/julia-changes.md`. Against the code I checked: `Compiler/src/facts.jl` (all), the facts gates in `abstractinterpretation.jl` (`find_method_matches`, `abstract_call_gf_by_type`, `merge_override_effects!`), `typeinfer.jl` (`adjust_effects`, `typeinf_ext_toplevel`), `src/gf.c` (`_invalidate_backedges`, `jl_default_owner`, `facts_callee_owner`), `src/module.c` (`jl_method_is_facts`), `src/codegen.cpp` (`applygeneric_for` sites, `invokelatest`), `TraitWorld/src/strict.jl`, `hooks.jl`, `ownership.jl`, `trait_module.jl` (`is_trait_world`), and the check list of `experiments/facts/acceptance_compiler.jl`. Three small runs on the patched binary (system image 6d480d0753), each a few seconds: the Vararg counterexample to Lemma O (`scratchpad/vararg_lemma_o.jl`), TraitWorld's ownership verdict on the same method (`scratchpad/owned_tw.jl`), and G1.10's shape with the assertion one frame up (`scratchpad/assert_one_up.jl`). Not checked: package images and `--trim` by experiment, strict mode by experiment (reasoned from `strict.jl`), threads, the `Dynamic` split beyond reading `abstract_split_call`, and `return_type`'s fold beyond reading `facts_plain_return_type`.

**Counts.** High 2, Medium 10, Low 9.

---

## High

### H1. Lemma O is false: an owned method with its only owned type in a `Vararg` tail wins at a concrete fact of a non-stakeholder, and strict mode lets it through

- **Location:** `writeup/reference/facts.md:68` (stakeholders of a method), `:70` (pirate), `:76` (Lemma O), `:134` (G2, "By Lemma O"), `:167` (the strict tier "holds in every environment that loads without a `PirateError`"), `:430`–`:432` (strict rule), `:438` (the safety net), `:442` (the property). Also `traits.md:1212`–`1215`, the glossary's "Stakeholder" and "Pirate", `design.md:37`.
- **What is wrong.** Lemma O: "A method that applies at a concrete `s` and is no pirate is defined by a stakeholder of `s`." Counterexample: `Lib.g(x::Integer) = 1`; package `P` owns `MyT` and defines `Lib.g(x::Int, y::MyT...) = 2`. By §1, `P` is a stakeholder of its own method (`MyT` is in its signature), so it is no pirate. The method applies at the concrete `s = Tuple{typeof(g), Int}` (zero vararg elements), whose stakeholders are only `Lib` and Julia. It is more specific than `g(::Integer)`, so it wins there.
- ***Verified*** on the patched binary (`scratchpad/vararg_lemma_o.jl`): a facts module `M` with `k(x::Int) = Lib.g(x)`; `M.k(1)` gives 1 and leaves one `CodeInstance` of owner `:facts` with `max_world = ∞`; after `P`'s definition its `max_world` is lowered and `M.k(1)` gives 2; `jl_type_morespecific(g(::Int, ::MyT...), g(::Integer))` is 1. TraitWorld agrees that the method is owned: `owned_method(m) == true`, `_stakeholder(P, Tuple{typeof(g), Int}) == false` (`scratchpad/owned_tw.jl`). In strict mode `_strict_violation` returns at `owned_method(m) && return nothing` (`TraitWorld/src/strict.jl:130`) and the safety net returns at `strict.jl:269` for the same reason, so the definition is neither refused nor caught: trait code is invalidated by a non-stakeholder with no error.
- **Cause.** `_owners!` counts a `Vararg{T}`'s `T` as an owned type of the method whatever the arity (`ownership.jl:155`), and `_sig_alternatives` enumerates `Union` members but not the arities a `Vararg` admits. Lemma O's proof needs the method's stakeholders to be stakeholders of *every* concrete signature it applies to; a `Vararg` tail breaks that at the arity where it is empty. The same hole exists for a `Vararg` inside a tuple argument and for a varargs method of a Base function (`Base.vcat(::MyT...)` applies at `vcat()`; in that case Base's exact `vcat()` happens to win).
- **Damage.** G2's attribution "such a definition is a stakeholder's, or a pirate's that wins there" (`:134`) is false; the strict tier's property (`:167`, `:442`) is false; traits §10.3's "a definition by a stakeholder is followed; strict mode refuses a pirate" does not cover this case. This challenges the decision row "Stakeholders and Lemma O restated (decision 2)" (`record/decisions.md` §4), which states the current definition.
- **Fix.** Judge a method's stakeholders per arity, as `Union`s are judged per member. In §1 replace the stakeholder sentence by: "**Stakeholders of a method:** the owner of its function, and the owners of the types in its own signature, judged at every signature it applies to: a `Union`'s members count one by one, and a `Vararg{T}` tail contributes `T` only where at least one vararg element is present. So `f(::Int, ::MyT...)` is a pirate at `f(::Int)`." Say the same in traits §10.2 (it changes what a user may write) and in the glossary. Until built, add a deviation row (new ID, F-19; F-numbers are never reused): "The reference judges stakeholders per arity; `owned_method` counts a `Vararg`'s element as owned at every arity (`TraitWorld/src/ownership.jl:155`, `:233`), so strict mode neither refuses such a method (`strict.jl:130`) nor catches it afterwards (`strict.jl:269`)." Add an acceptance check with the run above. Record the challenge to decision 2 in the log.

### H2. The asserted-effects rule is per frame, so a fold still rests on a dispatch no edge records; G1 fails one frame above a run-time site

- **Location:** `writeup/reference/facts.md:369`–`:377` (§8, Rule and Why), `:114` (G1, "Why it holds", last bullet), `:211` (§4.1), `:603` (F-12).
- **What is wrong.** §8 says "In a frame compiled by facts that has a run-time site, no asserted effect applies", and gives as the reason that "the fold would rest on a dispatch that no edge records". The reason is transitive; the rule and the code are not. `adjust_effects` drops the method-level override only when `frame.facts_rtsite` is set (`Compiler/src/typeinfer.jl:492`), and `facts_rtsite` is set only on the frame that holds the run-time site (`abstractinterpretation.jl:134`). A frame without run-time sites that calls, at a fact signature, a frame with one keeps its `@assume_effects :foldable`; its callers then fold it at compile time with an edge to it only; the run-time site below recorded nothing.
- ***Verified*** (`scratchpad/assert_one_up.jl`, system image 6d480d0753): in a facts module, `g(x) = 1`; `h(x::Int) = g(Base.inferencebarrier(x))`; `Base.@assume_effects :foldable h2(x::Int) = h(x)`; `kfold() = h2(1)`. After `g(x) = 2` is redefined, the plain copy of the same module gives 2, the facts copy still gives 1. The control with the assertion on `h` itself (G1.10's shape) follows the redefinition. So G1 is violated: plain code records an edge for `g`'s abstract call and is invalidated; facts code records none and keeps the fold.
- **Why it is High.** G1 is stated as Implemented in both settings (`:100`), and its "Why it holds" (`:114`) claims the rule closes exactly this hole. Base and packages carry many method-level assertions; under `all` every one of them above a chain that reaches a run-time site is such a fold. F-16 (`promote_type` still folding over run-time sites under `all`, "not diagnosed") has this shape and may be an instance.
- **What F-12 misses.** F-12 names the statement-level variant ("`Base.@assume_effects :foldable g(y)` at a fact signature, where `g`'s own frame holds the run-time site") and calls it untested. The method-level variant is the same gap and is the common one; it is not in F-12, and the §8 Rule as written does not even make it a deviation.
- **Fix.** Decide the rule's scope and write it:
  - either make it transitive: "no asserted effect applies in a frame compiled by facts that has a run-time site, nor in a frame that calls such a frame, however deep" — implemented by carrying `facts_rtsite` into the callee's `CodeInstance` (a flag beside its effects) and setting the caller's `facts_rtsite` when it takes an edge to such a `CodeInstance` or inlines it; the test is the run above, method-level and statement-level;
  - or keep the per-frame rule and then strike the last bullet of G1's "Why it holds" and add to §2.1 "Conditions": "a method-level or statement-level assertion on a frame whose callees reach a run-time site is the asserter's promise, as in plain Julia; such a fold can go stale (F-12)".
  Either way, F-12 must name the method-level case and cite `typeinfer.jl:492`.

---

## Medium

### M1. Ownership is attributed to the module a method is evaluated in; `@eval Owner` launders a pirate, and traits §10.3 recommends it

- **Location:** `writeup/reference/facts.md:63` (owner: "a package owns the functions, types and bindings it defines"), `:430` (strict rule 1: Julia's methods are not checked); `traits.md:1229` ("Define as the owner with `@eval Owner f(…) = …`").
- ***Verified*** (`scratchpad/owned_tw.jl`): a method defined by `Core.eval(Base, :(Lib.g(x::Int, y::Float64) = 3))` has `owner(m.module) == :Julia`. `ownership.jl:9`–`11` says so itself ("a definition laundered through `Core.eval(Owner, …)` counts as the owner's", "PoC limit"). `_strict_violation` returns at `definer === :Julia` (`strict.jl:125`).
- **What is wrong.** The reference's "defines" reads as "whose code defines", but the implementation reads "in whose module it is evaluated", and the only user-visible text (traits §10.3) tells users to exploit that. So the strict tier's property is a convention: any package can define a winning pirate of Base in strict mode by `@eval Base`. The reference does not say this.
- **Fix.** In §1 say: "A method belongs to the module it is defined in, `@eval Owner` included: a package that evaluates a method into another module defines it as that module's owner, by convention." Then either make that the design (and strike nothing) or open an issue: "should a method be attributed to the package whose file defines it (`m.file`), so that `@eval Base` from a package is that package's method?" Add a deviation row only if the second is chosen.

### M2. §7.1 writes a deviation into the design text: rule 3 says "in both settings", the next paragraph says it does not hold in the product setting, and the row that said so (F-10) is retired

- **Location:** `writeup/reference/facts.md:334` (status "Implemented, with one exception"), `:346` (rule 3), `:350` (the exception), `:601` (F-10 retired); `compiler.md:158` (same), `record/decisions.md` §4, row "`return_type`: an exception in the product setting, to be revisited" (2026-10-21).
- **What is wrong.** `reference/README.md:21`–`:40`: the intended shape first, deviations in the table. Rule 3 states the intended shape (plain inference's answer at run time, in both settings). The paragraph after it describes what the implementation does today (facts inference's answer for a facts method in the product setting), with "to be revisited" and an open-issue link: that is a deviation by the README's own definition. Putting it in prose and retiring F-10 leaves §7.1 "Implemented" while its own text says the intended answer is not given. *Reasoning*, from the README's conventions. This challenges the decision row named above.
- **Fix.** Keep rule 3 as written. Replace the exception paragraph by a status note "**Planned** in the product setting for facts methods (F-19… or a new row)", and add a row: "§7.1 rule 3: at run time the answer is plain inference's in both settings. | Product setting: `return_type_interp` is a `NativeInterpreter` of owner `nothing`, which leaves a facts method to facts inference, whose answer can be wider (`map(worker, [])` makes a `Vector{Any}`); two caches, as C-10. | `Compiler/src/facts.jl:384`". The decision log can keep its row; its "Where" then points at the new deviation instead of the prose.

### M3. §7.1 rule 1 overclaims: a facts answer that is a constant or a concrete type *can* be wider than plain inference's, when plain's is `Union{}`

- **Location:** `writeup/reference/facts.md:339`; `:121` admits the case.
- **What is wrong.** Facts inference types a run-time site `Any`; a typeassert or a declared result then narrows it. Plain inference at the same call may prove that every applicable method throws, giving `Union{}` for the whole function. Example: `g(x) = (h(x)::Int)` with the only method `h(::Any) = 1.0`: plain gives `Union{}` (the assert can never pass), facts gives `Int`. Rule 1 folds `Int`; plain Julia's `return_type` gives `Union{}`; `map(g, [])` differs. §2.1 lists exactly this ("`Union{}` where every method at a run-time site throws") as the exception, so the two sections disagree in wording. *Reasoning*; the code (`tfuncs.jl:3183`) implements rule 1 as written.
- **Fix.** Rule 1: "…is folded when it cannot be wider than plain inference's except by the `Union{}` case of §2.1: a constant, a concrete type that is not a kind, or `Union{}`."

### M4. F-15 and F-18 describe the built binary, not the committed source; their "Where" lines are stale

- **Location:** `writeup/reference/facts.md:606` (F-15), `:609` (F-18), `:178` (§3 status), `:301` (§6.3 status).
- ***Verified*** by reading `Compiler/src/facts.jl` at fa4e7f5798: `is_fact_sig` uses `fact_splits_ok(T, max_union_splitting)` with Julia's `unionsplitcost` (lines 213–258), and `facts_const_call` does concrete and semi-concrete evaluation into a facts callee (lines 112–135), gated at `abstractinterpretation.jl:902`. The system image is older (6d480d0753), so the binary still does what the rows say. `facts.jl:211` (cited by F-15) is inside a docstring now.
- **What is wrong.** "The implementation does" is true of the binary and false of the repository the row names ("Paths are in the workspace: `julia-1.13/` is the patched Julia", `:588`). A reader who checks the code finds the row wrong; a reader who runs the binary finds the reference wrong. Also `concrete_splits` and `tuple_splits` (for `return_type` rule 2) still use `MAX_FACT_SPLITS`; that is design (§7.1 rule 2 says four), so F-15 should not imply they change.
- **Fix.** Each row: "Built in fa4e7f5798 (committed 2026-10-22), not yet in a build; the checks that retire the row are G1.31 (F-15) and G1.30 (F-18) on the next build." Fix the line numbers (`facts.jl:213`, `:248`; `abstractinterpretation.jl:902`). State in `:588` which commit the rows describe.

### M5. A call at a fact signature with too many matching methods becomes a dynamic call with no edge, is not marked as a run-time site, and keeps its assertions

- **Location:** `writeup/reference/facts.md:21` ("Every other call is a run-time site"), `:80` (the term), `:215`–`:219` (§4.2), `:369` (§8).
- ***Verified*** by reading: `abstract_call_gf_by_type` sets `facts_rtsite` only for `FACTS_ABSTRACT_SITE` (`abstractinterpretation.jl:134`); `find_simple_method_matches` and `find_union_split_method_matches` return other `FailedMethodMatch`es ("Too many methods matched", `:393`, `:415`) for a fact signature with more than `max_methods` matches, which happens at a concrete `Vararg` tail (several arities match) or at an ambiguous dispatch tuple. Such a call is typed `Any`, records no edge, and the frame keeps its asserted effects.
- **What is wrong.** By the reference's definition the call is at a fact signature, so it is not a run-time site, yet it is dispatched at run time with no edge: a third kind of call the document does not name. It re-opens §8's hole in the frame itself (not only one frame up, H2).
- **Fix.** §4.2: "A call at a fact signature that matches more than `max_methods` methods is a run-time site too." Code: set `facts_rtsite` for every `FailedMethodMatch` under the facts mode. Add a check: a `Vararg{Int}` call with four matching arities, asserted `:foldable`, redefined.

### M6. §2.2 says no check counts facts code across package loads; F-11 says `g2all.jl` does

- **Location:** `writeup/reference/facts.md:158` versus `:602`.
- ***Verified*** by reading both lines. F-11 also carries a measurement with date and build ("0 of 12,835 lost on julia-1.13 711484a23e, 2026-10-21"), which `reference/README.md:44` keeps out of references.
- **Fix.** `:158`: "`experiments/facts/g2all.jl` counts the facts owner's valid CodeInstances across ten loads interleaved with the demonstrators' work, in the product setting; not under `all`, nor with the loads first (F-11)." F-11: drop the number and date, cite the evidence row.

### M7. `--trim`: "uses no code compiled by facts" and "compiles every method plainly" are Implemented in the text and untested in F-7

- **Location:** `writeup/reference/facts.md:485` (§11), `:525`–`:526` (§12.3, status Implemented), `:598` (F-7: "whether facts code then reaches a trimmed build is untested"); `compiler.md:450`–`:453`.
- **What is wrong.** `jl_method_is_facts` is 0 under trim (`module.c`), so what the trim build *infers* is plain. But a trimmed build reuses package images' cached code, which holds `:facts` CodeInstances and plain entries that `:invoke` them (§11 says images keep both). Whether the trim compile queue infers those again plainly or emits the facts copies (with run-time sites) is exactly what F-7 calls untested. The §11 and §12.3 sentences are stated more broadly than the check behind them. *Reasoning.*
- **Fix.** §12.3 status: "Implemented for the code the build infers; whether code of the facts owner in package images reaches the binary is untested (F-7)." Or test it: build the smallest trimmed demonstrator and grep the binary's compiled CodeInstances by owner.

### M8. "Stakeholders of a concrete signature" is worded for method signatures, not concrete ones, and does not say that parameters count

- **Location:** `writeup/reference/facts.md:69`; glossary "Stakeholder".
- **What is wrong.** "The owners of every type in `s`, of their supertypes, and of the types bounding their parameters": a concrete `s` has no bounded parameters; its parameters are types (or values). Lemma O needs `MyT` in `Vector{MyT}` to count (so that `f(::Vector{MyT})` is a stakeholder's method), and `MyNumber` in `Vector{MyNum}` with `MyNum <: MyNumber` (for `f(::AbstractArray{<:MyNumber})`). The sentence does not say so; TraitWorld's `_owners!` (`ownership.jl:150`–`:177`) reads it recursively and maps a value parameter to its type's owner. *Reasoning* against the code.
- **Fix.** "The owner of its function, and the owners of every type in `s` at any depth: each argument type, its parameters, a `Type{T}`'s `T`, a value parameter's type, and the supertypes of each of these."

### M9. "The entries compiled ahead" are named twice as boundary methods, but no such entries exist

- **Location:** `writeup/reference/facts.md:89` (term "boundary method"), `:271` (§6.1 table).
- ***Verified***: the per-type entry methods compiled ahead were deleted (decision log, row "`compiled_for` from an untyped caller through the table…", 2026-10-21; open issues closed §2 item 29). `lowering.md` §15.1 compiles workers and the table's pattern method ahead, and neither `ahead.jl`, `untyped.jl` nor `entry.jl` carries `:facts_boundary` (grep); the only boundary marks are `trait_module.jl:709` and `implement.jl:675` (lowering §2).
- **Fix.** Delete "and the entries compiled ahead" / "and the entry methods compiled ahead" at both places. Boundary methods are TraitWorld's entries and `conformance` methods.

### M10. Terms used before they are defined, against §1's "each term is defined here once"

- **Location:** `writeup/reference/facts.md:61` (the promise); "trait code" at `:30`, `:165`–`:168`, `:440` (defined only at `:440`); "facts method", "neutral method", "plain method" at `:243`–`:249` (defined at `:266`); "stakeholder's change" at `:134` (explained by examples at `:147`); "kind" at `:184` (never defined: `DataType`, `UnionAll`, `Union`, `typeof(Union{})`); "winning pirate" relies on "wins" at `:72`, fine.
- **Fix.** Add to §1: "**Trait code:** the code of trait modules, compiled by facts (facts methods, §6.1)." "**Facts, boundary, plain, neutral method:** the four kinds of §6.1." "**Kind:** a type whose instances are types: `DataType`, `UnionAll`, `Union`, `typeof(Union{})`." "**A stakeholder's change:** a definition, deletion or redefinition by a stakeholder of the fact it changes."

---

## Low

### L1. The acceptance count is stale in three places

- `writeup/reference/facts.md:127`: "G1.1–G1.15, G1.17–G1.29 and G2.1 (29 checks)". The script has G1.30 and G1.31 too (31 checks; `experiments/facts/acceptance_compiler.jl:691`, `:701`), added with fa4e7f5798. `design/julia-changes.md:76` says 25 checks and "23/23". *Verified* by grep.
- **Fix.** Name the checks by range without a count, or make the count the evidence's job: "the checks G1.1–G1.31 and G2.1 (no G1.16)"; G1.30 and G1.31 wait for a build.

### L2. "The limit of four" in the status index is Julia's default, not the design's

- `:555` says "fact signatures (the six forms, the limit of four)"; §3 (`:191`) says the facts mode adds no limit of its own and uses the interpreter's `max_union_splitting`.
- **Fix.** "the six forms, split at Julia's `max_union_splitting`".

### L3. "A `Callable`'s mode" is a retired term

- `:82`: "Other 'modes' (strict mode, fully typed mode, a `Callable`'s mode)". The mode parameter of `Callable` was removed (decision log, "`Dynamic` and `Compiled`, refined": `CompiledCall`, `DynamicCall` removed); a `Callable` now has an attribute, `Compiled` or `Dynamic`.
- **Fix.** "(strict mode, fully typed mode)". A value's attribute is not a mode (glossary, "Mode").

### L4. The closure example does not show the closure form

- `:187`: `(T -> sizeof(T))(Int)` is `Tuple{typeof(clo), Type{Int}}`, a dispatch tuple (first row). The form matters at `Tuple{typeof(clo), DataType}`.
- **Fix.** Example: `map(T -> sizeof(T), types)` with `types::Vector{DataType}`: the call at `DataType`.

### L5. Lemma D says nothing

- `:77`: "A definition that does not win at `s` leaves dispatch at `s` unchanged" restates the definition of "wins" (`:72`). What G2 uses (`:139`) is: dispatch at `s` is a function of the set of methods, not of their order; so a pirate that loses against the final table loses in every order.
- **Fix.** State that, or drop Lemma D and say it in G2.

### L6. Measurements and review citations in the Deviations table

- F-11 (`:602`): a count with date and build. F-15 (`:606`): "measured in [the review of 2026-10-20, F3]". C-3 (compiler) likewise. `reference/README.md:44`: no measurements; "Where" names code, a commit or a test.
- **Fix.** Cite the evidence row (E-n) instead; keep the test's path.

### L7. Wording and links

- `:107`: "exists for plain code neither" → "does not exist for plain code either".
- `:106`: `[traits §5.8](traits.md)` has no anchor; `traits.md#58-callable-functions-at-a-declared-signature`.
- `:300`–`:301`: the §6.3 status links `[F-18](#15-deviations)` while every other row links `#deviations`; both resolve, pick one.

### L8. A Planned item inside an Implemented section, without a row

- `:400`: "Code at a `Dynamic` position is compiled once for the position … (Planned with `Dynamic` positions; checked by new acceptance cases when they are built.)" inside §9, "Status: Implemented" (`:384`).
- **Fix.** Move "Planned: the acceptance cases for `Dynamic` positions" into §9's status line.

### L9. "None is added" is Julia's precision, not the design's

- `:230`: "No invalidation is skipped, and none is added." Julia's method-insertion walk decides winners by `jl_type_morespecific` between method signatures and a "covered by a more specific method" test (`gf.c`, `jl_method_table_insert`); for concrete signatures that is exact up to Julia's handling of type variables and ambiguities, which the design inherits.
- **Fix.** "…and none is added beyond what Julia's own invalidation adds at a concrete signature."

---

## Notes that are not findings

- The union-splitting cost text (`:191`) matches `unionsplitcost` exactly (the largest union counted as 2; I checked the two examples by hand against the code).
- `invokelatest` and `invoke_in_world` do go through `applygeneric_for` in codegen (`codegen.cpp:4297`–`:4328`), as §5 says.
- The bare-`MethodInstance` edge rule of §4.3 is what `_invalidate_backedges` does (`gf.c:2400`–`:2450`): the owner filter applies only when a particular `CodeInstance` is invalidated; a method replacement passes `NULL` and reaches every owner.
- `is_trait_world` (`trait_module.jl:38`) matches the list in §10.2's note.
- The `jl_apply` rule of §5 follows from `jl_default_owner` (`gf.c:424`) and `jl_method_is_facts` (`module.c`), as stated; a boundary method's default owner is `nothing`, consistent with §6.2's table.

---

**Addendum (2026-10-26, filing).** The scripts cited as `scratchpad/…` are filed in `experiments/review-2026-10-26-references/`. H1 and H2 were rerun independently by the session that commissioned the review, on the same system image (6d480d0753): both reproduce (`vararg_lemma_o.rerun.log`, `assert_one_up.rerun.log` there). Compiler review H1 (same date) is this review's M5, found independently. What was done with each finding is recorded where it was done.
