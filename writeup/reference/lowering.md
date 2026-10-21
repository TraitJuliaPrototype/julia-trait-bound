# Lowering: the reference

This page defines how the trait language ([`traits.md`](traits.md)) is realized on Julia's interfaces ([`compiler.md`](compiler.md)), within the facts mode's contract ([`facts.md`](facts.md)). For each construct it says what Julia methods, types, tables and caches it becomes, when they are made, in which mode and image their code is compiled, and which code is shared between which types.

It decides nothing the other three references decide. Where it seems to, they win.

- **Terms** as in the [glossary](../glossary.md). Terms used only here are defined where they first appear.
- **Code names** are TraitWorld's (`TraitWorld/src/`, at TraitWorld 227781a). Where the intended lowering differs from the code, the section states the intended form and the [Deviations](#18-deviations) table records the difference.
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
| `@trait X` | an abstract type; the operation functions; one method per operation on trait objects and on `Dynamic{X}`; records of operations, fields, parameters, defaults, the trait's default attribute | at the declaration | operation methods: inside the workers that call them | the declaring module's image |
| `@implement X T …` | records; a `conformance` method with a builder fixed now; for a block, the operations' methods | at the declaration | `conformance`: a boundary, compiled in its caller's mode | the declaring package's image, with the code compiled ahead ([§15](#15-compiling-ahead-workloads-closed-builds)) |
| a family member | a builder in the family's registry | at the member's first use | as above | the declaring package's image, for members its workload uses |
| a bounded function | a worker; an entry per shape | at the definition; the entry's needs and attributes at the trait module's end | worker: facts, per key, the erased key included; entry: a boundary | the image whose precompilation compiled them |
| a `Callable` argument | a `CObj` holding the function (`Compiled`) or a caller-world pointer (`Dynamic`) | at the entry, per call | worker per function type (`Compiled`) or per signature (`Dynamic`) | as for workers |
| `Dynamic{X}` | a struct holding the user's object; its operations are call-site splits over the held object's type; at a bound, a trait object at the erased key | methods at `@trait`; values at run time | in the caller | — |

