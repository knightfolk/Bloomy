# Chat, Activity, Opportunity, and Models — October 2, 2026

This is a bounded checkpoint in the continuing native polish and efficiency
run. Native inspection used isolated synthetic apps, disabled CPU/GPU readers,
and inert data clients. The installed production app and its unsaved state were
preserved. These checks did not issue real inference, model, fan, credential,
provider, or updater operations.

## Changes

- New Chat is unavailable during a send and explains the explicit Cancel step.
  Already-open route and paid-network confirmation actions recheck that guard
  synchronously before replacing the conversation. Cancellation retains the
  existing warning that the request may already have been delivered.
- Chat uses concise model names while retaining canonical IDs in picker tags,
  help, accessibility names, and response provenance. Visible You/Assistant
  captions distinguish identical message text. Message text remains selectable;
  waiting, failure, and cancellation descriptions name their speaker.
- Earnings keeps a selected model filter reachable when the chosen period has
  no results for it. This adds a filter option, not fabricated activity. All
  models clears only the model filter; its spoken description respects the
  independent base-reward visibility preference.
- Opportunity's individual counts and throughput describe their canonical
  model and network-wide scope. Retained demand, routing, and pressure values
  explicitly say they are past reports. Each Details disclosure has a contextual
  name, and neighboring cards stay aligned at the top when one expands.
- Metrics recording freshness requires finite clocks, current source quality,
  and an age from zero through ninety seconds. Render wall time evaluates new
  reads arriving between minute ticks. The tick remains an explicit visible
  expiry dependency; analysis retains the read token's original window.
- Model settings use the actual host screen's available height, with a stable
  scroll area and reachable Done controls. Missing or ambiguous canonical
  inventory entries show a refreshable unavailable state instead of the old
  captured model. Staged edits remain retained. Late Enable/Preload callbacks
  additionally require their captured selector to resolve uniquely to the same
  current downloaded model before staging either edit.

## Review findings and rejected native candidates

Independent review caught two clock hazards: clamping time to a future sample
could fabricate freshness, while using only the last minute tick could reject a
legitimate thirty-second read. The final implementation uses render wall time
without moving the analysis window. Tests cover between-tick arrival, finite
expiry, rollback, future samples, and invalid clocks.

A second review found an alias-change race. When a refreshed exact model ID
matches another model's former alias, a late checkbox callback could edit the
new model's raw selector. The store's selection remained valid, so draft
validation alone could not catch it. The final callback guard uses exact-ID
precedence and unique current alias resolution, without silently substituting
a new selector. Builder-backed tests reproduce the refresh for both toggles,
retain the unrelated draft, and verify normal independent aliases still work.

Native inspection exposed failures that green tests did not catch. Native 55
merged identical selectable message text into one accessibility aggregate and
omitted the speakers. Two subsequent Chat accessibility modifier arrangements
crashed with signal 11 during send/accessibility inspection (Native 56 and 57).
Removing the row container alone did not fix the failure. Native 58 restored the
safe label placement before text selection and added visible speaker captions;
its Chat checks passed. Applying an accessibility label to the entire Opportunity
disclosure then crashed when opening its selectable Details body. The final
contextual label is attached only to the nonselectable Details label text.
Native 59 opened and inspected the body safely.

These are observed native failures, not a proven framework-wide diagnosis.
The debugger attempt yielded no useful stack and was intentionally stopped;
no production process was affected. Rejected candidates were not committed or
released. Their build logs and staged sources remain available for provenance.

## Native component evidence

Native 55's Earnings and Metrics production source bytes are unchanged in the
later reviewed candidate. Its Models sheet proof predates only the additional
selector guard; the final sheet is checked again below. Its snapshot is identified by
`.build/native-dashboard-fixture-20261002-55/fixture-manifest.json`; binary
SHA-256 is
`247693054e2be5527bfe1ab1f073b678423f2dfc8c2d58d7d65ddc346fa84a8a`.

- Compact dark Models opened an actual 620 × 360 settings sheet. Scrolling
  reached the remaining editor controls and footer Done. A staged Gemma preload
  change survived Escape. Removing Gemma from the inert inventory while its
  sheet was mounted showed Model unavailable, removed its obsolete controls,
  retained the edit, and kept Refresh and both Done actions reachable. Refresh
  stayed read-only. Returning to Models retained the invalid draft and blocked
  Save rather than silently discarding it.
- Compact dark Earnings retained the selected Gemma filter after a refreshed
  report contained only Qwen. All models cleared Gemma. With base rewards hidden,
  its accessibility description said those rewards remained hidden. Chips were
  inspected at normal scale and retained consistent sizing.
- The controlled network snapshot expired with synthetic source publication
  held. Its visible badge and standalone values changed to past reports through
  their own visible deadline, without an unrelated refresh.

Native 58's final Chat production source is unchanged in the later reviewed
candidate. Its manifest is
`.build/native-dashboard-fixture-20261002-58/fixture-manifest.json`; binary
SHA-256 is
`44b6f49b8a8cd1c5858dd9baba4405242a721035d41f39ab801187184639f298`.
The whole candidate was rejected for the separate Opportunity disclosure crash.

