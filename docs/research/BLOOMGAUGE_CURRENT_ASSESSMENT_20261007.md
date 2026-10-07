# BloomGauge comparison: current assessment

Checked October 7, 2026 against Bloomy main `fc6b2f0`, with concurrent local-credit-attribution edits observed but not treated as verified or shipped. This assessment supersedes the earlier comparison's current-state claims about missing exact credit capture and missing Overview charts.

Bloomy has the stronger foundation for a native Mac control app. BloomGauge has a clearer earning narrative and advertises more complete setup and remote access. Neither source inspection nor screenshots establishes which app earns more, uses less power or behaves more reliably in production.

## Evidence and limits

Reviewed the current [website](https://bloomgauge.io/), [features](https://bloomgauge.io/features), [guide](https://bloomgauge.io/guide), [changelog](https://bloomgauge.io/changelog), [privacy notice](https://bloomgauge.io/privacy) and public source. A fresh GitHub API request confirmed public main at `724ce679e407eba0806cd03e94f303c4fb728468`; the architecture hash matches the retained research copy. Five retained vendor screenshots were visually inspected: dashboard, demand, switch rules, day replay and readiness. A fresh image request returned HTTP 403, so their bytes were not revalidated against today's website. The in-app browser was unavailable. No competitor binary, live interactions or comparative performance benchmark was tested.

The homepage lists 1.36.73 beta 54; the changelog's latest entry lists 1.36.72 beta 53. Public-core behavior is separate from current downloadable-app claims. Their September 29 [comparison](https://bloomgauge.io/help/darkbloom-apps-for-mac) describes our former Darkbloom Control and is not a current inventory of Bloomy.

## Product comparison

| Area | BloomGauge's published offering | Bloomy's current source |
| --- | --- | --- |
| Earnings | Pace gauge, hourly composition and a day replay. | Native Overview/Activity charts, credit composition, scoped reports and correction-aware records. Joined replay remains missing. |
| Model choice | Switch rules with loading cost and simulated outcomes. | Sustained confirmation, minimum residence, return wait and profit thresholds. Better explanations and outcome review would help. |
| Demand | Comparable model scales and historical context. | Requests per warm provider exist; persistent per-model baselines and sparklines do not. |
| Recovery | One diagnosis screen and bounded recovery. | Health, nudges, alerts, GPU protection and lifecycle controls exist, but explanations are scattered. |
| Setup and remote use | Guided provider setup and private phone/multi-Mac access. | Narrow setup guides and substantial companion foundations exist; full onboarding and production companion delivery remain unfinished. |
| Mac controls | Hardware monitoring. | Native model management/deletion, fans, host-GPU protection, chat and dense menu-bar controls provide broader local control. |

Competitor descriptions are vendor claims from the feature inventory and guide. Bloomy descriptions are source findings, not a claim that every feature is distributed or fully qualified.

## The current Manager is different from the older optimizer

The current [guide](https://bloomgauge.io/guide) describes holding a home model chosen from this Mac's past earnings, with similar-chip/memory evidence used before enough local history exists. Automatic departures require sustained evidence from at least five similar Macs over two hours, with at most three moves per day. Failed automatic loads receive increasing exclusion periods. The guide distinguishes that approach from its older demand-following learning mode; public-core code and switch-rule screenshots cannot establish the exact current implementation.

For Bloomy, the useful lesson is conservative ownership and explicit uncertainty. Darkbloom's live Autopilot should retain model selection authority; Bloomy can explain its state and observed outcomes. When Bloomy owns selection, prefer measured local evidence, loading reliability and a clearly stated decision budget. A shared earnings-prior service would introduce data-sharing, normalization and maintenance work; it is a later product choice, not a prerequisite for a useful local app.

The guide says recovery respects manual stops, schedules, Autopilot, accepted work and network-wide problems. These are important behaviors to verify before broadening Bloomy's recovery. A quiet earnings feed alone cannot prove a stalled provider. This review does not validate BloomGauge's advertised recovery in a running binary.

## Visual details worth adapting

The inspected demand screenshot uses a common ruler, a current marker, a typical marker and a small history graph. Adapt that hierarchy to our native model cards: short name and state first, demand graphic next, throughput and last observation in one compact row. Put units, history coverage and full identifiers in details and accessible help. The screenshot's pay-colored zones are model-relative estimates, so they should not be presented as universal network thresholds.

The day replay combines a total, work/base composition, model bands and reasons for gaps. Bloomy's version should also reveal loaded-but-no-observed-work visits, which directly answers Kevin's concern about switching away before receiving work. Join existing evidence rather than adding another separate list. Reward arrival and serving time must remain distinguishable.

Use the readiness screen's visual hierarchy: a concise summary, evidence-backed states and one relevant action. Do not reproduce its asserted payout chain as official Darkbloom requirements. Overview can show a compact summary; Health can hold the detailed evidence. The popup should remain a quick control surface with stable geometry, not a scaled-down copy of their full dashboard.

The dashboard's earning-rate gauge is visually strong, but a simple native trend with a clearly defined baseline will be easier to read than another ring alongside our model/GPU/fan rings. Retain confirmed account totals separately from forecasts and locally attributable earnings. Use symbols or labels as well as color, and keep motion restrained.

## What to improve first

1. **Finish the financial attribution prerequisite.** Exact account/provider/model credit capture and session-safe charts now exist. The next critical boundary is proving which historical provider identities belong to this Mac; retention and legacy-history disclosure also remain open. A current connection ID, matching model name or single provider on the account is insufficient. Concurrent code introduces an explicit local-report capability; it is not a completed production resolver. Keep account credits available, but do not use them as local profit or match them to this Mac's electricity without proof. Whole-Mac GPU and power measurements must retain their scope.

2. **Create one readiness explanation.** A pure evaluator should combine connected, authorized, accepting work, model ready, work observed and credits received, each with observation time and uncertainty. Overview gets a compact strip; Health gets evidence and one useful action. Distinguish quiet demand, accepted long-running work, stale readings and a failed provider. This should reuse existing controls rather than introduce another restart loop.

3. **Join Activity into a daily story.** Align model residence, observed work, loading, nudges and credit arrivals. Reuse `ModelVisitHistory`, performance samples, action history and scoped reports. Make unknown intervals visible. A credit arriving after a switch cannot automatically be attributed to the newly loaded model, and before/after observations cannot prove the income a different choice would have produced.

4. **Give model cards historical demand graphics.** Add one small demand bar and sparkline, with current/typical markers. Store validated observations with numerator, denominator, interval, timestamp and coverage in bounded SQLite history. The existing network-wide series is not per-model history. Zero warm providers means the ratio is undefined. Earnings-based color zones require attributable financial evidence; demand alone cannot establish profit.

5. **Explain switching economically.** Show supported net advantage, measured loading time, estimated payback and next eligible decision. Keep advanced timing in a disclosure. For positive incumbent projections, current policy requires a gain of at least the greater of 30% and $0.05; the zero-projection case uses the dollar floor. Default timing is ten-minute confirmation, sixty-minute residence and a three-hour return wait; these timings are configurable. Extend that policy with round-trip cost and measured outcomes rather than replacing it with a second optimizer. Respect live Darkbloom Autopilot as selection owner. Recommendation replay is not a financial backtest.

6. **Complete onboarding and companion delivery.** Resumable setup should inspect installation, authentication, selected cached models and readiness, retaining only nonsecret progress. Reuse model/lifecycle controls. Companion helper main currently exits deliberately and Settings says Coming soon; finish signed agent registration, approval IPC, live snapshots and physical-device/Tailscale validation. When the helper becomes the persistent command owner, the Mac app must route through it too.

## Stack recommendation

Keep SwiftUI/AppKit, native Charts, actor-owned telemetry and SQLite. BloomGauge's [public architecture](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/docs/ARCHITECTURE.md) uses a Swift/WKWebView shell, bundled Python collector, React/Vite dashboard and Tailscale phone listener. Its shared web UI aids phone reuse but adds runtime and HTTP boundaries. This is a tradeoff, not proof of inefficiency.

Bloomy's valuable improvements are shared read models, bounded history and one command authority. `ProviderControlStore` already serializes local operations; retain that protection across Autopilot, manual actions, profit switching, GPU protection and eventual companion commands. Derive views from immutable evidence instead of adding independent pollers. Preserve hidden-view suspension and last-good readings without marking stale values current.

Profile matched Release conditions before claiming a lighter stack: process-tree CPU, resident memory, wakeups, database growth and refresh latency, visible and hidden, with equivalent history and provider conditions. The broader native motion gate remains 12/15 in the existing review record; this research does not qualify it or a release.

The concrete stack work should be a shared immutable readiness snapshot, batched SQLite reads, bounded demand samples with longer-lived rollups, and a single command admission path. Record refresh/query duration and dropped or stale samples in the existing performance journal. Do not add a poller per card or a background optimizer merely to support a new chart. Treat companion delivery as its own signed, authenticated product boundary.

Their current [privacy notice](https://bloomgauge.io/privacy) also documents new-install setup/usage sharing defaults that differ from the older architecture description's broadly opt-in framing. Any future Bloomy shared-prior or diagnostics service should have explicit, separate choices and a clear account of what leaves the Mac. This review adds no reporting service or telemetry upload.

## Recommended next milestones

| Order | Deliverable | Evidence needed before calling it complete |
| --- | --- | --- |
| 1 | Reliable local attribution and stable financial presentation | Historical account/provider ownership across reconnects, corrections and account changes; stale and missing states remain explicit. Account charts can remain useful before this is available. |
| 2 | Compact readiness summary shared by Overview and Health | Fixtures distinguish manual stop, network quiet, accepted work, stale data and provider failure; each offered action uses existing command controls. |
| 3 | Joined day replay in Activity | Model visits, observed work, loading, actions and credits align without assigning credit arrival to the wrong residence. Unknown periods and no-observed-work visits are visible. |
| 4 | Demand graphics on native model cards | Bounded per-model history, validated interval/denominator, freshness and coverage; compact/wide and accessibility inspection. |
| 5 | Clear hold/switch explanations and measured outcomes | Supported advantage and round-trip loading cost; no simulated earnings shown as paid money; live Autopilot ownership preserved. |
| 6 | Resumable first-run setup and delivered companion access | Real clean-install, signed helper, authentication and physical-device validation, beyond fixture/protocol tests. |

Resource qualification should accompany these milestones: compare Release process trees with matched retained history, first with inert telemetry and then with an explicitly authorized identical provider workload. Measure visible dashboard, closed dashboard and popup separately. Keep raw measurements and report idle CPU, memory, wakeups and query/refresh latency; do not infer savings from language choice or download size.

The published screens offer useful hierarchy, particularly day replay and demand markers. Implement those ideas as original native components. Avoid importing their prose-heavy dashboard wholesale into the compact popup, and avoid adding credit animation while motion stability remains open.

## Source anchors

- `Sources/DarkbloomMonitor/Dashboard/DashboardOverviewView.swift`: mounts `OverviewEarningsView` and collapsible hardware.
- `Sources/DarkbloomTelemetry/AccountCreditLedger.swift`, `ScopedAccountCreditReport.swift`, `AuthenticatedEarningsClient.swift`: exact credits, scoped reports and financial sessions.
- `Sources/DarkbloomTelemetry/TelemetryService.swift`, `ModelVisitHistory.swift`, `NetworkCapacity.swift`, `ProfitSwitchPolicy.swift`: reusable evidence and decisions.
- `Sources/DarkbloomMonitor/ProviderControlStore.swift`: serialized command admission.
- `Sources/DarkbloomCompanionHelper/main.swift`, `Sources/DarkbloomCompanionHelper/HelperRegistration.swift`, `Sources/DarkbloomMonitor/MonitorSettingsView.swift`: incomplete companion delivery.
- `docs/FINANCIAL_SESSION_UI_REVIEW_20261007.md`, `docs/APP_POLISH_OPTIMIZATION_PLAN.md`: prior verification and remaining gates.

A bounded native source review confirmed the three leading UI opportunities and corrected the timing description to distinguish configurable defaults from fixed gain gates. It also noted that `ProfitSwitchStore` uses `max(1, warmProviders)` for heuristic pressure while `NetworkCapacity.demandPerWarmProvider` returns unavailable for a zero denominator. A shared demand read model should preserve the latter semantics rather than display that heuristic as a measured ratio.

This update is documentation only. Existing implementation work and production state were preserved. Concurrent local-attribution work is not committed or qualified for delivery by this report. This assessment does not establish competitor performance, final native visual qualification or release readiness.
