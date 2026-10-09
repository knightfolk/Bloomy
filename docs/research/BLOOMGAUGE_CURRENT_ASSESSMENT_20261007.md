# BloomGauge comparison: current assessment

## Latest checkout refresh

Rechecked October 7 against Bloomy `5658487`, then refreshed for the bounded demand-history implementation. A bounded read-only source audit confirmed the six product gaps below. The earlier `9a65f17` baseline remains useful for the detailed research, but its readiness and timeline status is superseded here. This pass reread the live homepage, features, guide, changelog and privacy notice, and fetched the current public architecture and README directly from GitHub. Four retained vendor captures were visually re-inspected: demand, day replay, dashboard and switch rules. These captures were not freshly downloaded. Computer Use reported that no browser was available, so no competitor binary or live interaction was tested. Unrelated native motion fixture work was preserved.

Bloomy's committed source now includes a shared readiness presentation in Overview and Health, observed model-residence bands, and provider activity intervals aligned to the same time scale. The timeline inspector is committed with native click, drag and accessibility selection verification. Retained actions now align with residence and provider activity, and Models/Opportunity share a current-demand ruler. A bounded local journal and native 24-hour per-model demand sparklines now extend the shared ruler. This is sampled pressure while Bloomy collects, not a recovered server history or a paid-earnings forecast. The earning-day replay remains incomplete: loading and credit arrivals still need one joined report.

| Product question | BloomGauge's published experience | Current Bloomy position | Useful next improvement |
| --- | --- | --- | --- |
| What happened today? | A day replay combines earnings, model stays and gaps. | Account credit charts and an inspectable residence/activity/action timeline exist. | Join loading and credits to the same day report without inventing serving times. |
| Which model is worth considering? | Shared demand ruler, typical marker and history; estimates have evidence-dependent zones. | Models and Opportunity now share current-demand rulers and locally recorded 24-hour sparklines; guarded profit-switch policy exists. | Build attributable earning-versus-demand comparisons after verifying local financial ownership. |
| Why am I getting no work? | A readiness diagnosis and one next action; bounded recovery is advertised. | A shared readiness strip now exists; Health carries supporting evidence. | Qualify all readiness states and connect them to relevant history, rather than treating silence as failure. |
| Can I get started without Terminal? | Guided official-provider install, sign-in, download and startup. | Narrow guides exist; complete resumable onboarding remains unfinished. | One resumable setup flow with explicit steps and progress. |
| Can I check another Mac or my phone? | Private Tailscale dashboard and a multi-Mac view are advertised. | Companion protocols/transport are substantial foundations; Settings still says Coming soon. | Finish packaged helper and real-device delivery before describing this as available. |
| Can I protect my own Mac's responsiveness? | Hardware readings and temperature-aware model checks are documented. | Fan controls, host-GPU protection, model deletion and Chat provide broader local control. | Keep the compact native controls coherent and clearly label whole-Mac measurements. |

### Recommended order

1. Finish historical local-provider attribution. The correction-aware account ledger exists, but the production financial client still does not return a verified local-provider report. A current provider ID or account-wide total cannot justify historical earnings for this Mac. Keep confirmed account credits useful while withholding unsupported local profit estimates.
2. Complete the joined Activity day report. The residence and activity charts are useful building blocks. Distinguish a visit ending without observed work from proven zero work; distinguish credit arrival from request execution. Let the user inspect the evidence and see why Bloomy acted.
3. Qualify the newly implemented bounded per-model demand history and compact card graphics. The shared historical scale, coverage and explicit gaps now exist. Add pay-colored zones only when attributable evidence supports them.
4. Explain existing switch decisions. Show the estimated advantage, load allowance, current hold/return limits and what evidence is missing. Bloomy's defaults already include ten-minute confirmation, sixty-minute residence and a three-hour return cooldown; a second model controller would complicate ownership. Live Darkbloom Autopilot must retain selection authority.
5. Finish complete onboarding, then deliver Companion access. These are real experience gaps relative to the vendor's published offering, even though parts of the underlying code exist.

### Stack recommendation

Retain SwiftUI/AppKit, native Charts and the existing Swift telemetry/SQLite modules. BloomGauge documents a Swift/WKWebView shell, bundled Python collector and React/Vite dashboard. Sharing that web UI with phones is a practical benefit; it also requires maintaining process, HTTP and web/native bridge boundaries. This review establishes neither stack's comparative CPU, memory, battery use or reliability.

Improve Bloomy's shared data flow instead: one immutable screen report, coordinated refreshes, batched database reads, bounded raw history and longer-lived rollups. Adapt earnings refresh to visibility and recent work without introducing timers on every model card. Keep manual commands, Autopilot, nudges, profit switching and host-GPU protection under coordinated ownership. Measure matched Release builds, visible and hidden, before claiming resource savings.

