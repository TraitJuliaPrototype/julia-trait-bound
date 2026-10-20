# `Dynamic{X}` and `Compiled{X}`: one language for trait positions (proposal, 2026-10-20)

**Status:** proposal, for the user; refined with the user (section 1b). Work item W-4 (`../record/todo.md`), open issue 33. Nothing here is built.

The user (2026-10-20): "I think all of this points to a unifying language. f(x::Dynamic{X}) for an erased position, and the new f2(x::Compiled{X}) for a static one. Then f(compiled_for(x)) and f2(with_dynamic(x)) override. Importantly these rules can be given without talking about receiver types at all. Receiver types are an optimization in Compiled{X} to reduce the amount of things f2 actually recompiles for using the trait information." And: "I think a bare x::X should be compiled by default, as that mirrors what Julia does now. But this is a decision that should be revisited later."

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

1. **TraitWorld:** `Compiled{X}` and `Dynamic{X}` in bounds; a `Dynamic` position's worker reuses `Dynamic`'s machinery (erase at the entry, split at operations); `compiled_for` and `with_dynamic` as per-value wrappers, as `compiled_call`/`dynamic_call` are; `Callable` re-expressed on top, its tests unchanged.
2. **The measurement (a new registry row):** TraitDifferentialEquations' new problem type with `solve` at a `Dynamic` position, against `Compiled`: first solve in a fresh session (expected near a dynamic callable's 19–25 ms, against 335–371), and the solve's run time per step (expected a few ns per right-hand-side call more). Rows timed whole, the garbage collector's time reported, on a quiet machine.
3. **The references:** traits §4, §9, §10 rewritten around the two modes; receiver types and keys moved to lowering §5 as the optimization of `Compiled`; the glossary.

Order: answer the questions of section 4, then 1 and 2 together, then 3. W-2 (TDE around `ODEProblemTrait`) follows, written in the new language.
