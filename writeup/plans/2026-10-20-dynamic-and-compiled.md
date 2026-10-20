# `Dynamic{X}` and `Compiled{X}`: one language for trait positions (proposal, 2026-10-20)

**Status:** the rule of section 0 adopted by the user (2026-10-20), refined the same day (first seen through a trait: concretely typed `Compiled`, abstractly typed `Dynamic`; annotations on item parameters; no warning on disagreement; no synonyms); sections 1–5 are the proposal's earlier form, kept for its reasoning, and superseded by section 0 where they differ. In particular, a `Dynamic` passed to a `Compiled` position is not opened (rule 7), unlike section 1's table and section 2's row "opened at `Compiled` positions only". Work item W-4 (`../record/todo.md`), open issue 33. Nothing here is built.

The user (2026-10-20): "I think all of this points to a unifying language. f(x::Dynamic{X}) for an erased position, and the new f2(x::Compiled{X}) for a static one. Then f(compiled_for(x)) and f2(with_dynamic(x)) override. Importantly these rules can be given without talking about receiver types at all. Receiver types are an optimization in Compiled{X} to reduce the amount of things f2 actually recompiles for using the trait information." And: "I think a bare x::X should be compiled by default, as that mirrors what Julia does now. But this is a decision that should be revisited later."

## 0. The rule (the user, 2026-10-20; this section supersedes sections 1 and 1b where they differ)

The user: "We can simplify this more: In trait code all values are either Dynamic, or Compiled. They get this attribute when plain values that conform to a trait cross over into trait world. Default is Compiled{X}. A traits default can override this (Callable does). A boundary default can override this (it wins against the trait default but warns). A caller (inside or outside trait code) can explicitly declare compiled_for or with_dynamic and that always wins and never warns. Untyped values that come out of values in the trait world are Dynamic and have to be cast to compiled_for explicitly."

**Refined** (the user, 2026-10-20, on the review of W-4's material): "I would refine the definition we have agreed on: Whenever a value is first seen through a trait X it becomes Compiled{X} if it is concretely typed and Dynamic{X} when it is abstractly typed." And: "The clear example is: function{ms::Iterable{Mark}} for m in ms draw(m); end; end; draw(m::Mark) = ... here m enters the trait world inside a function as an untyped value when the function is compiled. The library can say: for m in ms draw(compiled_for(m)) end to get m as a Compiled{Mark} or, and this is a new idea, it could declare function{ms::Iterable{Compiled{Mark}}} to override the default at the boundary." Asked whether an annotation re-decides items that are already trait-world values (no), and whether a call at the REPL on an ordinary global is `Dynamic` (yes): "Yes on both. Repl might bear revisiting later as a special case..." Rules 1, 2, 4, 6 and 7 below are the refined form; rule 2 replaces the default `Compiled`, and rule 4 no longer warns ("Let's remove the warning entirely").

1. **Every value in trait code is either `Dynamic` or `Compiled`.** It gets this attribute where it is **first seen through a trait** `X`: at an argument's bound, at an item parameter of a bound (the items of `ms::Iterable{Mark}`, each when it is read), at a field or an operation's result declared with a trait.
2. **Concretely typed: `Compiled{X}`. Abstractly typed: `Dynamic{X}`.** The type is the one the code that sees the value knows when it is compiled, not the value's type at run time (every value is concrete at run time).
   - A caller whose code knows the concrete type: `Compiled{X}`. A call dispatched at run time (an argument typed `Any` in the caller): `Dynamic{X}`.
   - Items of a `Vector{Circle}` are `Compiled{Mark}`; items of a `Vector{Any}` or `Vector{AbstractMark}`, values of a `Dict{K, Any}`: `Dynamic{Mark}`.
   - A field or an operation's result declared with a trait is `Dynamic` (its declared type is the trait).
   - **At the REPL,** a call on an ordinary global is `Dynamic`: the global's type is abstract to the code. `compiled_for(x)`, or code inside a function, gives `Compiled`. To revisit later as a special case.
3. **A trait's default overrides it.** `Callable` declares `Dynamic`, so a function crossing into a `Callable` bound is `Dynamic` (spelling: `@dynamic` in the trait's body, the word used everywhere else: `Dynamic{X}`, `with_dynamic`).
4. **A boundary's annotation overrides the trait's default,** without a warning:
   - on an argument, `f(x::Compiled{X})` or `f(x::Dynamic{X})`;
   - on an item parameter, `ms::Iterable{Compiled{Mark}}` or `ms::Iterable{Dynamic{Mark}}` (also `Keyed{String, Compiled{Shape}}`, and every other item parameter).
   - `Compiled` on an abstractly typed value opens it once, by its type at run time: a function barrier. `Dynamic` on a concretely typed value erases it.
