# Review: is the current design internally consistent? (fresh eye, 2026-10-17)

Scope: `writeup/README.md`, `notes/1-overview.md`, `2-design-choices.md`, `4-details.md`, `3-wrapping.md`, `decisions.md`, `open-issues.md`; checked against `explorations/wrapping-by-facts.md`, `strict-mode.md`, `aot-under-facts.md`, `julia-support.md`, session notes 24–26, `TraitReport/README.md`, `experiments/facts/README.md` and `TraitWorld/src` (main 6bcca9f). Code was read, not run. "Verified" below means read in source or a recorded measurement; everything else is reasoning.

## Summary verdict

The core of the design after wrapping by facts is coherent: rule 1 (concrete facts, nothing skipped), rule 2 (the boundary translates), keys, `Dynamic{X}`, pirates followed by default, builds compile the plain call. The notes, the decision register and the prototype agree on these, and the measurements support them.

Four things do not fit together, and each touches a headline claim:

1. **Concreteness** is "opt-in per trait" in the notes and the register, but unconditional in the prototype, stricter there than any text says, and it was used as an unconditional fact to justify the TraitTables/TraitCSV decision.
2. **Lemma O and the stakeholder definition** are misstated. The strict-mode exploration and the prototype use a different (correct) notion. As written, the notes' derivation of "an unrelated load never changes compiled trait-world code" is false for abstract-type methods and their package extensions.
3. **Facts at non-public functions** (session 26) breaks the premise of Theorem 2, is justified by a reading of rule 3 that rule 3 does not state, is implemented so that Base-internal calls from Base code are still facts, and is absent from the notes. It also undoes the strict-mode guarantee as written.
4. **Overrides refused after a conformance** (keys design) and **"the default decision is a fact that recompiles"** (facts design) are both adopted and prescribe different behaviour for the same event.

The rest is stale text and numbers: a dozen places where the pre-facts design survives outside marked history, and the register contradicting itself in four rows. None blocks work, but together they make the register unreliable as a register.

## Findings, ranked

### 1. Concreteness: opt-in in the text, required in the prototype, required in a decision's rationale — significant

**Locations.**
- Opt-in: `1-overview.md:40` ("Optionally, a trait guarantees…"); `2-design-choices.md:32`, `:420` (prediction 11: "concreteness is opt-in per trait"); `4-details.md:248` ("It is opt-in… the conforming type may hold abstract fields the trait does not declare"); `4-details.md:315` ("for a trait that requires it"); `4-details.md:707`; `aot-under-facts.md:14,42` ("where their traits require it"); `open-issues.md:25` (abstract keys in a trait that does not require it); `decisions.md:15` ("A concreteness guarantee is opt-in per trait… Prototype: yes").
- Unconditional: `4-details.md:392` ("Concreteness: field types … abstract in no other way… `Series{Real}` is refused at the entry"); `TraitReport/README.md` form (b) ("A `DataFrame` cannot conform to a trait, since it is not deeply concrete"); session note 26 line 54; the rationale of `decisions.md:100`.
- Prototype (verified): `TraitWorld/src/implement.jl:424` (`deep_concrete(R) || throw(… "cannot implement a trait")`), `:442–443` (forwarding field), `:1030` (one-line form). `deep_concrete` (`implement.jl:66–85`) recurses into **every** field of the implementing type, declared or not; `Dynamic` and `Erased` are exempted. `trait.jl` offers no way to opt in or out.

**Why inconsistent.**
- The register marks an opt-in as prototyped; the prototype has no opt-in.
- The prototype's check is stronger than the design's own statement: a type that implements the operations itself and holds an undeclared `Any` field (a `Dict{Symbol,Any}` of attributes, say) is refused, although `4-details.md:248` says exactly that is allowed. Under keys the worker is compiled for the implementing type, so undeclared fields do not enter the compiled code.
- "A `DataFrame` cannot conform" therefore follows from the prototype, not from the design as written. The user's TraitTables decision was argued from it. (The redesign has an independent rationale: column operations on `Vector{AbstractVector}` are run-time sites into native code that loads invalidate; `Vector{Dynamic{Column}}` dispatches to policy-compiled per-type workers. That argument is not the one recorded.)
- Pay-off 3 (`1-overview.md:97`, "An abstract type that reaches a hot loop is reported when the package is built") and "trait-world dispatch is closed by construction" (`aot-under-facts.md:20`) hold only for traits that require concreteness **and** modules that opt into concrete mode (`4-details.md:167`). Two opt-ins, stated as one unconditional pay-off.

