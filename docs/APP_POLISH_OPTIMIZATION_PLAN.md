# Bloomy native polish and efficiency

October 3 Earnings/popup checkpoint: Kevin's icon-first redesign now has a
graphic earnings total, model/reward composition, jobs and ledger intervals,
with chart options and ledger detail on demand. One shared popup header groups
provider, guarded Autopilot, Auto/Nudge, GPU, energy and cooling controls.
Native dark/compact, signed, action and 80/360-point scrolling checks,
1,597 reported tests (seven opt-in skips) and the Release build passed. This is
a local review checkpoint; installed build 143 and the provider are preserved.
See `EARNINGS_POPUP_COMMAND_BAR_REVIEW_20261003.md`. It does not complete the
broader native/VoiceOver, performance or real integration matrix below.

October 3 distribution checkpoint: version 1.9.18/build 143 was rebuilt from
the verified current source, signed, notarized, stapled and published with
matching asset digests and four exact-ZIP isolated updater gates. The running
installed app and provider were preserved. See
`RELEASE_1_9_18_VERIFICATION_20261003.md`; this does not complete the remaining
native, accessibility, performance or production integration review below.

The ongoing goal is a consistent, polished native Mac app with minimal background cost. A verified release checkpoint does not establish that every screen or state has completed review.

October 3 Action History checkpoint: compact columns retain Model and complete
timestamps; short search results keep details close. Native168 verifies mixed
5,000-entry history, precise amounts, resize/Refresh selection and filter recovery.
Actual public-API recording with isolated synthetic databases is 35–48× faster
than build 142 across four measured workloads, with exact retained-field/order
parity. Final 1,579 reported tests (seven opt-in skips) and Release compilation
pass. See `ACTION_RECORDING_COMPACT_HISTORY_REVIEW_20261003.md`; installed app
profiling and the broader native matrix remain open. This source is distributed
in signed/notarized 1.9.18/build 143 with four isolated updater gates verified.

The [native completion matrix](NATIVE_COMPLETION_MATRIX_20261002.md) indexes all
22 surfaces, distinguishing bounded coverage and each remaining proof gap.

October 3 Menu Bar checkpoint: settings shares the live three-ring status view,
adds icon-led explanations and the actual 70/85 °C boundaries, and keeps the
idle reminder separate from nudge timing. Native169/171 renders compact/wide
light/dark and reachable expanded details. Native171 preserves the same view,
layer and geometry through eight reading changes and passes all model/chart
checks, but only 12/15 motion cases pass: genuine cover occlusion and two
close/reopen cases remain unresolved. This fresh trace supersedes any inference
of reliable reopening from older bounded motion evidence. A drawing-callback
experiment failed and was removed. No release is ready from this checkpoint;
see `MENU_BAR_INDICATOR_PREVIEW_REVIEW_20261003.md`.

October 3 motion diagnosis: native stop callbacks confirm cancellation after
reopening; a one-retry recovery regressed order-out and failed both reopen
checks, so it was removed. The helper now requires real advancing angles across
more than one rotation cycle without forced display. Root ownership and direct
layer-content experiments did not repair reopening; a genuinely occluded cover
is still unproven despite confirmed front/opaque coverage. No release is ready.
Final retained-source Native183 still passes 12/15 motion cases; model/chart
checks, 1,579 reported tests (seven skips) and Release compilation pass.
See `MENU_BAR_ANIMATION_CANCELLATION_REVIEW_20261003.md` for rejected candidates,
finite traces, provenance and the next restoration/commit-boundary investigation.

October 3 resumed host comparison: the unchanged production SwiftUI label again
passes active rotation, ordinary/rapid reopening and actual dismantle. A fifth
case uses a separate app with an ordinary opaque window. Its WindowServer
front ordering and full target coverage pass, but the target never loses its
actual compositor-visible flag: terminal 4/5, genuine cover still unproven.
Both owned test processes exited, with no production lifecycle action. This
rules out different bundle identity alone as the explanation and does not
repair or supersede the standalone fifteen-case gate. Exact source, binary,
cleanup and evidence boundaries are in
`MENU_BAR_SWIFTUI_HOST_DIAGNOSTIC_20261003.md`.

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
- Model controls expose contextual native accessibility actions, Metrics retains an independently reachable Refresh button, and charts distinguish series with shapes, line patterns and compact numbered legends. Visit logos adapt to dark appearance. Popup preferred sizing follows actual hosted content before placement and after disclosure changes. Activity animation stops when hidden or dismantled without adding a polling clock; the older bounded rapid-reopen pass is superseded by the current failing native reproduction above. The bounded native proof, 1,264 passing tests and remaining accessibility/motion limits are recorded in `docs/ACCESSIBILITY_MOTION_POPUP_REVIEW_20261002.md`; this checkpoint does not establish the complete native review matrix.
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
`docs/PROVIDER_FAN_CLI_SETTINGS_REVIEW_20261002.md`. At that checkpoint the live
provider's separate managed-launch cache failure remained unresolved after the
authorized scoped permission reset. October 3's internal-cache migration later
restored startup; neither checkpoint completes the full review matrix.

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

