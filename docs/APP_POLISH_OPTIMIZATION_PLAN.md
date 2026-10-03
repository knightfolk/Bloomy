# Bloomy native polish and efficiency

The ongoing goal is a consistent, polished native Mac app with minimal background cost. A verified release checkpoint does not establish that every screen or state has completed review.

The [native completion matrix](NATIVE_COMPLETION_MATRIX_20261002.md) indexes all
22 surfaces, distinguishing bounded coverage and each remaining proof gap.

## Current review priorities

Kevin questioned the emphasis on keyboard controls on October 2. Keep ordinary
native Tab/Space/Escape behavior and accessible control names, but prioritize
visible layout, truthful state, reliable actions and measured resource use.
Exhaustive key-path audits and custom shortcuts are lower priority. Fix concrete
keyboard bugs that affect ordinary use; an unverified optional path is not itself
a product failure or a reason to add a new control system. Existing evidence and
remaining proof gaps stay recorded.

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
- Dashboard Chat keeps its unsent message in memory for the current conversation while its page is removed. Provider and fan policy editors retain nonsecret drafts while only the selected settings page remains mounted; credentials and transient confirmations remain local to their editors.
- Logs retain the selected event while its immutable identity remains visible after arrivals or filtering. Identical duplicates remain individually selectable, without claiming an occurrence identity the source does not provide.
- Freshness heartbeat ticks compare source/menu status before constructing a full snapshot. Unchanged freshness avoids rebuilding the event feed and sorting diagnostics; successful source publications remain immediate.
- Action History keeps expanded notes and selected details reachable within compact windows. Native before/partial/final geometry, draft navigation, window restoration, 1,178 passing tests, and the final release compile are recorded in `docs/NATIVE_DRAFT_HISTORY_REVIEW_20261002.md`. These are bounded isolated checks, not completion of the full native matrix.
- Chat publishes verification expiry through one shared deadline while a Chat surface is visible. Refresh, expired, failed, empty and verified states stay distinct; failed reads and obsolete results cannot silently restore sending. Drafts survive expiry and recovery. Exact regression and native evidence are in `docs/CHAT_EXPIRY_VISIBILITY_REVIEW_20261002.md`.
- Hidden dashboard display clocks stop while preserving their original visible cadences and calendar alignment. The dashboard-only CPU sampler also stops when hidden, including queued cancellation; monitoring, history, alerts and automatic actions continue independently.
- Hosting Apply preserves a restart warning for a token saved during its follow-up read. Endpoint discovery rejects superseded reads and permits an explicit fresh Copy retry after authentication changes, without copying a staged token as an active unauthenticated endpoint credential. Controlled store tests cover these races.
- Opportunity's Network activity page has an explicit Refresh action with a busy state. Manual success or failure replaces the owned automatic wait with the new deadline, retaining the five-minute successful cadence and bounded failure backoff without overlapping loops.
- Native 22 verifies Chat expiry and exact draft recovery after the same window is minimized and restored through the popup. Compact Network activity, Electricity validation, provider-update accessibility naming, and the Support review/save-cancellation path have bounded native evidence. The hidden-clock hosting test now waits for the actual hidden render before checking that dates stop. Final 1,212-test and release-build results are in `docs/HOSTING_HISTORY_RECOVERY_REVIEW_20261002.md`; broader keyboard and accessibility proof remains open.
- Native Quit now gates process exit on one owned asynchronous cleanup, including updater/monitor shutdown and the pending provider-operation join. Monitoring explicitly owns its unified-log reader even before start or between events; overlapping stops join process exit and handle cleanup. Support's previously inconclusive keyboard paths passed in a fresh sheet-targeted review. Exact race regressions, shared-gate native proof, and an installed-app stopped-provider CPU baseline are recorded in `docs/QUIT_CLEANUP_KEYBOARD_REVIEW_20261002.md`.
- Compact Logs keeps its title/picker visible while the independently scrolling table and page make event details reachable. Health freshness rows expose full timestamps/reasons to accessibility. Fan and automatic-provider-update writes reject expired evidence, and the app updater protects retained dashboard idle/fan drafts after routing away or closing. Bounded native proof and regressions are in `docs/SETTINGS_HEALTH_LOGS_REVIEW_20261002.md`; broader Chat, Hosting, credential-editor and popup draft update protection remains separate work.
- The updater now also protects retained dashboard/pop-out Chat and Hosting drafts, popup fan edits, mounted credential/Auto input, active Chat sends and pending Hosting confirmation. Local Discard controls restore only their own buffers and invalidate earlier saves. Native 29, independent review, 1,254 passing tests and the release compile are recorded in `docs/UPDATE_EDITOR_PROTECTION_REVIEW_20261002.md`; actual updater installation and the broader native matrix remain open.
- Model controls expose contextual native accessibility actions, Metrics retains an independently reachable Refresh button, and charts distinguish series with shapes, line patterns and compact numbered legends. Visit logos adapt to dark appearance. Popup preferred sizing follows actual hosted content before placement and after disclosure changes. Activity animation stops when hidden or dismantled and recovers after rapid close/reopen without adding a polling clock. The bounded native proof, 1,264 passing tests and remaining accessibility/motion limits are recorded in `docs/ACCESSIBILITY_MOTION_POPUP_REVIEW_20261002.md`; this checkpoint does not establish the complete native review matrix.
- Popup sizing now respects its actual screen and anchor, with body scrolling or a native whole-popup fallback at very small heights. Native checks cover 80/240/360-point budgets, actual-screen expansion, dark/grayscale, Auto/Nudge/Cooling and retained fan edits. CPU sampling balances its host-port ownership: 512 real reads produce zero reference growth versus 512 extra references before. Paid Chat prompts use plain language with all gates retained. Final 1,267 tests, release compile and bounded native evidence are in `docs/POPUP_SCREEN_CPU_REVIEW_20261002.md`; broader accessibility, production and distribution gates remain open.
- Cooling preserves each measured fan/temperature field and qualifies retained or unverified evidence visibly and accessibly. Request cards qualify past reports in their spoken value/help and keep missing data unavailable. GPU sampling rejects cancelled queued reads and ticks. The regressions and bounded native review are recorded in `docs/RESOURCE_FRESHNESS_GPU_REVIEW_20261002.md`; this remains part of the ongoing review rather than completion of every screen/state.
- Hosting distinguishes selected/applied settings, timestamps explicit discovery reads, ties copy feedback to the exact command, and aligns its mode cards. Saved idle-alert and startup-model choices have valid truthful presentation without implicit preference rewrites; preserving control refresh follows clean external changes and retains late edits. Native 47–49, independent review and 1,306 passing tests are recorded in `docs/SETTINGS_HOSTING_MODELS_REVIEW_20261002.md`; broader accessibility, production and distribution proof remains open.
- Chat names speakers while preserving selectable messages and canonical model identity; New Chat requires explicit cancellation during a send. Earnings retains selected filters without inventing results. Opportunity qualifies each retained network value and aligns expanded cards. Metrics uses finite nonnegative render-time freshness without moving its analysis window. Model sheets fit their host screen, retain missing-model drafts, and reject late callbacks whose alias now identifies another model. Bounded native and regression evidence is recorded in `docs/CHAT_ACTIVITY_MODELS_NATIVE_REVIEW_20261002.md`; the wider native and distribution matrices remain open.
- History derives one visible snapshot and supports full model-ID search, with cheaper fields matched before formatting. Network-cache restoration joins cancelled reads before refreshing and retains the existing cadence/backoff. Six finite model-image families reuse their normalized marks. Component measurements, Native 62's compact History/icon/disclosure proof, 1,357 passing tests, and the release compile are recorded in `docs/HISTORY_CACHE_IMAGE_EFFICIENCY_REVIEW_20261002.md`. Sustained native hidden-window/route-away proof was inconclusive; broader native, production, and distribution gates remain open.
- Electricity describes actual recording readiness, and prepared Support reports retain their alert-history availability metadata. Logs derives one display snapshot with bounded temporary date formatters while preserving identities, selection, export, and date semantics. Compact light/dark native checks, independent review, the 1,368-test pass, release build, and a finite real-window/cache-child visibility proof are recorded in `docs/SETTINGS_LOGS_VISIBILITY_REVIEW_20261002.md`. The two 65-second holds show no hidden/absent cache reads and prompt refresh on restoration/remount; this bounded synthetic host proof does not replace production navigation, VoiceOver, comparable whole-app profiling, or distribution gates.
- Explicit Chat Cancel restores the initiating composer after its keyboard-focused button disappears, without shared-store completion focus changes. Native dashboard/pop-out keyboard proof, four finite two-view focus cases with owned cleanup, stable selected Logs across publications/arrivals/filters, and the unchanged 1,368-test pass plus release compile are recorded in `docs/NATIVE_CHAT_KEYBOARD_LOGS_REVIEW_20261002.md`. The matrix remains open; actual VoiceOver awaits the scoped desktop-setting reply. A measured model-cache timestamp rebuild cost was small, so no production cache rewrite was made.
- Opportunity's full page now scrolls without blanking when compact guidance expands, and search matches the displayed short model name without requiring catalog metadata. Earnings axes retain an unrounded numeric scale to avoid a tiny-profit crash; isolated Area values draw shaped points with numbered badges and original-amount precision. Native 67–71 cover expanded Overview/Health, compact/wide Opportunity, dense thirty-day chart controls and final scalar points. The 38 focused regressions, 1,381-test pass, final release compile, provenance and limits are in `docs/WIDE_DASHBOARD_KEYBOARD_REVIEW_20261002.md`. Actual VoiceOver, native empty/negative/known-zero overlap, production profiling and distribution gates remain open.

