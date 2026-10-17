# Design decisions: the register

Every design decision with its status, as of 2026-10-17 (session 26). The notes say what the design is; this file says what was decided, when, and where it is written down. Statuses:
- **adopted:** in the design notes;
- **rejected:** considered and not taken;
- **deferred:** designed or agreed, but not worked on now;
- **pending:** waiting for a decision by the user.

"Prototype" says whether TraitWorld runs it.

## The core

| Decision | Status | Where | Prototype |
|---|---|---|---|
| A trait is an abstract type with behaviour: operations and fields. A concreteness guarantee is opt-in per trait. Abstract types stay in Julia; traits are a kind of them. | adopted (s22) | 1-overview "The idea"; 2-design-choices §1 | yes |
| Conformance is declared (`@implement`), never derived from the methods that exist. | adopted | 2-design-choices §2 | yes |
| Layering: ordinary code may use the trait world; the trait world uses only itself. | superseded for calls by wrapping by facts (s23): the trait world may call any Julia code; cache validity comes from concrete facts | 4-details "The four rules" | yes |
| The boundary translates once per bound; only values cross, code never crosses. | adopted (rule 2) | 4-details "The boundary principle" | yes |
| Ownership: owners are packages; a method's stakeholders are the owner of its function and the owners of its types; delegation by the owner only. | adopted (rule 3, s22 wording) | 4-details "Ownership" | yes |
| Views and placement: compiled code is compiled against its owners' view and lives where the type was chosen. | adopted (rule 4) | 4-details "The four rules"; 2-design-choices §7 | yes (view caches) |
| "Identical or error": a call computes what plain Julia computes, or raises. | adopted | 4-details "Identical or error" | yes |
| Types first, then traits, in dispatch. A trait bound ranks above `Any` and below every type. | adopted | 4-details "Dispatch" | yes |

## Keys (session 22)

| Decision | Status | Where | Prototype |
|---|---|---|---|
| Keys replace representations: code is compiled for what the bound can see. The key is the implementing type, if any, plus the declared fields' types. | adopted (6c7f088) | 1-overview; 2-design-choices §3; findings §19 | yes (s23) |
| The implementing type: the type whose own methods serve at least one operation (the conforming type, or the field it forwards to). There is none when defaults serve every operation. | adopted (329e945) | 4-details "Terms", "Declaring a trait" | yes (s23; kept when the declarations name `Self` or a parameter is not field-defined) |
| Implementation is separate from conformance: an implementation gives operations for a type; a conformance gives how a type joins, fields included. | adopted (second review) | 4-details "How a type conforms" | yes |
| Forwarding to a field (`by f`) replaces projections. | adopted | 4-details "How a type conforms" | yes |
| Computed and copying projections and `unproject` are removed. Types whose data needs another layout are converted explicitly by the library. | adopted | 4-details "Types that only convert"; 2-design-choices §3 | yes (refused with an `ImplementError`) |
| Declared fields are stored fields of the conforming type, by name or mapped (`name => stored`). A type with its own `getproperty` maps every field. Computed properties are not declared fields. | adopted | 4-details "Declaring a trait" | yes |
| The reference layout: a trait object reads the user's object. A mutable object is read through with Julia's alias metadata; an immutable type's parts are held, which is equivalent. No snapshots, no exit check. | adopted (dda875f; layout fixed by `experiments/keys-proto`) | 4-details "Declaring a trait", "What a field access costs" | yes (s23); a function that may keep a trait object gets the whole object, detected from its code (TraitWorld 52cbca3) |
| Overrides belong to the conformance: a later method of an operation that a default serves is refused. | adopted (329e945) | 4-details "Declaring a trait" | yes, at checkpoints: declarations, a module's end, first calls (`check_overrides`); refusing at the definition needs the runtime |
| Fields define the parameters their declared types mention, by matching (`data::Vector{T}`). A parameter is defined by a field or by an equation, never both. | adopted (329e945) | 4-details "Parameters" | yes (s23) |
| Membership through a generic implementation only for traits without declared fields. | adopted (second review) | 4-details "Generic implementations" | yes |
| Forwarding carries through generic implementations: the key stays the field's type. | adopted | 4-details "Generic implementations" | untested |
| Forwarding does not chain (a field whose type itself forwards). | adopted (implementation decision) | 4-details "How a type conforms" (implied) | yes |
| A subtrait's conformance must agree with its supertrait's, field mappings included. | adopted | 4-details "Supertraits" | no |
| The held/lens split, the exit check, and the re-entering `Dynamic` from the keys plan's sections 1 and 4. | withdrawn (replaced by the reference layout) | explorations/keys-plan.md §5 | — |
| Internal functions of a trait module take trait objects without bounds; the check follows the trait object through their bodies. | adopted (rev 988); implemented s23 | 4-details "What code in a trait module may do" | yes |

