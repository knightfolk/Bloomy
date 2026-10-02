# Bloomy project agreements

Follow Kevin's Friday working agreements and preserve concurrent work.
The active polish/efficiency scope and remaining native proof are tracked in
`docs/APP_POLISH_OPTIMIZATION_PLAN.md`; a release checkpoint does not complete
that broader goal.

## Provider testing authorization (2026-10-01)

For the current optimization run, Kevin initially stopped the provider and its
recovery watcher to free resources for VMs and other work, then explicitly
authorized resuming the provider. Restore its saved settings when the existing
cache-access failure is resolved. Prefer inert fixtures when a test does not
need the real provider. This does not authorize swaps, downloads, or inference
just to produce visual evidence.

## Checkpoints and release gates

Kevin permits prudent local commits of coherent verified work. The authorized
feature-work release cadence and exact signing/updater gates are in
`docs/RELEASING.md`. Do not publish a prepared artifact that predates later
source changes, bypass a failing native check, or equate review signing with
notarized distribution. Preserve the running production app and unsaved work
when testing isolated review builds.

On 2026-10-02 Kevin authorized resetting only Darkbloom's removable-drive
permission. The `SystemPolicyRemovableVolumes` reset for `io.darkbloom.provider`
succeeded. A retry with unchanged saved settings still exited while reading the
Sol model cache; its failed service and recovery watcher were stopped. System
Settings showed Darkbloom's removable-volume switch on. Diagnose that boundary
before retrying. This scoped reset does not authorize other privacy resets or
new Keychain, Full Disk, or broader drive access. Keep credentials out of logs
and evidence.
