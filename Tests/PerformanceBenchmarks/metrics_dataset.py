"""Read-only content provenance for privately owned, paused Metrics fixtures."""

import hashlib
import json
import math
import sqlite3
from contextlib import closing


def dataset_fingerprint(path):
    digest = hashlib.sha256()
    count = 0
    oldest = newest = None
    # mode=ro also prevents a misspelled path from creating a new database.
    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        connection.execute("BEGIN")
        for rowid, identifier, date, model, payload in connection.execute(
                "SELECT rowid, id, observed_at, model, sample FROM performance_history ORDER BY rowid"):
            if (type(rowid) is not int or type(identifier) is not str
                    or type(date) not in (int, float) or not math.isfinite(date)
                    or (model is not None and type(model) is not str)
                    or type(payload) is not bytes):
                raise ValueError("Metrics dataset has invalid recorded fields")
            metadata = json.dumps([rowid, identifier, date, model], ensure_ascii=False,
                                  separators=(",", ":"), allow_nan=False).encode()
            digest.update(len(metadata).to_bytes(8, "big"))
            digest.update(metadata)
            digest.update(len(payload).to_bytes(8, "big"))
            digest.update(payload)
            count += 1
            if count > 100_000:
                raise ValueError("Metrics dataset exceeds the fixture retention cap")
            oldest = date if oldest is None else min(oldest, date)
            newest = date if newest is None else max(newest, date)
    if not count:
        raise ValueError("Metrics dataset is empty")
    return {"sha256": digest.hexdigest(), "rows": count,
            "oldestUnix": oldest, "newestUnix": newest}
