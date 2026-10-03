# Bloomy 1.9.16 distribution verification

Version 1.9.16/build 141 was built from
`ea8506553ec99d3fbf98d41953e0466ae728d8fe`, tagged `v1.9.16` and published at
https://github.com/knightfolk/Bloomy/releases/tag/v1.9.16.
The earlier local build-140 candidate remains preserved; its archive does not
contain the later source changes and was not reused for this release.

## Exact source and distribution bytes

- The exact-commit Swift run passed 1,519 app/telemetry tests, 21 protocol tests
  and 28 host tests: 1,568 reported tests including seven explicit opt-in skips.
  All 17 packaging tests passed. Release compilation completed in 19.44 seconds.
- Sparkle's Downloader/Installer XPC services, Updater app, standalone Autoupdate
  executable and framework were signed inside-out before the containing app.
  Developer ID Application identity `5P2LWPPWRN`, hardened runtime and secure
  timestamps were inspected. Deep strict signature verification passed.
- Apple notarization `11931d10-0d4d-441b-a6b0-426ce5508d4d` returned **Accepted**.
  Stapling, ticket validation and Gatekeeper assessment passed. Gatekeeper reports
  **Notarized Developer ID**. The final distribution ZIP was created after stapling.
- `Bloomy-1.9.16-mac-arm64.zip`: 9,738,209 bytes, SHA-256
  `4284e0bb41c41b19c6ca6d45c4cecdec114fa164275e38d8b2cef385cf440ee5`.
  GitHub's ZIP, checksum-file and manifest sizes/digests matched the local final
  files before publication and were checked again after publication.
- The signed appcast item specifies build 141, version 1.9.16, macOS 14,
  arm64, the exact final archive length and HTTPS asset URL. All 26 older feed
  items were preserved when inserting the generated new item. The configured
  historical feed URL returned HTTP 200 before publication.
- Packaged automatic checks and installation remain off by default. Existing
  opt-ins were not rewritten. The main executable is arm64 and resolves Sparkle
  through its in-app framework search path.

## Isolated updater checks and protected runtime

Fresh clone-on-write copies of the signed/stapled build-140 baseline were used
for each scenario. The localhost-only harness served the exact final ZIP.
All four scenarios passed:

1. Invalid update signature: Sparkle error 4005; baseline build 140 retained.
2. Immediate installation: build 141 installed with a valid signature and
   accepted Gatekeeper assessment.
3. Deferred installation: build 140 retained while the disposable target ran;
   build 141 installed after that target terminated.
4. Installation/relaunch: build 141 installed, disposable target relaunched
   with a new PID, signature and Gatekeeper checks passed.

The target is the existing synthetic AppKit `QuitTarget.app`, passed to Sparkle
CLI's `--application` option. Its termination uses SIGTERM on only its owned PID.
This proves installer timing and target relaunch, not Bloomy's native Quit or
real dirty-editor callback/resumption integration. Those remain separate from
the actual-delegate protection tests and the bounded native cleanup/editor
reviews. No production termination or replacement was used for these gates.

The full gate window preserved app preferences except `SULastCheckTime`, provider
configuration, installed executable/Info hashes, and exact process/start
identities: installed Bloomy PID 61760, provider 63387 and watchdog 63393. The
provider stayed running from the verified internal model cache. The test server
and owned target stopped; private preference snapshots were removed.

Evidence is retained in `.build/release-v1.9.16-141/`, including the final
manifest, notarization/signing logs, uploaded asset verification, exact generated
feed and `upgrade-test/public-summary.json`. Test/build logs are
`/tmp/bloomy-1.9.16-exact-tests.log` and
`/tmp/bloomy-1.9.16-exact-release.log`.

## Scope that remains open

The native source review spans the focused checkpoints in
`APP_POLISH_OPTIMIZATION_PLAN.md`; the final signed/unknown Earnings review is
`EARNINGS_SIGNED_UNKNOWN_NATIVE_REVIEW_20261003.md`. The compiled production
sources have not changed since those final rendered checks, apart from release
metadata. Review fixtures are inert and are not claimed as production serving
or universal screen/accessibility proof.

The full native completion matrix, actual VoiceOver, comparable current-release
whole-app performance profiling, long-duration GPU protection and native
production Quit/updater/editor integration remain open. The installed app was
preserved over potential unsaved work; publishing this release does not mean it
has been installed there. This is a distribution checkpoint, not completion of
Kevin's ongoing polish and efficiency goal.
