# Chat expiry and hidden display work — October 2, 2026

Chat now visibly expires model verification without making an automatic API
request, retains unsent text, and offers manual Refresh recovery. Retained
dashboard views stop their recurring display clocks while hidden, and the
resource panel stops its own CPU sampler. This checkpoint advances the ongoing
[polish plan](APP_POLISH_OPTIMIZATION_PLAN.md); it does not establish measured
whole-app performance or complete native accessibility/release proof.

## Chat state and deadline behavior

[ChatStore.swift](../Sources/DarkbloomMonitor/ChatStore.swift) defines six explicit
verification states used by [ChatView.swift](../Sources/DarkbloomMonitor/ChatView.swift):

| State | Visible meaning |
| --- | --- |
| Unverified | No verified list; Refresh is required before sending. |
| Refreshing | A model-list read is actually in flight. |
| Fresh | The accepted list is current, with the available model count. Other route/send gates still apply. |
| Empty | Verification succeeded with no available models; sending remains disabled. |
| Expired | The cached list is outside the allowed time window; Refresh can recover. |
| Failed | A fixed, route-specific failure is shown; the manual Refresh button remains available and sending is disabled. |

Freshness is inclusive at 120 seconds and tolerates at most five seconds of
future clock skew: ages -5 and 120 seconds are valid; -5.001 and 120.001 are not.
A single shared, cancellable deadline is owned by the store while at least one
mounted Chat surface has a visible window. It publishes just after the boundary
(120.001 seconds), so the banner and Send state update without a per-second
Chat clock. Hiding/removing the last surface cancels that task; restoration
immediately recomputes the gates. Dashboard and pop-out ownership are independent.
The pop-out controller forwards close, minimize, and restore through
[ChatWindowController.swift](../Sources/DarkbloomMonitor/ChatWindowController.swift).
Wall-clock changes already on screen are re-evaluated at the scheduled deadline
or the next source/visibility event; no immediate system-clock-change observer
was added.

The deadline updates presentation only. It never calls the model API, invokes
inference, retries a failure, or changes a route. Existing explicit New Chat,
manual Refresh, and send preflight behavior remain separate. Failed reads
invalidate that route until an accepted successful read; a new conversation or
route round trip cannot resurrect the failed cache, including while a retry is
pending. Refresh/conversation generations and network credential generations
discard obsolete completions. When the clock moves behind a cached sample, a
new current successful read can replace that invalid future cache even though
its timestamp is earlier; a merely older still-valid cache replacement cannot.

[ChatStoreTests.swift](../Tests/DarkbloomTelemetryTests/ChatStoreTests.swift) checks
boundary ages, failure/empty presentation, one shared deadline, last-owner
cancellation, remount, no deadline API reads, rollback recovery, suspended
retries, overlapping reads, conversation changes, and old-key completions.
[ChatViewTests.swift](../Tests/DarkbloomTelemetryTests/ChatViewTests.swift) checks
mounted expiry/draft/manual recovery for both routes and pop-out ownership.

Replacing the dashboard's Chat store also replaces the mounted Chat view using
`.id(ObjectIdentifier(chatStore))` in
[DashboardRootView.swift](../Sources/DarkbloomMonitor/Dashboard/DashboardRootView.swift).
Before this identity correction, the replacement regression failed both targets:
the old store retained its deadline and the new store acquired none. The test
now passes. The retained dashboard message draft remains owned by the dashboard
and reconciles with the new conversation; store replacement is not permission
to move a message into a different conversation.

## Hidden display and CPU work

[VisibilityTimelineSchedule.swift](../Sources/DarkbloomMonitor/Components/VisibilityTimelineSchedule.swift)
wraps the original schedule. Hidden views emit their initial current date only;
visible views emit a current date immediately and continue the original cadence,
including calendar/minute alignment and periodic phase. Duplicate or preceding
dates are skipped. Restoring uses a new current date instead of replaying hidden
ticks or shifting the underlying cadence.

Adoption covers Overview and its model summary (1 s), Hosting selection (2 s),
Health and thermal display (5 s), Opportunity/model opportunities, network
history and cache (10 s), and Activity Earnings (calendar minute). Health's
thermal clock also follows its disclosure. These are display updates; this
change does not suspend provider monitoring, alerts, history recording, or
automatic actions. See the corresponding dashboard views and
[ProviderExtrasViews.swift](../Sources/DarkbloomMonitor/ProviderExtrasViews.swift).

