# Settings truth, Logs display, and cache visibility — October 2, 2026

This is a bounded checkpoint in the continuing native polish and efficiency
run. Production Bloomy and its unsaved work are preserved. The provider's
separate managed-launch cache failure remains unresolved after the authorized
removable-drive permission reset; no additional privacy or provider changes
were made for these checks.

## Changes and independent review

- Electricity distinguishes disabled recording, a missing price, an invalid
  price, and a valid price. Enabled recording with blank or invalid input says
  it is waiting for a valid price. Blank input has neutral guidance; negative
  or nonfinite input has validation. Zero is valid. Toggling recording off
  preserves the entered price. These states use the same rate parser as the
  actual recorder's sampling gate.
- A prepared Support report captures whether alert history was available at
  preparation. The page and preview explain unavailable history using that
  frozen metadata. A later storage failure or recovery cannot change what the
  existing report claims to contain. Known-empty history remains available;
  unprovided metadata remains unknown. The exported document/schema/bytes and
  review-before-save gate are unchanged.
- Logs derives one current display snapshot for its table, empty state,
  selection, and source timestamp. It prepares the trimmed query once and
  creates at most two date formatters per derivation, lazily. Formatters are
  discarded after the derivation so locale, calendar, and time-zone changes
  remain current. Event order, duplicate occurrence identity, selected
  payloads, UTC help, export policy, and collection cadence are unchanged.

Independent read-only Settings and Logs integration reviews found no actionable
correctness or regression issue. Regression tests compare Electricity with
the injected real recorder's sampling behavior, including blank, whitespace,
negative, nonfinite, zero, and positive input in enabled and disabled states.
Support tests cover byte/schema parity and both later availability changes.
Logs tests independently compare the prior query and formatting behavior,
duplicate/selected identities, corrected same-count payloads, locale/calendar/
time-zone variations, fresh time-zone evidence with unchanged IDs, and bounded
formatter creation.

## Logs component measurement

The finite standalone runner extracts the exact prior query/row/date helpers
and the current helpers. It uses 100 synthetic rows, seven samples of thirty
iterations, and asserts output, order, selection, timestamp, and formatter
parity. Both its compile and run completed successfully.

| Matching display batch | Baseline median ms | Final median ms |
| --- | ---: | ---: |
| 80-character messages | 8.950 | 0.291 |
| 1,200-character messages | 10.404 | 0.522 |

The baseline represents the prior source's six row derivations and formatting
of all matching rows: an upper component batch, not an observed SwiftUI render
count. The final uses one actual display snapshot. No-match batches measured
1.359 / 0.267 ms and 4.452 / 0.783 ms respectively. This excludes layout,
collection, storage, provider work, and whole-app CPU or energy. It does not
establish a total-app percentage improvement.

Runner/provenance and output are retained under
`/tmp/bloomy-efficiency-20261001/` as `logs-display-final-benchmark-01.log`,
`logs-display-final-provenance.txt`, and the corresponding task-owned source
and executable. Candidate LogsView SHA-256:
`3e70cb02ec7d51512e34cc36dd4aeb6b6229a5701e9a6db5513e35175567ecc3`;
LogsPresentation SHA-256:
`866127d0b908cf5b6020dd0dc3e559b7d588da4267a7f4a1e7bd3aa5b50ca29e`.

## Native inspection

Native 62 supplies the pre-change Settings baseline. At compact 800 × 560,
enabling Electricity with blank input incorrectly claimed recording with no
guidance. Appearance's native segmented control was reached through the
actual key loop; Right followed by Space in one uninterrupted key batch
selected Dark and updated the control and window. Right alone moved focus,
not selection. Intervening computer-use inspection can reopen/refocus this
fixture; earlier interrupted attempts are not counted as picker failures.
The first-party Appearance view is unchanged in Native 63. The Companion page
fit in light and dark and explicitly stated that pairing and remote controls
are unavailable in this version, with no unsupported setup controls.

Native 63 uses the final product sources with the established inert client
substitutions. Its 88 recorded source hashes matched the working tree before
inspection; no real provider, endpoint, inference, or API key was used.

- Compact light/dark Electricity shows waiting guidance for blank/whitespace,
  red validation for a negative price, and readiness for zero. Both messages
  are independently present in the accessibility tree. Turning recording off
  preserves `0.15` and hides validation. The native disclosure arrow exposes
  the fully wrapped whole-Mac estimate/coverage explanation. AX pressing the
  disclosure label did not open it; clicking its visible arrow did.
- Compact light/dark Support previews show the captured unavailable-history
  warning without clipping. The text preview scrolls; Close and the review
  checkbox remain reachable. Save is disabled until acknowledgement and resets
  on the next prepared report. Dismissing the preview leaves the same warning
  on the Support page. No report was saved or shared.
- Compact light/dark Logs retains its picker, readable table, local timestamps,
  UTC help, and source time. An unmatched search shows the empty message and
  disables export. `delayed` matches six warning events; the frozen export
  preview contains those six events and retains its review/save gate. A
  selected event exposes full details in AX and a visible details card;
  the outer page scrolls independently of the table. The fixture regenerates
  every event timestamp on each five-second tick, replacing immutable IDs and
  legitimately clearing selection. Full sustained selected-card inspection
  was therefore inconclusive in this live fixture. Retention after actual
  arrivals and same-ID corrections is established by the focused tests, not
  claimed from these synthetic replacements.

