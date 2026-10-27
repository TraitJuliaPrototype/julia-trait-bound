# Review: validation remembered for an unchanged environment (soundness)

Date: 2026-10-27.
Reviewed: the uncommitted diff in `julia-1.13` on base commit `6800be7839` (`src/gf.c`, `src/staticdata.c`, `src/julia_internal.h`, `Compiler/src/reinfer.jl`, `base/loading.jl`), against the note `writeup/plans/2026-10-27-remembered-validation.md`. Source read only; nothing built or run.

## Verdict

1. **Unsound as written, in one main way.** The fast path decides each CodeInstance by its own edges only. Full validation also takes in the validity of every CodeInstance it calls (B1). A callee can be invalid for reasons the chain key does not see (bindings, folds, a replaced global), and the caller is then accepted anyway.
2. **The key does not name the method table in four further cases:** a different system image with the same Base (B2), a definition racing the fast path (B3), `disable_new_worlds` (B4), and run-time methods in an overlay table (B5). B2 and B3 are plausible in this project; B4 and B5 are rare.
3. **Repairable at small cost.** Run the remembered outcome inside `verify_method` instead of beside it (B1). Mix the system image's identity into the key (B2). Read the key and the world together under `world_counter_lock` (B3). Break the chain in B4, mix the table in B5.
4. **What holds up:** see "Checked and sound" at the end.

---

## Findings

### Blocking

**B1. A recorded-valid caller is accepted although a callee CodeInstance is invalid.** `insert_backedges_remembered` and `remembered_ok`, `Compiler/src/reinfer.jl` (lines 665–707).
- What full validation does:
  - `verify_method` walks the CodeInstance edges in `:recursive_phase`.
  - In `:return_to_parent` the parent takes the child's world range: `parent_maxworld = min(parent_maxworld, max_valid2)`.
  - So a caller is invalid when any CodeInstance it calls is invalid. This holds for callees in the same image (still at the sentinel, validated recursively) and in earlier images (their current `max_world`, early return at line 178).
- What the fast path does:
  - `remembered_ok` looks at the caller's own edges for `Core.Binding` and `FoldRecord`, and at the caller's own method for `did_scan_source & 0x4`.
  - It never looks at CodeInstance edges. The callee's state in this session is ignored.
- Scenario, across images:
  - Q is loaded. In session 2 the user runs `Core.eval(Q, :(const X = 2))`, a const replaced in a package module.
  - This goes through binding partitions, not the method table. The chain key does not change.
  - `invalidate_method_for_globalref!` invalidates Q's CodeInstance `q` that reads `X` (`max_world` set finite).
  - `using P`. P's CodeInstance `p` calls `q` directly (a CodeInstance edge). `p` has no Binding edge of its own. Recorded valid in session 1, so it is accepted.
  - `p`'s native code calls `q`'s stale code, which uses the old `X`. Full validation would have set `p` invalid through the edge to `q`.
- Scenario, within one image: `p` calls `g` in P. `g`'s method has a GlobalRef to `Q.X`, which was replaced in session 2. `g` fails `remembered_ok` (bit 0x4), is validated in full and comes out invalid. `p` is accepted before or after it, in either order of `internal_methods`.
- The same holds for a callee with a `FoldRecord` whose library now answers differently, and for a callee whose own Binding edge was invalidated.
- Revise-style workflows replace bindings in package modules routinely on 1.12+, so this is not only theoretical.
- Fix: put the remembered outcome inside `verify_method`, not beside it.
  - Pass the recorded bits in. For a recorded-valid CodeInstance, treat its MethodInstance, `Int` and invoke edges as valid without a lookup, returning `(meth.primary_world, typemax)`.
  - Keep everything else as it is: the Tarjan walk over CodeInstance edges, the Binding and FoldRecord checks, bit 0x4, `needs_instrumentation`, the cleanup stage and the logger.
  - This also removes M3 and most of m1. The saving stays, because the lookups are the cost.

