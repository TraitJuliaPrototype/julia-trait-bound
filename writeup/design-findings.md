# Traits for better Julia: findings, measurements and details

*Layout note, 2026-10-14: `Background/`, `TraitRegions/`, `ecosystem/`, `binary/`, `rung2/`, `spike/`, `reviews/` and `experiments/{concrete,errorsplit,reprparam,verifymain}` were moved to `attic/` with the same relative layout; paths below that start with them now live under `attic/`.*

*Rule numbers, 2026-10-15: the note has four rules since rev 1110. Text below written earlier uses the seven: old 1 = 1 (layering); old 2, 3, 4 = 2 (the boundary translates, once per bound); old 5 = 3 (ownership); old 6 and 7 = 4 (what a call sees, and where its code lives).*

Companion to the design note "Traits for better Julia"
(https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20).
The note explains the design; this file holds the evidence, the proof-of-concept
results and the detailed tables. As of 2026-10-13, Julia 1.12.2 unless stated.
Sources: `session-notes/`, `experiments/*/README.md`. Numbers come from fresh
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
| Abstract type deep in a hierarchy | a field declared `Real` three calls below a hot loop: 66 ns against 0.9 ns per element with the field typed, 74× (`experiments/concrete`) |

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
| Implementations per representation run at plain speed | `experiments/reprparam`, one operation call per element: 1.02–1.03× plain Julia at 4096 elements per column; the seal's own operations 24–35× (19–23 ns per call) | Implement operations per representation; keep a seal's own operations for bespoke behaviour |
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

`experiments/errorsplit/`, TraitRegions `ownership.jl` and `audit.jl`: the ownership
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

`experiments/verifymain/`, TraitRegions `verify.jl`. Calls are classified as static,
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

`experiments/concrete/`, TraitRegions `concrete.jl`. Building the top package of a
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

`experiments/reprparam/`, TraitRegions `@trait Name{R}` and `@implement`. A trait
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
capability traits; the packages and every number are in `experiments/world/README.md`
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
`experiments/world/README.md`. Three sharpen the design:

- a trait object returned to ordinary code is an escape like any other;
- the fallback of a function with trait-bounded methods is the most specific
  ordinary method of any shape, so adopting a trait method never changes a
  call that worked;
- ownership counts a lower-bounded type variable only for a trait object's
  traits.

## 13. Interface packages around DataFrames and Makie

