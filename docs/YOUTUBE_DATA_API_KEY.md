# Setting up the YouTube Data API key (made-for-kids check)

Song Review only allows **made-for-kids** YouTube videos to be added (Spec §14.1 /
`COMPLIANCE.md`). That check calls the **YouTube Data API v3**, which needs an API
key. **Until a key is configured the gate fails closed** — no videos can be added,
on purpose — so set this up before testing Song Review.

The key is read at runtime from the Info.plist value `YouTubeDataAPIKey`, which is
populated from the **`YOUTUBE_DATA_API_KEY` build setting**. The build setting is
supplied by a **gitignored** xcconfig so the key is never committed.

---

## 1. Create + enable the API

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create
   (or pick) a project.
2. **APIs & Services → Library →** search **"YouTube Data API v3" → Enable**.

## 2. Create a restricted API key

1. **APIs & Services → Credentials → Create credentials → API key.** Copy it.
2. Click the key to edit it, then **restrict it** (do at least the first):
   - **API restrictions → Restrict key → YouTube Data API v3.** Always do this —
     it limits the blast radius if the key leaks, and works on every platform.
   - **Application restrictions → iOS apps → add bundle id `com.kidssrs.app`.**
     Optional but recommended for the iOS build. The app sends the
     `X-Ios-Bundle-Identifier` header so this restriction authorizes the request.
     - ⚠️ **macOS note:** the "iOS apps" restriction targets the iOS build. If the
       Mac (Mac App Store) build can't reach the API with it on, either use a
       **separate key with API-restriction-only** for macOS, or rely on the API
       restriction alone.

The check costs **1 quota unit per request** (videos are batched ≤50/request).
The default quota is 10,000 units/day — far more than this feature needs.

## 3. Wire the key into the build (not committed)

1. Copy the template and add your key:
   ```sh
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   # edit Config/Secrets.xcconfig → YOUTUBE_DATA_API_KEY = AIza...your-key...
   ```
   `Config/Secrets.xcconfig` is gitignored — your key stays local.
2. In Xcode, set it as the **base configuration**:
   **Project (not target) → Info → Configurations →** expand **Debug** and
   **Release →** for the **KidsSRS** project/target set the config file to
   **`Secrets`** (or `Config/Secrets.xcconfig`).
   *(Alternatively pass it on the command line: `xcodebuild … YOUTUBE_DATA_API_KEY=AIza…`.)*

That's it — `Info.plist`'s `$(YOUTUBE_DATA_API_KEY)` resolves at build time, and
`MadeForKidsChecker` picks it up.

## 4. Verify

Build + run, open **Parents → Song Review → a playlist → Add song**:

- Add a **made-for-kids** video (e.g. an official kids' song) → it's **added**.
- Add a non-MFK video (e.g. a typical music video) → it's **rejected** with
  "Only videos marked 'made for kids' on YouTube can be added."
- With **no key set**, every add is rejected with "couldn't confirm… made for
  kids" — that's the fail-closed default, confirming the gate is wired.

## Notes

- **Rotation:** if the key leaks, delete it in the Console and drop a new one into
  `Config/Secrets.xcconfig`. No code change needed.
- **CI:** inject `YOUTUBE_DATA_API_KEY` as a secret build setting/env var.
- This key only reads public video metadata (`status.madeForKids`); it grants no
  write access and touches no child data.
