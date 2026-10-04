# Bloomy 1.9.19 / build 144 — distribution verification

Published release: https://github.com/knightfolk/Bloomy/releases/tag/v1.9.19

## Exact source and artifact

- Release source: `cbd98874687e72fb4dedb89e7da37d49b900bea3` on
  `release/1.9.19`: the published 1.9.18 baseline plus guarded model Uninstall.
  The menu preview is excluded. Main preserves that preview, so its source
  differs from the release/tag source.
- Exact-source tests: 1,543 app/telemetry, 21 Companion and 28 host tests;
  **1,592 reported, seven opt-in skips**, no failures. Packaging: 17 tests pass.
  Release compilation completed in 115.42 seconds.
- Developer ID signing, hardened runtime and secure timestamp verified.
  Final deep strict signature verification passes, including embedded Sparkle.
- Apple notarization **Accepted**:
  `50f347aa-3e6e-4ca4-acd2-cb0465fdccbe`.
  Stapling, ticket validation and Gatekeeper pass (`Notarized Developer ID`).
- Final ZIP: `Bloomy-1.9.19-mac-arm64.zip`, **9,752,308 bytes**,
  SHA-256 `3dda3c7e170a7cf9708bf0d0727a795f2ec8a216559ed8915b886e24d4898928`.
  The uploaded ZIP, checksums and release manifest match their local asset
  sizes/digests. The ZIP was independently rehashed against the manifest.

Publication workflow deviation: the draft lookup by tag returned HTTP 404,
and publication was dispatched before the upload-digest assertion completed.
Immediate verification after publication confirmed all three uploaded assets
matched local sizes/digests, before copying the appcast. This is postpublication
verification, not proof of a completed prepublication digest gate.

## Native Uninstall proof

The synthetic native fixture uses the release source: all **101** entries in
`native-uninstall-review/fixture-manifest.json` match the exact release revision.
It is an isolated review application, not a distribution artifact.

- Cancellation made zero delete calls and retained the fixture sentinel.
- A simulated busy writer made one attempted call, blocked removal and retained
  the protected fixture sentinel.
- Successful confirmation in the compact light presentation reached two total
  calls and removed only the fixture sentinel. The final saved status records
  `weightsFileExists: false` and `removed fixture sentinel`.
- A resident model's Uninstall control was disabled; a missing model had no
  Uninstall action; fake removal exposed Download again.

No real model deletion or inference was performed for this proof. Native alert
semantics and actions were checked through accessibility. Alert captures had
blank pixels, so this record does not claim pixel-level visual approval.

## Isolated updater gates

The exact final signed ZIP was served to isolated copies of build 143 using
the real Sparkle protocol and a synthetic QuitTarget. All four gates passed:

1. Invalid signature rejected and build 143 retained.
2. Normal installation reached build 144.
3. Deferred installation retained build 143 until the test target quit, then
   reached build 144.
4. Installation with relaunch reached build 144.

Every installed test app passed signature and Gatekeeper checks. Preferences
changed only `SULastCheckTime`; provider configuration, the real application
bundle, and the real application/provider processes were preserved. The
recovery watcher was already absent before this check and remained absent.
The test server and application stopped, and private preference snapshots
were removed.

The initial preflight failed because its outdated baseline expectation required
the absent recovery watcher. Its failed `preflight-public-summary.json` is
retained. The subsequent `public-summary.json` records
`passed_final_signed_zip`; the failed preflight is not counted as a passed run.

## Evidence and remaining boundary

Logs and artifacts are retained under `.build/release-v1.9.19-144/`:
`exact-tests.log`, `packaging-tests.log`, `release-build.log`,
`upload/release-manifest.json`, `native-uninstall-review/fixture-manifest.json`,
`native-uninstall-status.json`, `notary-status.json`, `staple-validate.log`,
`final-codesign.log`, `gatekeeper.log`, and `upgrade-test/public-summary.json`.

Build, signing, notarization and updater checks pass for the exact ZIP above;
the publication-order deviation is recorded separately. Kevin is
handling the actual installed update. Production installation of 1.9.19/build
144 remains unverified here; the isolated updater gates do not establish that
installation or dirty-editor update behavior. Broader native polish and
performance work remains governed by `APP_POLISH_OPTIMIZATION_PLAN.md`.
