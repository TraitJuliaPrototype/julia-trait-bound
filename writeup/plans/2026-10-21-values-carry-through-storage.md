# Values carry their attribute through storage

**Status:** done (2026-10-21), revision 2, after [the review](../reviews/2026-10-21-values-carry-through-storage.md) and the user's answers on the kept form and on casts; amended by the user's answer on `Dynamic{X}` in storage (see the addendum at the end). The details not in the user's words are mine, flagged for review (open issues §1). Work item W-18.

**Revision 2 changes** (each from the review or the user):
- the kept form is one concrete type, not a union (§2, the user);
- `compiled_for` and `with_dynamic` are the only casts, the later one wins, and types never cast (§3, the user and F1);
- `Callable` has its own section (§6, F2);
- §4.3's rules are written (F3);
- writes (§5.2, F5), equality (§2, F8) and the places that assumed `Dynamic` (§7, F7) are covered.

## 0. The user's words

- On storage: "I thought of Values carry as just that: It persists through storage. Callable{... CompiledCall} worked like that, and it really has to. The type ODEProblem has to store the function and if compiled_for(f) is lost on storage this forces us back into the library provided switch (that already exists in SciML). We have just turned today's @nospecialize around rather than having a principled design."
- On the outline: "I honestly thought that this design was what we had agreed on yesterday, what was the reason to deviate? To keep close to Rust/C++? I think Julia's existing differences justify/enable a different design here. The outline minus the stored() looks good to me. Go for it."
- "Remember that the Demonstrators follow the design. […] the Demonstrators already built never constrain the design."
- On the kept form for heterogeneous storage: "One concrete type (Recommended)".
- On a library casting a value the caller cast the other way: "The library wins, but I was thinking: make compiled_for(x)/with_dynamic(x) the only way to do the cast?"
- On revision 2's rule (casts only by `compiled_for`/`with_dynamic`, constructors and types never cast): "Yes, that is a clean rule: Values carry. Annotations provide defaults when a plain value enters trait code. Explicit casts always win."

## 1. The rule

- **A value's attribute belongs to the value.** It is set once, where a plain value is first seen through a trait (traits §6.6, unchanged). Then the value keeps it: through calls, bounds, and storage.
- **Storage never decides.** A value read back from a field or a container has the attribute it had when it was stored.
- **Only a cast changes it:** `compiled_for(x)` or `with_dynamic(x)`.
  - These are the only casts, in plain code and in trait code. The later cast wins, so a library's cast overrides the caller's.
  - Constructors and types never cast (§3).
- **Why Julia can do this when Rust and Swift do not.** They compile ahead of time, so a value stored at an abstract type runs through a vtable or a witness table and shared code. Julia compiles per key when the code first runs, and a function barrier is idiomatic Julia. So a value stored at an abstract type can still select the code compiled for its key, once per call, at the next bound.

## 2. The forms of a trait-world value

| Where the value is | `Compiled` | `Dynamic` |
|---|---|---|
| in trait code, its type known to the code | the trait object at its key | the trait object at the erased key |
| one attribute, its type not known to the code | `Compiled{X}` | `Dynamic{X}` |
| in heterogeneous storage | `Kept{X}`, holding the attribute | `Kept{X}`, holding the attribute |
| in a field whose type is a parameter bounded by `X` (§4.3) | the user's object itself | `Dynamic{X}` |
| in plain code, before it meets a trait | `compiled_for(x)` | `with_dynamic(x)` |

- **`Compiled{X}` and `Dynamic{X}`** are concrete types. Each holds the user's object and has one attribute.
- **`Kept{X}` is a value of `X` with its attribute as data:** `struct Kept{X}; t::Any; compiled::Bool; end`.
  - It is one concrete type: stored inline, no allocation per value. Julia's established form for an unboxed sum type (SumTypes.jl, Moshi.jl).
  - It is what a trait's name means as a storage type inside a trait module (§4.1).
  - `Kept{X}` is a working name, and public: plain code meets it in field types.
