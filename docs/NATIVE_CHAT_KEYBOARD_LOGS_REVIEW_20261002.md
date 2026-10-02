# Chat keyboard focus and stable Logs — October 2, 2026

This checkpoint continues the [native polish plan](APP_POLISH_OPTIMIZATION_PLAN.md).
The [completion matrix](NATIVE_COMPLETION_MATRIX_20261002.md) distinguishes
bounded evidence from the full goal. Production Bloomy and its unsaved work are
preserved; all interactions below use isolated synthetic review clients.

## Native 64 baseline keyboard review

The committed Native 64 fixture was reopened with a fresh isolated runtime at
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-3E13C9C8-31F1-42BA-BE48-5A2C8F685ABF/`.
Its manifest and product identity are documented in
[the previous review](SETTINGS_LOGS_VISIBILITY_REVIEW_20261002.md). The dashboard
used compact 800 × 560 Light appearance and an opt-in bounded native focus
trace. No actual endpoint, inference, API key, clipboard write, or OS setting
change occurred.

- New Chat: the native sheet was raised through its exposed action. Tab/Space
  selected the paid route and opened its confirmation; Shift-Tab from Cancel
  reached Back, Space returned to the choices, and Escape dismissed the sheet
  without creating a conversation. A new sheet's default Local choice then
  created the explicit local conversation.
- Composer: Control-Tab reached Send, Shift-Tab returned to the editor, and
  Command-Return sent the selected synthetic model while preserving editor
  focus. Control-Shift-Tab reached Refresh. After verification expired, Space
  refreshed the route without clearing the unsent draft. Shift-Tab reached the
  model picker; Space/Down/Return selected Gemma, retaining the draft and full
  model identity. Command-Return while the picker was focused sent with Gemma
  provenance and retained picker focus.
- Cancel: a controlled 30-second held reply exposed the real Cancel control.
  Control-Tab/Space stopped the send and kept the honest maybe-delivered notice.
  A later Control-Tab batch reached the sidebar rather than Cancel, so its final
  Fans selection alone is not counted as cancellation proof.

A fresh Native 64 runtime at
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-E8189B23-7C6E-460A-BDDD-C541223F52A9/`
isolated the exact control. AX pressing Cancel and immediately typing retained
the composer because the press did not move focus out of the editor. In the
decisive keyboard case, Control-Tab was observed focused on the native Cancel
button; the uninterrupted Space → type `After keyboard Cancel` batch selected
Action History through sidebar type selection. Returning to Chat verified the
second assistant's Cancelled phase, maybe-delivered notice and empty composer.
Thus cancellation really occurred before typing, and focus loss depends on the
removed Cancel having keyboard focus. No observation separated Space and typing.

An earlier attempted reproduction outlasted the reply hold and completed
normally; another attempt hit expired model verification. Neither is counted
as Cancel evidence. Computer-use observations can reopen/refocus this fixture,
so the uninterrupted action sequence is necessary to separate that observer
effect from the confirmed focus loss.

## Changes

Chat binds its existing native message editor to a local SwiftUI focus state.
Only that view's explicit Cancel action requests composer focus after a send
actually stops, with the same conversation and a visible surface. Disappearance
or hidden visibility clears the local request. Shared-store cancellation,
normal completion, failure, and another window do not trigger that action.

The native fixture now seeds 48 immutable Logs payloads once per prepared
scenario. Five-second source publications retain those identities while capture
times advance. An explicit inert action prepends one unique Notice event,
preserving existing rows within the 100-event bound. Publications join their
predecessor before reading the retained feed, and generation/termination checks
prevent obsolete work from publishing into replacement stores. Quit joins the
publication tail. Independent read-only review found no actionable ordering,
generation, retention, or cleanup issue.

## Candidate native keyboard and Logs review

