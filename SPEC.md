# KidsSRS — Product & Technical Specification

> A spaced-repetition learning app for kids aged 8–11, for iOS and macOS.
> Think "Anki for kids" — the proven memory science of Anki/Quizlet, redesigned
> so an 8-year-old can use it daily without an adult driving every tap, and
> without the demotivating backlog, opaque grading, and engagement traps that
> make adult SRS tools unsuitable for children.

**Status:** Draft v1 spec, derived from product interview.
**Date:** 2026-06-04

---

## 1. Product Summary

KidsSRS helps children review and retain school material (vocabulary, sight
words, math facts, science terms, languages, etc.) through short, daily,
gamified study sessions backed by a spaced-repetition scheduler.

- **Primary user (studier):** child, 8–11.
- **Secondary user (manager):** parent (or a parent-like teacher managing a
  small number of children on their own device).
- **Platforms:** iOS (iPhone + iPad) and macOS, from a single SwiftUI
  multiplatform codebase.
- **Core loop:** Parent sets up children + decks → child studies a capped daily
  session → child earns deterministic collectible rewards → scheduler resurfaces
  cards over time → parent monitors progress.

### Design pillars

1. **No demotivating backlogs.** Daily load is capped; overflow reschedules
   silently. A kid never opens the app to "347 cards due."
2. **Honest grading without adult-level self-assessment.** Kids commit to a
   prediction *before* seeing the answer; the app coaches metacognition.
3. **Success-biased scheduling.** SM-2 is tuned for kids to favor frequent wins
   over theoretical optimality.
4. **Privacy by construction.** No PII, no accounts, no kid data on our servers.
   All child data lives in the family's own iCloud (CloudKit private database).
   *(Exception, added post-draft: the optional **Song Review** feature embeds
   YouTube and is deliberately excluded from this pillar — see §14.1.)*
5. **Calm, not addictive.** Deterministic rewards, no loot boxes, no streak-loss
   anxiety as the primary hook, no leaderboards.
6. **Accessible to struggling readers.** Dyslexia support, VoiceOver, Dynamic
   Type, color-blind-safe, reduced motion — all v1.

---

## 2. Audience & Assumptions

**Target age: 8–11 ("middle childhood").**

Implications baked into the design:

- Children can read independently but with varying fluency → text is primary,
  but read-aloud (TTS) and images support struggling readers.
- Children can self-direct a study session but need motivation and clear,
  bounded goals → capped sessions + visible reward progress.
- Children **cannot reliably self-grade** ("Did I really know that?") → the
  predict-then-verify flow (§6.3) and simplified two-button grading.
- Parental involvement is **light but present** → parent does setup and
  monitoring, not day-to-day driving.
- Shared family iPad is the common device → frictionless profile switching, no
  passwords for kids.

**Explicitly out of scope for the audience:** pre-readers (<8) and
near-adult tweens (12+). The UI is tuned for one band, not a 4–13 everything-app.

---

## 3. Scope: v1 vs. Later

### In v1
- Text cards (front/back) and **image cards**.
- Parent-authored decks (in-app editor) + a small set of **bundled starter
  decks** for instant first-run value.
- Multi-child profiles under one parent (one Apple ID / one family).
- Predict-then-verify study flow with simplified two-button self-rating.
- Kid-tuned SM-2 scheduler with learning steps.
- Parent-set daily limit per child.
- Deterministic collectible/avatar reward system.
- Progress dashboard for the parent.
- Full offline operation + CloudKit private sync across the family's devices.
- Optional local daily study reminder.
- Accessibility: Dynamic Type, VoiceOver, dyslexia-friendly mode, color-blind
  safe, reduced motion.
- **(Added post-draft)** Video **Song Review** and **Game Mode** content, behind
  the parent gate — a conscious departure from the Kids-Category / privacy
  posture below; see §14.

### Deferred to v2+
- **Audio cards** (recording + TTS-as-content). *Note: TTS read-aloud of text
  cards is still in v1 as an accessibility feature; what's deferred is audio as
  a first-class card content type.* *(**Video** as a content type was since added
  to v1 via Song Review — §14 — but recorded/TTS audio-as-content stays deferred.)*
