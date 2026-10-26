# Fresh-eye review of reference/lowering.md (2026-10-26)

**Reviewed:** `writeup/reference/lowering.md` at design repository c6662bf. Checked against `traits.md`, `facts.md`, `compiler.md`, `glossary.md`, `open-issues.md`, `record/decisions.md` (same commit), TraitWorld main 4410407 (`TraitWorld/src/`), and the patched Julia fa4e7f5798 (`julia-1.13/Compiler/src/`, by name only).

**Method.** I read the four references, the glossary, the open issues and the decision log in full. For the lowering I then checked against TraitWorld's source: every `file:line` citation (108 of them, by printing the cited line and matching the named function), every code name in backticks (257 names, by grep in `TraitWorld/src/` and the patched compiler), and the bodies of the functions behind the claims I doubted: `_key_and_slots`, `_no_implementing_type`, `_field_problems`, `_buildview`/`_parts`/`_partstype`, `enter`, `_enters_dynamic`, `_traits_default`, `enter_kw`, `_tw_type`, `enter_callable`, `_kept_at`, `Erased`/`_fptr`/`_CallWrap`/`_PtrCell`, `_conf_family`/`_conf_family_slow`, `_conformance_slow`, `_flush_if_stale!`, `_crosses`/`_cross_flag`/`_cross_decide`, `_umiss`/`_ulookup`, `_check_ahead!`, `_refusing`/`_rollback!`, `_note_conformances!`, `checked_call`, `archetype_sig`, `_machinery_method`, the `@max_methods` declarations, the `@trait` expansion of operation methods, the `@machinery` macro and TraitWorld's module header. No Julia was run: every claim below was settled by reading, so the system image's build does not matter. Not checked: the patched Julia's own behaviour behind `compiler.md` (taken as that reference states it), `strict.jl`, `verify.jl` beyond the guard list, `defcheck.jl` beyond `archetype_sig`, the demonstrators, and any timing.

**Counts.** High 3, Medium 7, Low 12.

Severity: **High** = a contradiction or unsoundness in the design, or a false statement about what is built; **Medium** = an inconsistency or gap a reader trips over; **Low** = wording, a stale term, a link. Within each level, ordered by damage.

---

## High

### H1. The key's field types: the lowering keys a `@const` field by its stored type; `traits.md` says the declared type

- **Location:** `writeup/reference/lowering.md:240` ("`Key{I, F}`, with ... `F` a named-tuple type of the declared fields' *stored* types"), `:292` ("The result has exactly the key's field type"); against `writeup/reference/traits.md:873` ("plus the declared fields' types"), `:877` ("An abstract declared field's type ... is part of the key as it is: one compiled copy for it, whatever the field holds, and operations on that part dispatch when they run. A value read from that part has an abstract type in the code"); `writeup/glossary.md:201`; `writeup/record/decisions.md:19` ("plus the declared fields' types").
- **What is wrong.** The two references disagree on what `Compiled` code is compiled for, which is `traits.md`'s to decide (README: "What a program means ... which code is shared" belongs to `traits.md`).
  - *Verified* (by reading): `_key_and_slots` (`TraitWorld/src/entry.jl:667`) builds `F` from `fieldtype(U, i)`, the stored field's type. `_field_problems` (`implement.jl:595`) requires the stored type to equal the declared type only for a writable field; for a `@const` field it accepts any subtype (`ST <: FT`).
  - Counterexample: `@trait Named begin @const name::AbstractString end`; `struct A; name::String; end`, `struct B; name::SubString{String}; end`, both `@implement Named`. Under the lowering, `A` and `B` have different keys, a bounded function is compiled twice, and `t.name` is typed `String` in one copy. Under `traits.md` §6.7 they share one copy at `AbstractString`, and `t.name` reads abstractly. The glossary and the decision log follow `traits.md`.
  - The lowering's reading is the better one for speed, but it is a decision, and it is not in `traits.md`. `traits.md` §3.3 ("same name ..., and the declared type") does not even say that a `@const` field may be stored at a subtype, so the implementation check is wider than the language too.