- Hosting now reveals no-address selection attempts without rewriting the saved binding, and startup-picker callbacks reject refreshed alias identity changes while preserving later drafts. Native Models review repaired selectable canonical-ID accessibility recursion and keeps footer Done visible outside scrolling content. Native71–76, rejected candidates, bounded keyboard/selection proof, 1,385 passing tests and the final release compile are recorded in `docs/HOSTING_STARTUP_NATIVE_REVIEW_20261002.md`. Offscreen focus reveal, Escape from selected text, actual VoiceOver and the broad native/distribution gates remain open. The subsequent app-native Autopilot checkpoint is recorded below.

- App-native Autopilot enrollment uses supported noninteractive commands, preserves saved choices, reconciles uncertain outcomes and distinguishes shadow, active, paused and stale status. Native79 verifies consent, immediate dirty-draft guards, inert Enable/Pause/Resume/Leave and actionable recovery; 1,417 tests and the final release compile pass. `docs/AUTOPILOT_NATIVE_REVIEW_20261002.md` records exact provenance, the unaccepted blank Leave-alert capture, protected production and remaining real-provider/accessibility/distribution gates. This focused checkpoint does not complete the broader plan.

- Manage-sheet focus scrolls native controls into view with centered margins; a sheet-owned plain-Escape handler closes selected canonical text without consuming modified Escape. Actual Native83 Tab/Shift-Tab/selection checks, Native84's 3/3 finite key-loop/cleanup proof, 1,417 passing tests and release compilation are recorded in `docs/MODEL_KEYBOARD_NATIVE_REVIEW_20261002.md`. Background activation failures remain recorded, and VoiceOver, real composition, other displays, native alert rendering and the wider matrix remain open. Installed production and its provider were unchanged.

