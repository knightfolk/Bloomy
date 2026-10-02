# Automatic nudge

Automatic nudge is an opt-in watcher for a provider that appears idle. It runs only while Bloomy is open. After 15 minutes by default (adjustable to 30 or 60 minutes) without observed work, it may send one tiny, exclusive self-route request through the provider's own advertised warm model, capped at 8 output tokens. It does not promise or create public jobs, and it does not restart the provider or change model configuration.

## Set up

In **Settings → Provider**, find **Automatic nudge**. Supply a Darkbloom consumer key restricted to **“my machine only”** in **Nudge setup**. Bloomy stores this as a dedicated watcher credential in the macOS Keychain, separate from provider credentials and local API tokens. The entry is masked; the saved key is never displayed. Remove it from the same section when you no longer want the watcher to use it. Choose an idle interval and turn on Automatic nudge. Disabling the toggle stops new attempts without removing the saved key.

Manual and automatic nudges use the same saved nudge key. On opening Bloomy, a background metadata check shows **Checking saved key…** until macOS responds. An unavailable Keychain status has a **Check again** action; it does not send you through setup or ask for another key. Presence establishes only that a key is saved. The request client still reads and validates it before sending.

## When an attempt is allowed

The watcher needs fresh account evidence that covers the observation interval: fetched account earnings rows must show positive base rewards and zero work rows during that interval. It also needs exactly one warm model that is advertised. Other models may stay advertised. It pauses when the provider is busy, evidence is stale or missing, a model switch is in progress, or more than one model is warm. It does not use a paid fallback.

An attempt starts a one-hour cooldown. At most three attempts can be made in a rolling 24-hour period, including failed attempts. These limits prevent a keep-alive traffic loop; they are not a schedule for guaranteed requests. The status and last-attempt time in Settings show what the watcher currently knows.

Earnings are account-wide, so work on another Mac can block an attempt on this Mac. Billing may post late; a quiet interval in fetched rows is only conservative evidence available at that moment, not proof that no work occurred. If the evidence cannot be established, the watcher waits. Public job routing remains outside Bloomy's control.

## Verification (2026-09-29)

The full normal Swift suite passed: 862 app/telemetry tests, 21 companion protocol tests, and 28 companion host tests. Packaging tests passed (17). After selecting 15 minutes as the default, all 16 focused watcher/policy/native rendering tests passed again. The exported native Settings view was visually inspected at 700 × 850 points. The release configuration builds successfully. No test sent an inference request to the live provider.

A run with global screenshot exports enabled exceeded the freshness window in an existing provider restart-confirmation test; the normal full run passed. The watcher remains opt-in and has not been enabled in the installed app by this source change.
