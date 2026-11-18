# Review: the implementation plan for `Dynamic` and `Compiled` (W-4)

**Reviewed:** [`../plans/2026-10-20-dynamic-compiled-implementation.md`](../plans/2026-10-20-dynamic-compiled-implementation.md) at design commit f2bec03, against the rule in [`../plans/2026-10-20-dynamic-and-compiled.md`](../plans/2026-10-20-dynamic-and-compiled.md) §0, the decision log's rows of 2026-10-20, the references (traits, lowering, compiler, facts), TraitWorld main 5b172e1 (`src/core.jl`, `entry.jl`, `trait_module.jl`, `untyped.jl`, `ahead.jl`, `BaseTraits.jl`, `trait.jl`, `defcheck.jl`, `checks.jl`, `compiler.jl`) and julia-1.13 3b8085c222 (`Compiler/src/facts.jl`, `abstractinterpretation.jl`, `src/julia-syntax.scm`, `src/ast.scm`).

**Reviewer:** Fable 5.1, 2026-10-20. Nothing was run: the machine is shared. "Verified" below means read in the code; "reasoning" means inferred from it.

**Verdict in one paragraph.** The plan is faithful to the nine rules of §0 in its language (findings 14 and 15 list the only quiet changes, both consequences of C2 rather than changes of wording). Its central lowering choices are implementable, but three of them carry costs the plan does not state and then measures too late or not at all: C2 deletes the untyped table and the entries compiled ahead in phase 3, before E-148 decides, although they are exactly the one-dispatch path that C3's `compiled_for` and C4's `Compiled` items need (finding 1); an erased worker compiled into a library's image splits over the library's own candidates only, so a user's type always takes the fallback, which turns open issue 32 from Optional into a prerequisite (finding 2); and `known_type` is `false` in every interpreted top-level call, so the REPL case is wider than the rule states and the demonstrators' rows (closures) measure what the user at the prompt does not get (finding 3). Findings 4 to 9 are gaps in C1, C4, C5 and the document tables that the phase-1 references would otherwise have to describe twice. Findings 10 to 15 are smaller.

Severity: **critical** would break the thesis of W-4; **high** changes the plan's order or a design choice; **medium** must be fixed before the phase that it concerns; **low** is housekeeping.

---

## 1. (high) C2 retires the one-dispatch path that C3 and C4 rely on, and does so before E-148 decides

**Evidence.**
- Plan §2 C2 (lines 66–67): the untyped callers' table (`untyped.jl`) and the entries compiled ahead (`_ahead_entry!`, `ahead.jl:168`) retire. Plan §5 step 3.8 (line 190) deletes them in phase 3; E-148 (line 218), which compares the erased path "against the retired table", runs in phase 5; R4 (line 242) says "if the erased path loses, the table stays". The deletion precedes its measurement.
- C3 (line 70): `compiled_for(x)` on a plain value of abstract type "is the wrapper, resolved by the next entry". At an entry compiled at `Any` that is: `_assemble` → `conformance(As{X}(), x)` (a run-time dispatch, `entry.jl:204`, `:377`), a trait object of unknown type, then `checked_call` (a second run-time dispatch, `trait_module.jl:643`), plus the wrapper's allocation. These two dispatches are the 105–117 ns per untyped call that the table's pointer path (`_pentry`, `untyped.jl:252`: one `:caller_world` call) and the per-type entry ahead (`ahead.jl:168`: one dispatch) were built to remove (open issues §4, item 9).
- The rule's guidance (§0, "Guidance for libraries"): "`Compiled` items pay off when the work per item is a call (`draw(m)` dispatches once per item into code compiled for the item's type)". Under C2 as planned, `draw(m)` on an item typed `Any` dispatches twice and allocates. E-150 (line 220) would then test the guidance on a lowering that cannot meet it.
- The cost model R4 states is per call. The cost that matters is per operation: a `Dynamic` position pays a split, or a fallback, at every operation inside the worker (lowering §13; `trait.jl:316`), where the table paid one dispatch per call and then ran the key's worker with direct operation calls. For a worker that loops over a column of n cells, the table wins by a factor of n. E-148 measures "ns per call, bytes, first-call latency" (line 218) and would not see this.

**Why it matters.** The rule makes untyped callers `Dynamic`; that is the user's. Which mechanism serves `compiled_for` from such a caller is the plan's, and the plan removes the only fast one.

