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
The AppKit delegate forwards initial presentation, close, minimize, and restore
to the current injected store's dashboard visibility; scenario/reload replacement
inherits the latest window visibility. This permits native Metrics checks of
hidden query/analysis cancellation, suspended timeline scheduling, and resumption
after restore. It does not establish production telemetry polling behavior:
`MonitorStore.start()` remains unused, and the fixture's five-second synthetic
refresh continues independently of dashboard visibility.
The fixture's native Edit menu uses production's responder-chain commands and
shortcuts for Undo, Redo, Cut, Copy, Paste, and Select All. Focus a synthetic text
field before testing Command-A and typing; these actions edit that field through
AppKit rather than assigning its accessibility value. Window > Minimize uses the
native window responder. Window > Show Dashboard, Dock reopen, and the popup's
Open dashboard action restore the
same owned window and visibility without reconstructing the stores or starting
collectors. Generic dashboard presentation preserves the selected page; explicit
Settings, Models, and Hosting routes still select their requested page.
These fixture menus contain only editing, native-window, and Quit
commands plus a synthetic inventory-removal command; production update/provider handlers are not installed. Use the menu
minimize/restore route for Metrics lifecycle review, with tracing disabled for
normal timing proof.

The standalone compiler does not invoke SwiftPM or its build lock. Its small
output stays under `.build/native-dashboard-fixture`; `--output /absolute/path`
can select another task-owned output directory. The builder records original
production source hashes, the linked telemetry library hash, the fixture binary
hash, and the exact compiler command in `fixture-manifest.json`. Production
source hashes describe the same bytes staged before dependency substitutions.
The fixture source and linked telemetry library are also copied into the staging
directory before compilation, so the manifest identifies the compiled snapshot
even if their original paths change afterward. Rebuild after
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
**Expired settings** keeps runtime telemetry current while successful extras
reads are backdated by 90 seconds, beyond the 45-second editing window.
**Expired helper** keeps the CLI capture current but backdates the helper journal
by 90 seconds and omits diagnostic readings, exposing the last-known fallback.
**Unavailable settings** supplies first-read failures with no prior good extras
data; it does not imply an unsupported CLI. All three scenarios use inert clients
and their Refresh actions preserve the selected condition.
**Partial cooling** keeps the CLI capture and diagnostic temperature current,
but expires a two-fan helper journal. The diagnostic includes fan 1 metadata
without RPM and a measured fan 2 RPM, exercising per-fan retention and freshness.
**Disabled helper** supplies current readings with helper enabled=false and
providerActive=true, exercising precedence of the disabled state.
**Unavailable runtime** has no daemon observation or authoritative stopped
status; it must show unknown activity rather than a stopped zero or Last report.
**Aliased startup** uses one slot, the catalog's unique `gpt` enabled family
alias and the independent exact `gpt-oss-20b` preload selector. It exercises the
startup picker without rewriting saved aliases merely to display them.
**Reported local endpoint** selects Local only and makes an explicit discovery
check return a fake loopback record on port 8123 with no bearer token. No socket,
provider or endpoint is started. Terminal-command copying is injected as an inert
successful result; it does not overwrite the user's clipboard. Do not use the
URL-copy action when preserving that clipboard is part of a review.
These are inert presentation scenarios, not changes to a running provider.
The banner controls switch Light/Dark and window content sizes 800 × 560 and
1280 × 900. Appearance settings share the same isolated preference suite.
The fixture applies that appearance to its own `NSApplication`, matching the
production appearance policy without changing macOS or the running production
app. Chat's production pop-out controller is connected to a separate owned
460 × 520 window, with its own draft and no frame-autosave key. Its title includes
Synthetic Review. The Chat verification menu can echo the user's synthetic text
or hold a cancellation-aware reply for 30 seconds to check speaker names, shared
send state, Cancel, and route replacement. No inference or socket is involved.
Another choice supplies two synthetic vendor IDs with the same short model name
to check canonical selection identity in the native menu and response provenance.
Replacing a fixture Chat store closes its owned pop-out and cancels the prior
inert send before publishing the replacement; it cannot leave two review stores
serving different conversations in visible windows.
For the Cancel focus regression, start **Held reply for 30 seconds**, focus the
message editor, type a synthetic message and send with Command-Return. Confirm
the held send is active, then use Control-Tab to reach the actual Cancel button.
Space followed immediately by typing, without an intervening observation, must
cancel the send and place that text in the same composer while leaving sidebar
selection unchanged. Inspect both the Cancelled transcript phase and the draft;
typing after a reply completed or a skipped Cancel does not prove this case.
Repeat in the dashboard and pop-out. Pressing Cancel through AX while the editor
still has focus is a separate path and cannot reproduce removed-button focus.
Data checks → **Chat Cancel focus proof**, enabled on Overview, runs four finite
cases in two separately owned Chat views sharing an inert store. First use the
fixture's native Window → **Show Dashboard** command so it is actually active;
raising its window alone does not establish that prerequisite. The JSON records
actual app/key-window/responder context, exact Cancel accessibility focus, the
existing native editor, independent drafts, completion/external-cancel sentinel
focus, and terminal send/window/host/deadline cleanup. Missing native focus or
key-window evidence fails the proof. Held completions handle cancellation before
and after registration, and shutdown rejects queued late calls. Quit cancels and
joins the proof. This native key-loop/AX-press check complements the real keyboard
sequence above; it does not synthesize OS keyboard input or prove VoiceOver.
The Data checks menu can reduce the synthetic Earnings report to Qwen (use the
actual Earnings Refresh afterward), constrain the model sheet to 360 points, or
remove Gemma from synthetic inventory. Window > Remove Gemma from inventory
(synthetic), also Control-Option-Command-R, permits that last change while the
Manage sheet is open. It only changes in-memory fixture records and preserves
staged provider drafts. Scenario replacement restores its initial fake records.
Each prepared scenario seeds 48 immutable synthetic log payloads. Ordinary
five-second telemetry ticks advance source capture dates and runtime state while
retaining those payloads, timestamps, and Logs row identities. Explicit inert
source reads use the same retained feed. Data checks → **Prepend one synthetic
log event** adds one distinctly named Notice event at the front; existing events
retain their order and identity until the normal 100-event bound drops the oldest.
Fixture publications are serialized so an in-flight tick cannot overwrite a
new arrival. Reload/scenario replacement seeds a new feed and resets arrivals.
The arrival action is disabled for stale/offline/unavailable runtime, Frozen
settings, network expiry review, and native proofs; it cannot turn unavailable
evidence into a fresh feed or disturb a controlled expiry interval.
For sustained Logs selection review, select an older visible event, leave it
selected across multiple five-second ticks, then prepend an arrival and inspect
the unchanged selected details. Apply a filter that retains that selected event,
then one that excludes it, to check the production selection policy. This is a
repeatable synthetic review path, not proof of live log collection.
Network expiry review reconstructs the inert stores with one capacity capture
100 seconds in the past and pauses synthetic source ticks. The normal 120-second
network freshness rule and production visible clock must show its remaining
20 seconds of current evidence expiring without an unrelated publication. Ending
this review reconstructs ordinary synthetic stores; it does not alter OS time.
The isolated suite starts with an unsupported idle-alert value of 99. Menu Bar
must display the policy's effective five-minute choice without silently
rewriting the saved value; an explicit choice still updates the isolated suite.
Binding tests verify raw-value preservation independently of native display.
**Static menu-bar activity** asks the review label to retain a stationary active
arc. The native arc also honors the Mac's own Reduce Motion preference; this
control cannot force animation against that preference. SwiftUI's system
accessibility environment values are read-only, so this is an explicit view
input rather than a system-setting simulation. **Grayscale** desaturates the
synthetic dashboard, popup, and review menu-bar label. Both controls last only
for this fixture session and leave the Mac's preferences unchanged. They do not
establish actual VoiceOver behavior or system preference delivery.

