# Native export fixture

This opt-in app hosts the production export view with a fixed synthetic snapshot.
It does not start a provider or read credentials/log files. It is not shipped.
The Swift test runner renders the view but does not expose its windows reliably
to external accessibility automation, so native save-dialog proof uses this app.

From the repository root, after `swift test` has built debug telemetry objects:

```sh
mkdir -p .build/native-export-proof/DarkbloomExportFixture.app/Contents/MacOS
cp Tests/NativeUI/Info.plist .build/native-export-proof/DarkbloomExportFixture.app/Contents/Info.plist
swiftc -target arm64-apple-macosx14.0 -parse-as-library -I .build/arm64-apple-macosx/debug/Modules Tests/NativeUI/LogExportFixture.swift Sources/DarkbloomMonitor/Dashboard/LogExportPreviewView.swift Sources/DarkbloomMonitor/Dashboard/LogsView.swift Sources/DarkbloomMonitor/Components/EventRow.swift .build/arm64-apple-macosx/debug/DarkbloomTelemetry.build/*.o -lsqlite3 -o .build/native-export-proof/DarkbloomExportFixture.app/Contents/MacOS/DarkbloomExportFixture
open -g .build/native-export-proof/DarkbloomExportFixture.app
```

Keep the explicit deployment target: this host's standalone compiler otherwise
produced a macOS 28 minimum on a macOS 27 host. `open -g` targets the app bundle,
never a raw executable (which can open Terminal).

Check Save is disabled before acknowledgement. Acknowledge, open the native
dialog, cancel and verify no output. Open it again and use **Go to Folder** to
select a newly created temporary directory before exporting. Do not put an
absolute path into the filename field: macOS may turn slashes into colons and
save in its remembered directory. Compare the resulting UTF-8 bytes with the
accessibility text of the JSON preview. Test replacement only against that
synthetic file: cancel should preserve a sentinel edit; confirm should restore
the exact preview bytes. Quit the fixture when finished.

The native proof performed on 2026-09-04 verified the review gate, cancellation,
546-byte exact output, overwrite cancellation and confirmed replacement. Failure
injection and the parent Logs filter-to-preview route remain separate checks.

For the parent route, launch the closed fixture with:

```sh
open -g .build/native-export-proof/DarkbloomExportFixture.app --args --logs-route
```

The two synthetic events have different sources/severities. Native selection of
Source = Legacy must leave one row and produce one legacy event in Preview export,
with `source_status = last-known` and the original source timestamp. Adding
Severity = Error must leave no matches and disable Preview export. These picker
checks passed on 2026-09-04 without saving a file. Direct accessibility assignment
to the text field did not update its SwiftUI binding and is not text-entry proof.
Do not issue keyboard events unless the fixture is confirmed foreground; prefer
targeted accessibility actions. Actual keyboard search and failure injection
remain separate checks.

## CLI 0.9.7 settings fixture

`CLI097Fixture.swift` hosts the production extras settings and slot explanation with an in-memory actor. It reads no provider files, starts no collectors, and its Save/Enable/Disable actions only alter synthetic data. It is not shipped.

With the current Xcode SwiftPM build layout, after `swift test`, compile it with:

```sh
swiftc -target arm64-apple-macosx14.0 -parse-as-library -I .build/out/Products/Debug Tests/NativeUI/CLI097Fixture.swift Sources/DarkbloomMonitor/ProviderExtrasStore.swift Sources/DarkbloomMonitor/ProviderExtrasViews.swift Sources/DarkbloomMonitor/Components/SlotCard.swift .build/out/Products/Debug/libDarkbloomTelemetry.a -lsqlite3 -o /absolute/path/to/CLI097Fixture.app/Contents/MacOS/CLI097Fixture
```

Supply a normal local app Info.plist with executable `CLI097Fixture` and identifier `dev.darkbloom.cli097fixture`. Native review on September 21 verified the corrected single-line idle field, typed 60-minute draft, Save becoming enabled then disabled, reread summary and restart-required feedback, MTP automatic-to-enabled state, and unknown feature read-only presentation. All changes stayed in the synthetic actor. This proves those view interactions, not live provider setting writes or macOS removable-volume access.

## Models fixture

`ModelsFixture.swift` hosts the production model editor with an in-memory controller. It never reads provider files. Its Save action changes only synthetic values; Finish simulated work changes only fake activity. Compile against the debug telemetry library with ModelManagerView and ProviderControlStore. Use a separate app identifier and keep the synthetic banner visible.

Native review verified populated cards, Capacity selection, unsaved changes, refresh preserving the draft, and synthetic save. This is interaction proof, separate from real CLI/configuration integration tests and live drive access.

## Full dashboard fixture

`DashboardFixture.swift` hosts the unchanged production `DashboardRootView` and
all its destinations/settings. Build after the current project debug test/build
has supplied `.build/out/Products/Debug/libDarkbloomTelemetry.a`:

