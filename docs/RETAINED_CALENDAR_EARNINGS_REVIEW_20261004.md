# Retained calendar Earnings

Popup and Overview preserve the last valid day/week observations after a
failed read or the existing ten-minute expiry. Compact clock/“last read”
qualifiers and timestamp help distinguish retained graphics from fresh data.
The existing icon-first popup command bar and three equal Earnings tiles remain.

Current-value consumers still reject stale or expired evidence. Menu earnings
and hourly state cannot use failed reads. Successful empty summaries clear old
totals; later failures cannot resurrect them. A real zero replaces retained
values. Day/week calendar validation rejects rollover, undated, future and
invalid observations. No new polling, database, provider or network action.

## Verification

The regression reproduced clearing both successful summaries after an account
failure before implementation. Five focused regressions cover failures,
independent day/week freshness, empty replacement, zero recovery, expiry,
calendar rollover and invalid evidence. Fresh/retained sizing retains the
528-point width and less-than-130-point height requirement in both themes.

- Focused run: 48 reported tests passed, before the sizing check was expanded
  to both fresh/retained variants. Log:
  `.build/retained-calendar-focused-20261004.log`.
- Final full `swift test -c release`: 1,593 telemetry/UI + 21 protocol + 28 host
  reported tests passed (1,642 total); seven existing opt-in checks skipped.
  Log: `.build/retained-calendar-full-20261004.log`.
- Final optimized native compilation passed without the earlier review-only
  Codable warning. Log:
  `.build/retained-calendar-verified-native-build-20261004.log`.
- Exact-source inert app:
  `.build/retained-calendar-verified-native-20261004/Bloomy Dashboard Fixture.app`.
  All 119 manifest source hashes matched the checkout. Executable SHA-256:
  `e09ee70f2693928cabd96a7f81e79cc151cf7e76ee723ca3d6da389574e0c242`.

Computer Use inspected the actual SwiftUI popup/Overview at compact 800 × 560:

- Fresh light popup: 6.4200 Today, 2.1400 per observed hour and 42.4000 Week.
- Account failure: all three graphics retained with aligned clock/last-read
  footers in light and dark. Overview exposes matching qualifiers/timestamp help.
- Day-only failure: Today/hour retained, Week fresh. Week-only failure reverses
  that distinction. Original values and current eligibility agree with the UI.
- Synthetic 601-second-old reads: all three remain visible as retained;
  neither current day nor current week is eligible.
- Recorded-zero recovery: all three display 0.0000 without retained markers.
- Successful empty read, then account failure: waiting remains and old totals
  do not return. Normal recovery restores the populated graphics.

Native state evidence and manifest verification are under
`.build/retained-calendar-proof-20261004/`. UI observations/screenshots are in
this task's Computer Use history. Calendar rollover is regression evidence,
not a real-time native wait across midnight. The expiry fixture supplies an old
capture timestamp; it is not a ten-minute elapsed runtime measurement.

## Limits and handoff

This uses inert services with acquisition off; ad hoc review signing is not
distribution proof. Actual VoiceOver narration, other displays/locales,
production profiling, live account/provider integration and the broader polish
matrix remain open. The prior owned review app quit normally. The final review
host remains available. Installed Bloomy, provider/watchdog, model selection,
configuration and credentials were preserved. No push, installation or release.
