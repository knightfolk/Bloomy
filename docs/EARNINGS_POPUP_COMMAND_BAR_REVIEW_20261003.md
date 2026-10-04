# Earnings graphics and shared popup command bar

Kevin requested less text, more graphics for Earnings, and a dense icon-first
popup bar containing provider, Autopilot, energy and cooling controls.

The implementation uses existing SwiftUI views and guarded provider actions.
The Earnings summary follows the displayed model/reward filters. It shows
recorded gross, model shares, jobs and the count of calendar intervals with
ledger entries. Negative net series use signed bars instead of pie slices;
unknown and recorded-zero states stay distinct. The existing time chart retains
its gap, precision, signed-axis and series-accessibility behavior. Chart options
and the ledger are available on demand. Profit per earning hour remains a
separate measure and is never summed into a gross dollar total.

The popup has one common header: brand/navigation, provider action/Autopilot/
Auto/Nudge, then GPU/adapter power/cooling readings. Autopilot uses fresh native
evidence and distinguishes shadow, live, paused, pending and stale states. Its
entry opens the existing enrollment/policy controls. Auto still edits the saved
one-slot plan; it does not imply active network Autopilot. Opening Nudge does
not send a request. Stop retains native confirmation and accepted-work draining.
Matched electricity shows gross and cost bars on a shared scale with the
estimated balance, using only matched intervals.

## Final verification

- Focused initial suite: 78 tests passed after the first compiler correction.
- Expanded suite: 82 tests passed, including summary filter/zero/signed/invalid
  cases and compact Autopilot mode assertions.
- Final full suite: 1,548 telemetry/UI tests, 21 companion protocol tests and
  28 companion host tests reported passing; seven existing opt-in tests skipped.
  Total reported: 1,597. The final Release build passed.
- Final isolated fixture:
  `.build/earnings-commandbar-native-final5-20261003/`.
  All 113 source hashes match the current checkout (103 production view/support
  sources, ten fixture/support sources). Its binary digest is
  `7b095ec8ae4d771f70e1a0e7408133c90daf36641a6cbe9ef73c858db155faad`.
- Native CUA review: wide/light Earnings, compact/dark layout and scrolling,
  reward hiding ($6.0600 → $5.5800), ledger expansion, and signed corrections
  ($0.4600 total with -$0.0200 rewards) were inspected. The final signed summary
  uses bars, retains the negative amount, and reports 20/24 ledger intervals.
- Popup normal/dark shows readable neutral action labels, earnings immediately
  below the common bar, and complete default model controls. At 360 points the
  bar stays fixed while the body scrolls. At 80 points native accessibility
  scrolling exposes the action row, then GPU/energy/fans through the outer
  viewport. Pointer scrolling in the remote offscreen popover failed with
  `windowNotFoundAtPosition`; the exposed native Scroll Down action worked.
- Final popup entries: Cooling opens its panel and Refresh; Auto opens the
  one-slot startup plan; Nudge opens its setup guide without sending; Energy
  opens Electricity after asynchronous popup dismissal. Fan temperature and
  speed are retained in the compact control's accessibility value.
- Autopilot: stale evidence disables mutations; Refresh restores native opt-in
  and the consent screen can be cancelled. In the exact final fixture, synthetic
  Shadow → Pause → Paused → Resume → Shadow was confirmed. Its saved receipt
  `autopilot-action-counts.json` reports zero enrollments and two policy actions.
- Accepted-work Stop was checked in the synthetic accepted-work scenario:
  “Drain and stop the provider?” explicitly preserves accepted requests; Cancel
  dismisses it. Existing lifecycle regression tests pass. Matched energy in the
  final fixture shows $5.6300 gross, $0.7600 power cost and $4.8700 after power
  across 22 matched hours, with no live sensor acquisition.
- Earlier candidates are retained under task-owned build paths. The first
  popup placed earnings too low; the dark candidate had subdued blue action
  labels. Both were corrected. One fixture build failed on the new scenarios'
  exhaustive switch and was repaired before the passing final build.
- The installed 1.9.18/build 143 app, real provider and unrelated dirty work are
  preserved. No provider inference or mutation is needed for visual proof.
  Final read-only verification: installed build remains 143, real provider PID
  47646 is fresh in shadow mode with Qwen 3.8 and Gemma 4 advertised, and the
  configuration SHA-256 is unchanged. The installed dashboard was restored to
  its original Updates page; no update switches were changed.

## Completed resource capture, before this redesign

Two 30-second read-only build-143 Metrics captures completed. Visible CPU was
7.00% of one core; after native Minimize it was 6.47%. This is a bounded sample
under a running provider, not a controlled before/after optimization result.
Neither window observed inference or increases in requests/tokens; five visible
samples reported a loading transition, compared with zero minimized samples.
Raw measurements and contemporaneous provider context remain in
`.build/production-profile-20261003-build143/`. No claim of a new performance
improvement is made from these captures.

These checks establish a bounded native redesign checkpoint. Real account
integration, all display/large-text/VoiceOver states and the broader polish and
efficiency matrix remain separate. No release, production replacement or push
is part of this checkpoint. The final synthetic review app may remain open for
Kevin to inspect.
