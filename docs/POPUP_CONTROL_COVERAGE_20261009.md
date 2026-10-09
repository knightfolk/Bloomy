# Popup control coverage — October 9

The popup is Bloomy's primary control center. Frequent actions belong in its
icon-first common bar or model rows; less frequent actions open a compact panel
from More. Operational controls should not require opening the dashboard.

The optimized synthetic review built from `30c00b2` exposes Hosting, provider
Start/Stop, Autopilot, Auto, Nudge, energy and cooling from the common bar.
More exposes Manage models, Hosting, Provider, GPU protection, Energy &
electricity, Cooling, Inactivity nudge, Profit switching, Health & Logs,
Appearance, Menu Bar, Updates and Support, plus Chat and the dashboard.

Computer use verified the More menu, the Provider panel and its Done return,
then Manage models and its Done return. Provider exposes restart, Autopilot
opt-in/refresh, idle memory policy, experimental features and the protection,
switching and nudge settings. Manage models exposes enable/preload selection,
guarded uninstall, details, collapsible groups and capacity, with Refresh,
Save Changes and Apply Live. No mutation, model deletion, inference or network
nudge was performed. Disabled fixture operations are not proof of live actions.

Evidence is `.build/metrics-current-native-review-20261009/popup-controls.png`.
The isolated app is on Sol under
`/Volumes/Sol/BloomyReview/metrics-current-native-review-20261009/native-fixture`.
All 142 staged source hashes match the checkout; deep strict signature
verification passes. Its binary SHA-256 is
`e6078d687128e2286067cf7436f484a66a0fcd456a87c61006d57cd210efe659`.
This is a review build, not an installed update or distribution artifact.

## Metrics qualification preparation

The read-phase checker now recognizes the current 1/2/8/12/24-hour scopes,
retaining the earlier 7/30-day proof scopes. Thirteen Python regressions pass;
they still reject invalid scopes, a scope change during measurement, failed,
empty, cancelled or unfinished reads and cache/retention changes. Independent
read-only review found no actionable issue. Forty-five focused Swift Metrics
checks and 49 native-fixture staging checks pass.

A fresh, closed 100,000-record synthetic journal was seeded on Sol and bundled
into the review. Seed SHA-256:
`e52d005cab3d024296ab7e2b7dc33a97c6b1d0bed40791bb77258c8190b620d5`.
No new accepted CPU/memory profile or full native Metrics-period audit is
claimed here. The strict row-count guard requires care for rolling windows
whose oldest observations age out naturally; it has not been relaxed.
Existing production state and unrelated local changes remain preserved.
