<p align="center">
  <img src="docs/static/img/logo.svg" width="72" alt="Sonus waveform mark">
</p>

<h1 align="center">Sonus</h1>

<p align="center">
  An open-source iPhone music player for music you host yourself (NAS, S3, Google Cloud Storage,
  GitHub or your own server), in an interface that already feels familiar.
  <br>
  <a href="https://moantage.github.io/sonus/"><strong>Documentation</strong></a> ·
  <a href="https://moantage.github.io/sonus/spec/manifest">Manifest spec</a> ·
  <a href="https://moantage.github.io/sonus/server-api/sonus-server-api">Server API</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

## What it does

- **Stream** songs straight from your own storage, or **download** them for offline play.
- Connect through an open, documented spec:
  - **Sonus Manifest**: one `sonus.json` file next to your music on any static host.
  - **Sonus Server API**: an OpenAPI 3.1 contract for dynamic servers.
  - **OpenSubsonic**: works with Navidrome, Gonic, Ampache and other existing NAS servers.
- Server credentials stay in the iPhone Keychain and are only ever sent to your server.

> **Status:** the spec is `1.0-draft`. The current app imports from the Files app. Manifest,
> Server API and OpenSubsonic support are in development; see the [changelog](CHANGELOG.md).

## Repository layout

| Path | Contents |
|---|---|
| [`ios/`](ios) | SwiftUI app (`MP3Player.xcodeproj`) and [`SonusCore`](ios/SonusCore), platform-independent logic tested on Linux |
| [`spec/`](spec) | Manifest JSON Schema, OpenAPI file and example manifests: the single source of truth |
| [`docs/`](docs) | Docusaurus site, regenerated from `spec/` and deployed on every merge |
| [`firebase/`](firebase) | Firestore rules and Cloud Functions for the official app |

## Getting started

```bash
npm install                                # spec + docs tooling (npm workspaces)
npm run spec:check                         # lint OpenAPI, validate example manifests
npm run docs:start                         # docs site at http://localhost:3000/sonus/
swift test --package-path ios/SonusCore    # unit tests (macOS or Linux)
```

**Building the app:** open `ios/MP3Player.xcodeproj` in Xcode (iOS 17+).

1. Copy `ios/MP3Player/GoogleService-Info.example.plist` to `GoogleService-Info.plist` and fill it
   in from your own Firebase project.
2. AdMob and Google Sign-In use placeholder or test IDs from `ios/MP3Player/Config.xcconfig`. To
   use real ones, copy `Secrets.example.xcconfig` to `Secrets.xcconfig` (gitignored).

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. In short: every PR adds
a changelog entry, CI runs on Linux, and merges go through a merge queue that only merges green
batches.

## License

[Apache-2.0](LICENSE). The Sonus name and logo identify the official Novora Labs app; please use
your own branding if you publish a fork.
