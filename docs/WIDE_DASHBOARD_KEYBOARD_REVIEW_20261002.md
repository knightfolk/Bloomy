# Opportunity scrolling and Earnings numeric review — October 2, 2026

This is a bounded checkpoint in the [active polish plan](APP_POLISH_OPTIMIZATION_PLAN.md),
not completion of every route or permission to distribute a build. Root inspected
native review apps through computer use. Three native workers reviewed source;
two made isolated changes and a third independently reviewed the integrated diff.
Production Bloomy, its unsaved work and the stopped provider were preserved.

## Changes and regression evidence

- Earnings signed axes previously derived their numeric step from rounded
  display ticks. At a one-micro-dollar positive or negative net result, adjacent
  ticks could both become zero, leading to division by zero and a trapping
  infinity-to-integer conversion during chart construction. Both axis styles
  now share an unrounded numeric scale. Tiny ticks remain distinct, currency
  precision adapts, and subnormal/overflow extremes use finite bounded scales.
- Independent review caught a second boundary: a normalized final tick for
  `0.000009` could slightly exceed the unrounded positive domain. The positive
  domain now covers both the input and its normalized final tick.
- Regression tests exercise tiny positive/negative/mixed profit through actual
  profit-bound calculation and both stacking arrangements, distinct formatted
  financial ticks, tiny gross earnings, subnormal and largest finite inputs,
  and nonfinite/zero fallbacks. Assertions require finite increasing ticks,
  zero, bounded tick counts and domains that contain the inputs and ticks.
- Opportunity search now matches the exact short name shown on the card as
  well as canonical identity and the matching catalog name. Tests cover Gemma
  and Qwen without catalog metadata, case-insensitive canonical searches,
  empty/unmatched queries, and rejection of another model's catalog name.
- Opportunity uses one bounded scrolling page for guidance, search, demand,
  cards and the explanatory footer. The model-only inner scroll/geometry was
  removed; the bounded outer viewport still chooses the original one/two-column
  threshold. Disclosure state, source freshness and actions were preserved.
- Earnings' chart accessibility description now promises aggregate totals and
  coverage in the table, accurately describing its all-model rows.
- A subsequent native scalar check found that one Area value cannot form an
  area polygon. Isolated series runs now also draw shaped points at their
  recorded bucket midpoint and signed stack endpoint, with a numbered badge
  and explicit recorded-period/amount accessibility text. Their former edge
  overlay badge is omitted. Multi-value areas keep their existing marks/cues.
  Helper regressions distinguish run breaks from multi-point endpoints, retain
  surrounding positive/negative stack contributions, preserve recorded zero,
  reject nonfinite/absent points and leave the input unchanged.
- Independent review then caught axis-scale rounding in the point's accessible
  amount. The final point uses its original chart value, not a subtraction of
  stacked endpoints, with point-specific USD precision. Tests preserve a
  one-micro-dollar contribution beside a much larger value, amounts lost by
  floating-point stack subtraction, locale, sign, fractional micro-dollars,
  zero and scientific notation below the decimal cap. Nonfinite is unavailable.
  The original-amount map is skipped when there are no isolated points.

## Native baseline: 67

The unchanged baseline was launched in a new isolated session,
`BloomyDashboardFixture-C294E502-5DC5-4412-95C3-5EC3B0597436`.
Its exact manifest and binary are retained under
`.build/native-dashboard-fixture-20261002-67` and were previously recorded in
[the keyboard/Logs review](NATIVE_CHAT_KEYBOARD_LOGS_REVIEW_20261002.md).

- Wide dark Overview showed aligned summary/resource/model cards. Opening
  Running and saved selection and invoking the outer native Scroll Down action
  reached its full panel and footer. Live versus last-observed cooling wording
  remained distinct; missing GPU/CPU measures were not invented.
- Wide dark Opportunity showed four aligned cards. Searching `Gemma 4` worked
  with the baseline's catalog present; this does not prove absent-catalog search.
- In compact light, the collapsed guidance page rendered normally. Opening
  Model guidance alone blanked the entire content area, including the sidebar
  and fixture controls, while the title bar and accessibility tree remained.
  A sidebar press failed as offscreen. Native activation and Fill did not
  repair the expanded state; collapsing guidance restored rendering. Returning
  to the compact preset and opening guidance again reproduced the blank page.
  Factors/history expansion was not required to trigger it.
- Compact Earnings Date range showed native From/Through fields and consistent
  model/measure/chart controls. From → Tab reached Through; subsequent Tab can
  traverse date segments. Control-Tab reached All models, then Tab/Space selected
  Qwen and changed its table to the model-specific throughput column.

## Native scrolling candidate: 68

