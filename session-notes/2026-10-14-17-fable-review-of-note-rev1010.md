# Fable review of "Traits for better Julia", rev 1010 (2026-10-14)

Reviewed: the full export at `scratchpad/note-rev1010.md` (all sections), checked against `poc/world/README.md`, `writeup/design-findings.md`, `TraitWorld/src` and small experiments on Julia 1.12.2 (scratch under `/tmp/claude-1000/.../scratchpad/exp`). "Verified" below means I ran it or read the source; everything else is reasoning from the note's own text.

## Verdict

The layering idea and the seven rules are internally coherent for the case the note was written around: packages with fixed dependency sets, values that are deeply concrete, and a pirate that arrives after the seal. The new material is where the argument is weakest. Sealing is specified for one load order only (seal, then pirate), its precompile-time refusal cannot be relied on because Julia's compile cache is shared across environments, and its load-time refusal leaves earlier definitions in place, which contradicts "nothing is left half loaded". `CompiledCall` compiles a trait module's own library code against a closure from above, in the caller's image, outside rule 6's view; the note calls that "ordinary code", which saves the letter of rule 1 but gives up goal 1 for every function whose default is `CompiledCall`, including the note's own `colsum`. Rule 6's view is undefined for a representation defined in the session, which is the note's running example (`Ramp`), so the interactivity and no-cliff guarantees are weaker than stated in exactly the interactive case. Several smaller contradictions (supertraits as both rule and extension, two meanings of `Callable`'s third parameter, "not yet measured" against a measured 4 ns, a stale 9–10 ms) are easy to fix. The claims about Julia as it is are almost all right; I found two minor factual slips (`--trim` default behaviour, `remotecall` returns a `Future`). Nothing I found breaks "identical or error" in the strict mode: the runtime dispatch check carries that guarantee everywhere the static story has a gap, and the note should say so more plainly, because it is doing far more work than the "each is closed" paragraph admits.

## Findings, most severe first

### 1. Sealing is defined only for the pirate-after-seal order; the other order is left open, and it is the common one

**Section:** "Identical or error"; "Sealing" (When, What you get); the second table.

**Quotes:** "From then on a definition that would pirate a sealed package is refused at the load, so no call ever sees a pirate and no call ever errors on one." — "Once a sealed package is loaded, loading a pirate fails, naming it." — "An interface package's own load checks the tree it seals, and a pirate in it that the package does not declare as tolerated fails that load." — "In a session whose packages are interface packages and their closures, nothing can pirate anything: every cache stays valid, every worker runs against what it was compiled for, and a build sees the whole world."

**Why it is wrong.** Every mechanism in the section fires when the *pirate* loads after the *seal*. The note's own example (`using MyTable` then `using Pirate`) is that order. The scenario the note allows and never resolves: `using Pirate` (an ordinary package, or any dependency of one, with `Base.convert(::Type{Float64}, ::Int32) = …`), then `using Columns`. Base becomes sealed at the second load, but the pirate is already in Base's method table. The seal's own check covers only "the tree it seals", and Pirate is not in BaseInterface's tree. Columns' image holds workers compiled against unpirated Base. On stock Julia the image loader validates edges against the live table and discards those workers, and the pirate applies; the design must now choose between (a) refusing Columns' load because of a pirate that loaded first, with the error reaching whoever loads the trait package, (b) tolerating with a warning and recompiling, which is the opt-out, or (c) keeping the cached workers and running two answers, which "Other options considered" rejects twice. The note says none of these. "No call ever sees a pirate" is therefore unsupported in the order most sessions produce, since pirates arrive through transitive dependencies long before the first trait package. "The sealed region is what the project file says" does not help: the check is at load, and the project file does not order loads.

**Severity:** class 2 (a guarantee violated by a scenario the note allows), with a class 1 edge against "What you get".

**Minimal fix.** State that the load of a trait or interface package also checks the *session's* live method tables for pirates of what it seals, not only its own tree, and say what happens when it finds one (I would say: the same as a tolerated pirate, warn and recompile, with strict mode refusing the load and naming the pirate). Reword "no call ever sees a pirate" to the conditional it actually is.

### 2. Precompile-time refusal cannot be relied on, and load-time refusal does leave things half loaded

**Section:** "Identical or error"; "Sealing" (When).