- **An operation or a field read** on any of the three is the same call-site split over the candidates, with the table behind it (lowering §13).
- **At a bound they differ:**
  - A `Compiled` value is opened by its type, and the code compiled for its key runs. The table of declared implementations selects it where the entry has one (lowering §9.3); elsewhere it costs two dynamic calls (lowering §9.2, open issues §3 item 9).
  - A `Dynamic` value runs the code compiled once for the position.
- **Equality and hashing** go by the held object across all three types, with one hash salt. The attribute is a choice of speed, never of results. `===` differs by type.
- **Printing:** `Compiled{Shape} at Hex`, `Dynamic{Shape} at Hex`, `Kept{Shape}: Compiled at Hex`.

## 3. Casts, constructors, types

- **The casts:**
  - `compiled_for(x)` gives a `Compiled` value: on a plain value the wrapper (until first seen), on a `Dynamic{X}` a `Compiled{X}`, on a `Kept{X}` a `Kept{X}` with `Compiled`, on a `Dynamic` trait object the opened trait object.
  - `with_dynamic(x)` likewise gives a `Dynamic` one.
  - A value that already has the attribute is returned as it is.
- **Constructors make or keep, never cast:**
  - `Dynamic{X}(x)`, `Compiled{X}(x)` and `Kept{X}(x)` on a plain value make a value. `Kept{X}(x)` gives it the attribute of the first-seen rule.
  - On a value that has an attribute (a trait object, a kept value, a `compiled_for(x)`): they keep it where it matches, and `Kept{X}` always matches. Otherwise they raise a `TraitBoundError` naming the cast.
  - So `Dynamic{Callable{A, S}}(compiled_for(f))` is an error, where today it drops the caller's cast silently (`entry.jl:814`).
- **Types never cast:**
  - Inside a trait module, an attribute on a field or an item type (`f::Dynamic{X}`, `Vector{Compiled{X}}`) is what it is on a bound: the default for values first seen there. The slot is a `Kept{X}`.
  - Outside trait modules, `Dynamic{X}` and `Compiled{X}` are plain types. Storing a value of the other attribute there is an error naming the cast. No `convert` exists between the two.

## 4. Storage

### 4.1 A trait's name as a storage type

- **Inside a trait module,** a trait's name in a struct field or as a container's element type (`model::Model`, `Vector{Hook}`, `Hook[]`) means `Kept{X}`. So do `Dynamic{X}` and `Compiled{X}` there (§3).
- **In an argument's type,** a trait's name as a parameter (`cs::Vector{Column}`) means `Vector{<:K}` for the kept types `K`, since Julia's parameters are invariant.
- **Storing a trait object there:** its key gives the attribute, at its own key `Compiled` and at the erased key `Dynamic`. A trait object `compiled_for` opened is at its key.
- **Storing a `Compiled{X}` or `Dynamic{X}`:** its attribute is kept.

### 4.2 Assignment from plain code

- A plain value assigned from plain code into a `Kept{X}` slot is first seen there.
- The first-seen rule needs to know whether the caller knew the value's type. A `convert` method always knows it, so the rule cannot be evaluated there.
- **Stays Planned, as today:** plain code writes `Compiled{X}(x)`, `Dynamic{X}(x)` or a cast.
- The rule for it is Open (open issues §1, new item).

### 4.3 A struct parameter bounded by a trait

```julia
struct ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}, D <: Callable{DualSig{P, 8}, Nothing}}
    f::F
    u0::Vector{T}
    tspan::Tuple{Float64, Float64}
    p::P
    fd::D
end
```

- **(a) The parameter.**
  - Inside a trait module, a struct parameter whose upper bound is a trait, a `Callable`, or an instance of either is bounded by it.
  - The macro strips the bound, since a trait is not a Julia type.
  - Julia's inner constructor with explicit parameters stays, unchecked, as an explicitly parameterized constructor is in Julia (SciML's `ODEFunction{iip, FullSpecialize}(f)`).
  - A user-written inner constructor is refused for now.
