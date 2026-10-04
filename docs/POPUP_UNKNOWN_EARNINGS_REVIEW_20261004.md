# Stable popup Earnings across missing data

The native baseline replaced all three Earnings tiles with one waiting line
when both calendar summaries were missing. Model cards consequently moved
upward. The popup now always renders its existing three-column graphic.
Missing values use neutral icons/backgrounds, a dash, a question mark and an
“unavailable” footer. Available values retain the recorded amount and color.
Known zero remains a real number with an empty amount bar. No history,
freshness, rate, timer, data-read or provider-action logic changes.

Missing-value accessibility/help explicitly says unavailable and distinguishes
missing history/coverage from zero. Retained timestamp help now avoids repeated
punctuation. Existing current-versus-retained rules remain intact.

## Checked evidence

- Before implementation, Computer Use reproduced the absent tiles in the
  exact previous retained-calendar review build. The synthetic no-summary
  result is preserved as `before-missing.json` in the proof directory below.
- A hosted layout regression compares populated, fully missing, each partial
  combination and recorded-zero graphics in both themes. Their heights differ
  by less than 0.5 points, with the existing 528-point width and less-than-130
  height limit. Existing fresh/retained sizing also passes.
- Focused checks: 38 reported tests in three suites pass. Log:
  `.build/popup-unknown-earnings-focused-20261004.log`.
- Full Release suite: 1,594 telemetry/UI + 21 protocol + 28 host reported tests
  pass (1,643 total), with seven existing opt-in skips. Log:
  `.build/popup-unknown-earnings-full-20261004.log`.
- Optimized native compilation passes. Log:
  `.build/popup-unknown-earnings-native-build-20261004.log`.

Final native app:
`.build/popup-unknown-earnings-native-20261004/Bloomy Dashboard Fixture.app`.
All 119 manifest source hashes and executable match the checkout. Binary SHA-256:
`5a0124313af50901247330dda370a741316e8c18d4bfaad0001b794250a9027d`.
It uses the established inert substitutions with acquisition off and ad hoc
review signing; it is not a distribution artifact.

Computer Use inspected actual production SwiftUI views with synthetic data:

- Fully unavailable, light and dark: all three neutral tiles remain, with
  missing-state AX values and unchanged model-card placement.
- Day-only light and Week-only dark: available and missing values stay in their
  own equal tiles. Missing Week does not become a zero or an inferred total.
- Recorded-zero dark, fresh recovery and retained account-failure dark:
  numbers, bars, qualifiers and timestamp help stay distinct and aligned.
- Dark 240-point popup: the command bar stays visible while the inner scroll
  reaches the tiles, model cards and Available disclosure. Available expands
  and collapses successfully. Normal screen-height sizing is restored afterward.

The computer-use wheel call failed with `windowNotFoundAtPosition`; this is
not accepted physical-wheel proof. Rebinding the exact running app and using
the scroll area's exposed native Scroll Down action succeeded. Actual physical
wheel behavior remains open. The screenshots/AX observations are in this task's
Computer Use history; synthetic state and source verification are under
`.build/popup-unknown-earnings-proof-20261004/`.

## Handoff and limits

All finite checks ended. The prior owned review app quit normally; the final
review host remains open at normal height, dark, recovered summaries and
Available collapsed, with synthetic publications paused. Installed Bloomy,
provider/watchdog, selected models, configuration and credentials are preserved.
No push, installation or release occurred. The unrelated motion diagnostic and
untracked user files remain outside this commit. Broader route/state, VoiceOver,
system motion, production resource and distribution proof remain open.