The fixture owns a separate 80-point native status item, using the production
three-ring label and freshness deadlines with synthetic provider/fan readings
and unavailable GPU usage. The banner's **Popup** action opens from this genuine
menu-bar anchor, rather than from a button near the dashboard's upper edge.
It uses the production fitting controller to set the popup's preferred size
before presentation and respond to later disclosure changes. Opening from a
real menu-bar anchor alone does not prove correct sizing: inspect the bounded
`popup-geometry.jsonl` records and the rendered header/body together. Enable
**Focus trace** to record geometry (at most six records per popup controller).
**Popup height** selects the actual screen budget or synthetic 360-, 240-, and
80-point budgets. It does not change the Mac's display or preferences. Check
Available expansion/collapse and scroll to the last footer control; a bounded
fitting size alone does not prove reachability. Extremely short budgets must
permit scrolling the whole popup, including its header and Cooling/Auto/Nudge
controls. Quit and relaunch the owned fixture for a new bounded trace once
its record limit is reached. The synthetic budget checks do not establish fit
on every physical display or screen-transition behavior.
The outer layer uses a native scroll view with an explicitly measured SwiftUI
document; its overlay scrollbar preserves the model-card width. At ordinary
budgets only the model body scrolls. At very small budgets check both nested
areas and return to the header. Reopen Auto/Nudge/Cooling and verify a fan draft
survives Refresh and sheet reopening; the test host must remain inert throughout.
The production status item is untouched. Quit joins the fixture's popup and
reader cleanup, then removes only its own item.

