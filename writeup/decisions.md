# Design decisions: the register

Every design decision with its status, as of 2026-10-16 (end of session 23). The notes say what the design is; this file says what was decided, when, and where it is written down. Statuses:
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
| Layering: ordinary code may use the trait world; the trait world uses only itself. | adopted (rule 1, rev 1110) | 4-details "The four rules" | yes |
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
| Keeping is detected, not declared: a function whose code may keep a trait object receives the whole user's object at its entry (an immutable type boxed only there); every other function receives what its bounds see. The alternative, a `Keep{X}` bound, was not needed. | adopted provisionally (s23, the agent's recommendation; **the user may prefer a declared bound**) | 4-details "Dynamic values" | yes (52cbca3) |
| Automatic differentiation in TraitDifferentialEquations for now by a dual number type owned by the library (`LDual{N}`, option 2); ForwardDiff joins the trait world later through a trait wrapper. | adopted (s23, the user: "Go with option 2 for now") | session note 23; TraitDifferentialEquations step 3 | yes (Rodas5) |
| Automatic-differentiation tags labelled by a `Callable`'s primal signature (`Tag{Sig{A, S}, V}`), so that loss closures of one signature share the solver's code; a closure that captures duals keeps its own tag. | adopted (s23, the user's question); tested with ForwardDiff | session note 23 | not yet in TraitDifferentialEquations |

## Code written without traits

| Decision | Status | Where | Prototype |
|---|---|---|---|
| Trait wrappers (one per package, implementations as delegates); calls upward (`@call`, `@handle`); sealing over views (pirates refused at load). | adopted, deferred while the demonstrators are built | 3-wrapping | yes, in the representation form (`experiments/interfaces`, pinned before keys) |
| Whether wrappers offer conversions for foreign types, now that conformance never converts. | pending | open-issues.md | — |

## Runtime and workspace

| Decision | Status | Where |
|---|---|---|
| Move to Julia 1.13.2. TraitWorld runs on stock 1.13.2 and on the patched 1.13.2 build (`julia-1.13/`, a worktree of `julia/` on `trait-world-1.13`, built in session 23). | adopted | explorations/runtime.md; `experiments/baseline-1.13.md`; session note 23 |
| The machinery's registries (`trait_fields`, `projection`, `op_*`, …) declared with `@max_methods 1` and sentinel methods, so code compiled at abstract types holds no edge to them; then TraitWorld's machinery is protected by the filter like a trait module. Trait modules register with the filter when they start. | adopted (s23, implementation) | session note 23 | yes |
| Workspace: the design repository with separate repositories inside it (`julia/`, `TraitWorld/`, `experiments/`, `TraitDifferentialEquations/`, `TraitMakie/`); local only, no remotes. | adopted | README.md |
| The plan: TraitWorld at the current design, then the demonstrators (TraitDifferentialEquations, then TraitMakie), then an upstream proposal; wrapping and sealing later. | adopted | README.md |
| **TraitWorld's runtime as methods:** a conformance is a method `conformance(As{X}(), u::U)` (`@max_methods 1` and a fallback, so a new conformance invalidates no entry); the entry is an ordinary `@inline` method, `@nospecialize` on the trait argument; the worker is compiled per key; trait sets are families plus parameter tags, so workers are specialized calls. Typed calls: 33 ns against 30 ns plain. | adopted (s23, the user: "go"); implemented (TraitWorld e26683a) | explorations/keys-plan.md §6; session note 23 |
