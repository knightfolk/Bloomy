# Bloomy and BloomGauge: product and stack review

## Current decision brief — October 7

The fresh review is anchored to Bloomy `b2251fe` plus explicitly unfinished
working-tree financial UI changes. BloomGauge's public main remains
`724ce679e407eba0806cd03e94f303c4fb728468`, confirmed through GitHub's API.
Its current homepage, feature catalog, setup guide, release history and pinned
architecture/README were rechecked. Four retained published screenshots were
visually inspected: demand, day replay, switch rules and readiness. A fresh
asset-byte check received HTTP 403, so those screenshots remain retained vendor
captures, not a newly exercised installed build. No app installation, model
change, provider command or comparative performance test was performed.

**Recommendation:** keep Bloomy's native stack and strengthen the connection
between evidence, decisions and graphics. BloomGauge presents a more complete
earning-management journey. Bloomy has useful additional local controls, but
feature count alone does not establish a better experience or higher earnings.

| User question | What BloomGauge makes clear | Bloomy's next useful improvement |
| --- | --- | --- |
| Is this Mac ready to earn? | A readiness chain with one next action | One compact readiness strip shared by popup, Overview and Health; evidence age and unknown states included |
| Why did today earn this amount? | A selected day's model timeline and earning breakdown | Join existing model visits, accepted-work observations, credits and actions in Activity; keep account money separate from local work |
| Was the switch worthwhile? | Entry/return thresholds, round-trip cost and modeled replay | Show measured load time, time to first organic work, no-work residence and estimated payback next to the switch reason |
| Which model has sustained demand? | A common ruler with current/usual markers and history | One demand strip and sparkline per model, consistent units, sample age and visible gaps |
| How do I get started? | Documented graphical install, browser sign-in and resumable progress | A resumable first-run flow using verified official installation and authentication mechanisms |
| Can I check another Mac? | Documented private phone access and a fleet view | Finish existing Companion packaging and physical-device qualification before claiming delivery parity |

