import copy
import unittest

import metrics_read_phase
from metrics_read_phase import MetricsReadPhase


def proof(**changes):
    result = dict(started=4, completed=4, failed=0, cancelled=0, empty=0,
                  cacheReleases=0, retainedSnapshotRows=100_000,
                  recentReads=[dict(intervalSeconds=2_592_000)])
    result.update(changes)
    return result


def rolling_read(read_id=4, *, end=1_700_000_000, seconds=3_600,
                 rows=144, reused=None):
    return dict(readID=read_id, intervalSeconds=seconds,
                queryStartUnix=end - seconds, queryEndUnix=end, rows=rows,
                reusedRows=rows if reused is None else reused, milliseconds=1.5)


def rolling_proof(reads=None, **changes):
    reads = [rolling_read()] if reads is None else reads
    result = proof(recentReads=reads, retainedSnapshotRows=reads[-1].get("rows", 0) if reads else 0)
    result.update(changes)
    return result


class MetricsEndpointBracketTests(unittest.TestCase):
    def test_stable_proof_preserves_order_timestamp_and_pre_counter_snapshot(self):
        calls = []
        snapshots = [proof(), proof()]

        def read_proof():
            calls.append("proof")
            return snapshots.pop(0)

        def read_usage():
            calls.append("usage")
            return 12.5

        def clock():
            calls.append("clock")
            return 42.25

        usage, timestamp, saved = metrics_read_phase.bracket_metrics_endpoint(
            read_usage, read_proof, clock)
        self.assertEqual(calls, ["proof", "usage", "clock", "proof"])
        self.assertEqual((usage, timestamp), (12.5, 42.25))
        self.assertEqual(saved, proof())

    def test_read_start_or_full_completion_during_cpu_endpoint_is_rejected(self):
        for changes in (dict(started=5), dict(started=5, completed=5)):
            shared = proof()
            quiet = MetricsReadPhase(shared, "quiet")

            def read_usage():
                shared.update(changes)
                return 10

            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, "endpoint"):
                metrics_read_phase.bracket_metrics_endpoint(
                    read_usage, lambda: shared, lambda: 20)
            self.assertEqual(quiet.finish()["completedDelta"], 0)

    def test_pending_completion_at_boundary_cannot_receive_phase_credit(self):
        guard = MetricsReadPhase(proof(), "refresh")
        pending = proof(started=5)
        guard.observe(pending)
        snapshots = [pending, proof(started=5, completed=5)]
        with self.assertRaisesRegex(ValueError, "endpoint"):
            metrics_read_phase.bracket_metrics_endpoint(
                lambda: 10, lambda: snapshots.pop(0), lambda: 20)
        with self.assertRaisesRegex(ValueError, "incomplete read"):
            guard.finish()

    def test_stable_pending_proof_is_returned_without_future_completion_credit(self):
        pending = proof(started=5)
        _, _, saved = metrics_read_phase.bracket_metrics_endpoint(
            lambda: 10, lambda: pending, lambda: 20)
        guard = MetricsReadPhase(proof(), "refresh")
        guard.observe(saved)
        with self.assertRaisesRegex(ValueError, "incomplete read"):
            guard.finish()

    def test_no_proof_process_profile_is_allowed_but_proof_presence_changes_are_rejected(self):
        self.assertEqual(metrics_read_phase.bracket_metrics_endpoint(
            lambda: 10, lambda: None, lambda: 20), (10, 20, None))
        for snapshots in ([None, proof()], [proof(), None]):
            with self.subTest(snapshots=snapshots), self.assertRaisesRegex(ValueError, "endpoint"):
                metrics_read_phase.bracket_metrics_endpoint(
                    lambda: 10, lambda: snapshots.pop(0), lambda: 20)

    def test_aliased_proof_mutation_during_usage_or_clock_is_rejected(self):
        for boundary in ("usage", "clock"):
            shared = proof()
            shared["nested"] = {"values": [1]}

            def mutate(where, value):
                if where == boundary:
                    shared["nested"]["values"].append(2)
                return value

            with self.subTest(boundary=boundary), self.assertRaisesRegex(ValueError, "endpoint"):
                metrics_read_phase.bracket_metrics_endpoint(
                    lambda: mutate("usage", 10), lambda: shared, lambda: mutate("clock", 20))

    def test_returned_proof_does_not_alias_either_callback_snapshot(self):
        before = proof()
        before["nested"] = {"values": [1]}
        after = copy.deepcopy(before)
        snapshots = [before, after]
        _, _, saved = metrics_read_phase.bracket_metrics_endpoint(
            lambda: 10, lambda: snapshots.pop(0), lambda: 20)
        before["nested"]["values"].append(2)
        after["nested"]["values"].append(3)
        self.assertEqual(saved["nested"]["values"], [1])


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


