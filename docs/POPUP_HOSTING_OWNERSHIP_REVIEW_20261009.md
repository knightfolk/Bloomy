# Popup Hosting confirmation ownership

October 9, 2026, America/Phoenix. Verified local functional checkpoint; native
dialog pixels, distribution and the broader polish/efficiency goal remain open.

## Problem and repair

Dashboard Hosting and popup Hosting share one store and can remain mounted
together. Previously, both read the same unowned pending-options flag. Either
editor's dismissal could clear the other's request, and a stale callback could
consume a replacement request. Source inspection demonstrated this ownership
gap; the baseline native run reached the dialog but did not demonstrate two
simultaneous alerts or their timing.

Each editor now has a stable owner UUID. A pending confirmation records that
owner, a unique request UUID and the immutable options the user is reviewing.
Only that editor receives the request. Confirm and Cancel require its exact
identity; stale callbacks cannot consume later settings. Labels and explanatory
text come from the captured request. Existing ownerless callers retain their
single-request behavior but cannot consume editor-owned requests.

System dismissal and editor disappearance defer cancellation by one actor yield
so a synchronous Confirm callback can reserve its request before its task starts.
Protection is request-specific, rather than one flag for the entire editor.
An older graceful restart cannot shield a newer dialog from dismissal. The
existing update guard still reads pending options, and partial nonsecret input
remains in the separately retained dashboard and popup drafts.

Read-only review caught the initial editor-wide suppression race. A regression
held restart A, created request B, dismissed B, and failed because B remained
pending. The corrected coordinator clears B while A remains suspended, then
verifies that only A dispatched. Final re-review found no further findings.

## Checks

Six added regressions cover editor ownership, stale same-owner replacement,
cross-editor delayed dismissal, Confirm/teardown ordering, ordinary system
dismissal and newer dismissal during an older held restart. Existing LAN,
authentication, retained draft and updater tests remain.

- Final focused Release selection: 99 tests in four suites pass.
- Full serial Release run: 1,838 app tests in 230 suites pass, with seven existing
  opt-in skips; 21 companion contract and 28 companion host tests pass.
- 49 native staging checks pass. Optimized production targets and the final
  native fixture compile; `git diff --check` and strict/deep fixture signature
  verification pass.
- The final fixture matches all 142 recorded source inputs. No production
  visibility override, new poller, release gate replacement or provider mutation
  was introduced.

Logs and review metadata are under `.build/popup-resource-review-20261009/`:
`hosting-focused-tests.log`, `hosting-newer-dismissal-red.log`,
`hosting-final-focused-tests.log`, `hosting-full-release-tests.log`,
`final-staging-tests.log`, `hosting-final-fixture-build.log` and
`review-manifest.json`.

## Native behavior and visual limit

The final isolated optimized fixture retains production view bodies and inert
provider/endpoint/token dependencies:

`.build/hosting-owner-review-20261009-b/Bloomy Dashboard Fixture.app`

Signed executable SHA-256:
`d02afcd56fa2d4de11649eef790c135c49649d2adbb4088f5892048e469ce662`.

At compact 800-by-560 dashboard size, dashboard Hosting remains selected while
More → Hosting opens the popup editor. The new Apply request exposes the expected
native network-access title, message, Confirm and Cancel actions. Cancel returns
to the same popup Hosting panel. This is observed behavior, not proof that all
other mounted windows lack an alert; exact ownership is established by the
store regressions and matching view wiring.

Entering the invalid partial port `8x` disables Apply. Done closes the panel;
dismissing the parent popup and reopening More → Hosting in dark appearance
retains `8x`. The independent dashboard input remains `8000`. Discard restores
the popup input to `8000` and re-enables Apply. A fresh Confirm consumes its
request and returns to the panel with the fixture's safe unsupported-application
error. The inert controller cannot restart a real provider; successful captured
options and exactly-once dispatch are verified by the store's spy tests.

The ordinary light and dark panels render. The light screenshot shows the
invalid field and validation; the retained dark still shows the panel's upper
content, while accessibility proves the retained field below the viewport.
Dialog capture produces blank pixels despite the expected native accessibility
tree. The image is retained as failed visual evidence, not approved pixels.
This limitation was previously observed outside Bloomy; this run does not prove
its cause or establish a remedy. Native dialog visual qualification stays open.

Evidence is in `native/`: action-state observations, `dialog-full.ax.txt`,
`hosting-confirmation-light.png` (blank), `hosting-partial-port-light.png`, and
`hosting-retained-port-dark.png`. No screenshot substitutes for sustained motion,
VoiceOver, whole-app performance or release proof.

## Ownership and handoff

Both review processes exited through the native More → Quit menu and are absent
after completion. An earlier baseline keyboard Quit attempt did not exit; this
was checked before using the supported menu action. The unlaunched fixture built
before the final coordinator correction was removed only after final-source
verification; its manifest and build log remain, and exact removed paths/bytes
are recorded in `owned-cleanup.json`.

Installed Bloomy remains PID 7234, provider PID 82428 and recovery PID 82434.
Provider configuration SHA-256 remains
`a559a8a109cb7ee6940cb9129cde2ce0305698ffe95148e126a803a69b0e495d`.
No real start/stop/restart, inference, swap, download, token/security change,
installed replacement, push or release occurred. The pre-existing dirty motion
proof remains at
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.

The next independent performance experiment is described in
[closed-popup fitting investigation](POPUP_HIDDEN_FITTING_INVESTIGATION_20261009.md).
Its installed measurements do not establish savings or qualify the newer source.
