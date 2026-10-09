# Model management from the popup

Manage now puts real model controls before an optional What-if forecast.
The forecast starts collapsed and keeps its selected runtime visible in the
disclosure label. Its slider, calculations, account-attribution explanation and
estimated-only qualifications remain available when expanded. Runtime values
stay owned by the existing parent and keyed by canonical model ID; expanding a
disclosure does not change provider selection.

Detailed demand now uses the same retained reading and snapshot-wide ruler as
compact cards. An expired or failed read shows Demand stale, Last known counts
and a hollow marker instead of discarding available history as unavailable.
Missing readings remain unavailable. Opportunity grades still receive only
fresh demand. Speed labels now say Average speed today and samples today,
matching the calendar-qualified input.

## Evidence and review

Task-owned evidence is under `.build/model-management-polish-review-20261009/`.
The baseline is `5399c1d`; the exact before source and optimized mixed-history
native capture are retained. The baseline's age-expired detail panel showed
Demand unavailable despite retained compact-card history.

The first native visual pass confirms controls before the collapsed forecast,
an expanded 25% / 6-hour scenario, $0.1500 estimated net per day, unchanged
attribution qualifiers and visibly retained stale demand. That intermediate
bundle is not evidence for the final accessibility-label change.

Independent source review found a reused Details scroll target in the new
disclosure. Forecast now has its own focus target; Details keeps its original.
The review found no other actionable regression. Native inspection subsequently
caught an explicit label hiding selected hours from accessibility; the override
is removed, allowing the native combined label to retain those hours. The finite
keyboard proof now opens the optional forecast before seeking its slider and
requires separate Forecast and Details targets.

The initial focused test compilation required testable access to the telemetry
model initializer. Its corrected run passes 39 tests in five suites. The first
full serial Release run reports 1,851 app tests in 233 suites plus 21 protocol
and 28 host tests, all passing. This run predates the final label adjustment;
the final source-aligned results are recorded below.
The 49 native fixture-staging checks pass. All failed/intermediate logs remain
retained.

The final optimized bundle matches all 142 recorded product source hashes,
includes the exact updated keyboard-proof source, and passes deep, strict review
signature verification. Its executable SHA-256 is
`85a0b74d30cdb80d2c9c647778daafa4e9f4b5409e08cc08804c1fcfc67b13b3`.
Source-aligned focused checks pass: 39 tests in five suites. The final serial
Release run passes 1,851 reported app tests in 233 suites (seven existing opt-in
skips), 21 protocol tests and 28 host tests; its finite process exits zero.

Final computer-use evidence confirms dark popup model-management navigation,
the collapsed 0% label, expansion to a 25% / 6-hour forecast, and the retained
25% label in accessibility after collapsing. Opening the same canonical model
from Models retains that scenario; Qwen independently stays at 0%. Light native
inspection at a 360-point dashboard sheet budget shows Last known demand on the
same scale, reachable model controls after scrolling and an always-visible
footer Done that closes the sheet. Qwen shows 52.7 tok/s and 116 samples today.
This compact-height proof is for the dashboard host; the popup review uses its
normal screen-constrained sheet. It does not claim a constrained popup sheet.

## Native focus boundary

The first updated native keyboard proof stops at owned-window activation before
any of its four semantic cases. The app reports inactive, the target is not key,
and cleanup passes. Raising and clicking the review window did not change its
inactive appearance. The Dock control surface timed out. No unchanged proof
retry, forced-focus fallback or activation-policy modification is used.

AppKit documents activation as cooperative; a window being raised is not proof
that its app has become active. See [Apple's activation documentation](https://developer.apple.com/documentation/appkit/nsapplication/activate%28%29).
Kevin has been asked to activate the synthetic review app while independent
visual and regression verification continues. This is an open focus-proof
qualification boundary, not a passing check or a claimed product regression.
The final keyboard traversal has not been retried without changed activation
evidence. Its source-aligned synthetic review app is left open at Overview for
that pending check. Both intermediate review apps and all finite test/build jobs
have exited; the installed app and provider configuration remain untouched.

## Remaining gates

The genuine-occlusion and dialog-pixel gaps, broader accessibility/larger-text
qualification, comparable whole-app resource measurements and distribution
checks remain open. No provider mutation, model swap, inference, download,
installed replacement, push or release is performed.
