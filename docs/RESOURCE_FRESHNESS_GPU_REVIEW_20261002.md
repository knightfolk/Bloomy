# Resource freshness and GPU cancellation — 2026-10-02

Local checkpoint for the ongoing native polish and efficiency work. The installed production app and its unsaved state were preserved. The real provider and recovery watcher stayed stopped. These checks use injected values; they require no provider startup, inference, fan-policy write, or real GPU registry read.

## Observed presentation defects

Native 43C, the prior `0db8edd` snapshot, exposed two incorrect descriptions in the compact Stale Overview:

- The thermal card showed a Stale badge but still said “Fan helper is active while the provider is serving.” Its helper journal and CLI capture were fifteen minutes old.
- The request card visibly showed `0 / Idle / Last report`, while its accessibility label said “No inference is currently active” and omitted Last report from its accessibility value.

The request card now derives its qualification from the original daemon source and the existing `HealthPresentation` age policy. Retained observations preserve their numeric/mode interpretation, but the spoken value and help explicitly describe the last report and unknown current activity. An unavailable source displays `— / Unavailable` without a Last report badge. Missing required `inference_active` data still fails decoding rather than becoming idle zero.

Thermal presentation independently evaluates the 45-second CLI capture and 15-second helper journal. Old helper posture says Last observed; invalid or future evidence is Unverified. A current disabled helper is described as disabled even if its provider-active flag is true. Current diagnostics can replace corresponding expired fields without claiming current helper activity. Each retained field remains visible and accessible with its qualification; these changes add no polling task.

Independent review caught a further fan-specific defect: valid CLI fan metadata may omit `actualRPM`. Treating a nonempty array as measured RPM data erased known readings and could leave an empty row under Live. Regression tests first failed on that case. Usable RPM observations are selected per fan index, with current helper/diagnostic evidence preferred and retained measured values qualified individually. A measured zero RPM is valid; metadata without RPM is not a measured zero.

## GPU cancellation

An immediately cancelled GPU sampling task previously performed its queued initial read and republished values after `stop()` cleared them. Rapid stop/start allowed both old and new initial reads. The sampling task now checks its own cancellation before initial refresh and after sleep. The sampler remains MainActor-isolated with the same cadence and synchronous read boundary; stopping cannot interleave inside a refresh.

The injected regression suite requires zero reads after queued stop, exactly one current initial read after rapid restart, and no further reads or publications after stopping an actually running sampler. The original implementation fails the first two cases; the corrected implementation passes all three alongside the four existing parsing/stale/reset tests. Logs: `/tmp/bloomy-efficiency-20261001/gpu-cancellation-red.log` and `gpu-cancellation-green.log` (7 tests / 2 suites, 0.259 seconds). This establishes bounded cancellation behavior, not a whole-app CPU or battery improvement.

The read-only ownership audit found no additional release imbalance in GPU IORegistry iteration or the adapter sensor service. Existing GPU history sampling remains app-owned; energy recording skips collection when recording is disabled or its rate is invalid. Fan subscribers retain their shared ownership and cadence. Source inspection is not sustained runtime energy profiling.

## Validation record

Request-card focused run: 5 test definitions / 16 parameterized case executions passed in 0.008 seconds, build 0.57 seconds. It covers current and retained idle/active/draining/stopped values, the ten-second daemon boundary, future/nonfinite timestamps, missing sources, and the required inference signal.

The first complete run passed 1,285 tests before the additional per-fan repair: telemetry 1,236 / 163 suites in 27.197 seconds, protocol 21 / 5 in 0.014 seconds, host 28 / 9 in 11.652 seconds. Native 44 compiled successfully from that intermediate snapshot but was not launched or used as final visual proof.

The per-fan red run failed as expected: 13 thermal tests with 9 issues, `/tmp/bloomy-efficiency-20261001/thermal-presentation-nil-rpm-red-01.log`. Existing ten cases remained green. The repaired run passed 13 tests in 0.115 seconds. A further constrained unit-layout regression brings the focused suite to 14 tests, all passing in `thermal-presentation-unit-layout-02.log`.

Native 45 verified current, retained, missing-runtime and disabled-helper descriptions with direct computer use and native accessibility inspection. Its mixed two-fan view preserved the correct numbers and individual spoken freshness, but visually clipped the retained fan's RPM unit. That layout defect required a further correction; Native 45 is not the final compact-layout proof. Its manifest hashes 85 sources; binary SHA-256 `04da30d6ff6b60595265cb55f598f2df2ccea92e65f337303ea9e45eb3b8eada` matched before review. Runtime directory: `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-C50001C8-054E-4DD2-9C7E-0F0F8E3450C1/`. Focus tracing remained off. The app was quit normally and PID 54597 absence confirmed.

