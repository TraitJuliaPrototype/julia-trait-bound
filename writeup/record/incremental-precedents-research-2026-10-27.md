# Precedents for identifying compiled code by what it used

> **Research of its date.** This page records what the research found on 2026-10-27. It serves [W-66's plan, §5b](../plans/2026-10-27-facts-keyed-cache.md#5b-an-open-choice-after-e-194-the-identitys-grain): a cache entry of code compiled by facts identified by fingerprints (F1 its own method, F2 its facts and callees' inferred results, F3 layouts), not by its dependencies' build ids. Its statements about other systems stand as of this date. Its statements about our design describe the plan of this date; the references and the plan win where they differ.

Research of 2026-10-27 (W-66), by one agent with web access and the local Julia tree.

**How to read the citations.**
- **Verified:** the agent opened the source and read the quoted or paraphrased text. Source files were fetched from the projects' main branches on 2026-10-27. Line numbers are as of that fetch; the note or function name is the stable pointer.
- **Not verified:** recalled, inferred from verified text, or from a secondary source. Each such claim is marked *(not verified)* or *(inference)*.
- The GHC wiki page on recompilation avoidance (`gitlab.haskell.org/ghc/ghc/-/wikis/commentary/compiler/recompilation-avoidance`) refused automated access. GHC's source notes and user guide were read instead.

**In one paragraph.** Identifying compiled code by fingerprints of what it used is standard practice inside one compilation unit or one package: GHC, rustc, Swift, Scala's Zinc and Salsa all do it, and the build-systems literature names it a *verifying* or *constructive trace with early cutoff*. Across packages, the same systems fall back to coarser identities: GHC records only a module's ABI hash for another package's module; rustc makes every query on an upstream crate depend on that crate's whole hash and recovers the grain by early cutoff on each query's result; Swift rebuilds a whole module when an imported module changes unless "incremental imports" are on. Julia's package images are the coarsest point: an image names each dependency by build id. The closest precedent for our *stakeholders* is GHC: a non-orphan instance is fingerprinted with its class or its type, so a module's usage of the class or the type covers it, and only orphan modules need a separate list. Our design transplants that split to multiple dispatch, at the grain of one concrete signature.

## 1. GHC: interface fingerprints and usages

