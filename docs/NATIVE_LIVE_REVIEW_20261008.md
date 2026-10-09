# Bloomy popup and live graphics review

Completed October 9, 2026, shortly after midnight America/Phoenix. This is a
local native review checkpoint for the October 8 request, not a distribution
release or completion of the broader polish/efficiency goal.

## Visible result

- Popup model rows are 52 points high, one third of the previous 156-point
  cards. Collapsed Models rows are 64 points, one third of the previous
  192-point cards. Available groups collapse and scroll; Manage opens details.
- Hosting, provider Start/Stop/Restart, Auto selection, Autopilot, manual and
  automatic nudge, Cooling, Energy, GPU protection, profit switching and app
  settings are reachable from the popup. Long analysis remains in the dashboard.
- Operational panels reuse the existing control stores and safeguards.
  Hosting partial input survives dismissal. Clean retained drafts follow saves
  from the other editor without overwriting a partial field.
- Hosting summary and Auto handoffs wait for sheet dismissal. Native testing
  caught and repaired the earlier Hosting popover handoff.
- Only the active popup presenter owns a lifecycle confirmation. Covered parent
  controls cannot present or dismiss a panel's pending action. The Provider panel
  includes the existing graceful lifecycle controls.
- Live bars follow accepted measurements, including explicitly labeled
  provider-wide tok/s. Idle, unavailable, stale and estimated values remain
  distinct. No decorative repeating value animation is added.
- Native performance charts share 1/2/8/12/24-hour controls. Provider/process
  changes, missing observations and stale readings preserve gaps. Historical
  points do not establish a current measurement or per-model attribution.
- Bounded network demand history uses shared reads and shared scales. Model
  controls shorten the existing demand cadence while visible, preserve retry
  backoff and avoid an extra fetch when the current reading is fresh.

## Final artifacts

Actual app, built from the production executable:

`/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor/.build/native-live-review-20261008-qualified/Bloomy Live Review.app`

Identity: `dev.darkbloom.monitor.live-review-20261008`, version `1.9.19`, build
`2026100901`. Local ad-hoc signing verifies with deep/strict checking; embedded
vendor framework signatures are retained. No updater feed is configured. This
does not establish Developer ID signing, notarization or release eligibility.

Signed executable SHA-256:
`863f4625489bae9b5d1cf2319682b9d355c8ee241a7bedaa48c1273be0a2440c`

The sibling `qualified-review-manifest.json` records all 253 production/fixture
source hashes, the final lifecycle test source hash and signed artifact hashes.
The earlier packaging manifest describes unsigned bytes; the qualified manifest
is authoritative for the signed review artifact. All frozen source hashes match.

Final inert native fixture:

`/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor/.build/native-live-review-fixture-20261008-d/Bloomy Dashboard Fixture.app`

Its `fixture-manifest.json` matches the current sources, including the preserved
pre-existing motion proof. It stages inert dependencies and retains production
view bodies. Synthetic readings are not real inference, demand or earnings.

## Checked behavior

- Native light and dark popup: readable full-width rows and unavailable GPU
  state; Available collapse/reopen and scrolling expose all rows and history.
- Manage models: compact rows, direct selection/preload/uninstall guards and
  return from detailed forecast/settings.
- Auto → Choose selected models: one sheet dismisses before the Models panel
  opens. The one-slot recommendation and selectable preload remain visible.
- Hosting summary → editor: immediate handoff after dismissal; partial invalid
  text survives closing/reopening, and Discard restores the last saved value.
- Energy, Cooling refresh/policy, manual nudge guide, automatic nudge, GPU
  protection, profit switching and Provider panels open inside the popup.
- Active-work Stop and Restart: exactly one graceful confirmation appears;
  Cancel returns to the Provider panel. No real lifecycle action is executed.
- Supplied high-load and idle readings update the gauges; idle throughput is
  distinct from a measured GPU zero. All five native chart periods select.
- The actual isolated app launches and reads current provider/model/demand
  data. Its Models view shows real demand and compact rows. Initial file-path
  selection timed out after launch; selection by verified bundle ID succeeded.

Evidence is retained in the `evidence` folders under fixture variants b, c and d
and under the qualified actual app output. Variants b/c establish unchanged
card/chart/draft behavior; d verifies the final lifecycle presentation. In
particular, d retains `popup-light.png`, `popup-provider-panel.png`,
`popup-stop-confirmation.png` and `popup-restart-confirmation.png`. The actual app
output retains `models-live.png`.

## Checks and boundaries

- Full Release suite with `--no-parallel`: 1,826 reported app tests, 230 suites,
  seven existing opt-in skips; 21 companion contract and 28 companion host
  tests pass. Log: `.build/native-live-review-final-serial-tests-20261008.log`.
- Final strengthened confirmation/process regression selection: 54 tests pass.
  It waits for deferred dismissal before verifying the covered parent cannot
  cancel a panel action. Log: `.build/native-live-review-final-regressions-20261008.log`.
- 47 native staging checks and 17 packaging checks pass. Final optimized fixture
  and production executable builds complete successfully. Deep/strict signature
  verification and `git diff --check` pass.
- A preceding concurrent full run missed the unchanged process-runner
  one-second timing bound (1.119 seconds). The serial full run passes it in
  0.322 seconds; the focused final run passes in 0.314 seconds. No bound changed.

The production app remained PID 7234 at `/Users/kevink/Applications/Bloomy.app`.
Darkbloom was stopped by another project earlier in the session, then was already
running again at the final live check (PIDs 41278/41284, Gemma enabled and warm).
This UI work did not stop, restart, reconfigure, swap, download or send paid
inference to that provider. Review automation defaults stayed off; live inspection
was read-only. A read-only SQLite backup supplied history to the review's private
application-support namespace; no credentials or production preferences were
copied. Both final review processes quit normally after inspection, leaving the
production app/provider running.

Ordinary menu-bar motion/occlusion, system Reduce Motion and large-text proof,
matched whole-app CPU/memory/wakeup measurements, historical local financial
attribution, Companion delivery and distribution gates remain open. Stills and
bounded scheduling architecture do not establish performance savings or complete
motion qualification. No push, release or installed-app replacement occurred.
