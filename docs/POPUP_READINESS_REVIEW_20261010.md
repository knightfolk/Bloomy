# Popup readiness review — October 10

## User-visible change

The popup command bar previously derived Online/Offline from process-running
status. The native baseline simultaneously shows Connection unconfirmed in
Overview and Online in the popup. A running process does not establish a
verified coordinator connection, authorization or warm serving model.

The new compact mascot control shares MonitorStore.providerReadiness with the
dashboard. Short states include Ready, Serving, Unconfirmed, Needs refresh,
Scheduled, Transitioning and On demand. Its tone also comes from the same
immutable presentation. Hover and accessibility retain the full authored
explanation. Clicking opens the suggested existing Health, Hosting or Models
popup panel, defaulting to Health when no recovery action is suggested.

No provider command, configuration write, poller or new process-identity read
is introduced. The existing identity cache remains shared across visible
summaries and expiry is evaluated against the existing popup clock.

## Review and checks so far

Independent review rejected the first transition caption, Finishing work,
because transition also includes validating model selections and preparing
startup models. The corrected neutral caption Transitioning is checked with
those actual readiness inputs, not only a manually constructed enum. Two inert
native fixture choices now expose validation and startup preloading. A labeled
argument-order issue in the fixture was corrected before its build.

The initial 50 focused checks pass. The final 33-check recheck includes the
TERM-resistant child cleanup test, passing in 0.315 seconds. Two full parallel
runs hit that unchanged test's one-second elapsed limit at about 1.07 seconds.
Those failures are retained in the logs; no assertion or timeout was weakened.
A complete nonparallel run passes: 1,879 application checks across 236 suites,
plus 49 companion checks. The final copy corrections also pass all 50 focused
checks. The 49 native staging checks and final Release application build pass.
Parallel-load timing is not claimed qualified by the serial result.

Final independent review reports no remaining actionable issues. Authorization
is captioned Check access because the presentation says unconfirmed, rather
than assuming permission is known missing. Accessibility punctuation is fixed.

## Final native proof

The exact final debug fixture records 144 source inputs, all matching the
current source; its strict review signature passes. Binary SHA-256:
`66f94c0930c1ca66f8262bc961776ce474b88339836fd4a97512545288bfb2ab`.
This is inert native UI qualification, not optimized performance or distribution
proof. The installed production app and provider settings were not changed.

Nine synthetic scenarios cover ready, serving, validation, preloading,
scheduled waiting, stopped, expired authorization, on-demand models and stale
daemon data. Actual light and dark captures show the compact caption fitting
the command bar. Clicks open Health, Models and Hosting inside the popup, with
Done returning to the parent. Final evidence is under
`.build/popup-readiness-20261010/verified-final/`, including `matrix.json` and
route accessibility captures. All task-owned review apps were normally quit.

A stale automation closure reopened the earlier candidate during the first
final attempt. The mixed-window `final-unconfirmed-light.png` is rejected and
excluded from final proof. The replacement captures used one verified process
and a new handle bound to the exact final build.

The existing model card can still say Serving now while live performance says
Idle. This is a separate presentation question to audit; this checkpoint only
changes provider readiness. Broad spoken accessibility, motion, production
performance and release qualification remain open.

Baseline screenshot: `.build/popup-readiness-20261010/baseline.png`.
