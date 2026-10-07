"""The diagnostic may expose a button, never rewrite the production host."""
import unittest
from pathlib import Path

from StatusItemHostStaging import ACCESS_EXTENSION, stage_status_item_access


class StatusItemStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (Path(__file__).resolve().parents[2] /
                      "Sources/DarkbloomMonitor/StatusItemController.swift").read_text()

    def test_original_host_is_byte_preserved(self):
        staged = stage_status_item_access(self.source)
        self.assertTrue(staged.endswith(ACCESS_EXTENSION))
        self.assertEqual(staged[:-len(ACCESS_EXTENSION)], self.source)

    def test_missing_or_duplicated_ownership_anchor_is_rejected(self):
        anchor = "    private let statusItem: NSStatusItem\n"
        for replacement in ("", anchor + anchor):
            with self.subTest(replacement=replacement), self.assertRaisesRegex(ValueError, "anchor drifted"):
                stage_status_item_access(self.source.replace(anchor, replacement))

    def test_repeated_staging_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "already present"):
            stage_status_item_access(stage_status_item_access(self.source))


if __name__ == "__main__":
    unittest.main()
