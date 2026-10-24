# Changelog

Every change merged into `main`, newest first. Each entry has a date, a title and a description.

## 2026-10-24 — Fix "Audio session setup failed" on device; build 2

- Playback on a real iPhone showed "Audio session setup failed." and nothing played. The audio
  session asked for the `.allowAirPlay` and `.allowBluetoothA2DP` options with the `.playback`
  category. iOS only accepts those with `.playAndRecord`, so setting the category threw.
- The session now uses `.playback` with the long-form audio policy. That is Apple's setting for
  music apps, and it routes to AirPlay and Bluetooth by itself.
- Build number raised to 2 for the next TestFlight upload.

## 2026-10-24 — Sign with the Sonus team; Sign in with Apple entitlement

- The app is now signed by team P7S9BC8T7P, the paid team on the project's Apple ID
  (dhruvabisht.work@proton.me). It was signed by a free personal team, which can't publish to
  TestFlight or the App Store. Build 1.0 (1) has been uploaded to TestFlight from this setup.
- Added `MP3Player.entitlements` with the Sign in with Apple capability, so "Continue with Apple"
  works in TestFlight and App Store builds.

## 2026-10-24 — Ember redesign: generated covers, a living Now Playing, one-tap Shuffle

- **Every song has a cover.** Songs without artwork get one drawn from their ID: a two-tone
  gradient, soft light and a rings, waves, sunset or equaliser motif in one of eight Ember-family
  palettes. The same song always gets the same cover.
- **Now Playing comes alive.** The song's artwork glows behind the player as a blurred light that
  drifts while music plays and holds still when paused or with Reduce Motion on. Swipe the artwork
  left or right to skip, or double-tap it to play or pause. An "Up next" pill shows the next song
  and opens the queue. The scrubber thickens and glows while you drag it. Previous and Next bounce
  when tapped, and the header says "Shuffling from" after a shuffle.
- **Shuffle everywhere.** A Shuffle all button on Home and a Shuffle button on every collection
  and playlist page play the list in a random order.
- **Home leads with a hero card**: what's playing, what played last, or the newest song, set on its
  own blurred artwork with Play/Resume and Shuffle all. The top of Home takes on the featured song's
  colour, and a line under the greeting sums up the library.
- **Mini-player** is a lit floating pane with an amber progress line and a Next button.
- **Your Library** always shows Recently added (plus Downloaded when there are downloads) and ends
  with a Create playlist row, so it is never empty.
- Softer corners, one shared spring vocabulary (`Theme.Motion`), and tab icons that bounce on tap.

## 2026-10-24 — Full-screen ads replace banners; high-quality audio is Premium again

- Banner ads are gone from every screen. Free users now see one full-screen **app open** ad when
  Sonus launches, and one **interstitial** after every 20 minutes of listening, shown at the next
  song change (music pauses for the ad and resumes after). A Premium subscription or the lifetime
  purchase removes both. New build settings: `ADMOB_APP_OPEN_UNIT_ID`, `ADMOB_INTERSTITIAL_UNIT_ID`
  (Google test IDs by default); `ADMOB_BANNER_UNIT_ID` is no longer used.
- The App Tracking Transparency prompt now actually appears (it was requested from an app-delegate
  callback that SwiftUI never calls). It's asked once the signed-in app is on screen; that launch
  skips the app open ad.
- The launch screen is Ember graphite instead of white, and the app is named "Sonus" on the home
  screen and in system prompts (it said "MP3 Player").
- New app icon: the owner's amber saxophone "Sonus" artwork, at every size (flattened to an opaque
  image, as the App Store requires).
- Per the owner's decision, high-quality audio output is back behind Premium: Premium users get the
  toggle in Profile, everyone else sees a locked row that opens the paywall. The paywall lists it.
- Advanced playback controls (speed, 15-second skip, sleep timer) stay free.

## 2026-10-12 — Player reports streams that fail to load

When a stream couldn't load (the server is down, or the phone is offline and the song isn't
downloaded), the player kept showing the song as playing and no error appeared. `AVQueuePlayer`
drops a failed item from its queue, and the engine only listened for failures of the player's
current item. It now follows the item it's playing directly, so the failure reaches
`lastPlaybackError` ("Couldn't reach the music server…") and the play button returns. Waiting with
nothing to play no longer counts as playing.

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