Session: `BloomyDashboardFixture-C2A60233-0382-459A-986D-084B8D6D9AE1`.
This candidate contains the final Opportunity scrolling/search changes but
predates the last unsigned-axis bound correction and isolated Area points. Its
evidence below applies to the unchanged Opportunity view, not those later chart
changes.

- Compact light guidance expanded without blanking the sidebar or fixture
  controls. Opening Factors rendered the four-model evidence list. Repeated
  native outer Scroll Down actions reached each model's factors, the final
  Bonsai rows, Recent decisions, search and cards. Recent decisions opened and
  truthfully showed that history was unavailable.
- Searching `Qwen 3.8` retained expanded guidance and returned the correct card.
  Resizing to wide dark retained search/guidance and reached the footer. After
  the card was visible, Shift-Tab from How to read this focused the canonical
  Qwen Details control; Space opened it. Outer scrolling reached the full
  canonical ID, download/RAM, retained routing/pressure, pricing qualification,
  compatibility explanation and footer.
- Changing search to `Gemma 4`, Tab through Refresh to its Details control and
  Space opened Gemma's canonical details. Both keyboard-focused disclosures
  had their own model-specific accessibility identifiers and matching bodies.
- Retained demand used Last known/Last reported qualification after expiry.
  Missing readiness, throughput and observed-work factors remained missing.

Limits: this synthetic catalog is present; absent-catalog matching is unit
evidence. An offscreen lazy card was skipped in one compact key-loop attempt
until it was brought into view. The CUA tree also omitted some descriptive
attributes while the large factors list was expanded; contextual identifiers
and detail bodies were observed, but this is not complete screen-reader proof.
The native scroll action is not proof of every physical-wheel or keyboard-page
interaction. Full history, maintenance and unavailable-source layouts remain
separate matrix items.

## Final-axis / scalar baseline: 69

Session: `BloomyDashboardFixture-7880F0AB-1C17-432D-9F74-E41501C63F9C`.
This includes the final numeric-axis fix and predates the isolated Area points.

- Wide dark Today and Date range rendered aligned controls and gross chart
  axes/legend/table. Native keyboard input changed From to September 3 while
  Through stayed October 2, producing thirty synthetic daily buckets. All thirty
  dates appeared in the chart/table accessibility output.
- Control-Tab traversed From → Through → All models. Four Tab moves reached
  Base rewards; Space hid its chart series without rewriting recorded table
  totals. Tab through Measure to Chart, Right/Space selected Lines, then Area.
  Wide dark Bars, Lines and Area were inspected; shapes/strokes/numbered cues
  remained visible. Compact dark retained dates, filters and Area selection;
  the outer native scroll action reached the chart and table.
- Date alone correctly produced twenty-four hourly values, not a scalar case.
  A genuine scalar used Date range with both endpoints September 3. Through
  was changed with the accessible date setter after several unsuccessful native
  click/typing attempts, then its popover was dismissed. The resulting table
  contained one `0.1500` Work row. The Area plot showed only an edge series badge
  and no visible amount mark. Source confirmed an isolated AreaMark cannot
  draw a polygon; this triggered the point fix above.

This proves the named keyboard path and chart observations, not every date
segment or a keyboard-only scalar setup. A later attempt to enter Health from
this date-editing session did not change the route; expanded Health was not
established in that session. It is retained as incomplete proof, not a source
defect or accepted Health check.

## Health and initial point candidate: 70

Session: `BloomyDashboardFixture-A4B3BD44-7A0B-4D86-8AE7-0FDC1B60CA92`.
This predates the final point-amount formatter and trailing-badge adjustment.

- The new session entered Health before date editing. Provider & verification,
  Daemon details, Thermal details and Advanced were opened at wide dark size,
  then retained through compact dark resizing. Native outer scrolling reached
  the full verification-unavailable explanation, daemon snapshot timestamp,
  GPU-memory scope warning, canonical Qwen slot/KV/MTP rows, retained cooling
  fields and the final Acquisition diagnostics / None reported rows. No blank
  page or inaccessible bottom was observed in this prepared case.
- Thermal fields explicitly became Stale / Last observed while fixture source
  captures continued advancing. The process-identity mismatch stayed
  Verification unavailable rather than implying successful verification.
- Compact Earnings Area with equal default Date range endpoints showed visible
  Work and Base reward symbols at their signed stack endpoints, with a matching
  single table row (`0.1500`, `0.0200`). The initial bottom reward badge crowded
  the Work symbol; the final candidate places point badges to the right.

Health's source was unchanged by the later point edits. This covers the named
expanded prepared-data layout, not all unavailable/missing states, arbitrarily
long IDs/reasons, a complete disclosure key loop or spoken VoiceOver.

## Final point candidate: 71

Session: `BloomyDashboardFixture-096176DD-9BDD-4420-AA41-56563539DFC7`.
All 89 recorded source hashes match the final current source. This candidate
includes the original-amount formatter and trailing numbered badges.

