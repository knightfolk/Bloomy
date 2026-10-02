# Hosting and Models keyboard review — October 2, 2026

Bounded progress in the [active polish plan](APP_POLISH_OPTIMIZATION_PLAN.md).
The complete route, accessibility, motion, production and distribution gates
remain open. Root performed native computer-use checks in isolated AppKit apps;
two workers implemented independent fixes and two provided read-only cross
reviews. No real provider model, network listener, credential or inference
operation was used to prove these editors.

## Repairs and regression evidence

- Choosing One LAN / tailnet address with no detected addresses previously
  returned before showing its editor or error, because both were conditional
  on a saved specific-interface selection. A transient selection attempt now
  reveals the editor and an explicit no-address notice while preserving the
  actual saved binding. Selecting loopback hides the transient editor without
  destroying a partially entered address. The existing active-interface Apply
  guard and network confirmation remain in place.
- Controlled Hosting tests cover saved loopback/all-interface settings,
  untouched persistence and invalid port/address drafts, recovery after a
  scanner publishes an active address, explicit selection of that address,
  cancellation of the transient choice, and saved specific-interface editing.
- A captured startup-picker option could previously outlive its catalog identity
  and stage a raw alias that now identified another model. The callback now
  checks the current enabled selection, current canonical identity and current
  downloaded inventory before staging. No-op choices compare canonical identity
  without normalizing the user's raw alias. Explicit Clear still uses the live
  draft rather than the menu's old preload count.
- Controlled provider-store tests reject refreshed exact-ID shadowing,
  ambiguous/removed/disabled options and preserve the complete later draft.
  Fresh explicit choices remain possible. Late no-op, Clear and change-back
  callbacks are separately covered; no controller mutation is performed.
- Expanding Manage Details in compact light could crash during accessibility
  label resolution. Reordering the canonical ID's label passed one pilot but
  failed after the footer layout changed. The final candidate separates the
  plain Canonical model ID caption from the selectable ID, preserving context,
  text selection and help without a custom label on selectable text.
- Native testing subsequently found the bottom Done button could receive Tab
  focus outside the viewport. Its footer now remains outside the scrolling
  content, within the same screen/host sheet budget. Header Done and Escape
  remain available; model/draft/save semantics are unchanged.

## Native 71–73 observations

Native71 reused the exact earlier candidate in a fresh session
`A9E20F2D-6C1C-421A-BABD-910FD808B489`. Compact dark Provider scrolling reached
profit controls and the full Nudge guide. Increment/decrement actions changed
only fixture preferences (confirmation 10 to 15 minutes; return interval 180
to 150 minutes). Secure input, disabled Save and all setup steps remained
reachable. No key or automatic action was enabled. This does not establish a
complete lower-control keyboard loop.

Native72, session `527601F2-E422-4BE3-AF51-6CABA5947032`, contains the new
no-address fixture scenario but predates both production fixes. In wide light,
pressing One LAN / tailnet address produced no editor, notice or AX change;
loopback stayed selected. This reproduced the Hosting bug. Wide dark mode cards
and Models neighbors aligned. Keyboard search → Refresh → Enabled → Available
→ Capacity traversal and Space disclosure changes worked; Use 1 slot staged
only an inert draft. Nothing was saved or applied.

Native73, session `8F65F02F-CD78-4EC3-B600-7AA9F30373F6`, contains both editor
fixes, before the later canonical-label and footer changes:

- Wide light / compact dark no-address Hosting displayed its notice and custom
  editor while preserving loopback. The notice wrapped without clipping.
- Keyboard entry of `192.168.1.` and Tab/Space on Use address displayed the full
  validation error and retained the partial input. Refresh preserved it. Wide
  dark mode cards aligned. Returning to loopback hid the editor; explicit
  Discard cleared the input warning.
- With a fresh detected address, selecting LAN staged `192.168.50.20` and showed
  network confirmation. Cancel/Space and reopening followed by Escape dismissed
  confirmation and retained the staged choice. The positive Allow action was
  not invoked. AX exposed the question/buttons, but the sheet screenshot was
  blank; confirmation-dialog visual acceptance remains open.
