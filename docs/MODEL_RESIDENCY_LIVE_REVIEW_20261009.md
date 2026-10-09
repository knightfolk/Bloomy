# Live model residency follow-up

October 9, 2026, America/Phoenix. Follow-up to the popup control checkpoint;
this does not complete the broader polish goal or qualify distribution.

## Problem and correction

The actual isolated app showed “Status unavailable” on every downloaded model
while its live provider rate continued updating. A read-only Models Refresh
restored Loaded/Unloaded labels, which disappeared again when the independent
control evidence exceeded its ten-second lifetime. The manager only used that
one-time control snapshot and ignored the monitor's current loaded-model reads.

Models now uses the same validated telemetry residency as popup pills when
independent controls expire. Both daemon and loaded-model captures must be
finite, current, and nonfuture; the daemon payload must remain current, and the
loaded-state file must belong to the current provider lifetime. An unchanged
loaded-state file may be old while a fresh read still establishes its value.
Missing or expired evidence stays unknown. A retained idle current-model name
alone is not loaded evidence; exact catalog/local identities support aliases.
Known stopped and fresh independent control evidence retain precedence.

The shared resident-ID set is prepared once per accepted presentation. No
acquisition loop, extra provider command, inventory refresh, or weaker freshness
limit is added. Loaded-read expiry participates in the existing finite,
visibility-gated deadline task. Telemetry changes do not rebuild grouping,
shared telemetry indexes, or opportunity grades.

## Verification

- The regression run before the implementation failed with four expected
  assertions: live loaded status and the three active/loaded/unloaded alias cases.
  Log: `.build/model-residency-regression-before-20261009.log`.
- Full serial Release run: 1,832 app tests in 230 suites pass, with seven existing
  opt-in skips; 21 companion contracts and 28 companion host tests pass.
  Log: `.build/model-residency-full-release-20261009.log`.
- Twelve residency tests cover precedence, live fallback, aliases, invalid and
  future captures, a prior-process loaded file, honest missing state, cache
  invalidation and loaded-read expiry. Existing popup source tests also pass.
- Read-only specialist source review found no actionable issues. This was source
  inspection, separate from Main's test and native verification.
- In the optimized inert native fixture, “Network expiry in 20 seconds” freezes
  automatic control/telemetry publications. After the control and telemetry
  evidence expire, all downloaded cards show unavailable. Supplying only fresh
  synthetic live measurements restores Serving, Loaded and Unloaded cards.
  Supplying idle observations changes Serving to Ready; stale observations
  return to unavailable. No model-controls Refresh is used for these transitions.
  Screenshots are under `.build/model-residency-fixture-20261009/evidence/`.

## Artifacts and boundary

Actual review app:
`.build/model-residency-review-20261009/Bloomy Residency Review.app`

Identity `dev.darkbloom.monitor.residency-review-20261009`, version 1.9.19,
build 2026100902. Signed executable SHA-256:
`a733d5c8cffedad7d53091941b45dda877c38cd847a798a10ea5a7d7492d269a`.
Its review manifest freezes 253 production source hashes and the residency test.
Local ad-hoc deep/strict verification passes; no updater feed is configured.
This is not a notarized distribution app. Original packaging manifests describe
unsigned bytes; the review manifest identifies signed executable bytes.

The optimized fixture manifest matches all 142 recorded production/native
inputs. Existing fixture controls were used without test-host overlays or
changes to the protected dirty motion proof. Evidence is synthetic and does not
establish actual inference or per-model earnings.

The provider stopped and later resumed during this work outside Main's actions;
Main sent no provider lifecycle command and preserved its current selection.
The actual review correctly showed Not loaded while stopped, then Ready in memory
for Gemma after resuming. Gemma stayed Ready through a further observation more
than a minute later without a controls Refresh; disabled downloaded models
remained Not loaded. Both review apps were quit and their exits checked.
Broad motion/occlusion, resource, accessibility,
financial and Companion gates remain open in the main plan. The next motion
experiment should compare the same actual Settings fixture with and without
active capture calls, retaining native delivery prerequisites rather than
changing product visibility heuristics.
