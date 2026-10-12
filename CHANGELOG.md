# Changelog

Every change merged into `main`, newest first. Each entry has a date, a title and a description.

## 2026-10-12 — Fix Firestore in emulator mode

In `-SonusFirebaseEmulator` mode, Firestore tried to reach the emulator over TLS and every read and
write failed. As a result, sign-in worked, but the profile and consent never saved and the consent
screen spun forever. Firebase 12's `useEmulator` only changes the host, so emulator mode now also
turns TLS off explicitly.

## 2026-10-12 — Firebase emulator mode for testing sign-in

- Debug builds launched with `-SonusFirebaseEmulator` use the Firebase Auth and Firestore emulators
  on the offline `demo-sonus` project instead of the real Firebase project. They need no
  `GoogleService-Info.plist`, and test accounts stay out of the production user database. Release
  builds are unchanged.
- `npm run emulators` starts the emulators, keeping their data in `firebase/emulator-data/`
  (gitignored). `npm run emulators:seed` creates test accounts from
  `firebase/emulator-seed.local.json` (gitignored) or the example file.
- Setup steps are in CONTRIBUTING.md.

## 2026-10-12 — Streaming engine with manifest and GitHub sources

Sonus can now stream and download music from the person's own sources, not just play imported
files.
- **Playback:** the player moves from `AVAudioPlayer` to `AVQueuePlayer`. Downloaded and imported
  songs play from the device; everything else streams, and the next song preloads so it starts
  without a gap. New buffering state, network errors in plain words, lock-screen info with artwork
  read from the file's tags. Speed, sleep timer, ±15 s skips, repeat, interruptions and background
  audio work as before.
- **Sources:** Sonus Manifest (`sonus.json`) and GitHub repositories. A source refresh updates
  songs in place by their stable IDs. GitHub repositories work with no setup: files are listed from
  the Git tree, titles are cleaned up until tags are read, and Git LFS files stream from the media
  host. A `sonus.json` in the repository is used when present. Private repositories work with a
  fine-grained token that stays in the Keychain and goes only to GitHub's API, raw and media hosts.
- **Authenticated streaming:** an `AVAssetResourceLoader` path makes ranged requests with the
  source's token, so seeking works on private sources. Sonus Server and private buckets can use it
  later.
- **Downloads:** offline downloads are free and run on a background `URLSession`. They report
  real progress, can be cancelled, resume where they stopped, and are checked against the source's
  SHA-256 when it publishes one.
- **Networking:** `NSAllowsLocalNetworking` and a local-network usage description, for servers on
  the home network. `NSAllowsArbitraryLoads` stays off; remote hosts must use https.
- **SonusCore:** source models, the merge planner, the stream-or-local decision, GitHub listing and
  LFS parsing, rate-limit handling, the ranged HTTP client and the token host policy, with Swift
  Testing tests against a local HTTP server.
- **Docs:** GitHub hosting (private repositories, tokens, limits) and which hosts receive a token.
## 2026-10-12 — Spotify-style shell in Ember (dark)

- Dark-only Ember theme (warm graphite, one amber accent, bold SF Pro, pill buttons and chips).
- New shell: Home / Search / Your Library tabs, avatar → Profile & settings, persistent mini-player
  (tap to expand, swipe to skip), and a Now Playing that grows out of it (drag down to dismiss,
  background tinted from the artwork, working queue, AirPlay picker).
- Tap a song to play it in place. New song rows with equaliser bars and a "⋯" bottom sheet
  (add to playlist, remove, download, delete). Library filter pills and playlist pages with a
  download toggle and a big play button. Full-screen "name your playlist" flow.
- Paywall: sources, streaming and downloads are free with an account; Premium is profile banners,
  sync across devices and ad-free listening. High-quality audio and playback controls are no
  longer gated (pending owner confirmation).
- DEBUG-only `-SonusUIReview` launch argument opens the shell without sign-in for UI review.

## 2026-10-11 — Xcode project uses a synced folder

`ios/MP3Player/` is now an Xcode synchronized folder: files added to it join the app target
automatically, without edits to `project.pbxproj`. Parallel branches and outside contributors no
longer conflict on the project file. Config, template and StoreKit files are excluded from the
app bundle, as before.

## 2026-10-11 — Sonus spec 1.0-draft, docs site and Linux CI/CD

Restructures the project as a monorepo and publishes the first draft of the open Sonus spec.
- **App:** the Xcode project moves to `ios/`. Real AdMob and Google Sign-In IDs now come from
  a gitignored `Secrets.xcconfig`; `Config.xcconfig` defaults to Google's public test IDs.
  Templates for `Secrets.xcconfig` and `GoogleService-Info.plist` are included.
- **Spec (`spec/`):** Sonus Manifest JSON Schema, Sonus Server API (OpenAPI 3.1) and example
  manifests, valid and invalid.
- **SonusCore (`ios/SonusCore`):** a Swift package with the manifest models, validation, URL
  resolution and the https-or-local-network rule, tested on Linux against the spec examples.
- **Docs (`docs/`):** a Docusaurus site whose API reference, schema and changelog are regenerated
  from `spec/` and this file on every build.
- **CI:** runs on Linux only — spec lint and examples, docs build, Swift tests, strict
  SwiftLint, and a changelog check. Merges to `main` go through a merge queue that batches PRs
  and only merges green results.
- **CD:** the docs site deploys to GitHub Pages after every merge to `main`.

## 2026-10-11 — Repository created

Sonus is now open source under the Apache-2.0 licence. This first commit adds the README, the
licence, the changelog and the `.gitignore` that keeps Firebase config, API keys and other secrets
out of the repository.
