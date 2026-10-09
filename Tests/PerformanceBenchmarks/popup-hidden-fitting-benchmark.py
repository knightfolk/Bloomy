#!/usr/bin/env python3
"""Finite matched popup fitting experiment, using inert native content.

Count explicit document-host sizeThatFits calls in a staged copy of an exact
source file. The baseline receives an unused environment key so the workload is
identical. This is not a whole-app CPU, automatic-layout, or energy measurement.
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
    parser.error('Choose a fresh output directory to preserve earlier evidence.')
output.mkdir(parents=True)
source = args.source.read_text()
needle = '        setDocumentSize(host.sizeThatFits(in: NSSize(width: contentWidth, height: 0)))'
assert source.count(needle) == 1, 'Actual explicit document fit must have one instrumentation site'
assert source.count('    private var documentSize = NSSize.zero') == 1
staged = source.replace('    private var documentSize = NSSize.zero',
    '    var explicitDocumentFitCount = 0\n    private var documentSize = NSSize.zero')
staged = staged.replace(needle, '        explicitDocumentFitCount += 1\n' + needle)
compatibility_key = 'var popupFittingActive:' not in source
if compatibility_key:
    staged += '''
private struct BenchmarkInactiveFittingKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var popupFittingActive: Bool {
        get { self[BenchmarkInactiveFittingKey.self] }
        set { self[BenchmarkInactiveFittingKey.self] = newValue }
    }
}
'''
(output / 'Sizing.swift').write_text(staged)
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
            var environment = EnvironmentValues()
            let scroll = PopupScrollView(content: Reading(height: 460, label: "Initial"),
                environment: environment, width: 528, maximumHeight: 180)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 180),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            window.orderBack(nil)
            try? await Task.sleep(for: .milliseconds(100))
            scroll.measureDocument()
            scroll.layoutSubtreeIfNeeded()
            let document = scroll.documentView!
            document.scroll(NSPoint(x: 0, y: 25))
            let retainedOrigin = scroll.contentView.bounds.origin
            let before = scroll.explicitDocumentFitCount
            environment.popupFittingActive = false
            // Switch the presentation input before allowing another actor turn.
            scroll.update(content: Reading(height: 460, label: "Closed"),
                environment: environment, width: 528, maximumHeight: 180)
            try? await Task.sleep(for: .milliseconds(30))
            var batches: [[String: Double]] = []
            for height: CGFloat in [220, 460, 96, 380, 460] {
                let startCount = scroll.explicitDocumentFitCount
                let start = ProcessInfo.processInfo.systemUptime
                for reading in 0..<300 {
                    scroll.update(content: Reading(height: height, label: "Hidden \(reading)"),
                        environment: environment, width: 528, maximumHeight: 180)
                    // Exercise explicit sizing requests too: hidden state must gate them.
                    if reading % 60 == 0 { scroll.measureDocument() }
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                try? await Task.sleep(for: .milliseconds(30))
                scroll.layoutSubtreeIfNeeded()
                batches.append(["updates": 300, "height": height,
                    "burst_ms": elapsed * 1000,
                    "explicit_fits": Double(scroll.explicitDocumentFitCount - startCount),
                    "document_height": document.frame.height])
            }
            let hiddenFits = scroll.explicitDocumentFitCount - before
            let identityWhileClosed = scroll.documentView === document
            let closedOrigin = scroll.contentView.bounds.origin
            environment.popupFittingActive = true
            let beforeReopen = scroll.explicitDocumentFitCount
            scroll.update(content: Reading(height: 520, label: "Reopened latest"),
                environment: environment, width: 400, maximumHeight: 80)
            scroll.measureDocument()
            scroll.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
            precondition(scroll.documentView === document && document.frame.size == NSSize(width: 400, height: 520))
            precondition(scroll.intrinsicContentSize == NSSize(width: 400, height: 80))
            let report: [String: Any] = [
                "hidden_updates": 1501, "hidden_explicit_fits": hiddenFits,
                "hidden_batches": batches, "retained_document": identityWhileClosed,
                "closed_scroll_unchanged": retainedOrigin == closedOrigin,
                "reopen_explicit_fits": scroll.explicitDocumentFitCount - beforeReopen,
                "reopen_document_width": document.frame.width,
                "reopen_document_height": document.frame.height,
                "reopen_viewport_height": scroll.intrinsicContentSize.height]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
            scroll.invalidate()
            window.close()
            app.terminate(nil)
        }
        app.run()
    }
}
''')
arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
binary = output / 'PopupHiddenFittingBenchmark'
subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-O',
    '-target', f'{arch}-apple-macosx14.0', str(output/'Sizing.swift'),
    str(output/'Harness.swift'), '-o', str(binary)], check=True)
result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
report = {'synthetic': True, 'distribution': False, 'source': str(args.source.resolve()),
    'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
    'staged_sha256': hashlib.sha256(staged.encode()).hexdigest(),
    'baseline_unused_compatibility_key': compatibility_key,
    'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'measurement': json.loads(result.stdout), 'stderr': result.stderr}
(output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
