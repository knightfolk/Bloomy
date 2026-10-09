# Compact settings inside the popup

Popup settings now use the panel's fixed title and Done control without repeating
the dashboard's large introductory banner. Energy, Appearance, Menu Bar,
Provider, Updates and Support retain their actual sections, instructions and
controls. Dashboard and standalone Settings keep the existing title by default.
This is a presentation change: stores, drafts, visibility, polling, update
protection and provider mutations are unchanged.

The popup remains the operational control surface. Its existing More menu offers
model management, Hosting, Provider, GPU protection, electricity, Cooling,
inactivity nudge, profit switching, Health & Logs and app settings. This
checkpoint improves those settings panels; it does not claim every app feature
or every live operation has been newly qualified.

## Verification

Evidence is retained in `.build/popup-settings-layout-review-20261009/`. The
baseline is `ffd595e`; original sources and the old native Electricity banner
are retained. Independent read-only review found no actionable issue with the
title ownership, retained instructions or existing state and action safeguards.

The serial Release regression run reports 1,860 app tests in 234 suites, 21
protocol tests and 28 host tests passing, with seven existing opt-in skips. All
49 fixture-staging checks pass. The regular Release build finishes successfully
in 53.56 seconds. All finite jobs finish with exit zero.

The optimized synthetic native fixture matches all 142 recorded product source
hashes and passes deep, strict review signature verification. Its binary SHA-256
is `23b85f95594639e7ce1f51c72d7aeb05787f05c3ede96fc46fdc93737fcde551`.
Review signing is not notarized distribution.

## Native review

- A fresh fixture set to a 360-point height budget fits on its first popup open.
  The icon-led command bar and first model row remain visible; lower content
  scrolls. Dark reopening retains the compact layout.
- Electricity's switch and price field appear directly beneath the fixed panel
  header. The introductory banner is absent. Its disclosure expands to the
  retained whole-Mac scope, dollars-versus-cents and missing-coverage explanation.
- Enabling the fixture-only electricity setting makes the price editable.
  Editing to `0.15`, Done and reopening preserve the switch and value. The
  fixture has private defaults and an inert power reader, independent of the
  installed app's preferences and energy history.
- Appearance, Menu Bar, Provider, Updates and Support open through More without
  the repeated banner. Menu Bar scrolls to its idle reminder; Provider scrolls
  to the complete nudge setup; Updates scrolls to provider update controls.
  Fixed Done remains visible, and returns to the parent popup.
- Support retains the instruction to review a report before saving or sharing.
  No report is saved or transmitted. Release-only app updates stay unavailable
  in the synthetic review, with the explanation retained.
- Dashboard Electricity still displays its original large title and description.
  Dark popup and Electricity panel pixels are inspected and retained.

An accessibility click on Electricity's disclosure left it unchanged; clicking
the visible triangle expanded it. This is retained as an input-path limitation,
not evidence of VoiceOver qualification.

Before replacing the older task-owned review, changing its already-retained
popup's budget to 360 points initially displayed the previous larger size.
Closing and reopening applied the compact budget. The fresh final fixture does
not reproduce that on first creation. This title change does not fix or qualify
the retained-controller budget-change path; a focused sizing follow-up remains.

## Handoff and limits

The previous owned review exits normally before the new review launches. The new
review is left at its dark Electricity panel. Installed Bloomy 1.9.19/build 144
and its process remain unchanged. Provider configuration and the unrelated
MenuBarMotionProof edit retain their original hashes. No provider start, stop,
swap, inference, network nudge, installation, push or release occurs.

Standalone Settings pixels, broader spoken accessibility and large text,
genuine occlusion, dialog pixels, production resource measurements and delivery
gates remain open. This is a coherent local polish checkpoint, not completion
of the broader app goal.