[VisibilityTimelineScheduleTests.swift](../Tests/DarkbloomTelemetryTests/VisibilityTimelineScheduleTests.swift)
checks finite hidden sequences, 1/2/5/10/60-second visible cadence, calendar
boundaries, phase-preserving restore, and a retained native hosting view stopping
and resuming dates. The native hosting test checks the same host remains mounted;
it is not production minimized-window CPU measurement.

[ProviderResourcesView.swift](../Sources/DarkbloomMonitor/Dashboard/ProviderResourcesView.swift)
starts/stops its own CPU sampler from dashboard visibility and still stops on
removal. Its cancellable visibility task checks cancellation before acting.
[SystemCPUUsageStore.swift](../Sources/DarkbloomMonitor/SystemCPUUsageStore.swift)
also checks cancellation before the first read and after each sleep. A dedicated
red test demonstrated an unwanted initial read when start was cancelled before
its queued task began; the guards now prevent it. The resource panel lifecycle
test checks hidden startup, visible measurements, hidden stability, restoration
with new counters, and removal. GPU sampling remains the shared app sampler;
this change does not stop that sampler or label whole-Mac CPU as Bloomy CPU.

## Native expiry proof and fixture limits

Native 18 was an isolated AppKit fixture with synthetic API/credential data and
CPU/GPU/power acquisition disabled. No real provider start, inference, model
swap/download, credential read/write, or policy mutation was needed. Its
verification controls supply an initial snapshot aged 110 seconds, an already
expired snapshot, a fixed failure, or an empty list. There is no fixture expiry
timer or repeated Chat publication: the production store deadline drives expiry.
The production Refresh button uses the controlled synthetic client.

Root native review observed a fresh banner and populated composer before the
ten-second remaining deadline, then an expired banner and disabled Send with
the exact same typed draft. Manual Refresh
retained another typed draft, `Keep this draft when the check expires.`, and
restored Send. No Send was clicked. Native 18 was cleanly quit and its process
absence was checked.

The Next verification read control in native 18 read a nested Chat store through
its parent fixture model without observing that child; after store replacement
it could remain disabled. The fixture-only control now directly observes the
child in a separate helper view. This is test-host fidelity work, not evidence
that production Refresh was disabled. Native 19 confirmed the control re-enables
after a read. In compact light appearance, a failed Refresh and a repeated failed
retry retained `Keep this draft through failed and empty checks.` with Send
disabled. Choosing a fresh next read and pressing production Refresh restored
Send with that draft unchanged. An empty read disabled Send, retained the draft,
and displayed the verified-empty banner. The empty state also fit the wide dark
window. No Send was clicked.

Native 19 exposed duplicated failure wording. The production label now displays
the fixed failure notice once, followed by the disabled-send fact. Native 20
confirmed the corrected compact light banner and available Refresh action. A new
ten-second expiry case showed a fresh list and enabled Send after typing
`Restore this draft after expiry.`; the later accessibility/screenshot observation
showed the expired banner, disabled Send and unchanged text.

The Window > Minimize action was invoked, but subsequent window/menu automation
timed out. Cached window captures and popup navigation do not prove that native
minimize/restore completed correctly. That check remains pending; neither a
shortcut attempt nor the popup's Open dashboard action is counted as a passed
restore test in this checkpoint. Subsequent native 22 review repaired the
fixture's popup presentation route and recorded actual native window flags,
same-window restoration, and exact draft recovery; see
[Hosting and history recovery review](HOSTING_HISTORY_RECOVERY_REVIEW_20261002.md).
The optional native launch API was unavailable in this Mac CUA
session. The automated ownership/lifecycle tests remain separate evidence.

