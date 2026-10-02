# Provider, Fans, and Updates settings — October 2, 2026

This is a bounded checkpoint in the continuing native polish and efficiency run.
The installed production app and its unsaved state were preserved. Native review
used isolated synthetic apps with CPU/GPU acquisition disabled and no real fan,
model, network inference, credential, or updater mutations.

## Changes and failures reproduced

- Idle and beta writes now validate their own source evidence again when they
  enter the settings store. A queued action cannot use an earlier UI decision
  after its evidence expires. Sources retain their independent 45-second age.
- Idle and beta presentation uses finite visible timeline deadlines. Empty beta
  results also become historical claims when expired. Hidden views request no
  recurring display clock. Native 51 exposed a further integration failure:
  discarding the timeline context date let SwiftUI retain the earlier section
  presentation. The final render paths explicitly receive that changing date;
  actual write validation still uses the store clock.
- A completed fan command no longer clears a submitted draft before a fresh,
  loaded, error-free helper readback matches its policy. A later matching read
  can confirm the same submission. Newer edits cannot be cleared by confirmation
  of an older submission. Completed but unconfirmed commands have distinct
  feedback from failed commands or fully confirmed saves.
- An expired helper cannot provide an actionable on/off toggle merely because
  the enclosing CLI read is recent. Temperature and each fan measurement retain
  independent freshness and spoken qualifiers.
- Retained CLI update notices use past-tense explanations and absolute dates.
  An old restart result no longer instructs the user to restart. Native 51 also
  exposed a truncated compact explanation; each paragraph now explicitly wraps.

## Regression and build evidence

Logs are retained under `/tmp/bloomy-efficiency-20261001/`.

- `provider-idle-beta-freshness-red-01.log` reproduced 38 issues in 6 tests.
  The first green execution-guard run passed 7 tests.
- `provider-visible-expiry-focused-03.log` passed 15 tests in 2 suites after
  the native render-date repair. These pure presentation tests alone do not
  establish real visible expiry.
- `fan-settings-focused-01.log` passed 23 test definitions in 4 suites. Fan
  state regressions cover matching/mismatched/stale/unavailable confirmation,
  helper age, per-field freshness, and later edits.
- `cli-update-presentation-focused-01.log` passed 8 tests in 2 suites, including
  all four historical status variants.
- The first combined run exposed an outdated polling test that wrote beta
  settings using 200-second-old evidence. The corrected test requires rejection
  without a write or implicit read, then explicit refresh and successful write.
  `provider-extras-polling-freshness-focused-01.log` passed all 6 polling tests.
- Final `provider-fan-cli-full-04.log` exited 0: 1,275 app/telemetry tests in
  168 suites (26.200 s), 21 companion-core tests (0.014 s), and 28 companion-host
  tests (11.630 s), **1,324 total**.
- Final `provider-fan-cli-release-02.log` exited 0 in 44.36 s. Earlier build/test
  runs preceded later native findings and do not establish the final source.

## Native evidence and limits

Native 49 supplied the settings baseline: Provider, Fans, Companion and Support
were inspected in compact light appearance. Idle text `45` and an unsaved Quiet
fan preset survived navigation. Companion explicitly said its capability was
not available. The 600 × 550 Support preview kept its review gate and footer
reachable; keyboard acknowledgement enabled Save and Return opened the native
exporter. After user intervention the preview reported that the synthetic
report was saved. The agent did not record the destination or remove that file.

Native 51 reproduced the still-current idle display after real evidence expiry.
It also verified the fan-save path through production controls: one Quiet policy
submission (60%, 45 °C) remained awaiting confirmation with an original policy
readback, survived persistent failed readings, then cleared only on matching
readback. Its fixture-owned JSON recorded exactly one command and the same
submitted values. Partial cooling showed current 42 °C, retained Fan 1 at
2,200 RPM, current Fan 2 at 1,200 RPM, and unavailable helper on/off state. The
compact CLI restart notice had correct historical wording but clipped text;
the final layout repair followed this observation.

Native 53 matches all 85 manifest source hashes and its binary SHA-256:
`d41d62922b337c00d70a9230929240cdc567a4d983c9b1704d638e8408ce020e`.
Its manifest is
`.build/native-dashboard-fixture-20261002-53/fixture-manifest.json`.

- In Frozen settings, the compact light Provider page initially enabled Save
  for typed `45`. Without any intervening UI action or data refresh, the real
  deadline changed the saved badge to Last known, disabled Save, removed beta's
  Change menu, and exposed both refresh notices. The typed value, dirty marker,
  and Discard action remained. Compact dark rendering showed the same expired
  idle and beta state clearly. A fresh scenario restored eligibility with `45`
  retained; an explicit inert Save confirmed After 45 min and cleared the edit.
- Compact dark Updates displayed the complete historical restart explanation
  without a restart instruction. Compact light quarantine text wrapped over
  two lines and kept its dated last-check and failure qualifier visible. The
  explicit production Check for updates action restored current wording through
  the inert client.
- Wide dark Fans retained per-field visual and spoken freshness: 42 °C current,
  Fan 1 at 2,200 RPM last observed, and Fan 2 at 1,200 RPM current with no target
  invented. The expired helper supplied no on/off toggle. Refresh readings was
  actionable and advanced the CLI check time while preserving these distinctions.

Native 49, 51 and 53 closed through their own Quit command; no fixture process
remained. Native 50's fixture-only compilation failed at an actor crossing using
a dictionary result; a typed Sendable proof record repaired it. Native 52 was
built but superseded before inspection by the CLI paragraph repair. Neither is
claimed as final native proof. Screenshot/accessibility outputs are retained in
this chat. The fan command-count record remains in Native 51's unique temporary
fixture directory. After all writers and fixture processes stopped, the unused
Native 50/52 app copies were removed; their staged sources, available manifest,
and diagnostic logs remain. Baseline and inspected apps were retained.

Broader light/dark, size, keyboard, actual VoiceOver, and live hardware matrices
remain open. These fixtures do not prove real provider controls or release
readiness. Production PID 31677 retained its original launch and binary hash;
no production relaunch was used to obtain these results.

## Scoped provider permission reset

Kevin authorized resuming the provider and subsequently approved resetting only
Darkbloom's removable-drive permission. The reset for
`SystemPolicyRemovableVolumes` / `io.darkbloom.provider` succeeded. The official
saved-settings restart still exited 1 while opening the Sol cache, then reported
no models selected. Its finite restart command exited 64 after 180 seconds; no
second restart was issued on that timeout. The failed service and its recovery
watcher were stopped through the official CLI.

System Settings showed Darkbloom's removable-volume switch on. Cache ancestors
exist with normal permissions, and CLI/LaunchAgent paths resolve to the same
validly signed vendor executable. A read-only model scan through that executable
exited 0 and reported 12 models in the expected cache without stderr. This
separates shell access from the managed launch failure; it does not prove the
underlying daemon error.

Narrow logs show macOS rejected this vendor executable's AppleEvents request
because its automation entitlement is absent. That signing defect is confirmed;
its causal connection to the cache failure is unproven. No supported read-only
permission preparation command appeared in installed help. The managed service
already uses the vendor's foreground path, so changing that flag would repeat
the same launch behavior. No broader reset, Full Disk grant, entitlement edit,
configuration change, or cache relocation was attempted.

The saved configuration SHA-256 remained
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
The smallest useful vendor diagnostic is the underlying cache-open error and a
read-only access check inside the managed launch context. No message was sent.
