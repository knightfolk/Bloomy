# Health summary heading review — October 7, 2026

Health's summary previously said **Needs attention** even when all four sources
were available and no warning, acquisition diagnostic or model-load failure
was reported. Its heading and symbol now reflect the existing evidence:

- **Reported health** with the health symbol when all sources are available
  and no issue is reported. The existing qualified message remains “No issues
  reported by current sources”; this is not a guarantee of provider health.
- **Readings incomplete** with a clock when coverage is incomplete without a
  reported issue. The existing source-freshness guidance remains visible.
- **Needs attention** with a warning triangle when a daemon warning,
  acquisition diagnostic or model-load issue is reported.

The summary is an accessibility heading. Existing warning rules, issue counts,
disclosures, source timestamps and full diagnostic reasons are unchanged. This
adds no acquisition, timer, provider action or preference write.

## Verification

The full Release test run finished successfully: 1,600 telemetry/UI tests,
21 protocol tests and 28 host tests, **1,649 reported total**, with seven existing
opt-in skips. Log: `.build/health-summary-full-20261007.log`. This display change
does not add a test that merely repeats its labels; the native fixture adds a
distinct incomplete-read scenario to exercise the actual rendered view.

The optimized ordinary fixture built successfully with no motion, real
status-item or Settings-proof overlays. All **121** source hashes and the
executable match the saved manifest. Provenance:

- Bundle: `.build/health-summary-native-20261007/Bloomy Dashboard Fixture.app`
- Manifest: `.build/health-summary-native-20261007/fixture-manifest.json`
- Readback: `.build/health-summary-native-20261007/source-verification.json`
- Executable SHA-256:
  `ebd93c1ba134bdb6993a6adab565a0f59e0caffb6642f80081ac0b7bd5d3852a`
- Manifest SHA-256:
  `6a9abf444ea639daa4663ebb45b6fb7628813c78aff2bf1e4197b2b89a1ab808`

## Native observation

Computer Use inspected the production Health view within the inert fixture;
screenshots and accessibility trees are captured in this task's tool history.

| Scenario | Inspection | Result |
| --- | --- | --- |
| Fresh | Wide/light | Reported health; qualified no-issues text; all four named captures visible |
| Health partial | Compact/dark | Readings incomplete; three captured sources and unavailable Loaded models |
| Health partial, expanded | Compact/dark, scrolled | Complete missing-read reason reachable; no invented capture time |
| Health long mixed | Compact/light | Needs attention; stale monitor, last-known daemon warning and acquisition count retained |
| Health long missing | Wide/dark | Needs attention; all four unavailable sources and full expanded two-paragraph model diagnostic |
| Recovery to Fresh | Wide then compact/dark | Heading returns to Reported health; warning text disappears and named captures return |

The accessibility tree exposes each of the three summary labels as a heading.
Open Loaded models details persisted through scenario, appearance and size
changes until fresh data removed the missing-read disclosure. Compact scrolling
reached the reason and later provider/daemon/thermal groups. The fixture's review
banner occupies additional space; the native Health scroll view remained usable.

The owned review app (PID 90137) was quit normally and verified absent. The
provider remains stopped, its configuration hash is unchanged, and the existing
dirty motion-proof source is preserved byte-for-byte. No provider start, swap,
nudge, model download or credential change occurred.

This closes the misleading summary-heading finding. Overall application polish,
spoken VoiceOver, real source-transition behavior, large-text/display settings,
production profiling and the broader native/distribution gates remain open.
