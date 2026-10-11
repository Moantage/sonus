// Generates everything the docs site builds from, so the site can never drift from the spec:
//   1. bundles ../spec/openapi.yaml (with its JSON Schema refs) into .generated/openapi.yaml
//   2. regenerates the Server API reference pages in docs/server-api/
//   3. copies the manifest JSON Schema and examples into static/ at stable URLs
//   4. copies ../CHANGELOG.md into src/pages/changelog.md
// Every output is gitignored. Run with --clean to delete them.
import {execFileSync} from 'node:child_process';
import {cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const docsDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoDir = join(docsDir, '..');
const specDir = join(repoDir, 'spec');

const outputs = {
  bundle: join(docsDir, '.generated/openapi.yaml'),
  apiPages: join(docsDir, 'docs/server-api'),
  schemas: join(docsDir, 'static/schemas'),
  examples: join(docsDir, 'static/examples'),
  changelog: join(docsDir, 'src/pages/changelog.md'),
};

for (const path of [dirname(outputs.bundle), outputs.apiPages, outputs.schemas, outputs.examples, outputs.changelog]) {
  rmSync(path, {recursive: true, force: true});
}
if (process.argv.includes('--clean')) process.exit(0);

const run = (bin, args) => execFileSync(bin, args, {cwd: docsDir, stdio: 'inherit'});

// 1. Bundle the spec.
mkdirSync(dirname(outputs.bundle), {recursive: true});
run('npx', ['--no-install', 'redocly', 'bundle', join(specDir, 'openapi.yaml'), '--output', outputs.bundle]);

// 2. Generate API reference pages.
run('npx', ['--no-install', 'docusaurus', 'gen-api-docs', 'all']);

// 3. Publish the schema and examples at stable URLs (the schema's $id points here).
cpSync(join(specDir, 'schemas/manifest.schema.json'), join(outputs.schemas, 'v1/manifest.schema.json'));
cpSync(join(specDir, 'examples/manifest'), join(outputs.examples, 'v1'), {recursive: true});

// 4. Changelog page.
const changelogPath = join(repoDir, 'CHANGELOG.md');
if (!existsSync(changelogPath)) throw new Error(`Missing ${changelogPath}`);
const changelog = readFileSync(changelogPath, 'utf8');
mkdirSync(dirname(outputs.changelog), {recursive: true});
writeFileSync(
  outputs.changelog,
  `---\ntitle: Changelog\ndescription: Every change merged into Sonus, newest first.\n---\n\n${changelog}`,
);

console.log('Docs content prepared from spec/ and CHANGELOG.md');
