# The project's context, for an agent that starts cold

This page is in the agents' tier ([the record's index](INDEX.md)). It holds what the documents for people leave out: how the design came to its shape, in which turns, and what the user wants, with the reasons, in the user's words.

**Its rules.**
- It may hold chronology and the user's words.
- It is never the only home of a rule of the design, a number or a decision. The design is the [references](../reference/README.md); numbers are in [the evidence](../design/evidence.md); decisions are in [the decision log](decisions.md).
- Read [`CLAUDE.md`](../../CLAUDE.md) first: it holds the rules. This page explains them. How the work is done is in [the playbook](playbook.md).

**Where it comes from.** The reading of every plan, review and exploration for the documentation clean-up (W-162), kept in [the harvest notebook](harvest-2026-11.md). The documents themselves are in the attic ([its index](../../attic/README.md)).

## 1. What the project is

A design for traits in Julia, with a compile mode ("by facts") that keeps compiled code through unrelated package loads. It is built as a changed Julia, a library (TraitWorld) and demonstrators: ports of parts of three ecosystems (SciML, Makie, and DataFrames with CSV and Tables) and of NetworkDynamics.

The aim is in [the goals](../goals.md), in the user's words. In short: show that traits and facts cut compilation and recompilation, with limited downsides, better messages and a better experience compiling ahead; show a path for the ecosystem; and keep the design simple enough to teach.

The user decides the design's direction and does not review details (§3).

## 2. The eras, and why each turn was taken

Each era's documents are in the attic under the era's name. Terms of an earlier era appear in old documents; the glossary gives today's.

### Era 0: regions and seals (August to mid October 2026)

- **What it was.** A package prototype (TraitRegions), then TraitWorld on stock Julia. A "trait world" closed against ordinary code: values entered through seals, a trait named its representation, projections converted, ordinary code was reached through wrappers, doors and declared calls. Invalidation was held off by a filter that skipped invalidations judged harmless.
- **What it taught.** A mechanism that skips invalidation holds only while its premise holds, and fails silently. The closed world needed more rules at each step (seven, then four).
- **The turns inside it.** Keys replaced representations (2026-10-16; the user: "Every other language doesn't tackle representations … Do we really need this to make the caches work? Or is the only real reason we have it is to enable concreteness guarantees?"). Associated types were adopted in first-order form only.

### Turn 1: wrapping by facts (2026-10-16 and 17)

- **The user's words:** "Try to come up with a much cleaner and simpler design for wrapping Julia code that is provably correct. Don't work on the basis of the current design, but do take some of the learnings on board."
- **How it was done.** A brief with the goals, ten lessons and four test cases, and none of the mechanisms. Three agents designed from the brief alone. All three arrived at one core: compiled code depends on the method table only through facts at concrete signatures, and no invalidation is ever skipped.
- **What went:** wrappers, sealing, doors, declared calls, the filter, the rule that the trait world calls only itself.
- **What it gave:** the guarantees G1 (identical or error) and G2 (kept through unrelated loads), with proofs ([the proofs](../design/proofs.md)).
- **Strict mode** came the same week. The user: "I want to keep the option open to have strict mode, so trait code is never invalidated. If it rarely happens anyway it's cheap in terms of user friction but powerful as a guarantee." And: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error."

### Era 1: the facts mode in Julia's compiler, and the library (17 to 29 October 2026)

- **The policy moved into Julia's compiler** (sessions 28 and 29), after the first port (DataFrames, CSV, Tables) showed what the facts rule meets in real packages: calls at abstract types everywhere, each returning `Any`.
- **The framing changed.** The user (2026-10-18): "I am thinking we should work the argument from strict mode first. The fact that it will not be the default comes later." A control showed that the protection against loads belongs to the facts rule, for any code, not to traits.
- **The language of `Compiled` and `Dynamic`** (2026-10-20), worked out with the user in a day. The user: "I think all of this points to a unifying language." And on storage, the sentence that the design still rests on: "The type ODEProblem has to store the function and if compiled_for(f) is lost on storage this forces us back into the library provided switch (that already exists in SciML). We have just turned today's @nospecialize around rather than having a principled design."
- **The ports** (from 2026-10-21): NetworkDynamics first, then SciML, Makie and DataFrames on a "lean core". The method was set here. The user (2026-10-22): "The idea is to make a choice and record where the design pushes back against it and then maybe revisit either the choice or the design later. Not to get all choices right from the start." And (2026-10-28): "Remember that one purpose of the ports is to identify weak points in the design." "The guiding principle should be principled solutions. If a tweak in the trait design can enable a principled solution in the port architecture, that's the most valuable finding we can have."
- **First use against Python** (2026-10-27). The user: "With a large solid trait core that is amenable to cross session caching, there should be no reason that loading+running first simulation+plot should be slow." Three caches across sessions were designed in a week; one was built and retired. None is built now (§4).
- **The demonstrators follow the design.** The user (2026-10-21): "Remember that the Demonstrators follow the design. […] the Demonstrators already built never constrain the design."

