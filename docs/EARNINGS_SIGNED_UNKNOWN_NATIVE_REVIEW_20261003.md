# Signed and unknown Earnings review — October 3, 2026

This is a bounded checkpoint in the ongoing native polish and efficiency work.
It does not complete the app, VoiceOver, performance or distribution review.

## Changes

Ledger corrections can be negative. Gross chart values now preserve signed
model work, rewards and aggregate fallbacks, as the table already did. Stacked
bars keep independent positive and negative cursors; signed charts use bounds
that cover both sides and a clearer zero grid line. Cancellation is not a
recorded-zero marker. Hourly profit and serving averages retain negative work
without changing their power coverage, model activity or idle-baseline gates.
Forecast/recommendation positivity checks are unchanged.

Hourly cards share the existing precise point formatter. One micro-dollar is
`$0.000001`, while zero remains `$0.0000`; nonfinite estimates remain unavailable.
Stacked-bar accessibility values use original amounts rather than cumulative
stack endpoints. Their lookup tolerates repeated custom-client identities.
This prevents a new dictionary trap; it does not repair every pre-existing
duplicate-series identity problem.

An all-unavailable calendar read shows native “No recorded activity” guidance.
An all-unknown read with uncertain boundaries instead explains that entries may
exist and retains its table. This distinction matters when the selection does
not align with stored hour boundaries, including fractional-hour time zones.
Recorded zero and completed-read retention remain distinct from both cases.

## Native observations and provenance

The inert dashboard fixture adds unknown, uncertain-boundary and signed ledger
reads, exact tiny hourly averages, and saved synthetic ten-second power intervals
covering complete hours from yesterday through the current complete hour. Signed
daily fixture values aggregate the hourly pattern. No live power/model acquisition,
account or inference request was used. `MonitorStore.start()` remains unused.

Native156 failed on two fixture-only type/argument-order errors. Native157 then
showed a pending read: actual compositor visibility briefly became true before
the review window was covered, correctly cancelling display work. Native158/159
have an explicit opt-in “Keep synthetic display reads on (review)” override.
It is off by default, leaves production visibility policy unchanged, and must
not be used to claim hidden-window efficiency or visibility behavior.

CUA inspected normal-scale native content at 800×560 and 1280×900:

- Native158: signed gross and profit in both bar layouts, Lines and Area;
  unknown gaps remain separate. A selected Qwen table retains `-0.0100` and
  `0.000001`, excludes rewards, and leaves throughput unavailable.
- Native158: recorded-zero Area retains separate gray markers; unknown periods
  do not create markers. Compact light/dark empty guidance stays reachable.
- Native159, after review corrections: compact light uncertain-boundary guidance
  and its visible Partial/dash table; wide light signed gross/profit stacks and
  negative hourly averages; compact dark tiny cards/table and unknown guidance.
  All three tiny cards visibly show `$0.000001`, with table values `0.000003`
  work, `0.000001` rewards and dashes for missing rows.
- Final stacked AX reads preserve `-$0.0300` and `±$0.000001` original profit
  amounts. Other styles still have automatic range grouping. These observations
  do not establish actual spoken point values or VoiceOver gap interpretation.

During the final CUA pass, a helper retained the older app binding and reopened
Native158. That candidate was quit normally; subsequent helpers take the app
explicitly. The final boundary screenshot/AX file was recaptured from Native159.
Final evidence is under `/tmp/bloomy-signed-earnings-review-20261003/`, including
PNG/AX captures and manifest verification. Native159's session is
`BloomyDashboardFixture-D833F928-270E-4CBB-AA28-4CFCEE4732BE` in the Mac temporary
directory. All 109 manifest source hashes, the final binary hash and the linked
debug telemetry archive match. The review bundle is isolated and ad-hoc signed,
not a notarized distribution build.

## Verification and remaining work

Final `swift test`: 1,519 app/telemetry, 21 protocol and 28 host tests passed,
or 1,568 reported tests including seven intentional opt-in skips. Meaningful
regressions cover signed corrections/cancellation, separate stack extents,
negative fallback identity, exact tiny amounts, repeated lookup identities,
unknown versus zero/boundary reads, signed profitability and unchanged evidence
gates. Final Release compilation passed in 43.00 seconds; `git diff --check`
passed. Logs are `/tmp/bloomy-signed-earnings-final-tests-20261003.log` and
`/tmp/bloomy-signed-earnings-final-release-20261003.log`.

Actual OS time-zone changes, full date-range controls, spoken chart values,
long-history rendering cost and the full native completion matrix remain open.
The installed production app and provider were preserved. Signed packaging,
notarization and isolated updater installation proof remain separate gates.
