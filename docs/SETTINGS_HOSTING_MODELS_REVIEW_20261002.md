# Hosting and saved settings review — October 2, 2026

This is a bounded native review and regression checkpoint in the ongoing polish
run. The installed production app and its unsaved state remain untouched. The
real provider and recovery watcher remain stopped; no real endpoint, inference,
network nudge, token access or sensor collector is needed for these checks.

## Corrections

- Hosting labels distinguish selected settings from applied provider state.
  Fleet-only and authentication warnings no longer claim a running endpoint has
  changed before Apply. Existing restart, token, exposure-confirmation and
  authentication guards remain in place.
- Hosting discovery records display an absolute last-check timestamp and
  reported connection details. They are explicit cached reads, not a continuous
  reachability claim. Superseded reads cannot restore their record or timestamp;
  mode/apply invalidation clears both. The header refresh still reads only the
  CLI version and LAN addresses, as its help states.
  Listener ports use literal digits rather than a localized thousands separator.
- Terminal-command copy feedback belongs to the exact successfully copied
  command. Changing its port, bind or authentication options removes the Copied
  display. Failed clipboard writes show a retryable error.
- Hosting mode cards fill their row's natural maximum height and align at the
  top. This corrects the visibly uneven card tops and bottoms in the prior
  compact and wide rendering without adding a measurement observer.
- Menu Bar's idle-alert picker uses the same supported-value fallback as the
  alert policy. An unknown saved value displays five minutes without being
  rewritten on mount. An explicit Off choice still persists zero.
- One-slot startup selection resolves independently spelled enabled/preloaded
  aliases to the same catalog identity. It preserves raw saved selectors on a
  no-op selection, displays canonical short names, and offers each resolved
  model once. Unresolved options are excluded. Unknown preferences remain
  visible as unavailable until an explicit clear; mounting never guesses or
  edits a saved preference.
- A preserving control refresh adopts authoritative saved selection and limits
  when the draft is clean. A dirty draft retains its original revision and the
  latest edits made during a suspended read. Explicit plain refresh continues
  to replace the draft with saved controls.

## Review and regression evidence

Independent native workers implemented nonoverlapping changes and cross-reviewed
the final store/view behavior. Review caught an additional Fleet-only warning
and a no-preference duplicate-alias picker failure; both were repaired before
the final native snapshot. No remaining actionable finding was reported in
those bounded source reviews.

The preserving-refresh red run failed four test definitions with seven issues
before the store correction. The same focused cases then passed. Inert read
gates cover initially clean/dirty drafts and edits made while the read is
suspended; no controller save is performed.

The initial combined focused run passed 131 tests in six suites in 2.352 seconds.
The additional selected-warning check passed 34 Hosting store tests in 0.047
seconds. The final picker check passed seven definitions / 13 case executions
in 0.005 seconds, covering independent aliases, duplicate enabled aliases with
zero/one/multiple preloads, unresolved choices, absent inventory and explicit
clear. These tests verify raw values and draft integrity separately from visible
native presentation.

## Native evidence

Native 46B was the unchanged before snapshot. At 1280 × 900, Hosting mode cards
had different top/bottom edges; at 800 × 560 the two first-row cards were visibly
uneven. Its Fleet-only labels also described selected settings as active.

Native 47 was an intermediate production-view snapshot. All 85 source hashes
and actual binary matched its manifest before launch; binary SHA-256 was
`da99bc8d5d4c457ca997d9ce2d8811ecd61e195098e9e1e54c0d02f7a93fb518`.
It verified aligned Hosting cards in compact/wide light presentation, an
unsupported fixture-only idle-alert value displayed as five minutes, an explicit
Off selection retained after routing away/back, and compact Appearance switching
from Light to Dark. The initially invented fixture alias did not match its
catalog family; the product correctly showed an unavailable preference. The
fixture was corrected to its actual unique `gpt` family before final proof.
Native 47 therefore is not the final startup-picker proof. Its runtime directory
was `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-FB00C0CB-037C-41BB-922E-D92A36F101AF/`.
The app was quit normally and its process absence confirmed.

