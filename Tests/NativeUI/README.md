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
collectors, and the actual host thermal state. Scenario switches reconstruct the
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
The Stale catalog scenario also renews runtime evidence every five seconds while
preserving its stale catalog/local-inventory source flags. The fixture naturally
inherits the host's existing reduced-motion preference. SwiftUI exposes that
environment value as read-only, so the attempted fixture override is unsupported;
controlled Reduced Motion proof remains pending.

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
