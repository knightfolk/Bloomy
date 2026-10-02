# Local performance history

Activity → Metrics shows measured serving performance separately from earnings.
Bloomy records structured observations every 30 seconds and at model, residency,
provider-process, inference, source-quality and native Autopilot phase changes.
Recording continues with the dashboard closed while Bloomy is running.

The private SQLite journal retains up to 30 days and 100,000 observations. Writes
and reads run outside the UI actor. Failed writes are retried with the same IDs;
a bounded in-memory backlog retains 120 observations. Recording and read errors
are visible. If the backlog overflows, a warning remains for that app session.
Older data may expire sooner when the row limit is reached.

The journal contains only timestamps, bounded model names, local process identity,
canonical Autopilot phase, inference state, provider request/token counters,
measured token rate, GPU measurements and measured power when available. It
excludes prompts, completions, API keys, account/coordinator identifiers,
configuration paths, raw logs and provider error prose. Files and SQLite sidecars
use owner-only permissions. History remains on this Mac.

Coverage and counter increases require consecutive fresh observations from the
same provider process with advancing source timestamps and gaps no longer than
90 seconds. Counter resets, stale/missing observations and application downtime
are unknown. Model summaries do not bridge another model's observations.
Speed averages require measured active intervals for the same model. These
observations cannot reconstruct every request or prove why a reward was missing.
Requests and tokens are provider counter increases, which can include local and
private traffic; they are not equivalent to paid work or earnings. These totals
are available only with All models selected, because the daemon does not emit
per-model request and token counters.

GPU utilization and power are whole-Mac readings. Provider GPU memory is reported
by the daemon. Missing measurements remain unknown. Estimated power is not written
to this performance journal. Native Autopilot phase is read-only; missing or
unrecognized phases remain unknown. Metrics does not enroll, pause, switch or
otherwise configure the provider.

Existing Health & Logs and Action History retain their roles for diagnostics,
nudge attempts, model operations, recorded jobs and rewards.

## Loaded-model visits

Metrics analyzes uninterrupted visits using the single resident model, rather than treating the daemon’s most-recently-used model as the loaded slot. Each completed visit reports its observed duration and work evidence. All-visits and Without-work filters show the latest 500 matching visits; counts and duration totals use the full selected history. A return to the same model is a separate visit.

No observed work requires a fully bounded visit, fresh inactive readings, unchanged counters and single-model residency. Provider restarts, stale or missing data, counter resets, clipped periods and ambiguous cross-switch counter increases stay uncertain. Positive counters between the same sole resident can detect brief completed work between idle polls. These observed intervals are approximate, and cannot prove the network sent no requests.

Positive shared counters can be attributed only to the same sole resident observed at both ends. Switches away and back entirely between readings cannot be ruled out. Model-filtered coverage follows sole residency; work or speed labeled for a previous model is not reassigned.
