# Firebase backend (official app)

Firestore security rules and Cloud Functions (App Store purchase verification) for the official
Sonus build. Forks should use their own Firebase project.

```bash
cd firebase
firebase use --add            # creates .firebaserc (gitignored) for your project
firebase functions:secrets:set EMAIL_HASH_PEPPER
firebase deploy --only firestore:rules,functions
```

Apple root certificates for purchase verification go in `functions/certs/` (see the README there).

## Local emulators (no real project)

For testing the app's sign-in and Firestore locally, run `npm run emulators` and
`npm run emulators:seed` from the repo root, then launch a debug build with `-SonusFirebaseEmulator`.
They use the offline `demo-sonus` project and the rules in `firestore.rules`. See
[CONTRIBUTING.md](../CONTRIBUTING.md#testing-sign-in-without-the-production-firebase-project).
