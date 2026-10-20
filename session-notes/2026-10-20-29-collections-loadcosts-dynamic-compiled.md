# Session 29, continued (2026-10-20): collections, load costs, `Dynamic` and `Compiled`

The second note of session 29 (the first, `2026-10-18-29-reviews-and-decisions.md`, runs to the measurement round of 2026-10-20). The user's words are in the decision log (`../writeup/record/decisions.md`), with dates; this note is the chronology and the pointers.

## To resume

1. `../CLAUDE.md`: the rules for documents (one home per kind of fact; what changes together).
2. `../writeup/record/todo.md`: the work queue. **Next: W-4**, the language of `Dynamic{X}` and `Compiled{X}`.
3. `../writeup/plans/2026-10-20-dynamic-and-compiled.md` **§0**: the rule the user adopted (sections 1–5 are the earlier form, kept for their reasoning). Open issue 33; decision log §3, the rows of 2026-10-20 on `Dynamic` and `Compiled`.
4. `../writeup/state.md`, the references (`../writeup/reference/`), `../writeup/open-issues.md` §1.

**W-4's next steps** (none started):
- **Prototype in TraitWorld** (main, 9fd18db and the `verify_main` fix after it): every trait-world value `Dynamic` or `Compiled`, set at crossing; the default `Compiled`; a trait's default `@dynamic` in its body (`Callable` declares it, replacing its `DynamicCall` default); a boundary's annotation `f(x::Dynamic{X})`, `f(x::Compiled{X})` overriding the trait's, with a warning when they disagree; `compiled_for(x)` and `with_dynamic(x)` always winning, inside and outside trait code; untyped values out of trait-world values (items of `Vector{Any}`, `Dict{K,Any}` values, abstract fields, trait-typed results) `Dynamic`; values carry their attribute (also from library to library); a warning for an annotation on a function neither exported nor public. `Callable`'s modes re-expressed on top, its tests unchanged.
- **The measurement** (a new registry row; on a quiet machine): TraitDifferentialEquations' new problem type with `solve` at a `Dynamic` position against `Compiled`: first solve in a fresh session (expected near a dynamic callable's 19–25 ms, against 335–371 ms) and the run time per step. Rows timed whole, GC reported (`TraitDifferentialEquations/scripts/rows.jl`, `experiments/loadcosts/run_rows_whole.sh`).
- **Then the references:** traits §4, §9, §10 (and §3.7: abstract parts of a key become `Dynamic`, no automatic opening) around the two attributes; receiver types and keys to lowering §5 as the optimization of `Compiled`; the glossary.
- After W-4: W-2 (TDE around `ODEProblemTrait`, written in the new language), W-3 (abstract types against traits).

**Machine:** the user reported it noisy in the afternoon; timings since then are indicative. One Julia job at a time, through `flock /tmp/claude-1000/julia-review.lock nice -n 19`.

## What was done (in order)

- **Heterogeneous collections, a fresh-eyes review** (`../writeup/reviews/2026-10-20-heterogeneous-collections.md`, `experiments/hetero/`): the facts tails reach trait code calling Base on plain containers; the cost is lost inlining, not dispatch; facts §3's "limit of four" misstated; `Dynamic` beyond four order-dependent. The user's framing: the facts mode is for calling smoothly into ordinary code, idiomatic trait code is judged separately; `Vector{AbstractType}` is a poor substitute for an `Iterable` trait (open issue 31; rationale §2.4).
- **E-140, a plotting session with upstream packages only** (`experiments/plotwork/`): `all` saves 6–10 s of recompilation per session, a round costs 91–169 ms more; break-even after 42–67 rounds.
- **The registry of experiments** (`../writeup/record/experiments.md`, E-1 to E-146) and **the rules for agents** (`../CLAUDE.md`).
- **`design.md` is the one rationale** (the argument merged in; `design/argument.md` a pointer); **the comparison** is `design/other-languages.md`, the research of 2026-10-16 moved to the record; a fresh-eyes proofread of the rationale (step 2 stated for fully typed code; terms defined at first use).
- **What follows the `Dynamic` split** (open issue 32, E-145 proposed): the split stays; options for the fallback, including recompiling in the background (the user: guarded devirtualization's problem was the permanent slowdown).
- **Load costs diagnosed and fixed** (E-141, E-142, E-146; `experiments/loadcosts/README.md`): TraitWorld 226db6a (`_tw_type` machinery; the generators' code fully typed), TraitDifferentialEquations 99393b9 (a function barrier); `rows.jl` times first calls whole and reports GC. Every TDE row the same in every load order but the first gradient (W-7). Found: `@elapsed` hid each call's own compilation; a new problem type's first solve is 335–371 ms whole. The 435 ms residue: SparseArrays' `vcat` recompiling `CSV._parse` (86–89 %), waiting on open issue §1.19.
- **BaseTraits v0, merged into TraitWorld's main** (9fd18db; W-1 done): `HasLength`, `Iterable{T}`, `Indexable{T}`, `MutableIndexable{T}`, `Resizable`, `Keyed{K,V}`, Base's containers conforming; `Dynamic` holds the user's object, construction 5 ns, the split's candidates in declaration order; a container with untyped items crosses implicitly, by the bound, a non-conforming item failing when read (`experiments/hetero-idiomatic/`). The crossing's finer choices wait for the user (open issues §1 item 26). Every suite passes (`experiments/checks/run_all.sh`, logs `after-basetraits-merge/`), but the known F-8 under `all`.
- **The website:** programmers first (with Porting to traits), then core developers, then the references, then the record.
- **The work queue** (`../writeup/record/todo.md`) and **the `Dynamic`/`Compiled` rule**, worked out with the user step by step (proposal §0; decision log §3).
