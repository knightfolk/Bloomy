# Quit cleanup and keyboard review — October 2, 2026

This checkpoint makes native Quit await owned cleanup and closes two unified-log
reader lifecycle gaps. It also supplies stronger Support keyboard proof and a
short installed-app CPU baseline. The full polish/efficiency goal remains active.

## Shutdown behavior and race proof

Production previously launched an unawaited cleanup task from
`applicationWillTerminate`; AppKit could exit before that task reached the log
reader. `ApplicationTerminationGate` now rejects the initial exit request, owns
one cleanup task, and retries native termination after cleanup completes. Only
the completed retry is approved. Repeated Quit requests reuse that task.
This uses the already verified fixture pattern rather than its previously
problematic nested `terminateLater` wait.

The production delegate invalidates its UI, cancels the current provider action,
awaits CLI update monitoring and app monitoring shutdown, then joins any pending
provider operation after the automatic watchers have stopped. Capturing the
operation task before cancelling it preserves the existing cleanup, detached
reconciliation, and action-history outcome. Cancellation alone did not join
those steps; deterministic tests held them after cancellation and demonstrated
both overlapping joins remaining suspended until release.

The production delegate's absent termination hook had a failing regression;
the initial cancel-only control join failed two premature-return assertions.
Those worker runs are retained in tool transcripts (sessions 18102 and 31391),
not separate raw log files. The worker's final 12-test run (session 53942) passed
and released/joined every controlled operation. The final full suite below also
covers these tests.

`UnifiedLogStreamer.eventSource()` supplies the event stream with an explicit
awaited stop capability. Production passes that owned source to `TelemetryService`.
Service shutdown closes it even when no iterator ever started or a consumer
exited between events while the stream remained retained. The compatibility
`events()` API keeps its previous iterator-cancellation behavior; explicit
ownership guarantees apply through `eventSource()`.

One regression stopped the service before start and observed its child still
alive before explicit source cleanup was wired. The corrected path reaps that
child while both source and service remain retained. Another cancels after the
first event without calling `next()` again, then overlaps normal and already
cancelled explicit stops. It verifies process exit and closed pipe handles.
The combined active-service test ingests an event, then stops a reader that
ignores TERM; shutdown returns only after its bounded escalation and exit.
These children are synthetic shell/sleep processes, not the real provider.

Independent review found a final natural-EOF race: cleanup could be claimed
before its handles/observer had finished, allowing explicit stop to return early.
A held-cleanup regression reproduced that return. Explicit stop now joins a
completion condition signalled at cleanup return. It waits outside the session
and cancellation locks; natural process-exit callbacks do not wait on this
barrier. This covers normal completion, cancellation, launch failure, and
deinitialization without adding a callback/`waitUntilExit` lock dependency.