```sh
python3 Tests/NativeUI/build-dashboard-fixture.py
open -g '.build/native-dashboard-fixture/Bloomy Dashboard Fixture.app'
```

The fixture uses `NSHostingController` inside an AppKit `NSWindow` with the same
titled/closable/miniaturizable/resizable style and full-screen-primary policy as
production `DashboardWindowController`. Its synthetic banner sits above the
unchanged dashboard root. It does not use SwiftUI `WindowGroup`, whose native
title-bar/scroll-edge policy can differ and confound a production comparison.

The standalone compiler does not invoke SwiftPM or its build lock. Its small
output stays under `.build/native-dashboard-fixture`; `--output /absolute/path`
can select another task-owned output directory. The builder records original
production source hashes, the linked telemetry library hash, the fixture binary
hash, and the exact compiler command in `fixture-manifest.json`. Rebuild after
source changes and identify this manifest when recording native proof.
Existing output directories are rejected before copying or compiling; use a
fresh `--output` path for each retry/rebuild and preserve failed outputs until
their diagnostics and review provenance are no longer needed.

The persistent orange banner identifies synthetic review, disabled CPU/GPU
collectors, and the actual local Mac name/host thermal state. Scenario switches reconstruct the
injected stores. **Fresh** supplies synthetic CLI 0.9.17 telemetry and refreshes
the synthetic state/control evidence every five seconds, preserving model drafts.
**Stale** retains last-known telemetry/extras and simulates failed follow-up
capacity/catalog/pricing/network-history reads. Its provider-control inventory
omits expired daemon state and loaded model IDs before building cards, matching
`ProviderControlService`; retained catalog/local files do not establish current
residency. **Stale catalog** retains catalog/local inventory while runtime state
and residency stay fresh, covering this independent source-quality combination.
**Offline** supplies a current synthetic stopped-provider state with no current
model, residency, slots, advertised models, or memory-capacity reading and with
matching current authoritative synthetic CLI status reporting `Stopped` at the
same capture time. Both stopped-source observations renew every five seconds;
they establish a known stopped state without serving evidence. Account, network,
loaded-model, and extras sources stay unavailable. The synthetic Bonsai catalog uses
the actual `ternary-bonsai-2-27b` ID so model alias presentation is exercised.
The banner controls switch Light/Dark and window content sizes 800 × 560 and
1280 × 900. Appearance settings share the same isolated preference suite.

For a bounded AppKit keyboard-focus diagnosis, enable the banner's **Focus trace**
checkbox, or launch the fixture executable with `--focus-diagnostics`.
The checkbox defaults off without the flag; its tooltip shows the exact file
path. Trace records stay in the session's task-owned temporary directory as
`BloomyDashboardFixture-*/focus-diagnostics.jsonl`, with one JSON record per line.
When disabled the diagnostic writes nothing. It captures one ready-view sample
after first enabling, then immediate before/after samples
for the first **24** Tab, Space, or arrow key-down events delivered to the fixture
window. Turning the checkbox off/on does not reset the per-process event budget.
Only a sample event ordinal is stored; key codes, modifiers, typed characters,
control labels/values, accessibility contents, credentials, and user data are
omitted. Record the controlled action sequence separately to match ordinals to
the tested keys. The diagnostic consumes no events, moves no focus,
and changes no key-view or OS keyboard settings. It has no timer or observer.

Each sample includes the native first and initial responders, the existing
Full Keyboard Access and automatic key-view-loop recalculation states, and up to
384 native views with class, parent,
window-relative geometry, hidden/enabled state, `acceptsFirstResponder`,
`canBecomeKeyView`, and `nextKeyView`/`nextValidKeyView` edges. Native table/outline
views also report row count and selected row indexes. View IDs are local to one
sample; compare class, geometry, and ancestry across samples. The raw and valid
key-view loops start at the current native first-responder view (falling back to
initial responder/content) and stop at a cycle, nil, or 64 views. Truncation is
explicit. SwiftUI can manage focus inside a single native hosting view, so a
native loop alone does not establish SwiftUI's internal focus order. The
after sample is synchronous with `sendEvent`; a deferred SwiftUI change may
first appear in the next before sample. Diagnostic sampling adds work to key
handling and is evidence about focus membership, not interaction performance.

To diagnose a skipped sidebar, preserve the same manifest, scenario, appearance,
window size, and initial selection. The diagnostic checkbox is an additional
banner focus stop. Traverse from the banner controls using Tab
until the first detail control receives focus, then click a sidebar row and use
Down/Up and Space. Compare the responder and native list geometry in those
samples. If the list is absent from the native tree, inspect the SwiftUI hosting
boundary; if present but ineligible or skipped by valid edges, inspect those
native eligibility/loop differences. If eligible and reachable in the native
loop while Tab still skips it, investigate SwiftUI's internal focus traversal.
Do not treat this instrumentation as a production fix or repeat already-failed
`.focusSection()`/`.focusable()` trials without new causal evidence. Rebuild the
fixture after changes and disable tracing for normal review proof. Quit the
fixture before removing its trace together with other task-owned session data.

