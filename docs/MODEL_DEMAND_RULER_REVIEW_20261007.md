# Shared model demand ruler

Models and Opportunity now use one native linear demand ruler: network-wide
active plus queued requests divided by loaded providers. The complete network
snapshot sets the common upper endpoint (at least 1); searching, changing draft
selection, or filtering displayed cards does not redefine the scale.

This builds on the BloomGauge comparison's recommendation for comparable card
graphics. It is a current/retained reading, not historical context, local routing
probability or an earnings forecast. Persistent per-model demand history and its
coverage-aware sparkline remain open work.

## Presentation and data boundaries

- A filled accent marker shows a current ratio. A hollow neutral marker and
  “Last” identify retained stale readings. Existing demand bands and network
  request counts remain visible; color does not carry the comparison alone.
- Missing readings and zero loaded providers have no marker and an explicit
  unavailable state. Recorded zero with a valid denominator places the marker
  at zero. Invalid counts cannot inflate the shared scale.
- Tiny positive values and extremely large values use scientific notation when
  needed, preventing a nonzero reading from being formatted as zero.
- Accessibility identifies the canonical model, freshness, ratio, active/queued/
  loaded counts and shared endpoints. Full source scope and units have hover help.
- Models reuses its shared presentation cache, and Opportunity calculates one
  scale before filtering its list. No per-card query, database, new recorder,
  polling schedule, provider command or inference is introduced.
- The popup retains its existing fixed card height and controls; its demand-free
  cards do not receive this dashboard ruler.

## Verification

Five new tests cover common scale and denominator semantics, malformed counts,
extreme values, search/draft/source transitions and rendering four evidence
states at 180/300/460-point widths. The initial render test used exact
floating-point width equality and failed despite matching displayed dimensions;
the final assertion permits less than 0.01 point of renderer difference. No
existing expectation was relaxed. Forty-seven native staging checks pass.

Before the final wording refinement, the serial Release suite passes: 1,753 telemetry/UI tests, 21 protocol tests and
28 host tests, totaling 1,802 reported tests with seven existing opt-in skips
(`.build/demand-ruler-serial-release-20261007.log`). After making the loaded-provider
unit explicit and correcting unavailable accessibility wording, the focused
Release run passes all 16 tests in three suites
(`.build/demand-ruler-final-focused-20261007.log`).

Computer Use inspected the final optimized artifact:

- Wide Models preserves three aligned columns. Current values of 2.4, 1.67,
  3.5 and 1.14 share a 0–3.5 axis. Canonical IDs and active/queued/loaded counts
  are present in separate accessible ruler elements.
- Searching for Gemma retains the 0–3.5 endpoint and its 2.4 reading. Clearing
  the search restores the catalog. Available collapses and reopens its cards.
- Compact 800-by-560 Models renders a readable bounded card and fixed controls
  footer in light, dark and grayscale. Numeric values and marker positions
  preserve meaning without color.
- The controlled demand-state scenario displays no marker and “Unavailable / No
  loaded providers” for Gemma with 11 active, 1 queued and 0 loaded providers.
  GPT-OSS with 0 active, 0 queued and 6 loaded providers has a filled zero marker.
- Opportunity shows the same ratios/endpoints and evidence states, including
  compact dark two-column and wide light cards. Search does not rescale it.
- A failed-source scenario retains neutral hollow markers and “Last” values in
  Models; Opportunity accessibility also reports last-known ratios and counts.
  Missing model readings remain unavailable with no marker.

Final artifact:
`.build/demand-ruler-final-native-20261007/Bloomy Dashboard Fixture.app`.
All 132 source hashes match the current tree. Manifest SHA-256:
`cc61abc34d2d7c033c0eaabf629db1e9d9953b11df732add2a309cf714bc8746`;
binary SHA-256:
`b216a25dfa177cbd2e15d33dc692e3606a8be59440336cd6a6021da6f256155b`;
linked telemetry SHA-256:
`8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`.
Baseline, preliminary and final review apps quit normally. Process inspection
confirms no remaining DashboardFixture process; the protected motion helper and
provider configuration retain their pre-task hashes. Final production Release
build passes (`.build/demand-ruler-production-build-20261007.log`, 45.56 seconds).
All finite jobs are joined and whitespace checks pass. No production app
replacement, push or release is included.

This is bounded native/AX inspection, not broad VoiceOver/large-text acceptance
or comparative CPU, battery, memory and wakeup qualification. Historical demand,
joined loading/credit replay, financial attribution and native motion/occlusion
gates remain open.
