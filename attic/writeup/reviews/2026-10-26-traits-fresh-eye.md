# Fresh-eye review of reference/traits.md (2026-10-26)

**Reviewed:** design repository c6662bf (`writeup/reference/traits.md`, 1548 lines); TraitWorld main 4410407; julia-1.13 fa4e7f5798 (source). The runs used `julia-1.13/usr/bin/julia`, whose system image is the build of 2026-10-21 (binary reports 6d480d0753); TraitWorld's compiled cache was current for it (`Base.isprecompiled` true).

**Method.** I read `reference/README.md`, then `traits.md` in full, then `facts.md`, `lowering.md`, the glossary, `open-issues.md` and `record/decisions.md`, and the anchors `traits.md` links to in `compiler.md`, `intro/`, `reviews/`, `record/todo.md` and `experiments/docs-examples/reference.jl` (all exist). I checked "Implemented" claims against TraitWorld's source where a grep settles it: the trait-default macros, `strict!`, `@joint_owners` and `owner`, the extension-trigger check, the `getproperty` rule, `_param_agrees`, `_redeclared` and `test/redeclare.jl`, `_trait_argument_outside`, `_warn_hidden_attributes`, `check_bounds`, `key_concrete`, `Kept{X}(x)`, `_implement_where`, `check_definitions`, `test/wherevars.jl`, `@mutating`, the precompile workload's old spelling, and Base's `abstractdict.jl`. Five questions that reading could not settle I ran as one 30-second script (`probe.jl`, same directory as this file; the prescribed `flock … nice` invocation): dispatch among bounds of one trait at different fixed parameters (P1), an operation whose second argument is typed by the trait's name (P2), `Kept{X}(x)` at the prompt (P3), `@implement` of a bundle (P4), a family with a block in the `S{T} where {T}` form (P5), a kept value of a subtrait at a supertrait's bound (P8). **Not checked:** `compiler.md` beyond its anchors; strict mode's behaviour; `verify_main`; the demonstrators; the deviation rows I do not name below (their line numbers are declared to be those of 227781a, 40 commits back); `intro/`.

**Counts.** High 3, Medium 17, Low 16.

Severity: **High** = a contradiction or unsoundness in the design, or a false statement about what is built; **Medium** = an inconsistency or gap a reader trips over; **Low** = wording, a stale term, a link.

---

## High

### H1. Who may add a bounded method to another package's function: §5.5 and §8.4 contradict

