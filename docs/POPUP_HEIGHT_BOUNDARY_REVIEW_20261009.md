# Popup height at the native placement boundary

The popup's native placement size now respects its current height budget even
when SwiftUI proposes a larger ideal height. Smaller content still uses its
natural size. Clearing an injected budget restores ordinary sizing. The change
does not replace the retained document or alter its inner scrolling, padding,
drafts, subscriptions or hidden-fitting suspension.

## Diagnosis and controlled proof

The earlier intermittent incident—an older retained review needing a second open
after a budget change—does not reproduce reliably. Before this edit, the current
native review correctly changed from 360 to 240 points. Environment-driven probes
also handled shrinking/growing budgets and ignored hidden preferred-size
callbacks. A new retained-document regression passed against the baseline. Those
results do not establish the older incident's cause.

A separate native boundary failure is deterministic. The controller accepted
an unchanged 720-point fitting result at every smaller requested budget. An
optimized, inert placement probe compiles the frozen `8c5cede` fitting source
and the final source with the identical harness:

| Current budget | Baseline native height | Final native height |
| --- | ---: | ---: |
| 580 pt | 720 pt | 580 pt |
| 80 pt | 720 pt | 80 pt |
| 360 pt | 720 pt | 360 pt |
| 240 pt | 720 pt | 240 pt |

The baseline probe exits one with four budget violations. The final probe exits
zero. Both ignore hidden callbacks. The oversized root deliberately does not
consume the environment budget: this isolates the placement boundary, not a
naturally occurring delayed SwiftUI callback. The native cap protects that
boundary without forcing the screen's full height into the padding-adjusted
inner scroll view.

## Regression and native verification

Evidence is retained under `.build/popup-height-transition-review-20261009/`.
Independent read-only review found no actionable issue in rounding, lifecycle,
smaller-content behavior or retained-document semantics.

- Two new regressions cover oversized input, fractional/large budgets, budget
  removal, hidden callback suppression and retained host/document identity over
  shrinking and growing budgets. The environment-driven test is supplementary
  retention coverage, not a baseline failure.
- The focused Release run passes 37 tests in two suites. The full serial run
  reports 1,862 app tests in 234 suites, 21 protocol tests and 28 host tests
  passing, with seven existing opt-in skips. All 49 fixture-staging checks pass.
  The regular Release build passes in 52.93 seconds. All finite jobs terminate.
- The optimized synthetic review matches all 142 recorded product source
  hashes and passes deep, strict review signature verification. Its binary
  SHA-256 is `31a79d0dd8955ea5539b281da50bb1a59c64fc83811472559a80fa17b58faaaa`.
  This is review signing, not notarized distribution.
- Native geometry records the same retained popup at 560×627 for Screen,
  560×80 after shrinking, and 560×360 after growing. Each fits the actual screen.
  Available remains expanded. At 80 points, native scroll actions/outer
  scrollbar positioning reach retained model rows. At 360 points, native body
  scrolling returns to the live-performance area below the fixed command bar.
- An unfinished Hosting port `8x` survives Screen→80→360 and dark reopening.
  Its invalid-port message renders, Apply remains disabled, and Done returns to
  the compact popup. No setting is applied and no provider command is invoked.

## Limits and next native work

The computer-use wheel input cannot target the tiny 80-point popup on this Mac;
native accessibility scrolling succeeds. Later direct scrollbar assignments in
the live 360-point content produce stale-reference errors; the advertised native
Scroll Up action succeeds. These input-path limits are not VoiceOver or ordinary
wheel-input qualification. Reaching every earnings/footer control at the tiny
budget is unqualified. The existing six-record geometry limit bounds the trace.

The panel minimum height is separate from the parent popup placement budget.
This checkpoint does not qualify every operational panel at an 80-point budget,
nor fix the old intermittent incident by inference. Hosting's repeated large
heading remains a concrete compact-panel polish follow-up.

Installed Bloomy 1.9.19/build 144 and its process remain unchanged. The provider
configuration and protected concurrent motion-proof edit retain their starting
hashes. The previous task-owned review exits normally; the new review remains
open at the dark 360-point popup. No provider start, stop, swap, inference,
network nudge, installed replacement, push or release occurs. Broader occlusion,
dialog, accessibility, resource and distribution gates remain open.