### Turn 2: unification (28 October to 7 November 2026)

- **The user's question** (2026-10-28): "Right now Julia has two more or less distinct ways to write generic code: Multiple Dispatch on functions written for abstract types (in the case of no type annotations at all Any), and traits with the compiled/dynamic switch. I wonder whether a unified perspective is possible, where we have one way to write generics. This would probably mean that abstract types are just traits."
- **Why it was ripe.** Every port's plan had listed cases where a trait stood beside an abstract type of the same meaning.
- **How it was decided.** Quick runs on the build of the day, then a gate. The user (2026-10-29): "Okay, given the evidence, we pursue (e)." Then the premise (2026-11-06): "Unification states "Traits are AbstractTypes" From this it follows that Traits can occur everywhere AbstractTypes can, and that they are parametrized the way AbstractTypes are parametrized, including Trait{<:T} and the like. This explicitly contradicts a number of things that are currently in the reference design. It also should eliminate a lot of the reference design." And: "If the ports have to be substantially changed that is fine. They were built under old assumptions and should be considred informative rather than limitative."
- **What went:** trait objects, views, entries, workers, the kept forms of that time, trait modules as the only place for a method at a trait, most of the library.
- **What was checked first:** what the change trades against what the earlier build had achieved. The guarantees survived, since they rest on the facts rule and not on the trait machinery.
- **The references were written from the ground up** on 2026-11-06. They are today's.
- **Membership is transitive.** The user reversed a recommendation the same day: "It must be transitive. So A <: B <: C has to imply A <: C."

### Era 2: the unified build (7 to 14 November 2026)

- **Built in days,** with each night's work reviewed the next day by an independent agent at the user's word.
- **Speed was let go.** A plan to reach Python + 1 s was adopted and dropped in two days. The user (2026-11-09): "Okay the speed plan goals were too ambitious. We hereby retire all strict speed gain gates we have been working under. We still care about speed but there is no concrete goal to try to achieve, and we are more interested in principled holistic/broad gains enabled by facts and traits rather than in patching details here and there." The episode that showed it was `IO` made a trait to cure one slow step ([the lessons](../design/lessons.md), §1 and §5).
- **The goals were stated** (2026-11-10) and the work ordered by the weakest axis. Tensions between the goals are recorded, not resolved at the case: "The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected."
- **A membership invalidates as a method does** (2026-11-11), in place of "a membership invalidates nothing". The user: "on reflection it is reasonable to say that declaring membership of a type in a trait if you own neither the type or the trait is piracy." And on defining a membership as a method: "Conceptual parsimony for the user only requires implementation to behave like a method. The implementation can be whatever is simplest/cleanest/fastest."

### Turn 3: the schedule, the round, the synthesis (11 to 14 November 2026)

- **The user's schedule** (2026-11-11): "The strategy should be to build the complete prototype. Then thoroughly measure it, and then do some performance work as long as it doesn't increase the code complexity too much."
- Every open question went into one of three bins by what it blocked. When the first was empty the prototype was "conceptually complete", the build was frozen and tagged, and the measurement round ran.
- The synthesis read the evidence, the tensions and the agent's choices together. The tag is `prototype-2026-11`.

### Era 3: the next iteration (from 15 November 2026)

- A review of the conceptual design found that most tensions came from places where the design held two of something. Its first proposal: **one way to erase**. The value's own type decides what is compiled for it; a box erases; no attribute, no five steps.
- The plan is [the next iteration](../plans/2026-11-15-next-iteration.md), with decisions D-1 to D-15, built by agents the main session directs. Where it stands is in that plan's §6 and in [the state](../state.md).
- The documentation clean-up (W-162, 2026-11-18) made the unified line "the implementation" in every current document. The user: "At this point unified _is_ the implementation. The documentation should describe the intended design." And: "The baseline is plane Julia and Python, not previous iterations of the design."

## 3. What the user wants, and why

Each is a standing preference. Its rule, where it is one, is in `CLAUDE.md`.