**Shared code.** A worker is compiled per view type. A view's type depends on the trait, the key and the witness, never on the user's type ([§5](#5-keys-and-views)). So every type with the key of an existing worker runs that worker, wherever it was compiled, and every `Dynamic` value runs the worker for the erased key.

**Status of the attributes:** Implemented, except [L-31](#18-deviations) and [L-35](#18-deviations).

---

## 2. Modes, owners and images

**Status: Implemented** (deviation [L-17](#18-deviations)).

The facts mode and its owners are Julia's ([compiler §2.2, the method flag](compiler.md#22-the-method-flag-boundaries-and-always-facts-methods); what code may assume: [facts §5, run-time sites](facts.md#run-time-sites)). TraitWorld places each piece of code in one of these modes:

| Code | Mode | How it is marked |
|---|---|---|
| a trait module's methods: workers, internal functions, closures | facts, cache owner `:facts`, whoever calls them | `Base.Experimental.@compiler_options facts=true` in the module's prologue (`trait_module.jl:60`) |
| what a worker calls (operation methods, the user's methods serving operations, Base) | inferred by facts with the worker | Julia's rule; the compiler's own code stays plain |
| entries, `conformance` methods | the caller's mode (a *boundary*) | `Expr(:meta, :facts_boundary)` (`trait_module.jl:709`, `implement.jl:675`) |
| the machinery's slow paths: expansion of `@implement`, checks, finding builders, hooks | always facts | `@machinery`, which inserts `Expr(:meta, :facts_always)` (`compiler.jl:43`) |
| TraitWorld's small helpers (`enter`, `_assemble`, `checked_call`, `opcall`, the builders) | plain code, inlined into the code that calls them | `@inline` |
| the definition checks' rule check | the default interpreter's reflection: a worker at archetypes is inferred by facts, in the facts cache, as the code that runs would be. An archetype never runs, so nothing it infers is called | `_worker_problems` (`checks.jl:84`) |
| the keep analysis and the result-type checks | plain inference on a `NativeInterpreter` | own cache owner `_CheckOwner` at archetypes; the plain cache at real signatures (`compiler.jl:57`, `:66`; `defcheck.jl:229`) |

**Where code lives** is Julia's behaviour ([facts §11, package images](facts.md#package-images), [compiler §2.9, what package images keep](compiler.md#29-what-package-images-keep)):
- code compiled while a package's image is built is kept in that image, `:facts` code included;
- TraitWorld switches on keep-compiled ([compiler §2.9](compiler.md#29-what-package-images-keep)) for its own image and for every package built after it loads (`TraitWorld.jl:73`, `hooks.jl:22`), so an image keeps the code its precompilation compiled for other packages' methods;
- TraitWorld's own workload compiles its machinery under the facts owner, so a session does not compile it again (`TraitWorld.jl:132`).

**Decisions in the caller's world.** The machinery decides implementations in the world of the call that reached it (`tls_world_age()`), as dispatch does (`_DECISION_WORLD`, `compiler.jl:104`). Its caches are keyed by that world and emptied when it changes (`_flush_if_stale!`, `implement.jl:269`).

---

## 3. Trait declarations

**Status: Implemented** (deviations [L-1](#18-deviations), [L-4](#18-deviations), [L-19](#18-deviations)).

`@trait X begin … end` ([`traits.md#3-trait-declarations`](traits.md#3-trait-declarations)) runs at the declaration, in the declaring module. That module may be a trait module or plain code. It defines:

**The trait type.**
- `abstract type X{P…, Self} <: Trait` (`trait.jl:198`). The design's syntax is lowered to a form whose last parameter is the key (`_keys_form`, `trait.jl:103`).
- A *trait instance* `X{p…, K}` names the parameters' values and the key `K`. Views carry trait instances ([§5](#5-keys-and-views)).

**The operation functions.**
- A plain name creates a generic function in the declaring module. A qualified name (`Base.length`) uses that function (`trait.jl:274`).
- One method per operation **on trait objects**: `op(t::TObj{T}, args...) where T >: X = opcall(X, Val(:op), op, t, args...)`, declared `@inline` (`trait.jl:294`). These are the only methods trait objects have ([§7](#7-operations-on-a-trait-object)).
- One method per operation and arity **on `Dynamic{X}`**: a call-site split ([§13](#13-dynamicx), `trait.jl:301`). Plain code holding a `Dynamic` calls these; inside a worker a `Dynamic` value is a trait object at the erased key, and its operations go through `opcall` ([§7](#7-operations-on-a-trait-object)).

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
| `trait_concreteness(X)` | `:none`, `:warn` or `:concrete_only` |

Every record function is declared `Base.Experimental.@max_methods 1` (`core.jl:303`–`641`). Code compiled at an abstract argument where at least two of a record's methods apply infers nothing from them and holds no edge to them. So a declaration changes no compiled code ([§17](#17-encodings-until-traits-are-in-the-type-system)).
- A fallback (*sentinel*) method makes two apply: `trait_params`, `trait_fields`, `trait_uses_self`, `trait_field_params`, `field_isrep`, `has_default`, `is_mutating`, `trait_concreteness`, `supertraits`, `bundle`, `implementation`, `projection`, `conformance`, `needed`, `keeps`, `_declared_builder` have one; so do `default_attribute`, `attribute`, `result_params` and `is_operation_function`.
- The others have none: `trait_ops`, `op_function`, `op_args`, `op_ret`, `op_default`, `generic_op`, `generic_rec`, `param`, `param_bound`, `field_type`, `_fieldmatch`, `_fieldpos`, `_declared_defaults`.
- Where exactly one method applies, the sentinel or a declaration's, inference infers it and records an edge for the abstract signature ([L-4](#18-deviations)).

**Fields on trait objects.** For each declared field, a method of `_tgetprop(t::TObj{T}, ::Val{f}) where T >: X` and of `_tsetprop!` (`trait.jl:330`). `getproperty` and `setproperty!` on a `TObj` reach them; a `@const` field's setter raises ([§6](#6-trait-objects-layout-fields-writes)).

**Equations** `T = eltype(Self)` become `param` methods evaluated at the key's receiver type (`trait.jl:223`). At an archetype, a parameter is the value the bound fixes or an opaque `ParamArchetype` (`trait.jl:205`).

After the declaration, `_bump!()` registers the candidates of implementations declared so far ([§13](#13-dynamicx)).

---

## 4. Implementations

`@implement` ([`traits.md#4-implementations`](traits.md#4-implementations)) is expanded by machinery code compiled by facts (`_implement_expand`, `implement.jl:930`). The expansion runs in the declaring module, at the declaration. Every form defines methods, so the declaration is saved with the declaring package's image and owned by it.

### 4.1 What every form defines

**Status: Implemented** (deviation [L-7](#18-deviations)).

| Defined | Meaning |
|---|---|
| `implementation(X, R) = ImplRec(kind, defaults)` | the receiver type `R` implements `X`: by a block (`:methods`, the operations defaults serve), by its existing methods (`:existing`), or as a family (`:family`) (`implement.jl:24`) |
| `projection(X, T) = ProjRec(…)` | for a type that conforms through a field or a field mapping: the receiver type `R`, the forwarding field's index (0: none), the field mapping, a table of dynamic operations (`implement.jl:45`) |
| `conformance(::As{X}, u::T)` | the implementation as a method: an `@inline` boundary that calls the builder fixed now (`implement.jl:669`) |
| `_declared_defaults(X, T)` | the operations defaults serve, per trait of the closure: what an override would change ([§4.8](#48-overrides-and-redeclaration)) |
| `_declared_builder(As{X}, T)` | the same builder, for the untyped calls' table ([§9.3](#93-untyped-callers-of-compiled-values-the-table)) |
| `_compile_ahead(mod, X, T)` | while the package is precompiled: the code calls with a `T` need ([§15](#15-compiling-ahead-workloads-closed-builds)) |

**The builder** is fixed when the implementation is declared (`_declare_conformance`, `implement.jl:640`). It is data: per trait of the closure, a `VSpec` with the witness and the slots ([§5](#5-keys-and-views)). It is a constant of the declaring module, so its image keeps it.

**Checks** run at the declaration, from the expansion's top-level code ([§14](#14-checks-and-where-their-results-live)): `_check_implementation` for a receiver type's operations, `_check_projection` for a type that conforms through a field or mapping, `_check_own_fields` for the one-line form.

### 4.2 A block of methods

**Status: Implemented.**

`@implement X T begin ncols(t) = …; … end` ([`traits.md#41-with-a-block-of-methods`](traits.md#41-with-a-block-of-methods)):
- Each definition becomes a method of the operation's function, qualified by its module, with the receiver typed `T` and unannotated arguments typed as declared (`_op_method`, `implement.jl:801`).
- `implementation(X, T) = ImplRec(:methods, D)`, with `D` the operations left to defaults.
- No `projection` record: `T` is its own receiver.
- The methods are ordinary methods of `T`. Plain code calling `ncols(x::T)` finds them.

### 4.3 One line

**Status: Implemented.**

`@implement X T` ([`traits.md#42-one-line`](traits.md#42-one-line)) declares `T`'s existing methods (`_implement_oneline`, `implement.jl:1147`):
- `implementation(X, T) = ImplRec(:existing, ())`. The operations served by defaults are those `T` has no method for, fixed at the declaration.
- A trait with fields only, or a field mapping, adds `projection(X, T) = ProjRec(identity, I, …)`, with `I = Nothing` for a trait without operations.
- The expansion never picks a field. Without methods for the operations it raises, naming the fields whose type conforms with their `by` lines (`implement.jl:1199`).

### 4.4 Forwarding with `by`

**Status: Implemented** (deviation [L-7](#18-deviations)).

`@implement X T by f` ([`traits.md#43-forwarding-with-by`](traits.md#43-forwarding-with-by)):
- The receiver type is the field's declared type `R`. The record is `projection(X, T) = ProjRec(…, R, …, field index of f, …)`.
- No method is defined for `T`'s operations. Defaults and the field type's methods serve trait code only.
- The witness is the field type's own: `witness(X, R)`, from `implementation(X, R)`. A field type that itself forwards has no `implementation` record, so forwarding does not chain (`_check_projection_now`, `implement.jl:526`).
- *As built,* `by f` is lowered to the projection `project(t) = getfield(t, :f)`, and the projection is accepted because it reads a field as is (`implement.jl:911`, `:1298`).

### 4.5 Field mappings, several traits, stated parameters

**Status: Implemented** (deviation [L-26](#18-deviations)).

- **A field mapping** `name => stored` is kept in the record (`ProjRec.fmap`). The builder takes each declared field's slot from the mapped stored field (`_mapped`, `entry.jl:434`).
- **Several traits** `(X, Y) T by f`: one `projection` record and one `conformance` method per trait. The entry merges their views into one trait object ([§8.2](#82-the-entry)).
- **Stated parameters** `@implement X{p…} T`: `param(X, Val(:p), T)` and `param(X, Val(:p), Key{T, F})` methods (`_param_methods`, `implement.jl:1008`), for the parameters no field and no equation defines.
- **A stated value for a parameter an equation defines** makes no method: the declaration's check compares it with the equation's value at `T` and refuses the implementation if they differ ([traits §4.6](traits.md#46-stating-parameters)). The equation's `param` method serves `T`.

### 4.6 Families

**Status: Implemented** (deviation [L-23](#18-deviations); the family-wide check [traits T-26, T-27](traits.md#17-deviations)); forwarding for a family **Planned**.

`@implement X S{P} where {P} [begin … end]` ([`traits.md#47-families`](traits.md#47-families)) defines (`_family_conformance_methods`, `implement.jl:690`):
- the operations' methods with the `where` clause, for a block;
- `implementation(X, S{P}) where {P}`, for the whole family;
- **a registry** in the declaring module: `const reg = Ref(IdDict())`, found again after an image loads through `_family_registry(Val(name))`;
- `conformance(::As{X}, u::S{P}) where {P} = _conf_family(reg, X, u)`.

**A member is fixed at its first use** (`_conf_family_slow`, `implement.jl:707`):
- the slow path finds the member's builder, checks its operations (a family of existing methods), refuses an abstract parameter under `@concrete_only`, and stores the builder in the registry, copy-on-write;
- the member's default-served operations are added to the override index then ([§4.8](#48-overrides-and-redeclaration));
- builders found by the declaring package's workload are saved with its image; a builder holding session pointers is not kept.

A later declaration for one member is a more specific `conformance` method.

**Planned: forwarding for a family**, `@implement X S{T} by f where {T}`: the family's `conformance` method with a builder per member that reads field `f`.

### 4.7 Generic implementations

**Status: Implemented** (the form); the overlap check **Planned**; what a predicate may say **Open** ([`traits.md#48-generic-implementations`](traits.md#48-generic-implementations)).

`@implement X R where {R: Y, pred} begin … end` defines (`implement.jl:1110`):
- `generic_rec(X, Val(k)) = GenericRec(constraints, predicate, defaults)`, with `k` a fresh name;
- each operation as a method of `generic_op(X, Val(k), Val(op), t, args…)`, where `t` is a trait object carrying the constraint traits;
- no `conformance` method: the generic `conformance` fallback finds the implementation ([§8.2](#82-the-entry)).

At a type's first call, `_witness` (`implement.jl:337`) tries each generic record: the constraints' witnesses, then the predicate, in the decision world. The witness is `Generic{X, k, S, D}`, holding the constraints' witnesses. More than one match is an error. A more specific declared implementation is found first, as a `conformance` method of its own. The generic implementation's results are checked at the first concrete type, with a warning (`_generic_problems`).

### 4.8 Overrides and redeclaration

**Status: Implemented**; redeclaration **Planned** ([`traits.md#49-checks-at-the-declaration`](traits.md#49-checks-at-the-declaration)).

- `_declared_defaults(X, T)` records `(trait, receiver type, operations)` for each trait of the closure (`implement.jl:625`). Family members add theirs at first use.
- From these, an index maps each operation function to the implementations its defaults serve (`_OVR_INDEX`, `hooks.jl:62`).
- **At a definition,** the method-definition hook refuses a method of an indexed operation for an indexed receiver type ([§16](#16-sessions-loads-and-hooks)).
- **At an image's activation,** the image hook leaves such a method inactive and reports it after the load.
- **Checkpoints** scan the records again (`check_overrides`, `implement.jl:753`): at each declaration, at a trait module's end, at a worker's first call.
- **Redeclaration** with a block is refused when `T` already has a `conformance` method of its own (`implement.jl:949`, `:972`). Other forms are accepted with another meaning ([traits T-29](traits.md#17-deviations)). *Planned:* redeclaration on Julia 1.13's struct redefinition: a new `conformance` method and records, old values keeping the old builder.

---

## 5. Keys and views

**Status: Implemented** (deviations [L-1](#18-deviations), [L-2](#18-deviations), [L-21](#18-deviations)).

The key ([`traits.md#67-what-compiled-code-is-compiled-for`](traits.md#67-what-compiled-code-is-compiled-for)) is lowered as follows (`_key_and_slots`, `entry.jl:442`):
- **A trait without fields:** the key is the receiver type `R`.
- **A trait with fields:** `Key{I, F}`, with `I` the receiver type and `F` a named-tuple type of the declared fields' stored types (`core.jl:70`).
- **No receiver type** (`I = Nothing`): every operation is served by a default ([traits §6.7](traits.md#67-what-compiled-code-is-compiled-for)). *As built,* also the declarations must not name `Self`, and fields must define every parameter (`_no_implementing_type`, `entry.jl:456`; [L-21](#18-deviations)).

**A view** is one trait's part of a trait object: `View{Xi, W, K, N, P}` or `Held{Xi, W, K, N, P}` (`core.jl:86`, `:101`), with
- `Xi` the trait instance `X{p…, K}`;
- `W` the **witness**, a type saying where the operations come from: `Impl{D}` (the receiver type's own methods, `D` those served by defaults), `Generic{…}`, `Dyn{…}`, or `ArchWit` at an archetype (`defcheck.jl:31`);
- `K` the key, `N` the number of declared fields, `P` the type of the parts the view holds.

**The builder** of a user type is `Builder{Tuple{VSpec…}}`, one `VSpec{Xi, W, K, N, P, S}` per trait of the closure (`entry.jl:40`, `:47`). A `VSpec` holds the witness, the receiver's slot and the declared fields' slots. A *slot* is a byte offset and a field index; offset −1 means the object itself (`core.jl:56`). `S` says that the user's type is its own receiver.

**Why a new type with an existing key compiles nothing in the library:**
- its views have the key's view type, so the worker for that view type serves it;
- its builder's type depends on the trait, the key, the witness and `S`, not on the user's type, for every type that forwards or is keyed by its fields alone;
- what the declaration adds is data (the builder's witness and slots) and one small `conformance` method, compiled into callers that know the type.

**The erased key** is `ErasedKey{P, Y}`, with the witness `ErasedWit`: a `View{X{p…, ErasedKey{P, Y}}, ErasedWit, ErasedKey{P, Y}, 0, Tuple{}}` holds the user's object in its field `o` (typed `Any`) and no slots. `P` is the tuple of the trait's parameter values; `Y` is the item trait of a `CompiledItems{Y}` view whose items are of an abstract type ([§13.1](#131-a-users-container-crossing-by-its-bound)), else `Nothing`. `Self` at the erased key is `ErasedSelf`: an operation's result declared `Self` gives a `Dynamic` of the new value; a field declared `Self` reads as `Any`.
- The parameter values `p…` are those the position fixes; at a bare bound that leaves a parameter its results use open, the value's own, read when it enters ([`traits.md#51-bounds`](traits.md#51-bounds)). So the worker at the erased key is compiled once per tuple of parameter values.
- A trait object at the erased key has an erased view for each trait of the bound's closure, supertraits included, so a bound on a supertrait accepts it, and several bounds at one position work.
- Its trait set has the same families and parameter tags as a keyed one's. The tags are attached only after the entry has checked the value's parameters, per candidate and, beyond them, dynamically.
- Its view type does not depend on the user's type. So one worker serves every `Dynamic` value at the position.

**A trait object** is `TObj{T, V}` (`core.jl:214`): `V` the tuple of views, `T` the trait set, computed from the views' instances (`_traitset`, `core.jl:292`).

**A worker's signature** names a trait object by its trait set's lower bound: `t::TObj{T} where T >: Union{F…, PTag{F, i, v}…}`, with the families of the bound and its supertraits and a tag per parameter the bound fixes (`tobj_bound`, `trait_module.jl:470`). The lower bound has no free type variable, so the worker's static parameters are all determined by its argument.

---

## 6. Trait objects: layout, fields, writes

**Status: Implemented**; a copying layout for isbits-only targets **Open** ([open issues §2](../open-issues.md#2-design), "Keys and fields", item 3).

**Three layouts,** chosen by the builder per view (`_buildview`, `entry.jl:56`):

| The user's value | View | Holds | A read |
|---|---|---|---|
| mutable | `View`, `o` = the user's object | the object; the slots of the receiver and of each declared field | a load at the slot's offset, every time |
| immutable, forwarding or keyed by its fields | `View`, `o = nothing` | the parts: receiver and declared fields' values, typed by the key | a field load from the view |
| immutable, its own receiver | `Held` (a *held view*) | the whole value and its declared fields' values | a field load |
| any, at the erased key | `View` at `ErasedKey`, `o` = the user's object as `Any` | the object | the call-site split over the candidates; in each branch the candidate's slot read as above; the result asserted to the declared field type ([§13](#13-dynamicx)) |

- Holding is equivalent to reading for an immutable value: none of its fields can be rebound.
- A key used both held and read through has one worker per view type.
- A function that may keep a trait object receives the whole user's object also for an immutable value: the entry replaces `o` by the boxed value (`_with_object`, `entry.jl:219`; [§8.4](#84-keeping)).

**The receiver** of a view is read by `_rep` (`core.jl:115`): the held part, or the object itself (slot −1), or its forwarding field at the slot's offset.

**Reading a declared field** `t.f` (`fieldget`, `core.jl:563`):
- a held view: the part at the field's position;
- otherwise, a load from the user's object at the slot, by the field's storage kind (`_storage`, `core.jl:162`):
  - isbits or a reference: the field-offset intrinsic `getfield_at_offset`, with Julia's alias metadata and, for a reference, the null check ([compiler §5.2, field-offset intrinsics](compiler.md#52-field-offset-intrinsics));
  - a singleton: the constant;
  - stored inline and not isbits: `getfield` by index.
- The result has exactly the key's field type.

**Writing a declared field** `t.f = x` (`fieldset!`, `core.jl:572`):
- `x` is asserted to the key's field type;
- a held view raises (an implementation check refuses writable fields on immutable types first);
- isbits and reference fields are stored with `setfield_at_offset`, which keeps the write barrier; others with `setfield!`.
- A `@const` field's setter raises `ArgumentError` (`_readonly`).

**An undeclared field** has no `_tgetprop` method: `ArgumentError` at run time, and a `TraitUseError` from the definition check ([§14](#14-checks-and-where-their-results-live)).

---

## 7. Operations on a trait object

**Status: Implemented.**

`op(t::TObj, args…)` reaches the method `@trait` defined, which calls `opcall` (`core.jl:661`):
1. selects the view of `X` (`viewof`, folded for a known view type);
2. checks the arguments against `op_args` at the key: `TraitArgumentError` otherwise. A trait object passed to an argument declared `Dynamic{Y}` is first converted to a `Dynamic{Y}` ([§13](#13-dynamicx), the seams);
3. dispatches on the witness (`_dispatch`, `core.jl:671`):
   - `Impl{D}`: a default (`op_default`, with the whole trait object, so it may call supertraits' operations) if `op ∈ D`, else `op(receiver, args…)`, the receiver type's own method;
   - `Generic`: `generic_op` on a trait object built from the constraints' witnesses;
   - `ErasedWit`: the call-site split over the held object's type, each branch the candidate's view folded and its own dispatch, the fallback a dynamic call ([§13](#13-dynamicx));
4. asserts the result to `op_ret` at the key.

For a concrete view type, the witness, the default test and the declared types are constants. The call to the receiver type's method is a call at concrete types: a fact. At the erased key, each branch of the split is such a call; the fallback is a run-time site.

---

## 8. Bounded functions: workers and entries

### 8.1 The rewrite

**Status: Implemented** (deviation [L-3](#18-deviations)).

`@trait_module` wraps every top-level statement in `@stmt`, so each is expanded after the ones before it have run (`trait_module.jl:71`). A function definition with a trait bound, a `Callable` bound or a trait vararg is rewritten (`_rewrite_fdef`, `trait_module.jl:413`) into:
- **the worker:** the definition as written, with each bounded argument typed `TObj{T} where T >: …` ([§5](#5-keys-and-views)), each `Callable` argument `CObj{A, S}`, several `Callable`s `CMulti`. It is a method of the trait module, so Julia compiles it by facts;
- **the entry,** once per *shape* (the pattern of annotated positions): a method with the bounded positions untyped and `@nospecialize`, compiled in its caller's mode ([§8.2](#82-the-entry));
- **a note of each trait position** (`_note_position`), from which the entry's needs and the position's attribute are fixed ([§8.3](#83-needs-and-the-modules-end)).

**Attributes:** `x::Compiled{X}` and `x::Dynamic{X}` (also `Compiled{Callable{A, S}}`; `Dynamic{(X, Y)}`: [traits T-50](traits.md#17-deviations)) are read by `_classify` as the bound `X` with an attribute, recorded in the position's note. An attribute on a bound's item parameter (`Iterable{Compiled{Mark}}`) becomes the item tag `Through{Mark, Compiled}`, and a bare trait name there `Through{Mark, Nothing}` ([§13.1](#131-a-users-container-crossing-by-its-bound)). A `Dynamic` attribute whose trait leaves a parameter its result types use open is refused here (`TraitBoundError`).


**`where` variables in bounds** (`f(v::KVec{T}) where {T}`): `_classify` evaluates the bound with the variables open, a family bound without their parameter tags. A variable that only bounds name is taken off the worker's `where` list, and the body begins with `T = _trait_param(v, KVec, Val(1))`, a constant per key read from the trait object's type (`core.jl`); one that an ordinary argument or a second bound also fixes is checked against it (`_param_mismatch`), and a bound on the variable is checked there too. A `Callable` bound naming one is refused (`_uses_callable`).

An untyped method of an existing entry's shape becomes the entry's **fallback**: `f(::Untyped, args…)` (`trait_module.jl:456`). An ordinary method that would take an entry's signature is refused (`_check_entries_intact`).

A worker calling a function with a trait object it carries reaches that function's worker directly: the trait object's type matches the worker's signature, and the entry at `Any` is less specific. A trait object reaching an entry raises `TraitBoundError`: its trait is not the one the callee needs (`_rule3_error`, `entry.jl:267`).

Internal functions without bounds take trait objects as ordinary arguments. Julia compiles them by facts as part of the worker's call graph.

### 8.2 The entry

**Status: Implemented**, except a keyword's value from a caller that does not know its type ([traits T-47](traits.md#17-deviations)).

The entry is declared `@inline` and is a boundary (`trait_module.jl:709`). Every trait position is `@nospecialize`: a typed caller inlines the entry, an untyped caller reaches the one entry compiled at `Any` ([§9](#9-callers-typed-untyped-compiled-ahead)). Its body, for each bounded position `i`:
1. `enter(EntryPos{typeof(f), i, nargs}(), x)` (`entry.jl:193`) decides the attribute once, for the value as it arrives:
   - a trait object raises ([§8.1](#81-the-rewrite));
   - a `Dynamic` stays `Dynamic`: the trait object at the erased key of its held object (`erased`), never opened ([§13](#13-dynamicx));
   - `compiled_for(y)`: the trait object of `y` at its own key, so the worker for that key is selected once. A typed caller assembles it in place. From an untyped caller, the table of declared implementations serves it ([§9.3](#93-untyped-callers-of-compiled-values-the-table));
   - `with_dynamic(y)`: the trait object at the erased key;
   - any other value, by the first that applies:
     1. the position's attribute, if the bound has one (`attribute(EntryPos{…}())`, fixed at the module's end);
     2. the traits' default (`default_attribute`), unless the value's type is of the trait world (`_tw_type`);
     3. `Compiler.known_type(x)` ([compiler §4.1](compiler.md#41-compilerknown_type)): `true`, `Compiled`; `false`, `Dynamic`. It is `false` wherever the call to the entry is dispatched at run time: the argument held at an abstract type, or the function itself not known to the caller (a module in a variable, a harness that calls through a function value). It is evaluated in the entry's own body, before the value is passed to any helper: in code compiled by facts, a helper called with an `Any`-typed value is a run-time site, compiled for the value's type, where it folds to `true` (E-148).
   - `Compiled`: `_assemble(needed(p), x)`, one `conformance(As{X}(), x)` call per needed trait, the views merged, each trait once (`entry.jl:225`). `Dynamic`: the conformance check split over the candidates (`@dynamic_of`'s), then the trait object at the erased key;
   - a container at an item position crosses into a view ([§13.1](#131-a-users-container-crossing-by-its-bound));
2. `NOTRAIT` (the value conforms to none of the needed traits) returns `fallback(f, args…)`: the `Untyped` fallback, else the most specific ordinary method that is neither entry nor worker, else `MethodError` with a hint naming the bound (`entry.jl:484`, `frames.jl:64`);
3. `Callable` positions are translated by `enter_callable` ([§12](#12-callable-and-dynamiccallable)), by the same decision;
4. the worker is called through `checked_call(f, views…)`: the first-call check flag, then the call (`checks.jl:253`). At the erased key the trait object's type is known to the entry, so the call is static;
5. a result like the input goes through `_like_out` ([§11](#11-results-like-the-input)).

**`conformance`** has one method per declared implementation, and a fallback that finds generic implementations and implementations without a fixed builder (`_conformance_slow`, `entry.jl:144`). The slow path's results are kept copy-on-write per decision world.

**Dispatch, types first** ([`traits.md#55-dispatch-types-first-then-traits`](traits.md#55-dispatch-types-first-then-traits)): the entry's bounded positions are `Any`, so every type-annotated method is more specific. A value caught by one takes it and is never translated.

### 8.3 Needs and the module's end

**Status: Implemented.**

- **What a position needs** is `needed(EntryPos{F, pos, nargs}())`: a `TraitList` of the traits the workers of `F` bound there. **Its attribute** is `attribute(EntryPos{F, pos, nargs}())`: `Compiled`, `Dynamic`, or `nothing` where no bound there has one, fixed with `needed`. Until the module is complete a fallback computes it by reflection (`entry.jl:183`). At the module's end, `_fix_needed!` defines one method per position, a constant (`trait_module.jl:776`). A later definition at the prompt redefines it when the needs change.
- **At the module's end** (`_finish_module`, `trait_module.jl:794`): the needs, attributes and keep flags are fixed; overrides are checked; unrelated bounds without a joint method and ambiguities with typed methods are reported (`check_bounds`, `check_entry_ambiguities`); an attribute on a function neither exported nor public in its owner module (`Base.ispublic`) warns (`_warn_hidden_attributes`); definition checking runs ([§14](#14-checks-and-where-their-results-live)).
- **The module's registries** are constants its prologue defines: `__tw_entries__` (shapes per function), `__tw_plain__`, `__tw_extended__`, `__tw_positions__`, `__tw_untyped__`, `__tw_finished__` (`trait_module.jl:60`).
- **Only the function's owner** may add an entry: an entry is a method at `Any` (`trait_module.jl:535`).

### 8.4 Keeping

**Status: Implemented.**

`keeps(KeepOf{F}())` says whether a worker of `F` may keep a trait object: make it a `Dynamic`, store it where a `Dynamic` is declared, or return a closure that captured it (`entry.jl:205`).
- It is decided at the module's end, by inferring each worker at archetypes in the checks' own cache and following internal functions and workers (`_analyze_keeps`, `defcheck.jl:277`).
- An answer the analysis cannot reach is `true`, the fallback. It costs a box, never a wrong result.
- The method-definition hook recomputes it for a function given a method after its module is complete (`hooks.jl:218`).
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
- its conformance is checked by a split over the candidates, folded to a constant per candidate, a dynamic call beyond them (`_ConformsTo`, `core.jl:514`);
- the trait object at the erased key is made from it ([§5](#5-keys-and-views));
- the worker for the erased key is called statically: the entry knows the bound, so it knows the trait object's type.

Nothing is compiled per user type. Code Julia does not compile (a statement at the prompt) is such a caller.

### 9.3 Untyped callers of `Compiled` values: the table

**Status: Implemented.**

An untyped caller passes a `Compiled` value where it converts it (`compiled_for(x)`), or where the position's attribute is `Compiled`. The entry compiled at `Any` then finds the code for the value's key through the **table of declared implementations** (`untyped.jl`). This is how Swift opens a value of a protocol type: the per-type data is looked up, the code is shared per key.
- **Which entries:** those of trait positions and ordinary arguments only, without keywords or varargs (`trait_module.jl:592`). Other entries take the generic path of `enter`: the trait object assembled for the value's type behind a dynamic call, then the worker selected by a second dynamic call.
- **The test** (`_tabled`, `attributes.jl`): no trait argument's object's type is known (a kept value's never is, `_known_object`), and every trait argument is `Compiled`: a `compiled_for`, a `Compiled{X}`, a `Kept{X}` holding `Compiled`, or a plain value at a `Compiled` position. The table's value is the object such a value holds (`_unconverted`).
- **Per entry position, a table** from the user's type to its implementation's builder, valid in a range of worlds: a declared implementation for the range of its dispatch, anything else for one world (`UTable`, `_umiss`). It is appended copy-on-write, and a table saved in an image is ignored in another session.
- **One trait position:** a table per entry pattern from the user's type to a `:caller_world` pointer ([compiler §3.1](compiler.md#31-the-cfunction-calling-convention-caller_world)) to the pattern's method specialized on the builder (`_pentry`). One call through it builds the views from the builder's data and calls the worker for the key. Several trait positions: the builders from each position's table, then one dynamic call on the builders' types.
- **The pattern's method** is compiled once per key, and compiled ahead per declared implementation ([§15.1](#151-compiling-ahead-from-declarations)).
- A type the table does not serve (a generic implementation, a family member, a position where containers cross) takes the generic path; a type without an implementation reaches the fallback as there.

---

## 10. Keywords, defaults and varargs

**Status: Implemented**; `Callable` with keywords **Planned** ([`traits.md#57-keywords-defaults-and-varargs`](traits.md#57-keywords-defaults-and-varargs)).

**The entry translates, the worker sorts:**
- The entry takes `f(args…; kws…)` and makes the supplied keywords a named tuple (`trait_module.jl:580`).
- A bounded keyword, if supplied, is translated by `enter_kw`, which refuses a value that conforms to none of its traits (`TraitBoundError`, `entry.jl:331`), and decides its attribute as `enter` does, but for a caller that does not know the type ([traits T-47](traits.md#17-deviations)). A `Callable` keyword by `enter_kw_callable`.
- `checked_kwcall(nt, f, views…)` calls `Core.kwcall(nt, f, views…)`: the worker's own keyword sorter, which Julia lowers from the worker's definition (`checks.jl:283`). It fills the defaults inside the worker, compiled by facts, so a default sees the trait objects.
- In the worker, a bounded keyword is typed `TObj` and a `Callable` keyword `CObj{A, S}`.

**Positional defaults** are expanded as Julia expands them: the full method, and one shorter method per default whose body calls the full one (`_expand_defaults`, `trait_module.jl:360`). Each is a bounded definition with its own worker and entry. The shorter worker calls the full worker with its trait objects.

**A trait vararg** `ts::X...` becomes a worker vararg whose elements each have their own `TObj{T} where T >: …`, so elements may differ in key. The entry translates each element (`enter_each`, `entry.jl:318`). The worker compiles per tuple of keys.

**Fallbacks** with keywords go through `kwfallback`.

**Planned:** `Callable{A, S, K}`, the keywords' named-tuple type `K` part of the pointer's signature and of the worker's key.

---

## 11. Results like the input

**Status: Implemented** (deviation [L-16](#18-deviations)); listing the inverses for compiled-ahead builds **Planned**.

`f(t::X, …)::Like{t} = body` ([`traits.md#56-results-declared-types-like-withfields`](traits.md#56-results-declared-types-like-withfields)) is rewritten (`trait_module.jl:429`):
- the worker's body becomes `like(t, body)`, and each `return x` `return like(t, x)` (`_like_returns`);
- `f`'s type is recorded, so the check that no trait object goes up allows the pending result (`_like!`, `entry.jl:648`).

**The pending result** is `LikeResult(t, x, fields)`: the input's trait object, the new receiver or `KeepSelf()`, and replaced declared fields (`entry.jl:658`). `withfields(t; f = v)` makes one with fields only. Nothing operates on it.

**The entry inverts it** (`_like_out`, `entry.jl:682`), for the argument whose trait object it names:
- a type that implements the operations itself: the new receiver, which must be of the same type family;
- otherwise: the user's object rebuilt by its type's constructor with the forwarding field and the replaced fields substituted (`_invert`, `_rebuild`, `entry.jl:710`, `:730`). The constructor recomputes the type's parameters, which gives siblings (`LSeries{Float64}` in, `LSeries{Float32}` out);
- a `Dynamic` in: the rebuilt object as a `Dynamic` of the same trait. At the erased key the inverse runs when the call runs, for the held object's type.

**A constructor operation on a `Dynamic`** returns a `Dynamic` of the new value (`_dyn_like`, `entry.jl:741`).

**Intended:** the inverse is compiled per key and user type where the caller knows the type, and its result has the caller's type. **As built,** it runs behind an inference barrier ([L-16](#18-deviations)).

---

## 12. `Callable` and `Dynamic{Callable}`

**Status: Implemented**; open result types **Planned** ([`traits.md#58-callable-functions-at-a-declared-signature`](traits.md#58-callable-functions-at-a-declared-signature)).

`Callable` keeps a lowering of its own; it is not a `@trait` declaration. Its default attribute is `Dynamic`.

**In the worker,** a function argument is a `CObj{A, S, F}` (`core.jl:897`). Calling it checks `args isa A` (`MethodError` otherwise) and asserts the result to `S`. The worker is compiled per `F`:
- `Dynamic`: `F = Erased{A, S}`, the same type for every function: one worker per signature;
- `Compiled`: `F` is the function's type: one worker per function type, the function's call inferred into it.

**At the entry,** `enter_callable(A, S, attribute, f)` (`entry.jl:720`):
- a cast, `compiled_for(f)` or `with_dynamic(f)`, wins; it takes the position's signature;
- a kept function, `Dynamic{Callable{…}}`, `Compiled{Callable{…}}` or `Kept{Callable{…}}` at any signature: its attribute, carried; a `Dynamic` one at another signature becomes `CObj{A, S}(Erased{A, S}(f))` of its function (`_erased_at`);
- otherwise: the position's attribute (`Compiled{Callable{A, S}}`), else `Callable`'s default `Dynamic` for a function whose type is not of the trait world (`_tw_type`, `entry.jl:697`), else `Compiler.known_type(f)`;
- `Compiled`: `CObj{A, S}(f)`; `Dynamic`: `CObj{A, S}(Erased{A, S}(f))`;
- caches the wrapper per (signature, attribute, type) for functions that capture nothing.

**`Erased{A, S}`** (`core.jl:841`) holds the function and a pointer to its code compiled for `A`:
- the pointer is a `cfunction` of the calling convention `:caller_world`: the call runs in the caller's world, through a world-checked cache in the pointer's thunk ([compiler §3.1, the `:caller_world` convention](compiler.md#31-the-cfunction-calling-convention-caller_world), `_fptr`);
- the callee is `_CallWrap{S}`, with fixed arities up to six, which calls the function and asserts `S`. Non-bits arguments go boxed. A `Dynamic{Y}` among `A` is passed as `Ref{Dynamic{Y}}` (`_cdecl`, `core.jl:860`); a trait object at the erased key is converted to it first ([§13](#13-dynamicx), the seams);
- the function runs as plain code, as every call through a `cfunction` does ([compiler §2.5, dispatch from facts code](compiler.md#25-dispatch-from-facts-code));
- the pointer sits in a mutable cell. A package image saves it as null, and the first call in a session makes it again (`_PtrCell`).

**Several signatures** `f::(Callable{…}, Callable{…})`: a `CMulti` holding one `CObj` per signature; a call picks the first signature its argument types match, at compile time (`core.jl:924`).

**Kept functions** (`entry.jl`, "`Callable`'s kept values"):
- **`Dynamic{Callable{A, S}}`** holds a `CObj{A, S, Erased{A, S}}`; its call reads the kept value at that asserted type and calls it, so the call stays typed. It adds a heap object and a load with a type assertion per call against a `CObj` held inline (a performance issue to revisit, [open issues §4](../open-issues.md#4-runtime-and-measurements), item 35).
- **`Compiled{Callable{A, S}}`** holds the function itself; its call is `CObj{A, S}(f)(args…)::S`, a dispatch on the function's type.
- **`Kept{Callable{A, S}}`** holds either, with its attribute, and branches on it at each call.
- Their constructors take a plain function, a cast, a function argument (`CObj`) or a kept function, and keep its attribute; asked to change it they refuse (`_cast_refuse`). `compiled_for` and `with_dynamic` move the function between the forms (`_callable_fn`, `_erased_at`).

**In a closed build** every function is known, so nothing is erased: `CObj{A, S}(f)` (`entry.jl:730`).

**Planned: an open result type** `Callable{A, S} where S`: `S` inferred at the entry in plain code, part of the worker's key, asserted at every call.

---

## 13. `Dynamic{X}`

**Status: Implemented** (deviations [L-6](#18-deviations), [L-20](#18-deviations), [L-25](#18-deviations), [L-31](#18-deviations)); `Dynamic{(X, Y)}` **Planned** ([`traits.md#7-kept-values-dynamicx-compiledx-keptx`](traits.md#7-kept-values-dynamicx-compiledx-keptx)).

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

- `_dynop(X, op)` is `op` applied to the opened object, as a value of its own type (`_DynOp{X, F}`, one method per arity up to six, `core.jl:448`). The split is over the held object.
- `RT` is the declared result type, with the parameters the `Dynamic`'s type fixes substituted ([traits §7](traits.md#7-kept-values-dynamicx-compiledx-keptx)). Where it names `Self`, or a parameter the type leaves open, it is `Any`. *As built,* it is `Any` wherever the declared type names `Self` or any parameter ([L-20](#18-deviations)).
- Julia infers the call at the union of the family's registered **candidates**, the first four, plus a fallback, and splits it as a union: `isa` branches on the held object's type, in each the view folded and the operation's method called directly. The last branch calls the target for the object's type through the table of the call's signature, its result asserted to `RT` ([compiler §4.2, the call-site split](compiler.md#42-compilersplit_call-the-call-site-split); [§4.3, the table](compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)).
- `@constprop :aggressive` makes each caller infer the call again, so it splits over the candidates registered when it is compiled.
- The fallback dispatches in the caller's world. A type outside the four costs one probe and an indirect call, at any number of implementations, and allocates nothing for a concrete `RT`.
- An operation whose result is `Self` returns a kept value of the new value instead, of the receiver's form and attribute (`_dyn_like`, `_like_held`).

**Which candidates a caller splits over** is fixed when the caller is compiled ([compiler §4.2](compiler.md#42-compilersplit_call-the-call-site-split)). So a worker at the erased key compiled into a package image splits over the implementations registered while that image was built, that package's and its dependencies'; a user's type takes the fallback at every operation. Code compiled in the session splits over the first four declared. A type outside the split takes the table, whose cost does not depend on the number of implementations.

**Candidates** are the types a `Dynamic` holds: the implementations' types (and, in the two cases above, trait-object types), registered with `Compiler.register_dynamic_candidate!` without an edge:
- **at each declaration and each package load,** for each implementation at a concrete type, from the `implementation` and `projection` records (`_note_conformances!`, `core.jl:532`). Each batch is registered in **declaration order:** by the declaration's file, then line. The records carry the `@implement`'s own line (`_at_declaration`, `implement.jl:943`), so a session that loads a package image registers its types in the order the image's code was compiled for. *As built,* a family member is registered only when a `Dynamic` of it is made ([L-25](#18-deviations));
- **when a `Dynamic` is made,** its object's type: once per type and session, through a flag per pair that the constructor's code holds as a constant (`_cand_flag`, `core.jl:390`), not by a search of the registry.

A later implementation reaches the fallback and invalidates nothing.

**Seeing a value of unknown type** (an item read from a `Vector{Any}`): `@kept_of X x attr` (`core.jl`) keeps a value that carries its attribute (`isa` tests on the kept forms and the casts), and for a plain value splits the conformance check over the same candidates (`_ConformsTo{X}`), folded to a constant for each. It makes the `Kept{X}` by an `invoke` of its constructor at `(Val{:checked}, Any, Bool)`, a fact, so `x` is held in the box it came in and nothing is allocated. Any other type is checked by a dynamic call. BaseTraits' views do this at each read ([§13.1](#131-a-users-container-crossing-by-its-bound)). `@dynamic_of X x` makes a `Dynamic{X}` likewise.

**The casts** (`attributes.jl`): `compiled_for(d)` of a `Dynamic{X}` is a `Compiled{X}` of the same object, of a `Kept{X}` a `Kept{X}` holding `Compiled`; `with_dynamic` the reverse. On a trait object at the erased key, `compiled_for` opens it and passes the trait object, typed `Any`, to the next call, which dispatches on its type, so it selects the worker for the key once.

**Fields:** a declared field read on a kept value or on a trait object at the erased key goes through the same split as an operation: each branch reads the candidate's slot ([§6](#6-trait-objects-layout-fields-writes)), the fallback reads through the opened trait object, and the result is asserted to the declared field type, or the parameter value fixed. A write is split the same way.

**Equality, hashing, printing:** `==` on the held user's objects (or the trait objects held), across the three forms; `hash` agrees, with one salt; `===` differs by form and attribute. They print `Dynamic{X} at <key>`, `Compiled{X} at <key>`, `Kept{X}: Compiled at <key>` (`_dyn_identity`).

### 13.1 A user's container crossing by its bound

**Status: Implemented** (deviation [L-27](#18-deviations); [traits §8.2–§8.3](traits.md#83-a-users-container-taken-as-it-is)).

- **Item positions:** a trait's name in a bound's parameter becomes the tag `Through{Y, A}` in the worker's trait set, with `A` the item parameter's attribute, a symbol (`:default`, `:compiled`, `:dynamic`). A trait object's set has a `Through{Y, A}` tag, for every `A`, where its item type is a kept value of `Y` (`Dynamic{Y}`, `Compiled{Y}`, `Kept{Y}`) or a trait object carrying `Y` (`_kept_item`, `_through_variants`, `core.jl`). So one worker signature accepts both views and a container of kept values.
- **What a position asks:** `crossing(EntryPos{F, pos, nargs}())` is fixed with `needed` at the trait module's end (`_fix_crossing!`, `trait_module.jl:773`; `crossing_at`, `entry.jl:310`): a `Crossing{Y, R}` where the workers' bounds at the position name item positions of one trait `Y`, with `R`, for each worker, the parameter tags its bound requires. Elsewhere, the fallback method: `nothing`, folded.
- **At the entry** (`enter`, `entry.jl:193`): if the position has a `Crossing` and `t`'s type is known to cross, `t` is replaced by `crossed(Y, t)` and only its view's trait object is assembled. Otherwise the trait object `v` of `t` is assembled, and the first call for the type decides; a container that crosses is then not assembled as it is again (under `all`, a `Dict{String, Any}` fails the `Iterable` family's check, and its slow path would run at each call).
- **Whether `t` crosses** (`_crosses`, `entry.jl:249`): its trait object meets none of the tag sets in `R`, and the view's does. Decided once per crossing and container type, in a flag the entry's code holds as a constant (a family member's trait object, every Base container's, has a type known only when it is built). The decision is machinery (`_cross_decide`), listed by `verify_main` as a guard. A container of kept values of `Y` meets the bound as it is, without a view (`_cross_view`).
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
- **registers** `bounded_constructor(S)`, so that the check of rule 3 lets trait code pass a trait object to the constructor.

`_kept_at` applies the bound: for `Callable{A, S}`, `enter_callable` at the position, then the function itself (`Compiled`) or a `Dynamic{Callable{A, S}}`; for a trait `X`, a trait object by its key, a kept value or a cast by its attribute, a plain value by the first-seen rule (the trait's default, then `known`), then the user's object (`Compiled`, a kept value's opened by its type at this call) or a `Dynamic{X}`. It refuses, at the definition, a bounded parameter that types two fields, or a field that uses it inside another type, or a free parameter no other field names.

**Planned:** `Dynamic{(X, Y)}`, a value seen through several traits.


---

## 14. Checks, and where their results live

**Status: Implemented** (deviations [L-9](#18-deviations), [L-10](#18-deviations), [L-17](#18-deviations)). What each check means and raises is [`traits.md#9-checks-and-when-they-run`](traits.md#9-checks-and-when-they-run); here is where it runs and what is kept.

| When | What runs | Code | Kept |
|---|---|---|---|
| `@trait` | the form of the body | the macro (`trait.jl:191`) | — |
| `@implement`, expansion | the form; refusal of a redeclaration; ownership of an operation's function before any method is defined | `_implement_expand`, `_op_method` (`implement.jl:930`, `:824`) | — |
| `@implement`, top level | ownership and delegation; completeness; result types by inference; fields; concreteness; supertraits implemented; overrides so far | `_check_implementation_now`, `_check_projection_now`, `_check_own_fields_now`, `_declare_conformance_now` (`implement.jl:496`–`653`) | the declaration's records, not the checks' results |
| a method definition | an override after an implementation; strict mode; keep flags of a complete module | the definition hook ([§16](#16-sessions-loads-and-hooks)) | — |
| an image's activation | overrides and, in strict mode, winning pirates left inactive | the image hook | reported after the load |
| a trait module's statement | ownership of each new method; no plain method in an entry's place | `_check_methods`, `_check_entries_intact` (`trait_module.jl:731`, `:746`) | — |
| a trait module's end | needs and keep flags fixed; overrides; joint methods; ambiguities; definition checking | `_finish_module` (`trait_module.jl:794`) | `needed` and `keeps` methods, in the module's image |
| a worker signature's first call | no worker at these parameters; overrides; the rules at the real signature, unless checked at the definition; concrete mode | `_check_once` (`checks.jl:334`) | a flag embedded in the signature's compiled code; `__tw_checked__` while an image is built |
| every call at the entry | conformance; bounded keywords; a family member's concreteness | [§8.2](#82-the-entry) | — |
| every operation call | arguments and result | `opcall` | — |
| every `Callable` call | arguments and result | `CObj` | — |

**Definition checking** (`check_definitions`, `defcheck.jl:159`) infers each worker once at **archetypes**, which stand for every key, the erased key included, so the worker at the erased key needs no check of its own: a stand-in key per bound, `Archetype{X, P}` with `P` the parameters the bound fixes, whose views have the witness `ArchWit` (`defcheck.jl:18`, `:64`). At `ArchWit` an operation and a field return an opaque value asserted to the declared type, and nothing more (`defcheck.jl:35`). The rules are checked on the inferred code (`worker_problems`, `checks.jl:77`).
- The rule check reflects the worker with the default interpreter: at archetypes, facts inference in the facts cache. An archetype never runs, so no code the program calls comes from it. The keep analysis ([§8.4](#84-keeping)) and the result-type checks infer plainly, at archetypes in the checks' own cache (`_CheckOwner`).
- While a package is precompiled, a problem fails the build. Elsewhere it warns, and the first call raises.
- Methods checked clean are recorded (`_DEF_CHECKED`). Their workers' first calls skip the rule check.
- **Intended:** only a bound with an open parameter and a `Callable` with an open result type wait for the first call. **As built,** keyword workers, vararg workers and every worker with a `Callable` argument wait too (`defcheck.jl:84`–`96`; [L-10](#18-deviations)).

**The first-call check** (`checked_call`, `checks.jl:253`) is a generated function. Each worker signature gets its own flag, a `Ref` embedded in its compiled code. The check runs once per signature, through `invokelatest`, behind an inference barrier, so compiled code holds no edge to it. Its rule check reflects the worker with the default interpreter: for a facts method that is facts inference, the code that runs, kept with it.

**Concrete mode** runs in the first-call check (`_check_concrete`, `concrete.jl:513`): abstract values traced to their root causes, and the fully-typed certificate ([§15](#15-compiling-ahead-workloads-closed-builds)). Its level is a constant `__tw_concrete__` of the module, or a `concrete_level(::typeof(f))` method for one function.

**Kept in images:**
- the declarations' records, builders and `conformance` methods;
- each trait module's `needed` and `keeps` methods;
- `__tw_checked__`: the worker signatures whose first-call check passed while the image was built, in the conforming type's module, else the declaring module ([§15](#15-compiling-ahead-workloads-closed-builds));
- family registries filled by the workload.

**Not kept:** the definition checks' results ([L-9](#18-deviations)), the slow path's caches, the `Callable` wrapper cache, `Erased` pointers.

---

## 15. Compiling ahead, workloads, closed builds

### 15.1 Compiling ahead from declarations

**Status: Implemented** (deviation [L-15](#18-deviations)).

While a package that declares `@implement X T` is precompiled (`_compile_ahead`, `ahead.jl:17`), for each trait module loaded at that point and each of its fixed-arity entry positions whose needs include `X` (`_compile_ahead_now`, `ahead.jl:94`):
- **the workers** whose only trait position is that one and whose other arguments are concrete ([traits §13](traits.md#13-compiling-ahead): a function with several trait positions is compiled at its first call), at the trait object of `T`'s builder. Each one's first-call check runs now, a failure fails the build, and the signature is added to `__tw_checked__` (`_check_ahead!`, `ahead.jl:58`);

- **the table's pattern method** at `T`'s builder, for untyped callers of `Compiled` values ([§9.3](#93-untyped-callers-of-compiled-values-the-table)).

**The worker at the erased key** is not compiled from declarations: no key of `T` names it. A workload that reaches it compiles it into the image ([§15.2](#152-workloads)), where it splits over the candidates registered then ([§13](#13-dynamicx)).

The list is exact because implementations are declared. A load of the image adds its `__tw_checked__` to the session's set (`_note_checked_ahead!`, `ahead.jl:30`).

`JULIA_TW_AHEAD=0` turns it off.

### 15.2 Workloads

**Status: Implemented.**

`TraitWorld.@workload begin … end` fixes the trait module's needs and keep flags first (`_finish_needed`), then runs PrecompileTools' `@compile_workload` (`TraitWorld.jl:166`). So the workload compiles the entries as they stay.

### 15.3 `verify_main`, `fully_typed`, closed builds

**Status: Implemented** (deviation [L-14](#18-deviations)).

**`verify_main(main, argtypes; entrypoints)`** (`verify.jl:881`) walks the optimized code reachable from `main`. It classifies every call:
- **static:** an `invoke`;
- **bounded:** a dynamic call with finitely many known targets;
- **trait:** a step of the machinery, with targets enumerated from the argument types and the declared implementations: the builder per user type, the worker per signature, a function's wrapper, the operations on `Dynamic` values per trait-object type the program keeps; at the erased key, every declared implementation as a target ([L-35](#18-deviations)) of the split's fallback and of the entry's conformance check;
- **guard:** the machinery's slow paths, not followed (`_machinery_method`, `verify.jl:464`);
- **hole:** anything else, marked when it lies only on a path to an uncaught throw.

It runs the rule check of every enumerated worker. With `entrypoints = true` it registers every target with `Base.Experimental.entrypoint`.

**A closed build** (`entrypoints = true` under `--trim`) closes the world (`close_world!`, `verify.jl:1011`):
- the slow path's cache is filled from the walk's plans;
- `CLOSED_WORLD` is set: the first-call checks are skipped (they ran at build time), a slow-path miss raises, and `Callable` arguments are not erased;
- under `--trim` the facts mode is off ([`facts.md#closed-builds`](facts.md#closed-builds)).

**`fully_typed(f, argtypes)`** (`certificate.jl:33`) is `verify_main`'s walk from a call of `f` at the argument types: the holes on normal paths are the run-time sites; operations on `Dynamic` values count as declared sites.

**Planned:** the inverses of `Like` results among the targets; a lint for calls reached from trait code that select a pirate.

---

## 16. Sessions, loads and hooks

**Status: Implemented** (deviation [L-18](#18-deviations)).

**At TraitWorld's load** (`__init__`, `TraitWorld.jl:21`):
- a new session stamp, which makes the flags saved in images stale (candidate registrations, the crossing's decisions);
- the method-definition and image hooks ([compiler §5.1, the definition and image hooks](compiler.md#51-method-definition-and-image-activation-hooks)), and keep-compiled for images built in this process;
- strict mode from `JULIA_TW_STRICT`;
- the type printers for `TObj`, `CObj` and `Builder` ([compiler §5.3, type printers](compiler.md#53-type-printers)): a trait object's type prints by bound and key, `at Dynamic` at the erased key;
- a filter that hides TraitWorld's frames in backtraces, through Base's `update_stackframes_callback` (`frames.jl:48`);
- an error hint naming the bound for a `MethodError` at a bounded position;
- a package callback.

**After every package load** (`_on_package_load`, `TraitWorld.jl:45`): the candidates of newly loaded implementations are registered, the image's `__tw_checked__` is read, known delegates are noted, and refused methods are reported.

**The definition hook** (`_on_method_definition`, `hooks.jl:160`), compiled by facts:
- refuses an override of an operation a fixed implementation serves by a default;
- in strict mode, refuses a pirate that would win at a fact of compiled trait code. Before the definition it reads Julia's backedges; after it, Julia's invalidation log as a safety net, deleting the method again if trait code was invalidated by a non-stakeholder (`strict.jl:1`);
- recomputes the keep flags of a complete trait module that gains a method.

**The image hook** (`_on_image_methods`, `hooks.jl:230`) leaves an image's overriding methods, and in strict mode its winning pirates, inactive, and reports them after the load.

**Planned, for strict mode's intended design:** a deletion hook, a read-only query of what a definition would invalidate, and image validation naming the winning method, in place of reading backedges ([compiler §5.4](compiler.md#54-planned-hooks-for-strict-modes-intended-design)).

---

## 17. Encodings until traits are in the type system

**Status: Implemented** as encodings; their removal **Planned**, last ([compiler §7, traits in the type system](compiler.md#7-traits-in-the-type-system)).

Julia has no trait in its type system, so TraitWorld encodes what membership as subtyping and a trait dispatch tier would give. Each encoding is a deviation:

| Encoding | Stands in for | Where | ID |
|---|---|---|---|
| the trait type carries the key as its last parameter, `X{P…, Self}`; trait instances `X{p…, K}` | a trait `X{P…}`, the key a parameter of the view only | `trait.jl:198`, `core.jl:316` | [L-1](#18-deviations) |
| trait sets as families plus `PTag{F, i, v}`; workers on `TObj{T} where T >: Union{…}` | a bound as a type in the method's signature | `core.jl:229`, `trait_module.jl:470` | [L-2](#18-deviations) |
| entries as methods at `Any` per shape, with the `Untyped` tag for fallbacks and hand-written joint-method and ambiguity checks | a trait bound as a dispatch tier above `Any` and below every type; entries and workers generated by the compiler | `trait_module.jl:528`, `entry.jl:28`, `trait_module.jl:840`, `:889` | [L-3](#18-deviations) |
| registries as methods of `@max_methods 1` functions with fallback (sentinel) methods, and the dispatch tokens `As{X}`, `EntryPos`, `TraitList`, `KeepOf` | declarations the type system holds, read without edges | `core.jl:303`–`641`, `entry.jl:112`–`205`, `implement.jl:28`, `:57` | [L-4](#18-deviations) |
| `conforms(T, X)` | `T <: X`, `x isa X` | `entry.jl:757` | [L-5](#18-deviations) |
| a trait's name as `Kept` inside trait modules, by rewriting their source; a struct parameter's trait bound stripped and applied by a generated constructor | a trait's name as an abstract type in any field or container; a trait as a parameter's bound | `trait_module.jl` (`_dynamic_fields`, `_dyn_body`, `_bounded_struct`) | [L-6](#18-deviations) |
| attributes as annotation types read by the rewrite, `Compiled{X}`, `Dynamic{X}`; item positions as the tag `Through{Y, A}`; the conversions as wrapper types `CompiledFor`, `WithDynamic` | an attribute on a bound, and a bound on a parameter, in the type system | `trait_module.jl` (`_classify`), `core.jl` | [L-2](#18-deviations) |

The meanings are permanent ([`traits.md#14-membership`](traits.md#14-membership)); only these forms go.

---

## 18. Deviations

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-1 | [§3](#3-trait-declarations), [§5](#5-keys-and-views) | a trait is `X{P…}`; the key is a parameter of the view | the trait type has the key as its last parameter, `X{P…, Self}`; trait instances name the key | `TraitWorld/src/trait.jl:198`, `core.jl:316` |
| L-2 | [§5](#5-keys-and-views) | a bound is a type in the worker's signature | trait sets are unions of families and `PTag`s; workers take `TObj{T} where T >: Union{…}` | `core.jl:229`, `trait_module.jl:470` |
| L-3 | [§8.1](#81-the-rewrite), [§17](#17-encodings-until-traits-are-in-the-type-system) | a trait bound is a dispatch tier; entries are generated by the compiler | entries are methods at `Any` per shape; the fallback is tagged `Untyped`; joint methods and ambiguities are checked by hand; so an untyped fallback of a bounded method's shape must be defined after the bounded methods, and only a function's owner may add a bounded method of a shape the function has none of yet (traits §5.5 states the rule as ownership alone) | `trait_module.jl:456`, `:528`–`715`, `:840`, `:889` |
| L-4 | [§3](#3-trait-declarations), [§17](#17-encodings-until-traits-are-in-the-type-system) | declarations read without edges | registries are methods of `@max_methods 1` functions, some with sentinel fallbacks ([§3](#3-trait-declarations) lists them). No edge is recorded only where at least two methods apply. Where exactly one does (by reading Julia's `max_methods` rule; not run), inference infers it with an edge for the abstract signature, and the first declaration whose method intersects that signature invalidates the code: a tabled entry's `conformance(As{X}(), ::Any)` compiled while `X` has no declared implementation; a specialized entry inlined into a plain caller at an abstract type that no declared implementation's type intersects; a record function without a sentinel, at its one method; `keeps` and `needed` before the module's end (intended: the module redefines them) | `core.jl:303`–`641`, `entry.jl:114`, `:174`, `:205`, `implement.jl:28`, `:57`, `:625`, `untyped.jl:102` |
| L-5 | [§17](#17-encodings-until-traits-are-in-the-type-system) | membership is `T <: X` | `conforms(T, X)` | `entry.jl:757` |
| L-6 | [§13](#13-dynamicx) | a trait's name as a type means `Kept{X}`, a value with its attribute | only inside trait modules, by rewriting struct fields, containers and argument types | `trait_module.jl` (`_dynamic_fields`, `_dyn_body`, `_dyn_sig`) |
| L-7 | [§4.1](#41-what-every-form-defines), [§4.4](#44-forwarding-with-by) | forwarding is written with `by` and recorded as forwarding | `by f` is lowered to a projection `project(t) = getfield(t, :f)`; a written `project(t) = t.f` is accepted as forwarding; TraitWorld's own precompile workload and tests use `project(t) = …` and the `{R}` spelling | `implement.jl:911`, `:1298`–`1305`; `TraitWorld.jl:88`, `:103`–`106`; `test/runtests.jl:50` |
| L-8 | — | *Retired*: see [§13](#13-dynamicx). | — | — |
| L-9 | [§14](#14-checks-and-where-their-results-live) | a worker checked at its definition is not checked again at its first call | the record of definition-checked methods is a session's set, filled only where the trait module's end runs; in a session that loads the package from its image, a worker signature whose checked code no image holds runs the rule check at its real signature at its first call | `defcheck.jl:119`, `:173`; `checks.jl:342` |
| L-10 | [§14](#14-checks-and-where-their-results-live) | only open parameters and open `Callable` result types wait for the first call | keyword workers, vararg workers and every worker with a `Callable` argument wait too | `defcheck.jl:84`, `:89`, `:93` |
| L-11 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-12 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-13 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-14 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-15 | [§15.1](#151-compiling-ahead-from-declarations) | the workers of every bounded function with one trait position whose bound includes `X` are compiled ahead, where the other arguments are concrete | vararg positions are skipped; so are entries with several trait positions: no worker, no pattern method and no entry method is compiled ahead for them | `ahead.jl:100`, `:132`, `:138`, `:151`–`152` |
| L-16 | [§11](#11-results-like-the-input) | the inverse is compiled for the caller's type, and its result has that type | the inverse runs behind an inference barrier through a `Dict` and the constructor; a typed caller's result is `Any` | `trait_module.jl:633`, `:702`; `entry.jl:681`–`739` |
| L-17 | [§2](#2-modes-owners-and-images), [§14](#14-checks-and-where-their-results-live) | the machinery's code is facts code, protected as trait code | machinery that calls compiler functions directly holds edges to plain compiler code, valid only as long as plain Julia keeps it valid | `checks.jl:97`–`117`; `defcheck.jl:236`–`258`; `core.jl:348`, `:415`; `compiler.jl:57`, `:68` |
| L-18 | [§16](#16-sessions-loads-and-hooks) | strict mode asks Julia what a definition would invalidate ([compiler §5.4](compiler.md#54-planned-hooks-for-strict-modes-intended-design)) | it reads backedges before the definition and the invalidation log after it, deleting the method again on a miss | `strict.jl:1`–`14`, `:123`, `:197` |
| L-19 | [§3](#3-trait-declarations) | a trait's body holds operations, defaults, fields, equations and concreteness lines ([`traits.md#1-syntax-summary`](traits.md#1-syntax-summary)) | `@mutating` is accepted in a trait's body and recorded as `is_mutating`, which no code reads | `trait.jl:284`; `implement.jl:132` |
| L-20 | [§13](#13-dynamicx) | an operation on a `Dynamic` of a parametric trait asserts its declared result at the parameters the `Dynamic`'s type fixes, so a `Dynamic{StateVector{Float64}}` operation declared `::T` is typed `Float64` | the result type is `Any` wherever the declared type names `Self` or any parameter, fixed or not; the code after the call is not inferred | `trait.jl:303`–`304` (`dep`, `retx`), `:314`, `:318` |
| L-21 | [§5](#5-keys-and-views) | an implementation whose operations are all served by defaults has no receiver type | it has one also when the trait's declarations name `Self`, or when a parameter is not defined by a field: then the conforming type is the receiver type and gets its own compiled copy | `entry.jl:456`–`465` (`_no_implementing_type`) |
| L-22 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-23 | [§4.6](#46-families) | A later declaration for one member of a family is a more specific `conformance` method, until the member's first use. | The member's declaration makes its own `conformance` method (`_declared_for`); a declaration after the member's first use is not refused. As [traits T-28](traits.md#17-deviations). | `implement.jl` (`_declared_for`) |
| L-24 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-25 | [§13](#13-dynamicx) | Candidates are registered for each declared implementation at a concrete type, after each declaration and each package load. | Types with an `implementation` or a `projection` record at a concrete type are registered then (types that forward, or conform by a field mapping, since branch `basetraits` 8863ea0). A family member's record has a `UnionAll` signature: it is registered only when a `Dynamic` of such a value is made, and code compiled before that takes the fallback for it. | `core.jl:532` (`_note_conformances!`; branch `basetraits`) |
| L-26 | [§4.5](#45-field-mappings-several-traits-stated-parameters) | A stated value for a parameter an equation defines is checked against the equation and makes no method. | For one type: checked, and no method is made when it agrees (`_param_agrees`). For a family: it becomes a `param` method with the family's `where`, replacing the equation's value, unchecked. As [traits T-37](traits.md#17-deviations). | `implement.jl` (`_param_methods`) |

| L-27 | [§13.1](#131-a-users-container-crossing-by-its-bound) | A closed build lists and fills everything an entry can reach. | The crossing's decision (`_cross_decide`) is reflection run at the first call per container type; `verify_main` lists it as a guard, and `close_world!` does not fill its flags, so in a closed build the first call of a crossing position would need it. Not tried with `--trim`. | `entry.jl:249`; `verify.jl:491` |
| L-28 | — | *Retired*: see [§9.2](#92-untyped-callers-the-erased-worker). | — | — |
| L-29 | — | *Retired*: see [§5](#5-keys-and-views). | — | — |
| L-30 | — | *Retired*: see [§12](#12-callable-and-dynamiccallable). | — | — |
| L-31 | [§13](#13-dynamicx) | a trait object reaching a `Callable`'s argument declared `Dynamic{X}` is converted (the seams) | the conversion is made for an operation's arguments only (`_seams` in `opcall`); a `CObj`'s check `args isa A` refuses a trait object where `A` declares `Dynamic{X}`: pass `Dynamic{X}(t)` | `TraitWorld/src/core.jl` (`CObj`'s call), `src/attributes.jl` (`_seams`) |
| L-32 | — | *Retired*: see [§4](#4-implementations). | — | — |
| L-33 | — | *Retired*: see [§13.1](#131-a-users-container-crossing-by-its-bound). | — | — |
| L-34 | — | *Retired*: see [§8.3](#83-needs-and-the-modules-end). | — | — |
| L-35 | [§15.3](#153-verify_main-fully_typed-closed-builds) | `verify_main` lists, at the erased key, every declared implementation as a target of the split's fallback and of the entry's conformance check | not done: for a program with untyped calls `verify_main` reports the program's run-time sites as holes, as before the erased key (checked by reading and one run, 2026-10-20); a closed build of code at a `Dynamic` position is not tried | `TraitWorld/src/verify.jl` |