**Fix.**
- Keep `untyped.jl` as the lowering of `compiled_for(x)` for a value of unknown type (it is literally "opened by `x`'s type at run time, the worker for its key reached by one dispatch", C3 line 63), and of `CompiledItems` reads in `Compiled` mode. At step 3.3, change only the entry's default routing (`known_type` false → erased), not the table.
- Move step 3.8 after E-148 and E-150, with the criterion written in the registry row: the table retires only if `compiled_for` through the entry's two dispatches is within noise of the pointer path for a worker that loops (n operations per call), not only for a worker that does one.
- E-148 adds a worker with a loop over operations, and reports the per-operation cost of the erased worker beside the per-call cost.
- Open issue 29 is then not "closed with C2" (line 159) but narrowed: entries compiled ahead serve `compiled_for` callers only; whether that still justifies the plain-code invalidation is the review the user asked for.

## 2. (high) An erased worker compiled ahead splits over the library's candidates only; every user type takes the fallback

**Evidence.**
- Compiler §4.2, Rules: "Which candidates a caller splits over is fixed when the caller is compiled. A caller compiled before a candidate is registered keeps the smaller split." Lowering §13: the operation's method is `@constprop :aggressive @inline` so that *each caller* splits over the candidates registered when *it* is compiled (`trait.jl:318–320`).
- Plan §3.1, §15 row (line 117): "workers ahead per key and for the erased key". An erased worker compiled into TraitDifferentialEquations' image (its workload, or a declaration in TDE) is compiled before any user's `@implement`. Its splits name TDE's own types. A user's `Lorenz` reaches the fallback at every operation, through the per-site cache (compiler §3.2), which thrashes past four types (compiler §3.3).
- Even an erased worker compiled in the session splits over "the first four declared" (`_note_conformances!`, `core.jl:532–553`, each batch sorted by file and line; the library's batch registers at load, the user's later). A library with four or more implementations of its own pushes every user type beyond the split.
- E-144 measured the price of the fallback in idiomatic code: 1.0–2.0 ns per item inside the split, 8.4–9.3 at five types through the view, 160–180 at 64 (registry row E-144).

