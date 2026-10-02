# Native draft, History, and heartbeat checkpoint — October 2, 2026

This checkpoint fixes lost unsent Chat/settings drafts, preserves selected log
details across matching feed updates, avoids redundant freshness snapshot work,
and corrects an expanded Action History layout that escaped the compact window.
It is verified source and isolated native interaction evidence, not a published
release or completion of the broader [polish plan](APP_POLISH_OPTIMIZATION_PLAN.md).

## Changes and regression evidence

| Area | Result | Checked evidence |
| --- | --- | --- |
| Chat | The dashboard owns an in-memory message draft associated with its conversation ID. Navigating away removes Chat without losing that conversation's unsent text. A different conversation clears the old draft; independent pop-out composers keep independent drafts. Accepted Send clears the draft and rejected Send preserves it. | Six added lifecycle tests in [ChatViewTests.swift](../Tests/DarkbloomTelemetryTests/ChatViewTests.swift), including actual view removal/return, hidden conversation changes, independent composers, accepted/rejected sends, stale callbacks, and key-editor removal. Native 14 reproduced draft loss on Chat → Hosting → Chat; native 15 retained the same typed unsent text through that route. |
| Credentials and accessibility | Retained Chat state contains text and a conversation ID only. Consumer key text/error/sheet state remains view-local; removing the key editor wipes its unsaved synthetic credential binding. Composer, retry, dismiss, and key controls have explicit accessibility names. | Mounted key-editor disappearance test passed. Native 15 exposed the composer as “Chat message.” This does not establish VoiceOver reading/focus behavior. |
| Provider/Fans settings | Only the selected settings page is mounted. The dashboard retains nonsecret idle and fan policy edits, including partial invalid idle text. Dirty drafts survive source refreshes; clean drafts follow source/readback. Revision checks prevent a late save from replacing newer edits. Standalone editors remain independent. | [SettingsDraftRetentionTests.swift](../Tests/DarkbloomTelemetryTests/SettingsDraftRetentionTests.swift) checks removal/return with five idle strings, fan subscriber release/reacquisition, presets, clean/readback behavior, newer edits during saves, and independent editors. No fake provider mutation occurred during navigation tests. |
| Log details | Row identity includes the entire immutable event value plus an occurrence number for identical duplicates, assigned before filtering. Selection remains while that identity is visible; removal or an excluding filter clears it. | Four selection/identity tests in [LogsQueryTests.swift](../Tests/DarkbloomTelemetryTests/LogsQueryTests.swift) cover arrivals, reordering, removal, intersecting filters, exact duplicates, all event identity fields, and export order. Export/privacy behavior is unchanged. |
| Freshness heartbeat | A tick captures the clock once and derives the source/menu freshness signature before building a full snapshot. Unchanged signatures avoid event-feed construction and diagnostic sorting. Successful acquisition publications remain intact. | Deterministic tests in [TelemetryServiceTests.swift](../Tests/DarkbloomTelemetryTests/TelemetryServiceTests.swift) cover unchanged fresh/stale ticks, the 10/60-second boundaries, expiry, a backward clock, reasons, last successful capture times, payloads, token rate, event feed, and diagnostics. The injected-tick integration test also remains. No current whole-app CPU/energy saving is claimed. |
| Action History | Expanded recording notes have bounded scrolling; the page body scrolls below its fixed heading, while the table and selected details keep bounded regions. Privacy text remains complete. | Native before/partial/final evidence below; [ActionHistoryViewTests.swift](../Tests/DarkbloomTelemetryTests/ActionHistoryViewTests.swift) hosts 48 synthetic rows with selected/unselected states at 800×480, 800×560, and 1280×900 and asserts host/split bounds. Native transition proof is separate from the initial-expanded test. |

The implementation is in [ChatView.swift](../Sources/DarkbloomMonitor/ChatView.swift),
[DashboardRootView.swift](../Sources/DarkbloomMonitor/Dashboard/DashboardRootView.swift),
[MonitorSettingsView.swift](../Sources/DarkbloomMonitor/MonitorSettingsView.swift),
[ProviderExtrasViews.swift](../Sources/DarkbloomMonitor/ProviderExtrasViews.swift),
[ProviderFanControlSettingsView.swift](../Sources/DarkbloomMonitor/ProviderFanControlSettingsView.swift),
[LogsView.swift](../Sources/DarkbloomMonitor/Dashboard/LogsView.swift),
[TelemetryService.swift](../Sources/DarkbloomTelemetry/TelemetryService.swift), and
[ActionHistoryView.swift](../Sources/DarkbloomMonitor/Dashboard/ActionHistoryView.swift).