Artifacts are retained locally in `/tmp/bloomy-efficiency-20261001/` and are not
distribution assets. `native18-fixture-manifest.json` records 77 source hashes,
substitutions, compiler invocation, linked library hash, and binary SHA-256:
`fe7120d4e47e9afcf16afedb41f89173bae1b4610b22f2fda2fd7deb2333bef4`.
The retained executable matches that hash. Its manifest predates the later CPU
cancellation guard and fixture helper repair; `SystemCPUUsageStore.swift` and
`DashboardFixture.swift` differ from native 18, and the final failure-label wording
also postdates native 18/19. Those builds prove only the stated interactions at
their recorded source identity. Final native 20 matches all 77 recorded current
source hashes, with binary SHA-256
`d931fb8d22af3065cff1728a17d24eba40e8235cac31bd8c3c998e08059ca4f9`
and linked telemetry library SHA-256
`64f14e507ddee718f08e506edb3bbefa84fa5948470ef13c5153cf88199bdd30`.
Its manifest is `native20-fixture-manifest.json`; the executable hash was checked
against the manifest before launch. Native 19's binary hash is
`02d030313e8027a32e67f75ec17812898ecdb96c2e18f1869f3b7003fa182d7a`.

## Verification and retained failed attempts

| Artifact under the local evidence directory | Result |
| --- | --- |
| `chat-expiry-clock-focused-tests-04.log` | 67 tests in 7 suites passed in 4.571 s. |
| **`chat-expiry-clock-full-tests-03.log`** | **Terminal records confirm 1,147 app/telemetry tests in 152 suites (24.279 s), 21 companion tests in 5 suites (0.015 s), and 28 host tests in 9 suites (11.630 s): 1,196 total passed.** |
| `chat-store-replacement-regression-before.log` | Before the identity correction, both old/new deadline-ownership assertions failed. |
| `cpu-queued-cancellation-before.log` | Before the cancellation guard, the initial-read assertion failed; one undesired read was observed. |
| `native18-chat-expiry-build.log` | Native 18 compiled; its binary identity was rechecked as above. |
| `native19-chat-expiry-build.log` | Terminal compilation passed; failure/empty/manual recovery checks above. |
| `native20-chat-expiry-build.log` | Terminal compilation passed; final source identity and corrected wording checked above. |
| `chat-expiry-wording-tests.log` | After the final label-only change, 50 Chat tests in 2 suites passed in 3.782 s. The 1,196-test run preceded only this wording correction. |
| `chat-expiry-visibility-release-build-02.log` | Final-source release compilation passed in 46.41 s. |

The first focused log (`chat-expiry-clock-focused-tests.log`) failed to compile
because a Swift Testing macro wrapped a mutating iterator expression. The next
(`chat-expiry-clock-focused-tests-02.log`) used nonexistent test fixture member
`TelemetrySnapshot.empty`. Both test-only issues were repaired before passing
runs. They are retained diagnostics, not production failures.

The first full run (`chat-expiry-clock-full-tests.log`) exposed a fixed 150 ms
pop-out visibility wait under parallel actor load. The test now waits for the
actual ownership condition. A subsequent run
(`chat-expiry-clock-final-full-tests.log`) exposed the CPU cancellation race
and a fan subscriber test that assumed a 30 ms check completed within its 120 ms
poll interval under full-suite contention. The CPU race received the guard and
dedicated red test. The fan test now blocks a controlled in-flight client read,
proves subscribers/background refresh share it, joins the cancelled observers,
then checks that no orphan polling continues. It retains the meaningful sharing
and cancellation assertions instead of relying on a fragile exact count while
an active periodic task is running.

## Remaining proof and release boundaries

- [x] Subsequent native 22 Chat minimize/restore proof is recorded in
  [Hosting and history recovery review](HOSTING_HISTORY_RECOVERY_REVIEW_20261002.md).
- [ ] Full route/appearance/size/source-state native matrix, actual VoiceOver,
  controlled Reduce Motion, and comparable current production CPU/energy and
  allocation measurements.
- [ ] Production external Sol cache permission boundary and required native
  release checks. Scoped removable-drive privacy reset remains pending human
  approval; no privacy/drive/Keychain workaround is authorized.

Production v1.9.15/build 140 remains the original PID 31677, started October 1
at 22:40:57; its binary SHA-256 is
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Its process and user state were preserved. Current CLI status reports
`Daemon: not running (stale state file)` and watchdog installed but not loaded;
the launch service list contains no provider/recovery service. Real
`~/.config/darkbloom/provider.toml` SHA-256 remains
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
Native 19/20 were quit through the fixture popup; their process absence was
checked. The provider and recovery watcher remain deliberately stopped for
Kevin's other work; this checkpoint needed no temporary start. These results are
separate from signing, notarization, updater installation/relaunch, and
publication. Follow [RELEASING.md](RELEASING.md) and retain the unresolved gates.
