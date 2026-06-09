---
name: next-stage
description: >-
  Plan what to work on next in the KidsSRS app: read SPEC.md and scan the
  codebase, then produce a sequenced roadmap of the next 3–4 stages that balances
  shipping features against paying down tech debt, keeping clean,
  non-accumulating code as the fixed constraint. Reach for this on ANY "what
  should I do next / where should I focus / how do I prioritize" decision about
  this project — and treat it as the default even when the user never says
  "KidsSRS" but is clearly working in it (they may just say "the app", "the
  project", or name a file or area like StudyViewModel, the dashboard, the
  persistence layer): "what's next?", "what should I work on now?", "the
  highest-leverage thing to do", "should I build feature X or fix the sync /
  refactor first?", "features or refactoring?", "weigh new features against
  cleaning up these stubs / TODOs", "give me a plan for the next milestones", "is
  the foundation solid enough to start X, or am I getting ahead of myself?". Don't
  answer these from memory — they require actually reading SPEC.md and the current
  code first, so invoke the skill instead of guessing. NOT for: implementing an
  already-chosen stage, fixing a specific bug, reviewing a diff, explaining how
  the app or scheduler works, choosing a tech stack, or brainstorming brand-new
  feature ideas. Specific to the KidsSRS codebase and its SPEC.md.
---

# KidsSRS — Next-Stage Planner

Decide what to build next in KidsSRS and lay it out as a **sequenced roadmap**
that interleaves features and tech-debt paydown. The output is a plan, not code.

The job is judgment: weigh feature value against the cost of accumulating debt
on a foundation that's still mostly scaffolding, and produce an ordered set of
stages a developer can pick up immediately. Every claim must be grounded in
either `SPEC.md` or something you actually observed in the code — never guess at
project state.

## What KidsSRS is (so you reason in the right frame)

- A spaced-repetition study app for kids 8–11, **SwiftUI multiplatform**
  (iOS 17 / macOS 14), **Core Data + `NSPersistentCloudKitContainer`**, with a
  **pure scheduler** in the `KidsSRSCore` Swift package.
- **`SPEC.md` is the source of truth.** Three parts of it drive this skill:
  - **§14 Suggested Build Order** — the *intended* engineering sequence. Your
    roadmap adapts this to the project's real current state, it does not blindly
    copy it.
  - **§1 Design pillars** — hard constraints (no backlogs, honest grading,
    privacy by construction, calm-not-addictive, accessibility is **v1**). A
    stage that violates a pillar is wrong even if it's valuable.
  - **§3 Scope (v1 vs v2+)** — only v1 items are candidate stages. Deferred
    items (audio cards, network catalog, IAP, classroom, typed/cloze answers)
    must NOT appear as a next stage.
- **§4.1 architectural guardrail:** SwiftUI views must never touch
  `NSManagedObject` directly — Core Data is wrapped behind a repository +
  `ObservableObject` view-model layer. Missing/violated layers here are
  foundational debt, because every feature depends on them.

## Procedure

Work through these steps in order. Steps 1–2 gather ground truth; steps 3–5 are
where the actual prioritization judgment happens.

### 1. Ground in the spec

Read the three driving sections of `SPEC.md`: §14 (build order), §1 (pillars),
§3 (scope). These tell you the *intended* sequence, the constraints, and what's
even allowed to be a next stage. Keep §14's ordering in mind as the default
spine — you'll bend it where reality demands.

### 2. Take a state snapshot (what's real vs. scaffolded)

Don't assume — look. The repo is deliberately scaffolded with `TODO(§N)` markers
that tie each gap back to a spec section. Run these to map the frontier:

```bash
# Debt markers, each linked to the spec section it implements:
grep -rn "TODO\|FIXME" KidsSRS KidsSRSCore --include="*.swift" | grep -v "/.build/"
# Scaffolding / placeholder implementations:
grep -rn -iE "stub|scaffold|sample|in-memory|demo data" KidsSRS --include="*.swift"
# What views / view-models / repositories actually exist:
find KidsSRS KidsSRSCore/Sources -name "*.swift" | sort
# Test coverage (what's verified vs. unverified):
find KidsSRSCore/Tests KidsSRSTests -name "*.swift" 2>/dev/null
```

Also skim the key files to judge depth, not just presence: a file can exist and
still be a stub (e.g. a view that renders `Text("… — TODO")`). Then identify the
**frontier**: the earliest §14 build-order step that is *not* solidly done
(implemented for real + persisted + tested where it matters).

> As of the spec's build order: step 1 (foundation/persistence/repository),
> step 2 (scheduler), and step 3 (study flow) are the early spine. Treat the
> scheduler as likely the most-complete piece (it's the pure, unit-tested
> `KidsSRSCore`), and persistence wiring + the repository layer as the most
> likely foundational gaps — but **verify against what you just scanned**, since
> the code moves between sessions.

### 3. Build the debt ledger

List the outstanding tech-debt items you found, each with:
- a one-line description, the **spec section** (`§N`) and **file:line** it lives at,
- a **severity**, and crucially whether it is **foundational** (blocks or
  silently corrupts many features) or **local** (contained to one feature).

Foundational debt to watch for specifically, because it gates everything above
it in the build order:
- **Missing/!§4.1 repository + view-model layer** — without it, every feature UI
  either can't persist or violates the guardrail (throwaway work).
- **Persistence not wired** — study results not saved (`TODO(§5)`), no `Child`
  fetch, in-memory sample data standing in for real records.
- **CloudKit zones + custom merge policy stubbed** (`§10.2`, `§10.3`) — a
  correctness risk: a completed review can be lost across devices.