The Stale catalog scenario also renews runtime evidence every five seconds while
preserving its stale catalog/local-inventory source flags. The fixture naturally
inherits the host's existing reduced-motion preference. SwiftUI exposes that
environment value as read-only, so the attempted fixture override is unsupported;
controlled Reduced Motion proof remains pending.

**Popup** opens the unchanged production `MonitorPopover` in an actual transient
`NSPopover`, configured with production's 560 × 430 content size and anchored to
the fixture button. Its Available disclosure uses the same isolated preference
suite, and its theme/control environment use the existing fixture dependencies.
The native delegate owns one visible-fan observation token; SwiftUI child fan
polling is disabled to avoid a duplicate subscription. Closing releases the
token; reload/scenario replacement and app termination additionally await the
cancelled polling task before replacing stores or exiting. Dashboard, Settings,
Models, and Hosting actions close the popup then route into the existing fixture
window. Keep the synthetic banner visible behind popup proof captures. This
proves native popup behavior, not placement beneath the production menu-bar item.

Rapid popup toggles retain every cancelled reader until it has been joined;
cleanup awaits AppKit's native close-completion event before draining outstanding
readers or dropping hosted content. A close waiter is registered before closure
is requested, and reopening is blocked while the native close is in progress.
If reopened while readers are being joined, cleanup awaits that close too.
Scenario loading owns one serialized
preparation task, captures the requested scenario/generation, cancels and joins
the previous preparation, and publishes completed stores only for the current
request. Rapid scenario changes cannot start two history seeders or let an older
request mark newer work ready. Termination also cancels and joins pending loading.
The fixture cancels the first native Quit request, starts one owned cleanup task,
then retries termination after cleanup has completed. Repeated Quit requests
reuse that task. This avoids a nested AppKit termination wait blocking cleanup
on the main actor when Quit originated in the popup's asynchronous action.
Native clean-quit behavior must be verified against the newly built fixture;
the previous fixture's hanging Quit is not proof of production behavior.

Popup model actions use the in-memory provider actor; fan mutations remain
unsupported/rejected; Nudge uses in-memory credentials with actions disabled.
The actor initially enables startup preload for its two saved preload models and
retains selection, slots, startup preload, and concurrency on save/readback, so
the Auto sheet can confirm a saved single-model startup plan without serving.
Its CLI update store uses the existing staged inert dependency. No additional
production substitutions are needed. One presentation limitation remains:
the production finance panel directly reads `UserDefaults.standard` for a
read-only electricity-enabled check. In this separate bundle that is the fixture
application domain, not the session suite, so its electricity settings-link
visibility may differ from the synthetic session toggle. It performs no write
and does not start power acquisition. Production credential-oriented text still
describes Keychain, but fixture Save/Remove operations remain memory-only.

Each process uses a unique `dev.darkbloom.dashboard-fixture.session.*` defaults
suite, a unique temporary `BloomyDashboardFixture-*` directory, 360 synthetic
performance samples, and 48 synthetic action events. History includes intentional
stale gaps and `waiting_inventory` phases. Single-model active visits increase
provider counters; a fully bounded, singly resident 90-second Bonsai idle visit
keeps request/token counters flat across its observed load and switch-away
boundaries so the no-observed-work panel is populated. These are synthetic
observation statements, not claims about real provider work. All seeded counters
stay monotonic and below the fresh scenario's cumulative counters.
Reloading a scenario retains its seeded
histories. Provider/configuration mutations use an in-memory actor; chat replies
use an in-memory client; consumer/local endpoint tokens are kept only in fixture
memory. `MonitorStore.start()` is never called. CPU, GPU, adapter power, LAN scans,
local-provider files, live logs, account APIs, and real Keychain access are absent.
Electricity settings remain navigable, but no power acquisition starts.

Three production default dependencies require fixture-only staged substitutions:
`CLIUpdateStatusStore.shared` uses `FixtureCLIUpdates`, because the production
update notice view starts that shared store; `SystemCPUUsageStore` defaults to a
nil reader, because the production resources view owns/starts its CPU sampler;
`NetworkCacheStore` defaults to `FixtureNetworkCache`, because expanding the
Infrastructure disclosure starts cache-health polling. Cache-health results are
synthetic shadow/planner-ready values in every fixture scenario.
All destination view bodies stay unchanged. The production app entry point is
excluded; Sparkle is linked for its unchanged settings view, but never started,
and the fixture plist has no update-feed configuration. These substitutions are
checked for exact matches and recorded in the manifest. Production files are
never modified by the builder.

This fixture proves layout and synthetic interaction paths. It does not prove
live provider controls, real credential/storage access, telemetry collection,
actual CPU/GPU/power behavior, provider availability, or distribution readiness.
Quit the fixture after review. Retain its manifest and task-owned evidence for
provenance; temporary histories may be removed only once review no longer needs
them and the fixture has quit.
