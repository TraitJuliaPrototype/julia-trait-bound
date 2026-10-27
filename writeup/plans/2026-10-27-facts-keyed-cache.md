# The cache across sessions keyed on facts and their origins

Status: **proposal** (2026-10-27, mine; W-66). Not normative. Builds on [the exploration](../explorations/facts-keyed-cache.md) and E-188. The environment-keyed cache (W-62) is retired ([alternatives](../design/alternatives.md)).

## 1. What it is for

The user (2026-10-27): "Is there a cleaner design that only catches trait/facts code and doesn't key on the environment but on the facts and their origins?"; then "Let's retire the experimental cache and add this cache to the Todo list."

Facts code depends on the method table only through facts at concrete signatures. A fact changes only by a stakeholder's change or a winning pirate ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). So a facts CodeInstance stays valid wherever its facts' **origins**, the stakeholders' identities, are the same, and no pirate wins at its facts. E-188: in C, half of a session's cacheable facts code depends on Base and Core only, the rest on 39 of 398 packages; one package's new version invalidates at most a quarter.

## 2. The design

**An entry:** a CodeInstance of owner `:facts` that a session compiled and that names no type or function of the session, with its first-call checks. It is identified by its method (the defining package's identity, the method's signature) and its specialization.

**Its origins, read from its edges** (as E-188 does; no compiler change):
- the packages owning its method, the types in its signature, and its edges' callees and signatures;
- the libraries of its folds (`FoldRecord`, [compiler §4.4](../reference/compiler.md#44-compilerfold_call)).

**A package's identity:** its UUID, its version, and its source's tree hash (the manifest's `git-tree-sha1`, or for a dev'd package a hash of its source files), plus its preferences. For an extension: its own, with its parent's and triggers'. For the standard libraries and Base: the Julia build. An identity does not change when only a dependency is rebuilt. That differs from an image's build id.

**The store:** one per Julia build, in the depot, shared by every environment. Each entry is stored with its origins' identities. An entry is usable in any session whose loaded packages have those identities.

**Recording and building:** at exit, a session records its new entries. A builder in the background merges them into the store and materializes them for loading.

**Loading and validation, in two phases:**
- **Phase A, no Julia change.** Entries are materialized as generated packages, grouped by origin set, with small groups merged into covering ones (E-187: 13 parts load in about 0.1 s against 45 in 0.45 s). A part loads once its origins are loaded with matching identities. Julia validates its edges at load like any image's: correct, but not cheaper.
  - **Gains over the retired cache:** reuse across environments, since a manifest change invalidates only entries whose origins changed; no environment key; eviction by origin; only trait and facts code.
- **Phase B, with strict mode's intended design** ([facts §10.3](../reference/facts.md#strict-intended)), a Julia change. An image of facts code is validated by comparing origins, with no edge walk. Strict mode guarantees that no pirate wins at a fact. This is open issue 73's "facts images without edge validation", shared by the packages' own images. Without strict mode, Phase B walks the facts edges only: fewer, but still a walk.

**A variant without strict mode (to evaluate):** each image records, at its build, the signatures of the methods it adds to functions it does not own (its pirate candidates). A session knows the pirate candidates of everything loaded. An entry needs an edge walk only where one of its facts' signatures intersects a loaded pirate candidate. That needs a Julia change, but not strict mode.

**What it does not keep:** plain code. In C that is half of a session's compiled code, mostly Base's methods called from plain code (E-188). In a whole trait world, only the plain layers' code.

## 3. Open choices

1. **Phase B's dependency on strict mode's intended design.** The clean-up proposal (W-65) keeps for the user whether to take strict mode's intended design up now. Phase B needs it, or the pirate-candidates variant.
2. **The vehicle beyond generated packages.** A store the compiler consults per method instance before inferring would need no load step at all, only a cost per hit. It is a larger Julia change (serializing single CodeInstances with native code). Optional.
3. **Identity of a dev'd package:** a hash of its source files is exact. An image's build id is simpler but invalidates on every rebuild of a dependency.

## 4. Experiments

- **E-188 (done):** the origins hold.
- **Next, Phase A, minutes once built:**
  - C and D off-workload, against no cache;
  - the same cache in a second environment that differs by one unrelated package's version: entries kept, and the session's time;
  - the load against E-187's parts.
- **Would change the design:** an entry valid by origins that Julia's validation rejects in Phase A, a sign that origins miss something (a fact through a plain callee, an extension), and the reason to look before Phase B.
