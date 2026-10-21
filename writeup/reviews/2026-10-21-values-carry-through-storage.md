# Review: values carry their attribute through storage (W-18)

**Date:** 2026-10-21. **Reviewer:** a critical reviewer (Claude, Fable 5.1), independent of the plan's author. **Status:** a review; not edited after today except by a dated addendum.

**Scope.** The proposal [`plans/2026-10-21-values-carry-through-storage.md`](../plans/2026-10-21-values-carry-through-storage.md), read against the references it changes ([traits](../reference/traits.md) §6.6, §9, §10–§10.3; [lowering](../reference/lowering.md) §9.3, §12, §13, §13.1), the decision rows of 2026-10-20 in [`record/decisions.md`](../record/decisions.md), the code it names (TraitWorld `src/attributes.jl`, `core.jl`, `entry.jl`, `BaseTraits.jl`, `trait_module.jl`, `untyped.jl`, `checks.jl`, `verify.jl`; TraitDifferentialEquations `src/ODECore.jl`, `src/TraitDifferentialEquations.jl`), and the evidence (E-145, E-148). No Julia was run; every claim below is from reading, and the ones marked *reasoning* are not verified by an experiment.

**The state of the tree.** TraitWorld's working tree already holds uncommitted work toward this plan (8 files, +240/−105 at `git diff --stat` on 4834cfc): `struct Compiled{X}` beside `Dynamic{X}`, `const Kept{X} = Union{Compiled{X}, Dynamic{X}}`, `@kept_of`, the entry's `_known_object`, `_dyn_like` on `Kept`, the views' item types. Where a finding concerns that code, it says so ("the tree"); the review is of the plan.

**Severity:** *major* changes the thesis or contradicts a decision in force; *medium* must be settled before the work is built; *minor* is a correction.

---

## Findings, by severity

### F1 (major). §4.2 contradicts the adopted rule that the caller's conversion always wins