The interfaces proof of concept (`experiments/interfaces/`, plan
`writeup/poc3-plan.md` with its review corrections §9–§10, sessions 18–20)
extends TraitWorld by keyword, default and variable arguments, `Callable`
modes, the one-line conformance, interface packages with declared calls and
handles, the door check and sealing, and connects Columns and Stats to the
real DataFrames.jl 1.8 and CairoMakie 0.15. Every number is in
`experiments/interfaces/README.md`. In short:

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
`experiments/interfaces/README.md` ("View caches", "Could a Makie in the trait world
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
| Machine code generated by a downstream workload for an upstream code entry is dropped | the juliac binary compiles 60 methods at run time (0.27–0.32 s); 26 of the 32 resolvable had inferred code cached but no machine code, 18 of them from Julia's system image; replaying them at build time: 0.012 s, whole process 0.69 s against Python's 0.57–0.67 s | rule 4 places that code in the downstream image; Julia keeps only entries a package creates |
| Makie is close to a wrapper for sealing, far for closure by construction | x14: wrapping Makie adds 46 pirates, nearly all core/implementation pairs a wrapper resolves by naming the implementation, plus one real pirate; `verify_main` stops after 4–246 instances per call at `Any`-typed dispatch; x15: 1,940 distinct dynamic-dispatch targets per first plot, 1 more for a second plot with other data | sealing needs four more core wrappers; closure needs typed values into ComputePipeline; in practice a recorded workload covers it |
| What caching cannot remove | the load (5.4–5.7 s, CairoMakie the bulk), `__init__` work (fonts, FreeType), GPU shader compilation | merged images or a system image are a separate question |

Open: types of the session itself (modules under `Main`) and of package
extensions get no view cache, because no package can depend on them (step 4,
deferred by the user). Concurrent sessions flushing the same view: the last
writer wins, and the other's new signatures are recorded again next time.
The `JULIA_TW_PROTECT` experiment only grants Makie's tree the filter's
protection; it does not rearchitect Makie. That is sound only because
MakiePlots passes Makie plain vectors and strings.

## 16. Between nested types and `Any` (session 21)

The question (the user's): typing everything in classic Julia leads to deeply
nested parametric types, C++ template style, with massive compilation; keeping
things at `Any` or abstract types keeps types sane but loses what a value
carries. Does the trait system let a complex system such as Makie escape that
choice? The note's answer is the section "Between nested types and `Any`" at
the head of "How the concepts achieve the goals" (rev 1112, revised at rev
1116 after a Fable review, below). This is the long form.

**Answer.** It escapes the forced choice, not the trade-off. The position is
chosen per conformance and per call mode instead of per field, and in every
position the code above a bound keeps the contract. Nesting ends where a
conformance projects or a position is dynamic. What stays is the cost, at
each position, of having many representations: more compiled code, a copy,
or an indirect call. What is new over plain Julia, which can reach the same
shape by discipline, is enforcement, targets closed by ownership, and the
placement of per-type code (16.3).

### 16.1 The dilemma, counted

A concrete Julia type is data; what can be done with a value lives in
methods that any package can add or change, and an abstract type names
intended behaviour without checking it (the user's correction, session 22,
of the first framing here, "a type carries contract and representation in
one"). Code is fast where it is compiled for concrete types, so the
concrete type must be known where the inner loop is compiled, and every
signature and type parameter above carries it. A trait bound is an abstract
type that guarantees concreteness: the conformance chooses a deeply concrete
representation and the worker is compiled for it, so the signature need not
carry the concrete type. Take layers 1…k, where layer i adds a type that holds
a value of layer i−1 as a parameter, and nᵢ variants occur at layer i:

- **Parametric throughout:** code at layer k compiles for up to n₁·n₂·…·nₖ
  types (those that occur). The types themselves grow with k.
- **`Any` at layer j:** code above j compiles once, but a call on the value
  is dynamic and its result is `Any` unless the function has at most
  `max_methods` applicable methods or the caller asserts it. The targets
  still compile, per runtime type, when first reached. Any load can add a
  target, and no static analysis lists them.
- **Trait world:** code at layer k compiles per tuple of the
  representations at its own bounds. Within one function that is still a
  product over its bounds (`meandiff` per pair). Across layers it is a sum:
  a conformance that projects maps every variant below onto representations
  the layer chose, a dynamic position onto one worker, so the product
  restarts. It continues only by choice, in the chooser's image: a type
  that is its own representation, a parametric family (one worker per
  instantiation), a generic implementation (every conforming family becomes
  a representation), a representation that is itself a family over lower
  representations, a compiled call, and a dynamic call with an open result
  type (part of the worker's key, inferred above).

### 16.2 The positions

| Position | Compiled | A call on the value | Compiled for | A load elsewhere | Measured on the prototype |
|---|---|---|---|---|---|
| Julia: a type parameter | per nested type | direct | the whole type | can invalidate it | session 20: an ad-hoc session recompiles about 13 s of Makie code that CSV's dependencies invalidate (an ownership problem, §15) |
| Julia: an `Any` field | the caller once, each target per runtime type when first reached | dynamic, result `Any` unless asserted | nothing | can add targets | x15/x16: about 1,900 targets per first plot, 35–84 more per new argument type or attribute shape; compiled at run time unless a workload recorded them |
| own representation (`@implement T` by methods) | the library per type, in the conformer's image | direct | the type, reached through its operations | changes nothing (rule 4; on stock Julia only for workers whose Base calls are concrete, §15) | `Ramp`: 1.7 ms first call from its image, 3 ms from a view cache |
| projection (a field, a written projection) | the projection per type, the library per representation | direct | the representation | changes nothing (rule 4) | `Measurements`: 1.4 ms first call; x8: 35–47 ms per new type (the declaration's checks) |
| dynamic operations (`@implement … dynamic`) | the library once per set of dynamic operations (`Dyn{NT, ops}`), in the conformer's image | indirect, declared result type | the shared representation | changes nothing (rule 4) | 6.3 ns per operation (7× plain Julia per element); `Reversed`: 107 ms first call in a fresh session (the pointers are made then), `colrange` outside the workload 84 ms |
| dynamic call (`Callable`, the default) | the library once per signature, the function by its caller | indirect, declared result type | the signature | changes nothing (rule 4) | 4.0–4.4 ns per call; first call of a new closure 7–8 ms |
| compiled call | per function type, in the caller's image | direct | the function's type | can invalidate it, as today | first call of a new closure 35–36 ms |

One more position exists inside a trait module: a field of an abstract type
or a union holding trait-world values the module made. It is allowed. Its
dispatch is closed by ownership (rule 4's dispatch check: only owners and
delegates of the function or the argument types), so no load from outside
adds a target, and `verify_main` lists the targets where every method is for
a concrete type. But results are not inferred, and concrete mode reports it
on a normal path. It is `Any` without the openness, not without the
information loss, and it is what a trait-world Makie would use for
attributes with several representations (16.4).

### 16.3 Why the dynamic positions are not `Any`, and what is new over discipline

Design:
1. **Results are declared.** A trait operation has a declared result type,
   asserted at the call, and a `Callable` has `S`. The code after the call
   infers concretely; the dynamic part is one call wide.
2. **Targets are closed and listed.** The targets of a dynamic operation are
   the conformances; of a dynamic call, the functions passed at the declared
   signature. Both come only from owners and delegates (rule 3), so no load
   from outside adds one, and a build can enumerate them.
3. **Targets are compiled ahead.** An operation's code is compiled with its
   conformance, in the conformer's image; a function's at its declared
   signature by the caller.
4. **What is lost** is the direct call: no inlining across the position, a
   few nanoseconds per call. It belongs where calls are coarse.

Prototype (verified in the review): items 2 and 3 hold for dynamic calls and
not for dynamic operations. `verify_main` classifies a `Callable` site as a
trait site with enumerated targets (the wrapper per function type), and in a
closed world `enter_callable` passes the function itself, so a build compiles
it as a direct call. A dynamic operation is an `Erased` `ccall` through a
`@cfunction` pointer made at the type's first entry in each session
(`implement.jl`, `core.jl`): `verify_main` skips the `:foreigncall`, so a
`main` over `Reversed` is reported closed with the user's operations in no
target list, and the first call costs 107 ms in a fresh session against
1.4 ms for a projection. `experiments/world/README.md` already says a closed world
should use implementations. An image cannot hold such a pointer; compiling a
dynamic operation into an image needs another mechanism (16.6).

Plain Julia can reach the same shape by discipline: convert to a few
concrete types first, assert results after dynamic calls. x8 measures it: a
hand-written convert-then-plot function costs 36 ms per new table type, the
trait route 35–47 ms, Makie's recipe route 297 ms because `_create_plot!`,
`conversion_trait`, the dim converts and `preferred_axis_type` see the
user's type before `convert_arguments`. So the per-type compile cost is not
what the design adds. It adds:
1. **Enforcement.** The bound is the only place the user's type is seen;
   nothing before the projection can specialize on it.
2. **Closed, listed targets** for the dynamic positions (rule 3), where an
   assertion after a dynamic call in plain Julia leaves the targets open.
3. **Placement.** Code compiled per type lives in the image of the package
   that chose the type (rule 4), where no other load invalidates it, so the
   per-type position costs build time and disk rather than session latency.

"Sane types", the other half of the question, is not answered by the
prototype: a worker's stack frame prints as
`colrange(t::TObj{ColTable, Tuple{TraitWorld.View{ColTable, TraitWorld.Impl{(:firstcol,)}, Ramp}}}, i::Int64)`,
and for dynamic operations the `Dyn{@NamedTuple{…Erased…}}` witness is
longer. The design should print a worker as its bound and representation,
as concrete mode's messages already do (`scaled_sum` at Series at
Vector{Float64}).

### 16.4 Makie as the worked case

Makie keeps `Observable{Any}`, `Dict{Symbol,Any}`-style attributes and
`invokelatest`, among other reasons because parametrizing them would compile
per combination of user argument types, attribute value types and plot
types, and because an attribute's value can change type over time
(`plot.color = :red`, then a vector). x15 and x16 measure what that `Any`
hides: a stable core of about 1,900 dynamic-dispatch targets per first plot,
one more for other values of the same types, and 35–84 more for each new
argument type or attribute shape (x16: `Vector{Int}` data 64, a range and a
vector of colors 35, an `RGBf` 41, a numeric color with a colormap 84). The
core is what a recorded workload covers today; the fringe is the per-type
code a trait-world Makie must place.

Makie computes on families of its own, not single types. Positions are
`Point{N, Float64}` for `Float64` and integer data and `Point{N, Float32}` for
`Float32` and small integers (`float_type`, conversions.jl), converted to
`Float32` only at the backend with a linear rescaling (`Float32Convert`):
Makie once converted everything to `Float32` and had to stop, for
precision, which is 16.6 item 2 observed in the field. `to_color` returns
five shapes (a `Float32` to colormap, `RGBA{Float32}`, `Vector{RGBAf}`,
`Vector{Float32}`, or a pattern or palette), with different downstream
semantics: a numeric color goes through `colorrange`, `colormap`, `lowclip`.
One representation per attribute would lose that, and a concrete record per
combination of shapes would be a product across forty attributes, worse
than the product across layers. So an attribute with several shapes is the
inside position of 16.2: a field whose type is a union of Makie's own
representations, dynamic inside, closed by ownership, its code compiled per
representation in Makie's images. ComputePipeline already works that way:
each edge is compiled per its inputs' types and the graph is dynamic between
edges.

| Makie today | Variety | Trait-world position |
|---|---|---|
| `convert_arguments`, `_create_plot!` and the code before conversion, specialized per user argument types (297 ms per table type, x8) | user data types | bounds on data arguments that project onto Makie's position families (`Vector{Point{N, Float64}}`, `Vector{Point{N, Float32}}`, …); the projection compiles per user type in the conformer's image; Dates, Unitful, categorical values as implementations |
| attributes and observables at `Any` (Base: `setindex!` 159 targets, `map` 47) | attribute shapes (`:red`, `"red"`, `RGBf`, a vector of colors, numbers with a colormap) | a bound per attribute projecting onto Makie's shapes; a field typed as a union of them, the inside position (16.2) |
| ComputePipeline `TypedEdge` per Makie closure and value types (656 targets; 14–22 more per new type or shape, x16) | closures × representations | closures are Makie's, value types its representations: a finite list per representation, compiled into Makie's images (a conformer's for an own representation) |
| recipes | user plot types | a downstream trait module's methods of `plot!` for its own plot type, selected at a dynamic site inside Makie and accepted by the dispatch check (rule 4), compiled in its image |
| `on(f, obs)`, `lift`, user transforms and colormap functions | user functions | `Callable`s, dynamic calls by default |
| backends (CairoMakie, GLMakie) | one per session | implementations a Makie wrapper names (x14 did this for CairoMakie) |
| globals: theme stack, `current_figure`, font and FreeType handles | none | typed, deeply concrete state or declared calls (rule 1's check of globals) |
| `show`/logging holes on the PNG path (24) | none | outward doors, outside Makie |

With this, `verify_main` would follow Makie from the plot call to the
backend: the 75 holes of x14 are in Observables (26), Base's output path
(24), `figureplotting.jl` (11) and GridLayoutBase (5), on `Any`-typed values
that the representations above replace or close. Not tested: Makie is
unchanged, the prototype's MakiePlots only translates tables into plain
vectors before its declared calls, and the note's trade-off 1 says Makie as
written is reached by calls upward.

### 16.5 Other languages

| Language | Compiled per type | Type-erased, with a contract | Erased value storable | Erased, without a contract |
|---|---|---|---|---|
| C++ | templates (the nesting the question names); C++20 concepts check the contract, still per type | virtual functions; `std::function` for one signature | yes | `void*`, `std::any` |
| Java | — in source (HotSpot specializes at run time) | generics (erased), interfaces | yes | `Object` |
| Rust | generics, monomorphized; `impl Trait` hides the name, not the cost | `dyn Trait`, a vtable per (trait, type) | `Box<dyn Trait>` | `Box<dyn Any>` |
| Swift | specialization, an optimization within a module or of `@inlinable` code | generics by default across modules (witness tables) | `any P` | `Any` |
| Julia today | type parameters | abstract types with asserted results (informal contract, open targets); FunctionWrappers and opaque closures for one signature | yes, at `Any` | `Any`, abstract types |
| Trait world | own representation, compiled call | dynamic operations, dynamic call, `Dynamic{X}` (rev 1125) | `Dynamic{X}` (rev 1125; before: no) | inside a module, closed by ownership |

The trait world adds the projection as an enforced position, which the
others leave to convention (Makie's `convert_arguments` is one), and
placement by owner: code compiled per type lives in the image of the package
that chose the type and is never invalidated from elsewhere. In Rust the
orphan rule corresponds to rule 3 and the placement of monomorphized code to
rule 4.

### 16.6 Open

1. **Storing erased values.** *Closed at note rev 1125: `Dynamic{X}`, see `proposal-stored-values.md`.* Rust's `Vec<Box<dyn Trait>>` and Swift's
   `[any P]` keep values of different types with their operations. The trait
   world forbids storing a trait object, so a library keeps projected
   representations. A storable dynamic trait object (the representation plus
   its operations, a trait-world value) would fill the gap; whether it fits
   rule 2 is not worked out.
2. **What a projection loses.** Dual numbers, units, `Float64` precision and
   lazy ranges do not survive a projection onto `Float32` arrays; Makie's
   own history shows it (16.4). Keeping them needs a representation that
   carries them, compiled per type: the product continues, by choice.
3. **Dynamic operations in an image.** The prototype's `@cfunction`
   pointers are made per session and invisible to `verify_main`. The design
   needs operation code compiled with the conformance and a dispatch the
   walk can list, for example a witness of compiled methods instead of
   pointers.
4. **Printing.** A worker should print as its bound and representation;
   the prototype prints the machinery's types.
5. **The claim is structural, not measured at scale.** It follows from
   workers being keyed by representation tuples (`TObj{T, V}`). x16 is the
   cheap half of the Makie test (variety per type). Still open: a synthetic
   stack of trait modules counting specializations against layers and
   variants, and ComputePipeline restricted to Makie's representation
   families with `verify_main` run through it.

**Review.** A Fable review of rev 1112 (11 findings) corrected: the claim
that `verify_main` counts dynamic operations as bounded and that they compile
ahead (false on the prototype, 16.3); "how little variety" (true for values,
not types: x16); Makie's types (`Point2f` → position families; `Float32` only
at the backend); the "wide record fixed by the library" (attribute shapes
need the inside position); "every bound ends the growth" (conformances do,
and six things continue it); the missing comparison with plain-Julia
discipline and the "sane types" half; table qualifications; the
other-languages table (Julia's abstract types with assertions, C++
`std::function` and concepts). Trade-off 1 now says "Makie as written".

## 17. Where unreadable errors come from, and what bounds change (session 22)

The user's question: where do the unreadable error messages of C++
templates and SciML come from, and how would C++ concepts and our trait
system solve them? Measurements in `experiments/errors/` (GCC 14.2; Julia 1.12.2
with the current OrdinaryDiffEq):

| case | lines | bytes (REPL / full) | path printed | longest line |
|---|---|---|---|---|
| C++ `std::sort` on `std::list` | 28 | 2,704 | 1 instantiation step | — |
| C++ `std::ranges::sort` on `std::list` (concepts) | 29 | 3,367 | the concept hierarchy | — |
| C++ `std::sort` of `vector<pair<string, Point>>`, `Point` without `<` | 33 | 3,938 | 6 instantiation steps | — |
| SciML, parameters used but never passed | 71 | 5,602 / 10,583 | 29 frames | 3,789 |
| SciML, a `Float64` cache under `ForwardDiff.gradient` | 101 | 6,559 / 13,811 | 44 frames | 5,574 |
| SciML, the same cache under `Rodas5()`'s automatic Jacobian | 81 | 4,704 / 89,627 | 22 frames | 33,673 |

The integrator's type for `Tsit5` on a 3-vector is 3,553 characters with 75
type-parameter lists: the algorithm, the state, time and parameter types,
the solution, which holds the problem, which holds the `ODEFunction`, which
holds the wrapped user function with its call signatures, the caches and the
options.

### 17.1 Anatomy: three ingredients

An unreadable message needs all three:

1. **The failure is detected deep, where an operation is missing.** The
   library never states what it requires of its arguments; the requirement
   is whatever its body happens to call, and it surfaces when that call
   fails, in the library's internals. The message therefore describes the
   internals, not the user's mistake:
   - "no match for `operator-`" in `std::__sort` instead of "a list is not
     random access";
   - "no match for `operator<` (`const Point`)" in `std::pair`'s comparison,
     six instantiation steps below `std::sort`, instead of "`Point` is not
     ordered";
   - `Float64(::ForwardDiff.Dual{…})` inside `copyto!` and `materialize!`
     instead of "your function is called with dual numbers and stores them
     in a `Float64` buffer".
2. **The path is printed.** Because the failure point says nothing about
   the cause, the compiler or runtime prints the path from the user's call
   to it: C++'s "required from" chain, Julia's stack trace (22–44 frames
   above, through `solve`, `__solve`, `__init`, `_ode_init`, `initialize!`,
   the function wrappers, broadcasting).
3. **Every step is printed at its full concrete type.** Code is compiled
   per concrete type, so each step is identified by its concrete arguments.
   And because fast code needs the concrete type where it runs, every type
   above the inner loop carries the types below as parameters: the
   integrator holds the solution holds the problem holds the function. Each
   frame is as long as the nesting is deep: C++ prints
   `__normal_iterator<pair<basic_string<char>, Point>*, vector<pair<…>>>`
   in every step, Julia prints one frame line of 33,673 characters.

C++ adds a fourth, overload candidates with the reason each failed; Julia's
"closest candidates" are its version.

Ingredient 3 is the user's observation about Julia types: a concrete type
is data, behaviour lives in methods anywhere, so the only way to make the
inner loop fast is to carry the concrete type all the way down, through
every signature and type parameter above it.

### 17.2 What SciML does today: contracts written by hand

- **Guidance messages.** For parameters never passed (`NullParameters`), a
  tuple used as a state, and "First call to automatic differentiation for
  the Jacobian failed", SciML catches or intercepts the failure and prints
  what the user probably did wrong and how to fix it. Each is a requirement
  of the library, stated after the fact, by hand, for one failure the
  maintainers have seen often.
- **AutoSpecialize.** The user's function is wrapped in a
  `FunctionWrappersWrapper` at fixed call signatures (visible in every trace
  above), so the solver is not compiled per function type: a dynamic call at
  a declared signature, by hand.
- **Julia's type abbreviation** (since 1.10, `{…}` in REPL stack traces):
  13.8 kB to 6.6 kB, 89.6 kB to 4.7 kB. It treats ingredient 3 by hiding,
  including the parameter that is sometimes the clue.

### 17.3 What C++ concepts change

- **Ingredient 1, at the use site.** `std::ranges::sort(list)` fails at the
  user's call, before the body is instantiated, naming the requirement:
  `random_access_range`, because "`std::random_access_iterator_tag` is not a
  base of `std::bidirectional_iterator_tag`".
- **Not shorter.** GCC 14 explains the failure by walking the concept
  hierarchy and the library's internal helper concepts
  (`__iter_concept_impl`, `derived_from`): 29 lines against 28 for the
  unconstrained `std::sort`, whose message GCC has meanwhile trimmed.
- **No definition checking.** A constrained library whose constraints are
  incomplete still fails deep inside, as before (§ other-languages 2). The
  `Point` case is unchanged under concepts if the constraint omits the
  element's ordering.
- **Ingredient 3 untouched.** Types are printed in full
  (`std::__cxx11::list<int, std::allocator<int> >&`); C++20's abbreviated
  `std::sortable auto&` changes how a signature is written, not what is
  compiled or printed.
- **Structural satisfaction** can accept a type by accident, which then
  fails deep inside.

Rust checks bounds at both ends and its errors are short ("the trait bound
`X: Ord` is not satisfied"), except where nested types must be printed:
RFC 2397 cites a Diesel error naming a "30 page long type". `impl Trait` is
Rust's way of keeping the concrete type out of the signature: concrete for
the compiler, known to the reader by its bound.

### 17.4 What trait bounds change

**Ingredient 3, the user's point.** A trait bound is an abstract type that
guarantees concreteness: whatever conforms becomes a deeply concrete
representation before code runs on it, and the worker is compiled for that.
Because the bound determines how a value becomes concrete, the signature
does not have to carry the concrete type. A solver's state, parameters and
right-hand side would be fields and arguments declared by bounds; the
concrete types are the worker's key, which the compiler needs and a reader
does not. A frame prints as its bound and representation,

    perform_step!(integrator::ODEIntegrator, u::StateVector at Vector{Float64}, f::Callable{…} at DynamicCall, p::Parameters at Vector{Float64})

and the representations are flat, chosen by their owners, not built from
how the user assembled the value. Two caveats: a type that is its own
representation prints as itself, nested if it is nested, by its owner's
choice; and the prototype prints the machinery (`TObj{…View{…}}`), so this
is design.

**Correction (review of the stored-values proposal, session 22).** The
integrator's 3,553 characters contain no user type: `u` and `p` are already
`Vector{Float64}` and `f` is already a dynamic call (SciML's AutoSpecialize).
The length is the library's own nesting: the solution 51%, the options 16%,
the `ODEFunction` 14%, the cache 5%. Bounds on `u`, `p` and `f` would remove
nothing from it; printing by bound shortens it only if the solution, options
and caches are themselves bounded or `Dynamic`, a library redesign. With
ComponentArrays the type is 5,118 characters, and the two user types account
for 37% of it, but that is the case in which the user's right-hand side
needs its own type (proposal-stored-values §8.1). Julia 1.12's REPL already
abbreviates such frames to `step!(i::Integrator{TObj{…}, …}, …)`, so the
gain of printing by bound in stack traces is modest; it is larger for
`MethodError` messages and `typeof`.

**Ingredient 1.** Requirements are stated and checked where they belong:
- **at the conformance** (`@implement`): a missing operation, a wrong
  result type, a representation that is not deeply concrete, reported where
  the user declares it, before any call; earlier than concepts, which check
  at each use;
- **at the library's build**: library code may use only the operations its
  bounds declare, reported at its line, so the class "the constraints were
  incomplete, it fails deep inside" cannot reach a user; C++20 cannot do
  this;
- **at the entry**: a value that cannot become its representation fails at
  the projection, naming the bound;
- **for functions from above**: a `Callable` bound declares the signatures
  the library calls them at. A solver that differentiates `f` calls it at
  two signatures, so it declares two bounds (rule 2), and "`f` is called
  with dual numbers" becomes part of its signature instead of a guidance
  message.

**Ingredient 2.** A failure at a declaration or an entry has a path of one
or two steps. A failure at run time inside user code above the trait world,
which is what all three SciML cases are (the bug is in `lorenz!` or the
cache), is still found at run time: the bounds pass because the user's
methods exist for any argument type. The trace then runs through the user's
function, the call upward, and frames of library code printed by bound, a
few lines instead of 22–44 frames at full concrete types.

So, for the SciML cases: the contract that SciML writes by hand in guidance
messages becomes part of the solver's signature; the failure is still found
at run time, because it is in user code; the message is short because every
frame inside the solver prints by bound. For the C++ class, where the
library's own requirements are unstated or incomplete, detection moves to
the conformance or the library's build.

### 17.5 Open

1. The printing policy (frames by bound and representation) is not
   implemented; the prototype's frames print `TObj{ColTable, Tuple{View{…}}}`.
2. *(Rejected by the user, session 22: hidden type parameters are antithetical to Julia.)* Struct fields declared by a bound, with the representation types as
   implicit parameters that the compiler keys on and the printer omits, are
   not in the note. They are what "the signature does not have to carry the
   concrete type" needs for stored state such as an integrator; today a
   trait object cannot be stored, and a struct of representations carries
   them as ordinary type parameters.
3. Whether the explanation of a failed conformance stays short when traits
   refine traits (GCC's concept explanations walk the hierarchy) is
   untested.

## 18. Writable fields and lenses (session 22)

The user asked for writable trait fields ("something people would expect. Its how traits elsewhere work") and proposed desugaring a field to a getter and a setter. The design, in `writeup/notes/4-details.md` ("Declaring a trait", "Dynamic values"):

- **Properties.** A trait field is a property: `getproperty` and `setproperty!` on the representation, as Scala desugars a trait's `var` and Swift requires `{ get set }`. Fields are writable unless declared `const`, as in a `mutable struct`.
- **When writes are seen.** Julia passes by sharing, so `t.d = 6` on a mutable argument is seen by the caller. Through a trait, a write is seen when the representation is the user's object or shares its data. Copying projections are refused for traits with writable fields.
- **The projection field.** A field of type `R` (`data::R`) names the projection. Writing it rebinds the user's field, so the trait object holds a lens, the user's object and the field's index, not the field's value.
  - Its type is fixed by declaring the field as exactly `R`.
  - Workers stay compiled per representation, since the lens carries an index, not the user's type.
  - A `Dynamic` made from a lens keeps it: it is live, and compares by identity.

**Cost** (`experiments/lens/lens_bench.jl`, Julia 1.12.2, -O2, 10^8 accesses, best of three; a loop that reads the representation once per iteration):

| access | ns |
|---|---|
| read, direct field (compiled per user type) | 1.04 |
| read, held value (snapshot) | 1.03 |
| read, lens via builtin `getfield(obj::Any, i)::R` | 4.6–4.7 |
| read, lens via a load at the field's byte offset (`pointer_from_objref` + offset) | 1.15 |
| write, direct field | 0.6 |
| write, lens via builtin `setfield!(obj::Any, i, x)` | 13.6 |

One compiled loop served lenses into two different user types. A rebinding of the field from above is seen through the lens (10.0) and not through the snapshot (1.0). On stock Julia a lens costs 4–5 ns per read and about 14 ns per write. A runtime that emits a typed load and store at the field's offset, with the write barrier, makes it nearly free.

**Open:**
- *Decided (the user, 2026-10-16):* every field projection of a mutable user type, from a field that can be rebound and is declared with exactly the representation's type, is kept as a lens. That removes the first stale-value case of the stored-values review. A field declared with an abstract type stays translated once, which is open;
- several views of one object, where a lens and a view computed from the same field must not diverge;
- computed properties as projections.
