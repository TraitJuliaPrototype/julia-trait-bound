# Review: the session cache note and the port note (W-58, phases 4 and 5)

Reviewer: fresh eyes, files read only, nothing run (2026-10-27). Sources:
- `writeup/plans/2026-10-27-session-cache.md` and `writeup/plans/2026-10-27-port-architecture-ttfx.md` as committed at 39cdba3;
- the plan they serve, `writeup/plans/2026-10-27-ttfx-sciml-makie.md`;
- `experiments/ttfx/` at 92246d1: README, `workload.jl`, `plotting.jl`, `cache/make_cache.sh`, the traces `cache/SessionCache{D,S,Sn}/src/trace.jl`;
- julia-1.13 at 252edca933; TraitWorld 04095fe;
- SciML and Makie in `ndport/pkgs/` (SciMLBase 3.58.0, OrdinaryDiffEqCore 4.19.0, DiffEqBase 7.21.4, Makie 0.24.16: the versions in `experiments/ttfx/env_up/Manifest.toml`).

Judged against the user's goal and direction (the plan §1), and against "Remember to design experiments that give feedback quickly. Nothing that runs for hours."

## Verdict

- **The cache's direction is right:** keep code compiled in a session, keyed on library types, and validate it at load. It is the user's lever, and E-174 shows its size.
- **The measurement behind both notes is partly an artefact (B1).** `--trace-compile` records only compile roots of the default owner. A root whose signature names `Main` takes all its callees with it, even callees keyed on library types. So:
  - E-172's "none of stock SciML's solver can be kept" is not shown;
  - stock's `AutoSpecialize` already erases the function below `get_concrete_problem`;
  - the same method records almost nothing in setting C, and nothing that the facts owner compiles.
