#!/usr/bin/env node
// Starts the Firebase Auth and Firestore emulators for testing the app locally.
// Uses the offline `demo-sonus` project, so it never touches a real Firebase project and needs no
// login. Data is saved to firebase/emulator-data/ (gitignored) on exit and loaded on the next start.
// Requires the Firebase CLI (`npm install -g firebase-tools`) and Java 11+.
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const firebaseDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const dataDir = join(firebaseDir, 'emulator-data');

const args = [
  'emulators:start',
  '--project', 'demo-sonus',
  '--only', 'auth,firestore',
  '--export-on-exit', dataDir,
];
if (existsSync(join(dataDir, 'firebase-export-metadata.json'))) {
  args.push('--import', dataDir);
}

const child = spawn('firebase', args, { cwd: firebaseDir, stdio: 'inherit' });
child.on('error', (error) => {
  console.error(`Could not start the Firebase CLI (${error.message}).`);
  console.error('Install it with: npm install -g firebase-tools');
  process.exit(1);
});
child.on('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));

// Ctrl-C already reaches the CLI through the process group; a second SIGINT would make it skip
// the export. Only forward SIGTERM, which is sent to this process alone.
process.on('SIGINT', () => {});
process.on('SIGTERM', () => child.kill('SIGTERM'));
