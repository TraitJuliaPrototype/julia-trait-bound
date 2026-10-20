# `Dynamic{X}` and `Compiled{X}`: one language for trait positions (proposal, 2026-10-20)

**Status:** proposal, for the user. Work item W-4 (`../record/todo.md`), open issue 33. Nothing here is built.

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
