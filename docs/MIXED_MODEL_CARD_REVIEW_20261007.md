# Mixed model-card history qualification

Local checkpoint against production source `5658487`. No production view or
provider behavior changed. The missing review coverage is now reproducible with
the native fixture's **Mixed model history** scenario.

## Controlled inputs and result

The fixture supplies five hours of private synthetic power intervals: two active
hours each for Qwen and Gemma, then one idle hour. A qualified current-day recorder
provides Qwen 52.7 tok/s from 116 synthetic samples; other rates remain absent.
The existing explicit synthetic-local-credit gate lets the production store derive
estimates from the fake financial client. This does not establish real historical
machine ownership or relax the production financial guard.

The first fixture mistakenly toggled the previous scenario's financial client.
Native inspection showed speed but no earnings, so it was not counted as mixed
earnings proof. The corrected fixture toggles the newly prepared client before
publication. Native accessibility then confirmed Gemma earnings-only, Qwen speed
and earnings, and GPT-OSS learning/no-history states together. The figures are
synthetic estimates; small currency values retain the existing cent rounding.

Computer Use inspected the final optimized artifact:

- Wide light/dark: three enabled cards have aligned rulers, metrics and controls
  despite different history content. Two disabled downloaded cards remain in
  Available, with explicit unavailable demand where appropriate.
- Compact dark: the full-history card remains readable with both metrics and its
  controls. Compact light/grayscale retains state labels and numeric demand.
- Available collapses/removes its card rows and reopens them without staging
  model changes. Manage opens Qwen's detailed evidence and independent what-if
  assumptions; dismissal returns to the cards.
- Accessibility preserves canonical IDs, speed samples, estimated net units,
  shared demand denominator/scale and missing-history states.

This is focused native inspection, not full VoiceOver, large-text, motion,
occlusion or production-serving qualification. Undownloaded catalog geometry is
covered by the regression, not claimed as present in this scenario.

## Verification and provenance

- `swift test -c release --filter ModelCardSummaryRenderingTests`: six tests pass,
  including learning, speed-only, gross-only, full-history and undownloaded actual
  card faces at 300, 344 and 460 points. Heights differ by less than one point.
- Final native staging suite: 47 tests pass.
- Corrected optimized fixture build exits successfully. All 132 source hashes
  match the current tree. No new full package or production build is claimed;
  production source is unchanged from the preceding verified checkpoint.

Artifact: `.build/mixed-model-cards-final-native-20261007`.
Manifest SHA-256: `9d3d796c2bf6b5b4dba9a8f91a1c353d8b41f5245af0177da53ce0365df0643e`.
Binary SHA-256: `96845416a253ee5baf2a5636888cda595cd99d513b2886850d90164cd7e5e253`.
Logs: `.build/mixed-model-cards-focused-20261007.log`,
`.build/mixed-model-cards-final-staging-20261007.log`,
`.build/mixed-model-cards-final-build-20261007.log`.

Both owned review apps exited normally, confirmed by process inspection after
dismissing the details sheet. No finite build/test or review process remains.
Provider configuration and the concurrent motion helper retain their prior
hashes. No production app replacement, provider command, download, inference,
privacy change, push or release occurred.

The comparison's next demand-history step is documented in
[the bounded integration design](research/NETWORK_DEMAND_HISTORY_DESIGN_20261007.md).
Historical local financial attribution, joined loading/credit replay, onboarding,
Companion delivery and broader native/performance qualification remain open.
