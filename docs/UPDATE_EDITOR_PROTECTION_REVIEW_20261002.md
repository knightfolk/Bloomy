# Update protection and editor recovery — October 2, 2026

This is a bounded continuation of the native polish run. The provider and
recovery watcher stayed stopped. No real inference, credentials, privacy
changes, updater installation, or replacement of the installed app was needed.

## Changes

- The production updater checks retained dashboard and pop-out Chat drafts,
  unfinished Hosting port/address buffers, popup fan drafts, active Chat sends,
  and pending Hosting exposure confirmation, alongside its existing provider
  operation/model-draft guard and retained dashboard idle/fan guard.
- Mounted Chat, Hosting, and Nudge credential editors register their unfinished
  input synchronously with independent owner IDs. The registry contains no
  credential strings. Clearing, successful saving, and editor disappearance
  release only that editor; disappearance also clears its local secret input.
- Auto protects deliberate changes, including an empty invalid selection.
  Suggested initial choices are clean. Verified save readback releases only the
  submitted revision; newer choices survive an older completion. Dismissal
  discards this transient editor's selection and releases its owner.
- Dashboard controllers retain the same nonsecret Chat/Hosting drafts injected
  into their views. Pop-out Chat owns a separate retained composer. Only
  meaningful Chat text belonging to the active conversation blocks updates;
  obsolete or unowned text cannot keep the updater waiting indefinitely.
- Hosting, idle, and fan editors expose local Discard controls. They restore
  text/policy from current saved or observed values without dispatching provider
  operations. Idle/fan discard invalidates previous save revisions, and one
  page's save/discard cannot clear another page's dirty draft.
- The update notice explains that unfinished edits and pending requests/actions
  delay restart. No recurring task was added to the editors or registry.

Hosting retains the existing immediate saving of valid port preferences. For
example, typing `8x` first saves the valid intermediate `8`, then retains `8x`
as invalid input. Discard restores the saved `8`, rather than the initial 8000.
This checkpoint does not change that preference-saving behavior.

## Tests and review

Four new suites exercise the actual production relaunch guard, retained native
Chat windows, Hosting draft synchronization, independent owner cleanup,
revision handling, and two mounted Nudge editors. Synthetic provider/endpoint
dependencies reject mutations or traffic, and credential stores return inert
absence. A suspended fake Chat response verifies the active-send guard.

An independent source review found Auto's empty-selection exemption; the final
source compares the selection with its baseline and includes a regression.
The first focused build also caught three mutating-value test macro calls;
their results are now assigned before assertion. The next focused run exposed
an overly strict inert token fixture: Hosting renders its Copy button using the
existing token-presence API. That fake now returns absence without reading any
file or invoking a credential callback; write/copy/provider traps remain.

The first full run passed the new suites but failed the existing log-stream
ordering assertion. A waiting consumer receives pipe order; queued events use
the existing newest-first EventBuffer. The test now checks exactly two matching
messages independently of consumer scheduling. The separate paused-stream
newest-first test is unchanged, and runtime logging source is unchanged.

Final verification completed with exit 0:

| Product | Tests | Suites | Test time |
| --- | ---: | ---: | ---: |
| App and telemetry | 1,205 | 158 | 33.382 s |
| Companion core | 21 | 5 | 0.016 s |
| Companion host | 28 | 9 | 11.751 s |
| Total | **1,254** | | |

The release compile completed with exit 0 in **53.48 s**. Raw logs under
`/tmp/bloomy-efficiency-20261001/` are `update-editors-focused-01.log`,
`update-editors-focused-02.log`, `update-editors-full-tests-01.log`,
`update-editors-full-tests-02.log`, and `update-editors-release-build-01.log`.
Only the final full run and release build establish the final source.

## Native proof

Native 29 hosts the production views with inert dependencies and retained
drafts. Its banner identifies synthetic review and disabled CPU/GPU collectors.
Computer-use screenshots and accessibility outputs are retained in this chat.

| Route/state | Observed result |
| --- | --- |
| Hosting, compact light | Typed `8x` disables Apply; navigation away/back and Refresh preserve it; Discard restores the saved port and removes the dirty notice |
| Nudge setup, light sheet | Whitespace stays secure, Save stays disabled, Discard appears and clears only the local input |
| Cooling, light sheet | Quiet draft shows Unsaved and 60%/45°C; closing/reopening retains it; scrolling reaches Discard; Discard restores observed 80%/65°C and disables Save |
| Auto, light sheet | Empty choice disables Save with guidance; selecting GPT-OSS and saving changes only the fake actor; verified readback shows Auto plan saved |
| Provider, wide dark | Invalid `-` idle text survives Refresh; reachable Discard restores observed 30 and removes the unsaved indication |
| Chat, wide to compact dark | Typed unsent prompt survives Overview navigation and return, with the full prompt and composer visible after resizing |
| Hosting, compact dark | Whitespace leaves Save token disabled; Clear input appears, remains reachable, and clears the secure field without saving |

The fixture excludes the production app delegate; native rendering alone does
not prove Sparkle's guard. The automated actual-delegate tests supply that
separate evidence. Native 28 compiled an intermediate Auto source and was not
used for final review. Native 29's manifest is
`.build/native-dashboard-fixture-20261002-29/fixture-manifest.json`, with a copy
under the temporary evidence folder. All **80** source hashes matched after
review. Final binary SHA-256:
`6009cc4690f27f489c3dfb53cfbd879797f8222f73774e3d8113214a7d3bd784`.
Linked telemetry library SHA-256:
`a8b51e2df2f6e0244733279b1b5f844c23f5d58e0e6fc08a7fd53d7f1754d65b`.

Native 29 quit through its own native Quit command; no fixture process remained.
Production PID 31677 retained its October 1 22:40:57 launch and binary hash
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
The real provider configuration retained hash
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
Launch services showed only the installed app, without provider/recovery.

## Remaining boundaries

This is a local checkpoint, not a release or full polish completion. Actual
Sparkle installation/resumption, the complete credential-editor/window matrix,
VoiceOver, controlled Reduce Motion, sustained updated-production profiling,
and production cache access remain open. The fixture's upper-page popup anchor
can clip its outer header; this pass does not establish production menu-bar
popup geometry. Protected production windows and the pending scoped Sol
permission decision remain in force. No CPU or battery improvement is inferred
from the inert host or these tests.
