import unittest
from pathlib import Path
from MenuBarRootLayer import ANCHOR, TREATMENT, METADATA, stage_root_layer


class RootLayerStagingTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).with_name('MenuBarMotionProof.swift').read_text()

    def test_exact_inverse_preserves_original_proof(self):
        staged = stage_root_layer(self.source)
        restored = staged.replace(TREATMENT, ANCHOR).replace(METADATA, '')
        restored = restored.replace('var payload: [String: Any]', 'let payload: [String: Any]')
        self.assertEqual(restored, self.source)

    def test_all_case_bodies_and_cleanup_are_unchanged(self):
        staged = stage_root_layer(self.source)
        start = '        await report.check("native_window_visible")'
        end = '    private static func require('
        self.assertEqual(self.source.split(start)[1].split(end)[0], staged.split(start)[1].split(end)[0])

    def test_one_guarded_root_change_without_recovery_or_wait(self):
        change = TREATMENT[len(ANCHOR):]
        self.assertEqual(change.count('container.wantsLayer = true'), 1)
        self.assertIn('#if FIXTURE_EXPLICIT_MOTION_ROOT_LAYER', change)
        for forbidden in ['sleep', 'flush', 'display', 'configure', 'animation', 'Task']:
            self.assertNotIn(forbidden, change)
        self.assertIn('replacesNormalNativeGate', METADATA)

    def test_missing_and_duplicate_root_anchors_rejected(self):
        for changed in (self.source.replace(ANCHOR, ''), self.source.replace(ANCHOR, ANCHOR+ANCHOR)):
            with self.assertRaises(ValueError): stage_root_layer(changed)

    def test_case_order_drift_rejected(self):
        with self.assertRaises(ValueError):
            stage_root_layer(self.source.replace('"detach_and_restore"', '"changed_case"'))

    def test_unique_anchor_moved_after_fixture_rejected(self):
        changed = self.source.replace(ANCHOR, '') + '\n' + ANCHOR
        with self.assertRaises(ValueError): stage_root_layer(changed)

    def test_report_anchor_drift_rejected(self):
        with self.assertRaises(ValueError):
            stage_root_layer(self.source.replace('"native-menu-bar-motion"', '"changed-proof"'))


if __name__ == '__main__': unittest.main()
