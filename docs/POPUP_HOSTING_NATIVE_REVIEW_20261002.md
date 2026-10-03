# Popup hosting connection summary — October 2, 2026

The popup now includes a compact Hosting section above Advertised models. It
shows the saved mode, a qualified local API status, the base URL when available,
API-key requirement and discovery check time. A fresh running provider snapshot
can also supply the coordinator hostname; URL credentials and query data are
never displayed. Hosting opens the existing dashboard destination, and Refresh
reads the existing bounded `darkbloom local --json` discovery client.

Discovery runs on popup opening when the previous check is older than 30 seconds,
and on an explicit Refresh. No new polling timer, inference request, provider
restart, exposure change or credential write is introduced. A report expires
after 30 seconds while the popup stays open, using its existing display timeline.
Fleet + local addresses remain configured/unverified because the CLI's local
discovery record covers local-only mode. Empty discovery never claims that a
Fleet + local listener is stopped. Saved mode and discovered mode may differ.

## Verification

- Focused presentation tests cover saved/runtime mismatch, empty/expired/future/
  undated reports, wildcard-to-loopback addressing, URL-secret rejection and
  compact fitting in both appearances.
- Final full `swift test` passes: 1,387 app/telemetry tests in 183 suites, 21
  protocol tests, and 28 host tests (1,436 total). Log:
  `/tmp/bloomy-popup-hosting-final-tests-20261002.log`.
- Release compilation passes in 46.24 seconds. Log:
  `/tmp/bloomy-popup-hosting-release-20261002.log`.
- Native113 was an intermediate isolated review. A refresh could briefly compare
  a newly published report against the previous display tick. Native114 evaluates
  freshness at render time instead. The intermediate artifact is retained.
- Native114 visibly renders the section in light appearance with empty discovery,
  and dark appearance with a reported `http://127.0.0.1:8123/v1` listener, no-key
  requirement and check time. A later screenshot/AX read confirms that the report
  becomes expired without another discovery read. Its height remains stable.

Native114 is an inert, review-signed fixture, not a distribution build:
`.build/native-dashboard-fixture-20261002-114/Bloomy Dashboard Fixture.app`.
All 97 source manifest hashes match the inspected source; exactly three existing
autonomous dependency substitutions remain in the builder. Binary SHA-256:
`4865f60e8c9b3f46cb05f687ad55f78874f24f464e9c20779b469fb5b3c6b1bc`.
Linked telemetry SHA-256:
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.

## Remaining proof and boundaries

During the first pass, CUA actions targeting the genuine menu-bar transient popup dismissed it and
returned the dashboard; a pointer attempt reported `windowNotFoundAtPosition`.
Therefore native Refresh and Hosting-navigation activation are **unconfirmed**,
not passed. Their source wiring and underlying read behavior are checked, but
these do not replace native action proof. Keyboard/VoiceOver, shorter popup
budgets, coordinator rendering, unified-mode rendering and real listener
reachability remain open. No new distribution artifact was published or installed.

The production app at `/Users/kevink/Applications/Bloomy.app` (PID 61760) and the
real provider were preserved. No whole-app performance window or hot-stack sample
was collected during this feature pass; the broader optimization goal stays open.

## Follow-up: native actions and keyboard reveal

Rebinding CUA with the exact app path **after** opening the popup resolves the
dashboard-bound input issue. Native114 then confirms pointer Hosting navigation
to the same dashboard's Hosting page and pointer Refresh changing the reported
listener check time from 8:34:35 PM to 8:34:46 PM. This supersedes the first-pass
native action limitation for these bounded assertions. A bundle-ID rebind is
ambiguous because multiple preserved fixtures share it; no bundle registrations
were removed.

The dark 240-point comparison finds a real defect: native Tab focuses Hosting
below the visible viewport without revealing it. Native115 adds a noninteractive
background anchor driven by the native control's SwiftUI focus state. It asks
each enclosing AppKit document to reveal the control with a six-point ring margin.
This uses Apple's [minimum-distance native scrolling API](https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:)).
No key events are consumed, no timer or animation is added, and unchanged source
publications do not repeat the scroll. Nested viewport geometry, unchanged-focus
position retention, and cancellation on focus loss have regression tests.

Native115 verifies dark 240-point reveal and a stable held focus/position across
synthetic source updates. Space also exposes a second issue: disabling Refresh
during its read drops keyboard focus to model Refresh. Native116 keeps the
hosting Refresh control focusable, shows Checking/hourglass while busy, and
ignores presses during an existing read. The fixed-width image avoids moving the
button as its state changes.

Native116 confirms:

- Light 80-point fallback: native Tab reaches Hosting and Refresh with visible
  focus rings; Space changes the check time from 8:43:17 PM to 8:43:48 PM while
  retaining Refresh focus. Another Space retains it again. Shift-Tab reveals
  Hosting, and Space opens Hosting in the same dashboard.
- Dark 240-point fallback: the reported URL, auth requirement and check time are
  visible; Tab reveals Refresh with a full focus ring; Space changes the check
  time from 8:44:39 PM to 8:44:59 PM without losing focus.
  A later AX/screenshot check shows the report expired while Refresh focus and
  the scroll position remain unchanged.
- The initial Native116 keyboard attempt returned to the dashboard. It is not
  accepted as proof. The successful repetition follows confirmed test-runner
  exit and a new exact-path popup binding.

Native116's 98 source manifest hashes match the final inspected source. Binary
SHA-256: `034c95a8b2d7b43c043e375b798c2c8b1911fde391bc4b3cbe8f05fddd41c5c3`.
Telemetry SHA-256 remains
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Native115 and earlier candidates are retained for provenance.

Final full tests pass: 1,390 app/telemetry, 21 protocol and 28 host tests (1,439
total), recorded in `/tmp/bloomy-popup-keyboard-final-tests-20261002.log`.
Final Release compilation passes in 47.05 seconds, recorded in
`/tmp/bloomy-popup-keyboard-final-release-20261002.log`.

This fix covers the two Hosting buttons. The remaining popup key loop, physical
wheel scrolling on the external display, delayed-discovery busy behavior,
coordinator/unified rendering and actual VoiceOver remain separate proof. The
running production app/provider and credentials remain unchanged; this is not
distribution or whole-app performance evidence.
