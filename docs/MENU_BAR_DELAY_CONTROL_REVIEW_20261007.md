# Native menu-ring delay control — October 7, 2026

A single 50 ms sleep after detach passes both unchanged reopening checks in
two fresh processes, as does compositor observation. Immediate controls fail
both reopening checks in both run orders. Presentation polling is therefore
not required for the observed improvement in this retained manual host.
This is diagnostic evidence, not a production repair. Genuine cover and the
ordinary native gate remain failed/open.

## Scope and controls

The fixture-only change extends `--motion-detach-cadence` with `delay-only`.
All three optimized builds stage identical source. Compiler definitions select
immediate continuation, compositor observation, or one 50 ms sleep after the
same original detach actions and animation-key wait. Shared synchronous
before/after diagnostic snapshots read native presentation in all arms; the
delay treatment adds no presentation reads during its sleep or validation.

Delay validation checks cancellation, retained native identities, unchanged
geometry, complete visibility eligibility and the exact single 1.4-second
infinite rotation. No display, flush, configuration, lifecycle repair, polling
loop or additional sustained hold is added. Both original normal/rapid reopening
bodies and their sustained-motion assertions remain unchanged. An exact inverse
staging regression verifies that the ordinary helper is preserved.

Thirty-two staging tests pass, including the two new single-sleep/scope checks.
Seven incompatible diagnostic/banner flag combinations reject before staging.
The bounded read-only review found no material issue and retained the
elapsed-time/run-loop interpretation limit.

## Completed native evidence

| Order | Arm | Motion | Normal / rapid reopen | Detach treatment elapsed |
| --- | --- | --- | --- | --- |
| Forward 1 | Immediate | 12/15 | Fail / Fail | 1.631 ms |
| Forward 2 | Compositor observed | 14/15 | Pass / Pass | 67.173 ms |
| Forward 3 | Delay only | 14/15 | Pass / Pass | 51.943 ms |
| Reverse 1 | Delay only | 14/15 | Pass / Pass | 54.982 ms |
| Reverse 2 | Compositor observed | 14/15 | Pass / Pass | 23.611 ms |
| Reverse 3 | Immediate | 12/15 | Fail / Fail | 1.224 ms |

Each invocation starts a fresh process and completes all fifteen motion cases
and Models/Charts before Quit. The forward controls preceded a research
continuation; these were counterbalanced fresh-process observations, not a
continuous or matched-resource benchmark. Actual elapsed times are reported;
50 ms was chosen from the earlier comparison and does not exceed every observed
interval in this comparison.

All ninety motion cases are terminal: eighty pass, ten fail, none are missing.
Models and Charts pass in all six runs. All eight successful reopening holds
last 1.603666–1.692799 seconds, exceeding the production cycle. Their minimum
post-hold angle advance is 0.188259 radians, and each retains exactly one
production rotation without requesting native display. Rapid reopening's
stationary follow-up passes in every successful arm.

All six cover cases fail the actual occlusion-bit prerequisite despite opaque
cover containment and front ordering in WindowServer. Each cover closes and
exits normally, with status 0 and parent-request termination. Every aggregate
remains failed. Terminal controls were inspected before Quit; all twelve owned
parent/cover PIDs were subsequently verified absent.

## Provenance

The three optimized build jobs completed and joined at exit 0. Outputs are
`.build/delay-control-{immediate,compositor-observed,delay-only}-20261007`.
Each retains its manifest, staged source, app and separate
`runtime-evidence-first/` and `runtime-evidence-reverse/` reports. All 122 source
hashes per manifest match the current checkout; binary hashes match. Normalized
compiler commands differ only in mode definitions and output paths.

Binary SHA-256:

- Immediate: `5a467501f4ce1b05cf841242f3348f7838ce1fee18c36d1414dcb70a54c7bd22`
- Observed: `c123c4ae755a9d042258f50b0b7fb7cc5d6d41cf84d251b43fab0cda23a1d09b`
- Delay: `518eeb71ff09f293abb548879d956348b996868412696f3426207cad4ff6054a`

Shared staged helper:
`026f15dad9c1020b9c1fbd27414ac5f075b01248752fc99407ac5cd4499fb54f`.
Original dirty helper remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Production label remains
`a71ff6af64a20393f625f4655dae2fecda365a46091c39e87a477866822bb22f`.

Verification summaries are `.build/delay-only-{source,flag}-verification-20261007.json`
and `.build/delay-control-runtime-summary-20261007.json`. The latter preserves
all report hashes, hold checks and absent PIDs: 21630/21652, 21804/21824,
34539/34548, 34878/34888, 34939/34953 and 35019/35034. Production app/provider,
configuration, credentials, cache and unrelated dirty work are preserved.
No fresh full package run or distribution readiness is claimed for this
fixture-only change.

## Consequence for the polish work

A short settling interval is sufficient under these test conditions; the
experiment does not establish the precise Core Animation mechanism or a newly
committed animation generation. Do not add a production sleep, retry timer or
replacement gate on this evidence.

The supported production Settings/status-item hosts already pass their bounded
lifecycle checks, but those checks do not reproduce this retained manual
detach-to-immediate-close transition. Next extend supported-host evidence to
dynamic menu extras and Reduce Motion changes, and investigate the independent
cover prerequisite separately. Preserve immediate-transition failure evidence
until a supported reproducer or a justified test-host repair establishes its
cause. The broader native, accessibility, performance and Apple-design matrix
remains open; the goal stays active.
