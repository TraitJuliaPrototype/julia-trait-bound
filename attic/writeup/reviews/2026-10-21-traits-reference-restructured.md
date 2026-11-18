# Review: the restructured traits reference (W-20)

**Date:** 2026-10-21. **Reviewer:** a critical reviewer (Claude, Fable 5.1), independent of the author of the restructuring. **Status:** a review; not edited after today except by a dated addendum.

**Scope.** [`reference/traits.md`](../reference/traits.md) in its working-tree state after W-20, read against its previous version (`git show HEAD:writeup/reference/traits.md`), [the structure review](2026-10-21-traits-reference-structure.md) it follows (F1–F11 and the outline), [the conventions](../reference/README.md), [`lowering.md`](../reference/lowering.md), [`facts.md`](../reference/facts.md), [the glossary](../glossary.md), the decision rows on `Dynamic` and `Compiled` of 2026-10-20 and 2026-10-21 in [`record/decisions.md`](../record/decisions.md), and TraitWorld's working tree (`src/trait_module.jl`, `core.jl`, `attributes.jl`, `entry.jl`, `trait.jl`, `test/attributes.jl`). No Julia was run. Every statement about the code is from reading and is marked so. Line numbers are those of the working tree.

**The user's decision since the structure review:** inside a trait module, `Dynamic{X}` and `Compiled{X}` written as a field's or element type are the plain types; a trait's name is the one kept form (`Kept{X}`). The user's rule: "Values carry. Annotations provide defaults when a plain value enters trait code. Explicit casts always win."

**Severity.** *Major:* a contradiction with a decision, a sibling reference or the code on a rule a user sees. *Medium:* a wrong or incomplete rule, a stale statement, or a contradiction inside the document. *Minor:* wording, terms, duplication.

---

## 1. The findings of the structure review, one by one

| Finding | Addressed? | Where | Remaining |
|---|---|---|---|
| F1 §5 contradicts §15 on compiling ahead | yes | the stale sentence cut from §4 (`:312`); §13 restated (`:1197`) | — |
| F2 five readings of `Dynamic{X}`, no table | yes, with the user's answer | the table by position in §6.3 (`:755–764`); §7.2 (`:892–893`) | the table is wrong in two columns and incomplete in one (R2); the "outside trait modules" cell states the encoding, not the design (R7) |
| F3 the attribute rules have no one home | yes | chapter 6 (`:672–848`) | three short restatements remain (R11) |
| F4 mechanism in the body | yes, nearly all | entries, workers, erased keys, views, pointers, "translated", "crosses", "inlined" are gone from the body; T-51 added; L-3 carries the order requirement; T-35 restated | "erased by choice" twice (`:769`, `:1165`); "views" in §8.3 (`:1040`); T-39's "crosses", "translated" and T-49's "receiver type" in the Deviations table (R17) |
| F5 `Self` defined by the receiver type | yes | §3.5 (`:278`); "receiver type" confined to §4.3 and §6.7 | the implementation served by defaults alone falls between §3.5's two cases (R13) |
| F6 nine stale spots after W-18 | the nine: yes | §14's row, §12 as the one home of printing, the status index row, §5.3's table, the example's labels, the grammar, "cast" for "convert", §7.3 Implemented, "same form and attribute" | the two "also stale" items are not done: the Deviations header's commit and the rows without lines (R10) |
| F7 an encoding written as a rule of dispatch | yes | §5.5 states ownership (`:589`); L-3's row holds the order requirement | — |
| F8 the warning's reason is false, the example trips it | yes, in part | §6.3 (`:767`); `public` added to the example (`:690`) | the new reason is still not exactly true, and the code's message keeps the old reason (R8) |
| F9 "inlined" | yes | `:840` | — |
| F10 terms | yes | "kept value" defined (`:868`) and in the glossary; "held value" and "crosses" gone; "of the trait world", bundle, joint family, sibling in the glossary; "Trait object" without offsets | "plain value" is defined at `:707` and absent from the glossary; the glossary's "Receiver type" points to §6.7 where §4.3 defines it (R17) |
| F11 two overclaims in "Choosing" | yes | §6.8 (`:844`) | — |