- **Fix:** an open issue: *is the key's field type the stored type as matched (the lowering, as built), or the declared type (`traits.md` §6.7)? May a `@const` declared field be stored at a strict subtype of its declared type?* Then: if the stored type wins, change `traits.md` §3.3 (a `@const` field may be stored at a subtype), §6.7 (bullet 2: "plus the declared fields' stored types, as the implementation matched them"; the "abstract declared field" bullet restricted to a field whose *stored* type is abstract), the glossary's "Key" and decisions row 19's wording; if the declared type wins, change `lowering.md:240`, `:292`, `_key_and_slots` and `_parts`, and add a row `L-42` until then. Until decided, a row in one Deviations table: "the key's field type is the stored type; a `@const` field stored at a subtype is accepted".

### H2. §2 says the machinery's caches are "keyed by that world and emptied when it changes"; the family registry never is

- **Location:** `writeup/reference/lowering.md:80` ("Its caches are keyed by that world and emptied when it changes (`_flush_if_stale!`, `implement.jl:269`)"); against `:198`–`:204` (§4.6, "A member is fixed at its first use ... stores it in the registry") and `traits.md:457`.
- **What is wrong.** *Verified* (by reading): `_flush_if_stale!` (`implement.jl:309`) empties only the witness caches `_WITNESS` and `_PWITNESS`; `_conformance_slow` (`entry.jl:144`) keys `_SLOW` by the caller's world. The family registry (`const reg = Ref(IdDict())`, read by `_conf_family`, `implement.jl:856`) is appended and never emptied; so are `_CALLABLE`, `_FROM_TW`, the crossing flags (H3) and the untyped tables (world *ranges*, `untyped.jl:66`). As written, §2 tells a reader that a family member is re-decided after any method definition, while §4.6 and `traits.md` §4.7 ("fixed at its first use", the owner's override allowed "until then, and not after"; T-28, L-23) rest on the registry being permanent. The sentence is false about what is built, and it hides the one design fact that matters here: which decisions are per world (a generic implementation's) and which are fixed for the session (a family member's, a type's trait-world test, a function's wrapper).
- **Fix:** replace `:80` with: "The witness caches and the slow path's cache are keyed by that world and emptied when it changes (`_flush_if_stale!`, `_conformance_slow`). A family member's builder (§4.6), the trait-world test of a type (§8.2) and a function's wrapper (§12) are fixed for the session once found." Cross-check with §9.3, which already states the world ranges correctly.

### H3. §16 says the session stamp makes "the crossing's decisions" stale; the crossing flag carries no stamp

- **Location:** `writeup/reference/lowering.md:693` ("a new session stamp, which makes the flags saved in images stale (candidate registrations, the crossing's decisions)"); `:566` (§13.1, "Decided once per crossing and container type, in a flag the entry's code holds as a constant").
- **What is wrong.** *Verified* (by reading): `_SESSION` is compared in `core.jl:533` (`_cand_flag`), `untyped.jl:49`, `:218` and `BaseTraits.jl:332` (`_hold_flag`); `_cross_flag` (`entry.jl:320`) is a `@generated` function returning a bare `Ref{UInt8}(0)` per crossing and container type, and `_cross_decide` writes 1 or 2 into it with no stamp. A flag at 2 saved in a package image is reused as it is in the next session. The statement is false about what is built. The damage is small: the decision depends only on the trait-object type of the container and of its view, which the image's dependencies fix, so a stale flag gives the same answer (speed only, by `compiler.md` §4.1's rule). But §13.1 should say so instead of §16 claiming a stamp.
- **Fix:** at `:693` drop "the crossing's decisions" and name what the stamp covers: "candidate registrations, the untyped tables, BaseTraits' hold flags"; at `:566` add: "The flag is not stamped: a decision saved in an image stands in the next session. It depends only on the types the image's dependencies define." If a stamp is wanted for symmetry, a row `L-43`.

---

## Medium

### M1. The code citations are pinned to TraitWorld 227781a; 94 of 108 cited lines no longer name their code at main

