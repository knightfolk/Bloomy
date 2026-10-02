# Popup screen budgets and CPU ownership — 2026-10-02

Local checkpoint for the ongoing native polish and efficiency work. Production PID 31677/build 140 and its unsaved state were preserved. The real provider and recovery watcher remained stopped; these checks required neither provider startup nor inference.

## CPU sampling resource proof

The production CPU sampler acquired a host-port send right through `mach_host_self()` on every read without releasing it. It now holds that right in a local value and balances it with `mach_port_deallocate` in `defer`, including failed statistics reads. Counter conversion, unknown states, polling cadence, and visibility cancellation are unchanged. Apple's [XNU implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/ipc_host.c#L151-L174) establishes the send-right acquisition.

`Tests/PerformanceBenchmarks/CPUPortOwnershipProof.swift` calls the actual production sampler in a separate finite process. One owned baseline reference remains alive while the helper warms the sampler once, records send-right references, performs 512 reads, and records references again. It requires every read and reference-count query to succeed and the final count to equal the initial count. It starts no application, provider, timer, network operation, or credential access.

| Source | Successful measured reads | References before → after | Growth | Direct executable result |
| --- | ---: | --- | ---: | --- |
| HEAD `d26f6a2`, before change | 512 | 2 → 514 | 512 | Fails, exit 1 |
| Updated production sampler | 512 | 1 → 1 | 0 | Passes, exit 0 |

Both binaries used the same Swift 6 compiler, ARM64/macOS 14 target, proof helper, and debug telemetry library. The first captured reports are `/tmp/bloomy-screen-fit-20261002/cpu-port-before.json` (PID 33874) and `cpu-port-after.json` (PID 33873). Subsequent direct runs independently confirmed exit 1 before (PID 34186) and exit 0 after (PID 34187). This proves bounded send-right ownership; it does not measure whole-app CPU, RSS, energy, or battery savings.

To reproduce after building the debug telemetry product:

```sh
swiftc -target arm64-apple-macosx14.0 -swift-version 6 -parse-as-library \
  -I .build/out/Products/Debug \
  Tests/PerformanceBenchmarks/CPUPortOwnershipProof.swift \
  Sources/DarkbloomMonitor/SystemCPUUsageStore.swift \
  .build/out/Products/Debug/libDarkbloomTelemetry.a -lsqlite3 \
  -o /tmp/bloomy-cpu-port-proof
/tmp/bloomy-cpu-port-proof
```

Require the helper's complete terminal JSON and direct exit status. A command that prints the report afterward returns the print command's status rather than necessarily returning the proof's status.

## Popup and Chat review

The fitting controller reads the actual menu-bar anchor's screen-visible frame, reserves room for placement, and supplies a per-controller content height budget. It responds to screen changes without a recurring timer. Model-body scrolling preserves the header on ordinary shorter displays. A very small viewport must scroll the whole popup while retaining the same editor tree and its drafts.

Native 42 direct computer-use review verified the 360-point viewport: the header remained visible, Available models expanded and collapsed, and inner scrolling reached the complete Earnings/electricity/jobs footer. The 80-point check exposed a real fallback problem: fitting size was bounded, but the outer scroll area offered no native scrolling actions and keyboard focus on Cooling did not reveal that control. This failed reachability check is separate from successful fitting-size tests; Native 42 is not full popup proof.

The same native build verified all three revised paid Chat explanations in a dark 800 × 560 review window. The New Chat destination sheet and network confirmation fit, and the paid acknowledgement, model/Refresh/key controls, composer, disabled Send button, and disabled-send reason remained visible. The copy explains the payment decision in plain language; destination, balance, key, pricing, model-verification and acknowledgement gates are unchanged. No real key or request was submitted.

Native 42 manifest: `.build/native-dashboard-fixture-20261002-42/fixture-manifest.json`; binary SHA-256 `83770428d94756186c0363aaf8d18ca989d40ccef584ea14b4e38c32aa10dca8`. Its 85 source hashes and binary matched before review. Geometry/focus reports: `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/BloomyDashboardFixture-24FFF79E-304B-4DF7-BEEE-F2389EC4FAAF/`. The fixture was quit normally and process absence verified; production was untouched.

## Automated checks