**Quotes:** "For a package the refusal comes at its precompile, naming the pirate, the method and the owner it would need, so nothing is left half loaded; for code evaluated later, at the definition." — "For a package, at its precompile when its environment holds an interface package sealing what it would pirate, otherwise at its load, where the first refused definition fails the load".

**Why it is wrong.** Two facts about Julia as it is (verified on 1.12.2, `base/loading.jl`):

- The compile cache is keyed on the package, its dependencies' build ids, preferences and flags, not on the environment. The 1.12 file name carries a crc of the active project path to avoid clobbering, but `stale_cachefile` accepts any cache file in the directory whose dependencies match. So a cache of Pirate produced in an environment without any interface package is valid in an environment with one, and no precompile happens there. "At its precompile when its environment holds an interface package" is a courtesy that a shared depot bypasses; the refusal must be at load in general, which the note gives only as the "otherwise" branch.
- A load that fails at "the first refused definition" leaves everything evaluated before it in place. Verified: a source-loaded package that defines `Base.convert(::Type{Float64}, ::Val{:half})` and then throws leaves that method callable afterwards, and the module in `Base.loaded_modules`. For an image, `jl_insert_methods` inserts the image's methods in one pass with no rollback. The refusal stops the first *pirate*, so no pirate survives, but the package is half loaded in exactly the sense the first quote says it is not; and a second `using Pirate` after `tolerate!`, as in the note's example, loads on top of that residue.

Also note: the piracy decision itself needs no environment (owner of function and types vs. the defining package, as Aqua computes it), so the environment-dependent part of the precompile check is only "is the victim sealed", which is a property of the eventual session, not of the precompiling environment.

**Severity:** class 4 (the check needs information not available where the note places it), plus class 1 (the two quoted sentences disagree about half-loaded state).

**Minimal fix.** Make the load the primary place of refusal; make precompile an early warning that cannot be assumed; drop "so nothing is left half loaded" or qualify it with what Julia actually leaves behind. If a transactional load is intended, say so and mark it as new runtime work in trade-off 8.

### 3. `CompiledCall` contradicts "never infers into or compiles the code above", and takes library code out of the trait world by default

**Section:** "Function arguments: Callable"; "Four goals" (1); "Finer points" preamble.

**Quotes:** "`CompiledCall` compiles the worker per function type instead, as ordinary code in the caller's image (rule 7), a direct call the compiler may inline: plain Julia's speed and plain Julia's invalidation for that piece, while the trait module's own cache stays untouched." — "**Layering holds either way.** The trait world never imports, infers into or compiles the code above: a dynamic call goes through its pointer, and a compiled call's worker is ordinary code that lives with the caller." — "Code never crosses: the trait world never compiles against code from above." — Goal 1: "Library code that uses traits is compiled once, stored with the package that owns it, and reused in every session and every combination of packages."

**Why it is wrong.** A call "the compiler may inline" is a call the compiler has inferred into: the worker's typed code contains the closure's body. The sentence before says the trait world never infers into the code above. The note escapes by declaring the worker "ordinary code", but the worker is the trait module's library code (`colsum`'s body, `sum`, `col(t, i)`), now compiled against the global method table, outside rule 6's view, without the dispatch check, and subject to plain invalidation. So for every function whose *default* is `CompiledCall`, which the note's own `colsum` is ("the library's default is a compiled call"), the library's code is never "compiled once, stored with the package that owns it": it is compiled per closure type, in the session or the application, every time. Goal 1 and "Nothing recompiles under you" silently do not apply to those functions, and a caller can put any function in that state with `compiled_call(f)`. The soundness of the result is fine (the closure's result is asserted; in strict mode there are no pirates for the ordinary worker to meet), so this is an overclaim about the guarantees, not a hole; but the note presents the two modes as a free choice ("the library has no stake") when one of them forfeits the library's cache for that function.

**Severity:** class 1 (the quoted sentences contradict), shading into class 2 (goal 1 fails for `CompiledCall` defaults).

**Minimal fix.** Replace "never infers into or compiles the code above" with "never does so inside its cached workers"; say in the Callable section that a `CompiledCall` worker is compiled per closure type outside the library's cache, and that a library choosing it as default gives up goal 1 for that function; strike "the library has no stake".

### 4. Rule 6's view is undefined for representations defined in the session, which is the running example

**Section:** "The rules of the trait world" (rules 6, 7); "An example: a library and its user"; "No performance cliffs".

