# Financial sessions in the native UI — October 7

## Result and scope

Overview and Activity now consume one authenticated, atomic account-credit
report per history read. MonitorStore clears financial summaries, caches and
visible recommendations when account generation or ledger readiness changes.
Held success and error responses cannot restore another account's values or
an earlier readiness epoch. Same-session refresh failures may retain accepted
evidence as stale; missing history remains unknown.

This is a source checkpoint and isolated native review. No installed-app update,
distribution release, real account switch, model change or inference is claimed.
Provider-ID mapping to this Mac, legacy disclosure, retention, day replay and
the existing broader motion gates remain open.

## Implementation

- A weakly owned financial-session observer uses the client's existing stream;
  it adds no polling timer. Ordered state reads follow the newest pending read.
- Coalesced callers reject obsolete results. A caller for B drains an in-flight
  A acquisition, then acquires B. A failed first acquisition cannot populate a
  partial summary through later getters.
- Query identity includes account context, ledger readiness and a published
  epoch. Render-time masking clears old charts before a replacement task runs.
  Changed session revisions invalidate even a buffered lost/restored readiness
  cycle in the same account.
- Profit, energy and recommendation publication check captured context,
  epoch, request identity and source revision after suspension. Persisted
  journal rows remain replayable without reappearing as B's recommendations.
- Hourly model activity is derived in the same bounded raw-record pass as the
  displayed report. Activity filters and per-model earning-hour averages need
  no second financial read.
- Signed corrections and partial recorded totals stay visible. An hourly pace
  requires complete observed coverage. Credit records are labeled as credits,
  including Activity's summary and ledger table; they are not request counts.

## Regression and review evidence

The full Release run before the final column-width adjustment passed all 1,742
reported tests across telemetry, Companion protocol and Companion host targets,
with seven existing opt-in skips. The 32 native staging checks passed. The
production Release build passed. Logs are task-owned under `.build`:

- `financial-ui-session-final-release-tests-20261007.log`
- `financial-ui-session-final-staging-20261007.log`
- `financial-ui-session-final-release-build-20261007.log`

A bounded native Codex read-only review found two publication defects: B could
join and return from an obsolete A acquisition without acquiring B, and a
readiness restoration could revive retained charts/reports from the earlier
epoch. Both were repaired and re-reviewed with no remaining concrete finding.
Regression fixtures cover obsolete fetch/summary/report success and errors,
revocation, A/B/A generations, buffered readiness, ordered snapshots, cache and
recommendation isolation, newer same-context results, and weak observer lifetime.

The first full run exposed seven assertions in one coalescing test. Five task
yields did not prove the second caller had joined the held request, and a
five-second fixture hold could expire under concurrent suite load. The test
now waits for actual waiter admission and uses a bounded 30-second hold while
preserving its rejection assertions. The final full run passed.

## Native observations

The optimized synthetic fixture uses production views with inert financial
data, no network calls and no live provider commands. The reviewed artifact
`financial-session-final-native-review-20261007` demonstrated:

- A's first hour: work $0.1500, rewards $0.0200. B replaced these with $0.4500
  and $0.0600 while old scalar summaries cleared to awaiting values.
- Same-context loss of ledger readiness removed the chart with an actionable
  unavailable message. Restoration loaded B afresh; revocation removed it
  with the connect-account message.
- A failed replacement read displayed unavailable history without A's chart.
  A held B refresh was cancelled when a new A generation loaded.
- Activity's wide light summary displayed `166 credits` with the composition
  chart. Compact dark layout wrapped filters and retained its readable summary.
- Compact ledger inspection found the old numeric column width truncating
  `Work credits`. The final layout adjustment gives that column 88 points.

The saved synthetic scoped-read proof recorded eight started reads: six
completed, one failed and one cancelled, with the restored A generation ready.
Its task-owned original is `fixture-earnings-read-proof.json` in the fixture's
temporary directory. Synthetic 24-hour samples include future hours and cannot
support a claim about live income or complete real-day coverage.

## Final source qualification

After widening the column, 63 focused Release tests in seven suites and the
production Release build passed. The final optimized artifact is
`.build/financial-session-credit-column-native-review-20261007/Bloomy Dashboard Fixture.app`.
All 124 source hashes match the checkout; its manifest SHA-256 is
`9fdb872a50b170416fb8c475ce9fbef464486ae5e2ff8ad546624e8eed9fb11f`.
The initial attempt to build that fixture correctly rejected a telemetry
module produced without test support by `swift build`; the focused test run
regenerated a testable module and the subsequent fixture build passed.

Final compact dark rendering shows the complete `Work credits` header and its
numeric values. Final wide light rendering keeps missing summaries neutral
alongside the current account's hourly chart. The final account-switch,
same-context readiness, revocation, failed replacement and held cancellation
checks were repeated against the sole final app. A stale computer-use helper
had reopened the earlier fixture; it was closed, the helper changed to take an
explicit app argument, and these final checks repeated. The final scoped-count
export records ten reads: eight completed, one failed and one cancelled, with
the new A generation ready. Its retained copy is
`.build/financial-ui-credit-column-read-proof-20261007.json`.

The ordinary native gate also reached a terminal result on the final artifact:
Models and Charts pass; motion remains 12/15. Its same three failures are
`opaque_cover_occlusion_and_restore`, `same_window_close_and_reopen` and
`rapid_same_window_close_and_reopen`. All fifteen cases are terminal and no
failure is waived. The retained result and detailed motion evidence are
`.build/financial-ui-credit-column-native-proof-result.json` and
`.build/financial-ui-credit-column-motion-lifecycle-proof.json`.

Both task-owned review apps exited through normal Quit. No DashboardFixture or
Darkbloom provider process remains. Provider configuration SHA-256 remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The unrelated dirty motion-proof source remains unstaged and unchanged at
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
No installed update or distribution release is part of this checkpoint.
