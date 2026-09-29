# Darkbloom Control design direction

Darkbloom Control makes a command-line provider approachable for the everyday 80 percent of Mac users. Build a friendly, consistent native SwiftUI interface that explains outcomes rather than exposing CLI machinery.

The menu-bar popup is the heart of the app. Put frequent actions and useful readings there, with dense but readable layouts, familiar icons, restrained text, and progressive disclosure for advanced settings. Model cards use three columns in the popup, short names, and full names on hover. Unadvertised downloaded models offer an explicit Activate action with truthful feedback about saving versus becoming live.

When the provider is offline, keep the same information architecture and fully desaturate the popup. Show saved selections in their usual positions, clearly identify Offline and next-start state, and never imply that saved or historical data is live. Keep controls usable where their actions are valid.

Use a dedicated design-review agent to catch design misses and ensure consistent spacing, hierarchy, controls, friendly language, and light/dark appearance. The main agent owns integration and verification. Inspect rendered online, offline, empty, and unavailable states at normal scale; passing builds alone are not visual proof.

Fan controls use the official helper. Present readable temperature and fan readings, a clear entry to the helper toggle, and advanced policy controls behind disclosure. Do not invent sensor values or hide errors behind an attractive badge.
