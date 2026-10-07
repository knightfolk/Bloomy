# Native timeline inspection — October 7, 2026

Activity Metrics now supports selecting an observed moment with a chart click,
drag or explicit accessibility Inspect action. A dashed time marker and a stable,
scrollable evidence panel show matching model visits and the separate all-model
provider interval. Clear removes the selection. Changing filters recomputes the
evidence; moving the period clears a moment outside its new range.

This is another step toward the joined Activity day report. Actions, credit
arrivals, historical local-machine attribution and loading evidence are not yet
joined into that report. No provider command, inference, download, new poller,
database write or dependency was added.

## Selection boundaries

Selection uses only currently displayed evidence. Bands and provider intervals
are half-open: the first time belongs, the final time does not. A point matches
only its exact stored time; its accessibility action makes it inspectable without
requiring pixel precision. All coincident matches remain in the scrollable panel.
Gaps do not select a nearby visit or imply downtime. Whole-visit classifications
remain distinct from approximate provider activity between readings.

The provider row retains all-model scope when model/no-work filters remove visits.
Both endpoint dates are displayed, avoiding ambiguity across midnight. Visit and
provider labels have separate accessibility identities; color is accompanied by
symbols and text. The inspector has a fixed height, including its empty hint, so
selection updates do not repeatedly move the content below it.

The implementation uses Swift Charts `chartXSelection` and a documented custom
`chartGesture` calling `ChartProxy.selectXValue`. Native macOS default selection is
hover-based; the preliminary artifact did not satisfy our click/drag interaction.
See Apple's [chart selection API](https://developer.apple.com/documentation/swiftui/view/chartxselection%28value%3A%29).

## Review repairs

Preliminary artifacts are retained and do not qualify the final source. Review
removed a three-row inspector cap, added dates to both provider endpoints and
separated inspector accessibility labels. Native testing led to the explicit
click/drag gesture. Final source review found a mixed-input state defect: Inspect
changed the displayed date while retaining an earlier chart binding. Returning to
the identical chart time could therefore fail to update the inspector. Both
Inspect actions now synchronize both dates. A fresh read-only review reported no
remaining concrete source findings.

## Tests and source provenance

Four new tests cover shared boundaries and four coincident points plus a band,
exact-point membership, gaps, invalid/moved ranges and current-filter replacement
while global provider evidence remains. The final serial Release run passes
1,785 reported tests: 1,736 telemetry, 21 protocol and 28 host. Seven existing
opt-in tests are skipped. All 32 staging checks and the production Release build
pass. Finite jobs were joined; no check expectation or production timing was
relaxed. Logs are retained as `.build/timeline-inspection-qualified-*20261007.log`.

The optimized isolated native artifact is
`.build/timeline-inspection-qualified-native-review-20261007`. All 128 view/fixture
source hashes match the working tree. Its linked telemetry library matches the
unchanged qualified library.

- Manifest: `f943f605e56dd18ff1d7b4de5fdc04446e1b55568956da26abbdda8c1d39cd91`
- Executable: `b62ca2e6e26b11ba06b275bdd61d2c92c73242f3a7614d620c4f2dd95f8cfad7`
- Telemetry library: `8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`

## Native interaction evidence

Computer use on the final artifact verifies:

- Chart click, drag, exact Gemma point Inspect and Clear.
- Chart A at 8:08:15 AM, accessibility Gemma B at 10:23:51 AM, then the exact same
  chart A at 8:08:15 AM. The Qwen visit and separate provider interval return.
  An earlier slower attempt crossed a 30-second range refresh and returned a
  different moment; it was not counted as this exact-time regression.
- Without work removes the selected Qwen visit while retaining its provider
  interval; Clear removes the inspected time.
- A Bonsai no-work visit and separate idle provider interval fit the 800 × 560
  light and dark inspector. Wide light/dark charts and selected evidence are
  visually inspected; dragging in wide dark selects a Gemma visit and provider
  interval with full endpoint dates.
- Expanding to seven days retains a still-valid selection. Selecting an October 3
  gap states no displayed visit/activity; returning to 24 hours clears it.

These are synthetic native interaction, layout and accessibility-identity checks.
They do not establish VoiceOver/audio traversal, larger-text behavior,
maximum-history responsiveness, comparative resource savings or production
financial attribution. The test for more than three coincident rows is pure
membership proof, not a rendered many-row qualification.

The unchanged ordinary native proof reached terminal completion: Models and
Charts pass; motion remains 12/15 with the same opaque-cover and normal/rapid
same-window reopening failures. Results are retained in the artifact's
`native-proof` directory. No animation or motion assertion was changed. These
failures remain qualification work, not a reason to label the app fully polished
or publish this artifact.

The earlier owned review process (98980) and final process (8004) quit normally
and were verified absent. Provider configuration and the pre-existing motion
proof retain their hashes; their contents were not changed by this work. No
installed update, push or release is claimed. Joined replay, historical local
attribution, demand history, broad native/accessibility/performance proof and
distribution remain open.
