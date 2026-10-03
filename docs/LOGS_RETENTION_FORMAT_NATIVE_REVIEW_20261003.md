# Logs retention, display context and export review — October 3, 2026

Scope: ordinary Logs behavior during bounded arrivals, quiet display-zone changes,
selected-detail eviction, and native export review. Custom keyboard shortcuts and
exhaustive traversal remain lower priority per Kevin's direction.

## Changes and regression evidence

- `EventBuffer` accepts chronological incoming reads. Stable timestamp sorting now
  favors later incoming lines within ties, then retained newest-first rows. Legacy
  batches are chronological; streamed callers insert singly. Deduplication,
  sanitization, the 100-event limit and 128-KiB payload cap remain in force.
- Regression tests fail on the old retention implementation (five issues), then
  pass: 101 same-second arrivals, singleton stream parity, repeated complete tail
  replay, and byte-cap ties with known/missing timestamps. Production selection
  tests cover retained versus evicted selected details at the 100-event boundary.
- Logs subscribes to SwiftUI locale/calendar/timeZone and passes that context to
  its per-derivation compact formatter. Row identity, selection and canonical UTC
  evidence remain unchanged. Explicit context and bounded-formatter tests pass.
- Review found the export caller supplies newest-first rows. Its new chronological
  buffer input is adapted by reversing that input. The tied-order export test
  failed twice before this adaptation; it now covers full retention and escaped
  JSON byte-cap trimming that omits the oldest tied entries first.
- Native export filename is `bloomy-logs`. Cancellation was not a bug: the baseline
  native panel returned cleanly to the frozen reviewed preview without an error.

## Native baseline and candidates

Native135 uses unchanged production source from `6a038a3` with inert review controls.
Synthetic publications were paused. Selected event `2026-10-03 07:00:56 UTC` stayed
at `10/03 00:00` after the review display environment changed to UTC; capture time
stayed `2026-10-03 07:01:18 UTC`. This reproduced the quiet-zone dependency defect.

Native136 proves the corrected view: selected event `2026-10-03 07:05:27 UTC`
changed from Phoenix `00:05` to UTC `07:05` to Kathmandu `12:50`, with capture time
fixed at `07:05:53 UTC`. Compact light and wide dark images were inspected; selected
payload and UTC detail remained unchanged. This preceded the export-order fix.
Native137 is excluded as final proof because it captured the prior telemetry
library during the debug rebuild. It was not launched or accepted.

## Final Native138 evidence

All 101 manifest source hashes match the final checkout. Actual binary SHA-256:
`e8098d431a2e65303b9fe85245d50f8b7ecd09a2afff7b31b81fe5e6c68fdea5`.
The staged telemetry archive matches the final tested debug library:
`cf04136189b825a3efe9fc0f8c131a585426d93c9f78087324355c3a9d4c04f3`.
Artifacts are bounded internal review builds (roughly 48 MiB each); the existing
Sol manifest-read boundary is documented in the prior Health/Earnings reviews.

- Paused publications; selected event `2026-10-03 07:09:40 UTC` changes from
  Phoenix `00:09` to UTC `07:09` to Kathmandu `12:54`. Capture time remains
  `2026-10-03 07:10:06 UTC`; selection, payload and UTC details stay fixed.
  Actual compact light and wide dark rendering inspected.
- Resumed synthetic reads, retained selection through ticks, then inserted one
  bounded batch of 100 arrivals. Old selected details clear and the page requests
  a new selection. Selected arrival 100, then inserted arrival 101: arrival 100
  stays selected with unchanged details. Native table reports 100 items.
- Export preview contains 100 events, 0 omitted, 24,239 bytes; first rows are
  101, 100, 99, 98. Actual wide light/dark and compact dark sheets were inspected:
  JSON scrolling, review checkbox and Close/Save footer fit. Save is initially
  disabled and requires review. Native panel suggests `bloomy-logs`; Cancel
  returns to the same frozen reviewed preview with Save enabled and no error.
  No export file was saved. Reopening a preview resets its review gate.
- Wide light details and compact dark table inspected after arrivals. Final
  fixture quit normally; the protected installed process remains PID 61760,
  started Oct 2 at 12:55:28, with unchanged executable hash
  `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.

## Final checks

- Full `swift test`: 1,472 reported tests (1,423 app/telemetry, 21 protocol,
  28 host); seven explicit opt-in skips. Log:
  `/tmp/bloomy-logs-final2-tests-20261003.log`.
- Final `swift build -c release`: success, 48.46 seconds. Log:
  `/tmp/bloomy-logs-final2-release-20261003.log`.
- Native138 compiler/signing log: `/tmp/bloomy-logs-native138-20261003.log`.
- `git diff --check` passes. Read-only reviewer caught the export caller-order
  mismatch; the failing regression and adaptation resolve that finding.
- This is a source/native review checkpoint, not a notarized release or completion
  of the broader optimization goal.

## Boundaries

The scoped display override changes only the review dashboard's SwiftUI environment,
not macOS preferences. The bounded 100-arrival control touches synthetic events only.
These reviews use production views with inert data and documented dependency
substitutions; they do not prove real provider traffic or source occurrence identity.
Exact duplicate immutable payloads still deduplicate. Timestamp ties are resolved
by supplied read order, not invented source sequence identifiers. OS notification
propagation, actual VoiceOver, arbitrary display sizes and distribution remain open.
The real provider, cache, credentials and protected installed app were untouched.
