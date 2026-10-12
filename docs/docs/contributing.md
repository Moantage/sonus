---
title: Contributing
description: How changes get into Sonus, and how this site stays up to date.
---

# Contributing

Everything lives in [Moantage/sonus](https://github.com/Moantage/sonus):

| Folder | What's inside |
|---|---|
| `ios/` | The SwiftUI app (`MP3Player.xcodeproj`) and `SonusCore`, a Swift package with logic that's tested on Linux |
| `spec/` | Manifest JSON Schema, OpenAPI file and example manifests: the single source of truth |
| `docs/` | This Docusaurus site |
| `firebase/` | Firestore rules and Cloud Functions for the official app |

## How a change lands

1. Open a pull request against `main`.
2. Add an entry to `CHANGELOG.md` (date, title, description). CI fails without one; maintainers can
   apply the `skip-changelog` label for changes that don't need one.
3. CI runs on Linux: spec lint and example validation, Swift unit tests, SwiftLint and a docs
   build.
4. When it's green, add the PR to the **merge queue**. The queue batches PRs, re-runs CI on the
   combined result and only merges if that's green too.
5. After the merge, the docs site redeploys automatically.

## Running things locally

```bash
npm install                      # spec + docs dependencies (npm workspaces)
npm run spec:check               # lint the OpenAPI file, validate example manifests
npm run docs:start               # live-reloading docs site
swift test --package-path ios/SonusCore
swiftlint lint
```

To build the app, open `ios/MP3Player.xcodeproj` in Xcode. Copy
`ios/MP3Player/GoogleService-Info.example.plist` to `GoogleService-Info.plist` with your own Firebase
project's values. AdMob uses Google's test IDs unless you add a `Secrets.xcconfig`.

### Testing sign-in without a Firebase project

Debug builds can use the Firebase Local Emulator Suite instead of a real project. You need the
Firebase CLI (`npm install -g firebase-tools`) and Java 11+, but no `GoogleService-Info.plist`.

```bash
npm run emulators         # Auth + Firestore emulators on the offline demo-sonus project
npm run emulators:seed    # test accounts from firebase/emulator-seed.local.json or the example
```

Then launch the app with the `-SonusFirebaseEmulator` argument and sign in with "Continue with
email". The example account is `tester@sonus.test` / `sonus-emulator-only`. The Emulator UI at
http://127.0.0.1:4000 shows the accounts and Firestore data. The flag is compiled out of release
builds.
