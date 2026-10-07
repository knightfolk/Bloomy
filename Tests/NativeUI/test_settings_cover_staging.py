import unittest
from pathlib import Path
from SettingsCoverStaging import ACCESS_EXTENSION, stage_settings_cover_access


class SettingsCoverStagingTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(__file__).with_name('MenuBarMotionProof.swift').read_text()

    def test_original_proof_and_owned_cover_are_byte_preserved(self):
        self.assertEqual(stage_settings_cover_access(self.source), self.source + ACCESS_EXTENSION)
        self.assertTrue(ACCESS_EXTENSION.startswith('\n#if FIXTURE_SETTINGS_PREVIEW_PROOF\n'))

    def test_missing_or_duplicate_safety_anchors_rejected(self):
        anchor = '    private final class OwnedMotionCover {\n'
        for replacement in ['', anchor + anchor]:
            with self.assertRaises(ValueError):
                stage_settings_cover_access(self.source.replace(anchor, replacement))
        with self.assertRaises(ValueError):
            stage_settings_cover_access(self.source.replace('process.arguments = ["--motion-cover",', 'process.arguments = []'))

    def test_repeated_staging_and_case_drift_rejected(self):
        with self.assertRaises(ValueError): stage_settings_cover_access(stage_settings_cover_access(self.source))
        with self.assertRaises(ValueError): stage_settings_cover_access(self.source.replace('"detach_and_restore"', '"different_case"'))

    def test_startup_failure_and_cancellation_share_joined_cleanup(self):
        self.assertEqual(ACCESS_EXTENSION.count('await cover.stop()'), 1)
        self.assertGreater(ACCESS_EXTENSION.index('result["cleanup"] = await cover.stop()'),
                           ACCESS_EXTENSION.index('catch is CancellationError'))
        self.assertLess(ACCESS_EXTENSION.index('let cover = OwnedMotionCover'), ACCESS_EXTENSION.index('do {'))
        after_cleanup = ACCESS_EXTENSION.split('result["cleanup"] = await cover.stop()', 1)[1]
        self.assertIn('if Task.isCancelled', after_cleanup)
        self.assertIn('result["cancelled"] = true', after_cleanup)
        self.assertIn('result["passed"] = false', after_cleanup)
        for forbidden in ['.terminate()', 'Darwin.kill', 'CATransaction', 'window.occlusionState =']:
            self.assertNotIn(forbidden, ACCESS_EXTENSION)


if __name__ == '__main__': unittest.main()
