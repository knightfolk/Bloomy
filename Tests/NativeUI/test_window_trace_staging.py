"""Trace overlays must retain production behavior and reject source drift."""
import unittest
from pathlib import Path

from MenuBarMotionComparison import stage_comparison
from MenuBarWindowTrace import (BEFORE_ANCHOR, LABEL_PATCHES, VISIBILITY_AFTER,
    VISIBILITY_BEFORE, TRACE_CASE, TRACE_METADATA, TRACE_REPORT_FIELDS,
    stage_trace_report, stage_window_trace)


class WindowTraceStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.label = (Path(__file__).resolve().parents[2] / 'Sources/DarkbloomMonitor/MenuBarLabel.swift').read_text()
        cls.report = stage_comparison(Path(__file__).with_name('MenuBarMotionProof.swift').read_text())

    def test_trace_retains_original_product_source_exactly(self):
        restored = stage_window_trace(self.label).replace(VISIBILITY_AFTER, VISIBILITY_BEFORE)
        for anchor, addition in reversed(LABEL_PATCHES):
            if anchor == BEFORE_ANCHOR:
                first, second = anchor.split('            super.', 1)
                restored = restored.replace(first + addition + '            super.' + second, anchor)
            else:
                restored = restored.replace(anchor + addition, anchor)
        self.assertEqual(restored, self.label)

    def test_each_product_anchor_drift_is_rejected(self):
        for anchor, _ in LABEL_PATCHES:
            with self.subTest(anchor=anchor), self.assertRaisesRegex(ValueError, 'anchor drifted'):
                stage_window_trace(self.label.replace(anchor, '', 1))

    def test_visibility_callback_drift_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'callback anchor drifted'):
            stage_window_trace(self.label.replace(VISIBILITY_BEFORE, '', 1))

    def test_trace_retains_original_comparison_report_exactly(self):
        restored = stage_trace_report(self.report)
        for addition in (TRACE_CASE, TRACE_METADATA, TRACE_REPORT_FIELDS):
            restored = restored.replace(addition, '')
        self.assertEqual(restored, self.report)

    def test_trace_requires_comparison_overlay(self):
        with self.assertRaisesRegex(ValueError, 'report anchor drifted'):
            stage_trace_report(Path(__file__).with_name('MenuBarMotionProof.swift').read_text())


if __name__ == '__main__':
    unittest.main()
