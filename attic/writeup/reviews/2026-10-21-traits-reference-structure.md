# Review: the traits reference, its level of abstraction and its structure

**Date:** 2026-10-21. **Reviewer:** a critical reviewer (Claude, Fable 5.1), independent of the authors of today's edits. **Status:** a review; not edited after today except by a dated addendum.

**Scope.** [`reference/traits.md`](../reference/traits.md) in its working-tree state (today's uncommitted edits for W-18 included), read against [`lowering.md`](../reference/lowering.md), [`compiler.md`](../reference/compiler.md), [`facts.md`](../reference/facts.md), [the conventions](../reference/README.md), [the glossary](../glossary.md), the decision rows on `Dynamic` and `Compiled` of 2026-10-20 and 2026-10-21 in [`record/decisions.md`](../record/decisions.md), [the plan](../plans/2026-10-21-values-carry-through-storage.md) and [the review](2026-10-21-values-carry-through-storage.md) of W-18. No Julia was run. Every finding is from reading; line numbers are those of the working tree.

**The user's request.** Two questions: where does the reference describe mechanism (receiver types, keys, trait objects as handles, erased keys, entries, workers, views, tables) instead of meaning; and can it be simpler and better structured now that `Compiled` and `Dynamic` are one design, with a section "how plain values enter the trait world" as a suggestion to explore.

**Severity.** *Major:* a contradiction with a decision or a sibling reference, or a structural fault that makes the rules hard to find. *Medium:* a leak of mechanism or encoding into a rule, or a stale statement. *Minor:* wording and terms.

---

## Findings, ranked

### F1 (major). §5 contradicts §15 and the decision log on compiling ahead

- §5 (`traits.md:365`): "In a package, compiling ahead may invalidate some plain code of the library's entry: accepted, to be reviewed (§15)."
- §15 (`traits.md:1113`): "No entry method is compiled ahead per declared type … So compiling ahead adds no method to the library's function, and invalidates no plain code."
- The decision log marks the row "An entry compiled ahead may invalidate plain code" as **history** since 2026-10-21 (`decisions.md:154`), and the row "`compiled_for` from an untyped caller through the table" says the entries compiled ahead per type are deleted (`decisions.md:88`).

§5's sentence is a stale copy of a retired decision, inside a reference. Cut it.

### F2 (major). `Dynamic{X}` has five meanings by position, no table says so, and one of them has no decided use

The spelling `Dynamic{X}` (and `Compiled{X}`) means, by where it is written:
1. on a bounded function's argument: a bound with a default attribute; it accepts any conforming value, and a value that carries keeps its attribute (`traits.md:586`, `:684`);
2. on an operation's argument: the concrete type; a value of the other attribute is refused (`traits.md:197`, `:697`);
3. on a struct field or a container's element type inside a trait module: `Kept{X}`, with the attribute as "the default for a value first seen there" (`traits.md:839`);
4. on a bound's item parameter: a default for plain items (`traits.md:587`, `:910–914`);
5. outside trait modules: the plain type; storing the other attribute is an error (`traits.md:644`, `:843`).

Three observations:
- No section states the five side by side. A reader meets each in a different chapter and must infer that the same spelling refuses in (2) and (5) but widens silently in (3).
- Reading (3) decides almost nothing, and what it would decide, lowering decides otherwise. A value stored from trait code carries its attribute, so a storage default can act only on a plain value: one assigned from plain code, which is Open (item 40; `traits.md:848`), or one trait code made itself and stores (a library's own `Circle()` into a `Kept{Shape}` field). For the second, lowering §13 says the store is `Kept{X}(x)`, which "takes the trait's default", and lowering §13.1's rewrite of `Dynamic{Column}[]` into a container of `Kept{Column}` records no attribute from the annotation. So, by reading lowering (the code is not checked here), the annotation's attribute in storage is not what decides today, and no L- row says so. Either a deviation row is missing, or the reading is not built because it is not needed.
- The user's rule, "types never cast", is applied as *refuse* in (2) and (5) and as *widen to `Kept{X}`* in (3). That is two behaviours under one principle.

**A simplification to put to the user.** Inside trait modules too, `Dynamic{X}` and `Compiled{X}` written on a field or an element type are the plain types (reading (5)), and a trait's name is the one spelling for "kept with its attribute". Then `Dynamic{X}` has one meaning in storage everywhere, "never casts" means one thing, reading (3) goes, and a plain value stored by trait code or by plain code takes what `Kept{X}(x)` already does (the trait's default, `traits.md:832`; lowering §13), which also answers item 40 as its option (a). The attribute on a *bound* (readings 1 and 4) stays, since there it has a decided use. This is a design question, not a documentation fix; recorded here for the user, not decided.

### F3 (major). The attribute rules have no one home

The rule the user stated in three sentences is spread over thirteen places, several of which restate a part of it:

| Rule | Stated in |
|---|---|
| where a plain value is first seen; `Compiled` if the type is known | §3.8 (`:327`, "at a bound" only), §6.1 (`:586`), §6.6 (`:671–677`), §10.2 (`:908`), §10.3 (`:932`), §10.5 (`:982`), §15 (`:1111`) |
| the trait's default `@dynamic`, and "of the trait world" | §3.8 (`:327–331`), §6.6 (`:679`), §9 (`:767`, `:770`), §10 (`:832`) |
| only `compiled_for`/`with_dynamic` cast; constructors keep; types never cast | §3.1 (`:197`), §6.6 (`:685`, `:697`), §10 (`:834`, `:839`, `:843`), §10.3 (`:942`) |
| a `Compiled` value at a bound is opened by its type, once; a `Dynamic` runs the code compiled once | §6.6 (`:680`, `:688`), §10 (`:827`), §10.5 (`:980`), §3.7 (`:308`) |
| the cost of an operation on a `Dynamic` value: four, then a table | §6.6 (`:693`), §10 (`:824`), §10 status (`:857`) |
| printing of the kept forms | §10 (`:846`), §14 (`:1097`) |

Two of the copies disagree with the fuller statement:
- §3.8 says `@dynamic` applies "at a bound"; §10 (`:832`) and lowering §13.2 apply it at `Kept{X}(x)` and at a bounded struct parameter too.
- §6.6's list of where a value is first seen (`:671`) omits the constructors from a plain value (`Dynamic{X}(x)`, `Compiled{X}(x)`, `Kept{X}(x)`, §10 `:832`) and the Open case of assignment from plain code (§10 `:848`).

The cause is structural: the chapters are cut by syntactic category (a bound in §6, storage in §10, functions in §9, items in §10.2–§10.3, struct parameters in §10.5), so each category restates the rule for its case. The remedy is a chapter cut by the rule, with one table of the positions where a plain value enters and one table of what each spelling means by position (F2). The proposal in the second part does this.

### F4 (major). Mechanism in the body, with a disposition for each

The reference's own contract is "the rules, as user code sees them" (`traits.md:3`; README: "A rule a user can observe belongs to `traits.md`. How it is achieved belongs to `lowering.md`"). The table lists each place where the body describes how, says whether lowering already holds it, and what to write instead.

| Where | Excerpt | Lowering holds it? | Disposition |
|---|---|---|---|
| front matter `:7` | terms listed: "entry, worker" | — | drop both from the list |
| §2 `:143` | "compiles … in its *facts mode* … the bodies of its bounded functions (the *workers*) … The small *entries* … are compiled in the caller's mode" | facts §6, lowering §2 | keep one observable sentence: loading another package cannot discard a trait module's compiled code; link facts.md |
| §3.3 `:232` | "a stored type exactly equal to the one the key records" | lowering §5 | "exactly the declared type, as matched at the implementation" |
| §3.5 `:274` | "`Self` is the receiver type of the implementation at hand" | — | restate, F5 |
| §3.7 `:307–313` | "a key may be abstract", "an abstract part of a key is compiled as it is", "an erased key is erased by choice" | lowering §5 | state it on what the user wrote: a declared field's type or a forwarded field's type that is abstract; "a `Dynamic` value is never an abstract key: it is a choice" |
| §4 `:337–353` | the key's structure: receiver type plus field types; the erased key; tuples of keys | lowering §5 | keep, as the *sharing rule* of `Compiled` code (what a library author must know, below), placed under the values chapter; "erased key" becomes "`Dynamic` values of one trait share one compiled copy per position" |
| §5 `:365` | "the library's entry" | — | cut (F1) |
| §6.2 `:598` | "A bounded function has two parts … Its **entry** … Its **worker** …" | lowering §8, whole | cut; the glossary's "Entry and worker" then points to lowering §8 |
| §6.5 `:638` | "A value caught by a typed method is not translated" | lowering §8.2 | "is not seen through a trait" |
| §6.5 `:642–643` | "An untyped method of the same shape, defined after the bounded ones"; "where it has no entry of that shape" | lowering §8.1, §8.3 (the encoding L-3) | F7 |
| §6.6 `:693` | "a call-site split over the first four … a table keyed by the value's type … registered when the calling code was compiled: code compiled into a package image covers …" | lowering §13, compiler §4.2–§4.3 | keep the user-visible part in one place: the first four implementations declared take the fastest path; beyond them the cost does not grow with the number of implementations; which four is fixed when the calling code is compiled. Drop "split", "table", "registered", the image clause |
| §8 `:735`, `:738` | "after the arguments are translated"; "translates and refuses" | lowering §10 | "after each value is seen through its bound" |
| §9 `:768`, `:785` | "an indirect call to the function's code compiled for `A`"; "erased to a pointer" | lowering §12 | "the library's code is compiled once per signature" / "per function"; no pointers |
| §9 `:795` | "A dynamic call takes at most six arguments." | lowering §12 (`_CallWrap`, "fixed arities up to six") | an implementation limit written as a rule of the design: a deviation row, or a lowering fact; not a rule of the language |
| §9 `:797` | "have an entry of their own" | lowering §8 | "are bounded functions" |
| §10 `:822` | "one at its key is `Compiled`, one at the erased key `Dynamic`" | lowering §13 | cut: §6.6 says it without keys |
| §10 `:824`, `:857` | "A fast path covers up to four"; "Beyond the four inlined implementations" | lowering §13 | one home (the cost line above); "inlined" goes (F9) |
| §10.3 `:917`, `:932` | "its entry translates it by the bound" | lowering §13.1 | "it is seen through its bound as every argument is" |
| §10.3 `:936` | "What the container crosses as is a view of BaseTraits: `DynamicItems{X}(v)` … `CompiledItems{X}(v)`, `CompiledValues{X}(d)`" | lowering §13.1, the table of views | keep only `DynamicItems{X}(v)` and `DynamicValues{X}(d)` in their public role, the explicit copy (open issues item 37); drop `CompiledItems`/`CompiledValues` and "what it crosses as" from the body and the status index (`:1231`) |
| §11 `:1007`, `:1010` | "a call, at the entry"; "a worker's first call" | lowering §14 | "a call"; "a bounded function's first call at a signature" |
| §13 `:1087` | "warns at a worker's first run" | lowering §14 | "at a bounded function's first run" |
| §14 `:1095` | "prints at its erased key" | — | the printed form `ColTable at Dynamic` is observable and stays; the term goes |
| §15 `:1113` | "No entry method is compiled ahead per declared type" | lowering §15.1 | "compiling ahead adds no method to the library's functions" |
| §19 T-35 | "whose views hold only its parts" | lowering §6 | restate in user terms: an immutable value kept by its parts, not whole |

Not mechanism, and to keep: file-and-line references appear only in the Deviations table, which the conventions require (`README.md:41`); `verify_main`, `@workload`, `JULIA_TW_AHEAD`, `check_definitions`, `fully_typed`, `conforms` are user-facing tools.

**What a library author must know, and why.** Three things in this list are a performance model the user needs, not an implementer's detail, and should stay in user terms:
- the attribute, and that it chooses speed never results (§6.6);
- which types share compiled code: a type that forwards shares the code of the field's type; a type with its own methods gets a copy; fields the trait does not declare never cause a recompile; an abstract declared field means one copy with dispatch inside. A library author predicts compile times, image coverage and what a new user type costs from this, and printed types show it (`ColTable at Vector{Vector{Float64}}`). That is §4, kept as "what `Compiled` code is compiled for";
- the cost shape of an operation on a `Dynamic` value (four, then constant), because the user chooses `Dynamic` positions by it. The number four is part of the design (`README.md:44`).

Everything else in the table (modes, entries, workers, views, pointers, tables, registration, images) is how, and lowering already holds all of it.

### F5 (medium). `Self` is defined by the receiver type, and the receiver type appears in ten places

- §3.5 (`traits.md:274`): "In a trait's body, `Self` is the receiver type of the implementation at hand." Then, as a patch for the case the definition does not cover: "On a `Dynamic` value, a constructor operation returns a `Dynamic` of the same implementation" (`:277`).
- "receiver type" also at `:7`, `:200`, `:243`, `:343–353`, `:423`, `:528`, `:712`, and T-11.
- The decision of 2026-10-20 (`decisions.md:79`): "these rules can be given without talking about receiver types at all. Receiver types are an optimization in `Compiled{X}` to reduce the amount of things f2 actually recompiles for using the trait information." The term itself is the user's (2026-10-19, `decisions.md:174`); the question is where it belongs.

**Restate `Self` as the user sees it:** `Self` is the type of the value seen through the trait. By the type's own methods, that is the conforming type; with `by f`, the field's type. An operation declared `::Self` returns a value like the one seen, in the form the caller passed: the value itself for a `Compiled` one, a `Dynamic` of the new value for a `Dynamic` one (lowering §13: "of the receiver's form and attribute"). That covers §3.5's patch and T-49 without a second notion.

**Confine "receiver type"** to two places: §5.3 (`by`: the operations are those of the field's type) and the sharing rule (§4 as kept). Elsewhere say "the type the operations are called on" or `Self`: in §3.1's check (`:200`), §5.9's completeness (`:528`), §7's `Like` (`:712`), and the comment at `:243` ("an equation of `Self`").

### F6 (medium). Stale after today's edit: nine places

1. §16, the table row "Values" (`traits.md:1144`): "a field or a container of the trait holds it as `Dynamic{X}`" — today it is `Kept{X}` (`:839`).
2. §14 (`:1097`): "A `Dynamic` value prints as … `Dynamic{Shape} at Circle`" — one of three forms; §10 (`:846`) has all three. One home: §14.
3. §18, status index (`:1184`): "an operation's argument declared `Dynamic{Y}`: a trait object converted" — §3.1 now says kept, or refused.
4. §6.3, the table (`:610–611`): "keep it beyond the call as a `Dynamic{X}`" and "convert it" — a `Compiled` trait object kept stays `Compiled`; the word is now "cast".
5. §6.6's example (`:663–665`) labels items `Compiled{Mark}` and `Dynamic{Mark}`, the types, where the worker sees a trait object; §10.2's table was changed today to the bare attributes. One labelling.
6. §1, the grammar (`:101–102`): `DynamicType` has no `Compiled{X}` and no `Kept{X}`; `Conversion` is the retired word; the bounded struct parameter of §10.5 has no production.
7. "conversion"/"convert" for the casts remains at `:102`, `:611`, `:696`, `:771`, `:853`, `:1184`, `:1216`; §6.6 and the glossary say "cast".
8. §10's status (`:853`): "Planned: the conversion of a plain value on assignment … (open issues, item 40)" — the body (`:848`) and item 40 say Open. Planned means decided (`README.md:28`).
9. §3.5 (`:277`) and §7 (`:718`) speak of a `Dynamic` input only; lowering §11 and §13 return "the input's form and attribute" for any kept form. Say "a kept value gives a kept value of the same form and attribute".

Also stale, from before today: the Deviations header names TraitWorld 227781a (`:1255`) while `state.md` names 1d09112 and rows T-37 to T-50 cite branches and no lines.

### F7 (medium). An encoding of lowering is written as a rule of dispatch

§6.5 (`traits.md:642–643`): "An untyped method of the same shape, defined after the bounded ones, serves as such a fallback" and "Only the package that defines a function … may add a bounded method to it where it has no entry of that shape."

- "shape" and "entry" are lowering's words (lowering §8.1: an entry per shape, the pattern of annotated positions).
- "defined after" is a consequence of the encoding: an untyped method has the entry's signature, so TraitWorld rewrites a later one into the fallback (lowering §8.1, `f(::Untyped, args…)`). In the intended design, where a trait bound is a dispatch tier and entries are generated by the compiler (L-3, lowering §17), order does not matter.
- "where it has no entry of that shape" is the same: the entry is a method at `Any`, which only the function's owner may add (lowering §8.3). The user-level rule is ownership alone: a package may add a bounded method to a function it owns, or to another's function where it owns a trait in the bound. The qualification belongs to L-3's row, as what the encoding requires today.

### F8 (medium). The warning on attributes of non-public functions: a wrong reason, and the section's own example trips it

- §6.6 (`traits.md:696`): "An attribute on a function that is neither exported nor declared `public` warns at the trait module's end: **no plain value crosses there**."
- The reason is false: plain code calls any function by its qualified name. §6.6's own example does it: `single(io, d::Dot) = Plots.paint(io, d)` (`:665`), and `Plots` exports nothing.
- So by the rule as written, `render_all(io, ms::Iterable{Compiled{Mark}})` (`:658`) and `paint_once(io, m::Dynamic{Mark})` (`:660`) warn at the end of the example module. The reference's example is not clean under its own rule.

The decision is the user's ("It would be easy to assume it achieves something that it doesn't", `decisions.md:82`) and stands. Fix the reason: a plain caller is expected only at public functions; inside the module values already carry, so the annotation decides nothing there. And add `public render_all, paint_once` to the example, or drop the attributes from it.

### F9 (minor). "Never promise inlining"

§10's status (`traits.md:857`): "Beyond the four inlined implementations". The writing rule in CLAUDE.md forbids promising inlining; the glossary hedges ("each a direct call that can inline"). Write "the four implementations of the fastest path".

### F10 (minor). Terms: a collision, an undefined term, and gaps in the glossary

- **"held value"** (`traits.md:686`, `:833`, `:853`, `:858`, `:940`, `:1231–1232`; lowering's `HeldValue{X}`) against the glossary's **"held view"** (an immutable value held whole in a view, a lowering concept). Two terms one word apart for different things; "held value" is in no glossary entry. The plan says "the forms of a trait-world value"; §10 says "three forms"; §9 says "Functions kept". One term: **kept value** (it matches `Kept{X}`, "kept where the code does not know its type", "Functions kept"), defined once in the storage chapter, with a glossary entry; "held view" stays lowering's.
- **"crosses", "the crossing"** (`traits.md:917–944`, the status index `:1230`): a project term, defined nowhere, indexed nowhere. Either define it where it first matters (§10.3) and index it, or say "is taken as it is".
- **"of the trait world"** (a type defined in Julia, TraitWorld or a trait module, all the way down; `traits.md:328`) carries a rule and is used in §6.6 and §9; the glossary mentions it once in passing. It needs an entry.
- **bundle** (§3.6), **joint family** (§5.7), **sibling** (§7) are defined in the reference and absent from the glossary's index; the conventions say the glossary links to where a reference defines a term.
- The glossary's **"Trait object"** entry says "seen through the offsets of what the bound can see": offsets are lowering. The reference's own wording, "the user's own object, seen through the bound" (`:594`), is the right level.

### F11 (minor). Two overclaims in "Choosing, for library authors"

- `traits.md:692`: "`Dynamic` positions suit large code … a new implementation compiles nothing in the library." With values carrying and casts winning, a caller that passes `compiled_for(m)` or a trait-world `Compiled` value compiles the library per key at that position. True for plain values from outside; say so.
- `traits.md:696`: see F8.

---

## The proposed outline

The principle: chapters by rule, not by syntactic category, for the part of the language that is about values; one table where one spelling has several readings; the performance model (keys, costs) in one subsection of the values chapter; everything "how" out. The user's suggested section is adopted, in a wider form, as the core of chapter 6: the five entry points and the three sentences of the rule are one subject, and today each syntactic category restates them. It simplifies because it replaces six statements of "never casts", three of "four", and five partial lists of "first seen" by one each. It is not adopted as a narrow section on plain values only, because carrying and casts are the other two sentences of the same rule and would otherwise stay scattered.

For each section: what it contains, and where the current content goes (kept, moved to lowering, merged, cut).

1. **Syntax summary.** As now, plus `Compiled{X}`, `Kept{X}` as value types, `Cast` for `Conversion`, a production for a bounded struct parameter (F6.6). Kept.
2. **Trait modules.** As now, minus the mode and entry/worker sentence (`:143`), replaced by one observable sentence with a link to facts.md. Kept.
3. **Trait declarations.** 3.1 operations (the argument-type rule links to 6.3's table instead of stating it); 3.2 defaults; 3.3 fields (`:232` restated); 3.4 parameters; 3.5 `Self` restated (F5); 3.6 supertraits and bundles. **Moved out:** 3.7 concreteness to chapter 11 (it is the per-trait half of concrete mode, and the planned one declaration with a level covers both, `:314`, `:1089`); 3.8 `@dynamic` to 6.3 (a body item stays listed in 3's syntax with a link).
4. **Implementations.** 5.1–5.10 as now, renumbered; `by` says "the operations are those of the field's type; `Self` is that type; its compiled code is shared (6.7)"; the stale sentence at `:365` cut (F1); the receiver type confined to 5.3 (F5).
5. **Bounded functions.** 5.1 bounds (syntax of attributes, with a link to 6.3); 5.2 what a bounded function receives: the value seen through the trait (the trait object), `Compiled` or `Dynamic` with the same results, nothing copied; the entry/worker paragraph moved to lowering §8 (already there); 5.3 what trait code may do (the table, rows at `:610–611` updated); 5.4 internal functions; 5.5 dispatch, stated as ownership, the encoding to L-3 (F7); 5.6 results: `Like`, `withfields`, siblings (merged from §7); 5.7 keywords, defaults, varargs (merged from §8, "translated" removed); 5.8 `Callable` as a bound: the signature, the checks, several signatures, the constant `A`, open result types, bounded closures (from §9's first half; "pointer" and "indirect call" out, the six-argument limit to a deviation row or lowering).
6. **Values in trait code: `Compiled` and `Dynamic`** (the new home; from §6.6, §3.8, §4, parts of §9, §10, §10.2, §10.3, §10.5).
   - 6.1 The attribute: what each means, speed never results, the three sentences of the user's rule.
   - 6.2 **How plain values enter the trait world:** one table of the positions where a plain value is first seen (a bound, including `Callable`; an item of a container at an item position, when read; a struct parameter bounded by a trait, at its constructor; an operation's result declared with a trait; a constructor `Kept{X}(x)`/`Dynamic{X}(x)`/`Compiled{X}(x)` from a plain value; assignment from plain code: Open, item 40), and the first-seen rule: `Compiled` if the code that sees it knows the concrete type, else `Dynamic`; the prompt and calls dispatched at run time.
   - 6.3 Defaults: the trait's `@dynamic` and "of the trait world" (from §3.8); an attribute at a position. **One table of what `X`, `Compiled{X}`, `Dynamic{X}`, `Kept{X}` mean by position** (F2): a bounded argument, a bound's item parameter, an operation's argument, a struct field or element type inside a trait module, a struct parameter's bound, outside trait modules. The order of overrides, once.
   - 6.4 Casts: `compiled_for`, `with_dynamic`; the later wins; constructors keep; types never cast; a `Dynamic` is never opened implicitly. One statement.
   - 6.5 Values carry: through calls, bounds and storage; library to library; up to plain code and back.
   - 6.6 Items of a user's container: the table of §10.2 (plain items by the position's attribute, carrying items their own), and that a container is taken as it is, each item seen when read; writes store what reads back the same. The rules of §10.3 on which containers and item types are taken, without view names (F4).
   - 6.7 **What `Compiled` code is compiled for** (from §4): the sharing rule; the receiver type and the declared fields' types; types with equal keys share, a type with its own methods gets a copy, undeclared fields never recompile; a `Dynamic` value shares one copy per position; several arguments. Status as now.
   - 6.8 Costs and choosing: the one statement of the cost shape (four, then constant), when `Compiled` items pay, when `Dynamic` positions pay (F11 corrected); a link to the evidence.
7. **Kept values: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`** (from §10's core, §9's "Functions kept", §10.5). 7.1 the three forms, what they hold, operations and fields on them, parameters fixed, up and down (constructors link to 6.4, not restate). 7.2 a trait's name as a storage type, inside and outside trait modules, in an argument's type; with traits in the type system. 7.3 assignment from plain code (Open, item 40). 7.4 a struct parameter bounded by a trait (§10.5 as is). 7.5 functions kept (from §9: the three forms at a signature; the same function at another signature; at a bounded parameter). 7.6 equality, hashing, the limit on inference through a cast. Printing stays in chapter 12. The term "kept value" defined here (F10).
8. **Collections** (from §10.1–§10.4): 8.1 BaseTraits; 8.2 item positions (the syntax; the attribute table lives in 6.6); 8.3 the explicit copy `DynamicItems{X}(v)`, `DynamicValues{X}(d)`, and `collect` as the check-before-start; 8.4 algorithms, `retain!`.
9. **Checks, and when they run** (§11; "entry" and "worker" out of the table).
10. **Who may implement; pirates; strict mode** (§12, as is).
11. **Concreteness and concrete mode** (§3.7 merged with §13): per trait, per function, per module; the planned one declaration with a level; `fully_typed`; "worker" out.
12. **Printing** (§14, now the one home: trait objects, kept values in their three forms, `Callable`; "erased key" out).
13. **Compiling ahead** (§15; "entry method" out).
14. **Membership** (§16; the row "Values" updated).
15. **Named implementations** (§17).
16. **Status index**, rebuilt to the new sections (rows `:1184`, `:1231` corrected).
17. **Deviations**, as is, with T-35 restated and the header's commit updated.

What the outline cuts outright: §6.2's entry/worker paragraph, §10 `:822`, §5 `:365`, "what the container crosses as", the duplicated printing, cost and "never casts" sentences. What it moves to lowering: nothing that lowering does not already hold, except the six-argument limit and L-3's order requirement, which need a row each.

---

## Verdict

The reference is right in substance on the design in force: the three sentences of the user's rule are there, the kept forms are there, and nothing in it contradicts the decision log except one stale sentence (F1). Its faults are of level and structure. It states the attribute rule in thirteen places cut by syntax, so the same spelling has five readings that no table shows (F2, F3); it describes entries, workers, erased keys, views, pointers and tables where lowering already does (F4); and it defines `Self` through the receiver type where the user wants the value seen through the trait (F5). Today's edit left nine stale spots (F6).

Adopt the user's section, widened to a chapter on values (6), with the position table (6.3) and the entry-point table (6.2) as its spine; put keys under it as the sharing rule; keep the four-then-constant cost line and the sharing rule as the performance model a library author needs, and move nothing else "how" into the body. Put F2's simplification to the user: it would give `Dynamic{X}` one meaning in storage and make "types never cast" one behaviour.