The banner's **Native proof** button runs three finite helpers inside this app's
normal `NSApplication` event loop: `MenuBarMotionProof.swift`,
`ModelManagerAccessibilityProof.swift`, and `ChartAccessibilityProof.swift`.
They create only synthetic, task-owned windows and controllers. The motion
helper checks real compositor advancement and window lifecycle; model/chart
helpers inspect and press actual accessibility controls. No helper pumps a
private event loop, starts the provider, reads a key, changes a Mac preference,
or performs network inference. Keep the dashboard anchor open and avoid
interacting with proof windows until the button reports completion.
The cover-occlusion case starts one child of the staged fixture executable in
an inert cover-only mode, dispatched before dashboard dependencies are created.
It validates the requested frame, owns one opaque window, and has an eight-second
self-timeout. The parent checks actual window ordering, coverage, occlusion and
animation removal, then requests closure and records the child's exit. It never
uses another application as a cover or treats window geometry as occlusion proof.

Each helper writes a bounded JSON report to the temporary directory shown in
the button's help. `native-proof-result.json` records all three terminal results;
an exit code or a partially written report is not a passing native proof. Review
failures and missing cases rather than treating an attempted check as success.
The build manifest hashes the staged helpers, production sources, telemetry
library, and final binary. This normal app host is necessary because SwiftPM's
rendering host does not reliably expose the SwiftUI accessibility tree.

Quit only this fixture when finished and confirm its process has stopped.
Do not request another automation snapshot of the closed fixture: the native
automation adapter may relaunch an app while resolving a new observation.
The fixture injects retained nonsecret dashboard Chat/Hosting/settings and popup
fan drafts, plus the same boolean-only mounted-editor protection registry used
by production. Use ordinary navigation, Refresh, sheet dismissal/reopening,
and local Discard controls to inspect recovery. It does not install Sparkle or
include the production app delegate; actual relaunch-guard coverage belongs to
`AppUpdateWorkProtectionTests`. Never paste a real key into this fixture.

### Controlled Chat verification

The second synthetic banner row contains **New synthetic local chat**. Each
menu action explicitly replaces the fixture's chat store and opens a new empty
local conversation; it discards the previous synthetic conversation and its
draft. Use it before typing a draft, never during a draft-preservation check.
All model reads and completions remain inert. The choices are:

- **Fresh verification**: current model-list capture time.
- **Verification expires in 10 s**: only the first response is backdated by
  110 seconds. The production 120-second verification window therefore expires
  after about ten seconds of actual elapsed time. Later reads return a fully
  fresh list. The fixture does not publish chat ticks or run an expiry timer.
- **Verification already expired**: first response backdated by 121 seconds;
  later reads return a fresh list.
- **Verification fails** and **Empty model list**: repeated reads respectively
  throw the synthetic offline error or return a successful empty list until
  their response mode is explicitly changed.

**Next verification read** changes only that controlled client's response mode;
it does not refresh, start a conversation, change the route, send text, or touch
the draft. Use the production Chat **Refresh** button afterward. It is disabled
until a controlled chat exists and during a refresh/send. Selecting a backdated
mode in an already freshly verified store can correctly be ignored by the
production rule rejecting older snapshots; use **New synthetic local chat** to
test the initial aged response instead.