Native 48 verified the corrected alias fixture and final picker/store behavior.
Its 85 source hashes and binary matched before launch; binary SHA-256 was
`f3ae67d319c33ea1b3581d933f82f580d919c31778afd4390751ef775aa837ec`.
Runtime directory:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-D9830EBF-71C2-45A5-AD03-EC82EF8A8518/`.

Direct native review observed:

- Aligned Hosting cards in wide light and compact dark presentation.
- Explicit discovery checks at 6:43:57 and 6:44:33 updated the absolute timestamp
  and retained the distinction between a reported endpoint and selected settings.
- Inert Terminal-command copy displayed Copied. Editing the selected port from
  8000 to 8124 updated the command and reset its button to Copy Terminal command.
  The reported endpoint remained on its independently read port.
- Compact dark and wide light one-slot capacity showed GPT-OSS · 20B despite the
  saved enabled selector being `gpt` and preload selector being `gpt-oss-20b`.
  Its menu help exposed both identities. Initial mounting and reselecting the
  displayed model kept Save Changes disabled. Choosing Gemma displayed Unsaved
  changes and enabled Save. Discard restored GPT-OSS and the clean state.
- Enabled and Available disclosures could collapse to reach capacity controls;
  compact body scrolling retained the footer and sidebar. Some native AX click
  attempts left controls unchanged, so visible-coordinate input was used and the
  resulting state checked. This does not establish comprehensive keyboard or
  VoiceOver behavior.

Native 48 also exposed localized listener text `127.0.0.1:8,123`. The only later
production change converts the port to a literal string before Text interpolation.
Native 49 verified the final source snapshot: all 85 source hashes and actual
binary matched `.build/native-dashboard-fixture-20261002-49/fixture-manifest.json`.
Binary SHA-256:
`bfd0e218279cbe6417d24b0f7c36e7746fc557bec4ad45d0d9990ce6bc0a3d3b`;
linked telemetry SHA-256:
`9ea433b3ead885ae0c9c524749a54274dd8cbb99f2e4b6cf6ccc07ac3211df4a`.
Runtime directory:
`/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-9EA2CEFB-D07B-4043-80C2-11CC4583401C/`.
The explicit fake discovery check displayed `Reported listener: 127.0.0.1:8123`
visibly and accessibly. Selecting authentication off and then Fleet only in
isolated preferences displayed the repaired selected-setting warnings, retained
an explicit Apply button, and invalidated the old discovery details. Apply was
not invoked. Compact dark Menu Bar showed the five-minute effective fallback
for the isolated saved value 99. Focus tracing stayed off throughout. Native 48
and 49 were quit normally and process absence checked.

## Final checks

Full run 02 passed **1,306 tests**: telemetry 1,257 / 165 suites in 30.132 seconds,
protocol 21 / 5 in 0.014 seconds, host 28 / 9 in 11.733 seconds. The release
build after those behavior corrections completed in 47.24 seconds. After the
one-line literal-port display correction, the final release build completed in
31.21 seconds and Native 49 inspected that exact view. All finite commands
exited 0; no compiler warnings or errors were found. The full suite was not
repeated for that literal display-only correction.

Logs are in `/tmp/bloomy-efficiency-20261001/`:
`models-refresh-preserving-red-01.log`,
`models-refresh-preserving-green-01.log`,
`settings-hosting-models-focused-01.log`,
`hosting-selected-warning-focused-01.log`,
`model-startup-picker-focused-02.log`,
`settings-hosting-models-full-02.log`,
`settings-hosting-models-release-03.log`, and the Native 47–49 build logs.

The installed v1.9.15/build 140 production app retains PID 31677 and its original
October 1 launch. Its executable SHA-256 remains
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`;
provider configuration SHA-256 remains
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
No provider or recovery launch service is running. Unrelated log readers and
other projects were preserved. This checkpoint is a local commit, not a new
installed or published release.

## Scope limits

The fixture uses isolated preferences, fake discovery and inert Terminal-command
copying. It does not establish production permissions, actual reachability,
provider behavior, real clipboard failure delivery, VoiceOver operation, system
Reduce Motion delivery, sustained whole-app performance, signing or updater
installation. Broader screen/appearance/size/keyboard review remains in the
ongoing plan. The known genuine-cover occlusion prerequisite is not retried or
relaxed as part of this checkpoint.
