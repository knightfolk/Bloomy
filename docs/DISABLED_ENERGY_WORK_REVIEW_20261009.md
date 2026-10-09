# Disabled electricity tracking: avoid empty financial work

When electricity tracking is disabled, `updateEnergyEarnings` now clears any
previous result once and returns before reading the financial session. Repeated
disabled samples do not republish the same empty energy-earnings value.

The independent account observer remains active. Re-enabling still reads the
authoritative session, validates the report and uses the account-bound cache.
Credential validation itself is unchanged. The energy recorder still receives
disabled samples so it breaks continuity across an off period; no electricity
cost is interpolated through that gap.

## Bounded evidence

Baseline: `b05de1947dcdb1a021dc07a7b5cb7e8d13956323`. Evidence is retained in
`.build/recurring-work-review-20261009/`.

Two new regressions first failed against the baseline. In 360 disabled calls,
the empty-result case published 361 energy-earnings notifications, including
initial financial-context clearing. Disabling a populated result published 360
notifications instead of the single necessary clear. Both also failed their
no-additional-session-read checks. The three existing efficiency tests passed.

The corrected tests require zero session/activity reads and zero unchanged
energy-earnings publications for 360 disabled calls. Disabling a populated
result must clear exactly once without additional session reads. Re-enabling
after a different account is installed, without any account-change callback,
must authenticate again, query fresh activity and display the new account's
amount. These calls simulate repeated samples; they are not an hour-long
production measurement.

An independent read-only review found no blocking issue in the guard, account
observation or test coverage. Existing account-isolation, held-result and energy
continuity regressions remain part of verification.

The focused Release run passes 26 tests in three suites. The full serial Release
run passes 1,854 reported app tests in 233 suites, plus 21 protocol and 28 host
tests, with seven existing opt-in skips. Both finite runs exit zero. The focused
run also compiles and links the Release monitor product successfully; the final
full Release product build exits zero after 48.94 seconds.

## Limits

This eliminates energy-specific session reads and energy-earnings notifications
while disabled. The outer ten-second sampling timer and its `energy = nil`
assignment remain. No whole-app CPU, allocation or power reduction is claimed.

A five-second read-only sample of installed Bloomy 1.9.19/build 144 includes
native popup document-fitting stacks. Current source already contains the
closed-popup fitting fix from `483553e`; this installed sample is neither a new
current-source regression nor a matched performance comparison. The sample
does not establish whether that popup was visible throughout acquisition.

There is no visual layout change in this checkpoint. The prior synthetic native
popup review remains at `b05de19`; it is not a rendering of this newer source.
Installed Bloomy and the provider configuration are preserved. No provider
command, account request, download, inference, push or release is used for proof.