- Final wide dark Models cards and compact light single-column cards fit.
  Keyboard Enabled/Available/Capacity disclosure traversal worked. The one-slot
  alias picker showed GPT-OSS selected: reselecting it kept Save disabled; an
  explicit Gemma choice staged a change; keyboard Discard restored GPT-OSS and
  disabled Save. No Save or Apply Live action was performed.
- Keyboard Manage opened the light sheet and reached Details, but expansion
  plus AX inspection terminated the app. Crash report
  `DashboardFixture-2026-10-02-115536.ips` records PID34236, capture 11:55:17,
  `EXC_BAD_ACCESS/SIGSEGV`, stack exhaustion and repeated SwiftUI/AppKit
  accessibility-label resolution. The crash is not accepted native proof.

A subsequent observation automatically launched a fresh Native73 session,
`6F97E78B-15D1-4C10-9753-AE7F07C3A918`, PID44629. Pointer expansion with header
Done focused succeeded. Both earlier sessions were absent after interruption.
Later explicit baseline sessions established a narrower reproducible condition:

- `22CD5274-35EF-4396-B1B4-86C4E7E0DC42`, PID83916: Fresh/wide light keyboard
  expansion, re-expansion and native scrolling succeeded; normal Quit followed.
- `A78E36EB-0CD2-438C-AF47-5EEB0A521178`, PID87645: Aliased startup / compact
  light, search → five Tab presses → Manage/Space → four Tab presses →
  Details/Space → AX/screenshot reproduced termination. Report
  `DashboardFixture-2026-10-02-145115.ips`, capture 14:51:14, repeats the same
  stack-exhaustion signature. Process absence was checked before any relaunch.

The stack cannot identify the exact accessibility node. Source comparison and
controlled native candidates guide the selectable-text repair; they do not
establish a general SwiftUI framework diagnosis.

## Native74 label-order pilot

Session `6CFD7C41-49F8-4A7E-8ED7-325E6D702DB5` repeated the failing Aliased
startup / compact light keyboard path with only the label order changed. Details
expanded, exposed the full canonical ID and showed its selectable text, RAM,
download, capability and freshness-qualified demand/pricing. Collapse/re-expand
and AX inspection succeeded. Tab reached footer Done, but its focus was below
the visible viewport; Page Down did not reveal it. Native Scroll Down exposed
the focused button and Space closed the sheet. This separately motivated the
fixed footer. The pilot quit normally; it is not the final footer candidate.

## Rejected Native75 footer candidate

Session `C5A8ABFA-09ED-48E3-8AF7-0A624B920DEF` showed the fixed footer correctly
in compact light, but repeating keyboard Details expansion crashed again.
Report `DashboardFixture-2026-10-02-145901.ips`, PID2012, capture14:59:00,
has the same recursive-label stack exhaustion. Process absence was verified.
This disproves label reordering as a sufficient repair; Native75 is rejected.
The next candidate changes only the canonical-ID component to a plain caption
plus selectable text, retaining the fixed footer.

## Final candidate and verification

Native76 session `3AAD46F2-6579-44AE-AA15-4DA597BE5C0F` repeated the original
compact light / Aliased startup keyboard route. Details expanded without
termination; repeated collapse/expansion and AX inspection exposed the full
canonical ID and qualified demand/pricing. Tab focused the footer Done with a
visible focus outline, without scrolling. Native Scroll Down reached every
Details row. Triple-click selected exactly `gemma-4-26b-qat-4bit`, visibly and
in AX. Pointer Done closed that selected-text state.

The dark 740-point sheet opened and Escape from header-control focus closed it.
With the fixture's explicit 360-point host budget, the dark sheet remained
620 × 360 with Done visible outside the scrolling viewport. Native scrolling
reached the lower controls and expanded Details, including the canonical ID,
complete metadata and stale network wording. Escape from slider focus closed
the constrained sheet. This is bounded native scrolling/close proof, not a
complete Tab loop: offscreen controls were not automatically revealed by Tab,
and Escape while the canonical text was selected did not dismiss the light
sheet. Those focus/selected-text boundaries remain follow-up work.

All six manifests identify 89 original source hashes and the exact three inert
substitutions. Native76's hashes matched current source before launch and after
normal Quit; its process was absent afterward. Native74 quit normally; Native75
terminated in the rejected crash. App screenshots and AX were inspected in this
conversation. The retained task-owned snapshots are
`.build/native-dashboard-fixture-20261002-71` through `-76`:

| Native | Manifest SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| 71 | `d89fd127fed9157a88015f2d1045bd1ee5595d9a4af13a3cca1e7bebb3c6b5f6` | `45697bc295ae2c4dd1615d170dff7b5946bce24d71ad5bd9cf09ee26ed707cd3` |
| 72 | `d5456f690d2e5a5e19141c779b6c6b0b4e22f21fb73ae55290c16985bcf6922e` | `8eaedfa643f860f13081d87e3a784f551b6b693bc02f121c0457f5d0f962ce07` |
| 73 | `9d7086ad44758403b1835fc298be0ad0109b415a8b39e50bf6366826363a519f` | `15514f819e892ccd2859678c9909a33cd7e552660f8b2970942a982baffc9d89` |
| 74 | `b2cecab36fa84170be0f2e5e47713bad58d165677748c7f5aa2973340b35b916` | `8b759843d99fcd7f0618f9a3585fa7d5d4f5d7d383145e113f25ffa0acbdec2c` |
| 75 rejected | `6897a9b0f0d39278f7174f1ae7853b14feb8121ff8f92aea26ed5a3cb83293a1` | `30bb7affee5946740a848590a5e82ef9987a50d752dff92cca8b12cda531bfd7` |
| 76 final | `e8ed199bba107a1910445a7703189c3d4fd78060711245f63fb8a72e31b800fa` | `bf8534d54b507583f8f121a82e1e0e21d7232c9478db7628e92fc8257324f5ef` |

Final full tests passed: **1,336 app/telemetry tests in178 suites**, **21 protocol
tests in5 suites**, and **28 companion-host tests in9 suites**: **1,385 total**.
The final release compile joined with exit0 in40.71 seconds. Earlier focused
regressions passed54 cases in4 suites. Logs remain in
`/tmp/bloomy-hosting-startup-20261002/{full-04,release-04,focused-03,native-76}.log`.
The focused pass predates the final separate-caption change; the full pass and
release compile include it. Whitespace checks passed. No distribution claim
follows from these local checks.

## Running-app temperature question

The installed app was inspected read-only at v1.9.15/build140, PID61760 (launch
12:55:28). Its Fans page readings changed from 78.2°C to 85.7°C. A separate
read-only official `fan status --json` command exited zero at 14:49:26 and
reported hottest GPU temperature 82.03125°C, with actual fans 7837/7819 RPM and
reported maximum 7826 RPM. These samples have different timestamps; they are
not an exact simultaneous sensor comparison or proof of menu-bar color.

Both release source `0c5abb7` and current source use display boundaries 70/85°C:
green below 70, yellow from 70 to below 85, red 85 and above, neutral without fresh
valid temperature. The thermometer ring fills by the highest measured actual
RPM / reported maximum RPM fraction, clamped to 100%; it does not fill by °C or
by the configured target. The GPU ring shows whole-Mac GPU utilization. The
model ring uses temperature color and animates only for fresh online inference.
These color boundaries are Bloomy presentation choices, not Apple's hardware
safety limits. Normal background fan reads occur every 30 seconds; a visible
Fans/Cooling surface shares a 2-second cadence. The user's exact color/reading
mismatch is still awaiting clarification; no cadence or threshold was changed.

Current afternoon read-only service checks found the provider PID67163 and
watchdog PID67169 running. Their resumption occurred outside these fixture
checks. Root did not restart, swap, nudge, stop or reconfigure them, and did not
reset any additional privacy permission. The earlier cache-start failure remains
historical evidence; these observations do not establish its cause or repair.

## Limits

Actual VoiceOver remains unverified and its desktop-setting question unanswered.
Native alias-reassignment callbacks, rendered missing/ambiguous inventory,
positive network confirmation, clipboard failure, complete keyboard scrolling,
other displays, sustained production profiling, updater installation and signed
distribution remain open. The fixture contains production views, three inert
dependency substitutions, synthetic data and isolated preferences. CPU/GPU
collectors are off; local Mac identity and system thermal state are actual,
while numerical temperature/fan samples in fixtures are synthetic. Production
unsaved work and unrelated files were preserved. Installed binary SHA-256 remains
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
