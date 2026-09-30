# Bloomy

<img src="assets/brand/bloomy-concept.png" width="96" alt="Bloomy app icon concept">

**Meet the little compute companion for your Mac.** Bloomy is a native macOS
menu-bar app for the official Darkbloom provider. It brings live provider
status, measured work and earnings, energy estimates, and practical controls
into one readable popup and dashboard. The new Bloomy character appears in the
app icon and menu bar.

Bloomy was previously named **Darkbloom Control**, and before that **Darkbloom
Monitor**. The provider's official product and CLI are still named
**Darkbloom**; commands such as `darkbloom login` have not changed.

Bloomy can help when work goes quiet. Two optional tools in **Settings →
Provider** are off by default: Automatic nudge can make a tiny request to your
own warm model after an observed idle period; Automatic profit switching can
change the model this Mac advertises when fresh demand, earnings, power, and
idle-state evidence support a meaningful estimated gain. Both wait when the
evidence is incomplete. Neither can promise public work or income.

Open **Diagnostics → Action History** for persistent nudge outcomes, provider
and model actions, and reported account-wide jobs and base rewards. History is
kept locally for up to 30 days or 5,000 entries, without credentials or prompt
contents. Earning IDs identify account records, not individual serving requests.

## Download

Download the Apple Silicon build from [Releases](https://github.com/knightfolk/Bloomy/releases/latest),
unzip it, move the downloaded app to Applications, then open it. Published
releases through **Darkbloom Control v1.9.3** use `Darkbloom Control.app`;
the Bloomy release uses `Bloomy.app`. Check the release page for the version
and signing status of the download you select.
Quit an older monitor copy before launching the new one. macOS may still ask
for first-launch confirmation or permission to read your external model drive.
Bloomy v1.9.10 is Developer ID signed and notarized by Apple, with a stapled
notarization ticket and verified Gatekeeper acceptance.

## Coming soon

The source tree now includes a native iOS companion, cryptographic QR pairing,
pinned TLS transport, multi-Mac status, alert history, and signed command
contracts. They remain development features and are not included in the current
download. The signed persistent Mac helper, physical-iPhone validation, and
release packaging are still required before remote controls ship. No background
remote-control service is installed or enabled by the current release.

The separate recommendation journal remains observe-only and never turns a
recommendation into a provider command. Automatic profit switching is an
explicit, off-by-default setting with its own evidence and timing checks.

## Source highlights

- Bloomy character icon and tintable menu-bar mark
- Menu-bar activity status with clearly labeled model-average throughput
- A compact popup with equal-sized model cards, collapsible available models, and stable live readings
- Swap locally, then send a network nudge while keeping the advertised selection
- Manual Nudge with guided Keychain setup and a clear completed state
- One-slot Auto plans with all selected models advertised and one chosen startup preload
- Configurable idle reminders, separate from automatic nudge timing
- Calendar-day average token throughput, including a per-model
  breakdown once more than one model has measured samples
- Calendar-day earnings, average earnings per observed hour, and a local
  calendar-week total
- Per-model average gross recorded work earnings per earning-hour, with its
  observed-hour count; this does not subtract electricity
- Activity charts with readable per-model company color families, clickable
  model filters, bar/line/area styles, and stacked or side-by-side bars
- Estimated per-model profit per earning-hour, with whole-Mac electricity
  shared evenly among models that earned in that fully measured hour
- Completed jobs today and the prior seven-day daily average when enough local
  history exists
- Green active, yellow loaded-idle, and gray available-model pills that remain
  visible during idle periods
- Start, Stop, and Restart controls with customer-impact confirmation when work
  is active or activity cannot be verified
- Model catalog management with separate Download, Delete, Enable, and Preload
  actions
- Live application of a saved model selection through the CLI's graceful
  same-session `switch` command when fresh runtime evidence says it is safe
- Models organized into collapsible Enabled and Available groups, with search,
  expandable details, and a separate Provider capacity section
- Independent daily-runtime what-if sliders with estimates from observed data;
  they do not schedule or change provider runtime. Earnings inputs are account-level
  and assume this Mac produced the recorded work for that model
- A whole-Mac GPU utilization ring in the menu bar, with fresh temperature coloring
- Concurrency selections from 1–24 and resident-model limits staged together with model selections
- Clear saved-state labels for idle-memory, beta, and electricity settings
- Starting/Restarting progress that blocks repeated clicks until fresh telemetry arrives
- Signed automatic and manual Control updates, a separate CLI update notice,
  and an explicit automatic CLI-update setting
- Native graceful Stop pauses new work, drains accepted requests, and reports exact requests remaining
- Provider resources include a system-wide GPU-use gauge and an honest running/draining request count
- Opportunity cards with readable names, RAM checks, demand badges, and workload counts
- Separate network-history charts with technical details available on demand
- Saved versus advertised model selection, with an explicit restart warning when they differ
- Model hardware/runtime requirements, quantization, and context/output limits
- GPU temperature and fan readings plus opt-in control through the official
  Darkbloom fan helper, with bounded policy values and macOS administrator approval
- Provider resources with measured Mac-wide CPU utilization and reported GPU
  active/cache memory; GPU engine utilization is not exposed by the provider
- Idle-memory policy and advanced beta settings, with explicit restart-required feedback
- Fresh verification diagnostics for legacy and App Attest authorization
- Network maintenance and aggregate cache-health reporting
- One resizable dashboard and Settings window
- System, Light, and Dark appearance choices; System follows macOS changes
- Evidence-backed local alerts, capped alert history, and a preview-first
  allowlist-only support packet
- Explainable observe-only model recommendations with local replay history
- Optional automatic nudge after 15, 30, or 60 minutes of observed idle time:
  a tiny self-route request to your own warm model, with a dedicated Keychain
  credential, fresh base-reward-only evidence, and strict attempt limits
- Optional automatic profit switching among already downloaded compatible
  models: a sustained estimated next-hour net advantage of at least 30% and
  $0.05 after loading, with configurable timing, fresh evidence, idle checks,
  and a maximum of three attempts per 24 hours
- Built-in Chat with an explicit per-conversation destination — the local
  endpoint on this Mac (default) or the paid Darkbloom network — a separate
  resizable chat window sharing the same conversation, verified-model
  pickers, per-response route provenance, and a fail-closed paid gate
  (consumer API key, fresh balance above zero, verified pricing, 402
  honored as the network's final decision with no retry)
- Qwen, OpenAI/GPT-OSS and Google/Gemma menu-bar icons during observed activity
- Opt-in estimated adapter power, a saved USD/kWh electricity rate, and earnings
  after electricity for matching measurement periods

During inference, the status item shows the model's daily rate labeled `avg`, or
`Working` when no average exists. These are not realtime measurements. The popup
also labels this working/average fallback. Earnings remain the idle fallback.
Unavailable values are omitted or shown with a compact
neutral state; the monitor does not manufacture values from unrelated counters.

## Screenshots

Settings from an earlier local review build. Values vary by provider.

![Electricity and menu-bar settings](docs/screenshots/settings.png)

## Requirements

- macOS 14 or newer
- Apple Silicon for the downloadable build; Swift 6 through Xcode for source builds
- The official, unmodified Darkbloom CLI for provider data and controls
- `darkbloom login` for authenticated earnings

The telemetry and command contracts cover Darkbloom 0.8.15 through 0.9.11,
with optional fields and source failures handled independently. The monitor remains usable when Darkbloom is missing or stopped, but
affected live values and actions will be unavailable.

## Build and run

```bash
git clone https://github.com/knightfolk/Bloomy.git
cd Bloomy
swift test
swift run DarkbloomMonitor
```

For a release build:

```bash
swift build -c release
./.build/release/DarkbloomMonitor
```

You can also open `Package.swift` in Xcode and run the `DarkbloomMonitor`
scheme. The app appears only in the menu bar and intentionally has no Dock icon
by default. Use the gear in its popup to access the resizable Settings window.
The Swift package target, executable and resource bundle are still named
`DarkbloomMonitor`. The old local checkout folder
`DarkbloomCLIMenuBarMonitor` may also stay as it is; neither name determines
the user-facing app name or the GitHub repository URL.

Each launch claims one user-scoped kernel lock before creating a status item.
A duplicate build using this same lock exits only the new process and does not
terminate the lock owner. Older builds predating this guard may still run beside
it. Rebuilding also does not replace an already-running process, even when its
executable path matches. See [the safe review-launch procedure](docs/REVIEW_LAUNCH.md).

## What it reads and stores

The monitor reads bounded local telemetry from:

- `~/.darkbloom/daemon-state.json`
- `~/.darkbloom/loaded-models.json`
- a bounded tail of `~/.darkbloom/provider.log`
- the local unified log for Darkbloom lifecycle, warning, and error events
- `darkbloom status`
- macOS thermal state
- authenticated Darkbloom account earnings and the public earnings leaderboard
- the public per-model network-capacity endpoint

The monitor does not use custom provider-control endpoints or require a patched
CLI. Model configuration changes take effect through the official CLI lifecycle.

It stores compact, user-only SQLite histories under:

```text
~/Library/Application Support/Darkbloom Monitor/
```

Those databases contain hourly earnings aggregates, changed balance samples,
observed uptime, and measured model token rates. They do not store the auth
token, account ID, provider key, prompts, responses, or per-job content.
Chat conversations are equally off-disk: the built-in Chat destination and
its pop-out window keep the transcript in memory only, discard it on quit,
and never write prompts or replies to any store. The Darkbloom consumer API
key used by network Chat and the free post-switch self-test lives only in the
macOS Keychain — never in preferences, files, or logs — and is separate from
both the provider device token and the local endpoint token. Automatic nudge
uses its own separate Keychain credential.

Historical throughput is derived from positive token/time deltas belonging to
the same provider process and model. These completion counters are not a live
streaming rate. Calendar earnings include both inference
work and rewards. When retained data does not cover the entire current week,
the popup says **Observed this week** instead of presenting a partial value as a
complete weekly total.

## Provider controls and safety

Download, Delete, Enable and Preload are separate operations. Saved model
selection is passed explicitly at startup to bypass the CLI picker. App Restart also
applies the saved selection; it can differ from the models the daemon currently
advertises. The comparison is shown separately from loaded models and unsaved edits. Saving
configuration does not silently restart the provider. With Darkbloom 0.9.10 or
newer, **Apply Live** can gracefully drain accepted requests and replace the
advertised model selection on the existing coordinator session. Timeouts leave
the provider draining and do not force-cancel work.

The popup's **Use only this model** action follows a confirmed switch with one
small self-route completion (eight output tokens maximum) when a consumer API
key is saved in Chat. This is an emergency warm-up for a CLI switch that leaves
the new model unloaded. It is free and cannot fall back to paid network routing.
The popup reports a skipped or failed test without undoing a successful model
switch. A successful self-test proves that an owned machine responded; it does
not guarantee public scheduler traffic. No test is sent when the switch outcome
or fresh advertised selection cannot be confirmed.

**Automatic nudge** is separate from that one-time post-switch test. With an
explicitly saved, “my machine only” consumer key, it can send a request capped
at eight output tokens after 15 minutes of observed idle time by default. It
requires fresh account evidence of base rewards without work, pauses for busy
or uncertain state, waits at least an hour between attempts, and allows at most
three attempts in 24 hours. It runs only while Bloomy is open and has no paid
fallback. See [automatic nudge](docs/INACTIVITY_NUDGE.md).

**Models → Provider capacity** lets you save a concurrency limit from 1–24
and choose how many models the provider may keep in memory. Darkbloom CLI 0.9.7
currently caps effective concurrency at 8 per model engine, even when a higher
value is saved. The CLI 0.9.7 defaults are
4 requests and 3 resident models. Existing per-model concurrency overrides are
preserved and may differ from the global setting. Actual capacity depends on memory.
Changes remain staged until **Save Changes**; **Refresh** preserves edits and
**Discard edits** reloads saved values. These settings use the official provider
configuration. Manual live warming and load-first replacement are not supported.
The separate opt-in profit switch uses the CLI's graceful switch only after
fresh evidence and an idle single-model state; see
[automatic profit switching](docs/PROFIT_SWITCHING.md).

Stop and Restart require a customer-impact confirmation when work is active or
activity is unknown. Stop uses the CLI's native graceful drain: it pauses new
requests, completes accepted work, confirms usage, and then stops. The app waits
up to ten minutes for the CLI drain; if work remains, the provider stays paused
and draining, and the exact remaining count is shown so Stop can continue it.
No force-cancel or uninstall option is used. Restart may interrupt work.
Delete requires fresh residency evidence. Quitting the monitor stops its own
work, not the provider.

Provider resources show a best-effort whole-Mac GPU utilization reading when
macOS exposes it; it includes other apps and is not attributed to Darkbloom.
During normal serving, the request indicator shows `1+` when inference is active
because the daemon reports activity but not an exact live count. During native
drain, it shows the exact accepted requests remaining.

Idle-memory and beta controls use official CLI commands and require a restart to
apply. They share the model/lifecycle action gate and cannot overwrite a staged
model draft. Automatic CLI updates use `darkbloom autoupdate` and apply when the
provider next starts.

Fan controls use only the official experimental CLI helper. Enable/configure are
limited to the CLI's 60–90% target and a validated temperature threshold; every
mutation displays a macOS administrator prompt. Disable and Uninstall restore
macOS automatic control. No custom fan curve, setuid executable, stored password,
or wildcard privileged helper is added. The authorization bridge refuses
`PATH`-discovered binaries and verifies the canonical provider executable's
Darkbloom Developer ID before running it. Verification guidance never removes
enrollment.

After saving model configuration, use **Apply Live** when fresh Darkbloom 0.9.11
state confirms that the graceful switch is safe. Restart remains available for
other saved provider changes. Control verifies outcomes through the CLI's public
status and state files rather than private APIs.

## Limitations

- Consult the release notes for signing and notarization status of each artifact.
- Electricity is estimated whole-Mac DC adapter input, not wall power or
  Darkbloom-only consumption. Missing readings leave gaps; only fully matched
  earnings hours contribute to earnings after electricity.
- Earnings and model-rate history begin when this monitor collects it. Partial
  weekly coverage is labeled explicitly.
- A per-model throughput breakdown appears only after at least two models have
  valid measured samples for the current local calendar day.
- CLI output and APIs may evolve after the validated 0.9.11 contract. Older CLI versions omit unsupported diagnostics.
- Chat is a first non-streaming version with cancellation; responses arrive
  as a single completion. The paid network route's balance display is
  advisory only — the network decides reservation sufficiency per request,
  and HTTP 402 is final.
- Only the official CLI is supported; do not install a custom provider branch
  to enable Bloomy features. Live streaming throughput is not available.
  Automatic profit estimates use observed account earnings and Mac activity;
  work on other devices can affect attribution, and future jobs are not
  guaranteed.
- Provider actions affect the local provider and may affect customer jobs; read
  confirmation dialogs before proceeding.

## Documentation

- [Telemetry contract](docs/TELEMETRY_CONTRACT.md)
- [Public API contract](docs/PUBLIC_API_CONTRACT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Electricity estimates and model icons](docs/ELECTRICITY_AND_MODEL_ICONS.md)
- [Presentation research](docs/PRESENTATION_OPTIONS.md)

## Development

Run the complete test suite and production build before submitting changes:

```bash
swift test
swift build -c release
```

The package targets macOS 14 and uses SwiftUI, AppKit, Swift Testing, and
SQLite3.
## Local review bundle assembly

After `swift build -c release`, assemble without launching or overwriting an
existing output (replace the absolute paths with your checkout paths):

```sh
python3 tools/package_app.py \
  --executable /absolute/checkout/.build/arm64-apple-macosx/release/DarkbloomMonitor \
  --resources /absolute/checkout/.build/arm64-apple-macosx/release/DarkbloomMonitor_DarkbloomMonitor.bundle \
  --output /absolute/checkout/.build/new-local-review \
  --sparkle-framework /absolute/checkout/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
  --version 1.1.0 --build-number 110
```

The new directory contains `Bloomy.app` and a SHA-256 file manifest.
Version/build values are labels, not release provenance. This tool does not
launch, register, install, distribution-sign, notarize, or publish the app.
The manifest is not an SBOM or reproducible-build proof. Keep live relaunch,
unsaved-settings safety, upgrade testing and distribution approval separate.

See [release signing and notarization](docs/RELEASING.md) for distribution packaging.

## Upgrade from Darkbloom Control or Darkbloom Monitor

Built-in updates preserve the installed app folder name while showing Bloomy
inside the app. After quitting, you may rename that folder to `Bloomy.app`.
For a manual upgrade, replace the old app with the downloaded `Bloomy.app`.
Quit the old app before opening Bloomy. Quitting the app
does not stop the official provider CLI. Keep only one installed app copy in
your chosen Applications folder; remove an old login item if you had configured
one, then use only the Bloomy app for future launches.

The bundle identifier, internal executable/resource names, settings keys,
history folder (`Library/Application Support/Darkbloom Monitor`), and
single-instance lock are intentionally unchanged. Existing settings and
history carry over without a migration. Swift package commands still use the
internal `DarkbloomMonitor` target name. The update feed and Sparkle public-key
identity remain the same so compatible signed updates can continue across the
display-name change. The Git history and old release notes retain their
original names for traceability.

See [Branding](docs/BRANDING.md) for editable icon sources and packaging details.

## App updates

v1.0 users need to download v1.1 manually once to gain the built-in updater.

Settings includes separate controls for automatically checking for **Bloomy**
updates and automatically downloading/installing them on quit. Use
**Check for Updates…** for a manual check; Sparkle’s update window offers the
signed download and installation when a newer app release is available.
Updating Bloomy does not restart the provider. Unfinished model edits or pending
provider actions postpone an updater-requested relaunch.

The CLI update notice is separate and read-only. Bloomy can announce a newer
CLI release, but does not install it or change the CLI’s automatic-update policy.
Local review bundles without an update feed/key show updating as unavailable.
See [release preparation](docs/RELEASING.md) for the signed feed and packaging
steps required before publishing an updater-enabled release.
