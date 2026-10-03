# Action History retention and production resource observation

## Installed-app evidence

The preserved running Bloomy is 1.9.15/build 140, PID 61760, launched October 2
at 12:55:28. Its wide dark Updates window was raised with its native accessibility
action; no navigation, edits or settings were changed. A screenshot and AX text
confirm the route and version. The restart/saved-edit question remains pending.

A calibrated 30.0016-second process observation measured:

- 2.86087 process CPU seconds: **9.5357% of one core**.
- Median resident memory 339,410,944 bytes (**323.69 MiB**); median physical
  footprint 339,789,432 bytes. These are process measurements, not GPU memory.
- Thirty read-only daemon observations report active inference throughout,
  GPT-OSS 20B, unchanged provider PID, no loading transition and maximum source
  age 2.0114 seconds. No synthetic inference or model swap was requested.

The Mach time conversion self-check passed against `getrusage` using the
125/3 timebase. The app's process identity and executable hash were unchanged.
This is one active-work observation on a parked route, not an idle average,
battery/energy measurement or proof of fully exposed compositor state.

A separate five-second, ten-millisecond stack sample finds a substantial busy
branch in `ActionHistoryStore.ingest` → `ActionHistoryDatabase.record` → `prune`
→ SQLite. It implicates retention during earnings replay; it does not establish
the precise fraction of all CPU or sustained usage. No credential, prompt or
provider-log contents are benchmark inputs.

## Focused source change

The old retention statement rebuilt a retained UUID set and scanned the entire
table on every recorded/replayed earning. The new statement selects expired
rowids through the existing timestamp index, plus rows beyond the newest count
limit, then deletes only those rowids. It remains one atomic statement in the
existing transaction, with the same inclusive age boundary, row limit and
descending rowid order for equal timestamps. No retention cache or schema
migration is introduced.

The source SHA-256 for the checked database implementation is
`3478d7fa9ee65b25457c748e38add4e96ae6a24be67ffdd7ad8e7a747f7f1649`.
This optimization follows published 1.9.17/build 142 and is **not in that ZIP**.

## Component comparison and verification

The reproducible benchmark extracts the actual production SQL and compares it
with the frozen pre-change query. It calls `/usr/lib/libsqlite3.dylib`, version
3.54.0 on this Mac, matching the platform library used by the app. A preliminary
Python-library pilot is retained separately; its timings are not the final
platform-library result.

All 144 exact row/order comparisons pass: empty, one-row, small, 5,000-row and
over-limit histories; unique/equal timestamps; multiple count limits; no,
partial, boundary and complete age expiry. Five serial timing repetitions
alternate reference/current order, using 100 warm in-memory retention
transactions per repetition with secure deletion enabled.

| 5,000-row fixture | Reference median ms | Current median ms | Ratio |
| --- | ---: | ---: | ---: |
| Unique timestamps | 2.2901 | 0.5928 | 3.86× |
| Equal-timestamp groups | 1.9275 | 0.3350 | 5.75× |

These measure the retention component, not complete recording, disk I/O,
whole-app CPU, energy or installed-release improvement. The installed build
was preserved, so no before/after production savings are claimed.

Public-API regressions independently check simultaneous age/count retention
against an in-memory ordered reference across nine combinations, inclusive age
expiry after reopening, and equal-timestamp replay order. The focused 13-test
suite passes. The full run passes 1,528 app/telemetry, 21 protocol and 28 host
tests: **1,577 reported**, including seven explicit opt-in skips. Release
compilation passes in 23.69 seconds. No view source or layout changed.

Evidence: `/tmp/bloomy-production-profile-20261003/`, especially
`build140-updates-resource.json`, `build140-updates-context.json`, the AX/PNG,
`build140-updates-stack.txt`, and `action-retention-system-sqlite-final.json`.
Logs: `/tmp/bloomy-action-retention-focused-20261003.log`,
`/tmp/bloomy-action-retention-full-tests-20261003.log` and
`/tmp/bloomy-action-retention-release-20261003.log`.

Reproduce with a fresh output:

```sh
python3 Tests/PerformanceBenchmarks/action-retention-query.py \
  --source Sources/DarkbloomTelemetry/ActionHistoryDatabase.swift \
  --output /tmp/fresh-action-retention.json
```

Comparable current-source installed-app visible/minimized profiling, actual
energy/allocation measurements and long-duration hardware/provider behavior
remain open. The broader Apple-native polish and efficiency goal is active.
