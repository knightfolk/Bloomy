# Closed-popup fitting investigation

October 9, 2026. This is a diagnostic observation and next-experiment boundary,
not a verified optimization, matched CPU comparison or closed-window gate.

## Installed observation

The live app is Bloomy 1.9.19/build 144, PID 7234. Executable SHA-256:
`57f9d4b2fa9f98bf1dbca607b5039b6fe4c3302adf671d0ab1ffce77b66911f7`.
It differs from the newer local review builds; these measurements do not qualify
the checkout or establish a before/after source comparison.

The initial accessibility state showed the production popup open. Dismissing it
revealed Overview. The dashboard was minimized through its native control,
then restored through Open Dashboard after measurement. No edits were made.
The two 30-second observations use process CPU-time deltas, not instantaneous
percentages or whole-Mac CPU. Calibration against getrusage passed: 0.9981773
converted seconds versus 0.9981800 reference seconds.

| Recorded condition | One-core CPU | Median RSS | Median footprint | Interrupt wakeups/s |
| --- | ---: | ---: | ---: | ---: |
| Popup open; retained Overview | 11.459% | 179,634,176 bytes | 115,590,272 bytes | 28.000 |
| Popup dismissed; dashboard minimize requested | 13.224% | 186,925,056 bytes | 117,539,992 bytes | 33.728 |

There is no native continuous visibility report for this installed process.
The minimize action and accessibility transitions do not establish an unchanged
hidden condition throughout the second interval. Live provider traffic and
other Mac work continued and differ across intervals. The difference is not an
optimization regression, improvement, battery estimate or matched workload.

Separate five-second native stack samples contain SwiftUI layout and
`PopupScrollView.measureDocument()` in both observations. Sampling was outside
the CPU observation windows. This identifies work in those samples; it does not
measure its sustained frequency or prove that fitting caused the CPU totals.

Evidence: `.build/popup-resource-review-20261009/installed-visible.json`,
`installed-minimized.json`, `calibration.json`, and the two
`installed-*.sample.txt` files. These are read-only observations. No provider
lifecycle command, inference, model change, download or installed replacement
was performed.

## Current source finding

Independent read-only review confirms that the current popup hierarchy remains
mounted when closed. `PopoverRootView` and `MonitorPopover` observe live stores;
`isVisible` stops clocks and selected reads but does not suspend observation.
Bridge updates replace the hosted root and schedule fitting. Layout proposals
call `measureDocument()` without a presentation-state guard. The retained
dashboard likewise keeps its selected hierarchy mounted when minimized.

This explains a plausible source of hidden work, but the installed source has
not been shown to match the checkout. No source fix is claimed here.

## Next bounded experiment

First isolate native fitting while retaining the complete popup hierarchy:

1. Add explicit presentation eligibility to the fitting controller and bridge.
2. Cancel queued fits on close, pause automatic preferred-content sizing, and
   answer hidden proposals from retained geometry.
3. Enable fitting and perform one immediate current-content/current-screen fit
   **before** reopening. Production prepares geometry before `popoverWillShow`,
   so merely checking the existing visible flag would skip the initial fit.
4. Preserve document identity, scroll offset, sheets, confirmations and drafts.
   Monitoring, recording, alerts, automatic actions and update guards continue.

Compare actual fitting calls and time under the same publication sequence, then
qualify rapid reopening, tiny viewports, disclosure changes, nested sheets,
retained edits, graceful lifecycle confirmations and updater blocking. Do not
unmount the popup solely to suppress observation: local editing and presentation
state would need an explicit retained session first. Fitting isolation also does
not eliminate all SwiftUI body invalidation. Broader whole-app performance and
native motion/occlusion qualification remain open.