- **(b) The constructor.**
  - The constructor without parameters is an entry: each field typed exactly `F` takes `F`'s bound, and the caller's cast or the first-seen rule applies there.
  - The bound may name the struct's other parameters (`RHSSig{P, T}`), computed from the other fields' types. Constructors are exempt from T-17: they store and never call, so `A` need not be constant for a key.
  - A parameter named only inside a bound is refused.
- **(c) The parameter's value is the stored form's type:**
  - for a `Compiled` value, the user's object's type (a function's type for `Callable`), so code over the struct is compiled per function;
  - for a `Dynamic` value, `Dynamic{X}`, so it is compiled once;
  - a `Compiled{X}` or a `Kept{X}` with `Compiled` is opened by its type at the constructor.
- **(d) Reading the field.** The struct's own methods (an implementation's) see a plain value of type `F`. They are plain code over the concrete type, so rule 3 does not arise. Bounded trait code reaches only the fields a trait declares.
- **(e) Several bounded parameters** each take their own bound. A field that uses `F` in another type (`fs::Vector{F}`) is refused for now.
- **(f) Precedent:**
  - Rust's `struct S<F: Fn(…)>`, Swift's `struct S<F: P>`, Julia's performance tip (make the field's type a parameter);
  - SciML's `ODEFunction{iip, specialize, F}`, where the caller picks a library-defined level. Here the switch is the language's (`compiled_for`) and the same in every library.
- **This replaces `stored(Callable{A, S}, f)`.** `stored` is deleted.

### 4.4 Other storage

A trait object stored in a `Vector{Any}`, a tuple, a `Ref`, or a field whose type is neither a trait's name nor a bounded parameter is refused, as today (rule 3). Library code stores `Kept{X}(t)`. A kept value may be stored anywhere.

## 5. Items of a user's container

### 5.1 Reads

- **Items of an abstract type** (`Any`, an abstract type, a union) keep each item's carried attribute.
  - The carried forms are `Kept{Y}`, `Compiled{Y}`, `Dynamic{Y}`, `compiled_for(x)` and `with_dynamic(x)`.
  - The position's attribute decides only for plain items, which are first seen there.
  - **Each read gives a `Kept{Y}`**, with no allocation. Today's `CompiledItems` at an abstract item type gives trait objects typed `Any` instead, and `DynamicItems` gives `Dynamic{Y}`.
- **Concrete item types are unchanged.** A `Vector{Dot}` gives trait objects at their key. A `Vector{Dynamic{Y}}`, `Vector{Compiled{Y}}` or `Vector{Kept{Y}}` meets the bound as it is.
- **The bug of 2026-10-21 goes:** a `Dynamic{Shape}` or a `compiled_for` value in a `Vector{Any}` was refused at `Iterable{Dynamic{Shape}}` and `Iterable{Compiled{Shape}}`.

### 5.2 Writes

- A write stores what reads back as the same value with the same attribute, in plain code's own forms:
  - the user's object, where a plain item of that container reads with that attribute;
  - else `compiled_for(o)` or `with_dynamic(o)`.
- A container that can hold neither (a `Vector{AbstractShape}` written a `Compiled` value through a view whose plain items are `Dynamic`) raises an error naming the cast: types never cast.
- `retain!` over a `Vector{Any}` keeps the user's objects as they were, and a `compiled_for` item stays one.
- This is mine. The review recommended "always the user's object", which drops the user's cast; §1 rules that out.

## 6. `Callable`

`Callable` has its own lowering (lowering §12): `CObj{A, S, F}`, `Erased{A, S}`, `CMulti`.
- **`Compiled{Callable{A, S}}` holds the function.** A call is `CObj{A, S}(f)(args…)` behind a dispatch on the function's type, one dynamic call. `Kept{Callable{A, S}}` branches on its attribute at each call.
- **`enter_callable` takes `Compiled{Callable}` and `Kept{Callable}` with their attribute.** A function of the trait world counts as the trait world's (`_tw_type`).
- **`compiled_for(d::Dynamic{Callable{A, S}})` takes the function out of its `Erased`.**
- **A `Dynamic` function at a bound of another signature** is the same function, still `Dynamic`, at that signature: a new erased pointer, made at its first call. A user's `Dynamic{Callable{RHSSig, Nothing}}` given to `ODEProblem` therefore serves the duals too, where W-2 fell back to finite differences.

