# Production Settings preview lifecycle — October 7, 2026

The unchanged production DashboardWindowController and DashboardRootView pass
all seven bounded Settings preview cases with synthetic activity. Normal and
rapid retained-window reopening keep the same native view/layer, one rotation
clock and advancing compositor angles. Cancellation stops departed clocks,
closes the owned production window and lets the fixture process exit. This adds
actual-route evidence; it is not a production animation repair or completion of
the broader native/release matrix.

## Scope and isolation

The opt-in `--settings-preview-proof` builds a dedicated guarded helper and
review-console button. The helper uses the production controller's own
navigation and `present()` method. It observes the actual MenuBarStatusView
inside Settings → Menu Bar, scanning only that window's content tree. It never
constructs a surrogate indicator host or replaces its SwiftUI root.

The production review window has a unique preference suite and a never-started
MonitorStore with synthetic daemon/earnings clients, providerExtras:nil, inert
GPU and energy readers, no control/hosting/chat stores and no frame autosave.
Its controller is the sole visibility owner for that store. The existing
console retains its separate store, preferences and observer. Store.start() is
never called. No provider command, model operation, network inference, credential
read/write or production app restart was performed.

Each case publishes fresh explicit activity before its transition. There is no
publication after minimize/close to rescue reopening, and no publication during
the compositor hold. Current-source assertions use the ten-second activity
limit. Motion reads require an attached visible 18-point arc, intersecting native
visible rect, visible/non-minimized AppKit window, dashboardVisible true, exactly
one infinite 1.4-second rotation and stable native identity/geometry. Successful
angle observations record freshness and native/window evidence.

The helper issues only supported navigation, minimize, close and production
presentation actions. It adds no forced configure, animation mutation, layout,
display, flush, visibility notification or recovery retry. Page departure
requires zero arcs and stopped old clocks; return requires a new native view and
layer. Minimize and close require dashboardVisible false and stopped clocks.
Final success also requires verified stopped retained clocks and closure of the
owned production controller. Normal fixture code and its original fifteen-case
Native proof are unchanged when the opt-in definition is absent.

## Investigation boundary

A preliminary run used the console's FixtureWindow/root and imitation
presentation path. It passed five cases but both close/reopen cases failed their
visible prerequisite with AppKit occlusionVisible false. Fresh input and retained
identities were present; clocks were stopped as required for occlusion. A later
read-only WindowServer inspection found ChatGPT above and geometrically covering
the target (own window 29068, PID 79071). That later observation is context, not
a timestamped proof of the cause of both failures.

This exposed an important host difference: production uses NSWindowController's
showWindow path and its actual sizing/presentation owner. The final run therefore
uses that class and unwrapped production root. The preliminary result is retained
and is not presented as an animation bug or as a passing gate. The final change
tests the real host; it does not establish which host/environment difference
caused the earlier failure.

Read-only review caught two visibility observers writing one shared store in an
intermediate setup. The final separate store and visibility assertions resolve
that diagnostic defect before execution. Review also tightened departure from
an ambiguous missing-host test to an explicit zero-arc requirement. Early
compile failures involved CGFloat text conversion and a PID integer conversion;
neither failed artifact was executed.

## Native results

CUA launched the exact optimized final app, clicked Settings preview proof and
inspected the actual Settings screen and terminal console result. The production
screen has no review banner; the separate console identifies the inert session.
The inspected screen was wide/light. Dark/compact/fan update qualification is
not newly claimed here.

| Case | Result | Compositor-only hold |
| --- | --- | --- |
| Actual Settings baseline | Pass | 1.723 s |
| Ten fresh updates | Pass, same clock/view/layer | 1.707 s |
| Active → idle → active | Pass, stopped idle clock | 1.767 s |
| Navigate away and return | Pass, old clock stopped/new native host | 1.767 s |
| Minimize and restore | Pass, same native host | 1.704 s |
| Retained close and reopen | Pass, same native host | 1.807 s |
| Rapid close and reopen | Pass, same native host | 1.745 s |

All seven post-hold angular advances exceed 0.1 radians (0.101–0.141). Successful
case source ages are 1.78–2.99 seconds. The two native hosts retained as departure
evidence have no animation keys at cleanup. The actual window is closed and its
store is display-disabled before the final result is written.

A second invocation uses a separate UUID directory. CUA Quit while the finite
proof was running results in terminal cancelled, passed false, four passed cases
and three explicitly cancelled cases. Cleanup and productionControllerClosed
are true. Main independently confirmed owned PID 81659 absent after Quit; no
post-Quit CUA observation was made that could relaunch it.

AppKit reports the actual window visible and on the active space; filtered
WindowServer entries independently match its number, owner PID, bounds, alpha
and on-screen identity. ApplicationActive and keyWindow are false in this run.
The filtered entries do not establish stacking against every external window.
These are bounded AppKit/layer/identity observations, not physical foreground
pixel motion or a genuine opaque-cover occlusion test.

## Evidence and checks

Final artifact: `.build/settings-preview-production-verified-20261007`.

- Binary SHA-256: `fa2bba7ccf90bac849fd5ac2047746c62df56889c91461407fa270490ea90483`.
- Manifest SHA-256: `d6edc78cfe41c5ac515d2ce606b0fee46229e6164923580c06054a54e012166a`.
- Completed report: `runtime-evidence/E6737D08-40B2-4CCE-8392-A7FDAB5EEAD2/settings-preview-result.json`, SHA-256 `8e026573345386d19324d29b2a65587b5660f1155833a8179056f1ce9435b449`.
- Cancelled report: `runtime-evidence/A6A62482-52F9-4324-A99B-BF9928BBE9D3/settings-preview-result.json`, SHA-256 `2e103c67b23e7eaf198225fc8a24cd5092168684b3b6fd2930b67d62d00b1581`.
- `runtime-summary.json` indexes holds, result hashes, cleanup and confirmed process absence. The manifest contains 121 current source hashes and the immutable linked telemetry library.
- Ordinary optimized control: `.build/settings-preview-production-control-20261007`, binary SHA-256 `f02b726657bf064e7c450313f9827438225478a720d4c1deb1581a8ce0143c2f`. The diagnostic definition is absent. Both optimized builds compile at exit 0.
- Production controller, root, label, shared status view and Settings legend bytes exactly match current source in both builds. The previously dirty MenuBarMotionProof bytes remain untouched.
- Fifteen staging regressions pass. Four conflicting diagnostic/banner combinations are rejected before staging. `git diff --check` passes. No fresh full package suite is claimed for these fixture-only changes.

The preliminary console-host artifact and its 5/7 report are preserved under
`.build/settings-preview-verified-20261007/runtime-evidence/08285DB7-F630-4BB6-B23C-AEE939DBC9DB`, report SHA-256
`520371855ecc4db61bbfe703a8b4cd8e7b3744c81a695a99c131ab5e9cbb42f5`.

## Remaining work

The original standalone fifteen-case gate and genuine opaque-cover observation
remain unresolved. This actual Settings-route check and the separate passing
production status-item check do not replace that gate or establish resource,
spoken VoiceOver, Reduce Motion transitions, fan/GPU updates, other displays or
installed-release behavior. The broader completion matrix remains open. Product
sources, provider configuration, cache, credentials and unrelated dirty work are
preserved; the provider stays stopped.