- Sending identical text in compact light appearance stayed stable. Captions
  visibly identified You and Assistant; the native accessibility aggregate
  included both speakers and the response's route/model provenance. Double-click
  selected message text. This remains one aggregate, not proof of independent
  message navigation or a complete VoiceOver transcript experience.
- A held inert send disabled New Chat in the pop-out and dashboard. Cancel in
  the dashboard stopped the send, restored New Chat, and retained delivery
  uncertainty. Automated tests additionally cover both late route choices.
- Two different canonical IDs with the same short model name were exposed in
  the actual picker menu. Selecting and sending with each preserved its correct
  canonical ID in response provenance.
- The 460 × 520 pop-out was inspected in light and dark appearance. Its draft
  and the dashboard's separate draft survived navigation and appearance changes.
  The real verification deadline disabled Send without losing either draft.
  Native 55 separately verified closing/reopening the pop-out retained its draft.

Native 59 verified the repaired contextual Details label and expanded body. A
controlled snapshot progressed from Live network at 1 min 41 sec to Last known
demand at 2 min 7 sec without source publication. Expanded routing and pressure
became last-reported values both visibly and in accessibility text. Its manifest
is `.build/native-dashboard-fixture-20261002-59/fixture-manifest.json`; binary
SHA-256 is
`2d64edcbd9afa966fd61a6c16a72b3c0f8202803d1193bc0138648613e53f4c7`.

Native 60 verified top-aligned neighboring cards with one Details body expanded
in wide light appearance. Compact dark inspection scrolled through the expanded
body to the final cards and How to read this disclosure. Its manifest is
`.build/native-dashboard-fixture-20261002-60/fixture-manifest.json`; all 85 source
hashes and the binary matched the source at that review. Binary SHA-256 is
`77270f75b21245d2b24db44253f5056c85ab0021d1d5bda438063a035fde7576`.

Native 61 includes the final selector guard. All 85 source hashes and the binary
match the final source. Its manifest is
`.build/native-dashboard-fixture-20261002-61/fixture-manifest.json`, manifest
SHA-256 `c1c5482a5435ba330c34b393c2475c72fe6e0de2c9537b43b9ab4186a4409694`,
and binary SHA-256
`d531e342a190dd3ca12b9e0987173c621800d63824433bcc446e2322900a964e`.
Only Model Manager changed after Native 60; the final Chat component matches
Native 58, and final Earnings/Metrics match Native 55.

In compact dark appearance with the fixture's 360-point host budget, the final
Gemma sheet rendered at 620 × 360. Its
remaining controls and footer Done were reachable by scrolling. An explicit
preload toggle staged its change. Removing Gemma through the fixture's inert
inventory command while the sheet was mounted showed Model unavailable and
removed obsolete controls. Refresh kept that state. Escape returned to Models
with Unsaved changes, the unavailable-model reason, and Save blocked. The
Available section collapsed and reopened with the draft retained. The alias
collision's late callback is established by the builder/store regression, not
by this native normal-selector check.

The fixture stages immutable source/library bytes and records three inert
dependency substitutions. It excludes the live production app entry point.
Source-matched component evidence is narrower than reviewing every state of
the final application. Screenshot/accessibility outputs are retained in this
chat, with synthetic runtime records in each fixture's unique temporary folder.

## Regression and build evidence

Logs remain under `/tmp/bloomy-efficiency-20261001/`.

- The new suites cover Chat phase/speaker/canonical identity and both late
  routes; retained Earnings filters and base visibility; current/retained
  Opportunity labels; Metrics arrival/expiry/rollback/invalid clocks; and model
  sheet height, inventory removal, alias replacement, draft retention, and valid
  independent selectors.
- `model-selector-focused-01.log` exited 0: six test definitions in one suite,
  including parameterized Enable/Preload cases; no warnings or errors.
- Final `chat-activity-models-full-07.log` exited 0: 1,295 app/telemetry tests
  in 173 suites (25.357 s), 21 companion-core tests (0.015 s), and 28
  companion-host tests (11.792 s), **1,344 total**.
- Final `chat-activity-models-release-06.log` exited 0 in 45.14 s. Native 61's
  standalone build also exited 0. Earlier test/build runs preceded later native
  or selector findings and do not establish final source verification.
- `git diff --check` passed. Finite build/test sessions were joined. Surviving
  fixtures closed through their own Quit command; no fixture or debugger process
  remained.

Production PID 31677 retained its October 1 22:40:57 launch and binary SHA-256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
The provider and recovery LaunchAgents remained unloaded. The unchanged saved
configuration and successful read-only cache scan are documented in
`docs/PROVIDER_CACHE_STARTUP_DIAGNOSTIC_20261002.md`; no vendor message was sent.

## Remaining boundaries

The full VoiceOver, keyboard, multiple-screen, Reduce Motion, live hardware,
production, updater-installation, signing, and distribution matrices remain
open. No production relaunch or publication was used to obtain these results.
The provider's separate managed-launch cache failure remains unresolved after
the authorized scoped removable-drive reset; the failed service and recovery
watcher remain stopped. Its sanitized diagnostic is kept separately.
