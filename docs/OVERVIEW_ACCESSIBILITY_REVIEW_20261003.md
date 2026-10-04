# Overview summary accessibility — October 3, 2026

The exact previous native fixture exposed the Overview heading, machine/status
and all four summary cards as one long static-text element. Individual metrics
were not represented separately in that tree, despite the visual card layout.

Each summary now exposes its own name and value within a named metrics group.
The native heading has the heading trait. Separate label/value semantics retain
the observed-hour qualification, full spoken currency and rate units, and
unavailable descriptions. Decorative card text and symbols do not create
duplicate accessible children. Visible labels, fonts, spacing, data sources and
refresh cadence are unchanged.

## Checked evidence

- Baseline: `.build/overview-precision-native-20261003/` in wide dark Fresh state
  exposes a single text starting `Overview Darkbloom online MacBook Pro Observed
  today...` and continuing through all four metrics.
- Exact candidate: `.build/overview-accessibility-native-20261003/`. All 113
  staged source hashes match. Executable SHA-256:
  `9404e6f91714766f964d48dc091e063260b8895f6a85b1ecc37125b7ea6d4267`.
- CUA checks assert one native node for each `overview.metric.today`, `.hourly`,
  `.speed` and `.jobs`; one `overview.metrics` group; `heading Overview`; the
  expected value/qualification; and no element merging multiple metric titles.
  Nine checks pass: wide light Fresh, compact light/dark Fresh, compact light/
  dark micro-dollar earnings, compact light Offline, wide dark Offline, wide
  dark Fresh and wide dark Fresh after Reload. The adaptive layout exposes no
  duplicate metrics from its other branch.
- Fresh values include `6.4200 US dollars`, `2.1400 US dollars per observed hour`
  and `236 jobs`. Tiny values retain `0.000001` and `0.000000333` with those units.
  Offline values say `Awaiting earnings`, `Awaiting coverage`, `Awaiting samples`
  and `Awaiting job history`; missing readings are not announced as zero.
- Rendered compact light/dark Fresh, compact dark micro-dollar and compact
  light Offline cards retain the accepted layout. Wide dark Fresh remains
  readable with all four summaries, resource cards and three model cards.
  The isolated review is left on wide dark Fresh Overview.
- Focused rendering/formatting suites report 33 passing tests in two suites.
  Full suite reports 1,561 telemetry/UI, 21 protocol and 28 host tests passing
  (1,610 total, seven existing opt-in skips). Release compilation passes.
  Logs: `.build/overview-accessibility-targeted-tests.log`,
  `.build/overview-accessibility-full-tests.log`,
  `.build/overview-accessibility-release.log`.

Installed Bloomy remains 1.9.18/build 143. Provider PID 47646 has fresh state,
exactly Qwen 3.8 and Gemma 4 advertised, and Autopilot shadow. Configuration
SHA-256 remains
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
No installed replacement, real inference/provider action or OS accessibility
setting change occurred. Unrelated menu-motion diagnostics and user files remain.

This verifies native accessibility structure and bounded rendered states.
Actual VoiceOver navigation/narration is unproven. These scenarios have no
measured daily speed; its populated native readout still needs separate proof.
Complete source/size/large-text/localization coverage, sustained production
updates, motion and comparable whole-app efficiency remain open. This is a
local checkpoint, not distribution or completion of the broader goal.
