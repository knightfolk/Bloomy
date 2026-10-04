# Opportunity: shared model identity and request graphics

The continuing polish run found Opportunity using generic CPU symbols and
longer catalog titles than the popup and Models page. It now reuses cached
model-family marks, canonical short aliases and compact metric symbols. Full
catalog names and IDs remain in hover help and expanded details. Unknown models
retain their matching catalog name; mismatched metadata cannot supply a name.
Search includes the actual visible alias as well as existing canonical/catalog
fields.

The native Models/Network activity picker shares a top row with the page title
when it fits, with a vertical fallback. Cards show active/waiting counts above
a thin request-mix graphic; loaded providers and aggregate network throughput
remain separate below. The graphic shares only reported in-progress and waiting
requests, never providers, throughput, local work, earnings or a routing
probability. Both request counts being zero leaves an empty track even while
providers remain loaded. Invalid negative counts cannot create a filled share;
maximum integer counts cannot overflow the projection.

Stale evidence keeps Last known on the card and complete Last reported/current
unknown metric accessibility descriptions. Marks and request shares become
neutral. Missing demand retains the existing unavailable message, not zero
cards. No polling, asset download, recommendation algorithm or provider action
was added.

## Verification

- Focused check: 12 reported tests in four suites passed, including alias search,
  matching metadata, zero/invalid/maximum counts and existing retained labels.
- Final full suite: 1,560 telemetry/UI, 21 companion protocol and 28 companion
  host tests pass (1,609 reported total), with seven existing opt-in skips.
  Final Release compilation passes.
- Exact fixture: `.build/opportunity-visual-native-verified-20261003/`.
  All 113 manifest source hashes match the checkout. Executable SHA-256:
  `e4b45e5a914a0d00e4e70eed8836acef6a7ac994882b8af69b8693d5b5bb0b07`.
- Native CUA review compares the compact/wide baseline with the new header and
  cards. Final wide dark and compact light/dark marks, names, metrics and shares
  are readable. Ordinary scrolling reaches lower cards and expanded Bonsai
  details without blanking or losing the canonical identifier.
- The first light rendering kept the marks' source pixels; dark review exposed
  black marks with poor contrast. That candidate was rejected. The final view
  uses the same template rendering as popup cards, without mutating cached
  image objects. Earlier fixture/source artifacts remain as provenance.
- The new inert Quiet network scenario shows active/waiting/throughput zero,
  empty request tracks and separate loaded-provider counts of five/six. Failed
  Stale refresh preserves qualified counts, neutral graphics, unknown RAM
  admission and retained details. Offline has no zero cards and retains its
  missing-demand guidance. These scenarios alter only synthetic stores.
- Pasting the exact visible `Bonsai 2 · 27B` alias leaves only the canonical
  `ternary-bonsai-2-27b` card. Clearing search restores the list. The header's
  Network activity tab still exposes its chart, metric choices and Refresh.
- Final wide dark fresh Models view is left open. Installed Bloomy remains
  1.9.18/build 143. Provider PID 47646 remains fresh with exactly Qwen 3.8 and
  Gemma 4 advertised and Autopilot shadow. Configuration SHA-256 remains
  `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

This is a local checkpoint, without push, release or installed replacement.
No real network, inference, key, fan or provider mutation was used for native
proof. Full large-text/localization and spoken accessibility, varied long
capability/number layouts, production profiling, live integration and the
broader menu-motion/native completion matrix remain open. Unrelated dirty
menu-motion diagnostics and user files are preserved.
