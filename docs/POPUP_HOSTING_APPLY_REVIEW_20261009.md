# Popup Hosting Apply review — October 9

The popup is the operational entry point. Its existing common bar and More
menu reach provider lifecycle, Autopilot, Auto setup, nudge, model management,
hosting, cooling, GPU protection, energy, profit switching, health/logs and app
settings. This checkpoint repairs a shared-state problem in Hosting rather than
adding a second settings implementation.

## Problem and change

After staging a model change in popup Models and selecting Done, Hosting still
offered Apply. The provider correctly refused the write, but Hosting instructed
the user to refresh. Preserving refresh retained the model draft, so that advice
could not resolve the blocker. A failing regression reproduced both the offered
exposure confirmation and the misleading error.

Hosting now checks the same typed write blocker as ProviderControlStore,
disables Apply with the specific explanation, and offers Review model changes.
The popup route and dashboard route return to their existing Models editor.
Shared provider updates forward through Hosting observation without polling;
replacing the attached store detaches its old observer. A second check before
confirmed dispatch rejects edits made while an exposure dialog was open.

Applying shows progress for the complete graceful restart/reconciliation and
blocks duplicate clicks. Existing security confirmations remain scoped to a
captured request and editor. New requests during an unfinished restart no
longer open a second exposure dialog. Actual failures use the provider's authored
safe diagnostic; successful completion clears temporary duplicate-click errors.
Hosting options, model drafts and token restart revisions remain preserved.

## Verification so far

The full debug run passes 1,877 app tests, 21 companion protocol tests and
28 companion host tests. Three new tests cover staged edits before and after
confirmation, duplicate dispatch/progress, and forwarded observer replacement.
The older overlapping-dialog test now asserts rejection during a restart.
Independent read-only review found no actionable issue in this scope.
The ordinary Release application build passes.

The final optimized run passes 64 focused tests; 49 native-fixture staging
checks also pass. The isolated Release fixture passes deep strict review-signature
verification. All 143 recorded source inputs match the checkout. Its binary hash
is `ec5667afe28a66ffd54c86047cb7b03d9d1129861bddb6b907c92062ecf89485`.

## Native popup proof and limits

Computer use reproduced the old enabled Apply button after staging GPT-OSS
preload in Models. The updated build repeats that same flow in compact light
and dark appearance: Apply is disabled, the blocker describes model edits, and
Review model changes returns directly to Models with the preload still selected.
Restoring that checkbox to its original selection and reopening Hosting enables
Apply without refreshing. The retained panel scrolls to the complete explanation
and recovery control; light/dark screenshots were inspected.

Artifacts are `.build/hosting-popup-20261009/baseline.png`, `fixed-light.png`,
`fixed-dark.png`, `fixed-dark.ax.txt` and `clean.ax.txt`. The optimized fixture and
manifest are under `/Volumes/Sol/BloomyReview/hosting-popup-20261009/native-verified`.
The full final log is `.build/hosting-popup-full-final.log`; optimized focused
checks, ordinary build and staging logs use the same `hosting-popup-` prefix.

Native proof covers the popup recovery. The dashboard callback passed compilation
and static review but was not established by rendered navigation: sidebar clicks
made no visible transition during the additional attempt. Progress and duplicate
restart prevention are controlled store-test evidence, not a real-provider test.
No provider mutation, inference, credential entry, installed replacement, push or
release occurred. Both task-owned review apps quit normally and production Bloomy
PID 7234 remained running. Broad accessibility, motion, resource and distribution
qualification remains separate from this local checkpoint.
