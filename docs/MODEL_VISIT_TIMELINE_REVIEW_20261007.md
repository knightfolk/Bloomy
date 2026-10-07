# Observed model residence timeline — October 7, 2026

## Scope

Activity → Metrics now presents retained model visits as a native Charts timeline.
One row per full model identifier shows observed residence and four distinct
symbols: work observed, no work observed, uncertain and last loaded. Short labels
have full-name hover help. Crosses identify clipped or uncertain boundaries.
The existing details remain in a collapsed disclosure; selecting Without work
opens them, and pagination retains the existing newest-eight starting limit.
The separate provider model reports are collapsed and continue to explain that
a reported most-recently-used model is not proof of loaded residence.

This uses the completed Metrics query range. Zero-duration observations remain
points, the closing boundary is exclusive, gaps are not filled, and original work
classification stays upstream. The upstream 500-visit retention limit is unchanged.
Blank time can be unobserved, filtered out or beyond retained history; it is not
proof of downtime. Last loaded is the last observation, not guaranteed current
residency. Observed work is not necessarily organic work or paid work.

No collector, poller, persistence, control action, dependency or telemetry schema
was added. This is a display checkpoint, not the joined day replay, reward-loss
analysis or a measured CPU/memory improvement.

## Preparation and review

A bounded read-only native source review caught a misleading blank-time caption;
it now describes undisplayed visits without assigning a cause. Native review also
caught merged accessibility point observations and misaligned categorical axis
labels. Explicit per-visit accessibility elements and stable numeric row positions
resolve those bounded failures without pixel offsets or invented point duration.
The final source review identified no remaining concrete finding in its scope.

Preliminary artifacts remain under the model-visit-timeline prefixes in .build.
They are not qualification. Five preliminary apps exited through normal Quit;
the final app was also quit normally and its PID 70449 was verified absent.
All finite builds and test handles were joined; no job was abandoned.

## Final verification

The final serial `swift test -c release --no-parallel` run reports 1,774 tests:
1,725 telemetry, 21 companion protocol and 28 companion host, with seven existing
opt-in skips. Six new tests cover points, clipping/gaps, distinct status symbols,
23/25-hour days, invalid intervals and distinct identifiers sharing display aliases.
Existing section rendering/retention tests pass. The 32 native staging checks and
`swift build -c release` pass. Logs include:

- `.build/model-visit-timeline-qualified-release-tests-20261007.log`
- `.build/model-visit-timeline-production-build-20261007.log`
- `.build/model-visit-timeline-row-native-build-20261007.log`

The final optimized isolated artifact is
`.build/model-visit-timeline-row-native-review-20261007/`.
All 127 fixture/view source hashes match the frozen source. Its manifest records:

- Manifest: `b16d99ba5baf3ea76b08b93f3593401c110f389efb6e88f88e765645b1610725`
- Executable: `f6624409c033a92f18ae8331e0b39e2b36c515a3772324ffadf005172e30b442`
- Telemetry library: `34a574a169dd64139079f8b9a41155d5d864774ea17a577bafc89887fcd1264b`

Computer-use inspection verifies aligned model labels/marks in wide light/dark
and compact light layouts. Compact dark checks cover the no-work filter. The
fixture grayscale rendering retains separate status shapes. Nine individual
accessibility visit rows, including point observations, are exposed; the no-work
filter gives one correctly scoped row. Details start with eight visits and Show
more reveals all nine fixture visits. Provider reports expand and collapse.
These are synthetic native checks, not a whole-app VoiceOver, audio-graph,
contrast or larger-text qualification. The chart accessibility representation
provides an explicit visit list; chart-descriptor/audio support remains unqualified.

The unchanged ordinary native proof reached terminal completion: Models and
Charts pass; motion remains 12/15 with `opaque_cover_occlusion_and_restore`,
`same_window_close_and_reopen` and `rapid_same_window_close_and_reopen` failed.
Results are retained in the final artifact's native-proof directory. No assertion,
animation timing or production motion behavior was changed.

The provider remains stopped and its configuration hash is unchanged. Installed
production app and unrelated dirty motion-proof, .mimosa and .zcodeignore work
were preserved. No push, release or installed update occurred. Local historical
machine attribution, joined work/action/credit replay, demand history, broader
native motion/accessibility/performance and distribution gates remain open.
