#!/usr/bin/env python3
"""Opt-in raw-buffer gate for an already-running inert dashboard fixture.

Never opens or controls UI. Capture a completed, stable read after narrowing or
hiding. Pass the linked PerformanceSample stride from the component benchmark.
Keeps no-content heap evidence and rejects changing read phases as inconclusive.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path


def sample_allocations(heap_text):
    return [int(size) for size in re.findall(
        r"^0x[0-9a-fA-F]+: Swift\._ContiguousArrayStorage<DarkbloomTelemetry\.PerformanceSample> \((\d+) bytes\)$",
        heap_text, re.MULTILINE)]


def allocation_budget(rows, stride):
    # Allow two current-scope buffers, allocator rounding and small auxiliary
    # allocations. An obsolete 100k-row buffer fails after a ~3k-row read.
    return max(16_384, rows * stride * 2 + 65_536)


def phase(proof):
    return tuple(proof[key] for key in (
        "started", "completed", "failed", "cancelled", "empty", "cacheReleases",
        "retainedSnapshotRows", "heldReadID") if key in proof)


def process_command(pid):
    return subprocess.run(["ps", "-p", str(pid), "-o", "comm="], check=True,
                          capture_output=True, text=True, timeout=10).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--sample-stride", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.pid <= 0 or args.sample_stride <= 0:
        parser.error("Pass a valid fixture PID and positive linked sample stride.")
    if args.output.exists():
        parser.error("Preserve existing evidence; use a fresh output directory.")
    command = process_command(args.pid)
    if "/.build/" not in command or not command.endswith(
            "/Bloomy Dashboard Fixture.app/Contents/MacOS/DashboardFixture"):
        parser.error("Only a task-owned inert dashboard fixture can be inspected.")
    before = json.loads(args.proof.read_text())
    rows = before["retainedSnapshotRows"]
    if not isinstance(rows, int) or not 0 <= rows <= 100_000:
        parser.error("Read proof is outside the synthetic fixture retention cap.")
    args.output.mkdir(parents=True)
    inspection = subprocess.run([
        "heap", "-s", "--showSizes", "--noContent",
        "--addresses=Swift._ContiguousArrayStorage<DarkbloomTelemetry.PerformanceSample>",
        str(args.pid)], capture_output=True, text=True, timeout=30)
    (args.output / "heap.txt").write_text(inspection.stdout + inspection.stderr)
    after = json.loads(args.proof.read_text())
    sizes = sample_allocations(inspection.stdout)
    stable = (phase(before) == phase(after)
              and before["started"] == before["completed"] + before["failed"] + before["cancelled"]
              and not before.get("heldReadID")
              and process_command(args.pid) == command)
    valid_inspection = inspection.returncode == 0 and (
        bool(sizes) or (rows == 0 and "Active blocks in all zones" in inspection.stdout))
    budget = allocation_budget(rows, args.sample_stride)
    passed = stable and valid_inspection and sum(sizes) <= budget
    result = {
        "synthetic": True, "pid": args.pid, "stableReadPhase": stable,
        "inspectionExit": inspection.returncode, "retainedSnapshotRows": rows,
        "sampleStride": args.sample_stride, "allocationBytes": sizes,
        "allocationBudgetBytes": budget, "passed": passed,
        "before": before, "after": after,
    }
    (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in (
        "stableReadPhase", "retainedSnapshotRows", "allocationBytes",
        "allocationBudgetBytes", "passed")}))
    return 0 if passed else (1 if stable and valid_inspection else 2)


if __name__ == "__main__":
    raise SystemExit(main())
