# The evidence

What is measured for each goal of [the goals](../goals.md#1-the-goals), against what, and what is not shown.

- **A number is always against plain Julia or Python.** Plain Julia is vanilla v1.13.2, or the same code without traits on the changed Julia ("plain code on the build"); the row says which. Python is SciPy with matplotlib, or pandas with matplotlib, on the same task.
- **A row** holds what is measured; the number with traits, or by facts alone (the facts rule needs no trait); plain Julia's; Python's where a Python run exists; the build; the experiment.
- **The experiments** are registered in [the registry](../record/experiments.md): the question, the setting, the runs, the logs. A comparison of the implementation with an earlier state of itself is a regression control. It stands in the registry's last section, and no claim here cites it.
- **The build** column names the branch and the commit. `next` is the head of the changed Julia; it continues `unified`, and `next-s3` is merged into it: one implementation. Where a row names `next` cf0f039f51, the library and the demonstrators are the heads of [the state](../state.md) (TraitWorld `unified` 42d60e1).
- **Unless a row says otherwise:** the product setting, strict mode off, one thread, fresh processes, ranges over the runs. "The forks" are the ports of CSV, DataFrames and Tables.
- The page as it stood, with every earlier number: [the snapshot](../../attic/writeup/design/evidence-2026-11-18.md).

## The problem in plain Julia

What plain Julia does where the design sets out to change it. No trait code is involved.

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| A package's load invalidates compiled code | — | `using CairoMakie` invalidates 3,539 CodeInstances on 1.11; on 1.12, 769 method-table signatures, none concrete (216 of 217 roots abstract) | — | stock 1.11 and 1.12 | E-1 |
| Code kept by a workload, then one unrelated definition | — | 100 functions reached by dispatch: 460 ms → 0.0 ms per session; one definition in an unrelated package destroys all 100 (462.7 ms) | — | stock Julia (version not documented) | E-2 |
| Whether invalidation is exact at concrete signatures | — | exact in all nine cases: a definition invalidates iff it wins at the signature or makes the call ambiguous | — | stock 1.13.2 | E-23 |
| Compiling per user type in a plotting library | — | Makie's recipes about 167 ms per table type; in `x8_types.jl` a recipe 297 ms per type | — | stock Julia (version not documented) | E-3 |
| Compiling per wrapper type | — | 30 wrapper types: 32 specializations, 6.8 ms; behind a function barrier 1 body, 0.2 ms | — | stock | E-7 |
| One abstract field deep in a type hierarchy, per element | — | 66.0 against 0.89 ns, 74×; 66–71× on 1.13.2 | — | stock; stock 1.13.2 | E-4 |
| SciML's first calls | — | Tsit5's first solve 0.16 s; a `DiscreteCallback` 0.84–0.96 s; Rodas5 1.43 s; the first gradient 1.97–2.73 s, a second loss closure 2.48 s; a `Float32` state 2.06 s | — | stock 1.12.2; stock 1.13.2 | E-6 |
| A first ODE-and-plot session | — | upstream OrdinaryDiffEq and CairoMakie: 9.16–9.17 s (load 3.5 s, first solve 3.75 s, first plot 1.5 s, second model 0.19 s); with CairoMakie loaded after the first solve 9.72–9.75 s, 0.44 s of it compiled again | SciPy, matplotlib: 1.45–1.46 s | stock 1.13.2; a warm-up and two sessions; two cores | E-168 |
| Where a stock load spends its time | — | edge validation about 34% (about 1.4 s), method activation about 27% (about 1.1 s), finding stale caches 7% | — | stock 1.13.2; one session | E-185 |
| What share of Makie's code a workload's plot runs | — | 2,710 of about 44,400 code lines (6.1%), in 52 of 150 files | — | stock 1.13.2 | E-183 |
| SciML's run-time error messages | — | 71–101 lines, 22–44 frames, a longest line up to 33,673 characters; `typeof(integrator)` 3,553 characters. C++ templates and concepts: 28–33 lines | — | stock 1.12.2; GCC 14.2 | E-5 |
| A bare process | — | 0.145–0.165 s (stock 1.13.2), 0.168–0.186 s (vanilla); the changed Julia 0.183–0.185 s | `python -c pass` 0.019–0.022 s; `import pandas, matplotlib.pyplot` 0.56–0.58 s | stock 1.13.2, vanilla v1.13.2, `unified` 350c5b1c59; a warm-up and 5 runs | E-291 |

<a id="1-the-guarantee"></a>

## G-1 Recompilation

**The claim:** traits and facts cut compilation and recompilation. Compiled code is kept through unrelated loads, and trait code is compiled once where its contract allows ([facts §2.2](../reference/facts.md#22-g2-stable-caches)).

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| Nine unrelated loads after the work: own image instances lost; the work after the loads | by facts, upstream CSV and DataFrames with one line per module: 14 of 3,490 (0.4 %: DataFrames 10, CSV 4); 1.45–1.46 s | upstream, plain code on the build: 426 of 4,688 (9.1 %); 5.19–5.32 s | — | `next` cf0f039f51; order A (the work, the loads, the work again), a warm-up and 2 processes, interleaved; load 2.6–3.1 | E-511 |
| The same, for the forks | with traits: 150 of 5,705 (2.6 %: CSV 137, DataFrames 12, PooledArrays 1); 2.19–2.34 s after the loads, against 0.19 s first. What ends them: 162 entries of the load's log hang from SparseArrays' method of Base's `_cat`, through Base's `vcat(::Int64, ::Vector{Int64})`, to CSV's `_parse`, `_parseprepared` and `_filefromprepared`; 32 from FilePathsBase's method of `open` | upstream, plain code on the build: 426 of 4,688; 5.19–5.32 s, against 4.45–4.46 s first | — | `next` cf0f039f51; as the row above; the causes from `w134/cause.jl`, one process, the work first | E-511 |
| Code in the deep class through the nine loads | by facts: the loads end no own instance in the class. In the class: the forks' own facts instances 63.1 %, upstream's by facts 79.0 % | — (a count) | — | `next-s3` bc844be7c0; one process per row | E-478 |
| The demonstrators' images through the nine loads | with traits: the table session loses no trait package's instance of 3,757 (Colors 6), 0 of 644 facts instances, and compiles nothing after; the ODE session none of 4,806 (ForwardDiff 7, CommonSubexpressions 6), 0 of 1,043 facts instances, 81 ms after | the table session's plain twin loses 28; 330–331 ms after the loads | — | `unified` 21c9b33e39; 2 runs per order | E-377 |
| Twenty small packages, each adding a member to one trait, in five load orders | with traits: 0 instances ended in every order, 160 instances, nothing compiled after a load, 8.2 ms of compiling per member | the plain twin loses 9 | — | `unified` 21c9b33e39; five orders | E-378 |
| A new type and an edit at the table's prompt, after the session's work | with traits: the work with a new cell type 523 ms, with a new column struct 145 ms (the struct defined in 66 ms); the edit of `summarize` defined in 0.235 s, then 9.3 ms, ending nothing | the plain twin (PlainTables) on the build: 535 ms, 144 ms (defined in 4.8 ms); the edit defined in 70.5 ms, then 6.7 ms, ending 3, then 2 | — | `next` cf0f039f51, TraitTables e1ec1f4; a warm-up and 2 processes; load 2.4–2.9 | E-512 |
| A new closure, a new struct and an edit at the ODE port's prompt | with traits: the work with a new closure 54 ms, 8 own instances compiled; with a new parameter struct 293 ms, 57 instances; an edit of `save_step!` defined in 82 ms, ends 63 facts instances of the port, the work after it 315 ms; an edit of `initdt` 18 ms, ends 11 | — (no twin) | — | `next` cf0f039f51, TraitDifferentialEquations 06c28c3; a warm-up and 2 processes | E-512 |
| An edit of a method at a trait, with the library alone | with traits: TraitTables' `summarize` 4.5–4.6 ms to define, 10.4 ms to the box's first call; the box's first call infers nothing | — | — | `next` 75a7f1795b; a warm-up and 5 edits, the median | E-440 |
| A first ODE-and-plot session | with traits: the ODE port with TraitMakie 1.89–1.91 s | upstream OrdinaryDiffEq and CairoMakie: 9.16–9.17 s | SciPy, matplotlib: 1.43 s | traits: `unified` 9c6c9270f3 (E-389); plain: stock 1.13.2 (E-168) | E-389, E-168, E-230 |
| A membership's walk at the forks' load | with traits: no method takes the conservative path; 1,228 instances in the load's log, 1,220 without the walk | — (a count) | — | `unified` 8fccf1e182; 3 runs a mode | E-390 |

**Not shown.**
- The forks' entry chain is lost to unrelated loads: CSV's reader, ended through Base's plain code by a standard library's method below `vcat` and another package's method on `open` (GT-8).
- The library's own hooks are ended by a port's load and compiled again: 15 of TraitWorld's instances at the ODE port's, the forks' and NetworkDynamics' loads, 0.20 to 0.24 s at the ODE port's (E-516); 16 in the forks' session after the nine loads (E-511). The cause and the proposal: [open issue 254](../open-issues.md#5-implementation-and-measurements).
- The ODE-and-plot row is not like for like: the demonstrators have a fraction of SciML's and Makie's features.
- The plain twins are written as plain Julia is commonly written. A twin hardened by hand at its barriers is not measured.
- Load protection for a package wrapped whole as a trait module, at the scale of NetworkDynamics with 186 packages loaded after its first simulation: measured only on the library of October 2026 (E-153 in the ledger); not measured on this implementation.

<a id="2-run-time"></a>

## G-2 Run-time speed

**The claim:** no regression against plain Julia where types are known, and a caller opts into full speed with `compiled_for(x)` ([traits §7.6](../reference/traits.md#76-compiled_forx)). No claim of better steady-state speed.

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| An operation, and a method at the trait, at a known type | with traits: 0.79 ns each | 0.79 ns | — | `next` cf0f039f51; 10^7 calls, the minimum of 7, two processes, the plain twin in the same process | E-513 |
| A call of an argument declared `Callable` | with traits: the wrapper `compiled_for(f)` 0.79 ns; the default, a box made at each call, 25.19–25.31 ns; a box held 25.25 ns | a plain argument 0.79 ns | — | `next` cf0f039f51; as above | E-513 |
| A plain member passed to a method of a trait that erases by default | with traits: 8.63–8.68 ns as it is (a box made at each call); a box held 7.15 ns; 2.38 ns with `compiled_for` | 2.38 ns | — | `next` cf0f039f51; as above | E-513 |
| An operation on a value known only by its trait | with traits: a box of the first member (a branch of the split) 5.56 ns; of the sixth (through the table's pointer) 9.14 ns | Julia's dynamic call of a value held as `Any` 18.4 ns | — | `next` 5b1900641f; 10^7 calls, the minimum of 5 | E-443 |
| An element of a vector typed by the trait, two member types | with traits, a `Vector{Shape}`: 2.86–2.87 ns | a `Vector` of the abstract type 2.70 ns; of the union 3.19 ns; of one type 2.34 ns | — | `next` cf0f039f51; as above | E-513 |
| A field typed by the trait | with traits, a field `::Dynamic{Shape}`: 5.56 ns | an abstract field of two subtypes, split: 0.79 ns | — | `next` cf0f039f51; as above | E-513 |
| Printing to a stream that plain code knows, `IO` a closed type with a contract | with traits: within vanilla's noise, 0.79–1.10× by the minimum | vanilla v1.13.2, the same workloads on an `IOBuffer` | — | `unified` b05ae361e0; a warm-up and 3 runs | E-337 |

**Not shown.**
- Better steady-state speed: not claimed.
- An operation on a box past the split's branches goes through the table's pointer (GT-7, below).
- A stream erased on purpose: up to 4.99 times the stream's type known (GT-5, below).
- NetworkDynamics' workload: the session 43.6 and 44.1 s, the first pass 19.5–20.2 s, the steady state (`again`) 312–313 ms (E-514, `next` cf0f039f51, NetworkDynamics c2bbf0d; a warm-up and 2 sessions). No plain run is beside it: upstream's packages on vanilla run SciML's solvers, another program, and were not run (no images in vanilla's depot). Its steady state against upstream's: measured only on the library of October 2026 (E-250 in the ledger); not measured on this implementation.
- The solver's time per step against OrdinaryDiffEq's: measured only on the library of October 2026 (E-163 in the ledger); not measured on this implementation.

<a id="3-first-calls-and-sessions"></a>

## G-3 Caching

**The claim:** what is compiled is kept in package images ([compiler §9](../reference/compiler.md#9-images-and-the-machine-code-cache)). No cache across sessions is built.

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| Two independent packages first combined in a session: A's algorithms at B's type | with traits, compiled for the type: none in the session where a package declares the membership, with no workload; compiled once: none in any case, 18 ms for the two operations' pointers; a membership declared in the session 139 to 144 ms | compiled in every session, 8 instances, 130 to 135 ms of a first run of 277 to 290 ms, unless a workload names the combination | — | `unified` 86deee2f98; a warm-up and 3 runs per case | E-375 |
| What a session still compiles that no image holds | with traits: the ODE session 2.68–2.72 s, of it 1.35 s the harness's `verify.jl` ([open issue 256](../open-issues.md#5-implementation-and-measurements)); 871 ms of compiling: the session's own 306 ms, Julia's own 243 ms, compiled again 236 ms (the library's hooks at load, [open issue 254](../open-issues.md#5-implementation-and-measurements)), a package's own image could hold 61 ms, a composition 26 ms. The table session 0.67–0.71 s, 169 ms of compiling: the session's own 70 ms, Julia's own 94 ms, compiled again 6 ms, none of it a library's | the ODE session with PlainODE on the build: 0.85 s, 550 ms of compiling: the session's own 366 ms, Julia's own 179 ms | — | `next` cf0f039f51; a warm-up and 3 runs, the last run's compiles; load 2.3–2.4 | E-521 |
| A member's image, on a real library | with traits: a column member 42 instances, 127,640 bytes; a problem member 74 and 168,336 | the plain twin's column: 146 instances, 266,448 bytes | — | `unified` 21c9b33e39 | E-380 |
| An image holds what a run-time site in code compiled by facts reaches | by facts: the library's compiles in three sessions 2/6/4 (16/48/32 ms) with the rule, 5/10/8 (97/153/146 ms) without; the library's precompile 8.4 s (4.8 s without), its image 6.5 MB | — | — | `unified` 6767b03893; a warm-up and 3 runs | E-326 |
| An image keeps the member checks that pass while it is built | with traits: kept and restored; a method outside the declared result is refused before any use | — | — | `unified` b1c0b50f4c; one run | E-366 |
| Code the system image holds without machine code | — | compiled by the JIT in every session: in the CSV-to-histogram task 8 of 28 compiled instances, 45.6 of 309.7 ms | — | `unified` 352b916899 (source); one traced session | E-351 |
| What a load validates, after the nine loads | by facts: deep code holds 68.3 % of the 7,484 instances the forks' CSV and DataFrames bring, 49.9 % of the edges, 129 of 701 calls by signature (18.4 %) | — (a count) | — | `next-s3` bc844be7c0 | E-480 |

**Not shown.**
- A cache across sessions, with its gain: not built (below, "Not shown").
- A failed member check, and one no image ran, are asked again in each session (compiler C-30).
- Validation remembered for an unchanged environment: deep code holds most of a load's instances but under a quarter of its calls by signature (E-480), so it is not built.
- A cache across sessions, emulated or keyed on the environment: measured only on the library of October 2026 (E-175, E-180 in the ledger); not measured on this implementation.

## G-4 Downsides

**The claim:** limited to none. What the design costs code that uses no trait, and code that does, is small and stated. Each tension's cost is in [the table below](#what-each-tension-costs).

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| Plain code's first work (upstream CSV and DataFrames) | — | plain code on the build 3.316–3.342 s, vanilla 3.252–3.281 s: 0.07 s more at the median (open issue 225) | — | `next` cf0f039f51; vanilla v1.13.2 45b6d15e34; a warm-up and 3 runs, interleaved; load 2.5–3.5 | E-515 |
| Plain code's repeated work, the median | — | plain code on the build 0.18–0.19 ms, vanilla 0.18 ms | — | `next` cf0f039f51; vanilla v1.13.2; as above | E-515 |
| The library loaded late, after plain work | with traits: 168–170 ms (58–80 ms loaded first), ending 0 of 120,780 plain instances; the work after it 1.05–1.08 ms. Of the profiled load's 381 samples, 277 are in the library's load-time callback, 221 of them code generation: its image code is invalid after CSV's and DataFrames' methods ([open issue 254](../open-issues.md#5-implementation-and-measurements)) | — | — | `next` cf0f039f51; 3 runs; the profile one process | E-515 |
| Base's patches that bring callees into the deep class | — | plain code on the build with and without them: nothing measurable; first work 3.355–3.359 s against 3.351–3.370 s; the system image +0.16 % | — | `next-s3` bc844be7c0; 3 runs each, alternating | E-479 |
| A load (`using`) | with traits: TraitWorld 58.7–60.5 ms, TraitTables with TraitCSV 153.0–153.7 ms, the ODE port 505.9–509.2 ms, TraitMakie 245.3–256.6 ms, the forks 1.19–1.21 s, NetworkDynamics 1.96–2.05 s. By facts, upstream CSV and DataFrames 586.8–588.5 ms | upstream plainly: 748.0–751.6 ms on the build, 652.1–660.6 ms on vanilla | — | `next` cf0f039f51; vanilla v1.13.2; a warm-up and 3 runs; load 2.6–3.3 | E-516 |
| What a load ends of the library's own code | with traits: 15 of TraitWorld's own instances at the ODE port's, the forks' and NetworkDynamics' loads, 0 at TraitTables' and TraitMakie's: a method of `promote_rule` that the port's dependencies add ends Base's plain `string(::Integer)`, `promote(::Int64, ::Integer)` and `sprint(showerror, …)` over a `Vector{Any}`, which the library's hooks call. They are compiled again in the session: 0.20 to 0.24 s at the ODE port's load ([open issue 254](../open-issues.md#5-implementation-and-measurements)) | — (a count) | — | `next` cf0f039f51; the causes from `probes/lib_ended.jl`, one process | E-516 |
| What the ODE port's load does | with traits: one profiled load, 469 samples: 148 in code generation (the hooks compiled again), 133 in the packages' load-time callbacks, 83 in the memberships' activation, of them 57 in the membership walk; 50 in the library's hook for an image's methods ([open issue 255](../open-issues.md#5-implementation-and-measurements)) | — | — | `next` cf0f039f51; one process, `probes/load_profile.jl`, 1 ms | E-516 |
| A package image: bytes, and seconds to write it | with traits: TraitTables 1,266,816 bytes, 1.99 s; the ODE port 4,495,400, 15.37 s; TraitMakie 4,633,152, 5.92 s; the library 6,883,472, 6.21 s | the plain twins on the build: PlainTables 1,453,648, 1.60 s; PlainODE 3,718,056, 3.23 s; PlainPlots 2,445,640, 2.45 s. The twins are smaller programs than the ports (fewer solvers, fewer plot kinds): not like for like | — | `next` cf0f039f51; each image written once anew into a scratch depot | E-517 |
| The system image, and Julia's build | — | the system image 212,164,208 bytes on the build, 194,307,784 on vanilla (+9.2 %). Base's stage of the build 32.37 s against vanilla's 32.48 s; the compiler's stage 387 s against 326 s (+19 %, at a load of 1.5 against 8.0); the whole build 829 s against 790 s | — | `next` cf0f039f51; vanilla v1.13.2; one build each, 64 jobs | E-517 |
| Upstream's REPL session, plain code | — | 14.1–14.4 s on the build, 13.5–13.6 s on vanilla | — | `unified` 21c9b33e39; a warm-up and 3 runs | E-386 |
| Inference on plain code, upstream's eight steps | — | 3.12 s on the build (the steps 9.91 s), 2.08 s on vanilla | — | `unified` 9c6c9270f3; a warm-up and 2 or 3 runs | E-389 |
| Subtyping: a non-member against a set | with traits: 23.6–24.4 ns at 0 to 50 entries; a member 25–27 ns, through three set-in-set entries 171 ns | an unrelated pair on vanilla 14.1–14.3 ns: 1.7–1.8× | — | `unified` fd800b27b9 and 29035cab11; five runs | E-270 |
| Methods at open sets on Base's hottest functions | with traits: dynamic calls 133–138 ns, a member's 141 ns; method matching +3 % (`getindex`), +7 % (`iterate`), +18 % (`length`), on inference and dispatch misses only | vanilla: dynamic calls 137–138 ns, the member type's call 151 ns | — | `unified` 3ad297247e and 8a9144928e; two runs per session, three sessions | E-269 |
| Base's tests | — | `subtype`, `core`, `ambiguous`, `worlds` pass on both, 16.1/67.7/8.6/8.6 s against 15.7/65.4/8.1/8.4 s; `detect_ambiguities(Base)` 0 on both | — | `unified` c3f0b4bc11; one run each | E-262 |

**Not shown.**
- Why plain code's first work on the head takes more code generation than vanilla's: not diagnosed; a bisection of `next`'s commits is under way (open issue 225, E-527).
- What the ODE port's load spends in the membership walk and the library's image hook, once the hooks are not compiled again at load: not attributed (open issue 255).
- A package image against a plain twin of the same program: the twins are smaller programs (E-517). A member's image against the twin's member: measured only on `unified` 21c9b33e39 (E-380).
- The facts rule's cost to plain code compiled by facts, on BaseBenchmarks under the test bed `all`: measured only on the library of October 2026 (E-163 in the ledger); not measured on this implementation.
- What the open rows of the references' Deviations tables cost: not measured.

<a id="4d-error-messages-against-plain-julias"></a>

## G-5 Error messages

**The claim:** better than plain Julia's: an error names the contract and the place where it is broken.

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| Thirteen mistakes against one small library: where each is reported | with traits: five at the line that makes the mistake; two more by a warning at the membership, an error under strict mode | four at a later call, one not at all | — | `unified` dd3f6d839b; vanilla v1.13.2; one run each | E-362 |
| The same messages | with traits: 2 to 5 lines, naming the trait, the type, the operation and its declared signature | 1 to 11 lines, naming the function that failed in the library or in Base under it | — | `unified` dd3f6d839b; vanilla v1.13.2 | E-362 |
| Library frames above the user's line, over the fifteen trait runs | with traits: 2, both at a use before the `@implement` | — | — | `unified` 381cc8b953; one run each | E-370 |
| The fifteen mistakes on the head; an operation called outside its declared signature | with traits: each reported at the user's line; the call outside the signature is Julia's `MethodError` with the contract's hint at the calling line, 11 lines and 752 bytes | the plain forms on the build print what vanilla prints, in each of the twelve plain cases; no case is reported earlier in plain Julia. The same call: 6 lines and 353 bytes | — | `next` cf0f039f51; vanilla v1.13.2; one process per case | E-518 |
| A pirate at Base's plain function that code compiled by facts calls (`uppercasefirst(::String)`, case 05) | with traits: by default a warning names the pirate, its definer and the 4 instances it ended, and the program runs; under strict mode `PirateError` at the user's line, 3 lines, 486 bytes, naming the call that code compiled by facts makes | the program runs and prints the pirate's result, with no message | — | `next` cf0f039f51; vanilla v1.13.2; one process per case | E-518 |
| A function with no method at `A`, passed where `Callable{A, S}` is asked | with traits: refused at the line that passes it, by the method's own `MethodError` (traits T-156) | — | — | `next` eaa19da272 | E-500 |
| SciML's three run-time error cases: the message in full, in bytes | with traits, the port: 3,706; 9,471; 7,410 | upstream: 10,725; 14,380; 89,806. The port's plain twin: 2,606; 8,079; 4,448 | — | `unified` dd3f6d839b; upstream on vanilla v1.13.2; one run each | E-363 |
| The same, with types limited as the REPL prints them | with traits, the port: 2,609; 5,184; 4,886 | the plain twin (PlainODE) on the build: 2,478; 5,564; 4,063 | — | `next` cf0f039f51; one process per case | E-518 |

**Not shown.**
- On SciML's three cases the port is no better than its plain twin: none of the three is a mistake against a contract (open issue 177 (d)). Upstream says more in two of them: SciML's hand-written explanations.
- Two failures exist only in the trait form: a member by its definition used before its `@implement`, and a membership too new for running code (GT-14).
- Whether a reader fixes a mistake faster from the trait form's message: no study.

<a id="4-builds-and-binaries"></a>

## G-6 Compiling ahead

**The claim:** a trait bound handles generics as in Rust and Mojo. Fully typed code is the code that compiles ahead, and `make_executable` and `make_library` write a small binary of it ([compiler §7.6](../reference/compiler.md#76-a-closed-build), [§2.7](../reference/compiler.md#27-fully-typed-mode)).

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| Small trait programs under `--trim=safe` | with traits: `typed_trait`, `vector_trait`, `dynamic_trait` and `ft_union` build and run with the session's output, 2,062,432 to 2,223,416 bytes | the plain loop over an abstract type (`vector_plain`) is refused, 2 errors; `typed_plain` 1,923,592 bytes; `ft_plain_hole` builds and runs | — | `next` cf0f039f51; 7 of the 13 programs; one session, build and run each | E-520 |
| A loop over a vector typed by the trait | with traits: 0 errors, 2,550,896 bytes; no LLVM linked | the plain twin, a `Vector` of an abstract type: 2 errors | — | `unified` 97861c6b31; vanilla v1.13.2; one build each | E-364 |
| Every call at a concrete member | with traits: 2,479,552 bytes | the plain twin: 1,942,688 bytes on the build, 1,845,008 on vanilla | — | `unified` 97861c6b31; vanilla v1.13.2 | E-364 |
| `make_executable`, `make_library`, a `main` entered at the prompt | with traits: an executable 2,543,792 bytes; a shared library 2,392,456 bytes, called from C; a `main` entered at a prompt 2,526,016 bytes; an untyped program refused with `BuildError` | — | — | `unified` 97861c6b31 and b5c6ac2967 | E-364 |
| The session's fully typed check against the build | with traits: they agree on each of the 7 programs run (E-520); on 17 of 18, `bb_invokelatest` differing (E-384) | — | — | `next` cf0f039f51 (E-520); `unified` 21c9b33e39 (E-384) | E-520, E-384 |
| The demonstrators' programs: the verifier's errors under `--trim=safe` | with traits: the table, the plot, the report, the ODE program and an ODE program with callbacks it knows: 0 errors each, 2,724,576, 4,951,728, 5,393,960, 4,292,960 and 4,083,552 bytes; each runs and prints a session's output | the plain twins on the build: PlainTables 6, PlainPlots 80, the report's twin (PlainTables, PlainPlots) 86, PlainODE 8; none builds. On vanilla: the table's twin 12, the plot's 88, the report's 98, upstream CSV with DataFrames 768 (E-383, vanilla v1.13.2) | — | `next` cf0f039f51, TraitDifferentialEquations 06c28c3; the images written first, one build each | E-519, E-383 |
| The ODE session (a Lorenz and a Robertson solve): its first run | with traits: 347–350 ms, of it compiling 344–347 ms | the same session with PlainODE on the build: 374.6–376.5 ms, of it compiling 371.5–373.4 ms | — | `next` cf0f039f51; a warm-up and 3 runs, interleaved; load 2.3–2.4 | E-521 |
| Base's exported surface at broad types | — | of 6,179 signatures of Base's 837 exported functions, 71.4 % fully typed, 20.1 % with a hole, 8.4 % where the report failed; five standard libraries 68.8 % of 474 | — | `unified` f6ad3008b4; one run | E-368 |

**On the head** (`next` cf0f039f51, TraitWorld `unified` 42d60e1, TraitDifferentialEquations `unified` 06c28c3; E-519; one build each, every package loaded from its image): the five programs of the row above build under `--trim=safe` with 0 errors and run. The table's and the ODE programs' output equals a session's; the plot's and the report's standard output does, their PNGs were not compared in this run (on `next` dc11704ef7 they equal a session's byte for byte, E-510). The ODE program solves a Lorenz and a Robertson problem. Each build takes 5 to 15 s. The ODE port follows the design at its callbacks, its function and Rodas5's chunk (open issue 184).

**Not shown.**
- A program at a port's scale as a trimmed binary: the programs built are a demonstrator's main with one or two solves, a table's summary, a plot.
- A hole in Base below a trait program fails the build where the user cannot fix it (open issues 179, 181).
- The time of the build's check, asked in a session: not measured on a registered row (GT-16). In the ODE session's harness, `verify_main` inferred at the session's `main` takes 1.35 s, though its branch is not taken (E-521; open issue 256).
- Six of the thirteen small programs were not run on this head (E-520).

## G-7 Transition

**The claim:** a clean, doable path for the ecosystem, with clear porting guidelines ([the porting guide](../intro/porting.md)). An ambition for the path, not a rule that code needs no rewrite.

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| A package compiled by facts as it is, one line per module: first work | by facts, upstream CSV and DataFrames: 1.75–1.83 s | plain code on the build: 4.45–4.46 s | — | `next` cf0f039f51; a warm-up and 2 processes; load 2.6–3.1 | E-511 |
| The forks' first work | with traits: 0.19 s | upstream, plain code on the build: 4.45–4.46 s | — | `next` cf0f039f51; a warm-up and 2 processes | E-511 |
| The forks' REPL session | with traits: 2.61–2.62 s | upstream: 14.1–14.4 s on the build, 13.5–13.6 s on vanilla | pandas: 0.69–0.75 s | traits: `unified` 8fccf1e182 (E-390); upstream: `unified` 21c9b33e39 (E-386) | E-390, E-386, E-289 |
| The ports' suites and results | with traits: the library 118 testsets, the ODE port 35, TraitMakie 8, TraitTables 3, TraitCSV 2, NetworkDynamics' six files with their two known failures, upstream Tables' suite on the forks with one error, `ByRow(Dict)` ([open issue 240](../open-issues.md#2-design)) (E-523). Upstream CSV's suite on the forks passes and DataFrames' has 4 errors (open issue 157 (a)) on `unified` 86deee2f98 (E-373) | the forks' digests equal upstream's at 26 steps (E-523) | — | `next` cf0f039f51 (E-523); `unified` 86deee2f98 (E-373) | E-523, E-373 |
| Annotations a port writes to choose how its code compiles | with traits: casts, module options, wrappers and `@default_dynamic` together: TraitTables 5, TraitCSV 1, TraitReport 0, TraitMakie 1, the forks 6, the ODE port 30, NetworkDynamics 1. Boxes written: TraitMakie 29, the forks 4, the ODE port 85. `unwrap`: the forks 10, the ODE port 18. `@implement Callable`: the ODE port 19, NetworkDynamics 1. `@nospecializeinfer`: TraitMakie 12, the ODE port 7, NetworkDynamics 3 | — (a count) | — | git at the freeze `round-2026-11-c` | E-522 |
| Methods that extend a function internal to a module declaring `facts` | by facts, with the default for trait modules: 0 in the forks' session, 0 in upstream's by facts, the ODE port's 4 | without that default, 86 in upstream's by facts (CSV, DataFrames, StructArrays → Tables) | — | `next-s3` e967266d9e | E-431 |
| Owner-only functions in the ports | with traits: run-time sites at an owner-only function, the forks 134 of 8,128, the trait demonstrators 0 of 136, the ODE packages 26 of 407; TraitMakie's eleven asserted barriers removed, its suite passes | — | — | `next-s3` e483299622 | E-458 |
| Typing the ODE port's front end | with traits: the session 1.25 → 1.33 s (6 %); the build's errors 122 to 50, none in the front end | — | — | `unified` 21c9b33e39; a warm-up and 3 runs | E-387 |

**Not shown.**
- A second port by another author: every port is the project's own.
- After unrelated loads the forks are behind the package compiled by facts as it is: 2.19–2.34 s against 1.45–1.46 s (E-511; GT-8).
- That a port needs few annotations: not shown. The ODE port writes 30 annotations that choose how its code compiles, 85 boxes and 19 declarations of `Callable` (E-522).
- Not run on this head: the forks' CSV and DataFrames suites, TraitReport's check and session, the sessions of TraitMakie and the ODE port (E-523).
- The ports' own questions are open: [the open issues, the ports](../open-issues.md#the-ports), and open issues 157 and 184.
- Upstream wrapped whole as trait modules, and the forks against upstream under the test bed: measured only on the library of October 2026 (E-212 in the ledger); not measured on this implementation.

## G-8 Simplicity

**The claim:** traits are abstract types: one mechanism, easy to teach. A membership behaves as a method does ([compiler §5.5](../reference/compiler.md#55-a-membership-invalidates-as-a-method-does), [§5.6](../reference/compiler.md#56-the-memberships-method-and-the-edges)).

| What is measured | With traits, or by facts | Plain Julia | Python | Build | Experiment |
|---|---|---|---|---|---|
| A membership built as a method | with traits: a declaration 30 to 40 µs; loads: TraitTables 0.104 s, the ODE port 1.00 s; a membership with 2,000 negatives folded elsewhere 293 µs; sessions hold 0 to 6 folded negatives | — | — | `unified` b66cdc66f2; one run each | E-367 |
| The piracy rules for a membership and for a method | with traits: they agree on 125 of 126 | — | — | `unified` b66cdc66f2 | E-367 |
| A membership reaches every caller as a method does | with traits: Julia's answer in every case (an abstract type against a trait, an image's code, a call cached before the membership, a caller at `Any`); the library's load invalidates no code instance | — | — | `unified` a19d937eaa; one run each | E-365 |
| A membership taken back as a method is deleted | with traits: 27 of 27 checks | — | — | `next-s3` 213c759370 | E-459 |
| A membership adds no type equality inside an invariant parameter | with traits: 33 of 33 checks, every reader agreeing | — | — | `next-s3` e967266d9e | E-456 |
| `Callable` as a contract at the box | with traits: no pair of methods needs dispatch by a function's signature; the gate 25 of 25 | — | — | `next` eaa19da272 | E-500 |

**Not shown.**
- Teaching: nothing measures "easy to teach".

<a id="4c-the-unifications-trade-offs-measured-on-todays-build"></a>
<a id="each-tensions-cost-on-the-rounds-second-freeze-w-145-part-8"></a>

## What each tension costs

Each tension that stands, with its entry in [the open issues §2](../open-issues.md#2-tensions-between-the-goals) and its axes in [the goals §3](../goals.md#3-tensions-between-the-goals).

| Tension | The rule | What it costs | Build | Experiment |
|---|---|---|---|---|
| GT-2 | A member's check is its instances, validated with an image; under strict mode the implementation infers an image's memberships again at its load (traits T-129) | TraitTables with TraitCSV load in 215.2–216.4 ms under strict mode, 153.0–153.7 ms without (+40 %) | `next` cf0f039f51; a warm-up and 3 runs | E-516 |
| GT-3 | The compiler and Base are compiled plainly ([facts §13.1](../reference/facts.md#131-the-product-setting)) | upstream's load logs 132 instances of the compiler, 122 on vanilla (E-516); the ODE port's load 489 (E-516); upstream's session 14.1–14.4 s against 13.5–13.6 s on vanilla (E-386); inference on plain code 3.12 s against 2.08 s (E-389) | `next` cf0f039f51 (E-516); `unified` 21c9b33e39 (E-386); `unified` 9c6c9270f3 (E-389) | E-516, E-386, E-389 |
| GT-5 | A closed type's contract promises no result | through the eraser `IOContext{IO}` against the stream's type known: `write(io, ::Char)` 4.99×, `print "ab"` 2.63×, `show` of a vector 1.09× | `unified` 18bbbf0841 | E-340 |
| GT-7 | A split's branch calls its candidate through a pointer, made per member in each session ([compiler §7.2](../reference/compiler.md#72-the-split)) | a box of the sixth member 9.14 ns, of the first 5.56 ns; 18 ms a session for the pointers of a member's two operations | `next` 5b1900641f (E-443); `unified` 86deee2f98 (E-375) | E-443, E-375 |
| GT-8 | G2 covers the deep class; facts code above a plain callee outside it is lost ([compiler §3.2](../reference/compiler.md#32-g2-as-a-predicate)) | in the class: the forks' own facts instances 63.1 %, upstream's by facts 79.0 % (E-478). The forks lose 150 of 5,705 own image instances to nine loads; their work after the loads 2.19–2.34 s against 0.19 s first (E-511). The library's own hooks: 15 instances ended at a port's load (E-516; open issue 254) | `next-s3` bc844be7c0 (E-478); `next` cf0f039f51 (E-511, E-516) | E-478, E-511, E-516 |
| GT-9 | The membership machinery is consulted for every type | plain code's repeated work 0.18–0.19 ms against vanilla's 0.18 ms; first work 3.316–3.342 s against 3.252–3.281 s (E-515); a non-member's `<:` 1.7–1.8× an unrelated pair's on vanilla (E-270) | `next` cf0f039f51 (E-515); `unified` fd800b27b9 (E-270) | E-515, E-270 |
| GT-12 | The definition-time check runs at each edit ([traits §5.10](../reference/traits.md#510-checks)) | an edit of TraitTables' `summarize` defined in 0.235 s the first time, 9.3 ms the second; the plain twin 70.5 ms and 6.7 ms (E-512). With the library alone: 4.5–4.6 ms to define (E-440) | `next` cf0f039f51 (E-512); `next` 75a7f1795b (E-440) | E-512, E-440; the check itself 0.17 ms median, 0.54 ms mean per method over the demonstrators' 142 methods at a trait, and 1.8 to 2.3 times that for a verdict no optimization decides (E-529, `next` d8f65ef1ea, TraitWorld f0a8c3e; a count, the second of two passes) |
| GT-14 | A membership is seen from the world of its declaration | a function that declares a member and stores a value of it raises `MethodError` ("may be too new"); the plain twin runs | `unified` dd3f6d839b | E-362 |
| GT-16 | Fully typed mode's check runs only where the session's inference found a run-time site; the exact question is `fully_typed`'s, the build's own check ([compiler §2.7](../reference/compiler.md#27-fully-typed-mode)) | not measured; the session's check and the build agree on 17 of 18 programs | `unified` 21c9b33e39 | E-384 |
| GT-21 | Calls that only throw keep a port's code out of the deep class | the forks' own image instances in the class: 1,983 of 4,799; 1,986 with such calls left to run time from facts code only; 2,917 (61 %) from every caller, plain code included | `next` at 7b374f39ce | E-416 |
| GT-32 | A callable struct that is no `Function` is no member of `Callable` until its owner declares it | 134 of 174 callable types in the forks' session, 35 of 67 in the demonstrators'; the ODE port needed 14 declarations, its tests 5. At the freeze the ODE port writes 19 `@implement Callable`, NetworkDynamics 1 (E-522) | `next` eaa19da272 (E-500); git at `round-2026-11-c` (E-522) | E-500, E-522 |
| GT-33 | A declared result read at a trait is checked where it is passed on ([compiler §7.1](../reference/compiler.md#71-the-rule)) | instances that carry the mark: the report's session 56, the table's 13, the ODE program with callbacks 62; statements that take a result as its type alone 50, 11, 49; checks after a call that passes a result on: the report 20, the table 2. The sessions' compiles: 24 and 19. No time measured | `next` 85bd884a57, TraitWorld `unified` 15070de; a count | E-530 |

## Where a session's time goes

Each step profiled at 0.5 ms in one process after a warm-up; the shares applied to an unprofiled run's times. Every sample goes to one class by its stack.

| Step | Time | Where it goes | Build | Experiment |
|---|---|---|---|---|
| `using TraitCSV, TraitTables, TraitMakie` | 0.38 s | the images' restore 36 %, their validation 36 %, file system calls 14 %, the methods' activation 9 %, the memberships' 2 %, the walk 1 % | `unified` 21c9b33e39 | E-388 |
| `using TraitDifferentialEquations` | 0.33 s | validation 31 %, restore 30 %, file system calls 18 %, the methods' activation 13 %, the memberships' 6 % | `unified` 21c9b33e39 | E-388 |
| The forks' CSV and DataFrames loaded | 1.02 s | validation 45 %, restore 25 %, file system calls 10 %, the methods' activation 8 % | `unified` 21c9b33e39 | E-388 |
| The first solve (Lorenz, Tsit5) | 0.18 s | code generation 57 %, inference 28 %, code compiled while inferring 13 % | `unified` 21c9b33e39 | E-388 |
| The first stiff solve (Robertson, Rodas5) | 0.14 s | code generation 37 %, code compiled while inferring 35 %, inference 26 % | `unified` 21c9b33e39 | E-388 |
| Upstream's eight steps, plain code on the build | 10.3 s | code generation 6.23 s, inference 3.57 s, code compiled while inferring 0.49 s | `unified` 21c9b33e39 | E-388 |
| The same on vanilla | 10.2 s | code generation 7.56 s, inference 2.08 s, code compiled while inferring 0.46 s | vanilla v1.13.2 | E-388 |
| NetworkDynamics' workload | 44.0 s | code generation 58 %, inference 26 %, code compiled while inferring 6 %, the work 4 %, the loads 6 % | `unified` 21c9b33e39 | E-388 |

- A session's time is the images' validation and restore at a load, and code generation and inference after it.
- The membership walk, the member check and the memberships' activation are below a tenth of every step.
- With no instance of the compiler compiled twice, inference on upstream's eight steps takes 3.12 s against vanilla's 2.08 s (E-389; GT-3).

<a id="5-not-shown"></a>

## Not shown

What no experiment shows. Each goal's own list is under its table.

- **Scale.** Composition is measured with twenty small packages (E-378). The ports are parts of three ecosystems, not the ecosystems.
- **A second port by another author.** Every port is the project's own.
- **Teaching.** Whether `intro/` teaches the design is not tested.
- **A cache across sessions.** Not built. By E-375 and E-521 it would serve:
  - the session's own code and Julia's methods at its signatures, which plain Julia compiles too: about 155 ms of the generated workload (E-375); 549 of the ODE session's 871 ms of compiling and 164 of the table session's 169 ms (E-521);
  - a library's code at another package's type, where the membership is declared in the session and compiled for the type: 152 ms;
  - a membership declared in the session: 139 to 144 ms;
  - the pointers of code compiled once: 18 ms (GT-7).
- **Better steady-state speed.** Not claimed (G-2).
- **Threads.** Calls on other threads while definitions are made, and code compiled by facts under `ThreadedExecution`: measured only on the library of October 2026 (E-63, E-152 in the ledger); not measured on this implementation.
- **Edits by Revise** (lowering L-64), and strict mode under the test bed `all`: untested.