- Metrics retains each completed read/analysis scope through pending and failed period/model changes, qualifies historical loaded visits and suppresses first-read zero results. Native87 verifies actual arrivals/expiry, held/empty/failed reads, recovery, route-away cancellation and forward offscreen focus reveal. Final 1,425 tests and release compilation pass; `docs/METRICS_SCOPE_KEYBOARD_NATIVE_REVIEW_20261002.md` records rejected candidates and provenance. Reverse Shift-Tab skipped offscreen controls at that checkpoint; the subsequent Native88 follow-up below repairs that sequence. The broader goal and distribution gates remain open.

- Metrics uses one native focus section to retain its controls in the sequential key loop. Native88 verifies actual compact dark/wide light forward/reverse traversal, expanded details, the filtered path without Show more and paused-publication native segment selection. All 1,425 tests and release compilation pass again. The review above retains the before/after trace and exact provenance. Sustained segment-focus preservation during publications, mounted slow analysis, VoiceOver and the broader matrix remain open.

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

The Provider/Fans/Updates checkpoint adds execution-time idle/beta freshness,
real finite visible expiry, protected fan submissions until matching readback,
per-field fan freshness, and historical CLI notices with compact wrapping.
Native 53, the 1,324-test pass, and release-build evidence are recorded in
`docs/PROVIDER_FAN_CLI_SETTINGS_REVIEW_20261002.md`. The live provider's separate
managed-launch cache failure remains unresolved after the authorized scoped
permission reset; this checkpoint does not complete the full review matrix.

The subsequent Chat/Activity/Opportunity/Models review is recorded in
`docs/CHAT_ACTIVITY_MODELS_NATIVE_REVIEW_20261002.md`. Native failures in rejected
accessibility candidates were corrected before accepting the checkpoint. The
sanitized, unsent provider diagnostic is in
`docs/PROVIDER_CACHE_STARTUP_DIAGNOSTIC_20261002.md`; matched model selectors and
successful shell scanning do not establish managed-launch cache access.

