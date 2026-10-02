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
- Settings, menu shortcuts, and contextual settings links share the existing dashboard window. Native application menus retain Edit/Window responder behavior.
- Darkbloom 0.9.17 `waiting_inventory` is recognized in local metrics and presented as a model-inventory refresh state.

## Evidence and limits

Baseline: signed 1.9.14/build 139 on the same Mac. Thirty-second process CPU windows measured 13.27% of one core with Metrics visible and 11.03% with the dashboard minimized; median RSS was 284.5 MiB and 304.1 MiB respectively. These are short observations under live provider traffic, not battery-life estimates or a universal idle baseline.

Synthetic SQLite tests with 100,000 performance rows reduced the empty overflow check from an 8.50 ms median to a 0.009 ms count check. Query plans no longer require temporary chronological sorts.

A synthetic 60,000-interval energy history measured a 117.78 ms median full JSON rewrite versus a 0.197 ms median interval append. This compares storage operations, not total app CPU. Migration validates the complete retained history once. The public interval snapshot can still require an array copy on the next append.

Live after-build measurements and the complete native verification result belong in the release evidence. Do not infer them from synthetic benchmarks.

## Remaining optimization review

- Profile the updated app with Metrics visible and minimized under comparable provider activity; inspect hot stacks if substantial work remains.
- Assess incremental metrics reads and analysis for large 30-day histories. Current reads retain all models and uncertainty boundaries; optimization must preserve out-of-order observations, retention, gaps, and switch attribution.
- Review remaining recurring tasks, subprocesses, telemetry publication, system-sensor reads, and database growth. Monitoring, alerts, history, and automatic actions must continue when windows are closed.
- Use Instruments for sustained energy/allocation evidence where short process measurements leave uncertainty. Keep whole-Mac/provider usage separate from Bloomy's own process cost.

## Native screen review

Review the popup, Overview, Activity (Earnings and Metrics), Opportunity, Models, Hosting, Chat, Action History, Health & Logs, and every Settings page. The iPhone Companion page is a setup surface; it must not imply a shipped companion capability that is absent.

For each route check light/dark appearance, narrow/wide windows, keyboard focus and shortcuts, accessibility names, Reduce Motion, tooltip usefulness, consistent card/pill sizing, missing/stale/offline states, retained unsaved drafts, and normal-speed updates without flashing or layout shifts. Inspect actual rendered screens; builds and fixtures alone are insufficient to claim complete visual polish.

Provider state is preserved during app verification. Never start/stop/swap/nudge the real provider merely to produce visual evidence; use isolated fixtures for those states.
