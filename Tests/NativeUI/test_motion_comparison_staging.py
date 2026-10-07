"""Fail-closed overlay tests; no compiler, app or provider dependency."""
import unittest
from pathlib import Path

from MenuBarMotionComparison import ALIASES, COMPARISON, EXPECTED_CASES, METADATA, PAYLOAD, stage_comparison


class MotionComparisonStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(__file__).with_name("MenuBarMotionProof.swift").read_text()

    def test_overlay_preserves_all_original_case_bodies_and_requirements(self):
        staged = stage_comparison(self.source)
        restored = staged.replace(COMPARISON, ALIASES).replace(
            "        var fixture: MotionArcFixture\n", "        let fixture: MotionArcFixture\n"
        ).replace("await comparisonCheck(", "await report.check(").replace(METADATA, "").replace(
            PAYLOAD.replace("let payload", "var payload"), PAYLOAD)
        self.assertEqual(restored, self.source)
        self.assertEqual(staged.count("await comparisonCheck("), len(EXPECTED_CASES))

    def test_added_case_is_rejected_instead_of_silently_skipped(self):
        source = self.source.replace('await report.check("native_window_visible")',
            'await report.check("new_case") {}\n        await report.check("native_window_visible")', 1)
        with self.assertRaisesRegex(ValueError, "fifteen ordered cases"):
            stage_comparison(source)

    def test_removed_case_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "fifteen ordered cases"):
            stage_comparison(self.source.replace('await report.check("same_window_close_and_reopen")',
                                                'await otherCheck("same_window_close_and_reopen")', 1))

    def test_case_order_drift_is_rejected(self):
        source = self.source.replace('await report.check("native_window_visible")',
                                    'await report.check("active_compositor_advances")', 1)
        with self.assertRaisesRegex(ValueError, "fifteen ordered cases"):
            stage_comparison(source)

    def test_initialization_drift_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "declaration/alias"):
            stage_comparison(self.source.replace("        let fixture: MotionArcFixture\n",
                                                "        let fixture: OtherFixture\n", 1))

    def test_alias_drift_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "declaration/alias"):
            stage_comparison(self.source.replace("        let arc = fixture.arc\n",
                                                "        let arc = anotherArc\n", 1))

    def test_report_metadata_drift_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "metadata"):
            stage_comparison(self.source.replace(PAYLOAD, PAYLOAD.replace('"native-menu-bar-motion"',
                                                                        '"different-proof"'), 1))


if __name__ == "__main__":
    unittest.main()
