# Models feedback and Manage recovery — October 3, 2026

This checkpoint consolidates repeated model-control explanations and makes
Refresh failures visible in the open Manage sheet. It uses the existing SwiftUI
editor and preserves provider action guards and staged configuration.

## Behavior and regression coverage

The footer sanitizes and trims messages before comparing their visible text.
Identical messages appear once at their highest severity; distinct errors,
validation warnings and availability reasons remain separate. No blocker uses
the existing Apply Live explanation. Eight regression tests cover triple and
pairwise collisions, severity ordering, similar-but-distinct strings, whitespace,
sanitization, blank input and refresh suppression.

Manage shows the current read's busy state and sanitized error inside the sheet.
Model disappearance or a new error reveals the padded content top. Recovery
Refresh now stays beside Done in the persistent footer; it is disabled during
an operation and uses the existing draft-preserving read. A model restored to
the same catalog identity resumes the open editor without saving settings.
No periodic read, service, timer or provider action was added to product code.

The inert fixture adds temporary inventory hiding/restoration, one failed read,
and full public draft readback. Temporary hiding leaves saved configuration
unchanged. Recovery tests use Frozen settings, whose periodic control reads are
already paused; early Fresh attempts could consume the failure in a background
read and are not accepted as failed-button proof.

## Native comparisons

All inputs and rendered inspection use CUA against isolated fixture bundles.
No installed app replacement, provider lifecycle, swap, download, inference or
credential operation was used for UI evidence.

| Build | Observation |
| --- | --- |
| Native150 baseline | Product ModelManagerView matches the prior checkpoint. A failed sheet Refresh leaves no visible error, although the draft readback records the failure. Deep-scroll disappearance clips the heading's top inset. The unavailable-catalog footer repeats Provider configuration is unavailable. |
| Native151 | The sheet error becomes visible. Scrolling to the header button still removes the normal top inset. |
| Native152 | A padded top target repairs that inset and a finite 20-second read visibly shows progress. In a 620 × 360 sheet, recovery text pushes the content Refresh button partly below the viewport. |
| Native153 | Moving Refresh to the fixed footer repairs compact recovery reachability. Compact light/dark and 620 × 740 dark failure/retry/restore checks pass. Parent-window inspection rejects the footer layout: the new ideal-height modifier expands the split view beyond its hosting view. |
| Native154 | Removing only the feedback row's fixedSize modifier restores the compact parent footer and review controls in light/dark mode. Two distinct explanations remain visible, with the repeated configuration warning removed. Native accessibility still combines them under the first row identifier, prompting a concrete container per row. |
| Native155 final | Compact/wide light and dark unavailable-catalog footers fit with one error and one distinct warning. Returning to compact also fits. All five captures pass 11 native geometry checks, measuring the dashboard split, Save Changes and Apply Live with zero overflow. Compact light Manage failure/retry/restore retains the draft and open sheet; the restored Preload action still works. A finite 20-second read visibly shows progress in compact dark, then enables the persistent recovery action. Failure text and both footer actions fit in compact dark and full-height dark sheets. |

Native153's own AppKit trace measures a 1280 × 900 hosting view, a dashboard
split view at [0, -149, 1280, 1083], and footer controls below its visible bounds.
A fresh Native150 comparison fits correctly. This establishes a regression in
the rejected candidate, not an external capture limitation or an accepted
product layout. Rejected and intermediate builds are not final-source proof.

Native150, Native153 and final Native155 readbacks independently establish identical public draft
fields, saved settings, store identity and sheet window number before failure
and after restoration. The failure records Could not refresh model controls;
restoration clears it. Save and lifecycle counts remain zero. Native155's restored
Preload switch also stages the next explicit change without writing settings.

## Verification boundaries

The final product source passes 1,552 reported tests: 1,503 app tests,
21 protocol tests and 28 host tests. Seven opt-in tests were skipped. Release
compilation completes in 46.98 seconds. Logs are
`/tmp/bloomy-model-feedback-final3-tests-20261003.log` and
`/tmp/bloomy-model-feedback-final3-release-20261003.log`.

The final Native155 manifest matches all 109 source hashes, the actual binary
and the tested Debug telemetry archive, with no mismatches. Binary SHA-256 is
`9be77c221e3e84ef61d8cd89488d540be95f02265c01b2ff8b111ac49a630465`.
The bundle is `.build/native-dashboard-fixture-20261003-155/Bloomy Dashboard Fixture.app`.
Its review session ends `919C6AAF-9F8E-45FA-97C2-C850315DC648`. Final normal Quit
leaves no review process. Production remains PID 61760 with its October 2
12:55:28 start time and unchanged binary SHA-256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`;
provider/watchdog PIDs 63387/63393 keep their October 3 01:45:06 start times.

The bounded native geometry helper measures current content, dashboard split
and identified footer-control rectangles; scroll documents are intentionally
excluded. Its standalone unshown AppKit regression accepts contained geometry,
rejects the observed Native153 rectangle with 149-point overflow, and checks a
Codable round trip. Reproduce it with:

```sh
xcrun swiftc Tests/NativeUI/ModelFeedbackLayoutProof.swift \
  Tests/NativeUI/ModelFeedbackLayoutRegression.swift -o /tmp/bloomy-feedback-geometry
/tmp/bloomy-feedback-geometry
```

Manifests, public synthetic draft readbacks, all five geometry results, the
standalone test output and rejected layout trace are retained at
`/tmp/bloomy-model-feedback-review-20261003/`. Source checks preserve per-kind
message identity, but macOS still combines adjacent diagnostic text in its AX
tree; the concrete container does not establish separate spoken elements.
Whole-app polish, actual VoiceOver,
long diagnostic wrapping, broader source/display states, live provider behavior
and distribution remain separate open gates.