- **Location:** `writeup/reference/lowering.md:8` (the pin), every `file:line` in §2–§16 and in the Deviations' "Where" column; `traits.md:1473` carries the same pin.
- **What is wrong.** *Verified*: main (4410407) is 40 commits and about 3100 inserted lines past 227781a. Printing each cited line and matching the named function: 14 of 108 still hold (e.g. `trait_module.jl:60`, `implement.jl:24`, `:45`, `hooks.jl:62`, `TraitWorld.jl:166`); the other 94 point at unrelated lines. Every cited *name* still exists except `_uses_callable` (`:335`; the check is now `trait_module.jl:495`/`:526`, unnamed). Two sections cite `entry.jl:730` for different things (`:464` `_rebuild`, `:504` the closed-build branch of `enter_callable`; the latter is now `entry.jl:812`). §13's sketch writes `family(X)` (`:533`) where the code has `_family_of(X)` (`trait.jl:437`). The README's convention ("Where names code (`file:line` in the repository)") is met by the letter and defeated in practice: the "Where" column cannot be followed against the implementation the record names as current.
- **Fix:** either re-pin to 4410407 and refresh every line number (a script that prints each cited line against the named function, as I did, finds the misses in seconds), or cite functions without line numbers, as the newer rows (L-16, L-23, L-26, L-36) already do. Rename `_uses_callable` to the function that refuses a `Callable` naming a `where` variable, or drop the name.

### M2. §8.2's default rule applies the "of the trait world" exception to both defaults; `traits.md` and the code apply it to `@default_with_dynamic_self` only

- **Location:** `writeup/reference/lowering.md:357` ("the traits' default (`default_attribute`), unless the value's type is of the trait world (`_tw_type`)"); `:99` (§3) and `:596` (§13.2, "a plain value by the first-seen rule (the trait's default, then `known`)") say nothing of the exception; against `traits.md:777` and `:781` ("`@default_compiled_for_self` ... applies to every plain value").
- **What is wrong.** *Verified*: `_enters_dynamic` (`attributes.jl:260`): `d === :dynamic && !_from_trait_world(t) && return true; d === :compiled && return false; return !kn`; `enter_kw` (`entry.jl:542`) and `_kept_at` (`entry.jl:863`) likewise. The code follows `traits.md`. Read literally, `:357` makes a trait-world value at a `@default_compiled_for_self` bound fall through to `known_type`, so an untyped caller would pass it `Dynamic`; the design says `Compiled`.
- **Fix:** `:357`: "the traits' default: `@default_compiled_for_self` for every plain value; `@default_with_dynamic_self` for a value whose type is not of the trait world (`_from_trait_world`)". Add the same clause at `:596`.

### M3. §12 says a `Dynamic` function "runs as plain code, as every call through a `cfunction` does"; `compiler.md` §2.5 says the default owner's code

- **Location:** `writeup/reference/lowering.md:493`; against `compiler.md:352`–`:359` and `facts.md:247`–`:249`.
- **What is wrong.** *Reasoning from the sources*: the pointer's target is `_CallWrap{S}` (`core.jl:1136`), a method of TraitWorld, whose module has no `facts` option (`TraitWorld.jl`; `compiler.jl:32`: "TraitWorld's other code stays plain"). From the cfunction thunk it runs through `jl_apply`, so by `compiler.md` §2.5 it runs its default owner's code, plain in the product setting; the call `o(a)` inside it is a dynamic dispatch from plain code to the user's function, which runs *its* default owner's code: plain for a user's closure, facts for a closure or function of a trait module. "Runs as plain code" is wrong for the second case, and the second case is exactly the one G2 cares about (a trait module's closure handed down as a `Dynamic` callback keeps its facts code and its protection). The sentence also cites §2.5 for the opposite of what §2.5 says.
- **Fix:** `:493`: "the function runs the code of its default owner, as every call through a `cfunction` does ([compiler §2.5]): plain code for a user's function, facts code for a function of a trait module".

### M4. §2's table calls TraitWorld's helpers "plain code"; they are neutral methods, compiled by facts when a worker reaches them

- **Location:** `writeup/reference/lowering.md:71` (row "TraitWorld's small helpers (`enter`, `_assemble`, `checked_call`, `opcall`, the builders) | plain code, inlined into the code that calls them | `@inline`"); against `facts.md:268`–`:291` (four kinds; a neutral method reached from the facts owner is compiled by facts) and `compiler.md:283`–`:291`.
- **What is wrong.** *Verified*: TraitWorld's module carries no `@compiler_options` (only `trait_module.jl:60` emits one, for trait modules). So these are neutral methods. `opcall` is reached from a worker through the operation method `@trait` defines; `enter` is reached from a worker when it calls another bounded function with a plain value; `checked_call` from an entry inlined into a worker. In those cases the helper's code is facts code under the facts owner, whether or not it is inlined. "Plain code" contradicts the mode rule the row sits beside, and a reader cannot tell which helper calls hold plain edges (none, in facts callers) from this table.
- **Fix:** `:71`: "neutral methods ([facts §6.1]): compiled in the mode that reaches them, plain from a plain caller, facts from a worker; usually inlined | `@inline`".

