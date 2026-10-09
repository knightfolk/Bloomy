import copy
import unittest

from metrics_read_phase import MetricsReadPhase


def proof(**changes):
    result = dict(started=4, completed=4, failed=0, cancelled=0, empty=0,
                  cacheReleases=0, retainedSnapshotRows=100_000,
                  recentReads=[dict(intervalSeconds=2_592_000)])
    result.update(changes)
    return result


class MetricsReadPhaseTests(unittest.TestCase):
    def test_current_hour_scopes_and_legacy_history_scopes_qualify(self):
        for seconds in (3_600, 7_200, 28_800, 43_200, 86_400, 604_800, 2_592_000):
            with self.subTest(seconds=seconds):
                before = proof(recentReads=[dict(intervalSeconds=seconds)])
                guard = MetricsReadPhase(before, "refresh")
                guard.observe(proof(started=5, completed=5,
                                    recentReads=[dict(intervalSeconds=seconds)]))
                result = guard.finish()
                self.assertEqual(result["completedDelta"], 1)
                self.assertEqual(result["after"]["periodSeconds"], seconds)

    def test_changed_short_scope_and_unrecognized_hours_are_rejected(self):
        before = proof(recentReads=[dict(intervalSeconds=3_600)])
        with self.assertRaisesRegex(ValueError, "scope, cache"):
            MetricsReadPhase(before, "refresh").observe(
                proof(recentReads=[dict(intervalSeconds=7_200)]))
        for seconds in (True, 0, 10_800, 28_801, float("inf"), "3600"):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                MetricsReadPhase(proof(recentReads=[dict(intervalSeconds=seconds)]), "refresh")

    def test_complete_refresh_includes_pending_intermediate_phase(self):
        guard = MetricsReadPhase(proof(), "refresh")
        guard.observe(proof(started=5))
        guard.observe(proof(started=5, completed=5))
        result = guard.finish()
        self.assertEqual(result["completedDelta"], 1)
        self.assertEqual(result["startedDelta"], 1)

    def test_quiet_visible_and_released_scopes_are_allowed(self):
        for rows in (100_000, 0):
            guard = MetricsReadPhase(proof(retainedSnapshotRows=rows), "quiet")
            guard.observe(proof(retainedSnapshotRows=rows))
            self.assertEqual(guard.finish()["completedDelta"], 0)

    def test_quiet_gap_does_not_qualify_as_refresh(self):
        with self.assertRaisesRegex(ValueError, "complete refresh"):
            MetricsReadPhase(proof(), "refresh").finish()

    def test_pending_start_and_end_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "pending read"):
            MetricsReadPhase(proof(started=5), "refresh")
        guard = MetricsReadPhase(proof(), "refresh")
        guard.observe(proof(started=5))
        with self.assertRaisesRegex(ValueError, "incomplete read"):
            guard.finish()

    def test_quiet_window_rejects_even_started_read(self):
        guard = MetricsReadPhase(proof(), "quiet")
        with self.assertRaisesRegex(ValueError, "read work"):
            guard.observe(proof(started=5))

    def test_read_failure_cancellation_empty_and_cache_release_are_rejected(self):
        for field in ("failed", "cancelled", "empty", "cacheReleases"):
            guard = MetricsReadPhase(proof(), "refresh")
            changed = proof(started=5, completed=5 if field in ("empty", "cacheReleases") else 4)
            changed[field] = 1
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "outcome changed"):
                guard.observe(changed)

    def test_row_release_and_period_changes_are_rejected(self):
        for changed in (proof(retainedSnapshotRows=0),
                        proof(recentReads=[dict(intervalSeconds=86_400)])):
            with self.assertRaisesRegex(ValueError, "scope, cache"):
                MetricsReadPhase(proof(), "refresh").observe(changed)

    def test_reload_counter_reset_is_rejected(self):
        guard = MetricsReadPhase(proof(), "refresh")
        with self.assertRaisesRegex(ValueError, "reset"):
            guard.observe(proof(started=1, completed=1))

    def test_invalid_counter_and_scope_values_are_rejected(self):
        invalid = [proof(started=True), proof(started=-1), proof(completed=5),
                   proof(empty=5), proof(retainedSnapshotRows=100_001),
                   proof(recentReads=[dict(intervalSeconds=float("nan"))])]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                MetricsReadPhase(value, "refresh")

    def test_held_and_first_reads_are_not_normal_refresh_profiles(self):
        for value in (proof(heldReadID=5), proof(retainedSnapshotRows=0), proof(recentReads=[])):
            with self.subTest(value=value), self.assertRaises(ValueError):
                MetricsReadPhase(value, "refresh")

    def test_finished_summary_does_not_alias_mutable_proof(self):
        original = proof()
        guard = MetricsReadPhase(original, "refresh")
        after = copy.deepcopy(original)
        after.update(started=5, completed=5)
        guard.observe(after)
        after["completed"] = 999
        self.assertEqual(guard.finish()["after"]["completed"], 5)


if __name__ == "__main__":
    unittest.main()
