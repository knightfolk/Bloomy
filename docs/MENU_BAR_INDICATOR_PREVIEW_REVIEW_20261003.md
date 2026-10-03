# Menu-bar indicator preview — October 3, 2026

Menu Bar settings now shows the same 72 × 18 point indicator view used by
the status item. The existing monitor, GPU and provider-extras stores supply
its readings; the preview does not start another collector or provider read.
Its existing one-shot freshness deadline is cancelled when the dashboard is
hidden, and other settings pages do not mount it.

Short icon-led explanations separate model activity, whole-Mac GPU usage and
measured fan speed. The temperature legend reads the production thresholds:
green below 70 °C, yellow from 70 to below 85 °C, red at 85 °C and above.
These are Bloomy's display cues. Missing GPU/fan readings remain dashed and
old measurements remain faded. An ordinary native disclosure holds the
longer RPM, whole-Mac and Reduce Motion explanation. The existing idle-reminder
picker retains its saved-value fallback and remains separate from nudge timing.

## Native evidence and limits

Native169 rendered compact 800 × 560 and wide 1280 × 900 content in light and
dark appearances, including the expanded explanation and reachable idle
reminder. Fresh synthetic samples showed the green 54 °C thermal rings;
expired samples retained their values with faded neutral styling and explicit
capture times in the accessibility description. The fixture banner disclosed
synthetic temperatures/fans and actual Mac identity/thermal state.

Evidence is retained at `/tmp/bloomy-menu-preview-20261003/native169/`.
The `wide-dark-expanded` filename is misleading: that capture was collapsed;
`wide-dark-about-expanded` contains the actual expanded explanation.
Native171 verified the final yellow legend wording “70 to below 85 °C” in
compact light and dark footers. All 110 production/helper source hashes match
the current source; its binary SHA-256 is
`3daf34f57516b50546250466d122e545c32239ec3eb0e5c29208380550647fac`.

Ninety screenshots over 4.921 seconds captured identical preview crops while
the dashboard was occluded. These establish a rendered stationary layout,
**not** visible animation. Native170's final diagnostics confirmed its
dashboard anchor lacked the actual compositor-visible bit.

Native169's motion windows also failed the initial visibility prerequisite.
The helper now places its own normal-level targets inside the active display
and orders them explicitly to the front. It evaluates diagnostics at timeout
rather than interpolating them before the wait. Predicates still require
actual WindowServer visibility and real compositor angle advancement.

Native170 passed the new eight-step reading-update proof: cool/hot, stale,
missing, stationary, resumed and idle readings retained the same native view
and layer, 72 × 18 fitting size and stable 18 × 18 arc geometry. Eligible
active steps advanced their presentation angles with one rotation key;
stationary and idle inputs stopped the clock while retaining truthful native
accessibility descriptions. It passed 12 of 15 motion cases overall.
Genuine cover occlusion and two close/reopen cases failed. These failures
remain required evidence; no successful full motion gate is claimed.

The Model Manager helper's old exact-one “Done” assertion conflicted with the
intentional header and footer controls. It now requires each distinct stable
identifier exactly once, checks both roles and titles, and dismisses with the
footer. Native171 and Native172 passed all three model cases and chart checks.

Native171's bounded notification trace reproduces the reopen failure with the
same visible native view/layer and all eligibility conditions satisfied. The
clock is present during the visible notification but absent at the subsequent
visibility check; rapid reopen also leaves it absent. This contradicts treating
the older session's passing reopen checks as proof of current reliable recovery.
The new trace captures only owned window metadata and removes its observers
after each case.

Native172 tried a production `viewWillDraw` recheck. The two reopen cases still
failed, so that attempted fix was removed. Its prototype and terminal reports
are retained for diagnosis, but are not the current source or a release candidate.
No required motion case was removed, weakened or marked passing. Native171 is
the exact-source native reference for this checkpoint, with 12 of 15 motion
cases passing and the combined native proof still failing.

## Checks and delivery

Final-source Swift suites report 1,579 tests with no failures (1,530 app/telemetry,
21 protocol and 28 transport; six opt-in skips). Release compilation
completed in 45.71 seconds with no compiler warnings or errors.
The passing unit/render tests do not establish the failed native motion gate.

Installed Bloomy, the provider and its recovery watcher retained their original
process identities during review. Native169 through Native172 quit normally.
No provider swap, download, inference request, credential or production setting
change was made. This work is not yet a published release; the broader native
polish, accessibility, motion, production integration and profiling goal remains
open.