### M5. §4.6's Planned mechanism (W-40) needs a compiler interface `compiler.md` does not provide

- **Location:** `writeup/reference/lowering.md:206` ("While the compiler infers such a caller, it checks the member and finds its builder as the slow path does, and puts the builder into the caller's code. The caller has edges on the methods the check read"); `record/decisions.md:41`; `record/todo.md:49` (W-40); `open-issues.md:244` (item 49, closed).
- **What is wrong.** *Reasoning*: the member check (`_member_problems`, `implement.jl`, after `_conf_family_slow`) infers the member's operations' methods and reads the records; it is machinery, not foldable. For its result to become a constant of the caller with "edges on the methods the check read", inference must run a library check during the caller's inference and record edges for what it read. `compiler.md` lists no such interface: §4 has `known_type` and `split_call`; §7 ("entries and workers generated by the compiler") is the last step, after this. Julia's own facilities give two partial routes, neither named: a generated `conformance` method whose generator runs the check and bounds its `CodeInfo` by `min_world`/`max_world` (world bounds, not edges), or concrete evaluation of a `:foldable` function (not this one). So the paragraph states an intended shape whose interface is undefined, which the README says belongs in `compiler.md` ("An interface of Julia's ... belongs to `compiler.md`, with its semantics"). This challenges decision row 41's "with edges on the methods the check read" as a statement of how, not whether.
- **Fix:** add a Planned section to `compiler.md` §4 or §5 naming the interface W-40 will use (a generator's world bounds, or a new "fold with edges" hook), and point `:206` at it. Until then, mark `:206` Open with an open issue: *how does a caller get a member's builder as a constant with the right invalidation?*

### M6. §6 adds to what code is compiled for: a key used both held and read through has two workers; `traits.md` §6.7 does not say so

- **Location:** `writeup/reference/lowering.md:281` ("A key used both held and read through has one worker per view type"), `:271`–`:278` (the layouts), `:53` (§1, "A worker is compiled per view type"); against `traits.md:875` ("Types with equal keys share compiled code").
- **What is wrong.** *Verified*: `_build` (`entry.jl:52`) makes a `Held` view when the user's type is its own receiver and immutable, else a `View`; mutable and immutable forwarders share `View{X,W,K,N,P}` (the parts are computed for both; only the value of `o` differs), so most of the sharing claim holds. The exception is real: an immutable type that implements the operations itself (key `R = U`, `Held`) and a type forwarding to a field of type `R` (`View`) have the same key and two workers. `traits.md` promises one copy per key; the lowering decides an exception and does not record it as a deviation or send it to `traits.md`.
- **Fix:** either state it in `traits.md` §6.7 ("an immutable receiver type seen directly and seen through a forwarding field have one key and two compiled copies"), or add a row `L-44` ("the reference says types with equal keys share compiled code; the implementation compiles a held view and a read-through view separately") and keep `:281` as the mechanism.

### M7. L-37 carries measurements and reads as if W-40 were done

- **Location:** `writeup/reference/lowering.md:775` (L-37: "384–456 ns and 208 bytes per call against 0.96 ns and 0 bytes ... 241 ns and 80 bytes against 3.2 ns (E-156 P15, P13 ...)"; "The gap is shown (E-156 P15); fixed by W-40").
- **What is wrong.** The README forbids measurements in a reference ("A number appears only when it is part of the design"); these numbers belong in `design/evidence.md`, which the row already links. "Fixed by W-40" reads as done; §4.6 marks W-40 Planned and `todo.md:49` says "not yet".
- **Fix:** "`conformance` reaches `_conf_family` at every call: a lookup in the family's registry and a call on the builder at the abstract type `Builder`; several hundred times a declared type's cost ([evidence §2], E-156 P13, P15). A port that needs the speed declares its hot members one by one. To be removed by W-40."

---

## Low

### L1. §4.7's Open item links `traits.md`, not the open issue
- **Location:** `writeup/reference/lowering.md:212` ("what a predicate may say **Open** ([`traits.md#48`])"). The README: an Open status links `open-issues.md`. *Verified*: the issue is `open-issues.md:129` ("Found in the writeup cleanup", item 2).
- **Fix:** link `../open-issues.md#2-design`, "the design and the code disagree", item 2.

### L2. §1's "Status of the attributes" omits L-36
- **Location:** `writeup/reference/lowering.md:55` ("Implemented, except L-31 and L-35"). L-36 (`:774`, a `Callable` at a typed entry entered untyped) is an attribute deviation; L-35 is about `verify_main`. *Verified*: `enter_callable` is still `@noinline` with `@nospecialize(f)` (`entry.jl:796`).
- **Fix:** "except L-31, L-36 (and, for closed builds, L-35)".

### L3. §3 says the operation methods are "on `Dynamic{X}`"; they are on the three kept forms, and the sentinel list is short
- **Location:** `writeup/reference/lowering.md:97` ("One method per operation and arity **on `Dynamic{X}`**"); `:115`–`:116` (the sentinel lists). *Verified*: `trait.jl:442` defines them on `HeldValue{X}` (§13 says so at `:532`); `crossing` (`entry.jl:290`), `bounded_constructor` (`entry.jl:833`), `supertrait_args` and `trait_super_params` (`core.jl:1028`, `:1031`) are `@max_methods 1` functions not in either list.
- **Fix:** `:97` "on the kept forms, `HeldValue{X}`"; add the four names to the lists at `:115`–`:116`.

### L4. §5's "The lower bound has no free type variable" trips a newcomer
- **Location:** `writeup/reference/lowering.md:263`. `T` in `TObj{T} where T >: Union{…}` *is* a free variable of the signature; the sentence means the `Union` names no variable. Also worth one sentence: why `>:` gives the dispatch order `traits.md` §5.5 wants (a larger union is a smaller set of `T`, so more bounds and a subtrait are more specific).
- **Fix:** "The union names no type variable, so `T` is fixed by the argument's type alone. A bound with more traits has a larger union, which fewer `T` satisfy, so it is more specific: this gives §5.5's order among bounds."

### L5. §6 announces "Three layouts" and lists four
- **Location:** `writeup/reference/lowering.md:271`–`:278`. The fourth row (the erased key) is a layout too.
- **Fix:** "Four layouts", or move the erased row to §13 and keep three.

### L6. §8.2: the attribute follows the inliner, not only the caller's knowledge
- **Location:** `writeup/reference/lowering.md:349`, `:358`, `:398`. The entry's trait positions are `@nospecialize`, so where the inliner does *not* inline the entry (a call at the inlining limit, `--inline=no`, an `:invoke` of the compileable specialization), the caller reaches the entry compiled at `Any` and `known_type` is `false`: a known type enters `Dynamic`. `compiler.md` §4.1 covers it (speed only), but the lowering states `traits.md` §6.2's rule as exact. *Reasoning* from `@nospecialize`'s semantics; E-148 tested inlined and dispatched calls only.
- **Fix:** one sentence after `:358`: "Where the entry is not inlined, the caller reaches the entry compiled at `Any` and the value enters `Dynamic`: speed only, by [compiler §4.1]'s rule."

### L7. §14's `__tw_checked__` placement reads as a choice of module; it is "whichever is open"
- **Location:** `writeup/reference/lowering.md:634` ("in the conforming type's module, else the declaring module"). *Verified*: `_check_ahead!` (`ahead.jl:57`) tries `parentmodule(T)` first and falls back to the declaring module when `eval` into the type's module fails because that module is closed (another image's).
- **Fix:** "in the conforming type's module when that module is the one being precompiled, else the declaring module".

