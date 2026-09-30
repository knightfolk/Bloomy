# Compact Models cards verification

The Models page shares the popup card component for model identity, residency, and metrics. It adds a dedicated network-demand row and keeps forecasts in the existing Manage/Details view. Hosting controls continue to stage selection and startup-loading settings.

Synthetic native SwiftUI renders were inspected at 300- and 400-point card widths and 640-, 1280-, and 1480-point page widths. Cards remain aligned, demand counts and actions remain readable, and the page uses one, two, or three bounded columns. An independent design review found no rendering defects.

A regression test checks current demand, unavailable model data, retained readings after a failed source refresh, expiration, and future timestamps. The full Swift test suite passed. Live app navigation confirmed the existing saved selection has no pending edits before preparing the update.

These checks do not claim an instantaneous demand stream: the page displays the latest polled network reading and its age.

Release 1.9.12 build 137 was built and tested from `3a2843e524e93bb444549a6b7ede327cc8bb0eed`. All 997 Swift tests and 17 packaging tests passed. A separate full run with every screenshot capture enabled aged an existing restart-test fixture beyond its ten-second freshness limit; the standard full suite and a focused screenshot/restart run passed. Developer ID signing, Apple notarization Accepted (`e2ebc42b-2ba4-444c-8cd5-63f9104cadc1`), ticket stapling, and Gatekeeper acceptance were verified. Final ZIP: 8,620,962 bytes, SHA-256 `85897c513d2efa0e592af5bce9e79b9d6ccbf0951c60c61c0decc1ef4368eff9`. Isolated signed updater gates checked normal 136-to-137 installation, invalid-signature rejection, deferred installation after a test target quits, and test-only relaunch. Results are retained in `.build/release-v1.9.12-137-r2/upgrade-test/results.json`. Uploaded asset digests matched local final bytes before publication.
