#!/usr/bin/env python3
"""Build/run the optimized public-API replay comparison on isolated databases.

Run swift build -c release first. Generates comparison classes from pinned Git
source without modifying that source. Never reads the user's journals/provider.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--reference-revision', default='88181f89bcb21ae88dd385f888aa3faf142b189f')
parser.add_argument('--previous-revision', default='a8cbf63aa244c178dd30a7b8319af20b3b853675')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output_dir.resolve()
if output.exists():
    parser.error('Use a fresh output directory; preserve previous evidence')
products = root / '.build/out/Products/Release'
archive = products / 'libDarkbloomTelemetry.a'
source = root / 'Sources/DarkbloomTelemetry/ActionHistoryDatabase.swift'
sources = sorted((root / 'Sources/DarkbloomTelemetry').glob('*.swift'))
if not archive.exists() or archive.stat().st_mtime < max(p.stat().st_mtime for p in sources):
    parser.error('Compile current sources with swift build -c release before benchmarking')
output.mkdir(parents=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = {'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'current_source_sha256': sha(source), 'telemetry_archive_sha256': sha(archive),
            'telemetry_sources': {str(p.relative_to(root)): sha(p) for p in sources},
            'references': {}}
references = []
for label, revision in [('Frozen', args.reference_revision), ('Previous', args.previous_revision)]:
    resolved = subprocess.check_output(['git', 'rev-parse', revision + '^{commit}'], cwd=root, text=True).strip()
    data = subprocess.check_output(['git', 'show', resolved + ':Sources/DarkbloomTelemetry/ActionHistoryDatabase.swift'], cwd=root)
    text = 'import DarkbloomTelemetry\n' + data.decode()
    text = text.replace('ActionHistoryDatabase', label + 'ActionHistoryDatabase')
    text = text.replace('ActionHistorySQLiteConnection', label + 'ActionHistorySQLiteConnection')
    text = text.replace('actionHistorySQLiteTransient', label.lower() + 'ActionHistorySQLiteTransient')
    path = output / (label + 'ActionHistoryDatabase.swift')
    path.write_text(text)
    references.append(path)
    manifest['references'][label] = {'revision': resolved,
                                     'original_sha256': hashlib.sha256(data).hexdigest(),
                                     'generated_sha256': sha(path)}

benchmark_source = root / 'Tests/PerformanceBenchmarks/ActionReplayBenchmark.swift'
manifest['benchmark_source_sha256'] = sha(benchmark_source)
binary = output / 'benchmark'
command = ['swiftc', '-O', '-swift-version', '6', '-parse-as-library', '-I', str(products),
           *map(str, references), str(benchmark_source), str(archive), '-lsqlite3', '-o', str(binary)]
manifest['compile_command'] = command
with (output / 'compile.log').open('w') as log:
    subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
assert sha(source) == manifest['current_source_sha256']
assert sha(archive) == manifest['telemetry_archive_sha256']
manifest['binary_sha256'] = sha(binary)
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with (output / 'measurements.json').open('w') as log, (output / 'runtime-errors.log').open('w') as errors:
    subprocess.run([str(binary), str(output / 'databases')], cwd=root, stdout=log,
                   stderr=errors, timeout=180, check=True)
data = json.loads((output / 'measurements.json').read_text())
assert all(row['exactRetainedEventsAndOrder'] for row in data['measurements'])
print(json.dumps(data, indent=2))