class RollingMetricsReadPhaseTests(unittest.TestCase):
    def test_supported_scopes_allow_complete_reused_rolling_shrinkage(self):
        for seconds in (3_600, 7_200, 28_800, 43_200, 86_400, 604_800, 2_592_000):
            with self.subTest(seconds=seconds):
                first = rolling_read(seconds=seconds, reused=0)
                guard = MetricsReadPhase(rolling_proof([first]), "rolling-refresh")
                second = rolling_read(5, seconds=seconds, end=1_700_000_030, rows=143)
                guard.observe(rolling_proof([first, second], started=5, completed=5))
                result = guard.finish()
                self.assertEqual(result["completedDelta"], 1)
                self.assertEqual(result["after"]["retainedSnapshotRows"], 143)

    def test_pending_phases_track_each_completed_read_without_double_counting(self):
        first = rolling_read()
        second = rolling_read(5, end=1_700_000_030, rows=143)
        third = rolling_read(6, end=1_700_000_060, rows=143)
        guard = MetricsReadPhase(rolling_proof([first]), "rolling-refresh")
        guard.observe(rolling_proof([first], started=5))
        intermediate = rolling_proof([first, second], started=6, completed=5)
        guard.observe(intermediate)
        guard.observe(intermediate)
        guard.observe(rolling_proof([second, third], started=6, completed=6))
        result = guard.finish()
        self.assertEqual(result["completedDelta"], 2)
        self.assertEqual(result["baselineRead"], first)
        self.assertEqual(result["completedReads"], [second, third])

    def test_saved_completions_survive_trimming_the_native_evidence_buffer(self):
        first = rolling_read()
        guard = MetricsReadPhase(rolling_proof([first]), "rolling-refresh")
        expected = []
        recent = [first]
        for read_id in range(5, 21):
            read = rolling_read(read_id, end=1_700_000_000 + (read_id - 4) * 30,
                                rows=144 - (read_id - 4))
            expected.append(read)
            recent = (recent + [read])[-12:]
            guard.observe(rolling_proof(recent, started=read_id, completed=read_id))
        result = guard.finish()
        self.assertEqual(result["baselineRead"], first)
        self.assertEqual(result["completedReads"], expected)
        self.assertEqual(len(result["completedReads"]), 16)

    def test_saved_evidence_only_contains_known_scalars_and_does_not_alias_callers(self):
        first = dict(rolling_read(), unknown={"payload": ["baseline"]})
        baseline = rolling_proof([first])
        guard = MetricsReadPhase(baseline, "rolling-refresh")
        second = dict(rolling_read(5, end=1_700_000_030, rows=143),
                      unknown={"payload": ["completion"]})
        after = rolling_proof([first, second], started=5, completed=5)
        guard.observe(after)
        first["rows"] = 999
        second["rows"] = 888
        first["unknown"]["payload"].append("changed")
        second["unknown"]["payload"].append("changed")
        baseline["retainedSnapshotRows"] = 999
        after["completed"] = 999

        result = guard.finish()
        expected = copy.deepcopy(result)
        self.assertNotIn("unknown", result["baselineRead"])
        self.assertNotIn("unknown", result["completedReads"][0])
        self.assertEqual(result["baselineRead"]["rows"], 144)
        self.assertEqual(result["completedReads"][0]["rows"], 143)
        result["baselineRead"]["rows"] = 777
        result["completedReads"][0]["rows"] = 666
        result["completedReads"].clear()
        result["before"]["retainedSnapshotRows"] = 555
        result["after"]["completed"] = 555
        self.assertEqual(guard.finish(), expected)

    def test_strict_reports_do_not_add_rolling_evidence_fields(self):
        for mode in ("refresh", "quiet"):
            guard = MetricsReadPhase(proof(), mode)
            guard.observe(proof(started=5, completed=5) if mode == "refresh" else proof())
            result = guard.finish()
            self.assertNotIn("baselineRead", result)
            self.assertNotIn("completedReads", result)

    def test_missing_skipped_duplicate_and_overflowed_read_evidence_is_rejected(self):
        first = rolling_read()
        second = rolling_read(5, end=1_700_000_030, rows=143)
        third = rolling_read(6, end=1_700_000_060, rows=142)
        changes = [rolling_proof([], started=5, completed=5, retainedSnapshotRows=143),
                   rolling_proof([first, third], started=6, completed=6),
                   rolling_proof([first, second, second], started=5, completed=5),
                   rolling_proof([third, second], started=6, completed=6),
                   rolling_proof([rolling_read(i, end=1_700_000_000 + i * 30)
                                  for i in range(7, 19)], started=18, completed=18)]
        for changed in changes:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(changed)

    def test_unexplained_rows_or_mutated_completed_evidence_are_rejected(self):
        first = rolling_read()
        mutated = dict(first, queryStartUnix=first["queryStartUnix"] + 30,
                       queryEndUnix=first["queryEndUnix"] + 30)
        for changed in (rolling_proof([first], retainedSnapshotRows=143),
                        rolling_proof([mutated]),
                        rolling_proof([rolling_read(5)], started=5),
                        rolling_proof([first], started=5, completed=5)):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(changed)

    def test_growth_partial_reuse_backward_bounds_and_period_changes_are_rejected(self):
        first = rolling_read()
        candidates = [rolling_read(5, end=1_700_000_030, rows=145),
                      rolling_read(5, end=1_700_000_030, rows=143, reused=142),
                      rolling_read(5, end=1_699_999_970, rows=143),
                      rolling_read(5, end=1_700_000_030, seconds=7_200, rows=143),
                      dict(rolling_read(5, end=1_700_000_030), queryStartUnix=1_699_996_429)]
        for candidate in candidates:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(
                    rolling_proof([first, candidate], started=5, completed=5))

    def test_valid_latest_record_cannot_hide_invalid_intermediate_work(self):
        first = rolling_read()
        last = rolling_read(6, end=1_700_000_060, rows=142)
        intermediate = [rolling_read(5, end=1_700_000_030, rows=145),
                        rolling_read(5, end=1_700_000_030, rows=143, reused=142),
                        rolling_read(5, end=1_700_000_030, seconds=7_200, rows=143),
                        rolling_read(5, end=1_699_999_970, rows=143)]
        for bad in intermediate:
            with self.subTest(intermediate=bad), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(
                    rolling_proof([first, bad, last], started=6, completed=6))

    def test_unix_rounding_tolerance_does_not_allow_a_different_scope(self):
        first = rolling_read()
        second = rolling_read(5, end=1_700_000_030.123456, rows=143)
        second["queryStartUnix"] += 0.0000002384185791015625
        guard = MetricsReadPhase(rolling_proof([first]), "rolling-refresh")
        guard.observe(rolling_proof([first, second], started=5, completed=5))
        self.assertEqual(guard.finish()["completedDelta"], 1)
        second["queryStartUnix"] += 0.00001
        with self.assertRaises(ValueError):
            MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(
                rolling_proof([first, second], started=5, completed=5))

    def test_all_record_scalars_have_a_finite_strict_schema(self):
        for field in ("readID", "rows", "reusedRows", "intervalSeconds",
                      "queryStartUnix", "queryEndUnix", "milliseconds"):
            for invalid in (True, "1", None, float("nan"), float("inf"), -float("inf")):
                malformed = dict(rolling_read(), **{field: invalid})
                with self.subTest(field=field, invalid=invalid), self.assertRaises(ValueError):
                    MetricsReadPhase(rolling_proof([malformed], retainedSnapshotRows=144), "rolling-refresh")
            missing = rolling_read()
            del missing[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([missing], retainedSnapshotRows=144), "rolling-refresh")
        for malformed in (dict(rolling_read(), readID=4.0), dict(rolling_read(), rows=144.0),
                          dict(rolling_read(), readID=0), dict(rolling_read(), rows=-1),
                          dict(rolling_read(), reusedRows=-1), dict(rolling_read(), reusedRows=145),
                          dict(rolling_read(), milliseconds=-1), dict(rolling_read(), intervalSeconds=10_800),
                          dict(rolling_read(), queryEndUnix=10 ** 1_000),
                          dict(rolling_read(), rows=0, reusedRows=0)):
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([malformed], retainedSnapshotRows=144), "rolling-refresh")
        for malformed in (None, {}, "reads", [None], [], [rolling_read()] * 13):
            value = proof(recentReads=malformed, retainedSnapshotRows=144)
            with self.subTest(reads=malformed), self.assertRaises(ValueError):
                MetricsReadPhase(value, "rolling-refresh")

    def test_outcome_cache_hold_counter_and_pending_protections_remain(self):
        first = rolling_read()
        second = rolling_read(5, end=1_700_000_030, rows=143)
        for field in ("failed", "cancelled", "empty", "cacheReleases"):
            changed = rolling_proof([first, second], started=6, completed=5, **{field: 1})
            with self.subTest(field=field), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(changed)
        for changed in (rolling_proof([first], heldReadID=5),
                        rolling_proof([rolling_read(1)], started=1, completed=1),
                        rolling_proof([first], started=True)):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), "rolling-refresh").observe(changed)
        with self.assertRaises(ValueError):
            MetricsReadPhase(rolling_proof([first], started=5), "rolling-refresh")
        guard = MetricsReadPhase(rolling_proof([first]), "rolling-refresh")
        guard.observe(rolling_proof([first], started=5))
        with self.assertRaises(ValueError):
            guard.finish()
        with self.assertRaises(ValueError):
            MetricsReadPhase(rolling_proof([first]), "rolling-refresh").finish()

    def test_strict_modes_still_reject_rolling_row_changes(self):
        first = rolling_read()
        second = rolling_read(5, end=1_700_000_030, rows=143)
        for mode in ("refresh", "quiet"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                MetricsReadPhase(rolling_proof([first]), mode).observe(
                    rolling_proof([first, second], started=5, completed=5))


if __name__ == "__main__":
    unittest.main()
