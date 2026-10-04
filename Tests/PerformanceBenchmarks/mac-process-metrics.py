#!/usr/bin/env python3
"""Finite read-only macOS process CPU/footprint observation; no UI interaction.

CPU is a process-time delta expressed as percent of one core, not host CPU or
energy. Keep this process and its test conditions unchanged during the window.
"""
import argparse
import ctypes
import json
import os
import resource
import sys
import statistics
import time
from pathlib import Path
from metrics_read_phase import MetricsReadPhase

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pid', type=int)
parser.add_argument('--seconds', type=float, default=30)
parser.add_argument('--label')
parser.add_argument('--output', type=Path)
parser.add_argument('--visibility-proof', type=Path,
                    help='Owned fixture visibility event file; verify state throughout the window')
parser.add_argument('--visibility-mode', choices=['visible', 'minimized', 'hidden'])
parser.add_argument('--metrics-read-proof', type=Path,
                    help='Inert fixture Metrics read proof; qualify refresh or quiet work')
parser.add_argument('--metrics-read-mode', choices=['refresh', 'quiet'])
parser.add_argument('--self-check', action='store_true', help='Check Mach time conversion against getrusage using one second of owned CPU work')
args = parser.parse_args()
if not 1 <= args.seconds <= 60:
    parser.error('Use a bounded 1–60 second window')
if args.output and args.output.exists():
    parser.error('Preserve existing evidence; choose a fresh output file')
if bool(args.visibility_proof) != bool(args.visibility_mode):
    parser.error('Use --visibility-proof and --visibility-mode together')
if bool(args.metrics_read_proof) != bool(args.metrics_read_mode):
    parser.error('Use --metrics-read-proof and --metrics-read-mode together')
if args.self_check and args.metrics_read_proof:
    parser.error('Calibration cannot qualify another process Metrics read phase')

class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        'user_time', 'system_time', 'pkg_idle_wkups', 'interrupt_wkups', 'pageins',
        'wired_size', 'resident_size', 'phys_footprint', 'proc_start_abstime', 'proc_exit_abstime')]

lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
lib.proc_pid_rusage.restype = ctypes.c_int

class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]

system = ctypes.CDLL('/usr/lib/libSystem.dylib')
system.mach_timebase_info.argtypes = [ctypes.POINTER(Timebase)]
system.mach_timebase_info.restype = ctypes.c_int
timebase = Timebase()
if system.mach_timebase_info(ctypes.byref(timebase)) or not timebase.denom:
    raise RuntimeError('Cannot read Mach timebase')

def cpu_seconds(before, after):
    # Apple XNU's recount tests convert ri_user_time/system_time from Mach
    # absolute time; these fields are not nanoseconds on every architecture.
    ticks = after['user_time'] - before['user_time'] + after['system_time'] - before['system_time']
    return ticks * timebase.numer / timebase.denom / 1e9

if args.self_check:
    args.pid = os.getpid()
else:
    if args.pid is None or args.pid <= 0 or not args.label or args.output is None:
        parser.error('A positive --pid, --label and fresh --output are required')

def read():
    usage = Usage()
    if lib.proc_pid_rusage(args.pid, 0, ctypes.byref(usage)):
        raise OSError(ctypes.get_errno(), 'Cannot read the requested live process')
    return {name: getattr(usage, name) for name, _ in Usage._fields_ if name != 'uuid'}

def visibility():
    if not args.visibility_proof:
        return None
    events = json.loads(args.visibility_proof.read_text())
    if not isinstance(events, list) or not events or not isinstance(events[-1], dict):
        raise RuntimeError('Visibility evidence is missing; reject this observation')
    latest = events[-1]
    expected = {
        'visible': {'applicationHidden': False, 'miniaturized': False,
                    'windowVisible': True, 'displayEnabled': True},
        'minimized': {'applicationHidden': False, 'miniaturized': True,
                      'windowVisible': False, 'displayEnabled': False},
        'hidden': {'applicationHidden': True, 'displayEnabled': False},
    }[args.visibility_mode]
    if any(latest.get(key) is not value for key, value in expected.items()):
        raise RuntimeError(f'Fixture no longer matches {args.visibility_mode}; reject this observation')
    return {'event_count': len(events), 'latest': {key: latest.get(key) for key in
            ('phase', 'uptime', 'applicationHidden', 'miniaturized', 'windowVisible',
             'compositorVisible', 'displayEnabled')}}

if args.self_check:
    before = read()
    reference_before = resource.getrusage(resource.RUSAGE_SELF)
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        pass
    after = read()
    reference_after = resource.getrusage(resource.RUSAGE_SELF)
    observed = cpu_seconds(before, after)
    reference = reference_after.ru_utime - reference_before.ru_utime + reference_after.ru_stime - reference_before.ru_stime
    result = {'mach_timebase_numer': timebase.numer, 'mach_timebase_denom': timebase.denom,
              'converted_cpu_seconds': observed, 'getrusage_cpu_seconds': reference,
              'passed': reference > 0 and abs(observed - reference) / reference < 0.02}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    sys.exit(0 if result['passed'] else 1)

samples = []
metrics_phase = (MetricsReadPhase(json.loads(args.metrics_read_proof.read_text()), args.metrics_read_mode)
                 if args.metrics_read_proof else None)
start = time.monotonic()
initial_visibility = visibility()
first = read()
samples.append({'elapsed_seconds': 0, **first, **({'visibility': initial_visibility} if initial_visibility else {})})
while time.monotonic() - start < args.seconds:
    time.sleep(min(1, max(0, args.seconds - (time.monotonic() - start))))
    elapsed = time.monotonic() - start
    current = read()
    current_visibility = visibility()
    if metrics_phase:
        metrics_phase.observe(json.loads(args.metrics_read_proof.read_text()))
    if initial_visibility and current_visibility != initial_visibility:
        raise RuntimeError('Visibility events changed during the window; reject this observation')
    if current['proc_start_abstime'] != first['proc_start_abstime'] or current['proc_exit_abstime']:
        raise RuntimeError('Process identity changed or exited; reject this observation')
    samples.append({'elapsed_seconds': elapsed, **current,
                    **({'visibility': current_visibility} if current_visibility else {})})
last = samples[-1]
wall = last['elapsed_seconds']
cpu = cpu_seconds(first, last)
result = {'mach_timebase_numer': timebase.numer, 'mach_timebase_denom': timebase.denom,
          'pid': args.pid, 'label': args.label, 'elapsed_seconds': wall,
          'cpu_seconds': cpu, 'cpu_percent_of_one_core': 100 * cpu / wall,
          'median_resident_bytes': statistics.median(s['resident_size'] for s in samples),
          'peak_resident_bytes': max(s['resident_size'] for s in samples),
          'median_footprint_bytes': statistics.median(s['phys_footprint'] for s in samples),
          'idle_wakeups_per_second': (last['pkg_idle_wkups'] - first['pkg_idle_wkups']) / wall,
          'interrupt_wakeups_per_second': (last['interrupt_wkups'] - first['interrupt_wkups']) / wall,
          'samples': samples}
if metrics_phase:
    result['metrics_read_phase'] = metrics_phase.finish()
if args.visibility_mode:
    result['visibility_mode'] = args.visibility_mode
    result['visibility_evidence'] = initial_visibility
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'samples'}))