**B2. The key does not identify the system image.** `insert_backedges_maybe_remembered`, `base/loading.jl:1376`; the initial value in `gf.c`.
- The chain starts at a constant. Julia mixes in only `module_build_id(Base)` and `module_build_id(Core)`.
- A system image built by PackageCompiler (or this project's `experiments/sysimage` prototype) is made by loading the stock image and adding packages. Base and Core keep their build ids. So a stock image and a custom image start with the same key, while their method tables differ by every method in the added packages.
- Package images are found by their header, not by the slug that names the image path (`compilecache_path` mixes `image_file` only into the name it writes). A package image of P that depends only on Base passes the staleness check under both system images. Its checksum, and so the key, is the same.
- Scenario: the session with the custom image records P. The custom image contains Q, which defines `Base.foo(::AbstractVector{Int})`. The stock session has the same key but not Q's method. Or the reverse: the stock session records, and the custom session's Q adds a method that intersects an edge of P. Full validation rejects P's CodeInstance; the fast path accepts it.
- Rebuilding a custom image in place (same path, different packages) gives the same exposure.
- Fix: mix the system image's identity into the initial key: its checksum (`image->checksum` in `staticdata.c`, stored at restore), and better also the build ids of all modules in the system image (`Base._sysimage_modules`, or `jl_get_loaded_modules` at startup).

**B3. The key and the validation world are read at different times; a definition between them is missed.** `insert_backedges_maybe_remembered` reads `jl_load_chain_key`, then reads the file; `insert_backedges_remembered` later reads `validation_world = get_world_counter()`.
- `_include_from_serialized` releases `require_lock` around the restore, so another task can restore another image (activating its methods) at any time, and any task can `eval` a method.
- Scenario:
  - The key is read as K. The file is read (I/O, a window of milliseconds).
  - Another task defines `Base.bar(::Int)`, which P's CodeInstance `p` expected to resolve elsewhere. Activation invalidates through backedges, but `p` has none yet.
  - `validation_world` is read after the definition. `p` gets `max_world = validation_world`, its backedges are stored, and `jl_promote_ci_to_current` succeeds because the world has not moved since.
  - `p` is valid in a world whose table holds a method that breaks it. Full validation looks up in that world and would reject `p`.
- Fix: a C accessor that returns the key and the world counter together under `world_counter_lock`. Use that world as `validation_world`. Fall back to full validation if the world has moved before the first CodeInstance is decided. Later moves are already caught: `jl_promote_cis_to_current` promotes only if the world is still the validation world.

**B4. After `Base.Experimental.disable_new_worlds()` an image's methods stay inactive, but the chain mixes its checksum.** `jl_activate_methods`, `src/staticdata_utils.c:965`; `src/staticdata.c:4470–4473`.
- With `allow_new_worlds` off, `jl_activate_methods` prints a warning and returns without activating the external methods. The `refused` test does not see this, so the key is mixed as if they were active.
- Scenario: session 1 records P normally. Session 2 calls `disable_new_worlds()`, then `using P`. P's `Base.show(::IO, ::PType)` is not in the table, yet P's CodeInstances that call it directly are accepted. Dispatch and compiled code then disagree about which method exists. Full validation finds the expected method never activated (`dispatch_status` 0) and rejects them.
- Fix: break the chain when `allow_new_worlds` is off and `extext_methods` is not empty. (`disable_new_worlds` also erases all backedges, so remembering is moot after it.)

**B5. A run-time method's table is not in the key.** `jl_method_table_insert`, `src/gf.c:3431`.
- The mix is `jl_object_id(method->sig)`. An overlay method (`Base.Experimental.@overlay MT Base.sin(x::Float64) = …`) has the same signature as a method of the same name in the global table.
- Scenario: session 1 defines the overlay at run time, then `using P`, and records. Session 2 instead replaces `Base.sin(::Float64)` in the global table, then `using P`. Same key. P's CodeInstance with an edge to Base's `sin(::Float64)` is accepted in session 2, although its expected method was replaced.
- Rare, because overlays are almost always defined in package images (covered by the checksum). The fix is one line: mix `jl_object_id(mt)` or the table's module and name as well. Mixing a tag for insertion versus replacement is not needed: the order already determines it.

### Should fix

**M1. An image enters the key with 32 bits, not 64.** `jl_load_chain_mix(checksum)`, `src/staticdata.c:4473`.
- `checksum` is `crc32c(data) | 0xfafbfcfd << 32` (`staticdata.c:3491–3493`). Only the low 32 bits vary.
- Two builds of the same package at the same position in the chain (an upgrade, or a rebuild after a change in its source) collide with probability 2^-32. The record then only needs the same number of entries to be accepted, and a new version often has the same number.
- The note's "a 64-bit collision is the residual risk" is therefore too strong. Across many users and rebuilds, 2^-32 per rebuild is not negligible for a cache whose failure is silent.
- Fix: mix the 128-bit build ids of the restored modules (their `build_id.lo` is random per precompile run) as well as the checksum.

**M2. A rebuild of the runtime alone keeps the key.** `sysimage.mk:98`: `basecompiler.ji` depends on `$(COMPILER_SRCS)`, not on the executable or `libjulia-internal`.
- In this repository, a change to `src/gf.c` or `src/subtype.c` (dispatch, specificity, ambiguity) rebuilds the runtime and can leave the system image and Base's build id as they are. Package images are accepted too, because their header names the git commit, which is unchanged for an uncommitted patch.
- Today this is harmless: full validation re-runs the lookups under the new rules. With records, the old outcomes are reused.
- Scenario: a patch changes how an ambiguity is resolved. Records made before the patch accept CodeInstances that the new rules invalidate.
- Fix: mix a build stamp of the runtime (e.g. a string compiled into `gf.c` from the build's time, or the size and mtime of `libjulia-internal`), and `jl_git_commit()`. Also put a format version at the head of the file (see m4).

**M3. The record is written under the key read before validation, even if the table changed during it.** `insert_backedges_maybe_remembered`, `base/loading.jl:1388–1395`.
- The same concurrency as B3 applies on the recording side. `fold_holds` also runs library code during validation.
- Adding methods mostly turns valid into invalid, so the record errs on the safe side. But a run-time replacement or deletion during validation can turn an invalid outcome valid, and that is then recorded under a key whose table does not contain the change.
- Fix: read key and world before and after `insert_backedges_typeinf`; record only if both are unchanged.

**M4. The fast path skips `jl_promote_mi_to_current`, so later validations run slower.** `verify_call` (`reinfer.jl:597–599`) sets `METHOD_SIG_LATEST_ONLY` on a callee MethodInstance after a successful lookup. Later validations use that bit to skip their lookups (the `n == 1` fast path, line 504).
- The fast path never calls `verify_call`, so the bits stay unset. Every image validated in full later in the session (no record, recorded invalid, or B1's fallback) loses this fast path and does more lookups than without the change.
- Not unsound, but it biases E-186: the saving on recorded images is partly paid back on others. The fix in B1 (lookups skipped inside `verify_method`) can still call `jl_promote_mi_to_current` for MethodInstance edges, which is cheap.

### Minor

**m1. `min_world` set to the validation world, not the earliest world the edges allow.** `reinfer.jl:676–679`.
- Full validation sets `min_world` from the edges (at least `jl_require_world`). The note says this only hides the code from older worlds, and that is right for soundness.
- It also changes later state: a caller in a later image takes `parent_minworld = max(…, child.min_world)`, so the narrower range propagates to callers; and code running in an older world (tasks started before the load, `invoke_in_world`) compiles its own copies. With B1's fix the full path computes the usual range at no cost.

**m2. Backedges are stored even when the world has moved.** `reinfer.jl:682`.
- Full validation stores them only when `validation_world == get_world_counter()` (line 339). The fast path stores them always. Extra backedges only cause spurious invalidations later, so this is harmless, but it is a difference in state. With B3's fix it disappears.

**m3. The invalidation logger.** With `_jl_debug_method_invalidation` on (SnoopCompile's `@snoop_invalidations` around `using`), recorded-valid CodeInstances produce no entries, which matches full validation for valid code. The B1 cases would be silent, though. Turn the fast path off while the logger is on: it is a debugging mode, and its users expect the full trace.

**m4. The file has no header.** The note says the record holds the image's checksum and the number of entries. The code writes only the bytes and checks only the length. Add a magic word, a format version, the checksum and `n`. That costs 24 bytes and catches a format change under an unchanged key (M2).

**m5. Temporary file names can clash on a shared depot.** `tmp = file * "." * getpid() * ".tmp"`: two machines with the same pid on an NFS depot write the same temporary file. Use hostname, pid and a random suffix. A failed `mv` leaves the temporary file behind; remove it in the `catch`.

**m6. Files are never removed.** One file per (key, image) accumulates under `compiled/v1.13/validation/`, and every change of the environment adds a set. `Pkg.gc` does not know the directory. Bound it (e.g. remove files older than the newest image they could match), or document it.

**m7. Run-time definitions in `Main` defeat reuse.** Not unsound, but the note's claim "same definitions between them, same key" holds only for signatures made of image types. A module created at run time (`Main`, a package loaded from source) gets a random `build_id.lo` (`module.c:512`), which enters the type name hash and so `jl_object_id(sig)`. A `startup.jl` that defines `f(::Int)` in `Main` gives every session a new key. State this in the note, and expect E-186's "a method defined before `using`" case to show no reuse for this reason, not only because the chain differs.

---

## Checked and sound

- **`jl_object_id(method->sig)`:** declared `JL_NOTSAFEPOINT` (`julia.h:1814`). It allocates nothing and takes no lock, so calling it under `world_counter_lock` is safe. It is stable across sessions for signatures made of image types: concrete types use `dt->hash`, built from the type name hash (module `build_id.lo`, read from the image, and the symbol hash); type variables bound in the signature hash by their position (`type_object_id_`). Unstable cases are the run-time modules of m7, which only lose reuse.
- **The paths that change the method table:** `jl_method_table_activate` is called only from `jl_method_table_insert` and `jl_activate_methods`. `jl_method_table_add` is also called from `precompile_utils.c` (output only). `Base.delete_method` goes through `jl_method_table_disable`, which is mixed. `Core.eval` in `__init__`, `@eval` and the run-time method hook all go through `jl_method_table_insert`. Extensions, and packages loaded lazily from `__init__`, are images and enter by checksum. Exceptions: B4 and B5.
- **Interferences and ambiguity data:** set at activation and determined by the order of activation, which the chain names.
- **`@generated` functions:** full validation consults the generator only for instrumentation, which the fast path refuses (and the loader excludes at the top level).
- **`jl_first_image_replacement_world` and `did_scan_source`:** the fast path calls `scan_new_methods!` with the same `backedges_only` and scans a method not yet scanned, as `verify_method` does. Bit 0x4 for the CodeInstance's own method sends it to full validation. Only the transitive case (B1) is missing.
- **`CI_FLAGS_NATIVE_CACHE_VALID`:** the fast path sets `min_world`, inserts into the MethodInstance's cache, then sets `max_world`. That is the order of `verify_method`'s cleanup stage, for a valid result.
- **Precompile processes, coverage and allocation logs:** `generating_output()`, `code_coverage` and `malloc_log` send the whole image to full validation and write no record. A session that used the fast path writes no record either, so a wrong outcome does not compound.
- **`--compiled-modules`, `--pkgimages`, `--check-bounds` and similar flags:** they select different cache files, hence different checksums. An image loaded without its native code keeps its flags, and the fast path honours them as full validation does.
- **World age and recursion in the loader:** `require` runs `__require` through `invoke_in_world(_require_world_age[], …)` (`loading.jl:2522`, `2644`). The new `read`, `isfile`, `mkpath`, `write`, `mv`, `hash` and `joinpath` calls therefore dispatch in that fixed world. A loaded package's piracy is invisible, and none of these functions calls `require`. Exceptions from the file operations are caught. The remembered path itself runs through `jl_call_in_typeinf_world`, like `insert_backedges_typeinf`.
- **Concurrent sessions writing the same file:** the rename is atomic, and two sessions with the same key write the same bytes (unless one of the B cases applies). See m5 for shared depots.
- **Stale files after an upgrade:** a new Julia version gets a new directory and a new Base build id. A new package version gets a new checksum, subject to M1. A rebuild of the runtime alone is M2.
