# Bloomy versus BloomGauge — deeper product and stack review

Reviewed October 8, 2026, Phoenix time. Bloomy source: `5e2d98a`, with concurrent
review changes identified separately below. This is research, not a release or
authorization to change either running provider.

## Decision

Keep Bloomy's native Mac stack. Its useful distinction is a dense menu-bar
control surface with local model management, cooling, host-GPU protection and
explicit local/network Chat. BloomGauge's strongest published experience is
the connected earning journey: setup, readiness, model choice, daily results
and remote monitoring. More controls alone do not establish a better product.

The highest-value improvement is to connect Bloomy's existing evidence into
clear answers: **Am I ready? What happened today? Was that switch worthwhile?**
Historical financial attribution is a prerequisite for trustworthy answers
about this Mac's profit. A UI rewrite or another model controller is unnecessary.

## Evidence and delivery boundaries

- Freshly read the vendor's homepage, feature catalog, guide, October 7
  changelog, Guardian and switch-rule documentation, privacy notice and public
  architecture. Current advertised release is **1.36.74 beta 55**. Its public
  main is `724ce679e407eba0806cd03e94f303c4fb728468`; the README identifies the
  public core as **1.36.63**, with newer setup/Guardian implementation private.
  [Release history](https://bloomgauge.io/changelog),
  [public-source boundary](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/README.md#L5-L15).
- Fresh browser inspection loaded five published screenshots: hourly earnings,
  demand, switch rules, day replay and readiness. This resolves the earlier
  research's browser/image-fetch limitation, but remains inspection of vendor
  captures, not operation of an installed competitor app.
- GitHub's current latest Bloomy release is **v1.9.19**, published October 4 UTC.
  Later committed polish and dirty review code must not be represented as
  features delivered in that release.
  [Published release](https://github.com/knightfolk/Bloomy/releases/tag/v1.9.19).
- Two bounded read-only source audits checked Bloomy's capabilities and the
  pinned public competitor core. No competitor software was installed or run;
  no model, provider configuration, credential, production app or remote
  publication was changed. No matched resource or income benchmark was performed.

## Product comparison

| Area | BloomGauge's documented offering | Bloomy's current source | Useful action |
| --- | --- | --- | --- |
| First run | Official-provider install, browser sign-in, download and progress; separate existing-provider/viewer paths | Narrow setup guides and provider controls; complete resumable onboarding absent | Detect existing installations first; resume each official setup step without replacing saved choices |
| Earnings | Pace display, hourly composition, selected-day replay | Exact correction-aware account credits and native charts; residence/work/action timeline exists separately | Join evidence by selected day, with explicit account versus this-Mac scope |
| Model demand | Common ruler, usual marker and historical context | Common current ruler committed; local 24-hour journal/sparklines under review | Finish current work; distinguish sampled local history from server aggregates |
| Switching | Entry/return rules, hold, cost and simulated comparison | Conservative gain/timing gates, idle checks and one command gate | Explain existing decisions and measure outcomes before expanding policy |
| Readiness/recovery | Diagnosis chain and bounded recovery | Shared readiness in Overview/Health; nudges, alerts, logs and controls | Connect the current diagnosis to its evidence and one relevant next action |
| Mac controls | Hardware and energy views | Fans, host-GPU protection, model download/delete/enable/preload, local/network Chat | Preserve these strengths and simplify their presentation |
| Phone/fleet | Private Tailscale dashboard and multi-Mac view advertised | Pairing, transport and native iOS foundations; helper/UI delivery unfinished | Treat Companion as a separate packaging and real-device milestone |

Vendor evidence: [feature catalog](https://bloomgauge.io/features),
[setup](https://bloomgauge.io/help/how-to-set-up-darkbloom-mac),
[Guardian](https://bloomgauge.io/help/bloomgauge-guardian),
[switch rules](https://bloomgauge.io/help/bloomgauge-switch-rules).
These are documented offerings, not independently measured outcomes.

Bloomy's capability anchors:
`AccountCreditLedger.swift`, `AuthenticatedEarningsClient.swift`,
`ProviderReadiness.swift`, `ModelVisitHistory.swift`, `PerformanceActivityHistory.swift`,
`ProviderControlStore.swift`, `ProfitSwitchPolicy.swift`, `HostGPUProtection.swift`,
`SupportPacketSnapshot.swift`, and `docs/COMPANION_OPERATIONS.md`.

## What to adapt from the interface

**One primary graphic per question.** The earnings capture places a pace gauge
beside hourly composition; the day replay starts with the result and then its
timeline. Bloomy's Overview should lead with confirmed earnings and a compact
composition chart. Live provider throughput and GPU activity belong alongside
it with their own units. Use aligned time axes rather than a single ambiguous
scale for dollars and tokens. Keep estimates subordinate to confirmed credits.
Their latest changelog also describes reducing tiles and moving detail out of
Overview. [October 7 changes](https://bloomgauge.io/changelog).

**Comparable model rows.** Their demand and rule captures use long rows on one
ruler, with a current marker and optional usual/threshold markers. That suits
our requested full-width cards. Keep the model name/state and controls stable,
use the same model identity colors across views, and reveal detailed reasoning
through selection. Their screens still contain substantial prose and small
legends; copying the whole layout would conflict with our dense, readable popup.
[Demand capture](https://bloomgauge.io/media/features/model-demand.jpg),
[rule capture](https://bloomgauge.io/media/features/switch-rules.jpg).

**A day that can be inspected.** Adapt the order of result, timeline and model
summary. Our timeline should include residence, loading, observed provider work,
actions and credit arrivals. An empty interval stays unknown unless covered by
valid observations. A credit arriving after a switch does not prove the work
was served after that switch. Selecting a no-work visit should reveal duration,
coverage, switch reason and any nudge attempt.
[Day-replay capture](https://bloomgauge.io/media/features/day-replay.jpg).

**Readiness with one next step.** Our shared readiness component already exists;
this is now a coherence and qualification task. Ready-but-quiet should remain a
normal state. Missing work or delayed credits alone should not diagnose a stall.
Show the blocker, evidence age and destination for the relevant control.
[Readiness capture](https://bloomgauge.io/media/features/why-not-earning.jpg).

## Stack findings and concrete improvements

### 1. Preserve the native architecture; strengthen shared reports

BloomGauge's public stack uses Swift/WKWebView, a bundled Python collector,
React/TypeScript, SQLite and Sparkle. Shared web rendering makes desktop/phone
reuse practical. Bloomy's SwiftUI/AppKit, Charts and Swift/SQLite modules already
fit the Mac product. Neither architecture establishes a CPU, memory, battery
or reliability winner. [Public architecture](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/docs/ARCHITECTURE.md).

Build immutable reports from acquisition, persistence and evidence, then let
popup, Overview and Activity render those reports. Coalesce reads at screen
level. Avoid a timer or journal query per card. Continue routing provider
mutations through `ProviderControlStore`; show whether manual control, native
Autopilot or Bloomy owns selection.

### 2. Finish local financial attribution before profit calibration

Bloomy's production `localProviderFinancialReport` currently defaults to nil
(`AuthenticatedEarningsClient.swift:97`). That correctly prevents unsupported
account-wide credits from becoming this Mac's profit inputs, but leaves a real
product gap.

The public competitor core hashes the daemon's attestation public key, requires
a unique public-roster match, and saves device/provider/session associations.
Its evidence uses covered warm minutes and a settlement delay. This offers a
concrete research direction, not proof that its legacy path works for every
current App Attest session.
[Identity path](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/optimizer.py#L185-L215),
[session report](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/live_earnings.py#L613-L740).

This only covers previously observed mappings: missing keys or ambiguous
matches revoke eligibility, and a changed key creates another device identity.
App Attest authorization does not replace that public-key requirement. Its
credit timestamps still do not establish underlying request execution times.

Design our own account-scoped resolver with timestamped connection mappings,
explicit coverage and invalidation on reconnect/account change. Unknown,
ambiguous and unsupported identity remain unavailable. Never assign old credits
using today's provider ID. Validate current official identities and contracts
before choosing the resolver; the public roster does not expose private App
Attest machine identity. [Official API contract](https://github.com/Layr-Labs/d-inference/blob/master/docs/reference/api-contracts.md).

### 3. Separate collection speed from animation speed

Bloomy's scheduled account refresh is currently 600 seconds
(`MonitorStore.swift:55`). The public competitor collector polls account
earnings at 20 seconds; its local UI refresh can be one second. These are
different operations. A moving gauge cannot make cached account data newer.
[Collector](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/collector.py#L587-L687).

Evaluate one adaptive financial scheduler: coalesced foreground/post-work
refreshes, source-cache awareness, Retry-After/backoff and slower hidden/quiet
cadence. Proposed 30–60-second foreground intervals require API/load testing.
Keep existing live provider sampling separate. Accept only source-backed
meter changes; honor Reduce Motion and preserve stale/idle/unavailable states.

### 4. Make switching costs and results visible

Our defaults already include ten-minute confirmation, sixty-minute residence,
three-hour return cooldown and five-minute loading allowance. The policy
requires a meaningful estimated gain and caps attempts. It also contains raw
request/gross-rate gates and a positive-incumbent prerequisite that deserve
fixtures before any policy revision (`ProfitSwitchPolicy.swift:210–229`).

The public competitor optimizer compares conservative rate bounds after load
downtime; target-specific observed loading times can replace its fallback.
[Public economic calculation](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/demand_optimizer.py#L482-L545).

Expose expected advantage, observed load reliability, estimated payback and
why a switch is held. Record load duration, time to first observed organic work,
no-work residence and subsequent attributable credits. A self-nudge must not
count as organic demand. Provider-global counters alone cannot prove that
distinction; ambiguous work stays unclassified until request provenance exists.
Estimated opportunity cost is not a cash charge;
simulated replay is not earned money. Verify reward timing before considering
reward-boundary scheduling; do not infer a reliable phase from wall-clock time.

### 5. Bound storage and qualify efficiency

The competitor core aggregates charts at query time, prunes raw samples after
90 days and retains important economic evidence separately. This is useful
separation, not proof of a strict whole-database bound.
[History](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/history.py#L49-L152),
[retention](https://github.com/cookder/bloomgauge/blob/724ce679e407eba0806cd03e94f303c4fb728468/native/retention.py#L1-L76).

Keep our bounded raw telemetry and exact correction-aware financial records.
Add durable hourly/day rollups if longer history is needed, preserving coverage
and provenance before pruning raw samples. Benchmark idle/busy, popup open/closed
and dashboard visible/hidden under matched Release conditions. Measure process
tree memory, CPU, wakeups, launch latency, query latency and database growth.
Do not claim performance superiority from framework choice or test count.

## Recommended sequence and proof

1. **Finish the current native review.** Full-width cards, passive live meters,
   local demand sparklines and 1/2/8/12/24-hour performance charts are dirty
   review work. Require layout, accessibility, source freshness, hidden-view
   resource and real-app inspection before counting them as delivered.
2. **Resolve financial ownership and join Activity.** Prove account changes,
   reconnects, missing identity, delayed/corrected credits, nudge exclusion and
   gaps. Deliver one inspectable selected-day report.
3. **Explain and calibrate the existing switch policy.** Start observe-only;
   qualify zero-profit incumbents, misleading raw request counts, failed loads
   and Autopilot ownership before changing automatic behavior.
4. **Complete resumable onboarding.** Existing users keep their setup; new
   users get verified official install/login/download/start steps with recovery
   from interruption. Do not enable unrelated automation implicitly.
5. **Deliver Companion separately.** Finish signed helper packaging, operational
   wiring and physical-device tests. Preserve pinned transport and explicit
   capabilities; do not advertise foundation code as available remote access.

During this research, the pre-existing serial Release test run was joined. It
completed with one popup layout expectation failure at
`MonitorPopoverLayoutTests.swift:567`; the new review must not be called fully
qualified. That failure and native review completion remain implementation
follow-through, separate from this comparison.

This review supersedes older current-state comparison claims. It does not
replace the broader polish plan or complete its native/release gates.
