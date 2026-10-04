# History field accessibility and selected-entry arrivals — October 4, 2026

The selected History entry previously appeared in the native accessibility tree
as one long text value, combining its title, all fields and account scope.
It now contains a heading and independent field groups. Each group keeps its
plain caption and native selectable value; selectable Text is not relabeled.
That preserves the earlier macOS recursion repair. Visual spacing, precision,
table selection, filtering, journal storage and acquisition are unchanged.

## Checked native behavior

The exact optimized fixture is
`.build/history-fields-native-final-20261004/Bloomy Dashboard Fixture.app`.
Its 116 source hashes match the checkout, including fixture/support sources.
Binary SHA-256:
`ea73f2316c1bf692d0a8872c0e890aa2513ebbe8ae6ce39a8f3365dd5b952c79`.
Its linked telemetry archive also matches the current Release archive. It is
an inert, ad-hoc-signed review bundle, not a distribution artifact.

- The finite native proof runs under `NSApplication.run()`, creates one owned
  selected-job window, and closes it. Its terminal report confirms nine unique
  fields with captions and exact values, including earning ID 14,998, 120 prompt
  tokens, 40 completion tokens and $0.000199. Account-wide qualification remains
  accessible. The proof uses the fixture's owned task, with overlap prevention
  and cancellation joined by Reload/quit.
- Actual CUA inspection of the final 5,000-entry mixed history confirms the
  heading and nine field groups in wide light and compact dark. Search for
  earning 14998 bounds the inspected table without removing retained records.
  The long model identifier remains complete in details and wraps at compact
  width. Ordinary outer and detail scrolling reaches tokens, amount and scope.
  A native double click selects part of the model text; selection is preserved.
- A new inert fixture action passes through the production recorder without
  sending a network nudge. The selected earning and its details stay intact
  through this arrival and resize. Its receipt confirms 5,000 records before
  and after insertion and confirms the new action is present. Read-only SQLite
  inspection finds 1,000 rewards, 2,000 jobs, 1,001 nudges and 999 swaps after
  retention. Earning 14998 still has tokens 120/40 and amount 199 micro-dollars.
- Final native reports are copied to
  `.build/history-fields-final-evidence-20261004/`. The fixture quit normally;
  process absence was checked. Installed Bloomy remains 1.9.18/build 143. Provider
  configuration hash is unchanged; Qwen 3.8 and Gemma 4 remain advertised with
  Autopilot in shadow mode. No live inference or provider mutation was performed.

## Rejected checks and repairs

Initial unfiltered row selection timed out in the computer-use observation.
A three-second stack sample showed heavy AppKit accessibility table enumeration;
the same review PID remained live and later reattached. The resize had not yet
run. Search bounded subsequent inspection to one earning. This is an observed
tool/native accessibility boundary, not proof of ordinary serving or UI cost,
and no CPU improvement is claimed from the field grouping.

An attempted SwiftPM-hosted accessibility assertion found no field nodes before
or after the production change. That host did not reliably expose the tree;
the failed check was removed and replaced with the finite app-native proof.
The before/after production evidence is the actual CUA tree, not that failed
harness. Failed logs remain in task-owned build paths.

The first fixture build produced a broad type-check diagnostic. Extracting its
new history controls into a small view exposed an invalid read of a private
fixture property. The controls now use public readiness; action methods retain
the private termination guard. Final Release fixture compilation passes.

The first full Release suite missed a unified-stream EOF snapshot within the
existing 100 ms test deadline. The functional test now allows a bounded two
seconds for observation and retains every event, staleness, capture-time and
reason assertion. The final full rerun passes: 1,572 telemetry/UI, 21 companion
protocol and 28 companion host tests reported passing (1,621 total, seven
existing opt-in skips). Successful log:
`.build/history-fields-full-release-tests-final-20261004.log`.
The failed initial log is retained separately.

This is a local accessibility checkpoint. Actual spoken VoiceOver, other
locales/displays, real account arrivals, large-table accessibility enumeration
cost, production performance, menu motion and installed delivery remain open.
It does not complete the broader polish and optimization goal.
