# Review: the cache keyed on facts and their origins (W-66)

Reviewer: fresh eyes (Opus 5.5), 2026-10-27. Files read; nothing run. Reviewed:
- the design note `writeup/plans/2026-10-27-facts-keyed-cache.md`, at design commit 9c93e5a (the last commit to touch it);
- `writeup/explorations/facts-keyed-cache.md` with its §6 (E-188);
- `experiments/ttfx/README.md` (E-175, E-180, E-185 to E-188), `experiments/ttfx/cache/probe_origins.jl`, the registry rows E-180 to E-189 in `writeup/record/experiments.md`;
- `writeup/reference/facts.md` §1, §2, §4, §6, §7, §9, §10, §11; `writeup/reference/compiler.md` §2, §4.2–§4.4, §5.4; `writeup/reference/lowering.md` §2, §4.6, §14–§16;
- the retired cache: `writeup/plans/2026-10-27-session-cache.md`, `writeup/reviews/2026-10-27-cache-design.md`, `writeup/reviews/2026-10-27-cache-and-port-notes.md`; `writeup/reviews/2026-10-27-w58-direction.md`;
- open issues 72, 73 and 76 (closed); W-21, W-62, W-66, W-69 in `writeup/record/todo.md`; `writeup/record/decisions.md` §4 and §5;
- julia-1.13 41d199c557 (E-188's build): `Compiler/src/reinfer.jl` (`verify_method`), `src/staticdata.c` (external linkage).

---

## Summary

- **The direction is right in one respect:** facts code is the only code whose validity can be stated without the whole method table, so it is the only code for which a key finer than the environment can be sound. E-188 shows that a facts-only cache has a large part (the Base-only copies) that no package change touches.
- **The note's validity claim does not hold as written.** "Valid wherever its origins are the same" needs three things the note does not give:
  - **the right stakeholders:** E-188's origins come from direct edges only. Julia's own validation is transitive, and facts §1 counts supertypes' owners (B1);
  - **an identity that fixes the code:** a package's tree hash does not determine its methods, its types' layouts or its constants. Dependencies' macros (TraitWorld's lowering of every trait package), `@eval` over a dependency's data and field layouts all change with a dependency's rebuild. Julia's images cannot even load against a rebuilt dependency (B2);
  - **presence:** some definitions change a fact without changing any origin's identity: an origin's extension activated by another package, a standard library loaded later, methods evaluated into an origin's module, joint owners, session edits. Strict mode refuses none of these, by design (B3).
- **G2 is a statement about one session's method table.** Reuse across sessions also needs the identity of every object the code names. Julia gets that from build ids. The note replaces build ids with something weaker.
- **Strict mode does not make Phase B's "no edge walk" sound** (B4):
  - a pirate loaded before an image is found only by checking the image's facts, which is the detection Phase B wants to skip;
  - the classes in B3 are followed by strict mode, not refused.

  The pirate-candidates variant, restated relative to an entry's dependency closure, is the mechanism that works, with or without strict mode.
- **A sound version is close:**
  - identity = the build ids of the entry's dependency closure (Julia's own key, which Phase A gets anyway);
  - validation = an index of the methods not from that closure's images, plus bindings and folds evaluated as today;
  - strict mode = policy (error or follow), not the enabler.
- **Phase A as specified is a re-run of the retired cache, restricted to facts code** (M2):
  - its reuse is decided by Julia's staleness of each part's whole closure, not by origins;
  - its 213 origin sets cost about 1.7 s at about 8 ms a part, so they must be merged back to coarse parts;
  - it is not Phase B's vehicle.
- **The evidence needs repeating before it carries the design** (M1):
  - E-188's C session ran with a stale extension image, the condition for which E-187 was declared invalid;
  - its origins are incomplete (B1);
  - its "a quarter at most" ignores that a new version rebuilds every dependent.
- **The facts-only framing has an unmeasured cost** (M6). In D, the trait demonstrators, the session made 95 facts and 475 plain CodeInstances. Measured in time, how much of a session the cache can save is not known.

---

## Findings

### B1. E-188's origins are not the stakeholders of an entry's facts (blocking)

**Evidence.**
- `probe_origins.jl:36–53` takes three things:
  - the entry's method's module;
  - the packages of the types in its `specTypes`;
  - for each edge, the callee method's module (`methpkg`), and the packages of the types only for edges that are `Type`s (`e isa Type && typepkgs!(o, e)`).
