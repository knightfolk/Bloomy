# Native menu-ring rendering history — October 7, 2026

Removing the four early explicit display/flush observations does not change the
later failures. Both matched modes complete 12/15 motion cases in both run
orders. Cover and both reopening cases fail in all four runs; Models and Charts
pass. Early forced rendering is therefore not necessary for these failures.
No production animation change or release qualification follows from this.

## Single-factor staging

Baseline is `a660e42`. `--motion-render-history display-flush` and
`--motion-render-history compositor-only` stage identical Swift sources. The
only compiler difference after output-path normalization is
`FIXTURE_COMPOSITOR_ONLY_HISTORY`. It selects whether the four early angle
reads call `window.displayIfNeeded()` and `CATransaction.flush()`. The original
control behavior is retained in the display-flush arm.

The overlay changes those call arguments and diagnostic metadata only. Every
later case, visibility action, target lifetime, predicate, recovery observation,
hold and cleanup remains identical. It does not change the helper's default,
which would affect the later parent-label checks. Original production and dirty
motion-helper sources are untouched. Ordinary builds receive no overlay.
Reports explicitly declare diagnostic-only scope and cannot replace the normal
native gate. All aggregate failure criteria are unchanged.

Seven new regression checks include exact inverse restoration of the original
source, unchanged later cases, and rejection of missing/added reads, changed case
order or drifted fixture/report anchors. All 22 staging checks pass. Six
incompatible mode/banner combinations reject before any staging. Independent
read-only review found no material issue before runtime.

## Native results

Each run starts a fresh process and completes motion, Models and Charts before
normal Quit. No further UI actions are taken during the case sequence. Terminal
reports and visible failed-status controls were inspected before quitting.

| Order | Early observation | Motion | Same-window / rapid reopen | Models / Charts |
| --- | --- | --- | --- | --- |
| First pair, first | Display + flush | 12/15 | Fail / Fail | Pass / Pass |
| First pair, second | Compositor only | 12/15 | Fail / Fail | Pass / Pass |
| Reverse pair, first | Compositor only | 12/15 | Fail / Fail | Pass / Pass |
| Reverse pair, second | Display + flush | 12/15 | Fail / Fail | Pass / Pass |

All sixty motion cases are terminal; 48 pass and 12 fail. No cases are missing.
The same self-hide, ancestor-hide, order-out and detach cases pass in all four
runs. Cover remains a failed actual-occlusion prerequisite despite opaque
front coverage. Every owned cover reports normal parent-request exit, status 0
and a closed window. Parent/cover PIDs 4774/4791, 4847/4861, 4921/4933 and
5605/5627 are verified absent after cleanup. Post-Quit UI lookup was avoided.

Both optimized builds finish at exit 0 with 122 current source hashes, identical
staged source bytes and telemetry archive. Full package tests were not rerun for
these fixture-only changes. Production app, provider settings, credentials,
model cache and unrelated dirty files are preserved.

## Retained evidence

Outputs are `.build/render-history-display-flush-20261007` and
`.build/render-history-compositor-only-20261007`. Each retains its build manifest,
immutable staged sources, app and `runtime-evidence-first/` and
`runtime-evidence-reverse/` reports. Build logs use the matching root plus
`-build.log`. Source/command matching, incompatible flags and runtime/cleanup
summaries are `.build/render-history-{source-verification,flag-verification,runtime-summary}-20261007.json`.

Binary SHA-256:

- Display-flush: `62a9bba84e4fa13acfaee9c907613419cef7a385188d63532148ed16e28614f6`
- Compositor-only: `6c53f0c5ca579edb570f17bfa00219a23bd0e657d085656a76bc0d659079d3ab`

Shared staged motion-helper SHA-256:
`6301e290d7decf41138a47fb301969662b09b6ab238a851c4695e618336b6d00`.
Original dirty helper remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
The runtime summary retains all four motion and aggregate report hashes.

## Next discriminating evidence

The original detach case waits only for a model-layer animation key, then can
proceed directly into close. The passing independent detach pair instead
observes advancing presentation motion and holds beyond a rotation before
closing. Compare immediate detach-to-close with a compositor-observed arm;
change only that boundary and retain both reopening assertions. If observation
changes the result, a subsequent delay-only control is needed to distinguish
observing presentation from elapsed settling time.

An observed arm would intentionally change cadence and cannot qualify the
original immediate transition. Product causality requires a failure through a
supported production host with fresh inputs, continuous eligibility and stable
native identities. Passing Settings/status-item proofs do not exercise this
retained manual detach-to-immediate-close path. Genuine cover, the original
native gate and broader Apple-design/accessibility/performance proof remain
open. The continuous polish goal remains active.
