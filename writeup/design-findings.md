# Traits for better Julia: findings, measurements and details

*Layout note, 2026-10-14: `Background/`, `TraitRegions/`, `ecosystem/`, `binary/`, `rung2/`, `spike/`, `reviews/` and `poc/{concrete,errorsplit,reprparam,verifymain}` were moved to `attic/` with the same relative layout; paths below that start with them now live under `attic/`.*

*Rule numbers, 2026-10-15: the note has four rules since rev 1110. Text below written earlier uses the seven: old 1 = 1 (layering); old 2, 3, 4 = 2 (the boundary translates, once per bound); old 5 = 3 (ownership); old 6 and 7 = 4 (what a call sees, and where its code lives).*

Companion to the design note "Traits for better Julia"
(https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20).
The note explains the design; this file holds the evidence, the proof-of-concept
results and the detailed tables. As of 2026-10-13, Julia 1.12.2 unless stated.
Sources: `session-notes/`, `poc/*/README.md`. Numbers come from fresh
processes, mostly single runs.

## 1. Measurements behind the motivation

| Effect | Measurement |
|---|---|
| Specialization on user types | a composed operation across two packages on a new type: 25 ms in plain Julia, 14 ms with regions (X1); Makie's `convert_arguments` recipes: about 167 ms per additional table type (X8) |
| Speculation on the open method table | `using CairoMakie` invalidated 3,539 CodeInstances across the stack on 1.11 (X9); 769 method-table signatures on 1.12 in October (665 in August, before stale caches were rebuilt) |
| Persistence does not rescue it | workload tagging takes 100 dispatch-reached functions from about 460 ms to 0.0 ms per session; one definition in an unrelated package destroyed all 100 (462.7 ms) |
| Minimal example (4 packages, 6 load orders, 2 runs each) | an unrelated package that pirates one function a worker calls brings back 24 of the 42 ms of cold compilation, in either load order; a dominated newcomer costs nothing (1.12 keeps such code); a top-level package that depends on everything is fully precompiled |
| `max_methods` cliff | inference gives up once more than three methods match an abstract call; one method in an unrelated package can push a call over the line |
| Results that follow inference | `map(w, Real[])` returns `Vector{Float64}` until a legitimate `w(::NewReal) = "s"` loads, `Vector{Any}` afterwards (verified on 1.12) |
| Dynamic dispatch has no target list | a generic function on an `Any` element compiles at first use (12 ms) in a session and is a `MethodError` in a trimmed binary |
| Abstract type deep in a hierarchy | a field declared `Real` three calls below a hot loop: 66 ns against 0.9 ns per element with the field typed, 74× (`poc/concrete`) |

## 2. Findings from the prototypes

The August 2026 prototype (TraitRegions.jl, a nine-package ecosystem, a
Rung-2 interpreter, a patched 1.12.2 binary) confirmed erasure and located the
real cost in load-order invalidation. October work on stock 1.12.2 built the
error split, the verifier and concrete mode.

