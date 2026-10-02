# History, cache refresh, and image reuse — October 2, 2026

This is a bounded checkpoint in the continuing native polish and efficiency
run. It does not complete the full screen, accessibility, production, or
distribution matrix. The installed app and its unsaved work were preserved.

## Changes and review

- Action History prepares one filtered, sorted snapshot per render for its
  empty state, table, and selected details. It matches canonical model IDs as
  well as their short display names. Cheap raw fields are matched before
  formatting labels or currency. No persistent presentation cache can conceal
  a corrected record with the same ID.
- Network cache health owns its current read as a cancellable task. A restored
  observer joins a cancelled read that is still unwinding before starting its
  immediate read. Busy manual calls continue to coalesce; cancellation cannot
  publish late data, count as a failure, or enter the next backoff sleep.
  Successful reads retain the sixty-second cadence and failures retain the
  existing bounded backoff.
- Model marks are normalized lazily and retained by their six finite families
  on the main actor. Missing results and the original-image fallback are
  retained too. The converter, geometry, pixels, and template flag are
  unchanged. Dynamic menu-bar drawing/tinting and animation remain unchanged.
- The inert native cache client records fake read count/time in its unique
  temporary directory. This adds no polling clock or real request.

An independent read-only review found no actionable search, selection,
ownership, cancellation, or publication regression. A late prior caller's
cancellation targets its captured task rather than a successor. That last
ordering is established by the ownership logic, rather than a separate
deferred-caller test.

Regression coverage compares the old query independently, including aliases,
case/whitespace, action labels, currency precision, correlation IDs, all type
filters, deterministic date/UUID order, same-ID corrections, and excluded
selection. Gated asynchronous clients cover noncooperative reads, serialized
restoration, busy manual calls, cancelled success/error, retained evidence,
and unchanged failure backoff. Image tests compare all six packaged families'
pixels and geometry, lazy/identity reuse, distinct marks, and both fallbacks.

## Component measurements

The task-owned History runner uses 5,000 deterministic records, timestamp ties,
two warmups, and nine alternating baseline/candidate rounds. Exact whole-event
arrays and selected payloads agree in each legacy scenario. The baseline models
the old render's two derivations without selection and three with selection.

| History preparation | Baseline median ms | Final median ms |
| --- | ---: | ---: |
| Empty search, selected | 7.903 | 2.556 |
| Model alias, selected | 130.889 | 42.157 |
| Currency, Jobs, selected | 66.661 | 22.841 |
| Raw trigger, Actions, selected | 64.209 | 15.355 |
| Model alias, unselected | 88.074 | 42.837 |

Canonical search intentionally changes zero old matches to 1,334 exact
expected matches. The isolated eager/lazy comparison also preserves exact
results: raw-trigger preparation measures 22.458 / 15.355 ms; canonical search
45.083 / 38.373 ms. These measurements use an optimized helper/driver and an
existing debug telemetry archive, excluding SwiftUI/AppKit layout, database,
provider, energy, and whole-app CPU. Parent native activity may add noise.

History provenance and the retained finite runner are under
`/tmp/bloomy-efficiency-20261001/action-history-presentation-benchmark-02/`
(`README.md`, `manifest.json`, `results.json`, and source copies). Baseline Git
revision is `f8aa3bdf69edf6f991639aac416f7c38a818fe12`; candidate helper SHA-256 is
`d7ef8610a93c735dcfa2e8c8c76cbd878b0ecdbd25ee630f8e51559ef01207e8`.
The fixture SHA-256 is
`2fbb21bdad02f09468cee92985f484027f0c26922f994f95dee3830d400e9982`.

The opt-in SwiftPM image benchmark performs 600 warm factory calls. The old
converter requests 600 bitmaps and creates 600 wrappers; the production cache
requests/creates zero more and retains six image identities. Warm factory time
is 3.337 / 0.464 ms in this debug run. A fresh cache with already-warmed source
assets creates six wrappers in 0.053 ms; this is not a cold AppKit/SVG-loading
comparison. Counters measure conversion requests and wrappers, not internal
SVG decodes. The original warm cost is small; this does not prove whole-app CPU
or battery savings. Reproduce with `DARKBLOOM_LOGO_BENCHMARK=1 swift test --filter
ModelLogoImageCacheTests`.

## Native inspection

