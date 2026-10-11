# Sonus spec

The single source of truth for how Sonus talks to music sources. The docs site and the app's
tests both build from these files.

| File | What it is |
|---|---|
| `schemas/manifest.schema.json` | Sonus Manifest, JSON Schema draft 2020-12, published at `https://moantage.github.io/sonus/schemas/v1/manifest.schema.json` |
| `openapi.yaml` | Sonus Server API, OpenAPI 3.1. Reuses the manifest schemas. |
| `examples/manifest/` | Valid manifests. They must pass every check. |
| `examples/manifest-invalid/` | Manifests that must be rejected, each breaking one rule |

```bash
npm run check   # redocly lint + example validation (schema and semantic rules) + bundle
```

Version: `1.0-draft`. See the versioning page on the docs site.
