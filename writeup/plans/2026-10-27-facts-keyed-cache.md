# The cache across sessions keyed on facts and their origins

Status: **adopted in part**: the identity by fingerprints (§5b; the user, 2026-10-27); validity replaced by Julia's validation of edges, with fingerprints for content (the user, 2026-10-28, open issue 80; [the store's note](2026-10-28-facts-cache-store.md)). Revision 2 (2026-10-27, mine; W-66): after [its fresh-eye review](../reviews/2026-10-27-facts-keyed-cache.md) (§6) and the user's suggestion on pirates outside strict mode. Not normative. Builds on [the exploration](../explorations/facts-keyed-cache.md). The environment-keyed cache (W-62) is retired ([alternatives](../design/alternatives.md)).

## 1. What it is for

The user (2026-10-27): "Is there a cleaner design that only catches trait/facts code and doesn't key on the environment but on the facts and their origins?"; "Let's retire the experimental cache and add this cache to the Todo list."; "Take up strict mode with W-66"; and "Outside of strict mode, when a pirate wins, could we use the strict mode machinery to mark cached methods as invalidated for this session only?"

Code compiled by facts depends on the method table only through facts at concrete signatures ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). So its validity can be stated relative to the packages it was compiled against, and to the methods from outside them, not to the whole environment.

## 2. The design

**An entry.**
- A CodeInstance of owner `:facts`, in the product setting.
- Compiled by a session, naming no type or function of the session.
- Named by its method and its specialization, with its first-call checks.
- Kept only if its own code and its callees' were compiled by facts. An entry that reaches plain code (the compiler's, plain answers of `return_type`) is excluded, or validated by the walk (M3).

**Its dependency closure:**
- the packages whose images its code could depend on: every package reached through its edges, transitively through callee CodeInstances;
- its signature's types and their supertypes;
- direct edges' functions and argument types;
- bindings and folds;
- all of these closed under package dependencies.

