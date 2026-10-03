# Hosting keyboard reachability — October 2, 2026

This checkpoint repairs offscreen Hosting controls while retaining the existing
cards, adaptive columns, native inputs, operation gates and exposure confirmation.
It does not complete the whole-app polish, accessibility or distribution goals.

## Diagnosis and changes

Native117, the committed baseline, confirms compact Apply can receive native
keyboard focus while the page remains at the top. Its initial traversal also
omits the lazily mounted network choices. Native118 adds focus-entry reveal:
port, authentication and secure input become visible, but network choices only
join reverse traversal after their section has mounted.

The small mode, network and active-address groups now use an eager adaptive
`HostingChoiceLayout`. It mounts every choice at initial layout, preserves the
original minimum widths and spacing, and gives neighboring cards equal row
heights. Tests cover the column boundaries and first-layout mounting below an
80-point viewport for one, two and three columns. No large model list is changed.

`ScrollControlKeyboardReveal` shares the popup's native, noninteractive anchor.
Controls retain their own Tab, Space, typing and arrow handling. The anchor uses
Apple's [minimum-distance scrolling API](https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:))
through enclosing native clips with a six-point ring margin. Popup registration
remains opt-in; unrelated dashboard controls acquire no anchors.

Native119 exposes a second defect: typing invalid port 65536 inserts the Discard
row above the field, pushing the still-focused field offscreen. Native120's
native-frame comparison passes the direct geometry regression but **fails** the
actual typing check. SwiftUI can move an ancestor without updating the anchor's
unchanged focus value. Native121 tracks Hosting control positions in a named
document coordinate space. A position change schedules reveal; manual scrolling
does not change that document position. Popup controls avoid this additional
geometry reader. No polling timer, animation, key interception or provider
mutation is introduced.

## Accepted native observations

Native121 runs after confirmed test-runner exit with inert provider, account,
endpoint and credential dependencies. It uses the final production views.

- Compact light: native Tab reveals the port; typing 65536 now leaves its full
  focus ring and validation message visible after Discard appears. Apply remains
  disabled. Manual native scrolling to the top retains port focus and 65536;
  a later synthetic publication leaves the scroll position at zero.
- Compact dark: appearance switching retains 65536. Reverse traversal reveals
  mode cards and Discard. Space on Discard removes the invalid draft and restores
  the last valid saved port, 6553 (entered as part of typing), with focus moving
  to Fleet only. Space selects Local only without applying or launching it.
  Native traversal reveals all network choices, secure input, local-only
  discovery and Copy Terminal command. The last two have visible full rings;
  the command is not copied or run.
- Wide dark: widening retains command focus. Reverse traversal reaches the
  header Refresh through local-only discovery, secure input, authentication,
  network choices, port and all mode cards. The three mode and network cards
  remain aligned and equally sized within their rows.
- Shared popup regression: dark 80-point fallback, exact-path popup rebind,
  Tab traversal updates both native clips and reveals the electricity shortcut
  with its ring visible. Hosting truthfully shows Selected: Local only alongside
  empty local-only discovery. No real endpoint is checked.

Native119 additionally records compact light mode-card Space selection and
forward/reverse network, secure-field and Apply reveal. Its validation result is
rejected, not accepted as final typing proof. Native118–120 remain preserved.
CUA's immediate AX reads can lag one focus step; final AX/screenshot pairs supply
the accepted focus/frame observations, not exact universal tab counts.

Initial entry from the synthetic banner still lands at Port rather than the
Hosting header. The page-local forward/reverse paths pass, but this does not
prove the real dashboard's complete window-entry order. A banner-free review,
other state-specific paths, enabled token controls, network-confirmation rendering,
actual VoiceOver, other displays and real provider behavior remain open.

## Verification and provenance

- Final `swift test`: 1,394 app/telemetry tests in 185 suites, 21 protocol tests
  and 28 host tests; **1,443 total**. Log:
  `/tmp/bloomy-hosting-keyboard-geometry-final-tests-20261002.log`.
- Final Release compilation: **43.93 seconds**. Log:
  `/tmp/bloomy-hosting-keyboard-geometry-final-release-20261002.log`.
- Native121: `.build/native-dashboard-fixture-20261002-121/Bloomy Dashboard Fixture.app`.
  All 100 source hashes match the inspected source. Its three existing inert
  substitutions are unchanged. Binary SHA-256:
  `41e601ff6b8a92a183f9bd1e35ef8f2ebe90e62163474967073e36b753908a48`.
  Linked telemetry SHA-256:
  `0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
- All owned review windows exit normally. Production remains PID 61760, launched
  October 2 at 12:55:28, with executable SHA-256
  `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
  No production app replacement, provider action, credential write, clipboard
  change, updater install or distribution publication occurs.

## Separate installed-process performance observation

Before opening this review, a 30.16-second CPU-time delta on the preserved
installed **1.9.15/build 140** process measures **8.49% of one core**; observed
RSS ranges from 433,232 to 433,600 KiB. The five-second, ten-millisecond sample
shows the main thread predominantly waiting, with active work including energy
history, uptime SQL and legacy parsing. These are older installed paths, several
already optimized in current source. Window/source activity was not normalized.
This is neither a current-source profile nor a before/after CPU or energy claim.
Evidence remains local in `/tmp/bloomy-installed-performance-window-20261002.json`
and `/tmp/bloomy-installed-performance-sample-20261002.txt`.

