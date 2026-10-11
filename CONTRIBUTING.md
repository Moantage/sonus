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

## Changing the spec

`spec/` is the single source of truth. When you change the schema or the OpenAPI file, update
the examples in `spec/examples/`. Valid examples must pass and the ones in `manifest-invalid/`
must fail, both in the JSON Schema check and in the `SonusCore` Swift tests. Breaking changes
need a new major version; see the versioning page on the docs site.

## Never commit secrets

Firebase config, real AdMob IDs, API keys, certificates and personal documents are gitignored.
Use the `*.example.*` templates instead. GitHub secret scanning with push protection is enabled
on this repository.