On October 2 Kevin authorized resetting only Darkbloom's removable-drive permission. The `SystemPolicyRemovableVolumes` reset for `io.darkbloom.provider` succeeded, but the saved-settings restart still exited while reading the Sol cache. Its failed service and recovery watcher were stopped; the saved configuration hash remained unchanged. System Settings showed Darkbloom's removable-volume switch on. October 3's verified internal-cache migration and saved-settings restart subsequently resolved that startup boundary. This does not authorize broader privacy resets, Full Disk, or Keychain access. Release publication is held until required native behavior is verified.

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

- Selected-model stacked Earnings bars now share resolved observations with
  Lines/Area, retaining the model identity/color and explicit zeros. Profit
  aggregation matches the old algorithm exactly in boundary tests and runs
  about 23× faster for the isolated eight-model/year Release fixture. Native132
  checks compact light selected bars and wide dark chart styles, aggregate
  fallback and zero/gaps. Full 1,467-test and Release checks pass; post-build Sol
  manifest readback stalled and remains unconfirmed. Details and limits are in
  `docs/EARNINGS_IDENTITY_PROFIT_EFFICIENCY_REVIEW_20261002.md`.

- Health's daemon version is now labeled as snapshot evidence rather than
  Running. Missing versions are explicit, and stale/unavailable verification
  displays its reason inside the card; failed process matching no longer
  assumes a live provider. Native134 checks compact light/dark stopped states,
  expanded missing/stale states, wrapping and lower diagnostics, plus wide
  light/dark layouts. All 101 source hashes and the actual binary match;
  1,467 reported tests and final Release compilation pass. Bounded evidence and
  remaining long-reason/VoiceOver/runtime gaps are recorded in
  `docs/HEALTH_VERSION_NATIVE_REVIEW_20261002.md`.

- Logs now retains new same-second arrivals at count/byte limits and preserves
  newest-first export order. Quiet SwiftUI display-zone changes update local
  times without changing selection or UTC evidence. Native138 checks paused
  Phoenix/UTC/Kathmandu, 100-event eviction/retained selection, light/dark export
  layout and Bloomy filename/clean save cancellation. All 101 source hashes,
  actual binary and final tested telemetry archive match; 1,472 reported tests
  and Release compilation pass. OS locale notification delivery, VoiceOver and
  broader whole-app profiling/distribution remain open. See
  `docs/LOGS_RETENTION_FORMAT_NATIVE_REVIEW_20261003.md`.

- Native Hide/minimize now stop dashboard display reads without stopping history
  recording. Six immutable privacy expressions replace per-field compilation;
  frozen-reference Release tail processing is 4.77–7.15× faster with exact
  retained-event parity. Native139/141, calibrated finite CPU windows, 1,482
  reported tests and Release compilation are recorded in
  `docs/RESOURCE_VISIBILITY_PRIVACY_REVIEW_20261003.md`. Whole-app energy,
  larger-history profiling, genuine compositor occlusion and broad completion
  remain open. Custom keyboard controls are not a project priority.

- Host GPU protection adds Off/Warn/Automatically pause with configurable idle
  pressure and recovery dwell, guarded session-owned graceful restart and
  manual override. A same-model speed drop corroborated by high whole-Mac GPU
  produces a warning while accepted inference continues. Activity Metrics
  includes qualified idle GPU coverage. Native143 inert checks, 1,520 reported
  tests and final Release compilation are recorded in
  `docs/HOST_GPU_PROTECTION_REVIEW_20261003.md`. No real provider lifecycle
  action was issued; current startup remains blocked by the Sol-cache access
  failure. Hardware pressure, long-duration and distribution proof remain open.

- Kevin's October 3 model migration supersedes the startup blocker above:
  the complete 230.44 GiB cache is now internal, every file hash passed, model
  records/configuration match and official restart confirmed fresh authorization.
  A fresh snapshot reports seven advertised models, one warm and active inference.
  The external originals remain preserved. Details and storage/runtime limits are
  in `docs/MODEL_CACHE_INTERNAL_MIGRATION_20261003.md`.

