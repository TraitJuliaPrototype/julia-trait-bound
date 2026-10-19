# Design history: how the current documents came about

Process history that the current documents for core developers leave out: where each document came from, the order of work as it was done, and the numbers of earlier builds. The designs that were tried and dropped, with their reasons, are in [`../design/alternatives.md`](../design/alternatives.md). The decisions with their dates are in [`../decisions.md`](../decisions.md). Everything else is in [`INDEX.md`](INDEX.md).

## The documents

- **2026-10-19, the split of `design.md`.** `design.md` was the consolidated statement of the design: the terms, the problem, the argument in four steps, traits, the three rules, what Julia provides, the decisions in force, the evidence, the software, what is not claimed. It became two pages: [`../design.md`](../design.md), the design in prose, and [`../design/implementation.md`](../design/implementation.md), the details, which keeps the old section numbers 1–9. History went to [`../design/alternatives.md`](../design/alternatives.md) and to this file. `decisions.md` was regrouped by topic, with the superseded rows at its end; `open-issues.md` keeps open items in place and lists closed ones at its end.
- **Sections 2 and 3 of `design.md`** followed the spine the user proposed and adopted in session 29: start from what is true today, then add one step at a time (the framing review, `../reviews/2026-10-18-framing-and-motivation.md` §5; the user: "1-3 is a yes").
- **`design/mechanisms.md`** was taken from `notes/4-details.md` (now in `../../attic/writeup/notes-2026-10-18/`), checked against `design.md` and the prototype (TraitWorld 375a930). Its last section listed what was dropped from the note as superseded; those items are now on the alternatives page.
- **`design/comparison.md`** was taken from `notes/2-design-choices.md`, §1–4, 8–10 and its closing sections, refreshed against `design.md`. Its research is `../other-languages.md` (session 22). Its list of costs is the list of session 22, with the items that described layering, sealing and wrappers replaced.
- **`design/performance.md`** was `notes/5-performance.md`, the report of session 29's performance phase. The Fable review of the phase (`../reviews/2026-10-19-performance-phase.md`) corrected three of its four themes as first written: theme 1 left out the costs of the choices; theme 2 called the inliner habits harmless in plain Julia (review A1 showed otherwise); theme 3 presented a workaround as the mechanism (review D3). The note also observed that `design.md` §6 had claimed "the compiler's own code stays plain" before the code did it.
- **The Julia pieces** have been numbered 1–17 since session 23 (`../explorations/julia-support.md`).
- **Session 28 had no session note;** its decisions were reconstructed in session note 29.

## Session 29: the order of work, done

Session 29's order (approved by the user) was done in this order: (A) in-tree; the control; (B) and (C); `Dynamic` in the compiler (D); the demonstrators measured; pieces 2 and 4 removed. Then the performance phase, and the user's order after its review: "diagnose, then fix", then acceptance checks ([`../design/implementation.md` §9.3](../design/implementation.md#93-the-order-of-work)).

The decisions review (`../reviews/2026-10-18-decisions-revisited.md`) was answered by the user: "Witness table: Yes. On 2. We need compiled call to have an ODE RHS that has the right type signature. Julia's type system can't express that otherwise. Everything else looks good."

## The performance phase

Session 29's performance phase (2026-10-19), on julia-1.13 with parts (A)–(D). The final runs are one process per load order (n = 1); earlier runs were two.

| What | Before the phase | After |
|---|---|---|
| raytrace over `Dynamic{Scene}` (rtopen) | 3,281 ms | 300–336 ms (held views, julia 61852d8fb1) |
| raytrace, small case | 54 ms, 72.6 MB | 4.7–5.3 ms, 3.8 MB |
| sum over `Dynamic{Shape}` (cache-resident) | 1.45–1.61 ns per element (before held views) | 0.92–1.40 ns |
| a varargs wrapper in a plain recursion | stock 1.13.2: 21.9–23.3 ms, 16.8 MB | 0.36–0.44 ms, 0 bytes (patched, plain code) |
| TDE: a new model type, after CSV + DataFrames + CairoMakie | `@implement` 2.0 s, first solve 2.1 s | 148–164 ms, 89–133 ms |
| TraitMakie: a new data type (forwarding), after the loads | 5.5 s + 2.1 s | 97 ms + 89–161 ms |
| TraitMakie: the same, without loads | 36 ms + 40 ms | 77 ms + 89–107 ms |
| TraitReport form (t), fresh process | 1.11–1.13 s | 0.76 s |
| TraitReport form (b), work, nine packages loaded first | 620 ms | 338–342 ms |
| forks: first `stringtype = String15` read (the read alone) | 1.74 s | 0.041–0.046 s |
| recursion through `Dynamic` against plain-closed | 1.65× | 1.26–1.31× |
| rtopen, cycle members inlining each other | 542 ms | 384 ms |

Other numbers of the phase's course:
- The inliner changes were first gated on facts, so that the plain baselines stayed stock, and were then ungated by the user's decision ("Apply to all code"); from then on the plain baselines are patched-plain. The forms tried before the final rule are on the alternatives page.
- The typed call's gap was first measured as 33 ns against 30 ns for plain Julia (`total(t, 16)`); the plain loop's literal `16` unrolled. Untyped calls were 105–117 ns and 64 bytes on the previous prototype (270–295 ns before TraitWorld 5efbb4c, when the entry built the tuples for a result like the input on every call).
- The control first failed in the harness: in 1.13 a trailing `:` in `JULIA_DEPOT_PATH` adds only the bundled depots, not `~/.julia`.
- A fresh session's `@implement` of a forwarding type had been about 470 ms before TraitWorld's rewrite; it has not been re-measured as such ([`../open-issues.md`](../open-issues.md), closed item 3.11).

## Earlier numbers of the demonstrators

- **TraitDifferentialEquations, session 24:** first solve 55–60 ms in every load order; TraitMakie's first PNG 89–97 ms. New trait code defined after big loads then took 2.7 s to define a small module and 0.8 s for its first call, against 1.0 s and 0.09 s.
- **Before session 24:** TraitDifferentialEquations' first solve took 0.7–1.05 s with CSV, DataFrames and CairoMakie loaded (73 ms without); TraitMakie's first PNG took 0.31–0.37 s with CSV and DataFrames before (0.1–0.2 s without; 0.09 s after, patched).
- **Session 26:** `using TraitMakie` took 0.69 s patched against 0.23 s stock, and CSV, DataFrames, Statistics and TraitMakie together 1.40 s against 0.82 s; after TraitWorld's load hooks were moved under the policy (TraitWorld 29f0a8e), `using TraitReport` took 0.79–0.82 s patched, 0.71–0.72 s stock. The view cache flushed at every exit, 0.14 s with TraitMakie alone (fixed in TraitWorld 6239b1e). TraitWorld's own `Base.show` methods for trait-object types invalidated callers compiled for `show(::IO, ::Type)`, 1.0 s on CSV's first read with DataFrames loaded (2.64 s against 3.6 s without them); fixed by Julia's type-printer registry (db82407fa6; TraitWorld 6239b1e).
- **Session 27 (the package policy):** a new model type 0.16–0.23 s to declare and 33–44 ms to solve first; family registries took row 1 from 47 to 7 ms (a19ba7e).

The open-issues entries of these numbers are at the end of [`../open-issues.md`](../open-issues.md#closed-items).
