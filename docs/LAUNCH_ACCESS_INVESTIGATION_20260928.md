# External model-cache access investigation

## Reproduced boundary

The same packaged read-only probe executed the installed provider's `models
catalog` and `models list --all` commands with the same explicit configuration.
Only timing, exit status, JSON counts, and an allowlist of non-secret launch
variables were recorded. No inference or provider mutation was requested.

| Launch/test | Catalog | Local list |
| --- | --- | --- |
| Direct executable | 0.93 s, 10 entries | 1.22 s, 12 records |
| Normal app launch | 25 s timeout, no output | 25 s timeout, no output |
| Direct executable with GUI cwd `/` and minimal GUI environment | 0.88 s, 10 entries | 1.14 s, 12 records |

A second GUI-launched probe used `/bin/ls` instead of the provider. Listing a
task-owned internal temporary directory took 0.12 s. Listing the external
Hugging Face cache timed out after 25 s. This reproduces the boundary without
the provider CLI, SwiftUI, or the monitor's process runner.

The blocked provider child was sampled in `ModelScanner.scanAllModels`, inside
Foundation directory enumeration and the kernel `open` call. Both probes were
bounded and their owned children exited. No weight files were moved or changed.

## macOS access evidence and limits

The privacy logs attribute the GUI child's file-access request to its responsible
GUI app, and record a `SystemPolicyAllFiles` service-policy denial. This is
evidence of a privacy/access-control path; it is **not** proof that Full Disk
Access is required. The exact removable-volume decision for that request was
not established. A separate removable-volume error for `spindump` is unrelated
and must not be used as proof for Darkbloom.

System Settings already showed **Removable Volumes on** for both Darkbloom Control
and DC Beta. No switch was changed. The same existing Beta bundle was then closed
after confirming no pending model changes and launched normally. Its catalog
failed again. A visible enabled permission entry is therefore insufficient to
establish successful access for this Beta.

The reviewed Beta has an ad-hoc designated requirement tied to its code hash.
The installed production app has a stable Developer ID designated requirement.
A stale or mismatched review-build permission association remains a hypothesis,
not a confirmed cause. No controlled production restart was performed, so this
investigation does not establish that the signed production build fails the
same launch test.

## Changes and next verification

- Preserve safe command-failure categories through model refresh diagnostics,
  including a conditional external-volume access hint for timeouts. Never echo
  raw CLI stderr, launch errors, credentials, or arbitrary paths.
- Keep last-good inventory explicitly stale when a refresh fails.
- Supply a removable-volume purpose description in packaged apps. This explains
  a system prompt; it neither grants access nor bypasses macOS privacy controls.

A signing-only comparison used a copy of the same Beta, with unchanged code and
Info.plist, signed with the release Developer ID. Its normal launch still did
not complete catalog loading. Stable signing alone is not a verified fix.

Next controlled OS-level test: re-request only that review app's
removable-volume permission if authorized.
Do not reset production permissions, grant broad Full Disk Access, change global
security settings, move the model cache, or restart the provider as a workaround.

Apple documents external-volume consent under
[app file access](https://support.apple.com/en-gb/guide/security/secddd1d86a6/web)
and the
[removable-volume purpose key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremovablevolumesusagedescription).

Raw task-owned timing and sampled-stack evidence remains under
`/tmp/darkbloom-launch-audit`; it is not included in release assets.

## Validation checkpoint

The integrated provider-service/store suite passed 118 tests, including safe
failure categories, last-good fallback, and rejection of credential-bearing or
malformed diagnostic strings. All 16 packaging tests and the monitor release
build passed. These changes improve diagnosis and permission-purpose text; they
are not a claim that the OS access failure has been fixed. The signed comparison
Beta remains the normal-launch reproducer. No production restart or provider
mutation was requested by this investigation. The final process check observed
that production Control had a different PID than at the start and its installed
version was 1.9.0; the cause of that transition was not established. Both provider
PIDs remained unchanged.