- **Principled solutions over patches at a case.** "When we see failures like this, also think about principled fixes or new tools that reveal common patterns" (2026-11-09). On annotations (2026-10-28): "Often in Julia code the more principled solution is to fix the inference rather than hard code an annotation. Likewise, marking something nospecialize should be an escape hatch in my opinion."
- **Close to designs proven elsewhere.** "As close as possible to established and battle proven designs of other languages" (2026-10-19). Rust, Swift and Mojo are the references ("As always Swift, Rust and Mojo provide crucial real world experience", 2026-11-06).
- **Decisions by principle, not one by one.** The rule for open questions (2026-10-27): "Is there a principled choice? A choice that simplifies the architecture at little cost? If so adopt that. Is it unclear what the repercussions of either choice are, but working with trait code could provide insight either way? Flag it as "revisit once experience with large scale ports is at hand". Is there other evidence/experiments that could settle the choice? Record it as such. If not just accept it as is. Only keep the choices with a well articulated trade-off for me to review." And (2026-11-10): "I don't want to review all decisions made by you."
- **The work does not stop at a gate.** "Okay, don't stop at gates, even if they fail. Make a choice and record it." (2026-11-06). The user often leaves for the night with "work without getting back to me".
- **No claim of better steady-state speed.** "I don't want to claim better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x))." (2026-11-10).
- **Fair workloads.** "Specific precompile workloads, unless they genuinely cover broad typical cases (String, Int Columns) are cheating. The traits+facts mode should enable us to work with Compiled code like with precompiled libraries." (2026-11-08).
- **Guarantees matter beyond what is measured.** "If certain performance characteristics are guaranteed that enables to build around them, even if they don't have a measurable effect now." (2026-11-06).
- **Small measurements now, campaigns at a freeze.** "Remember to design experiments that give feedback quickly. Nothing that runs for hours." (2026-10-27).
- **Nothing is proposed upstream yet** (2026-10-27). What the facts build finds wrong in plain Julia is kept as patches that stand without traits (W-19).
- **The shared machine is other people's too.** "This is a shared machine with MANY people on it. Be very careful with ressource use." "NEVER search the entire file system."
- **Reviews by an independent agent, for what matters.** The user asks for a Fable agent's review of a day's work, a plan or a high-impact choice, and for "fresh eyes" on a design. The findings are acted on, each where it belongs.

## 4. What is not built, on purpose

- **A cache across sessions.** "We don't build the cross session cache now. The measurement campaign should contain workloads that would exercise it" (2026-11-14).
- **Speed work.** Retired; the performance explorations log is an archive.
- **Sealed sets.** "Sealed AbstractTypes make sense but are an optimisation for later" (2026-10-29).
- **Keys in the language's core.** Optional extensions.

## 5. What a new agent tends to get wrong

- **Writing history into a current document.** "Was", "no longer", a date, a commit, a work item: none belongs in a reference, the rationale, the intro, the evidence, the goals or the state. History has homes: the alternatives, the decision log, this page, the attic.
- **Calling the implementation "the unified build", or comparing with "the earlier build".** There is one implementation. A baseline is plain Julia or Python.
- **Fixing at the case.** A failing test, a slow step, a port's obstacle: name the pattern and the rule, record it, propose the fix at the rule. `IO` cost a day and a change to Base.
- **Reading "do not design a port around a weak point" as forbidding the idiom the design teaches.** A port's change that follows a rule of the references is the port following the design.
- **Asking the user.** Only a question the work cannot continue without. Otherwise choose, record the choice as "mine" (the reference, the decision log, open issues §1) and go on.
- **Measuring too much.** Minutes, not hours; the registry row before the run.
- **Trusting a first number.** Profile; check the image is valid; time the step a second time.
- **Copying a number or a status.** Link to its home.
- **Relying on Claude Code's project memory.** It is in no repository.
- **Treating a demonstrator as a constraint.** It follows the design.

## 6. People, names and places

- **"Mine"** in a record means the agent's choice, input to the next synthesis.
- **"oc"** in documents of early November is an earlier attempt at the unified build by another model; its notes are in `attic/oc-notes/`. The build began from its branch after an audit.
- **Session numbers** ("s23") name sessions before dated notes began. "Session 30" is session 29.
- **IDs are permanent:** T-, F-, C-, L- (deviations), E- (experiments), W- (work items), GT- (tensions), D- (the next iteration's decisions), PE- (performance explorations), open-issue numbers.
