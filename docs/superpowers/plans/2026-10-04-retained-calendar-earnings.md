# Retained calendar earnings

Keep valid last-read calendar totals visible with explicit historical labels.
Preserve strict current-value eligibility, day/week boundaries, missing values,
successful-empty replacement and recovery. No new poller or live API action.

- [x] Reproduce loss on failed refresh with a focused regression.
- [x] Reuse available/stale/unavailable state for day and week reads.
- [x] Validate same-period retained display separately from current eligibility.
- [x] Qualify popup and Overview values consistently with compact labels/help.
- [x] Verify failures, expiry, rollover, empties and zero-valued recovery.
- [x] Exercise the real views with inert calendar-read controls; full checks.
- [x] Record native provenance/limits and commit the verified local scope.
