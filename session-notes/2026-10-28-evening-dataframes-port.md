# 2026-10-28, evening: the membership exploration's §11, the DataFrames port's D2–D4, W-82's builds, M6

The chronology of the evening, after `2026-10-28-day.md`. Not the home of any fact: each one is in the document named.

## The user's words

- "Go back to the Fable agent. Any creative principled original solutions to the 'two kinds of membership' issue?"
- "Good to know. For now we continue with the large scale ports to learn more about the design as it stands today."

## What was done

1. **The exploration's §11** (design 5f58e58): one kind of membership is possible under an ownership rule (C4, Lemma O extended to memberships, with C3 and C7); experiments U6 and U5 proposed. W-83 deferred by the user (9afe000).
2. **W-82, `Dynamic{X{T}} where {T}`, merged** (TraitWorld 3fcff02) with the member check's exemption for a declared `Union{}` result; **E-211 (D2) done:** the forks precompile and pass their upstream suites; the pooled path is taken through `Dynamic` columns.
3. **E-212 (D0):** the session in four settings. The forks 4.4–4.5 s wall, upstream 11.9–12.5 plain, 9.6–10.5 wrapped as trait modules, 7.5–7.6 under `all`. Wrapping upstream met two refusals of rule 3 (Tables' `nrow`/`ncol` for `NamedTuple`s, DataFrames' `vcat(dfs...)`); resolved by DataAPI naming Tables a joint owner, as SciMLBase does, and by naming `vcat`'s first frame.
4. **E-213 (D1):** a third of the forks' import is 28 family members of `Column` checked again at each load, members that CSV's and DataFrames' images folded. W-84 queued (where an image keeps a member's recorded fix is open).
5. **E-214 (D3):** the kernels 2–20× slower than upstream at first. Three causes: a boxed counter in the forks' `_group_rows!` (a plain-Julia bug), columns not opened at the kernels' entries, and cells copied for plain code. The last met traits §7.4's rule ("every other parameter is named by a field outside a bound"): open issue 96, decided as mine (a parameter named only by a bound is read from the kept value) and built (TraitWorld bdaf4b3), so `CellVector{T, C <: Column{T}} <: AbstractVector{T}` reads cells in place. After: within 1.5× of upstream except `groupby` (1.6–2.4×, the per-column codes written out).
6. **E-215 (D4):** no kernel worker for a schema whose column types were seen.
7. **T-18 built** (open `Callable` result types; TraitWorld bdaf4b3), for the port's user functions. During the build TraitWorld's source was edited while a suite run used it (against the machine's practice); every suite was run again on the final state (`experiments/checks/logs/w82c/`).
8. **E-216 (M6) done** (the three suites pass, digests equal): `ByRow` over one or two columns through `ColumnCore.byrow`, the function a `Callable` at the cells' types. Results equal to upstream's, element types included. A new closure's first call of the kernel 6 ms against `map`'s 18 ms; end to end a new closure's `transform` 24 ms against upstream's 25 ms, because the plain `ByRow` method and the mini-language are compiled per closure type before the kernel; the steady state 2–3× slower (the `Dynamic` call per row).
