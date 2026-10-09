# Settings capture-delivery comparison

October 9, 2026, America/Phoenix. Native qualification progress, not a product
fix, successful occlusion gate, distribution release or completion of the
broader polish/efficiency goal.

## What changed

The opt-in actual-Settings fixture can run its existing finite proof once after
its initial synthetic load finishes, then exit through the existing joined
termination gate. Build with `--settings-preview-proof` and run the resulting
fixture executable with `--settings-preview-autostart`. Without that runtime
switch, manual review behavior is unchanged. Normal builds compile no Settings
autostart branch. The emitted `SETTINGS_PREVIEW_OUTPUT` line identifies the
owned private report directory without requiring a window capture.

The cover prerequisite now reports three independent stages: opaque tracked
coverage, actual native loss of the visible bit, and the product's stopped
visibility/animation response. All stages share the original three-second
acceptance deadline, checked before each predicate evaluation. The existing
cover's eight-second lifetime, 1.7-second stopped hold, strict WindowServer
ownership/order/opacity/containment checks, unchanged identity/geometry,
recovery motion, original-frame restoration and joined child teardown remain.

A passive window-specific notification observer records at most 64 entries,
with capacity and dropped-entry metadata. It never changes visibility, layout,
animation or window ordering, and is removed at proof exit. The original dirty
fifteen-case MenuBarMotionProof remains byte-for-byte unchanged.

Read-only review caught a deadline acceptance edge and silent notification
truncation; both were corrected and guarded. The first compilation rejected
unannotated nested helpers; explicit main-actor annotations correct that issue.
The unlaunched failed compilation output was removed after successful final
build verification; its diagnostic log is retained.

## Matched runs and result

The same optimized artifact, same runtime arguments, fresh processes and private
preferences were used within each pair. Neither pair changes the production
view, native clock policy or synthetic inputs between arms.

| Identifier | Arm | Parent / cover PID | Passed cases | Cover-stage result |
| --- | --- | --- | --- | --- |
| Existing fixture | Tool-quiet | 11406 / 12271 | 11 of 12 | Opaque coverage; no native occlusion delivery |
| Existing fixture | Continuous capture | 16084 / 16225 | 11 of 12 | Same |
| Fresh, previously unselected fixture | Tool-quiet | 25365 / 25441 | 11 of 12 | Same |
| Fresh fixture | Continuous capture | 26036 / 26113 | 11 of 12 | Same |

The existing-identifier captured run records 95 captures, including nine while
the proof remains in the cover case after opaque coverage is accepted. The
fresh-identifier captured run records 82, including nine in that interval.
These are native per-window captures; their pixels do not prove how a covered
window appears on the physical display.

Two preliminary observation attempts (12334/13708 and 14477/15037) completed
with the same 11-of-12 result, but their sparse calls did not record the exact
cover interval. Their reports are retained as limited observations, not valid
continuous-capture comparison arms. Preparing the capture loop before launch
resolved that timing problem; no additional unchanged sparse attempt was made.

The fresh identifier is `dev.darkbloom.settings-delivery-20261009`. It was never
selected in CUA before its quiet run. Both quiet arms make no root CUA or screen
capture calls from launch to terminal reporting. This establishes **tool-quiet**,
not the absence of other software, user capture, or persistent whole-screen
capture. The comparison does not establish capture causality or rule it out.

All six completed runs:

- Pass baseline motion, ten fresh updates, active/idle/active, independent fan
  and temperature colors, failed fan read/recovery, window appearance changes,
  navigation away/back, immediate supported navigation/reopening, minimize/
  restore, retained reopening, and rapid reopening.
- Accept the live opaque cover at the correct front order with full containment
  of the 800-by-560 target. Fail specifically at
  `supported_cover_native_occlusion_not_delivered`; neither the stopped hold
  nor genuine-occlusion recovery is reached.
- Receive no occlusion notification during the cover case. Three notifications
  are retained: initial eligibility, minimize becoming invisible, and restored
  visibility. No notifications were dropped. The minimize observation disables
  the tested dashboard's display work; supported minimize/recovery motion passes.
- Complete all twelve cases with an aggregate **failed** result. Stop retained
  clocks, close the actual production controller, report no write errors, and
  gracefully close/reap the child with exit 0 and `parent-request` reason.

All twelve recorded parent/cover PIDs are absent after terminal completion.
No real provider lifecycle command, swap, download, inference, installed-app
replacement, privacy change or capture-permission change was made.

## Verification and artifacts

49 staging checks pass. The optimized Settings fixture compiles and its signed
artifact matches all 142 recorded production/native inputs. Source review finds
no remaining actionable issue in the diagnostic changes. No full package test
rerun is claimed for this fixture-only change; production source is unchanged
from the preceding 1,832-app/49-companion passing Release checkpoint.

- Existing identity artifact: `.build/settings-delivery-pair-20261009-b/`.
  Signed binary SHA-256:
  `c9d31e6156fe3b1ae5f522ba19fae96c20b4e673bdb7cc97b4b390abdb9be538`.
- Fresh identity artifact: `.build/settings-delivery-fresh-identity-20261009/`.
  It copies the same compiled app, changes only bundle identity and ad-hoc
  signature, and records the compiled parent hash, final binary and plist hashes.
  Deep/strict signature verification passes. Signed binary SHA-256:
  `31556635eb554d93209944b549896eb996fa7382e1da42291ec64c365449dcb6`.
- Both roots retain `fixture-manifest.json`, `runtime-summary.json`, and terminal
  reports under `runtime-evidence/`. Continuous arms retain `capture-log.json`
  and bounded cover screenshots. The original motion-proof hash remains
  `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.

## Gate and next action

Native delivery remains unproven; geometry and a passing minimize case cannot
substitute for genuine occlusion. No product poller, visibility override,
manual clock restart, timeout expansion or gate replacement is justified.
Repeating the same cover, capture cadence or identity variation adds little.
Further work on this boundary needs a new delivery condition or independent
local evidence; other UI, accessibility and efficiency work can proceed.

Apple's [window-visibility guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html)
distinguishes ordered windows from occlusion and recommends stopping work when
the window's visible bit clears. Its transparent/nonrectangular/OpenGL caveats
do not, by themselves, identify the cause here. The app's use of native window
notifications is preserved while the unresolved prerequisite remains failing.
