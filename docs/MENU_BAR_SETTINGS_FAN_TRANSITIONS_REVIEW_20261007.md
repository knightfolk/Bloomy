# Native menu-ring color and fan-transition review — October 7, 2026

The production activity ring now resolves dynamic colors in its own native
appearance. The full Release suite and all nine bounded Settings cases pass;
cancelled Quit verifies cleanup. The ordinary gate retains its three known
cover/reopening failures, so this checkpoint is not release readiness.

## Confirmed defect and narrow repair

The actual production Settings preview was exercised with independent synthetic
fan readings. The first extended run passed the original seven lifecycle cases,
but failed both new fan-transition cases. An appearance diagnostic then recorded
the native view as VibrantLight and its window as Aqua. The layer used Aqua green
initially and Dark Aqua green after activity updates, rather than the view's
resolved VibrantLight green. The stale neutral also resolved as Dark Aqua white.
The readings, native identities and geometry remained valid. This is a native
color-resolution defect, not evidence that the temperature source failed.

Production ActivityArcView.configure converted a dynamic NSColor to a fixed
CGColor under the ambient drawing context. The repair resolves only that color
inside the native view's effectiveAppearance.performAsCurrentDrawingAppearance.
No timing, animation, observer, visibility, geometry or thermal threshold rule
is changed. Appearance-only changes without configure are not newly qualified.

A deterministic regression configures four tints (green, yellow, red, neutral)
under a contrary drawing appearance, for Aqua, Dark Aqua, VibrantLight and
VibrantDark views. Before the repair all sixteen combinations fail exact RGBA
comparison; after the repair the full Release suite passes, including this test.
The test does not change global Mac preferences or prove physical motion.

## Independent input proof

The opt-in Settings fixture retains the production window controller, root and
navigation. An isolated never-started MonitorStore receives counted explicit
reads from an inert ProviderExtrasProviding actor. It creates measured synthetic
RPM against a 6,000 RPM maximum, not fan targets. No CLI, network, sensor, fan
mutation, provider command or polling occurs. The actor and helper are compiled
only under FIXTURE_SETTINGS_PREVIEW_PROOF.

Nine cases retain the original seven lifecycle checks and add a 54/70/85 °C
color ramp with 25/50/100 percent fan readings, plus a failed-read/recovery case.
The latter establishes and observes its own red baseline before failure, so an
earlier failure cannot cascade or coalesce away the fresh-to-stale transition.
The real extras store must retain the complete old payload and capture date as
stale; native color must become neutral while fresh daemon inference stays
active. Recovery supplies 54 °C and 75 percent fan speed. All input changes must
retain native view/layer identities, original geometry and exactly one unchanged
1.4-second rotation clock. RGBA expectations use the native view appearance,
including material appearances, and are recorded alongside actual components.

Successful motion observations use a publication-free compositor hold exceeding
1.6 seconds, with advancing angles before and after. There is no forced configure,
animation mutation, layout, display, flush or synthetic visibility notification.
These checks do not establish cooling-ring fill pixels or real sensor behavior.

## Verified checks and remaining gates

The full Release command exits 0: 1,650 reported tests across the three targets,
with seven existing opt-in skips. The new regression fails before the repair and
passes after it. All 32 staging regressions pass. A bounded native read-only
review found no remaining material code finding.

Both final optimized builds compile at exit 0 and their manifests match all
123 current source hashes. The production label bytes are unchanged by staging;
the diagnostic definition is absent from the ordinary control. CUA inspected
the actual wide/light Settings screen at 54 °C/25 percent and 85 °C/100 percent,
then the terminal console result. These snapshots show native rendering;
physical foreground pixel motion and quantified cooling-ring fill are not
claimed. The compositor evidence is listed below.

| Native Settings case | Result | Publication-free hold |
| --- | --- | --- |
| Baseline | Pass | 1.754 s |
| Ten fresh publications | Pass | 1.718 s |
| Active → idle → active | Pass | 1.807 s |
| Independent fan/temperature changes | Pass at 54, 70 and 85 °C | 1.724 / 1.779 / 1.749 s |
| Failed fan read and fresh recovery | Pass; retained payload/date, neutral then green | 1.774 / 1.769 s |
| Navigation departure and return | Pass | 1.743 s |
| Minimize and restore | Pass | 1.719 s |
| Retained close and reopen | Pass | 1.727 s |
| Rapid close and reopen | Pass | 1.727 s |