- `writeup/reference/traits.md:619` (§5.5): "a package may add one to a function it owns, or to another package's function where the package owns a trait the bound names."
- `writeup/reference/traits.md:1139` (§8.4): "BaseTraits' algorithms have names of their own: only Base may add bounded methods to Base's functions ([§5.5])." Repeated in `writeup/open-issues.md:101` (item 31).
- By §5.5, TraitWorld owns `MutableIndexable`, so `Base.filter!(f, xs::(MutableIndexable, Resizable))` in its trait module is allowed. By §8.4 it is not. A reader cannot predict which; the two sentences cite each other.
- *Verified* by reading. The implementation follows §8.4's side (lowering L-3: only the function's owner adds a bounded method of a shape the function has none of yet), which is recorded as a deviation from §5.5, so §5.5 is the intended rule and §8.4 states a different one as if it were the design.
- The real reason BaseTraits needs names of its own is dispatch, not ownership: by §5.5 "types first", a bounded `filter!` ranks below Base's `filter!(f, ::AbstractVector)` and never runs for Base's containers.
- **Fix:** replace §8.4's sentence by: "BaseTraits' algorithms have names of their own: a bounded method of Base's `filter!` would rank below Base's typed methods ([§5.5](#55-dispatch-types-first-then-traits)) and never run for Base's containers." Fix `open-issues.md` item 31 the same way. If the design instead means "only the owner", change §5.5 and retire W-36's premise; that is a decision (no row in `decisions.md` covers it).

### H2. The first-seen table lists two places where the first-seen rule does not apply, by the section's own bullets and by the code

- `writeup/reference/traits.md:738-749` (§6.2): the table names six places where a plain value is first seen, then "**The first-seen rule.** There, a plain value is `Compiled` if the code that sees it knows its concrete type, and `Dynamic` if not."
- `writeup/reference/traits.md:754`: "`Kept{X}(x)`, and a store into a field or container of a trait's name, take the trait's default, whoever calls: `Compiled`, unless the trait declares `@default_with_dynamic_self`." So at the prompt, where "every call typed at the prompt passes `Dynamic` values" (line 753), `Kept{Shape}(c)` is `Compiled`.
- `writeup/reference/traits.md:756`: "An operation's result declared with a trait is `Dynamic`", whatever the code knows.
- `writeup/reference/traits.md:775` (§6.3): "Without one [a trait's default], the first-seen rule decides." `writeup/reference/traits.md:942` (§7.1): `Kept{X}(x)` is made "by the first-seen rule and the trait's default". `writeup/reference/traits.md:784`: the list of places a trait's default applies omits the operation's result.
- *Verified*: `TraitWorld/src/core.jl:590` (`Kept{X}(x)` is `Compiled{X}(x)` unless the trait's default is `:dynamic`; the caller's knowledge is not consulted); probe P3: `Kept{M2.Sh}(C2(1.0))` at the prompt prints `Kept{Main.M2.Sh}: Compiled at C2`. The operation-result claim is from the text only (not run).
- The chapter calls itself "the one home of that rule" (line 705) and contradicts itself inside it. The decision row "A trait's default, either attribute" (`decisions.md:101`) fixes only that a trait's default applies at `Kept{X}(x)`; what a trait *without* a default does there is the builder's choice, stated at line 754 and nowhere else.
- **Fix:** split the table: the first-seen rule governs a bound, an item read and a struct parameter; `Kept{X}(x)` and a store take the trait's default, else `Compiled` (say why: a store has no caller to ask); an operation's result is `Dynamic` and no default applies to it. Change §7.1 line 942 to "by the trait's default ([§6.2](#62-how-plain-values-enter-the-trait-world))" and §6.3 line 775 to "Without one, the first-seen rule decides at a bound, an item read and a struct parameter." Add the `Kept{X}(x)` choice to the decision log as "mine" and to `open-issues.md` §1, or decide it.

### H3. `@implement` of a bundle: claimed Implemented, fails with an internal error, and §3.6 and §3.7 give it opposite meanings

- `writeup/reference/traits.md:321` (§3.7): "after `@trait Table <: (ColTable, RowTable)`, `Table` and `(ColTable, RowTable)` are the same trait"; line 319: `@implement` on a tuple "implements each member"; line 327 (Status): "Implemented for bounds and attributes on them, supertrait lists, bundles and `@implement`."
- `writeup/reference/traits.md:295` (§3.6): "`@implement B T` implements `B`'s own operations. `T` must conform to `A` too, by its own implementation." A bundle has no own operations, so by §3.6 `@implement Table T` requires both members declared first and implements nothing; by §3.7 it declares both. Two rules, opposite meanings, neither says which wins for a bundle.
- *Verified* (probe P4, TraitWorld 4410407): `@implement M4.AB4 G4` for `@trait AB4 <: (A4, B4)` raises `MethodError: no method matching trait_ops(::Type{Main.M4.AB4})`, an internal error, and defines nothing (`conforms(G4, M4.A4)` is `false`; `both(G4(1))` raises `MethodError`). The tuple form `@implement (M4.A4, M4.B4) G4` works (`both(G4(1)) == 3`). No deviation row covers the bundle form.
- **Fix:** decide (I suggest: `@implement Bundle T …` means `@implement (members…) T …`, since §3.7 says they are the same trait), state it in §3.6 under bundles and in §3.7, and add a row T-73: "`@implement` of a bundle raises an internal `MethodError` (`trait_ops`) and defines nothing; write the tuple." Until decided, the §3.7 status must not say "bundles and `@implement`".

---

## Medium

### M1. §2's load guarantee omits the exceptions facts.md names

- `writeup/reference/traits.md:144`: "Loading another package does not discard a trait module's compiled code, except a change by a stakeholder of code it depends on, or a pirate that wins there". Same at `:1226` (§10.3).
- `writeup/reference/facts.md:146-152` (§2.2) names more: a binding redefined from another module, the standard libraries counting as Julia's own code (open issue §1.19), direct calls into the compiler (open issue 27), a method on a closure's type from outside its module, and (line 134) plain code the facts code names.
- *Verified* by reading. facts.md wins on what compiled code may assume, but traits.md states the guarantee to programmers without the list.
- **Fix:** "… or a pirate that wins there, with the exceptions [facts §2.2](facts.md#g2) lists."

### M2. "No later load can create the ambiguity" contradicts §5.5's own "who may add"

- `writeup/reference/traits.md:616`: "Only the function's own methods are involved, so no later load can create the ambiguity."
- `writeup/reference/traits.md:619`: another package may add a bounded method to this function where it owns a trait the bound names. That is a later load adding a method of the function.
- *Verified* by reading; `TraitWorld/src/trait_module.jl:1242` (`check_bounds`) scans `methods(f)` at the adding module's end, so the ambiguity is caught there, not never created.
- **Fix:** "A package that adds a bounded method to the function ([below](#55-dispatch-types-first-then-traits)) is checked at its own module's end, so an unrelated bound never goes unreported."

### M3. A value conforming at other parameters: refused, or the fallback?

- `writeup/reference/traits.md:557` (§5.1): "A value conforming at another value is refused at the call with `TraitBoundError`."
- `writeup/reference/traits.md:618` (§5.5): "a value that conforms to none of the bounds reaches the most specific ordinary method that applies". Whether "conforms to none of the bounds" includes "conforms at other parameter values" is not said; §5.5 also never says two bounds of one trait at different fixed parameters may stand side by side.
- *Verified* (probe P1): with `f(v::SV{Float64})`, `f(v::SV{Float32})` and `f(x) = :fallback`, a `Vector{Float64}` gives `:f64`, a `Vector{Float32}` `:f32`, a `String` `:fallback`, and a `Vector{Int}` raises `TraitBoundError` ("whose bounds need a value conforming at the parameters they fix: SV{Float64}; or SV{Float32}"), typed and at the prompt. So the refusal wins over the fallback.
- **Fix:** in §5.5 "Among bounds" add: "Bounds of one trait at different fixed parameters are selected by the value's parameters. A value that conforms at none of them is refused (`TraitBoundError`); it does not reach the fallback." Cross-link from §5.1.

### M4. A trait's name on an operation's second argument is undefined, accepted, and fails at every call

- `writeup/reference/traits.md:193` (§3.1): "Further arguments are typed as in a method". `:198` defines `Dynamic{Y}`, `Compiled{Y}`, `Kept{Y}` there; a bare trait name (`overlap(a::Sh, b::Sh)::Float64`, Rust's `fn eq(&self, other: &Self)`) is covered nowhere; the §6.3 table's column "on an operation's argument" defines `X` only as "the first argument".
- *Verified* (probe P2): `@trait` accepts `overlap(a::Sh, b::Sh)`, definition checking passes `tot(a::Sh, b::Sh) = overlap(a, b)`, and the call raises `TraitArgumentError: … declared for arguments Tuple{Main.M2.Sh}, got Tuple{Main.M2.Sh at Dynamic}`.
- **Fix:** define it in §3.1 (either "a trait's name on a further argument is a type, as outside trait modules: write `Kept{Y}`", with the declaration refused at `@trait`; or make it a bound). Until built, a deviation row: accepted by `@trait` and by definition checking, fails at the call.

### M5. §14 says a trait is written where an abstract type is written, "an argument" included; §2 refuses that outside trait modules

- `writeup/reference/traits.md:1347`: "it is written where an abstract type is written (an argument, a field, a type parameter)".
- `writeup/reference/traits.md:149`: outside trait modules "a method with a trait's name as an argument's type is refused when it is defined (`TraitUseError`), now and with traits in the type system" (decision of 2026-10-21, `decisions.md:108`).
- *Verified* by reading; `TraitWorld/src/hooks.jl:162` implements the refusal.
- **Fix:** "(an argument in trait code; a field or a type parameter anywhere, as `Kept{X}`)".

### M6. Planned `x isa X` / `T <: X` against "an implementation discards no trait code"

- `writeup/reference/traits.md:339` (§4): "It discards no trait code." `:347`: "declaring one invalidates no trait code".
- `writeup/reference/traits.md:1362` (§14, Planned): "An implementation adds the trait to the type's supertypes after the type is defined. That is sound because only a stakeholder declares it".
- A membership test `x isa X` with `x::Circle` folded to `false` in compiled trait code becomes wrong when `@implement X Circle` is declared later. Either the implementation invalidates that code (a stakeholder's change, which is what line 1362 argues, and which contradicts §4's unconditional claim), or a membership test is never a compile-time constant (what `conforms` does today: decided in the decision world, no fold). The reference states neither.
- *Reasoning* (not run).
- **Fix:** add to §14: "A membership test on a type is answered when it runs; compiled code never folds it, so an implementation invalidates nothing" (consistent with §4), or make §4's claim conditional. An open issue if the choice is not obvious to the user.

### M7. §1's status overclaims: tuple forms and the field-bound form

- `writeup/reference/traits.md:118`: "Implemented, except the forms under `(* planned *)`."
- But the tuple-of-traits forms of `KeptType`, `ItemParam`, `StructParam`, `Param`'s trait bound and a field's or element type are Planned (§3.7 status, line 327; W-29 queued), and are not under `(* planned *)`. The Planned `f::(F <: Bound)` (§7.4, T-60) is not in the grammar at all; `@joint_owners` (§10.1) neither. `FamilyForward` puts `where` after `by`, `Target` puts it before `How`: two orders for one form (§4.7 line 451 uses the first, line 465 the second).
- *Verified* by reading.
- **Fix:** move the tuple forms' status into the §1 status line ("tuples of traits are Implemented only at bounds and in `@implement`, §3.7"), add `FieldBound ::= Name "::" "(" Name "<:" Bound ")"` and `JointOwners ::= "@joint_owners" Name+` to the grammar, and use one `where` order.

### M8. The explicit constructor of a bounded struct is "unchecked, as in Julia": the analogy is false, and the hole is unstated as a hole

- `writeup/reference/traits.md:995` (§7.4): "The constructor with explicit parameters (`ODEProblem{T, P, F}(…)`) stores what it is given, unchecked, as an explicitly parameterized constructor does in Julia."
- In Julia `struct S{F <: Function}; f::F; end; S{Int}(1)` raises `TypeError` (`F <: Function` is checked when the type is applied). Here the bound is stripped from the struct (lowering §13.2), so `S{MyType}(x)` with `MyType` not conforming is accepted, and code over the struct reads `f` as a `Compiled` value of the trait without a check (line 992). The declared contract "its field keeps a value of that trait" (line 990) does not hold for that constructor.
- *Reasoning* (not run).
- **Fix:** either Plan the check (`S{F}` refused unless `conforms(F, Bound)`, the counterpart of Julia's bound check) or state the hole plainly ("the parameter's trait bound is not checked there; a non-conforming value fails at its first operation") and drop the analogy.

### M9. "Concrete" is silent about kept forms; the code answers differently for the three

- `writeup/reference/traits.md:1272` (§11): concrete is "a concrete type, or a `Union` of at most four concrete types, whose type parameters are concrete in the same sense, all the way down". `Kept{Hook}` has the parameter `Hook`, a trait: by the letter, not concrete. So a trait with `@enforce_concrete_only` cannot have a parameter whose value is `Vector{Kept{Hook}}`, which is what `hooks::Vector{Hook}` means in a trait module (§7.2). §11.1 line 1286 exempts only a `Dynamic` *value* at a bound.
- *Verified*: `TraitWorld/src/implement.jl:72-87` (`key_concrete`) counts `Dynamic{X}` as concrete and `Kept{X}`, `Compiled{X}` not (they fall through to the parameter check). An unlisted deviation either way.
- **Fix:** add to §11: "A kept form (`Dynamic{X}`, `Compiled{X}`, `Kept{X}`) and a `Callable` form count as concrete: their parameter names a trait by choice." Add a deviation row for `Kept`/`Compiled`.

### M10. A defaults-only implementation has no receiver type, yet `Self` is the conforming type

- `writeup/reference/traits.md:874` (§6.7): an implementation whose operations are all served by defaults "has no receiver type. Its key is the declared fields' types alone." `:277` (§3.5): for such a type `Self` "is the conforming type".
- Code compiled per key cannot know a `Self` that is not in the key: a default returning `::Self`, or an equation `T = eltype(Self)`, has no value there. L-21 records what TraitWorld does (such a type gets a receiver type after all); the reference has no rule, so L-21 is a deviation from nothing.
- *Verified* by reading (`lowering.md:758`).
- **Fix:** a rule in §6.7: "An implementation whose trait names `Self` in an equation, an argument or a result has the conforming type as its receiver type, whether or not its own methods serve an operation." Then retire L-21, or decide otherwise and keep it.

### M11. An override of a family member by its parameter type's owner is accepted or refused by load order

- `writeup/reference/traits.md:457` (§4.7): the owner of `MyT` "may define an override for that member until then [the member's first use], and not after", and "Compiling a caller that knows the member's type is a use".
- Whether some other package's precompilation compiled a caller at `S{MyT}` before the owner's package defined its override is not under the owner's control. The same section's §5.5 (line 616) is careful to avoid order dependence. This challenges a consequence of the decision row "A family member's builder is fixed in the code of a caller that knows its type" (`decisions.md:41`), not the decision itself.
- *Reasoning*.
- **Fix:** state the order dependence in §4.7, or restrict: "An override by the parameter type's owner is accepted only in the owner's own package, which loads before any caller can name its type." An open issue if the user wants to choose.

### M12. §3.4 and §4.6 status lines say the equation check is not built; T-37 and the code have it for single types

- `writeup/reference/traits.md:273`: "except the check of a stated value against an equation (T-37)". `:438`: "today a stated value replaces the equation's value (T-37)".
- `writeup/reference/traits.md:1513` (T-37): "Checked for an implementation of one type (`_param_agrees` …; `test/params.jl`). For a family … the stated value still replaces the equation's".
- *Verified*: `TraitWorld/src/implement.jl:1291` defines `_param_agrees`; `test/params.jl` exists.
- **Fix:** both status lines: "except for a family (T-37)".

### M13. T-57 states a false fact and cites a retired row

- `writeup/reference/traits.md:1533`: "(The block form `@implement X S{T} where {T} begin … end` is not lowered as a family in any module: T-5.)" T-5 is *Retired* (line 1481) with no content.
- *Verified* (probe P5, TraitWorld 4410407): inside the owner's module, `@implement KV S5{T} where {T} begin kl(v) = length(v.v) end` is accepted and `use(S5([1.0]))` returns 1. `TraitWorld/src/implement.jl:1340-1347` routes the form to `_implement_family`.
- **Fix:** delete the parenthesis. Re-verify T-57's main claim (a family with a block declared outside the trait's module) before keeping the row; I did not run it.

### M14. Status index rows that contradict the sections or cite retired rows

- `writeup/reference/traits.md:1409`: "the family-wide check at the declaration; a member's override | Planned | §4.7, T-26, T-28". §4.7 (line 455) and the decision of 2026-10-21 ("checked at first use") say the family-wide check at the declaration is not part of the design; T-26 is retired.
- `writeup/reference/traits.md:1407`: "families, joint families | Implemented | §4.7, T-5, T-6" cites retired T-5.
- `writeup/reference/traits.md:1396`: "a value seen through the traits it entered with | Implemented, except T-53, T-54": the refusal is the rule's only observable effect, and it is not built (W-31 queued). "Planned (T-53, T-54)" is honest.
- *Verified* by reading.
- **Fix:** the three rows as above.

### M15. Redeclaration: lowering says "accepted with another meaning", traits says refused; and the Planned semantics are undefined

- `writeup/reference/lowering.md:230` (§4.8): "Other forms are accepted with another meaning (traits T-29)". T-29 is retired. `writeup/reference/traits.md:518`: "Today a second declaration is refused in a session, in every form".
- *Verified*: `TraitWorld/src/implement.jl:802-805`, `:1212`, `:1231` (`_redeclared`) and `TraitWorld/test/redeclare.jl` refuse every form. lowering.md is the stale one.
- The Planned redeclaration (`:513`) says only "changes it, as Julia 1.13 redefines a struct". What happens to kept values that hold the old builder (lowering §4.8: they keep it), to workers compiled for the old key, and to §3.4's "exactly one value for each [parameter]" per implementation, is not said; nor whether a refused override (line 512) can be lifted by redeclaring instead of restarting.
- **Fix:** fix lowering §4.8 to "refused in every form (traits §4.9)". An open issue: the meaning of a redeclaration for existing kept values and compiled code.

### M16. `cs::Vector{Shape}` and `shapes::Iterable{Shape}` on an argument mean different things, and the contrast is drawn nowhere

- `writeup/reference/traits.md:954` (§7.2) and the §6.3 table (line 802): `cs::Vector{Column}` "takes a container of any of the three forms" (kept values only). `writeup/reference/traits.md:1118` (§8.3): `Iterable{Shape}` takes the user's `Vector{Circle}` or `Vector{Any}` as it is.
- A newcomer writes `total(shapes::Vector{Shape})`, passes a `Vector{Circle}`, and gets `MethodError`. Open issue §2 item 11 is about this, but the reference should say it, not the issue list.
- *Verified* by reading.
- **Fix:** one sentence in §8.2 and §7.2: "A container of a trait's name, `Vector{Shape}`, takes only containers of kept values; to take a user's container by its items, bound it by a collection trait, `Iterable{Shape}` ([§8.3](#83-a-users-container-taken-as-it-is))."

### M17. Extensions: an implementation that does not name its triggers is refused, a method that does not is followed

- `writeup/reference/traits.md:1185` (§10.1): an implementation in an extension must mention each trigger, else `ImplementError`. `:1232` (§10.3): an extension's method that wins without mentioning its triggers' types "is followed, as its parent package's change … It is not refused." And `:1183`: "An implementation is a method".
- Both are decided (`decisions.md:128`, the extension row; the trigger rule from rule 3), but the asymmetry is unexplained, and "an implementation is a method" invites the reader to apply §10.3 to implementations.
- *Verified* by reading; `TraitWorld/src/implement.jl:507-526` implements the refusal.
- **Fix:** one sentence after line 1185: "This is stricter than for an extension's ordinary methods ([§10.3](#103-strict-mode)): a method is followed as its parent's change, but whether a type conforms must not depend on which packages happen to be loaded."

---

## Low

### L1. Terms used before they are defined, and core developers' terms without a plain sentence
- "stakeholder": used at `traits.md:144` (§2), defined at `:1229` (§10.3). "key": used at `:397`, `:485`, `:660`, defined at `:870` (§6.7). Add "(defined in §10.3)" / "(§6.7)" at the first use, or a one-line definition there.
- "package image" (`:512`), "function barrier" (`:780`, `:890`): no plain sentence. "worker signature" (`:1301`, `check_fully_typed`): lowering's term in the language reference; say "a bounded function's signature".
- **Fix:** as above.

### L2. §10.1's prompt example does not illustrate its sentence
- `traits.md:1182`: "a trait module defined at the prompt does not own the prompt's types: an implementation of its trait for `Vector{Int}`, written at the prompt, is refused." `Vector{Int}` is Julia's type, not the prompt's; and the refusal there is Main's (it owns neither). **Fix:** "an implementation of its trait for a struct defined at the prompt, written inside the trait module, is refused; written at the prompt, it is accepted."

### L3. `delegate!(Core => Impl)` reads as Julia's `Core`
- `traits.md:1230`. **Fix:** `delegate!(CorePkg => ImplPkg)`, as `strict.jl:22` writes it (`StaticArraysCore => StaticArrays`).

### L4. "More bounds beat fewer" is not the rule the code applies
- `traits.md:615`. `check_bounds` (`trait_module.jl:1242`) orders by "carries every trait of the other"; `(A, B)` against `C` is unrelated, not fewer. **Fix:** "a bound that carries every trait of another beats it".

### L5. One refused conversion raises `ArgumentError`, every other `TraitBoundError`
- `traits.md:946` (§7.1): a trait object carrying another trait made into a kept value: `ArgumentError`. `:830` (§6.4), `:1159` (§9): `TraitBoundError`. `ArgumentError` is in no row of §9's table. **Fix:** one error type, and a row.

### L6. History wording inside deviation rows
- `traits.md:1488` (T-12): "The earlier spelling … is still accepted"; `:1491` (T-15): "messages about retired features". **Fix:** "A second spelling, with the receiver type as the trait's last parameter, is accepted"; "messages naming forms the design does not have".

### L7. Claims about other languages without a source
- `traits.md:998` (§7.4, Rust and Swift), `:1064` (§8.1, `core::iter`, `Sequence`), `:1100` (§8.2), `:1137` (§8.4, `Vec::retain`). CLAUDE.md: such claims cite primary sources or the research note. **Fix:** cite `design/other-languages.md` or `record/other-languages-research-2026-10-16.md`, or move the comparisons there.

### L8. §6.9 is labelled Optional but is "not part of the language"
- `traits.md:907`. The conventions' Optional means decided, built on demand; §6.9 is a direction (line 902). **Fix:** "Open" with a link to an open issue, or keep the direction in `design/alternatives.md` and one sentence here.

### L9. §15 conflates two things
- `traits.md:1373-1375`: "a second implementation of a trait for a type, used only where a caller names it" and the orphan case (a foreign trait for a foreign type). `Via{Fast}(x)` is a newtype, so it is an implementation for another type, not a second one for the same. **Fix:** two bullets.

### L10. "A cast of a value that has the attribute already returns it unchanged"
- `traits.md:828`: reads as if `compiled_for(d::Dynamic{X})` returned `d`. **Fix:** "that has that attribute already".

### L11. A loop at the prompt is compiled
- `traits.md:753`: "Julia does not compile a statement without a loop". Say the consequence: inside a `for` loop typed at the prompt, the types are known, so the values are `Compiled`.

### L12. A rule in a status line
- `traits.md:303` (§3.6 Status): "The agreement is checked against the type's own implementations; one by a family or a generic implementation is not the type's own." Move it to the bullets.

### L13. §10.2's status does not name T-56
- `traits.md:1217`: "Implemented", while T-56 (line 1532) says the refusal depends on the order of definitions. Other sections name their rows. **Fix:** "Implemented (T-56)".

### L14. Grammar loose ends
- `traits.md:52-114`: `Struct` is not reached from any production and `Statement` is undefined; `OpenResult` writes a bound as `Name "::" …`; `Concrete` on a `Method` is listed before `FullyTyped` in §11's example but after it in the grammar. **Fix:** `Statement ::= Trait | Implementation | Method | Struct | Expr`; order the prefixes one way.

### L15. `AbstractTypeError` against `NotFullyTypedError`
- `traits.md:1299`: "(an abstract value used)" against "(a call with unknown types)" does not tell a reader which one a given program raises. One sentence each with an example.

### L16. §3.1's example uses a form the rules do not offer; §8.1's table hides a qualified name
- `traits.md:186-187`: `Base.iterate(t::Iterable)::Union{Nothing, Tuple{eltype(Self), Any}}` puts a function call in a result type; §3.4 offers equations (`T = eltype(Self)`) and names only (`:267`); §8.1's own table writes `Tuple{T, Any}`. **Fix:** write the example with `T`.
- `traits.md:1071`: `HasLength`'s operation is written `length(c)::Int`; it is `Base.length`, an existing function (§3.1's qualified form), which §10.1 line 1186 restricts to types the declaring package owns. Say "`Base.length(c)::Int`".

---

## What the probes showed that the reference gets right (for the record)

- Two bounded methods of one trait at different fixed parameters are selected by the value's parameters (P1).
- `Kept{B}(x)` of a subtrait is accepted at a supertrait's bound from plain code (P8), as §3.6 implies; the supertrait's operation on it raises `MethodError` (T-72 confirmed on 4410407).
- `conforms`, the `getproperty` mapping rule, the extension-trigger check, the outside-module refusal, the hidden-attribute warning (item parameters excluded: `__tw_attrs__` holds bounds only), `@joint_owners`, `strict!`, `check_definitions` (raises, else returns `[]`), `@mutating` (T-13), the old `{R}` spelling in the workload (T-12), `project(t) = …` (T-15), and Base having no `length(::AbstractDict)` (§4.7) are as the reference says.

---

**Addendum (2026-10-26, filing).** The scripts this review cites as being in the same directory (`probe.jl`) are filed in `experiments/review-2026-10-26-references/`. What was done with each finding is recorded where it was done (a deviation row, an open issue, a commit).