Exact duplicate log events have no source occurrence ID. The ordinal preserves
distinct selectable rows while multiplicity permits it; it does not establish
which physical identical occurrence survived removal. The dashboard fixture
regenerates its log timestamps every five seconds, so it is not evidence of
selection surviving real incremental log arrivals. The semantic tests establish
that behavior under unchanged event identities.

## Native evidence and provenance

Native review used separate AppKit dashboard fixture apps from
[DashboardFixture.swift](../Tests/NativeUI/DashboardFixture.swift). The banner
identifies synthetic data; Fresh/Stale/Stale catalog/Offline controls reconstruct
injected stores. Fresh supplies synthetic CLI 0.9.17 evidence renewed every five
seconds. CPU/GPU/power acquisition is disabled, `MonitorStore.start()` is not
called, and provider/API/credential controllers are inert fixtures. The host Mac
name and host thermal state are disclosed as real. These checks did not start
the real provider, perform inference, swap/download a model, save a real policy,
or read a real key. See [the fixture instructions](../Tests/NativeUI/README.md)
for dependency substitutions and limitations.

The fixture has production-style AppKit window behavior, native Edit shortcuts,
and Minimize/Show Dashboard commands. The corrected Edit menu allowed actual
Command-A and typing in a focused synthetic idle field. An earlier fixture
without that menu appended text instead of selecting all; that is not a
production text-field regression.

Evidence artifacts are retained locally under
`/tmp/bloomy-efficiency-20261001/`; these temporary paths are not release assets.
Each manifest records 76 source hashes, dependency substitutions, the telemetry
library hash, binary hash, and exact compiler invocation. Native 16's 76 recorded
source hashes match the frozen current files. All three binary hashes were
independently rechecked against the retained app executables.

| Fixture | Manifest | Binary SHA-256 |
| --- | --- | --- |
| Native 14, baseline | `native14-fixture-manifest.json` | `2543abe7f33df8ef3b7d28fefd08679fa95f80211b9d8653af0cafa927f55886` |
| Native 15, draft fixes and first History correction | `native15-fixture-manifest.json` | `fc43f9a12c7f8df631b465c410cfef595a0afce615a2f380394e2f0d7f151d2f` |
| Native 16, final History correction | `native16-fixture-manifest.json` | `f0b5a795fca420de3aad38304c03a4f8884a4d14d8a2d585a021ebd01ff4f312` |

Native 16 links telemetry library SHA-256
`64f14e507ddee718f08e506edb3bbefa84fa5948470ef13c5153cf88199bdd30`.
Native 15 and 16 have identical Chat/settings production source hashes; only
the History source differs between those two manifests. Review signing or a
fixture manifest does not establish notarized distribution.

### Completed native interactions

- Native 14: Available contained two downloaded, unselected models (Bonsai and
  Qwen3 8B), with matching card sizing; collapse, expand, and reopen worked.
  The controls did not activate those models.
- Native 15: typed unsent Chat text survived Chat → Hosting → Chat. The composer
  accessibility name was “Chat message.”
- Native 16, dark compact: a new Local Chat composer labeled “Chat message”
  received the exact typed text “Native review draft — keep this while I change
  pages.” Hosting → Chat returned that same text; the rendered result was
  inspected. Send was not clicked.
- Native 16, dark compact: saved idle policy was 30 minutes. Command-A followed
  by typing 45 showed Unsaved and enabled Save. Provider → Overview → Provider
  retained 45 while the saved summary remained 30. Save was not clicked.
- Native 16, dark compact: opening Fan policy via its visible chevron and choosing
  Quiet showed Selected, Unsaved, target 60%, trigger 45°C, and enabled Save Fan
  Policy. Fans → Overview → Fans remounted the page with the disclosure collapsed;
  reopening retained the same Quiet draft and unsaved values. Neither Save nor
  the fan-control switch was clicked. An accessibility disclosure press did not
  toggle while the visible coordinate click did; no source defect is inferred
  from that automation difference.
- Native 16: History expanded with no selection in compact light appearance;
  selecting a failed Swap retained usable layout and scrolling reached its full
  details. Dark wide, then dark compact collapse/reopen, also stayed visible.
  Heading, banner, and sidebar remained reachable.
