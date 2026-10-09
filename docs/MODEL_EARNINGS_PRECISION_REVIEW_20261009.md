# Consistent model earnings precision

Models, model detail panels and popup model summaries now share the existing
precision-preserving amount presentation used by Overview and Activity. A
nonzero hourly estimate such as $0.0050 no longer becomes $0.00 in model help;
$0.0250 remains intact in the compact row. Very small values retain meaningful
digits, losses retain their sign, negative zero becomes zero, and nonfinite
values remain unavailable instead of appearing as measured zero.

This only changes presentation. Account attribution, estimated-power subtraction,
forecast calculations, demand freshness and model selection are unchanged.
Callers still provide their own hourly/daily units. Historical and hypothetical
account-derived amounts remain distinguished from verified income on this Mac.

## Native evidence

Evidence is retained under `.build/model-earnings-precision-review-20261009/`.
Before sources are preserved alongside the fixture and logs. The previous
checkpoint's Models/popup images in `.build/overview-model-row-review-20261009/native/`
provide the same mixed-history baseline.

The optimized synthetic review bundle matches all 142 recorded product source
hashes and passes deep, strict review-signature verification. Computer use
inspected compact Models in light and dark at the 800-by-560 review window,
Gemma's native detail panel and the dark popup. Captures show $0.0250/h on compact
Models and popup rows, $0.0250 net per active hour in details, and $0.0050 in
Qwen's accessibility history. Missing history remains unknown and expired demand
is visibly stale. The popup's command bar and model actions remain intact.

The review uses inert dependencies and private preferences. No provider control,
model swap, inference, download or installed-app replacement was performed.
The review app was quit through its own UI and its process absence checked.
The provider configuration and protected pre-existing motion-proof source hashes
remain unchanged. At final inspection the installed app is still running; no
provider process is observed, so this review makes no claim about live service
health or delivery.

## Verification

The new focused suite checks tiny positive amounts, losses, known/negative zero,
nonfinite values, locale-specific digits/currency and subnormal values. The first
run failed eight exact-string expectations because en_US_POSIX legitimately
adds a currency space on this Mac. The ordinary US expectations now use en_US;
the product formatter was not altered to strip locale spacing. Both logs are
retained.

The next focused run passed 47 tests in four suites. The first full serial run
reported 1,849 app tests and found two existing what-if string expectations still
requiring two decimals ($11.88 and $14.40), while the product now preserves four
($11.8800 and $14.4000). Forecast calculations and qualifications matched. Those
expectations are updated, and an additional tiny daily-net regression checks
digits, daily units and the hypothetical qualifier. Final focused and full
The final focused run passes 71 tests in five suites, including the daily-forecast
regressions. The final serial Release run reports 1,850 app tests in 232 suites
(seven existing opt-in skips), plus 21 protocol and 28 host tests, with exit zero.
An intermediate test compilation read the new forecast case before its missing
telemetry import was added. That failed log is retained; the final compilation
runs against the finished source with the import present.
All finite test/build jobs finished. The 49 native fixture-staging checks pass.
Independent read-only source review
found no actionable regression and confirmed callers keep their units and
attribution qualifiers.

## Remaining gates

This is a local formatting checkpoint. Native genuine occlusion, dialog-pixel
qualification, broad VoiceOver/larger-text proof, comparable whole-app resource
measurements and distribution checks remain open. No push, release or installed
replacement is claimed.
