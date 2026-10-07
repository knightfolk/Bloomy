#!/usr/bin/env python3
"""Build an isolated production-SwiftUI menu host lifecycle diagnostic.

Uses existing current telemetry products; never runs SwiftPM, launches an
app, connects to the provider, changes preferences, or downloads dependencies.
This five-case comparison does not replace the standalone 15-case motion gate.
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
DEFAULT_OUTPUT = ROOT / ".build/menu-host-lifecycle-fixture-20261003"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_hashes(root):
    return {
        str(path.relative_to(root)): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file() and not path.is_symlink()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--bundle-id", default="dev.darkbloom.menu-host-lifecycle-fixture-20261003")
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument("--target-window-style", choices=["titled", "borderless"], default="titled",
                        help="Change only the target window style for the controlled SwiftUI host comparison.")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Output already exists; preserve it and pass --output with a fresh task-owned path.")

    products = ROOT / ".build/out/Products" / args.configuration.title()
    telemetry = products / "libDarkbloomTelemetry.a"
    module = products / "DarkbloomTelemetry.swiftmodule"
    monitor_resources = products / "DarkbloomMonitor_DarkbloomMonitor.bundle"
    sparkle = products / "Sparkle.framework"
    for required in (telemetry, module, monitor_resources, sparkle):
        if not required.exists():
            parser.error(f"Missing {args.configuration} product {required}; prepare current products before building this fixture.")
    telemetry_sources = sorted((ROOT / "Sources/DarkbloomTelemetry").rglob("*.swift"))
    newer = [str(path.relative_to(ROOT)) for path in telemetry_sources
             if path.stat().st_mtime_ns > telemetry.stat().st_mtime_ns]
    if newer:
        parser.error(f"{args.configuration.title()} telemetry archive predates current source files; rebuild products first: "
                     + ", ".join(newer))

    stage = output / "staged-sources"
    stage.mkdir(parents=True, exist_ok=False)
    dependencies = output / "staged-dependencies"
    dependencies.mkdir()
    app = output / "Bloomy Menu Host Lifecycle Fixture.app"
    contents = app / "Contents"
    binary = contents / "MacOS/MenuHostLifecycleFixture"
    binary.parent.mkdir(parents=True)
    resources = contents / "Resources"
    resources.mkdir()
    frameworks = contents / "Frameworks"
    frameworks.mkdir()
    info = {
        "CFBundleIdentifier": args.bundle_id,
        "CFBundleName": "Bloomy Menu Host Lifecycle Fixture",
        "CFBundleDisplayName": "Bloomy Menu Host Lifecycle Fixture",
        "CFBundleExecutable": "MenuHostLifecycleFixture",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "diagnostic-review",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
    }
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle, sort_keys=True)
    shutil.copytree(monitor_resources, resources / monitor_resources.name, symlinks=True)
    shutil.copytree(sparkle, frameworks / sparkle.name, symlinks=True)
    if module.is_dir():
        shutil.copytree(module, dependencies / module.name, symlinks=True)
    else:
        shutil.copy2(module, dependencies / module.name)
    staged_telemetry = dependencies / telemetry.name
    shutil.copy2(telemetry, staged_telemetry)

    source_hashes = {}
    sources = []
    for source in sorted((ROOT / "Sources/DarkbloomMonitor").rglob("*.swift")):
        if source.name == "DarkbloomMonitorApp.swift":
            continue  # Exclude live production startup and provider wiring.
        source_bytes = source.read_bytes()
        source_hashes[str(source.relative_to(ROOT))] = hashlib.sha256(source_bytes).hexdigest()
        destination = stage / source.relative_to(ROOT / "Sources/DarkbloomMonitor")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source_bytes)
        sources.append(destination)
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
    fixture = ROOT / "Tests/NativeUI/MenuBarHostLifecycleFixture.swift"
    fixture_bytes = fixture.read_bytes()
    source_hashes[str(fixture.relative_to(ROOT))] = hashlib.sha256(fixture_bytes).hexdigest()
    staged_fixture = stage / fixture.name
    staged_fixture.write_bytes(fixture_bytes)

    cover_source = ROOT / "Tests/NativeUI/MenuBarOpaqueCoverFixture.swift"
    staged_cover = stage / cover_source.name
    staged_cover.write_bytes(cover_source.read_bytes())
    source_hashes[str(cover_source.relative_to(ROOT))] = sha256(cover_source)
    cover_app = output / "Bloomy Menu Cover Fixture.app"
    cover_contents = cover_app / "Contents"
    cover_binary = cover_contents / "MacOS/MenuBarOpaqueCoverFixture"
    cover_binary.parent.mkdir(parents=True)
    cover_info = {"CFBundleIdentifier": args.bundle_id + ".cover",
                  "CFBundleName": "Bloomy Menu Cover Fixture",
                  "CFBundleExecutable": "MenuBarOpaqueCoverFixture",
                  "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0"}
    with (cover_contents / "Info.plist").open("wb") as handle:
        plistlib.dump(cover_info, handle)

    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    cover_command = ["swiftc", "-target", f"{arch}-apple-macosx14.0", "-swift-version", "6",
                     "-parse-as-library", str(staged_cover), "-framework", "AppKit", "-o", str(cover_binary)]
    command = ["swiftc", "-target", f"{arch}-apple-macosx14.0", "-swift-version", "6",
               "-parse-as-library", "-D", "DEBUG", "-I", str(dependencies), "-F", str(frameworks),
               *(["-O"] if args.configuration == "release" else []),
               *(["-D", "FIXTURE_BORDERLESS_TARGET"] if args.target_window_style == "borderless" else []),
               str(staged_fixture), *map(str, sources), str(staged_telemetry), "-framework", "Sparkle",
               "-lsqlite3", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
               "-o", str(binary)]
    manifest = {
        "fixture": str(app), "bundle_id": args.bundle_id, "synthetic": True,
        "diagnostic_comparison_only": True, "replaces_standalone_15_case_gate": False,
        "distribution": False, "provider_connected": False,
        "configuration": args.configuration, "target_window_style": args.target_window_style,
        "source_sha256": source_hashes,
        "telemetry_source_sha256": {str(path.relative_to(ROOT)): sha256(path) for path in telemetry_sources},
        "staged_source_sha256": file_hashes(stage),
        "dependency_sha256": file_hashes(dependencies),
        "resource_sha256": file_hashes(resources),
        "framework_sha256": file_hashes(frameworks),
        "telemetry_archive_sha256": sha256(staged_telemetry),
        "telemetry_archive_source": str(telemetry),
        "compiler_command": command,
        "cover_fixture": str(cover_app), "cover_bundle_id": cover_info["CFBundleIdentifier"],
        "cover_compiler_command": cover_command,
        "required_cases": ["visible_active_compositor_advances", "same_window_close_and_reopen",
                           "rapid_same_window_close_and_reopen", "swiftui_dismantle_retained_view",
                           "distinct_app_genuine_occlusion_and_restore"],
        "status_location_pattern": "NSTemporaryDirectory()/BloomyMenuHostLifecycle-<pid>-<uuid>/host-lifecycle-proof.json",
        "trigger": "Native Run lifecycle diagnostic button; one finite run per launch",
        "status": "staged",
    }
    manifest_path = output / "fixture-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    try:
        subprocess.run(cover_command, cwd=ROOT, check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(cover_app)], check=True)
        subprocess.run(command, cwd=ROOT, check=True)
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    except subprocess.CalledProcessError:
        manifest["status"] = "build-failed"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        raise
    manifest["binary_sha256"] = sha256(binary)
    manifest["cover_binary_sha256"] = sha256(cover_binary)
    manifest["status"] = "built-local-diagnostic"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(app)
    print(manifest_path)


if __name__ == "__main__":
    main()
