# Actual status-item independent inputs — October 7, 2026

The optimized production StatusItemController passes seven bounded cases in
two fresh processes. Independent GPU and cooling publications preserve native
host identity, geometry and the single production clock. A third fresh process
is cancelled during the cooling case and verifies joined cleanup. This extends
supported-host evidence; it does not replace the failing standalone motion gate.

## Scope and design

The original five checks retain their nil-extras, never-started store: baseline,
ten daemon updates, active/idle/active, production popover open/close, and
invalidation/recreation. They finish and verify controller teardown before a
second never-started store owns the dynamic-input host.

That separation matters because opening the production popover with extras
would start visible fan observation. The dynamic host never opens a popover;
exact owned extras/GPU store identities and zero visible fan subscribers are
required throughout. The fake clients read only controlled in-memory values.
No sensor, provider, CLI, network, persistent sampler or fan mutation is used.

GPU steps are unavailable, 12%, 87%, failed read retaining stale 87%, and
recovered 42%. One further failed read retains stale 42% during the thermal
case. Cooling steps are 54 °C/25%, 70 °C/50%, 90 °C/80%, failed read retaining
stale 90 °C/80% with neutral tint, then recovered 54 °C/25%.

Each step captures source timestamps and client counters before the isolated
publication. The daemon and other source remain unchanged through the measured
hold. The actual combined native accessibility label must expose the expected
values and freshness. Thermal steps also read the activity arc's actual stroke
color under its effective appearance. Failed readings retain their original
successful capture times. Exactly six GPU and five extras reads are required
for a completed run, with no additional reads during holds or teardown.

Every successful motion observation retains the actual status button, window,
native view and arc; geometry stays stable and exactly one 1.4-second infinite
rotation remains. Presentation advances are observed before and after holds
longer than 1.6 seconds without forced layout, display, flush or recovery.
GPU progress is verified semantically and through native accessibility;
**graphical GPU fill remains unqualified**. This is whole-Mac usage, with no
claim of LLM-process attribution.

## Verified native results

| Fresh process | Terminal result | Sustained holds | Minimum hold | Minimum post-hold angle advance |
| --- | --- | --- | --- | --- |
| 61769 | 7/7 passed | 19 | 1.700700 s | 0.183984 radians |
| 62492 | 7/7 passed | 19 | 1.700591 s | 0.104447 radians |
| 62965 | Cancelled during thermal case | 14 completed | 1.702725 s | 0.115898 radians |

The second run finished before an attempted cancellation arrived, so it is
recorded as another completed run. It is not counted as cancellation evidence.
The third run reaches the explicit cancelled state after six GPU reads and one
extras read. Its aggregate correctly stays incomplete/failed while cleanup
passes independently: all three owned controllers invalidated, retained clocks
stopped, both MonitorStores and extras/GPU stores stopped, no fan subscribers,
cleared GPU fields and unchanged before/after teardown read counts. All three
processes were quit normally and their PIDs verified absent.

## Provenance and checks

Final artifact: `.build/status-item-dynamic-qualified-native-review-20261007/`.
All 126 recorded source hashes match the checkout; frozen executable and linked
telemetry library match the manifest. The production host staging adds only its
test-access extension; no production view or animation code is changed.

- Manifest: `7b954ed5dbdc6d27b9016aaebd4fb57ecb909a98f7ddc716f61a14866b99bdea`
- Executable: `b04501ba166946865ab250749d9a819dc754971899bd14352105a9d407acf722`
- Library: `34a574a169dd64139079f8b9a41155d5d864774ea17a577bafc89887fcd1264b`

Reports, hashes, counters and holds are retained in `runtime-complete/`,
`runtime-complete-repeat/`, `runtime-cancelled/` and `runtime-summary.json`.
The preliminary artifact predates the final cancellation-report refinement and
is not qualification. Both finite optimized builders completed at exit 0.
The unchanged weak-variable compiler warning is retained in their logs.
Thirty-two staging checks and fourteen focused Release readiness tests pass;
`git diff --check` passes. No fresh full package run is claimed for these
fixture-only changes. Production source/library are unchanged from the prior
verified readiness checkpoint. A bounded read-only review found no regression.

The provider remains stopped, and its configuration retains SHA-256
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The pre-existing dirty ordinary proof retains SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
The installed app, preferences, credentials, cache and unrelated work remain
preserved. There is no installed update, push, release or distribution claim.

## Remaining boundaries

The ordinary motion gate still has its cover and normal/rapid reused-window
failures (12/15 at the readiness checkpoint). A settling interval changes that
manual host's results, but does not justify a production sleep or retry timer.
The current supported status-item and Settings evidence does not reproduce its
detach-to-immediate-close transition. Actual system Reduce Motion, genuine
cover/restoration, GPU pixels, broader accessibility and matched production
resource qualification remain open. The full polish goal remains active.