## Parameters, checking, dynamic values

| Decision | Status | Where | Prototype |
|---|---|---|---|
| Associated types in first-order form: one value per conformance, bounds on parameters, the joint family form `@implement X{T} S{T} where {T}`. No input parameters, no equations between type functions, no self-referential bounds. | adopted (s22) | 4-details "Parameters"; explorations/associated-types.md | yes |
| Definition checking at archetypes; open parameters checked per signature. | adopted | 4-details "Definition checking" | yes (keyword, vararg and `Callable` workers still per signature) |
| `Dynamic{X}`: a kept trait object; operations dispatch; opened at a bound; equality like `AnyHashable`. | adopted (s22) | 4-details "Dynamic values" | yes |
| A trait's name in a field or container means its `Dynamic` (the abstract-type sugar). | adopted | 4-details "Traits as abstract types" | yes, inside `@trait_module` only |
| Hidden type parameters for fields declared by bounds. | rejected (the user: "antithetical to Julia") | 2-design-choices §1 | — |
| Dynamic values through pointer tables. | rejected (world age, serialization, races) | 2-design-choices §8 | — |
| `Callable{A, S, M}`: functions from above are dynamic calls by default; the library sets a default, the caller overrides per value. | adopted (rev 988) | 4-details "Callable" | yes |
| Results like the input: `::Like{t}`, constructor operations returning `Self`, `withfields`, a pending result inverted at the entry by rebuilding the user's type. | adopted | 4-details "Results like the input" | yes (the inverse is not listed for AOT) |
| Named implementations by module (`via(M, x)`): anyone may write one; ambiguity surfaces at the call. | adopted (the user: "Liberal it is") | 4-details "Named implementations" | no |
| Selecting implementations by imported scope. | rejected | 4-details "Named implementations" | — |
| Printing trait objects by bound and key (`ColTable at Vector{Vector{Float64}}`). | adopted | 2-design-choices §9 | yes (types; stack frames inherit it) |
| `conforms(T, X)` as the package's stand-in for membership as subtyping. | adopted (prototype only) | README plan | yes |
| Stored functions from above as `DynamicFn{A, S}` (a `Callable` in `DynamicCall` mode as a value of fixed type), made by `dynamic_fn` in ordinary code: a library's model or callback types hold them. | adopted (s23, D5) | session note 23; TraitDifferentialEquations | yes |
| Keeping is detected, not declared: a function whose code may keep a trait object receives the whole user's object at its entry (an immutable type boxed only there); every other function receives what its bounds see. The alternative, a `Keep{X}` bound, was not needed. | adopted (s23, the user: "If feasible, detection is the way") | 4-details "Dynamic values" | yes (52cbca3) |
| Automatic differentiation in TraitDifferentialEquations for now by a dual number type owned by the library (`LDual{N}`, option 2); ForwardDiff joins the trait world later through a trait wrapper. | superseded (s24) by wrapping by facts: Rodas5 uses ForwardDiff's own `Dual` with the solver's tag, called directly | session note 24; TraitDifferentialEquations 702402d | yes (Rodas5) |
| Automatic-differentiation tags labelled by a `Callable`'s primal signature (`Tag{Sig{A, S}, V}`), so that loss closures of one signature share the solver's code; a closure that captures duals keeps its own tag. | adopted (s23, the user's question); tested with ForwardDiff | session note 23 | not yet in TraitDifferentialEquations |

## Code written without traits

| Decision | Status | Where | Prototype |
|---|---|---|---|
| **Wrapping by facts** replaces trait wrappers, delegates, sealing regions, doors and declared calls. Code compiled for the trait world, and every callee compiled for it, depends on the method table only through dispatch facts at concrete signatures; calls with non-concrete argument types dispatch at run time; no invalidation is skipped. The layering rule for calls goes: the trait world may call any Julia code. Each callee is compiled into the trait world's cache or called through a pointer into plain Julia's code, a choice that affects speed only. On pirates, the trait world follows plain Julia; a strict mode (outside pirates raise where they would win) is optional. | adopted (s23, the user: "Full go-ahead for the 'wrap by facts' strategy"); evidence E0–E3; validated (s24): G1 up to A3–A5, G2 for trait-world code with nothing skipped | explorations/wrapping-by-facts.md; experiments/facts | yes: `FactsInterp` in TraitWorld c62efbf; acceptance 16/16, `g2all` 0 lost (s24) |
| **Strict mode: defining a winning pirate is an error.** A method definition (at the prompt, by `include`, or an image's methods at load) is refused if it would win at a concrete fact held by trait-world code (Julia would invalidate that code because of it) and its package is not a stakeholder of that signature (extensions count as their parent, declared delegates as the package they implement). Trait-world code is then never invalidated by a pirate; G1 holds; nothing changes at run time; if pirates never win, it never errors (g2all: no trait-world code invalidated by twelve loads). Optional, off by default, per session or application. | adopted as an option (s25, the user: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error.") | explorations/strict-mode.md | yes: TraitWorld 7b328a5 (`src/strict.jl`), 32 tests; g2all refuses nothing, 0 misses; +0.54 s on a 4.1 s load of CSV, DataFrames, CairoMakie |
| **The intended design of strict mode: compiled trait code never invalidated** except by edits to its own dependencies; every other invalidating event is an error at its source. Adds to the prototype: an image-validation report (Julia piece 15) for pirates loaded before an image; a transitive check (piece 14) for dependence through native code; `twolibs` as acceptance; refusing extensions' winning methods at signatures without their triggers' types; a deletion hook (piece 1′). Edits stay the one exception. | adopted as the intended design, concrete work deferred (s25, the user: "Record what you gave above as the intended design for strict mode. Defer concrete work on it for now") | explorations/strict-mode.md §2b | partly (the prototype refuses pirates defined after the code) |
| Strict mode as `HiddenMethodError` at calls that would select a pirate from outside the code's dependencies (the views design). | not pursued (s25): my first reading of the user; a hostile review found it needs a second cache, checked run-time calls and a cache owner per mode, and reduces no invalidation | explorations/strict-mode.md §5 | — |
| The symmetric check (a fact that selects a pirate is an error when compiled, for pirates defined before the trait code). | adopted as a lint in `verify_main`, not a session default (s25) | explorations/strict-mode.md §4; aot-under-facts.md §5 | planned |
| Delegates kept as data, for split-core packages (StaticArrays for StaticArraysCore, …): a curated list in TraitWorld, or declared by the application. | adopted (s25) | explorations/strict-mode.md §3 | planned |
| "Never invalidated" by a skip predicate for pirates. | rejected (s25): gives up rule P; the refusal mode gives the same without it | explorations/strict-mode.md §5 | — |
| **AOT builds compile the plain call** (native inference in the closed world), not the policy's code: plain Julia by definition (G1), nothing to protect (G2); the binary's baseline is plain juliac (A3 values may differ from the session). | adopted (s25) | explorations/aot-under-facts.md | yes (`_closed_build()`); the image-reuse risk is untested |
| **A closed build replaces the policy's call by the plain call** (`verify_main(…; entrypoints = true)` under `--trim`), so entries from session images are inferred again for the closed world. | adopted (s25, found by the first binary) | explorations/aot-under-facts.md §7 | yes (TraitWorld 893f0bb) |
| AOT annotations for calls into ordinary code (a report at the package's build; `@closed`; result assertions; `@targets`; `@interpreted` with Julia piece 16). | recorded, deferred (s25, the user: "record the ideas but defer for now, except for work already started") | explorations/aot-under-facts.md §6 | — |
| Pay-off 2 restated: dispatch through trait-world code and over runtime types stays closed by conformances; plain code reached from trait code has plain Julia's AOT properties, which `verify_main` reports as holes. | adopted (s25), to be written into the notes and re-measured on three trimmed binaries | explorations/aot-under-facts.md | — |

| Decision | Status | Where | Prototype |
|---|---|---|---|
| Trait wrappers (one per package, implementations as delegates); calls upward (`@call`, `@handle`); sealing over views (pirates refused at load). | superseded by wrapping by facts (s23) | 3-wrapping | yes, in the representation form (`experiments/interfaces`, pinned before keys) |
| Whether wrappers offer conversions for foreign types, now that conformance never converts. | dissolved (s23): no wrappers | open-issues.md | — |

## Runtime and workspace

| Decision | Status | Where |
|---|---|---|
| Move to Julia 1.13.2. TraitWorld runs on stock 1.13.2 and on the patched 1.13.2 build (`julia-1.13/`, a worktree of `julia/` on `trait-world-1.13`, built in session 23). | adopted | explorations/runtime.md; `experiments/baseline-1.13.md`; session note 23 |
| The machinery's registries (`trait_fields`, `projection`, `op_*`, …) declared with `@max_methods 1` and sentinel methods, so code compiled at abstract types holds no edge to them; then TraitWorld's machinery is protected by the filter like a trait module. Trait modules register with the filter when they start. | adopted (s23, implementation) | session note 23 | yes |
| Workspace: the design repository with separate repositories inside it (`julia/`, `TraitWorld/`, `experiments/`, `TraitDifferentialEquations/`, `TraitMakie/`); local only, no remotes. | adopted | README.md |
| The plan: TraitWorld at the current design, then the demonstrators (TraitDifferentialEquations, then TraitMakie), then an upstream proposal; wrapping and sealing later. | adopted; "wrapping and sealing later" superseded by wrapping by facts (s23/s24) | README.md |
| **The Julia work, reviewed** (s25): drop pieces 2 (invalidation policy hook), 4 (post-inference hook) and 6 (dispatch check in codegen) from the upstream list; keep 1, 3, 5, 7, 8 and 9–12; add 13 (instrumentation of foreign CodeInstances); no trimming piece for foreign CodeInstances. Order: 10, 9, 11 (through 1.13's declared `CompilerPlugins.typeinf` hook), 12, 5, 13, 1, 3, then 7 and 8. First upstream proposal: "first-class foreign cache owners" (5, 9–13). | adopted (s25, the user: "make the decisions that need to be made") | explorations/julia-support.md "Review for wrapping by facts and strict mode" |
| The machinery's skip filter, sealing, trait wrappers, declared calls (`@call`/`@handle`) and the layering check removed from TraitWorld; the patched Julia keeps the hooks until then, opt-in. | adopted (s25) | session note 25 |
| **TraitWorld's runtime as methods:** a conformance is a method `conformance(As{X}(), u::U)` (`@max_methods 1` and a fallback, so a new conformance invalidates no entry); the entry is an ordinary `@inline` method, `@nospecialize` on the trait argument; the worker is compiled per key; trait sets are families plus parameter tags, so workers are specialized calls. Typed calls: 33 ns against 30 ns plain. | adopted (s23, the user: "go"); implemented (TraitWorld e26683a) | explorations/keys-plan.md §6; session note 23 |
| **The policy in the platform** (s26, the user): the facts policy's compiler is compiled with the system image and runs in a frozen compiler world, like Julia's own compiler, so that an interpreter loaded before it (REPL's in every interactive session; GPUCompiler, Enzyme, JET) cannot break its compiled code. First as a prototype: a patched system image with TraitWorld in it. | adopted (s26); prototype in progress | open-issues §1.3; session note 26 | not yet |
| **Facts at non-public functions** (s26, the user): in code compiled under the policy, a call at abstract argument types of a function that is not `public` (nor exported) in its owner's module is recorded as a fact, as at a concrete signature. Only the owner adds methods to its internal functions; extending another package's non-public function counts as piracy (rule 3). **Scoped in implementing it to calls from the same package**: applied to Base's internals, which packages extend as a matter of course, it let OffsetArrays, StatsBase and Unitful invalidate trait code (to confirm with the user). | adopted (s26), scoped | open-issues §1.4; session note 26 | yes (TraitWorld 6bcca9f) |
| **Run-time dispatch under the policy:** a run-time site in policy code looks up and invokes the policy's code for the run-time types (a Julia piece: dispatch under a cache owner), so that dynamically reached code, ordinary code included, is protected too. | alternative design, recorded (s26, the user); an experiment to run later | open-issues §1.4 | no |
| **TraitTables and TraitCSV; DataFrames redesigned around traits** (s26, the user): the table demonstrator is a DataFrame-shaped table written in the trait world (TraitTables: named columns kept as `Vector{Dynamic{Column}}`, so that a new schema compiles nothing while each column's code is compiled per column type) and a CSV reader that implements its traits (TraitCSV: cell types as a trait; package extensions such as InlineStrings' become conformances, which cannot discard other keys' code). The same storage, `Vector{Dynamic{Column}}` in place of `Vector{AbstractVector}`, is the proposed redesign of DataFrames itself, adoptable one function at a time behind its API. TraitReport then runs as a plain script with no workload of its own, against the plain package under loads. | adopted (s26) | TraitReport README; session note 26 | not yet |