Native 65 compiled successfully with 89 source hashes matching before launch.
Its manifest is `.build/native-dashboard-fixture-20261002-65/fixture-manifest.json`,
SHA-256 `eb3115bd996a3aa15a20f4b2e88e9e27aec4f1a46d30c998aae822f73283f1aa`;
binary SHA-256 `c51ef8f4aef1b6ed637f5f04b1f1726a1b8fb34fe562580c0c09b67d50581c58`.
Runtime:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-DB409214-9C27-4F96-9743-2EF4556D060B/`.

- Compact Light dashboard: Command-Return started the controlled held response;
  Control-Tab was observed focused on the actual Cancel button. The uninterrupted
  Space → type `Candidate follow-up stays here` batch cancelled the response,
  retained Chat sidebar selection, and left that exact draft in the focused
  native message editor. The Cancelled phase and delivery warning remained.
- Dark 460 × 520 pop-out: the same sequence put `Pop-out follow-up` in its own
  focused composer. Returning through the native Window menu showed the
  dashboard's unchanged `Candidate follow-up stays here` draft and shared
  cancelled transcript. Command-W did not establish close/reopen proof here;
  the Window menu was the verified return path.
- Normal completion: Control-Shift-Tab reached Refresh and Shift-Tab reached
  the model picker, whose focused AX value exposed `qwen3.8-27b`. Command-Return
  sent an immediate synthetic response and left that picker focused. An AX
  picker press alone did not establish keyboard focus and is not substituted
  for this check.
- Compact Dark Logs: a selected Legacy warning retained the full payload and
  exact timestamp `2026-10-02 17:26:35 UTC` while capture time advanced from
  `17:32:25` to `17:33:59 UTC`, across ordinary five-second source publications.
  Native page Scroll Down reached the complete details card; wheel input over
  the table scrolled the table instead and is not outer-page proof.
- Prepending `Synthetic log arrival 1` kept that warning selected and unchanged.
  In Light appearance, `delayed` retained its selected details. The excluding
  `arrival` filter removed the old details and showed the selection guidance.
  Clearing the query placed the new Notice first, before the original warning
  and unchanged older rows. This closes the bounded sustained-selection gap
  left by the older timestamp-regenerating fixture. It does not establish live
  collection, source occurrence identity, retention at the cap, locale changes,
  or every export/window state.

## Finite native focus regression and rejected attempts

`ChatComposerFocusProof` uses two actual owned Chat views with a shared inert
store under normal `NSApplication.run()`. Its first case requires exactly one
native Cancel AXButton reporting real accessibility focus, a real responder
inside the owned host, and the correct native key window. SwiftUI's responder
was `KeyViewProxy`; the actual getter was `isAccessibilityFocused`. The helper
presses that real control and requires the same existing native NSTextView,
the exact follow-up draft, and the independent other draft. Three further
cases check the native key window and sentinel responders through publication.
It generates no OS keyboard events; the direct keyboard checks above remain
separate evidence.

Native 65's first attempt and Raise-only retry failed all key-window prerequisites
and passed owned cleanup. Their preserved JSON files are
`/tmp/bloomy-efficiency-20261001/chat-focus-native65-background-failed.json` and
`chat-focus-native65-raised-failed.json`. These are not accepted focus proof.
The corrected helper records bounded application/window context and safely
handles completion cancellation before and after continuation registration;
terminal shutdown rejects queued late calls. Native 66 failed compilation
because the diagnostic used Objective-C's `canBecomeKeyWindow` spelling; root
corrected the Swift property to `canBecomeKey`, preserving the failed build log.

Native 67 compiled successfully and its 89 source hashes matched the tree.
Root used native Window → Show Dashboard, whose existing command activates the
fixture, before starting the helper. Recorded `NSApp.isActive` was true, with
owned key windows 18699 and 18700. The strict gates were retained.

| Native 67 case | Result |
| --- | --- |
| Keyboard-loop-focused Cancel restores the same composer and independent drafts | Passed |
| Cancel in the other owned view preserves the key window and its sentinel | Passed |
| Normal completion preserves both sentinel responders and the key window | Passed |
| Direct store cancellation preserves both sentinel responders and the key window | Passed |
| Held calls finish, send task context releases, owned windows/hosts/deadline clean up | Passed |

The helper tracks the inherited task context through a weak task-local token,
in addition to the fake completion count. It does not equate releasing a
continuation with joining the send. Terminal success requires all four cases,
no failures and cleanup; the returned menu subsequently said “Chat focus proof
passed”. Retained successful JSON:
`/tmp/bloomy-efficiency-20261001/chat-focus-native67-passed.json`, SHA-256
`441f96738a7a3299b24479b5db0c393d671e0e70ac99788f461a3ae1605946cf`.

Native 67 manifest: `.build/native-dashboard-fixture-20261002-67/fixture-manifest.json`,
SHA-256 `5da12201449f0bda33127f151a564e0cad0d3904f6b762fb50ddfda27a795f46`;
binary SHA-256 `dc9cd2ccc9ef78cb4ebfdb186652bb731ae8abfeecc5c3f8c32f72af5e2a4e19`.
Runtime:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-CC959CAD-676F-4DF0-81E5-EF84E0FFA836/`.