The vendor dashboard's strongest visual lesson is hierarchy: a clear earning summary, a trend and an explanation. For Bloomy, retain the dense icon-first popup and use the resizable dashboard for detailed history. The committed common model scale and timeline selection provide that hierarchy. The newly implemented historical demand narrows one gap; a joined earning-day report remains the next useful addition.

The retained captures also show substantial explanatory text and nested controls. Borrow their visual hierarchy, not their entire layout: one primary earning figure, compact hourly composition, a shared demand ruler, and details revealed through selection or disclosure. Keep confirmed credits, estimated pace and electricity-adjusted results visually distinct. Use shape or labels alongside color, short model aliases with full-name help, and stable control sizes. The menu-bar popup should remain the quick control surface; the dashboard should carry replay and policy explanations.

### Current implementation boundaries

- `AuthenticatedEarningsClient.swift:97` still supplies no verified historical local-provider report. `MonitorStore.swift:618` clears unsupported local profits. Provider IDs retained in credit records are useful evidence but do not alone complete machine attribution.
- Activity still separates Earnings and Metrics, with History separately available. Residence, provider activity and retained actions share an inspectable axis; loading and credits are not yet joined into one day report.
- `MonitorStore.refreshNetworkCapacity()` now records accepted observations into a separate bounded journal after publishing current facts. `NetworkHistoryView` still presents independent server-provided network totals; the new per-model sparklines are local sampled history.
- `ProviderControlStore.swift:140` coordinates command admission; `ProfitSwitchStore.swift:257` yields model-choice ownership to live Autopilot. Add a decision explanation to this existing flow rather than another controller.
- `NudgeSetupGuide.swift:17` provides a narrow setup guide. No complete resumable provider install, sign-in, download and startup journey was found.
- `DarkbloomCompanionHelper/main.swift:5` does not start a service, and `MonitorSettingsView.swift:136` labels Companion unavailable. Protocol and transport code are foundations, not delivered remote access.

Qualification should use matched optimized builds and history sizes, with the provider held in equivalent conditions: startup and refresh latency, process-tree memory, CPU and wakeups while visible and hidden, database size and query latency. These measurements are still outstanding; architecture alone establishes no performance winner. The existing native motion/occlusion proof gaps remain separate from this product comparison.

