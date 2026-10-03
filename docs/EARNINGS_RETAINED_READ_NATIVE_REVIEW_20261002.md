# Earnings completed-read retention — October 2, 2026

Earnings now publishes one completed report containing its resolved dates,
calendar/time zone, model, measure, buckets, attribution, averages, profit and
token rates. A new read retains that report. The permanent caption names the
selection actually shown; pending changes and failures qualify previous results.
Charts, tables and About use the completed interpretation and date formatting.

First-read progress, unavailable storage and successful empty history are
distinct. A nil primary read means unavailable, and only a successful empty
payload replaces recorded results with No recorded activity. Optional average
and token-rate absence retains existing semantics; every secondary-reader error
is not covered by this pass.

UUID tickets reject superseded completion/failure/cancellation, even for identical
queries. Cancellation is checked after every suspension, and power intervals are
captured before suspension. Publication is coherent for the view; separate local
reads are not claimed to be one database transaction. Hidden tasks have a stable
nil identity, suppressing ledger-triggered reads. Hiding/leaving cancels pending
work, and restoration starts a new read. No timer or provider action was added.

## Source verification

- The 17-test focused pass checks first-read failure, complete payload retention,
  changed scope, successful empty replacement, stale/mismatched callbacks,
  cancellation, calendar identity and captured time-zone formatting. The final
  full pass adds an identical-query stale-callback case.
- An NSHostingController test observes zero hidden reads, begins a cancellable
  inert read on visibility, cancels it on hiding, changes ledger revision while
  hidden without another read, then restores and cancels a second read. No
  downstream bucket reads occur. MonitorStore collectors are never started.
- Full tests pass: 1,409 app/telemetry in 186 suites, 21 protocol and 28 host
  tests: 1,458 reported, with six opt-in checks skipped (focus, benchmarks,
  live public endpoints and live adapter reads).
  Log: `/tmp/bloomy-earnings-retained-final-tests-20261002.log`.
- Release compilation passes in 46.50 seconds; log:
  `/tmp/bloomy-earnings-retained-final-release-20261002.log`.
- The first focused pass rejected a test's hardcoded 24-hour expectation.
  Omitting AM/PM does not force a 24-hour locale. The repaired test compares
  captured zones without imposing a clock preference. Accepted focused log:
  `/tmp/bloomy-earnings-retained-focused-r2-20261002.log`.

## Native131 review

The inert review-signed app is
`.build/native-dashboard-fixture-20261002-131/Bloomy Dashboard Fixture.app`.
Normal synthetic publications were paused; fixture controls hold/fail/empty the
first query stage. Actual screenshots and native state confirm:

- Compact light: held Refresh retains the chart/table and scope with Refreshing
  local history. Choosing Gemma cancels the hold and renders Gemma's result.
- Compact light: requested Qwen retains the completed Gemma report and its
  explicit Gemma caption. Failure retains that chart with a last-completed-read
  error. Refresh recovers Qwen, also inspected in wide dark appearance.
- Wide dark: requested This week retains Oct 2 daily axes/scope during a hold.
  Successful release updates the dates to Sep 27–Oct 3 and daily buckets together.
- Wide dark: requested profit retains the Earnings caption/chart during a hold.
  Successful release shows Est. profit / hour and qualified No covered profit
  hours because the fixture has no saved power. Successful empty then replaces
  the report with No recorded activity and explains that missing is not zero.
- Re-entering with a held first read displays Reading local history, with no
  completed scope/chart/empty state. Failure shows History unavailable; explicit
  Refresh recovers populated history.
- Native Window-menu Minimize cancels a held refresh. The next menu's Minimize
  is disabled, confirming the minimized state. Choosing the named window restores
  it and triggers a fresh captured read. Switching to Metrics during another
  hold cancels it, and returning to Earnings reads again.

Saved gate counts: 14 started, 9 completed, 2 failed, 3 cancelled and 1 empty
(empty is a completed subset). These count the first query stage, not full-report
completion; rendered checks prove the latter. File:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-47204B3A-333D-4537-84E8-A57AF88877A3/fixture-earnings-read-proof.json`.
The fixture exits normally with no remaining process.

All 101 manifest source hashes match. Binary SHA-256:
`ddc0d55eb6ebc77d8831e4b8fa99260ca03c7d86819eb1a18c6bb6172d3f25a5`.
Telemetry SHA-256:
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Exactly the builder's three documented inert dependency substitutions remain.

## Rejected observations and limits

CUA rejected direct AX presses on duplicated Next read items as ambiguous. The
accepted repetition opens the Earnings submenu and uses native selected-menu
keyboard state. An absent AX minimize button was not considered success; the
accepted minimize uses the Window menu.

After restoration, a Tab attempt returned no focused-control evidence and showed
an inactive window. Exact-path rebind, Raise and a background click did not prove
activation. This is not keyboard proof. Native129 baseline keyboard evidence
remains; pending Refresh focus, date/average controls, table key scrolling and
actual VoiceOver remain open. Host keyboard preferences were unchanged.

Live time-zone changes, native nil storage/invalid date ranges, secondary-reader
failures, real-ledger and whole-app performance, energy/allocation measurement
and distribution remain open. Production PID 61760 (October 2 12:55:28 launch)
and the real provider are unchanged. The broader polish goal remains active.
