# iOS Companion Candidate Operations

The companion is a source-level candidate and remains **Coming Soon** in the
shipping app. These instructions exercise a synthetic Mac host only. They do
not install a service, change provider settings, start the provider, or use a
real Darkbloom account.

## Current boundary

The candidate includes:

- a portable, versioned, size-bounded protocol;
- TLS 1.3 with a pinned host identity and explicit client authentication;
- expiring QR invitations and a persistent paired-device identity;
- signed, replay-protected, revision-checked control proposals;
- bounded session, pending-command, replay, frame, and operation state;
- iPhone views for status, models, performance, earnings, settings, provider
  lifecycle, live model application, and Mac app lifecycle;
- a synthetic Mac fixture that auto-approves enrollment and never invokes the
  live CLI or app.

The production per-user helper, SMAppService packaging, persistent operation
journal, durable audit log, and real Control telemetry projection remain release
gates. Until those are implemented, the companion must not be presented as a
background remote-control service.

## Remote access

The first release requires the user to install and sign in to Tailscale on both
the Mac and iPhone. Darkbloom does not embed Tailscale or distribute enrollment
keys. Native Darkbloom TLS and pairing remain mandatory above the Tailscale
route, so tailnet membership alone does not authorize a companion.

The evaluated embedded adapter remains excluded because its repeated-connection
transport integrity regression is unresolved. A standalone public relay would
be a separate hosted service with additional authentication, abuse, and
operations work.

## Build and test

From the repository root:

```bash
swift test
swift build -c release
xcodegen generate --spec CompanionApp/project.yml
xcodebuild \
  -project CompanionApp/DarkbloomCompanion.xcodeproj \
  -scheme DarkbloomCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  test
xcodebuild \
  -project CompanionApp/DarkbloomCompanion.xcodeproj \
  -scheme DarkbloomCompanion \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The generic-device build compiles the physical-device Secure Enclave paths.
It does not prove Keychain access groups, signing, entitlements, camera scanning,
local-network permission, or Tailscale behavior on hardware.

## Synthetic pairing smoke test

Choose a Mac address reachable from the simulator. Loopback is appropriate only
when the client shares the Mac network namespace.

```bash
DARKBLOOM_FIXTURE_HOST=192.168.1.20 \
  swift run DarkbloomCompanionFixtureHost
```

The fixture prints a `dc-pair:1:` value and atomically writes the same value to
`/tmp/darkbloom-companion-fixture.json`. In the simulator, open Darkbloom, choose
the paste/manual pairing path, and paste that value. The fixture intentionally
auto-approves the enrollment so the smoke test can run without an unreleased Mac
pairing UI.

Verify that the dashboard shows Fixture Mac, connected provider/app/helper
state, the Fixture Model, 42.5 tok/s, 23% whole-Mac GPU, and USD 12.34 account
earnings. Exercise settings and controls only against this fixture. Stop the
fixture with Control-C and confirm the companion reports stale or disconnected
data instead of presenting old telemetry as current.

## Production release gates

- Bundle and sign a user-scoped helper, register it through SMAppService, and
  prove quit/reopen plus restart recovery without a second runtime owner.
- Project live sanitized telemetry through the host coordinator and route every
  provider/config/app mutation through one serialized owner.
- Persist accepted operations and a redacted audit history across helper crashes.
- Add an explicit Mac approval and revocation UI; remove fixture auto-approval
  from every production target.
- Pass physical-iPhone pairing, Secure Enclave, camera, LAN, and external
  Tailscale tests using release entitlements and signatures.
- Complete signed/notarized packaging, update testing, accessibility review,
  threat-model review, and release evidence before removing **Coming Soon**.

Never place provider bearer tokens, account credentials, phone or host private
keys, invitation secrets, prompts, responses, or arbitrary configuration text
in QR payloads, companion snapshots, logs, or evidence.
