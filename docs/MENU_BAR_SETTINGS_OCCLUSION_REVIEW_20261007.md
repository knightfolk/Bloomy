# Supported Settings occlusion diagnostic — October 7, 2026

Opaque cover still does not establish AppKit occlusion in the actual production
Settings host. A fresh optimized run finishes all twelve cases: eleven pass,
and the new supported-cover prerequisite fails. The distinct-process cover is
opaque, above and contains the target in WindowServer, but the target retains
its visible occlusion bit and rotation key. This rules out the manual host as
the sole explanation for the failed cover prerequisite. It does not prove
animation failure under genuine occlusion or justify a product recovery change.

## Diagnostic construction

The original dirty MenuBarMotionProof is preserved byte for byte. Only the
Settings fixture stages a guarded same-file extension exposing its existing
private OwnedMotionCover. That owner still starts the same inert executable's
single-window mode, retains its eight-second timeout, drains pipes and awaits
tracked-process cleanup. No original fifteen-case body or cover renderer changes.
Normal staging receives no access extension; incompatible diagnostics remain
rejected. The manifest records original and staged helper hashes separately.

The new case uses the actual DashboardWindowController and unwrapped Settings
RootView with never-started inert dependencies. It temporarily sizes only the
owned review window to an actual 800-by-560 frame, centered within the screen's
visible frame with 32-point margins. The expanded cover is checked against its
screen and existing 1024-point bounds before launch. The original window frame
is restored on every exit; both retained reports confirm exact restoration.

One three-second prerequisite requires the live child, correct WindowServer
owners, opaque alpha, front order, complete containment, actual loss of the
target's AppKit visible occlusion bit, disabled dashboard visibility and a
stopped activity clock. Geometry alone cannot pass it. Successful prerequisites
would proceed through a 1.7-second stopped hold, graceful child shutdown and
unchanged identity/geometry with sustained recovered motion. Those hold and
recovery stages were not reached in either recorded cover attempt.

The adapter creates its owner before startup and always awaits stop after
startup failure, observation error or cancellation. After joined cleanup it
rechecks cancellation so a late cancellation cannot leave misleading probe
success metadata. A read-only review found that metadata edge; it is corrected
and guarded. The Session retains structured ready, failure and cleanup evidence
even when the prerequisite fails. No forced target layout, display, transaction
flush, visibility notification or animation configuration is introduced.

## Observed results and cleanup

| Run | Terminal state | Case results | Cover cleanup |
| --- | --- | --- | --- |
| Completed, PID 40133 | Completed, aggregate failed | 11 passed; cover prerequisite failed | Child 40437, parent-request, exit 0, window closed |
| Quit attempt, PID 41637 | Cancelled, aggregate failed | 9 passed; cover failed; 2 reopening cases cancelled | Child 42213, parent-request, exit 0, window closed |

The completed run's cover is an 864-by-624 opaque window at layer 1, front index
11. Its 800-by-560 target is at layer 0, index 14. Returned WindowServer bounds
fully contain the target; both entries report alpha 1 and the expected PIDs.
The target still reports `occlusionVisible: true`. Its seventeen-entry layer
ancestry includes the content layer, and `inferenceRotation` remains present.
The failed prerequisite is preserved, rather than treating coverage as proof
that the clock ought to have stopped. The first eleven pre-existing supported
Settings cases remain passing in the completed run.

The second process was launched to check cancellation while a cover was live.
A finite observer records live parent 41637 and child 42213 in the cover case.
CUA then requests normal Quit. By the time cancellation reaches the proof, the
cover has already failed and exited normally; its probe remains noncancelled.
Cancellation during the cover phase or its teardown is therefore **not verified**.
The report correctly marks the later retained/rapid reopening cases cancelled,
and the overall run cannot pass. Do not count this attempt as cover-cancellation
qualification or silently repeat the unchanged occlusion test.

Both terminal reports verify stopped retained clocks, production-window closure
and no write errors. All four recorded PIDs are absent. A post-Quit CUA read
reopened an idle review process; it was closed again, and a fresh process-list
check confirms no process running from this qualified artifact. Future quit
verification should use process absence without reopening the app.

## Verification and provenance

All 47 staging checks pass and git diff --check is clean. The optimized build
finishes successfully; all 128 original source hashes and binary bytes match
its manifest, and cover staging exactly matches the guarded access extension.
No fresh full package test run or production build is claimed for fixture-only
work. Product source and installed production state remain unchanged.

Qualified root: `.build/settings-occlusion-qualified-20261007`. It retains
`runtime-summary.json`, `cancellation-live-observation.json` and terminal reports
under `runtime-evidence/completed` and `runtime-evidence/cancelled`.

- Manifest SHA-256: `2f58c8b1ea7818ddc68dd07da1a656859fc981054c6a96e219d470bd8e9c67f4`.
- Binary SHA-256: `e1731605cee9b87d930d658cc47e0b3326de8771bd630c9e54180ce3b3717ba7`.
- Completed report SHA-256: `1206f23199a3663bf16592201a0dd0e7caf1f7e51d07c5c93547c8c6f034062d`.
- Cancelled report SHA-256: `225dd57df42e965efb84d87b5ba3d44c2133d4f9cc95180a8356e86fd40acb57`.
- Settings helper SHA-256: `5b951dd8f557f71ffbf102badbd013bbd7c83540ce44f7117eb13f13e6a65bea`.
- Staged cover helper SHA-256: `4678d900fba81da30489b2d84a000a4372eda9cf7cbb0c56c7c035ee869ca826`.

The protected original remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`;
provider configuration remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
Finite work is terminal and owned processes are absent. No provider action,
inference, installed-app update, global preference change, push or release
occurred. Genuine AppKit occlusion delivery, active-cover cancellation, the
ordinary gate and broader native/application qualification remain open.

The next occlusion investigation must isolate an actual delivery condition;
repeating the same cover or polling WindowServer in the product is not a repair.
Other product work, including joined Activity replay, demand history, financial
attribution and native accessibility, can continue independently.
