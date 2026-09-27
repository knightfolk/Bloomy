# Darkbloom CLI 0.9.10 and Companion Control Contract

## Scope

Darkbloom Control and its iOS companion must control the provider without
interrupting accepted work, losing lifecycle authority, exposing host secrets,
or mistaking an expected scheduled-idle process for a failed launch.

The macOS app is the single host coordinator. The iOS app communicates with
that coordinator over an authenticated paired channel; it never reads provider
credentials or invokes the provider directly. User-managed Tailscale is the v1
remote transport. Embedded Tailscale remains an evaluated future option.

## Provider lifecycle contract

- Start, stop, restart, update, and model switching use the CLI's native drain
  protocol. A caller must allow the requested drain deadline plus shutdown and
  startup confirmation time.
- Timing out the caller must not leave automatic recovery disabled without a
  visible, recoverable outcome.
- A newly launched provider waiting outside its configured availability window
  is a successful scheduled-idle launch when its process identity is fresh.
- A stale PID file whose PID belongs to another process never blocks startup and
  never authorizes signalling that process.
- Standalone startup publishes process-bound lifecycle control before model
  preload so `darkbloom stop` can cancel startup before the listener binds.

## Model control contract

- Live switching is offered only when fresh daemon state advertises the required
  runtime capability and process-bound switch metadata.
- Live switching uses the effective configured model-cache directory on every
  selection path.
- Saving a model selection and applying it to a running provider remain distinct
  actions. Older providers retain the save-and-restart path.
- The UI distinguishes startup preload, loaded, on-demand, switch validation,
  draining, switching, success, busy, timeout, forced, and failure states.

## State compatibility

- Schema 1 fields documented as optional remain optional to readers. Missing
  trust, capacity, slots, startup preload, switch, configuration, or capability
  data does not invalidate process identity and lifecycle data that is present.
- Unknown future lifecycle outcomes remain bounded and visible as unknown.
- Cache location is initially read-only in Control. Mutation remains in the CLI
  until cache selection and live switching share one verified path.

## Companion security and control

- Pairing uses a QR bootstrap and mutually authenticated device identities,
  without a shared password.
- Host credentials, provider bearer tokens, and signing private keys never leave
  their originating device.
- Commands are typed, size-bounded, revision-checked, auditable, and require a
  fresh authenticated session. Destructive or privilege-expanding settings are
  excluded from the first release.
- The first release supports host/provider status, models, performance,
  earnings, safe settings changes, provider start/stop/restart/switch, and Mac
  app quit/reopen through a background helper.
- The UI remains marked Coming Soon until simulator and Mac-host integration
  prove pairing, reconnect, command authorization, lifecycle recovery, and
  settings conflict handling.

## Release gate

Completion requires focused regression tests, full macOS tests, a macOS release
build, iOS simulator build/tests, real rendered simulator inspection, and a
paired Mac/simulator smoke test. Publishing, pushing, or deploying remains a
separate action.