**Quotes:** "A call in the trait world sees the packages that define its function and the representations involved, with their dependencies, and nothing else: its code is compiled against exactly their methods." — "and the session when nothing depends on all of them." — "colmean(r, 1)                         # 1.5, in a worker compiled once for Ramp" — "**Nothing recompiles under you.** No unrelated load invalidates trait-bound code." — "**Loads cannot change speed.** The methods at an abstract call site change only with their owners (rule 6), so an unrelated load cannot push inference over `max_methods` and turn a fast call dynamic."

**Why it is wrong.** `Ramp` is defined in `analysis.jl`, that is in `Main`. The view of its worker is Columns "with their dependencies" plus the package that defines the representation "with their dependencies": `Main`'s dependencies are whatever the session has loaded, and they change with every `using`. Either the view of a `Main`-defined representation is the whole session, in which case a later `using CairoMakie` is a definition "by one of those packages" and may recompile the worker and push its abstract sites over `max_methods`, exactly as today; or the view is something narrower that the note never defines. The note says "`Main`, the REPL and Pkg are ordinary code" and nothing more. The interactivity and no-cliff guarantees are thus unstated for the one case the note uses to introduce the design.

**Severity:** class 5 (hidden assumption: representations live in packages with fixed dependency sets), bordering class 4.

