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