- **Not transitive.** Julia validates a CodeInstance and then, recursively, every CodeInstance it has an edge to (`reinfer.jl:298` ff., the `:recursive_phase`; facts §4.3: "a CodeInstance it has an edge to is invalidated"). An entry that inlined `PkgB.g`, whose own CodeInstance inlined `PkgC.h`, depends on PkgC. Its origins name PkgA and PkgB only.
- **No supertypes.** Facts §1 (`facts.md:70`): the stakeholders of a concrete signature include "the supertypes of each of these". `typepkgs!` follows `x.name.module` and the parameters, never `supertype`. Take `P.T <: Q.A`. Then `Base.show(::IO, ::Q.A)` in a new version of Q is no pirate, yet it wins at `show(::IO, ::P.T)`. The entry's origins are {P, Base}.
- **Direct edges' signatures not walked.** A direct `CodeInstance` or `MethodInstance` edge contributes its method's module only. Two stakeholders of the call can then be missed:
  - the function's owner (a method of `PkgB.f` defined in PkgA names PkgA, not PkgB);
  - the argument types in the callee's `specTypes`.
- **Binding edges and fold records ignored.** `ci.edges` holds `Core.Binding` and `FoldRecord` entries (`reinfer.jl:242`, `:247`), and a method's own global references are scanned apart (`scan_new_method!`, `reinfer.jl:207`). `methpkg` returns `nothing` for all three, and neither is a `Type`. The note's "the libraries of its folds" is in the design but not in the measurement.
- **Types reached through fields.** `s.a.x`, where `P.S` has a field `a::Q.T`, is `getfield`: a builtin, with no edge. Q's layout is compiled into the code, and Q is no origin.

**Consequence.** Under the note's identity (B2), each item is a stale entry used as valid: a wrong result, or a wrong offset. Under build-id identity of the closure (the fix of B2), the content side of each is covered, because a package can only name its dependencies. Then the precise origin set no longer carries soundness, only grouping and the share that survives a change. Either way, E-188's numbers are lower bounds of an unstated quantity (M1).

**Fix.** Define an entry's origins as its dependency closure: the closure of its method's package, its signature's packages and its direct edges' packages, under the manifests' dependency relation. Its identity is that closure's build ids (B2). Keep E-188's antichain for grouping and for loading.

### B2. A package's tree hash does not fix the code compiled from it (blocking)

**The note** (§2, "A package's identity"): "An identity does not change when only a dependency is rebuilt." A dev'd package gets "a hash of its source files", which §3.3 calls "exact".

**Why it fails.** A method's lowered code, a type's layout and a constant's value depend on more than the package's source:
- **Dependencies' macros.**
  - Every trait package's methods are TraitWorld's expansion of `@trait_module` and `@implement` ([lowering §2–§8](../reference/lowering.md)). TraitWorld changed three times in one afternoon ([the direction review](2026-10-27-w58-direction.md), finding 4).
  - A worker whose lowered body names no TraitWorld type or method has origins without TraitWorld. Its tree hash survives a TraitWorld commit that changes its code.
- **`@eval` over a dependency's data,** `pkgversion(Dep)` tests, `@static if isdefined(Dep, …)`.
- **Struct layouts** of a dependency's types reached through fields (B1).
- **`include_dependency` files** outside the tree, and environment variables read at precompile time. Julia tracks the first and not the second. The cache inherits the second from Julia, as images do.

**And the vehicle cannot use such an identity.** An image refers to objects of another image by that image's build id and a byte offset into it (`staticdata.c:161–163`, `add_external_linkage` at `:1096`). Code cannot be loaded against a dependency that was rebuilt, even from the same source. Phase A's generated packages are therefore keyed by build ids whatever the note says. Phase B's "identity unchanged when a dependency is rebuilt" would need a new image format that links by name, and a content identity for each method and type. The note does not mention either.