- **Managed curated catalog** delivered over the network (see §9). v1 ships
  bundled starter decks only; the catalog mechanism (CDN deck packs) is designed
  for but not built in v1.
- **Parent subscription / IAP.** v1 ships free; monetization is a v2 concern.
- **Classroom / teacher rostering.** See §3.1.
- Typed-answer and cloze/math-input card types.
- Voice/spoken answering and multiple-choice answer modes.

### 3.1 Teacher / classroom — explicitly NOT v1

A teacher with ~30 kids across many devices breaks the CloudKit private-DB model
(it is scoped to a single Apple ID) and pulls in **FERPA**, not just COPPA.

**v1 decision:** *Family only.* One parent Apple ID, a handful of children as
profiles on the parent's device(s). A teacher can use the app as a "power
parent" (more profiles on their own device) but there is **no rostering, no
per-student devices, and no sharing** in v1. Real classroom support is a
separate later track that will require a backend + FERPA work and is
deliberately deferred.

---

## 4. Platform & Technology

| Concern | Decision |
|---|---|
| UI | **SwiftUI**, multiplatform (single codebase, iOS + macOS) |
| Min OS | iOS 17 / macOS 14 (for modern SwiftUI + Observation) |
| Persistence | **Core Data + `NSPersistentCloudKitContainer`** |
| Sync | CloudKit **private database**, per-child **record zones** |
| Catalog (v2) | CloudKit **public database** and/or **CDN deck packs** |
| Backend | **None** in v1 (no server, no PII) |
| Reminders | Local notifications (`UNUserNotificationCenter`) |
| TTS | `AVSpeechSynthesizer` (accessibility read-aloud) |

### 4.1 Why Core Data + CloudKit (not SwiftData)

SwiftData is more ergonomic but its CloudKit integration has hard constraints
that conflict with this product:

- **No public-database sync** — the v2 catalog needs CloudKit public DB; Core
  Data's `NSPersistentCloudKitContainer` supports it, SwiftData does not.
- **No unique constraints** under CloudKit sync — but we rely on **stable card
  IDs** for deck versioning/merge (§9.2). Core Data lets us model and enforce
  identity more directly.
- **All attributes must be optional or have defaults** under SwiftData+CloudKit,
  which complicates the scheduler's required fields.

Core Data + `NSPersistentCloudKitContainer` is the mature path that supports
multi-zone private sync **and** a future public-DB catalog from the same stack.
The extra boilerplate is an accepted cost.

> Architectural guardrail: even though we use Core Data, wrap it behind a thin
> repository/`@Observable` view-model layer so SwiftUI views never touch
> `NSManagedObject` directly. This isolates the persistence choice.

---

## 5. Data Model

All entities are designed to satisfy CloudKit constraints (no required
relationships at sync boundaries that can't be nil during partial sync;
relationships are optional with explicit inverse).

### Core entities

**`Child`** (one CloudKit record zone per child)
- `id: UUID` (stable)
- `displayName: String`
- `avatarConfig: Data` (chosen avatar + customizations)
- `dailyNewCardLimit: Int` (parent-set, default per §7.3)
- `dailyReviewLimit: Int` (parent-set)
- `pacingProfile: enum {gentle, normal, fast}`
- `reduceMotion / dyslexiaMode / readAloud: Bool` (per-child a11y prefs)
- relationships: → `CardState[]`, → `RewardProgress`, → `SessionLog[]`

**`Deck`**
- `id: UUID` (stable, shared across catalog versions)
- `title, subjectTag, iconConfig`
- `origin: enum {bundled, parentAuthored, catalog}`
- `version: Int` (for merge logic, §9.2)
- relationship: → `Card[]`

**`Card`**
- `id: UUID` (**stable, permanent** — survives deck edits; key to §9.2 merge)
- `deckID: UUID`
- `frontText: String?`, `backText: String?`
- `frontImageRef: AssetRef?`, `backImageRef: AssetRef?`
- `hint: String?`
- `order: Int`
- `contentHash: String` (detects content changes during catalog merge)

