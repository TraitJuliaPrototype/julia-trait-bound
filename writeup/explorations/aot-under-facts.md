# AOT under wrapping by facts

Exploration of 2026-10-17 (session 25), for the user's question: how the easy-AOT goal plays with wrapping by facts.

## Short answer

1. **A build compiles plain Julia.**
   - A `--trim` build does not use the facts policy. Entries generate the plain call, and native inference runs in the closed world (`_closed_build()` in TraitWorld).
   - That is correct by definition: in the closed world native inference *is* plain Julia (G1), and nothing loads in a binary, so G2 has nothing to protect.
   - It is also the better choice for trimming. Native inference may use abstract facts ("the methods matching `S` are these three"), which closes sites the policy would leave dynamic.
   - So no Julia piece is needed for trimming a foreign owner's code.
2. **What the trait world gives AOT is unchanged in kind.**
   - Dispatch over runtime types goes through conformances, whose targets `verify_main` enumerates: `Dynamic{X}` values, `Callable` targets, entries.
   - Keys are deeply concrete where their traits require it, so trait-world code has few open sites, and concrete mode reports those at their root cause.
   - `verify_main` says CLOSED or OPEN, and lists each hole with its line.
3. **What wrapping by facts changed is the boundary.**
   - **Under layering,** trait code reached code written without traits only through declared calls (`@call`) and wrapped packages. The roots of the plain parts were explicit and listed.
   - **Now trait code calls Cairo, ForwardDiff or CSV directly.** `verify_main` walks into them and reports their open sites as holes, as plain Julia would hit them.
   - The plain code had to be trimmable before too, since declared calls only named its roots. So nothing is lost in what can be trimmed. What is lost is a declared, listed boundary; the walk finds it instead.
   - **Pay-off 2 therefore reads:** trait-world dispatch is closed by construction. Plain code reached from trait code is as trimmable as in plain Julia, and `verify_main` says where it is not.
4. **Three risks need tests before the next binary** (§3):
   - images built without `--trim` carrying session-mode entry code into a trim build;
   - foreign CodeInstances referenced from image code;
   - values decided by inference differing between session and binary.
5. **The 2.09 MB trimmed executable predates keys and wrapping by facts.** Nothing about AOT under the current design is measured yet. The next step is three binaries (§4).

## 1. Session and build compile different code, deliberately

| | session | `--trim` build |
|---|---|---|
| entries call workers | through `_facts_call`: the worker's CodeInstance under the policy | the plain call |
| abstract call sites | dispatched at run time, in the current world | inferred natively over the closed world's methods; closed if the matches are few |
| G1 | identical to plain Julia in the current world (Theorem 1, up to A3–A5) | plain Julia by definition |
| G2 | concrete facts only (Theorem 2) | nothing loads |
| slow paths (builders, checks) | under the policy, in the caller's world | filled at build by `close_world!`; checks and reflection switched off |

**The binary's baseline is plain juliac, not the session.** Values that inference decides (A3: `return_type`, `promote_op`, element types of empty collections) can differ between them. Wherever the session matched plain Julia, it matched plain Julia's *session* answer; the binary gives plain Julia's *closed-world* answer.

## 2. Why the trait world still makes AOT easier than plain Julia

1. **Runtime-type dispatch is listed.** A `Dynamic{X}` value adds the conformances whose types reach the place it is made. A `Callable` adds one target at its declared signature. Plain Julia has no such list for a generic function called on a value of unknown type.
2. **Trait-world code is mostly closed by itself.** Workers are compiled per key, and keys hold concrete types where the trait requires it. Abstract values come only from traits that do not require concreteness, from the module's own code, or from the code it calls. Concrete mode reports them at their root cause.
3. **The checks run at build.** `verify_main` runs every enumerated worker's build-time checks, and separates holes on normal paths from holes on error paths.

What wrapping by facts adds:
- no `@call` declarations to write;
- no wrapper per package.

What it takes away:
- the declared boundary, as a list of the plain roots. `verify_main`'s report can list the first plain frame of each hole, which gives the same information after the fact. *To do.*

## 3. Risks to test

1. **Images built without `--trim`.**
   - `_closed_build()` is decided when an entry's code is generated, and `--trim` is not among the flags that key package images (`CacheFlags`, `base/loading.jl`).
   - If a trim build reuses a trait package's image, its entries may hold session code: `Core.invoke(f, ci)` of a policy-owned CodeInstance, which trimming does not compile.
   - **Test:** build a trimmed binary from a trait package with an existing image.
   - **Possible fixes:** a compile-time preference that keys images by build mode; `verify_main` refusing policy-owned CodeInstances on the binary's paths; or regenerating entries in the build process.