- Wide light Earnings Area with equal default Date range endpoints rendered
  one daily bucket with distinct Work and Base reward symbols at the signed
  stack endpoints. The numbered badges sit to the right of their symbols and
  match the legend and recorded table values (`0.1500`, `0.0200`). Compact dark
  resizing retained the dates and Area selection; outer scrolling reached both
  symbols, badges and the matching table without the earlier crowded badge.
- The native chart AX summary exposed its recorded period and two series,
  including the point midpoint/stack values. CUA did not expose the custom
  per-point period/amount labels individually. Original-amount precision is
  therefore source/unit evidence, not verified spoken VoiceOver behavior.
- Navigating back to Opportunity worked. Opening Model guidance in compact
  dark retained the sidebar, controls, guidance content and search/Refresh row
  without the baseline's blank page. Earlier Native 68 scrolling/key evidence
  applies to the unchanged Opportunity source.
- Native 71 was closed through normal Command-Q. A subsequent process check
  found no `DashboardFixture` process. No provider or production-app restart
  was performed.

Known zero points sharing a stack endpoint, negative/nonfinite/empty rendered
fixtures, and complete chart keyboard/VoiceOver behavior remain open. Helper
tests cover their numeric/selection semantics, not all native layouts.

## Verification and provenance

All recorded review apps are inert AppKit hosts of production SwiftUI views,
with isolated preferences and synthetic data. CPU/GPU sampling and provider,
credential, endpoint and inference actions remain disabled. Mac identity and
macOS thermal state are actual host readings; fan and temperature measurements
are synthetic. The fixture builder records 89 source
hashes, exact substitutions, library/binary hashes and compiler arguments.

Native 68 manifest SHA-256:
`0bcc2a4cdea6b366b85875e85a15e3e920aeb8dfa84512289d5b1f785ccc30ed`.
Binary SHA-256:
`bb4db2cddb117d04c4cdc631e232b34ffaff5175d9204d641ed0872678e2e3c3`.
Compilation exited 0. The intermediate focused run passed 24 tests in two
suites; the intermediate full run passed 1,325 app/telemetry, 21 protocol and
28 host tests. These predate the final bound adjustment.

The final-axis focused run passed 24 tests, the full run passed 1,325
app/telemetry + 21 protocol + 28 host tests (1,374 total), and release compilation
exited 0 in 46.46 seconds. These predate the subsequently discovered scalar fix.
The scalar-inclusive focused run passed 35 tests in three suites.
After the point-amount correction, the focused run passed 38 tests in three
suites, including the original scalar/axis/search regressions.

Final verification, joined to completion:

- `chart-opportunity-focused-04.log`: 38 tests in three suites passed (0.006 s).
- `chart-opportunity-full-04.log`: 1,332 app/telemetry tests in 178 suites
  (20.905 s), 21 protocol tests in five suites (0.014 s), and 28 host tests in
  nine suites (11.704 s) passed: **1,381 total**.
- `chart-opportunity-release-02.log`: release build exited 0 (39.88 s).
- `chart-opportunity-native71-build.log`: finite native fixture compilation
  exited 0. All 89 source hashes and the fixture binary matched its manifest.

The logs are retained in `/tmp/bloomy-efficiency-20261001/`. Native artifacts
and manifests are retained under `.build/native-dashboard-fixture-20261002-NN`.
The following hashes identify the reviewed intermediate/final candidates:

| Native | Manifest SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| 69 | `314e9f29700a94cdbf99074dbced60d198f10e97c132e1401665c7d157aace83` | `ca6ca56e3f67a72c7977649348af96598599847f6b10e25987d8860a0983ca29` |
| 70 | `1ca0670bd381b2d410580e3279ba22edaf4e1d0e08b928acab461c9db4960526` | `ef0c82f6486dbde6c8719acafe68bcc4662058e38d6f1454447bc455f63647fd` |
| 71 | `d89fd127fed9157a88015f2d1045bd1ee5595d9a4af13a3cca1e7bebb3c6b5f6` | `45697bc295ae2c4dd1615d170dff7b5946bce24d71ad5bd9cf09ee26ed707cd3` |

Production remained PID 31677, launched October 1 at 22:40:57, with unchanged
binary SHA-256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Both provider and watchdog were still unloaded (each service lookup exited 113).
The independent reviewer found no remaining actionable source finding after
the axis-bound and original-point-amount corrections; final visual verification
remained root's responsibility.

Actual VoiceOver, every route/appearance/source state, whole-app profiling,
production launch with unsaved work, real provider/hardware actions and updater
installation/signing/notarization/distribution remain open. The drive-permission
reset already succeeded; the separate managed cache failure remains unresolved
in the [sanitized diagnostic](PROVIDER_CACHE_STARTUP_DIAGNOSTIC_20261002.md).