| Finding | Evidence | Consequence |
|---|---|---|
| Compile cost follows representations, not types | X5: 13 types over 2 representations need 2–3 worker instances; X2: workers served from package images before the first call | Erasure works; the per-type cost is the seal |
| A conformer's image can own the workers for its new representation | X2, via `precompile_seal` in the conformer's workload | Basis of image ownership |
| Seals and ops stored as methods serialize and merge with no init code | P0 refactor; Julia refuses evaluation into another module during precompile | Registration is ownership; state is derived at load, not by running code |
| Witness indirection is cheap on coarse traits | X3: static wiring 0.99–1.31× plain Julia; dynamic tables 5.0× at 16 elements, 1.01× at 4096 | Keep traits coarse |
| Workload tagging retains native code | about 460 ms to 0.0 ms per 100 functions, on 1.11 and 1.12; patching the selection policy did not help | Precompile inside `@compile_workload` |
| Load-order definitions destroy tagged code | one later method killed 100 tagged functions (462.7 ms); minimal example: 24 ms in either load order | The central problem |
| Load-time invalidation comes through abstract call sites | `using CairoMakie` on 1.12.2: 769 method-table signatures, none concrete; 217 MethodInstance roots, 216 abstract, the remaining one a validation cascade | What the closed trait world must filter; whether every kill comes from outside the victim's part of the trait world is Gate A |
| Scoping invalidation to trait-bound code removes the cost | patched binary: 456 ms to 0.0 ms after load churn; the global filter was unsound for ordinary code (review #2: plain code was served a sealed answer after the filter was cleared; `invoke` bypassed it) | The trait world recorded per instance, and separate instances |
| Precision fixes are largely upstream already | 57.6% of killed signatures spurious by top match; 1.12 keeps dominated newcomers; verify-before-kill (v6) changes nothing at load | Precision alone will not deliver |
| With precise ownership, real code reaches no pirate | concrete call graphs of `sum`, `sort!`, `Dict`, `show`, broadcast, matrix multiply, ColStats and Makie's `lines` (15,180 CodeInstances, 37,422 concrete edges): 0 pirates; 1,128 without implementer declarations, 493 of them in StaticArrays | The error split is livable with Julia as one owner and declared implementers |
| Trait-bound workers have no abstract call sites of their own | modelled trait mode: ColStats workers 0; `sum`, `maximum`, matrix multiply, `parse` keep concrete return types; `sort!` has 64 abstract sites in its call graph | Workers are concrete; the trait world matters for library code |
| Library code reached from concrete calls is rarely free of abstract edges | 9–22% of compiled code reached from concrete entry points carries abstract-signature edges transitively, mostly through error-path constructors | Why the edge-level rule would need trait-mode copies of much of Base |
| Code behind dynamic calls keeps today's invalidation | `ColStats.colmean` call graph: 203 abstract-signature edges in 2,061 CodeInstances; Makie `lines`: 6,624 in 15,180 | Why the edge-level guarantee stops at dynamic calls |
| Return-type reflection is observable | `map(w, Real[])` changes element type on a legitimate load; every broadcast queries `return_type` | Answer such queries within the trait world (the documented exception) |
| Overlapping seals override each other silently | two packages sealing the same pair: the last one loaded wins, without a warning | Orphan rule for seals |
| Ordinary entries union-split the seal lookup only while few seals exist | with up to three seals a new seal invalidates the entry; beyond that the lookup infers `Any` with no edge | Ordinary callers pay an `Any` return, not invalidation |
| Implementations per representation run at plain speed | `poc/reprparam`, one operation call per element: 1.02–1.03× plain Julia at 4096 elements per column; the seal's own operations 24–35× (19–23 ns per call) | Implement operations per representation; keep a seal's own operations for bespoke behaviour |
| The sealing machinery must obey the rules too | its static registry lookups were invalidated by every package declaring a trait (134 ms at the first seal of a session); `fieldtypes` compiled a closure per visited type (about 70 ms) | Lookups through `invokelatest`; the first seal of a session 314–350 ms to 85 ms |
| At the Makie boundary, erasure is the win | X8 fair rerun: recipes 167, regions 98, hand-written erasure 51 ms per type | Seal cost must come down |
| The error split works on stock Julia | Stage 1 PoC (section 4) | Usable now, with warnings |
| The implementation must obey the rules too | the PoC guard's slow path, called statically, recompiled every entry on `using CairoMakie` (213 ms); behind a dynamic call, 0.0 ms | Runtime support code is held to the same discipline |
| Seal code must be compiled where it lives | conformers without a workload shipped seal code inferred only; the verifier predicted the 5 resulting runtime compiles exactly | `@seal` compiles it into the conformer's image |
| A program's reachable code can be listed | verifier predictions matched runtime compiles in all cases (section 5) | Simple AOT |
| An abstract type in a hot loop can be traced to its root at build time | concrete mode (section 6) | Opt-in concrete mode |

**Withdrawn or corrected.**

- X8's earlier 18 vs 155 ms per type: witness closures were shared across types and registration sat outside the timing.
- "Immortal workers for free" from leaving validity ranges unnarrowed: unsound, it poisons the global cache.
- X4's zero invalidations under churn as evidence for regions: the plain twin also scored zero; only targeted piracy (X10) discriminates.
- X9's diagnosis that Makie's ~240 ms per session is a retention limit: tagging fixes retention; load-order invalidation is the likely cause, not yet confirmed on ColPlots.
- "Compile cost flat in stack size": never measured.
- `ColPlots.histcounts` boxes only `lo` (captured and reassigned), not `w` as first reported.

## 3. Design details

Since doc rev 92 the note states the design as one principle, layering
("ordinary code may use the trait world; the trait world uses only itself"),
and seven rules: 1 layering; 2 projection per trait, at the boundary; 3 bounds
propagate to the boundary; 4 several bounds, several views; 5 one ownership
rule (seals and implementations are methods; ownership is delegated by the
owner, never claimed; checked per applicable signature, so a `Union` is no
loophole); 6 what a call sees; 7 where compiled code lives. The details below
predate that wording: "part of the trait world" is rule 6, the closed trait
world is rule 1, declared implementers and the orphan rule are rule 5, and
the caching table in 3.4 is rule 7. Since rev 99 the note calls a seal a
projection, written `@implement Trait T project(t) = …` (a seal's own
operations: `@implement Trait T dynamic begin … end`); the prototype still
uses `@seal`. The note's section "Working with existing Julia" adds, as design
not yet prototyped: traits over existing functions (capability traits such
as `Indexable` over `Base.length` and `getindex`, conformance declared for
families), defaults and generic implementations, one projection for several
traits, dispatch with types first and trait bounds above `Any`, and the
built-in trait `Callable{A, S}` for function arguments from ordinary code.

Since rev 959 (2026-10-14) the simplest form is `@implement Trait T` with no
body: the type conforms through methods of the trait's operations (it is its
own representation) or through a field `data` whose type conforms (the
projection is the field access); the written-out forms are listed in the
note's "How a type conforms to a trait", under "Finer points" since rev 981.
TraitWorld implements the written-out forms only. Since rev 964 only a trait
module's exported functions carry bounds: internal functions are inferred
from the representations the bounds admit and compiled with the worker that
calls them (rule 3 reworded); linked representations per module were
rejected. Rev 981 adds two subsections under "Finer points": parametric user
types conform as families declared with `where`, checked by coverage at the
declaration, never at a call; keyword and default arguments work as in plain
Julia with defaults evaluated in the worker after projection, the entry
projecting bounded keywords and passing supplied keywords on as a named
tuple, and a third `Callable` parameter naming keywords a function from above
is called with. Rev 984 states the principle behind these decisions at the
head of "Finer points" (rules 1 and 2 read operationally: only values cross
the boundary, each where a bound stands, translated by that bound; code
never crosses, so the trait world never compiles against code from above;
no bound for the way up) and derives varargs (several crossing points with
one bound) and functions that cross (a returned closure is a trait-world
value, a bounded closure has an entry; a `Callable` result is translated by
its bound, so a trait result is projected per call; trait objects never go
up). `@specialize` is unchanged: the worker moves up, the function never
moves down. Rev 988 lets the caller decide the mode of a function it hands
down: `Callable{A, S, M}` carries a third parameter, `DynamicCall` (the
default: a pointer at the signature, the worker compiled once, an indirect
call) or `CompiledCall` (a worker per function type, compiled above as
ordinary code, a direct call the compiler may inline); the bound carries the
library's default, a value wrapped by `compiled_call(f)` or `dynamic_call(f)`
fixes the mode and wins, since neither mode touches the library's cache.
`@specialize` is retired; "static and inlined" was corrected to "a direct
call the compiler may inline". Rev 1004 settles how code not written with
traits in mind is handled. Membership in the trait world is a property of
compiled code, checked on every specialization a worker reaches, Base and
packages alike (globals of trait-world types, no undeclared door, callees
checked transitively), so rule 1 now lets a trait module import any package;
doors have a direction (outward: logging, display, stdout as dynamic calls
upward without an inference edge; inward: eval, deserialization, reflection
only as declared calls with a checked result). Non-trait code is reached
only through an *interface package*, a category of its own: it admits what
passes the check and declares the rest, a trait half with traits, bounded
functions and handles, and an ordinary half of declared calls that also
hides the outside package's globals (Makie above all); BaseInterface is
implicit in every trait module and holds the door list and the curated
traits over Base's interfaces; each standard library has its own. Compiled
code follows rule 7 unchanged. A trait package *seals* itself and an
interface package seals what it wraps: a later definition that would pirate
a sealed package is refused at precompile, load or definition, never at a
call; the opt-out is
plain Julia (recompile the touched signatures, warn), the interim is
everything tolerated. Poisoning at the call (the previous rule) and an
immune trait world were rejected. TraitWorld's layering check stops at Base
and has none of the global check, door list, declared calls or sealing; it
rejects keyword, optional and vararg arguments in trait-bounded functions and
has no mode parameter. Session note 16.

### 3.1 What a later definition does to compiled trait-bound code

