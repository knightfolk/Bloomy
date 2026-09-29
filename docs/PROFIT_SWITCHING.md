# Automatic profit switching

Automatic profit switching is optional and off by default. When enabled, Bloomy may change the provider's advertised model using the existing provider control path. It does not download a model, add a paid route, or promise work or income. Manual model controls remain available. The coordinator still assigns public requests; Bloomy only changes this Mac’s advertised model through `darkbloom switch`. The native switch can drain any request that arrives between the idle check and dispatch. No restart or force-stop is used, and multi-model warm setups are left alone.

## Evidence and estimates

The candidate pool is limited to downloaded, compatible models that this Mac can serve. The watcher requires fresh provider telemetry, fresh network model demand, and a successful account-earnings fetch within 15 minutes, power readings within 30 seconds, and model serving profit estimates based on up to seven days of recorded activity. Electricity tracking and a valid electricity rate must be configured. It acts only while the provider is idle with a single advertised model and no conflicting control edit or operation.

Profit estimates use recorded account earnings by model, local model activity, and measured electricity use with a configured local electricity price. A model needs at least two active hours, two covered earning hours, and positive power samples before its estimated net rate can enter the comparison. The earnings source is account-wide, so work on another device can affect the attribution. The calculation is a heuristic calibrated to local activity, not a prediction or guarantee of future earnings. Customer-facing model prices are not inputs.

A cold candidate must also pass catalog capability/minimum-RAM checks and a live memory-headroom check: free plus inactive memory must cover 1.35 times its catalog weight size plus 4 GiB. This deliberately assumes no reclaim from evicting the current model; the CLI remains the final load authority.

The network reading indicates recent demand; it does not guarantee this Mac will receive that share of work. Missing, stale, or insufficient evidence prevents an automatic switch. Failed source refreshes make their readings unavailable to the watcher even when the UI retains the last value for historical display.

## Decision and rate limits

The watcher estimates the next hour of net earnings for the current and candidate models. It uses capped requests per warm provider as a rough utilization estimate and includes a loading allowance for the candidate. A longer measured switch duration always increases that allowance; durations over 30 minutes make the estimate ineligible. A switch needs an estimated advantage of both **30%** and **$0.05** over that hour. If the current demand estimate is zero, percentage gain is undefined and the $0.05 minimum still applies. The candidate must maintain the lead across fresh observations for the configured confirmation time. The selected model is held for the configured minimum time, and a departed model cannot be selected again until its return wait ends. At most **three attempts** may begin in any rolling 24 hours; failed attempts count toward that limit.

The timing controls are under **Settings → Provider → Switch timing**. Defaults and allowed ranges are:

| Control | Default | Range | Step |
| --- | ---: | ---: | ---: |
| Confirm better estimate | 10 min | 5–60 min | 5 min |
| Keep selected model | 60 min | 30–240 min | 15 min |
| Wait before returning | 180 min | 60–1,440 min | 30 min |
| Allow for loading | 5 min | 1–30 min | 1 min |

The return wait is always at least as long as the hold time. The hold time also governs the minimum interval between automatic attempts; changing it does not alter the three-attempt rolling daily cap. The loading control sets a floor for the estimate, and longer measured loading times take precedence.

The watcher waits whenever the provider is busy, has multiple advertised models, or is already performing a control operation. It does not make speculative downloads, repeatedly flip models, or fall back to paid inference. Its status and last attempt are shown under **Settings → Provider → Automatic profit switching**.

## Verification (2026-09-29)

The normal Swift suite passed: 882 app/telemetry tests, 21 companion protocol tests, and 28 companion host tests. Coverage includes sustained versus transient demand, duplicate observations, loading cost, configurable timing bounds/persistence, active-work suppression, memory refusal, a successful native switch fixture without warm-up inference, failed-attempt budgets, and stale account/power evidence. The native grouped Settings form was rendered and visually inspected at 700 × 700 points. Release build verification passed. All switch tests used synthetic controllers; no live provider switch or coordinator mutation was performed.
