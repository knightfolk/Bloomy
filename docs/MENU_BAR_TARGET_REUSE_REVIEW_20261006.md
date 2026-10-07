# Native menu-ring target reuse — October 6, 2026

Recreating the direct native target between cases removes both reopening
failures in this controlled comparison. Reused targets fail those cases in
both run orders; fresh targets sustain actual compositor motion in both orders.
Accumulated direct-target lifecycle history is therefore a useful next boundary
to investigate. This is not a production fix, a proof of deallocation, or a
replacement for the normal fifteen-case native gate.

## Controls and staging

The current baseline is `bf0f6b9`. The existing dirty `MenuBarMotionProof.swift`
was read and preserved byte-for-byte. Only staged copies receive the opt-in
overlay from `MenuBarMotionComparison.py`; ordinary fixture builds do not.
The overlay keeps all fifteen original case bodies, eligibility predicates,
compositor observations, holds and cleanup unchanged. It adds target identities,
generation numbers, preparation-phase diagnostics and explicit comparison-only
runtime metadata. Parent-label cases bypass the direct-target wrapper.

Both matched apps use the same optimized Release inputs, 119 recorded source
hashes, telemetry archive, resource/framework bytes and three existing inert
dependency substitutions. Their staged Swift bytes are identical. Normalized
compiler commands differ only by `FIXTURE_FRESH_MOTION_TARGETS`. Both receive
the same normal visibility preflight before each direct case. Fresh mode closes
and recreates the target after the first case; reused mode retains one target.
No redraw, transaction flush, animation retry or weakened assertion was added.

Review caught an initial fresh-only visibility preflight and missing context
for preparation failures. Both were corrected before native execution. The
initial pair compiled successfully but was not launched; it is not runtime
evidence. The matched pair also compiled successfully, with all four finite
builder jobs joined at exit 0. The native reviewer found no remaining edit
required before interpretation. Seven fail-closed staging regressions pass,
including a reverse transformation that reproduces the original Swift source
exactly and rejection of missing, reordered or new cases and changed anchors.

## Native results

Run order was reused → fresh, then fresh → reused using the same two binaries.
Every run completed the full motion → Models → Charts entry point before quit.

| Mode and order | Motion | Same-window reopen | Rapid reopen | Models / Charts |
| --- | --- | --- | --- | --- |
| Reused, first | 12/15 | Fail | Fail | Pass / Pass |
| Fresh, second | 14/15 | Pass | Pass | Pass / Pass |
| Fresh, reverse first | 14/15 | Pass | Pass | Pass / Pass |
| Reused, reverse second | 12/15 | Fail | Fail | Pass / Pass |

The reused target retains generation 0 and the same window/view/arc across
direct cases. Fresh mode records generations 0–12 and new window numbers;
the reopening cases retain their newly created window/view/arc throughout the
actual close/reopen transition. Pointer addresses may be recycled, so addresses
alone do not establish object lifetime or deallocation.

The four successful fresh reopening observations retain advancing angles both
before and after holds of 1.605–1.703 seconds, beyond the production 1.4-second
rotation. Post-hold angle advances are 0.190–0.193 radians. The one infinite
rotation key remains; compositor observation requests no native display.
The original helper's post-hold visibility, identity and clock checks remain.

All four runs fail genuine cover occlusion: front ordering and opaque coverage
cannot substitute for the target losing its compositor-visible bit. Each owned
cover is joined and its cleanup evidence retained. Models complete all three
cases and Charts both cases in every run. All aggregate reports remain failed
because motion fails. All sixty motion cases reached terminal status, with no
missing cases; fifty-two pass and eight fail. This does not qualify all Models,
Charts, accessibility or production routes beyond those fixture cases.

## Evidence and preservation

Matched outputs are `.build/menu-motion-reused-matched-20261006` and
`.build/menu-motion-fresh-matched-20261006`. Each retains its immutable staged
source, manifest and binary. `runtime-evidence/` and `runtime-evidence-reverse/`
retain the terminal motion, model-manager, chart and aggregate reports.
Corresponding `menu-motion-*-matched-build-20261006.log` files retain compiler
output. `.build/menu-motion-lifetime-summary-20261006.json` records per-run
hashes, outcomes and confirmed-absent parent/cover PIDs.

Parent binary SHA-256 values:

- Reused: `6c4c45a87f56f4866d00da26f0a19de6f3f281a535fb975f78875c2e4d837524`
- Fresh: `84328799fa773d23e92c40d031b2b54e254ec18aa39d17eca5b87d36041791c4`

The original motion helper SHA-256 remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`;
the shared staged overlay is
`9f81bed3b8bb3af08e03bc6e77ff715671bdffa7846d79997d236b40fd4e04ba`.
Current recorded source hashes, staged overlay bytes and binaries were checked
against their manifests. All four parent fixtures were quit after terminal
aggregate reports; every reported owned parent/cover PID was confirmed absent.

Product source and the existing dirty motion diagnostic were not edited. The
production app, provider settings, credentials and model cache were preserved.
The provider remains stopped. No fresh full package suite is claimed for these
test-builder-only changes; verification is the seven staging tests, optimized
compilation and the finite native comparisons.

## Next experiment and completion boundary

Isolate the preceding history without changing the reopening assertions: reset
once before detach, then retain that target through detach and both reopen
cases. Compare against the current reused control. A failure would narrow the
problem toward detach/reattach history; success would point toward earlier
cover/order-out history. Further controls are needed before assigning a cause.

The real status item uses NSHostingView inside NSStatusItem.button, unlike this
manual native window host. Actual status-item lifecycle and dependable genuine
occlusion still need proof. Keep the original reused-target gate, prior failed
reports and broader native completion matrix open. Do not replace the gate
with fresh-target results or add a production cancellation retry based on this
comparison. The continuous polish goal remains active.
