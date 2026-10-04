# Optimized Overview resource baseline — October 4, 2026

Current Overview has a bounded optimized-process baseline, rather than another
optimization based on source inspection alone. The native review builder now
supports `--configuration release`: production views and the fixture compile
with `-O`, use testable Release telemetry, and record the configuration and
optimization in the manifest. Debug remains the default. A module preflight
rejects telemetry products that cannot supply the fixture's test constructors.

The process sampler optionally checks an owned fixture visibility event file.
It requires the requested native state initially and during every one-second
sample, and rejects a changed event record even if the final state recovers.
Each accepted result retains its state evidence alongside process identity and
CPU/footprint counters. The native compositor flag alone is not used to infer
minimization: this Mac retained `compositorVisible=true` while the window was
miniaturized and display work was disabled.

## Observed baseline

Exact fixture: `.build/overview-optimized-profile-native-20261003/` (the build
began October 3). All 113 staged production/fixture source hashes match the
checkout; the pinned telemetry archive matches the final Release products.
Executable SHA-256:
`a9a31584c96b8bede10f56a15298a8e45bf5eabd832051f46561f865f8d35df9`.

Same process, PID 94366; wide light Overview; Fresh synthetic sources; three
model cards; CPU/GPU acquisition off; no real API calls. The fixture continues
its five-second synthetic source/history updates. Source timestamps naturally
age; Reload refreshes them before the displayed repeat windows. No compilation
or test suite ran during these four measurements. Other user processes remain.

| Qualified 30-second window | CPU, percent of one core | Median RSS, MiB | Median footprint, MiB |
| --- | ---: | ---: | ---: |
| Minimized B | 0.394 | 157.27 | 69.34 |
| Displayed B | 2.065 | 157.33 | 69.41 |
| Minimized C | 0.321 | 157.45 | 69.56 |
| Displayed C | 1.429 | 157.58 | 68.77 |

Every window has 31 observations with an unchanged visibility event record.
Minimized records have `miniaturized=true`, `windowVisible=false` and
`displayEnabled=false`; displayed records have the opposite values and neither
state is application-hidden. Native Window → Minimize All and Show Dashboard
control only the single task-owned review window. Rendering and summary
accessibility recover normally after restoration.

These short observations support the existing hidden-display behavior in this
fixture. They do not establish shipping-app CPU, collector costs, battery/energy
use, a leak-free allocator, or a universal idle baseline. Testable telemetry and
inert dependencies differ from the installed application; this is not a
comparison against its older build. No product rewrite is justified by this
Overview baseline alone. Optimized Metrics/larger histories and comparable
production activity are the next resource checks.

## Rejected observations and verification

- The first nominal minimized result actually ran after restoration, with
  display work enabled. `.build/overview-profile-minimized-A-20261004.json`
  remains as rejected evidence, excluded from the table. A subsequent key-only
  attempt failed the new state guard before a result could be written.
  Preliminary unguarded displayed windows are also excluded from this table.
- A deliberate minimized label against the displayed native state exits with
  an error and creates no metrics result. The expected rejection passes in
  `.build/profile-guard-validation-20261004.json`; its stderr is retained.
- Mach CPU-time calibration against `getrusage` passes: 0.99958725 versus
  0.999593 seconds, with timebase 125/3. Calibration is retained in
  `.build/overview-profile-calibration-20261003.json`.
- Qualified results: `.build/overview-profile-{minimized,visible}-verified-{B,C}-20261004.json`.
  The derived summary and copied native visibility events are retained in
  `.build/overview-profile-summary-20261004.json` and
  `.build/overview-profile-visibility-events-20261004.json`.
- Both Python tools pass syntax checks. The optimized native build and focused
  Release rendering cases pass. Full Release suite reports 1,561 telemetry/UI,
  21 protocol and 28 host tests passing: 1,610 total with seven existing opt-in
  skips. Log: `.build/optimized-review-full-release-tests-20261004.log`.

The two older review apps and final debug/optimized review apps quit normally;
no DashboardFixture process remains. Evidence bundles stay preserved. Installed
Bloomy remains 1.9.18/build 143. The real provider remains PID 47646 with fresh
state, exactly Qwen 3.8 and Gemma 4 advertised, and Autopilot shadow.
Configuration SHA-256 remains
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

This is local tooling and evidence, without push, release, installed replacement,
provider mutation or inference. Unrelated menu-motion diagnostics and user
files remain. The complete UI/accessibility/motion/source-state matrix and
whole-app production efficiency remain open.
