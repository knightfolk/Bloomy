# Overview earnings precision review — October 3, 2026

Overview's existing cards are readable in the normal wide layout, but their
four-decimal summaries hide small recorded earnings. A one-micro-dollar value
renders as `0.0000`; the former model currency formatter renders a negative
micro-dollar as `-$0.00`. These are display errors, not missing ledger rows.

Overview now uses the same adaptive precision as Activity. Summary numbers
retain their separate USD unit; model active-hour amounts retain currency and
their existing derived-gross/estimated-net qualification. Ordinary summary
values remain `6.4200` and `2.1400`. Missing values remain unavailable, measured
zero remains zero, and extremely small finite estimates use scientific notation.
Chart point labels and cards share one formatter; their previous nonfinite
accessibility wording is preserved. No new sampling, timer or account query is
added to the production view.

## Verification

- Reproduced both old outputs directly with Foundation's former format styles.
- A new regression covers ordinary/zero/negative-zero values, positive and
  negative micro-dollar values, the three-hour derived rate, decimal-comma
  localization, nonfinite values and positive/negative subnormal estimates.
- Focused formatting, chart and native rendering suites: 48 reported tests in
  three suites pass. Full suite: 1,561 telemetry/UI, 21 protocol and 28 host tests
  reported passing (1,610 total, seven existing opt-in skips). Release compilation
  succeeds. Logs: `.build/overview-precision-targeted-tests.log`,
  `.build/overview-precision-full-tests.log`, `.build/overview-precision-release.log`.
- Exact isolated native fixture:
  `.build/overview-precision-native-20261003/`. All 113 staged source hashes match
  the checkout. Executable SHA-256:
  `a9e36603ae3aca6a135918b9450327efae202c6d3a08aeda56b472919818c385`.
- Native CUA review of the production Overview shows total `0.000001`, hourly
  `0.000000333`, Qwen `$0.000001` and Gemma `-$0.000001`. The new inert scenario
  supplies recorded model rows and ten-second attributed power intervals through
  the normal store interfaces. With no idle baseline, model cards correctly say
  `derived gross / active h`, rather than inventing a net estimate.
- Compact 800 × 560 light/dark: summaries fit the two-column layout, scrolling
  reaches both signed model cards and the remaining content, and signs/values
  remain readable. Wide dark fits all four summaries and three model cards.
  Offline review keeps earnings/coverage/history placeholders and Learning
  model metrics. Ordinary Fresh state retains compact four-decimal summaries.
  The fixture is left on wide dark Fresh Overview.

Installed Bloomy remains 1.9.18/build 143. Provider PID 47646 has a fresh state
with exactly Qwen 3.8 and Gemma 4 advertised, Autopilot shadow. Configuration
SHA-256 remains
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
No real provider action, inference, credential, hardware setting or installed
replacement was used for the native review.

This is a local checkpoint. Full populated layout variants, large text and
localization, spoken accessibility, real menu motion, comparable production
performance and the broader completion matrix remain open. Unrelated dirty
menu-motion diagnostics and user files are preserved.
