# Review: what decisions 1 and 4 break or change (2026-10-17)

Scope: the two decisions the user leans to, from the fresh-eye review (`reviews/2026-10-17-consistency-fresh-eye.md`, findings 1 and 4; `open-issues.md` §1.5, §1.8):
- **Decision 1:** concreteness is opt-in per trait; the check is narrowed to the key.
- **Decision 4:** an override defined after a conformance that serves the operation by a default is refused (the keys design), not followed as a fact (rule P).

Method: the notes, explorations, register and session notes were read; `TraitWorld/src`, `TraitWorld/test`, `experiments/facts/acceptance.jl` and the five demonstrators' sources were read. One probe script ran on the patched 1.13.2 build (`/tmp/claude-1000/review-d1d4/probe.jl`, results below). "Verified" means read in source or seen in the probe; the rest is reasoning. Terms: a *key* is the implementing type plus the declared fields' types; a *worker* is a bounded function's body compiled per key; a *run-time site* is a call at non-concrete argument types, dispatched at run time; a *fact* is a recorded dispatch result at a concrete signature.

## Probe results (patched build, verified)

| # | What | Result |
|---|---|---|
| i | A type forwarding to `data::Vector{Float64}` with a declared field `meta::Any` | **admitted**; key prints `Fwd at Vector{Float64}; meta::Any`: an abstract key exists in the prototype today |
| ii | Family member `S{Any}` and `S{Vector{Any}}` of `@implement Fam S{P} where {P}` | **admitted** at the entry (4-details:392 says refused) |
| iv | A fields-only trait, conforming type with `data::Any` | **refused**: "not deeply concrete" |
| iii-b | After `@implement Rec Late`, re-declaring `@implement Rec Late begin rmean(s) = 0.0 end` | **refused** by the definition hook |
| iii-c | A plain method `rmean(s::Late)` after the conformance | **refused** by the hook (`_HAS_DEF_HOOK[] == true`) |
| v | A family conformance with a default; then a method `dbl(::S2{Int})` is defined | **not refused**; trait code returns the default (4) while plain `dbl(S2{Int}(…))` returns 100; `check_overrides()` empty |

So the prototype's concreteness rule is not "deeply concrete key" and not "every field of the implementing type". It is: every field of the implementing type for single-type declarations (iv; `implement.jl:423–424`), the forwarding field's type deeply for forwarding (`implement.jl:442–443`), nothing for declared fields beyond `ST <: FT` (i; `implement.jl:507`), nothing for families (ii; `implement.jl:423` skips, `_family_builder` `implement.jl:612–627` has no check). Row v is a G1 defect independent of either decision; it is taken up under decision 4.

---

## Decision 1: concreteness opt-in per trait, check narrowed to the key

### (a) What changes in the design text

Already conditional (no change): `4-details.md:248, :315, :449, :707`; `aot-under-facts.md:14, :42`; `1-overview.md:40`; `2-design-choices.md:32, :420`; `decisions.md:15`; `open-issues.md:33`.

Must be restated as conditional, or corrected:
- `1-overview.md:97` (pay-off 3, "An abstract type that reaches a hot loop is reported when the package is built"): holds for traits that require concreteness and modules in concrete mode (`4-details.md:166–167`). Two opt-ins; say so, or adopt concrete-mode warnings by default (`4-details.md:777`).
- `4-details.md:392` ("field types … abstract in no other way … `Series{Real}` is refused at the entry"): becomes "for a trait that requires it"; the prototype does not refuse (probe ii).
- `4-details.md:698–699` ("Loads do not change speed", "in the demonstrators such calls lie on cold paths"): true for the demonstrators because their keys are concrete. With abstract keys the price falls on hot paths. Add the condition.
- `aot-under-facts.md:20, :83` ("trait-world dispatch is closed by construction", "closed by conformances and keys, in either mode"): closed for dispatch over trait-world values; an abstract key adds plain open sites inside workers. Restate as "closed where keys are concrete; `verify_main` reports the rest".
- `2-design-choices.md:139–141` ("The dynamic positions are not `Any`"): add that a key with an abstract field type is an `Any`-like position by the conformer's choice, reported by concrete mode.
- `TraitReport/README.md:21` and `TraitReport/src/ReportCore.jl:21–24` ("A `DataFrame` cannot conform … not deeply concrete"), `session-notes/…-26-…:54`, `decisions.md:100` (the TraitTables rationale): restate on the invalidation argument (below).
- `TraitWorld/src/concrete.jl:16–18` ("Workers see only deeply concrete representations"), `implement.jl:66` (docstring of `deep_concrete`): update with the code.
- `4-details.md:248` defines the key as "the implementing type and the associated types"; `4-details.md:315` as "the type itself, the forwarding field's type, or a declared field's type". Pick one wording (the key as in Terms, `4-details.md:18`) and state the depth: concrete, with type parameters deeply concrete, *not* recursing into fields (see (d) 3).

