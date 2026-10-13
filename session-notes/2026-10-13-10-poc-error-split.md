# 2026-10-13 — Session 10: design rewrite, two reviews, Stage-1 PoC (error split)

## Intent

Rewrite the design from scratch around the user's chosen semantics (piracy or
redefinition affecting trait-bound code is an error with a recompiling
opt-out; interim: warning), get it critically reviewed, then build Stage 1 of
it as a proof of concept on stock Julia 1.12.2.

## Done

- **Design document** (Claude Doc "Trait-Bounded Julia: Design",
  https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20).
  Key moves: error split instead of sealed resolution (error-or-identical, by
  poisoning, not rejecting); edge-level rule for dependencies (trait-bound code
  speculates only on concrete signatures; concrete edges can only be changed by
  owners or pirates); ownership = Julia (Base + stdlibs) as one owner, Aqua's
  mention rule, extensions inherit, `[traitbound] implements` declarations;
  orphan rule for seals; `catch` rethrows `PiracyError`; return_type folded for
  concrete queries only; session-level opt-out.
- **Reviews.** Opus hostile review (poison vs reject, compile-state
  independence, ownership false positives, seal coherence, return_type) and a
  Fable 5.1 review (stdlibs-as-pirates under the strict rule; broadcast cost of
  runtime return_type; catchable PiracyError; trait-mode code needs runtime
  support before Gate B can be measured). Both folded into the doc.
  Fable's static audit: with Julia as one owner and implementer declarations,
  the concrete closures of sum, sort!, Dict, show, broadcast, matmul,
  ColStats, Makie `lines` (15,180 CIs) hit 0 pirate methods; CairoMakie load:
  769 mt-edge sigs, 0 concrete; 217 MI roots, 216 abstract.
- **Stage-1 PoC** (branch `poc-error-split`): TraitRegions gains
  `ownership.jl` (owner, implements, is_piratical), `audit.jl` (guard per op,
  concrete-edge closure audit cached by CodeInstance identity, PiracyError,
  modes), orphan check in `@seal`, `catch` rewrite in `@region`, per-op seal
  cache. Tests: 46/46 (23 old + 23 new). `poc/errorsplit/`: 7 packages,
  9 load orders x 3 modes + orphan, all as expected:

  | case | warn | error | recompile |
  |---|---|---|---|
  | MyTable alone, Dominated, Legit (both orders) | 0.0 ms, no warning | same | same |
  | Pirate after MyTable | warning, 36 ms, result 12 | PiracyError in 7 ms, no recompile | 21 ms, 12 |
  | Pirate before MyTable | warning, 37 ms | PiracyError in 22 ms (compiles to find it) | 18 ms |
  | FakeImpl (declared implementer) | no warning, 21 ms, 12 | same | same |
  | Orphan seal | warning at precompile | | |

- **Ecosystem (stock 1.12.2, scripts12), PoC vs pre-PoC baseline worktree:**

  | | baseline | PoC (warn) |
  |---|---|---|
  | first calls, 3 tables x 3 ops | 45-51 ms | 71-73 ms (first audits, ~20 ms) |
  | recompile after ChurnStorm | 0.0 | 0.0 |
  | recompile after CairoMakie | 0.0 | 0.0 |
  | audit findings / warnings on the whole stack incl. Makie-in-worker | n/a | 0 / 0 |
  | audit_all, empty cache / warm | n/a | 16-21 ms / 0.2-0.5 ms |
  | report len 16: static / dyn (ns) | 2007-2043 / 9491-10006 | 2009-2013 / 2038-2155 |

## Surprises (each one a design lesson)

1. **The guard reproduced the design's central problem on itself.** Its slow
   path (printing, logging, reflection) is ordinary code with abstract edges;
   entries called it statically, so `using CairoMakie` recompiled every entry
   (213 ms). Fixed by the design's own rule: slow path behind a dynamic call;
   the audit hot path made concrete (identity sets instead of `Set{Any}`
   hashing, `jl_compile_hint` instead of generic `precompile`, which
   Observables extends; TOML handling behind a barrier). After the fix: 0.0 ms.
   Lesson: trait-bound runtime code must itself obey the edge discipline.
2. **Inlining dyncall made dynamic composition 4.7x faster** than the
   baseline (the op name folds at each call site), and is what the guard
   needed anyway to stay cheap.
3. **op_info methods look like piracy** (region packages register ops for
   traits they do not own). Registration is by design; exempted.
4. **A single `get(::Dict{String,Any}, ::String, ::Vector{String})`** cost
   10 ms of first-use compile; plain `haskey`/`getindex` are in the sysimage.
5. MatrixTables seals its own `MatTable`, so it already obeys the orphan
   rule (the doc's claim that it would have to move was wrong; corrected).
6. The ownership gap is real on the ecosystem: `report`/`report_dyn` at
   `Matrix{Float64}` have no owner image (MatrixTables does not depend on
   ColReports) and compile at first call in both versions (~35 ms).

## Limits of the PoC

Poisoning is emulated at the entry (the runtime design poisons CodeInstances);
the error mode recompiles to discover a pirate that loaded first; the audit
covers worker closures, not seal code; attribution is by `parentmodule`, so
`Core.eval` laundering is not caught; the orphan check runs when a seal is
defined (precompile), not on load from a cached image; not thread-safe; no
trait compile mode (Stage 2-3): dependency code is ordinary code, and on this
stack it happens not to be invalidated by ChurnStorm or CairoMakie.

## Next

- Stage 2 (patched binary): runtime support for trait-mode CodeInstances
  (native dispatch + pkgimages honour an owner token; trait-bound method flag;
  CodeInstance-level poisoning), then Stage 3's compile mode and Gate C.
- Cheap next measurements: the audit on a SciML stack; the ownership gap via
  a package extension (MatrixTables x ColReports) that runs the workload.