- Native 16: Window → Minimize from Activity → Metrics (24h) produced a minimized
  accessibility state with the standard window operations disabled. Window →
  Show Dashboard restored the standard window, the same Metrics/24h route, and
  376 synthetic samples; the restored screenshot was inspected. This proves
  the native menu/window route, not measured query cancellation or CPU savings.

### History geometry correction

The observed blank window was a layout excursion, not a provider failure. With
notes expanded, native 14 retained responsive accessibility state but placed
the dashboard/sidebar outside the window. Collapsing restored it. A bounded
notes-only correction in native 15 removed the blank result but still clipped
the banner. Native 16 adds the outer body scroll; the fixture window sizing
routine was unchanged between the partial and final correction.

| Evidence file | Records | Observed native split rectangle `[x,y,width,height]` |
| --- | --- | --- |
| `native14-history-layout-diagnostics.jsonl` | 3 | Expanded `[0,-2490,800,5459]`; collapsed `[0,0,800,480]` |
| `native15-partial-history-layout-diagnostics.jsonl` | 3 | Collapsed `[0,0,800,480]`; expanded `[0,-37,800,553]` |
| `native16-history-layout-diagnostics.jsonl` | 9 | Compact `[0,0,800,480]`; wide `[0,0,1280,849]`, including expanded selected/unselected states |

The requested fixture content sizes were 800×560 and 1280×900; the banner leaves
the measured dashboard split area above. The wide trace flags tree truncation,
so it is evidence for the recorded split bounds, not a complete focus tree.
Normal native screenshots and interaction also confirmed content visibility.
The exact internal SwiftUI measurement mechanism remains an inference; the
before/partial/final geometry and visible correction are observed evidence.

## Finite verification

| Retained log | Result |
| --- | --- |
| `draft-log-heartbeat-focused-tests.log` | Initial test compilation failed in a Swift Testing macro applied to an optional-chain expression. The test uses a local value after repair; this is retained failed-attempt provenance. |
| `draft-log-heartbeat-focused-tests-02.log` | 49 tests in 5 suites passed; test run 8.401 s. |
| `history-bounded-scroll-focused-tests.log` | 3 test definitions in 1 suite passed, including parameterized sizes/selections; test run 2.321 s. |
| **`draft-log-history-final-full-tests.log`** | **1,129 app/telemetry tests in 151 suites (26.526 s), 21 companion tests in 5 suites (0.014 s), and 28 host tests in 9 suites (11.657 s): 1,178 total passed.** |
| **`draft-log-history-final-release-build.log`** | **Final release compilation completed in 49.42 s.** |
| `native16-final-layout-build.log` | Final isolated native fixture compiled. Manifest/binary identity checked as above. |

Earlier `draft-log-heartbeat-full-tests.log` and
`draft-log-heartbeat-release-build.log` predate the final History correction;
they are retained provenance, not the authoritative final verification.

## Pending proof and release boundaries

- [ ] Complete route × appearance × size × source-state review, actual VoiceOver
  interaction, and controlled Reduce Motion behavior.
- [ ] Chat verification expiry UX: after the 120-second local verification
  deadline, the view can describe “Verifying…” without a running refresh and
  lacks a timely expiry publication/recovery indication. The store safely
  rejects stale verification; visible status/action recovery still needs review.
- [ ] Comparable current production CPU/energy/allocation measurements with
  visible and minimized Metrics. This checkpoint proves avoided heartbeat work,
  not whole-app performance or battery savings.
- [ ] Production external Sol cache permission boundary and required native
  release checks. A scoped removable-drive privacy reset remains awaiting human
  approval; no privacy, Keychain, or drive access workaround is authorized.

The running production Bloomy app and its user state were preserved during
these isolated checks. Final verification at approximately 2:14 AM Phoenix
confirmed the same production PID 31677 at
`/Users/kevink/Applications/Bloomy.app/Contents/MacOS/DarkbloomMonitor`.
The real CLI 0.9.17 reported `Daemon: not running (stale state file)` and
`watchdog installed but not loaded`; launchctl independently found no
`io.darkbloom.watchdog` service. No temporary start was needed.
The provider configuration SHA-256 stayed
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
Native 14 and 15 were cleanly stopped earlier; native 16's popup Quit was
followed by a process check finding no remaining native 13–16 fixture process.
The final hash/process summary is retained as
`native16-final-protected-state.json` in the same temporary evidence directory.

Publishing remains held by the production/native boundary. A successful release
compile is not signing, notarization, a Sparkle install/relaunch test, or release
publication. Follow [RELEASING.md](RELEASING.md) for the exact source/artifact and
updater gates; this document does not waive them.
