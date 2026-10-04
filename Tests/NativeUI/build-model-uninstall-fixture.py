#!/usr/bin/env python3
"""Build an isolated native review app for ModelManagerView uninstall cards.

The fixture uses the checked-out production SwiftUI sources and the current
SwiftPM Debug telemetry products. It never connects to the provider. The
telemetry archive is checked for the current cache-bound deletion gates before use.
"""
import argparse
import hashlib
import json
import platform
import plistlib
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / ".build/model-uninstall-review-20261003"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
parser.add_argument("--bundle-id", default="dev.darkbloom.model-uninstall-review-20261003")
args = parser.parse_args()
output = args.output.resolve()
if output.exists():
    parser.error(
        "Output already exists; preserve it for provenance and pass --output "
        "with a fresh task-owned path."
    )

products = ROOT / ".build/out/Products/Debug"
telemetry = products / "libDarkbloomTelemetry.a"
telemetry_module = products / "DarkbloomTelemetry.swiftmodule"
monitor_resources = products / "DarkbloomMonitor_DarkbloomMonitor.bundle"
sparkle = products / "Sparkle.framework"
for required in (telemetry, telemetry_module, monitor_resources, sparkle):
    if not required.exists():
        parser.error(
            f"Missing current SwiftPM Debug product {required}; rebuild the "
            "Debug target and tests before building this fixture."
        )

# The UI source references this new safety gate. An old archive can appear
# buildable against a newer module but fail during linking or omit the current
# deletion preflight, so fail before staging anything if the symbol is absent.
symbols = subprocess.run(
    ["nm", "-gU", str(telemetry)], check=True, capture_output=True, text=True
)
demangled = subprocess.run(
    ["swift", "demangle"],
    input=symbols.stdout,
    check=True,
    capture_output=True,
    text=True,
)
required_symbols = (
    "ProviderControlSnapshot.runtimeDeletionBlockReason(for: Swift.String)",
    "ProviderControlService.performDelete(_: Swift.String, expectedCacheDirectory: Swift.String",
)
missing_symbols = [symbol for symbol in required_symbols if symbol not in demangled.stdout]
if missing_symbols:
    parser.error(
        "Debug telemetry archive is missing current uninstall safety symbols "
        f"({', '.join(missing_symbols)}). Rebuild SwiftPM Debug products before "
        "fixture compilation."
    )

stage = output / "staged-sources"
stage.mkdir(parents=True, exist_ok=False)
app = output / "Bloomy Model Uninstall Fixture.app"
contents = app / "Contents"
binary = contents / "MacOS/ModelUninstallFixture"
binary.parent.mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
frameworks = contents / "Frameworks"
frameworks.mkdir(exist_ok=True)

bundle_id = args.bundle_id
info = {
    "CFBundleIdentifier": bundle_id,
    "CFBundleName": "Bloomy Model Uninstall Fixture",
    "CFBundleDisplayName": "Bloomy Model Uninstall Fixture",
    "CFBundleExecutable": "ModelUninstallFixture",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "synthetic-review",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
}
with (contents / "Info.plist").open("wb") as handle:
    plistlib.dump(info, handle, sort_keys=True)

shutil.copytree(
    monitor_resources,
    resources / monitor_resources.name,
    dirs_exist_ok=True,
)
shutil.copytree(sparkle, frameworks / sparkle.name, symlinks=True, dirs_exist_ok=True)

hashes = {}
sources = []
for source in sorted((ROOT / "Sources/DarkbloomMonitor").rglob("*.swift")):
    if source.name == "DarkbloomMonitorApp.swift":
        continue  # Do not include live production startup wiring.
    source_bytes = source.read_bytes()
    hashes[str(source.relative_to(ROOT))] = hashlib.sha256(source_bytes).hexdigest()
    destination = stage / source.relative_to(ROOT / "Sources/DarkbloomMonitor")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(source_bytes)
    sources.append(destination)

accessor = stage / "fixture_resource_bundle_accessor.swift"
accessor.write_text(
    '''import Foundation
extension Bundle {
    static let module: Bundle = {
        let url = Bundle.main.resourceURL!.appendingPathComponent("DarkbloomMonitor_DarkbloomMonitor.bundle")
        guard let bundle = Bundle(url: url) else { fatalError("Fixture resources missing") }
        return bundle
    }()
}
'''
)
sources.append(accessor)

fixture = ROOT / "Tests/NativeUI/ModelUninstallFixture.swift"
fixture_bytes = fixture.read_bytes()
hashes[str(fixture.relative_to(ROOT))] = hashlib.sha256(fixture_bytes).hexdigest()
staged_fixture = stage / fixture.name
staged_fixture.write_bytes(fixture_bytes)

staged_telemetry = stage / telemetry.name
shutil.copy2(telemetry, staged_telemetry)
arch = "arm64" if platform.machine() == "arm64" else "x86_64"
command = [
    "swiftc",
    "-target",
    f"{arch}-apple-macosx14.0",
    "-swift-version",
    "6",
    "-parse-as-library",
    "-D",
    "DEBUG",
    "-I",
    str(products),
    "-F",
    str(products),
    str(staged_fixture),
    *map(str, sources),
    str(staged_telemetry),
    "-framework",
    "Sparkle",
    "-lsqlite3",
    "-Xlinker",
    "-rpath",
    "-Xlinker",
    "@executable_path/../Frameworks",
    "-o",
    str(binary),
]
subprocess.run(command, cwd=ROOT, check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)

manifest = {
    "fixture": str(app),
    "bundle_id": bundle_id,
    "synthetic": True,
    "distribution": False,
    "source_sha256": hashes,
    "telemetry_archive_sha256": hashlib.sha256(staged_telemetry.read_bytes()).hexdigest(),
    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "compiler_command": command,
    "status_location_pattern": "NSTemporaryDirectory()/BloomyModelUninstallReview-<pid>-<uuid>/status.json",
    "status_fields": [
        "deleteCallCount",
        "weightsFileExists",
        "simulatedWriterBusy",
        "lastDeleteOutcome",
        "fixtureStorageReady",
    ],
}
(output / "fixture-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(app)
print(output / "fixture-manifest.json")
