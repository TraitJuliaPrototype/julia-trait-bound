# The store of the facts-keyed cache, and its vehicle (W-66, step 4)

Status: **proposal, revision 1, reviewed; not to be built as written** (2026-10-28, mine; W-66). Not normative. [Its fresh-eye review](../reviews/2026-10-28-facts-cache-store.md) found three blocking faults (B1 `Serialization` cannot carry compiled code; B2 the fingerprints miss values that optimized IR embeds; B3 inferred code is discarded before exit) and proposes validating stored code with Julia's own edge validation (M1), which changes the user's decision on the fingerprints' form: [open issue 80](../open-issues.md#1-decisions-waiting-for-the-user). The user decided it on 2026-10-28 (option (b), M1's form): the revision is next (§7).

## 1. What is settled

[The note](2026-10-27-facts-keyed-cache.md) (revision 2, §5b) and its experiments fix what an entry is and when it is valid:
- **An entry** is a CodeInstance of owner `:facts`, compiled by a session, naming no type or function of the session.
- **Its identity** is a fingerprint scoped by the facts rule: F1 its method's lowered code; F2 per fact the stakeholders' methods of the fact's function and, for a callee, its inferred result; F3 the layouts it reads (E-195).
- **Its candidates:** the entry records the methods from outside each fact's stakeholders that intersect the fact. A session flags a candidate that is new, gone or changed (E-195 part 4: all of C's 2,143 entries kept across an unrelated FunctionWrappers update; none unsound in 30 small checks).
- **Folds and bindings** are checked as today; a fold is evaluated at load (compiler §4.4).
- **Strict mode is policy:** in a cache entry, a winning candidate discards the entry for the session.

What is open is the store: what is kept, where, and how a session finds and uses an entry.

## 2. What the store must give, and the bound on its gain

- **Inference first.** In C's session facts inference is 7.29 s of self-time against 6.32 s of code generation (E-194, overlapping). A store of inferred code removes the first; a store of machine code would remove both, but Julia cannot load machine code outside a package image, which links to its dependencies by build id.
- **So the first vehicle keeps inferred code,** and code generation stays in the session. Its bound: about the facts inference of a session's first calls, in C several seconds, in D (idiomatic trait code, whose images already hold its code) little.
- **The fingerprints' cost** is paid at a lookup. The prototype (`experiments/w66/Fingerprints.jl`) was not built for speed and its cost was not measured alone; E-195's checks spent minutes, most of it the witness (the code typed again).

## 3. The proposal

### 3.1 What an entry stores

- The method, by module path, name and signature; the specialization (`specTypes`).
- The inferred code, uncompressed (`CodeInfo`), with its edges as signatures and method references by path, as `Serialization` writes them. Compressed IR indexes its method's roots, which a session may number differently.
- The result: return and exception type, effects, constant result.
- The fingerprint (F1–F3) and the recorded candidates.
- Its first-call checks' passes, as §2.4's records are (the checked-record, E-203).

### 3.2 Where

- **One store per Julia build and setting,** in the depot (`compiled/v1.13/facts-cache/`), keyed by the method's path and specialization. An entry is usable in any environment whose fingerprints match (the note §2, M1).
- **Written at a session's exit,** as TraitWorld's retired environment-keyed cache wrote its own (E-180): the session's new facts CodeInstances that pass §1's conditions. An entry already present with the same fingerprint is not written again.
- **Read lazily:** an index (path and specialization → file offset) is read at the first facts compile request of a session; an entry only when asked for.

### 3.3 How a session uses an entry: a lookup before inference

- **The hook (a Julia change):** when the facts interpreter misses its cache for a MethodInstance (`typeinf_ext`, `typeinf_edge` under owner `:facts`), it asks a lookup function, if one is installed: `facts_store_lookup(mi) -> Union{Nothing, CodeInstance}`.
- **The lookup** (TraitWorld, or a small Compiler module): finds the entry, computes the fingerprint of what it names in this session (F1–F3, memoized per function and world), compares the candidates, evaluates its folds, and on a match builds a CodeInstance of owner `:facts` from the stored code, with its edges resolved in this world, and inserts it as inference would. On any mismatch it returns `nothing`, and the session infers as it does now.
- **Edges and invalidation:** the inserted CodeInstance has ordinary edges, so the session's invalidation follows it as any other code. Nothing new is needed after insertion.
- **Callees:** an entry's callee CodeInstances are entries too, looked up when the edges are resolved; a callee that misses makes the caller miss (no partial insertion).

### 3.4 What it does not do

- No machine code: code generation of an inserted CodeInstance runs as for inferred code.
- No plain code: the plain half of a session (E-194: 1,557 of C's CodeInstances) is outside the facts rule.
- No validation of package images (PE-8).

## 4. Risks and the questions for the review

1. **Soundness of insertion:** is a CodeInstance built from stored inferred code, with re-resolved edges, the same as inference would make in this world when the fingerprints match? The fingerprints were tested against the compiled code as a witness (E-195), not against insertion.
2. **Cycles:** a recursive group must be inserted together, or not at all (GHC's #18733, the note §5b).
3. **The hook's place:** `typeinf_edge` runs inside an inference; inserting there must not break the caller's cycle detection or world bounds.
4. **Cost:** the fingerprint at lookup (F2 walks the stakeholders' methods of every fact's function) against the inference it saves. A lookup that costs more than inferring is no gain.
5. **What `Serialization` can carry:** closures, generated functions' output, opaque closures, and `Core.Binding` edges.

## 5. Experiments before the Julia change (to register)

- **E-a, the gain's bound:** in C and D (perturbed shapes), the facts inference self-time of the CodeInstances that §1's conditions admit, against the session (from E-194's probe).
- **E-b, the lookup's cost:** the fingerprint of every entry of C, computed in a session from memoized per-function parts, timed.
- **E-c, insertion without the hook:** in a fresh session, before the workload, the stored entries inserted for every MethodInstance in a recorded list (a Julia script, as a lookup would), then the workload: the results equal, the facts inference saved, the code the session compiles. **Would change the plan:** results that differ, or a saving under the lookup's cost.

## 6. Where it would be recorded

[Compiler](../reference/compiler.md) (a planned section for the hook and the store), [facts §11](../reference/facts.md#package-images) (what a session may take from the store), the note's §2, W-66's row, `design/julia-changes.md`.

## 7. The review, and what is done with it

[The review](../reviews/2026-10-28-facts-cache-store.md) (fresh eyes, Opus, of revision 1):
- **B1** (`Serialization` copies Methods and MethodInstances, may insert methods, copies Bindings): the store needs a writer and reader of its own that name everything outside an entry by stable name (rustc's model). For the revision.
- **B2** (`const` values, preferences and objects with identity embedded in optimized IR): the content fingerprint must cover the values an entry embeds; an experiment by construction (E-0) comes first.
- **B3** (inferred code discarded once compiled): entries are captured in `finish!`, not at exit.
- **M1** (Julia's `verify_method_graph` validates loaded CodeInstances exactly, cycles included; fingerprints then only for content): open issue 80, the user's to decide, since it changes the form of F2 decided on 2026-10-27.
- **M2** (no hook inside `typeinf_edge`; eager insertion after loads, as E-c does): for the revision.
- **M3–M6** (optimized IR and G1 as the criterion; entries reaching plain code excluded, as the note says; E-195's witness weaker than read; the gain's bound not established): for the revision, with E-0 before E-c.
- **m1–m8:** for the revision.