Apple documents the native delegate's exit decision in
[applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)).
The pinned Sparkle source observes actual app termination before proceeding and
permits delayed/cancelled quit requests. Compatibility with the cleanup retry
is an inference from those source paths, not a live updater test.
[Termination observer and quit request](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Sparkle/InstallerProgress/InstallerProgressAppController.m#L343-L405),
[post-exit installation](https://github.com/sparkle-project/Sparkle/blob/ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a/Autoupdate/AppInstaller.m#L403-L410).
Cleanup that never completes keeps Quit unapproved; no premature-exit timeout
was added.

## Native proof and keyboard correction

A fresh process of native 22 reused its recorded binary from the previous
checkpoint. In wide light Support, a native Raise action on the actual preview
sheet preceded keyboard input. Space toggled review; Tab traversed checkbox,
Close, Save, then checkbox again. Space cleared review and Return left Save
disabled. Space restored review and Return opened the native export dialog.
Raising that panel and pressing Escape returned to the reviewed preview without
an error; raising the preview and pressing Escape closed it. The same focus
cycle, Return export, and Escape cancellation passed in compact dark appearance.
No report was saved or shared, and no production view/focus code changed.

The earlier unchanged keyboard observations did not establish the recipient's
activation or key receipt. The existing trace hooks only the owned main window;
it does not sample Support/export sheets and excludes Return/Escape. A main
window with `isKeyWindow=false` cannot identify a sheet's responder. The fresh
targeted results correct the prior proof gap without attributing an unverified
production defect. Actual VoiceOver remains separate.

The dashboard fixture now uses the same `ApplicationTerminationGate` as production.
Native 23 was raised and quit through Command-Q; process absence was checked.
Final-source native 25 opened the actual transient popup and quit through its
Quit button; process absence was checked. These exercise native AppKit gate
sequencing with synthetic stores. They do not establish native production
termination with a live subprocess, provider, or updater. No real provider start,
inference, swap, download, credential/configuration write, permission change, or
production app replacement was needed.

Native 25's manifest records 78 current source hashes, all matched before launch.
Its binary hash also matched. Native 23 predates the final provider-control join
and cleanup completion barrier; native 24 was an unlaunched intermediate before
the barrier. Neither is counted as final-source subprocess proof.
After final native verification, only the duplicate native 24 build output was
removed (42,418,468 bytes); its manifest and build log remain in the evidence
directory. Tested fixtures and unrelated work were retained.

- Manifest: `/tmp/bloomy-efficiency-20261001/native25-fixture-manifest.json`.
- Binary SHA-256: `c5f3085f6e606eb5ee18ef808a08e8acc775798dec0b5ab5a4d3b6ae25530b5f`.
- Linked telemetry SHA-256: `a8b51e2df2f6e0244733279b1b5f844c23f5d58e0e6fc08a7fd53d7f1754d65b`.

## Verification

All log paths below are under `/tmp/bloomy-efficiency-20261001/`.

| Evidence | Result |
| --- | --- |
| `unified-unstarted-reader-red-tests-02.log` | One meaningful child-still-alive assertion failed before the service explicitly stopped its source. |
| `unified-eof-cleanup-red-tests.log` | One early-return issue reproduced while natural cleanup was held. |
| `quit-reader-cleanup-focused-tests-02.log` | 45 tests in three suites passed in 1.018 s. |
| `quit-reader-cleanup-full-tests-02.log` | 1,173 app/telemetry tests in 153 suites (25.972 s), 21 companion tests in five suites (0.012 s), and 28 host tests in nine suites (11.681 s): **1,222 passed**, terminal exit 0. |
| `quit-reader-cleanup-release-build-02.log` | Final release compilation passed in 41.18 s, terminal exit 0. |
| `native25-quit-cleanup-build.log` | Final native fixture compiled and its manifest/binary were checked before the popup Quit test. |

The first service red attempt (`unified-unstarted-reader-red-tests.log`) stopped
at a nested Swift Testing macro expansion in the newly added gate test. Moving
the termination request result into a local fixed that test-only compilation
issue before the meaningful red run. The first 1,220-test full run and 50.45-second
release build passed before the later EOF barrier and active-source regression;
the second full/release logs are the final-source evidence.

## Installed-app efficiency baseline and preserved state

With provider/recovery stopped and production UI untouched, PID 31677 used 1.58
CPU seconds over a 30.003-second window: **5.27% of one core**. Median RSS was
202.89 MiB (202.81–203.06 MiB). Point CPU readings ranged from 0–23.1%; they
use a different averaging window. The five-second stack sample found the main
thread waiting in 401/442 samples, with small active counts in SwiftUI/chart
layout, Metrics analysis/decoding, uptime scans, and legacy parsing. Those counts
identify work, not CPU shares or battery-life estimates.

This describes the preserved installed v1.9.15/build 140 binary. Current-source
uptime, parser, Metrics, and hidden-display improvements are newer and were not
installed for this measurement. No current-source savings are claimed. Repeat
comparable visible/minimized measurements with the same history after the
production launch/replacement gate is resolved. Evidence is
`stopped-provider-cpu-window.json`, `stopped-provider-cpu-sample.txt`, and
`stopped-provider-cpu-report.txt`.

Production remains original PID 31677, started October 1 at 22:40:57, binary
SHA-256 `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Real provider configuration SHA-256 remains
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
The current production child reader 31763 and pre-existing adopted readers 6471,
57495, and 74340 were preserved. The adopted readers are consistent with the old
exit gap, but their original parents cannot be proven from current process state;
they were not assumed task-owned or terminated speculatively.

Remaining gates include the full native route/state matrix, actual VoiceOver,
controlled Reduce Motion, current-source production performance, and native
production Quit/updater integration. The production Sol cache permission
boundary and scoped removable-drive reset remain pending human approval.
Provider/recovery stay off; no privacy/drive/Keychain workaround, push, signing,
notarization, or publication is part of this checkpoint.