**`CardState`** (per child × card — the scheduler's state; lives in child's zone)
- `cardID: UUID`, `childID: UUID`
- SM-2 fields: `easeFactor: Double`, `intervalDays: Double`,
  `repetitions: Int`, `dueDate: Date`, `lapses: Int`
- `learningStepIndex: Int?` (nil once graduated to SM-2; see §7.2)
- `status: enum {new, learning, review, retired}`
- `lastReviewedAt: Date?`
- metacognition: `lastPredictionMatched: Bool?` (for §6.4 flagging)

**`SessionLog`** (per study session — powers dashboard + reminders)
- `childID, startedAt, endedAt, cardsSeen, cardsCorrect, newIntroduced`
- per-card review events (grade, prediction, latency) for the parent dashboard

**`RewardProgress`** (per child)
- `coinsOrPointsEarned`, `unlockedItemIDs: [UUID]`, `currentMilestoneID`

**`AssetRef`** — image stored as a CloudKit asset (`CKAsset`) for sync; cached
locally. Images must be downsized on import (target ≤ a few hundred KB) to
respect CloudKit limits and offline storage.

### Identity & merge

- `Card.id` is **permanent and global** (assigned at authoring/publish time, not
  per-child). This is what makes catalog deck updates merge cleanly (§9.2):
  content edits update `frontText`/`contentHash` but the `CardState` keyed on
  `cardID` is preserved.

---

## 6. The Study Experience (Child)

