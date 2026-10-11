---
title: Versioning
description: How the Sonus spec evolves without breaking apps or servers.
---

# Versioning

The Sonus Manifest and the Sonus Server API share one version number, `MAJOR.MINOR`.

- **Minor versions** (1.0 → 1.1) only add optional fields or endpoints. Apps MUST ignore fields
  they don't recognise, so a 1.1 manifest still works in an app built for 1.0.
- **Major versions** (1 → 2) may break compatibility. A new major version gets its own schema URL
  (`/schemas/v2/…`) and API prefix (`/sonus/v2`), and the app supports the old major for a
  deprecation period announced in the [changelog](/changelog).
- **Drafts** (`1.0-draft`) can still change. Nothing is frozen until 1.0 is released.

The manifest declares its version in the `sonus` field. Servers report theirs from
`GET /sonus/v1/info` in `specVersion`.