**Why it matters.** The plan treats "beyond the split" as the second half of E-147 (line 217). For a `Dynamic` position in any library that compiles its workers ahead, or declares four implementations, it is the only case. The thesis of W-4 for TDE ("a new problem type compiles nothing", proposal §2's table) then holds, but its per-step cost is the fallback's, not the split's. That makes open issue 32 / E-145 (what follows the split) a prerequisite of W-4's value for solvers, not Optional (compiler §3.3's status).

**Fix.**
- State it in the references (traits §6.6's cost paragraph; lowering §13 and §15): the split of an erased worker covers the candidates registered when the worker was compiled; a worker in a package image covers that package's and its dependencies' declarations.
- E-147 gains a dimension: the erased solver worker compiled in TDE's image (workload) against compiled at the first call of the session, each with the user's type inside and beyond the split.
- Decide, as a question for the user, whether erased workers are compiled ahead at all, or deliberately left to the session's first call so that the user's declarations before it enter the split; and raise E-145 into W-4's order if the fallback dominates E-147.

## 3. (high) `known_type` is `false` for every interpreted top-level call; the rule says "a call on an ordinary global"

**Evidence.**
- Compiler §4.1: "Where it is not folded (the interpreter, code compiled at abstract types), it is `false`." Verified: `abstractinterpretation.jl:2808–2810` folds `known_type` to `Const(isdispatchelem(widenconst(argtypes[2])))` in inference only; `facts.jl:390` is `false` otherwise. Julia interprets a top-level expression without loops; a call inside it is a dynamic dispatch, and a `@nospecialize` entry is compiled at its compileable signature, `f(::Any, …)`.
- So under C2, `colmean(Matrix(…), 1)` typed at the prompt, `f(Circle(1.0))`, and a call on a `const` global are all `Dynamic`, not only a call on "an ordinary global" (§0 rule 2's REPL sentence; plan §0 line 26; the traits §6.6 row, line 105). A compiled top-level thunk (one with a loop) with a `const` global is `Compiled`. The attribute at the prompt depends on whether the thunk was interpreted.
- Today those calls reach the table or the entry compiled ahead for the type and run the key's worker (lowering §9.2–9.3), so the change is a real change for interactive users and for every example in `intro/` run at the prompt.
- R2 (line 240) sees the half of it that concerns tests ("a top-level call is now `Dynamic`"). The demonstrators' rows do not see it at all: `@first` wraps the timed call in a closure and calls it with `invokelatest` (`TraitDifferentialEquations/scripts/rows.jl:24–34`), so the closure is compiled, `U0`, `P0` are `const`, the entry inlines and the row measures `Compiled`. E-149 would report no change where the prompt gets a different path.

**Fix.**
- Traits §6.6 states the REPL case precisely: "code that Julia does not compile (a top-level statement without a loop) knows no type; every bound it calls is `Dynamic`; `compiled_for(x)` or a function gives `Compiled`."
- Make it question Q6, now rather than "to revisit": whether top-level calls should be special-cased in W-4 (the entry ahead for declared types kept for interpreted callers; or `compiled_for` by default when the caller is the interpreter, which `known_type` cannot express today and would need a second primitive).
- E-148's "at the REPL" row states the expectation (a literal at the prompt is `Dynamic`), and E-149 adds one row per demonstrator measured from an interpreted top-level call, labelled as such, beside the closure rows.

## 4. (medium-high) C1 has two representations of a dynamic value and does not state the conversion at the seams

**Evidence.** Under C1 a dynamic value is an erased `TObj` inside workers and the struct `Dynamic{X}` (`core.jl:351`, `t::Any`) in fields, containers and plain code (plan line 57). The plan names the conversions at a bound and at a store. It does not name the seams where an `isa` check meets the other representation:
- `opcall` checks `args isa op_args(X, Val(op), K, Val(N))` (`core.jl:797`). An operation declared with a `Dynamic{Y}` argument, which R8 (line 246) keeps as a typed argument, refuses an erased trait object: TDE declares `condition(cb::Callback, …, integ::Dynamic{IntegratorView})` and `affect!(cb::Callback, integ::Dynamic{IntegratorView})` (`ODECore.jl:60–61`). A bounded function `h(integ::Dynamic{IntegratorView})` that calls `condition(cb, u, t, integ)` would raise `TraitArgumentError` on its own argument.
- `CObj`'s call checks `args isa A` (`core.jl:902`); TDE's `CondSig` and `AffectSig` name `Dynamic{IntegratorView}` (`ODECore.jl:68–69`). The `Erased` pointer's declared argument types come from `_cdecl` (`core.jl:860`): a `Dynamic{X}` is a `Ref{Dynamic{X}}`; an erased trait object cannot go through it.
- `_like_out` branches on `u isa Dynamic` (`entry.jl:827`); the erased trait object reaches it as a `TObj`.
- Fixed parameters: a worker's lower bound carries `PTag{F, i, v}` for each parameter the bound fixes (`trait_module.jl:495–499`). Today `opened(d)` builds the typed view and dispatch checks the tag. An erased trait object made at an entry for a value of unknown type does not know the parameter's value; the entry must check it per candidate (and dynamically in the fallback) before attaching the bound's tag. The plan's step 3.1 does not mention tags.

**Fix.** C1 gets one more rule, written into lowering §13: where a slot is typed `Dynamic{X}` (an operation's declared argument, a `Callable`'s `A`, a field, a container, a `Like` result), an erased trait object of `X` is converted to a `Dynamic{X}` on the way in, and a `Dynamic{X}` becomes the erased trait object at a bound; the list of slots is the list above. Step 3.1 adds `opcall`, `CObj` and `_cdecl`; step 3.2 adds the tag check; TDE's callback path is the test.

## 5. (medium) C5 adds an indirection to every stored-function call and the plan neither states nor isolates it

**Evidence.** `DynamicFn{A, S}` is `CObj{A, S, Erased{A, S}}` (`entry.jl:768`), stored inline in `FunctionModel` and `FunctionCallback` (`ODECore.jl:102–103`, `:130–131`); a call is the `Erased` call (`core.jl:876–888`). `Dynamic{Callable{A, S}}` under C5 (line 83) is `struct Dynamic{X}; t::Any; end` holding that `CObj` behind an `Any` field: one more heap object, and per call a load, a type assertion and then the same `Erased` call. E-147's per-step number (line 217) mixes this with the split's cost at the model's operations.

**Fix.** Either lower `Dynamic{Callable{A, S}}` to its own layout (the reference may say `Dynamic{Callable}`; the lowering may keep `CObj{A, S, Erased{A, S}}` as that type's layout, which is not a synonym the user writes), or keep the struct and have E-147 separate "the right-hand side through `Dynamic{Callable}`" from "the model's operations through the split" with one row each. Also: `Callable{A, S, M}(f)` "also fixes the signature" (traits §9); C5 removes it and names only `Dynamic{Callable{A, S}}(f)`. Add `Compiled{Callable{A, S}}(f)` or say that fixing the signature in `Compiled` mode is gone.

## 6. (medium) C4's item encoding and its definition checking are unspecified

**Evidence.** C4 (line 78): the bound's tag becomes "a tag 'seen through `Y`' that both views carry". `Iterable{T}` defines `T = eltype(Self)` (`BaseTraits.jl:45`); `eltype` of `CompiledItems{Y, V}` and `DynamicItems{Y, V}` must then be one type that (a) the archetype's `iterate` returns at definition checking (`defcheck.jl:64–77`), (b) a bound of `Y` accepts, and (c) has `Y`'s operations, since the body calls `draw(m)` on it. Today that type is `Dynamic{Shape}`, which has operation methods (`trait.jl:301–320`) and opens at an entry. Nothing in the plan says what replaces it (the erased view type could). Further: a `Vector{Dynamic{Plot}}` today meets `Iterable{Shape}` as it is (traits §10.2); under C4 its items are "read as erased trait objects in every mode" (line 77), so either the container crosses into a view or `Dynamic{Plot}` satisfies the new tag. Step 3.7's file list omits `defcheck.jl`.

**Fix.** Write the encoding as a row of lowering §17 (the annotation types and the item tag), name the archetype's item type, say whether `Vector{Dynamic{X}}` crosses, and add `defcheck.jl` to step 3.7.

## 7. (medium) The phase-2 grep contradicts the phase-6 split, and the glossary must keep the old terms until phase 7

**Evidence.** §4.3 (line 175) greps "every current document of Appendix A" at the end of phase 2 and expects hits "only in deviation rows, alternatives and history". By the plan's own split (line 40), `intro/` (70 lines with the old spelling, Appendix A), `state.md` (`:12`, `:24`, `:151`), `design/evidence.md` (`:60`, `:189`) and `intro/results.md` (`:68`) keep it until phase 6. The glossary (phase 2, line 155) removes `DynamicCall`, `CompiledCall` and `DynamicFn` while its own index (`glossary.md:18`, `:28`) and `intro/` still use them. `design/performance.md` gets "the cost model of the two attributes" in phase 2 (line 161) before any number exists (CLAUDE.md, rule 5).

**Fix.** The glossary keeps the three entries through phase 6, each marked "the prototype's spelling until W-4 lands; intended: …". The §4.3 grep excludes the phase-6 documents, or lists them as expected hits with a count. `performance.md` changes in phase 6 only; the intended cost model belongs to traits §6.6 and the rationale.

## 8. (medium) Sections missing from the per-section tables

**traits.md** (plan §3.1):
- §3.1 Operations: R8 (line 246) says the rule for a `Dynamic{X}` argument of an operation "is to be stated in traits §3.1"; the table has no §3.1 row.
- §5.9 `dynamic by`: Q2 asks whether it goes; the table has no row.
- §14 Printing: "`Callable{Tuple{Float64}, Float64} at DynamicCall`" (`traits.md:971`; `_show_cobj_type`, `core.jl:915`) and how an erased trait object prints.
- §16 Membership: `conforms` on an erased trait object.

**lowering.md** (plan §3.2):
- §3 Trait declarations: the lowering of `@dynamic`, and the fate of the operation methods on `Dynamic{X}` values (`trait.jl:301–320`), which plain code keeps calling.
- §6 Layout: a fourth layout, the erased view, beside the three in the table.
- §11 Results like the input: R5.
- §14 Checks: definition checking and the keep analysis at the erased key (step 3.2).
- §16 Sessions: the tables' session stamps (`_SESSION`, `untyped.jl:40`) and `_pmiss` go with the table, if it goes (finding 1).

**compiler.md** §4.1: the Rules bullet names the table (`compiler.md:547`).

**Fix.** Add the rows.

## 9. (medium) Ordering inside phase 3, and a missing spike for R1

**Evidence.**
- Step 3.11 (review every test for top-level calls, line 193) is last, but the suite breaks at step 3.3, where `known_type` starts routing top-level calls to the erased worker (R2). Each step's "done when" is the suite passing.
- Step 3.8 precedes E-148 (finding 1).
- `run_all.sh dyncomp` (line 209): the script takes only a log tag and runs the current checkouts (`experiments/checks/run_all.sh:5–20`); "against the branches" means checking out `dynamic-compiled` in every repository first. Say so.
- R1 is the plan's load-bearing assumption ("a typed caller inlines the entry and folds `known_type` to `true`", line 65) and is checked only at step 3.3, after the erased machinery exists. Verified in lowering: the keyword sorter receives the `inline` meta (`ast.scm:529–536`, `julia-syntax.scm:582`), the facts meta (`:583`) and the positional `nospecialize` meta (`:589–593`), so the typed keyword path folds when the inliner honours `@inline`; the remaining risk is where it declines (cost or recursion limits, `kws...` splats) and the interpreter (finding 3). `test/untyped.jl` has no keyword case.

**Fix.** A step 3.0 on main: one test per entry shape (positional, keyword, vararg, `Callable`, several trait positions) that a typed caller's entry folds `known_type` and compiles the key's worker, run before any erased code. Move the test review of 3.11 to 3.3 (the top-level cases) and keep 3.11 for the per-rule tests. Order 3.8 after phase 5.

## 10. (medium) Decisions hidden in the plan that should be questions

- Retiring the table and the entries ahead (C2): the user flagged open issue 29 "for future review"; the plan closes it as a side effect (line 159). Finding 1.
- The top-level consequence of `known_type` (finding 3): the user agreed to "a call on an ordinary global"; the plan delivers "every interpreted call".
- R8's "operations' arguments keep the type's meaning" for `Dynamic{X}` (line 246): a language rule, so a question, not a risk.
- Decision row 81: "a `Dynamic` position fixes every parameter its operations' result types use (weak yes)". The plan's tables (§6.1, §6.6, §11) do not say what happens to `s::Dynamic{StateVector}` with `T` open: refused at definition, or results typed `Any`.
- C3's `compiled_for(m)` inside a loop over items typed `Any`: three dispatches and an allocation per item under C2 as planned (finding 1). The guidance's sentence would promise one.

**Fix.** Q6 to Q9 in §11, and the row-81 rule as a check in traits §11.

## 11. (low-medium) The measurements: spelling, baselines and what is missing

- **E-147** must name the spelling measured: `solve(prob::Dynamic{…})` declared by TDE, `solve(with_dynamic(prob))` by the caller, and the prompt (finding 3); and where the erased worker lives (finding 2). Its "`Compiled`" baseline is today's 335–371 ms new-type row; its natural second baseline is today's `FunctionModel` with a `DynamicFn` (25–26 ms, E-146), which is the `Dynamic` of today for a *function*. The per-step row separates the two costs of finding 5.
- **E-148** adds: a worker that loops over operations (finding 1); the erased worker's own compile latency and code size on a realistic worker (`TraitMakie`'s `draw!`, `TraitTables`' `summarize`): a split per operation with up to four inlined candidate bodies, against a per-key worker that inlines one.
- **E-150** adds the guidance's recommended spelling, `draw(compiled_for(m))` in the loop, beside `Iterable{Compiled{Mark}}`.
- Not measured anywhere: `with_dynamic(x)` on an isbits value from a typed caller (a box per call); the first-call cost of a `Dynamic` position in a fresh session that loads a package image holding the erased worker (does the split's candidate order survive the load as lowering §13 claims for `Dynamic` values).
- The baselines are fair where stated (product setting and `all`, three runs, GC reported, the build named). The rows' closures make them `Compiled` measurements; say so in each row (finding 3).

## 12. (low) Appendix B's line numbers are stale

`_assemble` is `entry.jl:374` (not `:225`), `_rule3_error` `:416` (not `:267`), `fallback` `:633` (not `:484`), `_from_trait_world` `:680` (not `:531`), `enter_callable` `:720` (not `:569`), `dynamic_fn` `:776` (not `:617`); `CObj` is `core.jl:897` (not `:763`), `Erased` `:841` (not `:697`); `tobj_bound` is `trait_module.jl:482`, `_fix_needed!` `:803`, `_finish_module` `:822`. The plan is not normative, but phase 1's deviation rows will cite "Where" from it; use 5b172e1's numbers.

## 13. (low) Closed builds, compiling ahead and the plain compile of the entry

- `ahead.jl:146–153` precompiles "the entry for `T` itself" for shapes the table does not serve. With `@nospecialize` on every trait position that compiles `f(::Any, …)`, which no typed caller uses. Step 3.8 says `_ahead_entry!` is reduced; this branch goes too.
- `verify_main` under `CLOSED_WORLD` (`entry.jl:107`; lowering §15.3): the erased worker's fallback is a run-time site; step 3.10 lists the declared implementations as its targets. Also list the entry's conformance split for a value of unknown type (`_ConformsTo`, `core.jl:514`), which is a second run-time site per position.
- The entry's erased path runs `split_call` in a *plain* compile (a plain caller in the product setting inlines the entry plainly). Not verified here that `abstract_split_call` (`abstractinterpretation.jl:2806`) is reached by the plain interpreter as by the facts one; check at step 3.3.

## 14. (low) Faithfulness to the rule, rule by rule

| Rule (§0) | In the plan | Verdict |
|---|---|---|
| 1, every value `Dynamic` or `Compiled`, first seen through a trait | C1, C2 step 4, C4 | faithful |
| 2, concrete `Compiled`, abstract `Dynamic`; the REPL | C2's `known_type` | faithful in wording; wider at the prompt (finding 3) |
| 3, a trait's default, `@dynamic` | C5, C6 | faithful; `Callable` keeps its own lowering rather than becoming a `@trait` (fine, say so in lowering §12) |
| 4, annotations on arguments and item parameters, no warning | C2 step 4, C4, traits §6.1 | faithful |
| 5, `compiled_for`, `with_dynamic` always win | C3 | faithful in meaning; its cost from an untyped caller is not the guidance's (finding 1) |
| 6, a trait's name in an item parameter | C4, traits §10.2 | faithful; `Vector{Circle}` crosses into `CompiledItems` rather than "meets the bound as it is" (§0, "What changes"): same result, different lowering, acceptable |
| 7, values carry | C1 (a `Dynamic` is never opened) | faithful |
| 8, the warning | C6, at the module's end | faithful (decision row 82 says "at its definition"; the module's end is where `export`/`public` are known) |
| 9, library to library | C1 | faithful |
| no synonyms | C5 | faithful; the internal layout of `Dynamic{Callable}` is open (finding 5) |
| row 81, mixed modes per the `Compiled` keys; a `Dynamic` position fixes its parameters | C1 one worker per key tuple; the parameter rule absent | half (finding 10) |
| "What changes", traits §3.7 | C7 | faithful |

## 15. (low) Smaller points

- CLAUDE.md rule 1: a decision's reference change and its decision-log row go in one commit. §3.4 (line 147) writes the log row after all four references. Put each C-item's row in the commit of the reference that states it.
- `intro/traits-by-example.md` §20 "Planned syntax" already shows forms that do not work yet, checked by `reference.jl`; phase 2 could add `Compiled{X}` and `compiled_for` there without breaking "current state only", so that programmers see the direction before phase 6.
- The plan's §0 says the warning of rule 8 names "the explicit conversion as the fix"; C6 says the same; good. It should also say what `Base.ispublic` returns for a function defined at the prompt (no module statement), to avoid a warning on every interactive definition.
- Traits §6.5 row (line 107) says a `Dynamic{X}` argument "is not a typed method any more" inside trait modules. Outside them, `Dynamic{X}` stays a concrete Julia type with Julia's dispatch (TraitMakie's `Base.convert(::Type{Dynamic{X}}, x::Dynamic{X})`, `TraitMakie.jl:73`). Say both in §6.5, or the intro will overgeneralize.
- "`mkdocs build` passes its link validation" is phase 1's done-when; the glossary anchors of finding 7 are the first thing it will catch.

---

## What this review did not do

It did not run anything. It did not check the demonstrators' tests, the hetero-idiomatic scripts or the acceptance suite beyond reading their registry rows. It did not read `implement.jl`, `verify.jl` or `hooks.jl`. The claims about the interpreter and `jl_eval_with_compiler_p` are from knowledge of Julia's runtime, not from this tree.