Full run 02 exposed a test scheduling issue: concurrent MainActor rendering delayed the active GPU test for 4.404 seconds, beyond its two-second Date polling deadline; it had received one sample when its prerequisite failed. The correction awaits an event from the actual second injected read with a finite fifteen-second monotonic deadline. The requirement for at least two reads and the post-stop unchanged read/publication checks remain intact. The test-only change does not alter production cadence. The failed full run remains in `/tmp/bloomy-efficiency-20261001/resource-freshness-full-02.log`.

Full run 03 passed the corrected GPU case but exposed an unrelated popup fixture clock mismatch: after ten seconds, expired advertised telemetry fell back from three advertised models to six saved models, adding a selected row before expansion. Both states reached the same body cap, invalidating the test's assumed disclosure-height comparison. The test now keeps three advertised/saved models and six downloaded models, with explicit fresh and aged selection preconditions. All strict viewport, scroll, expansion and recollapse checks remain. Production clocks, source deadlines and popup code are unchanged. The full popup suite passed 27 tests; its final changed case passed all five viewport arguments. Logs: `popup-layout-fixture-focused-01.log` and `popup-layout-fixture-focused-02.log` in the same evidence directory.

## Final native review

Native 46 compiled the final production view snapshot. Its 85 source hashes and actual binary match `.build/native-dashboard-fixture-20261002-46/fixture-manifest.json`; binary SHA-256 `8c7b0eb503769bc0c71f53f0ae14e4c234f04a104b3a46dd0bbb27459f15aa04`. Runtime directory: `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-016F3D32-1EE3-4444-8527-7EAEEEEE016A/`.

Direct computer use and rendered screenshots verified:

- The compact 800 × 560 mixed row fits in light and dark appearance: current **42.0 °C**, retained **Fan 1 2200 RPM / Last observed**, and current **Fan 2 1200 RPM**. Both RPM units are completely visible; only the retained fan has the old-reading caption. Accessibility carries the same distinction.
- Stale Overview retains **54.0 °C / 2200 RPM** with individual Last observed labels and a past-tense helper caption. The request value is visibly Last report; accessibility says “Last reported provider request activity: 0, Idle. Current activity is unknown.” and includes Last report in its value.
- Expired helper retains known readings even with a current CLI capture and missing diagnostics, without a Live claim. Unavailable runtime shows **— / Unavailable**, no Last report badge, and unavailable fan telemetry.
- Current initial accessibility reports active request evidence and current thermal values. Native 45 separately verified the disabled helper caption in the same presentation logic; the final change only preserves measurement/unit width.
- The current-screen popup expands and collapses Available and preserves the Cooling/Auto/Nudge controls. Recorded fitting size is **560 × 605 → 560 × 709 → 560 × 605**; every content rectangle fits the actual screen. Native inner scrolling reaches the complete Earnings/electricity/jobs footer. The Cooling help is “Fan helper and cooling readings,” without an unconditional Live claim.

Native 46 was quit normally and process absence confirmed. Screenshots and accessibility states were inspected in the session; no saved screenshot artifact, actual VoiceOver session, physical-wheel matrix or universal display fit is claimed.

## Final automated checkpoint

Full run 04 passed **1,289 tests**: telemetry 1,240 / 163 suites in 30.055 seconds, protocol 21 / 5 in 0.017 seconds, host 28 / 9 in 11.781 seconds. The release build completed in **54.95 seconds**. Both commands exited 0 without compiler warnings or errors. Logs are `/tmp/bloomy-efficiency-20261001/resource-freshness-full-04.log` and `resource-freshness-release-01.log`.

Independent read-only reviews found no remaining actionable defect in the repaired per-fan selection, request qualification, or GPU cancellation. Focused red/green and full-run failures above remain recorded rather than being omitted from the evidence.

Production PID 31677 retained its October 1 22:40:57 launch. Its executable hash remains `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`; provider configuration hash remains `18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`. Final process/job checks showed no fixture, provider, recovery watcher, or power collector started by this work. The installed app and unrelated log readers/fan helper were preserved.

Actual VoiceOver, system Reduce Motion delivery, genuine cover occlusion, production privacy/removable-drive access, comparable whole-app profiling, and signed updater distribution remain separate gates. This checkpoint does not establish the complete native review matrix.
