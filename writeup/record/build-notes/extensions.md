# Build notes: extensions

This page is in the agents' tier ([the record's index](../INDEX.md)).
It holds what the pass of 2026-11-18 over [the extensions reference](../../reference/extensions.md) took out of it: where each rule is in the code, the commits that built it, its gates, who decided it, its experiments.
The reference is the source of truth for the rule; this page is its build log, by section, in the reference's order.

### The top of the page

- **Taken from the page's text:** **Adopted** with the plan's D-14 (2026-11-15; the user, by adopting [the plan](../../plans/2026-11-15-next-iteration.md): "Have Opus agents implement the plan"). This page holds mechanisms of the design that are **Optional** ([the folder's README](../../reference/README.md#conventions-for-every-reference)): built when a measurement or a later decision asks for them. User code may not rely on what they would give. No rule and no guarantee of the other four references depends on them.

### §1 Keys: code shared among members the contract sees alike

- **Taken from the section's text:** (the user, 2026-11-11: "Keys should be considered purely a performance optimization. They can stay deferred.")
- **Taken from the section's text:** The line "Status of the whole" as it stood: Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"). A use case to investigate, traits with operations only: [open issue 147](../../open-issues.md#2-design). Four of 148 memberships in the ports share a key (E-263).

### §1.1 The key

- **The status line as it stood:** Optional. The compilation per key of a method whose result is built by `like`, per type: mine (2026-11-06). Keys' printing: mine (2026-11-06).

### §1.2 The key as a type

- **The status line as it stood:** Optional. The name `TraitKey`, beside BaseTraits' trait `Keyed`, is mine (2026-11-06). Keys computed by the runtime from memberships: mine (2026-11-06, [the work plan's review](../../../attic/writeup/plans/2026-11-06-work-plan-under-the-draft-reference.md) §6, weak point 4).

### §1.3 Calls from code compiled per key

- **The status line as it stood:** Optional; mine (2026-11-06).

### §1.4 The calling convention

- **The status line as it stood:** Optional.

### §1.5 The boxed adapter

- **The status line as it stood:** Optional.
- **Taken from the section's text:** ; W-110 measures

### §1.6 Field-offset intrinsics

- **The status line as it stood:** Optional.
