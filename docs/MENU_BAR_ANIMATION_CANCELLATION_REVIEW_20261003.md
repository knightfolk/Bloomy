# Menu-bar animation cancellation diagnosis — October 3, 2026

The activity-ring reopening bug remains open. The new native helper demands
actual compositor advancement before and after a 1.6-second hold, extending
beyond the production 1.4-second rotation, with no forced redraw or transaction
flush during these observations. It also delivers late cancellation callbacks
before checking dismantled-view cleanup. Ordered-out failures now retain final
window/native state and a bounded lifecycle trace.

No experimental production change was retained. In particular, the native
animation delegate and its one-retry budget were removed after Native178 failed.
No release is ready from this diagnostic checkpoint. The installed app and
provider were preserved throughout; every review fixture was quit normally
following terminal reports.

## Observed boundary

Native173 traced forwarded shape-layer add/remove operations without replacing
production synchronization. Its native clock disappeared after reopening without
an explicit public layer removal from Bloomy's code. Native175 added a diagnostic
animation delegate forwarding any original delegate and observed false-finished
stop callbacks after the reopened window became genuinely visible. Apple's
[animation stop callback](https://developer.apple.com/documentation/quartzcore/caanimationdelegate/animationdidstop(_:finished:))
distinguishes natural completion from removal/cancellation. The callback records
show cancellation, not completion of a finite rotation.

Native179 instrumented the rejected one-retry candidate. Target layer
`ObjectIdentifier(0x0000007ae706e620)` had an ordinary eligible synchronization at
sequence 125, then started/cancelled its clock at 129/130. The eligible recovery
at 131 added a replacement, which also started/cancelled at 135/136. Sequence 137
correctly refused another recovery with its budget exhausted. Thus increasing
retries would hide a real repeated native cancellation and could introduce an
unbounded loop; a single cancellation response did not solve the lifecycle.

Its order-out trace shows a separate boundary: cancellation callbacks run while
`isVisible` is false but the occlusion-visible bit is still set. A fast restoration
can coalesce that bit without another visibility notification. The candidate
removed its clock during this interval and never received a restoring ordinary
callback. The original synchronization passed this bounded order-out case.

These diagnostic overlays are not exact production-motion proof. Their logger
is capped at 600 records and exists only in staged sources. The view/layer
identity, parent ownership, geometry, path, speed 1, real visibility and Reduce
Motion state were retained in reports; none alone proves an animation advances.

## Controlled experiments

All runs reached terminal model/chart/motion reports. Model and chart checks
passed throughout. The production model duration/repeat policy and strict
visibility/occlusion predicates were retained.

| Native | Single experiment or staged candidate | Motion result | Conclusion |
| --- | --- | --- | --- |
|173|Forwarded public shape-layer operation trace|12/15|Reproduced both reopening failures; no corresponding explicit public removal.|
|174|Assign owned root before `wantsLayer=true`|12/15|Root ownership did not restore the clock; rejected.|
|175|Forwarded animation-delegate trace|12/15|False-finished native cancellation observed.|
|176|Child cover changed to normal level|12/15|Invalid readiness setup: expected level remained +1; not an occlusion result.|
|177|Cancellation-driven recovery without a retry budget|13/15|Order-out regressed; old key-presence-only reopen checks were too weak to establish stable motion.|
|178|One-retry recovery; strengthened helper|11/15|Order-out and both reopen checks fail. Candidate removed from production.|
|179|Forwarded layer/delegate and eligibility/budget trace of178|11/15|Two consecutive native cancellations exhaust the budget; no retry-count escalation.|
|180|Normal-level cover with exact normal-level readback|12/15|Cover readiness passed, but it remained behind the target; genuine occlusion prerequisite failed.|
|181|Direct root-content path: `wantsUpdateLayer=true`, no-op `updateLayer`|12/15|Both reopening failures persist; rejected.|
|182|Compared with 180, child `orderFrontRegardless`|12/15|Front ordering, opaque coverage and containment passed; target still reported compositor-visible. Genuine occlusion remains unproven.|
|183|Final retained source, standard builder without an experiment|12/15|Model/chart checks pass; original order-out passes; genuine cover and both reopening cases fail.|

The original175/173 results and later180/181/182 still fail genuine cover and
both close/reopen cases. A later failure cannot be dismissed because a previous
key-presence assertion passed. The direct content-path experiment follows
[Apple's layer updating contract](https://developer.apple.com/documentation/appkit/nsview/updatelayer()),
but that contract does not establish the cause of these cancellations.

## Provenance and verification

The exact-source Native178 candidate binary SHA-256 is
`de9ad8d3ac2cfb62ac8f1428642f2ced36ecee6a4d0a70d8924d7aee47084134`.
The native179 diagnostic binary is
`a228e36b17e803d75d608fac58e5557420945cf81119f7c179f80150be8ec753`;
Native181 is `8de8c94bdffac8247fed3d4e67adff5cf524b8c4723a189d1fed06ba8d6639eb`;
Native182 is `d39d4dda1d23e98cb3cde329f74853b562be7a8969662fd51c169220b6d632ac`.

Immutable staged sources, dependency substitutions, source hashes, compiler
commands and binary hashes remain in each
`.build/native-dashboard-fixture-20261003-173` through `-183` manifest.
Task-owned builders, overlays, rejected candidate, terminal reports and a
per-run summary are retained at `/tmp/bloomy-menu-reopen-20261003/`.
`layer-trace-42964.jsonl` is the native179 trace. No provider log, credential,
prompt, synthetic inference or live provider action was used.

The one-retry candidate passed 26 focused ring tests, illustrating their bounded
geometry/store scope rather than native lifecycle correctness. The strengthened
helper compiled and executed in Native178–183; this is a verification improvement,
not proof that the bug is fixed. The final full suite passed 1,579 reported tests (1,530 app/telemetry, 21 protocol,
28 transport), with seven opt-in skips and no failures. Release compilation
completed successfully in 42.78 seconds. Both commands were joined to exit 0.
Native183's 110 production/helper source hashes all matched the retained source;
its binary SHA-256 is
`2cbecbf9cc0e5bac9fe7febee19dcbb1e1522596ceff3ad254315498cd2a9493`.
All 15 motion cases reached terminal status: 12 passed and 3 failed. Model and
chart checks passed; the combined native result is failed. This explicitly
keeps reopening, genuine occlusion and the release gate open.

The next investigation should isolate the native restoration/animation commit
boundary. Root ownership, drawing callbacks, direct layer-content updates and
cancellation retries have not solved reopening. Do not repeat those experiments
without changed evidence or replace the strict native predicates with geometry.
The broader layout, accessibility, profiling and distribution matrix remains
open; this checkpoint does not narrow the continuous polish goal.
