# KidsSRS — Compliance posture & pre-submission checklist

Derived from `SPEC.md` §12 (Privacy, Safety & Compliance) and §14.1 (the video
compliance pivot). This is an engineering checklist, **not legal advice**; the
items marked ⚠️ need legal/product sign-off before release.

## Age rating & category

- **Standard age rating (~12+), NOT the Kids Category.** Decided in §14.1:
  because Song Review embeds YouTube video, the app cannot meet Kids-Category
  requirements, so it ships at a standard rating instead.
- The rest of the app keeps its original posture; only the video feature is
  carved out.

## Privacy by construction (§12) — holds, except for video

- No accounts, no PII collected by us, no third-party analytics SDKs, no ads in
  our own code.
- All child data lives in the **family's own iCloud** (CloudKit private DB); it
  never reaches our servers (we have none).
- Declared in `KidsSRS/Resources/PrivacyInfo.xcprivacy`: no tracking, no
  collected data types, UserDefaults required-reason API (`CA92.1`).
- **Video carve-out (§14.1):** Song Review loads YouTube in a `WKWebView`.
  Google may collect identifiers from the child and ads may play. This waiver of
  privacy-by-construction is **scoped to Song Review only** and disclosed in-app
  on the consent screen.

## Gates

- **Adult gate (§8.1):** protects the parent zone. Math problem *or* parent-set
  passcode, plus optional Face ID / Touch ID. This is friction (keep-kids-out),
  **not** verifiable parental consent.
- **Video consent gate (§14.1):** `VideoConsentStore` blocks **all** video at
  the single chokepoint (`SongReviewView` — the only place `YouTubePlayerView`
  loads). Revocable from Parents → Song Review → Video consent.
  - ⚠️ **The consent *mechanism* is interim.** The grant action is an informed
    acknowledgment, **not** legally-sufficient verifiable parental consent (VPC).
    A legally-approved verification method must replace it (see the `⚠️ LEGAL`
    comments in `VideoConsent.swift` / `VideoConsentView.swift`) and be signed
    off before launch.

## YouTube ToS (§14.1)

- Player stays **visible** on-screen (no audio-only / locked-screen playback).
- Branding and controls remain; ads are not suppressed.

## Pre-submission checklist

- [x] Privacy manifest present and accurate.
- [x] No analytics/ad SDKs bundled.
- [x] No `NSManagedObject` in views; data behind repositories (§4.1).
- [x] Graceful handling of a Core Data load failure (no crash, §4).
- [ ] ⚠️ Verifiable parental consent (VPC) mechanism implemented + legal sign-off (§14.1).
- [ ] App Store privacy "nutrition label" filled (discloses iCloud storage + the YouTube data flow).
- [x] CloudKit container provisioned (`iCloud.com.kidssrs.app`); private-DB sync enabled in code (`PersistenceController.cloudKitContainerIdentifier`). **v1 uses NSPCKC's single managed private zone — per-child zones (§10.2) deferred to v2 sharing** (one family Apple ID needs no per-child isolation; children separated logically by `childID`).
- [ ] Multi-device sync verified on two **physical** devices (on-device step). Code-side is covered: the §10.3 newest-`lastReviewedAt` conflict resolution has automated end-to-end tests (`CardStateMergePolicyTests` — two contexts racing on one file-backed store, plus a non-`CardState` property-trump fallback case), and CloudKit health is now surfaced in-app at **Parents → iCloud Sync** (backed by `CloudKitSyncMonitor`) so a stalled/failed sync is visible, not silent.
- [ ] CloudKit schema deployed to **Production** before App Store release (dev env auto-creates on first run).
- [x] Background Modes → **Remote notifications** enabled for iOS background sync (`UIBackgroundModes` in `KidsSRS/Info.plist`). macOS needs no equivalent — the shared `aps-environment` push entitlement covers it.
- [x] **macOS distribution: Mac App Store** → App Sandbox enabled on the macOS build via a platform-specific `KidsSRS-macOS.entitlements` (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`), granting `app-sandbox` + `network.client` (outbound: YouTube + playlist import) + `network.server` (the `LocalPlayerServer` loopback listener). iOS entitlements unchanged.
  - **On-device verify (Xcode GUI build required — CLI can't provision the Mac):** Song Review video still loads under sandbox; iCloud sync works (note the store moves to the app's sandbox container, so existing non-sandboxed dev data won't carry over — CloudKit re-syncs it). Fallback if App Review rejects the local server: serve the player page from a hosted URL (see `LocalPlayerServer` note).
- [ ] On-device QA: notification delivery, biometric unlock, shared-iPad profile switching (§15.11).
- [x] Accessibility **code** pass across all surfaces incl. Song Review / Game Mode (§11).
  - Audited every view: reduce-motion is gated wherever the UI animates (`StudySessionView` celebrations); no state is conveyed by color alone — every grade/selection pairs color with an icon **and** text (`ScoreButton`, Game Mode score buttons); custom controls carry `accessibilityLabel` + `.isSelected` traits; text uses scalable semantic fonts (`.font(.system(size:))` is used only for decorative icons).
  - Fixes from this pass: labelled the `YouTubePlayerView` region for VoiceOver orientation; `SmartSongReviewView` child toggles announce name + selected trait (not a bare "checkmark"); `ImportPlaylistView` "Find playlist" keeps its label while the spinner shows; `RewardCollectionView` equipped item gains `.isSelected`.
  - **Remaining (on-device QA, rides with §15.11):** a live VoiceOver walkthrough + Dynamic Type XXXL screenshots on a real device — not verifiable from the simulator/CLI.
