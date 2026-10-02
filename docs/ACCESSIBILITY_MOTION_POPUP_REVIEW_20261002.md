# Accessibility, motion, and popup review — 2026-10-02

Local validation checkpoint for the current polish work. Native accessibility and popup sizing have useful proof; the complete motion gate remains open. These are isolated synthetic review builds, not production-launch or distribution proof. Production PID 31677/build 140 and its unsaved state were preserved; the provider and recovery watcher remained stopped. No real provider start or inference was needed.

## Verified behavior

- Native builds 34–39 and 41 passed all three Model Manager accessibility cases: contextual card actions and checkbox names/states, separate card draft edits, and Manage-sheet preload editing retained after closing the sheet. Each case requires actual native accessibility controls and real press actions; missing controls fail.
- Both Metrics accessibility cases passed in those native builds. Empty and stale data each expose exactly one `AXButton` named **Refresh metrics**, identifier `activity.metrics.refresh`, and one native press invokes the injected refresh callback exactly once. Stale observations produce no measured-speed points.
- Activity preserves its existing mark values, selected-model attribution, base rewards, signed stacks, and unknown gaps. Shapes, line patterns, sparse numbered badges, and matching compact legends provide cues beyond color. Area badges use a `ChartProxy` geometry overlay at existing plotted segment positions; transparent anchor marks failed visible review and were removed. Metrics has one short-name legend, stable canonical series identities, and full-name hover/accessibility text.
- Native 35 measured popup content at **560 × 604 → 560 × 708 → 560 × 604** while expanding and collapsing Available models. Hosted bounds, fitting size, and popover content size matched; each measured content rectangle fit the current screen. This verifies dynamic sizing on that screen, not every display height.
- Native 36 direct computer-use inspection verified model visit logos in dark/light grayscale review. These are recorded visual observations; no saved screenshot artifact is claimed.
- Native 39 direct computer-use inspection again verified a visible popup header and Available models expanding and collapsing from the genuine menu-bar anchor. These screenshots were inspected in the session; the measured sizing figures above come from Native 35's geometry report.

## Checks and remaining motion failure

| Check | Result | Evidence |
| --- | --- | --- |
| Full SwiftPM run 03 | **1,264 tests passed:** telemetry 1,215/160 suites in 29.784 s; protocol 21/5 in 0.013 s; host 28/9 in 11.709 s | `/tmp/bloomy-efficiency-20261001/accessibility-motion-full-03.log` |
| Release build 01 | Completed in **52.68 s**, before the later menu-bar close fix | `/tmp/bloomy-efficiency-20261001/accessibility-motion-release-01.log` |
| Focused run 08 after close fix | **52 tests/6 suites passed in 4.280 s** | `/tmp/bloomy-efficiency-20261001/accessibility-motion-focused-08.log` |
| Native 37 motion | **12/14 passed**; genuine cover occlusion and rapid close/reopen failed | Native 37 `motion-lifecycle-proof.json` |
| Native 38–39 | **13/14** each; rapid close/reopen passes. Cover case still fails because the target remains reported unoccluded, including with explicitly opaque target content | Runtime report directories below |
| Native 41 | **13/14 motion cases**, all 3 model cases and both chart cases passed. The strict genuine-occlusion prerequisite still failed with a separate owned process; overall native proof remains failed | Native 41 terminal reports below |
| Release build 02 | Completed in **50.81 s**, after the close fix; no compiler warnings/errors | `/tmp/bloomy-efficiency-20261001/accessibility-motion-release-02.log` |

The occlusion case is a failed prerequisite, not successful hidden-window animation proof. No overall native-proof pass is claimed while it remains unresolved.

Native 41 used distinct child PID 18502 and target PID 18489. WindowServer confirmed the child's opaque window was ahead of and fully covered the target. The target's actual occlusion state still retained `.visible` (raw value 8194). The cause remains unknown; neither same-process ownership nor transparent target content explains the observed result. The child closed its window on the parent's EOF request and exited normally with status 0. All test windows/processes were closed after review. Further cover variants were stopped rather than weakening the assertion.