**Minimal fix.** Define the view of an implementation written in `Main` as the trait package's view plus the implementation's own methods (not all of `Main`'s imports), and say that redefinitions at the prompt recompile as today. If that is not what is intended, say that session-defined representations get plain Julia's guarantees.

### 5. Abstract positions inside trait-world types are closed to downstream trait modules, and the note never says so

**Section:** "Interactivity" (Compiled against what it sees); "The rules of the trait world" (rule 6); "No performance cliffs" (the `Config` example); the second table.

**Quotes:** "A definition elsewhere, for the definer's own types, can never apply." — "Dynamic dispatch from trait-bound code therefore checks that the selected method comes from what the call sees, and raises an error otherwise: a leak becomes an error, never a wrong result." — "abstract types, under concrete mode | no | opt-in: a warning or an error that names the root cause" — "using CBottom: Config                  # a trait module too (rule 1); Config has a field declared Real".

**Why it is wrong.** Concrete mode is opt-in, so a trait-world struct with a field declared `Real` is allowed. Let Q be a trait module that depends on CTop and owns `QNum <: Real` with `*(::QNum, ::Int)`. Q's trait-bound code calls `CTop.scaled_sum(t, Config(QNum(1)))`, a value of a trait-world type with all parts trait-world, which rule 1 permits. CTop's worker for `(Series, Config)` was compiled against CTop's view, which does not contain Q. The site `x * factor(c)` dispatches to Q's method; the dispatch check finds it outside the view and raises. Plain Julia computes the product. "Identical or error" survives, but the note presents the dispatch check as catching *leaks* from ordinary code; here it rejects a legitimate trait-world value from a well-behaved downstream trait module. The consequence, which the note should state as a rule, is that an abstract-typed position in trait-world code admits only values whose methods are in the worker's view, that is from Base and the module's own dependencies, never from anything downstream. It is a real restriction and it changes how one must read "Several trait objects in one function" and the `Config` example.

**Severity:** class 5 (an unstated consequence of rules 6 and the dispatch check), with a class 2 flavour: a scenario the note allows ends in an error where the reader would expect a result.

**Minimal fix.** Add one sentence to rule 6 or to "What code in a trait module may do": "An abstract-typed value inside the trait world can hold only types whose methods are in the worker's view; a downstream module's subtype is refused at the dispatch check, so concrete mode is the practical default."

### 6. The `Config` example contradicts the admission criterion in "Base and the standard libraries"

**Section:** "No performance cliffs" versus "Base and the standard libraries"; "Trade-offs" (3).

**Quotes:** "**Arguments** are translated by their bound at the entry, or admitted only when their type is deeply a trait-world type." — "A value with parts is one when all its parts are, and the check accepts a value when its type decides that: `Vector{Float64}` does, `Vector{Any}` does not." — "function scaled_sum(t::Series, c::Config)" with "Config has a field declared Real" — Trade-off 3: "Arguments from ordinary code must be trait objects, `Callable` functions, or concretely typed values of trait-world types."

**Why it is wrong.** `Config`'s type does not decide: its field is `Real`, so a `Config` may hold a value from above. By the quoted criterion a `Config` is not admitted at an entry, whatever it contains, and `scaled_sum`, an exported function of the top module, cannot be called from ordinary code with any argument. The example is meant to show concrete mode finding a cliff three packages down; as written, the function it reports is uncallable from outside. Either the criterion is wider than stated (admission by type name, with the dispatch check catching leaks later, which is the reading finding 5 assumes), or the entry walks the value (a cost the note never mentions), or the example is wrong.

**Severity:** class 1.

**Minimal fix.** Say which of the three it is. If admission is by type name with the dispatch check behind it, change "admitted only when their type is deeply a trait-world type" to say that, and move the deep-concreteness requirement to representations, where "How a type conforms" already puts it.

### 7. Parametric families: the concreteness check cannot run at the declaration for an abstract-bounded family

**Section:** "Parametric user types".

**Quotes:** "The checks run at the declaration, for the family as a whole, never at a call" — "**Concreteness:** every instantiation must be a concrete representation, so field types may depend on the parameters but are abstract in no other way." — "This avoids a check at the first call of a new instantiation, which would be an error at a call, and conformance derived from what exists at that moment."

**Why it is wrong.** `Series{Real}` is an instantiation of `Series{T} where {T <: Real}` (`T = Real` satisfies the bound), and its field `Vector{Vector{Real}}` is not a concrete representation. So "every instantiation must be a concrete representation" is false of every family with an abstract bound, and no declaration-time check can make it true; the only way to keep the design's promise is to accept the family for concrete `T` and refuse `Series{Real}` when a value of it reaches an entry. That is a check at a call, of the "does not conform" kind the entry already performs, but the note explicitly claims to avoid it.

**Severity:** class 4.

**Minimal fix.** "A family declaration covers the instantiations whose parameters are concrete; an entry refuses any other, as it refuses a type without a projection." Drop "never at a call" for families, or restrict it to the ownership and method checks.

### 8. The four-source closure argument holds on static paths only; doors behind dynamic sites are not found at build time

**Section:** "Base and the standard libraries".

**Quotes:** "A specialization's values come from four places, and each is closed" — "**Calls** return values of specializations checked the same way, Base's and any package's, transitively. A dynamic site inside can select only methods applicable to trait-world values, which by rules 5 and 6 are Base's and owners'." — "A Base function that reaches a door at some specialization falls out there, found when the worker is compiled and named by worker and line".

**Why it is wrong.** The check walks typed code, so it sees the callees of static calls. Behind a dynamic site (any abstract-typed argument, allowed without concrete mode) the selected specialization is not known until run time, and the runtime dispatch check tests who *owns* the selected method, not whether that method reaches a door. A Base method selected dynamically on a trait-world value that reaches `task_local_storage`, `Main` (as `show` on types does through `IOContext`'s default `:module`) or `stdout` is therefore reached without a build-time report. The consequence for "identical or error" is nil (same process state in both worlds), but "each is closed" and "found when the worker is compiled" are true only of the static part of the worker, which the paragraph does not say. The same gap applies to "its author runs the check on the wrapped package at the interface's build": the check is per specialization, so the interface's build can only survey the signatures the author tries.

**Severity:** class 5.

**Minimal fix.** Say that the door check covers static paths and that dynamic sites are reported by concrete mode, which is the reason concrete mode should be on for any module that claims the closure.

### 9. An open `Callable` result type imports inference-dependence into the worker's key; the "one exception" is wider than stated

**Section:** "Function arguments: Callable"; "Identical or error" (One exception).

**Quotes:** "**An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in ordinary code, becomes part of the worker's key, and is checked at every call." — "**One exception.** Element types that Julia derives from inference, such as that of `map` over an empty collection, are answered within the trait world."

**Why it is wrong.** `S` is `Core.Compiler.return_type` of ordinary code, which depends on what is loaded (a method over `max_methods` inside the closure's callees turns `S` into `Any`). Two sessions with different package sets then run *different workers* for the same call, with different speed and, where `S` affects element types downstream, different results. "Identical or error" holds (the result is checked), but goal 3's "The speed of compiled code does not depend on what else happens to be loaded" does not for these workers, and the exception paragraph lists only element types, not `Callable` result types.

**Severity:** class 2, low damage.

**Minimal fix.** Add open `Callable` result types to the exception, and say concrete mode reports `S = Any`.

### 10. Two interface packages with overlapping trees can conflict through their tolerance lists

**Section:** "Interface packages"; "Sealing".

**Quotes:** "two interfaces to one package do not conflict, their surfaces being different traits with different owners." — "It declares the pirates in Makie's dependencies it tolerates, in its project file" — "An interface package's own load checks the tree it seals, and a pirate in it that the package does not declare as tolerated fails that load."

**Why it is wrong.** MakieInterface tolerates pirate X in Makie's tree; a second interface package wrapping a tree that also contains X does not list it. The second load fails, naming X, although nothing about the two surfaces conflicts. The claim "do not conflict" is about traits; the note should not let it cover loading.

**Severity:** class 2, low damage.

**Minimal fix.** "Their tolerance lists are unioned at load" or "the second load fails"; either is fine, but say which.

### 11. Supertraits are relied on by the rules and listed as a possible extension

**Section:** rule 3; "Dispatch"; "Several traits, one projection"; "Possible extensions".

**Quotes:** Rule 3: "or a supertrait whose declared representation map derives the other view." — "Among trait bounds, a subtrait beats its supertrait and more bounds beat fewer." — "`@trait Table{R} <: (ColTable{R}, RowTable{R})`" — Possible extensions: "**Supertraits.** `@trait B <: A` with a representation map lets B's operations call A's statically, and lets a trait object pass where its supertrait is expected (rule 3)."

**Severity:** class 1, low damage. **Fix:** move supertraits into the design or remove them from rule 3, the dispatch order and the bundle trait.

### 12. `Callable`'s third parameter has two meanings

**Section:** "Function arguments: Callable" versus "Keyword, default and variable arguments".

**Quotes:** "`Callable{A, S, M}` carries the mode `M`." — "A function the trait world calls with keywords names them in a third parameter, a named tuple type: `Callable{Tuple{Float64}, Float64, @NamedTuple{tol::Float64}}`."

**Severity:** class 1, low damage (this is parameter semantics, not syntax). **Fix:** a fourth parameter, or keywords inside `A`.

### 13. Measurement claims that disagree with each other or with the prototype

**Section:** "Function arguments: Callable"; "Trade-offs" (7); "Interactivity"; "No performance cliffs".

- "Open: the cost of a dynamic call, which is not yet measured." versus Trade-off 7: "A function from above passed as a dynamic call is an indirect call too, about 4 ns". `poc/world/README.md` (M5) measures 4.0–4.4 ns per element. Class 1; delete the "Open".
- "its first calls 9–10 ms" (Interactivity). README: "A fresh session's first calls of a newly projected type cost 19 ms in `bench_m1.jl`, not the 9–10 ms measured at M1: since M2, Columns' first projection of a session also searches its generic implementation". Stale by the prototype's own account.
- "**Trait operations cost nothing.** ... ran at 1.00–1.01× plain Julia" is the 4096-element figure; the README's 16-element figure for the same benchmark is 2.8–3.0×, and it names a fixed cost of about 110 ns per entry. The note never mentions a per-call entry cost, which bears on goal 4's "minimal performance costs" for small calls. Class 5 (selective reporting).
- "**Types cannot multiply compile cost.** Code compiles per representation, not per user type." versus "An own representation compiles the library's functions once for the type" and "colmean(r, 1) # 1.5, in a worker compiled once for Ramp". For form 2 and form 4 types, each type is a representation and the library compiles per type, as today. Goal 1's "a new user type costs only the little code that is specific to that type" is true of projections only. Class 1; qualify both sentences.

### 14. Trade-off 1 and trade-off 9 disagree about bottom-up adoption

**Quotes:** "Adoption is no longer bottom-up: a trait module may use any package through an interface package" — "Opting in is per module, so a package adopts the design one submodule at a time, from the bottom of its dependencies up."

The first is about using ordinary packages, the second about converting one's own modules, but as written they contradict. Class 1, low. Fix: "Using ordinary packages is no longer bottom-up; offering traits still is."

### 15. Two small facts about Julia

- "In plain Julia, a generic function called on a value of unknown type has no list of targets: it compiles at first use in a session, and crashes a trimmed binary." With `--trim` (default `safe`) the build fails on an unresolved dynamic call; it crashes only under `--trim=unsafe` or `unsafe-warn`, which is what `poc/world/trim/build.sh` uses. Class 3, low.
- "Distributed's `remotecall(f, …)::Vector{Float64}`, whose deserialized result is checked at the boundary": `remotecall` returns a `Future`; the deserialized value comes from `remotecall_fetch` or `fetch`. Class 3, trivial.

### 16. "The prototype checks every row of this table" is overclaimed

**Section:** "What code in a trait module may do".

**Quote:** "The prototype checks every row of this table: rule 3 and the escapes on the typed code of each worker signature, reported with their lines; ownership and imports when the module is defined; ambiguous bounds when it is complete; the rest at the first call of a signature, or while a package image is built."

Against the note's own later statements and the source: the door rows (outward and inward) are design ("the global check and the door list are design"); the sealed-load row is checked by the prototype at the first call of a signature, as a warning by default ("On stock Julia the prototype runs the check with warnings"; `TraitWorld/src/audit.jl`, modes `:warn`, `:error`, `:recompile`), and the audit's own header says a pirate reached through a dynamic call is applied as in plain Julia; the interface-package rows are design. Fix: "checks the rows that are not marked as design".

## Unclear but not wrong

- Rule 1 ("A trait module reaches code outside trait modules only through an interface package") against "Base is in the trait world wholesale, and so is any package a worker reaches: membership is a property of compiled code, not of a package's name." The second reads as automatic admission; the first makes the interface package a required declaration that the check validates. Say that both are needed.
- "The trait half's workers are in the package's trait-world cache, compiled against a closure without Makie." The interface package depends on Makie, so by rule 6's letter Makie is in its view; what keeps Makie out is the check, not the closure. Reword.
- Stdlibs: rule 5 makes Julia one owner, "Base and the standard libraries" seals per stdlib, and rule 6 views per package with dependencies. Verified on 1.12.2: `*`, `inv` and `transpose` on `Matrix{Float64}` are LinearAlgebra's methods on Base's function and types, and LinearAlgebra is loaded in every session. Under rule 6 as written, a trait module that does not depend on LinearAlgebra sees Base's `*` only and errors where plain Julia multiplies. Say whether the sysimage stdlibs are in every view. Also, upgradable stdlibs weaken "of one Julia version ... ship together".
- "Each is closed" (Base section) relies on the runtime dispatch check from the Interactivity section, which the Base section never mentions. Name it there; it is the actual guarantee.
- The entry "sits at `Any` in Julia's method table" and the ordinary fallback `describe(x) = …` is also at `Any`; in Julia's table they are one signature, so the entry must absorb the fallback, and the README says the fallback must come after the bounded methods. The note should say that order matters.
- "the worker is compiled per set of supplied keywords, by name and type, as Julia specializes its keyword sorter". Verified: Julia specializes the sorter per supplied set and the body once (1 body instance for 3 call shapes). A worker that is sorter plus body compiled per set compiles more than Julia does; say which is meant.
- "which `hasmethod` can": true (verified, `hasmethod(f, Tuple{}, (:tol,))`), but for a method with `kw...` it answers true for any name, so the boundary check is weaker than "accepts those keywords".
- The one-line form's "the one field whose type conforms" depends on which implementations are loaded at the declaration; a delegate extension that loads later can make a second field conform, so the inferred projection is order-dependent. Extensions load eagerly when their triggers are present, so this is probably harmless; say so.
- "`ENV` passes" admits mutable process state that a package's `__init__` can change; the central guarantee should say "which methods run", not "what code computes".
- "Trait objects never go up" against "it keeps the trait objects it captured, already projected" for a closure returned up; the closure carries them up as fields. Harmless, since a trait object is a trait-world value, but the table's "stored, returned: no" should say "as a bare value".
- "A delegate is a package extension triggered only by packages its methods mention": with two triggers, the extension loads only when both are loaded, so a method mentioning one of them is absent while only that one is loaded. Say one trigger set per delegate.

## Claims about the prototype or measurements I could not verify

- "the target is a few milliseconds" for implementing a projection (no measurement in the repo; a target, not a claim).
- "In this example that one field makes the loop 74× slower": the 74× is `poc/concrete`'s number for its own example (README M7, design-findings); I did not re-run it, and the note's `CTop` listing is presented as the same program.
- The 2.09 MB binary, "2 builders and 6 workers", 1.00–1.01× and 1.00–1.03×, 7× and 123–128 ms match `poc/world/README.md`; I did not re-run the benchmarks.