Proofs: nothing changes. Theorems 1–3 (`wrapping-by-facts.md:47–83`) speak of facts at call signatures, never of keys. The entry's hop stays a fact at a concrete signature (`3-wrapping.md:100`): a view type with an abstract key is still a concrete Julia type. Rule 4 (where code lives) is unaffected; an abstract-keyed worker's owners are the trait module and Julia, so it lives in the library's image. G2 holds trivially for run-time sites.

### (b) What breaks or must change in the prototype and tests

- `trait.jl`: no way to declare the option. Add a flag (`@trait X concrete begin … end` or a macro), stored as a `@max_methods 1` method like `has_default` (`core.jl:528–529`).
- `implement.jl:423–424` (`_check_implementation_now`): replace `deep_concrete(R)` by a key check, conditional on the flag. `:442–443` (`_check_projection_now`): same for the forwarding field. `:469–511` (`_field_problems`): add the per-declared-field check for requiring traits; today none exists (probe i). `:1070–1087` (one-line inference): the split `conforming`/`abstract_conforming` and the message at `:1086–1087` become conditional; for a non-requiring trait an abstract field that conforms through a family may forward (key abstract).
- `entry.jl:138–157` (`_conformance_slow`) and `implement.jl:612–627` (`_family_builder`): add the key check for requiring traits, so that "refused at the entry" (4-details:392) exists. Cheap: once per `(X, U)`, cached with the builder.
- `concrete.jl`: root-cause tracing for key field types (`open-issues.md` §3 item 6) becomes necessary, since abstract values now enter through keys by design.
- `verify.jl:478–490` (`_projected_types`) and the walk: no change needed; abstract keys surface as holes.
- Runtime paths already tolerate abstract keys (verified by reading and probe i): `View{X,W,K,N,P}` with `P = _partstype(K)` (`entry.jl:69`) holds boxed parts; `_loadfield`/`_storefield` (`core.jl:148–170`) take the `:ref` path for abstract `T` (pointer load, `::T` assertion; `setfield!` with the write barrier); `fieldset!` (`core.jl:478–487`) asserts `x::T` with `T` the stored type; writable fields need `ST === FT` (`implement.jl:505`), which an abstract stored type satisfies when the trait declares the same abstract type or a parameter. Offsets are per conforming type in the view instance, not in its type; unaffected. `Dynamic{X}` keeps the trait object; its operations dispatch on the view type; unaffected.
- Tests that encode the old rule and flip:
  - `test/runtests.jl:177–181` (`Abstr` with an undeclared `x::Real` implementing `ColTable` itself): accepted under a key check even if `ColTable` requires concreteness (the field is not in the key). Rewrite as: a requiring trait refuses an abstract key (`Vector{Any}` as implementing type; an abstract declared field type); a non-requiring trait accepts.
  - `test/runtests.jl:697–698` (`Abs1`, `data::AbstractVector{Vector{Float64}}` through a family): accepted for a non-requiring trait, with key `AbstractVector{…}` and every operation a run-time site. Decide which the test wants.
  - `test/runtime.jl`, `test/fields.jl:88–112`, `test/strict.jl`, `experiments/facts/acceptance.jl` (G1.3 is the only default-related case, `:67–82`): no concreteness assumption; unaffected.