### 6.1 Launch & profile selection
- App opens to a **"pick your face" profile picker** — large avatar tiles, no
  passwords. Frictionless for a shared family iPad; stakes are low (siblings
  picking each other's profile is tolerable).
- Only the **parent zone** is gated (§8); studying is never gated.

### 6.2 Session start
- Child sees today's session as a **bounded, finite goal**: a small progress
  track (e.g. "12 cards today" or a visual path), never a raw due-count.
- Session composition each day:
  1. **Due reviews** (capped at `dailyReviewLimit`), reviews scheduled first.
  2. **New cards** introduced up to `dailyNewCardLimit`, *after* reviews.
  - Overflow beyond caps is **silently rescheduled** — no guilt, no pile.

### 6.3 Predict-then-verify card flow (core interaction)

For each card:

1. **Prompt shown** (front: text and/or image; read-aloud available).
2. **Predict (commit before reveal):** child taps **"I think I know it"** vs.
   **"Not sure."** This is mandatory — the kid cannot grade blind, and the
   commitment nudges honesty and builds metacognition.
3. **Reveal:** child taps to flip; answer (back) is shown.
4. **Self-rate (simplified):** two kid-friendly buttons — **"Got it!"** vs.
   **"Missed it."** (Anki's 4-grade scale is reduced to 2; coarser but
   age-appropriate.)
5. The pair (prediction, self-rating) is recorded.

### 6.4 Metacognition signal — flag only, no scheduler change

The prediction vs. self-rating comparison is used for **coaching and parent
visibility only**; it does **not** alter SM-2. This keeps the algorithm clean
and debuggable.

- **Over-confident** ("I think I know it" → "Missed it"): gentle kid feedback
  ("Tricky one! Let's see it again soon.") and surfaced to the parent dashboard.
- **Under-confident** ("Not sure" → "Got it!"): encouraging feedback ("You knew
  more than you thought! 🎉").
- The scheduler consumes only the final **Got it / Missed it** self-rating.

> Rationale: altering intervals from prediction data was considered and
> rejected for v1 — it makes scheduling opaque and harder to validate. Revisit
> with real usage data.

### 6.5 Session end
- Clear "You're done!" celebration (respecting reduced-motion).
- Reward progress advances visibly (§7.4) — deterministic, "next unlock at X."
- No nagging to do more; the session is *complete*.

---

## 7. Scheduling Engine

### 7.1 Algorithm: kid-tuned SM-2

Base is classic SM-2 (ease factor + interval growth), adapted to favor frequent
success over long-interval optimality. The two-button grade maps to SM-2 as:

- **"Got it!"** → quality ≥ 4 equivalent (advance).
- **"Missed it"** → quality < 3 equivalent (lapse: reset to learning steps).

### 7.2 Learning steps (new-card pacing)

New cards do **not** go straight into SM-2. They pass through short,
same-session **learning steps** to solidify before spacing begins:

- Steps (default): **1 minute → 10 minutes** (re-shown within/near the session).
- A card graduates to SM-2 review state after passing its final learning step.
- A lapse ("Missed it") on a review card sends it **back into learning steps**
  rather than only shrinking the interval — kids re-solidify rather than waiting
  weeks for a half-known card.

### 7.3 Kid-tuned SM-2 parameter profile (recommended defaults)

These deviate intentionally from adult Anki defaults to keep kids succeeding:

| Parameter | Adult default | **Kid default (recommended)** | Why |
|---|---|---|---|
| Starting ease | 2.5 | **2.3** | Slightly slower interval growth → more reps, more wins. |
| Min ease floor | 1.3 | **1.6** | Prevents "ease hell"; one bad week can't trap a card. |
| Ease penalty on lapse | −0.20 | **−0.12** (gentler) | One bad day shouldn't tank a card. |
| Ease bonus on "Got it" | +0.0–0.15 | small/none | Avoid runaway intervals. |
| **Max interval cap** | months/years | **60 days** | Kids revisit familiar content, feel mastery, avoid scary gaps. |
| Target retention | ~85–90% | **~90%+** | Bias toward success; more frequent, easier reviews. |
| New cards/day | 20 | **5** (parent-adjustable) | Prevent overwhelm. |
| Learning steps | 1m 10m | **1m 10m** | Solidify before spacing. |

**Pacing profile** maps a single parent choice to a coherent parameter set:
- **Gentle:** new/day 3, max interval 30d, gentlest ease penalty.
- **Normal:** the table above.
- **Fast:** new/day 8, max interval 60d, standard penalties.

Parents adjust via the gentle/normal/fast control (and can override new/day and
the daily review cap directly).

### 7.4 Daily load — parent-set limit

- The parent sets a **daily ceiling per child** (review cap + new-card cap).
  This puts control with the adult and matches the "no backlog" pillar.
- Reviews are scheduled first; new cards fill remaining headroom.
- Anything over the cap silently moves to a future day. The child is never shown
  an overdue pile.

---

## 8. Parent / Adult Experience

A gated area inside the same app (no separate web app in v1).

### 8.1 The adult gate
- Entry to the parent zone is gated by an **adult check** — a generated
  arithmetic problem ("What is 7 × 8?") or a parent-set passcode, chosen at
  setup. This is a friction gate (keep-kids-out), not a security boundary.
- The gate protects: profile management, deck authoring, settings, scheduler
  tuning, and (in v2) any purchase flow.

### 8.2 Multi-child management
- Create / edit / remove child profiles (each backed by its own CloudKit zone).
- Per-child settings: avatar, daily limits, pacing profile, accessibility prefs,
  which decks are assigned.

### 8.3 Deck authoring (in-app editor)
- Create/edit decks and cards: front/back text, optional image (front and/or
  back), hint, ordering.
- Image import downsizes assets (§5).
- Authored decks are `origin: parentAuthored`, synced via the parent's private
  DB, assignable to one or more children.

### 8.4 Progress dashboard (read-only insight)
Per child: accuracy trend, time studied, current streak (informational, not
weaponized), cards in each state (new/learning/review), and a **"struggling
cards"** list (high lapse count or repeated over-confidence flags from §6.4) so
the parent can intervene or re-teach.

---

## 9. Content & Catalog

### 9.1 v1 content
- **Bundled starter decks** shipped in the app (instant offline first-run).
- **Parent-authored decks** via the editor.
- No network catalog in v1.

### 9.2 Catalog (v2) — designed for now, built later
- Delivery mechanism: **versioned CDN deck packs** (JSON + assets), downloaded
  on demand, with CloudKit public DB as an alternative considered. v1 ships a
  bundled subset using the same on-device deck format so the migration is clean.
- **Deck versioning with stable-ID merge** (the chosen strategy): when a catalog
  deck updates while a child already has SM-2 progress on it:
  - Cards carry **permanent IDs** (§5). On update:
    - **Edited cards** → content (`frontText`/`backText`/`contentHash`) updates
      in place; the child's `CardState` (keyed on `cardID`) is **preserved**.
    - **New cards** → added as `new`, enter the normal new-card pacing.
    - **Removed cards** → marked `retired` (kept for history, not scheduled).
  - This avoids stale copies and avoids resetting a child's progress on a typo
    fix. Merge is automatic (not opt-in) for catalog decks.

### 9.3 Reward economy — deterministic unlocks (no loot boxes)
- Apple's Kids Category **bans loot-box / gambling mechanics**; rewards must be
  deterministic.
- Model: **clear "study X → earn Y" milestones**, with the next unlock always
  visible ("Study 3 more days to unlock the dragon avatar").
- Rewards are **collectible avatars / customizations** — cosmetic, intrinsic-ish,
  low pressure. No randomness, no leaderboards, no streak-loss punishment as the
  primary driver.
- Reward progress is per child (`RewardProgress`).

---

## 10. Sync, Offline & Notifications

### 10.1 Offline-first
- **Everything works fully offline.** The app never blocks on the network.
- CloudKit (`NSPersistentCloudKitContainer`) syncs **opportunistically** in the
  background when connectivity is available.
- Essential for cars, travel, and spotty Wi-Fi — a kid must be able to study
  anywhere.

### 10.2 Sync architecture
- **One CloudKit record zone per child** in the family's **private database**,
  enabling clean per-child sync and isolation.
- Parent-authored decks + catalog state sync via the private DB.
- **No data on our servers; no PII collected** — child's name is a display label
  in the family's own iCloud, nothing leaves Apple's privacy boundary.

### 10.3 Conflict handling
- Last-writer-wins is acceptable for most fields, **except scheduler state**:
  for `CardState`, prefer the record with the **most recent `lastReviewedAt`**
  to avoid losing a completed review when two family devices sync. Implement a
  small custom merge policy for `CardState`.

### 10.4 Notifications
- **Optional local daily reminder** ("Time to study!") via local notifications,
  scheduled on-device. **Off by default; parent-enabled** per child, with a
  parent-chosen time.
- Tone is gentle and non-guilt-inducing. No streak-loss scare notifications.
- No push server in v1.

---

## 11. Accessibility & Inclusivity (all v1)

- **Dynamic Type + VoiceOver:** full support; App Store baseline expectation.
  All interactive elements labeled; study flow operable via VoiceOver.
- **Dyslexia-friendly mode:** OpenDyslexic (or similar) font option, generous
  line/letter spacing, and **text-to-speech read-aloud** (`AVSpeechSynthesizer`)
  of card fronts/backs. High value for struggling readers.
- **Color-blind safe:** correctness/state is **never encoded by color alone** —
  always pair with icon + shape + text. (Got it = green check ✓; Missed = amber
  circle ↻, etc.)
- **Reduced motion:** tones down avatar/reward animations; bound to the OS
  *Reduce Motion* setting and overridable per child.

---

## 12. Privacy, Safety & Compliance

- **COPPA posture:** no accounts, no PII collection, no third-party analytics
  SDKs, no ads. Child data lives only in the family's iCloud private DB.
- **Apple Kids Category compliance:** no behavioral ads, no loot boxes, no
  unbounded external links; any future purchase flow lives behind the adult gate
  (§8.1). *(Superseded for video: embedding YouTube in **Song Review** takes the
  app **out of the Kids Category** entirely — see §14.1.)*
- **No third-party trackers** in v1.
- Future catalog content must be vetted/curated (content ops) before publish.

---

## 13. Key Tradeoffs & Open Decisions (recorded)

1. **SM-2 + self-rating vs. auto-grading.** We kept self-rating (works for any
   content, no typing burden) and mitigated the honesty problem with
   predict-then-verify + simplified 2-button grades, rather than switching to
   auto-graded multiple-choice/typed answers. *Risk:* residual grading noise;
   *mitigation:* learning-step re-solidification on lapse + parent "struggling
   cards" visibility. Revisit if data shows bad calibration.
2. **Prediction data is flag-only.** Chosen for algorithm clarity; we forgo the
   potential accuracy of folding it into the grade. Revisit with usage data.
3. **Core Data over SwiftData.** Accepted extra boilerplate to keep public-DB
   catalog and stable-ID identity viable (§4.1).
4. **Family-only v1.** Classroom/teacher deferred to avoid FERPA + backend; a
   teacher can limp along as a power-parent meanwhile.
5. **Free v1, subscription v2.** Faster validation; revenue deferred.
6. **Audio cards deferred**, but TTS read-aloud kept as accessibility.
7. **Max-interval cap (60d) sacrifices theoretical retention efficiency** for
   kid motivation and a sense of mastery. Intentional.

---

## 14. Media Cards, Song Review & Game Mode (v1 addition)

> Recorded after the v1 draft, from a follow-up product decision. This section
> adds **video-based content** and two new study modes, and **consciously
> overrides** parts of the original design *for the video feature*: design pillar
> #4 (privacy by construction), the §3 scope/category posture, and §12's Kids
> Category stance. Those overrides are scoped to Song Review; the rest of the app
> keeps its original posture.

### 14.1 Compliance pivot (video)

Embedding YouTube is incompatible with Apple's Kids Category and with
privacy-by-construction. The decision is to **ship video anyway**, accepting:

- **Out of the Kids Category.** The app ships at a standard age rating (~12+),
  not in the Kids Category. The privacy-by-construction pillar is waived **for
  the video feature only**.
- **COPPA still applies** — it attaches to a service directed to under-13s
  *regardless of App Store category*. Embedding YouTube lets a third party
  (Google) collect persistent identifiers from a child, which legally requires
  **verifiable parental consent (VPC) before any video loads**. The §8.1 adult
  gate is an anti-kid *friction* gate, **not** VPC; a dedicated consent step is
  required and its mechanism needs legal sign-off before launch.
- **YouTube ToS shapes the UX:** the player must stay **visible** (no audio-only
  / screen-locked playback), branding and controls remain, and **ads will play**
  on arbitrary videos with no way to suppress them.

### 14.2 Media cards & cross-deck categories (data model)

Both new modes are **consumers of the existing card corpus** — they do not fork
the model. Two additive changes (one Core Data migration) serve both:

- **`Card.kind`** — `text | image | video` discriminator (default `text`), so a
  playlist can query video cards directly instead of sniffing which field is set.
- **`Card.videoRef`** — the YouTube video ID for `video` cards.
- **`Tag`** — a new entity, **many-to-many with `Card`**, giving **card-level,
  cross-deck categories**. This is the shared selection axis for Game Mode (and
  available to any mode): "pick cards where category ∈ {…}".

Per-child scheduling is unchanged: `CardState` is already keyed per
**(child × card)**, so "each kid's score on each song" needs no new state.

### 14.3 Song Review — parent-led, multi-kid (hybrid SRS)

- **Parent-initiated and parent-operated**, often with several kids watching
  together. Lives behind the parent / consent gate (§14.1).
- A "playlist" is a deck of `video` cards. Playback is **parent-curated** — the
  parent plays the whole list (or a chosen subset, e.g. "still learning"); it is
  **not** auto-composed from per-kid due dates, because one shared playthrough
  can't honor divergent per-kid schedules.
- After each song the parent rates **each child present** on a **3-level scale:
  Doesn't know it / Getting there / Knows it**. Each rating updates that child's
  `CardState` via the scheduler (§14.4) and writes a per-child `SessionLog`, so
  the existing dashboard (§8.4) surfaces per-kid song mastery for free.

### 14.4 The 3-level parent grade → SM-2

The parent's rating is a distinct grading path (no predict-then-verify; an adult
judges the child). It lives in `KidsSRSCore`, unit-tested like the core
scheduler, carries **no** confidence prediction (so it never sets the §6.4
metacognition flag), and maps to the existing state machine:

| Parent rating | SM-2 effect |
|---|---|
| **Knows it** | Same as "Got it" — advance through learning / grow the interval. |
| **Doesn't know it** | Same as "Missed it" — lapse back to learning, gentle ease drop. |
| **Getting there** | **Soft repeat:** re-show soon but **keep accumulated progress** — no ease penalty, no lapse count, no reset of repetitions. In review it re-checks at the graduating interval; in learning it re-shows at the current step without advancing. |

### 14.5 Game Mode — card draws for board games

- Replaces the question cards that ship with physical board games: the app draws
  a card on demand; the kid answers aloud; tap to reveal the back.
- **Choosable by category** (the `Tag` axis, §14.2) and **individualized to the
  kid** — drawn from that child's assigned decks, weighted by their `CardState`
  (what's new / learning / due). "Learning plan" here is **shorthand for assigned
  decks + scheduler state**, not a new entity.
- **Optional scoring:** the parent/kid may mark a drawn card right/wrong, which
  feeds the kid's `CardState` through the normal scheduler — so board-game time
  can double as review. Unmarked draws are non-scoring.

### 14.6 Model delta summary

- `Card`: **+`kind`**, **+`videoRef`**, **+`tags`** (↔ `Tag`).
- **New `Tag`** entity (`id`, `name`, ↔ `cards`).
- New grading types in `KidsSRSCore`: `ParentGrade` (3-level) + `ParentReviewInput`.
- No change to `CardState`, `Child`, `SessionLog`, or `RewardProgress`.

---

## 15. Suggested Build Order (engineering)

1. **Foundation:** Core Data model + `NSPersistentCloudKitContainer`, per-child
   zones, repository layer. Verify offline + multi-device private sync.
2. **Scheduler:** kid-tuned SM-2 + learning steps as a pure, unit-tested module
   (no UI dependency). This is the riskiest correctness surface — test it hard.
3. **Study flow:** profile picker → predict-then-verify card view → 2-button
   grade → session end. Wire to scheduler.
4. **Daily caps & session composition** (reviews-first, new-card limit).
5. **Parent zone:** adult gate, multi-child management, deck authoring (text +
   image), settings (pacing/limits/a11y).
6. **Bundled starter decks** in the on-device deck format (forward-compatible
   with v2 deck packs).
7. **Rewards:** deterministic unlock milestones + avatar collection UI.
8. **Dashboard:** session logs → accuracy/time/struggling-cards views.
9. **Accessibility pass:** Dynamic Type, VoiceOver, dyslexia mode + TTS,
   color-blind audit, reduced motion.
10. **Local reminders** (opt-in, parent-configured).
11. **Polish, App Store review (standard age rating — §14.1 — no longer Kids
    Category), QA on shared-iPad + multi-device sync edge cases.**
12. **(§14, slot before submission)** Media-card migration (`kind` / `videoRef` /
    `Tag`); the 3-level **parent grade** in `KidsSRSCore` (unit-tested); the
    parental-consent gate; the parent-led **Song Review** player; and **Game
    Mode** card draws.

---

## 16. Glossary

- **SRS** — Spaced Repetition System.
- **SM-2** — the SuperMemo-2 scheduling algorithm (ease factor + interval).
- **Learning steps** — short same-session repeats before a card enters spaced
  review.
- **Lapse** — a card answered "Missed it" after it had graduated to review.
- **Predict-then-verify** — child commits to a confidence prediction before
  revealing the answer, then self-rates.
- **Adult gate** — friction check (math problem/passcode) protecting the parent
  zone.
- **Song Review** — parent-led playback of a deck of video (song) cards, scored
  per kid on the 3-level parent grade (§14.3).
- **Game Mode** — on-demand card draws by category, individualized per kid, to
  replace the question cards of physical board games (§14.5).
- **Media card** — a card whose content is a video (`kind = video`, `videoRef`).
- **Parent grade** — the 3-level adult rating (Doesn't know it / Getting there /
  Knows it) that maps to SM-2 (§14.4).
- **VPC (verifiable parental consent)** — COPPA-grade consent, stronger than the
  §8.1 friction gate, required before loading third-party video (§14.1).
