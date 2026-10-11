// Validates every example manifest against the JSON Schema plus the semantic rules the
// schema can't express (unique IDs, references that resolve). Files in examples/manifest
// must pass; files in examples/manifest-invalid must each fail at least one check.
// The Swift package (ios/SonusCore) runs its own tests over the same fixtures.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const specDir = fileURLToPath(new URL("..", import.meta.url));
const readJSON = (path) => JSON.parse(readFileSync(path, "utf8"));

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validateSchema = ajv.compile(readJSON(join(specDir, "schemas/manifest.schema.json")));

export function semanticErrors(manifest) {
  const errors = [];
  const ids = {};
  for (const collection of ["artists", "albums", "tracks", "playlists"]) {
    const seen = new Set();
    for (const item of manifest[collection] ?? []) {
      if (seen.has(item.id)) errors.push(`duplicate ${collection} id "${item.id}"`);
      seen.add(item.id);
    }
    ids[collection] = seen;
  }
  const expect = (set, id, where) => {
    if (id !== undefined && !set.has(id)) errors.push(`${where} references unknown id "${id}"`);
  };
  for (const album of manifest.albums ?? []) expect(ids.artists, album.artistId, `album "${album.id}" artistId`);
  for (const track of manifest.tracks ?? []) {
    expect(ids.artists, track.artistId, `track "${track.id}" artistId`);
    expect(ids.albums, track.albumId, `track "${track.id}" albumId`);
  }
  for (const playlist of manifest.playlists ?? []) {
    for (const trackId of playlist.trackIds ?? []) expect(ids.tracks, trackId, `playlist "${playlist.id}"`);
  }
  return errors;
}

function check(file) {
  const manifest = readJSON(file);
  const errors = [];
  if (!validateSchema(manifest)) {
    errors.push(...validateSchema.errors.map((e) => `schema: ${e.instancePath || "/"} ${e.message}`));
  } else {
    errors.push(...semanticErrors(manifest));
  }
  return errors;
}

let failed = false;
const jsonFiles = (dir) => readdirSync(join(specDir, dir)).filter((f) => f.endsWith(".json")).map((f) => join(specDir, dir, f));

for (const file of jsonFiles("examples/manifest")) {
  const errors = check(file);
  if (errors.length) {
    failed = true;
    console.error(`✗ ${file} should be valid:\n  ${errors.join("\n  ")}`);
  } else {
    console.log(`✓ valid    ${file}`);
  }
}
for (const file of jsonFiles("examples/manifest-invalid")) {
  const errors = check(file);
  if (errors.length === 0) {
    failed = true;
    console.error(`✗ ${file} should be rejected but passed`);
  } else {
    console.log(`✓ rejected ${file} (${errors[0]})`);
  }
}
process.exit(failed ? 1 : 0);