- `experiments/facts/acceptance.jl`: add a G1 case with an abstract key (a run-time site inside a worker follows a redefinition) and a G2 case (an abstract-keyed worker is not invalidated by a load that adds a subtype with methods). Both should pass by Theorems 1–2; neither exists.

### (c) What breaks in the demonstrators

Nothing runs differently: every key in the five libraries is concrete by construction (verified in sources).
- TraitTables `Column{T}` (`TableCore.jl:17–25`): a family over `Vector`; `Vector{Any}` is admitted today (probe ii's path). `T = eltype(Self)` gives `T = Any`, and `cell(c, i)::T` is then a trivial assertion; summaries on such a column are run-time sites per cell. This is the one demonstrator trait that should **not** require concreteness: mixed columns are legitimate table data.
- TraitCSV `CSVColumn` (`CSVCore.jl:17–33`, ext `:10–13`): keys `Vector{Int}`, `Vector{Float64}`, `Vector{String}`, `Vector{String15}`. Opt in: the parse loop is the hot path.
- TraitDifferentialEquations: `ODEModel{T}` (`ODECore.jl:23–26`) wants `T` concrete; `IntegratorView{T, P}` (`:50–56`) wants `T` concrete and `P` free (the parameters flow to the user's function through a `DynamicFn` pointer and are never read in the step). Per-trait opt-in cannot express this (see (d) 1). Today `FunctionModel{Vector{Any}, Float64}` is admitted through the family path; tests use `Vector{Float64}`.
- TraitMakie `Positions`, `ColorSpec`, `Plot` (`PlotCore.jl:20–52, :127–131`): own concrete types; the trimmed binary's CLOSED result (`aot-under-facts.md` §7) relied on these keys being concrete in fact, not on the check. Opt in to keep that guarantee as a declaration.
- TraitReport `Table`, `Job` (`ReportCore.jl:15–47`): own types. Under opt-in a `DataFrame` **can** conform to a `Table` whose `column` returns `AbstractVector` (the `TableLike` pattern, `4-details.md:587–593`), declared by the trait's owner (rule 3). What it buys: no explicit `columns(df)` copy; `report(df)` without conversion. What it costs: every column operation in `summary_text` is a run-time site into native Base/DataFrames code, which loads invalidate; that is form (b)'s measured 5.3–5.7 s (`TraitReport/README.md:133`) and PlainTables' 17 of 49 methods lost. `Vector{Dynamic{Column}}` wins not by avoiding dispatch but by dispatching into policy-compiled, image-kept, per-type workers (the `Dynamic` operation methods `trait.jl:282–289` are trait-world code). The redesign's rationale stands; only its wording ("cannot conform") falls.

### (d) Subtle risks, ranked

1. **Per-trait grain is too coarse.** TraitDifferentialEquations needs "`T` concrete, `P` free" in one trait. Forced to choose, a library will not opt in, and pay-off 3 is lost where it matters (the state type). A per-parameter or per-field form (`@trait Integrator{T::Concrete, P}` or `@concrete u::Vector{T}`) is the natural grain; "per trait" would be the degenerate case.
2. **The default silently moves hot code into run-time sites into native code.** An abstract key is sound (G1, G2) but its worker's operation calls dispatch into native code that loads invalidate: the shape PlainTables measured. Nothing reports it unless the module opts into concrete mode too. Recommend concrete-mode warnings by default for workers at abstract keys (`4-details.md:777`), or at least a line in `verify_main`. This interacts with decision 3 (below).
3. **Depth.** "Deeply concrete" today recurses into every field of the implementing type (`implement.jl:66–83`), a leftover of representations (`design-findings.md:1114`). For a key the right depth is: `isconcretetype`, with type parameters deeply concrete (`Vector{Any}` fails), without descending into fields. A declared field of a concrete struct type with an `Any` field is the trait owner's choice; concrete mode already names such fields as root causes (`concrete.jl:350–352`). State the depth in the notes, or the implementation will drift again.
4. **"Refused at the entry" is unimplemented** (probe ii) and becomes the only check for requiring traits with families. It must be added at the slow path; otherwise a requiring trait's guarantee has a hole through every family conformance.
5. **AOT reporting.** `verify_main` will report more OPEN programs. Native inference in a closed build may close those sites by abstract facts (`aot-under-facts.md:10`), so binaries are not lost, but the "closed by construction" sentence is.
6. **Strict mode's reach.** Strict mode protects facts (`strict-mode.md:9–17`). A pirate winning inside a run-time site of an abstract-keyed worker is followed silently, as plain Julia follows it. Not new, but abstract keys move hot code out of the mode's reach. Say so in `3-wrapping.md:162–173`.
7. **Requiring later breaks conformers** (`4-details.md:248` already says it). A library that opts in after publishing conformers to abstract keys makes a breaking release. Fine, but it argues for deciding at publication, as the note says.
8. **Prototype tests encode the old rule** (b). Low risk, mechanical.

### (e) Recommendation

**Agree, with conditions:**
1. the grain is per parameter or per declared field, with "per trait" as shorthand for all of them (risk 1);
2. the depth is stated (risk 3) and `deep_concrete` is replaced by a key check at the three declaration sites and at the family slow path (risk 4);
3. abstract keys are reported, not silent: concrete-mode warnings on by default for workers at abstract keys, or a `verify_main` line (risk 2);
4. `1-overview.md:97`, `4-details.md:392, :698`, `aot-under-facts.md:20, :83`, `TraitReport/README.md:21`, `ReportCore.jl:21–24`, `decisions.md:100` are restated; the TraitTables decision keeps its result on the invalidation argument;
5. TraitMakie, TraitCSV and TraitDifferentialEquations (`ODEModel`, and `IntegratorView`'s `T`) declare the guarantee; TraitTables does not.

---

## Decision 4: a late override is refused

### What the prototype does (verified)

- A conformance fixes its witness `Impl{D}` (`D` = the operations served by defaults) in a `const` builder when declared (`implement.jl:542–556`, `entry.jl:127–133`); the operation call folds on `D` (`core.jl:559–577`, `_dispatch`). There is **no method-table edge** for "`T` uses the default for `op`": the decision is a constant, not a fact.
- A record `_declared_defaults(X, T)` is defined per concrete conformance (`implement.jl:572`). The definition hook refuses a later method applicable at the implementing type (`hooks.jl:97–113`, `:118–138`); an image's such methods are left inactive and reported with `@error` after the load (`hooks.jl:188–225`). On stock Julia the checkpoint `check_overrides` runs at declarations, a module's end and first calls (`implement.jl:629–662`).
- Re-declaring the conformance with an override block is refused too (probe iii-b), because the methods in the block are defined before the new record replaces the old one. The error's named fix ("define it before `@implement`, or in its block") is therefore not available after the fact.
- Family conformances define no record (`_family_conformance_methods`, `implement.jl:584–591`; `_declare_conformance_now` returns `()` for non-concrete `T`, `:545`), and their builders are cached per member in a registry saved with the image (`:592–610`). A later override is neither refused nor followed (probe v): **a G1 violation today.**

### (a) What changes in the design text

- Remove or restate "the default decision is a fact" wherever it is used to argue that a later method recompiles: `4-details.md:80`, `3-wrapping.md:90` ("so the owner adding `length(::T)` recompiles the code to the new method"), `wrapping-by-facts.md:25`, `:65` (lesson 4). Under decision 4 the decision is fixed at the declaration and the refusal keeps it true; Theorem 1's invariant (`wrapping-by-facts.md:49–55`) then needs one clause: "a definition that would change a conformance's default decision is refused, so the decision stays true".
- `4-details.md:200`: replace the justification "Plain Julia would call the later method, so accepting it would break identical or error". The correct reason: accepting *without* recompiling breaks G1; recompiling cannot restore it, because (1) a conformance that keeps every default has no implementing type and shares one worker with every type of the same field types (`4-details.md:189`, `entry.jl:449–458`), so the override changes the key from `Key{Nothing, F}` to `Key{T, F}`; (2) values already kept in `Dynamic` hold trait objects of the old key type and would keep running the default (the re-entering `Dynamic` was withdrawn, `keys-plan.md` §5). So a late override is refused for the reason Julia refuses to redefine a struct's fields: compiled code and live values depend on the declaration.
- `3-wrapping.md:150` ("Nothing is refused at load") and `julia-support.md:19` ("nothing is refused at load"): name the one refusal besides strict mode: an image's override of a conformance already active (the `@error` path, `hooks.jl:214–219`).
- `decisions.md:35` ("refusing at the definition needs the runtime"), `open-issues.md:87–88` (Behind the notes 1), `README.md:36` ("late overrides refused at checkpoints"): stale on the patched build, where the hook refuses at the definition (probe iii-c).
- `4-details.md:200` and `keys-plan.md:161`: say that the rule covers family conformances per member (today it does not).
- `4-details.md:189, :196–199` (the `HDAM` example): fine; add the restart case for interactive work (below).

### (b) What breaks or must change in the prototype and tests

- **Families** (probe v): define a record for family conformances and make `_override_violation` intersect the new method's signature with the family's pattern (`Tuple{typeof(f), S2{P}, args…} where P`); invalidate or rebuild the builder registry (`implement.jl:592–610`) when such a method appears. Until then `test/runtime.jl:154–175` covers the concrete case only. Add a family case there and a G1 acceptance case ("a late override for a family member is refused"); `acceptance.jl` has none (G1.3 at `:67–82` tests the opposite, a method the default does not call).
- **The error message** (`hooks.jl:108–109`, `implement.jl:650–651`): drop "or in its block" for the after-the-fact case; say "in a session: restart, or conform under a new type; in a package: move the method above the `@implement`".
- **The image path** (`hooks.jl:188–212`): a refused override is logged with `@error` after the load, and the image's other methods activate. For a package whose purpose is that override, this is a silent half-load. Consider failing the load, as strict mode's `PirateError` path reports, or at least returning the error to `require`.
- `check_overrides` on stock Julia remains a checkpoint (refusal after the fact, at the next declaration or first call). Document as the stock limitation; nothing else to change.
- `verify_main`: nothing; a closed build defines no methods.

### (c) What breaks in the demonstrators

Nothing. No demonstrator defines an override after a conformance (verified): TraitDifferentialEquations defines `jacobian!(::FunctionModelAD)` before `@implement` (`ODECore.jl:108–125`); `Plot`, `Column`, `CSVColumn`, `Table`, `Job` declare no defaults. The one exposure is the family gap: `@implement ODEModel{T} FunctionModel{P, T} where {P, T}` (`ODECore.jl:77`) keeps the `jacobian!` default; a `jacobian!(::FunctionModel)` added later in the library's own source rebuilds the image (fine), but added at the prompt or by Revise it is silently ignored (probe v).

### (d) Subtle risks, ranked

1. **The family gap is a G1 defect now** (probe v), independent of the decision; the decision makes it the one place where the refusal has a hole. Fix before relying on the rule.
2. **Load-order dependence for legitimate stakeholders.** The hook refuses any method *applicable* at the implementing type (`hooks.jl:107`), including a supertype owner's method `op(::AbstractSample)` defined in another package (a stakeholder under decision 2, no pirate under rule 3). If that package loads after the conformance, its method is refused at load; if before, the conforming type becomes the implementing type and the key differs. Plain Julia follows the method in either order. The design must say this is the price of fixing the key at declaration, and the load-time `@error` must name the conformance and the order. It cannot be removed without giving up shared workers under defaults.
3. **No interactive path** (probe iii-b, iii-c). REPL and Revise work on a type's methods after its conformance fails until restart, and Revise reports the hook's error at the edit. Equivalent to Julia's struct redefinition; state it, and give the message the right fix.
4. **Package extensions.** An override in an extension of the type's owner, triggered by an unrelated package, is refused at the extension's load (the image hook). This is the same case decision 2 names as Lemma O's exception; here it is a refusal, not an invalidation. Name both in one place.
5. **The D-fact sentences in the proofs** (`wrapping-by-facts.md:25, :65`; `4-details.md:80`; `3-wrapping.md:90`) are the only places where the facts design relies on the decision being a fact. Left as they are, a reader derives the opposite behaviour (finding 4). Restate (a).
6. **Strict mode: no interaction.** The override check runs before the strict check (`hooks.jl:121–124`); an override is an owned method and passes strict mode's fast path (`strict.jl:81–88`). G1 holds under refusal: a refused method does not exist for plain Julia either (`strict-mode.md:29`).
7. **Keys are unchanged by the decision.** Since the override is refused, the implementing type never changes after the declaration; no compiled code and no `Dynamic` value goes stale. This is what the decision buys.

### Following instead (option (a)) would require

For the record: making the decision a fact needs (1) the implementing type in every key from the start, or every worker under defaults compiled per conforming type (losing shared workers, `4-details.md:189`); (2) `Dynamic` values that rebuild their views per world (the re-entering `Dynamic`, withdrawn for 100–200 ns per operation, `keys-plan.md` §5 and §8); (3) `_dispatch` turning `op in D` into `applicable(f, r, args…)`, which inference folds with a "no method" edge (a fact that a later definition breaks), plus the family registry invalidated by world. (1) and (2) are costs the design has rejected. Refusal is the coherent choice.

### (e) Recommendation

**Agree, with conditions:**
1. close the family gap (risk 1) and test it;
2. restate the justification and the D-fact sentences (a; risk 5);
3. name the refusal at load in `3-wrapping.md:150` and `julia-support.md:19`, with the extension and supertype-owner cases (risks 2, 4) and the load-order dependence stated plainly;
4. fix the error message and document the interactive limitation (risk 3);
5. update `decisions.md:35`, `open-issues.md:87–88`, `README.md:36` to "refused at the definition on the patched build; at checkpoints on stock".

---

## Interactions among the four decisions

- **1 × 3** (concreteness opt-in × rule 3 as stated, facts at non-public functions dropped or confined to the machinery): an abstract key makes a worker's operation calls run-time sites. Without facts at the library's own internal functions, those sites dispatch into native code that loads invalidate: the shape measured for the machinery in session 26 (`@implement` 1.2–1.5 s after loads) and for PlainTables (17 of 49 methods lost). Decision 1's default therefore reintroduces, for every library that does not opt in, the cost the TraitTables redesign removed. Mitigations: the report by default (decision 1, condition 3); or §1.4 (b), run-time dispatch under the policy, which would protect such sites.
- **1 × 2** (stakeholders with supertype owners; Lemma O's extension exception): none. Facts are per call signature; keys do not enter Lemma O or Theorem 2.
- **4 × 2:** the refusal hits exactly the stakeholders decision 2 adds (supertype owners) and the exception it names (extensions). Both belong in one paragraph of "Ownership" (`4-details.md:61–63`): a stakeholder's definition recompiles trait code, except an override of an active conformance's default, which is refused.
- **4 × 3:** none in substance. The family builder registry is machinery state, not a fact; its staleness (probe v) is a cache defect, not an invalidation question.
- **1 × 4:** none. The override check runs on the implementing type; the key check runs on the key. Under decision 1 the one-line and block forms still pass through `_check_implementation`, where both checks sit.
- **Register consistency after both:** `decisions.md:15` ("opt-in … Prototype: yes") becomes true only after (b) of decision 1; `decisions.md:35` needs the family clause and the hook status; `decisions.md:100` needs the restated rationale.
