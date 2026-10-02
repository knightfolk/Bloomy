#!/usr/bin/env python3
"""Build a small isolated native review app using existing debug telemetry.

Production source files are never edited. The staged copies replace exactly
three autonomous default dependencies; all destination view bodies are unchanged.
"""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=ROOT / ".build/native-dashboard-fixture")
args = parser.parse_args()
output = args.output.resolve()
if output.exists():
    parser.error("Output already exists; preserve it for provenance and pass --output with a fresh task-owned path.")
products = ROOT / ".build/out/Products/Debug"
telemetry = products / "libDarkbloomTelemetry.a"
if not telemetry.is_file():
    parser.error("Expected existing .build/out/Products/Debug/libDarkbloomTelemetry.a; run the project debug test/build first.")
sparkle = products / "Sparkle.framework"
if not sparkle.is_dir():
    parser.error("Expected existing debug Sparkle.framework.")
stage = output / "staged-sources"
stage.mkdir(parents=True, exist_ok=True)
app = output / "Bloomy Dashboard Fixture.app"
contents = app / "Contents"
binary = contents / "MacOS/DashboardFixture"
binary.parent.mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
frameworks = contents / "Frameworks"
frameworks.mkdir(exist_ok=True)
shutil.copy2(ROOT / "Tests/NativeUI/DashboardFixture-Info.plist", contents / "Info.plist")
shutil.copytree(products / "DarkbloomMonitor_DarkbloomMonitor.bundle",
                resources / "DarkbloomMonitor_DarkbloomMonitor.bundle", dirs_exist_ok=True)
shutil.copytree(sparkle, frameworks / "Sparkle.framework", symlinks=True, dirs_exist_ok=True)

substitutions = {
    "CLIUpdateNoticeView.swift": (
        "static let shared = CLIUpdateStatusStore()",
        "static let shared = CLIUpdateStatusStore(client: FixtureCLIUpdates.shared)"),
    "SystemCPUUsageStore.swift": (
        "read: @escaping @MainActor () -> SystemCPUTimes? = MacHostCPUSampler.read",
        "read: @escaping @MainActor () -> SystemCPUTimes? = { nil }"),
    "NetworkCacheView.swift": (
        "init(client: any NetworkCacheFetching = NetworkCacheClient())",
        "init(client: any NetworkCacheFetching = FixtureNetworkCache())"),
}
hashes = {}
sources = []
for source in sorted((ROOT / "Sources/DarkbloomMonitor").rglob("*.swift")):
    if source.name == "DarkbloomMonitorApp.swift":
        continue  # Production app entry point owns all live start-up wiring.
    source_bytes = source.read_bytes()
    text = source_bytes.decode("utf-8")
    hashes[str(source.relative_to(ROOT))] = hashlib.sha256(source_bytes).hexdigest()
    if source.name in substitutions:
        before, after = substitutions[source.name]
        if text.count(before) != 1:
            parser.error(f"Safety substitution drifted: {source}")
        text = text.replace(before, after)
    destination = stage / source.relative_to(ROOT / "Sources/DarkbloomMonitor")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text)
    sources.append(destination)

# Same lookup contract as SwiftPM, with only the packaged fixture bundle as
# a resource source; no development-directory fallback is needed.
accessor = stage / "fixture_resource_bundle_accessor.swift"
accessor.write_text('''import Foundation
extension Bundle {
    static let module: Bundle = {
        let url = Bundle.main.resourceURL!.appendingPathComponent("DarkbloomMonitor_DarkbloomMonitor.bundle")
        guard let bundle = Bundle(url: url) else { fatalError("Fixture resources missing") }
        return bundle
    }()
}
''')
sources.append(accessor)
fixture = ROOT / "Tests/NativeUI/DashboardFixture.swift"
fixture_bytes = fixture.read_bytes()
hashes[str(fixture.relative_to(ROOT))] = hashlib.sha256(fixture_bytes).hexdigest()
staged_fixture = stage / fixture.name
staged_fixture.write_bytes(fixture_bytes)
for helper in sorted((ROOT / "Tests/NativeUI").glob("*Proof.swift")):
    helper_bytes = helper.read_bytes()
    hashes[str(helper.relative_to(ROOT))] = hashlib.sha256(helper_bytes).hexdigest()
    staged_helper = stage / helper.name
    staged_helper.write_bytes(helper_bytes)
    sources.append(staged_helper)
# Link the same immutable bytes that the manifest identifies, even if an
# independent debug build refreshes the original products during compilation.
staged_telemetry = stage / telemetry.name
shutil.copy2(telemetry, staged_telemetry)
arch = "arm64" if platform.machine() == "arm64" else "x86_64"
command = ["swiftc", "-target", f"{arch}-apple-macosx14.0", "-swift-version", "6",
           "-parse-as-library", "-D", "DEBUG", "-I", str(products), "-F", str(products),
           str(staged_fixture), *map(str, sources), str(staged_telemetry), "-framework", "Sparkle", "-lsqlite3",
           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-o", str(binary)]
subprocess.run(command, cwd=ROOT, check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
manifest = {
    "fixture": str(app), "synthetic": True, "distribution": False,
    "source_sha256": hashes,
    "dependency_substitutions": {name: {"before": pair[0], "after": pair[1]}
                                 for name, pair in substitutions.items()},
    "telemetry_library_sha256": hashlib.sha256(staged_telemetry.read_bytes()).hexdigest(),
    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "compiler_command": command,
}
(output / "fixture-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(app)
print(output / "fixture-manifest.json")