5. **A caller's explicit `compiled_for(x)` or `with_dynamic(x)` always wins,** outside trait code (at the call into a library) and inside it (`for m in ms; draw(compiled_for(m)); end`).
6. **What a bound's item parameter means:** a trait's name there (`Iterable{Mark}`) means items seen through `Mark`, each with the attribute of rule 2. It no longer means the trait's `Dynamic` (traits §10, §10.2). With no trait (`Iterable{Any}`), an item stays a plain value.

   | Bound | items of a `Vector{Circle}` | items of a `Vector{Any}`, `Vector{AbstractMark}` |
   |---|---|---|
   | `ms::Iterable{Mark}` | `Compiled{Mark}` | `Dynamic{Mark}` |
   | `ms::Iterable{Compiled{Mark}}` | `Compiled{Mark}` | `Compiled{Mark}`: each item opened when read |
   | `ms::Iterable{Dynamic{Mark}}` | `Dynamic{Mark}` | `Dynamic{Mark}` |

7. **Inside the trait world a value keeps its attribute,** through every call, bound and annotation, unless an explicit conversion changes it. An annotation decides only for values first seen there: the items of a stored `Vector{Dynamic{Plot}}` stay `Dynamic` at `Iterable{Compiled{Plot}}`, and become compiled only by `compiled_for`. A `Dynamic{X}` that plain code holds and passes back is a trait-world value and keeps its attribute.
8. **An annotation on a function that is neither exported nor public warns at its definition:** no plain value crosses there.
9. **Library to library, values carry:** a value passed from library A to library B's bounded function is already a trait-world value; B's defaults and annotations do not re-decide it.

**No synonyms** (the user, 2026-10-20: "Synonyms: no."): `Callable{A, S, M}`'s mode parameter, `CompiledCall`, `DynamicCall`, `compiled_call` and `dynamic_call` are removed; `DynamicFn{A, S}` is written `Dynamic{Callable{A, S}}`. `Callable`'s tests and the demonstrators are rewritten in the new spelling.

**Guidance for libraries:** with abstractly typed items, a loop is compiled once, so a `Compiled` item's type is unknown inside it. `Compiled` items pay off when the work per item is a call (`draw(m)` dispatches once per item into code compiled for the item's type). Operations called directly on the item in the loop are faster on `Dynamic` items: a typed call through the split, not a call on a value of unknown type.

**What changes in the current design:**
- Traits §3.7: an abstract part of a key is no longer opened at the next bounded function (the automatic function barrier). A value of abstract type passed to a bound is `Dynamic` (rule 2).
- Traits §10, §10.2: a trait's name in a bound's parameter no longer means its `Dynamic` (rule 6). A `Vector{Circle}` meets `Iterable{Mark}` as it is, its loop compiled for `Circle` (needs a bound whose item parameter accepts any conforming type, close to T-16); today it crosses through the `DynamicItems` view (§10.3), which stays for abstract item types.
- `Dynamic` values are no longer opened at every bound (traits §10). TraitTables (`summarize(t.cols[k], …)`) and TraitMakie (its drawing loops) rely on that today and need `compiled_for` at those calls.
- Lowering §9.2: the untyped callers' path (`known_type(x)` false) becomes the `Dynamic` path.