| A method defined later by | Effect on a trait-mode specialization |
|---|---|
| a module in its part of the trait world: an owner, a declared implementer, an extension | invalidation and recompilation, as today |
| an outside module, for its own types or functions | none: it can never be selected there |
| an outside module, applicable to that part's types | piracy: the affected code raises `PiracyError` when called |

The trait world is Base, Core, the standard libraries and every package that
has opted in; the closed trait world is the rule that trait-bound code reaches
nothing else. A specialization depends on part of it: the owners of its
function and its argument types, with their dependencies; Julia (Core, Base
and the standard libraries) counts as one owner. Fail-safe: dynamic dispatch
from trait-mode code checks that the selected method comes from the caller's
part of the trait world and raises an error otherwise, so a leaked value of an
outside type becomes an error, never a wrong result. Runtime support needed:
trait-mode CodeInstances with an owner token that native dispatch and package
images honour, the part of the trait world recorded per instance, the
invalidation filter, the dispatch check.

### 3.2 The doors of the closed trait world

- Trait objects enter through seals: the projection turns `t` into a deeply concrete representation; the trait's operations on it come from the representation's implementation (static calls) or from the seal itself (dynamic calls), with argument and result types the trait declares (`@region` asserts the results).
- Ordinary code enters trait mode by calling a trait-bound package with closed arguments: types of trait-bound modules, deeply concrete, no `Any` or function-typed parts. With an open argument the call runs as ordinary code, and so does every ordinary call into Base.
- Base's dynamic entry points stay outside: globals of abstract type (`stdout`, the global logger), `eval`, `invokelatest`, deserialization, `getglobal` with a runtime name.

### 3.3 Ownership and the error split

- **Poison, don't reject.** The method table stays plain Julia's; affected trait-mode code raises `PiracyError` naming the method. Rejecting would not work: `try using X catch end`, backend probing and REPL sessions would continue and compute something plain Julia does not.
- **Uncatchable inside trait-bound code.** Trait-mode lowering of `catch` rethrows `PiracyError`. Ordinary callers of a poisoned entry are invalidated, not poisoned.
- **What counts as piracy.** A method defined outside the part of the trait world some trait-mode code depends on, applicable to that part's types, including one that turns a `MethodError` into a result; redefinition by a stranger (overwriting a method, replacing a binding, redefining a struct). Methods are attributed to the package whose load created them, so `Core.eval(Owner, …)` cannot launder a definition (Julia does not record that today). This replaces Aqua's mention rule and closes its Union loophole.
- **Rules for trait-bound packages.** They may not pirate their dependencies (checked when built). Julia is one owner, so LinearAlgebra's matrix multiply is not piracy. Implementers declare the interface they implement (StaticArrays for StaticArraysCore; superseded: under the note's rule 5 only the owner names a delegate, and who declares a split package's implementations is open, §13); an implementer of a trait-bound package must be trait-bound and joins every part of the trait world that contains its interface.
- **Coherence of seals.** A seal for (Trait, T) may be defined only by the owner of Trait, the owner of T, or an extension of one triggered by the other.
- **Still allowed:** adding methods for your own types to any function; sealing your own types, in packages or at the REPL; redefining your own code; piracy no trait-mode code is affected by.
- **The exception to "identical or error".** Element types Julia derives from inference (broadcast, `map`, comprehensions) are answered within the trait world at compile time; where Julia documents them as inference-dependent (empty `map`), they can differ.
- **Independent of compile state.** The check runs when a definition arrives and whenever trait-mode code is compiled; workloads, first-call order and load order cannot decide whether an error occurs.

| Mode | On a stranger's conflicting definition | Intended use |
|---|---|---|
| error | the affected trait-mode code raises `PiracyError` when called | the target semantics |
| warn | a warning naming the method and the affected code, then recompilation as in plain Julia | the interim; runs on stock Julia today |
| recompile | silent recompilation | a session-level opt-out; owners' own edits recompile in every mode |

### 3.4 Caching and image ownership

| Piece | Compiled | Owner image | Status |
|---|---|---|---|
| Entry | once | region package | works |
| Seal: a projection, and operations of its own if it has any | per type | conformer, at the signatures workers call; or the REPL session | works for package types; REPL types pay at seal time (85 ms in a fresh session) |
| Worker at a canonical representation | per representation | region package | works |
| Worker at a new representation | per representation | conformer, via `precompile_seal` | works when the conformer depends on the region package |
| Worker at a new representation, packages independent | per representation | none today; proposed: an extension triggered by both, or the application's verified build | gap |
| Library code reached from workers | per representation | the image that compiled the worker | needs trait-mode instances retained in images |

Rules: tag everything (compile inside `@compile_workload`); validity per
part of the trait world; separate trait-mode instances, never used by ordinary callers
(package images store no native code for non-default owners today, an
upstream TODO in `precompile_utils.c`); entries, seals and workers exist only
in trait mode and ordinary inference treats them as opaque; compile where the
code lives (a downstream image cannot add native code to an upstream
CodeInstance).

### 3.5 Specialization across trait-bound packages

1. **Calls between regions: no new input.** A worker can call another package's worker directly; the callee is in the caller's part of the trait world. Measured: 0.99–1.31× plain Julia (X3).
2. **Callers that know T: no new input.** Seals return constants, so for a concrete T the lookup folds; an inlinable entry then calls the worker directly. Not yet measured.
3. **Operations in shared workers: implemented per representation (built, section 7).** `@implement Trait{R}` makes the calls static; a seal's own operations stay indirect. Alternatives: `@full_compile` (per type), runtime inline caches (JIT machinery Julia lacks). Speculative splitting over known seals was rejected: sealing a new type would invalidate it.
4. **Traits built on other traits: a new declaration.** `@trait B <: A` with a representation map makes B's calls into A static.

## 4. Stage 1 proof of concept: the error split on stock Julia

`poc/errorsplit/`, TraitRegions `ownership.jl` and `audit.jl`: the ownership
rule, a guard per region op that audits the worker's compiled concrete-edge
call graph, three modes, the orphan rule, `catch` rethrow, a per-op seal cache.

| Minimal example | warn | error | recompile |
|---|---|---|---|
| MyTable alone; Dominated or Legit in either order | 0.0 ms, no warning | 0.0 ms | 0.0 ms |
| Pirate loaded after MyTable | one warning, 36 ms, pirate's result | `PiracyError` after 7 ms, nothing recompiled | 21 ms, pirate's result |
| Pirate loaded before MyTable | one warning, 37 ms | `PiracyError` after 22 ms (compiles to find it) | 18 ms |
| FakeImpl, a declared implementer | no warning, 21 ms | no warning, 21–27 ms | 18–22 ms |
| Orphan seal | warning when the seal is defined | | |