## 7. The places that assumed "unknown means `Dynamic`" (F7)

- `enter_kw`, `enter_kw_callable` and `enter_each` take a kept value with its attribute.
- **The seams.** An operation's argument declared with a trait's name (`integ::IntegratorView`) is a `Kept{Y}`, and a trait object passed there keeps its attribute. One declared `Dynamic{Y}` takes `Dynamic` values only; a `Compiled` one is an error naming `with_dynamic` (types never cast).
- `_like_out` takes a kept input, and `verify_main` lists kept constants.
- `is_dynamic` covers the kept types.
- `ErasedKey`'s item parameter and `_compiled_view_item` are retired once the views give kept items.

## 8. What does not change

- Where a plain value gets its attribute, the order of overrides, and `@dynamic` (traits §6.6). They decide only for values first seen.
- The split, the table behind it, and the table of declared implementations.
- An operation's result declared with a trait is first seen there, so it is `Dynamic`, as today.

## 9. The demonstrators (they follow the design)

- **TraitDifferentialEquations:**
  - `ODEProblem{T, P, F, D}` as in §4.3. The plain front end calls `ODECore.ODEProblem(f, u0, tspan, p, f)`, so each bound applies the caller's cast or `Callable`'s default.
  - `stored` goes.
  - Callbacks: `Vector{Callback}`, a plain store in `keep_callback`, and `integ::IntegratorView` in the operations.
- **TraitMakie, TraitTables, TraitCSV, TraitReport:**
  - A trait's name in storage keeps each value's attribute, so a bound on a `Compiled` value compiles per key where it compiled once before.
  - `Dynamic{X}(t)` used as a cast becomes `with_dynamic(t)`.
  - Their tests run. A row is re-run only where a test or a quick check shows a change.

## 10. An experiment

E-149 (registry row before the run), a few minutes, product setting:
- `push!` and a read plus one operation on `Vector{Kept{X}}` against `Vector{Dynamic{X}}`;
- the views' reads over a `Vector{Any}`;
- E-145's rows, on the build.

Changes the design if `Kept{X}` allocates or a view read costs more than today's.

## 11. Order of work

1. TraitWorld:
   - `Kept{X}`, the three types' operations, fields, equality and printing;
   - the casts and the constructors' checks;
   - the entry for kept values, keywords and varargs;
   - storage (§4.1, §4.4) and the seams;
   - the views' reads and writes;
   - `Callable`'s forms;
   - struct parameters bounded by a trait;
   - `stored` deleted;
   - tests, the bug's test first.
2. E-149.
3. TraitDifferentialEquations, then the other demonstrators' suites, the acceptance checks in both settings, and the examples.
4. The documents:
   - traits §6.6, §9, §10–§10.3, the status index and deviations;
   - lowering §9.3, §12, §13, §13.1, a section on bounded struct parameters, §17, L-6;
   - the glossary, `alternatives.md`, the decision row;
   - open issues 39 and the new item;
   - `todo.md`, `state.md`, `intro/`;
   - all in one commit with the decision row.

## Addendum (2026-10-21, after building)

- **`Dynamic{X}` and `Compiled{X}` in a trait module's storage are the plain types,** not `Kept{X}` with a default (§3 and §4.1 above). The user, on finding F2 of [the review of the traits reference](../reviews/2026-10-21-traits-reference-structure.md): "The plain type (Recommended)". A trait's name is the one kept form; a plain value assigned to it takes the trait's default (open issue 40, closed).
- **Built differently from §7:** an operation's argument declared with a trait's name is not rewritten; libraries write `Kept{Y}` (TraitMakie's `setcolor!`) or keep `Dynamic{Y}` where they make the value themselves (TraitDifferentialEquations' integrator view). The seams apply to operations on held values too (`_seam1`).
- **Built beyond the plan:** the untyped table's pointer wrapper takes up to eight arguments (TraitMakie's `drawmarkers` has six); type assertions in a trait module's bodies keep the attributed types written in them.
