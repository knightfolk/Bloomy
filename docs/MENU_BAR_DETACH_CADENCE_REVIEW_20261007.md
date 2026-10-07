# Native menu-ring detach-to-close cadence — October 7, 2026

The retained manual host's reopening failures depend on the preceding detach
cadence in this comparison. Both immediate runs fail normal and rapid reopening
(12/15 motion); both compositor-observed runs pass those unchanged reopening
checks (14/15). Genuine cover fails in every run. This is a repeatable diagnostic
difference, not a production repair or a replacement release gate.

## Controlled treatment

Baseline is `da901c9`. Two optimized fixtures use identical staged Swift and
telemetry inputs. After output-path normalization, only
`FIXTURE_OBSERVED_DETACH_CADENCE` differs in compiler commands. The opt-in
`--motion-detach-cadence immediate|compositor-observed` overlay is confined to
the end of the existing detach case and diagnostic helpers/report metadata.
Ordinary builds retain the original helper unchanged.

Both arms retain the original detach actions and animation-key wait, then
capture the same synchronous native/window snapshots and elapsed time. The
immediate arm proceeds without an additional await. The observed arm accepts
two presentation angles advancing by more than 0.1 radians. Each accepted angle
requires full native visibility, unhidden attached state, retained backing/view/
arc/window/container identities, unchanged geometry and the exact single
1.4-second infinite rotation. It polls presentation directly without requesting
display, flushing transactions, configuring input, recovering lifecycle or
adding a hold. Observation errors stay failed even if later preparation recovers.

Both original reopening bodies, immediate rapid close/reopen actions, sustained
compositor observations and cleanup are unchanged. Existing lifecycle traces
retain pre-close native snapshots. Both modes report diagnostic-only scope and
preserve aggregate failure criteria.

Eight new staging checks cover exact inverse restoration of original source,
unchanged reopening bodies, treatment scope and fail-closed anchor/case drift.
All 30 staging checks pass. Seven incompatible mode/banner combinations reject
before staging. Independent read-only review found no material issue before
runtime and identified settling time as a remaining interpretation boundary.

## Native evidence

Every run starts a fresh process, completes all fifteen motion cases plus
Models/Charts and reaches a terminal aggregate before Quit. No further UI action
is taken during the case sequence. Terminal status controls were inspected;
all owned parent and cover processes subsequently exited.

| Run order | Cadence | Motion | Normal / rapid reopen | Treatment elapsed |
| --- | --- | --- | --- | --- |
| First pair, first | Immediate | 12/15 | Fail / Fail | 3.266 ms |
| First pair, second | Compositor observed | 14/15 | Pass / Pass | 23.014 ms |
| Reverse pair, first | Compositor observed | 14/15 | Pass / Pass | 47.684 ms |
| Reverse pair, second | Immediate | 12/15 | Fail / Fail | 1.538 ms |

All sixty motion cases are terminal: 52 pass, eight fail, none are missing.
Models and Charts pass in every run. All four observed reopening holds exceed
the 1.4-second production cycle (1.609342–1.671716 seconds); the minimum post-hold
angle advance is 0.187989 radians. Exactly one production rotation remains,
and recovery observations request no native display. The rapid case's stationary
follow-up also passes.

Each cover is opaque, above and contains the target in WindowServer, but fails
the target's actual occlusion-bit prerequisite. Every cover closes and exits
normally with status 0 and parent-request termination. The cover failure and
failed aggregate remain explicit in both arms. Original immediate-transition
qualification is still open.

## Provenance and preserved state

Outputs are `.build/detach-cadence-immediate-20261007` and
`.build/detach-cadence-compositor-observed-20261007`. Each retains immutable
sources, manifest, app, `runtime-evidence-first/` and `runtime-evidence-reverse/`.
Matching root names plus `-build.log` retain build output; both jobs joined at
exit 0. Both manifests record 122 current source hashes and identical staged
source bytes. The verification summaries are
`.build/cadence-{source-verification,flag-verification,runtime-summary}-20261007.json`.
The runtime summary includes all report hashes, angle/hold checks and PID absence.

Binary SHA-256:

- Immediate: `d0f94d3eba30fcb4829f402adf090123e9815807ab4351ee11a9c3cea94d3bcd`
- Observed: `47c1f197a8e1c146eab2b47378a22c89f7e36ac8936035d4df3ca445d18c65b2`

Shared staged helper SHA-256:
`38ed4b627321c951155c52a1e8a11f9644f69650bbfb26200a2edfff94b186f2`.
Original dirty helper remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Parent/cover PIDs 7061/7079, 7130/7146, 7223/7234 and 7290/7313 are verified
absent. No post-Quit accessibility lookup was used. Production app, provider
configuration, credentials, cache and unrelated dirty work are preserved.
No fresh full package test run is claimed for fixture-only changes.

## Next distinction

The observation treatment couples presentation reads, repeated polling/yields
and elapsed settling time. Test a 50 ms delay-only arm at the same boundary,
slightly above both measured observation durations. Use a single bounded sleep,
no presentation reads during treatment, and validate retained identity/geometry,
full eligibility and the clock afterward. Preserve all reopening assertions.
If it passes, short elapsed/run-loop settling is sufficient in this host. If it
fails, a single sleep has not reproduced the observed treatment; scheduler and
presentation-read effects remain possible factors.

Neither result establishes a particular Core Animation mechanism or the
identity of a newly committed animation generation. Product causality still
needs a supported production host reproducer with fresh inputs and stable native
state. Passing Settings/status-item proofs do not exercise this manual retained
detach-to-immediate-close path. Genuine occlusion, the original gate and broader
Apple-design/accessibility/performance requirements remain open. The goal is
active.