| Nine-package ecosystem | pre-PoC baseline | PoC, warn mode |
|---|---|---|
| First calls, 3 tables × 3 ops | 45–51 ms | 71–73 ms |
| Recompilation after ChurnStorm, after CairoMakie | 0.0 ms, 0.0 ms | 0.0 ms, 0.0 ms |
| Audit findings and warnings, Makie-calling worker included | – | 0 and 0 |
| Audit of everything: first time, then | – | 16–21 ms, then 0.2–0.5 ms |
| `report`, 16 elements: static and dynamic composition | 2,007 and 9,491–10,006 ns | 2,009 and 2,038–2,155 ns |

Lessons: the guard reproduced the central problem on itself until its slow
path moved behind a dynamic call; inlining the dynamic cross-region call made
composition 4.7× faster; registering a region op is formally piracy and must
be exempt; the first audit of each call graph costs about 20 ms per session; the
ownership gap is real (`report` at `Matrix{Float64}`, 35 ms at first call).
Limits: poisoning is emulated at the entry; error mode compiles to discover a
pirate that loaded first; seal code is not audited; the orphan check runs only
when a seal is defined; `Core.eval` laundering is not caught.

## 5. Verified programs and AOT (`verify_main`)

`poc/verifymain/`, TraitRegions `verify.jl`. Calls are classified as static,
bounded (finitely many targets known now), trait (seal lookup, projection,
worker call, witness call), root (a closure the runtime will call), guard, or
hole. A hole is on an error path when every path from it ends in an uncaught
throw.

| Program | Predicted | Compiled at runtime |
|---|---|---|
| Minimal trait main, verified or workload-only build | closed | nothing (0.0–0.2 ms compiler time) |
| Minimal, plain Julia: a generic method on an `Any` element | 1 hole: `plainsum(::Any)` | `plainsum(::AppTab)`, 12 ms |
| Ecosystem, verified build | closed | nothing |
| Ecosystem, workload-only build | 2 workers without native code: `report`, `report_dyn` at `Matrix{Float64}` | the same 2, 44 ms |
| Before the `@seal` fix: verified / workload-only ecosystem | 5 / 7 uncompiled (seal closures) | the same 5 / 7 |

Every prediction matched one for one, with the guard off and in warn mode.
`juliac --trim=unsafe-warn`: the verified minimal program is a 1.9 MB
executable with the same results as a session (80.0 for 4 tables, 236.0 for
7); trim's verifier reports 19 unresolved calls, all trait dispatch or guard
sites. Without the verifier's entry points the binary dies with a
`MethodError`, as does the plain-Julia main; `--trim=safe` refuses trait
dispatch.

Real programs over CairoMakie (normal-path holes): a computation 28 (all in
`histcounts`, the boxed `lo`); `histplot(t::Any, …)` plus render 16 (a
frontier); rendering a concretely typed table 79 (ColPlots 30, Observables 20,
Makie 18, GridLayoutBase 5, Julia 4, script 2). Error-path holes 28–51.

A Fable 5.1 review found three routes to a false "closed" verdict, all fixed
and kept as regression tests: `@nospecialize` on a typevar-typed position;
"cannot return" mistaken for "on the way to a throw" (server loops, `exit`,
recovered exceptions); closures run by tasks and `atexit`. Also fixed: the
`@seal` compile for witnesses with abstract declared argument types, and the
guard being switched off in non-trimmed builds.

## 6. Concrete mode

`poc/concrete/`, TraitRegions `concrete.jl`. Building the top package of a
four-package hierarchy prints:

    Warning: @warn_on_abstract: region op `scaled_sum` at representation Vector{Float64} uses abstract types on its normal path; 1 root cause:
      1. field `scale` of `CBottom.Config` is declared `Real` (CBottom.jl:6)
           3 uses, 2 in loops; first in a loop: CTop.jl:21  *(::Float64, ::Any)
           ← CMid2.factor(::CBottom.Config) returns Any (CTop.jl:21)
           ← dynamic call +(::Any, ::Int64) returns Any (CMid2.jl:4)
           ← CMid1.gain(::CBottom.Config) returns Any (CMid2.jl:4)
           ← dynamic call *(::Real, ::Int64) returns Any (CMid1.jl:4)

Later sessions are not warned again; the loop is 74× slower than with the
field typed. On the ecosystem, nothing annotated, `check_concrete(ColTable)`
(1.3 s for every op and representation): `histcounts` one root (boxed `lo`,
16 uses, 10 in loops); `histplot_naive` traced into
`GridLayoutBase.top_parent`; all other ops clean. One check: 5–27 ms warm.
Limits: only the region's own package's code is checked; a conformer's check
is not kept across sessions; a seal's own operations called in loops are not flagged.

## 7. Representations as trait parameters

