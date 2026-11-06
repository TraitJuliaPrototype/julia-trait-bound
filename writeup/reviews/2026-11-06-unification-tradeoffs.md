# Review: what the unification trades against the original implementation's goals (2026-11-06)

Status: current. Not edited after writing, except by a dated addendum. Dispositions of the findings: none yet (to be recorded where each is taken up).

**The question** (the user, 2026-11-06): "The original implementation made a lot of progress to our main goal of cutting load times, recompiles, session times, and enabling caching and better type signatures and error messages. Painless AOT and machine code caches that leverage the new guarantees were also well in sight. The unification offers substantial conceptual simplifications. The question is what the trade off is and whether they can be recovered later through further work. The unification plan should focus on identifying these trade offs and exploring mitigations. As always Swift, Rust and Mojo provide crucial real world experience."

**By whom, how.** A Fable agent, at the user's request. A reading review: no Julia was run, nothing built or measured, no file but this one written. "Verified" means read at the lines cited in the record or in a fetched primary source; "inferred" means my reasoning from the rules, and is marked. The two reviews of the draft ([the prototypes'](2026-11-06-unified-reference-prototypes.md), [the work plan's](../plans/2026-11-06-work-plan-under-the-draft-reference.md)) are not repeated; a finding of theirs is cited where a trade-off rests on it.

## What was read

- The original: `writeup/reference/` (compiler §2.9, §7.6–§7.8; facts §2.2, §11), `design.md`, `design/evidence.md`, `design/julia-changes.md`, `record/experiments.md` (the rows E-29, E-153, E-171, E-175, E-177, E-180, E-188, E-205 to E-208, E-231, E-233, E-234, E-238, E-256, E-258 to E-264), `record/performance-explorations.md`, `state.md`, `explorations/aot-under-facts.md`, `facts-keyed-cache.md`, `fast-loads.md`, `load-on-demand.md`, `keys-plan.md`.
- The unified: `writeup/reference-unified/` (README, compiler.md in full, facts.md in full, traits.md §7, §9, §11.3–§11.4, §13–§16, lowering.md §9–§13), `plans/2026-11-06-traits-are-abstract-types.md`, `plans/2026-11-05-unification-synthesis.md`, `plans/2026-10-29-unification-evidence.md`, `plans/2026-11-06-work-plan-under-the-draft-reference.md`, `record/decisions.md` §9, `open-issues.md` §1, `experiments/w105/census/README.md`.
- The reviews: [2026-10-29-unified-build-review.md](2026-10-29-unified-build-review.md) (H1–H4, D1–D9), [2026-11-06-oc-build-audit.md](2026-11-06-oc-build-audit.md) (summary, verdicts per file), [2026-11-06-unified-reference-prototypes.md](2026-11-06-unified-reference-prototypes.md) with its addendum.
- Other languages: `design/other-languages.md`, `record/other-languages-research-2026-10-16.md`, and the primary sources listed at the end (fetched 2026-11-06).

## Summary

- **The guarantee machinery survives the unification nearly unchanged.** The draft's facts reference states the same G1, G2, fact signatures, run-time sites, strict mode and image rules as the current one, in new terms (verified: `reference-unified/facts.md:85–136`, `:152–176`, `:354–371`, `:392–411` against `reference/facts.md:135–168`, `:491–518`). What the original *achieved* for recompiles (E-29, E-153, E-177) rests on that machinery, not on trait objects, entries or workers. So the thesis "the unification keeps the goals" is mostly right. It is wrong in four places, each measurable before the stage that fixes it in code.
- **Trade-off 1, the largest: G2 loses the second cache owner.** Today facts code reaching Base gets facts copies of Base, and no load discards them: 0 of 15,030 lost (E-29). The draft has one CodeInstance per MethodInstance and policy (`compiler.md:146–161`), so facts code calls plain Base code and is invalidated with it through code edges; result edges are saved only by the code slot. E-261 puts the loss at 120 and 100 facts callers per session of loads (780 and 457 with their callers), of which the slot keeps 67 and 91 (verified: `design/evidence.md:28`, the registry row). The rest is a real regression of "stable caches" for interop. **Recoverable at no cost now:** the slot (W-101), the G2 predicate on every CodeInstance (so fully typed plain callees are kept and cached), and the draft's own boundary flag (`:facts_boundary`, "up to one CodeInstance per policy", `compiler.md:138–143`, `:158`), which is the second owner per method, on demand.
- **Trade-off 2: "a membership invalidates nothing" becomes the stopgap C-18 until guards exist.** Until N7, every `@implement` replays the method-insertion walk and invalidates compiled callers (`compiler.md:771`). The guards are the largest compiler piece after keys, and the work plan's S9 proposes making them Optional. E-259's census (7 guard sites in five sessions, none in a loop) suggests the stopgap's volume is tiny in the ports and huge in one conservative shape (a set under `Vararg`: 2,898 cache entries, the synthesis plan §1.4). This should be measured on the ports' sessions before N7 is built or dropped. HotSpot's precedent is on the stopgap's side (deoptimize on class load, no guards), with a narrowed walk.
- **Trade-off 3: keys become Optional (open issue 145).** E-263 shows 4 of 148 memberships share a key, so the ports lose nothing. What keys bought beyond sharing is the *exclusion* of undeclared parts from compiled code (the original motivation: callbacks out of the integrator's key, `explorations/keys-plan.md:33`). Under per-type compilation the only other way to exclude a part is `Dynamic{X}` (a dispatch per operation: 7.6–7.8 ns against 1.5 ns direct, E-157) or restructuring the type, which is how TDE did it (W-63's two-layer adapters, which the prototypes' review says stay). Recoverable later: yes, if the draft keeps the classification per argument (needed by `bounded` anyway), the contract on the `TypeName` and the entry's receiver; all three are in W-98/N1 already.
- **Trade-off 4: the type system's changes cost plain code something.** Methods at open sets in the typemap's linear list on `getindex`, `iterate` and `length` (prototypes' review M6), entries consulted in `jl_subtype`'s walk (work plan weak point 9), a method-table query inside `jl_subtype` for `Callable` (`compiler.md:587`), guards' shadow queries in inference. E-262 saw Base's suites 2–6 % slower with no set declared (one run, within noise). The original's property "plain code keeps all of Julia's behaviour" (`facts.md:420`) was a property of the facts mode; the type system has no such property. Gates with a 10 % bound are too loose for dispatch-heavy code.
- **What is kept or gained:** load protection (the facts policy per method, images with memberships activated before validation), fewer CodeInstances per new type (E-256's 32–45 entry instances per held type go with the entries), the subtrait encoding's 237 rejected image CodeInstances (E-238) go with one dispatch, open issue 125's 0.24–0.34 s of Base's facts copies per session goes by construction, Revise (T-81), the record complete for a machine-code cache (`compiler.md:644–659`), AOT in kind unchanged with less machinery to trim.
- **What the plan should change:** measure trade-offs 1, 2 and 4 before W-100, N7 and W-99's gate respectively (§5, X1 to X4); build the slot; state the G2 loss in `design.md` with E-261's numbers; change `Callable`'s mechanism from a query inside subtyping to derived entries (P-7's mechanism is mine, not the user's); keep the classification in N1/N4; keep the facts policy (W-100) a patch series independent of the type system, for upstream.

---

## 1. Goal by goal

Each table: what the original achieved or had in sight (with its evidence), what the draft keeps, gains, loses or puts at risk, and how confident that is.

### 1.1 Load times

| Original | Unified |
|---|---|
| The trait demonstrators load in 0.44–0.46 s, TraitMakie 0.35 s, TraitReport 0.36 s (below Python's imports), the SciML split packages 0.57 s with members fixed from image records (E-168, E-228, E-233, E-231; `evidence.md:139–142`, `:148–155`, `:216–217`). A trait world of 4,000 workers loads in 0.30 s (E-171). The forks' imports 1.38 s: image validation 0.6 s, TraitWorld's hooks 0.2 s (E-233). | **Kept:** images keep memberships, check records and compiled-ahead code; memberships activated before validation (`compiler.md:644–649`; lowering §11–§12). **Gained:** no facts copies of Base to compile or validate (open issue 125, by construction, synthesis §5 stage 3); no entries per member (E-256's 32–45 CodeInstances per held type, T-94). **At risk, unmeasured:** (a) the stopgap at each membership an image activates: each `@implement` at load replays an insertion walk (C-18); (b) methods at open sets on Base's hottest functions in the typemap's linear list, scanned on every cache miss (M6); (c) `jl_subtype` consulting entries on common chains (`AbstractVector` under BaseTraits' families), pruned by reachability only if P-28 lands in W-98 (`compiler.md:291`); (d) the first slice's sessions run without the split, keys or facts: slower by design (work plan S1, `:272–279`). |

Confidence: moderate. The load's largest terms (image validation, package trees) are plain Julia's in both designs (E-185: validation about 1.4 s of stock's load). The new costs (a)–(c) are structural, small in the measured shapes (oc's 24 memberships: 48 events, 0.014 s; a 200-method lookup within 1.04×) and unmeasured on a port. Inferred: (b) matters most for BaseTraits, whose operations are methods of `Base.getindex` and `iterate` at open sets (`lowering.md:187–189`; the prototypes' review M6 says the same).

### 1.2 Recompiles and invalidations

| Original | Unified |
|---|---|
| G2 in the product setting: 0 of 15,030 CodeInstances of the facts owner lost after ten loads, both orders (E-29). NetworkDynamics wrapped: the next pass recompiles 0.04 s against 4.7 s (E-153, `evidence.md:49–55`). Makie by facts: 0.02 s against 6.1 s after a late `using DataFrames` (E-177). An implementation invalidates nothing: lowering made it a definition that wins at no fact (`reference/facts.md:162`); in the prototype it still invalidates its `Main` caller, 11 MethodInstances (E-254). TraitCSV's extension by implementation keeps the reader's code (`evidence.md:336`). | **Kept in design:** G1, G2, Lemma O and D, strict mode, the two tiers (`facts.md:85–148`). **Lost, quantified:** the second owner. Facts code calling plain code holds code edges (inlined, constant-propagated, evaluated) and result edges; code edges are invalidated with the callee, result edges revalidated by the slot (`facts.md:120–123`, `compiler.md:217–226`). E-261: without the slot 120 and 100 facts callers lost per session of loads (780 and 457 with theirs); with it 53 and 9 remain (verified: the registry row; approximations stated there, one run each). Against E-29's 0. **Lost until N7:** "a membership invalidates nothing": C-18 replays the insertion walk at each `@implement` and invalidates compiled callers whose selected method changes (`compiler.md:771`). **At risk:** `Callable` memberships that *end* when a method is deleted or replaced (`facts.md:335`): a stakeholder's change by Lemma O, but a new kind of invalidation the original did not have (verified the rule; its volume inferred small). |

Confidence: high on the direction, low on the size. E-261 counts CodeInstances, not time. The time of recompiling 457 facts callers of Base in a session is the number to get (§5, X1). Inferred: the lost callers are exactly the facts copies of Base's abstract-signature code (containers of `Any`, `show`, broadcasting), which the second owner compiled by facts and kept in images (julia-changes §2, 9892bfc288: the first `@implement` of a session inferred 188 ms, 17 ms once those copies were kept; `design/julia-changes.md:36`). Under one CodeInstance per MethodInstance and policy, stock Julia's rule drops plain code reached only by a dynamic call from an image (`compiler.md:429–453` of the current reference), so that 188 ms returns unless the image keeps plain code whose record satisfies G2 (§3, M1).

### 1.3 Session time (time to first X)

| Original | Unified |
|---|---|
| The trait demonstrators' session 0.94–0.99 s against Python's 1.45 s; the SciML split packages 1.19–1.20 s; TraitMakie's plotting 0.68 s against matplotlib's 0.98 s; TraitReport 0.63 against 0.61 s; the forks 4.71–4.83 s against pandas' 0.54 s (E-168, E-231, E-228, E-233). A new callback closure 24 ms, a new problem type's first solve 324–336 ms (the solver per key), parameters at the surface 0.21 s instead of 1.31 s (E-181), schema independence (E-215). | **Kept:** `Callable` `Dynamic` by default, `first_seen` in trait modules, the split and its table (cherry-picked, S7), `@default_compiled` for hot inner calls (traits §7.5, §7.10). Per-type compilation equals per-key compilation where the receiver is the member (E-263: 143 of 148). **Gained:** fewer instances per new type (no entries); constructors in the method table (L-50 goes). **At risk:** (a) `Callable` by a `hasmethod` query memoized per (`F`, `A`) inside subtyping: a cost per new closure type and a reentrancy hazard (`compiler.md:586–588`; work plan weak point 1, `:391–400`); (b) the first `@implement` of a session re-inferring Base's code (§1.2); (c) the stopgap's walk at each `@implement` in the session; (d) the first slice is slower than the prototype until N4–N7 land, and the plan's only session gate is W-104's (`:216`). |

Confidence: moderate. The prototypes' review found the ports' architecture unchanged under the draft (`:298`), so the session numbers should carry over once N4 to N7 exist. The risk is in the order of work: the premise is exercised on a slice whose speed mechanisms are all deferred, so a slow slice proves nothing against the thesis and a fast one nothing for it.

### 1.4 Caching: package images, and a machine-code cache across sessions

| Original | Unified |
|---|---|
| Images keep facts code reached only dynamically (keep-compiled, piece 5; 9892bfc288), machine code only for running owners (E-201, 7–13 % smaller), member records (E-231: the SciML load 1.18 → 0.57 s), check records (E-203). The facts-keyed cache (W-66): fingerprints keep 2,143 of 2,143 entries across an unrelated update (E-195); the store's bound 1.5 s in C, 0.02 s in D, code generation dominant (E-205); paused. E-234: a cache of a session's machine code brings the forks to 2.99–3.22 s; 1,083 of 1,175 kept types are plain, so a facts-only store keeps about a tenth. | **Kept:** the record complete, targets named by identities stable across sessions, "a cache later adds a loader, not a mechanism" (`compiler.md:651–657`); member records as the member hook's image answers (`compiler.md:714`); compiling ahead from the set-to-methods index (lowering §12). **Gained:** one CodeInstance per MethodInstance and policy removes the owner dimension from a store and lets one record serve both policies. **Lost or weakened:** (a) the facts-keyed cache's cheap validation ("origins compared, no method lookups", `explorations/facts-keyed-cache.md:31–34`) held because facts code's callees were facts code; now a facts entry's code-edge callees in plain code are valid only as plain Julia's method table says. The G2 predicate (`compiler.md:206–215`: every inlined callee's own record satisfies G2) restores it for entries whose plain callees are fully typed; others need Julia's edge validation, which the store note's revision 2 already uses (open issue 80). (b) Keep-compiled for facts copies of Base: gone with the owner (§1.2). |

Confidence: moderate. Inferred: the loss (b) is the one that shows in a session; (a) changes the store's admissibility predicate, not its feasibility. Note that E-234's lesson, the saving is plain code, makes the unified model *better* for a store: a store that keeps plain code too needs the same record and the same G2 bit, with no second owner to relink.

### 1.5 Type signatures

| Original | Unified |
|---|---|
| Keys print by bound and key (`ColTable at Vector{Vector{Float64}}`, piece 17); compiled code carries the key, not the whole type (the 3,553-character integrator, `design.md:19`); no hidden type parameters; machinery frames hidden. | **Gained:** a method at a trait is a Julia method with Julia's signature (F18); no `Kept{X}`, `Compiled{X}`, entry or worker names in traces (the prototypes' review §2). **Kept:** a key prints as the key where keys exist (traits §15; `TraitKey` visible, decision 12). **Changed:** an open method is compiled per type, so its frames carry the member's full type, as Julia's do today; with keys Optional, every method does. Neutral for the ports (E-263), a loss for a library whose members carry large types (a solver's problem type with its callbacks: `keys-plan.md:33`), unless it wraps them `Dynamic{X}`. |

Confidence: high on what is written; the ports' census is one data point on code built for the old design.

### 1.6 Error messages

| Original | Unified |
|---|---|
| `ImplementError` at the declaration; definition checking at archetypes before any type conforms; `TraitBoundError` at the call naming the bound; hints on `MethodError`; the SciML error cases not rerun (`other-languages.md:290`). | **Kept:** `ImplementError`, `OwnershipError`, `TraitUseError` with every use listed, `PirateError` (traits §11.3). **Changed:** `TraitBoundError`'s cases become `MethodError` with hints (F14; traits §11.4), a wrong result `TypeError` on return; a family member that fails its check is a member that raises at first use (F10). Detection moves later in two places: a non-member at a trait argument is Julia's `MethodError` (the hint carries the diagnosis), and a `Callable` whose result is wrong raises at the call, not at a first-call check. **Gained:** the classification report names each use outside the contract with its line (`compiler.md:497–505`). |

Confidence: moderate. The hints are now load-bearing for the goal; they are Planned (W-103) with no gate. Inferred: the loss is small if N9 gates the hints on the SciML error cases, which no design has rerun yet.

### 1.7 AOT and closed programs

| Original | Unified |
|---|---|
| `--trim` compiles plainly; `verify_main` lists the targets (`Dynamic` members, `Callable` signatures, entries); a 4.07 MB TraitMakie binary on the previous prototype; three risks and the annotations A–E, deferred (`explorations/aot-under-facts.md:53–62`, `:79–113`; open issues §1.2). | **Kept:** `--trim` plain (facts §13.3); `verify_main` with targets per trait and `Callable` (traits §16); the `nortsite` bit that annotation A rests on (`compiler.md:73–84`). **Gained:** less machinery to trim: no entries, workers, `_facts_call`, `CLOSED_WORLD` slow paths (the first binary's four fixes were all TraitWorld's, `aot-under-facts.md:126–137`); dispatch is Julia's, so trim's reachability works unchanged. **At risk:** memberships are run-time data on `TypeName`s (fine in a closed world), the member hook's checks must be resolved at build for pattern members, `Callable`'s method-table query needs the table present (trim keeps it); the table of a call's targets falls back to the dynamic call in a trimmed program (`compiler.md:578`), so `verify_main` must list the members' targets as today. Nothing measured on either design. |

Confidence: moderate; nothing here is built or measured in either design, and the mechanisms the draft removes were the ones that bit in the one binary built.

### 1.8 Machine-code caches that use G1/G2

Covered in §1.4. In one line: the record and the identities are the right door and are in the draft; G2's scope narrows where facts code rests on plain code that is not fully typed, and the slot plus the G2 bit on every CodeInstance recover most of it. The second owner's facts copies of Base, which made that plain code facts code and cacheable, are the part no door recovers without a per-method second policy (M2).

---

## 2. Each loss or risk: recoverable, at what cost, and what to keep open now

| # | Loss or risk | Recoverable? | Cost later | Needed now (the door) | Class |
|---|---|---|---|---|---|
| 1 | G2 for facts code resting on plain code (§1.2; E-261) | Mostly: the slot keeps result edges; the G2 bit keeps fully typed plain callees; the boundary flag gives a plain method a facts copy on demand | W-101 (planned); a sentence in §3.2 and §9; who sets `:facts_boundary` on Base's methods is a policy question (upstream, or the test bed) | the slot's write points (compiler §3.3); the G2 predicate computed for *every* CodeInstance, not only facts ones (§3.2 says "a CodeInstance"; make it explicit); keep-compiled keyed on the G2 bit (§9); the boundary flag's "up to one CodeInstance per policy" semantics (§2.3) | recoverable at no cost now, if the three sentences go into the draft |
| 2 | "A membership invalidates nothing" (C-18 until N7) | Yes: guards (N7), or the stopgap narrowed as the design if its volume is small | N7 is the largest compiler piece after keys; the narrowed stopgap is small | membership cells and positive memberships as record kinds (§3.1, in W-100); `jl_could_join` (§4.7, built); the set-to-methods index (§5.1, built) | recoverable later; decide by measurement (X2) before building either |
| 3 | Keys: exclusion of undeclared parts from compiled code (§1.5) | Yes: `TraitKey`, the `nospecializeinfer` path, the calling convention (N5) | N5, the second-largest piece | the contract on the `TypeName` with fields and receiver (§4.1, W-98); the entry's receiver and forwarding field (§4.2, W-98); the classification per argument (§6.7) delivered with `bounded`, not with keys | recoverable at no cost now, if the classification moves from N5 into N1/N4 |
| 4 | Plain code's dispatch and subtyping cost (§1.1, §1.3) | Partly: reachability pruning (P-28), BaseTraits without trait methods on Base's functions (M6's proposal), the typemap's typename index extended to memberships (review M1, option 2) | small to moderate | a gate per mechanism at W-98/W-99 with a bound of a few percent on dispatch microbenchmarks, not 10 % on suites | recoverable only if measured now: a regression found at W-104 is spread over three stages |
| 5 | Keep-compiled's facts copies of Base in images (188 → 17 ms per first `@implement`; §1.2) | Yes, as 1: plain G2 code kept in images | one rule in §9 | same as 1 | recoverable at no cost now |
| 6 | The facts-keyed cache's validation by origins alone (§1.4) | Partly: by the G2 bit; otherwise Julia's edge validation (open issue 80) | none beyond 1 | the record complete on both policies (§3.1) | recoverable; the store note's revision 2 already assumes edge validation |
| 7 | `Callable` memberships as a method-table query inside `jl_subtype` (§1.3) | Yes: derived entries, lowered by the member type's method definitions, read as entries | small, if decided before N8 | nothing; P-7's mechanism is mine (decisions §9), the user decided dispatch by signature and `S` on return | recoverable only if changed now: a query inside subtyping shapes the type cache and the leaf cache |
| 8 | Error detection later at non-members and `Callable` results (§1.6) | Yes: hints (§11.4), a definition-time check of a call's arguments where the function's methods are known | small | a gate for the hints on the SciML error cases (N9) | recoverable at no cost now |
| 9 | Upstreamability: the type system's changes (`subtype.c` +866, `gf.c` +1,208 before keys, guards, `All`, `attributed_call`) against the original's four general mechanisms (`state.md:50–56`) | Partly: the facts policy (W-100) is independent of the type system (work plan: "N4 needs neither W-100 nor N5"; W-100 needs neither W-98 nor W-99 in substance) | none | W-100 built as a patch series on vanilla plus the facts policy, mergeable without the type system (W-19's spirit) | recoverable at no cost now |
| 10 | The simplification's size: the library shrinks (about 6,000 lines of TraitWorld, the exploration's upper bound), Julia grows (type system, dispatch, keys, attribute, guards, intersections, two new hooks, a member hook) | not a loss to recover; a cost to state | — | the draft's compiler.md lists 11 parts (`:17–29`) against the current reference's 7 chapters; the honest comparison is lines of Julia changed per goal, after W-99 and after N7 | state it in `design.md`'s rationale |

Not recoverable without giving up a simplification: none found. The one that comes closest is 1: the second owner's facts copies of *every* Base method reached from facts code can return only as the test bed `all` (Base wholly by facts, with its tails: BaseBenchmarks 1.037 geometric mean, 27.8× on containers of `Any`) or as boundary flags on chosen Base methods, which is the second owner by another name, per method. The draft's one-CodeInstance rule is the simplification; the boundary flag is its escape hatch, already in the draft.

---

## 3. What Swift, Rust and Mojo teach, per trade-off

Each item: where they made the same choice, what it cost, what they built later, whether it worked. Sources: the research file (`record/other-languages-research-2026-10-16.md`) where it has them, else the primary source fetched for this review (listed at the end).

**One copy against per type (trade-off 3, keys and `Dynamic{X}`).**
- Swift compiled generics once with dictionary passing and specialization as an optimization (Generics.rst, research §6); the price is cliffs: unspecialized code "about 2 orders of magnitude slower than the specialized version" (SE-0460, verified). The fixes came in three steps, each a retrofit: `@inlinable` exports the body "as part of a module's interface" so clients can specialize (SE-0193, verified); `@specialized` lets the author emit specializations the generic entry redispatches to by *exact* type, "no semantic effect, only a change in performance" (SE-0460, verified); prespecialized generic metadata removes `swift_getGenericMetadata` calls, metadata only, with uniqueness across modules handled by a runtime registration (the forum pitch, verified). Each worked for its case; none removed the cliff.
- Rust compiles per type in the using crate: "all monomorphized functions from Crate A appear within a single codegen unit for Crate B" (rustc dev guide, monomorph, verified). The cost is compile time and duplicates: "up to 30% of the LLVM definitions" could be avoided (PR #48779, verified). Sharing was retrofitted and failed in the optimized case: `-Zshare-generics` is on for opt-levels `No`, `Less`, `Size`, `MinSize` and incremental, off at `-O2`/`-O3` because "it will impede optimization somewhat, since fewer functions can be internalized" (PR #48779, verified); polymorphization was removed (MCP 810, research §6).
- Mojo compiles per parameter value at compile time ("creates a concrete version … for each unique parameter value"; "If the compiler can't resolve all parameter values to constant values, compilation fails", the parameters manual, verified) and has no dynamic position: "Existentials / dynamic traits" is not started (the roadmap, verified).
- **The lesson for us:** sharing retrofitted into a compiler fails; sharing by a language-level erased type (`dyn`, `any`, `Dynamic{X}`) survives. The draft's `Dynamic{X}` is `dyn`; keys are Swift's `@specialized` middle (code per shape with exact redispatch), and like `@specialized` they are worth having where a library wants it, not as the default. E-263 says the ports do not want them today. Keeping them Optional with the doors of §2 row 3 is the Swift-shaped answer; the Rust-shaped warning is that compile time per type is what sessions pay (§1.3), so the erased default (`first_seen` → `Dynamic` at the prompt, `Callable` `Dynamic`) must stay the default, as matklad's "prefer `&dyn Fn()`" says for Rust (research §7).

**Caches across builds and sessions (trade-offs 1, 5, 6).**
- Rust's incremental compilation fingerprints every query result (128 bits) and marks dependents green when a re-run gives the same result (the red-green algorithm; the dev guide, verified); across crates everything hangs on the SVH, which "includes all upstream crate hashes", so any upstream change invalidates the whole downstream artefact (libs and metadata, verified); within a crate the fingerprints are "the main reason why incremental compilation can be slower than non-incremental compilation" (verified). The LLVM backend is not in the query system: a codegen unit is recompiled whole if its node is not green.
- Swift's library evolution keeps clients valid across library versions by indirection: client code "must be more conservative" and "cannot be freely reordered" (LibraryEvolution.rst, verified); an `@inlinable` body becomes part of the contract: it "must be prepared to interact with multiple versions of the same function" (SE-0193, verified).
- Mojo caches "non-elaborated code" per package, "tied to the exact version of the compiler that produced it", with machine code only "after it's imported into a Mojo program" (packages.md, verified): no cache of machine code across builds at all.
- **The lesson for us:** a result edge is a resilient (non-inlined) call, a code edge is an `@inlinable` one. Swift pays the indirection everywhere; the slot pays it only at result-edge sites, which is cheaper than Swift's model and sounder than the exploration's first version (the build review's H1). The record's "method plus a digest of its lowered code" is Rust's fingerprint at the right grain; Julia's build ids are Rust's SVH, the coarse key the facts-keyed cache was designed to escape (E-194: 86–90 % lost on one foundational package's update by build ids; E-195: 0 by fingerprints). The G2 bit is what no other language has: a per-entry statement of *who* can invalidate it. It is worth computing for plain code too (M1), since Rust shows that fingerprinting everything costs more than it saves unless the cut-off is by content.

**Erasure made implicit (trade-off 3's other half: `first_seen`).**
- Swift's bare protocol name as an existential "had risen to the level of active harm" because it hid boxing and dispatch (SE-0335, research §7); `any` made it explicit; Rust's `dyn` likewise (RFC 2113).
- **The lesson:** `first_seen`'s step 5 (a value from the prompt is `Dynamic` in a trait module, traits §7.5) is implicit erasure. Its cost is bounded by the split (1–5 ns per element within four members, E-164), which Swift did not have, so the harm is smaller. But fully typed mode counts such operations "as declared, not as faults" (traits §14, `:1041`), so nothing reports them. Mitigation M9.

**Memberships at run time and what a late membership does to compiled code (trade-off 2).**
- Swift registers conformances at load and scans them on a cache miss, over 100 ms of launch time in large apps (research §4); retroactive conformances make the winner "indeterminate" (SE-0364). The draft's entries on the member's `TypeName`, not a global list, are the fix Swift reached for later (research §4, the dyld conformance cache, unverified there).
- No static language guards a compiled call against a later membership; HotSpot does the equivalent for class loading: it compiles against class-hierarchy analysis and *deoptimizes* dependents when a class loads (the build review's H1 notes the same for nmethod dependencies). That is C-18, not the guards.
- **The lesson:** the stopgap is a known, working design when the event (a membership) is rare relative to calls and the dependents are few. E-259 says both hold in the ports (7 sites in five sessions). The guards buy "invalidates nothing" as a theorem at the cost of the shadow query in every inference and cells on every `TypeName`. Measure the stopgap's volume first (X2); HotSpot's experience says a narrowed walk may be the design.

**`Callable` (trade-off 7).**
- Rust's `Fn` traits are built into the compiler and implemented structurally by closure types at compile time; Swift's function types are matched by signature in overload resolution (the draft says so itself, `compiler.md:597`). Both are static: neither consults a method table at run time inside subtyping.
- **The lesson:** dispatch by signature is sound in both because the set of callable types is closed at compile time. In Julia it is open, so the membership must be world-stamped like any other. The draft's answer (a memoized query inside `jl_subtype`, `compiler.md:587`) puts `hasmethod`, which itself runs `ml_matches` and `jl_subtype`, under subtyping's recursion and the type cache. Derived *entries*, lowered by the function type's method definitions (the work plan's option (b), `:399`), keep the user's rule and keep subtyping free of method-table queries. It is a change to a choice marked mine, not to the user's.

**Intersections (`All`).** Swift has `P & Q` (protocol composition, SE-0095, not fetched for this review); Rust's `dyn A + B` allowed only auto traits beside one trait for vtable reasons, relaxed by trait upcasting (not fetched). Our table is keyed by the value's type, not a vtable, so Rust's restriction does not bind. The cost is in subtyping's normal form; P-21 (declared supertypes only) is the right guard against world-dependent type identity. No lesson beyond: keep `All` out of the first slice (the work plan's S3 does).

---

## 4. Mitigations, ranked by value against cost

| # | Mitigation | Where it belongs | The result that shows it is needed |
|---|---|---|---|
| M1 | **The G2 predicate on every CodeInstance, and keep-compiled keyed on it:** an image keeps plain code reached only dynamically from facts code when its record satisfies G2; a store admits plain entries by the same bit. | draft compiler §3.2 ("when a CodeInstance is finished", say "of either policy") and §9 (one rule); W-100 and N3 | X5: the share of today's kept facts copies of Base whose records are G2 as plain code; and the first `@implement`'s inference time on the unified build without it (188 against 17 ms, julia-changes §2) |
| M2 | **The slot built (W-101) as planned, and the boundary flag named as the recovery for Base's generic containers:** facts §2.2's scope paragraph cites E-261 and names `:facts_boundary` as the per-method second policy. | facts §2.2, compiler §2.2; `design.md` §2.6 states the loss with E-261's numbers; `alternatives.md` gains "the second cache owner, replaced by one CodeInstance per MethodInstance and policy" | X1: the time to recompile the lost facts callers per session of loads; above about 0.2 s, boundary flags on the Base methods the census names |
| M3 | **Measure the stopgap's volume on the ports' sessions before N7;** if small, guards become Optional and the stopgap, narrowed to the member's typenames, the design; the cells stay record kinds. | W-99's gate (the volume row, already there) extended to the forks' and ND's sessions; the work plan's S9 decided by it | X2: a membership that lowers more than about 1 % of the live cache or invalidates any CodeInstance in a loop keeps guards a stage |
| M4 | **`Callable` memberships as derived entries,** lowered by the member type's method definitions; subtyping reads entries only. | compiler §7.4 (a mechanism change to P-7, mine); N8 | X6: the memo's miss cost per new closure type, and a reentrant case (a closure whose body dispatches at a `Callable` bound) |
| M5 | **The classification per argument delivered in N1/N4 as a report** (`bounded` needs it; keys need it later), not in N5 with keys. | the work plan's N1/N4/N5 scopes; traits §7.3's status line | E-264's census reproduced on the unified build with the compiler's classification |
| M6 | **Plain-code regression gates at W-98 and W-99:** dispatch-miss microbenchmarks for `getindex`, `iterate`, `length` with BaseTraits' methods at open sets installed, `<:` and `isa` against a non-member with k entries on the chain, the quick BaseBenchmarks subset, each within a few percent of vanilla; BaseTraits declares no trait method on a Base function where it is unreachable (the prototypes' review M6). | W-98's and W-99's gates (the 10 % bound stays for the suites); lowering §10 | X3, X4 |
| M7 | **W-100 as a patch series independent of the type system,** buildable on vanilla, so the facts policy can go upstream on its own. | the work plan's W-100 row; W-19 | none: a property of the branch layout |
| M8 | **Hints gated on the SciML error cases** (`experiments/errors/`), rerun under the unified build. | N9's gate | a case whose unified message is longer or later than the prototype's |
| M9 | **A report of implicit erasure:** arguments made `Dynamic` by `first_seen`'s step 5 in a method, listed per module (`detect_dynamic_fallbacks(mod)`), beside `detect_unused_casts`. | traits §14 and compiler §6.9; N6 | a port's hot path found `Dynamic` by the fallback (L9 of the prototypes' review names `ODEProblemTrait`) |
| M10 | **Memberships in images (N3) before any package declares one.** Already the plan's order; endorsed. | the work plan's N3 | the two-package session in a fresh depot |

---

## 5. Experiments that settle the uncertain trade-offs early

In the registry's style; none run. Each on today's patched build (julia-1.13 00dcc9994c) unless it names the unified branch, in the product setting, strict mode off, one run where it counts and two where it times.

| ID | Question | Method | The result that changes the plan |
|---|---|---|---|
| X1 | What does G2's narrower scope cost in time per session of loads? | E-261's lost sets (the 457 and 780 facts callers of invalidated plain callees, `experiments/unification/s0a/out/`) joined with a session's compile counter per MethodInstance (E-233's harness): the sum of their inference and codegen times; separately the share that the slot keeps. The forks' session and the `g2all` session. | more than about 0.2 s per session, or any port's hot path among them: M2's boundary flags for the named Base methods, or Base's containers of `Any` by facts in the product image (`fast-loads.md:44`), measured as a third setting |
| X2 | How much does the stopgap invalidate at a membership on a real port? | On the unified branch after W-99: the forks' session and ND's with the volume log of C-18 (`src/datatype.c:288`): per `@implement`, cache entries lowered, CodeInstances invalidated, any in a loop (E-259's `sites.tsv` as the loop list). Also the conservative shapes: a `Vararg` and a `Union` position at a set. | any CodeInstance in a loop, or more than about 1 % of live entries at one membership: N7 stays Planned; else guards Optional, the narrowed stopgap the design (S9), facts §10's "invalidates nothing" restated as "invalidates what it changes" |
| X3 | What do methods at open sets on Base's hottest functions cost plain code? | Vanilla against `unified`: a `getindex`, `iterate`, `length` method at an open set with 1, 10 and 100 members installed; a dispatch-miss microbenchmark over 50 concrete container types; the quick BaseBenchmarks subset (148); E-262's four suites. | more than about 3 % on the microbenchmark or 2 % on the subset: BaseTraits' operations off Base's functions (M6), or the typename index extended (review M1 option 2) before W-99's gate |
| X4 | What does `jl_subtype` cost with many entries on a common chain? | Vanilla against `unified`: `S <: X` and `isa` for a member and a non-member, with k = 1, 10, 50 entries on `AbstractVector`'s chain (BaseTraits' shape), with and without reachability pruning (P-28); a set-in-set chain of depth 3. | a non-member's `<:` above 2× vanilla's for an unrelated pair: pruning and memoization into W-98's gate, not N5's |
| X5 | How much of the facts copies of Base that images keep today would an image keep as plain G2 code? | In TraitWorld's, TDE's and TraitMakie's images (`experiments/factscompiler/w89/`-style census): the facts owner's CodeInstances of Base methods; for each, whether every edge is at a concrete signature (the G2 bit as plain code); the share and the compile time of the rest (9892bfc288's 188 ms as the ceiling). | under about half kept: M1 alone does not recover the first `@implement`'s time; M2's boundary flags are needed for the named methods |
| X6 | Is `Callable` by a method-table query inside subtyping safe and cheap? | Plain Julia emulation on today's build: a dispatch at a `Callable{A, S}` bound through a memo keyed by (function type, `A`) with world ranges, n = 1,000 closure types; miss and hit cost; the reentrant case (a closure whose body dispatches at a `Callable` bound inside the query). | a miss above the entry's cost today (E-256's 80–96 ns), or any reentrancy failure: M4 (derived entries) before N8 |
| X7 | How much of the prototype's session time rests on the mechanisms the first slice defers? | The first slice (W-98, W-99, N1) on the two workloads against the prototype's numbers for the same shapes (a `Column` kernel, an `ODEAlgorithm` solve): session, first call, steady state. | a gap above 2× says the "speed later" mechanisms are not optional and their compiler cost belongs in the simplification's ledger; within 1.2× says the slice's design carries most of the value |

---

## 6. What the unification plan should look like from this perspective

**Identify and measure first, in this order:**
1. **The second owner's loss** (X1, X5), before W-100 writes "one CodeInstance per MethodInstance and policy" into code. The number decides whether M1 and the slot suffice or boundary flags on Base are needed, and it belongs in `design.md` §2.6 as the stated cost of the simplification, with E-261.
2. **The stopgap's volume** (X2), before N7 is built or made Optional. This is the cheapest decision with the largest compiler saving on the table.
3. **Plain code's cost of the type system** (X3, X4), as gates of W-98 and W-99, with bounds of a few percent on dispatch and subtyping microbenchmarks. A regression found at W-104 cannot be attributed.
4. **`Callable`'s mechanism** (X6), on paper and by emulation, before N8; it changes nothing the user decided.
5. **The first slice against the prototype** (X7), so that the premise's demonstration is read with its deferred mechanisms' value in hand.

**Simplifications worth their cost** (each removes something the evidence priced):
- the value is the value (F4): no entries, workers, views; E-256's 32–45 instances per held type and T-94 go;
- one dispatch (level 2): L-3, L-50, open issue 135, and the subtrait encoding that rejected 237 of DataFrames' image CodeInstances at load (E-238);
- storage as Julia's (F7) and `Dynamic{X}` as a struct: the seven-column table and the kept forms go, at no measured cost (E-257: raw members cost no more than `Kept`);
- one CodeInstance per MethodInstance and policy: open issue 125's 0.24–0.34 s per session, *provided* M1 and M2 keep the plain code it rests on cached and the loss is stated;
- `@trait_module` as a statement in an ordinary module (T-81): Revise;
- the record complete with stable identities: the store's door, better than the original's owner-keyed one.

**Simplifications to hold back, or to take in a different form:**
- **Keys:** Optional, not removed (open issue 145's recommendation stands), with the classification, the contract and the receiver kept as the door (§2 row 3). The Swift and Rust record says the per-shape middle is wanted later by exactly the libraries that carry large types.
- **Guards:** decided by X2, not by the work plan's S9 on paper.
- **`Callable` inside subtyping:** change the mechanism (M4).
- **`first_seen` as silent erasure:** keep the user's fallback, add the report (M9).

**Where the draft should change** (each a sentence or a status line):
- compiler §3.2: the predicate computed for every CodeInstance; §9: keep-compiled by the G2 bit; §2.2 or facts §6.1: the boundary flag named as the per-method second policy;
- facts §2.2's scope paragraph: cite E-261 and name the loss in numbers; the evidence's slot row already has them (`design/evidence.md:28`);
- compiler §7.4: derived entries instead of a query inside subtyping (P-7's mechanism);
- compiler §5.6 and §5.5: status "Planned; Optional if X2 says so", with the narrowed stopgap stated as the alternative design, not only as C-18;
- traits §14: operations made `Dynamic` by the fallback are reportable, not "declared".

**Where the plan should change:**
- the work plan gains a section "trade-offs and their gates" with X1 to X7 placed before the stage each decides (X1, X5 before W-100; X2 before N7; X3, X4 in W-98/W-99's gates; X6 before N8; X7 at the first slice's end);
- N1/N4 take the classification report from N5;
- W-100 is laid out as a patch series on vanilla (M7);
- W-104's session gate is kept, and a per-slice comparison against the prototype's shapes is added (X7);
- `design.md` §2.6 and `alternatives.md` state the second owner's replacement and its measured cost, so that the rationale carries the trade-off and not only the references' rules.

---

## Sources fetched for this review (2026-11-06)

- Swift: [SE-0193, cross-module inlining and specialization](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0193-cross-module-inlining-and-specialization.md); [LibraryEvolution.rst](https://github.com/swiftlang/swift/blob/main/docs/LibraryEvolution.rst); [SE-0460, explicit specialization](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md); [generic type metadata prespecialization (forum pitch)](https://forums.swift.org/t/generic-type-metadata-prespecialization/31659).
- Rust: [incremental compilation in detail](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html); [libs and metadata](https://rustc-dev-guide.rust-lang.org/backend/libs-and-metadata.html); [monomorphization](https://rustc-dev-guide.rust-lang.org/backend/monomorph.html); [PR #48611 / #48779, share-generics](https://github.com/rust-lang/rust/pull/48611).
- Mojo: [packages (`.mojoc`)](https://github.com/modular/modular/blob/main/Mojo/docs/site/manual/packages.md); [parameters](https://mojolang.org/docs/manual/parameters); [the roadmap](https://mojolang.org/docs/roadmap).
- Every other claim about another language cites `record/other-languages-research-2026-10-16.md` or `design/other-languages.md`, which carry their primary sources. SE-0095 and Rust's trait upcasting are named from memory and marked not fetched.

---

## Addendum (2026-11-06, the main session): where the findings went

- The trade-offs, the experiments X1 to X7 with the stage each must precede, the stage changes and the draft changes: [the work plan's proposal](../plans/2026-11-06-work-plan-under-the-draft-reference.md) §8. The draft changes are applied when the user adopts that plan.
- Keys as Optional: open issue 145 (the user's). Guards against the stopgap: the work plan's weak point 13, decided by X2 (the user's).
- Verified in the main session: the boundary flag's "up to one CodeInstance per policy" (draft compiler §2.3), 9892bfc288's 188 against 17 ms (`design/julia-changes.md:36`), E-259's 7 guard sites none in a loop, the synthesis plan's 2,898 cache entries.

## Addendum (2026-11-06, later, the main session): the plan adopted

- The user (2026-11-06): "Adopt, keys as optional is approved. Run the X now".
- Taken into the draft:
  - M1 and M2 as P-31;
  - M4 as P-30, after X6;
  - M5 in W-109;
  - M7 in W-100's scope;
  - M9 as P-32.
- X1, X5 and X6 were run as E-265 to E-267 ([the plan](../plans/2026-11-06-work-plan-under-the-draft-reference.md) §8.1):
  - X1 put trade-off 1 at 0.2–0.3 s per session with the slot, on a package's own plain methods rather than Base's;
  - X5 put M1 at 50–92 %;
  - X6 met its criterion.
- The user's point that guarantees matter to the ecosystem beyond what a measurement shows bears on this review's §6 ("Keys: Optional, not removed"; "Guards: decided by X2"). It is open issue 146.