**Fix.**
- Identity = Julia's build id of each package in the entry's closure, and of each of its active extensions (B3).
- The store key = the Julia commit, the system image's checksum, Julia's code-generation flags and CPU target (Julia's cache flags), and the setting (W-69, facts F-7).
- Reuse across environments then happens exactly where Julia already reuses an image: the same package with the same dependency subtree in a shared depot.
- The Base-only half survives every package change.
- A content identity robust to dependency rebuilds is a later refinement, with its own vehicle (Optional).

### B3. Definitions that change a fact without changing any origin's identity (blocking)

Each of the following changes dispatch at a concrete fact of an entry. In each, every origin's identity is the same, under the note's identity and under build ids alike:

| Source | Why no identity changes | Strict mode (facts §10.2–§10.3) |
|---|---|---|
| an origin's package extension, activated by an unrelated package's load, whose method applies without its triggers' types | the parent's tree hash and build id are the same; the extension's image is separate | followed, with a warning (facts §2.2, §10.3) |
| a standard library loaded later: SparseArrays' `vcat` for Base's types | "the standard libraries and Base: the Julia build" | not checked: Julia is one owner (§10.2, rule 1; open issue 19, E-189) |
| a method evaluated into an origin's module by another package's image, or at `__init__` | the method belongs to the module it is evaluated in (§1; open issue 65, E-189) | a stakeholder's: followed |
| a joint owner's or a delegate's method | stakeholders by declaration, outside the entry's closure (SciMLBase's joint owner DiffEqBase depends on SciMLBase, not the reverse) | followed |
| an edit in the session (Revise) | the method is a session definition; the tree hash at exit may or may not include it | the one exception (§10.3) |
| a closure image's method left inactive by the image hook, or deleted | the image's build id is the same | the deletion is an error in the intended design; TraitWorld's own deletions are exempt |

- The note's identity for an extension ("its own, with its parent's and triggers'") covers entries that name the extension. It does not cover entries of its parent that the extension's method changes, which is facts §2.2's case.
- The retired review found the same gap as "variants of one signature" (`2026-10-27-cache-design.md` §5, item 4). In the new design it is a correctness question, not a miss: the entry would be used.

**Fix.** Validation needs a check against these definitions, not a comparison of identities. B4 gives one.

### B4. Phase B's validation cannot rest on strict mode; restate the pirate-candidates variant (blocking for Phase B)

**The note** (§2, Phase B; [decisions](../record/decisions.md) §4, the first row): "Strict mode guarantees that no pirate wins at a fact", so an image of facts code is validated by comparing origins, with no edge walk.

**Why it fails.**
- **Pirates loaded before the image.** Strict mode's prototype refuses a pirate that would win at a fact of code that exists at the pirate's definition. An image loaded later brings facts that did not exist then. The intended design raises "at the image's validation, naming the pirate" (facts §10.3, the first row). That needs exactly the check of the image's facts against the session's methods which Phase B wants to drop.
- **B3's classes** are followed by strict mode by design. So "origins equal + strict mode" is not sufficient even for a perfect identity.
- **Binding redefinitions from another module:** facts §2.2 says strict mode's intended design refuses them at their source. §10.3's table does not list them (a stale copy, below).

**The pirate-candidates variant as written** ("the methods it adds to functions it does not own") is unsound:
- it misses an extension's methods on its parent's own functions (an extension counts as its parent, so it "owns" them), which is facts §2.2's case;
- it misses session definitions (Revise, `__init__`, the prompt) and deletions or deactivations;
- whether it catches joint owners, delegates and standard libraries depends on which ownership rule "does not own" uses.

**The sound form, relative to the entry's dependency closure:**
- **Candidates** for an entry: every active method not defined by an image in its closure, plus the closure's methods that are inactive or deleted.
- **The index:** the session keeps the candidates by function. Most functions have none; pirates, extensions, joint owners and session definitions put a few on some.
- **A fact needs a walk** only where a candidate on its function intersects its signature. Each callee CodeInstance must be valid, which Julia's recursion already checks with an early return.
- **Bindings and folds** are checked as today: the binding's partition; `g(AtLoad(), …)`.

Why it is sound: with the closure's images identical (B2), a winning method is either new to the session or a removal. A new method from inside the closure would mean a different image. So every new winner is a candidate.

Why it is cheap: by Lemma O, a non-pirate method that applies at a fact is a stakeholder's, and every stakeholder whose image is in the closure is excluded. So the index holds only pirates and the classes of B3, not every method that unrelated packages add to Base's functions.

