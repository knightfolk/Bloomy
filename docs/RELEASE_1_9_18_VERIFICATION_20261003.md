# Bloomy 1.9.18 / build 143 — distribution verification

Published October 3, 2026 at 14:33:55 UTC:
https://github.com/knightfolk/Bloomy/releases/tag/v1.9.18

## Exact source and artifact

- Source and annotated tag target:
  `dc5b8c6fc44281c2a7051717ad949fffb207906e`.
- Exact-source suite: 1,530 app/telemetry, 21 Companion and 28 host tests;
  **1,579 reported, seven opt-in skips**, no failures. Packaging: 17 tests pass.
  Release compilation: 21.14 seconds. No warnings/errors in these logs.
- Native168 verifies the History source shipped here, with all 109 review source
  hashes still matching. The isolated 5,000-entry proof, geometry regressions
  and database workload measurements are in
  `ACTION_RECORDING_COMPACT_HISTORY_REVIEW_20261003.md`.
- Sparkle Downloader/Installer XPCs, Updater, standalone Autoupdate and framework
  signed inside-out before Bloomy. Developer ID, hardened runtime and secure
  timestamp verified. The arm64 executable links packaged Sparkle via rpath.
- Apple notarization **Accepted**:
  `044125b9-fcce-42e0-a45a-a740aae2d284`.
  Stapling, ticket validation, deep strict signatures and Gatekeeper pass.
- Final ZIP made after stapling: `Bloomy-1.9.18-mac-arm64.zip`, **9,742,205 bytes**,
  SHA-256 `abb1fafffef173cfd88d3e6e24b57c2448e92e4d4ff9f741f81af2058d974c73`.
  ZIP, checksums and release manifest were uploaded as a draft; all three GitHub
  asset sizes/digests matched before publication and again afterward.
- The signed appcast specifies build 143, version 1.9.18, arm64, macOS 14.0,
  exact ZIP length and HTTPS asset URL. Its 28 older items are preserved verbatim.
  Automatic checking/installing stay off in package defaults; existing opt-ins
  were not rewritten.

## Isolated updater gates

Fresh clone-on-write copies of signed/stapled build 142 were tested against the
final signed ZIP on localhost. Previous logs were not reused:

1. Invalid signature rejected with Sparkle error 4005; build 142 retained.
2. Normal installation reached build 143; signature and Gatekeeper accepted.
3. Deferred installation retained build 142 until the synthetic target quit,
   then installed build 143; signature and Gatekeeper accepted.
4. Installation/relaunch reached build 143 and a new synthetic target PID;
   signature and Gatekeeper accepted.

App preferences changed only `SULastCheckTime`. Provider configuration, real
Bloomy bundle/executable, and canonical production/provider/watchdog process
identities remained unchanged. Test target and localhost server stopped; private
preference snapshots were removed. Sanitized summary and all finite gate logs
are in `.build/release-v1.9.18-143/`.

These gates use the real Sparkle protocol with a synthetic QuitTarget. They do
not establish dirty-editor installation or normal Quit behavior in the actual
production Bloomy. Installed build 140 stays running while the saved-edit reply
is pending. Whole-app CPU/energy improvement remains unmeasured; the release's
35–48× comparison is specifically synthetic disk-backed database recording.
The broader native polish, accessibility and performance matrix remains open.
