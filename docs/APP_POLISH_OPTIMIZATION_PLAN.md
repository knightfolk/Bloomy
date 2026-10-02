# Bloomy native polish and efficiency

The ongoing goal is a consistent, polished native Mac app with minimal background cost. A verified release checkpoint does not establish that every screen or state has completed review.

## Optimization checkpoint

Changes prepared for 1.9.15:

- Token-rate averages refresh on new successful measurements, day changes, or retries, instead of on every accepted source tick.
- Model cards share catalog grouping, telemetry lookup, peer calibration, and grading. Only demand age text keeps a visible one-second clock.
- Popup fan subscribers share one polling task. Static provider options refresh every five minutes in the background, with failed reads retried and explicit settings/manual refreshes kept fresh.
- Closed popup clocks, fan subscriptions, and hidden metrics reads/analysis stop. Cancelling obsolete metrics reads is distinct from a storage failure.
- Electricity history appends individual intervals to SQLite. The original JSON is retained as a migration backup; corruption and write errors remain visible, and restart/write gaps cannot become fabricated measurements.
- Performance-history indices match chronological ordering. Retention avoids walking the entire capped history when it is below the cap.
- Aggregate Metrics display reads are coalesced to 30 seconds while visible; reopening, period changes and manual Refresh are immediate. Recording of switches and request-counter changes stays immediate. Continuous visit analysis releases duplicate array ownership before appending.
- Metrics analysis follows successful read generations and their window endpoints. Explicit Refresh reanalyzes changed middle rows even when the count/newest ID are unchanged; the minute freshness clock updates labels without repeating analysis. Component timings and installed-app observation are in `docs/METRICS_REFRESH_OPTIMIZATION_20261002.md`.
- Settings, menu shortcuts, and contextual settings links share the existing dashboard window. Native application menus retain Edit/Window responder behavior.
- Native View and Help menus provide full-screen responder behavior and open the existing Support settings page.
- Model capacity display can read saved limits independently of live CLI inventory. This is read-only evidence and cannot authorize configuration or provider actions.
- Chat and Nudge startup presence checks request Keychain metadata in the background. Pending, missing, and unavailable status remain distinct; repeated UI checks do not query or decrypt a key.
- Observed uptime keeps cached interval totals and clips the rolling window with binary searches. Every observation still persists; reopening, older timestamps and external writes rebuild the aggregate. Unknown gaps and the ten-second carry limit remain unchanged.
- Legacy log parsing scans backward to the requested matching-event limit and reuses one date parser per read. The resulting events retain their original file order.
- Model Manager requires fresh runtime evidence for Active, Loaded and Unloaded labels. Missing evidence shows an unknown state; freshness deadlines update visible cards without repeating display polling or rebuilding grades.
- New Chat route descriptions wrap fully. Companion availability and Support report copy use plain language, with precise exclusions and the existing review-before-save gate retained.
- Model Manager cards keep display-name/ID order when serving or residency changes; badges still show the latest state. Enabled/Available sections and downloaded-first Available ordering remain.
- The dashboard sidebar uses native list selection for keyboard navigation. Settings keeps its independently saved page, and the concise Companion sidebar title retains the full hover/accessibility name.
- Explicit dashboard routes reopen their selected sidebar group. Native popup review covers Auto plan save/readback, Nudge setup, Cooling refresh, disclosures, navigation and clean fixture shutdown. A fresh native focus trace verifies the Overview Tab-to-sidebar/Down-to-Activity path; broader keyboard, VoiceOver and motion checks remain. Exact evidence and the correction to the earlier partial Tab test are in `docs/NATIVE_NAVIGATION_POPUP_REVIEW_20261002.md`.
- Custom model-section disclosures and the dashboard GPU ring honor the system Reduce Motion preference. Controlled native motion proof remains separate from source and build verification.
- Darkbloom 0.9.17 `waiting_inventory` is recognized in local metrics and presented as a model-inventory refresh state.

## Evidence and limits

Baseline: signed 1.9.14/build 139 on the same Mac. Thirty-second process CPU windows measured 13.27% of one core with Metrics visible and 11.03% with the dashboard minimized; median RSS was 284.5 MiB and 304.1 MiB respectively. These are short observations under live provider traffic, not battery-life estimates or a universal idle baseline.

Synthetic SQLite tests with 100,000 performance rows reduced the empty overflow check from an 8.50 ms median to a 0.009 ms count check. Query plans no longer require temporary chronological sorts.

A synthetic 60,000-interval energy history measured a 117.78 ms median full JSON rewrite versus a 0.197 ms median interval append. This compares storage operations, not total app CPU. Migration validates the complete retained history once. The public interval snapshot can still require an array copy on the next append.

Live after-build measurements and the complete native verification result belong in the release evidence. Do not infer them from synthetic benchmarks.

A release-mode 100,000-sample visit benchmark measured continuous idle analysis at 3.884 s before / 0.286 s after and continuous active analysis at 5.379 s before / 0.258 s after. Frequent switches and a gap remained about 0.30 s. Existing attribution, clipping and gap tests passed. This isolates visit analysis, rather than total Metrics refresh time.

The October 2 uptime benchmark used real SQLite storage with synthetic persisted observations. At 106,000 rows, median chronological record time fell from 18.427 ms to 0.019 ms in the same debug configuration. The first aggregate load remains about 15.5 ms; the cache retains approximately 3.2 MiB of entries plus array capacity. Randomized parity, rollback, external writes and bounded-cache tests preserve the original interval semantics. This measures one storage operation, not whole-app CPU or battery use.

A release-optimized parser benchmark with a synthetic 129,789-byte warning-heavy log tail and a 100-event limit measured 127.07 ms before / 5.34 ms after. Both selected the same events. Ordinary quieter logs may show a smaller benefit. Detailed evidence and limitations are in `docs/BACKGROUND_HISTORY_OPTIMIZATION_20261002.md`.

## Remaining optimization review

- Profile the updated app with Metrics visible and minimized under comparable provider activity; inspect hot stacks if substantial work remains.
- Assess incremental metrics reads and analysis for large 30-day histories. Current reads retain all models and uncertainty boundaries; optimization must preserve out-of-order observations, retention, gaps, and switch attribution.
- Review remaining recurring tasks, subprocesses, telemetry publication, system-sensor reads, and database growth. Monitoring, alerts, history, and automatic actions must continue when windows are closed.
- Use Instruments for sustained energy/allocation evidence where short process measurements leave uncertainty. Keep whole-Mac/provider usage separate from Bloomy's own process cost.

## Native screen review

Review the popup, Overview, Activity (Earnings and Metrics), Opportunity, Models, Hosting, Chat, Action History, Health & Logs, and every Settings page. The iPhone Companion page is a setup surface; it must not imply a shipped companion capability that is absent.

For each route check light/dark appearance, narrow/wide windows, keyboard focus and shortcuts, accessibility names, Reduce Motion, tooltip usefulness, consistent card/pill sizing, missing/stale/offline states, retained unsaved drafts, and normal-speed updates without flashing or layout shifts. Inspect actual rendered screens; builds and fixtures alone are insufficient to claim complete visual polish.

The provider and recovery watcher are deliberately stopped while Kevin uses the Mac for other work. Kevin authorizes a temporary provider start only if needed for a test; stop it again afterward. Use isolated fixtures for visual states that do not require a real provider, and do not swap or nudge merely to produce visual evidence.

The current production catalog fails at the external Sol cache boundary. A scoped production removable-drive permission reset remains pending human approval. Do not reset privacy permissions or grant Keychain access as an implicit part of a launch or release test. Release publication is held until required native behavior is verified.