- **The cache note's rule contradicts the port note's expectations (B2).** The rule keeps only facts code. The gains the port note expects (the plot step 1.56 → 0.48 s; E-174's 4.7 s session) come from plain code.
- **The cache design misses mechanics that decide whether it works.** Each is concrete and checkable in minutes:
  - what a package image records as its dependencies (M2);
  - extensions (M3);
  - its own load cost, already measured (M4);
  - TraitWorld's per-session checks (M5);
  - strict mode becoming dependent on history (M1);
  - concurrency (M8).
- **The port's order does not follow the goal (M6).** After E-174 the load is 3.7 s of 4.7 s, and the plan itself says "the load … comes next, before more design". The port defers the load. Its first moves buy first use, which a correct cache may already give stock SciML.
- **Fix before building:** B1 first (a CI-level emulation, minutes), then B2 and M2–M5. Re-decide the port's order after B1's re-run and E-170.

---

## Findings

### B1. The emulation cannot see what the design keeps; E-172's S result is an artefact (blocking)

**Evidence**
- `julia-1.13/src/gf.c:3942-3943`: `record_precompile_statement` runs only when `did_compile && codeinst->owner == jl_nothing`. A compile under owner `:facts` is never traced.
- Only roots are traced. Callees inferred inside a root's compilation get no statement of their own.
- `experiments/ttfx/cache/SessionCacheS/src/trace.jl` (stock, perturbed) has no statement for `solve_up`, `solve_call`, `__solve` or `_ode_init`. The whole solver hangs under `kwcall(solve, …, ODEProblem{…, ODEFunction{true, AutoSpecialize, typeof(Main.lorenz!), …}})`. `make_cache.sh` drops that root because it names `Main`.
- The same trace shows that the solution handed to `Main.plot_two` holds `ODEFunction{true, AutoSpecialize, FunctionWrappersWrappers.FunctionWrappersWrapper{…}}`, with no `Main` type. Below the entry, stock SciML's integrator and solution are keyed on library types. The erasure happens here:
  - `DiffEqBase/src/solve.jl:757-779`: `get_concrete_problem` calls `_promote_f`, then `_remake_with_promoted_function`;
  - `solve.jl:1011-1060`: `promote_f` wraps the function.
- In contrast, `SessionCacheSn/src/trace.jl` keeps `solve_call` and `initialize!`: its root no longer names `Main`. So E-174 shows that removing `Main` from the root makes the cache work. It does not show that the code below the root was keyed on `Main`.
- In setting C, SciML's methods are facts methods: their default owner is `:facts` (`jl_default_owner`, `gf.c:424`). The trace records almost none of SciML there. The same holds for Makie once it is wrapped by facts.
- D's "0.18 s of compiling stays in its first solve (not diagnosed)" (E-172) fits this: run-time-site targets compiled under `:facts` were never in D's cache.

**Consequences**
- The cache note §2, "none of the solver's 7.5 s could be kept", and the plan's phase-3a reading are not supported.
- The port note's premise that move 1 comes first for first use (§2.1, §3) rests on that reading.
- Phase 6 step 1 ("C with the cache") cannot be measured with `make_cache.sh`.

**Fix**
- Emulate at the level of CodeInstances, not roots. At the end of the traced session:
  - walk the CodeInstances created in the session, both owners;
  - keep those whose signature, and whose edges and constants, name no module defined in the session;
  - compile them in the cache package's build with the owner made explicit (`Compiler.typeinf_ext_toplevel(mi, world, source_mode, trim_mode, owner)`, compiler §2.4).
- Re-run E-172 for S with `AutoSpecialize` (no `NoSpecialize`), D and Dp. Minutes per setting.
- Until then, mark the S claim in E-172's registry row, in open issue 72's evidence and in the cache note §2 as an artefact of the trace (CLAUDE.md, rule 2: stale copies).

### B2. "Only facts code is kept" contradicts the gains the port expects (blocking for phase 6's order)

**Evidence**
- Cache note line 28: "Plain code compiled in the session is not kept."
- Port note §4, line 48: the cache "cut the first plot from 1.56 to 0.48 s for plain code". §3, line 32: "Expected: E-174's numbers". Both gains are plain code: stock S.
- Setting C uses Makie plain ("Makie from the port's clones", plan §4). Under the note's rule, phase 6 step 1 keeps none of the plot step, and its first plot stays at about 1.5 s.
- The premise is too strong. Julia validates a package image's plain code against its edges at load (`insert_backedges` → `verify_method_graph`, E-169), so keeping plain code does not put G1 at stake. What plain code lacks is G2: later loads may invalidate it. E-168 puts a size on that: S/b loses 0.44 s after CairoMakie's load.
- The combination caches lost Makie's code because of how they were built: replay in a fixed order (alternatives, "Caches across sessions"). That loss was not unsound validation.

**Fix**
- Keep plain code too, as best effort and validated by Julia at load. State that only facts code has G2.
- Measure plain code's survival in order B (M9, experiment 4) before deciding to drop it.
- Then Makie's wrapping by facts is a choice about order B (at most 0.44 s on this workload), not a precondition for any plot-step gain.

### M1. Strict mode becomes dependent on history (major)

**Scenario**
- Session 1 compiles trait code with a fact at `s`. The cache keeps it.
- Session 2 loads a package P that defines a non-stakeholder method winning at `s`.
- Without the cache, P's method is defined before the code is compiled and is followed (facts §10.1). With the cache, strict mode refuses P:
  - at P's definition, if the cache loaded first (facts §10.2);
  - at the cache image's validation, if P loaded first (the intended design, facts §10.3, first row).
- So whether an environment "loads without a `PirateError`" (the strict tier, facts §2.3) depends on what earlier sessions compiled. Today it is a function of the environment and its images.

**Fix**
- Cached code is evidence, not a contract. When a pirate wins only at facts of cached code (not of an image or of code compiled in this session), discard that code and follow the pirate.
- State this in the note, and in facts §10.3 when the cache is adopted.

### M2. A package image records every module loaded while it was built (major)

**Evidence**
- `julia-1.13/src/staticdata.c:3400`: `mod_array = jl_get_loaded_modules()`, "__toplevel__ modules loaded in this session". The image requires each of them at its exact build id.

**Consequences**
- If TraitWorld's package callback loads a cache partition inside another package's precompilation, that package's image depends on the cache. Every rebuild of the cache then makes the user's own packages stale, and they precompile again.
- The builder of a partition loads the previous cache version through the same callback. The new image then depends on its own predecessor.
- A partition depends on everything its build process loaded, not on "the packages whose types its code names" (note line 33). This is the root cause of E-173's untested order-independence check: the plotting library was loaded.

**Fix**
- Never load the cache when `jl_generating_output()` is set.
- Build each partition in a process that loads exactly its dependency set, and check the image's module list after the build.

### M3. Partitions keyed by signature types miss extensions (major)

**Evidence**
- `DiffEqBase/ext/DiffEqBaseForwardDiffExt.jl:227` defines `hasdualpromote(u0, t::Number)`. Every solve calls it in `promote_f` (`DiffEqBase/src/solve.jl:1031`, `:1052`).
- The extension loads with ForwardDiff, which Rosenbrock brings and Tsit5 alone does not. With the extension loaded, the Tsit5 path wraps the function. Without it, it does not: a different promoted problem type, so different keys.
- `SciMLBase/Project.toml`: `SciMLBaseMakieExt = ["Makie", "GeometryBasics"]`.

**Scenario**
- A partition whose signatures name only SciML types loads at `using OrdinaryDiffEqTsit5`.
- Its facts select the extension's methods, so it fails validation and is discarded.
- The session compiles the code again. Then `using OrdinaryDiffEqRosenbrock` loads the extension, a stakeholder's change (facts §2.2), which invalidates the new code once more.

**Fix**
- Key a partition by the owners of every method its edges select, extensions included, not by its signatures' types.
- A partition is then an exact counterpart of Julia's extension trigger sets. Consider building partitions as extensions of a generated cache package, so that Julia's own trigger logic loads them in any order.

### M4. The cache's own load cost is measured, and ignored (major)

**Evidence**
- E-173: D's cache of 52 statements adds 0.15 s to the load (0.61 against 0.44–0.46 s). The matched session gets slower with the cache: 1.02 s against 0.94–0.99 s.
- E-174: S/n's load rises from 3.55–3.57 to 3.66–3.67 s.
- E-169: method insertion and edge validation are about two thirds of S's load. A cache image adds external CodeInstances whose edges must be validated.
- The plan's own decision after E-174: "The load becomes the main question."
- The note's §5 asks the cost as an open question. Its "cap with least-recent eviction, by signature" (line 48) needs hit counts that Julia does not record for loaded code.

**Fix**
- A load-only experiment against cache size (M9, experiment 3).
- A load budget for the cache, within the plan §3's 1.2 s.
- Eviction by generations: drop signatures not recorded again in the last k sessions, which needs no hit counts.

### M5. Cached workers pay TraitWorld's first-call check in every session (major)

**Evidence**
- `TraitWorld/src/checks.jl:294-305`: each worker signature's check flag is a `Ref(false)` embedded in its compiled code, set by its first call. The check runs through `invokelatest` and reflects the worker again.
- Images carry the result only as `__tw_checked__`, written "while an image is built", and read per package (`ahead.jl:24-58`; lowering §14, §15.1).
- A replayed `precompile(…)` makes no call. So every cached worker runs `_check_once` at its first call in every session.

**Fix**
- The builder runs each cached worker's check and writes `__tw_checked__` into the cache package, and TraitWorld reads it there.
- For the later session image: state whether a flag saved as `true` may be trusted.
- Count the `_check_once` calls in a D/c session (minutes).

### M6. The port's order does not serve the goal's largest term (major)

**Evidence**
- E-174: the load is 3.66 of 4.69 s; after the load, 1.03 s against Python's 1.00 s.
- The plan, phase 3a decision: "phase 2's load profile of S and C comes next, before more design." The port note line 22 makes the load "not the port's" question. Its steps 1–2 for Makie and moves 1, 1b and 5 for SciML all target first use. Only PlotCore (step 3, "the large one") touches the load.
- What move 1 buys once B1's cache exists: stock's per-function layers above `get_concrete_problem`. E-168 bounds them: S's matched second model takes 0.16–0.19 s.
- Makie step 1 (wrapping by facts) likely adds load. Compiling SciML by facts added 1.0 s (C against U); CairoMakie loads in 4.9 s under `all` against 1.9 s (evidence §3, not diagnosed). It buys order independence, at most 0.44 s here (S/b).
- Makie step 2 (the typed front) buys nothing on this workload. The plot path already sees only `Vector{Float64}`, `typeof(log10)` and Makie's own types (`experiments/ttfx/plotting.jl`).

**Fix: reorder phase 6**
1. B1's re-run.
2. E-170, the system-image ceiling, built alone.
3. A per-image attribution of S's and C's load: which images carry the insertions and validations.
4. A quick measure of Makie's load when wrapped by facts (one `using`, no workload).
5. Then the SciML moves, justified by the keys of M7 and by the guarantees, not by E-172.

### M7. What stays keyed on the user's types after moves 1, 1b and 5 (major)

On the workload: only the entries (`ODEProblem(f, …)`, `ODEFunction{iip}(f)` with its `isinplace` reflection) and `Main`'s own `plot_two` and `digest`. Beyond it, on upstream's features, which phase 6 claims:
- **The parameters, `P`.**
  - `ODEProblem{…, P, …}` (`SciMLBase/src/problems/ode_problems.jl:114`, `:139-145`) and `ODEIntegrator{…, pType, …}` (`OrdinaryDiffEqCore/src/integrators/type.jl:155-170`).
  - A user's own parameter struct puts a `Main` type in every solver layer.
  - Move 1b keeps `P` as a key (port note line 39). TDE pays the same (+1.35 s, D/p in E-168).
  - Erasing `P` at the solver while keeping the call static means erasing at a wider signature, which the design refuses (lowering §12, T-54). Open an issue rather than leave it implicit.
  - Erasing `P` also reaches `promote_u0`'s dual detection in `p` (`DiffEqBase/src/solve.jl:755`).
- **Callbacks, and `DEOptions`' function fields** (`F1`–`F7`, `OrdinaryDiffEqCore/src/integrators/type.jl:30-34`). A user's closure (`isoutofdomain`, a `ContinuousCallback`'s condition) keys the integrator on `Main`. That is move 2, outside the workload, but not outside "upstream's features".
- **`saveat`'s type is stored in `DEOptions`** (`OrdinaryDiffEqCore/src/solve.jl:759`, `:772`). Move 1b covers it. Note that `_ode_init` (`solve.jl:270-840`, about 50 keywords, `@constprop :aggressive`) is the body to split, not just `solve`.
- **Rosenbrock's dual signature** is a family over the chunk size `N`, the state's length. The tag is a library type, `ForwardDiff.Tag(OrdinaryDiffEqTag(), eltype(u0))` (`OrdinaryDiffEqDifferentiation/src/alg_utils.jl:98`). Move 1's "second bounded parameter per signature" is a bound with an open parameter, which waits for the first call (lowering §14, L-10).
- **Makie's compute graph is keyed on the attributes' value types** (`TypedEdge{InputTuple, OutputTuple, F}`, `Makie.jl/ComputePipeline/src/ComputePipeline.jl:70-76`, `:113-162`). A user's type in data or attributes (a formatter closure, a unit) keys it on `Main`. This is where the typed front (step 2) pays, for users beyond the workload.

**Fix:** list these in the port note §2 as the keys a cache cannot keep, each with the move that removes it or "stays".

### M8. The builder: concurrency, stale images and churn (major)

**Scenarios**
- Two sessions exit together. Two builders regenerate one partition's source: lost signatures, or a corrupt package.
- A dev'd package is edited, and the next session must precompile it. The niced builder already holds its pidfile lock, so the foreground session waits for a nice-19 process.
- A stale cache image: with Julia's default `--compiled-modules=yes`, `require` precompiles it inside the session.
- A pirate in `startup.jl`, or in a package loaded before the partition, breaks a cached fact in every session. The code is then discarded at load, compiled again, recorded at exit and rebuilt, in every session.
- The machine's rule is one Julia job at a time. A builder at exit overlaps the next session by design. In the agents' sandbox a detached job dies with its command (memory note "No detached jobs from the sandbox").

**Fix**
- A lock and an append-only log of signatures per partition.
- The builder never precompiles dependencies; it skips partitions whose dependencies are stale.
- A session never compiles the cache; it loads it only if the image is valid.
- Signatures discarded at load are recorded and not added again for that environment.
- In the prototype, the build is a foreground step of the experiment.

### M9. The experiments are minutes long; the decisive quick ones are missing (major)

The cache note's checks (§4) are minutes long, but check 1 could not run, and neither check tests the mechanics above. Missing, each minutes, one Julia job at a time:
1. **The CI-level emulation** of B1 for S (`AutoSpecialize`), D and Dp. It decides whether move 1 is on the critical path at all.
2. **An owner-aware record for C:** the same walk, keeping `:facts` CodeInstances. Without it, phase 6 step 1 cannot be measured.
3. **Load against cache size:** partitions of 0, 50, 200 and 800 statements, `using` only, with the external CodeInstances and edges counted. It sizes M4.
4. **The split by dependency set:** two partitions (solver, plotting) built in processes that load only their dependencies (M2), then order B in S and D. For S, also count the plain CodeInstances of the cache that CairoMakie's load invalidates. That decides B2.
5. **Strict mode with a cache:** a synthetic pirate, a cache and both orders. It shows M1's error.
6. **A precompile process with the callback loading the cache:** check the image's module list (M2).
7. **`_check_once` calls in a D/c session** (M5).

E-170's system image is a single full build, run alone; it is not hours. Run it before phase 6.

### m1. "Names only types of packages" must cover the whole CodeInstance (minor; G1 for the session image)

- Code with a library-only signature can still hold session content:
  - `isa Main.T` branches, when a `Main` implementation was among a split's first four candidates (compiler §4.2);
  - `FoldRecord`s with `Main` arguments (compiler §4.4);
  - constants;
  - edges to `Main` methods (a pirate inlined).
- Replay in a builder removes these. The "later" session image (note line 42) would serialize them, so its rule must cover the signature, the IR, the edges and the fold records.
- Folds whose answer is registered lazily in a session (D's trace has `TraitWorld._member_fold` at `AtLoad`) may fail at the cache's validation, and their code is dropped silently. Count them in experiment 4.

### m2. The environment key misses preferences, stacked environments and dev'd edits (minor)

- SciMLBase reads `SpecializationLevel` from Preferences (`SciMLBase/src/scimlfunctions.jl:257`), which changes the keys without changing the manifest.
- Packages from a stacked environment (`@v1.13`: Revise, tools) are outside the manifest.
- Dev'd packages do have images; their versions stay the same across edits.
- If the key relies on the images' module lists (M2), every `Pkg.update` resets the partitions. Say so: the cache "builds up" between updates.
- Note line 61: "a package without an image (dev'd, not precompiled)" is not the usual case.

### m3. "Depends only on its stakeholders' methods" is too strong (minor)

Cache note line 19, and the port note line 50. Besides stakeholders' methods, facts code depends on:
- winning pirates;
- plain code it names (`return_type` answers under `:facts_plain_return_type`, the compiler's code: facts §6.4);
- bindings;
- a stakeholder's extension activated by another package (facts §2.2, G2's exceptions; M3).

### m4. Move 5 contradicts the exploration and the trace (minor)

- Port note line 41: move 5 is "needed for the plot step's share of the cache".
- `explorations/sciml-as-traits.md` §4, move 5: "not needed for the workload after move 1".
- In stock, the solution already carries no `Main` type (B1's evidence). Drop the claim, or justify move 5 by another workload.

### m5. Baselines (minor)

- Port note line 16 compares 0.30 s with 8.2 s. 8.2 s is S/n without a cache, slower than stock's own 5.3 s (S/p). Compare with 5.3 s.
- Port note §6, second question: the `NoSpecialize` branch shows SciML already runs with `F = Any` (`SciMLBase/src/scimlfunctions.jl:3215-3229`; `unwrapped_f`, `:3284-3297`). Code that reads `f.f` works with an untyped function, and a bounded `F` has that precedent.

### m6. Adoption: references and record (minor)

- The cache note does not name the reference sections it would change:
  - design §4 ("compiled once, not once per session", quoted in open issue 72);
  - facts §11 (images, and the cache as one);
  - lowering §16 (the callback that loads it; `__tw_checked__`);
  - facts §10.3 (M1).
- E-173's check 1 needs a registry row of its own when re-run with partitions; experiments 1–7 need rows before they run (CLAUDE.md).
- After B1's re-run, correct the S claim's copies: E-172's registry row, open issue 72's evidence, the plan's phase-3a outcome, the cache note §2 and the port note §2.1.

---

## Answers to the questions, in brief

1. **Soundness.**
   - G1 holds as long as the cache is an ordinary package image validated at load: facts edges, fold records, the image hook.
   - The rule for what is kept must cover the whole CodeInstance for the session image (m1).
   - G2 and order independence fail through extensions (M3) and through partition dependencies (M2).
   - Strict mode becomes dependent on history (M1).
   - TraitWorld's session stamp is harmless for split tables and `Erased` pointers (empty in a new session), but not for first-call checks (M5).
2. **What it misses:** the load cost (M4), the module lists of images (M2), extensions (M3), dev'd packages and preferences (m2), concurrency and churn (M8), and plain code's place (B2).
3. **The port's order:** not right for the goal (M6). Keys that stay on the user's types: M7. The SciML moves' premise needs B1's re-run.
4. **Experiments:** minutes long, but the decisive ones are missing (M9).
5. **Contradictions:**
   - the cache note's rule against the port note's expectations (B2);
   - move 5 against the exploration (m4);
   - the port deferring the load against the plan's decision (M6);
   - "only stakeholders" against facts §2.2 (m3).