### L8. History and a branch name in two deviation rows
- **Location:** `writeup/reference/lowering.md:762` (L-25: "since branch `basetraits` 8863ea0"; "Where: `core.jl:532` (...; branch `basetraits`)"), `:773` (L-35: "as before the erased key (checked by reading and one run, 2026-10-20)"). *Verified*: 8863ea0 is an ancestor of main; the branch is merged. The README forbids "since"/"before" history in a reference.
- **Fix:** L-25: drop the "since" clause and the branch; "Where: `TraitWorld/src/core.jl` (`_note_conformances!`)". L-35: "not done: for a program with untyped calls `verify_main` reports the program's run-time sites as holes; a closed build of code at a `Dynamic` position is not tried".

### L9. Three mechanisms described as complete have traits-side deviations the lowering does not point at
- **Location:** `writeup/reference/lowering.md:255` and `:310` (an argument declared `Self` at the erased key: `traits.md` T-49 says `TraitArgumentError`); `:467` (a constructor operation on a `Dynamic`: T-35, refused for a trait with fields); `:436`–`:444` (keywords: T-48, a function whose only bounded arguments are keywords gets an entry and a worker of one signature, a defect of the rewrite in §8.1). The rows belong where they are; the lowering sections should point at them, as §4.4 points at L-7.
- **Fix:** add "([traits T-49])", "([traits T-35])", "([traits T-48])" at those lines.

