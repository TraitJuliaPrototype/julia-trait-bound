# writeup/

**[`design.md`](design.md) is the current statement of the design and its decisions** (session 29, 2026-10-18). The notes below keep the detail; they predate the session-29 framing (strict mode first, three rules, the facts policy in Julia's compiler), and `design.md` wins where they disagree. Superseded documents are in `attic/writeup/`.

## Read in this order

1. **[`design.md`](design.md):** the problem, the guarantee (strict mode first), traits, the three rules, what Julia provides, the decisions in force, the evidence, the implementation and the order of work.
2. **[`open-issues.md`](open-issues.md):** everything open, decisions waiting for the user first (§1).
3. **The notes, for detail:**
   - [`notes/1-overview.md`](notes/1-overview.md): the earlier overview, with the example;
   - [`notes/2-design-choices.md`](notes/2-design-choices.md): the choices against C++, Rust, Swift and Mojo, and their costs;
   - [`notes/4-details.md`](notes/4-details.md): the mechanisms: ownership, traits, conformance, keys, dynamic values, results like the input, caching, AOT;
   - [`notes/3-wrapping.md`](notes/3-wrapping.md): code written without traits, pirates, strict mode.
4. **[`decisions.md`](decisions.md):** the full register, with history.

## Supporting documents

| File | What | Status |
|---|---|---|
| `other-languages.md` | research: how C++, Rust, Swift and Mojo arrived at their trait designs, with criticisms and sources | current |
| `design-findings.md` | the evidence log: measurements, prototype results, earlier forms of the design and why they changed, in session order | current evidence in §1, 5, 6, 13, 15–19; history elsewhere (its header) |
| `explorations/keys-plan.md` | how TraitWorld implements keys: two reviews' decisions, phases, the reference layout, the runtime as methods (§6) | implemented (session 23); the session note records what changed in implementing it |
| `explorations/wrapping-by-facts.md` | a simpler, provable design for using code written without traits: concrete facts, nothing skipped; synthesis of three fresh designs (`explorations/wrapping-designs/`) | adopted (session 23), validated (session 24: assumptions A3–A5, implementation rules 1–7) |
| `explorations/julia-support.md` | what TraitWorld needs from Julia proper, the order to implement them, and what is implemented in the patched build | reviewed in session 25 for wrapping by facts and strict mode: pieces 2, 4, 6 dropped, 9–13 added, new order |
| `explorations/strict-mode.md` | strict mode: defining a pirate that would win at a trait-world fact is an error, so trait code is never invalidated by a pirate | session 25; adopted as an option, prototype planned |
| `explorations/aot-under-facts.md` | AOT under wrapping by facts: builds compile plain Julia, what the trait world still gives, three risks, three binaries to measure | session 25 |
| `reviews/2026-10-18-design-and-fixes.md` | the design and the fixes since session 27, after the pivot to the compiler (Fable 5.1) | session 29; open-issues §1.11–1.14 |
| `reviews/2026-10-18-framing-and-motivation.md` | the framing and the user's two-goal reframing; §5 "strict mode first" (Fable 5.1) | session 29; adopted as the framing, notes to be rewritten |
| `reviews/2026-10-18-decisions-revisited.md` | every register row revisited for conceptual simplicity after session 29's decisions (Fable 5.1): ten ranked changes, a verdict per row, a simplified core | session 29; waiting for the user |
| `reviews/2026-10-18-implementation-shape.md` | the implementation and demonstrators: inventory, path dependencies, target architecture, migration order (Fable 5.1) | session 29; the basis of session note 29's "Next" |
| `reviews/2026-10-17-consistency-fresh-eye.md` | a fresh-eye review of the design's consistency after the churn (Fable 5.1): four significant inconsistencies, stale text | session 27; decisions waiting in open-issues §1.5–1.8, minor findings §5.5 |
| `reviews/2026-10-17-demonstrators-under-facts.md` | the three demonstrators' rows checked against wrapping by facts; the order of work (Julia pieces and TraitWorld fixes over workarounds) | session 26 |
| `reviews/2026-10-16-wrapping-under-keys.md` | review of code written without traits under keys (F1–F11, nine decisions) | F1 fixed; F2, F4–F8 and F10 dissolved by wrapping by facts; F3, F9 open (open-issues §4b) |
| `explorations/runtime.md` | the runtime the design needs, Julia 1.13, the load filter, the minimal runtime for the demonstrators | current, recommendation adopted |
| `explorations/runtime_load_filter_1.13.2.patch` | the load half of the invalidation filter, ported to 1.13.2 | history: the filter is not needed under wrapping by facts |
| `explorations/associated-types.md` | associated types: whether Rust's and Swift's experience applies, joint parametrization, bounds | adopted in first-order form; written before keys |
| `explorations/solvers.md` | the design of TraitDifferentialEquations: traits, composition, callbacks, AD, the SciML baseline | demonstrator design; written before keys (banner) |
| `explorations/makie-rewrite.md` | the design of TraitMakie: fundamental traits, a typed compute graph, the minimal demonstrator | demonstrator design; written before keys (banner) |

## Where the rest lives

- **`session-notes/`:** one note per working session. The latest is `2026-10-18-29-reviews-and-decisions.md` (session 28 left no note; it is reconstructed there); its "Next" list is the starting point for the next session.
- **The repositories inside the design repository** (`README.md` at the root): `TraitWorld/` (the prototype), `experiments/` (measurements and prototypes), `julia/` (patched Julia), `TraitDifferentialEquations/`, `TraitMakie/` and `TraitReport/` (the demonstrators).
- **`attic/`:** the earlier phases: TraitRegions, the ecosystem proof of concept, the frozen live note (revision 1146), the proposals and plans of sessions 14–22.

## Conventions

- **Terms** as in `notes/4-details.md` "Terms": trait, conformance, implementation, implementing type, key, trait object, entry, worker, view. "Representation" and "projection" belong to the design before keys, and appear only in history.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon.
- The machine is shared: one Julia job at a time, at `nice -n 19`; full builds alone, under a memory guard.