## Banner-free window entry and LAN controls

Native122 matches all 100 pre-repair source manifest hashes at `d37d4d7`, with the synthetic review
toolbar omitted and a compact initial window. From the actual Hosting sidebar
selection, native Tab reaches the production toolbar, Hosting Refresh, Fleet
only, Fleet + local, Local only and Port. Further traversal reaches loopback,
LAN and all-interface choices. This supersedes the synthetic-banner entry gap
for this light compact path; it does not prove every window or appearance.

Space selects Fleet + local and then the fake LAN address `192.168.50.20`.
The selected LAN card retains its full visible ring. Traversal includes the
active-address button, custom field, authentication switch, secure field, Copy
URL and Apply, with the focused Apply ring visible at the document bottom.
No URL, token or command is copied, and no real provider is used.

Space on Apply exposes the expected native confirmation to accessibility, with
the address, API-key requirement, HTTP limitation and default-focused Cancel.
Both the initial capture and a fresh exact-path sheet binding return a blank
image. **Confirmation rendering remains unaccepted.** Escape closes it and
restores the visible Apply focus ring without dispatching the operation.

Typing a custom address preserves the field ring after Discard appears. Saving
the syntactically valid but inactive `.21` address shows the expected inactive
address warning and selected URL; this is a saved preference, not an applied
listener. However, Use address becomes disabled while focused. Subsequent
reverse traversal resets to the sidebar; a later Tab/Space opens the toolbar
Nudge sheet instead of continuing through Hosting. This is an open focus defect,
not an accepted address-edit path. The Nudge sheet is dismissed without a key
or request. Re-entering the actual custom field and submitting `invalid-address`
then confirms the inline RFC 1918/Tailscale validation error, retained Use-address
ring and unchanged saved `.21` preference.

Native122 exits normally; the preserved production app remains PID 61760. No
source changes or new tests are introduced by this proof pass. Final source
tests/build above still apply. The next Hosting repair is focus continuity when
saving a custom address; confirmation pixels, other appearances, VoiceOver,
real provider behavior and the broader optimization/distribution work remain open.

## Custom-address save focus repair

Hosting now owns the custom field's native FocusState. After a valid Use-address
save, it returns focus to that field as the save button becomes disabled. The
shared reveal modifier accepts this same binding, so it does not attach competing
focus owners. Other controls retain their original private binding. Invalid
input retains the save-button focus and existing validation behavior; no hosting
operation, exposure check, address policy or credential behavior changes.

Native123 verifies compact light save of fake inactive `192.168.50.21`: the
address field regains its full visible ring and selected text; Shift-Tab reaches
the detected-address choice, and forward traversal skips the disabled save
button and reaches authentication. Selecting Dark through the production
Appearance page preserves the saved value. Dark keyboard traversal reaches the
custom field; saving fake active `.20` removes the inactive warning, selects
that address and restores field focus. Reverse traversal remains in Hosting with
the active-address ring visible. No Apply or inference action is invoked.

All 100 Native123 source hashes match the final production views. Binary SHA-256:
`069b9eb9ff6fed91ea882b61d29480bf2ff4e3b0e00d293f44d1ac138ea38879`.
Linked telemetry SHA-256 remains
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Both Native122 and Native123 are retained and exit normally. Native122 binary:
`cac344c8c7edb36554f07d582390957c196f143b7dd6d5a811cec80297264517`.

The focused precheck passes 44 tests. The added external-focus regression passes
alone. Its initial full-suite fixed-delay assertion misses the revealed frame
(1 issue); a bounded-await recheck also loses native focus (2 issues). Both runs
are rejected. The full suite mounts concurrent AppKit windows that can take the
single native focus owner, so this assertion now runs explicitly in isolation:
`BLOOMY_ISOLATED_FOCUS_PROOF=1 swift test --filter PopupKeyboardRevealTests.editorOwnedFocus`.
It passes 1 test in 0.210 seconds, recorded in
`/tmp/bloomy-hosting-editor-focus-isolated-20261002.log`. The normal suite skips
this focus-specific check; both commands are required and documented in
`Tests/NativeUI/README.md`. Initial failed logs remain
`/tmp/bloomy-hosting-address-final-tests-20261002.log` and
`/tmp/bloomy-hosting-address-final-tests-recheck-20261002.log`.
Final normal-suite verification passes: the runner reports 1,395 app/telemetry
tests in 185 suites, 21 protocol tests and 28 host tests, including the explicitly
skipped focus proof that passed separately. Log:
`/tmp/bloomy-hosting-address-final-tests-isolation-20261002.log`. Release compilation
passes in 41.43 seconds, log `/tmp/bloomy-hosting-address-release-20261002.log`.
Confirmation rendering, actual VoiceOver, real provider behavior, current-source
performance and distribution remain separate open gates.