Native 62 is an isolated synthetic review app built from the final product
sources. Its manifest records 86 source hashes, all compared to the working
tree before inspection. The builder's existing three default-client
substitutions remain recorded; it does not run the production entry point or
provider. All checks used computer use, with task-owned diagnostic files read
separately for evidence.

- Compact light History searches `qwen3.8-27b` and finds exactly sixteen Qwen
  Swap entries among forty-eight seeded actions. Searching `Qwen 3.8 · 27B`
  finds the same sixteen. A selected failed entry's details are reachable by
  scrolling the outer page and show its time, trigger, result, model, and
  reason. Jobs correctly shows No matching entries for this action-only
  fixture. Changing the search clears selection as before.
- Native 61 supplies the pre-change light/dark popup baseline. Native 62's
  Gemma orange mark, GPT grey mark, and Qwen green serving mark retain their
  shapes, contrast, tint, and equal card geometry. Expanding Available also
  shows the grey Qwen and Bonsai marks with the same card sizing. The pixel
  tests independently cover all six families; this visual comparison is not
  a new normal-speed animation or complete appearance-matrix proof.
- Network infrastructure initially reports zero fake reads while collapsed.
  Opening reports one read at epoch `1790957176.492149`. After closing, it
  remains at one through epoch `1790957267.034243`, more than one refresh
  interval. No new production visibility gate was needed. Reopening performs
  read two immediately at `1790957273.224727`; the visible sixty-second loop
  subsequently reads again.
- The first minimize/menu attempts were inconclusive: they did not establish
  a hidden window. Opening the dashboard through the popup then exposed its
  native window controls. Clicking Minimize produces a trace with
  `window.didMiniaturize`, `isMiniaturized=true`, and `isVisible=false`, but the
  following inspection also records deminiaturize/presented and a new read.
  This does not establish sustained hidden-window suspension. Route-away
  attempts during the same inactive-window inspection also failed to establish
  a route change. Neither is counted as a pass or diagnosed as a product bug.
  The unit tests establish cancellation/restoration logic; sustained native
  hidden/route-away proof remains separate.
- Before the source changes, Native 61's compact Menu Bar and Appearance pages
  fit their host. The native Light/Dark controls changed dashboard/window
  appearance immediately; System selected correctly and followed this Mac's
  dark appearance. Those production views are unchanged in Native 62. These
  checks do not establish the full keyboard or VoiceOver matrix.

Native manifest:
`.build/native-dashboard-fixture-20261002-62/fixture-manifest.json`

Manifest SHA-256:
`c7bc1960d8f4a24afc24c82c386531c8a11ffa1f5c1f0994f6174a06ed80df45`

Binary SHA-256:
`fa092fd04544d578ab7c4d13d4c2e0f35510b97714e6701fb5cc8c1d95c09bd2`

Runtime evidence:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-EF1AA150-4516-442B-8406-677474D055D2/`
(`network-cache-read-proof.json` and bounded `focus-diagnostics.jsonl`).

## Verification and remaining gates

All finite builds/tests were joined:

- `efficiency-focused-01.log`: exit 0, fifteen definitions in three suites,
  including the opt-in image benchmark and parameterized History cases.
- `efficiency-full-01.log`: exit 0; 1,308 app/telemetry tests in 175 suites
  (23.316 s), 21 core tests (0.016 s), and 28 host tests (11.657 s): 1,357
  reported tests total. The opt-in benchmark is skipped in this normal run.
- `efficiency-release-01.log`: exit 0, release compile 44.70 s.
- `efficiency-native-62.log`: exit 0, immutable native review build.

Logs are under `/tmp/bloomy-efficiency-20261001/`. These are exact-source local
checks, not signing, notarization, updater installation, or production proof.
The installed production app is preserved; the review app is retired after
inspection. No real model, credential, fan, inference, or provider operations
were used for this checkpoint.

The scoped drive-permission reset remains applied. The managed provider's
Sol-cache startup failure is still unresolved and its service/watchdog remain
stopped. A further bounded read-only review of the installed official bundle,
help, configuration schema, and local source fragments established no supported
new correction. The sanitized, unsent vendor diagnostic remains in
`docs/PROVIDER_CACHE_STARTUP_DIAGNOSTIC_20261002.md`. Obtain the underlying error
or a supported managed-context read-only probe before changing cache/privacy
settings or retrying startup. Production, sustained hidden-window, broader
native accessibility/motion, and distribution verification remain open.