- Metrics now reuses bounded decoded recent rows only after current-BLOB and
  indexed-field verification, and releases derived reuse on page exit/Hide.
  The accepted serial Release comparison measures 56.24 → 13.37 ms repeated
  reads at 10,000 rows and 595.39 → 531.73 ms at 100,000, with first-read overhead
  and a 12.4 MiB isolated resident-size difference explicitly recorded. Native144
  checks compact light/wide dark, route exit/reopen, Refresh, 30-day selection,
  136-second Hide/recording/restore and brief minimize eviction. All 1,537 reported
  tests and Release compilation pass. Actual allocation limits, whole-app energy,
  deterministic in-scan cancellation and wider native/distribution proof remain
  separate; see `docs/METRICS_DECODED_CACHE_REVIEW_20261003.md`.

- Model visits prepare immutable observation facts once, eliminating repeated
  validity checks and resident-set allocation without changing result semantics
  or retaining a history-sized array. Exact-reference tests and five optimized
  100,000-row fixtures measure 2.89–3.05× component improvement. Native145 checks
  compact light/wide dark visit pills, the sole 1m 30s no-work visit and restored
  mixed outcomes. All 1,543 reported tests and Release compilation pass; evidence
  and limits are in `docs/VISIT_OBSERVATION_FACTS_REVIEW_20261003.md`. Separate
  AppKit sheet/modal and minimal SwiftUI references reproduce blank alert
  captures outside Bloomy while normal parent content renders, narrowing the
  Hosting investigation without inventing a confirmation redesign.

- Models distinguishes multiple startup choices from No preference, excludes
  unavailable choices, qualifies startup loading off/default, and separates
  empty/unavailable/search messages. Native145–149 comparisons repair stale
  empty-state offsets and a blank rapid-scroll result while retaining lazy model
  grids and normal Refresh position. Saved inert choices preserve enabled models
  and the loading policy without lifecycle calls. The final 1,544 reported tests
  and Release compilation pass; exact provenance and remaining large-catalog,
  VoiceOver, alias-callback and distribution gates are in
  `docs/MODEL_STARTUP_STATES_NATIVE_REVIEW_20261003.md`.

- Models consolidates identical sanitized action explanations, preserves distinct
  blockers, and shows read progress/failure in Manage. The recovery Refresh stays
  beside Done; disappearance and new errors reveal the padded content top.
  Native155 checks compact/wide light/dark footers, return-to-compact, compact
  light/dark and full-height dark recovery, retained entire drafts/store/sheet,
  and an explicit restored action with zero save/lifecycle calls. Five captures
  each pass 11 bounded native geometry checks after rejecting an intermediate
  sizing regression. The 1,552 reported tests, standalone geometry regression
  and final Release compilation pass. Adjacent AX text remains grouped; spoken
  VoiceOver, long reasons and wider live/distribution proof remain open. See
  `docs/MODEL_FEEDBACK_RECOVERY_NATIVE_REVIEW_20261003.md`.

- Earnings preserves signed ledger corrections in charts and hourly/serving
  profit estimates, distinguishes all-unavailable history from uncertain hour
  boundaries, and keeps micro-dollar hourly cards nonzero. Signed charts have
  independent stack directions and a clearer zero line; stacked AX labels retain
  original amounts. Native158/159 checks actual signed styles, selected work,
  precise cards/table and empty/boundary guidance in compact/wide light/dark.
  The explicit inert visibility override does not prove hidden-window behavior.
  Final 1,568 reported tests, Release compilation and 109-source manifest checks
  pass. Spoken automatic range grouping, actual OS display/time-zone changes,
  wider history performance and distribution remain open. See
  `docs/EARNINGS_SIGNED_UNKNOWN_NATIVE_REVIEW_20261003.md`.

- Health uses concise attention summaries with complete source reasons retained,
  and expanded daemon/thermal bodies align with their headings. Native164 verifies
  bounded long-reason/identifier and missing/mixed layouts. Deferred updater
  callbacks cancel replaced work and cannot install after their owner disappears;
  six real-protocol regressions and the final 1,574-test run/Release build pass.
  These source changes follow published 1.9.16 and are included in 1.9.17.
  See `docs/HEALTH_LONG_REASONS_UPDATER_REVIEW_20261003.md`; full native/VoiceOver,
  production integration and comparable profiling remain open.

