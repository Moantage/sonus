# Changelog

Every change merged into `main`, newest first. Each entry has a date, a title and a description.

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
