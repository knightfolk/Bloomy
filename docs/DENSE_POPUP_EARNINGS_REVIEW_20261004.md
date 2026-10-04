# Dense popup and earnings graphics checkpoint

The shared popup header now uses two rows: Bloomy/provider state plus GPU,
energy and cooling readings, followed by Stop/Start, Autopilot, Auto, Nudge and
navigation. It removes the separate brand/navigation row and telemetry divider.
Icons lead short labels; existing control handlers, freshness qualifiers and
guarded mutations remain in place. The header stays above the scrolling body
where the popup height permits; the existing outer viewport handles tiny screens.

Popup earnings now include Today/Week bars on a common dollar scale, with exact
observed amounts and the hourly rate beside them. Neither period is a target
or prediction, and partial observation remains explicit. Missing amounts stay
unknown; recorded zero has no filled bar. Micro-dollar values remain visible.
Activity adds contribution bars beside its existing composition and time charts.
When any contribution is negative, these bars share a midpoint zero, with
corrections extending left. They follow the same model/reward filters as the
displayed values. These visuals add no network requests or polling tasks.

## Verification

- Final `swift test -c release` completed successfully: 1,566 telemetry/UI,
  21 companion protocol and 28 companion host tests reported passing (1,615
  total; seven existing opt-in skips). Log:
  `.build/popup-dense-final-full-tests-20261004.log`.
- New comparison tests cover shared scale, missing versus zero, micro amounts,
  differing partial periods and non-finite/negative inputs. Contribution tests
  retain signed adjustments and filtered micro earnings. Native hosting checks
  fit graphical popup earnings in a 528-point column in light and dark.
- Final optimized isolated review app:
  `.build/popup-dense-graphics-final-native-20261004/Bloomy Dashboard Fixture.app`.
  All 114 source hashes match the checkout; binary SHA-256:
  `252b5489e6b96a3ca157ff8091bc11211b7ff02c17d68d96c0a6c98bf09ac6fc`.
  The fixture uses synthetic data and the existing three inert substitutions;
  it is ad hoc signed, not a distribution release.
- Native computer-use inspection covered the light/dark popup, wide/light and
  800 × 560 dark Activity, signed earnings with -$0.0200 rewards and $0.4600 total,
  and the dark 360-point popup. Header labels fit; the shorter popup retains
  the bar while its body scrolls. Unknown GPU/power are displayed as unavailable.
- Cooling opens its panel and Refresh entry. Autopilot opens its guarded
  controls, Auto opens the one-slot startup plan, and Nudge opens setup without
  sending. Energy routes asynchronously to Electricity settings. The accepted-
  work fixture presents the native drain-and-stop confirmation; it was cancelled.
  The ordinary fixture's inert idle Stop does not change the provider display.
- This run's matched-energy fixture had no complete current-day matched hours
  just after midnight: it correctly showed collecting data and Power unavailable.
  This checkpoint does not claim a new native proof of positive matched totals.
- The observation-span ring from the first candidate was replaced after native
  inspection because it did not communicate the requested earnings information.
  Earlier candidate artifacts remain isolated for provenance.
- Final read-only production check: installed app remains 1.9.18/build 143;
  provider PID 47646 advertises Qwen 3.8 and Gemma 4 in shadow mode. Configuration
  digest remains `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
  The final review popup remains open for inspection. No production replacement,
  inference, model change, publication or push was performed.

This is a bounded local UI checkpoint. Spoken VoiceOver, the full display/state
matrix, production performance and delivery remain part of the broader polish
and optimization work. Unrelated dirty motion diagnostics remain unstaged.
