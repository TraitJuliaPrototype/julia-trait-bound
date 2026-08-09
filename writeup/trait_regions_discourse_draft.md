# [RFC / experiment report] Trait-bounded regions: measured evidence that erased trait dispatch could dramatically cut Julia's compilation costs

*Draft for Discourse (compiler/internals). All numbers reproducible from the
linked repo (Julia 1.11.7, `--startup-file=no`, fresh process per
measurement; experiment scripts in `ecosystem/scripts/` and `rung2/`. The
package and its 23-test suite pass unchanged on 1.11.7 and 1.12.2; the
sealed-interpreter experiment is 1.12-only).*

## The problem, in one sentence

Julia recompiles per *(function × concrete type)*, so ecosystem-wide compile
cost scales as types × ops × packages — every new user type re-pays every
generic library it touches, which is precisely what makes long interactive
sessions and TTFX painful.

## The experiment

We built a working prototype of **trait-bounded regions** — a pure-package
approximation of a possible language feature — and a 9-package miniature
ecosystem to measure it against ordinary generic Julia, twin-for-twin:

```julia
@trait ColTable begin              # interface package
    ncols(r)::Int
    col(r, i::Int)::Vector{Float64}
end

@seal ColTable MyTable begin       # any package, one declaration
    project(t) = t.cols            # T-specific boundary
    ncols(r)   = length(r)         # witnesses: mention only the representation
    col(r, i)  = r[i]
end

@region ColTable begin             # library package
    colmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})
end
```

`@region` splits each op into a tiny non-specializing entry and a **worker
keyed on the representation `R`, never on the user type `T`**. Witnesses are
called through erased tables (no inference edges). Consequences, each
measured (X-numbers = scripts):

1. **Flat TTFX (X1).** Fresh session, never-seen type, composed op across
   two region packages: **14 ms** of compilation (mostly the user's three
   witness lines) vs **25 ms and growing-with-stack-size** for the plain
   twin. Workers come precompiled from pkgimages and are reachable by types
   that did not exist at precompile time.
2. **Zero invalidation under churn (X4) — with the control stated.** 100 new
   types + methods on Base functions + redefinitions, and separately a full
   `using CairoMakie` (93 invalidation trees ecosystem-wide): zero region
   workers invalidated, 0.0 ms post-churn recompilation. The plain twin
   *also* survived this particular churn (well-typed new-type churn rarely
   invalidates concretely-typed code) — the discriminating case is targeted
   piracy at the representation's types (X10): there the plain twin and
   ordinary region ops change behavior and pay 60–73 ms session-wide
   recompilation, while sealed execution does neither.
3. **Instances scale with representations, not types (X5).** 13 user types
   over 2 representations → 2–3 worker instances per op, not 13. A conformer
   introducing a new representation owns its workers' native code in its own
   pkgimage (X2).
4. **A real-world example — Makie (X8), fair version.** Marginal compile per
   additional never-seen table type, with per-type registration/definition
   cost *inside* the measurement and per-type witness closures (no sharing
   artifacts): idiomatic `convert_arguments` recipes ≈ **167 ms/type**
   (typed Makie pipeline, indefinitely); trait region ≈ **98 ms/type**
   (mostly seal-time witness compilation + checks); hand-written
   "bin-then-plot" erasure ≈ **51 ms/type**. The honest reading: the win
   over recipes comes from *type erasure at the boundary* — which the
   region design systematizes rather than invents, and which a disciplined
   author can hand-write cheaper per type. What the trait layer buys over
   hand-erasure is not marginal compile but the guarantees: the erased
   reduction stays precompiled, checked at seal time, and
   invalidation-immune across types. (An earlier draft of this experiment
   reported 18 vs 155 ms; that version shared witness-closure types across
   test types and excluded registration — numbers withdrawn.)

## What does it cost at runtime?

The honest ledger (X3, `report` composing 4 ops over 6 columns):

| column length | plain Julia | region (static wiring) | region (dynamic) |
|---|---|---|---|
| 16 | 1.0× | 1.31× | 5.0× |
| 256 | 1.0× | 1.01× | 1.19× |
| 4096 | 1.0× | 0.99× | 1.01× |

Indirection amortizes on chunky trait signatures; fine-grained surfaces pay.
An opt-out (`@full_compile`) recovers full per-type monomorphization — same
worker body, concrete witness types — for hot paths that need it.

## The part aimed at this forum: faking the language feature

Cross-package region calls have two lowerings in the prototype. The dynamic
one (op registry + dynamic dispatch) is what a package can do soundly. The
static one — **declared imports rewritten to direct calls into the other
package's worker** — is what a compiler would emit inside a closed trait
universe. Measured: the static lowering runs at **0.99–1.31× plain Julia**
while keeping the flat 14 ms TTFX. That brackets the native feature: *the
mechanism is known-cheap; the only thing a package cannot provide is
soundness.* The convention-based static wiring re-freezes witness resolution
— exactly the hole compiler-managed universe versioning would close.

