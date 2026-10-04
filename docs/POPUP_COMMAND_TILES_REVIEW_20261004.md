# Popup command tiles and graphical earnings

Kevin requested less text in earnings and one dense, icon-first command bar.
The popup now groups Hosting, guarded Start/Stop, Autopilot, Auto, Nudge and
More in a consistent row above GPU, adapter power and cooling readings.
More contains Dashboard, Settings and Quit. Hosting opens the existing
connection report, refresh and settings entry in a detail popover.

Today, observed hourly earnings and Week use equal-width graphic tiles.
Today/Week bars compare recorded dollar amounts on one scale; they are not
completion gauges or targets. Missing values remain unavailable and partial
week coverage remains labeled observed. The hourly amount remains derived
from observed time. Electricity retains its matched-interval qualification.

Existing action stores, confirmation gates and credential handling are reused.
Secondary forms use their normal label/button styles. This is local source
review work; production installation and distribution are separate.

## Verification

- Final `swift test -c release` passed: 1,572 + 21 + 28 reported tests;
  seven opt-in checks skipped. Log:
  `.build/popup-command-tiles-verified-tests-20261004.log`.
- The earnings sizing checks keep the original 528-point width and less-than-130
  height requirement in both themes. The first two candidates exceeded the
  height limit; padding, graphic height and spacing were corrected without
  relaxing the assertion. The assertion now reports its measured height on failure.
- The exact-source optimized native bundle is
  `.build/popup-command-tiles-verified-native-20261004/Bloomy Dashboard Fixture.app`.
  All 118 source hashes matched the checkout at inspection. Binary SHA-256:
  `05c3693e5da1f115e5a841541c96a82f43b6055ae974e6a3bcb43dda8255f7c5`.
- Computer Use inspected light and dark native popups, including matched gross,
  electricity and after-power estimates. Auto opens its one-slot/startup-model
  form; Nudge opens the keyless setup guide; Cooling opens and refresh advances
  its checked time; Available expands and collapses; accepted-work Stop opens
  its drain confirmation and Cancel returns to the popup.
- Hosting and Autopilot detail panels were checked and their Refresh actions
  updated their synthetic reports during the preceding native candidates.
- A nested More popover failed navigation: its dismissal consumed the parent
  close request. It was removed. The replacement uses an AppKit NSButton and
  ordinary NSMenu for its three actions, retaining SwiftUI layout and styling.
  Native Settings navigation then closed the parent automatically and opened
  Appearance. The final icon-spacing variant uses the same menu/action code.
- Final-source Energy navigation opened Electricity. Quit from the native More
  menu completed ordinary fixture cleanup and process exit; no review or
  prototype process remained before the inspection handoff relaunch.
- The provider configuration SHA-256 remains
  `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
  No live provider, model, key, network inference or installed production app
  was changed for this review.

The fixture uses synthetic services. Full VoiceOver narration, other locales,
other displays and live provider integration remain separate proof. This does
not close the broader optimization and polish plan.
