# Native indicator appearance changes — October 7, 2026

The production activity arc now refreshes its fixed CGColor when AppKit changes
the view's effective appearance. It retains the last configured dynamic NSColor
and resolves it through the existing view-local drawing context. The callback
disables implicit layer actions and changes only strokeColor. It adds no timer,
configure call, animation reset, visibility repair or geometry change.

## Regression and native behavior

The mounted unit regression configures green, yellow, red and neutral once per
tint, then requests Dark Aqua and Aqua on an owned unshown window. It requires
the requested effective appearance, matching RGBA, unchanged geometry/attachment
and no compositor clock on the unshown window. It does not manually invoke the
appearance callback or configure/layout/display during transitions. Layout is
initialized once during setup before capturing the geometry baseline.

The initial pre-callback run failed four RGBA checks and two geometry checks.
After the callback repair, the full suite failed only those two geometry checks:
the test captured a zero layer frame before AppKit's first layout. Initializing
the baseline fixes that test defect without changing production layout. The
final five-test indicator suite passes, and the full Release command exits 0
with 1,651 reported tests (1,602 + 21 + 28), including seven existing opt-in skips.
All 32 staging checks and git diff --check pass.

The actual production Settings diagnostic retains its nine earlier input and
lifecycle cases and adds window appearance changes with no new daemon publication
or extras read. All ten cases pass in the optimized build. The new case requires
the same native view/layer, original geometry, one unchanged 1.4-second clock,
requested effective appearance and exact view-resolved green. Its two holds are
1.756 and 1.712 seconds. Dark Aqua resolves VibrantDark green to
[0.235294, 0.882353, 0.333333, 1]; Aqua resolves VibrantLight green to
[0.117647, 0.764706, 0.215686, 1]. The inert extras read count remains seven and
the daemon publication timestamp is unchanged throughout both holds/restoration.
The original nil window appearance is explicitly restored and verified before
success; defer also restores it on every exit.

All fourteen Settings holds exceed 1.6 seconds (1.700–1.812 seconds), preserve
native identities, geometry and the one clock, and have advancing compositor
angles before and after. Terminal success verifies stopped retained clocks,
owned production-window closure and no report write errors. CUA inspected the
actual light Settings preview and terminal pass, then a fresh dark Settings
preview. A normal Quit during that second process's fan ramp produces three
passed and seven explicitly cancelled cases, verified stopped clocks and owned
window closure. This does not qualify cancellation during an appearance hold.

Both optimized builds exit 0 and match all 123 current source hashes; the
production label is unmodified by staging. The ordinary control omits the
Settings diagnostic and runs the original native gate. It remains 12/15:
opaque cover, normal retained reopening and rapid retained reopening fail.
No cases are missing; Models and Charts pass. Cover cleanup reports exit 0 and
window closure. All four owned PIDs (53822, 54171, 54718, 54732) are absent.

## Artifact provenance and remaining gates

- Diagnostic root: `.build/settings-appearance-change-fixed-20261007`.
  Binary SHA-256: `8d6eb8220f9a4d1c2d031059ffb572918491690e663eea200ae20750c956b81e`.
  Manifest SHA-256: `82423467d0284c0f148bbdd63cedaa11c4561c459dc91212a2095a3bb405b5a9`.
- Completed report: `runtime-evidence/EC832623-E512-45A4-B80C-5414B7B256B9/settings-preview-result.json`.
  SHA-256: `6e404a818d7d1c3ee2c50666690504eeb62b8894fe03470fa221c1601d3e6af5`.
- Cancelled report: `runtime-evidence/D6F3450F-A583-456B-96FA-565AE9C1CCF9/settings-preview-result.json`.
  SHA-256: `c690c5344ed0f8d5f6dd1dccfd97a2af79690b3856206a4aa1339eb5ee2b23ed`.
- Ordinary root: `.build/settings-appearance-change-fixed-control-20261007`.
  Binary SHA-256: `642fa620509f461497ca4e9ff005996c1e3f7277ed8cf260bf9ecec329b9366b`.
  Manifest SHA-256: `6cc969b6a09495488db69b720efca32e7aa87da8fd37fb9c631796d0e9f7ea63`.
  Motion report: `runtime-evidence/BloomyDashboardFixture-1D3C3652-5EA7-4C25-A911-49C98AACD5B1/motion-lifecycle-proof.json`.
  SHA-256: `eb07696dfeaebc65c88a33c6c8bd0fb6ae582f5ccf237c0103609bfa50cc946c`.

`runtime-summary.json` under the diagnostic root indexes hashes, exact appearance
evidence, all holds and verified process absence. Test logs are
`.build/settings-appearance-change-{red,release-tests,focused,final-release-tests,staging}-20261007.log`.
The first full Release log contains the rejected geometry-baseline failures;
only final-release-tests is the green full-suite result.

Provider configuration remains SHA-256
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`;
the unrelated dirty MenuBarMotionProof remains SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
No provider commands, inference, sensors, installation or global settings changes
were made. Physical foreground pixel motion, real sensor/fan fill behavior,
system Reduce Motion delivery, genuine cover, the ordinary gate and broader
application polish remain open. This is a bounded checkpoint, not a release or
completion of the ongoing improvement goal.
