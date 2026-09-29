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
