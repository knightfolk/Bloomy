# Native navigation and popup review — October 2, 2026

This is a bounded checkpoint in the ongoing polish run, not a declaration that
every screen or production state is finished. The installed Bloomy app remains
unchanged. The real provider and recovery watcher remain stopped.

## Baseline

Root launched the isolated `native-dashboard-fixture-20261002-06` app from
the preceding checkpoint. Its manifest identifies the production views used.
The native AppKit window hosted the production dashboard with synthetic stores;
no provider, account API, credentials, or CPU/GPU collector was started.

With Overview shown, clicking its sidebar row selected the destination but left
the Scenario picker as the keyboard responder. Down then opened that picker.
The initial Tab check from Scenario stopped when it reached the Overview
disclosure. That partial traversal did not establish that the sidebar was
unreachable; the full traversal correction is recorded below. The click/Down
result established the selection/responder mismatch in the preceding fixture.
The baseline also showed the truncated `iPhone Compa…` sidebar title.

## Changes under review

- Dashboard rows now use native `List(selection:)` tags. A computed sidebar
  selection maps to the existing destination and independently saved Settings
  page, without maintaining another selection state.
- The Companion sidebar title is concise, with the full `iPhone Companion`
  heading, hover help, accessibility name, ID and persisted raw value retained.
- Explicit routes reveal their sidebar group even when that destination was
  already selected. Generic window reopening preserves the collapsed groups.
  The window host also passes its injected preferences to the SwiftUI tree.
- Model Manager ordering uses display name and canonical ID. Activity changes
  update the cards' badges instead of changing their positions. Section/search
  and downloaded-first Available grouping are retained.
- Both custom model-group disclosures and the dashboard GPU ring read the
  system Reduce Motion preference before choosing an animation. The actual
  host preference was off; no system preference was changed for this check.

The opt-in dashboard fixture also gains an actual transient `NSPopover`, hosted
from an explicit Popup review button with the production popup body and injected
stores. Its preferences are isolated, its fan subscription closes with the
popup, and navigation returns to the existing synthetic dashboard. The fixture
does not establish production menu-bar positioning or live provider actions.

## Verification

The complete production suite passed after the navigation/reveal, model-order,
label and Reduce Motion changes: 1,104 app/telemetry tests, 21 companion tests,
and 28 host tests (1,153 total). The release build completed in 38.44 seconds.
Logs are retained in `/tmp/bloomy-efficiency-20261001/` as
`stable-sidebar-final-full-tests.log` and `stable-sidebar-final-release-build.log`.
The later sidebar Tab-focus experiments were removed after native inspection;
the production sources again match the source used by those passing checks.

Native observations from isolated review builds:

- Build 07: clicking Overview followed by Down selected Activity and changed
  the detail page; Up returned to Overview. After entering the sidebar,
  Tab/Shift-Tab reached its Monitor disclosure and Space collapsed/reopened it.
  The sidebar shows the full concise Companion title.
- Build 09: selecting Companion, collapsing Settings, and opening Settings
  from the popup closed the popup and reopened Settings with Companion still
  selected. The full detail heading remains `iPhone Companion`.
- Build 09: Available on this Mac expanded to the empty-state message and
  collapsed again. The three Advertised cards used consistent widths. Rapid
  popup toggles and consecutive Reload requests remained responsive.
- Build 09: the manual Nudge action opened the three-step setup guide with a
  secure key field and disabled empty-key save button. No real key was entered,
  no account page was opened, and no request was sent.
- Build 09: Cooling displayed its Refresh readings button; clicking it updated
  the checked timestamp. The Fan policy disclosure opened its presets and
  sliders. No fan policy, helper installation or permissions were changed.
- Build 10: Auto retained all three selected models, saved one slot with GPT-OSS
  as the chosen startup model, and displayed `Auto plan saved`. This exercises
  the production view with an in-memory controller, not real configuration.
- Builds 09 and 10: Quit from the popup returned and the fixture process exited.
  The installed Bloomy process remained running throughout.

The final build is `native-dashboard-fixture-20261002-12`. All 76 source hashes,
the executable hash and the linked telemetry library hash matched its manifest.
Its executable SHA256 is
`4659f26daaa8602c96eff60399bd3bddfefb7f5dbee02a4f888f01623803a486`.
Root repeated native arrow navigation, the collapsed Settings return path, and
the GPT-OSS Auto save in this exact build. Auto's Choose selected models action
closed the popup and selected Models; the selected preload checkbox and all
three enabled cards were retained. The populated Models Available section also
collapsed and reopened. Quit returned and no fixture process remained.

The real CLI still reported version 0.9.17, `Daemon: not running (stale state
file)` and an installed but unloaded recovery watchdog. The provider config
SHA256 remained
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
The existing installed Bloomy process was not replaced or restarted.

The additional popup checks found and corrected three fixture defects: an
AppKit termination callback that blocked asynchronous cleanup, a busy loop
while waiting for the native popup close animation, and a save/readback client
that dropped the startup-preload flag. The fixture now cancels the first native
termination request while it joins cleanup, waits for the popover delegate's
close callback, and retains the complete saved startup plan. Earlier forced
stops and diagnostic samples are retained as `fixture07-quit-sample.txt` and
`fixture08-close-sample.txt`; neither was a production-app failure.

## Follow-up keyboard proof

Build 13 adds a bounded, opt-in native focus trace to the synthetic host. It
records responder classes, geometry and table selection around the first 24
Tab/Space/arrow events, without logging text, key contents or control values.
The ordinary native events are delivered unchanged; it adds no focus behavior
to production. Its log budget is 49 records per process and cannot be reset by
toggling the diagnostic.

In a fresh second build-13 session, root enabled the trace and used only Tab
to traverse from the fixture Scenario control. The sixth Tab reached the
Overview disclosure; the seventh reached the native SwiftUI sidebar outline.
The accessibility snapshot reported no focused element at that step, while
the native trace identified the outline as the first responder. Repeating
that keyboard path and pressing Down selected Activity and opened Earnings,
without a preceding sidebar mouse click. Full Keyboard Access was enabled.
The earlier conclusion that forward Tab skipped the sidebar was incorrect:
the partial test stopped one Tab early and accessibility output omitted the
outline's focus state. The removed `focusSection()` and `focusable()` trials
are not needed for this demonstrated path.

The exact build-13 sources, executable and linked telemetry library matched
their manifest. Its executable SHA256 is
`41907211e7b810600e3d4752af0c6b86c684147278e22f3412b9b7ccec9f1ca4`.
The bounded traces are retained in `/tmp/bloomy-efficiency-20261001/` as
`native13-focus-diagnostics.jsonl` and `native13b-focus-diagnostics.jsonl`.
The second trace has 37 records, including the Tab-to-outline and Down-to-
Activity evidence. Quit from the popup exited both sessions cleanly.

This establishes the tested native Tab/arrow path in the Overview fixture.
It does not establish every route's keyboard or VoiceOver behavior.

## Remaining evidence

Controlled Reduce Motion proof, nonempty popup Available cards, VoiceOver, the full
light/dark and narrow/wide state matrix, native menu-bar popup placement, live
provider actions and comparable process/energy profiling remain outstanding.
The native capture crops popup pixels outside its parent window; its header
actions were confirmed through accessibility rather than a complete header
image. The review fixture is not a distribution or updater artifact.