**What it does.**
- **Fingerprints per declaration and per interface.** "GHC calculates a fingerprint (in fact an MD5 hash) of each interface file, and of each declaration" and "keeps in every interface file a list of the fingerprints of everything it used when it last compiled the file." It recompiles when "the fingerprints on the things it needs this time" differ from last time. *Verified:* GHC User's Guide, [Separate compilation, "The recompilation checker"](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/separate_compilation.html).
- **A declaration's fingerprint covers what it refers to.** Declarations are hashed in dependency order, and a referenced `Name` is serialized as its fingerprint, which "ensures that the fingerprint of a decl changes if anything in its transitive closure changes." *Verified:* `compiler/GHC/Iface/Recomp.hs`, Note [Fingerprinting IfaceDecls] (line 1109), [source](https://github.com/ghc/ghc/blob/master/compiler/GHC/Iface/Recomp.hs).
- **Inlining enters the fingerprint only where a definition is exposed.** The ABI of a declaration includes "the declaration itself, as exposed to clients. That is, the definition of an Id is included in the fingerprint only if it is made available as an unfolding in the interface." *Verified:* same file, Note [The ABI of an IfaceDecl] (line 1632), item (b).
- **Instances are fingerprinted with their owners.** The same note lists, as part of a declaration's ABI, "(e) for classes: instances, fixity & rules for methods" and "(f) for datatypes: instances, fixity & rules for constrs". *Verified:* same note.
- **Usages.** For a module of the home package, a usage records the module's ABI hash and `usg_entities`, "Entities we depend on, sorted by occurrence name and fingerprinted". For a module of another package, a usage records only the module's ABI hash. *Verified:* `compiler/GHC/Unit/Module/Deps.hs`, `data Usage` (line 323), [source](https://github.com/ghc/ghc/blob/master/compiler/GHC/Unit/Module/Deps.hs).
- **Across packages, the module grain.** "We only track the ABI hash of package modules, rather than individual entity usages, so if the ABI hash changes we must recompile. This is safe but may entail more recompilation when a dependent package has changed." *Verified:* `Recomp.hs`, `checkModUsage` for `UsagePackageModule` (line 776).
- **ABI hash versus interface hash.** `mi_iface_hash` is "A hash of the whole interface"; `mi_mod_hash` is the "Hash of the ABI only". Besides them the interface carries an export hash, an orphan hash and an "orphan-like" hash. The interface hash is used where anything in the interface matters, for bytecode under Template Haskell. *Verified:* `compiler/GHC/Unit/Module/ModIface.hs`, `IfaceAbiHashes` (line 176) and `mi_iface_hash_` (line 266), [source](https://github.com/ghc/ghc/blob/master/compiler/GHC/Unit/Module/ModIface.hs); `Deps.hs`, `UsageHomeModuleBytecode`.
- **Orphans need a separate list.** An instance is an orphan when it sits in neither its class's module nor a module of a type in its head. "GHC identifies orphan modules, and visits the interface file of every orphan module below the module being compiled. This is usually wasted work, but there is no avoiding it." *Verified:* User's Guide, [Separate compilation, "Orphan modules and instance declarations"](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/separate_compilation.html). The interface keeps `dep_orphs`, the "Transitive closure of orphan modules (whether home or external pkg)". *Verified:* `Deps.hs` (line 107). A change to an orphan elsewhere must reach modules two imports away (Note [Take into account non-home package orphan modules], `Recomp.hs` line 1546; Note [Orphan-like hash], line 1012).
- **A caution.** Fingerprinting a recursive group wrongly made two mutually recursive types share a fingerprint: "Surprisingly, this bug (#18733) lurked for many years before being uncovered." *Verified:* Note [Fingerprinting recursive groups] (line 1130).
- *(not verified)* Installed packages carry an ABI hash of their own (`ghc-pkg`'s `abi` field), and Cabal rebuilds dependents when it changes. This is the package-level analogue of Julia's build ids.

**How it maps to our design.**
- GHC fingerprints declarations (types, functions, classes with their instances) and records per-entity usages. Our F1 to F3 fingerprint a method's lowered code, the stakeholders' methods at each fact, callees' inferred results and layouts, per CodeInstance.
- **Unfoldings ↔ inlining.** GHC hashes a function's body into its ABI only where the body is exposed for inlining. Our F2 hashes the stakeholders' methods' lowered code at every fact, whether or not the call was inlined.
- **Instances with their owners ↔ stakeholders.** A non-orphan instance changes the fingerprint of its class or its type, so a usage of either sees it. Our stakeholders are the owners of a fact's function and of the types in its signature; their methods enter F2. A pirate's method is outside both, as an orphan instance is outside its class's and type's interfaces.
- **Orphan modules ↔ the candidate index.** GHC keeps the transitive list of orphan modules and visits each. Our index keeps, per function, the methods from outside the stakeholders.
- **Cut-off.** A module recompiles only when a used entity's fingerprint changed. Across packages GHC cuts off at the module's ABI hash, not at the entity.

**What we can take, and where facts differ.**
- **Take: hash a callee's code only where it is inlined.** GHC's rule (b) suggests splitting F2: for a fact whose call was inlined, the selected method's lowered code; for a fact whose call stays a call, the selected method's identity and its callee's inferred result. This would keep an entry when a stakeholder edits the body of a method that the entry only calls. A suggestion, not part of the plan.
- **Take: the recursive-group caution.** Methods whose edges form a cycle need a fingerprint that captures the structure inside the cycle (Note [Fingerprinting recursive groups]); E-193's cases do not test that.
- **Differ: the grain of an instance's dependency.** GHC hashes all instances of a class with the class: a new instance anywhere in the class's module changes every user's fingerprint. A fact names one concrete signature, so a stakeholder's method that does not intersect it could be left out of the fingerprint. The plan hashes all the stakeholders' methods of the function; a narrowing to intersecting methods is possible.
- **Differ: across packages.** GHC is coarse across packages (module ABI hash). Our design aims at the per-fact grain across packages, which is where Julia's cascade (E-194) lives.

## 2. rustc: the query system, red-green, fingerprints

**What it does.**
- **Queries and their graph.** The compiler saves "the results of all the queries that we do, as well as the query DAG". *Verified:* rustc dev guide, [Incremental compilation](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html), "The basic algorithm".
- **Red-green.** Nodes are green if "we were able to prove that its cached result is still valid"; `try_mark_green` marks a node green when all its inputs are green; a red input forces re-execution. *Verified:* dev guide, [Incremental compilation in detail](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html).
- **Fingerprints and early cutoff.** "Each time a new query result is computed, the query engine will compute a 128 bit hash value of the result." After re-execution the compiler "can check if a result has actually changed"; a result with the same fingerprint is marked green and its dependents need not run. The dev guide does not use the term "early cutoff". *Verified:* same page.
- **Stable hashing.** Results are hashed "in a stable way": session-local identifiers are replaced by stable ones, for example a `DefPathHash`, "a 128-bit hash value of the `DefPath`", in place of a `DefId`. *Verified:* same page.
- **Projection queries as firewalls.** Small queries that read part of a large one stay green when the large one changes elsewhere: "These projection queries allow for building change propagation “firewalls”". *Verified:* same page.
- **The crate's SVH.** The Strict Version Hash hashes "the HIR nodes", "All of the upstream crate hashes", the source file names and tracked flags. "The crate loader will skip any crates that have the wrong SVH." *Verified:* dev guide, [Libraries and metadata](https://rustc-dev-guide.rust-lang.org/backend/libs-and-metadata.html), "Strict Version Hash".
- **Across crates.** Every query answered from an upstream crate's metadata first calls `crate_hash` "in order to register a dependency on the crate metadata". *Verified:* `compiler/rustc_metadata/src/rmeta/decoder/cstore_impl.rs`, macro `provide_one!` (line 149), [source](https://github.com/rust-lang/rust/blob/master/compiler/rustc_metadata/src/rmeta/decoder/cstore_impl.rs). `crate_hash` is `eval_always`. *Verified:* `compiler/rustc_middle/src/queries.rs`, `query crate_hash` (line 2060), [source](https://github.com/rust-lang/rust/blob/master/compiler/rustc_middle/src/queries.rs).
- *(inference)* So an upstream crate's new SVH turns its metadata queries red. Each is re-executed (a decode from metadata), its result is fingerprinted, and a result that did not change is green again. The SVH cascades through the crate graph, but the downstream crate's work is cut off at each upstream item it read.
- *(not verified)* rustc's incremental cache is per crate and per session directory; it is not shared between environments.

**How it maps to our design.**
- A query's key and its fingerprinted result ↔ an entry and the fingerprints it records. `try_mark_green` ↔ checking the recorded fingerprints at load.
- The upstream SVH ↔ Julia's build id: both hash the dependency closure and both cascade.
- The early cutoff on extern queries ↔ our §5b: the build id is allowed to change, and the entry survives when every item it read is unchanged.
- Projection queries ↔ facts: a fact is a projection of the method table (the methods at one concrete signature) that stays unchanged when the function gains methods elsewhere.

**What we can take, and where facts differ.**
- **Take: the two-step check.** A cheap closure identity first (rustc's SVH, our build ids), and the per-item fingerprints only when it changed. The plan's index already plays this role for candidates; the same order fits the fingerprints.
- **Take: stable hashing.** Fingerprints must not contain session addresses or world ages. rustc's `DefPathHash` is the model: a method named by its module path and signature, a type by its path.
- **Differ:** rustc's queries are its own compiler's queries, fixed by the compiler. Our dependencies are dispatches in a language whose method table any package can extend; the facts rule is what makes them finite and concrete.

## 3. Swift: fine-grained dependencies and fingerprints

**What it does.**
- **Provides and depends.** "Swift's intra-module dependency analysis is based on a "provides" / "depends" system". Kinds: top-level names, nominal types ("use of a particular type, in any way, and declarations that change the "shape" of the type"), members, and dynamic lookup ("use of a specific member accessed through `AnyObject`"). "The golden rule of dependency analysis is to be conservative." *Verified:* [`docs/DependencyAnalysis.md`](https://github.com/swiftlang/swift/blob/main/docs/DependencyAnalysis.md).
- **External dependencies, coarsely.** Imported modules form a special set; "if an external dependency changes, everything in the module is rebuilt." *Verified:* same document.
- **Interface and implementation nodes.** Each entity is "a pair of nodes. One node represents the "implementation." If the implementation changes, users of the entity need not be recompiled. The other node represents the "interface."" *Verified:* `include/swift/AST/FineGrainedDependencies.h`, comment above `enum class DeclAspect` (line 313), [source](https://github.com/swiftlang/swift/blob/main/include/swift/AST/FineGrainedDependencies.h).
- **Fingerprints.** "The frontend records in the fingerprint, all of the information about an entity, such that any uses need be rebuilt only if the fingerprint changes." Where a declaration has no fingerprint, the file's interface hash stands in: "a product of all the tokens that are not inside of function bodies." *Verified:* same file, `class DepGraphNode` (line 576).
- **Type-body fingerprints.** An iterable declaration context (a type or extension body) has `getBodyFingerprint()`, "a hash of all tokens in the body for dependency analysis". *Verified:* `include/swift/AST/DeclContext.h` (line 1095), [source](https://github.com/swiftlang/swift/blob/main/include/swift/AST/DeclContext.h).
- **Across modules: "incremental imports".** The flag `-enable-incremental-imports` enables "cross-module incremental build metadata and driver scheduling for Swift modules". *Verified:* `include/swift/Option/Options.td` (line 1818). The driver keeps `fingerprintedExternalDependencies` and, for a changed `swiftmodule`, reads its dependency graph to find the nodes that use a changed external declaration; without a fingerprint it falls back to invalidating every user ("No fingerprint in swiftmodule"). *Verified:* swift-driver, [`Sources/SwiftDriver/IncrementalCompilation/ModuleDependencyGraph.swift`](https://github.com/swiftlang/swift-driver/blob/main/Sources/SwiftDriver/IncrementalCompilation/ModuleDependencyGraph.swift), `collectUntracedNodes` and `findNodesInvalidated` (lines 306–460).
- *(not verified)* Whether incremental imports are on by default in current toolchains.

**How it maps to our design.**
- Swift's grain is a name (top-level, member) or a type body, per source file. Ours is a concrete signature, per CodeInstance.
- Interface versus implementation ↔ a callee's inferred result versus its code: a change that leaves the interface (for us, the inferred result) alone does not reach callers.
- A type body's fingerprint ↔ F3, the layout of a type read.
- A dependency by dynamic lookup through `AnyObject` is a dependency on any member of that name anywhere. Plain Julia's dispatch at an abstract signature is the same kind of dependency; the facts rule excludes it from code compiled by facts.

**What we can take, and where facts differ.**
- **Take:** the fallback rule. When a fingerprint is missing, Swift invalidates every user. An entry whose fingerprints cannot be computed (an image without the hashes, plain code reached) should be treated as invalid, never as valid.
- **Take:** the interface/implementation split is the same suggestion as GHC's unfoldings (§1).
- **Differ:** Swift's dependencies are by name, so a new overload of a name invalidates every user of the name. A fact names a signature, and only the stakeholders can add a method at it (or a pirate, which the index catches).

## 4. Salsa: backdating, early cutoff, durability

**What it does.**
- **Revisions.** "The Salsa database always tracks a single revision. Each time you set an input, the revision is incremented." For each input it tracks the revision in which it last changed. *Verified:* Salsa book, [The red-green algorithm](https://salsa-rs.github.io/salsa/reference/algorithm.html).
- **Backdating.** In a new revision a tracked function checks whether its inputs changed; if they did, it re-executes, and "If it's the same as last time, we can backdate the result", "meaning that we say that, even though the inputs changed, the output didn't." *Verified:* same page.
- **Durability.** "Durability specifies the probability that an input's value will change." For each durability Salsa tracks the revision in which an input of that durability last changed; a result that read only high-durability inputs is valid when no such input changed, "avoiding the need to traverse the input edges one by one". The book's examples of high-durability inputs: the standard library, inputs the user is not editing. *Verified:* Salsa book, [Durability](https://salsa-rs.github.io/salsa/reference/durability.html), and the algorithm page.
- *(not verified)* rust-analyzer, Salsa's main user, marks library source roots as high durability.

**How it maps to our design.**
- Backdating is early cutoff by value equality, in memory. Our fingerprints are early cutoff by hash, across sessions.
- Durability ↔ the store's layering by origin. An entry whose facts touch only the system image's standard libraries can be checked by the system image's identity alone.

**What we can take.**
- **Take: durability classes.** Record per entry the highest-churn origin among its facts (the system image, registered releases, dev'd packages). At load, an entry whose classes all match the session's identities is valid without hashing its facts. This bounds the check's cost, which the plan does not yet state.

## 5. Unison: content-addressed definitions

**What it does.**
- "Each Unison definition is identified by a hash of its syntax tree." Its dependencies "are replaced by their hashes"; "names are just separately stored metadata that don't affect the function's hash." *Verified:* [The big idea](https://www.unison-lang.org/docs/the-big-idea/).
- "the definition associated with a hash never changes", so Unison can "parse and typecheck definitions once, and then store the results in a cache which is never invalidated." *Verified:* same page.
- *(inference)* A definition's hash includes its dependencies' hashes, so an edit gives every transitive dependent a new hash; a dependent is reused only under its new identity once it is updated.

**How it maps to our design.**
- Unison's identity is the transitive closure of definitions, by content. That is a deep trace (§7): no cutoff at an unchanged intermediate result.
- Our F1 is Unison's idea for one method: its lowered code, not its package's version.

**Where facts differ.**
- Unison has no open method table: a reference is to a fixed definition. Julia's call names a function whose methods any package may extend, so a fact must fingerprint the set of methods that can answer it (F2), not one definition.
- Our F2 uses a callee's inferred result, not its hash. So an edit to a callee that keeps its inferred result does not invalidate a caller that did not inline it, which Unison's identity would.

## 6. Nix content-addressed derivations; Bazel's action cache

**Nix: what it does.**
- Input-addressed paths are computed from the build's inputs. Content-addressed derivations' outputs are named by what they contain: "we derive them from the output (the produced store path)." *Verified:* [RFC 0062](https://github.com/NixOS/rfcs/blob/master/rfcs/0062-content-addressed-paths.md), "Detailed design".
- The stated motivation: "setting some critical derivations as content-addressed can lead to some substantial build cutoffs." *Verified:* RFC 0062, "Motivation".
- A derivation is *resolved* by replacing every input derivation by the path it was realised as; "`resolved` is (intentionally) not injective". *Verified:* same RFC.
- *(inference)* So a dependency rebuilt to identical content resolves its dependents to the same derivation, and they are not rebuilt: early cutoff.
- Realisations, the map from a derivation output to its path, must be signed, since no hash links the two. *Verified:* same RFC, "Trust model" discussion.

**Bazel: what it does.**
- The remote cache is "a map of action hashes to action result metadata" and "A content-addressable store (CAS) of output files." *Verified:* [Remote caching](https://bazel.build/remote/caching), "Overview".
- An `Action` is identified by the digest of its command and `input_root_digest`, the digest of a Merkle tree of its input files. *Verified:* Remote Execution API, [`remote_execution.proto`](https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/execution/v2/remote_execution.proto), `message Action` (line 674).
- *(inference)* An upstream action that produces identical bytes gives its dependents the same input root, hence the same action digest and a cache hit. "Build Systems à la Carte" lists Bazel as supporting early cutoff (Table 1, §7 below).
- **Interface jars.** Bazel compiles Java against interface jars, so that "unnecessary recompilation is avoided when upstream changes don't affect the interface." *Verified:* [`third_party/ijar/README.txt`](https://github.com/bazelbuild/bazel/blob/master/third_party/ijar/README.txt), "Rationale".

**How it maps to our design.**
- Julia's build ids are input-addressed in Nix's sense: they change when any input in the closure changes, whatever the output.
- Our fingerprints are content-addressed: the inputs are the hashed values of what the entry read.
- Bazel's ijar is GHC's ABI hash at the build-system level: depend on a projection of the upstream artifact, not on the artifact.

**What we can take.**
- **Take: the trust split.** Nix separates the store from the trust in realisations. A shared store of entries (across environments, or across users) needs the same: an entry is evidence (the plan's M5), and its validity is decided by the fingerprints recomputed in the session, never by the entry's own claim.
- **Take: the projection.** Our F3 (layouts) and the callee's inferred result are the "interface jar" of a dependency.

## 7. "Build Systems à la Carte": the vocabulary

**Source.** Andrey Mokhov, Neil Mitchell, Simon Peyton Jones, "Build Systems à la Carte", Proc. ACM Program. Lang. 2, ICFP, Article 79, September 2018, [doi:10.1145/3236774](https://doi.org/10.1145/3236774), [PDF](https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems.pdf). *Verified:* the PDF's text.

**The terms.**
- **Minimality** (Definition 2.1): "A build system is minimal if it executes tasks at most once per build and only if they transitively depend on inputs that changed since the previous build." *Verified:* §2.1.
- **Early cutoff** (§2.3): "When it executes a task and the result is unchanged from the previous build, it is unnecessary to execute the dependent tasks". Make and Excel lack it; Shake and Bazel have it (Table 1). *Verified.*
- **Verifying traces** (§4.2.2): record "the values/hashes of dependencies used last time, and if something has changed, the key is dirty and must be rebuilt". Shake uses them. *Verified.*
- **Constructive traces** (§4.2.3): a verifying trace that "additionally stores the resulting value", which can be shared with other users: cloud builds. Bazel and CloudBuild use them. *Verified.*
- **Deep constructive traces** (§4.2.4): verify "by only looking at the terminal input keys, ignoring any intermediate dependencies". They "cannot support early cutoff", other than at n levels; for n ≥ 2 they require deterministic tasks. Buck and Nix use them. *Verified* (Table 2 and §4.2.4).
- **Self-tracking** (§6.5): a task is rebuilt when the task itself changes, as an Excel cell when its formula changes. Systems that embed tasks in a full programming language face "the challenge of implementing equality on arbitrary task functions". *Verified.*

**How it maps to our design.**
- **The closure's build ids are a deep constructive trace.** The entry is keyed by the hashes of its terminal inputs (every image in the closure, transitively), so no intermediate result can cut off. E-194's 86–90% is the cost the paper predicts.
- **The fingerprints are a constructive trace with n = 1.** Each entry records the hashes of what it read directly (its facts' methods, its callees' inferred results, its types' layouts) and stores the compiled code. Early cutoff happens at every callee whose inferred result is unchanged.
- **F1 is self-tracking.** The task's own definition (the method's lowered code) is one of its recorded inputs. Julia gives a cheap equality on "task functions": the lowered code.
- **Minimality** requires the recorded dependencies to be complete. That is G2 ([facts §2.2](../reference/facts.md#22-g2-stable-caches)): code compiled by facts depends on the method table only through its facts. For plain code, the set of dispatches that could change it is not finite (dispatch at abstract signatures), and a trace could not be complete.

## 8. What Julia itself does

**What it does.**
- **When a cache is stale.** A package is recompiled "if you update the module's dependencies or change its source code". "Dependencies are modules it imports, the Julia build, files it includes, or explicit dependencies declared by `include_dependency(path)`"; included files are compared by size and content hash, `include_dependency` files by modification time; compile-time preferences count too. *Verified:* Julia manual, `doc/src/manual/modules.md`, "Module initialization and precompilation" (the tree at `julia-1.13/`, 1.13.2; upstream [docs](https://docs.julialang.org/en/v1/manual/modules/#Module-initialization-and-precompilation)).
- **Dependencies by build id.** A cache file names each dependency with a build id, and loading rejects it "because it provides the wrong build_id" when the loaded dependency differs. *Verified:* `base/loading.jl`, `stale_cachefile` (line 4343 in `julia-1.13/`, commit 41d199c557). Flags that change code generation (`-g`, `--check-bounds`, `--inline`, `-O`) must match. *Verified:* `doc/src/devdocs/pkgimg.md`, "Flags that impact package image creation and selection".
- **Within the build id, the method table is checked per edge.** At load, `insert_backedges` re-verifies each CodeInstance's edges; `verify_call` checks "that these edges intersect with the same methods as before", comparing `ml_matches` at the edge's signature with the recorded methods. *Verified:* `Compiler/src/reinfer.jl`, `verify_method` (line 162) and `verify_call` (line 474), in `julia-1.13/`.
- **In the session, invalidation per signature.** "when a new method is defined, old compiled methods that made now-incorrect assumptions get invalidated." *Verified:* T. Holy, J. Bezanson, J. Nash, ["Analyzing sources of compiler latency in Julia: method invalidations"](https://julialang.org/blog/2020/08/invalidations/), 2020.
- **The cascade as users meet it.** A Discourse thread of 2026-08-31 quotes Pkg's warning that "153 dependents of these packages may trigger further precompilation", and explains a second image of a package for a different dependency version by inlining: "something as simple as a `B` function being automatically inlined into an `A` function requires this." *Verified* (secondary: a user forum): ["Why does everything keep precompiling?"](https://discourse.julialang.org/t/why-does-everything-keep-precompiling/139109).
- **No finer-grained proposal found.** The agent found no Julia issue or design document proposing to key package images, or parts of them, by what their code used. A search was made; absence is *not verified*.

**How it maps to our design.**
- Julia is a deep trace for code content (build ids, transitively) and a verifying trace for dispatch (edges re-verified at load by signature). Its dispatch check is already fine-grained; its content check cascades.
- Our §5b keeps Julia's edge check (the index restricts it to candidates) and replaces the build-id identity by content fingerprints of the same edges.

**Where facts differ.**
- Julia's edge check must run over all edges, since any package may have added a method. Facts with stakeholders let the check skip every fact whose function has no candidate, which is most of them (E-194: 11 of 1,835 entries hit a candidate).
- Julia cannot drop build ids for plain code: an edge of plain code may sit at an abstract signature, and its inferred code may have read anything. The fingerprint identity is sound only for code under G2.

## 9. Who may define a method, as a bound on what to watch

**What exists.**
- **GHC: the closest precedent.** Non-orphan instances are fingerprinted with their class or type (§1: Note [The ABI of an IfaceDecl], items (e) and (f)). A module that uses a class or a type already depends on its fingerprint, so its instances need no separate dependency. Only orphan instances need their own list (`dep_orphs`) and their own hash. *Verified* (§1). The user's guide states the cost of orphans: "This is usually wasted work, but there is no avoiding it." *Verified.*
- **Rust's orphan rule.** "a trait implementation is only allowed if either the trait or at least one of the types in the implementation is defined in the current crate"; it "prevents conflicting trait implementations across different crates and is key to ensuring coherence", and lets "library authors add new implementations to their traits without fear that they'll break downstream code." *Verified:* The Rust Reference, [Implementations, "Trait implementation coherence" and "Orphan rules"](https://doc.rust-lang.org/reference/items/implementations.html).
- *(not verified)* The agent found no rustc documentation or source comment that uses the orphan rule to narrow incremental dependencies. rustc's trait selection reads impls through queries, and their results are fingerprinted like any other.
- **Scala's Zinc: the problem without a bound.** Name hashing tracks used names, but implicit resolution escapes it: an analysis of which implicit is chosen "gets us very quickly to the implementation complexity of Scala's type checker"; inheritance dependencies "are never marked as irrelevant." For classes from jars, "Scala compiler does not track origin of Symbols derived from binary files", and a heuristic maps a class name to its classpath entry. *Verified:* sbt documentation, [Understanding Incremental Recompilation](https://www.scala-sbt.org/1.x/docs/Understanding-Recompilation.html), "Name hashing" and its limitations.

**How it maps to our design.**
- Our Lemma O ([facts.md](../reference/facts.md)): a method that applies at a concrete signature and is no pirate is defined by a stakeholder of that signature. This is GHC's split for multiple dispatch: stakeholders' methods are fingerprinted with the fact (F2), as instances with their class and type; pirates are indexed (the candidate index), as orphan modules are listed.
- Zinc's implicit problem is the problem of plain Julia: which method answers a call depends on definitions anywhere. The facts rule and Lemma O make it a finite, owned set.

**Where facts differ.**
- GHC's owners are one class and the types in one instance head. Our stakeholders of a concrete signature are the owner of its function and the owners of every type in it at any depth, and of their supertypes ([glossary, Stakeholder](../glossary.md#stakeholder)). The set is larger, but it is computed from the signature alone.
- GHC hashes every instance of a class together. A fact can hash only the stakeholders' methods of one function, or only those that intersect its signature (§1).
- Rust's rule refuses orphans at compile time. Julia admits pirates; the index catches them at load, and strict mode refuses those that win (the plan's §2).

## The precedents at a glance

| System | What it fingerprints | Grain | Across packages | Cut-off | Who may add a method |
|---|---|---|---|---|---|
| GHC | declarations (with exposed unfoldings, a class's and a type's instances) and interfaces | entity in the home package | module ABI hash | at an unchanged used entity's or module's fingerprint | owner of class or type; orphans listed (`dep_orphs`) |
| rustc | every query's result (stable hashing) | query | crate SVH, then each metadata query's result | at an unchanged query result (red-green) | orphan rule; not used by incremental *(not verified)* |
| Swift | declarations' interface and implementation, type bodies, file interface hash | name, member, type body | whole module, or per external declaration with incremental imports | at an unchanged interface fingerprint | anyone (retroactive) |
| Scala Zinc | API per name bucket | name | class name to classpath entry (heuristic) | at an unchanged name hash; implicits and inheritance escape | anyone |
| Salsa | tracked functions' results (by equality) | tracked function | — (one database) | backdating; durability skips verification | — |
| Unison | definitions' syntax trees, dependencies by hash | definition | the same (no packages in the hash) | none: a dependency's edit gives a new identity | — (no open method table) |
| Nix CA | derivation outputs' content | derivation | the same | resolved derivations equal | — |
| Bazel | actions (command and input Merkle tree); ijar for Java | action | the same | identical outputs give identical input roots | — |
| Julia | package images by build id, dependencies by build id; edges re-verified at load | package (content); signature (dispatch) | build id of every dependency, transitively | none for content; per edge for dispatch | anyone; pirates admitted |
| Ours (§5b) | own lowered code; stakeholders' methods at each fact; callees' inferred results; layouts read | CodeInstance, concrete signature | the same, per fact | at an unchanged fact, inferred result or layout | stakeholders (Lemma O); others in the candidate index |

**The three closest precedents.**
1. **GHC:** fingerprints per declaration with usages; instances fingerprinted with their owners and orphans listed separately. It is the only precedent found for using who may define a method to bound the analysis.
2. **rustc:** fingerprinted query results with red-green early cutoff; across crates, a closure hash (SVH) refined by early cutoff on each upstream item read. It is the model for a closure identity first and item fingerprints second.
3. **"Build Systems à la Carte":** the vocabulary that names the move from the plan's §2 to §5b: from a deep constructive trace (build ids) to a constructive trace with early cutoff (fingerprints), shared across environments as a cloud cache.

## What is new in our design

The others fingerprint what code used, but they have to approximate what it used. GHC hashes all instances of a class together and falls back to module hashes across packages. Swift and Zinc track names, and lose precision on overloads, implicits and inheritance. rustc tracks its own queries exactly but cascades across crates through the SVH, recovering the grain only by re-running each upstream query. Julia's plain code depends on dispatch at abstract signatures, an unbounded set, so it must be keyed by its dependencies' build ids. The facts rule removes the approximation: code compiled by facts depends on the method table only at concrete signatures (G2), and Lemma O bounds who can change each such dependency to its stakeholders plus pirates. So a fact's fingerprint is exact (the stakeholders' methods of one function, or only those at its signature), the rest of the world is reduced to a candidate index that is empty for most functions, and the identity can be per CodeInstance across packages, where every precedent found falls back to a whole module's or crate's hash.