- **Adult gate not enforced** (`§8.1`) — the parent zone opens without the gate.

### 4. Classify candidate work

Put every plausible next thing into one of two buckets:
- **Features** — v1, in-scope (§3), not yet really built (e.g. wire study flow to
  persisted `CardState`, parent deck/card editor, multi-child management,
  dashboard, rewards UI, reminders).
- **Tech debt** — items from the ledger in step 3.

Drop anything that's v2/deferred (§3) — it's not a candidate.

### 5. Sequence the roadmap (the balancing judgment)

This is the core of the skill. Order the candidates into stages using these
principles, and **make the reasoning visible** in the output — the user asked
specifically to see the feature-vs-debt tradeoff, not just a verdict.

- **The hard constraint is clean code and non-accumulating debt — not
  "architecture before features."** What this project refuses is *piling up tech
  debt*: every stage must leave the codebase clean, with any shortcut it takes on
  paid down inside that same stage rather than deferred onto a growing pile.
  Within that constraint, features and architecture trade off pragmatically — a
  stage is judged by "does it leave the code clean and debt-free when done?", not
  by whether it wears a feature or a debt label. A feature done properly is
  always welcome in the top stages; what's never welcome is shipping one by
  cutting corners and leaving a mess behind, which is *negative* progress here
  because it manufactures rework.
- **Let real features reveal the architecture; don't over-build ahead of them.**
  You often can't see the right abstraction until a concrete feature exercises
  it, so building a feature can be the *correct* way to discover the design —
  prefer that over speculative, big-upfront architecture built for needs that
  don't exist yet. Don't force a feature in purely for visible momentum, and
  equally don't force speculative scaffolding in just because it feels
  foundational. The judgment call is which real, near-term work most needs doing
  next; let that pull the design, and pay down any debt the work creates within
  the same stage.
- **Don't stack features on stubbed foundations.** If a feature needs a layer
  that's missing or faked (persistence, repository, a fetched `Child`), the
  foundational debt comes first — otherwise you build UI that can't save and
  will be reworked. Name the dependency explicitly.
- **Highest correctness-risk first.** §14 calls the scheduler the riskiest
  surface; once it's solid, the next correctness risks are `CardState`
  persistence and the cross-device merge (§10.3). Correctness debt outranks
  cosmetic features.
- **Pillars are constraints, not features.** Accessibility is **v1** (§11) — it
  rides along with each UI stage, it isn't deferred to a final "a11y pass" that
  never comes. Privacy-by-construction and no-backlog must not be regressed by a
  stage. Flag any stage that risks a pillar.
- **Sequence by what the next real work needs, paying debt as you go.** Don't
  alternate feature/debt mechanically, and don't stack speculative architecture
  for its own sake. Pick the stage that most unblocks or clarifies the next
  genuine work — that may be a feature, an architecture investment, or a feature
  that *drives* an architecture decision. The one rule that always holds: a stage
  that takes on debt must retire it within the same stage (or the immediately
  following one, stated explicitly), so debt never compounds across the roadmap.
  State the feature:debt mix you landed on and why.
- **Prefer vertical slices over breadth.** A stage that turns one scaffolded
  path into a real, persisted, tested slice (e.g. study flow → real `CardState`)
  beats spreading thin across many half-built screens.
- **Respect scope.** No v2 items as stages; park them in "Out of scope now."

## Output format

Produce exactly these sections, in this order. Be decisive about Stage 1 but
transparent about why. Cite `SPEC §N` and `file:line` wherever you make a claim.

### 1. State snapshot
2–4 sentences: where the frontier is, what's genuinely solid, what's still
scaffolding. Ground it in what you scanned.

### 2. Next-stage roadmap
An ordered list of the **next 3–4 stages** — the near horizon the user can act on
now, not the whole arc to v1. (If a critical foundation forces a clear 5th stage,
mention it in one line, but don't plan the full backlog.) Stage 1 is the
recommended immediate next stage. For each stage:

- **Title** + a type tag: `[Feature]`, `[Tech debt]`, or `[Mixed]`
- **Goal** — one line.
- **Why now** — the load-bearing justification: dependency unblocked, risk
  retired, pillar honored, or momentum. Reference the build order / ledger.
- **Key tasks** — concrete bullets, file-level where known.
- **Risk & effort** — `S` / `M` / `L`, plus the main thing that could go wrong.
- **Done when** — a verifiable completion check (builds, persists across
  relaunch, tests pass, etc.).

### 3. Debt ledger
Every outstanding debt item: description · `§N` · `file:line` · severity ·
foundational/local · **which stage addresses it** (or "deferred — <reason>").

### 4. Balance note
2–3 sentences on how you weighed features vs. debt this cycle and the
feature:debt mix of the proposed stages. Make the governing rule explicit — clean
code, with debt retired as it's incurred rather than allowed to pile up — and for
any feature you scheduled, say whether it's there because it's cleanly unblocked,
because it reveals the architecture direction, or both (never just because it's
visible). This is the answer to the user's actual question — make it explicit.

### 5. Out of scope now
v2/deferred items (§3) someone might expect to see, parked with a one-line
reason so the user knows they were considered, not forgotten.

## Style

- Be specific to *this* repo: cite real files and spec sections, not generic
  advice. If you couldn't verify something, say so rather than asserting it.
- Decisive but honest about uncertainty and tradeoffs. The user wants a plan
  they can act on *and* the reasoning behind the ordering.
- This skill plans; it does not implement. Stop at the roadmap unless the user
  asks you to start a stage.
