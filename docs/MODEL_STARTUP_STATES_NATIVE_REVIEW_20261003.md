# Models startup states and scroll recovery — October 3, 2026

This checkpoint fixes misleading startup choices and two visible scroll failures
in the existing SwiftUI Models screen. It is source and isolated native evidence;
the installed production app was neither replaced nor relaunched.

## Behavior

- Zero preloads show **No preference**; multiple preloads show **Multiple startup
  models**. The typed native picker distinguishes these states without inventing
  a model ID. The multiple-selection placeholder is disabled, and its action
  cannot stage a change. Choosing a real model or explicitly clearing remains
  possible. Mounting the picker does not normalize saved aliases.
- Startup options include only uniquely resolved, downloaded models without an
  inventory issue, matching the existing action guards. An unavailable saved
  preference is retained until an explicit clear. Missing downloads and ambiguous
  aliases no longer appear as choices whose action silently does nothing.
- Startup loading off is stated explicitly. Changing a saved preference does not
  turn that policy on. A missing startup-loading flag uses qualified default-policy
  wording instead of promising a load.
- Empty catalog, unavailable catalog and unmatched search have distinct messages.
  Searches and transitions to empty content reveal the start of the list; normal
  refreshes preserve its position.
- The few section containers use `VStack` so their bounds are available before a
  long scroll. Model cards remain in `LazyVGrid`. No timer, service read, provider
  action or history-sized state was introduced by this layout repair.

## Native comparisons

Review content sizes were 800 × 560 and 1280 × 900, plus native window chrome.
Every provider/configuration client was synthetic. UI input and screenshots used
CUA against the named fixture bundles.

| Candidate | Observed evidence |
| --- | --- |
| Native145 baseline | With two preloads and one staged memory slot, the picker visibly said No preference while the adjacent warning said multiple startup models. |
| Native146 | Harness compilation failed because its earnings switch lacked the six new scenario cases. It was never launched; the switch was corrected. |
| Native147 | Compact light multiple preference, explicit GPT-OSS choice/Save, reload/Clear/Save; wide dark loading off and Gemma choice/Save; wide dark missing download and compact dark ambiguous alias recovery. Clearing the missing preference offered only Gemma and GPT-OSS. Clearing/saving the ambiguous alias removed its catalog notice. Empty catalog copy was correct, but an old scroll offset could leave the panel blank until scrolling. |
| Native148 | Stable scroll target repaired deep full→empty and unmatched-search transitions. Clearing search restored the first model; an ordinary Refresh retained the final-card position. Unavailable catalog had its own visible explanation and Refresh. A six-page scroll immediately after fresh launch still yielded a blank area, so this was not accepted as the final scrolling layout. |
| Native149 final | The same fresh-launch six-page scroll reached the last Qwen card and Capacity footer immediately. Refresh retained position; deep full→empty displayed the explanation with scroll value zero and no manual recovery. Compact dark multiple-preload controls and warning remained readable; wide light loading-off controls, explanatory text and footer fit. Normal Quit left no review process. |

Native147's saved-state proof was copied before subsequent scenarios overwrote
its fixture file. These are controller readbacks after inert Save, **not pending
editor-draft snapshots**:

| Action | Saved preload | Enabled models | Startup loading | Save / lifecycle calls |
| --- | --- | --- | --- | --- |
| Multiple → GPT-OSS | `gpt-oss-20b` | Original three exact IDs | On | 1 / 0 |
| Multiple → Clear | Empty | Original three exact IDs | On | 1 / 0 |
| Loading off → Gemma | `gemma-4-26b-qat-4bit` | Original three exact IDs | Off | 1 / 0 |
| Ambiguous alias → Clear | Empty | Original three exact IDs | On | 1 / 0 |

Native147 and Native148 are intermediate evidence, not exact final-source
artifacts. Their startup logic is unchanged in Native149; the later source change
is the bounded section layout. The final Native149 manifest checks all 107 source
hashes, the binary and copied telemetry library against current source/build
bytes, with no mismatches. Its binary SHA-256 is
`eee2597f664995e0345b73791e6fd2944919edf3c85344943775b28dd03ca4b4`.

Local manifests and saved-state JSON are retained at
`/tmp/bloomy-model-state-review-20261003/`. Native149 is at
`.build/native-dashboard-fixture-20261003-149/Bloomy Dashboard Fixture.app`.
The Native147 session directory ends `43018455-5A49-4AE2-8C14-9C009E6A4BDD`;
Native149 ends `4402370F-1285-4F9D-9B49-8116BBC21222`.

## Verification and boundaries

The startup suite checks typed empty/multiple/single states, placeholder no-op,
explicit choice/clear, exclusion of issue-bearing and undownloaded options,
retained originals/enabled selectors, independent aliases and captured callbacks
against refreshed identity or later edits. A read-only native worker review found
no correctness or alias/callback regression in that change or the scroll-target
repair; it did not perform the native review or inspect the later VStack change.

The final full suite passed 1,544 reported tests: 1,495 app tests, 21 protocol
and 28 host tests. Seven opt-in tests were skipped. Final Release compilation
passed in 49.21 seconds. Logs are
`/tmp/bloomy-model-state-final3-tests-20261003.log` and
`/tmp/bloomy-model-state-final3-release-20261003.log`. `git diff --check` passes.

The installed production process remained PID 61760 with its October 2 12:55:28
start time and unchanged binary hash. Read-only CLI status still reported provider
PID 63387, shadow Autopilot, Qwen 3.8 warm and 59 served requests. No live provider
lifecycle, swap, download, inference or credential action was requested for proof.

This does not establish a hard allocation/RSS limit or whole-app energy savings.
The large-catalog cold-scroll case, repeated/system-driven inventory transitions,
actual VoiceOver, the nil startup-policy rendering branch, native alias callback
reassignment, full Manage states and other display sizes remain open. The native
menu capture did not separately establish its disabled-item appearance; the
source modifier and no-op regression establish the placeholder's action guard.
No distribution/updater or full-polish completion claim follows from this review.