Sources: [features](https://bloomgauge.io/features),
[setup](https://bloomgauge.io/help/how-to-set-up-darkbloom-mac),
[switch presentation](https://bloomgauge.io/media/features/switch-rules.jpg).
Competitor capabilities are documented offerings, not independently verified
runtime or income results.

### Concrete changes to our stack

1. **Finish the shared financial reporting path.** The committed ledger now
   preserves account scope, provider IDs, exact amounts and corrections;
   authenticated projections are present on main. The working-tree Activity
   and Overview integration consumes one report, but is still unfinished and
   its latest focused run reports three issues. Do not count that integration
   as released or fully verified. A provider-ID filter still needs a verified
   local-machine mapping before its credits can calibrate this Mac's profits.
2. **Make freshness adaptive through one scheduler.** The source currently
   schedules earnings refreshes every 600 seconds: six scheduled cycles per
   hour, excluding manual refreshes and requests within a cycle. Evaluate
   30–60-second foreground/post-completion refreshes with coalescing, rate-limit
   handling and backoff, then slow down when hidden or idle. These are proposed
   values requiring measurement; a one-second animation is not fresher money.
3. **Build one immutable day report.** Join existing histories by explicit
   scope and time, carrying coverage and source timestamps. Render aligned
   model, work, action and credit tracks from it. Credit time is not request
   start time, and nearby switches do not prove missing rewards were caused by
   switching. Preserve exact financial records; bound/downsample sensor data.
4. **Improve the economics without adding another controller.** Our existing
   policy already has gain, confirmation, hold, return and attempt-limit gates.
   Audit its positive-incumbent prerequisite and raw-request/gross-rate filters:
   they can exclude a better net alternative. First test those cases with
   fixtures, then qualify any policy change. Add measured round-trip costs and
   outcome review; keep simulations distinct from earned credits. Continue
   routing actions through `ProviderControlStore` and respecting Autopilot.
5. **Add bounded historical demand through the existing adapter.** The official
   endpoint is public and cached, but at least an hour behind current time and
   limited to publishable cohorts. It cannot replace live pressure, establish
   zero demand from an empty response, or predict local income by itself.
   [Official contract](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/api-contracts.md#model-demand-response).

Our SwiftUI/AppKit, native Charts and SQLite modules fit these changes.
BloomGauge's Swift/WKWebView, bundled Python and React stack supports shared
desktop/phone rendering; it is not evidence that a rewrite would improve
Bloomy. Compare CPU, memory, wakeups, launch latency and database growth under
matched release-build workloads before making an efficiency claim.
[Pinned architecture](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/docs/ARCHITECTURE.md).

The UI direction should stay original and native: stable icon-first controls,
one primary earnings graphic, compact readiness, comparable demand strips, and
details revealed through selection. The first implementation priority is
financial integration and machine attribution, followed by readiness/day
replay, demand/switch economics, onboarding and Companion delivery. This brief
is research only; it does not change runtime behavior or complete those items.

## Earlier review and supporting analysis

Initially reviewed October 6, 2026 at Bloomy `789b58e`. Refreshed October 7 at
`f76a89af7f548459fe9a3d0df8c75fd2a40e9e40` on `main`; unfinished working-tree
financial integration is explicitly excluded from completed-feature claims.

Bloomy has a strong native Mac foundation and substantial controls already implemented. BloomGauge's most useful advantage is how it explains the relationship between readiness, model choices and earnings. It also documents a more complete first-run experience and usable remote access. We should improve those areas rather than assume that either product is better in every respect.

This review uses vendor documentation, published screenshots, its public repository, Bloomy's source and release records, and the October 6 live read-only Darkbloom API check. It does **not** establish comparative CPU use, battery life, reliability or earnings. BloomGauge was not installed or exercised. The public repository is not proof of the current distributed application's complete implementation. The site also has inconsistent version labels across its homepage, guide and changelog, so the comparison concerns documented capabilities, not a verified installed competitor version. The October 7 follow-up inspects five screenshot assets and refreshes the source audit. [Public repository](https://github.com/cookder/bloomgauge), [changelog](https://bloomgauge.io/changelog).

Bloomy's actual SwiftUI Overview, Activity/Earnings and Opportunity were inspected in an optimized, isolated fixture during this review. The source manifest matches 119 files; values are synthetic. This confirms that our current main branch already has native summary cards, earnings composition graphics and graphical demand cards, without implying those latest layouts are installed or released. See [native evidence](HOSTING_CLI_EVIDENCE_REVIEW_20261006.md).

## Built, delivered and proposed

At the original October 6 release check, GitHub's latest published Bloomy release was **v1.9.19**, published October 4. Our main branch also contains subsequent popup, Earnings and Metrics polish. Those later changes are source work, not delivered improvements in that release. Native review fixtures demonstrate bounded behavior; they do not qualify every production route. The broader native completion matrix remains partial. [Bloomy v1.9.19](https://github.com/knightfolk/Bloomy/releases/tag/v1.9.19), [completion matrix](NATIVE_COMPLETION_MATRIX_20261002.md).

The underlying profit policy, model-visit tracking, Chat, Hosting and action history are already present in the released source. The iPhone Companion is different: its protocol and host components are development work, with packaging, operational wiring and physical-device proof still required. We should not advertise it as delivered remote access. [Companion operations](COMPANION_OPERATIONS.md).

The recommendations below are proposals, not features implemented by this review.

## Product comparison

| Area | Bloomy's current position | BloomGauge's documented offering | Practical improvement |
| --- | --- | --- | --- |
| Mac interface | SwiftUI/AppKit, native Charts, menu-bar controls, dashboard and settings; ongoing density and unknown-state polish | Dashboard with a prominent earnings pace display and connected model/day explanations | Keep native controls; make each overview graphic answer a specific question |
| Initial setup | Official CLI installation/login precede app use; in-app configuration guides exist | Guided installation, authentication, model download and readiness progress | Add a resumable first-run readiness flow around official mechanisms |
| Earnings | Base/inference ledger, hourly/model breakdowns, jobs and electricity estimates with coverage qualifications | Calendar/day replay ties daily earnings to readiness and model occupancy | Join existing evidence into a daily timeline instead of adding more separate text cards |
| Switching | Conservative gain, hold, cooldown, data-quality and memory gates; respects native Autopilot ownership | Home-model selection, qualified cohort fallback and explicit round-trip cost/replay explanations | Show why our policy holds, and measure the full cost of a switch |
| No work after a switch | Model visits already classify work, no observed work and unknown intervals | Paid work and ready-time explanations | Expose our existing tracking directly beside switch decisions |
| Diagnostics | Health, Logs, action history, hosting/connection status, nudge controls and GPU protection | Guardian explains the earning-readiness chain and bounded recovery | Add one evidence-based “Why no work?” surface; avoid a competing recovery controller |
| Additional controls | Local and explicit network Chat, Hosting, cooling, GPU protection, guarded model uninstall | Different emphasis on earnings, fleet visibility and provider management | Preserve these useful controls while consolidating navigation |
| Phone/fleet | Companion is not delivered | Documented Tailscale-based phone/browser access and multi-Mac views | Finish and qualify our secure companion before claiming parity |

Competitor sources: [setup](https://bloomgauge.io/help/how-to-set-up-darkbloom-mac), [guide](https://bloomgauge.io/guide), [switch rules](https://bloomgauge.io/help/bloomgauge-switch-rules), [Guardian](https://bloomgauge.io/help/bloomgauge-guardian), [feature catalog](https://bloomgauge.io/features). These are vendor descriptions, not independently measured results.

## What the screenshots teach us

The [dashboard capture](https://bloomgauge.io/images/hero-dashboard-1400.webp) establishes a useful hierarchy: comparable summary cards, a prominent pace graphic, then model comparison. The [day replay](https://bloomgauge.io/media/features/day-replay.jpg) is especially relevant to Kevin's concerns: an amount, a short explanation, a model timeline, then supporting details. We can use that information order without copying its artwork or layout.

The [model-demand capture](https://bloomgauge.io/media/features/model-demand.jpg) puts current and usual demand on a shared scale. The [switch-rule capture](https://bloomgauge.io/media/features/switch-rules.jpg) makes entry/return thresholds and holds visible. Both are better ways to explain decisions than adding another paragraph to every model card. They also contain considerable explanatory text, so adopting the entire presentation would conflict with our dense, icon-led direction.

For Bloomy, use consistent model colors in the cards, timeline and earnings composition. Keep controls stable as values arrive. Distinguish an observed zero from missing evidence; show uncertainty through gaps and neutral styling. A compact headline should describe the current state, while detailed reasoning belongs in a disclosure or selected-event panel. Avoid animated money counters and frequent layout changes.

BloomGauge's changelog documents a smoothed pace default intended to handle earnings arriving on job completion. That is a useful presentation idea, but pace, actual token throughput and paid ledger credits must remain separate measurements. A quieter trend must not hide an active request or imply that an unpaid request has earned money. [Changelog](https://bloomgauge.io/changelog).

## Stack assessment

Our stack is Swift 6, SwiftUI/AppKit, native Charts, SQLite-backed telemetry/history and Sparkle. BloomGauge's public architecture uses a Swift wrapper with WKWebView, React/Vite/TypeScript, a Python collector, SQLite and Sparkle. Its phone view reuses the web interface through Tailscale. That provides a practical shared desktop/phone UI; it does not establish lower resource consumption or better Mac integration. The repository is source available and explicitly omits newer private components. Independent implementation is the appropriate path. [Public repository](https://github.com/cookder/bloomgauge), [architecture](https://github.com/cookder/bloomgauge/blob/main/docs/ARCHITECTURE.md).

There is no compelling reason to replace our native UI with a browser or add a Python collector. We should improve the interfaces between acquisition, durable evidence, decisions and presentation:

1. **Acquisition:** bounded adapters, source timestamps, stable model/account identities, capability checks and backoff.
2. **Evidence:** reconcile ledger records, retain meaningful events, downsample continuous measurements, preserve missing intervals.
3. **Decisions:** record the observed inputs, automation owner, hold reason and expected benefit before an action.
4. **Presentation:** derive compact summaries and timelines from those records; avoid repeated full-history queries while hidden.

Our inert Metrics profiling already shows visibility-dependent resource behavior, but it is not production or comparative evidence. The next useful performance qualification is a repeatable installed-app workload: idle/busy provider, popup open/closed, dashboard visible/minimized, bounded historical data, plus CPU, memory and energy measurements. [Current Metrics resource review](METRICS_CURRENT_RESOURCE_PHASE_REVIEW_20261004.md).

## Recommended order

### 1. Establish trustworthy money and attribution

The October 6 audit identified a maximum-ID ingestion assumption as a test lead, not a reproduced missing-reward bug. Since then, committed changes `56ab21c`, `f267c7d` and `f76a89a` have added exact account-scoped credits and corrections, bounded atomic reports/reconciliation, and authenticated session generations. Those foundations are verified in their respective checkpoint reviews. Established UI reads still use the older financial interfaces; session-aware publication, retained-chart clearing, local-provider mapping and retention remain unfinished. Finish that integration before adding more forecasts. See [ledger capture](ACCOUNT_CREDIT_LEDGER_CAPTURE_REVIEW_20261007.md), [scoped reports](SCOPED_ACCOUNT_CREDIT_REPORT_REVIEW_20261007.md) and [authentication](AUTHENTICATED_FINANCIAL_SESSION_REVIEW_20261007.md).

Account earnings can cover multiple providers. Keep local model visits and throughput separate from account-wide money unless attribution is established. A fleet view must not sum the same account balance once per Mac. [Darkbloom API contracts](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/api-contracts.md).

### 2. Add a compact explanation of the current state

Show the loaded model, automation owner and mode, current accepted work, last organic work, last nudge outcome and one actionable readiness reason. “Autopilot enrolled in shadow mode” must remain visibly different from active control. A long-running job, quiet network, unknown connection and local readiness failure should lead to different explanations.

Use a structured chain such as connection → authorization → loaded readiness → accepted work → completed work → credit evidence. Each step needs a timestamp and an unknown state. Recovery should respect manual stops and defer to the official provider watchdog and native Autopilot. The competitor's diagnostic framing is useful; adding another independent restart loop is not. [Guardian](https://bloomgauge.io/help/bloomgauge-guardian), [official CLI reference](https://github.com/Layr-Labs/d-inference/blob/master/docs/provider/cli-reference.md).

### 3. Build “what happened after the switch?” from existing data

Combine `ModelVisitHistory`, actions, request observations and earnings intervals in a day view. Highlight visits with no observed organic work, duration until first work, load time, failure/unknown gaps and the next model change. Separate a synthetic nudge from real network work.

Overlay five-minute reward windows for investigation, but do not label every uncredited window as a loss caused by switching. Darkbloom's current pricing documentation uses a 300-second settlement period and qualifying availability/readiness conditions; it does not promise an unconditional credit every five minutes. Account-wide credits also complicate per-Mac correlation. Temporal proximity is evidence to investigate, not proof of causation. [Pricing model](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/pricing-model.md).

### 4. Explain and improve the economics of switching

Our policy already requires a meaningful increase: at least 30% and an estimated $0.05 next-hour net gain, with a 10-minute confirmation, 60-minute hold, 180-minute return cooldown and maximum three attempts per rolling day. It also requires substantial observations, memory headroom and safe provider state. These are implemented defaults, not missing basics. See `ProfitSwitchPolicy.swift` and `ProfitSwitchStore.swift`.

Improve the cost estimate beyond the existing five-minute loading floor: measure loading, waiting for first organic work, return loading, foregone qualified rewards and failed transitions. Show the payback estimate only when the expected gain is positive and evidence is sufficient. Distinguish estimated from observed values. Our recommendation journal can reevaluate stored inputs; it is not a counterfactual earnings simulator. BloomGauge's documented round-trip cost/replay approach is useful inspiration, but similar controls must not imply guaranteed better earnings. [Switch rules](https://bloomgauge.io/help/bloomgauge-switch-rules).

### 5. Use the historical demand API already available

The official contract documents `/v1/network/model-demand` with 24-hour, seven-day and 30-day windows. A live unauthenticated seven-day GET returned HTTP 200 on October 6, with nine model records, time series, coverage and update timestamps. This establishes endpoint availability, not complete seven-day coverage or suitability for earnings prediction. The sanitized schema check is retained in `.build/bloomgauge-research-20261006/public-api-schema-check.json`.

Add bounded, cached demand history through our existing telemetry adapter. Preserve coverage gaps and canonical model IDs; use the documented cache interval rather than polling every second. No new API key is necessary for that public read. Network demand is useful context, but cannot by itself predict what this Mac will earn. [API contracts](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/api-contracts.md).

### 6. Complete onboarding, then remote delivery

Build a resumable setup/readiness checklist around verified official downloads and the official browser authentication flow. Preserve existing provider selections, distinguish CLI installation from reward qualification, and avoid asking the user to paste one credential into several unrelated-looking screens. BloomGauge's setup documentation shows why this matters. [Guided setup](https://bloomgauge.io/help/how-to-set-up-darkbloom-mac).

For remote access, finish our native helper's packaging, registration and operational integration, then qualify read-only fleet views on a physical iPhone before adding remote mutations. Keep certificate pins, revocation and bounded operation journals. Do not expose a dashboard to the public internet to close the feature gap quickly. [Companion operations](COMPANION_OPERATIONS.md).

## Delivery and messaging

Ship the already-reviewed visual improvements through our normal signing/updater gates before advertising them. Update the public product description to explain Autopilot ownership, conservative automation, no-work tracking, host responsiveness, local/network Chat and guarded uninstall. A competitor-authored comparison still uses our former product name and describes a narrower manual-control tool; that page is not a current inventory of Bloomy. No outreach or external edits were performed. [Vendor comparison, dated September 29](https://bloomgauge.io/help/darkbloom-apps-for-mac).

The next implementation slice should finish scoped financial presentation, then add a compact readiness explanation and a switch-outcome timeline. Those directly address Kevin's missing-reward and model-switch questions, reuse our existing architecture, and provide useful evidence before more automation is added.

## October 7 deeper source and interface review

The current public BloomGauge repository tree is
`724ce679e407eba0806cd03e94f303c4fb728468`. Its retained source extracts and five
published screenshots have a checksum manifest in
`.build/bloomgauge-research-20261007/manifest.json`. The repository tree identity
was rechecked against GitHub today. The homepage now advertises beta 54 while
the changelog's latest entry is beta 53 and the guide shows beta 52; published
documentation is not a verified installed version. Browser control was
unavailable in this session. Screenshot inspection and public source review do
not establish interactive behavior, comparative resource use or earnings.
[Homepage](https://bloomgauge.io/), [changelog](https://bloomgauge.io/changelog),
[public source](https://github.com/cookder/bloomgauge).

### The most valuable interface ideas

The screenshots put the user's question ahead of the instrumentation. Day replay
starts with earnings, a short explanation and a colored residence timeline;
the readiness screen highlights the first failing condition; demand bars show
current pressure against a reference. These are useful information patterns.
Their full screens also contain substantial small explanatory text and nested
tabs, so they should not become our visual template.
[Day replay](https://bloomgauge.io/media/features/day-replay.jpg),
[readiness](https://bloomgauge.io/media/features/why-not-earning.jpg),
[demand](https://bloomgauge.io/media/features/model-demand.jpg).

For Bloomy, prioritize three native surfaces: a compact state summary above the
existing command bar, an Activity day timeline, and one comparable demand strip
per model. Reuse short aliases and consistent model colors. Put detailed
reasoning in a selection inspector or disclosure; retain neutral unknown gaps,
source ages and a stable layout. A money dial adds less value than a chart that
explains when work, rewards and switches occurred. A visual reference baseline
must have enough actual history; otherwise show insufficient evidence.

### Account money and this Mac's money need separate paths

BloomGauge's public `native/live_earnings.py:575–740` contains a concrete pattern
worth independently implementing: it associates account, device, session and
provider connections, then joins inference credits to those mappings. This is
stronger than assuming a model name identifies the earning Mac. Its code also
withholds a current-session rate without fresh matched evidence and enough
covered time. This is source evidence for that module, not proof of all vendor
screens. [Pinned implementation](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/live_earnings.py#L575).

Bloomy's new ledger already stores provider IDs, but a provider filter alone
does not prove local-machine identity. Persist a verified connection-to-machine
mapping across restarts before calibrating local model profitability. Keep
account-wide balance, local inferred work, credited inference and base rewards
separate. A fleet total must deduplicate account balances. Count credit records
as credits unless an actual request identifier establishes completed jobs.

### Timeliness is a real tradeoff in our stack

Our `MonitorStore.earningsPollingInterval` is currently 600 seconds. That is
quiet, but cannot support a frequently updated confirmed-credit experience.
The public competitor collector polls earnings every 20 seconds and its local
UI can update each second. This describes cadence, not greater accuracy or
lower resource consumption. [Architecture](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/docs/ARCHITECTURE.md).

Evaluate a single shared, workload-aware earnings refresh: for example 30–60
seconds while the earnings view is visible or accepted work has just completed,
with slower hidden/idle polling, request coalescing, cancellation and backoff.
Treat those values as proposed settings until the current API's cache and rate
limits are qualified. Do not add independent pollers for cards or simulate
credits between fetches. Measure requests/hour and idle CPU before choosing.

### Historical demand is not current pressure

The current official historical model-demand contract is more constrained than
a generic live chart: its window ends at the preceding UTC hour, includes only
publishable hourly cohorts, and null intervals mean unavailable data. A
successful empty response does not mean zero network traffic. Keep that chart
separate from fresh active/queued pressure. An equivalent-time baseline needs
its own suitable observations; this endpoint alone does not provide a live
requests-per-warm-Mac series. Cache bounded responses and expose the coverage
and observation time. [Official contract](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/api-contracts.md#model-demand-response).

### Recovery should respond to evidence, not just unpaid minutes

BloomGauge's recent releases specifically address long requests that looked
like stalls and quiet models whose peers also had no work. That is useful
regression-test inspiration for our 15-minute nudge watcher: accepted/in-flight
work, stale observations, a quiet network, a deliberate stop and an actual
readiness failure must produce different outcomes. A synthetic probe must never
reset the organic-work baseline or prove routing repaired. Keep every action
within our existing serialized provider-control path and preserve Autopilot's
ownership. [Recent fixes](https://bloomgauge.io/changelog),
[recovery policy](https://bloomgauge.io/help/bloomgauge-guardian).

Five-minute settlements are conditional on authorization, uptime, hardware and
health/readiness gates. A day replay should mark observed qualification and
missing evidence; it must not promise that every empty five-minute slot is a
lost reward caused by a switch. [Official reward rules](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/pricing-model.md#base-rewards).

### Stack changes with the best return

Keep Swift 6, SwiftUI/AppKit, native Charts and SQLite. Add an immutable reporting
layer that joins existing credits, model visits, action outcomes, readiness and
energy evidence by explicit scope and timestamp. Views should consume one
bounded report rather than independently reading changing datasets. Keep pure
decision logic separate from the sole mutation owner. Retain exact money records;
downsample high-frequency sensor history under an explicit retention policy.
Use synthetic transition replays to check long jobs, failed switches,
authentication changes and interrupted reads without touching the provider.

For economics, add measured load-to-first-organic-work and return-load cost to
the existing gain/hold/cooldown policy, then show estimated payback and the
actual outcome together. Historical replay is a modeled scenario, not money
the user would certainly have earned. For remote delivery, finish the existing
Companion rather than add another local web server and controller; packaging,
live integration and physical-device proof still block a shipped fleet claim.

Recommended priority: scoped money/UI integration and machine attribution;
readiness and switch replay; bounded demand history and explicit switch
economics; resumable first-run setup; then Companion delivery. Measure the
installed app before claiming an efficiency advantage. This update is research
only and adds no competitor-inspired runtime behavior.
