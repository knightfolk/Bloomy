# Production status-item host diagnostic — October 7, 2026

The actual `StatusItemController` passes five bounded native lifecycle cases
with synthetic inputs. This changes the next investigation: check the real
Settings preview through navigation and reopening, rather than repairing
observers or retrying cancelled animations in the manually retained window.
It does not fix or replace the failing fifteen-case native motion gate.

## Scope and isolation

The new fixture mode is opt-in:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Tests/NativeUI/build-dashboard-fixture.py \
  --configuration release --production-status-item-proof \
  --output .build/production-status-item-host-runtime-20261007
```

The normal fixture's custom status item is omitted. A dedicated MonitorStore,
never started and independent of the dashboard's five-second publications,
uses synthetic telemetry/earnings, nil provider extras, nil optional control,
hosting and chat stores, inert GPU/power readers and isolated preferences.
The production controller creates its actual NSStatusItem, hosting view,
SwiftUI label and popover. The only staged controller addition is a guarded
read-only accessor to its own button. Arc lookup stays beneath that button.
No production Source file was edited.

Each invocation has a new UUID output directory. The original **Native proof**
button and fifteen case bodies remain unchanged. This mode rejects the prior
target-lifetime/trace overlays and hidden review controls. No provider process,
model download, nudge, inference or production preference mutation was used.

## Observed results

CUA launched the exact optimized app and invoked **Status-item proof**. PID
74095 owned the fixture. Its completed report passes all five cases:

| Case | Verified observation |
| --- | --- |
| Actual host baseline | Mounted production native arc, AppKit-visible status-bar host, one advancing rotation clock. |
| Ten fresh publications | Separate run-loop opportunities; native identity and geometry retained, one clock. |
| Active → idle → active | Idle input hides the arc and removes its clock; fresh activity restores advancing rotation. |
| Production popup open/close | Actual showPopover/performClose, visibility state transitions, retained status-item identities and motion. |
| Invalidate/release/recreate | Old controller released and old clock stopped; new button/view/layer identities and advancing replacement clock. |

Nine compositor-only holds last 1.705–1.785 seconds, longer than the production
1.4-second rotation. Angles advance by 0.188–0.194 radians after the holds.
Exactly one `inferenceRotation` key remains, with the production key path,
duration and infinite repeat count. The holds call no forced display, layout,
transaction flush, configuration or animation recovery. Source age at the
end of these observations stays below 2.36 seconds, within the ten-second
activity rule. Identity, path bounds, stroke geometry and source checks run
alongside the angle observations.

The host class is `NSStatusBarWindow`. Visibility here is the AppKit-reported
visible/occlusion state plus live layer presentation angles. Its reported
`isOnActiveSpace` is false and its window number is 64424509440; these are
recorded without treating them as ordinary CGWindowList window identity or
independently established WindowServer coverage. This is bounded native host
evidence, not physical pixel acceptance on every display or a genuine cover
occlusion result.

CUA then observed **Status-item proof passed** in the dashboard. A second
invocation retained the first report and created a separate UUID directory.
After a fresh running progress report and live PID check, the normal Quit
action cancelled the proof during the production popover case. Its terminal
result is `cancelled`, `passed:false`; remaining cases stay explicitly
cancelled. Both normal and cancelled runs verify all owned clocks stopped and
all created status items invalidated. Normal cleanup is 2/2; cancelled cleanup
is 1/1. A bounded cleanup task is joined even after parent cancellation; matching
creation/invalidation counts alone cannot pass the report. PID 74095 was absent
after Quit, and no post-Quit AX read relaunched it.

## Provenance and checks

Artifact root: `.build/production-status-item-host-runtime-20261007`.

- Binary SHA-256: `bef47cb09074c8916e0111cd80df80b9f03cdd3e5382a2cac1b82c4799bf023e`.
- Completed report: `runtime-evidence/1E8CB8AD-3BCA-4923-AD6A-3AE92D2F1343/status-item-host-result.json`, SHA-256 `1a96fc96451b0e1973bcc64c3abda8af892dc53ec3142966a4e5e50c01a3b477`.
- Cancelled report: `runtime-evidence/F63D8B43-308F-429D-B9AB-2CF9372F5009/status-item-host-result.json`, SHA-256 `60afd4c390b780bf9a57556c6d4c6086d6ede5bb9fe1b4326632f97be456305e`.
- `runtime-summary.json` indexes holds, reports and cleanup; the manifest captures all 120 original source hashes, staged accessor, compiler command and immutable telemetry library.
- Fifteen Python staging regressions pass, including exact preservation of the original controller body and rejection of drift/repeated staging.
- The final optimized opt-in fixture and the ordinary optimized fixture both compile. The ordinary control preserves the original controller and label bytes and omits the diagnostic definition; neither is a distribution build.

Early compile attempts exposed missing explicit MainActor isolation on nested
diagnostic types. Review also corrected unsettled geometry capture, coalesced
publications, repeated-output overwrites and the final cleanup success gate.
Only the final matching artifact was executed. One harmless compiler warning
remains for the intentionally weak controller-release reference.

The dirty `MenuBarMotionProof.swift` was preserved at SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Production MenuBarLabel remains at
`a71ff6af64a20393f625f4655dae2fecda365a46091c39e87a477866822bb22f`.
Provider configuration remains at
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The provider stayed stopped; only its pre-existing fan helper was observed.

## Remaining gate

The earlier matched manual-host callback trace still reports 12/15 versus
14/15 with fresh targets. Its genuine cover test and retained-window reopening
remain unresolved. This five-case diagnostic does not supersede those reports,
prove the Settings preview lifecycle, qualify production resource use or make
a release ready. Next, inspect that preview in the actual dashboard under
supported navigation/window actions with fresh synthetic inputs and retained
identity/clock evidence. Do not manipulate the AppKit-managed status-bar window
to imitate an ordinary proof window's close/order-out behavior.