Review the popup, Overview, Activity (Earnings and Metrics), Opportunity, Models, Hosting, Chat, Action History, Health & Logs, and every Settings page. The iPhone Companion page is a setup surface; it must not imply a shipped companion capability that is absent.

For each route check light/dark appearance, narrow/wide windows, keyboard focus and shortcuts, accessibility names, Reduce Motion, tooltip usefulness, consistent card/pill sizing, missing/stale/offline states, retained unsaved drafts, and normal-speed updates without flashing or layout shifts. Inspect actual rendered screens; builds and fixtures alone are insufficient to claim complete visual polish.

The two-minute Chat verification-expiry presentation and explicit Refresh path are repaired. Remaining Chat review includes the complete native route/appearance/size matrix and actual VoiceOver behavior; focused local fixture checks and both-route automated tests do not establish that broader proof.

Kevin subsequently authorized resuming the provider with its saved settings. Use isolated fixtures for visual states that do not require a real provider, and do not swap or nudge merely to produce visual evidence.

On October 2 Kevin authorized resetting only Darkbloom's removable-drive permission. The `SystemPolicyRemovableVolumes` reset for `io.darkbloom.provider` succeeded, but the saved-settings restart still exited while reading the Sol cache. Its failed service and recovery watcher were stopped; the saved configuration hash remained unchanged. System Settings showed Darkbloom's removable-volume switch on. Diagnose that boundary before another retry; this does not authorize broader privacy resets, Full Disk, or Keychain access. Release publication is held until required native behavior is verified.

- Native91 preserves pending Metrics period and visit keyboard choices through changed measurements, then confirms with Space. Both native pickers share a stable leaf with immutable selection comparisons; 1,427 tests and the final release compile pass. The streaming diagnosis, rejected Native89 and intermediate Native90 are recorded in `docs/METRICS_SCOPE_KEYBOARD_NATIVE_REVIEW_20261002.md`. Broader native and distribution gates remain open.

- Native92 fixes false idle draft edits caused by native focus callbacks repeating unchanged text. Actual 30 focus/Tab stays clean; typing 45 still protects edits and Discard restores eligibility. The regression, partial Provider traversal, new upper-control key-loop finding and provenance are in `docs/PROVIDER_KEYBOARD_DRAFT_NATIVE_REVIEW_20261002.md`. All 1,429 tests and the final release compile pass. The full settings and distribution gates remain open.

- Native100 repairs idle editing lost when a read-only model refresh disabled
  the enclosing settings group. Mutations remain serialized and their actions
  stay gated. Sustained clean/dirty editing passes in compact light and wide
  dark. Native101 removes only the synthetic banner and verifies dashboard
  entry through both Autopilot buttons, plus forward/reverse lower-page reveal;
  the banner-origin skip is not proven as a product defect. All 1,429 tests and
  release compilation pass. Standalone/expanded/state-specific key loops,
  VoiceOver, real actions, profiling and distribution remain open. See the
  Provider keyboard review for rejected candidates and exact evidence.

- Native102 reproduced Fans disabling its entire editor during a read-only
  model refresh. Native103 keeps presets, sliders, disclosures, Discard and
  readings usable while helper commands wait for the shared mutation gate.
  Native104 wires popup Cooling to the same gate and verifies live sheet updates.
  Wide light and compact dark edits survive readback; pointer dragging works
  during a delayed read, and Reload cancels and joins it. All 1,430 tests and
  Release compilation pass. The Fan settings review records exact provenance;
  full keyboard/VoiceOver, real helper actions and distribution remain open.

- Native106 traces the fan enable switch losing focus when native disabling
  occurs. A standard macOS checkbox preserves focus; Native107 verifies sustained
  focus, confirmation cancellation and the bounded wide-light key sequence.
  Native108 checks compact dark traversal but exposes missing keyboard reveal
  for offscreen policy controls, which remains open. All 1,430 tests and Release
  compilation pass. See `docs/FAN_KEYBOARD_NATIVE_REVIEW_20261002.md`.
  Native108 also reconfirms app-native Autopilot Enable/Pause/Resume/Leave;
  real enrollment and distribution remain separate gates.