A package can only name its dependencies, so the closure covers macros, `@eval` over their data and struct layouts (the review's B1, B2).

**An entry's identity:**
- the **build ids** of the images in its closure, with the active extensions among them;
- the system image, the code generation's flags and the setting (m3).

A package's version or tree hash is not enough: a dependency's macro or layout changes the code without changing either, and images link to their dependencies by build id (B2).

**Validation at load: a session index of candidate methods** (the review's B4, and the user's suggestion):
- **The candidates** for an entry: every active method in the session that no image in its closure defined, plus the closure's methods that are inactive or deleted. These are pirates, extensions activated by other packages, standard libraries loaded later, methods evaluated into a module from outside, joint owners' and delegates' methods, and definitions at run time (Revise, `__init__`, the prompt).
- **The index:** the session keeps the candidates by function, from each image's own record (made at its build) and from the definition hook. Most functions have none.
- **An entry with identical closure build ids** is valid without an edge walk, except where a candidate on a fact's function intersects the fact's signature. Only those facts are walked; a walk that fails marks the entry invalid for this session only. The store keeps it.
- **Bindings and folds** are checked as today: the binding's partition; folds evaluated at load ([compiler §4.4](../reference/compiler.md#44-compilerfold_call)) (M4).
- **Strict mode is policy, not validity** (the user's decision to take it up with W-66 stands):
  - a candidate that would win at a fact of a package image raises an error in strict mode (facts §10.3's intended design);
  - in a cache entry it discards the entry for the session. A cache entry is evidence, not a contract (M5).
- **The same index validates the packages' own images:** open issue 73's lever, which needs no store.

**The first-call checks kept:** a kept check certifies that the worker's first-call check passed against the same closure (M4).

**The store:** one per Julia build and setting, in the depot, shared by every environment. An entry is usable in any session whose closure images have its build ids. A manifest change invalidates the entries whose closure contains a changed package or a dependent of one, since a new version rebuilds its dependents (M1).

**The vehicle:** after the index, and without a fixed cost per part (M2). Two options:
- sections of one image;
- a lookup per method instance before inference.

Generated packages per origin set would cost about 8 ms a part (E-187), and C has 213 origin sets.

**What it does not keep:** plain code. Its share in seconds is to be measured (M6, E-194). In D after W-63 the session compiled 95 facts and 475 plain CodeInstances.

## 3. The order

1. **E-193:** the identity and the index, by construction (minutes, no Julia change).
2. **E-194:** the closure and the index at scale (D and a valid C, minutes).
3. **Strict mode's intended design (F-6), with no store:** [its own note](2026-10-28-strict-mode-on-facts-code.md). The index for package images, open issue 73's lever, is not built now: its gain is at most about 0.1–0.15 s of C's load ([PE-8](../record/performance-explorations.md)).
4. **The store, with its vehicle.**

## 4. Experiments

- **E-188** (done; C's half invalid, a stale extension image): direct origins only.
- **E-193 (done):** all six cases caught as predicted, no false positives ([the README](../../experiments/w66/README.md)); the system image's standard libraries count as part of every closure.
- **E-193, as planned:** tiny dev'd packages, one pair of sessions per case, where E-188's origins and a version-level identity agree while a fresh compile differs:
  1. a dependency's macro changes its expansion;
  2. a dependency's struct gains a field read through the package's own type;
  3. a supertype's owner adds a method;
  4. a callee two levels down changes;
  5. the parent's extension is activated by an unrelated package's load;
  6. SparseArrays is loaded in the second session only.
  
  **Predicted:** build ids of the closure catch 1–4; the index catches 5 and 6. **Would change the design:** a case that both miss.
- **E-194 (done):** facts code is most of C's compilation; 11 of 1,835 entries hit a candidate; but a foundational package's change invalidates 86–90% of C's entries under the closure rule, since build ids cascade through dependents ([the README](../../experiments/ttfx/README.md), E-194). Hence §5b.
- **E-195 (parts 1–3 done; the README):** the fingerprints catch every change of the small cases that alters the code and keep every unused one; at scale, C's 2,143 entries keep their fingerprints across a FunctionWrappers update that the closure rule loses 90% to; 35 entries (1.6%) hit the candidate index of revision 2 in every session; compared against the candidates each entry saw at record, none does (part 4). **So the entry records its candidates, and the index flags a candidate that is new, gone or changed** (mine, from E-195).
- **E-194, as planned:** E-188's probe extended:
  - the transitive closure;
  - supertypes, direct edges' signatures, bindings and folds;
  - entries reaching another owner, flagged;
  - inference and code-generation time per owner;
  - the share each package's change invalidates under the closure rule;
  - the index's size, and how many entries hit a candidate.
  
  **Would change the design:**
  - facts code a small share of compile time (M6: then a trade-off for the user);
  - the closure rule invalidating nearly everything on a common package's update;
  - most entries hitting a candidate.

## 5b. An open choice after E-194: the identity's grain

A version update rebuilds every dependent, so the closure's build ids cascade: at SciML's scale one foundational package's change invalidates 86–90% of the entries (E-194). Two identities:
- **The closure's build ids** (now). Simple, and E-193 shows it sound on the content cases. Sharing across environments holds within an unchanged stack, which is the common case of one user's sessions.
- **Content hashes of what an entry uses:** each method in its transitive edges (its lowered code, as the image stores it, which includes macro expansions), each type's layout it reads, and the bindings and folds as now. An update that leaves those unchanged keeps the entry. It needs the hashes at record and at check, from the images, and E-193's cases 1–4 again, to show it catches them.

**Decided (the user, 2026-10-27): fingerprints, built now** ([decisions](../record/decisions.md) §5). The form, scoped by the facts rule:
- **F1, its own method:** the method's signature and its lowered code as the session holds it, which includes macro expansions.
- **F2, each fact** (an edge of the entry, where inlined callees' edges already are):
  - the stakeholders' methods of the fact's function, with their signatures and lowered code, where the stakeholders are the owners of the function and of the types in the fact's signature (facts §2.2);
  - for a callee CodeInstance, its inferred result (return and exception type, effects, constant result).
  
  A stakeholder's update that leaves that function's methods alone keeps the fact.
- **F3, layouts:** the layout of every type in the entry's signature, result and inferred code (field names, types, sizes, mutability).
- **Methods from outside the stakeholders:** the candidate index (E-193).
- **Bindings and folds:** as today.

**Precedent** ([the research](../record/incremental-precedents-research-2026-10-27.md)): GHC records per-entity usages with fingerprints and hashes a non-orphan instance with its class or its type, keeping orphans apart. These are this design's stakeholders and candidate index. rustc cuts off early on fingerprints. In "Build Systems à la Carte"'s terms, the build-id identity is a deep constructive trace, which cannot cut off early (E-194's cascade), and the fingerprints are a constructive trace with early cutoff.

**Refinements from the precedents, to test (E-195 and after):**
- **Narrow F2** to the stakeholders' methods that intersect the fact's signature, as GHC hashes an instance with its class or type. A method that does not intersect cannot change the fact.
- **Hash a callee's code only where it was inlined,** and otherwise its identity and inferred result (GHC's unfoldings, Swift's type bodies). This needs the edges to tell an inlined callee from a called one.
- **A missing fingerprint means invalid** (Swift).
- **Recursive groups** need a fingerprint scheme that terminates (GHC's bug #18733).
- **The store holds evidence only;** the session recomputes validity (Nix's trust split).
- **A fact at a vararg signature** is keyed by its recorded family signature, every arity at once, with Julia's `max_args` outside the fingerprint ([the varargs research](../record/varargs-research-2026-10-27.md), W-74).

So nothing cascades: a new version of FunctionWrappers invalidates only the entries whose facts touch its methods or layouts. The fingerprints are computed in the session, from the method table and the CodeInstances, with no Julia change. A vehicle that loads an entry against other builds of its dependencies is a separate step (package images link by build id).

## 5. What revision 1 said

Origins as direct edges' packages, identity as version and tree hash, Phase A as generated packages validated by Julia, Phase B validated by comparing origins under strict mode. The review showed the first three unsound or of little value and the fourth insufficient; see §6.

## 6. The review, and what is done with it

[The review](../reviews/2026-10-27-facts-keyed-cache.md) (fresh eyes, Opus, of revision 1):
- **B1 and B2** (origins miss stakeholders; a tree hash does not fix the code): the dependency closure with build ids (§2).
- **B3** (changes that leave every identity the same): the candidates of the index (§2).
- **B4** (Phase B cannot rest on strict mode): validation by the closure-relative index; strict mode is policy. This follows the user's suggestion (marking cached code invalid for the session only when a pirate wins) and is mine to confirm with the user through W-71's review session.
- **M1:** E-188's C half marked invalid; the closure rule's invalidation measured in E-194.
- **M2:** Phase A dropped; the vehicle after the index.
- **M3:** entries reaching plain code excluded or walked; the product setting only.
- **M4:** folds evaluated at load; the checks' meaning stated.
- **M5:** cache entries are evidence (the user's suggestion).
- **M6:** E-194 measures the plain share in seconds.
- **m1–m8:** the store key with the system image, flags and setting (m3); the rest in the text or in E-194.
