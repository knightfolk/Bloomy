# Popup Hosting recovery review — October 4, 2026

Bloomy's popup now displays the coordinator hostname from Darkbloom's actual
WebSocket report. Its Hosting action dismisses the nested detail before asking
the parent popup to close and opening the dashboard Hosting page.

## Changes

- Coordinator display accepts HTTP, HTTPS, WS and WSS reports, retaining the
  existing length, hostname and credential checks. It exposes only hostname
  and optional port; path, query and fragment are omitted. Local API address
  validation remains HTTP/HTTPS only. A displayed coordinator is not a
  reachability claim.
- Hosting navigation waits for child disappearance and yields once before the
  existing parent handler. Done still dismisses only the detail. This adds no
  polling or provider operation.
- The inert native fixture supplies a fake WSS coordinator with path/query
  canaries. Offline and local-only scenarios omit the coordinator.

## Verification

- The new WebSocket regression first failed on three expected host results.
  Final focused Hosting checks pass, including both appearances at 366- and
  526-point content widths with the existing height bound.
- Full Release checks report 1,595 telemetry/UI, 21 protocol and 28 host tests
  passing (1,644 total), with seven existing opt-in skips. Final log:
  `.build/popup-hosting-navigation-verified-full-20261004.log`.
- The initial sizing run failed four mixed numeric-type comparisons although
  the printed widths matched. Explicit CGFloat comparison fixes the test;
  no product dimension was changed or height limit relaxed. An initial native
  fixture build also failed on initializer argument ordering and was corrected
  before launch. Both rejected candidates remain separate from final proof.
- The final optimized native fixture built without compiler warnings/errors.
  Its manifest matches 119 source hashes; executable SHA-256 is
  `eb2cb213eaa4cf5bdc87ab6b4c985b67a49326e26c4624e8d64704f4ff232c29`.
  Bundle: `.build/popup-hosting-recovery-native-r2-20261004/Bloomy Dashboard Fixture.app`.
  Verification: `.build/popup-hosting-recovery-proof-20261004/source-verification.json`.

## Native observations

Computer Use inspected the actual SwiftUI views in the inert review app:

- Light and dark coordinator details show only `coordinator.example:8443`.
- Before the fix, activating Hosting left both popovers open; manually closing
  them allowed navigation to finish. After the fix, one pointer activation
  dismisses both and selects Hosting automatically. This also passed after
  reopening from a normal Done dismissal.
- Configured Fleet + local details preserve the unverified qualifier, local
  address and API-key-after-Apply guidance through Refresh. No Apply was used.
- An empty-discovery report became unknown while the detail stayed open, then
  Refresh restored the fresh empty result. The observed hold was 54 seconds,
  14:45:54–14:46:48 UTC.
- A reported local endpoint expired while open, retaining its original address
  and checked time. Refresh supplied a new checked time and fresh report.
  The observed hold was 62 seconds, 14:48:47–14:49:49 UTC; the original report
  was already about 22 seconds old when that hold began. These are observed
  holds, not claims of exact expiry scheduling.
- Offline inspection shows no coordinator, a Start control, unavailable
  Autopilot and neutral missing Earnings. Fake Fleet-only preference restored.

Observation times/states are transcribed in
`.build/popup-hosting-recovery-proof-20261004/observed-expiry.json`.
Transient CUA binding/cropping problems were resolved by rebinding to the exact
review-app path; they are not counted as product failures or recovery proof.

## Limits and handoff

Production Bloomy, provider and recovery processes were preserved; provider
configuration remained unchanged. No real hosting exposure, credentials,
models or inference were changed. Review signing is not notarized distribution,
and the installed app was not updated.

Spoken VoiceOver, physical wheel/other displays, real endpoint integration and
the broader polish/performance matrix remain open. Offline Hosting also showed
an Update CLI prompt with unavailable CLI version; that is a remaining lead,
outside this checkpoint. Kevin requested stopping after the next push, so this
verified source checkpoint is the stopping boundary, not completion of the
broader improvement goal.