An immediate reselect-proof → Command-Q attempt exited the app but left the
previous successful JSON unchanged. It establishes normal app exit only;
cancellation during an actually running helper is not claimed. Native 64 and
65 also exited through their normal fixture Quit path. Final process inspection
found no task-owned DashboardFixture executable.

## Test/build verification and limits

Actual VoiceOver remains pending the unanswered scoped desktop-setting question;
it was not enabled. The full route/appearance/size matrix, production relaunch,
provider recovery, updater installation and distribution remain open.

Focused Chat tests: 60 tests in four suites passed. The complete suite passed
1,319 app/telemetry tests in 178 suites, 21 protocol tests in five suites and
28 host tests in nine suites: 1,368 total. Release compilation completed in
40.61 seconds. Logs and store cancellation regressions remain included in the
full suite. Logs are not claimed covered by a filter that matched only Chat.

Evidence logs: `/tmp/bloomy-efficiency-20261001/chat-focus-logs-focused-01.log`,
`chat-focus-full-01.log`, and `chat-focus-release-01.log`; all finite commands
returned exit 0.

Independent product review found no actionable focus/lifecycle issue. Helper
review identified the pre-registration cancellation race, corrected before the
successful Native 67 run. No focus action is attached to shared store changes.
Production PID 31677 retains its October 1 22:40:57 launch and unchanged binary
SHA-256 `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Provider and watchdog were verified unloaded, with service queries exiting 113
and “Could not find service”; no provider change was needed for this review.

## Bounded performance preflight: no production change

An independent release-optimized runner measured the actual current model
presentation cache with unchanged qualified telemetry versus changes only to
the qualification period endpoint. Seven models measured 1.049 / 8.886 µs per
prepare; the 100-model stress case measured 8.055 / 108.210 µs. All latest-period,
grade/grouping/demand, alias precedence, failure, expiry and restoration parity
checks passed. Rebuilds occur, but the small measured cost does not justify
another production cache rewrite.

This excludes telemetry mapping, filtering, publication, SwiftUI rendering and
whole-app CPU/energy. The finite compiler and runner exited 0; retained source,
results and provenance are under
`/tmp/bloomy-efficiency-20261001/model-grade-period-preflight/`. Recorded production
source hashes were rechecked against the working tree. The initial incompatible
Swift 6.3.3 module attempt is retained as a failed diagnostic; the successful
runner used the current `.build/out/Products/Debug` Swift 6.4 module/archive.

## Separate provider boundary

The scoped removable-drive reset already succeeded, but saved-settings managed
startup failed and its service/recovery watcher were stopped. The
[sanitized diagnostic](PROVIDER_CACHE_STARTUP_DIAGNOSTIC_20261002.md) remains
unsent. Both LaunchAgents point at the same compiled arm64 executable; its
bundle contains no readable implementation source to trace the different cache
enumeration paths. Successful shell scanning does not establish managed launch
access or prove a privacy cause. No second reset or broader permission was made.
