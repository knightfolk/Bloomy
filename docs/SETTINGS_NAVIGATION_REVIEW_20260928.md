# Settings navigation review

The dashboard keeps one native sidebar with collapsible Monitor, Workspace,
Diagnostics, and Settings groups. Settings pages are Appearance, Menu Bar,
Electricity, Updates, Provider, Fans, iPhone Companion, and Support. Settings
selection is saved independently from the active dashboard destination.

Each Settings page stays mounted while switching between Settings pages, so
provider and fan edits survive navigation. Hidden pages cannot receive input
and are excluded from accessibility. Native sidebar buttons use a single
explicit selection highlight after a SwiftUI List selection bug was reproduced
and fixed in minimum-window captures.

## Checked

- Light and dark 800×560 screenshots of Appearance and Menu Bar, including a
  page switch with exactly one highlighted row.
- Live signed Beta: edited idle minutes from 0 to 7 without saving, switched
  pages, and confirmed 7 remained. Restored 0.
- Live signed Beta: edited fan target from 80 to 81 without saving, switched
  pages, and confirmed 81 remained. Restored 80 and cleared the temporary draft
  by leaving Settings. No provider or fan policy was saved.
- Live signed Beta: collapsed the three main groups while Settings remained
  usable. Confirmed Models showed four downloaded available models and only
  Qwen3.5-9B left to download.
- Full suite before the subsequent fan-control redesign: 865 Swift tests and
  16 packaging tests passed. The Release build passed.

The later fan-control redesign has its own focused rendering and interaction
checks; the text-field interaction proof above describes the first navigation
checkpoint, not the replacement slider controls.

## Simplified fan controls

The follow-up fan view uses the official helper's reported enabled state for its
switch, shows GPU temperature and actual/target RPM with the check time, and
keeps policy sliders/presets and helper maintenance collapsed by default. An
unknown helper enabled state is not guessed from its launchd loaded flag. Error
status is shown as Needs attention, not as successful fan ownership.

A fan-only read runs every two seconds while the fan view is selected, sharing
the store's existing refresh/mutation gate. Leaving the selected Settings page
cancels its task; hidden Settings pages do not poll. Other provider settings
retain their own values and capture timestamps. No custom helper or manual
curve support is included after the user's scope revision.

The 800×560 fan fixture was rendered and visually inspected with a helper error,
two fan readings, and an enabled toggle. Focused tests cover enabled-versus-loaded
state, the read-only fan command, and preserving unrelated settings during live
refresh. No live fan setting was applied during verification.
