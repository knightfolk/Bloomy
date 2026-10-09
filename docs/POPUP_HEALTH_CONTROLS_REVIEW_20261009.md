# Health and logs inside the popup

The popup's More menu now opens Health & Logs directly. The existing readiness,
source freshness, reported issues, model-load history, thermal details and logs
are available without navigating the dashboard. Readiness recommendations open
the existing Models or Hosting panel inside the same popup. Their retained
drafts and lifecycle confirmation guards remain owned by the original stores.

Health accepts an explicit popup visibility input. Its five-second display
schedule and expanded thermal presentation follow that surface; ordinary
dashboard Health retains its existing dashboard lifecycle. The change adds no
provider command, acquisition loop or sensor subscription. The popup supplies
its own fixed title and Done control; Health omits its duplicate large heading
and uses compact padding. Logs retains its filters, selected-event details and
review-before-save export.

## Verification

Task-owned evidence is in `.build/popup-health-control-review-20261009/`.
The baseline is `0381351`, with its original popup source and native More menu
retained. Independent read-only review identified the missing diagnostic route,
then found no actionable issues in the final routing or visibility changes.

The focused Release run passes 18 tests in four suites. The new regression checks
all six combinations of dashboard visibility and explicit/default popup
visibility against Health's actual schedule: hidden has one finite entry,
visible retains its five-second cadence. Existing native display-clock and
Health rendering tests also pass, including no unexpected telemetry acquisition.

The final serial Release run reports 1,852 app tests in 233 suites, plus 21
protocol and 28 host tests, passing with seven existing opt-in skips. The 49
fixture-staging checks pass. All finite test and build processes finish with
exit zero. The optimized synthetic review app matches all 142 recorded product
source hashes and passes deep, strict review signature verification. Its
executable SHA-256 is
`6b391ee9bee231dbe4ef9d766f9515f161368aecba8433eba6e6f6ee045b2276`.
This is review signing, not notarized distribution.

## Native computer-use review

- More contains Health & Logs alongside the existing operational controls.
- Current on-demand model evidence is shown truthfully; its Models action
  replaces Health with the model panel. Done returns to the popup.
- Missing/expired authorization remains explicitly unconfirmed. No repair or
  serving success is inferred from a connection observation.
- Logs search narrows to six delayed-refresh events. Selecting one exposes its
  full timestamp, source and message; scrolling reaches the complete detail.
- Preview export shows that frozen six-event snapshot. Save stays disabled
  before review. Close returns to the same filter and selected event; no export
  file is saved and no information is transmitted.
- Stopped-provider evidence offers Hosting. The action replaces Health with the
  existing Hosting editor; Done returns normally. Apply is not invoked.
- Dark Health and Logs render at a 360-point popup budget. The fixed Done and
  segmented view selector remain visible while the content scrolls. Source
  freshness, lower disclosures and expanded synthetic thermal readings are
  reachable.
- Long unavailable-source reasons start collapsed and expand to fully wrapped,
  selectable diagnostic text inside the compact viewport. Unavailable readings
  remain unknown rather than becoming zero or current.

The isolated app uses synthetic provider, account, logs, fan and temperature
data; Mac identity and macOS thermal state are actual. The actual provider is
not started, stopped, swapped, nudged or otherwise changed for this review.

## Limits and handoff

The native Window menu exposed Minimize as disabled during the attempted
dashboard-hidden check. Its evidence is retained. A menu Cancel reference became
ambiguous and Escape did not dismiss that menu; selecting the review
window through its native Window menu returned normally. No forced-focus or
visibility override was added, and this does not qualify an actual hidden-window
clock run. The independent visibility regression above is schedule evidence.

The earlier model keyboard activation boundary, genuine-occlusion and dialog
pixel gaps, broader accessibility/large-text and whole-app resource measurements
remain open. The current review app replaces the previous task-owned review
process and is left at Overview for the pending foreground check. Installed
Bloomy and the provider configuration remain unchanged. No push, installed
replacement or release is performed.
