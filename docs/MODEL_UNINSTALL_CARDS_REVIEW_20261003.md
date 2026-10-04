# Model uninstall on cards

Downloaded model cards expose a compact trash button with the accessible name
**Uninstall <model>**. The expanded Manage view uses an Uninstall label. The
existing model selection, startup choice and Download controls retain their
behavior. Undownloaded cards do not offer Uninstall.

The confirmation names the model, shows observed local payload bytes when
available, and identifies the reviewed effective cache directory. It explains
that cached revisions are removed too and that backups may delay free-space
recovery. Payload size is not a promise of immediately reclaimable disk space.

## Guarded removal

The UI retains the existing saved-selection, pending-edit, identity, residency
and freshness guards. It also blocks missing cache information, a target still
advertised by the running provider, unknown serving evidence, and pending
loading, switch or lifecycle work. Explicit stopped evidence is accepted only
without contradictory inference, loaded models or outstanding requests.

Confirmation captures the cache directory. The store forwards that directory
into the service's fresh removal preflight; a changed directory rejects the
operation and requires a new confirmation. Controllers that cannot implement
this check refuse cache-bound deletion. The legacy API remains compatible.

The official CLI removal command now receives the same explicit `--config`
path used for inventory reads. Duplicate local identities are marked ambiguous.
The CLI's own model writer lock remains responsible for concurrent cache
writes. A separate CLI can still change serving/configuration after preflight;
the app does not claim atomic coordination with independent processes.

## Verification

The final full `swift test` run reported 1,543 app/telemetry tests, 21 protocol
tests and 28 transport tests, with seven opt-in skips and no failures. The
Release build completed successfully in 60.06 seconds. Both processes were
joined to exit 0. Regression cases include advertised cold models, unknown
serving sets, contradictory stopped evidence, duplicate identities, explicit
configuration and cache A-to-B changes with command dispatch suppressed.
An independent read-only review found no remaining actionable issues in the
two initially identified cache/stop-state gaps.

Native review used production `ModelManagerView` and `ProviderControlStore` in
an isolated app with a synthetic controller and a uniquely owned temporary
sentinel. No real provider command, model removal, download or inference was
performed. The production app and provider remained running.

- The 900-point dark view shows a direct trash control on downloaded cards,
  a disabled control on the resident model, and Download on missing models.
- Cancel preserves the sentinel and leaves the uninstall call count at zero.
- A simulated writer-busy attempt increments the count to one, keeps the file
  and card downloaded, and exposes an error in the Models footer.
- Clearing the simulation and retrying increments the count to two, removes
  only the sentinel, and changes the model to Not downloaded with Download and
  Details controls. The resident model remains protected.
- A second fixture constrains the production Models content to 650 points.
  Light and dark captures show unclipped selection, startup, trash and Manage
  controls. Its trash action opens the same confirmation; Cancel again leaves
  zero calls and the sentinel intact. This proves content at the constrained
  width, not an OS window-resize lifecycle.

Native alert accessibility exposes the expected size, cache location and
Cancel/Uninstall actions, and actual clicks exercise both actions. The alert
pixel capture is blank, matching the already documented independent AppKit and
SwiftUI reference symptom. Alert pixel appearance and spoken VoiceOver remain
unverified; this review does not claim accepted alert pixels.

## Reproduction and delivery boundary

Run `swift test` to refresh `.build/out/Products/Debug`, then:

```sh
python3 Tests/NativeUI/build-model-uninstall-fixture.py
```

The builder refuses stale telemetry symbols and existing output, stages
production sources, and records source/archive/binary hashes in its manifest.
Use a fresh `--output` and distinct `--bundle-id` for another simultaneous
review. Its toggles exercise busy-cache handling, constrained content width and
appearance without changing macOS preferences.

Retained review outputs are `.build/model-uninstall-review-20261003` and
`.build/model-uninstall-review-20261003-r2`. All 101 staged production source
hashes match the checkout in both manifests. Their binary SHA-256 values are
`edeaf29178d52e274514ef05584927778fa8a7a71305682d1bd80f7e5855f95f` and
`58f08764aaa622cbe818b972743b36f58435e117607f616db2c88050334fe3d1`.
This is a source checkpoint and
isolated native proof, not a notarized distribution or an installed-app update.
The existing menu-bar motion release gate and broader optimization/native
matrix remain open.