For native expiry proof, start the ten-second chat, immediately type a short
unsent message, and observe the verification status and Send availability
change after the deadline without typing or clicking. Verify the exact draft
remains visible. Click production Refresh and verify current verification and
Send recover with the same draft. Repeat with a new aged chat while navigating
away/back and while minimizing/restoring the owned fixture window. This checks
visible lifecycle recovery, not provider activity or timing under real network
latency. The separate five-second monitor/control refresh is unchanged and does
not refresh `ChatStore` model snapshots; do not treat it as the expiry mechanism.

For failure proof, start a fresh controlled chat, type an unsent message, choose
**Next verification read > Verification fails**, then production Refresh. Check
the failure wording and Send state; repeat Refresh to ensure an old successful
list does not disguise the failure. Choose **Next verification read > Fresh
verification**, then production Refresh, and verify recovery without draft loss.
Repeat with **Empty model list**, including starting a new empty-list chat to
verify the absence of any available selection. No consumer key is required for
these local checks. Controlled states and this procedure provide review inputs;
record actual native outcomes separately rather than claiming proof from the
fixture implementation alone.

For a bounded AppKit keyboard-focus diagnosis, enable the banner's **Focus trace**
checkbox, or launch the fixture executable with `--focus-diagnostics`.
The checkbox defaults off without the flag; its tooltip shows the exact file
path. Trace records stay in the session's task-owned temporary directory as
`BloomyDashboardFixture-*/focus-diagnostics.jsonl`, with one JSON record per line.
When disabled the diagnostic writes nothing. It captures one ready-view sample
after first enabling, then immediate before/after samples
for the first **24** Tab, Space, or arrow key-down events delivered to the fixture
window. Ready, key, presentation, minimize, and restore samples share a maximum
of **49 records**. Lifecycle samples require the trace to be enabled and ready;
they can use part of the key-event budget. Turning the checkbox off/on does not
reset either per-process budget.
With the same opt-in control, `menu-bar-motion.jsonl` records up to 48 changed
states of the fixture's own native status item: requested stationary activity,
system Reduce Motion, actual window/view visibility, whether the active arc is
visible, and whether its rotation is installed. It reads the native layer after
rendering; it adds no clock, records no control text, and never inspects another
application. Installed animation state is distinct from compositor advancement,
which the finite native rendering test checks separately.
Only a sample event ordinal is stored; key codes, modifiers, typed characters,
control labels/values, accessibility contents, credentials, and user data are
omitted. Record the controlled action sequence separately to match ordinals to
the tested keys. The diagnostic consumes no events, moves no focus,
and changes no key-view or OS keyboard settings. It has no timer or observer.

Each sample includes the native first and initial responders, the existing
Full Keyboard Access and automatic key-view-loop recalculation states, native
window identity/frame and minimized/visible flags, and up to
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

This trace samples only the owned dashboard window, not SwiftUI sheets or native
export panels. It excludes Return and Escape. Do not infer sheet key delivery
from the main window's responder or `isKeyWindow` flag. In computer-use checks,
target the current sheet/panel and use its exposed native Raise action before
keyboard input, then inspect actual checkbox/focus/dialog changes. A fresh
native 22 session verified Support's Space, Tab cycle, Return review gate, and
Escape cancellation this way without changing production focus code.

