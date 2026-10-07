#!/usr/bin/env python3
"""Build a small isolated native review app using existing telemetry products.

Production source files are never edited. Normal staging replaces exactly
three autonomous default dependencies without changing destination view bodies.
Opt-in motion diagnostics additionally stage guarded lifetime/callback overlays.
Run swift test in the chosen configuration first for testable telemetry products.
"""
import argparse
import hashlib
import json
import platform
import shutil
import sqlite3
import subprocess
from pathlib import Path
from MenuBarMotionComparison import stage_comparison
from MenuBarRenderHistory import stage_render_history
from MenuBarDetachCadence import stage_detach_cadence
from MenuBarWindowTrace import stage_trace_report, stage_window_trace
from StatusItemHostStaging import stage_status_item_access

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=ROOT / ".build/native-dashboard-fixture")
parser.add_argument("--hide-review-banner", action="store_true",
                    help="Omit fixture controls to inspect the dashboard's own keyboard entry.")
parser.add_argument("--compact", action="store_true", help="Start the isolated window at 800 x 560.")
parser.add_argument("--configuration", choices=["debug", "release"], default="debug",
                    help="Release optimizes the fixture and production views for bounded profiling.")
parser.add_argument("--metrics-seed", type=Path,
                    help="Bundle a completed synthetic performance SQLite seed for the Fresh scenario only.")
parser.add_argument("--motion-target-lifetime", choices=["reused", "fresh", "reset-before-detach"],
                    help="Opt-in diagnostic overlay; compare reused targets, fresh targets or one reset before detach.")
parser.add_argument("--motion-window-trace", action="store_true",
                    help="Bounded staged native callback trace; requires a target-lifetime comparison.")
parser.add_argument("--production-status-item-proof", action="store_true",
                    help="Separate inert real-status-item diagnostic; does not replace the normal native gate.")
parser.add_argument("--settings-preview-proof", action="store_true",
                    help="Observe the actual dashboard Settings preview through navigation and retained-window reopening.")
parser.add_argument("--detach-history-proof", action="store_true",
                    help="Separate counterbalanced native detach versus continuously attached diagnostic.")
parser.add_argument("--motion-render-history", choices=["display-flush", "compositor-only"],
                    help="Matched staged comparison of the four early angle observations only.")
parser.add_argument("--motion-detach-cadence", choices=["immediate", "compositor-observed", "delay-only"],
                    help="Matched staged detach-to-close cadence comparison; original reopen bodies unchanged.")
args = parser.parse_args()
if args.motion_detach_cadence and (args.motion_render_history or args.detach_history_proof or args.settings_preview_proof or args.production_status_item_proof or args.motion_target_lifetime or args.motion_window_trace or args.hide_review_banner):
    parser.error("Detach cadence comparison requires visible controls and no other motion diagnostics.")
if args.motion_render_history and (args.detach_history_proof or args.settings_preview_proof or args.production_status_item_proof or args.motion_target_lifetime or args.motion_window_trace or args.hide_review_banner):
    parser.error("Render history comparison requires visible controls and no other motion diagnostics.")
if args.detach_history_proof and (args.settings_preview_proof or args.production_status_item_proof or args.motion_target_lifetime or args.motion_window_trace or args.hide_review_banner):
    parser.error("Detach history proof requires visible controls and no other motion diagnostics.")
if args.motion_window_trace and not args.motion_target_lifetime:
    parser.error("Window trace requires an explicit diagnostic target-lifetime comparison.")
if args.production_status_item_proof and (args.motion_target_lifetime or args.motion_window_trace or args.hide_review_banner):
    parser.error("Real status-item proof requires its visible review controls and no motion comparison overlays.")
if args.settings_preview_proof and (args.production_status_item_proof or args.motion_target_lifetime or args.motion_window_trace or args.hide_review_banner):
    parser.error("Settings preview proof requires visible controls and no other motion diagnostics.")
output = args.output.resolve()
if output.exists():
    parser.error("Output already exists; preserve it for provenance and pass --output with a fresh task-owned path.")
