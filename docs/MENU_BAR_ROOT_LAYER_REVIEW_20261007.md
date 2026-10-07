# Manual menu-ring root layer comparison — October 7, 2026

Explicitly backing the manual fixture's root view does not repair its motion
failures. Two fresh optimized native runs complete all fifteen unchanged cases;
both pass twelve and fail opaque cover, retained close/reopen and rapid reopening.
Models and Charts pass in both. This is negative diagnostic evidence, not a
production repair or replacement for the ordinary native gate.

## Hypothesis and scope

The manual fixture uses an NSView content root. The treatment sets only
`container.wantsLayer = true` during its initializer, behind
`FIXTURE_EXPLICIT_MOTION_ROOT_LAYER`. AppKit documents layer backing at
[NSView.wantsLayer](https://developer.apple.com/documentation/appkit/nsview/wantslayer).
Both arms compile the identical staged helper; only the explicit arm defines
that flag. The protected original helper and product source remain unchanged.

Staging validates the fifteen ordered case names and exact contiguous fixture
initializer. It adds report metadata identifying the diagnostic and arm. Case
bodies, waits, assertions, animation configuration, cleanup and recovery are
unchanged. No forced display, layout, flush, settling delay or observer is added.
The builder rejects combinations with other motion modes before staging.

## Results and interpretation

| Arm | Motion | Models | Charts | Root backing observed on reopening |
| --- | --- | --- | --- | --- |
| Ordinary | 12/15 | Pass | Pass | false |
| Explicit | 12/15 | Pass | Pass | true |

The three failed cases are `opaque_cover_occlusion_and_restore`,
`same_window_close_and_reopen` and `rapid_same_window_close_and_reopen`.
Both reopening failures still record no content-view layer in the activity
arc's ancestry and a nil backing-layer parent. The explicit setting reached
the tested root, but that setting alone did not attach the arc to the expected
content chain or restore motion. These observations do not establish a precise
Core Animation cause or a defect in the supported production window.

This is one bounded ordinary-then-explicit pair, not a counterbalanced study.
Because the treatment provides no improvement, repeating the same pair would
not justify a product change. The next distinct check is navigation away and
back through the actual Settings host, followed by immediate close/reopen
before a presentation-angle hold. Use the production navigation/controller;
do not manually detach SwiftUI-owned views. Genuine cover remains independent.

## Verification and provenance

All 39 staging tests pass, including seven root-layer regressions. Eight mode
conflicts reject before creating output. The first attempted fixture builds
reject modules lacking testability; rerunning the focused Release MenuBar suite
restores test-enabled products, with 36 tests in five suites passing. Both
subsequent optimized fixture builds complete successfully. No new full package
or production build is claimed for this fixture-only comparison.

Artifact roots are `.build/root-layer-{ordinary,explicit}-20261007`. All 128
original source hashes match the checkout in both arms. The staged helper and
telemetry library hashes match; normalized compiler commands differ only in
the explicit definition and output paths. Evidence indexes are
`.build/root-layer-provenance-20261007.json` and
`.build/root-layer-runtime-summary-20261007.json`.

| SHA-256 | Ordinary | Explicit |
| --- | --- | --- |
| Manifest | `3e0bd855dd00d27ba99ac9f59bc22ffba19857007de9c93bb2dfb2cae065b5b3` | `8c856af8ea335b43dd01f94ea382d7a379239361f2782d06d6d5ce280a5c67c8` |
| Binary | `2380f886b70da75164dc4713e648158ee53946d0c78bd55d8a78d86e40651632` | `35f3031409e5c485d3c25a5da931f1d17a8d8ba0b8199f2b4eddce1c76c55b42` |
| Motion report | `cbd74237cfdcce94d7b2e1b5b14a5502282ff29660a56a5a09e74f1f6fe78123` | `93db0174d2297fa5b2f48f319aac8c3efb9602214714c64d358715fb18628335` |

The shared staged helper hash is
`3bd12817ceb589474216edf2fd5c864b8d8a756bfe8f9dffc71e7defef97d000`;
the telemetry library is
`8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`.
Each root retains the four terminal native JSON reports in `runtime-evidence`.

Native CUA inspection confirms terminal failure in both apps. Normal Quit and
cover cleanup leave owned PIDs 20595, 20619, 20680 and 20705 absent. Both cover
reports record parent-request shutdown, exit zero and child-window closure.
All finite build, test and monitor jobs were joined.

The protected original proof remains SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`;
provider configuration remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
No provider action, inference, app installation, system preference change, push
or release occurred. Native motion and the broader polish goal remain open.