- Version 1.9.17/build 142 distributes the Health and updater ownership fixes.
  Exact-commit checks report 1,574 tests, 17 packaging tests and a successful
  Release build. Apple notarization, Gatekeeper, four isolated signed update
  scenarios and pre/post-publication GitHub asset digests pass. All 27 older
  feed items remain. Installed Bloomy and the provider stayed running unchanged;
  real installed-app restart/profiling awaits saved-edit confirmation. See
  `RELEASE_1_9_17_VERIFICATION_20261003.md`. The broader goal remains open.

- Read-only profiling of installed build 140 finds a busy SQLite Action History
  retention branch during natural inference. Retention now deletes expired and
  excess rowids directly; 144 platform-SQLite comparisons preserve exact rows
  and order, and two 5,000-row component fixtures improve 3.86–5.75×. Public-API
  boundary/replay tests, 1,577 reported full-suite tests and Release compilation
  pass. This source optimization follows 1.9.17 and is not yet distributed.
  No installed-app savings are claimed; saved-edit confirmation is still pending
  for replacement and comparable profiling. Evidence and reproduction are in
  `ACTION_RETENTION_PRODUCTION_PROFILE_20261003.md`.

- Downloaded model cards now expose Uninstall directly, with observed size and
  cache location in confirmation. Removal rechecks serving/residency and the
  captured cache, and passes the inventory configuration to the CLI. The full
  suite reports 1,592 tests with seven opt-in skips and no failures; Release
  compilation and inert native Cancel/busy/retry proof pass. Compact light/dark
  content is checked at 650 points. Alert pixels retain the documented capture
  limitation; installed-app delivery, menu-bar motion and the broader matrix
  remain open. See `MODEL_UNINSTALL_CARDS_REVIEW_20261003.md`.

- A native grid-boundary follow-up corrects the compact downloaded footer's
  7.5-point overgrowth at 300-point slots by shortening the preload label to
  “Startup.” The expanded label and model-specific help remain complete. Six
  light/dark geometry reports, actual rendered inspection, staged/reverted
  controls and five focused rendering tests pass. The first overgrown-content
  comparison was rejected and retained. See
  `MODEL_CARD_GRID_BOUNDARY_REVIEW_20261003.md`; wider accessibility/localization,
  full populated three-column and broader screen gates remain open.


- Earnings now presents recorded totals, model shares, signed corrections, jobs
  and ledger coverage graphically, with detailed options and ledger on demand.
  A common popup bar collects provider, Autopilot, Auto, Nudge, GPU, energy and
  cooling entries. Native compact/wide light/dark and bounded popup scrolling
  proof are recorded in `EARNINGS_POPUP_COMMAND_BAR_REVIEW_20261003.md`.
  A follow-up keeps disabled/error helper posture visible even with numeric fan
  readings, and qualifies retained sensors independently. Final 1,603 reported
  tests, Release compilation and exact-source native state checks pass; see
  `POPUP_COOLING_POSTURE_REVIEW_20261003.md`. Both checkpoints are local only;
  all-surface accessibility, production delivery and broader efficiency proof
  remain open.


- A read-only installed build-143 stack sample identifies repeated popup fitting
  during source updates. The native scroll bridge now coalesces clustered
  updates while width/layout requests remain immediate and dismantling cancels
  pending fits. Notification-only sizing was rejected after a real geometry
  regression. Five native component bursts reduce explicit fits from 300 to one;
  actual 360/80-point scrolling, disclosure recovery and normal reopening pass.
  The final 1,606 reported tests and Release build pass. See
  `POPUP_SIZING_COALESCING_REVIEW_20261003.md`. Production savings and the full
  native/accessibility/motion matrix remain unproven; this checkpoint is local.


- Opportunity now shares cached model marks and canonical short aliases with
  popup/Models cards, adds compact metric symbols and a network-only active/
  waiting share graphic, and aligns its native section picker with the title.
  Dark template contrast was corrected after actual rendering. Native compact/
  wide, quiet loaded-provider, retained/missing, alias search and expanded
  details checks pass. Final 1,609 reported tests and Release compilation pass;
  see `OPPORTUNITY_VISUAL_IDENTITY_REVIEW_20261003.md`. Full varied/large-text,
  spoken accessibility, production performance and broader gates remain open.

- Overview now shares Activity's adaptive monetary precision: tiny recorded
  earnings and signed model amounts stay visible instead of rounding to zero.
  Native compact light/dark, wide dark, missing and ordinary states pass in the
  exact inert fixture; 1,610 reported tests and Release compilation pass. See
  `OVERVIEW_EARNINGS_PRECISION_REVIEW_20261003.md`. This local checkpoint adds no
  production acquisition or timers; broader native and performance gates remain.
