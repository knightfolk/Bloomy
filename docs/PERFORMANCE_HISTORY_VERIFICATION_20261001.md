# Performance history verification — Bloomy 1.9.13 / build 138

Verified source: `44fe98725a5f3d6ef96c336aa3a938406a44302f`.

- All 1,026 Swift tests and 17 packaging tests passed for the release source.
- Native Activity rendering was inspected at narrow and wide sizes. Model filters have consistent dimensions; chart controls remain usable.
- Installed build 138 was inspected in the running app. Earnings/Metrics navigation, 24-hour/7-day/30-day periods, model filtering, refresh, and recording details were checked.
- Local observations increased with all Bloomy windows closed. The private database uses permissions 0600. Provider process identities remained unchanged during the app replacement.
- Developer ID signing, strict signature validation, Apple notarization Accepted (`720b34bc-f82e-4f23-86e8-c77bdfd69bdb`), ticket stapling, and Gatekeeper acceptance passed.
- Isolated Sparkle gates passed for normal 137-to-138 installation, invalid-signature rejection retaining 137, deferred installation after the test target quits, and installation with test-target relaunch. Settings and provider configuration were preserved. The harness includes a two-second teardown interval after cancelling a rejected update to let Sparkle's installer connection settle.
- Final archive: 8,784,436 bytes; SHA-256 `b8061ec9e43d672ef9aac9dc09fe5cada4d105dbef5350c9f04b3a634e240048`. All three uploaded asset digests matched local bytes before GitHub publication.

Private live telemetry, screenshots, preferences and configuration snapshots are excluded from public evidence. Local gate results are retained under `.build/release-v1.9.13-138/upgrade-test/`.

Autopilot integration in this release records the native phase only. Enrollment and shadow mode do not imply activation. Missing speed, latency, or model-attributed counters remain unknown; hardware readings retain their whole-Mac or provider-wide scope.
