# Bloomy native UI verification — 2026-09-29

The user observed uneven popup model cards, no Available collapse, missing fan controls, and flickering GPU/text. Reproduced against installed v1.9.4 using native computer use.

## Root causes and fixes

- Compact cards sized themselves to optional metrics/actions and wrapped titles. The popup now uses equal three-column cards with reserved title space and aligned actions.
- Available was a plain heading and unconditional grid. It is now a persisted disclosure; hidden cards no longer contribute to popup height.
- Fan helper timestamps advance during the CLI read. Comparing them with the pre-command time discarded valid helper state. Freshness is now checked at command completion; genuinely future and stale helper timestamps remain rejected.
- Fresh samples can post-date TimelineView's prior tick. Freshness-sensitive views now use wall-clock time at render instead of the earlier tick.
- A failed GPU read cleared the presentation. The UI now retains the original last-good sample, dims/labels it as stale, and retains its original timestamp. Stale menu rings exclude temperature coloring.
- Fan panels include a visible Refresh readings action in both popup and Settings. Last-known fan readings remain explicitly stale instead of vanishing.

## Native walkthrough completed on v1.9.4

- Activity: bars, lines, area, earnings/profit measures, model filter and restore.
- Opportunity: refresh, Models/Network activity, requests/input/output measures.
- Chat: destination chooser and cancel; no inference or paid requests sent.
- Models: catalog, saved/live controls, model-detail sheet, forecast slider increment/decrement and restore; no configuration writes.
- Hosting: read-only environment refresh and inspection of modes, auth, and apply controls.
- Health/Logs: navigation, log export preview/close; no exported file.
- Settings: Appearance, Menu Bar, Electricity, Updates, Provider, Fans, Companion, Support.
- Provider: confirmation timing changed and restored; nudge interval changed and restored to 15 minutes; both automations remained off.
- Support: sanitized packet preview and close; no file saved/shared.
- Companion correctly reports development status.

Provider start/stop/restart, downloads/deletion, auth changes, paid inference, and administrator fan-policy writes were not executed against the live serving machine. They are not claimed as end-to-end verified by this UI pass.

## Corrected build

The first corrected native review verified equal cards, Available expand/collapse and persistence, Cooling sheet, usable fan controls, and Refresh readings. The final review additionally verifies the steady Settings refresh label, fan refresh timestamps/readings, and the idle reminder default/options in Settings.

Validation: 955 tests passed (906 telemetry/app, 21 companion protocol, 28 companion host); the two rendered card/menu-bar layout checks passed; 11 focused nudge/attention/card checks passed after the final UI corrections; the Release build passed. The idle alert fixture is synthetic visual evidence, not a claim that the live five-minute timer fired.

Current review executable: `.build/bloomy-ui-fixes-20260929-final/assembled/Bloomy.app/Contents/MacOS/DarkbloomMonitor`, SHA-256 `45d3f2aa8c75af6a75834a020ce9d6792247ac9e87498ffe0cafa3f08dd06ae3`. The running mapping matches the file inode, with one lock owner. Provider process identity and provider configuration hash are unchanged. Installed production remains v1.9.4.

Remaining native verification: final Auto/Nudge sheets and popup repeated updates await popup access. The final build's startup model-catalog read and one manual refresh timed out; no configuration or provider action was attempted with unavailable controls.

## Auto, manual nudge, and idle reminder

- Auto is now an actionable popup setup sheet. The guarded save transaction retains all selected enabled models, sets one resident slot, enables startup preload, and saves exactly one chosen preload. Alias resolution, dirty drafts, stale controls, malformed TOML, and concurrent file changes are checked. Apply Live advertises the saved set; slot/preload changes require the next provider start.
- Manual Nudge opens a sheet with an explicit Send action, eligibility/result feedback, and Keychain setup. It works independently of automatic nudge, sends at most one capped self-route request, and rechecks fresh idle state before POST. It does not consume the automatic attempt budget. With several advertised models, the API must expose the exact warm model ID; a family-only alias produces no request.
- The automatic watcher now supports multiple advertised models with exactly one warm current model, retaining the 15-minute default, base-rewards evidence, one-hour cooldown, and three-attempt daily cap.
- A separate menu-bar reminder defaults to five minutes of continuously observed eligible idle state. It uses the Bloomy mascot, an exclamation icon, and a steady short label; popup/hover/accessibility text explains the reminder. Work, process/model changes, stale/offline evidence, polling gaps, and app stop clear it. Settings offers Off, 5, 10, 15, or 30 minutes. The reminder itself sends no request.

A subsequent controlled relaunch verified review job `com.darkbloom.monitor.codex-review`, PID 19879, and a sole lock owner before attaching native UI. The catalog timeout persisted. Read-only shell diagnosis with network access completed the exact catalog command in 0.83 seconds; the local-model list completed in under one second. An earlier restricted-shell DNS error was a sandbox artifact and is not evidence of a coordinator outage. The unresolved timeout is specific to the app process/context or command runner; increasing the deadline is not justified by these checks.

## Nudge visibility follow-up

