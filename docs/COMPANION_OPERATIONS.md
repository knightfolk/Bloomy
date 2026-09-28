# Companion operations

The native companion code is a development feature. It is not part of the
current downloadable Mac release and does not install or register a background
service.

## Current verified scope

- Versioned, bounded companion messages and length-prefixed frames.
- Expiring QR invitations, per-device P-256 identity, pinned TLS, capability
  checks, signed prepared commands, replay protection, and revocation.
- An iPhone registry keyed by random host identity, including migration from the
  earlier single-host preference. Duplicate display names remain distinct.
- Selected-host command routing, host-attributed freshness/errors, a read-only
  fleet view, and bounded fixed-code alert history.
- A helper core with one process-held ownership lock, a durable SQLite operation
  intent journal, uncertain crash recovery without automatic redispatch, capped
  audit records, an allowlisted snapshot adapter, and exact signed-app identity
  checks.
- User-installed Tailscale on the Mac and iPhone for private remote reachability.
  LAN routes use the same enrolled host identity and certificate pin.

## Coming soon before release

- Package and sign the helper inside the Mac app, add the service declaration,
  and expose local registration, QR approval, capability editing, and revocation
  UI. Registration must remain explicit and must never occur on app launch.
- Connect the helper to the live `TelemetryService`, `ProviderControlService`,
  configuration store, app lifecycle endpoint, and persistent paired-device
  registry. The current helper executable deliberately has no listener or live
  provider authority.
- Validate pairing, Keychain identity, local-network permission, Tailscale routes,
  background suspension, revocation, and command reconciliation on physical
  iPhones and a signed Mac bundle.
- Add richer job and temperature fields and a sanitized recommendation evidence
  page to the portable snapshot. The current fleet UI labels unavailable fields
  instead of deriving them from unrelated counters.

Automatic model mutation is outside this release. Recommendations are read-only
and replayable; they do not dispatch provider commands.

## Local verification

Run the package and iOS suites without enabling a service:

```bash
swift test
xcodebuild -project CompanionApp/DarkbloomCompanion.xcodeproj \
  -scheme DarkbloomCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

For a local synthetic pairing session, run
`swift run DarkbloomCompanionFixtureHost`, then launch the simulator app with
`--auto-pair-fixture --fixture-pairing-code <printed-code>`. The fixture uses
ephemeral identities and synthetic telemetry. It must never be treated as
physical-device or release-helper proof.