- The decision in force: "A caller (inside or outside trait code) can explicitly declare compiled_for or with_dynamic and that always wins and never warns" ([decisions.md](../record/decisions.md), row "`Dynamic` and `Compiled`, the rule", the user's words); traits §6.6 override 3: "It always wins" (`traits.md:681`).
- §4.2: "A slot declared with one of the two converts on assignment … It changes the attribute, exactly as `with_dynamic(t)` in library code does." So `struct S; f::Dynamic{X}; end` in a library silently erases a caller's `compiled_for(f)`. That is the library switch the user objects to, moved from a function to a field. The plan's defence, "visible in its type", is the same defence SciML's `specialize` parameter has.
- The asymmetry: on an argument, `x::Dynamic{X}` decides "only for values first seen at its position" (`traits.md:682`); on a field, `f::Dynamic{X}` would re-decide a carried value. One spelling, two meanings.
- The hole exists in the code today: `Dynamic{Callable{A, S}}(f)` unwraps a `CompiledFor` without a word (`entry.jl:814`). `stored` honours `compiled_for` only because it tests for the wrapper first (`entry.jl:837`). The tree adds `Base.convert(::Type{Dynamic{X}}, c::Compiled{X})` and the reverse (core.jl diff), which makes every typed slot an implicit, silent conversion.
- A latent conflict in the decision log itself: the rows "who decides" and "the rest" say a value's attribute is "changed only by an explicit conversion in library code"; the row "the rule" says the caller's conversion "always wins". Neither says what happens when both are explicit and disagree. §4.2 answers it in the library's favour without saying so.

**Recommendation.**
- One rule, stated in §1: **a type annotation never changes a carried attribute; only a conversion call does.** Inside a trait module, `f::Dynamic{X}` and `f::Compiled{X}` on a field or an item type mean the union of §4.1 with that attribute as the default for values first seen there, exactly as the same annotation on a bound (`traits.md:680`). Drop §4.2.
- No implicit `convert` between `Compiled{X}` and `Dynamic{X}`; the constructors `Dynamic{X}(c)` and `Compiled{X}(d)` stay as explicit conversions. Storing the other attribute into a slot that is one Julia type (outside trait modules, where `Dynamic{X}` is a plain type, `traits.md:644`) is an error whose message names `with_dynamic`/`compiled_for`.
- Put the open question to the user: may an explicit library conversion (`Dynamic{X}(t)`) override a value the caller converted explicitly? My recommendation: no, an error (two explicit conversions that disagree), in the spirit of "identical or error". `Dynamic{C}(f)` on a `CompiledFor` (`entry.jl:814`) then refuses instead of unwrapping. With the union in storage a library rarely needs `Dynamic{X}(t)` at all: TDE's `keep_callback` (`ODECore.jl:146`) and `test/dynamic.jl`'s `Dynamic{Model}(m)` in `start` (the tree's test diff calls it "the library's choice") become plain stores.

### F2 (major). `Callable` is not a trait like the others, and the plan treats it as one; the TDE case is all `Callable`

- `Callable` has a lowering of its own: "it is not a `@trait` declaration" (`lowering.md:466`); its values are `CObj{A, S, F}`, `Erased{A, S}`, `CMulti` (`core.jl:1028`, `:1085`, `:1112`); it has no `conformance` method, no candidates, no entry in the table of declared implementations (`trait_module.jl:592`: an entry with a `:callable` argument is never `tabled`).
- So every sentence of §2–§3 and §5 needs a `Callable` form that the plan does not give:
  - What `Compiled{Callable{A, S}}` holds (the function? a `CObj`?). In the tree, `compiled_for(d::Dynamic{Callable})` gives `Compiled{Callable}(Val(:checked), getfield(d, :t))`: a `Compiled` holding the *erased* `CObj{A, S, Erased{A, S}}`, not the function. The function is reachable (`Erased.obj`, `core.jl:1030`), but nothing reaches for it.
  - How it is called. `Dynamic{Callable{A, S}}` has a call method (`entry.jl:820`); `Compiled{Callable}` has none.
  - How a bound opens it. `enter_callable` (`entry.jl:762–790`) has no branch for it; `_tw_type` returns `false` for it (its field is `Any`, `entry.jl:746`), so it falls to `attr = :dynamic` and is wrapped as if it were a plain function: `Erased{A, S}(compiled_value)`, which fails with `MethodError` at the first call.
  - "Opened by its type … through the table of declared implementations (lowering §9.3)" (§2) does not apply: for `Callable` the opening is Julia's dispatch on `typeof(f)` into the worker compiled per `F`: one dynamic call (evidence §2: an untyped call 105–117 ns) and a compile per new function. That is a function barrier, as §2 says, but a slower one than the table, and it should be stated.
  - `with_dynamic(abs2)` erases Base's function (`traits.md:767`); what `Compiled{Callable}(abs2)` is, and whether a function of the trait world is ever kept as a `Compiled{Callable}` wrapper rather than itself, is unsaid.

**Recommendation.** A section "`Callable`'s forms" in the plan: `Compiled{Callable{A, S}}` holds the function; its call is `CObj{A, S}(f)(args…)` behind a dynamic dispatch (state the cost); `enter_callable` takes it with `attr = :compiled`; `compiled_for(d::Dynamic{Callable})` takes the function out of the `Erased`; `_tw_type` counts both kept types as the trait world's; the several-signature form has a written type (F3d). A test per line.

### F3 (major). §4.3 (struct parameters bounded by a trait) is under-specified in four places, and its own example breaks a rule in force

(a) **What a read of such a field yields in trait code.** For a `Compiled` value the field holds "the user's object itself". Read in trait code, that is a plain value of the user's type: either rule 3 ("code must not depend on the user's type", `traits.md:615`) is suspended for these fields, or the read is rewritten to a trait object (`CObj{A, S, F}(f)` for `Callable`). The plan says neither. Today's `rhs!` calls `prob.f(du, u, prob.p, t)::Nothing` plain (`ODECore.jl:109`), so §9's promise for `Compiled`, "The signature is still checked" (`traits.md:765`), does not hold for a function kept raw; a rewrite of the read would restore it at no cost.

(b) **The example violates §9.** "The argument types `A` are a constant type. A bound whose `A` names a method's `where` variables (`f::Callable{RHSSig{P, T}, Nothing}`) is refused when the method is defined. Write one method per signature." (`traits.md:786`; T-17.) §4.3's constructor is a bounded function whose `Callable` bound names `P` and `T`, the constructor's own `where` variables. Either constructors are exempt (say why: the worker stores and never calls, so `A` need not be constant for the key), or the rule changes.

(c) **Julia's constructor rules.** A trait is not a Julia type, and a tuple of traits is not a type at all, so `F <: (Callable{…}, Callable{…})` cannot stay in the struct: the macro must strip the bound (`F` becomes `F <: Any`), keep Julia's default inner constructor `ODEProblem{T, P, F}(…)` (unchecked: fine, say so, as SciML's explicit `ODEFunction{iip, FullSpecialize}` is), replace the default outer constructor by the bounded entry, and handle a user-written inner constructor (then Julia defines no outer one to replace). `_dyn_type` today leaves anything under `<:` alone (`trait_module.jl:169`). Rules to write: several bounded parameters; a bounded parameter used in another field (`fs::Vector{F}`) or in no field; a parameter bounded by a trait with fields (key `Key{I, F}`, `lowering.md:235`) where the stored form's type is the user's type and the key is not.

(d) **The `Dynamic` of several `Callable`s.** Its type is unnamed. `Dynamic{(C1, C2)}` is refused today by T-50 with the reason "a tuple of types is not a type parameter" (`traits.md:1260`). I believe that reason is wrong: Julia accepts a tuple whose elements are valid parameters, and types are (`Val{(Int, Float64)}`); check with one line before building on it. The refusal of a user's one-signature `Dynamic{Callable{RHSSig, Nothing}}` (§7) is a choice, not a necessity: `Erased` holds the function, so the second signature's pointer can be made lazily like the first (`_erased_ptr_slow`, `core.jl:1059`). W-2 accepts it today with finite differences (`TraitDifferentialEquations.jl:40`). Refusing a value the reference shows as the way to keep a function (`traits.md:777`) needs the user's word.

**A simpler route to compare.** The plan's own §2 already gives the function barrier: a `Compiled` value "is opened by its type … once per call, at the next bound". A problem that keeps its function in the union field (§4.1) and a solver that reads it once per solve and passes it down a `Callable` bound compiles its loop per function, with one opening per solve, and needs no struct parameter. It needs an operation whose result is a `Callable` at two signatures (`rhs(prob)::(Callable{…}, Callable{…})`, Planned in `traits.md:793`) and changes `ODEProblemTrait`'s interface; it loses dispatch on the problem's type in plain code (the front end's barrier moves to the solver's bound). Both routes are principled. §4.3 is the larger language feature, and it is not ready to build until (a)–(d) are written. Whichever is chosen, the user's sentence that the demonstrators never constrain the design cuts both ways: §4.3 should be justified as a language feature, not by `ODEProblem`.

### F4 (medium). The union's storage cost is unmeasured, and the plan's "stays typed" hides a layout change (*reasoning*)

- `Union{Compiled{X}, Dynamic{X}}` is a union of two non-`isbits` types. In Julia such a union is not stored inline: a field of that type is a boxed pointer, and a `Vector{Kept{X}}` stores boxed pointers. Each store allocates a 16-byte box and each read is one more indirection. `Dynamic{X}` alone (`struct Dynamic{X}; t::Any; end`, `core.jl:404`) is an immutable with one reference, stored inline since Julia 1.5: `Vector{Dynamic{Hook}}` is one word per item and `push!` allocates nothing. So "Julia splits on a union of two types, so reading such a field stays typed" (§4.1) is right about inference and silent about layout.
- Consequences: every `Vector{Hook}` field and every `Kept{X}` field pays a box per store; the tree makes `DynamicItems` over a `Vector{Any}` yield `Kept{X}` items (`_dyn_item_type`, BaseTraits diff), so `collect(DynamicItems{S}(v))` (E-145's 19.4 ns row, `evidence.md:70`) now builds a `Vector{Kept{S}}` with a box per element, by construction; its sum then pays a union split per item on top of the candidate split. E-145's first row (`Vector{Dynamic{S}}`, a concrete item type) is unchanged: such a vector meets the bound as it is (`_cross_view`, `BaseTraits.jl:279`).
- The alternatives the task asks about:
  - *An abstract supertype* `Kept{X}` with two concrete subtypes: boxed like the union, and worse: a field of abstract type is not union-split, so an operation on it is a call at an abstract type, a run-time site under the facts rule (`compiler.md:121`). Reject.
  - *One concrete type with a flag* (`t::Any`, `compiled::Bool`): inline (two words), no allocation, one branch at a bound and nowhere else, since operations and field reads are the same split for both attributes (§2). It loses `Dynamic{X}` and `Compiled{X}` as Julia types for plain code's dispatch (`traits.md:644`) and the two names the user chose.
  - *The union*, as in the tree: inference splits it, and each split is a fact (`facts.md:184`, `compiler.md:103`); the cost is the box.
- The tree introduces the name `TraitWorld.Kept{X}` (core.jl diff) while §4.1 says "No new name is introduced for it". Plain code will meet the name in printed types (`ODEProblem{Float64, Nothing, Union{Compiled{…}, Dynamic{…}}}`) and must write the union out for its own fields.

**Recommendation.** Keep the union; before the decision is final, an experiment row (E-n, a few minutes): `push!` into `Vector{Kept{Hook}}` against `Vector{Dynamic{Hook}}`, a field read plus one operation on each, and E-145's rows re-run on the tree. The flag form is the fallback if the box shows in a demonstrator. Decide the name: either `Kept{X}` is public and documented (traits §10, the glossary), or it stays internal and the reference says "write the union out".

### F5 (medium). Writes through views: the plan is silent, and the tree breaks §10.3's rule

- §10.3: "A write stores the user's object the `Dynamic` holds, not the `Dynamic`. After `retain!(isnum, v)` on a `Vector{Any}`, `v` holds the user's numbers, the same objects as before." (`traits.md:921`.)
- The tree's `DynamicItems.setindex!` stores the `Compiled{X}` wrapper itself into the user's vector when the item type may carry (`_may_carry(X, Any)` is `true`), and `CompiledItems.setindex!` stores the `Dynamic{X}` wrapper likewise (BaseTraits diff). So after a loop that reads an item, converts it with `compiled_for`, and writes it back, the user's `Vector{Any}` holds a `Compiled{Shape}` where it held a `Circle`. The two views also disagree with each other on which wrapper survives.
- §5 of the plan says nothing about writes; §1's "Storage never decides" does not say what a write stores.

**Recommendation.** Write the rule. My recommendation: a write stores the user's object, always (the §10.3 rule stands); a user's own wrapper (`compiled_for(x)`, `Compiled{X}`) in a plain container is the user's, and trait code that writes an item back writes the object, so the attribute of an item re-stored into a plain container is not carried. Say it in §5 and test `retain!` over a `Vector{Any}` that holds a `compiled_for` item.

### F6 (medium). The first-seen rule has two storage cases the plan does not decide

(a) **A plain value assigned from plain code** into a field whose type is a trait's name (`obj.model = circle`; traits §10 "Assigning from plain code", `traits.md:835`, Planned). Which attribute? §6.6 decides by whether "the code that sees it knows its concrete type" (`traits.md:672`); `convert` is always specialized on the value's type, so inside it the type is always known, and every such assignment would be `Compiled`, also from a caller that held the value as `Any`. The §6.6 rule cannot be evaluated in a `convert` method. The tree defines no `convert` for a plain value, so the assignment errors today.

(b) **An operation's result declared with a trait.** §6.6: "A field or an operation's result declared with a trait is `Dynamic`" (`traits.md:676`). §8 replaces the field half only. With the union as the trait name's meaning, an implementation's method must return a `Kept{X}` value; the result assertion is an `isa`, not a conversion; nobody converts the plain value such a method naturally returns.

**Recommendation.** (a) Decide and write: the trait's default (`@dynamic`) else `Compiled`, which is what a specialized `convert` can do; or require `Compiled{X}(x)` / `Dynamic{X}(x)` from plain code, as today. (b) State the rule for results, or mark it Open with an issue number.

### F7 (medium). Places that assume "a value of unknown type at a bound is `Dynamic`" and are not in the plan's list

The plan's §9 lists the entry, the conversions, the union and the views. Also affected (file:line as committed):
- `enter_callable`, `entry.jl:762–790`, and `_tw_type`, `entry.jl:740` (F2).
- `enter_kw` (`entry.jl:514`; T-47, a bounded keyword from a caller that does not know the type), `enter_kw_callable` (`entry.jl:539`) and `enter_each` (`entry.jl:501`, varargs): a `Compiled{X}` keyword or vararg element.
- The seams: `_seams` converts a trait object to a `Dynamic{Y}` where an operation's argument is declared `Dynamic{Y}` (`attributes.jl:131–142`); a `Compiled{Y}` arriving there is a `TraitArgumentError` from `opcall`'s check. Decide: refuse with a message naming `with_dynamic` (consistent with F1), or convert at the seam.
- `_like_out`, `entry.jl:906`: `u isa Dynamic` only; a `Compiled{X}` input falls into `_invert` with the wrapper as the user's object. The tree fixes `_dyn_like` (`Self` results) and not this.
- `verify.jl:362, 410`: `D <: Dynamic` only; `Compiled{X}` constants held by compiled code and their targets are not listed.
- `is_dynamic(::Compiled)`: missing (`checks.jl:134` lets `is_dynamic` through).
- The table serves `Compiled{X}` only at `tabled` entries: trait and ordinary positions, no keywords, no varargs, no `Callable` argument (`trait_module.jl:592`), no position where containers cross, and only declared implementations (`untyped.jl:81–89`). Everywhere else a `Compiled{X}` takes the generic path: the trait object assembled behind a dynamic call, then the worker selected by a second (`lowering.md:412`): 105–117 ns and 64 bytes per call (open issues §3, item 9). §2 says "through the table"; it should say "through the table where the entry has one, else two dynamic calls".
- `ErasedKey{P, Y}`'s `Y` and `_compiled_view_item` (`attributes.jl:23–28`, `core.jl:297`) exist because `CompiledItems` at an abstract item type declared its items `Any`; the tree now declares them `Compiled{X}` or `Kept{X}`, so that machinery may be dead. Retire it or say why it stays.

### F8 (medium). Equality and hash differ by attribute, against "never of results"

- The tree defines `==` for `Compiled{X}` and for `Dynamic{X}` within each type only, with different hash salts (`:TraitWorldCompiled`, `:TraitWorldDynamic`). `Compiled{X}(o) == Dynamic{X}(o)` falls to `===` and is `false`; a `Set` or `Dict` keyed by kept values separates two handles to the same object by their attribute. §6.6: the attribute "is a choice of speed, never of results" (`traits.md:670`); §2: "compared and printed the same way".

**Recommendation.** `==`, `isequal` and `hash` by the held identity across both types, one salt; `===` differs by type and is documented as such; a test.

### F9 (minor). Prior art (question 8)

- §1, Rust and Swift: the substantive claim holds. Neither generates code at run time; `Box<dyn P>` calls through a vtable (Rust's word; "witness table" is Swift's), and Swift's opened existential runs shared generic code driven by witness tables, specialized only where the compiler could at build time. One precision: the plan's own mechanism for a `Compiled{X}` at a bound is the table of lowering §9.3, which the reference itself calls "how Swift opens a value of a protocol type" (`lowering.md:411`); the difference is that the code reached is compiled per key (per function, for `Callable`), not shared. Say "per key", not "for its type" (traits §4).
- §4.3's precedents: Rust's `struct S<F: Fn(…)>`, Swift's `struct S<F: P>`, and Julia's performance tip are accurate. SciML's `ODEFunction{iip, specialize, F, …}` is not "where the library chooses": the caller chooses the level per problem (`ODEProblem{iip, FullSpecialize}(f, …)`), with `AutoSpecialize` the library's default. That is the "library provided switch" of the user's words; the difference here is that the switch is the language's (`compiled_for`) and uniform across libraries, not that the caller chooses. `FunctionWrappersWrapper` as the precedent for a `Dynamic` of several signatures is accurate (a tuple of `FunctionWrapper`s, chosen by argument types); its pointers are made at construction, here at the first call.

### F10 (minor). Smaller corrections to the plan's text

- §3: "`compiled_for(t)` on a `Dynamic` trait object of one trait gives a `Compiled{X}`. With several traits it gives the opened trait object" — one call, two kinds of result by a count. The tree does the cleaner thing: on a `Dynamic{X}` value a `Compiled{X}`; on a trait object the opened trait object (`attributes.jl:155`, unchanged). Make the text match.
- §2: "the cost is the same" holds per value; a `Kept{X}` slot pays a union split on top (F4), and a plain item read at a `Compiled` position allocates nothing only while the `Compiled{X}` wrapper does not escape. Say both.
- §4.1: "Storing a trait object there converts it by its key" is right and is the one place where the key, not a decision, gives the attribute; say that a trait object at its own key made by `compiled_for(t)` from an erased one is "at its key" too.
- §7: "Callbacks are kept as `Vector{Callback}`" means `FunctionCallback`'s two `Dynamic{Callable}` fields (`ODECore.jl:137–140`) also become unions, or stay the library's explicit choice; decide per F1.
- §8: the glossary row for `Compiled{X}`, and `Kept{X}` if it is public (F4); `intro/` where it says a trait's name in a field means `Dynamic`; lowering §17's encodings table (a trait's name as `Kept`, L-6).
- Process: no experiment row is planned (CLAUDE.md: the row before the run), and the tree holds the work before the review. The tree's `test/dynamic.jl` now asserts `fieldtype(S, :model) === TraitWorld.Kept{Model}`: a test of the name, which is undecided (F4).

---

## The eight questions, in short

| Q | Answer | Findings |
|---|---|---|
| 1. §1 against §6.6 and the overrides | Coherent for values that pass a bound. Two cases are decided nowhere: a plain value assigned from plain code into a trait-named field, and an operation's result declared with a trait. One case is decided against the rule in force: a slot declared `Dynamic{X}` re-decides a carried value. | F1, F6 |
| 2. `Compiled{X}` through the same split, opened at a bound | Sound for `@trait` traits at tabled entries; unsound as written for `Callable`; the generic path (two dynamic calls) is what every other entry runs; seven places in the machinery still assume `Dynamic`. | F2, F7 |
| 3. The union | The right representation for inference and the facts rule; an abstract supertype is worse (run-time sites); one type with a flag is layout-optimal but loses the two names as types. The union boxes every stored value; measure before deciding. | F4 |
| 4. §4.2 | A loophole: it re-creates the library switch and contradicts the user's rule. Drop it; annotations never convert, only calls do; ask the user about library conversions of caller-converted values. | F1 |
| 5. §4.3 | Principled in direction (Rust, Swift, the Julia tip); not ready: the field-read rule, the `where`-variable rule (its example breaks §9), the constructor rules and the several-signature type are unwritten. A simpler route exists inside §2. | F3 |
| 6. §5 items | Sound; concrete item types unchanged; the `Vector{Any}` path pays a union split per item and the collect row of E-145 changes by construction; writes are unspecified and the tree gets them wrong. | F4, F5 |
| 7. What is missing | Equality and hash (wrong in the tree), `Like` results, `verify_main`, seams, keywords and varargs, `_tw_type`, conversion on assignment, results declared with a trait. Printing, threads, world age, strict mode, package images and the facts rule hold as for `Dynamic{X}`. | F6, F7, F8 |
| 8. Prior art | Rust/Swift: right in substance, one precision. SciML: "where the library chooses" is wrong; the caller chooses there too. | F9 |

---

## Verdict

The principle is right and matches the user's rule: a value's attribute belongs to the value, storage never decides, and a trait's name in storage is the union of the two kept forms (§1, §3, §4.1, §5). Build those, with F5 and F6 written first and F4 measured.

Two parts should not be built as written. §4.2 contradicts the decision that the caller's conversion always wins (F1): drop it and put the one open question to the user. §4.3 is a language feature whose rules are unwritten and whose example breaks §9 (F3): write the four rules or take the simpler route; either way, `Callable` needs its own section before any of §2–§5 applies to TDE's function (F2).

What the tree already holds is on the right lines and has three bugs to fix before it is committed: the converts between the two kept types (F1), the wrappers written back into the user's container (F5), and equality by attribute (F8).
