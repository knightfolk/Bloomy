# Health diagnostics and deferred update ownership

This is a verified source checkpoint after published 1.9.16/build 141. It has
not been packaged as a newer app release. The broader polish goal remains open.

## Health presentation and native proof

Native161 showed complete wrapped reasons, but Needs attention repeated the
entire daemon diagnostic and pushed Source freshness off the compact initial
screen. The summary now names unavailable, last-known or noncurrent-timestamp
daemon details. Its existing warning gate is unchanged. Full reasons remain
selectable/accessibility-labelled below, in expanded details and in the tooltip.

Native163 exposed centered unavailable-daemon and thermal bodies beneath
left-aligned headings. Explicit leading stacks/frames now align those bodies.
Retained cards and slot details keep their existing contents.

The fixture adds mixed stale/missing/current and four-source unavailable cases,
two-paragraph reasons with distinct endings, and a long synthetic model ID.
Retained daemon/log timestamps precede acquisition; mixed CLI status remains
separately current. Dependencies remain inert. Mac identity/thermal state is
actual as disclosed by the banner; fan/temperature samples are synthetic.

Native160 failed because the fixture Earnings switch needed the two new enum
cases. Native161 is the before-summary baseline; Native162 is superseded after
independent review corrected mixed-state chronology. Native163 is the
before-alignment capture. Only Native164 is final-source rendering evidence.

CUA inspected Native164 at 800×560 and 1280×900 with all four sections expanded:

- Compact light missing summary retains the Source freshness heading. Wide
  light unavailable-daemon/thermal content aligns with its headings.
- Wide dark four-source reasons retain every paragraph and distinct ending.
- Compact dark unavailable verification shows its complete reason. Ordinary
  scrolling reaches the final acquisition diagnostic and complete long ID.
- Mixed wide light daemon/slot details remain usable. The compact dark model
  ID wraps onto two lines with all KV/MTP rows visible. Its last diagnostic is
  also reachable.

PNG/AX evidence: `/tmp/bloomy-health-long-review-20261003/`. All 109 final source
hashes, actual binary and staged telemetry library match the manifest.
Native164 binary SHA-256:
`484ee1fee12f807f54eaa28de9544774ac31edf0a85468beef1cb53921fbe803`.
Session: `BloomyDashboardFixture-B2EB44D9-FE44-4B2F-A7C4-77CB1F554EDF`.
The fixture quit normally. Its ad-hoc signature is not distribution proof.

## Deferred update callback

The actual `SPUUpdaterDelegate` callback had three defects: a clean replacement
left an old deferred handler polling; release before the first task turn could
still install; a blocked loop retained its owner across sleep. The fix cancels
the previous task before either guard branch, cancels on deinitialization, and
evaluates a weak owner's guard into a Boolean without retaining it across
suspension. A vanished owner cannot resume installation. No new timer was added.

Six regressions dispatch through the real optional Sparkle protocol method with
real updater/appcast types in a disposable bundle: clean handoff, blocked resume
exactly once, blocked/clean replacement, and release before/during polling.
Sparkle is never started, no request is made, and private defaults stay unwritten.

Worker red evidence is terminal session 12321/chunk 38d594, exit 1: four failed
assertions across three of eight tests. Green session 54654/chunk efc29b passed
all eight tests in 2.164 seconds, exit 0. There are no saved red/green log files
to claim. This verifies callback ownership, complementing actual application
draft-guard tests and the isolated 1.9.16 installer gates. It does not prove a
real production updater/dirty-editor installation or native production Quit.

## Final verification and preserved runtime

Final Swift tests: 1,525 app/telemetry, 21 protocol and 28 host tests; 1,574
reported tests including seven opt-in skips. Release compilation passed in
46.86 seconds; diff check passed. Saved logs:

- `/tmp/bloomy-health-updater-final2-tests-20261003.log`
- `/tmp/bloomy-health-updater-final2-release-20261003.log`
- `/tmp/bloomy-health-long-native164-build.log`

The earlier full run/45-second Release build preceded the alignment change;
final2 covers final production source. Independent review found no title-truth
issue; its chronology finding was fixed before final rendering.

Bloomy PID 61760 and provider/watchdog 63387/63393 retained original start
identities. No provider lifecycle, model/inference, credentials, privacy or
installed-app change was made. Actual source transitions, spoken freshness,
arbitrary display sizes, full native coverage, comparable whole-app profiling
and native production updater/editor integration remain open.
