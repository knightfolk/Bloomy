# Hosting and history recovery review — October 2, 2026

This checkpoint repairs Hosting action races and adds a manual network-history
retry. It also improves isolated native window proof. The broader polish and
efficiency goal remains active; this is not a release or full accessibility signoff.

## Production behavior

Hosting Apply captures its options and local-token revision before awaiting the
provider operation. A token saved during the follow-up read retains its restart
warning, because that newer token was not loaded by the earlier operation.
Failed or overlapping Apply attempts also preserve pending state. Applying an
unauthenticated or disabled endpoint describes the saved token as available for
a future authenticated start, rather than claiming it is currently active.

A successful Apply invalidates cached endpoint discovery. Explicit token Copy
remains available for a fresh read after a previous unauthenticated endpoint
snapshot; the current read still rejects an unauthenticated live endpoint and
cannot substitute a token staged on disk. Generations prevent late discovery
results from repopulating invalidated state or copying obsolete credentials.
The production clipboard path is injected for tests, which record synthetic
values without changing the user's clipboard.

Opportunity > Network activity exposes Refresh and a disabled busy state, with
the accessibility name “Refresh network history.” Manual success replaces a
previous long failure sleep with the five-minute successful deadline; another
failure replaces a shorter wait with the increased bounded backoff. Replacement
cancels and joins the previous owned polling loop, while visibility, shutdown,
and in-flight-read guards remain in place. Automatic refresh behavior is unchanged.

The provider-update action now has the specific accessibility name “Enable
automatic provider updates” or “Disable automatic provider updates,” with a
distinct saving label.

## Native 22 observations

The app was an isolated synthetic AppKit fixture with production dashboard,
popup, Chat, and Settings views. No real provider start, inference, swap,
download, credential access, configuration mutation, or permission change was
needed. CPU/GPU/power acquisition stayed disabled. The banner disclosed actual
Mac name and host thermal state. The running production app was preserved.

The fixture previously changed navigation when its popup opened the dashboard,
but did not restore its minimized native window. All fixture presentation routes
now share the owned window restoration path, and generic Open dashboard preserves
the selected page. This is fixture fidelity work, not a production window fix.

With the opt-in focus trace enabled, Window > Minimize recorded native window
10887 as minimized and invisible. Popup > Open dashboard recorded that same
window as no longer minimized and visible, with its original frame retained.
These are actual native flags, rather than an inference from cached window
captures. The trace contained 47 records within its shared 49-record limit.
Tracing adds diagnostic work and is not a performance measurement.

The ten-second synthetic Chat verification started fresh with Send enabled and
the typed unsent draft `Keep this message through a window restore.`. After
minimization and restoration, the expired banner and disabled Send appeared
with that exact draft retained. Production Refresh restored fresh verification,
four models, and enabled Send without changing the draft. No message was sent.
Native sidebar arrow navigation then changed the selected page after restoration.

In compact light appearance, Network activity Refresh updated its synthetic
history timestamp from roughly four minutes old to current. Offline retries in
compact light and dark appearances retained honest unavailable wording and a
usable Refresh action after the read failed. These are controlled UI outcomes,
not live network or provider evidence.

In compact dark Electricity settings, disabling the estimate disabled the price
field. Enabling it made the field editable. Entering `-1` displayed the
non-negative-price validation message; `0.15` cleared it. Disabling the estimate
retained the valid price. These changes stayed in isolated fixture preferences.
The Updates page exposed “Disable automatic provider updates” in its native
accessibility tree; that action was not invoked.

The compact dark Support review sheet fit its preview, review checkbox, Close,
and Save controls. Return before acknowledgement left Save disabled. Escape
closed the preview. After reopening and clicking the review checkbox, Return
opened the native export dialog. Cancel returned to the reviewed preview without
a failure message; Export was never selected, and no report was saved or shared.
Tab and Space did not visibly change focus/checkbox state in this CUA session;
Escape in the native export dialog also produced no observed dismissal. Those
keyboard paths remain unverified, rather than counted as passed or attributed
to a production defect without causal evidence. Actual VoiceOver remains pending.

