# Model editor keyboard review — October 2, 2026

The ongoing goal covers every native route and state. This checkpoint addresses
the previously recorded Manage-sheet keyboard boundaries; it does not close the
broader accessibility, production-profiling or distribution matrix.

## Baseline and diagnosis

The unchanged Native79 executable was launched in a new isolated session,
`D8FED9BC-E836-4C1E-B3F9-0BDABDE288AF`. At the 360-point sheet limit in compact
dark appearance, Tab from header Done reached footer Done, then the runtime
slider. Accessibility identified that slider as focused, but the screenshot
still showed the top metrics and the slider was below the viewport. This
reproduces hidden focus independently of the earlier selected-text issue.

Native80 (`EB880F65-DDBD-491B-BA8C-B0944C64C420`) adds sheet-only SwiftUI focus
bindings and a ScrollViewReader callback. The same key path visibly scrolls to
the slider. With the default minimal scroll anchor its focus ring lies close to
the clip edge; the final candidate uses a centered anchor for breathing room.
Compact cards do not install the callback or register these focus bindings.
There is no recurring clock. The focus callback is installed only inside the
presented Manage sheet.

The pilot also reproduced the second boundary: Details was expanded, its full
canonical ID selected, and Escape left the sheet and selection unchanged.
Native82 established that SwiftUI's `onExitCommand` also fails to close the
sheet from selected text. That candidate was rejected. The final implementation
installs a local AppKit key listener only while the Manage sheet is mounted.
It handles plain Escape only for its own key window, leaves marked-text
composition and modified Escape alone, ignores nested sheets, and removes the
listener when detached or dismantled. The listener neither polls nor observes
other applications' events.

Both baseline and pilot were closed normally, with process absence checked.
Their preserved manifests remain distinct from the subsequent candidate.

## Native alert investigation

A read-only reviewer compared fixture and production NSHostingController/window
policy and the native Autopilot/Hosting modifiers. Ordinary consent and Models
sheets render in the same host; native alerts/dialogs expose correct accessible
content and working actions while CUA's target screenshot returns blank.
No custom dialog sizing, opacity or color is applied. This does not establish
an application rendering failure. The current computer-use API has no separate
composed-screen capture for comparison, so rendered alert acceptance remains
open. Native confirmations are retained rather than replaced to accommodate an
unproven capture failure.

## Final evidence

The final production source passed **1,417 tests**: 1,368 app/telemetry tests in
180 suites, 21 protocol tests and 28 companion-host tests. `swift test` exited 0;
the three test runs took 16.739s, 0.012s and 11.634s. Release compilation exited
0 in 40.34s. Logs are `/tmp/bloomy-model-keyboard-20261002/full-03.log` and
`release-02.log`. The earlier `full-02` compilation rejected returning AppKit's
non-Sendable event through actor isolation; the final handler isolates only
the Boolean decision and returns the original event outside that closure.

**Native83**, session `45B311EA-7AE9-4094-9073-A315A67F3818`, checked the final
production views at 620 × 360 in compact dark appearance with actual keyboard
input:

- Tab from header Done reaches footer Done, then the runtime slider. The slider
  scrolls into the middle of the viewport with a visible focus ring.
- Further Tab reaches Enabled, Load at startup, and Details; each is visible.
  Shift-Tab reverses through both switches to the centered slider.
- Space expands Details. Native selection exposes the exact canonical model ID
  `gemma-4-26b-qat-4bit`; plain Escape now closes the sheet. Reopening, selecting
  the same ID and pressing Shift-Escape retains the sheet and selection; plain
  Escape closes it again. These actions do not stage provider edits.

The finite helper's initial candidates were rejected independently of that
actual-key proof. Native81's owned host shrank after attaching its controller;
its final setup explicitly restores the host size. Native82's ownership
diagnosis omitted the native sheet responder chain. Native83 recorded actual
AX focus and valid proxy-to-sheet ownership, but no key-window activation, so
all three assertions failed and cleanup passed. Those failures were not counted
as accepted keyboard proof.

**Native84**, session `989493A3-223E-455D-BD99-C0F3EDE2A14B`, includes the final
finite helper with bounded application/owned-window activation and unchanged
focus/visibility assertions. A background-only first run failed activation,
cleaned up, and was preserved as `keyboard-proof-background-rejected.json`.
After real Tab input activated the fixture, the same helper passed **3/3**:
forward and backward traversal each observed header, footer, runtime, Enabled,
Preload and Details; each direction moved the actual scroll viewport, and footer
Done closed the sheet. Exact native AX focus, key-window identity, responder
ownership and full control-frame containment were checked. Preferences and
provider drafts stayed unchanged; there was one synthetic refresh and no
controller mutation. Owned window/sheet/host/store cleanup passed.

The helper is limited to 45 seconds plus bounded cleanup, reports every failure,
and does not skip required controls. Its NSWindow key loop is complementary to
the actual Tab/Shift-Tab observations above; neither establishes VoiceOver.
The success report is retained at
`.build/native-dashboard-fixture-20261002-84/keyboard-proof-success.json`, SHA-256
`a69327e727f6d6030df14d92d87486e37538160b4054f7a204058ff95cf88a28`.

Native84 also rechecked Settings → Provider → Enable Autopilot: the optional
entry opens the readable native consent sheet without a terminal selector.
Escape cancels and retains Off. The earlier Native79 inert enrollment and policy
action evidence remains separate from this entry-point recheck.

Preserved manifests: `.build/native-dashboard-fixture-20261002-83/` and `-84/`.
All 92 Native84 source hashes match the checkout. Native83's only later source
difference is its rejected helper; all production views match Native84. The
Native84 executable SHA-256 is
`12329b149482d59cc4089973c441fd2d3a3dc85227117c1a1335ff16a73d2fdc`;
Native83 is `8708b1a00fe694fa2f7cbf999a024a19f3f8de6c997020e350c03129dc6b5b50`.
Both link telemetry library
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`
and use only the builder's documented three inert substitutions.

The installed app and real provider remained protected; no real model/provider
actions, privacy changes, or credential reads were needed. Production PID
61760, provider 67163 and watchdog 67169 retained their launch times, and the
installed executable hash remains
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
A read-only production review found no actionable defect in focus scope or
listener lifecycle. Its composition guard recognizes `NSTextView`; the current
Manage sheet has no editable input. This source review does not establish real
input-method or nested-dialog behavior. Native83 and Native84 were quit normally;
their processes were absent afterward. Observing a closed fixture can relaunch
it through the automation binding, so absence was checked without reopening it.

Actual input-method composition, other displays, unavailable/download branches,
full list-card traversal, VoiceOver, rendered native alerts, whole-app profiling
and signed distribution remain open. This checkpoint does not complete the
ongoing goal.
