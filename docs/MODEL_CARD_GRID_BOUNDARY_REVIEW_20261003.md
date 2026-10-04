# Model-card footer at grid boundaries — October 3, 2026

Downloaded card footers exceeded the actual grid allocation at the minimum
two- and three-column widths. The compact preload checkbox now reads “Startup”;
expanded Manage retains “Load at startup,” full model-specific accessibility
names and the explanation that saving/restarting applies the setting.

## Diagnosis and retained proof

The grid admits two 300-point cards at a 614-point grid width and three at 928.
Model-manager horizontal padding adds 40, giving content-width checks of 654 and
968. Each 300-point card has a 276-point interior after its 12-point side padding.
The new Uninstall action plus the old fixed-size preload label forced the
native downloaded content to 283.5 points: 7.5 points over its allocation.

The first diagnostic compared controls to the already-expanded native content
and falsely reported a pass. That rejected report is preserved as
`.build/model-card-boundary-20261003-before/initial-content-relative-bounds.json`.
An independent allocation comparison in `allocated-width-regression-before.json`
correctly fails both downloaded cards. The corrected review fixture uses the
allotted grid-slot width, bounds native traversal, and requires one readable
Enable, Preload, Uninstall and Manage control per downloaded card. It does not
press actions or change the provider.

## Native after checks

The exact-source after fixture is
`.build/model-card-boundary-20261003-after/Bloomy Model Uninstall Fixture.app`,
bundle `dev.darkbloom.model-card-boundary-after-20261003`, review PID 44367.
All recorded source hashes match the working checkout. Build completed with
exit 0; the retained manifest describes local review, not distribution signing.

Six retained native reports pass ten measurements each, with zero horizontal
overflow: 654, 968 and 650 content widths in light and dark. At 654/968, downloaded
content measures 276 points; at 650 the single card uses a 460-point slot.
Each report is named `boundary-<width>-<appearance>.json` in the after directory.
The Available row is visibly inspected after scrolling at the narrow two-column
boundary. For 968, the initial 900-point review window clips the outer content;
native Zoom widens the window before the accepted measurement and screenshot.
The fixture contains only two Available cards, so this does not prove a filled
three-card row. Actual rendered two-column light/dark, widened grid and Manage
screens were inspected through Computer Use.

Interaction proof preserves existing behavior:

- Startup on the enabled resident stages changes and enables Save; toggling it
  back removes the draft and disables Save. No Save or Apply was pressed.
- Startup on the disabled downloaded model still requires Enable or removing
  preload; the existing validation remains visible. It was reverted.
- Manage visibly retains “Load at startup” and full Preload accessibility/help.
  Done closes the sheet without changing the selection.
- Resident Uninstall remains disabled. Downloaded Uninstall is available with
  no draft and blocked while staging. No uninstall or download was invoked.
- Final synthetic status has zero delete calls and its fake sentinel intact.
  The review app quit normally; installed Bloomy was not replaced or quit.

The five focused `ModelCardSummaryRenderingTests` pass, including the two
rendering widths, responsive grid boundaries and grouped manager rendering.
`git diff --check` passes. Existing focused tests and a built exact-source
native review are proportionate to this single label change; no full release
suite or distribution run was repeated.

## Limits and current runtime

This verifies horizontal action containment and the described synthetic
interactions. It is not spoken VoiceOver, large-text/localization, installed
delivery, complete three-filled-column proof or full-app completion. The menu
motion gate and broader native matrix remain open. Nothing was pushed/released.

During this review Kevin separately requested starting the real provider with
Qwen 3.8 and Gemma 4, and enabled Autopilot. The official CLI start completed;
fresh daemon proof confirms those two advertised models, one slot, enabled and
unpaused shadow Autopilot and an App Attest-authorized connection. CLI enrollment
reports all seven cached supported models to Autopilot even though the current
hosting selection is two. Live activation belongs to the coordinator. Initial
Qwen loading encountered memory pressure; a later snapshot showed it warm,
followed by a snapshot with no warm model. No manual inference, forced restart,
extra preload mutation, cache deletion or unrelated process termination followed.
Do not infer sustained residency from the transient warm observation. Saved
configuration changes are limited to the two-model enabled selection and the
CLI's enrollment revision; all other settings were semantically unchanged.
