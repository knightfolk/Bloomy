# Activity action timeline

Activity Metrics now places retained action timestamps beside observed model
residence and explicitly all-model provider activity. This advances the joined
day report recommended by the BloomGauge comparison; loading duration, credit
arrival and verified historical local-provider earnings remain separate work.

## Behavior

- Reuses the existing action journal. No provider command, additional recorder,
  polling loop or inference is introduced.
- At most 96 equal-duration grouping slots retain nonempty action groups. A
  circle represents one event and a diamond represents several. Markers identify
  a grouping interval, not operation duration; empty time remains empty.
- The inspector lists every retained event in the selected group with its exact
  date/time, trigger, latest stored outcome/reason and model. An individual scope
  button selects that event's timestamp and returns the inspector to the model
  and provider evidence at the top.
- Selecting a model preserves matching canonical model actions and global
  actions. Filtering visits without observed work does not hide actions.
- Job/reward entries remain outside this lane. An action does not establish
  organic work or payment. The existing capped journal is not complete coverage
  of every selectable period.
- Empty metrics still expose retained actions. Hidden/cancelled or replaced
  requests cannot publish obsolete model, period or same-ID outcome data.

## Verification record

The serial Release run before the final inspector scroll repair reports 1,797
tests, including seven existing opt-in skips. The final focused Release run
after that repair passes 40 tests across four suites. Twelve new tests cover
grouping boundaries and gaps, scope, financial exclusions, corrected payloads,
malformed dates, bounded geometry, and obsolete read/selection protection.
Forty-seven native staging tests pass without changing the protected motion
helper or weakening expectations.

The final optimized isolated artifact is
`.build/action-timeline-scroll-qualified-native-20261007/Bloomy Dashboard Fixture.app`.
All 131 recorded source hashes match the final tree. Manifest SHA-256:
`bc90c6a19324a525e4fdfc8b2d848fbe8ae8d9c89cfbe9ab4b38f1dd1db5f8b6`;
binary SHA-256:
`ab559236d22be3e9842b5fb56542827666c002210f1494d0be75968fd7c818c1`.
Its linked telemetry SHA-256 is
`8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`.

Computer Use checked the final artifact with controlled synthetic data:

- A mixed five-event group shows distinct swap, failed nudge, skipped watcher
  and global actions with exact recorded times.
- After scrolling the event list, selecting the nudge's scope button returns to
  the header and visibly shows the matching Bonsai no-work visit and idle
  provider interval. The selected time is the nudge timestamp, not the marker's
  grouping midpoint.
- The without-work filter retains action groups. Gemma scope includes Gemma and
  global events while excluding Qwen/Bonsai actions; provider scope stays all.
- Compact 800-by-560 light and dark views retain aligned chart rows and a stable
  readable inspector. Native chart click selects an unknown gap; drag changes
  the selected moment; Clear restores the invitation to inspect.
- An empty synthetic metrics read reports zero samples but retains action
  groups. Inspecting them shows no displayed visit/activity instead of inventing
  work. Restoring normal reads restores measurement evidence.
- Thirty-day groups display complete boundary dates. The 5,000-record scenario
  produces 96 accessible groups, preserving bounded chart geometry; this is not
  a process-performance benchmark.

The review app quit normally and process inspection confirmed no remaining
`DashboardFixture` process. The final production Release build passes
(`.build/action-timeline-final-production-build-20261007.log`, 47.10 seconds).
All finite jobs are joined, whitespace checks pass, and the protected motion
helper/provider configuration retain their pre-task hashes.

This checkpoint does not qualify comparative CPU, memory, wakeups or battery
performance, complete replay, genuine native occlusion, broad VoiceOver behavior,
or distribution. Production provider configuration, running app and unrelated
motion-helper work are preserved. No push or release is included.
