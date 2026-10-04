#!/usr/bin/env python3
"""Finite native popup-sizing burst comparison; no provider or live telemetry.

Pass an exact before/after FittingPopoverHostingController.swift and a fresh
output directory. Only the staged copy receives a measurement counter. This
stress workload is not a whole-app CPU or ordinary one-second-update estimate.
"""
import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output.exists():
    parser.error('Output exists; preserve it and choose a fresh directory.')
output.mkdir(parents=True)
source = args.source.read_text()
assert source.count('    func measureDocument() {\n') == 1
assert source.count('    private var documentSize = NSSize.zero') == 1
instrumented = source.replace('    private var documentSize = NSSize.zero',
    '    var forcedMeasurementCount = 0\n    private var documentSize = NSSize.zero')
instrumented = instrumented.replace('    func measureDocument() {\n',
    '    func measureDocument() {\n        forcedMeasurementCount += 1\n')
(output / 'Sizing.swift').write_text(instrumented)
(output / 'Harness.swift').write_text(r'''
import AppKit
import SwiftUI

struct Reading: View {
    let height: CGFloat
    let label: String
    var body: some View { Text(label).frame(maxWidth: .infinity).frame(height: height) }
}

@main @MainActor struct Harness {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let scroll = PopupScrollView(content: Reading(height: 120, label: "Initial"),
                environment: EnvironmentValues(), width: 528, maximumHeight: 360)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 360),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            window.orderBack(nil)
            try? await Task.sleep(for: .milliseconds(100))
            var reports: [[String: Double]] = []
            for height: CGFloat in [220, 460, 96, 380, 120] {
                let before = scroll.forcedMeasurementCount
                let start = ProcessInfo.processInfo.systemUptime
                for reading in 0..<300 {
                    scroll.update(content: Reading(height: height, label: "Reading \(reading)"),
                        environment: EnvironmentValues(), width: 528, maximumHeight: 360)
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                for _ in 0..<100 {
                    scroll.layoutSubtreeIfNeeded()
                    if scroll.documentView?.frame.height == height { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                try? await Task.sleep(for: .milliseconds(20))
                let actual = scroll.documentView?.frame.height ?? -1
                let viewport = scroll.intrinsicContentSize.height
                precondition(actual == height && viewport == min(height, 360), "Document sizing regressed")
                reports.append(["updates": 300, "height": height,
                    "burst_ms": elapsed * 1000,
                    "forced_fits": Double(scroll.forcedMeasurementCount - before),
                    "document_height": actual, "viewport_height": viewport])
            }
            let encoded = try! JSONSerialization.data(withJSONObject: reports, options: [.sortedKeys])
            print(String(decoding: encoded, as: UTF8.self))
            scroll.invalidate()
            window.close()
            app.terminate(nil)
        }
        app.run()
    }
}
''')
arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
binary = output / 'PopupSizingBenchmark'
subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-O',
    '-target', f'{arch}-apple-macosx14.0', str(output/'Sizing.swift'),
    str(output/'Harness.swift'), '-o', str(binary)], check=True)
result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
report = {'synthetic': True, 'distribution': False, 'source': str(args.source.resolve()),
    'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
    'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'batches': json.loads(result.stdout), 'stderr': result.stderr}
(output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'report': str(output/'report.json'), 'batches': report['batches']}, indent=2))