To diagnose a skipped sidebar, preserve the same manifest, scenario, appearance,
window size, and initial selection. The diagnostic checkbox is an additional
banner focus stop. Traverse from the banner controls using Tab through a full
focus cycle, recording every stop, including those after the first detail
control. The native13b trace reached the sidebar one stop after the Overview
detail control; reaching detail first does not prove the sidebar was skipped.
At the sidebar stop, use Down/Up and Space and compare the responder, selected
rows, and native list geometry. Only diagnose skipping if a complete controlled
cycle fails to reach the list; if the 24-event budget is exhausted, start a fresh
process and record a bounded continuation from a known stop. If the list is
absent from the native tree, inspect the SwiftUI hosting
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
The initial Fresh inventory includes two downloaded, unselected, unloaded models,
Bonsai 2 27B and Qwen 3 8B, for native Available disclosure/card proof. Their
sizes and memory requirements are synthetic examples. Gemma, GPT-OSS, and Qwen
3.8 remain the three enabled/advertised models; the saved two-model preload and
Auto sheet behavior remain intact. Catalog/local freshness still follows the
selected scenario; downloaded files do not establish current residency.

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
The fixture uses production's `ApplicationTerminationGate` to cancel the first
native Quit request and start one owned cleanup task,
then retries termination after cleanup has completed. Repeated Quit requests
reuse that task. This avoids a nested AppKit termination wait blocking cleanup
on the main actor when Quit originated in the popup's asynchronous action.
Native clean-quit behavior must be verified against the newly built fixture;
the previous fixture's hanging Quit is not proof of production behavior.
Shared-gate native proof still uses synthetic stores. Owned subprocess shutdown
and production delegate integration have separate regression evidence; this
fixture does not start a live log reader or provider.

Hosting token-copy actions use an inert success sink; neither the fixture nor
its store regression tests write synthetic credentials to the user's clipboard.
Popup model actions use the in-memory provider actor; fan mutations remain
unsupported/rejected except for Configure in the explicit **Fan confirmation**
scenario. That action records only the submitted policy in the same fixture
actor and returns successfully. The **Fan readback** menu selects original,
failed, or matching readings without replacing the draft or store. Failed reads
persist through visible fan polling until another menu choice. A fixture-owned
`fixture-fan-proof.json` records the submitted values and command count after
each explicit readback choice; confirmation should require only one command.
No fan helper, administrator prompt, or real fan control is used.
Nudge uses in-memory credentials with actions disabled.
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

**Frozen settings** retains the initial idle/beta capture time and suppresses
the fixture's periodic telemetry publication. Leave Provider settings visible
to observe its real 45-second expiry without another read. **CLI check** selects
current, two-day-old retained, or failed synthetic update checks in the same
shared store. These controls perform no network calls, installation, or restart.

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
The inert client writes `network-cache-read-proof.json` in the fixture's unique
temporary directory. It starts at zero and records only the count and timestamp
of fake reads. Use it to verify Infrastructure disclosure, route, and window
visibility behavior; no additional polling clock or live request is introduced.
From Overview, Data checks → Cache visibility proof runs five finite native
checks in one task-owned window. It verifies initial reading, 65 seconds without
reads after actual minimization, immediate restoration, 65 seconds without
reads after removing the child view, and immediate reinsertion. Expect about
132 seconds. The dashboard/data controls stay disabled during the proof to
prevent competing cache readers. Incremental and terminal evidence is written
to `network-cache-visibility-proof.json`; the proof closes its window and
dismantles its child on success, failure, or cancellation. Quit joins that
cleanup. This checks the real staged NetworkCacheView with inert data, not
occlusion, actual VoiceOver, or the live provider.
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

### Manage-sheet keyboard regression

From Overview, Data checks → Model keyboard proof runs three finite checks in
an owned synthetic Model Manager window with a 360-point Manage sheet. Activate
the fixture with an actual key press before starting: background accessibility
menu presses do not guarantee macOS activation. Failure to acquire the exact
owned key window is a reported failure, never a skipped assertion.

The forward and backward native key loops must reach header/footer Done, runtime,
Enabled, Preload and Details, with exact AX focus and full control-frame
visibility. Both directions must move the real scroll viewport. Focused footer
Done must close the sheet. The helper checks unchanged settings/preferences,
one synthetic refresh, zero mutations, and released window/sheet/host/store.
It is bounded to 45 seconds plus cleanup and writes incremental and terminal
`model-manage-keyboard-proof.json` in the banner's unique temporary directory.
Quit cancels and joins it; do not interact with its window during the proof.

This NSWindow key loop complements actual Tab/Shift-Tab/Space/Escape testing;
it does not establish SwiftUI's complete internal focus order, selected-text
Escape, input-method composition or VoiceOver. Preserve rejected reports before
retrying. See `docs/MODEL_KEYBOARD_NATIVE_REVIEW_20261002.md` for the accepted
bounded observations and rejected activation candidates.
