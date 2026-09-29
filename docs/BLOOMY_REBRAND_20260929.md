# Bloomy rebrand checkpoint — 2026-09-29

Base checkpoint: `20d5ce5` (Darkbloom Control v1.9.3 feed). Rebrand branch:
`codex/bloomy-rebrand`. Existing tracked work was already committed; local
`.mimosa/` and `.zcodeignore` were left untouched.

## Changes

- Bloomy display names, packaging defaults, documentation, and companion copy.
- Approved compute-gremlin concept, derived app icon, native ICNS, and simplified
  tintable SVG marks. Source hashes are in `assets/brand/bloomy-provenance.json`.
- GitHub repository renamed from `knightfolk/DarkbloomControl` to
  `knightfolk/Bloomy`; repository ID remains `R_kgDOUPtQtg`. Local origin updated.
- Official Darkbloom CLI/provider name and behavior remain unchanged.

## Compatibility

Production bundle ID `dev.darkbloom.monitor`, executable/resource target names,
Keychain identities, preferences, history directory, window identifiers,
single-instance lock, Sparkle public key and existing feed URL are preserved.
Legacy DC vectors and historical release/appcast entries remain available.

After the repository rename, both old and new raw appcast URLs returned HTTP 200
and identical bytes (SHA-256
`a6a4d5e28e65d423e46e28ef538d9d10bfc63fa9620aa33b334bee740b68c0cb`).
The old latest-release URL redirected successfully to Bloomy v1.9.3.
Do not create a new repository at the old name: existing clients still use it.

## Verification

- Full Swift tests: 893 passed (844 telemetry/UI, 21 protocol, 28 host).
- Python packaging tests: 17 passed, including production identity and legacy
  display-name override coverage.
- Release build succeeded. New bundled icon and SVG loading/tinting checked.
- Native menu-bar asset render inspected at its intended small size.
- Isolated `Bloomy Review.app` packaged with its own bundle/storage identity and
  without an update feed. Dashboard launched and visually inspected with the
  Bloomy Review title. Review app quit after inspection. Production app and
  provider were not stopped or reconfigured.
- Read-only integration review found no identity/resource regressions; its
  pending-repository-URL concern was resolved by the verified rename.

This is a local rebrand checkpoint, not a new distributed release. VERSION stays
1.9.3. No source push, merge, appcast publication, or notarized Bloomy release was
performed. A signed old-to-new installation/relaunch migration and iOS build/device
validation remain release checks; unchanged identities and passing tests alone
are not proof of a complete installed upgrade.
