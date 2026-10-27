# Validation remembered for an unchanged environment

Status: **proposal** (2026-10-27, mine; W-58, [open issue 73](../open-issues.md#2-design), its second option). Not normative. A Julia change, not trait-specific; opt-in while it is an experiment (`JULIA_REMEMBER_VALIDATION=1`).

## 1. The question

The load is the session's largest term once a cache covers the work after it: stock SciML and CairoMakie load in 3.6–3.7 s of a 4.5 s session (E-184). E-185 profiles the load (stock 1.13.2, setting S): validating the images' edges takes about 34% of it (about 1.4 s), activating their methods about 27% (about 1.1 s); promoting validated code to the current world almost nothing. Validation repeats, in every session, the same method lookups with the same answers, as long as the method table is the same when each image is restored.

## 2. The design

**A chain key in the runtime.** A 64-bit value, mixed at every change of the method table that the restored images do not account for, in the order they happen:
- each image restored: its checksum, after its methods are activated; an image whose methods the image hook leaves inactive (strict mode's refusals) breaks the chain;
- each method defined at run time (`jl_method_table_insert`): its signature's object id;
- each method deleted (`jl_method_table_disable`): its signature's object id, marked.

Two sessions that start from the same system image and restore the same images in the same order, with the same definitions between them, have the same chain key before each image's validation, and the same method table.

**What is remembered.** After an image's edges are validated in the usual way, the outcome per CodeInstance of the image (`internal_methods`, in the image's own order): valid in the current world, or not. It is written to `<depot>/compiled/v<major>.<minor>/validation/<key>`, with the image's checksum and the number of its entries, by a rename.

**What a later session does with it.** Before validating an image, the loader looks up the key. On a match, for each CodeInstance of the image still awaiting validation:
- **recorded valid**, and none of the conditions below: its method's source is scanned for global references as today; its world range is set from the validation world; it enters its method instance's cache if its native code is valid; its backedges are stored; it is promoted to the current world. No method lookup.
- **recorded invalid, or any of the conditions below:** validated in full, as today.
- **The conditions** that always validate in full: edges to bindings or to folds kept with the code (their validity depends on session state, not only on the method table: [compiler §4.4](../reference/compiler.md#44-compilerfold_call)); a method whose global references were invalidated in the session; code that needs instrumentation (coverage, allocation logs).

**Soundness.** An edge's validity depends on the method table's answer for its signature in the validation world. With the same chain key, the method table holds the same methods (the system image's, the images' in the same order, the same run-time definitions), so the answers are the same. What the method table does not decide is validated in full (the conditions). A wrong key (a 64-bit collision) is the residual risk.

**The cost.** One small file read per image; the backedges stored as today; no lookups. The world range of remembered code starts at the validation world instead of the earliest world its edges allow, which only hides it from tasks in older worlds.

## 3. What it would change

- `src/`: the chain key (`staticdata.c` at restore, `gf.c` at insertion and deletion), with accessors.
- `base/loading.jl`: the lookup and the record around `insert_backedges`.
- `Compiler/src/reinfer.jl`: the remembered path beside `insert_backedges`.
- The references: [compiler §2.9](../reference/compiler.md#29-what-package-images-keep) or a new section on image restore, when adopted; [julia-changes](../design/julia-changes.md).

## 4. The experiment (E-186, minutes)

Setting U (the patched Julia, upstream packages, plain) and C: the load with and without the remembered outcome (the first session records, the next ones use), two runs each; the same outputs; a session that defines a method before `using` (the chain differs: no reuse); the remembered files' size.

**Would change the plan:** a saving well under E-185's 1.4 s (the backedges' storage dominates), or outputs that differ.
