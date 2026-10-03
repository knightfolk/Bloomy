# Bloomy 1.9.17 distribution verification

Version 1.9.17/build 142 was built from
`88181f89bcb21ae88dd385f888aa3faf142b189f`, tagged `v1.9.17` and published at
https://github.com/knightfolk/Bloomy/releases/tag/v1.9.17.
The prior build-141 archive remains preserved and was not reused as this release.

## Exact source and final bytes

- The exact-commit run passed 1,525 app/telemetry, 21 protocol and 28 host tests:
  1,574 reported tests including seven explicit opt-in skips. All 17 packaging
  tests passed. Release compilation completed in 21.05 seconds.
- Sparkle's Downloader/Installer XPC services, Updater app, standalone Autoupdate
  executable and framework were signed inside-out before Bloomy. Developer ID
  team `5P2LWPPWRN`, hardened runtime and secure timestamps were inspected.
  Deep strict signature verification passed; the executable is arm64 and links
  Sparkle through its in-app framework path.
- Apple submission `f0ddac2c-4fc2-4137-9188-9e35c4d0ee8e` returned **Accepted**.
  Stapling, ticket validation and post-stapling signature verification passed.
  Gatekeeper accepted the app as **Notarized Developer ID**. The final ZIP was
  created after stapling.
- `Bloomy-1.9.17-mac-arm64.zip`: 9,740,104 bytes, SHA-256
  `fd27fde23b2a13ee3debad892d410f160bf65cf1459e151b0d58596522cdc080`.
  GitHub's ZIP, checksum-file and manifest sizes/digests matched local files
  before and after publication at `2026-10-03T13:09:51Z`.
- The signed update item specifies build 142, displayed version 1.9.17,
  macOS 14, arm64, the exact final ZIP length and matching HTTPS asset URL.
  All 27 older items were preserved. Automatic checks and installation remain
  off in packaged defaults; existing opt-ins were not rewritten.
- After the feed commit was pushed, GitHub's API returned identical feed bytes.
  The configured historical public feed returned HTTP 200 with identical bytes,
  first item build 142 and 28 total items. Source tag and remote main were
  verified against `88181f8` and feed commit `ec13027`, respectively; the exact
  result is retained in `remote-feed-verification.json` in the release directory.

## Isolated update checks and preserved runtime

Fresh clone-on-write copies of the signed/stapled build-141 baseline were used
with the exact final archive served only on localhost. All four checks passed:

1. Invalid update signature: Sparkle error 4005; build 141 retained.
2. Immediate installation: build 142 installed; signature/Gatekeeper accepted.
3. Deferred installation: build 141 retained while the disposable target ran;
   build 142 installed after that target terminated.
4. Installation/relaunch: build 142 installed and the disposable target relaunched
   with a new PID; signature/Gatekeeper accepted.

The target is synthetic AppKit `QuitTarget.app`, passed to Sparkle CLI's
`--application` option. Only its owned PID receives SIGTERM. This establishes
installer timing and target relaunch, not real Bloomy native Quit, dirty-editor
resumption or production installation. Separate real-protocol regression tests
cover deferred callback replacement, resumption and updater-owner release;
see `HEALTH_LONG_REASONS_UPDATER_REVIEW_20261003.md`.

App preferences changed only in `SULastCheckTime`. Provider configuration,
installed executable/Info hashes and exact process/start identities were
preserved: Bloomy PID 61760, provider 63387 and watchdog 63393. The provider kept
running from the internal cache. The test server and owned target stopped;
private preference snapshots were removed. No model swap, download or synthetic
provider inference was requested for these gates.

Evidence is retained in `.build/release-v1.9.17-142/`, including signing,
notarization, asset digest verification, exact feed and
`upgrade-test/public-summary.json`. Exact-commit test, packaging and Release
logs are `/tmp/bloomy-1.9.17-exact-tests.log`,
`/tmp/bloomy-1.9.17-packaging-tests.log` and
`/tmp/bloomy-1.9.17-exact-release.log`.

## Remaining scope

Native164 provides the bounded long-Health-reason/layout evidence. The source
revision after that review changes only VERSION and release notes. Publication
does not establish installed-app integration: the preserved running app remains
1.9.15/build 140 at this checkpoint. Confirmation that its edits are saved is
pending before restarting it for comparable resource measurements.

The full native completion matrix, actual VoiceOver/system motion delivery,
whole-app visible/minimized CPU/energy/allocation measurements, long-duration
hardware GPU protection and real provider/editor/update actions remain open.
This is a verified distribution checkpoint, not completion of the ongoing
Apple-native polish and efficiency goal.
