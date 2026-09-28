# Darkbloom CLI 0.9.11 integration

Verified locally on September 28, 2026 against the installed signed CLI and
the public release record. This is implementation evidence, not release proof
for a new Darkbloom Control build.

## Release delta

`GET https://api.darkbloom.dev/v1/releases/latest` reported active provider
version `0.9.11`, bundle SHA-256
`d3e35441dfbefbbf91bd4c3c1cb2465babffb562fee8651edfbc62f529f1fdf7`,
created at `2026-09-28T03:26:45.074411Z`. Its published changelog contains one
provider-facing change from 0.9.10: exact model ID `Qwen3.5-9B` now defaults to
SSD prefix caching and paged KV under the automatic backend policy. Case
variants and aliases remain excluded. Darkbloom Control already decodes the
reported KV/cache posture; this change does not justify inventing a new switch.

## Public CLI capabilities adopted

- `darkbloom switch --model … --timeout 600` applies a complete saved model
  selection after a graceful drain on the same coordinator session. The app
  now offers this only with fresh, matching 0.9.10-or-newer runtime evidence.
- Sparse 0.9.10/0.9.11 daemon lifecycle snapshots are decoded without treating
  absent optional trust/capacity fields as fabricated failures.
- `darkbloom autoupdate enable|disable|status` is exposed as a saved provider
  setting. It is separate from the Sparkle updater for Darkbloom Control.
- `darkbloom fan status|diagnose` stays read-only. The official privileged
  mutations are `enable`, `configure`, `disable`, and `uninstall`. Control uses
  only those commands, validates 60–90% and 15–125 °C locally, passes the CLI
  path and arguments separately into a fixed AppleScript authorization bridge,
  and never stores an administrator password. Privileged fan mutations reject
  executables discovered through `PATH`; the bridge verifies the canonical
  provider executable against identifier `io.darkbloom.provider` and Team ID
  `SLDQ2GJ6TL` inside the administrator-approved command before execution.

The installed parent command's `darkbloom fan --help` currently renders the
default `status` help rather than listing all subcommands. Direct help for each
documented subcommand and the upstream CLI reference establish the writable
surface.

## Deliberately unavailable

- Custom curves and a 100% target remain **Coming Soon** because the official
  helper exposes one threshold and caps the target at 90%.
- Proactive warming, load-first replacement, and automatic demand switching
  remain **Coming Soon** because no public atomic API provides those semantics.
- `doctor --clear-backend-guard`, enrollment removal, log upload, forced
  lifecycle interruption, and provider update installation are not folded into
  ordinary settings. They have distinct recovery, privacy, or customer-impact
  consequences.

## Verification boundary

Command construction, bounds, fixed privilege script, decoder compatibility,
and settings rendering have automated coverage. No test or implementation step
changed the live fan policy, automatic-update preference, provider model
selection, or enrollment. A signed packaged build must still prove the native
administrator prompt and post-operation refresh before publication.
