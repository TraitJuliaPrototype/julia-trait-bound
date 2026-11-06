# Lowering: the reference

This page defines how the trait language ([`traits.md`](traits.md)) is realized on Julia's interfaces ([`compiler.md`](compiler.md)), within the facts mode's contract ([`facts.md`](facts.md)). For each construct it says what Julia methods, types, tables and caches it becomes, when they are made, in which mode and image their code is compiled, and which code is shared between which types.

It decides nothing the other three references decide. Where it seems to, they win.

- **Terms** as in the [glossary](../glossary.md). Terms used only here are defined where they first appear.
- **Code names** are TraitWorld's (`TraitWorld/src/`, at TraitWorld 4410407; a citation without a path names a line there). Where the intended lowering differs from the code, the section states the intended form and the [Deviations](#18-deviations) table records the difference.
- **Status labels** as in [the conventions](README.md#conventions-for-every-reference): **Implemented**, **Planned**, **Optional**, **Open**.

## Contents

1. [Summary](#1-summary)
2. [Modes, owners and images](#2-modes-owners-and-images)
3. [Trait declarations](#3-trait-declarations)
4. [Implementations](#4-implementations)
5. [Keys and views](#5-keys-and-views)
6. [Trait objects: layout, fields, writes](#6-trait-objects-layout-fields-writes)
7. [Operations on a trait object](#7-operations-on-a-trait-object)
8. [Bounded functions: workers and entries](#8-bounded-functions-workers-and-entries)
9. [Callers: typed, untyped, compiled ahead](#9-callers-typed-untyped-compiled-ahead)
10. [Keywords, defaults and varargs](#10-keywords-defaults-and-varargs)
11. [Results like the input](#11-results-like-the-input)
12. [`Callable` and `Dynamic{Callable}`](#12-callable-and-dynamiccallable)
13. [`Dynamic{X}`](#13-dynamicx)
14. [Checks, and where their results live](#14-checks-and-where-their-results-live)
15. [Compiling ahead, workloads, closed builds](#15-compiling-ahead-workloads-closed-builds)
16. [Sessions, loads and hooks](#16-sessions-loads-and-hooks)
17. [Encodings until traits are in the type system](#17-encodings-until-traits-are-in-the-type-system)
18. [Deviations](#18-deviations)

---

## 1. Summary

**Status: Implemented**, with the encodings of [§17](#17-encodings-until-traits-are-in-the-type-system).

A trait-bounded function has two parts:
- the **worker**, the body as written, compiled by facts per tuple of keys. A `Dynamic` value has the **erased key**, one per trait and parameter values, so the worker compiled for it serves every type ([§5](#5-keys-and-views));
- the **entry**, an ordinary method that decides each plain value's attribute, `Compiled` or `Dynamic` ([`traits.md#6-values-in-trait-code-compiled-and-dynamic`](traits.md#6-values-in-trait-code-compiled-and-dynamic)), translates it by its bound once, and calls the worker. It is compiled in its caller's mode.

What every construct becomes:

| Construct | Becomes | Made | Code compiled as | Kept in |
|---|---|---|---|---|
| `@trait X` | an abstract type; the operation functions; one method per operation on trait objects and on the kept forms (`HeldValue{X}`: `Compiled{X}`, `Dynamic{X}`, `Kept{X}`); records of operations, fields, parameters, defaults, the trait's default attribute | at the declaration | operation methods: inside the workers that call them | the declaring module's image |
| `@implement X T …` | records; a `conformance` method with a builder fixed now; for a block, the operations' methods | at the declaration | `conformance`: a boundary, compiled in its caller's mode | the declaring package's image, with the code compiled ahead ([§15](#15-compiling-ahead-workloads-closed-builds)) |
| a family member | a builder in the family's registry | at the member's first use | as above | the declaring package's image, for members its workload uses |
| a bounded function | a worker; an entry per shape | at the definition; the entry's needs and attributes at the trait module's end | worker: facts, per key, the erased key included; entry: a boundary | the image whose precompilation compiled them |
| a `Callable` argument | a `CObj` holding the function (`Compiled`) or a caller-world pointer (`Dynamic`) | at the entry, per call | worker per function type (`Compiled`) or per signature (`Dynamic`) | as for workers |
| `Dynamic{X}` | a struct holding the user's object; its operations are call-site splits over the held object's type; at a bound, a trait object at the erased key | methods at `@trait`; values at run time | in the caller | — |

**Shared code.** A worker is compiled per view type. A view's type depends on the trait, the key and the witness, never on the user's type ([§5](#5-keys-and-views)). So every type with the key of an existing worker runs that worker, wherever it was compiled, and every `Dynamic` value runs the worker for the erased key.

**Status of the attributes:** Implemented, except [L-31](#18-deviations), [L-36](#18-deviations) and, for closed builds, [L-35](#18-deviations).

---

## 2. Modes, owners and images

**Status: Implemented.**

The facts mode and its owners are Julia's ([compiler §2.2, the method flag](compiler.md#22-the-method-flag-boundaries-and-always-facts-methods); what code may assume: [facts §5, run-time sites](facts.md#run-time-sites)). TraitWorld places each piece of code in one of these modes:

| Code | Mode | How it is marked |
|---|---|---|
| a trait module's methods: workers, internal functions, closures | facts, cache owner `:facts`, whoever calls them | `Base.Experimental.@compiler_options facts=true` in the module's prologue (`trait_module.jl:60`) |
| what a worker calls (operation methods, the user's methods serving operations, Base) | inferred by facts with the worker | Julia's rule; the compiler's own code stays plain |
| entries, `conformance` methods | the caller's mode (a *boundary*) | `Expr(:meta, :facts_boundary)` (`trait_module.jl:791`, `implement.jl:821`) |
| the machinery's slow paths: expansion of `@implement`, checks, finding builders, hooks | always facts | `@machinery`, which inserts `Expr(:meta, :facts_always)` (`compiler.jl:35`) |
| TraitWorld's small helpers (`enter`, `_assemble`, `checked_call`, `opcall`, the builders) | neutral methods ([facts §6.1](facts.md#kinds-of-methods)): compiled in the mode that reaches them, plain from a plain caller, facts from a worker; usually inlined | `@inline` |
| the definition checks' rule check | the default interpreter's reflection: a worker at archetypes is inferred by facts, in the facts cache, as the code that runs would be. An archetype never runs, so nothing it infers is called | `_worker_problems` (`checks.jl:114`) |
| the keep analysis and the result-type checks | plain inference on a `NativeInterpreter` | own cache owner `_CheckOwner` at archetypes; the plain cache at real signatures (`compiler.jl:57`, `:66`; `defcheck.jl:238`) |

**Where code lives** is Julia's behaviour ([facts §11, package images](facts.md#package-images), [compiler §2.9, what package images keep](compiler.md#29-what-package-images-keep)):
- code compiled while a package's image is built is kept in that image, `:facts` code included;
- TraitWorld switches on keep-compiled ([compiler §2.9](compiler.md#29-what-package-images-keep)) for its own image and for every package built after it loads (`TraitWorld.jl:75`, `hooks.jl:22`), so an image keeps the code of the facts owner its precompilation compiled for other packages' methods;
- TraitWorld's own workload compiles its machinery under the facts owner, so a session does not compile it again (`TraitWorld.jl:134`).
- Machinery that calls compiler functions directly (`argextype`, `widenconst`, `sptypes_from_meth_instance`) holds edges to plain compiler code, as any code compiled by facts does: valid as long as plain Julia keeps that code valid ([facts §6.4](facts.md#the-compilers-own-code)).

**Decisions in the caller's world.** The machinery decides implementations in the world of the call that reached it (`tls_world_age()`), as dispatch does (`_DECISION_WORLD`, `compiler.jl:104`). The witness caches and the slow path's cache are keyed by that world and emptied when it changes (`_flush_if_stale!`, `implement.jl:309`; `_conformance_slow`). A family member's builder (§4.6), the trait-world test of a type (§8.2), a function's wrapper (§12), the crossing's flags (§13.1) and the untyped tables (§9.3, by world range) are fixed for the session once found.

---

## 3. Trait declarations

**Status: Implemented** (deviations [L-1](#18-deviations), [L-4](#18-deviations), [L-19](#18-deviations)).

`@trait X begin … end` ([`traits.md#3-trait-declarations`](traits.md#3-trait-declarations)) runs at the declaration, in the declaring module. That module may be a trait module or plain code. It defines:

**The trait type.**
- `abstract type X{P…, Self} <: Trait` (`trait.jl:336`); `InputTrait{K}` for a trait with `K` input parameters. The design's syntax is lowered to a form whose last parameter is the key (`_keys_form`, `trait.jl:103`).
- **A trait with supertraits** is `<: Subtrait{U}` (`InputSubtrait{U, K}` with input parameters), `U` the union of its supertraits' trait types, transitively, a bundle's members included (`_trait_supertype`, `_super_closure`, `core.jl:36`, `:1179`). Its supertraits' covering methods match its kept forms by `U` (below).
- A *trait instance* `X{p…, K}` names the parameters' values and the key `K`. Views carry trait instances ([§5](#5-keys-and-views)).

**The operation functions.**
- A plain name creates a generic function in the declaring module. A qualified name (`Base.length`) uses that function (`trait.jl:372`).
- One method per operation **on trait objects**: `op(t::TObj{T}, args...) where T >: X = opcall(X, Val(:op), op, t, args...)`, declared `@inline` (`trait.jl:405`). These are the only methods trait objects have ([§7](#7-operations-on-a-trait-object)).
- One method per operation and arity **on the kept forms, `HeldValue{X}`**: a call-site split ([§13](#13-dynamicx), `trait.jl:548`). Plain code holding a `Dynamic` calls these; inside a worker a `Dynamic` value is a trait object at the erased key, and its operations go through `opcall` ([§7](#7-operations-on-a-trait-object)).
- One method per operation function **on the kept forms of every subtrait**, declared now or later: `op(dyn::HeldValue{Y}, args...) where {U >: X, Y <: AnySubtrait{U}} = op(_as_super(X, dyn), args...)`, the value seen through `X` with its attribute, which runs `X`'s own method (`trait.jl:559`; [traits §3.6](traits.md#36-supertraits-and-bundles)). For a trait with input parameters, `X` at the family whose declared arguments the call matches, among those the subtrait's record `_input_cands(Y, op)` lists (`_input_super`), at the parameters the held value fixes.
  - **A subtrait's declaration adds no method to its supertraits' operation functions.** So plain code compiled with an untyped call of a supertrait's operation (`vector(::Any)`) keeps its edges when a later package declares a subtrait. It defines only TraitWorld records keyed by its own type: `supertraits`, `_input_cands`.
  - The one exception: a function that two of a subtrait's supertraits declare (`size1` by `A1` and `B1`, `@trait C1 <: (A1, B1)`). Both covering methods match, so the subtrait defines `op(dyn::HeldValue{Y}, args...) where Y <: C1`, through the first supertrait in its closure that declares the function (`trait.jl:594`).
  - The ownership check reads such a method as `X`'s owner's: a subtrait's `U` is never wider than its supertraits (`_owners!`, `ownership.jl`).

**The trait's default attribute:** `@default_with_dynamic_self` or `@default_compiled_for_self` in the body defines `default_attribute(::Type{X})` as `:dynamic` or `:compiled` (a record with a sentinel answering `nothing`: the first-seen rule), read by the entry's decision, the table's test (`_position_compiled`), the keywords' entry, a bounded struct parameter (`_kept_at`) and the item views' choice (`_cross_view`); the traits at one position combine where they agree (`_traits_default`) ([§8.2](#82-the-entry)).

**The records.** Each is a method of a TraitWorld function, specialized on `Type{X}` (and `Val{op}`, `Val{field}`):

| Record | What it answers |
|---|---|
| `trait_ops(X)`, `op_function(X, Val(op))` | the operations, and the function each is |
| `op_args(X, Val(op), K, Val(N))`, `op_ret(…)` | the declared argument and result types at key `K`, with `Self` bound to the key's receiver type |
| `op_default(X, Val(op), t, args…)`, `has_default(X, Val(op))` | a default's body, taking the whole trait object `t` |
| `trait_fields(X)`, `field_type(X, Val(f), K)`, `_fieldpos(X, Val(f))`, `field_isrep` | the declared fields, writable or not; a field's type at a key; its position |
| `trait_params(X)`, `param(X, Val(p), K)`, `param_bound(X, Val(p))` | the parameters; a parameter's value at a key (by equation, or matched from a field's type through `_fieldmatch`); a declared bound |
| `trait_field_params(X)`, `trait_uses_self(X)` | which parameters fields define; whether the declarations name `Self` |
| `supertraits(X)`, `bundle(X)` | supertraits; a bundle's traits |
| `trait_concreteness(X)` | the parts the trait asks to be concrete: `((name, level), …)`, a parameter or `:Self`, with `:error` or `:warn` |

Every record function is declared `Base.Experimental.@max_methods 1` (`core.jl:366`–`1038`). Code compiled at an abstract argument where at least two of a record's methods apply infers nothing from them and holds no edge to them. So a declaration changes no compiled code ([§17](#17-encodings-until-traits-are-in-the-type-system)).
- A fallback (*sentinel*) method makes two apply: `trait_params`, `trait_fields`, `trait_uses_self`, `trait_field_params`, `field_isrep`, `has_default`, `is_mutating`, `trait_concreteness`, `supertraits`, `bundle`, `implementation`, `projection`, `conformance`, `needed`, `keeps`, `_declared_builder` have one; so do `default_attribute`, `attribute`, `result_params` and `is_operation_function`.
- The others have none: `trait_ops`, `op_function`, `op_args`, `op_ret`, `op_default`, `generic_op`, `generic_rec`, `param`, `param_bound`, `field_type`, `_fieldmatch`, `_fieldpos`, `_declared_defaults`.
- Where exactly one method applies, the sentinel or a declaration's, inference infers it and records an edge for the abstract signature ([L-4](#18-deviations)).

**Fields on trait objects.** For each declared field, a method of `_tgetprop(t::TObj{T}, ::Val{f}) where T >: X` and of `_tsetprop!` (`trait.jl:458`). `getproperty` and `setproperty!` on a `TObj` reach them; a `@const` field's setter raises ([§6](#6-trait-objects-layout-fields-writes)).

**Equations** `T = eltype(Self)` become `param` methods evaluated at the key's receiver type (`trait.jl:288`). At an archetype, a parameter is the value the bound fixes or an opaque `ParamArchetype` (`trait.jl:268`).

After the declaration, `_bump!()` registers the candidates of implementations declared so far ([§13](#13-dynamicx)).

---

## 4. Implementations

`@implement` ([`traits.md#4-implementations`](traits.md#4-implementations)) is expanded by machinery code compiled by facts (`_implement_expand`, `implement.jl:1192`). The expansion runs in the declaring module, at the declaration. Every form defines methods, so the declaration is saved with the declaring package's image and owned by it.

### 4.1 What every form defines

**Status: Implemented** (deviation [L-7](#18-deviations)).

| Defined | Meaning |
|---|---|
| `implementation(X, R) = ImplRec(kind, defaults)` | the receiver type `R` implements `X`: by a block (`:methods`, the operations defaults serve), by its existing methods (`:existing`), or as a family (`:family`) (`implement.jl:24`) |
| `projection(X, T) = ProjRec(…)` | for a type that conforms through a field or a field mapping: the receiver type `R`, the forwarding field's index (0: none), the field mapping, a table of dynamic operations (`implement.jl:45`) |
| `conformance(::As{X}, u::T)` | the implementation as a method: an `@inline` boundary that calls the builder fixed now (`implement.jl:821`) |
| `_declared_defaults(X, T)` | the operations defaults serve, per trait of the closure: what an override would change ([§4.8](#48-overrides-and-redeclaration)) |
| `_declared_builder(As{X}, T)` | the same builder, for the untyped calls' table ([§9.3](#93-untyped-callers-of-compiled-values-the-table)) |
| `_compile_ahead(mod, X, T)` | while the package is precompiled: the code calls with a `T` need ([§15](#15-compiling-ahead-workloads-closed-builds)) |

**The builder** is fixed when the implementation is declared (`_declare_conformance`, `implement.jl:672`). It is data: per trait of the closure, a `VSpec` with the witness and the slots ([§5](#5-keys-and-views)). It is a constant of the declaring module, so its image keeps it.

**Checks** run at the declaration, from the expansion's top-level code ([§14](#14-checks-and-where-their-results-live)): `_check_implementation` for a receiver type's operations, `_check_projection` for a type that conforms through a field or mapping, `_check_own_fields` for the one-line form. `_declare_conformance` checks the parameters' bounds (`_param_bound_problems`) and the agreement with the type's implementations of related traits (`_agreement_problems`).

**A refused declaration defines nothing.** The checks infer the operations' results, so the expansion defines the methods before it checks them. It begins with `_declaration_begins()`, which records the world. A check that refuses deletes the methods the declaring module defined since then: the operations' methods of the trait and its supertraits, and the records (`implementation`, `projection`, `param`, `conformance`; `_rollback!`). While a package is built, a refusal fails the build, and nothing is deleted.

### 4.2 A block of methods

**Status: Implemented.**

`@implement X T begin ncols(t) = …; … end` ([`traits.md#41-with-a-block-of-methods`](traits.md#41-with-a-block-of-methods)):
- Each definition becomes a method of the operation's function, qualified by its module, with the receiver typed `T` and unannotated arguments typed as declared (`_op_method`, `implement.jl:991`).
- `implementation(X, T) = ImplRec(:methods, D)`, with `D` the operations left to defaults.
- No `projection` record: `T` is its own receiver.
- The methods are ordinary methods of `T`. Plain code calling `ncols(x::T)` finds them.

### 4.3 One line

**Status: Implemented.**

`@implement X T` ([`traits.md#42-one-line`](traits.md#42-one-line)) declares `T`'s existing methods (`_implement_oneline`, `implement.jl:1430`):
- `implementation(X, T) = ImplRec(:existing, ())`. The operations served by defaults are those `T` has no method for, fixed at the declaration.
- A trait with fields only, or a field mapping, adds `projection(X, T) = ProjRec(identity, I, …)`, with `I = Nothing` for a trait without operations.
- The expansion never picks a field. Without methods for the operations it raises, naming the fields whose type conforms with their `by` lines (`implement.jl:1482`).

### 4.4 Forwarding with `by`

**Status: Implemented** (deviation [L-7](#18-deviations)).

`@implement X T by f` ([`traits.md#43-forwarding-with-by`](traits.md#43-forwarding-with-by)):
- The receiver type is the field's declared type `R`. The record is `projection(X, T) = ProjRec(…, R, …, field index of f, …)`.
- No method is defined for `T`'s operations. Defaults and the field type's methods serve trait code only.
- The witness is the field type's own: `witness(X, R)`, from `implementation(X, R)`. A field type that itself forwards has no `implementation` record, so forwarding does not chain (`_check_projection_now`, `implement.jl:562`).
- *As built,* `by f` is lowered to the projection `project(t) = getfield(t, :f)`, and the projection is accepted because it reads a field as is (`implement.jl:1106`, `:1584`).

### 4.5 Field mappings, several traits, stated parameters

**Status: Implemented** (deviation [L-26](#18-deviations)).

- **A field mapping** `name => stored` is kept in the record (`ProjRec.fmap`). The builder takes each declared field's slot from the mapped stored field (`_mapped`, `entry.jl:659`).
- **Several traits** `(X, Y) T by f`: one `projection` record and one `conformance` method per trait. The entry merges their views into one trait object ([§8.2](#82-the-entry)).
- **Stated parameters** `@implement X{p…} T`: `param(X, Val(:p), T)` and `param(X, Val(:p), Key{T, F})` methods (`_param_methods`, `implement.jl:1264`), for the parameters no field and no equation defines.
- **A stated value for a parameter an equation defines** makes no method: the declaration's check compares it with the equation's value at `T` and refuses the implementation if they differ ([traits §4.6](traits.md#46-stating-parameters)). The equation's `param` method serves `T`.

### 4.6 Families

**Status: Implemented** (deviations [L-38](#18-deviations), [L-44](#18-deviations), [L-45](#18-deviations)); forwarding for a family **Planned**.

`@implement X S{P} where {P} [begin … end]` ([`traits.md#47-families`](traits.md#47-families)) defines (`_family_conformance_methods`, `implement.jl:842`):
- the operations' methods with the `where` clause, for a block;
- `implementation(X, S{P}) where {P}`, for the whole family;
- **a registry** in the declaring module: `const reg = Ref(IdDict())`, found again after an image loads through `_family_registry(Val(name))`;
- `conformance(::As{X}, u::S{P}) where {P} = _conf_family(reg, X, u)`.

**A member is fixed at its first use** (`_conf_family_slow`, `implement.jl:861`):
- the slow path checks the member once (`_member_problems`: the operations the family's methods serve, as at a single type's declaration, the parameters' bounds, and the parts the concreteness declarations name, `_concrete_problems`; a member that does not conform is refused with `ImplementError`), finds its builder and stores it in the registry, copy-on-write;
- a member that does not conform has no witness (`_witness` returns `nothing` for it), so no other path takes it as conforming;
- the member's default-served operations are added to the override index then ([§4.8](#48-overrides-and-redeclaration));
- builders found by the declaring package's workload are saved with its image; a builder holding session pointers is not kept.

A later declaration for one member is a more specific `conformance` method. It is refused after the member's first use, and in a package extension (`_member_override_problem`).

**A member's builder is a constant in a caller that knows its type,** as a declaration's is ([the design note](../plans/2026-10-26-w40-member-builder-fold.md)):
- the family's `conformance` method calls `Compiler.fold_call(_member_fold, reg, X, typeof(u))` ([compiler §4.4](compiler.md#44-compilerfold_call)). Where the member's type is known, inference calls `_member_fold`, and the caller holds the builder as a constant; elsewhere the call is `nothing` and the method takes the run-time path (`_conf_family`);
- `_member_fold` returns a builder in the registry, or does the slow path's work (`_member_fix!`: the member check, the builder, the registry entry, first writer wins, and the override index), the one place a member is fixed;
- while called from inference it takes TraitWorld's lock only by `trylock`, writes nothing, runs no generic implementation's predicate, and fixes a member only in the latest world. A member that does not conform, or whose builder holds a session's pointers, never folds (remembered). A busy lock, an older world, a re-entrant call or a check that would warn are "not now": the caller takes the run-time path, which checks the member at its first use and raises `ImplementError` or warns there, as without the fold;
- the fold's record stays in the caller's edges. When an image keeps the caller, the record is evaluated again at load (`_member_fold(Compiler.AtLoad(), …)`, which may wait for the lock), which fixes the member in that session; another answer invalidates the caller.
- **A member fixed while an image is built is recorded in that image** (`_note_image_member!`, `_write_image_members`): just before Julia writes the image (an `atexit` hook of the build), each member fixed there whose check passed without a warning becomes a method in the package's module, `_member_record(::Type{X}, ::Type{U}, ::Val{image})`. It holds the builder, the override index records, and the signatures the check depends on beyond the image's dependencies with the methods dispatch selected there: the conformance at `U` of each trait in `X`'s closure, each operation at its declared argument types. At load, `_member_fold_at_load` finds the record by dispatch (an image's methods are in the method table before its code is validated). Where dispatch selects the same methods, it fixes the member from the record (`_member_from_record!`): the registry entry, the checked mark, the index records, without the check and the builder. Otherwise, or without a record, `_member_fix!` runs. A member fixed while Julia writes the image (code compiled at output) has no record.
- A typed call of a family member then costs what one of a declared type does.

**Planned: forwarding for a family**, `@implement X S{T} by f where {T}`: the family's `conformance` method with a builder per member that reads field `f`.

### 4.7 Generic implementations

**Status: Implemented** (the form); the overlap check and the refusal of a computed condition **Planned** ([`traits.md#48-generic-implementations`](traits.md#48-generic-implementations), T-9, T-79).

`@implement X R where {R: Y, pred} begin … end` defines (`implement.jl:1393`):
- `generic_rec(X, Val(k)) = GenericRec(constraints, predicate, defaults)`, with `k` a fresh name;
- each operation as a method of `generic_op(X, Val(k), Val(op), t, args…)`, where `t` is a trait object carrying the constraint traits;
- no `conformance` method: the generic `conformance` fallback finds the implementation ([§8.2](#82-the-entry)).

At a type's first use, `_generic_concrete_check` (`entry.jl`) checks the parts the concreteness declarations name, as `_concrete_problems` does at a declaration, and refuses the type with `ImplementError`; the operations' results are checked by `_witness` with a warning only ([traits T-52](traits.md#17-deviations)). At a type's first call, `_witness` (`implement.jl:377`) tries each generic record: the constraints' witnesses, then the predicate, in the decision world. The witness is `Generic{X, k, S, D}`, holding the constraints' witnesses. More than one match is an error. A more specific declared implementation is found first, as a `conformance` method of its own. The generic implementation's results are checked at the first concrete type, with a warning (`_generic_problems`).

### 4.8 Overrides and redeclaration

**Status: Implemented**; redeclaration **Planned** ([`traits.md#49-checks-at-the-declaration`](traits.md#49-checks-at-the-declaration)).

- `_declared_defaults(X, T)` records `(trait, receiver type, operations)` for each trait of the closure (`implement.jl:657`). Family members add theirs at first use.
- From these, an index maps each operation function to the implementations its defaults serve (`_OVR_INDEX`, `hooks.jl:62`).
- **At a definition,** the method-definition hook refuses a method of an indexed operation for an indexed receiver type ([§16](#16-sessions-loads-and-hooks)).
- **At an image's activation,** the image hook leaves such a method inactive and reports it after the load.
- **Checkpoints** scan the records again (`check_overrides`, `implement.jl:943`): at each declaration, at a trait module's end, at a worker's first call.
- **Redeclaration** with a block is refused when `T` already has a `conformance` method of its own (`implement.jl:1192`, `:1192`). Every other form is refused too, in a session ([traits §4.9](traits.md#49-checks-at-the-declaration)). *Planned:* redeclaration on Julia 1.13's struct redefinition: a new `conformance` method and records, old values keeping the old builder.

---

## 5. Keys and views

**Status: Implemented** (deviations [L-1](#18-deviations), [L-2](#18-deviations)).

The key ([`traits.md#67-what-compiled-code-is-compiled-for`](traits.md#67-what-compiled-code-is-compiled-for)) is lowered as follows (`_key_and_slots`, `entry.jl:667`):
- **A trait without fields:** the key is the receiver type `R`.
- **A trait with fields:** `Key{I, F}`, with `I` the receiver type and `F` a named-tuple type of the declared fields' declared types (`core.jl:52`). A `@const` field stored at a subtype is read at its declared type ([traits §3.3](traits.md#33-fields)): types storing it at different subtypes have one key and one compiled worker. A field whose declared type is abstract is read from the object by its index, since the key does not fix its storage; a concrete one at its slot's offset (`_loadpart`, `core.jl`).
- **No receiver type** (`I = Nothing`): every operation is served by a default, the declarations do not name `Self`, and the fields define every parameter ([traits §6.7](traits.md#67-what-compiled-code-is-compiled-for); `_no_implementing_type`, `entry.jl:681`).

**A view** is one trait's part of a trait object: `View{Xi, W, K, N, P}` or `Held{Xi, W, K, N, P}` (`core.jl:68`, `:83`), with
- `Xi` the trait instance `X{p…, K}`;
- `W` the **witness**, a type saying where the operations come from: `Impl{D}` (the receiver type's own methods, `D` those served by defaults), `Generic{…}`, `Dyn{…}`, or `ArchWit` at an archetype (`defcheck.jl:40`);
- `K` the key, `N` the number of declared fields, `P` the type of the parts the view holds.

**The builder** of a user type is `Builder{Tuple{VSpec…}}`, one `VSpec{Xi, W, K, N, P, S}` per trait of the closure (`entry.jl:40`, `:47`). A `VSpec` holds the witness, the receiver's slot and the declared fields' slots. A *slot* is a byte offset and a field index; offset −1 means the object itself (`core.jl:38`). `S` says that the user's type is its own receiver.

**Why a new type with an existing key compiles nothing in the library:**
- its views have the key's view type, so the worker for that view type serves it;
- its builder's type depends on the trait, the key, the witness and `S`, not on the user's type, for every type that forwards or is keyed by its fields alone;
- what the declaration adds is data (the builder's witness and slots) and one small `conformance` method, compiled into callers that know the type.

**The erased key** is `ErasedKey{P, Y}`, with the witness `ErasedWit`: a `View{X{p…, ErasedKey{P, Y}}, ErasedWit, ErasedKey{P, Y}, 0, Tuple{}}` holds the user's object in its field `o` (typed `Any`) and no slots. `P` is the tuple of the trait's parameter values, each wrapped as `ParamVal{v}` (a tuple's field type cannot be `Union{}`, which a column of `Union{}` has); `Y` is the item trait of a `CompiledItems{Y}` view whose items are of an abstract type ([§13.1](#131-a-users-container-crossing-by-its-bound)), else `Nothing`. `Self` at the erased key is `ErasedSelf`: an operation's result declared `Self` gives a `Dynamic` of the new value; a field declared `Self` reads as `Any`.
- The parameter values `p…` are those the position fixes; at a bare bound that leaves a parameter its results use open, the value's own, read when it enters ([`traits.md#51-bounds`](traits.md#51-bounds)). So the worker at the erased key is compiled once per tuple of parameter values.
- A trait object at the erased key has an erased view for each trait of the bound's closure, supertraits included, so a bound on a supertrait accepts it, and several bounds at one position work.
- Its trait set has the same families and parameter tags as a keyed one's. The tags are attached only after the entry has checked the value's parameters, per candidate and, beyond them, dynamically.
- Its view type does not depend on the user's type. So one worker serves every `Dynamic` value at the position.

**A trait object** is `TObj{T, V}` (`core.jl:196`): `V` the tuple of views, `T` the trait set, computed from the views' instances (`_traitset`, `core.jl:355`).

**A worker's signature** names a trait object by its trait set's lower bound: `t::TObj{T} where T >: Union{F…, PTag{F, i, v}…}`, with the families of the bound and its supertraits and a tag per parameter the bound fixes (`tobj_bound`, `trait_module.jl:766`). The lower bound has no free type variable, so the worker's static parameters are all determined by its argument.

---

## 6. Trait objects: layout, fields, writes

**Status: Implemented**; a copying layout for isbits-only targets **Optional**, until a port targets isbits-only devices.

**Four layouts,** chosen by the builder per view (`_buildview`, `entry.jl:56`):

| The user's value | View | Holds | A read |
|---|---|---|---|
| mutable | `View`, `o` = the user's object | the object; the slots of the receiver and of each declared field | a load at the slot's offset, every time |
| immutable, forwarding or keyed by its fields | `View`, `o = nothing` | the parts: receiver and declared fields' values, typed by the key | a field load from the view |
| immutable, its own receiver | `Held` (a *held view*) | the whole value and its declared fields' values | a field load |
| any, at the erased key | `View` at `ErasedKey`, `o` = the user's object as `Any` | the object | the call-site split over the candidates; in each branch the candidate's slot read as above; the result asserted to the declared field type ([§13](#13-dynamicx)) |

- Holding is equivalent to reading for an immutable value: none of its fields can be rebound.
- A key used both held and read through has one worker per view type.
- A function that may keep a trait object receives the whole user's object also for an immutable value: the entry replaces `o` by the boxed value (`_with_object`, `entry.jl:422`; [§8.4](#84-keeping)).

**The receiver** of a view is read by `_rep` (`core.jl:97`): the held part, or the object itself (slot −1), or its forwarding field at the slot's offset.

**Reading a declared field** `t.f` (`fieldget`, `core.jl:949`):
- a held view: the part at the field's position;
- otherwise, a load from the user's object at the slot, by the field's storage kind (`_storage`, `core.jl:144`):
  - isbits or a reference: the field-offset intrinsic `getfield_at_offset`, with Julia's alias metadata and, for a reference, the null check ([compiler §5.2, field-offset intrinsics](compiler.md#52-field-offset-intrinsics));
  - a singleton: the constant;
  - stored inline and not isbits: `getfield` by index.
- The result has exactly the key's field type, the declared one.

**Writing a declared field** `t.f = x` (`fieldset!`, `core.jl:958`):
- `x` is asserted to the key's field type;
- a held view raises (an implementation check refuses writable fields on immutable types first);
- isbits and reference fields are stored with `setfield_at_offset`, which keeps the write barrier; others with `setfield!`.
- A `@const` field's setter raises `ArgumentError` (`_readonly`).

**An undeclared field** has no `_tgetprop` method: `ArgumentError` at run time, and a `TraitUseError` from the definition check ([§14](#14-checks-and-where-their-results-live)).

---

## 7. Operations on a trait object

**Status: Implemented.**

`op(t::TObj, args…)` reaches the method `@trait` defined, which calls `opcall` (`core.jl:1058`):
1. selects the view of `X` (`viewof`, folded for a known view type);
2. checks the arguments against `op_args` at the key: `TraitArgumentError` otherwise. A trait object passed to an argument declared `Dynamic{Y}` is first converted to a `Dynamic{Y}` ([§13](#13-dynamicx), the seams);
3. dispatches on the witness (`_dispatch`, `core.jl:1095`):
   - `Impl{D}`: a default (`op_default`, with the whole trait object, so it may call supertraits' operations) if `op ∈ D`, else `op(receiver, args…)`, the receiver type's own method;
   - `Generic`: `generic_op` on a trait object built from the constraints' witnesses;
   - `ErasedWit`: the call-site split over the held object's type, each branch the candidate's view folded and its own dispatch, the fallback a dynamic call ([§13](#13-dynamicx));
4. asserts the result to `op_ret` at the key.

For a concrete view type, the witness, the default test and the declared types are constants. The call to the receiver type's method is a call at concrete types: a fact. At the erased key, each branch of the split is such a call; the fallback is a run-time site.

---

## 8. Bounded functions: workers and entries

### 8.1 The rewrite

**Status: Implemented** (deviations [L-3](#18-deviations), [L-47](#18-deviations), [L-50](#18-deviations)).

`@trait_module` wraps every top-level statement in `@stmt`, so each is expanded after the ones before it have run (`trait_module.jl:72`). A function definition with a trait bound, a `Callable` bound or a trait vararg is rewritten (`_rewrite_fdef`, `trait_module.jl:649`) into:
- **the worker:** the definition as written, with each bounded argument typed `TObj{T} where T >: …` ([§5](#5-keys-and-views)), each `Callable` argument `CObj{A, S}`, several `Callable`s `CMulti`. It is a method of the trait module, so Julia compiles it by facts;
- **the entry,** once per *shape* (the pattern of annotated positions): a method with the bounded positions untyped and `@nospecialize`, compiled in its caller's mode ([§8.2](#82-the-entry)); a declared result that is a plain type (no `where` variable, no trait) or a `Dynamic{X}` is asserted at each of the entry's returns, the fallback's included ([traits T-95](traits.md#17-deviations)), so a caller's plain inference (the member check's among them) sees it rather than `Any`. Asserted, not converted: the worker returns the declared type already, and a conversion of a result typed `Any`, from a worker chosen when the code runs, would be a dispatch per call. Such a result is never a result like the input, so the entry has no branch for one;
- **a note of each trait position** (`_note_position`), from which the entry's needs and the position's attribute are fixed ([§8.3](#83-needs-and-the-modules-end)).

**Attributes:** `x::Compiled{X}` and `x::Dynamic{X}` (also `Compiled{Callable{A, S}}`; `Dynamic{(X, Y)}`, read from the syntax, since a tuple of traits is not a type parameter) are read by `_classify` as the bound `X` with an attribute, recorded in the position's note. An attribute on a bound's item parameter (`Iterable{Compiled{Mark}}`) becomes the item tag `Through{Mark, Compiled}`, and a bare trait name there `Through{Mark, Nothing}` ([§13.1](#131-a-users-container-crossing-by-its-bound)). A `Dynamic` attribute whose trait leaves a parameter its result types use open is refused here (`TraitBoundError`).


**A bound that opens its value** (`c::Opened{X}`, [traits §6.4](traits.md#64-casts)): `_strip_opened!` reads it as `c::X` and records the name; the entry begins, after its facts boundary, with `c = compiled_for(c)` for each such name, so the worker is called at the value's key. `_dyn_type` and `_dyn_body` leave `Opened{…}` as written. A keyword argument is not lowered so (traits T-88).

**`where` variables in bounds** (`f(v::KVec{T}) where {T}`, and under an attribute, `c::Dynamic{Column{T}} where {T}`, whose parameters are those of the bound inside): `_classify` evaluates the bound with the variables open, a family bound without their parameter tags. A variable that only bounds name is taken off the worker's `where` list, and the body begins with `T = _trait_param(v, KVec, Val(1))`, a constant per key read from the trait object's type (`core.jl`); one that an ordinary argument or a second bound also fixes is checked against it (`_param_mismatch`), and a bound on the variable is checked there too. A `Callable` bound naming one is refused (`_uses_callable`). A bound that names a variable is never evaluated as written first, so the variable shadows a global of the module of the same name (LinearAlgebra's `I` in `IndexProvider{I}`), as in plain Julia; an element of a tuple of bounds likewise.

**Macros around a definition:** `@inline`, `@noinline` and a docstring are kept on the worker. Any other macro around a function definition (`Base.@nospecializeinfer`, also under a docstring) is expanded once by `_process` (`macroexpand` without recursion, its outer `esc` removed), and the expansion is rewritten as a definition; otherwise a bounded function inside it would stay a plain method with the trait as an argument's type. **`@nospecialize` on an ordinary argument** (the macro, or Julia's expanded `(meta nospecialize x)`), an ordinary vararg included (`@nospecialize(xs...)`), is removed before `_classify` (`_strip_nospecialize!`) and put back on that argument of the entry and of the worker; on a bounded argument it is refused when the method is defined, since the attribute decides how a bounded argument is compiled.

**Concreteness prefixes** (`@enforce_concrete_only T v f(…)`, [traits §11.2](traits.md#112-per-function-concrete-parameters-of-the-bounds)): `_process` reads the level and names into a scoped value (`_PART_CONCRETE`), which `_rewrite_fdef` reads for every method the definition makes, defaults included. The worker's body starts with a check per name, after the `where` variables are bound: `_concrete_part(T, …)` for a variable, `_concrete_self(v, …)` for a bounded argument. Both are generators over types: for a key known where the worker is compiled the check is a constant; `_concrete_self` reads the receiver type from the trait object's type, and skips an erased key (a `Dynamic`) and an archetype. A failure raises `TraitBoundError`, or warns once per function, name and type.

**A type's constructor** takes bounded methods as any function does (`NWState(int::(IntegratorView, HasSystem))`). Everything the machinery keys by the function is keyed by `Core.Typeof(f)` (`_ftype`): `typeof(f)` for a function, `Type{S}` for a constructor, as in the methods' signatures (`typeof(S)`, `DataType` or `UnionAll`, is shared by every type). The function is read back from such a key by one helper (`_fof`: the singleton's instance, or `S` of `Type{S}`). An ordinary constructor at the entry's signature, defined before the bounded methods, becomes the entry's fallback: one of Julia's default constructors (`S(x)`, which converts to the field types; `S(x::T) where {T}` of a parametric struct) or an untyped inner one. When the entry is defined, that method and its keyword sorter are taken out of the method table (`_ctors_at_entry`, `_take_ctor!`), and a tagged method takes each one's place, `S(::Untyped, args…)` and `Core.kwcall(nt, ::Type{S}, ::Untyped, args…)`, which calls it by `invoke` with the method itself. While Julia writes a package image it refuses to take a method out ([L-50](#18-deviations)).

An untyped method of an existing entry's shape becomes the entry's **fallback**: `f(::Untyped, args…)` (`trait_module.jl:898`). An ordinary method that would take an entry's signature is refused (`_check_entries_intact`).
- **Only the machinery passes `Untyped()`,** and it chooses among the tagged methods alone: the most specific one that applies (`_tagged_fallback`, `entry.jl:713`). Where the call by dispatch is ambiguous with an ordinary method of one more argument (`f(::Untyped, thing)` beside `f(thing, uflat::AbstractVector)`), the tagged method is called by `invoke` at its own signature (`_invoke_tagged`).
- So no call reaches the intersection of a tagged method and another method, and the module's end does not report it as an ambiguity (`check_entry_ambiguities`, [§8.3](#83-needs-and-the-modules-end)). In a closed build: [L-47](#18-deviations).

A worker calling a function with a trait object it carries reaches that function's worker directly: the trait object's type matches the worker's signature, and the entry at `Any` is less specific. A trait object reaching an entry raises `TraitBoundError`: its trait is not the one the callee needs (`_rule3_error`, `entry.jl:470`).

Internal functions without bounds take trait objects as ordinary arguments. Julia compiles them by facts as part of the worker's call graph.

### 8.2 The entry

**Status: Implemented.**

The entry is declared `@inline` and is a boundary (`trait_module.jl:791`). Every trait position is `@nospecialize`: a typed caller inlines the entry, an untyped caller reaches the one entry compiled at `Any` ([§9](#9-callers-typed-untyped-compiled-ahead)). Its body, for each bounded position `i`:
1. `enter(EntryPos{Core.Typeof(f), i, nargs}(), x)` (`entry.jl:213`) decides the attribute once, for the value as it arrives:
   - a trait object raises ([§8.1](#81-the-rewrite));
   - a `Dynamic` stays `Dynamic`: the trait object at the erased key of its held object (`erased`), never opened ([§13](#13-dynamicx));
   - a kept value (`Dynamic`, `Compiled`, `Kept`) is assembled for every trait of the position its held object conforms to, with its attribute; one whose object conforms to none of them gives `NOTRAIT`, so the call reaches the fallback with the kept value as passed (`_enter_held`; [traits §5.5](traits.md#55-dispatch-types-first-then-traits), [§6.5](traits.md#65-values-carry));
   - `compiled_for(y)`: the trait object of `y` at its own key, so the worker for that key is selected once. A typed caller assembles it in place. From an untyped caller, the table of declared implementations serves it ([§9.3](#93-untyped-callers-of-compiled-values-the-table));
   - `with_dynamic(y)`: the trait object at the erased key;
   - any other value, by the first that applies:
     1. the position's attribute, if the bound has one (`attribute(EntryPos{…}())`, fixed at the module's end);
     2. the traits' default (`default_attribute`): `@default_compiled_for_self` for every plain value; `@default_with_dynamic_self` for a value whose type is not of the trait world (`_from_trait_world`);
     3. `Compiler.known_type(x)` ([compiler §4.1](compiler.md#41-compilerknown_type)): `true`, `Compiled`; `false`, `Dynamic`. It is `false` wherever the call to the entry is dispatched at run time: the argument held at an abstract type, or the function itself not known to the caller (a module in a variable, a harness that calls through a function value). It is evaluated in the entry's own body, before the value is passed to any helper: in code compiled by facts, a helper called with an `Any`-typed value is a run-time site, compiled for the value's type, where it folds to `true` (E-148).
   - `Compiled`: `_assemble(needed(p), x)`, one `conformance(As{X}(), x)` call per needed trait, the views merged, each trait once (`entry.jl:428`). `Dynamic`: the conformance check split over the candidates (`@dynamic_of`'s), then the trait object at the erased key;
   - a container at an item position crosses into a view ([§13.1](#131-a-users-container-crossing-by-its-bound));
2. `NOTRAIT` (the value conforms to none of the needed traits) returns `fallback(f, args…)` (with keywords, `kwfallback`, [§10](#10-keywords-defaults-and-varargs)): the `Untyped` fallback, else the most specific ordinary method that is neither entry nor worker, else `MethodError` with a hint naming the bound (`entry.jl:709`, `frames.jl:64`);
3. `Callable` positions are translated by `enter_callable` ([§12](#12-callable-and-dynamiccallable)), by the same decision;
4. the worker is called through `checked_call(f, views…)`: the first-call check flag, then the call (`checks.jl:294`). At the erased key the trait object's type is known to the entry, so the call is static;
5. a result like the input goes through `_like_out` ([§11](#11-results-like-the-input)).

**`conformance`** has one method per declared implementation, and a fallback that finds generic implementations and implementations without a fixed builder (`_conformance_slow`, `entry.jl:144`). The slow path's results are kept copy-on-write per decision world.

**Dispatch, types first** ([`traits.md#55-dispatch-types-first-then-traits`](traits.md#55-dispatch-types-first-then-traits)): the entry's bounded positions are `Any`, so every type-annotated method is more specific. A value caught by one takes it and is never translated.

### 8.3 Needs and the module's end

**Status: Implemented.**

- **What a position needs** is `needed(EntryPos{F, pos, nargs}())`, `F = Core.Typeof(f)` ([§8.1](#81-the-rewrite)): a `TraitList` of the traits the workers of `f` bound there. **Its attribute** is `attribute(EntryPos{F, pos, nargs}())`: `Compiled`, `Dynamic`, or `nothing` where no bound there has one, fixed with `needed`. Until the module is complete a fallback computes it by reflection (`entry.jl:202`). At the module's end, `_fix_needed!` defines one method per position, a constant (`trait_module.jl:1126`). A later definition at the prompt redefines it when the needs change.
- **At the module's end** (`_finish_module`, `trait_module.jl:1146`): the needs, attributes and keep flags are fixed; overrides are checked; unrelated bounds without a joint method and ambiguities with typed methods are reported (`check_bounds`, `check_entry_ambiguities`); an attribute on a function neither exported nor public in its owner module (`Base.ispublic`) warns (`_warn_hidden_attributes`); definition checking runs ([§14](#14-checks-and-where-their-results-live)).
- **The module's registries** are constants its prologue defines: `__tw_entries__` (shapes per function), `__tw_plain__`, `__tw_extended__`, `__tw_positions__`, `__tw_untyped__`, `__tw_finished__` (`trait_module.jl:60`).
- **Only the function's owner** may add an entry: an entry is a method at `Any` (`trait_module.jl:831`).
- **A bounded function defined again after the module's end** ([traits §2](traits.md#2-trait-modules)) goes through these steps for that function. TraitWorld puts a front before Julia's lowering (`Core._lower`, Julia's entry for another lowering; `_tw_lower`, `trait_module.jl`): a statement evaluated into a complete trait module is evaluated through `@stmt`, as the module's own statements are (`_eval_stmt`), and for a function it defines the module's end runs (`_finish_function`): overrides, bounds and ambiguities checked, definition checking. The worker is replaced, and `needed`, attributes and `keeps` are fixed again where it is defined (`_note_position`). The first-call checks' records name the worker methods ([§14](#14-checks-and-where-their-results-live)), so the replaced worker's records no longer apply. Revise: [traits T-81](traits.md#17-deviations).

### 8.4 Keeping

**Status: Implemented.**

`keeps(KeepOf{F}())` says whether a worker of `F` may keep a trait object: make it a `Dynamic`, store it where a `Dynamic` is declared, or return a closure that captured it (`entry.jl:408`).
- It is decided at the module's end, by inferring each worker at archetypes in the checks' own cache and following internal functions and workers (`_analyze_keeps`, `defcheck.jl:284`).
- An answer the analysis cannot reach is `true`, the fallback. It costs a box, never a wrong result.
- The method-definition hook recomputes it for a function given a method after its module is complete (`hooks.jl:242`).
- Where it is `true`, the entry gives an immutable value's views the whole object ([§6](#6-trait-objects-layout-fields-writes)).
- `with_dynamic(t)` in a worker keeps. A trait object at the erased key always holds the whole object, so a worker at the erased key may keep it whatever `keeps` says.

---

## 9. Callers: typed, untyped, compiled ahead

### 9.1 Typed callers

**Status: Implemented.**

A caller that knows the argument's concrete type inlines the entry, where `Compiler.known_type` folds to `true`, and passes a `Compiled` value:
- `needed`, the `conformance` method, the builder and the witness are constants there; the views are built in place;
- the worker's selection is a static call;
- in the patched build, Julia's inliner inlines the entry, as declared, and code of the other owner from that owner's cache ([compiler §2.7, inlining across owners](compiler.md#27-inlining-across-owners)).

The worker, compiled by facts, is shared by every caller of its key.

### 9.2 Untyped callers: the erased worker

**Status: Implemented.**

A caller that does not know the type reaches the one entry compiled at `Any`, where `Compiler.known_type(x)` is `false` ([compiler §4.1](compiler.md#41-compilerknown_type)). The value is `Dynamic` ([`traits.md#6-values-in-trait-code-compiled-and-dynamic`](traits.md#6-values-in-trait-code-compiled-and-dynamic)):
- its conformance is checked by a split over the candidates, folded to a constant per candidate, a dynamic call beyond them (`_ConformsTo`, `core.jl:878`);
- the trait object at the erased key is made from it ([§5](#5-keys-and-views));
- the worker for the erased key is called statically: the entry knows the bound, so it knows the trait object's type.

Nothing is compiled per user type. Code Julia does not compile (a statement at the prompt) is such a caller.

### 9.3 Untyped callers of `Compiled` values: the table

**Status: Implemented.**

An untyped caller passes a `Compiled` value where it converts it (`compiled_for(x)`), or where the position's attribute is `Compiled`. The entry compiled at `Any` then finds the code for the value's key through the **table of declared implementations** (`untyped.jl`). This is how Swift opens a value of a protocol type: the per-type data is looked up, the code is shared per key.
- **Which entries:** those of trait positions and ordinary arguments only, without keywords or varargs (`trait_module.jl:791`). Other entries take the generic path of `enter`: the trait object assembled for the value's type behind a dynamic call, then the worker selected by a second dynamic call.
- **The test** (`_tabled`, `attributes.jl`): no trait argument's object's type is known (a kept value's never is, `_known_object`), and every trait argument is `Compiled`: a `compiled_for`, a `Compiled{X}`, a `Kept{X}` holding `Compiled`, or a plain value at a `Compiled` position. The table's value is the object such a value holds (`_unconverted`).
- **Per entry position, a table** from the user's type to its implementation's builder, valid in a range of worlds: a declared implementation for the range of its dispatch, anything else for one world (`UTable`, `_umiss`). It is appended copy-on-write, and a table saved in an image is ignored in another session.
- **One trait position:** a table per entry pattern from the user's type to a `:caller_world` pointer ([compiler §3.1](compiler.md#31-the-cfunction-calling-convention-caller_world)) to the pattern's method specialized on the builder (`_pentry`). One call through it builds the views from the builder's data and calls the worker for the key. Several trait positions: the builders from each position's table, then one dynamic call on the builders' types.
- **The pattern's method** is compiled once per key, and compiled ahead per declared implementation ([§15.1](#151-compiling-ahead-from-declarations)).
- **A family member is served by the table** like a declared type: its builder enters the table after its member check (traits §4.7), valid for the worlds of the family method's dispatch.
- A type the table does not serve (a generic implementation, a position where containers cross) takes the generic path; a type without an implementation reaches the fallback as there.
- **The conversions of held values** (`compiled_for`, `with_dynamic`, `Kept{X}(d)`) call their constructors at the held value's concrete type, never at the `Any`-typed object it holds: in code compiled by facts such a call would be a run-time site. So `compiled_for(::Kept{X})` is a `Kept{X}`, and a crossing from trait code costs what one from plain code does.

---

## 10. Keywords, defaults and varargs

**Status: Implemented** (deviation [L-48](#18-deviations)); `Callable` with keywords **Planned** ([`traits.md#57-keywords-defaults-and-varargs`](traits.md#57-keywords-defaults-and-varargs)).

**The entry translates, the worker sorts:**
- The entry is its own keyword sorter, `Core.kwcall(@nospecialize(nt::NamedTuple), ::Core.Typeof(f), args…)`, beside `f(args…)`, which calls it with no keywords. Julia's sorter would be specialized on the named tuple of the supplied keywords, where `known_type` always sees their types. Unspecialized, the named tuple is as a positional argument is: a typed caller inlines the entry and sees the types, an untyped caller reaches the entry compiled at `NamedTuple` and does not.
- A bounded keyword, if supplied, is translated by `enter_kw`, which refuses a value that conforms to none of its traits (`TraitBoundError`, `entry.jl:534`), and decides its attribute as `enter` does. A `Callable` keyword by `enter_kw_callable`.
- `checked_kwcall(nt, f, views…)` calls `Core.kwcall(nt, f, views…)`: the worker's own keyword sorter, which Julia lowers from the worker's definition (`checks.jl:330`). It fills the defaults inside the worker, compiled by facts, so a default sees the trait objects.
- In the worker, a bounded keyword is typed `TObj` and a `Callable` keyword `CObj{A, S}`.

**Positional defaults** are expanded as Julia expands them: the full method, and one shorter method per default whose body calls the full one (`_expand_defaults`, `trait_module.jl:596`). Each is a bounded definition with its own worker and entry. The shorter worker calls the full worker with its trait objects.

**A trait vararg** `ts::X...` becomes a worker vararg whose elements each have their own `TObj{T} where T >: …`, so elements may differ in key. The entry translates each element (`enter_each`, `entry.jl:521`). The worker compiles per tuple of keys.

**An entry whose bounded methods take no keywords** has a keyword sorter too, `Core.kwcall(@nospecialize(nt::NamedTuple), ::Core.Typeof(f), args…)`, inlined and a boundary as the entry is. It translates nothing: it returns `kwfallback(nt, f, args…)`. So a call with keywords is sorted among the methods that take keywords, as Julia sorts it, and a value that conforms to the bound reaches the fallback too ([traits §5.7](traits.md#57-keywords-defaults-and-varargs)).

**Fallbacks with keywords** go through `kwfallback(nt, f, args…)` (`entry.jl`):
- with no keywords (an entry with keywords called without any), it is `fallback(f, args…)`: a call without keywords reaches every method, those without keywords included;
- otherwise the methods that take keywords, by their keyword sorters: the most specific tagged sorter, `Core.kwcall(nt, f, ::Untyped, …)`, chosen among the tagged ones alone and called by `invoke` where the call by dispatch is ambiguous (`_tagged_kwfallback`, as `_tagged_fallback`, [§8.1](#81-the-rewrite)); else the most specific ordinary method's sorter that is neither an entry's nor a worker's (`_plain_kwmethod`); else Julia's `MethodError` for the call with keywords, `f(::T; k::K)`;
- the hint naming a bound is added to that error only where a bounded method of `f` takes keywords (`_bound_hint`, `frames.jl`).

**Planned:** `Callable{A, S, K}`, the keywords' named-tuple type `K` part of the pointer's signature and of the worker's key.

---

## 11. Results like the input

**Status: Implemented** (deviation [L-16](#18-deviations)); listing the inverses for compiled-ahead builds **Planned**.

`f(t::X, …)::Like{t} = body` ([`traits.md#56-results-declared-types-like-withfields`](traits.md#56-results-declared-types-like-withfields)) is rewritten (`trait_module.jl:665`):
- the worker's body becomes `like(t, body)`, and each `return x` `return like(t, x)` (`_like_returns`);
- `f`'s type is recorded, so the check that no trait object goes up allows the pending result (`_like!`, `entry.jl:985`).

**The pending result** is `LikeResult(t, x, fields)`: the input's trait object, the new receiver or `KeepSelf()`, and replaced declared fields (`entry.jl:995`). `withfields(t; f = v)` makes one with fields only. Nothing operates on it.

**The entry inverts it** (`_like_out`, `entry.jl:1019`), for the argument whose trait object it names:
- a type that implements the operations itself: the new receiver, which must be of the same type family;
- otherwise: the user's object rebuilt by its type's constructor with the forwarding field and the replaced fields substituted (`_invert`, `_rebuild`, `entry.jl:1127`, `:1147`). The constructor recomputes the type's parameters, which gives siblings (`LSeries{Float64}` in, `LSeries{Float32}` out);
- a `Dynamic` in: the rebuilt object as a `Dynamic` of the same trait. At the erased key the inverse runs when the call runs, for the held object's type.

**A constructor operation on a `Dynamic`** returns a `Dynamic` of the new value (`_dyn_like`, `entry.jl:1158`).

**Where the caller knows the user's type** (`_like_return`, `entry.jl`), the inverse is compiled for it: the slots it replaces are read from the builder the type's declaration fixed (`_declared_builder`, a constant), and the type's constructor builds the result, so it has the type it builds. Elsewhere the inverse runs when the call runs (`_like_out`): a `Dynamic` or a kept value in, an untyped caller, two positions of one trait object type, a member of a family ([L-16](#18-deviations)).

---

## 12. `Callable` and `Dynamic{Callable}`

**Status: Implemented** ([`traits.md#58-callable-functions-at-a-declared-signature`](traits.md#58-callable-functions-at-a-declared-signature)).

`Callable` keeps a lowering of its own; it is not a `@trait` declaration. Its default attribute is `Dynamic`.

**In the worker,** a function argument is a `CObj{A, S, F}` (`core.jl:1216`). Calling it checks `args isa A` (`MethodError` otherwise) and asserts the result to `S`. The worker is compiled per `F`:
- `Dynamic`: `F = Erased{A, S}`, the same type for every function: one worker per signature;
- `Compiled`: `F` is the function's type: one worker per function type, the function's call inferred into it.

**At the entry,** `enter_callable(Callable{A, S}, attribute, f)` (`entry.jl`; deviation [L-36](#18-deviations)). The entry and its helpers (`_check_at_signature`, `_wrap_callable`, `_erased_at`, `_fptr`) are keyed by the bound, not by `A` and `S` apart: a type value whose parameters hold a `Union` (`Tuple{Union{Missing, Float64}}`) has no hash, and a package image keeps no code at a signature without one ([compiler §2.9](compiler.md#29-what-package-images-keep)); the bound has a hash. So an image whose workload entered a function at a signature keeps the entry, also where it was reached by a dynamic call.:
- a cast, `compiled_for(f)` or `with_dynamic(f)`, wins; it takes the position's signature;
- a kept function, `Dynamic{Callable{…}}`, `Compiled{Callable{…}}` or `Kept{Callable{…}}` at any signature: its attribute, carried; at another signature it is checked first, once per (signature, function type), a method at `A` whose inferred result meets `S` (`_check_at_signature`, else `TraitBoundError`; [traits §6.5](traits.md#65-values-carry)), and a `Dynamic` one becomes `CObj{A, S}(Erased{A, S}(f))` of its function (`_erased_at`);
- **argument types that follow the other arguments** ([traits §5.8](traits.md#58-callable-functions-at-a-declared-signature)): `_classify` keeps `A` and `S` as expressions over the `where` variables; the worker binds them by dispatch on `CObj{A, S}`, and checks a trait argument's parameter against them; the entry enters the function after the other arguments, a variable fixed by a plain argument from the entry's own `where` list, one fixed by a trait argument read from its key (`_trait_param`); a variable no other argument fixes is refused when the method is defined;
- otherwise: the position's attribute (`Compiled{Callable{A, S}}`), else `Callable`'s default `Dynamic` for a function whose type is not of the trait world (`_tw_type`, `entry.jl:1019`), else `Compiler.known_type(f)`;
- `Compiled`: `CObj{A, S}(f)`; `Dynamic`: `CObj{A, S}(Erased{A, S}(f))`;
- caches the wrapper per (signature, attribute, type) for functions that capture nothing.

**`Erased{A, S}`** (`core.jl:1216`) holds the function and a pointer to its code compiled for `A`:
- the pointer is a `cfunction` of the calling convention `:caller_world`: the call runs in the caller's world, through a world-checked cache in the pointer's thunk ([compiler §3.1, the `:caller_world` convention](compiler.md#31-the-cfunction-calling-convention-caller_world), `_fptr`);
- the callee is `_CallWrap{S}`, with fixed arities up to six, which calls the function and asserts `S`. Non-bits arguments go boxed. A `Dynamic{Y}` among `A` is passed as `Ref{Dynamic{Y}}` (`_cdecl`, `core.jl:1216`); a trait object at the erased key is converted to it first ([§13](#13-dynamicx), the seams);
- the function runs the code of its default owner, as every call through a `cfunction` does ([compiler §2.5](compiler.md#25-dispatch-from-facts-code), [§3.1](compiler.md#31-the-cfunction-calling-convention-caller_world)): plain code for a user's function, facts code for a function of a trait module;
- the pointer sits in a mutable cell. A package image saves it as null, and the first call in a session makes it again (`_PtrCell`).

**Several signatures** `f::(Callable{…}, Callable{…})`: a `CMulti` holding one `CObj` per signature; a call picks the first signature its argument types match, at compile time (`core.jl:1216`).

**Kept functions** (`entry.jl`, "`Callable`'s kept values"):
- **`Dynamic{Callable{A, S}}`** holds a `CObj{A, S, Erased{A, S}}`; its call reads the kept value at that asserted type and calls it, so the call stays typed. It adds a heap object and a load with a type assertion per call against a `CObj` held inline (measured with the gaps of [W-17](../record/todo.md)).
- **`Compiled{Callable{A, S}}`** holds the function itself; its call is `CObj{A, S}(f)(args…)::S`, a dispatch on the function's type.
- **`Kept{Callable{A, S}}`** holds either, with its attribute, and branches on it at each call.
- **Without a signature,** `Dynamic{Callable}`, `Compiled{Callable}` and `Kept{Callable}` hold the user's function itself (`_unsigned_dynamic`, and the branches for `C === Callable` in `_callable_dynamic`, `_callable_kept`); a call is the function's own call. `enter_callable` takes them as kept functions at another signature (above). A struct field written `Callable` is rewritten to `Kept{Callable}` (`_dyn_type`, `trait_module.jl`) ([traits §7.5](traits.md#75-functions-kept)).
- Their constructors take a plain function, a cast, a function argument (`CObj`) or a kept function, and keep its attribute; asked to change it they refuse (`_cast_refuse`). `compiled_for` and `with_dynamic` move the function between the forms (`_callable_fn`, `_erased_at`). `rewrap(g, f)` (`attributes.jl`) reads the user's function of a kept one by `_callable_fn` (the held object by `_dyn_object` for another trait) and casts `g` of it by the kept value's attribute ([traits §6.4](traits.md#64-casts)).

**In a closed build** every function is known, so nothing is erased: `CObj{A, S}(f)` (`entry.jl:1147`).

**An open result type** `Callable{A, S} where S`: a `where` variable that only the result names is a deferred `Callable`'s too (`_callable_args_use`); the entry binds the argument types' variables first, then `S = _callable_result(f, A)` (`entry.jl`): `Core.Compiler.return_type` of the function at `A`, plain inference's answer at run time ([facts §7](facts.md#return-type)), `Any` where it is `Union{}`; a constant where the function's type is known. `S` is then part of the worker's key (`CObj{A, S}`), asserted at every call.

---

## 13. `Dynamic{X}`

**Status: Implemented** (deviations [L-6](#18-deviations), [L-25](#18-deviations), [L-31](#18-deviations)); `Dynamic{(X, Y)}` **Planned** ([`traits.md#37-tuples-of-traits`](traits.md#37-tuples-of-traits)): a tuple of traits needs an encoding as a type parameter, since a tuple is not one.

**The representation:** three kept forms, each holding the user's object (`core.jl`):
- `struct Dynamic{X}; t::Any; end` and `struct Compiled{X}; t::Any; end`, one attribute each;
- `struct Kept{X}; t::Any; compiled::Bool; end`, the attribute as data: one concrete type, stored inline in a field or a `Vector{Kept{X}}`, made without allocation;
- `HeldValue{X} = Union{Compiled{X}, Dynamic{X}, Kept{X}}` names all three in method signatures (operations, fields, equality, the entry).

The view of `X` for the object's type is made where it is needed, by the builder that type's implementation fixed: a constant per pair, folded where the type is known.
- From a value, `Dynamic{X}(x)` and `Compiled{X}(x)` check that `x`'s type conforms (`TraitBoundError` otherwise) and hold `x`; `Kept{X}(x)` takes the trait's default (`default_attribute`).
- From a trait object, a constructor checks that it carries `X` (`ArgumentError` otherwise), narrows it to the views of `X` and its supertraits (`_narrow`), and holds the user's object the views read. `Dynamic{X}(t)` takes only a trait object at the erased key, `Compiled{X}(t)` only one at its key; `Kept{X}(t)` takes either and records the key's attribute.
- **Constructors never cast** (traits §6): on a kept value or a cast of the other attribute they raise `TraitBoundError` naming the cast (`_cast_refuse`). There is no `convert` between `Dynamic{X}` and `Compiled{X}`.
- A kept value holds the trait object itself in two cases, where there is no user's object to hold: the views hold only the parts of an immutable value (a worker that cannot keep received no whole object, [§8.4](#84-keeping)), and the new receiver value of a constructor operation (`_dyn_like`), which need not conform by itself.
- **Storing** a trait object, a kept value, a cast or a plain value where `Kept{X}` is declared converts it (`convert`, by `Kept{X}(t)`; a plain value takes the trait's default); storing into `Dynamic{X}` or `Compiled{X}` converts a trait object of that attribute and refuses the other.
- **At a bound:** the entry makes the trait object at the erased key of a `Dynamic` value's object (`_enter_erased`), and the trait object at its own key of a `Compiled` value's object (`_enter_compiled`; the table where the entry has one, [§9.3](#93-untyped-callers-of-compiled-values-the-table)); a `Kept{X}` by its attribute ([§8.2](#82-the-entry)).
- **Opening** (`opened`): the trait object of the kept value, made from the user's object as `Dynamic{X}(x)` would see it (whole object kept, so the worker may keep it), or the trait object held. The function that opens is a value of its own type (`_Open{X}()`), so an opening at an unknown type dispatches on the object alone.
- **The seams:** where a slot is typed `Dynamic{X}`, `Compiled{X}` or `Kept{X}` and a trait object of `X` arrives, it is converted by that type's constructor, keeping its attribute: an operation's argument (`opcall`'s check and `_seams` for an operation on a trait object; `_seam1`, one argument at a time, for an operation on a kept value), a `Callable`'s argument types `A` (the `CObj`'s check and `_cdecl`), a field or a container's item (`convert`), a `Like` result (`_like_out`, `_keep_as`: the input's form and attribute). A kept value becomes a trait object only at a bound.

**An operation on it** is the method `@trait` defined (`trait.jl`):

```julia
Base.@constprop :aggressive @inline op(d::HeldValue{X}, a…) where {X <: Trait} =
    Compiler.split_call(family(X), RT, _dynop(X, op), getfield(d, :t), a…)::RT
```

- `_dynop(X, op)` is `op` applied to the opened object, as a value of its own type (`_DynOp{X, F}`, one method per arity up to six, `core.jl:812`). The split is over the held object.
- `RT` is the declared result type, with the parameters the `Dynamic`'s type fixes substituted ([traits §7](traits.md#7-kept-values-dynamicx-compiledx-keptx)). Where it names `Self`, or a parameter the type leaves open, it is `Any`. It is computed where the call is compiled: `_erased_ft(op_ret(X, op, _erased_key_of(X), N))`, a constant, as a declared field's type is (`_dyn_getprop`).
- Julia infers the call at the union of the family's registered **candidates**, the first four, plus a fallback, and splits it as a union: `isa` branches on the held object's type, in each the view folded and the operation's method called directly. The last branch calls the target for the object's type through the table of the call's signature, its result asserted to `RT` ([compiler §4.2, the call-site split](compiler.md#42-compilersplit_call-the-call-site-split); [§4.3, the table](compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)).
- `@constprop :aggressive` makes each caller infer the call again, so it splits over the candidates registered when it is compiled.
- The fallback dispatches in the caller's world. A type outside the four costs one probe and an indirect call, at any number of implementations, and allocates nothing for a concrete `RT`.
- An operation whose result is `Self` returns a kept value of the new value instead, of the receiver's form and attribute (`_dyn_like`, `_like_held`).

**Which candidates a caller splits over** is fixed when the caller is compiled ([compiler §4.2](compiler.md#42-compilersplit_call-the-call-site-split)). So a worker at the erased key compiled into a package image splits over the implementations registered while that image was built, that package's and its dependencies'; a user's type takes the fallback at every operation. Code compiled in the session splits over the first four declared. A type outside the split takes the table, whose cost does not depend on the number of implementations.

**Candidates** are the types a `Dynamic` holds: the implementations' types (and, in the two cases above, trait-object types), registered with `Compiler.register_dynamic_candidate!` without an edge:
- **at each declaration and each package load,** for each implementation at a concrete type, from the `implementation` and `projection` records (`_note_conformances!`, `core.jl:897`). Each batch is registered in **declaration order:** by the declaration's file, then line. The records carry the `@implement`'s own line (`_at_declaration`, `implement.jl:1205`), so a session that loads a package image registers its types in the order the image's code was compiled for. *As built,* a family member is registered only when a `Dynamic` of it is made ([L-25](#18-deviations));
- **when a `Dynamic` is made,** its object's type: once per type and session, through a flag per pair that the constructor's code holds as a constant (`_cand_flag`, `core.jl:749`), not by a search of the registry.

A later implementation reaches the fallback and invalidates nothing.

**Seeing a value of unknown type** (an item read from a `Vector{Any}`): `@kept_of X x attr` (`core.jl`) keeps a value that carries its attribute (`isa` tests on the kept forms and the casts), and for a plain value splits the conformance check over the same candidates (`_ConformsTo{X}`), folded to a constant for each. It makes the `Kept{X}` by an `invoke` of its constructor at `(Val{:checked}, Any, Bool)`, a fact, so `x` is held in the box it came in and nothing is allocated. Any other type is checked by a dynamic call. BaseTraits' views do this at each read ([§13.1](#131-a-users-container-crossing-by-its-bound)). `@dynamic_of X x` makes a `Dynamic{X}` likewise.

**The casts** (`attributes.jl`): `compiled_for(d)` of a `Dynamic{X}` is a `Compiled{X}` of the same object, of a `Kept{X}` a `Kept{X}` holding `Compiled`; `with_dynamic` the reverse. On a trait object at the erased key, `compiled_for` opens it and passes the trait object, typed `Any`, to the next call, which dispatches on its type, so it selects the worker for the key once.

**Fields:** a declared field read on a kept value or on a trait object at the erased key goes through the same split as an operation: each branch reads the candidate's slot ([§6](#6-trait-objects-layout-fields-writes)), the fallback reads through the opened trait object, and the result is asserted to the declared field type, or the parameter value fixed. A write is split the same way.

**Equality, hashing, printing:** `==` on the held user's objects (or the trait objects held), across the three forms; `hash` agrees, with one salt; `===` differs by form and attribute. They print `Dynamic{X} at <key>`, `Compiled{X} at <key>`, `Kept{X}: Compiled at <key>` (`_dyn_identity`).

### 13.1 A user's container crossing by its bound

**Status: Implemented** (deviation [L-27](#18-deviations); [traits §8.2–§8.3](traits.md#83-a-users-container-taken-as-it-is)).

- **Item positions:** a trait's name in a bound's parameter becomes the tag `Through{Y, A}` in the worker's trait set, with `A` the item parameter's attribute, a symbol (`:default`, `:compiled`, `:dynamic`). A trait object's set has a `Through{Y, A}` tag, for every `A`, where its item type is a kept value of `Y` (`Dynamic{Y}`, `Compiled{Y}`, `Kept{Y}`) or a trait object carrying `Y` (`_kept_item`, `_through_variants`, `core.jl`). So one worker signature accepts both views and a container of kept values.
- **What a position asks:** `crossing(EntryPos{F, pos, nargs}())` is fixed with `needed` at the trait module's end (`_fix_crossing!`, `trait_module.jl:1123`; `crossing_at`, `entry.jl:492`): a `Crossing{Y, R}` where the workers' bounds at the position name item positions of one trait `Y`, with `R`, for each worker, the parameter tags its bound requires. Elsewhere, the fallback method: `nothing`, folded.
- **At the entry** (`enter`, `entry.jl:213`): if the position has a `Crossing` and `t`'s type is known to cross, `t` is replaced by `crossed(Y, t)` and only its view's trait object is assembled. Otherwise the trait object `v` of `t` is assembled, and the first call for the type decides; a container that crosses is then not assembled as it is again (under `all`, a `Dict{String, Any}` fails the `Iterable` family's check, and its slow path would run at each call).
- **Whether `t` crosses** (`_crosses`, `entry.jl:452`): its trait object meets none of the tag sets in `R`, and the view's does. Decided once per crossing and container type, in a flag the entry's code holds as a constant (a family member's trait object, every Base container's, has a type known only when it is built). The flag is not stamped: a decision saved in an image stands in the next session. It depends only on types the image's dependencies define. The decision is machinery (`_cross_decide`), listed by `verify_main` as a guard. A container of kept values of `Y` meets the bound as it is, without a view (`_cross_view`).
- **The view** is BaseTraits' `crossed(Y, t)` (`BaseTraits.jl:174`), chosen by the item type and the attribute:

| Item type of the container | no attribute | `Compiled` | `Dynamic` |
|---|---|---|---|
| a concrete type that conforms to `Y` | `CompiledItems{Y}(t)`: each read the item's trait object at its key, folded | `CompiledItems{Y}(t)` | `DynamicItems{Y}(t)` |
| `Any`, an abstract type, a union with such a member | `DynamicItems{Y}(t)`: each read a `Kept{Y}` (`@kept_of`), a plain item `Dynamic` | `CompiledItems{Y}(t)`: each read a `Kept{Y}`, a plain item `Compiled` | `DynamicItems{Y}(t)` |
| `Dynamic{Y}`, `Compiled{Y}`, `Kept{Y}` | none: met as it is (they carry) | none | none |

  For a dictionary, `CompiledValues` and `DynamicValues` likewise. Another item type (`Vector{Float64}` for `Iterable{Shape}`): `nothing`, and the value stays as it is, refused as one that conforms at other parameters.
- **The item type the worker sees** is the view's item type: the item's trait object at its key for `CompiledItems` at a concrete item type; `Kept{Y}` at an abstract item type, for both views. Definition checking reads it at the archetype as the trait object of `Y` at the archetype's key.
- **Reads and writes:** each read sees the item (`@kept_of`); a write stores what reads back as the same value with the same attribute (`_written`, `BaseTraits.jl`): the user's object, split over the candidates so that `setindex!` on the user's container is a call at a concrete type, where a plain item of the view reads with that attribute; else plain code's cast of it, `compiled_for(o)` or `with_dynamic(o)`; a container that cannot hold the cast refuses it (`TraitBoundError`).
- **Untyped callers:** the container itself is `Dynamic` at the position (the trait object of `Iterable` at the erased key); its plain items, of a type unknown to the code, are `Dynamic` unless the attribute says `Compiled`.

**A trait's name as a type inside a trait module** means `Kept{X}`; `Dynamic{X}`, `Compiled{X}` and `Kept{X}` written out are left as they are, plain types. The module's statements are rewritten (deviation [L-6](#18-deviations)):
- struct fields: `model::Model` becomes `Kept{Model}`, also inside parameters, not inside `<:` (`_dynamic_fields`, `_dyn_type`, `trait_module.jl`);
- containers in bodies: `Column[]`, `Vector{Column}(undef, n)` become containers of `Kept{Column}` (`_dyn_body`); `Dynamic{X}(t)`, `Dynamic{X}[]`, `Kept{X}` and type assertions with them are left as they are;
- containers in argument types: `cs::Vector{Column}` becomes `Vector{<:HeldValue{Column}}`, so a container of any held form is taken (`_dyn_sig`);
- a trait's name directly on an argument stays a bound; under `<:` in a struct's parameters it bounds the parameter ([§13.2](#132-a-struct-parameter-bounded-by-a-trait)).

### 13.2 A struct parameter bounded by a trait

**Status: Implemented** ([traits §7.4](traits.md#74-a-struct-parameter-bounded-by-a-trait)).

The rewrite of a struct in a trait module (`_bounded_struct`, `trait_module.jl`):
- **finds** each parameter whose upper bound names a trait or `Callable` (`_istraitbound`), and strips the bound from the header;
- **writes Julia's constructor with explicit parameters** out as an inner constructor, `S{P…}(fields…) = new{P…}(fields…)`, so Julia defines no default outer constructor;
- **defines the constructor without parameters** as a boundary (`Expr(:meta, :facts_boundary)`, inlined into its caller): each field typed by a bounded parameter is an argument `@nospecialize`d, as an entry's, and kept by `_kept_at(B, x, Val(Compiler.known_type(x)))` (`entry.jl`); every other field keeps its declared type, whose `where` variables determine the struct's free parameters; the result is `S{…, typeof(kept)…}(…)`;
- **registers** `bounded_constructor(S)`, so that the check of rule 3 lets trait code pass a trait object to the constructor;
- **defines `getproperty`** for a field bounded by `Callable{A, S}` (`@constprop :aggressive`, inlined): `_read_kept(B, getfield(s, f))` (`entry.jl`) gives a `Dynamic{Callable{A, S}}` as it is and the function itself as `CObj{A, S}(f)`, the function argument that `enter_callable` and `_kept_at` take as `Compiled`; every other field is `getfield`. The field check of an implementation (`_field_problems`, `implement.jl`) does not count this method as the type's own `getproperty` (it knows it by its file) ([traits §7.4](traits.md#74-a-struct-parameter-bounded-by-a-trait), [T-89](traits.md#17-deviations)).

`_kept_at` applies the bound: for `Callable{A, S}`, `enter_callable` at the position, then the function itself (`Compiled`) or a `Dynamic{Callable{A, S}}`; for a trait `X`, a trait object by its key, a kept value or a cast by its attribute, a plain value by the first-seen rule (the trait's default, `@default_with_dynamic_self` only for a type not of the trait world, then `known`), then the user's object (`Compiled`, a kept value's opened by its type at this call) or a `Dynamic{X}`. A free parameter that no other field names but a bound names as a parameter (`C <: Column{T}`): the field is kept at the trait's family first (`_kept_at(Column, x, …)`), the parameter read from the kept value (`_kept_param`, by `_trait_param` of its trait object, `core.jl`), and the value kept at the bound (`_kept_narrowed`: a `Dynamic{Column}` narrowed to `Dynamic{Column{T}}`, holding the same object). It refuses, at the definition, a bounded parameter that types two fields, or a field that uses it inside another type, or a free parameter named by no other field and by no bound.

**Planned:** `Dynamic{(X, Y)}`, a value seen through several traits.


---

## 14. Checks, and where their results live

**Status: Implemented** (deviation [L-10](#18-deviations)). What each check means and raises is [`traits.md#9-checks-and-when-they-run`](traits.md#9-checks-and-when-they-run); here is where it runs and what is kept.

| When | What runs | Code | Kept |
|---|---|---|---|
| `@trait` | the form of the body | the macro (`trait.jl:251`) | — |
| `@implement`, expansion | the form; refusal of a redeclaration; ownership of an operation's function before any method is defined | `_implement_expand`, `_op_method` (`implement.jl:1192`, `:991`) | — |
| `@implement`, top level | ownership and delegation; completeness; result types by inference; fields; concreteness; supertraits implemented; overrides so far | `_check_implementation_now`, `_check_projection_now`, `_check_own_fields_now`, `_declare_conformance_now` (`implement.jl:533`–`672`) | the declaration's records, not the checks' results |
| a method definition | an override after an implementation; strict mode; keep flags of a complete module | the definition hook ([§16](#16-sessions-loads-and-hooks)) | — |
| an image's activation | overrides and, in strict mode, winning pirates left inactive | the image hook | reported after the load |
| a trait module's statement | ownership of each new method; no plain method in an entry's place | `_check_methods`, `_check_entries_intact` (`trait_module.jl:1048`, `:1063`) | — |
| a trait module's end | needs and keep flags fixed; overrides; joint methods; ambiguities; definition checking | `_finish_module` (`trait_module.jl:1146`) | `needed` and `keeps` methods, in the module's image |
| a worker signature's first call | no worker at these parameters; overrides; the rules at the real signature, unless checked at the definition; fully typed mode | `_check_once` (`checks.jl:381`) | a flag embedded in the signature's compiled code; while an image is built, a record of the pass with the worker methods it checked (`__tw_checked__`) |
| every call at the entry | conformance; bounded keywords; a family member's concreteness | [§8.2](#82-the-entry) | — |
| every operation call | arguments and result | `opcall` | — |
| every `Callable` call | arguments and result | `CObj` | — |

**Definition checking** (`check_definitions`, `defcheck.jl:168`) infers each worker once at **archetypes**, which stand for every key, the erased key included, so the worker at the erased key needs no check of its own: a stand-in key per bound, `Archetype{X, P}` with `P` the parameters the bound fixes, whose views have the witness `ArchWit` (`defcheck.jl:18`, `:73`). At `ArchWit` an operation and a field return an opaque value asserted to the declared type, and nothing more (`defcheck.jl:44`). The rules are checked on the inferred code (`worker_problems`, `checks.jl:107`).
- The rule check reflects the worker with the default interpreter: at archetypes, facts inference in the facts cache. An archetype never runs, so no code the program calls comes from it. The keep analysis ([§8.4](#84-keeping)) and the result-type checks infer plainly, at archetypes in the checks' own cache (`_CheckOwner`).
- While a package is precompiled, a problem fails the build. Elsewhere it warns, and the first call raises.
- Methods checked clean are recorded: for the session (`_DEF_CHECKED`), and while the trait module's image is built in the module (`__tw_def_checked__`). Their workers' first calls skip the rule check, in the session and in every session that loads the image. A redefined method is another `Method`, so it is checked again.
- **Intended:** only a bound with an open parameter and a `Callable` with an open result type wait for the first call. **As built,** keyword workers, vararg workers and every worker with a `Callable` argument wait too (`defcheck.jl:93`–`105`; [L-10](#18-deviations)).

**The first-call check** (`checked_call`, `checks.jl:294`) is a generated function. Each worker signature gets its own flag, a `Ref` embedded in its compiled code. The check runs once per signature, through `invokelatest`, behind an inference barrier, so compiled code holds no edge to it. Its rule check reflects the worker with the default interpreter: for a facts method that is facts inference, the code that runs, kept with it.

**The records of checks kept with the code they checked** (`ahead.jl`, the facts-first review §2.4):
- A first-call check that passes while a package image is built is recorded in a module of that image that the signature names (its function's, or a type's), as the signature with the worker methods dispatch selects there (`__tw_checked__`). `@implement`'s compiling ahead records its checks the same way.
- A first call looks the record up in the modules its signature names, lazily: no walk over the loaded modules at a load.
- The record holds while dispatch selects the same worker methods: a redefined worker is checked again.

**Fully typed mode** runs in the first-call check (`_check_fully_typed`, `concrete.jl`): abstract values traced to their root causes, and the fully-typed certificate ([§15](#15-compiling-ahead-workloads-closed-builds)). Its level is a constant `__tw_concrete__` of the module, or a `concrete_level(::typeof(f))` method for one function.

**Kept in images:**
- the declarations' records, builders and `conformance` methods;
- each trait module's `needed` and `keeps` methods;
- `__tw_checked__`: the worker signatures whose first-call check passed while the image was built, in the conforming type's module when that module is the one being precompiled, else the declaring module ([§15](#15-compiling-ahead-workloads-closed-builds));
- family registries filled by the workload.

**Not kept:** the slow path's caches, the `Callable` wrapper cache, `Erased` pointers.

---

## 15. Compiling ahead, workloads, closed builds

### 15.1 Compiling ahead from declarations

**Status: Implemented** (deviation [L-15](#18-deviations)).

While a package that declares `@implement X T` is precompiled (`_compile_ahead`, `ahead.jl:16`), for each fixed-arity entry position known at that point whose needs include `X` (`_compile_ahead_now`, `ahead.jl:122`):
- **the workers** whose only trait position is that one and whose other arguments are concrete ([traits §13](traits.md#13-compiling-ahead): a function with several trait positions is compiled at its first call), at the trait object of `T`'s builder. Each one's first-call check runs now, a failure fails the build, and the signature is added to `__tw_checked__` (`_check_ahead!`, `ahead.jl:57`);

- **the table's pattern method** at `T`'s builder, for untyped callers of `Compiled` values ([§9.3](#93-untyped-callers-of-compiled-values-the-table)).

**The positions known** are read from TraitWorld's records, not from modules' bindings (`_entry_positions`, `ahead.jl:94`): each position whose needs a trait module's end fixed is a method of `needed` defined in that module ([§8.3](#83-needs-and-the-modules-end)); the positions of the declaring module, and of the trait modules around it, are read from their `__tw_positions__`, since they may not have reached their end. So the build reads no binding of other modules, deprecated ones included.

**The worker at the erased key** is not compiled from declarations: no key of `T` names it. A workload that reaches it compiles it into the image ([§15.2](#152-workloads)), where it splits over the candidates registered then ([§13](#13-dynamicx)).

The list is exact because implementations are declared. A load of the image adds its `__tw_checked__` to the session's set (`_note_checked_ahead!`, `ahead.jl:29`).

`JULIA_TW_AHEAD=0` turns it off.

### 15.2 Workloads

**Status: Implemented.**

`TraitWorld.@workload begin … end` fixes the trait module's needs and keep flags first (`_finish_needed`), then runs PrecompileTools' `@compile_workload` (`TraitWorld.jl:169`). So the workload compiles the entries as they stay.

### 15.3 `verify_main`, `fully_typed`, closed builds

**Status: Implemented** (deviation [L-14](#18-deviations)).

**`verify_main(main, argtypes; entrypoints)`** (`verify.jl:933`) walks the optimized code reachable from `main`. It classifies every call:
- **static:** an `invoke`;
- **bounded:** a dynamic call with finitely many known targets;
- **trait:** a step of the machinery, with targets enumerated from the argument types and the declared implementations: the builder per user type, the worker per signature, a function's wrapper, the operations on `Dynamic` values per trait-object type the program keeps; at the erased key, every declared implementation as a target ([L-35](#18-deviations)) of the split's fallback and of the entry's conformance check;
- **guard:** the machinery's slow paths, not followed (`_machinery_method`, `verify.jl:491`);
- **hole:** anything else, marked when it lies only on a path to an uncaught throw.

It runs the rule check of every enumerated worker. With `entrypoints = true` it registers every target with `Base.Experimental.entrypoint`.

**A closed build** (`entrypoints = true` under `--trim`) closes the world (`close_world!`, `verify.jl:1065`):
- the slow path's cache is filled from the walk's plans;
- `CLOSED_WORLD` is set: the first-call checks are skipped (they ran at build time), a slow-path miss raises, and `Callable` arguments are not erased;
- under `--trim` the facts mode is off ([`facts.md#closed-builds`](facts.md#closed-builds)).

**`fully_typed(f, argtypes)`** (`certificate.jl:33`) is `verify_main`'s walk from a call of `f` at the argument types: the holes on normal paths are the run-time sites; operations on `Dynamic` values count as declared sites.

**Planned:** the inverses of `Like` results among the targets; a lint for calls reached from trait code that select a pirate.

---

## 16. Sessions, loads and hooks

**Status: Implemented** (deviation [L-18](#18-deviations)).

**At TraitWorld's load** (`__init__`, `TraitWorld.jl:22`):
- a new session stamp, which makes the flags saved in images stale (candidate registrations, the untyped tables, BaseTraits' hold flags);
- the method-definition and image hooks ([compiler §5.1, the definition and image hooks](compiler.md#51-method-definition-and-image-activation-hooks)), and keep-compiled for images built in this process;
- strict mode from `JULIA_TW_STRICT`;
- the type printers for `TObj`, `CObj` and `Builder` ([compiler §5.3, type printers](compiler.md#53-type-printers)): a trait object's type prints by bound and key, `at Dynamic` at the erased key;
- a filter that hides TraitWorld's frames in backtraces, through Base's `update_stackframes_callback` (`frames.jl:48`);
- an error hint naming the bound for a `MethodError` at a bounded position;
- a package callback.

**After every package load** (`_on_package_load`, `TraitWorld.jl:50`, compiled by facts): the candidates of newly loaded implementations are registered, the image's `__tw_checked__` is read, known delegates are noted, and refused methods are reported.

**The definition hook** (`_on_method_definition`, `hooks.jl:180`), compiled by facts:
- refuses an override of an operation a fixed implementation serves by a default;
- in strict mode, refuses a pirate that would win at a fact of compiled trait code. Before the definition it reads Julia's backedges; after it, Julia's invalidation log as a safety net, deleting the method again if trait code was invalidated by a non-stakeholder (`strict.jl:1`);
- recomputes the keep flags of a complete trait module that gains a method of trait-module code; a method defined outside trait code (a user's implementation at the prompt) changes none, since the keep analysis follows only trait-module code (TraitWorld 003ce8f).

**The image hook** (`_on_image_methods`, `hooks.jl:254`) leaves an image's overriding methods, and in strict mode its winning pirates, inactive, and reports them after the load.

**Planned, for strict mode's intended design:** a deletion hook, a read-only query of what a definition would invalidate, and image validation naming the winning method, in place of reading backedges ([compiler §5.4](compiler.md#54-planned-hooks-for-strict-modes-intended-design)).

---

## 17. Encodings until traits are in the type system

**Status: Implemented** as encodings; their removal **Planned**, last ([compiler §7, traits in the type system](compiler.md#7-traits-in-the-type-system)).

Julia has no trait in its type system, so TraitWorld encodes what membership as subtyping and a trait dispatch tier would give. Each encoding is a deviation:

| Encoding | Stands in for | Where | ID |
|---|---|---|---|
| the trait type carries the key as its last parameter, `X{P…, Self}`; trait instances `X{p…, K}` | a trait `X{P…}`, the key a parameter of the view only | `trait.jl:259`, `core.jl:379` | [L-1](#18-deviations) |
| trait sets as families plus `PTag{F, i, v}`; workers on `TObj{T} where T >: Union{…}` | a bound as a type in the method's signature | `core.jl:211`, `trait_module.jl:766` | [L-2](#18-deviations) |
| entries as methods at `Any` per shape, with the `Untyped` tag for fallbacks and hand-written joint-method and ambiguity checks | a trait bound as a dispatch tier above `Any` and below every type; entries and workers generated by the compiler | `trait_module.jl:824`, `entry.jl:28`, `trait_module.jl:1193`, `:1242` | [L-3](#18-deviations) |
| registries as methods of `@max_methods 1` functions with fallback (sentinel) methods, and the dispatch tokens `As{X}`, `EntryPos`, `TraitList`, `KeepOf` | declarations the type system holds, read without edges | `core.jl:366`–`1038`, `entry.jl:112`–`408`, `implement.jl:28`, `:57` | [L-4](#18-deviations) |
| `conforms(T, X)` | `T <: X`, `x isa X` | `entry.jl:1183` | [L-5](#18-deviations) |
| a trait's name as `Kept` inside trait modules, by rewriting their source; a struct parameter's trait bound stripped and applied by a generated constructor | a trait's name as an abstract type in any field or container; a trait as a parameter's bound | `trait_module.jl` (`_dynamic_fields`, `_dyn_body`, `_bounded_struct`) | [L-6](#18-deviations) |
| attributes as annotation types read by the rewrite, `Compiled{X}`, `Dynamic{X}`; item positions as the tag `Through{Y, A}`; the conversions as wrapper types `CompiledFor`, `WithDynamic` | an attribute on a bound, and a bound on a parameter, in the type system | `trait_module.jl` (`_classify`), `core.jl` | [L-2](#18-deviations) |

The meanings are permanent ([`traits.md#14-membership`](traits.md#14-membership)); only these forms go.

**What removes each encoding** ([compiler §7](compiler.md#7-traits-in-the-type-system); the stages are W-98 to W-114, revised by [the work plan](../plans/2026-11-06-work-plan-under-the-draft-reference.md)):

| Encoding | Removed by | Work item |
|---|---|---|
| `conforms(T, X)` (L-5); registries for memberships (L-4, the membership half) | memberships in the type system ([compiler §7.2](compiler.md#72-memberships)) | W-98 |
| entries at `Any`, the `Untyped` fallback, the hand-written joint-method and ambiguity checks (L-3; and L-47, L-48, L-50) | one dispatch ([compiler §7.3](compiler.md#73-one-dispatch)) | W-99 |
| the key as the trait type's last parameter (L-1); trait sets as families and tags, workers on `TObj` (L-2); attributes as annotation types read by the rewrite (L-2); views and witnesses (§5, §6) | keys as compilation signatures, attributes as the choice of compilation signature ([compiler §7.5](compiler.md#75-keys-attributes-and-the-check)) | W-109 to W-111 |
| a trait's name as `Kept` by rewriting a module's source (L-6) | `Kept{X}` a Core type; a set's name in a field means it ([compiler §7.5](compiler.md#75-keys-attributes-and-the-check)) | W-106, W-108 |
| the remaining registries and dispatch tokens (L-4) | declarations the runtime holds; the printer registry by the key's own printing | W-108, W-114 |

---

## 18. Deviations

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-1 | [§3](#3-trait-declarations), [§5](#5-keys-and-views) | a trait is `X{P…}`; the key is a parameter of the view | the trait type has the key as its last parameter, `X{P…, Self}`; trait instances name the key | `TraitWorld/src/trait.jl:198`, `core.jl:379` |
| L-2 | [§5](#5-keys-and-views) | a bound is a type in the worker's signature | trait sets are unions of families and `PTag`s; workers take `TObj{T} where T >: Union{…}` | `core.jl:211`, `trait_module.jl:766` |
| L-3 | [§8.1](#81-the-rewrite), [§17](#17-encodings-until-traits-are-in-the-type-system) | a trait bound is a dispatch tier; entries are generated by the compiler | entries are methods at `Any` per shape; the fallback is tagged `Untyped`; joint methods and ambiguities are checked by hand; so an untyped fallback of a bounded method's shape must be defined after the bounded methods (a type's constructor at the entry's signature is the exception: it is taken over as the fallback, [L-50](#18-deviations) in a package image), and only a function's owner may add a bounded method of a shape the function has none of yet (traits §5.5 states the rule as ownership alone). The shape includes the ordinary arguments' declared types, so a package that owns a type cannot add a bounded method naming it to another package's function that has a bounded method of the same trait positions: `__init(prob::ODEProblemTrait, alg::MyAlg)` from a solver package is refused beside the core's `__init(prob::ODEProblemTrait, alg)` (E-156 P14; W-36, part of W-34) | `trait_module.jl:696`, `:824`–`791`, `:1193`, `:1242` |
| L-4 | [§3](#3-trait-declarations), [§17](#17-encodings-until-traits-are-in-the-type-system) | declarations read without edges | registries are methods of `@max_methods 1` functions, some with sentinel fallbacks ([§3](#3-trait-declarations) lists them). No edge is recorded only where at least two methods apply. Where exactly one does (by reading Julia's `max_methods` rule; not run), inference infers it with an edge for the abstract signature, and the first declaration whose method intersects that signature invalidates the code: a tabled entry's `conformance(As{X}(), ::Any)` compiled while `X` has no declared implementation; a specialized entry inlined into a plain caller at an abstract type that no declared implementation's type intersects; a record function without a sentinel, at its one method; `keeps` and `needed` before the module's end (intended: the module redefines them). Measured for `conforms` (E-254, [traits §14](traits.md#14-membership): compiled code never folds a membership test to `false`): in the product setting a plain `Main` caller of `conforms(typeof(x), X)` is inferred through it at constant types, with edges to `implementation` and `proj_lookup` at `(X, S)`; it folds the negative answer, and `@implement X S` invalidates 11 MethodInstances and compiles the caller again. Under `all` the call is a run-time site with no edge. | `core.jl:366`–`1038`, `entry.jl:114`, `:193`, `:408`, `implement.jl:28`, `:57`, `:657`, `untyped.jl:108`; `experiments/w83/u8/` |
| L-5 | [§17](#17-encodings-until-traits-are-in-the-type-system) | membership is `T <: X` | `conforms(T, X)` | `entry.jl:1183` |
| L-6 | [§13](#13-dynamicx) | a trait's name as a type means `Kept{X}`, a value with its attribute | only inside trait modules, by rewriting struct fields, containers and argument types | `trait_module.jl` (`_dynamic_fields`, `_dyn_body`, `_dyn_sig`) |
| L-7 | [§4.1](#41-what-every-form-defines), [§4.4](#44-forwarding-with-by) | forwarding is written with `by` and recorded as forwarding | `by f` is lowered to a projection `project(t) = getfield(t, :f)`; a written `project(t) = t.f` is accepted as forwarding; TraitWorld's own precompile workload and tests use `project(t) = …` and the `{R}` spelling | `implement.jl:1106`, `:1584`–`1591`; `TraitWorld.jl:95`, `:110`–`106`; `test/runtests.jl:50` |
| L-8 | — | *Retired*: see [§13](#13-dynamicx). | — | — |
| L-9 | — | *Retired*: see [§14](#14-checks-and-where-their-results-live), the records. | — | — |
| L-10 | [§14](#14-checks-and-where-their-results-live) | only open parameters and open `Callable` result types wait for the first call | keyword workers, vararg workers and every worker with a `Callable` argument wait too | `defcheck.jl:93`, `:98`, `:102` |
| L-11 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-12 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-13 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-14 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-15 | [§15.1](#151-compiling-ahead-from-declarations) | the workers of every bounded function with one trait position whose bound includes `X` are compiled ahead, where the other arguments are concrete | vararg positions are skipped; so are entries with several trait positions: no worker, no pattern method and no entry method is compiled ahead for them | `ahead.jl:128`, `:140`, `:160` |
| L-16 | [§11](#11-results-like-the-input) | the inverse is compiled for the caller's type, and its result has that type | for a member of a family implementation, the inverse runs behind an inference barrier (its builder is found at its first use, not a constant of a declaration), and a typed caller's result is `Any` | `entry.jl` (`_like_return`, `_like_typed`) |
| L-17 | — | *Retired*: see [§2](#2-modes-owners-and-images) and [facts §6.4](facts.md#the-compilers-own-code). | — | — |
| L-18 | [§16](#16-sessions-loads-and-hooks) | strict mode asks Julia what a definition would invalidate ([compiler §5.4](compiler.md#54-planned-hooks-for-strict-modes-intended-design)) | it reads backedges before the definition and the invalidation log after it, deleting the method again on a miss | `strict.jl:1`–`14`, `:123`, `:265` |
| L-19 | [§3](#3-trait-declarations) | a trait's body holds operations, defaults, fields, equations and concreteness lines ([`traits.md#1-syntax-summary`](traits.md#1-syntax-summary)) | `@mutating` is accepted in a trait's body and recorded as `is_mutating`, which no code reads | `trait.jl:395`; `implement.jl:157` |
| L-20 | — | *Retired*: see [§13](#13-dynamicx). | — | — |
| L-21 | — | *Retired*: see [traits §6.7](traits.md#67-what-compiled-code-is-compiled-for) and [§5](#5-keys-and-views). | — | — |
| L-22 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-23 | — | *Retired*: see [§4.6](#46-families). | — | — |
| L-24 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-25 | [§13](#13-dynamicx) | Candidates are registered for each declared implementation at a concrete type, after each declaration and each package load. | Types with an `implementation` or a `projection` record at a concrete type are registered then (types that forward, or conform by a field mapping, included). A family member's record has a `UnionAll` signature: it is registered only when a `Dynamic` of such a value is made, and code compiled before that takes the fallback for it. | `TraitWorld/src/core.jl` (`_note_conformances!`) |
| L-26 | [§4.5](#45-field-mappings-several-traits-stated-parameters) | A stated value for a parameter an equation defines is checked against the equation and makes no method. | For one type: checked, and no method is made when it agrees (`_param_agrees`). For a family: it becomes a `param` method with the family's `where`, replacing the equation's value, unchecked. As [traits T-37](traits.md#17-deviations). | `implement.jl` (`_param_methods`) |

| L-27 | [§13.1](#131-a-users-container-crossing-by-its-bound) | A closed build lists and fills everything an entry can reach. | The crossing's decision (`_cross_decide`) is reflection run at the first call per container type; `verify_main` lists it as a guard, and `close_world!` does not fill its flags, so in a closed build the first call of a crossing position would need it. Not tried with `--trim`. | `entry.jl:452`; `verify.jl:520` |
| L-28 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-29 | — | *Retired*: see [§5](#5-keys-and-views). | — | — |
| L-30 | — | *Retired*: see [§12](#12-callable-and-dynamiccallable). | — | — |
| L-31 | [§13](#13-dynamicx) | a trait object reaching a `Callable`'s argument declared `Dynamic{X}` is converted (the seams) | the conversion is made for an operation's arguments only (`_seams` in `opcall`); a `CObj`'s check `args isa A` refuses a trait object where `A` declares `Dynamic{X}`: pass `Dynamic{X}(t)` | `TraitWorld/src/core.jl` (`CObj`'s call), `src/attributes.jl` (`_seams`) |
| L-32 | — | *Retired*: see [§4](#4-implementations). | — | — |
| L-33 | — | *Retired*: see [§13.1](#131-a-users-container-crossing-by-its-bound). | — | — |
| L-34 | — | *Retired*: see [§8.3](#83-needs-and-the-modules-end). | — | — |
| L-35 | [§15.3](#153-verify_main-fully_typed-closed-builds) | `verify_main` lists, at the erased key, every declared implementation as a target of the split's fallback and of the entry's conformance check | not done: for a program with untyped calls `verify_main` reports the program's run-time sites as holes; a closed build of code at a `Dynamic` position is not tried | `TraitWorld/src/verify.jl` |
| L-36 | [§12](#12-callable-and-dynamiccallable), [§8.2](#82-the-entry) | an entry inlined into a typed caller runs at plain speed, a `Callable` argument included: the function's form decided where the call is compiled | `enter_callable` is `@noinline` with the function and the attribute unspecialized, so its result is `Any` even where the caller knows the function's type, and the worker's call after it is a dynamic dispatch with an `Any` result (seen in `code_typed`; measured by E-192 in [W-17](../record/todo.md)) | `entry.jl` (`enter_callable`) |
| L-37 | — | *Retired*: see [§4.6](#46-families). | — | — |
| L-38 | [§4.6](#46-families) | a family's registry is found again after an image loads, by a lookup that is the declaring module's own | `_family_registry(::Val{name}, ::Val{module})` is a method of TraitWorld's function on Julia's types, defined in the declaring module: a pirate by the letter, counted by the census (`owned_method` false) in NetworkDynamics and Graphs; strict mode refuses nothing, the signature being unique | `TraitWorld/src/implement.jl:796`; `ndport/scripts/merge_family_registry.jl`, `ndport/logs/merge/family-registry.log` (E-165) |
| L-39 | — | *Retired*: see [§9.3](#93-untyped-callers-of-compiled-values-the-table). | — | — |
| L-40 | — | *Retired*: see [§9.3](#93-untyped-callers-of-compiled-values-the-table). | — | — |
| L-41 | — | *Retired*: see [§9.3](#93-untyped-callers-of-compiled-values-the-table). | — | — |
| L-42 | — | *Retired*: see [§5](#5-keys-and-views)]. | — | — |
| L-43 | [§2](#2-modes-owners-and-images), [§4.6](#46-families), [traits §14](traits.md#14-membership) | The machinery decides in the caller's world; `conforms(T, X)` answers as `T <: X` would, in the caller's world ([facts §2.1](facts.md#g1): "the same world"). | (1) A family member's builder is found in the latest world (`_latest(_family_builder, X, U)`), not the caller's: a task in an older world can fix a builder from methods its world does not see. (2) `conforms` called outside an entry decides in the newest world (`_decision_world` is the latest world outside a decision): after `@implement X S`, `invoke_in_world` with the earlier world and a task created before both answer `true`, in both settings (E-254). | `TraitWorld/src/implement.jl` (`_conf_family_slow`); `src/compiler.jl:104`–`107` (`_decision_world`, `_in_decision_world`), `src/entry.jl:1348` (`conforms`); `experiments/w83/u8/` |
| L-44 | [§4.6](#46-families) | A typed call of a family member costs what a declared type's does. | A caller compiled when the fold is not decided (TraitWorld's lock busy, an older world, a re-entrant call, a member whose check warns), or inferred by constant propagation or semi-concrete evaluation, keeps the run-time path (a registry lookup per call) until it is compiled again. | `TraitWorld/src/implement.jl` (`_member_fold`); `julia-1.13/Compiler/src/facts.jl` (`abstract_fold_call`) |
| L-45 | [§4.6](#46-families) | a member fixed while an image is built is not checked again at its load while the methods that serve it are the same | (1) The record is found by dispatch on `_member_record(::Type{X}, ::Type{U}, ::Val{image})`, a method of TraitWorld's function on other packages' types, defined in the image's package: a pirate by the letter, as L-38; strict mode refuses nothing, the signature being unique. (2) A member fixed while Julia writes the image (code compiled at output, after the build's `atexit` hooks) has no record and is checked again (1 of the forks' 27 members, E-231). | `TraitWorld/src/implement.jl` (`_note_image_member!`, `_write_image_members`, `_member_from_record!`); `TraitWorld/test/member_records.jl` (E-231) |
| L-46 | — | *Retired*: see [§8.1](#81-the-rewrite). | — | — |
| L-47 | [§8.1](#81-the-rewrite) | The machinery chooses the untyped fallback among the tagged methods alone. | In a closed build (`CLOSED_WORLD`, [§15.3](#153-verify_main-fully_typed-closed-builds)) the fallback is called by dispatch, `f(Untyped(), args…)`, and a call with keywords `Core.kwcall(nt, f, Untyped(), args…)` ([§10](#10-keywords-defaults-and-varargs)): where that call is ambiguous with an ordinary method of one more argument, it raises Julia's ambiguity error; where no tagged method applies, Julia's `MethodError` names `Untyped`. Not tried in a trimmed binary. | `TraitWorld/src/entry.jl:741` (`fallback`, `kwfallback`) |
| L-48 | [§10](#10-keywords-defaults-and-varargs) | Bounded methods of one shape may differ in taking keywords: a call with keywords is sorted among those that take keywords and the fallbacks that do, a call without among all of them ([traits §5.7](traits.md#57-keywords-defaults-and-varargs)). | One entry per shape, with keywords or without, as the shape's first bounded method: a later bounded method of that shape that differs in taking keywords is refused when it is defined (`TraitBoundError`). | `TraitWorld/src/trait_module.jl` (`_rewrite_fdef`, `__tw_kwentries__`) |
| L-49 | — | *Retired*: see [§8.1](#81-the-rewrite), `where` variables in bounds. | — | — |
| L-50 | [§8.1](#81-the-rewrite) | A bounded method of a type's constructor has the type's ordinary constructors as its fallback, Julia's default constructors included ([traits §5.5](traits.md#55-dispatch-types-first-then-traits)). | In a session the constructor at the entry's signature is taken out of the method table and becomes the fallback. While Julia writes a package image (incremental output) it refuses to take a method out (`Method deletion is not possible during Module precompile`) or to replace one, so there such a bounded method is refused when it is defined (`ErrorException`, naming the constructor and L-50); the struct declares inner constructors with typed arguments, and an untyped constructor written after the bounded methods becomes their fallback. The fix is in Julia: let a package's precompilation take out a method that the package itself defined in this session (the image writer already writes a disabled method entry as dead, `staticdata.c`); [open issue 135](../open-issues.md#2-design), deferred to W-83. | `TraitWorld/src/trait_module.jl` (`_may_take_methods`); `test/constructors.jl` ("refused while Julia writes a package image") |