Native manifest: `.build/native-dashboard-fixture-20261002-63/fixture-manifest.json`

Manifest SHA-256:
`3e9709f3bacabbfe15e26c6865a34bae47ea7ba013bab3cb049f236c466e124e`

Binary SHA-256:
`740c0a011649aeb60dfb1f18a9ad3bfa8f1153a932af55452645efaace06f4f8`

Native 62 Settings/focus runtime:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-7D9F9575-E7DC-4B21-B3AE-BBA47368BA9D/`

Native 63 runtime:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-DA6B242A-ED83-4BBB-9FA8-1816A29636AA/`

## Finite native cache visibility proof

The opt-in helper runs under the fixture's normal `NSApplication.run()` and
hosts the real staged NetworkCacheView in a separately owned native window.
Window delegates forward actual minimize/restore/close events to its visibility
state. Conditional removal dismantles the real child. The shared inert-client
counter is baselined, never reset; the main dashboard stays on Overview with
no competing cache view. Root avoided CUA inspection during the timed holds.

Native 63's terminal JSON reports five of five passed, no failures, and passed
owned cleanup. The menu subsequently showed “Cache proof passed”, establishing
that the helper returned and the retained task finished.

| Case | Cumulative reads since baseline | Native evidence |
| --- | ---: | --- |
| Initially visible | 1 | Mounted child, visible rendered state |
| Minimized for 65 seconds | 1 | Real minimize notification, native hidden/miniaturized state |
| Restore | 2 | Same window, refresh in 0.684 seconds |
| Child absent for 65 seconds | 2 | View dismantled, host window remains visible |
| Reinsert child | 3 | Second mount, refresh in 0.022 seconds |
| Cleanup | 3 | Child unmounted, window closed, no late reads |

`network-cache-visibility-proof.json` records window number 18299, baseline
zero, one minimize/restore notification, two mounts, completed terminal status,
and passed cleanup. Each hold exceeds the real sixty-second refresh interval.
This closes the bounded window-delegate and child-remount evidence gap left
by Native 62's observer-interrupted attempts. It does not establish actual
production dashboard/Opportunity navigation, occlusion, VoiceOver, transport
timing, whole-app background cost, or user-state-safe production relaunch.
Delayed transport cancellation remains covered by the separate gated tests.

Independent review found no new proof ownership/cancellation issue. The caller
retains one task, prevents reload/competing proofs, and cancels then joins
cleanup during Quit. Cleanup is a separately awaited finite task so caller
cancellation cannot skip child/window dismantling. Incremental JSON remains
available if a run is interrupted; only complete cases plus cleanup can pass.

During Native 63 inspection, the cache-action enabled state did not observe
nested dashboard navigation. Returning to Overview left it disabled until an
unrelated fixture appearance refresh. Its execution guard remained correct.
The final fixture now observes navigation directly; this is a test-control
correction, with no production behavior change.

Native 64 verifies that correction: on Appearance, the cache proof is disabled;
returning to Overview enables it without an appearance or other unrelated
refresh. The product sources, telemetry library, and visibility helper are
unchanged from Native 63. The final fixture's 88 source hashes all match.

Native 64 manifest:
`.build/native-dashboard-fixture-20261002-64/fixture-manifest.json`

Manifest SHA-256:
`a7bc22e72fb42630cba1d76cf6c0f72932087149e1c9f3a88104892116e47bb6`

Binary SHA-256:
`498917e121ad2ca392b66d921a832c2308efe52536613ab7a23eb08d5989d7dd`

Runtime:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-1D6273C6-7749-4495-AB8E-1FBC260F1758/`

The final Native 64 run also completed five of five with no failures and passed
cleanup: cumulative reads `1, 1, 2, 2, 3`, one actual minimize/restore pair,
two mounts, window number 18322. Restore refreshed in 0.663 seconds; reinsertion
in 0.023 seconds. Terminal report SHA-256:
`d882f45f3114da4a54261ab756afac80a4e02096835cb707bd17451d0ba83c68`.
The native menu again showed “Cache proof passed”, with normal controls restored.
Both review processes were retired through their normal popup Quit actions.

## Verification and remaining gates

Root joined every finite compile/test process:

- `settings-logs-focused-01.log`: exit 0, 23 tests in six suites.
- `settings-logs-full-01.log`: exit 0; 1,319 app/telemetry tests in 178 suites
  (26.152 s), 21 core tests (0.014 s), and 28 host tests (11.758 s): 1,368
  reported tests total.
- `settings-logs-release-01.log`: exit 0, release compile 44.46 s.
- `settings-logs-native63-build-01.log`: exit 0, immutable native review build.
- `settings-logs-native64-build-01.log`: exit 0, fixture navigation-observation
  correction. The earlier product tests/release apply to unchanged product
  sources; the final native compile verifies the changed fixture.

Logs are under `/tmp/bloomy-efficiency-20261001/`. This is local native and
component evidence. Complete VoiceOver/keyboard/route matrices, comparable
whole-app profiling, production relaunch with unsaved work, updater install,
signing/notarization, and distribution remain separate open gates.

Final preservation checks found the installed process still at PID 31677 with
its original October 1 22:40:57 launch. Its executable SHA-256 remained
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Both `io.darkbloom.provider` and `io.darkbloom.watchdog` remained unloaded
(`launchctl` exit 113 with service not found). No provider/config/privacy change
or external transmission was made during this checkpoint. Retained native
artifacts and proof files remain available for review and provenance.
