# Firebase backend (official app)

Firestore security rules for the official Sonus build. Forks should use their own Firebase
project. Sonus is free and has no purchases, so there are no Cloud Functions.

```bash
cd firebase
firebase use --add            # creates .firebaserc (gitignored) for your project
firebase deploy --only firestore:rules
```

## Local emulators (no real project)

For testing the app's sign-in and Firestore locally, run `npm run emulators` and
`npm run emulators:seed` from the repo root, then launch a debug build with `-SonusFirebaseEmulator`.
They use the offline `demo-sonus` project and the rules in `firestore.rules`. See
[CONTRIBUTING.md](../CONTRIBUTING.md#testing-sign-in-without-the-production-firebase-project).
