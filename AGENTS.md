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

## Completion, integration and GitHub checkpoints

- For Kevin's authorized project work, commit completed, coherent changes after the required checks pass. Stage only your own verified scope; preserve concurrent and unrelated edits. A local commit alone does not mean integration or delivery is complete.
- Route completed work through the designated project integration owner, currently **Rebrand app as Bloomy** (task `01a0eb34-3317-7821-8c46-73723894fd79`) unless Kevin changes the owner, who verifies the intended target branch and handles merges after the relevant checks pass. Stop the merge when ownership or target is unclear, conflicts remain, or required checks fail; report the blocker and continue independent permitted work.
- Push validated milestones to the existing GitHub remote when prudent and the remote, branch and scope are authorized. Verify the destination and push result; do not assume a local or saved remote-tracking ref proves a current remote update.
- Do not force-push, rewrite shared history, stage unrelated work, or treat this workflow as authorization for deployments, credential/security changes or a broader scope. Existing project authorization, release gates and live tool restrictions still apply.
- At handoff, report the commit identity, whether it is local only or merged into the intended branch, whether GitHub received it, the checks performed and any remaining blocker. Pass this workflow to workers so integration does not get lost between threads.