We also demonstrated the contentious semantic — **sealed resolution** —
constructively, twice, at increasing strength:

- **Pinned in time (X10, stock 1.11)**: ops run via `Base.invoke_in_world`
  at a "universe world" bumped only by seal/op registrations. A pirated
  `Base.sort(::Vector{Float64})` changes results and forces 60–73 ms of
  session-wide recompilation on the normal paths; the sealed path returns
  the pre-pirate result with 0.0 ms — and the blame report names the pirate
  method and the modules it hit. Honest scope: this is *snapshot* semantics
  — the pin advances on every registration event, adopting anything defined
  in between, so it demonstrates the semantic fork cheaply but is not a
  standing guarantee. That is precisely why the design wants
  compiler-managed universe versioning rather than a package-side world ref.
- **Pinned in territory (X11, 1.12 Compiler stdlib, ~120 LOC)**: a custom
  `AbstractInterpreter` whose method table resolves only into an enrolled
  universe of modules, workers wrapped as OpaqueClosures. The same pirate,
  *defined before the worker is even compiled*, is invisible to statically
  resolved calls — non-enrolled modules do not exist inside sealed
  compilation — and a statically resolved region call landing outside the
  universe throws `MethodError`. Scope, measured not assumed: dynamic calls
  (the witness-table mechanism itself) are covered against *post*-compilation
  pirates by the OpaqueClosure's creation world, but a pirate that predates
  compilation and is reached dynamically leaks through — the residual hole
  is exactly "compile sealed workers at registration time", which a native
  implementation gets for free by keying compilation on the universe.

The X11 implementation surfaced a design fact the proposal should own:
**sealed resolution cannot be a post-filter**. `jl_matching_methods` drops
methods fully shadowed by a more-specific match, so filtering a pirate out
afterwards leaves its universe-internal victims missing from the match list;
our table view has to recover them by direct method-list search. A native
implementation should restrict the method table *below* the matcher.

## Friction a language feature would delete (found the hard way)

- **Registration boilerplate**: registries live in other packages' state, so
  cross-package mutations during precompile are discarded → conformers seal
  in `__init__`, region packages replay registrations. Pkg-level enrollment
  metadata (cf. #54903 strict subsets) is the natural home.
- **Return-type knowledge**: trait-call sites need user-written asserts to
  keep workers type-stable; native lowering gets this from the declaration.
- **Per-session codegen floor** (X9): pkgimages retain inference results but
  drop native code for foreign runtime-dispatched CIs (`cache=true,
  native=false`) — a ~240 ms/session constant no package workload can fix,
  which AOT over a closed trait universe would.
- Julia's `max_methods` union-splitting adds a one-time ~100–350 ms recompile
  above erased entries — gone if entries aren't dispatchable methods.

## What this prototype deliberately does not claim

No soundness in the macro layer (evadable; static wiring is convention). The
sealed interpreter enforces the closure rule for statically resolved calls
in individual workers; its allowlist is a whole-module proxy for a real,
curated `TraitCore` kernel — curating one is the closure rule's true cost
and remains future work — and **piracy from inside the universe** (an
enrolled module pirating Base at the representation's types) is not
prevented by any rung below full enrollment governance. Fingerprints are
best-effort (signature + source location — blind to in-place body edits)
and universe ids are not yet stable across sessions, so persisted-cache
validation remains future work. Registries are not thread-safe. No plotting
TTFP win (Makie's first-plot cost is Makie-internal; our machinery adds
~nothing to it, X7). Per-element trait surfaces favor `@full_compile`.
Seal-time return-type checks are best-effort `Base.return_types`. Sealed
OpaqueClosures are not yet wired into the region registry as a routine
execution mode (single-worker demo only).

## Ask

The ladder is now fully evidenced: **Rung 1** (macro prototype) measured on
a 9-package ecosystem; **Rung 2** (sealed resolution) implemented both as a
stock-Julia primitive-reuse and as a restricted-table interpreter; **Rung 3**
(the language feature) bracketed by the faked-native columns, with its two
genuinely new requirements identified concretely (enrollment metadata;
table restriction below the matcher). Is a versioned "trait-bound" strict
subset — enrollment via Project.toml, sealed resolution for region code,
compiler-managed witness tables and universe-keyed caches — something the
community wants developed into a full proposal? The repo has the design
documents, the prototype (TraitRegions.jl, 23 tests, 1.11+1.12), the
ecosystem, and every number above as a runnable script. Repo link: (to be
added on publication).