`poc/reprparam/`, TraitRegions `@trait Name{R}` and `@implement`. A trait
names its representation, so declarations may depend on it
(`firstel(r::R)::eltype(R)`). Operations are implemented once per
representation as ordinary methods (`@implement Trait{R}`; R may also be
inferred from the annotation of the first argument, from a user type that is
its own representation, or from a user type's `project`). A seal is a
projection; it may still bring operations of its own, called indirectly.
Both kinds coexist at one representation; workers specialize on which one
they get.

Steady state, `total(t, len)` over 4 columns, one `value` call per element
(two runs):

| len | plain Julia | implementation | the seal's own operations |
|---|---|---|---|
| 16 | 37–40 ns | 92–93 ns (2.3–2.5×) | 1,207–1,312 ns (30–35×) |
| 4096 | 14.6–15.0 µs | 14.9–15.5 µs (1.02–1.03×) | 357–376 µs (24–25×) |

A fresh session, `using Columns`, then a new type, its seal and the first
calls of three ops (ms):

| way | seal | first calls | of which compiling |
|---|---|---|---|
| projection onto the library's representation | 113 | 3 | 111 |
| operations of its own at the library's representation | 120 | 11 | 125 |
| own representation with an implementation | 240 | 103 | 337 |

The seal alone costs 85 ms, down from 314–350 ms after two fixes: registry
lookups in the sealing machinery through `invokelatest` (their static edges
were invalidated by every package declaring a trait), and `deep_concrete`
without per-type closures. A first benchmark run compared against a plain loop
whose unused result the compiler dropped; the benchmark now consumes results.

## 8. Trade-offs in full

| Decision | Gains | Pays |
|---|---|---|
| Closed trait world for modules and values | interactivity, AOT and cliff-free speed by construction; Base needs no traits | trait-bound code cannot call ordinary packages yet; arguments from ordinary code must be closed; Base's dynamic entry points are out |
| Compiling within the specialization's part of the trait world | full inference within it; unrelated loads never invalidate; return types fold | runtime support: owner tokens, the trait world recorded per instance, an invalidation filter, a dispatch check; correctness rests on the closed trait world, made fail-safe by that check |
| Error split by poisoning, not rejection | one meaning per call (#54903); the method table stays plain Julia's | trait-bound calls fail in programs that run in plain Julia; a stranger's piracy breaks someone else's code |
| Uncatchable poison | no fallback result plain Julia would not compute | no local recovery from `PiracyError` |
| Erasure at the seal | compile per representation; a new type costs only its seal | a seal's own operations are indirect calls: 19–23 ns each, 24–35× plain Julia for a per-element operation |
| Return-type queries answered within the trait world | no runtime inference and no load dependence | results Julia documents as inference-dependent can differ from plain Julia's |
| Ownership by the trait world; Julia as one owner; declared implementers | one rule for every case; closes the Union loophole | implementers must be declared and trait-bound |
| Separate trait-mode instances | ordinary semantics untouched | Base code used in both worlds compiles twice |
| Orphan rule for seals | seals compose; no silent override | sealing a foreign type for a foreign trait needs the trait's owner, an extension or a newtype |
| Warn first, error later | adoptable now on stock Julia | no latency guarantee in the interim |
| Session-level opt-out; owners always recompile | Revise works on your own packages; monkeypatching stays possible | the switch drops the guarantee for the whole session |
| Concrete mode, opt-in per region or op | an abstract type in a hot loop is reported at its root cause, at build time | 5–27 ms per op and representation; error mode refuses code that plain Julia runs, only slower |
| Implementations per representation, by default | static calls at plain-Julia speed; a seal is a projection | implementations for a Base-typed representation come only from the trait's owner; a new representation compiles every worker it uses |
| Deep concreteness of representations | concrete code in workers | conformers must normalize, for example materialize views |

## 9. Open issues

| Open issue | Why it matters | How to settle it |
|---|---|---|
| Runtime support for trait-mode code | nothing in trait mode can be timed end to end without it | patched binary: an owner token in native dispatch and images, the trait world recorded per instance, the invalidation filter, the dispatch check, poisoning |
| Does the closed trait world account for load-time invalidation? (Gate A) | the interactivity promise rests on it | classify every kill of `using CairoMakie` on stock 1.12: is the invalidating method's module outside the victim's part of the trait world, and does it apply to that part's types? |
| Cost of separate instances | Base code used in both worlds compiles twice | measure compile time and image size; share an instance where inference within the trait world produces the same code |
| Calling ordinary code from trait-bound code | Makie and most of the ecosystem are not trait-bound | a dynamic import that states its assumptions (the note's Possible extensions) |
| Return-type queries | the one exception to "identical or error" | accept the trait world's answer as documented behaviour, or keep plain Julia's answer where it differs |
| The doors of the closed trait world | a leak is an error, but the doors must be specified | the list of Base's dynamic entry points; the closed-argument check; generated functions, opaque closures and reflection |
| Main and the REPL | regions and seals typed at the REPL are trait-bound code in an ordinary module | decide their part of the trait world and their attribution |
| Method attribution | `Core.eval` laundering; Requires blocks; tests and scripts that run in `Main` | a loader-context field on methods |
| How is code poisoned? | image loading activates methods one by one under a lock; ordinary callers are invalidated, not poisoned | implement in the patched binary, with the minimal example as the test |
| Orphan rule versus scoped seals | scoped seals are more flexible but more complex | decide; port MatrixTables as the test case |
| Who receives the error? | a stranger's piracy breaks someone else's trait-bound code | #54903 discussion |
| Ownership gap for new representations | an independent region package and conformer compile their pair at runtime | an extension triggered by both, or the application's verified build |
| Seal cost for REPL types | Python parity needs a few milliseconds; today 85 ms in a fresh session, mostly Julia compiling its reflection | a fast path for interactive sealing that skips inference-based checks |
| Implementations for Base-typed representations | only the trait's owner may implement for `Matrix{Float64}`: centralization, as in Tables.jl | allow package extensions (glue) to implement |
| Load time | Python parity includes import time | measure package-image load times for the ecosystem |
| Inline entries and supertraits | specialization items 2 and 4 are unmeasured or undesigned | prototype both and compare against X3 |
| Concrete mode by default? | opt-in today; warnings for every worker would catch the cliff before anyone opts in | measure false positives on more packages |
| Reach of concrete mode | only the region's own code; a conformer's check is not kept; a seal's own operations in loops not flagged | check trait-bound dependencies too; keep results in the conformer's image; flag a seal's own operations in loops |
| Prototype gaps | multi-object and multi-trait operations, keywords, mutation, associated types | TraitRegions hardening, about a month |

## 10. Staging

0. **Done (Aug–Oct 2026):** package prototype and reviews; seals and ops as methods; nine-package ecosystem; load-order invalidation located; CairoMakie kills classified.
1. **Stage 1, ownership rule and interim tools (PoC built, Oct 2026):** Julia as one owner, declared implementers, orphan rule; on stock Julia the piracy audit with warnings, `verify_main`, concrete mode.
   - *Gate A:* every load-time kill comes from outside the victim's part of the trait world, and none of those methods applies to its types (to measure).
2. **Stage 2, runtime support in the patched binary:** trait-mode CodeInstances in native dispatch and images, poisoning; the trait world per instance, invalidation filter, dispatch check.
   - *Gate B:* minimal example and ecosystem: pirates raise errors, and no other load recompiles any trait-mode code.
3. **Stage 3, compiling within the trait world:** inference sees only the methods of the code's part of the trait world; return types fold; closed arguments checked at entries; Base's dynamic entry points shut; `verify_main` becomes the language's own check.
   - *Gate C:* acceptable cost of separate instances and the dispatch check, and enough real code fits the closed trait world without ordinary packages.
4. **Stage 4, language feature as upstream PRs:** Base designated; enrollment via Project.toml (#54903); warnings become errors; static wiring and inline entries; supertraits, calling ordinary code.

## 11. Other options considered, in full

| Option | Rule | Why not |
|---|---|---|
| Sealed resolution | outside definitions are invisible inside regions | the same call has two answers |
| Edge-level rule | trait-bound code calls ordinary packages freely and speculates only on concrete signatures; abstract call sites become dynamic calls | a built-in cliff at abstract call sites; trait-mode copies of the 9–22% of reached library code with abstract sites below; the guarantee stops at dynamic calls; no closed world for AOT |
| Absorbing dependencies | a dependency joins each package's universe; outside definitions intersecting its edges are errors | two packages that absorb Makie conflict as soon as one defines a recipe for its own type |
| A trait kernel for Base (TraitCore) | regions may call only trait-covered code, Base included | a curated kernel the size of an ecosystem before anything works; unnecessary once Base joins by designation |
| Precision fixes to invalidation | kill only code whose dispatch really changes | largely upstream already in 1.12; does not remove the cost |
| A global invalidation filter | ignore later definitions everywhere | unsound: ordinary code was served answers computed under the filter |
| Runtime inline caches for a seal's own operations | guard on the operation's identity, inline the fast path | JIT machinery Julia lacks |

## 12. TraitWorld: the design of rev 101 on stock Julia

`TraitWorld/` implements the note's design as of rev 101, with Base
capability traits; the packages and every number are in `poc/world/README.md`
(plan: `writeup/poc2-plan.md`). In short:

| | TraitWorld | TraitRegions |
|---|---|---|
| one operation per element, 4096 elements | 1.00–1.01× plain | 1.02–1.03× |
| the same, 16 elements (entry) | 2.8–3.0× | 2.3–2.5× |
| a type's own operations | 6.3–6.4 ns per element, 7.0–7.3× | 19–23 ns, 24–35× |
| generic implementation over `Indexable` against a specific one | 1.00–1.03× | – |
| `Callable`, erased, per call | 4.0–4.4 ns | – |
| first call of a new closure, erased / plain `map` / specialized | 7–8 / 19–20 / 35–36 ms | – |
| a fresh session: projection, implement + first calls | 123–128 + 9–10 ms | 113 + 3 ms |
| first calls with an application depending on both packages | nothing compiled | – |
| concrete mode, the abstract field three packages down | found at build time, 74× | the same |
| `verify_main` + `juliac --trim` of a program choosing its table type at run time | closed, 2.09 MB, runs | 1.9 MB |

Findings that change or sharpen the design:

- **Rule 5 covers an implementation's methods.** An operation that is
  someone else's function may be implemented only by an owner of the function
  or of the representation; the trait's owner declares existing methods
  instead.
- **A type's own operations replace the representation's.** Operations they
  leave out come from the trait's defaults.
- **Delegation is a package extension whose triggers its methods mention.**
  While the extension precompiles, the relation is read from the parent's
  Project.toml.
- **Inference confirms declared conformance only at concrete argument
  types,** and misses fallbacks that throw on some paths. Structural
  conformance would accept `Int`, `Char`, `Pair`, `NamedTuple`, `String`,
  `Dict` and `Matrix` where they mean something else.
- **Check results live where rule 7 places the code:** a flag per worker
  signature, embedded in a generated function's compiled code.
- **The machinery obeys the design:**
  - no edges from registry lookups;
  - reflection behind dynamic calls;
  - its own workload;
  - entries analyzed at their call sites for AOT.

Limits on stock Julia:

- Rule 6 is the audit, and rule 3 is checked on typed code at first use.
- Keyword arguments and varargs are not supported in trait-bounded functions.
- Dynamic operations hold run-time pointers, so not in a closed world.

**Review.** An adversarial review (Fable) of TraitWorld found ten bugs and
several overclaims, all fixed and tested; the table is in
`poc/world/README.md`. Three sharpen the design:

- a trait object returned to ordinary code is an escape like any other;
- the fallback of a function with trait-bounded methods is the most specific
  ordinary method of any shape, so adopting a trait method never changes a
  call that worked;
- ownership counts a lower-bounded type variable only for a trait object's
  traits.

## 13. Interface packages around DataFrames and Makie

The interfaces proof of concept (`poc/interfaces/`, plan
`writeup/poc3-plan.md` with its review corrections §9–§10, sessions 18–20)
extends TraitWorld by keyword, default and variable arguments, `Callable`
modes, the one-line conformance, interface packages with declared calls and
handles, the door check and sealing, and connects Columns and Stats to the
real DataFrames.jl 1.8 and CairoMakie 0.15. Every number is in
`poc/interfaces/README.md`. In short:

| | trait world | plain Julia |
|---|---|---|
| `summarize(df)` after `using` the stack and both interfaces, first call | 2.1–2.8 ms, nothing compiled | 76 ms |
| an entry's first call at a keyword type the image lacks | 0.9 s, mostly recompiling the per-signature check after Makie's load | 46 ms |
| first bars from the trait world's bins, first render | 1.07 s, 1.19 s: Makie's own first-plot costs behind declared calls, a third to a half of it recompilation despite the interface's workload | not comparable (13.4 s without a workload) |
| a new type at the REPL: declaring conformance / first result / first plot | 540–680 / 10–14 / 25–31 ms | 0.6–0.7 / 39–45 / 58–65 ms |
| marginal cost per additional type (X8) | 35–41 ms | Makie recipe 297 ms, hand erasure 36 ms |
| `using ChurnStorm` / `using CairoMakie`: trait-stack instances invalidated | 0 / 64, all check and macro code; no entry, worker or builder; next calls compile nothing | – |
| a worker redefined in the session | its dependents in Reports and TraitWorld only; next call 0.86 s, mostly recompiling the check code | – |
| a pirate of a sealed package, either load order | deleted at the load, `PiracyError` logged; tolerated: plain Julia's answer | – |
| pirates of what is sealed | sealing Makie's whole tree (before the rework): 49 after built-in implementer declarations, 1091 without; sealing over views (after): 20 with DataFrames wrapped and Makie called (OffsetArrays 12, StatsBase 4, Tables 4), the core wrappers' delegates absorbing StaticArrays' 511 and 212 of Colors, ColorVectorSpace and ImageCore | – |
| sealing scan per top-level `using`; demo load | 0.02–0.81 s (one global method table); 4.1 → 6.1 s | – |
| `verify_main(App.main)` (CSV, DataFrames, Makie) | no hole in the trait stack, 5 declared targets (not walked); 140 holes in the ordinary code (CSV 112, Base 17, DataFrames 11) | – |
| `juliac --trim` of the trait-world pipeline | 3.53 MB, 39 warnings (10 the entry's two dynamic steps to registered targets, 26 skipped paths, 3 `__init__`, none in the pipeline's code), runs | – |

Findings that change or sharpen the design:

- **Core and implementation packages are most of the piracy in a real
  tree, and rule 5 needs an answer for them.** Of 1091 methods in Makie's
  dependency closure that pirate what the interface seals, 1042 come from
  packages split into a core of types and functions and an implementation:
  StaticArrays on StaticArraysCore (794), ColorVectorSpace, Colors and
  ImageCore on ColorTypes (226), StatsBase on StatsAPI (22). TraitWorld exempts
  them by implementer declarations it makes itself (`DEFAULT_IMPLEMENTS`),
  as this file's §3 once put it ("implementers declare the interface they
  implement"); the note's rule 5 allows only "a delegate one of them
  names", the owner naming. Either the core package names its
  implementations (StaticArraysCore names StaticArrays), or an interface
  tolerates them, which would make the tolerations lists long and the
  sealing of real trees mostly nominal. Explained in the note at rev 1022
  (Sealing, trade-off 2) as an open problem, and resolved at rev 1058: a
  trait wrapper of the core names the implementations among its own
  dependencies, so they are loaded whenever the core's types can enter the
  trait world and count as the core's delegates. The PoC has
  StaticArraysCoreWrapper and ColorTypesWrapper and no built-in list. The remaining 49 methods from 10
  packages are a sibling package's generic function on Base's types
  (DataAPI's `nrow` on `NamedTuple`, AbstractFFTs' plans on `Array`,
  `getindex` on Base's ranges), which the interfaces tolerate; a package
  outside every wrapped tree (CSV's Durations, pirating `Dates`) is
  tolerated by the project.
- **An extension's triggers confer no ownership** (adopted in the note at
  rev 1022, rule 5): CompositionsBase's InverseFunctions extension defining
  `InverseFunctions.inverse(::Base.Splat{typeof(∘)})` is the orphan case,
  arising from aliasing a Base value instead of defining a type; counting
  triggers as owners would let two parents' extensions with the same
  trigger implement the same method, the conflict rule 5 prevents.
- **The machinery must have no static edge into Base's generic code.**
  An entry's error path that formatted its message by broadcasting over a
  `Vector{Any}` gave every entry an inference edge into `string`,
  `convert` and `promote` at abstract types; `using DataFrames`, `CSV` and
  `CairoMakie` each invalidated every entry through it. Message formatting
  and reflection only behind `Base.inferencebarrier` (`@noinline` is still
  a static edge), typed loops instead of generic reductions on untyped
  containers. After the sweep no entry, worker or builder is invalidated by
  any of these loads. A requirement on the runtime's entry code (trade-off
  8), not a change to the rules.
- **The checks are not immune, and that is the price of new signatures
  after a big load.** The rule-3, door and concrete checks and
  `@implement`'s macro code are reflection over the compiler; Makie's tree
  invalidates them (64 instances), so the one-line conformance costs
  0.5–0.7 s once Makie is loaded (0.12 s without), and so does an entry's
  first call at a keyword type the image lacks (0.9 s, plain Julia 46 ms).
  The compiled code for a new type is cheap (10–14 ms first result); the
  declaration and the per-signature check are not, on stock Julia.
- **A foreign type conforms through a delegate, by type.** `DataFrame`
  conforms to `ColTable` in an extension of Columns (rule 5), projecting to
  the DataFrame's own column vectors as `Vector{Vector{Float64}}` and
  refusing other column types by name; a projection to
  `Tables.columntable`, whose type varies per value, would compile a worker
  per column-type tuple at first call.
- **Declared calls return library objects as handles.** Makie's mutators
  return plot objects; a declared call's result crosses only as a handle.
- **On stock Julia refusal is deletion after the load, and so depends on
  the load order.** Base swallows exceptions from package callbacks, so a
  pirate's methods are deleted and a `PiracyError` logged, in either order;
  but an interface's tolerations count only from its own load, so a member
  of its tree loaded before the first trait package loses methods the
  interface would tolerate. The note's semantics (the seal's load fails)
  have no such case.
- **Sealing's scan is cheap with one global method table.** Julia 1.12
  keeps every method in `Core.methodtable`; visiting it, filtered by
  `primary_world`, costs 0.03 s with Makie loaded, and the full scan with
  ownership checks 0.02–0.81 s per top-level `using`. Walking the bound names
  (Aqua's way) took 2.3 s and missed call methods of callable types;
  everything the scan asks per method (ownership, extension parents) must be
  cached.
- **`verify_main` predicts where a trimmed binary dies.** Two binaries of
  the pipeline built and died at their first dynamic call, `readdlm`'s
  options and `readlines`' `ondone` closure; both were normal-path holes of
  the ordinary code in `verify_main`'s report. With them removed the binary
  runs, through the entry's two dynamic steps per call whose targets
  `verify_main` registered, and the quarantine is as planned: the trait part
  trims, and what DataFrames, CSV and Makie need is the ordinary code's
  business.

Limits:

- The door check is static on stock Julia: an inward door behind a dynamic
  call is not seen (the design checks a dynamic call's target when it
  compiles). Its walk into Base has a budget, whose end is warned.
- All standard libraries count as Julia, so `Pkg`, `REPL`,
  `InteractiveUtils` and `Test` are in the trait world, which the note
  counts as ordinary code.
- Outward doors are not bound to the application's declared sinks;
  declared targets with keywords are listed without their keywords; the
  code behind declared calls is not walked by `verify_main`.
- The untrimmed juliac build of the full application needs more memory
  than the 30 GB machine had free (about 14 GB more, at LLVM's code
  generation of the whole image); not built.
- Parametric user types, `Callable`'s keyword parameter and the capability
  traits' move into BaseInterface are not done.

**Review.** An adversarial review (Fable, session 20) found 18 items: four
bugs (call methods of callable types missed by the scan; the door budget's
end silent; compile time double-counted in the scripts; `repr` as an outward
door), all fixed and tested (191 tests, one `@test_broken` for the dynamic
door); overclaims about the implementer exemptions, the trimmed binary's
warnings, "closed" and the first-plot comparison, all corrected in the
README and above; and gaps now listed as limits. Not fixed: refuse mode's
order dependence, `_manifest_closure`'s silent fallback without a manifest
entry, keyword-less declared targets, the Union cap in
`_sig_alternatives`. The list is in `session-notes/2026-10-15-20-crash-recovery-and-m8.md`.

**Rework for the note at rev 1110** (session 20). The PoC follows the note:
`@interface_package` is gone; `@call` and `@handle` work in any trait module,
the calls held by the ordinary module around it (MakiePlots); `@trait_wrapper
Pkg Impl…` brings a package in, names its implementations as delegates,
reads its tolerations and seals the package, the implementations and their
dependencies (DataFramesWrapper, StaticArraysCoreWrapper, ColorTypesWrapper);
a second wrapper for a package is refused at its load; trait packages and
wrappers are the only things that seal, so Makie, behind declared calls, is
not sealed. The scan audits 20 methods with DataFrames wrapped and Makie
called. Wrapping ColorTypes surfaced two findings the closure-wide sealing
had hidden among tolerations: ImageCore's `showarg` methods at other
packages' types, which naming ImageCore does not cover, and PlotUtils, loaded
with Makie as ordinary code, pirating ColorTypes once it is sealed; wrapping
a core makes the pirates of it visible in every tree loaded beside the
wrapper. 199 tests, one `@test_broken`.

## 14. Earlier forms of the design

Moved from the note's "Other options considered" at rev 1110, so that the note lists only the alternatives a new reader would propose. Rule numbers in this list are the note's current ones.

- **Region blocks inside ordinary modules:** the first prototype's `@region`. Replaced by trait modules, because every rule of the design applies per module, and a block over one trait cannot declare the traits of several arguments.
- **A closed trait world stated per module:** each trait module checked against its own imports. Replaced by layering, a property of the dependency graph that also says where compiled code lives.
- **Making outside definitions invisible inside trait-bound code,** called sealed resolution in an earlier version: rejected because the same call would have two answers, and rejected again on 2026-10-14 as an immune trait world, because one method with two versions disagrees silently across the worlds through `hash`, `isless` or `convert` on values that cross. Sealing now names something else: the enforcement of ownership over what the trait world compiles against.
- **A trait layer for all of Base:** wrap Base in traits before anything works. Unnecessary once Base joins the trait world by designation; capability traits cover only the interfaces that conformance needs.
- **Linked representations per module:** `@trait_module Table{R} with ColTable{R}, RowTable{R}`, one representation for every function in a module. Rejected: a bundle trait links per function already, and a type links by one field whose type implements both; a module-wide link would make every function require conformance to both, which loses adoption one trait at a time, and a module generic over one representation cannot express a function over two, such as `meandiff(a::ColTable, b::ColTable)`.
- **Poisoning pirated code at the call,** an earlier version of this note: the affected worker kept its code and raised when called. Rejected because it fails late and the retained code can never run; refusing at the load fails first.
- **Interface packages as one kind of package** (until rev 1022): a package that admitted another package's code, declared calls into it, sealed its whole dependency tree and tolerated its pirates. Split in two because the jobs differ: admitting decides what trait-world code compiles against and needs one authority per package, a trait wrapper; declaring calls decides nothing and needs no category. Sealing the whole tree behind declared calls bought policy only, not caching, AOT or identical results.
- **Implementation packages declaring themselves** (the prototype's built-in list, StaticArrays implements StaticArraysCore and six more): a claim, which rule 3 forbids. Cores naming their implementations upstream is the right authority but not enough alone: a core cannot depend on its implementation, so nothing would load it when the core's types enter the trait world; the wrapper's dependency does.
- **An allowlist of trait-compatible Base:** rejected; Base's functions call each other, so the list would be transitive and per version. The check on compiled code with a door list is automatic and follows each version by itself.

## 15. Caching per representation, and Makie (session 21)

The goal stated by the user: installing a package precompiles its
trait-bound code; a representation it has never seen is compiled once and
cached; every later session takes that code from the cache. Measured in
`poc/interfaces/README.md` ("View caches", "Could a Makie in the trait world
be cached fully?").

| Finding | Evidence | Consequence |
|---|---|---|
| Rule 4 gives the cache key | a worker's view is the owners of what its signature names; `TWView_<hash>` packages depend on exactly those | caches are keyed by packages and versions, not by session or load order; recording needs no `--trace-compile` (the entry's check notes each new signature) |
| Cached trait code survives every load order on stock Julia if its Base calls are concrete | `UserTypes.Ramp` through Reports: first calls 3.1–3.3 ms with CSV and Makie loaded before, after or not at all (106–1188 ms without the cache) | view caches work on stock Julia for code that keeps the machinery's discipline |
| The machinery must keep that discipline too | `_witness`'s error message (`first.` over `Vector{Any}`) failed every builder at image validation when CSV loaded first (172 ms); fixed with an inference barrier | each such edge is found by tracing the validation log of `@snoop_invalidations` to its root signature |
| An abstract call in a worker loses its cache in both orders on stock Julia | `report` (`push!(::Vector{String}, ::Any)`): 30 ms in both orders, by insertion when CSV loads after and by image validation when it loads before | the filter needs a load-time half |
| The load-time half works, including Base callees | patched `base/staticdata.jl`: `report` 5.6–6.2 ms in both orders (lean 5.5 ms); a Base callee that fails only through outside, owned methods stays invalid for ordinary code but no longer takes its trait-world caller with it | the residual of §13 (Base code shared with ordinary code) is solved at the caller's edge, not by separate Base instances, for code compiled into images |
| Makie's ad-hoc recompilation is an ownership problem | Makie's tree treated as trait-world code (x13): the first PNG 8.5–8.9 s instead of 15.7–16.2 s in both load orders; Makie recompiles nothing; what remains is CSV×DataFrames (2.4 s, a combination no image holds) and `barplot`'s first `plot!` (0.24 s, outside Makie's workload) | a Makie in the trait world could be cached fully, modulo coverage; its per-user-type cost goes to the projection at its boundary |
| What a trait-world Makie must change | per-argument-type specialization of `_create_plot!`/`convert_arguments` (the projection instead), attribute values of trait-world types, Dates/Unitful/Categorical as implementations, user callbacks as calls upward, one pirate removed | ComputePipeline's typed edges and `invokelatest` need no change: inside the trait world their types form a closed set |
| What caching cannot remove | the load (5.4–5.7 s, CairoMakie the bulk), `__init__` work (fonts, FreeType), GPU shader compilation | merged images or a system image are a separate question |

Open: types of the session itself (modules under `Main`) and of package
extensions get no view cache, because no package can depend on them (step 4,
deferred by the user). Concurrent sessions flushing the same view: the last
writer wins, and the other's new signatures are recorded again next time.
The `JULIA_TW_PROTECT` experiment only grants Makie's tree the filter's
protection; it does not rearchitect Makie. That is sound only because
MakiePlots passes Makie plain vectors and strings.