- Focused run 02: 82 tests / 5 suites passed in 5.866 seconds.
- Full run 01: 1,267 tests passed — telemetry 1,218 / 160 suites (30.513 seconds), protocol 21 / 5 (0.018 seconds), host 28 / 9 (11.801 seconds).
- Release build 01 completed in 45.34 seconds.

Logs are under `/tmp/bloomy-screen-fit-20261002/`. These results precede the follow-up tiny-viewport correction; final validation is recorded below.

## Final scrolling correction and native proof

The modifier-only correction failed the stricter regression: the outer native document measured zero height against a 48-point viewport. The failing terminal result remains in `/tmp/bloomy-efficiency-20261001/popup-outer-scroll-focused-01.log`; no missing-view or zero-extent case was skipped.

The final outer layer is a local native `NSScrollView` with one retained SwiftUI document controller. It explicitly sizes the document and caps the viewport independently. Inherited `EnvironmentValues` are forwarded, including storage, appearance and accessibility. A local overlay scrollbar preserves the full card width without changing the Mac's settings. Updates retain the host/root identity and clip state; teardown clears the weak size callback and releases the hosted subtree. It adds no recurring timer or provider action. An independent read-only review found no actionable sizing, draft or lifetime defect.

Native 43 direct computer-use checks passed:

- At **80 points**, the outer area exposes real native Scroll Up/Down actions. Scrolling reveals Cooling and Auto/Nudge, Available expands and collapses, the downloaded cards are reachable, and scrolling both nested areas reaches the final jobs row. This proves manual accessibility scrolling, not the complete keyboard or physical-wheel matrix.
- Nudge opens the full setup guide from the scrolled popup. No key was entered and no request was sent.
- Auto opens correctly, a GPT-OSS startup choice survives Refresh, and the inert Save action returns saved/readback feedback. No real configuration was written.
- Cooling opens, Refresh advances the fake capture time, and Tab/Space opens Fan policy. An unsaved Quiet draft retains its **60% / 45 °C** values through Refresh and closing/reopening the sheet. No administrator action or fan-policy write was performed.
- At **240 points**, whole-popup scrolling reaches Available and the complete Earnings/electricity/jobs footer.
- In dark/grayscale review, the current-screen popup measures **560 × 605 → 560 × 709 → 560 × 605** across Available expansion/collapse. Header placement and every recorded content rectangle fit the actual screen.
- At **360 points**, the header stays visible while the independent body scrolls through expanded Available content to the footer. The geometry record measures **560 × 360**.

Native 43 manifest: `.build/native-dashboard-fixture-20261002-43/fixture-manifest.json`; all 85 production source hashes match the final source, and actual binary SHA-256 matches `59e33ca97bc9aba4f807791c83034e4ef8d7037ba2ce0868c3b5295916fe77d8`. Runtime report directories under `/var/folders/j3/qksc1twx2wz80r7_8w58qzzw0000gn/T/` are `BloomyDashboardFixture-064FAA50-6E0C-4CC0-BA91-4656A0A22047/` (80/240 points and editors) and `BloomyDashboardFixture-5047FBC3-B5DD-41B0-BFD9-8F666EF22385/` (actual-screen/dark/grayscale/360 points). Both fixture runs were quit normally and process absence verified. Screenshots and native accessibility states were inspected in the session; no saved screenshot artifact is claimed.

Final full run 02 passed **1,267 tests**: telemetry 1,218 / 160 suites in 24.326 seconds, protocol 21 / 5 in 0.015 seconds, host 28 / 9 in 11.729 seconds. The 80-point regression requires the identified outer scroll view, an actual document taller than its viewport, exact 528-point document/viewport width, overlay style, and changed visible-document origin after scrolling. Final release build 02 completed in **43.68 seconds**. Both commands exited 0 without compiler warnings/errors. These final results cover the corrected wrapper; the CPU ownership and Chat source remain the same bytes previously verified.

Production PID 31677, the installed executable hash `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`, and provider configuration hash `18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229` remained unchanged.

Actual VoiceOver, system Reduce Motion delivery, genuine cover occlusion, production privacy/removable-drive access, and signed updater distribution remain separate review gates. No complete native-matrix or distribution claim follows from this checkpoint.
