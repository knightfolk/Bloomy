# Popup Action History — October 10

The popup is the everyday control surface: provider Start/Stop, Autopilot,
one-slot Auto setup, nudge, model selection/preload/swap/uninstall, Hosting,
cooling, GPU protection, profit switching, energy and app settings are reachable
through its command bar or More panels. Chat retains its separate native window.
Detailed Activity and Opportunity analysis remain dashboard surfaces.

More now also opens Action History in the popup. It reuses the existing durable
store, search, All/Actions/Jobs filters, Refresh, selectable outcomes and account
attribution notes. A compact recording caption replaces the dashboard's large
title; the dashboard keeps its default presentation. Missing storage stays an
explicit failure or unavailable state. There is no new timer, network call,
provider command or retry/replay behavior. Opening and Refresh perform the same
bounded local history read as the dashboard.

## Verification

- All 1,880 application tests across 236 suites and 49 companion tests pass in
  the full nonparallel run. The focused 15 history tests include four embedded
  560-point layout cases at heights 300/620 with selected details and expanded
  notes; all columns fit. The 49 native staging tests and Release build pass.
- The exact final inert native fixture shows More → Action History, search with
  no matches, Jobs/Actions filtering, Refresh, Done/reopen, selected failed Swap
  details, and a successful synthetic Nudge with its qualification. Light at
  620 points and dark at 360 points retain the model column and reachable details
  through native outer scrolling. Empty, storage-failure and unavailable states
  remain distinct. No actual provider action or inference was performed.
- A repeated synthetic row could not be uniquely resolved by the automation
  accessibility action; a fresh rendered coordinate selected the observed row.
  The fixture dashboard sidebar did not change pages through the attempted
  actions, including after Show Dashboard. Interactive dashboard navigation is
  not qualified here. Its unchanged default view has focused layout regression
  and Release compilation evidence only.
- Independent review found a missing fixture notification for injected history
  replacement. It now invalidates the monitor before replacing that reference,
  including when synthetic observations are paused. Final review reports no
  remaining actionable finding in this scope.

Evidence: `.build/popup-history-20261010/`. Logs include focused tests, full
serial tests, staging checks and the Release build. Final debug fixture:
`/Volumes/Sol/BloomyReview/popup-history-20261010/native-final/`.
All 144 recorded input hashes match; strict review signing passes. Binary SHA:
`bb4cccfc392377161e1df8072e710c38b9dc5ae03f7333fd268a9c3b70ce4310`.
The fixture includes preserved pre-existing MenuBarMotionProof changes, which
are not included in this checkpoint. Review signing and debug rendering do not
qualify distribution or production performance. The review app was normally
quit; installed Bloomy PID 7234 remained running and was not replaced.

Full spoken accessibility, real traffic, production resource profiling and the
broader polish/release gates remain separate.