**What it means for the design.**
- Strict mode becomes policy:
  - a candidate that wins in a package image raises in strict mode (piece 15's report);
  - in a cache entry it discards the entry (M5).
- The index is piece 15 generalized. It serves strict mode's intended design and open issue 73's lever for every package image, not only the cache.
- The decision to take up strict mode with W-66 stands. The rationale clause of its log row ("since strict mode guarantees that no pirate wins at a fact") and the note's Phase B paragraph need restating. Whether validation rests on the index, independent of strict mode, is a design change for the user to confirm (open issues §1).

### M1. E-188 does not yet support the numbers the note relies on (major)

- **The setting was invalid.** C's session "compiled 20.9 s during its load (an extension image stale in `depot-C`, as in E-187)" (`experiments/ttfx/README.md:415`):
  - E-187 was marked "done, invalid" for the same condition (`experiments.md:272`); E-188 is marked "done";
  - its 11,543 facts CodeInstances against E-180's 3,418 entries of both owners suggest much of it is code a valid setting loads from images.
- **The probe is incomplete** (B1).
- **"One package's new version invalidates at most a quarter"** counts only entries that name the package. Under build ids, a new version rebuilds every dependent:
  - a new version of a package low in the tree (TraitWorld, PrecompileTools, StaticArraysCore, SciMLBase) invalidates every entry whose closure holds it;
  - for TraitWorld that is close to every non-Base entry.
- **LinearAlgebra tops the list at 24.7%.** The note's identity for standard libraries is "the Julia build", so it is not a package that has versions there (unless upgradable). Among packages, the largest is SciMLBase at 19.9%.
- **The 213 origin sets** come from the same session. Merging (M2) depends on them.

**Fix.** Mark E-188's C row invalid, as E-187's is. Repeat it on a valid C (`--compiled-modules=strict`, the direction review's finding 4) with the probe of the experiment below.

### M2. Phase A's value is small as specified; it is not a step towards Phase B's vehicle (major)

- **Its reuse is Julia's, not the origins':**
  - a generated part's image lists every module loaded while it was built and their build ids;
  - it goes stale when any of them changes: a part under CairoMakie with about 260 packages ([the cache's design review](2026-10-27-cache-design.md) §1, "Staleness").
  
  "A manifest change invalidates only entries whose origins changed" does not hold for Phase A. What Phase A gains over the retired cache:
  - facts code only;
  - a store that survives an environment change and is replayed into the stale parts (that review's §4, option 1);
  - a Base-only part that survives every package change.
- **Load against granularity.**
  - At about 8 ms a part (E-180; E-187's 13 parts in about 0.1 s comes from an invalid run), 213 origin sets cost about 1.7 s.
  - Merging into covering parts brings back coarse closures. It also brings back laziness lost: an entry waits for its part's whole union, or never arrives in a session that loads a subset.
  - The cache's load is dominated by this fixed cost (87% at C's size, the cache's design review §1), not by validation. So Phase B's lever does not address the cache's main load cost; the vehicle does. The note marks the vehicle Optional (§3.2).
- **It does not prepare Phase B.** Phase B's validation is a Julia change to image validation (B4), measurable on package images with no store at all. Generated packages are not its vehicle.
- **Its refutation signal is weak.** Julia's build-id staleness hides B2 entirely. B3 shows only if the second environment loads an extension's trigger, SparseArrays, or a package that evaluates into another module. The planned "one unrelated package's version" exercises none of them.
- **Builder cost:** 174–311 s for C's first build (E-180, E-187). The note's "minutes once built" is the sessions, not the build.

**Fix.** Either skip Phase A, or build it as a small change of the retired branch (`session-cache`):
- the facts owner only;
- parts kept as Julia keys them;
- the store kept across environments and replayed;
- a rebuild of stale parts (the retired review's defect: no rebuild without a new entry).

Use it then as the harness for B3's cases, not as a stage of the design.

### M3. Entries name code of other owners, which origins cannot validate (major)

- **The compiler's plain code.** Code compiled by facts that calls compiler functions directly holds edges to plain compiler code, "valid as long as plain Julia keeps that code valid" (facts §6.4; lowering §2: TraitWorld's machinery calls `argextype`, `widenconst`, `sptypes_from_meth_instance`). Plain code at abstract call sites can be invalidated by any package. Such entries are not "valid wherever origins are the same".
- **Plain answers for `return_type`.** Rule 2's fold (facts §7.1) holds an edge to a CodeInstance of `:facts_plain_return_type` whose own edges must rest on facts. The check gives up after 2000 CodeInstances (C-9).
- **The store is not closed under edges.** It keeps owner `:facts` only, yet its entries name CodeInstances of other owners that may be in no image.
- **Under `all`** code compiled by facts lives under owner `nothing` beside plain code (F-2): the store would see none of it, or plain results with non-fact edges.

**Fix.**
- Phase B keeps Julia's walk for any entry whose closure reaches a CodeInstance of another owner, or excludes such entries.
- The store keeps, or finds in images, every non-image CodeInstance its entries name.
- The cache is for the product setting until F-2 is fixed, and the setting is in its key (W-69).

### M4. Folds and first-call checks are not functions of origins (major)

- **Folds.** A fold's value is its library's answer in the session, not a function of the library's identity.
  - `_member_fold` reads the family's registry, and at load `_member_fold(AtLoad(), …)` fixes the member in the session (lowering §4.6). That is a side effect, and it can raise `ImplementError` or warn.
  - Both phases must evaluate every `FoldRecord` at load, as image validation does (compiler §4.4).
  - The note lists the folds' libraries as origins instead.
- **First-call checks** carry no edges (lowering §14). What a kept check certifies, and when it runs again, is the retired review's §5 item 2 and decision 4, which open issue 76 says carry over to W-66. The note says only "with its first-call checks". Unanswered:
  - a check that only warned, kept, warns once per environment;
  - a stricter `fully_typed_level` or a `concrete_level` method in a later session skips the check;
  - the scan for overrides (`_refuse_overrides`) is skipped too.

**Fix.**
- State in the note that folds are evaluated at load in both phases.
- State what a kept check certifies, for example "a clean pass at the default level". Name the session settings that run it again.
- Record it as mine, for the user to confirm.

### M5. What strict mode does with a cache is not decided (major)

- [The first review](2026-10-27-cache-and-port-notes.md) M1 and [the cache's design review](2026-10-27-cache-design.md) §5 item 1 and decision 3 raised it. Under the intended design, a pirate loaded before a cache part raises when the part loads. So whether a session errs depends on what earlier sessions compiled.
- The note's §3 lists neither this nor the other carried-over questions (budgets, default on or opt-in, disk, background CPU).

**Fix.**
- The rule "a cache entry is evidence, not a contract": a winning candidate (B4) discards a cache entry silently, and raises only for package images.
- As a sentence for facts §10.3 when Phase B is adopted, and as an open choice in the note's §3 meanwhile.

### M6. The trait-specific framing: its cost is unmeasured, and the trait demonstrators argue against "nearly all" (major)

- **The counts:**
  - E-188's D/p (the trait demonstrators): 95 facts and 475 plain CodeInstances;
  - C/p: 11,543 and 11,453;
  - facts code is 11% of what C loads (open issue 73).
  
  The exploration's §5 says "in a whole trait world it is nearly all", and the note says "only the plain layers' code". D is the closest thing to a trait world on hand, and its plain share is 83% by count.
- **Counts are not time.** CodeInstances carry their inference and code-generation times (`time_infer_total`, `time_compile`; the cache's design review §1). The probe can report time per owner in minutes.
- **The direction review's caution applies** (`2026-10-27-w58-direction.md`, finding 1). With a both-owner cache, the plain twins beat the demonstrators (Dp 0.64 s against D 0.97 s). A facts-only cache gives the plain twins nothing. A gain shown against no cache would credit traits with what a general cache also gives.
- **What is trait-specific and testable:**
  - no load-order key (G2);
  - validation without the method-table match (B4's index), if the index stays small.

**Fix.**
- The note's §2 "What it does not keep" in seconds, from the probe.
- §4's comparisons against E-180's both-owner numbers (D 1.07 s, C 6.1 s) as well as against no cache.
- The two trait-specific claims as the hypotheses, each with its experiment.
- Plain code stays a known gap. Julia's own images and workloads serve it.

---

### m1. "Without strict mode, Phase B walks the facts edges only: fewer, but still a walk"

A cache entry is facts code: all its method-table edges are facts edges, so "fewer" applies only to mixed package images. Say so.

### m2. The note's §1 names two causes of a fact change

G2's full list (facts §2.2) has more:
- a binding redefined from another module;
- a method on a closure's type from outside its module;
- the invalidation of a CodeInstance of the other mode;
- a stakeholder's extension activated by another package;
- the standard libraries.

Cite it rather than restate two.

### m3. Code-generation flags and the system image missing from the store's key

"One per Julia build" needs the system image's checksum, which differs for a custom image or the facts system image. It also needs `--check-bounds`, `-O`, the CPU target and the setting. Upgradable standard libraries have versions in the manifest.

### m4. The entry criterion is narrower than the retired review's m1

"Names no type or function of the session" must cover the whole CodeInstance: IR constants, `Ref`s (the first-call check's flag is a `Ref` embedded in the code, lowering §14), fold records, edges.

The probe's `:session` test also admits methods defined at run time in a loaded package's module (by `__init__` or `eval`). Those are in no image.

### m5. Eviction by origin

"An entry whose stakeholder version is no longer in any environment on the machine" needs the machine's manifests. Pkg's manifest usage log is the source `Pkg.gc` uses. Name it, or evict by part recency as the cache's design review §4 suggests.

### m6. E-187 is cited as evidence without its status

The note's §2 says "E-187: 13 parts load in about 0.1 s against 45 in 0.45 s". The registry marks E-187 invalid.

### m7. An entry's identity and its variants

Two variants of one signature (with and without an extension; the cache's design review §5 item 4) must be two entries. With keys by closure they are. Say so in §2's "An entry".

### m8. `Dynamic` splits

A cached caller splits over the candidates registered when it was compiled (compiler §4.2). Its edges then name those candidates' packages, so it loads only where they are loaded. This is correct (G1), but it narrows reuse. A session where other implementations are the first four declared gets different, equally correct code. Worth a sentence.

---

## Answers to the questions, in brief

1. **Soundness of "valid wherever its origins are the same":** not as defined. Per item:
   - **a callee compiled plainly:** only the compiler's own code and `return_type`'s plain answers have edges; neither is origin-valid (M3). Run-time sites and `jl_apply` paths hold no edge and are safe;
   - **abstract signatures and run-time sites:** safe, since they record nothing. `invoke` and `hasmethod` at declared signatures are facts; their declared types need supertypes' owners (B1);
   - **`return_type`:** rule 1 is covered by the entry's facts. Rule 2 is an edge to another owner, transitive (M3). Rule 3 is answered at run time, nothing kept;
   - **folds:** evaluated at load, never origin-valid (M4);
   - **bindings:** binding edges and the method's own global references are ignored by the probe (B1). Values and layouts need build-id identity (B2);
   - **extensions:** B3;
   - **preferences:** covered by build ids, which include the package's and its dependencies' compile-time preferences (B2);
   - **the first-call checks:** M4;
   - **code inlined from other packages:** an edge to the inlined CodeInstance only; its own edges are transitive (B1);
   - **the standard libraries and Base:** the system image's identity, plus which libraries are loaded (B3);
   - **where E-188's origin misses a stakeholder:** transitive callees, supertypes' owners, direct edges' function owners and argument types, bindings, folds, types reached through fields, and every class of B3.
2. **Package identity:**
   - **wrong** for code: it misses dependencies' macros, layouts and `@eval` over dependencies' data (B2);
   - **redundant** in its version, beside the tree hash;
   - **incomplete** without active extensions, the system image, the flags and the setting (B3, m3).
   
   Use build ids of the closure; a dev'd package then needs nothing of its own. Extensions are part of their parent's identity when active.
3. **Phase A:** correct by Julia's validation, but small as specified (M2):
   - its reuse is Julia's staleness of whole closures;
   - its granularity fights its load cost (213 sets at about 8 ms each);
   - it is not Phase B's vehicle.
   
   Worth it only as a small change of the retired branch, as a harness for B3. Phase B's validation can be built and measured on package images first, with no store.
4. **Phase B with strict mode:** strict mode would have to refuse every definition that wins at a fact from outside the entry's closure, including the classes it deliberately follows. For pirates loaded before an image, it would have to find them without checking the image's facts, which it cannot (B4). The pirate-candidates variant as written is unsound. Relative to the closure it is sound, with or without strict mode.
5. **What it does not keep:** the framing is principled, since only facts code admits a key finer than the environment. Its cost is unmeasured in time, and D's counts contradict "nearly all" (M6). The direction review's caution holds: show the two trait-specific claims, not a gain a general cache also gives.
6. **The smallest next experiment:** below.

---

## The smallest experiment that could refute the design

**Step 1, by construction (minutes, no store, no Julia change).** Tiny dev'd packages in `experiments/`, one pair of sessions or environments per case. In each, E-188's origins and the note's identities (tree hashes) are equal, while a fresh compile differs. A digest of the facts CodeInstance (its result type and inferred code) or the call's result shows it. The cases:
1. a dependency's macro changes its expansion (TraitWorld's lowering is the real instance);
2. a dependency's struct gains a field, read through a field of the package's own type;
3. a supertype's owner adds a method for its abstract type;
4. a callee two levels down, in a third package, changes;
5. the parent's extension is activated by an unrelated package's load;
6. SparseArrays is loaded in the second session only.

**Predictions:**
- the note's identity misses all six;
- build ids of the closure catch 1–4;
- no identity catches 5 and 6, and the closure-relative index of B4 catches them.

**What would change the design:** a case that build ids and the index both miss.

**Step 2, at scale (one session each of D and a valid C, minutes).** The probe extended to:
- the transitive closure through CodeInstance edges;
- supertypes' owners, direct edges' signatures, `Core.Binding` and `FoldRecord` edges;
- entries that reach another owner's CodeInstance, flagged;
- inference and code-generation time per owner;
- for each package, the share of entries invalidated under the closure rule (the package and its reverse dependencies, from the manifests);
- for each entry, whether any of its facts intersects a method from outside its closure (B4's index), and the index's size.

**What would change the design:**
- facts code a small share of compile time in D and C. The facts-only cache then saves little, which is a trade-off for the user before Phase A;
- the closure rule invalidating nearly every non-Base entry on a common package's update. Sharing across environments then reduces to the Base-only half;
- most entries hitting a candidate. Phase B's lever is then weak.

---

## Recommendation

1. **Do not build Phase A as specified.** First run steps 1 and 2 above, with registry rows before the runs. Mark E-188's C row invalid, as E-187's.
2. **Restate the note (revision 2):**
   - origins as the dependency closure (B1);
   - identity as build ids, with active extensions (B2);
   - the store key with the system image, flags and setting (m3);
   - Phase B's validation as the closure-relative index (B4), with strict mode as policy;
   - folds evaluated at load and the checks' meaning stated (M4);
   - "evidence, not contract" for strict mode with a cache (M5);
   - entries naming other owners walked or excluded, the product setting only (M3);
   - the plain share in seconds (M6).
   
   Then a fresh-eye review, by W-66's own steps.
3. **Build Phase B's validation first on package images** (open issue 73's lever, piece 15 generalized), with no store:
   - it needs no vehicle;
   - it gives strict mode's error at validation (F-6);
   - its gain is measurable on C and D.
   
   E-186 bounds what skipping the match saves: 0.6–0.8 s of the load in U and C, about half of E-185's 1.4 s of validation (the walk, the backedges and the cache insertions remain). Facts code's part of that is about its share of the loaded code (11% in C). Expect little in C today and more in a trait world. That is a principled improvement under the rule for performance work (decisions §5), but its size is to be stated before the build, not after.
4. **Then the store, with a vehicle without a fixed cost per part** (sections of one image, or a lookup per MethodInstance). Phase A only if the user wants a cache sooner. Then build it as the small change of the retired branch (M2).
5. **For the user** (open issues §1):
   - B4's change: validation rests on the index, and strict mode is policy. The decision to take up strict mode with W-66 is unaffected;
   - M5's rule for cache entries;
   - M6's trade-off once step 2 has measured it.

---

## Stale copies seen (CLAUDE.md, rule 2), for whoever applies this review

- `writeup/record/decisions.md` §4, the first row: "since strict mode guarantees that no pirate wins at a fact" (B4). The user's quoted words and the decision stand; the clause is the agent's rationale.
- `writeup/record/todo.md` W-66: "validation at load by comparing origins (under strict mode no edge walk; otherwise the facts edges only)" (B4, m1).
- `writeup/open-issues.md` 73 (closed), the third option: "stakeholders (its dependencies, fixed by the manifest's versions, and their extensions)". Versions do not fix code (B2); extensions activated by others are not captured (B3).
- `writeup/record/INDEX.md:139`, `:179`: "validated by comparing origins (under strict mode, no edge walk)".
- `writeup/explorations/facts-keyed-cache.md` §2 ("package and version, or build id for a dev'd package"), §3 ("Under strict mode: sufficient"), §5 ("In a whole trait world it is nearly all", against E-188's D).
- `writeup/reference/facts.md` §2.2 says strict mode's intended design refuses a binding redefined from another module at its source; §10.3's table does not list it.
- `writeup/record/experiments.md` E-188: "done" with a stale extension image, against E-187's "done, invalid" for the same condition (M1).
