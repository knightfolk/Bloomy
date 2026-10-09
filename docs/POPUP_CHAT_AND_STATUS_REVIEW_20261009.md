# Popup Chat and status review — October 9, 2026

The popup’s More menu now includes Open Chat. It opens the existing retained,
resizable Chat window with the shared conversation and updater protection. It
uses the menu’s existing deferred action, after menu dismissal, and the production
controller closes the parent popup before presenting Chat. No new chat store,
route, credential access, inference or network request is created by navigation.

A source audit confirms popup access to provider lifecycle, model selection and
management, Auto mode, Autopilot, Hosting, cooling, GPU protection, nudges/key setup,
profit switching, energy, appearance, updates, Support and Health & Logs. Detailed
Activity calendars, Opportunity exploration and Action History remain dashboard
workspaces. Native confirmations, Keychain/system prompts, save dialogs and
Terminal-managed local-only hosting retain their existing handoffs. Companion
has no functioning controls in this version.

## Unchanged status publication

Fan-only and Autopilot-only refreshes now publish a snapshot only when the
complete result differs. Equality includes capture times, availability cases,
values and diagnostic reasons. The first failure still marks retained evidence
stale; repeated identical failures no longer publish that same snapshot. Successful
readings with new timestamps and recovery still publish. Reads, retry cadence,
refresh progress publications, full refreshes, cancellation ownership, mutation
guards and command reconciliation are unchanged.

Two parameterized regressions cover both sources through first failure, repeated
retained failure, first recovery, renewed successful timestamps, exactly identical
successful evidence, initially unavailable evidence and changed unavailable
reasons. They count snapshot publications directly and assert reads still happen
without mutations. The baseline fails 14 expectations; the candidate’s 68 focused
tests in four suites pass, including existing shared gate, cancellation, native
popup layout and retained Chat updater guards. The 49 staging tests pass.

The guard removes one snapshot publication per exactly unchanged partial read.
The two refresh-progress publications remain. No whole-app CPU, battery or power
saving is inferred from this component change.

## Review ownership

Evidence root: `.build/popup-idle-overhead-review-20261009/`.
Independent source review found no actionable findings.
The installed Bloomy 1.9.19/build 144 remains untouched. Its short read-only stack
sample is an old-build observation, not qualification of the current source.
The real provider stopped and later restarted independently during this checkpoint.
No provider start, stop, swap, download, nudge, inference or configuration write
was performed by this work. Existing host workloads were preserved; provider
activity was not held constant for these isolated-process observations.

## Native and resource evidence

The optimized isolated fixture uses production SwiftUI views with private
preferences, fake provider/hosting/account/key dependencies and no real inference.
CPU/GPU acquisition is disabled; fan/temperature samples are synthetic. All 142
source-input hashes match the checkout, and deep strict review signature checks
pass. Executable SHA-256:
`fe2b9c15c1651e9bde97c33928b29a0fa25f355d756f1840867fcf74bd5400da`.

Computer-use checks verify Open Chat appears in the native More menu at the
360-point parent budget and opens the existing separate Chat window. Inert local
conversation creation exposes model choice and Refresh; an unsent draft survives
another Open Chat action in a dark popup. Light/dark Chat captures are retained.
The test draft was cleared without Send. The actual native close control was not
exposed in the active Chat capture, and Command-W did not change that window;
native close-and-reopen proof is unqualified. Existing automated retained-draft
and updater-protection checks pass. No product workaround was introduced.

Expired Autopilot status correctly shows Last known: Off with Enable disabled.
A fresh read through Refresh returns Off and enables enrollment. No enrollment
or policy mutation was requested. Nested Done and parent Cancel close the popup.

The process counter calibration agrees with getrusage within 2%. Two accepted
30-second windows run after all finite build/test/sample jobs finish, without UI
observations or other task-owned workloads during measurement. Native visibility
events remain unchanged throughout each window:

| Current fixture state | CPU, percent of one core | Median footprint | Interrupt wakeups/s |
| --- | ---: | ---: | ---: |
| Both review windows minimized; popup closed | 0.496% | 108.11 MiB | 0.50 |
| Overview restored; Chat minimized; popup closed | 1.220% | 108.49 MiB | 3.73 |

The ordinary five-second synthetic source publications continue in both states.
These are current-workload observations, not before/after savings, production
collector qualification, long-duration stability or power/battery measurements.
The native observer reports displayEnabled false when minimized and true after
restoration. Raw counters, calibration and retained visibility evidence are in
the evidence root. This does not complete the broader resource gate.

## Verification and delivery

- 68 focused tests in four suites pass.
- Full serial Release run: 1,864 reported app tests in 234 suites, plus 21 and 28
  Companion tests, exit 0. Seven existing opt-in tests skip.
- 49 staging tests pass.
- Regular Release build passes, 59.26 seconds.
- Independent source review finds no actionable issues.
- Protected concurrent MenuBarMotionProof.swift remains
  `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
- Real provider configuration changed independently from the earlier
  `e081909a3b2db8b1453e87efe30ca77322476b3d4ea16ff9ee8872447114093f`
  to `b7d3067043e57b297a21c174297e412804d568f86e85a7172f00df6eeb181aaf`.
  Its current provider processes 21956/21962 and installed Bloomy 7234 are preserved.

The isolated review app quit normally after its evidence was preserved. All
finite build, test, sampling and profiling jobs completed and were joined.
This is a local-only checkpoint. No installed replacement, push or release occurs.
Native activation/keyboard/VoiceOver, constrained-path coverage, confirmation
pixels, sustained production resources and distribution gates remain open.
The continuous polish goal remains active.
