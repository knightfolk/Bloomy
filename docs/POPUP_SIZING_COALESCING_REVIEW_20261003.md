# Popup sizing: coalesced native updates

The broader polish run continues after the Earnings/common-bar checkpoint.
Native inspection of its unchanged Earnings source confirms a readable wide
dark summary/time chart, compact recorded zero ($0.0000, eight recorded ledger
intervals out of 24) and a separate unknown-history message without a fabricated
zero. Those observations use the cooling-posture fixture, before this sizing
change; they do not establish complete Earnings accessibility or integration.

## Evidence and change

A five-second read-only `sample` of installed Bloomy 1.9.18/build 143 found
`PopupScrollingViewport.updateNSView` and its explicit document-fitting path
among active main-thread stacks (nine of 442 sampled main-thread stacks). Most
main-thread samples were waiting. This is a lead for a bounded component change,
not proof of a dominant CPU cause or a whole-app savings measurement. Installed
Updates preferences were only inspected and remain unchanged.

The retained native scroll bridge forced a full SwiftUI document fit on every
representable update, even when several observed sources arrived together.
Updates now share one deferred main-actor measurement. Width changes and explicit
layout requests still fit immediately; such requests cancel pending work.
Dismantling cancels the pending task and refuses late updates or measurements.
Content, scroll ownership and control state remain in the same hosted subtree.
There is no new repeating timer or provider call.

The first candidate removed explicit fits and relied only on preferred-content
size callbacks. It failed actual growth/shrink checks: retained document geometry
stayed at its initial height. That approach was rejected before the coalescing
implementation. Its failed test log and reconstructed patch are retained under
`.build/popup-sizing-comparison-20261003/`; this failure must not be treated as
accepted geometry proof.

## Verification

- Three new meaningful native regressions cover growing/shrinking live content
  at 80/360-point budgets, retained document identity and scroll position,
  immediate width/budget updates, 300-update latest-content bursts, explicit
  layout requests and pending-work cancellation on dismantling.
- Baseline geometry tests pass. The rejected notification-only run fails with
  12 issues. The coalesced focused run passes 32 reported tests in three suites;
  the final expanded full run passes 1,557 telemetry/UI, 21 companion protocol
  and 28 companion host tests (1,606 reported total), with seven existing opt-in
  skips. Final Release compilation passes.
- `Tests/PerformanceBenchmarks/popup-sizing-benchmark.py` stages the exact source
  and instruments only that copy. Five finite 300-update native bursts preserve
  all resulting document/viewport heights. Explicit fitting calls change from
  300 to one for each burst. Median synchronous burst time was 8.414 ms before
  and 0.097 ms after. These are clustered component updates, not an ordinary
  one-second cadence, total deferred/render time or a whole-app CPU reduction.
  Both processes exited; full reports and compiled sources are retained under
  `.build/popup-sizing-comparison-20261003/before/` and `after/`.
- Exact final fixture: `.build/popup-sizing-native-final-20261003/`. All 113
  source hashes match the checkout. Its executable SHA-256 is
  `8d791545d20204b228bc1f43c03db6393f5aba10caa8116193250550597f3469`.
- Native CUA review verifies the 360-point light popup keeps its shared command
  bar fixed while the body scrolls; Available expansion reveals its model rows
  and collapse recovers the preceding rows. At 80 points in dark appearance,
  native outer Scroll Down reaches provider actions, then GPU/energy/cooling.
  Restoring Screen, Reload and reopening restores the normal top position.
  The normal dark review popup remains open. Read-only source updates continue;
  no fan, provider, enrollment, key or inference action was performed.
- Installed PID 54773 remains running. Real provider PID 47646 still advertises
  exactly Qwen 3.8 and Gemma 4 with fresh Autopilot shadow evidence. Configuration
  SHA-256 remains `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

This is a local checkpoint, with no push, release or installed-app replacement.
Comparable production CPU/allocation profiling, complete native/accessibility
coverage, system motion delivery and the unresolved menu-ring gate remain open.
Unrelated menu-motion diagnostics and user files are preserved.
