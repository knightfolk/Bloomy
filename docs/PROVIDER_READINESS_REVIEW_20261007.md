# Shared provider readiness review — October 7, 2026

## Scope

Overview and Health use one pure provider-readiness presentation. Overview has a
compact summary and navigation action; Health adds five evidence rows. Connection,
authorization, warm advertised residency and active inference remain distinct.
Quiet demand does not imply a stall or missing earnings. Existing controls keep
command authority; this change adds no recovery, polling or provider operations.

The previous Overview online badge is replaced by the evidence-backed summary.
The macOS thermal status remains in Health's Thermal details heading. Detailed
verification, diagnostics, source freshness and daemon disclosures remain.

## State and efficiency boundaries

- Available source captures, snapshot capture and daemon write time must be valid,
  nonfuture and at most ten seconds old. Expected coordinator configuration must
  be available and at most sixty seconds old.
- A supplied current process identity must match the daemon. Explicit missing
  identity cannot fall back to a kernel read in the pure evaluator.
- Coordinator trust must be fresh, match the configured coordinator and follow
  provider startup. Online status alone does not establish authorization.
- Recognized legacy authorization remains supported. Unknown lifecycle, selection
  and availability phases stay unconfirmed.
- A completed drain while waiting for a scheduled window is intentional waiting.
  Explicit stop, interrupted drain and active drain keep their conservative states.
- Validation does not claim admissions are paused. Pending preload allows other
  warm models to continue serving. Active work has no timeout inferred from money.
- Warmth requires overlap between advertised and warm models. Cold advertised
  models are on demand; missing advertisement remains unknown.
- Each changed daemon observation causes at most one shared process identity read.
  Financial publications and clock redraws reuse it; freshness still expires.
- Existing visibility-aware schedules only trigger redraws. Evaluation captures
  actual wall time once per render. A timeline entry can predate rendering, per
  [Apple's context date contract](https://developer.apple.com/documentation/swiftui/timelineview/context/date).
  Future timestamps remain rejected; no clock-skew allowance was introduced.
- Upstream prose and identifiers are excluded from the authored summary. The
  presentation does not establish local earnings or guarantee new requests.

## Review and preparation

A bounded source review found the scheduled-drain precedence error; it is fixed
and covered. The first optimized compile hit Swift's SIL ownership verification
in optional daemon handling. Unwrapping the daemon once fixed that compiler
failure without flags or disabling optimization. A missing dashboard import was
also corrected before qualification.

The preliminary optimized native fixture has 126 matching source hashes and
manifest `89b9f872d471add00578ec64a39aa3e89db6151b6ffd6b3fbe7b3e18397bb052`.
Its Details button navigated to Health, and ready/active evidence rendered.
Native inspection found that the five rows merged into one long accessibility
item. Each row now has an explicit label/identifier and a containing group.
The preliminary fixture was quit normally; it is not final qualification.

No false-stale flash was reproduced in eight preliminary active-state samples.
The actual-render-time change addresses the documented timeline-date risk rather
than claiming a reproduced fix for the app's broader motion issues.

## Final qualification

The final serial `swift test -c release --no-parallel` run passed: 1,768 reported
tests (1,719 telemetry, 21 companion protocol, 28 companion host), including seven
existing opt-in skips. The 14 pure readiness tests and four shared-observation
tests cover timestamp/authorization boundaries, explicit missing identity,
scheduled drain, active work, and lookup reuse. The 32 native staging tests pass.
`swift build -c release` completes successfully on the final source. Optimizations
and timing bounds were not weakened. Logs are retained under `.build/` with the
`provider-readiness-qualified-*20261007.log` prefix.

The final optimized isolated fixture is
`.build/provider-readiness-qualified-native-review-20261007/`.
All 126 fixture/view source hashes and 94 telemetry source hashes match the
current source, and the frozen linked library and executable match the manifest:

- Manifest: `60863cc13a37d2b3d785c1c0cb664c3941087d7e5cc637614fb2c32cd61feda1`
- Executable: `32e6d13955b807b49303a9a5aeedba270fe159740d8b3a696ea5d318f27effaf`
- Telemetry library: `34a574a169dd64139079f8b9a41155d5d864774ea17a577bafc89887fcd1264b`

Computer-use inspection verified nine final Health states: ready and idle,
active inference, scheduled waiting, finishing accepted work, explicit stop,
expired authorization, models on demand, unknown lifecycle and expired daemon
observation. Each has five separate accessibility evidence rows. Scheduled
waiting now says **Scheduled idle**, whereas explicit stop says **Stopped**.
Details reveals a collapsed Diagnostics section and selects Health; Hosting
selects the existing Hosting screen with its refresh control; Models selects
the existing model screen. None of these navigation actions executes a command.

Overview and Health were inspected at wide and 800 × 560 sizes in light and dark
appearance. The Overview strip fits above the metrics without overlap; Health's
wrapped evidence remains reachable by its existing scroll view. Thermal status
and diagnostic disclosures remain available. These are synthetic layout and
accessibility checks, not live provider behavior or an exhaustive contrast,
screen-reader, larger-text or performance qualification.

The ordinary native proof reached terminal completion: Models and Charts pass;
motion remains **12/15**, failing `opaque_cover_occlusion_and_restore`,
`same_window_close_and_reopen` and `rapid_same_window_close_and_reopen`.
Final results are copied into the artifact's `native-proof/` directory. This
checkpoint does not resolve those existing motion gates or qualify distribution.
The bounded final source review found no new readiness regression.

Both review fixtures were quit normally and owned exits checked. The provider
remains stopped. Provider configuration and the pre-existing dirty native motion
proof file retain their original hashes. No installed update, provider operation,
inference, model download, telemetry upload or release occurred. The broader
polish objective remains active, including motion, historical local-machine
attribution, joined Activity replay, demand history, onboarding and companion
delivery.