**What the design requires.** Nothing in the facts proofs (G1, G2) needs concreteness; an abstract key gives run-time sites, which are sound. Concreteness serves pay-off 3 and AOT closure only. So opt-in is coherent, but then the pay-offs must be stated conditionally, and the prototype must implement the option.

**Resolution.** Decide one of:
- (a) required by default with a per-trait opt-out (`@trait … abstract_ok`), matching the prototype and the pay-offs as stated; then fix `1-overview.md:40`, `2-design-choices.md:32,420`, `4-details.md:248,315,449`, `open-issues.md:25`, `decisions.md:15`;
- (b) opt-in as written; then implement it, restrict `deep_concrete` to the key (implementing type `isconcretetype`, declared fields' types deep), and re-state the TraitTables rationale on the invalidation argument.
In either case restate the "cannot conform" sentences in `TraitReport/README.md` and `decisions.md:100`.

### 2. Lemma O and "stakeholder" are misstated; the derivation of G2 in the notes does not go through as written — significant

**Locations.** `4-details.md:22`, `:38` ("A method defined by a package that is not a stakeholder in every signature the method applies to is a pirate"), `:54–57`, `:102` (Lemma O); `1-overview.md:75–77`; `3-wrapping.md:142`; `wrapping-by-facts.md:73`. Against: `strict-mode.md:14` ("An abstract type counts, so `Base.length(::AT)` by AT's owner is no pirate even where it wins at another package's subtype"), `strict-mode.md:17`, session note 25 line 74 ("Checking ownership of the *method* (not of the fact's signature) is needed"); prototype `ownership.jl:205–217` (`owned_method`: the definer owns the function or a type **as written in the method's signature**, per Union alternative).

**Why inconsistent.**
- Take `f(::AbstractFoo)` defined by B, the owner of `AbstractFoo`, applying at the concrete signature `s = f(ConcreteFoo)` with `ConcreteFoo` owned by C. By `4-details.md:38` read literally ("in every signature the method applies to", stakeholders = owners of the types *in s*), B's method is a pirate. That cannot be intended: every method on an abstract type would be piracy. The prototype and `strict-mode.md` read it the other way (types as written). The notes need that reading too.
- With the correct reading, Lemma O as stated ("a non-pirate that applies at a concrete `s` is defined by a stakeholder of `s`") is false: B is no pirate and no stakeholder of `s`. The load-order argument survives for B itself, because B is loaded before `ConcreteFoo` can exist. It does not survive for **B's package extension** triggered by an unrelated package D: a legal method of B's at a signature without D's types changes a fact of code compiled before D loaded. `strict-mode.md:121` (§2b item 3) knows this; `1-overview.md:77` ("So an unrelated load never changes compiled trait-world code"), `4-details.md:72,113` and `3-wrapping.md:137–145` do not.

**Resolution.** Define stakeholders of a signature `s` as the owner of the function and the owners of every type that a type in `s` is a subtype of (also as a parameter). Restate Lemma O and Theorem 2 with that definition, and add the extension case as the one named exception (with the strict-mode rule of §2b item 3 as its remedy). Align `4-details.md:38` with `ownership.jl`.

### 3. Facts at non-public functions: outside the rules, inconsistent with rule 3, Theorem 2 and strict mode — significant

**Locations.** `decisions.md:98` (adopted, s26, "extending another package's non-public function counts as piracy (rule 3)"); `open-issues.md:13–16`; `facts.jl:89–107` (verified). No occurrence of "public" in `notes/` (grep). Rule 1: `4-details.md:78–81`, `3-wrapping.md:91` ("At any other call, it records nothing"). Theorem 2's premise "whose facts are all concrete": `wrapping-by-facts.md:67`, `3-wrapping.md:137`. Rule 3: `4-details.md:96–101`. Strict mode: `strict-mode.md:9–11` (refuses only at **concrete** fact signatures), `:27` ("the only definitions that invalidate trait code are its stakeholders'").

**Why inconsistent.**
- Rule 1 and the Terms section still say every non-concrete call is a run-time site. The adopted rule records facts at abstract signatures of non-public functions. The notes do not mention it.
- The rationale needs "extending a non-public foreign function is piracy". Rule 3 says a method is no pirate if the definer owns **a type** in it. `OffsetArrays.jl` defining `Base._some_internal(::OffsetArray)` is legal under rule 3. The measured consequence (`TraitReport/README.md` row 7: 5.3–5.7 s against 1.7 s with the rule off; session note 26 line 78) is exactly a non-pirate, non-stakeholder load invalidating trait code, which Theorem 2 says cannot happen.
- The scoping (`facts.jl:104`, equal module roots) excludes trait-module→Base calls but **not** Base→Base internal calls in Base code compiled under the policy. Those facts remain exposed to OffsetArrays, StatsBase and Unitful. The 1.7 s result may reflect which Base paths the report happens to touch; it is not a soundness argument.
- In strict mode, such a definition is neither refused (not a pirate; not at a concrete fact) nor prevented, so "trait-world code is never invalidated by a pirate" stays literally true while "only stakeholders invalidate" (`strict-mode.md:27`, the intended design §2b) becomes false.

**Resolution.** Either (a) amend rule 3 in `4-details.md` so that a method of a function that is not `public` in its owner's module is a pirate unless the definer owns the function, and exclude Julia (Base, Core, stdlibs) from the fact rule because its ecosystem does not follow that rule; or (b) keep the rule as an engineering measure for TraitWorld's own machinery only (its real purpose per `open-issues.md:13`) and say so, leaving rule 1 untouched for library code. In both cases write it into `4-details.md` rule 1 and `3-wrapping.md` "What the compiler records", and restate Theorem 2's premise. Decide before confirming the scoping with the user (`open-issues.md` §1.4, "to confirm").

### 4. Overrides after a conformance: "refused" (keys design) against "a fact that recompiles" (facts design) — significant

**Locations.** `4-details.md:200` ("A method of a trait's operation for a type whose conformance already serves that operation by a default is refused when it is defined… Plain Julia would call the later method, so accepting it would break identical or error"); `decisions.md:35` (adopted; prototype refuses at checkpoints); `implement.jl:584–606` (`check_overrides`, `_refuse_overrides`, verified). Against: `4-details.md:80` ("`D(length, Tuple{T}) = default` is a fact"); `3-wrapping.md:90` ("so the owner adding `length(::T)` recompiles the code to the new method"); `wrapping-by-facts.md:25,65`; `3-wrapping.md:150` ("Nothing is refused at load").

**Why inconsistent.** Both are adopted and describe the same event with opposite outcomes. The justification at `4-details.md:200` is false under rule P: accepting the later method and recompiling is precisely what "identical or error" yields. Refusal is a choice (like strict mode), not a correctness need. A later override arriving in a package image would be a refusal at load, which `3-wrapping.md:150` says never happens.

**Resolution.** Choose: (a) follow rule P: the conformance's default decision is a fact; a later override by a stakeholder recompiles the conformance and the key changes; drop the refusal (and `check_overrides`); or (b) keep the refusal as a declared-API rule, remove the "identical or error" justification, and amend `3-wrapping.md:150` to name it as the one refusal besides strict mode. Update `decisions.md:35` either way.

### 5. The compiler policy: "package code" in the notes, "part of the platform" in the register — significant

**Locations.** `1-overview.md:187` ("The trait world's compiler policy … is package code"); `3-wrapping.md:181` ("The compiler policy is package code"); `4-details.md:12`. Against: `decisions.md:97` (adopted s26: compiled into the system image, frozen compiler world); `open-issues.md:12`; `julia-support.md:37` (piece 12 "larger than thought"; "the principled form: the policy's compiler as part of the platform").

**Why inconsistent.** The two statements lead to different upstream proposals: "first-class foreign cache owners" lets a *package* own a cache; "policy in the platform" puts the policy *into Julia*. Both are called the first proposal (`3-wrapping.md:189`, root `README.md` plan item 6). Related stale detail: `3-wrapping.md:184` says piece 10 is worked around with `@noinline` (about 5 ns); `julia-support.md:35` says piece 10 is implemented and the work-around dropped.

**Resolution.** State the adopted direction in `1-overview.md` "What it costs" and `3-wrapping.md` "What Julia must provide", and say what the package-level form is for (stock Julia, other interpreters). Refresh the piece list (10 done, 12 enlarged, 14–17 added).

### 6. Strict mode: status and definition contradict within and across documents — minor

- `1-overview.md:207` "strict mode, not built" vs `decisions.md:70` "yes: TraitWorld 7b328a5 (`src/strict.jl`), 32 tests" and root `README.md` ("strict mode (a prototype)").
- `decisions.md:69` defines strict mode as "outside pirates raise where they would win" (the `HiddenMethodError` mode) while `decisions.md:70` adopts refusal at definition and `decisions.md:72` records the raise mode as not pursued.
- `3-wrapping.md:166` says the refused method's package is "no stakeholder of that signature"; `strict-mode.md:14–17` and the prototype test ownership of the method (finding 2).

**Resolution.** Fix `1-overview.md:207` to "prototype; intended design deferred"; rewrite `decisions.md:69`'s clause; align `3-wrapping.md:166` with the method-ownership wording.

### 7. The register contradicts itself in rows written for earlier designs — minor, but four rows

- `decisions.md:91`: "TraitWorld's machinery is protected by the filter like a trait module… adopted … Prototype yes" vs `decisions.md:95` (filter removed) and `wrapping-by-facts.md:98–101`.
- `decisions.md:19`: "delegation by the owner only" vs `strict-mode.md:137–139` and `decisions.md:74`: delegates declared by "a curated list in TraitWorld, or the application", that is, claimed by a third party. Rule 3 (`4-details.md:100`) says "Ownership is never claimed". A delegate list is an opt-out the application owns; say so instead of calling it delegation by the owner.
- `decisions.md:20`: rule 4 as "compiled against its owners' view" vs `4-details.md:103–104` (rule 4 is now "a call sees the current world; where code lives"). "View" also means field offsets in `4-details.md:21`; the two senses collide.
- `decisions.md:15`: "opt-in … Prototype yes" (finding 1).

**Resolution.** Mark rows 91 and 20 superseded; reword 19; fix 15.

### 8. "Functions from the trait world" is undefined under wrapping by facts, and the notes and prototype disagree on it — minor

**Locations.** `4-details.md:489` ("Functions from the trait world are always compiled calls. Base's `abs2`, **any package's functions**, a trait module's own functions, and closures created inside a trait module are called directly"); `4-details.md:476`. Prototype (verified): `entry.jl:585` (`M === CompiledCall || _from_trait_world(f)`); `trait_module.jl:38–48` (`is_trait_world`: Julia, TraitWorld and trait modules only). A function from an ordinary package (`ForwardDiff.derivative`, a user package's function) is erased to a pointer under `DynamicCall`.

**Why inconsistent.** The Terms (`4-details.md:11`) define the trait world as modules plus compiled code, not as a provenance of values. Under layering "above/below" was clear; under facts it is not. The behaviour that matters is where the compiled-call worker lives (rule 4): compiling for a dependency's function can live in the library's image, compiling for a caller's cannot.

**Resolution.** Define the default in rule-4 terms: a function whose type is owned by a package the library depends on (Julia included) is a compiled call by default; any other is dynamic by default. Fix `4-details.md:489` and check `entry.jl` against it.

### 9. Dispatch tier "above `Any`, below every type" needs the language; the prototype cannot run the adoption example — minor

**Locations.** `3-wrapping.md:19–28` (`describe(t::ColTable)` next to `describe(x)`, "the old fallback"); `4-details.md:419`, `:425` ("The entry sits at `Any`"). Prototype: `trait_module.jl:529–531` errors when an untyped method of the entry's shape exists; the entry **is** the method at `Any`.

**Why inconsistent.** The notes present the tier as the design and the entry at `Any` as how it is done, in one section, without marking that the tier needs Julia piece 7 (`julia-support.md:69`). The adoption example cannot coexist with a user fallback at `Any` on the prototype.

**Resolution.** Mark the tier as language-dependent in `4-details.md:419` and `3-wrapping.md:19`, and state the prototype's restriction (no untyped fallback of the entry's shape).

### 10. `2-design-choices.md`: pre-facts statements outside the banner's list — minor

The banner (`:3–8`) names §5, §6, §7, costs 1, 2, 6, 8 and "Other options". Stale text elsewhere:
- `:25` and `:48` "owner or delegate"; `:127` "an implementation its wrapper's delegates write"; `:140` "owners and delegates";
- `:185` "Calls into unconstrained code are ruled out by layering" (§4; the current answer is `3-wrapping.md:80`, rule 2);
- `:360–366` cost 3: "Inward doors (eval, deserialization, reflection) are available only as declared calls";
- `:410–411` predictions 1–2 answered by "wrappers" and "calls upward, outward doors";
- `:334` (§9) "printing of trait-object types by bound is written but not yet run" vs `decisions.md:58` ("yes").

**Resolution.** Extend the banner's list or fix the lines; the note says it is to be revised.

### 11. Numbers that disagree between documents — minor

- Typed calls: `1-overview.md:198` and `4-details.md:705` "37–39 ns"; `4-details.md:615` and `decisions.md:96` "33 ns"; session 25 "33–36 ns" after piece 10.
- First calls: `1-overview.md:200–201` 55–60 ms and 87–97 ms; session 26 remeasure 32–37 ms and 62–65 ms.
- Operations on a `Dynamic` value: `4-details.md:629`, `2-design-choices.md:141,377` "20–80 ns" (a measurement of Julia's dispatch on boxed values); `open-issues.md:81` "about 900 ns (`keepsum`), mostly the dynamic operation" on the prototype. TraitTables rests on `Vector{Dynamic{Column}}`; per-column operations tolerate 900 ns, per-element ones do not. State the prototype number next to the design estimate.

### 12. E2 is presented as evidence about policy-compiled code; it was measured on native code before the policy — minor

`3-wrapping.md:154–158` ("The code compiled for them has 3,533 CodeInstances, 3,043 concrete facts and 207 abstract facts") under "Pirates / Measured". `experiments/facts/README.md:23–30` and `e12_closure.jl:1`: stock Julia, the demonstrators' native edge closure, session 23, before `FactsInterp`. Code under rule R has no abstract facts by construction. Say "measured on the native closure before the policy (E2, session 23)".

### 13. Housekeeping — minor

- `open-issues.md:3` "as of … (session 25)"; `:65` state "893f0bb, 343 tests" (session 26: 6bcca9f, 344); `:61` item 25 "views exclude modules under `Main`" (views are gone).
- `writeup/README.md:27` lists `runtime.md` with "the load filter" as "current".
- `3-wrapping.md:201` cost 5 names "piece 7 and piece 12" as the cure; session 26 found two other causes and two decisions (`open-issues.md` §1.3–1.4).
- `open-issues.md:134` (§5.4) already records the AD-tag sentence in `1-overview.md:178`; it is still there.

## What is consistent and solid

- **Rule 1 and rule P** (concrete facts; nothing skipped) are stated identically in `1-overview.md:64–70`, `4-details.md:78–82`, `3-wrapping.md:84–94` and `wrapping-by-facts.md:22–29`, implemented as `_fact_sig` (`facts.jl:49`) with the closure-kinds exception documented in both `3-wrapping.md:99` and `wrapping-by-facts.md:190`, and supported by g2all (0 of 7871 policy CodeInstances lost over twelve loads, both orders) and acceptance 16/16.
- **Keys, implementing type, forwarding, declared fields, `Self`**: the Terms, "Declaring a trait" and "How a type conforms" agree with each other and with `decisions.md` §Keys; representations and projections appear only as history in the notes (the prototype's internal names still use them, which `4-details.md:5` acknowledges).
- **Rule 2** survives the removal of layering intact: `3-wrapping.md:80` correctly identifies what is kept (no bare trait object to ordinary code) and why definition checking still holds.
- **`Dynamic{X}`** is treated as deeply concrete by the prototype (`implement.jl:72`), so the TraitTables storage `Vector{Dynamic{Column}}` is admissible as a declared field.
- **Pirates followed by default**: `1-overview.md:79`, `4-details.md:72`, `3-wrapping.md:147–152`, `decisions.md:69` and the prototype (piracy guard off on the policy path) agree.
- **Trait modules may not define pirates**: stated in rule 3 and checked at module definition (`trait_module.jl:606`).
- **AOT**: "builds compile the plain call" is stated the same way in `4-details.md:686–692`, `aot-under-facts.md`, `decisions.md:76–77` and `1-overview.md:93`; risk 1 was found and fixed; pay-off 2 is restated consistently.
- **Strict mode as refusal at definition** is internally consistent with G1 (a refused method does not exist for plain Julia either), and its prototype measurements are recorded with limits (direct callers only).
- The deferred items (intended strict mode, AOT annotations, binaries) are marked the same way in `decisions.md`, `open-issues.md` §1 and the explorations.
