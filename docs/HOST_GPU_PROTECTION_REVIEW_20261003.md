# Host GPU protection and serving slowdown signal

Kevin selected protection only when GPU use is high while the provider is idle.
The feature uses the existing shared three-second whole-Mac GPU sampler; it does
not add a timer, privileged helper, subprocess sampler, per-process estimate or
new credential. Device utilization includes every app, compositor and provider
background work. Provider memory allocations and the inference Boolean cannot
be subtracted to obtain a non-LLM percentage. [Apple's GPU timing API](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)
describes an app's own command buffers, not attribution of another process's
device utilization; the current provider does not expose such timings.

## Behavior

Settings → Provider offers **Off**, **Warn**, or **Automatically pause**. Default
is Off. All thresholds and dwell times are validated and configurable:

| Setting | Initial value |
| --- | ---: |
| Idle whole-Mac GPU ceiling | 80% |
| Sustained above ceiling | 15 seconds |
| Resume below | 60% |
| Sustained recovery | 60 seconds |
| Minimum pause | 120 seconds |
| Speed warning below same-model recorded baseline | 60% |
| Sustained slowdown | 30 seconds |

The idle breach requires distinct fresh GPU observations and fresh running,
idle provider identity. Preloading, lifecycle/model-switch transitions,
scheduled inactivity, known load failures and unrecognized Autopilot phases
cannot qualify. Gaps, missing/future/stale data, clock rollback, active work and
identity changes break the streak. No missing metric is treated as zero.

Warn produces status in Provider settings, the popup and Overview. Automatic
pause uses the official serialized graceful stop, with two immediate idle-risk
reads and final identity/pressure checks. The provider drains requests accepted
during a race; it is never force-killed. There is no general live queue count.
Pause is a drain-and-stop, and restart can reload models. Bloomy pauses its
automatic nudge/profit-switch paths while the protection action or owned stop
is outstanding. Upstream Autopilot settings are not changed.

Automatic restart authority is session-local and requires a confirmed stop,
unchanged saved configuration revision and hosting options, no replacement
provider identity, fresh stopped evidence and sustained lower GPU use. Manual
provider/config mutation, unsaved edits, switching to Off/Warn, or app shutdown
end restart ownership without starting the provider. Relaunching Bloomy does
not revive a prior stop. Shutdown cancels and joins dispatched work; a native
drain/reconciliation can delay quit, preserving accepted requests.

Independent review found that status is normally read every 30 seconds while
restart needs evidence at most ten seconds old. The rejected initial flow could
latch a routine stale snapshot as an error. The corrected flow refreshes
telemetry before checking restart permission and re-reads configuration before
dispatch. Changed/missing conditions defer without latching command failure;
actual failed/unconfirmed commands require explicit Retry. Regression tests
cover both behaviors.

## Throughput and history

The warning-only speed signal pins the same model's recorded baseline from the
first fresh active observation, before this run is added to the local averages.
It needs at least ten baseline measurements, a 30-second active-session grace,
continuous fresh positive rates and the configured sustained drop. High current
whole-Mac GPU use corroborates the warning. It never stops accepted inference.
Model/provider changes, gaps and idle reset the session. Missing/zero rates
break the low-rate streak without fabricating speed or moving the pinned norm.
Sparse provider token-counter updates may leave this signal unavailable.
Request shape/context length and other workload changes also affect throughput;
the wording is **Possible GPU contention**, not a diagnosis or guarantee.

Action History records controlled GPU settings, warning, pause/resume attempt
and completion events, plus serving slowdown warnings. No prompt, credential,
provider error prose or new private process inventory enters that journal.
Activity → Metrics adds **GPU while idle**, a time-weighted whole-Mac average
for adjacent idle observations with unchanged request counters. It shows its
observed duration; unknown counts, work, gaps and reset intervals cannot invent
coverage. This retrospective interval proxy may miss work between readings
and is not attribution to other apps.

## Verification

Policy/store/control/summary tests cover dwell, hysteresis, distinct timestamps,
invalid/missing/stale evidence, configuration/identity and operator precedence,
pause ownership, failure/defer behavior, cancellation/join and sparse throughput
baseline pinning. Final full verification passed with 1,520 reported tests
across the three test executables (seven explicit opt-in skips). The final
Release build completed successfully in 37.59 seconds. Focused recovery
verification passed 123 tests before that full run.

Native142 inspected compact light Off/Warn/Automatic settings, an 80→81→80
ceiling edit, zero commands for Warn, and one fake pause followed by one fake
restart. It is superseded for final source proof after the recovery fix. Its
inert recovery initially retained a stopped fixture context after fake start;
the helper now reports a running fake provider after successful recovery.
No real provider stop/start was invoked. A read-only status check found CLI
0.9.17, provider not running with a stale state file and the existing Sol-cache
access error; the watchdog was active. These are separate from this disabled,
unreleased feature and require their own startup diagnosis.

Native143 is the final source review: all 107 recorded source hashes, the
actual fixture binary and the linked Debug telemetry archive match its manifest.
Binary SHA256: `68c6a6a2e186f6c947241605a08248ea56dc5bbb143cdc4fc5656594b894290f`.
The final Release and fixture builds both finished successfully.

Native pointer checks inspected compact light Warn/Automatic controls and
recovery status in dark appearance. Warn recorded zero stops and zero starts.
Automatic breach recorded one fake stop, no start and owned pause; recovery
recorded one stop, one start, no ownership and Watching status. A second fake
breach followed by Off ended ownership; further recovered samples left totals
at two stops and one start. Activity Metrics rendered its idle GPU value and
observed-duration qualifier in compact light and wide dark. These are accelerated
inert policy/UI checks, not real GPU pressure or live provider lifecycle proof.

The fixture was quit normally. The installed production app remains the same
PID 61760, October 2 12:55:28 start and binary SHA256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
A second read-only CLI check again reported not running, stale state and Sol-cache
access failure; no real provider lifecycle command was sent by these checks.

Live provider/hardware serving, long-duration pressure behavior, production launch
over protected unsaved edits and signed/notarized updater distribution remain
open. This feature and checkpoint do not complete the broader polish goal.
