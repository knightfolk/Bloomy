# Verified cache cleanup — October 3, 2026

Kevin requested researching the unexpectedly large internal model cache and
reclaiming space, including other safe cleanup candidates.

## Research and retained models

The installed provider reports CLI 0.9.17. Research used its exact upstream tag,
commit `75a6f4dbdc3b4d3bfe75213f36a2e99531c93db2`, rather than the older local
provider source checkout:

- [ModelScanner](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/ProviderCoreFoundation/ModelScanner.swift)
  selects `refs/main` explicitly. Legacy discovery occurs only when that ref is
  absent. All seven advertised models select their `.revision-*` snapshot.
- [ModelArtifactRevision](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/ProviderCore/Models/ModelArtifactRevision.swift)
  preserves independently owned immutable revisions for activation and rollback.
  Hard-linking mutable snapshots is explicitly forbidden; none were introduced.
- [ModelArtifactWriteLease](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/ProviderCore/Models/ModelArtifactWriteLease.swift)
  serializes writers with `flock` on stable `.artifact-writer-locks` files. Cleanup
  held the same exclusive leases, nonblocking, for all seven models and never
  removed those lock files.

The `.revision-*` snapshots, receipts, `refs/main`, provider configuration,
credentials, advertised model set and installed applications were retained.
The original complete external cache on Sol remains untouched for rollback.
No provider stop, restart, swap, model download, nudge or synthetic inference
was performed.

## Removed duplicates

For every regular file in each legacy `snapshots/local` directory, cleanup
independently SHA-256 hashed both current files and compared them with each other
and with the migration manifest. Sizes, timestamps and file identities were
checked before and after hashing; all 79 pairs passed. No open legacy files were
observed in the host process inventory.

Before unlinking, cleanup atomically renamed only the legacy directory to a
hidden sibling, then confirmed the complete `darkbloom models list --all --json`
result was unchanged. The same running provider PID and advertised set, with a
fresh daemon snapshot, were also checked. The hidden legacy copies were then
removed, leaving the selected revisions intact.

| Model | Identical file pairs | Removed logical GiB |
|---|---:|---:|
| EigenLabs/Qwen3.8-27B-4bit-mtp | 14 | 15.20 |
| gemma-4-26b-qat-4bit | 10 | 14.57 |
| gpt-oss-20b | 10 | 11.27 |
| nvidia-nemotron-3.5-lightning | 10 | 17.27 |
| qwen3.5-35b-a3b | 14 | 19.46 |
| qwen3.6-35b-a3b-vl-mtp-mxfp8 | 13 | 19.85 |
| ternary-bonsai-2-27b | 8 | 8.02 |

Total removed model-file bytes: **105.632 GiB**. The complete cache falls from
230.44 GiB to about 124.81 GiB. This includes the unselected older Qwen model
(17.01 GiB) and Whisper/CLAP/HTDemucs (2.16 GiB), which were preserved because
other applications may use them. Discovery of all 12 model records was unchanged.
The provider PID remained `63387`, with seven advertised models and active
GPT-OSS inference at the follow-up observation.

## Other completed cleanup

A read-only audit checked exact path types, allocated sizes, cache contents,
process use and open files. A fresh root/open-file check preceded deletion of
these inactive reproducible caches:

| Cache under `~/Library/Caches` | Allocated GiB before removal |
|---|---:|
| `Sparkle_generate_appcast` | 0.671 |
| `pip` | 0.065 |
| `node-gyp` | 0.061 |
| `electron` | 0.106 |

Total: **0.903 GiB** of cached release extraction, downloads and development
headers. They can be regenerated. Queued ZCode/MiniMax updates, active/native
proof builds, project source and provenance, DerivedData, simulator data and
other application state were retained. Bloomy's `.build` is about 15 GiB but
contains active processes and source/manifest evidence, so it was not swept.

## Space accounting and authorized snapshot cleanup

Deleted bytes are not the same as immediately reclaimed physical storage. `df`
and `statvfs` still reported about **19 GiB immediately free** after cleanup.
Eleven purgeable local Time Machine snapshots were present, nine created after
the internal model-copy completion. They appear to retain the deleted blocks.
Foundation reported about 58.6 GiB available for important use; this is a
separate estimate, not a measurement of released duplicate bytes.

[Apple describes local snapshots](https://support.apple.com/en-ca/102154) as
backup history that macOS can reclaim automatically. Removing a volume snapshot
also removes intermediate restore points for unrelated files; it cannot remove
only model bytes from that snapshot.

Kevin then explicitly authorized snapshot removal: “Don’t care about the
snapshots. I need space.” A fresh local snapshot (`2026-10-03-133546`) was created
and verified first. All nine planned local snapshots from 02:27 through 10:37
were then removed with `tmutil deletelocalsnapshots`; each command exited zero.
The 00:27 and 01:27 snapshots, later 11:37/12:38 snapshots, fresh 13:35 snapshot
and network backups were retained. No backup settings were changed.

After removal, `statvfs` measured **130.94 GiB immediately free**,
a gain of **112.78 GiB** from the live pre-removal measurement. `df` agreed,
reporting 131 GiB free on the Data volume. This is actual released space, not
just deleted-file totals or estimated purgeable capacity. The larger gain than
the model-file total includes other blocks held by those same snapshots.
A fresh daemon observation confirmed the same provider PID (`63387`), seven
advertised models, warm GPT-OSS and active inference. No provider interruption
was needed.

Detailed source research, cleanup script, file hashes, unchanged inventories,
completed-cache records and the completed snapshot plan/results are retained locally in
`/tmp/bloomy-cache-research-20261003/`. No credentials, prompts or raw provider
logs were included in the report. This storage work does not finish the broader
native polish/optimization goal or authorize a release.
