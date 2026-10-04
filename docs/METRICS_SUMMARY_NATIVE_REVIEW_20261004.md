# Balanced Metrics summary and source identity — October 4, 2026

Activity's seven summary values are now grouped into two time cards, three
performance cards and two work totals. The wide view no longer expands to a
six-card row followed by an isolated Tokens card. The existing adaptive layout
keeps equal heights within each row and fits three performance cards at the
380-, 550- and 1,040-point content widths checked by native component tests.
Smaller proposals still use the layout's ordinary column fallback.

Covered time shows observed coverage of the selected period. Active time shows
the fraction of intervals with known activity that were observed active, with
that measured denominator in text. Whole-Mac GPU averages have small capacity
arcs and numeric values; missing averages have a question-mark indicator and
Unknown. Measured zero is an empty arc with its numeric zero, not Unknown.
Model speed remains a number because no meaningful fixed maximum is supplied.
Full qualifiers wrap, and every metric has its own accessibility name, units,
scope and identifier. Native system fonts, colors, progress bars and the existing
ten-point card rounding are retained. These visuals add no clocks, polling or
network work, and do not change recorded totals or model attribution.

The missing-data native review also exposed a source replacement bug. With a
new `PerformanceHistoryStore`, the previous `.task` identity stayed the same;
Metrics kept reading and presenting the old store until manual Refresh. The
recorded view is now keyed by its history object's identity. Replacement cancels
the old pending read, discards its retained source-specific state and starts a
new read immediately. Period/model choices start from their normal defaults for
the replacement source. Ordinary hidden/reopened use of the same source retains
the prior completed summary, as verified in the preceding large-history review.

## Verification preparation and rejected checks

- The first isolated row test did not offer a definite width to its custom
  layout. All three requested window sizes therefore used the 115-point
  unspecified-width fallback, producing three separate rows. Bounded geometry
  output diagnosed this harness error. Supplying the same definite proposal
  as the application passes the unchanged same-row/equal-height assertions.
- Fraction checks cover missing, known zero, full scale, ordinary ratios,
  invalid denominators, out-of-range values, infinity and NaN.
- The source-replacement regression holds the first store's read, replaces the
  root's source and requires both cancellation and an immediate replacement
  read. It failed both assertions before the identity change and passes after
  it, while both stores retain healthy storage status. Its initial async actor
  predicate compile error was repaired before this behavioral comparison.
- The Debug native pilot showed wide light and compact dark cards, readable
  full-retention values, reachable counters/visits after scrolling, and seven
  independent native accessibility entries. Its missing-data source required
  manual Refresh before the production identity fix; it is retained as the
  diagnosed pilot, not final source-change proof.
- Two new inert review scenarios seed missing measurements and recorded idle
  measurements through the ordinary production database API. Synthetic
  observations are paused before selecting them so live fixture observations
  cannot contaminate either boundary. Real history and provider state are untouched.

## Final optimized native verification

- Full Release rerun: 1,572 telemetry/UI, 21 companion protocol and 28 companion
  host tests reported passing (1,621 total; seven existing opt-in skips).
  `.build/metrics-summary-final-full-tests-controlled-20261004.log` records the
  successful run. The first full run failed the new cancellation assertion:
  its five-second fake read expired while the busy UI queue took about fifteen
  seconds to replace the source. A cancellation-controlled continuation now
  holds that read, with the same assertions. Both the focused and full reruns
  pass. The failed log remains preserved.
- Final optimized fixture: `.build/metrics-summary-final-native-20261004/`.
  All 115 source hashes match the checkout. Binary SHA-256:
  `5d6513765f37d562f470d8bff240e5203c4e0feccc2ce012beac5faf5cd72565`.
  This is an inert, ad-hoc-signed Release review host, not a distribution build.
- Native CUA inspection of the 30-day, 100,000-row history shows two time
  cards, three performance cards and two work totals, including 67,485 requests
  and 20,245,500 tokens. Seven separate accessibility entries retain their
  full units and qualifications.
- Selecting Unmeasured metrics automatically replaces that history with 360
  samples, resets to 24 hours and shows Unknown for activity, speed, GPU and
  work counters. No Refresh was pressed. GPU indicators display question marks
  and the activity bar remains unavailable.
- Selecting Recorded idle metrics, again without Refresh, shows 360 samples,
  active time 0s, both GPU averages 0.0%, and both work counters 0. GPU rings
  are empty without question marks. Speed remains Unknown because no work was
  measured. The native zero-valued linear progress control has its normal
  minimal leading accent; its numeric value remains explicit.
- Compact dark inspection shows the three performance cards wrapping their
  qualifiers within their columns. Ordinary body scrolling exposes both work
  counters and Model visits. Wide light rendering was inspected separately.
- The existing Earnings graphics and unified icon-first popup bar were also
  inspected in this exact fixture. The bar visibly groups GPU, energy, cooling,
  Stop, Pilot, Auto, Nudge and navigation controls. Pilot opens its opt-in panel;
  Cooling opens qualified readings and its Refresh control. These bounded
  follow-up checks do not replace the earlier full common-bar action review.
- The task-owned final fixture quit normally after review. Installed app and
  real provider settings were not changed.

This checkpoint remains part of the larger polish/efficiency goal. Spoken
VoiceOver, large-text/localization, every source/display variant, production
resource savings, menu-motion and installed delivery remain separate evidence
requirements. The preceding large-history profiling still identifies repeated
full reads/analysis as further efficiency work; this UI change makes no CPU
improvement claim.
