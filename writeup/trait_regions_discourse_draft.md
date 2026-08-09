# [RFC / experiment report] Trait-bounded regions: measured evidence that erased trait dispatch could dramatically cut Julia's compilation costs

*Draft for Discourse (compiler/internals). All numbers reproducible from the
linked repo (Julia 1.11.7, `--startup-file=no`, fresh process per
measurement; experiment scripts in `ecosystem/scripts/`).*

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
2. **Zero invalidation under churn (X4).** 100 new types + methods on Base
   functions + redefinitions, and separately a full `using CairoMakie`
   (93 invalidation trees ecosystem-wide): **zero** region workers
   invalidated, 0.0 ms post-churn recompilation.
3. **Instances scale with representations, not types (X5).** 13 user types
   over 2 representations → 2–3 worker instances per op, not 13. A conformer
   introducing a new representation owns its workers' native code in its own
   pkgimage (X2).
4. **A real-world example — Makie (X8).** Idiomatic `convert_arguments`
   recipes drag each user type through Makie's pipeline: **~155 ms per
   additional custom type, forever**. Erasing the type before Makie sees it:
   **~18 ms, flat** (~8.5× per type; 2.9× over a 7-type session).

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

We also demonstrated the contentious semantic constructively (X10):
**sealed resolution** via `Base.invoke_in_world` pinned to a
"universe world" bumped only by seal/op registrations. A pirated
`Base.sort(::Vector{Float64})` changes results and forces 60–73 ms of
recompilation on the normal paths; the sealed path returns the pre-pirate
result with 0.0 ms — and the blame report names the pirate method and the
modules it hit. World-pinned execution is already in the language; sealed
resolution is a disciplined use of it, not an exotic new semantic.

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

No soundness (macros are evadable; static wiring is convention). No closure
rule enforcement (the sealed-world demo pins *time*, not *territory* — no
allowlisted kernel yet). No plotting TTFP win (Makie's first-plot cost is
Makie-internal; our machinery adds ~nothing to it, X7). Per-element trait
surfaces favor `@full_compile`. Seal-time return-type checks are best-effort
`Base.return_types`.

## Ask

Is a versioned "trait-bound" strict subset (enrollment via Project.toml, a
sealed-resolution rule for region code, compiler-managed witness tables and
universe-keyed caches) something the community wants us to develop into a
full proposal? The repo has the design documents, the prototype
(TraitRegions.jl, 23 tests), the ecosystem, and every number above as a
runnable script. Repo link: (to be added on publication).
