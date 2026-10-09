# Retained popup fitting isolation

October 9, 2026. This checkpoint addresses native fitting while the popup is
closed. It does not complete the broader polish, motion or resource qualification.

## Behavior

The fitting controller starts inactive and prepares current geometry immediately
before presentation. Its own popup close notifications synchronously suspend the
retained native documents, cancel queued fitting tasks and disable automatic
preferred-content sizing. Hidden layout proposals use cached geometry. The
existing SwiftUI subtree remains mounted, retaining drafts, sheets and scroll
identity; live data still reaches that subtree. Reopening enables fitting and
measures the latest content against the current screen budget.

A weak document registry closes the actor-turn gap before SwiftUI propagates
the inactive environment. That shared presentation state takes precedence over
an older environment value. Late preferred-content callbacks cannot resize a
closed popup. Standalone scroll documents remain active by default. Production
and fixture construction no longer prepare a popup that has never been opened.

## Matched finite experiment

`Tests/PerformanceBenchmarks/popup-hidden-fitting-benchmark.py` compiles exact
before/after source snapshots with one staged-only counter at the actual explicit
document-host `sizeThatFits` call. The baseline receives an unused environment
key so both runs execute the same workload. Neither run uses provider telemetry,
commands, inference or hardware sampling.

| Native synthetic workload | Before | After |
| --- | ---: | ---: |
| Hidden updates | 1,501 | 1,501 |
| Explicit document fits while closed | 31 | 0 |
| Retained native document | Yes | Yes |
| Scroll position unchanged while closed | No | Yes |
| Fresh document after reopening | 400 × 520 pt | 400 × 520 pt |
| Reopened viewport height | 80 pt | 80 pt |

The five batches include shrinking and growing content, plus explicit layout
requests. Reopening also changes the width and viewport budget. Measurements
are saved under `.build/popup-fitting-isolation-20261009/baseline-final/` and
`after-final/`; source, instrumented-source and executable hashes are recorded.
The original pilot runs remain historical evidence.

Only explicit fitting counts and native geometry are compared. These counts do
not include all automatic SwiftUI/AppKit layout, nor establish a whole-app CPU,
battery or wakeup reduction. Burst timings are retained as diagnostics and are
not interpreted as a controlled performance comparison because concurrent Mac
work and compilation were not held constant.

## Verification

The new hidden-document regression first reproduced three geometry failures
against unchanged fitting behavior. Final checks:

- 35 focused Release tests pass, including pending-fit cancellation, same-width
  reopen, changed width/budget, stale active environment after native close,
  late preferred-size callback, screen events, retention and invalidation.
- The full serial Release run reports 1,840 app tests across 230 suites, with
  seven existing opt-in skips; 21 protocol and 28 Companion host tests also pass.
  Native staging checks pass all 49 cases. Production executables and the
  optimized fixture compile; deep strict review signature verification passes.
- All 142 frozen fixture source hashes match the checkout. The final fitting
  source SHA-256 is
  `08e32da8569bf1fab8735acf48f0dec86d7a8ecbb111bd46f7aaec1e4103c85a`.
  The before/after workload harness bytes match exactly. Independent read-only
  review found no concrete source defect.
- Native first opening displays the dense command bar and model rows. Available
  expansion and body scroll position survive parent close/reopen. Hosting's
  `8x` unfinished port survives panel dismissal, parent dismissal and dark
  reopening; Apply remains disabled, and the dark screenshot visibly shows the
  retained input and validation error. The More menu exposes the operational
  settings. Manage models opens within the popup.
- The accepted-work scenario presents Drain & Stop, and Cancel returns to a
  usable popup. The earlier idle scenario takes the inert client's idle action
  path instead of showing that confirmation; no real provider command runs.
  Dialog pixels are not requalified by this accessibility check.
- Reopening with a 240-point budget fits the changed viewport, renders the
  command bar, and permits body scrolling. The isolated app exits through
  More → Quit; no task-owned fixture/build/test processes remain.

Native evidence is under the checkpoint's `native/` directory. The review
executable SHA-256 is
`6b7b13cfe6c9d14ee69fdfe02a79e75dba392684493d693d2e8891db6144ab3c`.
The fixture substitutes inert dependencies and is not a distribution build.
This is finite native behavior inspection, not continuous motion or occlusion
proof. Whole-app resource measurements, blank dialog capture and the existing
native occlusion gate remain open. No installed replacement, real provider
mutation, push or release occurred; provider configuration and the protected
concurrent motion-proof source retain their pre-task hashes.
