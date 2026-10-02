# Provider cache startup diagnostic — October 2, 2026

Prepared locally; not sent or uploaded. The message below contains no credentials,
configuration contents, model IDs, account identifiers, or raw log dumps.

## Copy-ready vendor message

Darkbloom 0.9.17 cannot read an external-volume model cache when starting through
its managed LaunchAgent, although the same installed executable can scan that
cache from the current shell.

Runtime: Apple Silicon (`arm64`), macOS 27.2, build `26B5091g`. The installed
application passes strict signature verification with identifier
`io.darkbloom.provider`, Developer ID Eigen Labs, Inc., team `SLDQ2GJ6TL`, and
CDHash `a9643be5f7094b56b0feed25729ca25e07f6e6b5`.

On October 2, a user-authorized reset of only
`SystemPolicyRemovableVolumes` for `io.darkbloom.provider` succeeded. System
Settings subsequently showed Darkbloom's Removable Volumes permission enabled.
The official saved-settings restart still failed:

- The managed provider exited 1. At `07:05:59 -0700`, its scanner reported that
  the external cache's `hub` directory could not be opened, followed by no models
  selected.
- The restart command exited 64 after its 180-second authorization wait. Its
  timeout text said the service was still starting; this did not establish a
  successful provider start. No second restart was issued on that timeout.
- The failed provider service and recovery watcher were then stopped with the
  official CLI.

A later read-only scan,
`darkbloom models list --config <saved-provider.toml> --json --all`, exited 0,
returned 12 model records from the expected external Hugging Face cache, and
produced no stderr. This establishes shell scan access, not successful model
loading or managed-service access.

Both LaunchAgents resolve to the same signed executable used for that scan. The
provider agent already runs `start --foreground`, with seven explicit model
selectors. Those seven selectors exactly match the saved enabled-model list,
and all seven are exact IDs in the successful scan. The saved preload list is
empty. Configuration SHA-256 remains unchanged:
`18c539de187013299d9801e68b79c92922477b37beb5c0aa83220d51e514b229`.
Cache ancestors exist with ordinary permissions. No broader privacy grant,
entitlement edit, configuration change, or cache relocation was attempted.

The cache warning does not expose an underlying `NSError` domain/code or errno.
Bounded startup log inspection did not recover that error. TCC separately
rejected an AppleEvents request from the provider because its hardened-runtime
automation entitlement is absent; its causal connection to cache access is
unproven. A nearby Full Disk Access record was attributed to System Settings,
not the provider, and is not evidence that Darkbloom needs Full Disk Access.

Please provide:

1. The cache-open error's `NSError` domain, code, and `NSUnderlyingError`
   chain, including any underlying POSIX errno.
2. A supported read-only cache-access probe under the same managed LaunchAgent
   identity/context, without loading models, connecting for inference, changing
   configuration, or granting broader permissions.
3. Whether the AppleEvents rejection is expected in this startup path and,
   if relevant, the supported vendor fix.

Installed help exposes no read-only permission-preparation command. `doctor`
includes public checks/subprocesses and network diagnostics; `report` uploads
unless `--dry-run` is supplied. Neither was invoked during this investigation.
The managed-launch access/attribution boundary remains a hypothesis, not an
established cause or permission repair.

## Local evidence pointers — do not copy wholesale

- [Restart command output](/tmp/bloomy-efficiency-20261001/provider-resume-after-drive-reset-20261002.log)
  records the finite timeout. The provider's exit 1 is recorded in the existing
  [scoped-reset review](/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor/docs/PROVIDER_FAN_CLI_SETTINGS_REVIEW_20261002.md:112).
- [Successful scan JSON](/tmp/bloomy-efficiency-20261001/provider-cache-list-after-reset-20261002.json)
  contains the 12 records and effective cache directory;
  [stderr](/tmp/bloomy-efficiency-20261001/provider-cache-list-after-reset-20261002.err)
  is zero bytes. These files contain local paths/model identifiers and are not
  included in the vendor message.
- [Provider log, line 17950](/Users/kevink/.darkbloom/provider.log:17950)
  contains the cache warning. Avoid exporting the surrounding log wholesale.
- [Official stop output](/tmp/bloomy-efficiency-20261001/provider-after-reset-stop-20261002.log)
  records the stopped service.
- Metadata-only checks used the saved config and the two
  `~/Library/LaunchAgents/io.darkbloom.{provider,watchdog}.plist` files. Only the
  configuration hash, counts, selector equality, executable identity, and
  non-secret launch structure were emitted; configuration contents were not.
- OS unified-log checks were bounded to `2026-10-02 07:05:10–07:06:10 -0700`.
  Provider PID `11771` received the AppleEvents entitlement rejection at
  `07:05:23.494`. Full Disk request `msgID=432.11771` instead identifies
  `com.apple.systemsettingsagent`, PID `43945`; the matching number is a request
  identifier, not provider attribution. No new raw log export was created.
- [Earlier launch-access investigation](/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor/docs/LAUNCH_ACCESS_INVESTIGATION_20260928.md)
  provides historical context; it is not proof of this managed-service cause.

Only the new diagnostic document was written during this preparation. Provider
and service state, configuration, privacy, Keychain, source, builds, and the
production application were left unchanged.
