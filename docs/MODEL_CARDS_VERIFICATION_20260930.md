# Compact Models cards verification

The Models page shares the popup card component for model identity, residency, and metrics. It adds a dedicated network-demand row and keeps forecasts in the existing Manage/Details view. Hosting controls continue to stage selection and startup-loading settings.

Synthetic native SwiftUI renders were inspected at 300- and 400-point card widths and 640-, 1280-, and 1480-point page widths. Cards remain aligned, demand counts and actions remain readable, and the page uses one, two, or three bounded columns. An independent design review found no rendering defects.

A regression test checks current demand, unavailable model data, retained readings after a failed source refresh, expiration, and future timestamps. The full Swift test suite passed. Live app navigation confirmed the existing saved selection has no pending edits before preparing the update.

These checks do not claim an instantaneous demand stream: the page displays the latest polled network reading and its age.
