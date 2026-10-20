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
12. [`Callable` and `DynamicFn`](#12-callable-and-dynamicfn)
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
- the **worker**, the body as written, compiled by facts per tuple of keys;
- the **entry**, an ordinary method that translates each argument by its bound once and calls the worker. It is compiled in its caller's mode.

What every construct becomes:

| Construct | Becomes | Made | Code compiled as | Kept in |
|---|---|---|---|---|
| `@trait X` | an abstract type; the operation functions; one method per operation on trait objects and on `Dynamic{X}`; records of operations, fields, parameters, defaults | at the declaration | operation methods: inside the workers that call them | the declaring module's image |
| `@implement X T …` | records; a `conformance` method with a builder fixed now; for a block, the operations' methods | at the declaration | `conformance`: a boundary, compiled in its caller's mode | the declaring package's image, with the code compiled ahead ([§15](#15-compiling-ahead-workloads-closed-builds)) |
| a family member | a builder in the family's registry | at the member's first use | as above | the declaring package's image, for members its workload uses |
| a bounded function | a worker; an entry per shape; for untyped callers, a pattern method and two tables | at the definition; the entry's needs at the trait module's end | worker: facts; entry: a boundary | the image whose precompilation compiled them |
| a `Callable` argument | a `CObj` holding the function or a caller-world pointer | at the entry, per call | worker per signature (`DynamicCall`) or per function type (`CompiledCall`) | as for workers |
| `Dynamic{X}` | a struct holding the user's object; its operations are call-site splits over the held object's type | methods at `@trait`; values at run time | in the caller | — |

**Shared code.** A worker is compiled per view type. A view's type depends on the trait, the key and the witness, never on the user's type ([§5](#5-keys-and-views)). So every type with the key of an existing worker runs that worker, wherever it was compiled.

---

## 2. Modes, owners and images

**Status: Implemented** (deviation [L-17](#18-deviations)).

The facts mode and its owners are Julia's ([compiler §2.2, the method flag](compiler.md#22-the-method-flag-boundaries-and-always-facts-methods); what code may assume: [facts §5, run-time sites](facts.md#run-time-sites)). TraitWorld places each piece of code in one of these modes:

| Code | Mode | How it is marked |
|---|---|---|
| a trait module's methods: workers, internal functions, closures, the pattern methods of untyped entries | facts, cache owner `:facts`, whoever calls them | `Base.Experimental.@compiler_options facts=true` in the module's prologue (`trait_module.jl:60`) |
| what a worker calls (operation methods, the user's methods serving operations, Base) | inferred by facts with the worker | Julia's rule; the compiler's own code stays plain |
| entries, `conformance` methods, entry methods for types compiled ahead | the caller's mode (a *boundary*) | `Expr(:meta, :facts_boundary)` (`trait_module.jl:709`, `implement.jl:675`, `ahead.jl:182`) |
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
- One method per operation and arity **on `Dynamic{X}`**: a call-site split ([§13](#13-dynamicx), `trait.jl:301`).

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
- A fallback (*sentinel*) method makes two apply: `trait_params`, `trait_fields`, `trait_uses_self`, `trait_field_params`, `field_isrep`, `has_default`, `is_mutating`, `trait_concreteness`, `supertraits`, `bundle`, `implementation`, `projection`, `conformance`, `needed`, `keeps`, `_declared_builder` have one.
- The others have none: `trait_ops`, `op_function`, `op_args`, `op_ret`, `op_default`, `generic_op`, `generic_rec`, `param`, `param_bound`, `field_type`, `_fieldmatch`, `_fieldpos`, `_declared_defaults`.
- Where exactly one method applies, the sentinel or a declaration's, inference infers it and records an edge for the abstract signature ([L-4](#18-deviations)).

**Fields on trait objects.** For each declared field, a method of `_tgetprop(t::TObj{T}, ::Val{f}) where T >: X` and of `_tsetprop!` (`trait.jl:330`). `getproperty` and `setproperty!` on a `TObj` reach them; a `@const` field's setter raises ([§6](#6-trait-objects-layout-fields-writes)).

**Equations** `T = eltype(Self)` become `param` methods evaluated at the key's receiver type (`trait.jl:223`). At an archetype, a parameter is the value the bound fixes or an opaque `ParamArchetype` (`trait.jl:205`).

After the declaration, `_bump!()` registers the candidates of implementations declared so far ([§13](#13-dynamicx)).

---

## 4. Implementations

`@implement` ([`traits.md#5-implementations`](traits.md#5-implementations)) is expanded by machinery code compiled by facts (`_implement_expand`, `implement.jl:930`). The expansion runs in the declaring module, at the declaration. Every form defines methods, so the declaration is saved with the declaring package's image and owned by it.

### 4.1 What every form defines

**Status: Implemented** (deviation [L-7](#18-deviations)).

| Defined | Meaning |
|---|---|
| `implementation(X, R) = ImplRec(kind, defaults)` | the receiver type `R` implements `X`: by a block (`:methods`, the operations defaults serve), by its existing methods (`:existing`), or as a family (`:family`) (`implement.jl:24`) |
| `projection(X, T) = ProjRec(…)` | for a type that conforms through a field or a field mapping: the receiver type `R`, the forwarding field's index (0: none), the field mapping, a table of dynamic operations (`implement.jl:45`) |
| `conformance(::As{X}, u::T)` | the implementation as a method: an `@inline` boundary that calls the builder fixed now (`implement.jl:669`) |
| `_declared_defaults(X, T)` | the operations defaults serve, per trait of the closure: what an override would change ([§4.9](#49-overrides-and-redeclaration)) |
| `_declared_builder(As{X}, T)` | the same builder, for the untyped calls' table ([§9.2](#92-untyped-callers-the-table-of-declared-implementations)) |
| `_compile_ahead(mod, X, T)` | while the package is precompiled: the code calls with a `T` need ([§15](#15-compiling-ahead-workloads-closed-builds)) |

**The builder** is fixed when the implementation is declared (`_declare_conformance`, `implement.jl:640`). It is data: per trait of the closure, a `VSpec` with the witness and the slots ([§5](#5-keys-and-views)). It is a constant of the declaring module, so its image keeps it. An implementation whose witness holds a session's pointers has no builder; its `conformance` method takes the slow path ([§4.8](#48-dynamic-operations)).

**Checks** run at the declaration, from the expansion's top-level code ([§14](#14-checks-and-where-their-results-live)): `_check_implementation` for a receiver type's operations, `_check_projection` for a type that conforms through a field or mapping, `_check_own_fields` for the one-line form.

### 4.2 A block of methods

**Status: Implemented.**

`@implement X T begin ncols(t) = …; … end` ([`traits.md#51-with-a-block-of-methods`](traits.md#51-with-a-block-of-methods)):
- Each definition becomes a method of the operation's function, qualified by its module, with the receiver typed `T` and unannotated arguments typed as declared (`_op_method`, `implement.jl:801`).
- `implementation(X, T) = ImplRec(:methods, D)`, with `D` the operations left to defaults.
- No `projection` record: `T` is its own receiver.
- The methods are ordinary methods of `T`. Plain code calling `ncols(x::T)` finds them.

### 4.3 One line

**Status: Implemented.**

`@implement X T` ([`traits.md#52-one-line`](traits.md#52-one-line)) declares `T`'s existing methods (`_implement_oneline`, `implement.jl:1147`):
- `implementation(X, T) = ImplRec(:existing, ())`. The operations served by defaults are those `T` has no method for, fixed at the declaration.
- A trait with fields only, or a field mapping, adds `projection(X, T) = ProjRec(identity, I, …)`, with `I = Nothing` for a trait without operations.
- The expansion never picks a field. Without methods for the operations it raises, naming the fields whose type conforms with their `by` lines (`implement.jl:1199`).

### 4.4 Forwarding with `by`

**Status: Implemented** (deviation [L-7](#18-deviations)).

`@implement X T by f` ([`traits.md#53-forwarding-with-by`](traits.md#53-forwarding-with-by)):
- The receiver type is the field's declared type `R`. The record is `projection(X, T) = ProjRec(…, R, …, field index of f, …)`.
- No method is defined for `T`'s operations. Defaults and the field type's methods serve trait code only.
- The witness is the field type's own: `witness(X, R)`, from `implementation(X, R)`. A field type that itself forwards has no `implementation` record, so forwarding does not chain (`_check_projection_now`, `implement.jl:526`).
- *As built,* `by f` is lowered to the projection `project(t) = getfield(t, :f)`, and the projection is accepted because it reads a field as is (`implement.jl:911`, `:1298`).

### 4.5 Field mappings, several traits, stated parameters

**Status: Implemented** (deviation [L-26](#18-deviations)).

- **A field mapping** `name => stored` is kept in the record (`ProjRec.fmap`). The builder takes each declared field's slot from the mapped stored field (`_mapped`, `entry.jl:434`).
- **Several traits** `(X, Y) T by f`: one `projection` record and one `conformance` method per trait. The entry merges their views into one trait object ([§8.2](#82-the-entry)).
- **Stated parameters** `@implement X{p…} T`: `param(X, Val(:p), T)` and `param(X, Val(:p), Key{T, F})` methods (`_param_methods`, `implement.jl:1008`), for the parameters no field and no equation defines.
- **A stated value for a parameter an equation defines** makes no method: the declaration's check compares it with the equation's value at `T` and refuses the implementation if they differ ([traits §5.6](traits.md#56-stating-parameters)). The equation's `param` method serves `T`.

### 4.6 Families

**Status: Implemented** (deviation [L-23](#18-deviations); the family-wide check [traits T-26, T-27](traits.md#19-deviations)); forwarding for a family **Planned**.

`@implement X S{P} where {P} [begin … end]` ([`traits.md#57-families`](traits.md#57-families)) defines (`_family_conformance_methods`, `implement.jl:690`):
- the operations' methods with the `where` clause, for a block;
- `implementation(X, S{P}) where {P}`, for the whole family;
- **a registry** in the declaring module: `const reg = Ref(IdDict())`, found again after an image loads through `_family_registry(Val(name))`;
- `conformance(::As{X}, u::S{P}) where {P} = _conf_family(reg, X, u)`.

**A member is fixed at its first use** (`_conf_family_slow`, `implement.jl:707`):
- the slow path finds the member's builder, checks its operations (a family of existing methods), refuses an abstract parameter under `@concrete_only`, and stores the builder in the registry, copy-on-write;
- the member's default-served operations are added to the override index then ([§4.9](#49-overrides-and-redeclaration));
- builders found by the declaring package's workload are saved with its image; a builder holding session pointers is not kept.

A later declaration for one member is a more specific `conformance` method.

**Planned: forwarding for a family**, `@implement X S{T} by f where {T}`: the family's `conformance` method with a builder per member that reads field `f`.

### 4.7 Generic implementations

**Status: Implemented** (the form); the overlap check **Planned**; what a predicate may say **Open** ([`traits.md#58-generic-implementations`](traits.md#58-generic-implementations)).

`@implement X R where {R: Y, pred} begin … end` defines (`implement.jl:1110`):
- `generic_rec(X, Val(k)) = GenericRec(constraints, predicate, defaults)`, with `k` a fresh name;
- each operation as a method of `generic_op(X, Val(k), Val(op), t, args…)`, where `t` is a trait object carrying the constraint traits;
- no `conformance` method: the generic `conformance` fallback finds the implementation ([§8.2](#82-the-entry)).

At a type's first call, `_witness` (`implement.jl:337`) tries each generic record: the constraints' witnesses, then the predicate, in the decision world. The witness is `Generic{X, k, S, D}`, holding the constraints' witnesses. More than one match is an error. A more specific declared implementation is found first, as a `conformance` method of its own. The generic implementation's results are checked at the first concrete type, with a warning (`_generic_problems`).

### 4.8 Dynamic operations

**Status: Open** ([`traits.md#59-dynamic-operations`](traits.md#59-dynamic-operations)).

`@implement X T dynamic by f begin … end` adds to the `projection` record a table of the block's functions. At the first call in a session, the witness becomes `Dyn{NT, D}`: each operation erased to a caller-world pointer at its declared signature ([§12](#12-callable-and-dynamicfn), `_dyn_witness`, `implement.jl:442`). No builder is fixed at the declaration, since pointers belong to a session. Every session finds it through the slow path.

### 4.9 Overrides and redeclaration

**Status: Implemented**; redeclaration **Planned** ([`traits.md#510-checks-at-the-declaration`](traits.md#510-checks-at-the-declaration)).

- `_declared_defaults(X, T)` records `(trait, receiver type, operations)` for each trait of the closure (`implement.jl:625`). Family members add theirs at first use.
- From these, an index maps each operation function to the implementations its defaults serve (`_OVR_INDEX`, `hooks.jl:62`).
- **At a definition,** the method-definition hook refuses a method of an indexed operation for an indexed receiver type ([§16](#16-sessions-loads-and-hooks)).
- **At an image's activation,** the image hook leaves such a method inactive and reports it after the load.
- **Checkpoints** scan the records again (`check_overrides`, `implement.jl:753`): at each declaration, at a trait module's end, at a worker's first call.
- **Redeclaration** with a block is refused when `T` already has a `conformance` method of its own (`implement.jl:949`, `:972`). Other forms are accepted with another meaning ([traits T-29](traits.md#19-deviations)). *Planned:* redeclaration on Julia 1.13's struct redefinition: a new `conformance` method and records, old values keeping the old builder.

---

## 5. Keys and views

**Status: Implemented** (deviations [L-1](#18-deviations), [L-2](#18-deviations), [L-21](#18-deviations)).

The key ([`traits.md#4-keys-what-code-is-compiled-for`](traits.md#4-keys-what-code-is-compiled-for)) is lowered as follows (`_key_and_slots`, `entry.jl:442`):
- **A trait without fields:** the key is the receiver type `R`.
- **A trait with fields:** `Key{I, F}`, with `I` the receiver type and `F` a named-tuple type of the declared fields' stored types (`core.jl:70`).
- **No receiver type** (`I = Nothing`): every operation is served by a default ([traits §4](traits.md#4-keys-what-code-is-compiled-for)). *As built,* also the declarations must not name `Self`, and fields must define every parameter (`_no_implementing_type`, `entry.jl:456`; [L-21](#18-deviations)).

**A view** is one trait's part of a trait object: `View{Xi, W, K, N, P}` or `Held{Xi, W, K, N, P}` (`core.jl:86`, `:101`), with
- `Xi` the trait instance `X{p…, K}`;
- `W` the **witness**, a type saying where the operations come from: `Impl{D}` (the receiver type's own methods, `D` those served by defaults), `Generic{…}`, `Dyn{…}`, or `ArchWit` at an archetype (`defcheck.jl:31`);
- `K` the key, `N` the number of declared fields, `P` the type of the parts the view holds.

**The builder** of a user type is `Builder{Tuple{VSpec…}}`, one `VSpec{Xi, W, K, N, P, S}` per trait of the closure (`entry.jl:40`, `:47`). A `VSpec` holds the witness, the receiver's slot and the declared fields' slots. A *slot* is a byte offset and a field index; offset −1 means the object itself (`core.jl:56`). `S` says that the user's type is its own receiver.

**Why a new type with an existing key compiles nothing in the library:**
- its views have the key's view type, so the worker for that view type serves it;
- its builder's type depends on the trait, the key, the witness and `S`, not on the user's type, for every type that forwards or is keyed by its fields alone;
- what the declaration adds is data (the builder's witness and slots) and one small `conformance` method, compiled into callers that know the type.

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
2. checks the arguments against `op_args` at the key: `TraitArgumentError` otherwise;
3. dispatches on the witness (`_dispatch`, `core.jl:671`):
   - `Impl{D}`: a default (`op_default`, with the whole trait object, so it may call supertraits' operations) if `op ∈ D`, else `op(receiver, args…)`, the receiver type's own method;
   - `Generic`: `generic_op` on a trait object built from the constraints' witnesses;
   - `Dyn`: the erased pointer, or the default;
4. asserts the result to `op_ret` at the key.

For a concrete view type, the witness, the default test and the declared types are constants. The call to the receiver type's method is a call at concrete types: a fact.

---

## 8. Bounded functions: workers and entries

### 8.1 The rewrite

**Status: Implemented** (deviation [L-3](#18-deviations)).

`@trait_module` wraps every top-level statement in `@stmt`, so each is expanded after the ones before it have run (`trait_module.jl:71`). A function definition with a trait bound, a `Callable` bound or a trait vararg is rewritten (`_rewrite_fdef`, `trait_module.jl:413`) into:
- **the worker:** the definition as written, with each bounded argument typed `TObj{T} where T >: …` ([§5](#5-keys-and-views)), each `Callable` argument `CObj{A, S}`, several `Callable`s `CMulti`. It is a method of the trait module, so Julia compiles it by facts;
- **the entry,** once per *shape* (the pattern of annotated positions): a method with the bounded positions untyped, compiled in its caller's mode ([§8.2](#82-the-entry));
- for an entry of trait positions and ordinary arguments only, **a pattern method and its tables** for untyped callers ([§9.2](#92-untyped-callers-the-table-of-declared-implementations));
- **a note of each trait position** (`_note_position`), from which the entry's needs are fixed ([§8.3](#83-needs-and-the-modules-end)).

An untyped method of an existing entry's shape becomes the entry's **fallback**: `f(::Untyped, args…)` (`trait_module.jl:456`). An ordinary method that would take an entry's signature is refused (`_check_entries_intact`).

A worker calling a function with a trait object it carries reaches that function's worker directly: the trait object's type matches the worker's signature, and the entry at `Any` is less specific. A trait object reaching an entry raises `TraitBoundError`: its trait is not the one the callee needs (`_rule3_error`, `entry.jl:267`).

Internal functions without bounds take trait objects as ordinary arguments. Julia compiles them by facts as part of the worker's call graph.

### 8.2 The entry

**Status: Implemented.**

The entry is declared `@inline` and is a boundary (`trait_module.jl:709`). Its body, for each bounded position `i`:
1. `enter(EntryPos{typeof(f), i, nargs}(), x)` (`entry.jl:193`):
   - a `Dynamic` is opened: its trait object ([§13](#13-dynamicx));
   - a trait object raises (above);
   - otherwise `_assemble(needed(p), x)`: one `conformance(As{X}(), x)` call per needed trait, the views merged, each trait once (`entry.jl:225`);
2. `NOTRAIT` (the value conforms to none of the needed traits) returns `fallback(f, args…)`: the `Untyped` fallback, else the most specific ordinary method that is neither entry nor worker, else `MethodError` with a hint naming the bound (`entry.jl:484`, `frames.jl:64`);
3. `Callable` positions are translated by `enter_callable` ([§12](#12-callable-and-dynamicfn));
4. the worker is called through `checked_call(f, views…)`: the first-call check flag, then the call (`checks.jl:253`);
5. a result like the input goes through `_like_out` ([§11](#11-results-like-the-input)).

**`conformance`** has one method per declared implementation, and a fallback that finds generic implementations and implementations without a fixed builder (`_conformance_slow`, `entry.jl:144`). The slow path's results are kept copy-on-write per decision world.

**Dispatch, types first** ([`traits.md#65-dispatch-types-first-then-traits`](traits.md#65-dispatch-types-first-then-traits)): the entry's bounded positions are `Any`, so every type-annotated method is more specific. A value caught by one takes it and is never translated.

### 8.3 Needs and the module's end

**Status: Implemented.**

- **What a position needs** is `needed(EntryPos{F, pos, nargs}())`: a `TraitList` of the traits the workers of `F` bound there. Until the module is complete a fallback computes it by reflection (`entry.jl:183`). At the module's end, `_fix_needed!` defines one method per position, a constant (`trait_module.jl:776`). A later definition at the prompt redefines it when the needs change.
- **At the module's end** (`_finish_module`, `trait_module.jl:794`): the needs and the keep flags are fixed; overrides are checked; unrelated bounds without a joint method and ambiguities with typed methods are reported (`check_bounds`, `check_entry_ambiguities`); definition checking runs ([§14](#14-checks-and-where-their-results-live)).
- **The module's registries** are constants its prologue defines: `__tw_entries__` (shapes per function), `__tw_plain__`, `__tw_extended__`, `__tw_positions__`, `__tw_untyped__`, `__tw_finished__` (`trait_module.jl:60`).
- **Only the function's owner** may add an entry: an entry is a method at `Any` (`trait_module.jl:535`).

### 8.4 Keeping

**Status: Implemented.**

`keeps(KeepOf{F}())` says whether a worker of `F` may keep a trait object: make it a `Dynamic`, store it where a `Dynamic` is declared, or return a closure that captured it (`entry.jl:205`).
- It is decided at the module's end, by inferring each worker at archetypes in the checks' own cache and following internal functions and workers (`_analyze_keeps`, `defcheck.jl:277`).
- An answer the analysis cannot reach is `true`, the fallback. It costs a box, never a wrong result.
- The method-definition hook recomputes it for a function given a method after its module is complete (`hooks.jl:218`).
- Where it is `true`, the entry gives an immutable value's views the whole object ([§6](#6-trait-objects-layout-fields-writes)).

---

## 9. Callers: typed, untyped, compiled ahead

### 9.1 Typed callers

**Status: Implemented.**

A caller that knows the argument's concrete type compiles the entry for it:
- `needed`, the `conformance` method, the builder and the witness are constants there; the views are built in place;
- the worker's selection is a static call;
- in the patched build, Julia's inliner inlines the entry, as declared, and code of the other owner from that owner's cache ([compiler §2.7, inlining across owners](compiler.md#27-inlining-across-owners)).

The worker, compiled by facts, is shared by every caller of its key.

### 9.2 Untyped callers: the table of declared implementations

**Status: Implemented** for entries of trait positions and ordinary arguments (deviations [L-11](#18-deviations), [L-12](#18-deviations), [L-13](#18-deviations), [L-24](#18-deviations)).

A caller that does not know the type reaches the entry compiled at `Any`. The entry switches on `Compiler.known_type(x)` ([compiler §4.1, `known_type`](compiler.md#41-compilerknown_type)): it folds to `true` in a typed caller, which takes [§9.1](#91-typed-callers), and is `false` otherwise (`untyped.jl:19`, `trait_module.jl:646`). On the untyped path nothing is compiled per user type:

- **The value is held** in `XAny`, a concrete holder, so every call on the path is at a fact signature (`untyped.jl:22`).
- **One table per entry position,** `UTable`, a constant of the code that reads it (`_utable`, `untyped.jl:43`). A table entry maps a user type to its builder, valid for a range of worlds (`UEntry`). A miss finds the builder (`_declared_builder`, else `_builder_for`) and the worlds in which each needed trait's `conformance` method for the type is the same method (`_umiss`, `untyped.jl:64`).
- **The pattern method** `tw_untyped_f(b::Builder…, xa::XAny…)` is a method of the trait module, compiled once per tuple of builder types, that is, per tuple of keys. It builds the views from the builders' data, reading the held object at the slots' offsets (`_build_any`, `untyped.jl:123`), and calls the worker (`trait_module.jl:676`).
- **One trait position:** the entry calls the pattern method through a caller-world pointer, one per (pattern, builder type), kept in a `PTable` per pattern (`_pentry`, `untyped.jl:250`; [compiler §3.1, the `:caller_world` convention](compiler.md#31-the-cfunction-calling-convention-caller_world)). The pointer's wrapper `_UWrap` passes every argument on in a holder. It has fixed arities, up to five arguments (`untyped.jl:177`); an entry with more positional arguments takes the dynamic call below.
- **Several trait positions,** or more than five positional arguments: one dynamic call to the pattern method on the builders' types.
- **Sessions:** each table carries the session's stamp. Entries of another session, saved with an image, are ignored (`untyped.jl:48`).

Implementations the table does not serve take the entry's own path, `conformance` ([L-11](#18-deviations)).

### 9.3 Entries compiled ahead

**Status: Implemented.** The invalidation of plain code below is accepted, and flagged for future review ([open issues §2](../open-issues.md#2-design), item 29).

While a package that declares `@implement X T` is precompiled, it defines an entry method for `T` itself, for each tabled entry whose position needs `X` (`_ahead_entry!`, `ahead.jl:168`):
- `f(a1::T, a2…) = invoke(f, Tuple{Any, …}, a1, a2…)`, a boundary, in `T`'s module (else the declaring module);
- it is the generic entry's folded path for `T`, compiled into that package's image;
- an untyped caller reaches it by one dispatch; every other type reaches the generic entry and the table;
- the package owns `T`, so the method is a stakeholder's;
- it discards no trait code: code compiled by facts calls `f` at abstract types only at run-time sites, without edges ([traits §5](traits.md#5-implementations));
- it is a new method of `f`, added at the declaring package's precompilation and at each load of its image. So it may invalidate plain code: plain callers compiled at an abstract argument type that `T` subtypes, and the entry's own untyped specialization, `f(::Any, …)` (the entry is `@nospecialize` on its trait position, so that is the code untyped callers run), with every plain caller holding an edge to it. Results stay the same. This is accepted ([traits §15](traits.md#15-compiling-ahead)); `experiments/docs-examples/ahead_invalidation.jl` shows it.

### 9.4 Entries specialized per type

**Status: Implemented** (deviation [L-12](#18-deviations)).

An entry with keywords, a vararg or a `Callable` position is not tabled (`trait_module.jl:543`). Its trait positions are specialized: an untyped caller's dispatch reaches the entry compiled for the argument's type, where the implementation, the views and the worker's selection fold. That entry is compiled per user type, ahead for declared types ([§15](#15-compiling-ahead-workloads-closed-builds)).

---

## 10. Keywords, defaults and varargs

**Status: Implemented**; `Callable` with keywords **Planned** ([`traits.md#8-keywords-defaults-and-varargs`](traits.md#8-keywords-defaults-and-varargs)).

**The entry translates, the worker sorts:**
- The entry takes `f(args…; kws…)` and makes the supplied keywords a named tuple (`trait_module.jl:580`).
- A bounded keyword, if supplied, is translated by `enter_kw`, which refuses a value that conforms to none of its traits (`TraitBoundError`, `entry.jl:331`). A `Callable` keyword by `enter_kw_callable`.
- `checked_kwcall(nt, f, views…)` calls `Core.kwcall(nt, f, views…)`: the worker's own keyword sorter, which Julia lowers from the worker's definition (`checks.jl:283`). It fills the defaults inside the worker, compiled by facts, so a default sees the trait objects.
- In the worker, a bounded keyword is typed `TObj` and a `Callable` keyword `CObj{A, S}`.

**Positional defaults** are expanded as Julia expands them: the full method, and one shorter method per default whose body calls the full one (`_expand_defaults`, `trait_module.jl:360`). Each is a bounded definition with its own worker and entry. The shorter worker calls the full worker with its trait objects.

**A trait vararg** `ts::X...` becomes a worker vararg whose elements each have their own `TObj{T} where T >: …`, so elements may differ in key. The entry translates each element (`enter_each`, `entry.jl:318`). The worker compiles per tuple of keys.

**Fallbacks** with keywords go through `kwfallback`.

**Planned:** `Callable{A, S, M, K}`, the keywords' named-tuple type `K` part of the pointer's signature and of the worker's key.

---

## 11. Results like the input

**Status: Implemented** (deviation [L-16](#18-deviations)); listing the inverses for compiled-ahead builds **Planned**.

`f(t::X, …)::Like{t} = body` ([`traits.md#7-results-declared-types-like-withfields`](traits.md#7-results-declared-types-like-withfields)) is rewritten (`trait_module.jl:429`):
- the worker's body becomes `like(t, body)`, and each `return x` `return like(t, x)` (`_like_returns`);
- `f`'s type is recorded, so the check that no trait object goes up allows the pending result (`_like!`, `entry.jl:648`).

**The pending result** is `LikeResult(t, x, fields)`: the input's trait object, the new receiver or `KeepSelf()`, and replaced declared fields (`entry.jl:658`). `withfields(t; f = v)` makes one with fields only. Nothing operates on it.

**The entry inverts it** (`_like_out`, `entry.jl:682`), for the argument whose trait object it names:
- a type that implements the operations itself: the new receiver, which must be of the same type family;
- otherwise: the user's object rebuilt by its type's constructor with the forwarding field and the replaced fields substituted (`_invert`, `_rebuild`, `entry.jl:710`, `:730`). The constructor recomputes the type's parameters, which gives siblings (`LSeries{Float64}` in, `LSeries{Float32}` out);
- a `Dynamic` in: the rebuilt object as a `Dynamic` of the same trait.

**A constructor operation on a `Dynamic`** returns a `Dynamic` of the new value (`_dyn_like`, `entry.jl:741`).

**Intended:** the inverse is compiled per key and user type where the caller knows the type, and its result has the caller's type. **As built,** it runs behind an inference barrier ([L-16](#18-deviations)).

---

## 12. `Callable` and `DynamicFn`

**Status: Implemented**; open result types **Planned** ([`traits.md#9-callable-functions-at-a-declared-signature`](traits.md#9-callable-functions-at-a-declared-signature)).

**In the worker,** a function argument is a `CObj{A, S, F}` (`core.jl:763`). Calling it checks `args isa A` (`MethodError` otherwise) and asserts the result to `S`. The worker is compiled per `F`:
- `DynamicCall`: `F = Erased{A, S}`, the same type for every function: one worker per signature;
- `CompiledCall`: `F` is the function's type: one worker per function type, the function's call inferred into it.

**At the entry,** `enter_callable(A, S, M, f)` (`entry.jl:569`):
- strips a `CallAs` wrapper (`compiled_call(f)`, `dynamic_call(f)`, `Callable{A, S, M}(f)`), whose mode wins over the bound's; a wrapper fixing another signature raises;
- takes the bound's mode, or `DynamicCall` when the bound leaves it open;
- passes a function of the trait world (Julia's, TraitWorld's, a trait module's, all the way down its fields) as itself (`_from_trait_world`, `entry.jl:531`);
- erases any other function under `DynamicCall`;
- caches the wrapper per (signature, mode, type) for functions that capture nothing.

**`Erased{A, S}`** (`core.jl:708`) holds the function and a pointer to its code compiled for `A`:
- the pointer is a `cfunction` of the calling convention `:caller_world`: the call runs in the caller's world, through a world-checked cache in the pointer's thunk ([compiler §3.1, the `:caller_world` convention](compiler.md#31-the-cfunction-calling-convention-caller_world), `_fptr`, `core.jl:731`);
- the callee is `_CallWrap{S}`, with fixed arities up to six, which calls the function and asserts `S`. Non-bits arguments go boxed;
- the function runs as plain code, as every call through a `cfunction` does ([compiler §2.5, dispatch from facts code](compiler.md#25-dispatch-from-facts-code));
- the pointer sits in a mutable cell. A package image saves it as null, and the first call in a session makes it again (`_PtrCell`, `core.jl:697`).

**Several signatures** `f::(Callable{…}, Callable{…})`: a `CMulti` holding one `CObj` per signature; a call picks the first signature its argument types match, at compile time (`core.jl:790`).

**`DynamicFn{A, S}`** is `CObj{A, S, Erased{A, S}}`, a value of fixed type for a library's fields. `dynamic_fn(A, S, f)` makes one in plain code (`entry.jl:617`).

**In a closed build** every function is known, so nothing is erased: `CObj{A, S}(f)` (`entry.jl:579`).

**Planned: an open result type** `Callable{A, S} where S`: `S` inferred at the entry in plain code, part of the worker's key, asserted at every call.

---

## 13. `Dynamic{X}`

**Status: Implemented** (deviations [L-6](#18-deviations), [L-20](#18-deviations), [L-25](#18-deviations)), on TraitWorld's branch `basetraits`, to be merged; `Dynamic{(X, Y)}` **Planned**; beyond four implementations **Optional** ([compiler §3.3](compiler.md#33-further-work-on-mechanism-3); [`traits.md#10-dynamicx-values-of-any-conforming-type`](traits.md#10-dynamicx-values-of-any-conforming-type)).

**The representation:** `struct Dynamic{X}; t::Any; end` holds the user's object (`core.jl:351`). The view of `X` for the object's type is made where it is needed, by the builder that type's implementation fixed: a constant per pair, folded where the type is known.
- From a value, `Dynamic{X}(x)` checks that `x`'s type conforms (`TraitBoundError` otherwise) and holds `x`.
- From a trait object, `Dynamic{X}(t)` checks that it carries `X` (`ArgumentError` otherwise), narrows it to the views of `X` and its supertraits (`_narrow`), and holds the user's object the views read.
- It holds the trait object itself in two cases, where there is no user's object to hold: the views hold only the parts of an immutable value (a worker that cannot keep received no whole object, [§8.4](#84-keeping)), and the new receiver value of a constructor operation (`_dyn_like`), which need not conform by itself.
- Storing a trait object where a `Dynamic{X}` is declared converts it (`convert`).
- **Opening** (`opened`, `core.jl:438`): the trait object of the held value, made from the user's object as `Dynamic{X}(x)` would see it (whole object kept, so the worker may keep it), or the trait object held. The function that opens is a value of its own type (`_Open{X}()`), so an opening at an unknown type dispatches on the object alone.

**An operation on it** is the method `@trait` defined (`trait.jl`):

```julia
Base.@constprop :aggressive @inline op(d::Dynamic{X}, a…) where {X <: Trait} =
    Compiler.split_call(family(X), RT, _dynop(X, op), getfield(d, :t), a…)::RT
```

- `_dynop(X, op)` is `op` applied to the opened object, as a value of its own type (`_DynOp{X, F}`, one method per arity up to six, `core.jl:448`). The split is over the held object.
- `RT` is the declared result type, with the parameters the `Dynamic`'s type fixes substituted ([traits §10](traits.md#10-dynamicx-values-of-any-conforming-type)). Where it names `Self`, or a parameter the type leaves open, it is `Any`. *As built,* it is `Any` wherever the declared type names `Self` or any parameter ([L-20](#18-deviations)).
- Julia infers the call at the union of the family's registered **candidates**, the first four, plus a fallback, and splits it as a union: `isa` branches on the held object's type, in each the view folded and the operation's method called directly, the dynamic call last, its result asserted to `RT` ([compiler §4.2, the call-site split](compiler.md#42-compilersplit_call-the-call-site-split)).
- `@constprop :aggressive` makes each caller infer the call again, so it splits over the candidates registered when it is compiled.
- The fallback dispatches in the caller's world.
- An operation whose result is `Self` returns a `Dynamic` of the new value instead (`_dyn_like`).

**Candidates** are the types a `Dynamic` holds: the implementations' types (and, in the two cases above, trait-object types), registered with `Compiler.register_dynamic_candidate!` without an edge:
- **at each declaration and each package load,** for each implementation at a concrete type, from the `implementation` and `projection` records (`_note_conformances!`, `core.jl:532`). Each batch is registered in **declaration order:** by the declaration's file, then line. The records carry the `@implement`'s own line (`_at_declaration`, `implement.jl:943`), so a session that loads a package image registers its types in the order the image's code was compiled for. *As built,* a family member is registered only when a `Dynamic` of it is made ([L-25](#18-deviations));
- **when a `Dynamic` is made,** its object's type: once per type and session, through a flag per pair that the constructor's code holds as a constant (`_cand_flag`, `core.jl:390`), not by a search of the registry.

A later implementation reaches the fallback and invalidates nothing.

**Wrapping a value of unknown type** (an item read from a `Vector{Any}`): `@dynamic_of X x` (`core.jl:500`) splits the conformance check over the same candidates (`_ConformsTo{X}`), folded to a constant for each, and makes the `Dynamic` by an `invoke` of its constructor at `(Val{:checked}, Any)`, a fact, so `x` is held in the box it came in. Any other type is checked by a dynamic call. BaseTraits' views do this at each read ([§13.1](#131-a-users-container-crossing-by-its-bound)).

**Opened at a bound:** the entry opens it (`opened`) and passes the trait object, typed `Any`, to `checked_call`. That call dispatches on the trait object's type, so it selects the worker for the key once, and the worker runs compiled ([§8.2](#82-the-entry)).

**Fields:** `getproperty` and `setproperty!` on a `Dynamic` forward to the opened trait object, dispatched at run time (`core.jl:687`).

**Equality, hashing, printing:** `===` on the held user's objects (or the trait objects held); `hash` agrees; `Dynamic{X} at <key>` (`_dyn_identity`, `core.jl:475`).

### 13.1 A user's container crossing by its bound

**Status: Implemented** (deviation [L-27](#18-deviations)), on TraitWorld's branch `basetraits`, to be merged ([traits §10.3](traits.md#103-a-users-container-seen-with-dynamic-items)).

- **What a position asks:** `crossing(EntryPos{F, pos, nargs}())` is fixed with `needed` at the trait module's end (`_fix_crossing!`, `trait_module.jl:773`; `crossing_at`, `entry.jl:310`): a `Crossing{Y, R}` where the workers' bounds at the position fix parameters to dynamic values of one trait `Y` (found inside the fixed values: `Dynamic{Y}`, `Pair{K, Dynamic{Y}}`), with `R`, for each worker, the parameter tags (`PTag`) its bound requires. Elsewhere, the fallback method: `nothing`, folded.
- **At the entry** (`enter`, `entry.jl:193`): if the position has a `Crossing` and `t`'s type is known to cross, `t` is replaced by `crossed(Y, t)` and only its view's trait object is assembled. Otherwise the trait object `v` of `t` is assembled, and the first call for the type decides; a container that crosses is then not assembled as it is again (under `all`, a `Dict{String, Any}` fails the `Iterable` family's check, and its slow path would run at each call).
- **Whether `t` crosses** (`_crosses`, `entry.jl:249`): its trait object meets none of the tag sets in `R`, and the view's does. Decided once per crossing and container type, in a flag the entry's code holds as a constant (a family member's trait object, every Base container's, has a type known only when it is built). The decision is machinery (`_cross_decide`), listed by `verify_main` as a guard.
- **The view** is BaseTraits' `crossed(Y, t)` (`BaseTraits.jl:174`): `DynamicItems{Y}(t)` for an `AbstractVector`, `DynamicValues{Y}(t)` for an `AbstractDict`, when its element (value) type may hold a conforming value (`_may_hold`: `Any`, abstract, a union with such a member, a concrete type that conforms; kept per pair and session once true); `nothing` otherwise, and the value stays as it is, refused as one that conforms at other parameters.
- **Reads and writes:** each read wraps the item (`@dynamic_of`); each write stores the held object, split over the candidates so that `setindex!` on the user's container is a call at a concrete type.
- **Untyped callers:** at a position with a `Crossing`, the table of declared implementations sends every type to the entry's own path (`_umiss`, `untyped.jl:87`), which crosses ([§9.2](#92-untyped-callers-the-table-of-declared-implementations)).

**A trait's name as a type inside a trait module** means its `Dynamic`. The module's statements are rewritten (deviation [L-6](#18-deviations)):
- struct fields: `model::Model` becomes `Dynamic{Model}`, also inside parameters, not inside `<:` (`_dynamic_fields`, `trait_module.jl:143`);
- containers in bodies and argument types: `Column[]`, `Vector{Column}`, `cs::Vector{Column}` (`_dynamic_containers`, `trait_module.jl:179`);
- a trait's name directly on an argument stays a bound.

**Planned:** `Dynamic{(X, Y)}`, a value seen through several traits.

**Optional:** for more than four implementations, a longer split for `split_call` only, or a world-checked table of caller-world pointers at the fallback ([compiler §3.3](compiler.md#33-further-work-on-mechanism-3)).

---

## 14. Checks, and where their results live

**Status: Implemented** (deviations [L-9](#18-deviations), [L-10](#18-deviations), [L-17](#18-deviations)). What each check means and raises is [`traits.md#11-checks-and-when-they-run`](traits.md#11-checks-and-when-they-run); here is where it runs and what is kept.

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

**Definition checking** (`check_definitions`, `defcheck.jl:159`) infers each worker once at **archetypes**: a stand-in key per bound, `Archetype{X, P}` with `P` the parameters the bound fixes, whose views have the witness `ArchWit` (`defcheck.jl:18`, `:64`). At `ArchWit` an operation and a field return an opaque value asserted to the declared type, and nothing more (`defcheck.jl:35`). The rules are checked on the inferred code (`worker_problems`, `checks.jl:77`).
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

**Not kept:** the definition checks' results ([L-9](#18-deviations)), the slow path's caches, the `Callable` wrapper cache, the untyped tables' entries (by their session stamp), `Erased` pointers.

---

## 15. Compiling ahead, workloads, closed builds

### 15.1 Compiling ahead from declarations

**Status: Implemented** (deviation [L-15](#18-deviations)).

While a package that declares `@implement X T` is precompiled (`_compile_ahead`, `ahead.jl:17`), for each trait module loaded at that point and each of its fixed-arity entry positions whose needs include `X` (`_compile_ahead_now`, `ahead.jl:94`):
- **the workers** whose only trait position is that one and whose other arguments are concrete ([traits §15](traits.md#15-compiling-ahead): a function with several trait positions is compiled at its first call), at the trait object of `T`'s builder. Each one's first-call check runs now, a failure fails the build, and the signature is added to `__tw_checked__` (`_check_ahead!`, `ahead.jl:58`);
- **the pattern method** at `T`'s builder type, for untyped callers: once per key;
- **the entry method for `T` itself** ([§9.3](#93-entries-compiled-ahead));
- for an entry the table does not serve, **the specialized entry** at `T`.

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
- **trait:** a step of the machinery, with targets enumerated from the argument types and the declared implementations: the builder per user type, the worker per signature, a function's wrapper, the operations on `Dynamic` values per trait-object type the program keeps;
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
- a new session stamp, which makes saved untyped tables' entries stale;
- the method-definition and image hooks ([compiler §5.1, the definition and image hooks](compiler.md#51-method-definition-and-image-activation-hooks)), and keep-compiled for images built in this process;
- strict mode from `JULIA_TW_STRICT`;
- the type printers for `TObj`, `CObj` and `Builder` ([compiler §5.3, type printers](compiler.md#53-type-printers)): a trait object's type prints by bound and key;
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
| a trait's name as `Dynamic` inside trait modules, by rewriting their source | a trait's name as an abstract type in any field or container | `trait_module.jl:143`, `:179` | [L-6](#18-deviations) |

The meanings are permanent ([`traits.md#16-membership`](traits.md#16-membership)); only these forms go.

---

## 18. Deviations

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-1 | [§3](#3-trait-declarations), [§5](#5-keys-and-views) | a trait is `X{P…}`; the key is a parameter of the view | the trait type has the key as its last parameter, `X{P…, Self}`; trait instances name the key | `TraitWorld/src/trait.jl:198`, `core.jl:316` |
| L-2 | [§5](#5-keys-and-views) | a bound is a type in the worker's signature | trait sets are unions of families and `PTag`s; workers take `TObj{T} where T >: Union{…}` | `core.jl:229`, `trait_module.jl:470` |
| L-3 | [§8.1](#81-the-rewrite), [§17](#17-encodings-until-traits-are-in-the-type-system) | a trait bound is a dispatch tier; entries are generated by the compiler | entries are methods at `Any` per shape; the fallback is tagged `Untyped`; joint methods and ambiguities are checked by hand | `trait_module.jl:456`, `:528`–`715`, `:840`, `:889` |
| L-4 | [§3](#3-trait-declarations), [§17](#17-encodings-until-traits-are-in-the-type-system) | declarations read without edges | registries are methods of `@max_methods 1` functions, some with sentinel fallbacks ([§3](#3-trait-declarations) lists them). No edge is recorded only where at least two methods apply. Where exactly one does (by reading Julia's `max_methods` rule; not run), inference infers it with an edge for the abstract signature, and the first declaration whose method intersects that signature invalidates the code: a tabled entry's `conformance(As{X}(), ::Any)` compiled while `X` has no declared implementation; a specialized entry inlined into a plain caller at an abstract type that no declared implementation's type intersects; a record function without a sentinel, at its one method; `keeps` and `needed` before the module's end (intended: the module redefines them) | `core.jl:303`–`641`, `entry.jl:114`, `:174`, `:205`, `implement.jl:28`, `:57`, `:625`, `untyped.jl:102` |
| L-5 | [§17](#17-encodings-until-traits-are-in-the-type-system) | membership is `T <: X` | `conforms(T, X)` | `entry.jl:757` |
| L-6 | [§13](#13-dynamicx) | a trait's name as a type means its `Dynamic` | only inside trait modules, by rewriting struct fields, containers and argument types | `trait_module.jl:143`, `:179` |
| L-7 | [§4.1](#41-what-every-form-defines), [§4.4](#44-forwarding-with-by) | forwarding is written with `by` and recorded as forwarding | `by f` is lowered to a projection `project(t) = getfield(t, :f)`; a written `project(t) = t.f` is accepted as forwarding; TraitWorld's own precompile workload and tests use `project(t) = …` and the `{R}` spelling | `implement.jl:911`, `:1298`–`1305`; `TraitWorld.jl:88`, `:103`–`106`; `test/runtests.jl:50` |
| L-8 | [§13](#13-dynamicx) | *Retired (2026-10-20).* No longer a deviation: a `Dynamic{X}` holds the user's object, and a trait object only where there is no user's object to hold (parts of an immutable value; a constructor operation's new receiver), the user's decision of 2026-10-20 ("What Dynamic{X} holds is correct"). On TraitWorld's branch `basetraits` (8863ea0) | — | — |
| L-9 | [§14](#14-checks-and-where-their-results-live) | a worker checked at its definition is not checked again at its first call | the record of definition-checked methods is a session's set, filled only where the trait module's end runs; in a session that loads the package from its image, a worker signature whose checked code no image holds runs the rule check at its real signature at its first call | `defcheck.jl:119`, `:173`; `checks.jl:342` |
| L-10 | [§14](#14-checks-and-where-their-results-live) | only open parameters and open `Callable` result types wait for the first call | keyword workers, vararg workers and every worker with a `Callable` argument wait too | `defcheck.jl:84`, `:89`, `:93` |
| L-11 | [§9.2](#92-untyped-callers-the-table-of-declared-implementations) | an untyped caller reaches the table for every implementation once fixed | family members and generic implementations are marked untabled and take the entry's own path, cached per world | `untyped.jl:76`–`86`; `entry.jl:144`; `implement.jl:707` |
| L-12 | [§9.4](#94-entries-specialized-per-type) | an untyped call compiles nothing per user type | entries with keywords, a vararg or a `Callable` position are specialized per argument type | `trait_module.jl:543`–`559` |
| L-13 | [§9.2](#92-untyped-callers-the-table-of-declared-implementations) | a table entry is valid until invalidation ends the worlds it rests on | an entry's range ends at the latest world when it is made, so every entry misses once after any definition (an open `max_world`: [compiler §3.3](compiler.md#33-further-work-on-mechanism-3), Planned) | `untyped.jl:70`, `:225` |
| L-14 | [§15.3](#153-verify_main-fully_typed-closed-builds) | a closed build fills every cache from the listed targets, and a miss is an error | `close_world!` fills only the slow path's cache; the untyped tables' miss paths have no closed-world branch and are not among `verify_main`'s guards | `verify.jl:464`, `:1011`; `untyped.jl:64`, `:220` |
| L-15 | [§15.1](#151-compiling-ahead-from-declarations) | the workers of every bounded function with one trait position whose bound includes `X` are compiled ahead, where the other arguments are concrete | vararg positions are skipped; so are entries with several trait positions: no worker, no pattern method and no entry method is compiled ahead for them | `ahead.jl:100`, `:132`, `:138`, `:151`–`152` |
| L-16 | [§11](#11-results-like-the-input) | the inverse is compiled for the caller's type, and its result has that type | the inverse runs behind an inference barrier through a `Dict` and the constructor; a typed caller's result is `Any` | `trait_module.jl:633`, `:702`; `entry.jl:681`–`739` |
| L-17 | [§2](#2-modes-owners-and-images), [§14](#14-checks-and-where-their-results-live) | the machinery's code is facts code, protected as trait code | machinery that calls compiler functions directly holds edges to plain compiler code, valid only as long as plain Julia keeps it valid | `checks.jl:97`–`117`; `defcheck.jl:236`–`258`; `core.jl:348`, `:415`; `compiler.jl:57`, `:68` |
| L-18 | [§16](#16-sessions-loads-and-hooks) | strict mode asks Julia what a definition would invalidate ([compiler §5.4](compiler.md#54-planned-hooks-for-strict-modes-intended-design)) | it reads backedges before the definition and the invalidation log after it, deleting the method again on a miss | `strict.jl:1`–`14`, `:123`, `:197` |
| L-19 | [§3](#3-trait-declarations) | a trait's body holds operations, defaults, fields, equations and concreteness lines ([`traits.md#1-syntax-summary`](traits.md#1-syntax-summary)) | `@mutating` is accepted in a trait's body and recorded as `is_mutating`, which no code reads | `trait.jl:284`; `implement.jl:132` |
| L-20 | [§13](#13-dynamicx) | an operation on a `Dynamic` of a parametric trait asserts its declared result at the parameters the `Dynamic`'s type fixes, so a `Dynamic{StateVector{Float64}}` operation declared `::T` is typed `Float64` | the result type is `Any` wherever the declared type names `Self` or any parameter, fixed or not; the code after the call is not inferred | `trait.jl:303`–`304` (`dep`, `retx`), `:314`, `:318` |
| L-21 | [§5](#5-keys-and-views) | an implementation whose operations are all served by defaults has no receiver type | it has one also when the trait's declarations name `Self`, or when a parameter is not defined by a field: then the conforming type is the receiver type and gets its own compiled copy | `entry.jl:456`–`465` (`_no_implementing_type`) |
| L-22 | [§9.3](#93-entries-compiled-ahead) | *Retired.* No longer a deviation: the invalidation of plain code by the entry compiled ahead is the intended shape, accepted and flagged for review ([§9.3](#93-entries-compiled-ahead); [traits §15](traits.md#15-compiling-ahead); [open issues §2](../open-issues.md#2-design), item 29). | — | — |
| L-23 | [§4.6](#46-families) | A later declaration for one member of a family is a more specific `conformance` method, until the member's first use. | The member's declaration makes its own `conformance` method (`_declared_for`); a declaration after the member's first use is not refused. As [traits T-28](traits.md#19-deviations). | `implement.jl` (`_declared_for`) |
| L-24 | [§9.2](#92-untyped-callers-the-table-of-declared-implementations) | An entry with more than five positional arguments takes the dynamic call to the pattern method. | The entry takes the pointer path for every tabled entry with one trait position, at any arity, and `_UWrap` has methods for 0 to 5 arguments only. By reading, an untyped call of an entry with six or more positional arguments then fails, when the pointer is made or called; not run. | `untyped.jl:177`–`181`; `trait_module.jl:659`–`666` |
| L-25 | [§13](#13-dynamicx) | Candidates are registered for each declared implementation at a concrete type, after each declaration and each package load. | Types with an `implementation` or a `projection` record at a concrete type are registered then (types that forward, or conform by a field mapping, since branch `basetraits` 8863ea0). A family member's record has a `UnionAll` signature: it is registered only when a `Dynamic` of such a value is made, and code compiled before that takes the fallback for it. | `core.jl:532` (`_note_conformances!`; branch `basetraits`) |
| L-26 | [§4.5](#45-field-mappings-several-traits-stated-parameters) | A stated value for a parameter an equation defines is checked against the equation and makes no method. | For one type: checked, and no method is made when it agrees (`_param_agrees`). For a family: it becomes a `param` method with the family's `where`, replacing the equation's value, unchecked. As [traits T-37](traits.md#19-deviations). | `implement.jl` (`_param_methods`) |

| L-27 | [§13.1](#131-a-users-container-crossing-by-its-bound) | A closed build lists and fills everything an entry can reach. | The crossing's decision (`_cross_decide`) is reflection run at the first call per container type; `verify_main` lists it as a guard, and `close_world!` does not fill its flags, so in a closed build the first call of a crossing position would need it. Not tried with `--trim`. | `entry.jl:249`; `verify.jl:491` (branch `basetraits`) |
