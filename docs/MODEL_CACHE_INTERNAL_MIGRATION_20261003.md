# Internal model-cache migration — October 3, 2026

Kevin requested moving all models off Sol because external-drive access was
unreliable. The complete Hugging Face cache now resides at
`/Users/kevink/.cache/huggingface`. It is a real internal directory on the same
device as the home folder. No environment override or provider TOML change was
needed; the former external symlink was replaced only after the copy passed.

The provider's recovery watcher had restarted it before migration. The official
`darkbloom stop` drained two accepted requests to zero, received the coordinator
acknowledgement and unloaded provider/watchdog services. No force flag or process
kill was used. No model download, manual swap, benchmark or synthetic inference
was requested.

## Copy and verification

- 317 regular files and 28 relative cache symlinks; 247,434,002,930 bytes
  (**230.44 GiB**), including the existing ancillary Hugging Face cache contents.
- Each regular file was streamed to a separate internal staging directory,
  SHA-256 hashed during source reading and independently hashed after destination
  flush. Every comparison passed. File sizes/timestamps and complete source and
  destination inventories matched; all cache links stayed within the cache tree.
- The old active symlink was renamed to
  `~/.cache/huggingface.external-backup-link-20261003`, then the verified internal
  staging directory was renamed to `~/.cache/huggingface`. The original
  `/Volumes/Sol/LLMS/HuggingFace-cache` remains intact for rollback.
- Before/after `darkbloom models list --all --json` returned exactly identical
  12 model records. The effective cache changed from Sol to
  `/Users/kevink/.cache/huggingface/hub`; the internal read emitted no errors.
- The saved provider configuration SHA-256 was unchanged before switching and
  after restart. Credentials and the installed Bloomy application were untouched.

The initial `df` result showed only 59 GiB immediately free. Foundation reported
294 GiB available for important use, enough for this user-requested copy plus
a 50 GiB reserve. [Apple's capacity guidance](https://developer.apple.com/documentation/foundation/checking-volume-storage-capacity)
specifies this check for requested storage. The copy rechecked that estimate and
a ten-GiB immediately-free floor throughout; macOS reclaimed space automatically.
No manual snapshot deletion, cache sweep or unrelated cleanup was performed.
At copy completion: 36.73 GiB immediately free and 63.53 GiB available for
important use. These are separate, time-specific measurements.

## Restored runtime

`darkbloom restart --startup-timeout 180` completed successfully and reported a
fresh authorized legacy connection. The following read-only status reported CLI
0.9.17, running PID 63387, seven local selected MLX models, always-ready idle
memory policy and unchanged experimental Autopilot enrollment. Provider and
watchdog LaunchAgents were both running.

A daemon snapshot less than one second old reported all seven selected models
advertised, one warm Qwen 3.8 model, no load transition, no pending startup preload,
shadow Autopilot and active inference. This demonstrates restored serving at
that observation; it does not predict future uptime or prove every model can
load. No manual model rotation was performed merely to test the migration.

The copy manifest, individual hashes, before/after model records and sanitized
completion summary are retained locally under
`/tmp/bloomy-model-migration-20261003/`. No raw provider logs, prompt contents or
credentials are included in this review.

This removes the external-cache access boundary for the active setup. The
broader native polish, large-history optimization, rendering/accessibility and
distribution gates remain open.

Follow-up: `MODEL_CACHE_CLEANUP_20261003.md` records removal of 105.632 GiB of
byte-identical, unselected legacy `snapshots/local` copies. The selected managed
revisions remain internal and the external backup is preserved. Local Time
Machine snapshots still appear to retain the removed bytes; physical space
reclamation is tracked separately from cache-file removal.