The other motion cases require real compositor angle advancement, one clock after repeated updates, self/ancestor hide and restore, ordering out and restore, detachment, same-window and rapid close/reopen, stationary preference round trips, immediate inactive stop, teardown, and the parent label's stationary input. The close fix uses one coalesced weak deferred reevaluation, without a recurring timer. An independent read-only review found no actionable lifetime or eligibility issue.

## Provenance and reproduction

Fixture manifests are `.build/native-dashboard-fixture-20261002-{34,35,36,37,38,39,41}/fixture-manifest.json`; each records staged production source hashes, telemetry-library identity, binary hash, and compiler command. Native 41's 85 source hashes and binary matched its compiled snapshot; binary SHA-256 was `7061ad232f08d8e4a86dee739460d0626729be6be55f39fdf2cfe0973dafa23a`. Rebuild after source changes; an earlier manifest does not validate later edits. Native 40 failed Swift 6 type checking because a cleanup task returned a non-Sendable dictionary. Native 41 fixes only that helper boundary by retaining evidence on its actor and returning Void from the task; its build completed without warnings/errors. Production source was unchanged by this repair.

Runtime evidence uses the prefix `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/`:

- Native 35: `BloomyDashboardFixture-1BDB7A08-3C8E-4987-8195-584DBDA90EB2/popup-geometry.jsonl`.
- Native 36: `BloomyDashboardFixture-76E40AFE-4C91-4763-B2C3-17BCD0EA7D0A/`.
- Native 37: `BloomyDashboardFixture-8BF39600-D023-4B68-A8F6-F8F73BD14EAC/`.
- Native 38: `BloomyDashboardFixture-C5FC37BD-E577-41D5-A010-3A7F166B56C2/`.
- Native 39: `BloomyDashboardFixture-F30DD14E-D8B1-43B7-A22F-B255C5073DD3/`.
- Native 41: `BloomyDashboardFixture-38A00174-F076-4474-8F21-2FBC27487B2E/`.

For a fresh reproduction, use the existing debug telemetry products and build `Tests/NativeUI/build-dashboard-fixture.py --output` into a new task-owned directory. Open that fixture's **Bloomy Dashboard Fixture.app**, wait until its synthetic stores are ready, then invoke **Native proof**. The fixture runs finite `MenuBarMotionProof`, `ModelManagerAccessibilityProof`, and `ChartAccessibilityProof` helpers under normal `NSApplication.run()`, retaining the dashboard window while their owned test windows close. Read all terminal reports: `motion-lifecycle-proof.json`, `model-manager-accessibility-proof.json`, `chart-accessibility-proof.json`, and `native-proof-result.json`. Require the expected case counts and terminal success; exit status, a running report, or a partial count alone is insufficient. Helpers yield to the normal run loop, never dispatch the application event queue manually, and never terminate the process themselves. Quit the owned fixture normally after collecting evidence.

Earlier SwiftPM accessibility-host checks were invalid proof: visible `NSHostingView` containers exposed no SwiftUI virtual controls in that host. The checks moved to the native fixture rather than accepting zero matches or skipping assertions. A premature SwiftPM exit without a terminal test summary also did not count as a pass. Pure chart identity/stack/gap tests remain in SwiftPM. The resource-panel test now acknowledges actual appearance and drives only its own hosted layout during bounded lifecycle waits, with stage/occlusion diagnostics and unchanged sampling assertions.

## Still unproven

Actual VoiceOver narration/focus order; toggling the system Reduce Motion setting; reliable genuine cover occlusion; short-screen popup fit with expanded content and notices; current production launch, privacy/TCC and removable-drive access; and signed/notarized updater distribution remain separate gates. Fixture-injected motion preferences and inert stores do not establish those outcomes. Release build 02 verifies compilation of the current product changes, not launch or distribution.
