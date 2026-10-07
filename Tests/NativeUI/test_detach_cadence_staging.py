import unittest
from pathlib import Path

from MenuBarDetachCadence import ANCHOR, TREATMENT, OBSERVER, DELAY, METADATA, stage_detach_cadence


class DetachCadenceStagingTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).with_name('MenuBarMotionProof.swift').read_text()

    def test_exact_inverse_preserves_original_proof(self):
        staged = stage_detach_cadence(self.source)
        restored = staged.replace(TREATMENT, ANCHOR).replace(OBSERVER, '').replace(DELAY, '').replace(METADATA, '')
        restored = restored.replace('var payload: [String: Any]', 'let payload: [String: Any]')
        self.assertEqual(restored, self.source)

    def test_reopening_bodies_unchanged(self):
        staged = stage_detach_cadence(self.source)
        start = '        await report.check("same_window_close_and_reopen")'
        end = '        await report.check("native_stationary_true_false_true")'
        self.assertEqual(self.source.split(start)[1].split(end)[0], staged.split(start)[1].split(end)[0])

    def test_only_detach_treatment_is_selected(self):
        staged = stage_detach_cadence(self.source)
        self.assertEqual(staged.count('try await observeDetachedCompositor('), 1)
        start = staged.index('await report.check("detach_and_restore")')
        end = staged.index('await report.check("same_window_close_and_reopen")')
        self.assertIn('try await observeDetachedCompositor(', staged[start:end])
        self.assertNotIn('displayIfNeeded', OBSERVER)
        self.assertNotIn('CATransaction.flush', OBSERVER)
        self.assertNotIn('.configure(', OBSERVER)

    def test_missing_detach_anchor_rejected(self):
        with self.assertRaises(ValueError): stage_detach_cadence(self.source.replace(ANCHOR, ''))

    def test_delay_is_single_sleep_without_observation_or_recovery(self):
        self.assertEqual(DELAY.count('Task.sleep('), 1)
        self.assertIn('.milliseconds(50)', DELAY)
        for forbidden in ['.presentation()', 'displayIfNeeded', 'CATransaction.flush', '.configure(', 'repeat {']:
            self.assertNotIn(forbidden, DELAY)

    def test_delay_selection_and_metadata_are_confined(self):
        staged = stage_detach_cadence(self.source)
        start = staged.index('await report.check("detach_and_restore")')
        end = staged.index('await report.check("same_window_close_and_reopen")')
        self.assertIn('try await waitDetachedCadence(', staged[start:end])
        self.assertEqual(staged.count('try await waitDetachedCadence('), 1)
        self.assertIn('payload["detachCadence"] = "delay-only"', METADATA)

    def test_duplicate_detach_anchor_rejected(self):
        with self.assertRaises(ValueError): stage_detach_cadence(self.source.replace(ANCHOR, ANCHOR + ANCHOR))

    def test_case_order_drift_rejected(self):
        with self.assertRaises(ValueError):
            stage_detach_cadence(self.source.replace('"detach_and_restore"', '"changed_case"'))

    def test_report_anchor_drift_rejected(self):
        with self.assertRaises(ValueError):
            stage_detach_cadence(self.source.replace('"native-menu-bar-motion"', '"changed-proof"'))

    def test_observer_anchor_drift_rejected(self):
        with self.assertRaises(ValueError):
            stage_detach_cadence(self.source.replace('    private static func recoveredClockEvidence(', '    private static func changedClockEvidence('))


if __name__ == '__main__': unittest.main()
