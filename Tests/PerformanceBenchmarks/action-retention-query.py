#!/usr/bin/env python3
"""Compare action retention with its frozen query using macOS's SQLite library.

Synthetic in-memory rows only. Measures warm retention statements, including
their transactions, not complete ingestion, disk I/O, app CPU or energy.
"""
import argparse
import ctypes
import hashlib
import json
import re
import statistics
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error('Choose a fresh output; preserve existing evidence')
source_bytes = args.source.read_bytes()
match = re.search(r'private func prune\(.*?prepare\("""\s*(.*?)\s*"""\)',
                  source_bytes.decode(), re.S)
if match is None:
    parser.error('Cannot locate the production retention statement')
candidate = ' '.join(match.group(1).split())
assert candidate.count('?') == 2
reference = ('DELETE FROM action_history WHERE occurred_at < ? OR id NOT IN ('
             'SELECT id FROM action_history ORDER BY occurred_at DESC, rowid DESC LIMIT ?)')

lib = ctypes.CDLL('/usr/lib/libsqlite3.dylib')
lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
lib.sqlite3_open.restype = ctypes.c_int
lib.sqlite3_close.argtypes = [ctypes.c_void_p]
lib.sqlite3_close.restype = ctypes.c_int
lib.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p,
                           ctypes.c_void_p, ctypes.c_void_p]
lib.sqlite3_exec.restype = ctypes.c_int
lib.sqlite3_errmsg.argtypes = [ctypes.c_void_p]
lib.sqlite3_errmsg.restype = ctypes.c_char_p
lib.sqlite3_libversion.restype = ctypes.c_char_p
callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_int,
                                ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p))


def execute(db, sql, collect=False):
    result = []

    @callback_type
    def callback(_, count, values, __):
        result.append([values[i].decode() if values[i] is not None else None for i in range(count)])
        return 0

    code = lib.sqlite3_exec(db, sql.encode(), callback if collect else None, None, None)
    if code:
        raise RuntimeError(lib.sqlite3_errmsg(db).decode())
    return result


def database(count, ties):
    db = ctypes.c_void_p()
    if lib.sqlite3_open(b':memory:', ctypes.byref(db)):
        raise RuntimeError('Cannot open isolated benchmark database')
    execute(db, 'CREATE TABLE action_history(id TEXT PRIMARY KEY, occurred_at REAL NOT NULL);'
            'CREATE INDEX action_history_occurred_at ON action_history(occurred_at DESC,id);'
            'PRAGMA secure_delete=ON; BEGIN IMMEDIATE;')
    execute(db, ''.join(f"INSERT INTO action_history VALUES ('{i:08d}',{10000 + (i // 100 if ties else i)});"
                       for i in range(count)) or 'SELECT 1;')
    execute(db, 'COMMIT;')
    return db


def bound(sql, cutoff, limit):
    # Only the benchmark's own integer constants are substituted.
    return sql.replace('?', str(cutoff), 1).replace('?', str(limit), 1)


cases = 0
for count in [0, 1, 10, 100, 5000, 5010]:
    for ties in [False, True]:
        for limit in [1, 3, 5000]:
            for cutoff in [0, 10000, 10003, 20000]:
                a, b = database(count, ties), database(count, ties)
                try:
                    execute(a, bound(reference, cutoff, limit))
                    execute(b, bound(candidate, cutoff, limit))
                    read = 'SELECT rowid,id,occurred_at FROM action_history ORDER BY occurred_at DESC,rowid DESC'
                    assert execute(a, read, True) == execute(b, read, True), (count, ties, limit, cutoff)
                    cases += 1
                finally:
                    lib.sqlite3_close(a)
                    lib.sqlite3_close(b)

measurements = []
for ties in [False, True]:
    times = {'reference': [], 'current': []}
    for repetition in range(5):
        order = [('reference', reference), ('current', candidate)]
        for name, sql in order if repetition % 2 == 0 else reversed(order):
            db = database(5000, ties)
            try:
                statement = 'BEGIN IMMEDIATE;' + bound(sql, 0, 5000) + ';COMMIT;'
                started = time.perf_counter()
                for _ in range(100):
                    execute(db, statement)
                times[name].append(1000 * (time.perf_counter() - started) / 100)
                assert execute(db, 'SELECT COUNT(*) FROM action_history', True) == [['5000']]
            finally:
                lib.sqlite3_close(db)
    medians = {name: statistics.median(values) for name, values in times.items()}
    measurements.append({'rows': 5000, 'equal_timestamp_groups': ties,
                         'ms_per_retention_statement': times, 'median_ms': medians,
                         'reference_over_current': medians['reference'] / medians['current']})

result = {'sqlite_library': '/usr/lib/libsqlite3.dylib',
          'sqlite_version': lib.sqlite3_libversion().decode(),
          'source': str(args.source.resolve()), 'reference_sql': reference,
          'source_sha256': hashlib.sha256(source_bytes).hexdigest(),
          'current_sql': candidate, 'exact_parity_cases': cases,
          'measurements': measurements, 'limits': __doc__}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
