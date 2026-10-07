import unittest
from pathlib import Path

from MenuBarRenderHistory import DECLARATION, METADATA, stage_render_history


class RenderHistoryStagingTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).with_name('MenuBarMotionProof.swift').read_text()

    def test_only_early_observations_and_metadata_change(self):
        staged = stage_render_history(self.source)
        restored = staged.replace(DECLARATION, '').replace(METADATA, '')
        restored = restored.replace(', requestDisplay: earlyRequestDisplay', '')
        restored = restored.replace('var payload: [String: Any]', 'let payload: [String: Any]')
        self.assertEqual(restored, self.source)
        self.assertEqual(staged.count('requestDisplay: earlyRequestDisplay'), 4)

    def test_later_observations_and_recovery_are_identical(self):
        staged = stage_render_history(self.source)
        start = '        await report.check("self_hide_and_restore")'
        original_tail = self.source.split(start, 1)[1]
        staged_tail = staged.split(start, 1)[1].replace(METADATA, '')
        staged_tail = staged_tail.replace('var payload: [String: Any]', 'let payload: [String: Any]')
        self.assertEqual(original_tail, staged_tail)

    def test_missing_early_read_is_rejected(self):
        altered = self.source.replace('let first = try await presentationAngle(arc, in: window)',
                                      'let first = 0.0', 1)
        with self.assertRaises(ValueError): stage_render_history(altered)

    def test_added_early_read_is_rejected(self):
        anchor = '        await report.check("self_hide_and_restore")'
        altered = self.source.replace(anchor, '            let extra = try await presentationAngle(arc, in: window)\n' + anchor)
        with self.assertRaises(ValueError): stage_render_history(altered)

    def test_changed_case_order_is_rejected(self):
        altered = self.source.replace('"self_hide_and_restore"', '"changed_case"')
        with self.assertRaises(ValueError): stage_render_history(altered)

    def test_changed_fixture_anchor_is_rejected(self):
        with self.assertRaises(ValueError):
            stage_render_history(self.source.replace('        let arc = fixture.arc\n', '        let arc = renamed.arc\n'))

    def test_changed_report_anchor_is_rejected(self):
        with self.assertRaises(ValueError):
            stage_render_history(self.source.replace('"native-menu-bar-motion"', '"changed-proof"'))


if __name__ == '__main__': unittest.main()
