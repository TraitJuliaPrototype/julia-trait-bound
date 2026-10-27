# A cache keyed on facts and their origins

Status: **exploration** (2026-10-27, mine; open issues 72, 73, 76). Not normative. Nothing built. The cache stays experimental (the user, 2026-10-27).

## 1. The question

The user (2026-10-27): "Is there a cleaner design that only catches trait/facts code and doesn't key on the environment but on the facts and their origins?"

The cache as built (E-180) keeps both owners' code, keys it on the whole environment (manifests, preferences, the Julia build), and lets Julia validate it at load like any image's code. [Its review](../reviews/2026-10-27-cache-design.md) found the key too coarse (any manifest change empties it), the store unbounded, and nothing in the mechanism specific to traits.

## 2. What facts give

Code compiled by facts depends on the method table only through facts at concrete signatures ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). A fact can change only by:
- a **stakeholder's change:** a new version of a package that owns the function or a type in the fact's signature, or an extension that such a package's types activate;
- a **winning pirate:** a method of a package that owns neither. Strict mode refuses it ([facts §10.2](../reference/facts.md#102-strict-mode)).

So a facts CodeInstance's validity is a function of its facts' **origins**: the stakeholders' identities (package and version, or build id for a dev'd package), plus "no winning pirate". It does not depend on the rest of the environment, on the load order, or on the method table beyond those origins.

## 3. The design

**What is kept:** facts code only, of owner `:facts`: trait code and the code facts compile for it, plus the first-call checks. These are facts too: about the trait declarations and the implementations, owned by their packages. Plain code is not kept.

**The key of an entry:**
- the method and its specialization, named by the defining package's identity;
- the set of its facts' origins: for each fact the compiler relied on, the stakeholders' identities.

The compiler knows each fact when it folds it, so it can record the origins with the edges.

**Where it lives:** one content-addressed store per Julia build, shared by every environment. An entry is found by its method and specialization. It is usable wherever its origins match, so a manifest change empties nothing but the entries whose stakeholders changed. The store is grouped by origin set, the natural dependency set: an entry loads once all its stakeholders are loaded.

**Validation at load:** compare the recorded origins with the loaded packages' identities. That is a table lookup per stakeholder, with no method lookups.
- **Under strict mode:** sufficient. Pirates are refused, so no fact can change otherwise. This is open issue 73's "facts images without edge validation", applied to the cache.
- **Without strict mode:** a winning pirate could change a fact. Its facts edges are then validated as today, which is still fewer than all edges.

**Eviction:** by origin. An entry whose stakeholder version is no longer in any environment on the machine can go.

## 4. Against the cache as built

| | Built (E-180) | Keyed on facts |
|---|---|---|
| What it keeps | both owners' code | facts code and checks only |
| Key | the environment | each entry's facts' origins |
| A manifest change | empties the cache | invalidates only the entries whose stakeholders changed |
| Shared across environments | no | yes |
| Load order | Julia's validation decides | irrelevant (facts) |
| Validation at load | the full edge walk | origins compared; edges only without strict mode |
| Trait-specific | no | yes: it rests on the facts rule |
| What it needs | nothing from Julia | the compiler records each fact's origins with the edges (a Julia change); strict mode for the cheap validation |
| What it loses | — | plain code: E-175's plain twins and upstream's plain packages gain nothing |

## 5. Questions

- **Can each fact's origins be recorded cheaply?** The facts compiler names each fact's signature. The origin is the owner of the function and of each concrete type in it. Their packages are known from `parentmodule`.
- **How much of a trait world's session is facts code?** In C, facts code is 11% of what loads (open issue 73). In a whole trait world it is nearly all. The gain grows with the ports.
- **Strict mode's load cost:** its intended design checks at image validation ([facts §10.3](../reference/facts.md#strict-intended)), which this cache would share.
- **A smallest experiment:** record origins for the trait demonstrators (D) by walking each facts CodeInstance's edges after the session. Then compare the origin sets with the dependency sets E-180 grouped by. Also count how many entries one environment change (a version bump of an unrelated package) would keep.
