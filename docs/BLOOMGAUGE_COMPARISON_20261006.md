# Bloomy and BloomGauge: product and stack review

Reviewed October 6, 2026. Bloomy source baseline: `789b58e` on `main`.

Bloomy has a strong native Mac foundation and substantial controls already implemented. BloomGauge's most useful advantage is how it explains the relationship between readiness, model choices and earnings. It also documents a more complete first-run experience and usable remote access. We should improve those areas rather than assume that either product is better in every respect.

This review uses the vendor's current documentation, four published screenshots, its public repository, Bloomy's source and release records, and a live read-only Darkbloom API check. It does **not** establish comparative CPU use, battery life, reliability or earnings. BloomGauge was not installed or exercised. Its public core is explicitly behind the current application; private features cannot be verified through that core. The site also has inconsistent version labels across its homepage, guide and changelog, so the comparison concerns documented capabilities on this date, not a verified installed competitor version. [Public repository](https://github.com/cookder/bloomgauge), [changelog](https://bloomgauge.io/changelog).

Bloomy's actual SwiftUI Overview, Activity/Earnings and Opportunity were inspected in an optimized, isolated fixture during this review. The source manifest matches 119 files; values are synthetic. This confirms that our current main branch already has native summary cards, earnings composition graphics and graphical demand cards, without implying those latest layouts are installed or released. See [native evidence](HOSTING_CLI_EVIDENCE_REVIEW_20261006.md).

## Built, delivered and proposed

GitHub's latest published Bloomy release is **v1.9.19**, published October 4. Our main branch also contains subsequent popup, Earnings and Metrics polish. Those later changes are source work, not delivered improvements in that release. Native review fixtures demonstrate bounded behavior; they do not qualify every production route. The broader native completion matrix remains partial. [Bloomy v1.9.19](https://github.com/knightfolk/Bloomy/releases/tag/v1.9.19), [completion matrix](NATIVE_COMPLETION_MATRIX_20261002.md).

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

Audit ledger reconciliation before adding more forecasts. `EarningsDatabase` normally ingests IDs above a saved watermark. Test late-arriving entries, corrections to older IDs, account changes and truncated pages explicitly. This is a source-derived test lead, **not a reproduced missing-reward bug**. Action history already has separate account/entry deduplication; reconcile the two paths rather than assuming they are interchangeable.

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

The first implementation slice should be the ledger audit plus a compact readiness explanation and a switch-outcome timeline. Those directly address Kevin's missing-reward and model-switch questions, reuse our existing architecture, and provide useful evidence before more automation is added.