All twelve holds exceed 1.6 seconds, preserve the one 1.4-second clock and
stable geometry, and advance by over 0.1 radians before and after the hold.
Fresh green/yellow/red and stale neutral match the view-resolved RGBA values.
The failed fan payload/date are retained through the real store merge, with
fresh daemon activity and a running clock; recovery restores fresh readings.
Terminal completed/passed verifies stopped retained clocks, closed owned window
and no report write errors. A separate process was cancelled during the fan
ramp: three cases passed and six explicitly cancelled; terminal cancelled,
cleanup and window closure are verified before the process exits.

The freshly run ordinary fifteen-case gate is still 12/15: opaque cover,
normal retained reopening and rapid retained reopening fail. No cases are
missing; Models and Charts pass. The distinct cover helper exits with status 0
and reports its owned window closed. This does not replace, weaken or repair
that gate. All six owned parent/cover PIDs (39739, 40998, 43919, 44016, 44075,
44091) are confirmed absent after cleanup. No finite task remains running.

No release or installation claim is made. Genuine cover, normal standalone
lifecycle proof, appearance-only changes without configure, system Reduce Motion
delivery, physical foreground motion and the broader native matrix stay open.
The previous attempt to inject SwiftUI accessibilityReduceMotion failed to compile
because it is a read-only environment key; that unsupported override was removed
and never executed. Global Mac settings remain unchanged pending Kevin's choice.

Preserved pre-fix evidence:

- Initial extended result: .build/settings-fan-inputs-20261007/runtime-evidence/77B88860-A7E9-41DF-B424-F0AFD4BE7C8B/settings-preview-result.json,
  SHA-256 7e42fe4f9c4a98b5f98698b54999c0f26323e4f243fa7787b28a8b4a8831a162.
- Appearance diagnostic result: .build/settings-fan-appearance-probe-20261007/runtime-evidence/F1AAED5E-F7C2-433D-AF3B-DCFD91D1B88A/settings-preview-result.json,
  SHA-256 9e34c627dee3bd65f3e10c63158f7b3d51f39d8b4be601694c5fd918bd6664eb.
- Deterministic pre-fix regression: .build/settings-fan-appearance-red-20261007.log,
  exit 1 with sixteen RGBA expectation issues after a successful compile.
- Full repaired Release suite: .build/settings-fan-appearance-release-tests-20261007.log.

Both pre-fix native invocations reach terminal completed/failed with verified
clock cleanup and owned production window closure. Their owned parent PIDs
39739 and 40998 are absent after CUA Quit. Credentials and provider configuration
were not changed. The unrelated MenuBarMotionProof edits remain preserved.


## Final artifact provenance

Diagnostic root: `.build/settings-fan-appearance-fixed-20261007`.

- Binary SHA-256: `4e5567498b0298a4485ca3514322d8763f2f21d1b9083e4e3c955f19ffde98cc`.
- Manifest SHA-256: `6ae49bf7d1ffd0ede75dcdc1137dd63af2f79fe3aea82001a6b0d6c026a7d48e`.
- Completed report: `runtime-evidence/B533C3D9-845B-430F-AF99-38DB27CBB6C6/settings-preview-result.json`,
  SHA-256 `9d72e0760c134d3315846032d2534ed6308105ef71f34eeed7eaaeaa6ccfdd94`.
- Cancelled report: `runtime-evidence/28B6257D-9320-468A-85D9-F90267DD029D/settings-preview-result.json`,
  SHA-256 `2fcb4d1668b3a6bc8e7d1322f3ddc976343c7b20aca994d3d99eee8e785819e7`.
- `runtime-summary.json` indexes report hashes, all twelve holds, exact neutral/recovery
  components, matched source counts, ordinary failures and owned process absence.

Ordinary root: `.build/settings-fan-appearance-fixed-control-20261007`.

- Binary SHA-256: `1d038ee7091830ed38d35381eaae5b8e962db2434e783afafd7ed22d375046b2`.
- Manifest SHA-256: `0c93e6f15b7c3343d8a90abbf378042d1cb2f6dd932e799c38fbdca1a639ef30`.
- Ordinary motion result: `runtime-evidence/BloomyDashboardFixture-A9CEE97A-FE56-4D9A-9CA3-66EEDEA9BF77/motion-lifecycle-proof.json`,
  SHA-256 `230642248d0ee348f10b320b2a78a29a0589b5d1444038107e158777d2376351`.

Provider configuration SHA-256 remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The unrelated dirty MenuBarMotionProof remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
No unsupported Reduce Motion override or builder change is retained. Future
work should test appearance-only transitions and actual system Reduce Motion
once authorized, while keeping the genuine-cover investigation separate.