---

## 2. Findings, ranked

### R1 (major, a change in flight). The trait's default: the reference still says `@dynamic`, the code refuses it, and the new third default is not yet in the reference

*Context, told to me by the coordinator while I reviewed:* the main agent renamed `@dynamic` to `@default_with_dynamic_self` in the code, added `@default_compiled_for_self`, and is about to change §6.3. So this is not an unrecorded drift. What follows is what the document under review says, and what the pending edit must cover.

**As the document stands.**
- `traits.md` says `@dynamic`: the grammar (`:67`), §3 (`:177`), §6.3's example and text (`:733–743`), §5.8 (`:654`), the status index (`:1297`).
- TraitWorld's working tree (uncommitted, on top of 804b662) accepts `@default_with_dynamic_self` and `@default_compiled_for_self`, and **refuses `@dynamic` with an error**: `trait.jl:202–206`; `test/attributes.jl:195–208` tests that refusal.
- In the same working tree, [`lowering.md` §3](../reference/lowering.md#3-trait-declarations), [the glossary](../glossary.md) (index and the entry "`Compiled` and `Dynamic`"), [`open-issues.md`](../open-issues.md) (closed item 15) and [`design/other-languages.md`](../design/other-languages.md) (`:223`) already say `@default_with_dynamic_self`.
- The decision log has no row for the new spelling or the new default. Its row of 2026-10-20 says `@dynamic`, with the user's words.
- The third default, `@default_compiled_for_self` (`:compiled`), makes a plain value `Compiled` whatever the caller knew (`attributes.jl`, `_enters_dynamic`: `d === :compiled && return false`; `entry.jl:834`, `_kept_at`); an untyped caller's value then takes the table (§6.8). The reference describes neither its spelling nor its meaning.

**What the pending edit of §6.3 must cover,** checked against the code as read and the coordinator's description of the choices:
1. The grammar's `TraitItem` line (`:67`), §3 (`:177`), §5.8 (`:654`: "`Callable` declares `@dynamic`") and the status index (`:1297`): the new spellings, in every copy.
2. The order (`:747–751`): a trait's `Compiled` default sits where the `Dynamic` one does, below an annotation and a cast.
3. The two choices, stated as rules and logged as "mine" with a line in `open-issues.md` §1: the `Compiled` default applies to every plain value, the `Dynamic` default keeps the trait-world exemption (`:741`); where the traits at one position declare different defaults, neither applies and the first-seen rule decides (`_traits_default`, `attributes.jl`). The second is a new rule for several bounds at one position (§5.1) and belongs in §6.3 with a pointer from §5.1.
4. §6.2's bullet on constructors (`:723`, R3): with a `Compiled` default, "unless the trait's default says otherwise" now cuts both ways; the two precise sentences recommended under R3 take the default in both directions without change.
5. The item table of §6.6 (`:804–808`) **assumes a trait without a default and does not say so.** This is wrong already for `@dynamic`: by §6.3 (`:740`) and by `BaseTraits.jl:324` (`d === :dynamic && !(isconcretetype(E) && from_trait_world(E))`), the items of a `Vector{Circle}` under `Iterable{Shape}` are `Dynamic` when `Shape` declares the `Dynamic` default and `Circle` is not of the trait world; the table's first row says `Compiled`. With the `Compiled` default, the first row's second column becomes `Compiled` too. One sentence above the table ("for a trait without a default; a trait's default applies to a plain item as at a bound, §6.3"), or a row per default.
6. R5 below bears on choice 3: as read, `Kept{X}(x)` applies the `Dynamic` default without the trait-world exemption (`core.jl:584–586`), where the entry, the bounded struct's constructor and the item read apply it. The coordinator's description ("the `Dynamic` default keeps its trait-world exemption") is then not what `Kept{X}(x)` does, unless the pending change touches `core.jl`, which the list of files does not name.
7. §13 (`:1196`): "A caller that does not know the argument's type passes a `Dynamic` value … and compiles nothing per type" is no longer true at a bound of a trait with the `Compiled` default (the table, per key). Add "unless the trait's default or an annotation says `Compiled`".

**Recommendation.** One commit: the reference (the seven points), a decision row quoting the user's words for the rename and marked "mine" for the two choices, the open-issues §1 line, and the glossary's index entry. No T- row is needed once the reference says the new spelling, since the old one is then refused cleanly.

### R2 (major). The table "What each spelling means, by position" is wrong in two columns and incomplete in one

The table (`:757–761`) and its bullet (`:763`): "'The type' holds kept values of that form. A value of the other attribute passed or stored there is refused with `TraitBoundError` naming the cast: a type never casts. `Kept{X}` takes either attribute."

By reading the code:
- **On a bounded function's argument, `k::Kept{X}` is a plain Julia method.** `_dyn_arg` sends `Kept{X}` to `_dyn_type`, which returns it unchanged (`_iskepttype`, `trait_module.jl:265–268`, `:315–318`); `_classify` sees no bound. So a `Dynamic{X}` value, a `Compiled{X}` value or a trait object passed there is refused by Julia's `MethodError`: not accepted ("takes either attribute"), and not "refused with `TraitBoundError` naming the cast". The form that takes either attribute on an argument is the bound `k::X`.
- **On an operation's argument,** only a trait object of the other attribute reaches the constructor and its `TraitBoundError` (`_seams`, `attributes.jl:123–145`). A kept value of another form (a `Kept{Y}` where `Dynamic{Y}` is declared) fails the argument check and raises `TraitArgumentError` (`core.jl:1028`).
- **A column is missing:** a trait's name as a parameter of a plain type in an argument (`cs::Vector{Column}`). §7.2 (`:894`) says it takes a container of any of the three forms, and the code rewrites it to `Vector{<:HeldValue{Column}}`. The table's nearest column, "as a field's or element type", says `Kept{X}`, which would be wrong there.
- **"—" has no legend.** For `X` on an operation's argument it hides the receiver, which is exactly that (`:194`). For `Compiled{X}` as a struct parameter's bound it means "plain Julia's bound". For `Kept{X}` as an item parameter it means "not offered", but the code does not refuse it: `_item_param` rewrites `Iterable{Kept{Shape}}` to `Iterable{Kept{Through{Shape, :default}}}` (`trait_module.jl:335–345`), a form with no meaning. Unverified by running.

**Recommendation.** Keep the table; it is the right spine. Give "—" a legend. Split the bullet "the type" by column: in storage, a value of that form or one converted by storing (a trait object, a kept value of the matching attribute; the other attribute `TraitBoundError`); on an operation's argument, a trait object converted the same way, anything else by Julia's dispatch; on a bounded function's argument, Julia's dispatch only, and the bound `k::X` is the way to take either attribute. Add the argument-parameter column, or a footnote with §7.2's sentence. Name the receiver in the operation column. A row for `Iterable{Kept{X}}`: refused, or a T- row.

### R3 (major). §6.2 contradicts §7.4 and lowering on a constructor

- §6.2 (`:723`): "A constructor and an assignment always know the value's type, so a plain value stored or made there is `Compiled`, unless the trait's default says otherwise."
- §7.4 (`:931`): a bounded struct's constructor is "a position where a cast, the value's carried attribute, or the first-seen rule decides". Lowering §13.2 and `_kept_at` (`entry.jl:822–836`) apply `Compiler.known_type`: a plain value from a caller that does not know its type is `Dynamic` there. §6.2's table lists that constructor as an entry point (`:713`).
- The reason given is false by the section's own account of the prompt (`:722`): a statement typed at the prompt knows no types, and `Kept{Shape}(Circle())` there is `Compiled` not because the type is known but because `Kept{X}(x)` takes the trait's default regardless (`core.jl:584–586`).
- The previous version said the precise thing (old §10: "the trait's default: `Dynamic` under `@dynamic`, else `Compiled`"). The restructuring replaced a rule by a rationalization that contradicts another section.

**Recommendation.** Two sentences: "`Kept{X}(x)` and a store into a field or container of a trait's name take the trait's default, whoever calls (`Compiled` unless the trait declares otherwise). A struct parameter bounded by a trait is a bound: its constructor applies the first-seen rule as a bounded function does (§7.4)."

### R4 (medium). §2 overclaims what loading another package cannot do

§2 (`:147`): "**Loading another package never discards a trait module's compiled code,** except a change by a stakeholder of code it depends on."

- [Facts G2](../reference/facts.md#g2): a CodeInstance compiled by facts is invalidated by a definition that changes dispatch at one of its facts, which "is a stakeholder's, or a pirate's that wins there".
- §10.2 (`:1115`): a pirate in plain code "is followed by default … Trait code it changes is compiled again once".
- §10.3 (`:1127`) gives the "never" to strict mode: "The property it secures: trait code is never invalidated, except by a change of code it depends on, a stakeholder's."

The exception list reads as exhaustive and omits the case the design spends a whole mode on. The old §2 had the overclaim too, unbolded and without the exception list; the new sentence makes it a rule.

**Recommendation.** "… except a change by a stakeholder of code it depends on, or a pirate that wins there; strict mode refuses the pirate (§10.3)."

### R5 (medium). `Kept{X}(x)` applies the trait's `Dynamic` default to values of the trait world too (by reading)

- §6.3 (`:741`): the trait's default "applies to values whose type is not of the trait world".
- The entry checks it (`_enters_dynamic`, `attributes.jl:241`), the bounded struct's constructor checks it (`_kept_at`, `entry.jl:834`), an item read checks it (`BaseTraits.jl:324`).
- `Kept{X}(x)` does not: `compiled = default_attribute(_family_of(X)) !== :dynamic` (`core.jl:584–586`), and `convert(::Type{Kept{X}}, x)` calls it (`core.jl:590`). So a library's own value of a `Dynamic`-default trait, stored into a field of the trait's name (`push!(s.hooks, LibraryHook())`), is `Dynamic`, where the reference says `Compiled`.

Not run; the reading is of six lines. **Recommendation.** A T- row, or the one-line fix in `Kept{X}(x)`.

### R6 (medium). §6.4's sentence on casts of kept values contradicts its own example

§6.4 (`:784`): "On a kept value, it gives a kept value of the same form with the other attribute where the form allows it (`compiled_for(d)` of a `Dynamic{X}` is a `Compiled{X}`)." A `Compiled{X}` is not the same form as a `Dynamic{X}`. The code (`attributes.jl:160–171`): `Dynamic{X}` and `Compiled{X}` swap; `Kept{X}` keeps its form and flips its attribute. **Recommendation.** "Of a `Dynamic{X}` a `Compiled{X}`, and the reverse; of a `Kept{X}` a `Kept{X}` with the other attribute."

### R7 (medium). A trait's name outside a trait module: the table states today's encoding as the design

- The table (`:759`), last column: `X` outside trait modules is "an abstract type no value has". §2 (`:152`) says the same for an argument.
- §7.2 (`:897`): with traits in the type system, "a trait's name in any field or container means `Kept{X}`, outside trait modules too" (Planned, L-6). §14 (`:1233`, Planned): `x isa X` is true for a conforming value.
- So in the intended design the cell is `Kept{X}` for a field or container, and for an argument the design is not stated: once `x isa Shape` holds, a plain method `g(x::Shape)` outside a trait module applies to a `Circle`, or it does not; nothing says which. The old §2 had the sentence; the new table promotes it to a rule of the design, against the conventions ("A Planned item is written as the design intends it").

**Recommendation.** The cell: "in a field or container, `Kept{X}` (Planned, L-6); in an argument, no bound (§2)". And an open issue for `g(x::Shape)` outside a trait module with traits in the type system, unless it is decided somewhere I did not find.

### R8 (medium). The warning's reason, second attempt; the code's message; which attributes it covers

- §6.3 (`:767`): "inside the module, values already carry their attribute, so the annotation would decide nothing there." Not exactly: a plain value trait code makes itself (`paint_once(io, Dot())` inside `Plots`) is first seen at that bound, and the annotation decides (§6.2's own table, first row). The decision's reason is about expectation, not impossibility ("It would be easy to assume it achieves something that it doesn't").
- The code's message (`attributes.jl:302–304`) still gives the reason the structure review showed false: "no value from plain code enters there, so the attribute decides nothing". The reference's §6.3 and the code now disagree on the text; no T- row.
- By reading, the warning covers attributes on bounds only: `__tw_attrs__` is keyed by `(function, position, nargs)` from `_classify`; an item parameter's attribute is a `Through` tag and is not recorded. The reference says "an attribute on a function", which a reader takes to include `ms::Iterable{Compiled{Mark}}`. Unverified by running.

**Recommendation.** The reason: "a plain value is expected from plain callers, at public functions; elsewhere an annotation is easily mistaken for a cast". Say which attributes warn. A T- row for the message, or the message changed.

### R9 (medium). A plain value stored where `Dynamic{X}` or `Compiled{X}` is declared is unspecified

The table's bullet (`:763`) says the type "holds kept values of that form"; §6.2's table (`:714`) lists only a field of a trait's name as an entry point for storage. So, by the letter, a plain value stored into a `Vector{Dynamic{Hook}}` or a `Dynamic{Shape}` field is not converted. The code agrees: there is no `convert(::Type{Dynamic{X}}, x)` for a plain `x` (`core.jl:588–593`), so `push!(hooks, Below(0.9))` on the example's `hooks` (`:861`) raises a `MethodError` from `convert`. The reference should say so, in one sentence under the table: "A plain value stored there is not converted; write `Dynamic{X}(x)`." Otherwise the user's "the plain type" is left for the reader to work out.

### R10 (medium). Stale, carried over

- The Deviations header (`:1337`) still names TraitWorld 227781a. TraitWorld's main is 804b662, with uncommitted changes (R1 among them); `state.md` names 1d09112.
- Rows T-37, T-38, T-39, T-47 to T-51 cite no lines; T-38, T-39 and L-27 cite "branch `basetraits`", which is merged. The conventions ask for `file:line`.
- Not a fault of the restructuring, but the structure review listed both under F6 and they were not done.

### R11 (minor). Duplicates that remain

- "A `@concrete_only` trait may be used at a `Dynamic` position: a `Dynamic` value is erased by choice, not of abstract type": verbatim in §6.3 (`:769`) and §11 (`:1165`). One stays; "erased" is lowering's word (F4): "a `Dynamic` value's type is unknown by choice".
- "A `Dynamic` annotation fixes the parameters its operations' result types use": §5.1 (`:535`), §6.3 (`:768`), §7.1 (`:876`). §6.3's is a pointer; §7.1's restates it for the form. Two would do.
- "A type never casts": §6.3 (`:763`), §6.4 (`:786`), §6.6 (`:812`), §7.1 (`:884`). Down from six; the last two can be pointers.

### R12 (minor). Two sections on one subject; one subsection that restates the table

- §6.6 "Items of a user's container" and §8.3 "A user's container, taken as it is" split one subject (which containers are taken; what each item is; writes) across two chapters, each linking the other (`:813`, `:1039`, `:1046`). One section, in chapter 8 with a pointer from §6.2's table, would be shorter.
- §7.2's first two bullets (`:892–893`) restate the table's storage column; §7.3 (`:901–907`) is the first-seen rule plus the `Base.convert` hook. Fold both into §6.3's bullets and §7.1, and keep the `convert` hook as one line.

### R13 (minor). `Self` for an implementation served by defaults alone

§3.5 (`:278`) gives two cases: own methods (the conforming type) and `by f` (the field's type). An implementation whose operations are all defaults (§6.7 `:825`) is neither. Say "the conforming type" for it; L-21 then has something to deviate from.

### R14 (minor). The grammar, and one form neither refused nor meaningful

- `:100`: `Struct ::= "struct" Name "{" ( StructParam "," )* "}" Field* "end"` requires a trailing comma, leaves `Field` undefined, and omits `mutable struct`, which the example at `:854` uses.
- `Iterable{Kept{X}}` as an item parameter: see R2's last point.

### R15 (minor). "Per key" became "per concrete type" in three places

§4.8 (`:458`, "Code is still compiled per concrete type"), against the same section's "shares the code compiled for the field's type" (`:460`) and §6.7; §4.10 (`:509`); §5.7 (`:629`, with a link to §6.7). The old text said "per key" in all three, which was right: a forwarding type shares. "Per key" is defined in §6.7 and is the term the user's performance model needs.

### R16 (minor). Content of the old version that is gone

Compared section by section (old §1–§19 against new §1–§17). Nothing that should have stayed is lost, with one question:
- Old §10.3: "Seeing an item costs a check, not a copy, **and allocates nothing**." The new §6.6 (`:810`) drops "allocates nothing". It is a guarantee, not a number, and lowering §13 states it ("nothing is allocated"). The user has cared about it (the 5 ns in `state.md`). Keep it or let lowering hold it; either way, decide.
- Dropped on purpose and rightly: the entry/worker paragraph, "one at its key is `Compiled`, one at the erased key `Dynamic`", `CompiledItems`/`CompiledValues` and "what the container crosses as" (they are still exported by TraitWorld; the reference now names only the two `Dynamic*` views as public, which is the F4 disposition), "a dynamic call takes at most six arguments" (now T-51), the pointers, "how untyped callers find it".
- Changed in meaning, rightly: §3.1 "At every call on a trait object **or a kept value**"; §5.6 "a kept value of the same form and attribute"; §13 "adds no method to the library's functions". The retired rows' pointers (T-24, T-25, T-29, T-40 to T-46) were renumbered correctly; T-35 restated in user terms.
- Old §12.3 "Plain code is not protected by it" is gone; its status note contradicted it, so no loss.

### R17 (minor). Terms

- **Plain value** is defined at `:707` ("one that does not carry an attribute yet") and used throughout chapter 6 and in the user's rule; the glossary has no entry. The conventions want one, pointing to §6.2.
- The glossary's **Receiver type** says "Defined in: traits §6.7"; the definition is §4.3 (`:370`). Its **Concrete mode** entry cites "traits §11, §11".
- **"Explicit views"** (§8.3 `:1040`) for `DynamicItems{X}(v)`: "view" is the glossary's lowering term. "Explicit copies" or "wrappers" would not collide.
- T-49 says "declared with the receiver type (`Self`)": say `Self`. T-39's "reference says" column uses "crosses" and "translated", which the body no longer does: "is taken at a bounded keyword as at a positional argument".
- L-31 (a trait object at a `Callable`'s argument that declares `Dynamic{X}` is refused) is user-visible and not linked from §5.8.

### R18 (minor). Sentences that are long or hard

`:811` (a write stores what reads back…; four clauses with "else"), `:840` (one bullet of five sentences, the cost model), `:1043` (which containers are taken), `:931` (the constructor is the bound), `:720` (the run-time dispatched call, with three examples in one parenthesis), `:484` (overrides belong to the implementation; pre-existing).

### R19 (minor). "Every value in trait code is `Compiled` or `Dynamic`"

§6.1 (`:678`). An `Int` in trait code is neither. The phrase is the user's (the decision row of 2026-10-20), so low priority; "every value seen through a trait" is exact.

### R20 (minor). The status index lists T-47 and T-50 and not T-48, T-49, T-51

Rows name deviations unevenly. Either every T- row with a construct in the index is cited there, or none.

---

## 3. Chapter 6 against the decisions in force

Checked against the rows "`Dynamic` and `Compiled`, the rule / the rest / refined / the implementation's choices / the remaining answers", "`compiled_for` from an untyped caller", "Values carry their attribute through storage", and the user's answer on `Dynamic{X}` in storage.

- The three sentences of the rule: stated once, at the head of the chapter (`:674`). Correct.
- Where a plain value is first seen (§6.2's table): matches the "refined" row's four places plus the two the W-18 row adds (a field of a trait's name; a bounded struct parameter) and the constructors. Complete.
- The first-seen rule, the prompt, run-time dispatched calls: as decided (Q6). Correct.
- The order (first-seen, trait's default, annotation, cast; the later of two casts): as decided. Correct, except that the code's third default (R1) has no line.
- Casts the only way; constructors keep, never cast; types never cast: as decided. Correct, except R6's sentence.
- Values carry through calls, bounds, storage, library to library, up and down: as decided. Correct.
- `Dynamic{X}`, `Compiled{X}` the plain types in a trait module's storage; a trait's name `Kept{X}`: as the user answered. Correct (`:892–893`), and the code agrees (`_dyn_type`, `_dyn_body`: `Dynamic{X}`, `Compiled{X}`, `Kept{X}` written out are left as they are).
- A plain value assigned to a field of a trait's name takes the trait's default (item 40 closed): §7.3 says so; the code does (`convert`, `core.jl:590`). Correct, except that the default ignores "of the trait world" there (R5) and that §6.2's reason for it is wrong (R3).
- The item table (§6.6, `:804–808`): checked cell by cell against lowering §13.1's view table. Correct for a trait without a default; it does not say so, and its first row is wrong for a trait with one (R1, point 5).
- The sharing rule (§6.7) and the cost line (§6.8): as decided (keys; four then a constant cost; the image clause in user terms). Correct.

So chapter 6 is right on the decisions. Its faults are R2 (the table's bullet), R3 (the constructor sentence), R6 (one sentence), R9 (one gap), and R1, which is not the chapter's fault.

---

## 4. Links

All 380 links in `traits.md` resolve (a script over GitHub-style anchors, `/tmp/claude-1000/review/linkcheck.py`). All inbound links from `lowering.md`, `facts.md`, `compiler.md`, the glossary, `state.md`, `open-issues.md`, `design.md`, the three `intro/` pages and `todo.md` resolve to the new section numbers. Two anchor texts are stale though the targets are right: `compiler.md` says "`traits.md` §12" for the link to §10, "§14" for §12 and "§16" for §14 (`compiler.md`, the lines on strict mode, printers and membership).

---

## 5. Is it simpler and clearer than before?

Yes, in structure. The rule has one home; the thirteen statements of the structure review are a table of entry points, a table of spellings and one order; `Self` is the value seen through the trait; the receiver type is in two places; the mechanism is out of the body; the checks table and the printing section no longer speak of entries, workers and erased keys. A programmer can now read chapters 5 to 7 in order and meet each rule once.

It is longer: 1391 lines against 1307. The growth is the two tables, chapter 7's split into six subsections, and §6.6/§8.3 saying one subject twice.

What would simplify further, in order of gain:
1. Fix the table (R2) and give it a legend; then §7.2 and §7.3 can go into it (R12).
2. One section for a user's container (R12), in chapter 8, with §6.2's table pointing at it.
3. Replace §6.2's constructor sentence by the two precise ones (R3).
4. Cut the three duplicates (R11) and the "views" word (R17).
5. Decide the default's spelling (R1) and write it once, in the grammar and §6.3.

---

## Verdict

The restructuring does what W-20 asked. F1 to F11 are addressed, with small residues listed above; nothing of substance was lost; the chapter on values states the decisions in force correctly; every link resolves. Three things must be fixed before the commit: the trait's default, where the reference still says `@dynamic`, the code refuses it, the third default and its two choices are not in §6.3, the §6.6 item table assumes no default, and no decision row exists; the main agent's pending edit of §6.3 covers the spelling, and R1 lists the seven points it must reach (R1); the table's bullet "the type", which is wrong on a bounded function's argument and on an operation's argument and misses the argument-parameter case (R2); and the sentence that makes every constructor `Compiled`, against §7.4 and the code (R3). The medium findings are one-sentence fixes (R4, R6, R9), one probable deviation to row or fix (R5), one wrong reason and one wrong message (R8), one design cell that states the encoding (R7), and the stale header and rows (R10). Adopt, with these fixes.
