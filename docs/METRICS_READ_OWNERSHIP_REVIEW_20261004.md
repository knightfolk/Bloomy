# Metrics read ownership

Metrics now has one reference-owned successful raw read. Copies of its mounted
SwiftUI view and long-lived refresh task share that owner, rather than carrying
obsolete large value-State snapshots. Only this data ownership changed: filters,
errors, loading state, refresh cadence, journal reuse, cancellation and retained
summary behavior remain in their existing locations.

The private `PerformanceMetricsReadStorage` owns one published value. It performs
no database access, scheduling or analysis. This avoids introducing a parallel
view-model control layer while making the large buffer's lifetime explicit.

This is local review work. Installed Bloomy, the provider, its recovery watcher,
configuration, models and credentials were preserved. No push, installation,
inference, provider command or release was performed.

## Diagnosis and rejected candidate

Evidence is under `.build/metrics-ownership-audit-20261004/`.

At `d7dd5d7`, after changing from 100,000 rows to a roughly 2,880-row 24-hour
scope, the journal reported the correct smaller snapshot. Native heap still
found an obsolete **22,413,312-byte** sample array beside the current small
array. It remained after several narrower periodic reads.

A successful `leaks --noContent --nostacks --traceTree` inspection led through
SwiftUI's `StoredLocation<PerformanceMetricsRead>` `savedValues` and a task
capture. The reverse tree includes conservative paths; its many roots are not
a claim that each cache path is a strong ownership chain, or that this is a leak.
The live typed allocation and explicitly strong saved-value edge are the useful
evidence. No Instruments attach or privacy change was needed for this trace.

The first candidate explicitly read the result in the outer body before making
TimelineView. It compiled and displayed correct totals but **failed** ownership:
the same 22,413,312-byte buffer remained through multiple smaller refreshes.
Its frozen bundle is `.build/metrics-ownership-body-read-native-20261004/`;
binary SHA-256:
`460978a5e10a07cfa2b3062e2b612ffffb238bf5ab16695b7935089264d8fb08`.
That source experiment was removed intentionally. Its traces and manifest remain.

## Accepted native candidate

The exact-source optimized inert bundle is
`.build/metrics-ownership-reference-native-20261004/Bloomy Dashboard Fixture.app`.
All 118 manifest source hashes matched the inspected checkout. Binary SHA-256:
`4f1400fd3e8d15caa664b1324769cfa02f195760fb52490812649ae1fc6b5326`.
Linked telemetry SHA-256 remains
`abdb41aa22e6d950896cf7ff4b4b2a6695ad001b9eff252b252f9969152d364e`.

Computer Use verified the same 100,000 samples, 693h 59m covered time and
158 visits without observed work totaling 65h 50m. After narrowing to 2,850
rows, heap found **638,976 and 256 bytes** of typed sample arrays; the obsolete
large array was gone. This tests raw ownership, not total process memory,
battery use, or a production-wide performance improvement.

Further native checks passed:

- Several narrower periodic reads and a final narrower read after recovery
  retain only the current small buffer. The latter read reused all 2,809 rows.
- A held 30-day read retained the completed 24-hour result and explicit old-scope
  notice. Failing it kept those totals, showed the error and left Refresh usable.
  The normal loop/retry recovered the full result.
- A real successful empty read replaced the summary with zero samples and
  "Metrics are accumulating." Its typed allocation was only 256 bytes; the
  following normal read recovered full history.
- Window → Minimize All was confirmed miniaturized, not visible and display
  work disabled without a reopening observation before heap inspection.
  The journal released all 100,000 rows and reported zero retained rows; only
  the 256-byte auxiliary array remained.
- Reopening with a held read kept the completed full summary while raw rows
  remained released. Selecting Qwen displayed "Showing All models" until
  the read completed. Pending heap again had only the auxiliary array.
  On release, Qwen correctly showed 75 visits without observed work/31h 15m,
  and provider-wide request counters stayed unknown for that filter.
- The final recovered 24-hour read passed the ownership gate again. Compact
  dark Metrics rendered correctly with native vertical scrolling; the review
  window remains open on that synthetic view for inspection.

The synthetic read file is written at read start and completion. During a hold,
its pending-ID field can lag setup; the UI plus unmatched started/completed
counters verify the pending phase. The reusable gate deliberately rejects
pending/changing phases rather than treating them as a stable ownership result.

## Reusable regression and checks

`Tests/NativeUI/check-metrics-read-ownership.py` inspects only an explicitly
identified, already-running task-owned dashboard fixture. It sends no UI input.
It saves no-content heap evidence, checks read phase/process stability and
compares total typed sample allocation with a bounded allowance for current
scope and allocator rounding. Supply the linked sample stride from the Release
component benchmark; here it is 224 bytes.

Four live native gates passed: initial narrow scope, successful empty read,
hidden full-history release, and recovered narrower scope. Its parser/budget
also rejects both captured baseline/rejected-candidate allocation sets and
accepts the reference-owned result. Raw result JSON and source hashes remain
with the evidence. This does not substitute for the native UI recovery checks.

All 24 `PerformanceMetricsViewTests` passed, including source replacement,
released-buffer/empty distinction, query scope and cancellation/recovery.
Full `swift test -c release` passed: 1,588 telemetry/UI, 21 protocol and 28 host
tests; **1,637 reported tests**, seven existing opt-in skips. Logs:
`.build/metrics-ownership-focused-20261004.log` and
`.build/metrics-ownership-full-20261004.log`. `git diff --check` passed.

All finite builds, traces and tests completed. Baseline and rejected review
processes exited normally; the accepted review host remains open. The installed
app/provider processes remained running. Provider configuration SHA-256 remains
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

The specific obsolete raw-read retention case is resolved in this bounded
fixture. Whole-app resource profiling, other graph ownership, production
integration, VoiceOver, menu-bar motion and the broader polish matrix remain open.
