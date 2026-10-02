# Native resilience and window review

This is a local development checkpoint, not a published release or a complete
native-screen audit. Production Bloomy was preserved at PID 31677. The provider
and its recovery watcher stayed stopped; no test required a provider start,
model load, swap, download, or inference request.

## Saved capacity while the catalog is unavailable

The control service reads a display-only saved-capacity value independently of
CLI inventory. It contains saved slot/concurrency limits and selection counts,
with no model selectors, configuration revision, or inventory authority. A
failed catalog cannot create an actionable draft or enable Save, Apply Live,
download, swap, Start, or Restart. Existing staged edits remain separate.

The signed `native-key-status-review-20261001` build was inspected through
native computer use. Its Models capacity disclosure showed saved limits of one
model slot, eight simultaneous requests, seven enabled models, and zero explicit
preload selections. The panel labeled these saved choices rather than running
limits. Save and Apply Live remained disabled while catalog acquisition timed
out. The initial label "Startup models" was subsequently clarified to "Preload
selection"; it is a saved list count, not a prediction of startup or live state.

Synthetic SwiftUI renders cover a 440-point panel in light/dark appearance and
fresh/stale states. The first AppKit bitmap export was mostly blank and was not
accepted as visual proof; the corrected ImageRenderer export was inspected.

## Saved-key status without a startup stall

The first menu review stalled on the main thread in Nudge initialization:
`hasKey` called `withConsumerKey`, requesting secret data through
`SecItemCopyMatching`. Chat initialization and Nudge view gates used the same
synchronous read.

Presence now requests attributes in the existing Keychain scope, with a
noninteractive authentication context, and runs outside the main actor. The
legacy backend, storage scope, and actual secret-read/format validation are
preserved. Checking, configured, missing, and unavailable states stay distinct;
old results cannot overwrite a successful save or newer removal verification.
Presence does not establish that a key is usable or accepted by the API.

The signed key-status review reached the AppKit event loop and its dashboard.
The Nudge sheet showed "Setup complete · Key saved", with the existing key
recognized and automation off. Send remained disabled because the provider was
stopped. No key was entered, disclosed, or decrypted merely for this display,
and no Keychain prompt was approved.

Tests use synthetic stores to suspend lookup, exercise unavailable results,
reject obsolete results after save/remove, and block Chat preflight safely.
Repeated UI gates perform no secret read. The suspended test lookup has a finite
deadline so a regression cannot leave the test process waiting indefinitely.

## Native menus and full screen

Help opened the existing dashboard's Support page in the signed native review.
View initially showed a disabled Enter Full Screen command, despite resizable
windows. Both Dashboard and Chat now opt into `.fullScreenPrimary`; their desktop
frame fitting and autosaving pause during full-screen transitions and while
full screen is active. Dashboard releases its desktop maximum size during entry
and restores normal fitting after exit or failed entry.

Ten parameterized controller cases cover eligibility, transition frame
preservation, exit, and failed-transition recovery. The initial fixture showed
its window for the first time during a synthetic transition; AppKit moved that
hidden window into the screen. Presenting it normally before the transition
corrected the fixture while retaining every frame assertion. These tests do not
enter macOS Spaces.

The final signed `native-fullscreen-key-review-20261001` review used build 141.
Native View menus offered Enter Full Screen. Control-Command-F entered full
screen in both Dashboard and Chat; each menu changed to Exit Full Screen and
each window returned to its previous visible size after the same shortcut.
Dashboard was inspected in full screen and after exit; Chat was inspected at
its original size before/after, with native full-screen state confirmed by its
menu and window controls. A direct automated menu-item click returned a stale
element identifier, so keyboard dispatch supplied the actual toggle proof.
Help from Chat returned to the existing dashboard Support page. The final Models
panel displayed the clarified Preload selection label with Save/Apply disabled.

Apple's [full-screen guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/FullScreenApp/FullScreenApp.html)
documents explicit window eligibility. Its [Keychain lookup documentation](https://developer.apple.com/documentation/security/secitemcopymatching(_:_:))
documents the blocking query; [Mac Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
explains why changing the backend would be a separate credential migration.

## Verification and release boundary

The corrected full Swift run passed 1,088 app/telemetry tests, 21 companion
protocol tests, and 28 companion host tests (1,137 total). All 17 packaging tests
passed. The final release build passed in 42.78 seconds. Scoped review manifests,
source/executable hashes, private Beta preference
snapshots, and logs live in `.build/native-*-review-20261001` and
`/tmp/bloomy-efficiency-20261001`; these are review artifacts, not release assets.

The first key-status review was closed and its exact Beta preferences restored,
including removal of its newly created capacity-disclosure preference. A later
observation coincided with a second Launch Services instance; the cause was not
established. That exact task-owned process was also stopped. Production Bloomy
was not replaced.

The final build-141 review was stopped by its verified executable/PID after
inspection. Its Beta preferences were restored exactly, including removal of
only the capacity-disclosure and Chat-frame preferences created by the test.
Neither review was notarized or promoted to the canonical installation.

Production catalog access to Sol still needs a separately approved scoped
permission retest. No privacy reset or wider access grant was performed. The
earlier notarized build 140 is retained for rollback/provenance and does not
contain these later changes. Any final distribution must be rebuilt from the
verified source and use a build number above 140, so the installed build-140
candidate can receive it through Sparkle. Publication remains held.
