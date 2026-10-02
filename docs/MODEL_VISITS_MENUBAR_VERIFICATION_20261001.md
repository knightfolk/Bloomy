# Bloomy 1.9.14 verification — October 1, 2026

Release source: `337bd26041f4a72f7d4b5b2d0d2b99d0934750d0`. Version **1.9.14**, build **139**.

## Behavior and UI

Activity → Metrics tracks separate visits for each observed loaded-model residence, including returns to the same model. Completed visits with fresh, unchanged request and token counters can be filtered as **Without work**, with individual durations and a combined observed time. Restart, stale, missing, multi-model and ambiguous counter evidence remains uncertain. Fresh, confirmed empty loading slots end a visit rather than bridging loading time into another model. Entire switches between observations cannot be excluded; these are observed estimates.

Computer-use inspection of the signed installed app verified Activity → Metrics, All visits/Without work, dates, consistent badges, duration totals, and the final Menu Bar settings explanation. Model-specific filtering and Show more were exercised in the preceding package with identical visit behavior. Available models collapsed and reopened; saved settings and absence of a chat draft were checked before replacement.

Native 1× render fixtures were inspected in light/dark appearance and at narrow/wide visit widths. The three menu-bar circles have fixed 72×18 content geometry inside an 80-point status item. Native compositor tests verify rotation while working, an immediate stop when idle, and static Reduce Motion behavior. Model and cooling rings reuse the existing temperature colors; unavailable values remain neutral and stale values faded. The computer-use screenshot surface captured app windows, so it did not provide a screenshot of the actual system status item.

## Tests and distribution

- **1,065 Swift tests passed**: 1,016 app/telemetry, 21 companion protocol, 28 companion host tests, on the exact release source.
- **17 packaging tests passed**; release build passed.
- Apple notarization **Accepted**: `d928969a-d02e-4948-9b88-f53980fc87f8`. Ticket stapled and validated; strict/deep signature verification and Gatekeeper assessment passed.
- Exact distribution archive: `Bloomy-1.9.14-mac-arm64.zip`, **8,866,140 bytes**.
- SHA-256: `793218810e706b5176d5865dd5adc1887bb50e2f9088f1aaa8ba1a836708c67f`.
- All four Sparkle gates passed against those exact bytes: invalid signature rejection retained build 138; immediate, deferred after test-app quit, and install/relaunch reached signed, Gatekeeper-accepted build 139.
- Updater gates preserved the production app, provider processes, provider configuration, and app preferences except Sparkle's last-check timestamp. Test app/server stopped; private preference snapshots removed.
- Final canonical installation matched the verified executable and plist, with one monitor process owning its instance lock. Fresh provider identities and configuration were unchanged across that final installation. No provider configuration, restart, swap, or nudge was requested by testing. Provider process identities did change independently earlier between the two review installations, so this is not a claim of uninterrupted provider uptime throughout all development.

Private runtime data and preference snapshots are excluded from this document and release assets. Release assets contain only the signed archive, checksum file and public artifact manifest.
