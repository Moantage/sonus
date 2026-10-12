#!/usr/bin/env node
// Creates test accounts in the Firebase Auth emulator. It only ever talks to the emulator.
// Accounts come from firebase/emulator-seed.local.json (gitignored) when it exists, otherwise
// from firebase/emulator-seed.example.json. Existing accounts are left as they are.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const firebaseDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const localSeed = join(firebaseDir, 'emulator-seed.local.json');
const seedFile = existsSync(localSeed) ? localSeed : join(firebaseDir, 'emulator-seed.example.json');
const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const signUpURL = `http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-sonus-emulator-key`;

const { accounts } = JSON.parse(readFileSync(seedFile, 'utf8'));
console.log(`Seeding ${accounts.length} account(s) from ${seedFile.slice(firebaseDir.length + 1)} into ${host}`);

for (const { email, password, displayName } of accounts) {
  let response;
  try {
    response = await fetch(signUpURL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, displayName, returnSecureToken: false }),
    });
  } catch (error) {
    console.error(`Can't reach the Auth emulator at ${host} (${error.cause?.code ?? error.message}).`);
    console.error('Start it first with: npm run emulators');
    process.exit(1);
  }
  const body = await response.json().catch(() => ({}));
  const message = body.error?.message ?? '';
  if (response.ok) {
    console.log(`  created  ${email}`);
  } else if (message.startsWith('EMAIL_EXISTS')) {
    console.log(`  exists   ${email}`);
  } else {
    console.error(`  failed   ${email}: ${message || response.status}`);
    process.exitCode = 1;
  }
}