metrics_seed = None
if args.metrics_seed:
    metrics_seed = args.metrics_seed.resolve()
    if not metrics_seed.is_file() or Path(str(metrics_seed) + "-wal").exists():
        parser.error("Pass a closed, checkpointed synthetic seed, without a live WAL writer.")
    with sqlite3.connect(metrics_seed.as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        if connection.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            parser.error("Synthetic seed integrity check failed.")
        seed_rows = connection.execute("SELECT COUNT(*) FROM performance_history").fetchone()[0]
        if not 1 <= seed_rows <= 100_000:
            parser.error("Synthetic seed must contain 1–100,000 performance rows.")
products = ROOT / ".build/out/Products" / args.configuration.title()
telemetry = products / "libDarkbloomTelemetry.a"
if not telemetry.is_file():
    parser.error(f"Expected existing {telemetry}; run swift test -c {args.configuration} first.")
sparkle = products / "Sparkle.framework"
if not sparkle.is_dir():
    parser.error(f"Expected existing {args.configuration} Sparkle.framework.")
module_check = subprocess.run(["swiftc", "-I", str(products), "-typecheck", "-e",
                               "@testable import DarkbloomTelemetry"], capture_output=True, text=True)
if module_check.returncode:
    parser.error(f"Telemetry must support the fixture's test-only constructors; run swift test -c {args.configuration} first.\n{module_check.stderr}")
stage = output / "staged-sources"
stage.mkdir(parents=True, exist_ok=True)
app = output / "Bloomy Dashboard Fixture.app"
contents = app / "Contents"
binary = contents / "MacOS/DashboardFixture"
binary.parent.mkdir(parents=True, exist_ok=True)
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
if metrics_seed:
    shutil.copy2(metrics_seed, resources / "fixture-performance-seed.sqlite")
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
window_trace = None
status_item_access = None
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
    if source.name == "MenuBarLabel.swift" and args.motion_window_trace:
        try:
            text = stage_window_trace(text)
        except ValueError as error:
            parser.error(str(error))
        window_trace = {"original_sha256": hashes[str(source.relative_to(ROOT))],
                        "staged_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                        "capacity_per_view": 512, "diagnostic_only": True}
    if source.name == "StatusItemController.swift" and args.production_status_item_proof:
        try:
            text = stage_status_item_access(text)
        except ValueError as error:
            parser.error(str(error))
        status_item_access = {"original_sha256": hashes[str(source.relative_to(ROOT))],
                              "staged_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                              "diagnostic_only": True, "replaces_normal_native_gate": False}
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
motion_comparison = None
render_history = None
detach_cadence = None
for helper in sorted((ROOT / "Tests/NativeUI").glob("*Proof.swift")):
    helper_bytes = helper.read_bytes()
    hashes[str(helper.relative_to(ROOT))] = hashlib.sha256(helper_bytes).hexdigest()
    staged_helper = stage / helper.name
    if helper.name == "MenuBarMotionProof.swift" and args.motion_target_lifetime:
        try:
            comparison_text = stage_comparison(helper_bytes.decode("utf-8"))
            if args.motion_window_trace:
                comparison_text = stage_trace_report(comparison_text)
            comparison_bytes = comparison_text.encode("utf-8")
        except ValueError as error:
            parser.error(str(error))
        staged_helper.write_bytes(comparison_bytes)
        motion_comparison = {"target_lifetime": args.motion_target_lifetime,
                            "original_sha256": hashes[str(helper.relative_to(ROOT))],
                            "staged_sha256": hashlib.sha256(comparison_bytes).hexdigest(),
                            "diagnostic_only": True, "replaces_normal_native_gate": False}
    elif helper.name == "MenuBarMotionProof.swift" and args.motion_render_history:
        try:
            staged_bytes = stage_render_history(helper_bytes.decode("utf-8")).encode("utf-8")
        except ValueError as error:
            parser.error(str(error))
        staged_helper.write_bytes(staged_bytes)
        render_history = {"early_angle_observation": args.motion_render_history,
                          "original_sha256": hashes[str(helper.relative_to(ROOT))],
                          "staged_sha256": hashlib.sha256(staged_bytes).hexdigest(),
                          "diagnostic_only": True, "replaces_normal_native_gate": False}
    elif helper.name == "MenuBarMotionProof.swift" and args.motion_detach_cadence:
        try:
            staged_bytes = stage_detach_cadence(helper_bytes.decode("utf-8")).encode("utf-8")
        except ValueError as error:
            parser.error(str(error))
        staged_helper.write_bytes(staged_bytes)
        detach_cadence = {"mode": args.motion_detach_cadence,
                          "original_sha256": hashes[str(helper.relative_to(ROOT))],
                          "staged_sha256": hashlib.sha256(staged_bytes).hexdigest(),
                          "diagnostic_only": True, "replaces_normal_native_gate": False}
    else:
        staged_helper.write_bytes(helper_bytes)
    sources.append(staged_helper)
# Link the same immutable bytes that the manifest identifies, even if an
# independent build refreshes the original products during compilation.
staged_telemetry = stage / telemetry.name
shutil.copy2(telemetry, staged_telemetry)
arch = "arm64" if platform.machine() == "arm64" else "x86_64"
command = ["swiftc", "-target", f"{arch}-apple-macosx14.0", "-swift-version", "6",
           "-parse-as-library", *(["-O"] if args.configuration == "release" else ["-Onone", "-D", "DEBUG"]),
           *(["-D", "FIXTURE_HIDE_REVIEW_BANNER"] if args.hide_review_banner else []),
           *(["-D", "FIXTURE_COMPACT"] if args.compact else []),
           *(["-D", "FIXTURE_FRESH_MOTION_TARGETS"] if args.motion_target_lifetime == "fresh" else []),
           *(["-D", "FIXTURE_RESET_BEFORE_DETACH"] if args.motion_target_lifetime == "reset-before-detach" else []),
           *(["-D", "FIXTURE_MOTION_WINDOW_TRACE"] if args.motion_window_trace else []),
           *(["-D", "FIXTURE_PRODUCTION_STATUS_ITEM_PROOF"] if args.production_status_item_proof else []),
           *(["-D", "FIXTURE_SETTINGS_PREVIEW_PROOF"] if args.settings_preview_proof else []),
           *(["-D", "FIXTURE_DETACH_HISTORY_PROOF"] if args.detach_history_proof else []),
           *(["-D", "FIXTURE_COMPOSITOR_ONLY_HISTORY"] if args.motion_render_history == "compositor-only" else []),
           *(["-D", "FIXTURE_OBSERVED_DETACH_CADENCE"] if args.motion_detach_cadence == "compositor-observed" else []),
           *(["-D", "FIXTURE_DELAY_ONLY_DETACH_CADENCE"] if args.motion_detach_cadence == "delay-only" else []),
           "-I", str(products), "-F", str(products),
           str(staged_fixture), *map(str, sources), str(staged_telemetry), "-framework", "Sparkle", "-lsqlite3",
           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-o", str(binary)]
subprocess.run(command, cwd=ROOT, check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
manifest = {
    "fixture": str(app), "synthetic": True, "distribution": False,
    "build_configuration": args.configuration,
    "view_optimization": "-O" if args.configuration == "release" else "-Onone",
    "review_banner_visible": not args.hide_review_banner, "initial_compact": args.compact,
    "source_sha256": hashes,
    "motion_target_comparison": motion_comparison,
    "motion_render_history": render_history,
    "motion_detach_cadence": detach_cadence,
    "motion_window_trace": window_trace,
    "production_status_item_proof": status_item_access,
    "settings_preview_proof": {"enabled": args.settings_preview_proof,
                               "retains_window_after_close": args.settings_preview_proof,
                               "production_source_overlay": False,
                               "replaces_normal_native_gate": False},
    "detach_history_proof": {"enabled": args.detach_history_proof, "replaces_normal_native_gate": False},
    "dependency_substitutions": {name: {"before": pair[0], "after": pair[1]}
                                 for name, pair in substitutions.items()},
    "telemetry_library_sha256": hashlib.sha256(staged_telemetry.read_bytes()).hexdigest(),
    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "compiler_command": command,
    "metrics_seed": ({"sha256": hashlib.sha256((resources / "fixture-performance-seed.sqlite").read_bytes()).hexdigest(),
                      "rows": seed_rows, "scenario": "Fresh"} if metrics_seed else None),
}
(output / "fixture-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(app)
print(output / "fixture-manifest.json")
