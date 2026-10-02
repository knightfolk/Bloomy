# Settings, Health, and compact Logs review — October 2, 2026

This is a bounded continuation of the native polish and efficiency run. The
installed production Bloomy and its unsaved windows were preserved. Provider
and recovery stayed stopped; no inference, model swap, download, credentials,
privacy changes, or real updater installation were needed.

## Findings and changes

- Native 25 exposed a compact Logs layout failure: selecting an event displaced
  the Health & Logs title and view picker above the visible content, with detail
  content clipped below. Logs now gives the page its own scrolling region and
  bounds the independently scrolling table to the available viewport.
- Source-freshness rows visibly showed timestamps and stale reasons, but native
  accessibility exposed only their source names. Each combined row now has an
  explicit label containing its name and full freshness presentation.
- Automatic provider-update and fan settings treated every successful read as
  current, even after its 45-second validity expired. The view, staged fan
  actions, confirmation execution, and store mutation now respect the existing
  validity window. Visible presentation wakes only at finite evidence deadlines;
  this adds no recurring polling loop.
- Expired fan-helper readings yield to current CLI diagnostics. When only old
  helper readings exist, they retain their numbers with a last-known label,
  separate CLI-check and helper-sample times, and retry guidance. Helper state
  also remains qualified. Generic acquisition failures ask for Refresh without
  asserting that the CLI needs an upgrade.
- The application updater guard now includes retained dashboard fan and idle
  drafts. The dashboard controller owns the same draft object used by its view,
  so switching pages or closing the window does not release update protection.
  This is a bounded guard improvement: broader Chat, Hosting, credential-editor,
  and popup draft protection remains separate work.

## Regression evidence

The fake-clock settings suite first reproduced 89 issues when expired, future,
last-good, unavailable, and missing evidence reached the mutation client. It
covers the inclusive 45-second boundary, delayed confirmation execution,
finite deadlines, and current-diagnostic precedence over an expired helper.
Existing extras, polling, fan rendering, and draft-retention tests are retained.

The actual production updater guard initially failed six retained-draft checks.
The final focused run passed 9 tests in 2 suites, including independent dirty
fan/idle states, inert Save/readback, navigation, closing/reopening the same
window, rendered invalid idle text, and saving one draft while another remains
dirty. This does not establish real Sparkle installation or resumption.

Raw logs are retained under `/tmp/bloomy-efficiency-20261001/`:

- `settings-freshness-red.log` — initial freshness failure.
- `settings-freshness-green.log` — first focused freshness pass.
- `settings-freshness-green-final.log` — freshness passed; the concurrent
  updater guard regression was deliberately still red with six issues.
- `settings-update-guard-red-01.log` — exact retained copy of that guard failure.
- `settings-update-guard-green-01.log` — final focused guard pass.

Combined verification and final native-source identity follow below.

## Final combined verification

The final source completed the full test command with exit 0:

| Product | Tests | Suites | Test time |
| --- | ---: | ---: | ---: |
| App and telemetry | 1,181 | 154 | 26.336 s |
| Companion core | 21 | 5 | 0.015 s |
| Companion host | 28 | 9 | 11.790 s |
| Total | **1,230** | | |

The release build completed with exit 0 in **47.14 s**. Authoritative logs are
`settings-health-logs-full-tests-02.log` and
`settings-health-logs-release-build-02.log` in the same temporary evidence
folder. Earlier `-01` runs preceded the final native-section alignment repair
and do not establish the final build.

## Native evidence and identity

All review apps used inert dependencies and closed through their own native
Quit command. No fixture process remained afterward. Screenshot and native
accessibility evidence are retained in this chat's computer-use outputs.

Native 25 supplied the before-state: compact Logs lost its title/picker on
selection, and Health rows exposed only their source names. Its Hosting review
also verified compact dark wrapping and invalid port `0` disabling Apply;
that is a bounded prior-source check, not fresh proof of every Hosting path.

Native 26 verified the corrected Logs and Health source, whose file hashes are
identical in Native 27:

- Compact light: Health title and segmented picker stayed visible with a
  selected row. Down selected a neighboring event. Scrolling within the table
  moved its rows independently; scrolling over the page outside the table
  reached the full selected-event details and export notice.
- Wide dark: selected details and the export notice remained visible. Changing
  Severity to Warning excluded the selected Info event and cleared its details.
- Fresh Health: the accessibility tree included all source capture timestamps.

Fresh synthetic event timestamps are reconstructed every five seconds by this
fixture. The longer selected-detail checks used its stable Stale scenario;
these checks do not establish selection retention across real event arrivals
or duplicate-event keyboard behavior.

Native 26 also caught a new presentation regression: wrapping Section inside
TimelineView changed Form headers into centered card content. The final source
keeps Section outside the timeline and aligns its content explicitly.

Native 27 is the final-source settings review:

| State and route | Native result |
| --- | --- |
| Expired settings / Updates, wide light | Native left section header restored; last-known Enabled badge and Refresh guidance; mutation action absent |
| Expired settings / Fans, compact dark | Native left section header restored; last-known readings/state and retry guidance; policy/mutation controls absent |
| Expired helper / Fans, compact dark | Separate CLI-check and old helper-sample times, last-known numbers/posture, and helper-refresh warning |
| Unavailable settings / Fans, compact light | Neutral unavailable guidance, reachable Refresh readings; inert retry retained the unavailable state |
| Unavailable settings / Updates, compact light | Lower section reachable by scrolling; neutral retry guidance with no unsupported-CLI assertion |
| Fresh / Updates, compact light | Disable changed only the fake actor; readback showed Disabled, Enable, and next-start Save confirmation |
| Stale / Health, compact light | All four accessibility rows included their timestamps and stale reasons; warning text wrapped cleanly |
| Offline / Health, compact light | Current stopped-source capture labels stayed distinct from unavailable loaded-model/event sources |

Final manifest:
`.build/native-dashboard-fixture-20261002-27/fixture-manifest.json`.
Copies of both Native 26 and 27 manifests are retained under the temporary
log folder. All **78** final source hashes and the binary hash matched after
review. Final binary SHA-256:
`9f8873f3782b40355c43f8d03c61d4f285dd248a29644c20d10e0e9a91a03944`.
Linked telemetry library SHA-256:
`a8b51e2df2f6e0244733279b1b5f844c23f5d58e0e6fc08a7fd53d7f1754d65b`.

The protected installed app still had PID 31677 and its original launch time
and binary hash. The real provider configuration hash was unchanged. Existing
unified-log readers were preserved; this pass did not prove their historical
ownership or remove them.

## Remaining boundaries

This is a local verified checkpoint, not full-matrix completion or a release.
Actual VoiceOver, controlled Reduce Motion, live fresh-to-expired native
settings transitions, broader keyboard/duplicate-event interaction, production
Sparkle installation/resumption, and sustained updated-production performance
remain open. The production Sol cache permission gate and protected unsaved
production windows remain in force. No current-source CPU/battery improvement
is inferred from the synthetic host or these tests.
