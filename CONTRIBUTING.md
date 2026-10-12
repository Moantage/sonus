# Contributing to Sonus

Thanks for helping. The full guide lives on the docs site:
**https://moantage.github.io/sonus/contributing**

## The short version

1. Branch from `main` and open a pull request back into `main`.
2. Add an entry at the top of [`CHANGELOG.md`](CHANGELOG.md):

   ```markdown
   ## 2026-10-11 — Short title

   What changed and why, in a sentence or two.
   ```

   CI fails without one. Maintainers can apply the `skip-changelog` label for changes that don't
   need an entry (typo fixes, CI-only tweaks).
3. CI runs on Linux. Every check must pass:
   - spec lint and example validation (`npm run spec:check`)
   - docs build with broken-link checking (`npm run docs:build`)
   - Swift unit tests (`swift test --package-path ios/SonusCore`)
   - SwiftLint in strict mode. Existing app findings are in `.swiftlint-baseline.json`; new code
     must be clean.
4. Once it's green, use **Merge when ready**. The merge queue batches PRs, re-runs CI against the
   latest `main` and only merges if that passes. After the merge, the docs site redeploys
   automatically.

## Testing sign-in without the production Firebase project

The app requires a login. Debug builds can use the Firebase Local Emulator Suite instead of a
real Firebase project. You don't need `GoogleService-Info.plist` or a Firebase account for this.
Nothing reaches a real project, so test accounts never end up in the production user database.

1. Install the Firebase CLI (`npm install -g firebase-tools`) and Java 11 or newer.
2. Start the Auth and Firestore emulators: `npm run emulators`. This uses the offline
   `demo-sonus` project. Data is kept in `firebase/emulator-data/` (gitignored) between runs, and
   the Emulator UI is at http://127.0.0.1:4000.
3. Create test accounts: `npm run emulators:seed`. This creates the accounts in
   `firebase/emulator-seed.local.json` (gitignored; copy the `.example.json` next to it to start),
   or `tester@sonus.test` / `sonus-emulator-only` from the example file if there's no local file.
4. Run the app in the Simulator with the launch argument `-SonusFirebaseEmulator`. You can add it
   in Xcode (Scheme → Run → Arguments) or pass it to
   `xcrun simctl launch <device> com.novoralabs.mp3player -SonusFirebaseEmulator`. Sign in with
   "Continue with email". To reach emulators on another machine, set the environment variable
   `SONUS_FIREBASE_EMULATOR_HOST` to its address.

Google, Apple and phone sign-in need the real project; use email in emulator mode. The flag is
compiled out of release builds.

## Changing the spec

`spec/` is the single source of truth. When you change the schema or the OpenAPI file, update
the examples in `spec/examples/`. Valid examples must pass and the ones in `manifest-invalid/`
must fail, both in the JSON Schema check and in the `SonusCore` Swift tests. Breaking changes
need a new major version; see the versioning page on the docs site.

## Never commit secrets

Firebase config, real AdMob IDs, API keys, certificates and personal documents are gitignored.
Use the `*.example.*` templates instead. GitHub secret scanning with push protection is enabled
on this repository.