Sources: [features](https://bloomgauge.io/features), [guide](https://bloomgauge.io/guide), [switch rules](https://bloomgauge.io/help/bloomgauge-switch-rules), [architecture](https://github.com/cookder/bloomgauge/blob/main/docs/ARCHITECTURE.md), [privacy](https://bloomgauge.io/privacy). Bloomy findings were refreshed against `Package.swift`, `ProviderReadinessSummaryView.swift`, `ModelVisitTimeline.swift`, `PerformanceActivityHistory.swift`, `ProfitSwitchPolicy.swift`, `AuthenticatedEarningsClient.swift` and the Companion availability UI. These are source capabilities, not claims that the current installed release includes or qualifies every feature.

### Concrete engineering follow-through

Use the existing native timeline as the spine of Activity. A selected day should show confirmed credits, observed model residence, provider work evidence and actions on the same time axis. Keep loading duration measured separately from residence; retain unknown gaps and delayed credit arrival. The inspector should answer Kevin's original question: did a model leave before any organic work was observed, and what evidence covers that visit?

The shared demand ruler is now accompanied by one history report for model cards and Opportunity. Accepted fresh capacity snapshots persist in a separate actor-owned bounded SQLite journal; historical points, coverage and a common scale derive from one batched read. Keep the server-provided aggregate network series separate. See [demand history integration design](NETWORK_DEMAND_HISTORY_DESIGN_20261007.md). Use a common scale and one small sparkline. A zero warm-provider denominator is unavailable, not zero demand. Avoid a timer or database query owned by each card.

Expose the existing command ownership in one place: manual choice, Darkbloom Autopilot, or Bloomy's eligible automation. Keep `ProviderControlStore`'s operation gate for changes. Explain a hold with evidence, estimated advantage, loading allowance and next eligible decision. A new earnings chart should not introduce another model controller.

Improve financial refresh without making the whole app poll faster. `MonitorStore.earningsPollingInterval` is currently 600 seconds. Consider a shared, rate-limited refresh after observed work and while earnings are visible, then back off when hidden or quiet. Measure API calls, wakeups, query latency and process-tree memory before changing defaults.

The Mac stack remains SwiftUI/AppKit, Charts and Swift telemetry/SQLite. A future phone interface can consume authenticated snapshots from the existing Companion foundation without replacing the Mac UI with a webview. Companion is still a delivery task: its Settings availability reads Coming soon.

Fresh public main remained `724ce679e407eba0806cd03e94f303c4fb728468`; the architecture SHA-256 remained `bfeeb61267e766d29a815836e124bf67e986a954a17d17f7ff2ecbce81a2ec53`. The freshly fetched README says the public core is 1.36.63 and newer setup/Guardian implementation is not public. The homepage advertises 1.36.74 beta 55. Treat current vendor behavior and public implementation as different evidence. No app was installed, provider command run, credential accessed or comparative performance measurement taken for this refresh.

---

Rechecked October 7, 2026 against Bloomy main `9a65f17`. The financial-attribution guard is committed; concurrent readiness presentation work is unfinished and is not counted as shipped. This assessment supersedes the earlier comparison's current-state claims about missing exact credit capture and missing Overview charts.

Bloomy has the stronger foundation for a native Mac control app. BloomGauge has a clearer earning narrative and advertises more complete setup and remote access. Neither source inspection nor screenshots establishes which app earns more, uses less power or behaves more reliably in production.

## Evidence and limits

Reviewed the current [website](https://bloomgauge.io/), [features](https://bloomgauge.io/features), [guide](https://bloomgauge.io/guide), [changelog](https://bloomgauge.io/changelog), [privacy notice](https://bloomgauge.io/privacy) and public source. A fresh GitHub API request confirmed public main at `724ce679e407eba0806cd03e94f303c4fb728468`; the architecture hash matches the retained research copy. Five retained vendor screenshots were visually inspected: dashboard, demand, switch rules, day replay and readiness. A fresh image request returned HTTP 403, so their bytes were not revalidated against today's website. The in-app browser was unavailable. No competitor binary, live interactions or comparative performance benchmark was tested.

The refreshed homepage lists **1.36.74 beta 55**; the changelog's latest entry still lists 1.36.72 beta 53, and the guide links beta 52. The public README explicitly says its core is from 1.36.63 and that newer setup/Guardian source is not public. Public-core behavior is separate from current downloadable-app claims. Their September 29 [comparison](https://bloomgauge.io/help/darkbloom-apps-for-mac) describes our former Darkbloom Control and is not a current inventory of Bloomy.

## Decision after the deeper review

Keep the native stack. Bloomy's useful advantage is direct Mac control: a compact menu-bar surface, host GPU protection, cooling controls, cached-model management and deletion, and local/network Chat. BloomGauge's stronger published journey is getting started, understanding earnings and checking another Mac. There is no comparative runtime evidence that either product earns more or consumes fewer resources.

The inspected screens suggest three original native improvements, in this order:

1. A compact **readiness summary** with detailed evidence in Health and one relevant navigation action. Separate ready-but-quiet, accepted work, scheduled waiting, stale evidence and failure. Do not make unpaid minutes alone a restart trigger.
2. An **Activity day replay** joining model residence, observed work, loading, nudges and credit arrivals. Highlight visits that ended without observed organic work. Keep credits' recorded model/provider scope; their arrival after a switch does not identify when that work was served.
3. **Comparable demand graphics** on model cards: one ruler, a current marker, historical context and a small chart. Pay-colored zones need attributable financial evidence; a demand ratio alone is not profitability.

The largest correctness prerequisite is historical local-machine attribution. On `9a65f17`, production `AuthenticatedEarningsClient` does not supply a verified local-provider report. The new boundary therefore withholds local profit and automatic profit switching when that evidence is absent. This is a useful guard, but it does not finish the resolver. Account credit charts remain useful on their own.

The largest experience gap is complete resumable onboarding. Companion access is also a delivery gap: the Settings UI says Coming soon, and the standalone helper deliberately has no listener or provider authority. Existing transport and pairing code should not be advertised as delivered phone/fleet access.

For efficiency, prioritize one immutable report per screen, shared/coalesced refreshes, bounded SQLite samples and batched queries. Bloomy's scheduled earnings interval is 600 seconds; the public competitor collector documents 20 seconds. Evaluate adaptive foreground/post-work refreshes with cache/rate-limit handling, rather than adding card-level polling. Profile CPU, memory, wakeups and query latency under matched Release conditions before claiming savings.

Fresh GitHub metadata still reports public main `724ce679e407eba0806cd03e94f303c4fb728468`; its architecture bytes match the retained research copy (SHA-256 `bfeeb61267e766d29a815836e124bf67e986a954a17d17f7ff2ecbce81a2ec53`). Four retained screenshots were re-inspected for hierarchy; these remain published captures, not live interaction proof. This research performed no provider commands or production app changes.

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

1. **Finish the financial attribution prerequisite.** Exact account/provider/model credit capture and session-safe charts now exist. The next critical boundary is proving which historical provider identities belong to this Mac; retention and legacy-history disclosure also remain open. A current connection ID, matching model name or single provider on the account is insufficient. The committed local-report capability withholds unsupported local economics; it is not a completed production resolver. Keep account credits available, but do not use them as local profit or match them to this Mac's electricity without proof. Whole-Mac GPU and power measurements must retain their scope.

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

This update is documentation only. Existing implementation work and production state were preserved. The financial boundary is committed; concurrent readiness work is not qualified for delivery by this report. This assessment does not establish competitor performance, final native visual qualification or release readiness.