**Decided since** (the user, 2026-10-20: "library to library: Values carry. Not redecided. Rule 8 is a warning. Is there a reason to say erased, instead of dynamic which we use everywhere else?"): rule 9; rule 8 a warning; a trait's default spelled `@dynamic` (no reason for a second word).

## 1. The language: what a programmer reads

**Two kinds of trait position.**

```julia
area_sum(xs::Iterable{Shape}) = …          # bare: Compiled{Iterable{Shape}}
solve(prob::Compiled{ODEProblemTrait}, alg) = …
plot!(ax, mark::Dynamic{Mark}) = …
```

- **`Compiled{X}`**: the function behaves as if compiled for the argument's own type. Calls of `X`'s operations are calls at that type.
- **`Dynamic{X}`**: the function is compiled once for the position. A call of one of `X`'s operations dispatches when it runs, and its result has the operation's declared result type, checked. Code after the call stays typed.
- **A bare bound `x::X` is `Compiled{X}`** (decided for now, to be revisited).
- **The mode is a choice of speed, never of results.** Both compute what the operations' methods compute, or raise (identical or error).

**The caller overrides per value.**
- `f(compiled_for(x))` at a `Dynamic` position: runs `f` as if compiled for `x`'s type.
- `f2(with_dynamic(x))` at a `Compiled` position: runs the code compiled once for the position.
- The library's declaration is the default; the caller decides per call, as for `Callable` today.

**`Dynamic{X}` is also a value.** It holds the user's object, of a type unknown to the code that holds it (traits §10).

| Passed | to `Dynamic{X}` | to `Compiled{X}` |
|---|---|---|
| a value of a conforming type | erased at the entry (the object is held, not copied) | as it is |
| a `Dynamic{X}` value | as it is | opened: the code compiled for its object's type runs |
| a container with untyped items, bounded by item | crosses by the bound (traits §10.3) | crosses by the bound |

**No receiver types in these rules.** What a function is compiled for is the lowering's business (section 3).

## 1b. The rule refined: who decides, and how the decision propagates (2026-10-20, with the user)

Worked out in conversation with the user, after the proposal's first version (section 1). It replaces section 1's "a bare bound is `Compiled{X}`" and the opening of a `Dynamic` value at every bound.

**The Rust and Swift precedent.** Neither language has a mode per bound. The value's own type decides: a concrete value runs generic code compiled for its type; a `dyn` (Rust) or an `any` (Swift) value runs it erased, once. Neither turns an erased value back into per-type code.

**Three levels, each overriding the one below,** applied once, where a value enters trait code from plain code:
1. **The value's form,** under a bare bound: a concrete value gets compiled code (as Julia does today, the user's decision that a bare bound is compiled); a `Dynamic` value gets erased code (as in Rust and Swift). A bare bound means "the library has no preference".
2. **The entry's annotation:** `Compiled{X}` or `Dynamic{X}` at the position sets the default for values entering there from plain code (TDE's solver: `Dynamic{ODEProblemTrait}`, so that a new problem type compiles nothing; a hot kernel: `Compiled{X}`).
3. **The caller's wrapper:** `compiled_for(x)` or `with_dynamic(x)` at the call.

**Inside the trait world, the value carries its mode** (the boundary rule: each value translated once by its bound; `Callable` works this way today, `enter_callable` passes a trait-world value through unchanged):
- a `Dynamic` stays `Dynamic`, a compiled value stays compiled, through every inner call, bound and annotation;
- an annotation on a function reached only from inside the library does nothing for the values arriving there; it is the default for values entering there from plain code, if any do;
- **library code changes a mode only by an explicit conversion in its own code,** `draw(compiled_for(m))` before a hot loop; the caller cannot override that from outside. Both decisions are where they can be seen: the user's at the call into the library, the library's in its code.
- A mode never changes results, so none of these choices can break a program.

