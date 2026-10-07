# Local credit attribution boundary

Account credit history remains available, while local serving profitability,
power matching and the profit chart require a separately verified local report.
This checkpoint establishes the boundary; it does not implement the production
machine-identity resolver or complete the broader native polish goal.

## Behavior

`AccountEarningsFetching.localProviderFinancialReport` returns a typed
`LocalProviderCreditReport`; its default is unavailable. Construction is internal
to telemetry. A provider filter, matching model, single account provider or one
current connection ID does not establish historical ownership. Implementations
must validate the complete requested range and publish a financial-session
revision when attribution changes.

MonitorStore uses this capability for energy matching and measured serving
profits. Activity uses one local report for estimated profit, and one account
report for gross earnings. Context, readiness and epoch checks reject obsolete
success and errors. Unsupported production clients provide no local calibration
and do not fall back to account-wide credits. The capability introduces no
network poller. Inert unit/native fixtures explicitly opt into synthetic local
ownership; they do not prove real ownership.

Visible graphics identify account earnings and the account ledger. Profit history
shows a concise unavailable explanation when attribution is absent; the account
chart cannot survive that result as local profit. A held replacement retains the
previous chart with its original metric, scope, heading and help. The unavailable
state fills the Activity pane width in compact and wide layouts. Power guidance
preserves whole-Mac measurement scope and unknown coverage.

## Review repairs

A bounded native Codex review identified two defects in the initial change.
The requested profit metric could label retained account data as local profit;
the header/help now follow the completed report's rendered metric. Financial
invalidation also cleared store values without notifying the automatic switch
controller; it now clears that controller's copied economics and sustained lead.

Pending evaluations change generation and are cancelled. Fresh data returning
before the old inventory read finishes cannot revive its proposal. Once provider
controls own a switch transaction, financial invalidation does not cancel its
CLI child or interrupt graceful draining. The controller retains tenure and
attempt budgets, and handles the already handed-off transaction to completion.
Manual disable and app shutdown retain their existing behavior.

Regressions exercise unqualified account-only data, matching provider/model
names, typed inert acceptance, wrong accounts, held success/errors across
revocation and readiness changes, attribution removal after publication,
MonitorStore notification wiring, held proposal invalidation with early evidence
restoration, and completion of an already handed-off switch without cancellation.
Negative dispatch assertions wait for actual evaluation settlement. Fixture holds
are bounded and joined during cleanup.

## Qualification

The full Release test rerun with explicit serial
execution passed 1,750 reported tests (1,701 telemetry, 21 protocol, 28 host),
with seven existing opt-in skips. Two default-execution runs each failed the
unchanged process runner's one-second elapsed-time assertion (1.069 and 1.036
seconds), while isolated execution passed in 0.325 seconds. Child reaping and
timeout-result checks passed; the scheduling-sensitive elapsed assertion is
not waived. Logs are under `.build/local-credit-attribution-handoff-*.log` and
`.build/local-credit-attribution-process-runner-isolated-20261007.log`.
The production Release build and all 32 native-staging checks pass. The final
optimized isolated app is
`.build/local-credit-attribution-handoff-native-review-20261007/Bloomy Dashboard Fixture.app`.
All 125 source hashes match the checkout. Its fixture manifest SHA-256 is
`58e4960d6d90e77df83e6e9329b33c390e4a985c56b1f728f2d701874c656ade`;
the executable SHA-256 is
`60eee795c49f4a2d4fc3b87eba4a00ed28208926f0b4ddb6bf4e888f11a2522a`.
The manifest was initially looked up under the wrong filename; the builder's
actual `fixture-manifest.json` was subsequently inspected and verified.

Native inspection of that sole final app covers wide light and 800-by-560 dark
unavailable states, explicit synthetic attribution acceptance, signed profit
above/below zero, attribution removal, and recovery of gross account history.
A held local-profit replacement retains the account chart's original heading,
completed scope, gross summary and help. On release the local chart appears;
removing attribution clears it again. Popup account summaries recover after an
explicit inert summary refresh without reviving local model calibration. Its
energy help preserves whole-Mac adapter scope and requires verified local
income. The fixture's saved-power issue overrides the default waiting caption;
it is not evidence of a real power reading or live financial association.

The final read export records seven started and seven completed reads, no held
read, a ready synthetic A ledger and `localProviderAttributed: false`. Retained
evidence is `.build/local-credit-attribution-handoff-read-proof-20261007.json`.
The ordinary native gate is terminal: Models and Charts pass; motion remains
12/15. The same failures are `opaque_cover_occlusion_and_restore`,
`same_window_close_and_reopen` and `rapid_same_window_close_and_reopen`.
No failure is waived. Results are retained as
`.build/local-credit-attribution-handoff-native-proof-result-20261007.json` and
`.build/local-credit-attribution-handoff-motion-lifecycle-proof-20261007.json`.

The task-owned app exited through normal Quit; no review/cover or Darkbloom
provider process remains. Provider configuration SHA-256 is unchanged at
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
The unrelated dirty motion-proof source is unchanged and excluded from staging,
at `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
The installed production app was not replaced. This narrow qualification does
not establish a release or completion of the broader polish objective.

## Remaining work

The installed official CLI reports 0.9.17. The earlier identity audit found no
coordinator provider UUID in the exposed daemon fields; historical upstream
generated connection IDs that change on reconnect. A current verified contract
and durable account/coordinator/history association are required before enabling
production local financial reports. This checkpoint must not be described as
working machine-specific earnings or verified local profit.

Legacy disclosure, retained-history bounds, joined day replay, demand history,
broader accessibility/motion proof and distribution gates remain open. The
provider and its configuration are not changed by this work.
