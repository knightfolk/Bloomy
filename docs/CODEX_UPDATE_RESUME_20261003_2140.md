# Bloomy safe update hold — October 3, 2026, 21:40 Phoenix

## Timeline correction

This hold was mistakenly replayed during an automatic post-resume turn. Fresh
supported history proves the direct update-stop request belongs to turn
`01a1050b-ad33-7ce2-9758-76a75ad76fe3`, before the direct voice resume in
`01a1051b-cc86-7589-ae6e-bbb24a0e88c7` and subsequent “Done” in
`01a10520-7870-713b-aa31-38fa182e223e`. No newer direct stop was found. Preserve
the checkpoint as historical evidence; its hold is superseded. Ordinary
authorized work resumed. The mistakenly paused native goal still requires the
official Resume control because the available tool cannot reactivate it; this
limitation was disclosed, with no UI-denial workaround attempted.

The card after-proof is now recorded in
`MODEL_CARD_GRID_BOUNDARY_REVIEW_20261003.md`. Kevin subsequently directly asked
to start Darkbloom with Qwen 3.8 and Gemma 4 and Autopilot enabled; that runtime
request supersedes the stopped-provider observation below. The official start
completed, and a fresh authorized daemon advertises exactly those two models,
one slot and enabled/unpaused shadow Autopilot. No extra restart or manual
preload change was dispatched after transient Qwen memory pressure. Private
rollback and sanitized runtime evidence are retained under
`.build/provider-qwen-gemma-start-20261003/`.

## Historical hold receipt

Kevin directly requested stopping safely for an app update. Hold implementation,
builds, tests and workers until he resumes this task. This checkpoint does not
complete the active polish/efficiency goal. The supported goal pause receipt is
retained beside the WIP backup.

## Preserved checkout and work

- Main integration owner: `01a0eb34-3317-7821-8c46-73723894fd79`.
- Checkout: `/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor`, branch `main`.
- HEAD: `e9e70ecdcde22669f4a4e8237842385ee1c5918d` (local diagnostic checkpoint).
- New unfinished scope: `ModelManagerView.swift` compact checkbox label changes
  from “Load at startup” to “Startup”; expanded Manage UI, accessibility label
  and help remain unchanged. `ModelUninstallFixture.swift` adds exact grid-width
  controls and allocated-card geometry measurements.
- Preserve unrelated dirty `Tests/NativeUI/MenuBarMotionProof.swift`, `.mimosa/`
  and `.zcodeignore`. Do not stage, revert or clean them.
- Exact tracked WIP patch, all three modified source files, hashes, status and
  build/test logs are saved under
  `.build/codex-update-checkpoint-20261003-214031/`.
- No incomplete implementation was committed or pushed for this hold.

## Evidence and immediate next step

Before fixture: `.build/model-card-boundary-20261003-before/`.
The rendered 654-point content width produces two allotted 300-point cards.
Native AX geometry measured both downloaded card contents at 283.5 points,
7.5 points wider than their available 276-point interior. Retain
`initial-content-relative-bounds.json` as a rejected comparison: it wrongly
checked against the already-expanded content. Independently corrected
`allocated-width-regression-before.json` records the failure against the actual
grid allocation.

After fixture: `.build/model-card-boundary-20261003-after/`, bundle
`dev.darkbloom.model-card-boundary-after-20261003`. Build completed successfully,
but the after app has NOT been launched or visually verified. The corrected
oracle compares cards against allocated width, rather than expanded content.

After explicit resume, revalidate source, goal, dirty state and installed app.
Launch only the after synthetic fixture. Check 654-point two-column boundary,
968-point three-column boundary and 650-point single-column comparison; retain
each geometry report and inspect the actual visible controls in light/dark.
Verify preload staging can be toggled and reverted without Save, expanded Manage
still shows the full label, resident uninstall remains disabled and no real or
fake uninstall occurs. Record native proof before claiming the UI fix complete,
then make a focused verified local checkpoint. No new release is authorized.

## Joined work and preserved runtime

- Fixture build session `58691`: joined, exit 0.
- Focused Swift test session `61549`: joined, exit 0; five tests in one suite
  passed (`ModelCardSummaryRenderingTests`). `git diff --check` passed.
- Before fixture PID `42748` quit normally through its own app; process absence
  verified. After fixture never launched. No finite build/test remains in flight.
- Native agent inventory contains only root; no running worker remains.
- Installed Bloomy PID `54773` remains running; installed version/build and
  provider configuration hash were freshly captured in checkpoint manifest.
  Preserve possible unsaved production edits. Kevin handles the installed update.
- Provider and recovery watcher are absent/stopped. Do not restart for this hold.
  The fan helper and installed app's log stream remain untouched.

## Remaining broader gates

`APP_POLISH_OPTIMIZATION_PLAN.md` and `NATIVE_COMPLETION_MATRIX_20261002.md`
remain authoritative and incomplete. Prior menu-host diagnostic is 4/5, with
the true opaque-cover occlusion prerequisite still failing; the older 15-case
gate is also not green. Do not repeat unchanged experiments or weaken predicates.
Do not equate the published 1.9.19 release with completion of these UI/efficiency
gates. Preserve all retained evidence and resume the same existing goal only
when Kevin requests it.
