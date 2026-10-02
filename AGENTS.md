# Bloomy project agreements

Follow Kevin's Friday working agreements and preserve concurrent work.
The active polish/efficiency scope and remaining native proof are tracked in
`docs/APP_POLISH_OPTIMIZATION_PLAN.md`; a release checkpoint does not complete
that broader goal.

## Provider testing authorization (2026-10-01)

For the current optimization run, Kevin stopped the provider and its recovery
watcher to free resources for VMs and other work. Leave them stopped. Kevin
explicitly permits a temporary provider start if necessary for a test; stop it
again afterward and report it. Prefer inert fixtures when a test does not need
the real provider. This does not authorize swaps, downloads, or inference just
to produce visual evidence.

## Checkpoints and release gates

Kevin permits prudent local commits of coherent verified work. The authorized
feature-work release cadence and exact signing/updater gates are in
`docs/RELEASING.md`. Do not publish a prepared artifact that predates later
source changes, bypass a failing native check, or equate review signing with
notarized distribution. Preserve the running production app and unsaved work
when testing isolated review builds.

A scoped production removable-drive permission reset is still awaiting human
approval. Do not reset privacy permissions or grant new Keychain/drive access
as a launch workaround. Keep credential material out of logs and evidence.
