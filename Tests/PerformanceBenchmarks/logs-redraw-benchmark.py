#!/usr/bin/env python3
"""Observe native Logs derivations under unrelated parent publications.

Exact product views and dependencies are copied; only the staged presentation
gets a counter. No provider, live logs, export action, telemetry or sensors run.
"""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
if out.exists():
    parser.error('Preserve earlier evidence and choose a fresh output directory.')
out.mkdir(parents=True)
products = root / '.build/out/Products/Release'
sources = ['Sources/DarkbloomMonitor/Dashboard/LogsView.swift',
           'Sources/DarkbloomMonitor/Dashboard/LogsPresentation.swift',
           'Sources/DarkbloomMonitor/Dashboard/LogExportPreviewView.swift',
           'Sources/DarkbloomMonitor/Components/EventRow.swift']
hashes = {}
for name in sources:
    original = (root / name).read_bytes()
    hashes[name] = hashlib.sha256(original).hexdigest()
    staged = original.decode()
    if name.endswith('/LogsPresentation.swift'):
        assert staged.count('struct LogsPresentation {') == 1
        assert staged.count('        var compactFormatter: DateFormatter?') == 1
        staged = staged.replace('struct LogsPresentation {',
            'struct LogsPresentation {\n    nonisolated(unsafe) static var benchmarkDerivations = 0')
        staged = staged.replace('        var compactFormatter: DateFormatter?',
            '        benchmarkDerivations += 1\n        var compactFormatter: DateFormatter?')
    (out / Path(name).name).write_text(staged)
library = out / 'libDarkbloomTelemetry.a'
shutil.copy2(products / library.name, library)
(out / 'Harness.swift').write_text(r'''
import AppKit
import SwiftUI
@testable import DarkbloomTelemetry

@MainActor final class Driver: ObservableObject {
    @Published var tick = 0
    @Published var feed: SourceAvailability<EventFeed>
    init() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let events = (0..<100).map { i in
            LogEvent(timestamp: date.addingTimeInterval(Double(i)), severity: .info,
                category: "Inert", message: "Synthetic event \(i)", source: .unified,
                processID: 1, processImage: "synthetic")
        }
        feed = .available(value: EventFeed(events: events, legacyReadAt: date, unifiedActivityAt: date), capturedAt: date)
    }
}

struct Parent: View {
    @ObservedObject var driver: Driver
    var body: some View {
        VStack { Text("Unrelated reading \(driver.tick)"); LogsView(feed: driver.feed) }
    }
}

@main @MainActor struct Harness {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let driver = Driver()
            let host = NSHostingController(rootView: Parent(driver: driver))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = host
            window.orderBack(nil)
            try? await Task.sleep(for: .milliseconds(100))
            host.view.layoutSubtreeIfNeeded()
            let initial = LogsPresentation.benchmarkDerivations
            let before = LogsPresentation.benchmarkDerivations
            for tick in 1...30 {
                driver.tick = tick
                try? await Task.sleep(for: .milliseconds(50))
                host.view.layoutSubtreeIfNeeded()
            }
            let unrelated = LogsPresentation.benchmarkDerivations - before
            let beforeFeed = LogsPresentation.benchmarkDerivations
            if case .available(let feed, let date) = driver.feed {
                driver.feed = .stale(value: feed, capturedAt: date, reason: "Controlled source failure")
            }
            try? await Task.sleep(for: .milliseconds(50))
            host.view.layoutSubtreeIfNeeded()
            let changed = LogsPresentation.benchmarkDerivations - beforeFeed
            precondition(initial > 0 && changed > 0, "Native view did not evaluate the presentation")
            let report = ["initial_derivations": initial, "unrelated_publications": 30,
                "unrelated_derivations": unrelated, "changed_feed_derivations": changed]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
            window.close()
            app.terminate(nil)
        }
        app.run()
    }
}
''')
arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
binary = out / 'LogsRedrawBenchmark'
command = ['swiftc', '-swift-version', '6', '-parse-as-library', '-O',
           '-target', f'{arch}-apple-macosx14.0', '-I', str(products),
           str(out/'Harness.swift'), *[str(out/Path(p).name) for p in sources],
           str(library), '-lsqlite3', '-o', str(binary)]
subprocess.run(command, check=True)
result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=15)
report = {'synthetic': True, 'distribution': False, 'source_sha256': hashes,
          'telemetry_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
          'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'counter_only_staging': True, 'measurement': json.loads(result.stdout),
          'stderr': result.stderr}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