The user could not find Nudge while viewing the dashboard. Moved the popup Auto/Nudge row above the scrollable model content and added a labeled Nudge action to the dashboard toolbar. The Release build passed. Launched `.build/bloomy-nudge-visible-20260929/assembled/Bloomy.app` through the review job after waiting for the old job to unregister. Native computer use verified the toolbar Nudge button, opened its panel, and showed the Keychain setup field. Send is correctly disabled with “Add a nudge key below”; automatic remains off with a 15-minute selection. No request or credential mutation occurred; provider identity/configuration remained unchanged. The previous review's model catalog had recovered by this follow-up; the earlier intermittent timeout is not claimed fixed.

## Guided first-use setup

Nudge now shows a three-step guide automatically when its dedicated key is missing, both from the popup/dashboard action and from Provider settings. It links to the verified official API console (`https://console.darkbloom.dev/api-console`), explains the own-machine restriction, and provides masked Keychain entry with Save key and continue. Existing-key users retain the normal controls. Saving only stores the key; it neither sends nor opts into automation. Seven focused manual-nudge tests passed, including save/remove setup state without dispatch or opt-in; Release build passed. Native computer use verified all three steps, the link, the secure field, and the disabled empty-key Save action in the running `.build/bloomy-nudge-guide-20260929/assembled/Bloomy.app`. No real key was entered and no request was sent during verification.

## Completed setup clarity

After setup, the Nudge panel now shows “Setup complete · Key saved.” The saved-key section explains that manual and automatic nudges share the existing key. The empty credential form is hidden until Replace key is selected; Cancel clears the replacement draft and restores the saved-key confirmation. Removal is separate under a disclosure. The initial save message no longer suggests an unexplained cancellation. Seven focused nudge tests and the Release build passed. Native computer use verified the completed state with the user's existing saved key, opened Replace key without entering anything, canceled, and confirmed the field disappeared. The existing automatic setting remained on at 15 minutes; no key was read, replaced, removed, or manually nudged by the verifier.

## Published v1.9.5 release validation

Source commit `c9644d1bd6ed48ad85f2f8c198ba2db604f8ccef`, version 1.9.5, build 130: all 956 Swift tests (907 telemetry/app, 21 protocol, 28 host), 17 packaging tests, and the Release build passed. The Developer ID signed app was accepted by Apple notarization, stapled, and passed signature and Gatekeeper verification.

The final ZIP SHA-256 is `8262e583350718bcfd2bfffaa7e87b1dfa9a5d0714b10b6125fa74f5815645a6` (8,481,941 bytes). All three uploaded release assets matched GitHub's recorded sizes and SHA-256 digests before publication. Sparkle tests against the exact final ZIP verified normal 129-to-130 installation, deferred installation after a test process quit, test-process relaunch, and invalid-signature rejection (error 4005; old app remained 129). User preferences remained unchanged except Sparkle's last-check timestamp. The test server and test-only processes were stopped. Evidence remains in `.build/release-v1.9.5-130/upgrade-test/results.json` and accompanying logs.

Release: https://github.com/knightfolk/Bloomy/releases/tag/v1.9.5. The provider and running review app were not changed by these updater tests. Live model application and real-key request dispatch remain outside the verification claims above.

## Local model Swap hotfix

Added a distinct Swap action for already-advertised unloaded popup models. The action sends an eight-token completion only to the provider's unified localhost API. Discovery must identify the same running provider PID/start time, have a valid bind timestamp, and use 127.0.0.1. Standalone/local servers with a different process, stale discovery, remote hosts, absent exact model IDs, active work, and changed advertisement/process state block the request. Saved configuration and the advertised list are never changed. Timeout/cancellation reconciles local residency; HTTP success alone is insufficient.

The local provider source in `../d-inference` at `5d400cf7` confirms unified local acquisition shares `ensureModelLoaded` with network serving and excludes in-flight work from slot eviction. The user's current provider returned no local endpoint during a read-only discovery check; no endpoint was enabled and no live inference, provider restart, or model switch was performed during verification. The UI provides Open Hosting to configure unified loopback mode explicitly.

All 968 Swift tests passed (919 telemetry/app, 21 protocol, 28 host), including 12 focused swap/identity tests; 17 packaging tests passed. The mixed-card native rendering shows Qwen in memory and advertised Gemma with Swap/Only controls at equal card dimensions. A headless sandbox capture cannot create an AppKit bitmap; the desktop-enabled focused rendering succeeded and was inspected separately. A read-only UI/wiring review found no blockers.

Release 1.9.6 build 131 was built from `92866601b54e406e35105e419b630c62b209908b`, Developer ID signed, Apple notarization Accepted (`9202900e-050b-46a1-bbdc-5d92e35d33a4`), stapled, and accepted by Gatekeeper. The final ZIP is 8,517,998 bytes with SHA-256 `609f509660f579c71c3de215b12f951b3cf3b08eca1e4c73e1eeeb42d9692f8d`. All three uploaded asset sizes/digests match local bytes. Exact-ZIP updater tests passed 130-to-131 install, invalid-signature rejection (4005, old copy retained), deferred install after test-target quit, and test-only relaunch. Existing user preferences remained unchanged except Sparkle's last-check timestamp. Test processes/server were stopped; provider PID 913 continued unchanged. Evidence: `.build/release-v1.9.6-131/upgrade-test/results.json`.
