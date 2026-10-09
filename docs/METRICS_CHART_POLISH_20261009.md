# Metrics chart symbol polish — October 9

## Change and preserved meaning

Dense provider token-rate charts previously drew an area-24 model symbol at
every plotted observation. Overlapping symbols obscured lines at the compact
800 × 560 review size. Hardware charts also duplicated every line observation
with a point mark.

The new selector thins symbols only. Every existing plotted LineMark retains
its date, value, run identifier and linear interpolation. Summaries, the existing
600-observation line budget, data recording, read cadence and query scope are
unchanged. The selector keeps every symbol for histories of at most 60 points.
For denser history it retains each contiguous run's first/last and actual
minimum/maximum observations, plus observations spaced by roughly 1/40 of the
displayed time range. Boundaries and extrema take priority over symbol count;
highly fragmented history can legitimately retain many symbols. Invalid ranges
or backward dates within a run conservatively retain every symbol.

Dense connected token-rate runs use area-9 symbols. Isolated observations and
short histories retain the existing area-24 symbols. This second adjustment
followed native evidence: thinning alone remained crowded in this synthetic
journal with many short runs. The first candidate is retained as a diagnostic,
not accepted as sufficient polish. Hardware symbols retain area 12.

Both ID sets are calculated with the background Metrics summary, not in each
chart's render loop. Model-specific line patterns, colors, symbol shapes and
the numbered native legend remain. Missing measurements do not become zero,
and this change cannot connect different measured runs.

## Regression evidence

Nine pure selector regressions cover dense chronological spacing, run extrema,
singleton/two-point runs, separated repeated labels, reset spacing, short and
empty history, duplicate dates and conservative invalid inputs. An integration
regression verifies that dense symbols are derived separately from unchanged
line IDs/rates/run keys, original hardware values and complete summary totals.

The initial 66 focused checks pass. The first integration-test compilation
failed because the test used nonexistent summary property names; the corrected
test compares the complete equatable summary. The final full run reports 1,874
app tests plus 21 protocol and 28 Companion host tests passing. The 49 existing
native-fixture staging checks pass. Independent read-only review found no
actionable issue; it specifically left small-shape readability and native
chart accessibility behavior for rendered review.

The ordinary Release build passes. The first final fixture attempt overlapped
that build and failed because the shared Release telemetry module was replaced
with a module not compiled for testing. The source itself was not rejected.
The optimized test products were then rebuilt sequentially: 68 focused Release
checks pass. No concurrent package build is used for the subsequent fixture.

## Native review and limits

Review artifacts are isolated on Sol under
`/Volumes/Sol/BloomyReview/metrics-chart-polish-20261009/` because internal free
space is about 14 GiB. The baseline and both candidates use the same closed
100,000-record seed. Individual visible rolling windows differ slightly because
their endpoints advance; screenshots are visual comparisons, not a claim of
identical query membership or measured performance savings.

Screenshots and finite build/test logs are under
`.build/metrics-chart-polish-20261009/`. No real provider actions, inference,
downloads, key reads, configuration writes or production-app replacement are
part of this review. The unrelated motion-proof changes remain preserved.

Final native computer use verifies the 24-hour chart at compact light/dark,
compact grayscale and wide dark sizes. The model legend retains full accessible
names, numbered shapes and line patterns. Dense symbols are less dominant but
fragmented history remains visibly dense; this is not a claim that every chart
layout is finished. The 1-hour scope has one saved provider-rate observation:
its full-size symbol remains visible, with explicit stale status and empty GPU
history rather than fabricated values. Native AX snapshots retain chart-value
descriptions. This is not actual VoiceOver or audio-graph proof.

The verified optimized fixture is `native-verified/Bloomy Dashboard Fixture.app`.
All 143 recorded source inputs (128 production files and 15 fixture-support
files) match the checkout. Deep strict signature verification passes. Binary
SHA-256 is `8d2c06ca666fe850e2642bb98a2cf7e89f2d47d383fcfd823da9e92adb4d82bb`.
The earlier baseline's 127 production-file hashes match commit `1b838d1`.
All finite builds/tests have terminal results, and owned review apps were quit
normally after inspection. The installed production app remains running.

Native evidence names: `baseline-light.png`, `spacing-only-light.png`,
`final-light.png`, `final-dark.png`, `final-grayscale.png`,
`final-wide-dark.png` and `final-sparse-dark.png`. Scope and value descriptions
are in the matching final AX captures. The sparse review exposed existing
singular grammar ("1 samples"); it is recorded for the next text-polish pass.

Actual VoiceOver/audio graphs, large accessibility text, a complete chart-state
matrix, production resource qualification and distribution remain separate
open gates. This focused change does not complete the broad polish plan.
