# Health version clarity — October 2, 2026

The expanded Provider & verification section could label a fresh daemon-state
version as Running even when the provider was stopped or its process identity
could not be matched. `ProviderVersionView` checked snapshot age, not liveness.
The compact light Native132 Offline review reproduced Installed CLI 0.9.17 /
Running 0.9.17 alongside Monitor Offline, stopped CLI evidence and Verification
unavailable. Fresh file contents are insufficient evidence of a running process.

The view now names that observation Daemon snapshot. Installed CLI and daemon
versions use aligned native Grid rows with selectable values and combined
accessibility labels. A mismatch is described as CLI versus daemon snapshot,
and missing/expired inputs explicitly show Current version details unavailable.
The existing 60-second CLI and 10-second daemon freshness limits are unchanged.
Nearby Verification remains responsible for confirming live process identity;
no additional process reads, acquisition, timer or provider action were added.

A bounded native read-only worker confirmed the version-label root cause and
found no additional concrete truncation issue in Health/verification/load-history
views. It did not build, test or inspect screenshots. Its audit also identified that stale and unavailable verification both said
Waiting for current verification details, while the actual reason was exposed
only in Source freshness. The verification card now explicitly says Verification
unavailable and shows the read reason; retained stale data is labeled Last
snapshot retained. A failed process match now says This snapshot could not be
matched to a live provider process, without asserting that one is running.

## Checks

- Full debug checks pass: 1,418 app/telemetry tests in 187 suites, 21 protocol and
  28 host tests, totaling 1,467 reported tests with seven opt-in skips.
  Log: `/tmp/bloomy-health-version-final-tests-20261002.log`.
- The change is presentation only; existing freshness policy is retained. No
  tests were added that merely restate the new strings. Native before/after
  checks verify the user-visible version and missing-state presentation.
- The initial version-only Release compile passed in 47.30 seconds. Native133
  confirmed aligned version rows but still displayed the misleading currently
  running sentence in Verification. It is retained as intermediate evidence.
- Final repeated debug checks after verification wording changes also pass:
  1,467 reported tests with seven opt-in skips. Final log:
  `/tmp/bloomy-health-version-verification-final-tests-20261002.log`.
- Final Release compilation passes in 48.25 seconds. Log:
  `/tmp/bloomy-health-version-verification-final-release-20261002.log`.

## Native134 review

CUA screenshots and native state confirm:

- Compact light and dark stopped-provider views show aligned Installed CLI and
  Daemon snapshot rows, followed by Verification unavailable and a failed live
  process-match explanation. There is no Running version claim.
- Compact light unavailable sources show Current version details unavailable,
  the actual unavailable reason inside Verification and Daemon details unavailable.
- Wide dark unavailable sources preserve all four unavailable source rows and
  their reasons, with the provider/verification/daemon/thermal groups expanded.
- Wide dark stale sources show retained-snapshot wording; compact dark reasons
  wrap without a one-line truncation, and the full verification reason is
  reachable by ordinary pointer scrolling.
- Wide light stopped-provider presentation also fits. Compact light scrolling
  reaches the last acquisition diagnostic with all four sections expanded.
- The view handles the controlled source transitions without acquiring a live
  endpoint or modifying provider settings. Long identifiers, multi-paragraph
  reasons, real helper actions and spoken VoiceOver remain outside this pass.
- The fixture quit normally and its process is absent. Production is unchanged:
  PID 61760, start October 2 12:55:28, executable SHA-256
  `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.

All 101 recorded source hashes match the current checkout. The actual native
binary matches the readable manifest:
`1c47dc13bc44f803962b752e55e546233e3c66094bc3b6e4152852988e6bbe83`.
The staged telemetry library is
`8cf12eae552d8257e720e21b28eb2ceebe53b95e5fcbd590998805ce4beb6e9c`.
The existing inert substitutions are CLIUpdateNoticeView, SystemCPUUsageStore
and NetworkCacheView; production startup remains excluded.
Build log: `/tmp/bloomy-health-version-verification-native134-20261002.log`.
Native133 and Native134 each occupy 48 MiB and are retained for provenance.

## Artifact plan

Sol manifest readback stalled in the preceding checkpoint. The new isolated
Native133 and Native134 reviews are stored internally under their respective
`.build/native-dashboard-fixture-20261002-133` and `...-134` directories.
The comparable prior fixture is 48 MiB; this bounded artifact fits the remaining
65 GiB without moving established data or changing drive permissions. Prior
review artifacts and unrelated work remain preserved. Do not treat a review
signature as notarized distribution or broad completion evidence.
