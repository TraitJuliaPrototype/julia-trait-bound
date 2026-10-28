# The store of the facts-keyed cache, and its vehicle (W-66, step 4)

Status: **proposal, revision 2** (2026-10-28, mine; W-66). Not normative. Revision 1 was reviewed by [a fresh-eye review](../reviews/2026-10-28-facts-cache-store.md) (B1–B3 blocking, M1–M6, m1–m8). Revision 2 takes every finding (§8) and the user's answer to open issue 80 (2026-10-28, "Accept both suggestions."): a stored entry is valid by Julia's validation of its edges, with fingerprints for content only ([decisions](../record/decisions.md) §5; [facts §11](../reference/facts.md#11-package-images)). No Julia change before E-a and E-0 (§6). E-a is done (E-205): a ceiling of 1.5 s in C and 0.02 s in D, with code generation, which this store leaves in the session, twice inference; the vehicle is [open issue 95](../open-issues.md#1-decisions-waiting-for-the-user).

## 1. What is settled

- **An entry** is a CodeInstance of owner `:facts`: its optimized IR and its result. It names no type or function of the session (a closure of `Main`, a type defined at the prompt).
- **Validity** (the user, 2026-10-28; review M1): the entry's edges go through Julia's own validation of loaded code, `verify_method_graph` (`Compiler/src/reinfer.jl`), in the session's latest world:
  - dispatch at every edge exact, by the methods that match now against the recorded ones;
  - `invoke` signatures, deleted methods, bindings' partitions, folds (`FoldRecord`s, evaluated at load, compiler §4.4);
  - a recursive group passes or fails as one (Tarjan's components);
  - world ranges from the validation, never from the record; insertion and backedges by Julia (`jl_mi_cache_insert`, `store_backedges`, `jl_promote_ci_to_current`).
- **Content** (the fingerprints, E-195's F1 and F3, narrowed): what the edges do not cover.
  - F1 of the entry's method, of each method its edges name, and of each method inlined into it (from its debug info);
  - F3, the layouts of the types it reads;
  - **the values it embeds** (review B2): every constant binding its code reads, with a hash of its value. A value with identity is relinked through its binding, or the entry is not stored;
  - **the flags** that change optimized IR (Julia's `CacheFlags`: check-bounds, inline, optimization level, debug level) and the module options inference reads (review m1).
- **Not stored** (review M4, m3, m4):
  - an entry with an edge to code of another owner (`return_type`'s plain answers, plain compiler code, an `:invoke` of plain code). E-194 found none in C; excluding them costs nothing measured;
  - an entry whose method, or a method inlined into it, is generated or makes an opaque closure;
  - an entry of an anonymous module;
  - an entry whose IR holds a generated name (`#f#12`) that occurs in the lowered code of no method whose F1 it records.
- **What E-195 showed stays evidence for the content fingerprints:** F1 and F3 stable across an unrelated update for all of C's 2,143 entries. F2 (the stakeholders' methods per fact) and the candidate index no longer decide validity; Lemma O explains why `verify_method_graph` rarely fails on facts edges.

## 2. The vehicles, and the bound on the gain

- **The machine-code vehicle** (the environment-keyed cache, E-180, retired): C off its workload from 19.4 to 6.1 s. Julia loads machine code only from a package image, which links to its dependencies by build id, so it cannot be shared across environments.
- **This store keeps optimized IR,** and code generation stays in the session. Its ceiling is lower: about the inference and optimization of the entries it admits. C's facts inference was 7.29 s of self-time against 6.32 s of code generation (E-194), but those are overlapping per-CodeInstance sums over all 2,506 facts CodeInstances of C/p, 671 of which name the session (review M6). The bound is E-a's to establish.
- **The trade** is the user's direction (decisions §5, 2026-10-27): a lower ceiling for reuse across environments.
- **Where the gain is:** facts code over upstream packages (interop, C). Idiomatic trait code (D) gains little: its images hold its code already (0.08 s of facts inference in D, E-194).

## 3. The proposal

### 3.1 Capture: when the code is made

- Julia discards a facts CodeInstance's inferred code once it is compiled, unless it can be inlined (`maybe_compress_codeinfo`; review B3). Nothing is left to write at exit.
- **A recording session keeps the optimized IR of owner `:facts`** as the precompile mode does (`precompile_keep_ir`): a Julia change, a flag read in `finish!`, beside `jl_push_newly_inferred`.
- For E-0 and E-a no Julia change: a recording script infers the session's facts MethodInstances again with the facts interpreter (`Compiler.facts_interp`, `cache_mode = :no`) and takes that IR (review M5's witness).

### 3.2 The writer and the reader (review B1)

`Serialization` is not the vehicle: it writes Methods by content with process-local numbers, makes new Methods and may insert them into the method table when read, and returns MethodInstances and CodeInstances that no cache knows. The store has a writer and reader of its own, with a table of external references by stable name (rustc's model, `../record/incremental-precedents-research-2026-10-27.md`):
- a method by module path, name and signature, checked against its F1;
- a MethodInstance interned in the session (`specialize_method`);
- a CodeInstance by its MethodInstance and owner, resolved to one of the session (a store entry, or one already valid); an `:invoke` statement is relinked so, or the entry is not read (else the JIT queue would cache a copy without validation);
- a binding by module and name;
- a type by path;
- a constant only where it has no identity. A `SplitTable` is made again by `split_table` (compiler §4.3); any other object with identity makes the entry not storable.

**Reading has no side effect before validation:** it defines nothing, inserts nothing, and a failed reference makes the entry miss.

### 3.3 Where

- **One store per Julia build and `CacheFlags`,** in the depot (`compiled/v1.13/facts-store/`). Not per setting: an image's CodeInstances mean the same in both settings ([facts §11](../reference/facts.md#11-package-images)), and so does an entry.
- **One file per entry,** written by atomic rename, so sessions that exit together do not clash (review m5; E-195 run 3 lost a file of the shared depot).
- **Bounded:** variants of one key with different content fingerprints are kept up to a small number; the oldest goes first. The store's size is capped, least recently used first.

### 3.4 Insertion: eager, after each load (review M2)

- **After each package load, outside inference,** in the latest world: every entry whose methods are all loaded and whose content checks pass is relocated, with `max_world` set to the revalidation sentinel, and handed to `verify_method_graph`. This is what image loading does; most of it is Compiler code that exists.
- **No hook inside inference.** Inside `typeinf_edge` a lookup would evaluate folds at load inside inference (against compiler §4.4), would have to respect the stack and `engine_reserve`, and could not take an entry checked only in the latest world for an inference in an older one. A hook is considered only if E-c finds the eager cost on unused entries too high; the lazy index then serves it.
- **Not while a package image is built** (review m2): entries inserted there would enter the image, which holds only code compiled while it was built (facts §11).
- **Inert in a trimmed build:** it has no facts code (compiler §2.10).

### 3.5 What the session keeps

An inserted entry's code that can be inlined is compressed against the session's method roots (`jl_compress_ir`); the rest is dropped after code generation, as Julia does (review m6).

### 3.6 What it gives up, for now

- **Early cutoff** (review M3): a callee whose content changed makes its caller miss, even when only the callee's body changed and its result is equal. Keeping the caller when the callee's inferred result is equal is a later refinement.
- **Entries over other owners' code** (§1).
- **Generated functions and opaque closures** (§1).

## 4. Soundness: G1's criterion

"The same as inference would make" is not defined: inference depends on history (what was inlined, what was cached). The criterion is G1's: the code computes the same, with the same effects (review M3). An inserted entry meets it when:
- every edge verifies in this world;
- every CodeInstance its IR names is relinked to a valid one of this session with the recorded result (return and exception type, effects, constant result);
- every method inlined into it is unchanged (F1);
- every embedded value is the same;
- the flags and the optimizer's parameters are the same.

## 5. What the references gain when it is built (review m7)

- [Facts §2.1](../reference/facts.md#g1) (G1's sources of valid code): the store as a source.
- [Facts §10.3](../reference/facts.md#strict-intended)'s table: a pirate that breaks a stored entry discards it silently, in strict mode too. A stored entry is evidence, not a contract; an image's broken fact stays the one strict mode reports (mine).
- [Compiler §4.4](../reference/compiler.md#44-compilerfold_call): folds of stored entries are evaluated at insertion, outside inference.
- [Facts §11](../reference/facts.md#11-package-images): its Planned paragraph, with insertion off while an image is built.
- [Compiler](../reference/compiler.md): a section for the capture flag and the insertion.
- `design/julia-changes.md`: the capture flag.

## 6. Experiments, in order

- **E-a, the gain's bound** (no Julia change): in C off its workload and in D (perturbed shapes), the exclusive wall-clock time of inference and optimization of the CodeInstances §1 admits; the memory their IR takes; the entries §1 excludes, by reason. **Would change the plan:** a bound under about 1 s in C, the bar at which the store's own costs would eat the gain.
- **E-0, soundness by construction** (minutes, toy packages, as E-193): record in one environment, insert in another through a prototype of §3.2 and §3.4 in Julia code, and compare each entry with a fresh facts inference. Cases: a preference read into a `const`; a `const` computed from a dependency; a mutable constant used for identity; a closure renumbered in a callee's module; a generator changed with the same stub; a recursive pair; a pirate loaded before insertion; an inference in an older world. **Would change the plan:** a case kept whose code differs.
- **E-b, the cost of validity:** relocation and `verify_method_graph` for C's entries, timed beside E-195's fingerprints (F2 and the index), facts on Base functions included.
- **E-c, insertion after the loads:** C's session with the store, its parts timed (reading, relocation, content checks, validation, the code generation that remains); each entry compared as in E-0. **Would change the plan:** results that differ, or a saving under the store's costs.

## 7. Alternatives looked at

- **A hook in inference** (revision 1): see §3.4.
- **`Serialization` as the vehicle** (revision 1): see §3.2.
- **Validity by F2 and the candidate index** (decided 2026-10-27, replaced by the user's answer to open issue 80): recorded in `design/alternatives.md`.
- **An image of the copies of Base methods compiled by facts, keyed by the Julia build:** keep-compiled exists (compiler §2.9) and such an image never goes stale within a build, but C has only 173 such entries (E-194). Not a step of its own.
- **Only `return_type`'s results:** C made 7 answers (E-194). Not worth it.

## 8. The review of revision 1, and what is done with each finding

| Finding | Done |
|---|---|
| B1 `Serialization` | §3.2: a writer and reader of its own |
| B2 embedded values | §1 (content), §3.2 (constants), E-0's first three cases |
| B3 nothing at exit | §3.1: captured when made |
| M1 `verify_method_graph` | §1, the user's answer to open issue 80 |
| M2 the hook's place | §3.4: eager insertion after loads |
| M3 optimized IR, G1 | §1, §4; early cutoff given up (§3.6) |
| M4 other owners | §1: not stored |
| M5 E-195's witness | §3.1, E-0 witnesses with the facts interpreter |
| M6 the bound, the order | §2, §6 (E-0 added) |
| m1 the key | §1 (flags, module options), §3.3 (not per setting) |
| m2 precompilation, trim | §3.4 |
| m3 generated, opaque | §1 |
| m4 generated names | §1 |
| m5 a shared depot | §3.3 |
| m6 IR kept | §3.5 |
| m7 references | §5 |
| m8 the citation | §1 no longer cites the 30 checks (E-195 parts 1–2) |
