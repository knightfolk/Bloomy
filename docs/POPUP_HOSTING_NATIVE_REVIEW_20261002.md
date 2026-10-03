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

CUA actions targeting the genuine menu-bar transient popup dismissed it and
returned the dashboard; a pointer attempt reported `windowNotFoundAtPosition`.
Therefore native Refresh and Hosting-navigation activation are **unconfirmed**,
not passed. Their source wiring and underlying read behavior are checked, but
these do not replace native action proof. Keyboard/VoiceOver, shorter popup
budgets, coordinator rendering, unified-mode rendering and real listener
reachability remain open. No new distribution artifact was published or installed.

The production app at `/Users/kevink/Applications/Bloomy.app` (PID 61760) and the
real provider were preserved. No whole-app performance window or hot-stack sample
was collected during this feature pass; the broader optimization goal stays open.