Subsequent fresh-session review targeted the actual sheet/panel with its native
Raise action. Space, the checkbox/Close/Save Tab cycle, Return review gating,
and Escape export/preview cancellation then passed in wide light and compact
dark checks without changing Support focus code. See
[Quit cleanup and keyboard review](QUIT_CLEANUP_KEYBOARD_REVIEW_20261002.md).
The earlier inconclusive observations remain recorded above.

The fixture quit through its popup, completed owned cleanup, and process absence
was checked. No production app was quit or replaced.

## Source identity and verification

Local evidence remains under `/tmp/bloomy-efficiency-20261001/`.
`native22-fixture-manifest.json` records 77 source hashes, dependency substitutions,
and the compiler command. All source hashes matched before launch and after the
native checks. The builder stages the fixture source and linked library before
compilation and hashes those exact bytes. The test-only hidden-render repair
postdated this native build; production sources were unchanged afterward.

- Fixture binary SHA-256: `c4562cb77f1f7f5d01d6dc334bd497bd39550dd9b34681be5dc579d8269513fe`.
- Linked telemetry library SHA-256: `64f14e507ddee718f08e506edb3bbefa84fa5948470ef13c5153cf88199bdd30`.
- Native lifecycle trace: `native22-window-focus-diagnostics.jsonl`.

| Retained evidence | Result |
| --- | --- |
| `hosting-recovery-race-red-tests.log` | Before the fixes, 22 tests produced six expected assertion issues. |
| `hosting-recovery-race-tests.log` | 31 focused Hosting tests passed. |
| `network-history-manual-retry-tests-02.log` | Four network polling tests passed, including held-read duplicate rejection and both manual rescheduling directions without reopening the dashboard. |
| `visibility-clock-focused-tests.log` | Five tests with 13 parameter cases passed. |
| `hosting-history-recovery-full-tests-02.log` | 1,163 app/telemetry tests in 152 suites (25.327 s), 21 companion tests in five suites (0.014 s), and 28 host tests in nine suites (11.417 s): **1,212 tests passed**, terminal exit 0. |
| `hosting-history-recovery-release-build.log` | Final release compilation passed in 45.82 s, terminal exit 0. |
| `native22-window-hosting-recovery-build.log` | Final native fixture compilation passed, followed by the bounded checks above. |

The first full run, `hosting-history-recovery-full-tests.log`, exposed an extra
finite hidden initial render after a test's fixed 150 ms settling delay. The
test now waits for a render carrying the hidden visibility snapshot and a date
at or after the hide request before checking exact date stability for five
intervals. It retains the same mounted host, stopped-date equality, and fresh
restore/tick assertions. Production timeline scheduling and test tolerances
were not weakened. The first manual retry implementation did not replace an
already sleeping automatic loop; independent review caught that omission before
the final wrapper and regression tests. Native 21 was an unlaunched intermediate
build during concurrent edits and is not final-source proof.

## Preserved state and remaining gates

Production Bloomy remains v1.9.15/build 140, original PID 31677 started October 1
at 22:40:57, binary SHA-256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
The real provider configuration hash remains
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
Current CLI status says `Daemon: not running (stale state file)` and watchdog
installed but not loaded. No provider/recovery launch service is loaded. Provider
and recovery remain deliberately off for Kevin's other work.

Remaining review includes the full route/appearance/size/source-state matrix,
complete native keyboard traversal, actual VoiceOver, controlled Reduce Motion,
and comparable current production CPU/energy/allocation measurements. Hosting
race tests are store-level proof, not live credential setup or restart proof.
The production Sol cache permission boundary and required release checks remain
open; the scoped removable-drive privacy reset is pending human approval.
No privacy, drive, or Keychain workaround was attempted. Signing, notarization,
updater installation/relaunch, and publication are separate gates under
[RELEASING.md](RELEASING.md).
