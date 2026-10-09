import sqlite3
import tempfile
import unittest
from pathlib import Path

from metrics_dataset import dataset_fingerprint


class MetricsDatasetTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "history.sqlite"
        self.connection = sqlite3.connect(self.path)
        self.addCleanup(self.connection.close)
        self.connection.execute("CREATE TABLE performance_history "
                                "(id TEXT PRIMARY KEY, observed_at REAL, model TEXT, sample BLOB)")
        self.connection.executemany("INSERT INTO performance_history VALUES (?, ?, ?, ?)", [
            ("first", 100.0, "qwen", b"first payload"),
            ("middle", 125.0, None, b"middle payload"),
            ("last", 150.0, "gemma", b"last payload"),
        ])
        self.connection.commit()

    def test_middle_payload_change_is_detected_with_same_count_and_dates(self):
        before = dataset_fingerprint(self.path)
        self.connection.execute("UPDATE performance_history SET sample=? WHERE id='middle'",
                                (b"changed payload",))
        self.connection.commit()
        after = dataset_fingerprint(self.path)
        self.assertEqual(before["rows"], after["rows"])
        self.assertEqual(before["oldestUnix"], after["oldestUnix"])
        self.assertEqual(before["newestUnix"], after["newestUnix"])
        self.assertNotEqual(before["sha256"], after["sha256"])

    def test_repeated_reads_do_not_change_the_dataset(self):
        before = dataset_fingerprint(self.path)
        self.assertEqual(before, dataset_fingerprint(self.path))
        self.assertEqual(before["rows"], 3)
        self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM performance_history").fetchone()[0], 3)

    def test_missing_path_is_not_created(self):
        missing = self.path.with_name("missing.sqlite")
        with self.assertRaises(sqlite3.OperationalError):
            dataset_fingerprint(missing)
        self.assertFalse(missing.exists())

    def test_empty_and_invalid_payloads_cannot_qualify_a_frozen_history(self):
        self.connection.execute("DELETE FROM performance_history")
        self.connection.commit()
        with self.assertRaises(ValueError):
            dataset_fingerprint(self.path)
        self.connection.execute("INSERT INTO performance_history VALUES ('bad', 100, NULL, 'not a blob')")
        self.connection.commit()
        with self.assertRaises(ValueError):
            dataset_fingerprint(self.path)


if __name__ == "__main__":
    unittest.main()
