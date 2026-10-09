# Compact Overview model rows

Overview now uses the popup's shared horizontal model face: 52-point rows,
short display names with canonical-ID help, residency status, accepted history
metrics and a compact network-demand ruler. The ruler uses the whole network
snapshot, so hiding or selecting models cannot stretch the scale. Failed reads
retain explicitly stale demand; missing demand stays unavailable.

One immutable render input qualifies calendar token-rate history once and
indexes it by canonical ID. It preserves duplicate rejection, date/age guards
and the original first serving-average match. There is no new poller or global
cache, and historical account-derived earnings remain distinguished from this
Mac's measured income. This is a source-level reduction in repeated derivation;
whole-app CPU or energy savings have not been measured.

## Evidence

Task-owned evidence is under `.build/overview-model-row-review-20261009/`.
The pre-change source is saved as `before.swift`; its native baseline comes
from the frozen `483553e` review fixture. Review apps use synthetic dependencies
and private preferences. Neither the installed app nor provider is changed.

An independent source review found no actionable regression in the Overview
integration. Initial native mixed-history inspection then caught a shared-card
width problem: simultaneous speed and a micro-dollar hourly amount could
truncate the amount and units. History rows now reserve their metric column's
natural width; aliases may shorten while canonical help remains available.
Live-throughput rows keep their flexible sizing.

The initial optimized fixture confirmed equal native rows in light and dark
appearances, mixed measured/learning history, explicit age-expired retained
demand, and unavailable model state when runtime evidence was stale. The popup's
More menu exposed model management, Hosting, Provider, GPU protection, energy,
cooling, inactivity nudge, profit switching, appearance, menu bar, updates and
support. GPU protection opened in a native popup panel. No live mutation was
performed. The first full run passed 1,846 app tests plus 21 protocol and 28 host
tests.

The final optimized fixture matches all 142 recorded source hashes and passes
deep, strict review-signature verification. Its executable SHA-256 is
`3859c1a186748ba2988bae11ac05b3a8a5afab236b3ec276abe19f4f8eb2959a`.
Final light/dark screenshots show full `avg 52.7 tok/s` and `est. $0.0050/h`,
equal row heights, and intact shared Models and popup controls. The updated
popup's command bar, model action buttons and full More menu remain visible.
Review apps were quit and their process absence checked.

Forty-five focused Release tests pass in four suites. They cover qualification,
first-match attribution, demand freshness, full-network scale, canonical
identity and actual 52-point rendering at 300/528/800-point widths. A glyph-mask
comparison checks actual trailing metric text at 300/528 against 800 points,
allowing at most four antialias-edge pixels; a deliberately shortened amount
must change more than fifty pixels. The initial raw-bitmap comparison failed
because native bitmap storage/background varies with width; normalized saved
images confirmed complete text before the check was corrected.

The final standard serial Release run passes: 1,847 reported app tests in 231
suites, 21 protocol tests and 28 host tests, with process exit zero. A preceding
concurrent run failed the unchanged active long-scan cancellation test, whose
five-millisecond cancellation assumption is scheduling-sensitive. That exact
test passes in the serial run; no source or assertion was changed or excluded.
Both logs remain preserved, rather than treating the failed run as clean.
The existing 49 fixture-staging checks and diagnostic Python compilation pass.
Source-level independent reviews found no actionable regression; real VoiceOver
and larger-text acceptance are not claimed. A standalone 300-point row shortens
its alias/status to preserve numeric precision; full identity remains in help.

## Logs redraw experiment

Before changing Logs, the exact Logs view and its three local dependencies were
staged in an optimized inert native host. Only the staged presentation received
a derivation counter. Thirty unrelated parent publications produced one extra
derivation; a changed feed produced one derivation. This did not support a new
Logs cache or render wrapper, so no product Logs code was changed.

The reusable diagnostic is `Tests/PerformanceBenchmarks/logs-redraw-benchmark.py`.
The hash-bound report and frozen library are preserved under
`.build/dashboard-redraw-review-20261009/logs-baseline/`. These are derivation
counts, not whole-app CPU measurements. No live logs, provider calls, export,
hardware sampling or production preferences are involved.

## Remaining gates

This checkpoint does not resolve the prior native genuine-occlusion and dialog
pixel qualification gaps. Broader accessibility, large-text, comparable live
resource measurements and distribution verification remain separate work.
The shared Models view also has a pre-existing two-decimal hourly-money formatter
(`ModelCardSummary.money`), which rounded the synthetic $0.0050 net rate to
$0.00 in accessibility help and $0.0250 to $0.02 visibly. Unifying that formatter
with the precision-preserving Overview formatter is a concrete next follow-up;
this layout fix does not change the Models view's value formatting.
No push, release or installed replacement is claimed.