- Native111 repairs the compact Fans offscreen-control issue: native focus
  requests minimum scrolling with a six-point ring margin, preserving card
  layout and source-update stability. Compact light/dark forward/reverse paths,
  draft retention, Refresh and keyboard Discard pass; Native112 adds wide
  comparisons and dark traversal. All 1,430 tests and Release compilation pass.
  The Fan keyboard review retains both intermediate candidates and exact proof.
  Standalone/stale, full-window continuation after Discard, VoiceOver, real helper
  actions and broader optimization/distribution remain open.

- Native114 adds the requested popup Hosting summary: selected mode, qualified
  discovery state, local base URL/authentication/check time and a sanitized
  coordinator hostname from fresh running telemetry. No extra periodic reader
  is added. Light empty discovery, dark reported listener and report expiry are
  visibly checked; CUA dismisses the transient popup when targeting its actions,
  leaving native Refresh/navigation proof open. All 1,436 tests and Release
  compilation pass. See `docs/POPUP_HOSTING_NATIVE_REVIEW_20261002.md`.

- Exact-path CUA rebinding resolves the popup action-test targeting issue.
  Native114 confirms Hosting navigation and Refresh; constrained keyboard review
  then finds offscreen hosting focus and transient Refresh focus loss. Native116
  reveals the two hosting controls through nested native clips only on focus
  entry and preserves Refresh focus during reads. Light 80-point and dark
  240-point native paths and the 1,439-test pass are recorded in the popup Hosting
  review. The rest of the popup key loop and broader optimization stay open.

- Native116 then confirms offscreen model Refresh, Available and electricity
  focus. Native117 extends focus-entry reveal across popup controls with an
  opt-in environment so shared dashboard controls register no native anchors.
  Light 240-point and dark 80-point rendered rings, Available Space expansion,
  footer/header reverse reveal and stable held focus pass. All 1,440 tests and
  Release compilation pass. Enabled model mutations, conditional entries,
  physical wheel/VoiceOver and broader optimization/distribution remain open;
  exact evidence is in the popup Hosting review.

- Hosting native review finds offscreen Apply/input focus and lazily omitted
  network choices. Small eager choice groups and shared native reveal repair
  page-local traversal. Native121 additionally keeps the invalid port visible
  when Discard inserts above it, using document geometry rather than focus-only
  updates. Compact light/dark draft/Discard, wide dark traversal/aligned cards
  and dark 80-point popup regression pass; all 1,443 tests and Release compilation
  pass. Native118–120 partial/rejected results and the separate installed 1.9.15
  process baseline are recorded in `docs/HOSTING_KEYBOARD_NATIVE_REVIEW_20261002.md`.
  Full window-entry order, state-specific controls, VoiceOver, current-source
  profiling and distribution remain open.

- Banner-free Native122 proves the light compact window-entry path and reveals
  LAN/custom-address controls. Malformed-address validation retains visible
  focus. Saving a valid custom address disables the focused Use-address button
  and resets subsequent navigation; Native123 repairs this with editor-owned
  native focus and verifies light/dark save and reverse traversal. Confirmation
  AX/default Cancel/Escape pass, but repeated blank sheet images leave rendering
  unaccepted. Exact accepted and rejected observations are appended to the
  Hosting keyboard review; broad completion remains unproven.
  The normal suite, explicitly isolated editor-focus regression and Release
  compile pass; their separate invocation and initial parallel-focus failures
  are preserved in that review and `Tests/NativeUI/README.md`.

- Earnings keeps offscreen filters in both native key directions, preserves individual model labels and reveals its history table. Empty, recorded zero and unknown states remain distinct; Decimal table values retain micro-dollar precision and scalar Area readings use points. Native129, rejected candidates, 1,449 reported tests and Release compilation are recorded in `docs/EARNINGS_KEYBOARD_VALUES_NATIVE_REVIEW_20261002.md`. Pending-read focus/scope retention, conditional controls, VoiceOver and broader performance/distribution gates remain open.

- Earnings now retains a completed report across pending/failed reads, with its
  captured dates, model, measure and time zone. Hidden revisions start no reads;
  hiding, model changes and Metrics navigation cancel obsolete work. Native131
  verifies compact light and wide dark retention, empty/error/retry and native
  minimize/restore paths. The regular suite passes with 1,458 reported tests and
  six opt-in skips; Release compilation passes. Pending Refresh keyboard focus,
  conditional date controls, live-zone changes and wider performance/distribution
  remain open. See `docs/EARNINGS_RETAINED_READ_NATIVE_REVIEW_20261002.md`.
