# 2026-10-28, evening: the membership exploration's §11, the DataFrames port's D2–D4, W-82's builds, M6

The chronology of the evening, after `2026-10-28-day.md`. Not the home of any fact: each one is in the document named.

## The user's words

- "Go back to the Fable agent. Any creative principled original solutions to the 'two kinds of membership' issue?"
- "Good to know. For now we continue with the large scale ports to learn more about the design as it stands today."
- "Can you summarise the learnings from the DataFrames port so far briefly?"
- "Go for it and continue with the other ports afterwards."
- "I have a side question, is there any tooling that would make debugging the various slow downs everywhere easier?"
- "Great, continue. I will be gone for the next couple of hours"
- "One note on Solvers. One of the especially important aspects in DE.jl is that it is possible to use various linear/nonlinear solvers within Rodas/etc..."
- "Go"

## What was done

1. **The exploration's §11** (design 5f58e58): one kind of membership is possible under an ownership rule (C4, Lemma O extended to memberships, with C3 and C7); experiments U6 and U5 proposed. W-83 deferred by the user (9afe000).
2. **W-82, `Dynamic{X{T}} where {T}`, merged** (TraitWorld 3fcff02) with the member check's exemption for a declared `Union{}` result; **E-211 (D2) done:** the forks precompile and pass their upstream suites; the pooled path is taken through `Dynamic` columns.
3. **E-212 (D0):** the session in four settings. The forks 4.4–4.5 s wall, upstream 11.9–12.5 plain, 9.6–10.5 wrapped as trait modules, 7.5–7.6 under `all`. Wrapping upstream met two refusals of rule 3 (Tables' `nrow`/`ncol` for `NamedTuple`s, DataFrames' `vcat(dfs...)`); resolved by DataAPI naming Tables a joint owner, as SciMLBase does, and by naming `vcat`'s first frame.
4. **E-213 (D1):** a third of the forks' import is 28 family members of `Column` checked again at each load, members that CSV's and DataFrames' images folded. W-84 queued (where an image keeps a member's recorded fix is open).
5. **E-214 (D3):** the kernels 2–20× slower than upstream at first. Three causes: a boxed counter in the forks' `_group_rows!` (a plain-Julia bug), columns not opened at the kernels' entries, and cells copied for plain code. The last met traits §7.4's rule ("every other parameter is named by a field outside a bound"): open issue 96, decided as mine (a parameter named only by a bound is read from the kept value) and built (TraitWorld bdaf4b3), so `CellVector{T, C <: Column{T}} <: AbstractVector{T}` reads cells in place. After: within 1.5× of upstream except `groupby` (1.6–2.4×, the per-column codes written out).
6. **E-215 (D4):** no kernel worker for a schema whose column types were seen.
7. **T-18 built** (open `Callable` result types; TraitWorld bdaf4b3), for the port's user functions. During the build TraitWorld's source was edited while a suite run used it (against the machine's practice); every suite was run again on the final state (`experiments/checks/logs/w82c/`).
8. **E-216 (M6) done** (the three suites pass, digests equal): `ByRow` over one or two columns through `ColumnCore.byrow`, the function a `Callable` at the cells' types. Results equal to upstream's, element types included. A new closure's first call of the kernel 6 ms against `map`'s 18 ms; end to end a new closure's `transform` 24 ms against upstream's 25 ms, because the plain `ByRow` method and the mini-language are compiled per closure type before the kernel; the steady state 2–3× slower (the `Dynamic` call per row).
9. **E-217 (M7):** the writer's fallback columns through a `Column` kernel; a plain bug made visible on the way (a column type of unknown width bounded its cells by the whole buffer: blocks of two rows). Steady write 7.75 ms against upstream's 21 ms; a schema of seen column types 0.8 ms against 368 ms.
10. **W-85 queued:** tooling for slowdowns (a report of a trait call's path, Cthulhu over facts code, an A/B harness, a load-time report), the user's side question.
11. **E-218 (SciML's X6):** a capability chosen by the stored object's traits serves an integrator; 361 ns a call against 74 ns for one bound (W-17).
12. **E-219 (Makie's X3, slice 1):** upstream's `stairs.jl`, unchanged, over TraitMakie through `MakieCompat`; PNGs equal byte for byte; first PNG 66 ms with a workload (the core's 42 ms); nothing recompiled after a late load. A TraitWorld bug found and fixed: the ownership precheck of a family implemented with methods by the members' owner.
13. **E-159 (SciML move 3), stages A and B:** the solvers an open set (`ODEAlgorithm`, its operation the solver's driver); the core and Rodas5 packages of their own, the front end in its owner, no pirate; a bounded front end on CommonSolve's `solve` meets L-3 (evidence for W-83's §11). Two TraitWorld lowering gaps fixed: a bounded function inside `Base.@nospecializeinfer`, and `@nospecialize` on ordinary arguments.
14. **E-220 (stage C),** after the user's note on solvers inside solvers: linear solvers an open set inside Rodas5, from a package Rodas5 does not know and from the prompt; compiled once when `Dynamic`, no measurable cost per step.
15. **E-221 (stage D):** nonlinear solvers (`NonlinearSolver`, Newton by default) taking linear solvers, inside an implicit method in a package of its own: three open sets nested across four packages; a user's pair at the prompt, in a trait module.
16. **E-160 (SciML move 4):** symbolic access as traits (a stand-in for SymbolicIndexingInterface): names from the problem's `sys`, the solution given its problem's parameters and names by the outer layer; getters per index shape; the sugar inferred by plain callers. Two TraitWorld gaps fixed: `where` variables in a tuple bound's members, and a bounded function's declared result on its entry.
17. **E-222 (Makie's X3, slice 2):** the umbrella owns the old API's names, the layer is its joint owner (without the declaration the layer does not load); the PlainPlots control: after a late load an old recipe over PlainPlots recompiles 166 ms, over the trait core 7 ms with nothing recompiled.
