# Current Metrics native review — October 9

## Native layout and behavior

An optimized, isolated native dashboard built from `3d8d5ab` was seeded with
100,000 synthetic observations spaced 25 seconds apart. Synthetic publication
was paused through Data checks before reviewing Activity → Metrics. No provider
commands, swaps, downloads, credentials or inference were used.

All five current scopes (1/2/8/12/24 hours) complete and show the corresponding
coverage. The Without work choice survives period changes and model filtering.
The 24-hour scope shows six completed visits without observed work, totaling
2h 30m; the shorter scopes reflect their own history. Filtering to Gemma shows
an explicit absence of completed no-work visits rather than fabricated work.
The timeline and visit details keep observation uncertainty visible.

Rendered inspection covers compact light, compact dark and wide dark, including
the collapsed and expanded visit details. Historical charts remain present
after current readings expire; they do not claim current GPU or power readings.
Saved screenshots and accessibility trees are in
`.build/metrics-current-native-review-20261009/`. This does not establish actual
VoiceOver, every state/appearance combination or the full native matrix.

The dense, multi-model token-rate plot remains visually busy over 24 hours.
Future marker-density work should preserve isolated observations, run/gap
identity and the non-color series cues; this review does not silently remove
those cues or claim that plot has reached its final polish.

## Qualification correction

The fixed-row profiler rejected a real 12-hour refresh from 1,696 to 1,695 rows.
The dataset was paused: an older observation had simply aged outside the window.
The original diagnostic before/after/result files are retained.

`rolling-refresh` is now a separate explicit mode. Each newly completed read
must have contiguous evidence, finite forward query bounds, unchanged duration,
positive nonincreasing membership and full reuse of its remaining rows. The
snapshot must match the latest completion. Failed, empty, cancelled, held,
incomplete, skipped or cache-released work still rejects the profile. Existing
strict refresh/quiet modes retain their fixed-row requirement.

The profiler hashes every row's metadata and payload in read-only SQLite
transactions outside the CPU interval. Rolling mode requires the explicit
private dataset and matching endpoint hashes. CPU counters are bracketed by
deep-copied read proofs; a boundary change rejects the observation. Only the
earlier proof receives completion credit. Reports retain independently copied
baseline and completed-read records even after the fixture trims its buffer.

Independent review found the initial CPU/proof ordering race and discarded
read evidence; both were repaired and re-reviewed with no remaining concrete
finding. Before/after hashes are endpoint evidence, not continuous writer
surveillance. Native pause, private ownership and unchanged source content are
part of this controlled measurement contract.

## Corrected finite measurements

The final optimized fixture binary is
`63a32976dbc3ac09fbab0429313445545877c6ad4654cdaaa54b8bb6a7fb99f1`.
All 142 production view inputs match the checkout; deep strict review-signature
verification passes. The fixture support and measurement sources have separate
hashes in `final-profile-provenance.json`. Both windows use PID 38920, compact
24-hour Metrics, all models, All visits and collapsed visit details.

| Native state | Window | CPU, % of one core | Median footprint | Complete Metrics reads |
| --- | --- | ---: | ---: | ---: |
| Minimized | 30.009 s | 0.0040% | 230.03 MiB | 0 |
| Visible | 45.004 s | 1.9037% | 248.86 MiB | 2 |

Native minimization disables display work and releases the raw snapshot to
zero rows. Restoration retains the selected scope and performs a fresh read.
Visibility and process identity remain stable inside each accepted window;
no UI actions or owned builds/tests occur during either measurement.

The visible window queries 3,377 → 3,376 → 3,375 rows from the 100,000-row
journal. Its two completed reads take 7.073 and 5.982 ms and reuse every returned
row. These are read-component times, not whole-refresh latency. The full dataset
content hash remains
`0c0148f63d6f19f5f1daf5e0ca430ebc449e1be33fe9d4e83775720d32c7f571`;
its oldest observation is about 28.96 days old, within the 30-day retention.
The archived self-contained `profiled-100k.sqlite` on Sol matches that content.

The original seed and both review builds are under
`/Volumes/Sol/BloomyReview/metrics-current-native-review-20261009/`.
Mach-time conversion (125/3) passes the one-second getrusage calibration. The
earlier `metrics-minimized-30s.json` predates the final endpoint fix and is
superseded by `metrics-minimized-final-30s.json`. No earlier observation is
silently overwritten or used as a saving baseline.

These are short synthetic dashboard measurements. They do not measure battery
energy, production inference, sustained allocation growth or all Bloomy
background work. The real provider/configuration changed independently during
review; the task performed no provider mutation. Installed Bloomy PID 7234
remained running. Both owned review apps and every finite job are terminal.

## Checks and remaining scope

Thirty-seven focused Python regressions and 49 staging checks pass. The new
valid rolling cases fail against the frozen original checker; endpoint-race
tests fail before its helper exists. Four dataset tests cover a changed middle
payload with unchanged count/bounds, repeated read-only snapshots, missing-path
noncreation, and invalid/empty data. The optimized native build verifies its
query metadata against actual reads. The earlier 45 focused Swift Metrics
checks still cover the unchanged production views; no app Swift source changed
in this qualification checkpoint.

Broader native accessibility/motion, production profiling, sustained
Instruments evidence and distribution gates remain open. The overall polish
goal remains active.