2. **Foreign CodeInstances in image code.** These are the same edges seen from the other side. `verify_main` should report any policy-owned CodeInstance reached in a closed build as a hole.
3. **Inference-decided values (A3).** A trait package's tests run in sessions, and the binary may type an empty `map` differently. This is the declared exception of "identical or error", but it now separates test and binary. Solvers declare such element types (open-issues 24).
4. **The machinery's slow paths.** `_latest_under_policy` and `invokelatest` are switched off by `close_world!`. A path that reaches them in a binary is a bug, and `verify_main` should find it as a hole.

## 4. What to measure

1. **TraitMakie, CSV-free:** lines and scatter to a PNG through Cairo, called directly. Cairo is mostly `ccall`, so `verify_main` should say CLOSED. Size and time against the old 2.09 MB program and against plain juliac on the same code without traits.
2. **TraitDifferentialEquations:** Tsit5 and Rodas5 with ForwardDiff's `Dual`. Generic arithmetic over duals, reached directly, is the test of "plain code as trimmable as in plain Julia".
3. **Reading data:** CSV and DataFrames reached from trait code, the hard case. Expect holes. The point is that `verify_main` names them before juliac does.

Each binary is built alone, under a memory guard (the full App build needed about 16.5 GB).

## 5. The pirate refusal mode and AOT

The optional mode in which defining a winning pirate is an error (`strict-mode.md`) acts at method definition.
- In a binary no method is defined at run time, so the mode does nothing there.
- At build, every pirate is defined before the trait code is compiled. Its symmetric check, "no fact of the trait code selects a pirate", becomes a lint over the build's edges.
- The lint attributes each call to the module of the code it was written in, using the debug information of inlined frames.
- It is optional for builds, and useful whether or not sessions run the mode.

## 6. AOT-focused annotations for calls into ordinary code

The user (session 25): "In my mind AOT means no LLVM in the binary. Thus no recompilation. Strict mode trait code has that. For its own code. But now we have made calling ordinary Julia code easy, so we don't get any benefits there it seems. On the one hand that's fair, on the other I wonder whether some additional aot focused annotations when calling ordinary code from trait world would be possible."

**A correction first.** The trait world's own code is closed by conformances and keys, in either mode. Strict mode adds nothing in a binary, since no method is defined at run time. The question is the right one, though: what the trait world can offer at its calls into ordinary code.

**What the facts policy already knows.**
- Under the policy, the code compiled for a call into ordinary code has exactly two kinds of call sites: facts at concrete signatures, and run-time sites (Theorem 3).
- The run-time sites are listable per call, with their argument types and lines. TraitWorld already scans for them (`_has_runtime_sites`, for rule 4).
- Native inference in the closed world is at least as precise, so every site the policy closes is closed in the binary too. The policy's list over-approximates the binary's holes.
- So the trait world can say, for each call into ordinary code and *at the trait package's own build*, whether a binary can run that call without a compiler. Plain Julia cannot say that before an application is trimmed.

**Possible annotations, from weakest to strongest:**

| | what | checked or done | what a binary gets | needs |
|---|---|---|---|---|
| A | none: a report | at the trait package's build, for each call into ordinary code on a normal path: its run-time sites with lines, attributed to the trait call that reaches them | the holes are known per package, not per application | TraitWorld only (`_has_runtime_sites` extended to list sites) |
| B | `@closed f(args...)` | the call's code under the policy has no run-time site on a normal path; otherwise a build error at the trait package, naming the sites | a guarantee by the package author that this call needs no compiler, in every application | TraitWorld only |
| C | `::R` at the call | the call's result is asserted at the boundary (`CSV.read(path, Table)::Table`) | the trait code after the call stays closed, whatever the callee does inside | exists (assertions), to be stated as the pattern |
| D | `@targets` (a list for an open site) | the concrete types that reach a run-time site inside ordinary code, declared by the trait package (`show(::IO, T) for T in (Int, Float64, String)`); `verify_main` registers them as entry points | the open site becomes closed for the listed types; an unlisted type is a named error instead of a crash | TraitWorld; a checked error at a missing target needs a small runtime hook |
| E | `@interpreted f(args...)` | the call's closure keeps its IR, and runs in Julia's interpreter in the binary | no LLVM and no recompilation, slow but complete: for cold paths (configuration, parsing a header, error messages) | Julia: an interpreter fallback in trimmed binaries for methods whose IR is kept (**piece 16**, new); size grows with the closure |

**What remains fair to say.**
- Ordinary code that decides types at run time is open by nature: CSV choosing column types from the data, or Makie's attribute system.
- The honest choices there are:
  - enumerate (D);
  - interpret (E);
  - keep LLVM in the binary;
  - or move the decision into the trait world, where conformances list it, as TraitMakie does for plots.
- A and B are cheap, and they turn "the binary dies at a generic call" into a report or an error at the trait package's build. That is the same direction as G4.

**Recommendation.**
1. Prototype A and B with the first trimmed binaries (§4), and compare the policy's list with what the trim verifier finds.
2. State C as the boundary pattern in the notes.
3. Leave D and E as proposals until the CSV/DataFrames binary shows how many open sites real ordinary code has on its normal paths.