### L10. The family's builder is found in the latest world, not the decision world
- **Location:** `writeup/reference/lowering.md:80` (§2, "decides implementations in the world of the call"), `:199` (§4.6). *Verified*: `_conf_family_slow` (`implement.jl:861`) decides conformance through `_conformance_slow` in the caller's world but finds the builder with `_latest(_family_builder, X, U)` (`invokelatest`). A task pinned to an older world can fix a builder found from methods its world does not see. An edge case, but it is the one rule §2 states.
- **Fix:** either `_in_world(w, _family_builder, …)` in the code, or a half-sentence at `:199`: "the builder is found in the latest world".

### L11. A Planned line sits in the wrong section
- **Location:** `writeup/reference/lowering.md:598` ("**Planned:** `Dynamic{(X, Y)}`, a value seen through several traits" at the end of §13.2, the struct section). §13's head (`:512`) already says it.
- **Fix:** delete `:598`, or make it "a tuple of traits as a struct parameter's bound" if that was meant (`traits.md:1020` lists it as Planned).

### L12. An open issue contradicts §13 and cites a retired row
- **Location:** `writeup/open-issues.md:130` ("Found in the writeup cleanup", item 4: "`Dynamic{X}` ... the code keeps a narrowed trait object (`_narrow`) ... [lowering L-8]"); against `lowering.md:514`–`:523` (the kept forms hold the user's object; a trait object only in two named cases) and L-8 retired (`:745`). Not the lowering's text, but a reader following the link lands on a stale claim.
- **Fix:** close item 4 with a pointer to §13, or restate it against the current text.

---

## What I checked and found sound (for the record)

- §4.1's rollback: `_refusing` deletes only on `ImplementError`; the `ErrorException` failures of T-10 are raised in the macro expansion before any method is defined, so "a refused declaration defines nothing" holds.
- §8.2's decision order in `enter` (rule 3, casts, carried attributes, then `_enters_dynamic`) and `known_type` evaluated in the entry's own body (`trait_module.jl:879`–`:954`).
- §9.3's world ranges in `_umiss`: a declared or family implementation for the range of `conformance`'s dispatch, a generic one for one world, a crossing position untabled.
- §12's pointer: `_fptr` emits `Expr(:cfunction, …, :caller_world)`; `_PtrCell` is mutable and atomic; `_cdecl` passes a concrete non-bits argument as `Ref{T}`; arities 0–6 (T-51).
- §13's sketch matches `trait.jl:437`–`:442` up to the name `_family_of`; candidates sorted by (file, line) in `_note_conformances!`; `_cand_flag` stamped by `_SESSION`.
- §14: `checked_call` is generated, holds a `Ref` flag, and calls `_check_once` through `invokelatest` behind an inference barrier; `archetype_sig` skips keyword, vararg and `Callable` workers (L-10).
- §15.3: `_cross_decide` is in `verify_main`'s guard list (L-27 consistent).
- §16: `_on_method_definition` is `@machinery`; `_on_package_load` registers candidates through `_bump!`.
- §17 and the retired rows follow the README's form (ID kept, pointer, no story).

---

**Addendum (2026-10-26, filing).** M5 (W-40's mechanism needs a compiler interface) is taken up by the W-40 design note, `writeup/plans/2026-10-26-w40-member-builder-fold.md` (`Compiler.fold_call`). `names.txt` is filed in `experiments/review-2026-10-26-references/`. What was done with each finding is recorded where it was done.
