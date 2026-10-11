# Changelog

Every change merged into `main`, newest first. Each entry has a date, a title and a description.

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
