# 2026-11-09, day: `IO` as Base's trait, and finality opt-in

The chronology of the session after the handover of the morning ([`2026-11-09-handover.md`](2026-11-09-handover.md)). Every fact has its home in the record; this note links there.

## 1. Where the project stands

The user asked where the project stands; the answer followed the handover and `state.md`. `state.md` §1 named older heads than §6.1 (`unified` 23022b0ec7, TraitWorld 6b342e9); fixed in this session's commit.

## 2. The core files

The user: "Delete the core dumps". The four untracked core files (about 10.9 GB) were deleted: `core-login02-842363` (a Claude Code crash), `core-login02-864686`, `TraitWorld-unified/core-login02-3042057`, `forks-unified/DataFrames/test/core-login02-1710729` (Julia crashes on the unified build).

## 3. The compiler by facts?

The user: "Okay, what are the next steps? Compiler compiled by facts and checking if that makes it dramatically slower on plain code?"

- The traced sessions of E-326 (`experiments/unification/e326/trace-*-w326b.jl`) attribute to recompiling the compiler about 9 ms of the goal's task's 273 ms traced, 17 ms of setting D's 1,526 ms and 17 ms of TraitReport (t)'s 163 ms. E-295 brought the compiler's invalidations by upstream CSV and DataFrames to 195 instances against vanilla's 193.
- So the compiler compiled by facts could win at most 10–20 ms per session; the cost E-318 and E-325 point at is Base's code compiled plainly (the REPL's display invalidated by DataStrings' methods; validation's costly edges in plain code failing G2).
- Not run. The recommendation given: open issue 164's decision first, then Base's printing by facts as the experiment.

## 4. Open issue 164 becomes `IO` as Base's trait

The user: "What's 164 again?", then: "The real point here is that Base should support and default to Dynamic{IO} right?"

- Agreed, as 164's proposal (c) at its root. Four points it meets: traits §7.5's exception for Julia's own types (the REPL's stream is Julia's); the run-time cost of a stream compiled once; negatives at an open set (`x isa IO`, guards at `print`, `write`, `show`), which the flagged item's proposal (d), finality by ownership, would remove; `IO`'s contract.
- The user: "Yes please." to recording it as 164 (d) and to a proxy measurement.
- **E-328** (registered before the run, `experiments/unification/e328/`): the smoke run showed `IOContext{IO}` 4.4–5.1× on byte and short-string writes; a variant emulating the split first came out slower than erasure, because its fallback's untyped result made Base's `Int(unsafe_write(…))` a second dynamic call; with the declared result asserted, as compiler §7.2 has it, the split recovers most. Two variants added to the row before the full run. Outcome in the registry and evidence §2.

## 5. The decisions

The user: "Finality should be opt in. Everything else is approved."

- Recorded in the references (traits §3.4, §7.5, §9b; facts §2.2, §10; compiler §4.8, §6.3, §7.5), decisions §9 (two rows the user's, two mine), open issue 164 closed, the flagged item's proposal (d) decided opt-in, 158's second case noted, W-129 queued, PE-19 returned to the queue as W-129, the alternatives not taken in `design/alternatives.md`.
- Mine, for the user to confirm (open issues §1): opted in per trait, spelled `@closed_after_load`; the final negative as an edge on the pair's cell; `IO` closed after load; `IO`'s declared results; the candidates' order `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`.
- Read "Everything else is approved" as the other two decisions listed for 164 (d) (step 4's exception not applied to `IO`; `IO`'s contract with `IOBuffer` among the candidates) and the recommendation (d) itself, with (a) not merged.
