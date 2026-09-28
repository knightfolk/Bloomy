# Native dashboard redesign — 2026-09-28

## Scope

Approved native SwiftUI redesign. “Marble” was a transcription error for “model”;
there are no decorative marble textures or web-based replacements.

- Shared compact model cards use family icons, short names, full canonical-ID help,
  explicit state, measured speed, and separately labeled derived earnings when present.
- Popup identifies the Mac, shows whole-Mac GPU utilization and available fan readings,
  and opens the existing fan-control view through the existing serial mutation gate.
- Advertised models come from fresh runtime advertising data, independently of saved
  enablement. A confirmed stopped provider advertises none. Missing and empty sets differ.
  The second popup group contains other downloaded models on this Mac.
- Earnings and electricity share a panel. Observation coverage, account attribution,
  active-hour denominators, and estimated power/net values remain explicit.
- Overview has a stable compact summary, resource gauges, and shared model cards.
- Activity uses uniform model filters, stable segmented controls, and compact earnings cards.
- Opportunity uses a responsive comparison grid and collapsed recommendation reasoning.
- Models supports one/two/three columns at 614/928-point content breakpoints.
- Health prioritizes status, issues, and source capture information. Logs provides a native
  selectable table, compact local times, adaptive filters, and scrollable full details.

No provider configuration, fan setting, model selection, model storage location, or
production installation was changed during verification.

## Verification

- Full SwiftPM suite: 810 telemetry/UI tests, 21 protocol tests, and 28 host tests passed.
- Subsequent focused checks passed after presentation refinements, including advertising
  missing/empty/future/stale/stopped cases, names, log queries, energy, and native renders.
- Release build passed; native fixture views were inspected at narrow and wide sizes.
- Live Beta verified: Overview/resource readings, Health/Logs navigation, log selection
  and full details, and all 10 catalog models in the three-column Models view.
- Enabling render evidence for the entire suite slowed a time-sensitive pre-existing
  provider-confirmation fixture past its freshness window. The ordinary full suite passed;
  native capture was verified separately with focused runs.

## Review provenance

MiniMax Code visibly used M3.1-Flash-Preview for the authorized read-only design review.
Codex checked its claims and corrected the claims about missing log severity affordances,
missing electricity waiting state, and saved-enabled versus runtime-advertised models.
MiniMax acknowledged the design decisions and supplied a review checklist. Its subsequent
integration audit ended with “Something went wrong” before returning findings; that pass
is not counted as a completed audit and was not retried or routed to another provider.

## Local review launch

The isolated bundle is `DC Beta.app`, identifier `dev.darkbloom.monitor.beta`.
Production Darkbloom Control and the provider remained running.

Launch Services and launchctl launches timed out loading provider controls. Starting the
same packaged executable directly from the command runner successfully loaded the live
catalog, whose effective cache is `/Volumes/Sol/LLMS/HuggingFace-cache/hub`. This reproduces
the existing review-launch distinction recorded in FAN_GPU_CARDS_REVIEW_CHECKPOINT.md;
it does not establish the root cause as TCC or an external-drive fault. The models were
not moved. The final Beta is left running via direct execution for review.

Beta uses an independent local history namespace, so a newly launched Beta can initially
show “Learning” or awaiting-coverage states even while production has historical data.
No historical earnings were copied or invented to fill those states.

Final review artifact: `.build/redesign-delivery-20260928/DC Beta.app`, build 18004.
Executable SHA-256: `1a69291a11047c4cad295c21d78de3e325fee22328272084eb10e5870652f224`.
Direct launch of this final bundle again loaded all 10 catalog entries. At handoff,
Beta PID was 18578; production PID 76580 and provider PIDs 85967/85973 were unchanged.
