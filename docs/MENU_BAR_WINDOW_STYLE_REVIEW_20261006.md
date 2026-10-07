# Menu-ring window-style comparison — October 6, 2026

The production SwiftUI label sustains rotation after normal and rapid reopening
in both titled and borderless comparison windows. Window style alone therefore
does not reproduce the earlier manually constructed AppKit host failure.
Genuine occlusion and restoration remain unresolved; no production animation
change or release qualification is claimed.

## Controlled comparison

The initial pair uses current `main` (`4e3e8c7`) monitor source, the same current
Release telemetry archive/modules, resources and Sparkle framework. Both parent
executables are optimized with `-O`; both retain the fixture's existing `DEBUG`
definition. These are diagnostic apps, not shipping Release bundles.

The bundle identity, synthetic inputs, initial 300×140 content rectangle,
NSHostingController hierarchy, fresh target per case, ordering calls,
eligibility predicates and cleanup are identical. After normalizing output
paths, compiler commands differ only by `FIXTURE_BORDERLESS_TARGET`.
Recorded source/dependency hashes match between the pair. Native style-mask
readback is 3 for titled/closable and 0 for borderless.

NSHostingController subsequently sizes to the label's intrinsic size: 72×50
including titled chrome versus 72×18 borderless. That is a measured consequence
of the host, not an additional configured geometry change.

| Initial case | Titled | Borderless |
| --- | --- | --- |
| Visible active compositor advances | Pass | Pass |
| Same-window close/reopen, retained host/view/layer | Pass | Pass |
| Rapid close/reopen without a yield between operations | Pass | Pass |
| Actual SwiftUI dismantle, retained-view stress | Pass | Pass |
| Separate-app genuine occlusion and restoration | Fail after uncovering | Cover startup rejected |

Reopening checks preserve exactly one production rotation key and require
advancing compositor angles before and after a hold exceeding the 1.4-second
rotation duration. No forced display, transaction flush or animation retry
establishes success. Dismantle remains driven by SwiftUI root removal, followed
by active configuration and lifecycle stress of the retained removed view.

## What the failures establish

The initial titled cover established genuine occlusion: the target's visible
flag cleared, rotation stopped, and a 0.641-second covered hold retained that
state. The cover then closed on parent request and exited normally. The target
briefly regained visibility and its animation key, then lost visibility again
before the angle observation completed. System Reduce Motion remained off.
This does not demonstrate failed rotation in a continuously eligible window;
the reason for renewed occlusion is not established.

The initial borderless cover was 98 points high (18-point target plus two
40-point margins). Its unchanged helper requires dimensions of at least 100,
so it exited with status 64 before readiness. The parent now centers a cover
with each dimension at least 100. Helper bounds, opaque/front-order/containment
requirements and genuine compositor occlusion are unchanged.

A follow-up pair adds that size correction, owned-window order readbacks and
an experimental explicit target-foreground action after cover exit. Both
reached terminal 4/5: covers started, but genuine occlusion was not established,
so the foreground experiment was never exercised. That action was removed.
The final retained source preserves automatic uncovering without an explicit
show, redraw, retry or relaxed visibility predicate.

The exact-source final borderless run again reached terminal 4/5. Its cover
started, fully covered the target in WindowServer and closed normally; the
target retained its compositor-visible flag. The size defect is corrected,
but geometry cannot substitute for genuine occlusion. The successful initial
transition and later prerequisite failures show inconsistent observations in
this desktop environment; capture interaction remains an unverified hypothesis.

## Verification and retained evidence

All five finite builders were joined at exit 0. All 25 diagnostic cases reached
terminal status: 20 passed and five failed, with no missing cases. The final
110 recorded monitor/helper source hashes match the checkout. Product sources
and telemetry inputs remain unchanged. Python syntax, builder help and
`git diff --check` pass. No new full package suite was run for these fixture-only
changes; earlier app-suite results are not claimed as fresh verification.

Evidence directories under `.build/`:

- `menu-host-style-titled-20261006`
- `menu-host-style-borderless-20261006`
- `menu-host-style-titled-restore-20261006` (unexercised foreground experiment)
- `menu-host-style-borderless-restore-20261006` (same experiment)
- `menu-host-style-borderless-final-20261006` (retained source)

Each retains immutable staged inputs, compiler manifest and terminal report;
cover status/log files were copied alongside the reports. Corresponding
`menu-host-style-*-build-20261006.log` files retain compiler results.
`menu-host-style-summary-20261006.json` records binary/report hashes and outcomes.
The final parent binary SHA-256 is
`e30584eb318e1ee85e3236143a571e25e97a98df4e46d9b1100b73f5b11a78a9`;
the unchanged cover binary is
`586ca5f3591c622c4ce614eed5f6dedaf0eb73feb7b484542f31a2f6466efac2`.

All parent fixtures were quit normally after their terminal reports. All
reported owned PIDs were confirmed absent. The provider remains stopped and
its configuration SHA-256 remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The production app, preferences, credentials, model cache and unrelated dirty
`MenuBarMotionProof.swift` diagnostics were preserved.

## Next boundary

This comparison uses NSHostingController. The real status item embeds an
NSHostingView inside NSStatusItem.button. The separate 15-case gate uses a
manual native view and reuses one target across multiple cases, including a
failed cover before reopening. It remains failed/open; these comparisons do
not replace it.

Next isolate fresh versus reused targets in that manual host while retaining
its geometry, ordering, animation checks and visibility requirements. Do not
repeat layer-ownership changes or add cancellation retries without new evidence.
Genuine occlusion still needs a reliably established transition, and actual
status-item lifecycle proof remains required. The broader native polish,
accessibility, performance and distribution matrix remains partial.
