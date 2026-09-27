# Secure iOS Companion Vertical Slice Evidence

Date: 2026-09-27. App branch: `codex/cli-0910-integration`. CLI branch:
`codex/0910-lifecycle-fixes`.

## Proven candidate behavior

- A simulator paired with the synthetic Mac host from a `dc-pair:1:` invitation
  over pinned TLS 1.3 and authenticated with its persistent phone identity.
- The rendered Status view showed the synthetic provider, app, and helper as
  available; 42.5 tok/s; 23% whole-Mac GPU; and account earnings of USD 12.34.
- Models rendered Fixture Model as enabled, advertised, resident, and active.
- Control rendered provider Start, Stop, Restart, Apply saved models live, plus
  Mac app Open, Quit, and Relaunch. These actions were not sent to the live CLI.
- Settings loaded the revisioned provider draft and rendered concurrency,
  resident slots, startup preload, model enable/preload, staging, and save.
- Visual inspection found that the original authenticated server closed an idle
  session after ten seconds. The server now allows a bounded 300-second idle
  interval; a regression proves sequential authenticated requests, and a fresh
  simulator pairing loaded Settings after the former deadline.

The fixture uses synthetic telemetry and in-memory provider/app adapters. It
auto-approves enrollment for deterministic testing. It is not a production
background helper and cannot mutate the live provider.

## Verification

| Check | Result |
| --- | --- |
| `swift test` | Pass: 765 Control tests, 18 protocol tests, 16 host/transport tests; 799 total |
| `swift build -c release` | Pass |
| iOS Simulator `xcodebuild ... test` | Pass: 4 tests |
| generic iOS `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` | Pass; compiles physical-device Secure Enclave branches |
| Paired fixture/simulator smoke | Pass for QR invitation, authenticated connection, Status, Models, Control, and Settings rendering |
| CLI focused lifecycle/switch tests | Pass: 21 tests before the final runner hardening |
| CLI diagnostic/config/lifecycle regression selection | Pass: 8 runner tests plus 28 CLI lifecycle/config tests |
| `swift build --package-path provider-swift` | Pass, with existing dependency/exclude warnings |
| Full CLI test command | Runs through the prior missing-metallib crash; all 298 CLI tests pass, but the overall command remains red because existing `ProviderCoreTests` and `GPTOSSOptimizationTests` report 129 GPT-OSS prefill parity issues on the shared GPU |

The full CLI run is therefore not release-green. The failing GPU parity scope is
outside the lifecycle/companion changes and requires an exclusive GPU lane. It
was not pursued while the simulator and a separate local image generator needed
the machine. The prior SwiftPM XCTest metallib lookup failure was fixed in the
nested MLX source, and focused GPU factory tests now load the packaged metallib.

## Deep-review changes

- Proved that a stop received during standalone preload prevents listener bind.
- Derived every lifecycle mailbox from the overridden daemon-state directory,
  eliminating test leakage into the real `~/.darkbloom/lifecycle` directory.
- Extended restart dispatch/reconciliation to cover the CLI drain plus startup
  window and require fresh replacement process identity before success.
- Converted post-dispatch timeouts into uncertain outcomes instead of false
  failure/success claims.
- Bounded host pending commands, replay IDs, sessions, frames, and retained
  operation statuses; failed mutations remain queryable terminal operations.
- Bound production security/hardware subprocess capture, closed owned readers
  after the process exits even when a descendant retains pipe descriptors, and
  cached immutable per-process hardware discovery to prevent subprocess fanout.
- Removed an unused restart command builder that no production path invoked.

GLM-5.3 Max performed a read-only review through ZCode. Its actionable findings
about restart bounds/identity confirmation, ambiguous timeout reconciliation,
and proving listener non-publication were fixed. It made no repository edits.

## Coming Soon gates

- Signed, packaged user-scoped helper and SMAppService registration.
- Live telemetry/config/provider/app adapters with one persistent runtime owner.
- Crash-persistent operation journal and redacted audit history.
- Mac approval/revocation UI and removal of fixture auto-approval from production.
- Physical-iPhone camera, Keychain/Secure Enclave, LAN, and external Tailscale proof.
- Accessibility, signing, notarization, update, and release review.

No push, release, deployment, service installation, provider start by this
verification, provider setting mutation, real account access, or
embedded-Tailscale promotion occurred. The final process audit found that
launch recovery had brought the provider back after the prior pause. The native
graceful stop drained zero requests, received coordinator acknowledgement,
disabled auto-start, and a final provider/watchdog process check was clear.