**Callable** keeps its dynamic default (the user's exception): its declaration's default is `Dynamic`, at level 2.

**Consequences:**
- A loop over `Dynamic` items calling a bare bounded function runs it erased; operations (behaviour per type) dispatch to the type's own method either way. Per-type copies of generic code come only from `Compiled{X}` or `compiled_for`. Section 4's question 3 is moot.
- Containers: a `Vector{Circle}` is concrete, its items keep their type, code is compiled for `Circle`; a `Vector{Any}` crosses with `Dynamic` items, erased. (This answers the BaseTraits agent's choice 1, open issues §1 item 26, with "no": concrete conforming element types keep their type. It needs `where` variables in bounds, T-16.)
- Closed builds: a `Dynamic` value at a bare bound needs one copy, not one per declared implementation.

**Annotations only where values enter from plain code** (the user, 2026-10-20: "We should then warn or error on a Compiled or Dynamic annotation in a trait bound for a non-exported function. It would be easy to assume it achieves something that it doesn't."): a `Compiled{X}` or `Dynamic{X}` annotation on a function that is neither exported nor declared `public` is reported at its definition (an error, or a warning: to settle), naming the explicit conversion as the fix (`compiled_for(x)`, `with_dynamic(x)` at the call inside the library).

**Open, for the user: does `Callable` still need its exception?** Without it, a function passed from plain code is a concrete value, so a bare `Callable{A, S}` bound would compile the library per function (per closure), the cost `DynamicCall` was made to remove. Options: keep the exception; drop it and have libraries write `Dynamic{Callable{A, S}}`; or give every trait a declared default form for bare bounds (`Callable` declaring `Dynamic`), so that `Callable` is no exception but an instance.

**Open, for the user: library to library.** When library A passes a value to library B's bounded function, the value is already a trait-world value, so B's annotation does not re-decide: if B declares `Dynamic{X}` to avoid per-type copies and A passes compiled values, B is compiled per type anyway. The alternative, letting each trait module's entries re-decide for values whose mode was only a default, needs a "forced" flag on every value. The proposal keeps the simple rule until a case asks for more.

## 2. What the rule absorbs

| Today | Under the rule |
|---|---|
| `Callable{A, S}` with modes `DynamicCall`, `CompiledCall` | a trait with one operation, "called at `A`, returns `S`": `DynamicCall` is `Dynamic{Callable{A, S}}`, `CompiledCall` is `Compiled{Callable{A, S}}`; `dynamic_call(f)` is `with_dynamic(f)`, `compiled_call(f)` is `compiled_for(f)` |
| "a type that supplies its own behaviour gets its own copy" (traits §4) | the meaning of `Compiled{X}`, with sharing as an optimization |
| `dynamic by` (traits §5.9, Open), the solvers' model mode (open issue §2.15) | `Dynamic{X}` positions; the implementation declares nothing |
| `Dynamic{X}` opened at every bound | opened at `Compiled` positions only |
| TDE: a new problem type compiles the solver (about 330 ms) | `solve(prob::Dynamic{ODEProblemTrait}, …)` compiles nothing per type |

## 3. The lowering: what is compiled

- **`Compiled{X}`** is compiled per key, the sharing optimization:
  - the types of the declared fields the function reads;
  - the receiver type only if the function, through its callees, reaches an operation the receiver serves (refinement of traits §4: an override the function never calls costs no copy);
  - forwarding: the field's type, as now.
- **`Dynamic{X}`** is compiled once per position.
  - An operation call is the call-site split over the first four declared implementations, then the fallback: today a dynamic call; what follows the split is open issue 32 (E-145), with a table per trait or background recompilation as candidates.
  - A declared field is read through the object's per-type field slots (the views'); its type is the declared type, or the parameter value the bound fixes (`Dynamic{StateVector{Float64}}`).
- **Guarantees,** by the reasoning that covers `DynamicCall` and the split today (to verify): `Compiled` positions call at fact signatures; `Dynamic` positions record no edge to the set of implementations, and the split's branches are facts.
- **Closed builds:** a `Dynamic` position lists the declared implementations as targets; a `Compiled` position lists its keys, as now.

## 4. Questions for the user

**Answers** (user (2026-10-20), on the proposal's questions: "1. Dynamic default as exception for Callable, 2. Yes, 4. Yes, 5. Weak yes. If this causes issues, revisit. Explain 3."):
- 1: `Callable` keeps the dynamic default, an exception to the bare rule: `Callable{A, S}` means `Dynamic{Callable{A, S}}`.
- 2: the names `Compiled{X}`, `Dynamic{X}`, `compiled_for(x)`, `with_dynamic(x)`.
- 4: mixed modes: compiled per the keys of the `Compiled` arguments only.
- 5: a `Dynamic` position fixes every parameter its operations' result types use (weak yes; revisit if it causes issues).
- 3: explained, open.

1. **`Callable`'s default.** Today a bare `f::Callable{A, S}` is a dynamic call (adopted rev 988: a new closure must not recompile the solver). Under "a bare bound is `Compiled`", it would become a compiled call. Keep `Callable`'s default dynamic (an exception to the bare rule, written as `Callable{A, S} = Dynamic{Callable{A, S}}`), or make it compiled and have libraries write `Dynamic{Callable{…}}` where a function should not recompile them?
2. **The names:** `Compiled{X}`, `Dynamic{X}`, `compiled_for(x)`, `with_dynamic(x)`. `Dynamic` is already the value type; reusing it for positions is the point.
3. **A `Dynamic` value inside a `Compiled` function** passed on to another `Compiled` function is opened at each call. A loop over `Vector{Dynamic{Shape}}` calling a `Compiled` function per item dispatches once per item into code compiled per type. Fine as the rule, with the library choosing `Dynamic` for the inner function where that is better?
4. **Several bounded arguments with mixed modes** (`f(a::Compiled{X}, b::Dynamic{Y})`): compiled per key of `a` only. Any objection?
5. **Families:** `Compiled{X{T}}` per `T`; `Dynamic{X{T}}` fixes `T`, or must a `Dynamic` position fix every parameter its operations' result types use (as `Dynamic` values must today)?

## 5. Prototype and measurement

1. **TraitWorld:** `Compiled{X}` and `Dynamic{X}` in bounds; a `Dynamic` position's worker reuses `Dynamic`'s machinery (erase at the entry, split at operations); `compiled_for` and `with_dynamic` as per-value wrappers, as `compiled_call`/`dynamic_call` are; `Callable` re-expressed on top, its tests rewritten in the new spelling (no synonyms, section 0). As planned at the review of 2026-10-20: the attribute is the value's representation (`Compiled`: a trait object, compiled per key; `Dynamic`: a `Dynamic{X}`), so values carry by their type; every bounded function gets a second worker taking `Dynamic{X}`, compiled once; only entries decide, the untyped path (`known_type` false) being the `Dynamic` path; typed reads of declared fields on a `Dynamic` (today `getproperty` dispatches at run time and returns `Any`); `compiled_for` in TraitTables' and TraitMakie's loops.
2. **The measurement (a new registry row):** TraitDifferentialEquations' new model type (today's `ODEModel{Float64}`; the problem trait is W-2, after W-4) with `solve_ode` at a `Dynamic` position, against `Compiled`: first solve in a fresh session (expected near a dynamic callable's 19–25 ms, against 335–371), and the solve's run time per step (expected a few ns per right-hand-side call more), with the new type among the split's first four declared implementations and beyond them (the fallback, E-145's question). TraitTables' and TraitMakie's rows before and after their `compiled_for`. Rows timed whole, the garbage collector's time reported, on a quiet machine.
3. **The references:** traits §4, §9, §10 rewritten around the two modes; receiver types and keys moved to lowering §5 as the optimization of `Compiled`; the glossary.

Order: answer the questions of section 4, then 1 and 2 together, then 3. W-2 (TDE around `ODEProblemTrait`) follows, written in the new language.
